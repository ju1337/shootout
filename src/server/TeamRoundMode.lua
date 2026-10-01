-- TeamRoundMode (ModuleScript, nur Server)
-- Gemeinsame Logik für Team-Modi im Stil von Rogue Company (Drop, Strikeout).
-- Ablauf eines Matches:
--   Waiting   -> warten, bis beide Teams Spieler/Bots haben (Admin kann sofort starten)
--   Select    -> Agentenwahl + Kaufphase vor jeder Runde
--   Countdown -> kurzer Countdown (Kaufen geht noch)
--   Round     -> Runde läuft
--   RoundEnd  -> Ergebnis, Geld, dann nächste Runde. RoundsToWin Rundensiege gewinnen das Match.
-- Was ein Modus anders macht, steht in seiner config:
--   DropIn  = true:  Absprung über der Map (Drop), sonst Spawn an den Team-Spawns der Map
--   Tickets = Einstellungs-Key für Respawn-Tickets pro Team (nil = kein Respawn)
--   Capture = { UnlockAfter, Radius } Eroberungspunkt in der Mitte (Strikeout)
-- Spieler-Attribute: RoundPhase, AgentLocked, SelectUntil, SelectDuration, RoundNumber,
--   TeamScore, EnemyScore, RoundsToWin, ModeText, CanFight, ObjMine/ObjEnemy (Punkt-Fortschritt)

local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)
local GameSettings = require(Shared.GameSettings)
local BuyConfig = require(Shared.BuyConfig)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local KillService = require(ServerShared.KillService)
local ProgressService = require(ServerShared.ProgressService)
local DownedService = require(ServerShared.DownedService)
local BuyService = require(ServerShared.BuyService)
local SpawnUtil = require(script.Parent.SpawnUtil)
local BotService = require(script.Parent.BotService)

local TeamRoundMode = {}

local DROP_HEIGHT = 300      -- Absprunghöhe über der Map (DropIn)
local SIDE_DISTANCE = 150    -- Abstand der Absprungseiten zur Mitte (DropIn)
local ROW_SPACING = 10       -- Abstand zwischen Spielern beim Absprung
local INTERMISSION = 5       -- Pause nach jeder Runde
local SPAWN_PROTECTION = 2   -- Schutzschild nach Boden-Spawns
local RESPAWN_TIME = 5       -- Sekunden bis zum Respawn (mit Ticket)

function TeamRoundMode.new(config)
	local mode = {}

	local MODE_ID = config.Id
	local TEAM_SIZE = config.TeamSize
	local MAP_CENTER = Modes.Get(MODE_ID).Center
	local map = config.MapName and workspace:WaitForChild("Maps"):WaitForChild(config.MapName)

	local members = {}           -- [Player] = true
	local bots = {}              -- [bot] = true
	local alive = {}             -- [Player] = true, solange der aktuelle Charakter lebt
	local pending = {}           -- [Player oder bot] = true, wartet auf Respawn (Ticket schon bezahlt)
	local tickets = {}           -- [Team] = übrige Respawns in dieser Runde
	local progress = {}          -- [Team] = Punkt-Fortschritt 0 bis 1
	local phase = "Waiting"
	local matchStarted = false
	local roundActive = false
	local spawning = false       -- true, während die Teams gespawnt werden
	local practiceRound = false  -- vom Admin gestartet, obwohl ein Team leer ist
	local forceStart = false     -- Admin: sofort starten
	local resetRequested = false -- Admin: Match zurücksetzen
	local roundWinner = nil
	local roundNumber = 0

	local function makeTeam(teamConfig)
		local team = Instance.new("Team")
		team.Name = teamConfig.Name
		team.TeamColor = teamConfig.Color
		team.AutoAssignable = false
		team.Parent = Teams
		return team
	end

	local teamA = makeTeam(config.Teams[1])
	local teamB = makeTeam(config.Teams[2])
	local scores = { [teamA] = 0, [teamB] = 0 }

	local function sideOf(team)
		return team == teamA and -1 or 1
	end

	local function otherTeam(team)
		return team == teamA and teamB or teamA
	end

	local function roundsToWin()
		return GameSettings.Get(config.RoundsSetting)
	end

	-- ---------- Zählen ----------

	local function count()
		local n = 0
		for _ in members do
			n += 1
		end
		return n
	end

	local function botCount(team)
		local n = 0
		for bot in bots do
			if not team or bot.Team == team then
				n += 1
			end
		end
		return n
	end

	-- Spieler + Bots in einem Team
	local function teamSize(team)
		return #team:GetPlayers() + botCount(team)
	end

	local function teamsReady()
		return teamSize(teamA) > 0 and teamSize(teamB) > 0
	end

	-- Noch im Spiel: lebt und liegt nicht am Boden, oder wartet auf Respawn
	local function aliveCount(team)
		local n = 0
		for player in alive do
			if player.Team == team and not DownedService.IsDowned(player.Character) then
				n += 1
			end
		end
		for bot in bots do
			if bot.Alive and bot.Team == team and not DownedService.IsDowned(bot.Model) then
				n += 1
			end
		end
		for who in pending do
			if who.Team == team then
				n += 1
			end
		end
		return n
	end

	-- ---------- Anzeige ----------

	local function announce(text)
		for player in members do
			Remotes.Announce:FireClient(player, text)
		end
	end

	local function setText(text)
		for player in members do
			player:SetAttribute("ModeText", text)
		end
	end

	local function setPhase(newPhase)
		phase = newPhase
		for player in members do
			player:SetAttribute("RoundPhase", newPhase)
		end
	end

	-- Rundenstand pro Spieler (aus Sicht seines Teams)
	local function publishScore()
		for player in members do
			local team = player.Team
			player:SetAttribute("RoundNumber", roundNumber + 1)
			player:SetAttribute("RoundsToWin", roundsToWin())
			player:SetAttribute("TeamScore", team and scores[team] or 0)
			player:SetAttribute("EnemyScore", team and scores[otherTeam(team)] or 0)
		end
	end

	local function updateInfo()
		local a, b = teamA.Name, teamB.Name
		if config.Tickets then
			setText(string.format("%s: %d Tickets · %d leben   |   %d : %d   |   %s: %d Tickets · %d leben",
				a, tickets[teamA] or 0, aliveCount(teamA), scores[teamA], scores[teamB],
				b, tickets[teamB] or 0, aliveCount(teamB)))
		else
			setText(string.format("%s: %d leben   |   %d : %d   |   %s: %d leben",
				a, aliveCount(teamA), scores[teamA], scores[teamB], b, aliveCount(teamB)))
		end
	end

	-- ---------- Teams und Auswahl ----------

	local function setLocked(value)
		for player in members do
			player:SetAttribute("AgentLocked", value)
		end
	end

	local function allLocked()
		for player in members do
			if not player:GetAttribute("AgentLocked") then
				return false
			end
		end
		return next(members) ~= nil
	end

	-- Teams ausgleichen (Spieler werden verschoben, Bots zählen mit): Unterschied höchstens 1
	local function balance()
		while math.abs(teamSize(teamA) - teamSize(teamB)) > 1 do
			local bigger = teamSize(teamA) > teamSize(teamB) and teamA or teamB
			if #bigger:GetPlayers() == 0 then
				break -- nur Bots zu viel: so lassen
			end
			local list = bigger:GetPlayers()
			list[math.random(#list)].Team = otherTeam(bigger)
		end
	end

	local function checkRoundEnd()
		if not roundActive or spawning then
			return
		end
		local aAlive, bAlive = aliveCount(teamA), aliveCount(teamB)
		if practiceRound then
			-- Übungsrunde: endet erst, wenn niemand mehr im Spiel ist
			if aAlive + bAlive > 0 then
				return
			end
		elseif aAlive > 0 and bAlive > 0 then
			return
		end
		roundActive = false
		if practiceRound then
			roundWinner = nil
		elseif aAlive > 0 then
			roundWinner = teamA
		elseif bAlive > 0 then
			roundWinner = teamB
		else
			roundWinner = nil -- beide gleichzeitig raus = unentschieden
		end
	end

	-- Charaktere und Bot-Modelle entfernen (für Agentenwahl / Warten)
	local function clearCharacters()
		for player in members do
			if player.Character then
				player.Character:Destroy()
			end
		end
		for bot in bots do
			BotService.Despawn(bot)
		end
	end

	-- ---------- Spawnen ----------

	-- Spawn-Position: Absprung über der eigenen Seite oder Team-Spawn der Map
	local function spawnCFrame(team, index, total)
		if config.DropIn then
			local offset = (index - (total + 1) / 2) * ROW_SPACING
			local position = MAP_CENTER + Vector3.new(sideOf(team) * SIDE_DISTANCE, DROP_HEIGHT, offset)
			return CFrame.lookAt(position, MAP_CENTER + Vector3.new(0, DROP_HEIGHT, offset))
		end
		return SpawnUtil.Pick(map:WaitForChild(team == teamA and "SpawnsA" or "SpawnsB"))
	end

	-- Bots starten immer am Boden ihrer Seite
	local function botCFrame(team, index)
		if config.DropIn then
			local position = MAP_CENTER + Vector3.new(sideOf(team) * (SIDE_DISTANCE + 10), 4, (index - 3) * ROW_SPACING)
			return CFrame.lookAt(position, MAP_CENTER + Vector3.new(0, 4, position.Z - MAP_CENTER.Z))
		end
		return spawnCFrame(team)
	end

	local spawnPlayer, spawnBot

	-- Tod: mit Ticket nach RESPAWN_TIME zurück, sonst bis zur nächsten Runde raus
	local function useTicket(who, respawn)
		if not (roundActive and config.Tickets and who.Team and (tickets[who.Team] or 0) > 0) then
			return
		end
		tickets[who.Team] -= 1
		pending[who] = true
		task.delay(RESPAWN_TIME, function()
			if not pending[who] then
				return -- Runde inzwischen vorbei
			end
			pending[who] = nil
			if roundActive then
				respawn()
			end
			updateInfo()
			checkRoundEnd()
		end)
	end

	function spawnPlayer(player, cframe)
		local character = SpawnUtil.Spawn(player, cframe, config.DropIn and 0 or SPAWN_PROTECTION)
		if not character or not members[player] then
			return
		end
		if config.DropIn then
			character:SetAttribute("Dropping", true) -- Client startet den Fallschirmsprung
		end
		alive[player] = true
		player:SetAttribute("CanFight", roundActive and not spawning)
		character:WaitForChild("Humanoid").Died:Connect(function()
			if alive[player] and player.Character == character then
				alive[player] = nil
				useTicket(player, function()
					if members[player] and player.Team then
						spawnPlayer(player, spawnCFrame(player.Team))
					end
				end)
				updateInfo()
				checkRoundEnd()
			end
		end)
	end

	function spawnBot(bot, cframe)
		local model
		model = BotService.SpawnModel(bot, cframe, function()
			useTicket(bot, function()
				if bots[bot] and bot.Team then
					spawnBot(bot, botCFrame(bot.Team))
					bot.CanFight = true
				end
			end)
			updateInfo()
			checkRoundEnd()
		end)
		-- Bots "kaufen" zufällig Rüstung
		if model and math.random() < 0.5 then
			model:SetAttribute("Armor", BuyConfig.ArmorAmount)
		end
	end

	local function spawnTeam(team)
		local players = team:GetPlayers()
		for i, player in players do
			spawnPlayer(player, spawnCFrame(team, i, #players))
		end
		local i = 0
		for bot in bots do
			if bot.Team == team then
				i += 1
				spawnBot(bot, botCFrame(team, i))
			end
		end
	end

	local function setCanFight(value)
		for player in members do
			player:SetAttribute("CanFight", value and alive[player] == true)
		end
		for bot in bots do
			bot.CanFight = value and bot.Alive
		end
	end

	-- ---------- Eroberungspunkt (Strikeout) ----------

	local point = config.Capture and map:WaitForChild("Objective"):WaitForChild("CapturePoint")
	local NEUTRAL = Color3.fromRGB(230, 230, 235)

	local function onPoint(position)
		local offset = position - point.Position
		return Vector3.new(offset.X, 0, offset.Z).Magnitude <= config.Capture.Radius and math.abs(offset.Y) < 10
	end

	-- Wer steht auf dem Punkt? (lebend und nicht am Boden)
	local function presence(team)
		local n = 0
		for player in alive do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if player.Team == team and root and onPoint(root.Position) and not DownedService.IsDowned(player.Character) then
				n += 1
			end
		end
		for bot in bots do
			local root = bot.Model and bot.Model:FindFirstChild("HumanoidRootPart")
			if bot.Alive and bot.Team == team and root and onPoint(root.Position) and not DownedService.IsDowned(bot.Model) then
				n += 1
			end
		end
		return n
	end

	local function publishObjective(info)
		for player in members do
			local team = player.Team
			player:SetAttribute("ObjMine", team and progress[team] or 0)
			player:SetAttribute("ObjEnemy", team and progress[otherTeam(team)] or 0)
			player:SetAttribute("ObjInfo", info)
		end
	end

	local function objectiveTick(dt, elapsed)
		local unlockIn = config.Capture.UnlockAfter - elapsed
		if unlockIn > 0 then
			point.Color = Color3.fromRGB(90, 90, 100)
			publishObjective("Punkt öffnet in " .. math.ceil(unlockIn) .. " s")
			for bot in bots do
				bot.Objective = nil
			end
			return
		end
		for bot in bots do
			bot.Objective = point.Position -- Bots laufen zum Punkt
		end
		local a, b = presence(teamA), presence(teamB)
		local captureTime = GameSettings.Get("CaptureTime")
		local info
		if a > 0 and b > 0 then
			point.Color = (math.floor(elapsed * 4) % 2 == 0) and NEUTRAL or Color3.fromRGB(255, 80, 80)
			info = "Punkt umkämpft!"
		elseif a > 0 or b > 0 then
			local team = a > 0 and teamA or teamB
			progress[team] = math.min(1, progress[team] + dt / captureTime)
			point.Color = team.TeamColor.Color
			info = "Team " .. team.Name .. " nimmt den Punkt ein"
			if progress[team] >= 1 and roundActive then
				roundWinner = team
				roundActive = false
				announce("Team " .. team.Name .. " hat den Punkt eingenommen!")
			end
		else
			point.Color = NEUTRAL
			info = "Punkt offen"
		end
		publishObjective(info)
	end

	local function clearObjective()
		progress[teamA], progress[teamB] = 0, 0
		if point then
			point.Color = NEUTRAL
		end
		for player in members do
			player:SetAttribute("ObjMine", nil)
			player:SetAttribute("ObjEnemy", nil)
			player:SetAttribute("ObjInfo", nil)
		end
		for bot in bots do
			bot.Objective = nil
		end
	end

	-- ---------- Ablauf ----------

	local function giveTeamXP(team, rewardKey, reason)
		for player in members do
			if player.Team == team then
				ProgressService.AddXP(player, ProgressService.ActiveAgent(player), AgentConfig.XPRewards[rewardKey], reason)
			end
		end
	end

	local function resetMatch()
		scores[teamA], scores[teamB] = 0, 0
		roundNumber = 0
		matchStarted = false
		for player in members do
			KillService.ResetPlayer(player)
		end
		clearCharacters()
		setLocked(false)
		publishScore()
	end

	-- Agentenwahl vor jeder Runde: endet nach Ablauf der Zeit, wenn alle bestätigt haben
	-- oder wenn der Admin startet. Danach ist jede Wahl automatisch bestätigt.
	local function agentSelect(duration)
		clearCharacters()
		publishScore()
		local endAt = os.clock() + duration
		for player in members do
			player:SetAttribute("SelectUntil", workspace:GetServerTimeNow() + duration)
			player:SetAttribute("SelectDuration", duration)
		end
		setPhase("Select")
		while os.clock() < endAt and not forceStart and count() > 0 do
			setText(Modes.Get(MODE_ID).Name .. " · Agentenwahl · noch " .. math.ceil(endAt - os.clock()) .. " s")
			if allLocked() then
				task.wait(1.5) -- alle bereit: kurz zeigen, dann los
				break
			end
			task.wait(0.25)
		end
		setLocked(true)
	end

	local function playRound()
		-- Countdown
		setPhase("Countdown")
		for seconds = GameSettings.Get("Countdown"), 1, -1 do
			setText(Modes.Get(MODE_ID).Name .. " · Runde " .. roundNumber + 1 .. " · Start in " .. seconds .. " s")
			task.wait(1)
		end
		if count() == 0 then
			return
		end

		practiceRound = not teamsReady()
		roundNumber += 1
		announce(practiceRound and "Übungsrunde" or ("Runde " .. roundNumber))
		alive = {}
		pending = {}
		roundWinner = nil
		local ticketCount = config.Tickets and GameSettings.Get(config.Tickets) or 0
		tickets[teamA], tickets[teamB] = ticketCount, ticketCount
		clearObjective()

		roundActive = true
		spawning = true
		setPhase("Round")
		spawnTeam(teamA)
		spawnTeam(teamB)
		spawning = false
		setCanFight(true)
		updateInfo()
		checkRoundEnd() -- falls schon beim Spawnen jemand gestorben/gegangen ist

		local roundStart = os.clock()
		while roundActive do
			task.wait(0.25)
			if config.Capture and roundActive then
				objectiveTick(0.25, os.clock() - roundStart)
			end
		end
		pending = {}
		setCanFight(false)
		setPhase("RoundEnd")
		setLocked(false) -- nächste Agentenwahl ist wieder frei
		for player in members do
			BuyService.EndRound(player) -- Rüstung und Extra-Gadget verfallen
		end

		if resetRequested then
			resetRequested = false
			announce("Match wurde zurückgesetzt")
			task.wait(3)
			clearObjective()
			resetMatch()
			return
		end

		if roundWinner then
			scores[roundWinner] += 1
			announce("Team " .. roundWinner.Name .. " gewinnt die Runde!")
			giveTeamXP(roundWinner, "RoundWin", "Rundensieg")
		else
			announce(practiceRound and "Übungsrunde vorbei" or "Unentschieden!")
		end
		-- Geld für die nächste Kaufphase: Sieger mehr, Verlierer etwas weniger
		for player in members do
			if roundWinner and player.Team == roundWinner then
				BuyService.AddMoney(player, BuyConfig.Rewards.RoundWin, "Rundensieg")
			else
				BuyService.AddMoney(player, BuyConfig.Rewards.RoundLoss, "Runde verloren")
			end
		end
		updateInfo()
		publishScore()
		task.wait(INTERMISSION)
		clearObjective()

		if roundWinner and scores[roundWinner] >= roundsToWin() then
			announce("Team " .. roundWinner.Name .. " gewinnt das Match!")
			giveTeamXP(roundWinner, "MatchWin", "Matchsieg")
			task.wait(INTERMISSION)
			resetMatch()
		elseif practiceRound then
			resetMatch() -- nach einer Übungsrunde wieder warten
		end
	end

	-- Match-Schleife, läuft dauerhaft im Hintergrund
	local function matchLoop()
		while true do
			balance()
			if not matchStarted then
				setPhase("Waiting")
				if not teamsReady() and not (forceStart and count() > 0) then
					setText(Modes.Get(MODE_ID).Name .. " · Warte auf Spieler in beiden Teams ("
						.. count() + botCount() .. "/" .. TEAM_SIZE * 2 .. ")")
					task.wait(1)
					continue
				end
				matchStarted = true
				roundNumber = 0
				for player in members do
					BuyService.StartMatch(player) -- Startgeld, Käufe zurücksetzen
				end
			end

			if count() == 0 then
				resetMatch()
				continue
			end
			if not teamsReady() and not forceStart then
				setText(Modes.Get(MODE_ID).Name .. " · Warte auf Spieler im anderen Team...")
				task.wait(1)
				continue
			end
			-- Agentenwahl (Admin-Start überspringt sie)
			if not forceStart then
				agentSelect(roundNumber == 0 and GameSettings.Get("SelectTime") or GameSettings.Get("RoundSelectTime"))
				if count() == 0 then
					continue
				end
			end
			forceStart = false
			playRound()
		end
	end

	-- ---------- Admin ----------

	function mode.AdminStart()
		if roundActive then
			return "Runde läuft bereits."
		end
		if count() == 0 then
			return "Niemand ist in diesem Modus."
		end
		forceStart = true
		return Modes.Get(MODE_ID).Name .. " startet sofort."
	end

	function mode.AdminEndRound()
		if not roundActive then
			return "Keine Runde aktiv."
		end
		roundActive = false -- endet als Unentschieden
		roundWinner = nil
		return "Runde beendet (ohne Sieger)."
	end

	function mode.AdminResetMatch()
		if roundActive then
			resetRequested = true
			roundActive = false
			roundWinner = nil
		else
			resetMatch()
		end
		return "Match zurückgesetzt."
	end

	function mode.AdminSwitchTeam(player)
		if not members[player] then
			return "Spieler ist nicht in diesem Modus."
		end
		if roundActive then
			return "Teamwechsel nur zwischen den Runden."
		end
		player.Team = otherTeam(player.Team)
		return player.Name .. " ist jetzt in Team " .. player.Team.Name .. "."
	end

	-- ---------- Modus-Schnittstelle ----------

	function mode.Init()
		-- Niedergeschlagen/wiederbelebt: Anzeige und Rundenende neu prüfen
		DownedService.Changed:Connect(function()
			if roundActive then
				updateInfo()
				checkRoundEnd()
			end
		end)
		task.spawn(matchLoop)
	end

	function mode.CanJoin()
		if count() + botCount() >= TEAM_SIZE * 2 then
			return false, Modes.Get(MODE_ID).Name .. " ist voll (" .. TEAM_SIZE * 2 .. "/" .. TEAM_SIZE * 2 .. ")."
		end
		return true
	end

	function mode.AddPlayer(player)
		members[player] = true
		player.Team = teamSize(teamA) <= teamSize(teamB) and teamA or teamB
		player:SetAttribute("RoundPhase", phase)
		player:SetAttribute("AgentLocked", false)
		publishScore()
		if matchStarted then
			BuyService.StartMatch(player) -- später dazugekommen: Startgeld
		end
		-- Ohne Charakter: Agentenwahl-Bildschirm bzw. Zuschauen bis zur nächsten Runde
		if player.Character then
			player.Character:Destroy()
		end
		if roundActive then
			updateInfo()
		end
	end

	function mode.RemovePlayer(player)
		members[player] = nil
		alive[player] = nil
		pending[player] = nil
		player.Team = nil
		for _, attribute in { "RoundPhase", "AgentLocked", "SelectUntil", "SelectDuration", "RoundNumber", "TeamScore",
			"EnemyScore", "RoundsToWin", "ObjMine", "ObjEnemy", "ObjInfo" } do
			player:SetAttribute(attribute, nil)
		end
		BuyService.Clear(player)
		if roundActive then
			updateInfo()
			checkRoundEnd()
		end
	end

	-- teamName: Name eines der beiden Teams oder nil (kleineres Team)
	function mode.AddBot(bot, teamName)
		if count() + botCount() >= TEAM_SIZE * 2 then
			return false, Modes.Get(MODE_ID).Name .. " ist voll (" .. TEAM_SIZE * 2 .. "/" .. TEAM_SIZE * 2 .. ")."
		end
		local team = teamName == teamA.Name and teamA or teamName == teamB.Name and teamB
			or (teamSize(teamA) <= teamSize(teamB) and teamA or teamB)
		if teamSize(team) >= TEAM_SIZE then
			return false, "Team " .. team.Name .. " ist voll."
		end
		bots[bot] = true
		BotService.SetTeam(bot, team)
		if roundActive then
			updateInfo() -- steigt in der nächsten Runde ein
		end
		return true
	end

	function mode.RemoveBot(bot)
		bots[bot] = nil
		pending[bot] = nil
		BotService.Despawn(bot)
		if roundActive then
			updateInfo()
			checkRoundEnd()
		end
	end

	-- Namen der beiden Teams (für Admin-Panel)
	function mode.TeamNames()
		return teamA.Name, teamB.Name
	end

	return mode
end

return TeamRoundMode

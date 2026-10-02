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
--   WingsuitStart = Höhe: zu Rundenbeginn Fallschirmsprung über dem eigenen Team-Spawn
--     (wie bei Rogue Company); Respawns während der Runde landen direkt am Boden
--   Tickets = Einstellungs-Key für Respawn-Tickets pro Team (nil = kein Respawn)
--   Capture = { UnlockAfter, Radius } Eroberungspunkt in der Mitte (Strikeout)
--   Maps    = Liste von Map-Namen (Workspace.Maps.<Name>); pro Match wird zufällig eine gewählt
--             (Map-Rotation wie bei RC). Ohne Maps gilt MapName.
--   RoundTime = Einstellungs-Key für die Rundenzeit in Sekunden (nil = ohne Zeitlimit)
--   Ranked = true: am Match-Ende Rangpunkte (nur wenn in beiden Teams echte Spieler sind)
--   Objective = function(api) -> Ziel-Objekt mit eigenen Regeln (z.B. Bombe in Demolition).
--     Mögliche Funktionen: RoundStart(roundNumber), Tick(dt, elapsed), RoundEnd(), SpawnFolder(team),
--     KeepsRoundAlive(aAlive, bAlive), TimeFrozen(), TimeOutWinner(), RoundInfo(),
--     Attackers() (angreifendes Team), Clock() (eigene Uhr statt der Rundenzeit, z.B. Bomben-Timer)
-- Spieler-Attribute: RoundPhase, AgentLocked, SelectUntil, SelectDuration, RoundNumber,
--   TeamScore, EnemyScore, RoundsToWin, ModeText, CanFight, ObjMine/ObjEnemy (Punkt-Fortschritt),
--   fürs HUD: RoundClock (Sekunden), ClockAlert (Uhr des Ziels läuft), Overtime, TeamTickets/EnemyTickets,
--   Attacking (true/false bei Angriff/Verteidigung), MapId (Ordnername der Map)

local Teams = game:GetService("Teams")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)
local GameSettings = require(Shared.GameSettings)
local BuyConfig = require(Shared.BuyConfig)
local RankConfig = require(Shared.RankConfig)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local KillService = require(ServerShared.KillService)
local ProgressService = require(ServerShared.ProgressService)
local DownedService = require(ServerShared.DownedService)
local BuyService = require(ServerShared.BuyService)
local LeaderboardService = require(ServerShared.LeaderboardService)
local SpawnUtil = require(script.Parent.SpawnUtil)
local PartyService = require(script.Parent.PartyService)
local BotService = require(script.Parent.BotService)

local TeamRoundMode = {}

local DROP_HEIGHT = 300      -- Absprunghöhe über der Map (DropIn)
local SIDE_DISTANCE = 150    -- Abstand der Absprungseiten zur Mitte (DropIn)
local ROW_SPACING = 10       -- Abstand zwischen Spielern beim Absprung
local INTERMISSION = 5       -- Pause nach jeder Runde
local OVERTIME_MAX = 30      -- Strikeout: Overtime dauert höchstens so lange (Sekunden)
local VOTE_TIME = 10         -- Map-Abstimmung vor dem Match (Sekunden)
local BOT_FILL_DELAY = 10    -- so lange wird auf echte Spieler gewartet, dann füllen Bots auf
local SPAWN_PROTECTION = 2   -- Schutzschild nach Boden-Spawns
local RESPAWN_TIME = 5       -- Sekunden bis zum Respawn (mit Ticket)

function TeamRoundMode.new(config)
	local mode = {}

	local MODE_ID = config.Id
	local TEAM_SIZE = config.TeamSize
	local MAP_CENTER = Modes.Get(MODE_ID).Center
	-- Map-Rotation: mögliche Maps dieses Modus, aktuelle Map wechselt pro Match
	local mapNames = config.Maps or (config.MapName and { config.MapName }) or {}
	local mapsFolder = workspace:WaitForChild("Maps")
	local map = mapNames[1] and mapsFolder:WaitForChild(mapNames[1])

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
	local timeLeft = nil         -- Restzeit der Runde (nur mit RoundTime)
	local overtime = false       -- Strikeout: Zeit um, aber das zurückliegende Team steht auf dem Punkt
	local roundKills = {}        -- [Player] = Kills in dieser Runde (für ACE)
	local clutches = {}          -- [Team] = { Player, Enemies }: letzter Überlebender gegen mehrere
	local objective = nil        -- eigenes Ziel des Modus (config.Objective), wird unten erzeugt

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

	-- Auffüll-Bots (Einstellung AutoFillBots): zählen für Plätze nicht als "echte" Belegung
	local function autoBotCount(team)
		local n = 0
		for bot in bots do
			if bot.AutoFill and (not team or bot.Team == team) then
				n += 1
			end
		end
		return n
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

	-- Uhr oben im HUD: Rundenzeit oder die eigene Uhr des Ziels (z.B. gelegte Bombe)
	local function currentClock()
		local own = objective and objective.Clock and objective.Clock()
		if own then
			return own, true
		end
		return timeLeft, false
	end

	-- Zahlen fürs HUD pro Spieler (aus Sicht seines Teams)
	local function publishMatchData()
		local clock, alert = currentClock()
		local attackers = objective and objective.Attackers and objective.Attackers()
		for player in members do
			local team = player.Team
			local attacking = nil
			if attackers and team then
				attacking = team == attackers
			end
			player:SetAttribute("RoundClock", clock and math.ceil(clock) or nil)
			player:SetAttribute("ClockAlert", alert or nil)
			player:SetAttribute("Overtime", overtime or nil)
			player:SetAttribute("TeamTickets", config.Tickets and team and (tickets[team] or 0) or nil)
			player:SetAttribute("EnemyTickets", config.Tickets and team and (tickets[otherTeam(team)] or 0) or nil)
			player:SetAttribute("Attacking", attacking)
		end
	end

	local function updateInfo()
		publishMatchData()
		local a, b = teamA.Name, teamB.Name
		local seconds = timeLeft and math.ceil(timeLeft)
		local clock = overtime and "   ·   OVERTIME"
			or seconds and string.format("   ·   %d:%02d", seconds // 60, seconds % 60) or ""
		if config.Tickets then
			setText(string.format("%s: %d Tickets · %d leben   |   %d : %d   |   %s: %d Tickets · %d leben%s",
				a, tickets[teamA] or 0, aliveCount(teamA), scores[teamA], scores[teamB],
				b, tickets[teamB] or 0, aliveCount(teamB), clock))
		else
			local extra = objective and objective.RoundInfo and objective.RoundInfo() or ""
			setText(string.format("%s: %d leben   |   %d : %d   |   %s: %d leben%s%s",
				a, aliveCount(teamA), scores[teamA], scores[teamB], b, aliveCount(teamB), extra, clock))
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
			-- Bevorzugt Spieler ohne Squad verschieben, damit Squads zusammenbleiben
			local list = bigger:GetPlayers()
			local solo = {}
			for _, p in list do
				if not PartyService.Leader(p) then
					table.insert(solo, p)
				end
			end
			local pool = #solo > 0 and solo or list
			pool[math.random(#pool)].Team = otherTeam(bigger)
		end
	end

	-- Clutch: ein echter Spieler steht allein gegen mindestens 2 Gegner (einmal pro Runde und Team)
	local function detectClutch(aAlive, bAlive)
		if config.Tickets or practiceRound then
			return
		end
		for _, pair in { { teamA, aAlive, bAlive }, { teamB, bAlive, aAlive } } do
			local team, mine, theirs = pair[1], pair[2], pair[3]
			if mine == 1 and theirs >= 2 and not clutches[team] then
				for player in alive do
					if player.Team == team and not DownedService.IsDowned(player.Character) then
						clutches[team] = { Player = player, Enemies = theirs }
						Remotes.Announce:FireClient(player, "CLUTCH: 1 gegen " .. theirs .. "!")
					end
				end
			end
		end
	end

	local function checkRoundEnd()
		if not roundActive or spawning then
			return
		end
		local aAlive, bAlive = aliveCount(teamA), aliveCount(teamB)
		detectClutch(aAlive, bAlive)
		if practiceRound then
			-- Übungsrunde: endet erst, wenn niemand mehr im Spiel ist
			if aAlive + bAlive > 0 then
				return
			end
		elseif aAlive > 0 and bAlive > 0 then
			return
		elseif objective and objective.KeepsRoundAlive and objective.KeepsRoundAlive(aAlive, bAlive) then
			return -- z.B. Bombe gelegt: Verteidiger müssen noch entschärfen
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
		local folder = objective and objective.SpawnFolder and objective.SpawnFolder(team)
			or (team == teamA and "SpawnsA" or "SpawnsB")
		return SpawnUtil.Pick(map:WaitForChild(folder))
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

	function spawnPlayer(player, cframe, dropping)
		dropping = dropping or config.DropIn
		local character = SpawnUtil.Spawn(player, cframe, dropping and 0 or SPAWN_PROTECTION)
		if not character or not members[player] then
			return
		end
		if dropping then
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
			local cframe = spawnCFrame(team, i, #players)
			if config.WingsuitStart then
				-- Rundenbeginn: über dem Team-Spawn abspringen
				cframe += Vector3.new(0, config.WingsuitStart, 0)
			end
			spawnPlayer(player, cframe, config.WingsuitStart ~= nil)
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
	-- Part-Attribute fürs HUD: Locked (Punkt noch zu), Contested (beide Teams drauf)

	local point = config.Capture and map:WaitForChild("Objective"):WaitForChild("CapturePoint")

	-- Neue Map fürs nächste Match auslosen (nur zwischen Matches aufrufen)
	-- name = bestimmte Map (z.B. aus der Abstimmung), sonst zufällig aus der Rotation
	local function chooseMap(name)
		if #mapNames == 0 then
			return
		end
		map = mapsFolder:WaitForChild(name or mapNames[math.random(#mapNames)])
		if config.Capture then
			point = map:WaitForChild("Objective"):WaitForChild("CapturePoint")
		end
	end

	-- Name und Mitte der aktuellen Map an einen Spieler (Agentenwahl, Kameraflug)
	local function publishMap(player)
		if map then
			player:SetAttribute("MapName", map:GetAttribute("DisplayName") or map.Name)
			player:SetAttribute("MapId", map.Name)
			player:SetAttribute("MapCenter", map:GetAttribute("Center"))
		end
	end

	-- ---------- Map-Abstimmung vor dem Match ----------
	-- Bis zu 3 Maps aus der Rotation, VOTE_TIME Sekunden. Spieler-Attribute: MapVoteOptions (JSON
	-- { {Id, Name} }), MapVoteEnd (Serverzeit), MapVoteCounts (JSON { n1, n2, n3 }), MapVoteMine
	local voteOptions = nil  -- { { Id, Name } } während der Abstimmung
	local votes = {}         -- [Player] = Nummer der Option
	local voteEnd = 0        -- Serverzeit, zu der die Abstimmung endet

	local function voteCounts()
		local counts = {}
		for i in voteOptions do
			counts[i] = 0
		end
		for player, index in votes do
			if members[player] then
				counts[index] += 1
			end
		end
		return counts
	end

	local function publishVote(player)
		if voteOptions then
			player:SetAttribute("MapVoteOptions", HttpService:JSONEncode(voteOptions))
			player:SetAttribute("MapVoteEnd", voteEnd)
			player:SetAttribute("MapVoteCounts", HttpService:JSONEncode(voteCounts()))
			player:SetAttribute("MapVoteMine", votes[player])
		else
			for _, attribute in { "MapVoteOptions", "MapVoteEnd", "MapVoteCounts", "MapVoteMine" } do
				player:SetAttribute(attribute, nil)
			end
		end
	end

	local function mapVote()
		if #mapNames < 2 then
			chooseMap()
			return
		end
		local pool = table.clone(mapNames)
		voteOptions = {}
		while #voteOptions < 3 and #pool > 0 do
			local name = table.remove(pool, math.random(#pool))
			local folder = mapsFolder:WaitForChild(name)
			table.insert(voteOptions, { Id = name, Name = folder:GetAttribute("DisplayName") or name })
		end
		votes = {}
		voteEnd = workspace:GetServerTimeNow() + VOTE_TIME
		setPhase("MapVote")
		for player in members do
			publishVote(player)
		end
		while workspace:GetServerTimeNow() < voteEnd and count() > 0 do
			setText(Modes.Get(MODE_ID).Name .. " · Map-Abstimmung · noch "
				.. math.ceil(voteEnd - workspace:GetServerTimeNow()) .. " s")
			-- Alle haben abgestimmt: nicht unnötig warten
			local voted = 0
			for player in members do
				if votes[player] then
					voted += 1
				end
			end
			if voted >= count() and voteEnd - workspace:GetServerTimeNow() > 1.5 then
				voteEnd = workspace:GetServerTimeNow() + 1.5
				for player in members do
					publishVote(player)
				end
			end
			task.wait(0.25)
		end
		-- Meiste Stimmen gewinnt, bei Gleichstand zufällig
		local counts = voteCounts()
		local best, winners = -1, {}
		for i, n in counts do
			if n > best then
				best, winners = n, { i }
			elseif n == best then
				table.insert(winners, i)
			end
		end
		local chosen = voteOptions[winners[math.random(#winners)]]
		voteOptions = nil
		votes = {}
		for player in members do
			publishVote(player)
		end
		chooseMap(chosen.Id)
		announce("Map: " .. chosen.Name)
	end
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

	-- Punkt wie bei Rogue Company: 3 s allein draufstehen = einnehmen. Solange ein Team den Punkt
	-- hält, verliert der Gegner alle TicketDrain Sekunden ein Ticket. Umkämpft = kein Fortschritt.
	local owner = nil
	local drainTimer = 0

	local function objectiveTick(dt, elapsed)
		local unlockIn = config.Capture.UnlockAfter - elapsed
		point:SetAttribute("Locked", unlockIn > 0 or nil)
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
		point:SetAttribute("Contested", (a > 0 and b > 0) or nil)
		local captureTime = GameSettings.Get("CaptureTime")
		local info
		if a > 0 and b > 0 then
			point.Color = (math.floor(elapsed * 4) % 2 == 0) and NEUTRAL or Color3.fromRGB(255, 80, 80)
			info = "Punkt umkämpft!"
		elseif a > 0 or b > 0 then
			local team = a > 0 and teamA or teamB
			if team ~= owner then
				progress[team] = math.min(1, progress[team] + dt / captureTime)
				info = "Team " .. team.Name .. " nimmt den Punkt ein"
				if progress[team] >= 1 then
					owner = team
					drainTimer = 0
					progress[otherTeam(team)] = 0
					announce("Team " .. team.Name .. " hat den Punkt eingenommen!")
				end
			end
		else
			-- Niemand drauf: angefangenes Einnehmen läuft langsam zurück
			for _, team in { teamA, teamB } do
				if team ~= owner then
					progress[team] = math.max(0, progress[team] - dt / (captureTime * 2))
				end
			end
		end

		-- Halter zieht dem Gegner regelmäßig Tickets ab
		if owner then
			progress[owner] = 1
			point.Color = owner.TeamColor.Color
			local enemy = otherTeam(owner)
			local interval = GameSettings.Get("TicketDrain")
			drainTimer += dt
			if drainTimer >= interval then
				drainTimer = 0
				if (tickets[enemy] or 0) > 0 then
					tickets[enemy] -= 1
					updateInfo()
					checkRoundEnd()
				end
			end
			info = info or ("Punkt gehört Team " .. owner.Name .. " · Team " .. enemy.Name
				.. " verliert ein Ticket in " .. math.ceil(interval - drainTimer) .. " s")
		elseif not info then
			point.Color = NEUTRAL
			info = "Punkt offen – 3 s draufstehen zum Einnehmen"
		end
		publishObjective(info)
	end

	local function clearObjective()
		progress[teamA], progress[teamB] = 0, 0
		owner = nil
		drainTimer = 0
		if point then
			point.Color = NEUTRAL
			point:SetAttribute("Locked", nil)
			point:SetAttribute("Contested", nil)
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

	-- Match-Ende: Ergebnis, MVP (meiste Kills, dann Schaden) und eigene Werte an alle Spieler
	local function sendSummary(winner, rankTexts, eloChanges)
		local mvp, best = nil, -1
		for player in members do
			local score = KillService.GetKills(player) * 1000 + (player:GetAttribute("Damage") or 0)
			if score > best then
				mvp, best = player, score
			end
		end
		for player in members do
			Remotes.MatchSummary:FireClient(player, {
				Won = winner ~= nil and player.Team == winner,
				Winner = winner and winner.Name or nil,
				Mode = Modes.Get(MODE_ID).Name,
				Score = (scores[player.Team] or 0) .. " : " .. (scores[otherTeam(player.Team)] or 0),
				Mvp = mvp and mvp.Name or nil,
				MvpKills = mvp and KillService.GetKills(mvp) or 0,
				Kills = KillService.GetKills(player),
				Deaths = player:GetAttribute("Deaths") or 0,
				Damage = player:GetAttribute("Damage") or 0,
				Rank = rankTexts and rankTexts[player] or nil,
				Map = player:GetAttribute("MapName"),
			})
			local won = nil -- nil = Unentschieden
			if winner then
				won = player.Team == winner
			end
			ProgressService.AddHistory(player, {
				Mode = Modes.Get(MODE_ID).Name,
				Map = player:GetAttribute("MapName"),
				Won = won,
				Score = (scores[player.Team] or 0) .. " : " .. (scores[otherTeam(player.Team)] or 0),
				Kills = KillService.GetKills(player),
				Deaths = player:GetAttribute("Deaths") or 0,
				Elo = eloChanges and eloChanges[player] or nil,
			})
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
		-- Countdown (Clients zeigen ihn groß in der Bildschirmmitte)
		setPhase("Countdown")
		for player in members do
			player:SetAttribute("CountdownEnd", workspace:GetServerTimeNow() + GameSettings.Get("Countdown"))
		end
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
		roundKills = {}
		clutches = {}
		roundWinner = nil
		local ticketCount = config.Tickets and GameSettings.Get(config.Tickets) or 0
		tickets[teamA], tickets[teamB] = ticketCount, ticketCount
		clearObjective()

		roundActive = true
		spawning = true
		setPhase("Round")
		if objective and objective.RoundStart then
			objective.RoundStart(roundNumber) -- vor dem Spawnen (legt z.B. Angreifer fest)
		end
		spawnTeam(teamA)
		spawnTeam(teamB)
		spawning = false
		setCanFight(true)
		if objective and objective.AfterSpawn then
			objective.AfterSpawn()
		end
		updateInfo()
		checkRoundEnd() -- falls schon beim Spawnen jemand gestorben/gegangen ist

		local roundStart = os.clock()
		local roundTime = config.RoundTime and GameSettings.Get(config.RoundTime)
		local lastSecond = -1
		while roundActive do
			task.wait(0.25)
			local elapsed = os.clock() - roundStart
			if config.Capture and roundActive then
				objectiveTick(0.25, elapsed)
			end
			if objective and objective.Tick and roundActive then
				objective.Tick(0.25, elapsed)
			end
			-- Rundenzeit steht still, solange das Ziel es will (z.B. Bombe gelegt)
			if objective and objective.TimeFrozen and objective.TimeFrozen() then
				roundStart += 0.25
			end
			if roundTime and roundActive then
				timeLeft = math.max(0, roundTime - elapsed)
				-- Zeit abgelaufen: mehr Tickets gewinnt, dann mehr Überlebende
				if timeLeft <= 0 then
					local ta, tb = tickets[teamA] or 0, tickets[teamB] or 0
					local aa, ab = aliveCount(teamA), aliveCount(teamB)
					local winner
					if objective and objective.TimeOutWinner then
						winner = objective.TimeOutWinner()
					elseif ta ~= tb then
						winner = ta > tb and teamA or teamB
					elseif aa ~= ab then
						winner = aa > ab and teamA or teamB
					end
					-- Overtime (wie bei RC): solange das zurückliegende Team auf dem Punkt steht, geht es
					-- weiter (höchstens OVERTIME_MAX Sekunden). Bei Gleichstand reicht irgendwer auf dem Punkt.
					local contesting = false
					if config.Capture and elapsed - roundTime < OVERTIME_MAX then
						if winner then
							contesting = presence(otherTeam(winner)) > 0
						else
							contesting = presence(teamA) + presence(teamB) > 0
						end
					end
					if contesting then
						if not overtime then
							overtime = true
							announce("OVERTIME!")
							updateInfo()
						end
					else
						roundWinner = winner
						roundActive = false
						announce(overtime and "Overtime vorbei!" or "Zeit abgelaufen!")
					end
				end
			end
			-- Uhr im HUD einmal pro Sekunde (Rundenzeit oder z.B. Bomben-Timer)
			local clock = currentClock()
			local second = clock and math.ceil(clock) or -1
			if second ~= lastSecond and roundActive then
				lastSecond = second
				updateInfo()
			end
		end
		timeLeft = nil
		overtime = false
		pending = {}
		if objective and objective.RoundEnd then
			objective.RoundEnd()
		end
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

		-- ACE: ein Spieler hat das komplette Gegnerteam (mind. 3) allein ausgeschaltet
		if not config.Tickets then
			for player, kills in roundKills do
				local enemies = player.Team and teamSize(otherTeam(player.Team)) or 0
				if members[player] and enemies >= 3 and kills >= enemies then
					announce("★ ACE! " .. player.Name .. " hat das ganze Team ausgeschaltet!")
					ProgressService.AddXP(player, ProgressService.ActiveAgent(player), 300, "ACE")
				end
			end
		end
		-- Clutch gewonnen?
		local clutch = roundWinner and clutches[roundWinner]
		if clutch and members[clutch.Player] then
			announce("★ CLUTCH! " .. clutch.Player.Name .. " gewinnt 1 gegen " .. clutch.Enemies .. "!")
			ProgressService.AddXP(clutch.Player, ProgressService.ActiveAgent(clutch.Player), 100 * clutch.Enemies, "Clutch")
			ProgressService.AddStat(clutch.Player, "Clutches", 1)
		end
		if roundWinner then
			scores[roundWinner] += 1
			announce("Team " .. roundWinner.Name .. " gewinnt die Runde!")
			giveTeamXP(roundWinner, "RoundWin", "Rundensieg")
		else
			announce(practiceRound and "Übungsrunde vorbei" or "Unentschieden!")
		end
		-- Aufträge: gespielte und gewonnene Runden
		for player in members do
			ProgressService.QuestEvent(player, "RoundPlayed", 1)
			if roundWinner and player.Team == roundWinner then
				ProgressService.QuestEvent(player, "RoundWin", 1)
				ProgressService.AddStat(player, "RoundsWon", 1)
			end
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
			-- Statistik: Match gespielt, gewonnen/verloren
			for player in members do
				ProgressService.AddStat(player, "Matches", 1)
				ProgressService.AddStat(player, player.Team == roundWinner and "Wins" or "Losses", 1)
			end
			-- Ranked: ELO nach Team-Durchschnitt, nur wenn beide Teams echte Spieler hatten
			local rankTexts, eloChanges = {}, {}
			if config.Ranked and #teamA:GetPlayers() > 0 and #teamB:GetPlayers() > 0 then
				local function averageElo(team)
					local sum, n = 0, 0
					for _, player in team:GetPlayers() do
						sum += ProgressService.GetElo(player)
						n += 1
					end
					return n > 0 and sum / n or RankConfig.StartElo
				end
				local averages = { [teamA] = averageElo(teamA), [teamB] = averageElo(teamB) }
				-- MVP bekommt einen kleinen Bonus
				local mvp, best = nil, -1
				for player in members do
					local score = KillService.GetKills(player) * 1000 + (player:GetAttribute("Damage") or 0)
					if score > best then
						mvp, best = player, score
					end
				end
				for player in members do
					local won = player.Team == roundWinner
					local before = ProgressService.GetElo(player)
					local change = RankConfig.Change(won, averages[player.Team], averages[otherTeam(player.Team)],
						ProgressService.GetRankedMatches(player), player == mvp)
					local after = ProgressService.ApplyRanked(player, change, won)
					LeaderboardService.Submit(player, after)
					local oldRank, newRank = RankConfig.Get(before), RankConfig.Get(after)
					local text = (change >= 0 and "+" or "−") .. math.abs(change) .. " ELO  ·  " .. newRank.Display
						.. "  (" .. after .. ")"
					if newRank.Display ~= oldRank.Display then
						text ..= change > 0 and "  ·  AUFSTIEG!" or "  ·  Abstieg"
					end
					if ProgressService.GetRankedMatches(player) <= RankConfig.PlacementMatches then
						text ..= "  ·  Platzierung " .. ProgressService.GetRankedMatches(player) .. "/" .. RankConfig.PlacementMatches
					end
					rankTexts[player] = text
					eloChanges[player] = change
				end
			end
			sendSummary(roundWinner, rankTexts, eloChanges)
			task.wait(INTERMISSION)
			resetMatch()
		elseif practiceRound then
			resetMatch() -- nach einer Übungsrunde wieder warten
		end
	end

	-- Freie Plätze beider Teams mit Bots auffüllen (nur wenn echte Spieler da sind)
	local function fillWithBots()
		if GameSettings.Get("AutoFillBots") < 1 or count() == 0 then
			return
		end
		for _, team in { teamA, teamB } do
			while teamSize(team) < TEAM_SIZE do
				local bot = BotService.Create(MODE_ID)
				bot.AutoFill = true
				if not mode.AddBot(bot, team.Name) then
					BotService.Destroy(bot)
					break
				end
			end
		end
	end

	-- Auffüll-Bots entfernen (z.B. wenn keine Spieler mehr da sind)
	local function removeAutoBots(team, limit)
		local removed = 0
		for bot in bots do
			if bot.AutoFill and (not team or bot.Team == team) and (not limit or removed < limit) then
				mode.RemoveBot(bot)
				BotService.Destroy(bot)
				removed += 1
			end
		end
		return removed
	end

	-- Match-Schleife, läuft dauerhaft im Hintergrund
	local function matchLoop()
		local waitingSince = nil
		while true do
			if count() == 0 and autoBotCount() > 0 then
				removeAutoBots() -- niemand mehr da: Auffüll-Bots weg
			end
			-- Zwischen den Runden: zu viele Auffüll-Bots (weil Spieler dazukamen) entfernen
			if not roundActive then
				for _, team in { teamA, teamB } do
					local over = teamSize(team) - TEAM_SIZE
					if over > 0 then
						removeAutoBots(team, over)
					end
				end
			end
			-- Nach kurzer Wartezeit mit Bots auffüllen, damit man auch allein spielen kann
			if count() > 0 and not roundActive then
				waitingSince = waitingSince or os.clock()
				if os.clock() - waitingSince >= BOT_FILL_DELAY then
					fillWithBots()
				end
			else
				waitingSince = nil
			end
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
				-- Map-Rotation: Abstimmung (Admin-Start nimmt eine zufällige Map)
				if forceStart then
					chooseMap()
				else
					mapVote()
				end
				for player in members do
					publishMap(player)
				end
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

	-- ---------- Schnittstelle für eigene Ziele (config.Objective) ----------

	-- Alle Teilnehmer eines Teams: { Player = ..., Bot = ..., Model = ... }
	local function participants(team)
		local list = {}
		for player in members do
			if player.Team == team then
				table.insert(list, { Player = player, Model = player.Character })
			end
		end
		for bot in bots do
			if bot.Team == team then
				table.insert(list, { Bot = bot, Model = bot.Model })
			end
		end
		return list
	end

	local api = {
		TeamA = teamA,
		TeamB = teamB,
		GetMap = function()
			return map
		end,
		OtherTeam = otherTeam,
		Announce = announce,
		UpdateInfo = updateInfo,
		Participants = participants,
		RoundsToWin = roundsToWin,
		IsRoundActive = function()
			return roundActive
		end,
		-- Lebt und liegt nicht am Boden?
		IsActive = function(model)
			local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
			return humanoid ~= nil and humanoid.Health > 0 and not DownedService.IsDowned(model)
		end,
		-- Runde sofort beenden (team = Sieger oder nil)
		EndRound = function(team, message)
			if not roundActive then
				return
			end
			roundWinner = team
			roundActive = false
			if message then
				announce(message)
			end
		end,
		-- Statuszeile unter der Modus-Info (wie beim Punkt in Strikeout)
		SetInfo = function(text)
			for player in members do
				player:SetAttribute("ObjInfo", text)
			end
		end,
	}
	objective = config.Objective and config.Objective(api)

	-- ---------- Modus-Schnittstelle ----------

	function mode.Init()
		-- Map-Abstimmung
		Remotes.MapVote.OnServerEvent:Connect(function(player, index)
			if voteOptions and members[player] and type(index) == "number" and voteOptions[index] then
				votes[player] = index
				for member in members do
					publishVote(member)
				end
			end
		end)
		-- Kills pro Runde zählen (für ACE)
		KillService.KillCounted:Connect(function(killer)
			if roundActive and members[killer] then
				roundKills[killer] = (roundKills[killer] or 0) + 1
			end
		end)
		-- Niedergeschlagen/wiederbelebt: Anzeige und Rundenende neu prüfen
		DownedService.Changed:Connect(function()
			if roundActive then
				updateInfo()
				checkRoundEnd()
			end
		end)
		task.spawn(matchLoop)
	end

	function mode.CanJoin(player)
		-- Auffüll-Bots machen Platz und zählen hier nicht
		-- Ranked erst ab Spielerlevel config.RequiredLevel (Summe der Agenten-Level)
		if config.RequiredLevel and player and AgentConfig.PlayerLevel(player) < config.RequiredLevel then
			return false, "Ranked ab Spielerlevel " .. config.RequiredLevel .. " (du: " .. AgentConfig.PlayerLevel(player)
				.. "). Spiele erst andere Modi."
		end
		if count() + botCount() - autoBotCount() >= TEAM_SIZE * 2 then
			return false, Modes.Get(MODE_ID).Name .. " ist voll (" .. TEAM_SIZE * 2 .. "/" .. TEAM_SIZE * 2 .. ")."
		end
		return true
	end

	function mode.AddPlayer(player)
		-- Voll mit Auffüll-Bots? Einen Bot Platz machen lassen (während einer Runde erst danach)
		if not roundActive and count() + botCount() >= TEAM_SIZE * 2 and autoBotCount() > 0 then
			local team = autoBotCount(teamA) >= autoBotCount(teamB) and teamA or teamB
			removeAutoBots(team, 1)
		end
		members[player] = true
		player.Team = teamSize(teamA) <= teamSize(teamB) and teamA or teamB
		-- Squad: ins Team des Anführers bzw. eines Squad-Mitglieds, wenn dort Platz ist
		for _, mate in PartyService.Members(player) do
			if mate ~= player and members[mate] and mate.Team and teamSize(mate.Team) < TEAM_SIZE then
				player.Team = mate.Team
				break
			end
		end
		player:SetAttribute("RoundPhase", phase)
		player:SetAttribute("AgentLocked", false)
		publishMap(player)
		publishVote(player)
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
		votes[player] = nil
		members[player] = nil
		alive[player] = nil
		pending[player] = nil
		player.Team = nil
		for _, attribute in { "RoundPhase", "AgentLocked", "SelectUntil", "SelectDuration", "RoundNumber", "TeamScore",
			"EnemyScore", "RoundsToWin", "ObjMine", "ObjEnemy", "ObjInfo", "MapName", "MapId", "MapCenter", "CountdownEnd",
			"MapVoteOptions", "MapVoteEnd", "MapVoteCounts", "MapVoteMine", "RoundClock", "ClockAlert", "Overtime",
			"TeamTickets", "EnemyTickets", "Attacking" } do
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

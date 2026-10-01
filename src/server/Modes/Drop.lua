-- Drop (ModuleScript, nur Server)
-- 5v5 im Stil von Rogue Company. Ablauf eines Matches:
--   Waiting  -> warten, bis beide Teams Spieler haben (Admin kann sofort starten)
--   Select   -> Agentenwahl mit Timer (Bildschirm beim Client)
--   Countdown-> kurzer Countdown vor jeder Runde
--   Round    -> Absprung über der Map, kein Respawn, letztes Team mit Überlebenden gewinnt
--   RoundEnd -> Ergebnis, dann nächste Runde. Wer zuerst RoundsToWin Runden hat, gewinnt das Match.
-- Spieler-Attribute: DropPhase (aktuelle Phase), AgentLocked (Agent bestätigt)
-- ReplicatedStorage: DropSelectUntil/DropSelectDuration (Timer), DropRound, DropScoreRot, DropScoreBlau

local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)
local GameSettings = require(Shared.GameSettings)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local KillService = require(ServerShared.KillService)
local ProgressService = require(ServerShared.ProgressService)
local SpawnUtil = require(script.Parent.Parent.SpawnUtil)
local BotService = require(script.Parent.Parent.BotService)
local DownedService = require(ServerShared.DownedService)

local Drop = {}

local TEAM_SIZE = 5
local MAP_CENTER = Modes.Get("Drop").Center
local DROP_HEIGHT = 300      -- Absprunghöhe über der Map
local SIDE_DISTANCE = 150    -- Abstand der Absprungseiten zur Mitte
local ROW_SPACING = 10       -- Abstand zwischen Spielern beim Absprung
local INTERMISSION = 5       -- Pause nach jeder Runde

local members = {}
local bots = {}              -- [bot] = true (Bots in diesem Modus, gehören zu einem Team)
local alive = {}             -- [Player] = true, solange in dieser Runde am Leben
local phase = "Waiting"
local matchStarted = false
local roundActive = false
local spawning = false       -- true, während die Teams abgesetzt werden
local practiceRound = false  -- vom Admin gestartet, obwohl ein Team leer ist
local forceStart = false     -- Admin: sofort starten
local resetRequested = false -- Admin: Match zurücksetzen
local roundWinner = nil
local roundNumber = 0

local function makeTeam(name, color)
	local team = Instance.new("Team")
	team.Name = name
	team.TeamColor = color
	team.AutoAssignable = false
	team.Parent = Teams
	return team
end

local red = makeTeam("Rot", BrickColor.new("Bright red"))
local blue = makeTeam("Blau", BrickColor.new("Bright blue"))
local scores = { [red] = 0, [blue] = 0 }

local function sideOf(team)
	return team == red and -1 or 1
end

local function otherTeam(team)
	return team == red and blue or red
end

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
	return teamSize(red) > 0 and teamSize(blue) > 0
end

-- Lebend und nicht am Boden (ein Team, das komplett am Boden liegt, hat verloren)
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
	return n
end

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
		player:SetAttribute("DropPhase", newPhase)
	end
end

-- Rundenstand für den Agentenwahl-Bildschirm
local function publishScore()
	ReplicatedStorage:SetAttribute("DropRound", roundNumber + 1)
	ReplicatedStorage:SetAttribute("DropScoreRot", scores[red])
	ReplicatedStorage:SetAttribute("DropScoreBlau", scores[blue])
end

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

local function updateInfo()
	setText(string.format("Rot: %d leben   |   %d : %d   |   Blau: %d leben",
		aliveCount(red), scores[red], scores[blue], aliveCount(blue)))
end

-- Teams ausgleichen (Spieler werden verschoben, Bots zählen mit): Unterschied höchstens 1
local function balance()
	while math.abs(teamSize(red) - teamSize(blue)) > 1 do
		local bigger = teamSize(red) > teamSize(blue) and red or blue
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
	local redAlive, blueAlive = aliveCount(red), aliveCount(blue)
	if practiceRound then
		-- Übungsrunde: endet erst, wenn alle tot sind
		if redAlive + blueAlive > 0 then
			return
		end
	elseif redAlive > 0 and blueAlive > 0 then
		return
	end
	roundActive = false
	if practiceRound then
		roundWinner = nil
	elseif redAlive > 0 then
		roundWinner = red
	elseif blueAlive > 0 then
		roundWinner = blue
	else
		roundWinner = nil -- beide gleichzeitig tot = unentschieden
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

-- Team hoch über seiner Seite der Map absetzen
local function dropTeam(team)
	local players = team:GetPlayers()
	for i, player in players do
		local offset = (i - (#players + 1) / 2) * ROW_SPACING
		local position = MAP_CENTER + Vector3.new(sideOf(team) * SIDE_DISTANCE, DROP_HEIGHT, offset)
		local lookAt = MAP_CENTER + Vector3.new(0, DROP_HEIGHT, offset)
		local character = SpawnUtil.Spawn(player, CFrame.lookAt(position, lookAt))
		if character and members[player] then
			character:SetAttribute("Dropping", true) -- Client startet den Fallschirmsprung
			alive[player] = true
			character:WaitForChild("Humanoid").Died:Connect(function()
				if alive[player] then
					alive[player] = nil
					updateInfo()
					checkRoundEnd()
				end
			end)
		end
	end
end

-- Bots des Teams starten am Boden ihrer Seite
local function spawnTeamBots(team)
	local i = 0
	for bot in bots do
		if bot.Team == team then
			i += 1
			local position = MAP_CENTER + Vector3.new(sideOf(team) * (SIDE_DISTANCE + 10), 4, (i - 3) * ROW_SPACING)
			local lookAt = MAP_CENTER + Vector3.new(0, 4, position.Z - MAP_CENTER.Z)
			BotService.SpawnModel(bot, CFrame.lookAt(position, lookAt), function()
				updateInfo()
				checkRoundEnd()
			end)
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

local function giveTeamXP(team, rewardKey, reason)
	for player in members do
		if player.Team == team then
			ProgressService.AddXP(player, ProgressService.ActiveAgent(player), AgentConfig.XPRewards[rewardKey], reason)
		end
	end
end

local function resetMatch()
	scores[red], scores[blue] = 0, 0
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
	ReplicatedStorage:SetAttribute("DropSelectUntil", workspace:GetServerTimeNow() + duration)
	ReplicatedStorage:SetAttribute("DropSelectDuration", duration)
	setPhase("Select")
	while os.clock() < endAt and not forceStart and count() > 0 do
		setText("Drop · Agentenwahl · noch " .. math.ceil(endAt - os.clock()) .. " s")
		if allLocked() then
			task.wait(1.5) -- alle bereit: kurz zeigen, dann los
			break
		end
		task.wait(0.25)
	end
	setLocked(true)
end

local function playRound()
	-- Countdown vor dem Absprung
	setPhase("Countdown")
	for seconds = GameSettings.Get("Countdown"), 1, -1 do
		setText("Drop · Runde " .. roundNumber + 1 .. " · Absprung in " .. seconds .. " s")
		task.wait(1)
	end
	if count() == 0 then
		return
	end

	practiceRound = not teamsReady()
	roundNumber += 1
	announce(practiceRound and "Übungsrunde" or ("Runde " .. roundNumber))
	alive = {}
	roundWinner = nil
	roundActive = true
	spawning = true
	setPhase("Round")
	dropTeam(red)
	dropTeam(blue)
	spawnTeamBots(red)
	spawnTeamBots(blue)
	spawning = false
	setCanFight(true)
	updateInfo()
	checkRoundEnd() -- falls schon beim Spawnen jemand gestorben/gegangen ist

	while roundActive do
		task.wait(0.25)
	end
	setCanFight(false)
	setPhase("RoundEnd")
	setLocked(false) -- nächste Agentenwahl ist wieder frei

	if resetRequested then
		resetRequested = false
		announce("Match wurde zurückgesetzt")
		task.wait(3)
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
	updateInfo()
	publishScore()
	task.wait(INTERMISSION)

	if roundWinner and scores[roundWinner] >= GameSettings.Get("RoundsToWin") then
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
				setText("Drop · Warte auf Spieler in beiden Teams (" .. count() .. "/" .. TEAM_SIZE * 2 .. ")")
				task.wait(1)
				continue
			end
			matchStarted = true
			roundNumber = 0
		end

		if count() == 0 then
			resetMatch()
			continue
		end
		if not teamsReady() and not forceStart then
			-- Ein Team ist leer geworden: warten
			setText("Drop · Warte auf Spieler im anderen Team...")
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

function Drop.AdminStart()
	if roundActive then
		return "Runde läuft bereits."
	end
	if count() == 0 then
		return "Niemand ist im Drop-Modus."
	end
	forceStart = true
	return "Drop startet sofort."
end

function Drop.AdminEndRound()
	if not roundActive then
		return "Keine Runde aktiv."
	end
	roundActive = false -- endet als Unentschieden
	roundWinner = nil
	return "Runde beendet (ohne Sieger)."
end

function Drop.AdminResetMatch()
	if roundActive then
		resetRequested = true
		roundActive = false
		roundWinner = nil
	else
		resetMatch()
	end
	return "Match zurückgesetzt."
end

function Drop.AdminSwitchTeam(player)
	if not members[player] then
		return "Spieler ist nicht im Drop-Modus."
	end
	if roundActive then
		return "Teamwechsel nur zwischen den Runden."
	end
	player.Team = otherTeam(player.Team)
	return player.Name .. " ist jetzt in Team " .. player.Team.Name .. "."
end

-- ---------- Modus-Schnittstelle ----------

function Drop.Init()
	-- Niedergeschlagen/wiederbelebt: Anzeige und Rundenende neu prüfen
	DownedService.Changed:Connect(function()
		if roundActive then
			updateInfo()
			checkRoundEnd()
		end
	end)
	task.spawn(matchLoop)
end

function Drop.CanJoin()
	if count() + botCount() >= TEAM_SIZE * 2 then
		return false, "Drop ist voll (" .. TEAM_SIZE * 2 .. "/" .. TEAM_SIZE * 2 .. ")."
	end
	return true
end

function Drop.AddPlayer(player)
	members[player] = true
	player.Team = teamSize(red) <= teamSize(blue) and red or blue
	player:SetAttribute("DropPhase", phase)
	player:SetAttribute("AgentLocked", false)
	-- Ohne Charakter: Agentenwahl-Bildschirm bzw. Zuschauen bis zur nächsten Runde
	if player.Character then
		player.Character:Destroy()
	end
	if roundActive then
		updateInfo()
	end
end

-- ---------- Bots ----------

-- teamName: "Rot", "Blau" oder nil (kleineres Team)
function Drop.AddBot(bot, teamName)
	if count() + botCount() >= TEAM_SIZE * 2 then
		return false, "Drop ist voll (" .. TEAM_SIZE * 2 .. "/" .. TEAM_SIZE * 2 .. ")."
	end
	local team = teamName == "Rot" and red or teamName == "Blau" and blue
		or (teamSize(red) <= teamSize(blue) and red or blue)
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

function Drop.RemoveBot(bot)
	bots[bot] = nil
	BotService.Despawn(bot)
	if roundActive then
		updateInfo()
		checkRoundEnd()
	end
end

function Drop.RemovePlayer(player)
	members[player] = nil
	alive[player] = nil
	player.Team = nil
	player:SetAttribute("DropPhase", nil)
	player:SetAttribute("AgentLocked", nil)
	if roundActive then
		updateInfo()
		checkRoundEnd()
	end
end

return Drop

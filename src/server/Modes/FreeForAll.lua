-- FreeForAll (ModuleScript, nur Server)
-- Jeder gegen jeden: kurzer Respawn, wer zuerst KillsToWin Kills hat, gewinnt die Runde.
-- Map-Rotation: nach jeder Runde (Top 3 + Zusammenfassung) stimmen alle über die nächste Map ab (MAPS).
-- Spieler-Attribute: MapId, MapName, MapCenter (aktuelle Map), während der Abstimmung RoundPhase = "MapVote"
-- und MapVoteOptions/MapVoteEnd/MapVoteCounts/MapVoteMine (wie in den Team-Modi, Client: MapVote).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local GameSettings = require(Shared.GameSettings)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local KillService = require(ServerShared.KillService)
local ProgressService = require(ServerShared.ProgressService)
local RewardService = require(ServerShared.RewardService)
local LeaderboardService = require(ServerShared.LeaderboardService)
local RankConfig = require(Shared.RankConfig)
local SpawnUtil = require(script.Parent.Parent.SpawnUtil)
local BotService = require(script.Parent.Parent.BotService)

local FreeForAll = {}

local MODE_ID = "FreeForAll"
local INTERMISSION = 10      -- Top-3-Bühne und Zusammenfassung nach der Runde (Sekunden), danach die Abstimmung
local VOTE_TIME = 8          -- Map-Abstimmung (endet früher, wenn alle gewählt haben)
local MAPS = { "FreeForAll", "Favela", "Orbit" } -- Altstadt, Favela, Orbit (Ordner in Workspace.Maps)
local SPAWN_PROTECTION = 2   -- Sekunden Schutzschild nach dem Spawn
local MAX_PLAYERS = 12

local members = {}
local bots = {} -- [bot] = true
local roundOver = false
local mapsFolder = workspace:WaitForChild("Maps")
local map = mapsFolder:WaitForChild(MAPS[1])

-- Aktuelle Map an einen Spieler (Minimap, Lichtstimmung, Kamera)
local function publishMap(player)
	player:SetAttribute("MapName", map:GetAttribute("DisplayName") or map.Name)
	player:SetAttribute("MapId", map.Name)
	player:SetAttribute("MapCenter", map:GetAttribute("Center"))
end

-- ---------- Map-Abstimmung nach jeder Runde ----------
local voteOptions = nil -- { { Id, Name } } während der Abstimmung
local votes = {}        -- [Player] = Nummer der Option
local voteEnd = 0

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
		player:SetAttribute("RoundPhase", "MapVote")
		player:SetAttribute("MapVoteOptions", HttpService:JSONEncode(voteOptions))
		player:SetAttribute("MapVoteEnd", voteEnd)
		player:SetAttribute("MapVoteCounts", HttpService:JSONEncode(voteCounts()))
		player:SetAttribute("MapVoteMine", votes[player])
	else
		for _, attribute in { "RoundPhase", "MapVoteOptions", "MapVoteEnd", "MapVoteCounts", "MapVoteMine" } do
			player:SetAttribute(attribute, nil)
		end
	end
end

local function mapVote()
	local options = {}
	for _, name in MAPS do
		local folder = mapsFolder:FindFirstChild(name)
		if folder then
			table.insert(options, { Id = name, Name = folder:GetAttribute("DisplayName") or name })
		end
	end
	if #options < 2 or next(members) == nil then
		return
	end
	voteOptions = options
	votes = {}
	voteEnd = workspace:GetServerTimeNow() + VOTE_TIME
	for player in members do
		publishVote(player)
	end
	while workspace:GetServerTimeNow() < voteEnd and next(members) ~= nil do
		local voted, total = 0, 0
		for player in members do
			total += 1
			if votes[player] then
				voted += 1
			end
		end
		-- alle haben gewählt: nicht unnötig warten
		if voted >= total and voteEnd - workspace:GetServerTimeNow() > 1.5 then
			voteEnd = workspace:GetServerTimeNow() + 1.5
			for player in members do
				publishVote(player)
			end
		end
		task.wait(0.25)
	end
	-- meiste Stimmen gewinnt, bei Gleichstand zufällig
	local best, winners = -1, {}
	for i, n in voteCounts() do
		if n > best then
			best, winners = n, { i }
		elseif n == best then
			table.insert(winners, i)
		end
	end
	local chosen = voteOptions[winners[math.random(#winners)]]
	voteOptions = nil
	votes = {}
	map = mapsFolder:WaitForChild(chosen.Id)
	for player in members do
		publishVote(player)
		publishMap(player)
	end
	for player in members do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Map gewählt", Title = chosen.Name, Sub = "Free-for-All",
			Style = "Info" })
	end
end

-- Spieler + Bots
local function count()
	local n = 0
	for _ in members do
		n += 1
	end
	for _ in bots do
		n += 1
	end
	return n
end

-- Meldung im CoD-Stil (Notifications) an alle Teilnehmer
local function notify(kind, data)
	for player in members do
		Remotes.Notify:FireClient(player, kind, data)
	end
end

-- Text oben mittig: Ziel und aktueller Führender
local function updateInfo()
	local leader, best = nil, 0
	for player in members do
		local kills = KillService.GetKills(player)
		if kills > best then
			leader, best = player, kills
		end
	end
	local text = "Free-for-All · " .. GameSettings.Get("KillsToWin") .. " Kills gewinnen"
	if leader then
		text ..= " · Führung: " .. leader.Name .. " (" .. best .. ")"
	end
	for player in members do
		player:SetAttribute("ModeText", text)
	end
end

local function spawnPlayer(player)
	if not members[player] then
		return
	end
	local character = SpawnUtil.Spawn(player, SpawnUtil.Pick(map.Spawns), SPAWN_PROTECTION)
	if not character then
		return
	end
	player:SetAttribute("CanFight", not roundOver)
	character:WaitForChild("Humanoid").Died:Connect(function()
		task.delay(GameSettings.Get("FFARespawnTime"), function()
			if members[player] and player.Character == character then
				spawnPlayer(player)
			end
		end)
	end)
end

local function spawnBot(bot)
	if not bots[bot] then
		return
	end
	local model
	model = BotService.SpawnModel(bot, SpawnUtil.Pick(map.Spawns), function()
		task.delay(GameSettings.Get("FFARespawnTime"), function()
			if bot.Model == model then -- nicht schon anders neu gespawnt
				spawnBot(bot)
			end
		end)
	end)
	bot.CanFight = not roundOver
end

-- Runde beenden: Sieger anzeigen (oder keiner), kurz warten, alles zurücksetzen
local function finishRound(winner)
	if roundOver then
		return
	end
	roundOver = true
	for player in members do
		player:SetAttribute("CanFight", false)
	end
	for bot in bots do
		bot.CanFight = false
	end
	-- ELO nach Platzierung (Kills): Erster gewinnt am meisten, Letzter verliert am meisten.
	-- Bots zählen als Gegner mit Start-ELO; ohne andere echte Spieler gibt es die halbe Änderung.
	local ranking = {}
	for player in members do
		table.insert(ranking, { Player = player, Name = player.Name, Kills = KillService.GetKills(player),
			UserId = player.UserId, Agent = ProgressService.ActiveAgent(player), Title = player:GetAttribute("Title") })
	end
	for bot in bots do
		table.insert(ranking, { Name = bot.Name, Kills = bot.Info and bot.Info:GetAttribute("Kills") or 0,
			Agent = bot.Agent, Bot = true })
	end
	table.sort(ranking, function(a, b)
		return a.Kills > b.Kills
	end)
	local eloChanges = {}
	if #ranking >= 2 then
		local realPlayers = 0
		for _ in members do
			realPlayers += 1
		end
		for place, entry in ranking do
			local player = entry.Player
			if player then
				local score = 1 - (place - 1) / (#ranking - 1) -- 1 = Erster, 0 = Letzter
				local k = ProgressService.GetRankedMatches(player) < RankConfig.PlacementMatches and RankConfig.PlacementK
					or RankConfig.K
				local change = k * (score - 0.5)
				change = score >= 0.5 and math.max(change, RankConfig.MinChange) or math.min(change, -RankConfig.MinChange)
				if realPlayers < 2 then
					change /= 2
				end
				change = math.floor(change + 0.5)
				ProgressService.ApplyRanked(player, change, place == 1)
				LeaderboardService.Submit(player)
				eloChanges[player] = change
			end
		end
	end

	-- Statistik: jede FFA-Runde zählt als Match
	for player in members do
		ProgressService.AddStat(player, "Matches", 1)
		ProgressService.AddStat(player, player == winner and "Wins" or "Losses", 1)
		ProgressService.QuestEvent(player, "MatchPlayed", 1)
		if player == winner then
			ProgressService.QuestEvent(player, "MatchWin", 1)
		end
		ProgressService.AddHistory(player, {
			Mode = "Free-for-All",
			Map = map:GetAttribute("DisplayName") or "Altstadt",
			Won = player == winner,
			Score = winner and ("Sieger: " .. winner.Name) or "–",
			Kills = KillService.GetKills(player),
			Deaths = player:GetAttribute("Deaths") or 0,
			Elo = eloChanges[player],
		})
	end
	-- Sieger, Platz und ELO zeigt die Zusammenfassung unten (Top-3-Bühne und Übersicht)
	if winner then
		ProgressService.AddXP(winner, ProgressService.ActiveAgent(winner), AgentConfig.XPRewards.FFAWin, "Rundensieg")
		ProgressService.QuestEvent(winner, "RoundWin", 1)
	end
	-- Zusammenfassung mit Top-3-Bühne, Platz, MVP und Belohnungs-Übersicht (XP, Münzen, Level, ELO)
	local podium = {}
	for i = 1, math.min(3, #ranking) do
		local entry = ranking[i]
		podium[i] = { Name = entry.Name, UserId = entry.UserId, Agent = entry.Agent, Kills = entry.Kills, Bot = entry.Bot,
			Title = entry.Title }
	end
	local top = ranking[1]
	for place, entry in ranking do
		local player = entry.Player
		if player then
			RewardService.Check(player) -- Meilensteine sofort, damit sie in der Übersicht stehen
			Remotes.MatchSummary:FireClient(player, {
				Won = place == 1,
				Winner = top and top.Name or nil,
				Mode = "Free-for-All",
				Place = place,
				Players = #ranking,
				Mvp = top and top.Name or nil,
				MvpKills = top and top.Kills or 0,
				Kills = KillService.GetKills(player),
				Deaths = player:GetAttribute("Deaths") or 0,
				Damage = player:GetAttribute("Damage") or 0,
				Map = map:GetAttribute("DisplayName"),
				Progress = ProgressService.TakeLedger(player),
				Top = podium,
				ShowTime = INTERMISSION,
			})
		end
	end
	task.wait(INTERMISSION)
	mapVote() -- nächste Map wählen (danach spawnen alle dort)

	roundOver = false
	KillService.NewRound(MODE_ID) -- ERSTES BLUT wieder frei
	for player in members do
		KillService.ResetPlayer(player)
		task.spawn(spawnPlayer, player)
	end
	for bot in bots do
		task.spawn(spawnBot, bot)
	end
	notify("Banner", { Caption = "Free-for-All", Title = "Neue Runde", Sub = GameSettings.Get("KillsToWin") .. " Kills gewinnen",
		Style = "Info" })
	updateInfo()
end

-- Auffüll-Bots: Mit echten Spielern, aber wenig Gegnern füllen Bots auf FILL_TO Teilnehmer auf
local FILL_TO = 6

function FreeForAll.Init()
	-- Stimmen für die Map-Abstimmung (nur FFA-Teilnehmer, die Team-Modi prüfen ihre eigenen)
	Remotes.MapVote.OnServerEvent:Connect(function(player, index)
		if voteOptions and members[player] and type(index) == "number" and voteOptions[index] then
			votes[player] = index
			for member in members do
				publishVote(member)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			local players = 0
			for _ in members do
				players += 1
			end
			local auto = {}
			for bot in bots do
				if bot.AutoFill then
					table.insert(auto, bot)
				end
			end
			if players == 0 or GameSettings.Get("AutoFillBots") < 1 then
				-- niemand da (oder ausgeschaltet): Auffüll-Bots weg
				for _, bot in auto do
					FreeForAll.RemoveBot(bot)
					BotService.Destroy(bot)
				end
			elseif count() < FILL_TO then
				for _ = 1, FILL_TO - count() do
					local bot = BotService.Create("FreeForAll")
					bot.AutoFill = true
					FreeForAll.AddBot(bot)
				end
			elseif count() > FILL_TO and #auto > 0 then
				-- echte Spieler dazugekommen: Bots machen Platz
				for i = 1, math.min(#auto, count() - FILL_TO) do
					FreeForAll.RemoveBot(auto[i])
					BotService.Destroy(auto[i])
				end
			end
		end
	end)
end

-- Echte Spieler und freie Plätze (für das Matchmaking über mehrere Server)
function FreeForAll.Slots()
	local players, fixed = 0, 0
	for _ in members do
		players += 1
	end
	for bot in bots do
		if not bot.AutoFill then
			fixed += 1 -- Auffüll-Bots machen Platz, vom Admin gesetzte nicht
		end
	end
	return players, math.max(0, MAX_PLAYERS - players - fixed)
end

function FreeForAll.CanJoin()
	if count() >= MAX_PLAYERS then
		return false, "Free-for-All ist voll (" .. MAX_PLAYERS .. "/" .. MAX_PLAYERS .. ")."
	end
	return true
end

function FreeForAll.AddPlayer(player)
	members[player] = true
	publishMap(player)
	if voteOptions then
		publishVote(player) -- mitten in der Abstimmung dazugekommen: gleich mitwählen
	end
	spawnPlayer(player)
	updateInfo()
end

function FreeForAll.RemovePlayer(player)
	members[player] = nil
	votes[player] = nil
	for _, attribute in { "RoundPhase", "MapVoteOptions", "MapVoteEnd", "MapVoteCounts", "MapVoteMine", "MapId", "MapName",
		"MapCenter" } do
		player:SetAttribute(attribute, nil)
	end
	updateInfo()
end

function FreeForAll.OnKill(killer, _, kills)
	updateInfo()
	if kills >= GameSettings.Get("KillsToWin") then
		finishRound(killer)
	end
end

-- ---------- Bots ----------

function FreeForAll.AddBot(bot)
	if count() >= MAX_PLAYERS then
		return false, "Free-for-All ist voll."
	end
	bots[bot] = true
	BotService.SetTeam(bot, nil)
	spawnBot(bot)
	return true
end

function FreeForAll.RemoveBot(bot)
	bots[bot] = nil
end

function FreeForAll.AdminEndRound()
	if roundOver then
		return "Runde ist bereits vorbei."
	end
	task.spawn(finishRound, nil)
	return "Free-for-All-Runde beendet."
end

return FreeForAll

-- FreeForAll (ModuleScript, nur Server)
-- Jeder gegen jeden: kurzer Respawn, wer zuerst KillsToWin Kills hat, gewinnt die Runde.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

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

local INTERMISSION = 9       -- Pause zwischen Runden in Sekunden (solange läuft die Zusammenfassung)
local SPAWN_PROTECTION = 2   -- Sekunden Schutzschild nach dem Spawn
local MAX_PLAYERS = 12

local members = {}
local bots = {} -- [bot] = true
local roundOver = false
local map = workspace:WaitForChild("Maps"):WaitForChild("FreeForAll")

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

local function announce(text)
	for player in members do
		Remotes.Announce:FireClient(player, text)
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
		table.insert(ranking, { Player = player, Name = player.Name, Kills = KillService.GetKills(player) })
	end
	for bot in bots do
		table.insert(ranking, { Name = bot.Name, Kills = bot.Info and bot.Info:GetAttribute("Kills") or 0 })
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
				local after = ProgressService.ApplyRanked(player, change, place == 1)
				LeaderboardService.Submit(player)
				eloChanges[player] = change
				Remotes.Announce:FireClient(player, "Platz " .. place .. "  ·  " .. (change >= 0 and "+" or "−")
					.. math.abs(change) .. " ELO  (" .. after .. ")")
			end
		end
	end

	-- Statistik: jede FFA-Runde zählt als Match
	for player in members do
		ProgressService.AddStat(player, "Matches", 1)
		ProgressService.AddStat(player, player == winner and "Wins" or "Losses", 1)
		ProgressService.AddHistory(player, {
			Mode = "Free-for-All",
			Map = "Raffinerie",
			Won = player == winner,
			Score = winner and ("Sieger: " .. winner.Name) or "–",
			Kills = KillService.GetKills(player),
			Deaths = player:GetAttribute("Deaths") or 0,
			Elo = eloChanges[player],
		})
	end
	if winner then
		announce(winner.Name .. " gewinnt die Runde!")
		ProgressService.AddXP(winner, ProgressService.ActiveAgent(winner), AgentConfig.XPRewards.FFAWin, "Rundensieg")
		ProgressService.QuestEvent(winner, "RoundWin", 1)
	else
		announce("Runde beendet")
	end
	-- Zusammenfassung mit Platz, MVP und Belohnungs-Übersicht (XP, Münzen, Level, ELO)
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
				Map = player:GetAttribute("MapName"),
				Progress = ProgressService.TakeLedger(player),
				ShowTime = INTERMISSION,
			})
		end
	end
	task.wait(INTERMISSION)

	roundOver = false
	for player in members do
		KillService.ResetPlayer(player)
		task.spawn(spawnPlayer, player)
	end
	for bot in bots do
		task.spawn(spawnBot, bot)
	end
	announce("Neue Runde!")
	updateInfo()
end

-- Auffüll-Bots: Mit echten Spielern, aber wenig Gegnern füllen Bots auf FILL_TO Teilnehmer auf
local FILL_TO = 6

function FreeForAll.Init()
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

function FreeForAll.CanJoin()
	if count() >= MAX_PLAYERS then
		return false, "Free-for-All ist voll (" .. MAX_PLAYERS .. "/" .. MAX_PLAYERS .. ")."
	end
	return true
end

function FreeForAll.AddPlayer(player)
	members[player] = true
	spawnPlayer(player)
	updateInfo()
end

function FreeForAll.RemovePlayer(player)
	members[player] = nil
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

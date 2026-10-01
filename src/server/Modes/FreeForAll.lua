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
local SpawnUtil = require(script.Parent.Parent.SpawnUtil)
local BotService = require(script.Parent.Parent.BotService)

local FreeForAll = {}

local INTERMISSION = 6       -- Pause zwischen Runden in Sekunden
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
	if winner then
		announce(winner.Name .. " gewinnt die Runde!")
		ProgressService.AddXP(winner, ProgressService.ActiveAgent(winner), AgentConfig.XPRewards.FFAWin, "Rundensieg")
	else
		announce("Runde beendet")
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

function FreeForAll.Init() end

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

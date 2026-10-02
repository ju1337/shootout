-- RewardService (ModuleScript, nur Server)
-- Vergibt die Belohnungen aus RewardConfig:
--   Killserien (Kills ohne zu sterben), Spielerlevel-Meilensteine, Prestige-Skins, Rang-Meilensteine pro Saison.
-- Prüft automatisch, sobald sich Level (AccountXP), Prestige oder ELO eines Spielers ändern.
-- Abgeholte Meilensteine stehen im Profil (profile.Rewards.Claimed) und als JSON im Spieler-Attribut
-- "RewardsClaimed" (für das Belohnungs-Fenster). Jede Belohnung zeigt der Client als Popup (Remotes.Reward).

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local RewardConfig = require(Shared.RewardConfig)
local LevelConfig = require(Shared.LevelConfig)
local RankConfig = require(Shared.RankConfig)
local Cosmetics = require(Shared.Cosmetics)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local ProgressService = require(ServerShared.ProgressService)
local KillService = require(ServerShared.KillService)

local RewardService = {}

local streaks = {} -- [Player] = Kills seit dem letzten Tod
local streakAtDeath = {} -- [Player] = Killserie im Moment des letzten Todes (für "Serie beendet")
local lastKiller = {} -- [Player] = wer ihn zuletzt erledigt hat (für "Rache")

local function claimedOf(profile)
	profile.Rewards = profile.Rewards or {}
	profile.Rewards.Claimed = profile.Rewards.Claimed or {}
	return profile.Rewards.Claimed
end

local function publish(player, profile)
	player:SetAttribute("RewardsClaimed", HttpService:JSONEncode(claimedOf(profile)))
end

-- Belohnung geben und als Popup melden. reward = { Coins, Item }
local function grant(player, title, reward)
	local lines = {}
	if reward.Coins and reward.Coins > 0 then
		ProgressService.AddCoins(player, reward.Coins, title)
		table.insert(lines, "+" .. reward.Coins .. " Münzen")
	end
	local item = reward.Item and Cosmetics.Get(reward.Item)
	if item and not ProgressService.Owns(player, item.Id) then
		ProgressService.GiveItem(player, item.Id)
		ProgressService.LedgerItem(player, item.Name, item.Rarity)
		table.insert(lines, "Neuer Skin: " .. item.Name)
	end
	if #lines > 0 then
		Remotes.Reward:FireClient(player, { Title = title, Lines = lines, Rarity = item and item.Rarity or nil })
	end
end

-- Alle Meilensteine prüfen, die der Spieler gerade erreicht hat
function RewardService.Check(player)
	local profile = ProgressService.Get(player)
	if not profile then
		return
	end
	local claimed = claimedOf(profile)
	local changed = false
	local info = LevelConfig.Get(player)

	-- Spielerlevel (Münzen je Prestige-Durchgang, Skins einmalig)
	for _, milestone in RewardConfig.Level do
		local key = "P" .. info.Prestige .. "_L" .. milestone.Level
		if info.Level >= milestone.Level and not claimed[key] then
			claimed[key] = true
			changed = true
			grant(player, "LEVEL " .. milestone.Level .. " ERREICHT", milestone)
		end
	end
	-- Prestige
	for _, milestone in RewardConfig.Prestige do
		local key = "Prestige" .. milestone.Prestige
		if info.Prestige >= milestone.Prestige and not claimed[key] then
			claimed[key] = true
			changed = true
			grant(player, "PRESTIGE " .. milestone.Prestige, milestone)
		end
	end
	-- Rang (erster Aufstieg pro Saison)
	local elo = ProgressService.GetElo(player)
	for _, milestone in RewardConfig.Rank do
		local key = "S" .. RankConfig.Season .. "_" .. milestone.Tier
		local tierElo
		for _, tier in RankConfig.Tiers do
			if tier.Name == milestone.Tier then
				tierElo = tier.Elo
			end
		end
		if tierElo and elo >= tierElo and not claimed[key] then
			claimed[key] = true
			changed = true
			grant(player, "RANG " .. string.upper(milestone.Tier) .. " ERREICHT", milestone)
		end
	end
	if changed then
		publish(player, profile)
	end
end

local function watch(player)
	-- warten, bis das Profil geladen ist, dann einmal prüfen (z.B. alte Spielstände) und bei Änderungen
	task.spawn(function()
		for _ = 1, 60 do
			if ProgressService.Get(player) then
				break
			end
			task.wait(0.5)
		end
		local profile = ProgressService.Get(player)
		if profile then
			publish(player, profile)
			RewardService.Check(player)
		end
	end)
	for _, attribute in { "AccountXP", "Prestige", "Elo" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			RewardService.Check(player)
		end)
	end
	-- Killserie endet mit dem Tod
	player.CharacterAdded:Connect(function(character)
		streaks[player] = 0
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				streakAtDeath[player] = math.max(streakAtDeath[player] or 0, streaks[player] or 0)
				streaks[player] = 0
			end)
		end
	end)
end

function RewardService.Init()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		streaks[player] = nil
		streakAtDeath[player] = nil
		lastKiller[player] = nil
	end)
	-- Killserien: Münzen bei 5, 10, 15, 20 Kills ohne zu sterben
	KillService.KillCounted:Connect(function(killer, victim)
		if typeof(killer) ~= "Instance" or not killer:IsA("Player") then
			return
		end
		if typeof(victim) == "Instance" and victim:IsA("Player") and victim ~= killer then
			-- Rache: der Gegner hatte uns zuletzt erledigt
			if lastKiller[killer] == victim then
				lastKiller[killer] = nil
				Remotes.Announce:FireClient(killer, RewardConfig.Revenge.Name .. "!")
				grant(killer, RewardConfig.Revenge.Name, RewardConfig.Revenge)
			end
			lastKiller[victim] = killer
			-- Serie beendet: der Gegner war auf einer Killserie
			local victimStreak = math.max(streaks[victim] or 0, streakAtDeath[victim] or 0)
			streakAtDeath[victim] = 0
			if victimStreak >= RewardConfig.Shutdown.MinStreak then
				Remotes.Announce:FireClient(killer, RewardConfig.Shutdown.Name .. " (" .. victimStreak .. ")!")
				grant(killer, RewardConfig.Shutdown.Name, RewardConfig.Shutdown)
			end
		end
		streaks[killer] = (streaks[killer] or 0) + 1
		for _, streak in RewardConfig.Streaks do
			if streaks[killer] == streak.Kills then
				Remotes.Announce:FireClient(killer, streak.Name .. "!")
				grant(killer, streak.Name, streak)
			end
		end
		-- beste Killserie merken
		local profile = ProgressService.Get(killer)
		if profile and profile.Stats and streaks[killer] > (profile.Stats.BestStreak or 0) then
			ProgressService.AddStat(killer, "BestStreak", streaks[killer] - (profile.Stats.BestStreak or 0))
		end
	end)
end

return RewardService

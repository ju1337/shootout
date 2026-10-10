-- RewardService (ModuleScript, nur Server)
-- Vergibt die Belohnungen aus RewardConfig:
--   Spielerlevel-Meilensteine, Prestige-Skins, Rang-Meilensteine pro Saison (nur mit Arcade), Waffen-Meisterschaft,
--   Titel.
--   Die Kill-Boni (Killserien, Rache, Serie beendet) vergibt KillService zusammen mit den Medaillen.
-- Prüft automatisch, sobald sich Level (AccountXP), Prestige oder ELO eines Spielers ändern.
-- Abgeholte Meilensteine stehen im Profil (profile.Rewards.Claimed) und als JSON im Spieler-Attribut
-- "RewardsClaimed" (für das Belohnungs-Fenster). Jede Belohnung zeigt der Client als Karte links (Remotes.Reward,
-- Notifications).

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local RewardConfig = require(Shared.RewardConfig)
local MasteryConfig = require(Shared.MasteryConfig)
local TitleConfig = require(Shared.TitleConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local LevelConfig = require(Shared.LevelConfig)
local RankConfig = require(Shared.RankConfig)
local Modes = require(Shared.Modes)
local Cosmetics = require(Shared.Cosmetics)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local ProgressService = require(ServerShared.ProgressService)
local KillService = require(ServerShared.KillService)

local RewardService = {}

local function claimedOf(profile)
	profile.Rewards = profile.Rewards or {}
	profile.Rewards.Claimed = profile.Rewards.Claimed or {}
	return profile.Rewards.Claimed
end

local function publish(player, profile)
	player:SetAttribute("RewardsClaimed", HttpService:JSONEncode(claimedOf(profile)))
end

-- Belohnung geben und als Karte melden. reward = { Coins, Item, ItemLabel (Name in der Match-Übersicht) }.
-- key verbindet die Karte mit einer gleichzeitigen Meldung (z.B. "Level20" mit dem Level-Aufstieg)
local function grant(player, title, reward, key)
	local lines = {}
	if reward.Coins and reward.Coins > 0 then
		ProgressService.AddCoins(player, reward.Coins, title)
		table.insert(lines, "+" .. reward.Coins .. " Münzen")
	end
	local item = reward.Item and Cosmetics.Get(reward.Item)
	if item and not ProgressService.Owns(player, item.Id) then
		ProgressService.GiveItem(player, item.Id)
		ProgressService.LedgerItem(player, reward.ItemLabel or item.Name, item.Rarity)
		table.insert(lines, "Neuer Skin: " .. (reward.ItemLabel or item.Name))
	end
	if #lines > 0 then
		Remotes.Reward:FireClient(player, { Title = title, Lines = lines, Rarity = item and item.Rarity or nil, Key = key })
	end
end

-- Neue Titel melden. Beim allerersten Mal (alter Spielstand) still merken, damit nicht alles auf einmal kommt.
local function checkTitles(player, profile)
	local data = ProgressService.TitleData(player)
	if not data then
		return
	end
	local first = profile.TitlesSeen == nil
	profile.TitlesSeen = profile.TitlesSeen or {}
	for _, title in TitleConfig.List do
		if not profile.TitlesSeen[title.Id] and TitleConfig.Unlocked(title, data) then
			profile.TitlesSeen[title.Id] = true
			if not first and title.Id ~= TitleConfig.Default then
				ProgressService.LedgerItem(player, "Titel: " .. title.Name, "Legendary")
				Remotes.Reward:FireClient(player, { Title = "NEUER TITEL", Lines = { "„" .. title.Name .. "“",
					"Im Fenster TITEL auswählen" }, Rarity = "Legendary" })
			end
		end
	end
end

-- Alle Meilensteine prüfen, die der Spieler gerade erreicht hat
function RewardService.Check(player)
	local profile = ProgressService.Get(player)
	if not profile or not ProgressService.IsLoaded(player) then -- nicht das leere Ersatzprofil während des Ladens
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
			grant(player, "LEVEL " .. milestone.Level .. " ERREICHT", milestone, "Level" .. milestone.Level)
		end
	end
	-- Prestige
	for _, milestone in RewardConfig.Prestige do
		local key = "Prestige" .. milestone.Prestige
		if info.Prestige >= milestone.Prestige and not claimed[key] then
			claimed[key] = true
			changed = true
			grant(player, "PRESTIGE " .. milestone.Prestige, milestone, "Prestige" .. milestone.Prestige)
		end
	end
	-- Rang (erster Aufstieg pro Saison): nur mit Arcade (Ranked), sonst bekäme jeder mit der Start-ELO jede Saison
	-- "RANG SILBER ERREICHT", ohne gespielt zu haben
	if Modes.ArcadeEnabled then
		local elo = ProgressService.GetElo(player)
		for _, milestone in RewardConfig.Rank do
			local key = "S" .. RankConfig.CurrentSeason() .. "_" .. milestone.Tier
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
	end
	if changed then
		publish(player, profile)
	end
	checkTitles(player, profile)
end

local function watch(player)
	-- warten, bis das Profil geladen ist, dann einmal prüfen (z.B. alte Spielstände) und bei Änderungen
	task.spawn(function()
		-- so lange wie nötig (Sperre eines alten Servers kann über 30 s dauern), sonst stünden alte Meilensteine als offen da
		while player.Parent and not ProgressService.IsLoaded(player) do
			task.wait(0.5)
		end
		local profile = player.Parent and ProgressService.Get(player)
		if profile then
			publish(player, profile)
			RewardService.Check(player)
		end
	end)
	for _, attribute in { "AccountXP", "Prestige", "Elo", "Stats", "Owned" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			RewardService.Check(player)
		end)
	end
end

function RewardService.Init()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	-- Waffen-Meisterschaft (Killserien, Rache und Serie beendet vergibt KillService mit den Medaillen)
	KillService.KillCounted:Connect(function(killer, _, _, weaponName)
		if typeof(killer) ~= "Instance" or not killer:IsA("Player") then
			return
		end
		-- Waffen-Meisterschaft: Kills pro Waffe zählen, Tarnungen freischalten
		if typeof(weaponName) == "string" and MasteryConfig.HasMastery(weaponName) then
			local key = MasteryConfig.StatKey(weaponName)
			ProgressService.AddStat(killer, key, 1)
			local profile = ProgressService.Get(killer)
			local kills = profile and profile.Stats and profile.Stats[key] or 0
			for _, tier in MasteryConfig.Tiers do
				local id = MasteryConfig.ItemId(weaponName, tier.Id)
				if kills >= tier.Kills and not ProgressService.Owns(killer, id) then
					local weapon = WeaponConfig.Get(weaponName).DisplayName
					grant(killer, "MEISTERSCHAFT · " .. string.upper(weapon), { Coins = tier.Coins, Item = id,
						ItemLabel = tier.Name .. "-Tarnung (" .. weapon .. ")" })
				end
			end
		end
	end)
end

return RewardService

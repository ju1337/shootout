-- AchievementService (ModuleScript, nur Server)
-- Erfolge-Wand (Werte in AchievementConfig): Bei jeder Änderung einer Statistik (ProgressService.OnStat) werden die
-- Erfolge dieser Statistik geprüft. Neu erreichte Stufen: Münzen, Meldung, Eintrag im Profil (Achievements = { [Id] = Stufe })
-- und im Spieler-Attribut "Achievements". Beim Laden des Profils werden verpasste Stufen nachgetragen.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AchievementConfig = require(Shared.AchievementConfig)
local ProgressService = require(script.Parent.ProgressService)
local Badges = require(script.Parent.Badges)

local AchievementService = {}

local function dataOf(profile)
	if type(profile.Achievements) ~= "table" then
		profile.Achievements = {}
	end
	return profile.Achievements
end

function AchievementService.Publish(player)
	local profile = ProgressService.Get(player)
	if profile and player.Parent then
		player:SetAttribute("Achievements", HttpService:JSONEncode(dataOf(profile)))
	end
end

-- Erfolge einer Statistik prüfen und neue Stufen vergeben
function AchievementService.Check(player, stat)
	local profile = ProgressService.Get(player)
	if not profile then
		return
	end
	local value = profile.Stats and tonumber(profile.Stats[stat]) or 0
	local data = dataOf(profile)
	local changed = false
	for _, achievement in AchievementConfig.ForStat(stat) do
		local have = tonumber(data[achievement.Id]) or 0
		local reached = AchievementConfig.TierFor(achievement, value)
		for tier = have + 1, reached do
			data[achievement.Id] = tier
			changed = true
			local coins = achievement.Coins[tier] or 0
			if coins > 0 then
				ProgressService.AddCoins(player, coins, "Erfolg")
			end
			Remotes.Notify:FireClient(player, "Banner", { Caption = "Erfolg · " .. AchievementConfig.Tiers[tier].Name,
				Title = string.upper(achievement.Name), Sub = achievement.Text .. " · +" .. coins .. " Münzen", Style = "Good" })
			Badges.OnAchievement(player, achievement.Id, tier) -- GOLD = Roblox-Badge
		end
	end
	if changed then
		AchievementService.Publish(player)
	end
end

function AchievementService.Init()
	table.insert(ProgressService.OnStat, function(player, stat)
		if #AchievementConfig.ForStat(stat) > 0 then
			AchievementService.Check(player, stat)
		end
	end)
	-- beim Laden: Stand anzeigen und verpasste Stufen nachtragen
	local function onPlayer(player)
		task.spawn(function()
			for _ = 1, 60 do
				if not player.Parent then
					return
				end
				if ProgressService.IsLoaded(player) then -- nicht das leere Ersatzprofil während des Ladens
					break
				end
				task.wait(0.5)
			end
			local seen = {}
			for _, achievement in AchievementConfig.List do
				if not seen[achievement.Stat] then
					seen[achievement.Stat] = true
					AchievementService.Check(player, achievement.Stat)
				end
			end
			AchievementService.Publish(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return AchievementService

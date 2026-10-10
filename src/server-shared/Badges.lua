-- Badges (ModuleScript, nur Server)
-- Vergibt Roblox-Badges (BadgeService) nach BadgeConfig: Begrüßung beim ersten Beitritt, Tutorial fertig, Anwerber
-- (InviteService) und jeder Erfolg der Erfolge-Wand auf GOLD (AchievementService). Verdiente Badges stehen im Profil
-- (Badges = { [Id] = true }), damit BadgeService nicht bei jedem Beitritt gefragt wird; ohne BadgeId (0) wird nur gemerkt
-- (Pending) und nachgetragen, sobald die ID eingetragen ist. Alles über pcall – in Studio ohne Rechte passiert nichts.

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BadgeConfig = require(Shared.BadgeConfig)
local AchievementConfig = require(Shared.AchievementConfig)
local ProgressService = require(script.Parent.ProgressService)

local Badges = {}

Badges.Awarded = {} -- für Tests: { Player, Id, BadgeId }

local function dataOf(profile)
	if type(profile.Badges) ~= "table" then
		profile.Badges = {}
	end
	return profile.Badges
end

-- Badge vergeben (einmal je Spieler). Gibt true zurück, wenn es neu war (vergeben oder vorgemerkt).
function Badges.Award(player, id)
	local badge = BadgeConfig.Get(id)
	local profile = player and ProgressService.Get(player)
	if not badge or not profile then
		return false
	end
	local data = dataOf(profile)
	if data[id] == true then
		return false
	end
	if (tonumber(badge.BadgeId) or 0) <= 0 then
		data[id] = "Pending" -- ID fehlt noch: merken, später nachtragen
		return true
	end
	local ok, result = pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badge.BadgeId)
	if ok and result ~= false then
		data[id] = true
		table.insert(Badges.Awarded, { Player = player, Id = id, BadgeId = badge.BadgeId })
		return true
	end
	warn("Badges: " .. id .. " konnte nicht vergeben werden: " .. tostring(result))
	return false
end

function Badges.Has(player, id)
	local profile = player and ProgressService.Get(player)
	return profile ~= nil and dataOf(profile)[id] == true
end

-- Erfolg auf GOLD -> Badge
function Badges.OnAchievement(player, achievementId, tier)
	if tier >= #AchievementConfig.Tiers then
		local badge = BadgeConfig.ForAchievement(achievementId)
		if badge then
			Badges.Award(player, badge.Id)
		end
	end
end

-- Auslöser ("Welcome", "Tutorial", "Recruiter")
function Badges.Trigger(player, trigger)
	local badge = BadgeConfig.ForTrigger(trigger)
	if badge then
		return Badges.Award(player, badge.Id)
	end
	return false
end

-- Beim Laden: vorgemerkte Badges nachtragen (ID inzwischen da) und verpasste GOLD-Erfolge
local function onLoaded(player)
	local profile = ProgressService.Get(player)
	if not profile then
		return
	end
	local data = dataOf(profile)
	for id, state in data do
		if state == "Pending" and BadgeConfig.Get(id) and (tonumber(BadgeConfig.Get(id).BadgeId) or 0) > 0 then
			data[id] = nil
			if not Badges.Award(player, id) then
				data[id] = "Pending" -- BadgeService gerade gestört: beim nächsten Laden wieder versuchen (Tutorial/Werber kommen nie wieder)
			end
		end
	end
	if type(profile.Achievements) == "table" then
		for achievementId, tier in profile.Achievements do
			Badges.OnAchievement(player, achievementId, tonumber(tier) or 0)
		end
	end
	Badges.Trigger(player, "Welcome")
end

function Badges.Init()
	table.insert(ProgressService.OnLoaded, onLoaded)
end

return Badges

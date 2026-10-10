-- RedPointsService (ModuleScript, nur Server)
-- Rote-Zone-Punkte (RZ, Werte in ExtinctionConfig.RedPoints): eigene Währung, die es nur in der roten Zone gibt (Kills dort,
-- Platz 1-3 der Rangliste beim Weiterziehen). Im Profil unter RedPoints, beim Spieler im Attribut "RedPoints". Ausgeben beim
-- Schieber (Stand_Red, InventoryService.Buy).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ProgressService = require(script.Parent.ProgressService)

local RedPointsService = {}

function RedPointsService.Get(player)
	local profile = ProgressService.Get(player)
	return profile and math.max(0, math.floor(tonumber(profile.RedPoints) or 0)) or 0
end

-- Stand ans Spieler-Attribut
function RedPointsService.Publish(player)
	if player.Parent and ProgressService.Get(player) then
		player:SetAttribute("RedPoints", RedPointsService.Get(player))
	end
end

-- amount RZ gutschreiben (mit Meldung "+N RZ · reason", ohne reason still)
function RedPointsService.Add(player, amount, reason)
	local profile = ProgressService.Get(player)
	amount = math.floor(tonumber(amount) or 0)
	if not profile or amount ~= amount or amount <= 0 or amount == math.huge then
		return false
	end
	profile.RedPoints = RedPointsService.Get(player) + amount
	RedPointsService.Publish(player)
	if reason then -- Zombies (1 RZ) ohne Meldung, sonst wird es zu viel
		Remotes.ExtUpdate:FireClient(player, "Status", "+" .. amount .. " RZ · " .. reason, true)
	end
	return true
end

-- amount RZ ausgeben; false, wenn nicht genug da sind
function RedPointsService.Spend(player, amount)
	local profile = ProgressService.Get(player)
	amount = math.floor(tonumber(amount) or 0)
	if not profile or amount ~= amount or amount < 0 or RedPointsService.Get(player) < amount then
		return false
	end
	profile.RedPoints = RedPointsService.Get(player) - amount
	RedPointsService.Publish(player)
	return true
end

return RedPointsService

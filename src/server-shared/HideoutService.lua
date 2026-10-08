-- HideoutService (ModuleScript, nur Server)
-- Eigenes Versteck der offenen Welt (Werte in HideoutConfig): Module ausbauen (Münzen und Items aus Tasche oder Lager)
-- und die Münzen des Generators abholen – beides nur am Punkt "Hideout" im Camp. Die Stufen stehen im Profil
-- (Hideout = { [Modul] = Stufe, GenAt }) und im Spieler-Attribut "Hideout"; die Boni lesen AgentService (Leben),
-- InventoryService (Rabatt, Heilzeit) über HideoutConfig.Value.
-- Aktionen über Remotes.ExtAction: "HideoutUpgrade" (Modul-Id), "HideoutCollect".

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HideoutConfig = require(Shared.HideoutConfig)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Modes = require(Shared.Modes)
local ProgressService = require(script.Parent.ProgressService)
local InventoryService = require(script.Parent.InventoryService)

local HideoutService = {}

local function dataOf(player)
	local profile = ProgressService.Get(player)
	if not profile then
		return nil
	end
	if type(profile.Hideout) ~= "table" then
		profile.Hideout = {}
	end
	return profile.Hideout
end

-- Stand ans Spieler-Attribut (für Client und Boni)
function HideoutService.Publish(player)
	local data = dataOf(player)
	if data and player.Parent then
		player:SetAttribute("Hideout", HttpService:JSONEncode(data))
	end
end

local function ready(player)
	if not Modes.IsSurvival(player:GetAttribute("Mode")) then
		return false
	end
	if not InventoryService.NearPoint(player, HideoutConfig.Point) then
		InventoryService.Status(player, "Geh in dein Versteck (Haus VERSTECK im Camp).")
		return false
	end
	return true
end

-- Münzen des Generators abholen. Gibt die Anzahl zurück.
function HideoutService.Collect(player, silent)
	local data = dataOf(player)
	if not data or (not silent and not ready(player)) then
		return 0
	end
	local now = os.time()
	local coins = HideoutConfig.Pending(data, now)
	if coins <= 0 then
		if not silent then
			InventoryService.Status(player, HideoutConfig.Level(data, "Generator") > 0 and "Der Generator hat noch nichts erzeugt."
				or "Bau zuerst den Generator.")
		end
		return 0
	end
	data.GenAt = now
	ProgressService.AddCoins(player, coins, "Generator")
	HideoutService.Publish(player)
	if not silent then
		InventoryService.Status(player, "+" .. coins .. " Münzen vom Generator", true)
	end
	return coins
end

-- Modul eine Stufe ausbauen. Gibt true zurück, wenn es geklappt hat.
function HideoutService.Upgrade(player, moduleId)
	local module = type(moduleId) == "string" and HideoutConfig.Get(moduleId)
	local data = dataOf(player)
	if not module or not data or not ready(player) then
		return false
	end
	local level = HideoutConfig.Level(data, moduleId)
	local nextLevel = module.Levels[level + 1]
	if not nextLevel then
		InventoryService.Status(player, module.Name .. " ist schon ganz ausgebaut.")
		return false
	end
	for _, need in nextLevel.Items do
		local have = InventoryService.CountEverywhere(player, need[1])
		if have < need[2] then
			local config = ExtinctionConfig.Get(need[1])
			InventoryService.Status(player, "Dir fehlt: " .. (need[2] - have) .. "× " .. (config and config.Name or need[1])
				.. " (Tasche oder Lager)")
			return false
		end
	end
	if not ProgressService.SpendCoins(player, nextLevel.Coins, "Versteck") then
		InventoryService.Status(player, "Nicht genug Münzen (" .. nextLevel.Coins .. " nötig).")
		return false
	end
	for _, need in nextLevel.Items do
		InventoryService.TakeEverywhere(player, need[1], need[2])
	end
	if moduleId == "Generator" then
		if level > 0 then
			HideoutService.Collect(player, true) -- bisher Erzeugtes zum alten Satz auszahlen
		end
		data.GenAt = os.time()
	end
	data[moduleId] = level + 1
	HideoutService.Publish(player)
	ProgressService.AddStat(player, "ExtHideout", 1) -- Erfolg Bauherr
	InventoryService.Status(player, module.Name .. " auf Stufe " .. (level + 1) .. " ausgebaut", true)
	return true
end

function HideoutService.Init()
	InventoryService.Handlers.HideoutUpgrade = HideoutService.Upgrade
	InventoryService.Handlers.HideoutCollect = function(player)
		HideoutService.Collect(player)
	end
end

return HideoutService

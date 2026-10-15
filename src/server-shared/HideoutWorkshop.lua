-- HideoutWorkshop (ModuleScript, nur Server)
-- Werkbank und Funkaufträge im Versteck (WorkshopConfig), am Punkt "Hideout" im Camp wie die Module (HideoutService).
-- Aktionen über Remotes.ExtAction (InventoryService.Handlers):
--   "HideoutCraft", Rezept-Id      Items und Münzen abgeben, Herstellung startet (einer gleichzeitig)
--   "HideoutCraftCollect"          fertiges Item ins Lager (sonst in die Tasche)
--   "HideoutContract", Nummer      Belohnung eines erledigten Funkauftrags (1..3) abholen
-- Stände im Profil unter Hideout (Craft, Contracts), sichtbar im Spieler-Attribut "Hideout" (HideoutService.Publish).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HideoutConfig = require(Shared.HideoutConfig)
local WorkshopConfig = require(Shared.WorkshopConfig)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Modes = require(Shared.Modes)
local Remotes = require(Shared.Remotes)
local ProgressService = require(script.Parent.ProgressService)
local InventoryService = require(script.Parent.InventoryService)
local HideoutService = require(script.Parent.HideoutService)
local RedPointsService = require(script.Parent.RedPointsService)

local HideoutWorkshop = {}

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

local function itemName(id)
	local config = ExtinctionConfig.Get(id)
	return config and config.Name or id
end

local function ready(player, data)
	if not Modes.IsSurvival(player:GetAttribute("Mode")) then
		return false
	end
	if not HideoutConfig.Unlocked(player, data) then
		InventoryService.Status(player, "Das Versteck wird ab Level " .. HideoutConfig.MinLevel .. " freigeschaltet.")
		return false
	end
	if not InventoryService.NearPoint(player, HideoutConfig.Point) then
		InventoryService.Status(player, "Geh in dein Versteck (Haus VERSTECK im Camp).")
		return false
	end
	return true
end

-- ---------- Werkbank ----------

function HideoutWorkshop.Craft(player, recipeId)
	local data = dataOf(player)
	local recipe = type(recipeId) == "string" and WorkshopConfig.Recipe(recipeId)
	if not data or not recipe or not ready(player, data) then
		return false
	end
	if type(data.Craft) == "table" then
		InventoryService.Status(player, "Die Werkbank ist noch beschäftigt.")
		return false
	end
	if HideoutConfig.Tier(player, data) < recipe.Tier then
		InventoryService.Status(player, "Dieses Rezept gibt es ab Versteckstufe " .. recipe.Tier .. ".")
		return false
	end
	for _, need in recipe.Items do
		local have = InventoryService.CountEverywhere(player, need[1])
		if have < need[2] then
			InventoryService.Status(player, "Dir fehlt: " .. (need[2] - have) .. "× " .. itemName(need[1]) .. " (Tasche oder Lager)")
			return false
		end
	end
	if recipe.Coins > 0 and not ProgressService.SpendCoins(player, recipe.Coins, "Werkbank", recipe.Id) then
		InventoryService.Status(player, "Nicht genug Münzen (" .. recipe.Coins .. " nötig).")
		return false
	end
	for _, need in recipe.Items do
		InventoryService.TakeEverywhere(player, need[1], need[2])
	end
	data.Craft = { Id = recipe.Id, Done = os.time() + WorkshopConfig.CraftTime(recipe, HideoutConfig.Level(data, "Workbench")) }
	HideoutService.Publish(player)
	InventoryService.Status(player, "Werkbank: " .. itemName(recipe.Out[1]) .. " wird hergestellt", true)
	return true
end

function HideoutWorkshop.CollectCraft(player)
	local data = dataOf(player)
	if not data or not ready(player, data) then
		return false
	end
	local craft = data.Craft
	local recipe = type(craft) == "table" and WorkshopConfig.Recipe(craft.Id)
	if not recipe then
		data.Craft = nil
		InventoryService.Status(player, "Auf der Werkbank liegt nichts.")
		return false
	end
	if os.time() < (tonumber(craft.Done) or 0) then
		InventoryService.Status(player, "Noch nicht fertig.")
		return false
	end
	local id, count = recipe.Out[1], recipe.Out[2]
	local added = InventoryService.GiveStash(player, id, count)
	if added < count then
		added += InventoryService.Give(player, id, count - added)
	end
	if added <= 0 then
		InventoryService.Status(player, "Lager und Tasche sind voll.")
		return false
	end
	data.Craft = nil
	HideoutService.Publish(player)
	InventoryService.Status(player, "+" .. added .. "× " .. itemName(id) .. " von der Werkbank", true)
	return true
end

-- ---------- Funkaufträge ----------

-- Heutige Aufträge mit Startwerten (Statistik beim ersten Blick des Tages); minus = Schritt, der schon zum neuen Tag zählt
local function contractsOf(player, data, minusStat, minus)
	local day = WorkshopConfig.Day()
	local state = type(data.Contracts) == "table" and data.Contracts or nil
	if not state or state.Day ~= day then
		local profile = ProgressService.Get(player)
		local stats = profile and profile.Stats or {}
		local list = {}
		for i, contract in WorkshopConfig.ContractsFor(day) do
			list[i] = { Base = (stats[contract.Stat] or 0) - (contract.Stat == minusStat and minus or 0), Claimed = false }
		end
		state = { Day = day, List = list }
		data.Contracts = state
	end
	return state
end

function HideoutWorkshop.Progress(player, index)
	local data = dataOf(player)
	if not data then
		return 0, 1, nil
	end
	local state = contractsOf(player, data)
	local contract = WorkshopConfig.ContractsFor(state.Day)[index]
	local entry = state.List[index]
	if not contract or not entry then
		return 0, 1, nil
	end
	local profile = ProgressService.Get(player)
	local have = math.max(0, ((profile and profile.Stats or {})[contract.Stat] or 0) - (tonumber(entry.Base) or 0))
	return math.min(have, contract.Need), contract.Need, contract, entry
end

function HideoutWorkshop.ClaimContract(player, index)
	local data = dataOf(player)
	if type(index) ~= "number" or not data or not ready(player, data) then
		return false
	end
	if HideoutConfig.Tier(player, data) < WorkshopConfig.ContractTier then
		InventoryService.Status(player, "Funkaufträge gibt es ab Versteckstufe " .. WorkshopConfig.ContractTier .. ".")
		return false
	end
	local have, need, contract, entry = HideoutWorkshop.Progress(player, index)
	if not contract then
		return false
	elseif entry.Claimed then
		InventoryService.Status(player, "Schon abgeholt. Morgen gibt es neue Funkaufträge.")
		return false
	elseif have < need then
		InventoryService.Status(player, "Noch nicht erledigt (" .. have .. "/" .. need .. ").")
		return false
	end
	entry.Claimed = true
	local reward = contract.Reward
	local parts = {}
	if reward.Coins then
		ProgressService.AddCoins(player, reward.Coins, "Funkauftrag")
		table.insert(parts, reward.Coins .. " Münzen")
	end
	if reward.RedPoints then
		RedPointsService.Add(player, reward.RedPoints, nil)
		table.insert(parts, reward.RedPoints .. " RZ")
	end
	for _, item in reward.Items or {} do
		local added = InventoryService.GiveStash(player, item[1], item[2])
		if added < item[2] then
			InventoryService.Give(player, item[1], item[2] - added)
		end
		table.insert(parts, item[2] .. "× " .. itemName(item[1]))
	end
	if reward.XP then
		local gained, doubled = ProgressService.AddAccountXP(player, reward.XP)
		if gained > 0 then
			Remotes.ExtUpdate:FireClient(player, "ExtXP", gained, doubled and "Funkauftrag · Doppel-XP" or "Funkauftrag")
		end
	end
	HideoutService.Publish(player)
	InventoryService.Status(player, "Funkauftrag erledigt: " .. table.concat(parts, ", "), true)
	return true
end

function HideoutWorkshop.Init()
	InventoryService.Handlers.HideoutCraft = HideoutWorkshop.Craft
	InventoryService.Handlers.HideoutCraftCollect = HideoutWorkshop.CollectCraft
	InventoryService.Handlers.HideoutContract = HideoutWorkshop.ClaimContract
	-- neuer Tag: Aufträge beim ersten gezählten Schritt neu stellen (der Schritt zählt schon mit) und anzeigen
	table.insert(ProgressService.OnStat, function(player, key, _, amount)
		local data = dataOf(player)
		if not data or not HideoutConfig.Unlocked(player, data) then
			return
		end
		local state = data.Contracts
		if type(state) ~= "table" or state.Day ~= WorkshopConfig.Day() then
			contractsOf(player, data, key, amount)
			HideoutService.Publish(player)
		end
	end)
	-- beim Veröffentlichen schon die heutigen Aufträge anlegen (Startwerte ab jetzt)
	local publish = HideoutService.Publish
	HideoutService.Publish = function(player)
		local data = dataOf(player)
		if data and HideoutConfig.Unlocked(player, data) then
			contractsOf(player, data)
		end
		publish(player)
	end
end

return HideoutWorkshop

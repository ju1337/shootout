-- HideoutService (ModuleScript, nur Server)
-- Eigenes Versteck der offenen Welt (Werte in HideoutConfig): Versteckstufe kaufen (Münzen und Items ab Spielerlevel,
-- oder mit Robux über GrantTier), Module ausbauen (Münzen und Items aus Tasche oder Lager, bis zur Versteckstufe),
-- Generator und Munitionspresse abholen, Tagesauftrag am Funkgerät abholen – alles außer Robux nur am Punkt "Hideout"
-- im Camp. Die Stände stehen im Profil (Hideout = { Tier, [Modul] = Stufe, GenAt, PressAt, PressAmmo, Radio }) und im
-- Spieler-Attribut "Hideout"; die Boni lesen AgentService (Leben), InventoryService (Rabatt, Heilzeit, Lagerplätze) über
-- HideoutConfig. Erst ab Spielerlevel HideoutConfig.MinLevel (oder mit einer gekauften Stufe).
-- Aktionen über Remotes.ExtAction: "HideoutTier" (Ziel-Stufe), "HideoutUpgrade" (Modul-Id, Ziel-Stufe), "HideoutCollect",
-- "HideoutPress" (abholen), "HideoutPressAmmo" (Item-Id), "HideoutRadio" (Tagesauftrag abholen).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HideoutConfig = require(Shared.HideoutConfig)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local LevelConfig = require(Shared.LevelConfig)
local Modes = require(Shared.Modes)
local Remotes = require(Shared.Remotes)
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
	local data = profile.Hideout
	-- alte Stände (vor den Versteckstufen): so hoch wie das höchste gebaute Modul, damit nichts verloren geht
	if data.Tier == nil then
		local highest = 0
		for _, module in HideoutConfig.Modules do
			highest = math.max(highest, HideoutConfig.Level(data, module.Id))
		end
		data.Tier = math.min(highest, #HideoutConfig.Tiers)
	end
	return data
end

-- Tagesauftrag des Funkgeräts auf heute stellen (Startwert der Statistik merken). minus: gerade gezählter Schritt, der
-- schon zum neuen Tag gehört
local function radioOf(player, data, minus)
	local day = HideoutConfig.Day()
	local radio = type(data.Radio) == "table" and data.Radio or nil
	if not radio or radio.Day ~= day then
		local radioJob = HideoutConfig.RadioTask(day)
		local profile = ProgressService.Get(player)
		local stats = profile and profile.Stats or {}
		radio = { Day = day, Base = (stats[radioJob.Stat] or 0) - (minus or 0), Claimed = false }
		data.Radio = radio
	end
	return radio
end

-- Fortschritt des heutigen Funkauftrags: have, need, Auftrag
local function radioProgress(player, data)
	local radio = radioOf(player, data)
	local radioJob = HideoutConfig.RadioTask(radio.Day)
	local profile = ProgressService.Get(player)
	local have = math.max(0, ((profile and profile.Stats or {})[radioJob.Stat] or 0) - radio.Base)
	return math.min(have, radioJob.Need), radioJob.Need, radioJob
end

-- Stand ans Spieler-Attribut (für Client und Boni)
function HideoutService.Publish(player)
	local data = dataOf(player)
	if data and player.Parent then
		if HideoutConfig.HasFeature(player, "Radio", data) then
			radioOf(player, data)
		end
		player:SetAttribute("Hideout", HttpService:JSONEncode(data))
	end
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

-- Fehlende Items (Tasche oder Lager) melden; true, wenn alles da ist
local function haveItems(player, items)
	for _, need in items do
		local have = InventoryService.CountEverywhere(player, need[1])
		if have < need[2] then
			local config = ExtinctionConfig.Get(need[1])
			InventoryService.Status(player, "Dir fehlt: " .. (need[2] - have) .. "× " .. (config and config.Name or need[1])
				.. " (Tasche oder Lager)")
			return false
		end
	end
	return true
end

-- Münzen des Generators abholen. Gibt die Anzahl zurück.
function HideoutService.Collect(player, silent)
	local data = dataOf(player)
	if not data or (not silent and not ready(player, data)) then
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

-- Munition der Presse ins Lager legen (was nicht passt, bleibt in der Presse). Gibt die Anzahl Patronen zurück.
function HideoutService.CollectPress(player, silent)
	local data = dataOf(player)
	if not data or (not silent and not ready(player, data)) then
		return 0
	end
	local now = os.time()
	local packs = HideoutConfig.PressPending(data, now)
	if packs <= 0 then
		if not silent then
			InventoryService.Status(player, HideoutConfig.Level(data, "AmmoPress") > 0 and "Die Munitionspresse hat noch nichts erzeugt."
				or "Bau zuerst die Munitionspresse.")
		end
		return 0
	end
	local ammoId = HideoutConfig.PressAmmoOf(data)
	local config = ExtinctionConfig.Get(ammoId)
	local pack = config and config.Pack or 30
	local added = InventoryService.GiveStash(player, ammoId, packs * pack)
	local usedPacks = math.ceil(added / pack)
	if usedPacks <= 0 then
		if not silent then
			InventoryService.Status(player, "Das Lager ist voll.")
		end
		return 0
	end
	if usedPacks >= packs then
		data.PressAt = now
	else
		-- nur die abgeholten Pakete abziehen, der Rest bleibt in der Presse
		local level = HideoutConfig.Level(data, "AmmoPress")
		local perHour = HideoutConfig.Get("AmmoPress").Levels[level].Value
		local start = math.max(tonumber(data.PressAt) or now, now - HideoutConfig.PressCap)
		data.PressAt = start + math.ceil(usedPacks * 3600 / perHour)
	end
	HideoutService.Publish(player)
	if not silent then
		InventoryService.Status(player, "+" .. added .. "× " .. (config and config.Name or ammoId) .. " ins Lager", true)
	end
	return added
end

-- Munitionssorte der Presse wählen; bisher Erzeugtes wird vorher in der alten Sorte ins Lager gelegt
function HideoutService.SetPressAmmo(player, ammoId)
	local data = dataOf(player)
	if not data or type(ammoId) ~= "string" or not table.find(HideoutConfig.PressAmmo, ammoId) or not ready(player, data) then
		return false
	end
	if HideoutConfig.PressAmmoOf(data) == ammoId then
		return true
	end
	HideoutService.CollectPress(player, true)
	data.PressAmmo = ammoId
	HideoutService.Publish(player)
	return true
end

-- Tagesauftrag des Funkgeräts abholen. Gibt true zurück, wenn es geklappt hat.
function HideoutService.ClaimRadio(player)
	local data = dataOf(player)
	if not data or not ready(player, data) then
		return false
	end
	if not HideoutConfig.HasFeature(player, "Radio", data) then
		InventoryService.Status(player, "Das Funkgerät gibt es ab Versteckstufe " .. HideoutConfig.Features.Radio .. ".")
		return false
	end
	local have, need = radioProgress(player, data)
	if data.Radio.Claimed then
		InventoryService.Status(player, "Heute schon abgeholt. Morgen gibt es einen neuen Funkauftrag.")
		return false
	elseif have < need then
		InventoryService.Status(player, "Der Funkauftrag ist noch nicht erledigt (" .. have .. "/" .. need .. ").")
		return false
	end
	data.Radio.Claimed = true
	local R = HideoutConfig.Radio
	ProgressService.AddCoins(player, R.Coins, "Funkgerät")
	local gained, doubled = ProgressService.AddAccountXP(player, R.XP)
	if gained > 0 then
		Remotes.ExtUpdate:FireClient(player, "ExtXP", gained, doubled and "Funkgerät · Doppel-XP" or "Funkgerät")
	end
	HideoutService.Publish(player)
	InventoryService.Status(player, "Funkauftrag erledigt: +" .. R.Coins .. " Münzen", true)
	return true
end

-- Versteckstufe mit Münzen und Items kaufen (ab dem Spielerlevel der Stufe). target: angezeigte Ziel-Stufe
function HideoutService.UpgradeTier(player, target)
	local data = dataOf(player)
	if not data or not ready(player, data) then
		return false
	end
	local tier = HideoutConfig.Tier(player, data)
	if target ~= nil and target ~= tier + 1 then -- Doppelklick: die angezeigte Stufe ist schon da
		return false
	end
	local nextTier = HideoutConfig.Tiers[tier + 1]
	if not nextTier then
		InventoryService.Status(player, "Dein Versteck ist schon ganz ausgebaut.")
		return false
	end
	local level = LevelConfig.Get(player).Total
	if level < nextTier.MinLevel then
		InventoryService.Status(player, nextTier.Name .. " gibt es ab Level " .. nextTier.MinLevel .. " (du: " .. level
			.. "). Oder sofort mit Robux.")
		return false
	end
	if not haveItems(player, nextTier.Items) then
		return false
	end
	if not ProgressService.SpendCoins(player, nextTier.Coins, "Versteck") then
		InventoryService.Status(player, "Nicht genug Münzen (" .. nextTier.Coins .. " nötig).")
		return false
	end
	for _, need in nextTier.Items do
		InventoryService.TakeEverywhere(player, need[1], need[2])
	end
	data.Tier = tier + 1
	HideoutService.Publish(player)
	InventoryService.Status(player, "Versteck auf Stufe " .. (tier + 1) .. " ausgebaut: " .. nextTier.Name, true)
	return true
end

-- Versteckstufe mit Robux (RobuxService): sofort, ohne Level-Grenze, überall. Gibt true zurück, wenn sie neu ist.
function HideoutService.GrantTier(player, tier)
	local data = dataOf(player)
	tier = math.clamp(math.floor(tonumber(tier) or 0), 0, #HideoutConfig.Tiers)
	if not data or tier <= (tonumber(data.Tier) or 0) then
		return false
	end
	data.Tier = tier
	HideoutService.Publish(player)
	return true
end

-- Modul eine Stufe ausbauen. Gibt true zurück, wenn es geklappt hat.
function HideoutService.Upgrade(player, moduleId, target)
	local module = type(moduleId) == "string" and HideoutConfig.Get(moduleId)
	local data = dataOf(player)
	if not module or not data or not ready(player, data) then
		return false
	end
	local level = HideoutConfig.Level(data, moduleId)
	if target ~= nil and target ~= level + 1 then -- Doppelklick: die angezeigte Stufe ist schon gebaut
		return false
	end
	local nextLevel = module.Levels[level + 1]
	if not nextLevel then
		InventoryService.Status(player, module.Name .. " ist schon ganz ausgebaut.")
		return false
	end
	local needTier = module.Tiers[level + 1]
	if HideoutConfig.Tier(player, data) < needTier then
		InventoryService.Status(player, "Dafür brauchst du Versteckstufe " .. needTier .. " (" .. HideoutConfig.Tiers[needTier].Name .. ").")
		return false
	end
	if not haveItems(player, nextLevel.Items) then
		return false
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
	elseif moduleId == "AmmoPress" then
		if level > 0 then
			HideoutService.CollectPress(player, true)
		end
		data.PressAt = os.time()
	end
	data[moduleId] = level + 1
	if moduleId == "Shelf" then
		InventoryService.ResizeStash(player)
	end
	HideoutService.Publish(player)
	ProgressService.AddStat(player, "ExtHideout", 1) -- Erfolg Bauherr
	InventoryService.Status(player, module.Name .. " auf Stufe " .. (level + 1) .. " ausgebaut", true)
	return true
end

function HideoutService.Init()
	InventoryService.Handlers.HideoutUpgrade = HideoutService.Upgrade
	InventoryService.Handlers.HideoutTier = HideoutService.UpgradeTier
	InventoryService.Handlers.HideoutCollect = function(player)
		HideoutService.Collect(player)
	end
	InventoryService.Handlers.HideoutPress = function(player)
		HideoutService.CollectPress(player)
	end
	InventoryService.Handlers.HideoutPressAmmo = HideoutService.SetPressAmmo
	InventoryService.Handlers.HideoutRadio = HideoutService.ClaimRadio
	-- Funkgerät: beim ersten Schritt eines neuen Tages den Auftrag neu stellen (der Schritt zählt schon mit)
	table.insert(ProgressService.OnStat, function(player, key, _, amount)
		local profile = ProgressService.Get(player)
		local data = profile and type(profile.Hideout) == "table" and profile.Hideout
		if not data or not HideoutConfig.HasFeature(player, "Radio", data) then
			return
		end
		local radio = data.Radio
		if type(radio) ~= "table" or radio.Day ~= HideoutConfig.Day() then
			local radioJob = HideoutConfig.RadioTask(HideoutConfig.Day())
			radioOf(player, data, key == radioJob.Stat and amount or 0)
			HideoutService.Publish(player)
		end
	end)
end

return HideoutService

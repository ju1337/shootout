-- Daten der offenen Welt passen zusammen (ohne Spiel, nur die Konfiguration): Jede Item-Id in Beute-Tabellen, Ständen,
-- Kits, täglichen Kisten, Bossen, Events und Dungeon-Belohnungen gibt es in ExtinctionConfig.Items; Waffen-Items zeigen
-- auf eine Waffe mit Munition; jede Waffe hat ihre Aufsätze als eigene Items (Att_<Waffe>_<Id>); am Stand gekauft und
-- sofort wieder verkauft bringt nie mehr Münzen, als es gekostet hat; der Schieber hat für jedes Item einen RZ-Preis.
-- Fängt Tippfehler, wenn neue Items, Waffen oder Beute dazukommen.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ExtinctionConfig = require("ExtinctionConfig")
local WeaponConfig = require("WeaponConfig")
local AttachmentConfig = require("AttachmentConfig")
local KitConfig = require("KitConfig")
local ExtDailyConfig = require("ExtDailyConfig")
local Items = ExtinctionConfig.Items

local function exists(id)
	return type(id) == "string" and Items[id] ~= nil
end

-- ---------- Item-Verweise überall in den Tabellen ----------
-- { Id = "...", Count/Chance/Weight = ... } (Beute), { "Id", Anzahl } (Always, Kits, Tageskisten), Listen von Ids
-- unter Items/Pick/Weapons (Stände, Tageskisten)
local LIST_KEYS = { Items = true, Pick = true, KitVariants = true }
local TUPLE_KEYS = { Items = true, Always = true, AdminLoadout = true, Loot = true, Rewards = true }
local checked = 0
local function walk(node, path, parentKey, seen)
	if type(node) ~= "table" or seen[node] then
		return
	end
	seen[node] = true
	if type(node.Id) == "string" and (node.Count ~= nil or node.Chance ~= nil or node.Weight ~= nil) then
		checked += 1
		check(exists(node.Id), path .. ": unbekanntes Item " .. node.Id)
	end
	if TUPLE_KEYS[parentKey] then
		for i, entry in ipairs(node) do
			if type(entry) == "table" and type(entry[1]) == "string" and type(entry[2]) == "number" then
				checked += 1
				check(exists(entry[1]), path .. "[" .. i .. "]: unbekanntes Item " .. entry[1])
			end
		end
	end
	if LIST_KEYS[parentKey] then
		for i, entry in ipairs(node) do
			if type(entry) == "string" then
				checked += 1
				check(exists(entry), path .. "[" .. i .. "]: unbekanntes Item " .. entry)
			end
		end
	end
	for key, value in node do
		walk(value, path .. "." .. tostring(key), key, seen)
	end
end
-- nicht: die Item-Liste selbst (Kit-Ausführungen verweisen auf ihr Original), Aufträge (Id = Auftragsart) und die
-- Sturm-Belohnung ({ Beute-Tabelle, Anzahl }, unten geprüft)
local seen = { [Items] = true, [ExtinctionConfig.Missions] = true, [ExtinctionConfig.Storm.Reward] = true }
for key, value in ExtinctionConfig do
	if type(value) == "table" then
		walk(value, "ExtinctionConfig." .. key, key, seen)
	end
end
walk(KitConfig.List, "KitConfig.List", "List", {})
walk(ExtDailyConfig, "ExtDailyConfig", "ExtDailyConfig", {})
check(checked > 100, "genug Item-Verweise gefunden (" .. checked .. ") – sonst prüft der Test nichts mehr")

-- Beute-Tabellen, auf die Belohnungen verweisen
for _, entry in ExtinctionConfig.Storm.Reward.Items do
	check(ExtinctionConfig.LootTables[entry[1]] ~= nil, "Storm.Reward: unbekannte Beute-Tabelle " .. tostring(entry[1]))
end
for wave = 1, 30 do
	local reward = ExtinctionConfig.DungeonReward(wave)
	check(ExtinctionConfig.LootTables[reward.Table] ~= nil,
		"DungeonReward(" .. wave .. "): unbekannte Beute-Tabelle " .. tostring(reward.Table))
end
check(exists(ExtinctionConfig.Dungeon.KeyItem), "Dungeon.KeyItem fehlt in Items")
local random = Random.new(7)
for name in ExtinctionConfig.LootTables do
	for _ = 1, 20 do
		for _, entry in ExtinctionConfig.RollLoot(name, 3, random) or {} do
			local id = type(entry) == "table" and (entry.Id or entry[1])
			check(exists(id), "RollLoot(" .. name .. "): unbekanntes Item " .. tostring(id))
		end
	end
end

-- ---------- jedes Item ----------
for id, item in Items do
	check(type(item.Name) == "string" and item.Name ~= "", id .. ": ohne Name")
	check(type(item.Kind) == "string", id .. ": ohne Kind")
	if item.Kind == "Weapon" then
		check(WeaponConfig.Get(item.Weapon) ~= nil, id .. ": Waffe " .. tostring(item.Weapon) .. " fehlt in WeaponConfig")
		check(exists(item.Ammo) and Items[item.Ammo].Kind == "Ammo", id .. ": Munition " .. tostring(item.Ammo) .. " fehlt")
	end
	if item.Price ~= nil then
		check(type(item.Price) == "number" and item.Price > 0, id .. ": Preis muss größer als 0 sein")
	end
	if item.MaxStack ~= nil and item.Pack ~= nil then
		check(item.MaxStack >= item.Pack, id .. ": eine Packung passt nicht auf einen Stapel")
	end
end

-- ---------- Aufsätze je Waffe ----------
for _, item in Items do
	if item.Kind == "Weapon" and not item.Kit then
		local ids = AttachmentConfig.ByWeapon[item.Weapon]
		check(ids ~= nil, item.Weapon .. ": keine Aufsätze in AttachmentConfig.ByWeapon (leere Liste, wenn keine passen)")
		for _, attId in ids or {} do
			check(AttachmentConfig.Get(attId) ~= nil, item.Weapon .. ": Aufsatz " .. attId .. " fehlt in AttachmentConfig.List")
			local itemId = ExtinctionConfig.AttachmentItemId(item.Weapon, attId)
			check(exists(itemId), item.Weapon .. ": Aufsatz-Item " .. tostring(itemId) .. " fehlt")
			check(AttachmentConfig.Fits(item.Weapon, attId), item.Weapon .. ": " .. attId .. " passt laut Fits nicht")
		end
	end
end
for weaponName in AttachmentConfig.ByWeapon do
	check(WeaponConfig.Get(weaponName) ~= nil, "ByWeapon: unbekannte Waffe " .. weaponName)
end
for _, id in ExtinctionConfig.AttachmentItems do
	check(exists(id), "AttachmentItems: " .. id .. " fehlt in Items")
end

-- ---------- Stände: kaufen und gleich verkaufen bringt keinen Gewinn ----------
for standName, stand in ExtinctionConfig.Stands do
	check(type(stand.Items) == "table" and #stand.Items > 0, standName .. ": ohne Items")
	for _, id in stand.Items do
		local item = Items[id]
		if item and stand.Currency == "RedPoints" then
			check(type(stand.Prices) == "table" and type(stand.Prices[id]) == "number" and stand.Prices[id] > 0,
				standName .. ": kein RZ-Preis für " .. id)
		elseif item then
			check(type(item.Price) == "number", standName .. ": " .. id .. " hat keinen Preis")
			local count = item.Pack or 1
			local sell = ExtinctionConfig.SellPrice(id, count)
			check(sell < (item.Price or 0), standName .. ": " .. id .. " kaufen und verkaufen bringt Gewinn ("
				.. tostring(item.Price) .. " -> " .. sell .. ")")
		end
	end
end
check(ExtinctionConfig.SellFactor > 0 and ExtinctionConfig.SellFactor < 1, "SellFactor zwischen 0 und 1")
-- Kit-Items bringen beim Verkaufen nichts
for id, item in Items do
	if item.Kit then
		check(ExtinctionConfig.SellPrice(id, 5) == 0, id .. ": Kit-Item bringt beim Verkaufen Münzen")
	end
end
check(ExtinctionConfig.Market.FeeRate > 0 and ExtinctionConfig.Market.FeeRate < 1, "Markt-Gebühr zwischen 0 und 1")

if failures > 0 then
	error(failures .. " Prüfungen fehlgeschlagen")
end
print("configrefs: " .. checked .. " Item-Verweise geprüft")

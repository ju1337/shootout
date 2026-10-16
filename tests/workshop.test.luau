-- Werkbank, Funkaufträge (HideoutWorkshop) und Schießstand (RangeService) im Versteck: Rezepte brauchen Items und Stufe,
-- eine Herstellung gleichzeitig, fertig ins Lager; drei Funkaufträge am Tag mit eigenen Belohnungen, jeder einmal; am
-- Schießstand nur der Spieler mit der Runde und nur im Feld, Treffer zählen, Bestwert und Tagesbelohnung.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 1, 20) -- mit Heartbeat (Safe-Zone-Prüfung, Magazin-Abgleich)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v2")
local HttpService = game:GetService("HttpService")
local Remotes = require("Remotes")
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
local Damage = require("Damage")
ProgressService.Init()
WeaponService.Init()

-- Karte wie aus tools/build_maps.py: Safe Zone (Radius 100) um (0, 0, -6000), Spawns, Stände, Lager, Tor zum Hub
local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("DisplayName", "Ödland")
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
-- kleine Safe Zone draußen (Safehouse) mit eigenen Spawns
local safehouse = Instance.new("Part", map.Zone)
safehouse.Name = "SafeZone_Test"
safehouse:SetAttribute("Title", "SAFEHOUSE TEST")
safehouse.Size = Vector3.new(80, 80, 80)
safehouse.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 600))
local safehouseSpawns = Instance.new("Folder", map)
safehouseSpawns.Name = "Spawns_Test"
Instance.new("Part", safehouseSpawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 610))
local houseStand = Instance.new("Part", map.Stands) -- zweiter Waffenstand im Safehouse (gleicher Name)
houseStand.Name = "Stand_Weapons"
houseStand.CFrame = CFrame.new(CENTER + Vector3.new(-12, 2.5, 600))
local travelStop = Instance.new("Part", map.Stands)
travelStop.Name = "Travel"
travelStop.CFrame = CFrame.new(CENTER + Vector3.new(-36, 2.5, 16))
local spawnPoint = Instance.new("Part", map.Spawns)
spawnPoint.CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
local portal = Instance.new("Part", map.Portals)
portal.Name = "Portal_Hub"
portal.CFrame = CFrame.new(CENTER + Vector3.new(-62, 0.4, -32))
local standPos = {
	Stand_Weapons = CENTER + Vector3.new(-36, 2.5, 34),
	Stand_Items = CENTER + Vector3.new(36, 2.5, 34),
	Stand_Vehicles = CENTER + Vector3.new(-30, 2.5, -42),
	Stash = CENTER + Vector3.new(52, 2.5, -30),
	Hideout = CENTER + Vector3.new(52, 2.5, 7),
}
for name, position in standPos do
	local part = Instance.new("Part", map.Stands)
	part.Name = name
	part.CFrame = CFrame.new(position)
end

-- Schießstand im Camp (Gruppe Zentrale)
local zentrale = Instance.new("Folder", map)
zentrale.Name = "Zentrale"
local function zpart(name, offset, size)
	local part = Instance.new("Part", zentrale)
	part.Name = name
	part.Size = size or Vector3.new(2, 2, 2)
	part.CFrame = CFrame.new(CENTER + offset)
	return part
end
zpart("Range_Start", Vector3.new(-60, 2.5, 60))
zpart("Range_Zone", Vector3.new(-60, 3, 60), Vector3.new(6, 6, 10))
for i = 1, 3 do
	zpart("Range_Target" .. i, Vector3.new(-90, 3.5, 56 + i * 2), Vector3.new(0.2, 2.6, 1.8))
	zpart("Range_Bull" .. i, Vector3.new(-89.8, 3.9, 56 + i * 2), Vector3.new(0.12, 0.7, 0.7))
end

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
InventoryService.Init()
LootService.Init()
local statusText = nil
local manager = {
	Join = function(player, modeId)
		if modeId ~= "Extinction" and player:GetAttribute("Mode") == "Extinction" then
			if Extinction.ConfirmLeave(player) then
				Extinction.RemovePlayer(player)
				player:SetAttribute("Mode", modeId)
			end
		end
	end,
	Status = function(_, text)
		statusText = text
	end,
}
require("ExtinctionConfig").Airdrop.FirstDelay = math.huge -- hier keine Lootdrops (eigener Test: airdrop)
require("ExtinctionConfig").Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
require("ExtinctionConfig").HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
require("ExtDailyConfig").Enabled = false -- tägliche Kiste: eigener Test (extdaily)
require("ExtinctionConfig").Day.Fixed = 12 -- immer Tag (nachts mehr Zombies; eigener Test: daycycle)
require("ExtinctionConfig").Zombies.KindWeights = { Walker = 1 } -- nur normale Zombies (Schreier rufen sonst Verstärkung)
Extinction.Init(manager)

local function bagOf(player)
	return HttpService:JSONDecode(player:GetAttribute("ExtBag") or "[]")
end
local function slot(player, s)
	for _, entry in bagOf(player) do
		if entry.S == s then
			return entry
		end
	end
	return nil
end
local function lastExt(player, kind)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "ExtUpdate" and entry.Player == player and entry.Args[1] == kind then
			return entry.Args
		end
	end
	return nil
end
local function lastAmmo(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "AmmoUpdate" and entry.Player == player then
			return entry.Args
		end
	end
	return nil
end
local function moveTo(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
	step(0.3)
end
local function enter(player)
	player:SetAttribute("Mode", "Extinction")
	Extinction.AddPlayer(player)
	step(0.3)
end

local HideoutConfig = require("HideoutConfig")
local HideoutService = require("HideoutService")
local WorkshopConfig = require("WorkshopConfig")
local HideoutWorkshop = require("HideoutWorkshop")
local RangeService = require("RangeService")

store.Data.u1 = { XP = {}, Coins = 200000, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)
enter(alice)
local function coins()
	return ProgressService.Get(alice).Coins
end
local function data()
	return ProgressService.Get(alice).Hideout
end
local function count(id)
	return InventoryService.CountEverywhere(alice, id)
end
local LevelConfig = require("LevelConfig")
local level4XP = 0
for level = 1, HideoutConfig.MinLevel - 1 do
	level4XP += LevelConfig.XPForLevel(level)
end
ProgressService.Get(alice).AccountXP = level4XP
alice:SetAttribute("AccountXP", level4XP)
check(HideoutConfig.Tier(alice) == 1, "Versteckstufe 1")

-- ---------- Werkbank ----------
moveTo(alice, Vector3.new(0, 3, 0))
check(HideoutWorkshop.Craft(alice, "Medkit") == false, "nicht am Versteck: keine Werkbank")
moveTo(alice, Vector3.new(52, 3, 2))
check(HideoutWorkshop.Craft(alice, "Medkit") == false and string.find(lastExt(alice, "Status")[2], "Verband", 1, true) ~= nil,
	"Medikit ohne Verbände nicht")
InventoryService.Give(alice, "Bandage", 6, nil, "Hotbar")
check(HideoutWorkshop.Craft(alice, "Medkit") == true and count("Bandage") == 2, "Medikit: 4 Verbände abgegeben")
check(type(data().Craft) == "table" and data().Craft.Id == "Medkit", "Werkbank arbeitet")
check(string.find(alice:GetAttribute("Hideout") or "", "Medkit", 1, true) ~= nil, "Stand im Attribut")
check(HideoutWorkshop.Craft(alice, "Molotov") == false and string.find(lastExt(alice, "Status")[2], "beschäftigt", 1, true) ~= nil,
	"nur eine Herstellung gleichzeitig")
check(HideoutWorkshop.CollectCraft(alice) == false, "vor der Zeit nicht abholen")
data().Craft.Done = os.time() - 1
check(HideoutWorkshop.CollectCraft(alice) == true and count("Medkit") == 1 and data().Craft == nil, "fertig: Medikit abgeholt")
check(HideoutWorkshop.Craft(alice, "Adrenaline") == false and string.find(lastExt(alice, "Status")[2], "Versteckstufe 2", 1, true) ~= nil,
	"Adrenalin erst ab Stufe 2")
check(WorkshopConfig.CraftTime(WorkshopConfig.Recipe("DungeonKey"), 2) < WorkshopConfig.Recipe("DungeonKey").Time,
	"Werkbank-Modul macht schneller")
for _, recipe in WorkshopConfig.Recipes do
	check(ExtinctionConfig.Get(recipe.Out[1]) ~= nil, "Rezept " .. recipe.Id .. ": Item gibt es")
	for _, need in recipe.Items do
		check(ExtinctionConfig.Get(need[1]) ~= nil, "Rezept " .. recipe.Id .. ": Zutat " .. need[1] .. " gibt es")
	end
end

-- ---------- Funkaufträge ----------
HideoutService.Publish(alice)
local today = WorkshopConfig.ContractsFor(WorkshopConfig.Day())
check(#today == 3 and today[1].Id ~= today[2].Id and today[2].Id ~= today[3].Id, "drei verschiedene Aufträge")
check(type(data().Contracts) == "table" and #data().Contracts.List == 3, "Startwerte gemerkt")
check(HideoutWorkshop.ClaimContract(alice, 1) == false and string.find(lastExt(alice, "Status")[2], "Noch nicht", 1, true) ~= nil,
	"unerledigt: nichts")
ProgressService.AddStat(alice, today[1].Stat, today[1].Need)
local before = coins()
local rz = ProgressService.Get(alice).RedPoints or 0
check(HideoutWorkshop.ClaimContract(alice, 1) == true, "erledigt: abgeholt")
local reward = today[1].Reward
check(coins() == before + (reward.Coins or 0) and (ProgressService.Get(alice).RedPoints or 0) == rz + (reward.RedPoints or 0),
	"Belohnung: Münzen und RZ")
for _, item in reward.Items or {} do
	check(count(item[1]) >= item[2], "Belohnung: " .. item[1])
end
check(HideoutWorkshop.ClaimContract(alice, 1) == false, "nur einmal")
for _, contract in WorkshopConfig.Contracts do
	for _, item in contract.Reward.Items or {} do
		check(ExtinctionConfig.Get(item[1]) ~= nil, "Auftrag " .. contract.Id .. ": Item " .. item[1] .. " gibt es")
	end
end

-- ---------- Schießstand ----------
local R = WorkshopConfig.Range
moveTo(alice, Vector3.new(0, 3, 0))
check(RangeService.Start(alice) == false, "außerhalb des Felds keine Runde")
moveTo(alice, Vector3.new(-60, 3, 60))
check(RangeService.Start(alice) == true and alice:GetAttribute("RangeActive") == true, "Runde gestartet")
check(alice:GetAttribute("InSafeZone") == true, "Stand liegt in der Safe Zone")
step(1.5)
local targets = RangeService.Targets(alice)
check(targets and #targets == 2, "ein Ziel steht (Scheibe und Mitte)")
local bull = targets and targets[2]
RangeService.Hit(alice, bull)
check(RangeService.Current().Score == R.Bullseye, "Mitte zählt " .. R.Bullseye)
check(#(RangeService.Targets(alice) or {}) == 0, "getroffenes Ziel klappt weg")
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local bob = SIM.Join("Bob")
step(2)
enter(bob)
moveTo(bob, Vector3.new(-61, 3, 61))
check(RangeService.Start(bob) == false and RangeService.Targets(bob) == nil, "besetzt: Bob muss warten")
RangeService.Current().Score = R.DailyScore -- genug für die Tagesbelohnung
before = coins()
step(R.Duration)
check(RangeService.Current() == nil and alice:GetAttribute("RangeActive") == nil, "Runde vorbei")
check(data().RangeBest == R.DailyScore and coins() == before + R.DailyCoins, "Bestwert und Tagesbelohnung")
check(RangeService.Start(alice) == true, "neue Runde")
RangeService.Current().Score = R.DailyScore + 50
moveTo(alice, Vector3.new(0, 3, 0))
step(0.5)
check(RangeService.Current() == nil and data().RangeBest == R.DailyScore + 50 and coins() == before + R.DailyCoins,
	"Feld verlassen beendet die Runde, neuer Bestwert, Belohnung nur einmal am Tag")

if failures == 0 then
	print("Werkbank, Funkaufträge, Schießstand: alles in Ordnung")
end

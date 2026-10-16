-- Eigenes Versteck (HideoutService): erst ab Spielerlevel 4; Ausbauen nur am Versteck, mit Münzen und Items (aus Lager oder Tasche), Stufen
-- nacheinander bis zum Maximum; Werkbank gibt Rabatt am Stand, Sanistation verkürzt das Heilen, Feldbett gibt mehr Leben
-- (Wert für AgentService), Generator erzeugt Münzen mit der Zeit (auch offline, höchstens 8 h) und zahlt beim Abholen aus;
-- alles bleibt im Profil.
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
local store = SIM.DataStore("PlayerData_v1")
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
HideoutService.Init()

store.Data.u1 = { XP = {}, Coins = 200000, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)
enter(alice)
local function coins()
	return ProgressService.Get(alice).Coins
end
local function data()
	return HideoutConfig.Data(alice)
end

-- erst ab Spielerlevel 4
local LevelConfig = require("LevelConfig")
moveTo(alice, Vector3.new(52, 3, 2))
check(HideoutConfig.Unlocked(alice) == false, "Level 1: Versteck gesperrt")
check(HideoutService.Upgrade(alice, "Bed") == false, "Level 1: kein Ausbau")
check(string.find(lastExt(alice, "Status")[2], "ab Level 4", 1, true) ~= nil, "Hinweis: ab Level 4")
check(HideoutService.Collect(alice) == 0, "Level 1: kein Abholen")
local level4XP = 0
for level = 1, HideoutConfig.MinLevel - 1 do
	level4XP += LevelConfig.XPForLevel(level)
end
alice:SetAttribute("AccountXP", level4XP - 1)
check(HideoutConfig.Unlocked(alice) == false, "knapp unter Level 4: gesperrt")
ProgressService.Get(alice).AccountXP = level4XP
alice:SetAttribute("AccountXP", level4XP)
check(HideoutConfig.Unlocked(alice) == true, "Level 4: freigeschaltet")

-- nur am Versteck
moveTo(alice, Vector3.new(0, 3, 0))
check(HideoutService.Upgrade(alice, "Bed") == false, "nicht am Versteck: kein Ausbau")
check(string.find(lastExt(alice, "Status")[2], "Versteck", 1, true) ~= nil, "Hinweis: ins Versteck")
moveTo(alice, Vector3.new(52, 3, 2))

-- Feldbett Stufe 1 (nur Münzen), Stufe 2 braucht Verbände
local before = coins()
check(HideoutService.Upgrade(alice, "Bed") == true, "Feldbett gebaut")
check(HideoutService.Upgrade(alice, "Bed", 1) == false, "Doppelklick: Stufe 1 ist schon gebaut, keine zweite Stufe")
check(coins() == before - HideoutConfig.Get("Bed").Levels[1].Coins, "Münzen bezahlt")
check(HideoutConfig.Level(data(), "Bed") == 1 and HideoutConfig.Value(alice, "Bed") == 5, "Stufe 1: +5 Leben")
check(HideoutConfig.Tier(alice) == 1, "Level 4: Versteckstufe 1 gratis")
check(HideoutService.Upgrade(alice, "Bed") == false, "Feldbett 2 braucht Versteckstufe 2")
check(string.find(lastExt(alice, "Status")[2], "Versteckstufe 2", 1, true) ~= nil, "Hinweis: Versteckstufe 2")
check(HideoutService.UpgradeTier(alice) == false, "Werkstatt mit Münzen erst ab Level 10")
check(string.find(lastExt(alice, "Status")[2], "ab Level 10", 1, true) ~= nil, "Hinweis: ab Level 10")
check(HideoutService.GrantTier(alice, 3) == true and HideoutConfig.Tier(alice) == 3, "Robux: Bunker sofort, ohne Level")
check(HideoutService.GrantTier(alice, 2) == false and HideoutConfig.Tier(alice) == 3, "niedrigere Stufe ändert nichts")
check(HideoutService.Upgrade(alice, "Bed") == false, "Stufe 2 ohne Verbände nicht")
check(string.find(lastExt(alice, "Status")[2], "Verband", 1, true) ~= nil, "Hinweis: Verbände fehlen")
InventoryService.Give(alice, "Bandage", 3, nil, "Hotbar")
check(HideoutService.Upgrade(alice, "Bed") == true, "Stufe 2 mit Verbänden")
local left = 0
for _, entry in bagOf(alice) do
	if entry.Id == "Bandage" then
		left += entry.N
	end
end
check(left == 0, "Verbände verbraucht")
InventoryService.Give(alice, "Medkit", 2, nil, "Hotbar")
check(HideoutService.Upgrade(alice, "Bed") == true, "Stufe 3")
check(HideoutService.Upgrade(alice, "Bed") == false and HideoutConfig.Value(alice, "Bed") == 15, "ganz ausgebaut (+15)")

-- Werkbank: Rabatt am Stand
check(HideoutService.Upgrade(alice, "Workbench") == true, "Werkbank gebaut")
moveTo(alice, Vector3.new(-36, 3, 28))
before = coins()
check(InventoryService.Buy(alice, "Stand_Weapons", "SMG") == true, "MP gekauft")
check(coins() == before - math.floor(550 * 0.95), "5 % Rabatt (" .. (before - coins()) .. ")")

-- Sanistation: schneller heilen
moveTo(alice, Vector3.new(52, 3, 2))
check(HideoutService.Upgrade(alice, "Medical") == true, "Sanistation gebaut")
moveTo(alice, Vector3.new(0, 3, 160))
alice.Character.Humanoid.Health = 50
InventoryService.Give(alice, "Medkit", 1, nil, "Hotbar")
local medSlot
for _, entry in bagOf(alice) do
	if entry.Id == "Medkit" and entry.S <= ExtinctionConfig.HotbarSlots then
		medSlot = entry.S
	end
end
InventoryService.Use(alice, medSlot)
local useStart = lastExt(alice, "UseStart")
check(useStart and math.abs(useStart[3] - 6 * 0.85) < 0.01, "Medikit 15 % schneller (" .. tostring(useStart and useStart[3]) .. ")")
step(6)

-- Generator: erzeugt mit der Zeit, höchstens 8 h, Abholen zahlt aus
moveTo(alice, Vector3.new(52, 3, 2))
check(HideoutService.Upgrade(alice, "Generator") == true, "Generator gebaut")
local stored = ProgressService.Get(alice).Hideout
stored.GenAt -= 3600 -- eine Stunde ist vergangen
HideoutService.Publish(alice)
check(HideoutConfig.Pending(data(), os.time()) == 120, "eine Stunde: 120 Münzen")
before = coins()
check(HideoutService.Collect(alice) == 120 and coins() == before + 120, "abgeholt")
check(HideoutConfig.Pending(data(), os.time()) == 0, "danach wieder bei 0")
stored.GenAt -= 24 * 3600
HideoutService.Publish(alice)
check(HideoutConfig.Pending(data(), os.time()) == 8 * 120, "höchstens 8 Stunden")

-- Generator Stufe 2 braucht ein Quad: ein ausgeparktes zählt nicht (sonst Ausbau und Fahrzeug behalten)
InventoryService.Give(alice, "V_Quad", 1)
local quad = nil
for _, item in InventoryService.GetBag(alice).Slots do
	if item.Id == "V_Quad" then
		quad = item
	end
end
quad.Out = true
before = coins()
check(HideoutService.Upgrade(alice, "Generator") == false and coins() == before and HideoutConfig.Level(data(), "Generator") == 1,
	"ausgeparktes Quad zählt nicht für den Ausbau")
quad.Out = nil
check(HideoutService.Upgrade(alice, "Generator") == true and HideoutConfig.Level(data(), "Generator") == 2, "eingepacktes Quad: Stufe 2")
check(InventoryService.CountEverywhere(alice, "V_Quad") == 0, "Quad verbraucht")

-- im Profil gespeichert
check(stored.Bed == 3 and stored.Workbench == 1 and stored.Medical == 1 and stored.Generator == 2 and stored.Tier == 3,
	"Stufen im Profil")

-- Versteckstufe 4 mit Münzen: ab Level 35, mit Items
local level35XP = 0
for level = 1, 34 do
	level35XP += LevelConfig.XPForLevel(level)
end
ProgressService.Get(alice).AccountXP = level35XP
alice:SetAttribute("AccountXP", level35XP)
local top = HideoutConfig.Tiers[4]
check(HideoutService.UpgradeTier(alice, 4) == false and HideoutConfig.Tier(alice) == 3, "Kommandozentrale ohne Items nicht")
for _, need in top.Items do
	InventoryService.GiveStash(alice, need[1], need[2])
end
before = coins()
check(HideoutService.UpgradeTier(alice, 5) == false, "Doppelklick: falsche Ziel-Stufe baut nicht")
check(HideoutService.UpgradeTier(alice, 4) == true and HideoutConfig.Tier(alice) == 4, "Kommandozentrale gebaut")
check(coins() == before - top.Coins, "Münzen für die Stufe bezahlt")
check(InventoryService.CountEverywhere(alice, "V_Pickup") == 0, "Items für die Stufe verbraucht")
check(HideoutService.UpgradeTier(alice) == false, "höchste Stufe erreicht")

-- Lagerregal: mehr Plätze im Lager
local stashSize = function()
	return #HttpService:JSONDecode(alice:GetAttribute("ExtStash") or "[]")
end
InventoryService.GiveStash(alice, "Bandage", 400) -- Lager mit Verbänden füllen (10 pro Platz)
local full = stashSize()
check(full == ExtinctionConfig.StashSlots, "Lager voll mit " .. ExtinctionConfig.StashSlots .. " Plätzen (" .. full .. ")")
check(HideoutService.Upgrade(alice, "Shelf") == true, "Lagerregal gebaut")
InventoryService.GiveStash(alice, "Bandage", 400)
check(stashSize() == ExtinctionConfig.StashSlots + 10, "10 Plätze mehr (" .. stashSize() .. ")")
InventoryService.TakeEverywhere(alice, "Bandage", 1000)
InventoryService.GiveStash(alice, "V_Quad", 1)
check(HideoutService.Upgrade(alice, "Shelf") == true and HideoutConfig.StashBonus(data()) == 20, "Lagerregal 2: +20")

-- Munitionspresse: Pakete mit der Zeit, Sorte wählbar, ins Lager
InventoryService.GiveStash(alice, "Ammo_Rifle", 90)
check(HideoutService.Upgrade(alice, "AmmoPress") == true, "Munitionspresse gebaut")
stored.PressAt -= 3600
HideoutService.Publish(alice)
check(HideoutConfig.PressPending(data(), os.time()) == 1, "eine Stunde: 1 Paket")
local ammoBefore = InventoryService.CountEverywhere(alice, "Ammo_9mm")
check(HideoutService.CollectPress(alice) == 30, "30 Schuss 9mm abgeholt")
check(InventoryService.CountEverywhere(alice, "Ammo_9mm") == ammoBefore + 30, "9mm im Lager")
check(HideoutService.SetPressAmmo(alice, "Ammo_Rifle") == true and HideoutConfig.PressAmmoOf(data()) == "Ammo_Rifle", "Sorte gewechselt")
check(HideoutService.SetPressAmmo(alice, "Rifle") == false, "nur Munition wählbar")
stored.PressAt -= 100 * 3600
HideoutService.Publish(alice)
check(HideoutConfig.PressPending(data(), os.time()) == 8, "höchstens 8 Stunden")
ammoBefore = InventoryService.CountEverywhere(alice, "Ammo_Rifle")
check(HideoutService.CollectPress(alice) == 8 * 30 and InventoryService.CountEverywhere(alice, "Ammo_Rifle") == ammoBefore + 240,
	"8 Pakete Gewehrmunition")

-- Funkgerät: ein Tagesauftrag, einmal abholen
local radioJob = HideoutConfig.RadioTask(HideoutConfig.Day())
check(HideoutService.ClaimRadio(alice) == false, "Funkauftrag noch nicht erledigt")
ProgressService.AddStat(alice, radioJob.Stat, radioJob.Need)
before = coins()
check(HideoutService.ClaimRadio(alice) == true and coins() == before + HideoutConfig.Radio.Coins, "Funkauftrag abgeholt")
check(HideoutService.ClaimRadio(alice) == false, "nur einmal am Tag")
check(HideoutConfig.Data(alice).Radio.Claimed == true, "am Client sichtbar")

-- gesperrter Spieler (Level 1) kauft eine Stufe mit Robux: Versteck sofort offen
local RobuxConfig = require("RobuxConfig")
local RobuxService = require("RobuxService")
local tierProduct = RobuxConfig.Product("HideoutTier2")
check(tierProduct ~= nil and tierProduct.HideoutTier == 2 and tierProduct.Shop == false, "Robux-Produkt Werkstatt")
RobuxConfig.ByProductId = function(id)
	return id == 777 and tierProduct or nil
end
RobuxService.Init()
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local bob = SIM.Join("Bob")
step(2)
check(HideoutConfig.Unlocked(bob) == false, "Bob (Level 1) gesperrt")
local result
task.spawn(function()
	result = game:GetService("MarketplaceService").ProcessReceipt({ PlayerId = bob.UserId, ProductId = 777, PurchaseId = "p1" })
end)
step(5)
check(result == Enum.ProductPurchaseDecision.PurchaseGranted, "Kauf bestätigt")
check(HideoutConfig.Tier(bob) == 2 and HideoutConfig.Unlocked(bob), "Werkstatt mit Robux, trotz Level 1")

-- alter Spielstand ohne Versteckstufe: Stufe so hoch wie das höchste Modul
store.Data.u3 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {}, Hideout = { Bed = 3, Generator = 1 } }
local carl = SIM.Join("Carl")
step(2)
HideoutService.Publish(carl)
check(HideoutConfig.Tier(carl) == 3, "alter Stand: Versteckstufe 3")

if failures == 0 then
	print("Versteck in Ordnung")
end

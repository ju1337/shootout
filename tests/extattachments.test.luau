-- Waffen-Aufsätze in der offenen Welt: als Items kaufen (Seltenheit 4 nur zu finden), auf eine Waffe ziehen baut an
-- (Item weg, Feld A an der Waffe), Wirkung über AttachmentConfig nur von der Waffe in der Hand (Lobby-Aufsätze gelten
-- nicht), Taste mit der Waffe in der Hand ersetzt (alter Aufsatz zurück in die Tasche), Abnehmen, Aufsätze bleiben beim
-- Tod an der Waffe (Tasche am Boden), Speichern prüft die Aufsätze, Beute-Tabellen enthalten Aufsätze.
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

local AttachmentConfig = require("AttachmentConfig")
local Inventory = require("Inventory")

store.Data.u1 = { XP = {}, Coins = 5000, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)
enter(alice)

-- Items und Stand
check(ExtinctionConfig.Get("Att_Compensator") and ExtinctionConfig.Get("Att_Compensator").Kind == "Attachment", "Aufsatz-Item")
check(ExtinctionConfig.Get("Att_Suppressor").Price == nil and ExtinctionConfig.Get("Att_Compensator").Price == nil,
	"Aufsätze sind nicht zu kaufen")
local atStand = false
for _, id in ExtinctionConfig.Stands.Stand_Weapons.Items do
	atStand = atStand or string.sub(id, 1, 4) == "Att_"
end
check(not atStand, "kein Aufsatz am Waffenstand")
check(ExtinctionConfig.SellPrice("Att_Compensator", 1) > 0, "Aufsätze lassen sich verkaufen")
local inLoot = false
for _, entry in ExtinctionConfig.LootTables.Airdrop do
	inLoot = inLoot or entry.Id == "Att_Suppressor"
end
check(inLoot, "Schalldämpfer selten in Lootdrops")
check(#ExtinctionConfig.LootTables.ConvoyAttachments == #ExtinctionConfig.AttachmentItems, "Konvoi: alle Aufsätze möglich")
for _, name in { "Zombie", "Zombie2", "Tier1", "Tier2", "Tier3", "Medical", "Ammo" } do
	for _, entry in ExtinctionConfig.LootTables[name] do
		check(string.sub(entry.Id, 1, 4) ~= "Att_", "kein Aufsatz in " .. name)
	end
end
check(ExtinctionConfig.Convoy.Attachments and ExtinctionConfig.Convoy.Attachments[1] >= 1, "Konvoi bringt sicher Aufsätze")

moveTo(alice, Vector3.new(-36, 3, 28))
check(InventoryService.Buy(alice, "Stand_Weapons", "Rifle") == true, "Sturmgewehr gekauft")
check(InventoryService.Buy(alice, "Stand_Weapons", "Ammo_Rifle", 2) == true, "Munition gekauft")
check(InventoryService.Buy(alice, "Stand_Weapons", "Att_ExtendedMag") == false, "Magazin nicht zu kaufen")
check(InventoryService.Give(alice, "Att_ExtendedMag", 1) == 1, "erweitertes Magazin (aus dem Konvoi)")
check(InventoryService.Give(alice, "Att_Compensator", 1) == 1, "Kompensator (aus dem Konvoi)")
local rifleSlot, magSlot, compSlot
for s = 1, ExtinctionConfig.BagSlots do
	local entry = slot(alice, s)
	if entry and entry.Id == "Rifle" then rifleSlot = s end
	if entry and entry.Id == "Att_ExtendedMag" then magSlot = s end
	if entry and entry.Id == "Att_Compensator" then compSlot = s end
end
check(rifleSlot and magSlot and compSlot, "alles in der Tasche")

-- auf die Waffe ziehen: anbauen
check(InventoryService.Move(alice, "Bag", magSlot, "Bag", rifleSlot) == true, "Magazin auf das Gewehr gezogen")
local rifle = slot(alice, rifleSlot)
check(rifle and type(rifle.A) == "table" and rifle.A.Magazine == "ExtendedMag", "Magazin hängt am Gewehr")
check(slot(alice, magSlot) == nil, "Aufsatz-Item ist weg")
check(InventoryService.Move(alice, "Bag", compSlot, "Bag", rifleSlot) == true, "Kompensator angebaut")
rifle = slot(alice, rifleSlot)
check(rifle.A.Muzzle == "Compensator" and rifle.A.Magazine == "ExtendedMag", "zwei Aufsätze am Gewehr")

-- Lobby-Aufsätze gelten in der offenen Welt nicht
alice:SetAttribute("Attachments", HttpService:JSONEncode({ Owned = { Rifle = { DrumMag = true } },
	Equipped = { Rifle = { Magazine = "DrumMag" } } }))
check(AttachmentConfig.Effects(alice, "Rifle").Mag == 1, "ohne Waffe in der Hand keine Wirkung (auch nicht aus der Lobby)")

-- in die Hand: Wirkung und Magazin
if rifleSlot > ExtinctionConfig.HotbarSlots then
	InventoryService.Move(alice, "Bag", rifleSlot, "Bag", 1)
	rifleSlot = 1
end
moveTo(alice, Vector3.new(0, 3, 160))
InventoryService.Use(alice, rifleSlot)
check(WeaponService.CarriedWeapon(alice) == "Rifle", "Gewehr in der Hand")
local effects = AttachmentConfig.Effects(alice, "Rifle")
check(math.abs(effects.Mag - 1.34) < 1e-6 and math.abs(effects.Recoil - 0.8) < 1e-6, "Wirkung der angebauten Aufsätze")
-- Sturmgewehr: erweitertes Magazin = 40 Schuss (nur hier, andere Waffen +30 %)
check(math.floor(require("WeaponConfig").Get("Rifle").MagazineSize * effects.Mag) == 40, "Sturmgewehr mit erweitertem Magazin: 40 Schuss")
local list = AttachmentConfig.EquippedList(alice, "Rifle")
check(#list == 2, "Modell zeigt beide Aufsätze (" .. #list .. ")")
local ammo = lastAmmo(alice)
check(ammo and ammo[1] == "Rifle", "Munitionsanzeige")

-- Taste mit der Waffe in der Hand: ersetzt, alter Aufsatz kommt in die Tasche
InventoryService.Give(alice, "Att_FastMag", 1)
local fastSlot
for s = 1, ExtinctionConfig.HotbarSlots do
	local entry = slot(alice, s)
	if entry and entry.Id == "Att_FastMag" then fastSlot = s end
end
check(fastSlot ~= nil, "Schnellmagazin auf der Hotbar")
InventoryService.Use(alice, fastSlot)
rifle = slot(alice, rifleSlot)
check(rifle.A.Magazine == "FastMag", "Schnellmagazin ersetzt das erweiterte")
check(WeaponService.CarriedWeapon(alice) == "Rifle", "Gewehr bleibt in der Hand")
local back = false
for _, entry in bagOf(alice) do
	back = back or entry.Id == "Att_ExtendedMag"
end
check(back, "erweitertes Magazin zurück in der Tasche")
effects = AttachmentConfig.Effects(alice, "Rifle")
check(effects.Mag == 1 and math.abs(effects.Reload - 0.75) < 1e-6, "neue Wirkung sofort")

-- abnehmen
check(InventoryService.Detach(alice, rifleSlot, "Magazine") == true, "Magazin abgenommen")
rifle = slot(alice, rifleSlot)
check(rifle.A and rifle.A.Magazine == nil and rifle.A.Muzzle == "Compensator", "nur das Magazin ist ab")
check(InventoryService.Detach(alice, rifleSlot, "Grip") == false, "leerer Platz: nichts abzunehmen")

-- Tod / Tasche am Boden: Aufsätze bleiben an der Waffe
local items = InventoryService.TakeAll(alice)
local found = nil
for _, item in items do
	if item.Id == "Rifle" then
		found = item
	end
end
check(found and found.Att and found.Att.Muzzle == "Compensator", "Aufsatz bleibt an der Waffe in der Tasche am Boden")
check(alice:GetAttribute("ExtAttach") == nil, "keine Waffe mehr in der Hand: keine Wirkung")

-- Speichern/Laden: ungültige Aufsätze fallen weg
local loaded = Inventory.FromList({ { S = 1, Id = "Rifle", N = 1, A = { Muzzle = "Compensator", Grip = "DrumMag", Barrel = "Quatsch" } },
	{ S = 2, Id = "Bandage", N = 1, A = { Muzzle = "Compensator" } } }, 10)
check(loaded.Slots[1].Att and loaded.Slots[1].Att.Muzzle == "Compensator" and loaded.Slots[1].Att.Grip == nil
	and loaded.Slots[1].Att.Barrel == nil, "falscher Platz und unbekannte Aufsätze fallen weg")
check(loaded.Slots[2].Att == nil, "nur Waffen haben Aufsätze")
local again = Inventory.FromList(Inventory.ToList(loaded), 10)
check(again.Slots[1].Att.Muzzle == "Compensator", "Aufsätze überstehen Speichern und Laden")

-- Nicht jeder Aufsatz passt auf jede Waffe: Laden legt unpassende zurück (Tasche voll -> Lager)
local fitLoose = {}
local fitLoaded = Inventory.FromList({ { S = 1, Id = "Revolver", N = 1, A = { Grip = "VerticalGrip", Barrel = "LongBarrel" } } },
	10, fitLoose)
check(fitLoaded.Slots[1].Att and fitLoaded.Slots[1].Att.Barrel == "LongBarrel" and fitLoaded.Slots[1].Att.Grip == nil,
	"Griff fällt vom Revolver ab, langer Lauf bleibt")
check(#fitLoose == 1 and fitLoose[1] == "VerticalGrip", "abgenommener Griff wird gemeldet")

-- Anbauen: Griff passt nicht auf den Revolver
check(InventoryService.Give(alice, "Revolver", 1) == 1, "Revolver bekommen")
check(InventoryService.Give(alice, "Att_VerticalGrip", 1) == 1, "Vertikalgriff bekommen")
local revolverSlot, gripSlot
for s = 1, ExtinctionConfig.BagSlots do
	local entry = slot(alice, s)
	if entry and entry.Id == "Revolver" then revolverSlot = s end
	if entry and entry.Id == "Att_VerticalGrip" then gripSlot = s end
end
check(revolverSlot and gripSlot, "Revolver und Griff in der Tasche")
check(InventoryService.Move(alice, "Bag", gripSlot, "Bag", revolverSlot) == false, "Griff lässt sich nicht an den Revolver bauen")
check(slot(alice, revolverSlot).A == nil, "Revolver ohne Aufsatz")
check(slot(alice, gripSlot) and slot(alice, gripSlot).Id == "Att_VerticalGrip", "Griff bleibt in der Tasche")
local fitStatus = lastExt(alice, "Status")
check(fitStatus and string.find(tostring(fitStatus[2]), "passt nicht", 1, true), "Meldung: passt nicht")

-- alter Spielstand mit Griff am Revolver: Griff kommt beim Laden ins Lager
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {}, Extinction = {
	Bag = { { S = 1, Id = "Revolver", N = 1, A = { Grip = "AngledGrip", Barrel = "ShortBarrel" } } }, Stash = {}, Safe = {} } }
local bob = SIM.Join("Bob")
Instance.new("Backpack", bob).Name = "Backpack"
step(2)
enter(bob)
step(2)
local bobBag = bagOf(bob)
local bobStash = HttpService:JSONDecode(bob:GetAttribute("ExtStash") or "[]")
local bobRevolver, bobGrip = nil, false
for _, entry in bobBag do
	if entry.Id == "Revolver" then bobRevolver = entry end
end
for _, entry in bobStash do
	bobGrip = bobGrip or entry.Id == "Att_AngledGrip"
end
check(bobRevolver and bobRevolver.A and bobRevolver.A.Barrel == "ShortBarrel" and bobRevolver.A.Grip == nil,
	"alter Spielstand: Griff vom Revolver abgenommen")
check(bobGrip, "alter Spielstand: Griff liegt im Lager statt gelöscht")

if failures == 0 then
	print("Waffen-Aufsätze in der offenen Welt in Ordnung")
end

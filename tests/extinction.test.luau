-- Offene Welt (EXTINCTION): Safe Zone und PvP-Zeit, Kaufen am Stand (Nähe, Münzen, Platz), Hotbar (Waffe nur
-- draußen, Wegstecken in der Safe Zone), Munition aus dem Inventar (Nachladen, Magazin am Item), Heilen mit Dauer,
-- Verkaufen, keine automatische Lebensregeneration, Lager (nur am Lager, bleibt beim Tod), Tod draußen = Tasche am Boden, Looten durch andere,
-- Verlassen draußen nur mit zweitem Klick und dann ohne Tasche, Verlassen in der Safe Zone behält alles
-- (Anordnung bleibt), Spiel verlassen draußen = Tasche weg (vor dem Speichern), Herunterfahren ohne Verlust,
-- PvP nur wenn beide draußen und ihre PvP-Zeit erreicht haben
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

-- wie in Roblox: jeder Charakter bekommt das Standard-Skript "Health" (heilt ständig nach)
local makeRig = SIM.MakeRig
SIM.MakeRig = function(name)
	local model = makeRig(name)
	Instance.new("Script", model).Name = "Health"
	return model
end

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

store.Data.u1 = { XP = {}, Coins = 5000, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 300, Rap = 0, Owned = {}, Equipped = {} }
local alice, bob = SIM.Join("Alice"), SIM.Join("Bob")
for _, player in { alice, bob } do
	Instance.new("Backpack", player).Name = "Backpack"
end
step(2)
check(Extinction.CanJoin(alice) == true, "Spielstand geladen: Beitreten möglich")

-- ---------- Ankunft in der Safe Zone ----------
enter(alice)
check(alice.Character ~= nil, "Alice gespawnt")
check(alice.Character:FindFirstChild("Health") == nil, "keine automatische Lebensregeneration (Health-Skript entfernt)")
check(alice:GetAttribute("InSafeZone") == true and alice:GetAttribute("CanFight") == false, "Spawn in der Safe Zone, kein Kampf")
check(alice.Character:GetAttribute("SafeZone") == true, "Charakter in der Safe Zone geschützt")
check(alice:GetAttribute("ExtBag") == "[]", "leere Tasche")
check(WeaponService.CarriedWeapon(alice) == nil, "keine Standardwaffe")
local ammo = lastAmmo(alice)
check(ammo ~= nil and ammo[1] == nil, "Munitionsanzeige: keine Waffe")
check(alice:GetAttribute("MapId") == "Extinction", "Map für Minimap und Licht gesetzt")

-- ---------- Kaufen ----------
moveTo(alice, Vector3.new(0, 3, 0))
check(InventoryService.Buy(alice, "Stand_Weapons", "Rifle") == false, "zu weit vom Stand weg")
check(string.find(lastExt(alice, "Status")[2], "näher", 1, true) ~= nil, "Hinweis: näher ran")
moveTo(alice, Vector3.new(-36, 3, 28))
check(InventoryService.Buy(alice, "Stand_Weapons", "Bandage") == false, "Verband gibt es nicht am Waffenstand")
check(InventoryService.Buy(alice, "Stand_Weapons", "Rifle") == true, "Sturmgewehr gekauft")
check(ProgressService.Get(alice).Coins == 5000 - 1100, "Preis abgezogen")
check(slot(alice, 1) and slot(alice, 1).Id == "Rifle", "Waffe landet auf Hotbar-Platz 1")
check(InventoryService.Buy(alice, "Stand_Weapons", "Ammo_Rifle", 2) == true, "zwei Packungen Gewehrmunition")
local ammoSlot = slot(alice, ExtinctionConfig.HotbarSlots + 1)
check(ammoSlot and ammoSlot.Id == "Ammo_Rifle" and ammoSlot.N == 60, "Munition hinten in der Tasche (60)")
check(InventoryService.Buy(alice, "Stand_Weapons", "Pistol") == true, "Pistole gekauft")
check(slot(alice, 2) and slot(alice, 2).Id == "Pistol", "Pistole auf Platz 2")
-- Verkauf einer geladenen Waffe: die Patronen im Magazin bleiben
do
	local bagState = InventoryService.GetBag(alice)
	local function count9mm()
		local n = 0
		for _, it in bagState.Slots do
			if it.Id == "Ammo_9mm" then
				n += it.Count
			end
		end
		return n
	end
	InventoryService.Buy(alice, "Stand_Weapons", "Pistol")
	local extra
	for s, it in bagState.Slots do
		if it.Id == "Pistol" and s ~= 2 then
			extra = s
		end
	end
	local ammoBefore = count9mm()
	bagState.Slots[extra].Mag = 7
	check(InventoryService.Sell(alice, extra) == true and bagState.Slots[extra] == nil and count9mm() == ammoBefore + 7,
		"verkaufte Pistole gibt ihre 7 Patronen zurück (" .. count9mm() - ammoBefore .. ")")
	for s, it in bagState.Slots do -- spätere Prüfungen erwarten keine 9mm-Munition
		if it.Id == "Ammo_9mm" then
			bagState.Slots[s] = nil
		end
	end
	InventoryService.Changed(alice)
end
moveTo(alice, Vector3.new(36, 3, 28))
check(InventoryService.Buy(alice, "Stand_Items", "Bandage", 3) == true, "drei Verbände")
check(slot(alice, 3) and slot(alice, 3).N == 3, "Verbände gestapelt auf Platz 3")
check(InventoryService.Buy(bob, "Stand_Items", "Bandage") == false, "Bob ist nicht in der offenen Welt")
-- manipulierte Zahlen vom Client (NaN, unendlich) dürfen Münzen und Stapel nicht kaputt machen
local before = ProgressService.Get(alice).Coins
Remotes.ExtAction.OnServerEvent:Fire(alice, "Buy", "Stand_Items", "Bandage", 0 / 0)
Remotes.ExtAction.OnServerEvent:Fire(alice, "Buy", "Stand_Items", "Bandage", math.huge)
check(ProgressService.Get(alice).Coins == before - 2 * 25, "NaN und unendlich zählen als 1 ("
	.. tostring(ProgressService.Get(alice).Coins) .. ")")
Remotes.ExtAction.OnServerEvent:Fire(alice, "Sell", 3, 0 / 0)
local stack = slot(alice, 3)
check(stack == nil or (stack.N == stack.N and stack.N >= 0), "Verkauf mit NaN macht den Stapel nicht kaputt")
InventoryService.Buy(alice, "Stand_Items", "Bandage", 3)
for s = 1, ExtinctionConfig.BagSlots do
	local entry = slot(alice, s)
	if entry and entry.Id == "Bandage" and s ~= 3 then
		InventoryService.Move(alice, "Bag", s, "Bag", 3)
	end
end

-- ---------- Hotbar: Waffe nur draußen ----------
InventoryService.Use(alice, 1)
check(WeaponService.CarriedWeapon(alice) == nil, "in der Safe Zone keine Waffe in der Hand")
check(string.find(lastExt(alice, "Status")[2], "gesichert", 1, true) ~= nil, "Hinweis: Waffen gesichert")
moveTo(alice, Vector3.new(0, 3, 160))
check(alice:GetAttribute("InSafeZone") == false and alice:GetAttribute("CanFight") == false, "Spawnschutz: noch kein Kampf")
check(math.abs((alice:GetAttribute("ProtectedUntil") or 0) - (workspace:GetServerTimeNow() + ExtinctionConfig.SpawnProtection)) < 0.6,
	"Spawnschutz läuft " .. ExtinctionConfig.SpawnProtection .. " Sekunden")
local protectedHumanoid = alice.Character.Humanoid
check(Damage.Apply(alice.Character, protectedHumanoid, 30, nil) == 0 and protectedHumanoid.Health == 100,
	"Spawnschutz: kein Schaden (auch nicht von Zombies)")
check(alice:GetAttribute("PvP") == false and alice.Character:GetAttribute("SafeZone") == nil, "PvP noch nicht an, Schutz weg")
check(math.abs(alice:GetAttribute("PvPAt") - (workspace:GetServerTimeNow() + 5)) < 0.6, "PvP-Zeit in 5 Sekunden")
step(5.2)
check(alice:GetAttribute("CanFight") == true and alice:GetAttribute("ProtectedUntil") == nil, "nach dem Spawnschutz: Kampf erlaubt")
check(alice:GetAttribute("PvP") == true, "nach 5 Sekunden PvP an")
InventoryService.Use(alice, 1)
check(WeaponService.CarriedWeapon(alice) == "Rifle", "Taste 1: Sturmgewehr in der Hand")
check(alice:GetAttribute("ExtEquipped") == 1, "Hotbar zeigt Platz 1 als aktiv")
ammo = lastAmmo(alice)
check(ammo[1] == "Rifle" and ammo[2] == 30 and ammo[3] == 60 and ammo[7] == false, "voll, Reserve 60 aus dem Inventar, nicht unendlich")

-- Schießen und Nachladen: Magazin am Item, Munition aus der Tasche (erst nach dem Ziehen, 0,3 s)
local head = alice.Character.Head
Remotes.Fire.OnServerEvent:Fire(alice, head.Position, Vector3.new(0, 0, 1), false, 1, {})
check(WeaponService.CarriedMag(alice) == 30, "direkt nach dem Ziehen noch kein Schuss")
step(0.4)
for i = 2, 6 do
	Remotes.Fire.OnServerEvent:Fire(alice, head.Position, Vector3.new(0, 0, 1), false, i, {})
	step(0.15)
end
step(1)
check(slot(alice, 1).Mag == 25, "Magazin steht am Item (25), war " .. tostring(slot(alice, 1).Mag))
Remotes.Reload.OnServerEvent:Fire(alice)
step(2.5)
check(WeaponService.CarriedMag(alice) == 30, "nachgeladen")
check(slot(alice, ExtinctionConfig.HotbarSlots + 1).N == 55, "5 Schuss aus der Tasche genommen")
ammo = lastAmmo(alice)
check(ammo[3] == 55, "Reserve-Anzeige 55")

-- Wechsel auf die Pistole: ohne passende Munition kein Nachladen
InventoryService.Use(alice, 2)
check(WeaponService.CarriedWeapon(alice) == "Pistol" and alice:GetAttribute("ExtEquipped") == 2, "Pistole in der Hand")
check(slot(alice, 1).Mag == 30, "Magazin des Gewehrs gesichert")
step(0.4)
Remotes.Fire.OnServerEvent:Fire(alice, head.Position, Vector3.new(0, 0, 1), false, 10, {})
step(0.5)
Remotes.Reload.OnServerEvent:Fire(alice)
step(2)
check(WeaponService.CarriedMag(alice) == 11, "ohne 9mm-Munition kein Nachladen")
InventoryService.Use(alice, 2)
check(WeaponService.CarriedWeapon(alice) == nil and alice:GetAttribute("ExtEquipped") == 0, "gleiche Taste: wegstecken")
InventoryService.Use(alice, 1)
check(WeaponService.CarriedWeapon(alice) == "Rifle" and WeaponService.CarriedMag(alice) == 30, "Gewehr wieder in der Hand")

-- Heilen dauert
alice.Character.Humanoid.Health = 50
InventoryService.Use(alice, 3)
check(alice.Character:GetAttribute("UsingItem") == "Verband", "Verband wird benutzt")
Remotes.Fire.OnServerEvent:Fire(alice, head.Position, Vector3.new(0, 0, 1), false, 20, {})
step(0.2)
check(WeaponService.CarriedMag(alice) == 30, "beim Verbinden kein Schuss")
step(1)
check(alice.Character.Humanoid.Health == 50, "noch nicht geheilt")
step(1.6)
check(alice.Character.Humanoid.Health == 70 and slot(alice, 3).N == 2, "+20 Leben, ein Verband weniger")

-- Zurück in die Safe Zone: Waffe weg, kein PvP
moveTo(alice, Vector3.new(10, 3, 20))
check(alice:GetAttribute("InSafeZone") == true and alice:GetAttribute("PvP") == false, "zurück in der Safe Zone")
check(WeaponService.CarriedWeapon(alice) == nil, "Waffe beim Betreten weggesteckt")
check(Damage.Apply(alice.Character, alice.Character.Humanoid, 30, nil) == 0, "in der Safe Zone kein Schaden")

-- ---------- Anordnen, Lager, Verkaufen ----------
check(InventoryService.Move(alice, "Bag", 3, "Bag", 9) == true, "Verbände auf Platz 9 gelegt")
check(slot(alice, 9) and slot(alice, 9).Id == "Bandage" and slot(alice, 3) == nil, "Platz 9 belegt, 3 frei")
check(InventoryService.Move(alice, "Bag", 2, "Stash", nil) == false, "Lager nur direkt am Lager")
moveTo(alice, Vector3.new(52, 3, -24))
check(InventoryService.Move(alice, "Bag", 2, "Stash", nil) == true, "Pistole ins Lager")
local stash = HttpService:JSONDecode(alice:GetAttribute("ExtStash"))
check(#stash == 1 and stash[1].Id == "Pistol" and stash[1].Mag == 11, "Pistole mit Magazin im Lager")
moveTo(alice, Vector3.new(36, 3, 28))
local coins = ProgressService.Get(alice).Coins
check(InventoryService.Sell(alice, 9, 1) == true, "einen Verband verkauft")
check(ProgressService.Get(alice).Coins == coins + ExtinctionConfig.SellPrice("Bandage", 1), "Verkaufspreis gutgeschrieben")
check(slot(alice, 9).N == 1, "ein Verband übrig")

-- ---------- Tod draußen: Tasche am Boden, Lager bleibt ----------
moveTo(alice, Vector3.new(0, 3, 200))
step(5.5)
InventoryService.Use(alice, 1)
step(0.4)
Remotes.Fire.OnServerEvent:Fire(alice, alice.Character.Head.Position, Vector3.new(0, 0, 1), false, 30, {})
step(0.5)
local deathPos = alice.Character.HumanoidRootPart.Position
alice.Character.Humanoid.Health = 0
step(0.2)
check(alice:GetAttribute("ExtBag") == "[]", "Tasche nach dem Tod leer")
local loot = workspace.ExtinctionLoot:GetChildren()
check(#loot == 1, "eine Tasche liegt am Boden")
local bagPart = loot[1] and loot[1]:FindFirstChild("LootBag")
local bagId = bagPart and bagPart:GetAttribute("LootBag")
local bagData = bagId and LootService.Get(bagId)
check(bagData ~= nil and #bagData.Container.Slots >= 3, "Gewehr, Munition und Verband in der Tasche")
local rifleInBag = nil
for _, item in bagData and bagData.Container.Slots or {} do
	if item.Id == "Rifle" then
		rifleInBag = item
	end
end
check(rifleInBag ~= nil and rifleInBag.Mag == 29, "Gewehr mit Magazin (29) in der Tasche")
check(bagPart and bagPart:FindFirstChildOfClass("ProximityPrompt") ~= nil, "Tasche mit E durchsuchbar")
check(#HttpService:JSONDecode(alice:GetAttribute("ExtStash")) == 1, "Lager behält die Pistole")
-- eigene Tasche auf Minimap und Karte: Attribut ExtDeathBag mit Ort und Ablaufzeit
local marker = alice:GetAttribute("ExtDeathBag") and HttpService:JSONDecode(alice:GetAttribute("ExtDeathBag"))
check(marker and marker.Id == bagId and math.abs(marker.X - deathPos.X) <= 1 and math.abs(marker.Z - deathPos.Z) <= 1,
	"Markierung der eigenen Tasche am Todesort")
check(marker and math.abs(marker.Ends - (workspace:GetServerTimeNow() + ExtinctionConfig.BagLifetime)) < 2, "Markierung mit Ablaufzeit")
local function lastBanner(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "Notify" and entry.Player == player and entry.Args[1] == "Banner" then
			return entry.Args[2]
		end
	end
	return nil
end
step(5.5)
check(alice.Character and alice.Character.Humanoid.Health > 0 and alice:GetAttribute("InSafeZone") == true, "Respawn in der Safe Zone")
local respawnBanner = lastBanner(alice)
check(respawnBanner and respawnBanner.Title == "DEINE TASCHE LIEGT DRAUSSEN", "nach dem Respawn: Hinweis auf die Tasche ("
	.. tostring(respawnBanner and respawnBanner.Title) .. ")")

-- ---------- Bob lootet die Tasche ----------
enter(bob)
check(LootService.Open(bob, bagId) == false, "zu weit weg zum Durchsuchen")
bob.Character:PivotTo(CFrame.new(deathPos + Vector3.new(3, 0, 0)))
step(0.3)
check(LootService.Open(bob, bagId) == true, "Bob öffnet die Tasche")
check(lastExt(bob, "Loot") ~= nil and #lastExt(bob, "Loot")[2].Items >= 3, "Inhalt an Bob geschickt")
-- Alles auf einmal nur mit dem Gamepass ALLES LOOTEN; F ohne Pass öffnet das Fenster (dort einzeln nehmen)
check(LootService.Take(bob, bagId, "All") == false and LootService.Get(bagId) ~= nil, "ohne Gamepass: nicht alles auf einmal")
local hint = lastExt(bob, "Status")
check(hint ~= nil and string.find(tostring(hint[2]), "ALLES LOOTEN", 1, true) ~= nil, "Hinweis auf den Gamepass")
local bagModel = LootService.Get(bagId).Part
bagModel.TakeAllPrompt.Triggered:Fire(bob)
check(LootService.Get(bagId) ~= nil and lastExt(bob, "Loot") ~= nil, "F ohne Gamepass: Tasche bleibt, Fenster offen")
bob:SetAttribute("Pass_LootAll", true)
check(LootService.Take(bob, bagId, "All") == true, "alles genommen")
local bobHasRifle = false
for _, entry in bagOf(bob) do
	if entry.Id == "Rifle" and entry.Mag == 29 then
		bobHasRifle = true
	end
end
check(bobHasRifle, "Bob hat das Gewehr mit Magazin")
check(LootService.Get(bagId) == nil and #workspace.ExtinctionLoot:GetChildren() == 0, "leere Tasche verschwindet")
check(alice:GetAttribute("ExtDeathBag") == nil, "Markierung weg, sobald die Tasche leer geräumt ist")
check(lastExt(bob, "LootClosed") ~= nil, "Fenster bei Bob geschlossen")

-- ---------- PvP: beide draußen und PvP-Zeit erreicht ----------
moveTo(alice, Vector3.new(0, 3, 230))
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 250)))
step(1)
local function shoot(shooter, target, id)
	local origin = shooter.Character.Head.Position
	local direction = (target.Character.Head.Position - origin).Unit
	Remotes.Fire.OnServerEvent:Fire(shooter, origin, direction, false, id,
		{ { Part = target.Character.Head, Position = target.Character.Head.Position } })
	step(0.3)
end
InventoryService.Use(bob, 1)
check(WeaponService.CarriedWeapon(bob) == "Rifle", "Bob zieht das Gewehr")
step(0.4)
shoot(bob, alice, 100)
check(alice.Character.Humanoid.Health == 100, "vor Ablauf der PvP-Zeit kein Schaden")
step(5)
shoot(bob, alice, 101)
check(alice.Character.Humanoid.Health < 100, "nach 5 Sekunden draußen: PvP-Schaden")
-- gemeldeter Kopftreffer, dessen Punkt gar nicht am Kopf liegt (an den Beinen): zählt nicht als Kopftreffer
local headDamage = 100 - alice.Character.Humanoid.Health
alice.Character.Humanoid.Health = 100
step(1)
do
	local origin = bob.Character.Head.Position
	local legs = alice.Character.HumanoidRootPart.Position - Vector3.new(0, 2.5, 0)
	Remotes.Fire.OnServerEvent:Fire(bob, origin, (legs - origin).Unit, false, 102,
		{ { Part = alice.Character.Head, Position = legs } })
	step(0.3)
end
check(100 - alice.Character.Humanoid.Health < headDamage,
	"falscher Kopftreffer: weniger Schaden als am Kopf (" .. (100 - alice.Character.Humanoid.Health) .. " / " .. headDamage .. ")")
alice.Character.Humanoid.Health = 100

-- ---------- Im Kampf: Safe Zone gesperrt (CombatUntil), danach wieder offen ----------
local now = workspace:GetServerTimeNow()
check((alice:GetAttribute("CombatUntil") or 0) > now and (bob:GetAttribute("CombatUntil") or 0) > now,
	"Treffer Spieler gegen Spieler: beide im Kampf")
moveTo(alice, Vector3.new(0, 3, 590))
step(0.5)
local aliceRoot = alice.Character.HumanoidRootPart
check(alice:GetAttribute("InSafeZone") ~= true and not Extinction.InSafeZone(aliceRoot.Position),
	"im Kampf nicht ins Safehouse (zurück an den Rand)")
step(ExtinctionConfig.CombatTime)

-- ---------- Safehouse: kein PvP, wird zum Spawnpunkt ----------
check(Extinction.InSafeZone(CENTER + Vector3.new(20, 0, 600)) and not Extinction.InSafeZone(CENTER + Vector3.new(0, 0, 660)),
	"Safehouse zählt als Safe Zone")
check(#Extinction.SafeZones() == 2, "Camp und Safehouse")
moveTo(alice, Vector3.new(0, 3, 590))
step(0.5)
check(alice:GetAttribute("InSafeZone") == true and alice:GetAttribute("PvP") == false, "im Safehouse kein PvP")
check(alice:GetAttribute("ExtHome") == "SAFEHOUSE TEST" and alice:GetAttribute("SafeZoneTitle") == "SAFEHOUSE TEST", "Spawnpunkt gesetzt")
local homeBanner = false
for _, entry in SIM.RemoteLog do
	if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" and entry.Args[2].Caption == "Spawnpunkt gesetzt" then
		homeBanner = true
	end
end
check(homeBanner, "Meldung: Spawnpunkt gesetzt")
moveTo(alice, Vector3.new(0, 3, 700))
step(0.5)
check(alice:GetAttribute("SafeZoneTitle") == nil and alice:GetAttribute("ExtHome") == "SAFEHOUSE TEST", "draußen bleibt der Spawnpunkt")
alice.Character.Humanoid.Health = 0
step(ExtinctionConfig.RespawnTime + 0.5)
local root = alice.Character and alice.Character:FindFirstChild("HumanoidRootPart")
check(root ~= nil and (root.Position - (CENTER + Vector3.new(0, 0, 610))).Magnitude < 12, "Respawn im Safehouse")
local emptyBanner = lastBanner(alice)
check(emptyBanner and emptyBanner.Title == "NICHTS VERLOREN" and alice:GetAttribute("ExtDeathBag") == nil,
	"leere Tasche: keine Tasche am Boden, Hinweis nach dem Respawn")
check(alice:GetAttribute("InSafeZone") == true, "nach dem Respawn in der Safe Zone")
moveTo(alice, Vector3.new(-12, 3, 594))
check(InventoryService.Buy(alice, "Stand_Weapons", "Ammo_Rifle", 1) == true, "Händler im Safehouse verkauft auch")
InventoryService.TakeAll(alice) -- Tasche wieder leer wie nach dem Respawn
-- zurück ins Camp: Spawnpunkt wieder das Camp
moveTo(alice, Vector3.new(0, 3, 20))
step(0.5)
check(alice:GetAttribute("ExtHome") == "CAMP PHOENIX", "Camp wieder Spawnpunkt")

-- ---------- Reisen: an der Haltestelle zu einer anderen Safe Zone ----------
check(Extinction.Travel(alice, "Test") == false, "weit weg von der Haltestelle: keine Reise")
moveTo(alice, Vector3.new(-36, 3, 12))
check(Extinction.Travel(alice, "") == false, "nicht dorthin, wo man schon ist")
check(Extinction.Travel(alice, "Gibtsnicht") == false, "unbekanntes Ziel")
check(Extinction.Travel(alice, "Test") == true, "Reise zum Safehouse")
step(0.3)
local travelRoot = alice.Character:FindFirstChild("HumanoidRootPart")
check(travelRoot and (travelRoot.Position - (CENTER + Vector3.new(0, 0, 610))).Magnitude < 12, "angekommen im Safehouse")
check(alice:GetAttribute("ExtHome") == "SAFEHOUSE TEST" and alice:GetAttribute("InSafeZone") == true, "dort Spawnpunkt, Safe Zone")
moveTo(alice, Vector3.new(-36, 3, 12))
check(Extinction.Travel(alice, "Test") == false, "kurz danach: Fahrer braucht einen Moment")
step(ExtinctionConfig.TravelCooldown + 0.5)
moveTo(alice, Vector3.new(0, 3, 20))

-- ---------- Verlassen draußen: zweiter Klick, Tasche fällt ----------
statusText = nil
manager.Join(bob, "Hub")
check(bob:GetAttribute("Mode") == "Extinction" and statusText ~= nil, "erster Klick: Warnung statt Verlassen")
manager.Join(bob, "Hub")
check(bob:GetAttribute("Mode") == "Hub", "zweiter Klick: verlassen")
check(#workspace.ExtinctionLoot:GetChildren() == 1, "Bobs Tasche liegt draußen")
check(#(ProgressService.Get(bob).Extinction.Bag) == 0, "Bobs Tasche im Profil leer")

-- ---------- Verlassen in der Safe Zone: alles bleibt, Anordnung auch ----------
moveTo(alice, Vector3.new(36, 3, 28))
InventoryService.Buy(alice, "Stand_Items", "Medkit")
InventoryService.Buy(alice, "Stand_Items", "Vest")
InventoryService.Move(alice, "Bag", 1, "Bag", 7)
local before = HttpService:JSONEncode(ProgressService.Get(alice).Extinction.Bag)
manager.Join(alice, "Hub")
check(alice:GetAttribute("Mode") == "Hub", "in der Safe Zone sofort verlassen")
check(HttpService:JSONEncode(ProgressService.Get(alice).Extinction.Bag) == before, "Tasche und Anordnung bleiben")
check(alice:GetAttribute("ExtBag") == nil, "Anzeige-Attribute weg")
enter(alice)
check(slot(alice, 7) and slot(alice, 7).Id == "Medkit", "nach dem Wiederkommen liegt alles am selben Platz")

-- ---------- Spiel verlassen draußen: Tasche weg, gespeichert ohne Inhalt ----------
moveTo(alice, Vector3.new(-200, 3, 0))
SIM.Leave(alice)
step(2)
local saved = store.Data.u1
check(saved and saved.Extinction and #saved.Extinction.Bag == 0, "gespeichert: Tasche leer")
check(saved and #saved.Extinction.Stash == 1, "gespeichert: Lager unverändert")
check(#workspace.ExtinctionLoot:GetChildren() == 2, "Alices Tasche liegt am Boden")

-- ---------- Herunterfahren: niemand verliert etwas ----------
store.Data.u3 = { XP = {}, Coins = 2000, Rap = 0, Owned = {}, Equipped = {},
	Extinction = { Bag = { { S = 1, Id = "SMG", N = 1, Mag = 20 } }, Stash = {} } }
local carl = SIM.Join("Carl")
Instance.new("Backpack", carl).Name = "Backpack"
step(2)
enter(carl)
check(slot(carl, 1) and slot(carl, 1).Id == "SMG" and slot(carl, 1).Mag == 20, "gespeicherte Tasche geladen")
moveTo(carl, Vector3.new(0, 3, -300))
local bagsBefore = #workspace.ExtinctionLoot:GetChildren()
task.spawn(function()
	for _, close in SIM.Closers do
		close()
	end
end)
-- Server fährt herunter: Spieler werden getrennt. ModeManager meldet sie dabei beim Modus ab (Reihenfolge zum
-- Speichern ist in Roblox nicht festgelegt, hier zuerst)
Extinction.RemovePlayer(carl)
SIM.Leave(carl)
step(30)
check(store.Data.u3.Extinction and #store.Data.u3.Extinction.Bag == 1, "beim Herunterfahren bleibt die Tasche")
check(#workspace.ExtinctionLoot:GetChildren() == bagsBefore, "beim Herunterfahren fällt keine Tasche")

-- Safe-Zone-Liste ist zwischengespeichert, folgt aber Änderungen (neues Safehouse, verschoben, entfernt)
local probe = CENTER + Vector3.new(900, 0, 0)
check(not Extinction.InSafeZone(probe) and Extinction.SafeZones() == Extinction.SafeZones(), "Liste zwischengespeichert")
local extra = Instance.new("Part", map.Zone)
extra.Name = "SafeZone_Neu"
extra.Size = Vector3.new(60, 40, 60)
extra.CFrame = CFrame.new(probe)
check(Extinction.InSafeZone(probe), "neues Safehouse sofort erkannt")
extra.CFrame = CFrame.new(probe + Vector3.new(500, 0, 0))
check(not Extinction.InSafeZone(probe) and Extinction.InSafeZone(probe + Vector3.new(500, 0, 0)), "verschobenes Safehouse erkannt")
extra:Destroy()
check(not Extinction.InSafeZone(probe + Vector3.new(500, 0, 0)), "entferntes Safehouse weg")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

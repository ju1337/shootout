-- Ausrüstungen (Loadouts) in der offenen Welt: SPEICHERN merkt sich die Anordnung der Tasche (Plätze, Ids, Anzahl,
-- Aufsätze), AUSRÜSTUNG 1/2 legt sie am Lager in der Safe Zone an: Übriges ins Lager, Teile aus Lager und Tasche auf ihre
-- Plätze (Waffen mit denselben Aufsätzen, lose Aufsätze werden angebaut), Fehlendes in der Meldung, draußen oder abseits
-- vom Lager geht nichts. Gespeichert im Profil (Extinction.Loadouts), Anzeige über ExtLoadouts.
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
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
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
local manager = {
	Join = function(player, modeId)
		if modeId ~= "Extinction" and player:GetAttribute("Mode") == "Extinction" then
			if Extinction.ConfirmLeave(player) then
				Extinction.RemovePlayer(player)
				player:SetAttribute("Mode", modeId)
			end
		end
	end,
	Status = function() end,
}
require("ExtDailyConfig").Enabled = false -- tägliche Kiste: eigener Test (extdaily)
require("ExtinctionConfig").Airdrop.FirstDelay = math.huge -- hier keine Lootdrops (eigener Test: airdrop)
require("ExtinctionConfig").Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
require("ExtinctionConfig").HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
require("ExtinctionConfig").Day.Fixed = 12 -- immer Tag (nachts mehr Zombies; eigener Test: daycycle)
require("ExtinctionConfig").Zombies.KindWeights = { Walker = 1 } -- nur normale Zombies (Schreier rufen sonst Verstärkung)
Extinction.Init(manager)

local function bagOf(player)
	return HttpService:JSONDecode(player:GetAttribute("ExtBag") or "[]")
end
local function stashOf(player)
	return HttpService:JSONDecode(player:GetAttribute("ExtStash") or "[]")
end
local function slot(player, s)
	for _, entry in bagOf(player) do
		if entry.S == s then
			return entry
		end
	end
	return nil
end
local function slotOf(player, id)
	for _, entry in bagOf(player) do
		if entry.Id == id then
			return entry.S
		end
	end
	return nil
end
local function find(list, id)
	for _, entry in list do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end
local function countIn(list, id)
	local n = 0
	for _, entry in list do
		if entry.Id == id then
			n += entry.N
		end
	end
	return n
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
local function statusText(player)
	local args = lastExt(player, "Status")
	return args and args[2] or ""
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
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)
enter(alice)

check(alice:GetAttribute("ExtLoadouts") == "[0,0]", "am Anfang zwei leere Ausrüstungen (Attribut da): " .. tostring(alice:GetAttribute("ExtLoadouts")))

-- Tasche einrichten: Gewehr mit zwei Aufsätzen auf Platz 1, Pistole auf 2, Munition, Medikits auf 9
moveTo(alice, Vector3.new(-36, 3, 28))
check(InventoryService.Buy(alice, "Stand_Weapons", "Rifle") == true, "Gewehr gekauft")
check(InventoryService.Buy(alice, "Stand_Weapons", "Pistol") == true, "Pistole gekauft")
check(InventoryService.Buy(alice, "Stand_Weapons", "Ammo_Rifle", 2) == true, "Munition gekauft")
check(InventoryService.Give(alice, "Att_Compensator", 1) == 1, "Kompensator")
check(InventoryService.Give(alice, "Att_ExtendedMag", 1) == 1, "erweitertes Magazin")
check(InventoryService.Give(alice, "Medkit", 2) == 2, "zwei Medikits")
local rifleSlot = slotOf(alice, "Rifle")
check(InventoryService.Move(alice, "Bag", slotOf(alice, "Att_Compensator"), "Bag", rifleSlot) == true, "Kompensator angebaut")
check(InventoryService.Move(alice, "Bag", slotOf(alice, "Att_ExtendedMag"), "Bag", rifleSlot) == true, "Magazin angebaut")
local rifle = slot(alice, rifleSlot)
check(rifle and rifle.A and rifle.A.Muzzle == "Compensator" and rifle.A.Magazine == "ExtendedMag", "Gewehr mit zwei Aufsätzen")
check(InventoryService.Move(alice, "Bag", slotOf(alice, "Medkit"), "Bag", 9) == true, "Medikits auf Platz 9")
if slotOf(alice, "Pistol") ~= 2 then
	InventoryService.Move(alice, "Bag", slotOf(alice, "Pistol"), "Bag", 2)
end
local layout = {}
for _, entry in bagOf(alice) do
	layout[entry.S] = { Id = entry.Id, N = entry.N, A = entry.A }
end
check(layout[1] and layout[1].Id == "Rifle" and layout[2] and layout[2].Id == "Pistol" and layout[9] and layout[9].Id == "Medkit"
	and layout[9].N == 2, "Anordnung steht")
local ammoSlot = slotOf(alice, "Ammo_Rifle")
check(ammoSlot ~= nil and layout[ammoSlot].N == 60, "60 Schuss in der Tasche")

-- Eingaben prüfen
check(InventoryService.LoadoutSave(alice, 3) == false and InventoryService.LoadoutSave(alice, "x") == false
	and InventoryService.LoadoutSave(alice, 0 / 0) == false and InventoryService.LoadoutSave(alice, nil) == false, "Save: nur 1 oder 2")
check(InventoryService.LoadoutApply(alice, 1) == false and string.find(statusText(alice), "noch leer", 1, true) ~= nil,
	"Apply: leere Ausrüstung")

-- Speichern (auch abseits vom Lager), Anzeige und Profil
check(InventoryService.LoadoutSave(alice, 1) == true, "Ausrüstung 1 gespeichert")
check(string.find(statusText(alice), "Ausrüstung 1 gespeichert", 1, true) ~= nil and lastExt(alice, "Status")[3] == true,
	"Meldung: gespeichert")
check(alice:GetAttribute("ExtLoadouts") == "[4,0]", "Attribut: 4 Plätze in Ausrüstung 1: " .. tostring(alice:GetAttribute("ExtLoadouts")))
local savedTemplate = ProgressService.Get(alice).Extinction.Loadouts[1]
check(savedTemplate and #savedTemplate == 4 and savedTemplate[1].S == 1 and savedTemplate[1].Id == "Rifle"
	and savedTemplate[1].Att.Muzzle == "Compensator" and savedTemplate[1].Mag == nil, "Vorlage im Profil: Plätze, Ids, Aufsätze, kein Magazin")

-- Anlegen nur am Lager in der Safe Zone
moveTo(alice, Vector3.new(0, 3, 0))
check(InventoryService.LoadoutApply(alice, 1) == false and string.find(statusText(alice), "direkt am Lager", 1, true) ~= nil,
	"in der Safe Zone, aber nicht am Lager: nichts")
moveTo(alice, Vector3.new(0, 3, 300))
step(5.5)
check(alice:GetAttribute("InSafeZone") ~= true, "draußen")
check(InventoryService.LoadoutApply(alice, 1) == false, "draußen: nichts")
check(#bagOf(alice) == 4, "Tasche unverändert")

-- Alles ins Lager, dann draußen mit anderem Zeug sterben
moveTo(alice, Vector3.new(52, 3, -26))
for _, entry in bagOf(alice) do
	check(InventoryService.Move(alice, "Bag", entry.S, "Stash", nil) == true, "ins Lager: " .. entry.Id)
end
check(#bagOf(alice) == 0 and #stashOf(alice) == 4, "alles im Lager")
moveTo(alice, Vector3.new(-36, 3, 28))
check(InventoryService.Buy(alice, "Stand_Weapons", "Pistol") == true, "zweite Pistole")
check(InventoryService.Give(alice, "Bandage", 3) == 3, "Verbände")
moveTo(alice, Vector3.new(0, 3, 300))
step(5.5)
alice.Character.Humanoid.Health = 0
step(0.2)
check(alice:GetAttribute("ExtBag") == "[]", "Tasche nach dem Tod leer")
step(ExtinctionConfig.RespawnTime + 0.5)
check(alice.Character and alice.Character.Humanoid.Health > 0, "Respawn")

-- Anlegen am Lager: alles wieder auf seinem Platz, das Gewehr mit seinen Aufsätzen
moveTo(alice, Vector3.new(52, 3, -26))
check(InventoryService.LoadoutApply(alice, 1) == true, "Ausrüstung 1 angelegt")
check(statusText(alice) == "Ausrüstung 1 angelegt" and lastExt(alice, "Status")[3] == true, "Meldung ohne Fehlendes: " .. statusText(alice))
check(#bagOf(alice) == 4, "vier Plätze belegt (" .. #bagOf(alice) .. ")")
for s, want in layout do
	local got = slot(alice, s)
	check(got ~= nil and got.Id == want.Id and got.N == want.N, "Platz " .. s .. ": " .. want.Id .. " ×" .. want.N)
end
rifle = slot(alice, 1)
check(rifle and rifle.A and rifle.A.Muzzle == "Compensator" and rifle.A.Magazine == "ExtendedMag", "Gewehr mit beiden Aufsätzen zurück")
check(#stashOf(alice) == 0, "Lager leer")

-- Nicht zur Vorlage Gehörendes geht ins Lager; fehlende Stücke stehen in der Meldung
check(InventoryService.Give(alice, "Bandage", 3) == 3, "Verbände in der Tasche")
check(InventoryService.TakeEverywhere(alice, "Medkit", 1) == 1, "ein Medikit weg")
check(InventoryService.TakeSlot(alice, 2) ~= nil, "Pistole weg")
check(InventoryService.LoadoutApply(alice, 1) == true, "wieder angelegt")
check(string.find(statusText(alice), "Fehlt: ", 1, true) ~= nil and string.find(statusText(alice), "Pistole", 1, true) ~= nil
	and string.find(statusText(alice), "Medikit", 1, true) ~= nil and string.find(statusText(alice), "×", 1, true) == nil
	and lastExt(alice, "Status")[3] == false, "Meldung nennt Fehlendes (ein Stück ohne Anzahl): " .. statusText(alice))
check(countIn(bagOf(alice), "Bandage") == 0 and countIn(stashOf(alice), "Bandage") == 3, "Verbände im Lager")
check(slot(alice, 9) and slot(alice, 9).Id == "Medkit" and slot(alice, 9).N == 1, "ein Medikit auf Platz 9")
check(slot(alice, 2) == nil, "Platz 2 bleibt leer")
check(InventoryService.TakeEverywhere(alice, "Medkit", 1) == 1 and InventoryService.LoadoutApply(alice, 1) == true
	and string.find(statusText(alice), "Medikit ×2", 1, true) ~= nil, "Anzahl in der Meldung: " .. statusText(alice))

-- Loser Aufsatz im Lager wird angebaut; eine Waffe mit denselben Aufsätzen wird bevorzugt
check(InventoryService.Detach(alice, 1, "Muzzle") == true, "Kompensator abgenommen")
check(InventoryService.Move(alice, "Bag", slotOf(alice, "Att_Compensator"), "Stash", nil) == true, "Kompensator ins Lager")
check(InventoryService.Give(alice, "Rifle", 1) == 1, "zweites Gewehr ohne Aufsätze in der Tasche")
check(InventoryService.LoadoutApply(alice, 1) == true, "angelegt")
rifle = slot(alice, 1)
check(rifle and rifle.A and rifle.A.Muzzle == "Compensator" and rifle.A.Magazine == "ExtendedMag",
	"Gewehr mit Magazin gewählt, Kompensator aus dem Lager angebaut")
check(find(stashOf(alice), "Att_Compensator") == nil and find(bagOf(alice), "Att_Compensator") == nil, "loser Kompensator ist weg")
check(find(stashOf(alice), "Rifle") ~= nil and find(stashOf(alice), "Rifle").A == nil, "zweites Gewehr (ohne Aufsätze) im Lager")

-- Zweite Vorlage, Speichern mit leerer Tasche
check(InventoryService.LoadoutSave(alice, 2) == true and alice:GetAttribute("ExtLoadouts") == "[4,2]",
	"Ausrüstung 2 gespeichert: " .. tostring(alice:GetAttribute("ExtLoadouts")))
for _, entry in bagOf(alice) do
	InventoryService.Move(alice, "Bag", entry.S, "Stash", nil)
end
check(#bagOf(alice) == 0, "Tasche leer")
check(InventoryService.LoadoutSave(alice, 2) == false and string.find(statusText(alice), "leer", 1, true) ~= nil,
	"leere Tasche: nichts gespeichert")
check(alice:GetAttribute("ExtLoadouts") == "[4,2]", "Vorlage 2 bleibt")
check(InventoryService.LoadoutApply(alice, 2) == true and #bagOf(alice) == 2, "Ausrüstung 2 angelegt")

-- Verlassen: Vorlagen gespeichert, Laden prüft sie
SIM.Leave(alice)
step(2)
local saved = store.Data.u1
check(saved and saved.Extinction and type(saved.Extinction.Loadouts) == "table" and #saved.Extinction.Loadouts[1] == 4
	and #saved.Extinction.Loadouts[2] == 2 and saved.Extinction.Loadouts[1][1].Att.Magazine == "ExtendedMag", "gespeichert: beide Vorlagen")
saved.Extinction.Loadouts[1][1].Att.Grip = "Unbekannt" -- unbekannter Aufsatz
table.insert(saved.Extinction.Loadouts[1], { S = 1, Id = "Pistol", N = 1 }) -- doppelter Platz
table.insert(saved.Extinction.Loadouts[1], { S = 99, Id = "Pistol", N = 1 }) -- Platz außerhalb
table.insert(saved.Extinction.Loadouts[1], { S = 3, Id = "Gibtsnicht", N = 1 }) -- unbekanntes Item
table.insert(saved.Extinction.Loadouts[1], { S = 4, Id = "Bandage", N = 99 }) -- über der Stapelgröße
local again = SIM.Join("Alice", 1)
Instance.new("Backpack", again).Name = "Backpack"
step(2)
enter(again)
check(again:GetAttribute("ExtLoadouts") == "[5,2]", "geladen und bereinigt: " .. tostring(again:GetAttribute("ExtLoadouts")))
local loaded = ProgressService.Get(again).Extinction.Loadouts[1]
check(loaded[1].Att.Grip == nil and loaded[1].Att.Magazine == "ExtendedMag", "unbekannter Aufsatz weg")
local bandageEntry = find(loaded, "Bandage")
check(bandageEntry ~= nil and bandageEntry.N == ExtinctionConfig.MaxStack("Bandage"), "Anzahl auf die Stapelgröße begrenzt")

if failures == 0 then
	print("Ausrüstungen: alles in Ordnung")
end

-- Container in der offenen Welt: sichere Tasche mit SafeSlots Plätzen. Hin und her mit der Tasche geht überall (auch
-- draußen), mit dem Lager nur am Lager. Beim Tod draußen und beim Verlassen draußen bleibt der Container, die Tasche ist
-- weg. Waffe in der Hand in den Container = weggesteckt. Gespeichert im Profil (Extinction.Safe), Anzeige über ExtSafe.
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

local function safeOf(player)
	return HttpService:JSONDecode(player:GetAttribute("ExtSafe") or "[]")
end
local function find(list, id)
	for _, entry in list do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

check(ExtinctionConfig.SafeSlots == 20, "Container hat 20 Plätze")
check(alice:GetAttribute("ExtSafe") == "[]", "Container am Anfang leer (Attribut da)")

-- Kaufen im Camp, dann draußen in den Container legen
moveTo(alice, Vector3.new(-36, 3, 28))
check(InventoryService.Buy(alice, "Stand_Weapons", "Rifle") == true, "Gewehr gekauft")
check(InventoryService.Buy(alice, "Stand_Weapons", "Ammo_Rifle", 2) == true, "Munition gekauft")
check(InventoryService.Buy(alice, "Stand_Weapons", "Pistol") == true, "Pistole gekauft")
local rifleSlot = slot(alice, 1) and slot(alice, 1).Id == "Rifle" and 1 or nil
check(rifleSlot ~= nil, "Gewehr auf Platz 1")

moveTo(alice, Vector3.new(0, 3, 300)) -- weit draußen, weit weg vom Lager
step(5.5)
InventoryService.Use(alice, 1)
step(0.4)
check(alice:GetAttribute("ExtEquipped") == 1, "Gewehr in der Hand")
check(InventoryService.Move(alice, "Bag", 1, "Safe", nil) == true, "draußen: Gewehr in den Container")
check(alice:GetAttribute("ExtEquipped") == 0, "Waffe weggesteckt, als sie in den Container kam")
check(find(safeOf(alice), "Rifle") ~= nil, "Gewehr im Container (ExtSafe)")
check(slot(alice, 1) == nil, "Platz 1 der Tasche leer")
check(InventoryService.Move(alice, "Safe", 1, "Bag", 5) == true, "draußen: zurück auf Platz 5 der Tasche")
check(slot(alice, 5) and slot(alice, 5).Id == "Rifle", "Gewehr auf Platz 5")
check(InventoryService.Move(alice, "Bag", 5, "Safe", 3) == true, "auf einen bestimmten Platz im Container")
check(safeOf(alice)[1] and safeOf(alice)[1].S == 3, "Gewehr auf Platz 3 des Containers")

-- Lager nur am Lager, auch vom Container aus
check(InventoryService.Move(alice, "Safe", 3, "Stash", nil) == false, "draußen: Container -> Lager geht nicht")

-- Container voll
for _ = 1, ExtinctionConfig.SafeSlots - 1 do
	InventoryService.Give(alice, "Bandage", 1)
	local bagNow = bagOf(alice)
	local last = nil
	for _, entry in bagNow do
		if entry.Id == "Bandage" then
			last = entry.S
		end
	end
	-- jeden Verband einzeln auf einen eigenen Platz im Container legen
	for s = 1, ExtinctionConfig.SafeSlots do
		local taken = false
		for _, entry in safeOf(alice) do
			taken = taken or entry.S == s
		end
		if not taken then
			InventoryService.Move(alice, "Bag", last, "Safe", s)
			break
		end
	end
end
check(#safeOf(alice) == ExtinctionConfig.SafeSlots, "Container voll (" .. #safeOf(alice) .. ")")
local pistolSlot = nil
for _, entry in bagOf(alice) do
	if entry.Id == "Pistol" then
		pistolSlot = entry.S
	end
end
check(InventoryService.Move(alice, "Bag", pistolSlot, "Safe", nil) == false, "volle Container nehmen nichts mehr")
local status = lastExt(alice, "Status")
check(status and string.find(status[2], "Container ist voll") ~= nil, "Meldung: Container voll")

-- Tod draußen: Tasche weg, Container bleibt
local safeBefore = #safeOf(alice)
alice.Character.Humanoid.Health = 0
step(0.2)
check(alice:GetAttribute("ExtBag") == "[]", "Tasche nach dem Tod leer")
check(#safeOf(alice) == safeBefore and find(safeOf(alice), "Rifle") ~= nil, "Container nach dem Tod unverändert")
local loot = workspace.ExtinctionLoot:GetChildren()
local dropped = loot[1] and LootService.Get(loot[1].LootBag:GetAttribute("LootBag"))
local droppedRifle = false
for _, item in dropped and dropped.Container.Slots or {} do
	droppedRifle = droppedRifle or item.Id == "Rifle"
end
check(dropped ~= nil and not droppedRifle, "Tasche am Boden ohne das Gewehr aus dem Container")
step(ExtinctionConfig.RespawnTime + 0.5)
check(alice.Character and alice.Character.Humanoid.Health > 0, "Respawn")
check(find(safeOf(alice), "Rifle") ~= nil, "nach dem Respawn: Gewehr im Container")

-- am Lager: Container <-> Lager
moveTo(alice, Vector3.new(52, 3, -26))
check(InventoryService.Move(alice, "Safe", 3, "Stash", nil) == true, "am Lager: Container -> Lager")
check(find(HttpService:JSONDecode(alice:GetAttribute("ExtStash")), "Rifle") ~= nil, "Gewehr im Lager")
check(InventoryService.CountEverywhere(alice, "Bandage") == ExtinctionConfig.SafeSlots - 1, "CountEverywhere zählt den Container")
check(InventoryService.TakeEverywhere(alice, "Bandage", 2) == 2, "TakeEverywhere nimmt aus dem Container")

-- Spiel verlassen draußen: gespeichert mit Container
moveTo(alice, Vector3.new(-200, 3, 0))
SIM.Leave(alice)
step(2)
local saved = store.Data.u1
check(saved and saved.Extinction and #saved.Extinction.Bag == 0, "gespeichert: Tasche leer")
check(saved and type(saved.Extinction.Safe) == "table" and #saved.Extinction.Safe == ExtinctionConfig.SafeSlots - 3,
	"gespeichert: Container (" .. (saved and saved.Extinction and saved.Extinction.Safe and #saved.Extinction.Safe or -1) .. ")")

if failures == 0 then
	print("Container: alles in Ordnung")
end

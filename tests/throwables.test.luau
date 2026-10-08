-- Granaten und Molotows (ThrowableService): am Waffenstand zu kaufen, in der Safe Zone nicht zu werfen, draußen fliegt die
-- Granate und explodiert nach der Zündzeit (Schaden an Zombies im Umkreis), der Molotow zerplatzt zu einem Feuer, das eine
-- Weile Schaden macht. Das Item ist danach weg. Spieler ohne PvP-Zeit bekommen nichts ab.
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

require("ExtDailyConfig").Enabled = false
local ThrowableService = require("ThrowableService")
ThrowableService.Init()

check(table.find(ExtinctionConfig.Stands.Stand_Weapons.Items, "Grenade") ~= nil
	and table.find(ExtinctionConfig.Stands.Stand_Weapons.Items, "Molotov") ~= nil, "Granate und Molotow am Waffenstand")

moveTo(alice, Vector3.new(-36, 3, 28))
check(InventoryService.Buy(alice, "Stand_Weapons", "Grenade") == true, "Granate gekauft")
check(InventoryService.Buy(alice, "Stand_Weapons", "Molotov") == true, "Molotow gekauft")
local function slotOf(id)
	for _, entry in bagOf(alice) do
		if entry.Id == id then
			return entry.S, entry.N
		end
	end
	return nil, 0
end
local grenadeSlot = slotOf("Grenade")
check(grenadeSlot ~= nil and grenadeSlot <= ExtinctionConfig.HotbarSlots, "Granate auf der Hotbar")

-- Safe Zone: kein Wurf
step(0.5)
InventoryService.Throw(alice, grenadeSlot, Vector3.new(0, 0, 1))
step(0.1)
check(select(2, slotOf("Grenade")) == 1, "in der Safe Zone nicht geworfen")
local status = lastExt(alice, "Status")
check(status and string.find(status[2], "Safe Zone") ~= nil, "Meldung: Safe Zone")

-- draußen: Zombie (Übungsziel) vor Alice
moveTo(alice, Vector3.new(0, 3, 300))
step(5.5)
local zombies = workspace:FindFirstChild("Zombies") or Instance.new("Folder", workspace)
zombies.Name = "Zombies"
local function dummy(offset)
	local model = Instance.new("Model")
	model.Name = "Zombie"
	model:SetAttribute("IsZombie", true)
	local root = Instance.new("Part", model)
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(alice.Character.HumanoidRootPart.Position + offset)
	local humanoid = Instance.new("Humanoid", model)
	humanoid.MaxHealth = 300
	humanoid.Health = 300
	model.Parent = zombies
	return model, humanoid
end
local zombie, zombieHumanoid = dummy(Vector3.new(0, 0, 8))
InventoryService.Throw(alice, grenadeSlot, Vector3.new(0, 0, 1))
step(0.2)
check(slotOf("Grenade") == nil, "Granate geworfen (Item weg)")
check(workspace:FindFirstChild("Throwables") and workspace.Throwables:FindFirstChild("Frag") ~= nil, "Granate fliegt")
check(zombieHumanoid.Health == 300, "vor der Zündzeit kein Schaden")
step(ExtinctionConfig.Throwables.Frag.Fuse + 0.2)
check(zombieHumanoid.Health < 300 and zombieHumanoid.Health > 300 - ExtinctionConfig.Throwables.Frag.Damage - 1,
	"Explosion trifft den Zombie (" .. zombieHumanoid.Health .. ")")
check(workspace.Throwables:FindFirstChild("Frag") == nil, "Granate weg")

-- Molotow: Feuer brennt eine Weile
local before = zombieHumanoid.Health
local molotovSlot = slotOf("Molotov")
step(1.2) -- Abklingzeit
InventoryService.Throw(alice, molotovSlot, Vector3.new(0, 0, 1))
step(ExtinctionConfig.Throwables.Molotov.Fuse + 0.2)
check(#ThrowableService.Fires() == 1, "Feuer brennt")
step(2)
check(zombieHumanoid.Health < before - 10, "Feuer macht Schaden (" .. before .. " -> " .. zombieHumanoid.Health .. ")")
step(ExtinctionConfig.Throwables.Molotov.Duration)
check(#ThrowableService.Fires() == 0, "Feuer aus")

if failures == 0 then
	print("Wurfwaffen: alles in Ordnung")
end

-- Heli-Absturz (HeliCrashService): Heli fliegt (noch nicht auf der Karte), schlägt ein, Wrack brennt (Schaden in der Nähe,
-- Zombies kommen), danach Kisten am Wrack; leer geräumt ist alles weg.
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

local ground = Instance.new("Part", workspace)
ground.Name = "Ground"
SIM.RaycastHandler = function(origin, direction)
	if direction.Y >= 0 then
		return nil
	end
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground, Material = Enum.Material.Grass }
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

local K = ExtinctionConfig.HeliCrash
K.FlyTime = 2
K.BurnTime = 3
K.Zombies = 2
local HeliCrashService = require("HeliCrashService")
local ZombieService = require("ZombieService")
local HttpService2 = game:GetService("HttpService")
require("ExtDailyConfig").Enabled = false

moveTo(alice, Vector3.new(0, 3, 300))
step(5.5)
local target = alice.Character.HumanoidRootPart.Position + Vector3.new(4, -3, 0)
local crash = HeliCrashService.Start(target)
step(0.3)
check(crash ~= nil and crash.State == "Flying" and workspace.ExtinctionHeliCrash:FindFirstChild("CrashingHeli") ~= nil, "Heli fliegt")
check(#HttpService2:JSONDecode(map:GetAttribute("HeliCrashes") or "[]") == 0, "im Flug noch nicht auf der Karte")
check(HeliCrashService.Start() == nil, "nur einer gleichzeitig")
local zombiesBefore = ZombieService.Count()
local health = alice.Character.Humanoid.Health
step(K.FlyTime + 0.3)
check(crash.State == "Burning" and workspace.ExtinctionHeliCrash:FindFirstChild("HeliWreck") ~= nil, "eingeschlagen, Wrack brennt")
local list = HttpService2:JSONDecode(map:GetAttribute("HeliCrashes") or "[]")
check(#list == 1 and list[1].State == "Burning", "Wrack auf der Karte")
check(ZombieService.Count() > zombiesBefore, "Zombies kommen zum Absturz")
step(1)
check(alice.Character.Humanoid.Health < health, "Feuer am Wrack macht Schaden (" .. health .. " -> " .. alice.Character.Humanoid.Health .. ")")
moveTo(alice, Vector3.new(0, 3, 380))
local lootBefore = #workspace.ExtinctionLoot:GetChildren()
step(K.BurnTime)
check(crash.State == "Loot", "Feuer aus")
check(#workspace.ExtinctionLoot:GetChildren() == lootBefore + K.Crates, "Kisten am Wrack")
for _, id in crash.Loot do
	require("LootService").Remove(id)
end
step(0.5)
check(HeliCrashService.Current() == nil and workspace.ExtinctionHeliCrash:FindFirstChild("HeliWreck") == nil, "leer geräumt: alles weg")

if failures == 0 then
	print("Heli-Absturz: alles in Ordnung")
end

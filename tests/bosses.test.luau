-- Bosse (BossService): der Chirurg bewacht das Krankenhaus, erscheint erst, wenn jemand in die Nähe kommt (Name und
-- Lebensbalken, viel Leben, groß), wirft Spritzen (Schaden, langsamer), stirbt mit fester Beute in einer Tasche und Münzen
-- für den Killer und kommt erst nach der Wartezeit wieder.
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
local places = map:FindFirstChild("Places") or Instance.new("Folder", map)
places.Name = "Places"
local hospital = Instance.new("Part", places)
hospital.Name = "Place_Krankenhaus"
hospital:SetAttribute("Title", "Krankenhaus")
hospital.Size = Vector3.new(120, 4, 120)
hospital.CFrame = CFrame.new(CENTER + Vector3.new(0, 2, 330))
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

local cfg = ExtinctionConfig.Bosses.Chirurg
cfg.RespawnTime = 5
local BossService = require("BossService")
local HttpService2 = game:GetService("HttpService")
require("ExtDailyConfig").Enabled = false

local list = HttpService2:JSONDecode(map:GetAttribute("Bosses") or "[]")
check(#list == 1 and list[1].Name == "DER CHIRURG" and list[1].Alive == false, "Chirurg auf der Karte (noch nicht da)")
check(BossService.All().Chirurg and BossService.All().Chirurg.Model == nil, "ohne Spieler in der Nähe kein Boss")

moveTo(alice, Vector3.new(0, 3, 300)) -- 30 Studs vor dem Krankenhaus
step(5.5)
step(1)
local boss = BossService.All().Chirurg
check(boss.Model ~= nil and boss.Model:GetAttribute("IsBoss") == true, "Chirurg erscheint, wenn jemand kommt")
local humanoid = boss.Model and boss.Model:FindFirstChildOfClass("Humanoid")
check(humanoid and humanoid.MaxHealth == cfg.Health and humanoid.Health == cfg.Health, "viel Leben (" .. tostring(humanoid and humanoid.MaxHealth) .. ")")
check(boss.Model and boss.Model:FindFirstChild("BossBar", true) ~= nil, "Name und Lebensbalken")
list = HttpService2:JSONDecode(map:GetAttribute("Bosses") or "[]")
check(list[1] and list[1].Alive == true, "Karte: Boss lebt")

-- Spritze: Alice in Reichweite stellen
boss.Model:PivotTo(CFrame.new(alice.Character.HumanoidRootPart.Position + Vector3.new(0, 0, 20)))
local health = alice.Character.Humanoid.Health
step(cfg.AbilityEvery + 0.6)
check(alice.Character.Humanoid.Health < health or alice.Character:GetAttribute("SpeedMultiplier") == cfg.SlowFactor,
	"Spritze trifft (Leben " .. health .. " -> " .. alice.Character.Humanoid.Health .. ")")

-- Tod: Beute und Münzen für den Killer
local coins = ProgressService.Get(alice).Coins
local lootBefore = #workspace.ExtinctionLoot:GetChildren()
require("Damage").Apply(boss.Model, humanoid, cfg.Health + 10, { Player = alice })
step(0.6)
check(boss.Model == nil, "Chirurg tot")
check(#workspace.ExtinctionLoot:GetChildren() >= lootBefore + 1, "Beute liegt am Boden")
check(ProgressService.Get(alice).Coins >= coins + cfg.Coins, "Münzen für Alice")
list = HttpService2:JSONDecode(map:GetAttribute("Bosses") or "[]")
check(list[1] and list[1].Alive == false and list[1].RespawnAt ~= nil, "Karte: tot mit Rückkehr-Zeit")
step(2)
check(boss.Model == nil, "kommt nicht sofort wieder")
step(cfg.RespawnTime)
check(boss.Model ~= nil, "nach der Wartezeit wieder da")

if failures == 0 then
	print("Bosse: alles in Ordnung")
end

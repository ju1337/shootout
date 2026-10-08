-- Horden-Kiste (HordeService): Kiste steht verriegelt, E startet die Belagerung (Welle 1), in der Nähe bleiben lässt den
-- Fortschritt laufen (weitere Wellen), weggehen hält ihn an, zu lange weg setzt zurück; bei 100 % Beute und Münzen.
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

local H = ExtinctionConfig.Horde
H.HoldTime = 6
H.PauseLimit = 3
for _, wave in H.Waves do
	wave.Count = 2
end
local HordeService = require("HordeService")
local ZombieService = require("ZombieService")
local HttpService2 = game:GetService("HttpService")
require("ExtDailyConfig").Enabled = false

moveTo(alice, Vector3.new(0, 3, 300))
step(5.5)
Instance.new("ForceField", alice.Character) -- Zombies sollen Alice hier nicht erledigen
local spot = alice.Character.HumanoidRootPart.Position + Vector3.new(6, -3, 0)
local horde = HordeService.Start(spot)
step(0.3)
check(horde ~= nil and workspace.ExtinctionHordes:FindFirstChild("HordeCrate") ~= nil, "Horden-Kiste steht")
check(HordeService.Start() == nil, "nur eine gleichzeitig")
local list = HttpService2:JSONDecode(map:GetAttribute("Hordes") or "[]")
check(#list == 1 and list[1].State == "Locked", "auf der Karte (verriegelt)")
local prompt = workspace.ExtinctionHordes.HordeCrate.Crate:FindFirstChild("HordePrompt")
check(prompt ~= nil, "E-Aufforderung an der Kiste")

local zombiesBefore = ZombieService.Count()
prompt.Triggered:Fire(alice)
step(0.5)
check(horde.State == "Siege" and horde.Wave == 1, "Belagerung läuft, Welle 1")
check(ZombieService.Count() > zombiesBefore, "Zombies der ersten Welle (" .. zombiesBefore .. " -> " .. ZombieService.Count() .. ")")
step(2.5)
check(horde.Progress > 0.34 and horde.Wave >= 2, "Fortschritt " .. math.floor(horde.Progress * 100) .. " %, Welle " .. horde.Wave)

-- weggehen: Fortschritt steht, zu lange weg: zurück auf 0
local progress = horde.Progress
moveTo(alice, Vector3.new(0, 3, 400))
step(1)
check(math.abs(horde.Progress - progress) < 0.1, "weg: Fortschritt steht")
step(3)
check(horde.State == "Locked" and horde.Progress == 0 and prompt.Enabled, "zu lange weg: wieder verriegelt")

-- nochmal und durchhalten
moveTo(alice, Vector3.new(0, 3, 300))
local coins = ProgressService.Get(alice).Coins
prompt.Triggered:Fire(alice)
local lootBefore = #workspace.ExtinctionLoot:GetChildren()
step(H.HoldTime + 1)
check(HordeService.Current() == nil, "Kiste offen und weg")
check(#workspace.ExtinctionLoot:GetChildren() == lootBefore + 1, "Beute liegt bereit")
check(ProgressService.Get(alice).Coins >= coins + H.Coins, "Münzen für Alice")
check(#HttpService2:JSONDecode(map:GetAttribute("Hordes") or "[]") == 0, "Karte wieder leer")

if failures == 0 then
	print("Horden-Kiste: alles in Ordnung")
end

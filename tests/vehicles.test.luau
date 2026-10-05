-- Fahrzeuge der offenen Welt: kaufen, Taste spawnt vor dem Spieler und setzt ihn auf den Fahrersitz (Waffe weg),
-- nur ein Fahrzeug draußen, K packt ein (nur nah dran) und startet 8 s Wartezeit, Mitfahrer per E (fahren nur der
-- Besitzer), Treffer nur draußen mit PvP, kaputt = Item weg, Umfahren schadet Zombies, Tod und Verlassen räumen auf,
-- Tempo-Check; Client: Gas, Bremse, Lenken und Aussteigen (VehicleClient)
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 1, 20)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local HttpService = game:GetService("HttpService")
local Remotes = require("Remotes")
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
ProgressService.Init()
WeaponService.Init()

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
local stand = Instance.new("Part", map.Stands)
stand.Name = "Stand_Vehicles"
stand.CFrame = CFrame.new(CENTER + Vector3.new(-30, 2.5, -42))
local ground = Instance.new("Part", workspace)
ground.Name = "Ground"
SIM.RaycastHandler = function(origin, direction)
	if direction.Y < 0 then
		return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground }
	end
	return nil
end

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local VehicleService = require("VehicleService")
local ZombieService = require("ZombieService")
local Damage = require("Damage")
InventoryService.Init()
LootService.Init()
require("ExtinctionConfig").Airdrop.FirstDelay = math.huge -- hier keine Lootdrops (eigener Test: airdrop)
Extinction.Init({ Join = function() end, Status = function() end })
ExtinctionConfig.Zombies.PerPlayer = 0 -- hier keine Zombies von selbst

store.Data.u1 = { XP = {}, Coins = 20000, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 500, Rap = 0, Owned = {}, Equipped = {} }
local alice, bob = SIM.Join("Alice"), SIM.Join("Bob")
for _, player in { alice, bob } do
	Instance.new("Backpack", player).Name = "Backpack"
end
step(2)
for _, player in { alice, bob } do
	player:SetAttribute("Mode", "Extinction")
	Extinction.AddPlayer(player)
end
step(0.5)

local function place(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
	step(0.3)
end
local function slotOf(player, id)
	for _, entry in HttpService:JSONDecode(player:GetAttribute("ExtBag") or "[]") do
		if entry.Id == id then
			return entry.S, entry
		end
	end
	return nil
end
local function lastStatus(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "ExtUpdate" and entry.Player == player and entry.Args[1] == "Status" then
			return entry.Args[2]
		end
	end
	return ""
end

-- Kaufen am Fahrzeugstand
place(alice, Vector3.new(-30, 3, -36))
check(InventoryService.Buy(alice, "Stand_Vehicles", "V_Quad") == true, "Quad gekauft")
check(InventoryService.Buy(alice, "Stand_Vehicles", "V_Pickup") == true, "Geländewagen gekauft")
local quadSlot = slotOf(alice, "V_Quad")
local pickupSlot = slotOf(alice, "V_Pickup")
check(quadSlot == 1 and pickupSlot == 2, "Fahrzeuge auf der Hotbar (1, 2)")
InventoryService.Buy(alice, "Stand_Vehicles", "V_Sports")

-- Taste: spawnen und einsteigen
place(alice, Vector3.new(0, 3, 200))
InventoryService.Use(alice, quadSlot)
step(0.2)
local quad = VehicleService.Get(alice)
check(quad ~= nil and quad.Parent == workspace.ExtinctionVehicles, "Quad steht in der Welt")
check(quad and quad:GetAttribute("Owner") == alice.UserId and quad:GetAttribute("VehicleId") == "Quad", "Besitzer und Art am Modell")
local humanoid = alice.Character.Humanoid
local driverSeat = quad and quad:FindFirstChild("DriverSeat")
check(driverSeat ~= nil and humanoid.SeatPart == driverSeat and driverSeat.Occupant == humanoid, "Alice sitzt auf dem Fahrersitz")
local _, entry = slotOf(alice, "V_Quad")
check(entry and entry.Out == true, "Hotbar zeigt: Fahrzeug draußen")
local chassis = quad and quad.PrimaryPart
check(chassis and (chassis.Position - alice.Character.HumanoidRootPart.Position).Magnitude < 15, "vor dem Spieler gespawnt")
check(chassis and chassis:FindFirstChild("Drive") and chassis:FindFirstChild("Steer"), "Antrieb und Lenkung am Rumpf")
check(quad and quad:GetAttribute("Health") == ExtinctionConfig.Vehicles.Quad.Health, "volles Leben")

-- im Fahrzeug keine Waffe, kein zweites Fahrzeug
InventoryService.Buy(alice, "Stand_Vehicles", "V_Quad") -- zu weit weg vom Stand: geht nicht
check(slotOf(alice, "Pistol") == nil, "kein Kauf weit weg vom Stand")
alice.Character.Humanoid.Sit = false
step(0.2)
InventoryService.Use(alice, pickupSlot)
check(string.find(lastStatus(alice), "schon ein Fahrzeug", 1, true) ~= nil, "nur ein Fahrzeug gleichzeitig")
InventoryService.Use(alice, quadSlot)
check(humanoid.SeatPart == driverSeat, "gleiche Taste in der Nähe: wieder einsteigen")

-- K: einpacken, dann 8 Sekunden warten
Remotes.ExtAction.OnServerEvent:Fire(alice, "StoreVehicle")
step(0.2)
check(VehicleService.Get(alice) == nil and quad.Parent == nil, "Quad eingepackt")
check(humanoid.SeatPart == nil, "Alice steht wieder")
_, entry = slotOf(alice, "V_Quad")
check(entry and not entry.Out, "Quad wieder in der Tasche")
local readyAt = alice:GetAttribute("ExtVehicleReadyAt")
check(readyAt and math.abs(readyAt - (workspace:GetServerTimeNow() + 8)) < 0.5, "Wartezeit 8 Sekunden")
InventoryService.Use(alice, quadSlot)
check(VehicleService.Get(alice) == nil and string.find(lastStatus(alice), "bereit in", 1, true) ~= nil, "vor Ablauf kein Spawn")
step(8)
InventoryService.Use(alice, quadSlot)
check(VehicleService.Get(alice) ~= nil, "nach 8 Sekunden wieder spawnbar")

-- K nur in der Nähe
humanoid.Sit = false
step(0.1)
place(alice, Vector3.new(0, 3, 260))
Remotes.ExtAction.OnServerEvent:Fire(alice, "StoreVehicle")
check(VehicleService.Get(alice) ~= nil, "zu weit weg: nicht eingepackt")
place(alice, Vector3.new(0, 3, 210))
Remotes.ExtAction.OnServerEvent:Fire(alice, "StoreVehicle")
check(VehicleService.Get(alice) == nil, "nah dran: eingepackt")
step(8.5)

-- Geländewagen: Mitfahrer per E, fahren nur der Besitzer
InventoryService.Use(alice, pickupSlot)
local pickup = VehicleService.Get(alice)
check(pickup ~= nil and pickup:FindFirstChild("Seat2") ~= nil and pickup:FindFirstChild("Seat4") ~= nil, "Geländewagen mit 4 Sitzen")
place(bob, Vector3.new(4, 3, 200))
local seat2 = pickup.Seat2
seat2.SeatPrompt.Triggered:Fire(bob)
check(bob.Character.Humanoid.SeatPart == seat2, "Bob fährt mit")
check(seat2.SeatPrompt.Enabled == false, "besetzter Sitz ohne E-Aufforderung")
bob.Character.Humanoid.Sit = false
alice.Character.Humanoid.Sit = false
step(0.1)
pickup.DriverSeat.SeatPrompt.Triggered:Fire(bob)
check(bob.Character.Humanoid.SeatPart == nil, "Bob darf nicht fahren")
pickup.DriverSeat.SeatPrompt.Triggered:Fire(alice)
check(alice.Character.Humanoid.SeatPart == pickup.DriverSeat, "Alice steigt per E wieder ein")

-- Treffer: nicht ohne PvP, nicht in der Safe Zone; kaputt = Item weg
local health = pickup:GetAttribute("Health")
check(VehicleService.Hit(bob, pickup, 50) == 0 and pickup:GetAttribute("Health") == health, "ohne PvP kein Schaden am Fahrzeug")
step(5.5)
check(bob:GetAttribute("PvP") == true, "Bob hat PvP")
check(VehicleService.Hit(bob, pickup, 50) == 50 and pickup:GetAttribute("Health") == health - 50, "mit PvP: Schaden am Fahrzeug")
pickup:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 30)))
check(VehicleService.Hit(bob, pickup, 50) == 0, "in der Safe Zone kein Schaden am Fahrzeug")
pickup:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 200)))
step(0.6)
VehicleService.Hit(bob, pickup, 10000)
step(0.1)
check(VehicleService.Get(alice) == nil, "zerstört: nicht mehr aktiv")
check(slotOf(alice, "V_Pickup") == nil, "Geländewagen aus der Tasche entfernt")
check(alice.Character.Humanoid.SeatPart == nil, "Insassen ausgestiegen")
check(string.find(lastStatus(alice), "zerstört", 1, true) ~= nil, "Meldung: zerstört")
step(6.5)
check(pickup.Parent == nil, "Wrack verschwindet")

-- Schüsse treffen Fahrzeuge über WeaponService
check(WeaponService.OnVehicleHit == VehicleService.Hit, "WeaponService meldet Fahrzeugtreffer")

-- Umfahren: Zombies nehmen Schaden, wenn das Fahrzeug schnell ist
step(8.5)
InventoryService.Use(alice, quadSlot)
quad = VehicleService.Get(alice)
local zombie = ZombieService.Spawn(quad.PrimaryPart.Position + Vector3.new(0, 0, -8))
local zombieHumanoid = zombie.Humanoid
quad.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, -10)
quad.PrimaryPart.Touched:Fire(zombie.Torso)
check(zombieHumanoid.Health == zombieHumanoid.MaxHealth, "langsam: kein Schaden")
quad.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, -50)
quad.PrimaryPart.Touched:Fire(zombie.Torso)
check(zombieHumanoid.Health < zombieHumanoid.MaxHealth, "schnell: Zombie nimmt Schaden")

-- Tempo-Check: zu schnell versetzt -> zurück
local before = quad.PrimaryPart.Position
step(0.6)
before = quad.PrimaryPart.Position
quad:PivotTo(CFrame.new(before + Vector3.new(400, 0, 0)))
step(0.6)
check((quad.PrimaryPart.Position - before).Magnitude < 1, "zu schnell bewegt: zurückgesetzt")

-- Client: Gas, Lenken, Bremsen (Physik nachgestellt: Tempo folgt dem Soll)
rawget(SIM.Players, "__props").LocalPlayer = alice
local VehicleClient = require("VehicleClient")
local Movement = require("Movement")
check(alice.Character.Humanoid.SeatPart == quad.DriverSeat, "Alice sitzt im Quad")
local drive = quad.PrimaryPart.Drive
local function simulate(seconds, throttle, steer)
	quad.DriverSeat.ThrottleFloat = throttle
	quad.DriverSeat.SteerFloat = steer
	for _ = 1, math.floor(seconds * 20) do
		VehicleClient.Update(0.05)
		local v = drive.PlaneVelocity
		quad.PrimaryPart.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Y)
	end
end
simulate(0.5, 1, 0)
local state = VehicleClient.Driving()
check(state ~= nil and Movement.InVehicle(), "Fahrer erkannt, Verfolgerkamera")
check(state and state.Speed > 10 and state.Speed < ExtinctionConfig.Vehicles.Quad.Speed, "beschleunigt (" .. tostring(state and state.Speed) .. ")")
simulate(4, 1, 0)
check(math.abs(state.Speed - ExtinctionConfig.Vehicles.Quad.Speed) < 0.01, "Höchsttempo erreicht")
check(math.abs(drive.PlaneVelocity.Magnitude - ExtinctionConfig.Vehicles.Quad.Speed) < 0.01, "Antrieb bekommt das Tempo")
local yaw = state.Yaw
simulate(0.5, 1, 1)
check(state.Yaw < yaw, "rechts lenken dreht nach rechts")
simulate(0.5, -1, 0)
check(state.Speed < ExtinctionConfig.Vehicles.Quad.Speed - 30, "Bremsen wirkt stärker als Gas")
simulate(4, 0, 0)
check(math.abs(state.Speed) < 0.01, "ohne Gas rollt es aus")
yaw = state.Yaw
simulate(0.5, 0, 1)
check(math.abs(state.Yaw - yaw) < 1e-6, "im Stand lenkt nichts")
-- Tastatur direkt (wenn der Sitz nichts meldet): W gibt Gas
SIM.KeysDown[Enum.KeyCode.W] = true
simulate(0.5, 0, 0)
SIM.KeysDown[Enum.KeyCode.W] = nil
check(state.Speed > 5, "W gibt Gas, auch ohne Werte vom Sitz")
simulate(4, 0, 0)
-- an einer Wand: echtes Tempo 0, Soll bleibt in der Nähe
quad.DriverSeat.ThrottleFloat = 1
for _ = 1, 40 do
	VehicleClient.Update(0.05)
	quad.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
end
check(VehicleClient.Driving().Speed <= 12.01, "an der Wand kein Weiterschieben (" .. VehicleClient.Driving().Speed .. ")")
alice.Character.Humanoid.Sit = false
VehicleClient.Update(0.05)
check(VehicleClient.Driving() == nil and drive.PlaneVelocity == Vector2.zero and not Movement.InVehicle(), "Aussteigen: anhalten, Kamera zurück")

-- Tod mit Fahrzeug draußen: Fahrzeug weg, Item in der Tasche am Boden
local bags = #workspace.ExtinctionLoot:GetChildren()
alice.Character.Humanoid.Health = 0
step(0.3)
check(VehicleService.Get(alice) == nil and quad.Parent == nil, "Fahrzeug nach dem Tod weg")
check(#workspace.ExtinctionLoot:GetChildren() == bags + 1, "Tasche am Boden")
local hasQuad = false
for _, model in workspace.ExtinctionLoot:GetChildren() do
	local bag = LootService.Get(model.LootBag:GetAttribute("LootBag"))
	for _, item in bag and bag.Container.Slots or {} do
		if item.Id == "V_Quad" then
			hasQuad = true
			check(item.Out == nil, "Item in der Tasche ist nicht mehr draußen")
		end
	end
end
check(hasQuad, "Quad liegt in der Todestasche")

-- Verlassen mit Fahrzeug draußen: Fahrzeug weg
step(6)
place(alice, Vector3.new(-30, 3, -36))
InventoryService.Buy(alice, "Stand_Vehicles", "V_Quad")
place(alice, Vector3.new(0, 3, 60))
InventoryService.Use(alice, slotOf(alice, "V_Quad"))
local last = VehicleService.Get(alice)
check(last ~= nil, "Quad in der Safe Zone gespawnt")
SIM.Leave(alice)
step(0.2)
check(last.Parent == nil, "Spiel verlassen: Fahrzeug weg")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

-- Helikopter der offenen Welt: kaufen (Fahrzeugstand), spawnt mit Abstand und Platz für Rotor und Heck, 4 Sitze (Pilot +
-- 3 Mitfahrer), Antrieb in alle Richtungen mit Kraft für das Gewicht, Rotoren an Motor6D; Client (VehicleClient): am Boden
-- erst abheben, Leertaste steigt, ohne Eingabe Höhe halten, W fliegt mit Neigung, A/D dreht mit Schräglage, Shift sinkt,
-- Flughöhe und Rand der Welt begrenzt, Leertaste/Shift/R2/L2 geschluckt, F steigt aus, Absprung hoch oben = Gleiten,
-- Rotoren drehen sich; Server: ohne Pilot sinkt er und setzt auf, Einpacken nur gelandet, Check für Steigen, Flughöhe
-- und Weltrand, kaputt stürzt er ab
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
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Day.Fixed = 12
Extinction.Init({ Join = function() end, Status = function() end })
ExtinctionConfig.Zombies.PerPlayer = 0

local config = ExtinctionConfig.Vehicles.Heli
store.Data.u1 = { XP = {}, Coins = 20000, Rap = 0, Owned = {}, Equipped = {} }
local alice, bob, carol, dave, erin = SIM.Join("Alice"), SIM.Join("Bob"), SIM.Join("Carol"), SIM.Join("Dave"), SIM.Join("Erin")
local everyone = { alice, bob, carol, dave, erin }
for _, player in everyone do
	Instance.new("Backpack", player).Name = "Backpack"
end
step(2)
for _, player in everyone do
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
local function sameCFrame(a, b)
	local ca, cb = { a:GetComponents() }, { b:GetComponents() }
	for i = 1, 12 do
		if math.abs(ca[i] - cb[i]) > 1e-6 then
			return false
		end
	end
	return true
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
check(table.find(ExtinctionConfig.Stands.Stand_Vehicles.Items, "V_Heli") ~= nil, "Helikopter im Fahrzeugstand")
place(alice, Vector3.new(-30, 3, -36))
check(InventoryService.Buy(alice, "Stand_Vehicles", "V_Heli") == true, "Helikopter gekauft")
local heliSlot = slotOf(alice, "V_Heli")
check(heliSlot ~= nil, "Helikopter in der Tasche")

-- Spawnen: mit Abstand vor dem Spieler, Pilot sitzt
place(alice, Vector3.new(0, 3, 300))
InventoryService.Use(alice, heliSlot)
step(0.2)
local heli = VehicleService.Get(alice)
check(heli ~= nil and heli:GetAttribute("VehicleId") == "Heli", "Helikopter steht in der Welt")
local chassis = heli.PrimaryPart
local spawnPos = chassis.Position
local distance = (Vector3.new(chassis.Position.X, 0, chassis.Position.Z) - Vector3.new(0, 0, CENTER.Z + 300)).Magnitude
check(math.abs(distance - 18) < 0.5, "steht 18 Studs vor dem Spieler (Rotor und Heck haben Platz): " .. distance)
check(alice.Character.Humanoid.SeatPart == heli.DriverSeat, "Alice sitzt am Steuer")
check(heli:GetAttribute("Health") == config.Health, "volles Leben")

-- Aufbau: 4 Sitze, Rotoren an Motor6D, Antrieb in alle Richtungen mit Kraft für das Gewicht
check(heli:FindFirstChild("Seat2") and heli:FindFirstChild("Seat3") and heli:FindFirstChild("Seat4") and not heli:FindFirstChild("Seat5"),
	"Pilot plus drei Plätze")
local rotorMotor, tailMotor = chassis:FindFirstChild("RotorMotor"), chassis:FindFirstChild("TailRotorMotor")
check(rotorMotor and rotorMotor:IsA("Motor6D") and rotorMotor.Part1 == heli.RotorHub, "Hauptrotor hängt an einem Motor6D")
check(tailMotor and tailMotor:IsA("Motor6D") and tailMotor.Part1 == heli.TailRotorHub, "Heckrotor hängt an einem Motor6D")
local blades = 0
for _, part in heli:GetChildren() do
	if part.Name == "RotorBlade" then
		blades += 1
		local weld = part:FindFirstChildOfClass("WeldConstraint")
		check(weld and weld.Part0 == heli.RotorHub, "Rotorblatt an der Nabe")
		check(part.CanCollide == false and part.Massless, "Rotorblatt ohne Kollision und Masse")
	end
end
check(blades == 2, "zwei gekreuzte Rotorblätter")
local drive = chassis.Drive
check(drive.VelocityConstraintMode == Enum.VelocityConstraintMode.Vector, "Antrieb in alle Richtungen")
local minMass = config.Size.X * config.Size.Y * config.Size.Z * 0.8
check(drive.MaxForce > (minMass + 4 * 15) * workspace.Gravity * 1.3, "Antrieb trägt das Gewicht mit vier Insassen")
check(heli:FindFirstChild("Searchlight") and heli.Searchlight:FindFirstChildOfClass("SpotLight"), "Suchscheinwerfer")

-- Mitfahrer per E: drei Plätze, der vierte Mitfahrer findet keinen
local riders = { bob, carol, dave }
for index, rider in riders do
	place(rider, Vector3.new(4 * index, 3, 280))
	local seat = heli["Seat" .. (index + 1)]
	seat.SeatPrompt.Triggered:Fire(rider)
	check(rider.Character.Humanoid.SeatPart == seat, rider.Name .. " sitzt im Helikopter")
end
local occupied = 0
for _, part in heli:GetChildren() do
	if (part:IsA("Seat") or part:IsA("VehicleSeat")) and part.Occupant then
		occupied += 1
	end
end
check(occupied == 4, "vier Leute im Helikopter")
place(erin, Vector3.new(-4, 3, 280))
heli.DriverSeat.SeatPrompt.Triggered:Fire(erin)
check(erin.Character.Humanoid.SeatPart == nil, "nur der Besitzer fliegt")

-- ---------- Client: fliegen ----------
rawget(SIM.Players, "__props").LocalPlayer = alice
local VehicleClient = require("VehicleClient")
local Movement = require("Movement")
local InputActions = require("InputActions")
local function fly(seconds, keys)
	for key in keys or {} do
		SIM.KeysDown[key] = true
	end
	for _ = 1, math.floor(seconds * 20 + 0.5) do
		VehicleClient.Update(0.05)
		local v = drive.VectorVelocity
		chassis.AssemblyLinearVelocity = v
		heli:PivotTo(heli:GetPivot() + v * 0.05)
	end
	for key in keys or {} do
		SIM.KeysDown[key] = nil
	end
end
local K = Enum.KeyCode
fly(0.1)
local state = VehicleClient.Driving()
check(state ~= nil and state.Heli and Movement.InVehicle(), "Pilot erkannt, Verfolgerkamera")
check(state and state.Height < 0.8, "steht am Boden (" .. tostring(state and state.Height) .. ")")
local sink = SIM.BoundActions.HeliControls
check(sink ~= nil and sink.Priority == Enum.ContextActionPriority.High.Value, "Flugtasten mit hohem Vorrang gebunden")
check(sink and table.find(sink.Inputs, K.Space) and table.find(sink.Inputs, K.LeftShift) and table.find(sink.Inputs, K.ButtonR2)
	and table.find(sink.Inputs, K.ButtonL2), "Leertaste, Shift, R2, L2 gehören zum Flug")
check(sink and sink.Callback() == Enum.ContextActionResult.Sink, "Roblox bekommt sie nicht (kein Aussteigen per Leertaste)")

-- am Boden: W und D bewegen nichts
local yaw = state.Yaw
fly(1, { [K.W] = true, [K.D] = true })
check(math.abs(state.Speed) < 0.01 and math.abs(state.Yaw - yaw) < 1e-6, "am Boden: kein Vorwärts, kein Drehen")
-- Leertaste: abheben und steigen
fly(2, { [K.Space] = true })
check(math.abs(state.Lift - config.Climb) < 0.01, "steigt mit Climb (" .. state.Lift .. ")")
check(state.Height > 30, "abgehoben (" .. math.floor(state.Height) .. " Studs)")
-- ohne Eingabe: Höhe halten
fly(1)
local height = state.Height
fly(2)
check(math.abs(state.Lift) < 0.01 and math.abs(state.Height - height) < 0.01, "ohne Eingabe hält er die Höhe")
-- W: vorwärts mit Neigung nach vorne
fly(5, { [K.W] = true })
check(math.abs(state.Speed - config.Speed) < 0.01, "Höchsttempo " .. config.Speed)
check(math.abs(Vector3.new(drive.VectorVelocity.X, 0, drive.VectorVelocity.Z).Magnitude - config.Speed) < 0.01, "Antrieb bekommt das Tempo")
check(state.Pitch < -math.rad(10), "Nase nach unten im Vorwärtsflug")
local upY = chassis.Steer.CFrame.UpVector.Y
check(upY < 0.99, "Lenkung neigt den Helikopter (" .. upY .. ")")
-- D: rechts drehen mit Schräglage
yaw = state.Yaw
fly(0.5, { [K.W] = true, [K.D] = true })
check(state.Yaw < yaw, "D dreht nach rechts")
check(state.Roll < -math.rad(10), "Schräglage nach rechts")
-- loslassen: bremst und bleibt in der Luft stehen
fly(6)
check(math.abs(state.Speed) < 0.01 and math.abs(state.Roll) < 1e-6, "ohne Gas: bleibt stehen, gerade")
-- Shift: sinken
height = state.Height
fly(1, { [K.LeftShift] = true })
check(state.Lift < -config.Climb + 0.01 and state.Height < height - 15, "Shift sinkt")
-- Touch: HOCH-Knopf (InputActions) steigt
InputActions.Trigger("HeliUp", true)
fly(1)
InputActions.Trigger("HeliUp", false)
check(state.Lift > config.Climb - 0.01, "Touch HOCH steigt")
fly(1)

-- Flughöhe: über Ceiling (über MapCenter) steigt er nicht weiter, weit drüber sinkt er
heli:PivotTo(CFrame.new(chassis.Position.X, CENTER.Y + config.Ceiling + 1, chassis.Position.Z) * chassis.CFrame.Rotation)
fly(0.5, { [K.Space] = true })
check(state.Lift <= 0, "an der Flughöhe kein Steigen")
heli:PivotTo(CFrame.new(chassis.Position.X, CENTER.Y + config.Ceiling + 10, chassis.Position.Z) * chassis.CFrame.Rotation)
fly(0.5)
check(state.Lift < 0, "über der Flughöhe sinkt er")
heli:PivotTo(CFrame.new(chassis.Position.X, CENTER.Y + 60, chassis.Position.Z) * chassis.CFrame.Rotation)
fly(1)

-- Rand der Welt: nicht weiter hinaus (nach +X schauen und Gas geben)
local edge = ExtinctionConfig.WorldSize / 2 - 30
heli:PivotTo(CFrame.new(CENTER.X + edge, CENTER.Y + 60, chassis.Position.Z))
state.Yaw = -math.pi / 2
fly(2, { [K.W] = true })
check(drive.VectorVelocity.X == 0 and state.Speed <= 12.01, "am Rand der Welt nicht weiter hinaus (" .. drive.VectorVelocity.X .. ")")
state.Yaw = math.pi / 2
fly(1, { [K.W] = true })
check(drive.VectorVelocity.X < 0, "zurück in die Welt geht")
fly(6)
-- zurück über die Stelle, an der er stand (für den Tempo-Check des Servers ein erlaubtes Steigen)
heli:PivotTo(CFrame.new(spawnPos + Vector3.new(0, 30, 0)))
fly(0.2)
step(0.6)
check((chassis.Position - (spawnPos + Vector3.new(0, 30, 0))).Magnitude < 1, "erlaubtes Steigen: kein Zurücksetzen")

-- Rotoren drehen sich (alle Clients); mit Pilot schnell
VehicleClient.SpinRotors(1)
VehicleClient.SpinRotors(1)
VehicleClient.SpinRotors(0.05)
local turned = rotorMotor.Transform
VehicleClient.SpinRotors(0.05)
check(not sameCFrame(rotorMotor.Transform, turned), "Hauptrotor dreht sich")
check(not sameCFrame(tailMotor.Transform, CFrame.new()), "Heckrotor dreht sich")

-- Einpacken in der Luft: nein
Remotes.ExtAction.OnServerEvent:Fire(alice, "StoreVehicle")
check(VehicleService.Get(alice) == heli and string.find(lastStatus(alice), "Lande erst", 1, true) ~= nil, "in der Luft nicht einpacken")

-- Pilot steigt per F aus (in der Luft): Glide, Helikopter sinkt ohne Pilot senkrecht
alice.Character:PivotTo(CFrame.new(heli.DriverSeat.Position + Vector3.new(0, 2, 0)))
VehicleClient.Update(0.05)
local exit = SIM.BoundActions.HeliExit
check(exit ~= nil and table.find(exit.Inputs, K.F) ~= nil, "F zum Aussteigen gebunden")
exit.Callback("HeliExit", Enum.UserInputState.Begin, { KeyCode = K.F })
check(alice.Character.Humanoid.SeatPart == nil, "F: Pilot ausgestiegen")
VehicleClient.Update(0.05)
check(VehicleClient.Driving() == nil and SIM.BoundActions.HeliControls == nil and SIM.BoundActions.HeliExit == nil,
	"Flugtasten wieder frei")
SIM.Advance(0.1, 20)
check(alice.Character.Humanoid.PlatformStand == true, "Absprung hoch oben: Fallschirmsprung (Glide)")
check(alice.Character.HumanoidRootPart.AssemblyLinearVelocity.Y < -20, "fällt gebremst wie beim Fallschirmsprung")
check(drive.VectorVelocity == Vector3.new(0, -config.Descent, 0), "ohne Pilot: sinkt senkrecht (Autorotation)")
-- sinken lassen bis zum Boden: setzt auf und bleibt stehen
for _ = 1, 200 do
	local v = drive.VectorVelocity
	if v.Y == 0 then
		break
	end
	heli:PivotTo(heli:GetPivot() + v * 0.05)
	step(0.05)
end
check(drive.VectorVelocity == Vector3.zero, "aufgesetzt: Antrieb steht")
check(VehicleService.HeightAboveGround(heli, chassis) < 0.8, "steht am Boden")
-- Rotoren laufen am Boden ohne Pilot aus
for _ = 1, 10 do
	VehicleClient.SpinRotors(1)
end
local before = rotorMotor.Transform
VehicleClient.SpinRotors(0.05)
check(sameCFrame(rotorMotor.Transform, before), "Rotoren stehen am Boden ohne Pilot")

-- Server-Check: zu schnelles Steigen wird zurückgesetzt
step(0.6)
local base = chassis.Position
heli:PivotTo(CFrame.new(base + Vector3.new(0, 150, 0)))
step(0.6)
check((chassis.Position - base).Magnitude < 1, "zu schnell gestiegen: zurückgesetzt")
-- über der Flughöhe (in erlaubten Schritten hochgezogen): zurückgesetzt
local y = base.Y
while y < CENTER.Y + config.Ceiling + 30 do
	y = math.min(y + 30, CENTER.Y + config.Ceiling + 30)
	heli:PivotTo(CFrame.new(base.X, y, base.Z))
	step(0.55)
end
check(math.abs(chassis.Position.Y - y) < 1, "bis knapp über die Flughöhe erlaubt")
heli:PivotTo(CFrame.new(base.X, CENTER.Y + config.Ceiling + 45, base.Z))
step(0.55)
check(math.abs(chassis.Position.Y - y) < 1, "weit über der Flughöhe: zurückgesetzt")
heli:PivotTo(CFrame.new(base))
step(0.6)
-- außerhalb der Welt: zurückgesetzt
local half = ExtinctionConfig.WorldSize / 2
local inside = CFrame.new(CENTER.X + half - 20, base.Y, base.Z)
for x = base.X, CENTER.X + half - 20, 60 do
	heli:PivotTo(CFrame.new(x, base.Y, base.Z))
	step(0.55)
end
heli:PivotTo(inside)
step(0.55)
check(math.abs(chassis.Position.X - inside.Position.X) < 1, "nah am Rand: erlaubt")
heli:PivotTo(CFrame.new(CENTER.X + half + 10, base.Y, base.Z))
step(0.55)
check(math.abs(chassis.Position.X - inside.Position.X) < 1, "über den Rand der Welt: zurückgesetzt")
heli:PivotTo(CFrame.new(base))
step(0.6)

-- gelandet: Einpacken geht
place(alice, Vector3.new(0, 3, 300))
alice.Character:PivotTo(CFrame.new(chassis.Position + Vector3.new(6, 0, 0)))
Remotes.ExtAction.OnServerEvent:Fire(alice, "StoreVehicle")
check(VehicleService.Get(alice) == nil and heli.Parent == nil, "gelandet: eingepackt")

-- Absturz: kaputt in der Luft = Antrieb aus, alle steigen aus
step(8.5)
for _, player in { alice, bob, carol, dave } do
	player.Character.Humanoid.Sit = false
end
place(alice, Vector3.new(0, 3, 300))
InventoryService.Use(alice, slotOf(alice, "V_Heli"))
heli = VehicleService.Get(alice)
check(heli ~= nil, "wieder gespawnt")
chassis = heli.PrimaryPart
heli.Seat2.SeatPrompt.Triggered:Fire(carol)
heli:PivotTo(heli:GetPivot() + Vector3.new(0, 25, 0))
step(5.5)
check(erin:GetAttribute("PvP") == true, "Erin hat PvP")
VehicleService.Hit(erin, heli, 100000)
check(chassis.Drive.Enabled == false and chassis.Steer.Enabled == false, "kaputt: kein Antrieb mehr, er stürzt ab")
check(alice.Character.Humanoid.SeatPart == nil and carol.Character.Humanoid.SeatPart == nil, "alle steigen aus")
check(slotOf(alice, "V_Heli") == nil, "Helikopter weg")
for _ = 1, 10 do
	VehicleClient.SpinRotors(1)
end
check(sameCFrame(chassis.RotorMotor.Transform, CFrame.new()), "Wrack: Rotoren drehen nicht")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

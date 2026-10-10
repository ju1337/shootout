-- VehicleClient (ModuleScript, nur Client)
-- Fahren in der offenen Welt (EXTINCTION). Der Fahrer besitzt die Physik seines Fahrzeugs (VehicleService gibt sie
-- ihm beim Einsteigen); dieses Modul setzt jedes Bild vor der Physik das Tempo (LinearVelocity "Drive", nur
-- waagerecht) und die Richtung (AlignOrientation "Steer") am Rumpf. Gas/Bremse und Lenken kommen vom Fahrersitz
-- (ThrottleFloat/SteerFloat: Tastatur, Controller, Touch-Stick über Roblox), sonst direkt von W/A/S/D bzw. Pfeilen.
-- Fahrgefühl aus ExtinctionConfig.Vehicles: Speed (vorwärts, rückwärts ein Drittel), Accel, Turn (Grad/s bei
-- Tempo, im Stand lenkt nichts). Bremst schneller als es beschleunigt; an Hindernissen gleicht sich das Soll-Tempo
-- dem echten an (kein Weiterschieben an Wänden). Mitfahrer und Fahrer bekommen die Verfolgerkamera (Movement).
-- Leertaste: aussteigen (Roblox), K: einpacken (ExtinctionClient -> VehicleService).
--
-- Helikopter (Kind "Heli", LinearVelocity in alle Richtungen): W/S vor/zurück, A/D drehen, Leertaste steigen,
-- Shift/Strg/C sinken, F aussteigen; Controller: Stick, R2 steigen, L2 sinken, ✕ aussteigen; Touch: Stick, STEIGEN/SINKEN
-- (TouchControls, Aktionen HeliUp/HeliDown), SPRUNG aussteigen. Ohne Eingabe hält er die Höhe; am Boden fliegt und
-- dreht er erst nach dem Abheben. Höchstens Ceiling über MapCenter, am Rand der Welt (EDGE) nicht weiter hinaus. Er
-- neigt sich in Flugrichtung und in Kurven. Solange man fliegt, schluckt eine ContextActionService-Aktion mit hohem
-- Vorrang Leertaste, Shift und R2/L2 (sonst steigt Roblox aus bzw. gibt am Sitz Gas). Wer hoch über dem Boden aus einem
-- Helikopter steigt (auch Mitfahrer, auch wenn er kaputt geht), gleitet per Fallschirmsprung (Glide). Die Rotoren aller
-- Helikopter drehen sich auf jedem Client (Motor6D.Transform, wird nicht übertragen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Movement = require(Shared.Movement)
local InputActions = require(Shared.InputActions)
local Glide = require(script.Parent:WaitForChild("Glide"))

local player = Players.LocalPlayer

local VehicleClient = {}

local REVERSE = 0.35   -- Rückwärts-Tempo als Anteil von Speed
local COAST = 0.5      -- ohne Gas: so viel von Accel bremst das Fahrzeug aus
local BRAKE = 2.2      -- gegen die Fahrtrichtung: so viel stärker als Accel
local GRIP_SPEED = 14  -- ab diesem Tempo lenkt es voll
local SLIP = 12        -- so weit darf das Soll-Tempo über dem echten liegen (Hindernisse)
local SKID_DROP = 1.4  -- Gleitkugeln (bzw. Kufen) unter der Unterseite des Rumpfs (VehicleService: 0,3 + halbe Kugel)

-- Helikopter
local HELI_COAST = 0.8        -- ohne Gas: so viel von Accel bremst er (bleibt dann in der Luft stehen)
local LIFT_RATE = 3           -- Steigen/Sinken erreicht das Soll in 1/LIFT_RATE Sekunden
local GROUNDED = 0.8          -- so hoch (Kufen über dem Boden) gilt er als gelandet
local PITCH = math.rad(12)    -- Neigung nach vorne bei Höchsttempo (rückwärts nach hinten)
local ROLL = math.rad(14)     -- Neigung zur Seite beim Drehen
local TILT_RATE = math.rad(45) -- so schnell (rad/s) neigt er sich
local EDGE = 40               -- so weit vor dem Rand der Welt fliegt er nicht weiter hinaus
local ROTOR_SPEED = 22        -- Drehzahl des Hauptrotors mit Pilot (rad/s); Heckrotor 1,6-mal so schnell
local ROTOR_SPIN_UP = 9       -- so schnell (rad/s²) dreht er hoch bzw. läuft aus
local GLIDE_HEIGHT = 12       -- wer höher über dem Boden aussteigt, gleitet
local SINK_ACTION = "HeliControls"
local EXIT_ACTION = "HeliExit"

local driving = nil -- { Model, Chassis, Seat, Drive, Steer, Config, Speed, Yaw, Heli, Lift, Pitch, Roll, Height }
local lastHeli = nil -- Helikopter, in dem der Spieler im letzten Bild saß (Aussteigen in der Luft erkennen)
local sinking = false
local rotors = setmetatable({}, { __mode = "k" }) -- [Modell] = { Main, Tail, Seat, Chassis, Angle, TailAngle, Speed } oder false

-- Fahrzeug, in dem der Sitz steckt (Modell mit VehicleId), sonst nil
local function vehicleOf(seat)
	if not seat or not seat:GetAttribute("Vehicle") then
		return nil
	end
	local model = seat.Parent
	return model and model:GetAttribute("VehicleId") and model or nil
end

local function configOf(model)
	return model and ExtinctionConfig.Vehicles[model:GetAttribute("VehicleId")]
end

local function isHeli(model)
	local config = configOf(model)
	return config ~= nil and config.Kind == "Heli"
end

local function moveToward(value, target, step)
	if value < target then
		return math.min(target, value + step)
	end
	return math.max(target, value - step)
end

local function keyDown(...)
	for i = 1, select("#", ...) do -- ohne Tabelle (läuft mehrmals pro Bild)
		if UserInputService:IsKeyDown((select(i, ...))) then
			return true
		end
	end
	return false
end

local function padDown(key)
	return UserInputService.GamepadEnabled == true and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key)
end

-- Gas (-1..1) und Lenkung (-1 links .. 1 rechts)
local function inputs(seat)
	local throttle, steer = seat.ThrottleFloat, seat.SteerFloat
	if throttle == 0 and steer == 0 and not UserInputService:GetFocusedTextBox() then
		throttle = (keyDown(Enum.KeyCode.W, Enum.KeyCode.Up) and 1 or 0) - (keyDown(Enum.KeyCode.S, Enum.KeyCode.Down) and 1 or 0)
		steer = (keyDown(Enum.KeyCode.D, Enum.KeyCode.Right) and 1 or 0) - (keyDown(Enum.KeyCode.A, Enum.KeyCode.Left) and 1 or 0)
	end
	return throttle, steer
end

-- Helikopter: steigen (1), sinken (-1) oder Höhe halten (0)
local function liftInput()
	if UserInputService:GetFocusedTextBox() then
		return 0
	end
	local up = keyDown(Enum.KeyCode.Space) or padDown(Enum.KeyCode.ButtonR2) or InputActions.IsHeld("HeliUp")
	local down = keyDown(Enum.KeyCode.LeftShift, Enum.KeyCode.LeftControl, Enum.KeyCode.C) or padDown(Enum.KeyCode.ButtonL2)
		or InputActions.IsHeld("HeliDown")
	return (up and 1 or 0) - (down and 1 or 0)
end

-- Boden unter einer Stelle (y), ohne ignore, Spieler, Zombies, Taschen und nicht feste Teile; nil = nichts darunter
-- (Filter nur alle 0,5 s neu bauen: die Höhe wird beim Fliegen jedes Bild gemessen)
local groundParams = { Params = nil, Ignore = nil, At = -math.huge }
local function groundBelow(origin, ignore)
	if groundParams.Params and groundParams.Ignore == ignore and os.clock() - groundParams.At < 0.5 then
		local hit = workspace:Raycast(origin, Vector3.new(0, -1000, 0), groundParams.Params)
		return hit and hit.Position.Y or nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	groundParams.Params, groundParams.Ignore, groundParams.At = params, ignore, os.clock()
	local list = { ignore }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	for _, name in { "Zombies", "ExtinctionLoot" } do
		local extra = workspace:FindFirstChild(name)
		if extra then
			table.insert(list, extra)
		end
	end
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(origin, Vector3.new(0, -1000, 0), params)
	return hit and hit.Position.Y or nil
end

-- Höhe eines Fahrzeugs (Unterkante der Gleitkugeln bzw. Kufen) über dem Boden; math.huge = nichts darunter
function VehicleClient.Height(model)
	local chassis = model and model.PrimaryPart
	local config = configOf(model)
	if not chassis or not config then
		return math.huge
	end
	local ground = groundBelow(chassis.Position, model)
	return ground and (chassis.Position.Y - config.Size.Y / 2 - SKID_DROP - ground) or math.huge
end

local function exitSeat()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart then
		humanoid.Sit = false
		humanoid.Jump = true
	end
end

-- Solange man fliegt: Leertaste, Shift und R2/L2 nicht an Roblox weitergeben (Aussteigen bzw. Gas am Sitz); F steigt aus
local function setSink(on)
	if sinking == on then
		return
	end
	sinking = on
	if on then
		ContextActionService:BindActionAtPriority(SINK_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR2,
			Enum.KeyCode.ButtonL2)
		ContextActionService:BindActionAtPriority(EXIT_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then
				exitSeat()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.F)
	else
		ContextActionService:UnbindAction(SINK_ACTION)
		ContextActionService:UnbindAction(EXIT_ACTION)
	end
end

local function stopDriving()
	if driving then
		local drive = driving.Drive
		if drive.Parent and not driving.Heli then -- Helikopter: das Sinken ohne Pilot setzt der Server (VehicleService)
			drive.PlaneVelocity = Vector2.zero
		end
		driving = nil
	end
	setSink(false)
end

local function startDriving(model, seat)
	local chassis = model.PrimaryPart
	local drive = chassis and chassis:FindFirstChild("Drive")
	local steer = chassis and chassis:FindFirstChild("Steer")
	local config = configOf(model)
	if not chassis or not drive or not drive:IsA("LinearVelocity") or not steer or not steer:IsA("AlignOrientation") or not config then
		return
	end
	local _, yaw = chassis.CFrame:ToOrientation()
	local look = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local velocity = chassis.AssemblyLinearVelocity
	driving = { Model = model, Chassis = chassis, Seat = seat, Drive = drive, Steer = steer, Config = config,
		Speed = velocity:Dot(look), Yaw = yaw, Heli = config.Kind == "Heli", Lift = velocity.Y, Pitch = 0, Roll = 0,
		Height = 0 }
end

-- Ein Schritt des Piloten: Soll-Geschwindigkeit (alle Richtungen) und Ausrichtung samt Neigung setzen
local function stepHeli(state, dt)
	local config = state.Config
	local chassis = state.Chassis
	local throttle, steer = inputs(state.Seat)
	local height = VehicleClient.Height(state.Model)
	state.Height = height
	local grounded = height < GROUNDED
	local center = player:GetAttribute("MapCenter")
	local hasCenter = typeof(center) == "Vector3"
	-- steigen/sinken: ohne Eingabe Höhe halten, am Boden nicht tiefer, über der Flughöhe nicht höher (weit drüber: sinken)
	local climb = liftInput() * config.Climb
	if grounded then
		climb = math.max(climb, 0)
	end
	if hasCenter then
		local top = center.Y + config.Ceiling
		if chassis.Position.Y > top + 4 then
			climb = -config.Climb * 0.5
		elseif chassis.Position.Y >= top then
			climb = math.min(climb, 0)
		end
	end
	state.Lift = moveToward(state.Lift, climb, config.Climb * LIFT_RATE * dt)
	-- vor/zurück: erst in der Luft; ohne Gas bleibt er stehen
	local target = 0
	if not grounded then
		target = throttle >= 0 and throttle * config.Speed or throttle * config.Speed * REVERSE
	end
	local rate = config.Accel
	if target == 0 then
		rate = config.Accel * HELI_COAST
	elseif state.Speed ~= 0 and math.sign(target) ~= math.sign(state.Speed) then
		rate = config.Accel * BRAKE
	end
	state.Speed = moveToward(state.Speed, target, rate * dt)
	-- an Hindernissen (Wand, Dach) nicht weiterschieben: Soll bleibt nah am echten Tempo, waagerecht und senkrecht
	local velocity = chassis.AssemblyLinearVelocity
	local look = Vector3.new(-math.sin(state.Yaw), 0, -math.cos(state.Yaw))
	local actual = velocity:Dot(look)
	if math.abs(state.Speed - actual) > SLIP then
		state.Speed = actual + math.clamp(state.Speed - actual, -SLIP, SLIP)
	end
	if math.abs(state.Lift - velocity.Y) > SLIP then
		state.Lift = velocity.Y + math.clamp(state.Lift - velocity.Y, -SLIP, SLIP)
	end
	-- drehen: nur in der Luft, in beide Richtungen gleich (unabhängig vom Tempo)
	if not grounded then
		state.Yaw -= steer * math.rad(config.Turn) * dt
	end
	look = Vector3.new(-math.sin(state.Yaw), 0, -math.cos(state.Yaw))
	local x, z = look.X * state.Speed, look.Z * state.Speed
	-- Rand der Welt: nicht weiter hinaus
	if hasCenter then
		local half = ExtinctionConfig.WorldSize / 2 - EDGE
		local offset = chassis.Position - center
		if (offset.X > half and x > 0) or (offset.X < -half and x < 0) then
			x = 0
		end
		if (offset.Z > half and z > 0) or (offset.Z < -half and z < 0) then
			z = 0
		end
	end
	state.Drive.VectorVelocity = Vector3.new(x, state.Lift, z)
	-- Neigung: Nase nach unten beim Vorwärtsfliegen, zur Seite beim Drehen; am Boden gerade
	local pitch = grounded and 0 or -PITCH * state.Speed / config.Speed
	local roll = grounded and 0 or -ROLL * steer
	state.Pitch = moveToward(state.Pitch, pitch, TILT_RATE * dt)
	state.Roll = moveToward(state.Roll, roll, TILT_RATE * dt)
	state.Steer.CFrame = CFrame.Angles(0, state.Yaw, 0) * CFrame.Angles(state.Pitch, 0, state.Roll)
end

-- Ein Schritt des Fahrers: Soll-Tempo und Richtung setzen
function VehicleClient.Step(dt)
	local state = driving
	if not state then
		return
	end
	if state.Heli then
		stepHeli(state, dt)
		return
	end
	local config = state.Config
	local throttle, steer = inputs(state.Seat)
	local target = throttle >= 0 and throttle * config.Speed or throttle * config.Speed * REVERSE
	local rate = config.Accel
	if target == 0 then
		rate = config.Accel * COAST
	elseif state.Speed ~= 0 and math.sign(target) ~= math.sign(state.Speed) then
		rate = config.Accel * BRAKE
	end
	state.Speed = moveToward(state.Speed, target, rate * dt)
	-- an Hindernissen nicht weiterschieben: Soll-Tempo bleibt nah am echten
	local look = Vector3.new(-math.sin(state.Yaw), 0, -math.cos(state.Yaw))
	local actual = state.Chassis.AssemblyLinearVelocity:Dot(look)
	if math.abs(state.Speed - actual) > SLIP then
		state.Speed = actual + math.clamp(state.Speed - actual, -SLIP, SLIP)
	end
	-- lenken: im Stand nicht, rückwärts andersherum
	local grip = math.clamp(math.abs(state.Speed) / GRIP_SPEED, 0, 1)
	state.Yaw -= steer * math.rad(config.Turn) * grip * dt * (state.Speed >= 0 and 1 or -1)
	look = Vector3.new(-math.sin(state.Yaw), 0, -math.cos(state.Yaw))
	state.Drive.PlaneVelocity = Vector2.new(look.X * state.Speed, look.Z * state.Speed)
	state.Steer.CFrame = CFrame.Angles(0, state.Yaw, 0)
end

-- Fährt der Spieler gerade (Zustand für Anzeige und Tests)?
function VehicleClient.Driving()
	return driving
end

-- Sitzt der Spieler in einem Fahrzeug? Gibt Modell und Sitz zurück
function VehicleClient.Seat()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = vehicleOf(seat)
	return model, seat
end

-- Aus einem Helikopter gestiegen (oder er ist zerbrochen): hoch über dem Boden gleiten statt fallen
local function checkBailOut(model)
	if not lastHeli or model == lastHeli then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 or humanoid.SeatPart then
		return
	end
	local ground = groundBelow(root.Position, lastHeli)
	if not ground or root.Position.Y - ground > GLIDE_HEIGHT then
		Glide.Start(character, lastHeli)
	end
end

function VehicleClient.Update(dt)
	local model, seat = VehicleClient.Seat()
	local heli = isHeli(model)
	Movement.SetVehicle(model ~= nil, heli)
	checkBailOut(model)
	lastHeli = heli and model or nil
	if not model or not seat then
		stopDriving()
		return
	end
	local isDriver = seat:IsA("VehicleSeat") and model:GetAttribute("Owner") == player.UserId
	if not isDriver then
		stopDriving()
		return
	end
	if not driving or driving.Model ~= model then
		startDriving(model, seat)
	end
	setSink(driving ~= nil and driving.Heli)
	VehicleClient.Step(dt)
end

-- Rotoren aller Helikopter drehen: mit Pilot volle Drehzahl, ohne Pilot in der Luft (Autorotation) etwas weniger,
-- am Boden oder kaputt laufen sie aus
function VehicleClient.SpinRotors(dt)
	local vehicles = workspace:FindFirstChild("ExtinctionVehicles")
	if not vehicles then
		return
	end
	for _, model in vehicles:GetChildren() do
		local spin = rotors[model]
		if spin and (not spin.Chassis.Parent or not spin.Main.Parent) then
			spin = nil -- Streaming: weg- und wieder hergestreamt, Teile neu suchen
		end
		local chassis = model:IsA("Model") and model.PrimaryPart
		if spin == nil and (chassis or not model:IsA("Model")) then -- ohne PrimaryPart (noch nicht gestreamt): später
			local main = chassis and chassis:FindFirstChild("RotorMotor")
			if chassis and main and main:IsA("Motor6D") then
				local tail = chassis:FindFirstChild("TailRotorMotor")
				spin = { Main = main, Tail = tail and tail:IsA("Motor6D") and tail or nil, Seat = model:FindFirstChild("DriverSeat"),
					Chassis = chassis, Angle = 0, TailAngle = 0, Speed = 0 }
			else
				spin = false -- kein Helikopter
			end
			rotors[model] = spin
		end
		if spin and spin.Chassis.Parent then
			local seat = spin.Seat
			local alive = (model:GetAttribute("Health") or 0) > 0
			local airborne = math.abs(spin.Chassis.AssemblyLinearVelocity.Y) > 1
			local target = 0
			if alive and seat and seat:IsA("VehicleSeat") and seat.Occupant then
				target = ROTOR_SPEED
			elseif alive and airborne then
				target = ROTOR_SPEED * 0.6
			end
			spin.Speed = moveToward(spin.Speed, target, ROTOR_SPIN_UP * dt)
			spin.Angle = (spin.Angle + spin.Speed * dt) % (2 * math.pi)
			spin.TailAngle = (spin.TailAngle + spin.Speed * 1.6 * dt) % (2 * math.pi)
			spin.Main.Transform = CFrame.Angles(0, spin.Angle, 0)
			if spin.Tail then
				spin.Tail.Transform = CFrame.Angles(spin.TailAngle, 0, 0)
			end
		end
	end
end

function VehicleClient.Init()
	-- vor der Physik: das neue Soll gilt schon in diesem Schritt
	RunService.Stepped:Connect(function(_, dt)
		VehicleClient.Update(dt)
	end)
	RunService.RenderStepped:Connect(VehicleClient.SpinRotors)
	player.CharacterAdded:Connect(function()
		stopDriving()
		lastHeli = nil
		Movement.SetVehicle(false)
	end)
end

return VehicleClient

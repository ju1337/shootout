-- VehicleClient (ModuleScript, nur Client)
-- Fahren in der offenen Welt (EXTINCTION). Der Fahrer besitzt die Physik seines Fahrzeugs (VehicleService gibt sie
-- ihm beim Einsteigen); dieses Modul setzt jedes Bild vor der Physik das Tempo (LinearVelocity "Drive", nur
-- waagerecht) und die Richtung (AlignOrientation "Steer") am Rumpf. Gas/Bremse und Lenken kommen vom Fahrersitz
-- (ThrottleFloat/SteerFloat: Tastatur, Controller, Touch-Stick über Roblox), sonst direkt von W/A/S/D bzw. Pfeilen.
-- Fahrgefühl aus ExtinctionConfig.Vehicles: Speed (vorwärts, rückwärts ein Drittel), Accel, Turn (Grad/s bei
-- Tempo, im Stand lenkt nichts). Bremst schneller als es beschleunigt; an Hindernissen gleicht sich das Soll-Tempo
-- dem echten an (kein Weiterschieben an Wänden). Mitfahrer und Fahrer bekommen die Verfolgerkamera (Movement).
-- Leertaste: aussteigen (Roblox), K: einpacken (ExtinctionClient -> VehicleService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Movement = require(Shared.Movement)

local player = Players.LocalPlayer

local VehicleClient = {}

local REVERSE = 0.35   -- Rückwärts-Tempo als Anteil von Speed
local COAST = 0.5      -- ohne Gas: so viel von Accel bremst das Fahrzeug aus
local BRAKE = 2.2      -- gegen die Fahrtrichtung: so viel stärker als Accel
local GRIP_SPEED = 14  -- ab diesem Tempo lenkt es voll
local SLIP = 12        -- so weit darf das Soll-Tempo über dem echten liegen (Hindernisse)

local driving = nil -- { Model, Chassis, Seat, Drive, Steer, Config, Speed, Yaw }

-- Fahrzeug, in dem der Sitz steckt (Modell mit VehicleId), sonst nil
local function vehicleOf(seat)
	if not seat or not seat:GetAttribute("Vehicle") then
		return nil
	end
	local model = seat.Parent
	return model and model:GetAttribute("VehicleId") and model or nil
end

local function moveToward(value, target, step)
	if value < target then
		return math.min(target, value + step)
	end
	return math.max(target, value - step)
end

local function keyDown(...)
	for _, key in { ... } do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
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

local function stopDriving()
	if driving then
		local drive = driving.Drive
		if drive.Parent then
			drive.PlaneVelocity = Vector2.zero
		end
		driving = nil
	end
end

local function startDriving(model, seat)
	local chassis = model.PrimaryPart
	local drive = chassis and chassis:FindFirstChild("Drive")
	local steer = chassis and chassis:FindFirstChild("Steer")
	local config = ExtinctionConfig.Vehicles[model:GetAttribute("VehicleId")]
	if not chassis or not drive or not drive:IsA("LinearVelocity") or not steer or not steer:IsA("AlignOrientation") or not config then
		return
	end
	local _, yaw = chassis.CFrame:ToOrientation()
	local look = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	driving = { Model = model, Chassis = chassis, Seat = seat, Drive = drive, Steer = steer, Config = config,
		Speed = chassis.AssemblyLinearVelocity:Dot(look), Yaw = yaw }
end

-- Ein Schritt des Fahrers: Soll-Tempo und Richtung setzen
function VehicleClient.Step(dt)
	local state = driving
	if not state then
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

function VehicleClient.Update(dt)
	local model, seat = VehicleClient.Seat()
	Movement.SetVehicle(model ~= nil)
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
	VehicleClient.Step(dt)
end

function VehicleClient.Init()
	-- vor der Physik: das neue Soll gilt schon in diesem Schritt
	RunService.Stepped:Connect(function(_, dt)
		VehicleClient.Update(dt)
	end)
	player.CharacterAdded:Connect(function()
		stopDriving()
		Movement.SetVehicle(false)
	end)
end

return VehicleClient

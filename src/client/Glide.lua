-- Glide (ModuleScript, nur Client)
-- Fallschirmsprung beim Absprung: Körper liegt waagerecht in der Luft (wie ein Skydiver),
-- mit WASD steuern, ohne Eingabe leicht nach vorne gleiten. Kurz über dem Boden
-- richtet sich der Charakter auf und bremst ab, damit niemand Fallschaden bekommt.
-- Start: Charakter-Attribut "Dropping" (Server, Absprung zu Rundenbeginn) oder Glide.Start(character) (z.B. Aussteigen
-- hoch aus einem Helikopter, VehicleClient).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Movement = require(ReplicatedStorage:WaitForChild("Shared").Movement)

local player = Players.LocalPlayer

local Glide = {}

local FALL_SPEED = 35        -- Fallgeschwindigkeit beim Gleiten (Studs/s)
local GLIDE_SPEED = 55       -- Geschwindigkeit mit WASD
local DRIFT_SPEED = 18       -- Vorwärtsdrift ohne Eingabe
local BRAKE_HEIGHT = 25      -- ab dieser Höhe über Boden wird abgebremst
local BRAKE_FALL_SPEED = 6   -- Fallgeschwindigkeit beim Abbremsen
local BODY_PITCH = math.rad(-75) -- Körper nach vorne gekippt (fast waagerecht)
local DIVE_FOV = 85

local connection

local function stop(humanoid)
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = false
	end
	Movement.SetFovOverride(nil)
end

local function start(character)
	stop()
	local root = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	connection = RunService.Heartbeat:Connect(function()
		if not root.Parent or humanoid.Health <= 0 then
			stop(humanoid)
			return
		end

		-- Höhe über dem Boden messen
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -2000, 0), params)
		local height = hit and (root.Position.Y - hit.Position.Y) or math.huge

		-- Blickrichtung (waagerecht) und Steuerung
		local look = workspace.CurrentCamera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
		local move = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.MoveDirection * GLIDE_SPEED
			or flat * DRIFT_SPEED

		if height > BRAKE_HEIGHT then
			-- Freier Fall: Körper waagerecht, Kopf in Blickrichtung
			humanoid.PlatformStand = true
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) * CFrame.Angles(BODY_PITCH, 0, 0)
			root.AssemblyLinearVelocity = Vector3.new(move.X, -FALL_SPEED, move.Z)
			root.AssemblyAngularVelocity = Vector3.zero
			Movement.SetFovOverride(DIVE_FOV)
		elseif humanoid.FloorMaterial == Enum.Material.Air then
			Movement.SetFovOverride(nil)
			-- Abbremsen: aufrichten und langsam landen
			humanoid.PlatformStand = false
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
			root.AssemblyLinearVelocity = Vector3.new(move.X * 0.3, -BRAKE_FALL_SPEED, move.Z * 0.3)
			root.AssemblyAngularVelocity = Vector3.zero
		else
			stop(humanoid) -- gelandet
		end
	end)
end

Glide.Start = start

function Glide.Init()
	local function watch(character)
		if character:GetAttribute("Dropping") then
			start(character)
		end
		character:GetAttributeChangedSignal("Dropping"):Connect(function()
			if character:GetAttribute("Dropping") then
				start(character)
			end
		end)
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
end

return Glide

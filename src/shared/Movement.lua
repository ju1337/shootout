-- Movement (ModuleScript, nur Client)
-- First-Person-Ansicht, Sprinten (Shift), Ducken (STRG oder C, gedrückt halten),
-- Sliden (im Sprint ducken) und Zielen (setzt WeaponClient über SetAiming).
-- Grundtempo kommt vom Agenten, Fähigkeiten können es per "SpeedMultiplier" erhöhen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local Modes = require(Shared.Modes)

local player = Players.LocalPlayer

local Movement = {}

local DEFAULT_SPEED = 16
local SPRINT_FACTOR = 1.5
local CROUCH_FACTOR = 0.5
local AIM_FACTOR = 0.6         -- langsamer beim Zielen
local AIM_SENSITIVITY = 0.6    -- Maus langsamer beim Zielen
local SPRINT_FOV_BONUS = 8
local CROUCH_CAMERA = Vector3.new(0, -1.3, 0)
local CROUCH_HIP_FACTOR = 0.55 -- Körper sinkt ab (kleineres Ziel)
local SLIDE_SPEED = 42
local SLIDE_END_SPEED = 18
local SLIDE_TIME = 0.7
local SLIDE_COOLDOWN = 1.2

local normalFov = 70
local sensitivity = 1
local sprintHeld = false
local crouchHeld = false
local aiming = false
local aimFov = 50
local sliding = false
local lastSlide = 0
local normalHipHeight = nil

local function getHumanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid"), character
end

-- Fallschirmsprung läuft: dann nichts an der Haltung ändern
local function isDropping(humanoid)
	return humanoid.PlatformStand
end

local function isCrouched()
	return (crouchHeld or sliding) and Modes.IsFighting(player)
end

local function apply()
	local humanoid, character = getHumanoid()
	local sprinting = sprintHeld and not aiming and not isCrouched()
	if humanoid then
		local agent = AgentConfig.Get(character:GetAttribute("Agent"))
		local speed = (agent and agent.WalkSpeed or DEFAULT_SPEED) * (character:GetAttribute("SpeedMultiplier") or 1)
		if sprinting then
			speed *= SPRINT_FACTOR
		elseif isCrouched() then
			speed *= CROUCH_FACTOR
		end
		if aiming then
			speed *= AIM_FACTOR
		end
		humanoid.WalkSpeed = speed

		-- Ducken: Kamera tiefer, Körper sinkt ab
		normalHipHeight = normalHipHeight or humanoid.HipHeight
		local crouched = isCrouched() and not isDropping(humanoid)
		humanoid.CameraOffset = crouched and CROUCH_CAMERA or Vector3.zero
		humanoid.HipHeight = crouched and normalHipHeight * CROUCH_HIP_FACTOR or normalHipHeight
	end

	local camera = workspace.CurrentCamera
	if aiming then
		camera.FieldOfView = aimFov
	else
		camera.FieldOfView = sprinting and normalFov + SPRINT_FOV_BONUS or normalFov
	end
	UserInputService.MouseDeltaSensitivity = aiming and sensitivity * AIM_SENSITIVITY or sensitivity
end

-- Slide: kurzer Schub in Laufrichtung, der langsam ausläuft
local function startSlide()
	local humanoid, character = getHumanoid()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or sliding or isDropping(humanoid) then
		return
	end
	if humanoid.FloorMaterial == Enum.Material.Air or humanoid.MoveDirection.Magnitude < 0.5 then
		return
	end
	if os.clock() - lastSlide < SLIDE_COOLDOWN then
		return
	end
	lastSlide = os.clock()
	sliding = true
	apply()
	local direction = humanoid.MoveDirection.Unit
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - started) / SLIDE_TIME
		if t >= 1 or not root.Parent or humanoid.Health <= 0 then
			connection:Disconnect()
			sliding = false
			apply()
			return
		end
		local speed = SLIDE_SPEED + (SLIDE_END_SPEED - SLIDE_SPEED) * t
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(direction.X * speed, velocity.Y, direction.Z * speed)
	end)
end

-- An = First Person, Aus = Kamera hinter dem Ziel (z.B. beim Zuschauen)
function Movement.SetFirstPerson(on: boolean)
	if on then
		player.CameraMinZoomDistance = 0.5
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		player.CameraMode = Enum.CameraMode.Classic
		-- Kurz rauszoomen, sonst bleibt die Kamera in der Ego-Ansicht hängen
		player.CameraMinZoomDistance = 12
		task.delay(0.1, function()
			if player.CameraMode == Enum.CameraMode.Classic then
				player.CameraMinZoomDistance = 0.5
			end
		end)
	end
end

-- Zielen an/aus (von WeaponClient), fov = Sichtfeld der Waffe beim Zielen
function Movement.SetAiming(on, fov)
	aiming = on
	aimFov = fov or aimFov
	apply()
end

-- Sichtfeld und Empfindlichkeit aus den Einstellungen
function Movement.SetFov(fov)
	normalFov = fov
	apply()
end

function Movement.GetFov()
	return normalFov
end

function Movement.SetSensitivity(value)
	sensitivity = value
	apply()
end

function Movement.GetSensitivity()
	return sensitivity
end

function Movement.Init()
	-- First Person nur in Kampfmodi, im Hub normale Kamera
	local function updateCamera()
		Movement.SetFirstPerson(Modes.IsFighting(player))
	end
	updateCamera()
	player:GetAttributeChangedSignal("Mode"):Connect(updateCamera)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = true
			apply()
		elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
			local humanoid = getHumanoid()
			local wasSprinting = sprintHeld and not aiming and humanoid and humanoid.MoveDirection.Magnitude > 0.5
			crouchHeld = true
			if wasSprinting and Modes.IsFighting(player) then
				startSlide()
			end
			apply()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = false
			apply()
		elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
			crouchHeld = false
			apply()
		end
	end)

	local function onCharacter(character)
		local humanoid = character:WaitForChild("Humanoid")
		normalHipHeight = humanoid.HipHeight
		sliding = false
		aiming = false
		character:GetAttributeChangedSignal("SpeedMultiplier"):Connect(apply)
		character:GetAttributeChangedSignal("Agent"):Connect(apply)
		apply()
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return Movement

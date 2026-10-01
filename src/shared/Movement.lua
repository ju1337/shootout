-- Movement (ModuleScript, nur Client)
-- First-Person-Ansicht und Sprinten mit Shift. Springen ist Roblox-Standard (Leertaste).
-- Grundtempo kommt vom Agenten, Fähigkeiten können es per "SpeedMultiplier" erhöhen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local Modes = require(Shared.Modes)

local player = Players.LocalPlayer

local Movement = {}

local DEFAULT_SPEED = 16
local SPRINT_FACTOR = 1.5
local SPRINT_FOV_BONUS = 8
local normalFov = 70

local sprinting = false

local function apply()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local agent = AgentConfig.Get(character:GetAttribute("Agent"))
		local speed = (agent and agent.WalkSpeed or DEFAULT_SPEED) * (character:GetAttribute("SpeedMultiplier") or 1)
		humanoid.WalkSpeed = sprinting and speed * SPRINT_FACTOR or speed
	end
	workspace.CurrentCamera.FieldOfView = sprinting and normalFov + SPRINT_FOV_BONUS or normalFov
end

-- Sichtfeld aus den Einstellungen
function Movement.SetFov(fov)
	normalFov = fov
	apply()
end

function Movement.GetFov()
	return normalFov
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

function Movement.Init()
	-- First Person nur in Kampfmodi, im Hub normale Kamera
	local function updateCamera()
		Movement.SetFirstPerson(Modes.IsFighting(player))
	end
	updateCamera()
	player:GetAttributeChangedSignal("Mode"):Connect(updateCamera)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.LeftShift then
			sprinting = true
			apply()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprinting = false
			apply()
		end
	end)

	local function onCharacter(character)
		character:WaitForChild("Humanoid")
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

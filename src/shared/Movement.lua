-- Movement (ModuleScript, nur Client)
-- First-Person-Ansicht, Sprinten (Shift), Ducken (STRG oder C, gedrückt halten),
-- Sliden (im Sprint ducken), Klettern über Kanten (Springen vor einer Kante) und Zielen
-- (setzt WeaponClient über SetAiming).
-- Grundtempo kommt vom Agenten, Fähigkeiten können es per "SpeedMultiplier" erhöhen.
-- Kamera in Kampfmodi: Ego-Perspektive oder Schulterkamera wie bei Rogue Company (Einstellung,
-- jederzeit mit T umschalten).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local Modes = require(Shared.Modes)
local Remotes = require(Shared.Remotes)
local BuyConfig = require(Shared.BuyConfig)

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
local MANTLE_MIN = 2.5         -- niedrigere Hindernisse einfach überspringen
local MANTLE_MAX = 6.5         -- höchste Kante, an der man sich hochzieht
local MANTLE_REACH = 3.5       -- so nah muss die Wand vor einem sein
local MANTLE_TIME = 0.3

local normalFov = 70
local sensitivity = 1
local sprintHeld = false
local crouchHeld = false
local aiming = false
local aimFov = 50
local sliding = false
local lastSlide = 0
local normalHipHeight = nil
local mantling = false
local thirdPerson = false        -- Einstellung: Schulterkamera statt Ego-Perspektive
local SHOULDER_OFFSET = Vector3.new(2.2, 0.8, 0)
local shoulderSide = 1           -- 1 = rechte Schulter, -1 = linke (Taste X)
local SHOULDER_DISTANCE = 9
local SHOULDER_AIM_DISTANCE = 5

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
		if BuyConfig.Has(player, "Runner") then
			speed *= BuyConfig.RunnerFactor
		end
		-- Stacheldraht (TRAPPER): 50 % langsamer
		if (character:GetAttribute("SlowedUntil") or 0) > workspace:GetServerTimeNow() then
			speed *= 0.5
		end
		humanoid.WalkSpeed = speed

		-- Ducken: Kamera tiefer, Körper sinkt ab
		normalHipHeight = normalHipHeight or humanoid.HipHeight
		local crouched = isCrouched() and not isDropping(humanoid)
		local offset = crouched and CROUCH_CAMERA or Vector3.zero
		if thirdPerson and Modes.IsFighting(player) then
			offset += Vector3.new(SHOULDER_OFFSET.X * shoulderSide, SHOULDER_OFFSET.Y, 0) -- über die Schulter
			local distance = aiming and SHOULDER_AIM_DISTANCE or SHOULDER_DISTANCE
			player.CameraMinZoomDistance = distance
			player.CameraMaxZoomDistance = distance
		end
		humanoid.CameraOffset = offset
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

-- Klettern: Wand vor einem, oben eine Kante mit Platz darüber -> hochziehen
local function tryMantle()
	local humanoid, character = getHumanoid()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if mantling or sliding or not humanoid or not root or humanoid.Health <= 0 or isDropping(humanoid) then
		return
	end
	if character:GetAttribute("Downed") then
		return
	end
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.01 then
		return
	end
	look = look.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local wall = workspace:Raycast(root.Position, look * MANTLE_REACH, params)
	if not wall then
		return
	end
	local feetY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	local probe = Vector3.new(root.Position.X, feetY + MANTLE_MAX + 0.5, root.Position.Z) + look * (wall.Distance + 1.2)
	local ledge = workspace:Raycast(probe, Vector3.new(0, -(MANTLE_MAX + 1), 0), params)
	if not ledge then
		return
	end
	local height = ledge.Position.Y - feetY
	if height < MANTLE_MIN or height > MANTLE_MAX then
		return
	end
	-- Oben muss Platz für den Körper sein
	if workspace:Raycast(ledge.Position + Vector3.new(0, 0.2, 0), Vector3.new(0, 5, 0), params) then
		return
	end

	mantling = true
	local startPos = root.Position
	local target = ledge.Position + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 + 0.1, 0)
	local rotation = CFrame.lookAt(Vector3.zero, look)
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = math.min(1, (os.clock() - started) / MANTLE_TIME)
		-- Erst hoch, dann nach vorne
		local up = math.min(1, t * 1.6)
		local position = Vector3.new(
			startPos.X + (target.X - startPos.X) * t,
			startPos.Y + (target.Y - startPos.Y) * up,
			startPos.Z + (target.Z - startPos.Z) * t)
		root.CFrame = CFrame.new(position) * rotation
		root.AssemblyLinearVelocity = Vector3.zero
		if t >= 1 or not root.Parent then
			connection:Disconnect()
			mantling = false
		end
	end)
end

-- An = First Person, Aus = Kamera hinter dem Ziel (z.B. beim Zuschauen)
function Movement.SetFirstPerson(on: boolean)
	player.CameraMaxZoomDistance = 128
	if on and thirdPerson then
		-- Schulterkamera: Abstand fest, Maus gesperrt (siehe RenderStep unten)
		player.CameraMode = Enum.CameraMode.Classic
		apply()
		return
	end
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

-- Kamera passend zum Modus setzen (Hub: frei, Kampf: Ego oder Schulter)
function Movement.ApplyCamera()
	Movement.SetFirstPerson(Modes.IsFighting(player))
end

-- Einstellung Schulterkamera an/aus
function Movement.SetThirdPerson(on)
	thirdPerson = on
	local humanoid = getHumanoid()
	if humanoid and not on then
		humanoid.AutoRotate = true
	end
	Movement.ApplyCamera()
	apply()
end

-- Gespeicherte Einstellung (unabhängig davon, ob man gerade kämpft)
function Movement.GetThirdPersonSetting()
	return thirdPerson
end

function Movement.IsThirdPerson()
	return thirdPerson and Modes.IsFighting(player)
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
		Movement.ApplyCamera()
		local humanoid = getHumanoid()
		if humanoid and not Movement.IsThirdPerson() then
			humanoid.AutoRotate = true
		end
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
	-- Schulterkamera: Maus mittig sperren, Körper dreht mit der Kamera (wie Shift-Lock)
	RunService:BindToRenderStep("ShoulderCamera", Enum.RenderPriority.Camera.Value + 1, function()
		if not Movement.IsThirdPerson() or player.CameraMode ~= Enum.CameraMode.Classic then
			return
		end
		local humanoid, character = getHumanoid()
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root or humanoid.Health <= 0 or humanoid.PlatformStand or mantling then
			return
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		humanoid.AutoRotate = false
		local look = workspace.CurrentCamera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end)

	-- Springen vor einer Kante = hochziehen
	UserInputService.JumpRequest:Connect(tryMantle)

	-- T: zwischen Ego- und Schulterkamera wechseln (wird im Profil gespeichert), X: Schulter wechseln
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.X and Movement.IsThirdPerson() then
			shoulderSide = -shoulderSide
			apply()
			return
		end
		if input.KeyCode ~= Enum.KeyCode.T then
			return
		end
		Movement.SetThirdPerson(not thirdPerson)
		Remotes.ShopAction:FireServer("SaveSettings", {
			Fov = normalFov,
			Sensitivity = sensitivity,
			ThirdPerson = thirdPerson,
		})
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
		character:GetAttributeChangedSignal("SlowedUntil"):Connect(function()
			apply()
			task.delay(0.6, apply) -- danach wieder normales Tempo
		end)
		player:GetAttributeChangedSignal("Buy_Runner"):Connect(apply)
		-- Neuer Charakter (z.B. nach Todeskamera): Kamera wieder auf Ego/Schulter
		if not workspace.CurrentCamera:GetAttribute("KillCam") then
			Movement.ApplyCamera()
		end
		apply()
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return Movement

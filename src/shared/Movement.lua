-- Movement (ModuleScript, nur Client)
-- First-Person-Ansicht, Sprinten (Shift), Ducken (STRG oder C, gedrückt halten),
-- Sliden (im Sprint ducken), Klettern über Kanten (Springen vor einer Kante) und Zielen
-- (setzt WeaponClient über SetAiming).
-- Grundtempo kommt vom Agenten, Fähigkeiten können es per "SpeedMultiplier" erhöhen.
-- Kamera in Kampfmodi: Ego-Perspektive oder Schulterkamera wie bei Rogue Company (Einstellung,
-- jederzeit mit T umschalten). Der Charakter steht links im Bild, die Bildmitte (Fadenkreuz) bleibt frei –
-- auch beim Zielen, wenn die Kamera näher heranrückt. Steht rechts eine Wand, rückt die Kamera seitlich
-- an den Kopf heran, statt durch die Wand zu schauen. Sichtfeld, Abstand und Kamera-Versatz gleiten weich
-- (RenderStep "CameraSmooth"). Schießen unterbricht den Sprint kurz.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local Modes = require(Shared.Modes)
local BuyConfig = require(Shared.BuyConfig)
local InputActions = require(Shared.InputActions)
local PlayerSettings = require(Shared.PlayerSettings)

local player = Players.LocalPlayer

local Movement = {}

local DEFAULT_SPEED = 16
local SPRINT_FACTOR = 1.5
local CROUCH_FACTOR = 0.5
local AIM_FACTOR = 0.6         -- langsamer beim Zielen
local aimSensitivity = 0.6     -- Maus langsamer beim Zielen (Einstellung "Empfindlichkeit beim Zielen")
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
local inVehicle = false          -- sitzt in einem Fahrzeug der offenen Welt: Verfolgerkamera statt Ego/Schulter
-- Schulterkamera: seitlicher Versatz so groß, dass der Charakter (Arme bis 2 Studs neben der Mitte) die
-- Bildmitte mit ca. 8° Abstand freilässt; beim Zielen näher heran, aber weiter seitlich als der Arm
local SHOULDER_OFFSET = Vector3.new(3.4, 1.0, 0)
local SHOULDER_AIM_OFFSET = Vector3.new(2.7, 0.8, 0)
local shoulderSide = 1           -- 1 = rechte Schulter, -1 = linke (Taste H)
local SHOULDER_DISTANCE = 9
local SHOULDER_AIM_DISTANCE = 5.5
local SHOULDER_WALL_MARGIN = 0.8 -- so weit bleibt die Kamera seitlich von Wänden weg
local HEAD_HEIGHT = 1.5          -- Höhe des Kamera-Ziels über dem HumanoidRootPart (Roblox-Kamera, R15)
local CAMERA_SMOOTH = 12         -- wie schnell Sichtfeld, Abstand und Versatz nachziehen
local sprintBlockedUntil = 0     -- Schießen unterbricht den Sprint kurz
local fovOverride = nil          -- z.B. Fallschirmsprung
local targetFov = 70
local targetOffset = Vector3.zero
local targetDistance = SHOULDER_DISTANCE
local currentDistance = nil      -- aktueller Abstand der Schulterkamera (nil = nicht aktiv)

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

local function isSprinting()
	return sprintHeld and not aiming and not isCrouched() and os.clock() >= sprintBlockedUntil
end

local function apply()
	local humanoid, character = getHumanoid()
	local sprinting = isSprinting()
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

		-- Ducken: Kamera tiefer, Körper sinkt ab (Kamera-Versatz gleitet im RenderStep "CameraSmooth")
		normalHipHeight = normalHipHeight or humanoid.HipHeight
		local crouched = isCrouched() and not isDropping(humanoid)
		local offset = crouched and CROUCH_CAMERA or Vector3.zero
		if thirdPerson and Modes.IsFighting(player) and not inVehicle then
			local shoulder = aiming and SHOULDER_AIM_OFFSET or SHOULDER_OFFSET
			offset += Vector3.new(shoulder.X * shoulderSide, shoulder.Y, 0) -- über die Schulter
			targetDistance = aiming and SHOULDER_AIM_DISTANCE or SHOULDER_DISTANCE
		end
		targetOffset = offset
		humanoid.HipHeight = crouched and normalHipHeight * CROUCH_HIP_FACTOR or normalHipHeight
	end

	if aiming then
		targetFov = aimFov
	else
		targetFov = sprinting and normalFov + SPRINT_FOV_BONUS or normalFov
	end
	UserInputService.MouseDeltaSensitivity = aiming and sensitivity * aimSensitivity or sensitivity
end

-- Seitlichen Schulter-Versatz kürzen, wenn neben dem Kopf eine Wand der Map ist (sonst schaut die
-- Kamera durch die Wand). Gibt den erlaubten Versatz und ob gekürzt wurde zurück.
local shoulderParams = RaycastParams.new()
shoulderParams.FilterType = Enum.RaycastFilterType.Include
local function clampShoulder(character, offset)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local maps = workspace:FindFirstChild("Maps")
	if not root or not maps or math.abs(offset.X) < 0.05 then
		return offset, false
	end
	shoulderParams.FilterDescendantsInstances = { maps }
	local origin = (root :: BasePart).CFrame * Vector3.new(0, HEAD_HEIGHT + offset.Y, 0)
	local side = (root :: BasePart).CFrame.RightVector * offset.X
	local result = workspace:Raycast(origin, side + side.Unit * SHOULDER_WALL_MARGIN, shoulderParams)
	if not result then
		return offset, false
	end
	local free = math.max(0, (result.Position - origin).Magnitude - SHOULDER_WALL_MARGIN)
	if free >= math.abs(offset.X) then
		return offset, false
	end
	return Vector3.new(math.sign(offset.X) * free, offset.Y, offset.Z), true
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

-- Kamera passend zum Modus setzen (Hub: frei, Kampf: Ego oder Schulter; im Fahrzeug: Verfolgerkamera)
function Movement.ApplyCamera()
	if inVehicle then
		return
	end
	Movement.SetFirstPerson(Modes.IsFighting(player))
end

-- Fahrzeug der offenen Welt: Kamera hinter dem Fahrzeug (Roblox folgt dem Fahrersitz), Maus frei.
-- Beim Aussteigen wieder Ego- bzw. Schulterkamera.
function Movement.SetVehicle(on)
	if inVehicle == on then
		return
	end
	inVehicle = on
	if on then
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = 45
		player.CameraMinZoomDistance = 16 -- erst herauszoomen, dann frei
		task.delay(0.2, function()
			if inVehicle then
				player.CameraMinZoomDistance = 8
			end
		end)
	else
		Movement.ApplyCamera()
	end
	apply()
end

function Movement.InVehicle()
	return inVehicle
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
	return thirdPerson and Modes.IsFighting(player) and not inVehicle
end

-- Zielen an/aus (von WeaponClient), fov = Sichtfeld der Waffe beim Zielen
function Movement.SetAiming(on, fov)
	aiming = on
	aimFov = fov or aimFov
	apply()
end

-- Sprintet der Spieler gerade (gedrückt, in Bewegung, nicht durch Schießen unterbrochen)?
function Movement.IsSprinting()
	local humanoid = getHumanoid()
	return isSprinting() and Modes.IsFighting(player) and humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
end

-- Schießen unterbricht den Sprint für seconds Sekunden (danach geht er von selbst weiter)
function Movement.SuppressSprint(seconds)
	local was = isSprinting()
	sprintBlockedUntil = math.max(sprintBlockedUntil, os.clock() + seconds)
	if was then
		apply()
	end
end

-- Sichtfeld fest vorgeben (z.B. Fallschirmsprung), nil = wieder normal
function Movement.SetFovOverride(fov)
	fovOverride = fov
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

	-- Sprinten und Ducken über InputActions. Tastatur: gedrückt halten.
	-- Controller (L3) und Touch: Sprinten schaltet um und endet, wenn man stehen bleibt.
	local function setCrouch(on)
		local humanoid = getHumanoid()
		local wasSprinting = sprintHeld and not aiming and humanoid and humanoid.MoveDirection.Magnitude > 0.5
		crouchHeld = on
		if on and wasSprinting and Modes.IsFighting(player) then
			startSlide()
		end
		apply()
	end
	InputActions.Bind("Sprint", function(began)
		if InputActions.Device() == "Keyboard" then
			sprintHeld = began
		elseif began then
			sprintHeld = not sprintHeld
		end
		apply()
	end)
	InputActions.Bind("Crouch", function(began)
		if InputActions.Device() == "Touch" then
			if began then
				setCrouch(not crouchHeld)
			end
		else
			setCrouch(began)
		end
	end)
	local wasBlocked = false
	RunService.Heartbeat:Connect(function()
		if sprintHeld and InputActions.Device() ~= "Keyboard" then
			local humanoid = getHumanoid()
			if not humanoid or humanoid.MoveDirection.Magnitude < 0.1 then
				sprintHeld = false
				apply()
			end
		end
		-- Sprint-Unterbrechung durch Schießen vorbei: Tempo wieder anpassen
		local blocked = os.clock() < sprintBlockedUntil
		if blocked ~= wasBlocked then
			wasBlocked = blocked
			apply()
		end
	end)
	-- Sichtfeld, Kamera-Versatz (Ducken, Schulter) und Abstand der Schulterkamera gleiten weich.
	-- Läuft vor der Kamera von Roblox, damit sie die neuen Werte noch im selben Bild benutzt.
	RunService:BindToRenderStep("CameraSmooth", Enum.RenderPriority.Camera.Value - 1, function(dt)
		local camera = workspace.CurrentCamera
		local alpha = math.min(1, dt * CAMERA_SMOOTH)
		local fov = fovOverride or targetFov
		if math.abs(camera.FieldOfView - fov) > 0.01 then
			camera.FieldOfView += (fov - camera.FieldOfView) * alpha
		end
		local humanoid, character = getHumanoid()
		if humanoid then
			local goal, blocked = targetOffset, false
			if Movement.IsThirdPerson() then
				goal, blocked = clampShoulder(character, targetOffset)
			end
			local current = humanoid.CameraOffset
			local nextOffset = current:Lerp(goal, alpha)
			-- An eine Wand heran sofort (nicht hindurchschauen), wieder weg davon weich
			if blocked and math.abs(nextOffset.X) > math.abs(goal.X) then
				nextOffset = Vector3.new(goal.X, nextOffset.Y, nextOffset.Z)
			end
			if (current - nextOffset).Magnitude > 0.001 then
				humanoid.CameraOffset = nextOffset
			end
		end
		local active = Movement.IsThirdPerson() and player.CameraMode == Enum.CameraMode.Classic and humanoid ~= nil
			and humanoid.Health > 0 and not humanoid.PlatformStand and not camera:GetAttribute("KillCam")
		if active then
			currentDistance = currentDistance and currentDistance + (targetDistance - currentDistance) * alpha or targetDistance
			player.CameraMinZoomDistance = currentDistance
			player.CameraMaxZoomDistance = currentDistance
		else
			currentDistance = nil
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

	-- Springen vor einer Kante = hochziehen (auch über den eigenen Touch-Springen-Knopf)
	UserInputService.JumpRequest:Connect(tryMantle)
	InputActions.Bind("Jump", function(began)
		if began then
			tryMantle()
		end
	end)

	-- Einstellungen (Seite OPTIONEN) übernehmen: jetzt und bei jeder Änderung
	local function applySetting(key, value)
		if key == "Fov" then
			Movement.SetFov(value)
		elseif key == "Sensitivity" then
			Movement.SetSensitivity(value)
		elseif key == "AimSensitivity" then
			aimSensitivity = value
			apply()
		elseif key == "ThirdPerson" then
			Movement.SetThirdPerson(value == true)
		elseif key == "ShoulderLeft" then
			shoulderSide = value and -1 or 1
			apply()
		end
	end
	for _, setting in PlayerSettings.List do
		applySetting(setting.Key, PlayerSettings.Get(setting.Key))
	end
	PlayerSettings.Changed:Connect(applySetting)

	-- Kamera-Taste: zwischen Ego- und Schulterkamera wechseln (wird als Einstellung gespeichert),
	-- Schulter-Taste: Schulter wechseln (nur für dieses Spiel, Start-Schulter steht in den Einstellungen)
	InputActions.Bind("Shoulder", function(began)
		-- Controller: Steuerkreuz rechts löst sonst eine bereite Killstreak aus (KillstreakHUD)
		local ready = player:GetAttribute("KillstreakReady")
		local padBusy = InputActions.Device() == "Gamepad" and type(ready) == "string" and ready ~= "{}" and ready ~= "[]"
		if began and Movement.IsThirdPerson() and not padBusy then
			shoulderSide = -shoulderSide
			apply()
		end
	end)
	InputActions.Bind("Camera", function(began)
		if not began then
			return
		end
		PlayerSettings.Set("ThirdPerson", not thirdPerson)
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

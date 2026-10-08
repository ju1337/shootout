-- Movement (ModuleScript, nur Client)
-- Bewegung und Kamera des eigenen Charakters. Die Rechnungen stehen in MovementPhysics, hier nur Ablauf und Roblox.
--   * Tempo: Grundtempo vom Agenten (Fähigkeiten können es per "SpeedMultiplier" erhöhen), Sprinten (Shift), Ducken
--     (STRG oder C, gedrückt halten), Zielen. Das Tempo läuft weich an und ab (WalkSpeed folgt einer Rampe). Sprinten
--     nicht rückwärts; halten oder umschalten (Einstellung "Sprinten").
--   * Rutschen: im Sprint (oder mit Schwung) ducken. Schub aus dem aktuellen Tempo, Reibung, bergab schneller und
--     bergauf kürzer, mit der Eingabe lenkbar. Springen aus dem Rutschen nimmt den Schwung mit in die Luft, beim Landen
--     mit gedrückter Ducken-Taste geht es direkt weiter (Schub lädt erst wieder auf: kein Dauer-Tempo).
--   * Springen: Coyote-Time (kurz nach dem Verlassen einer Kante geht der Sprung noch) und Sprungpuffer (kurz vor dem
--     Landen gedrückt = Sprung beim Landen). Harte Landungen bremsen kurz und lassen die Kamera eintauchen. In der
--     Luft lenkt man nur begrenzt (der Sprung trägt seinen Schwung, kein Umdrehen auf der Stelle). Beim Fallen zieht
--     die Schwerkraft stärker (knackiger Sprung, gleiche Höhe).
--   * Hindernisse: Springen vor einem niedrigen, dünnen Hindernis = drüberspringen (Vault, der Schwung bleibt), vor
--     einer höheren Kante = hochziehen. Klappt auch aus dem Sprung heraus, wenn man auf die Kante zu läuft. Auf
--     Dächer (Teile namens "Roof") zieht man sich nie hoch: dahin geht es nur über Treppen und Leitern.
--   * Kamera in Kampfmodi: Ego-Perspektive oder Schulterkamera wie bei Rogue Company (Einstellung, jederzeit mit T
--     umschalten). Der Charakter steht links im Bild, die Bildmitte (Fadenkreuz) bleibt frei – auch beim Zielen, wenn
--     die Kamera näher heranrückt. Steht rechts eine Wand, rückt die Kamera seitlich an den Kopf heran, statt durch die
--     Wand zu schauen. Sichtfeld, Abstand und Kamera-Versatz gleiten weich (RenderStep "CameraSmooth"); dazu leichtes
--     Neigen beim Seitwärtslaufen und Rutschen, Wippen beim Laufen (Ego) und Eintauchen beim Landen.
--   * Schießen unterbricht den Sprint kurz. Zielen setzt WeaponClient über SetAiming.

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
local P = require(Shared.MovementPhysics)

local player = Players.LocalPlayer

local Movement = {}

local DEFAULT_SPEED = 16
local aimSensitivity = 0.6     -- Maus langsamer beim Zielen (Einstellung "Empfindlichkeit beim Zielen")
local SPRINT_FOV_BONUS = 8
local SLIDE_FOV_BONUS = 6
local CROUCH_CAMERA = Vector3.new(0, -1.3, 0)
local CROUCH_HIP_FACTOR = 0.55 -- Körper sinkt ab (kleineres Ziel)
local CROUCH_TIME = 0.12       -- so lange dauert Hinhocken und Aufstehen
local SLIDE_AIR_TIME = 0.18    -- so lange ohne Boden, dann ist man über eine Kante gerutscht (Schwung in die Luft)
local JUMP_INTENT = 0.4        -- so lange nach dem Drücken zählt Springen für das Hochziehen aus der Luft
local DIP_SPRING = 140         -- Federhärte des Eintauchens beim Landen
local DIP_DAMPING = 18
local TILT_SMOOTH = 14         -- wie schnell die Neigung nachzieht
local MOMENTUM_GRACE = 0.3     -- so lange bleibt Schwung am Boden stehen, bis der Absprung kommt

local normalFov = 70
local sensitivity = 1
local sprintHeld = false
local crouchHeld = false
local aiming = false
local aimFov = 50
local normalHipHeight = nil
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
local CAMERA_SMOOTH = 18         -- wie schnell Sichtfeld, Abstand und Versatz nachziehen
local sprintBlockedUntil = 0     -- Schießen unterbricht den Sprint kurz
local fovOverride = nil          -- z.B. Fallschirmsprung
local targetFov = 70
local targetOffset = Vector3.zero
local baseOffset = Vector3.zero  -- geglätteter Kamera-Versatz (ohne Wippen und Eintauchen)
local targetDistance = SHOULDER_DISTANCE
local currentDistance = nil      -- aktueller Abstand der Schulterkamera (nil = nicht aktiv)

-- Bewegungs-Zustand
local speedTarget = DEFAULT_SPEED -- Ziel für WalkSpeed (apply), die Rampe läuft im Heartbeat
local walkSpeed = nil             -- zuletzt gesetztes WalkSpeed
local hipTarget = nil
local slide = nil                 -- { Speed, Dir, Started, AirTime }
local lastSlideEnd = -math.huge
local move = nil                  -- Hindernis: { Kind, Started, Duration, Start, Near, Far, Land, Target, Dir, ExitSpeed }
local airMomentum = 0             -- Schwung in der Luft (Absprung, Rutschen, Vault)
local momentumAt = -math.huge     -- wann er gesetzt wurde (am Boden verfällt er nach MOMENTUM_GRACE)
local grounded = true
local leftGroundAt = nil          -- wann der Boden verlassen wurde (Coyote-Time)
local jumpedAt = nil              -- letzter Absprung (Zustand Jumping)
local jumpRequestAt = nil         -- letzter Sprung-Druck in der Luft (Sprungpuffer, Hochziehen)
local lastGroundY = nil           -- Höhe der Füße beim letzten Bodenkontakt
local fallSpeed = 0
local slowUntil = 0               -- harte Landung: so lange langsamer
local dip, dipVelocity = 0, 0     -- Kamera-Eintauchen (Studs nach unten) und seine Geschwindigkeit
local bobPhase = 0
local roll = 0                    -- aktuelle Kamera-Neigung (Grad)
local slideBlend = 0              -- 0..1 weich für Kamera-Neigung und Sichtfeld beim Rutschen
local rawMove = Vector3.zero      -- Eingabe vom ControlModule in diesem Bild (bevor Rutschen/Luft sie überschreiben)
local lastMoveOut = nil           -- zuletzt selbst gesetzte Laufrichtung (Rutschen, Luft)
local airMove = nil               -- Laufrichtung in der Luft (Länge 0..1), nil = am Boden
local sprintForward = true        -- Eingabe zeigt nicht nach hinten (sonst kein Sprint)
local fallForce = nil             -- VectorForce: stärkere Schwerkraft beim Fallen (P.FallGravity)

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function getHumanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid"), character
end

-- Fallschirmsprung, niedergeschlagen, Noclip: dann nichts an Haltung und Tempo ändern
local function isDropping(humanoid)
	return humanoid.PlatformStand
end

local function isCrouched()
	return (crouchHeld or slide ~= nil) and Modes.IsFighting(player)
end

local function isSprinting()
	return sprintHeld and sprintForward and not aiming and not isCrouched() and os.clock() >= sprintBlockedUntil
end

-- Grundtempo ohne Sprint/Ducken/Zielen (Agent, Fähigkeiten, Runner, Stacheldraht)
local function baseSpeed(character)
	local agent = character and AgentConfig.Get(character:GetAttribute("Agent"))
	local speed = (agent and agent.WalkSpeed or DEFAULT_SPEED) * P.SpeedScale
		* (character and character:GetAttribute("SpeedMultiplier") or 1)
	if BuyConfig.Has(player, "Runner") then
		speed *= BuyConfig.RunnerFactor
	end
	-- Stacheldraht (TRAPPER): 50 % langsamer
	if character and (character:GetAttribute("SlowedUntil") or 0) > workspace:GetServerTimeNow() then
		speed *= 0.5
	end
	return speed
end

-- Eingabe des Spielers (nicht die beim Rutschen oder in der Luft überschriebene Laufrichtung)
local function wishMove(humanoid)
	return lastMoveOut and rawMove or humanoid.MoveDirection
end

-- Sprinten halten (Tastatur, Standard) oder umschalten (Einstellung, Controller L3, Touch)
local function holdSprint()
	return InputActions.Device() == "Keyboard" and not PlayerSettings.Get("ToggleSprint")
end

local function feetOf(root, humanoid)
	return root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
end

-- Schwung für die Luft merken (höchstens AirMomentumMax): in der Luft hält das Tempo, statt abzubremsen
local function giveMomentum(speed)
	airMomentum = math.min(P.AirMomentumMax, math.max(airMomentum, speed or 0))
	momentumAt = os.clock()
end

local function apply()
	local humanoid, character = getHumanoid()
	local sprinting = isSprinting()
	if humanoid then
		local speed = baseSpeed(character)
		if sprinting then
			speed *= P.SprintFactor
		elseif isCrouched() then
			speed *= P.CrouchFactor
		end
		if aiming then
			speed *= P.AimFactor
		end
		speedTarget = speed

		-- Ducken: Kamera tiefer, Körper sinkt ab (beides gleitet: Versatz im RenderStep, Hüfte im Heartbeat)
		normalHipHeight = normalHipHeight or humanoid.HipHeight
		local crouched = isCrouched() and not isDropping(humanoid)
		local offset = crouched and CROUCH_CAMERA or Vector3.zero
		if thirdPerson and Modes.IsFighting(player) and not inVehicle then
			local shoulder = aiming and SHOULDER_AIM_OFFSET or SHOULDER_OFFSET
			offset += Vector3.new(shoulder.X * shoulderSide, shoulder.Y, 0) -- über die Schulter
			targetDistance = aiming and SHOULDER_AIM_DISTANCE or SHOULDER_DISTANCE
		end
		targetOffset = offset
		hipTarget = crouched and normalHipHeight * CROUCH_HIP_FACTOR or normalHipHeight
	end

	if aiming then
		targetFov = aimFov
	else
		-- Rutschen fühlt sich schneller an als der Sprint: dessen Bonus bleibt, dazu SLIDE_FOV_BONUS (RenderStep)
		targetFov = (sprinting or slide) and normalFov + SPRINT_FOV_BONUS or normalFov
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

-- ---------- Rutschen ----------
local function endSlide()
	if not slide then
		return
	end
	slide = nil
	lastSlideEnd = os.clock()
	apply()
end

-- Rutschen beginnen (im Sprint oder mit Schwung am Boden ducken). true = rutscht jetzt.
local function startSlide()
	local humanoid, character = getHumanoid()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or slide or move or not Modes.IsFighting(player) or isDropping(humanoid) or humanoid.Sit
		or humanoid.Health <= 0 or character:GetAttribute("Downed") then
		return false
	end
	if humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local input = wishMove(humanoid)
	local dir = P.Flat(input) or P.Flat(flat)
	local speed = math.max(flat.Magnitude, input.Magnitude > 0.5 and walkSpeed or 0)
	local base = baseSpeed(character)
	if not dir or speed < base * P.SlideMinStart then
		return false
	end
	slide = { Speed = P.SlideStart(speed, base * P.SprintFactor, os.clock() - lastSlideEnd), Dir = dir, Started = os.clock(),
		AirTime = 0 }
	walkSpeed = slide.Speed
	humanoid.WalkSpeed = walkSpeed
	apply()
	return true
end

local function stepSlide(dt, now, humanoid, character, root, onGround)
	if not onGround then
		slide.AirTime += dt
		if slide.AirTime > SLIDE_AIR_TIME then
			-- über eine Kante gerutscht: Schwung in die Luft mitnehmen
			giveMomentum(slide.Speed)
			endSlide()
			return
		end
	else
		slide.AirTime = 0
	end
	groundParams.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -(root.Size.Y / 2 + humanoid.HipHeight + 2.5), 0), groundParams)
	local slope = hit and P.SlopeAlong(hit.Normal, slide.Dir) or 0
	slide.Speed = P.SlideStep(slide.Speed, dt, slope, workspace.Gravity)
	if P.SlideOver(slide.Speed, baseSpeed(character) * P.CrouchFactor, now - slide.Started) then
		endSlide()
	end
end

-- ---------- Hindernisse: drüberspringen oder hochziehen ----------
-- Misst das Hindernis vor einem (Richtung dir): Abstand der Wand, Oberkante, dünn (dahinter geht es runter), Platz
-- über der Kante, Boden dahinter und wo das Hindernis endet. nil = keins.
local function probeObstacle(character, rootPosition, feet, dir)
	groundParams.FilterDescendantsInstances = { character }
	local wall = nil
	for _, height in { 0.9, 2.4, 4.2 } do
		local origin = Vector3.new(rootPosition.X, feet + height, rootPosition.Z)
		local hit = workspace:Raycast(origin, dir * P.Reach, groundParams)
		if hit and math.abs(hit.Normal.Y) < 0.7 and (not wall or hit.Distance < wall) then
			wall = hit.Distance
		end
	end
	if not wall then
		return nil
	end
	local top, topPosition = nil, nil
	for _, inset in { 0.25, 0.8 } do
		local origin = Vector3.new(rootPosition.X, feet + P.MantleMax + 1.2, rootPosition.Z) + dir * (wall + inset)
		local hit = workspace:Raycast(origin, Vector3.new(0, -(P.MantleMax + 1.2), 0), groundParams)
		if hit and hit.Instance.Name == "Roof" then
			return nil -- aufs Dach nur über Treppen und Leitern
		end
		if hit and (not top or hit.Position.Y > top) then
			top, topPosition = hit.Position.Y, hit.Position
		end
	end
	if not top then
		return nil
	end
	-- Platz über der Kante und für den Kopf auf dem Weg nach vorn (Fensterrahmen, Decken)
	local clear = not workspace:Raycast(topPosition + Vector3.new(0, 0.2, 0), Vector3.new(0, P.Clearance, 0), groundParams)
	if clear then
		local head = Vector3.new(rootPosition.X, top + 2.6, rootPosition.Z)
		clear = not workspace:Raycast(head, dir * (wall + 1.5), groundParams)
	end
	-- Wo endet die Oberseite? Dahinter tiefer als die Kante = dünn (drüberspringen)
	local far, behind = nil, nil
	for _, depth in { 1, 2, 3, P.VaultThickness } do
		local origin = Vector3.new(rootPosition.X, top + 0.6, rootPosition.Z) + dir * (wall + depth)
		local hit = workspace:Raycast(origin, Vector3.new(0, -(top - feet + 6), 0), groundParams)
		if not hit or hit.Position.Y < top - 1 then
			far, behind = depth, hit and hit.Position or nil
			break
		end
	end
	return { Wall = wall, Top = top, Thin = far ~= nil, Far = far, Behind = behind, Clear = clear }
end

local function startMove(kind, probe, dir, humanoid, root)
	local hip = root.Size.Y / 2 + humanoid.HipHeight -- Füße bis Mitte des HumanoidRootPart
	local start = root.Position
	local velocity = root.AssemblyLinearVelocity
	local speed = math.max(Vector3.new(velocity.X, 0, velocity.Z).Magnitude, walkSpeed or DEFAULT_SPEED)
	local feet = feetOf(root, humanoid)
	local flatStart = Vector3.new(start.X, 0, start.Z)
	local function at(distance, y)
		local p = flatStart + dir * distance
		return Vector3.new(p.X, y, p.Z)
	end
	local over = probe.Top + hip + 0.5
	if kind == "Vault" then
		local landY = probe.Behind and probe.Behind.Y + hip or math.min(start.Y, over - 2)
		move = { Kind = "Vault", Started = os.clock(), Start = start, Near = at(probe.Wall + 0.3, over),
			Far = at(probe.Wall + probe.Far, over), Land = at(probe.Wall + probe.Far + 1.6, landY), Dir = dir,
			Duration = P.VaultTime(probe.Top - feet, probe.Wall + probe.Far + 1.6), ExitSpeed = math.max(speed, DEFAULT_SPEED) }
	else
		move = { Kind = "Mantle", Started = os.clock(), Start = start, Target = at(probe.Wall + 1.4, probe.Top + hip + 0.05),
			Dir = dir, Duration = P.MantleTime(probe.Top - feet), ExitSpeed = 4 }
	end
	endSlide()
	airMomentum = 0
	dipVelocity -= 1.6 -- kleiner Ruck der Kamera beim Abstoßen
end

local function stepMove(now, root)
	local t = math.min(1, (now - move.Started) / move.Duration)
	local position = move.Kind == "Vault" and P.VaultPoint(move.Start, move.Near, move.Far, move.Land, t)
		or P.MantlePoint(move.Start, move.Target, t)
	root.CFrame = CFrame.new(position) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
	if t >= 1 then
		local exit = move.Dir * move.ExitSpeed
		root.AssemblyLinearVelocity = Vector3.new(exit.X, 0, exit.Z)
		if move.Kind == "Vault" then
			-- Schwung bleibt: weiter mit dem Tempo von vorher
			giveMomentum(move.ExitSpeed)
			walkSpeed = math.max(walkSpeed or 0, move.ExitSpeed)
		end
		move = nil
	end
end

-- Hindernis vor einem nehmen (inAir = aus dem Sprung heraus). true = Bewegung läuft.
local function tryObstacle(inAir)
	local humanoid, character = getHumanoid()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if move or not humanoid or not root or humanoid.Health <= 0 or isDropping(humanoid) or humanoid.Sit or inVehicle
		or character:GetAttribute("Downed") then
		return false
	end
	local input = wishMove(humanoid)
	local wish = P.Flat(input)
	if inAir and (not wish or input.Magnitude < 0.3) then
		return false -- in der Luft nur, wenn man auf die Kante zu will
	end
	local dir = wish or P.Flat(root.CFrame.LookVector)
	if not dir then
		return false
	end
	local feet = feetOf(root, humanoid)
	local probe = probeObstacle(character, root.Position, feet, dir)
	if not probe then
		return false
	end
	local fromGround = inAir and lastGroundY and (probe.Top - lastGroundY) or nil
	-- im Lauf über dünne Hindernisse drüber, langsam (oder im Stand) hinauf
	local velocity = root.AssemblyLinearVelocity
	local fast = Vector3.new(velocity.X, 0, velocity.Z).Magnitude >= baseSpeed(character) * 1.05
	local kind = P.Classify(probe.Top - feet, probe.Thin, fromGround, probe.Clear, fast)
	if not kind then
		return false
	end
	startMove(kind, probe, dir, humanoid, root)
	return true
end

-- ---------- Springen ----------
-- Springen gerade gedrückt? (Tastatur: Leertaste, Controller: ✕; Touch über die Zeitfenster nach dem Drücken)
local function jumpHeld()
	local device = InputActions.Device()
	if device == "Keyboard" then
		return UserInputService:IsKeyDown(Enum.KeyCode.Space)
	elseif device == "Gamepad" then
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
	end
	return false
end

local function onJumpRequest()
	local humanoid = getHumanoid()
	if not humanoid or humanoid.Health <= 0 or isDropping(humanoid) or humanoid.Sit or move or inVehicle then
		return
	end
	local now = os.clock()
	local inAir = humanoid.FloorMaterial == Enum.Material.Air
	if inAir then
		jumpRequestAt = now
	end
	if tryObstacle(inAir) then
		return
	end
	if slide then
		-- aus dem Rutschen springen: der Schwung kommt mit (der Humanoid springt selbst)
		giveMomentum(slide.Speed)
		endSlide()
		return
	end
	if inAir and P.CoyoteOk(now, leftGroundAt, jumpedAt) then
		-- gerade erst von der Kante: der Sprung zählt noch
		jumpedAt = now
		jumpRequestAt = nil
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

local function onLanded(humanoid, now)
	local impact = fallSpeed
	fallSpeed = 0
	airMomentum = 0
	dipVelocity -= P.LandDip(impact) * 9
	if impact >= P.HardLanding and not crouchHeld then
		slowUntil = now + P.HardLandingTime
	end
	if P.Buffered(now, jumpRequestAt) then
		jumpRequestAt = nil
		humanoid.Jump = true
		return
	end
	jumpRequestAt = nil
	if crouchHeld then
		startSlide() -- mit Schwung gelandet und Ducken gehalten: weiter rutschen
	end
end

-- ---------- Ablauf je Bild ----------
local function step(dt)
	local humanoid, character = getHumanoid()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		slide, move = nil, nil
		return
	end
	if isDropping(humanoid) or humanoid.Sit or inVehicle then
		if fallForce then
			fallForce.Force = Vector3.zero
		end
		slide, move, airMomentum = nil, nil, 0
		walkSpeed = humanoid.WalkSpeed
		return
	end
	local now = os.clock()
	local velocity = root.AssemblyLinearVelocity
	local onGround = humanoid.FloorMaterial ~= Enum.Material.Air
	if onGround and not grounded then
		grounded = true
		onLanded(humanoid, now)
	elseif not onGround and grounded then
		grounded = false
		leftGroundAt = now
		giveMomentum(walkSpeed) -- Absprung: das Tempo bleibt in der Luft (Sprint loslassen bremst nicht mitten im Sprung)
	end
	if onGround then
		lastGroundY = feetOf(root, humanoid)
	else
		fallSpeed = math.max(0, -velocity.Y)
	end
	-- beim Fallen stärkere Schwerkraft (nicht an Leitern, im Wasser, beim Hindernis)
	if fallForce then
		local state = humanoid:GetState()
		local falling = not onGround and not move and velocity.Y < 0 and state ~= Enum.HumanoidStateType.Climbing
			and state ~= Enum.HumanoidStateType.Swimming
		local force = falling and Vector3.new(0, -root.AssemblyMass * workspace.Gravity * (P.FallGravity - 1), 0) or Vector3.zero
		if fallForce.Force ~= force then
			fallForce.Force = force
		end
	end

	if move then
		stepMove(now, root)
		return
	end
	-- aus dem Sprung an eine Kante: hochziehen, solange Springen gedrückt ist oder kurz vorher gedrückt wurde
	if not onGround and (jumpHeld() or (jumpRequestAt ~= nil and now - jumpRequestAt <= JUMP_INTENT)
		or (jumpedAt ~= nil and now - jumpedAt <= JUMP_INTENT)) then
		if tryObstacle(true) then
			return
		end
	end
	if slide then
		stepSlide(dt, now, humanoid, character, root, onGround)
	end

	-- Tempo: Rampe zum Ziel, Rutschen direkt, in der Luft hält der Schwung
	local target = speedTarget
	if now < slowUntil then
		target *= P.HardLandingSlow
	end
	walkSpeed = walkSpeed or humanoid.WalkSpeed
	if onGround and airMomentum > 0 and now - momentumAt > MOMENTUM_GRACE then
		airMomentum = 0 -- kein Absprung gekommen (z.B. Decke über dem Kopf): Schwung verfällt
	end
	if slide then
		walkSpeed = slide.Speed
	elseif not onGround and airMomentum > 0 then
		airMomentum = P.AirStep(airMomentum, dt)
		walkSpeed = math.max(airMomentum, P.Approach(walkSpeed, target, dt))
	else
		walkSpeed = P.Approach(walkSpeed, target, dt)
	end
	if math.abs(humanoid.WalkSpeed - walkSpeed) > 0.01 then
		humanoid.WalkSpeed = walkSpeed
	end

	-- Ducken weich: Hüfte gleitet
	if hipTarget and normalHipHeight then
		local rate = normalHipHeight * (1 - CROUCH_HIP_FACTOR) / CROUCH_TIME
		local hip = humanoid.HipHeight
		local nextHip = hip < hipTarget and math.min(hipTarget, hip + rate * dt) or math.max(hipTarget, hip - rate * dt)
		if math.abs(nextHip - hip) > 0.0001 then
			humanoid.HipHeight = nextHip
		end
	end
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

-- Fahrzeug der offenen Welt: Kamera hinter dem Fahrzeug (Roblox folgt dem Fahrersitz), Maus frei. far = Helikopter
-- (Rotor und Heck brauchen mehr Abstand). Beim Aussteigen wieder Ego- bzw. Schulterkamera.
function Movement.SetVehicle(on, far)
	if inVehicle == on then
		return
	end
	inVehicle = on
	if on then
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = far and 90 or 45
		player.CameraMinZoomDistance = far and 32 or 16 -- erst herauszoomen, dann frei
		task.delay(0.2, function()
			if inVehicle then
				player.CameraMinZoomDistance = far and 14 or 8
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
	return isSprinting() and Modes.IsFighting(player) and humanoid ~= nil and wishMove(humanoid).Magnitude > 0.1
end

-- Rutscht der Spieler gerade? (Waffe in der Ego-Ansicht gekippt)
function Movement.IsSliding()
	return slide ~= nil
end

-- Springt er gerade über ein Hindernis oder zieht sich hoch? ("Vault", "Mantle" oder nil)
function Movement.Obstacle()
	return move and move.Kind or nil
end

-- Zustand für Tests und Anzeigen
function Movement.State()
	return { Slide = slide and slide.Speed or nil, SlideDir = slide and slide.Dir or nil, Obstacle = move and move.Kind or nil,
		AirMomentum = airMomentum, SpeedTarget = speedTarget, WalkSpeed = walkSpeed, SlowUntil = slowUntil }
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

-- Kamera-Effekte (Neigen, Wippen, Eintauchen) nur in der Ego- und Schulterkamera im Kampf, und nur solange Roblox die
-- Kamera führt (CameraType Custom rechnet sie jedes Bild neu; eine geskriptete Kamera würde sich sonst aufdrehen)
local function cameraEffectsOn(humanoid)
	local camera = workspace.CurrentCamera
	return Modes.IsFighting(player) and not inVehicle and humanoid ~= nil and humanoid.Health > 0 and not humanoid.PlatformStand
		and camera.CameraType == Enum.CameraType.Custom and not camera:GetAttribute("KillCam")
		and (player.CameraMode == Enum.CameraMode.LockFirstPerson or Movement.IsThirdPerson())
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
	-- Ducken im Sprint (oder mit Schwung) = Rutschen; Tippen reicht, das Rutschen läuft dann von selbst aus.
	local function setCrouch(on)
		crouchHeld = on
		if on then
			startSlide()
		end
		apply()
	end
	InputActions.Bind("Sprint", function(began)
		if holdSprint() then
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
	RunService.Heartbeat:Connect(function(dt)
		-- kein Sprint rückwärts; umgeschalteter Sprint endet beim Stehenbleiben oder Rückwärtslaufen
		local humanoid = getHumanoid()
		local forward = humanoid == nil or P.SprintAllowed(wishMove(humanoid), workspace.CurrentCamera.CFrame.LookVector)
		if sprintHeld and not holdSprint() and (not humanoid or wishMove(humanoid).Magnitude < 0.1 or not forward) then
			sprintHeld = false
			apply()
		end
		if forward ~= sprintForward then
			sprintForward = forward
			apply()
		end
		-- Sprint-Unterbrechung durch Schießen vorbei: Tempo wieder anpassen
		local blocked = os.clock() < sprintBlockedUntil
		if blocked ~= wasBlocked then
			wasBlocked = blocked
			apply()
		end
		step(math.min(dt, 0.1))
	end)
	-- Rutschen: Richtung nach der Eingabe lenken und den Humanoid in diese Richtung schieben. In der Luft: Laufrichtung
	-- folgt der Eingabe nur begrenzt (AirSteer). Läuft direkt nach dem ControlModule von Roblox (RenderPriority Input),
	-- damit dessen Eingabe gelesen und überschrieben wird.
	local FREE_STATES = { [Enum.HumanoidStateType.Climbing] = true, [Enum.HumanoidStateType.Swimming] = true,
		[Enum.HumanoidStateType.Seated] = true }
	RunService:BindToRenderStep("MovementSlide", Enum.RenderPriority.Input.Value + 1, function(dt)
		dt = math.min(dt, 0.1)
		local humanoid, character = getHumanoid()
		if not humanoid then
			return
		end
		rawMove = humanoid.MoveDirection -- frisch vom ControlModule (setzt sie jedes Bild neu)
		lastMoveOut = nil
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local airborne = humanoid.FloorMaterial == Enum.Material.Air and not slide and not move and not inVehicle
			and not isDropping(humanoid) and not FREE_STATES[humanoid:GetState()] and root ~= nil
		if not airborne then
			airMove = nil
		end
		local out = nil
		if slide then
			slide.Dir = P.Steer(slide.Dir, rawMove, dt)
			out = slide.Dir
		elseif airborne then
			if not airMove then
				-- Absprung: in die Richtung weiter, in die man gerade läuft
				local velocity = (root :: BasePart).AssemblyLinearVelocity
				local flat = Vector3.new(velocity.X, 0, velocity.Z) / math.max(walkSpeed or DEFAULT_SPEED, 1)
				airMove = flat.Magnitude > 1 and flat.Unit or flat
			end
			airMove = P.AirSteer(airMove, rawMove, dt)
			out = airMove
		end
		if out then
			humanoid:Move(out, false)
			lastMoveOut = out
		end
	end)
	-- Sichtfeld, Kamera-Versatz (Ducken, Schulter, Wippen, Eintauchen) und Abstand der Schulterkamera gleiten weich.
	-- Läuft vor der Kamera von Roblox, damit sie die neuen Werte noch im selben Bild benutzt.
	RunService:BindToRenderStep("CameraSmooth", Enum.RenderPriority.Camera.Value - 1, function(dt)
		dt = math.min(dt, 0.1)
		local camera = workspace.CurrentCamera
		local alpha = math.min(1, dt * CAMERA_SMOOTH)
		slideBlend += ((slide and 1 or 0) - slideBlend) * math.min(1, dt * 10)
		local fov = fovOverride or (targetFov + (aiming and 0 or SLIDE_FOV_BONUS * slideBlend))
		if math.abs(camera.FieldOfView - fov) > 0.01 then
			camera.FieldOfView += (fov - camera.FieldOfView) * alpha
		end
		local humanoid, character = getHumanoid()
		if humanoid then
			local goal, blocked = targetOffset, false
			if Movement.IsThirdPerson() then
				goal, blocked = clampShoulder(character, targetOffset)
			end
			local nextOffset = baseOffset:Lerp(goal, alpha)
			-- An eine Wand heran sofort (nicht hindurchschauen), wieder weg davon weich
			if blocked and math.abs(nextOffset.X) > math.abs(goal.X) then
				nextOffset = Vector3.new(goal.X, nextOffset.Y, nextOffset.Z)
			end
			baseOffset = nextOffset
			-- Eintauchen beim Landen (gedämpfte Feder) und Wippen beim Laufen (nur Ego, nicht beim Zielen)
			dipVelocity += (-DIP_SPRING * dip - DIP_DAMPING * dipVelocity) * dt
			dip = math.clamp(dip + dipVelocity * dt, -P.LandDipMax * 1.2, 0.4)
			local extra = 0
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if cameraEffectsOn(humanoid) and root then
				extra = dip
				local velocity = root.AssemblyLinearVelocity
				local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
				if grounded and not slide and not move and not aiming and not Movement.IsThirdPerson() then
					bobPhase += speed * dt * math.pi / 2.6 -- ein Schritt alle 2,6 Studs
					extra += P.Bob(bobPhase, speed / DEFAULT_SPEED)
				end
			end
			local offset = baseOffset + Vector3.new(0, extra, 0)
			if (humanoid.CameraOffset - offset).Magnitude > 0.001 then
				humanoid.CameraOffset = offset
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
		if not humanoid or not root or humanoid.Health <= 0 or humanoid.PlatformStand or move then
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
	-- Neigung der Kamera: seitwärts laufen leicht, rutschen deutlich. Nach der Kamera von Roblox und dem Rückstoß
	-- (die rechnet jedes Bild ohne Neigung neu, darum sammelt sich nichts an).
	RunService:BindToRenderStep("CameraTilt", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local humanoid, character = getHumanoid()
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		local goal = 0
		if root and cameraEffectsOn(humanoid) then
			local velocity = root.AssemblyLinearVelocity
			local strafe = velocity:Dot(camera.CFrame.RightVector) / math.max(DEFAULT_SPEED, speedTarget)
			goal = P.Roll(strafe, slideBlend, aiming)
		end
		roll += (goal - roll) * math.min(1, math.min(dt, 0.1) * TILT_SMOOTH)
		if camera.CameraType ~= Enum.CameraType.Custom then
			roll = 0
		elseif math.abs(roll) > 0.01 then
			camera.CFrame *= CFrame.Angles(0, 0, math.rad(roll))
		end
	end)

	-- Springen: Hindernis nehmen, aus dem Rutschen springen, Coyote-Time und Sprungpuffer (auch über den eigenen
	-- Touch-Springen-Knopf)
	UserInputService.JumpRequest:Connect(onJumpRequest)
	InputActions.Bind("Jump", function(began)
		if began then
			onJumpRequest()
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
		if character:GetAttribute("AgentModelCharacter") then
			-- Agentenmodell als Charakter: beim ersten Join kippt es sonst kurz um und liegt steif (FallingDown)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			if humanoid:GetState() == Enum.HumanoidStateType.FallingDown
				or humanoid:GetState() == Enum.HumanoidStateType.Ragdoll then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
		-- feste Sprunghöhe (sonst Roblox-Standard bzw. JumpPower 50 bei Agentenmodellen: man käme fast aufs Dach)
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = P.JumpHeight
		normalHipHeight = humanoid.HipHeight
		hipTarget = normalHipHeight
		slide, move, airMomentum, momentumAt = nil, nil, 0, -math.huge
		airMove, lastMoveOut, rawMove = nil, nil, Vector3.zero
		local root = character:WaitForChild("HumanoidRootPart", 5)
		fallForce = nil
		if root then
			local attachment = Instance.new("Attachment")
			attachment.Name = "FallGravityAttachment"
			attachment.Parent = root
			fallForce = Instance.new("VectorForce")
			fallForce.Name = "FallGravity"
			fallForce.Attachment0 = attachment
			fallForce.RelativeTo = Enum.ActuatorRelativeTo.World
			fallForce.ApplyAtCenterOfMass = true
			fallForce.Force = Vector3.zero
			fallForce.Parent = root
		end
		walkSpeed = nil
		grounded, leftGroundAt, jumpedAt, jumpRequestAt, lastGroundY = true, nil, nil, nil, nil
		fallSpeed, slowUntil, dip, dipVelocity = 0, 0, 0, 0
		aiming = false
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping then
				jumpedAt = os.clock()
			end
		end)
		character:GetAttributeChangedSignal("SpeedMultiplier"):Connect(apply)
		character:GetAttributeChangedSignal("Agent"):Connect(apply)
		character:GetAttributeChangedSignal("SlowedUntil"):Connect(function()
			apply()
			task.delay(0.6, apply) -- danach wieder normales Tempo
		end)
		-- Neuer Charakter (z.B. nach Todeskamera): Kamera wieder auf Ego/Schulter
		if not workspace.CurrentCamera:GetAttribute("KillCam") then
			Movement.ApplyCamera()
		end
		apply()
	end
	player:GetAttributeChangedSignal("Buy_Runner"):Connect(apply)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return Movement

-- CharacterPose (ModuleScript, nur Client)
-- Third-Person-Haltung aller Charaktere mit Waffe (Spieler und Bots), wie bei Rogue Company:
--   * lange Waffen im Schulteranschlag, Oberkörper eingedreht, beide Hände an der Waffe
--   * Pistole und Revolver beidhändig vor der Brust
--   * Waffe und Kopf folgen dem Blick nach oben/unten, beim Zielen höher, beim Sprinten gesenkt
--   * Nachladen (Magazin raus/rein mit der linken Hand), Pumpen/Schlitten und Rückstoß
-- Jeder Client rechnet das selbst für alle Charaktere in der Nähe: Motor6D.Transform wird nach den
-- Animationen in RunService.PreSimulation überschrieben. Blick und Zielen der anderen kommen über die
-- Charakter-Attribute AimPitch/Aiming (vom Server), Nachladen über ReloadStart/ReloadTime/ReloadShells.
-- R15 bekommt die volle Haltung, R6 eine einfache (Arme zeigen zur Waffe).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunModels = require(Shared.GunModels)
local WeaponConfig = require(Shared.WeaponConfig)
local WeaponAnimations = require(Shared.WeaponAnimations)
local WeaponEffects = require(Shared.WeaponEffects)
local PoseMath = require(Shared.PoseMath)
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)

local player = Players.LocalPlayer

local CharacterPose = {}

local MAX_DISTANCE = 220          -- weiter weg: keine Haltung berechnen
local EVENT_DISTANCE = 70         -- Nachlade-Geräusche und fallende Magazine nur in der Nähe
local LONG_TWIST = math.rad(50)   -- Oberkörper bei langen Waffen eingedreht (linke Schulter nach vorne)
local SHORT_TWIST = math.rad(12)
local LEAN = 0.4                  -- so viel vom Blickwinkel übernimmt der Oberkörper
local MAX_SLIDE = 0.7             -- so weit darf die linke Hand am Handschutz nach hinten rutschen
local SPRINT_SPEED = 21           -- ab hier gilt ein anderer Charakter als sprintend
local SCALE = GunModels.ToolScale
local RIGHT_POLE = Vector3.new(0.8, -1, 0.35) -- Ellbogen zeigen nach unten/außen (im Blick-Raum)
local LEFT_POLE = Vector3.new(-0.7, -1, 0.1)

local BLOCKING_STATES = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
	[Enum.HumanoidStateType.Physics] = true,
}

local entries = setmetatable({}, { __mode = "k" }) -- [Charakter] = Zustand
local weldRest = setmetatable({}, { __mode = "k" }) -- [Weld] = ursprüngliches C0 (vom Server)
-- Zustand des eigenen Charakters (setzt WeaponClient jedes Bild)
local localState = { Aiming = false, Sprinting = false, Reload = nil, Visible = false }
local lastSent = { Pitch = 0, Aiming = false, Time = 0 }

local function smooth(alpha)
	return alpha * alpha * (3 - 2 * alpha)
end

-- Modell-Einheiten der Waffe -> Größe in der Hand
local function scaled(cframe)
	return CFrame.new(cframe.Position * SCALE) * cframe.Rotation
end

-- ---------- Rig ----------

local function rigOf(model, humanoid, root)
	local function motor(partName, motorName)
		local part = model:FindFirstChild(partName)
		local found = part and part:FindFirstChild(motorName)
		return found and found:IsA("Motor6D") and found or nil
	end
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		local rig = {
			Type = "R15",
			Root = root,
			RootJoint = motor("LowerTorso", "Root"),
			Waist = motor("UpperTorso", "Waist"),
			Neck = motor("Head", "Neck"),
			RShoulder = motor("RightUpperArm", "RightShoulder"),
			RElbow = motor("RightLowerArm", "RightElbow"),
			RWrist = motor("RightHand", "RightWrist"),
			LShoulder = motor("LeftUpperArm", "LeftShoulder"),
			LElbow = motor("LeftLowerArm", "LeftElbow"),
			LWrist = motor("LeftHand", "LeftWrist"),
			GripPart = model:FindFirstChild("RightHand"),
			UpperTorso = model:FindFirstChild("UpperTorso"),
		}
		for _, key in { "RootJoint", "Waist", "Neck", "RShoulder", "RElbow", "RWrist", "LShoulder", "LElbow", "LWrist",
			"GripPart", "UpperTorso" } do
			if not rig[key] then
				return nil
			end
		end
		rig.Joints = { rig.Waist, rig.Neck, rig.RShoulder, rig.RElbow, rig.RWrist, rig.LShoulder, rig.LElbow, rig.LWrist }
		return rig
	end
	local torso = model:FindFirstChild("Torso")
	local rig = {
		Type = "R6",
		Root = root,
		RootJoint = motor("HumanoidRootPart", "RootJoint"),
		Neck = motor("Torso", "Neck"),
		RShoulder = motor("Torso", "Right Shoulder"),
		LShoulder = motor("Torso", "Left Shoulder"),
		GripPart = model:FindFirstChild("Right Arm"),
	}
	if not torso or not rig.RootJoint or not rig.Neck or not rig.RShoulder or not rig.LShoulder or not rig.GripPart then
		return nil
	end
	rig.Joints = { rig.Neck, rig.RShoulder, rig.LShoulder }
	return rig
end

local function armJoints(shoulder, elbow, wrist)
	return {
		ShoulderC0 = shoulder.C0, ShoulderC1 = shoulder.C1,
		ElbowC0 = elbow.C0, ElbowC1 = elbow.C1,
		WristC0 = wrist.C0, WristC1 = wrist.C1,
	}
end

-- ---------- Waffe in der Hand (Tool) ----------

local function restoreTool(entry)
	for _, w in entry.Welds or {} do
		if w.Weld.Parent then
			w.Weld.C0 = w.Rest
		end
		if w.Part.Parent then
			w.Part.Transparency = w.Transparency
		end
	end
end

local function bindTool(entry, tool)
	entry.Tool = tool
	entry.Weapon = tool:GetAttribute("Weapon")
	entry.Handle = tool:FindFirstChild("Handle")
	entry.Welds = {}
	entry.ReloadKey = nil
	entry.Reload = nil
	entry.Fire = nil
	for _, part in tool:GetChildren() do
		local weld = part:IsA("BasePart") and part:FindFirstChild("GunWeld")
		if weld and weld:IsA("Weld") then
			weldRest[weld] = weldRest[weld] or weld.C0
			local hidden = part:GetAttribute("Hidden") == true
			table.insert(entry.Welds, {
				Weld = weld,
				Rest = weldRest[weld],
				Part = part,
				Group = part:GetAttribute("Group"),
				Hidden = hidden,
				Transparency = hidden and 1 or part.Transparency,
			})
		end
	end
end

-- Teile nach der Animation bewegen bzw. zeigen/verstecken (nur lokal)
local function applyParts(entry, pose)
	for _, w in entry.Welds do
		local offset = pose and w.Group and pose.Groups[w.Group]
		local c0 = offset and GunModels.GroupTransform(entry.Weapon, w.Group, offset, SCALE) * w.Rest or w.Rest
		if w.Weld.C0 ~= c0 then
			w.Weld.C0 = c0
		end
		local visible = pose and w.Group and pose.Visible[w.Group]
		local transparency = w.Transparency
		if w.Hidden then
			transparency = visible == true and 0 or 1
		elseif visible == false then
			transparency = 1
		end
		if w.Part.Transparency ~= transparency then
			w.Part.Transparency = transparency
		end
	end
end

-- Haltung abschalten: Gelenke wieder den Animationen überlassen, Waffenteile in Ruhe
local function deactivate(entry)
	if not entry.Active then
		return
	end
	entry.Active = false
	if entry.Rig then
		for _, joint in entry.Rig.Joints do
			if joint.Parent then
				joint.Transform = CFrame.new()
			end
		end
	end
	restoreTool(entry)
end

-- ---------- Nachladen der anderen (aus Attributen) ----------

local function handleEvent(entry, event, position)
	local kind = event[2]
	if kind == "Sound" then
		WeaponEffects.ActionSound(event[3], position)
	elseif kind == "Drop" then
		WeaponEffects.DropCopy(GunModels.GroupParts(entry.Tool, event[3]), Vector3.new(0, -3, 0), true, 3)
	elseif kind == "Spill" then
		local parts = GunModels.GroupParts(entry.Tool, event[3])
		if parts[1] then
			WeaponEffects.Spill(parts[1].Position, event[4] or 6, SCALE)
		end
	end
end

local function remoteReload(model, entry, inRange)
	local start = model:GetAttribute("ReloadStart")
	local duration = model:GetAttribute("ReloadTime")
	if typeof(start) ~= "number" or typeof(duration) ~= "number" or duration <= 0 then
		entry.Reload = nil
		entry.ReloadKey = nil
		return nil
	end
	local now = workspace:GetServerTimeNow()
	local key = tostring(start) .. tostring(entry.Weapon)
	if entry.ReloadKey ~= key then
		entry.ReloadKey = key
		local anim, total = WeaponAnimations.Reload(entry.Weapon, duration, model:GetAttribute("ReloadShells"))
		entry.Reload = anim and { Anim = anim, Start = start, Duration = total } or nil
		-- Erst mitten im Nachladen gesehen: vergangene Ereignisse nicht nachholen
		entry.LastT = entry.Reload and math.max(-1, (now - start) / total - 0.001) or -1
	end
	local reload = entry.Reload
	if not reload then
		return nil
	end
	local t = (now - reload.Start) / reload.Duration
	if t < 0 or t >= 1 then
		return nil
	end
	if inRange then
		for _, event in WeaponAnimations.Events(reload.Anim, entry.LastT, t) do
			handleEvent(entry, event, entry.Handle and entry.Handle.Position)
		end
	end
	entry.LastT = t
	return WeaponAnimations.Sample(reload.Anim, entry.Weapon, t), t
end

-- ---------- Haltung ----------

-- Linke Hand in der Third-Person: Animationen sind für die Ego-Ansicht gebaut, am Anfang und Ende auf die
-- (näher am Griff liegende) Third-Person-Ruheposition überblenden
local function leftHandLocal(info, pose, t)
	if not pose or not pose.Hand then
		return info.LeftHandTP
	end
	local hand = pose.Hand.Position
	if t then
		local w = math.clamp(1 - t / 0.12, 0, 1) + math.clamp((t - 0.88) / 0.12, 0, 1)
		hand += (info.LeftHandTP - info.LeftHand) * w
	end
	return hand
end

-- Avatar-Arme sind kurz: Liegt die Handmitte außer Reichweite der Schulter, rutscht die Hand an der Waffe
-- entlang Richtung Schaft, bis sie hinkommt (höchstens MAX_SLIDE). So bleibt sie immer an der Waffe.
local function slideIntoReach(palm, gun, shoulder, joints)
	local reach = (joints.ElbowC0.Position - joints.ShoulderC1.Position).Magnitude
		+ (joints.WristC0.Position - joints.ElbowC1.Position).Magnitude + joints.WristC1.Position.Magnitude - 0.03
	local d = palm - shoulder
	if d.Magnitude <= reach then
		return palm
	end
	local back = gun.ZVector
	local b = back:Dot(d)
	local disc = b * b - (d:Dot(d) - reach * reach)
	local slide = disc >= 0 and (-b - math.sqrt(disc)) or -b
	return palm + back * math.clamp(slide, 0, MAX_SLIDE)
end

local function poseR15(entry, rig, info, pitch, pose, poseT)
	local root = rig.Root
	local yaw = root.CFrame.Rotation
	local sprint = smooth(entry.Sprint)
	local twist = (info.Long and LONG_TWIST or SHORT_TWIST) * (1 - sprint)
	local lean = pitch * LEAN * (1 - sprint * 0.6)

	-- Unterkörper wie animiert, Oberkörper eingedreht und mit dem Blick geneigt, Kopf schaut in Blickrichtung
	local lowerTorso = PoseMath.Chain(root.CFrame, rig.RootJoint.C0, rig.RootJoint.Transform, rig.RootJoint.C1)
	local torsoRot = yaw * CFrame.Angles(lean, 0, 0) * CFrame.Angles(0, -twist, 0)
	local waistT = PoseMath.MotorTransform(lowerTorso.Rotation, rig.Waist.C0, rig.Waist.C1, torsoRot)
	local upperTorso = PoseMath.Chain(lowerTorso, rig.Waist.C0, waistT, rig.Waist.C1)
	local neckT = PoseMath.MotorTransform(upperTorso.Rotation, rig.Neck.C0, rig.Neck.C1, yaw * CFrame.Angles(pitch * 0.8, 0, 0))

	-- Waffe: lange im Schulteranschlag (Schaftende an der rechten Schulter), kurze vor der Brust
	local aimRot = yaw * CFrame.Angles(pitch, 0, 0)
	local size = rig.UpperTorso.Size
	local gun
	if info.Long and info.Stock then
		local hip = Vector3.new(size.X * 0.2, size.Y * 0.18, -size.Z * 0.5)
		local ads = Vector3.new(size.X * 0.1, size.Y * 0.36, -size.Z * 0.5) -- höher, an die Wange
		local pocket = upperTorso * hip:Lerp(ads, smooth(entry.Aim))
		gun = CFrame.new(pocket) * aimRot * CFrame.new(-info.Stock * SCALE)
	else
		local chest = upperTorso * Vector3.new(0, size.Y * 0.22, 0)
		gun = CFrame.new(chest) * aimRot * CFrame.new(size.X * 0.06, -0.05 + entry.Aim * size.Y * 0.1, -size.X * 0.72)
	end
	if sprint > 0.001 then
		local low = CFrame.new(upperTorso.Position) * yaw * CFrame.new(size.X * 0.15, -size.Y * 0.3, -size.Z * 0.9)
			* CFrame.Angles(math.rad(-35), math.rad(35), math.rad(15))
		gun = gun:Lerp(low, sprint)
	end
	gun = gun * CFrame.new(0, 0, entry.Kick * 0.1) * CFrame.Angles(math.rad(entry.Kick * 5), 0, 0)
	if pose then
		gun = gun * scaled(pose.Gun)
	end

	-- Hände: rechts so, dass die Waffe (am RightGrip) genau in "gun" liegt, links an die Waffe
	local grip = rig.GripPart:FindFirstChild("RightGrip")
	if not grip or not grip:IsA("JointInstance") then
		return false
	end
	local handCF = gun * grip.C1 * grip.C0:Inverse()
	local leftJoints = armJoints(rig.LShoulder, rig.LElbow, rig.LWrist)
	local palm = slideIntoReach(gun * (leftHandLocal(info, pose, poseT) * SCALE), gun,
		(upperTorso * rig.LShoulder.C0).Position, leftJoints)
	local tRS, tRE, tRW = PoseMath.SolveArm(upperTorso, armJoints(rig.RShoulder, rig.RElbow, rig.RWrist), handCF, nil,
		aimRot:VectorToWorldSpace(RIGHT_POLE))
	local tLS, tLE, tLW = PoseMath.SolveArm(upperTorso, leftJoints, nil, palm, aimRot:VectorToWorldSpace(LEFT_POLE))

	rig.Waist.Transform = waistT
	rig.Neck.Transform = neckT
	rig.RShoulder.Transform = tRS
	rig.RElbow.Transform = tRE
	rig.RWrist.Transform = tRW
	rig.LShoulder.Transform = tLS
	rig.LElbow.Transform = tLE
	rig.LWrist.Transform = tLW
	return true
end

-- R6: rechter Arm zeigt in Blickrichtung (Waffe hängt an der Hand), linker Arm zur Waffe
local function poseR6(entry, rig, info, pitch, pose, poseT)
	local root = rig.Root
	local yaw = root.CFrame.Rotation
	local torso = PoseMath.Chain(root.CFrame, rig.RootJoint.C0, rig.RootJoint.Transform, rig.RootJoint.C1)
	local aimRot = yaw * CFrame.Angles(pitch - math.rad(entry.Kick * 4), 0, 0)
	local neckT = PoseMath.MotorTransform(torso.Rotation, rig.Neck.C0, rig.Neck.C1, yaw * CFrame.Angles(pitch * 0.8, 0, 0))
	local armRot = PoseMath.AlignBone(Vector3.new(0, -1, 0), Vector3.xAxis, aimRot.LookVector, aimRot.RightVector)
	local tRS = PoseMath.MotorTransform(torso.Rotation, rig.RShoulder.C0, rig.RShoulder.C1, armRot)
	local tLS = CFrame.new()
	local grip = rig.GripPart:FindFirstChild("RightGrip")
	if grip and grip:IsA("JointInstance") then
		local rightArm = PoseMath.Chain(torso, rig.RShoulder.C0, tRS, rig.RShoulder.C1)
		local handle = rightArm * grip.C0 * grip.C1:Inverse()
		local target = handle * (leftHandLocal(info, pose, poseT) * SCALE)
		local shoulder = (torso * rig.LShoulder.C0).Position
		if (target - shoulder).Magnitude > 0.05 then
			local leftRot = PoseMath.AlignBone(Vector3.new(0, -1, 0), Vector3.xAxis, target - shoulder, aimRot.RightVector)
			tLS = PoseMath.MotorTransform(torso.Rotation, rig.LShoulder.C0, rig.LShoulder.C1, leftRot)
		end
	end
	rig.Neck.Transform = neckT
	rig.RShoulder.Transform = tRS
	rig.LShoulder.Transform = tLS
	return true
end

local function updateCharacter(model, entry, dt, isLocal, cameraPosition)
	local tool = model:FindFirstChildOfClass("Tool")
	local weapon = tool and tool:GetAttribute("Weapon")
	local info = weapon and GunModels.Info[weapon]
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local usable = info ~= nil and humanoid ~= nil and root ~= nil and humanoid.Health > 0 and not humanoid.PlatformStand
		and not humanoid.Sit and not model:GetAttribute("Downed") and not BLOCKING_STATES[humanoid:GetState()]
		and root.CFrame.UpVector.Y > 0.7 -- liegt/gleitet nicht
	if isLocal and not localState.Visible then
		usable = false -- Ego-Perspektive: eigener Körper ist unsichtbar
	end
	if not usable then
		deactivate(entry)
		return
	end
	if (root.Position - cameraPosition).Magnitude > MAX_DISTANCE then
		return
	end
	if entry.Tool ~= tool then
		restoreTool(entry)
		bindTool(entry, tool)
	end
	if not entry.Rig or entry.Rig.Root ~= root or not entry.Rig.GripPart.Parent then
		entry.Rig = rigOf(model, humanoid, root)
		if not entry.Rig then
			return
		end
	end

	-- Eingaben: eigener Charakter direkt, andere aus den Attributen
	local pitchTarget, aiming, sprinting
	if isLocal then
		pitchTarget = math.deg(math.asin(math.clamp(workspace.CurrentCamera.CFrame.LookVector.Y, -1, 1)))
		aiming, sprinting = localState.Aiming, localState.Sprinting
	else
		pitchTarget = model:GetAttribute("AimPitch") or 0
		aiming = model:GetAttribute("Aiming") == true
		local velocity = root.AssemblyLinearVelocity
		sprinting = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > SPRINT_SPEED
	end
	entry.Pitch += (pitchTarget - entry.Pitch) * math.min(1, dt * (isLocal and 40 or 12))

	-- Nachladen / Schuss-Animation
	local pose, poseT = nil, nil
	if isLocal then
		local reload = localState.Reload
		if reload and reload.Weapon == weapon then
			poseT = math.clamp((os.clock() - reload.Start) / reload.Duration, 0, 1)
			pose = WeaponAnimations.Sample(reload.Anim, weapon, poseT)
		end
	else
		pose, poseT = remoteReload(model, entry, (root.Position - cameraPosition).Magnitude < EVENT_DISTANCE)
	end
	local reloading = pose ~= nil
	if not pose and entry.Fire then
		local fire = entry.Fire
		local t = (os.clock() - fire.Start) / fire.Anim.Duration
		if t < 1 then
			pose = WeaponAnimations.Sample(fire.Anim, weapon, t)
		else
			entry.Fire = nil
		end
	end

	entry.Aim += (((aiming and not reloading and not sprinting) and 1 or 0) - entry.Aim) * math.min(1, dt * 12)
	entry.Sprint += (((sprinting and not aiming and not reloading) and 1 or 0) - entry.Sprint) * math.min(1, dt * 8)
	-- Rückstoß: Feder zurück in Ruhe (Teilschritte, damit sie auch bei wenig FPS stabil bleibt)
	local h = dt / 3
	for _ = 1, 3 do
		entry.KickVel += (-entry.Kick * 300 - entry.KickVel * 24) * h
		entry.Kick += entry.KickVel * h
	end

	local pitch = math.rad(math.clamp(entry.Pitch, -70, 70))
	local ok
	if entry.Rig.Type == "R15" then
		ok = poseR15(entry, entry.Rig, info, pitch, pose, poseT)
	else
		ok = poseR6(entry, entry.Rig, info, pitch, pose, poseT)
	end
	if ok then
		applyParts(entry, pose)
		entry.Active = true
	end
end

local function update(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	dt = math.min(dt, 0.1)
	local cameraPosition = camera.CFrame.Position
	local myCharacter = player.Character
	for _, other in Players:GetPlayers() do
		local model = other.Character
		if model then
			local entry = entries[model]
			if not entry then
				entry = { Pitch = 0, Aim = 0, Sprint = 0, Kick = 0, KickVel = 0, Active = false, LastT = -1 }
				entries[model] = entry
			end
			updateCharacter(model, entry, dt, model == myCharacter, cameraPosition)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, model in bots:GetChildren() do
			if model:IsA("Model") then
				local entry = entries[model]
				if not entry then
					entry = { Pitch = 0, Aim = 0, Sprint = 0, Kick = 0, KickVel = 0, Active = false, LastT = -1 }
					entries[model] = entry
				end
				updateCharacter(model, entry, dt, false, cameraPosition)
			end
		end
	end
end

-- Eigenen Blickwinkel und Zielen an den Server melden (für die Haltung bei den anderen)
local function sendAimState()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not Modes.IsFighting(player) then
		return
	end
	local now = os.clock()
	if now - lastSent.Time < 0.08 then
		return
	end
	local pitch = math.deg(math.asin(math.clamp(workspace.CurrentCamera.CFrame.LookVector.Y, -1, 1)))
	if math.abs(pitch - lastSent.Pitch) >= 2 or localState.Aiming ~= lastSent.Aiming then
		lastSent.Pitch, lastSent.Aiming, lastSent.Time = pitch, localState.Aiming, now
		Remotes.AimState:FireServer(math.round(pitch), localState.Aiming)
	end
end

-- Vom WeaponClient jedes Bild: zielt, sprintet, Nachladen ({ Weapon, Anim, Start (os.clock), Duration } oder nil),
-- visible = eigener Charakter ist zu sehen (Schulterkamera)
function CharacterPose.SetLocal(aiming, sprinting, reload, visible)
	localState.Aiming = aiming
	localState.Sprinting = sprinting
	localState.Reload = reload
	localState.Visible = visible
end

-- Ein Charakter hat geschossen: Rückstoß und Schuss-Animation (Pumpen, Schlitten)
function CharacterPose.Fired(model, weaponName)
	local entry = model and entries[model]
	if not entry then
		return
	end
	local cfg = WeaponConfig.Get(weaponName)
	entry.KickVel += 20 * (cfg and cfg.Kick or 1)
	local anim = WeaponAnimations.Fire(weaponName)
	if anim and (anim.Groups or anim.Gun) then
		entry.Fire = { Anim = anim, Start = os.clock() }
	end
end

function CharacterPose.Init()
	RunService.PreSimulation:Connect(update)
	RunService.Heartbeat:Connect(sendAimState)
end

return CharacterPose

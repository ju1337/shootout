--!expose CharacterPose poseR15 poseR6 rigOf rigValid gripFrames keepArmsAtSides
-- Test der Third-Person-Haltung mit einem nachgebauten R15-Rig (Gelenkwerte wie beim Standard-R15)
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local CharacterPose = require("CharacterPose")
local GunModels = require("GunModels")
local PoseMath = require("PoseMath")
local WeaponAnimations = require("WeaponAnimations")
local WeaponConfig = require("WeaponConfig")
local SCALE = GunModels.ToolScale

local function motor(c0, c1)
	return { C0 = c0, C1 = c1, Transform = CFrame.new(), Parent = true }
end
local grip = { C0 = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0), C1 = CFrame.new(),
	IsA = function(_, cls) return cls == "JointInstance" end }

-- Körperbau wie im Spiel (AgentConfig.BodyScale: schmalere Schultern, flacherer Oberkörper)
local AgentConfig = require("AgentConfig")
BODY_W = BODY_W or AgentConfig.BodyScale.Width
BODY_D = BODY_D or AgentConfig.BodyScale.Depth
local function makeRig(rootCF)
	local gripPart = { FindFirstChild = function(_, name) return name == "RightGrip" and grip or nil end, Parent = true }
	grip.Part0 = gripPart -- RightGrip: Part0 = Hand, Part1 = Handle
	return {
		Type = "R15",
		Root = { CFrame = rootCF },
		RootJoint = motor(CFrame.new(0, -1, 0), CFrame.new(0, -0.4, 0)),
		Waist = motor(CFrame.new(0, 0.4, 0), CFrame.new(0, -0.8, 0)),
		Neck = motor(CFrame.new(0, 0.8, 0), CFrame.new(0, -0.5, 0)),
		RShoulder = motor(CFrame.new(1 * BODY_W, 0.563, 0), CFrame.new(-0.5 * BODY_W, 0.394, 0)),
		RElbow = motor(CFrame.new(0, -0.334, 0), CFrame.new(0, 0.259, 0)),
		RWrist = motor(CFrame.new(0, -0.501, 0), CFrame.new(0, 0.125, 0)),
		LShoulder = motor(CFrame.new(-1 * BODY_W, 0.563, 0), CFrame.new(0.5 * BODY_W, 0.394, 0)),
		LElbow = motor(CFrame.new(0, -0.334, 0), CFrame.new(0, 0.259, 0)),
		LWrist = motor(CFrame.new(0, -0.501, 0), CFrame.new(0, 0.125, 0)),
		GripPart = gripPart,
		UpperTorso = { Size = Vector3.new(2 * BODY_W, 1.6, 1 * BODY_D) },
		Head = { Size = Vector3.new(1.2, 1.2, 1.2) },
	}
end

-- Vorwärtskinematik: Welt-CFrames von Oberkörper, Händen und Griff aus den gesetzten Transforms
local function fk(rig)
	local lower = PoseMath.Chain(rig.Root.CFrame, rig.RootJoint.C0, rig.RootJoint.Transform, rig.RootJoint.C1)
	local upper = PoseMath.Chain(lower, rig.Waist.C0, rig.Waist.Transform, rig.Waist.C1)
	local head = PoseMath.Chain(upper, rig.Neck.C0, rig.Neck.Transform, rig.Neck.C1)
	local function arm(s, e, w)
		local a = PoseMath.Chain(upper, s.C0, s.Transform, s.C1)
		local b = PoseMath.Chain(a, e.C0, e.Transform, e.C1)
		return PoseMath.Chain(b, w.C0, w.Transform, w.C1), a, b
	end
	local rightHand = arm(rig.RShoulder, rig.RElbow, rig.RWrist)
	local leftHand, leftUpper = arm(rig.LShoulder, rig.LElbow, rig.LWrist)
	local handle = rightHand * grip.C0 * grip.C1:Inverse()
	return { Upper = upper, Head = head, RightHand = rightHand, LeftHand = leftHand, Handle = handle, LeftUpper = leftUpper }
end

local worstLeft, worstDir = {}, 0
for weaponName, info in GunModels.Info do
	local maxLeft, maxDirErr, maxHeadErr = 0, 0, 0
	for _, yawDeg in { 0, 73, -140 } do
		for pitchDeg = -60, 60, 15 do
			for _, aim in { 0, 1 } do
				local rootCF = CFrame.new(20, 3, -7) * CFrame.Angles(0, math.rad(yawDeg), 0)
				local rig = makeRig(rootCF)
				local entry = { Sprint = 0, Aim = aim, Kick = 0 }
				local pitch = math.rad(pitchDeg)
				local ok = CharacterPose.__poseR15(entry, rig, info, pitch, nil, nil)
				check(ok, weaponName .. ": Pose nicht gesetzt")
				local r = fk(rig)
				-- Waffe zeigt genau in Blickrichtung
				local aimDir = (rootCF.Rotation * CFrame.Angles(pitch, 0, 0)).LookVector
				local dirErr = math.deg(math.acos(math.clamp(r.Handle.LookVector:Dot(aimDir), -1, 1)))
				maxDirErr = math.max(maxDirErr, dirErr)
				-- Linke Hand an der Waffe (Handmitte am Ziel)
				local target = r.Handle * (info.LeftHandTP * SCALE)
				-- Hand darf am Handschutz Richtung Schaft rutschen (höchstens MAX_SLIDE): Abstand zu diesem Stück
				local back = r.Handle.ZVector
				local slide = math.clamp((r.LeftHand.Position - target):Dot(back), 0, 1.0 * SCALE) -- MAX_SLIDE
				local leftErr = (r.LeftHand.Position - (target + back * slide)).Magnitude
				maxLeft = math.max(maxLeft, leftErr)
				-- Kopf schaut ungefähr in Blickrichtung
				local headErr = math.deg(math.acos(math.clamp(r.Head.LookVector:Dot(aimDir), -1, 1)))
				maxHeadErr = math.max(maxHeadErr, headErr)
				-- Waffe vor dem Körper (Mündung vor dem Oberkörper)
				local muzzle = r.Handle * (info.Muzzle * SCALE)
				local forward = rootCF.LookVector
				local ahead = (muzzle - r.Upper.Position):Dot(forward)
				-- angelegt und steil nach oben lehnt sich der Oberkörper zurück: dann reicht etwas weniger Abstand
				check(ahead > (aim == 1 and pitchDeg > 45 and 0.3 or 0.5), string.format("%s: Mündung nicht vor dem Körper (%.2f bei Pitch %d, Zielen %d)", weaponName,
					ahead, pitchDeg, aim))
			end
		end
	end
	print(string.format("%-9s Waffe->Blick max %.3f°, linke Hand max %.3f Studs, Kopf max %.1f°", weaponName, maxDirErr, maxLeft, maxHeadErr))
	-- Atmen im Stand neigt die Waffe gewollt um bis zu 0,6° (CharacterPose, prozedurale Bewegung)
	check(maxDirErr < 0.8, weaponName .. ": Waffe zeigt nicht in Blickrichtung")
	check(maxLeft < 0.12, weaponName .. ": linke Hand erreicht die Waffe nicht")
	check(maxHeadErr < 20, weaponName .. ": Kopf schaut woanders hin")
end

-- Sprint: Waffe gesenkt (Mündung zeigt nach unten), keine NaN
do
	local rig = makeRig(CFrame.new(0, 3, 0))
	local entry = { Sprint = 1, Aim = 0, Kick = 0 }
	CharacterPose.__poseR15(entry, rig, GunModels.Info.Rifle, 0, nil, nil)
	local r = fk(rig)
	check(r.Handle.LookVector.Y < -0.2, "Sprint: Waffe nicht gesenkt")
	check(r.Handle.Position.X == r.Handle.Position.X, "Sprint: NaN")
end

-- Nachladen: Linke Hand folgt dem Magazin (mitten im Nachladen)
for weaponName, info in GunModels.Info do
	local anim, duration = WeaponAnimations.Reload(weaponName, WeaponConfig.Get(weaponName).ReloadTime, 4)
	local maxErr, worst = 0, 0
	for i = 0, 100 do
		local t = i / 100
		local pose = WeaponAnimations.Sample(anim, weaponName, t)
		local rig = makeRig(CFrame.new(0, 3, 0))
		local entry = { Sprint = 0, Aim = 0, Kick = 0 }
		CharacterPose.__poseR15(entry, rig, info, math.rad(-10), pose, t)
		local r = fk(rig)
		local w = math.clamp(1 - t / 0.12, 0, 1) + math.clamp((t - 0.88) / 0.12, 0, 1)
		local local_ = pose.Hand.Position + (info.LeftHandTP - info.LeftHand) * w
		local target = r.Handle * (local_ * SCALE)
		local back = r.Handle.ZVector
		local slide = math.clamp((r.LeftHand.Position - target):Dot(back), 0, 1.0 * SCALE) -- MAX_SLIDE
		local err = (r.LeftHand.Position - (target + back * slide)).Magnitude
		if err > maxErr then maxErr, worst = err, t end
	end
	print(string.format("%-9s Nachladen: linke Hand max %.3f Studs vom Ziel (bei t=%.2f)", weaponName, maxErr, worst))
	check(maxErr < 0.25, weaponName .. ": linke Hand beim Nachladen weit weg vom Ziel")
end

-- Zielen (angelegt): Visier liegt auf der Blicklinie direkt vor dem rechten Auge; die Waffe kommt dafür nicht
-- tiefer als aus der Hüfte (die hält sie schon auf Schulterhöhe)
for weaponName, info in GunModels.Info do
	local maxOff, minAlong, maxAlong, minRaise = 0, math.huge, 0, math.huge
	for _, yawDeg in { 0, 73, -140 } do
		for pitchDeg = -60, 60, 15 do
			local rootCF = CFrame.new(-4, 3, 9) * CFrame.Angles(0, math.rad(yawDeg), 0)
			local pitch = math.rad(pitchDeg)
			local rig = makeRig(rootCF)
			CharacterPose.__poseR15({ Sprint = 0, Aim = 1, Kick = 0 }, rig, info, pitch, nil, nil)
			local r = fk(rig)
			local eye = r.Head * Vector3.new(1.2 * 0.17, 1.2 * 0.08, -1.2 * 0.42)
			local sight = r.Handle * (Vector3.new(0, info.SightHeight, info.SightZ) * SCALE)
			local look = r.Handle.LookVector
			local along = (sight - eye):Dot(look)
			local off = ((sight - eye) - look * along).Magnitude
			maxOff = math.max(maxOff, off)
			minAlong, maxAlong = math.min(minAlong, along), math.max(maxAlong, along)
			-- gegenüber der Hüfthaltung angehoben (im Oberkörper-Raum gemessen)
			local hipRig = makeRig(rootCF)
			CharacterPose.__poseR15({ Sprint = 0, Aim = 0, Kick = 0 }, hipRig, info, pitch, nil, nil)
			local hip = fk(hipRig)
			local up = rootCF.UpVector
			if math.abs(pitchDeg) <= 30 then -- bei steilen Winkeln ist "höher" nicht aussagekräftig
				minRaise = math.min(minRaise, (sight - hip.Handle * (Vector3.new(0, info.SightHeight, info.SightZ) * SCALE)):Dot(up))
			end
		end
	end
	print(string.format("%-9s Zielen: Visier %.3f Studs neben der Augenlinie, %.2f-%.2f Studs vor dem Auge, mind. %.2f höher",
		weaponName, maxOff, minAlong, maxAlong, minRaise))
	check(maxOff < 0.03, weaponName .. ": Visier nicht vor dem Auge")
	check(minAlong > 0.15 and maxAlong < 1.6, weaponName .. ": Visier zu nah/weit vom Auge")
	check(minRaise > -0.2, weaponName .. ": Zielen senkt die Waffe")
end

-- Ganzer Charakter aus einem Modell, ohne Waffe: die Arme werden nicht seitlich abgespreizt (sonst klafft zwischen den
-- starren Teilen von Rumpf und Arm eine Lücke), Vor-/Zurückschwingen und Eindrehen bleiben
local idle = makeRig(CFrame.new())
idle.LShoulder.Transform = CFrame.new(0, 0.01, 0) * CFrame.Angles(0.4, 0.05, -0.2)
idle.RShoulder.Transform = CFrame.Angles(-0.3, 0, 0.25)
local elbowBefore = CFrame.Angles(0.2, 0, 0.1)
idle.LElbow.Transform = elbowBefore
CharacterPose.__keepArmsAtSides(idle)
local lx, ly, lz = idle.LShoulder.Transform:ToEulerAnglesXYZ()
local rx, _, rz = idle.RShoulder.Transform:ToEulerAnglesXYZ()
check(math.abs(lz) < 1e-6 and math.abs(rz) < 1e-6, "Arme nicht seitlich abgespreizt")
check(math.abs(lx - 0.4) < 1e-6 and math.abs(ly - 0.05) < 1e-6 and math.abs(rx + 0.3) < 1e-6
	and (idle.LShoulder.Transform.Position - Vector3.new(0, 0.01, 0)).Magnitude < 1e-6, "Schwingen und Eindrehen bleiben")
check(idle.LElbow.Transform == elbowBefore, "Ellbogen unverändert")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

--!expose CharacterPose poseR15 poseR6 rigOf rigValid gripFrames
-- Gelenk-Erkennung der Third-Person-Haltung: klassische Motor6D-Rigs und Rigs mit dem Avatar Joint Upgrade
-- (AnimationConstraint statt Motor6D, C0/C1 nur als lesbare Aliase der Attachments)
local CharacterPose = require("CharacterPose")
local GunModels = require("GunModels")
local PoseMath = require("PoseMath")
local SCALE = GunModels.ToolScale

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

-- ---------- Mini-Instanzen ----------
local BASES = {
	AnimationConstraint = { "Constraint" },
	BallSocketConstraint = { "Constraint" },
	RigidConstraint = { "Constraint" },
	Motor6D = { "Motor", "JointInstance" },
	Weld = { "JointInstance" },
	Part = { "BasePart" },
}
local function new(className, name, parent, props)
	local o = { ClassName = className, Name = name, Children = {} }
	for k, v in props or {} do
		o[k] = v
	end
	function o:IsA(cls)
		return cls == "Instance" or cls == self.ClassName or table.find(BASES[self.ClassName] or {}, cls) ~= nil
	end
	function o:FindFirstChild(n)
		for _, c in self.Children do
			if c.Name == n then
				return c
			end
		end
		return nil
	end
	function o:GetChildren()
		return table.clone(self.Children)
	end
	function o:GetDescendants()
		local out = {}
		local function rec(x)
			for _, c in x.Children do
				table.insert(out, c)
				rec(c)
			end
		end
		rec(self)
		return out
	end
	if parent then
		table.insert(parent.Children, o)
	end
	o.Parent = parent
	return o
end

local W, D = 0.75, 0.8
local R15_PARTS = {
	HumanoidRootPart = Vector3.new(2 * W, 2, 1 * D), LowerTorso = Vector3.new(2 * W, 0.4, 1 * D),
	UpperTorso = Vector3.new(2 * W, 1.6, 1 * D), Head = Vector3.new(1.2, 1.2, 1.2),
	RightUpperArm = Vector3.new(1 * W, 1.2, 1 * D), RightLowerArm = Vector3.new(1 * W, 1.2, 1 * D),
	RightHand = Vector3.new(1 * W, 0.3, 1 * D), LeftUpperArm = Vector3.new(1 * W, 1.2, 1 * D),
	LeftLowerArm = Vector3.new(1 * W, 1.2, 1 * D), LeftHand = Vector3.new(1 * W, 0.3, 1 * D),
}
-- Name, bewegtes Teil (liegt darin), Elternteil, C0, C1 (Werte wie beim Standard-R15)
local R15_JOINTS = {
	{ "Root", "LowerTorso", "HumanoidRootPart", CFrame.new(0, -1, 0), CFrame.new(0, -0.4, 0) },
	{ "Waist", "UpperTorso", "LowerTorso", CFrame.new(0, 0.4, 0), CFrame.new(0, -0.8, 0) },
	{ "Neck", "Head", "UpperTorso", CFrame.new(0, 0.8, 0), CFrame.new(0, -0.5, 0) },
	{ "RightShoulder", "RightUpperArm", "UpperTorso", CFrame.new(1 * W, 0.563, 0), CFrame.new(-0.5 * W, 0.394, 0) },
	{ "RightElbow", "RightLowerArm", "RightUpperArm", CFrame.new(0, -0.334, 0), CFrame.new(0, 0.259, 0) },
	{ "RightWrist", "RightHand", "RightLowerArm", CFrame.new(0, -0.501, 0), CFrame.new(0, 0.125, 0) },
	{ "LeftShoulder", "LeftUpperArm", "UpperTorso", CFrame.new(-1 * W, 0.563, 0), CFrame.new(0.5 * W, 0.394, 0) },
	{ "LeftElbow", "LeftLowerArm", "LeftUpperArm", CFrame.new(0, -0.334, 0), CFrame.new(0, 0.259, 0) },
	{ "LeftWrist", "LeftHand", "LeftLowerArm", CFrame.new(0, -0.501, 0), CFrame.new(0, 0.125, 0) },
}

local function motor6D(name, holder, part0, c0, c1)
	return new("Motor6D", name, holder, { Part0 = part0, Part1 = holder, C0 = c0, C1 = c1, Transform = CFrame.new() })
end
local function animationConstraint(name, holder, part0, part1, c0, c1)
	local a0 = new("Attachment", name .. "RigAttachment", part0, { CFrame = c0 })
	local a1 = new("Attachment", name .. "RigAttachment", part1, { CFrame = c1 })
	-- C0/C1/Part0/Part1: lesbare Aliase (Attachment0/1)
	return new("AnimationConstraint", name, holder, { Attachment0 = a0, Attachment1 = a1, C0 = c0, C1 = c1,
		Part0 = part0, Part1 = part1, Transform = CFrame.new(), IsKinematic = true })
end

-- mode: "legacy" (Motor6D), "aju" (AnimationConstraint), "both" (altes Motor6D + AnimationConstraint gleichen
-- Namens), "elsewhere" (AnimationConstraints anders benannt in einem Ordner)
local function buildR15(mode, rootCF)
	local model = new("Model", "Spieler")
	local parts = {}
	for name, size in R15_PARTS do
		parts[name] = new("Part", name, model, { Size = size })
	end
	parts.HumanoidRootPart.CFrame = rootCF
	local folder = mode == "elsewhere" and new("Folder", "Joints", model) or nil
	local joints = {}
	for _, j in R15_JOINTS do
		local name, holderName, parentName, c0, c1 = j[1], j[2], j[3], j[4], j[5]
		local holder, part0 = parts[holderName], parts[parentName]
		if mode == "legacy" then
			joints[name] = motor6D(name, holder, part0, c0, c1)
		elseif mode == "both" then
			motor6D(name, holder, part0, c0, c1)
			joints[name] = animationConstraint(name, holder, part0, holder, c0, c1)
		elseif mode == "elsewhere" then
			joints[name] = animationConstraint("AC_" .. name, folder, part0, holder, c0, c1)
		else
			joints[name] = animationConstraint(name, holder, part0, holder, c0, c1)
		end
	end
	new("BallSocketConstraint", "RightShoulderBallSocket", parts.RightUpperArm) -- gibt es beim Upgrade zusätzlich
	local handle = new("Part", "Handle", model, { Size = Vector3.new(0.3, 0.3, 1) })
	new("Weld", "RightGrip", parts.RightHand, { Part0 = parts.RightHand, Part1 = handle,
		C0 = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0), C1 = CFrame.new() })
	local humanoid = { RigType = Enum.HumanoidRigType.R15 }
	return model, humanoid, parts, joints
end

-- Vorwärtskinematik mit den gesetzten Transforms (wie die Engine: Part1 = Part0 * C0 * Transform * C1^-1)
local function fk(rig, gripC0, gripC1)
	local lower = PoseMath.Chain(rig.Root.CFrame, rig.RootJoint.C0, rig.RootJoint.Transform, rig.RootJoint.C1)
	local upper = PoseMath.Chain(lower, rig.Waist.C0, rig.Waist.Transform, rig.Waist.C1)
	local function arm(s, e, w)
		local a = PoseMath.Chain(upper, s.C0, s.Transform, s.C1)
		local b = PoseMath.Chain(a, e.C0, e.Transform, e.C1)
		return PoseMath.Chain(b, w.C0, w.Transform, w.C1)
	end
	local rightHand = arm(rig.RShoulder, rig.RElbow, rig.RWrist)
	local leftHand = arm(rig.LShoulder, rig.LElbow, rig.LWrist)
	return rightHand * gripC0 * gripC1:Inverse(), leftHand
end

for _, mode in { "legacy", "aju", "both", "elsewhere" } do
	local rootCF = CFrame.new(5, 3, -2) * CFrame.Angles(0, math.rad(30), 0)
	local model, humanoid, parts, joints = buildR15(mode, rootCF)
	local rig = CharacterPose.__rigOf(model, humanoid, parts.HumanoidRootPart)
	check(rig ~= nil, mode .. ": Rig nicht erkannt")
	if rig then
		local expect = { RootJoint = "Root", Waist = "Waist", Neck = "Neck", RShoulder = "RightShoulder",
			RElbow = "RightElbow", RWrist = "RightWrist", LShoulder = "LeftShoulder", LElbow = "LeftElbow",
			LWrist = "LeftWrist" }
		for key, name in expect do
			check(rig[key] == joints[name], string.format("%s: %s ist nicht das richtige Gelenk", mode, key))
		end
		check(rig.Type == "R15", mode .. ": kein R15")
		check(CharacterPose.__rigValid(rig, parts.HumanoidRootPart), mode .. ": Rig gilt als ungültig")

		-- Haltung setzen (angelegt, leicht nach oben) und nachrechnen: Waffe zeigt in Blickrichtung,
		-- linke Hand an der Waffe
		local tool = { Grip = CFrame.new() }
		local info = GunModels.Info.Rifle
		local pitch = math.rad(12)
		for _, aim in { 0, 1 } do
			local entry = { Sprint = 0, Aim = aim, Kick = 0, Tool = tool }
			local ok = CharacterPose.__poseR15(entry, rig, info, pitch, nil, nil)
			check(ok, mode .. ": Haltung nicht gesetzt")
			local t = rig.RShoulder.Transform
			check(t.LookVector:Dot(Vector3.new(0, 0, -1)) < 0.999 or t.Position.Magnitude > 0.001,
				mode .. ": Schulter-Transform nicht geschrieben")
			local c0, c1 = CharacterPose.__gripFrames(rig, tool)
			local handle, leftHand = fk(rig, c0, c1)
			local aimDir = (rootCF.Rotation * CFrame.Angles(pitch, 0, 0)).LookVector
			local dirErr = math.deg(math.acos(math.clamp(handle.LookVector:Dot(aimDir), -1, 1)))
			local target = handle * (info.LeftHandTP * SCALE)
			local back = handle.ZVector
			local slide = math.clamp((leftHand.Position - target):Dot(back), 0, 1.0 * SCALE)
			local leftErr = (leftHand.Position - (target + back * slide)).Magnitude
			print(string.format("%-9s Zielen %d: Waffe->Blick %.3f°, linke Hand %.3f Studs", mode, aim, dirErr, leftErr))
			check(dirErr < 0.8, mode .. ": Waffe zeigt nicht in Blickrichtung")
			check(leftErr < 0.12, mode .. ": linke Hand nicht an der Waffe")
		end

		-- Gelenk ersetzt (Parent nil): Rig wird neu gesucht
		rig.RElbow.Parent = nil
		check(not CharacterPose.__rigValid(rig, parts.HumanoidRootPart), mode .. ": ersetztes Gelenk nicht bemerkt")
	end
end

-- Altes Motor6D daneben: die AnimationConstraint gewinnt (die bewegt den Körper)
do
	local model, humanoid, parts = buildR15("both", CFrame.new())
	local rig = CharacterPose.__rigOf(model, humanoid, parts.HumanoidRootPart)
	check(rig and rig.RShoulder:IsA("AnimationConstraint"), "both: Motor6D statt AnimationConstraint genommen")
end

-- Fehlt ein Gelenk ganz: kein Rig (keine halbe Haltung)
do
	local model, humanoid, parts = buildR15("aju", CFrame.new())
	local elbow = parts.LeftLowerArm:FindFirstChild("LeftElbow")
	table.remove(parts.LeftLowerArm.Children, table.find(parts.LeftLowerArm.Children, elbow))
	check(CharacterPose.__rigOf(model, humanoid, parts.HumanoidRootPart) == nil, "fehlendes Gelenk: trotzdem Rig")
end

-- ---------- R6 (klassisch, Gelenke im Torso) ----------
local function buildR6(renameShoulder)
	local model = new("Model", "R6")
	local root = new("Part", "HumanoidRootPart", model, { Size = Vector3.new(2, 2, 1), CFrame = CFrame.new(0, 3, 0) })
	local torso = new("Part", "Torso", model, { Size = Vector3.new(2, 2, 1) })
	local head = new("Part", "Head", model, { Size = Vector3.new(2, 1, 1) })
	local rArm = new("Part", "Right Arm", model, { Size = Vector3.new(1, 2, 1) })
	local lArm = new("Part", "Left Arm", model, { Size = Vector3.new(1, 2, 1) })
	local j = {}
	j.RootJoint = new("Motor6D", "RootJoint", root, { Part0 = root, Part1 = torso,
		C0 = CFrame.new(0, 0, 0, -1, -0, -0, 0, 0, 1, 0, 1, 0), C1 = CFrame.new(0, 0, 0, -1, -0, -0, 0, 0, 1, 0, 1, 0), Transform = CFrame.new() })
	j.Neck = new("Motor6D", "Neck", torso, { Part0 = torso, Part1 = head,
		C0 = CFrame.new(0, 1, 0, -1, -0, -0, 0, 0, 1, 0, 1, 0), C1 = CFrame.new(0, -0.5, 0, -1, -0, -0, 0, 0, 1, 0, 1, 0), Transform = CFrame.new() })
	j.RShoulder = new("Motor6D", renameShoulder and "RS" or "Right Shoulder", torso, { Part0 = torso, Part1 = rArm,
		C0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0), C1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0), Transform = CFrame.new() })
	j.LShoulder = new("Motor6D", "Left Shoulder", torso, { Part0 = torso, Part1 = lArm,
		C0 = CFrame.new(-1, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0), C1 = CFrame.new(0.5, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0), Transform = CFrame.new() })
	return model, { RigType = Enum.HumanoidRigType.R6 }, root, j
end
for _, rename in { false, true } do
	local model, humanoid, root, j = buildR6(rename)
	local rig = CharacterPose.__rigOf(model, humanoid, root)
	check(rig ~= nil, "R6: Rig nicht erkannt")
	if rig then
		check(rig.Type == "R6", "R6: Typ")
		check(rig.RootJoint == j.RootJoint and rig.Neck == j.Neck and rig.RShoulder == j.RShoulder
			and rig.LShoulder == j.LShoulder, "R6: falsche Gelenke" .. (rename and " (umbenannt)" or ""))
	end
end

-- ---------- Griff ----------
do
	local hand = new("Part", "RightHand", nil)
	local handle = new("Part", "Handle", nil)
	local rig = { GripPart = hand }
	local tool = { Grip = CFrame.new(0, 0, 0.4) }
	local c0, c1 = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0), CFrame.new(0.1, 0.2, 0.3)
	-- Weld wie von Roblox (Part0 = Hand)
	local weld = new("Weld", "RightGrip", hand, { Part0 = hand, Part1 = handle, C0 = c0, C1 = c1 })
	local a, b = CharacterPose.__gripFrames(rig, tool)
	check(a == c0 and b == c1, "Griff: Weld")
	-- umgekehrt verbunden
	weld.Part0, weld.Part1, weld.C0, weld.C1 = handle, hand, c1, c0
	a, b = CharacterPose.__gripFrames(rig, tool)
	check(a == c0 and b == c1, "Griff: Weld umgekehrt")
	-- Constraint mit Attachments
	table.clear(hand.Children)
	local att0 = new("Attachment", "RightGripAttachment", hand, { CFrame = c0 })
	local att1 = new("Attachment", "GripAttachment", handle, { CFrame = c1 })
	new("RigidConstraint", "RightGrip", hand, { Attachment0 = att1, Attachment1 = att0 })
	a, b = CharacterPose.__gripFrames(rig, tool)
	check(a == c0 and b == c1, "Griff: Constraint")
	-- kein Griff-Objekt: RightGripAttachment + Tool.Grip
	table.clear(hand.Children)
	table.insert(hand.Children, att0)
	a, b = CharacterPose.__gripFrames(rig, tool)
	check(a == c0 and b == tool.Grip, "Griff: Attachment + Tool.Grip")
	-- gar nichts: keine Haltung
	table.clear(hand.Children)
	a, b = CharacterPose.__gripFrames(rig, tool)
	check(a == nil and b == nil, "Griff: nichts gefunden, trotzdem Werte")
end

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

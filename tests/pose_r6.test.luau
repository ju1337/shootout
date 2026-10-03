--!expose CharacterPose poseR15 poseR6 rigOf rigValid gripFrames
-- R6-Haltung: läuft sie ohne Fehler, und wohin zeigen die Arme?
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
local function motor(c0, c1)
	return { C0 = c0, C1 = c1, Transform = CFrame.new(), Parent = true }
end
-- Standardwerte eines R6-Rigs
local grip = { C0 = CFrame.new(0, -1, 0, 1, 0, -0, 0, 0, 1, 0, -1, -0), C1 = CFrame.new(),
	IsA = function(_, cls) return cls == "JointInstance" end }
local function makeRig(rootCF)
	local gripPart = { FindFirstChild = function(_, name) return name == "RightGrip" and grip or nil end, Parent = true }
	grip.Part0 = gripPart -- RightGrip: Part0 = Hand, Part1 = Handle
	return {
		Type = "R6",
		Root = { CFrame = rootCF },
		RootJoint = motor(CFrame.new(0, 0, 0, -1, -0, -0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, -0, -0, 0, 0, 1, 0, 1, 0)),
		Neck = motor(CFrame.new(0, 1, 0, -1, -0, -0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, -0, -0, 0, 0, 1, 0, 1, 0)),
		RShoulder = motor(CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, -0, -0)),
		LShoulder = motor(CFrame.new(-1, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, -0, -0, -1, 0, 1, 0, 1, 0, 0)),
		GripPart = gripPart,
	}
end
for weaponName, info in GunModels.Info do
	for _, aim in { 0, 1 } do
		local rootCF = CFrame.new(0, 3, 0)
		local rig = makeRig(rootCF)
		local entry = { Sprint = 0, Aim = aim, Kick = 0 }
		local ok, err = pcall(CharacterPose.__poseR6, entry, rig, info, 0, nil, nil)
		check(ok, weaponName .. ": Fehler " .. tostring(err))
		if ok then
			local torso = PoseMath.Chain(rootCF, rig.RootJoint.C0, rig.RootJoint.Transform, rig.RootJoint.C1)
			local rArm = PoseMath.Chain(torso, rig.RShoulder.C0, rig.RShoulder.Transform, rig.RShoulder.C1)
			local lArm = PoseMath.Chain(torso, rig.LShoulder.C0, rig.LShoulder.Transform, rig.LShoulder.C1)
			print(string.format("%-9s aim %d: rechter Arm -Y=(%.2f %.2f %.2f) linker Arm -Y=(%.2f %.2f %.2f)", weaponName, aim,
				-rArm.UpVector.X, -rArm.UpVector.Y, -rArm.UpVector.Z, -lArm.UpVector.X, -lArm.UpVector.Y, -lArm.UpVector.Z))
		end
	end
end
print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

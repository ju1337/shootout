-- AvatarArms (ModuleScript)
-- Die echten Arme des Roblox-Avatars eines Charakters als Kopien für die Waffe vor der Kamera (ViewModel): Oberarm,
-- Unterarm und Hand jeder Seite samt Kleidung, in Ruhelage über die Gelenke (R15, Motor6D oder Avatar Joint Upgrade).

local AvatarArms = {}

-- Blender bzw. Studio hängt an Kopien ".001" an – das zählt nicht zum Namen
local function cleanName(name)
	return (string.gsub(name, "%.%d+$", ""))
end

local function isJoint(obj)
	return obj:IsA("Motor6D") or obj:IsA("AnimationConstraint")
end

-- Teil, das ein Gelenk bewegt, und das, an dem es hängt
local function jointParts(joint)
	if joint:IsA("AnimationConstraint") then
		local a0, a1 = joint.Attachment0, joint.Attachment1
		return a1 and a1.Parent, a0 and a0.Parent
	end
	return joint.Part1, joint.Part0
end

-- Gezeigte Teile: sichtbar, kein HumanoidRootPart
local function shown(part)
	return part.Transparency < 1 and cleanName(part.Name) ~= "HumanoidRootPart"
end

-- Ruhelage der Körperteile eines Charakters über seine Gelenke (Animationen zählen nicht): [Teil] = CFrame
local function restFrames(container)
	local drivers = {}
	for _, joint in container:GetDescendants() do
		if isJoint(joint) then
			local part, parent = jointParts(joint)
			if part and parent then
				local c0, c1
				if joint:IsA("AnimationConstraint") then
					c0, c1 = joint.Attachment0.CFrame, joint.Attachment1.CFrame
				else
					c0, c1 = joint.C0, joint.C1
				end
				drivers[part] = { Parent = parent, Offset = c0 * c1:Inverse() }
			end
		end
	end
	local rest = {}
	local function restOf(part, depth)
		if not rest[part] then
			local driver = drivers[part]
			rest[part] = driver and depth < 20 and restOf(driver.Parent, depth + 1) * driver.Offset or part.CFrame
		end
		return rest[part]
	end
	return function(part)
		return restOf(part, 0)
	end
end

local ARM_SEGMENTS = { Upper = "UpperArm", Lower = "LowerArm", Hand = "Hand" }

-- Gelenkpunkt im Ruhe-Raum: Lage des Gelenks an seinem Elternteil (C0 bzw. Attachment0)
local function jointPoint(container, restOf, jointName, partName)
	for _, joint in container:GetDescendants() do
		if isJoint(joint) and joint.Name == jointName then
			local part, parent = jointParts(joint)
			if part and parent and cleanName(part.Name) == partName then
				local c0 = joint:IsA("AnimationConstraint") and joint.Attachment0.CFrame or joint.C0
				return (restOf(parent) * c0).Position
			end
		end
	end
	return nil
end

local function armCopy(part, name)
	local copy = part:Clone()
	if not copy then
		return nil -- Archivable aus
	end
	for _, child in copy:GetDescendants() do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") or child:IsA("Constraint")
			or child:IsA("BasePart") or child:IsA("LuaSourceContainer") then
			child:Destroy()
		end
	end
	copy.Name = name
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.CastShadow = false
	copy.Massless = true
	copy.LocalTransparencyModifier = 0
	return copy
end

-- Arme des Charakters im Ruhe-Raum (Raum des HumanoidRootPart, Arme hängen, Blick -Z):
-- { Right = Seite, Left = Seite }, Seite = { Shoulder, Elbow, Wrist = Vector3,
-- Pieces = { { Part = Kopie, Rest = CFrame, Segment = "Upper" | "Lower" | "Hand" } } }.
-- nil, wenn sich die Arme nicht finden lassen (z.B. R6 oder noch nicht geladen).
function AvatarArms.ArmPieces(character)
	if not character then
		return nil
	end
	local restOf = restFrames(character)
	local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("UpperTorso")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local toRoot = restOf(root):Inverse()
	local result = {}
	for _, side in { "Right", "Left" } do
		local entry = { Pieces = {} }
		entry.Shoulder = jointPoint(character, restOf, side .. "Shoulder", side .. "UpperArm")
		entry.Elbow = jointPoint(character, restOf, side .. "Elbow", side .. "LowerArm")
		entry.Wrist = jointPoint(character, restOf, side .. "Wrist", side .. "Hand")
		if not entry.Shoulder or not entry.Elbow or not entry.Wrist then
			return nil
		end
		entry.Shoulder, entry.Elbow, entry.Wrist = toRoot * entry.Shoulder, toRoot * entry.Elbow, toRoot * entry.Wrist
		for segment, suffix in ARM_SEGMENTS do
			local bodyName = side .. suffix
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") and cleanName(part.Name) == bodyName and shown(part) then
					local copy = armCopy(part, bodyName .. "_" .. (#entry.Pieces + 1))
					if copy then
						table.insert(entry.Pieces, { Part = copy, Rest = toRoot * restOf(part), Segment = segment })
					end
				end
			end
		end
		if #entry.Pieces == 0 then
			return nil
		end
		result[side] = entry
	end
	return result
end

return AvatarArms

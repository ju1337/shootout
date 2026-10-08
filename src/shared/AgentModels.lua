-- AgentModels (ModuleScript)
-- Aussehen der Agenten: das 3D-Modell aus ReplicatedStorage.Assets.Agents.<Agent-Id> (Anleitung in
-- docs/agenten-modelle.md) – genau so, wie es in Blender bzw. Studio aussieht. Nichts wird umgefärbt, gestreckt,
-- zerlegt oder umgebogen. Der Spielkörper bleibt unsichtbar als Trefferzone, die Teile des Modells zählen nie als
-- Treffer (gleiche Trefferzonen für alle). Ohne Modell: Standard-Look aus AgentBody.
--
-- Zwei Arten von Modellen:
--   * Rig (Humanoid, HumanoidRootPart, Gelenke – wie ein StarterCharacter oder aus dem Avatar-Setup): bleibt komplett
--     (gehäutete Meshes, Bones, Accessoires, Layered Clothing). Es steht mit den Füßen auf dem Boden, sein
--     HumanoidRootPart ist an das des Spielkörpers geschweißt, und seine Gelenke übernehmen jedes Bild die Bewegung
--     der gleichnamigen Gelenke des Spielkörpers – es bewegt sich wie als eigener Charakter.
--   * Starre Teile (ohne Rig): jedes Teil hängt am Körperteil, mit dem sein Name beginnt (Head_Suit, LeftUpperArm_Pad),
--     sonst am nächsten. Boden = Marker Point_Root, sonst der tiefste Punkt unter der Mitte des Rumpfs; vorne = -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AgentConfig = require(script.Parent.AgentConfig)

local AgentModels = {}

-- ---------- Der Spielkörper ----------
-- R15 mit klassischen Proportionen, Breite und Tiefe wie AgentConfig.BodyScale (der Kopf wird nicht verschmälert).
-- Ruhelage: Ursprung = Boden zwischen den Füßen, Blick nach -Z, Arme hängen. Höhen aus den Gelenken des
-- Standard-R15; Teile überlappen an den Gelenken wie beim echten Körper. Auf diesen Körper wird ein Modell gesetzt.
local W, D = AgentConfig.BodyScale.Width, AgentConfig.BodyScale.Depth
local function bodyPart(width, height, depth, x, y)
	return { Size = Vector3.new(width, height, depth), CFrame = CFrame.new(x, y, 0) }
end
AgentModels.Body = {
	Head = bodyPart(1.2, 1.2, 1.2, 0, 4.5),
	UpperTorso = bodyPart(2 * W, 1.6, D, 0, 3.2),
	LowerTorso = bodyPart(2 * W, 0.4, D, 0, 2.2),
	LeftUpperArm = bodyPart(W, 1.169, D, -1.5 * W, 3.369),
	LeftLowerArm = bodyPart(W, 1.052, D, -1.5 * W, 2.776),
	LeftHand = bodyPart(W, 0.3, D, -1.5 * W, 2.15),
	RightUpperArm = bodyPart(W, 1.169, D, 1.5 * W, 3.369),
	RightLowerArm = bodyPart(W, 1.052, D, 1.5 * W, 2.776),
	RightHand = bodyPart(W, 0.3, D, 1.5 * W, 2.15),
	LeftUpperLeg = bodyPart(W, 1.217, D, -0.5 * W, 1.58),
	LeftLowerLeg = bodyPart(W, 1.193, D, -0.5 * W, 0.8),
	LeftFoot = bodyPart(W, 0.3, D, -0.5 * W, 0.15),
	RightUpperLeg = bodyPart(W, 1.217, D, 0.5 * W, 1.58),
	RightLowerLeg = bodyPart(W, 1.193, D, 0.5 * W, 0.8),
	RightFoot = bodyPart(W, 0.3, D, 0.5 * W, 0.15),
}
AgentModels.BodyParts = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
	"RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
-- Rechtes Schultergelenk in Ruhelage (Figuren heben den Arm mit der Waffe)
AgentModels.RightShoulder = Vector3.new(W, 3.763, 0)

-- Standard-Look: Haut, Hose = Uniformfarbe abgedunkelt
AgentModels.SkinColor = Color3.fromRGB(205, 160, 130)
AgentModels.FaceTexture = "rbxasset://textures/face.png" -- Roblox-Standardgesicht
function AgentModels.PantsColor(primary)
	return primary:Lerp(Color3.new(0, 0, 0), 0.5)
end

-- ---------- 3D-Modelle aus Assets.Agents ----------
-- Untermodell im Charakter bzw. in der Figur, in dem das Modell hängt
AgentModels.ModelName = "AgentModel"
local HEIGHT = 5.1 -- Scheitel bis Sohle des Spielkörpers
-- So hoch darf ein Modell sein, damit es 1:1 bleibt (1 Blender-Einheit = 1 Stud); sonst stimmt beim Import die
-- Einheit nicht (z.B. Zentimeter), und es wird auf die Höhe des Spielkörpers gebracht
local MIN_HEIGHT, MAX_HEIGHT = 4, 6.5
local MAX_PARTS = 40 -- mehr Teile kosten auf Handys Leistung (nur ein Hinweis)
local WELD_NAME = "AgentWeld" -- Schweißung Modell → Spielkörper

-- [Agent-Id] = { Rig = Modell, Floor = Boden unter dem HumanoidRootPart, Count } (Rig) bzw.
-- { Pieces = Modell (Teile mit den Attributen AgentBody und AgentRest), Count } (ohne Rig)
local assetData = {}
local assetReport = {} -- [Name] = { Loaded = bool, Errors = { Text }, Warnings = { Text } }

-- Blender hängt an Kopien ".001" an – das zählt nicht zum Namen
local function cleanName(name)
	return (string.gsub(name, "%.%d+$", ""))
end

-- Körperteil, zu dem ein Teil laut Namen gehört (Head, Head_Suit, LeftUpperArm.001 …), sonst nil
local function bodyNameOf(name)
	local first = string.match(cleanName(name), "^[^_%.%s]+")
	return first and AgentModels.Body[first] and first or nil
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

-- Gezeigte Teile: sichtbar, keine Marker Point_… und Maßstab-Teile Ref_…, kein HumanoidRootPart
local function shown(part)
	local name = cleanName(part.Name)
	return part.Transparency < 1 and name ~= "HumanoidRootPart" and not string.match(name, "^Point_")
		and not string.match(name, "^Ref_")
end

-- Halbe Ausdehnung eines (evtl. gedrehten) Quaders entlang der Achsen eines Bezugsraums
local function halfExtent(rotation, size)
	local r, u, l, h = rotation.RightVector, rotation.UpVector, rotation.LookVector, size / 2
	return Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z)
end

-- Ausdehnung von Teilen im Raum frame: min, max
local function bounds(parts, frame)
	local min, max = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in parts do
		local center = frame:PointToObjectSpace(part.Position)
		local extent = halfExtent(frame.Rotation:Inverse() * part.CFrame.Rotation, part.Size)
		min, max = min:Min(center - extent), max:Max(center + extent)
	end
	return min, max
end

-- Faktor, falls das Modell in der falschen Einheit importiert wurde (sonst 1)
local function unitScale(height, report)
	if height >= MIN_HEIGHT and height <= MAX_HEIGHT then
		return 1
	end
	local scale = HEIGHT / height
	table.insert(report.Warnings, string.format("Modell ist %.2f Studs hoch, auf %.1f gebracht (mal %.4g) – stimmt "
		.. "die Einheit beim Import (1 Blender-Einheit = 1 Stud)?", height, HEIGHT, scale))
	return scale
end

-- Körperteil des Spielkörpers, dem ein Punkt (Agentenraum) am nächsten ist
local function nearestBodyPart(position)
	local best, bestDistance = nil, math.huge
	for _, name in AgentModels.BodyParts do
		local rest = AgentModels.Body[name]
		local offset = (position - rest.CFrame.Position):Abs() - rest.Size / 2
		local outside = Vector3.new(math.max(offset.X, 0), math.max(offset.Y, 0), math.max(offset.Z, 0)).Magnitude
		local distance = outside + 0.001 * (position - rest.CFrame.Position).Magnitude -- innen: die nähere Mitte
		if distance < bestDistance then
			best, bestDistance = name, distance
		end
	end
	return best
end

-- Teile für Charakter und Figur: nie Trefferzone, keine Kollision, kein Gewicht
local function prepare(part)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

local R15_JOINTS = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow",
	"RightWrist", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
-- Ohne Rig werden die Teile nur einzeln an die Körperteile gehängt, wenn mindestens diese so benannt sind
local SPLIT_CORE = { "Head", "UpperTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }
local AVATAR_SETUP = "In Studio: Modell im Workspace anklicken › Reiter Avatar › Avatar Setup bis zum Ende, das Ergebnis "
	.. "nach Assets.Agents legen."

-- Teile, die über Gelenke oder Schweißungen (auch indirekt) mit start verbunden sind: [Teil] = true
local function connected(model, start)
	local links = {}
	local function link(a, b)
		if a and b then
			links[a] = links[a] or {}
			links[b] = links[b] or {}
			table.insert(links[a], b)
			table.insert(links[b], a)
		end
	end
	for _, obj in model:GetDescendants() do
		if obj:IsA("JointInstance") or obj:IsA("WeldConstraint") then
			link(obj.Part0, obj.Part1)
		elseif obj:IsA("Constraint") and obj.Attachment0 and obj.Attachment1 then
			link(obj.Attachment0.Parent, obj.Attachment1.Parent)
		end
	end
	local seen, queue = { [start] = true }, { start }
	while #queue > 0 do
		local part = table.remove(queue)
		for _, other in links[part] or {} do
			if not seen[other] then
				seen[other] = true
				table.insert(queue, other)
			end
		end
	end
	return seen
end

-- HumanoidRootPart wie bei jedem Roblox-Charakter: genau eins und unsichtbar. Aus Blender importiert ist es oft eine
-- sichtbare Box, und mit Rig Type R15 legt Studio oft ein zweites an. Das echte trägt das Gelenk "Root".
local function fixRoots(model)
	local roots = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and cleanName(part.Name) == "HumanoidRootPart" then
			table.insert(roots, part)
		end
	end
	local real = roots[1]
	for _, joint in model:GetDescendants() do
		if joint:IsA("Motor6D") and joint.Name == "Root" and table.find(roots, joint.Part0) then
			real = joint.Part0
		end
	end
	for _, part in roots do
		if part ~= real then
			-- nicht löschen (darin können Bones hängen), nur umbenennen und ausblenden
			part.Name = "ExtraRootPart"
			part.Transparency = 1
			part.CanCollide = false
			part.Massless = true
		end
	end
	if real then
		real.Name = "HumanoidRootPart"
		real.Transparency = 1
	end
end

-- ---------- Rig (Humanoid und HumanoidRootPart – z.B. aus dem Avatar-Setup oder als StarterCharacter gebaut) ----------
-- Bleibt komplett, wie es ist: Gelenke, gehäutete Meshes, Bones, Accessoires, Layered Clothing (Wraps), Humanoid.
-- Das HumanoidRootPart wird an das des Spielkörpers geschweißt, die Gelenke übernehmen jedes Bild die Bewegung der
-- gleichnamigen Gelenke des Spielkörpers (SyncJoints) – das Modell bewegt sich also genau wie als eigener Charakter.
local function loadRig(rig, report)
	local template = rig:Clone()
	if not template then
		table.insert(report.Errors, "Modell lässt sich nicht kopieren (Archivable ist aus)")
		return nil
	end
	fixRoots(template)
	local templateRoot = template:FindFirstChild("HumanoidRootPart", true)
	for _, obj in template:GetDescendants() do
		if obj:IsA("LuaSourceContainer") then
			obj:Destroy() -- (z.B. Animate, Health: bewegt wird über den Spielkörper)
		end
	end
	local copy = template:FindFirstChildWhichIsA("Humanoid", true)
	if not copy or not templateRoot or not templateRoot:IsA("BasePart") then
		table.insert(report.Errors, "Humanoid oder HumanoidRootPart lässt sich nicht kopieren (Archivable ist aus)")
		return nil
	end
	-- was an keinem Gelenk hängt, hängt fest am HumanoidRootPart (sonst fiele es herunter)
	local attached = connected(template, templateRoot)
	local visible, joints, matched = {}, 0, 0
	for _, obj in template:GetDescendants() do
		if obj:IsA("BasePart") then
			obj.Anchored = false
			prepare(obj)
			if shown(obj) then
				table.insert(visible, obj)
			end
			if not attached[obj] then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = templateRoot
				weld.Part1 = obj
				weld.Parent = obj
			end
		elseif isJoint(obj) then
			joints += 1
			matched += table.find(R15_JOINTS, obj.Name) and 1 or 0
		end
	end
	if #visible == 0 then
		table.insert(report.Errors, "keine sichtbaren Teile im Modell")
		return nil
	end
	if joints == 0 then
		table.insert(report.Warnings, "Rig ohne Gelenke (Motor6D) – steht steif, bewegt sich nur als Ganzes. "
			.. AVATAR_SETUP)
	elseif matched < 5 then
		table.insert(report.Warnings, "Gelenke heißen nicht wie im R15-Rig (LeftShoulder, RightHip …) – Arme und Beine "
			.. "bewegen sich nicht. " .. AVATAR_SETUP)
	end
	copy.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	copy.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	copy.EvaluateStateMachine = false -- steuert nichts (sonst zöge er am Spielkörper)
	copy.BreakJointsOnDeath = false
	copy.RequiresNeck = false
	copy.AutomaticScalingEnabled = false
	template.PrimaryPart = templateRoot
	templateRoot.PivotOffset = CFrame.new()
	local min, max = bounds(visible, templateRoot.CFrame)
	local scale = unitScale(max.Y - min.Y, report)
	if scale ~= 1 then
		template:ScaleTo(template:GetScale() * scale)
		min = bounds(visible, templateRoot.CFrame)
	end
	template.Name = AgentModels.ModelName
	template:SetAttribute("AgentGear", true)
	local count = 0
	for _, part in template:GetDescendants() do
		count += part:IsA("BasePart") and 1 or 0
	end
	if #visible > MAX_PARTS then
		table.insert(report.Warnings, #visible .. " Teile – für Handys besser höchstens " .. MAX_PARTS)
	end
	-- Als eigener Charakter (AgentModels.BuildCharacter): das Rig unverändert, nur in Spielgröße; sichtbare Teile sind
	-- die Trefferzone
	local character = rig:Clone()
	fixRoots(character)
	local characterRoot = character:FindFirstChild("HumanoidRootPart", true)
	character.PrimaryPart = characterRoot
	if scale ~= 1 then
		character:ScaleTo(character:GetScale() * scale)
	end
	-- Wie ein Roblox-Charakter: nur das HumanoidRootPart stößt an, die Körperteile nicht (aus Studio importierte
	-- MeshParts kollidieren sonst untereinander und mit dem Boden, der Charakter kippt um und bleibt liegen)
	local parts = {}
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = part == characterRoot
			part.CanQuery = shown(part)
			part.Massless = part ~= characterRoot
			if shown(part) then
				table.insert(parts, part)
			end
		end
	end
	-- Hüfthöhe aus dem Modell: Füße genau auf dem Boden (der Import setzt sie oft falsch)
	local humanoid = character:FindFirstChildWhichIsA("Humanoid", true)
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.AutomaticScalingEnabled = false
	local feet = bounds(parts, characterRoot.CFrame)
	humanoid.HipHeight = math.max(-feet.Y - characterRoot.Size.Y / 2, 0)
	return { Rig = template, Floor = min.Y, Count = count, Character = character }
end

-- Charakter aus einem Modell ohne Rig: unsichtbares HumanoidRootPart (2 hoch, HIP über dem Boden) mit Humanoid, das
-- Modell genau wie gebaut fest daran (Füße auf dem Boden, Blick -Z), seine sichtbaren Teile sind die Trefferzone. Dazu
-- zwei unsichtbare Hilfsteile, die das Spiel braucht: "Head" (Kopfschüsse, Namensschild) über dem Kopf des Modells und
-- "RightHand" (hält die Waffe).
local HIP = 2
local function characterFromPieces(pieces)
	local character = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, HIP + 1, 0)
	root.Transparency = 1
	root.Parent = character
	character.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = HIP
	humanoid.Parent = character
	local function fix(part, canQuery)
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = canQuery
		part.CanTouch = canQuery
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	-- Modell als Ordner (kein eigenes Modell im Charakter: Treffer finden den Charakter über das nächste Modell)
	local folder = Instance.new("Folder")
	folder.Name = AgentModels.ModelName
	folder.Parent = character
	local model = pieces:Clone()
	local top, headMin, headMax = 0, nil, nil
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = part:GetAttribute("AgentRest")
			part:SetAttribute("AgentBody", nil)
			part:SetAttribute("AgentRest", nil)
			part:SetAttribute("AgentGear", nil)
			fix(part, shown(part))
			local min, max = bounds({ part }, CFrame.new())
			top = math.max(top, max.Y)
			if bodyNameOf(part.Name) == "Head" then
				headMin, headMax = headMin and headMin:Min(min) or min, headMax and headMax:Max(max) or max
			end
			if part.Parent:IsA("Model") then
				part.Parent = folder
			end
		end
	end
	model:Destroy()
	-- Kopf-Trefferzone: etwas größer als der Kopf des Modells (sonst träfe man zuerst das Modell), sonst ganz oben
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Transparency = 1
	if headMin then
		head.Size = headMax - headMin + Vector3.new(0.1, 0.1, 0.1)
		head.CFrame = CFrame.new((headMin + headMax) / 2)
	else
		head.Size = Vector3.new(1.4, 1.4, 1.4)
		head.CFrame = CFrame.new(0, top - 0.65, 0)
	end
	head.Parent = character
	fix(head, true)
	local hand = Instance.new("Part")
	hand.Name = "RightHand"
	hand.Transparency = 1
	hand.Size = AgentModels.Body.RightHand.Size
	hand.CFrame = AgentModels.Body.RightHand.CFrame
	hand.Parent = character
	fix(hand, false)
	local grip = Instance.new("Attachment")
	grip.Name = "RightGripAttachment"
	grip.CFrame = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	grip.Parent = hand
	return character
end

-- ---------- Ohne Rig (z.B. ein Teil <Körperteil>_<Name> pro Körperteil aus Blender) ----------
-- Das Modell bleibt zusammen (Hierarchie, Bones, Texturen); jedes Teil hängt am Körperteil, zu dem es gehört, und sitzt
-- dort genau wie im Modell (gemessen ab dem Boden). Ein Modell mit Bones (gehäutetes Mesh) hängt als Ganzes am
-- Unterkörper.
local function loadPieces(source, report)
	local template = source:Clone()
	if not template then
		table.insert(report.Errors, "Modell lässt sich nicht kopieren (Archivable ist aus)")
		return nil
	end
	if not template:IsA("Model") then
		local model = Instance.new("Model")
		template.Parent = model
		template = model
	end
	-- Gelenke, Schweißungen, Skripte, Humanoid & Co. steuern hier nichts (die Teile hängen am Spielkörper)
	local marker, rootPart, drop, skinned = nil, nil, {}, false
	for _, obj in template:GetDescendants() do
		local name = cleanName(obj.Name)
		if obj:IsA("JointInstance") or obj:IsA("WeldConstraint") or obj:IsA("Constraint") or obj:IsA("LuaSourceContainer")
			or obj:IsA("ValueBase") or obj:IsA("Humanoid") or obj:IsA("AnimationController") then
			obj:Destroy()
		elseif name == "Point_Root" and (obj:IsA("BasePart") or obj:IsA("Attachment")) then
			marker = obj
		elseif obj:IsA("Bone") or (obj:IsA("MeshPart") and obj.HasSkinnedMesh == true) then
			skinned = true
		elseif obj:IsA("BasePart") then
			if name == "HumanoidRootPart" then
				rootPart = obj
			end
			local hasBones = obj:FindFirstChildWhichIsA("Bone", true) ~= nil
			if not hasBones and (not shown(obj) or string.match(name, "^Point_")) then
				table.insert(drop, obj) -- unsichtbare Hilfsteile, Marker, Maßstab-Teile
			end
		end
	end
	local function markerPosition()
		if marker and marker:IsA("BasePart") then
			return marker.Position
		elseif marker and marker.Parent and marker.Parent:IsA("BasePart") then
			return (marker.Parent.CFrame * marker.CFrame).Position
		end
		return nil
	end
	local function visibleParts()
		local list = {}
		for _, part in template:GetDescendants() do
			if part:IsA("BasePart") and shown(part) and part ~= marker then
				table.insert(list, part)
			end
		end
		return list
	end
	local visible = visibleParts()
	if #visible == 0 then
		table.insert(report.Errors, "keine sichtbaren Teile im Modell")
		return nil
	end
	-- Bezugsrahmen: Achsen des HumanoidRootPart (sonst des Modells), Boden = Point_Root bzw. tiefster Punkt unter der
	-- Mitte des Rumpfs
	local basis = rootPart and rootPart.CFrame.Rotation or CFrame.new()
	local min, max = bounds(visible, basis)
	local scale = unitScale(max.Y - min.Y, report)
	if scale ~= 1 then
		template:ScaleTo(template:GetScale() * scale)
		min, max = bounds(visible, basis)
	end
	local origin = markerPosition()
	if not origin then
		local torso = {}
		for _, part in visible do
			local bodyName = bodyNameOf(part.Name)
			if bodyName == "UpperTorso" or bodyName == "LowerTorso" then
				table.insert(torso, part)
			end
		end
		local torsoMin, torsoMax = bounds(torso, basis)
		local middle = #torso > 0 and (torsoMin + torsoMax) / 2
			or rootPart and basis:PointToObjectSpace(rootPart.Position) or (min + max) / 2
		origin = basis * Vector3.new(middle.X, min.Y, middle.Z)
	end
	local toAgent = (CFrame.new(origin) * basis):Inverse()
	for _, part in drop do
		for _, child in part:GetChildren() do
			if child:IsA("BasePart") then
				child.Parent = part.Parent -- sichtbare Teile darin bleiben
			end
		end
		part:Destroy()
	end
	if marker then
		marker:Destroy()
	end

	-- Teile einzeln an die Körperteile nur, wenn das Modell ausdrücklich so benannt ist (Kopf, Rumpf, Arme und Beine
	-- je mit einem Teil <Körperteil>_…) und keine Bones hat. Sonst bleibt es ein Stück: genau wie gebaut, fest am
	-- Körper (nichts wird zerlegt oder falsch zugeordnet; Arme und Beine bewegen sich dann nicht mit).
	local named = {}
	for _, part in template:GetDescendants() do
		if part:IsA("BasePart") and shown(part) and bodyNameOf(part.Name) then
			named[bodyNameOf(part.Name)] = true
		end
	end
	local split = not skinned
	for _, name in SPLIT_CORE do
		split = split and named[name] == true
	end

	-- jedes Teil: Körperteil ("" = als Ganzes) und Lage im Agentenraum (Boden zwischen den Füßen, Blick -Z)
	local covered, count = {}, 0
	for _, part in template:GetDescendants() do
		if part:IsA("BasePart") then
			local inAgent = toAgent * part.CFrame
			local bodyName = split and (bodyNameOf(part.Name) or nearestBodyPart(inAgent.Position)) or ""
			if shown(part) then
				covered[bodyName] = true
			end
			part:SetAttribute("AgentBody", bodyName)
			part:SetAttribute("AgentRest", inAgent)
			part.Anchored = true
			prepare(part)
			count += 1
		end
	end
	template.Name = AgentModels.ModelName
	template:SetAttribute("AgentGear", true)
	if not split then
		table.insert(report.Warnings, "Modell als Ganzes am Körper (genau wie gebaut) – Arme und Beine bewegen sich nicht "
			.. "mit. Damit sie mitgehen: ein Rig daraus machen (" .. AVATAR_SETUP .. ") oder in Blender je Körperteil ein "
			.. "Teil <Körperteil>_<Name> bauen (Head_…, UpperTorso_…, LeftUpperArm_… usw.).")
	else
		local open = {}
		for _, name in AgentModels.BodyParts do
			if not covered[name] then
				table.insert(open, name)
			end
		end
		if #open > 0 then
			table.insert(report.Warnings, "zu " .. table.concat(open, ", ") .. " gehört kein Teil – dort ist nichts zu sehen")
		end
	end
	if count > MAX_PARTS then
		table.insert(report.Warnings, count .. " Teile – für Handys besser höchstens " .. MAX_PARTS
			.. " (in Blender zusammenfügen)")
	end
	return { Pieces = template, Count = count, Whole = not split, Character = characterFromPieces(template) }
end

-- Ein Modell aus Assets.Agents prüfen und vorbereiten. Gibt (Daten oder nil, Bericht) zurück.
-- Rig = irgendwo ein Humanoid, und daneben (im selben Modell) ein HumanoidRootPart.
local function loadAsset(source)
	local report = { Loaded = false, Errors = {}, Warnings = {} }
	-- Aufbau des Modells (steht in Studio im Output, hilft bei der Fehlersuche)
	local counts = { BasePart = 0, Visible = 0, Humanoid = 0, HumanoidRootPart = 0, Joint = 0, Bone = 0 }
	for _, obj in source:GetDescendants() do
		if obj:IsA("BasePart") then
			counts.BasePart += 1
			counts.Visible += obj.Transparency < 1 and 1 or 0
			counts.HumanoidRootPart += obj.Name == "HumanoidRootPart" and 1 or 0
		elseif obj:IsA("Humanoid") then
			counts.Humanoid += 1
		elseif isJoint(obj) then
			counts.Joint += 1
		elseif obj:IsA("Bone") then
			counts.Bone += 1
		end
	end
	report.Info = string.format("Aufbau: %s, %d Teile (%d sichtbar), Humanoid %d, HumanoidRootPart %d, Gelenke %d, "
		.. "Bones %d", source.ClassName, counts.BasePart, counts.Visible, counts.Humanoid, counts.HumanoidRootPart,
		counts.Joint, counts.Bone)
	local humanoid = source:FindFirstChildWhichIsA("Humanoid", true)
	local rig = humanoid and humanoid.Parent
	local root = rig and rig:FindFirstChild("HumanoidRootPart", true)
	local data
	if rig and rig:IsA("Model") and root and root:IsA("BasePart") then
		data = loadRig(rig, report)
	else
		if humanoid then
			table.insert(report.Warnings, "Humanoid ohne HumanoidRootPart – kein Rig, die Teile hängen starr am Körper. "
				.. AVATAR_SETUP)
		end
		data = loadPieces(source, report)
	end
	report.Loaded = data ~= nil
	return data, report
end

-- Ein Modell aus Assets.Agents laden (Name = Agent-Id) und den Bericht dazu ablegen
local function loadOne(source)
	local name = source.Name
	if not AgentConfig.Get(name) then
		local ids = {}
		for _, agent in AgentConfig.Agents do
			table.insert(ids, agent.Id)
		end
		table.sort(ids)
		assetReport[name] = { Loaded = false, Warnings = {},
			Errors = { "unbekannter Name – Modelle heißen wie der Agent: " .. table.concat(ids, ", ") } }
		return
	end
	local ok, data, report = pcall(loadAsset, source)
	if not ok then
		data, report = nil, { Loaded = false, Warnings = {}, Errors = { "Fehler beim Laden: " .. tostring(data) } }
	end
	local twins = 0
	for _, other in source.Parent and source.Parent:GetChildren() or {} do
		twins += other.Name == name and 1 or 0
	end
	if twins > 1 then
		table.insert(report.Warnings, 1, twins .. " Modelle heißen " .. name .. " – es zählt nur eins, die anderen in "
			.. "Assets.Agents löschen!")
	end
	assetReport[name] = report
	assetData[name] = data
end

-- Im Studio-Output (nur Server): was mit dem Modell eines Namens los ist
local function printReport(name)
	if RunService:IsClient() or not RunService:IsStudio() then
		return
	end
	local report = assetReport[name]
	if not report then
		print("[Agentenmodelle] " .. name .. ": kein Modell mehr – Standard-Look")
	elseif report.Loaded then
		local data = assetData[name]
		print("[Agentenmodelle] " .. name .. ": " .. (data.Rig and "Rig (bewegt sich mit)" or data.Whole
			and "Modell als Ganzes" or "Modell, Teile an den Körperteilen") .. " geladen (" .. data.Count .. " Teile)")
	else
		warn("[Agentenmodelle] " .. name .. ": Modell NICHT geladen, es bleibt der Standard-Look:\n  - "
			.. table.concat(report.Errors, "\n  - "))
	end
	if report and report.Info then
		print("[Agentenmodelle] " .. name .. ": " .. report.Info)
	end
	if report and #report.Warnings > 0 then
		warn("[Agentenmodelle] " .. name .. ": Hinweise:\n  - " .. table.concat(report.Warnings, "\n  - "))
	end
end

local changedCallbacks = {}
-- callback(Name) läuft, wenn sich das Modell eines Agenten ändert (neu eingefügt, ersetzt, umbenannt, entfernt)
function AgentModels.OnChanged(callback)
	table.insert(changedCallbacks, callback)
end

-- Ordner mit den Modellen: Rojo legt ReplicatedStorage.Assets.Agents an, die Modelle selbst liegen im Place.
-- Server und Client laden neu, sobald ein Modell dazukommt, sich ändert, umbenannt oder entfernt wird – auch
-- während das Spiel läuft (z.B. in Studio eingefügt). Der Client wartet nicht auf den Ordner (bis dahin zeigen die
-- Vorschauen den Standard-Look).
local function watchAgents(folder)
	local nameOf = {} -- [Modell] = Name, unter dem es zuletzt geladen wurde
	local pending = {} -- Namen, die am Ende dieses Moments neu geladen werden
	local function reload(name)
		assetData[name], assetReport[name] = nil, nil
		local source = folder:FindFirstChild(name)
		if source then
			loadOne(source)
		end
		printReport(name)
		for _, callback in changedCallbacks do
			task.spawn(callback, name)
		end
	end
	local function schedule(name)
		if not name or pending[name] then
			return
		end
		pending[name] = true
		task.defer(function()
			pending[name] = nil
			reload(name)
		end)
	end
	local function track(source)
		nameOf[source] = source.Name
		source:GetPropertyChangedSignal("Name"):Connect(function()
			if nameOf[source] then
				schedule(nameOf[source])
				nameOf[source] = source.Name
				schedule(source.Name)
			end
		end)
		-- Änderungen im Modell (Teile dazu, weg, ersetzt): neu laden
		source.DescendantAdded:Connect(function()
			schedule(nameOf[source])
		end)
		source.DescendantRemoving:Connect(function()
			schedule(nameOf[source])
		end)
	end
	for _, source in folder:GetChildren() do
		if not assetReport[source.Name] then -- (gleicher Name doppelt: das erste zählt, wie beim Neuladen)
			loadOne(source)
		end
		track(source)
	end
	folder.ChildAdded:Connect(function(source)
		track(source)
		schedule(source.Name)
	end)
	folder.ChildRemoved:Connect(function(source)
		local name = nameOf[source]
		nameOf[source] = nil
		schedule(name)
	end)
end

local function whenChild(parent, name, callback)
	local found = parent:FindFirstChild(name)
	if found then
		callback(found)
		return
	end
	local connection
	connection = parent.ChildAdded:Connect(function(child)
		if child.Name == name then
			connection:Disconnect()
			callback(child)
		end
	end)
end

if RunService:IsClient() then
	whenChild(ReplicatedStorage, "Assets", function(assets)
		whenChild(assets, "Agents", watchAgents)
	end)
else
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Agents")
	if folder then
		watchAgents(folder)
	else
		-- Ordner kommt erst später (z.B. in Studio angelegt): dann ab da beobachten
		whenChild(ReplicatedStorage, "Assets", function(later)
			whenChild(later, "Agents", watchAgents)
		end)
	end
	-- In Studio steht im Output, was mit jedem Modell los ist (auch wenn noch keins da ist)
	if RunService:IsStudio() then
		if not folder then
			warn("[Agentenmodelle] Ordner ReplicatedStorage.Assets.Agents fehlt – alle Agenten haben den Standard-Look")
		elseif next(assetReport) == nil then
			print("[Agentenmodelle] noch keine Modelle in ReplicatedStorage.Assets.Agents – alle Agenten haben den "
				.. "Standard-Look")
		end
		for name in assetReport do
			printReport(name)
		end
	end
end

-- Hat der Agent ein 3D-Modell (statt des Standard-Looks)?
function AgentModels.HasAsset(agentId)
	return agentId ~= nil and assetData[agentId] ~= nil
end

-- Das Modell eines Agenten als eigener Charakter (statt des Roblox-Standardkörpers, für Player.Character und Bots):
-- ein Rig unverändert, sonst das Modell genau wie gebaut an einem unsichtbaren HumanoidRootPart (siehe
-- characterFromPieces). Füße auf dem Boden unter dem Drehpunkt (HumanoidRootPart), Blick nach -Z. Attribut
-- AgentModelCharacter = Agent-Id. nil ohne Modell.
function AgentModels.BuildCharacter(agentId)
	local data = agentId and assetData[agentId]
	if not data or not data.Character then
		return nil
	end
	local character = data.Character:Clone()
	character:SetAttribute("AgentModelCharacter", agentId)
	return character
end

-- Ist der Charakter das Modell selbst (BuildCharacter)?
function AgentModels.IsModelCharacter(character)
	return character ~= nil and character:GetAttribute("AgentModelCharacter") ~= nil
end

-- Wie viele Teile Attach für einen Agenten anlegt (0 ohne Modell)
function AgentModels.PartCount(agentId)
	local data = agentId and assetData[agentId]
	return data and data.Count or 0
end

-- Prüfbericht aller Modelle in Assets.Agents: [Name] = { Loaded, Errors = { Text }, Warnings = { Text } }
function AgentModels.AssetReport()
	return assetReport
end

-- Boden unter dem Körper (Blick nach -Z) und woran das Modell geschweißt wird: an Charakteren aus dem
-- HumanoidRootPart (dort hält der Humanoid es über dem Boden), an Figuren aus dem Unterkörper (Ruhelage wie Body)
local function floorOf(container, parts)
	local root = container:FindFirstChild("HumanoidRootPart")
	local humanoid = container:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid then
		return root.CFrame * CFrame.new(0, -(root.Size.Y / 2 + humanoid.HipHeight), 0), root
	end
	local lower = parts.LowerTorso
	if lower then
		return lower.CFrame * AgentModels.Body.LowerTorso.CFrame:Inverse(), lower
	end
	return nil, nil
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

local function weldTo(body, part)
	local joint = Instance.new("WeldConstraint")
	joint.Name = WELD_NAME
	joint.Part0 = body
	joint.Part1 = part
	joint.Parent = part
end

-- Das 3D-Modell eines Agenten an einen Körper hängen. parts = { [Körperteil] = BasePart }: diese Teile werden
-- unsichtbar (bleiben Trefferzone). weld = true: Charakter (angeschweißt, bewegt sich mit), sonst Figur (verankert,
-- Ruhelage wie gebaut). Das Modell liegt im Untermodell AgentModels.ModelName (Attribut AgentGear, ebenso jedes
-- Teil). Gibt das Untermodell zurück, nil ohne Modell.
function AgentModels.Attach(container, parts, agentId, weld)
	local data = agentId and assetData[agentId]
	local floor, anchor = floorOf(container, parts)
	if not data or not floor then
		return nil
	end
	for _, body in parts do
		body.Transparency = 1
		for _, decal in body:GetChildren() do
			if decal:IsA("Decal") then
				decal.Transparency = 1
			end
		end
	end
	local holder
	if data.Rig then
		holder = data.Rig:Clone()
		holder:PivotTo(floor * CFrame.new(0, -data.Floor, 0))
		for _, part in holder:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = not weld
				part:SetAttribute("AgentGear", true)
			end
		end
		if weld then
			weldTo(anchor, holder.PrimaryPart)
		end
	else
		holder = data.Pieces:Clone()
		-- Charakter: Ruhelage über die Gelenke; Figur: Ruhelage wie Body (ein gehobener Arm trägt sein Teil mit)
		local restOf = container:FindFirstChild("HumanoidRootPart") and restFrames(container)
		local missing = {}
		for _, part in holder:GetDescendants() do
			if part:IsA("BasePart") then
				local bodyName = part:GetAttribute("AgentBody")
				local body = parts[bodyName]
				if bodyName == "" then
					-- als Ganzes: fest am HumanoidRootPart (Figur: am Unterkörper), genau wie gebaut
					part.CFrame = floor * part:GetAttribute("AgentRest")
					part.Anchored = not weld
					part:SetAttribute("AgentGear", true)
					if weld then
						weldTo(anchor, part)
					end
				elseif body then
					local rest = restOf and restOf(body) or floor * AgentModels.Body[bodyName].CFrame
					part.CFrame = body.CFrame * rest:ToObjectSpace(floor * part:GetAttribute("AgentRest"))
					part.Anchored = not weld
					part:SetAttribute("AgentGear", true)
					if weld then
						weldTo(body, part)
					end
				else
					table.insert(missing, part) -- Körperteil fehlt (z.B. ein Körper ohne Hände)
				end
			end
		end
		for _, part in missing do
			part:Destroy()
		end
	end
	local count = 0
	for _, part in holder:GetDescendants() do
		count += part:IsA("BasePart") and 1 or 0
	end
	holder:SetAttribute("AgentParts", count) -- so viele Teile gehören dazu (AgentBody prüft, ob alle noch da sind)
	holder.Parent = container
	return holder
end

-- Nur Client, jedes Bild nach den Animationen: die Gelenke eines Rig-Modells übernehmen die Bewegung der
-- gleichnamigen Gelenke des Spielkörpers (Laufen, Springen, Zielen, Waffe halten).
local jointPairs = setmetatable({}, { __mode = "k" }) -- [Untermodell] = { { From, To } }
function AgentModels.SyncJoints(character)
	local holder = character:FindFirstChild(AgentModels.ModelName)
	if not holder or not holder:FindFirstChildOfClass("Humanoid") then
		return
	end
	local list = jointPairs[holder]
	if list then
		for _, pair in list do
			if not pair.From.Parent or not pair.To.Parent then
				list = nil -- Spielkörper ausgetauscht: neu zuordnen
				break
			end
		end
	end
	if not list then
		local sources = {}
		for _, joint in character:GetDescendants() do
			if isJoint(joint) and not joint:IsDescendantOf(holder) then
				local part = jointParts(joint)
				sources[joint.Name .. "/" .. (part and part.Name or "")] = joint
			end
		end
		list = {}
		for _, joint in holder:GetDescendants() do
			if isJoint(joint) then
				local part = jointParts(joint)
				local from = sources[joint.Name .. "/" .. (part and part.Name or "")]
				if from then
					table.insert(list, { From = from, To = joint })
				end
			end
		end
		jointPairs[holder] = list
	end
	for _, pair in list do
		pair.To.Transform = pair.From.Transform
	end
end

-- ---------- Arme für die Ego-Perspektive (ViewModel) ----------
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
	copy:SetAttribute("AgentGear", nil)
	return copy
end

-- Die echten Arme eines Charakters als Kopien für die Waffe vor der Kamera: die Arme des 3D-Modells (Rig oder Teile
-- an den Körperteilen), sonst die des Spielkörpers. Alles im Ruhe-Raum des Charakters (Arme hängen, Blick -Z):
-- { Right = Seite, Left = Seite }, Seite = { Shoulder, Elbow, Wrist = Vector3,
-- Pieces = { { Part = Kopie, Rest = CFrame, Segment = "Upper" | "Lower" | "Hand" } } }.
-- nil, wenn sich die Arme nicht finden lassen (z.B. Modell als Ganzes am Körper).
-- Gelenke des Spielkörpers in Ruhelage (Raum: Boden zwischen den Füßen): Schulter, Ellbogen, Handgelenk
local function bodyArmJoints(side)
	local sign = side == "Right" and 1 or -1
	local upper, lower, hand = AgentModels.Body[side .. "UpperArm"], AgentModels.Body[side .. "LowerArm"],
		AgentModels.Body[side .. "Hand"]
	local function between(a, b) -- Mitte der Überlappung: Unterkante von a, Oberkante von b
		local y = (a.CFrame.Y - a.Size.Y / 2 + b.CFrame.Y + b.Size.Y / 2) / 2
		return Vector3.new(b.CFrame.X, y, 0)
	end
	local shoulder = AgentModels.RightShoulder
	return Vector3.new(shoulder.X * sign, shoulder.Y, shoulder.Z), between(upper, lower), between(lower, hand)
end

-- Charakter aus einem Modell ohne Rig (characterFromPieces): alles hängt fest am HumanoidRootPart, die Arme werden
-- wie beim Laden über ihre Namen bzw. das nächste Körperteil gefunden
local function piecesCharacterArms(character, holder)
	local data = assetData[character:GetAttribute("AgentModelCharacter")]
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not data or data.Whole or not root or not humanoid then
		return nil
	end
	local ground = root.CFrame * CFrame.new(0, -(root.Size.Y / 2 + humanoid.HipHeight), 0)
	local result = {}
	for _, side in { "Right", "Left" } do
		local entry = { Pieces = {} }
		entry.Shoulder, entry.Elbow, entry.Wrist = bodyArmJoints(side)
		for _, part in holder:GetDescendants() do
			if part:IsA("BasePart") and shown(part) then
				local rest = ground:ToObjectSpace(part.CFrame)
				local bodyName = bodyNameOf(part.Name) or nearestBodyPart(rest.Position)
				for segment, suffix in ARM_SEGMENTS do
					local copy = bodyName == side .. suffix and armCopy(part, bodyName .. "_" .. (#entry.Pieces + 1))
					if copy then
						table.insert(entry.Pieces, { Part = copy, Rest = rest, Segment = segment })
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

function AgentModels.ArmPieces(character)
	if not character then
		return nil
	end
	local holder = character:FindFirstChild(AgentModels.ModelName)
	if holder and AgentModels.IsModelCharacter(character) and not character:FindFirstChild("RightUpperArm") then
		return piecesCharacterArms(character, holder)
	end
	local rig = holder and holder:FindFirstChildOfClass("Humanoid") and holder or nil
	local body = rig or character -- hier liegen die Gelenke
	local restOf = restFrames(body)
	local root = body:FindFirstChild("HumanoidRootPart", rig ~= nil) or body:FindFirstChild("UpperTorso", rig ~= nil)
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local toRoot = restOf(root):Inverse()
	local result = {}
	for _, side in { "Right", "Left" } do
		local entry = { Pieces = {} }
		entry.Shoulder = jointPoint(body, restOf, side .. "Shoulder", side .. "UpperArm")
		entry.Elbow = jointPoint(body, restOf, side .. "Elbow", side .. "LowerArm")
		entry.Wrist = jointPoint(body, restOf, side .. "Wrist", side .. "Hand")
		if not entry.Shoulder or not entry.Elbow or not entry.Wrist then
			return nil
		end
		entry.Shoulder, entry.Elbow, entry.Wrist = toRoot * entry.Shoulder, toRoot * entry.Elbow, toRoot * entry.Wrist
		for segment, suffix in ARM_SEGMENTS do
			local bodyName = side .. suffix
			local function add(part, rest)
				local copy = shown(part) and armCopy(part, bodyName .. "_" .. (#entry.Pieces + 1))
				if copy then
					table.insert(entry.Pieces, { Part = copy, Rest = toRoot * rest, Segment = segment })
				end
			end
			if holder and not rig then
				-- Teile des Modells, die am Körperteil hängen (AgentModels.Attach)
				local bodyPart = character:FindFirstChild(bodyName)
				for _, part in holder:GetDescendants() do
					if bodyPart and part:IsA("BasePart") and part:GetAttribute("AgentBody") == bodyName then
						add(part, restOf(bodyPart) * bodyPart.CFrame:ToObjectSpace(part.CFrame))
					end
				end
			else
				for _, part in body:GetDescendants() do
					if part:IsA("BasePart") and cleanName(part.Name) == bodyName then
						add(part, restOf(part))
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

-- Tod (Server): Die Gelenke des Spielkörpers zerfallen bzw. werden zu Kugelgelenken (Ragdoll). Damit ein Rig-Modell
-- mitfällt statt steif stehen zu bleiben, wird jedes seiner Körperteile an das gleichnamige Teil des Spielkörpers
-- geschweißt (statt an seinem Gelenk zu hängen).
function AgentModels.WeldToBody(character)
	local holder = character:FindFirstChild(AgentModels.ModelName)
	if not holder or not holder:FindFirstChildOfClass("Humanoid") then
		return
	end
	for _, joint in holder:GetDescendants() do
		if isJoint(joint) then
			local part = jointParts(joint)
			local body = part and character:FindFirstChild(part.Name)
			if body and body:IsA("BasePart") then
				joint:Destroy()
				weldTo(body, part)
			end
		end
	end
end

return AgentModels

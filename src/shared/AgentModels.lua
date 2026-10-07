-- AgentModels (ModuleScript)
-- Aussehen der Agenten: das 3D-Modell aus ReplicatedStorage.Assets.Agents.<Agent-Id> (Anleitung in
-- docs/agenten-modelle.md) – genau so, wie es in Blender bzw. Studio aussieht: gleiche Teile, Lage, Größe, Farben,
-- Materialien und Texturen. Nichts wird umgefärbt, gestreckt oder gedreht. Jedes Teil wird an das Körperteil des
-- Spielkörpers geschweißt, zu dem es gehört, und bewegt sich mit ihm (laufen, zielen, Waffe halten). Der Spielkörper
-- bleibt unsichtbar als Trefferzone, die Teile des Modells zählen nie als Treffer (gleiche Trefferzonen für alle).
-- Solange es kein Modell gibt: Standard-Look aus AgentBody (Roblox-Körper mit Gesicht in den Agentenfarben).
--
-- Zu welchem Körperteil ein Teil gehört: heißt es wie ein Körperteil (Head, UpperTorso, … wie im R15-Rig) oder
-- beginnt sein Name damit (Head_Suit, LeftUpperArm_Pad), zu diesem; sonst zu dem, dem es am nächsten ist (Haare,
-- Helm, Rucksack …). Lage: Boden zwischen den Füßen = Marker Point_Root (Teil oder Attachment), sonst der tiefste
-- Punkt unter der Mitte des Rumpfs. Vorne = Blickrichtung des HumanoidRootPart, sonst -Z. Unsichtbare Teile
-- (Transparency 1, z.B. das HumanoidRootPart), Marker Point_… und Maßstab-Teile Ref_… werden nicht angezeigt.

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
-- Untermodell im Charakter bzw. in der Figur, in dem die Teile des Modells hängen. Die Teile behalten ihre Namen
-- (gehäutete Meshes finden ihre Gelenke darüber), ohne mit dem gleichnamigen Spielkörper zu kollidieren.
AgentModels.ModelName = "AgentModel"
local HEIGHT = 5.1 -- Scheitel bis Sohle des Spielkörpers
-- So hoch darf ein Modell sein, damit es 1:1 bleibt (1 Blender-Einheit = 1 Stud); sonst stimmt beim Import die
-- Einheit nicht (z.B. Zentimeter), und es wird auf die Höhe des Spielkörpers gebracht
local MIN_HEIGHT, MAX_HEIGHT = 4, 6.5
local MAX_PARTS = 40 -- mehr Teile kosten auf Handys Leistung (nur ein Hinweis)

local assetData = {}   -- [Agent-Id] = { { Name, Body, Offset, Template } }
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

-- Halbe Ausdehnung eines (evtl. gedrehten) Quaders entlang der Achsen eines Bezugsraums
local function halfExtent(rotation, size)
	local r, u, l, h = rotation.RightVector, rotation.UpVector, rotation.LookVector, size / 2
	return Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z)
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

-- Ein Modell aus Assets.Agents prüfen und vorbereiten. Gibt (Teile oder nil, Bericht) zurück.
local function loadAsset(source)
	local report = { Loaded = false, Errors = {}, Warnings = {} }
	local pieces, root, rootPart = {}, nil, nil
	for _, obj in source:GetDescendants() do
		local name = cleanName(obj.Name)
		if name == "Point_Root" and obj:IsA("BasePart") then
			root = obj.Position
		elseif name == "Point_Root" and obj:IsA("Attachment") and obj.Parent and obj.Parent:IsA("BasePart") then
			root = (obj.Parent.CFrame * obj.CFrame).Position
		elseif obj:IsA("BasePart") then
			if name == "HumanoidRootPart" then
				rootPart = obj
			elseif obj.Transparency < 1 and not string.match(name, "^Point_") and not string.match(name, "^Ref_") then
				table.insert(pieces, obj) -- (Marker und Maßstab-Teile wie Ref_Ground nicht)
			end
		end
	end
	if #pieces == 0 then
		table.insert(report.Errors, "keine sichtbaren Teile im Modell")
		return nil, report
	end

	-- Bezugsrahmen: Achsen des HumanoidRootPart (sonst des Modells), Boden = Point_Root bzw. tiefster Punkt
	local basis = rootPart and rootPart.CFrame.Rotation or CFrame.new()
	local min, max = Vector3.one * math.huge, -Vector3.one * math.huge -- ganzes Modell
	local torsoMin, torsoMax = min, max -- Rumpf (seine Mitte ist die Mitte des Modells)
	for _, part in pieces do
		local center = basis:PointToObjectSpace(part.Position)
		local extent = halfExtent(basis:Inverse() * part.CFrame.Rotation, part.Size)
		min, max = min:Min(center - extent), max:Max(center + extent)
		local bodyName = bodyNameOf(part.Name)
		if bodyName == "UpperTorso" or bodyName == "LowerTorso" then
			torsoMin, torsoMax = torsoMin:Min(center - extent), torsoMax:Max(center + extent)
		end
	end
	local height = max.Y - min.Y
	if height < 0.1 then
		table.insert(report.Errors, "das Modell ist flach (Teile ohne Größe)")
		return nil, report
	end
	local origin = root
	if not origin then
		local middle = torsoMin.X <= torsoMax.X and (torsoMin + torsoMax) / 2
			or rootPart and basis:PointToObjectSpace(rootPart.Position) or (min + max) / 2
		origin = basis * Vector3.new(middle.X, min.Y, middle.Z)
	end
	local scale = 1
	if height < MIN_HEIGHT or height > MAX_HEIGHT then
		scale = HEIGHT / height
		table.insert(report.Warnings, string.format("Modell ist %.2f Studs hoch, auf %.1f gebracht (mal %.4g) – stimmt "
			.. "die Einheit beim Import (1 Blender-Einheit = 1 Stud)?", height, HEIGHT, scale))
	end
	local toAgent = (CFrame.new(origin) * basis):Inverse()

	local entries, used, covered = {}, {}, {}
	for _, original in pieces do
		local part = original:Clone()
		if not part then
			table.insert(report.Warnings, original.Name .. " lässt sich nicht kopieren (Archivable ist aus)")
			continue
		end
		-- nur das Aussehen bleibt (Mesh, Textur, SurfaceAppearance, Decals, Bones): keine Teile (kommen einzeln dran),
		-- Gelenke, Rig-Attachments, Wraps, Skripte und Werte der Roblox-Skalierung (OriginalSize & Co.)
		for _, child in part:GetDescendants() do
			if child:IsA("BasePart") or child:IsA("JointInstance") or child:IsA("WeldConstraint") or child:IsA("Constraint")
				or child:IsA("BaseWrap") or child:IsA("LuaSourceContainer") or child:IsA("ValueBase")
				or (child:IsA("Attachment") and not child:IsA("Bone") and string.match(child.Name, "RigAttachment$")) then
				child:Destroy()
			elseif scale ~= 1 and child:IsA("Attachment") then -- (auch Bones)
				child.CFrame = CFrame.new(child.CFrame.Position * scale) * child.CFrame.Rotation
			elseif scale ~= 1 and child:IsA("DataModelMesh") then
				child.Scale *= scale
				child.Offset *= scale
			end
		end
		local inAgent = toAgent * original.CFrame
		inAgent = CFrame.new(inAgent.Position * scale) * inAgent.Rotation
		local bodyName = bodyNameOf(original.Name) or nearestBodyPart(inAgent.Position)
		covered[bodyName] = true
		local unique, count = original.Name, 1
		while used[unique] do
			count += 1
			unique = original.Name .. "_" .. count
		end
		used[unique] = true
		part.Name = unique
		part.Size = original.Size * scale
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		table.insert(entries, { Name = unique, Body = bodyName,
			Offset = AgentModels.Body[bodyName].CFrame:ToObjectSpace(inAgent), Template = part })
	end
	if #entries == 0 then
		table.insert(report.Errors, "kein Teil ließ sich kopieren")
		return nil, report
	end
	local open = {}
	for _, name in AgentModels.BodyParts do
		if not covered[name] then
			table.insert(open, name)
		end
	end
	if #open > 0 then
		table.insert(report.Warnings, "zu " .. table.concat(open, ", ") .. " gehört kein Teil – dort ist nichts zu sehen")
	end
	if #entries > MAX_PARTS then
		table.insert(report.Warnings, #entries .. " Teile – für Handys besser höchstens " .. MAX_PARTS
			.. " (in Blender zusammenfügen)")
	end
	report.Loaded = true
	return entries, report
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
	local ok, entries, report = pcall(loadAsset, source)
	if not ok then
		entries, report = nil, { Loaded = false, Warnings = {}, Errors = { "Fehler beim Laden: " .. tostring(entries) } }
	end
	assetReport[name] = report
	assetData[name] = entries
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
		print("[Agentenmodelle] " .. name .. ": Modell geladen (" .. #assetData[name] .. " Teile)")
	else
		warn("[Agentenmodelle] " .. name .. ": Modell NICHT geladen, es bleibt der Standard-Look:\n  - "
			.. table.concat(report.Errors, "\n  - "))
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
		loadOne(source)
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

-- Teile, die Attach aus dem Modell eines Agenten anlegt: [Name des Teils] = Körperteil, an dem es hängt; nil ohne Modell
function AgentModels.PiecesOf(agentId)
	local entries = agentId and assetData[agentId]
	if not entries then
		return nil
	end
	local pieces = {}
	for _, entry in entries do
		pieces[entry.Name] = entry.Body
	end
	return pieces
end

-- Prüfbericht aller Modelle in Assets.Agents: [Name] = { Loaded, Errors = { Text }, Warnings = { Text } }
function AgentModels.AssetReport()
	return assetReport
end

-- Das 3D-Modell eines Agenten an einen Körper hängen. parts = { [Körperteil] = BasePart }: diese Teile werden
-- unsichtbar (bleiben Trefferzone), jedes Modellteil sitzt an seinem Körperteil wie im Modell. weld = true: an die
-- Körperteile geschweißt (Charaktere), sonst verankert (Figuren). Die Teile liegen im Untermodell
-- AgentModels.ModelName; es und jedes Teil haben das Attribut AgentGear. Gibt die neuen Teile zurück, nil ohne Modell.
function AgentModels.Attach(container, parts, agentId, weld)
	local entries = agentId and assetData[agentId]
	if not entries then
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
	local holder = Instance.new("Model")
	holder.Name = AgentModels.ModelName
	holder:SetAttribute("AgentGear", true)
	local created = {}
	for _, entry in entries do
		local body = parts[entry.Body]
		if not body then
			continue
		end
		local part = entry.Template:Clone()
		part.CFrame = body.CFrame * entry.Offset
		part.Anchored = not weld
		part:SetAttribute("AgentGear", true)
		if weld then
			local joint = Instance.new("WeldConstraint")
			joint.Part0 = body
			joint.Part1 = part
			joint.Parent = part
		end
		part.Parent = holder
		table.insert(created, part)
	end
	holder.Parent = container
	return created
end

return AgentModels

-- AgentModels (ModuleScript)
-- Ausrüstung der Agenten: fertige 3D-Modelle aus ReplicatedStorage.Assets.Agents (Blender, Anleitung in
-- docs/agenten-modelle.md) oder – solange es keins gibt – die Quader-Ausrüstung aus AgentBody (Kapuze, Visier,
-- Maske, Weste, Schulterpolster, Gürtel).
-- Alle Agenten haben denselben Körper (gleiche Trefferzonen); ein Modell liefert nur die Ausrüstung: starre Teile,
-- jedes an genau einem Körperteil. Das Spiel hängt sie an Spieler und Bots (AgentBody.Dress: angeschweißt, nie
-- Trefferzone) und an die Figuren in Menüs, Shop und Markt (AgentFigure).
--
-- Aufbau eines Modells (ausführlich in docs/agenten-modelle.md):
--   Ausrüstungsteile heißen <Körperteil>_<Name>, z.B. Head_Helmet_Primary oder UpperTorso_Vest_Accent (Wörter mit
--   "_", Blender-Endungen wie ".001" sind egal). Wörter mit Bedeutung: Primary = Uniformfarbe, Accent = zweite
--   Farbe, Glass = getöntes Visier, Neon = leuchtet. Teile mit dem Wort Ref sind nur Maßstab und werden ignoriert.
--   Marker Point_Root: Boden zwischen den Füßen (kleines Teil oder Attachment, nur die Mitte zählt).
--   Körper als Bezug (empfohlen): Teile, die genau wie ein Körperteil heißen (Head, UpperTorso, ...), z.B. der Körper
--   aus der Vorlage art/templates/Agents/Agent.obj. Dann richtet das Spiel das Modell an ihnen aus (Lage, Drehung
--   und Verschiebung nach dem Import sind egal) und misst jedes Ausrüstungsteil an seinem Körperteil. Ohne Körper
--   zählen Point_Root und die Achsen des Modells (vorne = -Z, oben = +Y). Ein HumanoidRootPart (Körper aus Studio
--   exportiert) wird ignoriert.
--   Textur-Skins: Ordner "Skins" im Modell, darin je Skin ein Ordner mit der Skin-Id (z.B. "A_Viper_Nacht") mit
--   SurfaceAppearances, benannt wie die Teile, die sie bekommen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AgentConfig = require(script.Parent.AgentConfig)

local AgentModels = {}

-- ---------- Der Agenten-Körper ----------
-- R15 mit klassischen Proportionen, Breite und Tiefe wie AgentConfig.BodyScale (der Kopf wird nicht verschmälert).
-- Ruhelage: Ursprung = Boden zwischen den Füßen (Point_Root), Blick nach -Z, Arme hängen. Höhen aus den Gelenken
-- des Standard-R15 (Schulter 0,563 über der Mitte des Oberkörpers, Hüfte an der Unterkante des Unterkörpers);
-- Teile überlappen an den Gelenken wie beim echten Körper. Aus diesen Werten entstehen die Vorlage und die Figuren.
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
-- Schultergelenke in Ruhelage (für Figuren, die den Arm heben)
AgentModels.RightShoulder = Vector3.new(W, 3.763, 0)
AgentModels.LeftShoulder = Vector3.new(-W, 3.763, 0)

-- Visier: fast schwarz mit einem Hauch Agentenfarbe und glänzend (Glas-Material wirkt im Licht des Hubs hellgrau)
AgentModels.VisorReflectance = 0.3
function AgentModels.VisorColor(accent)
	return Color3.fromRGB(22, 24, 28):Lerp(accent, 0.15)
end

-- ---------- Fertige 3D-Modelle (Blender) ----------
local ZONES = { Primary = true, Accent = true, Glass = true }
local MAX_PARTS = 12        -- Budget pro Agent (Handys)
local MAX_DISTANCE = 0.75   -- so weit darf die Mitte eines Teils außerhalb seines Körperteils liegen
local MAX_REACH = 0.45      -- weiter steht Ausrüstung nicht ab (sähe aus wie ein Ziel, zählt aber nicht als Treffer)
local MAX_BODY_DEVIATION = 0.4 -- mitgelieferter Körper: so weit darf ein Körperteil vom Spielkörper abweichen
local DEFAULT_COLOR = Color3.fromRGB(52, 54, 58) -- untexturierte Teile ohne Farbzone (ein Import ist sonst weiß)
-- Paare links/rechts, aus denen die Querachse des mitgelieferten Körpers kommt (erstes vorhandenes)
local SIDE_PAIRS = { { "LeftUpperArm", "RightUpperArm" }, { "LeftLowerArm", "RightLowerArm" }, { "LeftHand", "RightHand" },
	{ "LeftUpperLeg", "RightUpperLeg" }, { "LeftLowerLeg", "RightLowerLeg" }, { "LeftFoot", "RightFoot" } }

local assetData = {}   -- [Agent-Id] = { Gear = { Eintrag }, Skins = Ordner oder nil }
local assetReport = {} -- [Name] = { Loaded = bool, Errors = { Text }, Warnings = { Text } }

-- Blender hängt an Kopien ".001" an – das zählt nicht zum Namen
local function cleanName(name)
	return (string.gsub(name, "%.%d+$", ""))
end

local function wordsOf(name)
	local list = {}
	for word in string.gmatch(name, "[^_%.%s]+") do
		table.insert(list, word)
	end
	return list
end

local function markerPosition(obj)
	if obj:IsA("BasePart") then
		return obj.Position
	end
	local parent = obj.Parent
	if obj:IsA("Attachment") and parent and parent:IsA("BasePart") then
		return (parent.CFrame * obj.CFrame).Position
	end
	return nil
end

-- Halbe Ausdehnung eines (evtl. gedrehten) Quaders entlang der Achsen eines Bezugsraums
local function halfExtent(rotation, size)
	local r, u, l, h = rotation.RightVector, rotation.UpVector, rotation.LookVector, size / 2
	return Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z)
end

local function sizeText(size)
	return string.format("%.2f × %.2f × %.2f", size.X, size.Y, size.Z)
end

-- Bezugsrahmen: aus dem mitgelieferten Körper (oben = Unterkörper → Kopf, rechts = linke → rechte Seite), sonst
-- Point_Root mit den Achsen des Modells. Gibt (CFrame, aus dem Körper?, Text bei falscher Größe) zurück.
local function frameOf(root, refs)
	local topName = refs.Head and "Head" or (refs.UpperTorso and "UpperTorso")
	local bottomName = refs.LowerTorso and "LowerTorso" or (refs.UpperTorso and topName ~= "UpperTorso" and "UpperTorso")
	local side
	for _, pair in SIDE_PAIRS do
		if refs[pair[1]] and refs[pair[2]] then
			side = refs[pair[2]].Position - refs[pair[1]].Position
			break
		end
	end
	if topName and (bottomName or root) and side then
		local bottom = bottomName and refs[bottomName].Position or root
		local up = refs[topName].Position - bottom
		local expected = AgentModels.Body[topName].CFrame.Y - (bottomName and AgentModels.Body[bottomName].CFrame.Y or 0)
		if up.Magnitude > 0.05 and side.Magnitude > 0.05 then
			local factor = up.Magnitude / expected
			if factor < 0.6 or factor > 1.6 then
				return nil, true, string.format("Körper ist %.2f-mal so groß wie im Spiel – stimmt die Einheit beim Import "
					.. "(1 Blender-Einheit = 1 Stud)?", factor)
			end
			up = up.Unit
			local right = side - up * side:Dot(up)
			if right.Magnitude > 0.05 then
				right = right.Unit
				local origin = root or (bottom - up * (bottomName and AgentModels.Body[bottomName].CFrame.Y or 0))
				return CFrame.fromMatrix(origin, right, up, right:Cross(up)), true, nil
			end
		end
	end
	if not root then
		return nil, false, nil
	end
	return CFrame.new(root), false, nil
end

-- Ein Modell aus Assets.Agents prüfen und vorbereiten. Gibt (Daten oder nil, Bericht) zurück.
local function loadAsset(agentId, source)
	local report = { Loaded = false, Errors = {}, Warnings = {} }
	local function problem(text)
		table.insert(report.Errors, text)
	end
	local function hint(text)
		table.insert(report.Warnings, text)
	end
	local skins = source:FindFirstChild("Skins")

	-- Marker, Körper und Ausrüstung einsammeln
	local root, refs, gear = nil, {}, {}
	for _, obj in source:GetDescendants() do
		if skins and (obj == skins or obj:IsDescendantOf(skins)) then
			continue
		end
		local name = cleanName(obj.Name)
		local point = string.match(name, "^Point_(.+)$")
		if point and (obj:IsA("BasePart") or obj:IsA("Attachment")) then
			if point == "Root" then
				root = markerPosition(obj)
			else
				hint("Unbekannter Marker " .. obj.Name)
			end
		elseif obj:IsA("BasePart") then
			local words = wordsOf(name)
			if table.find(words, "Ref") or name == "HumanoidRootPart" then
				continue -- nur Maßstab bzw. unsichtbarer Teil des Körpers (Export des Körpers aus Studio)
			elseif AgentModels.Body[name] then
				refs[name] = obj
			elseif AgentModels.Body[words[1] or ""] then
				table.insert(gear, obj)
			else
				problem(obj.Name .. ": der Name beginnt nicht mit einem Körperteil (z.B. Head_Helmet, UpperTorso_Vest)")
			end
		end
	end
	if #gear == 0 then
		problem("keine Ausrüstung im Modell (Teile heißen <Körperteil>_<Name>, z.B. Head_Helmet)")
	end
	local frame, fromBody, sizeProblem = frameOf(root, refs)
	if sizeProblem then
		problem(sizeProblem)
	elseif not frame then
		problem("Marker Point_Root fehlt (Boden zwischen den Füßen)")
	end
	if #report.Errors > 0 then
		return nil, report
	end
	if not root then
		hint("Marker Point_Root fehlt – ausgerichtet am mitgelieferten Körper")
	end
	local toAgent = frame:Inverse()

	-- Ruhelage eines Körperteils im Agentenraum: mitgelieferter Körper oder der Spielkörper
	local rests = {}
	local function restOf(bodyName)
		if not rests[bodyName] then
			local ref = refs[bodyName]
			if ref and fromBody then
				rests[bodyName] = { CFrame = CFrame.new(toAgent * ref.Position),
					Size = halfExtent(toAgent.Rotation * ref.CFrame.Rotation, ref.Size) * 2 }
			else
				rests[bodyName] = AgentModels.Body[bodyName]
			end
		end
		return rests[bodyName]
	end
	if fromBody then
		for name in refs do
			local size, expected = restOf(name).Size, AgentModels.Body[name].Size
			local deviation = (size - expected):Abs()
			if math.max(deviation.X, deviation.Y, deviation.Z) > MAX_BODY_DEVIATION then
				hint("Körperteil " .. name .. " ist " .. sizeText(size) .. " groß, im Spiel " .. sizeText(expected)
					.. " – ist es der schlanke Agenten-Körper aus der Vorlage?")
			end
		end
	end

	-- Ausrüstung: Lage relativ zum Körperteil, Farbzonen
	local entries, used, names = {}, {}, {}
	for _, original in gear do
		local name = cleanName(original.Name)
		local words = wordsOf(name)
		local bodyName = words[1]
		local rest = restOf(bodyName)
		local offset = rest.CFrame:ToObjectSpace(toAgent * original.CFrame)
		local position, half = offset.Position, rest.Size / 2
		local outside = Vector3.new(math.max(0, math.abs(position.X) - half.X), math.max(0, math.abs(position.Y) - half.Y),
			math.max(0, math.abs(position.Z) - half.Z)).Magnitude
		if outside > MAX_DISTANCE then
			problem(string.format("%s hängt nicht am Körperteil %s (Mitte %.2f Studs daneben) – stimmen Einheit "
				.. "(1 Blender-Einheit = 1 Stud), Lage und Richtung (Point_Root zwischen den Füßen, vorne = -Z)?",
				original.Name, bodyName, outside))
			continue
		end
		local extent = halfExtent(offset.Rotation, original.Size)
		local reach = math.max(math.abs(position.X) + extent.X - half.X, math.abs(position.Y) + extent.Y - half.Y,
			math.abs(position.Z) + extent.Z - half.Z)
		if reach > MAX_REACH then
			hint(string.format("%s steht %.2f Studs vom Körperteil %s ab – eng am Körper bauen (höchstens 0,25, Helm 0,3)",
				original.Name, reach, bodyName))
		end
		local part = original:Clone()
		if not part then
			hint(original.Name .. " lässt sich nicht kopieren (Archivable ist aus)")
			continue
		end
		for _, child in part:GetDescendants() do
			-- verschachtelte Teile kommen einzeln dran, Gelenke und Marker gehören nicht dazu
			if child:IsA("BasePart") or child:IsA("JointInstance") or child:IsA("WeldConstraint")
				or (child:IsA("Attachment") and string.match(cleanName(child.Name), "^Point_")) then
				child:Destroy()
			end
		end
		local unique, count = name, 1
		while used[unique] do
			count += 1
			unique = name .. "_" .. count
		end
		used[unique] = true
		local zone, neon = nil, false
		for _, word in words do
			if not zone and ZONES[word] then
				zone = word
			end
			neon = neon or word == "Neon"
		end
		local textured = part:FindFirstChildOfClass("SurfaceAppearance") ~= nil
		local plain = part.Color == Color3.new(1, 1, 1) and not textured
		if plain and not zone and not neon then
			part.Color = DEFAULT_COLOR
		end
		if neon then
			part.Material = Enum.Material.Neon
		end
		part.Name = unique
		part.CFrame = offset
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		table.insert(entries, { Name = unique, Body = bodyName, Offset = offset, RefSize = rest.Size, Zone = zone,
			NeonAccent = neon and plain, Template = part })
		names[unique] = true
	end
	if #entries > MAX_PARTS then
		hint(#entries .. " Ausrüstungsteile – höchstens " .. MAX_PARTS .. ": Teile am selben Körperteil ohne eigene "
			.. "Farbzone in Blender zusammenfügen (spart Leistung)")
	end
	for _, folder in skins and skins:GetChildren() or {} do
		for _, appearance in folder:GetChildren() do
			if appearance:IsA("SurfaceAppearance") and not names[cleanName(appearance.Name)] then
				hint("Skins/" .. folder.Name .. "/" .. appearance.Name .. ": kein Teil mit diesem Namen")
			end
		end
	end
	if #report.Errors > 0 then
		return nil, report
	end
	report.Loaded = true
	return { Gear = entries, Skins = skins }, report
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
	local ok, asset, report = pcall(loadAsset, name, source)
	if not ok then
		asset, report = nil, { Loaded = false, Warnings = {}, Errors = { "Fehler beim Laden: " .. tostring(asset) } }
	end
	assetReport[name] = report
	assetData[name] = asset
end

-- Ordner mit den Modellen: Rojo legt ReplicatedStorage.Assets.Agents an, die Modelle selbst liegen im Place.
-- Der Client wartet nicht darauf: Kommen Ordner oder Modelle erst nach dem Start an, werden sie dann geladen (bis
-- dahin zeigen die Vorschauen die Quader-Ausrüstung).
local function watchAgents(folder)
	for _, source in folder:GetChildren() do
		loadOne(source)
	end
	if RunService:IsClient() then
		folder.ChildAdded:Connect(loadOne)
	end
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
	end
	-- In Studio steht im Output, was mit jedem Modell los ist
	if RunService:IsStudio() then
		for name, report in assetReport do
			if report.Loaded then
				print("[Agentenmodelle] " .. name .. ": 3D-Modell geladen (" .. #assetData[name].Gear .. " Teile)")
			else
				warn("[Agentenmodelle] " .. name .. ": 3D-Modell NICHT geladen, es bleibt die Quader-Ausrüstung:\n  - "
					.. table.concat(report.Errors, "\n  - "))
			end
			if #report.Warnings > 0 then
				warn("[Agentenmodelle] " .. name .. ": Hinweise:\n  - " .. table.concat(report.Warnings, "\n  - "))
			end
		end
	end
end

-- Hat der Agent ein fertiges 3D-Modell (statt der Quader-Ausrüstung)?
function AgentModels.HasAsset(agentId)
	return agentId ~= nil and assetData[agentId] ~= nil
end

-- Prüfbericht aller Modelle in Assets.Agents: [Name] = { Loaded, Errors = { Text }, Warnings = { Text } }
function AgentModels.AssetReport()
	return assetReport
end

-- Lage und Größe eines Teils an einem Körperteil, das anders groß ist als beim Modellieren: Abstände und Größe
-- wachsen mit dem Körperteil (je Achse)
local function fitted(entry, body)
	local ratio = body.Size / entry.RefSize
	local size = entry.Template.Size
	if math.abs(ratio.X - 1) < 0.01 and math.abs(ratio.Y - 1) < 0.01 and math.abs(ratio.Z - 1) < 0.01 then
		return entry.Offset, size
	end
	local rotation = entry.Offset.Rotation
	local function along(axis)
		return (ratio * rotation:VectorToWorldSpace(axis)).Magnitude
	end
	size *= Vector3.new(along(Vector3.new(1, 0, 0)), along(Vector3.new(0, 1, 0)), along(Vector3.new(0, 0, 1)))
	return CFrame.new(entry.Offset.Position * ratio) * rotation, size
end

-- Ausrüstung aus dem 3D-Modell eines Agenten an einen Körper hängen.
-- parts = { [Körperteil] = BasePart } (fehlt ein Körperteil, fehlt auch seine Ausrüstung), primary/accent = Farben
-- (Agent bzw. Skin), skinId = ausgerüsteter Agenten-Skin (für Textur-Skins, optional), weld = true: an die
-- Körperteile geschweißt (Charaktere), sonst verankert (Figuren). Jedes Teil bekommt das Attribut AgentGear.
-- Gibt die neuen Teile zurück, nil, wenn der Agent kein Modell hat.
function AgentModels.Attach(container, parts, agentId, primary, accent, skinId, weld)
	local asset = agentId and assetData[agentId]
	if not asset then
		return nil
	end
	local textures = asset.Skins and skinId and asset.Skins:FindFirstChild(skinId)
	local created = {}
	for _, entry in asset.Gear do
		local body = parts[entry.Body]
		if not body then
			continue
		end
		local part = entry.Template:Clone()
		local offset, size = fitted(entry, body)
		part.Size = size
		part.CFrame = body.CFrame * offset
		local appearance = textures and textures:FindFirstChild(entry.Name)
		if appearance and appearance:IsA("SurfaceAppearance") then
			for _, old in part:GetChildren() do
				if old:IsA("SurfaceAppearance") then
					old:Destroy()
				end
			end
			appearance:Clone().Parent = part
		end
		if entry.Zone == "Primary" then
			part.Color = primary
		elseif entry.Zone == "Accent" or entry.NeonAccent then
			part.Color = accent
		elseif entry.Zone == "Glass" then
			part.Color = AgentModels.VisorColor(accent)
			if not part:FindFirstChildOfClass("SurfaceAppearance") then
				part.Material = Enum.Material.SmoothPlastic
				part.Reflectance = AgentModels.VisorReflectance
			end
		end
		part.Anchored = not weld
		part:SetAttribute("AgentGear", true)
		if weld then
			local joint = Instance.new("WeldConstraint")
			joint.Part0 = body
			joint.Part1 = part
			joint.Parent = part
		end
		part.Parent = container
		table.insert(created, part)
	end
	return created
end

return AgentModels

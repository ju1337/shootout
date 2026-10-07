-- AgentBody (ModuleScript, nur Server)
-- Einheitlicher Agenten-Körper für alle Charaktere: Spieler (im Hub, im Markt und im Match), Bots und
-- Übungspuppen bekommen denselben schlanken R15-Körper (Standardteile, feste Maße aus AgentConfig.BodyScale, kein
-- Rthro, kein eigener Avatar). Damit sind die Trefferzonen für alle gleich – getroffen werden nur die Körperteile.
-- Dazu die Ausrüstung des Agenten: sein fertiges 3D-Modell aus Assets.Agents (AgentModels, Anleitung in
-- docs/agenten-modelle.md) oder, solange es keins gibt, die Quader-Ausrüstung der Menü-Figur: Kapuze, Maske,
-- getöntes Visier, Weste, Schulterpolster und Gürtel in den Agentenfarben bzw. im Skin. Die Kapuze ist ein offener
-- Rahmen (oben, hinten, seitlich), weil der R15-Kopf rund ist: ein geschlossener Kasten würde fast das ganze
-- Gesicht verdecken. Statt des Roblox-Gesichts tragen alle Visier und Maske. Ausrüstung und Accessoires sind für
-- Schüsse unsichtbar (CanQuery = false), auch Accessoires, die erst später an den Charakter gehängt werden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local AgentModels = require(Shared.AgentModels)

local AgentBody = {}

AgentBody.SkinColor = AgentModels.SkinColor
local MASK = Color3.fromRGB(52, 54, 58)
local BELT = Color3.fromRGB(30, 30, 30)

-- Visier in der Welt: fast schwarz mit einem Hauch Agentenfarbe und glänzend (Glas-Material wirkt im Licht
-- des Hubs hellgrau und verschwindet fast) – gilt auch für Visiere aus 3D-Modellen (Wort Glass)
AgentBody.VisorColor = AgentModels.VisorColor
local VISOR_REFLECTANCE = AgentModels.VisorReflectance

-- Hosen: Uniformfarbe abgedunkelt (wie bei der Menü-Figur)
AgentBody.PantsColor = AgentModels.PantsColor

-- Beschreibung des Körpers für Player:LoadCharacterWithHumanoidDescription bzw.
-- Players:CreateHumanoidModelFromDescription. Alle Körperteile Standard (0), keine Kleidung, keine Accessoires,
-- Standard-Animationen; nur die Farben unterscheiden sich.
function AgentBody.Description(primary)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = AgentBody.SkinColor
	description.TorsoColor = primary
	description.LeftArmColor = primary
	description.RightArmColor = primary
	local pants = AgentBody.PantsColor(primary)
	description.LeftLegColor = pants
	description.RightLegColor = pants
	-- feste Maße: klassische R15-Proportionen, Kopf und Größe Standard, Breite/Tiefe schlank
	description.HeightScale = 1
	description.HeadScale = 1
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	AgentConfig.DescribeBody(description)
	return description
end

-- Quader-Ausrüstung (wie bei der Menü-Figur), relativ zum Körperteil (passt sich an dessen Größe an):
-- { Name, Körperteil, Größe (× Teilgröße), Mitte (× Teilgröße, im Teil), Farbe, Material, Name nach der
-- Spezifikation für 3D-Modelle (so heißt das Teil in der Vorlage art/templates/Agents/Agent.obj) }
-- Kopf: Mitte = Mitte des Kopf-Teils, vorne = -Z; Augen liegen etwas über der Mitte.
local GEAR = {
	-- Kapuze als offener Rahmen um den Kopf: oben, hinten, links, rechts – das Gesicht bleibt frei
	{ "AgentHoodTop", "Head", Vector3.new(1.16, 0.16, 1.1), Vector3.new(0, 0.56, 0.05), "Primary", Enum.Material.Fabric,
		"Head_HoodTop_Primary" },
	{ "AgentHoodBack", "Head", Vector3.new(1.16, 1.02, 0.16), Vector3.new(0, 0.07, 0.57), "Primary", Enum.Material.Fabric,
		"Head_HoodBack_Primary" },
	{ "AgentHoodLeft", "Head", Vector3.new(0.14, 0.98, 1.08), Vector3.new(-0.56, 0.08, 0.04), "Primary", Enum.Material.Fabric,
		"Head_HoodLeft_Primary" },
	{ "AgentHoodRight", "Head", Vector3.new(0.14, 0.98, 1.08), Vector3.new(0.56, 0.08, 0.04), "Primary", Enum.Material.Fabric,
		"Head_HoodRight_Primary" },
	-- Visier über den Augen, Maske über Mund und Kinn
	{ "AgentVisor", "Head", Vector3.new(0.94, 0.22, 0.08), Vector3.new(0, 0.16, -0.5), "Visor", Enum.Material.SmoothPlastic,
		"Head_Visor_Glass" },
	{ "AgentMask", "Head", Vector3.new(0.84, 0.36, 0.07), Vector3.new(0, -0.24, -0.49), "Mask", Enum.Material.Fabric,
		"Head_Mask" },
	{ "AgentVest", "UpperTorso", Vector3.new(1.06, 0.7, 1.15), Vector3.new(0, 0.1, 0), "Accent", Enum.Material.Metal,
		"UpperTorso_Vest_Accent" },
	{ "AgentPadLeft", "LeftUpperArm", Vector3.new(1.18, 0.28, 1.18), Vector3.new(0, 0.42, 0), "Accent", Enum.Material.Metal,
		"LeftUpperArm_Pad_Accent" },
	{ "AgentPadRight", "RightUpperArm", Vector3.new(1.18, 0.28, 1.18), Vector3.new(0, 0.42, 0), "Accent", Enum.Material.Metal,
		"RightUpperArm_Pad_Accent" },
	{ "AgentBelt", "LowerTorso", Vector3.new(1.04, 0.75, 1.06), Vector3.new(0, 0, 0), "Belt", Enum.Material.SmoothPlastic,
		"LowerTorso_Belt" },
}
AgentBody.GearNames = {}
AgentBody.SpecNames = {} -- [Name der Quader-Ausrüstung] = Name in der Vorlage für 3D-Modelle
local gearNameSet = {}
for _, def in GEAR do
	table.insert(AgentBody.GearNames, def[1])
	AgentBody.SpecNames[def[1]] = def[7]
	gearNameSet[def[1]] = true
end
-- Körperteile, an denen Ausrüstung hängen kann (Quader oder 3D-Modell): [Name] = true
AgentBody.GearAnchors = {}
for _, name in AgentModels.BodyParts do
	AgentBody.GearAnchors[name] = true
end

local function gearColor(key, primary, accent)
	if key == "Primary" then
		return primary
	elseif key == "Accent" then
		return accent
	elseif key == "Visor" then
		return AgentBody.VisorColor(accent)
	elseif key == "Mask" then
		return MASK
	end
	return BELT
end

-- Teile in Accessoires (Hüte, Haare, Flügel, Rucksäcke) zählen nie als Treffer
local function makeUntargetable(obj)
	if obj:IsA("BasePart") and obj:FindFirstAncestorWhichIsA("Accoutrement") then
		obj.CanQuery = false
		obj.CanTouch = false
	end
end

local watched = setmetatable({}, { __mode = "k" })

-- Accessoires des Charakters untreffbar machen, jetzt und für alles, was später noch angehängt wird
function AgentBody.Protect(character)
	for _, obj in character:GetDescendants() do
		makeUntargetable(obj)
	end
	if not watched[character] then
		watched[character] = true
		character.DescendantAdded:Connect(makeUntargetable)
	end
end

-- Gesicht: alle Decals am Kopf weg, auch solche, die Roblox nach dem Spawn noch anhängt (das Aussehen wird
-- teils erst nach CharacterAdded fertig geladen)
local faceWatched = setmetatable({}, { __mode = "k" })
local function stripFace(head)
	for _, child in head:GetChildren() do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end
	if not faceWatched[head] then
		faceWatched[head] = true
		head.ChildAdded:Connect(function(child)
			if child:IsA("Decal") then
				task.defer(function()
					if child.Parent then
						child:Destroy()
					end
				end)
			end
		end)
	end
end

-- Ganzer Charakter: der Spielkörper (Trefferzone) bleibt unsichtbar, solange das Modell der Look ist – egal, wer ihn
-- wieder sichtbar macht (Roblox setzt beim Laden des Aussehens teils Transparenz und Gesicht zurück). Sonst lägen
-- Spielkörper und Modell sichtbar übereinander.
-- [Charakter] = { [Körperteil-Name] = true }: diese Teile des Spielkörpers müssen unsichtbar bleiben (die das Modell abdeckt)
local hiddenBody = setmetatable({}, { __mode = "k" })
local guardedParts = setmetatable({}, { __mode = "k" }) -- [Körperteil] = true: wird schon bewacht
local revealReported = setmetatable({}, { __mode = "k" }) -- [Charakter] = true: schon im Studio-Output gemeldet

local function hideBodyPart(part)
	if part.Transparency < 1 then
		part.Transparency = 1
	end
	for _, child in part:GetChildren() do
		if child:IsA("Decal") and child.Transparency < 1 then -- auch Texture (erbt von Decal)
			child.Transparency = 1
		end
	end
end

local function guardBodyPart(character, part)
	if guardedParts[part] then
		return
	end
	guardedParts[part] = true
	local function enforce(what)
		local hidden = hiddenBody[character]
		if hidden and hidden[part.Name] and part.Parent == character then
			if RunService:IsStudio() and not revealReported[character] then
				revealReported[character] = true
				print("[Agentenmodelle] " .. character.Name .. ": " .. what .. " am Spielkörper (" .. part.Name
					.. ") wieder sichtbar gemacht – sofort wieder ausgeblendet, zu sehen bleibt nur das Modell")
			end
			hideBodyPart(part)
		end
	end
	part:GetPropertyChangedSignal("Transparency"):Connect(function()
		if part.Transparency < 1 then
			enforce("Transparenz")
		end
	end)
	part.ChildAdded:Connect(function(child)
		if child:IsA("Decal") then
			enforce("Gesicht/Decal")
		end
	end)
end

-- Eigenen Avatar entfernen (Kleidung, Accessoires, Gesicht), Körperfarben setzen, Ausrüstung neu anlegen.
-- agentId (optional): hat der Agent ein 3D-Modell (AgentModels), trägt er dessen Ausrüstung, sonst die Quader;
-- skinId = ausgerüsteter Agenten-Skin (Textur-Skins des Modells, optional).
-- Kann beliebig oft aufgerufen werden (z.B. nach einem Agenten- oder Skin-Wechsel); die Ausrüstung wird jedes Mal
-- neu an die aktuelle Größe der Körperteile angepasst.
function AgentBody.Dress(character, primary, accent, agentId, skinId)
	for _, obj in character:GetChildren() do
		if obj:IsA("Accoutrement") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic")
			or obj:IsA("CharacterMesh") then
			obj:Destroy()
		end
	end
	-- Körperteile; gibt es einen Namen kurz doppelt (Roblox tauscht gerade Teile aus), zählt das neueste
	local bodyParts, allBodyParts = {}, {}
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and AgentBody.GearAnchors[child.Name] then
			bodyParts[child.Name] = child
			table.insert(allBodyParts, child)
			if child.Name == "Head" then
				stripFace(child)
			end
		end
	end

	local colors = character:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	local pants = AgentBody.PantsColor(primary)
	colors.HeadColor3 = AgentBody.SkinColor
	colors.TorsoColor3 = primary
	colors.LeftArmColor3 = primary
	colors.RightArmColor3 = primary
	colors.LeftLegColor3 = pants
	colors.RightLegColor3 = pants
	colors.Parent = character

	-- alte Ausrüstung weg (Quader wie 3D-Modell), dann die neue anlegen
	for _, child in character:GetChildren() do
		if child:GetAttribute("AgentGear") or gearNameSet[child.Name] then
			child:Destroy()
		end
	end
	-- Körper wieder sichtbar (ein ganzer Charakter blendet ihn gleich wieder aus; nicht während der Tarnung)
	hiddenBody[character] = nil
	local function showBody()
		if not character:GetAttribute("Cloaked") then
			for _, part in bodyParts do
				part.Transparency = 0
			end
		end
	end
	showBody()
	-- 3D-Modell des Agenten; geht dabei etwas schief, trägt er die Quader-Ausrüstung (nie ohne Look)
	local ok, attached = pcall(AgentModels.Attach, character, bodyParts, agentId, primary, accent, skinId, true)
	if not ok then
		warn("[Agentenmodelle] " .. tostring(agentId) .. ": Modell konnte nicht angezogen werden (" .. tostring(attached)
			.. ") – Quader-Ausrüstung")
		for _, child in character:GetChildren() do
			if child:GetAttribute("AgentGear") then
				child:Destroy()
			end
		end
		showBody()
		attached = nil
	end
	local look = attached and (AgentModels.IsCharacter(agentId) and "Charakter" or "Modell") or "Quader"
	if RunService:IsStudio() and character:GetAttribute("AgentLook") ~= look then
		print("[Agentenmodelle] " .. character.Name .. " als " .. tostring(agentId) .. ": " .. (look == "Quader"
			and ("Quader-Ausrüstung" .. (AgentModels.HasAsset(agentId) and "" or " (kein Modell \"" .. tostring(agentId)
				.. "\" in Assets.Agents)")) or look == "Charakter" and "ganzer Charakter aus dem Modell" or "Ausrüstung aus dem Modell"))
	end
	character:SetAttribute("AgentLook", look)
	character:SetAttribute("AgentLookOf", agentId)
	if look == "Charakter" then
		local covered = {}
		for _, bodyName in AgentModels.PiecesOf(agentId) or {} do
			covered[bodyName] = true
		end
		hiddenBody[character] = covered
		for _, part in allBodyParts do
			if covered[part.Name] then
				hideBodyPart(part)
				guardBodyPart(character, part)
			end
		end
	end
	if attached then
		AgentBody.Protect(character)
		return
	end
	for _, def in GEAR do
		local name, bodyPart = def[1], bodyParts[def[2]]
		if bodyPart then
			local gear = Instance.new("Part")
			gear.Name = name
			gear.Size = bodyPart.Size * def[3]
			gear.CFrame = bodyPart.CFrame * CFrame.new(bodyPart.Size * def[4])
			gear.Color = gearColor(def[5], primary, accent)
			gear.Material = def[6]
			gear.Reflectance = def[5] == "Visor" and VISOR_REFLECTANCE or 0
			gear.CanCollide = false
			gear.CanQuery = false -- Ausrüstung ist kein Teil der Trefferzone
			gear.CanTouch = false
			gear.Massless = true
			gear.TopSurface = Enum.SurfaceType.Smooth
			gear.BottomSurface = Enum.SurfaceType.Smooth
			gear:SetAttribute("AgentGear", true)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = bodyPart
			weld.Part1 = gear
			weld.Parent = gear
			gear.Parent = character
		end
	end
	AgentBody.Protect(character)
end

-- Was am Look nicht (mehr) stimmt, als Text für den Studio-Output – nil, wenn alles sitzt (kein Roblox-Gesicht,
-- Ausrüstung bzw. Modell an den aktuellen Körperteilen, bei einem ganzen Charakter der Spielkörper unsichtbar).
-- Roblox tauscht beim Laden des Aussehens manchmal noch Körperteile aus – dann hängt die Ausrüstung an den alten
-- Teilen und fällt weg.
function AgentBody.DressProblem(character, agentId)
	local head = character:FindFirstChild("Head")
	if head and head:FindFirstChildWhichIsA("Decal") then
		return "Roblox-Gesicht am Kopf"
	end
	local present = {} -- [Name] = true für jedes Teil, das an einem Körperteil des Charakters hängt
	for _, child in character:GetDescendants() do -- auch im Untermodell eines ganzen Charakters
		if child:IsA("BasePart") and child:GetAttribute("AgentGear") then
			local weld = child:FindFirstChildOfClass("WeldConstraint")
			local part0 = weld and weld.Part0
			if not part0 or part0.Parent ~= character then
				return child.Name .. " hängt an einem Körperteil, das es nicht mehr gibt"
			end
			present[child.Name] = true
		end
	end
	-- jedes Teil, das beim Anziehen angelegt wurde (Modell oder – auch als Rückfall – Quader), muss noch da sein
	local look = character:GetAttribute("AgentLook")
	local expected = look ~= "Quader" and AgentModels.PiecesOf(agentId) or nil
	if not expected then
		expected = {}
		for _, def in GEAR do
			expected[def[1]] = def[2]
		end
	end
	for name, bodyName in expected do
		local part = character:FindFirstChild(bodyName)
		if part and part:IsA("BasePart") then
			if not present[name] then
				return name .. " fehlt"
			end
			if look == "Charakter" and part.Transparency < 1 and not character:GetAttribute("Cloaked") then
				return "Spielkörper sichtbar (" .. bodyName .. ")"
			end
		end
	end
	if character:GetAttribute("AgentLookOf") ~= agentId then
		return "trägt noch " .. tostring(character:GetAttribute("AgentLookOf"))
	end
	return nil
end

function AgentBody.IsDressed(character, agentId)
	return AgentBody.DressProblem(character, agentId) == nil
end

return AgentBody

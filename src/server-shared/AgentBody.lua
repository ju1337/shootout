-- AgentBody (ModuleScript, nur Server)
-- Einheitlicher Agenten-Körper für alle Charaktere, bis die eigenen Agenten-Modelle aus Blender da sind:
-- Spieler (im Hub, im Markt und im Match), Bots und Übungspuppen bekommen denselben schlanken R15-Körper
-- (Standardteile, feste Maße aus AgentConfig.BodyScale, kein Rthro, kein eigener Avatar). Damit sind die
-- Trefferzonen für alle gleich – getroffen werden nur die Körperteile.
-- Dazu die Ausrüstung der Menü-Figur (AgentFigure): Kapuze, Maske, getöntes Visier, Weste, Schulterpolster und
-- Gürtel in den Agentenfarben bzw. im Skin. Die Kapuze ist ein offener Rahmen (oben, hinten, seitlich), weil der
-- R15-Kopf rund ist: ein geschlossener Kasten würde fast das ganze Gesicht verdecken. Statt des Roblox-Gesichts
-- tragen alle Visier und Maske. Ausrüstung und Accessoires sind für Schüsse unsichtbar (CanQuery = false), auch
-- Accessoires, die erst später an den Charakter gehängt werden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)

local AgentBody = {}

AgentBody.SkinColor = Color3.fromRGB(205, 160, 130)
local MASK = Color3.fromRGB(52, 54, 58)
local BELT = Color3.fromRGB(30, 30, 30)

-- Visier in der Welt: fast schwarz mit einem Hauch Agentenfarbe und glänzend (Glas-Material wirkt im Licht
-- des Hubs hellgrau und verschwindet fast)
function AgentBody.VisorColor(accent)
	return Color3.fromRGB(22, 24, 28):Lerp(accent, 0.15)
end
local VISOR_REFLECTANCE = 0.3

-- Hosen: Uniformfarbe abgedunkelt (wie bei der Menü-Figur)
function AgentBody.PantsColor(primary)
	return primary:Lerp(Color3.new(0, 0, 0), 0.5)
end

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

-- Ausrüstung wie bei der Menü-Figur, relativ zum Körperteil (passt sich an dessen Größe an):
-- { Name, Körperteil, Größe (× Teilgröße), Mitte (× Teilgröße, im Teil), Farbe, Material }
-- Kopf: Mitte = Mitte des Kopf-Teils, vorne = -Z; Augen liegen etwas über der Mitte.
local GEAR = {
	-- Kapuze als offener Rahmen um den Kopf: oben, hinten, links, rechts – das Gesicht bleibt frei
	{ "AgentHoodTop", "Head", Vector3.new(1.16, 0.16, 1.1), Vector3.new(0, 0.56, 0.05), "Primary", Enum.Material.Fabric },
	{ "AgentHoodBack", "Head", Vector3.new(1.16, 1.02, 0.16), Vector3.new(0, 0.07, 0.57), "Primary", Enum.Material.Fabric },
	{ "AgentHoodLeft", "Head", Vector3.new(0.14, 0.98, 1.08), Vector3.new(-0.56, 0.08, 0.04), "Primary", Enum.Material.Fabric },
	{ "AgentHoodRight", "Head", Vector3.new(0.14, 0.98, 1.08), Vector3.new(0.56, 0.08, 0.04), "Primary", Enum.Material.Fabric },
	-- Visier über den Augen, Maske über Mund und Kinn
	{ "AgentVisor", "Head", Vector3.new(0.94, 0.22, 0.08), Vector3.new(0, 0.16, -0.5), "Visor", Enum.Material.SmoothPlastic },
	{ "AgentMask", "Head", Vector3.new(0.84, 0.36, 0.07), Vector3.new(0, -0.24, -0.49), "Mask", Enum.Material.Fabric },
	{ "AgentVest", "UpperTorso", Vector3.new(1.06, 0.7, 1.15), Vector3.new(0, 0.1, 0), "Accent", Enum.Material.Metal },
	{ "AgentPadLeft", "LeftUpperArm", Vector3.new(1.18, 0.28, 1.18), Vector3.new(0, 0.42, 0), "Accent", Enum.Material.Metal },
	{ "AgentPadRight", "RightUpperArm", Vector3.new(1.18, 0.28, 1.18), Vector3.new(0, 0.42, 0), "Accent", Enum.Material.Metal },
	{ "AgentBelt", "LowerTorso", Vector3.new(1.04, 0.75, 1.06), Vector3.new(0, 0, 0), "Belt", Enum.Material.SmoothPlastic },
}
AgentBody.GearNames = {}
AgentBody.GearAnchors = {} -- Körperteile, an denen Ausrüstung hängt: [Name] = true
for _, def in GEAR do
	table.insert(AgentBody.GearNames, def[1])
	AgentBody.GearAnchors[def[2]] = true
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

-- Eigenen Avatar entfernen (Kleidung, Accessoires, Gesicht), Körperfarben setzen, Ausrüstung neu anlegen.
-- Kann beliebig oft aufgerufen werden (z.B. nach einem Skin-Wechsel); die Ausrüstung wird jedes Mal neu an die
-- aktuelle Größe der Körperteile angepasst.
function AgentBody.Dress(character, primary, accent)
	for _, obj in character:GetChildren() do
		if obj:IsA("Accoutrement") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic")
			or obj:IsA("CharacterMesh") then
			obj:Destroy()
		end
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		stripFace(head)
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

	for _, def in GEAR do
		local name, bodyPart = def[1], character:FindFirstChild(def[2])
		local old = character:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		if bodyPart and bodyPart:IsA("BasePart") then
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
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = bodyPart
			weld.Part1 = gear
			weld.Parent = gear
			gear.Parent = character
		end
	end
	AgentBody.Protect(character)
end

return AgentBody

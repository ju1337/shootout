-- AgentBody (ModuleScript, nur Server)
-- Einheitlicher Agenten-Körper für alle Charaktere, bis die eigenen Agenten-Modelle aus Blender da sind:
-- Spieler (im Hub, im Markt und im Match), Bots und Übungspuppen bekommen denselben schlanken R15-Körper
-- (Standardteile, feste Maße aus AgentConfig.BodyScale, kein Rthro, kein eigener Avatar). Damit sind die
-- Trefferzonen für alle gleich – getroffen werden nur die Körperteile.
-- Dazu die Ausrüstung der Menü-Figur (AgentFigure): Kapuze, Maske, getöntes Visier, Weste, Schulterpolster und
-- Gürtel in den Agentenfarben bzw. im Skin. Ausrüstung und Accessoires sind für Schüsse unsichtbar
-- (CanQuery = false), auch Accessoires, die erst später an den Charakter gehängt werden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)

local AgentBody = {}

AgentBody.SkinColor = Color3.fromRGB(205, 160, 130)
local MASK = Color3.fromRGB(45, 45, 50)
local BELT = Color3.fromRGB(30, 30, 30)

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
local GEAR = {
	-- Kapuze etwas nach hinten versetzt: das Gesicht (Maske, Visier) schaut vorne heraus
	{ "AgentHood", "Head", Vector3.new(1.27, 1.32, 1.18), Vector3.new(0, 0.07, 0.18), "Primary", Enum.Material.Fabric },
	{ "AgentMask", "Head", Vector3.new(0.86, 0.36, 0.1), Vector3.new(0, -0.27, -0.51), "Mask", Enum.Material.SmoothPlastic },
	{ "AgentVisor", "Head", Vector3.new(0.91, 0.2, 0.1), Vector3.new(0, 0.11, -0.52), "Visor", AgentConfig.VisorMaterial },
	{ "AgentVest", "UpperTorso", Vector3.new(1.06, 0.7, 1.15), Vector3.new(0, 0.1, 0), "Accent", Enum.Material.Metal },
	{ "AgentPadLeft", "LeftUpperArm", Vector3.new(1.18, 0.28, 1.18), Vector3.new(0, 0.42, 0), "Accent", Enum.Material.Metal },
	{ "AgentPadRight", "RightUpperArm", Vector3.new(1.18, 0.28, 1.18), Vector3.new(0, 0.42, 0), "Accent", Enum.Material.Metal },
	{ "AgentBelt", "LowerTorso", Vector3.new(1.04, 0.75, 1.06), Vector3.new(0, 0, 0), "Belt", Enum.Material.SmoothPlastic },
}
AgentBody.GearNames = {}
for _, def in GEAR do
	table.insert(AgentBody.GearNames, def[1])
end

local function gearColor(key, primary, accent)
	if key == "Primary" then
		return primary
	elseif key == "Accent" then
		return accent
	elseif key == "Visor" then
		return AgentConfig.VisorColor(accent)
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

-- Eigenen Avatar entfernen (Kleidung, Accessoires, Gesicht), Körperfarben setzen, Ausrüstung anlegen bzw.
-- umfärben. Kann beliebig oft aufgerufen werden (z.B. nach einem Skin-Wechsel).
function AgentBody.Dress(character, primary, accent)
	for _, obj in character:GetChildren() do
		if obj:IsA("Accoutrement") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic")
			or obj:IsA("CharacterMesh") then
			obj:Destroy()
		end
	end
	local head = character:FindFirstChild("Head")
	local face = head and head:FindFirstChild("face")
	if face and face:IsA("Decal") then
		face:Destroy() -- Maske und Visier statt Gesicht
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
		local gear = character:FindFirstChild(name)
		if not gear and bodyPart and bodyPart:IsA("BasePart") then
			gear = Instance.new("Part")
			gear.Name = name
			gear.Size = bodyPart.Size * def[3]
			gear.CFrame = bodyPart.CFrame * CFrame.new(bodyPart.Size * def[4])
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
		if gear and gear:IsA("BasePart") then
			gear.Color = gearColor(def[5], primary, accent)
			gear.Material = def[6]
			gear.Reflectance = def[5] == "Visor" and 0.25 or 0
		end
	end
	AgentBody.Protect(character)
end

return AgentBody

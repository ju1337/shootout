-- CharacterBody (ModuleScript, nur Server)
-- Körper für Bots und Übungspuppen: schlanker R15-Körper im Roblox-Standard-Look (Standardteile, feste Maße aus
-- AgentConfig.BodyScale, Kopf in Hautfarbe mit dem Roblox-Gesicht, Oberkörper und Arme in einer Farbe, Beine dunkler).
-- Spieler behalten ihren eigenen Roblox-Avatar. Accessoires sind bei allen Charakteren für Schüsse unsichtbar
-- (CanQuery = false), auch die, die erst später an den Charakter gehängt werden (Protect).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)

local CharacterBody = {}

CharacterBody.SkinColor = Color3.fromRGB(205, 160, 130)
CharacterBody.FaceTexture = "rbxasset://textures/face.png" -- Roblox-Standardgesicht

-- Hosen: Hauptfarbe abgedunkelt
function CharacterBody.PantsColor(primary)
	return primary:Lerp(Color3.new(0, 0, 0), 0.5)
end

-- Beschreibung des Körpers für Players:CreateHumanoidModelFromDescription. Alle Körperteile Standard (0),
-- Roblox-Standardgesicht, keine Kleidung, keine Accessoires, Standard-Animationen; nur die Farben unterscheiden sich.
function CharacterBody.Description(primary)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = CharacterBody.SkinColor
	description.TorsoColor = primary
	description.LeftArmColor = primary
	description.RightArmColor = primary
	local pants = CharacterBody.PantsColor(primary)
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

-- Teile in Accessoires (Hüte, Haare, Flügel, Rucksäcke) zählen nie als Treffer
local function makeUntargetable(obj)
	if obj:IsA("BasePart") and obj:FindFirstAncestorWhichIsA("Accoutrement") then
		obj.CanQuery = false
		obj.CanTouch = false
	end
end

local watched = setmetatable({}, { __mode = "k" })

-- Accessoires des Charakters untreffbar machen, jetzt und für alles, was später noch angehängt wird
function CharacterBody.Protect(character)
	for _, obj in character:GetDescendants() do
		makeUntargetable(obj)
	end
	if not watched[character] then
		watched[character] = true
		character.DescendantAdded:Connect(makeUntargetable)
	end
end

-- Standard-Look anziehen: Kleidung und Accessoires weg, Körperfarben setzen, Roblox-Gesicht, falls keins da ist
function CharacterBody.Dress(character, primary)
	for _, obj in character:GetChildren() do
		if obj:IsA("Accoutrement") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic")
			or obj:IsA("CharacterMesh") then
			obj:Destroy()
		end
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") and not head:FindFirstChildWhichIsA("Decal")
		and not head:FindFirstChildOfClass("FaceControls") then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Texture = CharacterBody.FaceTexture
		face.Face = Enum.NormalId.Front
		face.Parent = head
	end
	local colors = character:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	local pants = CharacterBody.PantsColor(primary)
	colors.HeadColor3 = CharacterBody.SkinColor
	colors.TorsoColor3 = primary
	colors.LeftArmColor3 = primary
	colors.RightArmColor3 = primary
	colors.LeftLegColor3 = pants
	colors.RightLegColor3 = pants
	colors.Parent = character
	CharacterBody.Protect(character)
end

return CharacterBody

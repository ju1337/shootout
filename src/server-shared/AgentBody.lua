-- AgentBody (ModuleScript, nur Server)
-- Einheitlicher Agenten-Körper für alle Charaktere: Spieler (in der offenen Welt, im Markt und im Match), Bots und
-- Übungspuppen bekommen denselben schlanken R15-Körper (Standardteile, feste Maße aus AgentConfig.BodyScale, kein
-- Rthro, kein eigener Avatar). Damit sind die Trefferzonen für alle gleich – getroffen werden nur die Körperteile.
-- Aussehen: der Roblox-Standard-Look in den Farben des Agenten (Kopf in Hautfarbe mit dem Roblox-Gesicht, Oberkörper
-- und Arme in der Uniformfarbe, Beine dunkler) – oder, wenn es eins gibt, sein fertiges 3D-Modell aus Assets.Agents
-- (AgentModels, Anleitung in docs/agenten-modelle.md). Modellteile und Accessoires sind für Schüsse unsichtbar
-- (CanQuery = false), auch Accessoires, die erst später an den Charakter gehängt werden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local AgentModels = require(Shared.AgentModels)

local AgentBody = {}

AgentBody.SkinColor = AgentModels.SkinColor

-- Hosen: Uniformfarbe abgedunkelt (wie bei der Menü-Figur)
AgentBody.PantsColor = AgentModels.PantsColor

-- Beschreibung des Körpers für Player:LoadCharacterWithHumanoidDescription bzw.
-- Players:CreateHumanoidModelFromDescription. Alle Körperteile Standard (0), Roblox-Standardgesicht, keine Kleidung,
-- keine Accessoires, Standard-Animationen; nur die Farben unterscheiden sich.
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

-- Körperteile, an denen das 3D-Modell hängt: [Name] = true
AgentBody.GearAnchors = {}
for _, name in AgentModels.BodyParts do
	AgentBody.GearAnchors[name] = true
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

-- Mit Modell bleibt der Spielkörper (Trefferzone) unsichtbar – egal, wer ihn wieder sichtbar macht (Roblox setzt beim
-- Laden des Aussehens teils Transparenz und Gesicht zurück). Sonst lägen Spielkörper und Modell sichtbar übereinander.
local hiddenBody = setmetatable({}, { __mode = "k" }) -- [Charakter] = true: Spielkörper muss unsichtbar bleiben
local guardedParts = setmetatable({}, { __mode = "k" }) -- [Körperteil] = true: wird schon bewacht
local revealReported = setmetatable({}, { __mode = "k" }) -- [Charakter] = true: schon im Studio-Output gemeldet
local diesWatched = setmetatable({}, { __mode = "k" }) -- [Charakter] = true: Tod wird schon beobachtet

local function hideBodyPart(part)
	if part.Transparency < 1 then
		part.Transparency = 1
	end
	for _, child in part:GetChildren() do
		if child:IsA("Decal") and child.Transparency < 1 then -- Gesicht, auch Texture (erbt von Decal)
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
		if hiddenBody[character] and part.Parent == character then
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

local function removeModel(character)
	for _, child in character:GetChildren() do
		if child:GetAttribute("AgentGear") then
			child:Destroy()
		end
	end
end

-- Eigenen Avatar entfernen (Kleidung, Accessoires), Körperfarben setzen und – hat der Agent ein 3D-Modell
-- (AgentModels) – das Modell anlegen; sonst bleibt der Standard-Look mit dem Roblox-Gesicht.
-- Kann beliebig oft aufgerufen werden (z.B. nach einem Agentenwechsel); das Modell wird jedes Mal neu angelegt.
function AgentBody.Dress(character, primary, agentId)
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
		end
	end
	-- Roblox-Standardgesicht, falls der Kopf keins hat (ein dynamischer Kopf hat es im Mesh: FaceControls)
	local head = bodyParts.Head
	if head and not head:FindFirstChildWhichIsA("Decal") and not head:FindFirstChildOfClass("FaceControls") then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Texture = AgentModels.FaceTexture
		face.Face = Enum.NormalId.Front
		face.Parent = head
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

	-- altes Modell weg, Körper wieder sichtbar mit Gesicht (das Modell blendet ihn gleich wieder aus; nicht während
	-- der Tarnung)
	removeModel(character)
	hiddenBody[character] = nil
	local function showBody()
		if not character:GetAttribute("Cloaked") then
			for _, part in bodyParts do
				part.Transparency = 0
				for _, decal in part:GetChildren() do
					if decal:IsA("Decal") then
						decal.Transparency = 0
					end
				end
			end
		end
	end
	showBody()
	-- 3D-Modell des Agenten; geht dabei etwas schief, bleibt der Standard-Look (nie halb angezogen)
	local ok, attached = pcall(AgentModels.Attach, character, bodyParts, agentId, true)
	if not ok then
		warn("[Agentenmodelle] " .. tostring(agentId) .. ": Modell konnte nicht angezogen werden (" .. tostring(attached)
			.. ") – Standard-Look")
		removeModel(character)
		showBody()
		attached = nil
	end
	local look = attached and "Charakter" or "Standard"
	if RunService:IsStudio() and character:GetAttribute("AgentLook") ~= look then
		print("[Agentenmodelle] " .. character.Name .. " als " .. tostring(agentId) .. ": " .. (attached
			and "Modell aus Assets.Agents" or ("Standard-Look" .. (AgentModels.HasAsset(agentId) and ""
				or " (kein Modell \"" .. tostring(agentId) .. "\" in Assets.Agents)"))))
	end
	character:SetAttribute("AgentLook", look)
	character:SetAttribute("AgentLookOf", agentId)
	if attached then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and not diesWatched[character] then
			diesWatched[character] = true
			humanoid.Died:Once(function()
				AgentModels.WeldToBody(character) -- Agentenmodell (Rig) fällt mit dem Körper
			end)
		end
		hiddenBody[character] = true
		for _, part in allBodyParts do
			hideBodyPart(part)
			guardBodyPart(character, part)
		end
	end
	AgentBody.Protect(character)
end

-- Was am Look nicht (mehr) stimmt, als Text für den Studio-Output – nil, wenn alles sitzt (Modell vollständig an den
-- aktuellen Körperteilen, Spielkörper samt Gesicht unsichtbar). Roblox tauscht beim Laden des Aussehens manchmal noch
-- Körperteile aus – dann hängt das Modell an den alten Teilen und fällt weg.
function AgentBody.DressProblem(character, agentId)
	if AgentModels.IsModelCharacter(character) then
		return nil -- das Modell ist selbst der Charakter
	end
	if character:GetAttribute("AgentLook") == "Charakter" then
		-- das Modell ist vollständig da und hängt an Teilen, die es im Charakter noch gibt
		local holder = character:FindFirstChild(AgentModels.ModelName)
		local count = 0
		for _, child in holder and holder:GetDescendants() or {} do
			if child:IsA("BasePart") then
				count += 1
			elseif child:IsA("WeldConstraint") and child.Name == "AgentWeld" and (not child.Part0
				or child.Part0.Parent ~= character) then
				return child.Parent.Name .. " hängt an einem Körperteil, das es nicht mehr gibt"
			end
		end
		local expected = holder and holder:GetAttribute("AgentParts") or 1
		if count < expected then
			return "Modell unvollständig (" .. count .. " von " .. expected .. " Teilen)"
		end
		-- Spielkörper samt Gesicht unsichtbar
		if not character:GetAttribute("Cloaked") then
			for _, part in character:GetChildren() do
				if part:IsA("BasePart") and AgentBody.GearAnchors[part.Name] then
					if part.Transparency < 1 then
						return "Spielkörper sichtbar (" .. part.Name .. ")"
					end
					for _, decal in part:GetChildren() do
						if decal:IsA("Decal") and decal.Transparency < 1 then
							return "Gesicht am Spielkörper sichtbar (" .. part.Name .. ")"
						end
					end
				end
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

-- Agentenmodell als R15-Rig (wie aus dem Avatar-Setup von Studio, mit Humanoid und HumanoidRootPart) unter
-- Assets.Agents, benannt wie der Agent. Hier gedreht und verschoben importiert und mit Armen in T-Haltung: Vorne ist,
-- wohin das HumanoidRootPart schaut, und sonst bleibt alles genau wie modelliert (auch die waagerechten Arme). Gelenke,
-- Rig-Attachments und Werte der Roblox-Skalierung fallen weg, Bones (gehäutete Meshes) bleiben. Der Spielkörper bleibt
-- unsichtbar als Trefferzone; der Server sorgt dafür, dass das so bleibt (Roblox tauscht Teile aus, macht sie sichtbar …).
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, tolerance)
	return (a - b).Magnitude <= (tolerance or 1e-3)
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder", ReplicatedStorage)
assets.Name = "Assets"
local folder = assets:FindFirstChild("Agents") or Instance.new("Folder", assets)
folder.Name = "Agents"

local AgentConfig = require("AgentConfig")
-- Als Client laden: der Client lädt auch Modelle, die erst nach dem Start in Assets.Agents ankommen
SIM.IsServer = false
local AgentModels = require("AgentModels")
local AgentBody = require("AgentBody")
local W = AgentConfig.BodyScale.Width
local PLACE = CFrame.new(100, 50, 30) * CFrame.Angles(0, math.rad(90), 0) -- irgendwo und gedreht importiert

-- Teile des Rigs im eigenen Raum (Boden = 0, Blick -Z): Rumpf, Kopf und Beine wie der Spielkörper, Arme in T-Haltung
local LAYOUT = {}
for _, partName in { "Head", "UpperTorso", "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg",
	"RightLowerLeg", "RightFoot" } do
	LAYOUT[partName] = { AgentModels.Body[partName].Size, AgentModels.Body[partName].CFrame }
end
for _, side in { -1, 1 } do
	local prefix = side < 0 and "Left" or "Right"
	local shoulder = Vector3.new(side * W, 3.763, 0)
	local elbow = shoulder + Vector3.new(side * 0.728, 0, 0)
	local wrist = elbow + Vector3.new(side * 0.76, 0, 0)
	LAYOUT[prefix .. "UpperArm"] = { Vector3.new(1.169, W, 0.8), CFrame.new((shoulder + elbow) / 2) }
	LAYOUT[prefix .. "LowerArm"] = { Vector3.new(1.052, W, 0.8), CFrame.new((elbow + wrist) / 2) }
	LAYOUT[prefix .. "Hand"] = { Vector3.new(0.3, W, 0.8), CFrame.new(wrist + Vector3.new(side * 0.15, 0, 0)) }
end
LAYOUT.Cap = { Vector3.new(1.3, 0.3, 1.3), CFrame.new(0, 5.2, 0) } -- Accessoire, an den Kopf geschweißt

local function buildRig(name, skip)
	local rig = Instance.new("Model")
	rig.Name = name
	Instance.new("Humanoid", rig)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2 * W, 2, 1)
	root.CFrame = PLACE * CFrame.new(0, 2.2, 0)
	root.Transparency = 1
	root.Parent = rig
	local parts = {}
	for partName, def in LAYOUT do
		if partName ~= skip then
			local p = Instance.new("MeshPart")
			p.Name = partName
			p.Size = def[1]
			p.CFrame = PLACE * def[2]
			p.Parent = rig
			local originalSize = Instance.new("Vector3Value") -- Wert der Roblox-Skalierung (aus dem Avatar-Setup)
			originalSize.Name = "OriginalSize"
			originalSize.Value = p.Size
			originalSize.Parent = p
			local attachment = Instance.new("Attachment") -- Rig-Attachment (Gelenk)
			attachment.Name = partName .. "RigAttachment"
			attachment.Parent = p
			parts[partName] = p
		end
	end
	for partName, p in parts do
		if partName ~= "LowerTorso" and partName ~= "Cap" then
			local motor = Instance.new("Motor6D")
			motor.Name = partName
			motor.Part0 = parts.LowerTorso
			motor.Part1 = p
			motor.Parent = p
		end
	end
	if parts.Head then
		local jaw = Instance.new("Bone") -- Gesichts-Bone (dynamischer Kopf)
		jaw.Name = "Jaw"
		jaw.CFrame = CFrame.new(0, -0.4, -0.3)
		jaw.Parent = parts.Head
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = parts.Cap
		weld.Part1 = parts.Head
		weld.Parent = parts.Cap
	end
	return rig
end

buildRig("Viper").Parent = folder
buildRig("Bastion", "LeftHand").Parent = folder -- ohne linke Hand
SIM.Advance(0.1) -- geladen wird am Ende des Moments
SIM.IsServer = true
local report = AgentModels.AssetReport()
check(report.Viper and report.Viper.Loaded and #report.Viper.Warnings == 0, "Viper: R15-Rig geladen "
	.. (report.Viper and table.concat(report.Viper.Errors, "; ") .. table.concat(report.Viper.Warnings, "; ") or ""))
check(report.Bastion and report.Bastion.Loaded
	and string.find(table.concat(report.Bastion.Warnings, " "), "LeftHand", 1, true) ~= nil,
	"fehlende Hand: lädt trotzdem, Hinweis")

-- An einen Körper in Ruhelage hängen (wie AgentBody.Dress an Spielern und Bots)
local body = Instance.new("Model")
local bodyParts = {}
for _, partName in AgentModels.BodyParts do
	local rest = AgentModels.Body[partName]
	local p = Instance.new("Part")
	p.Name = partName
	p.Size = rest.Size
	p.CFrame = rest.CFrame
	p.Parent = body
	bodyParts[partName] = p
end
local created = AgentModels.Attach(body, bodyParts, "Viper", true)
check(created ~= nil and #created == 16, "15 Körperteile + Kappe angehängt (" .. tostring(created and #created) .. ")")
local holder = body:FindFirstChild(AgentModels.ModelName)
local byName = {}
for _, p in created or {} do
	-- Namen wie im Rig (gehäutete Meshes finden ihre Gelenke darüber), im eigenen Untermodell
	check(p.Parent == holder, p.Name .. ": im Untermodell")
	byName[p.Name] = p
	check(p:FindFirstChildOfClass("Motor6D") == nil and p:FindFirstChildOfClass("Attachment") == nil
		and p:FindFirstChildWhichIsA("ValueBase") == nil, p.Name .. ": ohne Gelenke, Rig-Attachments und Skalierungswerte")
	-- genau wie modelliert, Blick nach vorne (das Rig war um 90° gedreht)
	local def = LAYOUT[p.Name]
	check(def and near(p.Position, def[2].Position) and near(p.Size, def[1])
		and p.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.9999, p.Name .. ": wie modelliert")
end
local jaw = byName.Head and byName.Head:FindFirstChild("Jaw")
check(jaw ~= nil and jaw:IsA("Bone") and near(jaw.CFrame.Position, Vector3.new(0, -0.4, -0.3)), "Gesichts-Bone bleibt")
check(byName.Cap and byName.Cap:FindFirstChildOfClass("WeldConstraint").Part0 == bodyParts.Head, "Kappe am Kopf")
for partName, p in bodyParts do
	check(p.Transparency == 1 and body:FindFirstChild(partName) == p, partName .. ": Spielkörper unsichtbar, behält den Namen")
end

-- Erneut anziehen mit einem Agenten ohne Modell: Körper wieder sichtbar, Modell weg
AgentBody.Dress(body, Color3.new(0, 0, 0), "Mender")
check(bodyParts.Head.Transparency == 0 and body:FindFirstChild(AgentModels.ModelName) == nil,
	"anderer Agent: Körper wieder sichtbar, Modell entfernt")

-- ---------- Im Spiel: Spieler mit diesem Agenten ----------
game.JobId = "server-1"
SIM.DataStore("PlayerData_v1")
local function step(seconds)
	SIM.Run(SIM.Now + (seconds or 1))
end
local AgentService = require("AgentService")
local SpawnUtil = require("SpawnUtil")
AgentService.Init()
local alice = SIM.Join("Alice")
step(1)
alice:SetAttribute("Mode", "Hub")
alice:SetAttribute("Agent", "Viper")
local character = SpawnUtil.Spawn(alice, CFrame.new(10, 5, 10))
step(0.3)
local function state()
	local clones, visible = 0, 0
	local model = character:FindFirstChild(AgentModels.ModelName)
	for _, p in model and model:GetChildren() or {} do
		if p:IsA("BasePart") and p:GetAttribute("AgentGear") then
			clones += 1
		end
	end
	for _, p in character:GetChildren() do
		if p:IsA("BasePart") and AgentModels.Body[p.Name] and p.Transparency < 1 then
			visible += 1
		end
	end
	return clones, visible
end
local clones, visible = state()
check(clones > 0 and visible == 0 and character:GetAttribute("AgentLook") == "Charakter"
	and AgentBody.IsDressed(character, "Viper"), "Spieler mit dem Modell (" .. clones .. " Modellteile, "
	.. visible .. " Körperteile sichtbar)")

-- Fällt etwas weg (z.B. weil Roblox Körperteile nachträglich austauscht), zieht der Server neu an
for _, p in character:GetChildren() do
	if p:GetAttribute("AgentGear") then
		p:Destroy()
		break
	end
end
check(not AgentBody.IsDressed(character, "Viper"), "fehlendes Modellteil erkannt")
step(3)
check(AgentBody.IsDressed(character, "Viper"), "nach kurzer Zeit wieder vollständig angezogen")

-- Macht etwas (Roblox beim Laden des Aussehens, ein Skript) den Spielkörper wieder sichtbar oder hängt ein Gesicht an,
-- blendet der Server ihn sofort wieder aus: Spielkörper und Modell liegen nie sichtbar übereinander
character.UpperTorso.Transparency = 0
step(0.1)
check(character.UpperTorso.Transparency == 1, "sichtbar gemachter Spielkörper sofort wieder unsichtbar")
local face = Instance.new("Decal")
face.Name = "face"
face.Parent = character.Head
check(face.Transparency == 1, "neues Gesicht sofort unsichtbar")
step(0.1)
check(face.Transparency == 1 and AgentBody.IsDressed(character, "Viper"), "Gesicht bleibt unsichtbar")

-- Roblox tauscht ein Körperteil aus (wie auf dem Screenshot: neuer Kopf mit Roblox-Gesicht): das neue kommt sichtbar
-- dazu (kurz gibt es den Namen doppelt), das alte geht – angezogen wird das neue, das Modell hängt daran
local oldHead = character.Head
local newHead = Instance.new("MeshPart")
newHead.Name = "Head"
newHead.Size = oldHead.Size
newHead.CFrame = oldHead.CFrame
Instance.new("Decal", newHead).Name = "face"
newHead.Parent = character
step(0.1)
check(newHead.Transparency == 1 and oldHead.Transparency == 1, "doppelter Kopf: beide unsichtbar")
oldHead:Destroy()
step(0.1)
check(newHead.Transparency == 1 and newHead:FindFirstChildWhichIsA("Decal").Transparency == 1
	and AgentBody.IsDressed(character, "Viper"), "ausgetauschter Kopf: unsichtbar samt Gesicht, neu angezogen")
local onNewHead = false
for _, p in character:GetDescendants() do
	local weld = p:IsA("BasePart") and p:GetAttribute("AgentGear") and p:FindFirstChildOfClass("WeldConstraint")
	onNewHead = onNewHead or (weld and weld.Part0 == newHead) == true
end
check(onNewHead, "Modell hängt am neuen Kopf")

-- Später (nach den ersten Kontrollen) geht ein Modellteil ohne jedes Ereignis verloren: die regelmäßige Kontrolle
-- zieht neu an, solange der Charakter lebt
step(25)
for _, p in character:GetDescendants() do
	if p:IsA("BasePart") and p:GetAttribute("AgentGear") then
		p:Destroy()
		break
	end
end
check(not AgentBody.IsDressed(character, "Viper"), "verlorenes Modellteil erkannt")
step(6)
check(AgentBody.IsDressed(character, "Viper"), "regelmäßige Kontrolle: wieder angezogen")

-- Modell während des Spiels entfernt: Standard-Look, Körper samt Gesicht sichtbar
folder.Viper:Destroy()
step(0.3)
clones, visible = state()
local headFace = character.Head:FindFirstChildWhichIsA("Decal")
check(not AgentModels.HasAsset("Viper") and clones == 0 and visible > 0 and headFace ~= nil and headFace.Transparency == 0
	and character:GetAttribute("AgentLook") == "Standard", "Modell entfernt: sofort wieder Standard-Look mit Gesicht")
-- … und wieder eingefügt (z.B. in Studio während des Spiels): sofort der ganze Charakter
buildRig("Viper").Parent = folder
step(0.3)
clones, visible = state()
check(AgentModels.HasAsset("Viper") and clones > 0 and visible == 0 and character:GetAttribute("AgentLook") == "Charakter",
	"Modell eingefügt: sofort mit dem Modell angezogen")

-- Wirft das Anziehen mit dem Modell einen Fehler, bleibt der Standard-Look (nie halb angezogen)
local attach = AgentModels.Attach
AgentModels.Attach = function()
	error("kaputt")
end
SIM.Quiet = true
AgentBody.Dress(character, Color3.new(0, 0, 0), "Viper")
SIM.Quiet = false
AgentModels.Attach = attach
clones, visible = state()
check(clones == 0 and visible > 0 and character:GetAttribute("AgentLook") == "Standard", "Fehler im Modell: Standard-Look")

if failures == 0 then
	print("Agentenmodell als R15-Rig: alles in Ordnung")
end

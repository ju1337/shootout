--!expose BotService rigTemplate
-- Agentenmodell als Rig (Humanoid, HumanoidRootPart, Gelenke – wie ein StarterCharacter oder aus dem Avatar-Setup)
-- unter Assets.Agents, benannt wie der Agent. Hier gedreht und verschoben importiert: Das Rig bleibt komplett
-- (Gelenke, Rig-Attachments, Bones, Skalierungswerte, Humanoid – nur Skripte nicht), steht mit den Füßen auf dem Boden
-- und schaut nach vorne, sein HumanoidRootPart hängt am Spielkörper, und seine Gelenke übernehmen jedes Bild die
-- Bewegung des Spielkörpers. Beim Tod fällt es mit. Der Spielkörper bleibt unsichtbar als Trefferzone; der Server sorgt
-- dafür, dass das so bleibt (Roblox tauscht Teile aus, macht sie sichtbar …).
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
local function same(a, b)
	return near(a.Position, b.Position, 1e-6) and a.RightVector:Dot(b.RightVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
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

-- Gelenknamen wie im R15-Rig (alle hier am Unterkörper aufgehängt, Root am HumanoidRootPart)
local JOINT = { Head = "Neck", UpperTorso = "Waist", LowerTorso = "Root", LeftUpperArm = "LeftShoulder",
	LeftLowerArm = "LeftElbow", LeftHand = "LeftWrist", RightUpperArm = "RightShoulder", RightLowerArm = "RightElbow",
	RightHand = "RightWrist", LeftUpperLeg = "LeftHip", LeftLowerLeg = "LeftKnee", LeftFoot = "LeftAnkle",
	RightUpperLeg = "RightHip", RightLowerLeg = "RightKnee", RightFoot = "RightAnkle" }

-- Gelenke wie im Rig: Part1 = partName, Part0 = HumanoidRootPart (Root) bzw. LowerTorso, in Ruhelage
local function addJoints(model, parts, root)
	for partName, jointName in JOINT do
		local part, parent = parts[partName], partName == "LowerTorso" and root or parts.LowerTorso
		if part and parent then
			local motor = Instance.new("Motor6D")
			motor.Name = jointName
			motor.Part0 = parent
			motor.Part1 = part
			motor.C0 = parent.CFrame:ToObjectSpace(part.CFrame)
			motor.C1 = CFrame.new()
			motor.Transform = CFrame.new()
			motor.Parent = part
		end
	end
	return model
end

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
			p.TextureID = "rbxassetid://7"
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
	addJoints(rig, parts, root)
	local jaw = Instance.new("Bone") -- Gesichts-Bone (dynamischer Kopf)
	jaw.Name = "Jaw"
	jaw.CFrame = CFrame.new(0, -0.4, -0.3)
	jaw.Parent = parts.Head
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parts.Cap
	weld.Part1 = parts.Head
	weld.Parent = parts.Cap
	Instance.new("Script", rig).Name = "Animate" -- Skripte laufen im Spiel nicht mit
	return rig
end

buildRig("Viper").Parent = folder
buildRig("Bastion", "LeftHand").Parent = folder -- ohne linke Hand: ein Rig lädt trotzdem
SIM.Advance(0.1) -- geladen wird am Ende des Moments
SIM.IsServer = true
local report = AgentModels.AssetReport()
check(report.Viper and report.Viper.Loaded and #report.Viper.Warnings == 0, "Viper: Rig geladen "
	.. (report.Viper and table.concat(report.Viper.Errors, "; ") .. table.concat(report.Viper.Warnings, "; ") or ""))
check(report.Bastion and report.Bastion.Loaded, "Rig ohne linke Hand lädt")
check(AgentModels.PartCount("Viper") == 17, "17 Teile (15 Körperteile, Kappe, HumanoidRootPart): "
	.. AgentModels.PartCount("Viper"))

-- Spielkörper in Ruhelage mit denselben Gelenken (wie AgentBody.Dress an Spielern und Bots)
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
addJoints(body, bodyParts, nil)
local holder = AgentModels.Attach(body, bodyParts, "Viper", true)
check(holder ~= nil and holder == body:FindFirstChild(AgentModels.ModelName) and holder:GetAttribute("AgentGear"),
	"Rig im Untermodell " .. AgentModels.ModelName)
holder = holder or Instance.new("Model")
local modelRoot = holder:FindFirstChild("HumanoidRootPart")
check(modelRoot ~= nil and holder.PrimaryPart == modelRoot, "HumanoidRootPart bleibt (PrimaryPart)")
-- Rig bleibt komplett: Gelenke, Rig-Attachments, Bones, Skalierungswerte; nur Skripte sind weg
for partName, def in LAYOUT do
	local p = holder:FindFirstChild(partName)
	check(p ~= nil, partName .. " da")
	if p then
		check(near(p.Position, def[2].Position) and near(p.Size, def[1]) and p.TextureID == "rbxassetid://7"
			and p.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.9999,
			partName .. ": wie modelliert, Blick nach vorne (" .. tostring(p.Position) .. ")")
		check(p:FindFirstChild(partName .. "RigAttachment") ~= nil and p:FindFirstChild("OriginalSize") ~= nil,
			partName .. ": Rig-Attachment und Skalierungswert bleiben")
		check(p.CanQuery == false and p.CanCollide == false and p.CanTouch == false and p.Massless and not p.Anchored
			and p:GetAttribute("AgentGear"), partName .. ": nie Trefferzone, bewegt sich mit")
	end
	if JOINT[partName] then
		local motor = p and p:FindFirstChild(JOINT[partName])
		check(motor ~= nil and motor:IsA("Motor6D") and motor.Part1 == p, partName .. ": Gelenk " .. JOINT[partName] .. " bleibt")
	end
end
local jaw = holder:FindFirstChild("Head") and holder.Head:FindFirstChild("Jaw")
check(jaw ~= nil and jaw:IsA("Bone") and near(jaw.CFrame.Position, Vector3.new(0, -0.4, -0.3)), "Gesichts-Bone bleibt")
check(holder:FindFirstChild("Animate") == nil, "Skripte des Modells laufen nicht mit")
local inner = holder:FindFirstChildOfClass("Humanoid")
check(inner ~= nil and inner.EvaluateStateMachine == false and inner.DisplayDistanceType
	== Enum.HumanoidDisplayDistanceType.None, "Humanoid des Modells bleibt, steuert aber nichts")
local rootWeld = modelRoot and modelRoot:FindFirstChildOfClass("WeldConstraint")
check(rootWeld ~= nil and rootWeld.Part0 == bodyParts.LowerTorso and rootWeld.Part1 == modelRoot,
	"Rig am Spielkörper angeschweißt")
for partName, p in bodyParts do
	check(p.Transparency == 1 and body:FindFirstChild(partName) == p, partName .. ": Spielkörper unsichtbar, behält den Namen")
end

-- Jedes Bild (Client): die Gelenke des Rigs übernehmen die Bewegung der gleichnamigen Gelenke des Spielkörpers
local swing = CFrame.Angles(math.rad(40), 0, math.rad(-10))
bodyParts.RightUpperArm.RightShoulder.Transform = swing
bodyParts.LowerTorso.Root.Transform = CFrame.new(0, -0.2, 0)
AgentModels.SyncJoints(body)
check(same(holder.RightUpperArm.RightShoulder.Transform, swing) and same(holder.LowerTorso.Root.Transform,
	CFrame.new(0, -0.2, 0)) and same(holder.Head.Neck.Transform, CFrame.new()), "Gelenke übernommen")
-- Spielkörper ausgetauscht (neue Gelenke): neu zugeordnet
local oldShoulder = bodyParts.RightUpperArm.RightShoulder
local newShoulder = oldShoulder:Clone()
oldShoulder:Destroy()
newShoulder.Transform = CFrame.Angles(0, 0, math.rad(30))
newShoulder.Parent = bodyParts.RightUpperArm
AgentModels.SyncJoints(body)
check(same(holder.RightUpperArm.RightShoulder.Transform, newShoulder.Transform), "neues Gelenk des Spielkörpers übernommen")

-- Tod: Körperteile des Rigs an die gleichnamigen Teile des Spielkörpers geschweißt (fällt mit)
AgentModels.WeldToBody(body)
local welded = holder.RightUpperArm:FindFirstChildOfClass("WeldConstraint")
check(holder.RightUpperArm:FindFirstChildOfClass("Motor6D") == nil and welded ~= nil
	and welded.Part0 == bodyParts.RightUpperArm, "Tod: Rig hängt an den Teilen des Spielkörpers")

-- Figuren (Menüs, Shop, Markt): Rig wie gebaut, verankert, Körper unsichtbar, Waffe in seiner Hand
local AgentFigure = require("AgentFigure")
local figure = AgentFigure.Build(AgentConfig.Get("Viper"), Color3.new(0, 0, 0), Color3.new(1, 1, 1))
local worn = figure:FindFirstChild(AgentModels.ModelName)
local visibleBody = 0
for _, p in figure:GetChildren() do
	if p:IsA("BasePart") and AgentModels.Body[p.Name] and p.Transparency < 1 then
		visibleBody += 1
	end
end
check(worn ~= nil and visibleBody == 0 and near(worn.Head.Position, LAYOUT.Head[2].Position)
	and near(worn.LeftFoot.Position, LAYOUT.LeftFoot[2].Position), "Figur: Rig wie gebaut, Füße auf dem Boden")
for _, p in figure:GetDescendants() do
	if p:IsA("BasePart") and not p.Anchored then
		check(false, "Figur: " .. p.Name .. " verankert")
	end
end
local gun
for _, child in figure:GetChildren() do
	if child:IsA("Model") and child ~= worn then
		gun = child
	end
end
check(worn and gun and (gun:GetPivot().Position - worn.RightHand.Position).Magnitude < 0.3, "Waffe in der Hand des Rigs")

-- Erneut anziehen mit einem Agenten ohne Modell: Körper wieder sichtbar, Modell weg
AgentBody.Dress(body, Color3.new(0, 0, 0), "Mender")
check(bodyParts.Head.Transparency == 0 and body:FindFirstChild(AgentModels.ModelName) == nil,
	"anderer Agent: Körper wieder sichtbar, Modell entfernt")

-- ---------- Im Spiel: das Rig ist selbst der Charakter ----------
-- Wie ein StarterCharacter: der Roblox-Standardkörper wird ersetzt, das Rig bleibt unverändert (Gelenke, Bones,
-- Skalierungswerte, eigener Humanoid), seine sichtbaren Teile sind die Trefferzone.
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
alice:SetAttribute("Mode", "FreeForAll")
alice:SetAttribute("Agent", "Viper")
local character = SpawnUtil.Spawn(alice, CFrame.new(10, 5, 10))
step(0.3)
check(character == alice.Character and AgentModels.IsModelCharacter(character) and character.Name == "Alice",
	"Spieler: das Rig ist der Charakter")
check(character and character:FindFirstChild("Animate") ~= nil and character.Head.TextureID == "rbxassetid://7"
	and character.Head.CanQuery and character.Head.Transparency == 0, "Kopf des Rigs: sichtbar, Trefferzone; eigene Skripte laufen mit (wie als StarterCharacter)")
check(character and character.RightUpperArm:FindFirstChild("RightShoulder") ~= nil
	and character.RightUpperArm:FindFirstChild("OriginalSize") ~= nil and character.Head:FindFirstChild("Jaw") ~= nil,
	"Rig unverändert (Gelenke, Skalierungswerte, Bones)")
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
check(humanoid and humanoid.MaxHealth == AgentConfig.Get("Viper").Health and humanoid.DisplayDistanceType
	== Enum.HumanoidDisplayDistanceType.None, "Leben gesetzt, kein Roblox-Namensschild")
check(AgentBody.IsDressed(character, "Viper"), "nichts anzuziehen")
-- im Match bleibt der Charakter beim Agentenwechsel bis zum nächsten Spawn
alice:SetAttribute("Agent", "Mender")
step(0.3)
check(alice.Character == character, "Agentenwechsel im Match: erst beim nächsten Spawn")
character = SpawnUtil.Spawn(alice, CFrame.new(0, 5, 0))
step(0.3)
check(not AgentModels.IsModelCharacter(character) and character:GetAttribute("AgentLook") == "Standard",
	"nächster Spawn als MENDER (ohne Modell): Standard-Look")
-- Bot als VIPER: das Rig ist sein Körper
local BotService = require("BotService")
local template
task.spawn(function()
	template = BotService.__rigTemplate(AgentConfig.Get("Viper"))
end)
step(1)
check(template ~= nil and AgentModels.IsModelCharacter(template) and template:FindFirstChild("RightHand") ~= nil
	and template:FindFirstChildOfClass("Humanoid").BreakJointsOnDeath == false, "Bot: das Rig ist sein Körper")

if failures == 0 then
	print("Agentenmodell als Rig: alles in Ordnung")
end

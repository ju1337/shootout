-- Ganzer Charakter als Agentenmodell: ein R15-Rig (wie aus dem Avatar-Setup von Studio, mit Humanoid) unter
-- Assets.Agents heißt wie der Agent und ersetzt dessen Aussehen. Hier absichtlich doppelt so groß, gedreht, verschoben
-- und in T-Haltung: das Spiel bringt es auf die Größe des Spielkörpers, setzt jedes Teil an seinem Gelenk an und dreht
-- die Arme in die hängende Haltung. Der Spielkörper bleibt unsichtbar als Trefferzone, die Teile des Modells zählen nie
-- als Treffer. Fehlt ein Körperteil, wird das Modell nicht geladen.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
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
local SCALE = 2
local PLACE = CFrame.new(100, 50, 30) * CFrame.Angles(0, math.rad(90), 0) -- irgendwo und gedreht importiert

-- Rig im eigenen Raum bauen (Boden = 0, Blick -Z), dann skaliert an PLACE
local function buildRig(name, skip)
	local rig = Instance.new("Model")
	rig.Name = name
	Instance.new("Humanoid", rig)
	local function at(cframe)
		return PLACE * (CFrame.new(cframe.Position * SCALE) * cframe.Rotation)
	end
	local parts = {}
	local function part(partName, size, cframe)
		if partName == skip then
			return nil
		end
		local p = Instance.new("MeshPart")
		p.Name = partName
		p.Size = size * SCALE
		p.CFrame = at(cframe)
		p.Anchored = true
		p.Parent = rig
		parts[partName] = p
		return p
	end
	local function rigAttachment(partName, attachmentName, position)
		local p = parts[partName]
		if p then
			local a = Instance.new("Attachment")
			a.Name = attachmentName
			a.CFrame = p.CFrame:ToObjectSpace(at(CFrame.new(position)))
			a.Parent = p
		end
	end
	part("HumanoidRootPart", Vector3.new(2 * W, 2, 1), CFrame.new(0, 2.2, 0)).Transparency = 1
	-- Rumpf, Kopf, Beine wie der Spielkörper
	for _, partName in { "Head", "UpperTorso", "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg",
		"RightLowerLeg", "RightFoot" } do
		local rest = AgentModels.Body[partName]
		part(partName, rest.Size, rest.CFrame)
	end
	-- Arme in T-Haltung: waagerecht nach außen, lange Achse = X
	for _, side in { -1, 1 } do
		local prefix = side < 0 and "Left" or "Right"
		local shoulder = Vector3.new(side * W, 3.763, 0)
		local elbow = shoulder + Vector3.new(side * 0.728, 0, 0)
		local wrist = elbow + Vector3.new(side * 0.76, 0, 0)
		part(prefix .. "UpperArm", Vector3.new(1.169, W, 0.8), CFrame.new((shoulder + elbow) / 2))
		part(prefix .. "LowerArm", Vector3.new(1.052, W, 0.8), CFrame.new((elbow + wrist) / 2))
		part(prefix .. "Hand", Vector3.new(0.3, W, 0.8), CFrame.new(wrist + Vector3.new(side * 0.15, 0, 0)))
		rigAttachment(prefix .. "UpperArm", prefix .. "ShoulderRigAttachment", shoulder)
		rigAttachment(prefix .. "LowerArm", prefix .. "ElbowRigAttachment", elbow)
		rigAttachment(prefix .. "Hand", prefix .. "WristRigAttachment", wrist)
	end
	local joints = AgentModels.Joints
	for _, partName in { "Head", "UpperTorso", "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg",
		"RightLowerLeg", "RightFoot" } do
		rigAttachment(partName, joints[partName].Rig, joints[partName].At)
	end
	-- Accessoire: Kappe, an den Kopf geschweißt
	if parts.Head then
		local cap = part("Cap", Vector3.new(1.3, 0.3, 1.3), CFrame.new(0, 5.2, 0))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = cap
		weld.Part1 = parts.Head
		weld.Parent = cap
	end
	return rig
end

local viperRig = buildRig("Viper")
local skins = Instance.new("Folder", viperRig)
skins.Name = "Skins"
local skinFolder = Instance.new("Folder", skins)
skinFolder.Name = "A_Viper_Nacht"
Instance.new("SurfaceAppearance", skinFolder).Name = "UpperTorso"
Instance.new("SurfaceAppearance", skinFolder).Name = "UperTorso" -- Tippfehler
viperRig.Parent = folder
buildRig("Bastion", "LeftHand").Parent = folder -- unvollständig
SIM.Advance(0.1) -- geladen wird am Ende des Moments
SIM.IsServer = true
local report = AgentModels.AssetReport()
check(report.Viper and report.Viper.Loaded and report.Viper.Character, "Viper: als ganzer Charakter geladen "
	.. (report.Viper and table.concat(report.Viper.Errors, "; ") or ""))
check(AgentModels.HasAsset("Viper") and AgentModels.IsCharacter("Viper"), "HasAsset/IsCharacter")
local warned = false
for _, text in report.Viper and report.Viper.Warnings or {} do
	warned = warned or string.find(text, "skaliert", 1, true) ~= nil
end
check(warned, "Hinweis: Modell skaliert (doppelt so groß)")
local typo = false
for _, text in report.Viper and report.Viper.Warnings or {} do
	typo = typo or string.find(text, "UperTorso", 1, true) ~= nil
end
check(typo, "Hinweis: Textur-Skin mit falschem Teilnamen")
check(report.Bastion and not report.Bastion.Loaded and not AgentModels.HasAsset("Bastion")
	and string.find(table.concat(report.Bastion.Errors, " "), "LeftHand", 1, true) ~= nil, "fehlendes Körperteil gemeldet")

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
local created = AgentModels.Attach(body, bodyParts, "Viper", Color3.new(0, 0, 0), Color3.new(1, 1, 1), nil, true)
check(created ~= nil and #created == 16, "15 Körperteile + Kappe angehängt (" .. tostring(created and #created) .. ")")
local byName = {}
for _, p in created or {} do
	check(string.sub(p.Name, 1, 6) == "Model_", p.Name .. ": eigener Name (kein zweites Körperteil im Charakter)")
	byName[string.sub(p.Name, 7)] = p
	local weld = p:FindFirstChildOfClass("WeldConstraint")
	check(weld and weld.Part0 and weld.Part0.Parent == body, p.Name .. ": angeschweißt")
	check(p.CanQuery == false and p.CanCollide == false and p:GetAttribute("AgentGear"), p.Name .. ": nie Trefferzone")
	check(p:FindFirstChildOfClass("Attachment") == nil, p.Name .. ": ohne Rig-Attachments")
end
for partName, p in bodyParts do
	check(p.Transparency == 1, partName .. ": Spielkörper unsichtbar (Trefferzone)")
end

local function near(a, b, tolerance)
	return (a - b).Magnitude <= (tolerance or 0.05)
end
-- Größe: auf den Spielkörper gebracht
check(byName.Head and near(byName.Head.Size, AgentModels.Body.Head.Size), "Kopf in Spielgröße")
check(byName.Head and near(byName.Head.Position, AgentModels.Body.Head.CFrame.Position), "Kopf sitzt auf dem Hals")
check(byName.LeftFoot and near(byName.LeftFoot.Position, AgentModels.Body.LeftFoot.CFrame.Position), "Fuß am Boden")
-- Blickrichtung: Modell war gedreht importiert, Teile stehen wieder gerade
check(byName.UpperTorso and byName.UpperTorso.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.99, "Blick nach vorne (-Z)")
-- Arme: aus der T-Haltung in die Richtung der Spiel-Arme gedreht, zwischen Schulter und Ellbogen
local joints = AgentModels.Joints
for _, prefix in { "Left", "Right" } do
	local upper = byName[prefix .. "UpperArm"]
	local shoulder, elbow, wrist = joints[prefix .. "UpperArm"].At, joints[prefix .. "LowerArm"].At, joints[prefix .. "Hand"].At
	check(upper and near(upper.Position, (shoulder + elbow) / 2, 0.06), prefix .. "UpperArm zwischen Schulter und Ellbogen")
	check(upper and math.abs(upper.CFrame.RightVector:Dot((elbow - shoulder).Unit)) > 0.99, prefix .. "UpperArm hängt")
	local lower = byName[prefix .. "LowerArm"]
	check(lower and math.abs(lower.CFrame.RightVector:Dot((wrist - elbow).Unit)) > 0.99, prefix .. "LowerArm hängt")
	local hand = byName[prefix .. "Hand"]
	check(hand and hand.Position.Y < wrist.Y and near(Vector3.new(hand.Position.X, 0, hand.Position.Z),
		Vector3.new(wrist.X, 0, wrist.Z), 0.1), prefix .. "Hand unter dem Handgelenk")
end
-- Accessoire folgt dem Kopf
check(byName.Cap and byName.Cap:FindFirstChildOfClass("WeldConstraint").Part0 == bodyParts.Head
	and byName.Cap.Position.Y > byName.Head.Position.Y, "Kappe am Kopf")

-- Folgt dem Körperteil: Arm heben bewegt das Modell mit (wie im Spiel per Gelenk)
local before = byName.RightHand and byName.RightHand.Position
local raise = CFrame.new(AgentModels.RightShoulder) * CFrame.Angles(math.rad(70), 0, 0) * CFrame.new(-AgentModels.RightShoulder)
-- (in der Engine bewegt die WeldConstraint nicht mit – Lage relativ zum Körperteil prüfen)
check(byName.RightHand and near(bodyParts.RightHand.CFrame:ToObjectSpace(byName.RightHand.CFrame).Position,
	AgentModels.Body.RightHand.CFrame:ToObjectSpace(byName.RightHand.CFrame).Position), "Hand relativ zum Körperteil fest")
check(before ~= nil and raise ~= nil, "Arm-Daten vorhanden")

-- Figuren (Menüs, Shop, Markt): Modell sichtbar, Körper unsichtbar
local AgentFigure = require("AgentFigure")
local figure = AgentFigure.Build(AgentConfig.Get("Viper"), Color3.new(0, 0, 0), Color3.new(1, 1, 1))
local visibleBody, modelParts = 0, 0
for _, p in figure:GetChildren() do
	if p:IsA("BasePart") then
		if AgentModels.Body[p.Name] then
			visibleBody += p.Transparency < 1 and 1 or 0
		elseif p:GetAttribute("AgentGear") then
			modelParts += 1
		end
	end
end
check(visibleBody == 0 and modelParts == 16, "Figur: nur das Modell zu sehen (" .. visibleBody .. " Körperteile sichtbar, "
	.. modelParts .. " Modellteile)")

-- Erneut anziehen mit einem Agenten ohne Modell: Körper wieder sichtbar
AgentBody.Dress(body, Color3.new(0, 0, 0), Color3.new(1, 1, 1), "Mender")
check(bodyParts.Head.Transparency == 0 and body:FindFirstChild("Head_2") == nil, "anderer Agent: Körper wieder sichtbar")
local leftover = 0
for _, p in body:GetChildren() do
	if p:GetAttribute("AgentGear") and p:IsA("MeshPart") then
		leftover += 1
	end
end
check(leftover == 0, "Modellteile beim Umziehen entfernt")

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
	for _, p in character:GetChildren() do
		if p:IsA("BasePart") then
			if p:GetAttribute("AgentGear") and string.sub(p.Name, 1, 6) == "Model_" then
				clones += 1
			elseif AgentModels.Body[p.Name] and p.Transparency < 1 then
				visible += 1
			end
		end
	end
	return clones, visible
end
local clones, visible = state()
check(clones > 0 and visible == 0 and character:GetAttribute("AgentLook") == "Charakter"
	and AgentBody.IsDressed(character, "Viper"), "Spieler als ganzer Charakter (" .. clones .. " Modellteile, "
	.. visible .. " Körperteile sichtbar)")

-- Fällt etwas weg (z.B. weil Roblox Körperteile nachträglich austauscht), zieht der Server neu an
for _, p in character:GetChildren() do
	if p:GetAttribute("AgentGear") then
		p:Destroy()
		break
	end
end
character.UpperTorso.Transparency = 0
check(not AgentBody.IsDressed(character, "Viper"), "fehlendes Modellteil / sichtbarer Körper erkannt")
step(3)
check(AgentBody.IsDressed(character, "Viper"), "nach kurzer Zeit wieder vollständig angezogen")

-- Modell während des Spiels entfernt: Quader-Ausrüstung, Körper sichtbar
folder.Viper:Destroy()
step(0.3)
clones, visible = state()
check(not AgentModels.HasAsset("Viper") and clones == 0 and visible > 0 and character:FindFirstChild("AgentVisor") ~= nil
	and character:GetAttribute("AgentLook") == "Quader", "Modell entfernt: sofort wieder Quader-Ausrüstung")
-- … und wieder eingefügt (z.B. in Studio während des Spiels): sofort der ganze Charakter
buildRig("Viper").Parent = folder
step(0.3)
clones, visible = state()
check(AgentModels.IsCharacter("Viper") and clones > 0 and visible == 0 and character:FindFirstChild("AgentVisor") == nil,
	"Modell eingefügt: sofort als ganzer Charakter angezogen")

-- Wirft das Anziehen mit dem Modell einen Fehler, trägt der Agent die Quader-Ausrüstung (nie ohne Look)
local attach = AgentModels.Attach
AgentModels.Attach = function()
	error("kaputt")
end
SIM.Quiet = true
AgentBody.Dress(character, Color3.new(0, 0, 0), Color3.new(1, 1, 1), "Viper")
SIM.Quiet = false
AgentModels.Attach = attach
clones, visible = state()
check(clones == 0 and visible > 0 and character:FindFirstChild("AgentVisor") ~= nil, "Fehler im Modell: Quader-Ausrüstung")

if failures == 0 then
	print("Ganzer Charakter: alles in Ordnung")
end

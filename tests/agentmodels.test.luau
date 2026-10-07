--!assets art/templates
--!expose AgentModels loadAsset
--!expose BotService rigTemplate
-- Agenten-Modelle (AgentModels): Die Vorlage art/templates/Agents/Agent.rbxmx (erzeugt von tools/agent_templates.py)
-- ist selbst ein gültiges Agenten-Modell. Unter Assets.Agents als "Viper" geladen, trägt VIPER genau die Ausrüstung,
-- die er heute als Quader trägt – an Spielern, Bots und in den Menü-Figuren. Dazu: Ausrichtung am mitgelieferten
-- Körper (gedreht und verschoben importiert), Anpassung an andere Körpergrößen, Textur-Skins, Rückfall ohne Modell
-- und die Prüfmeldungen, die in Studio im Output stehen.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, eps)
	if typeof(a) == "Vector3" then
		return (a - b).Magnitude < (eps or 1e-4)
	end
	return math.abs(a - b) < (eps or 1e-4)
end
local function hasText(list, text)
	for _, line in list or {} do
		if string.find(line, text, 1, true) then
			return true
		end
	end
	return false
end
local function step(seconds)
	SIM.Run(SIM.Now + (seconds or 1))
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local folder = ReplicatedStorage.Assets.Agents
local template = folder:FindFirstChild("Agent")
check(template ~= nil and template:IsA("Model"), "Vorlage Agent.rbxmx unter Assets.Agents")

-- Vor dem ersten require (der Lader liest Assets.Agents beim Laden): die Vorlage als VIPER und – gedreht und
-- verschoben wie nach einem Import, mit Textur-Skin – als BASTION. Die Vorlage selbst bleibt unter ihrem Namen liegen.
local viperSource = template:Clone()
viperSource.Name = "Viper"
viperSource.Parent = folder
local bastionSource = template:Clone()
bastionSource.Name = "Bastion"
local tilt = CFrame.new(12, -3, 40) * CFrame.Angles(0.4, 2.1, -0.3)
for _, part in bastionSource:GetDescendants() do
	if part:IsA("BasePart") then
		part.CFrame = tilt * part.CFrame
	end
end
local skins = Instance.new("Folder")
skins.Name = "Skins"
local steel = Instance.new("Folder")
steel.Name = "A_Bastion_Stahl"
steel.Parent = skins
local vestTexture = Instance.new("SurfaceAppearance")
vestTexture.Name = "UpperTorso_Vest_Accent"
vestTexture.Parent = steel
local strayTexture = Instance.new("SurfaceAppearance")
strayTexture.Name = "Head_Helmet"
strayTexture.Parent = steel
skins.Parent = bastionSource
bastionSource.Parent = folder

SIM.IsStudio = true -- Studio: Bericht im Output
local AgentModels = require("AgentModels")
SIM.IsStudio = false
local AgentBody = require("AgentBody")
local AgentConfig = require("AgentConfig")
local Cosmetics = require("Cosmetics")

-- ---------- Laden ----------
local report = AgentModels.AssetReport()
local function messages(entry)
	return entry and (table.concat(entry.Errors, "; ") .. " | " .. table.concat(entry.Warnings, "; ")) or "kein Bericht"
end
check(report.Viper and report.Viper.Loaded and #report.Viper.Errors == 0 and #report.Viper.Warnings == 0,
	"Vorlage lädt als Agent ohne Meldungen: " .. messages(report.Viper))
check(report.Bastion and report.Bastion.Loaded and #report.Bastion.Errors == 0,
	"gedreht und verschoben importiert: lädt (ausgerichtet am mitgelieferten Körper): " .. messages(report.Bastion))
check(report.Bastion and #report.Bastion.Warnings == 1 and hasText(report.Bastion.Warnings, "Skins/A_Bastion_Stahl/Head_Helmet"),
	"Textur ohne passendes Teil gemeldet: " .. messages(report.Bastion))
check(report.Agent and not report.Agent.Loaded and hasText(report.Agent.Errors, "unbekannter Name"),
	"Modell mit falschem Namen gemeldet")
check(AgentModels.HasAsset("Viper") and AgentModels.HasAsset("Bastion") and not AgentModels.HasAsset("Mender")
	and not AgentModels.HasAsset(nil), "HasAsset")

-- ---------- An einem Körper: genau wie die Quader-Ausrüstung ----------
local function rig(scale)
	local model = Instance.new("Model")
	model.Name = "Agent"
	Instance.new("Humanoid", model)
	local place = CFrame.new(5, 0, -7) * CFrame.Angles(0, 0.7, 0)
	for _, name in AgentModels.BodyParts do
		local body = AgentModels.Body[name]
		local part = Instance.new("Part")
		part.Name = name
		part.Size = body.Size * ((scale and scale[name]) or 1)
		part.CFrame = place * body.CFrame
		part.Parent = model
	end
	model.Parent = workspace
	return model
end
local primary, accent = Color3.fromRGB(40, 60, 50), Color3.fromRGB(90, 160, 110)

local function compare(label, model, blockout)
	for _, gearName in AgentBody.GearNames do
		local spec = AgentBody.SpecNames[gearName]
		local quad, part = blockout:FindFirstChild(gearName), model:FindFirstChild(spec)
		check(part ~= nil and quad ~= nil, label .. ": " .. spec .. " da")
		if part and quad then
			check(near(part.Position, quad.Position, 1e-3) and near(part.Size, quad.Size, 1e-3)
				and near(part.CFrame.LookVector, quad.CFrame.LookVector, 1e-3)
				and near(part.CFrame.UpVector, quad.CFrame.UpVector, 1e-3), label .. ": " .. spec .. " sitzt wie die Quader")
			check(part.Color == quad.Color and part.Material == quad.Material
				and near(part.Reflectance or 0, quad.Reflectance or 0), label .. ": " .. spec .. " Farbe und Material wie die Quader")
			check(part.CanQuery == false and part.CanCollide == false and part.CanTouch == false and part.Massless == true
				and part.Anchored == false, label .. ": " .. spec .. " nie Trefferzone, ohne Kollision und Gewicht")
			check(part:GetAttribute("AgentGear") == true, label .. ": " .. spec .. " als Ausrüstung markiert")
			local weld = part:FindFirstChildOfClass("WeldConstraint")
			local body = model:FindFirstChild(string.match(spec, "^[^_]+"))
			check(weld ~= nil and weld.Part0 == body and weld.Part1 == part, label .. ": " .. spec .. " am Körperteil angeschweißt")
		end
	end
	check(model:FindFirstChild("AgentVest") == nil and model:FindFirstChild("AgentHoodTop") == nil,
		label .. ": keine Quader-Ausrüstung dazu")
end

local blockout = rig()
AgentBody.Dress(blockout, primary, accent)
check(blockout:FindFirstChild("AgentVest") ~= nil and blockout.AgentVest:GetAttribute("AgentGear") == true,
	"ohne Agent: Quader-Ausrüstung (markiert)")
local viper = rig()
AgentBody.Dress(viper, primary, accent, "Viper")
compare("Viper", viper, blockout)
local bastion = rig()
AgentBody.Dress(bastion, primary, accent, "Bastion")
compare("Bastion (gedreht importiert)", bastion, blockout)
local mender = rig()
AgentBody.Dress(mender, primary, accent, "Mender")
check(mender:FindFirstChild("AgentVest") ~= nil and mender:FindFirstChild("UpperTorso_Vest_Accent") == nil,
	"Agent ohne Modell: Quader-Ausrüstung")

-- Wechsel hin und her: nichts doppelt, nichts bleibt hängen
AgentBody.Dress(viper, primary, accent, "Mender")
check(viper:FindFirstChild("Head_Visor_Glass") == nil and viper:FindFirstChild("AgentVisor") ~= nil,
	"Wechsel auf Agent ohne Modell: Modell-Ausrüstung weg, Quader dran")
AgentBody.Dress(viper, primary, accent, "Viper")
AgentBody.Dress(viper, primary, accent, "Viper")
local visors = 0
for _, child in viper:GetChildren() do
	if child.Name == "Head_Visor_Glass" or child.Name == "AgentVisor" then
		visors += 1
	end
end
check(visors == 1, "erneut angezogen: genau ein Visier")

-- Anderer Körper (z.B. größerer Kopf): Ausrüstung wächst mit, wie die Quader
local scale = { Head = 1.25, UpperTorso = 1.1 }
local bigBlockout = rig(scale)
AgentBody.Dress(bigBlockout, primary, accent)
local bigViper = rig(scale)
AgentBody.Dress(bigViper, primary, accent, "Viper")
compare("größerer Körper", bigViper, bigBlockout)

-- Textur-Skin: nur mit diesem Skin, Farbe der Zone bleibt
local plain = rig()
AgentBody.Dress(plain, primary, accent, "Bastion")
check(plain.UpperTorso_Vest_Accent:FindFirstChildOfClass("SurfaceAppearance") == nil, "ohne Skin keine Textur")
local textured = rig()
AgentBody.Dress(textured, primary, accent, "Bastion", "A_Bastion_Stahl")
local vest = textured.UpperTorso_Vest_Accent
check(vest:FindFirstChildOfClass("SurfaceAppearance") ~= nil and vest.Color == accent, "Textur-Skin an der Weste")
check(textured.Head_Visor_Glass:FindFirstChildOfClass("SurfaceAppearance") == nil, "Textur nur am genannten Teil")
-- Die Vorlage ist nur Ausrüstung (5 Körperteile): der Spielkörper bleibt zu sehen
check(not AgentModels.IsCharacter("Viper") and viper:GetAttribute("AgentLook") == "Modell" and viper.UpperTorso.Transparency == 0
	and viper.LeftLowerLeg.Transparency == 0, "nur Ausrüstung: Spielkörper sichtbar")
for _, model in { blockout, viper, bastion, mender, bigBlockout, bigViper, plain, textured } do
	model:Destroy()
end

-- ---------- Ganzer Charakter ohne Humanoid ----------
-- Auf der Vorlage gebaut (z.B. in Blender), ein Teil <Körperteil>_<Name> je Körperteil: deckt das Modell Kopf, Rumpf,
-- Arme und Beine ab, ist es ein ganzer Charakter wie mit Humanoid – nur das Modell ist zu sehen, der Spielkörper bleibt
-- unsichtbar als Trefferzone (so lag sonst beides übereinander)
local function wholeBody(model, skip)
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and AgentModels.Body[string.match(child.Name, "^([^_]+)_") or ""] then
			child:Destroy() -- Ausrüstung der Vorlage weg
		end
	end
	for _, name in AgentModels.BodyParts do
		if not table.find(skip or {}, name) then
			local piece = Instance.new("MeshPart")
			piece.Name = name .. "_Geo"
			piece.Size = model[name].Size * 1.04
			piece.CFrame = model[name].CFrame
			piece.Parent = model
		end
	end
	return model
end
local hawkSource = wholeBody(template:Clone())
hawkSource.Name = "Hawk"
local ownTorso = Color3.fromRGB(70, 90, 40)
hawkSource.UpperTorso.Color = ownTorso -- selbst eingefärbter Körper (Rest bleibt der graue Vorlagen-Körper)
-- zusätzlich ein eigener Oberkörper mit demselben Namen (Blender hängt ".001" an): wird auch gezeigt, Bezug bleibt
-- der erste
local ownShirt = Instance.new("MeshPart")
ownShirt.Name = "UpperTorso.001"
ownShirt.Size = hawkSource.UpperTorso.Size * 1.1
ownShirt.CFrame = hawkSource.UpperTorso.CFrame
ownShirt.Color = Color3.fromRGB(90, 110, 60)
ownShirt.Parent = hawkSource
hawkSource.Parent = folder
local trapperSource = wholeBody(template:Clone(), { "LeftHand", "RightHand", "LeftFoot", "RightFoot" })
for _, name in { "LeftHand", "RightHand", "LeftFoot", "RightFoot" } do
	trapperSource[name]:Destroy() -- auch kein mitgelieferter Körper an Händen und Füßen
end
trapperSource.Name = "Trapper"
trapperSource.Parent = folder
-- Nur ein Körper (Teile heißen genau wie die Körperteile, z.B. R15-Rig ohne Humanoid): ganzer Charakter wie mit Humanoid
local ghostSource = template:Clone()
for _, child in ghostSource:GetChildren() do
	if child:IsA("BasePart") and string.find(child.Name, "_", 1, true) and not string.match(child.Name, "^Point_")
		and not string.match(child.Name, "^Ref_") then
		child:Destroy()
	end
end
ghostSource.Name = "Ghost"
ghostSource.Parent = folder
step(0.1)
report = AgentModels.AssetReport()
check(report.Hawk and report.Hawk.Loaded and report.Hawk.Character and #report.Hawk.Warnings == 0
	and AgentModels.IsCharacter("Hawk"), "ganzer Körper ohne Humanoid: als Charakter geladen, ohne Hinweis auf 12 Teile: "
	.. messages(report.Hawk))
local hawk = rig()
AgentBody.Dress(hawk, primary, accent, "Hawk")
local hawkModel = hawk:FindFirstChild(AgentModels.ModelName)
local hawkVisible = 0
for _, name in AgentModels.BodyParts do
	hawkVisible += hawk[name].Transparency < 1 and 1 or 0
end
check(hawkModel ~= nil and #hawkModel:GetChildren() == 31 and hawkVisible == 0 and hawk:GetAttribute("AgentLook") == "Charakter"
	and AgentBody.IsDressed(hawk, "Hawk"), "ganzer Körper ohne Humanoid: Ausrüstung und mitgelieferter Körper, Spielkörper "
	.. "unsichtbar (" .. (hawkModel and #hawkModel:GetChildren() or 0) .. " Teile, " .. hawkVisible .. " Körperteile sichtbar)")
-- Der mitgelieferte Körper wird mit angezeigt: grau aus der Vorlage in den Agentenfarben, selbst eingefärbt wie gebaut
local torso, head, shin = hawkModel and hawkModel:FindFirstChild("UpperTorso"), hawkModel and hawkModel:FindFirstChild("Head"),
	hawkModel and hawkModel:FindFirstChild("LeftLowerLeg")
check(torso and torso.Color == ownTorso, "eigener Körper: Farbe wie gebaut")
local shirt = hawkModel and hawkModel:FindFirstChild("UpperTorso_2")
check(shirt and shirt.Color == ownShirt.Color and near(shirt.Size, hawk.UpperTorso.Size * 1.1, 1e-3),
	"zweiter Oberkörper mit demselben Namen: auch zu sehen, Größe relativ zum ersten")
check(head and head.Color == AgentBody.SkinColor and shin and shin.Color == AgentBody.PantsColor(primary)
	and hawkModel.LeftUpperArm.Color == primary, "grauer Vorlagen-Körper: Haut, Uniform, Hose wie der Spielkörper")
check(torso and near(torso.Size, hawk.UpperTorso.Size, 1e-3) and near(torso.Position, hawk.UpperTorso.Position, 1e-3)
	and torso:FindFirstChildOfClass("WeldConstraint").Part0 == hawk.UpperTorso and torso.CanQuery == false,
	"mitgelieferter Körper sitzt genau auf dem Spielkörper, angeschweißt, nie Trefferzone")
check(report.Trapper and report.Trapper.Character and hasText(report.Trapper.Warnings, "ohne LeftHand"),
	"ohne Hände und Füße: trotzdem ganzer Charakter, mit Hinweis: " .. messages(report.Trapper))
local trapper = rig()
AgentBody.Dress(trapper, primary, accent, "Trapper")
check(trapper.UpperTorso.Transparency == 1 and trapper.LeftLowerArm.Transparency == 1 and trapper.LeftHand.Transparency == 0
	and trapper.RightFoot.Transparency == 0 and AgentBody.IsDressed(trapper, "Trapper"),
	"ohne Hände und Füße: nur dort bleibt der Spielkörper zu sehen")
local ghostPieces = 0
for _ in AgentModels.PiecesOf("Ghost") or {} do
	ghostPieces += 1
end
check(report.Ghost and report.Ghost.Loaded and report.Ghost.Character and ghostPieces == 15,
	"nur ein Körper ohne Ausrüstung: ganzer Charakter (15 Teile, Marker und Maßstab nicht): " .. messages(report.Ghost)
	.. " / " .. ghostPieces .. " Teile")
for _, model in { hawk, trapper } do
	model:Destroy()
end
hawkSource:Destroy()
trapperSource:Destroy()
ghostSource:Destroy()
step(0.1)

-- ---------- Prüfmeldungen ----------
local function variant(edit)
	local model = template:Clone()
	edit(model)
	local data, rep = AgentModels.__loadAsset("Viper", model)
	return data, rep
end
local function removeBody(model)
	for _, name in AgentModels.BodyParts do
		model[name]:Destroy()
	end
end
local function moveAll(model, cframe, factor)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local c = part.CFrame
			part.CFrame = cframe * (CFrame.new(c.Position * (factor or 1)) * c.Rotation)
			part.Size *= factor or 1
		end
	end
end
local base = variant(function() end)
local function offsetsMatch(data)
	if not (base and data) then
		return false
	end
	local byName = {}
	for _, entry in base.Gear do
		byName[entry.Name] = entry
	end
	for _, entry in data.Gear do
		local other = byName[entry.Name]
		if not (other and near(entry.Offset.Position, other.Offset.Position, 1e-3)
			and near(entry.Offset.LookVector, other.Offset.LookVector, 1e-3)) then
			return false
		end
	end
	return #data.Gear == #base.Gear
end

-- ohne Körper, nur verschoben: Point_Root und die Achsen des Modells reichen
local data, rep = variant(function(model)
	removeBody(model)
	moveAll(model, CFrame.new(3, 1, -2))
end)
check(data ~= nil and #rep.Warnings == 0 and offsetsMatch(data), "ohne Körper, verschoben: gleiche Lage: " .. messages(rep))
-- ohne Körper, aber liegend importiert: kann nicht passen
data, rep = variant(function(model)
	removeBody(model)
	moveAll(model, CFrame.Angles(math.rad(90), 0, 0))
end)
check(data == nil and hasText(rep.Errors, "hängt nicht am Körperteil"), "liegend ohne Körper gemeldet: " .. messages(rep))
-- 100-mal zu groß (FBX ohne „FBX Unit Scale“)
data, rep = variant(function(model)
	moveAll(model, CFrame.new(), 100)
end)
check(data == nil and hasText(rep.Errors, "Einheit"), "100-mal zu groß (mit Körper) gemeldet: " .. messages(rep))
data, rep = variant(function(model)
	removeBody(model)
	moveAll(model, CFrame.new(), 100)
end)
check(data == nil and hasText(rep.Errors, "Einheit"), "100-mal zu groß (ohne Körper) gemeldet: " .. messages(rep))
-- Point_Root fehlt: ohne Körper ein Fehler, mit Körper reicht der Körper
data, rep = variant(function(model)
	removeBody(model)
	model.Point_Root:Destroy()
end)
check(data == nil and hasText(rep.Errors, "Point_Root fehlt"), "fehlender Point_Root gemeldet: " .. messages(rep))
data, rep = variant(function(model)
	model.Point_Root:Destroy()
	moveAll(model, CFrame.new(-4, 2, 9) * CFrame.Angles(0, 1, 0))
end)
check(data ~= nil and hasText(rep.Warnings, "Point_Root fehlt") and offsetsMatch(data),
	"ohne Point_Root, mit Körper: lädt, Hinweis: " .. messages(rep))
-- Point_Root als Attachment (z.B. in Studio gesetzt)
data, rep = variant(function(model)
	local mask = model.Head_Mask
	local marker = Instance.new("Attachment")
	marker.Name = "Point_Root"
	marker.CFrame = mask.CFrame:ToObjectSpace(CFrame.new(model.Point_Root.Position))
	marker.Parent = mask
	model.Point_Root:Destroy()
	removeBody(model)
end)
check(data ~= nil and offsetsMatch(data), "Point_Root als Attachment: " .. messages(rep))
-- Namen
data, rep = variant(function(model)
	local stray = Instance.new("Part")
	stray.Name = "Helmet"
	stray.CFrame = model.Head.CFrame
	stray.Parent = model
end)
check(data == nil and hasText(rep.Errors, "Helmet: der Name beginnt nicht mit einem Körperteil"), "Name ohne Körperteil gemeldet")
-- (nur ein vollständiger Körper ohne Ausrüstung ist ein ganzer Charakter, siehe oben – fehlt auch ein Körperteil,
-- ist es nichts von beidem)
data, rep = variant(function(model)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and string.find(part.Name, "_") and not string.find(part.Name, "^Point_")
			and not string.find(part.Name, "^Ref_") then
			part:Destroy()
		end
	end
	model.LeftHand:Destroy()
end)
check(data == nil and hasText(rep.Errors, "keine Ausrüstung"), "Modell ohne Ausrüstung gemeldet")
data, rep = variant(function(model)
	model.Head_Mask.Name = "Head_Mask.001"
	local marker = Instance.new("Part")
	marker.Name = "Point_Backpack"
	marker.Parent = model
end)
check(data ~= nil and hasText(rep.Warnings, "Unbekannter Marker Point_Backpack"), "unbekannter Marker: Hinweis")
local names = {}
for _, entry in data and data.Gear or {} do
	names[entry.Name] = true
end
check(names.Head_Mask and not names["Head_Mask.001"], "Blender-Endung .001 zählt nicht zum Namen")
-- Körper aus Studio exportiert (AgentVorlage): mit HumanoidRootPart, kleine Abweichungen der Körperteile
data, rep = variant(function(model)
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(1.5, 2, 0.8)
	rootPart.CFrame = CFrame.new(0, 3, 0)
	rootPart.Parent = model
	model.UpperTorso.Size += Vector3.new(0.04, -0.05, 0.02)
end)
check(data ~= nil and #rep.Warnings == 0, "Körper aus Studio (mit HumanoidRootPart): lädt ohne Meldungen: " .. messages(rep))
-- Abstand und Budget
data, rep = variant(function(model)
	local antenna = Instance.new("Part")
	antenna.Name = "Head_Antenna"
	antenna.Size = Vector3.new(0.1, 1.5, 0.1)
	antenna.CFrame = model.Head.CFrame * CFrame.new(0.3, 1.0, 0.3)
	antenna.Parent = model
end)
check(data ~= nil and hasText(rep.Warnings, "Head_Antenna steht"), "weit abstehendes Teil: Hinweis: " .. messages(rep))
data, rep = variant(function(model)
	for i = 1, 3 do
		local pouch = Instance.new("Part")
		pouch.Name = "LowerTorso_Pouch" .. i
		pouch.Size = Vector3.new(0.2, 0.2, 0.2)
		pouch.CFrame = model.LowerTorso.CFrame * CFrame.new(-0.5 + i * 0.25, 0, -0.45)
		pouch.Parent = model
	end
end)
check(data ~= nil and hasText(rep.Warnings, "13 Ausrüstungsteile"), "zu viele Teile: Hinweis: " .. messages(rep))
-- Körper in falscher Breite (z.B. Roblox-Standard statt schlank)
data, rep = variant(function(model)
	model.UpperTorso.Size = Vector3.new(2, 1.6, 1)
end)
check(data ~= nil and hasText(rep.Warnings, "Körperteil UpperTorso ist"), "zu breiter Körper: Hinweis: " .. messages(rep))
-- Farben: Neon und unbemalte Importe
data, rep = variant(function(model)
	local lamp = Instance.new("Part")
	lamp.Name = "LeftUpperArm_Lamp_Neon"
	lamp.Size = Vector3.new(0.15, 0.15, 0.05)
	lamp.Color = Color3.new(1, 1, 1)
	lamp.CFrame = model.LeftUpperArm.CFrame * CFrame.new(0, 0, -0.42)
	lamp.Parent = model
	local glove = Instance.new("Part")
	glove.Name = "RightHand_Glove"
	glove.Size = Vector3.new(0.8, 0.32, 0.85)
	glove.Color = Color3.new(1, 1, 1)
	glove.CFrame = model.RightHand.CFrame
	glove.Parent = model
end)
local lampEntry, gloveEntry
for _, entry in data and data.Gear or {} do
	if entry.Name == "LeftUpperArm_Lamp_Neon" then
		lampEntry = entry
	elseif entry.Name == "RightHand_Glove" then
		gloveEntry = entry
	end
end
check(lampEntry and lampEntry.Template.Material == Enum.Material.Neon and lampEntry.NeonAccent, "Neon leuchtet (weiß: Akzentfarbe)")
check(gloveEntry and gloveEntry.Template.Color == Color3.fromRGB(52, 54, 58), "unbemalter Import ohne Farbzone: dunkelgrau")

-- ---------- Menü-Figur ----------
local AgentFigure = require("AgentFigure")
local figure = AgentFigure.Build(AgentConfig.Get("Viper"), primary, accent, nil, nil, nil)
check(figure:FindFirstChild("Head_Visor_Glass") ~= nil and figure:FindFirstChild("UpperTorso_Vest_Accent") ~= nil
	and figure:FindFirstChild("RightHand") ~= nil and figure:FindFirstChild("Torso") == nil,
	"Figur mit 3D-Modell: Spielkörper mit der Ausrüstung des Modells")
check(near(figure:GetPivot().Position, Vector3.new(0, 3, 0)), "Drehpunkt der Figur wie bisher auf Höhe 3")
local hand, pad = figure.RightHand, figure.RightUpperArm_Pad_Accent
check(hand.Position.Z < -1 and hand.Position.Y > 2.8, "rechter Arm nach vorne gehoben")
local restPad = AgentModels.Body.RightUpperArm.CFrame:ToObjectSpace(
	AgentModels.Body.RightUpperArm.CFrame * CFrame.new(0, 0.42 * AgentModels.Body.RightUpperArm.Size.Y, 0))
check(near(figure.RightUpperArm.CFrame:ToObjectSpace(pad.CFrame).Position, restPad.Position, 1e-3),
	"Schulterpolster geht mit dem gehobenen Arm mit")
local gun
for _, child in figure:GetChildren() do
	if child:IsA("Model") then
		gun = child
	end
end
check(gun ~= nil and (gun:GetPivot().Position - hand.Position).Magnitude < 0.3, "Waffe in der rechten Hand")
for _, part in figure:GetDescendants() do
	if part:IsA("BasePart") and not part.Anchored then
		check(false, "Figur: " .. part.Name .. " verankert")
	end
end
local old = AgentFigure.Build(AgentConfig.Get("Mender"), primary, accent)
check(old:FindFirstChild("Torso") ~= nil and old:FindFirstChild("Visor") ~= nil, "ohne Modell: bisherige Figur")

-- ---------- Spieler und Bots ----------
game.JobId = "server-1"
SIM.DataStore("PlayerData_v1")
local AgentService = require("AgentService")
local SpawnUtil = require("SpawnUtil")
AgentService.Init()
local alice = SIM.Join("Alice")
step(1)
alice:SetAttribute("Mode", "Hub")
alice:SetAttribute("Agent", "Viper")
local character = SpawnUtil.Spawn(alice, CFrame.new(10, 5, 10))
step(0.5)
local vPrimary, vAccent = Cosmetics.AgentColors(alice, "Viper")
check(character and character:FindFirstChild("Head_Visor_Glass") and character:FindFirstChild("UpperTorso_Vest_Accent")
	and character.UpperTorso_Vest_Accent.Color == vAccent and character:FindFirstChild("AgentVest") == nil,
	"Spieler als VIPER: Ausrüstung aus dem 3D-Modell")
-- Skin im Hub: neue Farben sofort
local skin = Cosmetics.Get("A_Viper_Nacht")
alice:SetAttribute("Owned", HttpService:JSONEncode({ A_Viper_Nacht = 1 }))
alice:SetAttribute("Equipped", HttpService:JSONEncode({ ["A:Viper"] = "A_Viper_Nacht" }))
step(0.1)
check(Cosmetics.AgentSkin(alice, "Viper") == skin, "ausgerüsteter Skin")
check(character.UpperTorso_Vest_Accent.Color == skin.Accent and character.Head_HoodTop_Primary.Color == skin.Primary,
	"Skin-Farben auf der Modell-Ausrüstung")
-- Agent ohne Modell: Quader
alice:SetAttribute("Agent", "Mender")
step(0.1)
check(character:FindFirstChild("AgentVest") ~= nil and character:FindFirstChild("UpperTorso_Vest_Accent") == nil,
	"Wechsel im Hub auf einen Agenten ohne Modell: Quader-Ausrüstung")
-- Bot mit VIPER
local BotService = require("BotService")
local botTemplate
task.spawn(function()
	botTemplate = BotService.__rigTemplate(AgentConfig.Get("Viper"))
end)
step(1)
check(botTemplate ~= nil and botTemplate:FindFirstChild("Head_Visor_Glass") ~= nil
	and botTemplate:FindFirstChild("AgentVisor") == nil, "Bot als VIPER trägt die Ausrüstung aus dem 3D-Modell")

if failures == 0 then
	print("Agenten-Modelle: alles in Ordnung")
end

--!expose BotService rigTemplate
-- Agenten-Modelle (AgentModels): Ein Modell unter Assets.Agents, benannt wie der Agent, ist im Spiel genau so zu sehen
-- wie in Blender bzw. Studio – jedes Teil an derselben Stelle, gleich groß, gleich gedreht, mit Farbe, Material und
-- Textur, nichts umgefärbt oder gestreckt. Jedes Teil hängt am Körperteil, zu dem es gehört (Name, sonst das nächste),
-- der Spielkörper bleibt unsichtbar als Trefferzone. Maße wie Viper_3.glb: 15 starre Teile <Körperteil>_Suit auf dem
-- Spielkörper, dazu Point_Root. Außerdem: falsche Einheit, fehlender Marker, Prüfmeldungen, Neuladen, Menü-Figur,
-- Spieler und Bots.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, eps)
	if typeof(a) == "Vector3" then
		return (a - b).Magnitude < (eps or 1e-3)
	end
	return math.abs(a - b) < (eps or 1e-3)
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
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder", ReplicatedStorage)
assets.Name = "Assets"
local folder = assets:FindFirstChild("Agents") or Instance.new("Folder", assets)
folder.Name = "Agents"

-- { Name, Größe, Mitte (Boden zwischen den Füßen = 0, Blick -Z) } wie in Viper_3.glb, dazu Haare ohne Körperteil-Namen
local SUIT = {
	{ "Head_Suit", Vector3.new(1.3, 1.2, 1.3), Vector3.new(0, 4.6, 0) },
	{ "LeftFoot_Suit", Vector3.new(0.75, 0.25, 0.8), Vector3.new(-0.375, 0.125, 0) },
	{ "LeftHand_Suit", Vector3.new(0.75, 0.275, 0.8), Vector3.new(-1.125, 2.1375, 0) },
	{ "LeftLowerArm_Suit", Vector3.new(0.75, 0.76, 0.8), Vector3.new(-1.125, 2.655, 0) },
	{ "LeftLowerLeg_Suit", Vector3.new(0.75, 0.93, 0.8), Vector3.new(-0.375, 0.715, 0) },
	{ "LeftUpperArm_Suit", Vector3.new(0.75, 0.915, 0.8), Vector3.new(-1.125, 3.4925, 0) },
	{ "LeftUpperLeg_Suit", Vector3.new(0.75, 0.82, 0.8), Vector3.new(-0.375, 1.59, 0) },
	{ "LowerTorso_Suit", Vector3.new(1.5, 0.4, 0.8), Vector3.new(0, 2.2, 0) },
	{ "RightFoot_Suit", Vector3.new(0.75, 0.25, 0.8), Vector3.new(0.375, 0.125, 0) },
	{ "RightHand_Suit", Vector3.new(0.75, 0.275, 0.8), Vector3.new(1.125, 2.1375, 0) },
	{ "RightLowerArm_Suit", Vector3.new(0.75, 0.76, 0.8), Vector3.new(1.125, 2.655, 0) },
	{ "RightLowerLeg_Suit", Vector3.new(0.75, 0.93, 0.8), Vector3.new(0.375, 0.715, 0) },
	{ "RightUpperArm_Suit", Vector3.new(0.75, 0.915, 0.8), Vector3.new(1.125, 3.4925, 0) },
	{ "RightUpperLeg_Suit", Vector3.new(0.75, 0.82, 0.8), Vector3.new(0.375, 1.59, 0) },
	{ "UpperTorso_Suit", Vector3.new(1.5, 1.6, 0.8), Vector3.new(0, 3.2, 0) },
	{ "Hair", Vector3.new(1.4, 0.3, 1.4), Vector3.new(0, 5.3, 0.05) },
}
local OWNER = { Hair = "Head" } -- Teil ohne Körperteil-Namen: gehört zum nächsten Körperteil
local function ownerOf(name)
	return OWNER[name] or string.match(name, "^[^_]+")
end
local TILT = CFrame.Angles(0, 0, math.rad(8)) -- ein Teil leicht gedreht modelliert (bleibt so)

-- Modell wie nach dem Import in Studio: irgendwo in der Welt (place), evtl. in falscher Einheit (unit)
local function suit(name, place, unit, withRoot)
	local model = Instance.new("Model")
	model.Name = name
	for i, def in SUIT do
		local part = Instance.new("MeshPart")
		part.Name = def[1]
		part.Size = def[2] * unit
		part.CFrame = place * CFrame.new(def[3] * unit) * (def[1] == "LeftUpperArm_Suit" and TILT or CFrame.new())
		part.Color = Color3.fromRGB(10 + i, 200, 30) -- Farbe aus der Datei
		part.Material = Enum.Material.Fabric
		part.TextureID = "rbxassetid://" .. i
		Instance.new("SurfaceAppearance", part)
		local scaleValue = Instance.new("Vector3Value") -- Wert der Roblox-Skalierung (z.B. aus dem Avatar-Setup)
		scaleValue.Name = "OriginalSize"
		scaleValue.Parent = part
		part.Parent = model
	end
	local hidden = Instance.new("Part") -- unsichtbares Hilfsteil: wird nicht gezeigt
	hidden.Name = "Collider"
	hidden.Transparency = 1
	hidden.Size = Vector3.new(4, 6, 2)
	hidden.CFrame = place * CFrame.new(0, 3 * unit, 0)
	hidden.Parent = model
	if withRoot then
		local root = Instance.new("Part")
		root.Name = "Point_Root"
		root.Size = Vector3.new(0.05, 0.05, 0.05)
		root.CFrame = place
		root.Parent = model
	end
	return model
end

-- Vor dem ersten require (der Lader liest Assets.Agents beim Laden)
local PLACE = CFrame.new(40, 12, -25)
suit("Viper", PLACE, 1, true).Parent = folder
suit("Hawk", CFrame.new(-3, 7, 9), 1, false).Parent = folder -- ohne Point_Root: Boden = tiefster Punkt
suit("Bastion", CFrame.new(0, 100, 0), 100, true).Parent = folder -- in Zentimetern importiert
suit("Agent", PLACE, 1, true).Parent = folder -- kein Agent
local empty = Instance.new("Model")
empty.Name = "Ghost"
local invisible = Instance.new("Part", empty)
invisible.Transparency = 1
empty.Parent = folder

SIM.IsStudio = true -- Studio: Bericht im Output
local AgentModels = require("AgentModels")
SIM.IsStudio = false
local AgentBody = require("AgentBody")
local AgentConfig = require("AgentConfig")

-- ---------- Laden ----------
local report = AgentModels.AssetReport()
local function messages(entry)
	return entry and (table.concat(entry.Errors, "; ") .. " | " .. table.concat(entry.Warnings, "; ")) or "kein Bericht"
end
check(report.Viper and report.Viper.Loaded and #report.Viper.Errors == 0 and #report.Viper.Warnings == 0,
	"Viper_3 lädt ohne Meldungen: " .. messages(report.Viper))
check(report.Hawk and report.Hawk.Loaded and #report.Hawk.Warnings == 0, "ohne Point_Root: lädt " .. messages(report.Hawk))
check(report.Bastion and report.Bastion.Loaded and hasText(report.Bastion.Warnings, "Einheit"),
	"falsche Einheit: lädt, Hinweis: " .. messages(report.Bastion))
check(report.Agent and not report.Agent.Loaded and hasText(report.Agent.Errors, "unbekannter Name"),
	"falscher Name gemeldet")
check(report.Ghost and not report.Ghost.Loaded and hasText(report.Ghost.Errors, "keine sichtbaren Teile"),
	"Modell ohne sichtbare Teile gemeldet")
check(AgentModels.HasAsset("Viper") and not AgentModels.HasAsset("Ghost") and not AgentModels.HasAsset("Mender")
	and not AgentModels.HasAsset(nil), "HasAsset")
local pieces = AgentModels.PiecesOf("Viper")
local count = 0
for name, bodyName in pieces or {} do
	count += 1
	check(bodyName == ownerOf(name), name .. " gehört zu " .. ownerOf(name) .. " (" .. tostring(bodyName) .. ")")
end
check(count == #SUIT, "alle Teile geladen (" .. count .. "), unsichtbares Hilfsteil und Marker nicht")

-- ---------- An einem Körper: jedes Teil genau wie im Modell ----------
local function restBody(where)
	local body = Instance.new("Model")
	local parts = {}
	for _, name in AgentModels.BodyParts do
		local rest = AgentModels.Body[name]
		local part = Instance.new("Part")
		part.Name = name
		part.Size = rest.Size
		part.CFrame = where * rest.CFrame
		part.Parent = body
		parts[name] = part
	end
	return body, parts
end
local function byName(created)
	local list = {}
	for _, part in created or {} do
		list[part.Name] = part
	end
	return list
end

local where = CFrame.new(-7, 3, 18) * CFrame.Angles(0, 0.8, 0) -- irgendwo und gedreht
local body, parts = restBody(where)
local created = AgentModels.Attach(body, parts, "Viper", true)
local holder = body:FindFirstChild(AgentModels.ModelName)
check(created ~= nil and #created == #SUIT and holder ~= nil and holder:GetAttribute("AgentGear"),
	"alle Teile im Untermodell " .. AgentModels.ModelName)
local placed = byName(created)
for i, def in SUIT do
	local part = placed[def[1]]
	check(part ~= nil and part.Parent == holder, def[1] .. " da")
	if part then
		local relative = where:ToObjectSpace(part.CFrame)
		local rotation = def[1] == "LeftUpperArm_Suit" and TILT or CFrame.new()
		check(near(relative.Position, def[3]) and near(part.Size, def[2])
			and relative.RightVector:Dot(rotation.RightVector) > 0.9999 and relative.UpVector:Dot(rotation.UpVector) > 0.9999,
			def[1] .. " sitzt, liegt und ist so groß wie im Modell (" .. tostring(relative.Position) .. ", " .. tostring(part.Size) .. ")")
		check(part.Color == Color3.fromRGB(10 + i, 200, 30) and part.Material == Enum.Material.Fabric
			and part.TextureID == "rbxassetid://" .. i and part:FindFirstChildOfClass("SurfaceAppearance") ~= nil,
			def[1] .. ": Farbe, Material und Textur wie im Modell")
		check(part:FindFirstChildWhichIsA("ValueBase") == nil, def[1] .. ": ohne Werte der Roblox-Skalierung")
		local weld = part:FindFirstChildOfClass("WeldConstraint")
		check(weld ~= nil and weld.Part0 == parts[ownerOf(def[1])] and weld.Part1 == part,
			def[1] .. " an " .. ownerOf(def[1]) .. " geschweißt")
		check(part.CanQuery == false and part.CanCollide == false and part.CanTouch == false and part.Massless
			and not part.Anchored and part:GetAttribute("AgentGear"), def[1] .. ": nie Trefferzone, bewegt sich mit")
	end
end
for name, part in parts do
	check(part.Transparency == 1, name .. ": Spielkörper unsichtbar (Trefferzone)")
end
-- Arme liegen am Oberkörper an (keine Lücke in Ruhelage)
local torso, arm = placed.UpperTorso_Suit, placed.RightUpperArm_Suit
check(torso and arm and near(where:ToObjectSpace(torso.CFrame).Position.X + torso.Size.X / 2,
	where:ToObjectSpace(arm.CFrame).Position.X - arm.Size.X / 2), "rechter Arm liegt am Oberkörper an")

-- Ohne Point_Root genauso (Boden = tiefster Punkt, Mitte = Rumpf)
local hawkBody, hawkParts = restBody(CFrame.new())
local hawk = byName(AgentModels.Attach(hawkBody, hawkParts, "Hawk", true))
for _, def in SUIT do
	check(hawk[def[1]] and near(hawk[def[1]].Position, def[3]), "ohne Point_Root: " .. def[1] .. " wie im Modell")
end
-- Falsche Einheit: auf die Höhe des Spielkörpers gebracht, Proportionen bleiben
local bastionBody, bastionParts = restBody(CFrame.new())
local bastion = byName(AgentModels.Attach(bastionBody, bastionParts, "Bastion", true))
local factor = 5.1 / 5.45 -- Modell ist 5,45 hoch (Haare oben)
check(bastion.Head_Suit and near(bastion.Head_Suit.Size, SUIT[1][2] * factor)
	and near(bastion.Head_Suit.Position, SUIT[1][3] * factor), "falsche Einheit: skaliert, Proportionen bleiben")
-- Ohne Modell: nichts angehängt, Körper bleibt
local plainBody, plainParts = restBody(CFrame.new())
check(AgentModels.Attach(plainBody, plainParts, "Mender", true) == nil and plainParts.Head.Transparency == 0,
	"Agent ohne Modell: nichts angehängt")

-- ---------- Neu laden (z.B. in Studio während des Spiels) ----------
local changed = {}
AgentModels.OnChanged(function(name)
	changed[name] = true
end)
folder.Bastion.Name = "Mender"
step(0.1)
check(changed.Bastion and changed.Mender and AgentModels.HasAsset("Mender") and not AgentModels.HasAsset("Bastion"),
	"umbenannt: unter dem neuen Namen geladen")
folder.Mender:Destroy()
step(0.1)
check(not AgentModels.HasAsset("Mender"), "entfernt: kein Modell mehr")
changed = {}
local backpack = Instance.new("Part") -- Teil dazu (ohne Körperteil-Namen, hinten am Rumpf)
backpack.Name = "Backpack"
backpack.Size = Vector3.new(1, 1.2, 0.5)
backpack.CFrame = folder.Hawk.UpperTorso_Suit.CFrame * CFrame.new(0, 0, 0.65)
backpack.Parent = folder.Hawk
step(0.1)
check(changed.Hawk and AgentModels.PiecesOf("Hawk").Backpack == "UpperTorso", "Teil dazu: neu geladen, hängt am Rumpf")

-- ---------- Menü-Figur ----------
local AgentFigure = require("AgentFigure")
local primary = Color3.fromRGB(40, 60, 50)
local figure = AgentFigure.Build(AgentConfig.Get("Viper"), primary, Color3.new(1, 1, 1))
local model = figure:FindFirstChild(AgentModels.ModelName)
local visible = 0
for _, part in figure:GetChildren() do
	if part:IsA("BasePart") and AgentModels.Body[part.Name] and part.Transparency < 1 then
		visible += 1
	end
end
check(model ~= nil and #model:GetChildren() == #SUIT and visible == 0, "Figur: nur das Modell zu sehen")
for _, part in figure:GetDescendants() do
	if part:IsA("BasePart") and not part.Anchored then
		check(false, "Figur: " .. part.Name .. " verankert")
	end
end
local hand = model and model:FindFirstChild("RightHand_Suit")
check(hand and hand.Position.Z < -1 and hand.Position.Y > 2.8 and near(figure.RightHand.CFrame:ToObjectSpace(hand.CFrame).Position,
	SUIT[10][3] - AgentModels.Body.RightHand.CFrame.Position), "rechte Hand des Modells mit dem Arm gehoben")
check(model and near(model.Head_Suit.Position, SUIT[1][3]), "Kopf des Modells wie im Modell")
local standard = AgentFigure.Build(AgentConfig.Get("Mender"), primary, Color3.new(1, 1, 1))
local face = standard.Head:FindFirstChildOfClass("Decal")
check(standard:FindFirstChild(AgentModels.ModelName) == nil and standard.Head.Transparency == 0 and face ~= nil
	and face.Transparency == 0, "ohne Modell: Standard-Figur mit Gesicht")

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
local worn = character and character:FindFirstChild(AgentModels.ModelName)
check(worn ~= nil and worn:FindFirstChild("Head_Suit") ~= nil and character:GetAttribute("AgentLook") == "Charakter"
	and AgentBody.IsDressed(character, "Viper"), "Spieler als VIPER trägt das Modell")
alice:SetAttribute("Agent", "Ghost")
step(0.1)
check(character:GetAttribute("AgentLook") == "Standard" and character:FindFirstChild(AgentModels.ModelName) == nil
	and character.Head.Transparency == 0, "Wechsel im Hub auf einen Agenten ohne Modell: Standard-Look")
local BotService = require("BotService")
local botTemplate
task.spawn(function()
	botTemplate = BotService.__rigTemplate(AgentConfig.Get("Viper"))
end)
step(1)
local botModel = botTemplate and botTemplate:FindFirstChild(AgentModels.ModelName)
check(botModel ~= nil and botModel:FindFirstChild("Head_Suit") ~= nil, "Bot als VIPER trägt das Modell")

if failures == 0 then
	print("Agenten-Modelle: alles in Ordnung")
end

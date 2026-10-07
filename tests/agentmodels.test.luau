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
check(AgentModels.PartCount("Viper") == #SUIT, "alle Teile geladen (" .. AgentModels.PartCount("Viper")
	.. "), unsichtbares Hilfsteil und Marker nicht")

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
local function byName(holder)
	local list = {}
	for _, part in holder and holder:GetChildren() or {} do
		list[part.Name] = part
	end
	return list
end

local where = CFrame.new(-7, 3, 18) * CFrame.Angles(0, 0.8, 0) -- irgendwo und gedreht
local body, parts = restBody(where)
local holder = AgentModels.Attach(body, parts, "Viper", true)
local function modelParts(model)
	return model and #model:GetChildren() or 0
end
check(holder ~= nil and holder == body:FindFirstChild(AgentModels.ModelName) and modelParts(holder) == #SUIT
	and holder:GetAttribute("AgentGear"), "alle Teile im Untermodell " .. AgentModels.ModelName)
local placed = byName(holder)
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
local backpackBody, backpackParts = restBody(CFrame.new())
local withBackpack = byName(AgentModels.Attach(backpackBody, backpackParts, "Hawk", true))
check(changed.Hawk and withBackpack.Backpack and withBackpack.Backpack:FindFirstChildOfClass("WeldConstraint").Part0
	== backpackParts.UpperTorso, "Teil dazu: neu geladen, hängt am Rumpf")

-- ---------- Importiertes Modell mit Bones (gehäutetes Mesh), ohne Rig ----------
-- Wie nach Import 3D: die Bones hängen an einem unsichtbaren Teil, das Mesh liegt daneben. Das Modell bleibt
-- zusammen (Bones bei ihrem Teil, im selben Modell wie das Mesh) und hängt als Ganzes am Körper; der Output sagt,
-- wie es ein Rig wird.
local skinnedSource = Instance.new("Model")
skinnedSource.Name = "Blaze"
local armature = Instance.new("Part")
armature.Name = "Armature"
armature.Transparency = 1
armature.Size = Vector3.new(0.2, 0.2, 0.2)
armature.CFrame = CFrame.new(5, 2.2, 5)
armature.Parent = skinnedSource
local hips = Instance.new("Bone")
hips.Name = "Hips"
hips.Parent = armature
local spine = Instance.new("Bone")
spine.Name = "Spine"
spine.CFrame = CFrame.new(0, 0.6, 0)
spine.Parent = hips
local skin = Instance.new("MeshPart")
skin.Name = "Body"
skin.Size = Vector3.new(2.2, 5.2, 1)
skin.CFrame = CFrame.new(5, 2.6, 5)
skin.TextureID = "rbxassetid://99"
skin.Parent = skinnedSource
skinnedSource.Parent = folder
step(0.1)
check(report.Blaze and report.Blaze.Loaded and hasText(report.Blaze.Warnings, "Avatar Setup"),
	"Modell mit Bones ohne Rig: lädt, Hinweis auf das Avatar-Setup: " .. messages(report.Blaze))
local skinBody, skinParts = restBody(CFrame.new())
local skinHolder = AgentModels.Attach(skinBody, skinParts, "Blaze", true)
local skinArmature = skinHolder and skinHolder:FindFirstChild("Armature")
check(skinArmature ~= nil and skinArmature.Transparency == 1 and skinArmature:FindFirstChild("Hips") ~= nil
	and skinArmature.Hips:FindFirstChild("Spine") ~= nil, "Bones bleiben bei ihrem Teil im Modell")
check(skinHolder and skinHolder.Body and skinHolder.Body.TextureID == "rbxassetid://99"
	and skinHolder.Body:FindFirstChildOfClass("WeldConstraint").Part0 == skinParts.LowerTorso
	and skinArmature and skinArmature:FindFirstChildOfClass("WeldConstraint").Part0 == skinParts.LowerTorso,
	"Mesh und Bones hängen zusammen am Unterkörper")
check(skinHolder and near(skinHolder.Body.Position, Vector3.new(0, 2.6, 0)), "Mesh steht auf dem Boden")

-- ---------- Modell ohne Rig und ohne Körperteil-Namen (z.B. aus Meshy) ----------
-- Bleibt ein Stück, genau wie gebaut, fest am Körper: nichts wird zerlegt oder einem falschen Körperteil zugeordnet
local meshy = Instance.new("Model")
meshy.Name = "Trapper"
local MESHY = { { "Mesh_0", Vector3.new(1.6, 2.6, 1), Vector3.new(0, 3.3, 0) },
	{ "Mesh_1", Vector3.new(1.6, 2.2, 1), Vector3.new(0, 1.1, 0) },
	{ "Mesh_2", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 4.6, 0) } } -- (Mitte = Mitte des Modells, Boden = tiefster Punkt)
for _, def in MESHY do
	local part = Instance.new("MeshPart")
	part.Name = def[1]
	part.Size = def[2]
	part.CFrame = CFrame.new(-20, 3, 7) * CFrame.new(def[3])
	part.Parent = meshy
end
meshy.Parent = folder
step(0.1)
check(report.Trapper and report.Trapper.Loaded and hasText(report.Trapper.Warnings, "als Ganzes")
	and string.find(report.Trapper.Info or "", "Humanoid 0", 1, true) ~= nil,
	"Modell ohne Namen: als Ganzes geladen, Hinweis und Aufbau im Bericht: " .. messages(report.Trapper))
local meshyBody, meshyParts = restBody(where)
local meshyHolder = byName(AgentModels.Attach(meshyBody, meshyParts, "Trapper", true))
for _, def in MESHY do
	local part = meshyHolder[def[1]]
	local weldOf = part and part:FindFirstChildOfClass("WeldConstraint")
	check(part and near(where:ToObjectSpace(part.CFrame).Position, def[3]) and weldOf
		and weldOf.Part0 == meshyParts.LowerTorso, def[1] .. ": genau wie gebaut, alle am selben Teil")
end
-- am Charakter: fest am HumanoidRootPart
local character0 = SIM.MakeRig("Probe")
character0:PivotTo(CFrame.new(3, 3, 3))
local probeParts = { Head = character0.Head, UpperTorso = character0.UpperTorso }
local probeHolder = byName(AgentModels.Attach(character0, probeParts, "Trapper", true))
check(probeHolder.Mesh_0 and probeHolder.Mesh_0:FindFirstChildOfClass("WeldConstraint").Part0 == character0.HumanoidRootPart
	and probeHolder.Mesh_1 ~= nil, "am Charakter: alles fest am HumanoidRootPart (auch ohne Beine im Körper)")

-- ---------- Zwei Modelle mit demselben Namen ----------
local twinA = meshy:Clone()
twinA.Name = "Volt"
twinA.Parent = folder
local twinB = meshy:Clone()
twinB.Name = "Volt"
twinB.Parent = folder
step(0.1)
check(report.Volt and hasText(report.Volt.Warnings, "2 Modelle heißen Volt"), "doppelter Name gemeldet: " .. messages(report.Volt))

-- ---------- Rig ohne Gelenke ----------
-- Humanoid und HumanoidRootPart, aber keine Motor6D: bleibt ein Rig, jedes Teil hängt fest am HumanoidRootPart
local stiff = Instance.new("Model")
stiff.Name = "Aegis"
Instance.new("Humanoid", stiff)
local stiffRoot = Instance.new("Part")
stiffRoot.Name = "HumanoidRootPart"
stiffRoot.Transparency = 1
stiffRoot.Size = Vector3.new(2, 2, 1)
stiffRoot.CFrame = CFrame.new(0, 3, 0)
stiffRoot.Parent = stiff
local stiffBody = Instance.new("MeshPart")
stiffBody.Name = "Mesh"
stiffBody.Size = Vector3.new(2, 5, 1)
stiffBody.CFrame = CFrame.new(0, 2.5, 0)
stiffBody.Parent = stiff
stiff.Parent = folder
step(0.1)
check(report.Aegis and report.Aegis.Loaded and hasText(report.Aegis.Warnings, "ohne Gelenke"),
	"Rig ohne Gelenke: lädt, Hinweis: " .. messages(report.Aegis))
local stiffBodyModel, stiffParts = restBody(CFrame.new())
local stiffHolder = AgentModels.Attach(stiffBodyModel, stiffParts, "Aegis", true)
local held = stiffHolder and stiffHolder:FindFirstChild("Mesh")
local holdWeld = held and held:FindFirstChildOfClass("WeldConstraint")
check(holdWeld ~= nil and holdWeld.Part0 == stiffHolder.HumanoidRootPart and near(held.Position, Vector3.new(0, 2.5, 0)),
	"Teil ohne Gelenk hängt am HumanoidRootPart, steht auf dem Boden")

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
check(model ~= nil and modelParts(model) == #SUIT and visible == 0, "Figur: Modell zu sehen, Spielkörper nicht")
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

-- ---------- Spieler und Bots: das Modell ist selbst der Charakter ----------
-- Kein Roblox-Standardkörper: der geladene Körper wird durch das Modell ersetzt (wie ein StarterCharacter). Das Modell
-- steht genau wie gebaut an einem unsichtbaren HumanoidRootPart, seine sichtbaren Teile sind die Trefferzone; dazu
-- unsichtbare Hilfsteile Head (Kopfschüsse) und RightHand (Waffe).
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
check(character ~= nil and character == alice.Character and AgentModels.IsModelCharacter(character)
	and character.Parent == workspace, "Spieler als VIPER: das Modell ist der Charakter")
local function standardParts(model)
	local count = 0
	for _, name in AgentModels.BodyParts do
		local part = model:FindFirstChild(name)
		count += (part and part:IsA("BasePart") and name ~= "Head" and name ~= "RightHand") and 1 or 0
	end
	return count
end
check(character and standardParts(character) == 0, "kein Roblox-Standardkörper im Charakter")
local worn = character and character:FindFirstChild(AgentModels.ModelName)
check(worn ~= nil and worn:IsA("Folder") and worn:FindFirstChild("Head_Suit") ~= nil, "Teile des Modells im Charakter")
local root = character.HumanoidRootPart
local humanoid = character:FindFirstChildOfClass("Humanoid")
check(humanoid ~= nil and humanoid.MaxHealth == AgentConfig.Get("Viper").Health and character:GetAttribute("Agent") == "Viper",
	"Leben und Agent gesetzt")
local ground = root.CFrame * CFrame.new(0, -(root.Size.Y / 2 + humanoid.HipHeight), 0)
for _, def in SUIT do
	local part = worn and worn:FindFirstChild(def[1])
	check(part and near(ground:ToObjectSpace(part.CFrame).Position, def[3]) and part.CanQuery
		and part:FindFirstChildOfClass("WeldConstraint").Part0 == root, def[1] .. ": genau wie gebaut, Trefferzone")
end
local head, hand = character:FindFirstChild("Head"), character:FindFirstChild("RightHand")
check(head and head.Transparency == 1 and head.CanQuery and near(ground:ToObjectSpace(head.CFrame).Position, SUIT[1][3])
	and head.Size.X > SUIT[1][2].X, "unsichtbare Kopf-Trefferzone um den Kopf des Modells")
check(hand and hand.Transparency == 1 and hand:FindFirstChild("RightGripAttachment"), "unsichtbare rechte Hand für die Waffe")
-- Wechsel im Hub auf einen Agenten ohne Modell: neu gespawnt mit dem Standard-Look, an derselben Stelle
local before = root.Position
alice:SetAttribute("Agent", "Ghost")
step(0.5)
local standard = alice.Character
check(standard ~= character and not AgentModels.IsModelCharacter(standard) and standard:GetAttribute("AgentLook") == "Standard"
	and (standard.HumanoidRootPart.Position - before).Magnitude < 0.5, "Wechsel auf Agent ohne Modell: Standard-Look")
alice:SetAttribute("Agent", "Viper")
step(0.5)
check(AgentModels.IsModelCharacter(alice.Character), "zurück zu VIPER: wieder das Modell")
-- Bots: das Modell ist ihr Körper
local BotService = require("BotService")
local botTemplate
task.spawn(function()
	botTemplate = BotService.__rigTemplate(AgentConfig.Get("Viper"))
end)
step(1)
check(botTemplate ~= nil and AgentModels.IsModelCharacter(botTemplate) and botTemplate:FindFirstChild("Head") ~= nil
	and botTemplate:FindFirstChildOfClass("Humanoid") ~= nil, "Bot als VIPER: das Modell ist der Körper")

if failures == 0 then
	print("Agenten-Modelle: alles in Ordnung")
end

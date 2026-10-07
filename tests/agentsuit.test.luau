-- Ganzer Charakter aus Blender ohne Humanoid und ohne mitgelieferten Körper (wie Viper_3.glb): 15 starre Teile
-- <Körperteil>_Suit, auf den schlanken Spielkörper gebaut, dazu Point_Root. Maße und Lage hier genau wie in dieser
-- Datei (nach dem Import in Roblox: Blick nach -Z). Das Spiel muss jedes Teil genau dort an den Spielkörper hängen,
-- wo es im Modell sitzt: Arme direkt am Oberkörper, Kapuze über dem Kopf, nichts verschoben oder verzerrt.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, eps)
	return (a - b).Magnitude < (eps or 1e-3)
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder", ReplicatedStorage)
assets.Name = "Assets"
local folder = assets:FindFirstChild("Agents") or Instance.new("Folder", assets)
folder.Name = "Agents"

-- { Name, Größe, Mitte } aus Viper_3.glb
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
}
-- irgendwo in der Welt importiert (Lage egal, Point_Root zählt)
local PLACE = CFrame.new(40, 12, -25)
local source = Instance.new("Model")
source.Name = "Viper"
for _, def in SUIT do
	local part = Instance.new("MeshPart")
	part.Name = def[1]
	part.Size = def[2]
	part.CFrame = PLACE * CFrame.new(def[3])
	part.Color = Color3.new(1, 1, 1) -- wie nach dem Import
	part.TextureID = "rbxassetid://1" -- Textur aus der Datei
	part.Parent = source
end
local root = Instance.new("Part")
root.Name = "Point_Root"
root.Size = Vector3.new(0.05, 0.05, 0.05)
root.CFrame = PLACE
root.Parent = source
source.Parent = folder

local AgentModels = require("AgentModels")
local report = AgentModels.AssetReport().Viper
check(report and report.Loaded and report.Character and #report.Errors == 0 and #report.Warnings == 0,
	"Viper_3: als ganzer Charakter geladen, ohne Meldungen: "
	.. (report and (table.concat(report.Errors, "; ") .. " | " .. table.concat(report.Warnings, "; ")) or "kein Bericht"))

-- Spielkörper in Ruhelage, irgendwo und gedreht
local where = CFrame.new(-7, 3, 18) * CFrame.Angles(0, 0.8, 0)
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
local created = AgentModels.Attach(body, parts, "Viper", Color3.new(0.2, 0.3, 0.2), Color3.new(0.4, 0.6, 0.4), true)
check(created ~= nil and #created == 15, "15 Teile angehängt (" .. tostring(created and #created) .. ")")
local byName = {}
for _, part in created or {} do
	byName[part.Name] = part
end
-- Jedes Teil sitzt genau wie im Modell (relativ zum Boden zwischen den Füßen), gleiche Größe, nicht gedreht
for _, def in SUIT do
	local part = byName[def[1]]
	check(part ~= nil, def[1] .. " da")
	if part then
		local relative = where:ToObjectSpace(part.CFrame)
		check(near(relative.Position, def[3]) and near(part.Size, def[2])
			and relative.RightVector:Dot(Vector3.new(1, 0, 0)) > 0.9999 and relative.UpVector:Dot(Vector3.new(0, 1, 0)) > 0.9999,
			def[1] .. " sitzt wie im Modell (" .. tostring(relative.Position) .. ", Größe " .. tostring(part.Size) .. ")")
		check(part.Color == Color3.new(1, 1, 1), def[1] .. ": Textur nicht grau übermalt")
	end
end
-- Arme direkt am Oberkörper (keine Lücke in Ruhelage)
local torso, arm = byName.UpperTorso_Suit, byName.LeftUpperArm_Suit
if torso and arm then
	local torsoEdge = where:ToObjectSpace(torso.CFrame).Position.X - torso.Size.X / 2
	local armInner = where:ToObjectSpace(arm.CFrame).Position.X + arm.Size.X / 2
	check(math.abs(torsoEdge - armInner) < 1e-3, string.format("linker Arm liegt am Oberkörper an (Lücke %.3f)",
		torsoEdge - armInner))
end
-- Spielkörper komplett unsichtbar, Modellteile nie Trefferzone
for name, part in parts do
	check(part.Transparency == 1, name .. ": Spielkörper unsichtbar")
end
for _, part in created or {} do
	local weld = part:FindFirstChildOfClass("WeldConstraint")
	check(part.CanQuery == false and part.CanCollide == false and weld ~= nil and weld.Part0 ~= nil and weld.Part0.Parent == body,
		part.Name .. ": nie Trefferzone, am Spielkörper angeschweißt")
end

if failures == 0 then
	print("Viper_3 (Teile ohne Körper): alles in Ordnung")
end

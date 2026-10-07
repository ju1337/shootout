-- Gibt die Vorlage für Agenten-Modelle aus (für tools/agent_templates.py, läuft in der Test-Engine): den
-- Agenten-Körper aus dem Spiel in Ruhelage (AgentModels.Body; die Teile heißen wie die Körperteile) und eine
-- Beispiel-Ausrüstung (Kapuze, Visier, Maske, Weste, Schulterpolster, Gürtel – die frühere Quader-Ausrüstung) mit Namen
-- nach der Spezifikation (docs/agenten-modelle.md), in den Farben von VIPER.
-- Zeilen: PART <Teil> <Form> <12 CFrame-Zahlen> <3 Größe> <r g b> <Material> <Transparenz>
local AgentModels = require("AgentModels")
local Cosmetics = require("Cosmetics")

local BODY = Color3.fromRGB(196, 198, 204) -- Körper hellgrau: nur Bezug, wird nicht umgefärbt
local MASK = Color3.fromRGB(52, 54, 58)
local BELT = Color3.fromRGB(30, 30, 30)

-- Beispiel-Ausrüstung relativ zum Körperteil: { Name in der Vorlage, Körperteil, Größe (× Teilgröße),
-- Mitte (× Teilgröße, im Teil), Farbe, Material }. Kopf: vorne = -Z, die Augen liegen etwas über der Mitte.
local GEAR = {
	-- Kapuze als offener Rahmen um den Kopf: oben, hinten, links, rechts – das Gesicht bleibt frei
	{ "Head_HoodTop_Primary", "Head", Vector3.new(1.16, 0.16, 1.1), Vector3.new(0, 0.56, 0.05), "Primary", Enum.Material.Fabric },
	{ "Head_HoodBack_Primary", "Head", Vector3.new(1.16, 1.02, 0.16), Vector3.new(0, 0.07, 0.57), "Primary", Enum.Material.Fabric },
	{ "Head_HoodLeft_Primary", "Head", Vector3.new(0.14, 0.98, 1.08), Vector3.new(-0.56, 0.08, 0.04), "Primary",
		Enum.Material.Fabric },
	{ "Head_HoodRight_Primary", "Head", Vector3.new(0.14, 0.98, 1.08), Vector3.new(0.56, 0.08, 0.04), "Primary",
		Enum.Material.Fabric },
	-- Visier über den Augen, Maske über Mund und Kinn
	{ "Head_Visor_Glass", "Head", Vector3.new(0.94, 0.22, 0.08), Vector3.new(0, 0.16, -0.5), "Visor", Enum.Material.SmoothPlastic },
	{ "Head_Mask", "Head", Vector3.new(0.84, 0.36, 0.07), Vector3.new(0, -0.24, -0.49), "Mask", Enum.Material.Fabric },
	{ "UpperTorso_Vest_Accent", "UpperTorso", Vector3.new(1.06, 0.7, 1.15), Vector3.new(0, 0.1, 0), "Accent", Enum.Material.Metal },
	{ "LeftUpperArm_Pad_Accent", "LeftUpperArm", Vector3.new(1.18, 0.28, 1.18), Vector3.new(0, 0.42, 0), "Accent",
		Enum.Material.Metal },
	{ "RightUpperArm_Pad_Accent", "RightUpperArm", Vector3.new(1.18, 0.28, 1.18), Vector3.new(0, 0.42, 0), "Accent",
		Enum.Material.Metal },
	{ "LowerTorso_Belt", "LowerTorso", Vector3.new(1.04, 0.75, 1.06), Vector3.new(0, 0, 0), "Belt", Enum.Material.SmoothPlastic },
}

local function numbers(...)
	local list = {}
	for _, value in { ... } do
		table.insert(list, string.format("%.6f", value))
	end
	return table.concat(list, "\t")
end

local function enumName(value)
	return string.match(tostring(value), "[^%.]+$")
end

local function emit(name, cframe, size, color, material, transparency)
	print(table.concat({ "PART", name, "Block", numbers(cframe:GetComponents()), numbers(size.X, size.Y, size.Z),
		numbers(color.R * 255, color.G * 255, color.B * 255), enumName(material), string.format("%.3f", transparency) },
		"\t"))
end

for _, name in AgentModels.BodyParts do
	local body = AgentModels.Body[name]
	emit(name, body.CFrame, body.Size, BODY, Enum.Material.SmoothPlastic, 0)
end
local primary, accent = Cosmetics.AgentColors(nil, "Viper")
local colors = { Primary = primary, Accent = accent, Visor = AgentModels.VisorColor(accent), Mask = MASK, Belt = BELT }
for _, def in GEAR do
	local body = AgentModels.Body[def[2]]
	emit(def[1], body.CFrame * CFrame.new(body.Size * def[4]), body.Size * def[3], colors[def[5]], def[6], 0)
end

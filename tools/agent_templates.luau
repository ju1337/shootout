-- Gibt die Vorlage für Agenten-Modelle aus (für tools/agent_templates.py, läuft in der Test-Engine): den
-- Agenten-Körper aus dem Spiel in Ruhelage (AgentModels.Body; die Teile heißen wie die Körperteile) und die heutige
-- Quader-Ausrüstung (AgentBody) mit Namen nach der Spezifikation (docs/agenten-modelle.md), in den Farben von VIPER.
-- Zeilen: PART <Teil> <Form> <12 CFrame-Zahlen> <3 Größe> <r g b> <Material> <Transparenz>
local AgentModels = require("AgentModels")
local AgentBody = require("AgentBody")
local Cosmetics = require("Cosmetics")

local BODY = Color3.fromRGB(196, 198, 204) -- Körper hellgrau: nur Bezug, wird nicht umgefärbt

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

local rig = Instance.new("Model")
for _, name in AgentModels.BodyParts do
	local body = AgentModels.Body[name]
	local part = Instance.new("Part")
	part.Name = name
	part.Size = body.Size
	part.CFrame = body.CFrame
	part.Color = BODY
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = rig
end
local primary, accent = Cosmetics.AgentColors(nil, "Viper")
AgentBody.Dress(rig, primary, accent)

local function emit(name, part)
	local color = part.Color
	print(table.concat({ "PART", name, part.Shape and enumName(part.Shape) or "Block", numbers(part.CFrame:GetComponents()),
		numbers(part.Size.X, part.Size.Y, part.Size.Z), numbers(color.R * 255, color.G * 255, color.B * 255),
		enumName(part.Material), string.format("%.3f", part.Transparency) }, "\t"))
end
for _, name in AgentModels.BodyParts do
	emit(name, rig[name])
end
for _, gearName in AgentBody.GearNames do
	emit(AgentBody.SpecNames[gearName], rig[gearName])
end

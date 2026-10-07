-- Gibt die Fahrzeuge aus dem Spiel (VehicleService, heutige Quader-Optik) für tools/asset_templates.py aus: jedes
-- Fahrzeug in Ruhelage (Gleitkugeln auf dem Boden, Boden = y 0), Mitte des Rumpfs über x = z = 0, Blick nach -Z.
-- Zeilen: PART <Fahrzeug> <Teil> <Klasse> <Form> <12 CFrame-Zahlen> <3 Größe> <r g b> <Material> <Transparenz>
local ExtinctionConfig = require("ExtinctionConfig")
local VehicleService = require("VehicleService")

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

local ids = {}
for id in ExtinctionConfig.Vehicles do
	table.insert(ids, id)
end
table.sort(ids)

for _, id in ids do
	local model = VehicleService.Build(id, ExtinctionConfig.Vehicles[id], CFrame.new(0, 20, 0))
	-- Boden = Unterkante der Gleitkugeln
	local ground = math.huge
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Skid" then
			ground = math.min(ground, part.Position.Y - part.Size.Y / 2)
		end
	end
	local shift = CFrame.new(0, -ground, 0)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local cframe = shift * part.CFrame
			local color = part.Color
			print(table.concat({ "PART", id, part.Name, part.ClassName, enumName(part.Shape), numbers(cframe:GetComponents()),
				numbers(part.Size.X, part.Size.Y, part.Size.Z), numbers(color.R * 255, color.G * 255, color.B * 255),
				enumName(part.Material), string.format("%.3f", part.Transparency) }, "\t"))
		end
	end
end

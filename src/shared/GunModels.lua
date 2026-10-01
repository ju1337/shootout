-- GunModels (ModuleScript)
-- Baut einfache Waffenmodelle aus Parts. Lauf zeigt nach -Z, "Handle" ist der Griff.
-- Wird für die Waffe vor der eigenen Kamera (Client) und in der Hand der anderen (Server) benutzt.
-- skin (aus AgentConfig.Skins) färbt die markierten Teile um (Gold, Diamant).

local GunModels = {}

local DARK = Color3.fromRGB(45, 45, 50)
local BLACK = Color3.fromRGB(20, 20, 22)
local WOOD = Color3.fromRGB(110, 75, 45)
local GOLD = Color3.fromRGB(190, 150, 60)
local OLIVE = Color3.fromRGB(70, 80, 55)
local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.Plastic

-- { Name, Größe, Position relativ zum Griff, Farbe, Material, vom Skin umgefärbt? }
local PARTS = {
	Rifle = {
		{ "Handle", Vector3.new(0.25, 0.5, 0.3), Vector3.new(0, -0.1, 0), BLACK, PLASTIC },
		{ "Body", Vector3.new(0.35, 0.45, 1.8), Vector3.new(0, 0.3, -0.35), DARK, METAL, true },
		{ "Barrel", Vector3.new(0.15, 0.15, 1.1), Vector3.new(0, 0.38, -1.8), BLACK, METAL },
		{ "Stock", Vector3.new(0.3, 0.5, 0.9), Vector3.new(0, 0.25, 0.95), WOOD, Enum.Material.Wood, true },
		{ "Magazine", Vector3.new(0.25, 0.6, 0.35), Vector3.new(0, -0.15, -0.65), BLACK, METAL },
		{ "Sight", Vector3.new(0.1, 0.2, 0.35), Vector3.new(0, 0.62, -0.4), BLACK, METAL },
	},
	SMG = {
		{ "Handle", Vector3.new(0.22, 0.5, 0.28), Vector3.new(0, -0.1, 0), BLACK, PLASTIC },
		{ "Body", Vector3.new(0.3, 0.4, 1.2), Vector3.new(0, 0.28, -0.2), OLIVE, METAL, true },
		{ "Barrel", Vector3.new(0.12, 0.12, 0.5), Vector3.new(0, 0.33, -1.05), BLACK, METAL },
		{ "Magazine", Vector3.new(0.2, 0.75, 0.25), Vector3.new(0, -0.2, -0.45), BLACK, METAL },
		{ "Stock", Vector3.new(0.15, 0.3, 0.6), Vector3.new(0, 0.25, 0.65), BLACK, METAL, true },
	},
	Shotgun = {
		{ "Handle", Vector3.new(0.25, 0.5, 0.3), Vector3.new(0, -0.1, 0), BLACK, PLASTIC },
		{ "Body", Vector3.new(0.35, 0.4, 1.2), Vector3.new(0, 0.28, -0.3), DARK, METAL, true },
		{ "Barrel", Vector3.new(0.2, 0.2, 1.6), Vector3.new(0, 0.42, -1.5), BLACK, METAL },
		{ "Pump", Vector3.new(0.3, 0.25, 0.6), Vector3.new(0, 0.18, -1.3), WOOD, Enum.Material.Wood },
		{ "Stock", Vector3.new(0.3, 0.5, 1.0), Vector3.new(0, 0.2, 1.0), WOOD, Enum.Material.Wood, true },
	},
	DMR = {
		{ "Handle", Vector3.new(0.25, 0.5, 0.3), Vector3.new(0, -0.1, 0), BLACK, PLASTIC },
		{ "Body", Vector3.new(0.32, 0.42, 2.0), Vector3.new(0, 0.3, -0.4), DARK, METAL, true },
		{ "Barrel", Vector3.new(0.14, 0.14, 1.4), Vector3.new(0, 0.36, -2.1), BLACK, METAL },
		{ "Scope", Vector3.new(0.22, 0.22, 0.9), Vector3.new(0, 0.68, -0.4), BLACK, METAL },
		{ "Magazine", Vector3.new(0.22, 0.45, 0.3), Vector3.new(0, -0.1, -0.6), BLACK, METAL },
		{ "Stock", Vector3.new(0.3, 0.5, 1.0), Vector3.new(0, 0.25, 1.0), DARK, METAL, true },
	},
	Pistol = {
		{ "Handle", Vector3.new(0.22, 0.55, 0.3), Vector3.new(0, -0.1, 0), BLACK, PLASTIC },
		{ "Slide", Vector3.new(0.25, 0.28, 0.95), Vector3.new(0, 0.28, -0.25), GOLD, METAL, true },
		{ "Barrel", Vector3.new(0.12, 0.12, 0.2), Vector3.new(0, 0.3, -0.8), BLACK, METAL },
	},
	Revolver = {
		{ "Handle", Vector3.new(0.22, 0.55, 0.3), Vector3.new(0, -0.1, 0), WOOD, Enum.Material.Wood },
		{ "Frame", Vector3.new(0.25, 0.3, 0.6), Vector3.new(0, 0.28, -0.15), DARK, METAL, true },
		{ "Cylinder", Vector3.new(0.32, 0.32, 0.35), Vector3.new(0, 0.28, -0.25), DARK, METAL, true },
		{ "Barrel", Vector3.new(0.14, 0.14, 0.75), Vector3.new(0, 0.33, -0.8), BLACK, METAL },
	},
}

-- Liefert ein Model mit PrimaryPart "Handle". Alle Parts sind verankert und ohne Kollision.
function GunModels.Build(weaponName, skin)
	local model = Instance.new("Model")
	model.Name = weaponName
	for _, def in PARTS[weaponName] do
		local part = Instance.new("Part")
		part.Name = def[1]
		part.Size = def[2]
		part.CFrame = CFrame.new(def[3])
		part.Color = def[4]
		part.Material = def[5]
		if skin and def[6] then
			part.Color = skin.Color
			part.Material = skin.Material
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.Parent = model
		if def[1] == "Handle" then
			model.PrimaryPart = part
		end
	end
	return model
end

-- Liefert ein Tool (für die Hand des Charakters): Parts sind per Weld am Handle befestigt.
function GunModels.BuildTool(weaponName, displayName, skin)
	local model = GunModels.Build(weaponName, skin)
	local tool = Instance.new("Tool")
	tool.Name = displayName
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.RequiresHandle = true
	tool:SetAttribute("Weapon", weaponName)

	local handle = model.PrimaryPart
	for _, part in model:GetChildren() do
		part.Anchored = false
		if part ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
		end
		part.Parent = tool
	end
	model:Destroy()
	return tool
end

return GunModels

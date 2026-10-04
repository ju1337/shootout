-- Gibt die Quader-Waffen samt Markern aus (für tools/weapon_templates.py, läuft in der Test-Engine).
-- Teilnamen folgen schon der Spezifikation (docs/waffen-modelle.md): Skin-Zonen mit "Skin", bewegte Teile mit
-- ihrer Animationsgruppe, Leuchtpunkte mit "Neon", Glas mit "Glass", der rote Punkt als "Reticle".
-- Zeilen: PART <Waffe> <Teil> <Form> <12 CFrame-Zahlen> <3 Größe> <r g b> <Material> <Transparenz>
--         POINT <Waffe> <Name> <x y z>
local GunModels = require("GunModels")

local function numbers(...)
	local list = {}
	for _, value in { ... } do
		table.insert(list, string.format("%.6f", value))
	end
	return table.concat(list, "\t")
end

local names = {}
for weaponName in GunModels.Info do
	table.insert(names, weaponName)
end
table.sort(names)

-- Skin-Zonen erkennen: mit einem Erkennungs-Skin bauen und schauen, welche Teile ihn annehmen
local PROBE = { Color = Color3.fromRGB(1, 2, 3), Material = Enum.Material.Plastic }

-- Name nach der Spezifikation aus Gruppe, Skin-Zone, Neon und Glas des Quader-Teils
local function specName(part, isSkin)
	local name = part.Name
	local group = part:GetAttribute("Group")
	local material = string.match(tostring(part.Material), "[^%.]+$")
	if name == "DotReticle" then
		return "Reticle"
	end
	if group and string.sub(name, 1, #group) ~= group then
		name = group .. "_" .. name
	end
	if material == "Neon" then
		name = "Neon_" .. name
	elseif material == "Glass" then
		name = "Glass_" .. name
	end
	if isSkin then
		name = "Skin_" .. name
	end
	return name
end

for _, weaponName in names do
	local info = GunModels.Info[weaponName]
	local model = GunModels.Build(weaponName)
	local probe = GunModels.Build(weaponName, PROBE)
	local groups, frontDot = {}, nil
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "Handle" then
			local probed = probe:FindFirstChild(part.Name)
			local isSkin = probed ~= nil and probed.Color == PROBE.Color
			local shape = "Block"
			if part.Shape == Enum.PartType.Cylinder then
				shape = "Cylinder"
			elseif part.Shape == Enum.PartType.Ball then
				shape = "Ball"
			end
			local c = part.CFrame
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
			print(table.concat({ "PART", weaponName, specName(part, isSkin), shape,
				numbers(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22),
				numbers(part.Size.X, part.Size.Y, part.Size.Z),
				numbers(part.Color.R * 255, part.Color.G * 255, part.Color.B * 255),
				string.match(tostring(part.Material), "[^%.]+$"), numbers(part.Transparency) }, "\t"))
			local group = part:GetAttribute("Group")
			if group then
				groups[group] = true
			end
			if part.Name == "FrontDot" then
				frontDot = part.Position
			end
		end
	end
	local function point(name, position)
		print(table.concat({ "POINT", weaponName, name, numbers(position.X, position.Y, position.Z) }, "\t"))
	end
	-- Visierlinie: hinten Kimme bzw. roter Punkt, vorne Korn bzw. ein Stück vor dem Rotpunkt
	local frontZ = frontDot and frontDot.Z or info.SightZ - 0.2
	point("Point_Grip", info.RightHand)
	point("Point_SightRear", Vector3.new(0, info.SightHeight, info.SightZ))
	point("Point_SightFront", Vector3.new(0, info.SightHeight, frontZ))
	point("Point_Muzzle", info.Muzzle)
	point("Point_Eject", info.Eject)
	point("Point_LeftHand", info.LeftHand)
	if info.LeftHandTP and (info.LeftHandTP - info.LeftHand).Magnitude > 1e-6 then
		point("Point_LeftHandTP", info.LeftHandTP)
	end
	if info.Stock then
		point("Point_Stock", info.Stock)
	end
	for group in groups do
		point("Pivot_" .. group, GunModels.GroupPivot(weaponName, group).Position)
	end
end

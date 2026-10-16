-- Skins auf allen Waffen: die importierten Waffen (assets/Weapons, mit Skins aus models/Skins wie im Spiel) haben eine
-- deckende Textur. Ein Farb-Skin tauscht sie an jeder Skin-Zone gegen die Farb-Grundtextur (Skins/Farbe, ohne ColorMap),
-- damit die Skin-Farbe zu sehen ist; ohne Skin bleibt die Original-Textur. Effekt-Skins (Drachengold, Splitterlicht,
-- Glücksrad) gehen auf jede Waffe und holen ihre Partikelbilder notfalls vom Sturmgewehr.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GunModels = require("GunModels")
local Cosmetics = require("Cosmetics")
local SkinEffects = require("SkinEffects")

local function skinZones(model)
	local zones = {}
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("Skin") then
			table.insert(zones, part)
		end
	end
	return zones
end

local lava = Cosmetics.Get("W_Lava")
local tested = 0
for _, source in ReplicatedStorage.Assets.Weapons:GetChildren() do
	local name = source.Name
	if not GunModels.HasAsset(name) then
		continue
	end
	local textured = false
	local skinFolder = source:FindFirstChild("Skins")
	for _, obj in source:GetDescendants() do
		if obj:IsA("SurfaceAppearance") and obj.ColorMap and not (skinFolder and obj:IsDescendantOf(skinFolder)) then
			textured = true
		end
	end
	if not textured then
		continue
	end
	tested += 1
	local farbe = source:FindFirstChild("Skins") and source.Skins:FindFirstChild(GunModels.ColorSkinFolder)
	check(farbe ~= nil, name .. ": texturierte Waffe ohne Skins/Farbe – Farb-Skins wären unsichtbar (tools/models/color_skins.py)")

	-- ohne Skin: Original-Textur
	for _, part in skinZones(GunModels.Build(name, nil)) do
		local sa = part:FindFirstChildOfClass("SurfaceAppearance")
		check(sa == nil or sa.ColorMap ~= nil, name .. ": ohne Skin fehlt die Original-Textur an " .. part.Name)
	end

	-- Farb-Skin: jede Skin-Zone in Skin-Farbe, keine deckende Textur mehr
	local zones = skinZones(GunModels.Build(name, lava))
	check(#zones > 0, name .. ": keine Skin-Zonen")
	for _, part in zones do
		local sas = {}
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				table.insert(sas, child)
			end
		end
		check(part.Color == lava.Color, name .. ": " .. part.Name .. " hat nicht die Skin-Farbe")
		check(#sas <= 1, name .. ": " .. part.Name .. " hat mehrere SurfaceAppearances")
		check(sas[1] == nil or sas[1].ColorMap == nil,
			name .. ": " .. part.Name .. " behält die deckende Textur – Skin-Farbe nicht zu sehen")
	end

	-- Effekt-Skin auf dieser Waffe: Effekte da, Bilder vom Sturmgewehr (wenn es sie hat)
	local gold = Cosmetics.Get("W_Drachengold")
	check(Cosmetics.FitsWeapon(gold, name), name .. ": Drachengold passt nicht")
	local model = GunModels.Build(name, gold)
	local fx = false
	for _, obj in model:GetDescendants() do
		if string.sub(obj.Name, 1, 7) == "SkinFx_" then
			fx = true
		end
	end
	check(fx, name .. ": Drachengold ohne Effekte")
end
check(tested >= 4, "zu wenige texturierte Waffen geprüft (" .. tested .. ")")

-- Partikelbilder: hat die Waffe keinen eigenen Skin-Ordner, nimmt SkinEffects den einer anderen Waffe
local weapons = ReplicatedStorage.Assets.Weapons
local rifle = weapons:FindFirstChild("Rifle")
local createdRifle = false
if not rifle then
	rifle = Instance.new("Model")
	rifle.Name = "Rifle"
	rifle.Parent = weapons
	createdRifle = true
end
local skins = rifle:FindFirstChild("Skins") or Instance.new("Folder")
skins.Name = "Skins"
skins.Parent = rifle
local folder = Instance.new("Folder")
folder.Name = "W_TestFx"
folder.Parent = skins
check(SkinEffects.Folder("SMG", "W_TestFx") == folder, "kein Rückgriff auf den Skin-Ordner einer anderen Waffe")
check(SkinEffects.Folder("Rifle", "W_TestFx") == folder, "eigener Skin-Ordner")
check(SkinEffects.Folder("SMG", "W_GibtEsNicht") == nil, "unbekannter Skin hat einen Ordner")
folder:Destroy()
if createdRifle then
	rifle:Destroy()
end

if failures == 0 then
	print("Skins auf allen Waffen: alles in Ordnung (" .. tested .. " texturierte Waffen)")
end

-- Baut ReplicatedStorage.Assets.Weapons.Rifle.Skins (alle Textur-Skins) als Datei für Rojo:
--   lune run tools/models/skins.luau models/Skins/Rifle.rbxmx
--   python3 tools/models/skins_legacy.py models/Skins/Rifle.rbxmx
-- Neuer Skin: Bilder in Studio hochladen (Asset Manager), IDs unten eintragen, beide Befehle ausführen.
-- Skins ohne Textur-IDs werden übersprungen (im Spiel dann nur Skin-Farbe + Standard-Partikelbilder).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local Instance, Content = roblox.Instance, roblox.Content

local SKINS = {
	{
		Id = "W_Drachengold",
		Textures = { Color = "88331684470741", Normal = "132303539386958", Roughness = "86156491508027",
			Metalness = "76966203756367", Emissive = "76587727648510" },
		Glow = { Tint = { 255, 110, 25 }, Strength = 4 },
		FX = { Glitzer = "92462690456150", Glut = "90333709813491", Flamme = "130268591969568" },
	},
	{
		Id = "W_Splitterlicht",
		Textures = { Color = "99136908861448", Normal = "126624004325595", Roughness = "121179829337104",
			Metalness = "122872738540040", Emissive = "70404628104932" },
		Glow = { Tint = { 255, 255, 255 }, Strength = 2 },
		FX = { Glitzer = "134875643310091", Splitter = "130677581126374", Staub = "89890220258426",
			Muendungsblitz = "121533793284101", Prismaring = "86750518345969", Leuchtspur = "103811217451772",
			Einschlag = "92445896050173", Emblem = "126040453631246" },
	},
}
local PARTS = { "Skin_Body", "Magazine", "Aufsaetze" } -- Teile der AR (+ alle Aufsätze)

local function uri(id) return Content.fromUri("rbxassetid://" .. id) end
local skins = Instance.new("Folder")
skins.Name = "Skins"
for _, skin in SKINS do
	local t = skin.Textures
	if t.Color == "" then
		print("übersprungen (keine Textur-IDs): " .. skin.Id)
		continue
	end
	local folder = Instance.new("Folder")
	folder.Name = skin.Id
	local keys = {}
	for key in skin.FX do table.insert(keys, key) end
	table.sort(keys)
	for _, key in keys do
		if skin.FX[key] ~= "" then
			folder:SetAttribute("FX_" .. key, skin.FX[key])
		end
	end
	for _, name in PARTS do
		local sa = Instance.new("SurfaceAppearance")
		sa.Name = name
		sa.ColorMapContent = uri(t.Color)
		sa.NormalMapContent = uri(t.Normal)
		sa.RoughnessMapContent = uri(t.Roughness)
		sa.MetalnessMapContent = uri(t.Metalness)
		if t.Emissive ~= "" then
			sa.EmissiveMaskContent = uri(t.Emissive)
			sa.EmissiveTint = roblox.Color3.fromRGB(skin.Glow.Tint[1], skin.Glow.Tint[2], skin.Glow.Tint[3])
			sa.EmissiveStrength = skin.Glow.Strength
		end
		sa.Parent = folder
	end
	folder.Parent = skins
	print("eingetragen: " .. skin.Id)
end
fs.writeFile(process.args[1], roblox.serializeModel({ skins }, true))

-- Baut ReplicatedStorage.Assets.Weapons.Rifle.Skins (Drachengold) als Datei für Rojo
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local Instance, Content = roblox.Instance, roblox.Content
local IDS = {
	Color = "88331684470741", Normal = "132303539386958", Roughness = "86156491508027",
	Metalness = "76966203756367", Emissive = "76587727648510",
	Glitzer = "92462690456150", Glut = "90333709813491", Flamme = "130268591969568",
}
local function uri(id) return Content.fromUri("rbxassetid://" .. id) end
local skins = Instance.new("Folder")
skins.Name = "Skins"
local folder = Instance.new("Folder")
folder.Name = "W_Drachengold"
for _, key in { "Glitzer", "Glut", "Flamme" } do
	folder:SetAttribute("FX_" .. key, IDS[key])
end
for _, name in { "Skin_Body", "Magazine", "Aufsaetze" } do
	local sa = Instance.new("SurfaceAppearance")
	sa.Name = name
	sa.ColorMapContent = uri(IDS.Color)
	sa.NormalMapContent = uri(IDS.Normal)
	sa.RoughnessMapContent = uri(IDS.Roughness)
	sa.MetalnessMapContent = uri(IDS.Metalness)
	sa.EmissiveMaskContent = uri(IDS.Emissive)
	sa.EmissiveTint = roblox.Color3.fromRGB(255, 110, 25)
	sa.EmissiveStrength = 4
	sa.Parent = folder
end
folder.Parent = skins
fs.writeFile(process.args[1], roblox.serializeModel({ skins }, true))

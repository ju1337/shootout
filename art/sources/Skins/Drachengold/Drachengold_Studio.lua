-- Drachengold in den Place eintragen (einmal in Studio, Command Bar, NICHT während Play)
-- 1. Im Asset Manager die 5 Bilder aus Texturen_Standard und die 3 aus Effekte hochladen
-- 2. Unten bei IDS die Nummern eintragen (Rechtsklick auf das Bild -> Copy ID)
-- 3. Dieses ganze Skript in die Command Bar einfügen, Enter
-- Legt an: ReplicatedStorage > Assets > Weapons > Rifle > Skins > W_Drachengold
-- (für jedes Teil der AR die Gold-Textur + "Aufsaetze" für Visier, Schalldämpfer, Griff).
-- Die Waffe selbst wird nicht verändert – den Skin sieht nur, wer ihn im Shop gekauft und ausgerüstet hat.
local IDS = {
	Color = 0, -- Drachengold_Color.png
	Normal = 0, -- Drachengold_Normal.png
	Roughness = 0, -- Drachengold_Roughness.png
	Metalness = 0, -- Drachengold_Metalness.png
	Emissive = 0, -- Drachengold_Emissive.png (Lava-Glühen)
	Glitzer = 0, -- FX_Glitzer.png
	Glut = 0, -- FX_Glut.png
	Flamme = 0, -- FX_Flamme.png
}
local SKIN = "W_Drachengold"
local GLUT = Color3.fromRGB(255, 110, 25)

local function asset(id)
	id = tonumber(id) or 0
	return id > 0 and ("rbxassetid://" .. string.format("%.0f", id)) or nil
end
for _, key in { "Color", "Normal", "Roughness", "Metalness" } do
	assert(asset(IDS[key]), "Bei IDS fehlt noch die Nummer für " .. key)
end

local rifle = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
rifle = rifle and rifle:FindFirstChild("Weapons")
rifle = rifle and rifle:FindFirstChild("Rifle")
assert(rifle, "ReplicatedStorage > Assets > Weapons > Rifle fehlt – erst die AR importieren")

local skins = rifle:FindFirstChild("Skins") or Instance.new("Folder")
skins.Name = "Skins"
skins.Parent = rifle
local old = skins:FindFirstChild(SKIN)
if old then old:Destroy() end
local folder = Instance.new("Folder")
folder.Name = SKIN
for _, key in { "Glitzer", "Glut", "Flamme" } do
	if asset(IDS[key]) then folder:SetAttribute("FX_" .. key, tostring(IDS[key])) end
end

local function appearance(name)
	local sa = Instance.new("SurfaceAppearance")
	sa.Name = name
	sa.ColorMap = asset(IDS.Color)
	sa.NormalMap = asset(IDS.Normal)
	sa.RoughnessMap = asset(IDS.Roughness)
	sa.MetalnessMap = asset(IDS.Metalness)
	if asset(IDS.Emissive) then
		local ok, err = pcall(function()
			sa.EmissiveMaskContent = Content.fromUri(asset(IDS.Emissive))
			sa.EmissiveTint = GLUT
			sa.EmissiveStrength = 4
		end)
		if not ok then warn("Drachengold: Glühen geht in dieser Studio-Version nicht: " .. tostring(err)) end
	end
	sa.Parent = folder
end

local names = {}
for _, part in rifle:GetDescendants() do
	if part:IsA("MeshPart") and not part:IsDescendantOf(skins) then
		local name = string.gsub(part.Name, "%.%d+$", "")
		local lower = string.lower(name)
		if not (string.find(lower, "point_") or string.find(lower, "pivot_") or string.find(lower, "glass")
			or string.find(lower, "neon") or string.find(lower, "reticle")) and not names[name] then
			names[name] = true
			appearance(name)
		end
	end
end
appearance("Aufsaetze")
folder.Parent = skins
local list = {}
for name in names do table.insert(list, name) end
print("[Drachengold] fertig: Rifle > Skins > " .. SKIN .. " für " .. table.concat(list, ", ") .. " + Aufsätze. Jetzt Play: Shop -> Drachengold kaufen (1 Münze) und ausrüsten")

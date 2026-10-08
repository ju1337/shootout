-- Drachengold (Test-Skin mit Effekten): im Shop für 1 Münze, nur Sturmgewehr, nicht in Kisten. Die Waffe bekommt
-- Glitzer, Glutfunken und Licht, das Glühen pulsiert, beim Schießen gibt es einen Feuerstoß. Ohne Skin: nichts davon.
local failures = 0
local function check(c, m) if not c then failures += 1 print("FEHLER: " .. m) end end

local Cosmetics = require("Cosmetics")
local CrateConfig = require("CrateConfig")
local GunModels = require("GunModels")
local SkinEffects = require("SkinEffects")
local CollectionService = game:GetService("CollectionService")

-- Shop
local item = Cosmetics.Get("W_Drachengold")
check(item ~= nil, "W_Drachengold fehlt in Cosmetics")
check(Cosmetics.ForSale(item), "Drachengold ist nicht im Shop kaufbar")
check(item.Price == 1, "Testpreis ist nicht 1 Münze")
check(item.Rarity == "Legendary", "Drachengold ist nicht legendär")
check(Cosmetics.FitsWeapon(item, "Rifle"), "Drachengold passt nicht aufs Sturmgewehr")
check(not Cosmetics.FitsWeapon(item, "SMG"), "Drachengold passt auch auf andere Waffen")
for _, crate in CrateConfig.Crates do
	for _, entry in CrateConfig.Pool(crate) do
		check(entry.Id ~= "W_Drachengold", "Test-Skin liegt in der Kiste " .. tostring(crate.Id))
	end
end

-- Effekte an der Waffe
local function count(container, name)
	local n = 0
	for _, obj in container:GetDescendants() do
		if obj.Name == name then n += 1 end
	end
	return n
end
local plain = GunModels.Build("Rifle", Cosmetics.Get("W_Chrom"))
check(count(plain, "SkinFx_Glitzer") + count(plain, "SkinFx_Glut") + count(plain, "SkinFx_Licht") == 0,
	"normaler Skin hat Drachengold-Effekte")
local model = GunModels.Build("Rifle", item)
check(count(model, "SkinFx_Glitzer") >= 1, "kein Glitzer")
check(count(model, "SkinFx_Glut") == 1, "keine Glutfunken")
check(count(model, "SkinFx_Licht") == 1, "kein Licht")
local main = nil
for _, part in model:GetChildren() do
	if part:IsA("BasePart") and CollectionService:HasTag(part, SkinEffects.Tag) then main = part end
end
check(main ~= nil and main:GetAttribute("SkinFx") == "Drachengold", "Hauptteil nicht markiert")
check(main ~= nil and main.Name ~= "Handle" and main.Transparency < 0.95, "Effekte am unsichtbaren Griffpunkt")

-- Pulsieren: Licht wird heller und dunkler
local appearance = Instance.new("SurfaceAppearance")
appearance:SetAttribute("SkinGlow", true)
appearance.Parent = main
model.Parent = workspace
SkinEffects.Init()
SkinEffects.Track(model)
local light = main:FindFirstChild("SkinFx_Licht")
local seen = {}
for i = 0, 20 do
	SkinEffects.Update(i * 0.13)
	seen[math.floor(light.Brightness * 2 + 0.5)] = true
end
local levels = 0
for _ in seen do levels += 1 end
check(levels >= 3, "Licht pulsiert nicht")
local style = SkinEffects.Styles.Drachengold
check(appearance.EmissiveStrength ~= nil and appearance.EmissiveStrength >= style.GlowMin - 1e-6
	and appearance.EmissiveStrength <= style.GlowMax + 1e-6, "Glühen außerhalb von GlowMin..GlowMax")

-- Tool: Attribute für den Feuerstoß bei anderen Spielern
local tool = GunModels.BuildTool("Rifle", "Sturmgewehr", item)
check(tool:GetAttribute("SkinFx") == "Drachengold" and tool:GetAttribute("SkinId") == "W_Drachengold",
	"Tool ohne SkinFx/SkinId")
check(GunModels.BuildTool("Rifle", "Sturmgewehr", nil):GetAttribute("SkinFx") == nil, "Tool ohne Skin hat SkinFx")

-- Feuerstoß: erscheint an der Mündung und verschwindet wieder
SkinEffects.Breath(CFrame.new(0, 5, 0), 1, "Rifle", "W_Drachengold", "Drachengold")
local breath = workspace:FindFirstChild("SkinFx_Drachenatem")
check(breath ~= nil and breath:FindFirstChild("Atem") ~= nil, "kein Feuerstoß")
SIM.Advance(1, 20)
check(workspace:FindFirstChild("SkinFx_Drachenatem") == nil, "Feuerstoß bleibt liegen")
SkinEffects.Breath(CFrame.new(), 1, "Rifle", nil, nil)
check(workspace:FindFirstChild("SkinFx_Drachenatem") == nil, "Feuerstoß ohne Effekt-Skin")

if failures == 0 then print("alles ok") end

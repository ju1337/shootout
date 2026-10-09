-- Splitterlicht (Test-Skin): im Shop, nur Sturmgewehr, nicht in Kisten. Dauer-Partikel nur in der Box unter der
-- Visierlinie, Ego halb so viele, beim Zielen keine. Eigenes Mündungsfeuer, Leuchtspur, Einschlag, Laufglühen und
-- Kill-Finisher (Server schickt ihn an alle im Modus).
local failures = 0
local function check(c, m) if not c then failures += 1 print("FEHLER: " .. m) end end

local Cosmetics = require("Cosmetics")
local CrateConfig = require("CrateConfig")
local GunModels = require("GunModels")
local SkinEffects = require("SkinEffects")
local SkinStyles = require("SkinStyles")

local item = Cosmetics.Get("W_Splitterlicht")
check(item ~= nil and Cosmetics.ForSale(item) and item.Price == 1, "Splitterlicht nicht für 1 Münze im Shop")
check(item ~= nil and item.Rarity == "Legendary", "nicht legendär")
check(Cosmetics.FitsWeapon(item, "Rifle") and not Cosmetics.FitsWeapon(item, "SMG"), "passt nicht nur aufs Sturmgewehr")
for _, crate in CrateConfig.Crates do
	for _, entry in CrateConfig.Pool(crate) do
		check(entry.Id ~= "W_Splitterlicht", "Test-Skin in Kiste " .. tostring(crate.Id))
	end
end

-- Waffe: Box unter der Visierlinie mit 3 Dauer-Emittern und Licht
local model = GunModels.Build("Rifle", item)
local box = model:FindFirstChild("SkinFx_Box")
check(box ~= nil, "keine Effekt-Box an der Waffe")
local info = GunModels.Info.Rifle
local top = box and (box.Position.Y + box.Size.Y / 2) or math.huge
check(top <= info.SightHeight - 0.25 + 1e-6, string.format("Box-Oberkante %.2f nicht 0,25 unter der Visierlinie %.2f",
	top, info.SightHeight))
local emitters = {}
for _, e in box and box:GetChildren() or {} do
	if e:IsA("ParticleEmitter") then table.insert(emitters, e) end
end
check(#emitters == 3, "nicht 3 Dauer-Emitter (Glitzer, Splitter, Staub)")
check(box and box:FindFirstChild("SkinFx_Licht") ~= nil, "kein Waffenlicht")
check(model:FindFirstChild("SkinFx_Glitzer", true) == nil, "Drachengold-Glitzer an Splitterlicht")
-- Partikel-Budget wie im Paket: TP <= 30, FP höchstens halb so viel
local tp, fp = 0, 0
for _, spec in SkinStyles.Splitterlicht.Weapon do
	tp += spec.Rate[1] * spec.Lifetime[2]
	fp += spec.Rate[2] * spec.Lifetime[2]
end
check(tp <= 30 and fp <= tp / 2 + 0.2, string.format("Partikel-Budget TP %.1f FP %.1f", tp, fp))

-- Puls, Ego-Raten und Zielen
local appearance = Instance.new("SurfaceAppearance")
appearance:SetAttribute("SkinGlow", true)
appearance.Parent = model:FindFirstChildWhichIsA("BasePart")
model.Parent = workspace
SkinEffects.Init()
SkinEffects.Track(model)
SkinEffects.Update(0)
SkinEffects.Update(1.5)
local glow = SkinStyles.Splitterlicht.Glow
check(appearance.EmissiveStrength ~= nil and math.abs(appearance.EmissiveStrength - glow.Max) < 0.05,
	"Glühen nach halber Periode nicht beim Maximum")
check(emitters[1].Rate == SkinStyles.Splitterlicht.Weapon[1].Rate[1], "Third-Person-Rate falsch")

-- Laufglühen: 10 Schüsse heizen auf, danach kühlt es ab
local heatLight = box:FindFirstChild("SkinFx_Laufglut", true)
for i = 1, 10 do
	SkinEffects.Fired(model, 2 + i * 0.1)
	SkinEffects.Update(2 + i * 0.1)
end
for i = 1, 20 do SkinEffects.Update(3 + i * 0.05) end
local hot = heatLight.Brightness
check(hot > 0.3, string.format("Laufglühen nach 10 Schüssen zu schwach (%.2f)", hot))
for i = 1, 60 do SkinEffects.Update(4 + i * 0.1) end
check(heatLight.Brightness < hot * 0.2, "Laufglühen kühlt nicht ab")

-- Schuss: eigenes Mündungsfeuer ersetzt das normale; Gegner mit Schalldämpfer: nichts
check(SkinEffects.Shot(CFrame.new(0, 5, 0), 1, "Rifle", "W_Splitterlicht", "Splitterlicht", false, false, false) == true,
	"Mündungsfeuer ersetzt das normale nicht")
check(workspace:FindFirstChild("SkinFx_Burst") ~= nil, "kein Mündungseffekt")
SIM.Advance(1, 20)
check(workspace:FindFirstChild("SkinFx_Burst") == nil, "Mündungseffekt bleibt liegen")
SkinEffects.Shot(CFrame.new(0, 5, 0), 1, "Rifle", "W_Splitterlicht", "Splitterlicht", false, false, true)
check(workspace:FindFirstChild("SkinFx_Burst") == nil, "Gegner sehen Mündungsfeuer trotz Schalldämpfer")
SkinEffects.Shot(CFrame.new(0, 5, 0), 1, "Rifle", "W_Splitterlicht", "Splitterlicht", true, true, true)
check(workspace:FindFirstChild("SkinFx_Burst") ~= nil, "eigener Kristallhauch mit Schalldämpfer fehlt")
SIM.Advance(1, 20)

-- Leuchtspur und Einschlag
check(SkinEffects.Tracer(Vector3.new(0, 5, 0), Vector3.new(0, 5, -50), "Rifle", "W_Splitterlicht", "Splitterlicht", false),
	"Leuchtspur ersetzt die normale nicht")
local spur = workspace:FindFirstChild("SkinFx_Spur")
check(spur ~= nil and spur:FindFirstChildOfClass("Beam") ~= nil, "keine Beam-Leuchtspur")
SIM.Advance(1, 20)
check(workspace:FindFirstChild("SkinFx_Spur") == nil, "Leuchtspur bleibt liegen")
check(SkinEffects.Tracer(Vector3.zero, Vector3.new(0, 0, -50), "Rifle", nil, "Drachengold", false) == false,
	"Drachengold ersetzt die Leuchtspur")
for _ = 1, 20 do
	SkinEffects.Impact(Vector3.new(0, 0, -10), Vector3.yAxis, "Rifle", "W_Splitterlicht", "Splitterlicht")
end
local count = 0
for _, c in workspace:GetChildren() do
	if c.Name == "SkinFx_Burst" then count += 1 end
end
check(count >= 1 and count <= 12, "Einschläge nicht begrenzt (" .. count .. ")")
SIM.Advance(1, 20)

-- Finisher: Highlight nur sichtbar, wenn nicht verdeckt; nach 1,6 s alles weg, Körper ausgeblendet
check(SkinEffects.HasFinisher("Splitterlicht") and not SkinEffects.HasFinisher("Drachengold"), "HasFinisher falsch")
local victim = Instance.new("Model")
local torso = Instance.new("Part")
torso.Name = "UpperTorso"
torso.Parent = victim
victim.Parent = workspace
local finisher = SkinEffects.Finisher(victim, CFrame.new(0, 3, 0), "Splitterlicht", "Rifle", "W_Splitterlicht")
check(finisher ~= nil, "kein Finisher")
local highlight = finisher and finisher:FindFirstChildOfClass("Highlight")
check(highlight ~= nil and highlight.DepthMode == Enum.HighlightDepthMode.Occluded, "Highlight nicht Occluded")
SIM.Advance(0.6, 30)
check(torso.Transparency > 0.9, "Körper zerspringt nicht")
SIM.Advance(1.2, 30)
check(workspace:FindFirstChild("SkinFx_Finisher") == nil, "Finisher bleibt liegen")
check(SkinEffects.Finisher(nil, CFrame.new(), "Drachengold") == nil, "Drachengold hat einen Finisher")

if failures == 0 then print("alles ok") end

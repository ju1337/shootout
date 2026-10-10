-- Deine Waffenmodelle: assets/Weapons/*.rbxmx (in Studio per Rechtsklick "Save to File..." gespeichert) gegen die
-- Spezifikation (docs/waffen-modelle.md). Jedes Modell muss laden (alle Marker, plausible Lage und Größe), Textur-
-- Skins müssen zu echten Skins dieser Waffe gehören. Hinweise (z.B. eine fehlende Animationsgruppe) erscheinen als
-- HINWEIS im Log. Zielen, Haltung und Nachladen prüfen weapons, viewmodel und pose automatisch mit deinem Modell.
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

local models = ReplicatedStorage.Assets.Weapons:GetChildren()
if #models == 0 then
	print("Noch keine Waffenmodelle in assets/Weapons – alle Waffen sind Quader-Waffen")
end
local report = GunModels.AssetReport()
for _, source in models do
	local name = source.Name
	local entry = report[name]
	check(entry ~= nil and entry.Loaded,
		name .. ": nicht geladen – " .. (entry and table.concat(entry.Errors, "; ") or "kein Prüfbericht"))
	for _, warning in entry and entry.Warnings or {} do
		print("HINWEIS " .. name .. ": " .. warning)
	end
	local skins = source:FindFirstChild("Skins")
	for _, folder in skins and skins:GetChildren() or {} do
		local item = Cosmetics.Get(folder.Name)
		check(folder.Name == GunModels.ColorSkinFolder or item ~= nil and item.Type == "Weapon" and Cosmetics.FitsWeapon(item, name),
			name .. ": Skins/" .. folder.Name .. " ist kein Waffen-Skin für diese Waffe")
	end
	if entry and entry.Loaded then
		print(string.format("%s: 3D-Modell geladen (Visierlinie %.3f Studs über dem Griff)", name, GunModels.Info[name].SightHeight))
	end
end

if failures == 0 then
	print("Waffenmodelle: alles in Ordnung")
end

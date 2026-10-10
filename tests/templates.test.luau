--!assets art/templates
-- Die Vorlagen (art/templates/Weapons, erzeugt von tools/weapon_templates.py) sind selbst gültige Waffenmodelle:
-- alle sieben laden ohne Fehler und Hinweise, die Drehpunkte liegen wie bei den Quader-Waffen auf dem Hauptteil
-- jeder Gruppe, und beim Zielen liegt die Visierlinie in der Bildmitte. So passen Vorlage, Spezifikation und Lader
-- zusammen – wer um die Vorlage herum modelliert, bekommt ein Modell, das funktioniert.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, eps)
	return (a - b).Magnitude < (eps or 1e-4)
end

local GunModels = require("GunModels")
local ViewModel = require("ViewModel")
local report = GunModels.AssetReport()
local camera = CFrame.new(3, 6, -9) * CFrame.Angles(0.15, -0.6, 0)

for weaponName, info in GunModels.Info do
	local entry = report[weaponName]
	check(GunModels.HasAsset(weaponName) and entry and entry.Loaded, weaponName .. ": Vorlage lädt nicht")
	check(entry and #entry.Errors == 0 and #entry.Warnings == 0, weaponName .. ": Meldungen: "
		.. (entry and table.concat(entry.Errors, "; ") .. " " .. table.concat(entry.Warnings, "; ") or "-"))
	-- Drehpunkte (Pivot-Marker der Vorlage) = Mitte des Hauptteils, wie bei den Quader-Waffen
	local model = GunModels.Build(weaponName)
	local groups = {}
	for _, part in model:GetChildren() do
		local group = part:GetAttribute("Group")
		if group then
			groups[group] = true
		end
	end
	for group in groups do
		local main = GunModels.GroupMainPart(weaponName, group)
		check(main ~= nil and near(GunModels.GroupPivot(weaponName, group).Position, GunModels.Rest(weaponName, main).Position),
			weaponName .. ": Drehpunkt " .. group .. " nicht auf dem Hauptteil " .. tostring(main))
	end
	check(info.Muzzle.Z < info.SightFrontZ and info.SightFrontZ < info.SightZ, weaponName .. ": Mündung vor Korn vor Kimme")
	-- Zielen: Visierlinie mittig
	local vm = ViewModel.new(weaponName, nil, Color3.fromRGB(80, 80, 80))
	vm.DrawStart = os.clock() - 5
	for _ = 1, 3 do
		vm:Update(1 / 60, { Camera = camera, Aim = 1, Sprinting = false, Speed = 0 })
	end
	for _, z in { info.SightZ, info.SightFrontZ } do
		local p = camera:PointToObjectSpace(vm.GunWorld * (Vector3.new(0, info.SightHeight, z) * ViewModel.Scale()))
		check(math.abs(p.X) < 1e-3 and math.abs(p.Y) < 1e-3, weaponName .. ": Visierlinie nicht mittig")
	end
end
-- MG: Hauptteil der Magazin-Gruppe ist der Kasten, nicht der Gurt
check(GunModels.GroupMainPart("LMG", "Magazine") == "Skin_Magazine_Box", "MG: Kasten ist das Magazin")
local lmg = GunModels.Build("LMG", nil, { "DrumMag" })
-- 3D-Waffe ohne Trommel-Modell (Assets.Attachments.DrumMag fehlt): kein Klotz, eingebauter Kasten bleibt
check(lmg:FindFirstChild("AttDrum") == nil and lmg:FindFirstChild("Skin_Magazine_Box") ~= nil, "MG: kein Trommel-Klotz am 3D-Modell")

if failures == 0 then
	print("Vorlagen: alle sieben laden und passen")
end

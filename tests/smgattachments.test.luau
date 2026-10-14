-- Aufsatz-Modelle nur für die MP (Assets.Attachments.<Aufsatz>_SMG, tools/attachments/meshy_attachment.py): Maße aus
-- art/sources/SMG.glb und art/sources/Attachments/*_SMG.glb (Teile in Stücken zusammengefasst). Geprüft: Vorrang vor
-- dem allgemeinen Modell, Sitz wie in der GLB (Magazin am eingebauten, Mündung, Visier auf Point_Optic), eingebautes
-- Magazin in zwei Stücken ganz weg, Zielen durch den Rotpunkt.
local failures = 0
local function check(c, m) if not c then failures += 1 print("FEHLER: " .. m) end end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local folder = ReplicatedStorage.Assets.Weapons
for _, c in folder:GetChildren() do c:Destroy() end
local att = Instance.new("Folder", ReplicatedStorage.Assets) att.Name = "Attachments"
local function build(name, parent, data, place)
	local m = Instance.new("Model") m.Name = name
	for _, d in data do
		local p = Instance.new("MeshPart") p.Name = d[1] p.Size = Vector3.new(d[5], d[6], d[7])
		p.CFrame = place * CFrame.new(d[2], d[3], d[4]) p.Parent = m
	end
	m.Parent = parent
	return m
end
local turn = CFrame.Angles(0, math.rad(180), 0)
build("SMG", folder, {{"Skin_Body", -0.0003,0.0694,0.2504, 0.2103,0.9618,2.3750},{"Magazine_01", 0.0001,-0.4063,0.7097, 0.0888,0.4409,0.2026},{"Magazine_02", -0.0006,-0.3012,0.5433, 0.1148,0.6273,0.3005},{"Bolt", 0.0010,0.4248,0.9182, 0.0395,0.0110,0.0786},{"Neon_FrontDot", -0.0000,0.4654,1.2422, 0.0250,0.0250,0.0062},{"Pivot_Bolt", -0.0000,0.4243,0.9234, 0.0600,0.0600,0.0600},{"Pivot_Magazine", -0.0000,0.0125,0.4991, 0.0600,0.0600,0.0600},{"Point_Eject", -0.0749,0.2870,0.2496, 0.0400,0.0400,0.0400},{"Point_Grip", -0.0000,0.0000,-0.0000, 0.0400,0.0400,0.0400},{"Point_LeftHand", -0.0000,0.2745,0.8735, 0.0400,0.0400,0.0400},{"Point_Muzzle", -0.0000,0.2683,1.4379, 0.0400,0.0400,0.0400},{"Point_Optic", -0.0000,0.3806,0.1685, 0.0400,0.0400,0.0400},{"Point_SightFront", -0.0000,0.4792,1.2540, 0.0400,0.0400,0.0400},{"Point_SightRear", -0.0000,0.4792,-0.0998, 0.0400,0.0400,0.0400},{"Point_Stock", -0.0000,0.1185,-0.9371, 0.0400,0.0400,0.0400}}, CFrame.new(6, 3, -2) * turn)
build("FastMag_SMG", att, {{"Magazine_Fast", 0.0003,-0.2499,0.6155, 0.0884,0.9285,0.4569},{"Point_Front", -0.0006,-0.3012,1.5433, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0006,-0.3012,0.5433, 0.0300,0.0300,0.0300}}, CFrame.new(-9, 4, 7) * turn)
build("Suppressor_SMG", att, {{"Suppressor", 0.0002,0.2749,1.8658, 0.2493,0.2496,1.0812},{"Point_Mount", -0.0000,0.2683,1.4379, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.2683,2.4064, 0.0300,0.0300,0.0300}}, CFrame.new(4, -5, 11) * turn)
build("Compensator_SMG", att, {{"Compensator", 0.0002,0.2749,1.5956, 0.1568,0.1622,0.4410},{"Point_Mount", -0.0000,0.2683,1.4379, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.2683,1.8161, 0.0300,0.0300,0.0300}}, CFrame.new(12, 2, 5) * turn)
build("HoloSight_SMG", att, {{"RedDot", -0.0012,0.4694,0.1687, 0.1520,0.1776,0.2375},{"Glass", -0.0000,0.5103,0.2561, 0.1223,0.0668,0.0010},{"Neon_Reticle", -0.0000,0.5103,0.2561, 0.0050,0.0050,0.0050},{"Point_Mount", -0.0000,0.3806,0.1685, 0.0300,0.0300,0.0300},{"Point_SightFront", -0.0000,0.5103,0.2561, 0.0300,0.0300,0.0300},{"Point_SightRear", -0.0000,0.5103,0.0499, 0.0300,0.0300,0.0300}}, CFrame.new(-3, 8, -6) * turn)
-- allgemeine Modelle (für andere Waffen): an der MP dürfen sie nicht auftauchen
build("FastMag", att, {{"Magazine_Fast_01", 0.0021,-0.2993,0.7507, 0.1208,0.9539,0.4598},{"Point_Front", -0.0013,-0.1940,1.0495, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0013,-0.1940,0.7495, 0.0300,0.0300,0.0300}}, CFrame.new(4, -6, 9) * turn)
build("Suppressor", att, {{"Suppressor", -0.0000,0.0000,0.4420, 0.2100,0.2088,0.8840},{"Point_Mount", -0.0000,0.0000,0.1700, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.0000,0.8840, 0.0300,0.0300,0.0300}}, CFrame.new(5, 8, 2) * turn)
local GunModels = require("GunModels")
local info = GunModels.Info.SMG
check(GunModels.HasAsset("SMG"), "MP-Modell nicht geladen")
check(typeof(info.Optic) == "Vector3" and math.abs(info.Optic.Y - 0.3806) < 0.005 and math.abs(info.Optic.Z + 0.1685) < 0.005,
	"Point_Optic nicht als Info.Optic uebernommen: " .. tostring(info.Optic))
-- Lage eines Teils im Modell (Griff = Ursprung)
local function rel(model, part)
	return model.PrimaryPart.CFrame:PointToObjectSpace(part.Position)
end
-- Schnellmagazin: ersetzt beide Stücke des eingebauten Magazins, sitzt wie in der GLB (Mitte 0,0513 höher und 0,0722
-- weiter vorn als die Mitte von Magazine_02, siehe Point_Mount)
do
	local base = GunModels.Build("SMG", nil, {})
	local m = GunModels.Build("SMG", nil, { "FastMag" })
	local part = m:FindFirstChild("AttFastMag_Magazine_Fast")
	check(part ~= nil, "MP-Schnellmagazin nicht angebaut")
	check(m:FindFirstChild("AttFastMag_Magazine_Fast_01") == nil, "allgemeines Schnellmagazin an der MP")
	check(m:FindFirstChild("Magazine_01") == nil and m:FindFirstChild("Magazine_02") == nil, "eingebautes Magazin (Stuecke) noch da")
	local mag2 = base:FindFirstChild("Magazine_02")
	if part and mag2 then
		check(part:GetAttribute("Group") == "Magazine", "Schnellmagazin nicht in der Gruppe Magazine")
		local d = rel(m, part) - rel(base, mag2)
		print("HINWEIS MP-Schnellmagazin gegenueber Magazine_02 " .. tostring(d))
		check(math.abs(d.X) < 0.005 and math.abs(d.Y - 0.0513) < 0.005 and math.abs(d.Z + 0.0722) < 0.005,
			"MP-Schnellmagazin sitzt nicht wie in der GLB")
	end
end
-- Mündung: Teil-Mitte = Mündung + Versatz aus der GLB (Achse 0,0066 über Point_Muzzle)
for _, case in { { "Suppressor", 1.8658 }, { "Compensator", 1.5956 } } do
	local id, centre = case[1], case[2]
	local c = GunModels.Build("SMG", nil, { id })
	local part = c:FindFirstChild("Att" .. id .. "_" .. id)
	check(part ~= nil, id .. ": MP-Modell nicht angebaut")
	if part then
		local want = info.Muzzle + Vector3.new(0, 0.2749 - 0.2683, -(centre - 1.4379))
		print("HINWEIS MP-" .. id .. " " .. tostring(rel(c, part)) .. ", soll " .. tostring(want))
		check((rel(c, part) - want).Magnitude < 0.01, id .. " sitzt nicht an der MP-Muendung")
		check(math.abs(part.Size.Z - (id == "Suppressor" and 1.0812 or 0.4410)) < 0.01, id .. ": allgemeines Modell statt MP-Modell")
	end
end
-- Rotpunkt: auf Point_Optic, Leuchtpunkt genau auf der Ziellinie, Visierlinie über Kimme und Korn
do
	local plain = GunModels.AimOffset("SMG")
	local aim = GunModels.AimOffset("SMG", { "HoloSight" })
	local s = GunModels.Build("SMG", nil, { "HoloSight" })
	local body = s:FindFirstChild("AttHoloSight_RedDot")
	local ret = s:FindFirstChild("AttHoloSight_Neon_Reticle")
	check(body and ret, "Rotpunkt nicht angebaut")
	check(aim.Position.Y < plain.Position.Y - 0.02, "Rotpunkt: Visierlinie nicht ueber Kimme und Korn")
	if body and ret then
		local r = rel(s, ret)
		print("HINWEIS Rotpunkt-Absehen " .. tostring(r) .. ", Zielen " .. tostring(aim.Position))
		check(math.abs(r.X) < 0.01 and math.abs(r.Y + aim.Position.Y) < 0.01, "Absehen nicht auf der Ziellinie")
		check(math.abs(r.Z + 0.2561) < 0.01, "Absehen nicht ueber dem Gehaeuse")
		check(math.abs(rel(s, body).Y - 0.4694) < 0.01, "Rotpunkt sitzt nicht auf Point_Optic")
		check(ret.Material == Enum.Material.Neon, "Absehen leuchtet nicht")
		local glass = s:FindFirstChild("AttHoloSight_Glass")
		check(glass and glass.Material == Enum.Material.Glass, "kein Glas im Fenster")
	end
end
if failures == 0 then print("HINWEIS alles ok") end

-- Aufsatz-Modelle nur für die Schrotflinte (Assets.Attachments.<Aufsatz>_Shotgun, tools/attachments/meshy_attachment.py):
-- Maße aus art/sources/Shotgun.glb und art/sources/Attachments/*_Shotgun.glb (Teile in Stücken zusammengefasst).
-- Geprüft: Läufe ersetzen Skin_Barrel (samt Korn-Leuchtpunkt, Hide_FrontDot), der kurze Lauf auch das Röhrenmagazin
-- vor dem Vorderschaft (Hide_Tube); neue Mündung, Mündungsbremse daran; Griff und Laser am Vorderschaft gehören zur
-- Gruppe Pump (Group_Pump) und sitzen wie in der GLB.
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
build("Shotgun", folder, {{"Skin_Body", -0.0004,-0.0637,0.5970, 0.2961,0.8441,3.2347},{"Pump", -0.0006,-0.0182,1.7569, 0.2937,0.2859,0.8941},{"Skin_Barrel", -0.0009,0.2204,1.9898, 0.1719,0.2745,1.8796},{"Skin_Tube", -0.0006,-0.0663,2.4859, 0.1661,0.2989,0.5431},{"Shell", -0.0000,-0.1040,0.8317, 0.0639,0.0700,0.2212},{"Neon_FrontDot", -0.0006,0.3462,2.6859, 0.0200,0.0200,0.0104},{"Neon_RearDot_L", 0.0218,0.3462,0.4387, 0.0071,0.0071,0.0104},{"Neon_RearDot_R", -0.0218,0.3462,0.4387, 0.0071,0.0071,0.0104},{"Pivot_Pump", -0.0000,-0.0208,1.7465, 0.0600,0.0600,0.0600},{"Pivot_Shell", -0.0000,-0.1040,0.8317, 0.0600,0.0600,0.0600},{"Point_Eject", -0.0832,0.1663,0.8525, 0.0400,0.0400,0.0400},{"Point_Grip", -0.0000,0.0000,-0.0000, 0.0400,0.0400,0.0400},{"Point_LeftHand", -0.0000,-0.0208,1.7465, 0.0400,0.0400,0.0400},{"Point_Muzzle", -0.0000,0.1975,2.9296, 0.0400,0.0400,0.0400},{"Point_SightFront", -0.0000,0.3576,2.7445, 0.0400,0.0400,0.0400},{"Point_SightRear", -0.0000,0.3576,0.4678, 0.0400,0.0400,0.0400},{"Point_Stock", -0.0000,-0.1663,-1.0204, 0.0400,0.0400,0.0400}}, CFrame.new(3, 2, -8) * turn)
build("LongBarrel_Shotgun", att, {{"LongBarrel", -0.0008,0.1690,2.3562, 0.2601,0.2960,2.6124},{"Hide_FrontDot", -0.0000,0.1559,2.9296, 0.0300,0.0300,0.0300},{"Point_Front", -0.0000,0.1975,3.5534, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0000,0.1975,2.9296, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.1975,3.6624, 0.0300,0.0300,0.0300}}, CFrame.new(-6, 5, 4) * turn)
build("ShortBarrel_Shotgun", att, {{"ShortBarrel", -0.0003,0.1572,1.6831, 0.2151,0.3331,1.2663},{"Hide_FrontDot", -0.0000,0.1559,2.9296, 0.0300,0.0300,0.0300},{"Hide_Tube", -0.0000,0.1559,2.9296, 0.0300,0.0300,0.0300},{"Point_Front", -0.0000,0.1975,3.5534, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0000,0.1975,2.9296, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.1975,2.3163, 0.0300,0.0300,0.0300}}, CFrame.new(9, -4, 2) * turn)
build("MuzzleBrake_Shotgun", att, {{"MuzzleBrake", -0.0000,0.1643,3.1788, 0.2246,0.2197,0.5920},{"Point_Mount", -0.0000,0.1975,2.9296, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.1975,3.4748, 0.0300,0.0300,0.0300}}, CFrame.new(1, 7, -3) * turn)
build("VerticalGrip_Shotgun", att, {{"VerticalGrip", -0.0000,-0.3742,1.8297, 0.1634,0.4574,0.1986},{"Group_Pump", -0.0000,0.0208,1.7465, 0.0300,0.0300,0.0300},{"Point_Front", -0.0000,-0.0208,2.3703, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0000,-0.0208,1.7465, 0.0300,0.0300,0.0300}}, CFrame.new(-2, 3, 12) * turn)
build("Laser_Shotgun", att, {{"Laser", -0.2266,0.0000,2.0273, 0.1705,0.1413,0.4156},{"Group_Pump", -0.0000,0.0208,1.7465, 0.0300,0.0300,0.0300},{"Point_Front", -0.0000,-0.0208,2.3703, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0000,-0.0208,1.7465, 0.0300,0.0300,0.0300}}, CFrame.new(7, 1, 6) * turn)
local GunModels = require("GunModels")
local info = GunModels.Info.Shotgun
check(GunModels.HasAsset("Shotgun"), "Schrotflinte nicht geladen")
local function rel(model, part)
	return model.PrimaryPart.CFrame:PointToObjectSpace(part.Position)
end
local base = GunModels.Build("Shotgun", nil, {})
check(base:FindFirstChild("Skin_Barrel") and base:FindFirstChild("Skin_Tube") and base:FindFirstChild("Neon_FrontDot"),
	"eingebauter Lauf, Roehre oder Korn fehlt ohne Aufsatz")
-- Läufe: Lauf und Korn weg, neue Mündung, Mündungsbremse an der neuen Mündung
for _, case in { { "LongBarrel", 3.6624, true }, { "ShortBarrel", 2.3163, false } } do
	local id, front, tube = case[1], case[2], case[3]
	local m = GunModels.Build("Shotgun", nil, { id, "MuzzleBrake" })
	local part = m:FindFirstChild("Att" .. id .. "_" .. id)
	check(part ~= nil, id .. ": Modell nicht angebaut")
	check(m:FindFirstChild("Skin_Barrel") == nil, id .. ": eingebauter Lauf noch da")
	check(m:FindFirstChild("Neon_FrontDot") == nil, id .. ": Leuchtpunkt des alten Korns noch da")
	check((m:FindFirstChild("Skin_Tube") ~= nil) == tube, id .. ": Roehrenmagazin " .. (tube and "fehlt" or "noch da"))
	check(m:FindFirstChild("Neon_RearDot_L") ~= nil and m:FindFirstChild("Pump") ~= nil, id .. ": zu viel ausgeblendet")
	local muzzle = m:GetAttribute("Muzzle")
	check(typeof(muzzle) == "Vector3", id .. ": Muendung nicht verschoben")
	if part and typeof(muzzle) == "Vector3" then
		local want = info.Muzzle + Vector3.new(0, 0, -(front - 2.9296))
		print("HINWEIS " .. id .. " Muendung " .. tostring(muzzle) .. ", soll " .. tostring(want))
		check((muzzle - want).Magnitude < 0.01, id .. ": neue Muendung falsch")
		local brake = m:FindFirstChild("AttMuzzleBrake_MuzzleBrake")
		check(brake ~= nil, id .. ": Muendungsbremse fehlt")
		if brake then
			-- Bremse relativ zur Mündung wie in der GLB (Mitte 0,2492 vor, 0,0332 unter Point_Muzzle)
			local d = rel(m, brake) - muzzle
			check((d - Vector3.new(0, 0.1643 - 0.1975, -(3.1788 - 2.9296))).Magnitude < 0.01, id .. ": Bremse nicht an der neuen Muendung")
		end
	end
end
-- Griff und Laser am Vorderschaft: Gruppe Pump, Lage wie in der GLB
for _, case in { { "VerticalGrip", Vector3.new(0, -0.3742, -1.8297) }, { "Laser", Vector3.new(0.2266, 0, -2.0273) } } do
	local id, want = case[1], case[2]
	local m = GunModels.Build("Shotgun", nil, { id })
	local part = m:FindFirstChild("Att" .. id .. "_" .. id)
	check(part ~= nil, id .. ": Modell nicht angebaut")
	check(m:FindFirstChild("Att" .. id .. "_Group_Pump") == nil, id .. ": Marker angebaut")
	if part then
		check(part:GetAttribute("Group") == "Pump", id .. ": geht nicht mit dem Vorderschaft mit")
		print("HINWEIS " .. id .. " " .. tostring(rel(m, part)) .. ", soll " .. tostring(want))
		check((rel(m, part) - want).Magnitude < 0.01, id .. " sitzt nicht wie in der GLB")
	end
end
if failures == 0 then print("HINWEIS alles ok") end

-- Aufsatz-Modelle nur für das Präzisionsgewehr (Assets.Attachments.<Aufsatz>_DMR, tools/attachments/meshy_attachment.py):
-- Maße aus art/sources/DMR.glb (sniper_v1.py) und art/sources/Attachments/*_DMR.glb (Teile in Stücken zusammengefasst).
-- Geprüft: Läufe ersetzen Lauf und Mündungsbremse (Wort Barrel), neue Mündung; der Schalldämpfer ersetzt nur die Bremse
-- (Hide_Brake) und sitzt am Laufende; Magazine ersetzen das eingebaute und sitzen wie in der GLB.
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
build("DMR", folder, {{"Skin_Body", 0.0033,0.2692,0.6870, 0.4233,0.9251,3.5660},{"Skin_Barrel_Brake", -0.0017,0.3324,3.2661, 0.2010,0.2061,0.4258},{"Magazine", -0.0006,-0.0293,0.4904, 0.1346,0.2606,0.3221},{"Bolt", -0.1777,0.2329,0.1991, 0.1342,0.1531,0.1529},{"Skin_Barrel_01", -0.0006,0.3371,2.7328, 0.1266,0.1252,0.6408},{"Skin_Barrel_02", -0.0009,0.3363,2.1432, 0.1221,0.1235,0.7043},{"Pivot_Bolt", -0.0962,0.3486,0.2284, 0.0600,0.0600,0.0600},{"Pivot_Magazine", -0.0000,0.1010,0.5529, 0.0600,0.0600,0.0600},{"Point_Eject", -0.0841,0.3847,0.4688, 0.0400,0.0400,0.0400},{"Point_Grip", -0.0000,0.0000,-0.0000, 0.0400,0.0400,0.0400},{"Point_LeftHand", -0.0000,0.2524,1.2621, 0.0400,0.0400,0.0400},{"Point_Muzzle", -0.0000,0.3363,3.4790, 0.0400,0.0400,0.0400},{"Point_SightFront", -0.0024,0.5594,1.3703, 0.0400,0.0400,0.0400},{"Point_SightRear", -0.0024,0.5594,-0.0421, 0.0400,0.0400,0.0400},{"Point_Stock", -0.0000,0.1022,-1.0960, 0.0400,0.0400,0.0400}}, CFrame.new(4, 3, -6) * turn)
build("LongBarrel_DMR", att, {{"LongBarrel", -0.0004,0.3359,2.9925, 0.2133,0.2134,2.4029},{"Point_Front", -0.0000,0.3363,4.2002, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0000,0.3363,3.4790, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.3363,4.1940, 0.0300,0.0300,0.0300}}, CFrame.new(-5, 2, 8) * turn)
build("HeavyBarrel_DMR", att, {{"HeavyBarrel", -0.0003,0.3265,2.7519, 0.2504,0.3006,1.9217},{"Point_Front", -0.0000,0.3363,4.2002, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0000,0.3363,3.4790, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.3363,3.7128, 0.0300,0.0300,0.0300}}, CFrame.new(7, -3, 1) * turn)
build("Suppressor_DMR", att, {{"Suppressor", -0.0000,0.3363,3.5398, 0.2056,0.2116,1.0886},{"Hide_Brake", -0.0000,0.2882,3.4790, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0000,0.3363,3.4790, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.3363,4.0841, 0.0300,0.0300,0.0300}}, CFrame.new(2, 9, 4) * turn)
build("FastMag_DMR", att, {{"Magazine_Fast", -0.0002,-0.0362,0.4891, 0.0761,0.6267,0.3140},{"Point_Front", -0.0006,-0.0293,1.4904, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0006,-0.0293,0.4904, 0.0300,0.0300,0.0300}}, CFrame.new(-8, 5, -2) * turn)
build("ExtendedMag_DMR", att, {{"Magazine_Ext", -0.0001,-0.1346,0.4891, 0.1053,0.8831,0.3322},{"Point_Front", -0.0006,-0.0293,1.4904, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0006,-0.0293,0.4904, 0.0300,0.0300,0.0300}}, CFrame.new(3, -7, 9) * turn)
local GunModels = require("GunModels")
local info = GunModels.Info.DMR
check(GunModels.HasAsset("DMR"), "Praezisionsgewehr nicht geladen")
local function rel(model, part)
	return model.PrimaryPart.CFrame:PointToObjectSpace(part.Position)
end
-- Läufe: Lauf und Bremse weg, neue Mündung; Schalldämpfer am neuen Lauf
for _, case in { { "LongBarrel", 4.1940 }, { "HeavyBarrel", 3.7128 } } do
	local id, front = case[1], case[2]
	local m = GunModels.Build("DMR", nil, { id, "Suppressor" })
	check(m:FindFirstChild("Att" .. id .. "_" .. id) ~= nil, id .. ": Modell nicht angebaut")
	check(m:FindFirstChild("Skin_Barrel_01") == nil and m:FindFirstChild("Skin_Barrel_Brake") == nil,
		id .. ": eingebauter Lauf oder Bremse noch da")
	local muzzle = m:GetAttribute("Muzzle")
	check(typeof(muzzle) == "Vector3" and (muzzle - (info.Muzzle + Vector3.new(0, 0, -(front - 3.4790)))).Magnitude < 0.01,
		id .. ": neue Muendung falsch " .. tostring(muzzle))
	local sup = m:FindFirstChild("AttSuppressor_Suppressor")
	if sup and typeof(muzzle) == "Vector3" then
		local d = rel(m, sup) - muzzle
		check((d - Vector3.new(0, 0, -(3.5398 - 3.4790))).Magnitude < 0.01, id .. ": Schalldaempfer nicht an der neuen Muendung")
	else
		check(false, id .. ": Schalldaempfer fehlt")
	end
end
-- Schalldämpfer am eingebauten Lauf: nur die Bremse weg
do
	local m = GunModels.Build("DMR", nil, { "Suppressor" })
	local sup = m:FindFirstChild("AttSuppressor_Suppressor")
	check(sup ~= nil, "Schalldaempfer nicht angebaut")
	check(m:FindFirstChild("Skin_Barrel_Brake") == nil, "Muendungsbremse unter dem Schalldaempfer noch da")
	check(m:FindFirstChild("Skin_Barrel_01") ~= nil and m:FindFirstChild("Skin_Barrel_02") ~= nil, "Lauf mit ausgeblendet")
	if sup then
		local want = info.Muzzle + Vector3.new(0, 0, -(3.5398 - 3.4790))
		check((rel(m, sup) - want).Magnitude < 0.01, "Schalldaempfer sitzt nicht wie in der GLB")
	end
end
-- Magazine: ersetzen das eingebaute, Mitte wie in der GLB
for _, case in { { "FastMag", "Magazine_Fast", Vector3.new(0.0002, -0.0362, -0.4891) }, { "ExtendedMag", "Magazine_Ext", Vector3.new(0.0001, -0.1346, -0.4891) } } do
	local id, name, want = case[1], case[2], case[3]
	local m = GunModels.Build("DMR", nil, { id })
	local part = m:FindFirstChild("Att" .. id .. "_" .. name)
	check(part ~= nil and m:FindFirstChild("Magazine") == nil, id .. ": Magazin nicht ersetzt")
	if part then
		check(part:GetAttribute("Group") == "Magazine", id .. ": nicht in der Gruppe Magazine")
		print("HINWEIS " .. id .. " " .. tostring(rel(m, part)) .. ", soll " .. tostring(want))
		check((rel(m, part) - want).Magnitude < 0.01, id .. " sitzt nicht wie in der GLB")
	end
end
if failures == 0 then print("HINWEIS alles ok") end

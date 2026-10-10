-- Aufsatz-Modelle (Assets.Attachments): Holo-Visier, Schalldämpfer und Winkelgriff mit den Maßen aus art/sources/Attachments
-- am Sturmgewehr (Maße wie art/sources/Rifle.glb). Geprüft: Sitz an Schiene, Mündung und Handschutz, Zielen durchs
-- Visier (Leuchtpunkt genau auf der Ziellinie, rund und leuchtend), keine Klotz-Aufsätze, Pistole ohne Visier.
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
build("Rifle", folder, {{"Skin_Body", -0.0199,0.2569,0.4907, 0.3161,1.0198,3.7946},{"Skin_Body_Barrel", 0.0015,0.5259,2.3367, 0.1302,0.1257,0.7734},{"Magazine", -0.0013,-0.1362,0.6858, 0.1792,0.6611,0.4411},{"Pivot_Magazine", -0.0000,0.1522,0.6522, 0.0600,0.0600,0.0600},{"Point_Eject", -0.0978,0.5870,0.1087, 0.0400,0.0400,0.0400},{"Point_Grip", -0.0000,0.0000,-0.0000, 0.0400,0.0400,0.0400},{"Point_LeftHand", -0.0000,0.4131,1.5871, 0.0400,0.0400,0.0400},{"Point_LeftHandTP", -0.0000,0.4131,1.1305, 0.0400,0.0400,0.0400},{"Point_Muzzle", -0.0000,0.5261,2.7234, 0.0400,0.0400,0.0400},{"Point_SightFront", -0.0000,0.7675,2.2459, 0.0400,0.0400,0.0400},{"Point_SightRear", -0.0000,0.7349,0.0435, 0.0400,0.0400,0.0400},{"Point_Stock", -0.0000,0.4022,-1.4066, 0.0400,0.0400,0.0400}}, CFrame.new(10, 4, -3) * CFrame.Angles(0, math.rad(180), 0))
build("HoloSight", att, {{"HoloSight", -0.0001,0.1582,-0.0000, 0.2616,0.3164,0.4558},{"Glass_Window", -0.0000,0.2236,-0.1022, 0.1344,0.1008,0.0010},{"Neon_Reticle", -0.0000,0.2236,-0.0998, 0.0581,0.0581,0.0012},{"Point_Mount", -0.0000,0.0000,-0.0000, 0.0200,0.0200,0.0200},{"Point_SightRear", -0.0000,0.2236,-0.1094, 0.0200,0.0200,0.0200},{"Point_SightFront", -0.0000,0.2236,0.1342, 0.0200,0.0200,0.0200}}, CFrame.new(-20, 1, 9) * CFrame.Angles(0, math.rad(180), 0))
build("Suppressor", att, {{"Suppressor", -0.0000,0.0000,0.4420, 0.2100,0.2088,0.8840},{"Point_Mount", -0.0000,0.0000,0.1700, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.0000,0.8840, 0.0300,0.0300,0.0300}}, CFrame.new(5, 8, 2) * CFrame.Angles(0, math.rad(180), 0))
build("AngledGrip", att, {{"AngledGrip_01", -0.0267,-0.3187,-0.1303, 0.1038,0.0637,0.1576},{"AngledGrip_02", -0.0237,-0.2850,-0.1208, 0.0965,0.0142,0.1556},{"AngledGrip_03", -0.0229,-0.2734,-0.1074, 0.0960,0.0211,0.1634},{"AngledGrip_04", -0.0214,-0.2583,-0.0910, 0.0955,0.0291,0.1804},{"AngledGrip_05", -0.0204,-0.2448,-0.0774, 0.0946,0.0190,0.1829},{"AngledGrip_06", -0.0185,-0.2290,-0.0632, 0.0957,0.0267,0.2008},{"AngledGrip_07", -0.0174,-0.2144,-0.0502, 0.0942,0.0220,0.1983},{"AngledGrip_08", -0.0162,-0.1995,-0.0377, 0.0941,0.0270,0.2169},{"AngledGrip_09", -0.0146,-0.1866,-0.0221, 0.0926,0.0262,0.2242},{"AngledGrip_10", -0.0141,-0.1733,-0.0120, 0.0919,0.0222,0.2305},{"AngledGrip_11", -0.0121,-0.1596,0.0036, 0.0916,0.0287,0.2428},{"AngledGrip_12", -0.0111,-0.1454,0.0151, 0.0918,0.0212,0.2437},{"AngledGrip_13", -0.0096,-0.1325,0.0286, 0.0921,0.0258,0.2604},{"AngledGrip_14", 0.0014,-0.1046,0.0453, 0.1110,0.0482,0.3044},{"AngledGrip_15", 0.0025,-0.0708,0.0326, 0.1323,0.0348,0.3421},{"AngledGrip_16", 0.0043,-0.0593,0.0321, 0.1445,0.0182,0.3417},{"AngledGrip_17", 0.0010,-0.0402,0.0347, 0.1543,0.0419,0.3475},{"AngledGrip_18", 0.0010,-0.0361,0.0348, 0.1543,0.0338,0.3477},{"AngledGrip_19", 0.0009,-0.0220,0.0348, 0.1540,0.0215,0.3477},{"AngledGrip_20", 0.0003,-0.0131,0.0353, 0.1502,0.0261,0.3487},{"Point_Mount", -0.0000,0.0000,-0.0000, 0.0200,0.0200,0.0200},{"Point_Front", -0.0000,0.0000,0.2096, 0.0200,0.0200,0.0200}}, CFrame.new(3, 3, 3) * CFrame.Angles(0, math.rad(180), 0))
-- 60er-Magazin (art/sources/Attachments/ExtendedMag.glb): Point_Mount = Mitte des eingebauten AR-Magazins, 0,07 tiefer
-- im Schacht (SEAT_UP in mag_full.py)
build("ExtendedMag", att, {{"Magazine_Ext_01", -0.0013,0.0550,0.6380, 0.1600,0.3000,0.3900},{"Magazine_Ext_02", -0.0013,-0.6000,0.7900, 0.1600,1.1000,0.4500},{"Point_Mount", -0.0013,-0.2004,0.7202, 0.0300,0.0300,0.0300},{"Point_Front", -0.0013,-0.2004,1.0202, 0.0300,0.0300,0.0300}}, CFrame.new(-7, 2, 12) * CFrame.Angles(0, math.rad(180), 0))
-- Kompensator (art/sources/Attachments/Compensator.glb): Point_Mount = AR-Mündung, Körper reicht 0,28 dahinter
build("Compensator", att, {{"Compensator", -0.0000,0.5261,2.6769, 0.1500,0.1500,0.4670},{"Point_Mount", -0.0000,0.5261,2.7234, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.5261,2.9105, 0.0300,0.0300,0.0300}}, CFrame.new(-4, 6, -9) * CFrame.Angles(0, math.rad(180), 0))
-- Mündungsbremse (art/sources/Attachments/MuzzleBrake.glb): wie der Kompensator, 0,539 lang
build("MuzzleBrake", att, {{"MuzzleBrake", -0.0000,0.5261,2.7129, 0.1500,0.1460,0.5390},{"Point_Mount", -0.0000,0.5261,2.7234, 0.0300,0.0300,0.0300},{"Point_Muzzle", -0.0000,0.5261,2.9824, 0.0300,0.0300,0.0300}}, CFrame.new(8, -3, 4) * CFrame.Angles(0, math.rad(180), 0))
-- Langer Lauf (art/sources/Attachments/LongBarrel.glb): Point_Mount = eingebaute Mündung, Point_Muzzle = neue Mündung
build("LongBarrel", att, {{"LongBarrel", 0.0000,0.5261,2.4541, 0.1448,0.1389,1.2368},{"Point_Front", 0.0000,0.5261,3.0234, 0.0300,0.0300,0.0300},{"Point_Mount", 0.0000,0.5261,2.7234, 0.0300,0.0300,0.0300},{"Point_Muzzle", 0.0000,0.5261,3.0725, 0.0300,0.0300,0.0300}}, CFrame.new(-12, 5, 6) * CFrame.Angles(0, math.rad(180), 0))
-- Kurzer Lauf (art/sources/Attachments/ShortBarrel.glb): Mündung hinter der eingebauten
build("ShortBarrel", att, {{"Point_Front", 0.0000,0.5261,3.0234, 0.0300,0.0300,0.0300},{"Point_Mount", 0.0000,0.5261,2.7234, 0.0300,0.0300,0.0300},{"Point_Muzzle", 0.0000,0.5261,2.5999, 0.0300,0.0300,0.0300},{"ShortBarrel", 0.0000,0.5261,2.1240, 0.1600,0.1632,0.9518}}, CFrame.new(14, -2, -5) * CFrame.Angles(0, math.rad(180), 0))
-- Schwerer Lauf (art/sources/Attachments/HeavyBarrel.glb)
build("HeavyBarrel", att, {{"HeavyBarrel", 0.0000,0.5261,2.2576, 0.1993,0.2023,1.0844},{"Point_Front", 0.0000,0.5261,3.0234, 0.0300,0.0300,0.0300},{"Point_Mount", 0.0000,0.5261,2.7234, 0.0300,0.0300,0.0300},{"Point_Muzzle", 0.0000,0.5261,2.7998, 0.0300,0.0300,0.0300}}, CFrame.new(3, 9, -14) * CFrame.Angles(0, math.rad(180), 0))
-- Vertikalgriff (art/sources/Attachments/VerticalGrip.glb): Oberkante der Klemme an Point_LeftHand
build("VerticalGrip", att, {{"Point_Front", 0.0000,0.4131,1.7871, 0.0200,0.0200,0.0200},{"Point_Mount", 0.0000,0.4131,1.5871, 0.0200,0.0200,0.0200},{"VerticalGrip", -0.0000,0.1831,1.5871, 0.1333,0.4600,0.1739}}, CFrame.new(-6, 11, 2) * CFrame.Angles(0, math.rad(180), 0))
-- Laser (art/sources/Attachments/Laser.glb, 47 Teile – hier vorderes, mittleres, hinteres): rechts am Handschutz
build("Laser", att, {{"Laser_01", -0.2454,0.5330,2.3204, 0.1503,0.1076,0.0192},{"Laser_24", -0.2604,0.5417,2.0364, 0.1742,0.1960,0.0351},{"Laser_47", -0.2647,0.5430,1.9180, 0.0790,0.0488,0.0084},{"Point_Front", 0.0000,0.4131,1.7871, 0.0200,0.0200,0.0200},{"Point_Mount", 0.0000,0.4131,1.5871, 0.0200,0.0200,0.0200}}, CFrame.new(9, 1, -7) * CFrame.Angles(0, math.rad(180), 0))
-- Schnellmagazin (art/sources/Attachments/FastMag.glb): 30er mit Zugschlaufe, sitzt wie das 60er tief im Schacht
build("FastMag", att, {{"Magazine_Fast_01", 0.0021,-0.2993,0.7507, 0.1208,0.9539,0.4598},{"Point_Front", -0.0013,-0.1940,1.0495, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0013,-0.1940,0.7495, 0.0300,0.0300,0.0300}}, CFrame.new(4, -6, 9) * CFrame.Angles(0, math.rad(180), 0))
-- Trommelmagazin (art/sources/Attachments/DrumMag.glb): Hals im Schacht, Trommel darunter
build("DrumMag", att, {{"Magazine_Drum_01", -0.0155,-0.3941,0.7865, 0.4408,1.1242,0.7347},{"Point_Front", -0.0013,-0.1906,1.0180, 0.0300,0.0300,0.0300},{"Point_Mount", -0.0013,-0.1906,0.7180, 0.0300,0.0300,0.0300}}, CFrame.new(-3, 7, 15) * CFrame.Angles(0, math.rad(180), 0))
local GunModels = require("GunModels")
local plain = GunModels.AimOffset("Rifle")
local aim = GunModels.AimOffset("Rifle", { "HoloSight", "Suppressor" })
print("HINWEIS Zielen ohne Visier " .. tostring(plain.Position) .. ", mit Holo " .. tostring(aim.Position))
check(aim.Position.Y < plain.Position.Y - 0.1, "Holo: Visierlinie hoeher als Kimme und Korn")
local built = GunModels.Build("Rifle", nil, { "HoloSight", "Suppressor" })
local handle = built.PrimaryPart
local holo = built:FindFirstChild("AttHoloSight_HoloSight")
local ret = built:FindFirstChild("AttHoloSight_Neon_Reticle")
check(holo and ret, "Holo-Teile angebaut")
check(built:FindFirstChild("AttHoloSight_Point_Mount") == nil, "keine Marker")
check(built:FindFirstChild("AttSuppressor_Suppressor") ~= nil, "Schalldaempfer weiter da")
if ret then
	local r = handle.CFrame:ToObjectSpace(ret.CFrame).Position
	print("HINWEIS Absehen relativ zum Griff " .. tostring(r))
	-- Absehen muss genau auf der Ziellinie liegen: x = 0, y = -aim.Y
	check(math.abs(r.X) < 0.01 and math.abs(r.Y + aim.Position.Y) < 0.01, "Absehen auf der Ziellinie")
	check(ret.Material == Enum.Material.Neon, "Absehen leuchtet")
end
local glass = built:FindFirstChild("AttHoloSight_Glass_Window")
check(glass and glass.Material == Enum.Material.Glass, "Glas")
local pistol = GunModels.Build("Pistol", nil, { "HoloSight" })
check(pistol:FindFirstChild("AttHoloSight_HoloSight") == nil, "Pistole ohne Holo")
local g = GunModels.Build("Rifle", nil, { "AngledGrip" })
check(g:FindFirstChild("AttAngledGrip") == nil, "kein Klotz-Griff")
local top, bottom, n = -math.huge, math.huge, 0
for _, p in g:GetChildren() do
	if string.match(p.Name, "^AttAngledGrip_") then
		n += 1
		local r = g.PrimaryPart.CFrame:ToObjectSpace(p.CFrame).Position
		top = math.max(top, r.Y + p.Size.Y / 2) bottom = math.min(bottom, r.Y - p.Size.Y / 2)
	end
end
print("HINWEIS Griff: " .. n .. " Teile, oben " .. top .. ", unten " .. bottom)
print("HINWEIS LeftHand " .. tostring(GunModels.Info.Rifle.LeftHand))
check(n == 20 and math.abs(top - GunModels.Info.Rifle.LeftHand.Y) < 0.01 and bottom < 0.1, "Griff unter dem Handschutz")
-- Erweitertes Magazin: ersetzt das eingebaute Magazin, sitzt an dessen Stelle, wandert beim Nachladen mit
local base = GunModels.Build("Rifle", nil, {})
local baseMag = base:FindFirstChild("Magazine")
local m = GunModels.Build("Rifle", nil, { "ExtendedMag" })
local ext1, ext2 = m:FindFirstChild("AttExtendedMag_Magazine_Ext_01"), m:FindFirstChild("AttExtendedMag_Magazine_Ext_02")
check(baseMag ~= nil and m:FindFirstChild("Magazine") == nil, "eingebautes Magazin nicht ersetzt")
check(ext1 and ext2 and ext1:GetAttribute("Group") == "Magazine" and ext2:GetAttribute("Group") == "Magazine",
	"Magazin-Aufsatz nicht in der Gruppe Magazine")
check(m:FindFirstChild("AttExtendedMag_Point_Mount") == nil, "Marker angebaut")
if baseMag and ext1 and ext2 then
	-- Abstand Aufsatzteil -> eingebautes Magazin wie im Modell (Point_Mount = Mitte des eingebauten Magazins)
	local function rel(part)
		return base.PrimaryPart.CFrame:ToObjectSpace(baseMag.CFrame):PointToObjectSpace(
			base.PrimaryPart.CFrame * m.PrimaryPart.CFrame:PointToObjectSpace(part.Position))
	end
	local r1, r2 = rel(ext1), rel(ext2)
	print("HINWEIS Magazin oben " .. tostring(r1) .. ", unten " .. tostring(r2))
	check(math.abs(r1.X) < 0.01 and r1.Y > 0.1 and r2.Y < -0.3, "Magazin-Aufsatz sitzt nicht im Schacht")
	check(r2.Y < r1.Y and math.abs(r2.Z - r1.Z) < 0.3, "Magazin-Aufsatz verdreht")
end
check(GunModels.Build("Pistol", nil, { "ExtendedMag" }):FindFirstChild("AttExtendedMag_Magazine_Ext_01") == nil,
	"Quader-Waffe bekommt das AR-Magazin")
-- Mündungsaufsätze: 3D-Modell statt Klotz, an der Mündung (reicht 0,28 dahinter), Laufrichtung
for _, case in { { "Compensator", 0.467, "AttCompensator" }, { "MuzzleBrake", 0.539, "AttBrake" } } do
	local id, length, block = case[1], case[2], case[3]
	local c = GunModels.Build("Rifle", nil, { id })
	local part = c:FindFirstChild("Att" .. id .. "_" .. id)
	check(part ~= nil and c:FindFirstChild(block) == nil, id .. ": Modell nicht angebaut")
	check(c:FindFirstChild("Att" .. id .. "_Point_Muzzle") == nil, id .. ": Marker angebaut")
	if part then
		local r = c.PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
		local muzzle = GunModels.Info.Rifle.Muzzle
		local want = muzzle + Vector3.new(0, 0, 0.28 - length / 2)
		print("HINWEIS " .. id .. " " .. tostring(r.Position) .. ", soll " .. tostring(want))
		check((r.Position - want).Magnitude < 0.01, id .. " sitzt nicht an der Muendung")
		check(math.abs(r.LookVector:Dot(Vector3.zAxis)) > 0.999 and r.UpVector.Y > 0.999, id .. " verdreht")
	end
end
-- Lauf-Aufsätze: eingebauter Lauf weg, neuer Lauf auf der Laufachse, Mündung (und Mündungsaufsätze) vorn am neuen Lauf
for _, case in { { "LongBarrel", 3.0725 - 2.7234 }, { "ShortBarrel", 2.5999 - 2.7234 }, { "HeavyBarrel", 2.7998 - 2.7234 } } do
	local id, ahead = case[1], case[2]
	local b = GunModels.Build("Rifle", nil, { id })
	local part = b:FindFirstChild("Att" .. id .. "_" .. id)
	local muzzle = GunModels.Info.Rifle.Muzzle
	check(part ~= nil, id .. ": Modell nicht angebaut")
	check(b:FindFirstChild("Skin_Body_Barrel") == nil, id .. ": eingebauter Lauf noch da")
	check(GunModels.Build("Rifle", nil, {}):FindFirstChild("Skin_Body_Barrel") ~= nil, "ohne Lauf-Aufsatz fehlt der eingebaute Lauf")
	local shifted = b:GetAttribute("Muzzle")
	check(typeof(shifted) == "Vector3", id .. ": Muendung nicht verschoben")
	if part and typeof(shifted) == "Vector3" then
		-- neue Mündung liegt auf der Achse des alten Laufs (Richtung alte Mündung -> Lauf-Teil nach vorn)
		local axis = (shifted - muzzle)
		local forward = axis.Unit * math.sign(ahead) -- kurzer Lauf: neue Mündung liegt hinter der alten
		print("HINWEIS " .. id .. " Muendung " .. tostring(shifted) .. ", eingebaut " .. tostring(muzzle))
		check(math.abs(axis.Magnitude - math.abs(ahead)) < 0.01 and forward.Z < -0.999, id .. ": Muendung nicht auf der Laufachse")
		local r = b.PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
		local off = (r.Position - muzzle)
		local side = off - forward * off:Dot(forward)
		check(side.Magnitude < 0.005, id .. ": Lauf nicht auf der Laufachse")
		check(math.abs(r.LookVector:Dot(forward)) > 0.9999, id .. ": Lauf nicht parallel zur Laufachse")
		local tool = GunModels.BuildTool("Rifle", "Rifle", nil, { id })
		check(tool:GetAttribute("Muzzle") == shifted, id .. ": Tool ohne Muendung")
		check(GunModels.MuzzleOf("Rifle", tool) == shifted and GunModels.MuzzleOf("Rifle", nil) == muzzle, id .. ": MuzzleOf")
		-- Mündungsaufsatz sitzt an der neuen Mündung
		local cb = GunModels.Build("Rifle", nil, { id, "Compensator" })
		local comp = cb:FindFirstChild("AttCompensator_Compensator")
		if comp then
			local rc = cb.PrimaryPart.CFrame:ToObjectSpace(comp.CFrame).Position
			local want = shifted + forward * (0.467 / 2 - 0.28)
			check((rc - want).Magnitude < 0.01, id .. ": Kompensator nicht an der neuen Muendung")
		else
			check(false, id .. ": Kompensator fehlt")
		end
	end
end
-- Vertikalgriff: Klemme bündig unter dem Handschutz an der linken Hand, mittig, senkrecht nach unten
do
	local v = GunModels.Build("Rifle", nil, { "VerticalGrip" })
	local grip = v:FindFirstChild("AttVerticalGrip_VerticalGrip")
	check(grip ~= nil and v:FindFirstChild("AttGrip") == nil, "Vertikalgriff-Modell nicht angebaut")
	if grip then
		local r = v.PrimaryPart.CFrame:ToObjectSpace(grip.CFrame)
		local hand = GunModels.Info.Rifle.LeftHand
		local top = r.Position.Y + 0.46 / 2
		print("HINWEIS Vertikalgriff " .. tostring(r.Position) .. ", oben " .. top .. ", LeftHand " .. tostring(hand))
		check(math.abs(r.Position.X) < 0.01 and math.abs(top - hand.Y) < 0.01 and math.abs(r.Position.Z - hand.Z) < 0.03,
			"Vertikalgriff sitzt nicht unter dem Handschutz an der linken Hand")
	end
end
-- Laser: 3D-Modell statt Klotz, rechts neben dem Handschutz (Klemme an der Seitenfläche x 0,108), vor der linken Hand
do
	local l = GunModels.Build("Rifle", nil, { "Laser" })
	local front, back = l:FindFirstChild("AttLaser_Laser_01"), l:FindFirstChild("AttLaser_Laser_47")
	check(front and back and l:FindFirstChild("AttLaser") == nil and l:FindFirstChild("AttLaserDot") == nil,
		"Laser-Modell nicht angebaut")
	if front and back then
		local f = l.PrimaryPart.CFrame:ToObjectSpace(front.CFrame).Position
		local b = l.PrimaryPart.CFrame:ToObjectSpace(back.CFrame).Position
		local hand = GunModels.Info.Rifle.LeftHand
		print("HINWEIS Laser vorn " .. tostring(f) .. ", hinten " .. tostring(b))
		check(f.X > 0.15 and b.X > 0.15, "Laser nicht rechts neben dem Handschutz")
		check(f.Z < b.Z and b.Z < hand.Z - 0.2 and f.Z > GunModels.Info.Rifle.Muzzle.Z, "Laser nicht vor der linken Hand")
	end
end
-- Schnellmagazin: ersetzt das eingebaute Magazin (statt zwei zusammengeklebter Klötze), wandert beim Nachladen mit
do
	local base = GunModels.Build("Rifle", nil, {})
	local f = GunModels.Build("Rifle", nil, { "FastMag" })
	local part = f:FindFirstChild("AttFastMag_Magazine_Fast_01")
	check(part ~= nil and f:FindFirstChild("Magazine") == nil and f:FindFirstChild("AttTwinMag") == nil,
		"Schnellmagazin-Modell nicht angebaut")
	if part then
		check(part:GetAttribute("Group") == "Magazine", "Schnellmagazin nicht in der Gruppe Magazine")
		local mag = base:FindFirstChild("Magazine")
		local r = mag.CFrame:PointToObjectSpace(part.Position)
		print("HINWEIS Schnellmagazin relativ zum eingebauten " .. tostring(r))
		-- Mitte wie im Modell: 0,1 unter der Mitte des eingebauten Magazins, mittig, kaum vor/zurück
		check(math.abs(r.X) < 0.01 and r.Y < -0.05 and math.abs(r.Z) < 0.1, "Schnellmagazin sitzt nicht im Schacht")
	end
end
-- Trommelmagazin: ersetzt das eingebaute Magazin (statt Zylinder-Klotz), hängt mittig darunter
do
	local base = GunModels.Build("Rifle", nil, {})
	local d = GunModels.Build("Rifle", nil, { "DrumMag" })
	local part = d:FindFirstChild("AttDrumMag_Magazine_Drum_01")
	check(part ~= nil and d:FindFirstChild("Magazine") == nil and d:FindFirstChild("AttDrum") == nil,
		"Trommelmagazin-Modell nicht angebaut")
	if part then
		check(part:GetAttribute("Group") == "Magazine", "Trommelmagazin nicht in der Gruppe Magazine")
		local r = base:FindFirstChild("Magazine").CFrame:PointToObjectSpace(part.Position)
		print("HINWEIS Trommelmagazin relativ zum eingebauten " .. tostring(r))
		check(math.abs(r.X) < 0.02 and r.Y < -0.2, "Trommelmagazin sitzt nicht unter dem Schacht")
	end
end
if failures == 0 then print("HINWEIS alles ok") end

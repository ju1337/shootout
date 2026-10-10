-- Waffen-Lader (GunModels): 3D-Modelle aus ReplicatedStorage.Assets.Weapons statt der Quader-Waffen.
-- Simuliert werden Modelle direkt nach dem Import aus Blender: beliebig gedreht und verschoben, Teile teils in
-- Untermodellen, Marker als kleine Teile oder Attachments. Geprüft: Ausrichtung und Punkte aus den Markern,
-- Ruhelage, Gruppen, Drehpunkte, Skin-Zonen und Textur-Skins, Aufsätze, Werkzeug, Zielen über die Visierlinie,
-- Nachlade-Animation – und dass kaputte Modelle mit verständlicher Meldung bei der Quader-Waffe bleiben.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, eps)
	if typeof(a) == "Vector3" then
		return (a - b).Magnitude < (eps or 1e-6)
	end
	return math.abs(a - b) < (eps or 1e-6)
end
local function anyContains(list, text)
	for _, line in list or {} do
		if string.find(line, text, 1, true) then
			return true
		end
	end
	return false
end

-- Nur die Modelle dieses Tests (echte Modelle aus assets/ prüft weaponassets.test.luau)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local folder = ReplicatedStorage.Assets.Weapons
for _, child in folder:GetChildren() do
	child:Destroy()
end

-- Import in Studio: Lage und Drehung beliebig (hier: gekippt wie aus Blender, irgendwo im Raum)
local IMPORT = CFrame.new(37, -5, 12) * CFrame.Angles(math.rad(90), math.rad(30), math.rad(-12))

local function model(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent or folder
	return m
end
local function mesh(parent, name, size, rest, color, import)
	local p = Instance.new("MeshPart")
	p.Name = name
	p.Size = size
	p.CFrame = (import or IMPORT) * rest
	p.Color = color or Color3.fromRGB(60, 60, 60)
	p.Parent = parent
	return p
end
local function marker(parent, name, position, import)
	return mesh(parent, name, Vector3.new(0.05, 0.05, 0.05), CFrame.new(position), nil, import)
end

-- ---------- Sturmgewehr: vollständig, mit Untermodell, Glas, Textur-Skin ----------
local RIFLE = {
	SightRear = Vector3.new(0, 0.9, -0.3), SightFront = Vector3.new(0, 0.9, -0.5), Muzzle = Vector3.new(0, 0.48, -2.7),
	Eject = Vector3.new(0.18, 0.47, -0.3), LeftHand = Vector3.new(-0.03, 0.27, -1.55), Stock = Vector3.new(0, 0.35, 1.4),
	BoltPivot = Vector3.new(0, 0.6, 0.7),
}
local MAG_REST = CFrame.new(0, -0.08, -0.65) * CFrame.Angles(math.rad(10), 0, 0)
local rifle = model("Rifle")
mesh(rifle, "Skin_Receiver", Vector3.new(0.35, 0.45, 1.8), CFrame.new(0, 0.4, -0.35))
local barrelGroup = model("Laufgruppe", rifle) -- Untermodell aus dem Import
mesh(barrelGroup, "Barrel", Vector3.new(0.14, 0.14, 0.6), CFrame.new(0, 0.48, -2.25))
mesh(barrelGroup, "Handguard.001", Vector3.new(0.3, 0.32, 0.75), CFrame.new(0, 0.44, -1.6))
mesh(rifle, "Stock_Skin", Vector3.new(0.3, 0.5, 0.9), CFrame.new(0, 0.35, 0.95))
mesh(rifle, "Magazine", Vector3.new(0.24, 0.62, 0.34), MAG_REST)
mesh(rifle, "Magazine_Rounds", Vector3.new(0.1, 0.05, 0.25), CFrame.new(0, 0.2, -0.65))
mesh(rifle, "Bolt", Vector3.new(0.22, 0.06, 0.1), CFrame.new(0, 0.6, 0.6))
mesh(rifle, "Optic", Vector3.new(0.2, 0.075, 0.34), CFrame.new(0, 0.77, -0.13))
mesh(rifle, "Glass_Optic", Vector3.new(0.26, 0.21, 0.008), CFrame.new(0, 0.9, -0.36))
local receiverDefault = Instance.new("SurfaceAppearance")
receiverDefault.Name = "Standard"
receiverDefault.Parent = rifle:FindFirstChild("Skin_Receiver")
marker(rifle, "Point_Grip", Vector3.zero)
marker(rifle, "Point_SightRear", RIFLE.SightRear)
marker(rifle, "Point_SightFront", RIFLE.SightFront)
marker(rifle, "Point_Muzzle", RIFLE.Muzzle)
marker(rifle, "Point_Eject", RIFLE.Eject)
marker(rifle, "Point_LeftHand", RIFLE.LeftHand)
marker(rifle, "Point_Stock", RIFLE.Stock)
marker(rifle, "Pivot_Bolt", RIFLE.BoltPivot)
marker(rifle, "Point_Muzle", Vector3.new(0, 0, -3)) -- Tippfehler: wird gemeldet
local skins = Instance.new("Folder")
skins.Name = "Skins"
skins.Parent = rifle
local lava = Instance.new("Folder")
lava.Name = "W_Lava"
lava.Parent = skins
local lavaTexture = Instance.new("SurfaceAppearance")
lavaTexture.Name = "Skin_Receiver"
lavaTexture.Parent = lava
local wrong = Instance.new("SurfaceAppearance")
wrong.Name = "Skin_Gibtsnicht"
wrong.Parent = lava
-- Grundtextur der Farb-Skins (Skins/Farbe): durchsichtige Farbflächen, die Skin-Farbe scheint durch
local colorBase = Instance.new("Folder")
colorBase.Name = "Farbe"
colorBase.Parent = skins
local overlay = Instance.new("SurfaceAppearance")
overlay.Name = "Skin_Receiver"
overlay:SetAttribute("Overlay", true)
overlay.Parent = colorBase

-- ---------- Revolver: Marker als Attachments, Drehpunkt der Trommel als Attachment ----------
local revolverImport = CFrame.new(-4, 20, 3) * CFrame.Angles(0, math.rad(-90), 0)
local revolver = model("Revolver")
local frame = mesh(revolver, "Skin_Frame", Vector3.new(0.25, 0.3, 0.6), CFrame.new(0, 0.38, -0.15), nil, revolverImport)
mesh(revolver, "Cylinder_Skin", Vector3.new(0.32, 0.32, 0.35), CFrame.new(0, 0.38, -0.25), nil, revolverImport)
mesh(revolver, "Hammer", Vector3.new(0.06, 0.1, 0.1), CFrame.new(0, 0.5, 0.15), nil, revolverImport)
mesh(revolver, "Loader", Vector3.new(0.12, 0.3, 0.3), CFrame.new(-0.28, 0.28, 0), nil, revolverImport)
mesh(revolver, "Barrel", Vector3.new(0.14, 0.14, 0.75), CFrame.new(0, 0.43, -0.8), nil, revolverImport)
mesh(revolver, "Grip", Vector3.new(0.22, 0.55, 0.3), CFrame.new(0, -0.02, 0.06), nil, revolverImport)
mesh(revolver, "Neon_FrontDot", Vector3.new(0.037, 0.025, 0.06), CFrame.new(0, 0.5875, -1.08), nil, revolverImport)
local frameWorld = revolverImport * CFrame.new(0, 0.38, -0.15)
local function attach(name, position)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = CFrame.new(frameWorld:PointToObjectSpace(revolverImport * position))
	a.Parent = frame
end
attach("Grip", Vector3.zero)
attach("SightRear", Vector3.new(0, 0.6, 0.08))
attach("SightFront", Vector3.new(0, 0.6, -1.08))
attach("Muzzle", Vector3.new(0, 0.43, -1.175))
attach("Eject", Vector3.new(0, 0.38, -0.25))
attach("LeftHand", Vector3.new(-0.12, -0.1, 0.03))
attach("Pivot_Cylinder", Vector3.new(0, 0.3, -0.1))

-- ---------- Kaputte Modelle ----------
local smg = model("SMG") -- Visier vorne fehlt
mesh(smg, "Body", Vector3.new(0.3, 0.4, 1.2), CFrame.new(0, 0.38, -0.2))
marker(smg, "Point_Grip", Vector3.zero)
marker(smg, "Point_SightRear", Vector3.new(0, 0.76, 0.3))
local dmr = model("DMR") -- 100-mal zu groß (Einheit beim Import)
local big = CFrame.new(0, 0, 0)
local function bigMesh(name, size, position)
	local p = Instance.new("MeshPart")
	p.Name = name
	p.Size = size * 100
	p.CFrame = big * CFrame.new(position * 100)
	p.Parent = dmr
end
bigMesh("Body", Vector3.new(0.32, 0.42, 3.4), Vector3.new(0, 0.4, -0.6))
for name, position in { Point_Grip = Vector3.zero, Point_SightRear = Vector3.new(0, 0.88, 0.15),
	Point_SightFront = Vector3.new(0, 0.88, -2.65), Point_Muzzle = Vector3.new(0, 0.46, -3.07),
	Point_Eject = Vector3.new(0.17, 0.48, -0.25), Point_LeftHand = Vector3.new(-0.03, 0.18, -1.2),
	Point_Stock = Vector3.new(0, 0.35, 1.5) } do
	bigMesh(name, Vector3.new(0.05, 0.05, 0.05), position)
end
local pistol = model("Pistol") -- Kimme und Korn vertauscht: Lauf zeigt nach hinten
mesh(pistol, "Slide_Skin", Vector3.new(0.25, 0.28, 0.95), CFrame.new(0, 0.38, -0.25))
marker(pistol, "Point_Grip", Vector3.zero)
marker(pistol, "Point_SightRear", Vector3.new(0, 0.6, -0.66))
marker(pistol, "Point_SightFront", Vector3.new(0, 0.6, 0.17))
marker(pistol, "Point_Muzzle", Vector3.new(0, 0.4, -0.79))
marker(pistol, "Point_Eject", Vector3.new(0.14, 0.45, -0.15))
marker(pistol, "Point_LeftHand", Vector3.new(-0.12, -0.1, 0.02))
local shotgun = model("Shotgun") -- vollständig, aber ohne Pumpe und Patrone
mesh(shotgun, "Body", Vector3.new(0.35, 0.4, 1.2), CFrame.new(0, 0.38, -0.3))
mesh(shotgun, "Barrel", Vector3.new(0.2, 0.2, 1.55), CFrame.new(0, 0.52, -1.675))
mesh(shotgun, "Stock", Vector3.new(0.3, 0.5, 1.0), CFrame.new(0, 0.3, 1.0))
for name, position in { Point_Grip = Vector3.zero, Point_SightRear = Vector3.new(0, 0.71, 0.18),
	Point_SightFront = Vector3.new(0, 0.71, -2.38), Point_Muzzle = Vector3.new(0, 0.52, -2.45),
	Point_Eject = Vector3.new(0.18, 0.42, -0.35), Point_LeftHand = Vector3.new(-0.02, 0.2, -1.35),
	Point_Stock = Vector3.new(0, 0.3, 1.5) } do
	marker(shotgun, name, position)
end
model("Sturmgewehr") -- falscher Name

-- ---------- Laden ----------
local GunModels = require("GunModels")
local report = GunModels.AssetReport()
local info = GunModels.Info.Rifle

check(GunModels.HasAsset("Rifle") and report.Rifle.Loaded, "Sturmgewehr geladen: " .. table.concat(report.Rifle.Errors, "; "))
check(near(info.SightHeight, 0.9) and near(info.SightZ, -0.3) and near(info.SightFrontZ, -0.5),
	string.format("Visierlinie aus den Markern: Höhe %.4f, Kimme %.4f", info.SightHeight, info.SightZ))
check(near(info.Muzzle, RIFLE.Muzzle) and near(info.Eject, RIFLE.Eject) and near(info.LeftHand, RIFLE.LeftHand)
	and near(info.Stock, RIFLE.Stock), "Mündung, Auswurf, linke Hand, Schaft im Waffenraum")
check(near(info.LeftHandTP, info.LeftHand), "ohne Point_LeftHandTP: wie die linke Hand")
check(near(info.RightHand, Vector3.zero), "rechte Hand = Griff = Ursprung")
check(info.Reflex == true and info.Long == true and info.EyeRelief == 1.08, "Einstellungen aus dem Code bleiben")
check(anyContains(report.Rifle.Warnings, "Point_Muzle"), "Tippfehler im Marker wird gemeldet")
check(anyContains(report.Rifle.Warnings, "Skin_Gibtsnicht"), "Textur für ein fehlendes Teil wird gemeldet")

-- Gebautes Modell: Ruhelage wie in Blender gedacht, flach, Marker weg, Attribute
local built = GunModels.Build("Rifle")
check(built.PrimaryPart and built.PrimaryPart.Name == "Handle" and near(built.PrimaryPart.Position, Vector3.zero),
	"Handle am Ursprung")
local receiver = built:FindFirstChild("Skin_Receiver")
check(receiver and near(receiver.Position, Vector3.new(0, 0.4, -0.35))
	and near(receiver.CFrame.LookVector, Vector3.new(0, 0, -1)), "Import-Drehung herausgerechnet")
check(near(built.Magazine.CFrame.UpVector, MAG_REST.UpVector), "gekipptes Magazin behält seine Neigung")
check(built:FindFirstChild("Barrel") and built.Barrel.Parent == built, "Teile aus Untermodellen liegen direkt im Modell")
check(built:FindFirstChild("Handguard") ~= nil, "Blender-Endung .001 entfernt")
for _, part in built:GetChildren() do
	check(not string.find(part.Name, "^Point_") and not string.find(part.Name, "^Pivot_"), "Marker im Spielmodell: " .. part.Name)
	if part:IsA("BasePart") then
		check(part.Anchored and not part.CanCollide and not part.CanQuery and part:GetAttribute("Rest") ~= nil,
			part.Name .. ": verankert, ohne Kollision, mit Ruhelage")
	end
end
check(built:FindFirstChild("Skins") == nil, "Skin-Ordner nicht im Spielmodell")
check(built.Magazine:GetAttribute("Group") == "Magazine" and built.Magazine_Rounds:GetAttribute("Group") == "Magazine",
	"Gruppe aus dem Namen")
check(built.Bolt:GetAttribute("Group") == "Bolt" and built.Stock_Skin:GetAttribute("Skin") == true, "Gruppe und Skin-Zone")
check(built.Glass_Optic.Material == Enum.Material.Glass and near(built.Glass_Optic.Transparency, 0.82), "Glas")
local reticle = built:FindFirstChild("Neon_Reticle")
check(reticle and reticle.Material == Enum.Material.Neon and near(reticle.Position, Vector3.new(0, 0.9, -0.3)),
	"roter Punkt automatisch auf Point_SightRear")
check(GunModels.GroupMainPart("Rifle", "Magazine") == "Magazine", "Hauptteil = Teil mit dem Namen der Gruppe")
check(near(GunModels.GroupPivot("Rifle", "Magazine").Position, MAG_REST.Position), "Drehpunkt Magazin = Magazin-Mitte")
check(near(GunModels.GroupPivot("Rifle", "Bolt").Position, RIFLE.BoltPivot), "Drehpunkt aus Pivot_Bolt")
check(near(GunModels.Rest("Rifle", "Bolt").Position, Vector3.new(0, 0.6, 0.6)), "Rest() aus dem Modell")

-- Skins: Farbe auf die Zonen, Textur ersetzt die SurfaceAppearance, Rest unverändert
local Cosmetics = require("Cosmetics")
local lavaSkin = Cosmetics.Get("W_Lava")
local skinned = GunModels.Build("Rifle", lavaSkin)
local appearances = {}
for _, child in skinned.Skin_Receiver:GetChildren() do
	if child:IsA("SurfaceAppearance") then
		table.insert(appearances, child.Name)
	end
end
check(#appearances == 1 and appearances[1] == "Skin_Receiver", "Textur-Skin ersetzt die Standard-Textur")
check(skinned.Skin_Receiver.Color == lavaSkin.Color, "Zone mit Textur bekommt die Skin-Farbe (scheint durch)")
check(skinned.Stock_Skin.Color == lavaSkin.Color and skinned.Stock_Skin.Material == lavaSkin.Material,
	"Zone ohne Textur: Farbe und Material des Skins")
check(skinned.Barrel.Color == built.Barrel.Color, "Teil ohne Skin-Zone bleibt")
check(skinned.Skin_Receiver:FindFirstChildOfClass("SurfaceAppearance"):GetAttribute("Overlay") == nil,
	"Skin mit eigener Textur nimmt nicht die Farb-Grundtextur")
local plain = GunModels.Build("Rifle", Cosmetics.Get("W_Wald"))
local plainLook = plain.Skin_Receiver:FindFirstChildOfClass("SurfaceAppearance")
check(plain.Skin_Receiver:FindFirstChild("Standard") == nil and plainLook and plainLook:GetAttribute("Overlay") == true,
	"Farb-Skin bekommt die Farb-Grundtextur statt der deckenden Standard-Textur")
check(plain.Skin_Receiver.Color == Cosmetics.Get("W_Wald").Color, "Farb-Skin: Farbe scheint durch")
check(built.Skin_Receiver:FindFirstChild("Standard") ~= nil, "ohne Skin: Standard-Textur (Vorlage unverändert)")

-- Aufsätze an den Punkten aus dem Modell
local equipped = GunModels.Build("Rifle", nil, { "Suppressor", "ExtendedMag" })
-- ohne fertige Aufsatz-Modelle (Assets.Attachments) bekommt eine 3D-Waffe keine Klötze: sie bleibt unverändert
check(equipped:FindFirstChild("AttSuppressor") == nil, "kein Schalldämpfer-Klotz am 3D-Modell")
check(equipped.Magazine.Size == built.Magazine.Size, "eingebautes Magazin bleibt ohne Magazin-Modell unverändert")

-- Werkzeug für die Hand: Teile an den Griff geschweißt, verkleinert
local tool = GunModels.BuildTool("Rifle", "Sturmgewehr")
local welded = 0
for _, part in tool:GetChildren() do
	if part:IsA("BasePart") and part:FindFirstChild("GunWeld") then
		welded += 1
	end
end
check(tool:FindFirstChild("Handle") and welded >= 9, "Werkzeug mit angeschweißten Teilen: " .. welded)

-- Ego-Waffe: beim Zielen liegt die Visierlinie des Modells genau in der Bildmitte
local ViewModel = require("ViewModel")
local camera = CFrame.new(5, 8, -2) * CFrame.Angles(-0.1, 0.7, 0)
local vm = ViewModel.new("Rifle", nil, Color3.fromRGB(80, 80, 80))
vm.DrawStart = os.clock() - 5
for _ = 1, 3 do
	vm:Update(1 / 60, { Camera = camera, Aim = 1, Sprinting = false, Speed = 0 })
end
local scale = ViewModel.Scale()
for _, z in { info.SightZ, info.SightFrontZ, info.SightZ - 1 } do
	local p = camera:PointToObjectSpace(vm.GunWorld * (Vector3.new(0, info.SightHeight, z) * scale))
	check(math.abs(p.X) < 1e-3 and math.abs(p.Y) < 1e-3 and p.Z < 0, string.format("Visierlinie bei z=%.2f mittig: (%.4f, %.4f)", z, p.X, p.Y))
end
local dot = camera:PointToObjectSpace(vm.Model.Neon_Reticle.Position)
check(math.abs(dot.X) < 1e-3 and math.abs(dot.Y) < 1e-3, "roter Punkt in der Bildmitte")

-- Nachlade-Animation: die Hand greift das Magazin des Modells
local WeaponAnimations = require("WeaponAnimations")
local WeaponConfig = require("WeaponConfig")
local anim = WeaponAnimations.Reload("Rifle", WeaponConfig.Get("Rifle").ReloadTime, 30)
local pose = WeaponAnimations.Sample(anim, "Rifle", 0.3)
check(pose.Hand and (pose.Hand.Position - MAG_REST.Position).Magnitude < 1.6, "Hand am Magazin beim Nachladen")
local rest = WeaponAnimations.Sample(anim, "Rifle", 1)
check(rest.Hand and near(rest.Hand.Position, info.LeftHand), "Hand am Ende wieder an Point_LeftHand")

-- Revolver: Marker als Attachments
check(GunModels.HasAsset("Revolver"), "Revolver mit Attachments geladen: " .. table.concat(report.Revolver.Errors, "; "))
local rinfo = GunModels.Info.Revolver
check(near(rinfo.SightHeight, 0.6) and near(rinfo.SightZ, 0.08) and near(rinfo.Muzzle, Vector3.new(0, 0.43, -1.175)),
	"Revolver-Punkte aus Attachments")
check(near(GunModels.GroupPivot("Revolver", "Cylinder").Position, Vector3.new(0, 0.3, -0.1)), "Drehpunkt aus Attachment")
local rbuilt = GunModels.Build("Revolver")
check(rbuilt.Loader:GetAttribute("Hidden") == true and rbuilt.Loader.Transparency == 1, "Schnelllader nur in der Animation")
check(rbuilt.Neon_FrontDot.Material == Enum.Material.Neon, "Leuchtpunkt")
check(rbuilt.Cylinder_Skin:GetAttribute("Group") == "Cylinder" and rbuilt.Cylinder_Skin:GetAttribute("Skin") == true,
	"Gruppe und Skin-Zone in einem Namen")
check(rbuilt:FindFirstChild("Neon_Reticle") == nil, "kein roter Punkt ohne Rotpunktvisier")

-- Kaputte Modelle: Quader-Waffe bleibt, Meldung sagt, was los ist
check(not GunModels.HasAsset("SMG") and anyContains(report.SMG.Errors, "Point_SightFront fehlt"), "fehlender Marker")
check(GunModels.Build("SMG"):FindFirstChild("FrontDot") ~= nil and near(GunModels.Info.SMG.SightHeight, 0.76),
	"SMG bleibt die Quader-Waffe")
check(not GunModels.HasAsset("DMR") and anyContains(report.DMR.Errors, "Einheit"), "100-mal zu groß: Hinweis auf die Einheit")
check(not GunModels.HasAsset("Pistol") and anyContains(report.Pistol.Errors, "vertauscht"), "Kimme/Korn vertauscht")
check(GunModels.HasAsset("Shotgun") and anyContains(report.Shotgun.Warnings, "Pump")
	and anyContains(report.Shotgun.Warnings, "Shell"), "fehlende Animationsgruppen als Hinweis")
check(report.Sturmgewehr and not report.Sturmgewehr.Loaded and anyContains(report.Sturmgewehr.Errors, "Rifle"),
	"falscher Name: erlaubte Namen werden genannt")
check(not GunModels.HasAsset("LMG") and GunModels.Build("LMG"):FindFirstChild("Box") ~= nil, "ohne Modell: Quader")

if failures == 0 then
	print("Waffen-Lader: alles in Ordnung")
end

--!assets tests/fixtures/assets
-- Modelle im Studio-Format (.rbxmx): tests/lib/rbxmx.py liest sie, die Test-Engine legt sie unter
-- ReplicatedStorage.Assets ab, GunModels lädt sie. Grundlage: tests/fixtures/assets/Weapons/Rifle.rbxmx, ein
-- Sturmgewehr wie nach einem Blender-Import gespeichert (gekippt und verschoben, Untermodell, Marker als Teile und
-- als Attachment, SurfaceAppearance, Textur-Skin).
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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local source = ReplicatedStorage.Assets.Weapons:FindFirstChild("Rifle")
check(source ~= nil and source:IsA("Model"), "Modell aus der Datei unter Assets.Weapons")

-- Eigenschaften aus der Datei
local receiver = source and source:FindFirstChild("Skin_Receiver")
check(receiver and receiver:IsA("MeshPart") and receiver:IsA("BasePart"), "MeshPart")
check(receiver and near(receiver.Size, Vector3.new(0.35, 0.45, 1.8)), "Größe")
check(receiver and receiver.Color == Color3.fromRGB(60, 62, 68) and receiver.Material == Enum.Material.Metal, "Farbe und Material")
check(receiver and receiver:FindFirstChildOfClass("SurfaceAppearance") ~= nil, "SurfaceAppearance")
check(source and source.Mesh:FindFirstChild("Handguard.001") ~= nil, "Untermodell mit Blender-Namen")
check(source and source.Glass_Optic.Transparency == 0.5, "Transparenz")
local attachment = source and source.Stock_Skin:FindFirstChild("Point_Stock")
check(attachment and attachment:IsA("Attachment"), "Attachment")
check(source and source.Skins.W_Lava.Skin_Receiver:IsA("SurfaceAppearance"), "Skin-Ordner")
-- Lage im Raum: Markerabstand wie im Waffenraum (Drehung erhält Abstände)
check(source and near((source.Point_Muzzle.Position - source.Point_Grip.Position).Magnitude,
	Vector3.new(0, 0.48, -2.6).Magnitude), "CFrame aus der Datei")

-- GunModels lädt das Modell
local GunModels = require("GunModels")
local report = GunModels.AssetReport().Rifle
check(GunModels.HasAsset("Rifle") and report and report.Loaded, "geladen: " .. (report and table.concat(report.Errors, "; ") or "-"))
local info = GunModels.Info.Rifle
check(near(info.SightHeight, 0.9) and near(info.SightZ, -0.36) and near(info.SightFrontZ, -0.6), "Visierlinie")
check(near(info.Muzzle, Vector3.new(0, 0.48, -2.6)) and near(info.LeftHand, Vector3.new(-0.03, 0.27, -1.55)), "Punkte")
check(near(info.Stock, Vector3.new(0, 0.35, 1.4)), "Schaft aus dem Attachment")
local built = GunModels.Build("Rifle", require("Cosmetics").Get("W_Lava"))
check(near(built.Magazine.CFrame.UpVector, (CFrame.Angles(math.rad(10), 0, 0)).UpVector), "Magazin-Neigung")
check(built.Glass_Optic.Transparency == 0.5, "eigene Transparenz des Glases bleibt")
check(built.Skin_Receiver:FindFirstChild("Skin_Receiver") ~= nil, "Textur-Skin aus der Datei")
check(built:FindFirstChild("Handguard") ~= nil, "Untermodell aufgelöst")

if failures == 0 then
	print("Studio-Modelle (.rbxmx): alles in Ordnung")
end

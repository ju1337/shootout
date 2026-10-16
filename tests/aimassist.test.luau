-- Zielhilfe für den Controller (AimAssist): Liegt ein sichtbarer Gegner dicht am Fadenkreuz, dreht der Stick langsamer
-- (beim Zielen noch etwas mehr); beim Anlegen zieht die Kamera in kurzer Zeit auf einen nahen Zombie, nie auf Spieler.
-- Nichts davon mit der Maus, in der Safe Zone, ohne Waffe, hinter einer Wand oder bei abgeschalteter Option.
-- Y-Achse umkehren dreht nur beim Controller das Nicken um.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local UserInputService = game:GetService("UserInputService")
SIM.IsServer = false
local bob = SIM.AddPlayer("Bob", 1001)
rawget(SIM.Players, "__props").LocalPlayer = bob
bob:SetAttribute("Mode", "Extinction")
bob:SetAttribute("InSafeZone", false)
local rig = SIM.MakeRig("Bob")
rig.Parent = workspace
bob.Character = rig
rig:PivotTo(CFrame.new(0, 3, 0))

local InputActions = require("InputActions")
local PlayerSettings = require("PlayerSettings")
local AimAssist = require("AimAssist")
InputActions.Init()
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
local drawn = true
AimAssist.WeaponDrawn = function()
	return drawn
end

local camera = workspace.CurrentCamera
camera.CFrame = CFrame.lookAt(Vector3.new(0, 5, 0), Vector3.new(0, 5, -100))

local zombies = Instance.new("Folder", workspace)
zombies.Name = "Zombies"
local zombie = SIM.MakeRig("Zombie")
zombie.Parent = zombies
-- 1,5 Studs neben der Bildmitte in 40 Studs Entfernung
zombie:PivotTo(CFrame.new(1.5, 4, -40))
local zombieRoot = zombie:FindFirstChild("HumanoidRootPart")
check(zombieRoot ~= nil, "Zombie hat HumanoidRootPart")

local stick = Vector2.new(0.02, 0)

-- ---------- Abbremsen ----------
local out = AimAssist.Adjust(stick, false, 1 / 60)
AimAssist.Scan(true)
out = AimAssist.Adjust(stick, false, 1 / 60)
check(AimAssist.Target() ~= nil and AimAssist.Target().Model == zombie, "Zombie am Fadenkreuz erkannt")
check(math.abs(out.X - stick.X * AimAssist.Friction) < 1e-6, "Hüfte: Stick am Ziel gebremst (" .. out.X .. ")")
out = AimAssist.Adjust(stick, true, 1 / 60)
check(math.abs(out.X - stick.X * AimAssist.AimFriction) < 1e-6, "Zielen: noch etwas mehr gebremst")

-- weit neben dem Ziel: kein Bremsen
camera.CFrame = CFrame.lookAt(Vector3.new(0, 5, 0), Vector3.new(-100, 5, -40))
AimAssist.Scan(true)
out = AimAssist.Adjust(stick, false, 1 / 60)
check(out == stick, "daneben: volle Drehung")
camera.CFrame = CFrame.lookAt(Vector3.new(0, 5, 0), Vector3.new(0, 5, -100))

-- Maus: nie
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.MouseMovement)
AimAssist.Scan(true)
check(AimAssist.Adjust(stick, false, 1 / 60) == stick, "Maus: keine Zielhilfe")
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)

-- Safe Zone, ohne Waffe, Option aus: nie
bob:SetAttribute("InSafeZone", true)
AimAssist.Scan(true)
check(AimAssist.Target() == nil, "Safe Zone: keine Zielhilfe")
bob:SetAttribute("InSafeZone", false)
drawn = false
AimAssist.Scan(true)
check(AimAssist.Target() == nil, "ohne Waffe: keine Zielhilfe")
drawn = true
PlayerSettings.Set("AimAssist", false)
AimAssist.Scan(true)
check(AimAssist.Adjust(stick, false, 1 / 60) == stick, "Option aus: keine Zielhilfe")
PlayerSettings.Set("AimAssist", true)

-- hinter einer Wand: nicht
local wall = Instance.new("Part", workspace)
SIM.RaycastHandler = function(origin, direction)
	if origin.Z > -20 and (origin + direction).Z < -20 then
		return { Instance = wall, Position = Vector3.new(0, 5, -20), Normal = Vector3.new(0, 0, 1), Material = Enum.Material.Plastic }
	end
	return nil
end
AimAssist.Scan(true)
check(AimAssist.Target() == nil, "Ziel hinter der Wand: keine Zielhilfe")
SIM.RaycastHandler = nil
wall:Destroy()

-- ---------- Einrasten beim Anlegen ----------
zombie:PivotTo(CFrame.new(3, 4, -30)) -- etwas weiter daneben (außerhalb des Bremskegels, im Einrast-Kegel)
AimAssist.OnAim()
check(AimAssist.Snapping(), "Anlegen: rastet auf den Zombie ein")
-- wie die Roblox-Kamera: Gieren rechts +, Nicken runter + (CameraInput), Zeit läuft weiter
local total = Vector2.zero
for _ = 1, 30 do
	local delta = AimAssist.Adjust(Vector2.zero, true, 1 / 60)
	total += delta
	local look = camera.CFrame.LookVector
	local turned = CFrame.Angles(0, -delta.X, 0) * CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(-delta.Y, 0, 0)
	camera.CFrame = CFrame.lookAt(camera.CFrame.Position, camera.CFrame.Position + turned.LookVector)
	SIM.Advance(1 / 60, 60)
end
check(total.X > 0, "Einrasten dreht nach rechts zum Zombie (" .. total.X .. ")")
local wanted = math.atan2(3, 30)
check(math.abs(total.X - wanted) < 0.03, "Einrasten dreht ungefähr bis aufs Ziel (" .. total.X .. " / " .. wanted .. ")")
check(not AimAssist.Snapping(), "Einrasten nach kurzer Zeit vorbei")

-- Spieler: nur bremsen, nie einrasten
zombie:Destroy()
local eve = SIM.AddPlayer("Eve", 1002)
eve:SetAttribute("Mode", "Extinction")
eve:SetAttribute("InSafeZone", false)
local eveRig = SIM.MakeRig("Eve")
eveRig.Parent = workspace
eve.Character = eveRig
eveRig:PivotTo(CFrame.new(3, 4, -30))
AimAssist.OnAim()
check(not AimAssist.Snapping(), "auf Spieler wird nicht eingerastet")

-- ---------- Y-Achse umkehren ----------
PlayerSettings.Set("InvertY", true)
local pitched = AimAssist.Adjust(Vector2.new(0, 0.05), false, 1 / 60)
check(pitched.Y < 0, "Y umgekehrt mit Controller")
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.MouseMovement)
pitched = AimAssist.Adjust(Vector2.new(0, 0.05), false, 1 / 60)
check(pitched.Y > 0, "Maus bleibt normal")
PlayerSettings.Set("InvertY", false)

if failures > 0 then
	error(failures .. " Prüfung(en) fehlgeschlagen")
end
print("aimassist: alles ok")

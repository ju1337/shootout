-- AimAssist (ModuleScript, nur Client)
-- Zielhilfe für den Controller, wie in Konsolen-Shootern üblich (Maus und Touch bekommen nichts davon):
--   Abbremsen: Liegt ein Gegner (Zombie, Boss, Bot, feindlicher Spieler) dicht am Fadenkreuz, dreht die Kamera mit dem
--              Stick langsamer (FRICTION), so bleibt man leichter drauf.
--   Einrasten: Beim Anlegen (L2) zieht die Kamera kurz auf einen nahen Zombie/Bot (nicht auf Spieler: PvP bleibt fair
--              gegenüber Maus-Spielern).
-- Nur mit gezogener Waffe, außerhalb von Safe Zones und Menüs, nur auf sichtbare Ziele (Strahl von der Kamera).
-- Abschaltbar in OPTIONEN › STEUERUNG › Zielhilfe (Controller). Dazu Y-Achse umkehren (Controller).
-- Movement hängt Adjust in die Kameradrehung (CameraInput.getRotation) und ruft OnAim beim Anlegen auf.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local InputActions = require(Shared.InputActions)
local PlayerSettings = require(Shared.PlayerSettings)
local TeamCheck = require(Shared.TeamCheck)
local Modes = require(Shared.Modes)

local player = Players.LocalPlayer

local AimAssist = {}

AimAssist.Range = 220            -- weiter weg keine Hilfe (Studs)
AimAssist.Friction = 0.55        -- Faktor auf die Stick-Drehung am Ziel (Hüfte)
AimAssist.AimFriction = 0.45     -- ... beim Zielen
AimAssist.FrictionRadius = 2.6   -- so breit (Studs) um die Zielmitte bremst es (Winkel wächst, je näher das Ziel)
AimAssist.SnapRadius = 4.5       -- so weit daneben rastet das Anlegen noch ein (Studs, höchstens MAX_SNAP_ANGLE)
AimAssist.SnapTime = 0.14        -- in dieser Zeit zieht die Kamera aufs Ziel
local MIN_ANGLE, MAX_FRICTION_ANGLE, MAX_SNAP_ANGLE = math.rad(1.5), math.rad(7), math.rad(9)
local SCAN_EVERY = 0.1

local target = nil   -- { Model, Point, Npc } nächstes Ziel am Fadenkreuz (alle SCAN_EVERY neu)
local snap = nil     -- { Model, Until } solange das Einrasten läuft
local lastScan = -math.huge

local function enabled()
	return InputActions.Device() == "Gamepad" and PlayerSettings.Get("AimAssist") ~= false
end

-- Waffe in der Hand? (Tests ersetzen die Funktion)
function AimAssist.WeaponDrawn()
	local ok, WeaponClient = pcall(require, Shared.WeaponClient) -- erst zur Laufzeit (WeaponClient braucht Movement)
	return ok and type(WeaponClient) == "table" and WeaponClient.GetWeapon and WeaponClient.GetWeapon() ~= nil
end

local function active()
	if not enabled() or player:GetAttribute("InSafeZone") then
		return false
	end
	local mode = player:GetAttribute("Mode")
	if not (mode and Modes.IsFighting(player)) then
		return false
	end
	local ok, UITheme = pcall(require, Shared.UITheme)
	if ok and UITheme.IsMenuOpen() then
		return false
	end
	return AimAssist.WeaponDrawn()
end

-- Zielpunkt: Brustmitte (zwischen Kopf und Hüfte); nil, wenn das Modell nicht lebt
local function aimPoint(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return root.Position:Lerp(head.Position, 0.45)
	end
	return root.Position + Vector3.new(0, 1, 0)
end

-- Kandidaten: sichtbare Zombies (fremde liegen bei ZombieVisibility gar nicht im Ordner) und Gegner (TeamCheck)
local function candidates()
	local list = {}
	local zombies = workspace:FindFirstChild("Zombies")
	if zombies then
		for _, model in zombies:GetChildren() do
			if model:IsA("Model") then
				table.insert(list, { Model = model, Npc = true })
			end
		end
	end
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if other ~= player and character and TeamCheck.IsEnemy(character) and not other:GetAttribute("InSafeZone") then
			table.insert(list, { Model = character, Npc = false })
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, model in bots:GetChildren() do
			if model:IsA("Model") and TeamCheck.IsEnemy(model) then
				table.insert(list, { Model = model, Npc = true })
			end
		end
	end
	return list
end

-- Winkel zwischen Blickrichtung und Ziel
local function angleTo(cameraCFrame, point)
	local direction = point - cameraCFrame.Position
	local distance = direction.Magnitude
	if distance < 1 then
		return math.pi, distance
	end
	local dot = math.clamp(cameraCFrame.LookVector:Dot(direction / distance), -1, 1)
	return math.acos(dot), distance
end

local function visible(cameraCFrame, model, point)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character or workspace.Terrain }
	local hit = workspace:Raycast(cameraCFrame.Position, point - cameraCFrame.Position, params)
	return hit == nil or hit.Instance:IsDescendantOf(model)
end

-- Nächstes sichtbares Ziel im Kegel (Winkel je nach Entfernung: radius Studs neben der Mitte, höchstens maxAngle)
local function nearest(cameraCFrame, radius, maxAngle, npcOnly)
	local best, bestAngle = nil, math.huge
	for _, entry in candidates() do
		if npcOnly and not entry.Npc then
			continue
		end
		local point = aimPoint(entry.Model)
		if point then
			local angle, distance = angleTo(cameraCFrame, point)
			local cone = math.clamp(math.atan(radius / math.max(distance, 1)), MIN_ANGLE, maxAngle)
			if distance <= AimAssist.Range and angle <= cone and angle < bestAngle and visible(cameraCFrame, entry.Model, point) then
				best, bestAngle = { Model = entry.Model, Point = point, Npc = entry.Npc }, angle
			end
		end
	end
	return best
end

-- Drehung (Gieren rechts +, Nicken runter +, wie CameraInput) von der Blickrichtung zum Punkt
local function deltaTo(cameraCFrame, point)
	local direction = cameraCFrame:VectorToObjectSpace(point - cameraCFrame.Position)
	local yaw = math.atan2(direction.X, -direction.Z)
	local pitch = -math.atan2(direction.Y, math.sqrt(direction.X ^ 2 + direction.Z ^ 2))
	return Vector2.new(yaw, pitch)
end

-- Ziel am Fadenkreuz neu bestimmen (gedrosselt)
function AimAssist.Scan(force)
	local now = os.clock()
	if not force and now - lastScan < SCAN_EVERY then
		return target
	end
	lastScan = now
	local camera = workspace.CurrentCamera
	target = (camera and active()) and nearest(camera.CFrame, AimAssist.FrictionRadius, MAX_FRICTION_ANGLE, false) or nil
	return target
end

-- Beim Anlegen: auf einen nahen Zombie/Bot einrasten
function AimAssist.OnAim()
	local camera = workspace.CurrentCamera
	if not (camera and active()) then
		return
	end
	local found = nearest(camera.CFrame, AimAssist.SnapRadius, MAX_SNAP_ANGLE, true)
	snap = found and { Model = found.Model, Until = os.clock() + AimAssist.SnapTime } or nil
end

-- Kameradrehung eines Bildes anpassen (rotation schon mit der Empfindlichkeit multipliziert)
function AimAssist.Adjust(rotation: Vector2, aiming: boolean, dt: number?): Vector2
	if not enabled() then
		return rotation
	end
	if PlayerSettings.Get("InvertY") == true then
		rotation = Vector2.new(rotation.X, -rotation.Y)
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return rotation
	end
	-- Einrasten: Rest der Drehung zum Ziel auf die verbleibende Zeit verteilen
	if snap then
		local left = snap.Until - os.clock()
		local point = snap.Model.Parent and aimPoint(snap.Model)
		if left <= 0 or not point or not aiming then
			snap = nil
		else
			local share = math.clamp((dt or 1 / 60) / left, 0, 1)
			return rotation + deltaTo(camera.CFrame, point) * share
		end
	end
	-- Abbremsen am Ziel
	if rotation.Magnitude > 0 and AimAssist.Scan() then
		return rotation * (aiming and AimAssist.AimFriction or AimAssist.Friction)
	end
	return rotation
end

-- Läuft gerade ein Einrasten? (Tests)
function AimAssist.Snapping()
	return snap ~= nil
end

function AimAssist.Target()
	return target
end

-- Bildzeit für Adjust (CameraInput.getRotation bekommt keine)
local frameTime = 1 / 60
RunService.RenderStepped:Connect(function(dt)
	frameTime = dt
end)
function AimAssist.FrameTime()
	return frameTime
end

return AimAssist

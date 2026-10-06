-- ViewModel (ModuleScript, nur Client)
-- Waffe mit Armen vor der eigenen Kamera (Ego-Perspektive):
--   * Hüfte <-> Zielen: beim Zielen liegt die Visierlinie (Kimme + Korn) genau in der Bildmitte
--   * Sprint-Haltung, Schwanken beim Umsehen, Wippen beim Laufen, Eintauchen beim Landen, gekippt beim Rutschen
--   * Rückschlag mit Federung, Ziehen beim Waffenwechsel
--   * Nachlade- und Schuss-Animationen aus WeaponAnimations (Magazin, Schlitten, Pumpe, linke Hand, ...)
-- Alles ist auf SCALE verkleinert und entsprechend näher an der Kamera: sieht gleich aus, ragt aber
-- nicht so leicht in Wände.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunModels = require(Shared.GunModels)
local WeaponAnimations = require(Shared.WeaponAnimations)
local PoseMath = require(Shared.PoseMath)

local ViewModel = {}
ViewModel.__index = ViewModel

local SCALE = 0.5

-- Haltung aus der Hüfte (Kamera-Raum, Modell-Einheiten): Griffpunkt rechts unten, leicht zur Mitte gedreht
local HIP_LONG = CFrame.new(0.78, -0.88, -1.95) * CFrame.Angles(0, math.rad(2), 0)
local HIP_SHORT = CFrame.new(0.68, -0.78, -1.6) * CFrame.Angles(0, math.rad(3), 0)
-- Sprint: Waffe gesenkt und nach links gekippt
local SPRINT = CFrame.new(-0.3, -0.3, 0.15) * CFrame.Angles(math.rad(-22), math.rad(38), math.rad(18))
-- Ziehen beim Waffenwechsel: kommt von unten
local DRAW = CFrame.new(0, -0.6, 0.3) * CFrame.Angles(math.rad(-40), math.rad(10), math.rad(-10))
local DRAW_TIME = 0.35
-- Schultern unter der Kamera (außerhalb des Bildes), Länge von Ober- und Unterarm
local RIGHT_SHOULDER = Vector3.new(0.95, -1.7, 0.9)
local LEFT_SHOULDER = Vector3.new(-0.7, -1.8, -0.2)
local UPPER_ARM, FOREARM = 1.7, 1.8
local SLEEVE_WIDTH = 0.34
local GLOVE_COLOR = Color3.fromRGB(38, 38, 44)

-- Feder für weiche Bewegungen (Wert, Geschwindigkeit als Vector3)
local function newSpring()
	return { Value = Vector3.zero, Velocity = Vector3.zero }
end
local function stepSpring(spring, target, dt, stiffness, damping)
	-- zwei Teilschritte: stabil auch bei niedriger Bildrate
	local h = dt / 2
	for _ = 1, 2 do
		local force = (target - spring.Value) * stiffness - spring.Velocity * damping
		spring.Velocity += force * h
		spring.Value += spring.Velocity * h
	end
end

-- Modell-Einheiten -> verkleinerter Kamera-Raum
local function scaled(cframe)
	return CFrame.new(cframe.Position * SCALE) * cframe.Rotation
end

local function smooth(alpha)
	return alpha * alpha * (3 - 2 * alpha)
end

local function armPart(name, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.one * 0.3 * SCALE
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- weaponName, skin (Waffen-Skin oder nil), sleeveColor = Farbe der Ärmel (Uniform des Agenten)
function ViewModel.new(weaponName, skin, sleeveColor, attachments)
	local self = setmetatable({}, ViewModel)
	self.Weapon = weaponName
	self.Info = GunModels.Info[weaponName]
	self.Model = GunModels.Build(weaponName, skin, attachments)
	self.Model:ScaleTo(SCALE)
	self.Model.Name = "ViewModel"
	self.Parts = {}
	for _, part in self.Model:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(self.Parts, {
				Part = part,
				Rest = scaled(part:GetAttribute("Rest") or GunModels.Rest(weaponName, part.Name)),
				Group = part:GetAttribute("Group"),
				Hidden = part:GetAttribute("Hidden") == true,
				Transparency = part.Transparency,
			})
		end
	end
	-- Arme: Oberarm + Unterarm im Ärmel, Handschuh
	self.Arms = {}
	for _, side in { "Right", "Left" } do
		self.Arms[side] = {
			Upper = armPart(side .. "Upper", sleeveColor, Enum.Material.Fabric, self.Model),
			Fore = armPart(side .. "Fore", sleeveColor, Enum.Material.Fabric, self.Model),
			Glove = armPart(side .. "Glove", GLOVE_COLOR, Enum.Material.SmoothPlastic, self.Model),
		}
	end
	self.Hip = self.Info.Long and HIP_LONG or HIP_SHORT
	self.Aim = GunModels.AimOffset(weaponName)
	self.Kick = newSpring()   -- Rückschlag: X = nach oben (Grad), Y = zur Seite (Grad), Z = nach hinten (Studs)
	self.Sway = { Value = Vector3.zero } -- Schwanken: X = Nicken, Y = Drehen (Grad)
	self.Dip = newSpring()    -- Eintauchen beim Landen (Y)
	self.BobPhase = 0
	self.Bob = 0
	self.SprintBlend = 0
	self.SlideBlend = 0
	self.DrawStart = os.clock()
	self.LastLook = nil
	self.GunWorld = CFrame.new()
	return self
end

function ViewModel:Destroy()
	self.Model:Destroy()
end

function ViewModel:SetParent(parent)
	if self.Model.Parent ~= parent then
		self.Model.Parent = parent
	end
end

-- Waffe kommt neu von unten (Waffenwechsel/Spawn)
function ViewModel:Draw()
	self.DrawStart = os.clock()
end

-- Rückschlag beim Schuss. strength aus WeaponConfig (Kick), aiming = beim Zielen ruhiger
function ViewModel:Fire(strength, aiming)
	local k = strength * (aiming and 0.45 or 1)
	self.Kick.Velocity += Vector3.new(55 * k, (math.random() - 0.5) * 30 * k, 2.6 * k)
end

function ViewModel:Land(speed)
	self.Dip.Velocity += Vector3.new(0, -math.clamp(speed, 0, 60) * 0.06, 0)
end

-- state: Camera (CFrame), Aim (0..1), Sprinting, Sliding, Speed (Studs/s am Boden, 0 in der Luft),
-- Reload/Fire = { Anim, T } oder nil, Melee (Messer gerade draußen)
function ViewModel:Update(dt, state)
	dt = math.min(dt, 1 / 20)
	local camera = state.Camera

	-- Umsehen: Waffe hängt kurz hinterher (aus der Drehgeschwindigkeit, unabhängig von der Bildrate)
	local look = camera.LookVector
	local swayTarget = Vector3.zero
	if self.LastLook and dt > 0 then
		local yawDelta = math.deg(math.atan2(look.X, -look.Z) - math.atan2(self.LastLook.X, -self.LastLook.Z))
		yawDelta = (yawDelta + 180) % 360 - 180
		local pitchDelta = math.deg(math.asin(math.clamp(look.Y, -1, 1)) - math.asin(math.clamp(self.LastLook.Y, -1, 1)))
		local factor = 1 - state.Aim * 0.75
		swayTarget = Vector3.new(math.clamp(-pitchDelta / dt * 0.012, -4, 4), math.clamp(yawDelta / dt * 0.012, -5, 5), 0)
			* factor
	end
	self.LastLook = look
	self.Sway.Value = self.Sway.Value:Lerp(swayTarget, math.min(1, dt * 10))
	stepSpring(self.Kick, Vector3.zero, dt, 320, 26)
	stepSpring(self.Dip, Vector3.zero, dt, 180, 18)

	-- Laufen: Wippen (beim Zielen kaum)
	local moving = math.clamp(state.Speed / 16, 0, 1.6)
	self.BobPhase += dt * (4 + state.Speed * 0.42)
	self.Bob += (moving - self.Bob) * math.min(1, dt * 8)
	local bobAmount = self.Bob * (1 - state.Aim * 0.85)
	local bob = CFrame.new(math.sin(self.BobPhase) * 0.045 * bobAmount, -math.abs(math.cos(self.BobPhase)) * 0.05 * bobAmount, 0)
		* CFrame.Angles(0, 0, math.sin(self.BobPhase) * math.rad(1.2) * bobAmount)

	self.SprintBlend += ((state.Sprinting and state.Aim < 0.1 and 1 or 0) - self.SprintBlend) * math.min(1, dt * 10)
	self.SlideBlend += ((state.Sliding and 1 or 0) - self.SlideBlend) * math.min(1, dt * 9)

	-- Grundhaltung: Hüfte -> Zielen (Kimme in der Bildmitte) -> Sprint
	local aim = smooth(state.Aim)
	local base = self.Hip:Lerp(self.Aim, aim)
	if self.SprintBlend > 0.001 then
		base = base:Lerp(base * SPRINT, smooth(self.SprintBlend))
	end
	-- Rutschen: Waffe kippt zur Seite und sinkt etwas (beim Zielen weniger)
	if self.SlideBlend > 0.001 then
		local slide = smooth(self.SlideBlend) * (1 - aim * 0.7)
		base = CFrame.new(0.05 * slide, -0.08 * slide, 0.05 * slide) * CFrame.Angles(0, 0, math.rad(-16) * slide) * base
	end
	local kick, sway = self.Kick.Value, self.Sway.Value
	local gun = bob * CFrame.new(0, self.Dip.Value.Y, 0) * base
		* CFrame.Angles(math.rad(sway.X), math.rad(sway.Y), 0)
		* CFrame.new(0, 0, kick.Z) * CFrame.Angles(math.rad(kick.X), math.rad(kick.Y), 0)

	-- Ziehen beim Waffenwechsel, Messer
	local draw = math.clamp((os.clock() - self.DrawStart) / DRAW_TIME, 0, 1)
	if draw < 1 then
		gun = DRAW:Lerp(CFrame.new(), smooth(draw)) * gun
	end
	if state.Melee then
		gun = CFrame.new(0, -1.2, 0.4) * gun
	end

	-- Animationen (Nachladen hat Vorrang vor der Schuss-Animation)
	local pose = nil
	local active = state.Reload or state.Fire
	if active then
		pose = WeaponAnimations.Sample(active.Anim, self.Weapon, active.T)
		gun = gun * pose.Gun
	end

	local gunWorld = camera * scaled(gun)
	self.GunWorld = gunWorld
	for _, entry in self.Parts do
		local offset = pose and entry.Group and pose.Groups[entry.Group]
		local cframe = gunWorld
		if offset then
			cframe = cframe * GunModels.GroupTransform(self.Weapon, entry.Group, offset, SCALE)
		end
		entry.Part.CFrame = cframe * entry.Rest
		local visible = pose and entry.Group and pose.Visible[entry.Group]
		if entry.Hidden then
			entry.Part.Transparency = visible == true and 0 or 1
		elseif entry.Group then
			entry.Part.Transparency = visible == false and 1 or entry.Transparency
		end
	end

	-- Hände: rechts am Griff, links am Handschutz bzw. dort, wo die Animation sie hinführt
	local right = gunWorld * scaled(CFrame.new(self.Info.RightHand) * CFrame.Angles(math.rad(-15), 0, 0))
	local leftLocal = pose and pose.Hand or CFrame.new(self.Info.LeftHand)
	local left = gunWorld * scaled(leftLocal)
	self:PlaceArm(self.Arms.Right, camera, right, RIGHT_SHOULDER, Vector3.new(1, -0.6, 0.2))
	self:PlaceArm(self.Arms.Left, camera, left, LEFT_SHOULDER, Vector3.new(-1, -0.7, 0.1))
end

-- Arm von der Schulter (hinter der Kamera) über den Ellbogen zur Hand
function ViewModel:PlaceArm(arm, camera, hand, shoulderLocal, poleLocal)
	local shoulder = camera * (shoulderLocal * SCALE)
	local wrist = (hand * CFrame.new(0, -0.02 * SCALE, 0.16 * SCALE)).Position
	local elbow = PoseMath.SolveTwoBone(shoulder, wrist, UPPER_ARM * SCALE, FOREARM * SCALE, camera:VectorToWorldSpace(poleLocal))
	local function segment(part, from, to)
		local length = (to - from).Magnitude
		part.Size = Vector3.new(SLEEVE_WIDTH * SCALE, SLEEVE_WIDTH * SCALE, math.max(length, 0.01))
		part.CFrame = CFrame.lookAt((from + to) / 2, to)
	end
	segment(arm.Upper, shoulder, elbow)
	segment(arm.Fore, elbow, wrist)
	arm.Glove.Size = Vector3.new(0.3, 0.33, 0.38) * SCALE
	arm.Glove.CFrame = hand
end

-- Weltposition und Richtung der Mündung (für Mündungsfeuer und Leuchtspur)
function ViewModel:MuzzleCFrame()
	return self.GunWorld * CFrame.new(self.Info.Muzzle * SCALE)
end

function ViewModel:EjectCFrame()
	return self.GunWorld * CFrame.new(self.Info.Eject * SCALE)
end

function ViewModel:GroupParts(group)
	return GunModels.GroupParts(self.Model, group)
end

function ViewModel.Scale()
	return SCALE
end

return ViewModel

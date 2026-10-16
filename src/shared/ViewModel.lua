-- ViewModel (ModuleScript, nur Client)
-- Waffe mit Armen vor der eigenen Kamera (Ego-Perspektive):
--   * Hüfte <-> Zielen: beim Zielen liegt die Visierlinie (Kimme + Korn) genau in der Bildmitte
--   * Sprint-Haltung, Schwanken beim Umsehen, Wippen beim Laufen, Eintauchen beim Landen, gekippt beim Rutschen
--   * Rückschlag mit Federung, Ziehen beim Waffenwechsel
--   * Nachlade-, Inspizier- und Schuss-Animationen aus WeaponAnimations (Magazin, Schlitten, Pumpe, linke Hand, ...)
-- Alles ist auf SCALE verkleinert und entsprechend näher an der Kamera: sieht gleich aus, ragt aber
-- nicht so leicht in Wände.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunModels = require(Shared.GunModels)
local WeaponAnimations = require(Shared.WeaponAnimations)
local PoseMath = require(Shared.PoseMath)

local ViewModel = {}
ViewModel.__index = ViewModel

-- Arme und Hände vor der Kamera: die echten Arme des eigenen Avatars (mit Shirt) und gebaute Hände mit Fingern in seiner
-- Hautfarbe (false = nur die Waffe)
ViewModel.ShowArms = true

local SCALE = 0.5

-- Haltung aus der Hüfte (Kamera-Raum, Modell-Einheiten): Griffpunkt rechts unten, leicht zur Mitte gedreht
local HIP_LONG = CFrame.new(0.78, -0.88, -1.95) * CFrame.Angles(0, math.rad(2), 0)
local HIP_SHORT = CFrame.new(0.68, -0.78, -1.6) * CFrame.Angles(0, math.rad(3), 0)
-- Sprint: Waffe gesenkt und nach links gekippt
local SPRINT = CFrame.new(-0.3, -0.3, 0.15) * CFrame.Angles(math.rad(-22), math.rad(38), math.rad(18))
-- Ziehen beim Waffenwechsel: kommt von unten
local DRAW = CFrame.new(0, -0.6, 0.3) * CFrame.Angles(math.rad(-40), math.rad(10), math.rad(-10))
local DRAW_TIME = 0.35
-- kurze Waffen beim Zielen so viel weiter vor dem Auge (Modell-Einheiten), die Visierlinie bleibt in der Bildmitte
local SHORT_AIM_REACH = 0.6
-- Schultern tief unter der Kamera (außerhalb des Bildes), die Ellbogen zeigen nach unten: die Arme kommen von unten ins
-- Bild statt quer davor (vor allem beim Zielen, wenn die Waffe nah am Auge ist). Länge von Ober- und Unterarm: Unterarm
-- im Verhältnis zur Waffe wie echt (gut 40 % der Strecke Griff–Mündung eines Gewehrs)
local RIGHT_SHOULDER = Vector3.new(0.8, -2.3, 0.5)
local LEFT_SHOULDER = Vector3.new(-0.6, -2.3, -0.8)
local LEFT_SHOULDER_SHORT = Vector3.new(-0.6, -2.3, 0.3) -- kurze Waffen: beide Hände am Griff, Schulter nicht so weit vorn
local UPPER_ARM, FOREARM = 1.7, 1.2
local GLOVE_COLOR = Color3.fromRGB(38, 38, 44)
-- Gebaute Arme (ohne echte Arme): Ärmel bis kurz vor das Handgelenk, dann Handgelenk und Hand in Hautfarbe.
-- Dicken in Modell-Einheiten (Durchmesser der Zylinder)
local UPPER_WIDTH, FORE_WIDTH, WRIST_WIDTH = 0.42, 0.36, 0.24
local CUFF = 0.8 -- Ärmel endet bei 80 % des Unterarms
-- Handgelenk im Raum der Hand (Modell-Einheiten): rechts hinter dem Griff, links unter/hinter dem Handschutz
local WRIST = { Right = Vector3.new(0.09, -0.1, 0.22), Left = Vector3.new(-0.03, -0.14, 0.2) }
-- Hand aus Quadern im Raum der Hand (Modell-Einheiten; X rechts, Y oben, -Z Richtung Mündung). "Glove" sitzt genau am
-- Handpunkt (Griff bzw. Handschutz), die übrigen Teile formen Handrücken, Finger und Daumen um die Waffe.
local HAND_SHAPES = {
	-- rechte Hand am Pistolengriff: Handrücken rechts, Finger vorne um den Griff herum, Zeigefinger am Abzug,
	-- Daumen links oben
	Right = {
		{ "Glove", Vector3.new(0.16, 0.3, 0.2), CFrame.new() },
		{ "Back", Vector3.new(0.1, 0.32, 0.3), CFrame.new(0.13, -0.08, 0.02) },
		{ "Fingers", Vector3.new(0.3, 0.24, 0.09), CFrame.new(0.02, -0.12, -0.13) },
		{ "Tips", Vector3.new(0.08, 0.24, 0.16), CFrame.new(-0.11, -0.12, -0.08) },
		{ "Index", Vector3.new(0.07, 0.07, 0.22), CFrame.new(0.1, 0.06, -0.17) * CFrame.Angles(math.rad(-8), math.rad(-12), 0) },
		{ "Thumb", Vector3.new(0.07, 0.07, 0.22), CFrame.new(-0.1, 0.06, -0.04) * CFrame.Angles(math.rad(-10), math.rad(14), 0) },
	},
	-- linke Hand um den Handschutz: Handballen unten, Handfläche an der linken Seite, Daumen links oben nach vorne,
	-- Finger rechts hoch
	Left = {
		{ "Glove", Vector3.new(0.2, 0.08, 0.26), CFrame.new() },
		{ "Palm", Vector3.new(0.3, 0.1, 0.34), CFrame.new(-0.02, -0.05, 0.02) },
		{ "Side", Vector3.new(0.1, 0.24, 0.32), CFrame.new(-0.17, 0.08, 0) },
		{ "Thumb", Vector3.new(0.08, 0.08, 0.26), CFrame.new(-0.17, 0.21, -0.12) * CFrame.Angles(0, math.rad(-6), 0) },
		{ "Fingers", Vector3.new(0.08, 0.22, 0.3), CFrame.new(0.17, 0.07, -0.02) },
		{ "Tips", Vector3.new(0.1, 0.07, 0.28), CFrame.new(0.14, 0.18, -0.02) },
	},
}
-- Echte Arme des Charakters: so dick wie am Körper mal ARM_THICKNESS (die Länge passt sich den Armen oben an)
local ARM_THICKNESS = 0.6

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

local function armPart(name, color, material, parent, shape)
	local part = Instance.new("Part")
	if shape then
		part.Shape = shape
	end
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

-- Gebaute Hand mit Fingern und Daumen (HAND_SHAPES) in einer Farbe: { { Part, Offset } }
local function buildHand(side, color, parent)
	local hand = {}
	for _, shape in HAND_SHAPES[side] do
		local part = armPart(side .. shape[1], color, Enum.Material.SmoothPlastic, parent)
		part.Size = shape[2] * SCALE
		table.insert(hand, { Part = part, Offset = scaled(shape[3]) })
	end
	return hand
end

-- Echte Arme (AvatarArms.ArmPieces) einbauen: jedes Teil hängt an seinem Knochen (Oberarm, Unterarm, Hand) und
-- wird mit ihm gestreckt (Länge wie UPPER_ARM/FOREARM, Dicke ARM_THICKNESS)
-- width = gewünschte Dicke des Unterarms (Kamera-Raum, Studs) statt Körper-Dicke mal ARM_THICKNESS (eigener Roblox-Avatar:
-- dessen Arme sind 1 Stud dick und wären vor der Kamera breite Platten)
local function buildRealArm(side, width)
	local bones: { [string]: any } = {
		Upper = { From = side.Shoulder, To = side.Elbow },
		Lower = { From = side.Elbow, To = side.Wrist },
		Hand = { From = side.Wrist, To = side.Wrist + (side.Wrist - side.Elbow) },
	}
	local lengths = { Upper = UPPER_ARM * SCALE, Lower = FOREARM * SCALE }
	local cross = ARM_THICKNESS * SCALE
	if width then
		-- Dicke des Unterarms quer zum Knochen (größte Ausdehnung seiner Teile)
		local axis = (side.Wrist - side.Elbow).Unit
		local across1 = axis:Cross(math.abs(axis.Z) < 0.9 and Vector3.zAxis or Vector3.xAxis).Unit
		local across2 = axis:Cross(across1)
		local thick = 0
		for _, piece in side.Pieces do
			if piece.Segment == "Lower" then
				local r, size = piece.Rest, piece.Part.Size
				for _, dir in { across1, across2 } do
					thick = math.max(thick, math.abs(r.RightVector:Dot(dir)) * size.X + math.abs(r.UpVector:Dot(dir)) * size.Y
						+ math.abs(r.LookVector:Dot(dir)) * size.Z)
				end
			end
		end
		if thick > 1e-3 then
			cross = width / thick
		end
	end
	for segment, bone in bones do
		local axis = bone.To - bone.From
		if axis.Magnitude < 1e-3 then
			return nil
		end
		bone.Axis = axis.Unit
		bone.Length = axis.Magnitude
		bone.Cross = cross
		bone.Stretch = lengths[segment] and lengths[segment] / bone.Length or bone.Cross
	end
	-- Hand wie der Unterarm verkleinert (sonst wird sie mit der Dicke gestaucht und zur flachen Platte)
	bones.Hand.Stretch = bones.Lower.Stretch
	local pieces = {}
	for _, piece in side.Pieces do
		local bone = bones[piece.Segment]
		local function stretch(v)
			local along = bone.Axis * v:Dot(bone.Axis)
			return along * bone.Stretch + (v - along) * bone.Cross
		end
		local rest = piece.Rest
		local size = piece.Part.Size
		piece.Part.Size = Vector3.new(stretch(rest.RightVector).Magnitude * size.X, stretch(rest.UpVector).Magnitude * size.Y,
			stretch(rest.LookVector).Magnitude * size.Z)
		local offset = rest.Position - bone.From -- Lage zum Gelenk (Ruhe-Raum)
		local along = offset:Dot(bone.Axis)
		table.insert(pieces, {
			Part = piece.Part,
			Bone = piece.Segment,
			Along = along, -- entlang des Knochens (wird mit ihm gestreckt)
			Across = (offset - bone.Axis * along) * bone.Cross, -- quer dazu
			Rotation = rest.Rotation,
		})
	end
	return { Pieces = pieces, Bones = bones }
end

-- weaponName, skin (Waffen-Skin oder nil), sleeveColor = Farbe der Ärmel (Uniform des Agenten),
-- arms = echte Arme des Charakters (AvatarArms.ArmPieces) oder nil (dann Ärmel und Handschuhe),
-- handColor = Farbe der gebauten Hände, wenn die echte Hand fehlt (Hautfarbe des Avatars), sonst dunkle Handschuhe,
-- armWidth = Dicke der echten Unterarme vor der Kamera (Studs, siehe buildRealArm), nil = Körper-Dicke mal ARM_THICKNESS
-- shirt = klassisches Shirt des Avatars (oder nil): die echten Arme tragen es auch vor der Kamera
function ViewModel.new(weaponName, skin, sleeveColor, attachments, arms, handColor, armWidth, shirt)
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
	-- Arme: die echten des Charakters, sonst Oberarm + Unterarm im Ärmel, Handschuh
	self.Arms = {}
	if ViewModel.ShowArms then
		local right = arms and arms.Right and buildRealArm(arms.Right, armWidth)
		local left = right and arms.Left and buildRealArm(arms.Left, armWidth)
		if right and left then
			self.RealArms = { Right = right, Left = left }
			-- mit Shirt: Arme in ein eigenes Modell mit Humanoid und den echten Teilnamen (RightUpperArm …), dann zeichnet
			-- Roblox das Shirt wie am Körper darauf
			local holder = self.Model
			if shirt then
				holder = Instance.new("Model")
				holder.Name = "AvatarArms"
				local humanoid = Instance.new("Humanoid")
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				humanoid.RequiresNeck = false
				humanoid.EvaluateStateMachine = false
				humanoid.Parent = holder
				shirt:Clone().Parent = holder
				holder.Parent = self.Model
			end
			for _, arm in self.RealArms do
				-- die echte Hand weg (Roblox-Hände sind Klötze ohne Finger): an ihre Stelle kommt unten die gebaute Hand
				-- mit Fingern in der Hautfarbe der echten Hand
				local kept = {}
				for _, piece in arm.Pieces do
					if piece.Bone == "Hand" then
						arm.SkinColor = arm.SkinColor or piece.Part.Color
						piece.Part:Destroy()
					else
						table.insert(kept, piece)
					end
				end
				arm.Pieces = kept
				for _, piece in arm.Pieces do
					if shirt then
						piece.Part.Name = string.gsub(piece.Part.Name, "_%d+$", "")
					end
					piece.Part.Parent = holder
				end
			end
		end
		local cylinder, skin = Enum.PartType.Cylinder, handColor or GLOVE_COLOR
		for _, side in { "Right", "Left" } do
			local real = self.RealArms and self.RealArms[side]
			if real then
				local color = real.SkinColor or handColor or GLOVE_COLOR
				real.WristLocal = WRIST[side]
				-- Handgelenk in Hautfarbe: schließt die Lücke zwischen Ärmel/Unterarm und gebauter Hand
				real.Wrist = armPart(side .. "Wrist", color, Enum.Material.SmoothPlastic, self.Model, cylinder)
				real.Hand = buildHand(side, color, self.Model)
				self.Arms[side] = real
				continue
			end
			local arm = {
				Upper = armPart(side .. "Upper", sleeveColor, Enum.Material.SmoothPlastic, self.Model, cylinder),
				Fore = armPart(side .. "Fore", sleeveColor, Enum.Material.SmoothPlastic, self.Model, cylinder),
				Wrist = armPart(side .. "Wrist", skin, Enum.Material.SmoothPlastic, self.Model, cylinder),
				WristLocal = WRIST[side],
				Hand = {},
			}
			arm.Hand = buildHand(side, skin, self.Model)
			self.Arms[side] = arm
		end
	end
	self.Hip = (self.Info.Long and HIP_LONG or HIP_SHORT) * CFrame.new(0, -(self.Info.HipDrop or 0), 0)
	self.Aim = GunModels.AimOffset(weaponName, attachments)
	if not self.Info.Long then
		-- Pistole/Revolver beim Zielen weiter vorn (gestreckte Arme): Hände und Arme verdecken weniger vom Bild
		self.Aim = CFrame.new(0, 0, -SHORT_AIM_REACH) * self.Aim
	end
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
-- Reload/Inspect/Fire = { Anim, T } oder nil, Melee (Messer gerade draußen)
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
	-- dezent: wenige Hundertstel Studs und ein halbes Grad, damit die Waffe ruhig im Bild bleibt
	local bob = CFrame.new(math.sin(self.BobPhase) * 0.016 * bobAmount, -math.abs(math.cos(self.BobPhase)) * 0.018 * bobAmount, 0)
		* CFrame.Angles(0, 0, math.sin(self.BobPhase) * math.rad(0.4) * bobAmount)

	self.SprintBlend += ((state.Sprinting and state.Aim < 0.1 and not state.Inspect and 1 or 0) - self.SprintBlend) * math.min(1, dt * 10)
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

	-- Animationen (Nachladen vor Inspizieren vor der Schuss-Animation)
	local pose = nil
	local active = state.Reload or state.Inspect or state.Fire
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
	if self.Arms.Right then
		self:PlaceArm(self.Arms.Right, camera, right, RIGHT_SHOULDER, Vector3.new(0.4, -1, 0.3))
		self:PlaceArm(self.Arms.Left, camera, left, self.Info.Long and LEFT_SHOULDER or LEFT_SHOULDER_SHORT, Vector3.new(-0.4, -1, 0.2))
	end
end

-- Arm von der Schulter (hinter der Kamera) über den Ellbogen zur Hand
function ViewModel:PlaceArm(arm, camera, hand, shoulderLocal, poleLocal)
	local shoulder = camera * (shoulderLocal * SCALE)
	local wrist = (hand * CFrame.new((arm.WristLocal or Vector3.new(0, -0.02, 0.16)) * SCALE)).Position
	local elbow = PoseMath.SolveTwoBone(shoulder, wrist, UPPER_ARM * SCALE, FOREARM * SCALE, camera:VectorToWorldSpace(poleLocal))
	for _, piece in arm.Hand do
		piece.Part.CFrame = hand * piece.Offset
	end
	-- Zylinder (Achse X) von from nach to
	local function segment(part, from, to, width)
		local length = (to - from).Magnitude
		part.Size = Vector3.new(math.max(length, 0.01), width * SCALE, width * SCALE)
		part.CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0)
	end
	if arm.Pieces then
		self:PlaceRealArm(arm, shoulder, elbow, wrist)
		-- vom Ende des Unterarms bis in die Hand
		segment(arm.Wrist, wrist:Lerp(elbow, 0.15), wrist:Lerp(hand.Position, 0.6), WRIST_WIDTH)
		return
	end
	local cuff = elbow:Lerp(wrist, CUFF)
	segment(arm.Upper, shoulder, elbow, UPPER_WIDTH)
	segment(arm.Fore, elbow, cuff, FORE_WIDTH)
	segment(arm.Wrist, cuff:Lerp(elbow, 0.05), wrist, WRIST_WIDTH)
end

-- Echte Arme: Knochen drehen wie bei den Figuren (PoseMath.AlignBone, Ellbogen-Achse = X im Ruhe-Raum), die Hand
-- verlängert den Unterarm
function ViewModel:PlaceRealArm(arm, shoulder, elbow, wrist)
	local upperDir, lowerDir = elbow - shoulder, wrist - elbow
	local hinge = upperDir:Cross(lowerDir)
	if hinge.Magnitude < 1e-4 then
		hinge = upperDir:Cross(Vector3.yAxis)
	end
	local bones = arm.Bones
	local upperRot = PoseMath.AlignBone(bones.Upper.Axis, Vector3.xAxis, upperDir, hinge)
	local lowerRot = PoseMath.AlignBone(bones.Lower.Axis, Vector3.xAxis, lowerDir, hinge)
	local frames = {
		Upper = { CFrame.new(shoulder) * upperRot, upperDir.Magnitude / bones.Upper.Length },
		-- Unterarm reicht immer bis zur Hand (auch wenn die Hand weiter weg ist als FOREARM)
		Lower = { CFrame.new(elbow) * lowerRot, lowerDir.Magnitude / bones.Lower.Length },
		Hand = { CFrame.new(wrist) * PoseMath.AlignBone(bones.Hand.Axis, Vector3.xAxis, lowerDir, hinge), bones.Hand.Stretch },
	}
	for _, piece in arm.Pieces do
		local frame, stretch = frames[piece.Bone][1], frames[piece.Bone][2]
		local bone = bones[piece.Bone]
		piece.Part.CFrame = frame * CFrame.new(bone.Axis * piece.Along * stretch + piece.Across) * piece.Rotation
	end
end

-- Weltposition und Richtung der Mündung (für Mündungsfeuer und Leuchtspur)
function ViewModel:MuzzleCFrame()
	return self.GunWorld * CFrame.new(GunModels.MuzzleOf(self.Weapon, self.Model) * SCALE)
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

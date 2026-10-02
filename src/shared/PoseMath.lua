-- PoseMath (ModuleScript)
-- Mathe für die Arm-Pose der Charaktere (CharacterPose): Zwei-Knochen-IK (Schulter - Ellbogen - Hand)
-- und Drehungen, die einen Knochen im Teil-Raum auf eine Richtung in der Welt legen.
-- Nur CFrame/Vector3, keine Instanzen – so lässt sich das ohne Roblox testen.

local PoseMath = {}

-- Ein Vektor senkrecht zu axis (für Sonderfälle, wenn nichts Besseres da ist)
local function anyPerpendicular(axis)
	local candidate = axis:Cross(Vector3.xAxis)
	if candidate.Magnitude < 1e-4 then
		candidate = axis:Cross(Vector3.zAxis)
	end
	return candidate.Unit
end

-- Anteil von v senkrecht zu der (Einheits-)Achse axis, normiert. fallback, falls v parallel zur Achse ist.
local function perpendicular(v, axis, fallback)
	local p = v - axis * v:Dot(axis)
	if p.Magnitude < 1e-4 then
		return fallback or anyPerpendicular(axis)
	end
	return p.Unit
end
PoseMath.Perpendicular = perpendicular

-- Ellbogen für Schulter S, Ziel T (Weltpositionen), Oberarmlänge a, Unterarmlänge b.
-- pole = Richtung, in die der Ellbogen ausweicht. Ist T zu weit weg, wird der Arm gestreckt.
-- Gibt (Ellbogen, erreichter Endpunkt) zurück.
function PoseMath.SolveTwoBone(S, T, a, b, pole)
	local toTarget = T - S
	local dist = toTarget.Magnitude
	local axis = dist > 1e-4 and toTarget / dist or Vector3.new(0, -1, 0)
	local d = math.clamp(dist, math.abs(a - b) + 1e-3, a + b - 1e-3)
	local x = (a * a - b * b + d * d) / (2 * d)
	local h = math.sqrt(math.max(0, a * a - x * x))
	local side = perpendicular(pole, axis)
	return S + axis * x + side * h, S + axis * d
end

-- Drehung (ohne Position), die den Knochen localBone (Richtung im Teil-Raum) auf worldBone legt und
-- localHinge (Gelenkachse im Teil-Raum) möglichst auf worldHinge.
function PoseMath.AlignBone(localBone, localHinge, worldBone, worldHinge)
	local lb = localBone.Unit
	local wb = worldBone.Unit
	local lh = perpendicular(localHinge, lb)
	local wh = perpendicular(worldHinge, wb)
	local localBasis = CFrame.fromMatrix(Vector3.zero, lh, lb)
	local worldBasis = CFrame.fromMatrix(Vector3.zero, wh, wb)
	return worldBasis * localBasis:Inverse()
end

-- Transform eines Motor6D, damit Part1 die Welt-Drehung part1Rot bekommt. Nur Drehung: Das Gelenk
-- bleibt verbunden. part0Rot = Welt-Drehung von Part0.
function PoseMath.MotorTransform(part0Rot, c0, c1, part1Rot)
	return (part0Rot * c0.Rotation):Inverse() * part1Rot * c1.Rotation
end

-- Welt-CFrame von Part1 eines Motors: Part0 * C0 * Transform * C1^-1
function PoseMath.Chain(part0CF, c0, transform, c1)
	return part0CF * c0 * transform * c1:Inverse()
end

-- Arm (Schulter, Ellbogen, Handgelenk wie bei R15) auf ein Ziel legen.
-- parentCF = Welt-CFrame des Oberkörpers, joints = { ShoulderC0, ShoulderC1, ElbowC0, ElbowC1, WristC0, WristC1 }
-- handCF = gewünschte Welt-CFrame der Hand (Drehung wird genau übernommen) ODER
-- palm = Position, an die die Handmitte soll (Handgelenk bleibt gerade).
-- pole = Ausweichrichtung des Ellbogens (Welt).
-- Gibt die drei Transforms (Schulter, Ellbogen, Handgelenk) zurück.
function PoseMath.SolveArm(parentCF, joints, handCF, palm, pole)
	local shoulder = parentCF * joints.ShoulderC0
	local S = shoulder.Position
	local upperBone = joints.ElbowC0.Position - joints.ShoulderC1.Position
	local lowerBone = joints.WristC0.Position - joints.ElbowC1.Position
	local a, b = upperBone.Magnitude, lowerBone.Magnitude

	local E, W
	if handCF then
		-- Handgelenk dort, wo es bei der gewünschten Hand-CFrame liegt
		local target = handCF:PointToWorldSpace(joints.WristC1.Position)
		local reached
		E, reached = PoseMath.SolveTwoBone(S, target, a, b, pole)
		W = reached
	else
		-- Hand verlängert den Unterarm: Handmitte soll auf palm
		local extra = joints.WristC1.Position.Magnitude
		local reached
		E, reached = PoseMath.SolveTwoBone(S, palm, a, b + extra, pole)
		W = E + (reached - E).Unit * b
	end

	local upperDir, lowerDir = E - S, W - E
	local hinge = upperDir:Cross(lowerDir)
	if hinge.Magnitude < 1e-4 then
		hinge = upperDir:Cross(pole)
		if hinge.Magnitude < 1e-4 then
			hinge = anyPerpendicular(upperDir.Unit)
		end
	end
	local upperRot = PoseMath.AlignBone(upperBone, Vector3.xAxis, upperDir, hinge)
	local lowerRot = PoseMath.AlignBone(lowerBone, Vector3.xAxis, lowerDir, hinge)
	local shoulderT = PoseMath.MotorTransform(parentCF.Rotation, joints.ShoulderC0, joints.ShoulderC1, upperRot)
	local elbowT = PoseMath.MotorTransform(upperRot, joints.ElbowC0, joints.ElbowC1, lowerRot)
	local wristT = CFrame.new()
	if handCF then
		wristT = PoseMath.MotorTransform(lowerRot, joints.WristC0, joints.WristC1, handCF.Rotation)
	end
	return shoulderT, elbowT, wristT
end

return PoseMath

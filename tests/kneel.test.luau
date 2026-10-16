--!expose CharacterPose kneelLegs
-- Knien beim Medikit/Verband/Weste (CharacterPose, Charakter-Attribut UseKneel): Beine eines nachgebauten R15-Rigs
-- (Gelenkwerte wie beim Standard-R15). Rechtes Knie und Schienbein am Boden, Fuß hinter der Hüfte; linker Fuß flach
-- vor der Hüfte. Auch während die Hüfte noch absinkt (zu hoch) kommt nichts Kaputtes heraus.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local CharacterPose = require("CharacterPose")
local PoseMath = require("PoseMath")

local function motor(c0, c1)
	return { C0 = c0, C1 = c1, Transform = CFrame.new(), Parent = true }
end
local function leg(side)
	return {
		Hip = motor(CFrame.new(0.5 * side, -0.2, 0), CFrame.new(0, 0.42, 0)),
		Knee = motor(CFrame.new(0, -0.41, 0), CFrame.new(0, 0.38, 0)),
		Ankle = motor(CFrame.new(0, -0.55, 0), CFrame.new(0, 0.1, 0)),
		LowerLeg = { Size = Vector3.new(1, 1.193, 1) },
		Foot = { Size = Vector3.new(1, 0.3, 1) },
	}
end

local FLOOR = 4
for _, yawDeg in { 0, 73, -140 } do
	-- Hüfte ganz unten (Movement: HipHeight auf 55 %) und mitten im Absinken
	for _, rootY in { 2.1, 2.5, 3 } do
		local yaw = CFrame.Angles(0, math.rad(yawDeg), 0)
		local rootCF = CFrame.new(10, FLOOR + rootY, -3) * yaw
		local legs = { Right = leg(1), Left = leg(-1) }
		local rootJoint = motor(CFrame.new(0, -1, 0), CFrame.new(0, -0.2, 0))
		local lowerTorso = PoseMath.Chain(rootCF, rootJoint.C0, rootJoint.Transform, rootJoint.C1)
		local t = CharacterPose.__kneelLegs({ Legs = legs }, lowerTorso, yaw, FLOOR)
		local label = "Drehung " .. yawDeg .. ", Höhe " .. rootY .. ": "
		check(t ~= nil and #t == 6 and PoseMath.AllFinite(t), label .. "Beine gesetzt")
		if t then
			local function fk(l, hipT, kneeT, ankleT)
				local upper = PoseMath.Chain(lowerTorso, l.Hip.C0, hipT, l.Hip.C1)
				local lower = PoseMath.Chain(upper, l.Knee.C0, kneeT, l.Knee.C1)
				local foot = PoseMath.Chain(lower, l.Ankle.C0, ankleT, l.Ankle.C1)
				return (upper * l.Knee.C0).Position, foot, (lowerTorso * l.Hip.C0).Position
			end
			local forward = yaw.LookVector
			local rKnee, rFoot, rHip = fk(legs.Right, t[1], t[2], t[3])
			local lKnee, lFoot, lHip = fk(legs.Left, t[4], t[5], t[6])
			-- Fuß- und Kniehöhe über dem Boden
			local rFootY = rFoot.Position.Y - FLOOR
			local lFootY = lFoot.Position.Y - FLOOR
			check(rootY > 2.5 or math.abs(lFootY - 0.15) < 0.12, label .. "linker Fuß steht auf dem Boden (" .. lFootY .. ")")
			check(lFoot.UpVector.Y > 0.95, label .. "linker Fuß flach")
			check((lFoot.Position - lHip):Dot(forward) > 0.3, label .. "linker Fuß vor der Hüfte")
			check(lKnee.Y > lFoot.Position.Y + 0.6, label .. "linkes Knie oben")
			check(rootY > 2.5 or (rFoot.Position - rHip):Dot(forward) < -0.15, label .. "rechter Fuß hinter der Hüfte (" .. (rFoot.Position - rHip):Dot(forward) .. ")")
			check(rootY > 2.5 or rFoot.UpVector.Y < -0.8, label .. "rechter Fußrücken unten")
			if rootY <= 2.1 then
				check(rFootY > 0.1 and rFootY < 0.7, label .. "rechter Fuß am Boden (" .. rFootY .. ")")
				check(math.abs(rKnee.Y - FLOOR - 0.45) < 0.15, label .. "rechtes Knie am Boden (" .. (rKnee.Y - FLOOR) .. ")")
			end
			check(rKnee.Y >= FLOOR + 0.2, label .. "rechtes Knie nicht im Boden")
		end
	end
end

if failures > 0 then
	error(failures .. " Prüfungen fehlgeschlagen")
end
print("kneel ok")

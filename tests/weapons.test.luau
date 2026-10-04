-- Tests für PoseMath, GunModels (Visierlinie), WeaponAnimations und WeaponConfig
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-4) end

local PoseMath = require("PoseMath")
local GunModels = require("GunModels")
local WeaponAnimations = require("WeaponAnimations")
local WeaponConfig = require("WeaponConfig")

-- ---------- PoseMath: Arm-IK mit R15-ähnlichen Gelenken ----------
local joints = {
	ShoulderC0 = CFrame.new(1, 0.563, 0), ShoulderC1 = CFrame.new(-0.5, 0.394, 0),
	ElbowC0 = CFrame.new(0, -0.334, 0), ElbowC1 = CFrame.new(0, 0.259, 0),
	WristC0 = CFrame.new(0, -0.501, 0), WristC1 = CFrame.new(0, 0.125, 0),
}
local function forward(parentCF, tS, tE, tW)
	local upper = PoseMath.Chain(parentCF, joints.ShoulderC0, tS, joints.ShoulderC1)
	local lower = PoseMath.Chain(upper, joints.ElbowC0, tE, joints.ElbowC1)
	local hand = PoseMath.Chain(lower, joints.WristC0, tW, joints.WristC1)
	return upper, lower, hand
end

local maxPos, maxAng = 0, 0
local rng = Random and Random.new and Random.new(1) or nil
local seed = 12345
local function rnd(a, b)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return a + (b - a) * (seed / 2147483648)
end
for i = 1, 400 do
	local parentCF = CFrame.new(rnd(-50, 50), rnd(0, 20), rnd(-50, 50)) * CFrame.Angles(rnd(-0.6, 0.6), rnd(-3, 3), rnd(-0.3, 0.3))
	-- Ziel in Reichweite (vor dem Körper, rechts)
	local local_ = Vector3.new(rnd(0.2, 1.2), rnd(-0.8, 0.3), rnd(-1.4, -0.6))
	local target = parentCF * CFrame.new(local_) * CFrame.Angles(rnd(-1.6, -0.6), rnd(-0.5, 0.5), rnd(-0.5, 0.5))
	local S = (parentCF * joints.ShoulderC0).Position
	local wristTarget = target:PointToWorldSpace(joints.WristC1.Position)
	local reach = 0.883 + 0.76
	if (wristTarget - S).Magnitude < reach - 0.02 and (wristTarget - S).Magnitude > 0.2 then
		local pole = parentCF:VectorToWorldSpace(Vector3.new(0.8, -1, 0.4))
		local tS, tE, tW = PoseMath.SolveArm(parentCF, joints, target, nil, pole)
		local upper, lower, hand = forward(parentCF, tS, tE, tW)
		local dp = (hand.Position - target.Position).Magnitude
		local da = __shim.angleBetween(hand, target)
		maxPos = math.max(maxPos, dp)
		maxAng = math.max(maxAng, da)
		-- Ellbogen muss zum Pol hin ausweichen
		local E = (upper * joints.ElbowC0).Position
		local axis = (wristTarget - S).Unit
		local off = (E - S) - axis * (E - S):Dot(axis)
		if off.Magnitude > 0.05 then
			check(off:Dot(pole) > 0, "Ellbogen zeigt vom Pol weg (Fall " .. i .. ")")
		end
		-- Schulter bleibt verbunden (Transform ohne Verschiebung)
		check(tS.Position.Magnitude < 1e-6 and tE.Position.Magnitude < 1e-6, "Transform verschiebt das Gelenk")
	end
end
print(string.format("IK Hand: max Positionsfehler %.6f, max Winkelfehler %.4f°", maxPos, maxAng))
check(maxPos < 1e-3, "Hand landet nicht am Ziel")
check(maxAng < 0.05, "Handdrehung stimmt nicht")

-- Unerreichbares Ziel: Arm gestreckt in Zielrichtung
do
	local parentCF = CFrame.new(0, 5, 0)
	local S = (parentCF * joints.ShoulderC0).Position
	local palm = S + Vector3.new(0.3, -0.2, -5)
	local tS, tE, tW = PoseMath.SolveArm(parentCF, joints, nil, palm, Vector3.new(0, -1, 0))
	local upper, lower, hand = forward(parentCF, tS, tE, tW)
	local dir = (palm - S).Unit
	local handDir = (hand.Position - S).Unit
	check(handDir:Dot(dir) > 0.999, "gestreckter Arm zeigt nicht zum Ziel")
	print("Gestreckt: Hand-Abstand " .. string.format("%.3f", (hand.Position - S).Magnitude))
end

-- Linke Hand (palm): Handmitte am Ziel
do
	local lj = {
		ShoulderC0 = CFrame.new(-1, 0.563, 0), ShoulderC1 = CFrame.new(0.5, 0.394, 0),
		ElbowC0 = CFrame.new(0, -0.334, 0), ElbowC1 = CFrame.new(0, 0.259, 0),
		WristC0 = CFrame.new(0, -0.501, 0), WristC1 = CFrame.new(0, 0.125, 0),
	}
	local maxErr = 0
	for i = 1, 200 do
		local parentCF = CFrame.new(rnd(-9, 9), 4, rnd(-9, 9)) * CFrame.Angles(0, rnd(-3, 3), 0) * CFrame.Angles(0, -0.7, 0)
		local palm = parentCF * Vector3.new(rnd(-0.2, 1.0), rnd(-0.6, 0.3), rnd(-1.5, -0.8))
		local S = (parentCF * lj.ShoulderC0).Position
		if (palm - S).Magnitude < 0.883 + 0.76 + 0.125 - 0.02 then
			local tS, tE, tW = PoseMath.SolveArm(parentCF, lj, nil, palm, parentCF:VectorToWorldSpace(Vector3.new(-0.6, -1, 0.1)))
			local upper = PoseMath.Chain(parentCF, lj.ShoulderC0, tS, lj.ShoulderC1)
			local lower = PoseMath.Chain(upper, lj.ElbowC0, tE, lj.ElbowC1)
			local hand = PoseMath.Chain(lower, lj.WristC0, tW, lj.WristC1)
			maxErr = math.max(maxErr, (hand.Position - palm).Magnitude)
		end
	end
	print(string.format("IK linke Hand: max Fehler %.6f", maxErr))
	check(maxErr < 1e-3, "linke Hand verfehlt das Ziel")
end

-- ---------- GunModels: Visierlinie frei, Korn genau auf der Linie ----------
-- Strahl gegen gedrehte Box (Slab-Test im Teil-Raum). Gibt Eintrittsabstand oder nil zurück.
local function rayBox(origin, dir, part)
	local inv = part.CFrame:Inverse()
	local o = inv * origin
	local d = inv:VectorToWorldSpace(dir) -- Inverse hat die Drehung
	local half = part.Size / 2
	local tmin, tmax = -math.huge, math.huge
	for _, axis in { "X", "Y", "Z" } do
		local oo, dd, h = o[axis], d[axis], half[axis]
		if math.abs(dd) < 1e-9 then
			if oo <= -h or oo >= h then return nil end
		else
			local t1, t2 = (-h - oo) / dd, (h - oo) / dd
			if t1 > t2 then t1, t2 = t2, t1 end
			tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
			if tmin >= tmax then return nil end
		end
	end
	if tmax <= 0 then return nil end
	return math.max(tmin, 0)
end

local function quaderSights(weaponName, info)
	local model = GunModels.Build(weaponName, nil)
	local eye = Vector3.new(0, info.SightHeight, info.SightZ + info.EyeRelief)
	local dir = Vector3.new(0, 0, -1)
	-- knapp über der Visierlinie: nichts darf den Blick versperren (außer der Perle der Schrotflinte)
	local blockers = {}
	for _, part in model:GetChildren() do
		if (part.Transparency or 0) < 1 then
			local t = rayBox(eye + Vector3.new(0, 0.003, 0), dir, part)
			if t then table.insert(blockers, part.Name) end
		end
	end
	local allowed = weaponName == "Shotgun" and { FrontDot = true }
		or info.Reflex and { DotGlass = true, DotReticle = true } or {}
	for _, name in blockers do
		check(allowed[name], weaponName .. ": Visierlinie versperrt durch " .. name)
	end
	-- knapp darunter: zuerst muss das Korn kommen (Rotpunkt: Punkt bzw. Glas)
	local first, firstT = nil, math.huge
	for _, part in model:GetChildren() do
		if (part.Transparency or 0) < 1 then
			local t = rayBox(eye - Vector3.new(0, 0.012, 0), dir, part)
			if t and t < firstT then first, firstT = part.Name, t end
		end
	end
	if info.Reflex then
		check(first == "DotReticle" or first == "DotGlass", weaponName .. ": unter der Linie trifft man zuerst " .. tostring(first))
		-- genau auf der Linie: zuerst der rote Punkt
		local onLine, onLineT = nil, math.huge
		for _, part in model:GetChildren() do
			local t = rayBox(eye, dir, part)
			if t and t < onLineT then onLine, onLineT = part.Name, t end
		end
		check(onLine == "DotReticle", weaponName .. ": auf der Visierlinie liegt zuerst " .. tostring(onLine))
		-- Blick durchs Fenster (bis nahe an den Rand): nur Glas und Punkt, kein Rahmen oder Gehäuse
		local glass = model.DotGlass
		for _, offset in { Vector3.new(0.11, 0, 0), Vector3.new(-0.11, 0, 0), Vector3.new(0, 0.085, 0),
			Vector3.new(0, -0.09, 0), Vector3.new(0.08, 0.06, 0), Vector3.new(-0.08, -0.07, 0) } do
			local target = glass.CFrame.Position + offset
			local look = (target - eye).Unit
			for _, part in model:GetChildren() do
				if (part.Transparency or 0) < 1 and part.Name ~= "DotGlass" and part.Name ~= "DotReticle" then
					local t = rayBox(eye, look, part)
					check(t == nil or t > (target - eye).Magnitude + 0.05,
						weaponName .. ": Fenster bei " .. tostring(offset) .. " verdeckt durch " .. part.Name)
				end
			end
		end
		-- knapp über dem Fenster: der Rahmen ist im Weg
		local above = (glass.CFrame.Position + Vector3.new(0, 0.125, 0) - eye).Unit
		check(rayBox(eye, above, model.DotHoodTop) ~= nil, weaponName .. ": Fensterrahmen oben fehlt")
	else
		check(first == "FrontDot" or first == "FrontPost", weaponName .. ": unter der Linie trifft man zuerst " .. tostring(first))
	end
	return blockers, first
end

for weaponName, info in GunModels.Info do
	-- Quader-Waffen: Kimme, Korn und Rotpunkt aus Teilen nachmessen. 3D-Modelle (Assets.Weapons): die Visierlinie
	-- kommt aus den Markern, das Modell prüfen weaponmodels/weaponassets.
	local blockers, first = {}, "Marker"
	if not GunModels.HasAsset(weaponName) then
		blockers, first = quaderSights(weaponName, info)
	end
	-- AimOffset legt die Kimme genau vor das Auge
	local rear = Vector3.new(0, info.SightHeight, info.SightZ)
	local camSpace = GunModels.AimOffset(weaponName) * rear
	check(near(camSpace.X, 0) and near(camSpace.Y, 0) and near(camSpace.Z, -info.EyeRelief), weaponName .. ": AimOffset falsch")
	-- Mündung liegt vor dem Lauf
	check(info.Muzzle.Z < info.SightZ, weaponName .. ": Mündung hinter der Kimme?")
	print(string.format("%-9s Visier ok: Blocker=%s, erstes Teil darunter=%s", weaponName, #blockers > 0 and table.concat(blockers, ",") or "-", tostring(first)))
end

-- Werkzeug-Skalierung: Teile werden kleiner, relative Lage bleibt
do
	local model = GunModels.Build("Rifle", nil)
	local body = model:FindFirstChild("Body")
	for _, part in model:GetChildren() do
		if not body and part:IsA("BasePart") and part.Name ~= "Handle" then
			body = part -- 3D-Modell: irgendein Teil außer dem Griffpunkt
		end
	end
	local before = body.CFrame.Position
	model:ScaleTo(0.7)
	check((body.CFrame.Position - before * 0.7).Magnitude < 1e-6, "Skalierung verschiebt Teile falsch")
end

-- ---------- WeaponAnimations: Spuren stetig, keine NaN, Ereignisse sortiert ----------
local function isNaNVec(v) return v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z end
for weaponName in GunModels.Info do
	local anim, duration = WeaponAnimations.Reload(weaponName, WeaponConfig.Get(weaponName).ReloadTime, 3)
	check(anim ~= nil, weaponName .. ": keine Nachlade-Animation")
	local prevHand, prevGun = nil, nil
	local maxHandJump, maxGunJump = 0, 0
	local steps = 2000
	for i = 0, steps do
		local t = i / steps
		local pose = WeaponAnimations.Sample(anim, weaponName, t)
		check(not isNaNVec(pose.Gun.Position), weaponName .. ": NaN in Gun bei " .. t)
		if pose.Hand then
			check(not isNaNVec(pose.Hand.Position), weaponName .. ": NaN in Hand bei " .. t)
			if prevHand then maxHandJump = math.max(maxHandJump, (pose.Hand.Position - prevHand).Magnitude) end
			prevHand = pose.Hand.Position
		end
		if prevGun then maxGunJump = math.max(maxGunJump, (pose.Gun.Position - prevGun).Magnitude) end
		prevGun = pose.Gun.Position
		for group, offset in pose.Groups do
			check(not isNaNVec(offset.Position), weaponName .. ": NaN in Gruppe " .. group)
		end
	end
	-- Pro Schritt (Dauer/2000 s) darf sich die Hand nur wenig bewegen
	local speed = maxHandJump * steps / duration
	print(string.format("%-9s Nachladen %.2fs: max Handgeschwindigkeit %.1f Studs/s, Waffe %.1f", weaponName, duration, speed, maxGunJump * steps / duration))
	check(speed < 40, weaponName .. ": Hand springt (" .. speed .. ")")
	-- Anfang und Ende: Waffe in Ruhe, Hand an der Ruheposition
	local startPose = WeaponAnimations.Sample(anim, weaponName, 0)
	local endPose = WeaponAnimations.Sample(anim, weaponName, 1)
	check(startPose.Gun.Position.Magnitude < 1e-6 and endPose.Gun.Position.Magnitude < 1e-6, weaponName .. ": Waffe nicht in Ruhe am Anfang/Ende")
	local rest = GunModels.Info[weaponName].LeftHand
	if weaponName ~= "Shotgun" then
		check((startPose.Hand.Position - rest).Magnitude < 1e-6 and (endPose.Hand.Position - rest).Magnitude < 1e-6, weaponName .. ": Hand nicht in Ruhe")
	end
	-- Gruppen am Ende in Ruhe
	for group, offset in endPose.Groups do
		check(offset.Position.Magnitude < 1e-6, weaponName .. ": Gruppe " .. group .. " am Ende nicht in Ruhe")
	end
	-- Ereignisse
	local events = WeaponAnimations.Events(anim, -1, 1)
	for i = 2, #events do
		check(events[i][1] >= events[i - 1][1], weaponName .. ": Ereignisse unsortiert")
	end
	-- Jede Gruppe in den Spuren muss es im Modell geben
	for group in anim.Groups or {} do
		check(GunModels.GroupPivot(weaponName, group) ~= nil, weaponName .. ": Gruppe fehlt im Modell: " .. group)
	end
	for group in anim.Hide or {} do
		check(GunModels.GroupPivot(weaponName, group) ~= nil, weaponName .. ": Hide-Gruppe fehlt: " .. group)
	end
	for group in anim.Show or {} do
		check(GunModels.GroupPivot(weaponName, group) ~= nil, weaponName .. ": Show-Gruppe fehlt: " .. group)
	end
end

-- Schrotflinte: Dauer passt zur Server-Zeitleiste
do
	local cfg = WeaponConfig.Get("Shotgun")
	for shells = 1, 7 do
		local _, total = WeaponAnimations.Reload("Shotgun", 2.5, shells)
		local start, per, finish = WeaponConfig.ShellTiming(cfg, 2.5)
		check(near(total, start + shells * per + finish), "Schrotflinte: Dauer stimmt nicht")
	end
	local _, full = WeaponAnimations.Reload("Shotgun", 2.5, cfg.MagazineSize)
	check(near(full, 2.5), "Schrotflinte: volles Magazin dauert nicht ReloadTime")
end

-- Schuss-Animationen
for weaponName in GunModels.Info do
	local anim = WeaponAnimations.Fire(weaponName)
	if anim then
		for t = 0, 1, 0.05 do
			local pose = WeaponAnimations.Sample(anim, weaponName, t)
			check(not isNaNVec(pose.Gun.Position), weaponName .. ": Fire NaN")
		end
	end
end

-- ---------- WeaponConfig: Streuung und Bloom ----------
do
	local rifle = WeaponConfig.Get("Rifle")
	check(near(WeaponConfig.SpreadFor(rifle, 0, 0, false, false, false), 1.2), "Grund-Streuung")
	check(near(WeaponConfig.SpreadFor(rifle, 0, 0, false, true, false), 0.3), "Zielen")
	check(near(WeaponConfig.SpreadFor(rifle, 0, 16, false, false, false), 1.8), "Laufen")
	check(WeaponConfig.SpreadFor(rifle, 0, 0, true, false, false) > 3, "Sprung")
	local bloom = 0
	local current
	for i = 1, 15 do
		current, bloom = WeaponConfig.StepBloom(rifle, bloom, i == 1 and 10 or rifle.FireDelay)
	end
	check(near(bloom, rifle.MaxBloom), "Bloom erreicht Maximum")
	check(near(WeaponConfig.DecayBloom(rifle, bloom, rifle.FireDelay), rifle.MaxBloom), "kein Abbau direkt nach dem Schuss")
	check(WeaponConfig.DecayBloom(rifle, bloom, 2) == 0, "Bloom baut sich ab")
	local first = WeaponConfig.StepBloom(rifle, 0, 10)
	check(first == 0, "erster Schuss ohne Bloom")
end

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

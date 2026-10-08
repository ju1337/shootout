-- MovementPhysics (ModuleScript, Client und Tests)
-- Rechenteil der Bewegung (Movement): Tempo-Rampe, Rutschen (Schwung, Reibung, Hang, Lenken), Schwung in der Luft,
-- Hindernisse (drüberspringen oder hochziehen) samt Bahn, Coyote-Time und Sprungpuffer, Kamera-Neigung, Wippen und
-- Eintauchen beim Landen. Keine Dienste und kein Zustand: reine Rechnungen (geprüft in tests/movementfeel.test.luau).
-- Alle Tempi bleiben unter dem Server-Check (MovementGuard: waagerecht dauerhaft 62 Studs/s, nach oben 50 Studs/s).

local P = {}

-- ---------- Tempo ----------
P.SprintFactor = 1.5
P.CrouchFactor = 0.5
P.AimFactor = 0.6
P.SprintForward = 0.5 -- Sprint nur nach vorn: Eingabe höchstens 60° neben der Blickrichtung (schräg vorn geht noch)
P.AccelUp = 34      -- Studs/s² beim Schneller-Werden (Gehen -> Sprint in gut 0,2 s: man spürt das Anlaufen)
P.AccelDown = 80    -- Studs/s² beim Langsamer-Werden (Zielen, Ducken, Sprint loslassen, Schwung nach dem Landen)

-- Laufgeschwindigkeit (WalkSpeed) einen Schritt Richtung Ziel
function P.Approach(current, target, dt)
	if current < target then
		return math.min(target, current + P.AccelUp * dt)
	end
	return math.max(target, current - P.AccelDown * dt)
end

-- ---------- Rutschen ----------
P.SlideBoost = 9           -- Schub beim Start, zusätzlich zum aktuellen Tempo
P.SlideBoostRecharge = 1.4 -- der Schub wächst nach dem letzten Rutschen in dieser Zeit wieder von 0 auf voll
P.SlideMax = 50            -- Höchsttempo (auch bergab)
P.SlideFriction = 13       -- Grundreibung (Studs/s²)
P.SlideDrag = 0.45         -- zusätzliche Bremsung je Studs/s Tempo (schnell = bremst stärker)
P.SlideSlope = 0.55        -- Anteil der Schwerkraft, der am Hang zieht (bergab schneller, bergauf kürzer)
P.SlideTurn = math.rad(110) -- so weit lässt sich pro Sekunde lenken
P.SlideMaxTime = 2.6       -- längstes Rutschen (lange Hänge)
P.SlideEndMargin = 1.5     -- endet, wenn das Tempo unter Ducken + diesen Wert fällt
P.SlideMinStart = 1.12     -- rutschen erst ab diesem Vielfachen des Gehtempos (also im Sprint oder mit Schwung)

-- Starttempo: aktuelles Tempo (mindestens Sprint) plus Schub. Der Schub lädt nach dem letzten Rutschen erst wieder auf,
-- Dauer-Rutschen bringt also kein Extra-Tempo.
function P.SlideStart(speed, sprintSpeed, sinceLastSlide)
	local boost = P.SlideBoost * math.clamp((sinceLastSlide or math.huge) / P.SlideBoostRecharge, 0, 1)
	return math.min(P.SlideMax, math.max(speed, sprintSpeed) + boost)
end

-- Neues Tempo nach dt. slope = sin(Neigung) in Rutschrichtung (+ bergab, - bergauf), gravity = Schwerkraft (Studs/s²)
function P.SlideStep(speed, dt, slope, gravity)
	local decel = P.SlideFriction + P.SlideDrag * speed
	local pull = P.SlideSlope * (gravity or 196.2) * (slope or 0)
	return math.clamp(speed + (pull - decel) * dt, 0, P.SlideMax)
end

-- Ende des Rutschens? (Tempo zu klein oder zu lange)
function P.SlideOver(speed, crouchSpeed, elapsed)
	return speed <= crouchSpeed + P.SlideEndMargin or elapsed >= P.SlideMaxTime
end

-- Neigung des Bodens in Laufrichtung aus seiner Normalen: sin(Winkel), + = bergab
function P.SlopeAlong(normal, dir)
	return normal.X * dir.X + normal.Z * dir.Z
end

-- Flache Richtung (Y = 0, Länge 1) oder nil
function P.Flat(v)
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	return flat.Unit
end

-- Rutschrichtung zur Eingabe drehen, höchstens SlideTurn pro Sekunde. Nach hinten ziehen lenkt nicht.
function P.Steer(dir, input, dt)
	local target = input and input.Magnitude > 0.1 and P.Flat(input)
	if not target then
		return dir
	end
	local cosAngle = math.clamp(dir.X * target.X + dir.Z * target.Z, -1, 1)
	local angle = math.acos(cosAngle)
	if angle < 1e-4 or angle > math.rad(100) then
		return angle < 1e-4 and target or dir
	end
	local turn = math.min(angle, P.SlideTurn * dt)
	-- Drehung um +Y: positiver Winkel dreht +X Richtung -Z (wie CFrame.Angles(0, a, 0))
	local side = dir.Z * target.X - dir.X * target.Z -- = (dir × target).Y
	local a = side >= 0 and turn or -turn
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(dir.X * c + dir.Z * s, 0, -dir.X * s + dir.Z * c)
end

-- ---------- Luft ----------
P.AirDrag = 5            -- Schwung (aus Rutschen oder Vault) nimmt in der Luft so ab (Studs/s²)
P.AirMomentumMax = 46
P.Coyote = 0.12          -- Sprung kurz nach dem Verlassen einer Kante zählt noch
P.JumpBuffer = 0.15      -- Sprung kurz vor dem Landen wird beim Landen ausgeführt
P.JumpHeight = 4.5       -- Sprunghöhe in Studs (Roblox-Standard 7,2 ist fast anderthalb Körper hoch)

-- Lenken in der Luft: die Laufrichtung (MoveDirection, Länge 0..1) folgt der Eingabe nur mit AirAccel pro Sekunde,
-- ohne Eingabe läuft sie langsam aus (AirRelease). Ein Sprung trägt so seinen Schwung, statt mitten in der Luft auf der
-- Stelle umzudrehen (Roblox lenkt in der Luft sonst genauso hart wie am Boden).
P.AirAccel = 4.5   -- volle Umkehr in gut 0,4 s, 90° in gut 0,3 s
P.AirRelease = 1.5 -- Tasten los: der Schwung trägt noch ein Stück weiter

function P.AirSteer(current, input, dt)
	local target = Vector3.new(input.X, 0, input.Z)
	if target.Magnitude > 1 then
		target = target.Unit
	end
	local rate = target.Magnitude > 0.1 and P.AirAccel or P.AirRelease
	local delta = target - current
	local maxStep = rate * dt
	if delta.Magnitude <= maxStep then
		return target
	end
	return current + delta.Unit * maxStep
end

-- Sprint erlaubt? input = Eingabe (MoveDirection), look = Blickrichtung. Im Stand zählt es als vorn.
function P.SprintAllowed(input, look)
	local wish = P.Flat(input)
	local forward = P.Flat(look)
	if not wish or not forward or input.Magnitude < 0.1 then
		return true
	end
	return wish:Dot(forward) >= P.SprintForward
end

function P.AirStep(momentum, dt)
	return math.max(0, momentum - P.AirDrag * dt)
end

-- Darf ein Sprung in der Luft noch als Absprung von der Kante gelten?
function P.CoyoteOk(now, leftGroundAt, jumpedAt)
	if not leftGroundAt or now - leftGroundAt > P.Coyote then
		return false
	end
	return jumpedAt == nil or jumpedAt < leftGroundAt - 0.05
end

-- Wurde kurz vor dem Landen gesprungen?
function P.Buffered(now, requestAt)
	return requestAt ~= nil and now - requestAt <= P.JumpBuffer
end

-- ---------- Hindernisse ----------
P.VaultMin = 1.3         -- niedriger: einfach weiterlaufen (Stufen nimmt der Humanoid selbst)
P.VaultMax = 4.4         -- bis zu dieser Höhe springt man über dünne Hindernisse
P.MantleMax = 6.2        -- höchste Kante über den Füßen, an der man sich hochzieht (Arme gestreckt)
P.MantleFromGround = 7   -- aus dem Sprung: Kante höchstens so hoch über dem letzten Boden (Dächer ab 9 nur über Treppen)
P.VaultThickness = 4.5   -- dünner als das (dahinter geht es runter): drüberspringen
P.Reach = 4              -- so nah muss die Wand vor einem sein
P.Clearance = 4.6        -- so viel Platz braucht der Körper über der Kante

-- Art der Bewegung aus der Messung: height = Kante über den Füßen, thin = dahinter geht es runter,
-- fromGround = Kante über dem letzten Boden (in der Luft), clear = genug Platz über der Kante, fast = im Lauf (Sprint
-- oder Schwung): dann über dünne Hindernisse drüber, sonst hinauf
function P.Classify(height, thin, fromGround, clear, fast)
	if not clear or height < P.VaultMin or (fromGround or height) > P.MantleFromGround then
		return nil
	end
	if thin and fast and height <= P.VaultMax then
		return "Vault"
	end
	if height <= P.MantleMax then
		return "Mantle"
	end
	return nil
end

-- Dauer: über ein Hindernis schnell (Schwung bleibt; höher und weiter dauert etwas länger), Hochziehen je nach Höhe
function P.VaultTime(height, distance)
	return math.clamp(0.2 + height * 0.03 + distance * 0.012, 0.26, 0.42)
end

function P.MantleTime(height)
	return math.clamp(0.2 + height * 0.035, 0.28, 0.5)
end

-- Bahn über ein Hindernis, t = 0..1: zügig hoch an die Vorderkante (near), oben drüber bis zur Hinterkante (far),
-- dann fallen bis zur Landung (land). Die Füße bleiben so über der ganzen Oberseite.
function P.VaultPoint(start, near, far, land, t)
	if t < 0.4 then
		local u = t / 0.4
		local up = 1 - (1 - u) ^ 2 -- schnell hoch, oben langsamer
		return Vector3.new(start.X + (near.X - start.X) * u, start.Y + (near.Y - start.Y) * up, start.Z + (near.Z - start.Z) * u)
	elseif t < 0.65 then
		return near:Lerp(far, (t - 0.4) / 0.25)
	end
	local u = math.min(1, (t - 0.65) / 0.35)
	local down = u * u -- erst langsam, dann fallen
	return Vector3.new(far.X + (land.X - far.X) * u, far.Y + (land.Y - far.Y) * down, far.Z + (land.Z - far.Z) * u)
end

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Hochziehen: erst vor allem hoch (zügig, läuft aus), dann nach vorn auf die Kante, t = 0..1
function P.MantlePoint(start, target, t)
	local up = 1 - (1 - math.clamp(t / 0.7, 0, 1)) ^ 3
	local forward = smooth((t - 0.25) / 0.75)
	return Vector3.new(start.X + (target.X - start.X) * forward, start.Y + (target.Y - start.Y) * up,
		start.Z + (target.Z - start.Z) * forward)
end

-- ---------- Kamera ----------
P.StrafeRoll = 1.6      -- Grad bei vollem Seitwärtslaufen
P.SlideRoll = 5         -- Grad beim Rutschen
P.LandDipMax = 0.9      -- Studs, so tief taucht die Kamera bei harten Landungen ein
P.HardLanding = 85      -- ab dieser Fallgeschwindigkeit bremst die Landung kurz (Studs/s)
P.HardLandingSlow = 0.6 -- Tempo-Faktor dabei
P.HardLandingTime = 0.3

-- Neigung (Grad): strafe = Anteil seitwärts (-1..1, + = rechts), slide = 0..1 (Rutschen, weich überblendet)
function P.Roll(strafe, slide, aiming)
	local roll = -math.clamp(strafe, -1, 1) * P.StrafeRoll * (1 - slide) + P.SlideRoll * slide
	return aiming and roll * 0.3 or roll
end

-- Eintauchen beim Landen (Studs nach unten) aus der Fallgeschwindigkeit
function P.LandDip(fallSpeed)
	return math.clamp((fallSpeed - 25) / 70, 0, 1) * P.LandDipMax
end

-- Wippen der Kamera beim Laufen (Studs nach unten): phase läuft mit der Strecke, speedRatio = Tempo / Gehtempo
-- Dezent: höchstens P.BobMax Studs (beim Sprinten), damit das Bild ruhig bleibt
P.BobMax = 0.018
function P.Bob(phase, speedRatio)
	local amount = math.clamp(speedRatio, 0, 1.3) / 1.3
	return -math.abs(math.sin(phase)) * P.BobMax * amount
end

return P

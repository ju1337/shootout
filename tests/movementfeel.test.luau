-- Bewegungsgefühl (MovementPhysics und Movement auf dem Client): Tempo läuft weich an und schneller ab, Rutschen mit
-- Schub, Reibung, Hang und Lenken, Rutsch-Sprung-Ketten bringen kein Dauer-Tempo, Rutsch-Sprung nimmt Schwung mit,
-- Coyote-Time und Sprungpuffer, im Lauf über dünne Hindernisse drüber, an Kanten hoch (auch aus dem Sprung), zu hohe
-- Wände nicht, harte Landung bremst kurz. Alle Tempi bleiben unter dem Server-Check (MovementGuard).
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-3)
end

local P = require("MovementPhysics")
local DT = 1 / 60
local G = 196.2
local GUARD_FLAT = 62 -- MovementGuard: erlaubtes Dauertempo waagerecht

-- ---------- Rechnungen ----------
-- Tempo-Rampe: Anlaufen spürbar, Abbremsen schneller
local speed, t = 16, 0
while speed < 24 - 1e-6 and t < 2 do
	speed = P.Approach(speed, 24, DT)
	t += DT
end
check(t > 0.15 and t < 0.35, "Gehen -> Sprint läuft in 0,15-0,35 s an (" .. t .. ")")
speed, t = 24, 0
while speed > 16 + 1e-6 and t < 2 do
	speed = P.Approach(speed, 16, DT)
	t += DT
end
check(t < 0.15, "Abbremsen schneller als Anlaufen (" .. t .. ")")

-- Rutschen: flach, bergab, bergauf
local function slideRun(startSpeed, slope, crouch)
	local s, time, dist = startSpeed, 0, 0
	while not P.SlideOver(s, crouch, time) do
		s = P.SlideStep(s, DT, slope, G)
		time += DT
		dist += s * DT
	end
	return time, dist
end
local start = P.SlideStart(24, 24, math.huge)
check(near(start, 24 + P.SlideBoost), "Start aus dem Sprint mit vollem Schub (" .. start .. ")")
check(P.SlideStart(24, 24, 0.2) < start - 5, "direkt nochmal rutschen: kaum Schub")
check(P.SlideStart(60, 24, math.huge) == P.SlideMax, "nie schneller als SlideMax")
local flatTime, flatDist = slideRun(start, 0, 8)
check(flatTime > 0.8 and flatTime < 1.5, "flach rutscht man 0,8-1,5 s (" .. flatTime .. ")")
check(flatDist > 15 and flatDist < 35, "flach 15-35 Studs weit (" .. flatDist .. ")")
local downTime, downDist = slideRun(start, math.sin(math.rad(20)), 8)
check(downTime > flatTime + 0.5 and downDist > flatDist * 1.5, "bergab weiter und länger (" .. downTime .. " s, "
	.. downDist .. " Studs)")
local upTime = slideRun(start, -math.sin(math.rad(20)), 8)
check(upTime < flatTime * 0.7, "bergauf kürzer (" .. upTime .. " s)")
local steep = start
for _ = 1, 600 do
	steep = P.SlideStep(steep, DT, 0.9, G)
end
check(steep <= P.SlideMax + 1e-6 and P.SlideMax < GUARD_FLAT, "steil bergab höchstens SlideMax, unter dem Server-Check")
check(P.SlideOver(30, 8, P.SlideMaxTime), "Rutschen endet spätestens nach SlideMaxTime")
check(near(P.SlopeAlong(Vector3.new(math.sin(0.3), math.cos(0.3), 0), Vector3.new(1, 0, 0)), math.sin(0.3))
	and P.SlopeAlong(Vector3.new(0, 1, 0), Vector3.new(1, 0, 0)) == 0, "Hangneigung aus der Boden-Normalen")

-- Rutsch-Sprung-Ketten: immer wieder rutschen und springen bleibt nahe am Sprint
local v, clock, lastEnd = 24, 0, -math.huge
for _ = 1, 15 do
	v = P.SlideStart(v, 24, clock - lastEnd)
	for _ = 1, 18 do -- 0,3 s rutschen
		v = P.SlideStep(v, DT, 0, G)
		clock += DT
	end
	lastEnd = clock
	for _ = 1, 36 do -- 0,6 s in der Luft
		v = P.AirStep(v, DT)
		clock += DT
	end
	v = math.max(v, 24)
end
check(v < 34, "Rutsch-Sprung-Ketten bringen kein Dauer-Tempo (" .. v .. ")")

-- Lenken: höchstens SlideTurn pro Sekunde, nicht nach hinten
local dir = Vector3.new(1, 0, 0)
local turned = P.Steer(dir, Vector3.new(0, 0, -1), 0.1)
local angle = math.deg(math.acos(math.clamp(turned:Dot(dir), -1, 1)))
check(near(angle, math.deg(P.SlideTurn) * 0.1, 0.01), "Lenken höchstens SlideTurn pro Sekunde (" .. angle .. ")")
check(turned.Z < 0, "Lenken in die gewünschte Richtung")
check(P.Steer(dir, Vector3.new(-1, 0, 0), 0.1) == dir, "nach hinten ziehen lenkt nicht")
check(P.Steer(dir, Vector3.zero, 0.1) == dir, "ohne Eingabe geradeaus")
local d = dir
for _ = 1, 120 do
	d = P.Steer(d, Vector3.new(0, 0, 1), DT)
end
check(near(d.Z, 1, 1e-3) and near(d.Magnitude, 1, 1e-6), "Lenken erreicht das Ziel und bleibt Länge 1")

-- Coyote-Time, Sprungpuffer, Schwung in der Luft
check(P.CoyoteOk(10.1, 10.0, nil), "Sprung kurz nach der Kante zählt noch")
check(not P.CoyoteOk(10.2, 10.0, nil), "später nicht mehr")
check(not P.CoyoteOk(10.05, 10.0, 10.0), "nicht nach einem echten Sprung")
check(P.CoyoteOk(10.05, 10.0, 8.0), "ein älterer Sprung zählt nicht")
check(P.Buffered(5.1, 5.0) and not P.Buffered(5.3, 5.0) and not P.Buffered(5.1, nil), "Sprungpuffer 0,15 s")
check(near(P.AirStep(40, 1), 40 - P.AirDrag) and P.AirStep(1, 1) == 0, "Schwung in der Luft nimmt langsam ab")
check(P.AirMomentumMax < GUARD_FLAT, "Schwung in der Luft unter dem Server-Check")

-- Hindernisse
check(P.Classify(3, true, nil, true, true) == "Vault", "im Lauf über eine dünne Mauer")
check(P.Classify(3, true, nil, true, false) == "Mantle", "langsam auf die dünne Mauer")
check(P.Classify(6, false, nil, true, true) == "Mantle", "an einer hohen Kante hoch")
check(P.Classify(6, true, nil, true, true) == "Mantle", "zu hoch zum Drüberspringen: hochziehen")
check(P.Classify(9, false, nil, true, true) == nil, "zu hohe Wand: nichts")
check(P.Classify(1, true, nil, true, true) == nil, "Stufe: einfach weiterlaufen")
check(P.Classify(5, false, nil, false, true) == nil, "kein Platz über der Kante: nichts")
check(P.Classify(3, false, 10, true, true) == nil, "aus dem Sprung nicht höher als MantleFromGround über dem Boden")
-- Bahnen
local s0, near0, far0, land0 = Vector3.new(0, 3, 0), Vector3.new(2, 7, 0), Vector3.new(3, 7, 0), Vector3.new(5, 3, 0)
check((P.VaultPoint(s0, near0, far0, land0, 0) - s0).Magnitude < 1e-6
	and (P.VaultPoint(s0, near0, far0, land0, 1) - land0).Magnitude < 1e-6, "Vault-Bahn: Anfang und Ende")
local over = true
for i = 0, 200 do
	local p = P.VaultPoint(s0, near0, far0, land0, i / 200)
	if p.X >= near0.X and p.X <= far0.X and p.Y < near0.Y - 1e-6 then
		over = false
	end
end
check(over, "Vault-Bahn bleibt über dem ganzen Hindernis")
local target = Vector3.new(4, 9, 0)
local upFirst = true
for i = 0, 200 do
	local p = P.MantlePoint(s0, target, i / 200)
	if p.X > 2 and p.Y < target.Y - 0.05 then
		upFirst = false
	end
end
check(upFirst, "Hochziehen: erst oben, dann nach vorn über die Kante")
check((P.MantlePoint(s0, target, 1) - target).Magnitude < 1e-6, "Hochziehen endet auf der Kante")
-- Tempo der Bewegungen für den Server-Check (weitester Vault: Wand 4, Hindernis 4,5, Landung 1,6 dahinter)
local farthest = P.Reach + P.VaultThickness + 1.6
check(farthest / P.VaultTime(P.VaultMax, farthest) < GUARD_FLAT, "Vault waagerecht unter dem Server-Check")
check(P.MantleTime(P.MantleMax) >= 0.3 and P.MantleTime(2) >= 0.28, "Hochziehen dauert sichtbar")

-- Kamera
check(P.Roll(1, 0, false) < 0 and P.Roll(-1, 0, false) > 0, "seitwärts laufen neigt die Kamera")
check(near(P.Roll(0, 1, false), P.SlideRoll), "Rutschen neigt deutlich")
check(math.abs(P.Roll(1, 0, true)) < math.abs(P.Roll(1, 0, false)), "beim Zielen kaum Neigung")
check(P.LandDip(20) == 0 and near(P.LandDip(200), P.LandDipMax), "Eintauchen erst bei harten Landungen")
check(P.Bob(0, 1) == 0 and P.Bob(math.pi / 2, 1) < 0 and P.Bob(math.pi / 2, 0) == 0, "Wippen nur beim Laufen")
check(math.abs(P.Bob(math.pi / 2, 5)) <= 0.02, "Wippen dezent: höchstens 0,02 Studs, auch beim Sprinten")

-- ---------- Movement im Simulator ----------
-- Welt aus Quadern: Boden, eine dünne Mauer (3 hoch), ein Block (6 hoch), eine hohe Wand (12) und eine Kante in 8,5
local boxes = {}
local function box(center, size)
	local part = Instance.new("Part", workspace)
	part.Size = size
	part.CFrame = CFrame.new(center)
	table.insert(boxes, { Min = center - size / 2, Max = center + size / 2, Part = part })
end
box(Vector3.new(0, -5, 0), Vector3.new(1000, 10, 1000))
box(Vector3.new(4, 1.5, 0), Vector3.new(1, 3, 10))        -- dünne Mauer bei x = 3,5..4,5
box(Vector3.new(8, 3, 40), Vector3.new(10, 6, 10))        -- Block bei x = 3..13, oben 6
box(Vector3.new(8, 6, 80), Vector3.new(10, 12, 10))       -- hohe Wand, oben 12
box(Vector3.new(8, 4.25, 120), Vector3.new(10, 8.5, 10))  -- Kante in 8,5
local AXES = { "X", "Y", "Z" }
local UNIT = { X = Vector3.new(1, 0, 0), Y = Vector3.new(0, 1, 0), Z = Vector3.new(0, 0, 1) }
SIM.RaycastHandler = function(origin, direction)
	local best = nil
	for _, b in boxes do
		local tmin, tmax, normal, hit = 0, 1, nil, true
		for _, axis in AXES do
			local o, dd = origin[axis], direction[axis]
			local lo, hi = b.Min[axis], b.Max[axis]
			if math.abs(dd) < 1e-9 then
				if o < lo or o > hi then
					hit = false
					break
				end
			else
				local tNear = (dd > 0 and lo - o or hi - o) / dd
				local tFar = (dd > 0 and hi - o or lo - o) / dd
				if tNear > tmin then
					tmin, normal = tNear, UNIT[axis] * (dd > 0 and -1 or 1)
				end
				tmax = math.min(tmax, tFar)
				if tmin > tmax then
					hit = false
					break
				end
			end
		end
		if hit and normal and (not best or tmin < best.T) then
			best = { T = tmin, Normal = normal, Part = b.Part }
		end
	end
	if not best then
		return nil
	end
	return { Position = origin + direction * best.T, Normal = best.Normal, Distance = direction.Magnitude * best.T,
		Instance = best.Part, Material = Enum.Material.Concrete }
end

SIM.IsServer = false -- Client: RenderStep läuft (Kamera, Lenken beim Rutschen)
local InputActions = require("InputActions")
local UserInputService = game:GetService("UserInputService")
local bob = SIM.Join("Bob")
rawget(SIM.Players, "__props").LocalPlayer = bob
if not bob:FindFirstChild("PlayerGui") then
	Instance.new("PlayerGui", bob)
end
bob:LoadCharacter()
SIM.Advance(1, 60)
bob:SetAttribute("Mode", "FreeForAll")
local Movement = require("Movement")
Movement.Init()
SIM.Advance(0.2, 60)
local character = bob.Character
local humanoid = character:FindFirstChildOfClass("Humanoid")
local root = character:FindFirstChild("HumanoidRootPart")
local X = Vector3.new(1, 0, 0)
local function at(position, velocity)
	root.CFrame = CFrame.new(position)
	root.AssemblyLinearVelocity = velocity or Vector3.zero
	humanoid.FloorMaterial = Enum.Material.Plastic
end
local function frames(seconds)
	SIM.Advance(seconds, 60)
end
local function jump()
	UserInputService.JumpRequest:Fire()
end
at(Vector3.new(0, 3, -40))
frames(0.5)

-- Sprint: läuft weich an
check(near(humanoid.WalkSpeed, 16, 0.01), "Gehtempo am Anfang (" .. humanoid.WalkSpeed .. ")")
humanoid.MoveDirection = X
InputActions.Trigger("Sprint", true)
frames(1 / 60)
check(humanoid.WalkSpeed > 16 and humanoid.WalkSpeed < 23, "Sprint springt nicht sofort auf volles Tempo (" .. humanoid.WalkSpeed .. ")")
frames(0.5)
check(near(humanoid.WalkSpeed, 24, 0.01), "nach 0,5 s volles Sprinttempo (" .. humanoid.WalkSpeed .. ")")
check(Movement.IsSprinting(), "sprintet")

-- Rutschen: Schub, läuft aus, Tippen reicht
root.AssemblyLinearVelocity = X * 24
local fovBefore = workspace.CurrentCamera.FieldOfView
InputActions.Trigger("Crouch", true)
check(Movement.IsSliding(), "Ducken im Sprint = Rutschen")
check(near(humanoid.WalkSpeed, 24 + P.SlideBoost, 0.01), "Rutschen mit Schub (" .. humanoid.WalkSpeed .. ")")
InputActions.Trigger("Crouch", false)
-- Eingabe seitwärts (wie vom ControlModule): die Rutschrichtung dreht nur langsam mit, der Humanoid wird in die
-- Rutschrichtung geschoben, nicht in die Eingabe
humanoid.MoveDirection = Vector3.new(0, 0, 1)
frames(1 / 60)
local steered = humanoid.MoveDirection
check(steered.X > 0.99 and steered.Z > 0.01, "Rutschen lenkt langsam zur Eingabe (" .. tostring(steered) .. ")")
frames(0.3)
check(Movement.IsSliding() and humanoid.WalkSpeed < 24 + P.SlideBoost, "Tippen reicht, das Rutschen läuft aus")
check((humanoid.MoveDirection - steered).Magnitude < 1e-6, "ohne neue Eingabe bleibt die Rutschrichtung")
check(workspace.CurrentCamera.FieldOfView > fovBefore, "Sichtfeld weitet sich beim Rutschen")
frames(1.6)
check(not Movement.IsSliding(), "Rutschen endet von selbst")

-- Rutsch-Sprung: Schwung in die Luft, hält in der Luft, baut nach dem Landen ab
frames(1.5) -- Schub lädt wieder auf
humanoid.MoveDirection = X
root.AssemblyLinearVelocity = X * 24
InputActions.Trigger("Crouch", true)
InputActions.Trigger("Crouch", false)
frames(0.1)
local slideSpeed = humanoid.WalkSpeed
check(Movement.IsSliding() and slideSpeed > 28, "wieder am Rutschen (" .. slideSpeed .. ")")
jump()
check(not Movement.IsSliding() and near(Movement.State().AirMomentum, slideSpeed, 0.5), "Sprung aus dem Rutschen nimmt den Schwung mit")
humanoid.FloorMaterial = Enum.Material.Air
frames(0.4)
check(humanoid.WalkSpeed > 26, "in der Luft hält der Schwung (" .. humanoid.WalkSpeed .. ")")
humanoid.FloorMaterial = Enum.Material.Plastic
frames(0.5)
check(near(humanoid.WalkSpeed, 24, 0.01), "nach dem Landen zurück auf Sprinttempo (" .. humanoid.WalkSpeed .. ")")

-- Absprung im Sprint, in der Luft Sprint loslassen: das Tempo bleibt bis zur Landung
humanoid.FloorMaterial = Enum.Material.Air
frames(0.05)
InputActions.Trigger("Sprint", false)
frames(0.4)
check(humanoid.WalkSpeed > 21, "in der Luft bremst Sprint-Loslassen kaum (" .. humanoid.WalkSpeed .. ")")
humanoid.FloorMaterial = Enum.Material.Plastic
frames(0.3)
check(near(humanoid.WalkSpeed, 16, 0.01), "nach der Landung Gehtempo (" .. humanoid.WalkSpeed .. ")")
InputActions.Trigger("Sprint", true)
frames(0.5)
-- Rutsch-Sprung ohne Absprung (z.B. Decke über dem Kopf): der Schwung verfällt am Boden
frames(1.5)
root.AssemblyLinearVelocity = X * 24
humanoid.MoveDirection = X
InputActions.Trigger("Crouch", true)
InputActions.Trigger("Crouch", false)
frames(0.1)
jump()
check(Movement.State().AirMomentum > 24, "Schwung gemerkt")
frames(0.5)
check(Movement.State().AirMomentum == 0, "ohne Absprung verfällt der Schwung")
frames(0.5)

-- Coyote-Time: kurz nach dem Verlassen der Kante zählt der Sprung noch
humanoid:ChangeState(Enum.HumanoidStateType.Running)
frames(0.2)
humanoid.FloorMaterial = Enum.Material.Air
frames(0.05)
jump()
check(humanoid:GetState() == Enum.HumanoidStateType.Jumping, "Coyote-Time: Sprung kurz nach der Kante")
humanoid.FloorMaterial = Enum.Material.Plastic
humanoid:ChangeState(Enum.HumanoidStateType.Running)
frames(0.2)
humanoid.FloorMaterial = Enum.Material.Air
frames(0.3)
jump()
check(humanoid:GetState() == Enum.HumanoidStateType.Running, "zu spät: kein Sprung in der Luft")
-- Sprungpuffer: in der Luft gedrückt, beim Landen gesprungen
humanoid.Jump = false
humanoid.FloorMaterial = Enum.Material.Plastic
check(humanoid.Jump ~= true, "ohne Puffer kein Sprung")
frames(0.1)
humanoid.FloorMaterial = Enum.Material.Air
frames(0.3)
jump()
frames(0.05)
humanoid.FloorMaterial = Enum.Material.Plastic
frames(1 / 60)
check(humanoid.Jump == true, "Sprungpuffer: Sprung beim Landen")
humanoid.Jump = false

-- Harte Landung bremst kurz
humanoid.FloorMaterial = Enum.Material.Air
root.AssemblyLinearVelocity = Vector3.new(0, -110, 0)
frames(0.1)
root.AssemblyLinearVelocity = X * 24
humanoid.FloorMaterial = Enum.Material.Plastic
frames(0.2)
check(humanoid.WalkSpeed < 24 * P.HardLandingSlow + 0.5, "harte Landung bremst (" .. humanoid.WalkSpeed .. ")")
frames(0.6)
check(near(humanoid.WalkSpeed, 24, 0.01), "danach wieder volles Tempo")

-- Vault: im Lauf über die dünne Mauer, Schwung bleibt
at(Vector3.new(0, 3, 0), X * 24)
humanoid.MoveDirection = X
frames(1 / 60)
jump()
check(Movement.Obstacle() == "Vault", "im Lauf vor der dünnen Mauer: drüberspringen (" .. tostring(Movement.Obstacle()) .. ")")
local highest, vaultFrames = -math.huge, 0
while Movement.Obstacle() == "Vault" and vaultFrames < 60 do
	frames(1 / 60)
	vaultFrames += 1
	if root.Position.X > 3.4 and root.Position.X < 4.6 then
		highest = math.max(highest, root.Position.Y)
	end
end
check(Movement.Obstacle() == nil and vaultFrames < 30, "Vault vorbei nach " .. vaultFrames .. " Bildern")
check(root.Position.X > 5 and math.abs(root.Position.Y - 3) < 0.3, "hinter der Mauer gelandet (" .. tostring(root.Position) .. ")")
check(highest - 3 > 3, "über die Mauer hinweg, nicht durch (Füße über der Kante)")
check(humanoid.WalkSpeed >= 23, "Schwung bleibt nach dem Vault (" .. humanoid.WalkSpeed .. ")")

-- Mantle: langsam vor dem Block (6 hoch) -> hinauf
InputActions.Trigger("Sprint", false)
at(Vector3.new(0, 3, 40))
humanoid.MoveDirection = X
frames(0.5)
jump()
check(Movement.Obstacle() == "Mantle", "vor dem Block: hochziehen (" .. tostring(Movement.Obstacle()) .. ")")
frames(0.7)
check(Movement.Obstacle() == nil and near(root.Position.Y, 6 + 3, 0.2) and root.Position.X > 3.5,
	"oben auf dem Block (" .. tostring(root.Position) .. ")")

-- zu hohe Wand: nichts
at(Vector3.new(0, 3, 80))
humanoid.MoveDirection = X
frames(0.2)
jump()
check(Movement.Obstacle() == nil, "zu hohe Wand: kein Hochziehen")

-- Kante in 8,5: vom Boden zu hoch, aus dem Sprung (Leertaste gehalten, auf die Wand zu) erreichbar
at(Vector3.new(0, 3, 120))
humanoid.MoveDirection = X
frames(0.2)
jump()
check(Movement.Obstacle() == nil, "Kante in 8,5 vom Boden aus zu hoch")
SIM.KeysDown[Enum.KeyCode.Space] = true
humanoid.FloorMaterial = Enum.Material.Air
root.CFrame = CFrame.new(0, 4.6, 120)
frames(2 / 60)
check(Movement.Obstacle() == "Mantle", "aus dem Sprung an die Kante: hochziehen")
frames(0.7)
SIM.KeysDown[Enum.KeyCode.Space] = nil
check(near(root.Position.Y, 8.5 + 3, 0.2), "oben auf der Kante (" .. tostring(root.Position) .. ")")

-- Kamera-Neigung: beim Seitwärtslaufen ja, bei einer geskripteten Kamera (Agentenwahl, Zuschauen) nie
local camera = workspace.CurrentCamera
at(Vector3.new(0, 3, -80), camera.CFrame.RightVector * 24)
humanoid.MoveDirection = camera.CFrame.RightVector
local before = camera.CFrame
frames(0.3)
check(math.abs(camera.CFrame.UpVector:Dot(before.RightVector)) > 0.005, "seitwärts laufen neigt die Kamera")
camera.CameraType = Enum.CameraType.Scriptable
frames(0.1)
before = camera.CFrame
frames(0.5)
check((camera.CFrame.UpVector - before.UpVector).Magnitude < 1e-6, "geskriptete Kamera wird nie geneigt")
camera.CameraType = Enum.CameraType.Custom

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

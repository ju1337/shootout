-- MovementGuard: legale Bewegungen dürfen nie zurückgesetzt werden, Speedhacks und Teleports schon.
-- Simuliert wird mit 60 Bildern pro Sekunde: der Client bewegt den Charakter, der Server sieht die Position
-- (außer während Lag) und prüft im Heartbeat. Gespawnt wird mit dem echten SpawnUtil.Spawn (LoadCharacter wartet
-- dabei kurz, der Charakter steht so lange am Standard-Spawn).
local MovementGuard = require("MovementGuard")
local SpawnUtil = require("SpawnUtil")
local RunService = game:GetService("RunService")

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local FPS = 60
local DT = 1 / FPS
local GRAVITY = 196.2
SIM.LoadCharacterDelay = 0.3
MovementGuard.Init()

local function newWorld()
	for _, other in SIM.Players:GetPlayers() do
		SIM.Leave(other)
	end
	local player = SIM.AddPlayer("Spieler")
	local w = { Player = player, Pulls = 0, WarnStart = #SIM.Warnings, Character = nil, Client = Vector3.zero }
	-- Ein Bild: Zeit läuft weiter, der Client bewegt sich mit vel, der Server sieht es (außer bei lag) und prüft
	-- (außer bei hitch: Server hängt)
	local function frame(vel, lag, hitch)
		SIM.Run(SIM.Now + DT)
		local character = w.Character
		if character then
			w.Client += vel * DT
			if not lag then
				character.HumanoidRootPart.Position = w.Client
			end
		end
		if not hitch then
			RunService.Heartbeat:Fire(DT)
		end
	end
	-- Client bewegt sich seconds lang mit vel (Vector3 oder function(t) -> Vector3)
	function w:Step(seconds, vel, lag, hitch)
		local started = SIM.Now
		for _ = 1, math.floor(seconds * FPS + 0.5) do
			local v = type(vel) == "function" and vel(SIM.Now - started) or vel or Vector3.zero
			frame(v, lag, hitch)
		end
	end
	function w:Spawn(position)
		self.Character = nil
		local done = false
		task.spawn(function()
			SpawnUtil.Spawn(player, CFrame.new(position))
			done = true
		end)
		while not done do
			frame(Vector3.zero)
		end
		local character = player.Character
		self.Character = character
		self.Client = character.HumanoidRootPart.Position
		-- Korrekturen des Wächters zählen und übernehmen (der Client springt an die Stelle zurück)
		rawset(character, "__methods", {
			PivotTo = function(model, cframe)
				SIM.ClassMethods.Model.PivotTo(model, cframe)
				self.Pulls += 1
				self.Client = model.HumanoidRootPart.Position
			end,
		})
	end
	function w:Teleport(offset)
		self.Client += offset
	end
	-- Server versetzt selbst (Wiederbeleben hebt um 2 Studs an)
	function w:ServerMove(offset)
		local root = self.Character.HumanoidRootPart
		root.Position += offset
		self.Client = root.Position
	end
	function w:Warnings()
		return #SIM.Warnings - self.WarnStart
	end
	return w
end

local function legal(name, fn)
	local w = newWorld()
	w:Spawn(Vector3.new(500, 5, 500))
	fn(w)
	check(w.Pulls == 0 and w:Warnings() == 0, string.format("%s: %d-mal zurückgesetzt (legal)", name, w.Pulls))
	print("ok   legal: " .. name)
end

local SPRINT = 54 -- schnellster Sprint: 18 × 1,15 (Tempo-Faktor) × 1,6 (Adrenalin) × 1,5 × 1,08 (Runner)
local X = Vector3.new(1, 0, 0)
local function hop(t)
	return 50 - GRAVITY * (t % (2 * 50 / GRAVITY))
end

legal("Sprint geradeaus 20 s", function(w)
	w:Step(20, X * SPRINT)
end)
legal("Zickzack mit 56 Studs/s", function(w)
	w:Step(20, function(t)
		local a = math.floor(t * 2) * 1.3
		return Vector3.new(math.cos(a), 0, math.sin(a)) * 56
	end)
end)
legal("Sprint-Stoß alle 3 s", function(w)
	w:Step(20, function(t)
		return X * ((t % 3) < 0.25 and 90 or SPRINT)
	end)
end)
legal("Sprint-Stoß direkt nacheinander (3×)", function(w)
	w:Step(0.75, X * 90)
	w:Step(5, X * SPRINT)
end)
legal("Rutschen nach dem Sprint", function(w)
	w:Step(20, function(t)
		local phase = t % 1.9
		return X * (phase < 1.2 and SPRINT or 42 + (18 - 42) * (phase - 1.2) / 0.7)
	end)
end)
legal("Fallschirmsprung aus 120 Studs", function(w)
	w:Spawn(Vector3.new(500, 125, 500))
	w:Step(30, function()
		local height = w.Client.Y - 5
		if height > 25 then
			return Vector3.new(55, -35, 0)
		elseif height > 0 then
			return Vector3.new(16.5, -6, 0)
		end
		return X * SPRINT
	end)
end)
legal("Treppe im Sprint, Hüpfen, Hochziehen", function(w)
	w:Step(0.4, Vector3.new(SPRINT, 30, 0))
	w:Step(5, function(t)
		return Vector3.new(SPRINT, hop(t), 0)
	end)
	-- Hochziehen auf Kanten: Sprung bis 6,4 Studs, dann 6,6 Studs hoch in 0,19 s, mehrmals hintereinander
	for _ = 1, 6 do
		w:Step(0.255, function(t)
			return Vector3.new(0, 50 - GRAVITY * t, 0)
		end)
		w:Step(0.19, Vector3.new(4.7 / 0.3, 6.6 / 0.19, 0))
		w:Step(0.11, Vector3.new(4.7 / 0.3, 0, 0))
	end
end)
-- Neue Bewegung (MovementPhysics): Rutschen bergab mit Höchsttempo, Rutsch-Sprünge mit Schwung, Vault und Hochziehen
local MP = require("MovementPhysics")
legal("Rutschen bergab (Höchsttempo) und Rutsch-Sprünge mit Schwung", function(w)
	w:Step(1, X * SPRINT)
	for _ = 1, 4 do
		w:Step(MP.SlideMaxTime, X * MP.SlideMax)
		w:Step(0.65, function(t)
			return Vector3.new(MP.AirStep(MP.AirMomentumMax, t), 50 - GRAVITY * t, 0)
		end)
	end
end)
legal("Vault und Hochziehen an den größten Hindernissen, direkt nacheinander", function(w)
	-- Bahn (Position relativ zum Start, u = 0..1) über duration Sekunden abfahren
	local function along(duration, point)
		w:Step(duration, function(t)
			return (point(math.min(1, (t + DT) / duration)) - point(math.min(1, t / duration))) / DT
		end)
	end
	for _ = 1, 5 do
		w:Step(0.5, X * SPRINT)
		-- Vault: Wand 4 vor einem, Hindernis 4,5 tief und 4,4 hoch, Landung 1,6 dahinter (Füße 0,5 über der Kante)
		local nearP, farP, land = Vector3.new(4.3, 4.9, 0), Vector3.new(8.5, 4.9, 0), Vector3.new(10.1, 0, 0)
		along(MP.VaultTime(MP.VaultMax, 10.1), function(u)
			return MP.VaultPoint(Vector3.zero, nearP, farP, land, u)
		end)
		w:Step(0.3, X * SPRINT)
		-- Sprung an eine Kante, dann hochziehen (7,8 über den Füßen)
		w:Step(0.2, function(t)
			return Vector3.new(SPRINT * 0.5, 50 - GRAVITY * t, 0)
		end)
		local target = Vector3.new(3.4, MP.MantleMax, 0)
		along(MP.MantleTime(MP.MantleMax), function(u)
			return MP.MantlePoint(Vector3.zero, target, u)
		end)
		w:Step(0.3, X * 4)
	end
end)
legal("Lag auf der Treppe und beim Hüpfen", function(w)
	w:Step(1, Vector3.new(SPRINT, 30, 0), true)
	w:Step(1, X * SPRINT)
	w:Step(1, function(t)
		return Vector3.new(SPRINT, hop(t), 0)
	end, true)
	w:Step(1, X * SPRINT)
end)
legal("Lag-Spitzen bis 1,5 s im Sprint", function(w)
	for _, seconds in { 0.3, 0.5, 1, 1.5 } do
		w:Step(seconds, X * SPRINT, true)
		w:Step(2, X * SPRINT)
	end
end)
legal("Server hängt 3 s", function(w)
	w:Step(3, X * SPRINT, false, true)
	w:Step(2, X * SPRINT)
end)
legal("Fallen aus 300 Studs", function(w)
	w:Spawn(Vector3.new(500, 305, 500))
	w:Step(2, function(t)
		return Vector3.new(SPRINT, -math.min(GRAVITY * t, 300), 0)
	end)
end)
legal("Wiederbeleben hebt um 2 Studs an", function(w)
	w:Step(1, Vector3.zero)
	w:ServerMove(Vector3.new(0, 2, 0))
	w:Step(1, X * SPRINT)
end)
legal("Respawn an anderer Stelle", function(w)
	w:Step(2, X * SPRINT)
	w:Spawn(Vector3.new(-900, 40, 1200))
	w:Step(2, X * SPRINT)
end)
legal("Tod mit Wegschleudern", function(w)
	w:Step(1, X * SPRINT)
	w.Character:FindFirstChildOfClass("Humanoid").Health = 0
	w:Step(2, Vector3.new(500, 200, 0))
end)
legal("Zufällige Bewegung mit Lag und Hängern (5 min)", function(w)
	local random = Random.new(7)
	for _ = 1, 150 do
		local angle = random:NextNumber(0, math.pi * 2)
		local speed = ({ 16, 24, SPRINT, 56, 42 })[random:NextInteger(1, 5)]
		local vel = Vector3.new(math.cos(angle) * speed, 0, math.sin(angle) * speed)
		local r = random:NextNumber()
		if r < 0.1 then
			w:Step(0.25, vel.Unit * 90) -- Sprint-Stoß
		elseif r < 0.2 then
			w:Step(random:NextNumber(0, 1.2), vel, true) -- Lag
		elseif r < 0.25 then
			w:Step(random:NextNumber(0, 2), vel, false, true) -- Server hängt
		end
		w:Step(random:NextNumber(0, 2.5), vel)
	end
end)

-- ---------- Verstöße ----------
local function exploit(name, fn)
	local w = newWorld()
	w:Spawn(Vector3.new(0, 5, 0))
	fn(w)
	print(string.format("ok   Verstoß: %s (%d-mal zurückgesetzt, %d Warnungen)", name, w.Pulls, w:Warnings()))
end

exploit("Teleport 300 Studs", function(w)
	w:Step(1, X * SPRINT)
	w:Teleport(X * 300)
	w:Step(0.5, Vector3.zero)
	check(w.Pulls == 1, "Teleport: einmal zurückgesetzt, war " .. w.Pulls)
	check(math.abs(w.Client.X - SPRINT) <= 10, "Teleport: zurück an der alten Stelle, X = " .. w.Client.X)
	check(w:Warnings() == 1, "Teleport: eine Warnung")
end)
exploit("Teleport 60 Studs nach oben", function(w)
	w:Step(1, Vector3.zero)
	w:Teleport(Vector3.new(0, 60, 0))
	w:Step(0.5, Vector3.zero)
	check(w.Pulls == 1 and math.abs(w.Client.Y - 5) < 0.01, "Teleport nach oben zurückgesetzt")
end)
exploit("Teleport direkt nach dem Spawn", function(w)
	w:Teleport(Vector3.new(200, 0, 0))
	w:Step(0.5, Vector3.zero)
	check(w.Pulls == 1 and (w.Client - Vector3.new(0, 5, 0)).Magnitude < 0.01,
		"Spawn-Teleport: zurück am Spawn, war " .. tostring(w.Client))
end)
exploit("Speedhack 150 Studs/s für 10 s", function(w)
	w:Step(10, X * 150)
	check(w.Pulls > 0, "Speedhack 150 erkannt")
	check(w.Client.X <= 62 * 10 + 100 + 10, "Speedhack 150 begrenzt, X = " .. w.Client.X)
	check(w:Warnings() <= 3, "Warnungen begrenzt (höchstens alle 5 s), waren " .. w:Warnings())
end)
exploit("Speedhack 80 Studs/s für 30 s", function(w)
	w:Step(30, X * 80)
	check(w.Pulls > 0, "Speedhack 80 erkannt")
	check(w.Client.X <= 62 * 30 + 100 + 10, "Speedhack 80 begrenzt, X = " .. w.Client.X)
end)
exploit("Fliegen nach oben mit 80 Studs/s für 5 s", function(w)
	w:Step(5, Vector3.new(0, 80, 0))
	check(w.Pulls > 0, "Fliegen erkannt")
	check(w.Client.Y - 5 <= 50 * 5 + 40 + 10, "Fliegen begrenzt, Höhe = " .. w.Client.Y)
end)
exploit("Neues HumanoidRootPart an fremder Stelle", function(w)
	w:Step(1, Vector3.zero)
	local character = w.Character
	local old = character.HumanoidRootPart
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(300, 5, 0)
	old:Destroy()
	root.Parent = character
	w.Client = root.Position
	w:Step(0.5, Vector3.zero)
	check(w.Pulls == 1 and (w.Client - Vector3.new(0, 5, 0)).Magnitude < 0.01,
		"neues Root zurückgesetzt, war " .. tostring(w.Client))
end)
legal("Admin-Noclip: frei fliegen wird nicht zurückgesetzt", function(w)
	w.Player:SetAttribute("Noclip", true)
	w:Step(3, Vector3.new(0, 80, 80))
	check(w.Pulls == 0, "im Noclip kein Zurücksetzen (" .. w.Pulls .. ")")
	w.Player:SetAttribute("Noclip", nil)
	w:Step(1, Vector3.zero)
	check(w.Pulls == 0, "nach dem Noclip gilt die neue Stelle")
end)
exploit("Spieler geht, Eintrag wird entfernt", function(w)
	w:Step(0.5, Vector3.zero)
	SIM.Leave(w.Player)
	w.Character = nil
	w:Step(0.5, Vector3.zero)
	check(w.Pulls == 0, "nach dem Verlassen nichts mehr geprüft")
end)

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

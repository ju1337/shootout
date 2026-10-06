-- MovementGuard (ModuleScript, nur Server)
-- Einfacher Bewegungs-Check gegen Speedhacks und Teleports. Charaktere werden vom Client bewegt; der Server
-- vergleicht alle CHECK_INTERVAL Sekunden die zurückgelegte Strecke mit dem erlaubten Tempo. Erlaubt ist ein
-- Dauertempo plus ein Vorrat (Sprint-Stoß, Lag-Spitzen: der Server bekommt die Bewegung dann gebündelt), getrennt
-- waagerecht und nach oben. Fallen ist frei. Wer mehr zurücklegt, wird an die letzte gültige Stelle zurückgesetzt.
-- Tote Charaktere werden nicht geprüft (Ragdoll), Insassen von Fahrzeugen auch nicht (VehicleService prüft das Tempo).
-- Versetzt der Server einen Charakter selbst (Spawn), muss er danach MovementGuard.Teleported(character) aufrufen,
-- sonst gilt die neue Stelle als Teleport.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MovementGuard = {}

local CHECK_INTERVAL = 0.2 -- so oft wird geprüft (Sekunden)
-- Schnellste legale Bewegung waagerecht: Sprint mit Tempo-Fähigkeit und Runner ca. 47 Studs/s,
-- Fallschirmsprung 55, Rutschen bis 50 (bergab, MovementPhysics.SlideMax), Schwung in der Luft bis 46,
-- Vault ca. 24, Sprint-Stoß 90 (nur 0,25 s)
local FLAT_SPEED = 62      -- erlaubtes Dauertempo waagerecht (Studs/s)
local FLAT_BURST = 100     -- Vorrat dafür (Studs)
-- Steigen: Treppen im Sprint ca. 30 Studs/s, Sprung 6,4 Studs, Hochziehen an Kanten bis 7,8 Studs (aus dem Sprung bis
-- 9,5 über dem Boden), Vault bis 4,9 Studs
local UP_SPEED = 50        -- erlaubtes Steigen (Studs/s)
local UP_BURST = 40        -- Vorrat dafür (Studs)
local WARN_INTERVAL = 5    -- höchstens so oft (Sekunden) pro Spieler eine Warnung ins Log

-- [Player] = { Character, Root, Position (letzte gültige Stelle), Flat, Up (Vorräte), Time, Flags, WarnedAt }
local tracks = {}

local function newTrack(character, root, now)
	return { Character = character, Root = root, Position = root.Position, Flat = FLAT_BURST, Up = UP_BURST,
		Time = now, Flags = 0, WarnedAt = -math.huge }
end

-- Vorrat auffüllen: Dauertempo × vergangene Zeit, höchstens bis zum Vorrat. Hing der Server selbst länger
-- (großes dt), gilt mindestens die Strecke, die in dieser Zeit erlaubt ist.
local function refill(budget, speed, burst, dt)
	local gain = speed * dt
	return math.max(math.min(burst, budget + gain), gain)
end

-- true = Bewegung seit der letzten Prüfung ist erlaubt
local function check(track, now)
	local dt = now - track.Time
	track.Time = now
	track.Flat = refill(track.Flat, FLAT_SPEED, FLAT_BURST, dt)
	track.Up = refill(track.Up, UP_SPEED, UP_BURST, dt)
	local position = track.Root.Position
	local delta = position - track.Position
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local up = math.max(0, delta.Y)
	if flat <= track.Flat and up <= track.Up then
		track.Flat -= flat
		track.Up -= up
		track.Position = position
		return true
	end
	return false, flat, up
end

-- An die letzte gültige Stelle zurücksetzen (Blickrichtung bleibt)
local function pullBack(player, track, flat, up, now)
	local root = track.Root
	track.Character:PivotTo(CFrame.new(track.Position) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	track.Flags += 1
	if now - track.WarnedAt >= WARN_INTERVAL then
		track.WarnedAt = now
		warn(string.format("MovementGuard: %s zurückgesetzt (%.0f Studs waagerecht, %.0f nach oben; %d. Mal)",
			player.Name, flat, up, track.Flags))
	end
end

local function step(now)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local track = tracks[player]
		if not humanoid or not root or humanoid.Health <= 0 or not root:IsDescendantOf(workspace) then
			tracks[player] = nil
		elseif player:GetAttribute("Noclip") then
			-- Admin-Noclip: frei fliegen erlaubt; danach gilt die Stelle neu
			tracks[player] = newTrack(character, root, now)
		elseif humanoid.SeatPart and humanoid.SeatPart:GetAttribute("Vehicle") then
			-- im Fahrzeug der offenen Welt: das prüft VehicleService; nach dem Aussteigen gilt die Stelle neu
			tracks[player] = newTrack(character, root, now)
		elseif not track or track.Character ~= character then
			tracks[player] = newTrack(character, root, now)
		else
			track.Root = root -- neues HumanoidRootPart im selben Charakter: weiter von der letzten Stelle aus prüfen
			local ok, flat, up = check(track, now)
			if not ok then
				pullBack(player, track, flat, up, now)
			end
		end
	end
end

-- Nach einem Versetzen durch den Server (Spawn): die aktuelle Stelle gilt als gültig
function MovementGuard.Teleported(character)
	local player = Players:GetPlayerFromCharacter(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if player and root then
		tracks[player] = newTrack(character, root, os.clock())
	end
end

function MovementGuard.Init()
	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now >= nextCheck then
			nextCheck = now + CHECK_INTERVAL
			step(now)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
	end)
end

return MovementGuard

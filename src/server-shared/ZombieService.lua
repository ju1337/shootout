-- ZombieService (ModuleScript, nur Server)
-- Zombies der offenen Welt (EXTINCTION): Sobald Spieler außerhalb der Safe Zone sind, spawnen um jeden herum
-- Zombies im weiteren Umkreis (ExtinctionConfig.Zombies: SpawnMin bis SpawnMax Studs, höchstens PerPlayer pro
-- Spieler und MaxTotal auf dem Server) – nur auf dem Boden (nicht auf Dächern), nicht im Wasser und nicht nah an der
-- Safe Zone. Sie schlurfen herum, bemerken Spieler in SightRange, rennen hin und schlagen zu (AttackDamage alle
-- AttackDelay Sekunden). In die Safe Zone gehen sie nicht (sie bleiben am Rand stehen), dort gibt es auch keinen
-- Schaden.
-- Wegfindung (ExtinctionConfig.ZombiePath): beim Jagen prüft ein Raycast auf Brusthöhe (ohne Charaktere, Zombies und
-- Beute), ob die gerade Linie zum Ziel frei ist. Wenn ja: direkt hin (MoveTo). Wenn nicht (Mauern, Häuser, Ruinen):
-- Pfad vom PathfindingService, Wegpunkt für Wegpunkt (Jump-Wegpunkte: springen), jeder Wegpunkt mit clampOutside.
-- Neuer Pfad frühestens alle Recompute Sekunden und nur, wenn das Ziel sich mehr als MoveTolerance Studs bewegt hat,
-- der Pfad fehlschlug oder verbaut wurde; pro Heartbeat höchstens PerFrame Berechnungen für alle Zombies zusammen
-- (die Berechnung läuft in einem eigenen Thread, bis sie fertig ist läuft der Zombie gerade). Ohne Pfad: gerade hin.
-- Ohne Ziel (Schlurfen) keine Wegfindung. Wer eine Weile keinen Spieler draußen in der Nähe hat, verschwindet. Bots der offenen Welt (Admin-Panel,
-- options.Bots) jagen sie genauso wie Spieler.
-- Arten (ExtinctionConfig.ZombieKinds): Walker (normal, langsam), in der roten Zone auch Läufer (schneller) und Brocken
-- (groß, zäh, schlägt hart). In der roten Zone (RedzoneService) spawnen mehr Zombies, innerhalb der Zone.
-- Anti-Zombie-Spritze (Charakter-Attribut ZombieShieldUntil): solange sie wirkt, spawnt näher als Zombies.ShieldRadius am
-- Spieler kein Zombie – egal woher (Umgebung, rote Zone, Schreier, Nester, Lootdrop-Begleiter, Bosse).
-- Tod: der Schütze bekommt Münzen (je Art, wenig). Beute steckt in der Leiche (LootService.Attach): E öffnet das
-- Beute-Fenster, dort nimmt man Items einzeln heraus; F nimmt alles (nur mit dem Gamepass ALLES LOOTEN). Die Leiche
-- bleibt ExtinctionConfig.Zombies.CorpseLootTime Sekunden liegen, leer geräumt verschwindet sie kurz darauf.
-- In der roten Zone gestorben: doppelte Münzen und bessere Beute (ExtinctionConfig.Redzone.Loot).
-- Körper: einfacher R6-Körper (6 Teile, schnell), Arme nach vorn, rote Augen; Animation: Roblox-Standard (R6).
-- Modelle in Workspace.Zombies, Attribut IsZombie (Messer und Schüsse treffen sie, der Ping-Ausgleich kennt sie).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local DayCycle = require(Shared.DayCycle)
local Sfx = require(Shared.Sfx)
local Damage = require(script.Parent.Damage)
local ProgressService = require(script.Parent.ProgressService)
local Telemetry = require(script.Parent.Telemetry)
local LootService = require(script.Parent.LootService)

local ZombieService = {}

local Z = ExtinctionConfig.Zombies
local P = ExtinctionConfig.ZombiePath
local AI_STEP = 0.25        -- Sekunden zwischen zwei KI-Schritten je Zombie (über die Frames verteilt, info.NextAI)
local WANDER_RADIUS = 30
local LONELY_TIME = 8       -- so lange ohne Spieler draußen in der Nähe, dann verschwindet ein Zombie
local CORPSE_RANGE = 9      -- so nah muss man an der Leiche sein, um sie zu durchsuchen

-- Standard-Animationen von Roblox (R6)
local ANIMATIONS = {
	Idle = "rbxassetid://180435571",
	Walk = "rbxassetid://180426354",
}

local folder = workspace:FindFirstChild("Zombies") or Instance.new("Folder")
folder.Name = "Zombies"
folder.Parent = workspace

local options = nil  -- { Map, InSafeZone(position), SafeCenter(), Players() -> Liste der Spieler in der offenen Welt,
                     --   RedzoneAt(position) -> Zone | nil, IsWater(x, z) -> bool, Bots() -> Bot-Modelle (auch Ziele) }
local zombies = {}   -- [Model] = { Humanoid, Root, Target, NextAttack, NextWander, LastPos, StuckTime, Speed, Walk, Damage, Coins, Kind,
                     --   Path, Waypoints, WaypointIndex, PathGoal, PathAt, PathBusy, PathBlocked (Wegfindung, siehe followPath) }
local pathBudget = 0 -- Pfad-Berechnungen, die in dieser KI-Runde (AI_STEP) noch erlaubt sind (ZombiePath.PerFrame)
local castParams = nil -- RaycastParams für die Sichtlinie beim Jagen (je KI-Runde neu: ohne Charaktere, Zombies, Beute)
local count = 0
local template = nil
local random = Random.new()

-- Werte einer Art (fehlende Werte kommen aus ExtinctionConfig.Zombies / ZombieCoins / ZombieDropChance)
function ZombieService.Kind(name)
	local kind = ExtinctionConfig.ZombieKinds[name] or ExtinctionConfig.ZombieKinds.Walker
	return {
		Id = ExtinctionConfig.ZombieKinds[name] and name or "Walker",
		Name = kind.Name or "Zombie",
		Health = kind.Health or Z.Health,
		Walk = kind.Walk or Z.WalkSpeed,
		Run = kind.Run or Z.RunSpeed,
		Damage = kind.Damage or Z.AttackDamage,
		Coins = kind.Coins or ExtinctionConfig.ZombieCoins,
		XP = kind.XP or ExtinctionConfig.ZombieXP,
		Scale = kind.Scale or 1,
		Drop = kind.Drop or ExtinctionConfig.ZombieDropChance,
		Items = kind.Items or { 1, 1 },
		Table = kind.Table or "Zombie",
		Eyes = kind.Eyes or Color3.fromRGB(255, 40, 30),
		Scream = kind.Scream == true,
		Boss = kind.Boss == true,
	}
end

-- Art würfeln: Sturmnacht (Storm.KindWeights), rote Zone (Redzone.KindWeights), sonst Tag/Nacht (Zombies.KindWeights /
-- NightKindWeights)
local function rollKind(inRedzone)
	local night = DayCycle.IsNight(DayCycle.Clock(workspace:GetServerTimeNow()))
	local blood = DayCycle.IsBloodMoon(workspace:GetServerTimeNow())
	local storm = DayCycle.IsStorm(workspace:GetServerTimeNow())
	local weights = (storm and ExtinctionConfig.Storm.KindWeights) or inRedzone and ExtinctionConfig.Redzone.KindWeights
		or (blood and ExtinctionConfig.Day.BloodMoonKindWeights) or (night and Z.NightKindWeights or Z.KindWeights) or { Walker = 1 }
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll = random:NextNumber(0, total)
	local last = "Walker"
	for name, weight in weights do
		last = name
		roll -= weight
		if roll <= 0 then
			return name
		end
	end
	return last
end


-- R6-Körper aus Teilen und Gelenken (Standardmaße von Roblox)
local function part(model, name, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function joint(name, part0, part1, c0, c1)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = part0
	return motor
end

local function buildTemplate()
	local model = Instance.new("Model")
	model.Name = "Zombie"
	local skin, shirt, pants = Color3.fromRGB(122, 146, 104), Color3.fromRGB(96, 78, 64), Color3.fromRGB(56, 60, 74)
	local root = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), skin)
	root.Transparency = 1
	root.CanCollide = false
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), shirt)
	local head = part(model, "Head", Vector3.new(2, 1, 1), skin)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local leftArm = part(model, "Left Arm", Vector3.new(1, 2, 1), skin)
	local rightArm = part(model, "Right Arm", Vector3.new(1, 2, 1), skin)
	local leftLeg = part(model, "Left Leg", Vector3.new(1, 2, 1), pants)
	local rightLeg = part(model, "Right Leg", Vector3.new(1, 2, 1), pants)
	root.CFrame = CFrame.new(0, 3, 0)
	torso.CFrame = root.CFrame
	head.CFrame = root.CFrame * CFrame.new(0, 1.5, 0)
	leftArm.CFrame = root.CFrame * CFrame.new(-1.5, 0, 0)
	rightArm.CFrame = root.CFrame * CFrame.new(1.5, 0, 0)
	leftLeg.CFrame = root.CFrame * CFrame.new(-0.5, -2, 0)
	rightLeg.CFrame = root.CFrame * CFrame.new(0.5, -2, 0)
	local rootC = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	joint("RootJoint", root, torso, rootC, rootC)
	joint("Neck", torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	-- Arme nach vorn gestreckt (Zombie-Haltung), die Lauf-Animation schwingt um diese Lage
	joint("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) * CFrame.Angles(0, 0, math.rad(80)),
		CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	joint("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) * CFrame.Angles(0, 0, math.rad(-80)),
		CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	joint("Right Hip", torso, rightLeg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	joint("Left Hip", torso, leftLeg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	-- rote Augen
	for _, x in { -0.22, 0.22 } do
		local eye = part(model, "Eye", Vector3.new(0.18, 0.12, 0.05), Color3.fromRGB(255, 40, 30))
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.Massless = true
		eye.CFrame = head.CFrame * CFrame.new(x, 0.12, -0.6)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = eye
		weld.Parent = eye
	end
	-- Blut und Wunden (bleiben beim Umfärben dunkelrot)
	for _, info in { { torso, Vector3.new(1.2, 0.9, 0.06), CFrame.new(0.3, -0.2, -0.52) },
		{ torso, Vector3.new(0.7, 0.5, 0.06), CFrame.new(-0.5, 0.5, 0.52) },
		{ head, Vector3.new(0.5, 0.35, 0.06), CFrame.new(-0.3, -0.25, -0.62) },
		{ rightArm, Vector3.new(0.06, 0.8, 0.6), CFrame.new(0.52, -0.4, 0) } } do
		local blood = part(model, "Blood", info[2], Color3.fromRGB(92, 14, 12))
		blood.Material = Enum.Material.Glass
		blood.CanCollide = false
		blood.CanQuery = false
		blood.CanTouch = false
		blood.Massless = true
		blood.CFrame = info[1].CFrame * info[3]
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = info[1]
		weld.Part1 = blood
		weld.Parent = blood
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid
	model.PrimaryPart = root
	model:SetAttribute("IsZombie", true)
	model:SetAttribute("Mode", ExtinctionConfig.ModeId)
	return model
end

local function playAnimations(humanoid, speed)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local function load(id, priority)
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		if ok and track then
			track.Priority = priority
			track.Looped = true
			return track
		end
		return nil
	end
	local idle = load(ANIMATIONS.Idle, Enum.AnimationPriority.Idle)
	local walk = load(ANIMATIONS.Walk, Enum.AnimationPriority.Movement)
	if idle then
		idle:Play()
	end
	humanoid.Running:Connect(function(velocity)
		if not walk then
			return
		end
		if velocity > 1 then
			if not walk.IsPlaying then
				walk:Play()
			end
			walk:AdjustSpeed(math.clamp(velocity / speed, 0.5, 1.4) * 0.8) -- schlurfender Gang
		elseif walk.IsPlaying then
			walk:Stop()
		end
	end)
end

-- Lauf- und Stand-Animation für andere R6-Figuren (z. B. Überlebende); braucht einen Animator am Humanoid
function ZombieService.Animate(humanoid, speed)
	playAnimations(humanoid, speed)
end

-- ---------- Ziele ----------

-- Ziel ist ein Spieler oder ein Bot-Modell (Bots der offenen Welt, options.Bots)
local function livingRoot(target)
	local character = if target:IsA("Player") then target.Character else target
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return root, humanoid, character
	end
	return nil, nil, nil
end

-- Spieler (und Bots), die draußen sind (Zombies jagen nur sie)
local function huntable(target)
	local root = livingRoot(target)
	return root ~= nil and not target:GetAttribute("InSafeZone") and not options.InSafeZone(root.Position), root
end

local function nearestTarget(position, range)
	local best, bestDistance = nil, range
	local function consider(target)
		local ok, root = huntable(target)
		if ok and root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = target, distance
			end
		end
	end
	for _, player in options.Players() do
		consider(player)
	end
	for _, bot in options.Bots and options.Bots() or {} do
		consider(bot)
	end
	return best, bestDistance
end

-- Punkt am Rand der Safe Zone (Zombies bleiben draußen stehen)
-- Alle Safe Zones als { Center, Radius } (Camp und Safehouses; ohne SafeZones nur das Camp)
local function safeZones()
	if options.SafeZones then
		return options.SafeZones()
	end
	local center, radius = options.SafeCenter()
	return { { Center = center, Radius = radius } }
end

local function clampOutside(position)
	for _, zone in safeZones() do
		local center = zone.Center
		local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
		local limit = zone.Radius + 6
		if flat.Magnitude < limit and flat.Magnitude >= 0.01 then
			local edge = center + flat.Unit * limit
			return Vector3.new(edge.X, position.Y, edge.Z)
		end
	end
	return position
end

-- weit genug von allen Safe Zones?
local function nearPlayer(x, z, radius)
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and Vector3.new(x - root.Position.X, 0, z - root.Position.Z).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function farFromSafe(x, z, margin)
	for _, zone in safeZones() do
		if Vector3.new(x - zone.Center.X, 0, z - zone.Center.Z).Magnitude <= zone.Radius + margin then
			return false
		end
	end
	return true
end

-- ---------- Spawnen ----------

local function groundAt(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder }
	local loot = workspace:FindFirstChild("ExtinctionLoot")
	if loot then
		table.insert(ignore, loot)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	if options.IsWater and options.IsWater(x, z) then
		return nil
	end
	local base = options.Center.Y
	local result = workspace:Raycast(Vector3.new(x, base + 400, z), Vector3.new(0, -600, 0), params)
	-- nur Boden (Gelände, Straße, Boden-Teile) und nicht zu steil: kein Dach, kein Auto, kein Container
	if not result or result.Normal.Y < 0.8 then
		return nil
	end
	local hit = result.Instance
	local isGround = hit ~= nil and (hit:IsA("Terrain") or hit.Name == "Ground" or (hit.Parent ~= nil and (hit.Parent.Name == "Ground" or hit.Parent.Name == "Roads")))
	if not isGround or result.Material == Enum.Material.Water then
		return nil
	end
	return result.Position
end

-- Freie Stelle im weiteren Umkreis um position (nil, wenn keine passt)
local function spawnPoint(position)
	local half = ExtinctionConfig.WorldSize / 2 - 70
	for _ = 1, 8 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(Z.SpawnMin, Z.SpawnMax)
		local x, z = position.X + math.cos(angle) * distance, position.Z + math.sin(angle) * distance
		local fromCenter = Vector3.new(x - options.Center.X, 0, z - options.Center.Z)
		if math.abs(fromCenter.X) < half and math.abs(fromCenter.Z) < half and farFromSafe(x, z, Z.SafeMargin) then
			-- nicht direkt vor einem anderen Spieler auftauchen
			local tooClose = false
			for _, player in options.Players() do
				local root = livingRoot(player)
				if root and (Vector3.new(root.Position.X - x, 0, root.Position.Z - z)).Magnitude < Z.SpawnMin * 0.7 then
					tooClose = true
					break
				end
			end
			local ground = not tooClose and groundAt(x, z)
			if ground then
				return ground
			end
		end
	end
	return nil
end

-- Freie Stelle innerhalb der roten Zone (nicht direkt vor einem Spieler), nil wenn keine passt
local function redzoneSpawnPoint(zone)
	for _ = 1, 8 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = zone.Radius * math.sqrt(random:NextNumber(0.04, 0.8))
		local x, z = zone.Center.X + math.cos(angle) * distance, zone.Center.Z + math.sin(angle) * distance
		local tooClose = false
		for _, player in options.Players() do
			local root = livingRoot(player)
			if root and Vector3.new(root.Position.X - x, 0, root.Position.Z - z).Magnitude < 40 then
				tooClose = true
				break
			end
		end
		local ground = not tooClose and groundAt(x, z)
		if ground then
			return ground
		end
	end
	return nil
end

-- Beute für eine Leiche würfeln: { { Id, Count } } (leer = nichts)
-- Beute einer Leiche; blood = im Blutmond gespawnt: bessere Tabelle, höhere Chance, mehr Items; red = in der roten Zone
-- gestorben: noch eine Stufe besser, höhere Chance, ein Item mehr, größere Stapel (ExtinctionConfig.Redzone.Loot)
local function rollCorpseLoot(stats, blood, red)
	local B = ExtinctionConfig.BloodMoon
	local L = ExtinctionConfig.Redzone.Loot
	local chance = stats.Drop + (blood and B.DropBonus or 0) + (red and L.DropBonus or 0)
	if random:NextNumber() > chance then
		return {}
	end
	local tableName = blood and not stats.Boss and B.BetterTable[stats.Table] or stats.Table
	local amount = random:NextInteger(stats.Items[1], stats.Items[2]) + (blood and not stats.Boss and B.ExtraItems or 0)
	if red and not stats.Boss then
		return ExtinctionConfig.RedzoneRoll(tableName, amount, random)
	end
	return ExtinctionConfig.RollLoot(tableName, amount, random)
end
ZombieService.RollCorpseLoot = rollCorpseLoot

-- Großbuchstaben inkl. Umlaute (string.upper kennt nur ASCII: "Läufer" -> "LäUFER")
local function upper(text)
	local result = string.upper(text)
	result = string.gsub(result, "ä", "Ä")
	result = string.gsub(result, "ö", "Ö")
	result = string.gsub(result, "ü", "Ü")
	return result
end

-- Beute in der Leiche: E öffnet das Beute-Fenster (einzeln herausnehmen), F nimmt alles (Gamepass ALLES LOOTEN).
-- Leer geräumt verschwindet die Leiche kurz darauf.
local function attachCorpseLoot(model, root, info, items)
	local highlight = Instance.new("Highlight")
	highlight.Name = "LootHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 214, 110)
	highlight.OutlineTransparency = 0.35
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	local corpse = {}
	info.Corpse = corpse
	corpse.LootId = LootService.Attach(model, root, items, "LEICHE · " .. upper(info.Name), {
		PromptName = "CorpsePrompt",
		ActionText = "Durchsuchen",
		ObjectText = info.Name,
		Range = CORPSE_RANGE,
		Lifetime = Z.CorpseLootTime + 1, -- die Leiche selbst verschwindet nach CorpseLootTime (onDeath)
		OnRemoved = function()
			highlight:Destroy()
			if info.Corpse == corpse then
				info.Corpse = nil
			end
			task.delay(1.5, function()
				if model.Parent then
					model:Destroy()
				end
			end)
		end,
	})
end

local function remove(model)
	local info = zombies[model]
	if info then
		zombies[model] = nil
		if not info.Dungeon then
			count -= 1
		end
		if info.Path then
			info.Path:Destroy()
			info.Path = nil
		end
	end
end

-- Stimme eines Zombies (SoundLibrary): wie in Unturned hat jeder Zombie seine eigene Stimmlage (VoicePitch, beim
-- Spawnen gewürfelt), Brocken brüllen beim Bemerken und Zuschlagen, Läufer klingen etwas höher, Bosse tiefer.
-- Höchstens alle VOICE_GAP Sekunden je Zombie (force = trotzdem, z.B. Tod).
local VOICE_GAP = 1.2
local AGGRO_COOLDOWN = 8 -- Sekunden, bis derselbe Zombie wieder beim Entdecken schreit
local function voice(info, name, force)
	local now = os.clock()
	if not force and now < (info.QuietUntil or 0) then
		return
	end
	info.QuietUntil = now + VOICE_GAP
	local pitch = info.VoicePitch or 1
	if info.Stats and info.Stats.Boss then
		pitch *= 0.7
	elseif info.Kind == "Brute" then
		pitch *= 0.85
		if name == "ZombieAggro" or name == "ZombieAttack" then
			name = "BruteRoar"
		end
	elseif info.Kind == "Runner" then
		pitch *= 1.08
	end
	Sfx.At(name, info.Root, { Pitch = pitch })
end
ZombieService.Voice = voice

local function onDeath(model, info)
	local root = info.Root
	remove(model)
	if root and root.Parent then
		voice(info, "ZombieDeath", true)
	end
	-- in der roten Zone gestorben: mehr Münzen, bessere Beute
	local red = root and options and options.RedzoneAt and options.RedzoneAt(root.Position) ~= nil
	-- Münzen für den, der zuletzt getroffen hat (Spieler)
	local hit = Damage.LastHit(model)
	local killer = hit and ((hit.Player and hit.Player.Parent and hit.Player) or (hit.Model and Players:GetPlayerFromCharacter(hit.Model)))
	if killer then
		local A = ExtinctionConfig.ArmoredZombies
		ProgressService.AddCoins(killer, info.Coins * (red and ExtinctionConfig.Redzone.Loot.CoinFactor or 1)
			* (info.Armored and A.CoinFactor or 1), "Zombie")
		-- XP für den aktiven Agenten (zählt auch fürs Spielerlevel und den Battle Pass); die Münzen sind oben schon gezahlt
		ProgressService.AddXP(killer, ProgressService.ActiveAgent(killer), math.floor(info.Stats.XP * (info.Armored and A.XPFactor or 1)),
			info.Name, false, true)
		ProgressService.AddStat(killer, "Zombies", 1)
		Telemetry.Count(killer, "ZombieKills", 1)
		killer:SetAttribute("ZombieKills", (killer:GetAttribute("ZombieKills") or 0) + 1)
		for _, callback in ZombieService.OnKill do
			local ok, err = pcall(callback, killer, info.Kind, root and root.Position or Vector3.zero, info.Armored == true,
				info.Dungeon == true)
			if not ok then
				warn("ZombieService.OnKill: " .. tostring(err))
			end
		end
	end
	-- Beute steckt in der Leiche (E durchsucht sie), sonst verschwindet sie bald
	-- (feste Bosse wie der Chirurg: die Beute kommt von BossService, nicht noch einmal aus der Leiche)
	local items = root and not info.Boss and rollCorpseLoot(info.Stats, info.Blood, red) or {}
	-- Dungeon-Schlüssel: selten bei normalen Zombies, öfter bei Bossen – nie bei Zombies im Dungeon selbst
	if root and not info.Dungeon and not info.Boss then
		ExtinctionConfig.AddDungeonKey(items, info.Stats.Boss and "Boss" or "Zombie", random)
	end
	if #items > 0 and root then
		attachCorpseLoot(model, root, info, items)
	end
	task.delay(#items > 0 and Z.CorpseLootTime or Z.CorpseTime, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- Wie viele Zombies der Server gerade haben darf (mit Bonus, solange jemand in der roten Zone ist)
local function maxTotal()
	local bonus = 0
	if options and options.RedzoneAt then
		for _, player in options.Players() do
			local root = livingRoot(player)
			if root and options.RedzoneAt(root.Position) then
				bonus = ExtinctionConfig.Redzone.MaxTotalBonus
				break
			end
		end
	end
	local now = workspace:GetServerTimeNow()
	local night = DayCycle.IsNight(DayCycle.Clock(now))
	local blood = DayCycle.IsBloodMoon(now) and ExtinctionConfig.Day.BloodMoonZombies or 1
	local storm = DayCycle.IsStorm(now) and ExtinctionConfig.Storm.Zombies or 1
	return math.floor(Z.MaxTotal * (night and ExtinctionConfig.Day.NightZombies or 1) * blood * storm + 0.5) + bonus
end

-- Andere Dienste (Aufträge): callback(killer, kind, position, armored), wenn ein Spieler einen Zombie erledigt
ZombieService.OnKill = {} -- callback(killer, kind, position, armored, dungeon)

-- Wirkt bei diesem Spieler gerade die Anti-Zombie-Spritze?
local function shielded(player)
	local character = player.Character
	return character ~= nil and (character:GetAttribute("ZombieShieldUntil") or 0) > workspace:GetServerTimeNow()
end
ZombieService.Shielded = shielded

-- Liegt position zu nah an einem Spieler mit Anti-Zombie-Spritze? (dort spawnt nichts)
local function nearShield(position)
	for _, player in Players:GetPlayers() do
		local root = shielded(player) and livingRoot(player)
		if root and Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z).Magnitude < Z.ShieldRadius then
			return true
		end
	end
	return false
end

-- ---------- Aussehen: fünf Zombie-Typen, zufällig ----------
-- Je Typ: Haut, Oberteil und Hose (je eine Farbe aus der Liste), Sleeves = Ärmel lang (Arme in Oberteilfarbe), und
-- Outfit-Teile (Mütze, Haare, Weste …), angeschweißt, ohne Kollision und ohne Treffer (CanQuery aus: Kopf und Körper
-- bleiben die Trefferzonen). Gepanzerte tragen statt Kopfbedeckung und Oberteil-Extras Helm und Weste.
-- Der sichtbare Kopf (Head-Mesh) ist etwa 1,25 groß: Oberkante bei +0,62, Gesicht bei z = -0,6.
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local SKINS = { rgb(122, 146, 104), rgb(140, 150, 112), rgb(112, 132, 100), rgb(150, 156, 120), rgb(128, 138, 118) }

local function outfit(model, attachTo, size, offset, color, material, shape)
	local p = Instance.new("Part")
	p.Name = "Outfit"
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = attachTo.CFrame * offset
	if shape == "Sphere" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachTo
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- Zylinder stehend (Achse nach oben)

local VARIANTS = {
	-- Zivilist: verblichenes Hemd, Jeans, wirre Haare
	{ Id = "Civilian", Shirts = { rgb(96, 78, 64), rgb(70, 82, 96), rgb(110, 56, 50), rgb(84, 96, 70) },
		Pants = { rgb(56, 60, 74), rgb(48, 50, 54), rgb(70, 62, 52) },
		Head = function(model, head, torso, look)
			local hair = ({ rgb(40, 30, 24), rgb(70, 50, 30), rgb(30, 30, 30) })[random:NextInteger(1, 3)]
			outfit(model, head, Vector3.new(1.3, 0.45, 1.32), CFrame.new(0, 0.42, 0.06), hair, Enum.Material.Fabric, "Sphere")
		end,
		Body = function(model, head, torso, look)
			-- zerrissener Saum: dunkler Streifen unten am Hemd
			outfit(model, torso, Vector3.new(2.02, 0.25, 1.02), CFrame.new(0, -0.85, 0), look.Shirt:Lerp(rgb(0, 0, 0), 0.35))
		end },
	-- Bauarbeiter: Warnweste mit Reflexstreifen, Schutzhelm
	{ Id = "Worker", Shirts = { rgb(90, 90, 96), rgb(70, 80, 100) }, Pants = { rgb(60, 54, 46), rgb(54, 58, 66) },
		Head = function(model, head, torso, look)
			local hat = ({ rgb(230, 190, 40), rgb(230, 120, 40), rgb(225, 225, 220) })[random:NextInteger(1, 3)]
			outfit(model, head, Vector3.new(1.38, 0.7, 1.42), CFrame.new(0, 0.42, 0.02), hat, Enum.Material.SmoothPlastic, "Sphere")
			outfit(model, head, Vector3.new(0.07, 1.5, 1.62), CFrame.new(0, 0.25, -0.06) * UPRIGHT, hat, Enum.Material.SmoothPlastic,
				"Cylinder")
		end,
		Body = function(model, head, torso, look)
			local vest = ({ rgb(226, 150, 40), rgb(200, 220, 50) })[random:NextInteger(1, 2)]
			outfit(model, torso, Vector3.new(2.06, 1.7, 1.06), CFrame.new(0, 0.1, 0), vest)
			for _, y in { -0.15, -0.55 } do
				outfit(model, torso, Vector3.new(2.08, 0.14, 1.08), CFrame.new(0, y, 0), rgb(205, 210, 215), Enum.Material.SmoothPlastic)
			end
		end },
	-- Patient aus dem Krankenhaus: langes Krankenhaushemd, nackte Beine, Kopfverband
	{ Id = "Patient", Shirts = { rgb(150, 190, 200), rgb(176, 196, 186), rgb(196, 206, 214) }, Pants = { "Skin" },
		Head = function(model, head, torso, look)
			outfit(model, head, Vector3.new(0.26, 1.32, 1.32), CFrame.new(0, 0.4, 0) * UPRIGHT, rgb(224, 222, 210), Enum.Material.Fabric,
				"Cylinder")
		end,
		Body = function(model, head, torso, look)
			outfit(model, torso, Vector3.new(2.06, 2.7, 1.06), CFrame.new(0, -0.32, 0), look.Shirt) -- reicht bis über die Knie
		end },
	-- Häftling aus dem Gefängnis: orangefarbener Overall mit Nummer, Glatze
	{ Id = "Prisoner", Shirts = { rgb(214, 110, 40), rgb(200, 96, 36) }, Pants = { "Shirt" }, Sleeves = true,
		Body = function(model, head, torso, look)
			outfit(model, torso, Vector3.new(0.7, 0.4, 0.05), CFrame.new(-0.45, 0.45, -0.52), rgb(230, 228, 220), Enum.Material.SmoothPlastic)
			outfit(model, torso, Vector3.new(0.5, 0.08, 0.06), CFrame.new(-0.45, 0.45, -0.55), rgb(40, 40, 40), Enum.Material.SmoothPlastic)
		end },
	-- Polizist: dunkelblaue Uniform, Mütze mit Schirm, Abzeichen, Gürtel
	{ Id = "Police", Shirts = { rgb(40, 52, 82), rgb(48, 58, 74) }, Pants = { rgb(30, 34, 46) }, Sleeves = true,
		Head = function(model, head, torso, look)
			local cap = rgb(28, 32, 44)
			outfit(model, head, Vector3.new(0.4, 1.4, 1.4), CFrame.new(0, 0.55, 0.04) * UPRIGHT, cap, Enum.Material.Fabric, "Cylinder")
			outfit(model, head, Vector3.new(1.0, 0.08, 0.45), CFrame.new(0, 0.38, -0.72), rgb(20, 20, 22), Enum.Material.SmoothPlastic)
			outfit(model, head, Vector3.new(0.3, 0.2, 0.05), CFrame.new(0, 0.58, -0.71), rgb(210, 176, 70), Enum.Material.Metal)
		end,
		Body = function(model, head, torso, look)
			outfit(model, torso, Vector3.new(0.3, 0.35, 0.05), CFrame.new(-0.5, 0.45, -0.52), rgb(210, 176, 70), Enum.Material.Metal)
			outfit(model, torso, Vector3.new(2.06, 0.22, 1.06), CFrame.new(0, -0.88, 0), rgb(20, 20, 22), Enum.Material.SmoothPlastic)
		end },
}

-- Typ würfeln, einfärben und Outfit anbauen (vor dem Skalieren). armored = keine Kopfbedeckung/Oberteil-Extras.
local function dress(model, armored)
	local variant = VARIANTS[random:NextInteger(1, #VARIANTS)]
	local look = { Skin = SKINS[random:NextInteger(1, #SKINS)] }
	look.Shirt = variant.Shirts[random:NextInteger(1, #variant.Shirts)]
	local pants = variant.Pants[random:NextInteger(1, #variant.Pants)]
	look.Pants = pants == "Skin" and look.Skin or pants == "Shirt" and look.Shirt or pants
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "Eye" and child.Name ~= "HumanoidRootPart" and child.Name ~= "Blood" then
			local name = child.Name
			if name == "Torso" then
				child.Color = look.Shirt
			elseif name == "Left Leg" or name == "Right Leg" then
				child.Color = look.Pants
			elseif (name == "Left Arm" or name == "Right Arm") and variant.Sleeves then
				child.Color = look.Shirt
			else
				child.Color = look.Skin
			end
		end
	end
	model:SetAttribute("ZombieLook", variant.Id)
	local head, torso = model:FindFirstChild("Head"), model:FindFirstChild("Torso")
	if head and torso and not armored then
		if variant.Head then
			variant.Head(model, head, torso, look)
		end
		if variant.Body then
			variant.Body(model, head, torso, look)
		end
	end
end

-- Gepanzert? armored = true/false erzwingt es, nil würfelt: Sturmnacht Storm.ArmoredChance, rote Zone
-- ArmoredZombies.RedzoneChance, sonst ArmoredZombies.Chance. Bosse nie.
local function rollArmored(position, armored, stats)
	if stats.Boss or armored == false then
		return false
	end
	if armored == true then
		return true
	end
	local A = ExtinctionConfig.ArmoredZombies
	local chance = A.Chance
	if DayCycle.IsStorm(workspace:GetServerTimeNow()) then
		chance = ExtinctionConfig.Storm.ArmoredChance
	elseif options and options.RedzoneAt and options.RedzoneAt(position) then
		chance = A.RedzoneChance
	end
	return random:NextNumber() < chance
end

-- Helm und Weste anbauen (vor dem Skalieren, damit sie mitwachsen). Treffer gehen durch sie hindurch (CanQuery aus):
-- Kopf und Körper bleiben die Trefferzonen, Damage zieht den Schutz von den Attributen ZHelmet / ZVest ab.
local ARMOR_COLOR = Color3.fromRGB(58, 64, 52)
local function armorPart(model, name, size, attachTo, offset, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = ARMOR_COLOR
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = attachTo.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachTo
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function addArmor(model)
	local A = ExtinctionConfig.ArmoredZombies
	local head, torso = model:FindFirstChild("Head"), model:FindFirstChild("Torso")
	if head then
		-- runde Kuppel in Kopfgröße (der sichtbare Kopf ist ~1,25 breit), Rand knapp über den Augen
		local dome = armorPart(model, "ZHelmetPart", Vector3.new(1.42, 0.7, 1.45), head, CFrame.new(0, 0.42, 0.02), Enum.Material.Metal)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = dome
		local rim = armorPart(model, "ZHelmetPart", Vector3.new(0.08, 1.52, 1.55), head,
			CFrame.new(0, 0.24, 0.0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Metal)
		rim.Shape = Enum.PartType.Cylinder
	end
	if torso then
		armorPart(model, "ZVestPart", Vector3.new(2.15, 1.7, 1.25), torso, CFrame.new(0, 0.1, 0), Enum.Material.Fabric)
		for _, x in { -0.55, 0.55 } do
			armorPart(model, "ZVestPart", Vector3.new(0.7, 0.5, 0.2), torso, CFrame.new(x, -0.35, -0.68), Enum.Material.Fabric)
		end
	end
	model:SetAttribute("ZHelmet", A.Helmet)
	model:SetAttribute("ZVest", A.Vest)
	-- aufgebraucht: Teile fallen ab
	local function knockOff(name, attribute)
		model:GetAttributeChangedSignal(attribute):Connect(function()
			if (model:GetAttribute(attribute) or 0) > 0 then
				return
			end
			for _, child in model:GetChildren() do
				if child.Name == name and child:IsA("BasePart") then
					local weld = child:FindFirstChildOfClass("WeldConstraint")
					if weld then
						weld:Destroy()
					end
					child.Massless = false
					child.CanCollide = true
					child:ApplyImpulse(Vector3.new(random:NextNumber(-1, 1), 1.5, random:NextNumber(-1, 1)) * child:GetMass() * 25)
					task.delay(6, function()
						if child.Parent then
							child:Destroy()
						end
					end)
				end
			end
		end)
	end
	knockOff("ZHelmetPart", "ZHelmet")
	knockOff("ZVestPart", "ZVest")
end

-- kindName: "Walker" (Standard), "Runner" oder "Brute". force = true: auch über der Obergrenze (Nester, Lager-Alarm), aber
-- höchstens ForceExtra darüber. Nie nah an einem Spieler mit Anti-Zombie-Spritze (dann nil). armored: siehe rollArmored.
-- force = true: etwas über die Obergrenze hinaus (Events); force = "Dungeon": ohne Obergrenze und Spritze (die Halle
-- hat ihre eigene Grenze, sonst friert eine Welle ein, wenn draußen viel los ist)
function ZombieService.Spawn(position, kindName, force, armored)
	if force ~= "Dungeon" and (count >= maxTotal() + (force and Z.ForceExtra or 0) or nearShield(position)) then
		return nil
	end
	local stats = ZombieService.Kind(kindName)
	template = template or buildTemplate()
	local model = template:Clone()
	armored = rollArmored(position, armored, stats)
	dress(model, armored)
	for _, child in model:GetChildren() do
		if child.Name == "Eye" then
			child.Color = stats.Eyes
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	-- Blutmond: zäher, härter, schneller (Bosse haben ihre eigenen Werte)
	local B = ExtinctionConfig.BloodMoon
	local blood = DayCycle.IsBloodMoon(workspace:GetServerTimeNow()) and not stats.Boss
	local health = math.floor(stats.Health * random:NextNumber(0.8, 1.2) * (blood and B.Health or 1))
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.WalkSpeed = stats.Walk
	local speed = stats.Run * random:NextNumber(0.88, 1.12) * (blood and B.Speed or 1)
	if armored then
		addArmor(model)
	end
	if stats.Scale ~= 1 then
		model:ScaleTo(stats.Scale)
	end
	model:SetAttribute("ZombieKind", stats.Id)
	if stats.Boss then
		-- Boss: Name und Lebensbalken über dem Kopf, roter Umriss (durch Wände sichtbar)
		model:SetAttribute("Boss", true)
		local head = model:FindFirstChild("Head")
		local board = Instance.new("BillboardGui")
		board.Name = "BossTag"
		board.Size = UDim2.fromOffset(220, 46)
		board.StudsOffset = Vector3.new(0, 3, 0)
		board.AlwaysOnTop = true
		board.MaxDistance = 260
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0, 24)
		title.Text = string.upper(stats.Name)
		title.TextColor3 = Color3.fromRGB(255, 70, 60)
		title.TextStrokeTransparency = 0.3
		title.Font = Enum.Font.BuilderSansExtraBold
		title.TextScaled = true
		title.Parent = board
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.Position = UDim2.new(0.1, 0, 0, 30)
		bar.Size = UDim2.new(0.8, 0, 0, 8)
		bar.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
		bar.BorderSizePixel = 0
		bar.Parent = board
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Color3.fromRGB(220, 40, 30)
		fill.BorderSizePixel = 0
		fill.Parent = bar
		board.Parent = head or model
		humanoid.HealthChanged:Connect(function(value)
			fill.Size = UDim2.fromScale(math.clamp(value / math.max(1, humanoid.MaxHealth), 0, 1), 1)
		end)
		local glow = Instance.new("Highlight")
		glow.Name = "BossGlow"
		glow.FillColor = Color3.fromRGB(160, 20, 20)
		glow.FillTransparency = 0.75
		glow.OutlineColor = Color3.fromRGB(255, 60, 50)
		glow.Parent = model
	end
	model:PivotTo(CFrame.new(position + Vector3.new(0, 3 * stats.Scale, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- Streaming: beim Client ganz oder gar nicht
	model.Parent = folder
	local root = model:FindFirstChild("HumanoidRootPart")
	pcall(function()
		root:SetNetworkOwner(nil) -- der Server steuert die Zombies
	end)
	local info = { Humanoid = humanoid, Root = root, Target = nil, NextAttack = 0, NextWander = 0, LastPos = root.Position,
		StuckTime = 0, Speed = speed, Walk = stats.Walk, Damage = stats.Damage * (blood and B.Damage or 1), Coins = stats.Coins,
		Kind = stats.Id, Name = (armored and "Armored " or "") .. stats.Name, Stats = stats, Blood = blood, Armored = armored,
		VoicePitch = random:NextNumber(0.88, 1.1), Dungeon = force == "Dungeon" }
	zombies[model] = info
	if not info.Dungeon then
		count += 1 -- Dungeon-Zombies zählen nicht gegen die Obergrenze der offenen Welt
	end
	playAnimations(humanoid, speed)
	humanoid.Died:Once(function()
		onDeath(model, info)
	end)
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(value)
		if value < lastHealth - 0.5 and value > 0 then
			voice(info, "ZombieHurt")
		end
		lastHealth = value
	end)
	return model
end

-- ---------- KI ----------

-- Raycast-Filter für die Sichtlinie beim Jagen: Zombies, Beute, Spieler-Charaktere und Bots zählen nicht als Hindernis
local function buildCastParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder }
	local loot = workspace:FindFirstChild("ExtinctionLoot")
	if loot then
		table.insert(ignore, loot)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, bot in options.Bots and options.Bots() or {} do
		table.insert(ignore, bot)
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- Ist die gerade Linie vom Zombie zum Ziel (Brusthöhe) verbaut?
local function lineBlocked(root, targetRoot)
	local origin = root.Position
	local direction = targetRoot.Position - origin
	if direction.Magnitude < 0.5 then
		return false
	end
	castParams = castParams or buildCastParams()
	return workspace:Raycast(origin, direction, castParams) ~= nil
end

-- Neuen Pfad anfordern (im eigenen Thread, ComputeAsync wartet). Höchstens PerFrame je Heartbeat: ist das Budget
-- aufgebraucht, passiert nichts und der nächste KI-Schritt versucht es wieder.
local function requestPath(info, root, goal, now)
	if info.PathBusy or pathBudget <= 0 then
		return
	end
	pathBudget -= 1
	local path = info.Path
	if not path then
		path = PathfindingService:CreatePath({ AgentRadius = P.AgentRadius, AgentHeight = P.AgentHeight, AgentCanJump = true,
			WaypointSpacing = P.WaypointSpacing })
		info.Path = path
		path.Blocked:Connect(function(index)
			if info.Waypoints and index >= (info.WaypointIndex or 1) then
				info.PathBlocked = true -- vor dem Zombie verbaut: beim nächsten Schritt neu berechnen
			end
		end)
	end
	info.PathBusy, info.PathAt, info.PathGoal, info.PathBlocked = true, now, goal, false
	task.spawn(function()
		local ok = pcall(path.ComputeAsync, path, root.Position, goal)
		info.PathBusy = false
		if ok and path.Status == Enum.PathStatus.Success and info.Path == path then
			info.Waypoints = path:GetWaypoints()
			info.WaypointIndex = 2 -- der erste Wegpunkt ist die eigene Position
		else
			info.Waypoints = nil -- kein Weg: gerade hin, später noch einmal versuchen
		end
	end)
end

-- Jagen mit verbauter Sichtlinie: dem Pfad folgen, solange keiner da ist (noch nicht berechnet, fehlgeschlagen,
-- abgelaufen) gerade auf das Ziel zu
local function followPath(info, humanoid, root, goal, now)
	local waypoints = info.Waypoints
	local stale = waypoints == nil or info.PathBlocked or info.PathGoal == nil
		or (goal - info.PathGoal).Magnitude > P.MoveTolerance
	if stale and now - (info.PathAt or -math.huge) >= P.Recompute then
		requestPath(info, root, goal, now)
		waypoints = info.Waypoints
	end
	local waypoint = waypoints and waypoints[info.WaypointIndex]
	if waypoint then
		local offset = waypoint.Position - root.Position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude < P.WaypointReach then
			info.WaypointIndex += 1
			waypoint = waypoints[info.WaypointIndex]
		end
	end
	if not waypoint then
		if waypoints and not info.PathBusy then
			info.Waypoints = nil -- Pfad abgelaufen, Ziel aber noch verbaut: beim nächsten Schritt neu berechnen
		end
		humanoid:MoveTo(goal)
		return
	end
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		humanoid.Jump = true
	end
	humanoid:MoveTo(clampOutside(waypoint.Position))
end

local function step(model, info, now)
	local humanoid, root = info.Humanoid, info.Root
	if not model.Parent or humanoid.Health <= 0 or not root.Parent then
		return
	end
	-- Ziel behalten, solange es draußen und nah genug ist, sonst das nächste suchen
	local target = info.Target
	if target then
		local ok, targetRoot = huntable(target)
		if not ok or not targetRoot or (targetRoot.Position - root.Position).Magnitude > Z.LoseRange then
			target = nil
		end
	end
	if not target then
		local night = DayCycle.IsNight(DayCycle.Clock(workspace:GetServerTimeNow()))
		target = nearestTarget(root.Position, Z.SightRange * (night and ExtinctionConfig.Day.NightSight or 1))
		if target and info.Stats and info.Stats.Scream and now >= (info.NextScream or 0) then
			info.NextScream = now + Z.ScreamCooldown
			ZombieService.Scream(model, target)
		end
	end
	-- hat jemanden bemerkt: Schrei, aber nicht jedes Mal, wenn er das Ziel kurz verliert und wiederfindet
	if target and not info.Target and now >= (info.NextAggro or 0) then
		info.NextAggro = now + AGGRO_COOLDOWN
		voice(info, "ZombieAggro", true)
		info.NextGroan = now + random:NextNumber(1.5, 3)
	end
	info.Target = target
	-- Leerlauf: hin und wieder leise stöhnen; beim Jagen kurz und oft knurren; nicht gleich beim Spawnen
	if not info.NextGroan then
		info.NextGroan = now + random:NextNumber(2, 10)
	elseif now >= info.NextGroan then
		info.NextGroan = now + (target and random:NextNumber(2.5, 5) or random:NextNumber(8, 18))
		voice(info, target and "ZombieChase" or "ZombieIdle")
	end
	if target then
		local targetRoot, targetHumanoid, character = livingRoot(target)
		if not targetRoot or not targetHumanoid or not character then
			return
		end
		local distance = (targetRoot.Position - root.Position).Magnitude
		humanoid.WalkSpeed = info.Speed
		-- große Zombies reichen weiter; nicht durch Wände (sonst trifft er, an die Wand gedrückt, wer dahinter steht)
		if distance <= Z.AttackRange * math.max(1, info.Stats and info.Stats.Scale or 1) and not lineBlocked(root, targetRoot) then
			humanoid:MoveTo(root.Position) -- stehen bleiben und zuschlagen
			if now >= info.NextAttack then
				info.NextAttack = now + Z.AttackDelay
				voice(info, "ZombieAttack")
				Damage.Apply(character, targetHumanoid, info.Damage, { Model = model, BotName = info.Name, Weapon = "Zombie" })
			end
		else
			local goal = clampOutside(targetRoot.Position)
			if P.Enabled and lineBlocked(root, targetRoot) then
				followPath(info, humanoid, root, goal, now)
			else
				info.Waypoints = nil -- freie Sicht: direkt hin
				humanoid:MoveTo(goal)
			end
		end
	elseif now >= info.NextWander then
		-- herumschlurfen
		info.NextWander = now + random:NextNumber(4, 9)
		humanoid.WalkSpeed = info.Walk
		local angle = random:NextNumber(0, math.pi * 2)
		local goal = root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(8, WANDER_RADIUS)
		humanoid:MoveTo(clampOutside(goal))
	end
	-- hängt fest: springen
	if humanoid.MoveDirection.Magnitude > 0.1 and (root.Position - info.LastPos).Magnitude < 0.4 then
		info.StuckTime += AI_STEP
		if info.StuckTime > 0.75 then
			humanoid.Jump = true
			info.StuckTime = 0
		end
	else
		info.StuckTime = 0
	end
	info.LastPos = root.Position
end

-- Zombies entfernen, wenn eine Weile kein Spieler draußen in ihrer Nähe ist (in der Safe Zone zählt nicht)
local function despawnFar(now)
	for model, info in zombies do
		local near = false
		for _, player in options.Players() do
			local ok, root = huntable(player)
			if ok and root and (root.Position - info.Root.Position).Magnitude <= Z.DespawnDistance then
				near = true
				break
			end
		end
		if near then
			info.LonelySince = nil
		else
			info.LonelySince = info.LonelySince or now
		end
		if not model.Parent or (info.LonelySince and now - info.LonelySince >= LONELY_TIME) then
			remove(model)
			model:Destroy()
		end
	end
end

-- Pro Spieler draußen nachspawnen, bis PerPlayer Zombies in seiner Nähe sind (in der roten Zone mehr, mit Läufern und
-- Brocken, und innerhalb der Zone)
local function spawnRound()
	for _, player in options.Players() do
		local ok, root = huntable(player)
		if ok and root and count < maxTotal() and not shielded(player) then
			local zone = options.RedzoneAt and options.RedzoneAt(root.Position)
			local wanted = zone and math.floor(Z.PerPlayer * ExtinctionConfig.Redzone.PerPlayerFactor + 0.5) or Z.PerPlayer
			if DayCycle.IsNight(DayCycle.Clock(workspace:GetServerTimeNow())) then
				wanted = math.floor(wanted * ExtinctionConfig.Day.NightZombies + 0.5) -- nachts mehr
				if DayCycle.IsBloodMoon(workspace:GetServerTimeNow()) then
					wanted = math.floor(wanted * ExtinctionConfig.Day.BloodMoonZombies + 0.5) -- Blutmond: noch mehr
				end
			end
			if DayCycle.IsStorm(workspace:GetServerTimeNow()) then
				wanted = math.floor(wanted * ExtinctionConfig.Storm.Zombies + 0.5) -- Sturmnacht: mehr
			end
			local around = 0
			for _, info in zombies do
				if (info.Root.Position - root.Position).Magnitude <= Z.SpawnMax + 20 then
					around += 1
				end
			end
			if around < wanted then
				local point = zone and redzoneSpawnPoint(zone) or spawnPoint(root.Position)
				if point then
					ZombieService.Spawn(point, rollKind(zone ~= nil))
				end
			end
		end
	end
end

-- opts = { Map, Center (Vector3), InSafeZone(position) -> bool, SafeCenter() -> (Vector3, Radius), Players() -> { Player },
--          RedzoneAt(position) -> Zone | nil (optional), IsWater(x, z) -> bool (optional),
--          Bots() -> { Model } (optional: Bots der offenen Welt, Zombies jagen sie wie Spieler) }
function ZombieService.Init(opts)
	options = opts
	local aiElapsed, spawnElapsed, despawnElapsed = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		aiElapsed += dt
		spawnElapsed += dt
		despawnElapsed += dt
		if aiElapsed >= AI_STEP then
			aiElapsed = 0
			castParams = nil -- Filter je Runde neu (Charaktere und Bots ändern sich)
			pathBudget = P.PerFrame -- Pfad-Budget je KI-Runde (die Schritte verteilen sich über die Frames der Runde)
		end
		-- jeder Zombie alle AI_STEP Sekunden, aber über die Frames verteilt (nicht alle im selben Frame: sonst ein Ruckler
		-- alle 0,25 s, und das Pfad-Budget pro Frame reicht nur für einen Frame)
		local now = os.clock()
		for model, info in zombies do
			local due = info.NextAI
			if not due then
				info.NextAI = now + math.random() * AI_STEP
			elseif now >= due then
				info.NextAI = math.max(due + AI_STEP, now)
				local ok, err = pcall(step, model, info, now)
				if not ok then
					warn("Zombie-KI: " .. tostring(err))
				end
			end
		end
		if spawnElapsed >= Z.SpawnInterval then
			spawnElapsed = 0
			spawnRound()
		end
		if despawnElapsed >= 2 then
			despawnElapsed = 0
			despawnFar(os.clock())
		end
	end)
end

-- Zombie gehört zu einem Dungeon (DungeonService): kein Dungeon-Schlüssel in der Beute
function ZombieService.MarkDungeon(model)
	local info = zombies[model]
	if info and not info.Dungeon then
		info.Dungeon = true
		count -= 1
	end
end

-- Bodenpunkt bei (x, z) für Spawns und Abwürfe: nur Gelände/Straße, nicht im Wasser, nicht zu steil (nil = ungeeignet)
function ZombieService.GroundAt(x, z)
	return groundAt(x, z)
end

-- amount Zombies der Art kindName in einem Ring (minRadius bis maxRadius) um center spawnen (z.B. Begleiter eines Lootdrops).
-- Gibt die gespawnten Modelle zurück (weniger, wenn kein Platz oder die Obergrenze erreicht ist). kindName = "Random":
-- Art wie beim normalen Spawnen würfeln. armored: siehe ZombieService.Spawn.
function ZombieService.SpawnAround(center, amount, minRadius, maxRadius, kindName, force, armored)
	local spawned = {}
	for _ = 1, amount do
		for _ = 1, 6 do
			local angle = random:NextNumber(0, math.pi * 2)
			local distance = random:NextNumber(minRadius, maxRadius)
			local x, z = center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance
			-- nicht in einer Safe Zone und nicht direkt neben einem Spieler (Sturm, Schreier, Alarm spawnen um Spieler)
			local point = farFromSafe(x, z, 6) and not nearPlayer(x, z, 12) and groundAt(x, z)
			if point then
				local model = ZombieService.Spawn(point, kindName == "Random" and rollKind(false) or kindName, force, armored)
				if model then
					table.insert(spawned, model)
				end
				break
			end
		end
	end
	return spawned
end

-- Schreier hat einen Spieler gesehen: alle Zombies im Umkreis jagen ihn, ein paar kommen dazu, roter Schrei-Ring
function ZombieService.Scream(model, target)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	Sfx.At("ZombieScream", root)
	for other, info in zombies do
		if other ~= model and (info.Root.Position - root.Position).Magnitude <= Z.ScreamRange then
			info.Target = target
		end
	end
	ZombieService.SpawnAround(root.Position, Z.ScreamCalls, 25, 60, nil, true)
	local ring = Instance.new("Part")
	ring.Name = "ScreamRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 8, 8)
	ring.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = Color3.fromRGB(255, 60, 50)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.4
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Parent = folder
	pcall(function()
		game:GetService("TweenService"):Create(ring, TweenInfo.new(1.2), { Size = Vector3.new(0.3, 80, 80), Transparency = 1 }):Play()
	end)
	task.delay(1.3, function()
		ring:Destroy()
	end)
	local ok, InventoryService = pcall(require, script.Parent.InventoryService)
	if ok and InventoryService and InventoryService.Status and target:IsA("Player") then
		InventoryService.Status(target, "Ein Schreier ruft die Zombies!")
	end
end

-- Zustand eines Zombies (Damage, Coins, Speed, Kind …) zum Anpassen, z.B. für Bosse (BossService); nil = kein Zombie
function ZombieService.Info(model)
	return zombies[model]
end

-- Admin: alle Zombies entfernen (auch Blutbestien; Bosse an festen Orten bleiben, die regelt BossService). Gibt die Anzahl zurück.
function ZombieService.ClearAll()
	local removed = 0
	for model, info in zombies do
		if not model:GetAttribute("IsBoss") then
			remove(model)
			model:Destroy()
			removed += 1
		end
	end
	return removed
end

-- Anzahl lebender Zombies (für Tests und das Admin-Panel)
function ZombieService.Count()
	return count
end

function ZombieService.All()
	local list = {}
	for model in zombies do
		table.insert(list, model)
	end
	return list
end

return ZombieService

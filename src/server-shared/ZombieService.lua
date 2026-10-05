-- ZombieService (ModuleScript, nur Server)
-- Zombies der offenen Welt (EXTINCTION): Sobald Spieler außerhalb der Safe Zone sind, spawnen um jeden herum
-- Zombies im weiteren Umkreis (ExtinctionConfig.Zombies: SpawnMin bis SpawnMax Studs, höchstens PerPlayer pro
-- Spieler und MaxTotal auf dem Server) – nur auf dem Boden (nicht auf Dächern), nicht im Wasser und nicht nah an der
-- Safe Zone. Sie schlurfen herum, bemerken Spieler in SightRange, rennen hin und schlagen zu (AttackDamage alle
-- AttackDelay Sekunden). In die Safe Zone gehen sie nicht (sie bleiben am Rand stehen), dort gibt es auch keinen
-- Schaden. Wer eine Weile keinen Spieler draußen in der Nähe hat, verschwindet.
-- Arten (ExtinctionConfig.ZombieKinds): Walker (normal, langsam), in roten Zonen auch Läufer (schneller) und Brocken
-- (groß, zäh, schlägt hart). In einer roten Zone (RedzoneService) spawnen mehr Zombies, innerhalb der Zone.
-- Tod: der Schütze bekommt Münzen (je Art, wenig). Beute steckt in der Leiche: E durchsucht sie, alles geht direkt ins
-- Inventar (LootService.Grab); was nicht passt, bleibt in der Leiche (ExtinctionConfig.Zombies.CorpseLootTime Sekunden).
-- Körper: einfacher R6-Körper (6 Teile, schnell), Arme nach vorn, rote Augen; Animation: Roblox-Standard (R6).
-- Modelle in Workspace.Zombies, Attribut IsZombie (Messer und Schüsse treffen sie, der Ping-Ausgleich kennt sie).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local DayCycle = require(Shared.DayCycle)
local Damage = require(script.Parent.Damage)
local Modes = require(Shared.Modes)
local ProgressService = require(script.Parent.ProgressService)
local LootService = require(script.Parent.LootService)

local ZombieService = {}

local Z = ExtinctionConfig.Zombies
local AI_STEP = 0.25        -- Sekunden zwischen zwei KI-Schritten (alle Zombies, verteilt)
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
                     --   RedzoneAt(position) -> Zone | nil, IsWater(x, z) -> bool }
local zombies = {}   -- [Model] = { Humanoid, Root, Target, NextAttack, NextWander, LastPos, StuckTime, Speed, Walk, Damage, Coins, Kind }
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
		Scale = kind.Scale or 1,
		Drop = kind.Drop or ExtinctionConfig.ZombieDropChance,
		Items = kind.Items or { 1, 1 },
		Table = kind.Table or "Zombie",
		Eyes = kind.Eyes or Color3.fromRGB(255, 40, 30),
	}
end

-- Art würfeln (in roten Zonen mit KindWeights, sonst immer Walker)
local function rollKind(inRedzone)
	if not inRedzone then
		return "Walker"
	end
	local weights = ExtinctionConfig.Redzone.KindWeights
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

-- Farben: Haut, Oberteil, Hose (zerrissen, verblichen)
local LOOKS = {
	{ Color3.fromRGB(122, 146, 104), Color3.fromRGB(96, 78, 64), Color3.fromRGB(56, 60, 74) },
	{ Color3.fromRGB(140, 150, 112), Color3.fromRGB(70, 82, 96), Color3.fromRGB(70, 62, 52) },
	{ Color3.fromRGB(112, 132, 100), Color3.fromRGB(128, 112, 86), Color3.fromRGB(48, 50, 54) },
	{ Color3.fromRGB(150, 156, 120), Color3.fromRGB(110, 56, 50), Color3.fromRGB(60, 66, 58) },
}

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
	local skin, shirt, pants = LOOKS[1][1], LOOKS[1][2], LOOKS[1][3]
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

-- ---------- Ziele ----------

local function livingRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return root, humanoid, character
	end
	return nil, nil, nil
end

-- Spieler, die draußen sind (Zombies jagen nur sie)
local function huntable(player)
	local root = livingRoot(player)
	return root ~= nil and not player:GetAttribute("InSafeZone") and not options.InSafeZone(root.Position), root
end

local function nearestTarget(position, range)
	local best, bestDistance = nil, range
	for _, player in options.Players() do
		local ok, root = huntable(player)
		if ok and root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best, bestDistance
end

-- Punkt am Rand der Safe Zone (Zombies bleiben draußen stehen)
local function clampOutside(position)
	local center, radius = options.SafeCenter()
	local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	local limit = radius + 6
	if flat.Magnitude >= limit or flat.Magnitude < 0.01 then
		return position
	end
	local edge = center + flat.Unit * limit
	return Vector3.new(edge.X, position.Y, edge.Z)
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
	local center, radius = options.SafeCenter()
	local half = ExtinctionConfig.WorldSize / 2 - 70
	for _ = 1, 8 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(Z.SpawnMin, Z.SpawnMax)
		local x, z = position.X + math.cos(angle) * distance, position.Z + math.sin(angle) * distance
		local fromCenter = Vector3.new(x - options.Center.X, 0, z - options.Center.Z)
		local fromSafe = Vector3.new(x - center.X, 0, z - center.Z)
		if math.abs(fromCenter.X) < half and math.abs(fromCenter.Z) < half and fromSafe.Magnitude > radius + Z.SafeMargin then
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

-- Freie Stelle innerhalb einer roten Zone (nicht direkt vor einem Spieler), nil wenn keine passt
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
local function rollCorpseLoot(stats)
	if random:NextNumber() > stats.Drop then
		return {}
	end
	return ExtinctionConfig.RollLoot(stats.Table, random:NextInteger(stats.Items[1], stats.Items[2]), random)
end

-- E an der Leiche: Beute direkt ins Inventar. Was nicht passt, bleibt liegen.
local function attachCorpsePrompt(model, root, info, items)
	local corpse = { Items = items }
	info.Corpse = corpse
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CorpsePrompt"
	prompt.ActionText = "Aufheben"
	prompt.ObjectText = info.Name .. " · " .. LootService.Summary(items)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0 -- einmal E, kein Halten
	prompt.MaxActivationDistance = CORPSE_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	local highlight = Instance.new("Highlight")
	highlight.Name = "LootHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 214, 110)
	highlight.OutlineTransparency = 0.35
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	prompt.Triggered:Connect(function(player)
		local playerRoot = livingRoot(player)
		if not playerRoot or not Modes.IsSurvival(player:GetAttribute("Mode"))
			or (playerRoot.Position - root.Position).Magnitude > CORPSE_RANGE + 3 or #corpse.Items == 0 then
			return
		end
		local rest = LootService.Grab(player, corpse.Items)
		corpse.Items = rest
		if #rest == 0 then
			prompt:Destroy()
			highlight:Destroy()
			info.Corpse = nil
			task.delay(1.5, function()
				if model.Parent then
					model:Destroy()
				end
			end)
		else
			prompt.ObjectText = info.Name .. " · " .. LootService.Summary(rest)
		end
	end)
end

local function remove(model)
	if zombies[model] then
		zombies[model] = nil
		count -= 1
	end
end

local function onDeath(model, info)
	local root = info.Root
	remove(model)
	-- Münzen für den, der zuletzt getroffen hat (Spieler)
	local hit = Damage.LastHit(model)
	local killer = hit and hit.Model and Players:GetPlayerFromCharacter(hit.Model)
	if killer then
		ProgressService.AddCoins(killer, info.Coins, "Zombie")
		ProgressService.AddStat(killer, "Zombies", 1)
		killer:SetAttribute("ZombieKills", (killer:GetAttribute("ZombieKills") or 0) + 1)
	end
	-- Beute steckt in der Leiche (E durchsucht sie), sonst verschwindet sie bald
	local items = root and rollCorpseLoot(info.Stats) or {}
	if #items > 0 and root then
		attachCorpsePrompt(model, root, info, items)
	end
	task.delay(#items > 0 and Z.CorpseLootTime or Z.CorpseTime, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- Wie viele Zombies der Server gerade haben darf (mit Bonus, solange jemand in einer roten Zone ist)
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
	local night = DayCycle.IsNight(DayCycle.Clock(workspace:GetServerTimeNow()))
	return math.floor(Z.MaxTotal * (night and ExtinctionConfig.Day.NightZombies or 1) + 0.5) + bonus
end

-- kindName: "Walker" (Standard), "Runner" oder "Brute"
function ZombieService.Spawn(position, kindName)
	if count >= maxTotal() then
		return nil
	end
	local stats = ZombieService.Kind(kindName)
	template = template or buildTemplate()
	local model = template:Clone()
	local look = LOOKS[random:NextInteger(1, #LOOKS)]
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "Eye" and child.Name ~= "HumanoidRootPart" then
			child.Color = (child.Name == "Torso" and look[2]) or ((child.Name == "Left Leg" or child.Name == "Right Leg") and look[3])
				or look[1]
		end
	end
	for _, child in model:GetChildren() do
		if child.Name == "Eye" then
			child.Color = stats.Eyes
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local health = math.floor(stats.Health * random:NextNumber(0.8, 1.2))
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.WalkSpeed = stats.Walk
	local speed = stats.Run * random:NextNumber(0.88, 1.12)
	if stats.Scale ~= 1 then
		model:ScaleTo(stats.Scale)
	end
	model:SetAttribute("ZombieKind", stats.Id)
	model:PivotTo(CFrame.new(position + Vector3.new(0, 3 * stats.Scale, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0))
	model.Parent = folder
	local root = model:FindFirstChild("HumanoidRootPart")
	pcall(function()
		root:SetNetworkOwner(nil) -- der Server steuert die Zombies
	end)
	local info = { Humanoid = humanoid, Root = root, Target = nil, NextAttack = 0, NextWander = 0, LastPos = root.Position,
		StuckTime = 0, Speed = speed, Walk = stats.Walk, Damage = stats.Damage, Coins = stats.Coins, Kind = stats.Id,
		Name = stats.Name, Stats = stats }
	zombies[model] = info
	count += 1
	playAnimations(humanoid, speed)
	humanoid.Died:Once(function()
		onDeath(model, info)
	end)
	return model
end

-- ---------- KI ----------

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
	end
	info.Target = target
	if target then
		local targetRoot, targetHumanoid, character = livingRoot(target)
		if not targetRoot or not targetHumanoid or not character then
			return
		end
		local distance = (targetRoot.Position - root.Position).Magnitude
		humanoid.WalkSpeed = info.Speed
		if distance <= Z.AttackRange then
			humanoid:MoveTo(root.Position) -- stehen bleiben und zuschlagen
			if now >= info.NextAttack then
				info.NextAttack = now + Z.AttackDelay
				Damage.Apply(character, targetHumanoid, info.Damage, { Model = model, BotName = info.Name, Weapon = "Zombie" })
			end
		else
			humanoid:MoveTo(clampOutside(targetRoot.Position))
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

-- Pro Spieler draußen nachspawnen, bis PerPlayer Zombies in seiner Nähe sind (in roten Zonen mehr, mit Läufern und
-- Brocken, und innerhalb der Zone)
local function spawnRound()
	for _, player in options.Players() do
		local ok, root = huntable(player)
		if ok and root and count < maxTotal() then
			local zone = options.RedzoneAt and options.RedzoneAt(root.Position)
			local wanted = zone and math.floor(Z.PerPlayer * ExtinctionConfig.Redzone.PerPlayerFactor + 0.5) or Z.PerPlayer
			if DayCycle.IsNight(DayCycle.Clock(workspace:GetServerTimeNow())) then
				wanted = math.floor(wanted * ExtinctionConfig.Day.NightZombies + 0.5) -- nachts mehr
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
--          RedzoneAt(position) -> Zone | nil (optional), IsWater(x, z) -> bool (optional) }
function ZombieService.Init(opts)
	options = opts
	local aiElapsed, spawnElapsed, despawnElapsed = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		aiElapsed += dt
		spawnElapsed += dt
		despawnElapsed += dt
		if aiElapsed >= AI_STEP then
			aiElapsed = 0
			local now = os.clock()
			for model, info in zombies do
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

-- Bodenpunkt bei (x, z) für Spawns und Abwürfe: nur Gelände/Straße, nicht im Wasser, nicht zu steil (nil = ungeeignet)
function ZombieService.GroundAt(x, z)
	return groundAt(x, z)
end

-- amount Zombies der Art kindName in einem Ring (minRadius bis maxRadius) um center spawnen (z.B. Begleiter eines Lootdrops).
-- Gibt die gespawnten Modelle zurück (weniger, wenn kein Platz oder die Obergrenze erreicht ist).
function ZombieService.SpawnAround(center, amount, minRadius, maxRadius, kindName)
	local spawned = {}
	for _ = 1, amount do
		for _ = 1, 6 do
			local angle = random:NextNumber(0, math.pi * 2)
			local distance = random:NextNumber(minRadius, maxRadius)
			local point = groundAt(center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance)
			if point then
				local model = ZombieService.Spawn(point, kindName)
				if model then
					table.insert(spawned, model)
				end
				break
			end
		end
	end
	return spawned
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

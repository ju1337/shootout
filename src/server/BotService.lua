-- BotService (ModuleScript, nur Server)
-- Computer-Gegner zum Testen und Auffüllen. Ein Bot hat einen zufälligen Agenten,
-- dessen Leben, Tempo und Hauptwaffe. Er sucht den nächsten sichtbaren Gegner im selben
-- Modus, läuft hin, hält Abstand und schießt mit etwas Streuung.
-- Die Modi (FreeForAll, Drop) entscheiden, wann ein Bot spawnt; der BotService baut Modell und KI.
-- Optionale Felder am Bot (setzt der Modus, z.B. Extinction): Weapon (WeaponConfig-Name statt der Agenten-Waffe),
-- Home (Mittelpunkt zum Umherlaufen statt der Mapmitte), HuntRange (nur so nah zum nächsten Gegner laufen),
-- ZombieRange (Zombies so nah sind auch Ziele), AllowPoint(position) (Ziel beim Umherlaufen erlaubt?), NoGadgets (keine Gadgets).
-- Wer in einer Safe Zone steht (Charakter-Attribut "SafeZone"), ist nie ein Ziel.
-- Tote Bots fallen als Ragdoll um und werden nach 2 s ausgeblendet (corpse), damit kein toter Körper wie ein
-- leeres Gegner-Modell herumsteht; die KI startet nach einem Fehler neu (superviseAI).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.WeaponConfig)
local AgentConfig = require(Shared.AgentConfig)
local GameSettings = require(Shared.GameSettings)
local GunModels = require(Shared.GunModels)
local Modes = require(Shared.Modes)
local Cosmetics = require(Shared.Cosmetics)
local AgentModels = require(Shared.AgentModels)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local KillService = require(ServerShared.KillService)
local Damage = require(ServerShared.Damage)
local DownedService = require(ServerShared.DownedService)
local GadgetService = require(ServerShared.GadgetService)
local WeaponService = require(ServerShared.WeaponService)
local AgentBody = require(ServerShared.AgentBody)

local BotService = {}

local TICK = 0.15            -- Sekunden zwischen zwei KI-Schritten
-- Reaktionszeit und Streuung der Bots: Einstellungen BotReaction / BotSpread (Admin-Panel)
local KEEP_DISTANCE = 30     -- ab hier bleibt der Bot stehen und weicht seitlich aus
local VIEW_RANGE = 250       -- so weit sieht ein Bot
local WANDER_RADIUS = 60     -- ohne Gegner: zufällig um die Mapmitte laufen
local HELP_RADIUS = 80       -- so weit laufen Bots zu niedergeschlagenen Teamkollegen
local GADGET_CHANCE = 0.04   -- Chance pro KI-Schritt, ein Gadget auf einen sichtbaren Gegner zu werfen

-- Standard-Animationen von Roblox (R15)
local ANIMATIONS = {
	Idle = "rbxassetid://507766666",
	Walk = "rbxassetid://507777826",
	Hold = "rbxassetid://507768375",
}

local NAMES = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet", "Kilo", "Lima" }

-- Bot-Modelle liegen in Workspace.Bots, Infos für die Clients in ReplicatedStorage.BotInfo
local modelFolder = Instance.new("Folder")
modelFolder.Name = "Bots"
modelFolder.Parent = workspace
local infoFolder = Instance.new("Folder")
infoFolder.Name = "BotInfo"
infoFolder.Parent = ReplicatedStorage

local bots = {} -- [bot] = true
local owners = setmetatable({}, { __mode = "k" }) -- [Modell] = bot (zum Aufräumen verwaister Modelle)
local nextId = 0
local random = Random.new()

-- ---------- Verwaltung ----------

-- Neuer Bot (noch ohne Modell). Der Modus spawnt ihn mit SpawnModel.
function BotService.Create(modeId)
	nextId += 1
	local agent = AgentConfig.Agents[random:NextInteger(1, #AgentConfig.Agents)]
	local bot = {
		Id = nextId,
		Name = "BOT " .. NAMES[(nextId - 1) % #NAMES + 1] .. (nextId > #NAMES and tostring(nextId) or ""),
		Mode = modeId,
		Agent = agent.Id,
		Team = nil,
		Model = nil,
		Alive = false,
		CanFight = false,
	}
	local info = Instance.new("Configuration")
	info.Name = bot.Name
	info:SetAttribute("Mode", modeId)
	info:SetAttribute("Agent", agent.Id)
	info:SetAttribute("TeamName", "")
	info.Parent = infoFolder
	bot.Info = info
	bots[bot] = true
	return bot
end

function BotService.SetTeam(bot, team)
	bot.Team = team
	local teamName = team and team.Name or ""
	bot.Info:SetAttribute("TeamName", teamName)
	if bot.Model then
		bot.Model:SetAttribute("TeamName", teamName)
	end
end

-- Alle Bots (optional nur in einem Modus)
function BotService.All(modeId)
	local list = {}
	for bot in bots do
		if not modeId or bot.Mode == modeId then
			table.insert(list, bot)
		end
	end
	return list
end

-- Modell entfernen (Bot bleibt angemeldet, z.B. zwischen Drop-Runden).
-- Bricht auch einen gerade laufenden SpawnModel ab (der baut dann kein Modell mehr).
function BotService.Despawn(bot)
	bot.SpawnSerial = (bot.SpawnSerial or 0) + 1
	if bot.Model then
		bot.Model:Destroy()
	end
	bot.Model = nil
	bot.Alive = false
end

-- Bot komplett löschen
function BotService.Destroy(bot)
	BotService.Despawn(bot)
	bot.Info:Destroy()
	bots[bot] = nil
end

-- ---------- Ziele ----------

local function livingHumanoid(model)
	local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Ist model (Spieler- oder Bot-Charakter) ein Gegner dieses Bots?
local function isEnemy(bot, model)
	if model == bot.Model or model:GetAttribute("SafeZone") then
		return false
	end
	if model:GetAttribute("IsZombie") then
		return bot.ZombieRange ~= nil -- nur Bots der offenen Welt wehren sich gegen Zombies
	end
	local player = Players:GetPlayerFromCharacter(model)
	local mode, teamName
	if player then
		mode = player:GetAttribute("Mode")
		teamName = player.Team and player.Team.Name or ""
	elseif model:GetAttribute("IsBot") then
		mode = model:GetAttribute("Mode")
		teamName = model:GetAttribute("TeamName") or ""
	else
		return false
	end
	if mode ~= bot.Mode then
		return false
	end
	return not (bot.Team ~= nil and teamName == bot.Team.Name)
end

-- Alle lebenden Gegner im selben Modus
local function enemies(bot)
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if livingHumanoid(character) and isEnemy(bot, character) and not DownedService.IsDowned(character)
			and not character:GetAttribute("Cloaked") then
			table.insert(list, character)
		end
	end
	for other in bots do
		if other ~= bot and livingHumanoid(other.Model) and isEnemy(bot, other.Model)
			and not DownedService.IsDowned(other.Model) then
			table.insert(list, other.Model)
		end
	end
	-- Zombies in der Nähe (offene Welt)
	local root = bot.ZombieRange and bot.Model and bot.Model:FindFirstChild("HumanoidRootPart")
	local zombies = root and workspace:FindFirstChild("Zombies")
	for _, zombie in zombies and zombies:GetChildren() or {} do
		-- erst der Abstand (billig), dann Attribut und Leben (die meisten Zombies sind weit weg)
		local zombieRoot = zombie:IsA("Model") and zombie:FindFirstChild("HumanoidRootPart")
		if zombieRoot and (zombieRoot.Position - root.Position).Magnitude <= bot.ZombieRange
			and zombie:GetAttribute("IsZombie") and livingHumanoid(zombie) then
			table.insert(list, zombie)
		end
	end
	return list
end

local function canSee(bot, fromPos, model)
	local head = model:FindFirstChild("Head")
	if not head then
		return false
	end
	-- Filter je Bot einmal anlegen (nicht bei jedem Blick neu)
	local params = bot.SightParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { bot.Model }
		bot.SightParams = params
	end
	local result = workspace:Raycast(fromPos, head.Position - fromPos, params)
	return result ~= nil and result.Instance:IsDescendantOf(model) and not GadgetService.BlocksSight(fromPos, head.Position)
end

-- ---------- Schießen ----------

local function spread(direction, degrees)
	local angle = math.rad(degrees) * math.sqrt(random:NextNumber())
	local spin = random:NextNumber() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)).LookVector
end

local function shoot(bot, head, target, weaponName)
	local cfg = WeaponConfig.Get(weaponName)
	local aimPart = target:FindFirstChild("UpperTorso") or target:FindFirstChild("Torso") or target:FindFirstChild("Head")
	if not aimPart then
		return
	end
	local origin = head.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.Model }

	-- Blickwinkel für die Arm-Pose auf den Clients (nur bei spürbarer Änderung neu setzen)
	local pitch = math.round(math.deg(math.asin(math.clamp((aimPart.Position - origin).Unit.Y, -1, 1))))
	if math.abs(pitch - (bot.Model:GetAttribute("AimPitch") or 0)) >= 2 then
		bot.Model:SetAttribute("AimPitch", pitch)
	end

	for _ = 1, cfg.Pellets or 1 do
		local direction = spread(aimPart.Position - origin, (cfg.Spread or 0) + GameSettings.Get("BotSpread"))
		local result = workspace:Raycast(origin, direction * cfg.Range, params)
		local endPos = result and result.Position or (origin + direction * cfg.Range)

		local hitModel = result and result.Instance:FindFirstAncestorOfClass("Model")
		local humanoid = livingHumanoid(hitModel)
		local hitKind = result and (hitModel and hitModel:FindFirstChildOfClass("Humanoid") and "Character"
			or (result.Instance.Anchored and "World" or "Prop"))
		WeaponService.BroadcastShot(bot.Mode, bot.Model, origin, endPos, weaponName, result and result.Normal, hitKind)
		if humanoid and isEnemy(bot, hitModel) then
			local headshot = result.Instance.Name == "Head"
			local damage = cfg.Damage * (headshot and WeaponConfig.HeadshotMultiplier or 1)
				* GameSettings.Get("DamageMultiplier") * GameSettings.Get("BotDamage")
			local _, killed = Damage.Apply(hitModel, humanoid, damage,
				{ BotName = bot.Name, Model = bot.Model, Weapon = weaponName, Headshot = headshot })
			if killed and not hitModel:GetAttribute("IsZombie") then -- Zombies zählen nicht (kein Killfeed)
				local victim = Players:GetPlayerFromCharacter(hitModel)
				KillService.ReportBotKill(bot.Mode, bot.Name, victim and victim.Name or hitModel.Name, weaponName, headshot)
				bot.Info:SetAttribute("Kills", (bot.Info:GetAttribute("Kills") or 0) + 1)
			end
		end
	end
end

-- ---------- KI ----------

-- Wegfindung: Bots laufen um Wände herum statt dagegen. Pfad wird neu berechnet, wenn sich das Ziel
-- deutlich bewegt hat, der Pfad zu alt ist oder der Bot festhängt.
local REPATH_TIME = 2.5
local function makeNavigator(humanoid, root)
	local nav = { Goal = nil, Waypoints = nil, Index = 0, ComputedAt = 0 }
	local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5.5, AgentCanJump = true,
		WaypointSpacing = 6 })

	function nav.MoveTo(goal, stuck)
		local now = os.clock()
		local needPath = nav.Waypoints == nil or nav.Goal == nil or (goal - nav.Goal).Magnitude > 10
			or now - nav.ComputedAt > REPATH_TIME or nav.Index > #nav.Waypoints or stuck
		if needPath then
			nav.Goal, nav.ComputedAt = goal, now
			local ok = pcall(path.ComputeAsync, path, root.Position, goal)
			if ok and path.Status == Enum.PathStatus.Success then
				nav.Waypoints = path:GetWaypoints()
				nav.Index = 2
			else
				nav.Waypoints = nil
				humanoid:MoveTo(goal) -- kein Weg gefunden: direkt versuchen
				return
			end
		end
		local waypoint = nav.Waypoints and nav.Waypoints[nav.Index]
		if not waypoint then
			humanoid:MoveTo(goal)
			return
		end
		local offset = waypoint.Position - root.Position
		if Vector3.new(offset.X, 0, offset.Z).Magnitude < 3.5 then
			nav.Index += 1
			waypoint = nav.Waypoints[nav.Index]
			if not waypoint then
				humanoid:MoveTo(goal)
				return
			end
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(waypoint.Position)
	end

	function nav.Clear()
		nav.Waypoints = nil
		nav.Goal = nil
	end
	return nav
end

local function runAI(bot, model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:WaitForChild("HumanoidRootPart")
	local head = model:WaitForChild("Head")
	local weaponName = bot.Weapon or AgentConfig.Get(bot.Agent).Loadout[1]
	local cfg = WeaponConfig.Get(weaponName)
	local center = bot.Home or Modes.Get(bot.Mode).Center

	local seenSince = nil
	local lastShot = 0
	local shotsInMagazine = 0
	local reloadUntil = 0
	local nextMove = 0
	local lastPosition = root.Position
	local nav = makeNavigator(humanoid, root)
	local wanderGoal = nil -- Ziel ohne Gegner in Sicht (Punkt, nächster Gegner, Umherlaufen)
	local stuckTicks = 0

	while bot.Model == model and humanoid.Health > 0 do
		local now = os.clock()

		-- Stacheldraht (TRAPPER) bremst auch Bots
		local slowed = (model:GetAttribute("SlowedUntil") or 0) > workspace:GetServerTimeNow()
		humanoid.WalkSpeed = AgentConfig.Get(bot.Agent).WalkSpeed * (slowed and 0.5 or 1)

		-- Selbst am Boden: liegen bleiben und warten
		if DownedService.IsDowned(model) then
			humanoid:MoveTo(root.Position)
			task.wait(TICK)
			continue
		end

		-- Nächsten sichtbaren Gegner suchen (und den nächsten überhaupt, um hinzulaufen)
		local nearest, nearestDistance = nil, math.huge
		local target, targetDistance = nil, math.huge
		for _, enemy in enemies(bot) do
			local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
			if enemyRoot then
				local distance = (enemyRoot.Position - root.Position).Magnitude
				-- hinlaufen nur zu Spielern und Bots (Zombies nur abwehren), in der offenen Welt nicht quer über die Karte
				if distance < nearestDistance and not enemy:GetAttribute("IsZombie") and distance <= (bot.HuntRange or math.huge) then
					nearest, nearestDistance = enemy, distance
				end
				if distance < targetDistance and distance <= VIEW_RANGE and canSee(bot, head.Position, enemy) then
					target, targetDistance = enemy, distance
				end
			end
		end

		-- Waffe im Anschlag, solange ein Gegner in Sicht ist (Arm-Pose auf den Clients)
		model:SetAttribute("Aiming", target ~= nil)
		if not target and model:GetAttribute("AimPitch") ~= 0 then
			model:SetAttribute("AimPitch", 0)
		end

		-- Orte, die der Modus nicht erlaubt (offene Welt: Safe Zones): nicht hingehen und von dort nicht schießen
		local function allowed(point)
			return not bot.AllowPoint or bot.AllowPoint(point)
		end
		if target then
			local targetPosition = target.HumanoidRootPart.Position
			seenSince = seenSince or now
			-- Zum Ziel drehen
			humanoid.AutoRotate = false
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPosition.X, root.Position.Y, targetPosition.Z))
			nav.Clear()
			wanderGoal = nil
			if now >= nextMove then
				local strafe = root.Position + root.CFrame.RightVector * random:NextInteger(-12, 12)
				if targetDistance > KEEP_DISTANCE and allowed(targetPosition) then
					humanoid:MoveTo(targetPosition) -- in Sicht: direkter Weg ist frei
				elseif allowed(strafe) then
					humanoid:MoveTo(strafe)
				else
					humanoid:MoveTo(root.Position)
				end
				nextMove = now + 0.8
			end
			-- Schießen (Reaktionszeit, Feuerrate, Magazin)
			local ready = now - seenSince >= GameSettings.Get("BotReaction") and now >= reloadUntil
				and now - lastShot >= cfg.FireDelay and targetDistance <= cfg.Range
			local blinded = (model:GetAttribute("BlindedUntil") or 0) > now
			-- Ab und zu ein Gadget werfen (mittlere Entfernung)
			local canShoot = bot.CanFight and allowed(root.Position)
			if canShoot and not blinded and targetDistance > 15 and targetDistance < 60
				and random:NextNumber() < GADGET_CHANCE then
				local aim = (targetPosition - head.Position).Unit + Vector3.new(0, 0.15, 0)
				GadgetService.BotThrow(bot, aim)
			end
			if canShoot and ready and not blinded then
				lastShot = now
				shoot(bot, head, target, weaponName)
				shotsInMagazine += 1
				if shotsInMagazine >= cfg.MagazineSize then
					shotsInMagazine = 0
					reloadUntil = now + cfg.ReloadTime
					-- Nachlade-Animation auf den Clients
					model:SetAttribute("ReloadStart", workspace:GetServerTimeNow())
					model:SetAttribute("ReloadTime", cfg.ReloadTime)
					model:SetAttribute("ReloadShells", cfg.ShellReload and cfg.MagazineSize or nil)
				end
			end
		else
			seenSince = nil
			humanoid.AutoRotate = true
			-- Kein Gegner in Sicht: niedergeschlagenen Teamkollegen wiederbeleben
			local mate, mateDistance = nil, HELP_RADIUS
			for _, downedModel in DownedService.All() do
				local mateRoot = downedModel:FindFirstChild("HumanoidRootPart")
				if mateRoot and not isEnemy(bot, downedModel) and downedModel ~= model then
					local distance = (mateRoot.Position - root.Position).Magnitude
					if distance < mateDistance then
						mate, mateDistance = downedModel, distance
					end
				end
			end
			local stuck = stuckTicks > 6
			if stuck then
				stuckTicks = 0
			end
			if mate then
				if not DownedService.ReviveTick(model, mate, TICK) then
					nav.MoveTo(mate.HumanoidRootPart.Position, stuck)
				end
			else
				if now >= nextMove or not wanderGoal then
					if bot.Objective then
						-- Ziel des Modus (Punkt, Bombe, Hack)
						wanderGoal = bot.Objective + Vector3.new(random:NextNumber(-6, 6), 0, random:NextNumber(-6, 6))
					elseif nearest and allowed(nearest.HumanoidRootPart.Position) then
						wanderGoal = nearest.HumanoidRootPart.Position
					else
						-- zufällig um die Mitte; ein Punkt, den der Modus nicht erlaubt (Safe Zone), wird neu gewürfelt
						for _ = 1, 4 do
							local offset = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * WANDER_RADIUS
							wanderGoal = center + offset
							if not bot.AllowPoint or bot.AllowPoint(wanderGoal) then
								break
							end
							wanderGoal = root.Position
						end
					end
					nextMove = now + 2
				end
				nav.MoveTo(wanderGoal, stuck)
			end
		end

		-- Festgelaufen? Springen und Weg neu berechnen.
		if (root.Position - lastPosition).Magnitude < 0.3 and humanoid.MoveDirection.Magnitude > 0 then
			humanoid.Jump = true
			stuckTicks += 1
		else
			stuckTicks = 0
		end
		lastPosition = root.Position
		task.wait(TICK)
	end
end

local function playAnimations(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
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
	local hold = load(ANIMATIONS.Hold, Enum.AnimationPriority.Action)
	if idle then
		idle:Play()
	end
	if hold then
		hold:Play() -- Arm mit Waffe nach vorne
	end
	humanoid.Running:Connect(function(speed)
		if not walk then
			return
		end
		if speed > 1 and not walk.IsPlaying then
			walk:Play()
		elseif speed <= 1 and walk.IsPlaying then
			walk:Stop()
		end
	end)
end

-- Körper-Vorlagen pro Agent. Players:CreateHumanoidModelFromDescription wartet (lädt Assets) und kann
-- dauern – während dieser Zeit konnte ein Bot schon entfernt, neu gespawnt oder die Runde vorbei sein,
-- und dann blieb ein zweites ("verwaistes") Modell in der Welt stehen. Deshalb wird jeder Agent nur
-- einmal gebaut und danach geklont: Klonen wartet nicht.
-- Bots sehen aus wie Spieler mit diesem Agenten: derselbe Körper (AgentBody) im Standard-Look bzw. mit dem 3D-Modell
-- des Agenten, wenn es eins gibt, dieselben Trefferzonen. Das Team erkennt man wie bei Spielern am Namensschild (nur
-- fürs eigene Team).
local SPAWN_RETRY = 3 -- Sekunden bis zum nächsten Versuch, wenn ein Körper nicht gebaut werden konnte
local templates = {}  -- [Agent-Id] = Modell (außerhalb des Workspace)
local building = {}   -- [Agent-Id] = true, solange die Vorlage gebaut wird
-- Neues oder geändertes 3D-Modell eines Agenten: Vorlage beim nächsten Bot neu bauen
AgentModels.OnChanged(function(agentId)
	templates[agentId] = nil
end)

local function rigTemplate(agent)
	local key = agent.Id
	while building[key] do
		task.wait(0.1)
	end
	if templates[key] then
		return templates[key]
	end
	-- Agent mit 3D-Modell: das Modell ist selbst der Körper des Bots (kein Roblox-Standardkörper)
	local own = AgentModels.BuildCharacter(agent.Id)
	if own then
		own.Archivable = true
		local ownHumanoid = own:FindFirstChildOfClass("Humanoid")
		if ownHumanoid then
			ownHumanoid.BreakJointsOnDeath = false
		end
		templates[key] = own
		return own
	end
	building[key] = true
	local primary = Cosmetics.AgentColors(nil, agent.Id)
	local description = AgentBody.Description(primary)
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	building[key] = nil
	if not ok or not model then
		warn("Bot-Körper konnte nicht erstellt werden: " .. tostring(model))
		return nil
	end
	model.Archivable = true
	AgentBody.Dress(model, primary, agent.Id)
	-- Beim Tod nicht von Roblox zerlegen lassen: das macht corpse() einheitlich (Ragdoll, dann ausblenden)
	local templateHumanoid = model:FindFirstChildOfClass("Humanoid")
	if templateHumanoid then
		templateHumanoid.BreakJointsOnDeath = false
	end
	templates[key] = model
	return model
end

-- ---------- Tod: Ragdoll, dann ausblenden ----------
-- Wie ein toter Körper aussieht, hängt sonst von Roblox ab: klassisch zerfallen, Ragdoll oder – mit dem Avatar
-- Joint Upgrade (AnimationConstraints statt Motor6D) – steif stehen bleiben. Ein stehender toter Bot sieht aus wie
-- ein leeres Gegner-Modell. Darum hier einheitlich: Gelenke durch Kugelgelenke ersetzen (der Körper fällt um),
-- nach CORPSE_FADE_START Sekunden ausblenden und danach unsichtbar ohne Kollision liegen lassen, bis der Bot
-- neu spawnt (Despawn räumt das Modell dann weg).
local CORPSE_FADE_START = 2
local CORPSE_FADE_TIME = 0.6
local CORPSE_FADE_STEPS = 6

local function ragdoll(model)
	AgentModels.WeldToBody(model) -- Agentenmodell (Rig) fällt mit dem Körper
	for _, joint in model:GetDescendants() do
		if (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) and joint.Parent then
			-- AnimationConstraint: Part0/Part1/C0/C1 sind lesbare Aliase der Attachments. Klappt das Kugelgelenk
			-- nicht, zerfällt der Körper eben klassisch – Hauptsache, er bleibt nicht stehen.
			pcall(function()
				local part0, part1 = joint.Part0, joint.Part1
				if part0 and part1 then
					local a0 = Instance.new("Attachment")
					a0.Name = "RagdollAttachment"
					a0.CFrame = joint.C0
					a0.Parent = part0
					local a1 = Instance.new("Attachment")
					a1.Name = "RagdollAttachment"
					a1.CFrame = joint.C1
					a1.Parent = part1
					local socket = Instance.new("BallSocketConstraint")
					socket.Attachment0 = a0
					socket.Attachment1 = a1
					socket.LimitsEnabled = true
					socket.UpperAngle = 70
					socket.TwistLimitsEnabled = true
					socket.TwistLowerAngle = -45
					socket.TwistUpperAngle = 45
					socket.Parent = part1
					-- Nachbarteile nicht gegeneinander stoßen lassen (sonst zittert der Körper)
					local noCollide = Instance.new("NoCollisionConstraint")
					noCollide.Part0 = part0
					noCollide.Part1 = part1
					noCollide.Parent = part1
				end
			end)
			joint:Destroy()
		end
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = true -- Gliedmaßen liegen auf dem Boden statt hindurchzufallen
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			pcall(part.SetNetworkOwner, part, nil) -- der Server rechnet den fallenden Körper
		end
	end
end

local function corpse(model)
	ragdoll(model)
	task.wait(CORPSE_FADE_START)
	local items = {}
	for _, obj in model:GetDescendants() do
		if obj:IsA("BasePart") or obj:IsA("Decal") then
			table.insert(items, { Object = obj, From = obj.Transparency })
		end
	end
	for step = 1, CORPSE_FADE_STEPS do
		if not model.Parent then
			return
		end
		for _, item in items do
			item.Object.Transparency = item.From + (1 - item.From) * step / CORPSE_FADE_STEPS
		end
		task.wait(CORPSE_FADE_TIME / CORPSE_FADE_STEPS)
	end
	for _, item in items do
		local part = item.Object
		if part:IsA("BasePart") and part.Parent then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
end

-- KI mit Neustart: Ein Fehler in einem KI-Schritt darf keinen lebenden Bot als stehendes, leeres Modell
-- zurücklassen
local function superviseAI(bot, model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	while bot.Model == model and model.Parent and humanoid and humanoid.Health > 0 do
		local ok, err = pcall(runAI, bot, model)
		if ok then
			return
		end
		warn(string.format("Bot-KI von %s neu gestartet: %s", bot.Name, tostring(err)))
		task.wait(1)
	end
end

-- Modell an cframe erzeugen und KI starten. onDied wird beim Tod aufgerufen.
-- Gibt das Modell zurück, oder nil, wenn der Spawn abgebrochen wurde (Bot inzwischen despawnt/gelöscht
-- bzw. neu gespawnt) oder der Körper noch nicht gebaut werden konnte (dann neuer Versuch nach SPAWN_RETRY).
function BotService.SpawnModel(bot, cframe, onDied)
	BotService.Despawn(bot)
	local serial = bot.SpawnSerial
	local agent = AgentConfig.Get(bot.Agent)

	-- Körper des Agenten (wartet nur beim ersten Mal pro Agent)
	local template = rigTemplate(agent)
	if bot.SpawnSerial ~= serial or not bots[bot] then
		return nil -- inzwischen despawnt, gelöscht oder schon neu gespawnt: kein zweites Modell
	end
	if not template then
		task.delay(SPAWN_RETRY, function()
			if bot.SpawnSerial == serial and bots[bot] then
				BotService.SpawnModel(bot, cframe, onDied)
			end
		end)
		return nil
	end
	local model = template:Clone()
	AgentBody.Protect(model) -- Accessoires (falls je welche dazukommen) sind nie Trefferzone

	model.Name = bot.Name
	model:SetAttribute("IsBot", true)
	model:SetAttribute("Mode", bot.Mode)
	model:SetAttribute("Agent", bot.Agent)
	model:SetAttribute("TeamName", bot.Team and bot.Team.Name or "")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayName = bot.Name .. " · " .. agent.Name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- Namen zeigt der Client nur fürs eigene Team
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = agent.Health
	humanoid.Health = agent.Health
	humanoid.WalkSpeed = agent.WalkSpeed
	owners[model] = bot
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- Streaming: beim Client ganz oder gar nicht
	model.Parent = modelFolder
	model:PivotTo(cframe)
	pcall(function()
		model.HumanoidRootPart:SetNetworkOwner(nil) -- Server steuert den Bot
	end)

	-- Hauptwaffe in die Hand (der Modus kann eine andere vorgeben)
	local weaponName = bot.Weapon or agent.Loadout[1]
	local tool = GunModels.BuildTool(weaponName, WeaponConfig.Get(weaponName).DisplayName)
	tool.Parent = model
	humanoid:EquipTool(tool)
	playAnimations(humanoid)

	bot.Model = model
	bot.SightParams = nil -- neuer Körper: Sicht-Filter neu anlegen
	bot.Alive = true
	bot.GadgetCharges = (not bot.NoGadgets and agent.Gadget and agent.Gadget.Charges) or 0
	-- Tod: über Died und zur Sicherheit auch über das Leben (genau einmal)
	local dead = false
	local function onDeath()
		if dead then
			return
		end
		dead = true
		if bot.Model == model then
			bot.Alive = false
			bot.Info:SetAttribute("Deaths", (bot.Info:GetAttribute("Deaths") or 0) + 1)
			if onDied then
				onDied()
			end
		end
		task.spawn(corpse, model)
	end
	humanoid.Died:Once(onDeath)
	humanoid.HealthChanged:Connect(function(health)
		if health <= 0 then
			onDeath()
		end
	end)
	task.spawn(superviseAI, bot, model)
	return model
end

-- Sicherheitsnetz: Modelle, die keinem angemeldeten Bot (mehr) gehören, regelmäßig entfernen.
-- Die Leiche eines Bots bleibt (umgefallen und ausgeblendet, siehe corpse), bis er neu spawnt – sie ist dann
-- noch sein bot.Model.
task.spawn(function()
	while true do
		task.wait(2)
		for _, model in modelFolder:GetChildren() do
			local bot = owners[model]
			if not bot or not bots[bot] or bot.Model ~= model then
				model:Destroy()
			end
		end
	end
end)

return BotService

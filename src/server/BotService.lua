-- BotService (ModuleScript, nur Server)
-- Computer-Gegner zum Testen und Auffüllen. Ein Bot hat einen zufälligen Agenten,
-- dessen Leben, Tempo und Hauptwaffe. Er sucht den nächsten sichtbaren Gegner im selben
-- Modus, läuft hin, hält Abstand und schießt mit etwas Streuung.
-- Die Modi (FreeForAll, Drop) entscheiden, wann ein Bot spawnt; der BotService baut Modell und KI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.WeaponConfig)
local AgentConfig = require(Shared.AgentConfig)
local GameSettings = require(Shared.GameSettings)
local Remotes = require(Shared.Remotes)
local GunModels = require(Shared.GunModels)
local Modes = require(Shared.Modes)
local KillService = require(ServerStorage:WaitForChild("ServerShared").KillService)

local BotService = {}

local TICK = 0.15            -- Sekunden zwischen zwei KI-Schritten
local REACTION_TIME = 0.5    -- so lange muss ein Gegner sichtbar sein, bevor der Bot schießt
local AIM_SPREAD = 4         -- zusätzliche Streuung in Grad (Bots treffen nicht perfekt)
local KEEP_DISTANCE = 30     -- ab hier bleibt der Bot stehen und weicht seitlich aus
local VIEW_RANGE = 250       -- so weit sieht ein Bot
local WANDER_RADIUS = 60     -- ohne Gegner: zufällig um die Mapmitte laufen

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

-- Modell entfernen (Bot bleibt angemeldet, z.B. zwischen Drop-Runden)
function BotService.Despawn(bot)
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
	if model == bot.Model then
		return false
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
		if livingHumanoid(player.Character) and isEnemy(bot, player.Character) then
			table.insert(list, player.Character)
		end
	end
	for other in bots do
		if other ~= bot and livingHumanoid(other.Model) and isEnemy(bot, other.Model) then
			table.insert(list, other.Model)
		end
	end
	return list
end

local function canSee(bot, fromPos, model)
	local head = model:FindFirstChild("Head")
	if not head then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.Model }
	local result = workspace:Raycast(fromPos, head.Position - fromPos, params)
	return result ~= nil and result.Instance:IsDescendantOf(model)
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

	for _ = 1, cfg.Pellets or 1 do
		local direction = spread(aimPart.Position - origin, (cfg.Spread or 0) + AIM_SPREAD)
		local result = workspace:Raycast(origin, direction * cfg.Range, params)
		local endPos = result and result.Position or (origin + direction * cfg.Range)
		Remotes.Shot:FireAllClients(nil, origin, endPos)

		local hitModel = result and result.Instance:FindFirstAncestorOfClass("Model")
		local humanoid = livingHumanoid(hitModel)
		if humanoid and isEnemy(bot, hitModel) then
			local headshot = result.Instance.Name == "Head"
			local damage = cfg.Damage * (headshot and WeaponConfig.HeadshotMultiplier or 1)
				* GameSettings.Get("DamageMultiplier") * GameSettings.Get("BotDamage")
			humanoid:TakeDamage(damage)
			if humanoid.Health <= 0 then
				local victim = Players:GetPlayerFromCharacter(hitModel)
				KillService.ReportBotKill(bot.Mode, bot.Name, victim and victim.Name or hitModel.Name, weaponName, headshot)
			end
		end
	end
end

-- ---------- KI ----------

local function runAI(bot, model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:WaitForChild("HumanoidRootPart")
	local head = model:WaitForChild("Head")
	local weaponName = AgentConfig.Get(bot.Agent).Loadout[1]
	local cfg = WeaponConfig.Get(weaponName)
	local center = Modes.Get(bot.Mode).Center

	local seenSince = nil
	local lastShot = 0
	local shotsInMagazine = 0
	local reloadUntil = 0
	local nextMove = 0
	local lastPosition = root.Position

	while bot.Model == model and humanoid.Health > 0 do
		local now = os.clock()

		-- Nächsten sichtbaren Gegner suchen (und den nächsten überhaupt, um hinzulaufen)
		local nearest, nearestDistance = nil, math.huge
		local target, targetDistance = nil, math.huge
		for _, enemy in enemies(bot) do
			local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
			if enemyRoot then
				local distance = (enemyRoot.Position - root.Position).Magnitude
				if distance < nearestDistance then
					nearest, nearestDistance = enemy, distance
				end
				if distance < targetDistance and distance <= VIEW_RANGE and canSee(bot, head.Position, enemy) then
					target, targetDistance = enemy, distance
				end
			end
		end

		if target then
			local targetPosition = target.HumanoidRootPart.Position
			seenSince = seenSince or now
			-- Zum Ziel drehen
			humanoid.AutoRotate = false
			root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetPosition.X, root.Position.Y, targetPosition.Z))
			if now >= nextMove then
				if targetDistance > KEEP_DISTANCE then
					humanoid:MoveTo(targetPosition)
				else
					humanoid:MoveTo(root.Position + root.CFrame.RightVector * random:NextInteger(-12, 12))
				end
				nextMove = now + 0.8
			end
			-- Schießen (Reaktionszeit, Feuerrate, Magazin)
			local ready = now - seenSince >= REACTION_TIME and now >= reloadUntil
				and now - lastShot >= cfg.FireDelay and targetDistance <= cfg.Range
			if bot.CanFight and ready then
				lastShot = now
				shoot(bot, head, target, weaponName)
				shotsInMagazine += 1
				if shotsInMagazine >= cfg.MagazineSize then
					shotsInMagazine = 0
					reloadUntil = now + cfg.ReloadTime
				end
			end
		else
			seenSince = nil
			humanoid.AutoRotate = true
			if now >= nextMove then
				if nearest then
					humanoid:MoveTo(nearest.HumanoidRootPart.Position)
				else
					local offset = Vector3.new(random:NextNumber(-1, 1), 0, random:NextNumber(-1, 1)) * WANDER_RADIUS
					humanoid:MoveTo(center + offset)
				end
				nextMove = now + 2
			end
		end

		-- Festgelaufen? Springen.
		if (root.Position - lastPosition).Magnitude < 0.3 and humanoid.MoveDirection.Magnitude > 0 then
			humanoid.Jump = true
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

-- Modell an cframe erzeugen und KI starten. onDied wird beim Tod aufgerufen.
function BotService.SpawnModel(bot, cframe, onDied)
	BotService.Despawn(bot)
	local agent = AgentConfig.Get(bot.Agent)

	-- Körper in Team- bzw. Agentenfarbe
	local color = bot.Team and bot.Team.TeamColor.Color or agent.Color
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = Color3.fromRGB(205, 160, 130)
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
	description.LeftLegColor = Color3.fromRGB(40, 40, 45)
	description.RightLegColor = Color3.fromRGB(40, 40, 45)
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok or not model then
		warn("Bot konnte nicht erstellt werden: " .. tostring(model))
		return nil
	end

	model.Name = bot.Name
	model:SetAttribute("IsBot", true)
	model:SetAttribute("Mode", bot.Mode)
	model:SetAttribute("Agent", bot.Agent)
	model:SetAttribute("TeamName", bot.Team and bot.Team.Name or "")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayName = bot.Name .. " · " .. agent.Name
	humanoid.MaxHealth = agent.Health
	humanoid.Health = agent.Health
	humanoid.WalkSpeed = agent.WalkSpeed
	model.Parent = modelFolder
	model:PivotTo(cframe)
	pcall(function()
		model.HumanoidRootPart:SetNetworkOwner(nil) -- Server steuert den Bot
	end)

	-- Hauptwaffe in die Hand
	local weaponName = agent.Loadout[1]
	local tool = GunModels.BuildTool(weaponName, WeaponConfig.Get(weaponName).DisplayName)
	tool.Parent = model
	humanoid:EquipTool(tool)
	playAnimations(humanoid)

	bot.Model = model
	bot.Alive = true
	humanoid.Died:Connect(function()
		if bot.Model == model then
			bot.Alive = false
			if onDied then
				onDied()
			end
		end
	end)
	task.spawn(runAI, bot, model)
	return model
end

return BotService

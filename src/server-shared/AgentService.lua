-- AgentService (ModuleScript, nur Server)
-- Agentenwahl, Leben pro Agent und Fähigkeiten. Alles wird auf dem Server geprüft.
-- Dazu die Ultimate "Überladung" (AgentConfig.Ultimate): lädt über Schaden/Kills (Damage) und langsam im Kampf.
-- Spieler-Attribute: Agent (Id), AbilityReadyAt (Serverzeit), AbilityActiveUntil (Serverzeit), UltCharge (0-100)
-- Charakter-Attribute: Agent (aktiver Agent dieses Lebens), SpeedMultiplier (Tempo-Faktor)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local Cosmetics = require(Shared.Cosmetics)
local Modes = require(Shared.Modes)
local BuyConfig = require(Shared.BuyConfig)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local Damage = require(ServerShared.Damage)
local WeaponService = require(ServerShared.WeaponService)
local AgentBody = require(ServerShared.AgentBody)

local AgentService = {}

local function serverNow()
	return workspace:GetServerTimeNow()
end

local function getAgent(player)
	return AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
end

-- Agenten-Look überall (Hub, Markt, Match): einheitlicher Körper in Agentenfarben bzw. Skin mit Ausrüstung,
-- ohne eigenen Avatar (AgentBody) – bis die eigenen Agenten-Modelle aus Blender da sind
local function applyUniform(player, character, agent)
	-- nur den aktuellen Charakter (CharacterAdded kommt in Roblox schon, bevor er im Workspace ist – anziehen
	-- geht trotzdem)
	if player.Character ~= character then
		return
	end
	local primary, accent = Cosmetics.AgentColors(player, agent.Id)
	AgentBody.Dress(character, primary, accent)
end

-- Leben und Fähigkeit beim Spawn setzen
local function applyAgent(player, character)
	local agent = getAgent(player)
	local humanoid = character:WaitForChild("Humanoid")
	local health = agent.Health + (BuyConfig.Has(player, "Tough") and BuyConfig.ToughHealth or 0)
	humanoid.MaxHealth = health
	humanoid.Health = health
	character:SetAttribute("Agent", agent.Id)
	character:SetAttribute("SpeedMultiplier", 1)
	player:SetAttribute("AbilityReadyAt", 0)
	player:SetAttribute("AbilityActiveUntil", 0)
end

-- Funkeln am Charakter als einfacher Effekt
local function sparkle(root, color, duration)
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = color
	sparkles.Parent = root
	Debris:AddItem(sparkles, duration)
end

local function doBoost(character, root, agent)
	local ability = agent.Ability
	character:SetAttribute("SpeedMultiplier", ability.SpeedMultiplier)
	sparkle(root, agent.Color, ability.Duration)
	task.delay(ability.Duration, function()
		if character.Parent then
			character:SetAttribute("SpeedMultiplier", 1)
		end
	end)
end

local function doWall(character, root, agent)
	local ability = agent.Ability
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit

	-- Boden vor dem Spieler suchen
	local spot = root.Position + flat * 6
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(spot + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
	local groundY = hit and hit.Position.Y or (root.Position.Y - 3)

	local center = Vector3.new(spot.X, groundY + ability.Size.Y / 2, spot.Z)
	local wall = Instance.new("Part")
	wall.Name = "AbilityWall"
	wall.Size = ability.Size
	wall.CFrame = CFrame.lookAt(center, center + flat)
	wall.Anchored = true
	wall.Material = Enum.Material.ForceField
	wall.Color = agent.Color
	wall.Transparency = 0.1
	wall.TopSurface = Enum.SurfaceType.Smooth
	wall.Parent = workspace
	Debris:AddItem(wall, ability.Duration)
end

local function doHeal(humanoid, root, agent)
	local ability = agent.Ability
	sparkle(root, Color3.fromRGB(120, 255, 140), ability.Duration)
	task.spawn(function()
		local steps = 10
		for _ = 1, steps do
			task.wait(ability.Duration / steps)
			if humanoid.Health <= 0 then
				return
			end
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + ability.Amount / steps)
		end
	end)
end

-- Gegner im Umkreis für das eigene Team markieren (nur deren Clients sehen es)
local function doReveal(player, root, agent)
	local ability = agent.Ability
	local mode = player:GetAttribute("Mode")
	local enemies = {}
	for _, other in Players:GetPlayers() do
		local isEnemy = other ~= player and other:GetAttribute("Mode") == mode
			and not (other.Team ~= nil and other.Team == player.Team)
		local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if isEnemy and otherRoot and (otherRoot.Position - root.Position).Magnitude <= ability.Radius then
			table.insert(enemies, other.Character)
		end
	end
	for _, mate in Players:GetPlayers() do
		local isMate = mate == player
			or (player.Team ~= nil and mate.Team == player.Team and mate:GetAttribute("Mode") == mode)
		if isMate then
			Remotes.Reveal:FireClient(mate, enemies, ability.Duration)
		end
	end
	sparkle(root, agent.Color, 1)
end

-- Tarnung: Körper fast unsichtbar (für alle), endet nach Ablauf oder beim Schießen
-- (WeaponService setzt dann "Cloaked" auf false)
local function doCloak(character, agent)
	local ability = agent.Ability
	local saved = {}
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			saved[part] = part.Transparency
			part.Transparency = math.max(part.Transparency, 0.92)
		elseif part:IsA("Decal") then
			saved[part] = part.Transparency
			part.Transparency = 1
		end
	end
	character:SetAttribute("Cloaked", true)
	local function reveal()
		if not character:GetAttribute("Cloaked") then
			return
		end
		character:SetAttribute("Cloaked", false)
		for obj, transparency in saved do
			if obj.Parent then
				obj.Transparency = transparency
			end
		end
	end
	character:GetAttributeChangedSignal("Cloaked"):Connect(function()
		if character:GetAttribute("Cloaked") == false then
			for obj, transparency in saved do
				if obj.Parent then
					obj.Transparency = transparency
				end
			end
		end
	end)
	task.delay(ability.Duration, reveal)
end

-- Feldlazarett: sich selbst und Teamkollegen im Umkreis heilen
local function doTeamHeal(player, root, agent)
	local ability = agent.Ability
	local mode = player:GetAttribute("Mode")
	for _, mate in Players:GetPlayers() do
		local sameTeam = mate == player or (player.Team ~= nil and mate.Team == player.Team and mate:GetAttribute("Mode") == mode)
		local character = mate.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local mateRoot = character and character:FindFirstChild("HumanoidRootPart")
		if sameTeam and humanoid and humanoid.Health > 0 and mateRoot and not character:GetAttribute("Downed")
			and (mateRoot.Position - root.Position).Magnitude <= ability.Radius then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + ability.Amount)
			sparkle(mateRoot, Color3.fromRGB(120, 255, 140), 1.5)
		end
	end
	-- Heilender Ring am Boden
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, ability.Radius * 2, ability.Radius * 2)
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = agent.Color
	ring.Transparency = 0.6
	ring.Parent = workspace
	Debris:AddItem(ring, 1)
end

-- Gegner eines Spielers im selben Modus (Spieler-Charaktere und Bot-Modelle), lebend
local function enemyModels(player)
	local mode, team = player:GetAttribute("Mode"), player.Team and player.Team.Name
	local list = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if other ~= player and humanoid and humanoid.Health > 0 and other:GetAttribute("Mode") == mode
			and not (team and other.Team and other.Team.Name == team) then
			table.insert(list, character)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	for _, model in bots and bots:GetChildren() or {} do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and model:GetAttribute("Mode") == mode
			and not (team and model:GetAttribute("TeamName") == team) then
			table.insert(list, model)
		end
	end
	return list
end

-- Schaden durch eine Fähigkeit, inkl. Kill-Meldung
local function abilityDamage(player, model, amount, weaponName)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local victim = Players:GetPlayerFromCharacter(model)
	local dealt, killed, downed, armor = Damage.Apply(model, humanoid, amount, { Player = player, Weapon = weaponName })
	if dealt > 0 then
		Remotes.Hitmarker:FireClient(player, false, killed, dealt, model:GetPivot().Position, victim and victim.Name or model.Name,
			downed, armor, model)
	end
	if killed then
		WeaponService.ReportKill(player, victim, weaponName, false, victim and victim.Name or model.Name)
	end
end

-- Stacheldraht: Fläche vor dem Spieler, Gegner darin langsamer (Attribut "SlowedUntil") + Schaden
local function doTrap(player, character, root, agent)
	local ability = agent.Ability
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local center = root.Position + flat * 8 - Vector3.new(0, 2.6, 0)
	local wire = Instance.new("Part")
	wire.Name = "BarbedWire"
	wire.Size = ability.Size
	wire.CFrame = CFrame.lookAt(center, center + flat)
	wire.Anchored = true
	wire.CanCollide = false
	wire.CanQuery = false
	wire.Material = Enum.Material.DiamondPlate
	wire.Color = Color3.fromRGB(110, 100, 85)
	wire.Transparency = 0.2
	wire.Parent = workspace
	Debris:AddItem(wire, ability.Duration)
	task.spawn(function()
		local tick = 0.25
		while wire.Parent do
			for _, model in enemyModels(player) do
				local enemyRoot = model:FindFirstChild("HumanoidRootPart")
				local localPos = enemyRoot and wire.CFrame:PointToObjectSpace(enemyRoot.Position)
				if localPos and math.abs(localPos.X) <= ability.Size.X / 2 and math.abs(localPos.Z) <= ability.Size.Z / 2
					and math.abs(localPos.Y) < 5 then
					model:SetAttribute("SlowedUntil", workspace:GetServerTimeNow() + 0.5)
					abilityDamage(player, model, ability.DamagePerSecond * tick, "Stacheldraht")
				end
			end
			task.wait(tick)
		end
	end)
end

-- Geschützturm: schießt auf den nächsten sichtbaren Gegner in Reichweite
local function doTurret(player, character, root, agent)
	local ability = agent.Ability
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local base = root.Position + flat * 4 - Vector3.new(0, 2.5, 0)
	local turret = Instance.new("Model")
	turret.Name = "Turret"
	local stand = Instance.new("Part")
	stand.Size = Vector3.new(1.4, 2.4, 1.4)
	stand.Position = base + Vector3.new(0, 1.2, 0)
	stand.Color = Color3.fromRGB(60, 62, 68)
	stand.Material = Enum.Material.Metal
	stand.Anchored = true
	stand.Parent = turret
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.6, 1, 2.2)
	head.CFrame = CFrame.lookAt(base + Vector3.new(0, 2.9, 0), base + Vector3.new(0, 2.9, 0) + flat)
	head.Color = agent.Color
	head.Material = Enum.Material.Metal
	head.Anchored = true
	head.Parent = turret
	turret.Parent = workspace
	Debris:AddItem(turret, ability.Duration)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { turret, character }
	task.spawn(function()
		while turret.Parent do
			local origin = head.Position
			local target, best = nil, ability.Range
			for _, model in enemyModels(player) do
				local aim = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
				local distance = aim and (aim.Position - origin).Magnitude or math.huge
				if distance < best and not model:GetAttribute("Cloaked") then
					local result = workspace:Raycast(origin, aim.Position - origin, params)
					if result and result.Instance:IsDescendantOf(model) then
						target, best = model, distance
					end
				end
			end
			if target then
				local aim = target:FindFirstChild("UpperTorso") or target:FindFirstChild("HumanoidRootPart")
				head.CFrame = CFrame.lookAt(origin, aim.Position)
				WeaponService.BroadcastShot(player:GetAttribute("Mode"), nil, origin, aim.Position, "SMG", nil, "Character")
				abilityDamage(player, target, ability.Damage, "Geschützturm")
			end
			task.wait(ability.FireDelay)
		end
	end)
end

local function useAbility(player)
	-- Nur wenn der Modus Kampf erlaubt (nicht im Hub, nicht zwischen Runden); offene Welt: nur passive Fähigkeiten
	if not player:GetAttribute("CanFight") or Modes.IsSurvival(player:GetAttribute("Mode")) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or character:GetAttribute("Downed") then
		return
	end

	local now = serverNow()
	if now < (player:GetAttribute("AbilityReadyAt") or 0) then
		return -- noch Abklingzeit
	end
	local agent = AgentConfig.Get(character:GetAttribute("Agent")) or getAgent(player)
	local cooldown = agent.Ability.Cooldown * (agent.Passive and agent.Passive.Type == "Cooldown" and 0.8 or 1) -- Passiv VOLT
	player:SetAttribute("AbilityReadyAt", now + cooldown)
	player:SetAttribute("AbilityActiveUntil", now + agent.Ability.Duration)

	local abilityType = agent.Ability.Type
	if abilityType == "Boost" then
		doBoost(character, root, agent)
	elseif abilityType == "Wall" then
		doWall(character, root, agent)
	elseif abilityType == "Heal" then
		doHeal(humanoid, root, agent)
	elseif abilityType == "Reveal" then
		doReveal(player, root, agent)
	elseif abilityType == "Cloak" then
		doCloak(character, agent)
	elseif abilityType == "Dash" then
		-- Der eigene Client bewegt den Charakter (er steuert dessen Physik)
		Remotes.AbilityEffect:FireClient(player, "Dash", agent.Ability.Speed, agent.Ability.Duration)
		sparkle(root, agent.Color, 0.5)
	elseif abilityType == "TeamHeal" then
		doTeamHeal(player, root, agent)
	elseif abilityType == "Trap" then
		doTrap(player, character, root, agent)
	elseif abilityType == "Turret" then
		doTurret(player, character, root, agent)
	end
end

-- Ultimate "Überladung": volles Leben, Rüstung, Fähigkeit sofort bereit, +1 Gadget-Ladung.
-- Geht nur mit voller Ladung (UltCharge = 100), im Kampf, lebend und nicht am Boden.
local function useUltimate(player)
	if not player:GetAttribute("CanFight") or (player:GetAttribute("UltCharge") or 0) < 100
		or Modes.IsSurvival(player:GetAttribute("Mode")) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or character:GetAttribute("Downed") then
		return
	end
	local ult = AgentConfig.Ultimate
	player:SetAttribute("UltCharge", 0)
	humanoid.Health = humanoid.MaxHealth
	character:SetAttribute("Armor", math.max(character:GetAttribute("Armor") or 0, ult.Armor))
	player:SetAttribute("AbilityReadyAt", serverNow())
	player:SetAttribute("Gadgets", (player:GetAttribute("Gadgets") or 0) + 1)
	local agent = AgentConfig.Get(character:GetAttribute("Agent")) or getAgent(player)
	sparkle(root, agent.Color, 2.5)
	Remotes.Notify:FireClient(player, "Medal", { { Id = "Ultimate", Title = ult.Name,
		Sub = "Volles Leben  ·  +" .. ult.Armor .. " Rüstung  ·  Fähigkeit bereit" } })
end

local function setupPlayer(player)
	player:SetAttribute("Agent", AgentConfig.Agents[1].Id)
	player:SetAttribute("UltCharge", 0)
	-- Neuer Modus (oder zurück im Hub): Ultimate beginnt wieder bei 0
	player:GetAttributeChangedSignal("Mode"):Connect(function()
		player:SetAttribute("UltCharge", 0)
	end)

	player.CharacterAdded:Connect(function(character)
		AgentBody.Protect(character) -- Accessoires sind nie Trefferzone, auch nicht kurz nach dem Spawn
		-- Tauscht Roblox beim Laden des Aussehens noch Körperteile aus, die Ausrüstung neu anlegen
		character.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") and AgentBody.GearAnchors[child.Name] then
				task.defer(function()
					applyUniform(player, character, getAgent(player))
				end)
			end
		end)
		-- Standard-Namen ausblenden (würden Gegner durch Wände verraten); eigene Namensschilder im Client
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		AgentConfig.SlimBody(humanoid) -- schlanker Körperbau wie alle Charaktere
		applyAgent(player, character)
		applyUniform(player, character, getAgent(player))
	end)
	-- Kleidung (und Skalierung) wird manchmal erst nach dem Spawn geladen: dann nochmal
	player.CharacterAppearanceLoaded:Connect(function(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			AgentConfig.SlimBody(humanoid)
		end
		applyUniform(player, character, getAgent(player))
	end)
	-- Im Hub und im Markt sieht man einen Agenten- oder Skin-Wechsel sofort (im Match erst beim nächsten Spawn)
	local function redress()
		local character = player.Character
		if character and Modes.IsSocial(player:GetAttribute("Mode")) then
			applyUniform(player, character, getAgent(player))
		end
	end
	player:GetAttributeChangedSignal("Agent"):Connect(redress)
	player:GetAttributeChangedSignal("Equipped"):Connect(redress)
	if player.Character then
		task.spawn(applyAgent, player, player.Character)
	end
end

function AgentService.Init()
	-- Agent wählen (gilt ab dem nächsten Spawn). lock = true: Wahl bestätigen (Drop-Agentenwahl).
	-- Bestätigte Wahl kann erst in der nächsten Agentenwahl geändert werden.
	Remotes.SelectAgent.OnServerEvent:Connect(function(player, id, lock)
		if player:GetAttribute("AgentLocked") then
			return
		end
		if typeof(id) == "string" and AgentConfig.Get(id) and AgentConfig.IsUnlocked(player, id) then
			player:SetAttribute("Agent", id)
			if lock == true then
				player:SetAttribute("AgentLocked", true)
			end
		end
	end)
	Remotes.UseAbility.OnServerEvent:Connect(useAbility)
	Remotes.UseUltimate.OnServerEvent:Connect(useUltimate)

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	-- Ultimate lädt langsam von selbst, solange man im Kampf lebt
	task.spawn(function()
		local perSecond = AgentConfig.Ultimate.ChargePerSecond
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				local charge = player:GetAttribute("UltCharge") or 0
				if player:GetAttribute("CanFight") and humanoid and humanoid.Health > 0 and charge < 100 then
					player:SetAttribute("UltCharge", math.min(100, charge + perSecond))
				end
			end
		end
	end)
end

return AgentService

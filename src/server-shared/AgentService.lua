-- AgentService (ModuleScript, nur Server)
-- Agentenwahl, Leben pro Agent und Fähigkeiten. Alles wird auf dem Server geprüft.
-- Spieler-Attribute: Agent (Id), AbilityReadyAt (Serverzeit), AbilityActiveUntil (Serverzeit)
-- Charakter-Attribute: Agent (aktiver Agent dieses Lebens), SpeedMultiplier (Tempo-Faktor)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local Cosmetics = require(Shared.Cosmetics)
local Modes = require(Shared.Modes)
local BuyConfig = require(Shared.BuyConfig)

local AgentService = {}

local function serverNow()
	return workspace:GetServerTimeNow()
end

local function getAgent(player)
	return AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
end

-- Uniform in Agentenfarben (bzw. Skin): Kleidung weg, Körperfarben, leuchtendes Visier
local function applyUniform(player, character, agent)
	if not Modes.IsFighting(player) or not character.Parent then
		return
	end
	local primary, accent = Cosmetics.AgentColors(player, agent.Id)
	for _, obj in character:GetChildren() do
		if obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") then
			obj:Destroy()
		end
	end
	local colors = character:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
	colors.TorsoColor3 = primary
	colors.LeftArmColor3 = primary
	colors.RightArmColor3 = primary
	colors.LeftLegColor3 = primary:Lerp(Color3.new(0, 0, 0), 0.5)
	colors.RightLegColor3 = primary:Lerp(Color3.new(0, 0, 0), 0.5)
	colors.Parent = character

	local head = character:FindFirstChild("Head")
	if head and not character:FindFirstChild("AgentVisor") then
		local visor = Instance.new("Part")
		visor.Name = "AgentVisor"
		visor.Size = Vector3.new(head.Size.X * 0.85, head.Size.Y * 0.18, 0.12)
		visor.Color = accent
		visor.Material = Enum.Material.Neon
		visor.CanCollide = false
		visor.CanQuery = false
		visor.CanTouch = false
		visor.Massless = true
		visor.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * 0.08, -head.Size.Z / 2 - 0.03)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = visor
		weld.Parent = visor
		visor.Parent = character
	end
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

local function useAbility(player)
	-- Nur wenn der Modus Kampf erlaubt (nicht im Hub, nicht zwischen Runden)
	if not player:GetAttribute("CanFight") then
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
	player:SetAttribute("AbilityReadyAt", now + agent.Ability.Cooldown)
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
	end
end

local function setupPlayer(player)
	player:SetAttribute("Agent", AgentConfig.Agents[1].Id)

	player.CharacterAdded:Connect(function(character)
		applyAgent(player, character)
		applyUniform(player, character, getAgent(player))
	end)
	-- Kleidung wird manchmal erst nach dem Spawn geladen: dann nochmal
	player.CharacterAppearanceLoaded:Connect(function(character)
		applyUniform(player, character, getAgent(player))
	end)
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

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

return AgentService

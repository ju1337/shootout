-- GadgetService (ModuleScript, nur Server)
-- Gadgets der Agenten (Taste G), geworfen als kleine Kugel mit Flugbahn:
--   Frag   – explodiert nach kurzer Zeit, Schaden im Umkreis (weniger am Rand)
--   Flash  – blendet Gegner, die hinschauen (stärker, je direkter sie schauen)
--   Smoke  – Rauchwolke als Sichtschutz (blockiert auch die Sicht der Bots)
--   Sensor – bleibt liegen und markiert vorbeilaufende Gegner für das eigene Team
-- Ladungen pro Leben im Spieler-Attribut "Gadgets" (Agent + gekauftes Extra-Gadget).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local BuyConfig = require(Shared.BuyConfig)
local Modes = require(Shared.Modes)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local Damage = require(ServerShared.Damage)
local WeaponService = require(ServerShared.WeaponService)
local KillService = require(ServerShared.KillService)
local ProgressService = require(ServerShared.ProgressService)

local GadgetService = {}

local THROW_SPEED = 70
local THROW_UP = 18
local COOLDOWN = 1
local SENSOR_REPEAT = 3 -- derselbe Gegner wird höchstens alle 3 s erneut markiert
local COLORS = {
	Frag = Color3.fromRGB(70, 90, 60),
	Flash = Color3.fromRGB(220, 220, 230),
	Smoke = Color3.fromRGB(120, 120, 130),
	Sensor = Color3.fromRGB(240, 200, 80),
}

local folder = Instance.new("Folder")
folder.Name = "Gadgets"
folder.Parent = workspace

local smokes = {}     -- { Position, Radius, Until }
local lastThrow = {}  -- [Player] = os.clock()

-- ---------- Besitzer (Spieler oder Bot) ----------
-- owner = { Player = Player } oder { Bot = bot }

local function ownerMode(owner)
	return owner.Player and owner.Player:GetAttribute("Mode") or owner.Bot.Mode
end

local function ownerTeam(owner)
	if owner.Player then
		return owner.Player.Team and owner.Player.Team.Name or nil
	end
	return owner.Bot.Team and owner.Bot.Team.Name or nil
end

local function ownerModel(owner)
	return owner.Player and owner.Player.Character or owner.Bot.Model
end

local function livingHumanoid(model)
	local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Alle lebenden Gegner des Besitzers (Spieler-Charaktere und Bot-Modelle) im selben Modus
local function enemies(owner)
	local mode, team, own = ownerMode(owner), ownerTeam(owner), ownerModel(owner)
	local list = {}
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if character ~= own and livingHumanoid(character) and p:GetAttribute("Mode") == mode
			and not (team and p.Team and p.Team.Name == team) then
			table.insert(list, character)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, model in bots:GetChildren() do
			if model ~= own and livingHumanoid(model) and model:GetAttribute("Mode") == mode
				and not (team and model:GetAttribute("TeamName") == team) then
				table.insert(list, model)
			end
		end
	end
	return list
end

-- Freie Sicht von position zum Ziel (Wände blockieren)?
local function lineOfSight(position, model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, workspace:FindFirstChild("Bots") or folder }
	for _, p in Players:GetPlayers() do
		if p.Character and p.Character ~= model then
			params:AddToFilter(p.Character)
		end
	end
	local result = workspace:Raycast(position, root.Position - position, params)
	return result == nil or result.Instance:IsDescendantOf(model)
end

-- Blockiert eine Rauchwolke die Sicht zwischen a und b? (für Bots)
function GadgetService.BlocksSight(a, b)
	local now = os.clock()
	for i = #smokes, 1, -1 do
		local smoke = smokes[i]
		if now > smoke.Until then
			table.remove(smokes, i)
		else
			-- Abstand Mittelpunkt -> Strecke a-b
			local ab = b - a
			local t = math.clamp((smoke.Position - a):Dot(ab) / ab:Dot(ab), 0, 1)
			if (a + ab * t - smoke.Position).Magnitude < smoke.Radius then
				return true
			end
		end
	end
	return false
end

-- ---------- Wirkungen ----------

local function explodeFrag(owner, position, gadget)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = gadget.Radius
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace

	local origin = position + Vector3.new(0, 1, 0)
	for _, model in enemies(owner) do
		local root = model:FindFirstChild("HumanoidRootPart")
		local distance = root and (root.Position - position).Magnitude or math.huge
		if distance <= gadget.Radius and lineOfSight(origin, model) then
			local humanoid = livingHumanoid(model)
			local amount = gadget.Damage * (1 - distance / gadget.Radius * 0.6)
			local victim = Players:GetPlayerFromCharacter(model)
			local victimName = victim and victim.Name or model.Name
			local dealt, killed, downed = Damage.Apply(model, humanoid, amount,
				{ Player = owner.Player, BotName = owner.Bot and owner.Bot.Name, Model = owner.Bot and owner.Bot.Model,
					Weapon = "Granate" })
			if owner.Player then
				owner.Player:SetAttribute("Damage", (owner.Player:GetAttribute("Damage") or 0) + math.floor(dealt + 0.5))
				Remotes.Hitmarker:FireClient(owner.Player, false, killed, dealt, root.Position, victimName, downed)
				if killed then
					WeaponService.ReportKill(owner.Player, victim, "Granate", false, victimName)
				end
			elseif killed then
				KillService.ReportBotKill(owner.Bot.Mode, owner.Bot.Name, victimName, "Granate", false)
			end
		end
	end
end

local function explodeFlash(owner, position, gadget)
	-- Kurzer heller Lichtblitz für alle
	local flashPart = Instance.new("Part")
	flashPart.Anchored = true
	flashPart.CanCollide = false
	flashPart.CanQuery = false
	flashPart.Transparency = 1
	flashPart.Position = position
	flashPart.Parent = folder
	local light = Instance.new("PointLight")
	light.Brightness = 40
	light.Range = gadget.Radius
	light.Parent = flashPart
	Debris:AddItem(flashPart, 0.2)

	for _, model in enemies(owner) do
		local head = model:FindFirstChild("Head")
		local distance = head and (head.Position - position).Magnitude or math.huge
		if distance <= gadget.Radius and lineOfSight(position + Vector3.new(0, 0.5, 0), model) then
			-- Wer direkt hinschaut, ist länger geblendet
			local facing = (position - head.Position).Unit:Dot(head.CFrame.LookVector)
			local strength = (facing > 0.3 and 1 or 0.4) * (1 - distance / gadget.Radius * 0.5)
			local duration = gadget.Duration * strength
			local victim = Players:GetPlayerFromCharacter(model)
			if victim then
				Remotes.Flash:FireClient(victim, duration)
			else
				model:SetAttribute("BlindedUntil", os.clock() + duration)
			end
		end
	end
end

local function explodeSmoke(position, gadget)
	local cloud = Instance.new("Model")
	cloud.Name = "Smoke"
	for i = 1, 7 do
		local puff = Instance.new("Part")
		puff.Shape = Enum.PartType.Ball
		puff.Anchored = true
		puff.CanCollide = false
		puff.CanQuery = false
		puff.CanTouch = false
		puff.CastShadow = false
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = Color3.fromRGB(200, 200, 205)
		puff.Transparency = 0.15
		puff.Size = Vector3.new(1, 1, 1)
		local offset = i == 1 and Vector3.zero
			or Vector3.new(math.random(-10, 10), math.random(0, 6), math.random(-10, 10)) / 10 * gadget.Radius * 0.5
		puff.Position = position + offset + Vector3.new(0, gadget.Radius * 0.3, 0)
		puff.Parent = cloud
		local size = gadget.Radius * (i == 1 and 1.5 or 1.1)
		TweenService:Create(puff, TweenInfo.new(1.2), { Size = Vector3.new(size, size, size) }):Play()
		-- Am Ende auflösen
		task.delay(gadget.Duration - 1.5, function()
			if puff.Parent then
				TweenService:Create(puff, TweenInfo.new(1.5), { Transparency = 1 }):Play()
			end
		end)
	end
	cloud.Parent = folder
	Debris:AddItem(cloud, gadget.Duration)
	table.insert(smokes, { Position = position + Vector3.new(0, gadget.Radius * 0.3, 0), Radius = gadget.Radius * 0.8,
		Until = os.clock() + gadget.Duration })
end

local function activateSensor(owner, part, gadget)
	part.Anchored = true
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 60, 60)
	local seen = {}
	local endAt = os.clock() + gadget.Duration
	task.spawn(function()
		while part.Parent and os.clock() < endAt do
			for _, model in enemies(owner) do
				local root = model:FindFirstChild("HumanoidRootPart")
				local now = os.clock()
				if root and (root.Position - part.Position).Magnitude <= gadget.Radius
					and not AgentConfig.PassiveOf(model, "SensorImmune") -- Passiv GHOST
					and (not seen[model] or now - seen[model] > SENSOR_REPEAT) then
					seen[model] = now
					-- Markierung an Besitzer und Team (wie Radar-Puls)
					local mode, team = ownerMode(owner), ownerTeam(owner)
					for _, mate in Players:GetPlayers() do
						if mate == owner.Player or (team and mate.Team and mate.Team.Name == team and mate:GetAttribute("Mode") == mode) then
							Remotes.Reveal:FireClient(mate, { model }, 3)
						end
					end
				end
			end
			part.Transparency = part.Transparency == 0 and 0.6 or 0 -- blinken
			task.wait(0.25)
		end
		if part.Parent then
			part:Destroy()
		end
	end)
end

-- ---------- Werfen ----------

local function throw(owner, origin, direction, gadget)
	local part = Instance.new("Part")
	part.Name = gadget.Type
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.9, 0.9, 0.9)
	part.Color = COLORS[gadget.Type]
	part.Material = Enum.Material.Metal
	part.CanQuery = false
	part.Position = origin + direction * 2.5
	part.Parent = folder
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	part.AssemblyLinearVelocity = direction * THROW_SPEED + Vector3.new(0, THROW_UP, 0)

	if gadget.Type == "Sensor" then
		-- Bleibt am ersten Hindernis kleben (spätestens nach 3 s)
		local activated = false
		local function activate()
			if not activated and part.Parent then
				activated = true
				activateSensor(owner, part, gadget)
			end
		end
		part.Touched:Connect(function(hit)
			if not hit:FindFirstAncestorOfClass("Model") or not hit:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") then
				activate()
			end
		end)
		task.delay(3, activate)
		return
	end

	task.delay(gadget.Fuse, function()
		if not part.Parent then
			return
		end
		local position = part.Position
		part:Destroy()
		if gadget.Type == "Frag" then
			explodeFrag(owner, position, gadget)
		elseif gadget.Type == "Flash" then
			explodeFlash(owner, position, gadget)
		elseif gadget.Type == "Smoke" then
			explodeSmoke(position, gadget)
		end
	end)
end

-- Spieler wirft (G gedrückt)
local function onUseGadget(player, direction)
	if typeof(direction) ~= "Vector3" or not (direction.Magnitude > 0.01) then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not livingHumanoid(character) or character:GetAttribute("Downed") or not player:GetAttribute("CanFight") then
		return
	end
	local charges = player:GetAttribute("Gadgets") or 0
	local now = os.clock()
	if charges <= 0 or (lastThrow[player] and now - lastThrow[player] < COOLDOWN) then
		return
	end
	local agent = AgentConfig.Get(character:GetAttribute("Agent")) or AgentConfig.Agents[1]
	lastThrow[player] = now
	player:SetAttribute("Gadgets", charges - 1)
	throw({ Player = player }, head.Position, direction.Unit, agent.Gadget)
	ProgressService.QuestEvent(player, "Gadget", 1)
end

-- Bot wirft (von BotService)
function GadgetService.BotThrow(bot, direction)
	local head = bot.Model and bot.Model:FindFirstChild("Head")
	if not head or (bot.GadgetCharges or 0) <= 0 then
		return
	end
	bot.GadgetCharges -= 1
	local agent = AgentConfig.Get(bot.Agent) or AgentConfig.Agents[1]
	throw({ Bot = bot }, head.Position, direction.Unit, agent.Gadget)
end

function GadgetService.Init()
	Remotes.UseGadget.OnServerEvent:Connect(onUseGadget)

	-- Ladungen pro Leben: Agent + gekauftes Extra-Gadget (nur in Kampfmodi)
	local function onPlayer(player)
		player.CharacterAdded:Connect(function()
			if Modes.IsFighting(player) then
				local agent = AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
				local passiveBonus = agent.Passive and agent.Passive.Type == "ExtraGadget" and 1 or 0 -- Passiv TRAPPER
				player:SetAttribute("Gadgets", agent.Gadget.Charges + (BuyConfig.Has(player, "ExtraGadget") and 1 or 0) + passiveBonus)
			else
				player:SetAttribute("Gadgets", 0)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastThrow[player] = nil
	end)
end

return GadgetService

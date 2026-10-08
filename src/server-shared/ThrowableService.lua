-- ThrowableService (ModuleScript, nur Server)
-- Wurfwaffen der offenen Welt (Items mit Kind "Throwable", Werte in ExtinctionConfig.Throwables):
--   Frag     Granate: fliegt im Bogen, explodiert nach Fuse Sekunden, Schaden im Umkreis (Wände schützen)
--   Molotov  Molotow: zerplatzt beim Aufprall zu einem Feuer, das eine Weile brennt und alle Tick Sekunden Schaden macht
-- Werfen: Hotbar-Taste (Aktion "Throw" mit Blickrichtung, InventoryService.UseThrowable) – nicht in der Safe Zone und nicht
-- im Fahrzeug. Getroffen werden Zombies, Bots (Konvoi-Wachen), Fahrzeuge, der Konvoi und Spieler nach den PvP-Regeln
-- (beide PvP-Zeit, nie der eigene Squad); der Werfer selbst nicht.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DayCycle = require(Shared.DayCycle)
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Modes = require(Shared.Modes)
local Damage = require(script.Parent.Damage)
local WeaponService = require(script.Parent.WeaponService)
local InventoryService = require(script.Parent.InventoryService)

local ThrowableService = {}

local folder = workspace:FindFirstChild("Throwables") or Instance.new("Folder")
folder.Name = "Throwables"
folder.Parent = workspace

local lastThrow = {} -- [Player] = os.clock()
local fires = {} -- { Position, Radius, Until } (für Tests und andere Dienste)

local function living(model)
	local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Darf thrower diesem Modell schaden? (Spieler: PvP-Regeln der offenen Welt)
local function canHurt(thrower, model)
	if model == thrower.Character then
		return false
	end
	local victim = Players:GetPlayerFromCharacter(model)
	if not victim then
		return model:GetAttribute("IsZombie") == true or model:GetAttribute("IsBot") == true
	end
	if not Modes.IsSurvival(victim:GetAttribute("Mode")) then
		return false
	end
	local squad = thrower:GetAttribute("SquadId")
	if squad ~= nil and squad == victim:GetAttribute("SquadId") then
		return false
	end
	if DayCycle.StormPvPPaused(workspace:GetServerTimeNow()) then
		return false -- Sturmnacht: PvP ausgesetzt
	end
	return thrower:GetAttribute("PvP") == true and victim:GetAttribute("PvP") == true
end

-- Alle Lebewesen, die getroffen werden können (Spieler, Bots, Zombies)
local function targets(thrower)
	local list = {}
	for _, other in Players:GetPlayers() do
		if other.Character and living(other.Character) and canHurt(thrower, other.Character) then
			table.insert(list, other.Character)
		end
	end
	for _, name in { "Bots", "Zombies" } do
		local holder = workspace:FindFirstChild(name)
		for _, model in holder and holder:GetChildren() or {} do
			if model:IsA("Model") and living(model) and canHurt(thrower, model) then
				table.insert(list, model)
			end
		end
	end
	return list
end

-- Freie Sicht vom Explosionspunkt zum Ziel (Wände schützen)
local function clear(position, model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	for _, name in { "Bots", "Zombies", "ExtinctionVehicles", "ExtinctionConvoy", "ExtinctionLoot" } do
		local holder = workspace:FindFirstChild(name)
		if holder then
			table.insert(ignore, holder)
		end
	end
	params.FilterDescendantsInstances = ignore
	return workspace:Raycast(position, root.Position - position, params) == nil
end

-- Schaden an einem Lebewesen, mit Trefferanzeige und Kill-Meldung wie bei Schüssen
local function hurt(thrower, model, amount, weaponName)
	local humanoid = living(model)
	if not humanoid or amount <= 0 then
		return
	end
	local victim = Players:GetPlayerFromCharacter(model)
	local victimName = victim and victim.Name or model.Name
	local dealt, killed, downed, armor = Damage.Apply(model, humanoid, amount,
		{ Player = thrower, Model = thrower.Character, Weapon = weaponName })
	if dealt > 0 then
		local root = model:FindFirstChild("HumanoidRootPart")
		Remotes.Hitmarker:FireClient(thrower, false, killed, dealt, root and root.Position or Vector3.zero, victimName, downed, armor, model)
	end
	if killed and (victim or model:GetAttribute("IsBot") == true) then
		WeaponService.ReportKill(thrower, victim, weaponName, false, victimName, model)
	end
end

-- Fahrzeuge und Konvoi im Umkreis
local function hurtVehicles(thrower, position, radius, amount)
	for _, name in { "ExtinctionVehicles", "ExtinctionConvoy" } do
		local holder = workspace:FindFirstChild(name)
		for _, model in holder and holder:GetChildren() or {} do
			if model:IsA("Model") and (model:GetPivot().Position - position).Magnitude <= radius + 4 then
				if model:GetAttribute("Convoy") and WeaponService.OnConvoyHit then
					WeaponService.OnConvoyHit(thrower, model, amount)
				elseif model:GetAttribute("VehicleId") and WeaponService.OnVehicleHit then
					WeaponService.OnVehicleHit(thrower, model, amount)
				end
			end
		end
	end
end

-- ---------- Granate ----------

local function explode(thrower, position, cfg)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = cfg.Radius
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = workspace
	local origin = position + Vector3.new(0, 1, 0)
	for _, model in targets(thrower) do
		local root = model:FindFirstChild("HumanoidRootPart")
		local distance = root and (root.Position - position).Magnitude or math.huge
		if distance <= cfg.Radius and clear(origin, model) then
			hurt(thrower, model, cfg.Damage * (1 - distance / cfg.Radius * (1 - cfg.EdgeFactor)), "Granate")
		end
	end
	hurtVehicles(thrower, position, cfg.Radius, cfg.Damage * cfg.VehicleFactor)
end

-- ---------- Molotow ----------

local function ignite(thrower, position, cfg)
	-- Boden unter dem Aufprall
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local down = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -30, 0), params)
	local ground = down and down.Position or position
	local area = Instance.new("Part")
	area.Name = "MolotovFire"
	area.Anchored = true
	area.CanCollide = false
	area.CanQuery = false
	area.CanTouch = false
	area.Shape = Enum.PartType.Cylinder
	area.Size = Vector3.new(0.3, cfg.Radius * 2, cfg.Radius * 2)
	area.CFrame = CFrame.new(ground + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	area.Color = Color3.fromRGB(255, 120, 30)
	area.Material = Enum.Material.Neon
	area.Transparency = 0.55
	area.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = cfg.Radius * 2
	light.Brightness = 2
	light.Parent = area
	-- Flammen verteilt über die Fläche
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		local spot = Instance.new("Attachment")
		spot.Position = Vector3.new(0, math.cos(angle) * cfg.Radius * 0.55, math.sin(angle) * cfg.Radius * 0.55)
		spot.Parent = area
		local flame = Instance.new("Fire")
		flame.Size = 6
		flame.Heat = 9
		flame.Parent = spot
	end
	local center = Instance.new("Fire")
	center.Size = 9
	center.Heat = 12
	center.Parent = area
	Debris:AddItem(area, cfg.Duration + 0.5)
	local burn = { Position = ground, Radius = cfg.Radius, Until = os.clock() + cfg.Duration }
	table.insert(fires, burn)
	task.spawn(function()
		local ends = os.clock() + cfg.Duration
		while os.clock() < ends and area.Parent do
			for _, model in targets(thrower) do
				local root = model:FindFirstChild("HumanoidRootPart")
				if root then
					local offset = root.Position - ground
					if Vector2.new(offset.X, offset.Z).Magnitude <= cfg.Radius and math.abs(offset.Y) <= 7 then
						local factor = model:GetAttribute("IsZombie") and cfg.ZombieFactor or 1
						hurt(thrower, model, cfg.TickDamage * factor, "Molotow")
					end
				end
			end
			hurtVehicles(thrower, ground, cfg.Radius, cfg.TickDamage * cfg.VehicleFactor)
			task.wait(cfg.Tick)
		end
		local index = table.find(fires, burn)
		if index then
			table.remove(fires, index)
		end
	end)
end

-- Brennende Feuer (Position, Radius, Until)
function ThrowableService.Fires()
	return fires
end

-- ---------- Werfen ----------

local function launch(thrower, kind, origin, direction, cfg)
	local part = Instance.new("Part")
	part.Name = kind
	part.CanQuery = false
	if kind == "Molotov" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(1.1, 0.5, 0.5)
		part.Color = Color3.fromRGB(110, 140, 70)
		part.Material = Enum.Material.Glass
		part.Transparency = 0.2
		local flame = Instance.new("Fire")
		flame.Size = 1.5
		flame.Heat = 2
		flame.Parent = part
	else
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(0.8, 0.8, 0.8)
		part.Color = Color3.fromRGB(64, 80, 54)
		part.Material = Enum.Material.Metal
	end
	part.Position = origin + direction * 2.5
	part.Parent = folder
	pcall(function()
		part:SetNetworkOwner(nil)
	end)
	part.AssemblyLinearVelocity = direction * cfg.Speed + Vector3.new(0, cfg.Up, 0)
	part.AssemblyAngularVelocity = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5)

	if kind == "Molotov" then
		local done = false
		local function burst()
			if done or not part.Parent then
				return
			end
			done = true
			local position = part.Position
			part:Destroy()
			ignite(thrower, position, cfg)
		end
		part.Touched:Connect(function(hit)
			if thrower.Character and hit:IsDescendantOf(thrower.Character) or hit:IsDescendantOf(folder) then
				return
			end
			burst()
		end)
		task.delay(cfg.Fuse, burst)
	else
		task.delay(cfg.Fuse, function()
			if part.Parent then
				local position = part.Position
				part:Destroy()
				explode(thrower, position, cfg)
			end
		end)
	end
	return part
end

-- Item auf Platz slot werfen (direction = Blickrichtung des Clients, nil = Blickrichtung des Charakters).
-- Gibt true zurück, wenn geworfen.
function ThrowableService.Throw(player, slot, item, direction)
	local config = item and ExtinctionConfig.Get(item.Id)
	local cfg = config and config.Kind == "Throwable" and ExtinctionConfig.Throwables[config.Throwable]
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and living(character)
	if not cfg or not head or not humanoid then
		return false
	end
	if player:GetAttribute("InSafeZone") then
		InventoryService.Status(player, "In der Safe Zone wird nichts geworfen.")
		return false
	end
	if humanoid.SeatPart then
		InventoryService.Status(player, "Aus dem Fahrzeug kannst du nicht werfen.")
		return false
	end
	local now = os.clock()
	if lastThrow[player] and now - lastThrow[player] < cfg.Cooldown then
		return false
	end
	if typeof(direction) ~= "Vector3" or direction ~= direction or not (direction.Magnitude > 0.01) or direction.Magnitude > 10 then
		local root = character:FindFirstChild("HumanoidRootPart")
		direction = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
	end
	local taken = InventoryService.TakeSlot(player, slot, 1)
	if not taken then
		return false
	end
	lastThrow[player] = now
	launch(player, config.Throwable, head.Position, direction.Unit, cfg)
	return true
end

function ThrowableService.Init()
	InventoryService.UseThrowable = ThrowableService.Throw
	Players.PlayerRemoving:Connect(function(player)
		lastThrow[player] = nil
	end)
end

return ThrowableService

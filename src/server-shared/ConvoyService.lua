-- ConvoyService (ModuleScript, nur Server)
-- Konvoi der offenen Welt (EXTINCTION), Werte in ExtinctionConfig.Convoy: Ein bewaffneter Konvoi (Begleitfahrzeug, Lkw,
-- Begleitfahrzeug) fährt eine Landstraße entlang.
--   1. Warten (Warning Sekunden) am Start: Ansage an alle, Markierung auf der Karte.
--   2. Fahren: alle Fahrzeuge folgen der Strecke (verankert, Höhe vom Boden), die Begleitfahrzeuge schießen auf Spieler in
--      der Nähe. Schüsse auf ein Fahrzeug (WeaponService.OnVehicleHit) kosten den Konvoi Leben.
--   3. Angehalten (Leben unter HaltAt): Wachen steigen aus (Bots über options.SpawnGuard), Ansage.
--   4. Ladung frei (alle Wachen tot oder GuardTimeout): Kiste mit bester Beute am Lkw, Münzen für alle Angreifer.
--   Ende der Strecke ohne Halt: entkommen. Danach Wartezeit bis zum nächsten Konvoi.
-- Stand für die Clients: Karten-Attribut "Convoys" = [{ Id, X, Z, State, Route }] (State: Waiting, Driving, Halted, Loot).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local LootService = require(script.Parent.LootService)
local ZombieService = require(script.Parent.ZombieService)
local WeaponService = require(script.Parent.WeaponService)
local Damage = require(script.Parent.Damage)

local ConvoyService = {}

local K = ExtinctionConfig.Convoy
local random = Random.new()
-- options = { Map, Center, Players() -> { Player }, InSafeZone(position), SpawnGuard(cframe, weaponItemId) -> Bot,
--             GuardAlive(bot) -> bool, RemoveGuard(bot), Reward(player, coins, text) }
local options = nil
local current = nil -- laufender Konvoi oder nil
local nextAt = 0
local nextId = 0
local folder = workspace:FindFirstChild("ExtinctionConvoy") or Instance.new("Folder")
folder.Name = "ExtinctionConvoy"
folder.Parent = workspace

-- ---------- Aussehen ----------

local function part(model, name, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.CFrame = offset
	p.Parent = model
	return p
end

-- Fahrzeug (Front lokal -Z): kind "Truck" (Lkw mit Plane) oder "Escort" (Geländewagen mit MG auf der Ladefläche)
local function buildVehicle(kind)
	local model = Instance.new("Model")
	model.Name = kind == "Truck" and "ConvoyTruck" or "ConvoyEscort"
	local paint = Color3.fromRGB(70, 78, 58)
	local dark = Color3.fromRGB(34, 34, 36)
	local body
	if kind == "Truck" then
		body = part(model, "Body", Vector3.new(7.4, 3, 22), CFrame.new(0, 3, 0), paint)
		part(model, "Cab", Vector3.new(7.2, 4.6, 6), CFrame.new(0, 6.6, -7.6), paint)
		part(model, "Glass", Vector3.new(6.6, 2, 0.3), CFrame.new(0, 7.6, -10.7), Color3.fromRGB(40, 52, 60), Enum.Material.Glass)
		part(model, "Tarp", Vector3.new(7.6, 6, 14.6), CFrame.new(0, 7.6, 3.4), Color3.fromRGB(88, 96, 70), Enum.Material.Fabric)
		for _, z in { -7, 3, 8 } do
			for _, x in { -3.6, 3.6 } do
				part(model, "Wheel", Vector3.new(1.2, 3, 3), CFrame.new(x, 1.5, z), dark, Enum.Material.Rubber)
			end
		end
	else
		body = part(model, "Body", Vector3.new(6.4, 2.6, 12), CFrame.new(0, 2.4, 0), paint)
		part(model, "Cab", Vector3.new(6, 2.4, 5), CFrame.new(0, 4.9, -1.6), paint)
		part(model, "Glass", Vector3.new(5.6, 1.6, 0.3), CFrame.new(0, 5.1, -4.2), Color3.fromRGB(40, 52, 60), Enum.Material.Glass)
		part(model, "GunMount", Vector3.new(1, 2.4, 1), CFrame.new(0, 4.9, 3.6), dark)
		part(model, "Gun", Vector3.new(0.5, 0.5, 4), CFrame.new(0, 6.3, 2.2), dark)
		for _, z in { -3.8, 3.8 } do
			for _, x in { -3.2, 3.2 } do
				part(model, "Wheel", Vector3.new(1, 2.6, 2.6), CFrame.new(x, 1.3, z), dark, Enum.Material.Rubber)
			end
		end
	end
	model.PrimaryPart = body
	-- Treffer landen über WeaponService.OnVehicleHit hier (VehicleId wie bei Spieler-Fahrzeugen)
	model:SetAttribute("VehicleId", "Convoy")
	model:SetAttribute("Convoy", true)
	model.Parent = folder
	return model
end

-- ---------- Strecke ----------

local function buildRoute(route)
	local points = {}
	for _, p in route.Points do
		table.insert(points, options.Center + Vector3.new(p[1], 0, p[2]))
	end
	if random:NextNumber() < 0.5 then
		local reversed = {}
		for i = #points, 1, -1 do
			table.insert(reversed, points[i])
		end
		points = reversed
	end
	local lengths = { 0 }
	for i = 2, #points do
		lengths[i] = lengths[i - 1] + (points[i] - points[i - 1]).Magnitude
	end
	return { Points = points, Lengths = lengths, Total = lengths[#lengths], Name = route.Name }
end

-- Punkt auf der Strecke nach distance Studs (flach, y = 0)
local function pointAt(path, distance)
	distance = math.clamp(distance, 0, path.Total)
	for i = 2, #path.Points do
		if path.Lengths[i] >= distance then
			local seg = path.Lengths[i] - path.Lengths[i - 1]
			local t = seg > 0 and (distance - path.Lengths[i - 1]) / seg or 0
			return path.Points[i - 1]:Lerp(path.Points[i], t)
		end
	end
	return path.Points[#path.Points]
end

local function groundY(position, fallback)
	local ground = ZombieService.GroundAt(position.X, position.Z)
	return ground and ground.Y or fallback
end

-- Fahrzeuge an ihre Stelle (Abstand Spacing hintereinander, Blick in Fahrtrichtung)
local function place(convoy)
	for index, vehicle in convoy.Vehicles do
		if vehicle.Model.Parent then
			local s = convoy.Distance - (index - 1) * K.Spacing
			local here = pointAt(convoy.Path, s)
			local ahead = pointAt(convoy.Path, s + 6)
			if (ahead - here).Magnitude < 0.1 then
				ahead = here + (vehicle.Model:GetPivot().LookVector * Vector3.new(1, 0, 1))
			end
			vehicle.Y = groundY(here, vehicle.Y or here.Y)
			local base = Vector3.new(here.X, vehicle.Y, here.Z)
			vehicle.Model:PivotTo(CFrame.lookAt(base, Vector3.new(ahead.X, vehicle.Y, ahead.Z)))
		end
	end
end

-- ---------- Ablauf ----------

local function publish()
	local list = {}
	if current and current.State ~= "Gone" then
		local lead = current.Vehicles[2] and current.Vehicles[2].Model or current.Vehicles[1].Model
		local at = lead:GetPivot().Position
		table.insert(list, { Id = current.Id, X = math.floor(at.X), Z = math.floor(at.Z), State = current.State,
			Route = current.Path.Name })
	end
	options.Map:SetAttribute("Convoys", HttpService:JSONEncode(list))
end

local function announce(title, sub)
	for _, player in options.Players() do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Konvoi", Title = title, Sub = sub, Style = "Info" })
	end
end

local function playersOutside()
	local list = {}
	for _, player in options.Players() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 and not options.InSafeZone(root.Position) then
			table.insert(list, { Player = player, Humanoid = humanoid, Root = root, Character = character })
		end
	end
	return list
end

local function cleanup(convoy)
	for _, vehicle in convoy.Vehicles do
		if vehicle.Model.Parent then
			vehicle.Model:Destroy()
		end
	end
	for _, guard in convoy.Guards do
		if options.RemoveGuard then
			options.RemoveGuard(guard)
		end
	end
	convoy.Guards = {}
end

local function finish(convoy)
	convoy.State = "Gone"
	if current == convoy then
		current = nil
	end
	nextAt = os.clock() + random:NextNumber(K.MinInterval, K.MaxInterval)
	publish()
end

-- Ladung frei: Kiste am Lkw, Münzen für alle Angreifer
local function release(convoy)
	convoy.State = "Loot"
	local truck = convoy.Vehicles[2].Model
	local at = (truck:GetPivot() * CFrame.new(0, 0, 14)).Position
	local items = ExtinctionConfig.RollLoot(K.Table, random:NextInteger(K.Items[1], K.Items[2]), random)
	convoy.LootId = LootService.Create(at, items, "Airdrop", "KONVOI-LADUNG",
		{ HoldTime = K.OpenTime, Lifetime = K.Lifetime, Meta = { Convoy = convoy.Id } })
	for player in convoy.Attackers do
		if player.Parent and options.Reward then
			options.Reward(player, K.Coins, "Konvoi geknackt")
		end
	end
	announce("KONVOI GEKNACKT", "Die Ladung liegt am Lkw · E halten zum Öffnen")
	publish()
	if not convoy.LootId then
		task.delay(10, function()
			cleanup(convoy)
			finish(convoy)
		end)
	end
end

local function halt(convoy)
	convoy.State = "Halted"
	convoy.HaltedAt = os.clock()
	for index = 1, K.Guards do
		local vehicle = convoy.Vehicles[(index - 1) % #convoy.Vehicles + 1]
		local pivot = vehicle.Model:GetPivot()
		local side = index % 2 == 0 and 7 or -7
		local spot = (pivot * CFrame.new(side, 0, random:NextNumber(-5, 5))).Position
		local y = groundY(spot, pivot.Position.Y)
		local weapon = K.GuardWeapons[(index - 1) % #K.GuardWeapons + 1]
		local guard = options.SpawnGuard and options.SpawnGuard(CFrame.new(spot.X, y + 3, spot.Z), weapon)
		if guard then
			table.insert(convoy.Guards, guard)
		end
	end
	announce("KONVOI GESTOPPT", "Wachen steigen aus · erledige sie, dann ist die Ladung frei")
	publish()
end

-- Begleitfahrzeuge schießen auf Spieler in der Nähe (nicht in Safe Zones)
local function gunners(convoy, now)
	if now < (convoy.NextShot or 0) then
		return
	end
	convoy.NextShot = now + K.GunEvery
	local targets = playersOutside()
	for _, index in { 1, 3 } do
		local vehicle = convoy.Vehicles[index]
		local gun = vehicle and vehicle.Model.Parent and vehicle.Model:FindFirstChild("Gun")
		if gun then
			local best, bestDistance = nil, K.GunRange
			for _, target in targets do
				local distance = (target.Root.Position - gun.Position).Magnitude
				if distance < bestDistance and not target.Character:GetAttribute("SafeZone") then
					best, bestDistance = target, distance
				end
			end
			if best then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { folder }
				local direction = best.Root.Position - gun.Position
				local hit = workspace:Raycast(gun.Position, direction, params)
				local clear = hit == nil or hit.Instance:IsDescendantOf(best.Character)
				local endPos = clear and best.Root.Position or (hit and hit.Position or best.Root.Position)
				WeaponService.BroadcastShot("Extinction", vehicle.Model, gun.Position, endPos, "LMG", nil, clear and "Character" or nil, false)
				if clear and random:NextNumber() < K.GunChance then
					Damage.Apply(best.Character, best.Humanoid, K.GunDamage, { Model = vehicle.Model, BotName = "KONVOI", Weapon = "LMG" })
				end
			end
		end
	end
end

local function tick(now, dt)
	local convoy = current
	if not convoy then
		if K.Enabled and now >= nextAt and #playersOutside() >= K.MinPlayers then
			ConvoyService.Start()
		end
		return
	end
	if convoy.State == "Waiting" then
		if now >= convoy.DepartAt then
			convoy.State = "Driving"
			announce("KONVOI FÄHRT LOS", "Auf der Strecke " .. convoy.Path.Name .. " · halte ihn auf")
		end
	elseif convoy.State == "Driving" then
		convoy.Distance += K.Speed * dt
		place(convoy)
		gunners(convoy, now)
		if convoy.Distance - (#convoy.Vehicles - 1) * K.Spacing >= convoy.Path.Total then
			announce("KONVOI ENTKOMMEN", "Er hat das Ende der Strecke erreicht")
			cleanup(convoy)
			finish(convoy)
			return
		end
	elseif convoy.State == "Halted" then
		local alive = 0
		for _, guard in convoy.Guards do
			if options.GuardAlive and options.GuardAlive(guard) then
				alive += 1
			end
		end
		if alive == 0 or now - convoy.HaltedAt >= K.GuardTimeout then
			release(convoy)
		end
	end
	convoy.PublishIn = (convoy.PublishIn or 0) - dt
	if convoy.PublishIn <= 0 then
		convoy.PublishIn = 1
		publish()
	end
end

-- ---------- Schnittstelle ----------

-- Konvoi starten (routeIndex optional, sonst zufällig). Gibt den Konvoi zurück (nil, wenn schon einer läuft).
function ConvoyService.Start(routeIndex)
	if current or not options or #K.Routes == 0 then
		return nil
	end
	nextId += 1
	local route = K.Routes[routeIndex or random:NextInteger(1, #K.Routes)]
	local convoy = { Id = nextId, Path = buildRoute(route), State = "Waiting", Health = K.Health, Attackers = {}, Guards = {},
		DepartAt = os.clock() + K.Warning }
	convoy.Vehicles = {
		{ Kind = "Escort", Model = buildVehicle("Escort") },
		{ Kind = "Truck", Model = buildVehicle("Truck") },
		{ Kind = "Escort", Model = buildVehicle("Escort") },
	}
	convoy.Distance = (#convoy.Vehicles - 1) * K.Spacing -- alle Fahrzeuge am Start hintereinander
	current = convoy
	place(convoy)
	publish()
	announce("KONVOI GESICHTET", convoy.Path.Name .. " · fährt in " .. K.Warning .. " Sekunden los · Markierung auf der Karte (N)")
	return convoy
end

-- Treffer auf ein Konvoi-Fahrzeug (aus WeaponService.OnVehicleHit)
function ConvoyService.Hit(player, _model, damage)
	local convoy = current
	if not convoy or (convoy.State ~= "Driving" and convoy.State ~= "Waiting") then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and options.InSafeZone(root.Position) then
		return
	end
	convoy.Attackers[player] = true
	convoy.Health = math.max(0, convoy.Health - (tonumber(damage) or 0))
	if convoy.Health <= K.Health * K.HaltAt then
		halt(convoy)
	end
end

function ConvoyService.Current()
	return current
end

-- opts siehe options oben
function ConvoyService.Init(opts)
	options = opts
	nextAt = os.clock() + K.FirstDelay
	publish()
	-- Treffer: Konvoi-Fahrzeuge hier, alle anderen wie bisher (VehicleService)
	local previous = WeaponService.OnVehicleHit
	WeaponService.OnVehicleHit = function(player, model, damage)
		if model:GetAttribute("Convoy") then
			ConvoyService.Hit(player, model, damage)
		elseif previous then
			previous(player, model, damage)
		end
	end
	LootService.OnRemoved[#LootService.OnRemoved + 1] = function(bag)
		local convoy = current
		if convoy and convoy.State == "Loot" and bag.Meta and bag.Meta.Convoy == convoy.Id then
			cleanup(convoy)
			finish(convoy)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		if current then
			current.Attackers[player] = nil
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.1 then
			local step = elapsed
			elapsed = 0
			local ok, err = pcall(tick, os.clock(), step)
			if not ok then
				warn("Konvoi: " .. tostring(err))
			end
		end
	end)
end

return ConvoyService

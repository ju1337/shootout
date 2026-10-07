-- VehicleService (ModuleScript, nur Server)
-- Fahrzeuge der offenen Welt (EXTINCTION): Ein Fahrzeug ist ein Item in der Tasche ("Vehicle", siehe
-- ExtinctionConfig.Vehicles). Taste 1-9 auf dem Platz spawnt es vor dem Spieler und setzt ihn auf den Fahrersitz;
-- K packt es wieder ein (danach VehicleCooldown Sekunden warten). Pro Spieler ist höchstens ein Fahrzeug draußen
-- (Item-Feld Out). Mitfahrer steigen per E ein (Sitze für Seats > 1), fahren darf nur der Besitzer.
-- Physik: ein unsichtbarer Rumpf ("Chassis") gleitet auf vier unsichtbaren Kugeln (ohne Reibung) über den Boden,
-- LinearVelocity (nur waagerecht, Schwerkraft bleibt) gibt das Tempo, AlignOrientation hält es gerade und dreht
-- es. Gesteuert wird auf dem Client des Fahrers (VehicleClient, er besitzt die Physik); steigt er aus, bremst der
-- Server das Fahrzeug. Ein Tempo-Check setzt zu schnelle Fahrzeuge zurück.
-- Leben: Attribute Health/MaxHealth am Modell; Schüsse treffen es (nur draußen und mit PvP, siehe OnVehicleHit),
-- bei 0 brennt es aus und das Item ist weg. Zombies, die man umfährt, nehmen Schaden.
-- Stirbt oder geht der Besitzer, verschwindet das Fahrzeug (das Item liegt dann in seiner Tasche am Boden).
-- Modelle in Workspace.ExtinctionVehicles, Attribute: VehicleId, Owner (UserId), OwnerName, Health, MaxHealth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Inventory = require(Shared.Inventory)
local Modes = require(Shared.Modes)
local InventoryService = require(script.Parent.InventoryService)
local Damage = require(script.Parent.Damage)

local VehicleService = {}

local BALL = 2.2             -- Durchmesser der Gleitkugeln
local RAM_SPEED = 22         -- ab diesem Tempo nehmen umgefahrene Zombies Schaden
local SPEED_SLACK = 1.6      -- Tempo-Check: so viel schneller als erlaubt (plus 30 Studs) gilt als Betrug
local SEAT_RANGE = 12        -- so nah muss man zum Einsteigen sein (Taste erneut drücken)

local folder = workspace:FindFirstChild("ExtinctionVehicles") or Instance.new("Folder")
folder.Name = "ExtinctionVehicles"
folder.Parent = workspace

local options = nil -- { InSafeZone(position) }
local active = {}   -- [Player] = { Model, Chassis, Seat, Item, Config, LastPos, LastTime }

local function status(player, text, ok)
	InventoryService.Status(player, text, ok)
end

local function livingCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil, nil, nil
end

-- ---------- Bauen ----------

local function weldTo(base, part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = part
	weld.Parent = part
end

-- Sichtbares Teil (masselos, nicht fest) relativ zum Rumpf
local function visual(model, chassis, name, size, offset, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	if shape then
		part.Shape = shape
	end
	part.CFrame = chassis.CFrame * offset
	part.Parent = model
	weldTo(chassis, part)
	return part
end

local function wheel(model, chassis, x, y, z, diameter, width)
	return visual(model, chassis, "Wheel", Vector3.new(width, diameter, diameter), CFrame.new(x, y, z),
		Color3.fromRGB(26, 26, 28), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
end

-- Sitz relativ zum Rumpf; driver = Fahrersitz (VehicleSeat)
local function seat(model, chassis, offset, driver, index)
	local part = Instance.new(driver and "VehicleSeat" or "Seat")
	part.Name = driver and "DriverSeat" or ("Seat" .. index)
	part.Size = Vector3.new(1.8, 0.4, 1.8)
	part.Color = Color3.fromRGB(40, 40, 44)
	part.Material = Enum.Material.Fabric
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false -- nicht beim Vorbeilaufen hinsetzen, nur per Taste/E
	part.Massless = true
	part.CFrame = chassis.CFrame * offset
	if driver then
		local vehicleSeat = part :: VehicleSeat
		vehicleSeat.HeadsUpDisplay = false
		vehicleSeat.MaxSpeed = 0
	end
	part:SetAttribute("Vehicle", true)
	part.Parent = model
	weldTo(chassis, part)
	return part
end

-- Fahrzeug bauen (noch nicht im Workspace). cframe = Mitte des Rumpfs, Blick = Fahrtrichtung (-Z).
local function build(vehicleId, config, cframe)
	local model = Instance.new("Model")
	model.Name = config.Name
	local size = config.Size
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = size
	chassis.Transparency = 1
	chassis.CFrame = cframe
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.8, 0, 0, 100, 1)
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.Parent = model
	model.PrimaryPart = chassis

	-- Gleitkugeln an den Ecken (tragen das Fahrzeug, gleiten über kleine Kanten)
	local hx, hz = math.max(0.5, size.X / 2 - 0.9), size.Z / 2 - 1.4
	local ballY = -size.Y / 2 - 0.3
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local ball = Instance.new("Part")
			ball.Name = "Skid"
			ball.Shape = Enum.PartType.Ball
			ball.Size = Vector3.new(BALL, BALL, BALL)
			ball.Transparency = 1
			ball.CustomPhysicalProperties = PhysicalProperties.new(0.8, 0, 0, 100, 1)
			ball.CFrame = cframe * CFrame.new(sx * hx, ballY, sz * hz)
			ball.Parent = model
			weldTo(chassis, ball)
		end
	end

	-- Aussehen je Art (alle offen, damit man die Insassen sieht)
	local color = config.Color
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.45)
	local top = size.Y / 2
	local glass = Color3.fromRGB(150, 180, 200)
	local seats = {}
	if config.Kind == "Car" then
		visual(model, chassis, "Body", Vector3.new(size.X, size.Y * 0.9, size.Z), CFrame.new(0, 0.1, 0), color, Enum.Material.Metal)
		visual(model, chassis, "Hood", Vector3.new(size.X - 0.4, 0.5, size.Z * 0.32), CFrame.new(0, top + 0.3, -size.Z * 0.32),
			color, Enum.Material.Metal)
		visual(model, chassis, "Windshield", Vector3.new(size.X - 0.6, 1.6, 0.2), CFrame.new(0, top + 1.2, -size.Z * 0.14)
			* CFrame.Angles(math.rad(-20), 0, 0), glass, Enum.Material.Glass).Transparency = 0.45
		visual(model, chassis, "RollBar", Vector3.new(size.X - 0.3, 0.3, 0.3), CFrame.new(0, top + 2.6, size.Z * 0.12), dark,
			Enum.Material.Metal)
		for _, sx in { -1, 1 } do
			visual(model, chassis, "RollBarPost", Vector3.new(0.3, 2.4, 0.3), CFrame.new(sx * (size.X / 2 - 0.3), top + 1.3, size.Z * 0.12),
				dark, Enum.Material.Metal)
			visual(model, chassis, "Headlight", Vector3.new(0.9, 0.4, 0.1), CFrame.new(sx * (size.X / 2 - 0.9), 0.3, -size.Z / 2 - 0.05),
				Color3.fromRGB(255, 244, 214), Enum.Material.Neon)
			visual(model, chassis, "Taillight", Vector3.new(0.8, 0.35, 0.1), CFrame.new(sx * (size.X / 2 - 0.8), 0.3, size.Z / 2 + 0.05),
				Color3.fromRGB(200, 30, 30), Enum.Material.Neon)
		end
		if vehicleId == "Sports" then
			visual(model, chassis, "Spoiler", Vector3.new(size.X - 0.8, 0.2, 1.2), CFrame.new(0, top + 0.9, size.Z / 2 - 0.6), dark,
				Enum.Material.Metal)
		else
			-- Pritsche hinten
			visual(model, chassis, "BedWallL", Vector3.new(0.3, 1.2, size.Z * 0.34), CFrame.new(-size.X / 2 + 0.15, top + 0.6, size.Z * 0.31),
				color, Enum.Material.Metal)
			visual(model, chassis, "BedWallR", Vector3.new(0.3, 1.2, size.Z * 0.34), CFrame.new(size.X / 2 - 0.15, top + 0.6, size.Z * 0.31),
				color, Enum.Material.Metal)
			visual(model, chassis, "BedWallBack", Vector3.new(size.X, 1.2, 0.3), CFrame.new(0, top + 0.6, size.Z / 2 - 0.15), color,
				Enum.Material.Metal)
		end
		local wheelY = ballY + 0.1
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				wheel(model, chassis, sx * (size.X / 2 - 0.2), wheelY, sz * hz, 2.6, 1)
			end
		end
		table.insert(seats, CFrame.new(-size.X / 4, top + 0.4, -size.Z * 0.02))
		table.insert(seats, CFrame.new(size.X / 4, top + 0.4, -size.Z * 0.02))
		table.insert(seats, CFrame.new(-size.X / 4, top + 0.4, size.Z * 0.3))
		table.insert(seats, CFrame.new(size.X / 4, top + 0.4, size.Z * 0.3))
	elseif config.Kind == "Quad" then
		visual(model, chassis, "Body", Vector3.new(size.X - 1.2, size.Y * 0.8, size.Z - 1), CFrame.new(0, 0.2, 0), color, Enum.Material.Metal)
		visual(model, chassis, "Fender", Vector3.new(size.X, 0.4, 1.8), CFrame.new(0, top - 0.1, -size.Z / 2 + 1.2), dark, Enum.Material.Metal)
		visual(model, chassis, "Fender", Vector3.new(size.X, 0.4, 1.8), CFrame.new(0, top - 0.1, size.Z / 2 - 1.2), dark, Enum.Material.Metal)
		visual(model, chassis, "Handlebar", Vector3.new(2.6, 0.25, 0.25), CFrame.new(0, top + 1.1, -size.Z * 0.2), Color3.fromRGB(30, 30, 32),
			Enum.Material.Metal)
		visual(model, chassis, "Steering", Vector3.new(0.25, 1.1, 0.25), CFrame.new(0, top + 0.55, -size.Z * 0.18), Color3.fromRGB(30, 30, 32),
			Enum.Material.Metal)
		visual(model, chassis, "Headlight", Vector3.new(1.4, 0.4, 0.1), CFrame.new(0, 0.4, -size.Z / 2 + 0.4),
			Color3.fromRGB(255, 244, 214), Enum.Material.Neon)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				wheel(model, chassis, sx * (size.X / 2 - 0.3), ballY + 0.2, sz * hz, 2.4, 1.2)
			end
		end
		table.insert(seats, CFrame.new(0, top + 0.3, size.Z * 0.12))
	else
		-- Fahrrad: Rahmen, zwei Räder, Lenker, Sattel (Kugeln unsichtbar, darum kippt es nicht)
		visual(model, chassis, "Frame", Vector3.new(0.3, 0.3, size.Z * 0.6), CFrame.new(0, 0.6, 0), color, Enum.Material.Metal)
		visual(model, chassis, "FrameDown", Vector3.new(0.3, 1.6, 0.3), CFrame.new(0, 0.2, -size.Z * 0.22) * CFrame.Angles(math.rad(25), 0, 0),
			color, Enum.Material.Metal)
		visual(model, chassis, "Handlebar", Vector3.new(1.6, 0.2, 0.2), CFrame.new(0, 1.6, -size.Z * 0.3), Color3.fromRGB(30, 30, 32),
			Enum.Material.Metal)
		for _, sz in { -1, 1 } do
			wheel(model, chassis, 0, ballY + 0.4, sz * (size.Z / 2 - 0.6), 2.6, 0.25)
		end
		table.insert(seats, CFrame.new(0, 0.9, size.Z * 0.12))
	end

	local driverSeat = nil
	for index = 1, math.min(config.Seats or 1, #seats) do
		local part = seat(model, chassis, seats[index], index == 1, index)
		if index == 1 then
			driverSeat = part
		end
	end

	-- Antrieb: Tempo nur waagerecht (Schwerkraft frei), Ausrichtung gerade mit Drehung um die Hochachse
	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.Parent = chassis
	local mass = size.X * size.Y * size.Z * 0.8 + 4 * 5.6 * 0.8 + 30 -- Rumpf, Kugeln, Insassen
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "Drive"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	velocity.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	velocity.PlaneVelocity = Vector2.zero
	velocity.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	velocity.MaxForce = mass * 90
	velocity.Parent = chassis
	local _, yaw = cframe:ToOrientation()
	local align = Instance.new("AlignOrientation")
	align.Name = "Steer"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.CFrame = CFrame.Angles(0, yaw, 0)
	align.MaxTorque = mass * 4000
	align.Responsiveness = 35
	align.Parent = chassis

	model:SetAttribute("VehicleId", vehicleId)
	model:SetAttribute("MaxHealth", config.Health)
	model:SetAttribute("Health", config.Health)
	return model, chassis, driverSeat
end

-- ---------- Spawnen und Einpacken ----------

local function inventorySlotOf(player, item)
	local bag = InventoryService.GetBag(player)
	if not bag then
		return nil
	end
	for slot = 1, bag.Size do
		if bag.Slots[slot] == item then
			return slot
		end
	end
	return nil
end

-- Alle Insassen aussteigen lassen
local function ejectAll(model)
	for _, part in model:GetChildren() do
		if (part:IsA("Seat") or part:IsA("VehicleSeat")) and part.Occupant then
			local humanoid = part.Occupant
			humanoid.Sit = false
			humanoid.Jump = true
		end
	end
end

-- Fahrzeug entfernen (ohne Wartezeit), Item wieder "drinnen"
local function despawn(player)
	local entry = active[player]
	if not entry then
		return
	end
	active[player] = nil
	entry.Item.Out = nil
	ejectAll(entry.Model)
	entry.Model:Destroy()
	if player.Parent then
		InventoryService.Changed(player)
	end
end
VehicleService.Despawn = despawn

-- Stelle für das Fahrzeug vor dem Spieler (sonst rechts, links, hinter ihm). nil = kein Platz.
local function placement(player, root, config)
	local size = config.Size
	local _, yaw = root.CFrame:ToOrientation()
	local facing = CFrame.Angles(0, yaw, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	for _, name in { "Zombies", "ExtinctionLoot" } do
		local extra = workspace:FindFirstChild(name)
		if extra then
			table.insert(ignore, extra)
		end
	end
	params.FilterDescendantsInstances = ignore
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	local lift = size.Y / 2 + 0.3 + BALL / 2 + 0.15 -- Mitte des Rumpfs über dem Boden
	local away = size.Z / 2 + 3
	for _, offset in { Vector3.new(0, 0, -away), Vector3.new(size.X + 3, 0, 0), Vector3.new(-size.X - 3, 0, 0),
		Vector3.new(0, 0, away) } do
		local probe = (root.CFrame.Position + facing:VectorToWorldSpace(offset))
		local hit = workspace:Raycast(probe + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), params)
		if hit and hit.Normal.Y > 0.8 then
			local cframe = CFrame.new(hit.Position + Vector3.new(0, lift, 0)) * facing
			local blocking = false
			for _, part in workspace:GetPartBoundsInBox(cframe, size + Vector3.new(0, 1, 0), overlap) do
				if part.CanCollide and part.Transparency < 1 then
					blocking = true
					break
				end
			end
			if not blocking then
				return cframe
			end
		end
	end
	return nil
end

local function watchSeats(player, model)
	for _, part in model:GetChildren() do
		if part:IsA("Seat") or part:IsA("VehicleSeat") then
			local isDriver = part:IsA("VehicleSeat")
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "SeatPrompt"
			prompt.ActionText = isDriver and "Fahren" or "Mitfahren"
			prompt.ObjectText = model.Name .. " · " .. player.Name
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.Parent = part
			prompt.Triggered:Connect(function(who)
				local _, humanoid = livingCharacter(who)
				if not humanoid or part.Occupant or humanoid.SeatPart then
					return
				end
				if isDriver and who ~= player then
					status(who, "Nur der Besitzer darf fahren.")
					return
				end
				InventoryService.Holster(who)
				part:Sit(humanoid)
			end)
			part:GetPropertyChangedSignal("Occupant"):Connect(function()
				prompt.Enabled = part.Occupant == nil
				local occupant = part.Occupant
				local rider = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
				if rider then
					InventoryService.Holster(rider) -- im Fahrzeug keine Waffe
				end
				if isDriver then
					local chassis = model.PrimaryPart
					if rider == player then
						pcall(chassis.SetNetworkOwner, chassis, player) -- der Fahrer rechnet die Physik
					else
						-- niemand fährt: anhalten und gerade stehen lassen
						local drive = chassis:FindFirstChild("Drive")
						local steer = chassis:FindFirstChild("Steer")
						if drive and drive:IsA("LinearVelocity") then
							drive.PlaneVelocity = Vector2.zero
						end
						if steer and steer:IsA("AlignOrientation") then
							local _, yaw = chassis.CFrame:ToOrientation()
							steer.CFrame = CFrame.Angles(0, yaw, 0)
						end
						pcall(chassis.SetNetworkOwner, chassis, nil)
					end
				end
			end)
		end
	end
end

-- Taste auf einem Fahrzeug-Platz: spawnen und einsteigen bzw. wieder einsteigen
function VehicleService.Use(player, _, item)
	local character, humanoid, root = livingCharacter(player)
	if not character or not humanoid or not root or not Modes.IsSurvival(player:GetAttribute("Mode")) then
		return false
	end
	local itemConfig = ExtinctionConfig.Get(item.Id)
	local config = itemConfig and ExtinctionConfig.Vehicles[itemConfig.Vehicle]
	if not config then
		return false
	end
	local entry = active[player]
	if entry and entry.Item == item then
		-- schon draußen: in der Nähe wieder einsteigen
		local driverSeat = entry.Seat
		if humanoid.SeatPart then
			return false
		end
		if (driverSeat.Position - root.Position).Magnitude <= SEAT_RANGE and not driverSeat.Occupant then
			InventoryService.Holster(player)
			driverSeat:Sit(humanoid)
			return true
		end
		status(player, "Dein " .. config.Name .. " ist schon draußen – K packt es ein.")
		return false
	elseif entry then
		status(player, "Du hast schon ein Fahrzeug draußen. Pack es erst mit K ein.")
		return false
	end
	if humanoid.SeatPart then
		status(player, "Steig erst aus.")
		return false
	end
	local wait = (player:GetAttribute("ExtVehicleReadyAt") or 0) - workspace:GetServerTimeNow()
	if wait > 0 then
		status(player, "Fahrzeug wieder bereit in " .. math.ceil(wait) .. " s.")
		return false
	end
	local cframe = placement(player, root, config)
	if not cframe then
		status(player, "Hier ist kein Platz für das Fahrzeug.")
		return false
	end
	local model, chassis, driverSeat = build(itemConfig.Vehicle, config, cframe)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("OwnerName", player.Name)
	model.Parent = folder
	active[player] = { Model = model, Chassis = chassis, Seat = driverSeat, Item = item, Config = config,
		LastPos = chassis.Position, LastTime = os.clock() }
	item.Out = true
	watchSeats(player, model)
	VehicleService.WatchRam(player, model, chassis)
	InventoryService.Holster(player)
	InventoryService.Changed(player)
	driverSeat:Sit(humanoid)
	return true
end

-- K: Fahrzeug einpacken (sitzend oder in der Nähe), danach VehicleCooldown Sekunden warten
function VehicleService.Store(player)
	local entry = active[player]
	if not entry then
		return false
	end
	local _, humanoid, root = livingCharacter(player)
	local inside = humanoid ~= nil and humanoid.SeatPart ~= nil and humanoid.SeatPart:IsDescendantOf(entry.Model)
	if not inside and (not root or (root.Position - entry.Chassis.Position).Magnitude > ExtinctionConfig.VehicleStoreRange) then
		status(player, "Geh näher an dein Fahrzeug, um es einzupacken.")
		return false
	end
	despawn(player)
	player:SetAttribute("ExtVehicleReadyAt", workspace:GetServerTimeNow() + ExtinctionConfig.VehicleCooldown)
	status(player, entry.Config.Name .. " eingepackt.", true)
	return true
end

-- ---------- Schaden ----------

-- Fahrzeug kaputt: ausbrennen, Item weg
local function wreck(owner, entry)
	active[owner] = nil
	local model = entry.Model
	ejectAll(model)
	local slot = inventorySlotOf(owner, entry.Item)
	local bag = InventoryService.GetBag(owner)
	if slot and bag then
		Inventory.TakeSlot(bag, slot)
		InventoryService.Changed(owner)
	end
	status(owner, "Dein " .. entry.Config.Name .. " wurde zerstört.")
	local chassis = entry.Chassis
	local explosion = Instance.new("Explosion")
	explosion.BlastPressure = 0
	explosion.BlastRadius = 6
	explosion.DestroyJointRadiusPercent = 0
	explosion.Position = chassis.Position
	explosion.Parent = workspace
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			part.Color = Color3.fromRGB(30, 28, 26)
			part.Material = Enum.Material.CorrodedMetal
		elseif part:IsA("ProximityPrompt") then
			part.Enabled = false
		end
	end
	local fire = Instance.new("Fire")
	fire.Size = 8
	fire.Parent = chassis
	local smoke = Instance.new("Smoke")
	smoke.RiseVelocity = 8
	smoke.Opacity = 0.4
	smoke.Parent = chassis
	task.delay(6, function()
		model:Destroy()
	end)
end

-- Treffer auf ein Fahrzeug (WeaponService): nur draußen und mit PvP-Zeit des Schützen. Gibt den Schaden zurück.
function VehicleService.Hit(attacker, model, amount)
	local ownerId = model:GetAttribute("Owner")
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	local entry = owner and active[owner]
	if not entry or entry.Model ~= model or not entry.Chassis.Parent then
		return 0
	end
	if options and options.InSafeZone(entry.Chassis.Position) then
		return 0
	end
	if attacker and attacker ~= owner and attacker:GetAttribute("PvP") ~= true then
		return 0
	end
	-- Fahrzeug eines Squad-Mitglieds: kein Schaden
	local squad = attacker and attacker ~= owner and attacker:GetAttribute("SquadId")
	if squad and squad == owner:GetAttribute("SquadId") then
		return 0
	end
	local health = math.max(0, (model:GetAttribute("Health") or 0) - amount)
	model:SetAttribute("Health", health)
	if health <= 0 then
		wreck(owner, entry)
	end
	return amount
end

-- Umfahrene Zombies nehmen Schaden (je schneller, desto mehr)
local rammed = setmetatable({}, { __mode = "k" }) -- [Zombie-Modell] = os.clock() des letzten Treffers
function VehicleService.WatchRam(player, model, chassis)
	local function onTouched(hit)
		local zombie = hit:FindFirstAncestorOfClass("Model")
		if not zombie or not zombie:GetAttribute("IsZombie") then
			return
		end
		local humanoid = zombie:FindFirstChildOfClass("Humanoid")
		local speed = chassis.AssemblyLinearVelocity.Magnitude
		local now = os.clock()
		if not humanoid or humanoid.Health <= 0 or speed < RAM_SPEED or (rammed[zombie] and now - rammed[zombie] < 0.6) then
			return
		end
		rammed[zombie] = now
		Damage.Apply(zombie, humanoid, speed * 2, { Player = player, Weapon = model.Name })
	end
	chassis.Touched:Connect(onTouched)
	for _, part in model:GetChildren() do
		if part.Name == "Skid" and part:IsA("BasePart") then
			part.Touched:Connect(onTouched)
		end
	end
end

-- Aktives Fahrzeug eines Spielers (Tests, Anzeige)
function VehicleService.Get(player)
	local entry = active[player]
	return entry and entry.Model
end

-- opts = { InSafeZone(position) }
function VehicleService.Init(opts)
	options = opts
	InventoryService.UseVehicle = VehicleService.Use
	InventoryService.Handlers.StoreVehicle = VehicleService.Store
	require(script.Parent.WeaponService).OnVehicleHit = VehicleService.Hit
	Players.PlayerRemoving:Connect(function(player)
		despawn(player)
	end)
	-- Tempo-Check: Fahrzeuge, die schneller sind als erlaubt, zurücksetzen
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		local now = os.clock()
		for player, entry in active do
			local chassis = entry.Chassis
			if not chassis.Parent then
				active[player] = nil
			else
				local delta = now - entry.LastTime
				local moved = Vector3.new(chassis.Position.X - entry.LastPos.X, 0, chassis.Position.Z - entry.LastPos.Z).Magnitude
				if moved > (entry.Config.Speed * SPEED_SLACK + 30) * delta then
					entry.Model:PivotTo(CFrame.new(entry.LastPos) * chassis.CFrame.Rotation)
					chassis.AssemblyLinearVelocity = Vector3.zero
					warn("Fahrzeug von " .. player.Name .. " zu schnell, zurückgesetzt")
				else
					entry.LastPos = chassis.Position
				end
				entry.LastTime = now
			end
		end
	end)
end

return VehicleService

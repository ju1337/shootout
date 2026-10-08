-- AirdropService (ModuleScript, nur Server)
-- Lootdrops (Versorgungsabwürfe) der offenen Welt (EXTINCTION): Alle paar Minuten (ExtinctionConfig.Airdrop: FirstDelay,
-- MinInterval bis MaxInterval) wirft ein Flugzeug eine Kiste ab, solange mindestens ein Spieler draußen ist.
--   1. Warnung (Warning Sekunden): Ansage an alle in der offenen Welt, Leuchtfackel und Lichtsäule an der Landestelle, die
--      Stelle steht für die Clients im Attribut "Airdrops" an der Karte: [{ Id, X, Y, Z, State, Eta, Zone }].
--   2. Landung: die Kiste sinkt am Fallschirm (FallTime Sekunden) von Height Studs herunter.
--   3. Gelandet: Kiste (LootService, Art "Airdrop") mit bester Beute (LootTables.Airdrop, Items Einträge), E halten (OpenTime
--      Sekunden) öffnet, F nimmt alles; Escort Zombies kommen um die Landestelle. Nach Lifetime Sekunden oder wenn sie leer
--      ist, verschwindet die Kiste; dann beginnt die Wartezeit bis zum nächsten Abwurf.
-- Das Ziel liegt mit RedzoneChance in der roten Zone, sonst irgendwo auf dem Boden (nicht nah am Rand, nicht nah an der Safe
-- Zone, nicht im Wasser). In der roten Zone ist die Beute besser (ExtinctionConfig.Redzone.Loot: mehr Items, größere Stapel),
-- und bei jedem Wechsel der Zone kommt ein Abwurf in die neue Zone (StartInZone, wenn jemand draußen ist).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local LootService = require(script.Parent.LootService)
local ZombieService = require(script.Parent.ZombieService)

local AirdropService = {}

local A = ExtinctionConfig.Airdrop
local random = Random.new()
local options = nil  -- { Map, Center, InSafeZone(position), SafeCenter(), Players(), RedzoneRandom() -> Zone | nil, IsWater(x, z) }
local active = {}    -- Liste der laufenden Abwürfe (höchstens einer)
local nextAt = 0
local nextId = 0
local folder = workspace:FindFirstChild("ExtinctionDrops") or Instance.new("Folder")
folder.Name = "ExtinctionDrops"
folder.Parent = workspace

local function part(model, name, size, cframe, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if shape then
		p.Shape = shape
	end
	p.CFrame = cframe
	p.Parent = model
	return p
end

local function announce(title, sub)
	for _, player in options.Players() do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Lootdrop", Title = title, Sub = sub, Style = "Info" })
	end
end

local function publish()
	local list = {}
	for _, drop in active do
		table.insert(list, { Id = drop.Id, X = drop.Target.X, Y = drop.Target.Y, Z = drop.Target.Z, State = drop.State, Eta = drop.Eta,
			Zone = drop.Zone and drop.Zone.Title or nil })
	end
	options.Map:SetAttribute("Airdrops", HttpService:JSONEncode(list))
end

local function playersOutside()
	local n = 0
	for _, player in options.Players() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 and not options.InSafeZone(root.Position) then
			n += 1
		end
	end
	return n
end

-- ---------- Ziel ----------

-- Bodenpunkt in der inneren Hälfte einer Zone (nil, wenn keiner passt)
local function pointInZone(zone)
	for _ = 1, 12 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = zone.Radius * math.sqrt(random:NextNumber(0, 0.5))
		local ground = ZombieService.GroundAt(zone.Center.X + math.cos(angle) * distance, zone.Center.Z + math.sin(angle) * distance)
		if ground then
			return ground
		end
	end
	return nil
end

-- Landestelle: in der roten Zone (mit RedzoneChance) oder irgendwo; nil, wenn nichts Passendes gefunden wurde
local function pickTarget()
	local half = ExtinctionConfig.WorldSize / 2 - A.EdgeMargin
	local safeCenter, safeRadius = options.SafeCenter()
	if options.RedzoneRandom and random:NextNumber() < A.RedzoneChance then
		local zone = options.RedzoneRandom()
		local ground = zone and pointInZone(zone)
		if ground then
			return ground, zone
		end
	end
	for _ = 1, 40 do
		local x = options.Center.X + random:NextNumber(-half, half)
		local z = options.Center.Z + random:NextNumber(-half, half)
		local clear = Vector3.new(x - safeCenter.X, 0, z - safeCenter.Z).Magnitude > safeRadius + A.SafeMargin
		for _, zone in options.SafeZones and options.SafeZones() or {} do
			if Vector3.new(x - zone.Center.X, 0, z - zone.Center.Z).Magnitude <= zone.Radius + A.SafeMargin then
				clear = false
			end
		end
		if clear then
			local ground = ZombieService.GroundAt(x, z)
			if ground then
				return ground, options.RedzoneAt and options.RedzoneAt(ground) or nil
			end
		end
	end
	return nil, nil
end

-- ---------- Aussehen ----------

local function buildFlare(target)
	local model = Instance.new("Model")
	model.Name = "AirdropFlare"
	local base = CFrame.new(target)
	local disc = part(model, "Zone", Vector3.new(0.3, 24, 24), base * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(255, 110, 50), Enum.Material.Neon, Enum.PartType.Cylinder)
	disc.Transparency = 0.7
	local beam = part(model, "Beam", Vector3.new(1.4, 140, 1.4), base * CFrame.new(0, 70, 0), Color3.fromRGB(255, 90, 40), Enum.Material.Neon)
	beam.Transparency = 0.55
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 60)
	light.Range = 40
	light.Brightness = 2
	light.Parent = beam
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 96, 56))
	smoke.Size = NumberSequence.new(6, 14)
	smoke.Lifetime = NumberRange.new(3, 6)
	smoke.Rate = 12
	smoke.Speed = NumberRange.new(6, 12)
	smoke.Transparency = NumberSequence.new(0.35, 1)
	smoke.Parent = beam
	model.Parent = folder
	return model
end

local function buildCrateFall()
	local model = Instance.new("Model")
	model.Name = "AirdropFall"
	local body = part(model, "Crate", Vector3.new(5, 3.6, 5), CFrame.new(), Color3.fromRGB(214, 120, 40), Enum.Material.Metal)
	part(model, "Lid", Vector3.new(5.3, 0.4, 5.3), CFrame.new(0, 2, 0), Color3.fromRGB(150, 84, 28), Enum.Material.Metal)
	local canopy = part(model, "Canopy", Vector3.new(14, 14, 14), CFrame.new(0, 12, 0), Color3.fromRGB(240, 240, 235), Enum.Material.Fabric,
		Enum.PartType.Ball)
	canopy.Name = "Canopy"
	for index, corner in { Vector3.new(2.2, 1.8, 2.2), Vector3.new(-2.2, 1.8, 2.2), Vector3.new(2.2, 1.8, -2.2), Vector3.new(-2.2, 1.8, -2.2) } do
		local top = Vector3.new(corner.X * 2.2, 8.5, corner.Z * 2.2)
		local mid = (corner + top) / 2
		part(model, "Rope" .. index, Vector3.new(0.12, 0.12, (top - corner).Magnitude), CFrame.lookAt(mid, top), Color3.fromRGB(60, 60, 60))
	end
	model.PrimaryPart = body
	model.Parent = folder
	return model
end

-- ---------- Ablauf ----------

local function finish(drop)
	for index, other in active do
		if other == drop then
			table.remove(active, index)
			break
		end
	end
	if drop.Flare then
		drop.Flare:Destroy()
		drop.Flare = nil
	end
	if drop.Falling then
		drop.Falling:Destroy()
		drop.Falling = nil
	end
	drop.State = "Gone"
	nextAt = os.clock() + random:NextNumber(A.MinInterval, A.MaxInterval)
	publish()
end

local function land(drop)
	if drop.Falling then
		drop.Falling:Destroy()
		drop.Falling = nil
	end
	local count = random:NextInteger(A.Items[1], A.Items[2])
	local items = drop.Zone and ExtinctionConfig.RedzoneRoll("Airdrop", count + ExtinctionConfig.Redzone.Loot.AirdropExtra, random)
		or ExtinctionConfig.RollLoot("Airdrop", count, random)
	drop.LootId = LootService.Create(drop.Target, items, "Airdrop", "LOOTDROP", { HoldTime = A.OpenTime, Lifetime = A.Lifetime, Meta = { Drop = drop } })
	if not drop.LootId then
		finish(drop)
		return
	end
	drop.State = "Landed"
	drop.Eta = 0
	drop.Escort = ZombieService.SpawnAround(drop.Target, A.Escort, 20, 50, "Walker")
	if drop.Flare then
		local beam = drop.Flare:FindFirstChild("Beam")
		if beam then
			beam.Size = Vector3.new(1.0, 90, 1.0)
		end
	end
	publish()
	announce("LOOTDROP GELANDET", "E halten zum Öffnen · Zombies in der Nähe")
end

local function tick(now)
	for _, drop in table.clone(active) do
		if drop.State == "Warning" then
			if now >= drop.FallAt then
				drop.State = "Falling"
				drop.Falling = buildCrateFall()
				publish()
			end
		end
		if drop.State == "Falling" then
			local t = math.clamp((now - drop.FallAt) / A.FallTime, 0, 1)
			local eased = 1 - (1 - t) * (1 - t) -- erst schnell, dann sanft
			local height = A.Height * (1 - eased)
			if drop.Falling and drop.Falling.PrimaryPart then
				drop.Falling:PivotTo(CFrame.new(drop.Target + Vector3.new(0, 2 + height, 0)) * CFrame.Angles(0, t * 1.5, math.sin(now * 1.3) * 0.05))
			end
			if t >= 1 then
				land(drop)
			end
		end
	end
	-- nächster Abwurf, sobald Zeit und Spieler da sind
	if #active == 0 and now >= nextAt and playersOutside() >= A.MinPlayers then
		AirdropService.Start()
	end
end

-- Abwurf starten (zu Tests und für Admins mit festem Ziel position; sonst wird eins gewürfelt). Gibt den Abwurf zurück.
function AirdropService.Start(position)
	if #active > 0 then
		return nil
	end
	local target, zone = position, nil
	if target then
		zone = options.RedzoneAt and options.RedzoneAt(target) or nil
	else
		target, zone = pickTarget()
	end
	if not target then
		nextAt = os.clock() + 30 -- nichts Passendes gefunden: bald nochmal
		return nil
	end
	nextId += 1
	local now = os.clock()
	local drop = { Id = nextId, Target = target, Zone = zone, State = "Warning", FallAt = now + A.Warning,
		Eta = workspace:GetServerTimeNow() + A.Warning + A.FallTime }
	drop.Flare = buildFlare(target)
	table.insert(active, drop)
	publish()
	announce("VERSORGUNGSABWURF", (zone and ("In der roten Zone " .. zone.Title .. " · ") or "") .. "Landet in " .. A.Warning + A.FallTime
		.. " Sekunden · Markierung auf dem Bildschirm")
	return drop
end

function AirdropService.Active()
	return active
end

-- Abwurf in eine Zone (die rote Zone hat gerade gewechselt): nur, wenn jemand draußen ist und gerade keiner läuft
function AirdropService.StartInZone(zone)
	if not options or #active > 0 or not zone or playersOutside() < A.MinPlayers then
		return nil
	end
	local ground = pointInZone(zone)
	return ground and AirdropService.Start(ground) or nil
end

-- opts = { Map, Center (Vector3), InSafeZone(position), SafeCenter() -> (Vector3, Radius), Players() -> { Player },
--          RedzoneAt(position) -> Zone | nil, RedzoneRandom() -> Zone | nil }
-- Zufällige freie Stelle draußen (auch für andere Events, z.B. die Horden-Kiste)
function AirdropService.PickTarget()
	local target = pickTarget()
	return target
end

function AirdropService.Init(opts)
	options = opts
	nextAt = os.clock() + A.FirstDelay
	publish()
	LootService.OnRemoved[#LootService.OnRemoved + 1] = function(bag)
		local drop = bag.Meta and bag.Meta.Drop
		if bag.Kind == "Airdrop" and drop and drop.State == "Landed" then
			finish(drop)
		end
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.1 then
			elapsed = 0
			local ok, err = pcall(tick, os.clock())
			if not ok then
				warn("Lootdrop: " .. tostring(err))
			end
		end
	end)
end

return AirdropService

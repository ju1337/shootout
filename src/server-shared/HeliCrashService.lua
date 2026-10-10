-- HeliCrashService (ModuleScript, nur Server)
-- Heli-Absturz der offenen Welt (Werte in ExtinctionConfig.HeliCrash): Ein Militär-Heli zieht mit Rauchfahne über die Karte
-- (Ansage, aber kein Ziel) und schlägt irgendwo ein. Das Wrack brennt eine Weile (Feuer macht allen in der Nähe Schaden, auch
-- Zombies), der Lärm lockt Zombies an, und erst wenn das Feuer aus ist, liegen die Kisten mit Militär-Beute am Wrack bereit.
-- Ab dem Einschlag steht das Wrack auf der Karte (Attribut "HeliCrashes" [{ Id, X, Z, State ("Burning"/"Loot"), Ends }]).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sfx = require(Shared.Sfx)
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local LootService = require(script.Parent.LootService)
local ZombieService = require(script.Parent.ZombieService)
local Damage = require(script.Parent.Damage)

local HeliCrashService = {}

local K = ExtinctionConfig.HeliCrash
local random = Random.new()
local options = nil -- { Map, Center, Players(), InSafeZone(position), PickTarget() -> Vector3? }
local current = nil -- { Id, Target, Start, State, Model, FlyStart, BurnEnds, Ends, Loot = { LootId } }
local nextAt = 0
local nextId = 0
local folder = workspace:FindFirstChild("ExtinctionHeliCrash") or Instance.new("Folder")
folder.Name = "ExtinctionHeliCrash"
folder.Parent = workspace

local OLIVE = Color3.fromRGB(70, 78, 56)
local DARK = Color3.fromRGB(34, 34, 36)

local function announce(title, sub, style)
	for _, player in options.Players() do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Heli", Title = title, Sub = sub, Style = style or "Warning" })
	end
end

local function publish()
	local list = {}
	if current and current.State ~= "Flying" then
		table.insert(list, { Id = current.Id, X = current.Target.X, Z = current.Target.Z, State = current.State,
			Ends = current.State == "Burning" and current.BurnEndsServer or nil })
	end
	options.Map:SetAttribute("HeliCrashes", HttpService:JSONEncode(list))
end

local function part(model, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = model
	return p
end

local function smoke(parent, color, size, rise)
	local s = Instance.new("Smoke")
	s.Color = color
	s.Size = size
	s.RiseVelocity = rise
	s.Opacity = 0.5
	s.Parent = parent
	return s
end

-- Heli im Flug (Nase lokal -Z): Rumpf, Kanzel, Heckausleger, Leitwerk, Rotor, Kufen, Rauchfahne
local function buildFlying()
	local model = Instance.new("Model")
	model.Name = "CrashingHeli"
	local body = part(model, "Body", Vector3.new(6, 5, 12), CFrame.new(), OLIVE)
	model.PrimaryPart = body
	part(model, "Cockpit", Vector3.new(5, 3.5, 3), CFrame.new(0, 0.5, -6.5), Color3.fromRGB(60, 80, 90), Enum.Material.Glass)
	part(model, "Tail", Vector3.new(1.6, 1.6, 14), CFrame.new(0, 1, 12), OLIVE)
	part(model, "Fin", Vector3.new(0.4, 4, 2.5), CFrame.new(0, 3, 18.5), OLIVE)
	part(model, "Rotor", Vector3.new(30, 0.3, 1.4), CFrame.new(0, 3.5, 0), DARK)
	part(model, "Rotor2", Vector3.new(1.4, 0.3, 30), CFrame.new(0, 3.5, 0), DARK)
	for _, x in { -3, 3 } do
		part(model, "Skid", Vector3.new(0.5, 0.5, 12), CFrame.new(x, -3.2, 0), DARK)
	end
	smoke(body, Color3.fromRGB(40, 40, 40), 8, 6)
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Parent = body
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- Streaming: beim Client ganz oder gar nicht
	model.Parent = folder
	-- Rotor und Warnton im Cockpit (enden mit dem Modell beim Aufprall)
	Sfx.Loop("HeliLoop", body)
	Sfx.Loop("HeliAlarm", body)
	return model
end

-- Wrack am Einschlag: gekippter Rumpf, abgebrochenes Heck, Rotorblätter verstreut, Feuer und schwarzer Rauch
local function buildWreck(target)
	local model = Instance.new("Model")
	model.Name = "HeliWreck"
	local base = CFrame.new(target) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	local body = part(model, "Body", Vector3.new(6, 5, 12), base * CFrame.new(0, 2.2, 0) * CFrame.Angles(math.rad(8), 0, math.rad(24)),
		Color3.fromRGB(52, 56, 44))
	body.CanQuery = true
	model.PrimaryPart = body
	part(model, "Cockpit", Vector3.new(5, 3, 3), base * CFrame.new(0.8, 1.6, -6.4) * CFrame.Angles(math.rad(14), 0, math.rad(24)),
		Color3.fromRGB(30, 34, 36), Enum.Material.Glass).Transparency = 0.3
	part(model, "Tail", Vector3.new(1.6, 1.6, 12), base * CFrame.new(5, 0.9, 13) * CFrame.Angles(0, math.rad(35), math.rad(-10)),
		Color3.fromRGB(52, 56, 44))
	part(model, "Fin", Vector3.new(0.4, 4, 2.5), base * CFrame.new(8.5, 1.8, 18) * CFrame.Angles(0, math.rad(35), math.rad(70)), OLIVE)
	for i = 1, 3 do
		local angle = i * 2.1
		part(model, "Blade", Vector3.new(13, 0.3, 1.2), base * CFrame.new(math.cos(angle) * 12, 0.3, math.sin(angle) * 12)
			* CFrame.Angles(0, angle + 0.6, math.rad(random:NextNumber(-12, 12))), DARK)
	end
	part(model, "Crater", Vector3.new(0.4, 22, 22), base * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(30, 28, 26), Enum.Material.Basalt).Shape = Enum.PartType.Cylinder
	smoke(body, Color3.fromRGB(26, 26, 26), 14, 14)
	for _, offset in { Vector3.new(0, 3, 0), Vector3.new(4, 1, 10), Vector3.new(-3, 1, -6) } do
		local spot = part(model, "FirePoint", Vector3.new(1, 1, 1), base * CFrame.new(offset), DARK)
		spot.Transparency = 1
		spot.CanCollide = false
		local fire = Instance.new("Fire")
		fire.Name = "Fire"
		fire.Size = 10
		fire.Heat = 14
		fire.Parent = spot
		local light = Instance.new("PointLight")
		light.Name = "Light"
		light.Color = Color3.fromRGB(255, 140, 60)
		light.Range = 30
		light.Brightness = 2.5
		light.Parent = spot
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- Streaming: beim Client ganz oder gar nicht
	model.Parent = folder
	return model
end

-- Feuer aus: nur noch Rauch
local function extinguish(model)
	for _, item in model:GetDescendants() do
		if item:IsA("Fire") or item:IsA("PointLight") then
			item:Destroy()
		elseif item:IsA("Smoke") then
			item.Color = Color3.fromRGB(90, 90, 90)
			item.Opacity = 0.25
		end
	end
end

local function remove()
	if current then
		if current.Model then
			current.Model:Destroy()
		end
		for _, id in current.Loot or {} do
			if LootService.Get(id) then
				LootService.Remove(id)
			end
		end
	end
	current = nil
	nextAt = os.clock() + random:NextNumber(K.MinInterval, K.MaxInterval)
	publish()
end

-- Brandschaden im Umkreis: Spieler (auch in der PvP-Pause, es ist Feuer) und Zombies; Safe Zone schützt Damage selbst
local function burn(dt)
	current.TickIn = (current.TickIn or 0) - dt
	if current.TickIn > 0 then
		return
	end
	current.TickIn = K.Tick
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	local zombies = workspace:FindFirstChild("Zombies")
	for _, model in zombies and zombies:GetChildren() or {} do
		table.insert(list, model)
	end
	for _, model in list do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			local offset = root.Position - current.Target
			if Vector2.new(offset.X, offset.Z).Magnitude <= K.FireRadius and math.abs(offset.Y) <= 10 then
				if Players:GetPlayerFromCharacter(model) then
					Damage.Forget(model) -- im Feuer gestorben: kein alter Gegner als Killer
				end
				Damage.Apply(model, humanoid, K.TickDamage, nil)
			end
		end
	end
end

local function crash()
	local target = current.Target
	if current.Model then
		current.Model:Destroy()
	end
	local explosion = Instance.new("Explosion")
	explosion.Position = target + Vector3.new(0, 2, 0)
	explosion.BlastRadius = 12
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace
	Sfx.At("HeliImpact", target + Vector3.new(0, 2, 0))
	Sfx.At("BigExplosion", target + Vector3.new(0, 2, 0))
	current.Model = buildWreck(target)
	if current.Model.PrimaryPart then
		current.Fire = Sfx.Loop("FireLoopBig", current.Model.PrimaryPart) -- Wrack brennt
	end
	current.State = "Burning"
	current.BurnEnds = os.clock() + K.BurnTime
	current.BurnEndsServer = workspace:GetServerTimeNow() + K.BurnTime
	ZombieService.Keep(ZombieService.SpawnAround(target, K.Zombies, 30, 80, nil, true), K.BurnTime + 120)
	publish()
	announce("HELI ABGESTÜRZT", "Rauchsäule am Horizont · Wrack auf der Karte (N) · brennt noch " .. K.BurnTime .. " s")
end

local function releaseLoot()
	extinguish(current.Model)
	if current.Fire then
		current.Fire:Destroy()
		current.Fire = nil
	end
	current.State = "Loot"
	current.Loot = {}
	for i = 1, K.Crates do
		local items = ExtinctionConfig.RollLoot(K.Table, random:NextInteger(K.Items[1], K.Items[2]), random)
		for _, item in ExtinctionConfig.RollLoot(K.BonusTable, random:NextInteger(K.BonusItems[1], K.BonusItems[2]), random) do
			table.insert(items, item)
		end
		if random:NextNumber() < K.AttachmentChance then
			for _, item in ExtinctionConfig.RollLoot("ConvoyAttachments", 1, random) do
				table.insert(items, item)
			end
		end
		if i == 1 then
			ExtinctionConfig.AddDungeonKey(items, "HeliCrash", random)
		end
		local angle = i / K.Crates * math.pi * 2
		local at = current.Target + Vector3.new(math.cos(angle) * 9, 1, math.sin(angle) * 9)
		local id = LootService.Create(at, items, "Airdrop", "HELI-WRACK", { HoldTime = 4, Lifetime = K.Lifetime })
		table.insert(current.Loot, id)
	end
	current.Ends = os.clock() + K.Lifetime
	publish()
	announce("FEUER AM HELI AUS", "Die Kisten am Wrack sind jetzt zugänglich", "Info")
end

local function tick(now, dt)
	if not current then
		if K.Enabled and now >= nextAt then
			local outside = 0
			for _, player in options.Players() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and not options.InSafeZone(root.Position)
			and not player:GetAttribute("Dungeon") then -- im Dungeon ist man nicht auf der Karte
					outside += 1
				end
			end
			if outside >= K.MinPlayers then
				HeliCrashService.Start()
			else
				nextAt = now + 30
			end
		end
		return
	end
	if current.State == "Flying" then
		local t = math.clamp((now - current.FlyStart) / K.FlyTime, 0, 1)
		local position = current.Start:Lerp(current.Target + Vector3.new(0, 3, 0), t)
		-- leicht schlingernd nach unten, Nase in Flugrichtung
		local look = (current.Target - current.Start) * Vector3.new(1, 0, 1)
		local cf = CFrame.lookAt(position, position + look) * CFrame.Angles(math.rad(-10 * t), 0, math.sin(now * 3) * 0.25)
		if current.Model and current.Model.PrimaryPart then
			current.Model:PivotTo(cf)
		end
		if t >= 1 then
			crash()
		end
	elseif current.State == "Burning" then
		burn(dt)
		if now >= current.BurnEnds then
			releaseLoot()
		end
	elseif current.State == "Loot" then
		local any = false
		for _, id in current.Loot do
			any = any or LootService.Get(id) ~= nil
		end
		if not any or now >= current.Ends then
			remove()
		end
	end
end

-- ---------- Schnittstelle ----------

-- Absturz starten (target optional, sonst zufällig). Gibt den Stand zurück (nil, wenn schon einer läuft).
function HeliCrashService.Start(target)
	if current or not options then
		return nil
	end
	target = target or (options.PickTarget and options.PickTarget())
	if not target then
		nextAt = os.clock() + 30
		return nil
	end
	nextId += 1
	-- Anflug von weit her (zufällige Richtung), in großer Höhe
	local angle = random:NextNumber(0, math.pi * 2)
	local start = target + Vector3.new(math.cos(angle) * 700, 260, math.sin(angle) * 700)
	current = { Id = nextId, Target = target, Start = start, State = "Flying", FlyStart = os.clock(), Model = buildFlying() }
	current.Model:PivotTo(CFrame.lookAt(start, target * Vector3.new(1, 0, 1) + Vector3.new(0, start.Y, 0)))
	publish()
	announce("MAYDAY", "Ein Militär-Heli verliert an Höhe – achte auf die Rauchfahne", "Warning")
	return current
end

-- Admin: Heli-Absturz sofort beenden (Heli, Wrack und Kisten weg). Gibt true zurück, wenn einer lief.
function HeliCrashService.Stop()
	if not current then
		return false
	end
	remove()
	return true
end

function HeliCrashService.Current()
	return current
end

-- opts = { Map, Players(), InSafeZone(position), PickTarget() -> Vector3? }
function HeliCrashService.Init(opts)
	options = opts
	nextAt = os.clock() + K.FirstDelay
	publish()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		local step = elapsed
		elapsed = 0
		local ok, err = pcall(tick, os.clock(), step)
		if not ok then
			warn("Heli-Absturz: " .. tostring(err))
		end
	end)
end

return HeliCrashService

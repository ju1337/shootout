-- BossService (ModuleScript, nur Server)
-- Bosse der offenen Welt (Werte in ExtinctionConfig.Bosses): große Zombies, die ein Gebäude bewachen (Ort aus der Gruppe Places).
-- Ein Boss erscheint, sobald jemand in der Nähe ist, mit Name und Lebensbalken über dem Kopf und einer eigenen Fähigkeit
-- (Chirurg: wirft Spritzen, die Schaden machen und verlangsamen). Stirbt er, liegt seine Beute in einer Tasche am Boden (immer
-- etwas Gutes, dazu seltene Chancen), der Killer bekommt Münzen, und erst nach RespawnTime kommt er wieder.
-- Verschwindet er ohne Tod (z.B. weil niemand mehr in der Nähe war), erscheint er beim nächsten Besuch wieder.
-- Stand für die Karte: Attribut "Bosses" [{ Id, Name, X, Z, Alive, RespawnAt }].

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sfx = require(Shared.Sfx)
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local LootService = require(script.Parent.LootService)
local ZombieService = require(script.Parent.ZombieService)
local Damage = require(script.Parent.Damage)
local ProgressService = require(script.Parent.ProgressService)

local BossService = {}

local random = Random.new()
local options = nil -- { Map, Players(), InSafeZone(position) }
local bosses = {} -- [Id] = { Id, Config, Home (Vector3), Model, Humanoid, RespawnAt (os.clock), RespawnServer, NextAbility }

local function publish()
	local list = {}
	for id, boss in bosses do
		table.insert(list, { Id = id, Name = boss.Config.Name, X = boss.Home.X, Z = boss.Home.Z, Alive = boss.Model ~= nil,
			RespawnAt = boss.Model == nil and boss.RespawnServer or nil })
	end
	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)
	options.Map:SetAttribute("Bosses", HttpService:JSONEncode(list))
end

-- Lebende Spieler draußen in Reichweite
local function playersNear(position, range)
	local list = {}
	for _, player in options.Players() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 and not options.InSafeZone(root.Position)
			and (root.Position - position).Magnitude <= range then
			table.insert(list, { Player = player, Root = root, Humanoid = humanoid, Distance = (root.Position - position).Magnitude })
		end
	end
	table.sort(list, function(a, b)
		return a.Distance < b.Distance
	end)
	return list
end

-- Name und Lebensbalken über dem Kopf
local function addNameplate(model, cfg, humanoid)
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BossBar"
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 160
	gui.Parent = head
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 20)
	name.BackgroundTransparency = 1
	name.Text = cfg.Name
	name.Font = Enum.Font.BuilderSansExtraBold
	name.TextSize = 16
	name.TextColor3 = Color3.fromRGB(255, 90, 80)
	name.TextStrokeTransparency = 0.3
	name.Parent = gui
	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(10, 24)
	track.Size = UDim2.new(1, -20, 0, 8)
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	track.BorderSizePixel = 0
	track.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(214, 58, 58)
	fill.BorderSizePixel = 0
	fill.Parent = track
	humanoid.HealthChanged:Connect(function(health)
		fill.Size = UDim2.fromScale(math.clamp(health / math.max(1, humanoid.MaxHealth), 0, 1), 1)
	end)
end

-- Beute in einer Tasche am Boden, Münzen für den Killer
local function onDeath(boss, model)
	local cfg = boss.Config
	local root = model:FindFirstChild("HumanoidRootPart")
	local position = root and root.Position or boss.Home
	local items = {}
	for _, entry in cfg.Always do
		table.insert(items, { Id = entry[1], Count = entry[2] })
	end
	for _, entry in cfg.Chances do
		if random:NextNumber() < entry.Chance then
			table.insert(items, { Id = entry.Id, Count = entry.Count })
		end
	end
	LootService.Create(position, items, "Drop", "BEUTE · " .. cfg.Name, { Lifetime = 300 })
	local hit = Damage.LastHit(model)
	local killer = hit and hit.Model and Players:GetPlayerFromCharacter(hit.Model)
	if killer then
		ProgressService.AddCoins(killer, cfg.Coins, "Boss")
		ProgressService.AddStat(killer, "Bosses", 1)
	end
	for _, player in options.Players() do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Boss", Title = cfg.Name .. " IST TOT",
			Sub = (killer and (killer.Name .. " hat ihn erledigt · ") or "") .. "Beute liegt beim " .. cfg.Place, Style = "Info" })
	end
	boss.Model, boss.Humanoid = nil, nil
	boss.RespawnAt = os.clock() + cfg.RespawnTime
	boss.RespawnServer = workspace:GetServerTimeNow() + cfg.RespawnTime
	publish()
end

-- Boss erscheinen lassen (am Ort, als großer Zombie)
local function spawn(boss)
	local cfg = boss.Config
	local ground = ZombieService.GroundAt(boss.Home.X, boss.Home.Z) or boss.Home
	local model = ZombieService.Spawn(ground, cfg.Kind, true, false) -- Bosse nie gepanzert
	if not model then
		return false
	end
	model.Name = "Boss_" .. boss.Id
	model:SetAttribute("IsBoss", true)
	model:SetAttribute("BossName", cfg.Name)
	pcall(function()
		model:ScaleTo(cfg.Scale)
	end)
	for _, child in model:GetChildren() do
		if child.Name == "Outfit" then
			child:Destroy() -- eigenes Aussehen, keine Zombie-Kleidung
		elseif child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" and child.Name ~= "Eye" and child.Name ~= "Blood"
			and child.Name ~= "Head" then
			child.Color = cfg.Color
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = cfg.Health
	humanoid.Health = cfg.Health
	humanoid.WalkSpeed = cfg.Speed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local info = ZombieService.Info(model)
	if info then
		info.Damage = cfg.Damage
		info.Speed = cfg.Speed
		info.Coins = 0 -- Münzen gibt es über den Boss
		info.Boss = true
	end
	addNameplate(model, cfg, humanoid)
	if model:FindFirstChild("HumanoidRootPart") then
		Sfx.At("BossRoar", model.HumanoidRootPart) -- erwacht
	end
	boss.Model, boss.Humanoid = model, humanoid
	boss.NextAbility = os.clock() + cfg.AbilityEvery
	humanoid.Died:Once(function()
		if boss.Model == model then
			onDeath(boss, model)
		end
	end)
	publish()
	return true
end

-- Spritze werfen: Schaden und Verlangsamung beim nächsten Spieler
local function throwSyringe(boss, target)
	local cfg = boss.Config
	local head = boss.Model:FindFirstChild("Head") or boss.Model:FindFirstChild("HumanoidRootPart")
	if not head then
		return
	end
	-- sichtbare Spritze, die zum Ziel fliegt
	local dart = Instance.new("Part")
	dart.Name = "BossSyringe"
	dart.Size = Vector3.new(0.3, 0.3, 1.6)
	dart.Color = Color3.fromRGB(150, 230, 120)
	dart.Material = Enum.Material.Neon
	dart.Anchored = true
	dart.CanCollide = false
	dart.CanQuery = false
	dart.CanTouch = false
	dart.CFrame = CFrame.lookAt(head.Position, target.Root.Position)
	dart.Parent = workspace
	Debris:AddItem(dart, 0.6)
	task.spawn(function()
		local from, to = head.Position, target.Root.Position
		for i = 1, 6 do
			if dart.Parent then
				dart.CFrame = CFrame.lookAt(from:Lerp(to, i / 6), to)
			end
			task.wait(0.05)
		end
	end)
	Damage.Apply(target.Root.Parent, target.Humanoid, cfg.AbilityDamage, { Model = boss.Model, BotName = cfg.Name, Weapon = "Spritze" })
	Sfx.At("Spray", target.Root)
	local character = target.Root.Parent
	character:SetAttribute("SpeedMultiplier", cfg.SlowFactor)
	task.delay(cfg.SlowTime, function()
		if character.Parent and character:GetAttribute("SpeedMultiplier") == cfg.SlowFactor then
			character:SetAttribute("SpeedMultiplier", 1)
		end
	end)
end

local function tick(now)
	local changed = false
	for _, boss in bosses do
		local cfg = boss.Config
		if boss.Model and (not boss.Model.Parent or not boss.Humanoid or boss.Humanoid.Health <= 0) then
			if boss.Humanoid and boss.Humanoid.Health > 0 or not boss.Model.Parent then
				-- ohne Tod verschwunden (niemand mehr in der Nähe): beim nächsten Besuch wieder da
				boss.Model, boss.Humanoid = nil, nil
				boss.RespawnAt = now
				changed = true
			end
		end
		if not boss.Model and now >= (boss.RespawnAt or 0) and #playersNear(boss.Home, cfg.WakeRange) > 0 then
			changed = spawn(boss) or changed
		end
		if boss.Model and boss.Humanoid and boss.Humanoid.Health > 0 and cfg.Ability == "Syringe" and now >= boss.NextAbility then
			boss.NextAbility = now + cfg.AbilityEvery
			local root = boss.Model:FindFirstChild("HumanoidRootPart")
			local near = root and playersNear(root.Position, cfg.AbilityRange) or {}
			if near[1] then
				throwSyringe(boss, near[1])
			end
		end
	end
	if changed then
		publish()
	end
end

-- ---------- Schnittstelle ----------

function BossService.All()
	return bosses
end

-- Boss sofort erscheinen lassen (Admin, Tests); gibt das Modell zurück
function BossService.SpawnNow(id)
	local boss = bosses[id]
	if not boss then
		return nil
	end
	if boss.Model then
		return boss.Model
	end
	spawn(boss)
	return boss.Model
end

-- opts = { Map, Players(), InSafeZone(position) }
function BossService.Init(opts)
	options = opts
	local places = opts.Map:FindFirstChild("Places")
	for id, cfg in ExtinctionConfig.Bosses do
		local place = places and places:FindFirstChild("Place_" .. cfg.Place)
		if place and place:IsA("BasePart") then
			bosses[id] = { Id = id, Config = cfg, Home = place.Position, RespawnAt = 0 }
		end
	end
	publish()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		local ok, err = pcall(tick, os.clock())
		if not ok then
			warn("Bosse: " .. tostring(err))
		end
	end)
end

return BossService

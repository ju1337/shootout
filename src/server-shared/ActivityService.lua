-- ActivityService (ModuleScript, nur Server)
-- Dinge zum Tun in der offenen Welt (EXTINCTION). Die Karte legt unsichtbare Teile "Act_<Art>" in die Gruppe Activities
-- (Attribut Title = Name des Ortes). Werte in ExtinctionConfig.Activities.
--   Nest   Zombienest (Modell mit Humanoid, man schießt darauf). Solange es lebt und Spieler in der Nähe sind, kriechen
--          Zombies heraus. Zerstört: alle, die Schaden gemacht haben, bekommen Münzen und Beute direkt ins Inventar.
--          Wächst nach Respawn Sekunden nach.
--   Cache  Vorratslager: E halten zum Aufbrechen, der Lärm lockt Zombies an; Beute direkt ins Inventar, danach leer
--          bis zum Respawn. In roten Zonen bessere Beute.
--   Radio  Funkgerät (Funkturm): E halten = Notruf, ein Lootdrop wird angefordert (Abklingzeit).
--   Horde  Sammelpunkte für Horden: regelmäßig zieht eine Horde in einen Ort in der Nähe der Spieler. Wer dabei ist
--          (Range) und genug von ihr erledigt (Win), bekommt Münzen und Beute.
-- Für die Clients steht alles als JSON im Karten-Attribut "Activities": [{ Id, Kind, Title, X, Z, State, Ends, Left }]
-- (State: Active/Cleared bei Nestern, Ready/Opened bei Lagern, Ready/Cooldown beim Funk, Active bei der Horde).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local LootService = require(script.Parent.LootService)
local ZombieService = require(script.Parent.ZombieService)
local ProgressService = require(script.Parent.ProgressService)
local InventoryService = require(script.Parent.InventoryService)
local AirdropService = require(script.Parent.AirdropService)
local Damage = require(script.Parent.Damage)

local ActivityService = {}

local A = ExtinctionConfig.Activities
local random = Random.new()
local options = nil   -- { Map, Players() -> { Player }, InSafeZone(position) -> bool, RedzoneAt(position) -> Zone | nil }
local spots = {}      -- { Id, Kind, Title, Position, State, ReadyAt, Model, ... }
local horde = nil     -- laufende Horde { Spot, Models, Total, Killed, Ends, Participants }
local nextHorde = math.huge
local folder = workspace:FindFirstChild("ExtinctionActivities") or Instance.new("Folder")
folder.Name = "ExtinctionActivities"
folder.Parent = workspace

local function now()
	return os.clock()
end

local function announce(list, title, sub, style)
	for _, player in list do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Ereignis", Title = title, Sub = sub, Style = style or "Info" })
	end
end

local function publish()
	if not options then
		return
	end
	local list = {}
	for _, spot in spots do
		table.insert(list, { Id = spot.Id, Kind = spot.Kind, Title = spot.Title, X = spot.Position.X, Z = spot.Position.Z,
			State = spot.State })
	end
	if horde then
		table.insert(list, { Id = "Horde", Kind = "Horde", Title = horde.Spot.Title, X = horde.Spot.Position.X,
			Z = horde.Spot.Position.Z, State = "Active", Left = horde.Total - horde.Killed,
			Ends = workspace:GetServerTimeNow() + math.max(0, horde.Ends - now()) })
	end
	options.Map:SetAttribute("Activities", HttpService:JSONEncode(list))
end

local function livingRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return root
	end
	return nil
end

-- Spieler draußen (nicht in der Safe Zone) im Umkreis
local function playersNear(position, range)
	local list = {}
	for _, player in options.Players() do
		local root = livingRoot(player)
		if root and not options.InSafeZone(root.Position)
			and Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z).Magnitude <= range then
			table.insert(list, player)
		end
	end
	return list
end

local function roll(spot, cfg)
	local red = options.RedzoneAt and options.RedzoneAt(spot.Position)
	return ExtinctionConfig.RollLoot(red and cfg.RedTable or cfg.Table, random:NextInteger(cfg.Items[1], cfg.Items[2]), random)
end

local function part(model, name, size, cframe, color, material, shape, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide ~= false
	if shape then
		p.Shape = shape
	end
	p.CFrame = cframe
	p.Parent = model
	return p
end

local function billboard(adornee, title, color, offset)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(200, 38)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.MaxDistance = 120
	gui.AlwaysOnTop = true
	gui.Parent = adornee
	local text = Instance.new("TextLabel")
	text.Name = "Title"
	text.Size = UDim2.new(1, 0, 0.55, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 14
	text.TextColor3 = color
	text.TextStrokeTransparency = 0.4
	text.Text = title
	text.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Position = UDim2.fromScale(0, 0.55)
	sub.Size = UDim2.new(1, 0, 0.45, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 11
	sub.TextColor3 = Color3.fromRGB(220, 224, 230)
	sub.TextStrokeTransparency = 0.5
	sub.Text = ""
	sub.Parent = gui
	return text, sub
end

local function prompt(parent, action, object, hold)
	local p = Instance.new("ProximityPrompt")
	p.Name = "ActivityPrompt"
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.HoldDuration = hold
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- Darf der Spieler gerade etwas an diesem Spot tun? (lebt, offene Welt, nah dran)
local function canUse(player, spot)
	local root = livingRoot(player)
	return root ~= nil and Modes.IsSurvival(player:GetAttribute("Mode"))
		and (root.Position - spot.Position).Magnitude <= 14
end

-- ---------- Zombienest ----------

local function buildNest(spot)
	local cfg = A.Nest
	local model = Instance.new("Model")
	model.Name = "ZombieNest"
	local base = CFrame.new(spot.Position)
	local root = part(model, "HumanoidRootPart", Vector3.new(7, 6, 7), base * CFrame.new(0, 3, 0), Color3.fromRGB(70, 30, 34),
		Enum.Material.Slate)
	root.Transparency = 1
	local core = part(model, "Head", Vector3.new(4, 4, 4), base * CFrame.new(0, 3.4, 0), Color3.fromRGB(150, 220, 70),
		Enum.Material.Neon, Enum.PartType.Ball)
	core.Transparency = 0.15
	for k = 1, 7 do
		local angle = k / 7 * math.pi * 2
		local size = random:NextNumber(3.5, 6)
		part(model, "Flesh", Vector3.new(size, size, size), base * CFrame.new(math.cos(angle) * 3.4, size * 0.3, math.sin(angle) * 3.4),
			Color3.fromRGB(random:NextInteger(70, 100), random:NextInteger(30, 46), random:NextInteger(32, 44)), Enum.Material.Slate,
			Enum.PartType.Ball)
	end
	for k = 1, 5 do
		local angle = k / 5 * math.pi * 2 + 0.4
		part(model, "Tendril", Vector3.new(0.9, random:NextNumber(4, 7), 0.9),
			base * CFrame.new(math.cos(angle) * 6, 1.2, math.sin(angle) * 6) * CFrame.Angles(math.rad(random:NextInteger(-60, 60)), 0,
				math.rad(random:NextInteger(-60, 60))), Color3.fromRGB(60, 34, 30), Enum.Material.Slate)
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 230, 80)
	light.Range = 22
	light.Brightness = 1.4
	light.Parent = core
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(120, 160, 70)
	smoke.Opacity = 0.18
	smoke.RiseVelocity = 3
	smoke.Size = 6
	smoke.Parent = core
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.MaxHealth = cfg.Health
	humanoid.Health = cfg.Health
	humanoid.Parent = model
	model.PrimaryPart = root
	local _, sub = billboard(core, "ZOMBIENEST", Color3.fromRGB(170, 230, 90), 5)
	sub.Text = cfg.Health .. " / " .. cfg.Health
	humanoid.HealthChanged:Connect(function(health)
		sub.Text = math.max(0, math.ceil(health)) .. " / " .. cfg.Health
	end)
	model:SetAttribute("Activity", spot.Id)
	model.Parent = folder
	spot.Model = model
	spot.Humanoid = humanoid
	spot.State = "Active"
	spot.NextSpawn = 0
	humanoid.Died:Once(function()
		-- erst nach dem Treffer auswerten (Damage merkt sich die Schützen nach dem Setzen der Gesundheit)
		task.defer(ActivityService.DestroyNest, spot)
	end)
end

-- Nest zerstört: Belohnung für alle, die Schaden gemacht haben
function ActivityService.DestroyNest(spot)
	if spot.State ~= "Active" then
		return
	end
	local cfg = A.Nest
	spot.State = "Cleared"
	spot.ReadyAt = now() + cfg.Respawn
	local model = spot.Model
	local rewarded = {}
	for player, dealt in Damage.Contributors(model) do
		if typeof(player) == "Instance" and player.Parent and dealt > 0 and Modes.IsSurvival(player:GetAttribute("Mode")) then
			ProgressService.AddCoins(player, cfg.Coins, "Nest")
			LootService.Grab(player, roll(spot, cfg))
			table.insert(rewarded, player)
		end
	end
	announce(rewarded, "ZOMBIENEST ZERSTÖRT", spot.Title .. " · +" .. cfg.Coins .. " Münzen und Beute", "Good")
	if model then
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") then
				child.Color = Color3.fromRGB(40, 30, 28)
				child.Material = Enum.Material.Slate
			end
		end
		task.delay(3, function()
			if model.Parent then
				model:Destroy()
			end
		end)
	end
	spot.Model, spot.Humanoid = nil, nil
	publish()
end

local function nestStep(spot, t)
	if spot.State == "Cleared" then
		if t >= spot.ReadyAt then
			buildNest(spot)
			publish()
		end
		return
	end
	local cfg = A.Nest
	if t < (spot.NextSpawn or 0) or #playersNear(spot.Position, cfg.ActiveRange) == 0 then
		return
	end
	spot.NextSpawn = t + cfg.SpawnEvery
	local around = 0
	for _, zombie in ZombieService.All() do
		local root = zombie:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - spot.Position).Magnitude <= cfg.SpawnMax + 20 then
			around += 1
		end
	end
	if around < cfg.MaxAround then
		ZombieService.SpawnAround(spot.Position, 1, cfg.SpawnMin, cfg.SpawnMax, nil, true)
	end
end

-- ---------- Vorratslager ----------

local function setCacheLook(spot, open)
	local lid = spot.Model and spot.Model:FindFirstChild("Lid")
	if lid then
		lid.CFrame = spot.LidClosed * (open and CFrame.new(0, 1.2, 1.8) * CFrame.Angles(math.rad(-70), 0, 0) or CFrame.new())
	end
	local lock = spot.Model and spot.Model:FindFirstChild("Lock")
	if lock then
		lock.Transparency = open and 1 or 0
	end
	if spot.Prompt then
		spot.Prompt.Enabled = not open
	end
	if spot.SubText then
		spot.SubText.Text = open and "LEER · KOMMT WIEDER" or "E HALTEN · LAUT!"
	end
end

local function buildCache(spot)
	local model = Instance.new("Model")
	model.Name = "SupplyCache"
	local base = CFrame.new(spot.Position) * CFrame.Angles(0, spot.Yaw or 0, 0)
	part(model, "Box", Vector3.new(6, 3, 3.6), base * CFrame.new(0, 1.5, 0), Color3.fromRGB(70, 82, 56), Enum.Material.DiamondPlate)
	spot.LidClosed = base * CFrame.new(0, 3.2, 0)
	part(model, "Lid", Vector3.new(6.2, 0.4, 3.8), spot.LidClosed, Color3.fromRGB(60, 70, 48), Enum.Material.DiamondPlate)
	part(model, "Lock", Vector3.new(0.8, 1, 0.4), base * CFrame.new(0, 2.4, -1.95), Color3.fromRGB(200, 170, 60), Enum.Material.Metal)
	part(model, "Stripe", Vector3.new(6.05, 0.5, 3.65), base * CFrame.new(0, 2.2, 0), Color3.fromRGB(220, 180, 40), Enum.Material.SmoothPlastic)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 210, 90)
	glow.Range = 10
	glow.Brightness = 0.7
	glow.Parent = model.Box
	local _, sub = billboard(model.Box, "VORRATSLAGER", Color3.fromRGB(255, 214, 110), 3.6)
	spot.SubText = sub
	local p = prompt(model.Box, "Aufbrechen", "Vorratslager", A.Cache.HoldTime)
	spot.Prompt = p
	model.Parent = folder
	spot.Model = model
	-- schon beim Anfangen macht das Aufbrechen Lärm
	local ok = pcall(function()
		p.PromptButtonHoldBegan:Connect(function(player)
			if spot.State == "Ready" and canUse(player, spot) and now() - (spot.AlarmAt or -100) > 30 then
				spot.AlarmAt = now()
				ZombieService.SpawnAround(spot.Position, A.Cache.Alarm, 18, 40, nil, true)
				InventoryService.Status(player, "Der Lärm lockt Zombies an!")
			end
		end)
	end)
	if not ok then
		spot.NoHoldSignal = true
	end
	p.Triggered:Connect(function(player)
		ActivityService.OpenCache(player, spot)
	end)
	spot.State = "Ready"
	setCacheLook(spot, false)
end

function ActivityService.OpenCache(player, spot)
	if spot.State ~= "Ready" or not canUse(player, spot) then
		return false
	end
	spot.State = "Opened"
	spot.ReadyAt = now() + A.Cache.Respawn
	LootService.Grab(player, roll(spot, A.Cache))
	if now() - (spot.AlarmAt or -100) > 30 then
		spot.AlarmAt = now()
		ZombieService.SpawnAround(spot.Position, A.Cache.Alarm, 18, 40, nil, true)
	end
	setCacheLook(spot, true)
	publish()
	return true
end

local function cacheStep(spot, t)
	if spot.State == "Opened" and t >= spot.ReadyAt then
		spot.State = "Ready"
		setCacheLook(spot, false)
		publish()
	end
end

-- ---------- Funkgerät ----------

local function buildRadio(spot)
	local model = Instance.new("Model")
	model.Name = "RadioStation"
	local base = CFrame.new(spot.Position) * CFrame.Angles(0, spot.Yaw or 0, 0)
	part(model, "Table", Vector3.new(5, 0.4, 3), base * CFrame.new(0, 3, 0), Color3.fromRGB(96, 76, 56), Enum.Material.WoodPlanks)
	for _, offset in { Vector3.new(-2.2, 1.4, -1.2), Vector3.new(2.2, 1.4, -1.2), Vector3.new(-2.2, 1.4, 1.2), Vector3.new(2.2, 1.4, 1.2) } do
		part(model, "Leg", Vector3.new(0.3, 2.8, 0.3), base * CFrame.new(offset), Color3.fromRGB(80, 64, 48), Enum.Material.Wood)
	end
	local radio = part(model, "Radio", Vector3.new(2.6, 1.4, 1.6), base * CFrame.new(0, 3.9, 0), Color3.fromRGB(60, 70, 52), Enum.Material.Metal)
	part(model, "Antenna", Vector3.new(0.15, 4, 0.15), base * CFrame.new(1, 6.4, 0.4), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
	local lamp = part(model, "Lamp", Vector3.new(0.4, 0.4, 0.4), base * CFrame.new(-0.8, 4.7, -0.8), Color3.fromRGB(90, 255, 120), Enum.Material.Neon)
	spot.Lamp = lamp
	local _, sub = billboard(radio, "FUNKGERÄT", Color3.fromRGB(120, 200, 255), 3)
	spot.SubText = sub
	local p = prompt(radio, "Notruf senden", "Funkgerät", A.Radio.HoldTime)
	spot.Prompt = p
	p.Triggered:Connect(function(player)
		ActivityService.UseRadio(player, spot)
	end)
	model.Parent = folder
	spot.Model = model
	spot.State = "Ready"
	spot.ReadyAt = 0
end

local function radioLook(spot)
	local ready = spot.State == "Ready"
	if spot.Lamp then
		spot.Lamp.Color = ready and Color3.fromRGB(90, 255, 120) or Color3.fromRGB(255, 70, 50)
	end
	if spot.SubText then
		spot.SubText.Text = ready and "E HALTEN · LOOTDROP ANFORDERN"
			or ("BEREIT IN " .. math.ceil(math.max(0, spot.ReadyAt - now()) / 60) .. " MIN")
	end
end

function ActivityService.UseRadio(player, spot)
	if not canUse(player, spot) then
		return false
	end
	if spot.State ~= "Ready" then
		InventoryService.Status(player, "Das Funkgerät lädt noch.")
		return false
	end
	if #AirdropService.Active() > 0 then
		InventoryService.Status(player, "Es ist schon ein Lootdrop unterwegs.")
		return false
	end
	local drop = AirdropService.Start(nil)
	if not drop then
		InventoryService.Status(player, "Keine Antwort. Versuch es gleich nochmal.")
		return false
	end
	spot.State = "Cooldown"
	spot.ReadyAt = now() + A.Radio.Cooldown
	radioLook(spot)
	announce(options.Players(), "NOTRUF EMPFANGEN", player.Name .. " hat einen Versorgungsabwurf angefordert", "Info")
	publish()
	return true
end

local function radioStep(spot, t)
	if spot.State == "Cooldown" and t >= spot.ReadyAt then
		spot.State = "Ready"
		publish()
	end
	radioLook(spot)
end

-- ---------- Horde ----------

local function hordeSpots()
	local list = {}
	for _, spot in spots do
		if spot.Kind == "Horde" then
			table.insert(list, spot)
		end
	end
	return list
end

-- Ort für die nächste Horde: in passender Entfernung zu einem Spieler draußen
local function pickHordeSpot()
	local cfg = A.Horde
	local outside = playersNear(Vector3.zero, math.huge)
	if #outside == 0 then
		return nil
	end
	local player = outside[random:NextInteger(1, #outside)]
	local root = livingRoot(player)
	if not root then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, spot in hordeSpots() do
		local distance = Vector3.new(spot.Position.X - root.Position.X, 0, spot.Position.Z - root.Position.Z).Magnitude
		if distance >= cfg.MinDistance and distance <= cfg.MaxDistance and distance < bestDistance
			and not options.InSafeZone(spot.Position) then
			best, bestDistance = spot, distance
		end
	end
	return best
end

function ActivityService.StartHorde(spot)
	local cfg = A.Horde
	if horde then
		return nil
	end
	spot = spot or pickHordeSpot()
	if not spot then
		return nil
	end
	local models = ZombieService.SpawnAround(spot.Position, math.ceil(cfg.Size * 0.7), 15, 55, nil, true)
	for _, model in ZombieService.SpawnAround(spot.Position, math.floor(cfg.Size * 0.3), 15, 55, "Runner", true) do
		table.insert(models, model)
	end
	if #models == 0 then
		return nil
	end
	horde = { Spot = spot, Models = models, Total = #models, Killed = 0, Ends = now() + cfg.Duration, Participants = {} }
	for _, model in models do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Once(function()
				if horde and table.find(horde.Models, model) then
					local hit = Damage.LastHit(model)
					if hit and hit.Model and Players:GetPlayerFromCharacter(hit.Model) then
						horde.Killed += 1
					end
				end
			end)
		end
	end
	announce(options.Players(), "HORDE IM ANMARSCH", spot.Title .. " · " .. #models .. " Zombies · besiegt sie für Belohnungen", "Warning")
	publish()
	return horde
end

local function endHorde(won)
	local cfg = A.Horde
	local current = horde
	horde = nil
	nextHorde = now() + random:NextNumber(cfg.MinInterval, cfg.MaxInterval)
	if not current then
		return
	end
	local list = {}
	for player in current.Participants do
		if player.Parent then
			table.insert(list, player)
			if won then
				ProgressService.AddCoins(player, cfg.Coins, "Horde")
				LootService.Grab(player, roll(current.Spot, cfg))
			end
		end
	end
	if won then
		announce(list, "HORDE BESIEGT", current.Spot.Title .. " · +" .. cfg.Coins .. " Münzen und Beute", "Good")
	else
		announce(list, "DIE HORDE ZIEHT WEITER", current.Spot.Title, "Info")
	end
	publish()
end

local function hordeStep(t)
	local cfg = A.Horde
	if not horde then
		if t >= nextHorde then
			if not ActivityService.StartHorde() then
				nextHorde = t + 60 -- keiner draußen oder kein passender Ort: bald nochmal
			end
		end
		return
	end
	for _, player in playersNear(horde.Spot.Position, cfg.Range) do
		horde.Participants[player] = true
	end
	local alive = 0
	for _, model in horde.Models do
		local humanoid = model.Parent and model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			alive += 1
		end
	end
	if alive == 0 or t >= horde.Ends then
		endHorde(horde.Killed >= math.ceil(horde.Total * cfg.Win))
	end
end

-- ---------- Ablauf ----------

function ActivityService.Spots()
	return spots
end

function ActivityService.Horde()
	return horde
end

function ActivityService.Step()
	local t = now()
	for _, spot in spots do
		if spot.Kind == "Nest" then
			nestStep(spot, t)
		elseif spot.Kind == "Cache" then
			cacheStep(spot, t)
		elseif spot.Kind == "Radio" then
			radioStep(spot, t)
		end
	end
	hordeStep(t)
	publish()
end

-- opts = { Map, Players(), InSafeZone(position), RedzoneAt(position) }
function ActivityService.Init(opts)
	options = opts
	spots = {}
	horde = nil
	nextHorde = now() + A.Horde.FirstDelay
	folder:ClearAllChildren()
	local group = options.Map:FindFirstChild("Activities")
	local n = 0
	for _, marker in group and group:GetChildren() or {} do
		local kind = marker:IsA("BasePart") and string.match(marker.Name, "^Act_([A-Za-z]+)")
		if kind and (A[kind] or kind == "Horde") then
			n += 1
			local _, yaw = marker.CFrame:ToOrientation()
			local spot = { Id = kind .. n, Kind = kind, Title = marker:GetAttribute("Title") or kind,
				Position = Vector3.new(marker.Position.X, marker.Position.Y - marker.Size.Y / 2, marker.Position.Z), Yaw = yaw,
				State = "Ready", ReadyAt = 0 }
			table.insert(spots, spot)
			if kind == "Nest" then
				buildNest(spot)
			elseif kind == "Cache" then
				buildCache(spot)
			elseif kind == "Radio" then
				buildRadio(spot)
			end
		end
	end
	publish()
	local last = 0
	RunService.Heartbeat:Connect(function()
		local t = now()
		if t - last >= 1 then
			last = t
			ActivityService.Step()
		end
	end)
end

return ActivityService

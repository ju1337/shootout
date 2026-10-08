-- HordeService (ModuleScript, nur Server)
-- Horden-Kiste der offenen Welt (Werte in ExtinctionConfig.Horde): Eine verriegelte Versorgungskiste mit Signalfeuer steht
-- irgendwo draußen. E halten startet die Belagerung; solange Spieler in der Nähe bleiben, läuft der Fortschritt (Balken über
-- der Kiste), und es kommen drei Wellen Zombies, jede stärker. Bei 100 % springt die Kiste auf (Beute wie eine Militärkiste plus
-- Lootdrop-Beute) und alle, die mitgehalten haben, bekommen Münzen. Wer weggeht, hält den Fortschritt an; bleibt zu lange
-- niemand da, fällt er auf 0 zurück.
-- Stand für Karte und Clients: Karten-Attribut "Hordes" [{ Id, X, Z, State ("Locked"/"Siege"), Progress (0..1), Wave }].

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sfx = require(Shared.Sfx)
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local LootService = require(script.Parent.LootService)
local ZombieService = require(script.Parent.ZombieService)

local HordeService = {}

local H = ExtinctionConfig.Horde
local random = Random.new()
local options = nil -- { Map, Players(), InSafeZone(position), PickTarget() -> Vector3?, Reward(player, coins, text) }
local current = nil -- { Id, Position, Model, Bar, Text, State, Progress, Wave, Idle, Ends, Holders }
local nextAt = 0
local nextId = 0
local folder = workspace:FindFirstChild("ExtinctionHordes") or Instance.new("Folder")
folder.Name = "ExtinctionHordes"
folder.Parent = workspace

local function announce(title, sub, style)
	for _, player in options.Players() do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Horde", Title = title, Sub = sub, Style = style or "Info" })
	end
end

local function publish()
	local list = {}
	if current then
		table.insert(list, { Id = current.Id, X = current.Position.X, Z = current.Position.Z, State = current.State,
			Progress = math.floor(current.Progress * 100) / 100, Wave = current.Wave })
	end
	options.Map:SetAttribute("Hordes", HttpService:JSONEncode(list))
end

local function part(model, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanQuery = false
	p.CanTouch = false
	p.CFrame = cframe
	p.Parent = model
	return p
end

-- Kiste mit Ketten, Signalfeuer (rot) daneben, Balken und Text darüber
local function build(position)
	local model = Instance.new("Model")
	model.Name = "HordeCrate"
	local base = CFrame.new(position)
	local crate = part(model, "Crate", Vector3.new(6, 4, 4), base * CFrame.new(0, 2, 0), Color3.fromRGB(70, 84, 56), Enum.Material.Metal)
	model.PrimaryPart = crate
	part(model, "Lid", Vector3.new(6.2, 0.6, 4.2), base * CFrame.new(0, 4.3, 0), Color3.fromRGB(56, 68, 46), Enum.Material.Metal)
	for _, x in { -1.8, 1.8 } do
		part(model, "Chain", Vector3.new(0.3, 4.4, 4.4), base * CFrame.new(x, 2.2, 0), Color3.fromRGB(150, 150, 146), Enum.Material.DiamondPlate)
	end
	part(model, "Lock", Vector3.new(1, 1.2, 0.5), base * CFrame.new(0, 2.6, -2.2), Color3.fromRGB(200, 170, 60), Enum.Material.Metal)
	for _, offset in { Vector3.new(5, 0, 3), Vector3.new(-5, 0, -3) } do
		local flare = part(model, "Flare", Vector3.new(0.5, 1.2, 0.5), base * CFrame.new(offset + Vector3.new(0, 0.6, 0)),
			Color3.fromRGB(255, 60, 40), Enum.Material.Neon)
		flare.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 70, 50)
		light.Range = 24
		light.Brightness = 2.5
		light.Parent = flare
		Sfx.Loop("FlareLoop", flare, { Volume = 0.7 }) -- Signalfeuer zischt
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(200, 40, 30)
		smoke.Opacity = 0.35
		smoke.RiseVelocity = 8
		smoke.Size = 3
		smoke.Parent = flare
	end
	-- Umkreis am Boden (so nah muss man bleiben)
	local ring = part(model, "Ring", Vector3.new(0.2, H.Radius * 2, H.Radius * 2), base * CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(220, 60, 50), Enum.Material.Neon)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.85
	ring.CanCollide = false
	-- Anzeige über der Kiste
	local gui = Instance.new("BillboardGui")
	gui.Name = "Status"
	gui.Size = UDim2.fromOffset(240, 54)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.Parent = crate
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.new(1, 0, 0, 24)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.BuilderSansExtraBold
	text.TextSize = 16
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.4
	text.Parent = gui
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(20, 30)
	track.Size = UDim2.new(1, -40, 0, 8)
	track.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	track.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(214, 58, 58)
	fill.BorderSizePixel = 0
	fill.Parent = track
	-- E halten startet die Belagerung
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HordePrompt"
	prompt.ActionText = "Belagerung starten"
	prompt.ObjectText = "Horden-Kiste"
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = crate
	model.Parent = folder
	return model, text, fill, prompt
end

local function refreshLabel()
	if not current then
		return
	end
	current.Fill.Size = UDim2.fromScale(current.Progress, 1)
	if current.State == "Locked" then
		current.Text.Text = "HORDEN-KISTE · E HALTEN"
	else
		current.Text.Text = string.format("%d %% · WELLE %d/%d%s", math.floor(current.Progress * 100), current.Wave, #H.Waves,
			current.Idle > 0 and " · NIEMAND DA" or "")
	end
end

local function remove()
	if current and current.Model then
		current.Model:Destroy()
	end
	current = nil
	nextAt = os.clock() + random:NextNumber(H.MinInterval, H.MaxInterval)
	publish()
end

-- Spieler im Umkreis (lebend, nicht im Fahrzeug)
local function holders()
	local list = {}
	for _, player in options.Players() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 and not humanoid.SeatPart
			and (root.Position - current.Position).Magnitude <= H.Radius then
			table.insert(list, player)
		end
	end
	return list
end

-- Art einer Welle würfeln
local function rollKind(weights)
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll = random:NextNumber(0, total)
	for kind, weight in weights do
		roll -= weight
		if roll <= 0 then
			return kind
		end
	end
	return nil
end

local function spawnWave(index)
	local wave = H.Waves[index]
	current.Wave = index
	Sfx.At("WaveSting", current.Position + Vector3.new(0, 3, 0))
	for _ = 1, wave.Count do
		ZombieService.SpawnAround(current.Position, 1, H.SpawnMin, H.SpawnMax, rollKind(wave.KindWeights), true)
	end
	announce("WELLE " .. index .. " VON " .. #H.Waves, wave.Count .. " Zombies kommen auf die Horden-Kiste zu", "Warning")
end

local function open()
	local position = current.Position
	local items = ExtinctionConfig.RollLoot(H.Table, random:NextInteger(H.Items[1], H.Items[2]), random)
	for _, item in ExtinctionConfig.RollLoot(H.BonusTable, random:NextInteger(H.BonusItems[1], H.BonusItems[2]), random) do
		table.insert(items, item)
	end
	for player in current.Holders do
		if player.Parent and options.Reward then
			options.Reward(player, H.Coins, "Horden-Kiste")
		end
	end
	if current.Model then
		current.Model:Destroy()
		current.Model = nil
	end
	LootService.Create(position + Vector3.new(0, 1, 0), items, "Airdrop", "HORDEN-KISTE", { HoldTime = 2, Lifetime = 300 })
	announce("HORDEN-KISTE OFFEN", "Die Horde ist zurückgeschlagen · Beute liegt bereit", "Info")
	remove()
end

local function tick(now, dt)
	if not current then
		if H.Enabled and now >= nextAt then
			local outside = 0
			for _, player in options.Players() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and not options.InSafeZone(root.Position) then
					outside += 1
				end
			end
			if outside >= H.MinPlayers then
				HordeService.Start()
			else
				nextAt = now + 30
			end
		end
		return
	end
	if current.State == "Locked" then
		if now >= current.Ends then
			remove()
		end
		return
	end
	local here = holders()
	if #here > 0 then
		current.Idle = 0
		for _, player in here do
			current.Holders[player] = true
		end
		current.Progress = math.min(1, current.Progress + dt * (1 + 0.5 * (#here - 1)) / H.HoldTime)
		-- nächste Welle bei ihrem Anteil
		local nextWave = H.Waves[current.Wave + 1]
		if nextWave and current.Progress >= nextWave.At then
			spawnWave(current.Wave + 1)
		end
		if current.Progress >= 1 then
			open()
			return
		end
	else
		current.Idle += dt
		if current.Idle >= H.PauseLimit then
			-- zu lange niemand da: von vorn, Kiste wieder verriegelt
			current.State = "Locked"
			current.Progress = 0
			current.Wave = 0
			current.Idle = 0
			current.Ends = now + H.Lifetime
			current.Prompt.Enabled = true
			announce("BELAGERUNG ABGEBROCHEN", "Niemand hat die Horden-Kiste gehalten", "Warning")
		end
	end
	refreshLabel()
end

-- ---------- Schnittstelle ----------

-- Horden-Kiste aufstellen (position optional, sonst zufällig). Gibt den Stand zurück (nil, wenn schon eine steht).
function HordeService.Start(position)
	if current or not options then
		return nil
	end
	position = position or (options.PickTarget and options.PickTarget())
	if not position then
		nextAt = os.clock() + 30
		return nil
	end
	nextId += 1
	local model, text, fill, prompt = build(position)
	current = { Id = nextId, Position = position, Model = model, Text = text, Fill = fill, Prompt = prompt, State = "Locked",
		Progress = 0, Wave = 0, Idle = 0, Ends = os.clock() + H.Lifetime, Holders = {} }
	local horde = current
	prompt.Triggered:Connect(function(player)
		HordeService.Begin(player, horde)
	end)
	refreshLabel()
	publish()
	announce("HORDEN-KISTE", "Eine verriegelte Kiste mit Signalfeuer · Markierung auf der Karte (N) · halte sie gegen die Horde")
	return current
end

-- Belagerung beginnen (E an der Kiste)
function HordeService.Begin(player, horde)
	horde = horde or current
	if not horde or horde ~= current or current.State ~= "Locked" then
		return false
	end
	current.State = "Siege"
	current.Holders[player] = true
	current.Prompt.Enabled = false
	if current.Model and current.Model.PrimaryPart then
		Sfx.At("Siren", current.Model.PrimaryPart) -- Belagerung beginnt
	end
	spawnWave(1)
	refreshLabel()
	publish()
	return true
end

function HordeService.Current()
	return current
end

-- opts = { Map, Players(), InSafeZone(position), PickTarget() -> Vector3?, Reward(player, coins, text) }
function HordeService.Init(opts)
	options = opts
	nextAt = os.clock() + H.FirstDelay
	publish()
	local elapsed, lastPublish = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		local step = elapsed
		elapsed = 0
		local now = os.clock()
		local ok, err = pcall(tick, now, step)
		if not ok then
			warn("Horden-Kiste: " .. tostring(err))
		end
		if current and current.State == "Siege" and now - lastPublish >= 1 then
			lastPublish = now
			publish()
		end
	end)
end

return HordeService

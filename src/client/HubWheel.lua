-- HubWheel (ModuleScript, nur Client)
-- Das Glücksrad steht als großes Rad in der Einsatzzentrale im Camp (Teil "WheelSpot" der Gruppe Zentrale, siehe
-- Shared/Zentrale: Mitte des Rads, LookVector = Vorderseite). Podest, Ständer und Schild kommen aus der Map, das Rad baut dieses Modul lokal:
-- acht farbige Felder (LoginConfig.Wheel) aus Keilen, goldene Trennstege, Beschriftung, Nabe, Rand mit
-- Lichtern und oben ein Zeiger. Am Pult davor ("WheelConsole") öffnet E bzw. Antippen den Dreh: der Server lost
-- das Feld aus (ShopAction "SpinWheel" -> Remotes.WheelResult), das Rad dreht ein paar Runden und bleibt genau
-- dort stehen, der Zeiger klackt an jedem Steg, die Lichter laufen mit, danach blinkt das Gewinnfeld und eine
-- Belohnungs-Karte erscheint. Die Tafel auf dem Pult ("WheelBoard") zeigt, ob ein Gratis- oder Extra-Dreh bereit
-- ist bzw. wann der nächste kommt. Einmal am Tag gratis, dazu Extra-Drehs (Login-Kalender, Robux-Shop).
-- Weil man Drehs für Robux kaufen kann, steht auf jedem Feld seine Chance, und am Pult öffnet Q (bzw. Antippen des
-- zweiten Knopfs) das Fenster CHANCEN mit allen Gewinnen (OddsPanel, Roblox-Regeln für bezahlte Zufallsitems).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local LoginConfig = require(Shared.LoginConfig)
local Cosmetics = require(Shared.Cosmetics)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)
local Notifications = require(Shared.Notifications)
local PaidRandom = require(Shared.PaidRandom)
local OddsPanel = require(Shared.OddsPanel)
local Zentrale = require(Shared.Zentrale)

local player = Players.LocalPlayer

local HubWheel = {}

HubWheel.Radius = 6
local SLICE_COUNT = #LoginConfig.Wheel
local SLICE = 360 / SLICE_COUNT       -- Grad pro Feld
local SUB = 3                          -- Dreiecke pro Feld (Rand fast rund)
local SPIN_TIME = 5.6                  -- Sekunden vom Anstoß bis zum Stillstand
local SPIN_TURNS = 4                   -- mindestens so viele volle Runden
local BULBS = 20
local GOLD = Color3.fromRGB(212, 170, 80)
local DARK = Color3.fromRGB(24, 27, 32)
local STEEL = Color3.fromRGB(52, 57, 66)
local TICK_SOUND = "rbxasset://sounds/clickfast.wav"
local WIN_SOUND = "rbxasset://sounds/electronicpingshort.wav"

-- ---------- Rechnen (auch für die Tests) ----------
-- Drehung in Grad im Uhrzeigersinn (von vorn gesehen). Feld i liegt in Ruhe mit seiner Mitte bei (i - 1) * SLICE
-- Grad im Uhrzeigersinn von oben; der Zeiger steht oben.

-- Feld unter dem Zeiger bei Drehung rotation
function HubWheel.IndexAt(rotation)
	return math.floor(-rotation / SLICE + 0.5) % SLICE_COUNT + 1
end

-- Enddrehung, um von current aus mindestens turns volle Runden im Uhrzeigersinn zu drehen und mit Feld index
-- unter dem Zeiger zu halten; jitter (Grad, |jitter| < SLICE / 2) verschiebt den Halt innerhalb des Felds
function HubWheel.TargetRotation(current, index, turns, jitter)
	local base = -(index - 1) * SLICE + (jitter or 0)
	local minimum = current + 360 * (turns or SPIN_TURNS)
	return base + 360 * math.ceil((minimum - base) / 360)
end

-- Dreieck a, b, c (Weltpunkte) aus zwei Keilen: { { Size, CFrame }, { Size, CFrame } }
function HubWheel.Triangle(a, b, c, thickness)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	return {
		{ Size = Vector3.new(thickness, height, math.abs(ab:Dot(back))), CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back) },
		{ Size = Vector3.new(thickness, height, math.abs(ac:Dot(back))), CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back) },
	}
end

-- Ist heute schon gedreht und kein Extra-Dreh da? Gibt (bereit, gratis, extra) zurück
local function wheelState()
	local raw = player:GetAttribute("WheelData")
	local ok, data = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "{}")
	data = ok and type(data) == "table" and data or {}
	local free = data.Date ~= LoginConfig.Date(workspace:GetServerTimeNow())
	local extra = tonumber(data.Spins) or 0
	return free or extra > 0, free, extra
end

local function sound(id, speed, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 2)
end

-- ---------- Bauen ----------

local function part(parent, className, props)
	local p = Instance.new(className)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

-- Rad an spot bauen. Gibt { Spin (Modell, dreht sich), Static (Modell), Face (CFrame), Slices, Bulbs, Pointer,
-- PointerPivot } zurück. Face: x = rechts, y = oben, z = zum Betrachter (Vorderseite).
function HubWheel.Build(spot, parent)
	local R = HubWheel.Radius
	local face = spot.CFrame * CFrame.Angles(0, math.pi, 0)
	local function at(x, y, z)
		return (face * CFrame.new(x, y, z)).Position
	end

	local spin = Instance.new("Model")
	spin.Name = "LuckyWheel"
	local static = Instance.new("Model")
	static.Name = "LuckyWheelFrame"

	-- Scheibe (Zylinder liegt mit seiner Achse entlang z)
	part(spin, "Part", { Name = "Disc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 2 * R + 0.2, 2 * R + 0.2),
		CFrame = face * CFrame.Angles(0, math.pi / 2, 0), Color = DARK, Material = Enum.Material.Metal })

	-- Felder aus je zwei Keilen, Trennstege, Beschriftung mit Chance
	local slices = {}
	local odds = LoginConfig.WheelOdds()
	for i, field in LoginConfig.Wheel do
		local center = (i - 1) * SLICE
		local wedges = {}
		-- je Feld drei schmale Dreiecke, damit der Rand fast rund ist
		for k = 0, SUB - 1 do
			local a0 = math.rad(center - SLICE / 2 + k * SLICE / SUB)
			local a1 = math.rad(center - SLICE / 2 + (k + 1) * SLICE / SUB)
			for _, spec in HubWheel.Triangle(at(0, 0, 0.28), at(math.sin(a0) * R, math.cos(a0) * R, 0.28),
				at(math.sin(a1) * R, math.cos(a1) * R, 0.28), 0.06) do
				table.insert(wedges, part(spin, "WedgePart", { Name = "Slice" .. i, Size = spec.Size, CFrame = spec.CFrame,
					Color = field.Color, Material = Enum.Material.SmoothPlastic }))
			end
		end
		local edge = math.rad(center + SLICE / 2)
		part(spin, "Part", { Name = "Divider", Size = Vector3.new(0.16, R, 0.08), Color = GOLD, Material = Enum.Material.Metal,
			CFrame = face * CFrame.Angles(0, 0, -edge) * CFrame.new(0, R / 2, 0.34) })
		-- Beschriftung entlang des Radius, von der Mitte nach außen lesbar
		local label = part(spin, "Part", { Name = "Label" .. i, Size = Vector3.new(R * 0.56, 1.15, 0.05), Transparency = 1,
			CFrame = face * CFrame.Angles(0, 0, -math.rad(center)) * CFrame.new(0, R * 0.6, 0.36) * CFrame.Angles(0, 0, math.pi / 2) })
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Back
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 60
		surface.LightInfluence = 0.3
		surface.Parent = label
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 0.7)
		text.BackgroundTransparency = 1
		text.Text = field.Text
		text.TextScaled = true
		text.Font = Enum.Font.BuilderSansExtraBold
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextStrokeTransparency = 0.35
		text.Parent = surface
		local chance = Instance.new("TextLabel")
		chance.Name = "Chance"
		chance.Position = UDim2.fromScale(0, 0.68)
		chance.Size = UDim2.fromScale(1, 0.3)
		chance.BackgroundTransparency = 1
		chance.Text = PaidRandom.Percent(odds[i])
		chance.TextScaled = true
		chance.Font = Enum.Font.BuilderSansBold
		chance.TextColor3 = Color3.fromRGB(255, 244, 220)
		chance.TextStrokeTransparency = 0.5
		chance.Parent = surface
		slices[i] = { Wedges = wedges, Color = field.Color }
	end
	-- Nabe
	part(spin, "Part", { Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 2.4, 2.4), Color = GOLD,
		Material = Enum.Material.Metal, CFrame = face * CFrame.new(0, 0, 0.45) * CFrame.Angles(0, math.pi / 2, 0) })
	part(spin, "Part", { Name = "HubCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.56, 1.3, 1.3), Color = DARK,
		Material = Enum.Material.Metal, CFrame = face * CFrame.new(0, 0, 0.5) * CFrame.Angles(0, math.pi / 2, 0) })
	spin.WorldPivot = face

	-- Rand (steht still) mit Lichtern
	part(static, "Part", { Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 2 * R + 1.1, 2 * R + 1.1),
		Color = STEEL, Material = Enum.Material.Metal, CFrame = face * CFrame.new(0, 0, -0.4) * CFrame.Angles(0, math.pi / 2, 0) })
	local bulbs = {}
	for k = 1, BULBS do
		local angle = math.rad((k - 1) * 360 / BULBS)
		bulbs[k] = part(static, "Part", { Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.42, 0.42, 0.42),
			Color = Color3.fromRGB(255, 236, 190), Material = Enum.Material.Neon,
			CFrame = CFrame.new(at(math.sin(angle) * (R + 0.3), math.cos(angle) * (R + 0.3), 0.02)) })
	end
	-- Zeiger oben: Dreieck nach unten, Drehpunkt in der Kugel darüber
	local pointer = Instance.new("Model")
	pointer.Name = "Pointer"
	for _, spec in HubWheel.Triangle(at(-0.8, R + 1.25, 0.62), at(0.8, R + 1.25, 0.62), at(0, R - 0.55, 0.62), 0.22) do
		part(pointer, "WedgePart", { Name = "Arrow", Size = spec.Size, CFrame = spec.CFrame, Color = Color3.fromRGB(236, 239, 243),
			Material = Enum.Material.Metal })
	end
	local pivot = face * CFrame.new(0, R + 1.25, 0.62)
	part(pointer, "Part", { Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), Color = GOLD,
		Material = Enum.Material.Metal, CFrame = pivot })
	pointer.WorldPivot = pivot
	pointer.Parent = static

	static.Parent = parent
	spin.Parent = parent
	return { Spin = spin, Static = static, Face = face, Slices = slices, Bulbs = bulbs, Pointer = pointer, PointerPivot = pivot }
end

-- ---------- Tafel am Pult ----------

local function buildBoard(board)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "WheelBoardGui"
	surface.ResetOnSpawn = false -- liegt im PlayerGui: sonst beim nächsten Spawn gelöscht
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 80
	surface.LightInfluence = 0
	surface.Brightness = 1.4
	surface.Adornee = board
	surface.Parent = player:WaitForChild("PlayerGui")
	local function line(name, y, h, font, color)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Position = UDim2.fromScale(0.05, y)
		label.Size = UDim2.fromScale(0.9, h)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = font
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.6
		label.Text = ""
		label.Parent = surface
		return label
	end
	return {
		Title = line("Title", 0.06, 0.24, Enum.Font.BuilderSansExtraBold, GOLD),
		Status = line("Status", 0.34, 0.34, Enum.Font.BuilderSansExtraBold, Color3.new(1, 1, 1)),
		Hint = line("Hint", 0.72, 0.2, Enum.Font.BuilderSansBold, Color3.fromRGB(170, 178, 190)),
	}
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
end

-- ---------- Start ----------

function HubWheel.Init()
	local decor = Zentrale.Folder(60)
	local spot = decor and decor:WaitForChild("WheelSpot", 60)
	if not decor or not spot then
		return -- Zentrale ohne Glücksrad
	end
	local wheel = HubWheel.Build(spot, workspace)
	local console = decor:FindFirstChild("WheelConsole") or spot
	local boardPart = decor:FindFirstChild("WheelBoard")
	local board = boardPart and buildBoard(boardPart)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drehen"
	prompt.ObjectText = "Glücksrad"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = console

	-- Chancen ansehen (immer möglich, auch ohne Dreh)
	local oddsPrompt = Instance.new("ProximityPrompt")
	oddsPrompt.Name = "OddsPrompt"
	oddsPrompt.ActionText = "Chancen ansehen"
	oddsPrompt.ObjectText = "Glücksrad"
	oddsPrompt.KeyboardKeyCode = Enum.KeyCode.Q
	oddsPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	oddsPrompt.HoldDuration = 0
	oddsPrompt.MaxActivationDistance = 12
	oddsPrompt.RequiresLineOfSight = false
	oddsPrompt.UIOffset = Vector2.new(0, 72)
	oddsPrompt.Parent = console
	oddsPrompt.Triggered:Connect(function()
		OddsPanel.Show("Glücksrad", OddsPanel.WheelRows())
	end)

	local rotation = 0          -- aktuelle Drehung (Grad)
	local spinning = false      -- Rad dreht (oder wartet auf den Server)
	local waitingSince = nil    -- Anfrage geschickt, noch keine Antwort
	local resultText, resultUntil = nil, 0
	local errorText, errorUntil = nil, 0
	local winner = nil          -- Feld, das nach dem Dreh blinkt
	local kick = 0              -- Ausschlag des Zeigers (Grad), klingt ab

	local function apply()
		wheel.Spin:PivotTo(wheel.Face * CFrame.Angles(0, 0, -math.rad(rotation)))
	end
	apply()

	local function refresh()
		local ready, free, extra = wheelState()
		prompt.Enabled = ready and not spinning
		prompt.ActionText = free and "Gratis drehen" or "Extra-Dreh (" .. extra .. ")"
		if not board then
			return
		end
		local now = workspace:GetServerTimeNow()
		board.Title.Text = "GLÜCKSRAD"
		if spinning then
			board.Status.Text = "DREHT ..."
			board.Status.TextColor3 = GOLD
			board.Hint.Text = "VIEL GLÜCK"
		elseif errorText and os.clock() < errorUntil then
			board.Status.Text = errorText
			board.Status.TextColor3 = UITheme.Colors.Bad
			board.Hint.Text = ""
		elseif resultText and os.clock() < resultUntil then
			board.Status.Text = resultText
			board.Status.TextColor3 = UITheme.Colors.Good
			board.Hint.Text = ready and "NOCHMAL: E AM PULT" or "MORGEN GIBT ES DEN NÄCHSTEN GRATIS-DREH"
		elseif ready then
			board.Status.Text = free and "GRATIS-DREH BEREIT" or ("EXTRA-DREH BEREIT  ·  " .. extra)
			board.Status.TextColor3 = Color3.new(1, 1, 1)
			board.Hint.Text = InputActions.IsTouch() and "TIPPE AUF DREHEN" or "E DREHEN  ·  Q CHANCEN"
		else
			board.Status.Text = "NÄCHSTER DREH IN " .. clock(86400 - now % 86400)
			board.Status.TextColor3 = Color3.fromRGB(170, 178, 190)
			board.Hint.Text = "EXTRA-DREHS GIBT ES IM LOGIN-KALENDER"
		end
	end

	prompt.Triggered:Connect(function()
		if spinning or not wheelState() then
			return
		end
		spinning = true
		waitingSince = os.clock()
		winner = nil
		Remotes.ShopAction:FireServer("SpinWheel")
		refresh()
	end)
	-- Abgelehnt (z.B. nicht im Hub): Meldung auf die Tafel, Rad wieder freigeben
	Remotes.ShopStatus.OnClientEvent:Connect(function(message, success)
		if waitingSince and success == false then
			waitingSince = nil
			spinning = false
			errorText, errorUntil = string.upper(tostring(message)), os.clock() + 4
			refresh()
		end
	end)

	Remotes.WheelResult.OnClientEvent:Connect(function(index, text)
		index = math.clamp(math.floor(tonumber(index) or 1), 1, SLICE_COUNT)
		waitingSince = nil
		spinning = true
		refresh()
		local start = rotation
		local target = HubWheel.TargetRotation(start, index, SPIN_TURNS, (math.random() - 0.5) * SLICE * 0.7)
		local began = os.clock()
		local lastBoundary = math.floor((start + SLICE / 2) / SLICE)
		local connection
		connection = RunService.Heartbeat:Connect(function()
			local alpha = math.min((os.clock() - began) / SPIN_TIME, 1)
			rotation = start + (target - start) * TweenService:GetValue(alpha, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			apply()
			-- Klack an jedem Steg, der am Zeiger vorbeikommt
			local boundary = math.floor((rotation + SLICE / 2) / SLICE)
			if boundary ~= lastBoundary then
				lastBoundary = boundary
				kick = 16
				sound(TICK_SOUND, 1.5, 0.35)
			end
			if alpha >= 1 then
				connection:Disconnect()
				rotation = target % 360
				apply()
				spinning = false
				winner = { Index = index, Until = os.clock() + 3 }
				local field = LoginConfig.Wheel[index]
				local jackpot = index == SLICE_COUNT
				sound(WIN_SOUND, jackpot and 1.5 or 1.2, 0.6)
				if jackpot then
					task.delay(0.15, sound, WIN_SOUND, 1.8, 0.6)
					task.delay(0.3, sound, WIN_SOUND, 2.2, 0.6)
				end
				local item = field.Item and Cosmetics.Get(field.Item)
				resultText, resultUntil = "GEWONNEN: " .. string.upper(field.Text), os.clock() + 8
				Notifications.Reward({ Title = "GLÜCKSRAD", Lines = { tostring(text or field.Text) },
					Rarity = jackpot and "Legendary" or (item and item.Rarity) or nil })
				refresh()
			end
		end)
	end)

	-- Lichter: ruhig abwechselnd, beim Drehen ein Lauflicht, danach blinkt das Gewinnfeld
	local warm, white = Color3.fromRGB(255, 196, 90), Color3.fromRGB(255, 244, 220)
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		for k, bulb in wheel.Bulbs do
			local on
			if spinning then
				on = (k + math.floor(t * 18)) % 5 == 0
			elseif winner and t < winner.Until then
				on = math.floor(t * 6) % 2 == 0
			else
				on = (k + math.floor(t * 1.5)) % 2 == 0
			end
			bulb.Color = on and white or warm
			bulb.Transparency = on and 0 or 0.45
		end
		if winner then
			local blink = t < winner.Until and math.floor(t * 6) % 2 == 0
			for i, slice in wheel.Slices do
				for _, wedge in slice.Wedges do
					wedge.Material = (blink and i == winner.Index) and Enum.Material.Neon or Enum.Material.SmoothPlastic
				end
			end
			if t >= winner.Until then
				winner = nil
			end
		end
		-- Zeiger schlägt beim Klacken aus und schwingt zurück
		kick = math.max(0, kick - dt * 90)
		wheel.Pointer:PivotTo(wheel.PointerPivot * CFrame.Angles(0, 0, math.rad(kick)))
	end)

	-- Anfrage ohne Antwort: nach 6 s wieder freigeben
	task.spawn(function()
		while true do
			if waitingSince and os.clock() - waitingSince > 6 then
				waitingSince = nil
				spinning = false
			end
			refresh()
			task.wait(0.5)
		end
	end)
	player:GetAttributeChangedSignal("WheelData"):Connect(refresh)
end

return HubWheel

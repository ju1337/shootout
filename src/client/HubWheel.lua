-- HubWheel (ModuleScript, nur Client)
-- Das Glücksrad steht als großes Rad im Camp am Phönixplatz (Teil "WheelSpot" der Gruppe Zentrale, siehe
-- Shared/Zentrale: Mitte des Rads, LookVector = Vorderseite). Podest, Ständer und Schild kommen aus der Map, das Rad baut dieses Modul lokal:
-- zehn farbige Felder (LoginConfig.Wheel) aus Keilen, goldene Trennstege, Beschriftung, Nabe, Rand mit
-- Glühbirnen und oben ein Zeiger. Alles matt (SmoothPlastic): Metall spiegelt nachts den hellen Himmel und
-- überstrahlte das Rad. Am Pult davor ("WheelConsole") öffnet E bzw. Antippen den Dreh: der Server lost das Feld
-- aus (ShopAction "SpinWheel" -> Remotes.WheelResult) und zeigt den Dreh allen (Remotes.WheelSpin).
-- Ablauf: Anlauf (Rad holt nach hinten aus), schnelle Runden, langes Auslaufen über die letzten Felder (Zeiger
-- klackt an jedem Steg, Klack wird mit dem Rad langsamer), kurze Stille, dann die Gewinn-Show nach Seltenheit:
-- Gewinnfeld leuchtet, die anderen werden dunkel, Birnen blinken in der Seltenheitsfarbe, Lichtblitz, Funken,
-- ab Selten eine Druckwelle, ab Episch Sternregen, legendär (Skins, JACKPOT) ein Strahlenkranz hinter dem Rad. Wer gedreht hat,
-- bekommt die Gewinn-Karte (Skin-Vorschau bzw. hochzählende Münzen) mit NOCHMAL DREHEN; Spieler in der Nähe
-- sehen große Gewinne als Meldung. Die Tafel auf dem Pult ("WheelBoard") zeigt, ob ein Gratis- oder Extra-Dreh
-- bereit ist bzw. wann der nächste kommt. Einmal am Tag gratis, dazu Extra-Drehs (Login-Kalender, Robux-Shop).
-- Weil man Drehs für Robux kaufen kann, steht auf jedem Feld seine Chance, und am Pult öffnet Q (bzw. Antippen des
-- zweiten Knopfs) das Fenster CHANCEN mit allen Gewinnen (OddsPanel, Roblox-Regeln für bezahlte Zufallsitems).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local LoginConfig = require(Shared.LoginConfig)
local Cosmetics = require(Shared.Cosmetics)
local RobuxConfig = require(Shared.RobuxConfig)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)
local Notifications = require(Shared.Notifications)
local PaidRandom = require(Shared.PaidRandom)
local OddsPanel = require(Shared.OddsPanel)
local ItemPreview = require(Shared.ItemPreview)
local Sfx = require(Shared.Sfx)
local Zentrale = require(Shared.Zentrale)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label, upper = UITheme.Make, UITheme.Label, UITheme.Upper
local format = UITheme.FormatNumber

local HubWheel = {}

HubWheel.Radius = 6
local SLICE_COUNT = #LoginConfig.Wheel
local SLICE = 360 / SLICE_COUNT       -- Grad pro Feld
local SUB = 3                          -- Dreiecke pro Feld (Rand fast rund)
HubWheel.WindupTime = 0.6              -- Anlauf: Rad holt nach hinten aus
HubWheel.WindupAngle = 14              -- so weit (Grad)
HubWheel.SpinTime = 6.4                -- Sekunden vom Anstoß bis zum Stillstand
local SPIN_TURNS = 5                   -- mindestens so viele volle Runden
local REVEAL_DELAY = 0.45              -- Stille zwischen Stillstand und Gewinn-Show
local BULBS = 30
local GOLD = Color3.fromRGB(212, 170, 80)
local DARK = Color3.fromRGB(20, 22, 27)
local FRAME = Color3.fromRGB(34, 37, 44)
local BULB_ON = Color3.fromRGB(255, 226, 150)
local BULB_OFF = Color3.fromRGB(70, 52, 30)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

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

-- Anteil des Wegs (0..1) nach dem Anteil alpha der Drehzeit: kubisch auslaufend. Das Rad ist am Anfang am
-- schnellsten und kriecht am Ende lange über die letzten Felder (Spannung), ohne Ruck beim Anhalten.
function HubWheel.SpinCurve(alpha)
	alpha = math.clamp(alpha, 0, 1)
	return 1 - (1 - alpha) ^ 3
end

-- Seltenheit eines Felds (Cosmetics.Rarities): Skins nach dem Skin, JACKPOT legendär, sonst nach dem Gewinn
function HubWheel.FieldRarity(index)
	local field = LoginConfig.Wheel[index]
	if not field then
		return "Common"
	end
	local item = field.Item and Cosmetics.Get(field.Item)
	if index == SLICE_COUNT then
		return "Legendary"
	elseif item then
		return item.Rarity
	elseif (field.Coins or 0) >= 1000 then
		return "Epic"
	elseif (field.Coins or 0) >= 250 or field.BoostMinutes then
		return "Rare"
	end
	return "Common"
end

local RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 4 }
local function rarityColor(rarity)
	local entry = Cosmetics.Rarities[rarity]
	return rarity == "Common" and Color3.fromRGB(236, 238, 241) or (entry and entry.Color) or GOLD
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
	local extra = (tonumber(data.Spins) or 0)
		+ (player:GetAttribute("PaidRandomOk") ~= false and tonumber(data.PaidSpins) or 0) -- gekaufte nur ohne Länder-Sperre
	return free or extra > 0, free, extra
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
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function NS(points)
	local list = {}
	for _, p in points do
		table.insert(list, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(list)
end

local function emitter(name, parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = SPARK
	e.Enabled = false
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

-- Rad an spot bauen. Gibt { Spin (Modell, dreht sich), Static (Modell), Face (CFrame), Slices, Bulbs, Pointer,
-- PointerPivot, Halo, Wave, Fx (Teil mit Licht und Partikeln) } zurück. Face: x = rechts, y = oben,
-- z = zum Betrachter (Vorderseite).
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
		CFrame = face * CFrame.Angles(0, math.pi / 2, 0), Color = DARK })

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
					Color = field.Color }))
			end
		end
		local edge = math.rad(center + SLICE / 2)
		part(spin, "Part", { Name = "Divider", Size = Vector3.new(0.16, R, 0.08), Color = GOLD,
			CFrame = face * CFrame.Angles(0, 0, -edge) * CFrame.new(0, R / 2, 0.34) })
		-- Beschriftung entlang des Radius, von der Mitte nach außen lesbar
		local label = part(spin, "Part", { Name = "Label" .. i, Size = Vector3.new(R * 0.56, 1.15, 0.05), Transparency = 1,
			CFrame = face * CFrame.Angles(0, 0, -math.rad(center)) * CFrame.new(0, R * 0.6, 0.36) * CFrame.Angles(0, 0, math.pi / 2) })
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Back
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 60
		surface.LightInfluence = 0.15
		surface.Parent = label
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 0.7)
		text.BackgroundTransparency = 1
		text.Text = field.Text
		text.TextScaled = true
		text.Font = Enum.Font.BuilderSansExtraBold
		text.TextColor3 = field.TextColor or Color3.new(1, 1, 1)
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
		CFrame = face * CFrame.new(0, 0, 0.45) * CFrame.Angles(0, math.pi / 2, 0) })
	part(spin, "Part", { Name = "HubCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.56, 1.3, 1.3), Color = DARK,
		CFrame = face * CFrame.new(0, 0, 0.5) * CFrame.Angles(0, math.pi / 2, 0) })
	spin.WorldPivot = face

	-- Rand (steht still) mit Glühbirnen, dahinter der Lichthof (nur bei der Gewinn-Show sichtbar)
	part(static, "Part", { Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 2 * R + 1.3, 2 * R + 1.3),
		Color = FRAME, CFrame = face * CFrame.new(0, 0, -0.4) * CFrame.Angles(0, math.pi / 2, 0) })
	part(static, "Part", { Name = "RimRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 2 * R + 0.5, 2 * R + 0.5),
		Color = GOLD, CFrame = face * CFrame.new(0, 0, -0.06) * CFrame.Angles(0, math.pi / 2, 0) })
	local halo = part(static, "Part", { Name = "Halo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 2 * R + 5, 2 * R + 5),
		Color = GOLD, Material = Enum.Material.Neon, Transparency = 1,
		CFrame = face * CFrame.new(0, 0, -0.8) * CFrame.Angles(0, math.pi / 2, 0) })
	local wave = part(static, "Part", { Name = "Wave", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 2 * R, 2 * R),
		Color = GOLD, Material = Enum.Material.Neon, Transparency = 1,
		CFrame = face * CFrame.new(0, 0, 0.7) * CFrame.Angles(0, math.pi / 2, 0) })
	local bulbs = {}
	for k = 1, BULBS do
		local angle = math.rad((k - 1) * 360 / BULBS)
		bulbs[k] = part(static, "Part", { Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.36, 0.36, 0.36),
			Color = BULB_OFF, CFrame = CFrame.new(at(math.sin(angle) * (R + 0.35), math.cos(angle) * (R + 0.35), 0.05)) })
	end
	-- Zeiger oben: Dreieck nach unten, Drehpunkt in der Kugel darüber
	local pointer = Instance.new("Model")
	pointer.Name = "Pointer"
	for _, spec in HubWheel.Triangle(at(-0.8, R + 1.25, 0.62), at(0.8, R + 1.25, 0.62), at(0, R - 0.55, 0.62), 0.22) do
		part(pointer, "WedgePart", { Name = "Arrow", Size = spec.Size, CFrame = spec.CFrame, Color = Color3.fromRGB(196, 38, 46) })
	end
	local pivot = face * CFrame.new(0, R + 1.25, 0.62)
	part(pointer, "Part", { Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), Color = GOLD,
		CFrame = pivot })
	pointer.WorldPivot = pivot
	pointer.Parent = static

	-- Effekte vor der Nabe: Lichtblitz, Funken, Sternregen; Strahlenkranz hinter dem Rad
	local fx = part(static, "Part", { Name = "Fx", Size = Vector3.new(2 * R, 2 * R, 0.1), Transparency = 1,
		CFrame = face * CFrame.new(0, 0, 0.9) })
	local light = Instance.new("PointLight")
	light.Name = "Flash"
	light.Brightness = 0
	light.Range = 22
	light.Shadows = false
	light.Parent = fx
	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = fx
	emitter("Sparks", center, { Lifetime = NumberRange.new(0.6, 1.3), Speed = NumberRange.new(14, 30),
		SpreadAngle = Vector2.new(180, 180), Drag = 3, Acceleration = Vector3.new(0, -14, 0),
		Size = NS({ { 0, 0.5 }, { 0.6, 0.35 }, { 1, 0 } }), Transparency = NS({ { 0, 0 }, { 0.8, 0.2 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), Brightness = 3 })
	emitter("Stars", fx, { Lifetime = NumberRange.new(1.4, 2.4), Speed = NumberRange.new(2, 6),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(40, 40), Acceleration = Vector3.new(0, -6, 0),
		Drag = 0.6, Size = NS({ { 0, 0 }, { 0.15, 0.45 }, { 1, 0 } }), Transparency = NS({ { 0, 0 }, { 0.7, 0.1 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120), Brightness = 2.5,
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume })
	local column = part(static, "Part", { Name = "Column", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1,
		CFrame = face * CFrame.new(0, 0, -1) })
	emitter("Beam", column, { Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(16, 26),
		SpreadAngle = Vector2.new(180, 180), Drag = 2, Size = NS({ { 0, 1.4 }, { 0.6, 0.9 }, { 1, 0 } }),
		Transparency = NS({ { 0, 0.15 }, { 0.7, 0.5 }, { 1, 1 } }), Rotation = NumberRange.new(0, 360), Brightness = 3 })

	static.Parent = parent
	spin.Parent = parent
	return { Spin = spin, Static = static, Face = face, Slices = slices, Bulbs = bulbs, Pointer = pointer, PointerPivot = pivot,
		Halo = halo, Wave = wave, Fx = fx, Light = light, Column = column }
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
	surface.Brightness = 1
	surface.Adornee = board
	surface.Parent = player:WaitForChild("PlayerGui")
	local function line(name, y, h, font, color)
		local text = Instance.new("TextLabel")
		text.Name = name
		text.Position = UDim2.fromScale(0.05, y)
		text.Size = UDim2.fromScale(0.9, h)
		text.BackgroundTransparency = 1
		text.TextScaled = true
		text.Font = font
		text.TextColor3 = color
		text.TextStrokeTransparency = 0.6
		text.Text = ""
		text.Parent = surface
		return text
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

-- Was das Feld bringt, für Karte und Meldungen
local function prizeText(index)
	local field = LoginConfig.Wheel[index]
	local item = field and field.Item and Cosmetics.Get(field.Item)
	if item then
		return upper(item.Name)
	elseif field and field.BoostMinutes then
		return field.BoostMinutes .. " MIN. DOPPEL-XP"
	end
	return "+" .. format(field and field.Coins or 0) .. " MÜNZEN"
end

-- ---------- Gewinn-Karte (nur für den, der gedreht hat) ----------

local reveal = nil -- { Gui, Connection }

local function closeReveal()
	if not reveal then
		return
	end
	if reveal.Connection then
		reveal.Connection:Disconnect()
	end
	reveal.Gui:Destroy()
	reveal = nil
	UITheme.SetBlur("HubWheel", false)
end

local function showReveal(index, serverText, onAgain)
	closeReveal()
	local field = LoginConfig.Wheel[index]
	if not field then
		return
	end
	local rarity = HubWheel.FieldRarity(index)
	local rank = RANK[rarity] or 1
	local color = rarityColor(rarity)
	local item = field.Item and Cosmetics.Get(field.Item)
	local jackpot = index == SLICE_COUNT
	-- Duplikat eines gebundenen Skins: Server gab Münzen statt Skin
	local gotItem = item ~= nil and string.find(tostring(serverText or ""), item.Name, 1, true) ~= nil

	local gui = make("ScreenGui", { Name = "WheelReveal", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30 },
		player:WaitForChild("PlayerGui"))
	local root = UITheme.ScaledRoot(gui)
	-- Active: Klicks gehen nicht in die Welt dahinter
	local overlay = make("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background,
		BackgroundTransparency = 1, BorderSizePixel = 0, Active = true }, root)
	TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.35 }):Play()

	-- Strahlen hinter der Karte (drehen sich langsam), ab Episch doppelt
	local rays = make("Frame", { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(980, 980), BackgroundTransparency = 1 }, overlay)
	local rayCount = rank >= 3 and 16 or 10
	for k = 1, rayCount do
		local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Rotation = (k - 1) * 180 / rayCount }, rays)
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, rank >= 3 and 46 or 30, 1, 0), BackgroundColor3 = color,
			BackgroundTransparency = rank >= 4 and 0.82 or 0.88, BorderSizePixel = 0 }, holder)
	end

	local card = UITheme.Card({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, item and 470 or 360) }, overlay)
	UITheme.AccentBar(card, color, { Thickness = 4 })
	local scale = make("UIScale", { Scale = 0.55 }, card)
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local rarityName = Cosmetics.Rarities[rarity] and Cosmetics.Rarities[rarity].Name or ""
	label({ Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 20), Text = "GLÜCKSRAD  ·  " .. upper(rarityName),
		TextSize = 15, Font = F.Bold, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center }, card)
	label({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 48),
		Text = jackpot and "JACKPOT!" or (gotItem and "NEUER SKIN" or "GEWONNEN"), TextSize = 44, Font = F.Display,
		TextColor3 = rank >= 4 and color or C.Text, TextXAlignment = Enum.TextXAlignment.Center }, card)

	local y = 96
	local prize = label({ Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 40), Text = prizeText(index),
		TextSize = 34, Font = F.Display, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center }, card)
	y += 46
	if item then
		local view = ItemPreview.New(card, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y),
			Size = UDim2.fromOffset(340, 150) })
		ItemPreview.Show(view, item, 340 / 150)
		y += 156
	end
	label({ Position = UDim2.fromOffset(20, y), Size = UDim2.new(1, -40, 0, 22), Text = tostring(serverText or ""),
		TextSize = 15, Font = F.Bold, TextColor3 = C.Muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center }, card)

	-- Münzen zählen hoch
	local connection = nil
	if not item and field.Coins then
		local began, total = os.clock(), field.Coins
		connection = RunService.RenderStepped:Connect(function()
			local a = math.min((os.clock() - began) / 1.1, 1)
			prize.Text = "+" .. format(math.floor(total * HubWheel.SpinCurve(a) + 0.5)) .. " MÜNZEN"
		end)
	end

	-- unten: nochmal drehen (wenn möglich), sonst wann der nächste Gratis-Dreh kommt; dazu Drehs kaufen
	local ready, _, extra = wheelState()
	local again
	if ready then
		again = UITheme.Chunky({ Position = UDim2.new(0, 28, 1, -78), Size = UDim2.fromOffset(300, 56), Color = C.Primary,
			TextColor = C.PrimaryText, Text = extra > 0 and ("NOCHMAL DREHEN  ·  " .. extra) or "NOCHMAL DREHEN", TextSize = 20 },
			card, function()
				closeReveal()
				onAgain()
			end)
	else
		label({ Position = UDim2.new(0, 28, 1, -100), Size = UDim2.fromOffset(300, 20),
			Text = "NÄCHSTER DREH IN " .. clock(86400 - workspace:GetServerTimeNow() % 86400), TextSize = 15, Font = F.Bold,
			TextColor3 = C.Muted }, card)
		local pack = RobuxConfig.Product("Spins5")
		if pack and pack.ProductId ~= 0 and player:GetAttribute("PaidRandomOk") ~= false then
			again = UITheme.Chunky({ Position = UDim2.new(0, 28, 1, -78), Size = UDim2.fromOffset(300, 56), Color = C.Good,
				TextColor = C.OnLight, Text = pack.Name .. "  ·  R$ " .. pack.Robux, TextSize = 17 }, card, function()
				MarketplaceService:PromptProductPurchase(player, pack.ProductId)
			end)
		end
	end
	local ok = UITheme.Chunky({ Position = UDim2.new(1, -216, 1, -78), Size = UDim2.fromOffset(188, 56), Color = C.Card,
		StrokeColor = C.Border, Text = "OK", TextSize = 20 }, card, closeReveal)
	InputActions.Focus(overlay, (again or ok).Button)
	UITheme.SetBlur("HubWheel", true)

	local spinRays = RunService.RenderStepped:Connect(function(dt)
		rays.Rotation = (rays.Rotation + dt * (rank >= 4 and 14 or 8)) % 360
	end)
	reveal = { Gui = gui, Connection = spinRays }
	gui.Destroying:Connect(function()
		spinRays:Disconnect()
		if connection then
			connection:Disconnect()
		end
	end)
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
	local resultText, resultUntil, resultColor = nil, 0, C.Good
	local errorText, errorUntil = nil, 0
	local show = nil            -- Gewinn-Show { Index, Color, Rank, Began, Until }
	local windup = false        -- Anlauf läuft (Birnen blinken alle)
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
			board.Status.TextColor3 = resultColor
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

	local function request()
		if spinning or not wheelState() then
			return
		end
		spinning = true
		waitingSince = os.clock()
		Remotes.ShopAction:FireServer("SpinWheel")
		refresh()
	end
	prompt.Triggered:Connect(request)
	-- Abgelehnt (z.B. zu weit weg, Rad besetzt): Meldung auf die Tafel, Rad wieder freigeben
	Remotes.ShopStatus.OnClientEvent:Connect(function(message, success)
		if waitingSince and success == false then
			waitingSince = nil
			spinning = false
			errorText, errorUntil = upper(tostring(message)), os.clock() + 4
			refresh()
		end
	end)

	-- Gewinn-Show am Rad (für alle, die zusehen)
	local function celebrate(index)
		local rarity = HubWheel.FieldRarity(index)
		local rank = RANK[rarity] or 1
		local color = rarityColor(rarity)
		show = { Index = index, Color = color, Rank = rank, Began = os.clock(), Until = os.clock() + 2.5 + rank }
		local where = wheel.Fx
		-- Klang je Seltenheit
		Sfx.At("WheelWin", where, { Pitch = rank >= 3 and 0.9 or 1.1 })
		if rank >= 2 then
			Sfx.At("WheelCoins", where)
		end
		if rank >= 3 then
			task.delay(0.25, Sfx.At, "WheelWinBig", where)
		end
		if rank >= 4 then
			task.delay(0.5, Sfx.At, "WheelWin", where, { Pitch = 1.25 })
			task.delay(0.8, Sfx.At, "WheelWinBig", where, { Pitch = 1.2 })
		end
		-- Lichtblitz und Lichthof in der Seltenheitsfarbe
		wheel.Light.Color = color
		wheel.Light.Brightness = 1.2 + rank * 0.7
		TweenService:Create(wheel.Light, TweenInfo.new(1.4 + rank * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 }):Play()
		wheel.Halo.Color = color
		wheel.Halo.Transparency = 0.55
		TweenService:Create(wheel.Halo, TweenInfo.new(1.2 + rank * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }):Play()
		-- Funken für alle, Druckwelle ab Selten, Sternregen ab Episch, Strahlenkranz legendär
		local sparks = wheel.Fx.Center.Sparks
		sparks.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		sparks:Emit(({ 24, 45, 80, 140 })[rank] or 24)
		if rank >= 2 then
			local R = HubWheel.Radius
			wheel.Wave.Color = color
			wheel.Wave.Transparency = 0.3
			wheel.Wave.Size = Vector3.new(0.05, 2 * R, 2 * R)
			TweenService:Create(wheel.Wave, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(0.05, 2 * R + 14, 2 * R + 14), Transparency = 1 }):Play()
		end
		if rank >= 3 then
			local stars = wheel.Fx.Stars
			stars.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
			stars:Emit(rank >= 4 and 120 or 60)
		end
		if rank >= 4 then
			local beam = wheel.Column.Beam
			beam.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
			beam.Rate = 40
			beam.Enabled = true
			task.delay(2.5, function()
				beam.Enabled = false
			end)
		end
	end

	-- Dreh abspielen: Anlauf, Runden, Auslaufen, Stille, Show. own = selbst gedreht (Karte, Tafel)
	local spinConnection = nil -- laufende Dreh-Animation (ein spätes zweites Ergebnis ersetzt sie)
	local spinToken = 0
	local function play(index, text, own, who)
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
		spinToken += 1
		local token = spinToken
		index = math.clamp(math.floor(tonumber(index) or 1), 1, SLICE_COUNT)
		spinning = true
		show = nil
		if own then
			closeReveal()
		end
		refresh()
		local from = rotation
		local start = from - HubWheel.WindupAngle
		local target = HubWheel.TargetRotation(start, index, SPIN_TURNS, (math.random() - 0.5) * SLICE * 0.7)
		local began = os.clock()
		local lastBoundary = math.floor((from + SLICE / 2) / SLICE)
		local lastTick = 0
		windup = true
		Sfx.At("WheelWindup", wheel.Fx)
		spinConnection = RunService.Heartbeat:Connect(function()
			local t = os.clock() - began
			if t < HubWheel.WindupTime then
				local a = TweenService:GetValue(t / HubWheel.WindupTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
				rotation = from - HubWheel.WindupAngle * a
				apply()
				return
			end
			windup = false
			local alpha = math.min((t - HubWheel.WindupTime) / HubWheel.SpinTime, 1)
			rotation = start + (target - start) * HubWheel.SpinCurve(alpha)
			apply()
			-- Klack an jedem Steg, der am Zeiger vorbeikommt; schnell = hoch und leise, langsam = tief und deutlich
			local boundary = math.floor((rotation + SLICE / 2) / SLICE)
			if boundary ~= lastBoundary then
				lastBoundary = boundary
				kick = 18
				local speed = 3 * (1 - alpha) ^ 2 -- relative Geschwindigkeit (Ableitung der Kurve)
				if os.clock() - lastTick > 0.045 then -- bei voller Fahrt nicht jeden Steg (sonst Knattern)
					lastTick = os.clock()
					Sfx.At("WheelTick", wheel.Fx, { Pitch = 0.85 + math.min(speed, 3) * 0.2, Volume = 0.6 + (1 - alpha) * 0.4 })
				end
			end
			if alpha >= 1 then
				spinConnection:Disconnect()
				spinConnection = nil
				rotation = target % 360
				apply()
				Sfx.At("WheelStop", wheel.Fx)
				task.delay(REVEAL_DELAY, function()
					if token ~= spinToken then
						return
					end
					spinning = false
					celebrate(index)
					local rarity = HubWheel.FieldRarity(index)
					resultColor = rarityColor(rarity)
					if own then
						resultText, resultUntil = "GEWONNEN: " .. prizeText(index), os.clock() + 8
						task.delay(0.35, function()
							if token == spinToken then
								showReveal(index, text, request)
							end
						end)
					else
						resultText, resultUntil = upper(who) .. " GEWINNT " .. prizeText(index), os.clock() + 6
						-- große Gewinne anderer in der Nähe als Meldung
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if (RANK[rarity] or 1) >= 3 and root and (root.Position - wheel.Face.Position).Magnitude < 160 then
							Notifications.Reward({ Title = "GLÜCKSRAD", Lines = { who .. " gewinnt " .. prizeText(index) },
								Rarity = rarity })
						end
					end
					refresh()
				end)
			end
		end)
	end

	Remotes.WheelResult.OnClientEvent:Connect(function(index, text)
		waitingSince = nil
		play(index, text, true, player.DisplayName)
	end)
	Remotes.WheelSpin.OnClientEvent:Connect(function(spinner, index)
		if spinner == player or typeof(spinner) ~= "Instance" or not spinner:IsA("Player") then
			return -- eigener Dreh kommt als WheelResult (mit Text)
		end
		play(index, nil, false, spinner.DisplayName)
	end)

	-- Birnen und Felder: ruhig im Leerlauf, Lauflicht wenn ein Dreh bereit ist, wild beim Drehen,
	-- in der Show blinken sie in der Seltenheitsfarbe, das Gewinnfeld leuchtet und die anderen werden dunkel
	local dimmed = false
	local idleSpeed = 0
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		-- weit weg und ruhig: nichts zu sehen, also nicht jedes Bild 30+ Teile umfärben
		local camera = workspace.CurrentCamera
		if not spinning and not show and kick <= 0 and camera
			and (camera.CFrame.Position - wheel.Face.Position).Magnitude > 250 then
			return
		end
		local ready = not spinning and not show and wheelState()
		-- bereit: das Rad dreht sich ganz langsam (lädt ein), sonst steht es
		idleSpeed += ((ready and 5 or 0) - idleSpeed) * math.min(1, dt * 2)
		if not spinning and idleSpeed > 0.01 then
			rotation += idleSpeed * dt
			apply()
		end
		local showing = show and t < show.Until
		for k, bulb in wheel.Bulbs do
			local on, color = false, BULB_ON
			if windup then
				on = math.floor(t * 14) % 2 == 0
			elseif spinning then
				on = (k + math.floor(t * 24)) % 3 == 0
			elseif showing then
				on = (k + math.floor(t * 8)) % 2 == 0
				color = show.Color
			elseif ready then
				on = (k + math.floor(t * 6)) % 5 < 2
			else
				on = (k + math.floor(t * 1.2)) % 3 == 0
			end
			bulb.Color = on and color or BULB_OFF
			bulb.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
		if showing then
			local glow = math.floor((t - show.Began) * 5) % 2 == 0
			for i, slice in wheel.Slices do
				local winner = i == show.Index
				for _, wedge in slice.Wedges do
					wedge.Material = (winner and glow) and Enum.Material.Neon or Enum.Material.SmoothPlastic
					wedge.Color = winner and slice.Color or slice.Color:Lerp(Color3.new(0, 0, 0), 0.65)
				end
			end
			dimmed = true
		elseif dimmed then
			dimmed = false
			show = nil
			for _, slice in wheel.Slices do
				for _, wedge in slice.Wedges do
					wedge.Material = Enum.Material.SmoothPlastic
					wedge.Color = slice.Color
				end
			end
		elseif show and t >= show.Until then
			show = nil
		end
		-- Zeiger schlägt beim Klacken aus und schwingt zurück
		kick = math.max(0, kick - dt * 110)
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

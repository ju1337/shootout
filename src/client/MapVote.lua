-- MapVote (ModuleScript, nur Client)
-- Map-Abstimmung vor einem Team-Match bzw. nach jeder FFA-Runde: eigener Vollbild-Screen über dem HUD (Minimap,
-- Fähigkeiten, Killstreaks, Tastenzeile usw. sind währenddessen verdeckt, unten links ein eigenes VERLASSEN) mit
-- bis zu 3 Karten: Vorschaubild, Map-Name und Stimmen. Anklicken oder 1/2/3 drücken. Daten kommen als Spieler-Attribute vom Server
-- (MapVoteOptions, MapVoteEnd, MapVoteCounts, MapVoteMine).
-- Vorschaubild: die echte Map-Geometrie (workspace.Maps[Id]) schräg von oben in einem ViewportFrame. Sie wird beim
-- ersten Mal über mehrere Bilder verteilt kopiert (kein Ruckeln) und für spätere Abstimmungen behalten.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)
local Modes = require(Shared.Modes)
local LeaveButton = require(Shared.LeaveButton)

local player = Players.LocalPlayer
local C = UITheme.Colors
local make = UITheme.Make

local MapVote = {}

local CARD_W, CARD_H, CARD_GAP = 460, 320, 28
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
-- Über allem HUD (HUD/Fähigkeiten/Killstreaks 0, Level 2, Touch 4, Agentenwahl 5, Downed 6, Scoreboard 8,
-- Knöpfe 9, Lobby 10, Meldungen 11, Zusammenfassung 12), unter Seitenmenü (15), Admin (20), Belohnungskarten (25)
-- und Party-Einladung (30)
local DISPLAY_ORDER = 13

-- Vorschaubild
local PREVIEW_MIN_SIZE = 1.5        -- kleinere Teile (Kleinkram) weglassen: weniger zu zeichnen
local PREVIEW_BATCH = 150           -- so viele Teile pro Bild beim Kopieren
local PREVIEW_FOV = 34
local PREVIEW_YAW = math.rad(-30)   -- schräg über Eck ...
local PREVIEW_PITCH = math.rad(-34) -- ... und von oben
local PREVIEW_HEIGHT = 14           -- höhere Teile (Schornsteine, Türme) zählen beim Einpassen nur bis hier
local PREVIEW_ZOOM = 0.96           -- etwas näher als ganz eingepasst: Karte voll, Ecken dürfen abgeschnitten sein
local PREVIEW_MARGIN = 60           -- Deko so weit neben dem Boden der Map kommt mit, fernere (Planeten ...) nicht
local PREVIEW_ABOVE = 120           -- ... und nur bis so hoch über dem Boden
local LIGHT_DIRECTION = Vector3.new(-0.55, -1, -0.4)
local LIGHT = {
	Default = { Ambient = Color3.fromRGB(138, 140, 148), Light = Color3.fromRGB(220, 212, 198) },
	Tropical = { Ambient = Color3.fromRGB(150, 146, 136), Light = Color3.fromRGB(255, 238, 205) },
	Space = { Ambient = Color3.fromRGB(96, 102, 126), Light = Color3.fromRGB(210, 214, 240) },
}
local KEEP_IN_COPY = { "DataModelMesh", "Decal", "SurfaceAppearance" } -- Decal schließt Texture ein

-- Farbstimmung je Map (Himmel hinter der Vorschau)
local MOODS = {
	Fabrik = { Color3.fromRGB(120, 90, 60), Color3.fromRGB(40, 32, 26) },
	Hafen = { Color3.fromRGB(50, 100, 130), Color3.fromRGB(18, 30, 44) },
	Gletscher = { Color3.fromRGB(150, 200, 230), Color3.fromRGB(40, 70, 95) },
	Zellenblock = { Color3.fromRGB(110, 110, 105), Color3.fromRGB(35, 35, 38) },
	["Kanäle"] = { Color3.fromRGB(200, 150, 120), Color3.fromRGB(45, 60, 75) },
	["Windmühlen"] = { Color3.fromRGB(110, 160, 80), Color3.fromRGB(30, 50, 35) },
	Hochhaus = { Color3.fromRGB(90, 120, 170), Color3.fromRGB(20, 26, 44) },
	Altstadt = { Color3.fromRGB(190, 150, 110), Color3.fromRGB(60, 44, 36) },
	Kraftwerk = { Color3.fromRGB(150, 150, 140), Color3.fromRGB(40, 42, 46) },
	Favela = { Color3.fromRGB(255, 120, 150), Color3.fromRGB(60, 140, 160) },
	Lagune = { Color3.fromRGB(70, 210, 210), Color3.fromRGB(240, 170, 90) },
	Orbit = { Color3.fromRGB(120, 80, 220), Color3.fromRGB(10, 12, 30) },
	Mondbasis = { Color3.fromRGB(150, 160, 180), Color3.fromRGB(14, 16, 28) },
}

local gui, timerLabel, timerBar, captionLabel, hintLabel
local cards = {}
local refresh -- (vorwärts)
local voteTotal, lastVoteEnd = 1, nil -- Länge der Abstimmung für den Zeitbalken

local function decode(name)
	local raw = player:GetAttribute(name)
	if type(raw) ~= "string" then
		return nil
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and data or nil
end

local function vote(index)
	if gui.Enabled then
		Remotes.MapVote:FireServer(index)
	end
end

-- ---------- Vorschaubild ----------

local PREVIEW_CACHE = 6 -- so viele Vorschauen bleiben im Speicher (Team-Modus + FFA je 3 Maps)
local previews = {} -- [MapId] = { Ready, Model, Camera (CFrame), Light, Used (os.clock) }

-- Zu viele Vorschauen im Speicher: die am längsten nicht gezeigte (und gerade in keiner Karte hängende) weg
local function trimPreviews()
	local count, oldestId, oldest = 0, nil, math.huge
	for mapId, preview in previews do
		count += 1
		local attached = preview.Model ~= nil and preview.Model.Parent ~= nil
		if preview.Ready and not attached and (preview.Used or 0) < oldest then
			oldestId, oldest = mapId, preview.Used or 0
		end
	end
	if count > PREVIEW_CACHE and oldestId then
		previews[oldestId].Model:Destroy()
		previews[oldestId] = nil
	end
end

-- Nur das Sichtbare behalten (Meshes, Decals/Texturen), keine Skripte, Lichter, Sounds, Gelenke ...
local function stripCopy(copy)
	for _, child in copy:GetDescendants() do
		local keep = false
		for _, class in KEEP_IN_COPY do
			if child:IsA(class) then
				keep = true
				break
			end
		end
		if not keep then
			child:Destroy()
		end
	end
end

-- Ausdehnung einer (gedrehten) Box entlang der Weltachsen (halbe Kantenlängen)
local function worldExtent(cframe, size)
	local h = size / 2
	local r, u, l = cframe.RightVector, cframe.UpVector, cframe.LookVector
	return Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z)
end

type Bounds = { Min: Vector3?, Max: Vector3? }

local function extend(bounds: Bounds, part: BasePart)
	local extent = worldExtent(part.CFrame, part.Size)
	local low, high = part.Position - extent, part.Position + extent
	local min, max = bounds.Min, bounds.Max
	if min and max then
		bounds.Min, bounds.Max = min:Min(low), max:Max(high)
	else
		bounds.Min, bounds.Max = low, high
	end
end

-- Kamera schräg von oben, so dass die Box (low..high) die Karte (Seitenverhältnis aspect) füllt
local function framePreview(low, high, aspect)
	local rotation = CFrame.Angles(0, PREVIEW_YAW, 0) * CFrame.Angles(PREVIEW_PITCH, 0, 0)
	local center = (low + high) / 2
	local tanV = math.tan(math.rad(PREVIEW_FOV) / 2)
	local tanH = tanV * aspect
	local distance = 0
	for _, x in { low.X, high.X } do
		for _, y in { low.Y, high.Y } do
			for _, z in { low.Z, high.Z } do
				local q = rotation:VectorToObjectSpace(Vector3.new(x, y, z) - center)
				distance = math.max(distance, q.Z + math.abs(q.X) / tanH, q.Z + math.abs(q.Y) / tanV)
			end
		end
	end
	return CFrame.new(center - rotation.LookVector * distance * PREVIEW_ZOOM) * rotation
end

local function visibleInPreview(obj)
	return obj:IsA("BasePart") and obj.Transparency < 0.95 and obj.Size.Magnitude >= PREVIEW_MIN_SIZE
end

-- Map kopieren (über mehrere Bilder verteilt) und Kamera einpassen; danach refresh().
-- Gibt false zurück, wenn es die Map (noch) nicht gibt.
local function buildPreview(mapId)
	if previews[mapId] then
		return true
	end
	local maps = workspace:FindFirstChild("Maps")
	local source = maps and maps:FindFirstChild(mapId)
	if not source then
		return false
	end
	local preview = { Ready = false }
	previews[mapId] = preview
	task.spawn(function()
		-- Streaming: die Map liegt weit weg und ist beim Client sonst nicht geladen – vorher holen (danach bleibt die Kopie)
		local center = source:GetAttribute("Center")
		if typeof(center) == "Vector3" then
			pcall(player.RequestStreamAroundAsync, player, center, 5)
		end
		-- Spielfläche: der Boden der Map (Ordner/Teil "Ground"), sonst alles
		local floor: Bounds = {}
		local ground = source:FindFirstChild("Ground")
		if ground then
			if visibleInPreview(ground) then
				extend(floor, ground)
			end
			for _, obj in ground:GetDescendants() do
				if visibleInPreview(obj) then
					extend(floor, obj)
				end
			end
		end
		local floorMin, floorMax = floor.Min, floor.Max
		local keepMin = floorMin and floorMin - Vector3.new(PREVIEW_MARGIN, PREVIEW_MARGIN, PREVIEW_MARGIN)
		local keepMax = floorMax and floorMax + Vector3.new(PREVIEW_MARGIN, PREVIEW_ABOVE, PREVIEW_MARGIN)

		local model = Instance.new("Model")
		model.Name = "Vorschau_" .. mapId
		local all: Bounds = {}
		local count = 0
		for _, obj in source:GetDescendants() do
			local position = obj:IsA("BasePart") and obj.Position
			local near = position and (not keepMin or not keepMax or (position.X >= keepMin.X and position.X <= keepMax.X
				and position.Y >= keepMin.Y and position.Y <= keepMax.Y and position.Z >= keepMin.Z and position.Z <= keepMax.Z))
			if near and visibleInPreview(obj) then
				local copy = obj:Clone()
				if copy then
					stripCopy(copy)
					copy.Anchored = true
					copy.Parent = model
					extend(all, obj)
					count += 1
					if count % PREVIEW_BATCH == 0 then
						task.wait()
					end
				end
			end
		end
		local allMin, allMax = all.Min, all.Max
		if not allMin or not allMax then
			previews[mapId] = nil
			model:Destroy()
			return
		end
		-- Einpassen: Fläche des Bodens, Höhe bis PREVIEW_HEIGHT darüber
		local areaMin, areaMax = floorMin or allMin, floorMax or allMax
		local top = math.min(allMax.Y, areaMax.Y + PREVIEW_HEIGHT)
		local low = Vector3.new(areaMin.X, areaMin.Y, areaMin.Z)
		local high = Vector3.new(areaMax.X, top, areaMax.Z)
		preview.Model = model
		preview.Camera = framePreview(low, high, CARD_W / CARD_H)
		preview.Light = LIGHT[source:GetAttribute("Atmosphere") or ""] or LIGHT.Default
		preview.Used = os.clock()
		preview.Ready = true
		trimPreviews()
		refresh()
	end)
	return true
end

-- Vorschau der Map in eine Karte hängen (oder "lädt" zeigen, solange sie gebaut wird)
local function showPreview(entry, mapId)
	local preview = previews[mapId]
	local ready = preview ~= nil and preview.Ready
	if entry.ShownMap == mapId and entry.ShownReady == ready then
		return
	end
	if entry.Model and entry.Model.Parent == entry.Viewport and (not ready or entry.Model ~= preview.Model) then
		entry.Model.Parent = nil -- gehört jetzt evtl. einer anderen Karte, bleibt im Zwischenspeicher
	end
	entry.ShownMap, entry.ShownReady = mapId, ready
	entry.Model = nil
	if not ready then
		entry.Viewport.ImageTransparency = 1
		local building = buildPreview(mapId)
		entry.Loading.Visible = building
		if not building then
			entry.ShownMap = nil -- Map (noch) nicht da: beim nächsten refresh neu versuchen
		end
		return
	end
	entry.Model = preview.Model
	preview.Model.Parent = entry.Viewport
	preview.Used = os.clock()
	entry.Camera.CFrame = preview.Camera
	entry.Viewport.Ambient = preview.Light.Ambient
	entry.Viewport.LightColor = preview.Light.Light
	entry.Loading.Visible = false
	entry.Viewport.ImageTransparency = 1
	TweenService:Create(entry.Viewport, TweenInfo.new(0.35), { ImageTransparency = 0 }):Play()
end

-- ---------- Aufbau ----------

local function buildCard(row, i)
	-- Modal: gibt die Maus frei, solange die Abstimmung offen ist
	local card = make("TextButton", { Size = UDim2.new(0, CARD_W, 0, CARD_H), BackgroundColor3 = C.Card, Text = "",
		AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = i, Modal = i == 1, ClipsDescendants = true }, row)
	UITheme.Corner(card, UITheme.Radius.Large)
	local gradient = UITheme.Gradient(card, C.Card, C.Panel, 90)
	local stroke = UITheme.Stroke(card, C.Border, 1.5)
	local scale = make("UIScale", {}, card)

	local viewport = make("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ImageTransparency = 1,
		LightDirection = LIGHT_DIRECTION, ZIndex = 1 }, card)
	UITheme.Corner(viewport, UITheme.Radius.Large)
	local camera = make("Camera", { FieldOfView = PREVIEW_FOV }, viewport)
	viewport.CurrentCamera = camera
	local loading = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(1, 0, 0, 20), Text = "VORSCHAU LÄDT …", TextSize = 14, TextColor3 = C.Muted, ZIndex = 2,
		TextXAlignment = Enum.TextXAlignment.Center }, card)

	-- Abdunklung unten (Name und Stimmen lesbar) und schmal oben (Taste, DEINE WAHL)
	local bottomShade = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.6), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 2 }, card)
	UITheme.Corner(bottomShade, UITheme.Radius.Large)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.55, 0.45), NumberSequenceKeypoint.new(1, 0.08) }) }, bottomShade)
	local topShade = make("Frame", { Size = UDim2.fromScale(1, 0.3), BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0, ZIndex = 2 }, card)
	UITheme.Corner(topShade, UITheme.Radius.Large)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 1) }, topShade)

	local key = UITheme.Label({ Position = UDim2.new(0, 14, 0, 12), Size = UDim2.new(0, 30, 0, 30), Text = tostring(i),
		Font = UITheme.Fonts.Title, TextSize = 20, BackgroundTransparency = 0.15, BackgroundColor3 = C.Background,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, card)
	UITheme.Corner(key, 3)
	local name = UITheme.Label({ Position = UDim2.new(0, 18, 1, -80), Size = UDim2.new(1, -36, 0, 46), Text = "",
		Font = UITheme.Fonts.Title, TextSize = 42, TextStrokeTransparency = 0.6, ZIndex = 3 }, card)
	local votes = UITheme.Label({ Position = UDim2.new(0, 18, 1, -34), Size = UDim2.new(1, -36, 0, 22), Text = "",
		Font = UITheme.Fonts.Title, TextSize = 18, TextColor3 = Color3.fromRGB(196, 202, 210), ZIndex = 3 }, card)
	local bar = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0, 0, 0, 4), BackgroundColor3 = C.Accent, BorderSizePixel = 0, ZIndex = 4 }, card)
	local check = UITheme.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.new(0, 132, 0, 30), Text = "DEINE WAHL", Font = UITheme.Fonts.Title, TextSize = 18,
		TextColor3 = C.OnLight, BackgroundTransparency = 0, BackgroundColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 3 }, card)
	UITheme.Corner(check, 3)

	-- Überfahren / Controller-Auswahl: Karte hebt sich leicht
	local function hover(on)
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = on and 1.03 or 1 }):Play()
	end
	card.MouseEnter:Connect(function()
		hover(true)
	end)
	card.MouseLeave:Connect(function()
		hover(false)
	end)
	card.SelectionGained:Connect(function()
		hover(true)
	end)
	card.SelectionLost:Connect(function()
		hover(false)
	end)
	card.Activated:Connect(function()
		vote(i)
	end)
	return { Card = card, Gradient = gradient, Stroke = stroke, Name = name, Votes = votes, Bar = bar, Check = check,
		Viewport = viewport, Camera = camera, Loading = loading }
end

local function build()
	gui = make("ScreenGui", { Name = "MapVote", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = DISPLAY_ORDER,
		Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	-- Undurchsichtiger Hintergrund: nichts vom HUD oder der Welt scheint durch
	local background = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, Active = true }, gui)
	UITheme.Gradient(background, Color3.fromRGB(20, 24, 31), Color3.fromRGB(6, 7, 10), 90)
	local canvas = UITheme.Canvas(background, 1600, 900)

	captionLabel = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 160),
		Size = UDim2.new(0, 800, 0, 22), Text = "", TextSize = 16, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)
	UITheme.Diamond(canvas, 18, UDim2.new(0.5, 0, 0, 208), C.Accent)
	UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 224), Size = UDim2.new(0, 800, 0, 56),
		Text = "MAP-ABSTIMMUNG", Font = UITheme.Fonts.Title, TextSize = 52, TextXAlignment = Enum.TextXAlignment.Center }, canvas)
	timerLabel = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 280),
		Size = UDim2.new(0, 800, 0, 26), Text = "", Font = UITheme.Fonts.Title, TextSize = 22, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)
	local track = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 314),
		Size = UDim2.new(0, 360, 0, 3), BackgroundColor3 = C.Border, BorderSizePixel = 0 }, canvas)
	timerBar = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Accent, BorderSizePixel = 0 }, track)

	local row = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 346),
		Size = UDim2.new(0, CARD_W * 3 + CARD_GAP * 2, 0, CARD_H), BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, CARD_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for i = 1, 3 do
		cards[i] = buildCard(row, i)
	end
	hintLabel = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 692), Size = UDim2.new(0, 800, 0, 24),
		Text = "", Font = UITheme.Fonts.Body, TextSize = 17, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)
	-- Das HUD (mit seinem VERLASSEN) ist verdeckt: eigener Knopf unten links
	LeaveButton.new(canvas, { Name = "LeaveButton", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 40, 0, 860),
		Size = UDim2.new(0, 190, 0, 34) })
end

function refresh()
	local options = decode("MapVoteOptions")
	local show = options ~= nil and player:GetAttribute("RoundPhase") == "MapVote"
	gui.Enabled = show
	if not show then
		lastVoteEnd = nil
		return
	end
	local counts = decode("MapVoteCounts") or {}
	local mine = player:GetAttribute("MapVoteMine")
	local total = 0
	for _, n in counts do
		total += n
	end
	local modeInfo = Modes.Get(player:GetAttribute("Mode"))
	captionLabel.Text = (modeInfo and modeInfo.Name .. "  ·  " or "") .. "NÄCHSTE MAP"
	local device = InputActions.Device()
	hintLabel.Text = device == "Gamepad" and "Mit dem Steuerkreuz wählen, A drücken"
		or InputActions.IsTouch() and "Karte antippen" or "Klicken oder 1 / 2 / 3 drücken"
	-- Zeitbalken: Länge der Abstimmung beim Öffnen merken
	local voteEnd = player:GetAttribute("MapVoteEnd")
	if type(voteEnd) == "number" and lastVoteEnd == nil then
		voteTotal = math.max(1, voteEnd - workspace:GetServerTimeNow())
	end
	lastVoteEnd = voteEnd
	for i, entry in cards do
		local option = options[i]
		entry.Card.Visible = option ~= nil
		if option then
			local mood = MOODS[option.Name] or { C.Card, C.Panel }
			entry.Gradient.Color = ColorSequence.new(mood[1], mood[2])
			entry.Name.Text = UITheme.Upper(option.Name)
			local n = counts[i] or 0
			entry.Votes.Text = n .. (n == 1 and " STIMME" or " STIMMEN")
			entry.Bar.Size = UDim2.new(total > 0 and n / total or 0, 0, 0, 4)
			entry.Stroke.Color = mine == i and C.Accent or C.Border
			entry.Stroke.Thickness = mine == i and 3 or 1.5
			entry.Check.Visible = mine == i
			if type(option.Id) == "string" then
				showPreview(entry, option.Id)
			end
		end
	end
end

function MapVote.Init()
	build()
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 7) == "MapVote" or name == "RoundPhase" or name == "Mode" then
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local index = table.find(KEYS, input.KeyCode)
		if index then
			vote(index)
		end
	end)
	-- Controller: erste Karte auswählen, damit man mit dem Steuerkreuz wählen kann;
	-- Maus frei, solange abgestimmt wird (in FFA steht man dabei noch in der Ego-Perspektive)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			RunService:BindToRenderStep("MapVoteMouse", Enum.RenderPriority.Camera.Value + 2, function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			end)
		else
			RunService:UnbindFromRenderStep("MapVoteMouse")
		end
		if gui.Enabled and InputActions.Device() == "Gamepad" then
			GuiService.SelectedObject = cards[1].Card
		elseif not gui.Enabled and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
	end)
	RunService.Heartbeat:Connect(function()
		if gui.Enabled then
			local left = math.max(0, (player:GetAttribute("MapVoteEnd") or 0) - workspace:GetServerTimeNow())
			timerLabel.Text = "NOCH " .. math.ceil(left) .. (math.ceil(left) == 1 and " SEKUNDE" or " SEKUNDEN")
			timerBar.Size = UDim2.fromScale(math.clamp(left / voteTotal, 0, 1), 1)
		end
	end)
	refresh()
end

return MapVote

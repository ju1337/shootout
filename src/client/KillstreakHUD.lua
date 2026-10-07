-- KillstreakHUD (ModuleScript, nur Client)
-- Killstreaks in Herrschaft rechts am Rand in der Mitte. Oben die Killserie dieses Lebens als große Zahl, die bei
-- jedem Kill aufspringt, daneben die nächste Belohnung ("LUFTSCHLAG IN 2"). Darunter eine Karte pro Belohnung
-- (KillstreakConfig): gezeichnetes Symbol (Drohne, Jet, Schild), Name und ein Segment pro nötigem Kill, die sich
-- in der Farbe der Belohnung füllen. Wird eine bereit, fährt ihre Karte herein, blitzt auf, ein Glanz läuft
-- darüber und das Symbol pulsiert in seiner Farbe, bis man sie auslöst: 4/5/6 (Controller: Steuerkreuz rechts =
-- erste bereite, Touch/Maus: Karte antippen). Luftschlag: Ziel ist der Punkt unter dem Fadenkreuz.
-- Daten: Spieler-Attribute Killstreak (Kills dieses Lebens), KillstreakReady (JSON { [Id] = true }).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)
local KillstreakConfig = require(Shared.KillstreakConfig)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make = UITheme.Make
local label = UITheme.Label

local KillstreakHUD = {}

local WIDTH, CARD_H, GAP, HEADER_H = 270, 62, 8, 56
local TILE = 46          -- Kachel mit dem Symbol (rechts in der Karte)
local TILE_RIGHT = 14    -- Abstand der Kachel zum rechten Rand
local TEXT_RIGHT = TILE_RIGHT + TILE + 12 -- rechter Rand von Name und Segmenten
local PIPS_W, PIP_GAP = 132, 3
local WHITE = Color3.new(1, 1, 1)

local function readyList()
	local raw = player:GetAttribute("KillstreakReady")
	local ok, data = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "{}")
	return ok and type(data) == "table" and data or {}
end

-- Punkt unter dem Fadenkreuz (Boden oder Wand), für den Luftschlag
local function aimPoint()
	local camera = workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, workspace:FindFirstChild("Bots") }
	local result = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 400, params)
	return result and result.Position or nil
end

local function use(entry)
	if not readyList()[entry.Id] then
		return
	end
	Remotes.UseKillstreak:FireServer(entry.Id, entry.Aim and aimPoint() or nil)
end

local function tween(object, time, props, style, direction)
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- ---------- Symbole ----------
-- Gezeichnet aus Strichen und Kreisen im Halter (36 x 36, Maße in Pixeln relativ zur Mitte). Jeder Baustein kommt
-- in die Liste paint, damit die Karte das ganze Symbol umfärben kann (bereit: weiß, sonst in der Farbe der Belohnung).

local function bar(holder, paint, x, y, w, h, rotation, radius)
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, y),
		Size = UDim2.fromOffset(w, h), Rotation = rotation or 0, BorderSizePixel = 0 }, holder)
	if radius then
		make("UICorner", { CornerRadius = UDim.new(0, radius) }, frame)
	end
	table.insert(paint, frame)
	return frame
end
local function ring(holder, paint, x, y, size, thickness)
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, y),
		Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, holder)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
	table.insert(paint, make("UIStroke", { Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame))
	return frame
end

local ICONS = {}
-- Quadrocopter von oben: Rumpf, zwei gekreuzte Arme, vier Rotoren
ICONS.Radar = function(holder, paint)
	bar(holder, paint, 0, 0, 30, 3, 45)
	bar(holder, paint, 0, 0, 30, 3, -45)
	for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		ring(holder, paint, corner[1] * 11, corner[2] * 11, 11, 2)
	end
	bar(holder, paint, 0, 0, 11, 11, 0, 3)
end
-- Kampfjet von oben, Nase nach oben: Rumpf, gepfeilte Flügel, Leitwerk
ICONS.Airstrike = function(holder, paint)
	bar(holder, paint, 0, 0, 5, 30, 0, 2)
	bar(holder, paint, 0, -14.5, 4.5, 4.5, 45)
	bar(holder, paint, -7.5, 2.5, 18, 5, -26)
	bar(holder, paint, 7.5, 2.5, 18, 5, 26)
	bar(holder, paint, -4.5, 13, 9, 3.5, -24)
	bar(holder, paint, 4.5, 13, 9, 3.5, 24)
end
-- Schild als Umriss mit Kreuz in der Mitte
ICONS.Shield = function(holder, paint)
	bar(holder, paint, 0, -12, 24, 3)
	bar(holder, paint, -10.5, -5, 3, 17)
	bar(holder, paint, 10.5, -5, 3, 17)
	bar(holder, paint, -5.2, 8.6, 18.5, 3, 54)
	bar(holder, paint, 5.2, 8.6, 18.5, 3, -54)
	bar(holder, paint, 0, -2, 3, 11)
	bar(holder, paint, 0, -2, 11, 3)
end

-- Symbol bauen (unbekannte Belohnungen: Kurzbuchstabe). Gibt eine Funktion zum Umfärben zurück.
local function buildIcon(parent, entry)
	local holder = make("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1 }, parent)
	local paint = {}
	local draw = ICONS[entry.Id]
	local letter = nil
	if draw then
		draw(holder, paint)
	else
		letter = label({ Size = UDim2.fromScale(1, 1), Text = entry.Short or "", TextSize = 26, Font = F.Display,
			TextXAlignment = Enum.TextXAlignment.Center }, holder)
	end
	return function(color, transparency)
		for _, part in paint do
			if part:IsA("UIStroke") then
				part.Color = color
				part.Transparency = transparency
			else
				part.BackgroundColor3 = color
				part.BackgroundTransparency = transparency
			end
		end
		if letter then
			letter.TextColor3 = color
			letter.TextTransparency = transparency
		end
	end
end

-- ---------- Karten ----------

local function buildCard(column, entry, index)
	local card = make("TextButton", { Name = entry.Id, Position = UDim2.fromOffset(0, HEADER_H + (index - 1) * (CARD_H + GAP)),
		Size = UDim2.fromOffset(WIDTH, CARD_H), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		Selectable = false, ClipsDescendants = true }, column)
	-- Inhalt in eigenem Rahmen: fährt beim Bereitwerden von rechts herein
	local inner = make("Frame", { Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.2, BorderSizePixel = 0 }, card)
	UITheme.Corner(inner, UITheme.Radius.Small)
	-- links ausblenden, damit die Karte zur Bildmitte hin in die Welt übergeht
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.95),
		NumberSequenceKeypoint.new(0.45, 0.25), NumberSequenceKeypoint.new(1, 0) }) }, inner)
	local accent = UITheme.AccentBar(inner, entry.Color, { Side = "Right" })

	-- Kachel mit Symbol und pulsierendem Schein dahinter
	local halo = make("Frame", { Name = "Halo", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -(TILE_RIGHT + TILE / 2), 0.5, 0), Size = UDim2.fromOffset(TILE, TILE),
		BackgroundColor3 = entry.Color, BackgroundTransparency = 1, BorderSizePixel = 0 }, inner)
	UITheme.Corner(halo, UITheme.Radius.Medium)
	local tile = make("Frame", { Name = "Tile", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -TILE_RIGHT, 0.5, 0),
		Size = UDim2.fromOffset(TILE, TILE), BackgroundColor3 = entry.Color, BorderSizePixel = 0 }, inner)
	UITheme.Corner(tile, UITheme.Radius.Small)
	local tileStroke = UITheme.Stroke(tile, entry.Color, 1.5, 0.4)
	local paintIcon = buildIcon(tile, entry)

	local name = label({ Name = "Title", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TEXT_RIGHT, 0, 8),
		Size = UDim2.fromOffset(WIDTH - TEXT_RIGHT - 12, 24), Text = entry.Name, TextSize = 21, Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd }, inner)

	-- Fortschritt: ein Segment pro Kill, links davon "6 / 8"
	local pips = make("Frame", { Name = "Pips", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TEXT_RIGHT, 0, 39),
		Size = UDim2.fromOffset(PIPS_W, 6), BackgroundTransparency = 1 }, inner)
	local pipW = (PIPS_W - PIP_GAP * (entry.Kills - 1)) / entry.Kills
	local pipList = {}
	for i = 1, entry.Kills do
		local pip = make("Frame", { Position = UDim2.fromOffset((i - 1) * (pipW + PIP_GAP), 0), Size = UDim2.new(0, pipW, 1, 0),
			BackgroundColor3 = WHITE, BackgroundTransparency = 0.85, BorderSizePixel = 0 }, pips)
		make("UICorner", { CornerRadius = UDim.new(0, 2) }, pip)
		pipList[i] = pip
	end
	local count = label({ Name = "Count", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(TEXT_RIGHT + PIPS_W + 8), 0, 42),
		Size = UDim2.fromOffset(44, 14), Text = "", TextSize = 11, Font = F.Bold, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right }, inner)

	-- Bereit: Taste + Schild statt der Segmente
	local readyRow = make("Frame", { Name = "ReadyRow", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TEXT_RIGHT, 0, 34),
		Size = UDim2.fromOffset(WIDTH - TEXT_RIGHT - 12, 20), BackgroundTransparency = 1, Visible = false }, inner)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, readyRow)
	local key = label({ Name = "Key", LayoutOrder = 1, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
		Text = "", TextSize = 12, Font = F.Bold, TextColor3 = C.Text, BackgroundColor3 = C.Background, BackgroundTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center }, readyRow)
	UITheme.Corner(key, 4)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, key)
	local keyStroke = UITheme.Stroke(key, entry.Color, 1, 0)
	local tag = UITheme.Tag({ Name = "Tag", LayoutOrder = 2, Text = "BEREIT", TextSize = 11, Font = F.Bold,
		BackgroundColor3 = entry.Color, Size = UDim2.fromOffset(0, 20) }, readyRow)

	-- Effekte beim Bereitwerden: Aufblitzen und ein Glanzstreifen
	local flash = make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = entry.Color,
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3 }, inner)
	UITheme.Corner(flash, UITheme.Radius.Small)
	local shine = make("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE,
		BorderSizePixel = 0, Visible = false, ZIndex = 3 }, inner)
	local shineGradient = make("UIGradient", { Rotation = 20, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }) }, shine)

	card.Activated:Connect(function()
		use(entry)
	end)

	local state = { Ready = nil, Pulse = {} }
	local function stopPulse()
		for _, t in state.Pulse do
			t:Cancel()
		end
		state.Pulse = {}
	end

	-- Darstellung setzen. kills = Kills dieses Lebens, hint = Tastenname ("" = keiner), touch = Touch-Gerät.
	local function apply(isReady, kills, hint, touch)
		local fresh = isReady and state.Ready == false
		if isReady ~= state.Ready then
			state.Ready = isReady
			stopPulse()
			inner.BackgroundColor3 = isReady and entry.Color:Lerp(C.Background, 0.72) or C.Background
			accent.BackgroundTransparency = isReady and 0 or 0.65
			tile.BackgroundTransparency = isReady and 0.15 or 0.86
			tileStroke.Transparency = isReady and 0 or 0.55
			tileStroke.Thickness = 1.5
			paintIcon(isReady and WHITE or entry.Color, isReady and 0 or 0.3)
			name.TextColor3 = isReady and C.Text or C.Muted
			pips.Visible = not isReady
			count.Visible = not isReady
			readyRow.Visible = isReady
			halo.Size = UDim2.fromOffset(TILE, TILE)
			halo.BackgroundTransparency = 1
			if isReady then
				-- solange bereit: Rand und Schein der Kachel pulsieren
				local info = TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
				halo.BackgroundTransparency = 0.7
				state.Pulse = {
					TweenService:Create(tileStroke, info, { Thickness = 3.5, Transparency = 0.35 }),
					TweenService:Create(halo, info, { Size = UDim2.fromOffset(TILE + 14, TILE + 14), BackgroundTransparency = 0.95 }),
				}
				for _, t in state.Pulse do
					t:Play()
				end
			end
		end
		if fresh then
			inner.Position = UDim2.fromOffset(46, 0)
			tween(inner, 0.45, { Position = UDim2.new() }, Enum.EasingStyle.Back)
			flash.BackgroundTransparency = 0.25
			tween(flash, 0.6, { BackgroundTransparency = 1 })
			shine.Visible = true
			shineGradient.Offset = Vector2.new(-1, 0)
			tween(shineGradient, 0.7, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				.Completed:Connect(function()
					shine.Visible = false
				end)
		end
		if isReady then
			key.Visible = hint ~= ""
			key.Text = hint
			keyStroke.Color = entry.Color
			tag.Text = touch and "ANTIPPEN" or "BEREIT"
		else
			local filled = math.clamp(kills, 0, entry.Kills)
			for i, pip in pipList do
				local on = i <= filled
				pip.BackgroundColor3 = on and entry.Color or WHITE
				pip.BackgroundTransparency = on and 0 or 0.85
			end
			count.Text = filled .. " / " .. entry.Kills
		end
	end

	return { Card = card, Apply = apply }
end

function KillstreakHUD.Init()
	local gui = make("ScreenGui", { Name = "Killstreaks", ResetOnSpawn = false, IgnoreGuiInset = true, Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	local root = UITheme.ScaledRoot(gui)
	local count = #KillstreakConfig.List
	local column = make("Frame", { Name = "Column", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 10),
		Size = UDim2.fromOffset(WIDTH, HEADER_H + count * CARD_H + (count - 1) * GAP), BackgroundTransparency = 1 }, root)

	-- Kopf: Killserie als große Zahl über den Kacheln, daneben die nächste Belohnung
	local streak = label({ Name = "Streak", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(1, -(TILE_RIGHT + TILE / 2), 0, 0),
		Size = UDim2.fromOffset(80, 44), Text = "0", TextSize = 44, Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Center }, column)
	UITheme.Outline(streak, 1)
	local streakScale = make("UIScale", {}, streak)
	label({ Name = "Caption", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TEXT_RIGHT, 0, 7),
		Size = UDim2.fromOffset(WIDTH - TEXT_RIGHT, 14), Text = "KILLSERIE", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.7 }, column)
	local nextLine = label({ Name = "Next", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TEXT_RIGHT, 0, 23),
		Size = UDim2.fromOffset(WIDTH - TEXT_RIGHT, 16), Text = "", TextSize = 13, Font = F.Bold,
		TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.7 }, column)
	local divider = make("Frame", { Name = "Divider", Position = UDim2.fromOffset(0, HEADER_H - 9), Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, column)
	make("UIGradient", { Transparency = NumberSequence.new(1, 0.55) }, divider)

	local cards = {}
	for i, entry in KillstreakConfig.List do
		cards[entry.Id] = buildCard(column, entry, i)
	end

	local lastKills = 0
	local function refresh()
		local inMode = KillstreakConfig.Modes[player:GetAttribute("Mode")] == true
		gui.Enabled = inMode
		if not inMode then
			return
		end
		local kills = tonumber(player:GetAttribute("Killstreak")) or 0
		local ready = readyList()
		local touch = InputActions.IsTouch()
		local gamepad = InputActions.Device() == "Gamepad"
		local padFirst = true
		local nextEntry = nil
		for _, entry in KillstreakConfig.List do
			local isReady = ready[entry.Id] == true
			-- Taste fürs aktuelle Gerät (Controller: Steuerkreuz rechts für die erste bereite, Touch: keine)
			local hint = ""
			if gamepad then
				hint = (isReady and padFirst) and InputActions.Hint("KillstreakPad") or ""
			elseif not touch then
				hint = InputActions.Hint(entry.Action)
			end
			if isReady then
				padFirst = false
			end
			cards[entry.Id].Apply(isReady, kills, hint, touch)
			if not nextEntry and entry.Kills > kills then
				nextEntry = entry
			end
		end

		-- Kopf: Zahl springt bei jedem neuen Kill auf
		streak.Text = tostring(kills)
		streak.TextColor3 = kills > 0 and C.Text or C.Muted
		if kills > lastKills then
			streakScale.Scale = 1.45
			tween(streakScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			streak.TextColor3 = nextEntry and nextEntry.Color or C.Good
			tween(streak, 0.5, { TextColor3 = C.Text })
		end
		lastKills = kills
		if nextEntry then
			local missing = nextEntry.Kills - kills
			nextLine.Text = nextEntry.Name .. " IN " .. missing .. (missing == 1 and " KILL" or " KILLS")
			nextLine.TextColor3 = nextEntry.Color
		else
			nextLine.Text = "MAXIMALE SERIE"
			nextLine.TextColor3 = C.Good
		end
	end
	refresh()
	for _, attribute in { "Killstreak", "KillstreakReady", "Mode" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	InputActions.DeviceChanged:Connect(refresh)

	-- Tasten 4/5/6 und Controller (erste bereite)
	for _, entry in KillstreakConfig.List do
		InputActions.Bind(entry.Action, function(began)
			if began and gui.Enabled then
				use(entry)
			end
		end)
	end
	InputActions.Bind("KillstreakPad", function(began)
		if not began or not gui.Enabled then
			return
		end
		local ready = readyList()
		for _, entry in KillstreakConfig.List do
			if ready[entry.Id] then
				use(entry)
				return
			end
		end
	end)
end

return KillstreakHUD

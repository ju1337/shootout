-- Notifications (ModuleScript, nur Client)
-- Meldungen im Stil von Call of Duty auf einer eigenen Ebene über HUD und Menüs:
--   * Medaillen (Remotes.Notify "Medal"): Abzeichen mit Symbol, großer Titel mit Glanz, seitliche Linien,
--     darunter XP/Münzen und weitere Medaillen desselben Kills als kleine Schilder. Unter dem Fadenkreuz,
--     nacheinander; Mehrfach-Kills ersetzen sich sofort (DOPPEL-KILL -> TRIPLE-KILL). Stufe 1-4 bestimmt
--     Farbe, Größe, Standzeit und Klang.
--   * Banner ("Banner"): breites Band im oberen Drittel, öffnet sich von der Mitte aus (RUNDE 3,
--     RUNDE GEWONNEN, SIEG, OVERTIME). Daten: { Caption, Title, Sub, Style, Big }; Style = Win, Loss,
--     Info, Neutral oder Alert (Farben aus Sicht des Spielers, der Server schickt jedem seine Sicht).
--   * Ziel-Meldungen ("Objective"): schmale Leiste unter dem Punktestand (FLAGGE A EINGENOMMEN) mit Raute
--     in Team-, Gegner- oder Warnfarbe. Daten: { Text, Side = Ally/Enemy/Alert/Neutral, Icon = Buchstabe }
--   * Fortschritt ("Progress"): Karte links, fährt herein (LEVEL 12, BATTLE PASS STUFE 5, PRESTIGE) – auch alle
--     Belohnungen vom RewardService (Remotes.Reward: Meilensteine, Meisterschaft, Titel, Wochen-Bonus, Saison).
--     Daten: { Caption, Title, Sub, Badge, Style oder Color, Key, Primary }. Karten mit gleichem Key werden zu
--     einer zusammengeführt (LEVEL 20 + Belohnung "LEVEL 20 ERREICHT" -> eine Karte mit den Münzen), Primary
--     behält dabei Überschrift und Titel. Level-Aufstiege (Spieler und Agent) erkennt das Modul selbst.
--     Die Karten liegen auf einer eigenen Ebene über Menüs und Match-Zusammenfassung.
-- Remotes.Announce (einfacher Text) erscheint als neutrales Banner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Sfx = require(Shared.Sfx)
local UITheme = require(Shared.UITheme)
local Medals = require(Shared.Medals)
local AgentConfig = require(Shared.AgentConfig)
local LevelConfig = require(Shared.LevelConfig)
local Cosmetics = require(Shared.Cosmetics)
local InputActions = require(Shared.InputActions)
local TopStack = require(Shared.TopStack)
local Modes = require(Shared.Modes)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make = UITheme.Make
local upper = UITheme.Upper

local Notifications = {}

local WHITE = Color3.new(1, 1, 1)
local ORANGE = Color3.fromRGB(226, 128, 52)
local RED = Color3.fromRGB(222, 64, 52)
local BLOOD = Color3.fromRGB(196, 38, 38)

-- Medaillen nach Stufe: Farbe, Titelgröße, Standzeit
local TIER_COLORS = { Color3.fromRGB(232, 234, 238), C.Primary, ORANGE, RED }
local TIER_TEXT = { 38, 44, 50, 56 }
local TIER_HOLD = { 1.8, 2.2, 2.6, 3.1 }

-- Banner/Fortschritt: Farbe je Stil; Ziel-Meldungen: Farbe je Seite
local STYLES = { Win = C.Ally, Loss = C.Enemy, Info = C.Primary, Neutral = C.Muted, Alert = ORANGE,
	Level = C.Primary, Pass = C.Gold, Prestige = ORANGE }
local SIDES = { Ally = C.Ally, Enemy = C.Enemy, Alert = ORANGE, Neutral = C.Text }

local MEDAL_TOP = 170       -- Oberkante der Medaille unter der Bildschirmmitte: mit Abstand unter Fadenkreuz und Kill-Meldung,
                            -- über den Fähigkeiten-Karten unten in der Mitte (AbilityClient)
local MEDAL_TOP_TOUCH = 90  -- Touch: unten in der Mitte liegen Munition, Geld und Fähigkeiten, darum höher
local MEDAL_PAD = 70        -- Rand in der CanvasGroup, damit das große Abzeichen beim Einfliegen nicht abgeschnitten wird
local BANNER_Y = 0.3        -- Mitte des Banners (Anteil der Bildschirmhöhe), weiter unten wenn oben belegt (TopStack)
local OBJECTIVE_Y = 150     -- Ziel-Meldungen unter Punktestand und Zustandsschild
local MEDAL_MIN = 0.7       -- Mindest-Standzeit, wenn schon die nächste Meldung wartet
local BANNER_MIN = 1.6
local OBJECTIVE_MIN = 1.2
local PROGRESS_MIN = 1.6
local BANNER_HOLD = 2.6
local OBJECTIVE_HOLD = 2.8
local PROGRESS_HOLD = 3.6

local PING = "rbxasset://sounds/electronicpingshort.wav"
local THUD = "rbxasset://sounds/switch.wav"

local layers: { [string]: any } = {} -- Medal, Banner, Objective, Progress: Warteschlangen der Anzeigen (siehe build*)

-- ---------- Helfer ----------

local function tween(object, time, props, style, direction, delay)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, 0, false, delay or 0)
	local t = TweenService:Create(object, info, props)
	t:Play()
	return t
end

local function tone(id, speed, volume, delay)
	task.delay(delay or 0, function()
		local sound = Instance.new("Sound")
		sound.SoundId = id
		sound.PlaybackSpeed = speed
		sound.Volume = volume
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 3)
	end)
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or C.Text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	props.Font = UITheme.FontFor(props.Font or F.Bold, props.TextSize)
	return make("TextLabel", props, parent)
end

-- Verlauf, der links und rechts ausblendet (Bänder und Linien)
local function edgeFade(parent, edge)
	return make("UIGradient", { Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(edge, 0), NumberSequenceKeypoint.new(1 - edge, 0),
		NumberSequenceKeypoint.new(1, 1) }) }, parent)
end

-- Glanz: ein heller Streifen läuft einmal über den Text (Text weiß, Farbe kommt aus dem Verlauf)
local function shine(gradient, color, time, delay)
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(0.4, color), ColorSequenceKeypoint.new(0.5, WHITE),
		ColorSequenceKeypoint.new(0.6, color), ColorSequenceKeypoint.new(1, color) })
	gradient.Offset = Vector2.new(-1, 0)
	tween(gradient, time, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, delay)
end

-- Kleine Bausteine für Symbole, Maße in Pixeln relativ zur Mitte des Halters
local function bar(parent, x, y, w, h, rotation, color)
	return make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0.5, y),
		Size = UDim2.fromOffset(w, h), Rotation = rotation or 0, BackgroundColor3 = color, BorderSizePixel = 0 }, parent)
end
local function circle(parent, x, y, size, color)
	local frame = bar(parent, x, y, size, size, 0, color)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
	return frame
end
local function ring(parent, x, y, size, color, thickness)
	local frame = circle(parent, x, y, size, color)
	frame.BackgroundTransparency = 1
	make("UIStroke", { Color = color, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	return frame
end
local function glyph(parent, text, size, color, y, font)
	return label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, y or 0),
		Size = UDim2.new(2, 0, 0, size + 4), Text = text, TextSize = size, Font = font or F.Display, TextColor3 = color,
		RichText = true }, parent)
end
-- Winkel "^" aus zwei Strichen (Spitze bei y - 5)
local function chevron(parent, y, width, color, thickness)
	bar(parent, -width / 4, y, width / 2 + 2, thickness, -40, color)
	bar(parent, width / 4, y, width / 2 + 2, thickness, 40, color)
end

-- Symbole im Abzeichen (Halter 34 x 34, nicht gedreht)
local ICONS = {}
ICONS.Multi = function(holder, color, entry, medal)
	local count = entry.Count or medal.Count or 2
	glyph(holder, '<font size="15">X</font>' .. (count >= 9 and "9+" or tostring(count)), 28, color, 1)
end
ICONS.Streak = function(holder, color, entry, medal)
	chevron(holder, -11, 18, color, 3)
	glyph(holder, tostring(entry.Count or medal.Count or ""), 22, color, 5)
end
ICONS.Blood = function(holder)
	-- Tropfen: Kreis und darüber eine Raute, deren Seiten den Kreis berühren
	circle(holder, 0, 2.5, 22.5, BLOOD)
	bar(holder, 0, -5.5, 11.25, 11.25, 45, BLOOD)
end
ICONS.Revenge = function(holder, color)
	-- zwei gekreuzte Klingen mit Parierstangen
	bar(holder, 0, 0, 30, 3, 45, color)
	bar(holder, 0, 0, 30, 3, -45, color)
	bar(holder, 6, 6, 10, 3, -45, color)
	bar(holder, -6, 6, 10, 3, 45, color)
end
ICONS.Longshot = function(holder, color)
	ring(holder, 0, 0, 24, color, 2)
	bar(holder, 0, -10, 2, 10, 0, color)
	bar(holder, 0, 10, 2, 10, 0, color)
	bar(holder, -10, 0, 10, 2, 0, color)
	bar(holder, 10, 0, 10, 2, 0, color)
	circle(holder, 0, 0, 4, RED)
end
ICONS.Headshot = function(holder, color)
	circle(holder, 0, -5, 13, color)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, bar(holder, 0, 10, 24, 10, 0, color))
	ring(holder, 0, -5, 20, RED, 1.5)
end
ICONS.Buzzkill = function(holder, color)
	chevron(holder, -2, 22, color, 3)
	chevron(holder, 6, 22, color, 3)
	bar(holder, 0, 2, 32, 3, -55, RED)
end
ICONS.Comeback = function(holder, color)
	bar(holder, 0, 4, 4, 20, 0, color)
	bar(holder, -5.5, -6, 15, 4, -45, color)
	bar(holder, 5.5, -6, 15, 4, 45, color)
end
ICONS.Clutch = function(holder, color, entry)
	glyph(holder, "1V" .. tostring(entry.Count or ""), 22, color, 1)
end
ICONS.Ace = function(holder, color)
	glyph(holder, "★", 30, color, 1, F.Bold) -- Gotham kennt den Stern, Oswald nicht
end
ICONS.Bomb = function(holder, color)
	circle(holder, -2, 4, 22, color)
	bar(holder, 8, -9, 3, 9, 40, color)
	circle(holder, 11, -13, 5, ORANGE)
end
ICONS.Defuse = function(holder)
	bar(holder, -6, 4, 12, 4, 45, C.Good)
	bar(holder, 5, -0.5, 22, 4, -50, C.Good)
end
ICONS.Flag = function(holder, color)
	bar(holder, -8, 2, 3, 28, 0, color)
	bar(holder, 2, -6, 18, 12, 0, color)
end
ICONS.Hack = function(holder, color)
	local screen = bar(holder, 0, 0, 26, 20, 0, color)
	screen.BackgroundTransparency = 1
	make("UIStroke", { Color = color, Thickness = 2 }, screen)
	bar(holder, -4, -3, 10, 2, 0, color)
	bar(holder, 1, 3, 14, 2, 0, color)
end
ICONS.Ultimate = function(holder, color)
	-- Blitz aus drei Strichen
	bar(holder, 1, -6.5, 17, 4, -62, color)
	bar(holder, 0.5, 0, 8, 4, -16, color)
	bar(holder, 0, 7, 18, 4, -63, color)
end

-- Raute (gedreht) mit Füllung und Rand; Texte/Symbole als Geschwister darüberlegen
local function diamond(parent, size, position, fill, strokeColor, thickness)
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = UDim2.fromOffset(size, size),
		Rotation = 45, BackgroundColor3 = fill or C.Panel, BorderSizePixel = 0 }, parent)
	local stroke = strokeColor and make("UIStroke", { Color = strokeColor, Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	return frame, stroke
end

-- Ausblenden einer Anzeige per Tween; danach unsichtbar, falls sie nicht vorher neu gezeigt wurde.
-- Cancel() bricht ein laufendes Ausblenden ab (beim nächsten Zeigen aufrufen).
local function fader(group)
	local current = nil
	local api = {}
	function api.Cancel()
		if current then
			current:Cancel()
			current = nil
		end
	end
	function api.Hide(instant, time, props, style, direction)
		api.Cancel()
		if instant then
			group.Visible = false
			group.GroupTransparency = 1
			return
		end
		local t = tween(group, time, props, style, direction)
		current = t
		t.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				group.Visible = false
			end
		end)
	end
	return api
end

-- Einfache Warteschlange: zeigt Einträge nacheinander. show(item) gibt die Standzeit zurück, hide() blendet aus.
-- Wartet schon der nächste Eintrag, wird nach minTime gewechselt (oder sofort, wenn skip(aktuell, nächster) true ist).
local function makeQueue(show, hide, minTime, maxQueue, skip)
	local queue = {}
	local current = nil -- gerade gezeigter Eintrag
	local running = false
	local generation = 0
	local api = {}
	-- Gezeigten oder wartenden Eintrag suchen: gibt (Eintrag, wird gerade gezeigt) zurück
	function api.Find(predicate)
		if current and predicate(current) then
			return current, true
		end
		for _, item in queue do
			if predicate(item) then
				return item, false
			end
		end
		return nil, false
	end
	function api.Push(item)
		table.insert(queue, item)
		if #queue > maxQueue then
			table.remove(queue, 1) -- nicht endlos stauen
		end
		if running then
			return
		end
		running = true
		local myGeneration = generation
		task.spawn(function()
			while #queue > 0 and generation == myGeneration do
				local item = table.remove(queue, 1)
				current = item
				local hold = show(item)
				local shown = 0
				while shown < hold and generation == myGeneration do
					local nextItem = queue[1]
					if nextItem and (shown >= minTime or (skip and skip(item, nextItem))) then
						break
					end
					shown += task.wait(0.05)
				end
			end
			if generation == myGeneration then
				current = nil
				hide()
				running = false
			end
		end)
	end
	-- Alles sofort weg (z.B. Moduswechsel)
	function api.Clear()
		generation += 1
		table.clear(queue)
		current = nil
		running = false
		hide(true)
	end
	return api
end

-- ---------- Medaillen ----------

local function medalTop()
	return InputActions.IsTouch() and MEDAL_TOP_TOUCH or MEDAL_TOP
end

local function buildMedal(root)
	local group = make("CanvasGroup", { Name = "Medal", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, medalTop() - MEDAL_PAD), Size = UDim2.fromOffset(820, MEDAL_PAD + 210),
		BackgroundTransparency = 1, GroupTransparency = 1, Visible = false }, root)
	local centerY = MEDAL_PAD + 42

	-- Seitliche Linien (zwei pro Seite, laufen nach außen aus)
	local wings = {}
	for _, side in { -1, 1 } do
		for i, spec in { { 0, 190, 2 }, { 6, 120, 1 } } do
			local wing = make("Frame", { AnchorPoint = Vector2.new(side < 0 and 1 or 0, 0.5),
				Position = UDim2.new(0.5, side * 50, 0, centerY + spec[1]), Size = UDim2.fromOffset(spec[2], spec[3]),
				BackgroundColor3 = WHITE, BorderSizePixel = 0, BackgroundTransparency = i == 1 and 0 or 0.35 }, group)
			make("UIGradient", { Rotation = side < 0 and 180 or 0, Transparency = NumberSequence.new(0, 1) }, wing)
			table.insert(wings, { Frame = wing, Length = spec[2] })
		end
	end

	-- Abzeichen: Schein, Platte mit Rand, innerer Ring, Symbol, Blitz-Ring beim Aufschlagen
	local emblem = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, centerY),
		Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1, ZIndex = 2 }, group) -- über den Strahlen
	local emblemScale = make("UIScale", {}, emblem)
	-- Strahlen hinter dem Abzeichen (nur Stufe 3 und 4), drehen sich langsam
	local rays = {}
	for i = 0, 5 do
		local ray = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, centerY),
			Size = UDim2.fromOffset(170, 2), Rotation = i * 30, BackgroundColor3 = WHITE, BackgroundTransparency = 0.35,
			BorderSizePixel = 0, Visible = false }, group)
		make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.5), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(0.7, 0.5),
			NumberSequenceKeypoint.new(1, 1) }) }, ray)
		table.insert(rays, ray)
	end
	local glow = diamond(emblem, 66, UDim2.fromScale(0.5, 0.5), WHITE)
	glow.BackgroundTransparency = 0.82
	-- Platte: dunkles Metall, oben etwas heller (Verlauf dreht mit der Raute: 45 + 45 = senkrecht)
	local plate, plateStroke = diamond(emblem, 56, UDim2.fromScale(0.5, 0.5), WHITE, WHITE, 2)
	make("UIGradient", { Rotation = 45, Color = ColorSequence.new(Color3.fromRGB(62, 68, 78), Color3.fromRGB(20, 23, 28)) },
		plate)
	local inner, innerStroke = diamond(emblem, 44, UDim2.fromScale(0.5, 0.5), WHITE, WHITE, 1)
	inner.BackgroundTransparency = 1
	innerStroke.Transparency = 0.6
	local iconHolder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1 }, emblem)
	local flash, flashStroke = diamond(emblem, 56, UDim2.fromScale(0.5, 0.5), WHITE, WHITE, 2)
	flash.BackgroundTransparency = 1
	flashStroke.Transparency = 1
	local flashScale = make("UIScale", {}, flash)

	-- Titel mit Glanz, darunter XP/Zusatz und weitere Medaillen
	local title = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, MEDAL_PAD + 86),
		Size = UDim2.new(1, 0, 0, 58), Text = "", TextSize = 44, Font = F.Display, TextColor3 = WHITE }, group)
	make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 0.45,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, title)
	local titleGradient = make("UIGradient", {}, title)
	local titleScale = make("UIScale", {}, title)
	local sub = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, MEDAL_PAD + 144),
		Size = UDim2.new(1, 0, 0, 18), Text = "", TextSize = 14, RichText = true, TextColor3 = C.Text }, group)
	local chips = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, MEDAL_PAD + 168),
		Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, group)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder },
		chips)

	local function chip(entry, order)
		local medal = Medals.Get(entry.Id)
		if not medal then
			return
		end
		local color = TIER_COLORS[medal.Tier] or WHITE
		local frame = make("Frame", { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1, LayoutOrder = order }, chips)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
		local dotHolder = make("Frame", { Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, LayoutOrder = 1 }, frame)
		diamond(dotHolder, 7, UDim2.fromScale(0.5, 0.5), color)
		label({ Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = upper(entry.Title or medal.Title),
			TextSize = 18, Font = F.Display, TextColor3 = color, LayoutOrder = 2 }, frame)
		if (tonumber(entry.Xp) or 0) > 0 then
			label({ Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = "+" .. entry.Xp,
				TextSize = 12, TextColor3 = C.Primary, LayoutOrder = 3 }, frame)
		end
	end

	local function sound(tier)
		tone(THUD, 0.5, 0.55)
		tone(PING, 0.85, 0.4, 0.03)
		tone(PING, 1.15, 0.38, 0.1)
		if tier >= 2 then
			tone(PING, 1.5, 0.36, 0.17)
		end
		if tier >= 3 then
			tone(PING, 1.9, 0.34, 0.24)
		end
		if tier >= 4 then
			tone(PING, 2.5, 0.34, 0.31)
			tone(THUD, 0.38, 0.65, 0.31)
		end
	end

	local fade = fader(group)

	local function show(item)
		local list = item.List
		local main = list[1]
		local medal = Medals.Get(main.Id)
		local tier = medal.Tier
		local color = TIER_COLORS[tier] or WHITE
		fade.Cancel()

		-- Inhalt
		for _, child in iconHolder:GetChildren() do
			child:Destroy()
		end
		local draw = ICONS[medal.Icon]
		if draw then
			draw(iconHolder, color, main, medal)
		else
			diamond(iconHolder, 12, UDim2.fromScale(0.5, 0.5), color)
		end
		plateStroke.Color = color
		innerStroke.Color = color
		glow.BackgroundColor3 = color
		for _, wing in wings do
			wing.Frame.BackgroundColor3 = color
		end
		title.Text = upper(main.Title or medal.Title)
		title.TextSize = TIER_TEXT[tier] or 44
		local parts = {}
		local xp, coins = 0, 0
		for _, entry in list do
			xp += tonumber(entry.Xp) or 0
			coins += tonumber(entry.Coins) or 0
		end
		local gains = {}
		if xp > 0 then
			table.insert(gains, "+" .. xp .. " XP")
		end
		if coins > 0 then
			table.insert(gains, "+" .. coins .. " MÜNZEN")
		end
		if #gains > 0 then
			table.insert(parts, '<font color="#' .. C.Primary:ToHex() .. '">' .. table.concat(gains, "   ") .. "</font>")
		end
		if main.Sub and main.Sub ~= "" then
			table.insert(parts, upper(main.Sub))
		end
		sub.Text = table.concat(parts, "    ")
		sub.Visible = #parts > 0
		for _, child in chips:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i = 2, #list do
			chip(list[i], i)
		end

		-- Auftritt: Abzeichen schlägt ein, Blitz-Ring, Titel zieht zusammen, Linien laufen aus, Glanz
		group.Visible = true
		group.Position = UDim2.new(0.5, 0, 0.5, medalTop() - MEDAL_PAD)
		tween(group, 0.12, { GroupTransparency = 0 })
		emblemScale.Scale = 2.3
		tween(emblemScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		flashScale.Scale = 1
		flashStroke.Transparency = 0
		tween(flashScale, 0.5, { Scale = 2.4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.22)
		tween(flashStroke, 0.5, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.22)
		titleScale.Scale = 1.6
		tween(titleScale, 0.24, { Scale = 1 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0.05)
		shine(titleGradient, color, 0.75, 0.3)
		for _, wing in wings do
			wing.Frame.Size = UDim2.fromOffset(0, wing.Frame.Size.Y.Offset)
			tween(wing.Frame, 0.4, { Size = UDim2.fromOffset(wing.Length, wing.Frame.Size.Y.Offset) }, Enum.EasingStyle.Quart,
				Enum.EasingDirection.Out, 0.15)
		end
		sub.TextTransparency = 1
		tween(sub, 0.25, { TextTransparency = 0 }, nil, nil, 0.3)
		local hold = TIER_HOLD[tier] or 2
		for i, ray in rays do
			ray.Visible = tier >= 3
			ray.BackgroundColor3 = color
			ray.Rotation = (i - 1) * 30
			tween(ray, hold + 0.5, { Rotation = (i - 1) * 30 + 25 }, Enum.EasingStyle.Linear)
		end
		sound(tier)
		return hold
	end

	local function hide(instant)
		fade.Hide(instant, 0.35, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, medalTop() - MEDAL_PAD - 14) })
	end

	-- Mehrfach-Kills: nächste Stufe ersetzt die aktuelle sofort
	local function skip(current, nextItem)
		return current.Group ~= nil and current.Group == nextItem.Group
	end
	return makeQueue(show, hide, MEDAL_MIN, 4, skip)
end

-- Medaillen eines Ereignisses (Liste von { Id, Xp, Sub, Title, Count }, wichtigste zuerst)
function Notifications.Medal(list)
	if type(list) ~= "table" then
		return
	end
	local valid = {}
	for _, entry in list do
		if type(entry) == "table" and Medals.Get(entry.Id) then
			table.insert(valid, entry)
		end
	end
	if #valid == 0 or not layers.Medal then
		return
	end
	Medals.Sort(valid)
	layers.Medal.Push({ List = valid, Group = Medals.Get(valid[1].Id).Group })
end

-- ---------- Banner ----------

local function buildBanner(root)
	local group = make("CanvasGroup", { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, BANNER_Y, 0), Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, GroupTransparency = 1,
		Visible = false }, root)
	local back = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background, BackgroundTransparency = 0.18,
		BorderSizePixel = 0 }, group)
	edgeFade(back, 0.22)
	local tint = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Primary, BackgroundTransparency = 0.86,
		BorderSizePixel = 0 }, group)
	edgeFade(tint, 0.32)
	local lines = {}
	for _, top in { true, false } do
		local line = make("Frame", { AnchorPoint = Vector2.new(0.5, top and 0 or 1),
			Position = UDim2.fromScale(0.5, top and 0 or 1), Size = UDim2.new(0.8, 0, 0, 2), BackgroundColor3 = C.Primary,
			BorderSizePixel = 0 }, group)
		edgeFade(line, 0.3)
		table.insert(lines, line)
	end
	local ornament = diamond(group, 12, UDim2.fromScale(0.5, 0), C.Primary)

	local caption = label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 0, 0, 18), Text = "", TextSize = 14,
		TextColor3 = C.Muted }, group)
	local title = label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 0, 0, 68), Text = "", TextSize = 60,
		Font = F.Display, TextColor3 = WHITE }, group)
	make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 0.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, title)
	local titleGradient = make("UIGradient", {}, title)
	local titleScale = make("UIScale", {}, title)
	local sub = label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 0, 0, 20), Text = "", TextSize = 15,
		TextColor3 = C.Text }, group)

	local fade = fader(group)
	-- oben in der Mitte unter Zone, Spawnschutz und Ortsname einreihen (Höhe: Zielhöhe, das Band öffnet sich erst)
	local stackHeight = 0
	TopStack.Register(group, { Order = TopStack.Order.Banner, MinY = BANNER_Y, Height = function()
		return stackHeight
	end })

	local function show(data)
		local color = STYLES[data.Style] or C.Primary
		local big = data.Big == true
		local hasCaption = data.Caption ~= nil and data.Caption ~= ""
		local hasSub = data.Sub ~= nil and data.Sub ~= ""
		local titleText = upper(data.Title or "")
		-- lange Titel (z.B. Admin-Ankündigung): kleiner und bis zu drei Zeilen statt aus dem Bild zu laufen
		local length = utf8.len(titleText) or #titleText
		local titleSize = math.min(big and 76 or 56, math.max(28, math.floor(1800 / math.max(length, 1))))
		local titleRows = math.clamp(math.ceil(length * 0.6 * titleSize / 1100), 1, 3)
		local titleH = titleRows * (titleSize + 8)
		fade.Cancel()

		caption.Text = hasCaption and upper(data.Caption) or ""
		caption.Visible = hasCaption
		title.Text = titleText
		title.TextSize = titleSize
		title.TextWrapped = titleRows > 1
		title.Size = UDim2.new(0.8, 0, 0, titleH)
		sub.Text = hasSub and upper(data.Sub) or ""
		sub.Visible = hasSub
		-- von oben nach unten anordnen (Überschrift, Titel, Zeile darunter), alles um die Mitte des Bands
		local height = 12 + (hasCaption and 20 or 0) + titleH + (hasSub and 20 or 0) + 14
		stackHeight = height
		local y = -height / 2 + 12
		if hasCaption then
			caption.Position = UDim2.new(0.5, 0, 0.5, y + 9)
			y += 20
		end
		title.Position = UDim2.new(0.5, 0, 0.5, y + titleH / 2)
		y += titleH
		sub.Position = UDim2.new(0.5, 0, 0.5, y + 10)

		tint.BackgroundColor3 = color
		ornament.BackgroundColor3 = color
		for _, line in lines do
			line.BackgroundColor3 = color
			line.Size = UDim2.new(0, 0, 0, 2)
			tween(line, 0.5, { Size = UDim2.new(0.8, 0, 0, 2) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0.1)
		end
		local titleColor = (data.Style == "Info" or data.Style == "Neutral" or data.Style == nil) and C.Text
			or color:Lerp(WHITE, 0.2)

		-- Band öffnet sich von der Mitte, Titel zieht zusammen, Glanz läuft drüber
		group.Visible = true
		group.Size = UDim2.new(1, 0, 0, 0)
		tween(group, 0.15, { GroupTransparency = 0 })
		tween(group, 0.3, { Size = UDim2.new(1, 0, 0, height) }, Enum.EasingStyle.Quart)
		titleScale.Scale = 1.3
		tween(titleScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0.05)
		shine(titleGradient, titleColor, 0.9, 0.35)
		sub.TextTransparency = 1
		tween(sub, 0.3, { TextTransparency = 0 }, nil, nil, 0.35)
		caption.TextTransparency = 1
		tween(caption, 0.3, { TextTransparency = 0 }, nil, nil, 0.2)

		-- Klang: eigener Klang (data.Sound, SoundLibrary), Warnung/Erfolg der offenen Welt als Signalton, sonst tiefer
		-- Schlag; bei Sieg/Niederlage zwei Töne steigend bzw. fallend
		if type(data.Sound) == "string" or data.Style == "Warning" or data.Style == "Good" then
			Sfx.UI(type(data.Sound) == "string" and data.Sound or (data.Style == "Warning" and "StingWarning" or "StingGood"))
			return data.Hold or (big and BANNER_HOLD + 0.9 or BANNER_HOLD)
		end
		tone(THUD, 0.42, 0.7)
		if data.Style == "Win" then
			tone(PING, 1.0, 0.4, 0.08)
			tone(PING, 1.5, 0.4, 0.2)
		elseif data.Style == "Loss" then
			tone(PING, 0.9, 0.4, 0.08)
			tone(PING, 0.65, 0.4, 0.22)
		elseif data.Style == "Alert" then
			tone(PING, 1.6, 0.4, 0.06)
			tone(PING, 1.6, 0.4, 0.26)
		else
			tone(PING, 1.2, 0.35, 0.08)
		end
		return data.Hold or (big and BANNER_HOLD + 0.9 or BANNER_HOLD)
	end

	local function hide(instant)
		fade.Hide(instant, 0.3, { Size = UDim2.new(1, 0, 0, 0), GroupTransparency = 1 }, Enum.EasingStyle.Quad,
			Enum.EasingDirection.In)
	end
	return makeQueue(show, hide, BANNER_MIN, 4)
end

function Notifications.Banner(data)
	if type(data) == "table" and layers.Banner then
		layers.Banner.Push(data)
	end
end

-- ---------- Ziel-Meldungen ----------

local function buildObjective(root)
	local group = make("CanvasGroup", { Name = "Objective", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, OBJECTIVE_Y), Size = UDim2.fromOffset(680, 34), BackgroundTransparency = 1,
		GroupTransparency = 1, Visible = false }, root)
	local back = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background, BackgroundTransparency = 0.2,
		BorderSizePixel = 0 }, group)
	edgeFade(back, 0.2)
	local line = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.Ally, BorderSizePixel = 0 }, group)
	edgeFade(line, 0.25)
	local row = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, group)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local iconHolder = make("Frame", { Size = UDim2.fromOffset(26, 26), BackgroundTransparency = 1, LayoutOrder = 1 }, row)
	local icon = diamond(iconHolder, 18, UDim2.fromScale(0.5, 0.5), C.Ally)
	local letter = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 1),
		Size = UDim2.fromScale(1, 1), Text = "", TextSize = 16, Font = F.Display, TextColor3 = C.PrimaryText }, iconHolder)
	local dot = diamond(iconHolder, 7, UDim2.fromScale(0.5, 0.5), C.PrimaryText)
	local text = label({ Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 22,
		Font = F.Display, LayoutOrder = 2 }, row)

	local fade = fader(group)

	local function show(data)
		local color = SIDES[data.Side] or C.Text
		local hasIcon = type(data.Icon) == "string" and data.Icon ~= ""
		fade.Cancel()
		icon.BackgroundColor3 = color
		letter.Text = hasIcon and upper(data.Icon) or ""
		dot.Visible = not hasIcon
		line.BackgroundColor3 = color
		text.Text = upper(tostring(data.Text or ""))
		text.TextColor3 = color:Lerp(WHITE, 0.25)
		group.Visible = true
		group.Position = UDim2.new(0.5, 0, 0, OBJECTIVE_Y - 12)
		tween(group, 0.22, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, OBJECTIVE_Y) })
		tone(PING, data.Side == "Enemy" and 0.8 or 1.35, 0.35)
		if data.Side == "Alert" then
			tone(PING, 1.35, 0.3, 0.14)
		end
		return OBJECTIVE_HOLD
	end

	local function hide(instant)
		fade.Hide(instant, 0.3, { GroupTransparency = 1 })
	end
	return makeQueue(show, hide, OBJECTIVE_MIN, 3)
end

function Notifications.Objective(data)
	if type(data) == "table" and layers.Objective then
		layers.Objective.Push(data)
	end
end

-- ---------- Fortschritt ----------

local PROGRESS_W = 370
local PROGRESS_SUB_W = PROGRESS_W - 112

local function buildProgress(root)
	local group = make("CanvasGroup", { Name = "Progress", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -400, 0.5, -40), Size = UDim2.fromOffset(PROGRESS_W, 94), BackgroundTransparency = 1,
		GroupTransparency = 1, Visible = false }, root)
	local back = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.08,
		BorderSizePixel = 0 }, group)
	make("UIGradient", { Transparency = NumberSequence.new(0, 0.45) }, back)
	local accent = make("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = C.Primary, BorderSizePixel = 0 }, group)
	local badge, badgeStroke = diamond(group, 42, UDim2.new(0, 52, 0.5, 0), C.Background, C.Primary, 2)
	local badgeText = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 52, 0.5, 1),
		Size = UDim2.fromOffset(56, 30), Text = "", TextSize = 22, Font = F.Display, TextColor3 = C.Primary }, group)
	local caption = label({ Position = UDim2.fromOffset(98, 13), Size = UDim2.new(1, -112, 0, 14), Text = "", TextSize = 12,
		TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left }, group)
	local title = label({ Position = UDim2.fromOffset(98, 27), Size = UDim2.new(1, -112, 0, 38), Text = "", TextSize = 32,
		Font = F.Display, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd },
		group)
	local titleGradient = make("UIGradient", {}, title)
	local sub = label({ Position = UDim2.fromOffset(98, 66), Size = UDim2.new(1, -112, 0, 16), Text = "", TextSize = 13,
		TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd }, group)

	local fade = fader(group)
	local function colorOf(data)
		return typeof(data.Color) == "Color3" and data.Color or STYLES[data.Style] or C.Primary
	end

	-- Inhalt setzen (auch für eine schon sichtbare Karte, wenn eine Belohnung dazukommt); Zeile darunter
	-- darf zweizeilig werden, dann wird die Karte höher
	local function apply(data)
		local color = colorOf(data)
		accent.BackgroundColor3 = color
		badgeStroke.Color = color
		badge.BackgroundColor3 = C.Background
		badgeText.TextColor3 = color
		local mark = data.Badge ~= nil and tostring(data.Badge) or ""
		badgeText.Font = mark == "" and F.Bold or F.Display -- ohne Zahl ein Stern (kennt nur Gotham)
		badgeText.Text = mark == "" and "★" or upper(mark)
		caption.Text = upper(tostring(data.Caption or ""))
		title.Text = upper(tostring(data.Title or ""))
		sub.Text = upper(tostring(data.Sub or ""))
		local lines = TextService:GetTextSize(sub.Text, 13, F.Bold, Vector2.new(PROGRESS_SUB_W, 1000)).Y > 20 and 2 or 1
		sub.Size = UDim2.new(1, -112, 0, lines * 16)
		group.Size = UDim2.fromOffset(PROGRESS_W, lines == 2 and 110 or 94)
		return color
	end

	local function show(data)
		fade.Cancel()
		local color = apply(data)
		group.Visible = true
		group.Position = UDim2.new(0, -400, 0.5, -40)
		tween(group, 0.2, { GroupTransparency = 0 })
		tween(group, 0.4, { Position = UDim2.new(0, 24, 0.5, -40) }, Enum.EasingStyle.Quart)
		shine(titleGradient, color:Lerp(WHITE, 0.15), 0.8, 0.35)
		tone(PING, 1.0, 0.4)
		tone(PING, 1.25, 0.4, 0.1)
		tone(PING, 1.5, 0.4, 0.2)
		return PROGRESS_HOLD
	end

	local function hide(instant)
		fade.Hide(instant, 0.3, { Position = UDim2.new(0, -400, 0.5, -40), GroupTransparency = 1 }, Enum.EasingStyle.Quad,
			Enum.EasingDirection.In)
	end
	local queue = makeQueue(show, hide, PROGRESS_MIN, 4)
	-- Sichtbare Karte nach dem Zusammenführen neu beschriften (ohne neuen Auftritt), kurzer Glanz als Hinweis
	function queue.Refresh(data)
		local color = apply(data)
		shine(titleGradient, color:Lerp(WHITE, 0.15), 0.6, 0)
		tone(PING, 1.5, 0.35)
	end
	return queue
end

-- Zwei Karten mit gleichem Key zu einer: die Primary-Karte (z.B. LEVEL 20) behält Überschrift, Titel und Farbe,
-- die Zeilen darunter werden aneinandergehängt (z.B. "+440 MÜNZEN")
local function mergeProgress(existing, incoming)
	local primary, secondary = existing, incoming
	if incoming.Primary and not existing.Primary then
		primary, secondary = incoming, existing
	end
	local subs = {}
	for _, text in { primary.Sub, secondary.Sub } do
		if text ~= nil and tostring(text) ~= "" then
			table.insert(subs, tostring(text))
		end
	end
	existing.Caption, existing.Title, existing.Badge = primary.Caption, primary.Title, primary.Badge
	existing.Color, existing.Style, existing.Primary = primary.Color, primary.Style, primary.Primary
	existing.Sub = table.concat(subs, "  ·  ")
end

function Notifications.Progress(data)
	if type(data) ~= "table" or not layers.Progress then
		return
	end
	if data.Key ~= nil then
		local existing, showing = layers.Progress.Find(function(item)
			return item.Key == data.Key
		end)
		if existing then
			mergeProgress(existing, data)
			if showing then
				layers.Progress.Refresh(existing)
			end
			return
		end
	end
	layers.Progress.Push(data)
end

-- Belohnung vom RewardService ({ Title, Lines, Rarity, Key }) als Karte im selben Stil wie Level und Battle Pass:
-- Zahl aus dem Titel ins Abzeichen (LEVEL 20, PRESTIGE 3), Farbe nach Seltenheit des Skins, sonst Gold
function Notifications.Reward(data)
	if type(data) ~= "table" then
		return
	end
	local lines = {}
	for _, line in (type(data.Lines) == "table" and data.Lines or {}) do
		table.insert(lines, tostring(line))
	end
	local rarity = data.Rarity and Cosmetics.Rarities[data.Rarity]
	local title = tostring(data.Title or "")
	Notifications.Progress({ Caption = "Belohnung", Title = title, Sub = table.concat(lines, "  ·  "),
		Badge = string.match(title, "%d+"), Color = rarity and rarity.Color or C.Gold, Key = data.Key })
end

-- ---------- Start ----------

function Notifications.Init()
	local screen = make("ScreenGui", { Name = "Notifications", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 11 },
		player:WaitForChild("PlayerGui"))
	local root = UITheme.ScaledRoot(screen)
	layers.Medal = buildMedal(root)
	layers.Banner = buildBanner(root)
	layers.Objective = buildObjective(root)
	-- Karten (Level, Battle Pass, Belohnungen) über Menüs und Match-Zusammenfassung
	local cards = make("ScreenGui", { Name = "NotificationCards", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 25 }, player:WaitForChild("PlayerGui"))
	layers.Progress = buildProgress(UITheme.ScaledRoot(cards))

	Remotes.Notify.OnClientEvent:Connect(function(kind, data)
		if kind == "Medal" then
			Notifications.Medal(data)
		elseif kind == "Banner" then
			Notifications.Banner(data)
		elseif kind == "Objective" then
			Notifications.Objective(data)
		elseif kind == "Progress" then
			Notifications.Progress(data)
		end
	end)
	Remotes.Announce.OnClientEvent:Connect(function(text)
		Notifications.Banner({ Title = tostring(text), Style = "Neutral" })
	end)
	Remotes.Reward.OnClientEvent:Connect(Notifications.Reward)

	-- Moduswechsel (z.B. Match verlassen): Match-Meldungen sofort weg, Fortschritt darf bleiben
	player:GetAttributeChangedSignal("Mode"):Connect(function()
		layers.Medal.Clear()
		layers.Banner.Clear()
		layers.Objective.Clear()
	end)

	-- Agenten-Level gestiegen (kommt mit den XP vom Server). Ohne Arcade gibt es nur noch das Spielerlevel: dann keine
	-- eigene Level-Karte, nur wenn dabei ein Waffen-Skin (Gold, Diamant) frei wird
	Remotes.XPGain.OnClientEvent:Connect(function(_, _, agentId, levelUp)
		local agent = AgentConfig.Get(agentId)
		if not levelUp or not agent then
			return
		end
		local level = AgentConfig.LevelFromXP(AgentConfig.GetXP(player, agentId))
		local skin = AgentConfig.SkinForLevel(level)
		local unlocked = skin and skin.Level == level
		if Modes.ArcadeEnabled then
			Notifications.Progress({ Caption = agent.Name .. " aufgestiegen", Title = "Level " .. level, Badge = tostring(level),
				Sub = unlocked and (skin.Name .. "-Skin freigeschaltet") or "Agenten-Level", Color = agent.Color })
		elseif unlocked then
			Notifications.Progress({ Caption = "Waffen-Skin freigeschaltet", Title = skin.Name,
				Sub = "Für alle Waffen ohne ausgerüsteten Skin", Color = skin.Color })
		end
	end)

	-- Spielerlevel gestiegen (Prestige setzt das Level zurück, das zählt nicht)
	local info = LevelConfig.Get(player)
	local lastLevel, lastPrestige = info.Level, info.Prestige
	player:GetAttributeChangedSignal("AccountXP"):Connect(function()
		local now = LevelConfig.Get(player)
		if now.Level > lastLevel and now.Prestige == lastPrestige then
			-- Key passt zur Belohnung "LEVEL n ERREICHT" vom RewardService: deren Münzen landen in dieser Karte
			Notifications.Progress({ Caption = "Level aufgestiegen", Title = "Level " .. now.Level, Badge = tostring(now.Level),
				Sub = now.CanPrestige and "Prestige jetzt möglich" or nil, Style = "Level", Key = "Level" .. now.Level,
				Primary = true })
		end
		lastLevel, lastPrestige = now.Level, now.Prestige
	end)
end

return Notifications

-- MatchSummary (ModuleScript, nur Client)
-- Match-Ende-Bildschirm im Stil von Rogue Company: breites Band mit SIEG/NIEDERLAGE (FFA: Platz), Endstand,
-- Modus und Map, MVP-Karte, eigene Werte als Kacheln und darunter die Belohnungs-Übersicht:
--   BELOHNUNGEN: XP und Münzen nach Grund (Kills, Matchsieg, Killserien, Rache, ...) und neue Skins
--   SPIELERLEVEL: Prestige-Abzeichen, XP-Balken läuft hoch, LEVEL UP!
--   RANG: Rang-Abzeichen, ELO zählt hoch/runter, Balken bis zur nächsten Stufe, AUFSTIEG!/NEUER RANG!/ABSTIEG
-- Vorher steht die TOP 3 des Matches als 3D-Figuren auf einem Podest (data.Top, PODIUM_TIME Sekunden).
-- Die Übersicht kommt vom Server (data.Progress, ProgressService.TakeLedger).
-- Verschwindet nach data.ShowTime Sekunden von selbst bzw. sobald Map-Abstimmung/Agentenwahl beginnt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)
local RankConfig = require(Shared.RankConfig)
local LevelConfig = require(Shared.LevelConfig)
local PrestigeEmblem = require(Shared.PrestigeEmblem)
local RankEmblem = require(Shared.RankEmblem)
local Cosmetics = require(Shared.Cosmetics)
local AgentConfig = require(Shared.AgentConfig)
local AgentFigure = require(Shared.AgentFigure)
local TitleConfig = require(Shared.TitleConfig)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make = UITheme.Make
local label = UITheme.Label

local MatchSummary = {}

local SHOW_TIME = 10 -- falls der Server keine Zeit mitschickt (TeamRoundMode: SUMMARY_TIME)
local PODIUM_TIME = 3.6 -- so lange steht die Top-3-Bühne, danach kommt die Übersicht
local MAX_LINES = 7  -- so viele Zeilen passen in die Belohnungs-Karte
local ROW_Y = 492    -- obere Kante der drei Karten unten
local ROW_H = 300

local function formatNumber(n)
	return UITheme.FormatNumber(math.floor(n + 0.5))
end

local function signed(n)
	if n == 0 then
		return "±0"
	end
	return (n > 0 and "+" or "−") .. formatNumber(math.abs(n))
end

-- Karte unten mit grauer Überschrift
local function card(title, x, width, parent)
	local frame = UITheme.Card({ Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, width, 1, 0),
		BackgroundTransparency = 0.06 }, parent)
	label({ Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 22), Text = title, Font = F.Display,
		TextSize = 18, TextColor3 = C.Muted }, frame)
	return frame
end

-- Fortschrittsbalken: gibt Spur und Füllung zurück
local function bar(parent, y, color)
	local track = make("Frame", { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 10),
		BackgroundColor3 = C.CardHover, BorderSizePixel = 0 }, parent)
	UITheme.Corner(track, 5)
	local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color or C.Primary, BorderSizePixel = 0 }, track)
	UITheme.Corner(fill, 5)
	return track, fill
end

-- Großer Hinweis (LEVEL UP!, AUFSTIEG!), springt herein
local function popLabel(parent)
	local text = label({ Position = UDim2.fromOffset(20, 146), Size = UDim2.new(1, -40, 0, 44), Font = F.Display,
		TextSize = 34, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Visible = false }, parent)
	make("UITextSizeConstraint", { MaxTextSize = 34 }, text) -- lange Texte (NEUER RANG: DIAMANT!) werden kleiner
	make("UIScale", {}, text)
	return text
end

local function pop(text, value, color)
	text.Text = value
	text.TextColor3 = color
	text.Visible = true
	local scale = text:FindFirstChildOfClass("UIScale")
	scale.Scale = 1.8
	text.TextTransparency = 1
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(text, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
end

-- Läuft über duration Sekunden, step(alpha) bekommt 0..1 (auslaufend). Bricht ab, wenn alive() false wird.
local function animate(duration, alive, step)
	local start = os.clock()
	while true do
		if not alive() then
			return false
		end
		local alpha = math.min((os.clock() - start) / duration, 1)
		step(1 - (1 - alpha) ^ 3)
		if alpha >= 1 then
			return true
		end
		RunService.Heartbeat:Wait()
	end
end

-- Nächste Rang-Stufe über elo: Anzeige-Name und wie viel ELO noch fehlen (nil auf dem höchsten Rang)
local function nextStage(elo)
	local current = RankConfig.Get(elo).Display
	for step = 1, 600 do
		local rank = RankConfig.Get(elo + step)
		if rank.Display ~= current then
			return rank.Display, step
		end
	end
	return nil
end

-- ---------- Top-3-Bühne ----------
-- 3D-Szene (ViewportFrame, fest 1600x900 auf der Leinwand): drei Podeste, Platz 1 in der Mitte und am höchsten,
-- Platz 2 links, Platz 3 rechts. Achtung: die Kamera schaut nach +Z, Welt-+X liegt also im Bild LINKS.
local PLACES = {
	{ X = 0, Height = 1.8, Yaw = 0, Color = Color3.fromRGB(240, 195, 60) },
	{ X = 4.6, Height = 1.2, Yaw = 0.22, Color = Color3.fromRGB(200, 205, 215) },
	{ X = -4.6, Height = 0.8, Yaw = -0.22, Color = Color3.fromRGB(190, 120, 70) },
}
local CAMERA_FROM = CFrame.lookAt(Vector3.new(0, 5.2, -22), Vector3.new(0, 3.4, 0))
local CAMERA_TO = CFrame.lookAt(Vector3.new(0, 4.4, -17), Vector3.new(0, 3.4, 0))
local PODIUM_FOV = 40

local function buildPodium(parent)
	local holder = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 10, 14),
		BorderSizePixel = 0, Visible = false, ZIndex = 5 }, parent)
	local stage = UITheme.Canvas(holder, 1600, 900)
	local viewport = make("ViewportFrame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 12, 17),
		BorderSizePixel = 0, Ambient = Color3.fromRGB(120, 125, 140), LightColor = Color3.fromRGB(255, 245, 225),
		LightDirection = Vector3.new(-0.3, -1, 0.6) }, stage)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 46, 58), Color3.fromRGB(255, 255, 255)) },
		viewport)
	local camera = Instance.new("Camera")
	camera.FieldOfView = PODIUM_FOV
	camera.CFrame = CAMERA_TO
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- Boden und Podeste (bleiben stehen), Figuren kommen pro Match neu
	local scenery = Instance.new("Model")
	local function block(size, cframe, color, material)
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = size
		part.CFrame = cframe
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Parent = scenery
		return part
	end
	block(Vector3.new(60, 1, 40), CFrame.new(0, -0.5, 8), Color3.fromRGB(22, 25, 31))
	for _, place in PLACES do
		block(Vector3.new(3.8, place.Height, 3.4), CFrame.new(place.X, place.Height / 2, 0), Color3.fromRGB(34, 38, 46))
		block(Vector3.new(3.9, 0.12, 3.5), CFrame.new(place.X, place.Height + 0.06, 0), place.Color, Enum.Material.Neon)
	end
	-- Lichtleiste hinten
	block(Vector3.new(30, 0.25, 0.25), CFrame.new(0, 7.5, 6), Color3.fromRGB(212, 170, 80), Enum.Material.Neon)
	scenery.Parent = viewport
	local figures = Instance.new("Model")
	figures.Parent = viewport

	local heading = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(800, 56), Size = UDim2.fromOffset(900, 70),
		Text = "TOP 3 DES MATCHES", Font = F.Title, TextSize = 64, TextXAlignment = Enum.TextXAlignment.Center }, stage)
	local labels = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, stage)

	-- Welt-Punkt -> Pixel auf der 1600x900-Bühne (mit der End-Kamera)
	local function project(point)
		local rel = CAMERA_TO:PointToObjectSpace(point)
		local depth = -rel.Z
		local halfH = depth * math.tan(math.rad(PODIUM_FOV / 2))
		local halfW = halfH * 16 / 9
		return UDim2.fromOffset((0.5 + rel.X / (2 * halfW)) * 1600, (0.5 - rel.Y / (2 * halfH)) * 900)
	end

	local podium = { Frame = holder }

	-- top = { { Name, UserId, Agent, Kills, Team, Bot } } (bis zu 3); alive() = Anzeige noch aktuell?
	function podium.Show(top, alive)
		figures:ClearAllChildren()
		labels:ClearAllChildren()
		local texts = {}
		for i, entry in top do
			local place = PLACES[i]
			local agent = AgentConfig.Get(entry.Agent) or AgentConfig.Agents[1]
			local owner = entry.UserId and Players:GetPlayerByUserId(entry.UserId) or nil
			local primary, accent = Cosmetics.AgentColors(owner, agent.Id)
			local weapon = agent.Loadout[1]
			local skin = owner and Cosmetics.WeaponSkin(owner, agent.Id, weapon) or nil
			local ok, figure = pcall(AgentFigure.Build, agent, primary, accent, skin, weapon)
			if ok and figure then
				figure:PivotTo(CFrame.new(place.X, place.Height, 0) * CFrame.Angles(0, place.Yaw, 0) * figure:GetPivot())
				figure.Parent = figures
			end
			-- Name und Kills über dem Kopf, Platz-Zahl vorne auf dem Podest
			local mine = entry.UserId == player.UserId
			local nameColor = mine and C.Accent or C.Text
			if entry.Team and player.Team and not mine then
				nameColor = entry.Team == player.Team.Name and C.Ally or C.Enemy
			end
			local nameLabel = label({ AnchorPoint = Vector2.new(0.5, 1), Position = project(Vector3.new(place.X, place.Height + 6.6, 0)),
				Size = UDim2.fromOffset(320, 40), Text = UITheme.Upper(tostring(entry.Name)), Font = F.Title, TextSize = i == 1 and 36 or 30,
				TextColor3 = nameColor, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5 }, labels)
			local title = TitleConfig.Get(entry.Title or "")
			local titleText = (title and title.Id ~= TitleConfig.Default)
				and ('  ·  <font color="#' .. title.Color:ToHex() .. '">' .. UITheme.Upper(title.Name) .. "</font>") or ""
			local killLabel = label({ AnchorPoint = Vector2.new(0.5, 0), Position = project(Vector3.new(place.X, place.Height + 6.6, 0))
				+ UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(420, 24), Text = (entry.Kills or 0) .. " KILLS"
				.. (entry.Bot and "  ·  BOT" or titleText), Font = F.Bold, TextSize = 18, TextColor3 = C.Muted, RichText = true,
				TextXAlignment = Enum.TextXAlignment.Center }, labels)
			local number = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = project(Vector3.new(place.X, place.Height * 0.5, -1.75)),
				Size = UDim2.fromOffset(120, 80), Text = tostring(i), Font = F.Title, TextSize = i == 1 and 64 or 52,
				TextColor3 = place.Color, TextXAlignment = Enum.TextXAlignment.Center }, labels)
			texts[i] = { nameLabel, killLabel, number }
			for _, text in texts[i] do
				text.TextTransparency = 1
				text.TextStrokeTransparency = 1
			end
		end

		holder.Visible = true
		heading.TextTransparency = 1
		TweenService:Create(heading, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
		-- Kamera fährt heran, dann Plätze 3, 2, 1 nacheinander einblenden
		task.spawn(function()
			animate(0.9, alive, function(alpha)
				camera.CFrame = CAMERA_FROM:Lerp(CAMERA_TO, alpha)
			end)
			for i = #texts, 1, -1 do
				if not alive() then
					return
				end
				for _, text in texts[i] do
					TweenService:Create(text, TweenInfo.new(0.3), { TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
				end
				task.wait(0.35)
			end
		end)
	end

	function podium.Hide()
		holder.Visible = false
	end

	return podium
end

function MatchSummary.Init()
	local gui = make("ScreenGui", { Name = "MatchSummary", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 12,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, player:WaitForChild("PlayerGui"))
	local background = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.2, BorderSizePixel = 0 }, gui)
	local canvas = UITheme.Canvas(background, 1600, 900)

	-- Band quer über den Bildschirm
	local band = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = C.Panel, BorderSizePixel = 0 }, canvas)
	local bandGradient = make("UIGradient", { Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.1), NumberSequenceKeypoint.new(0.8, 0.1),
		NumberSequenceKeypoint.new(1, 1) }) }, band)
	local lineTop = make("Frame", { Size = UDim2.new(1, 0, 0, 3), BorderSizePixel = 0 }, band)
	local lineBottom = make("Frame", { Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3), BorderSizePixel = 0 }, band)
	bandGradient:Clone().Parent = lineTop
	bandGradient:Clone().Parent = lineBottom
	local diamond = UITheme.Diamond(band, 26, UDim2.new(0.5, 0, 0, 0), C.Panel, C.Accent)

	local title = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(1, 0, 0, 96), Font = F.Title, TextSize = 92, TextXAlignment = Enum.TextXAlignment.Center }, band)
	local titleScale = make("UIScale", {}, title)
	local sub = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.new(1, 0, 0, 28), Font = F.Title, TextSize = 22, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center }, band)

	-- Endstand (FFA: Platz)
	local score = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 226),
		Size = UDim2.new(0, 700, 0, 66), Font = F.Title, TextSize = 58, RichText = true,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)

	-- MVP-Karte
	local mvpCard = UITheme.Panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 302),
		Size = UDim2.new(0, 520, 0, 64), BackgroundColor3 = C.Card }, canvas)
	make("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = C.Gold, BorderSizePixel = 0 }, mvpCard)
	label({ Position = UDim2.new(0, 24, 0, 6), Size = UDim2.new(1, -48, 0, 18), Text = "MVP DES MATCHES",
		Font = F.Title, TextSize = 16, TextColor3 = C.Gold }, mvpCard)
	local mvpName = label({ Position = UDim2.new(0, 24, 0, 24), Size = UDim2.new(1, -150, 0, 36),
		Font = F.Title, TextSize = 28 }, mvpCard)
	local mvpKills = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 24),
		Size = UDim2.new(0, 140, 0, 36), Font = F.Title, TextSize = 24, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right }, mvpCard)

	-- Eigene Werte
	local tilesFrame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 382),
		Size = UDim2.new(0, 760, 0, 92), BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, tilesFrame)
	local tiles = {}
	for i, key in { "KILLS", "TODE", "K/D", "SCHADEN" } do
		local tile = UITheme.Panel({ Size = UDim2.new(0, 181, 1, 0), BackgroundColor3 = C.Card, LayoutOrder = i }, tilesFrame)
		make("Frame", { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = i == 3 and C.Accent or C.Border,
			BorderSizePixel = 0 }, tile)
		label({ Position = UDim2.new(0, 0, 0, 10), Size = UDim2.new(1, 0, 0, 20), Text = key,
			Font = F.Title, TextSize = 16, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }, tile)
		tiles[key] = label({ Position = UDim2.new(0, 0, 0, 32), Size = UDim2.new(1, 0, 0, 52),
			Font = F.Title, TextSize = 46, TextXAlignment = Enum.TextXAlignment.Center }, tile)
	end

	-- ---------- Belohnungs-Übersicht: drei Karten ----------
	local row = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, ROW_Y),
		Size = UDim2.new(0, 1192, 0, ROW_H), BackgroundTransparency = 1 }, canvas)

	-- BELOHNUNGEN: Summen oben, darunter die Gründe
	local rewards = card("BELOHNUNGEN", 0, 480, row)
	local xpTotal = label({ Position = UDim2.fromOffset(20, 38), Size = UDim2.fromOffset(220, 42), Font = F.Display,
		TextSize = 36, TextColor3 = C.Accent }, rewards)
	local coinRow = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 38),
		Size = UDim2.fromOffset(220, 42), BackgroundTransparency = 1 }, rewards)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder }, coinRow)
	UITheme.Coin(coinRow, 22, { LayoutOrder = 1 })
	local coinTotal = label({ Size = UDim2.fromOffset(0, 42), AutomaticSize = Enum.AutomaticSize.X, Font = F.Display,
		TextSize = 36, TextColor3 = C.Gold, LayoutOrder = 2 }, coinRow)
	make("Frame", { Position = UDim2.fromOffset(20, 86), Size = UDim2.new(1, -40, 0, 1), BackgroundColor3 = C.Border,
		BorderSizePixel = 0 }, rewards)
	local list = make("Frame", { Position = UDim2.fromOffset(20, 94), Size = UDim2.new(1, -40, 0, MAX_LINES * 24),
		BackgroundTransparency = 1 }, rewards)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rewardNote = label({ Position = UDim2.new(0, 20, 1, -32), Size = UDim2.new(1, -40, 0, 20), Font = F.Bold,
		TextSize = 14, TextColor3 = C.Primary }, rewards)

	-- SPIELERLEVEL: Abzeichen, Level, Balken
	local levelCard = card("SPIELERLEVEL", 496, 340, row)
	local emblem = PrestigeEmblem.new(levelCard, 92)
	emblem.Root.Position = UDim2.fromOffset(16, 40)
	local levelText = label({ Position = UDim2.fromOffset(120, 48), Size = UDim2.new(1, -140, 0, 46), Font = F.Display,
		TextSize = 42 }, levelCard)
	local prestigeText = label({ Position = UDim2.fromOffset(120, 94), Size = UDim2.new(1, -140, 0, 22), Font = F.Display,
		TextSize = 18, TextColor3 = C.Muted }, levelCard)
	local levelPop = popLabel(levelCard)
	local _, levelFill = bar(levelCard, 214, C.Primary)
	local levelInfo = label({ Position = UDim2.fromOffset(20, 232), Size = UDim2.new(1, -40, 0, 20), Font = F.Bold,
		TextSize = 14, TextColor3 = C.Muted }, levelCard)

	-- RANG: Name in Rangfarbe, ELO, Änderung, Balken
	local rankCard = card("RANG", 852, 340, row)
	local rankStroke = rankCard:FindFirstChildOfClass("UIStroke")
	local rankEmblem = RankEmblem.new(rankCard, 92)
	rankEmblem.Root.Position = UDim2.fromOffset(12, 38)
	local rankName = label({ Position = UDim2.fromOffset(112, 44), Size = UDim2.new(1, -130, 0, 46), Font = F.Display,
		TextSize = 38 }, rankCard)
	local eloText = label({ Position = UDim2.fromOffset(112, 92), Size = UDim2.new(1, -200, 0, 30), Font = F.Display,
		TextSize = 22 }, rankCard)
	local eloChange = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 90),
		Size = UDim2.new(0.4, 0, 0, 30), Font = F.Display, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Right }, rankCard)
	local rankPop = popLabel(rankCard)
	local _, rankFill = bar(rankCard, 214)
	local rankInfo = label({ Position = UDim2.fromOffset(20, 232), Size = UDim2.new(1, -40, 0, 20), Font = F.Bold,
		TextSize = 14, TextColor3 = C.Muted }, rankCard)

	local footer = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, ROW_Y + ROW_H + 22),
		Size = UDim2.new(0, 600, 0, 24), Font = F.Title, TextSize = 18, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)

	-- Eine Zeile in BELOHNUNGEN (Name links, XP und Münzen rechts)
	local function addLine(order, name, xp, coins, color)
		local line = make("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = order }, list)
		local texts = {}
		table.insert(texts, label({ Size = UDim2.new(1, -170, 1, 0), Text = name, Font = F.Bold, TextSize = 15,
			TextColor3 = color or C.Text, TextTruncate = Enum.TextTruncate.AtEnd }, line))
		if xp and xp > 0 then
			table.insert(texts, label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 0),
				Size = UDim2.fromOffset(84, 24), Text = "+" .. formatNumber(xp) .. " XP", Font = F.Bold, TextSize = 15,
				TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Right }, line))
		end
		if coins and coins > 0 then
			table.insert(texts, label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 0),
				Size = UDim2.fromOffset(64, 24), Text = "+" .. formatNumber(coins), Font = F.Bold, TextSize = 15,
				TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Right }, line))
			UITheme.Coin(line, 12, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0) })
		end
		for _, text in texts do
			text.TextTransparency = 1
		end
		return texts
	end

	local function setLevel(level, prestige)
		emblem:Set(level, prestige)
		levelText.Text = "LEVEL " .. level
	end

	local podium = buildPodium(gui)

	local showId = 0
	-- Nie über der Map-Abstimmung oder Agentenwahl liegen: sobald die beginnt, ausblenden
	player:GetAttributeChangedSignal("RoundPhase"):Connect(function()
		local phase = player:GetAttribute("RoundPhase")
		if phase == "MapVote" or phase == "Select" or phase == "Countdown" then
			showId += 1
			gui.Enabled = false
		end
	end)

	-- Belohnungs-Übersicht füllen und animieren (läuft in eigenem Thread)
	local function showProgress(progress, alive)
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		levelPop.Visible = false
		rankPop.Visible = false
		rankStroke.Color = C.Border
		rankStroke.Transparency = 0.25

		-- BELOHNUNGEN
		xpTotal.Text = "+0 XP"
		coinTotal.Text = "+0"
		local fades = {}
		local order = 0
		for _, item in progress.Items or {} do
			order += 1
			local rarity = Cosmetics.Rarities[item.Rarity]
			table.insert(fades, addLine(order, "NEUER SKIN · " .. UITheme.Upper(item.Name), nil, nil,
				rarity and rarity.Color or C.Primary))
		end
		local lines = progress.Lines or {}
		local room = MAX_LINES - order
		for i, line in lines do
			if i == room and #lines > room then
				-- Rest zusammenfassen
				local xp, coins = 0, 0
				for j = i, #lines do
					xp += lines[j].XP
					coins += lines[j].Coins
				end
				order += 1
				table.insert(fades, addLine(order, "WEITERE", xp, coins, C.Muted))
				break
			elseif i > room then
				break
			end
			order += 1
			local name = UITheme.Upper(line.Name) .. (line.Count > 1 and ("  ×" .. line.Count) or "")
			table.insert(fades, addLine(order, name, line.XP, line.Coins))
		end
		if order == 0 then
			order += 1
			table.insert(fades, addLine(order, "KEINE BELOHNUNGEN IN DIESEM MATCH", nil, nil, C.Muted))
		end
		local notes = {}
		if progress.AgentOfWeek then
			table.insert(notes, "+50 % XP · AGENT DER WOCHE")
		end
		if progress.DoubleXP then
			table.insert(notes, "DOPPEL-XP")
		end
		rewardNote.Text = #notes > 0 and ("INKL. " .. table.concat(notes, "  ·  ")) or ""

		-- SPIELERLEVEL: Startzustand
		local lv = progress.Level or {}
		local prestige = lv.Prestige or (player:GetAttribute("Prestige") or 0)
		local levelBefore, levelAfter = lv.Before or 1, lv.After or 1
		if (lv.PrestigeBefore or prestige) ~= prestige or levelAfter < levelBefore then
			levelBefore = levelAfter -- Prestige/Admin während des Matches: keinen Verlauf zeigen
			lv.BeforeProgress = lv.AfterProgress
		end
		setLevel(levelBefore, prestige)
		local color = LevelConfig.PrestigeColors[math.min(prestige, LevelConfig.MaxPrestige)]
		prestigeText.Text = prestige > 0 and ("PRESTIGE " .. prestige) or ""
		prestigeText.TextColor3 = color
		levelFill.BackgroundColor3 = C.Primary
		levelFill.Size = UDim2.fromScale(lv.BeforeProgress or 0, 1)
		levelInfo.Text = levelAfter >= LevelConfig.MaxLevel and "MAX-LEVEL · PRESTIGE IM MENÜ"
			or ("NOCH " .. formatNumber(lv.XPLeft or 0) .. " XP BIS LEVEL " .. (levelAfter + 1))

		-- RANG: Startzustand
		local elo = progress.Elo or {}
		local eloBefore, eloAfter = elo.Before or RankConfig.StartElo, elo.After or RankConfig.StartElo
		local rankBefore, rankAfter = RankConfig.Get(eloBefore), RankConfig.Get(eloAfter)
		rankName.Text = rankBefore.Display
		rankName.TextColor3 = rankBefore.Color
		rankEmblem:SetRank(rankBefore)
		rankFill.BackgroundColor3 = rankBefore.Color
		rankFill.Size = UDim2.fromScale(rankBefore.Progress, 1)
		eloText.Text = formatNumber(eloBefore) .. " ELO"
		local change = eloAfter - eloBefore
		eloChange.Text = signed(change)
		eloChange.TextColor3 = change > 0 and C.Good or (change < 0 and C.Bad or C.Muted)
		eloChange.TextTransparency = 1
		if (elo.Matches or 0) <= RankConfig.PlacementMatches and change ~= 0 then
			rankInfo.Text = "PLATZIERUNG " .. (elo.Matches or 0) .. "/" .. RankConfig.PlacementMatches
		else
			local nextName, missing = nextStage(eloAfter)
			rankInfo.Text = nextName and ("NÄCHSTE STUFE: " .. nextName .. "  (+" .. missing .. ")") or "HÖCHSTER RANG"
		end

		task.wait(0.5)
		if not alive() then
			return
		end

		-- Zeilen nacheinander einblenden, Summen zählen hoch
		task.spawn(function()
			for _, texts in fades do
				if not alive() then
					return
				end
				for _, text in texts do
					TweenService:Create(text, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
				end
				task.wait(0.07)
			end
		end)
		task.spawn(animate, 1.2, alive, function(alpha)
			xpTotal.Text = "+" .. formatNumber((progress.XP or 0) * alpha) .. " XP"
			coinTotal.Text = "+" .. formatNumber((progress.Coins or 0) * alpha)
		end)

		-- Level: Balken füllt sich, bei Level-Up einmal (bis dreimal) voll laufen lassen
		task.spawn(function()
			local levels = levelAfter - levelBefore
			if levels > 0 then
				local from = lv.BeforeProgress or 0
				for i = 1, math.min(levels, 3) do
					if not animate(0.45, alive, function(alpha)
						levelFill.Size = UDim2.fromScale(from + (1 - from) * alpha, 1)
					end) then
						return
					end
					setLevel(i == math.min(levels, 3) and levelAfter or levelBefore + i, prestige)
					from = 0
					levelFill.Size = UDim2.fromScale(0, 1)
				end
				pop(levelPop, levels > 1 and ("LEVEL UP! ×" .. levels) or "LEVEL UP!", C.Primary)
				animate(0.5, alive, function(alpha)
					levelFill.Size = UDim2.fromScale((lv.AfterProgress or 0) * alpha, 1)
				end)
			else
				local from, to = lv.BeforeProgress or 0, lv.AfterProgress or 0
				animate(0.9, alive, function(alpha)
					levelFill.Size = UDim2.fromScale(from + (to - from) * alpha, 1)
				end)
			end
		end)

		-- Rang: ELO zählt, Name und Balken wechseln beim Überschreiten einer Stufe mit
		TweenService:Create(eloChange, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		local done = animate(1.4, alive, function(alpha)
			local value = eloBefore + change * alpha
			local rank = RankConfig.Get(value)
			eloText.Text = formatNumber(value) .. " ELO"
			if rank.Display ~= rankName.Text then
				rankEmblem:SetRank(rank)
			end
			rankName.Text = rank.Display
			rankName.TextColor3 = rank.Color
			rankFill.BackgroundColor3 = rank.Color
			rankFill.Size = UDim2.fromScale(rank.Progress, 1)
		end)
		if not done or rankAfter.Display == rankBefore.Display then
			return
		end
		if change > 0 then
			pop(rankPop, rankAfter.Name ~= rankBefore.Name and ("NEUER RANG: " .. string.upper(rankAfter.Name) .. "!")
				or "AUFSTIEG!", rankAfter.Color)
			rankStroke.Color = rankAfter.Color
			rankStroke.Transparency = 0
		else
			pop(rankPop, "ABSTIEG", C.Bad)
		end
	end

	Remotes.MatchSummary.OnClientEvent:Connect(function(data)
		showId += 1
		local myId = showId
		local function isCurrent()
			return showId == myId
		end

		-- Titel: Team-Modi SIEG/NIEDERLAGE/UNENTSCHIEDEN, FFA Platz
		local color, text
		if data.Place then
			color = data.Place == 1 and C.Accent or (data.Place <= 3 and C.Primary or C.Muted)
			text = data.Place == 1 and "SIEG" or ("PLATZ " .. data.Place)
		elseif data.Winner == nil then
			color, text = C.Muted, "UNENTSCHIEDEN"
		else
			color, text = data.Won and C.Accent or C.Bad, data.Won and "SIEG" or "NIEDERLAGE"
		end
		title.Text = text
		title.TextColor3 = data.Winner == nil and not data.Place and C.Text or color
		lineTop.BackgroundColor3 = color
		lineBottom.BackgroundColor3 = color
		diamond:FindFirstChildOfClass("UIStroke").Color = color
		sub.Text = UITheme.Upper(tostring(data.Mode)) .. (data.Map and ("  ·  " .. UITheme.Upper(data.Map)) or "")

		if data.Place then
			score.Text = string.format('PLATZ <font color="#%s">%d</font> / %d', color:ToHex(), data.Place, data.Players or 1)
		else
			local mine, theirs = string.match(tostring(data.Score), "(%d+)%s*:%s*(%d+)")
			score.Text = mine and string.format('<font color="#%s">%s</font>  :  <font color="#%s">%s</font>',
				C.Accent:ToHex(), mine, C.Bad:ToHex(), theirs) or tostring(data.Score)
		end

		mvpCard.Visible = data.Mvp ~= nil
		mvpName.Text = UITheme.Upper(tostring(data.Mvp or ""))
		mvpName.TextColor3 = data.Mvp == player.Name and C.Accent or C.Text
		mvpKills.Text = (data.MvpKills or 0) .. " KILLS"

		local kills, deaths = data.Kills or 0, data.Deaths or 0
		local kd = deaths > 0 and kills / deaths or kills
		tiles.KILLS.Text = tostring(kills)
		tiles.TODE.Text = tostring(deaths)
		tiles["K/D"].Text = string.format("%.2f", kd)
		tiles["K/D"].TextColor3 = kd >= 1 and C.Good or C.Text
		tiles.SCHADEN.Text = formatNumber(data.Damage or 0)

		row.Visible = data.Progress ~= nil
		gui.Enabled = true

		-- Übersicht einblenden: Titel springt herein, Band klappt auf, Belohnungen laufen
		local function reveal()
			podium.Hide()
			background.Visible = true
			band.Size = UDim2.new(1, 0, 0, 0)
			TweenService:Create(band, TweenInfo.new(0.35, Enum.EasingStyle.Quart), { Size = UDim2.new(1, 0, 0, 150) }):Play()
			titleScale.Scale = 1.6
			title.TextTransparency = 1
			TweenService:Create(titleScale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			TweenService:Create(title, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
			if data.Progress then
				task.spawn(showProgress, data.Progress, isCurrent)
			end
		end

		-- Erst die Top-3-Bühne, dann die Übersicht
		if type(data.Top) == "table" and #data.Top > 0 then
			background.Visible = false
			podium.Show(data.Top, isCurrent)
			task.delay(PODIUM_TIME, function()
				if isCurrent() then
					reveal()
				end
			end)
		else
			reveal()
		end

		task.spawn(function()
			for left = math.floor(tonumber(data.ShowTime) or SHOW_TIME), 1, -1 do
				if not isCurrent() then
					return
				end
				footer.Text = "WEITER IN " .. left
				task.wait(1)
			end
			if isCurrent() then
				gui.Enabled = false
			end
		end)
	end)
end

return MatchSummary

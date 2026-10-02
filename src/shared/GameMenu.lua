-- GameMenu (ModuleScript, nur Client)
-- Hauptmenü im Stil von Rogue Company: oben Logo, Tabs (SPIELEN / AGENTEN), Münzen und Rang;
-- in der Mitte Karten für Modi bzw. Agenten; unten der große SPIELEN-Knopf.
-- Öffnen/Schließen mit M oder dem SPIELEN-Knopf im Hub. Es öffnet sich NICHT von selbst.
-- Alles liegt auf einer zentrierten Leinwand (UITheme.Canvas) und skaliert sauber mit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local RankConfig = require(Shared.RankConfig)
local Cosmetics = require(Shared.Cosmetics)
local AgentFigure = require(Shared.AgentFigure)
local UITheme = require(Shared.UITheme)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label

local GameMenu = {}

local WIDTH, HEIGHT = 1600, 900
local CARD_W, CARD_H, GAP = 284, 236, 20
local COLUMNS = 5 -- 10 Modi = 2 Reihen

-- Symbol pro Modus
local ICONS = {
	FreeForAll = "🎯", Drop = "🪂", Strikeout = "⚡", Demolition = "💣", Wingman = "🤝",
	Training = "🛠", Arena = "⚔", Ranked = "🏆", Extraction = "💻", TeamDeathmatch = "☠",
}

local gui, background, canvas, statusLabel, playButton, openButton, hubButton, closeButton
local modePage, agentPage
local tabButtons = {}
local modeCards = {}  -- [mode] = { Card, Stroke, Scale }
local agentCards = {} -- [agent] = { Card, Stroke, Badge, Level, Bar }
local selectedMode
local currentTab = "Modes"
local isOpen = false
local inHub = false

local function setStatus(message)
	statusLabel.Text = message or ""
end

-- Raster mit COLUMNS Spalten, mittig auf der Leinwand
local function makeGrid(count)
	local rows = math.ceil(count / COLUMNS)
	local columns = math.min(COLUMNS, count)
	local grid = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.new(0, columns * CARD_W + (columns - 1) * GAP, 0, rows * CARD_H + (rows - 1) * GAP),
		BackgroundTransparency = 1 }, canvas)
	make("UIGridLayout", { CellSize = UDim2.new(0, CARD_W, 0, CARD_H), CellPadding = UDim2.new(0, GAP, 0, GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	return grid
end

-- Karte mit Farbverlauf in der Modus-/Agentenfarbe und Hover-Effekt
local function makeCard(parent, order, color)
	local card = make("TextButton", { BackgroundColor3 = C.Card, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "", LayoutOrder = order, ClipsDescendants = true }, parent)
	UITheme.Corner(card, 4)
	make("UIGradient", { Rotation = 115, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(C.Card, 0.55)),
		ColorSequenceKeypoint.new(0.55, C.Card),
		ColorSequenceKeypoint.new(1, C.Card),
	}) }, card)
	local stroke = UITheme.Stroke(card, C.Border, 1)
	local scale = make("UIScale", {}, card)
	-- Farbige Leiste links
	make("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, card)
	card.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 1.03 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 1 }):Play()
	end)
	return card, stroke, scale
end

local function highlightCards(cards, chosen)
	for item, entry in cards do
		local on = item == chosen
		entry.Stroke.Color = on and C.Accent or C.Border
		entry.Stroke.Thickness = on and 3 or 1
	end
end

-- ---------- Tab SPIELEN ----------

local function selectMode(mode)
	selectedMode = mode
	highlightCards(modeCards, mode)
	if mode.Available then
		playButton.Text = "SPIELEN  ·  " .. mode.Name
		playButton.BackgroundColor3 = C.Play
		playButton.TextColor3 = Color3.fromRGB(20, 16, 10)
	else
		playButton.Text = "BALD VERFÜGBAR"
		playButton.BackgroundColor3 = C.Card
		playButton.TextColor3 = C.Muted
	end
end

local function buildModePage()
	modePage = makeGrid(#Modes.List)
	for i, mode in Modes.List do
		local card, stroke = makeCard(modePage, i, mode.Color)
		local faded = not mode.Available
		label({ Position = UDim2.new(0, 22, 0, 14), Size = UDim2.new(0, 60, 0, 60), Text = ICONS[mode.Id] or "◆",
			TextSize = 44, TextTransparency = faded and 0.5 or 0 }, card)
		label({ Position = UDim2.new(0, 22, 0, 78), Size = UDim2.new(1, -44, 0, 34), Text = mode.Name, TextSize = 28,
			Font = F.Title, TextTransparency = faded and 0.5 or 0 }, card)
		label({ Position = UDim2.new(0, 22, 0, 110), Size = UDim2.new(1, -44, 0, 20), Text = string.upper(mode.Tag),
			TextSize = 14, TextColor3 = mode.Color }, card)
		label({ Position = UDim2.new(0, 22, 0, 136), Size = UDim2.new(1, -44, 0, 60), Text = mode.Description,
			TextSize = 14, Font = F.Body, TextColor3 = C.Muted, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top }, card)
		label({ Position = UDim2.new(0, 22, 1, -32), Size = UDim2.new(0.6, 0, 0, 20), Text = "👥  " .. mode.Players,
			TextSize = 13, TextColor3 = C.Muted }, card)
		local live = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 1, -32), Size = UDim2.new(0.4, 0, 0, 20),
			Text = "", TextSize = 13, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Right }, card)
		if faded then
			local soon = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 18), Size = UDim2.new(0, 80, 0, 26),
				Text = "BALD", TextSize = 13, BackgroundTransparency = 0, BackgroundColor3 = C.Border,
				TextXAlignment = Enum.TextXAlignment.Center }, card)
			UITheme.Corner(soon, 6)
		end
		card.Activated:Connect(function()
			selectMode(mode)
		end)
		modeCards[mode] = { Card = card, Stroke = stroke, Live = live }
	end
end

-- ---------- Tab AGENTEN ----------

local function currentAgent()
	return AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
end

local function buildAgentPage()
	agentPage = makeGrid(#AgentConfig.Agents)
	agentPage.Visible = false
	for i, agent in AgentConfig.Agents do
		local card, stroke = makeCard(agentPage, i, agent.Color)
		-- 3D-Figur links
		local viewport = make("ViewportFrame", { Position = UDim2.new(0, 6, 0, 0), Size = UDim2.new(0, 130, 1, 0),
			BackgroundTransparency = 1, Ambient = Color3.fromRGB(130, 135, 150), LightColor = Color3.fromRGB(255, 245, 235),
			LightDirection = Vector3.new(-0.5, -1, 0.6) }, card)
		local camera = make("Camera", { FieldOfView = 34 }, viewport)
		camera.CFrame = AgentFigure.CameraCFrame
		viewport.CurrentCamera = camera
		local primary, accent = Cosmetics.AgentColors(player, agent.Id)
		local figure = AgentFigure.Build(agent, primary, accent, nil)
		figure:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, 0.35, 0))
		figure.Parent = viewport

		local x = 140
		label({ Position = UDim2.new(0, x, 0, 16), Size = UDim2.new(1, -x - 14, 0, 32), Text = agent.Name, TextSize = 26,
			Font = F.Title }, card)
		label({ Position = UDim2.new(0, x, 0, 46), Size = UDim2.new(1, -x - 14, 0, 18), Text = string.upper(agent.Role),
			TextSize = 13, TextColor3 = agent.Color }, card)
		local level = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 20), Size = UDim2.new(0, 60, 0, 20),
			Text = "", TextSize = 14, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Right }, card)
		-- Kills mit diesem Agenten (aus der Statistik)
		local kills = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 46), Size = UDim2.new(0, 100, 0, 18),
			Text = "", TextSize = 12, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, card)
		local barBack = make("Frame", { Position = UDim2.new(0, x, 0, 70), Size = UDim2.new(1, -x - 14, 0, 4),
			BackgroundColor3 = C.Border, BorderSizePixel = 0 }, card)
		local bar = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = agent.Color, BorderSizePixel = 0 }, barBack)
		local weapons = {}
		for _, weapon in agent.Loadout do
			table.insert(weapons, WeaponConfig.Get(weapon).DisplayName)
		end
		label({ Position = UDim2.new(0, x, 0, 82), Size = UDim2.new(1, -x - 14, 0, 18),
			Text = "♥ " .. agent.Health .. "   ⚡ " .. agent.WalkSpeed, TextSize = 13 }, card)
		label({ Position = UDim2.new(0, x, 0, 102), Size = UDim2.new(1, -x - 14, 0, 18), Text = table.concat(weapons, " + "),
			TextSize = 13, Font = F.Body, TextColor3 = C.Muted }, card)
		label({ Position = UDim2.new(0, x, 0, 126), Size = UDim2.new(1, -x - 14, 0, 18),
			Text = "Q  " .. string.upper(agent.Ability.Name), TextSize = 13, TextColor3 = agent.Color }, card)
		label({ Position = UDim2.new(0, x, 0, 146), Size = UDim2.new(1, -x - 14, 0, 18),
			Text = "G  " .. string.upper(agent.Gadget.Name), TextSize = 13, TextColor3 = C.Muted }, card)
		label({ Position = UDim2.new(0, x, 0, 166), Size = UDim2.new(1, -x - 14, 0, 18),
			Text = "◆  " .. string.upper(agent.Passive and agent.Passive.Name or ""), TextSize = 13, TextColor3 = C.Muted }, card)
		local badge = label({ Position = UDim2.new(0, x, 1, -42), Size = UDim2.new(1, -x - 14, 0, 30), Text = "",
			TextSize = 14, BackgroundTransparency = 0, BackgroundColor3 = C.Border,
			TextXAlignment = Enum.TextXAlignment.Center }, card)
		UITheme.Corner(badge, 8)

		card.Activated:Connect(function()
			-- Gesperrt: mit Münzen freischalten, sonst wählen
			if not AgentConfig.IsUnlocked(player, agent.Id) then
				Remotes.ShopAction:FireServer("UnlockAgent", agent.Id)
				return
			end
			Remotes.SelectAgent:FireServer(agent.Id)
			setStatus(agent.Name .. " gewählt – aktiv ab dem nächsten Spawn.")
		end)
		agentCards[agent] = { Card = card, Stroke = stroke, Badge = badge, Level = level, Bar = bar, Kills = kills }
	end

	local function refresh()
		local chosen = currentAgent()
		local ok, stats = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Stats") or "{}")
		stats = ok and type(stats) == "table" and stats or {}
		for agent, entry in agentCards do
			local isChosen = agent == chosen
			local unlocked = AgentConfig.IsUnlocked(player, agent.Id)
			entry.Stroke.Color = isChosen and C.Accent or C.Border
			entry.Stroke.Thickness = isChosen and 3 or 1
			entry.Badge.Text = not unlocked and ("🔒  " .. agent.Price .. " MÜNZEN") or (isChosen and "✓  GEWÄHLT" or "WÄHLEN")
			entry.Badge.BackgroundColor3 = isChosen and C.Good or (unlocked and C.Border or C.AccentDark)
			entry.Badge.TextColor3 = (isChosen or not unlocked) and Color3.fromRGB(15, 15, 20) or C.Text
			local xp = AgentConfig.GetXP(player, agent.Id)
			entry.Level.Text = "LV " .. AgentConfig.LevelFromXP(xp)
			entry.Bar.Size = UDim2.new(AgentConfig.LevelProgress(xp), 0, 1, 0)
			entry.Kills.Text = (stats["Kills_" .. agent.Id] or 0) .. " KILLS"
		end
	end
	refresh()
	player.AttributeChanged:Connect(refresh)
end

-- ---------- Tabs ----------

local function showTab(name)
	currentTab = name
	modePage.Visible = name == "Modes"
	agentPage.Visible = name == "Agents"
	playButton.Visible = name == "Modes"
	for tabName, entry in tabButtons do
		local active = tabName == name
		entry.Button.TextColor3 = active and C.Text or C.Muted
		entry.Underline.Visible = active
	end
	setStatus("")
end

local function buildTopBar()
	UITheme.Diamond(canvas, 34, UDim2.new(0, 80, 0, 62), C.Accent)
	label({ Position = UDim2.new(0, 110, 0, 34), Size = UDim2.new(0, 400, 0, 56), Text = "SHOOTOUT", TextSize = 54,
		Font = F.Title, TextColor3 = C.Text }, canvas)
	label({ Position = UDim2.new(0, 112, 0, 86), Size = UDim2.new(0, 400, 0, 18), Text = "TACTICAL OPERATIONS",
		TextSize = 14, Font = F.Bold, TextColor3 = C.Accent }, canvas)

	-- Tabs in der Mitte
	local tabs = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.new(0, 420, 0, 46), BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 20),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for i, entry in { { "Modes", "SPIELEN" }, { "Agents", "AGENTEN" } } do
		local button = make("TextButton", { Size = UDim2.new(0, 190, 1, 0), BackgroundTransparency = 1, Text = entry[2],
			Font = F.Title, TextSize = 28, TextColor3 = C.Muted, LayoutOrder = i }, tabs)
		local underline = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(0, 120, 0, 4), BackgroundColor3 = C.Accent, BorderSizePixel = 0 }, button)
		UITheme.Corner(underline, 2)
		button.Activated:Connect(function()
			showTab(entry[1])
		end)
		tabButtons[entry[1]] = { Button = button, Underline = underline }
	end

	-- Rechts: Münzen und Rang
	local coins = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 0, 36), Size = UDim2.new(0, 300, 0, 28),
		Text = "", TextSize = 22, Font = F.Title, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Right }, canvas)
	local rank = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 0, 66), Size = UDim2.new(0, 300, 0, 24),
		Text = "", TextSize = 17, Font = F.Title, TextXAlignment = Enum.TextXAlignment.Right }, canvas)
	local function update()
		coins.Text = "LV " .. AgentConfig.PlayerLevel(player) .. "     💰 " .. (player:GetAttribute("Coins") or 0)
		local elo = player:GetAttribute("Elo") or RankConfig.StartElo
		local tier = RankConfig.Get(elo)
		rank.Text = "🏆 " .. tier.Display .. "  ·  " .. elo .. " ELO"
		rank.TextColor3 = tier.Color
	end
	update()
	player:GetAttributeChangedSignal("Coins"):Connect(update)
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 3) == "XP_" then
			update()
		end
	end)
	player:GetAttributeChangedSignal("Elo"):Connect(update)
end

local function buildBottomBar()
	statusLabel = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 704), Size = UDim2.new(0, 900, 0, 26),
		Text = "", TextSize = 17, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }, canvas)

	playButton = UITheme.Button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 0, 760),
		Size = UDim2.new(0, 420, 0, 84), TextSize = 34, Text = "" }, canvas, function()
		if selectedMode.Available then
			setStatus("Suche Server für " .. selectedMode.Name .. "...")
			Remotes.JoinMode:FireServer(selectedMode.Id)
		else
			setStatus(selectedMode.Name .. " kommt bald.")
		end
	end)

	-- Schnelles Spiel (RC "Quick Play"): Server wählt den vollsten Modus mit freiem Platz
	UITheme.Button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -500, 0, 772), Size = UDim2.new(0, 230, 0, 60),
		TextSize = 20, Text = "⚡ SCHNELLES SPIEL", BackgroundColor3 = C.AccentDark }, canvas, function()
		setStatus("Suche schnelles Spiel...")
		Remotes.JoinMode:FireServer("Quick")
	end)

	hubButton = UITheme.Button({ Position = UDim2.new(0, 60, 0, 772), Size = UDim2.new(0, 250, 0, 60), TextSize = 18,
		Text = "⌂  ZURÜCK ZUM HUB", BackgroundColor3 = C.Card }, canvas, function()
		setStatus("Zurück zum Hub...")
		Remotes.JoinMode:FireServer(Modes.Hub.Id)
	end)
	closeButton = UITheme.Button({ Position = UDim2.new(0, 330, 0, 772), Size = UDim2.new(0, 220, 0, 60), TextSize = 18,
		Text = "", BackgroundColor3 = C.Card }, canvas, function()
		GameMenu.SetOpen(false)
	end)

	label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 862), Size = UDim2.new(0, 1200, 0, 20),
		Text = "M Menü  ·  Q Fähigkeit  ·  G Gadget  ·  V Messer  ·  Z Ping  ·  T Kamera  ·  X Schulter  ·  Rechtsklick Zielen  ·  STRG Ducken/Slide  ·  E Aktion  ·  Tab Punkte",
		TextSize = 13, Font = F.Body, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }, canvas)
end

-- Menü öffnen/schließen. Solange offen: Maus frei, Hintergrund unscharf.
function GameMenu.SetOpen(open: boolean)
	if open == isOpen and gui.Enabled == open then
		return
	end
	isOpen = open
	gui.Enabled = open
	openButton.Visible = inHub and not open
	UITheme.SetBlur("GameMenu", open)
	if open then
		background.BackgroundTransparency = 1
		TweenService:Create(background, TweenInfo.new(0.2), { BackgroundTransparency = 0.25 }):Play()
		RunService:BindToRenderStep("GameMenuMouse", Enum.RenderPriority.Camera.Value + 1, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	else
		RunService:UnbindFromRenderStep("GameMenuMouse")
	end
end

function GameMenu.Open(tab)
	GameMenu.SetOpen(true)
	showTab(tab or "Modes")
end

function GameMenu.IsOpen()
	return isOpen
end

function GameMenu.Init()
	gui = make("ScreenGui", { Name = "GameMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, player:WaitForChild("PlayerGui"))
	background = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.25, Active = true }, gui) -- Active: Klicks gehen nicht ins Spiel
	UITheme.Gradient(background, Color3.fromRGB(20, 45, 65), Color3.fromRGB(4, 8, 14))
	canvas = UITheme.Canvas(background, WIDTH, HEIGHT)

	buildTopBar()
	buildBottomBar()
	buildModePage()
	buildAgentPage()
	selectMode(Modes.List[1])
	showTab("Modes")

	-- Live-Spielerzahlen auf den Modus-Karten
	local function updateCounts()
		local raw = ReplicatedStorage:GetAttribute("ModeCounts")
		local ok, counts = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), raw or "{}")
		counts = ok and counts or {}
		for mode, entry in modeCards do
			local n = counts[mode.Id] or 0
			entry.Live.Text = n > 0 and ("● " .. n .. " spielen") or ""
		end
	end
	updateCounts()
	ReplicatedStorage:GetAttributeChangedSignal("ModeCounts"):Connect(updateCounts)

	-- Im Hub: großer Knopf unten mittig öffnet das Menü
	local openGui = make("ScreenGui", { Name = "PlayButton", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9 },
		player.PlayerGui)
	openButton = UITheme.Button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34),
		Size = UDim2.new(0, 300, 0, 64), TextSize = 30, Text = "SPIELEN   [M]", BackgroundColor3 = C.Play,
		TextColor3 = Color3.fromRGB(20, 16, 10), Visible = false }, openGui, function()
		GameMenu.SetOpen(true)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.M then
			GameMenu.SetOpen(not isOpen)
		end
	end)

	-- Rückmeldung beim Freischalten von Agenten
	Remotes.ShopStatus.OnClientEvent:Connect(function(message)
		if isOpen then
			setStatus(message)
		end
	end)
	-- Meldungen vom Server (Modus voll, kommt bald, ...) öffnen das Menü mit der Meldung
	Remotes.MenuStatus.OnClientEvent:Connect(function(message)
		GameMenu.SetOpen(true)
		showTab("Modes")
		setStatus(message)
	end)

	-- Moduswechsel: Menü schließen (öffnet sich nicht von selbst), im Hub den SPIELEN-Knopf zeigen
	local function onModeChanged()
		local mode = player:GetAttribute("Mode")
		if mode == nil then
			return
		end
		inHub = mode == Modes.Hub.Id
		hubButton.Visible = not inHub
		closeButton.Position = UDim2.new(0, inHub and 60 or 330, 0, 772)
		closeButton.Text = inHub and "✕  SCHLIESSEN" or "▶  WEITERSPIELEN"
		GameMenu.SetOpen(false)
		openButton.Visible = inHub
	end
	player:GetAttributeChangedSignal("Mode"):Connect(onModeChanged)
	onModeChanged()
end

return GameMenu

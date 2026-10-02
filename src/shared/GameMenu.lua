-- GameMenu (ModuleScript, nur Client)
-- Lobby im nüchternen Taktik-Look (UITheme):
--   oben:   Logo, Reiter SPIELEN · AGENTEN · LOADOUT · SHOP · BATTLE PASS (aktiv: weiß mit Bernstein-Strich),
--           rechts Münzen, Level, STATISTIK, CODES, OPTIONEN und Schließen
--   links:  Spielmodi (aktiver Modus heller mit Bernstein-Balken links) und der Squad (bis 4, Anführer mit
--           Stern, Level, BEREIT/NICHT BEREIT – den eigenen Status schaltet man per Klick, freie Plätze laden ein)
--   Mitte:  der gewählte Agent groß in 3D mit Rollen-Schild und Namen
--   rechts: Battle Pass (Stufe, Fortschritt, nächste Belohnung), täglicher Auftrag, großer SPIELEN-Knopf
--           mit Modus, Spielerzahl und Ping
-- AGENTEN zeigt alle Agenten als Karten (wählen bzw. freischalten). LOADOUT, SHOP, BATTLE PASS, Statistik,
-- Codes, Einstellungen, Aufträge, tägliche Belohnung und Squad öffnen die Fenster des SideMenu über der
-- Lobby (GameMenu.SetPanelHandler). Öffnen/Schließen mit M oder dem SPIELEN-Knopf im Hub; es öffnet sich
-- NICHT von selbst. Alles liegt auf einer zentrierten Leinwand (UITheme.Canvas) und skaliert mit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)
local LevelConfig = require(Shared.LevelConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local Cosmetics = require(Shared.Cosmetics)
local AgentFigure = require(Shared.AgentFigure)
local PassConfig = require(Shared.PassConfig)
local QuestConfig = require(Shared.QuestConfig)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label
local upper = UITheme.Upper

local GameMenu = {}

local WIDTH, HEIGHT = 1600, 900
local LEFT_X, LEFT_W = 40, 340          -- Spalte Spielmodi + Squad
local RIGHT_X, RIGHT_W = 1220, 340      -- Spalte Battle Pass, Auftrag, SPIELEN
local SQUAD_SIZE = 4

-- Schnelles Spiel: der Server wählt den vollsten Kampfmodus mit freiem Platz
local QUICK = { Id = "Quick", Name = "SCHNELLES SPIEL", Tag = "Voller Modus mit freiem Platz", Available = true }

-- Navigation: Seite in der Lobby oder Fenster des SideMenu
local NAV = {
	{ Id = "Play", Text = "SPIELEN" },
	{ Id = "Agents", Text = "AGENTEN" },
	{ Id = "Inventory", Text = "LOADOUT", Panel = true },
	{ Id = "Shop", Text = "SHOP", Panel = true },
	{ Id = "Pass", Text = "BATTLE PASS", Panel = true },
}

local gui, background, canvas, statusLabel, openButton, hubButton, closeButton
local play -- großer SPIELEN-Knopf (Chunky) mit Unterzeile
local playSub
local playPage, agentPage
local navButtons = {}   -- [Id] = TextButton
local modeButtons = {}  -- [mode] = { Chunky, Detail, Check, Live }
local agentCards = {}   -- [agent] = { ... }
local selectedMode
local currentPage = "Play"
local isOpen = false
local inHub = false
local panelHandler = nil -- function(name): Fenster des SideMenu öffnen (nil = schließen)
local openPanelName = nil

local function setStatus(message)
	statusLabel.Text = message or ""
end

local function currentAgent()
	return AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
end

local function decode(raw)
	if type(raw) ~= "string" then
		return {}
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(data) == "table" and data or {}
end

-- Fenster des SideMenu über der Lobby öffnen
local function openPanel(name)
	if panelHandler then
		panelHandler(name)
	end
end

-- Kleine Fläche mit Rand (Münzen, Level oben rechts)
local function pill(width, order, parent)
	return UITheme.Panel({ Size = UDim2.fromOffset(width, 44), LayoutOrder = order, BackgroundTransparency = 0.12 }, parent)
end

-- Flacher Text-Knopf oben rechts (Statistik, Codes, Optionen, Schließen)
local function headerButton(text, width, order, parent, onClick)
	return UITheme.Chunky({ Size = UDim2.fromOffset(width, 44), LayoutOrder = order, Color = C.Panel, StrokeColor = C.Border,
		Text = text, TextSize = 16, Font = F.Display }, parent, onClick)
end

-- ---------- Navigation ----------

-- Aktiver Reiter: weiße Schrift mit Bernstein-Strich darunter, sonst gedämpft
local function updateNav()
	local active = openPanelName or currentPage
	for id, button in navButtons do
		local on = id == active
		button.TextColor3 = on and C.Text or C.Muted
		button.Underline.Visible = on
	end
end

local function showPage(name)
	currentPage = name
	playPage.Visible = name == "Play"
	agentPage.Visible = name == "Agents"
	updateNav()
	setStatus("")
end

local function buildHeader()
	label({ Position = UDim2.fromOffset(LEFT_X, 26), Size = UDim2.fromOffset(280, 56), Text = "SHOOTOUT",
		TextSize = 46, Font = F.Display, TextColor3 = C.Text }, canvas)
	make("Frame", { Position = UDim2.fromOffset(LEFT_X, 82), Size = UDim2.fromOffset(36, 2), BackgroundColor3 = C.Primary,
		BorderSizePixel = 0 }, canvas)

	local nav = make("Frame", { Position = UDim2.fromOffset(330, 32), Size = UDim2.fromOffset(700, 44),
		BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, nav)
	for i, entry in NAV do
		local button = make("TextButton", { Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false,
			Font = F.Display, TextSize = 19, Text = entry.Text, TextColor3 = C.Muted, LayoutOrder = i }, nav)
		make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, button)
		make("Frame", { Name = "Underline", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, -28, 0, 2), BackgroundColor3 = C.Primary, BorderSizePixel = 0, Visible = false }, button)
		button.MouseEnter:Connect(function()
			button.TextColor3 = C.Text
		end)
		button.MouseLeave:Connect(updateNav)
		button.Activated:Connect(function()
			if entry.Panel then
				openPanel(entry.Id)
			else
				openPanel(nil)
				showPage(entry.Id)
			end
		end)
		navButtons[entry.Id] = button
	end

	-- Rechts: Münzen, Level, Statistik, Codes, Optionen, Schließen
	local right = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -LEFT_X, 0, 30),
		Size = UDim2.fromOffset(660, 50), BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, right)

	local coins = pill(132, 1, right)
	UITheme.Coin(coins, 14, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0) })
	local coinText = label({ Position = UDim2.fromOffset(36, 2), Size = UDim2.new(1, -48, 0, 40), Text = "", TextSize = 22,
		Font = F.Display, TextXAlignment = Enum.TextXAlignment.Right }, coins)

	local level = pill(104, 2, right)
	local levelTag = UITheme.Tag({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Text = "LV", TextSize = 11,
		BackgroundColor3 = C.Secondary, TextColor3 = C.Muted }, level)
	local levelText = label({ Position = UDim2.fromOffset(46, 2), Size = UDim2.new(1, -58, 0, 40), Text = "", TextSize = 22,
		Font = F.Display, TextXAlignment = Enum.TextXAlignment.Right }, level)

	headerButton("STATISTIK", 92, 3, right, function()
		openPanel("Stats")
	end)
	headerButton("CODES", 72, 4, right, function()
		openPanel("Codes")
	end)
	headerButton("OPTIONEN", 90, 5, right, function()
		openPanel("Settings")
	end)
	closeButton = headerButton("✕", 44, 6, right, function()
		GameMenu.SetOpen(false)
	end)

	local function update()
		coinText.Text = UITheme.FormatNumber(player:GetAttribute("Coins") or 0)
		local info = LevelConfig.Get(player)
		levelText.Text = (info.Prestige > 0 and ("★" .. info.Prestige .. " ") or "") .. tostring(info.Level)
		levelText.TextColor3 = info.Prestige > 0 and info.Color or C.Text
		levelTag.TextColor3 = info.Prestige > 0 and info.Color or C.Muted
	end
	update()
	player.AttributeChanged:Connect(function(name)
		if name == "Coins" or name == "AccountXP" or name == "Prestige" then
			update()
		end
	end)
end

-- ---------- Links: Spielmodi ----------

local function liveCounts()
	return decode(ReplicatedStorage:GetAttribute("ModeCounts"))
end

-- Aktiver Modus: hellere Fläche, Bernstein-Balken links und Rand
local function selectMode(mode)
	selectedMode = mode
	for entryMode, entry in modeButtons do
		local on = entryMode == mode
		entry.Chunky.SetColor(on and C.Secondary or C.Panel, C.Text)
		entry.Chunky.SetStroke(on and C.Primary or C.Border, 1)
		entry.Chunky.Stroke.Transparency = on and 0.35 or 0.6
		entry.Detail.TextColor3 = on and C.Primary or C.Muted
		entry.Check.Visible = on
	end
	GameMenu.UpdatePlay()
end

local function buildModes()
	label({ Position = UDim2.fromOffset(LEFT_X, 106), Size = UDim2.fromOffset(LEFT_W, 22), Text = "SPIELMODUS", TextSize = 12,
		Font = F.Bold, TextColor3 = C.Muted }, playPage.Parent)
	local list = make("Frame", { Position = UDim2.fromOffset(LEFT_X, 134), Size = UDim2.fromOffset(LEFT_W, 450),
		BackgroundTransparency = 1 }, playPage.Parent)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local entries = { QUICK }
	for _, mode in Modes.List do
		table.insert(entries, mode)
	end
	for i, mode in entries do
		local chunky = UITheme.Chunky({ Size = UDim2.fromOffset(LEFT_W, 58), LayoutOrder = i, Color = C.Panel, Text = "",
			StrokeColor = C.Border }, list, function()
			selectMode(mode)
		end)
		local face = chunky.Face
		face.BackgroundTransparency = 0.12
		local name = label({ Position = UDim2.fromOffset(18, 8), Size = UDim2.new(1, -100, 0, 26),
			Text = mode.Name, TextSize = 22, Font = F.Display }, face)
		local detail = label({ Position = UDim2.fromOffset(18, 34), Size = UDim2.new(1, -100, 0, 16),
			Text = upper(mode.Tag or ""), TextSize = 11, Font = F.Bold, TextColor3 = C.Muted }, face)
		-- aktiv: Bernstein-Balken am linken Rand
		local check = make("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = C.Primary, BorderSizePixel = 0,
			Visible = false }, face)
		local live = label({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(80, 20),
			Text = "", TextSize = 12, Font = F.Bold, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Right }, face)
		if not mode.Available then
			name.TextTransparency = 0.5
			detail.Text = "BALD VERFÜGBAR"
		end
		modeButtons[mode] = { Chunky = chunky, Detail = detail, Check = check, Live = live, Name = name }
	end

	local function updateCounts()
		local counts = liveCounts()
		local total = 0
		for _, n in counts do
			total += tonumber(n) or 0
		end
		for mode, entry in modeButtons do
			local n = mode == QUICK and total or (counts[mode.Id] or 0)
			entry.Live.Text = n > 0 and ("● " .. n) or ""
		end
		GameMenu.UpdatePlay()
	end
	updateCounts()
	ReplicatedStorage:GetAttributeChangedSignal("ModeCounts"):Connect(updateCounts)
end

-- ---------- Links: Squad ----------

local function initials(name)
	local letters = string.gsub(name, "[^%w]", "")
	return string.upper(string.sub(letters ~= "" and letters or name, 1, 2))
end

local function buildSquad()
	local panel = UITheme.Card({ Name = "Squad", Position = UDim2.fromOffset(LEFT_X, 598), Size = UDim2.fromOffset(LEFT_W, 262) },
		playPage.Parent)
	local title = label({ Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(200, 26), Text = "", TextSize = 21,
		Font = F.Display, RichText = true, ZIndex = 3 }, panel)
	local invite = make("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 1, Text = "+ EINLADEN", Font = F.Bold, TextSize = 12,
		TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 }, panel)
	invite.Activated:Connect(function()
		openPanel("Squad")
	end)
	local rows = make("Frame", { Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -28, 1, -60), BackgroundTransparency = 1,
		ZIndex = 3 }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, rows)

	local signature = ""
	local function refresh()
		local party = decode(player:GetAttribute("Party"))
		local members = party.Members or { { UserId = player.UserId, Name = player.Name } }
		local leader = party.Leader or player.UserId
		local parts = {}
		local list = {}
		for _, member in members do
			local other = Players:GetPlayerByUserId(member.UserId)
			local info = other and LevelConfig.Get(other)
			local ready = other and other:GetAttribute("PartyReady") == true
			local entry = { UserId = member.UserId, Name = member.Name, Leader = member.UserId == leader,
				Level = info and info.Level or 1, Ready = ready, Me = member.UserId == player.UserId }
			table.insert(list, entry)
			table.insert(parts, member.UserId .. tostring(entry.Level) .. tostring(ready) .. tostring(entry.Leader))
		end
		local newSignature = table.concat(parts, "|")
		if newSignature == signature then
			return
		end
		signature = newSignature
		title.Text = string.format('SQUAD <font color="#%s">%d/%d</font>', C.Muted:ToHex(), #list, SQUAD_SIZE)
		for _, child in rows:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i = 1, SQUAD_SIZE do
			local entry = list[i]
			if entry then
				local row = make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 3 }, rows)
				local avatar = label({ Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(36, 36), Text = initials(entry.Name),
					TextSize = 13, Font = F.Bold, BackgroundTransparency = 0, BackgroundColor3 = C.Secondary,
					TextColor3 = entry.Me and C.Primary or C.Text, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, row)
				UITheme.Corner(avatar, UITheme.Radius.Small)
				UITheme.Stroke(avatar, entry.Me and C.Primary or C.Border, 1)
				label({ Position = UDim2.fromOffset(46, 3), Size = UDim2.new(1, -170, 0, 20),
					Text = (entry.Me and "Du" or entry.Name) .. (entry.Leader and "  ★" or ""), TextSize = 15,
					TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 }, row)
				label({ Position = UDim2.fromOffset(46, 23), Size = UDim2.new(1, -170, 0, 16), Text = "Level " .. entry.Level,
					TextSize = 12, Font = F.Medium, TextColor3 = C.Muted, ZIndex = 3 }, row)
				local badge = make("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.fromOffset(112, 26), BackgroundColor3 = entry.Ready and C.Good or C.MutedBack, BorderSizePixel = 0,
					AutoButtonColor = entry.Me, Font = F.Bold, TextSize = 11,
					Text = entry.Ready and "BEREIT" or "NICHT BEREIT", ZIndex = 3,
					TextColor3 = entry.Ready and C.PrimaryText or C.Muted }, row)
				UITheme.Corner(badge, UITheme.Radius.Small)
				if entry.Me then
					badge.Activated:Connect(function()
						Remotes.PartyAction:FireServer("Ready")
					end)
				end
			else
				local slot = make("TextButton", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Text = "+  FREIER PLATZ",
					Font = F.Bold, TextSize = 11, TextColor3 = C.Muted, AutoButtonColor = false, LayoutOrder = i, ZIndex = 3 }, rows)
				UITheme.Corner(slot, UITheme.Radius.Small)
				UITheme.Stroke(slot, C.Border, 1, 0.3)
				slot.Activated:Connect(function()
					openPanel("Squad")
				end)
			end
		end
	end
	refresh()
	player:GetAttributeChangedSignal("Party"):Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			if isOpen then
				refresh()
			end
		end
	end)
end

-- ---------- Mitte: Agent ----------

local function buildAgentStage()
	local stage = make("Frame", { Position = UDim2.fromOffset(410, 96), Size = UDim2.fromOffset(780, 790), BackgroundTransparency = 1 },
		playPage)
	-- dezentes Gegenlicht hinter der Figur (weich auslaufend) und ein Schatten am Boden – neutral, nicht in Agentenfarbe
	for _, size in { 600, 450, 300 } do
		local backlight = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 330),
			Size = UDim2.fromOffset(size, size), BackgroundColor3 = C.Text, BackgroundTransparency = 0.982, BorderSizePixel = 0 }, stage)
		UITheme.Corner(backlight, size / 2)
	end
	local floor = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 618),
		Size = UDim2.fromOffset(300, 34), BackgroundColor3 = C.Shadow, BackgroundTransparency = 0.55, BorderSizePixel = 0 }, stage)
	UITheme.Corner(floor, 17)
	local viewport = make("ViewportFrame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.fromOffset(600, 640), BackgroundTransparency = 1, Ambient = Color3.fromRGB(140, 145, 165),
		LightColor = Color3.fromRGB(255, 246, 232), LightDirection = Vector3.new(-0.45, -1, 0.65) }, stage)
	local camera = make("Camera", { FieldOfView = 30 }, viewport)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 2.9, -12), Vector3.new(0, 2.75, 0))
	viewport.CurrentCamera = camera

	local role = UITheme.Tag({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 640), Text = "", TextSize = 12,
		BackgroundColor3 = C.Secondary, TextColor3 = C.Primary }, stage)
	local name = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 664), Size = UDim2.fromOffset(780, 84),
		Text = "", TextSize = 84, Font = F.Display, TextXAlignment = Enum.TextXAlignment.Center }, stage)
	UITheme.Outline(name, 1)
	local change = make("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 752),
		Size = UDim2.fromOffset(240, 24), BackgroundTransparency = 1, Text = "AGENT WECHSELN  →", Font = F.Bold, TextSize = 12,
		TextColor3 = C.Muted }, stage)
	change.Activated:Connect(function()
		showPage("Agents")
	end)

	local figure, shownKey = nil, nil
	local function refresh()
		local agent = currentAgent()
		local primary, accent = Cosmetics.AgentColors(player, agent.Id)
		local weapon = AgentConfig.LoadoutFor(player, agent.Id)[1]
		local key = agent.Id .. tostring(primary) .. tostring(accent) .. tostring(weapon)
			.. tostring(Cosmetics.WeaponSkin(player, agent.Id, weapon))
		if key ~= shownKey then
			shownKey = key
			if figure then
				figure:Destroy()
			end
			figure = AgentFigure.Build(agent, primary, accent, Cosmetics.WeaponSkin(player, agent.Id, weapon), weapon)
			figure.Parent = viewport
		end
		role.Text = upper(agent.Role)
		name.Text = agent.Name
	end
	refresh()
	player.AttributeChanged:Connect(function(attribute)
		if attribute == "Agent" or attribute == "Equipped" or attribute == "Owned" or attribute == "Loadouts" then
			refresh()
		end
	end)
	-- Figur dreht sich langsam hin und her
	RunService.RenderStepped:Connect(function()
		if isOpen and figure and playPage.Visible then
			local angle = math.sin(os.clock() * 0.5) * 0.5 + 0.35
			figure:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, angle, 0))
		end
	end)
end

-- ---------- Rechts: Battle Pass, täglicher Auftrag, SPIELEN ----------

local function clickable(frame, onClick)
	local button = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5 }, frame)
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	button.MouseEnter:Connect(function()
		if stroke then
			stroke.Color = C.Primary
		end
	end)
	button.MouseLeave:Connect(function()
		if stroke then
			stroke.Color = C.Border
		end
	end)
	button.Activated:Connect(onClick)
	return button
end

local function progressBar(parent, y, color)
	local back = make("Frame", { Position = UDim2.fromOffset(18, y + 5), Size = UDim2.new(1, -36, 0, 6), BackgroundColor3 = C.Background,
		BorderSizePixel = 0, ZIndex = 3 }, parent)
	UITheme.Corner(back, 1)
	local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 3 }, back)
	UITheme.Corner(fill, 1)
	return fill
end

local function buildPass()
	local panel = UITheme.Card({ Name = "Pass", Position = UDim2.fromOffset(RIGHT_X, 106), Size = UDim2.fromOffset(RIGHT_W, 156) },
		playPage)
	label({ Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(220, 26), Text = "BATTLE PASS · S1", TextSize = 21,
		Font = F.Display, ZIndex = 3 }, panel)
	local tier = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 12), Size = UDim2.fromOffset(120, 26),
		Text = "", TextSize = 21, Font = F.Display, TextColor3 = C.Primary, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 },
		panel)
	local fill = progressBar(panel, 52, C.Primary)
	local xpText = label({ Position = UDim2.fromOffset(18, 80), Size = UDim2.new(1, -36, 0, 18), Text = "", TextSize = 13,
		Font = F.Medium, TextColor3 = C.Muted, ZIndex = 3 }, panel)
	local rewardText = label({ Position = UDim2.fromOffset(18, 102), Size = UDim2.new(1, -36, 0, 36), Text = "", TextSize = 13,
		Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3 }, panel)
	clickable(panel, function()
		openPanel("Pass")
	end)

	local function refresh()
		local xp = player:GetAttribute("PassXP") or 0
		local current, progress = PassConfig.TierFromXP(xp)
		local max = #PassConfig.Tiers
		tier.Text = "STUFE " .. current
		fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
		if current >= max then
			xpText.Text = "Pass abgeschlossen!"
			rewardText.Text = PassConfig.SeasonName
			return
		end
		xpText.Text = UITheme.FormatNumber(progress * PassConfig.XPPerTier) .. " / " .. UITheme.FormatNumber(PassConfig.XPPerTier)
			.. " XP bis Stufe " .. (current + 1)
		local reward = PassConfig.Tiers[current + 1]
		local item = reward and reward.Item and Cosmetics.Get(reward.Item)
		rewardText.Text = "Schaltet frei: " .. (item and item.Name or ((reward and reward.Coins or 0) .. " Münzen"))
	end
	refresh()
	player:GetAttributeChangedSignal("PassXP"):Connect(refresh)
end

local function buildDaily()
	local panel = UITheme.Card({ Name = "Daily", Position = UDim2.fromOffset(RIGHT_X, 280), Size = UDim2.fromOffset(RIGHT_W, 170) },
		playPage)
	label({ Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(240, 26), Text = "TÄGLICHER AUFTRAG", TextSize = 21,
		Font = F.Display, ZIndex = 3 }, panel)
	local count = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 16), Size = UDim2.fromOffset(90, 20),
		Text = "", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 }, panel)
	local questText = label({ Position = UDim2.fromOffset(18, 46), Size = UDim2.new(1, -110, 0, 44), Text = "", TextSize = 16,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3 }, panel)
	local progressText = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 44), Size = UDim2.fromOffset(84, 30),
		Text = "", TextSize = 26, Font = F.Display, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 }, panel)
	local fill = progressBar(panel, 96, C.Accent)
	local rewardText = label({ Position = UDim2.fromOffset(18, 124), Size = UDim2.new(1, -36, 0, 18), Text = "", TextSize = 13,
		Font = F.Medium, TextColor3 = C.Muted, ZIndex = 3 }, panel)
	local dailyChip = UITheme.Tag({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 122), Text = "BELOHNUNG BEREIT",
		TextSize = 11, BackgroundColor3 = C.Good, Visible = false, ZIndex = 6 }, panel)
	clickable(panel, function()
		if dailyChip.Visible then
			openPanel("Daily")
		else
			openPanel("Quests")
		end
	end)

	local function refresh()
		local data = QuestConfig.Read(player)
		local ids = data and data.Ids or {}
		local done, best = 0, nil
		for _, id in ids do
			local quest = QuestConfig.Get(id)
			if quest then
				local progress = (data.Progress or {})[id] or 0
				local claimed = (data.Claimed or {})[id] == true
				if claimed or progress >= quest.Goal then
					done += 1
				end
				-- erst abholbare, dann offene Aufträge zeigen
				local ready = progress >= quest.Goal and not claimed
				if not claimed and (best == nil or (ready and not best.Ready)) then
					best = { Quest = quest, Progress = math.min(progress, quest.Goal), Ready = ready }
				end
			end
		end
		count.Text = #ids > 0 and (done .. "/" .. #ids .. " ERLEDIGT") or ""
		if best then
			questText.Text = best.Quest.Text
			progressText.Text = best.Progress .. "/" .. best.Quest.Goal
			fill.Size = UDim2.fromScale(best.Progress / best.Quest.Goal, 1)
			fill.BackgroundColor3 = best.Ready and C.Good or C.Accent
			rewardText.Text = best.Ready and "Fertig – jetzt abholen!" or ("Belohnung: " .. best.Quest.Reward .. " Münzen")
		else
			questText.Text = #ids > 0 and "Alle Aufträge erledigt – morgen gibt es neue!" or "Aufträge werden geladen ..."
			progressText.Text = ""
			fill.Size = UDim2.fromScale(#ids > 0 and 1 or 0, 1)
			fill.BackgroundColor3 = C.Good
			rewardText.Text = ""
		end
		local dailyLeft = (player:GetAttribute("LastDaily") or 0) + Cosmetics.DailyCooldown - os.time()
		dailyChip.Visible = dailyLeft <= 0
		rewardText.Visible = not dailyChip.Visible
	end
	refresh()
	player.AttributeChanged:Connect(function(name)
		if name == "Quests" or name == "LastDaily" then
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			if isOpen then
				refresh()
			end
		end
	end)
end

-- SPIELEN-Knopf: Modus, Spielerzahl, Ping
function GameMenu.UpdatePlay()
	if not play or not selectedMode then
		return
	end
	local current = player:GetAttribute("Mode")
	local counts = liveCounts()
	local ping = math.floor((player:GetNetworkPing() or 0) * 1000 + 0.5)
	if not selectedMode.Available then
		play.SetText("BALD")
		play.SetColor(C.Card, C.Muted)
		playSub.Text = selectedMode.Name .. " KOMMT BALD"
		return
	end
	play.SetColor(C.Primary, C.PrimaryText)
	if not inHub and selectedMode.Id == current then
		play.SetText("WEITER")
		playSub.Text = selectedMode.Name .. " · ZURÜCK INS SPIEL"
	else
		play.SetText("SPIELEN")
		local n = 0
		if selectedMode == QUICK then
			for _, value in counts do
				n += tonumber(value) or 0
			end
		else
			n = counts[selectedMode.Id] or 0
		end
		playSub.Text = selectedMode.Name .. " · " .. n .. " SPIELEN · " .. ping .. " MS"
	end
	playSub.TextColor3 = C.PrimaryText
end

local function buildPlay()
	statusLabel = label({ Position = UDim2.fromOffset(RIGHT_X, 468), Size = UDim2.fromOffset(RIGHT_W, 60), Text = "", TextSize = 14,
		Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Bottom }, playPage)

	hubButton = UITheme.Chunky({ Position = UDim2.fromOffset(RIGHT_X, 544), Size = UDim2.fromOffset(RIGHT_W, 52), Color = C.Panel,
		StrokeColor = C.Border, Text = "ZURÜCK ZUM HUB", TextSize = 18 }, playPage, function()
		setStatus("Zurück zum Hub ...")
		Remotes.JoinMode:FireServer(Modes.Hub.Id)
	end)

	play = UITheme.Chunky({ Position = UDim2.fromOffset(RIGHT_X, 614), Size = UDim2.fromOffset(RIGHT_W, 150), Color = C.Primary,
		Text = "SPIELEN", TextSize = 64, TextColor = C.PrimaryText }, playPage, function()
		if not selectedMode.Available then
			setStatus(selectedMode.Name .. " kommt bald.")
		elseif not inHub and selectedMode.Id == player:GetAttribute("Mode") then
			GameMenu.SetOpen(false)
		else
			setStatus("Suche Server für " .. selectedMode.Name .. " ...")
			Remotes.JoinMode:FireServer(selectedMode.Id)
		end
	end)
	play.Label.Size = UDim2.new(1, 0, 0, 100)
	play.Label.Position = UDim2.fromOffset(0, 12)
	playSub = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.new(1, -24, 0, 20),
		Text = "", TextSize = 12, Font = F.Bold, TextColor3 = C.PrimaryText, TextXAlignment = Enum.TextXAlignment.Center }, play.Face)

	-- Steuerungs-Hinweise passend zum Gerät (Tastatur, Controller oder Touch)
	local hints = label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(1500, 18),
		Text = "", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, TextTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)
	local function updateHints()
		if InputActions.IsTouch() then
			hints.Text = "ALLE AKTIONEN ÜBER DIE KNÖPFE AM BILDSCHIRMRAND  ·  LINKS BEWEGEN, RECHTS WISCHEN ZUM UMSEHEN"
			return
		end
		local parts = {}
		for _, entry in { { "Fire", "Schießen" }, { "Aim", "Zielen" }, { "Ability", "Fähigkeit" }, { "Gadget", "Gadget" },
			{ "Reload", "Nachladen" }, { "Melee", "Messer" }, { "Crouch", "Ducken/Slide" }, { "Sprint", "Sprinten" },
			{ "Interact", "Aktion" }, { "Ping", "Ping" }, { "Camera", "Kamera" }, { "Scoreboard", "Punkte" }, { "Menu", "Menü" } } do
			local key = InputActions.Hint(entry[1])
			if key ~= "" then
				table.insert(parts, key .. " " .. upper(entry[2]))
			end
		end
		hints.Text = table.concat(parts, "  ·  ")
	end
	updateHints()
	InputActions.DeviceChanged:Connect(updateHints)
end

-- ---------- Seite AGENTEN ----------

local function buildAgentPage()
	agentPage = make("Frame", { Position = UDim2.fromOffset(410, 106), Size = UDim2.fromOffset(1150, 770), BackgroundTransparency = 1,
		Visible = false }, canvas)
	label({ Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(600, 22), Text = "AGENTEN  ·  KLICKEN ZUM WÄHLEN ODER FREISCHALTEN",
		TextSize = 15, Font = F.Display, TextColor3 = C.Muted }, agentPage)
	local grid = make("Frame", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), BackgroundTransparency = 1 },
		agentPage)
	-- 5 Spalten x 2 Reihen (bis 10 Agenten)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(218, 360), CellPadding = UDim2.fromOffset(14, 14),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, agent in AgentConfig.Agents do
		local card = make("TextButton", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.08, BorderSizePixel = 0, Text = "",
			AutoButtonColor = false, LayoutOrder = i }, grid)
		UITheme.Corner(card, UITheme.Radius.XL)
		local stroke = UITheme.Stroke(card, C.Border, 1)
		-- 3D-Figur oben
		local viewport = make("ViewportFrame", { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 168),
			BackgroundTransparency = 1, Ambient = Color3.fromRGB(135, 140, 158), LightColor = Color3.fromRGB(255, 245, 235),
			LightDirection = Vector3.new(-0.5, -1, 0.6) }, card)
		local camera = make("Camera", { FieldOfView = 34 }, viewport)
		camera.CFrame = AgentFigure.CameraCFrame
		viewport.CurrentCamera = camera
		local primary, accent = Cosmetics.AgentColors(player, agent.Id)
		local figure = AgentFigure.Build(agent, primary, accent, nil)
		figure:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, 0.35, 0))
		figure.Parent = viewport

		label({ Position = UDim2.fromOffset(14, 170), Size = UDim2.new(1, -74, 0, 32), Text = agent.Name, TextSize = 28,
			Font = F.Display }, card)
		local level = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 178), Size = UDim2.fromOffset(60, 20),
			Text = "", TextSize = 13, Font = F.Bold, TextColor3 = C.Primary, TextXAlignment = Enum.TextXAlignment.Right }, card)
		UITheme.Tag({ Position = UDim2.fromOffset(14, 204), Text = upper(agent.Role), TextSize = 11, BackgroundColor3 = C.Secondary,
			TextColor3 = C.Muted }, card)
		local barBack = make("Frame", { Position = UDim2.fromOffset(14, 234), Size = UDim2.new(1, -28, 0, 3), BackgroundColor3 = C.Background,
			BorderSizePixel = 0 }, card)
		local bar = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Primary, BorderSizePixel = 0 }, barBack)
		local weapons = {}
		for _, weapon in agent.Primaries or { agent.Loadout[1] } do
			table.insert(weapons, WeaponConfig.Get(weapon).DisplayName)
		end
		label({ Position = UDim2.fromOffset(14, 244), Size = UDim2.new(1, -28, 0, 16),
			Text = table.concat(weapons, " / ") .. " + " .. WeaponConfig.Get(agent.Loadout[2]).DisplayName, TextSize = 11,
			Font = F.Medium, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		label({ Position = UDim2.fromOffset(14, 262), Size = UDim2.new(1, -28, 0, 16), Text = "Q  " .. upper(agent.Ability.Name),
			TextSize = 12, Font = F.Bold, TextColor3 = C.Text, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		label({ Position = UDim2.fromOffset(14, 278), Size = UDim2.new(1, -28, 0, 16), Text = "G  " .. upper(agent.Gadget.Name),
			TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		local kills = label({ Position = UDim2.fromOffset(14, 294), Size = UDim2.new(1, -28, 0, 16), Text = "", TextSize = 11,
			Font = F.Bold, TextColor3 = C.Muted }, card)
		local badge = label({ Position = UDim2.fromOffset(14, 316), Size = UDim2.new(1, -28, 0, 34), Text = "", TextSize = 16,
			Font = F.Display, BackgroundTransparency = 0, BackgroundColor3 = C.Secondary, TextXAlignment = Enum.TextXAlignment.Center }, card)
		UITheme.Corner(badge, UITheme.Radius.Small)

		card.MouseEnter:Connect(function()
			card.BackgroundColor3 = C.Card
		end)
		card.MouseLeave:Connect(function()
			card.BackgroundColor3 = C.Panel
		end)
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
		local stats = decode(player:GetAttribute("Stats"))
		for agent, entry in agentCards do
			local isChosen = agent == chosen
			local unlocked = AgentConfig.IsUnlocked(player, agent.Id)
			entry.Stroke.Color = isChosen and C.Primary or C.Border
			entry.Stroke.Thickness = isChosen and 2 or 1
			entry.Badge.Text = not unlocked and ("FREISCHALTEN · " .. UITheme.FormatNumber(agent.Price))
				or (isChosen and "GEWÄHLT" or "WÄHLEN")
			entry.Badge.BackgroundColor3 = isChosen and C.Primary or (unlocked and C.Secondary or C.MutedBack)
			entry.Badge.TextColor3 = isChosen and C.PrimaryText or (unlocked and C.Text or C.Muted)
			local xp = AgentConfig.GetXP(player, agent.Id)
			entry.Level.Text = "LV " .. AgentConfig.LevelFromXP(xp)
			entry.Bar.Size = UDim2.fromScale(AgentConfig.LevelProgress(xp), 1)
			entry.Kills.Text = (stats["Kills_" .. agent.Id] or 0) .. " KILLS MIT " .. agent.Name
		end
	end
	refresh()
	player.AttributeChanged:Connect(refresh)
end

-- ---------- Öffnen / Schließen ----------

-- Menü öffnen/schließen. Solange offen: Maus frei, Hintergrund unscharf.
function GameMenu.SetOpen(open: boolean)
	if open == isOpen and gui.Enabled == open then
		return
	end
	isOpen = open
	gui.Enabled = open
	openButton.Button.Visible = inHub and not open
	UITheme.SetBlur("GameMenu", open)
	if not open then
		openPanel(nil) -- aus der Lobby geöffnete Fenster mit schließen
	end
	-- Controller: Auswahl auf den Spielen-Knopf setzen bzw. beim Schließen aufheben
	if open and InputActions.Device() == "Gamepad" then
		GuiService.SelectedObject = play.Button
	elseif not open and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
	if open then
		GameMenu.UpdatePlay()
		background.BackgroundTransparency = 1
		TweenService:Create(background, TweenInfo.new(0.2), { BackgroundTransparency = 0.3 }):Play()
		RunService:BindToRenderStep("GameMenuMouse", Enum.RenderPriority.Camera.Value + 1, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	else
		RunService:UnbindFromRenderStep("GameMenuMouse")
	end
end

-- tab: "Modes"/"Play" (Lobby), "Agents" oder ein Fenster des SideMenu ("Shop", "Inventory", "Pass" ...)
function GameMenu.Open(tab)
	GameMenu.SetOpen(true)
	if tab == "Agents" then
		openPanel(nil)
		showPage("Agents")
	elseif tab == nil or tab == "Modes" or tab == "Play" then
		openPanel(nil)
		showPage("Play")
	else
		showPage("Play")
		openPanel(tab)
	end
end

function GameMenu.IsOpen()
	return isOpen
end

-- Vom SideMenu: handler(name) öffnet dessen Fenster (nil = schließen)
function GameMenu.SetPanelHandler(handler)
	panelHandler = handler
end

-- Vom SideMenu: welches Fenster gerade offen ist (für die Hervorhebung in der Navigation)
function GameMenu.PanelChanged(name)
	openPanelName = name
	if next(navButtons) ~= nil then
		updateNav()
	end
end

function GameMenu.Init()
	gui = make("ScreenGui", { Name = "GameMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, player:WaitForChild("PlayerGui"))
	background = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.3, Active = true }, gui) -- Active: Klicks gehen nicht ins Spiel
	UITheme.Gradient(background, Color3.fromRGB(30, 33, 38), Color3.fromRGB(6, 7, 9))
	canvas = UITheme.Canvas(background, WIDTH, HEIGHT)

	playPage = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, canvas)
	buildHeader()
	buildModes()
	buildSquad()
	buildAgentStage()
	buildPass()
	buildDaily()
	buildPlay()
	buildAgentPage()
	selectMode(QUICK)
	showPage("Play")

	-- Ping im SPIELEN-Knopf alle 2 s aktualisieren
	task.spawn(function()
		while true do
			task.wait(2)
			if isOpen then
				GameMenu.UpdatePlay()
			end
		end
	end)

	-- Im Hub: großer Knopf unten mittig öffnet das Menü
	local openGui = make("ScreenGui", { Name = "PlayButton", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player.PlayerGui)
	openButton = UITheme.Chunky({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(300, 60), Color = C.Primary, Text = "SPIELEN", TextSize = 32, TextColor = C.PrimaryText,
		Visible = false }, openGui, function()
		GameMenu.SetOpen(true)
	end)

	-- Controller: ○ schließt das Menü
	UserInputService.InputBegan:Connect(function(input)
		if isOpen and input.KeyCode == Enum.KeyCode.ButtonB then
			GameMenu.SetOpen(false)
		end
	end)
	-- Spielen-Knopf zeigt die Taste des aktuellen Geräts
	local function updateOpenButton()
		local key = InputActions.Hint("Menu")
		openButton.SetText(key ~= "" and ("SPIELEN   [" .. key .. "]") or "SPIELEN")
	end
	updateOpenButton()
	InputActions.DeviceChanged:Connect(updateOpenButton)
	-- Menü-Taste (M bzw. Steuerkreuz unten): nur im Hub bzw. wenn das Menü offen ist
	InputActions.Bind("Menu", function(began)
		if began and (isOpen or not Modes.IsFighting(player)) then
			GameMenu.SetOpen(not isOpen)
		end
	end)

	-- Rückmeldung beim Freischalten von Agenten
	Remotes.ShopStatus.OnClientEvent:Connect(function(message)
		if isOpen and not openPanelName then
			setStatus(message)
		end
	end)
	-- Meldungen vom Server (Modus voll, kommt bald, ...) öffnen das Menü mit der Meldung
	Remotes.MenuStatus.OnClientEvent:Connect(function(message)
		GameMenu.SetOpen(true)
		showPage("Play")
		setStatus(message)
	end)

	-- Moduswechsel: Menü schließen (öffnet sich nicht von selbst), im Hub den SPIELEN-Knopf zeigen
	local function onModeChanged()
		local mode = player:GetAttribute("Mode")
		if mode == nil then
			return
		end
		inHub = mode == Modes.Hub.Id
		hubButton.Button.Visible = not inHub
		closeButton.SetText("✕")
		GameMenu.SetOpen(false)
		openButton.Button.Visible = inHub
		GameMenu.UpdatePlay()
	end
	player:GetAttributeChangedSignal("Mode"):Connect(onModeChanged)
	onModeChanged()
end

return GameMenu

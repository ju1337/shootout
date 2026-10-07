-- GameMenu (ModuleScript, nur Client)
-- Lobby im nüchternen Taktik-Look (UITheme):
--   oben:   Logo, Reiter SPIELEN · AGENTEN · LOADOUT · SHOP · BATTLE PASS (aktiv: weiß mit Bernstein-Strich),
--           rechts Münzen, Level, STATISTIK, CODES, OPTIONEN und Schließen
--   links:  Spielmodi (aktiver Modus heller mit Bernstein-Balken links) und der Squad (bis 4, Anführer mit
--           Stern, Level, BEREIT/NICHT BEREIT – den eigenen Status schaltet man per Klick, freie Plätze laden ein)
--   Mitte:  der gewählte Agent groß in 3D mit Rollen-Schild und Namen
--   rechts: Battle Pass (Stufe, Fortschritt, nächste Belohnung), täglicher Auftrag, großer SPIELEN-Knopf
--           mit Modus, Spielerzahl und Ping
-- Jeder Reiter ist eine eigene Seite unter der Kopfzeile (Modi und Squad gehören nur zu SPIELEN):
--   AGENTEN:     links eine Detailkarte (überfahrener bzw. angeklickter Agent: Rolle, Werte, Standardwaffe – eine
--                der zwei Primärwaffen ausrüsten –, Fähigkeit, Gadget, Passiv, Level, WÄHLEN/FREISCHALTEN),
--                rechts alle Agenten als Karten (ausgerüstete Primärwaffe hell)
--   LOADOUT, SHOP, BATTLE PASS: Seiten aus LobbyPages (direkt in der Lobby, kein eigenes Fenster)
--   STATISTIK, CODES, OPTIONEN (oben rechts): ebenfalls Seiten; den Inhalt baut das SideMenu (GameMenu.AddPage)
-- Aufträge, tägliche Belohnung, Belohnungen, Titel und Squad öffnen weiter die Fenster des SideMenu
-- über der Lobby (GameMenu.SetPanelHandler). Öffnen/Schließen mit M oder dem SPIELEN-Knopf im Hub; es öffnet
-- sich NICHT von selbst. Alles liegt auf einer zentrierten Leinwand (UITheme.Canvas) und skaliert mit.

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
local LobbyPages = require(Shared.LobbyPages)
local HUDIcons = require(Shared.HUDIcons)

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

-- Schnelles Spiel: der Server wählt den vollsten Arcade-Modus mit freiem Platz
local QUICK = { Id = "Quick", Name = "SCHNELLES SPIEL", Tag = "Arcade-Modus mit freiem Platz", Available = true }

-- Navigation: Seite in der Lobby oder Fenster des SideMenu
local NAV = {
	{ Id = "Play", Text = "SPIELEN" },
	{ Id = "Agents", Text = "AGENTEN" },
	{ Id = "Inventory", Text = "LOADOUT" },
	{ Id = "Shop", Text = "SHOP" },
	{ Id = "Pass", Text = "BATTLE PASS" },
}

local gui, background, canvas, statusLabel, pageStatus, openButton, hubButton, closeButton
local play -- großer SPIELEN-Knopf (Chunky) mit Unterzeile
local playSub
local playPage, agentPage
local pages = {}        -- [Id] = { Frame, Refresh, Watch, Build } (Build: baut die Seite beim ersten Anzeigen)
local navButtons = {}   -- [Id] = TextButton
local borrowed = {}     -- [Id] = true: Seite steckt gerade im Menü der offenen Welt (GameMenu.BorrowPage)
local headerPages = {}  -- [Id] = Chunky (STATISTIK, CODES, OPTIONEN oben rechts: Seiten, keine Fenster)
local modeButtons = {}  -- [mode] = { Chunky, Detail, Check, Live }
local agentCards = {}   -- [agent] = { ... }
local selectedMode
local currentPage = "Play"
local isOpen = false
local inHub = false
local panelHandler = nil -- function(name): Fenster des SideMenu öffnen (nil = schließen)
local openPanelName = nil

-- Rückmeldung: auf SPIELEN rechts über dem Knopf, auf den anderen Seiten in der Zeile unten
local function setStatus(message, color)
	for _, target in { statusLabel, pageStatus } do
		if target then
			target.Text = message or ""
			target.TextColor3 = color or C.Muted
		end
	end
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
	for id, chunky in headerPages do
		local on = id == active
		chunky.Stroke.Color = on and C.Primary or C.Border
		chunky.Stroke.Transparency = on and 0 or 0.4
	end
end

local function showPage(name)
	if not pages[name] then
		name = "Play"
	end
	currentPage = name
	local entry = pages[name]
	if entry.Build then
		local built = entry.Build(entry.Frame)
		entry.Build = nil
		entry.Refresh, entry.Watch = built.Refresh, built.Watch
	end
	for id, page in pages do
		if not borrowed[id] then
			page.Frame.Visible = id == name
		end
	end
	pageStatus.Visible = name ~= "Play"
	updateNav()
	setStatus("")
	if entry.Refresh then
		entry.Refresh()
	end
	-- Controller: Auswahl in die neue Seite setzen (Spielen-Seite: auf den SPIELEN-Knopf)
	if isOpen and not openPanelName then
		InputActions.Focus(entry.Frame, name == "Play" and play and play.Button or nil)
	end
end

-- Controller: L1/R1 blättert durch die Seiten der Lobby
local function cyclePage(step)
	local index = 1
	for i, entry in NAV do
		if entry.Id == currentPage then
			index = i
		end
	end
	index = (index - 1 + step) % #NAV + 1
	openPanel(nil)
	showPage(NAV[index].Id)
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
			openPanel(nil)
			showPage(entry.Id)
		end)
		navButtons[entry.Id] = button
	end
	-- Controller: L1/R1-Hinweise links und rechts der Reiter (nur mit Controller sichtbar)
	local padHints = {}
	for _, hint in { { Text = "L1", Order = 0 }, { Text = "R1", Order = #NAV + 1 } } do
		local tag = UITheme.Tag({ Text = hint.Text, TextSize = 13, LayoutOrder = hint.Order, BackgroundColor3 = C.Secondary,
			TextColor3 = C.Text }, nav)
		table.insert(padHints, tag)
	end
	local function updatePadHints()
		for _, tag in padHints do
			tag.Visible = InputActions.Device() == "Gamepad"
		end
	end
	updatePadHints()
	InputActions.DeviceChanged:Connect(updatePadHints)

	-- Rechts: Münzen, Level, Statistik, Codes, Optionen, Schließen
	local right = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -LEFT_X, 0, 30),
		Size = UDim2.fromOffset(720, 50), BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, right)

	local coins = pill(122, 1, right)
	UITheme.Coin(coins, 14, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0) })
	local coinText = label({ Position = UDim2.fromOffset(36, 2), Size = UDim2.new(1, -48, 0, 40), Text = "", TextSize = 22,
		Font = F.Display, TextXAlignment = Enum.TextXAlignment.Right }, coins)
	-- RAP (zweite Währung): Guthaben, mintgrün
	local rap = pill(122, 1, right)
	UITheme.RapIcon(rap, 18, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 11, 0.5, 0) })
	local rapText = label({ Position = UDim2.fromOffset(36, 2), Size = UDim2.new(1, -48, 0, 40), Text = "", TextSize = 22,
		Font = F.Display, TextColor3 = C.Rap, TextXAlignment = Enum.TextXAlignment.Right }, rap)

	local level = pill(104, 2, right)
	local levelTag = UITheme.Tag({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Text = "LV", TextSize = 11,
		BackgroundColor3 = C.Secondary, TextColor3 = C.Muted }, level)
	local levelText = label({ Position = UDim2.fromOffset(46, 2), Size = UDim2.new(1, -58, 0, 40), Text = "", TextSize = 22,
		Font = F.Display, TextXAlignment = Enum.TextXAlignment.Right }, level)

	-- Statistik, Codes, Optionen sind Seiten der Lobby (Inhalt baut das SideMenu über GameMenu.AddPage)
	for i, entry in { { "Stats", "STATISTIK", 92 }, { "Codes", "CODES", 72 }, { "Settings", "OPTIONEN", 90 } } do
		headerPages[entry[1]] = headerButton(entry[2], entry[3], 2 + i, right, function()
			openPanel(nil)
			showPage(entry[1])
		end)
	end
	closeButton = headerButton("", 44, 6, right, function()
		GameMenu.SetOpen(false)
	end)
	UITheme.Cross(closeButton.Face, 14, C.Text, 2)

	local function update()
		coinText.Text = UITheme.FormatNumber(player:GetAttribute("Coins") or 0)
		rapText.Text = UITheme.FormatNumber(player:GetAttribute("Rap") or 0)
		local info = LevelConfig.Get(player)
		levelText.Text = (info.Prestige > 0 and ("P" .. info.Prestige .. " · ") or "") .. tostring(info.Level)
		levelText.TextColor3 = info.Prestige > 0 and info.Color or C.Text
		levelTag.TextColor3 = info.Prestige > 0 and info.Color or C.Muted
	end
	update()
	player.AttributeChanged:Connect(function(name)
		if name == "Coins" or name == "Rap" or name == "AccountXP" or name == "Prestige" then
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

-- Spieler in einem Eintrag der Liste: Schnelles Spiel zählt alle Arcade-Modi zusammen
local function modeCount(counts, mode)
	if mode == QUICK then
		local n = 0
		for _, arcade in Modes.Arcade() do
			n += tonumber(counts[arcade.Id]) or 0
		end
		return n
	end
	return tonumber(counts[mode.Id]) or 0
end

-- Links: oben groß der Hauptmodus (EXTINCTION, offene Welt), darunter ARCADE mit den Minispielen
local function buildModes()
	label({ Position = UDim2.fromOffset(LEFT_X, 106), Size = UDim2.fromOffset(LEFT_W, 22), Text = "SPIELMODUS", TextSize = 12,
		Font = F.Bold, TextColor3 = C.Muted }, playPage)

	local function addEntry(mode, parent, size, order, big)
		local chunky = UITheme.Chunky({ Size = size, LayoutOrder = order, Color = C.Panel, Text = "",
			StrokeColor = C.Border }, parent, function()
			selectMode(mode)
		end)
		local face = chunky.Face
		face.BackgroundTransparency = 0.12
		local name = label({ Position = UDim2.fromOffset(18, big and 14 or 5), Size = UDim2.new(1, -100, 0, big and 36 or 22),
			Text = mode.Name, TextSize = big and 34 or 19, Font = F.Display }, face)
		local detail = label({ Position = UDim2.fromOffset(18, big and 52 or 28), Size = UDim2.new(1, -100, 0, big and 16 or 14),
			Text = upper(mode.Tag or ""), TextSize = big and 12 or 10, Font = F.Bold, TextColor3 = C.Muted }, face)
		if big then
			-- Hauptmodus: Streifen in der Modusfarbe und kurze Zeile, worum es geht
			UITheme.AccentBar(face, mode.Color or C.Primary, { Side = "Right", Thickness = 6 })
			label({ Position = UDim2.fromOffset(18, 70), Size = UDim2.new(1, -40, 0, 16), Text = "SAFE ZONE · ZOMBIES · PVP · FAHRZEUGE",
				TextSize = 10, Font = F.Bold, TextColor3 = mode.Color or C.Primary }, face)
		end
		-- aktiv: Bernstein-Balken am linken Rand
		local check = UITheme.AccentBar(face, C.Primary, { Side = "Left", Visible = false })
		local live = label({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(80, 20),
			Text = "", TextSize = 12, Font = F.Bold, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Right }, face)
		if not mode.Available then
			name.TextTransparency = 0.5
			detail.Text = "BALD VERFÜGBAR"
		end
		modeButtons[mode] = { Chunky = chunky, Detail = detail, Check = check, Live = live, Name = name }
	end

	local featured = Modes.Featured()
	local top = 134
	if featured then
		local holder = make("Frame", { Position = UDim2.fromOffset(LEFT_X, top), Size = UDim2.fromOffset(LEFT_W, 96),
			BackgroundTransparency = 1 }, playPage)
		addEntry(featured, holder, UDim2.fromOffset(LEFT_W, 96), 1, true)
		top += 106
	end
	label({ Position = UDim2.fromOffset(LEFT_X, top), Size = UDim2.fromOffset(LEFT_W, 20), Text = "ARCADE", TextSize = 12,
		Font = F.Bold, TextColor3 = C.Muted }, playPage)
	local list = make("Frame", { Position = UDim2.fromOffset(LEFT_X, top + 24), Size = UDim2.fromOffset(LEFT_W, 584 - top - 24),
		BackgroundTransparency = 1 }, playPage)
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local entries = { QUICK }
	for _, mode in Modes.Arcade() do
		table.insert(entries, mode)
	end
	for i, mode in entries do
		addEntry(mode, list, UDim2.fromOffset(LEFT_W, 47), i, false)
	end

	local function updateCounts()
		local counts = liveCounts()
		for mode, entry in modeButtons do
			local n = modeCount(counts, mode)
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
		playPage)
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
		Size = UDim2.fromOffset(240, 24), BackgroundTransparency = 1, Text = "AGENT WECHSELN", Font = F.Bold, TextSize = 12,
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
			local agentSkin = Cosmetics.AgentSkin(player, agent.Id)
			figure = AgentFigure.Build(agent, primary, accent, Cosmetics.WeaponSkin(player, agent.Id, weapon), weapon,
				agentSkin and agentSkin.Id)
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
		showPage("Pass")
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

-- Unterzeile des SPIELEN-Knopfs im Hub: gewählter Modus und wie viele ihn gerade spielen
local function updateHubPlay()
	if not openButton or not selectedMode then
		return
	end
	if not selectedMode.Available then
		openButton.SetSub(selectedMode.Name .. " KOMMT BALD")
		return
	end
	local n = modeCount(liveCounts(), selectedMode)
	openButton.SetSub(n > 0 and (selectedMode.Name .. "  ·  " .. n .. (n == 1 and " SPIELT" or " SPIELEN")) or selectedMode.Name)
end

-- SPIELEN-Knopf: Modus, Spielerzahl, Ping
function GameMenu.UpdatePlay()
	updateHubPlay()
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
		local n = modeCount(counts, selectedMode)
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

-- Agent wählen bzw. (gesperrt) mit Münzen freischalten
local function activateAgent(agent)
	if not AgentConfig.IsUnlocked(player, agent.Id) then
		Remotes.ShopAction:FireServer("UnlockAgent", agent.Id)
		return
	end
	Remotes.SelectAgent:FireServer(agent.Id)
	setStatus(agent.Name .. " gewählt – aktiv ab dem nächsten Spawn.")
end

local function buildAgentPage()
	agentPage = make("Frame", { Name = "AgentsPage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false },
		canvas)
	local hovered, pinned = nil, nil -- überfahrener Agent (Vorschau) und zuletzt angeklickter

	-- ----- Detailkarte links -----
	local detail = UITheme.Card({ Name = "AgentDetail", Position = UDim2.fromOffset(LEFT_X, 106), Size = UDim2.fromOffset(LEFT_W, 730) },
		agentPage)
	local function text(props)
		props.ZIndex = 3
		return label(props, detail)
	end
	local role = UITheme.Tag({ Position = UDim2.fromOffset(20, 20), Text = "", TextSize = 11, BackgroundColor3 = C.Secondary,
		TextColor3 = C.Primary, ZIndex = 3 }, detail)
	local name = text({ Position = UDim2.fromOffset(20, 46), Size = UDim2.new(1, -40, 0, 58), Text = "", TextSize = 60, Font = F.Display })
	local description = text({ Position = UDim2.fromOffset(20, 108), Size = UDim2.new(1, -40, 0, 36), Text = "", TextSize = 13,
		Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })

	text({ Position = UDim2.fromOffset(20, 152), Size = UDim2.fromOffset(300, 16), Text = "WERTE", TextSize = 12, Font = F.Bold,
		TextColor3 = C.Muted })
	local statRows = {}
	for i, entry in { { "Health", "LEBEN" }, { "Speed", "TEMPO" }, { "Utility", "FÄHIGKEIT" } } do
		local y = 172 + (i - 1) * 22
		text({ Position = UDim2.fromOffset(20, y), Size = UDim2.fromOffset(90, 16), Text = entry[2], TextSize = 11, Font = F.Bold })
		local segments = {}
		for s = 1, 10 do
			segments[s] = make("Frame", { Position = UDim2.fromOffset(112 + (s - 1) * 15, y + 5), Size = UDim2.fromOffset(13, 6),
				BackgroundColor3 = C.Background, BorderSizePixel = 0, ZIndex = 3 }, detail)
		end
		local value = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, y), Size = UDim2.fromOffset(50, 16),
			Text = "", TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right })
		statRows[entry[1]] = { Segments = segments, Value = value }
	end

	-- Standardwaffe: eine der zwei Primärwaffen ausrüsten (gilt bei jedem Spawn mit dem Agenten, im Hub auf dem Rücken)
	local shownAgent = nil -- Agent, den die Detailkarte gerade zeigt
	text({ Position = UDim2.fromOffset(20, 246), Size = UDim2.fromOffset(150, 16), Text = "STANDARDWAFFE", TextSize = 12,
		Font = F.Bold, TextColor3 = C.Muted })
	local secondaryText = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 246), Size = UDim2.fromOffset(160, 16),
		Text = "", TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right })
	local weaponCards = {}
	for i = 1, 2 do
		local button = make("TextButton", { Name = "Weapon" .. i, Position = UDim2.fromOffset(20 + (i - 1) * 154, 268),
			Size = UDim2.fromOffset(146, 82), BackgroundColor3 = C.Background, BorderSizePixel = 0, Text = "", AutoButtonColor = false,
			ZIndex = 3 }, detail)
		UITheme.Corner(button, UITheme.Radius.Small)
		local stroke = UITheme.Stroke(button, C.Border, 1)
		local holder = make("Frame", { Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(130, 42), BackgroundTransparency = 1,
			ZIndex = 3 }, button)
		local weaponName = label({ Position = UDim2.fromOffset(10, 46), Size = UDim2.new(1, -20, 0, 18), Text = "", TextSize = 16,
			Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 }, button)
		local tag = label({ Position = UDim2.fromOffset(10, 64), Size = UDim2.new(1, -20, 0, 12), Text = "", TextSize = 10,
			Font = F.Bold, TextColor3 = C.Muted, ZIndex = 4 }, button)
		local card = { Button = button, Stroke = stroke, Holder = holder, Name = weaponName, Tag = tag, Weapon = nil, Shown = nil }
		button.MouseEnter:Connect(function()
			button.BackgroundColor3 = C.CardHover
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = C.Background
		end)
		button.Activated:Connect(function()
			local agent = shownAgent or currentAgent()
			if card.Weapon and card.Weapon ~= AgentConfig.LoadoutFor(player, agent.Id)[1] then
				Remotes.ShopAction:FireServer("SelectPrimary", agent.Id, card.Weapon)
			end
		end)
		weaponCards[i] = card
	end

	text({ Position = UDim2.fromOffset(20, 364), Size = UDim2.fromOffset(300, 16), Text = "FÄHIGKEITEN", TextSize = 12, Font = F.Bold,
		TextColor3 = C.Muted })
	local abilityRows = {}
	for i = 1, 3 do
		local y = 386 + (i - 1) * 56
		local key = text({ Position = UDim2.fromOffset(20, y), Size = UDim2.fromOffset(30, 30), Text = "", TextSize = 13, Font = F.Bold,
			TextColor3 = C.Primary, BackgroundTransparency = 0, BackgroundColor3 = C.Background,
			TextXAlignment = Enum.TextXAlignment.Center })
		UITheme.Corner(key, UITheme.Radius.Small)
		UITheme.Stroke(key, C.Primary, 1)
		local diamond = UITheme.Diamond(key, 10, UDim2.fromScale(0.5, 0.5), C.Primary) -- Passiv (Oswald hat kein "◆")
		diamond.ZIndex = 4
		local rowName = text({ Position = UDim2.fromOffset(62, y - 1), Size = UDim2.new(1, -82, 0, 18), Text = "", TextSize = 13,
			RichText = true, TextTruncate = Enum.TextTruncate.AtEnd })
		local rowText = text({ Position = UDim2.fromOffset(62, y + 18), Size = UDim2.new(1, -82, 0, 36), Text = "", TextSize = 11,
			Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		abilityRows[i] = { Key = key, Diamond = diamond, Name = rowName, Text = rowText }
	end

	text({ Position = UDim2.fromOffset(20, 556), Size = UDim2.fromOffset(300, 16), Text = "AGENTEN-LEVEL", TextSize = 12, Font = F.Bold,
		TextColor3 = C.Muted })
	local levelText = text({ Position = UDim2.fromOffset(20, 574), Size = UDim2.fromOffset(160, 28), Text = "", TextSize = 28,
		Font = F.Display })
	local xpText = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 584), Size = UDim2.fromOffset(180, 16),
		Text = "", TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right })
	local levelBack = make("Frame", { Position = UDim2.fromOffset(20, 608), Size = UDim2.new(1, -40, 0, 4), BackgroundColor3 = C.Background,
		BorderSizePixel = 0, ZIndex = 3 }, detail)
	local levelBar = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Primary, BorderSizePixel = 0, ZIndex = 3 },
		levelBack)
	local killsText = text({ Position = UDim2.fromOffset(20, 620), Size = UDim2.new(1, -40, 0, 16), Text = "", TextSize = 11,
		Font = F.Bold, TextColor3 = C.Muted })

	local action = UITheme.Chunky({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -20), Size = UDim2.new(1, -40, 0, 52),
		Color = C.Primary, Text = "", TextSize = 24, TextColor = C.PrimaryText, ZIndex = 3 }, detail, function()
		local agent = pinned or currentAgent()
		if agent ~= currentAgent() or not AgentConfig.IsUnlocked(player, agent.Id) then
			activateAgent(agent)
		end
	end)

	local function showWeapons(agent)
		local chosen = AgentConfig.LoadoutFor(player, agent.Id)[1]
		for i, card in weaponCards do
			local weapon = (agent.Primaries or { agent.Loadout[1] })[i]
			card.Weapon = weapon
			card.Button.Visible = weapon ~= nil
			if weapon then
				local skin = Cosmetics.WeaponSkin(player, agent.Id, weapon)
				local key = weapon .. "|" .. tostring(skin and skin.Name)
				if key ~= card.Shown then
					card.Shown = key
					local old = card.Holder:FindFirstChildWhichIsA("ViewportFrame")
					if old then
						old:Destroy()
					end
					local preview = HUDIcons.WeaponModel(card.Holder, weapon, 130, 42, skin)
					if preview then
						preview.ZIndex = 3
					end
				end
				local equipped = weapon == chosen
				card.Name.Text = upper(WeaponConfig.Get(weapon).DisplayName)
				card.Tag.Text = equipped and "AUSGERÜSTET" or "AUSRÜSTEN"
				card.Tag.TextColor3 = equipped and C.Primary or C.Muted
				card.Stroke.Color = equipped and C.Primary or C.Border
				card.Stroke.Thickness = equipped and 2 or 1
			end
		end
		secondaryText.Text = "+ " .. upper(WeaponConfig.Get(agent.Loadout[2]).DisplayName)
	end

	local function showDetail()
		local agent = hovered or pinned or currentAgent()
		shownAgent = agent
		showWeapons(agent)
		local stats = decode(player:GetAttribute("Stats"))
		role.Text = upper(agent.Role)
		name.Text = agent.Name
		description.Text = agent.Description or ""
		for stat, row in statRows do
			local value = AgentConfig.StatValue(stat, agent)
			for i, segment in row.Segments do
				segment.BackgroundColor3 = i <= value and C.Primary or C.Background
			end
			row.Value.Text = stat == "Health" and tostring(agent.Health) or stat == "Speed" and tostring(agent.WalkSpeed)
				or (agent.Ability.Cooldown .. " s")
		end
		local rows = {
			{ AgentConfig.AbilityKey.Name, agent.Ability.Name, agent.Ability.Cooldown .. " s", agent.Ability.Description or "" },
			{ AgentConfig.GadgetKey.Name, agent.Gadget.Name, (agent.Gadget.Charges or 1) .. "×", AgentConfig.GadgetDescription(agent.Gadget) },
			{ "", agent.Passive and agent.Passive.Name or "–", "PASSIV", agent.Passive and agent.Passive.Description or "" },
		}
		for i, row in rows do
			local entry = abilityRows[i]
			entry.Key.Text = row[1]
			entry.Diamond.Visible = row[1] == ""
			entry.Name.Text = string.format('%s  <font color="#%s">· %s</font>', upper(row[2]), C.Muted:ToHex(), row[3])
			entry.Text.Text = row[4]
		end
		local xp = AgentConfig.GetXP(player, agent.Id)
		local level = AgentConfig.LevelFromXP(xp)
		levelText.Text = "LEVEL " .. level
		levelBar.Size = UDim2.fromScale(AgentConfig.LevelProgress(xp), 1)
		xpText.Text = level >= AgentConfig.MaxLevel and "MAX-LEVEL"
			or (UITheme.FormatNumber(AgentConfig.LevelProgress(xp) * AgentConfig.XPPerLevel) .. " / "
				.. UITheme.FormatNumber(AgentConfig.XPPerLevel) .. " XP")
		killsText.Text = (stats["Kills_" .. agent.Id] or 0) .. " KILLS MIT " .. agent.Name

		-- Knopf für den angezeigten Agenten
		local unlocked = AgentConfig.IsUnlocked(player, agent.Id)
		if not unlocked then
			local affordable = (player:GetAttribute("Coins") or 0) >= (agent.Price or 0)
			action.SetText("FREISCHALTEN  ·  " .. UITheme.FormatNumber(agent.Price or 0))
			action.SetColor(affordable and C.Primary or C.MutedBack, affordable and C.PrimaryText or C.Bad)
		elseif agent == currentAgent() then
			action.SetText("GEWÄHLT")
			action.SetColor(C.MutedBack, C.Muted)
		else
			action.SetText("WÄHLEN")
			action.SetColor(C.Primary, C.PrimaryText)
		end
	end

	-- ----- Karten rechts -----
	label({ Position = UDim2.fromOffset(410, 106), Size = UDim2.fromOffset(800, 22),
		Text = "AGENTEN  ·  KLICKEN ZUM WÄHLEN, GESPERRTE LINKS FREISCHALTEN", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted },
		agentPage)
	local grid = make("Frame", { Position = UDim2.fromOffset(410, 134), Size = UDim2.fromOffset(1150, 702), BackgroundTransparency = 1 },
		agentPage)
	-- 5 Spalten x 2 Reihen (bis 10 Agenten)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(218, 344), CellPadding = UDim2.fromOffset(14, 14),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)

	local refresh -- vorab (Karten-Ereignisse rufen es auf)
	for i, agent in AgentConfig.Agents do
		local card = make("TextButton", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.08, BorderSizePixel = 0, Text = "",
			AutoButtonColor = false, LayoutOrder = i }, grid)
		UITheme.Corner(card, UITheme.Radius.XL)
		local stroke = UITheme.Stroke(card, C.Border, 1)
		-- 3D-Figur oben
		local viewport = make("ViewportFrame", { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 156),
			BackgroundTransparency = 1, Ambient = Color3.fromRGB(135, 140, 158), LightColor = Color3.fromRGB(255, 245, 235),
			LightDirection = Vector3.new(-0.5, -1, 0.6) }, card)
		local camera = make("Camera", { FieldOfView = 34 }, viewport)
		camera.CFrame = AgentFigure.CameraCFrame
		viewport.CurrentCamera = camera
		local primary, accent = Cosmetics.AgentColors(player, agent.Id)
		local agentSkin = Cosmetics.AgentSkin(player, agent.Id)
		local figure = AgentFigure.Build(agent, primary, accent, nil, nil, agentSkin and agentSkin.Id)
		figure:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, 0.35, 0))
		figure.Parent = viewport

		label({ Position = UDim2.fromOffset(14, 160), Size = UDim2.new(1, -74, 0, 32), Text = agent.Name, TextSize = 28,
			Font = F.Display }, card)
		local level = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 168), Size = UDim2.fromOffset(60, 20),
			Text = "", TextSize = 13, Font = F.Bold, TextColor3 = C.Primary, TextXAlignment = Enum.TextXAlignment.Right }, card)
		UITheme.Tag({ Position = UDim2.fromOffset(14, 194), Text = upper(agent.Role), TextSize = 11, BackgroundColor3 = C.Secondary,
			TextColor3 = C.Muted }, card)
		local barBack = make("Frame", { Position = UDim2.fromOffset(14, 224), Size = UDim2.new(1, -28, 0, 3), BackgroundColor3 = C.Background,
			BorderSizePixel = 0 }, card)
		local bar = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Primary, BorderSizePixel = 0 }, barBack)
		local weaponLine = label({ Position = UDim2.fromOffset(14, 234), Size = UDim2.new(1, -28, 0, 16), Text = "", TextSize = 11,
			Font = F.Medium, TextColor3 = C.Muted, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		label({ Position = UDim2.fromOffset(14, 252), Size = UDim2.new(1, -28, 0, 16), Text = "Q  " .. upper(agent.Ability.Name),
			TextSize = 12, Font = F.Bold, TextColor3 = C.Text, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		label({ Position = UDim2.fromOffset(14, 268), Size = UDim2.new(1, -28, 0, 16), Text = "G  " .. upper(agent.Gadget.Name),
			TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		local badge = label({ Position = UDim2.fromOffset(14, 296), Size = UDim2.new(1, -28, 0, 34), Text = "", TextSize = 16,
			Font = F.Display, BackgroundTransparency = 0, BackgroundColor3 = C.Secondary, TextXAlignment = Enum.TextXAlignment.Center }, card)
		UITheme.Corner(badge, UITheme.Radius.Small)

		-- Überfahren: Vorschau links; Klick: links festhalten und (wenn frei) wählen – Freischalten nur über den Knopf links
		card.MouseEnter:Connect(function()
			card.BackgroundColor3 = C.Card
			hovered = agent
			showDetail()
		end)
		card.MouseLeave:Connect(function()
			card.BackgroundColor3 = C.Panel
			if hovered == agent then
				hovered = nil
				showDetail()
			end
		end)
		card.Activated:Connect(function()
			pinned = agent
			if AgentConfig.IsUnlocked(player, agent.Id) then
				activateAgent(agent)
			else
				setStatus(agent.Name .. " ist gesperrt – links mit Münzen freischalten.")
			end
			refresh()
		end)
		agentCards[agent] = { Card = card, Stroke = stroke, Badge = badge, Level = level, Bar = bar, Weapons = weaponLine }
	end

	refresh = function()
		local chosen = currentAgent()
		for agent, entry in agentCards do
			local isChosen = agent == chosen
			local unlocked = AgentConfig.IsUnlocked(player, agent.Id)
			entry.Stroke.Color = isChosen and C.Primary or (agent == pinned and C.Text or C.Border)
			entry.Stroke.Thickness = isChosen and 2 or 1
			entry.Stroke.Transparency = (not isChosen and agent == pinned) and 0.4 or 0
			entry.Badge.Text = not unlocked and ("GESPERRT  ·  " .. UITheme.FormatNumber(agent.Price))
				or (isChosen and "GEWÄHLT" or "WÄHLEN")
			entry.Badge.BackgroundColor3 = isChosen and C.Primary or (unlocked and C.Secondary or C.MutedBack)
			entry.Badge.TextColor3 = isChosen and C.PrimaryText or (unlocked and C.Text or C.Muted)
			local xp = AgentConfig.GetXP(player, agent.Id)
			entry.Level.Text = "LV " .. AgentConfig.LevelFromXP(xp)
			entry.Bar.Size = UDim2.fromScale(AgentConfig.LevelProgress(xp), 1)
			-- Waffen: ausgerüstete Primärwaffe hell, die andere und die Sekundärwaffe gedämpft
			local chosenWeapon = AgentConfig.LoadoutFor(player, agent.Id)[1]
			local names = {}
			for _, weapon in agent.Primaries or { agent.Loadout[1] } do
				local weaponName = WeaponConfig.Get(weapon).DisplayName
				table.insert(names, weapon == chosenWeapon
					and string.format('<font color="#%s">%s</font>', C.Text:ToHex(), weaponName) or weaponName)
			end
			entry.Weapons.Text = table.concat(names, " / ") .. " + " .. WeaponConfig.Get(agent.Loadout[2]).DisplayName
		end
		showDetail()
	end
	refresh()
	player.AttributeChanged:Connect(refresh)
	pages.Agents = { Frame = agentPage, Refresh = function()
		hovered = nil
		refresh()
	end }
end

-- ---------- Seiten LOADOUT, SHOP, BATTLE PASS (LobbyPages, beim ersten Anzeigen gebaut) ----------

local function buildLobbyPages()
	local builders = {
		Inventory = function(frame)
			return LobbyPages.Loadout(frame, function()
				showPage("Shop")
			end)
		end,
		Shop = LobbyPages.Shop,
		Pass = LobbyPages.Pass,
	}
	for id, build in builders do
		local frame = make("Frame", { Name = id .. "Page", Position = UDim2.fromOffset(LEFT_X, 106),
			Size = UDim2.fromOffset(LobbyPages.PAGE_W, LobbyPages.PAGE_H), BackgroundTransparency = 1, Visible = false }, canvas)
		pages[id] = { Frame = frame, Build = build }
	end
	-- Besitz, Münzen, Ausrüstung, Pass-XP geändert: sichtbare (oder ausgeliehene) Seite aktualisieren
	player.AttributeChanged:Connect(function(attribute)
		for id, entry in pages do
			local shown = borrowed[id] or (isOpen and id == currentPage)
			if shown and entry.Watch and entry.Watch[attribute] and entry.Refresh then
				entry.Refresh()
			end
		end
	end)
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

-- tab: Seite der Lobby ("Play"/"Modes", "Agents", "Inventory", "Shop", "Pass") oder ein Fenster des SideMenu
-- ("Quests", "Daily", "Squad", "Rewards", "Titles"); "Stats", "Codes", "Settings" sind Seiten
function GameMenu.Open(tab)
	GameMenu.SetOpen(true)
	if tab == nil or tab == "Modes" then
		tab = "Play"
	end
	if pages[tab] then
		openPanel(nil)
		showPage(tab)
	else
		showPage("Play")
		openPanel(tab)
	end
end

function GameMenu.IsOpen()
	return isOpen
end

-- Weitere Lobby-Seite von außen (SideMenu: Statistik, Codes, Optionen). Gibt den Eintrag { Frame } zurück;
-- Refresh (beim Anzeigen) und Watch (Attribute, bei denen neu gezeichnet wird) setzt der Aufrufer.
function GameMenu.AddPage(id)
	local frame = make("Frame", { Name = id .. "Page", Position = UDim2.fromOffset(LEFT_X, 106),
		Size = UDim2.fromOffset(LobbyPages.PAGE_W, LobbyPages.PAGE_H), BackgroundTransparency = 1, Visible = false }, canvas)
	pages[id] = { Frame = frame }
	return pages[id]
end

-- Seite der Lobby ausleihen (Menü der offenen Welt): baut sie beim ersten Mal, hängt ihren Rahmen (PAGE_W x PAGE_H)
-- links oben an parent, zeigt und aktualisiert sie. Gibt den Rahmen zurück (nil, wenn es die Seite nicht gibt).
-- ReturnPage(id) hängt sie wieder in die Lobby.
function GameMenu.BorrowPage(id, parent)
	local entry = pages[id]
	if not entry or id == "Play" then
		return nil
	end
	if entry.Build then
		local built = entry.Build(entry.Frame)
		entry.Build = nil
		entry.Refresh, entry.Watch = built.Refresh, built.Watch
	end
	borrowed[id] = true
	entry.Frame.Parent = parent
	entry.Frame.Position = UDim2.fromOffset(0, 0)
	entry.Frame.Visible = true
	if entry.Refresh then
		entry.Refresh()
	end
	return entry.Frame
end

function GameMenu.ReturnPage(id)
	local entry = pages[id]
	if not entry or not borrowed[id] then
		return
	end
	borrowed[id] = nil
	entry.Frame.Parent = canvas
	entry.Frame.Position = UDim2.fromOffset(LEFT_X, 106)
	entry.Frame.Visible = isOpen and currentPage == id
end

-- Vom SideMenu: handler(name) öffnet dessen Fenster (nil = schließen)
function GameMenu.SetPanelHandler(handler)
	panelHandler = handler
end

-- Vom SideMenu: welches Fenster gerade offen ist (für die Hervorhebung in der Navigation)
function GameMenu.PanelChanged(name)
	local wasOpen = openPanelName
	openPanelName = name
	if next(navButtons) ~= nil then
		updateNav()
	end
	-- Controller: nach dem Schließen eines Fensters wieder in die Lobby-Seite
	if wasOpen and not name and isOpen and pages[currentPage] then
		InputActions.Focus(pages[currentPage].Frame, currentPage == "Play" and play and play.Button or nil)
	end
end

-- ---------- SPIELEN-Knopf im Hub ----------
-- Großer Bernstein-Knopf unten mittig: rundes Play-Symbol, SPIELEN, darunter Modus und Spielerzahl, rechts die
-- Taste (M bzw. Steuerkreuz unten). Ein Rand breitet sich immer wieder aus und verblasst, alle paar Sekunden läuft
-- ein Glanz darüber; Überfahren/Auswählen vergrößert ihn leicht und schiebt das Play-Symbol an.
-- Gibt { Button, SetKey(text), SetSub(text) } zurück.
local HUB_PLAY_W, HUB_PLAY_H = 360, 78

local function buildHubPlay(parentGui)
	local white = Color3.new(1, 1, 1)
	local root = UITheme.ScaledRoot(parentGui, nil, nil, 0.6)
	local button = make("TextButton", { Name = "HubPlay", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.fromOffset(HUB_PLAY_W, HUB_PLAY_H), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		Visible = false, Selectable = true }, root)
	local scale = make("UIScale", {}, button)

	-- Welle: Rand, der sich ausbreitet und verblasst
	local wave = make("Frame", { Name = "Wave", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, button)
	UITheme.Corner(wave, UITheme.Radius.Large)
	local waveStroke = make("UIStroke", { Color = C.Primary, Thickness = 2, Transparency = 0.1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, wave)
	local waveInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, false, 0.7)
	TweenService:Create(wave, waveInfo, { Size = UDim2.new(1, 28, 1, 28) }):Play()
	TweenService:Create(waveStroke, waveInfo, { Transparency = 1 }):Play()

	-- Fläche: Bernstein mit Verlauf (oben heller), feine helle Kante oben
	local face = make("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = white, BorderSizePixel = 0 }, button)
	UITheme.Corner(face, UITheme.Radius.Large)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(UITheme.Brighten(C.Primary, 0.2),
		C.Primary:Lerp(Color3.new(0, 0, 0), 0.12)) }, face)
	make("Frame", { Name = "Edge", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 1), Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = white, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, face)

	-- Play-Symbol: dunkle Scheibe mit Dreieck aus 1-px-Zeilen (Schriften haben kein verlässliches ▶)
	local disc = make("Frame", { Name = "Disc", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(48, 48), BackgroundColor3 = C.PrimaryText, BorderSizePixel = 0 }, face)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, disc)
	local arrow = make("Frame", { Name = "Arrow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 2, 0.5, 0),
		Size = UDim2.fromOffset(16, 18), BackgroundTransparency = 1 }, disc)
	for row = 0, 17 do
		local width = 16 * (1 - math.abs(row + 0.5 - 9) / 9)
		make("Frame", { Position = UDim2.fromOffset(0, row), Size = UDim2.fromOffset(width, 1), BackgroundColor3 = C.Primary,
			BorderSizePixel = 0 }, arrow)
	end

	label({ Name = "Title", Position = UDim2.fromOffset(78, 8), Size = UDim2.new(1, -150, 0, 42), Text = "SPIELEN",
		TextSize = 40, Font = F.Display, TextColor3 = C.PrimaryText }, face)
	local sub = label({ Name = "Sub", Position = UDim2.fromOffset(79, 50), Size = UDim2.new(1, -150, 0, 16), Text = "",
		TextSize = 12, Font = F.Bold, TextColor3 = C.PrimaryText, TextTransparency = 0.25,
		TextTruncate = Enum.TextTruncate.AtEnd }, face)
	local key = label({ Name = "Key", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(40, 36), Text = "", TextSize = 16, Font = F.Bold, TextColor3 = C.Primary,
		BackgroundColor3 = C.PrimaryText, BackgroundTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false }, face)
	UITheme.Corner(key, UITheme.Radius.Small)

	-- Glanz: heller Streifen läuft alle paar Sekunden schräg darüber
	local shine = make("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = white, BorderSizePixel = 0,
		ZIndex = 2 }, face)
	UITheme.Corner(shine, UITheme.Radius.Large)
	local shineGradient = make("UIGradient", { Rotation = 25, Offset = Vector2.new(-1, 0), Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1), NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1) }) }, shine)
	TweenService:Create(shineGradient, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 2.6),
		{ Offset = Vector2.new(1, 0) }):Play()

	-- Überfahren/Auswählen: etwas größer, hellere Schicht, Play-Symbol rückt vor; Drücken: kurz kleiner
	local hover = make("Frame", { Name = "Hover", Size = UDim2.fromScale(1, 1), BackgroundColor3 = white, BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 2 }, face)
	UITheme.Corner(hover, UITheme.Radius.Large)
	local hovering = false
	local function setHover(on)
		hovering = on
		hover.BackgroundTransparency = on and 0.88 or 1
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = on and 1.04 or 1 }):Play()
		TweenService:Create(arrow, TweenInfo.new(0.18), { Position = UDim2.new(0.5, on and 5 or 2, 0.5, 0) }):Play()
	end
	button.MouseEnter:Connect(function()
		setHover(true)
	end)
	button.MouseLeave:Connect(function()
		setHover(false)
	end)
	button.SelectionGained:Connect(function()
		setHover(true)
	end)
	button.SelectionLost:Connect(function()
		setHover(false)
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 0.97 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = hovering and 1.04 or 1 }):Play()
	end)

	return {
		Button = button,
		SetKey = function(text)
			key.Text = text
			key.Visible = text ~= ""
		end,
		SetSub = function(text)
			sub.Text = text
		end,
	}
end

function GameMenu.Init()
	gui = make("ScreenGui", { Name = "GameMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false }, player:WaitForChild("PlayerGui"))
	background = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.3, Active = true }, gui) -- Active: Klicks gehen nicht ins Spiel
	UITheme.Gradient(background, Color3.fromRGB(30, 33, 38), Color3.fromRGB(6, 7, 9))
	canvas = UITheme.Canvas(background, WIDTH, HEIGHT)

	playPage = make("Frame", { Name = "PlayPage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, canvas)
	pages.Play = { Frame = playPage }
	-- Statuszeile für die Seiten außer SPIELEN (dort steht sie rechts über dem Knopf)
	pageStatus = label({ Position = UDim2.fromOffset(LEFT_X, 842), Size = UDim2.fromOffset(WIDTH - 2 * LEFT_X, 18), Text = "",
		TextSize = 13, Font = F.Medium, TextColor3 = C.Muted, Visible = false }, canvas)
	buildHeader()
	buildModes()
	buildSquad()
	buildAgentStage()
	buildPass()
	buildDaily()
	buildPlay()
	buildAgentPage()
	buildLobbyPages()
	selectMode(Modes.Featured() or QUICK)
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
	openButton = buildHubPlay(openGui)
	openButton.Button.Activated:Connect(function()
		GameMenu.SetOpen(true)
	end)
	updateHubPlay()

	-- Controller: ○ schließt zuerst ein offenes Fenster (auch im Hub), dann das Menü; L1/R1 blättert die Seiten
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonB then
			if openPanelName then
				openPanel(nil)
			elseif isOpen then
				GameMenu.SetOpen(false)
			end
		elseif isOpen and not openPanelName and (input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1) then
			cyclePage(input.KeyCode == Enum.KeyCode.ButtonL1 and -1 or 1)
		end
	end)
	-- Spielen-Knopf zeigt die Taste des aktuellen Geräts
	local function updateOpenButton()
		openButton.SetKey(InputActions.Hint("Menu"))
	end
	updateOpenButton()
	InputActions.DeviceChanged:Connect(updateOpenButton)
	-- Menü-Taste (M bzw. Steuerkreuz unten): nur im Hub bzw. wenn das Menü offen ist
	InputActions.Bind("Menu", function(began)
		if began and (isOpen or not Modes.IsFighting(player)) then
			GameMenu.SetOpen(not isOpen)
		end
	end)

	-- Rückmeldung vom Server (Kaufen, Ausrüsten, Freischalten) in die Statuszeile
	Remotes.ShopStatus.OnClientEvent:Connect(function(message, success)
		if isOpen and not openPanelName then
			setStatus(message, success == true and C.Good or (success == false and C.Bad or nil))
		end
	end)
	-- Meldungen vom Server (Modus voll, kommt bald, ...) öffnen das Menü mit der Meldung
	Remotes.MenuStatus.OnClientEvent:Connect(function(message)
		GameMenu.SetOpen(true)
		showPage("Play")
		setStatus(message)
	end)

	-- Moduswechsel: Menü schließen (öffnet sich nicht von selbst), im Hub und im Markt den SPIELEN-Knopf zeigen
	local function onModeChanged()
		local mode = player:GetAttribute("Mode")
		if mode == nil then
			return
		end
		inHub = Modes.IsSocial(mode) -- Hub oder Markt: kein laufendes Spiel
		hubButton.Button.Visible = mode ~= Modes.Hub.Id
		GameMenu.SetOpen(false)
		openButton.Button.Visible = inHub
		GameMenu.UpdatePlay()
	end
	player:GetAttributeChangedSignal("Mode"):Connect(onModeChanged)
	onModeChanged()
end

return GameMenu

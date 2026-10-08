-- AdminPanel (ModuleScript, nur Client)
-- Nur für Admins (Attribut "IsAdmin" vom Server). Öffnen/Schließen mit P oder dem ADMIN-Knopf.
-- Aufbau: Kopfzeile (Titel, Rückmeldung, Schließen), Reiter (SPIEL, EVENTS, BOTS, EINSTELLUNGEN, SPIELER), darunter die
-- Seite des Reiters. EVENTS zeigt jedes Event der offenen Welt als Karte mit Live-Status und START / HIER / STOP.
-- Alle Befehle prüft der Server noch einmal (AdminService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local GameSettings = require(Shared.GameSettings)
local AgentConfig = require(Shared.AgentConfig)
local DayCycle = require(Shared.DayCycle)

local player = Players.LocalPlayer

local AdminPanel = {}

-- Farben (Rogue-Company-Stil: Navy und Cyan)
local ACCENT = Color3.fromRGB(40, 210, 230)
local PANEL = Color3.fromRGB(10, 16, 28)
local HEADER = Color3.fromRGB(14, 24, 40)
local CARD = Color3.fromRGB(18, 30, 48)
local BUTTON = Color3.fromRGB(32, 48, 70)
local TEXT = Color3.fromRGB(235, 242, 248)
local MUTED = Color3.fromRGB(130, 155, 175)
local DARK_TEXT = Color3.fromRGB(10, 20, 30)
local TONES = {
	Accent = ACCENT,
	Good = Color3.fromRGB(56, 160, 92),
	Danger = Color3.fromRGB(196, 56, 64),
	Warn = Color3.fromRGB(200, 140, 40),
	Event = Color3.fromRGB(170, 84, 50),
	Night = Color3.fromRGB(70, 92, 150),
	Blood = Color3.fromRGB(150, 36, 40),
	Purple = Color3.fromRGB(116, 84, 176),
	Teal = Color3.fromRGB(40, 150, 120),
}
local PANEL_W = 560

local gui, panel, statusLabel, playerSection, toggleButton
local pages, tabButtons = {}, {}
local valueLabels = {} -- [Key] = Label
local eventStatus = {} -- [Event] = Label
local botCountLabel
local isOpen = false
local currentTab = "Events"
local playerSignature = ""

local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function corner(obj, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, obj)
end

local function label(textValue, size, parent, props)
	props = props or {}
	props.Text = textValue
	props.Size = props.Size or UDim2.new(1, 0, 0, size + 8)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.BuilderSansBold
	props.TextSize = size
	props.TextColor3 = props.TextColor3 or TEXT
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, parent)
end

-- Knopf: tone = Name aus TONES oder Color3 (gefüllt), nil = dunkel; beim Darüberfahren heller
local function button(textValue, width, parent, tone, onClick)
	local base = typeof(tone) == "Color3" and tone or (tone and TONES[tone]) or BUTTON
	local b = make("TextButton", {
		Size = UDim2.new(0, width, 0, 30),
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansBold,
		TextSize = 13,
		TextColor3 = TEXT,
		Text = textValue,
		AutoButtonColor = false,
	}, parent)
	corner(b, 6)
	local info = TweenInfo.new(0.12)
	b.MouseEnter:Connect(function()
		TweenService:Create(b, info, { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.15) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, info, { BackgroundColor3 = base }):Play()
	end)
	b.Activated:Connect(onClick)
	return b
end

-- Zeile mit Knöpfen nebeneinander
local function row(parent, height)
	local frame = make("Frame", { Size = UDim2.new(1, 0, 0, height or 30), BackgroundTransparency = 1 }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	return frame
end

-- Karte (dunkler Kasten mit Innenabstand, wächst mit dem Inhalt)
local function card(parent)
	local frame = make("Frame", { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = CARD,
		BorderSizePixel = 0 }, parent)
	corner(frame, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10) }, frame)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	return frame
end

local function send(action, a, b)
	statusLabel.Text = "…"
	statusLabel.TextColor3 = MUTED
	Remotes.AdminAction:FireServer(action, a, b)
end

local function section(title, parent)
	local holder = make("Frame", { Size = UDim2.new(1, -8, 0, 26), BackgroundTransparency = 1 }, parent)
	label(title, 13, holder, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = ACCENT, Font = Enum.Font.BuilderSansExtraBold })
	make("Frame", { Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = ACCENT,
		BackgroundTransparency = 0.7, BorderSizePixel = 0 }, holder)
	return holder
end

-- Reihenfolge = Erstellungsreihenfolge (für Seiten und Karten mit UIListLayout)
local function order(page)
	for i, child in page:GetChildren() do
		if child:IsA("GuiObject") then
			child.LayoutOrder = i
		end
	end
end

-- ---------- Seiten ----------

local function buildGame(page)
	section("MODI", page)
	for _, modeId in { "Domination", "Wingman", "Arena" } do
		local c = card(page)
		label(modeId, 15, c)
		local r = row(c)
		button("JETZT STARTEN", 130, r, "Good", function()
			send("ModeStart", modeId)
		end)
		button("RUNDE BEENDEN", 130, r, nil, function()
			send("ModeEndRound", modeId)
		end)
		button("RESET", 80, r, "Danger", function()
			send("ModeResetMatch", modeId)
		end)
		order(c)
	end
	local ffa = card(page)
	label("Free for All", 15, ffa)
	button("RUNDE BEENDEN", 130, row(ffa), nil, function()
		send("FFAEndRound")
	end)
	order(ffa)
	section("ICH", page)
	local me = card(page)
	local r = row(me)
	button("NOCLIP (B)", 120, r, "Night", function()
		send("Noclip")
	end)
	button("TAG / NACHT", 120, r, "Warn", function()
		send("DayNight")
	end)
end

-- Event-Karte: Name, Live-Status rechts, Knöpfe darunter. buttons = { { Text, Aktion, Wert, Ton, Breite } }
local function eventCard(page, key, title, buttons)
	local c = card(page)
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1 }, c)
	label(title, 15, head, { Size = UDim2.new(0.6, 0, 1, 0) })
	eventStatus[key] = label("", 12, head, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = MUTED })
	local r = row(c)
	for _, def in buttons do
		button(def[1], def[5] or 90, r, def[4], function()
			send(def[2], def[3])
		end)
	end
	order(c)
end

local function buildEvents(page)
	section("ALLES", page)
	local all = card(page)
	local r = row(all, 34)
	button("ALLE EVENTS BEENDEN", 200, r, "Danger", function()
		send("ExtStop", "All")
	end).Size = UDim2.new(0, 200, 0, 34)
	button("ZOMBIES ENTFERNEN", 170, r, nil, function()
		send("ExtStop", "Zombies")
	end).Size = UDim2.new(0, 170, 0, 34)
	section("EVENTS DER OFFENEN WELT", page)
	eventCard(page, "Airdrop", "Lootdrop", {
		{ "START", "ExtAirdrop", nil, "Event" }, { "BEI MIR", "ExtAirdrop", "Here", "Event" }, { "STOP", "ExtStop", "Airdrop", "Danger" } })
	eventCard(page, "Convoy", "Konvoi", {
		{ "START", "ExtConvoy", nil, "Event" }, { "STOP", "ExtStop", "Convoy", "Danger" } })
	eventCard(page, "HeliCrash", "Heli-Absturz", {
		{ "START", "ExtHeliCrash", nil, "Event" }, { "VOR MIR", "ExtHeliCrash", "Here", "Event" },
		{ "STOP", "ExtStop", "HeliCrash", "Danger" } })
	eventCard(page, "Horde", "Horden-Kiste", {
		{ "START", "ExtHordeCrate", nil, "Event" }, { "VOR MIR", "ExtHordeCrate", "Here", "Event" },
		{ "STOP", "ExtStop", "HordeCrate", "Danger" } })
	eventCard(page, "BloodMoon", "Blutmond", {
		{ "START", "BloodMoon", nil, "Blood" }, { "STOP", "ExtStop", "BloodMoon", "Danger" } })
	eventCard(page, "Storm", "Sturmnacht", {
		{ "START", "Storm", nil, "Night" }, { "STOP", "ExtStop", "Storm", "Danger" } })
	eventCard(page, "Bounty", "Kopfgeld", {
		{ "AUF MICH", "ExtBountyMe", nil, "Blood" }, { "STOP", "ExtStop", "Bounty", "Danger" } })
	eventCard(page, "Redzone", "Rote Zone", { { "WEITERZIEHEN", "ExtRedzone", nil, "Event", 130 } })
	section("SPAWNEN", page)
	local spawn = card(page)
	local r2 = row(spawn)
	button("12 ZOMBIES UM MICH", 160, r2, "Event", function()
		send("ExtHorde", 12)
	end)
	button("BOSSE SPAWNEN", 140, r2, "Blood", function()
		send("ExtBosses")
	end)
	button("TAG / NACHT", 110, r2, "Warn", function()
		send("DayNight")
	end)
	section("MIR GEBEN", page)
	local give = card(page)
	local r3 = row(give)
	button("AUFSÄTZE", 100, r3, "Teal", function()
		send("ExtGive", "Attachments")
	end)
	button("GRANATEN", 100, r3, "Teal", function()
		send("ExtGive", "Throwables")
	end)
	button("AUSRÜSTUNG", 110, r3, "Teal", function()
		send("ExtGive", "Kit")
	end)
	-- Rote-Zone-Punkte (RZ): Menge eintippen, dann RZ GEBEN
	local r4 = row(give)
	local rzBox = make("TextBox", { Size = UDim2.new(0, 110, 0, 30), BackgroundColor3 = BUTTON, BorderSizePixel = 0,
		Font = Enum.Font.BuilderSansBold, TextSize = 13, TextColor3 = TEXT, PlaceholderText = "Menge RZ",
		PlaceholderColor3 = MUTED, Text = "100", ClearTextOnFocus = false }, r4)
	corner(rzBox, 6)
	rzBox:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = string.gsub(rzBox.Text, "%D", "")
		if digits ~= rzBox.Text then
			rzBox.Text = digits
		end
	end)
	button("RZ GEBEN", 100, r4, "Blood", function()
		send("GiveRedPoints", tonumber(rzBox.Text) or 0)
	end)
	order(give)
end

-- Live-Status der Events (Karten-Attribute der offenen Welt, Blutmond/Sturm aus DayCycle)
local function refreshEvents()
	local maps = workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild("Extinction")
	local function listActive(attribute)
		local raw = map and map:GetAttribute(attribute)
		return type(raw) == "string" and raw ~= "" and raw ~= "[]"
	end
	local now = workspace:GetServerTimeNow()
	local bounty = map and map:GetAttribute("Bounty")
	local states = {
		Airdrop = listActive("Airdrops"),
		Convoy = listActive("Convoys"),
		HeliCrash = listActive("HeliCrashes"),
		Horde = listActive("Hordes"),
		BloodMoon = DayCycle.IsBloodMoon(now),
		Storm = DayCycle.IsStorm(now),
		Bounty = type(bounty) == "string" and bounty ~= "",
	}
	for key, statusText in eventStatus do
		if key ~= "Redzone" then
			local on = states[key]
			statusText.Text = on and "● LÄUFT" or "○ aus"
			statusText.TextColor3 = on and TONES.Good:Lerp(Color3.new(1, 1, 1), 0.2) or MUTED
		end
	end
end

local function buildBots(page)
	section("BOTS", page)
	local ffa = card(page)
	label("Free for All", 15, ffa)
	local r = row(ffa)
	button("+1 BOT", 80, r, nil, function()
		send("SpawnBot", "FreeForAll")
	end)
	button("+5 BOTS", 80, r, nil, function()
		for _ = 1, 5 do
			send("SpawnBot", "FreeForAll")
		end
	end)
	order(ffa)
	-- { Modus, Team A, Farbe A, Team B, Farbe B, Plätze }
	for _, entry in {
		{ "Domination", "Rot", Color3.fromRGB(150, 50, 50), "Blau", Color3.fromRGB(50, 80, 160), 10 },
		{ "Wingman", "Alpha", Color3.fromRGB(60, 150, 100), "Bravo", Color3.fromRGB(150, 130, 40), 4 },
		{ "Arena", "Links", Color3.fromRGB(120, 70, 170), "Rechts", Color3.fromRGB(70, 120, 170), 2 },
	} do
		local c = card(page)
		label(entry[1], 15, c)
		local mr = row(c)
		button("+1 " .. entry[2], 90, mr, entry[3], function()
			send("SpawnBot", entry[1], entry[2])
		end)
		button("+1 " .. entry[4], 90, mr, entry[5], function()
			send("SpawnBot", entry[1], entry[4])
		end)
		button("AUFFÜLLEN", 100, mr, nil, function()
			for _ = 1, entry[6] do
				send("SpawnBot", entry[1])
			end
		end)
		order(c)
	end
	-- Offene Welt: Bots spawnen beim Admin (draußen; in der Safe Zone vor ihrem Rand), sonst in der roten Zone
	local ext = card(page)
	label("Extinction", 15, ext)
	local er = row(ext)
	button("+1 BOT", 80, er, "Event", function()
		send("SpawnBot", "Extinction")
	end)
	button("+5 BOTS", 80, er, "Event", function()
		for _ = 1, 5 do
			send("SpawnBot", "Extinction")
		end
	end)
	button("ENTFERNEN", 100, er, "Danger", function()
		send("RemoveBots", "Extinction")
	end)
	order(ext)
	local all = card(page)
	button("ALLE BOTS ENTFERNEN", 180, row(all), "Danger", function()
		send("RemoveBots")
	end)
	botCountLabel = label("", 13, all, { Font = Enum.Font.BuilderSans, TextColor3 = MUTED })
	order(all)
end

local function refreshBots()
	if not botCountLabel then
		return
	end
	local counts = {}
	local folder = ReplicatedStorage:FindFirstChild("BotInfo")
	for _, info in folder and folder:GetChildren() or {} do
		local mode = info:GetAttribute("Mode")
		counts[mode] = (counts[mode] or 0) + 1
	end
	botCountLabel.Text = "FFA " .. (counts.FreeForAll or 0) .. "  ·  Herrschaft " .. (counts.Drop or 0) .. "  ·  Wingman "
		.. (counts.Wingman or 0) .. "  ·  Extinction " .. (counts.Extinction or 0)
end

local function buildSettings(page)
	local lastGroup, c = nil, nil
	for _, def in GameSettings.List do
		if def.Group ~= lastGroup then
			if c then
				order(c)
			end
			lastGroup = def.Group
			section(string.upper(def.Group), page)
			c = card(page)
		end
		local r = row(c)
		label(def.Label, 14, r, { Size = UDim2.new(0, 260, 1, 0), Font = Enum.Font.BuilderSans })
		button("−", 34, r, nil, function()
			send("SetSetting", def.Key, GameSettings.Get(def.Key) - def.Step)
		end)
		valueLabels[def.Key] = label("", 15, r, { Size = UDim2.new(0, 60, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = ACCENT })
		button("+", 34, r, nil, function()
			send("SetSetting", def.Key, GameSettings.Get(def.Key) + def.Step)
		end)
	end
	if c then
		order(c)
	end
end

local function refreshSettings()
	for key, valueLabel in valueLabels do
		valueLabel.Text = tostring(GameSettings.Get(key))
	end
end

-- Spielerliste neu bauen (nur wenn sich etwas geändert hat)
local function refreshPlayers()
	local parts = {}
	for _, p in Players:GetPlayers() do
		table.insert(parts, p.UserId .. ":" .. tostring(p:GetAttribute("Mode")) .. ":" .. tostring(p.Team)
			.. ":" .. tostring(p:GetAttribute("Agent")))
	end
	local signature = table.concat(parts, "|")
	if signature == playerSignature then
		return
	end
	playerSignature = signature

	for _, child in playerSection:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, p in Players:GetPlayers() do
		local box = card(playerSection)
		box.LayoutOrder = i
		local agent = AgentConfig.Get(p:GetAttribute("Agent"))
		label(p.Name, 16, box, { Font = Enum.Font.BuilderSansExtraBold })
		label(tostring(p:GetAttribute("Mode")) .. (p.Team and ("  ·  " .. p.Team.Name) or "") .. "  ·  " .. (agent and agent.Name or "?"),
			12, box, { TextColor3 = MUTED, Font = Enum.Font.BuilderSans })
		local moves = row(box)
		local short = { Hub = "Hub", Market = "Markt", FreeForAll = "FFA", Domination = "Herr.", Wingman = "Wing",
			Arena = "1v1", Training = "Train" }
		for _, modeId in { "Hub", "Market", "FreeForAll", "Domination", "Wingman", "Arena", "Training" } do
			button(short[modeId], 52, moves, nil, function()
				send("MovePlayer", p.UserId, modeId)
			end)
		end
		button("Team", 56, moves, "Accent", function()
			send("SwitchTeam", p.UserId)
		end).TextColor3 = DARK_TEXT
		local actions = row(box)
		button("Heilen", 60, actions, "Good", function()
			send("Heal", p.UserId)
		end)
		button("Töten", 56, actions, "Danger", function()
			send("Kill", p.UserId)
		end)
		button("+500 XP", 70, actions, nil, function()
			send("GiveXP", p.UserId, 500)
		end)
		button("+5000 XP", 76, actions, nil, function()
			send("GiveXP", p.UserId, 5000)
		end)
		button("+1000 Münzen", 100, actions, "Warn", function()
			send("GiveCoins", p.UserId, 1000)
		end)
		button("+5 Stufen", 80, actions, "Teal", function()
			send("GivePassXP", p.UserId, 5000)
		end)
		local prestige = row(box)
		button("Max Prestige", 104, prestige, "Warn", function()
			send("SetPrestige", p.UserId, "max")
		end)
		button("Prestige +1", 94, prestige, "Purple", function()
			send("SetPrestige", p.UserId, "next")
		end)
		button("Level 100", 84, prestige, nil, function()
			send("SetPrestige", p.UserId, "level100")
		end)
		button("Prestige 0", 88, prestige, "Danger", function()
			send("SetPrestige", p.UserId, 0)
		end)
		local elo = row(box)
		button("Max ELO", 76, elo, "Warn", function()
			send("SetElo", p.UserId, "max")
		end)
		for _, step in { 100, 1, -1, -100 } do
			button((step > 0 and "+" or "−") .. math.abs(step), 52, elo, nil, function()
				send("SetElo", p.UserId, step)
			end)
		end
		button("ELO zurück", 90, elo, "Danger", function()
			send("SetElo", p.UserId, "reset")
		end)
		local season = row(box)
		button("Saisonende testen", 140, season, "Purple", function()
			send("SetElo", p.UserId, "season")
		end)
		button("+10.000 RAP", 104, season, "Teal", function()
			send("GiveRap", p.UserId, 10000)
		end)
		button("Handelbarer Skin", 130, season, "Teal", function()
			send("GiveTradeSkin", p.UserId)
		end)
		order(box)
	end
end

-- ---------- Rahmen ----------

local function showTab(id)
	currentTab = id
	for tabId, page in pages do
		page.Visible = tabId == id
	end
	for tabId, tab in tabButtons do
		local on = tabId == id
		tab.BackgroundColor3 = on and ACCENT or BUTTON
		tab.TextColor3 = on and DARK_TEXT or MUTED
	end
	if id == "Players" then
		playerSignature = ""
		refreshPlayers()
	end
end

local function setOpen(open)
	isOpen = open
	panel.Visible = open
	if open then
		refreshSettings()
		refreshEvents()
		refreshBots()
		showTab(currentTab)
		RunService:BindToRenderStep("AdminMouse", Enum.RenderPriority.Camera.Value + 2, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	else
		RunService:UnbindFromRenderStep("AdminMouse")
	end
end

local function newPage(id)
	local page = make("ScrollingFrame", { Name = "Page_" .. id, Position = UDim2.new(0, 16, 0, 112), Size = UDim2.new(1, -24, 1, -124),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = ACCENT,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	make("UIPadding", { PaddingBottom = UDim.new(0, 12) }, page)
	pages[id] = page
	return page
end

local function build()
	gui = make("ScreenGui", { Name = "AdminPanel", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20 },
		player:WaitForChild("PlayerGui"))

	toggleButton = button("ADMIN (P)", 110, gui, "Accent", function()
		setOpen(not isOpen)
	end)
	toggleButton.Position = UDim2.new(0, 150, 0, 6)
	toggleButton.TextColor3 = DARK_TEXT

	panel = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.new(0, PANEL_W, 0.88, 0), BackgroundColor3 = PANEL, BackgroundTransparency = 0.03,
		BorderSizePixel = 0, Visible = false, Active = true, ClipsDescendants = true }, gui)
	corner(panel, 12)
	make("UIStroke", { Color = Color3.fromRGB(40, 70, 95), Thickness = 1.2 }, panel)

	-- Kopfzeile: Akzentstreifen, Titel, Rückmeldung, Schließen
	local header = make("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = HEADER, BorderSizePixel = 0 }, panel)
	make("Frame", { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, header)
	label("ADMIN", 22, header, { Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(0, 200, 0, 26),
		Font = Enum.Font.BuilderSansExtraBold, TextColor3 = ACCENT })
	statusLabel = label("Bereit", 13, header, { Position = UDim2.new(0, 16, 0, 36), Size = UDim2.new(1, -80, 0, 18),
		Font = Enum.Font.BuilderSans, TextColor3 = MUTED, TextTruncate = Enum.TextTruncate.AtEnd })
	local close = button("✕", 36, header, nil, function()
		setOpen(false)
	end)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.new(0, 36, 0, 36)

	-- Reiter
	local tabs = make("Frame", { Position = UDim2.new(0, 16, 0, 74), Size = UDim2.new(1, -32, 0, 30), BackgroundTransparency = 1 },
		panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for index, def in { { "Game", "SPIEL", 80 }, { "Events", "EVENTS", 90 }, { "Bots", "BOTS", 74 },
		{ "Settings", "EINSTELLUNGEN", 130 }, { "Players", "SPIELER", 96 } } do
		local tab = make("TextButton", { Size = UDim2.new(0, def[3], 1, 0), BackgroundColor3 = BUTTON, BorderSizePixel = 0,
			Font = Enum.Font.BuilderSansExtraBold, TextSize = 13, TextColor3 = MUTED, Text = def[2], AutoButtonColor = false,
			LayoutOrder = index }, tabs)
		corner(tab, 15)
		tab.Activated:Connect(function()
			showTab(def[1])
		end)
		tabButtons[def[1]] = tab
	end

	buildGame(newPage("Game"))
	buildEvents(newPage("Events"))
	buildBots(newPage("Bots"))
	buildSettings(newPage("Settings"))
	local playersPage = newPage("Players")
	playerSection = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1 }, playersPage)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, playerSection)
	for _, page in pages do
		order(page)
	end
	showTab(currentTab)
end

function AdminPanel.Init()
	if not player:GetAttribute("IsAdmin") then
		player:GetAttributeChangedSignal("IsAdmin"):Wait()
	end
	if not player:GetAttribute("IsAdmin") then
		return
	end
	build()

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.P then
			setOpen(not isOpen)
		end
	end)
	Remotes.AdminStatus.OnClientEvent:Connect(function(message)
		statusLabel.Text = message
		statusLabel.TextColor3 = TEXT
	end)
	ReplicatedStorage.AttributeChanged:Connect(function()
		if isOpen then
			refreshSettings()
		end
	end)
	task.spawn(function()
		while true do
			if isOpen then
				refreshEvents()
				refreshBots()
				if currentTab == "Players" then
					refreshPlayers()
				end
			end
			task.wait(1)
		end
	end)
end

return AdminPanel

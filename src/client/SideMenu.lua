-- SideMenu (ModuleScript, nur Client)
-- Menüliste links im Hub: SHOP, LOADOUT, AGENTEN, BATTLE PASS, AUFTRÄGE, TÄGLICH, SQUAD, STATISTIK,
-- CODES, OPTIONEN (schlichte Textzeilen), darüber die Spielerkarte (Level, Prestige, Rang, Münzen).
-- SHOP, LOADOUT, AGENTEN und BATTLE PASS öffnen die Lobby (GameMenu) auf der passenden Seite; Aufträge,
-- Täglich, Squad, Statistik, Codes und Optionen sind Fenster in der Mitte – dieselben Fenster öffnet auch die
-- Lobby (Squad, Auftrag, Knöpfe oben rechts). Design wie die Lobby (UITheme, nüchterner Taktik-Look):
-- dunkle Flächen mit 1 px Rand, flache Knöpfe, Bernstein für aktiv. Kaufen/Ausrüsten prüft der Server (ShopService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.Cosmetics)
local AgentConfig = require(Shared.AgentConfig)
local Movement = require(Shared.Movement)
local GameMenu = require(Shared.GameMenu)
local UITheme = require(Shared.UITheme)
local QuestConfig = require(Shared.QuestConfig)
local RankConfig = require(Shared.RankConfig)
local RankEmblem = require(Shared.RankEmblem)
local LevelConfig = require(Shared.LevelConfig)
local RewardConfig = require(Shared.RewardConfig)
local InputActions = require(Shared.InputActions)
local PrestigeEmblem = require(Shared.PrestigeEmblem)
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

local SideMenu = {}

-- Farben aus dem gemeinsamen Design (UITheme): Bernstein = aktiv/hervorgehoben, Blau = Team
local ACCENT = UITheme.Colors.Primary
local ON_ACCENT = UITheme.Colors.PrimaryText
local PANEL = UITheme.Colors.Panel
local CARD = UITheme.Colors.Card
local BORDER = UITheme.Colors.Border
local GRAY = UITheme.Colors.Muted
local GREEN = UITheme.Colors.Good
local DISPLAY = UITheme.Fonts.Display


local gui, column, coinLabel, dailyDot, questDot
local panels = {}      -- [Name] = { Frame, Status, Refresh }
local openPanel = nil

-- ---------- Helfer ----------

local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function text(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = UITheme.FontFor(props.Font or Enum.Font.GothamBold, props.TextSize)
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, parent)
end

local function button(props, parent, onClick)
	props.Font = props.Font or UITheme.Fonts.Bold
	return UITheme.Button(props, parent, onClick)
end

local formatNumber = UITheme.FormatNumber

local function coins()
	return player:GetAttribute("Coins") or 0
end

-- ---------- Fenster ----------

local function setPanel(name)
	if name and not panels[name] then
		name = nil
	end
	for panelName, panel in panels do
		if panelName ~= name then
			InputActions.Unfocus(panel.Frame) -- Controller-Auswahl nicht in einem unsichtbaren Fenster lassen
		end
		panel.Frame.Visible = panelName == name
	end
	openPanel = name
	UITheme.SetBlur("SideMenu", name ~= nil)
	GameMenu.PanelChanged(name) -- Lobby: passenden Reiter hervorheben
	if name and panels[name].Refresh then
		panels[name].Refresh()
	end
	if name then
		InputActions.Focus(panels[name].Frame) -- Controller: Auswahl in das Fenster
	end
end

local function makePanel(name, title, width, height)
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, width, 0, height), BackgroundColor3 = PANEL, Visible = false, Active = true }, gui)
	make("UICorner", { CornerRadius = UDim.new(0, UITheme.Radius.XL) }, frame)
	make("UIStroke", { Color = BORDER, Thickness = 1 }, frame)
	UITheme.Gradient(frame, Color3.fromRGB(27, 31, 36), PANEL)
	local scale = make("UIScale", {}, frame)
	local function updateScale()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min((viewport.X - 280) / (width + 40), (viewport.Y - 60) / (height + 40)), 0.4, 1.15)
	end
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	text({ Position = UDim2.new(0, 24, 0, 12), Size = UDim2.new(1, -100, 0, 40), Text = UITheme.Upper(title),
		TextSize = 32, Font = DISPLAY, TextColor3 = UITheme.Colors.Text }, frame)
	make("Frame", { Position = UDim2.new(0, 24, 0, 52), Size = UDim2.new(0, 28, 0, 2), BackgroundColor3 = ACCENT,
		BorderSizePixel = 0 }, frame)
	local close = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.new(0, 40, 0, 40),
		Text = "", TextSize = 18, BackgroundColor3 = CARD }, frame, function()
		setPanel(nil)
	end)
	close:SetAttribute("NoFocus", true) -- Controller: schließen per ○, Auswahl startet beim Inhalt
	UITheme.Cross(close, 14, UITheme.Colors.Text, 2)
	local status = text({ Position = UDim2.new(0, 24, 1, -36), Size = UDim2.new(1, -48, 0, 24), Text = "",
		TextSize = 16, TextColor3 = GRAY }, frame)
	panels[name] = { Frame = frame, Status = status }
	return frame
end

-- ---------- AUFTRÄGE ----------

-- Gibt es einen fertigen, noch nicht abgeholten Auftrag (täglich oder wöchentlich) oder den Wochen-Bonus?
local function questReady()
	for _, attribute in { "Quests", "Weekly" } do
		local data = QuestConfig.Read(player, attribute)
		if data and data.Ids then
			local allClaimed = true
			for _, id in data.Ids do
				local quest = QuestConfig.Get(id)
				local claimed = (data.Claimed or {})[id] == true
				allClaimed = allClaimed and claimed
				if quest and not claimed and ((data.Progress or {})[id] or 0) >= quest.Goal then
					return true
				end
			end
			if attribute == "Weekly" and allClaimed and #data.Ids > 0 and not data.Bonus then
				return true
			end
		end
	end
	return false
end

-- "5 h 12 min" bzw. "3 T 4 h"
local function timeLeft(seconds)
	if seconds >= 86400 then
		return math.floor(seconds / 86400) .. " T " .. math.floor(seconds % 86400 / 3600) .. " h"
	end
	return math.floor(seconds / 3600) .. " h " .. math.floor(seconds % 3600 / 60) .. " min"
end

local function buildQuests()
	local frame = makePanel("Quests", "AUFTRÄGE", 1000, 580)
	local columns = {}
	for i, info in { { "TÄGLICH", "Jeden Tag neu" }, { "WÖCHENTLICH", "Jeden Montag neu · alle geschafft = Wochen-Bonus" } } do
		local x = i == 1 and 24 or 512
		text({ Position = UDim2.new(0, x, 0, 62), Size = UDim2.new(0, 300, 0, 24), Text = info[1], TextSize = 20,
			Font = UITheme.Fonts.Title, TextColor3 = i == 1 and ACCENT or UITheme.Colors.Gold }, frame)
		local timer = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0, x + 464, 0, 64), Size = UDim2.new(0, 200, 0, 20),
			Text = "", TextSize = 14, TextColor3 = GRAY, TextXAlignment = Enum.TextXAlignment.Right }, frame)
		text({ Position = UDim2.new(0, x, 0, 86), Size = UDim2.new(0, 464, 0, 18), Text = info[2], TextSize = 13,
			Font = UITheme.Fonts.Body, TextColor3 = GRAY }, frame)
		local list = make("Frame", { Position = UDim2.new(0, x, 0, 114), Size = UDim2.new(0, 464, 1, -160),
			BackgroundTransparency = 1 }, frame)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		columns[i] = { List = list, Timer = timer }
	end
	make("Frame", { Position = UDim2.new(0, 499, 0, 66), Size = UDim2.new(0, 1, 1, -110), BackgroundColor3 = BORDER,
		BorderSizePixel = 0 }, frame)

	-- Eine Auftragszeile: Text, Fortschritt, Belohnung, Knopf
	local function questRow(list, order, quest, data, color)
		local id = quest.Id
		local progress = (data.Progress or {})[id] or 0
		local claimed = (data.Claimed or {})[id] == true
		local done = progress >= quest.Goal
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = CARD, LayoutOrder = order }, list)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, row)
		text({ Position = UDim2.new(0, 14, 0, 9), Size = UDim2.new(1, -164, 0, 22), Text = quest.Text, TextSize = 17,
			TextTruncate = Enum.TextTruncate.AtEnd }, row)
		text({ Position = UDim2.new(0, 14, 0, 33), Size = UDim2.new(1, -164, 0, 16),
			Text = math.min(progress, quest.Goal) .. " / " .. quest.Goal .. "   ·   " .. formatNumber(quest.Reward) .. " Münzen",
			TextSize = 13, TextColor3 = GRAY }, row)
		local barBack = make("Frame", { Position = UDim2.new(0, 14, 0, 56), Size = UDim2.new(1, -164, 0, 4),
			BackgroundColor3 = BORDER, BorderSizePixel = 0 }, row)
		make("Frame", { Size = UDim2.new(math.clamp(progress / quest.Goal, 0, 1), 0, 1, 0), BorderSizePixel = 0,
			BackgroundColor3 = done and GREEN or color }, barBack)
		button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0, 128, 0, 42),
			TextSize = 15, Text = claimed and "ABGEHOLT" or (done and "ABHOLEN" or "OFFEN"),
			BackgroundColor3 = (done and not claimed) and ACCENT or UITheme.Colors.MutedBack,
			TextColor3 = (done and not claimed) and ON_ACCENT or GRAY }, row, function()
			if done and not claimed then
				Remotes.ShopAction:FireServer("ClaimQuest", id)
			end
		end)
	end

	local function clearList(list)
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	panels.Quests.Refresh = function()
		local now = workspace:GetServerTimeNow()
		columns[1].Timer.Text = "NEU IN " .. timeLeft(QuestConfig.DayLeft(now))
		columns[2].Timer.Text = "NEU IN " .. timeLeft(QuestConfig.WeekLeft(now))

		-- Täglich
		clearList(columns[1].List)
		local daily = QuestConfig.Read(player, "Quests")
		for i, id in daily and daily.Ids or {} do
			local quest = QuestConfig.Get(id)
			if quest then
				questRow(columns[1].List, i, quest, daily, ACCENT)
			end
		end

		-- Wöchentlich + Bonus
		clearList(columns[2].List)
		local weekly = QuestConfig.Read(player, "Weekly")
		if not weekly or not weekly.Ids then
			return
		end
		local allClaimed = #weekly.Ids > 0
		for i, id in weekly.Ids do
			local quest = QuestConfig.Get(id)
			if quest then
				questRow(columns[2].List, i, quest, weekly, UITheme.Colors.Gold)
				allClaimed = allClaimed and (weekly.Claimed or {})[id] == true
			end
		end
		local skin = Cosmetics.Get(QuestConfig.BonusSkin(weekly.Week or 0))
		local rarity = skin and Cosmetics.Rarities[skin.Rarity]
		local bonus = make("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = CARD, LayoutOrder = 99 }, columns[2].List)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, bonus)
		make("UIStroke", { Color = UITheme.Colors.Gold, Transparency = weekly.Bonus and 0.7 or 0.2 }, bonus)
		text({ Position = UDim2.new(0, 14, 0, 9), Size = UDim2.new(1, -164, 0, 22), Text = "WOCHEN-BONUS", TextSize = 18,
			Font = UITheme.Fonts.Title, TextColor3 = UITheme.Colors.Gold }, bonus)
		text({ Position = UDim2.new(0, 14, 0, 34), Size = UDim2.new(1, -164, 0, 18), RichText = true,
			Text = formatNumber(QuestConfig.WeeklyBonus.Coins) .. " Münzen" .. (skin and (' + Skin <font color="#'
				.. (rarity and rarity.Color or UITheme.Colors.Gold):ToHex() .. '">' .. skin.Name .. "</font>") or ""),
			TextSize = 14, TextColor3 = GRAY }, bonus)
		button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0, 128, 0, 42),
			TextSize = 15, Text = weekly.Bonus and "ABGEHOLT" or (allClaimed and "ABHOLEN" or "GESPERRT"),
			BackgroundColor3 = (allClaimed and not weekly.Bonus) and UITheme.Colors.Gold or UITheme.Colors.MutedBack,
			TextColor3 = (allClaimed and not weekly.Bonus) and ON_ACCENT or GRAY }, bonus, function()
			if allClaimed and not weekly.Bonus then
				Remotes.ShopAction:FireServer("ClaimWeeklyBonus")
			end
		end)
	end
end

local function decodeAttribute(target, name)
	local raw = target:GetAttribute(name)
	if type(raw) ~= "string" then
		return {}
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(data) == "table" and data or {}
end

-- ---------- SQUAD ----------

local function buildSquad()
	local frame = makePanel("Squad", "SQUAD", 760, 560)
	text({ Position = UDim2.new(0, 24, 0, 64), Size = UDim2.new(0.5, -30, 0, 20), Text = "DEIN SQUAD (max. 4)", TextSize = 14,
		TextColor3 = ACCENT }, frame)
	text({ Position = UDim2.new(0.5, 6, 0, 64), Size = UDim2.new(0.5, -30, 0, 20), Text = "SPIELER IM SERVER", TextSize = 14,
		TextColor3 = ACCENT }, frame)
	local function column(x)
		local list = make("ScrollingFrame", { Position = UDim2.new(x, x == 0 and 24 or 6, 0, 92), Size = UDim2.new(0.5, -30, 1, -180),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y }, frame)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		return list
	end
	local mine, others = column(0), column(0.5)
	button({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -48), Size = UDim2.new(0, 220, 0, 44),
		Text = "SQUAD VERLASSEN", TextSize = 16, BackgroundColor3 = Color3.fromRGB(140, 45, 50) }, frame, function()
		Remotes.PartyAction:FireServer("Leave")
	end)

	local function row(parent, order, name, buttonText, buttonColor, onClick)
		local entry = make("Frame", { Size = UDim2.new(1, -6, 0, 48), BackgroundColor3 = CARD, LayoutOrder = order }, parent)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, entry)
		text({ Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -150, 1, 0), Text = name, TextSize = 16 }, entry)
		if buttonText then
			button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 120, 0, 34),
				Text = buttonText, TextSize = 14, BackgroundColor3 = buttonColor }, entry, onClick)
		end
	end

	panels.Squad.Refresh = function()
		for _, list in { mine, others } do
			for _, child in list:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
		end
		local party = decodeAttribute(player, "Party")
		local inParty = {}
		local iAmLeader = party.Leader == nil or party.Leader == player.UserId
		if party.Members then
			for i, member in party.Members do
				inParty[member.UserId] = true
				local isLeader = member.UserId == party.Leader
				local kick = iAmLeader and member.UserId ~= player.UserId
				row(mine, i, (isLeader and "★  " or "") .. member.Name, kick and "ENTFERNEN" or nil, Color3.fromRGB(140, 45, 50),
					function()
						Remotes.PartyAction:FireServer("Kick", member.UserId)
					end)
			end
		else
			row(mine, 1, "Du spielst allein – lade jemanden ein!")
		end
		local order = 0
		for _, other in Players:GetPlayers() do
			if other ~= player and not inParty[other.UserId] then
				order += 1
				row(others, order, other.Name, iAmLeader and "EINLADEN" or nil, GREEN, function()
					Remotes.PartyAction:FireServer("Invite", other.UserId)
				end)
			end
		end
		if order == 0 then
			row(others, 1, "Keine anderen Spieler im Server.")
		end
	end
	Players.PlayerAdded:Connect(function()
		if openPanel == "Squad" then
			panels.Squad.Refresh()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if openPanel == "Squad" then
				panels.Squad.Refresh()
			end
		end)
	end)

	-- Einladung (erscheint überall, auch außerhalb des Hubs)
	local inviteGui = make("ScreenGui", { Name = "PartyInvite", ResetOnSpawn = false, DisplayOrder = 30 }, player.PlayerGui)
	local popup = make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -140), Size = UDim2.new(0, 360, 0, 120),
		BackgroundColor3 = PANEL, Visible = false }, inviteGui)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, popup)
	make("UIStroke", { Color = ACCENT, Thickness = 1 }, popup)
	local inviteText = text({ Position = UDim2.new(0, 16, 0, 12), Size = UDim2.new(1, -32, 0, 44), Text = "", TextSize = 16,
		TextWrapped = true }, popup)
	local inviter = nil
	local inviteId = 0
	button({ Position = UDim2.new(0, 16, 1, -52), Size = UDim2.new(0.5, -22, 0, 40), Text = "ANNEHMEN", TextSize = 15,
		BackgroundColor3 = GREEN }, popup, function()
		Remotes.PartyAction:FireServer("Accept", inviter)
		popup.Visible = false
	end)
	button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 1, -52), Size = UDim2.new(0.5, -22, 0, 40), Text = "ABLEHNEN",
		TextSize = 15, BackgroundColor3 = CARD }, popup, function()
		Remotes.PartyAction:FireServer("Decline", inviter)
		popup.Visible = false
	end)
	Remotes.PartyInvite.OnClientEvent:Connect(function(name, userId)
		inviteId += 1
		local myId = inviteId
		inviter = userId
		inviteText.Text = name .. " lädt dich in seinen Squad ein."
		popup.Visible = true
		task.delay(20, function()
			if inviteId == myId then
				popup.Visible = false
			end
		end)
	end)
end

-- ---------- STATS + RANKED ----------


local function ratio(a, b)
	return b > 0 and a / b or a
end

local function percent(a, b)
	return b > 0 and string.format("%d %%", math.floor(a / b * 100 + 0.5)) or "–"
end

local function buildStats()
	local frame = makePanel("Stats", "STATISTIK", 1040, 760)
	-- Linke Seite: Kacheln
	local grid = make("Frame", { Position = UDim2.new(0, 24, 0, 70), Size = UDim2.new(0, 620, 0, 376),
		BackgroundTransparency = 1 }, frame)
	make("UIGridLayout", { CellSize = UDim2.new(0, 145, 0, 84), CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local tiles = {}
	local order = { "KD", "Kills", "Deaths", "Assists", "WinRate", "Matches", "Wins", "Clutches", "HSRate", "Accuracy",
		"AvgDamage", "Revives", "Captures", "AvgKills", "BestStreak", "Favorite" }
	local titles = { KD = "K/D", Kills = "KILLS", Deaths = "TODE", Assists = "ASSISTS", WinRate = "SIEGQUOTE",
		Matches = "MATCHES", Wins = "SIEGE", Clutches = "CLUTCHES", HSRate = "KOPFSCHUSS-QUOTE", Accuracy = "TREFFERQUOTE",
		AvgDamage = "Ø SCHADEN/MATCH", Revives = "WIEDERBELEBT", Captures = "FLAGGEN EINGENOMMEN", AvgKills = "Ø KILLS/MATCH",
		BestStreak = "BESTE KILLSERIE", Favorite = "LIEBLINGS-AGENT" }
	for i, key in order do
		local tile = make("Frame", { BackgroundColor3 = CARD, LayoutOrder = i }, grid)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, tile)
		make("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = (key == "KD" or key == "WinRate") and ACCENT or BORDER,
			BorderSizePixel = 0 }, tile)
		text({ Position = UDim2.new(0, 14, 0, 10), Size = UDim2.new(1, -20, 0, 16), Text = titles[key], TextSize = 11,
			TextColor3 = GRAY }, tile)
		tiles[key] = text({ Position = UDim2.new(0, 14, 0, 30), Size = UDim2.new(1, -20, 0, 40), Text = "–", TextSize = 30,
			Font = UITheme.Fonts.Title, TextScaled = false }, tile)
	end

	-- Rechte Seite: Ranked
	local rankedBox = make("Frame", { Position = UDim2.new(0, 668, 0, 70), Size = UDim2.new(1, -692, 0, 230),
		BackgroundColor3 = CARD }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, rankedBox)
	text({ Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 18), Text = "ELO · SAISON " .. RankConfig.Season .. "  ·  IN JEDEM MODUS",
		TextSize = 13, TextColor3 = ACCENT }, rankedBox)
	local rankName = text({ Position = UDim2.new(0, 16, 0, 32), Size = UDim2.new(1, -100, 0, 50), Text = "", TextSize = 42,
		Font = UITheme.Fonts.Title }, rankedBox)
	local statsRankHolder = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 22),
		Size = UDim2.new(0, 84, 0, 84), BackgroundTransparency = 1 }, rankedBox)
	local statsRank = RankEmblem.new(statsRankHolder, 84)
	local eloText = text({ Position = UDim2.new(0, 16, 0, 84), Size = UDim2.new(1, -32, 0, 24), Text = "", TextSize = 18 }, rankedBox)
	local barBack = make("Frame", { Position = UDim2.new(0, 16, 0, 116), Size = UDim2.new(1, -32, 0, 8),
		BackgroundColor3 = BORDER, BorderSizePixel = 0 }, rankedBox)
	local bar = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, barBack)
	local rankedInfo = text({ Position = UDim2.new(0, 16, 0, 136), Size = UDim2.new(1, -32, 0, 84), Text = "", TextSize = 15,
		Font = UITheme.Fonts.Body, TextColor3 = GRAY, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, rankedBox)

	-- Bestenliste
	local board = make("Frame", { Position = UDim2.new(0, 668, 0, 312), Size = UDim2.new(1, -692, 1, -352),
		BackgroundColor3 = CARD }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, board)
	text({ Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 18), Text = "TOP 10 · ELO", TextSize = 13,
		TextColor3 = ACCENT }, board)
	local boardText = text({ Position = UDim2.new(0, 16, 0, 34), Size = UDim2.new(1, -32, 1, -44), Text = "", TextSize = 15,
		Font = UITheme.Fonts.Body, TextYAlignment = Enum.TextYAlignment.Top, RichText = true }, board)

	-- Match-Verlauf (letzte 10 Matches)
	local history = make("Frame", { Position = UDim2.new(0, 24, 0, 456), Size = UDim2.new(0, 620, 0, 256),
		BackgroundColor3 = CARD }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, history)
	text({ Position = UDim2.new(0, 16, 0, 8), Size = UDim2.new(1, -32, 0, 18), Text = "LETZTE MATCHES", TextSize = 13,
		TextColor3 = ACCENT }, history)
	local COLUMNS = { { "Result", 0, 110 }, { "Mode", 110, 140 }, { "Map", 250, 120 }, { "Score", 370, 70 },
		{ "KD", 440, 70 }, { "Elo", 510, 60 } }
	local rows = {}
	for i = 1, 10 do
		local row = make("Frame", { Position = UDim2.new(0, 16, 0, 30 + (i - 1) * 22), Size = UDim2.new(1, -32, 0, 22),
			BackgroundColor3 = BORDER, BackgroundTransparency = i % 2 == 0 and 0.75 or 1, BorderSizePixel = 0 }, history)
		local cells = {}
		for _, column in COLUMNS do
			cells[column[1]] = text({ Position = UDim2.new(0, column[2] + 6, 0, 0), Size = UDim2.new(0, column[3] - 6, 1, 0),
				Text = "", TextSize = 14, Font = UITheme.Fonts.Body, TextTruncate = Enum.TextTruncate.AtEnd }, row)
		end
		cells.Result.Font = UITheme.Fonts.Title
		rows[i] = cells
	end
	local historyEmpty = text({ Position = UDim2.new(0, 16, 0, 34), Size = UDim2.new(1, -32, 0, 20),
		Text = "Noch keine Matches gespielt.", TextSize = 15, Font = UITheme.Fonts.Body, TextColor3 = GRAY }, history)

	panels.Stats.Refresh = function()
		local list = decodeAttribute(player, "MatchHistory")
		historyEmpty.Visible = #list == 0
		for i, cells in rows do
			local entry = list[i]
			for _, label in cells do
				label.Text = ""
			end
			if entry then
				cells.Result.Text = entry.Won == true and "SIEG" or entry.Won == false and "NIEDERLAGE" or "UNENTSCHIEDEN"
				cells.Result.TextColor3 = entry.Won == true and GREEN or entry.Won == false and UITheme.Colors.Bad or GRAY
				cells.Mode.Text = tostring(entry.Mode or "")
				cells.Map.Text = tostring(entry.Map or "")
				cells.Map.TextColor3 = GRAY
				cells.Score.Text = tostring(entry.Score or "")
				cells.KD.Text = (entry.Kills or 0) .. " / " .. (entry.Deaths or 0)
				if entry.Elo then
					cells.Elo.Text = (entry.Elo >= 0 and "+" or "−") .. math.abs(entry.Elo)
					cells.Elo.TextColor3 = entry.Elo >= 0 and GREEN or UITheme.Colors.Bad
				end
			end
		end

		local stats = decodeAttribute(player, "Stats")
		local function get(key)
			return stats[key] or 0
		end
		tiles.KD.Text = string.format("%.2f", ratio(get("Kills"), get("Deaths")))
		tiles.Kills.Text = tostring(get("Kills"))
		tiles.Deaths.Text = tostring(get("Deaths"))
		tiles.Assists.Text = tostring(get("Assists"))
		tiles.WinRate.Text = percent(get("Wins"), get("Matches"))
		tiles.Matches.Text = tostring(get("Matches"))
		tiles.Wins.Text = tostring(get("Wins"))
		tiles.Clutches.Text = tostring(get("Clutches"))
		tiles.HSRate.Text = percent(get("Headshots"), get("Kills"))
		tiles.Accuracy.Text = percent(get("ShotsHit"), get("ShotsFired"))
		tiles.AvgDamage.Text = tostring(math.floor(ratio(get("Damage"), math.max(1, get("Matches")))))
		tiles.Revives.Text = tostring(get("Revives"))
		tiles.Captures.Text = tostring(get("Captures"))
		tiles.AvgKills.Text = string.format("%.1f", ratio(get("Kills"), math.max(1, get("Matches"))))
		tiles.BestStreak.Text = tostring(get("BestStreak"))
		local favorite, most = nil, 0
		for _, agent in AgentConfig.Agents do
			if get("Kills_" .. agent.Id) > most then
				favorite, most = agent, get("Kills_" .. agent.Id)
			end
		end
		tiles.Favorite.Text = favorite and favorite.Name or "–"
		tiles.Favorite.TextColor3 = favorite and favorite.Color or Color3.new(1, 1, 1)

		local ranked = decodeAttribute(player, "RankedData")
		local elo = player:GetAttribute("Elo") or RankConfig.StartElo
		local rank = RankConfig.Get(elo)
		local matches = ranked.Matches or 0
		statsRank:SetRank(rank)
		statsRankHolder.Visible = matches >= RankConfig.PlacementMatches
		if matches < RankConfig.PlacementMatches then
			rankName.Text = "PLATZIERUNG"
			rankName.TextColor3 = GRAY
			rankedInfo.Text = "Noch " .. (RankConfig.PlacementMatches - matches) .. " Platzierungsspiele bis zu deinem Rang."
		else
			rankName.Text = rank.Display
			rankName.TextColor3 = rank.Color
			rankedInfo.Text = "Peak: " .. (ranked.Peak or elo) .. " ELO  ·  " .. RankConfig.Get(ranked.Peak or elo).Display
		end
		eloText.Text = elo .. " ELO"
		bar.Size = UDim2.new(rank.Progress, 0, 1, 0)
		bar.BackgroundColor3 = rank.Color
		rankedInfo.Text ..= "\nGewertet: " .. (ranked.Wins or 0) .. " Siege · " .. (ranked.Losses or 0) .. " Niederlagen ("
			.. percent(ranked.Wins or 0, matches) .. ")"

		local lines = {}
		for i, entry in decodeAttribute(game:GetService("ReplicatedStorage"), "RankedLeaderboard") do
			local tier = RankConfig.Get(entry.Elo)
			local color = string.format("#%02X%02X%02X", tier.Color.R * 255, tier.Color.G * 255, tier.Color.B * 255)
			table.insert(lines, i .. ".  " .. tostring(entry.Name) .. '   <font color="' .. color .. '">' .. entry.Elo .. "</font>")
		end
		boardText.Text = #lines > 0 and table.concat(lines, "\n")
			or "Noch keine Einträge.\n(Die Bestenliste funktioniert im veröffentlichten Spiel.)"
	end
end

-- ---------- TÄGLICH ----------

local function dailyLeft()
	return (player:GetAttribute("LastDaily") or 0) + Cosmetics.DailyCooldown - os.time()
end

local function buildDaily()
	local frame = makePanel("Daily", "TÄGLICHE BELOHNUNG", 560, 330)
	text({ Position = UDim2.new(0, 24, 0, 80), Size = UDim2.new(1, -48, 0, 60),
		Text = Cosmetics.DailyReward .. " MÜNZEN", TextSize = 48, Font = Enum.Font.Oswald,
		TextColor3 = UITheme.Colors.Gold, TextXAlignment = Enum.TextXAlignment.Center }, frame)
	text({ Position = UDim2.new(0, 24, 0, 144), Size = UDim2.new(1, -48, 0, 24),
		Text = "Jeden Tag kostenlos abholen!", TextSize = 17, TextColor3 = GRAY,
		TextXAlignment = Enum.TextXAlignment.Center }, frame)
	local claim = button({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 196),
		Size = UDim2.new(0, 300, 0, 56), TextSize = 22, Text = "" }, frame, function()
		Remotes.ShopAction:FireServer("ClaimDaily")
	end)
	panels.Daily.Refresh = function()
		local left = dailyLeft()
		if left <= 0 then
			claim.Text = "ABHOLEN"
			claim.BackgroundColor3 = ACCENT
			claim.TextColor3 = ON_ACCENT
		else
			claim.Text = string.format("IN %d h %02d min", left // 3600, (left % 3600) // 60)
			claim.BackgroundColor3 = UITheme.Colors.MutedBack
			claim.TextColor3 = GRAY
		end
	end
end

-- ---------- CODES ----------

local function buildCodes()
	local frame = makePanel("Codes", "CODES", 560, 300)
	text({ Position = UDim2.new(0, 24, 0, 70), Size = UDim2.new(1, -48, 0, 24),
		Text = "Code eingeben und Belohnung abholen:", TextSize = 17, TextColor3 = GRAY }, frame)
	local box = make("TextBox", { Position = UDim2.new(0, 24, 0, 104), Size = UDim2.new(1, -48, 0, 50),
		BackgroundColor3 = CARD, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 22,
		TextColor3 = Color3.new(1, 1, 1), PlaceholderText = "CODE", PlaceholderColor3 = GRAY, Text = "",
		ClearTextOnFocus = false }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
	button({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 172), Size = UDim2.new(0, 260, 0, 52),
		TextSize = 20, Text = "EINLÖSEN", BackgroundColor3 = ACCENT, TextColor3 = ON_ACCENT }, frame, function()
		Remotes.ShopAction:FireServer("RedeemCode", box.Text)
	end)
end

-- ---------- BELOHNUNGEN ----------
-- Übersicht: was man pro Aktion bekommt, Killserien, Level-Meilensteine (dieser Prestige-Durchgang),
-- Prestige-Skins und Rang-Meilensteine der Saison. Erledigt = grün mit Haken, nächstes Ziel hervorgehoben.

local function buildRewards()
	local frame = makePanel("Rewards", "BELOHNUNGEN", 1120, 640)
	local COLUMN_W = 340
	local function column(x, title)
		text({ Position = UDim2.new(0, x, 0, 72), Size = UDim2.new(0, COLUMN_W, 0, 18), Text = title, TextSize = 13,
			Font = UITheme.Fonts.Bold, TextColor3 = GRAY }, frame)
		local list = make("ScrollingFrame", { Position = UDim2.new(0, x, 0, 96), Size = UDim2.new(0, COLUMN_W, 1, -150),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = BORDER,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, frame)
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		return list
	end
	local levelList = column(24, "LEVEL-MEILENSTEINE  ·  DIESER PRESTIGE-DURCHGANG")
	local specialList = column(390, "PRESTIGE  ·  RANG DIESER SAISON")
	local actionList = column(756, "PRO AKTION  ·  KILLSERIEN")

	-- Zeile: links Titel, rechts Belohnung, Farbe nach Zustand ("done", "next", "open")
	local function row(list, order, title, reward, state, accent)
		local r = make("Frame", { Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = CARD, LayoutOrder = order,
			BackgroundTransparency = state == "open" and 0.35 or 0.05 }, list)
		make("UICorner", { CornerRadius = UDim.new(0, UITheme.Radius.Small) }, r)
		local color = state == "done" and GREEN or (state == "next" and ACCENT or BORDER)
		make("UIStroke", { Color = color, Thickness = state == "next" and 1.5 or 1, Transparency = state == "open" and 0.6 or 0 }, r)
		make("Frame", { Size = UDim2.new(0, 3, 1, -12), Position = UDim2.new(0, 6, 0, 6), BackgroundColor3 = accent or color,
			BorderSizePixel = 0 }, r)
		text({ Position = UDim2.new(0, 18, 0, 4), Size = UDim2.new(0.5, -18, 1, -8), Text = title, TextSize = 18, Font = DISPLAY,
			TextColor3 = state == "open" and GRAY or UITheme.Colors.Text }, r)
		text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 4), Size = UDim2.new(0.55, 0, 1, -8),
			Text = (state == "done" and "✓  " or "") .. reward, TextSize = 13, Font = UITheme.Fonts.Bold, TextWrapped = true,
			TextColor3 = state == "done" and GREEN or (state == "next" and ACCENT or GRAY),
			TextXAlignment = Enum.TextXAlignment.Right }, r)
	end
	local function rewardText(entry)
		local parts = {}
		if entry.Coins then
			table.insert(parts, UITheme.FormatNumber(entry.Coins) .. " Münzen")
		end
		local item = entry.Item and Cosmetics.Get(entry.Item)
		if item then
			table.insert(parts, "Skin " .. item.Name)
		end
		return table.concat(parts, " + ")
	end
	local function clear(list)
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	panels.Rewards.Refresh = function()
		local claimed = decodeAttribute(player, "RewardsClaimed")
		local info = LevelConfig.Get(player)
		clear(levelList)
		local nextShown = false
		for i, milestone in RewardConfig.Level do
			local done = claimed["P" .. info.Prestige .. "_L" .. milestone.Level] == true
			local state = done and "done" or (not nextShown and "next" or "open")
			if not done then
				nextShown = true
			end
			row(levelList, i, "LEVEL " .. milestone.Level, rewardText(milestone), state,
				milestone.Item and Cosmetics.Rarities[Cosmetics.Get(milestone.Item).Rarity].Color or nil)
		end
		clear(specialList)
		local order = 0
		for _, milestone in RewardConfig.Prestige do
			order += 1
			local done = claimed["Prestige" .. milestone.Prestige] == true
			row(specialList, order, "PRESTIGE " .. milestone.Prestige, rewardText(milestone), done and "done" or "open",
				LevelConfig.PrestigeColors[milestone.Prestige])
		end
		for _, milestone in RewardConfig.Rank do
			order += 1
			local done = claimed["S" .. RankConfig.Season .. "_" .. milestone.Tier] == true
			local tierColor
			for _, tier in RankConfig.Tiers do
				if tier.Name == milestone.Tier then
					tierColor = tier.Color
				end
			end
			row(specialList, order, string.upper(milestone.Tier), rewardText(milestone), done and "done" or "open", tierColor)
		end
		clear(actionList)
		for i, entry in RewardConfig.PerAction do
			row(actionList, i, string.upper(entry[1]), entry[2], "open", ACCENT)
		end
		for i, streak in RewardConfig.Streaks do
			row(actionList, 100 + i, streak.Kills .. " KILLS IN FOLGE", UITheme.FormatNumber(streak.Coins) .. " Münzen", "open",
				Color3.fromRGB(206, 110, 80))
		end
	end
end

-- ---------- EINSTELLUNGEN ----------

-- Einstellungen im Profil speichern (kurz verzögert, damit nicht jeder Klick gesendet wird)
local saveToken = 0
local function saveSettings()
	saveToken += 1
	local myToken = saveToken
	task.delay(1, function()
		if myToken == saveToken then
			Remotes.ShopAction:FireServer("SaveSettings", {
				Fov = Movement.GetFov(),
				Sensitivity = Movement.GetSensitivity(),
				ThirdPerson = Movement.GetThirdPersonSetting(),
			})
		end
	end)
end

-- Gespeicherte Einstellungen einmal beim Laden übernehmen
local function loadSettings()
	local raw = player:GetAttribute("ClientSettings")
	if type(raw) ~= "string" then
		return false
	end
	local ok, data = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), raw)
	if not ok or type(data) ~= "table" or next(data) == nil then
		return false
	end
	Movement.SetFov(data.Fov or 70)
	Movement.SetSensitivity(data.Sensitivity or 1)
	Movement.SetThirdPerson(data.ThirdPerson == true)
	return true
end

local function buildSettings()
	local frame = makePanel("Settings", "EINSTELLUNGEN", 560, 380)
	local refreshers = {}
	local function settingRow(y, label, getValue, change)
		text({ Position = UDim2.new(0, 24, 0, y), Size = UDim2.new(0, 260, 0, 44), Text = label, TextSize = 18 }, frame)
		local value = text({ Position = UDim2.new(0, 360, 0, y), Size = UDim2.new(0, 80, 0, 44), Text = "",
			TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center }, frame)
		local function refresh()
			value.Text = tostring(getValue())
		end
		table.insert(refreshers, refresh)
		button({ Position = UDim2.new(0, 304, 0, y), Size = UDim2.new(0, 48, 0, 44), Text = "−", TextSize = 22,
			BackgroundColor3 = CARD }, frame, function()
			change(-1)
			refresh()
			saveSettings()
		end)
		button({ Position = UDim2.new(0, 448, 0, y), Size = UDim2.new(0, 48, 0, 44), Text = "+", TextSize = 22,
			BackgroundColor3 = CARD }, frame, function()
			change(1)
			refresh()
			saveSettings()
		end)
		refresh()
	end
	settingRow(90, "Sichtfeld (FOV)", function()
		return Movement.GetFov()
	end, function(direction)
		Movement.SetFov(math.clamp(Movement.GetFov() + direction * 5, 60, 100))
	end)
	settingRow(150, "Maus-Empfindlichkeit", function()
		return string.format("%.1f", Movement.GetSensitivity())
	end, function(direction)
		Movement.SetSensitivity(math.clamp(Movement.GetSensitivity() + direction * 0.1, 0.1, 3))
	end)
	settingRow(210, "Kamera (Kampf)", function()
		return Movement.GetThirdPersonSetting() and "Schulter" or "Ego"
	end, function()
		Movement.SetThirdPerson(not Movement.GetThirdPersonSetting())
	end)
	panels.Settings.Refresh = function()
		for _, refresh in refreshers do
			refresh()
		end
	end
end

-- ---------- Symbol-Knöpfe oben links (rund, unter der Spielerkarte, wie in vielen Roblox-Spielen) ----------

local ICON_SIZE, ICON_GAP, ICON_COLUMNS = 52, 10, 5
local CELL_HEIGHT = ICON_SIZE + 16 -- Platz für die Beschriftung darunter

local function sideButton(label, order, onClick, parent, color, icon)
	local cell = make("Frame", { Size = UDim2.new(0, ICON_SIZE, 0, CELL_HEIGHT), BackgroundTransparency = 1,
		LayoutOrder = order }, parent)
	local b = make("TextButton", { Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE), BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.1, BorderSizePixel = 0, Text = "", AutoButtonColor = false }, cell)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, b)
	local stroke = make("UIStroke", { Color = color or BORDER, Thickness = 1.5, Transparency = 0.45,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	make("TextLabel", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = icon or "", TextSize = 24,
		Font = UITheme.Fonts.Bold, TextColor3 = UITheme.Colors.Text }, b)
	local caption = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, ICON_SIZE + 2),
		Size = UDim2.new(0, ICON_SIZE + ICON_GAP, 0, 13), BackgroundTransparency = 1, Text = label, TextSize = 10,
		Font = UITheme.Fonts.Bold, TextColor3 = UITheme.Colors.Text, TextStrokeTransparency = 0.4 }, cell)
	local scale = make("UIScale", {}, b)
	b.MouseEnter:Connect(function()
		stroke.Transparency = 0
		caption.TextColor3 = color or ACCENT
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.1 }):Play()
	end)
	b.MouseLeave:Connect(function()
		stroke.Transparency = 0.45
		caption.TextColor3 = UITheme.Colors.Text
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	b.Activated:Connect(onClick)
	return b
end

local function togglePanel(name)
	setPanel(openPanel ~= name and name or nil)
end

-- Lobby auf einer Seite öffnen (SHOP, LOADOUT, AGENTEN, BATTLE PASS sind Seiten der Lobby, keine Fenster)
local function openLobby(page)
	setPanel(nil)
	GameMenu.Open(page)
end

local playerCard -- Spielerkarte oben links (Level, Prestige, Rang, Münzen)

local function buildPlayerCard()
	-- Fläche wie in der Lobby (runde Ecken, 2 px Rand, Schatten)
	playerCard = UITheme.Card({ Name = "PlayerCard", Position = UDim2.new(0, 16, 0, 64), Size = UDim2.new(0, 340, 0, 104),
		BackgroundTransparency = 0.06 }, gui)
	local accentStrip = make("Frame", { Size = UDim2.new(0, 0, 0, 0), BackgroundColor3 = ACCENT, BorderSizePixel = 0,
		Visible = false }, playerCard)

	-- Prestige-Abzeichen links (gleiches Symbol wie über dem Kopf)
	local emblemHolder = make("Frame", { Position = UDim2.new(0, 6, 0, 2), Size = UDim2.new(0, 84, 0, 84),
		BackgroundTransparency = 1 }, playerCard)
	local emblem = PrestigeEmblem.new(emblemHolder, 84)
	local levelCaption = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, 48, 0, 84),
		Size = UDim2.new(0, 90, 0, 16), Text = "LEVEL", TextSize = 11, Font = DISPLAY, TextColor3 = GRAY,
		TextXAlignment = Enum.TextXAlignment.Center }, playerCard)

	local nameLabel = text({ Position = UDim2.new(0, 92, 0, 10), Size = UDim2.new(1, -200, 0, 26), Text = player.Name,
		TextSize = 20, Font = DISPLAY, TextTruncate = Enum.TextTruncate.AtEnd }, playerCard)
	coinLabel = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.new(0, 110, 0, 24),
		Text = "", TextSize = 18, Font = DISPLAY, TextColor3 = UITheme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Right }, playerCard)
	local rankHolder = make("Frame", { Position = UDim2.new(0, 90, 0, 36), Size = UDim2.new(0, 24, 0, 24),
		BackgroundTransparency = 1 }, playerCard)
	local cardRank = RankEmblem.new(rankHolder, 24)
	local rankLabel = text({ Position = UDim2.new(0, 118, 0, 38), Size = UDim2.new(1, -130, 0, 20), Text = "",
		TextSize = 16, Font = UITheme.Fonts.Title, RichText = true }, playerCard)
	local barBack = make("Frame", { Position = UDim2.new(0, 92, 0, 67), Size = UDim2.new(1, -104, 0, 5),
		BackgroundColor3 = UITheme.Colors.Background, BorderSizePixel = 0 }, playerCard)
	local bar = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, barBack)
	local xpLabel = text({ Position = UDim2.new(0, 92, 0, 78), Size = UDim2.new(1, -104, 0, 18), Text = "", TextSize = 13,
		Font = UITheme.Fonts.Body, TextColor3 = GRAY }, playerCard)

	-- Prestige-Knopf (nur auf Max-Level), zweimal klicken zum Bestätigen
	local prestigeButton = UITheme.Button({ AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 0, 1, 12),
		Size = UDim2.new(1, 0, 0, 44), Text = "PRESTIGE", TextSize = 18, BackgroundColor3 = UITheme.Colors.Play,
		TextColor3 = ON_ACCENT, Visible = false }, playerCard)
	local confirmUntil = 0
	prestigeButton.Activated:Connect(function()
		if os.clock() < confirmUntil then
			confirmUntil = 0
			Remotes.ShopAction:FireServer("Prestige")
		else
			confirmUntil = os.clock() + 4
			prestigeButton.Text = "SICHER? LEVEL WIRD 1  ·  NOCHMAL KLICKEN"
			task.delay(4, function()
				if os.clock() >= confirmUntil then
					prestigeButton.Text = "PRESTIGE"
				end
			end)
		end
	end)

	local function refresh()
		local info = LevelConfig.Get(player)
		emblem:Set(info.Level, info.Prestige)
		accentStrip.BackgroundColor3 = info.Color
		bar.BackgroundColor3 = info.Color
		levelCaption.Text = info.Prestige > 0 and ("PRESTIGE " .. info.Prestige) or "LEVEL"
		levelCaption.TextColor3 = info.Prestige > 0 and info.Color or GRAY
		local elo = player:GetAttribute("Elo") or RankConfig.StartElo
		local rank = RankConfig.Get(elo)
		cardRank:SetRank(rank)
		local color = string.format("#%02X%02X%02X", rank.Color.R * 255, rank.Color.G * 255, rank.Color.B * 255)
		rankLabel.Text = '<font color="' .. color .. '">' .. rank.Display .. "</font>   ·   " .. elo .. " ELO"
		bar.Size = UDim2.new(info.Progress, 0, 1, 0)
		xpLabel.Text = info.Needed > 0 and (formatNumber(info.XP) .. " / " .. formatNumber(info.Needed) .. " XP")
			or (info.CanPrestige and "MAX-LEVEL – bereit für Prestige!" or "MAX-LEVEL")
		prestigeButton.Visible = info.CanPrestige
		-- Symbol-Knöpfe rutschen unter den Prestige-Knopf, solange er da ist
		if column then
			column.Position = UDim2.new(0, 16, 0, info.CanPrestige and 236 or 180)
		end
		coinLabel.Text = formatNumber(coins()) .. " MÜNZEN"
		nameLabel.Text = player.Name
	end
	refresh()
	player.AttributeChanged:Connect(function(name)
		if name == "AccountXP" or name == "Prestige" or name == "Elo" or name == "Coins" then
			refresh()
		end
	end)
end

local function buildColumn()
	-- Reihe 1: Ausrüstung und Fortschritt, Reihe 2: Belohnungen, Statistik, Einstellungen
	local entries = {
		{ "SHOP", function() openLobby("Shop") end, Color3.fromRGB(212, 170, 80), "🛒" },
		{ "LOADOUT", function() openLobby("Inventory") end, Color3.fromRGB(96, 164, 214), "🎒" },
		{ "AGENTEN", function() openLobby("Agents") end, Color3.fromRGB(150, 120, 210), "🦸" },
		{ "PASS", function() openLobby("Pass") end, Color3.fromRGB(212, 170, 80), "🎫" },
		{ "SQUAD", function() togglePanel("Squad") end, Color3.fromRGB(112, 178, 112), "👥" },
		{ "AUFTRÄGE", function() togglePanel("Quests") end, Color3.fromRGB(206, 110, 80), "📋" },
		{ "TÄGLICH", function() togglePanel("Daily") end, Color3.fromRGB(206, 110, 150), "🎁" },
		{ "STATS", function() togglePanel("Stats") end, Color3.fromRGB(96, 164, 214), "📊" },
		{ "BELOHNUNG", function() togglePanel("Rewards") end, Color3.fromRGB(212, 170, 80), "🏅" },
		{ "CODES", function() togglePanel("Codes") end, Color3.fromRGB(112, 178, 160), "🎟" },
		{ "OPTIONEN", function() togglePanel("Settings") end, Color3.fromRGB(134, 142, 152), "⚙" },
	}
	local rows = math.ceil(#entries / ICON_COLUMNS)
	local width = ICON_COLUMNS * ICON_SIZE + (ICON_COLUMNS - 1) * ICON_GAP
	local height = rows * CELL_HEIGHT + (rows - 1) * 6
	-- direkt unter der Spielerkarte (oben links bei y 64, 104 hoch)
	column = make("Frame", { Position = UDim2.new(0, 16, 0, 180), Size = UDim2.new(0, width, 0, height),
		BackgroundTransparency = 1 }, gui)
	make("UIGridLayout", { CellSize = UDim2.new(0, ICON_SIZE, 0, CELL_HEIGHT), CellPadding = UDim2.new(0, ICON_GAP, 0, 6),
		FillDirectionMaxCells = ICON_COLUMNS, SortOrder = Enum.SortOrder.LayoutOrder }, column)
	-- Auf kleinen Bildschirmen etwas verkleinern
	local columnScale = make("UIScale", {}, column)
	local function updateColumnScale()
		columnScale.Scale = math.clamp(workspace.CurrentCamera.ViewportSize.Y / 800, 0.6, 1)
	end
	updateColumnScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateColumnScale)
	local daily, quests
	for i, entry in entries do
		local b = sideButton(entry[1], i, entry[2], column, entry[3], entry[4])
		if entry[1] == "TÄGLICH" then
			daily = b
		elseif entry[1] == "AUFTRÄGE" then
			quests = b
		end
	end
	-- Kleiner Punkt "!" am Knopf, wenn ein Auftrag bzw. die tägliche Belohnung bereit ist
	local function notifyDot(parent)
		local dot = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.new(0, 18, 0, 18), BackgroundColor3 = ACCENT, BorderSizePixel = 0,
			Text = "!", TextSize = 13, Font = UITheme.Fonts.Bold, TextColor3 = ON_ACCENT, ZIndex = 3 }, parent)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
		return dot
	end
	questDot = notifyDot(quests)
	dailyDot = notifyDot(daily)

	buildPlayerCard()
	column:GetPropertyChangedSignal("Visible"):Connect(function()
		playerCard.Visible = column.Visible
	end)
end

-- ---------- Start ----------

function SideMenu.Init()
	gui = make("ScreenGui", { Name = "SideMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	-- Die Lobby öffnet dieselben Fenster (Navigation, Squad, Battle Pass, Auftrag, Symbole)
	GameMenu.SetPanelHandler(function(name)
		setPanel(name)
	end)
	buildColumn()
	buildSquad()
	buildStats()
	buildQuests()
	buildDaily()
	buildCodes()
	buildSettings()
	buildRewards()

	-- Gespeicherte Einstellungen übernehmen, sobald das Profil geladen ist
	if not loadSettings() then
		local connection
		connection = player:GetAttributeChangedSignal("ClientSettings"):Connect(function()
			if loadSettings() then
				connection:Disconnect()
			end
		end)
	end

	-- Rückmeldung vom Server in das offene Fenster
	Remotes.ShopStatus.OnClientEvent:Connect(function(message, success)
		for _, panel in panels do
			panel.Status.Text = message
			panel.Status.TextColor3 = success and Color3.fromRGB(120, 230, 140) or Color3.fromRGB(255, 120, 120)
		end
	end)
	-- Münzen, Besitz, Ausrüstung geändert: offenes Fenster aktualisieren
	player.AttributeChanged:Connect(function(name)
		if name == "Coins" or name == "Owned" or name == "Equipped" or name == "LastDaily" or name == "Quests" or name == "Weekly"
			or name == "PassXP" or name == "Stats" or name == "Elo" or name == "RankedData" or name == "Party"
			or name == "MatchHistory" or name == "RewardsClaimed" or name == "AccountXP" or name == "Prestige" then
			if openPanel and panels[openPanel].Refresh then
				panels[openPanel].Refresh()
			end
		end
	end)
	coinLabel.Text = formatNumber(coins()) .. " MÜNZEN"

	-- Menüliste nur im Hub bei geschlossener Lobby; Fenster im Hub oder aus der Lobby heraus
	task.spawn(function()
		while true do
			local inHub = player:GetAttribute("Mode") == "Hub"
			local lobby = GameMenu.IsOpen()
			column.Visible = inHub and not lobby
			if openPanel and not (inHub or lobby) then
				setPanel(nil)
			end
			dailyDot.Visible = dailyLeft() <= 0
			questDot.Visible = questReady()
			if openPanel == "Daily" then
				panels.Daily.Refresh()
			end
			task.wait(0.25)
		end
	end)
end

return SideMenu

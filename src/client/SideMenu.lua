-- SideMenu (ModuleScript, nur Client)
-- Menüliste links im Hub und im Markt: SHOP, LOADOUT, AGENTEN, BATTLE PASS, AUFTRÄGE, TÄGLICH, SQUAD, MARKT
-- (in die Markthalle bzw. von dort zurück: ZUM HUB), CLAN, STATISTIK, CODES, OPTIONEN, darüber die Spielerkarte
-- (Level, Prestige, Rang, Münzen, RAP).
-- SHOP, LOADOUT, AGENTEN und BATTLE PASS öffnen die Lobby (GameMenu) auf der passenden Seite; Aufträge,
-- Täglich, Squad, Statistik, Codes und Optionen sind Fenster in der Mitte – dieselben Fenster öffnet auch die
-- Lobby (Squad, Auftrag, Knöpfe oben rechts). Design wie die Lobby (UITheme, nüchterner Taktik-Look):
-- dunkle Flächen mit 1 px Rand, flache Knöpfe, Bernstein für aktiv. Kaufen/Ausrüsten prüft der Server (ShopService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.Cosmetics)
local AgentConfig = require(Shared.AgentConfig)
local GameMenu = require(Shared.GameMenu)
local UITheme = require(Shared.UITheme)
local QuestConfig = require(Shared.QuestConfig)
local RankConfig = require(Shared.RankConfig)
local RankEmblem = require(Shared.RankEmblem)
local LevelConfig = require(Shared.LevelConfig)
local RewardConfig = require(Shared.RewardConfig)
local InputActions = require(Shared.InputActions)
local LoginConfig = require(Shared.LoginConfig)
local PlayerSettings = require(Shared.PlayerSettings)
local HitFeedback = require(Shared.HitFeedback)
local TitleConfig = require(Shared.TitleConfig)
local PrestigeEmblem = require(Shared.PrestigeEmblem)
local Modes = require(Shared.Modes)
local QuestBoard = require(script.Parent:WaitForChild("QuestBoard"))
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
	props.Font = UITheme.FontFor(props.Font or Enum.Font.BuilderSansBold, props.TextSize)
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

-- Fertiger, nicht abgeholter Auftrag (Arcade, Extinction, VIP & BOOSTER) oder Wochen-Bonus? (Punkt am Knopf)
local function questReady()
	return QuestBoard.Ready()
end

-- Fenster AUFTRÄGE: Inhalt baut QuestBoard (Reiter ARCADE / EXTINCTION, Spalten Täglich, Wöchentlich, VIP & BOOSTER)
local function buildQuests()
	local width, height = 1180, 660
	local frame = makePanel("Quests", "AUFTRÄGE", width, height)
	local board = QuestBoard.new(frame, width - 48, height - 64 - 48, { Mode = "Arcade" })
	board.Frame.Position = UDim2.fromOffset(24, 64)
	panels.Quests.Refresh = function()
		board.Refresh()
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

	-- Einladung (erscheint überall außerhalb der offenen Welt; dort ist die Maus im Spiel gefangen, die Einladung nimmt man
	-- im Squad-Fenster an, siehe ExtinctionClient)
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
		if Modes.IsSurvival(player:GetAttribute("Mode")) then
			return
		end
		inviteId += 1
		local myId = inviteId
		inviter = userId
		inviteText.Text = name .. " lädt dich in den Squad ein."
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

-- Seite der Lobby statt Fenster (wie BATTLE PASS): Titel groß oben links, Unterzeile, Inhalt auf PAGE_W x PAGE_H.
-- Meldungen des Servers zeigt die Lobby in ihrer Statuszeile.
local function makePage(name, title, subtitle)
	local entry = GameMenu.AddPage(name)
	local frame = entry.Frame
	text({ Position = UDim2.new(0, 0, 0, -4), Size = UDim2.new(0, 900, 0, 46), Text = title, TextSize = 42, Font = DISPLAY }, frame)
	text({ Position = UDim2.new(0, 0, 0, 44), Size = UDim2.new(0, 900, 0, 16), Text = subtitle or "", TextSize = 11,
		TextColor3 = GRAY }, frame)
	return frame, entry
end

local function buildStats()
	local frame, page = makePage("Stats", "STATISTIK", "DEINE WERTE ÜBER ALLE MODI  ·  RANG  ·  LETZTE MATCHES")
	-- Linke Seite: Kacheln
	local grid = make("Frame", { Position = UDim2.new(0, 0, 0, 72), Size = UDim2.new(0, 744, 0, 376),
		BackgroundTransparency = 1 }, frame)
	make("UIGridLayout", { CellSize = UDim2.new(0, 178, 0, 86), CellPadding = UDim2.new(0, 10, 0, 10),
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
		UITheme.AccentBar(tile, (key == "KD" or key == "WinRate") and ACCENT or BORDER, { Side = "Left" })
		text({ Position = UDim2.new(0, 14, 0, 10), Size = UDim2.new(1, -20, 0, 16), Text = titles[key], TextSize = 11,
			TextColor3 = GRAY }, tile)
		tiles[key] = text({ Position = UDim2.new(0, 14, 0, 30), Size = UDim2.new(1, -20, 0, 40), Text = "–", TextSize = 30,
			Font = UITheme.Fonts.Title, TextScaled = false }, tile)
	end

	-- Rechte Seite: Ranked
	local rankedBox = make("Frame", { Position = UDim2.new(0, 768, 0, 72), Size = UDim2.new(0, 752, 0, 230),
		BackgroundColor3 = CARD }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, rankedBox)
	local seasonText = text({ Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 18), Text = "",
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
	local board = make("Frame", { Position = UDim2.new(0, 768, 0, 314), Size = UDim2.new(0, 752, 0, 416),
		BackgroundColor3 = CARD }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, board)
	text({ Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 18), Text = "TOP 10 · ELO", TextSize = 13,
		TextColor3 = ACCENT }, board)
	local boardText = text({ Position = UDim2.new(0, 16, 0, 34), Size = UDim2.new(1, -32, 1, -44), Text = "", TextSize = 15,
		Font = UITheme.Fonts.Body, TextYAlignment = Enum.TextYAlignment.Top, RichText = true }, board)

	-- Match-Verlauf (letzte 10 Matches)
	local history = make("Frame", { Position = UDim2.new(0, 0, 0, 460), Size = UDim2.new(0, 744, 0, 270),
		BackgroundColor3 = CARD }, frame)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, history)
	text({ Position = UDim2.new(0, 16, 0, 8), Size = UDim2.new(1, -32, 0, 18), Text = "LETZTE MATCHES", TextSize = 13,
		TextColor3 = ACCENT }, history)
	local COLUMNS = { { "Result", 0, 130 }, { "Mode", 130, 170 }, { "Map", 300, 150 }, { "Score", 450, 90 },
		{ "KD", 540, 90 }, { "Elo", 630, 80 } }
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

	page.Watch = { Stats = true, Elo = true, RankedData = true, MatchHistory = true }
	page.Refresh = function()
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
		seasonText.Text = "ELO · SAISON " .. RankConfig.CurrentSeason() .. "  ·  ENDET IN " .. RankConfig.FormatLeft(RankConfig.SeasonLeft())
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

-- Login-Kalender: kann heute abgeholt werden?
local function loginClaimable()
	return LoginConfig.CanClaim(decodeAttribute(player, "LoginData"), workspace:GetServerTimeNow())
end

local function rewardLines(reward)
	local lines = {}
	if reward.Coins then
		table.insert(lines, formatNumber(reward.Coins) .. " Münzen")
	end
	if reward.BoostMinutes then
		table.insert(lines, reward.BoostMinutes .. " Min. 2× XP")
	end
	if reward.Spins then
		table.insert(lines, "+" .. reward.Spins .. " Glücksrad")
	end
	if reward.Item then
		local item = Cosmetics.Get(reward.Item)
		table.insert(lines, item and ("Skin " .. item.Name) or "Skin")
	end
	return table.concat(lines, "\n")
end

local function buildDaily()
	local frame = makePanel("Daily", "LOGIN-BONUS", 940, 380)
	text({ Position = UDim2.new(0, 24, 0, 62), Size = UDim2.new(1, -48, 0, 20),
		Text = "Jeden Tag abholen – wer dranbleibt, rückt weiter. Einen Tag verpasst = zurück auf Tag 1.", TextSize = 15,
		Font = UITheme.Fonts.Body, TextColor3 = GRAY }, frame)
	local row = make("Frame", { Position = UDim2.new(0, 24, 0, 96), Size = UDim2.new(1, -48, 0, 170),
		BackgroundTransparency = 1 }, frame)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local cards = {}
	for day, reward in LoginConfig.Days do
		local big = day == #LoginConfig.Days
		local card = make("Frame", { Size = UDim2.new(0, big and 152 or 108, 1, 0), BackgroundColor3 = CARD, LayoutOrder = day }, row)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
		local stroke = make("UIStroke", { Color = BORDER, Thickness = 1.5 }, card)
		text({ Position = UDim2.new(0, 0, 0, 10), Size = UDim2.new(1, 0, 0, 18), Text = "TAG " .. day, TextSize = 14,
			Font = DISPLAY, TextColor3 = GRAY, TextXAlignment = Enum.TextXAlignment.Center }, card)
		local coin = UITheme.Coin(card, big and 34 or 26, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 38) })
		local info = text({ Position = UDim2.new(0, 6, 0, big and 80 or 72), Size = UDim2.new(1, -12, 0, 54),
			Text = rewardLines(reward), TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top }, card)
		local state = text({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -8), Size = UDim2.new(1, 0, 0, 16),
			Text = "", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center }, card)
		cards[day] = { Card = card, Stroke = stroke, State = state, Info = info, Coin = coin }
	end
	local claim = button({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 284),
		Size = UDim2.new(0, 320, 0, 52), TextSize = 20, Text = "" }, frame, function()
		Remotes.ShopAction:FireServer("ClaimDaily")
	end)
	panels.Daily.Refresh = function()
		local now = workspace:GetServerTimeNow()
		local data = decodeAttribute(player, "LoginData")
		local claimable = LoginConfig.CanClaim(data, now)
		local today = claimable and LoginConfig.NextDay(data, now) or (data.Day or 1)
		for day, entry in cards do
			local done = day < today or (not claimable and day == today)
			local current = day == today
			entry.Card.BackgroundColor3 = current and UITheme.Colors.Secondary or CARD
			entry.Stroke.Color = done and GREEN or (current and ACCENT or BORDER)
			entry.State.Text = done and "✓ ABGEHOLT" or (current and "HEUTE" or "")
			entry.State.TextColor3 = done and GREEN or ACCENT
		end
		if claimable then
			claim.Text = "TAG " .. today .. " ABHOLEN"
			claim.BackgroundColor3 = ACCENT
			claim.TextColor3 = ON_ACCENT
		else
			local left = 86400 - math.floor(now) % 86400
			claim.Text = string.format("MORGEN WIEDER (%d h %02d min)", left // 3600, (left % 3600) // 60)
			claim.BackgroundColor3 = UITheme.Colors.MutedBack
			claim.TextColor3 = GRAY
		end
	end
end

-- ---------- CLAN ----------
-- Ohne Clan: gründen (Name, Kürzel, kostet Münzen) oder per Kürzel beitreten. Im Clan: Name, Mitglieder (Leiter mit
-- Krone, online-Punkt, Entfernen für den Leiter) und Verlassen (zweimal klicken). Daten: Spieler-Attribute ClanTag,
-- ClanName, ClanData (ClanService).

local CLAN_COST = 2500

local function buildClan()
	local frame = makePanel("Clan", "CLAN", 860, 560)
	local function box(parent, y, placeholder, maxLength)
		local textBox = make("TextBox", { Position = UDim2.new(0, 20, 0, y), Size = UDim2.new(1, -40, 0, 46),
			BackgroundColor3 = UITheme.Colors.Background, BorderSizePixel = 0, Font = Enum.Font.BuilderSansBold, TextSize = 20,
			TextColor3 = Color3.new(1, 1, 1), PlaceholderText = placeholder, PlaceholderColor3 = GRAY, Text = "",
			ClearTextOnFocus = false }, parent)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, textBox)
		textBox:GetPropertyChangedSignal("Text"):Connect(function()
			if #textBox.Text > maxLength then
				textBox.Text = string.sub(textBox.Text, 1, maxLength)
			end
		end)
		return textBox
	end

	-- Ohne Clan
	local noClan = make("Frame", { Position = UDim2.new(0, 24, 0, 70), Size = UDim2.new(1, -48, 1, -120),
		BackgroundTransparency = 1 }, frame)
	local create = make("Frame", { Size = UDim2.new(0.5, -10, 1, 0), BackgroundColor3 = CARD }, noClan)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, create)
	text({ Position = UDim2.new(0, 20, 0, 16), Size = UDim2.new(1, -40, 0, 28), Text = "CLAN GRÜNDEN", TextSize = 24,
		Font = DISPLAY }, create)
	text({ Position = UDim2.new(0, 20, 0, 46), Size = UDim2.new(1, -40, 0, 18), Text = "Du wirst Leiter. Max. 20 Mitglieder.",
		TextSize = 13, Font = UITheme.Fonts.Body, TextColor3 = GRAY }, create)
	local nameBox = box(create, 82, "CLAN-NAME (3–20 Zeichen)", 20)
	local tagBox = box(create, 140, "KÜRZEL (2–4, z.B. ABC)", 4)
	button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.new(1, -40, 0, 50),
		TextSize = 18, Text = "GRÜNDEN  ·  " .. formatNumber(CLAN_COST) .. " MÜNZEN", BackgroundColor3 = ACCENT,
		TextColor3 = ON_ACCENT }, create, function()
		Remotes.ShopAction:FireServer("CreateClan", nameBox.Text, tagBox.Text)
	end)
	local join = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.5, -10, 1, 0),
		BackgroundColor3 = CARD }, noClan)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, join)
	text({ Position = UDim2.new(0, 20, 0, 16), Size = UDim2.new(1, -40, 0, 28), Text = "CLAN BEITRETEN", TextSize = 24,
		Font = DISPLAY }, join)
	text({ Position = UDim2.new(0, 20, 0, 46), Size = UDim2.new(1, -40, 0, 18), Text = "Frag deine Freunde nach ihrem Kürzel.",
		TextSize = 13, Font = UITheme.Fonts.Body, TextColor3 = GRAY }, join)
	local joinBox = box(join, 82, "KÜRZEL", 4)
	button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.new(1, -40, 0, 50),
		TextSize = 18, Text = "BEITRETEN", BackgroundColor3 = UITheme.Colors.Accent, TextColor3 = ON_ACCENT }, join, function()
		Remotes.ShopAction:FireServer("JoinClan", joinBox.Text)
	end)

	-- Im Clan
	local inClan = make("Frame", { Position = UDim2.new(0, 24, 0, 66), Size = UDim2.new(1, -48, 1, -116),
		BackgroundTransparency = 1, Visible = false }, frame)
	local clanTitle = text({ Size = UDim2.new(1, -220, 0, 44), Text = "", TextSize = 36, Font = DISPLAY, RichText = true }, inClan)
	local clanInfo = text({ Position = UDim2.new(0, 0, 0, 44), Size = UDim2.new(1, -220, 0, 18), Text = "", TextSize = 13,
		TextColor3 = GRAY }, inClan)
	local confirmLeave = 0
	local leave
	leave = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 6), Size = UDim2.new(0, 200, 0, 44),
		TextSize = 15, Text = "CLAN VERLASSEN", BackgroundColor3 = UITheme.Colors.MutedBack, TextColor3 = UITheme.Colors.Bad },
		inClan, function()
			if os.clock() < confirmLeave then
				confirmLeave = 0
				Remotes.ShopAction:FireServer("LeaveClan")
			else
				confirmLeave = os.clock() + 4
				leave.Text = "WIRKLICH? NOCHMAL"
				task.delay(4, function()
					leave.Text = "CLAN VERLASSEN"
				end)
			end
		end)
	local list = make("ScrollingFrame", { Position = UDim2.new(0, 0, 0, 76), Size = UDim2.new(1, 0, 1, -76),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = BORDER,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, inClan)
	make("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 46), CellPadding = UDim2.new(0, 12, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder }, list)

	panels.Clan.Refresh = function()
		local tag = player:GetAttribute("ClanTag")
		noClan.Visible = tag == nil
		inClan.Visible = tag ~= nil
		if not tag then
			return
		end
		local data = decodeAttribute(player, "ClanData")
		local members = data.Members or {}
		local total = 0
		for _ in members do
			total += 1
		end
		clanTitle.Text = '<font color="#8FC3FF">[' .. tag .. ']</font>  ' .. tostring(player:GetAttribute("ClanName") or "")
		clanInfo.Text = total .. " / 20 MITGLIEDER  ·  KÜRZEL ZUM BEITRETEN: " .. tag
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local isLeader = data.Owner == player.UserId
		local order = 0
		for id, name in members do
			order += 1
			local userId = tonumber(id)
			local leader = userId == data.Owner
			local online = Players:GetPlayerByUserId(userId or 0) ~= nil
			local row = make("Frame", { BackgroundColor3 = CARD, LayoutOrder = leader and 0 or order }, list)
			make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
			local dot = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.new(0, 8, 0, 8),
				BackgroundColor3 = online and GREEN or BORDER }, row)
			make("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
			text({ Position = UDim2.new(0, 32, 0, 0), Size = UDim2.new(1, -150, 1, 0), Text = (leader and "👑  " or "") .. tostring(name),
				TextSize = 16, TextColor3 = userId == player.UserId and ACCENT or UITheme.Colors.Text,
				TextTruncate = Enum.TextTruncate.AtEnd }, row)
			if isLeader and userId ~= player.UserId then
				button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0, 100, 0, 32),
					TextSize = 12, Text = "ENTFERNEN", BackgroundColor3 = UITheme.Colors.MutedBack, TextColor3 = UITheme.Colors.Bad },
					row, function()
						Remotes.ShopAction:FireServer("KickClanMember", userId)
					end)
			elseif leader then
				text({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0, 90, 0, 20),
					Text = "LEITER", TextSize = 12, TextColor3 = UITheme.Colors.Gold, TextXAlignment = Enum.TextXAlignment.Right }, row)
			end
		end
	end
end

-- ---------- CODES ----------

local function buildCodes()
	local frame = makePage("Codes", "CODES", "CODE EINGEBEN UND BELOHNUNG ABHOLEN  ·  JEDER CODE EINMAL PRO SPIELER")
	-- Karte mittig: Eingabe und Knopf
	local card = UITheme.Card({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.new(0, 620, 0, 260), BackgroundTransparency = 0.1 }, frame)
	text({ Position = UDim2.new(0, 32, 0, 28), Size = UDim2.new(1, -64, 0, 30), Text = "CODE EINLÖSEN", TextSize = 28,
		Font = DISPLAY }, card)
	text({ Position = UDim2.new(0, 32, 0, 62), Size = UDim2.new(1, -64, 0, 20),
		Text = "Neue Codes gibt es bei Updates und Events.", TextSize = 15, Font = UITheme.Fonts.Body, TextColor3 = GRAY }, card)
	local box = make("TextBox", { Position = UDim2.new(0, 32, 0, 100), Size = UDim2.new(1, -64, 0, 56),
		BackgroundColor3 = UITheme.Colors.Background, BorderSizePixel = 0, Font = Enum.Font.BuilderSansBold, TextSize = 24,
		TextColor3 = Color3.new(1, 1, 1), PlaceholderText = "CODE", PlaceholderColor3 = GRAY, Text = "",
		ClearTextOnFocus = false }, card)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
	make("UIStroke", { Color = BORDER, Transparency = 0.2 }, box)
	local function redeem()
		if box.Text ~= "" then
			Remotes.ShopAction:FireServer("RedeemCode", box.Text)
		end
	end
	box.FocusLost:Connect(function(enter)
		if enter then
			redeem()
		end
	end)
	button({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 178), Size = UDim2.new(0, 280, 0, 54),
		TextSize = 20, Text = "EINLÖSEN", BackgroundColor3 = ACCENT, TextColor3 = ON_ACCENT }, card, redeem)
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
	local specialList = column(390, "PRESTIGE  ·  RANG DIESER SAISON  ·  SAISON-ENDE")
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
			local done = claimed["S" .. RankConfig.CurrentSeason() .. "_" .. milestone.Tier] == true
			local tierColor
			for _, tier in RankConfig.Tiers do
				if tier.Name == milestone.Tier then
					tierColor = tier.Color
				end
			end
			row(specialList, order, string.upper(milestone.Tier), rewardText(milestone), done and "done" or "open", tierColor)
		end
		-- Saison-Ende: was es für den höchsten Rang der laufenden Saison gibt (aktueller Peak hervorgehoben)
		local peakTier = RankConfig.Get(decodeAttribute(player, "RankedData").Peak or RankConfig.StartElo).Name
		for _, entry in RewardConfig.SeasonEnd do
			order += 1
			local tierColor
			for _, tier in RankConfig.Tiers do
				if tier.Name == entry.Tier then
					tierColor = tier.Color
				end
			end
			row(specialList, order, "ENDE · " .. string.upper(entry.Tier), rewardText(entry),
				entry.Tier == peakTier and "next" or "open", tierColor)
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

-- ---------- TITEL ----------
-- Alle Titel als Karten: freigeschaltete zuerst (anklicken = auswählen), gesperrte mit Fortschritt.

local function buildTitles()
	local frame = makePanel("Titles", "TITEL", 1000, 620)
	local current = text({ Position = UDim2.new(0, 24, 0, 62), Size = UDim2.new(1, -48, 0, 22), Text = "", TextSize = 16,
		TextColor3 = GRAY, RichText = true }, frame)
	local grid = make("ScrollingFrame", { Position = UDim2.new(0, 24, 0, 96), Size = UDim2.new(1, -48, 1, -140),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = BORDER,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, frame)
	make("UIGridLayout", { CellSize = UDim2.new(0, 306, 0, 84), CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)

	panels.Titles.Refresh = function()
		for _, child in grid:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local data = TitleConfig.DataFromPlayer(player)
		local selected = TitleConfig.Get(player:GetAttribute("Title") or "") or TitleConfig.Get(TitleConfig.Default)
		current.Text = 'AUSGEWÄHLT: <font color="#' .. selected.Color:ToHex() .. '">' .. UITheme.Upper(selected.Name)
			.. "</font>   ·   steht unter deinem Namen über dem Kopf"
		for i, title in TitleConfig.List do
			local value, goal = TitleConfig.Progress(title, data)
			local unlocked = value >= goal
			local isOn = title.Id == selected.Id
			local card = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = CARD,
				BackgroundTransparency = unlocked and 0.05 or 0.45, LayoutOrder = (unlocked and 0 or 100) + i }, grid)
			make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
			make("UIStroke", { Color = isOn and UITheme.Colors.Primary or (unlocked and title.Color or BORDER),
				Thickness = isOn and 2 or 1, Transparency = isOn and 0 or (unlocked and 0.4 or 0.6) }, card)
			make("Frame", { Position = UDim2.new(0, 8, 0, 10), Size = UDim2.new(0, 3, 1, -20),
				BackgroundColor3 = unlocked and title.Color or BORDER, BorderSizePixel = 0 }, card)
			text({ Position = UDim2.new(0, 22, 0, 8), Size = UDim2.new(1, -120, 0, 28), Text = UITheme.Upper(title.Name),
				TextSize = 22, Font = DISPLAY, TextColor3 = unlocked and title.Color or GRAY,
				TextTruncate = Enum.TextTruncate.AtEnd }, card)
			text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.new(0, 96, 0, 16),
				Text = isOn and "AUSGEWÄHLT" or (unlocked and "AUSWÄHLEN" or "GESPERRT"), TextSize = 11,
				TextColor3 = isOn and UITheme.Colors.Primary or (unlocked and UITheme.Colors.Text or GRAY),
				TextXAlignment = Enum.TextXAlignment.Right }, card)
			text({ Position = UDim2.new(0, 22, 0, 38), Size = UDim2.new(1, -34, 0, 16), Text = title.Text, TextSize = 13,
				Font = UITheme.Fonts.Body, TextColor3 = GRAY }, card)
			if not unlocked then
				local barBack = make("Frame", { Position = UDim2.new(0, 22, 0, 64), Size = UDim2.new(1, -120, 0, 4),
					BackgroundColor3 = BORDER, BorderSizePixel = 0 }, card)
				make("Frame", { Size = UDim2.new(math.clamp(value / goal, 0, 1), 0, 1, 0), BackgroundColor3 = title.Color,
					BorderSizePixel = 0 }, barBack)
				text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 58), Size = UDim2.new(0, 90, 0, 16),
					Text = formatNumber(math.min(value, goal)) .. " / " .. formatNumber(goal), TextSize = 12,
					TextColor3 = GRAY, TextXAlignment = Enum.TextXAlignment.Right }, card)
			end
			card.Activated:Connect(function()
				if unlocked and not isOn then
					Remotes.ShopAction:FireServer("SetTitle", title.Id)
				end
			end)
		end
	end
end

-- ---------- OPTIONEN ----------
-- Seite der Lobby aus PlayerSettings.List: Karten je Kategorie in zwei Spalten (Steuerung, Anzeige, Ton links;
-- Kamera, Treffer rechts), je Einstellung eine Zeile mit Schieberegler (ziehen oder − / +), Schalter oder
-- Auswahl-Knöpfen. Unter TREFFER eine Vorschau (HitFeedback.Preview): Puppe mit Fadenkreuz, auf die eine
-- Trefferfolge mit dem gewählten Hitmarker und den gewählten Schadenszahlen läuft. Speichert automatisch.

local function buildSettings()
	local frame, page = makePage("Settings", "OPTIONEN", "WIRKT SOFORT  ·  WIRD AUTOMATISCH GESPEICHERT")
	local updaters = {} -- [Key] = function() (Anzeige aus dem aktuellen Wert)
	UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(250, 44),
		Color = CARD, StrokeColor = BORDER, Text = "STANDARD WIEDERHERSTELLEN", TextSize = 15 }, frame, function()
		PlayerSettings.Reset()
	end)

	local CARD_W, ROW_H, CONTROL_W = 748, 62, 380
	local function slider(row, setting)
		local holder = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(CONTROL_W, 36), BackgroundTransparency = 1 }, row)
		local function step(direction)
			PlayerSettings.Set(setting.Key, PlayerSettings.Get(setting.Key) + direction * setting.Step)
		end
		button({ Size = UDim2.fromOffset(36, 36), Text = "−", TextSize = 20, BackgroundColor3 = UITheme.Colors.Background },
			holder, function()
				step(-1)
			end)
		local track = make("TextButton", { Position = UDim2.fromOffset(48, 14), Size = UDim2.fromOffset(196, 8), Text = "",
			AutoButtonColor = false, BackgroundColor3 = UITheme.Colors.Background, BorderSizePixel = 0, Selectable = false }, holder)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
		local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, track)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
		local knob = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(18, 18), BackgroundColor3 = UITheme.Colors.Text, BorderSizePixel = 0, ZIndex = 2 }, track)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
		button({ Position = UDim2.fromOffset(256, 0), Size = UDim2.fromOffset(36, 36), Text = "+", TextSize = 20,
			BackgroundColor3 = UITheme.Colors.Background }, holder, function()
			step(1)
		end)
		local value = text({ Position = UDim2.fromOffset(300, 0), Size = UDim2.fromOffset(80, 36), Text = "", TextSize = 22,
			Font = DISPLAY, TextXAlignment = Enum.TextXAlignment.Right }, holder)
		-- Ziehen mit Maus/Finger
		local dragging = false
		local function setFromX(x)
			local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			PlayerSettings.Set(setting.Key, setting.Min + alpha * (setting.Max - setting.Min))
		end
		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				setFromX(input.Position.X)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				setFromX(input.Position.X)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
		updaters[setting.Key] = function()
			local current = PlayerSettings.Get(setting.Key)
			local alpha = (current - setting.Min) / (setting.Max - setting.Min)
			fill.Size = UDim2.fromScale(alpha, 1)
			knob.Position = UDim2.fromScale(alpha, 0.5)
			value.Text = string.format(setting.Format or "%s", current)
		end
	end

	local function toggle(row, setting)
		local switch = make("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(76, 34), Text = "", AutoButtonColor = false, BorderSizePixel = 0 }, row)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, switch)
		local knob = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = UITheme.Colors.Text, BorderSizePixel = 0 }, switch)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
		local state = text({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -104, 0.5, 0), Size = UDim2.fromOffset(60, 34),
			Text = "", TextSize = 18, Font = DISPLAY, TextXAlignment = Enum.TextXAlignment.Right }, row)
		switch.Activated:Connect(function()
			PlayerSettings.Set(setting.Key, not PlayerSettings.Get(setting.Key))
		end)
		updaters[setting.Key] = function()
			local on = PlayerSettings.Get(setting.Key) == true
			switch.BackgroundColor3 = on and ACCENT or UITheme.Colors.Background
			knob.Position = on and UDim2.new(1, -30, 0.5, 0) or UDim2.new(0, 4, 0.5, 0)
			state.Text = on and "AN" or "AUS"
			state.TextColor3 = on and UITheme.Colors.Text or GRAY
		end
	end

	local function choice(row, setting)
		local holder = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(CONTROL_W, 36), BackgroundTransparency = 1 }, row)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
		local width = math.floor((CONTROL_W - 6 * (#setting.Options - 1)) / #setting.Options)
		width = math.min(width, 130)
		local buttons = {}
		for i, option in setting.Options do
			local swatch = setting.Key == "CrosshairColor" and PlayerSettings.CrosshairColors[option[1]] or nil
			local b = button({ Size = UDim2.fromOffset(width, 36), Text = option[2], TextSize = 14, LayoutOrder = i,
				BackgroundColor3 = UITheme.Colors.Background, TextColor3 = swatch or UITheme.Colors.Text }, holder, function()
				PlayerSettings.Set(setting.Key, option[1])
			end)
			local stroke = make("UIStroke", { Color = ACCENT, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
			buttons[i] = { Button = b, Stroke = stroke, Value = option[1], Swatch = swatch }
		end
		updaters[setting.Key] = function()
			local current = PlayerSettings.Get(setting.Key)
			for _, entry in buttons do
				local on = entry.Value == current
				entry.Stroke.Transparency = on and 0 or 1
				entry.Button.BackgroundColor3 = on and UITheme.Colors.Secondary or UITheme.Colors.Background
				if not entry.Swatch then
					entry.Button.TextColor3 = on and UITheme.Colors.Text or GRAY
				end
			end
		end
	end

	-- Karten in zwei Spalten, untereinander
	local PREVIEW_H = 214
	local columnY = { 72, 72 }
	for _, category in PlayerSettings.Categories do
		local list = {}
		for _, setting in PlayerSettings.List do
			if setting.Category == category.Id then
				table.insert(list, setting)
			end
		end
		local column = category.Column == 2 and 2 or 1
		local x = column == 1 and 0 or CARD_W + 24
		local y = columnY[column]
		local height = 52 + #list * ROW_H + 8 + (category.Preview and PREVIEW_H or 0)
		columnY[column] = y + height + 20
		local card = UITheme.Card({ Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(CARD_W, height),
			BackgroundTransparency = 0.1 }, frame)
		make("Frame", { Position = UDim2.fromOffset(20, 18), Size = UDim2.fromOffset(3, 18), BackgroundColor3 = ACCENT,
			BorderSizePixel = 0 }, card)
		text({ Position = UDim2.fromOffset(32, 12), Size = UDim2.new(1, -52, 0, 30), Text = category.Name, TextSize = 24,
			Font = DISPLAY }, card)
		for i, setting in list do
			local row = make("Frame", { Position = UDim2.fromOffset(0, 52 + (i - 1) * ROW_H), Size = UDim2.new(1, 0, 0, ROW_H),
				BackgroundTransparency = 1 }, card)
			if i > 1 then
				make("Frame", { Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -40, 0, 1), BackgroundColor3 = BORDER,
					BackgroundTransparency = 0.4, BorderSizePixel = 0 }, row)
			end
			text({ Position = UDim2.fromOffset(20, setting.Hint and 10 or 0), Size = UDim2.new(0, 300, 0, setting.Hint and 24 or ROW_H),
				Text = setting.Label, TextSize = 18 }, row)
			if setting.Hint then
				text({ Position = UDim2.fromOffset(20, 34), Size = UDim2.new(0, 320, 0, 16), Text = setting.Hint, TextSize = 13,
					Font = UITheme.Fonts.Body, TextColor3 = GRAY }, row)
			end
			if setting.Type == "Slider" then
				slider(row, setting)
			elseif setting.Type == "Toggle" then
				toggle(row, setting)
			else
				choice(row, setting)
			end
		end
		if category.Preview == "HitFeedback" then
			-- Vorschau: läuft leise in Schleife; nach dem Umschalten oder per Klick sofort mit Ton
			local surface = make("TextButton", { Name = "HitPreview", Position = UDim2.fromOffset(20, 52 + #list * ROW_H + 2),
				Size = UDim2.fromOffset(CARD_W - 40, PREVIEW_H - 12), BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0, Text = "", AutoButtonColor = false }, card)
			UITheme.Corner(surface, UITheme.Radius.Small)
			make("UIStroke", { Color = BORDER, Thickness = 1, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
				surface)
			-- Verlauf von oben (etwas heller) nach unten, wie ein schwach beleuchteter Schießstand
			make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(34, 39, 46),
				Color3.fromRGB(14, 16, 20)) }, surface)
			text({ Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(200, 16), Text = "VORSCHAU", TextSize = 12,
				TextColor3 = GRAY }, surface)
			text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), Size = UDim2.fromOffset(240, 16),
				Text = "KLICK = MIT TON ABSPIELEN", TextSize = 12, TextColor3 = GRAY, TextXAlignment = Enum.TextXAlignment.Right },
				surface)
			local preview = HitFeedback.Preview(surface)
			surface.Activated:Connect(function()
				preview.Play(true)
			end)
			PlayerSettings.Changed:Connect(function(key)
				if key == "HitmarkerStyle" or key == "DamageNumbers" then
					preview.Play(true)
				end
			end)
		end
	end

	local function updateAll()
		for _, update in updaters do
			update()
		end
	end
	updateAll()
	-- Änderungen von außen (z.B. Kamera-Taste T, Laden des Profils) gleich anzeigen
	PlayerSettings.Changed:Connect(function(key)
		if updaters[key] then
			updaters[key]()
		end
	end)
	page.Refresh = updateAll
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
	return b, caption
end

local function togglePanel(name)
	setPanel(openPanel ~= name and name or nil)
end

-- Lobby auf einer Seite öffnen (SHOP, LOADOUT, AGENTEN, BATTLE PASS sind Seiten der Lobby, keine Fenster)
local function openLobby(page)
	setPanel(nil)
	GameMenu.Open(page)
end

-- MARKT: in die Markthalle (im Markt geht es mit demselben Knopf zurück in den Hub)
local marketCaption
local function goMarket()
	setPanel(nil)
	local inMarket = player:GetAttribute("Mode") == Modes.Market.Id
	Remotes.JoinMode:FireServer(inMarket and Modes.Hub.Id or Modes.Market.Id)
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

	local nameLabel = text({ Position = UDim2.new(0, 92, 0, 10), Size = UDim2.new(1, -200, 0, 26), Text = player.Name, RichText = true,
		TextSize = 20, Font = DISPLAY, TextTruncate = Enum.TextTruncate.AtEnd }, playerCard)
	coinLabel = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.new(0, 110, 0, 20),
		Text = "", TextSize = 17, Font = DISPLAY, TextColor3 = UITheme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Right }, playerCard)
	-- RAP-Guthaben darunter (mintgrün, Rauten-Symbol davor; die Zeile wächst nach links)
	local rapRow = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 25),
		Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, playerCard)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, rapRow)
	UITheme.RapIcon(rapRow, 13, { LayoutOrder = 1 })
	local rapLabel = text({ Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 14,
		Font = DISPLAY, TextColor3 = UITheme.Colors.Rap, LayoutOrder = 2 }, rapRow)
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
		-- Doppel-XP aktiv (Login-Kalender, Glücksrad)
		local boost = (player:GetAttribute("XPBoostUntil") or 0) - workspace:GetServerTimeNow()
		if boost > 0 then
			xpLabel.Text ..= string.format("   ·   2× XP NOCH %d MIN", math.ceil(boost / 60))
		end
		prestigeButton.Visible = info.CanPrestige
		-- Symbol-Knöpfe rutschen unter den Prestige-Knopf, solange er da ist
		if column then
			column.Position = UDim2.new(0, 16, 0, info.CanPrestige and 236 or 180)
		end
		coinLabel.Text = formatNumber(coins()) .. " MÜNZEN"
		rapLabel.Text = formatNumber(player:GetAttribute("Rap") or 0) .. " RAP"
		-- Name mit ausgewähltem Titel (Rekrut wird nicht extra angezeigt)
		local title = TitleConfig.Get(player:GetAttribute("Title") or "")
		local clanTag = player:GetAttribute("ClanTag")
		nameLabel.Text = (clanTag and ('<font color="#8FC3FF">[' .. clanTag .. ']</font> ') or "") .. player.Name
			.. ((title and title.Id ~= TitleConfig.Default)
			and ('  <font size="13" color="#' .. title.Color:ToHex() .. '">' .. UITheme.Upper(title.Name) .. "</font>") or "")
	end
	refresh()
	player.AttributeChanged:Connect(function(name)
		if name == "AccountXP" or name == "Prestige" or name == "Elo" or name == "Coins" or name == "Title"
			or name == "XPBoostUntil" or name == "ClanTag" or name == "Rap" then
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
		{ "LOGIN", function() togglePanel("Daily") end, Color3.fromRGB(206, 110, 150), "📅" },
		{ "MARKT", function() goMarket() end, UITheme.Colors.Rap, "🏪" },
		{ "CLAN", function() togglePanel("Clan") end, Color3.fromRGB(110, 160, 230), "🛡" },
		{ "STATS", function() openLobby("Stats") end, Color3.fromRGB(96, 164, 214), "📊" },
		{ "BELOHNUNG", function() togglePanel("Rewards") end, Color3.fromRGB(212, 170, 80), "🏅" },
		{ "TITEL", function() togglePanel("Titles") end, Color3.fromRGB(190, 110, 230), "🏷" },
		{ "CODES", function() openLobby("Codes") end, Color3.fromRGB(112, 178, 160), "🎟" },
		{ "OPTIONEN", function() openLobby("Settings") end, Color3.fromRGB(134, 142, 152), "⚙" },
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
		local b, caption = sideButton(entry[1], i, entry[2], column, entry[3], entry[4])
		if entry[1] == "MARKT" then
			marketCaption = caption
		end
		if entry[1] == "LOGIN" then
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
	buildClan()
	buildCodes()
	buildSettings()
	buildRewards()
	buildTitles()

	-- Rückmeldung vom Server in das offene Fenster
	Remotes.ShopStatus.OnClientEvent:Connect(function(message, success)
		for _, panel in panels do
			panel.Status.Text = message
			panel.Status.TextColor3 = success and Color3.fromRGB(120, 230, 140) or Color3.fromRGB(255, 120, 120)
		end
	end)
	-- Münzen, Besitz, Ausrüstung geändert: offenes Fenster aktualisieren
	player.AttributeChanged:Connect(function(name)
		if name == "Coins" or name == "Owned" or name == "Equipped" or name == "LastDaily" or QuestBoard.Watch[name] or name == "LoginData" or name == "ClanTag" or name == "ClanData"
			or name == "PassXP" or name == "Stats" or name == "Elo" or name == "RankedData" or name == "Party"
			or name == "MatchHistory" or name == "RewardsClaimed" or name == "AccountXP" or name == "Prestige" or name == "Title" then
			if openPanel and panels[openPanel].Refresh then
				panels[openPanel].Refresh()
			end
		end
	end)
	coinLabel.Text = formatNumber(coins()) .. " MÜNZEN"

	-- Menüliste nur im Hub bei geschlossener Lobby; Fenster im Hub oder aus der Lobby heraus
	task.spawn(function()
		while true do
			local inHub = Modes.IsSocial(player:GetAttribute("Mode")) -- Hub oder Markt
			marketCaption.Text = player:GetAttribute("Mode") == Modes.Market.Id and "ZUM HUB" or "MARKT"
			local lobby = GameMenu.IsOpen()
			-- Markt- und Tausch-Fenster liegen in der Mitte: Menüliste solange weg (sie läge darüber)
			local covered = UITheme.IsMenuOpenBy("Market") or UITheme.IsMenuOpenBy("Trade")
			column.Visible = inHub and not lobby and not covered
			if openPanel and not (inHub or lobby) then
				setPanel(nil)
			end
			dailyDot.Visible = loginClaimable()
			questDot.Visible = questReady()
			if openPanel == "Daily" then
				panels.Daily.Refresh()
			end
			task.wait(0.25)
		end
	end)
end

return SideMenu

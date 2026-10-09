-- QuestBoard (ModuleScript, nur Client)
-- Inhalt des Fensters AUFTRÄGE (Hub: SideMenu, offene Welt: Reiter AUFTRÄGE im Menü von ExtinctionClient).
-- Oben die Reiter ARCADE / EXTINCTION, darunter drei Spalten: TÄGLICH, WÖCHENTLICH (Arcade mit Wochen-Bonus) und
-- VIP & BOOSTER (je ein Spezial-Auftrag am Tag und in der Woche für den gewählten Modus; ohne Berechtigung gesperrt).
-- Daten: Spieler-Attribute Quests/Weekly (Arcade), ExtQuests/ExtWeekly, SpecialQuests/SpecialWeekly (QuestConfig).
--   QuestBoard.new(parent, width, height, { Mode = "Arcade" | "Extinction", ZIndex = n, Colors = UITheme.MenuColors })
--   board.Refresh(), board.SetMode(mode), board.Destroy()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local QuestConfig = require(Shared.QuestConfig)
local Cosmetics = require(Shared.Cosmetics)
local UITheme = require(Shared.UITheme)
local Locale = require(Shared.Locale)

local player = Players.LocalPlayer

local QuestBoard = {}

local BORDER = UITheme.Colors.Border
local GRAY = UITheme.Colors.Muted
local GREEN = UITheme.Colors.Good
local GOLD = UITheme.Colors.Gold
local VIP = Color3.fromRGB(255, 115, 250) -- Booster-Pink, Spalte VIP & BOOSTER

-- Attribute, bei deren Änderung neu gezeichnet wird
QuestBoard.Watch = { Quests = true, Weekly = true, ExtQuests = true, ExtWeekly = true, SpecialQuests = true,
	SpecialWeekly = true, Pass_VIP = true, StaffRank = true }

-- "5 h 12 min" bzw. "3 T 4 h"
local function timeLeft(seconds)
	if seconds >= 86400 then
		return math.floor(seconds / 86400) .. " T " .. math.floor(seconds % 86400 / 3600) .. " h"
	end
	return math.floor(seconds / 3600) .. " h " .. math.floor(seconds % 3600 / 60) .. " min"
end

-- Gibt es irgendwo einen fertigen, nicht abgeholten Auftrag (oder den Wochen-Bonus)? Für den Punkt am Menüknopf.
function QuestBoard.Ready()
	local special = QuestConfig.IsSpecial(player)
	for _, attribute in { "Quests", "Weekly", "ExtQuests", "ExtWeekly", "SpecialQuests", "SpecialWeekly" } do
		local data = QuestConfig.Read(player, attribute)
		if data and data.Ids then
			local allClaimed = true
			for _, id in data.Ids do
				local quest = QuestConfig.Get(id)
				local claimed = (data.Claimed or {})[id] == true
				allClaimed = allClaimed and claimed
				if quest and not claimed and ((data.Progress or {})[id] or 0) >= quest.Goal and (special or not quest.Special) then
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

function QuestBoard.new(parent, width, height, options)
	options = options or {}
	local z = options.ZIndex or 1
	-- Farben (Menü der offenen Welt: UITheme.MenuColors, rot statt Bernstein)
	local palette = options.Colors or UITheme.Colors
	local ACCENT, ON_ACCENT, CARD = palette.Primary, palette.PrimaryText, palette.Card
	local MUTED_BACK = palette.MutedBack
	local board = { Mode = options.Mode or (player:GetAttribute("Mode") == "Extinction" and "Extinction" or "Arcade") }

	local function make(className, props, into)
		local obj = Instance.new(className)
		if obj:IsA("GuiObject") then
			obj.ZIndex = z
		end
		for key, value in props do
			obj[key] = value
		end
		obj.Parent = into
		return obj
	end
	local function text(props, into)
		props.BackgroundTransparency = 1
		props.Font = UITheme.FontFor(props.Font or Enum.Font.BuilderSansBold, props.TextSize)
		props.TextColor3 = props.TextColor3 or UITheme.Colors.Text
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		return make("TextLabel", props, into)
	end
	local function button(props, into, onClick)
		props.Font = props.Font or UITheme.Fonts.Bold
		props.ZIndex = z + 1
		return UITheme.Button(props, into, onClick)
	end

	local root = make("Frame", { Name = "QuestBoard", Size = UDim2.fromOffset(width, height), BackgroundTransparency = 1 },
		parent)
	board.Frame = root

	-- Reiter ARCADE / EXTINCTION
	local tabs = {}
	for i, def in { { "Arcade", "ARCADE" }, { "Extinction", "EXTINCTION" } } do
		tabs[def[1]] = button({ Position = UDim2.fromOffset((i - 1) * 168, 0), Size = UDim2.fromOffset(160, 36), Text = def[2],
			TextSize = 16 }, root, function()
			(board :: any).SetMode(def[1]) -- SetMode steht weiter unten
		end)
	end

	-- Drei Spalten
	local gap = 24
	local colW = math.floor((width - 2 * gap) / 3)
	local top = 52
	local columns = {}
	for i, info in { { "TÄGLICH", "Jeden Tag neu", ACCENT }, { "WÖCHENTLICH", "Jeden Montag neu", GOLD },
		{ "VIP & BOOSTER", "Gamepass VIP oder Discord-Booster", VIP } } do
		local x = (i - 1) * (colW + gap)
		text({ Position = UDim2.fromOffset(x, top), Size = UDim2.fromOffset(colW, 24), Text = info[1], TextSize = 20,
			Font = UITheme.Fonts.Title, TextColor3 = info[3] }, root)
		local timer = text({ Position = UDim2.fromOffset(x, top + 2), Size = UDim2.fromOffset(colW, 20), Text = "", TextSize = 13,
			TextColor3 = GRAY, TextXAlignment = Enum.TextXAlignment.Right }, root)
		local sub = text({ Position = UDim2.fromOffset(x, top + 26), Size = UDim2.fromOffset(colW, 16), Text = info[2],
			TextSize = 12, Font = UITheme.Fonts.Body, TextColor3 = GRAY, TextTruncate = Enum.TextTruncate.AtEnd }, root)
		local list = make("ScrollingFrame", { Position = UDim2.fromOffset(x, top + 52), Size = UDim2.fromOffset(colW, height - top - 52),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y }, root)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		make("UIPadding", { PaddingRight = UDim.new(0, 6) }, list)
		columns[i] = { List = list, Timer = timer, Sub = sub, Color = info[3] }
		if i < 3 then
			make("Frame", { Position = UDim2.fromOffset(x + colW + gap / 2, top + 4), Size = UDim2.new(0, 1, 0, height - top - 8),
				BackgroundColor3 = BORDER, BorderSizePixel = 0 }, root)
		end
	end

	-- Eine Auftragszeile: Text, Fortschritt, Belohnung, Knopf. tag = kleiner Hinweis über dem Text (z.B. "TÄGLICH"),
	-- locked = VIP & BOOSTER ohne Berechtigung
	local function questRow(list, order, quest, data, color, tag, locked)
		local id = quest.Id
		local progress = (data.Progress or {})[id] or 0
		local claimed = (data.Claimed or {})[id] == true
		local done = progress >= quest.Goal and not locked
		local rowH = tag and 92 or 78
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, rowH), BackgroundColor3 = CARD, LayoutOrder = order }, list)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, row)
		if tag then
			make("UIStroke", { Color = color, Transparency = locked and 0.75 or 0.35 }, row)
		end
		local y = 8
		if tag then
			text({ Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -150, 0, 14), Text = tag, TextSize = 11,
				TextColor3 = color }, row)
			y += 15
		end
		text({ Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -150, 0, 20), Text = quest.Text, TextSize = 16,
			TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = locked and GRAY or UITheme.Colors.Text }, row)
		text({ Position = UDim2.fromOffset(14, y + 22), Size = UDim2.new(1, -150, 0, 30), TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = math.min(progress, quest.Goal) .. " / " .. quest.Goal .. "  ·  " .. QuestConfig.RewardText(quest, Locale.Translate, Cosmetics.GetOwned(player)),
			TextSize = 12, TextColor3 = GRAY }, row)
		local barBack = make("Frame", { Position = UDim2.new(0, 14, 1, -12), Size = UDim2.new(1, -150, 0, 4),
			BackgroundColor3 = BORDER, BorderSizePixel = 0 }, row)
		make("Frame", { Size = UDim2.new(math.clamp(progress / quest.Goal, 0, 1), 0, 1, 0), BorderSizePixel = 0,
			BackgroundColor3 = done and GREEN or color }, barBack)
		local label = locked and "🔒 NUR VIP" or (claimed and "ABGEHOLT" or (done and "ABHOLEN" or "OFFEN"))
		button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(118, 40),
			TextSize = 14, Text = label,
			BackgroundColor3 = (done and not claimed) and ACCENT or MUTED_BACK,
			TextColor3 = (done and not claimed) and ON_ACCENT or (locked and VIP or GRAY) }, row, function()
			if done and not claimed then
				Remotes.ShopAction:FireServer("ClaimQuest", id)
			end
		end)
	end

	-- Wochen-Bonus (nur Arcade)
	local function bonusRow(list, weekly, allClaimed)
		local skin = Cosmetics.Get(QuestConfig.BonusSkin(weekly.Week or 0))
		local rarity = skin and Cosmetics.Rarities[skin.Rarity]
		local bonus = make("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = CARD, LayoutOrder = 99 }, list)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, bonus)
		make("UIStroke", { Color = GOLD, Transparency = weekly.Bonus and 0.7 or 0.2 }, bonus)
		text({ Position = UDim2.fromOffset(14, 9), Size = UDim2.new(1, -150, 0, 22), Text = "WOCHEN-BONUS", TextSize = 18,
			Font = UITheme.Fonts.Title, TextColor3 = GOLD }, bonus)
		text({ Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -150, 0, 18), RichText = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = UITheme.FormatNumber(QuestConfig.WeeklyBonus.Coins) .. " Münzen" .. (skin and (' + Skin <font color="#'
				.. (rarity and rarity.Color or GOLD):ToHex() .. '">' .. skin.Name .. "</font>") or ""),
			TextSize = 13, TextColor3 = GRAY }, bonus)
		button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(118, 40),
			TextSize = 14, Text = weekly.Bonus and "ABGEHOLT" or (allClaimed and "ABHOLEN" or "GESPERRT"),
			BackgroundColor3 = (allClaimed and not weekly.Bonus) and GOLD or MUTED_BACK,
			TextColor3 = (allClaimed and not weekly.Bonus) and ON_ACCENT or GRAY }, bonus, function()
			if allClaimed and not weekly.Bonus then
				Remotes.ShopAction:FireServer("ClaimWeeklyBonus")
			end
		end)
	end

	local function clear(list)
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	-- Aufträge eines Attributs in eine Spalte (filter(quest) -> true = zeigen)
	local function fill(column, attribute, filter, tag, locked)
		local data = QuestConfig.Read(player, attribute)
		local allClaimed = data ~= nil and data.Ids ~= nil and #data.Ids > 0
		for i, id in data and data.Ids or {} do
			local quest = QuestConfig.Get(id)
			if quest and (not filter or filter(quest)) then
				questRow(column.List, #column.List:GetChildren() + i, quest, data, column.Color, tag, locked)
				allClaimed = allClaimed and (data.Claimed or {})[id] == true
			end
		end
		return data, allClaimed
	end

	function board.Refresh()
		if not root.Parent then
			return
		end
		local mode = board.Mode
		for id, tab in tabs do
			local on = id == mode
			tab.BackgroundColor3 = on and ACCENT or MUTED_BACK
			tab.TextColor3 = on and ON_ACCENT or GRAY
		end
		local now = workspace:GetServerTimeNow()
		columns[1].Timer.Text = "NEU IN " .. timeLeft(QuestConfig.DayLeft(now))
		columns[2].Timer.Text = "NEU IN " .. timeLeft(QuestConfig.WeekLeft(now))
		columns[3].Timer.Text = ""
		local special = QuestConfig.IsSpecial(player)
		columns[2].Sub.Text = mode == "Arcade" and "Jeden Montag neu · alle geschafft = Wochen-Bonus" or "Jeden Montag neu"
		columns[3].Sub.Text = special and "Danke für deine Unterstützung!" or "Gamepass VIP oder Discord-Booster"
		for _, column in columns do
			clear(column.List)
		end

		if mode == "Arcade" then
			fill(columns[1], "Quests")
			local weekly, allClaimed = fill(columns[2], "Weekly")
			if weekly and weekly.Ids then
				bonusRow(columns[2].List, weekly, allClaimed)
			end
		else
			fill(columns[1], "ExtQuests")
			fill(columns[2], "ExtWeekly")
		end
		local function ofMode(quest)
			return quest.Mode == mode
		end
		fill(columns[3], "SpecialQuests", ofMode, "TÄGLICH", not special)
		fill(columns[3], "SpecialWeekly", ofMode, "WÖCHENTLICH", not special)
	end

	function board.SetMode(mode)
		board.Mode = mode
		board.Refresh()
	end

	local connection = player.AttributeChanged:Connect(function(name)
		if QuestBoard.Watch[name] and root.Parent and root.Visible then
			board.Refresh()
		end
	end)
	function board.Destroy()
		connection:Disconnect()
		root:Destroy()
	end
	root.Destroying:Connect(function()
		connection:Disconnect()
	end)

	board.Refresh()
	return board
end

return QuestBoard

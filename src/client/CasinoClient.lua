-- CasinoClient (ModuleScript, nur Client)
-- Fenster des Casinos im Camp (CasinoService öffnet es mit Remotes.CasinoUpdate "Open"): oben Spiel, Währung (MÜNZEN / RZ)
-- und Guthaben, links das Spiel, rechts die Chancen (Pflicht für Münz-Spiele, PaidRandom), unten Einsatz und Meldungen.
--   Spielautomat: drei Walzen, DREHEN
--   Roulette:     Wette wählen (Farbe, Gerade/Ungerade, Hälfte, Dutzend oder eine Zahl), DREHEN
--   Blackjack:    Croupier oben, darunter die Plätze (allein einer, am Tisch bis zu 4); EINSATZ SETZEN, KARTE ZIEHEN,
--                 KEINE KARTE, VERDOPPELN
-- Gewürfelt und ausgezahlt wird nur auf dem Server; hier wird nur angezeigt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)
local CasinoConfig = require(Shared.CasinoConfig)
local PaidRandom = require(Shared.PaidRandom)

local player = Players.LocalPlayer
local C = UITheme.MenuColors
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label

local CasinoClient = {}

local W, H = 820, 500
local GAME_W = 520
local GOLD = Color3.fromRGB(226, 184, 92)
local FELT = Color3.fromRGB(22, 84, 52)
local RED = Color3.fromRGB(200, 44, 44)
local TITLES = { Slot = "SPIELAUTOMAT", Roulette = "ROULETTE", Blackjack = "BLACKJACK", Table = "BLACKJACK-TISCH" }

local ui: any = {} -- gebaute Teile (Felder kommen erst beim Bauen dazu)
local state: any = { Game = nil, Currency = "RedPoints", Step = 1, PaidOk = false, Bet = "Red", Number = 7, Spinning = false,
	Stopped = 0, Table = nil }

local function amount()
	return CasinoConfig.Currencies[state.Currency].Steps[state.Step]
end

local function button(props, parent, onClick)
	props.TextSize = props.TextSize or 16
	return UITheme.Button(props, parent, onClick)
end

local function setStatus(text, color)
	ui.Status.Text = text or ""
	ui.Status.TextColor3 = color or C.Muted
end

-- ---------- Kopfzeile, Währung, Einsatz ----------

local function refreshMoney()
	if not ui.Balance then
		return
	end
	local coins = player:GetAttribute("Coins") or 0
	local rz = player:GetAttribute("RedPoints") or 0
	ui.Balance.Text = UITheme.FormatNumber(coins) .. " MÜNZEN  ·  " .. UITheme.FormatNumber(rz) .. " RZ"
	for currency, b in ui.CurrencyButtons do
		local on = state.Currency == currency
		local allowed = currency ~= "Coins" or state.PaidOk
		b.BackgroundColor3 = on and C.Primary or C.Card
		b.TextColor3 = allowed and C.Text or C.Muted
	end
	ui.Amount.Text = UITheme.FormatNumber(amount()) .. " " .. CasinoConfig.Currencies[state.Currency].Name
end

local function cardFrame(parent, card, order)
	local hidden = card.R == 0
	local frame = make("Frame", { Name = "Card", Size = UDim2.fromOffset(46, 64), LayoutOrder = order,
		BackgroundColor3 = hidden and Color3.fromRGB(120, 30, 34) or Color3.fromRGB(244, 242, 236), BorderSizePixel = 0 }, parent)
	UITheme.Corner(frame, 4)
	local red = card.S == 2 or card.S == 3
	label({ Size = UDim2.fromScale(1, 1), Text = hidden and "?" or CasinoConfig.CardText(card), TextSize = 20, Font = F.Display,
		TextColor3 = hidden and GOLD or (red and RED or Color3.fromRGB(20, 20, 24)),
		TextXAlignment = Enum.TextXAlignment.Center }, frame)
	return frame
end

local function cardRow(parent, cards)
	for _, child in parent:GetChildren() do
		if child.Name == "Card" then
			child:Destroy()
		end
	end
	for i, card in cards or {} do
		cardFrame(parent, card, i)
	end
end

-- ---------- Chancen ----------

local function oddsLine(text, right)
	local row = make("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1 }, ui.Odds)
	label({ Size = UDim2.new(0.62, 0, 1, 0), Text = text, TextSize = 12, Font = F.Bold }, row)
	label({ Position = UDim2.fromScale(0.62, 0), Size = UDim2.new(0.38, 0, 1, 0), Text = right, TextSize = 12, Font = F.Medium,
		TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, row)
end

local function fillOdds(game)
	for _, child in ui.Odds:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if game == "Slot" then
		local list, rtp = CasinoConfig.SlotOdds()
		for _, entry in list do
			oddsLine(entry.Text .. (entry.Pays > 0 and ("  ·  " .. entry.Pays .. "×") or ""), PaidRandom.Percent(entry.Chance))
		end
		oddsLine("RÜCKZAHLUNG", PaidRandom.Percent(math.floor(rtp * 1000 + 0.5) / 1000))
	elseif game == "Roulette" then
		for _, bet in CasinoConfig.RouletteBets do
			oddsLine(bet.Name .. "  ·  " .. bet.Pays .. "×", PaidRandom.Percent(CasinoConfig.RouletteChance(bet.Id)))
		end
	else
		local odds = CasinoConfig.Blackjack.Odds
		oddsLine("GEWINN (ca.)", PaidRandom.Percent(odds.Win))
		oddsLine("UNENTSCHIEDEN (ca.)", PaidRandom.Percent(odds.Push))
		oddsLine("VERLUST (ca.)", PaidRandom.Percent(odds.Lose))
		oddsLine("BLACKJACK ZAHLT", "3:2")
		oddsLine("CROUPIER ZIEHT BIS", tostring(CasinoConfig.Blackjack.DealerStands))
	end
end

-- ---------- Spiele ----------

local function buildSlot(body)
	local reels = make("Frame", { Name = "Reels", Position = UDim2.fromOffset(40, 40), Size = UDim2.fromOffset(GAME_W - 80, 170),
		BackgroundColor3 = Color3.fromRGB(14, 14, 18), BorderSizePixel = 0 }, body)
	UITheme.Corner(reels, 6)
	UITheme.Stroke(reels, GOLD, 2, 0.2)
	ui.Reels = {}
	for i = 1, 3 do
		local reel = make("Frame", { Position = UDim2.new((i - 1) / 3, 8, 0, 10), Size = UDim2.new(1 / 3, -16, 1, -20),
			BackgroundColor3 = Color3.fromRGB(240, 236, 226), BorderSizePixel = 0 }, reels)
		UITheme.Corner(reel, 4)
		ui.Reels[i] = label({ Size = UDim2.fromScale(1, 1), Text = "7", TextSize = 70, Font = F.Display,
			TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center }, reel)
	end
	ui.Result = label({ Position = UDim2.fromOffset(40, 222), Size = UDim2.fromOffset(GAME_W - 80, 40), Text = "",
		TextSize = 30, Font = F.Display, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center }, body)
	button({ Name = "Spin", Position = UDim2.fromOffset(GAME_W / 2 - 110, 276), Size = UDim2.fromOffset(220, 54), Text = "HEBEL ZIEHEN",
		TextSize = 24, BackgroundColor3 = C.Primary }, body, function()
		if state.Spinning then
			return
		end
		state.Spinning = true
		state.Stopped = 0
		ui.Result.Text = ""
		setStatus("")
		Remotes.CasinoAction:FireServer("Slot", state.Currency, amount())
		local started = os.clock()
		task.spawn(function()
			while state.Spinning and os.clock() - started < 4 do
				for i, reel in ui.Reels do
					if i > state.Stopped then -- angehaltene Walzen zeigen schon ihr Ergebnis
						local symbol = CasinoConfig.Slots.Symbols[math.random(#CasinoConfig.Slots.Symbols)]
						reel.Text = symbol.Text
					end
				end
				task.wait(0.07)
			end
			state.Spinning = false
		end)
	end)
end

local function showSlot(data)
	task.spawn(function()
		task.wait(0.6)
		for i, id in data.Reels do
			task.wait(0.25)
			state.Stopped = i
			local symbol = CasinoConfig.Symbol(id)
			ui.Reels[i].Text = symbol and symbol.Text or "?"
		end
		state.Spinning = false
		if data.Win > 0 then
			ui.Result.Text = "GEWINN +" .. UITheme.FormatNumber(data.Win) .. " " .. CasinoConfig.Currencies[data.Currency].Name
			ui.Result.TextColor3 = GOLD
		else
			ui.Result.Text = "KEIN GEWINN"
			ui.Result.TextColor3 = C.Muted
		end
	end)
end

local function buildRoulette(body)
	ui.Wheel = make("Frame", { Position = UDim2.fromOffset(GAME_W / 2 - 60, 16), Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = FELT, BorderSizePixel = 0 }, body)
	UITheme.Corner(ui.Wheel, 60)
	UITheme.Stroke(ui.Wheel, GOLD, 3, 0)
	ui.WheelNumber = label({ Size = UDim2.fromScale(1, 1), Text = "0", TextSize = 52, Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Center }, ui.Wheel)
	ui.Result = label({ Position = UDim2.fromOffset(20, 140), Size = UDim2.fromOffset(GAME_W - 40, 30), Text = "", TextSize = 24,
		Font = F.Display, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center }, body)
	local grid = make("Frame", { Position = UDim2.fromOffset(20, 176), Size = UDim2.fromOffset(GAME_W - 40, 104),
		BackgroundTransparency = 1 }, body)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(91, 30), CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	ui.BetButtons = {}
	for i, bet in CasinoConfig.RouletteBets do
		local color = bet.Id == "Red" and RED or bet.Id == "Black" and Color3.fromRGB(20, 20, 24) or FELT
		local b = button({ Name = "Bet_" .. bet.Id, LayoutOrder = i, Text = bet.Name, TextSize = 14, BackgroundColor3 = color }, grid,
			function()
				state.Bet = bet.Id
				CasinoClient.Refresh()
			end)
		ui.BetButtons[bet.Id] = b
	end
	ui.NumberBox = make("TextBox", { Name = "Number", Position = UDim2.fromOffset(20, 286), Size = UDim2.fromOffset(120, 34),
		BackgroundColor3 = C.Card, BorderSizePixel = 0, Text = "7", PlaceholderText = "0–36", TextColor3 = C.Text,
		Font = F.Display, TextSize = 18, ClearTextOnFocus = true }, body)
	UITheme.Corner(ui.NumberBox, 4)
	ui.NumberBox.FocusLost:Connect(function()
		local n = tonumber(ui.NumberBox.Text)
		if n and n == math.floor(n) and n >= 0 and n <= 36 then
			state.Number = n
			state.Bet = "Number"
		end
		ui.NumberBox.Text = tostring(state.Number)
		CasinoClient.Refresh()
	end)
	label({ Position = UDim2.fromOffset(148, 286), Size = UDim2.fromOffset(160, 34), Text = "← ZAHL 0–36", TextSize = 13,
		TextColor3 = C.Muted }, body)
	button({ Name = "Spin", Position = UDim2.fromOffset(GAME_W - 240, 284), Size = UDim2.fromOffset(220, 40), Text = "KUGEL WERFEN",
		TextSize = 22, BackgroundColor3 = C.Primary }, body, function()
		if state.Spinning then
			return
		end
		state.Spinning = true
		ui.Result.Text = ""
		setStatus("")
		Remotes.CasinoAction:FireServer("Roulette", state.Currency, amount(), state.Bet, state.Number)
		local started = os.clock()
		task.spawn(function()
			while state.Spinning and os.clock() - started < 5 do
				local n = math.random(0, 36)
				ui.WheelNumber.Text = tostring(n)
				local color = CasinoConfig.RouletteColor(n)
				ui.Wheel.BackgroundColor3 = color == "Red" and RED or color == "Black" and Color3.fromRGB(20, 20, 24) or FELT
				task.wait(0.06)
			end
			state.Spinning = false
		end)
	end)
end

local function showRoulette(data)
	task.spawn(function()
		task.wait(1.4)
		state.Spinning = false
		task.wait(0.07)
		ui.WheelNumber.Text = tostring(data.Number)
		ui.Wheel.BackgroundColor3 = data.Color == "Red" and RED or data.Color == "Black" and Color3.fromRGB(20, 20, 24) or FELT
		if data.Win > 0 then
			ui.Result.Text = "GEWINN +" .. UITheme.FormatNumber(data.Win) .. " " .. CasinoConfig.Currencies[data.Currency].Name
			ui.Result.TextColor3 = GOLD
		else
			ui.Result.Text = "VERLOREN"
			ui.Result.TextColor3 = C.Muted
		end
	end)
end

local RESULTS = { Blackjack = "BLACKJACK!", Win = "GEWONNEN", Push = "UNENTSCHIEDEN", Lose = "VERLOREN", Bust = "ÜBERKAUFT" }

local function buildBlackjack(body, seats)
	local felt = make("Frame", { Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(GAME_W - 20, 280), BackgroundColor3 = FELT,
		BorderSizePixel = 0 }, body)
	UITheme.Corner(felt, 8)
	UITheme.Stroke(felt, GOLD, 2, 0.3)
	label({ Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(200, 16), Text = "CROUPIER", TextSize = 12,
		TextColor3 = GOLD }, felt)
	ui.DealerValue = label({ Position = UDim2.fromOffset(GAME_W - 220, 8), Size = UDim2.fromOffset(180, 16), Text = "", TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right }, felt)
	ui.Dealer = make("Frame", { Position = UDim2.fromOffset(14, 28), Size = UDim2.fromOffset(GAME_W - 48, 64),
		BackgroundTransparency = 1 }, felt)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder },
		ui.Dealer)
	ui.Seats = {}
	local seatW = math.floor((GAME_W - 48 - (seats - 1) * 8) / seats)
	for i = 1, seats do
		local seat = make("Frame", { Name = "Seat" .. i, Position = UDim2.fromOffset(14 + (i - 1) * (seatW + 8), 104),
			Size = UDim2.fromOffset(seatW, 168), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.75,
			BorderSizePixel = 0 }, felt)
		UITheme.Corner(seat, 6)
		local stroke = UITheme.Stroke(seat, GOLD, 2, 1)
		local name = label({ Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 16), Text = "FREI", TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd }, seat)
		local info = label({ Position = UDim2.fromOffset(8, 22), Size = UDim2.new(1, -16, 0, 14), Text = "", TextSize = 11,
			TextColor3 = C.Muted }, seat)
		local cards = make("Frame", { Position = UDim2.fromOffset(8, 42), Size = UDim2.new(1, -16, 0, 64), BackgroundTransparency = 1 }, seat)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, -18),
			SortOrder = Enum.SortOrder.LayoutOrder }, cards)
		local result = label({ Position = UDim2.fromOffset(8, 112), Size = UDim2.new(1, -16, 0, 22), Text = "", TextSize = 16,
			Font = F.Display, TextColor3 = GOLD }, seat)
		local value = label({ Position = UDim2.fromOffset(8, 136), Size = UDim2.new(1, -16, 0, 22), Text = "", TextSize = 14 }, seat)
		ui.Seats[i] = { Frame = seat, Stroke = stroke, Name = name, Info = info, Cards = cards, Result = result, Value = value }
	end
	ui.Timer = label({ Position = UDim2.fromOffset(10, 290), Size = UDim2.fromOffset(GAME_W - 20, 16), Text = "", TextSize = 13,
		TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }, body)
	local actions = make("Frame", { Position = UDim2.fromOffset(10, 308), Size = UDim2.fromOffset(GAME_W - 20, 40),
		BackgroundTransparency = 1 }, body)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center }, actions)
	ui.Actions = {}
	for i, entry in { { "Bet", "EINSATZ SETZEN" }, { "Hit", "KARTE ZIEHEN" }, { "Stand", "KEINE KARTE" }, { "Double", "VERDOPPELN" } } do
		ui.Actions[entry[1]] = button({ Name = entry[1], LayoutOrder = i, Size = UDim2.fromOffset(118, 40), Text = entry[2],
			BackgroundColor3 = entry[1] == "Bet" and C.Primary or C.Card }, actions, function()
			if entry[1] == "Bet" then
				Remotes.CasinoAction:FireServer("Bet", state.Currency, amount())
			else
				Remotes.CasinoAction:FireServer(entry[1])
			end
		end)
	end
end

local function showTable(data)
	state.Table = data
	if not ui.Seats then
		return
	end
	cardRow(ui.Dealer, data.Dealer)
	ui.DealerValue.Text = data.DealerValue and ("WERT " .. data.DealerValue) or ""
	local mine = nil
	for i, seatUi in ui.Seats do
		local seat = data.Seats[i]
		if seat then
			local own = seat.UserId == player.UserId
			if own then
				mine = { Index = i, Seat = seat }
			end
			seatUi.Name.Text = own and "DU" or seat.Name
			seatUi.Name.TextColor3 = own and GOLD or C.Text
			seatUi.Info.Text = seat.Bet and ("EINSATZ " .. UITheme.FormatNumber(seat.Bet) .. " " .. CasinoConfig.Currencies[seat.Currency].Name)
				or "SETZT NOCH"
			cardRow(seatUi.Cards, seat.Cards)
			seatUi.Value.Text = seat.Value and ("WERT " .. seat.Value) or ""
			seatUi.Result.Text = seat.Result and (RESULTS[seat.Result] .. (seat.Win and seat.Win > 0
				and ("  +" .. UITheme.FormatNumber(seat.Win)) or "")) or ""
		else
			seatUi.Name.Text = "FREI"
			seatUi.Name.TextColor3 = C.Muted
			seatUi.Info.Text = ""
			cardRow(seatUi.Cards, {})
			seatUi.Value.Text = ""
			seatUi.Result.Text = ""
		end
		seatUi.Stroke.Transparency = data.Turn == i and 0 or 1
	end
	local myTurn = mine ~= nil and data.Phase == "Play" and data.Turn == mine.Index
	local canBet = mine ~= nil and not mine.Seat.Bet and (data.Phase == "Waiting" or data.Phase == "Betting")
	ui.Actions.Bet.Visible = canBet
	ui.Actions.Hit.Visible = myTurn
	ui.Actions.Stand.Visible = myTurn
	ui.Actions.Double.Visible = myTurn and #mine.Seat.Cards == 2
	if not mine then
		setStatus("Der Tisch ist voll – du schaust zu.")
	end
end

-- ---------- Fenster ----------

local function close(send)
	if ui.Gui then
		ui.Gui.Enabled = false
	end
	state.Game, state.Table, state.Spinning = nil, nil, false
	UITheme.SetMenu("Casino", false)
	if send then
		Remotes.CasinoAction:FireServer("Leave")
	end
end

local function build()
	local gui = make("ScreenGui", { Name = "Casino", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 21, Enabled = false },
		player:WaitForChild("PlayerGui"))
	ui.Gui = gui
	local root = UITheme.ScaledRoot(gui)
	local panel = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H), BackgroundColor3 = Color3.fromRGB(16, 14, 18), BackgroundTransparency = 0.05,
		BorderSizePixel = 0 }, root)
	UITheme.Corner(panel, 8)
	UITheme.Stroke(panel, GOLD, 1, 0.4)
	ui.Panel = panel
	-- Kopfzeile
	ui.Title = label({ Position = UDim2.fromOffset(20, 12), Size = UDim2.fromOffset(300, 28), Text = "CASINO", TextSize = 24,
		Font = F.Display, TextColor3 = GOLD }, panel)
	ui.Balance = label({ Position = UDim2.fromOffset(20, 40), Size = UDim2.fromOffset(400, 16), Text = "", TextSize = 12,
		TextColor3 = C.Muted }, panel)
	button({ Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(40, 40),
		Text = "✕", TextSize = 20 }, panel, function()
		close(true)
	end)
	ui.CurrencyButtons = {}
	for i, currency in CasinoConfig.CurrencyOrder do
		ui.CurrencyButtons[currency] = button({ Name = "Currency_" .. currency, AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -64 - (#CasinoConfig.CurrencyOrder - i) * 108, 0, 14), Size = UDim2.fromOffset(100, 36),
			Text = CasinoConfig.Currencies[currency].Name, TextSize = 15 }, panel, function()
			if currency == "Coins" and not state.PaidOk then
				setStatus("Münz-Spiele sind in deinem Land nicht erlaubt – spiel mit RZ.", C.Bad)
				return
			end
			state.Currency = currency
			state.Step = 1
			refreshMoney()
		end)
	end
	-- Spielfläche und Chancen
	ui.Body = make("Frame", { Name = "Body", Position = UDim2.fromOffset(20, 66), Size = UDim2.fromOffset(GAME_W, 350),
		BackgroundTransparency = 1 }, panel)
	local oddsBox = make("Frame", { Name = "OddsBox", Position = UDim2.fromOffset(GAME_W + 36, 66), Size = UDim2.fromOffset(W - GAME_W - 56, 350),
		BackgroundColor3 = Color3.fromRGB(26, 24, 30), BorderSizePixel = 0 }, panel)
	UITheme.Corner(oddsBox, 6)
	label({ Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 18), Text = "CHANCEN", TextSize = 14, Font = F.Display,
		TextColor3 = GOLD }, oddsBox)
	ui.Odds = make("Frame", { Name = "Odds", Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 1, -64),
		BackgroundTransparency = 1 }, oddsBox)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, ui.Odds)
	label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -8), Size = UDim2.new(1, -24, 0, 22), Text = PaidRandom.Note,
		TextSize = 10, TextColor3 = C.Muted, TextWrapped = true }, oddsBox)
	-- Einsatz
	local betRow = make("Frame", { Name = "BetRow", Position = UDim2.fromOffset(20, H - 74), Size = UDim2.fromOffset(GAME_W, 40),
		BackgroundTransparency = 1 }, panel)
	label({ Size = UDim2.fromOffset(90, 40), Text = "EINSATZ", TextSize = 14, TextColor3 = C.Muted }, betRow)
	button({ Name = "Less", Position = UDim2.fromOffset(90, 0), Size = UDim2.fromOffset(40, 40), Text = "−", TextSize = 22 }, betRow,
		function()
			state.Step = math.max(1, state.Step - 1)
			refreshMoney()
		end)
	ui.Amount = label({ Position = UDim2.fromOffset(136, 0), Size = UDim2.fromOffset(200, 40), Text = "", TextSize = 20, Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Center }, betRow)
	button({ Name = "More", Position = UDim2.fromOffset(342, 0), Size = UDim2.fromOffset(40, 40), Text = "+", TextSize = 22 }, betRow,
		function()
			state.Step = math.min(#CasinoConfig.Currencies[state.Currency].Steps, state.Step + 1)
			refreshMoney()
		end)
	ui.Status = label({ Position = UDim2.fromOffset(20, H - 28), Size = UDim2.fromOffset(W - 40, 18), Text = "", TextSize = 13,
		TextColor3 = C.Muted }, panel)
end

function CasinoClient.Refresh()
	refreshMoney()
	if ui.BetButtons then
		for id, b in ui.BetButtons do
			local stroke = b:FindFirstChild("Selected") or UITheme.Stroke(b, GOLD, 2, 1)
			stroke.Name = "Selected"
			stroke.Transparency = state.Bet == id and 0 or 1
		end
		ui.BetButtons.Number.Text = "ZAHL " .. state.Number
	end
end

local function openWindow(data)
	if not ui.Gui then
		build()
	end
	for _, child in ui.Body:GetChildren() do
		child:Destroy()
	end
	ui.Reels, ui.BetButtons, ui.Seats, ui.Actions = nil, nil, nil, nil
	state.Game = data.Game
	state.PaidOk = data.PaidOk == true
	if not state.PaidOk and state.Currency ~= "RedPoints" then
		state.Currency = "RedPoints" -- Münzen hier nicht erlaubt: auf RZ, kleinster Einsatz
		state.Step = 1
	end
	state.Step = math.min(state.Step, #CasinoConfig.Currencies[state.Currency].Steps)
	state.Spinning = false
	ui.Title.Text = "CASINO · " .. (TITLES[data.Game] or "")
	if data.Game == "Slot" then
		buildSlot(ui.Body)
	elseif data.Game == "Roulette" then
		buildRoulette(ui.Body)
	else
		buildBlackjack(ui.Body, data.Game == "Table" and CasinoConfig.Blackjack.Seats or 1)
	end
	fillOdds(data.Game)
	setStatus(state.PaidOk and "" or "Münz-Spiele sind in deinem Land nicht erlaubt – hier geht nur RZ.")
	CasinoClient.Refresh()
	ui.Gui.Enabled = true
	UITheme.SetMenu("Casino", true)
end

function CasinoClient.Init()
	Remotes.CasinoUpdate.OnClientEvent:Connect(function(kind, data)
		if kind == "Open" then
			openWindow(data)
		elseif kind == "Close" then
			close(false)
		elseif not state.Game then
			return
		elseif kind == "Slot" and ui.Reels then
			showSlot(data)
		elseif kind == "Roulette" and ui.Wheel and ui.Wheel.Parent then
			showRoulette(data)
		elseif kind == "Table" then
			showTable(data)
		elseif kind == "Status" then
			state.Spinning = false
			setStatus(data, C.Bad)
		end
	end)
	for _, attribute in { "Coins", "RedPoints" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshMoney)
	end
	-- Restzeit am Blackjack-Tisch
	RunService.Heartbeat:Connect(function()
		local data = state.Table
		if not (ui.Timer and ui.Timer.Parent and data) then
			return
		end
		local left = math.max(0, math.ceil((data.Deadline or 0) - workspace:GetServerTimeNow()))
		if data.Phase == "Betting" then
			ui.Timer.Text = "KARTEN IN " .. left .. " S  ·  JETZT SETZEN"
		elseif data.Phase == "Play" then
			ui.Timer.Text = "AM ZUG: PLATZ " .. tostring(data.Turn) .. "  ·  " .. left .. " S"
		elseif data.Phase == "Result" then
			ui.Timer.Text = "NEUE RUNDE IN " .. left .. " S"
		else
			ui.Timer.Text = "SETZ DEINEN EINSATZ"
		end
	end)
end

-- Für Tests
function CasinoClient.Ui()
	return ui, state
end

return CasinoClient

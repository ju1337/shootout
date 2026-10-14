-- CasinoService (ModuleScript, nur Server)
-- Casino im Camp (CasinoConfig): E an einem Punkt (Spielautomat, Roulette, Blackjack allein, Blackjack-Tisch) öffnet beim
-- Spieler das Fenster (Remotes.CasinoUpdate "Open"). Alles Würfeln und Auszahlen passiert hier; der Client schickt nur
-- Aktionen (Remotes.CasinoAction):
--   "Slot", Währung, Einsatz                      Walzen drehen
--   "Roulette", Währung, Einsatz, Wette, Zahl     Kugel werfen
--   "Bet", Währung, Einsatz                       Blackjack: setzen (allein: sofort geben; Tisch: Runde startet nach BetTime)
--   "Hit" / "Stand" / "Double"                    Blackjack: Karte, halten, verdoppeln
--   "Leave"                                       Fenster zu (vom Tisch aufstehen)
-- Münz-Einsätze nur mit PaidRandomOk (PolicyGate, PaidRandom); RZ immer. Antworten: CasinoUpdate "Slot", "Roulette",
-- "Table" (Stand des Tisches), "Status" (Text), "Close".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local CasinoConfig = require(Shared.CasinoConfig)
local Zentrale = require(Shared.Zentrale)
local ProgressService = require(script.Parent.ProgressService)
local RedPointsService = require(script.Parent.RedPointsService)

local CasinoService = {}

local B = CasinoConfig.Blackjack
local random = Random.new()
local options = nil
local points = {}   -- [Name] = Part
local open = {}     -- [Player] = { Game, Point }
local busyUntil = {} -- [Player] = os.clock(): Automat/Roulette drehen noch
local soloTables = {} -- [Player] = Tisch (Blackjack allein)
local groupTable = nil

-- Für Tests: Zufall festlegen
function CasinoService.SetRandom(r)
	random = r
end

local function status(player, text)
	Remotes.CasinoUpdate:FireClient(player, "Status", text)
end

-- ---------- Geld ----------

local function balance(player, currency)
	if currency == "Coins" then
		local profile = ProgressService.Get(player)
		return profile and profile.Coins or 0
	end
	return RedPointsService.Get(player)
end

-- Einsatz prüfen und abbuchen; gibt nil oder einen Fehlertext zurück
local function take(player, currency, amount, what)
	if not CasinoConfig.ValidBet(currency, amount) then
		return "Ungültiger Einsatz."
	end
	if CasinoConfig.Currencies[currency].Paid and player:GetAttribute("PaidRandomOk") ~= true then
		return "Münz-Spiele sind in deinem Land nicht erlaubt – spiel mit RZ."
	end
	if balance(player, currency) < amount then
		return currency == "Coins" and "Nicht genug Münzen." or "Nicht genug RZ."
	end
	local ok
	if currency == "Coins" then
		ok = ProgressService.SpendCoins(player, amount, "Casino", what)
	else
		ok = RedPointsService.Spend(player, amount)
	end
	return not ok and "Nicht genug." or nil
end

local function give(player, currency, amount)
	amount = math.floor(amount)
	if amount <= 0 or not player.Parent then
		return
	end
	if currency == "Coins" then
		ProgressService.AddCoins(player, amount, "Casino")
	else
		RedPointsService.Add(player, amount, nil)
	end
end

-- ---------- Nähe ----------

local function near(player, game)
	local session = open[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not session or session.Game ~= game or not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return (root.Position - session.Point.Position).Magnitude <= CasinoConfig.Range + 6
end

-- ---------- Spielautomat und Roulette ----------

local function slot(player, currency, amount)
	if not near(player, "Slot") or (busyUntil[player] or 0) > os.clock() then
		return
	end
	local err = take(player, currency, amount, "Slot")
	if err then
		return status(player, err)
	end
	busyUntil[player] = os.clock() + 1.2
	local reels = { CasinoConfig.RollSymbol(random:NextNumber()), CasinoConfig.RollSymbol(random:NextNumber()),
		CasinoConfig.RollSymbol(random:NextNumber()) }
	local pays = CasinoConfig.SlotPayout(reels)
	local win = math.floor(amount * pays)
	give(player, currency, win)
	Remotes.CasinoUpdate:FireClient(player, "Slot", { Reels = reels, Win = win, Bet = amount, Currency = currency })
end

local function roulette(player, currency, amount, betId, number)
	if not near(player, "Roulette") or (busyUntil[player] or 0) > os.clock() then
		return
	end
	local bet = CasinoConfig.RouletteBet(betId)
	if not bet or (betId == "Number" and (type(number) ~= "number" or number ~= math.floor(number) or number < 0 or number > 36)) then
		return status(player, "Ungültige Wette.")
	end
	local err = take(player, currency, amount, "Roulette")
	if err then
		return status(player, err)
	end
	busyUntil[player] = os.clock() + 2
	local n = random:NextInteger(0, 36)
	local win = CasinoConfig.RouletteWins(betId, n, number) and amount * bet.Pays or 0
	give(player, currency, win)
	Remotes.CasinoUpdate:FireClient(player, "Roulette", { Number = n, Color = CasinoConfig.RouletteColor(n), Win = win,
		Bet = amount, Currency = currency })
end

-- ---------- Blackjack ----------

local function draw()
	return { R = random:NextInteger(1, 13), S = random:NextInteger(1, 4) }
end

local function newTable(seats, betTime, game)
	return { Seats = {}, Size = seats, BetTime = betTime, Game = game, Phase = "Waiting", Dealer = {}, Turn = nil,
		Deadline = 0 }
end

-- Stand des Tisches für die Anzeige (Karte 2 des Croupiers verdeckt, solange gespielt wird)
local function snapshot(t)
	local dealer = {}
	for i, card in t.Dealer do
		table.insert(dealer, (i == 2 and t.Phase == "Play") and { R = 0, S = 0 } or card)
	end
	local seats = {}
	for i = 1, t.Size do
		local seat = t.Seats[i]
		seats[i] = seat and { Name = seat.Player.DisplayName, UserId = seat.Player.UserId, Bet = seat.Bet, Currency = seat.Currency,
			Cards = seat.Cards, Value = #seat.Cards > 0 and (CasinoConfig.HandValue(seat.Cards)) or nil, Result = seat.Result,
			Win = seat.Win } or false
	end
	return { Phase = t.Phase, Turn = t.Turn, Deadline = t.Deadline, Dealer = dealer,
		DealerValue = t.Phase ~= "Play" and #t.Dealer > 0 and (CasinoConfig.HandValue(t.Dealer)) or nil, Seats = seats,
		Size = t.Size, Game = t.Game }
end

local function watchers(t)
	local list = {}
	for player, session in open do
		if (t == groupTable and session.Game == "Table") or (soloTables[player] == t and session.Game == "Blackjack") then
			table.insert(list, player)
		end
	end
	return list
end

local function publish(t)
	local data = snapshot(t)
	for _, player in watchers(t) do
		Remotes.CasinoUpdate:FireClient(player, "Table", data)
	end
end

local function seatOf(t, player)
	for i = 1, t.Size do
		if t.Seats[i] and t.Seats[i].Player == player then
			return i, t.Seats[i]
		end
	end
	return nil, nil
end

-- nächster Spieler am Zug (nach Platz from), sonst der Croupier
local finish
local function nextTurn(t, from)
	for i = (from or 0) + 1, t.Size do
		local seat = t.Seats[i]
		if seat and seat.Bet and not seat.Done then
			t.Turn = i
			t.Deadline = workspace:GetServerTimeNow() + B.TurnTime
			return
		end
	end
	finish(t)
end

local function deal(t)
	t.Dealer = { draw(), draw() }
	local anyone = false
	for i = 1, t.Size do
		local seat = t.Seats[i]
		if seat and seat.Bet then
			anyone = true
			seat.Cards = { draw(), draw() }
			seat.Done = CasinoConfig.IsBlackjack(seat.Cards) or CasinoConfig.IsBlackjack(t.Dealer)
		end
	end
	if not anyone then
		t.Phase = "Waiting"
		return
	end
	t.Phase = "Play"
	nextTurn(t, 0)
end

finish = function(t)
	t.Turn = nil
	-- Croupier zieht nur, wenn noch jemand ohne Blackjack im Spiel ist
	local live = false
	for i = 1, t.Size do
		local seat = t.Seats[i]
		if seat and seat.Bet and CasinoConfig.HandValue(seat.Cards) <= 21 and not CasinoConfig.IsBlackjack(seat.Cards) then
			live = true
		end
	end
	if live then
		while (CasinoConfig.HandValue(t.Dealer)) < B.DealerStands do
			table.insert(t.Dealer, draw())
		end
	end
	for i = 1, t.Size do
		local seat = t.Seats[i]
		if seat and seat.Bet then
			local pays, result = CasinoConfig.BlackjackResult(seat.Cards, t.Dealer)
			seat.Result = result
			seat.Win = math.floor(seat.Bet * pays)
			give(seat.Player, seat.Currency, seat.Win)
		end
	end
	t.Phase = "Result"
	t.Deadline = workspace:GetServerTimeNow() + B.ResultTime
end

-- neue Runde: Karten und Einsätze weg, wer gegangen ist, verliert seinen Platz
local function reset(t)
	t.Phase = "Waiting"
	t.Dealer = {}
	t.Turn = nil
	for i = 1, t.Size do
		local seat = t.Seats[i]
		if seat then
			if seat.Left or not seat.Player.Parent then
				t.Seats[i] = nil
			else
				seat.Bet, seat.Currency, seat.Cards, seat.Done, seat.Result, seat.Win = nil, nil, {}, false, nil, nil
			end
		end
	end
end

local function sit(t, player)
	local index = seatOf(t, player)
	if index then
		t.Seats[index].Left = nil
		return index
	end
	for i = 1, t.Size do
		if not t.Seats[i] then
			t.Seats[i] = { Player = player, Cards = {}, Done = false }
			return i
		end
	end
	return nil
end

local function tableFor(player)
	local session = open[player]
	if session and session.Game == "Table" then
		return groupTable
	elseif session and session.Game == "Blackjack" then
		return soloTables[player]
	end
	return nil
end

local function bet(player, currency, amount)
	local t = tableFor(player)
	if not t or not near(player, t.Game) then
		return
	end
	if t.Phase ~= "Waiting" and t.Phase ~= "Betting" then
		return status(player, "Warte auf die nächste Runde.")
	end
	local _, seat = seatOf(t, player)
	if not seat then
		return status(player, "Der Tisch ist voll – schau zu oder warte auf einen freien Platz.")
	end
	if seat.Bet then
		return
	end
	local err = take(player, currency, amount, "Blackjack")
	if err then
		return status(player, err)
	end
	seat.Bet, seat.Currency, seat.Cards, seat.Done, seat.Result, seat.Win = amount, currency, {}, false, nil, nil
	if t.Phase == "Waiting" then
		t.Phase = "Betting"
		t.Deadline = workspace:GetServerTimeNow() + t.BetTime
	end
	if t.BetTime <= 0 then
		deal(t)
	end
	publish(t)
end

local function move(player, action)
	local t = tableFor(player)
	if not t or t.Phase ~= "Play" or not near(player, t.Game) then
		return
	end
	local index, seat = seatOf(t, player)
	if not seat or t.Turn ~= index then
		return
	end
	if action == "Hit" then
		table.insert(seat.Cards, draw())
		if (CasinoConfig.HandValue(seat.Cards)) >= 21 then
			seat.Done = true
		end
	elseif action == "Stand" then
		seat.Done = true
	elseif action == "Double" then
		if #seat.Cards ~= 2 then
			return
		end
		local err = take(player, seat.Currency, seat.Bet, "Blackjack")
		if err then
			return status(player, err)
		end
		seat.Bet *= 2
		table.insert(seat.Cards, draw())
		seat.Done = true
	end
	if seat.Done then
		nextTurn(t, index)
	end
	publish(t)
end

local function stepTable(t, now)
	if t.Phase == "Betting" and now >= t.Deadline then
		deal(t)
		publish(t)
	elseif t.Phase == "Play" and t.Turn and now >= t.Deadline then
		local seat = t.Seats[t.Turn]
		if seat then
			seat.Done = true -- Zeit um: halten
		end
		nextTurn(t, t.Turn)
		publish(t)
	elseif t.Phase == "Result" and now >= t.Deadline then
		reset(t)
		publish(t)
	end
end

-- ---------- Fenster ----------

local function close(player, silent)
	local session = open[player]
	open[player] = nil
	if session and session.Game == "Table" and groupTable then
		local index, seat = seatOf(groupTable, player)
		if index and seat then
			if seat.Bet and groupTable.Phase ~= "Waiting" then
				seat.Left = true -- Runde läuft: Platz bleibt bis zum Ende, am Zug hält er automatisch
				if groupTable.Turn == index then
					seat.Done = true
					nextTurn(groupTable, index)
				end
			else
				groupTable.Seats[index] = nil
			end
			publish(groupTable)
		end
	end
	if not silent and player.Parent then
		Remotes.CasinoUpdate:FireClient(player, "Close")
	end
end

local function openGame(player, game, point)
	if open[player] then
		close(player, true)
	end
	open[player] = { Game = game, Point = point }
	local data = { Game = game, PaidOk = player:GetAttribute("PaidRandomOk") == true }
	if game == "Blackjack" then
		soloTables[player] = soloTables[player] or newTable(1, 0, "Blackjack")
		sit(soloTables[player], player)
	elseif game == "Table" then
		data.Seat = sit(groupTable, player)
	end
	Remotes.CasinoUpdate:FireClient(player, "Open", data)
	local t = tableFor(player)
	if t then
		publish(t)
	end
end

local function addPrompt(point, game, title, action)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CasinoPrompt"
	prompt.ActionText = action
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = game == "Slot" and 5 or CasinoConfig.Range -- Automaten stehen dicht nebeneinander
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton -- nur die nächste E-Aufforderung
	prompt.RequiresLineOfSight = false
	prompt.Parent = point
	prompt.Triggered:Connect(function(player)
		openGame(player, game, point)
	end)
end

-- Aktion vom Client (auch für Tests)
function CasinoService.Action(player, action, a, b, c, d)
	if action == "Slot" then
		slot(player, a, b)
	elseif action == "Roulette" then
		roulette(player, a, b, c, d)
	elseif action == "Bet" then
		bet(player, a, b)
	elseif action == "Hit" or action == "Stand" or action == "Double" then
		move(player, action)
	elseif action == "Leave" then
		close(player, true)
	end
end

-- Fenster öffnen wie mit E (für Tests); game = "Slot", "Roulette", "Blackjack" oder "Table"
function CasinoService.Open(player, game)
	local name = game == "Slot" and CasinoConfig.Points.Slot[1] or CasinoConfig.Points[game]
	if points[name] then
		openGame(player, game, points[name])
	end
end

function CasinoService.TableState(player)
	local t = tableFor(player)
	return t and snapshot(t) or nil
end

-- Ein Schritt (Zeitlimits, Abstand); läuft sonst auf Heartbeat
function CasinoService.Step()
	local now = workspace:GetServerTimeNow()
	if groupTable then
		stepTable(groupTable, now)
	end
	for _, t in soloTables do
		stepTable(t, now)
	end
	for player, session in open do
		if not player.Parent or not near(player, session.Game) then
			close(player)
		end
	end
end

-- opts = { Map }
function CasinoService.Init(opts)
	options = opts
	if not CasinoConfig.Enabled then
		return
	end
	local zentrale = options.Map and options.Map:FindFirstChild(Zentrale.Group)
	local function point(name)
		local part = zentrale and zentrale:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			points[name] = part
			return part
		end
		warn("CasinoService: Punkt " .. name .. " fehlt im Camp")
		return nil
	end
	for i, name in CasinoConfig.Points.Slot do
		local part = point(name)
		if part then
			addPrompt(part, "Slot", "Spielautomat " .. i, "Spielen")
		end
	end
	local roulettePoint = point(CasinoConfig.Points.Roulette)
	if roulettePoint then
		addPrompt(roulettePoint, "Roulette", "Roulette", "Spielen")
	end
	local soloPoint = point(CasinoConfig.Points.Blackjack)
	if soloPoint then
		addPrompt(soloPoint, "Blackjack", "Blackjack · Croupier", "Spielen")
	end
	local tablePoint = point(CasinoConfig.Points.Table)
	if tablePoint then
		addPrompt(tablePoint, "Table", "Blackjack-Tisch · bis " .. B.Seats .. " Spieler", "Hinsetzen")
	end
	groupTable = newTable(B.Seats, B.BetTime, "Table")
	Remotes.CasinoAction.OnServerEvent:Connect(function(player, action, a, b, c, d)
		if type(action) == "string" then
			CasinoService.Action(player, action, a, b, c, d)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		close(player, true)
		soloTables[player] = nil
		busyUntil[player] = nil
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.25 then
			elapsed = 0
			CasinoService.Step()
		end
	end)
end

return CasinoService

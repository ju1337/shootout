-- CasinoConfig (ModuleScript, Server und Client)
-- Casino im Camp (Halle im Nordwesten, tools/camp_phoenix.py): Spielautomaten, Roulette und Blackjack gegen den Croupier
-- sowie ein Blackjack-Tisch für bis zu 4 Spieler. Gespielt wird mit Münzen oder Rote-Zone-Punkten (RZ).
-- Münzen kann man für Robux kaufen: Münz-Spiele sind darum bezahlte Zufallsitems (PaidRandom) – Chancen stehen vor dem
-- Spiel im Fenster, und wo PolicyService sie verbietet (PaidRandomOk = false), geht nur RZ. RZ gibt es nur durch Spielen.
-- Hier stehen auch die Regeln als reine Funktionen (Auszahlung, Chancen, Kartenwert): Server, Client und Tests nutzen sie.

local CasinoConfig = {}

CasinoConfig.Enabled = true

-- Punkte in der Gruppe Zentrale der Karte (unsichtbar, tragen die E-Aufforderung), siehe CasinoService
CasinoConfig.Points = {
	Slot = { "Casino_Slot1", "Casino_Slot2", "Casino_Slot3", "Casino_Slot4" },
	Roulette = "Casino_Roulette",
	Blackjack = "Casino_Blackjack", -- allein gegen den Croupier
	Table = "Casino_Table",         -- Tisch für mehrere Spieler
}
CasinoConfig.Range = 9 -- so nah muss man am Punkt stehen (E-Aufforderung und jede Aktion)

-- Einsatz je Währung: kleinster, größter und die Stufen zum Durchschalten im Fenster
CasinoConfig.Currencies = {
	Coins = { Name = "MÜNZEN", Min = 50, Max = 5000, Steps = { 50, 100, 250, 500, 1000, 2500, 5000 }, Paid = true },
	RedPoints = { Name = "RZ", Min = 5, Max = 500, Steps = { 5, 10, 25, 50, 100, 250, 500 }, Paid = false },
}
CasinoConfig.CurrencyOrder = { "Coins", "RedPoints" }

-- ---------- Spielautomat: 3 Walzen, je Walze ein Symbol nach Gewicht ----------
-- Three = Auszahlung (Vielfaches des Einsatzes, inkl. Einsatz) bei drei gleichen, Two = bei genau zwei gleichen.
-- Rückzahlquote etwa 94 % (Test casino rechnet sie nach).
CasinoConfig.Slots = {
	Symbols = {
		{ Id = "Cherry", Text = "🍒", Name = "KIRSCHE", Weight = 30, Three = 7, Two = 0.5 },
		{ Id = "Lemon", Text = "🍋", Name = "ZITRONE", Weight = 25, Three = 9, Two = 0.5 },
		{ Id = "Bell", Text = "🔔", Name = "GLOCKE", Weight = 20, Three = 14, Two = 1 },
		{ Id = "Bar", Text = "BAR", Name = "BAR", Weight = 13, Three = 25, Two = 1.5 },
		{ Id = "Seven", Text = "7", Name = "SIEBEN", Weight = 8, Three = 60, Two = 3 },
		{ Id = "Skull", Text = "💀", Name = "TOTENKOPF", Weight = 4, Three = 200, Two = 5 },
	},
}

-- ---------- Roulette (europäisch, 0 bis 36) ----------
CasinoConfig.RedNumbers = { 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36 }
-- Wetten: Auszahlung inkl. Einsatz; Number braucht eine Zahl 0..36
CasinoConfig.RouletteBets = {
	{ Id = "Red", Name = "ROT", Pays = 2 },
	{ Id = "Black", Name = "SCHWARZ", Pays = 2 },
	{ Id = "Even", Name = "GERADE", Pays = 2 },
	{ Id = "Odd", Name = "UNGERADE", Pays = 2 },
	{ Id = "Low", Name = "1–18", Pays = 2 },
	{ Id = "High", Name = "19–36", Pays = 2 },
	{ Id = "Dozen1", Name = "1–12", Pays = 3 },
	{ Id = "Dozen2", Name = "13–24", Pays = 3 },
	{ Id = "Dozen3", Name = "25–36", Pays = 3 },
	{ Id = "Number", Name = "ZAHL", Pays = 36 },
}

-- ---------- Blackjack ----------
-- Endloser Schuh (jede Karte zufällig), Croupier zieht bis 17 (bleibt bei weicher 17), Blackjack zahlt 3:2,
-- Verdoppeln auf den ersten zwei Karten, kein Teilen, keine Versicherung.
CasinoConfig.Blackjack = {
	BlackjackPays = 2.5, -- inkl. Einsatz
	DealerStands = 17,
	TurnTime = 20,       -- Sekunden je Zug, danach hält man automatisch
	BetTime = 12,        -- Tisch: so lange nach dem ersten Einsatz können weitere setzen
	ResultTime = 5,      -- Ergebnis so lange zeigen, dann neue Runde
	Seats = 4,
	-- ungefähre Chancen je Hand bei guter Spielweise (Anzeige vor dem Spiel)
	Odds = { Win = 0.42, Push = 0.09, Lose = 0.49 },
}

-- ---------- Regeln ----------

-- Summe der Walzen-Gewichte
local function weightTotal()
	local total = 0
	for _, symbol in CasinoConfig.Slots.Symbols do
		total += symbol.Weight
	end
	return total
end

function CasinoConfig.Symbol(id)
	for _, symbol in CasinoConfig.Slots.Symbols do
		if symbol.Id == id then
			return symbol
		end
	end
	return nil
end

-- Ein Walzen-Symbol würfeln (r = Zufallszahl 0..1)
function CasinoConfig.RollSymbol(r)
	local pick = r * weightTotal()
	for _, symbol in CasinoConfig.Slots.Symbols do
		pick -= symbol.Weight
		if pick < 0 then
			return symbol.Id
		end
	end
	return CasinoConfig.Slots.Symbols[#CasinoConfig.Slots.Symbols].Id
end

-- Auszahlung (Vielfaches des Einsatzes) und Art ("Three", "Two" oder nil) für drei Walzen
function CasinoConfig.SlotPayout(reels)
	local counts = {}
	for _, id in reels do
		counts[id] = (counts[id] or 0) + 1
	end
	local best, kind = 0, nil
	for id, n in counts do
		local symbol = CasinoConfig.Symbol(id)
		if symbol and n == 3 and symbol.Three > best then
			best, kind = symbol.Three, "Three"
		elseif symbol and n == 2 and symbol.Two > best then
			best, kind = symbol.Two, "Two"
		end
	end
	return best, kind
end

-- Chancen aller Ergebnisse (für die Anzeige, Summe 1): { { Text, Chance, Pays } }, dazu die Rückzahlquote
function CasinoConfig.SlotOdds()
	local total = weightTotal()
	local list, none, rtp = {}, 1, 0
	for _, symbol in CasinoConfig.Slots.Symbols do
		local p = symbol.Weight / total
		local three = p * p * p
		local two = 3 * p * p * (1 - p)
		table.insert(list, { Text = "3× " .. symbol.Name, Chance = three, Pays = symbol.Three })
		table.insert(list, { Text = "2× " .. symbol.Name, Chance = two, Pays = symbol.Two })
		none -= three + two
		rtp += three * symbol.Three + two * symbol.Two
	end
	table.insert(list, { Text = "KEIN GEWINN", Chance = none, Pays = 0 })
	return list, rtp
end

local isRed = {}
for _, n in CasinoConfig.RedNumbers do
	isRed[n] = true
end

function CasinoConfig.RouletteColor(n)
	if n == 0 then
		return "Green"
	end
	return isRed[n] and "Red" or "Black"
end

function CasinoConfig.RouletteBet(id)
	for _, bet in CasinoConfig.RouletteBets do
		if bet.Id == id then
			return bet
		end
	end
	return nil
end

-- Gewinnt die Wette bei Zahl n? (number = gesetzte Zahl bei "Number")
function CasinoConfig.RouletteWins(betId, n, number)
	if betId == "Number" then
		return n == number
	elseif n == 0 then
		return false
	elseif betId == "Red" then
		return isRed[n] == true
	elseif betId == "Black" then
		return not isRed[n]
	elseif betId == "Even" then
		return n % 2 == 0
	elseif betId == "Odd" then
		return n % 2 == 1
	elseif betId == "Low" then
		return n <= 18
	elseif betId == "High" then
		return n >= 19
	elseif betId == "Dozen1" then
		return n <= 12
	elseif betId == "Dozen2" then
		return n >= 13 and n <= 24
	elseif betId == "Dozen3" then
		return n >= 25
	end
	return false
end

-- Gewinnchance einer Wette (0..1)
function CasinoConfig.RouletteChance(betId)
	local wins = 0
	for n = 0, 36 do
		if CasinoConfig.RouletteWins(betId, n, 7) then
			wins += 1
		end
	end
	return wins / 37
end

-- Karten: 1 = Ass, 11/12/13 = Bube/Dame/König
local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "B", "D", "K" }
CasinoConfig.Suits = { "♠", "♥", "♦", "♣" }

function CasinoConfig.CardText(card)
	return RANKS[card.R] .. CasinoConfig.Suits[card.S]
end

-- Wert einer Hand (Asse als 11, solange es nicht über 21 geht) und ob sie weich ist
function CasinoConfig.HandValue(cards)
	local total, aces = 0, 0
	for _, card in cards do
		local rank = card.R
		if rank == 1 then
			aces += 1
			total += 11
		else
			total += math.min(rank, 10)
		end
	end
	while total > 21 and aces > 0 do
		total -= 10
		aces -= 1
	end
	return total, aces > 0
end

function CasinoConfig.IsBlackjack(cards)
	return #cards == 2 and (CasinoConfig.HandValue(cards)) == 21
end

-- Auszahlung (Vielfaches des Einsatzes, inkl. Einsatz) und Ergebnis ("Blackjack", "Win", "Push", "Lose", "Bust")
function CasinoConfig.BlackjackResult(playerCards, dealerCards)
	local mine = CasinoConfig.HandValue(playerCards)
	local theirs = CasinoConfig.HandValue(dealerCards)
	local myBj, theirBj = CasinoConfig.IsBlackjack(playerCards), CasinoConfig.IsBlackjack(dealerCards)
	if mine > 21 then
		return 0, "Bust"
	elseif myBj and not theirBj then
		return CasinoConfig.Blackjack.BlackjackPays, "Blackjack"
	elseif theirBj and not myBj then
		return 0, "Lose"
	elseif theirs > 21 or mine > theirs then
		return 2, "Win"
	elseif mine == theirs then
		return 1, "Push"
	end
	return 0, "Lose"
end

-- Erlaubter Einsatz? (ganze Zahl im Rahmen der Währung)
function CasinoConfig.ValidBet(currency, amount)
	local info = CasinoConfig.Currencies[currency]
	return info ~= nil and type(amount) == "number" and amount == math.floor(amount) and amount >= info.Min and amount <= info.Max
end

return CasinoConfig

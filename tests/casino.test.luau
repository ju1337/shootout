-- Casino (CasinoConfig, CasinoService): Regeln (Auszahlungen, Chancen, Kartenwerte), Spielautomat und Roulette mit Münzen
-- und RZ (Münzen nur mit PaidRandomOk), Blackjack allein gegen den Croupier und am Tisch mit zwei Spielern (Setzzeit,
-- Züge, Zeitlimit hält automatisch), Fenster zu beim Weggehen.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 1, 20)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local ProgressService = require("ProgressService")
ProgressService.Init()
local CasinoConfig = require("CasinoConfig")
local CasinoService = require("CasinoService")

-- ---------- Regeln ----------
local odds, rtp = CasinoConfig.SlotOdds()
local sum = 0
for _, entry in odds do
	sum += entry.Chance
end
check(math.abs(sum - 1) < 1e-9, "Automat: Chancen ergeben zusammen 100 % (" .. sum .. ")")
check(rtp > 0.9 and rtp < 0.97, "Automat: Rückzahlung unter 100 %, aber fair (" .. rtp .. ")")
check(CasinoConfig.SlotPayout({ "Seven", "Seven", "Seven" }) == 60, "drei Siebenen zahlen 60×")
check(CasinoConfig.SlotPayout({ "Cherry", "Bell", "Cherry" }) == 0.5, "zwei Kirschen zahlen 0,5×")
check(CasinoConfig.SlotPayout({ "Cherry", "Bell", "Lemon" }) == 0, "drei verschiedene: nichts")
check(CasinoConfig.RollSymbol(0) == "Cherry" and CasinoConfig.RollSymbol(0.999) == "Skull", "Walze nach Gewicht")
check(CasinoConfig.RouletteWins("Red", 1) and not CasinoConfig.RouletteWins("Red", 2) and not CasinoConfig.RouletteWins("Red", 0),
	"Roulette: 1 rot, 2 schwarz, 0 verliert")
check(CasinoConfig.RouletteWins("Number", 0, 0) and not CasinoConfig.RouletteWins("Number", 5, 6), "Roulette: Zahl")
check(math.abs(CasinoConfig.RouletteChance("Red") - 18 / 37) < 1e-9 and math.abs(CasinoConfig.RouletteChance("Number") - 1 / 37) < 1e-9,
	"Roulette: Chancen 18/37 und 1/37")
local function cards(...)
	local list = {}
	for _, r in { ... } do
		table.insert(list, { R = r, S = 1 })
	end
	return list
end
check(CasinoConfig.HandValue(cards(1, 13)) == 21 and CasinoConfig.IsBlackjack(cards(1, 13)), "Ass + König = Blackjack")
check(CasinoConfig.HandValue(cards(1, 1, 9)) == 21 and CasinoConfig.HandValue(cards(10, 9, 5)) == 24, "Asse zählen 1 oder 11")
check(CasinoConfig.BlackjackResult(cards(1, 12), cards(10, 9)) == 2.5, "Blackjack zahlt 3:2")
check(CasinoConfig.BlackjackResult(cards(10, 9), cards(10, 8)) == 2, "19 gegen 18 gewinnt")
check(CasinoConfig.BlackjackResult(cards(10, 8), cards(9, 9)) == 1, "Gleichstand: Einsatz zurück")
check(CasinoConfig.BlackjackResult(cards(10, 8, 7), cards(10, 6, 9)) == 0, "überkauft verliert auch gegen überkauften Croupier")
check(CasinoConfig.ValidBet("Coins", 50) and not CasinoConfig.ValidBet("Coins", 49) and not CasinoConfig.ValidBet("RedPoints", 7.5)
	and not CasinoConfig.ValidBet("Robux", 100), "Einsatzgrenzen")

-- ---------- Casino im Camp ----------
local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
local zentrale = Instance.new("Folder", map)
zentrale.Name = "Zentrale"
local function point(name, offset)
	local part = Instance.new("Part", zentrale)
	part.Name = name
	part.CFrame = CFrame.new(CENTER + offset)
	return part
end
for i, name in CasinoConfig.Points.Slot do
	point(name, Vector3.new(-60, 2.5, i * 4))
end
point(CasinoConfig.Points.Roulette, Vector3.new(-50, 2.5, 0))
point(CasinoConfig.Points.Blackjack, Vector3.new(-40, 2.5, 0))
local tablePoint = point(CasinoConfig.Points.Table, Vector3.new(-30, 2.5, 0))
CasinoService.Init({ Map = map })
check(zentrale[CasinoConfig.Points.Table]:FindFirstChildOfClass("ProximityPrompt") ~= nil
	and zentrale.Casino_Slot1:FindFirstChildOfClass("ProximityPrompt") ~= nil, "E-Aufforderungen an den Punkten")

store.Data.u1 = { XP = {}, Coins = 10000, Rap = 0, Owned = {}, Equipped = {}, RedPoints = 1000 }
store.Data.u2 = { XP = {}, Coins = 10000, Rap = 0, Owned = {}, Equipped = {}, RedPoints = 1000 }
local alice = SIM.Join("Alice")
local bob = SIM.Join("Bob")
step(2)
for _, player in { alice, bob } do
	player:LoadCharacter()
end
step(0.5)
alice:SetAttribute("PaidRandomOk", true)
bob:SetAttribute("PaidRandomOk", false) -- Land ohne bezahlte Zufallsitems
local function stand(player, name)
	player.Character:PivotTo(CFrame.new(zentrale[name].Position + Vector3.new(0, 0.5, -2)))
end
local function coins(player)
	return ProgressService.Get(player).Coins
end
local function rz(player)
	return ProgressService.Get(player).RedPoints
end
local function last(player, kind)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "CasinoUpdate" and entry.Player == player and entry.Args[1] == kind then
			return entry.Args[2], i
		end
	end
	return nil, 0
end

-- Zufall zum Festlegen: NextNumber liefert number, NextInteger die nächste Zahl aus queue (sonst die Untergrenze)
local queue, number = {}, 0.999
CasinoService.SetRandom({
	NextNumber = function()
		return number
	end,
	NextInteger = function(_, low)
		return table.remove(queue, 1) or low
	end,
})

-- Spielautomat: drei Totenköpfe zahlen 200×
stand(alice, "Casino_Slot1")
CasinoService.Open(alice, "Slot")
check((last(alice, "Open") or {}).Game == "Slot" and (last(alice, "Open") or {}).PaidOk == true, "Automat: Fenster offen")
local before = coins(alice)
CasinoService.Action(alice, "Slot", "Coins", 100)
local result = last(alice, "Slot")
check(result and result.Win == 20000 and result.Reels[1] == "Skull", "Automat: Jackpot 200× (" .. tostring(result and result.Win) .. ")")
check(coins(alice) == before - 100 + 20000, "Automat: Einsatz ab, Gewinn gutgeschrieben (" .. coins(alice) .. ")")
CasinoService.Action(alice, "Slot", "Coins", 100) -- dreht noch
check(coins(alice) == before - 100 + 20000, "Automat: während des Drehens kein zweiter Einsatz")
step(1.5)
number = 0 -- drei Kirschen: 7×
CasinoService.Action(alice, "Slot", "Coins", 49)
check(coins(alice) == before - 100 + 20000, "Automat: zu kleiner Einsatz wird abgelehnt")
CasinoService.Action(alice, "Slot", "Coins", 50)
check(coins(alice) == before - 100 + 20000 - 50 + 350, "Automat: drei Kirschen 7×")

-- Münzen nur mit PaidRandomOk; RZ geht immer
stand(bob, "Casino_Slot2")
CasinoService.Open(bob, "Slot")
check((last(bob, "Open") or {}).PaidOk == false, "Bob: Münz-Spiele aus")
local bobCoins = coins(bob)
CasinoService.Action(bob, "Slot", "Coins", 100)
check(coins(bob) == bobCoins and string.find(tostring(last(bob, "Status")), "RZ") ~= nil, "Bob: Münz-Einsatz abgelehnt")
CasinoService.Action(bob, "Slot", "RedPoints", 10)
check(rz(bob) == 1000 - 10 + 70 and bob:GetAttribute("RedPoints") == rz(bob), "Bob: mit RZ gespielt (" .. rz(bob) .. ")")
CasinoService.Action(bob, "Slot", "RedPoints", 5000)
step(1.5)
CasinoService.Action(bob, "Slot", "RedPoints", 500)
step(1.5)
check(rz(bob) == 1000 - 10 + 70 - 500 + 3500, "Bob: höchster RZ-Einsatz 500")

-- Roulette: 7 ist rot
stand(alice, "Casino_Roulette")
CasinoService.Open(alice, "Roulette")
before = coins(alice)
queue = { 7 }
CasinoService.Action(alice, "Roulette", "Coins", 100, "Red")
check((last(alice, "Roulette") or {}).Number == 7 and coins(alice) == before + 100, "Roulette: Rot gewinnt doppelt")
step(2.5)
queue = { 7 }
CasinoService.Action(alice, "Roulette", "Coins", 100, "Number", 7)
check(coins(alice) == before + 100 + 3500, "Roulette: Zahl zahlt 36×")
step(2.5)
queue = { 0 }
CasinoService.Action(alice, "Roulette", "Coins", 100, "Black")
check(coins(alice) == before + 100 + 3500 - 100, "Roulette: 0 verliert")
step(2.5)
CasinoService.Action(alice, "Roulette", "Coins", 100, "Number", 40)
check(coins(alice) == before + 100 + 3500 - 100, "Roulette: Zahl außerhalb 0–36 abgelehnt")

-- Blackjack allein: Croupier 10 + 7, Alice 10 + 9, halten gewinnt
stand(alice, "Casino_Blackjack")
CasinoService.Open(alice, "Blackjack")
before = coins(alice)
queue = { 10, 1, 7, 2, 10, 3, 9, 4 }
CasinoService.Action(alice, "Bet", "Coins", 200)
local state = CasinoService.TableState(alice)
check(state and state.Phase == "Play" and state.Turn == 1 and #state.Seats[1].Cards == 2 and state.Dealer[2].R == 0,
	"Blackjack: sofort gegeben, Karte 2 des Croupiers verdeckt")
check(coins(alice) == before - 200, "Blackjack: Einsatz ab")
CasinoService.Action(alice, "Stand")
state = CasinoService.TableState(alice)
check(state.Phase == "Result" and state.Seats[1].Result == "Win" and coins(alice) == before + 200,
	"Blackjack: 19 gegen 17 gewinnt (" .. tostring(state.Seats[1].Result) .. ")")
step(CasinoConfig.Blackjack.ResultTime + 0.5)
state = CasinoService.TableState(alice)
check(state.Phase == "Waiting" and not state.Seats[1].Bet, "Blackjack: neue Runde")
-- Verdoppeln: 5 + 6, dann 10 = 21 gegen 10 + 8
queue = { 10, 1, 8, 2, 5, 3, 6, 4, 10, 1 }
before = coins(alice)
CasinoService.Action(alice, "Bet", "Coins", 100)
CasinoService.Action(alice, "Double")
state = CasinoService.TableState(alice)
check(state.Phase == "Result" and state.Seats[1].Bet == 200 and state.Seats[1].Value == 21 and coins(alice) == before + 200,
	"Blackjack: verdoppelt, eine Karte, doppelter Gewinn")
step(CasinoConfig.Blackjack.ResultTime + 0.5)

-- Tisch: Alice (Münzen) und Bob (RZ) setzen, nach der Setzzeit Karten, Alice verpasst ihren Zug (hält automatisch)
stand(alice, "Casino_Table")
stand(bob, "Casino_Table")
CasinoService.Open(alice, "Table")
CasinoService.Open(bob, "Table")
state = CasinoService.TableState(alice)
check(state and state.Size == 4 and state.Seats[1] and state.Seats[2] and state.Seats[1].UserId == alice.UserId,
	"Tisch: beide sitzen (Platz 1 und 2)")
before = coins(alice)
local bobRz = rz(bob)
CasinoService.Action(alice, "Bet", "Coins", 100)
state = CasinoService.TableState(alice)
check(state.Phase == "Betting", "Tisch: erster Einsatz startet die Setzzeit")
CasinoService.Action(bob, "Bet", "RedPoints", 50)
check(rz(bob) == bobRz - 50, "Tisch: Bob setzt RZ")
-- Karten: Croupier 10 + 8, Alice 10 + 7, Bob 10 + 2 (zieht 9)
queue = { 10, 1, 8, 2, 10, 3, 7, 4, 10, 1, 2, 2, 9, 3 }
step(CasinoConfig.Blackjack.BetTime + 0.5)
state = CasinoService.TableState(bob)
check(state.Phase == "Play" and state.Turn == 1, "Tisch: nach der Setzzeit Karten, Alice ist am Zug")
CasinoService.Action(bob, "Hit") -- nicht dran
check(#CasinoService.TableState(bob).Seats[2].Cards == 2, "Tisch: Bob darf nicht vor seinem Zug")
step(CasinoConfig.Blackjack.TurnTime + 0.5)
state = CasinoService.TableState(bob)
check(state.Turn == 2, "Tisch: Zeit um – Alice hält, Bob ist dran")
CasinoService.Action(bob, "Hit")
CasinoService.Action(bob, "Stand")
state = CasinoService.TableState(bob)
check(state.Phase == "Result" and state.Seats[1].Result == "Lose" and state.Seats[2].Result == "Win", "Tisch: Alice 17 verliert, Bob 21 gewinnt")
check(coins(alice) == before - 100 and rz(bob) == bobRz + 50, "Tisch: Auszahlung in der eigenen Währung")
check((last(alice, "Table") or {}).Phase == "Result", "Tisch: Stand geht an alle am Tisch")

-- Weggehen schließt das Fenster und gibt den Platz frei
alice.Character:PivotTo(CFrame.new(tablePoint.Position + Vector3.new(60, 0, 0)))
step(0.5)
local _, closedAt = last(alice, "Close")
check(closedAt > 0 and CasinoService.TableState(alice) == nil, "weggegangen: Fenster zu")
step(CasinoConfig.Blackjack.ResultTime + 0.5)
state = CasinoService.TableState(bob)
check(state and not state.Seats[1] and state.Seats[2], "Alices Platz ist frei, Bob sitzt noch")

if failures == 0 then
	print("Casino: alles in Ordnung")
end

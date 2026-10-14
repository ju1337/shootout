-- Casino-Fenster (CasinoClient): öffnet auf "Open" vom Server mit Chancen, Einsatz und Währung; ohne PaidRandomOk nur RZ;
-- DREHEN schickt den Einsatz, das Ergebnis des Servers steht danach auf den Walzen; Blackjack-Tisch zeigt Plätze, Karten
-- (verdeckte Karte des Croupiers) und nur die passenden Knöpfe; ✕ schließt und meldet es dem Server.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local Remotes = require("Remotes") -- als Server anlegen, dann Client
SIM.IsServer = false
local bob = SIM.Join("Bob")
rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
bob:SetAttribute("Coins", 1200)
bob:SetAttribute("RedPoints", 80)
bob:LoadCharacter()
SIM.Advance(0.5, 10)

local CasinoConfig = require("CasinoConfig")
local CasinoClient = require("CasinoClient")
CasinoClient.Init()

local function find(root, name)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local function texts(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
			table.insert(out, d.Text)
		end
	end
	return table.concat(out, " | ")
end
local function sent(action)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "CasinoAction" and entry.Args[1] == action then
			return entry.Args
		end
	end
	return nil
end

-- Spielautomat, Münzen erlaubt
Remotes.CasinoUpdate.OnClientEvent:Fire("Open", { Game = "Slot", PaidOk = true })
SIM.Advance(0.1, 2)
local gui = playerGui:FindFirstChild("Casino")
check(gui ~= nil and gui.Enabled, "Fenster offen")
local all = texts(gui)
check(string.find(all, "SPIELAUTOMAT", 1, true) ~= nil and string.find(all, "3× TOTENKOPF", 1, true) ~= nil
	and string.find(all, "KEIN GEWINN", 1, true) ~= nil and string.find(all, "RÜCKZAHLUNG", 1, true) ~= nil,
	"Automat: Titel und Chancen sichtbar")
check(string.find(all, "1.200 MÜNZEN", 1, true) ~= nil or string.find(all, "1,200 MÜNZEN", 1, true) ~= nil
	or string.find(all, "1200 MÜNZEN", 1, true) ~= nil, "Guthaben sichtbar: " .. all)
find(gui, "Currency_Coins").Activated:Fire()
find(gui, "More").Activated:Fire()
SIM.Advance(0.1, 2)
check(string.find(texts(gui), "100 MÜNZEN", 1, true) ~= nil, "Einsatz 100 Münzen eingestellt")
find(gui, "Spin").Activated:Fire()
local args = sent("Slot")
check(args and args[2] == "Coins" and args[3] == 100, "DREHEN schickt Währung und Einsatz")
Remotes.CasinoUpdate.OnClientEvent:Fire("Slot", { Reels = { "Seven", "Seven", "Seven" }, Win = 6000, Bet = 100, Currency = "Coins" })
SIM.Advance(2, 40)
local _, state = CasinoClient.Ui()
check(not state.Spinning, "Walzen stehen wieder")
all = texts(gui)
check(string.find(all, "GEWINN +6", 1, true) ~= nil, "Gewinn angezeigt: " .. all)
local sevens = 0
for _, d in find(gui, "Reels"):GetDescendants() do
	if d:IsA("TextLabel") and d.Text == "7" then
		sevens += 1
	end
end
check(sevens == 3, "drei Siebenen auf den Walzen (" .. sevens .. ")")

-- ohne PaidRandomOk: nur RZ
Remotes.CasinoUpdate.OnClientEvent:Fire("Open", { Game = "Roulette", PaidOk = false })
SIM.Advance(0.1, 2)
_, state = CasinoClient.Ui()
check(state.Currency == "RedPoints", "ohne Erlaubnis: RZ")
find(gui, "Currency_Coins").Activated:Fire()
check(state.Currency == "RedPoints" and string.find(texts(gui), "nicht erlaubt", 1, true) ~= nil, "Münzen bleiben gesperrt")
check(string.find(texts(gui), "ROT  ·  2×", 1, true) ~= nil, "Roulette: Chancen je Wette")
find(gui, "Bet_Dozen2").Activated:Fire()
find(gui, "Spin").Activated:Fire()
args = sent("Roulette")
check(args and args[2] == "RedPoints" and args[3] == CasinoConfig.Currencies.RedPoints.Steps[1] and args[4] == "Dozen2",
	"Roulette: gewählte Wette geschickt")

-- Blackjack-Tisch: Bob auf Platz 2, ist am Zug
Remotes.CasinoUpdate.OnClientEvent:Fire("Open", { Game = "Table", PaidOk = true, Seat = 2 })
Remotes.CasinoUpdate.OnClientEvent:Fire("Table", { Phase = "Play", Turn = 2, Deadline = workspace:GetServerTimeNow() + 10, Size = 4,
	Dealer = { { R = 10, S = 1 }, { R = 0, S = 0 } },
	Seats = {
		{ Name = "Alice", UserId = 99, Bet = 100, Currency = "Coins", Cards = { { R = 5, S = 2 }, { R = 9, S = 3 } }, Value = 14 },
		{ Name = "Bob", UserId = bob.UserId, Bet = 10, Currency = "RedPoints", Cards = { { R = 1, S = 1 }, { R = 7, S = 4 } }, Value = 18 },
		false, false,
	} })
SIM.Advance(0.1, 2)
all = texts(gui)
check(string.find(all, "BLACKJACK-TISCH", 1, true) ~= nil and string.find(all, "Alice", 1, true) ~= nil
	and string.find(all, "DU", 1, true) ~= nil and string.find(all, "A♠", 1, true) ~= nil and string.find(all, "?", 1, true) ~= nil,
	"Tisch: Plätze, Karten und verdeckte Karte: " .. all)
check(find(gui, "Hit").Visible and find(gui, "Stand").Visible and find(gui, "Double").Visible and not find(gui, "Bet").Visible,
	"am Zug: KARTE, HALTEN, VERDOPPELN")
find(gui, "Stand").Activated:Fire()
check(sent("Stand") ~= nil, "HALTEN geschickt")

find(gui, "Close").Activated:Fire()
check(not gui.Enabled and sent("Leave") ~= nil, "✕ schließt und meldet Leave")

if failures == 0 then
	print("Casino-Fenster: alles in Ordnung")
end

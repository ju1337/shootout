-- Bezahlte Zufallsitems (Roblox-Regeln): Prozent-Anzeige, Chancen von Glücksrad und Kiste (je Ergebnis, Summe 100 %),
-- PolicyGate sperrt Kisten und Handel (Tausch, Markt), wo PolicyService es verbietet, und rechnet bei Fehlern mit
-- dem Verbot; Fenster CHANCEN, Glücksrad-Drehs im Robux-Shop mit CHANCEN-Knopf bzw. ausgeblendet
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Run(SIM.Now + (seconds or 1))
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local PaidRandom = require("PaidRandom")
local LoginConfig = require("LoginConfig")
local CrateConfig = require("CrateConfig")
local RobuxConfig = require("RobuxConfig")

-- Prozent
check(PaidRandom.Percent(0.26) == "26 %", "26 %: " .. PaidRandom.Percent(0.26))
check(PaidRandom.Percent(1) == "100 %", "100 %")
check(PaidRandom.Percent(1 / 150) == "0.6667 %", "4 Stellen ab der ersten Ziffer: " .. PaidRandom.Percent(1 / 150))
check(PaidRandom.Percent(0.28 / 3) == "9.333 %", "9.333 %: " .. PaidRandom.Percent(0.28 / 3))
check(PaidRandom.Percent(0.125) == "12.5 %", "Nullen am Ende weg: " .. PaidRandom.Percent(0.125))
check(PaidRandom.IsRandomProduct(RobuxConfig.Products[4]) and RobuxConfig.Products[4].Spins ~= nil, "Glücksrad-Drehs sind Zufall")
check(not PaidRandom.IsRandomProduct(RobuxConfig.Products[1]), "Münzen sind kein Zufall")

-- Chancen summieren sich zu 100 %
local sum = 0
for index, chance in LoginConfig.WheelOdds() do
	check(chance > 0 and chance == LoginConfig.Wheel[index].Weight / 100, "Glücksrad-Feld " .. index)
	sum += chance
end
check(math.abs(sum - 1) < 1e-9, "Glücksrad: Summe 100 %")
local crate = CrateConfig.Get("Weapon")
local itemOdds = CrateConfig.ItemOdds(crate)
sum = 0
local count = 0
for _, item in CrateConfig.Pool(crate) do
	check((itemOdds[item.Id] or 0) > 0, "Kiste: Chance für " .. item.Id)
	sum += itemOdds[item.Id] or 0
	count += 1
end
check(count > 0 and math.abs(sum - 1) < 1e-9, "Kiste: Summe je Skin 100 % (" .. sum .. ")")
for _, entry in CrateConfig.Odds(crate) do
	local first = nil
	for _, item in CrateConfig.Pool(crate) do
		if item.Rarity == entry.Rarity then
			first = first or itemOdds[item.Id]
			check(math.abs(itemOdds[item.Id] - entry.Chance / entry.Count) < 1e-12, "gleiche Chance je Seltenheit: " .. item.Id)
		end
	end
end

-- Server
local ProgressService = require("ProgressService")
local EconomyService = require("EconomyService")
local CrateService = require("CrateService")
local TradeService = require("TradeService")
local PolicyGate = require("PolicyGate")
ProgressService.Init()
EconomyService.Init()
CrateService.Init()
TradeService.Init()

store.Data.u1 = { XP = {}, Coins = 5000, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 5000, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u3 = { XP = {}, Coins = 5000, Rap = 0, Owned = {}, Equipped = {} }
local free, belgian, unknown = SIM.Join("Frei"), SIM.Join("Belgier"), SIM.Join("Unbekannt")
step(2)
local function place(player, mode, position)
	player:SetAttribute("Mode", mode)
	local rig = player.Character or SIM.MakeRig(player.Name)
	rig.Parent = workspace
	player.Character = rig
	rig:PivotTo(CFrame.new(position))
end
for index, player in { free, belgian, unknown } do
	place(player, "Market", Vector3.new(index * 3, 3, 0))
end

-- frei: Kiste geht, Attribute gesetzt
local ok, result = CrateService.Open(free, "Weapon")
check(ok == true, "Kiste ohne Einschränkung: " .. tostring(result))
check(free:GetAttribute("PaidRandomOk") == true and free:GetAttribute("PaidTradeOk") == true, "Attribute für die Anzeige")

-- eingeschränkt: Kiste zu, Münzen unangetastet, Tausch gesperrt
SIM.Policy = { ArePaidRandomItemsRestricted = true, IsPaidItemTradingAllowed = false }
local coinsBefore = belgian:GetAttribute("Coins")
step(2) -- Kisten-Abklingzeit
ok, result = CrateService.Open(belgian, "Weapon")
check(ok == false and string.find(result, "Land", 1, true) ~= nil, "Kiste gesperrt: " .. tostring(result))
check(belgian:GetAttribute("Coins") == coinsBefore, "keine Münzen abgebucht")
check(belgian:GetAttribute("PaidRandomOk") == false and belgian:GetAttribute("PaidTradeOk") == false, "Attribute: verboten")
local message, success = TradeService.Do(belgian, "Request", free.UserId)
check(success == false and string.find(message, "Land", 1, true) ~= nil, "Tausch-Anfrage gesperrt: " .. tostring(message))
message, success = TradeService.Do(free, "Request", belgian.UserId)
check(success == false and string.find(message, "Belgier", 1, true) ~= nil, "mit Gesperrtem nicht tauschen: " .. tostring(message))
check(PolicyGate.TradeAllowed(free) == true, "Antwort je Spieler gemerkt (Frei bleibt erlaubt)")

-- PolicyService antwortet nicht: vorsichtig sperren, später nochmal fragen
SIM.Policy = { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = true }
SIM.PolicyFail = PolicyGate.Tries
local done = false
task.spawn(function()
	ok, result = CrateService.Open(unknown, "Weapon")
	done = true
end)
step(10)
check(done and ok == false, "Abfrage fehlgeschlagen: Kiste zu")
check(unknown:GetAttribute("PaidRandomOk") == false, "ohne Antwort auch in der Anzeige gesperrt")
check(PolicyGate.RandomAllowed(unknown) == false, "Fehlschlag eine Weile gemerkt (kein erneutes Warten)")
step(PolicyGate.RetryAfter + 1)
check(PolicyGate.RandomAllowed(unknown) == true and unknown:GetAttribute("PaidRandomOk") == true, "nächste Abfrage klappt")

-- gekaufte Glücksrad-Drehs: nur ohne Länder-Sperre
ProgressService.SpinWheel(belgian) -- Gratis-Dreh von heute verbrauchen
step(6)
ProgressService.AddSpins(belgian, 1, true)
local spinMessage, spinOk = ProgressService.SpinWheel(belgian)
check(spinOk == false and string.find(tostring(spinMessage), "Land", 1, true) ~= nil, "gekaufter Dreh gesperrt: " .. tostring(spinMessage))
ProgressService.AddSpins(belgian, 1)
spinMessage, spinOk = ProgressService.SpinWheel(belgian)
check(spinOk ~= false, "verdienter Extra-Dreh geht: " .. tostring(spinMessage))

-- Client: Fenster CHANCEN und Robux-Shop
SIM.IsServer = false
rawget(SIM.Players, "__props").LocalPlayer = belgian
Instance.new("PlayerGui", belgian)
local OddsPanel = require("OddsPanel")
local rows = OddsPanel.WheelRows()
check(#rows == #LoginConfig.Wheel, "eine Zeile je Feld")
check(rows[1].Text == "50 Münzen" and rows[6].Text == "Skin Glücksklee" and string.sub(rows[8].Text, 1, 7) == "JACKPOT", "Gewinne beschrieben")
local frame = OddsPanel.Show("Glücksrad", rows)
local percents = {}
for _, d in frame:GetDescendants() do
	if d:IsA("TextLabel") and d.Name == "Chance" then
		table.insert(percents, d.Text)
	end
end
check(#percents == #rows and table.find(percents, "26 %") and table.find(percents, "2 %"), "Prozent je Zeile")
check(OddsPanel.IsOpen(), "Fenster offen")
OddsPanel.Close()
check(not OddsPanel.IsOpen(), "Fenster zu")
check(PaidRandom.ShowRandom(belgian) == false and PaidRandom.ShowRandom(free) == true, "Anzeige folgt dem Attribut")

if failures > 0 then
	error(failures .. " Fehler")
end
print("paidrandom: alles ok")

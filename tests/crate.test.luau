-- Kisten: nur die Waffen-Kiste (die Agenten-Kiste ist ausgebaut), Pool und Chancen, Öffnen (Ort, Münzen, Wartezeit),
-- Gewinn im Inventar, Duplikate (Münzen zurück), handelbare Duplikate als zweites Stück, Rolle mit dem Gewinn an festem Platz
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
local Remotes = require("Remotes")
local Cosmetics = require("Cosmetics")
local RapConfig = require("RapConfig")
local CrateConfig = require("CrateConfig")
local ProgressService = require("ProgressService")
local CrateService = require("CrateService")
ProgressService.Init()
CrateService.Init()

-- Pool
local weaponCrate = CrateConfig.Get("Weapon")
check(weaponCrate ~= nil and #CrateConfig.Crates == 1, "genau eine Kiste: die Waffen-Kiste")
check(CrateConfig.Get("Agent") == nil, "die Agenten-Kiste gibt es nicht mehr")
check(CrateConfig.Get("Nix") == nil, "unbekannte Kiste")
local weaponPool = CrateConfig.Pool(weaponCrate)
check(#weaponPool >= 8, "genug Skins im Pool")
for _, item in weaponPool do
	check(item.Type == "Weapon" and Cosmetics.ForSale(item), "Waffen-Pool: nur kaufbare Waffen-Skins (" .. item.Id .. ")")
	check(RapConfig.Tradeable(item.Id), "Waffen-Pool: handelbar mit RAP-Wert (" .. item.Id .. ")")
	check(not item.Pass and not item.Reward and not item.Robux, "keine Pass-, Belohnungs- oder Robux-Skins in der Kiste")
end

-- Chancen
for _, crate in CrateConfig.Crates do
	local sum = 0
	for _, entry in CrateConfig.Odds(crate) do
		sum += entry.Chance
		check(entry.Count > 0, crate.Id .. ": Seltenheit " .. entry.Rarity .. " hat Skins")
	end
	check(math.abs(sum - 1) < 1e-9, crate.Id .. ": Chancen ergeben 100 %")
end
local weaponOdds = CrateConfig.Odds(weaponCrate)
check(#weaponOdds == 4 and weaponOdds[1].Rarity == "Common" and weaponOdds[4].Rarity == "Legendary", "Waffen-Kiste: alle vier Seltenheiten")
check(weaponOdds[1].Chance > weaponOdds[2].Chance and weaponOdds[3].Chance > weaponOdds[4].Chance, "seltener = unwahrscheinlicher")

-- Verteilung beim Ziehen (feste Zufallszahlen)
local random = Random.new(7)
local seen, rarities, n = {}, {}, 6000
for _ = 1, n do
	local item = CrateConfig.Roll(weaponCrate, random)
	seen[item.Id] = true
	rarities[item.Rarity] = (rarities[item.Rarity] or 0) + 1
	check(item.Type == "Weapon", "Waffen-Kiste gibt nur Waffen-Skins")
end
for _, entry in weaponOdds do
	local share = (rarities[entry.Rarity] or 0) / n
	check(math.abs(share - entry.Chance) < 0.03, "Waffen-Kiste " .. entry.Rarity .. ": " .. share .. " statt " .. entry.Chance)
end
for _, item in weaponPool do
	check(seen[item.Id], "jeder Waffen-Skin kommt vor: " .. item.Id)
end

-- Öffnen
store.Data.u1 = { XP = {}, Coins = 100000, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 100, Rap = 0, Owned = {}, Equipped = {} }
local alice, bob = SIM.Join("Alice"), SIM.Join("Bob")
step(2)
local function lastResult(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "CrateResult" and entry.Player == player then
			return entry.Args[1]
		end
	end
	return nil
end

alice:SetAttribute("Mode", "Domination")
local ok, message = CrateService.Open(alice, "Weapon")
check(ok == false and string.find(message, "Markt", 1, true) ~= nil, "im Match keine Kisten: " .. tostring(message))
alice:SetAttribute("Mode", "Market")
check(CrateService.Open(alice, "Nix") == false, "unbekannte Kiste öffnen")
check(CrateService.Open(alice, "Agent") == false, "die alte Agenten-Kiste lässt sich nicht mehr öffnen")
check(CrateService.Open(alice, 42) == false, "Kisten-Id muss ein Text sein")
bob:SetAttribute("Mode", "Market")
ok, message = CrateService.Open(bob, "Weapon")
check(ok == false and string.find(message, "Münzen", 1, true) ~= nil, "Bob hat zu wenig Münzen: " .. tostring(message))
check(ProgressService.Get(bob).Coins == 100, "Bob behält seine Münzen")

local before = ProgressService.Get(alice).Coins
ok, message = CrateService.Open(alice, "Weapon")
check(ok == true, "Alice öffnet eine Waffen-Kiste: " .. tostring(message))
local result = message
check(result.Crate == "Weapon" and #result.Reel == CrateConfig.ReelLength, "Ergebnis mit Rolle")
check(result.Reel[result.Index] == result.Item and result.Index == CrateConfig.WinnerIndex, "Gewinn liegt an Platz " .. CrateConfig.WinnerIndex)
check(Cosmetics.Get(result.Item).Type == "Weapon", "Gewinn ist ein Waffen-Skin")
local after = ProgressService.Get(alice).Coins
check(after == before - weaponCrate.Price + result.Refund, "Münzen: -" .. weaponCrate.Price .. " (+ Rückgabe)")
check(result.Status == "new" and ProgressService.ItemCount(alice, result.Item) == 1, "neuer Skin im Inventar")
check(lastResult(alice) ~= nil and lastResult(alice).Item == result.Item, "Ergebnis ging an den Client")
check(alice:GetAttribute("Coins") == after, "Münzen-Attribut aktuell")
-- Wartezeit
ok, message = CrateService.Open(alice, "Weapon")
check(ok == false and string.find(message, "schnell", 1, true) ~= nil, "zu schnell hintereinander: " .. tostring(message))
check(ProgressService.Get(alice).Coins == after, "dabei kein Münzverlust")
step(CrateConfig.Cooldown + 0.1)

-- Viele Kisten: Duplikate und Stückzahlen
local coinsBefore = ProgressService.Get(alice).Coins
local spent, refunds, duplicates, copies = 0, 0, 0, 0
local expected = {}
expected[result.Item] = 1
for i = 1, 80 do
	local crate = weaponCrate
	local pre = ProgressService.Get(alice).Coins
	local opened, r = CrateService.Open(alice, crate.Id)
	check(opened == true, "Kiste " .. i .. " öffnen: " .. tostring(r))
	if opened then
		spent += crate.Price
		refunds += r.Refund
		local item = Cosmetics.Get(r.Item)
		check(item.Type == crate.Type, "Kiste " .. crate.Id .. " gibt Skin der Art " .. crate.Type)
		check(r.Reel[r.Index] == r.Item and #r.Reel == CrateConfig.ReelLength, "Rolle stimmt")
		for _, id in r.Reel do
			check(Cosmetics.Get(id) ~= nil and Cosmetics.Get(id).Type == crate.Type, "Rolle enthält nur Skins der Kiste")
		end
		local count = ProgressService.ItemCount(alice, r.Item)
		if RapConfig.Tradeable(r.Item) then
			expected[r.Item] = (expected[r.Item] or 0) + 1
			check(r.Status == "new" or r.Status == "copy", "handelbarer Skin ist nie ein Duplikat")
			if r.Status == "copy" then
				copies += 1
			end
			check(count == expected[r.Item], "handelbar: Stückzahl " .. count .. " statt " .. tostring(expected[r.Item]))
			check(r.Refund == 0, "handelbar: keine Rückgabe")
		else
			if r.Status == "duplicate" then
				duplicates += 1
				check(r.Refund == math.floor(item.Price * CrateConfig.DuplicateRefund), "Duplikat: Münzen zurück")
				check(count == 1, "Duplikat: weiter genau ein Stück")
			else
				check(count == 1 and not expected[r.Item], "erster gebundener Skin: ein Stück")
				expected[r.Item] = 1
			end
		end
		check(ProgressService.Get(alice).Coins == pre - crate.Price + r.Refund, "Münzen nach Kiste " .. i)
	end
	step(CrateConfig.Cooldown + 0.1)
end
check(copies > 0, "bei 80 Kisten kommt dasselbe handelbare Stück mehrfach vor (" .. copies .. ")")
check(duplicates == 0, "alle Kisten-Skins sind handelbar: nie ein Duplikat mit Münzen zurück (" .. duplicates .. ")")
check(ProgressService.Get(alice).Coins == coinsBefore - spent + refunds, "Gesamtbilanz der Münzen")
local weaponsOwned = 0
for id in ProgressService.Get(alice).Owned do
	local item = Cosmetics.Get(id)
	check(item ~= nil and item.Type == "Weapon", "nur Waffen-Skins aus der Kiste: " .. id)
	weaponsOwned += 1
end
check(weaponsOwned >= 8, "die Kiste hat viele verschiedene Skins geliefert (" .. weaponsOwned .. ")")
step(2)
check(store.Data.u1.Coins == ProgressService.Get(alice).Coins, "nach der Kiste gespeichert")

-- über das Remote, mit Fehlermeldung
Remotes.CrateAction.OnServerEvent:Fire(bob, "Open", "Weapon")
step(0.2)
local denied = lastResult(bob)
check(denied and denied.Ok == false and string.find(denied.Message, "Münzen", 1, true) ~= nil, "Remote: Fehlermeldung an Bob")
Remotes.CrateAction.OnServerEvent:Fire(alice, "Open", "Weapon")
step(0.2)
check(lastResult(alice) and lastResult(alice).Ok == true, "Remote: Alice bekommt das Ergebnis")
step(CrateConfig.Cooldown + 0.1)
Remotes.CrateAction.OnServerEvent:Fire(alice, "Open", "Agent")
step(0.2)
local gone = lastResult(alice)
check(gone and gone.Ok == false and string.find(gone.Message, "gibt es nicht", 1, true) ~= nil,
	"Remote: alte Agenten-Kiste wird abgelehnt: " .. tostring(gone and gone.Message))
Remotes.CrateAction.OnServerEvent:Fire(alice, "Quatsch", "Weapon")

if failures == 0 then
	print("Kisten: alles in Ordnung")
end

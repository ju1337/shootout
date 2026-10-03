-- RAP-Wirtschaft: alte Spielstände (Besitz = true), Stückzahlen, Duplikate handelbarer Skins, Rückverkauf ans
-- System, Reservierungen (Stand/Tausch), Austausch zwischen zwei Spielern mit Marktgebühr, alles oder nichts
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
local HttpService = game:GetService("HttpService")
local ProgressService = require("ProgressService")
local EconomyService = require("EconomyService")
local ShopService = require("ShopService")
local Remotes = require("Remotes")
local RapConfig = require("RapConfig")
ProgressService.Init()
EconomyService.Init()
ShopService.Init()

local function lastStatus(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "ShopStatus" and entry.Player == player then
			return entry.Args[1], entry.Args[2]
		end
	end
	return nil
end
local function action(player, ...)
	Remotes.ShopAction.OnServerEvent:Fire(player, ...)
	step(0.2)
	return lastStatus(player)
end
local function reservedAttr(player)
	return HttpService:JSONDecode(player:GetAttribute("Reserved") or "{}")
end

-- Werte: jeder handelbare Skin existiert, gebundene haben keinen Wert
local Cosmetics = require("Cosmetics")
for id, value in RapConfig.Values do
	check(Cosmetics.Get(id) ~= nil, "RAP-Wert für unbekannten Skin " .. id)
	check(type(value) == "number" and value > 0, "RAP-Wert positiv: " .. id)
	local item = Cosmetics.Get(id)
	check(item == nil or item.Rarity ~= "Common", "gewöhnliche Skins sind nicht handelbar: " .. id)
end
for _, id in { "W_Wald", "W_Rekrut", "W_PrestigeLegende", "W_SE_Champion" } do
	check(not RapConfig.Tradeable(id), id .. " ist gebunden")
end
check(RapConfig.Count({ X = true }, "X") == 1 and RapConfig.Count({ X = 3 }, "X") == 3 and RapConfig.Count({}, "X") == 0,
	"Stückzahl aus true/Zahl/nichts")
check(RapConfig.AfterFee(1000) == 950, "5 % Marktgebühr")
check(RapConfig.CleanPrice("12") == 12 and RapConfig.CleanPrice(0) == nil and RapConfig.CleanPrice(1 / 0) == nil
	and RapConfig.CleanPrice(0 / 0) == nil and RapConfig.CleanPrice(2.9) == 2, "Preise werden geprüft")

-- Alter Spielstand: Besitz als true, ausgerüstet
store.Data.u1 = { XP = {}, Coins = 50, Owned = { W_Lava = true, W_Wald = true }, Equipped = { ["W:Rifle"] = "W_Lava" } }
local alice = SIM.Join("Alice")
step(2)
check(ProgressService.IsLoaded(alice), "Profil geladen")
check(ProgressService.ItemCount(alice, "W_Lava") == 1 and ProgressService.Owns(alice, "W_Lava"), "true zählt als 1 Stück")
check(alice:GetAttribute("Rap") == 0, "ohne RAP-Feld: Guthaben 0")
check(alice:GetAttribute("RapValue") == RapConfig.Values.W_Lava, "Wert der Skins: " .. tostring(alice:GetAttribute("RapValue")))

-- Gebundene Skins kauft das System nicht
local message, ok = action(alice, "SellSkin", "W_Wald")
check(ok == false and ProgressService.Owns(alice, "W_Wald"), "gewöhnlicher Skin nicht verkaufbar")
message, ok = action(alice, "SellSkin", "W_Galaxie")
check(ok == false, "nicht besessener Skin nicht verkaufbar")

-- Rückverkauf: Skin weg, abgelegt, RAP drauf, gespeichert
message, ok = action(alice, "SellSkin", "W_Lava")
local price = RapConfig.SellPrice("W_Lava")
check(ok == true, "Lava verkauft: " .. tostring(message))
check(price == math.floor(RapConfig.Values.W_Lava * RapConfig.SellRate), "70 % des Werts")
check(alice:GetAttribute("Rap") == price, "RAP gutgeschrieben: " .. tostring(alice:GetAttribute("Rap")))
check(not ProgressService.Owns(alice, "W_Lava"), "Skin weg")
check(ProgressService.Get(alice).Equipped["W:Rifle"] == nil, "verkaufter Skin abgelegt")
check(alice:GetAttribute("RapValue") == 0, "Wert der Skins jetzt 0")
step(2)
check(store.Data.u1.Rap == price and store.Data.u1.Owned.W_Lava == nil, "sofort gespeichert")

-- Belohnungen: handelbare Skins als weiteres Stück, gebundene nur einmal
check(ProgressService.GrantSkin(alice, "W_Gluecksklee") == "new", "erstes Stück neu")
check(ProgressService.GrantSkin(alice, "W_Gluecksklee") == "copy", "zweites Stück = Duplikat")
check(ProgressService.GrantSkin(alice, "W_Gluecksklee") == "copy", "drittes Stück = Duplikat")
check(ProgressService.ItemCount(alice, "W_Gluecksklee") == 3, "drei Stück")
check(ProgressService.GrantSkin(alice, "W_Rekrut") == "new" and ProgressService.GrantSkin(alice, "W_Rekrut") == nil,
	"gebundener Skin nur einmal")
check(alice:GetAttribute("RapValue") == 3 * RapConfig.Values.W_Gluecksklee, "Wert zählt alle Stücke")

-- Reservierung: nur freie Stücke, nur handelbare
check(EconomyService.Reserve(alice, "W_Gluecksklee", 2, "Stand"), "zwei Stück an den Stand")
check(not EconomyService.Reserve(alice, "W_Gluecksklee", 2, "Trade"), "nur noch eins frei")
check(EconomyService.Reserve(alice, "W_Gluecksklee", 1, "Trade"), "das letzte in einen Tausch")
check(not EconomyService.Reserve(alice, "W_Rekrut", 1, "Stand"), "gebundene Skins nicht reservierbar")
check(EconomyService.Available(alice, "W_Gluecksklee") == 0, "keins mehr frei")
check(reservedAttr(alice).W_Gluecksklee == 3, "Reserved-Attribut für den Client")
message, ok = action(alice, "SellSkin", "W_Gluecksklee")
check(ok == false and string.find(message, "Stand", 1, true) ~= nil, "zurückgelegter Skin nicht verkaufbar: " .. tostring(message))
EconomyService.ClearKey(alice, "Trade")
check(EconomyService.Available(alice, "W_Gluecksklee") == 1 and reservedAttr(alice).W_Gluecksklee == 2, "Tausch freigegeben")
message, ok = action(alice, "SellSkin", "W_Gluecksklee", 2)
check(ok == false, "nur ein freies Stück: zwei auf einmal geht nicht")

-- Austausch (Markt-Kauf): Skin gegen RAP, Gebühr beim Verkäufer
store.Data.u2 = { XP = {}, Coins = 0, Rap = 1000, Owned = {}, Equipped = {} }
local bob = SIM.Join("Bob")
step(2)
local aliceRap = alice:GetAttribute("Rap")
local done, reason = EconomyService.Exchange(alice, bob, { Items = { W_Gluecksklee = 1 } }, { Rap = 1200 }, "Stand",
	RapConfig.MarketFee)
check(not done and reason ~= nil, "zu wenig RAP: kein Kauf")
check(ProgressService.ItemCount(alice, "W_Gluecksklee") == 3 and bob:GetAttribute("Rap") == 1000, "nichts geändert")
done = EconomyService.Exchange(alice, bob, { Items = { W_Gluecksklee = 1 } }, { Rap = 800 }, "Stand", RapConfig.MarketFee)
check(done, "Kauf am Stand")
check(ProgressService.ItemCount(alice, "W_Gluecksklee") == 2 and ProgressService.ItemCount(bob, "W_Gluecksklee") == 1,
	"Skin gewandert")
check(bob:GetAttribute("Rap") == 200, "Käufer zahlt 800")
check(alice:GetAttribute("Rap") == aliceRap + RapConfig.AfterFee(800), "Verkäufer bekommt 800 minus Gebühr")
check(EconomyService.ReservedCount(alice, "W_Gluecksklee", "Stand") == 1, "verkauftes Stück nicht mehr zurückgelegt")
step(2)
check(store.Data.u1.Owned.W_Gluecksklee == 2 and store.Data.u2.Owned.W_Gluecksklee == 1, "beide gespeichert")
-- Nicht zurückgelegte Skins wandern nicht
done = EconomyService.Exchange(bob, alice, { Items = { W_Gluecksklee = 1 } }, {}, "Trade")
check(not done and ProgressService.ItemCount(bob, "W_Gluecksklee") == 1, "ohne Reservierung kein Austausch")
check(not EconomyService.Exchange(alice, alice, {}, {}, "Trade"), "nicht mit sich selbst")

-- Letztes Stück eines ausgerüsteten Skins geht weg: abgelegt
ProgressService.SetEquipped(bob, "W:SMG", "W_Gluecksklee")
check(ProgressService.TakeItem(bob, "W_Gluecksklee", 1), "Stück weggenommen")
check(ProgressService.Get(bob).Equipped["W:SMG"] == nil, "abgelegt")
check(not ProgressService.TakeItem(bob, "W_Gluecksklee", 1), "kein Stück mehr da")

-- Verlässt ein Spieler das Spiel, sind seine Reservierungen weg (die Skins hat er noch)
SIM.Leave(alice)
step(3)
check(EconomyService.ReservedCount(alice, "W_Gluecksklee") == 0, "Reservierungen beim Verlassen gelöscht")
check(store.Data.u1.Owned.W_Gluecksklee == 2, "Skins bleiben im Spielstand")

-- Studio ohne DataStore-Zugriff: Stand nur für die Sitzung, Verkaufen geht trotzdem (nichts wird gespeichert)
SIM.IsStudio = true
store.FailNext = math.huge
local tester = SIM.Join("Tester")
step(120) -- alle Wiederholungen schlagen fehl
check(ProgressService.IsLoaded(tester), "Studio ohne DataStore: Profil gilt für die Sitzung")
ProgressService.GrantSkin(tester, "W_Lava")
message, ok = EconomyService.SellToSystem(tester, "W_Lava")
check(ok == true and tester:GetAttribute("Rap") == RapConfig.SellPrice("W_Lava"), "Studio: Rückverkauf geht: " .. tostring(message))
store.FailNext = 0
SIM.Leave(tester)
step(3)
check(store.Data["u" .. tester.UserId] == nil, "nicht geladener Stand wird nicht gespeichert")
SIM.IsStudio = false

if failures == 0 then
	print("RAP-Wirtschaft: alles in Ordnung")
end

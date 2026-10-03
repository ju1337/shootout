-- Integrationstest: ProgressService (Spielstand mit Sitzungssperre) + RobuxService (Käufe erst nach dem Speichern)
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
-- DataStore mit Verzögerung (0,3 s hin, 0,3 s zurück); store.FailNext = so viele Anfragen schlagen fehl
SIM.DataStoreLatency = 0.6
game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local ProgressService = require("ProgressService")
local RobuxService = require("RobuxService")
local RobuxConfig = require("RobuxConfig")
local market = game:GetService("MarketplaceService")
local coinPack = RobuxConfig.Products[1] -- 1.000 Münzen
RobuxConfig.ByProductId = function(id)
	return id == 4242 and coinPack or nil
end
ProgressService.Init()
RobuxService.Init()
local GRANTED, LATER = Enum.ProductPurchaseDecision.PurchaseGranted, Enum.ProductPurchaseDecision.NotProcessedYet

local function step(seconds)
	SIM.Run(SIM.Now + seconds)
end
local function receipt(player, id)
	local result
	task.spawn(function()
		result = market.ProcessReceipt({ PlayerId = player.UserId, ProductId = 4242, PurchaseId = id })
	end)
	step(30)
	return result
end

-- Bestehender Spielstand (altes Format ohne Sperre)
store.Data.u1 = { XP = {}, Coins = 300, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
step(5)
check(ProgressService.IsLoaded(alice), "Profil geladen")
check(alice:GetAttribute("Coins") == 300, "Münzen aus dem Stand: " .. tostring(alice:GetAttribute("Coins")))
check(store.Data.u1.Session and store.Data.u1.Session.Id == "server-1", "Server hält die Sperre")

-- Kauf normal: gutgeschrieben, gespeichert, bestätigt
check(receipt(alice, "p1") == GRANTED, "Kauf p1 bestätigt")
check(alice:GetAttribute("Coins") == 1300, "1.000 Münzen gutgeschrieben")
check(store.Data.u1.Coins == 1300, "gespeichert: " .. tostring(store.Data.u1.Coins))
check(receipt(alice, "p1") == GRANTED and alice:GetAttribute("Coins") == 1300, "gleicher Beleg nicht doppelt")

-- Speichern schlägt dauerhaft fehl: nicht bestätigen (Roblox fragt später erneut)
store.FailNext = math.huge
check(receipt(alice, "p2") == LATER, "Kauf p2 ohne Speichern nicht bestätigt")
check(alice:GetAttribute("Coins") == 2300, "im Spiel schon gutgeschrieben")
check(store.Data.u1.Coins == 1300, "im DataStore noch der alte Stand")
-- Störung vorbei: Roblox stellt p2 erneut zu -> nicht doppelt, jetzt gespeichert und bestätigt
store.FailNext = 0
check(receipt(alice, "p2") == GRANTED, "p2 beim zweiten Versuch bestätigt")
check(alice:GetAttribute("Coins") == 2300 and store.Data.u1.Coins == 2300, "nicht doppelt, gespeichert")

-- Verlassen: speichern und Sperre freigeben
ProgressService.AddCoins(alice, 50, "Test")
SIM.Leave(alice)
step(10)
check(store.Data.u1.Coins == 2350, "beim Verlassen gespeichert: " .. tostring(store.Data.u1.Coins))
check(store.Data.u1.Session == nil, "Sperre freigegeben")

-- Ein anderer Server hält das Profil (frisch): warten; nie freigegeben -> nach der Wartezeit übernehmen
store.Data.u2 = { XP = {}, Coins = 10, Owned = {}, Equipped = {}, Session = { Id = "server-2", Time = os.time() } }
local bob = SIM.Join("Bob")
step(5)
check(not ProgressService.IsLoaded(bob), "wartet auf die Freigabe")
step(40)
check(ProgressService.IsLoaded(bob) and bob:GetAttribute("Coins") == 10, "übernimmt nach der Wartezeit")
check(store.Data.u2.Session.Id == "server-1", "Sperre jetzt hier")

-- Laden klappt gar nicht: Spieler wird mit Hinweis gekickt (nicht ohne Speichern weiterspielen)
store.FailNext = math.huge
local carl = SIM.Join("Carl")
step(60)
check(SIM.Kicked[carl] ~= nil, "Carl gekickt: " .. tostring(SIM.Kicked[carl]))
store.FailNext = 0

-- Herunterfahren: alle verbliebenen speichern und freigeben
ProgressService.AddCoins(bob, 5, "Test")
local closed = false
task.spawn(function()
	for _, close in SIM.Closers do
		close()
	end
	closed = true
end)
step(30)
check(closed, "BindToClose fertig")
check(store.Data.u2.Coins == 15 and store.Data.u2.Session == nil, "beim Herunterfahren gespeichert und freigegeben: "
	.. tostring(store.Data.u2.Coins) .. " " .. tostring(store.Data.u2.Session and store.Data.u2.Session.Id))

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

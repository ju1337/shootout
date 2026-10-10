-- Tauschen: Anfrage (nur Markt oder Safe Zone der offenen Welt, nah beieinander), ablehnen, annehmen, gegenseitige Anfrage, Angebote (nur
-- handelbare freie Skins, RAP bis zum Guthaben), BEREIT + Countdown, Änderung nimmt BEREIT zurück, Abschluss
-- (alles auf einmal, gespeichert), Abbruch (Knopf, Moduswechsel, Spiel verlassen), fehlgeschlagener Tausch,
-- entfernte Agenten-Skins aus alten Spielständen sind weg und nicht tauschbar
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
local RapConfig = require("RapConfig")
local Remotes = require("Remotes")
local ProgressService = require("ProgressService")
local EconomyService = require("EconomyService")
local TradeService = require("TradeService")
ProgressService.Init()
EconomyService.Init()
TradeService.Init()

local function place(player, mode, position)
	player:SetAttribute("Mode", mode)
	local rig = player.Character or SIM.MakeRig(player.Name)
	rig.Parent = workspace
	player.Character = rig
	rig:PivotTo(CFrame.new(position))
end
local function act(player, ...)
	return TradeService.Do(player, ...)
end
local function updates(player, kind)
	local list = {}
	for _, entry in SIM.RemoteLog do
		if entry.Remote == "TradeUpdate" and entry.Player == player and entry.Args[1] == kind then
			table.insert(list, entry.Args[2])
		end
	end
	return list
end
local function last(player, kind)
	local list = updates(player, kind)
	return list[#list]
end

store.Data.u1 = { XP = {}, Coins = 0, Rap = 1000, Owned = { W_Lava = 2, W_Rekrut = true }, Equipped = { ["W:Rifle"] = "W_Lava" } }
-- Bobs alter Spielstand hat noch einen Agenten-Skin (gibt es nicht mehr)
store.Data.u2 = { XP = {}, Coins = 0, Rap = 500, Owned = { W_Kalender = 1, W_Chrom = 1, A_Ghost_Nebel = 1 },
	Equipped = { ["A:Ghost"] = "A_Ghost_Nebel" } }
store.Data.u3 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u4 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local alice, bob, carl, dana = SIM.Join("Alice"), SIM.Join("Bob"), SIM.Join("Carl"), SIM.Join("Dana")
step(2)
check(ProgressService.ItemCount(bob, "A_Ghost_Nebel") == 0 and ProgressService.ItemCount(bob, "W_Chrom") == 1,
	"alter Agenten-Skin beim Laden entfernt, Waffen-Skins bleiben")
check(next(ProgressService.Get(bob).Equipped) == nil, "kein Agenten-Skin mehr ausgerüstet")
place(alice, "Market", Vector3.new(0, 3, 0))
place(bob, "Domination", Vector3.new(4, 3, 0))

-- Anfrage
local message, ok = act(alice, "Request", bob.UserId)
check(ok == false, "nicht mit jemandem im Match")
place(bob, "Market", Vector3.new(80, 3, 0))
message, ok = act(alice, "Request", bob.UserId)
check(ok == false and string.find(message, "näher", 1, true) ~= nil, "zu weit weg: " .. tostring(message))
place(bob, "Market", Vector3.new(6, 3, 0))
check(select(2, act(alice, "Request", alice.UserId)) == false, "nicht mit sich selbst")
message, ok = act(alice, "Request", bob.UserId)
check(ok == true, "Anfrage geschickt")
local request = last(bob, "Request")
check(request and request.From == alice.UserId and request.Name == "Alice", "Bob bekommt die Anfrage")

-- Ablehnen
act(bob, "Respond", alice.UserId, false)
check(TradeService.TradeOf(alice) == nil, "abgelehnt: kein Tausch")
check(select(2, act(bob, "Respond", alice.UserId, true)) == false, "abgelehnte Anfrage gilt nicht mehr")
-- Abgelaufen
act(alice, "Request", bob.UserId)
step(RapConfig.TradeRequestTime + 1)
check(select(2, act(bob, "Respond", alice.UserId, true)) == false, "abgelaufene Anfrage gilt nicht")

-- Annehmen
act(alice, "Request", bob.UserId)
act(bob, "Respond", alice.UserId, true)
local trade = TradeService.TradeOf(alice)
check(trade ~= nil and TradeService.TradeOf(bob) == trade, "Tausch läuft")
local state = last(alice, "State")
check(state and state.Partner.Name == "Bob" and next(state.Mine.Items) == nil, "Stand an Alice")
check(select(2, act(carl, "Request", alice.UserId)) == false, "wer tauscht, nimmt keine Anfrage an")

-- Angebote
check(select(2, act(alice, "AddItem", "W_Rekrut")) == false, "gebundener Skin nicht tauschbar")
check(select(2, act(alice, "AddItem", "W_Galaxie")) == false, "nicht besessener Skin")
act(alice, "AddItem", "W_Lava")
act(alice, "AddItem", "W_Lava")
check(select(2, act(alice, "AddItem", "W_Lava")) == false, "nur zwei Stück Lava")
check(EconomyService.ReservedCount(alice, "W_Lava", "Trade") == 2, "beide Lava zurückgelegt")
act(alice, "RemoveItem", "W_Lava")
check(EconomyService.ReservedCount(alice, "W_Lava", "Trade") == 1, "eine Lava wieder raus")
check(select(2, act(alice, "SetRap", 5000)) == false, "nicht mehr RAP als vorhanden")
act(alice, "SetRap", 300)
act(bob, "AddItem", "W_Kalender")
check(select(2, act(bob, "AddItem", "A_Ghost_Nebel")) == false, "entfernter Agenten-Skin nicht tauschbar")
state = last(bob, "State")
check(state.Theirs.Items.W_Lava == 1 and state.Theirs.Rap == 300 and state.Mine.Items.W_Kalender == 1,
	"Bob sieht beide Angebote")

-- BEREIT: Änderung im Countdown nimmt BEREIT zurück, es wird nicht getauscht
act(alice, "Ready", true)
act(bob, "Ready", true)
check(last(alice, "State").Countdown ~= nil, "Countdown läuft, wenn beide bereit sind")
step(RapConfig.TradeConfirmTime - 1)
act(bob, "AddItem", "W_Chrom")
check(last(alice, "State").Mine.Ready == false and last(alice, "State").Countdown == nil, "Änderung: BEREIT zurück")
step(3)
check(ProgressService.ItemCount(bob, "W_Lava") == 0, "nach Änderung kein Tausch")
check(TradeService.TradeOf(alice) == trade, "Tausch läuft weiter")

-- BEREIT zu einem älteren Stand (Angebot hat sich inzwischen geändert): abgelehnt
local seen = last(bob, "State").OfferVersion
act(alice, "SetRap", 200)
local _, staleOk = act(bob, "Ready", true, seen)
check(staleOk == false and last(alice, "State").Theirs.Ready == false, "BEREIT zum alten Angebot zählt nicht")
act(alice, "SetRap", 300)

-- Beide wieder bereit (gleichzeitig, mit demselben gesehenen Stand): Tausch nach dem Countdown
local both = last(bob, "State").OfferVersion
act(alice, "Ready", true, both)
local _, bobOk = act(bob, "Ready", true, both)
check(bobOk ~= false, "gleichzeitiges BEREIT beider zählt (BEREIT ändert das Angebot nicht)")
step(RapConfig.TradeConfirmTime + 0.5)
check(TradeService.TradeOf(alice) == nil and TradeService.TradeOf(bob) == nil, "Tausch beendet")
check(ProgressService.ItemCount(alice, "W_Lava") == 1 and ProgressService.ItemCount(bob, "W_Lava") == 1, "Lava gewandert")
check(ProgressService.ItemCount(alice, "W_Kalender") == 1 and ProgressService.ItemCount(alice, "W_Chrom") == 1,
	"Bobs Skins bei Alice")
check(ProgressService.ItemCount(bob, "W_Kalender") == 0, "Bob hat den Kalender-Skin abgegeben")
check(alice:GetAttribute("Rap") == 700 and bob:GetAttribute("Rap") == 800, "RAP gewandert (ohne Gebühr)")
check(EconomyService.ReservedCount(alice, "W_Lava") == 0 and EconomyService.ReservedCount(bob, "W_Kalender") == 0,
	"keine Reservierungen mehr")
check(last(alice, "Done") ~= nil and last(bob, "Done") ~= nil, "beide bekommen die Abschluss-Meldung")
step(2)
check(store.Data.u1.Owned.W_Kalender == 1 and store.Data.u2.Owned.W_Lava == 1 and store.Data.u1.Rap == 700, "gespeichert")
check(store.Data.u2.Owned.A_Ghost_Nebel == nil and store.Data.u2.Equipped["A:Ghost"] == nil,
	"entfernter Agenten-Skin auch im gespeicherten Stand weg")

-- Gegenseitige Anfrage startet sofort
place(carl, "Market", Vector3.new(-1500, 3, -1500))
place(dana, "Market", Vector3.new(-1496, 3, -1500))
act(carl, "Request", dana.UserId)
act(dana, "Request", carl.UserId)
check(TradeService.TradeOf(carl) ~= nil and TradeService.TradeOf(carl) == TradeService.TradeOf(dana), "gegenseitig: Tausch startet")
-- Abbrechen per Knopf
act(dana, "Cancel")
check(TradeService.TradeOf(carl) == nil, "abgebrochen")
check(string.find(last(carl, "Closed").Reason, "Dana", 1, true) ~= nil, "Carl erfährt, wer abgebrochen hat")

-- Moduswechsel bricht ab, Skins werden frei
act(alice, "Request", bob.UserId)
act(bob, "Respond", alice.UserId, true)
act(alice, "AddItem", "W_Kalender")
check(EconomyService.ReservedCount(alice, "W_Kalender") == 1, "im Tausch zurückgelegt")
alice:SetAttribute("Mode", "Domination")
check(TradeService.TradeOf(bob) == nil and EconomyService.ReservedCount(alice, "W_Kalender") == 0, "Moduswechsel: abgebrochen, frei")

-- Fehlgeschlagener Tausch: RAP inzwischen ausgegeben -> nichts passiert
place(alice, "Market", Vector3.new(0, 3, 0))
act(alice, "Request", bob.UserId)
act(bob, "Respond", alice.UserId, true)
act(alice, "SetRap", 700)
act(bob, "AddItem", "W_Lava")
act(alice, "Ready", true)
act(bob, "Ready", true)
ProgressService.SpendRap(alice, 600) -- z.B. im Markt gekauft
step(RapConfig.TradeConfirmTime + 0.5)
check(TradeService.TradeOf(alice) == nil, "Tausch beendet")
check(ProgressService.ItemCount(bob, "W_Lava") == 1 and alice:GetAttribute("Rap") == 100 and bob:GetAttribute("Rap") == 800,
	"fehlgeschlagen: nichts getauscht")
check(string.find(last(alice, "Closed").Reason, "fehlgeschlagen", 1, true) ~= nil, "Grund wird gemeldet")

-- Spiel verlassen bricht ab
act(alice, "Request", bob.UserId)
act(bob, "Respond", alice.UserId, true)
act(bob, "AddItem", "W_Lava")
SIM.Leave(alice)
step(1)
check(TradeService.TradeOf(bob) == nil and EconomyService.ReservedCount(bob, "W_Lava") == 0, "Verlassen: abgebrochen, frei")

-- Offene Welt: nur in der Safe Zone; wer sie verlässt, bricht ab
place(carl, "Extinction", Vector3.new(-1500, 3, -1500))
place(dana, "Extinction", Vector3.new(-1496, 3, -1500))
carl:SetAttribute("InSafeZone", true)
dana:SetAttribute("InSafeZone", false)
check(select(2, act(carl, "Request", dana.UserId)) == false, "offene Welt draußen: kein Tausch")
dana:SetAttribute("InSafeZone", true)
act(carl, "Request", dana.UserId)
act(dana, "Respond", carl.UserId, true)
check(TradeService.TradeOf(carl) ~= nil, "Safe Zone: Tausch läuft")
dana:SetAttribute("InSafeZone", false)
check(TradeService.TradeOf(carl) == nil, "Safe Zone verlassen: abgebrochen")
place(dana, "Market", Vector3.new(-1496, 3, -1500))

-- Über das Remote (mit Rückmeldung)
place(carl, "Market", Vector3.new(-1500, 3, -1500))
Remotes.TradeAction.OnServerEvent:Fire(carl, "Request", dana.UserId)
step(0.2)
check(last(dana, "Request") ~= nil and last(dana, "Request").From == carl.UserId, "Anfrage über das Remote")

if failures == 0 then
	print("Tausch: alles in Ordnung")
end

-- Markt, Teil 2: Gebühr nach Preis, Gegenangebote (annehmen, ablehnen, Ablauf,
-- Preisänderung), Stand-Name, Merkliste samt Meldung, Preisverlauf (Durchschnitt, DataStore), Händler-Rangliste;
-- entfernte Agenten-Skins in alten Daten (Merkliste, Preisverlauf, lebender RAP) fallen weg
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
local RapConfig = require("RapConfig")
local Remotes = require("Remotes")
local ProgressService = require("ProgressService")
local EconomyService = require("EconomyService")
ProgressService.Init()
EconomyService.Init()

-- Markt-Map: drei Stände nebeneinander (Prompt vor der Theke, Platz hinter der Theke)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Market"
for _, name in { "Spawns", "Portals" } do
	Instance.new("Folder", map).Name = name
end
local spawn = Instance.new("Part", map.Spawns)
spawn.CFrame = CFrame.new(-1500, 1, -1536)
for id = 1, 3 do
	local folder = Instance.new("Folder", map)
	folder.Name = "Stand_" .. id
	local prompt = Instance.new("Part", folder)
	prompt.Name = "Prompt"
	prompt.Position = Vector3.new(-1520, 2.6, -1530 + id * 14)
	local spot = Instance.new("Part", folder)
	spot.Name = "OwnerSpot"
	spot.CFrame = CFrame.new(-1525, 0.9, -1530 + id * 14)
end
-- Alter Stand im DataStore: Preisverlauf und lebender RAP eines entfernten Agenten-Skins
local historyData = SIM.DataStore("MarketHistory_v1").Data
historyData.sales = { A_Ghost_Nebel = { { Time = os.time(), Price = 7000 } }, W_Carbon = { { Time = os.time(), Price = 60 } } }
historyData.rap = { A_Ghost_Nebel = 8000, W_Carbon = 50 }
local MarketService = require("MarketService")
local MarketMode = require("Market")
local joined = {}
MarketMode.Init({ Join = function(player, modeId)
	joined[player] = modeId
end })

local function stand(id)
	return map["Stand_" .. id]
end
local function listings(id)
	return HttpService:JSONDecode(stand(id):GetAttribute("Listings") or "[]")
end
local function enter(player, position)
	player:SetAttribute("Mode", "Market")
	local rig = player.Character or SIM.MakeRig(player.Name)
	rig.Parent = workspace
	player.Character = rig
	rig:PivotTo(CFrame.new(position))
end
local function act(player, ...)
	return MarketService.Do(player, ...)
end
local function lastRemote(player, remote)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == remote and entry.Player == player then
			return entry.Args
		end
	end
	return nil
end


store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = { W_Lava = 3, W_Kirsche = 3 }, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 0, Rap = 5000, Owned = {}, Equipped = {}, MarketWatch = { A_Ghost_Nebel = true } }
store.Data.u3 = { XP = {}, Coins = 0, Rap = 5000, Owned = {}, Equipped = {} }
local alice, bob, carl = SIM.Join("Alice"), SIM.Join("Bob"), SIM.Join("Carl")
step(2)
check(next(ProgressService.Get(bob).MarketWatch) == nil, "entfernter Agenten-Skin nicht mehr auf der Merkliste")
check(HttpService:JSONDecode(map:GetAttribute("PriceStats")).A_Ghost_Nebel == nil and RapConfig.Live.A_Ghost_Nebel == nil,
	"entfernter Agenten-Skin weder im Preisverlauf noch im lebenden RAP")
check(HttpService:JSONDecode(map:GetAttribute("PriceStats")).W_Carbon ~= nil and RapConfig.Live.W_Carbon == 50,
	"alte Einträge (vor der Aufteilung) werden noch gelesen")
local function remoteCount(player, remote)
	local n = 0
	for _, entry in SIM.RemoteLog do
		if entry.Remote == remote and entry.Player == player then
			n += 1
		end
	end
	return n
end

-- Gebühr nach Preis
check(RapConfig.FeeRate(5) == 0.02 and RapConfig.FeeRate(50) == 0.02, "kleine Verkäufe (bis 50 RAP): 2 %")
check(RapConfig.FeeRate(51) == 0.05 and RapConfig.FeeRate(1000) == 0.05, "mittlere Verkäufe (bis 1.000 RAP): 5 %")
check(RapConfig.FeeRate(1001) == 0.07 and RapConfig.FeeRate(20000) == 0.07 and RapConfig.FeeRate(20001) == 0.10, "teure Verkäufe: 7 % und 10 %")
check(RapConfig.AfterFee(50) == 49 and RapConfig.AfterFee(20001) == 20001 - 2000 and RapConfig.AfterFee(2) == 2 and RapConfig.Fee(30) == 1, "Gebühr gerundet: winzige Preise zahlen nichts")

enter(alice, Vector3.new(-1514, 3, -1516))
enter(bob, Vector3.new(-1512, 3, -1516))
enter(carl, Vector3.new(-1512, 3, -1502))
check(select(2, act(alice, "Claim", 1)) == true, "Alice nimmt Stand 1")

-- Stand-Name
check(select(2, act(bob, "Name", "Hallo")) == false, "ohne Stand kein Name")
local message, ok = act(alice, "Name", "  Alices   Waffen\n  ")
check(ok == true and stand(1):GetAttribute("StandName") == "Alices Waffen", "Name bereinigt und gesetzt: " .. tostring(stand(1):GetAttribute("StandName")))
act(alice, "Name", string.rep("x", 60))
check(utf8.len(stand(1):GetAttribute("StandName")) == RapConfig.StandNameLength, "Name auf " .. RapConfig.StandNameLength .. " Zeichen gekürzt")
check(select(2, act(alice, "Name", 42)) == false, "Name muss ein Text sein")
act(alice, "Name", "")
check(stand(1):GetAttribute("StandName") == "", "Name zurückgesetzt")
act(alice, "Name", "Lava-Laden")

-- Merkliste: Bob merkt Lava, Carl nicht
check(select(2, act(bob, "Watch", "W_Rekrut")) == false, "gebundener Skin nicht merkbar")
check(select(2, act(bob, "Watch", "W_Lava")) == true, "Lava gemerkt")
check(select(2, act(bob, "Watch", "W_Lava")) == false, "doppelt merken geht nicht")
check(bob:GetAttribute("MarketWatch") == '["W_Lava"]', "Merkliste als Attribut: " .. tostring(bob:GetAttribute("MarketWatch")))
check(ProgressService.Get(bob).MarketWatch.W_Lava == true, "Merkliste im Profil (wird mitgespeichert)")
local before = remoteCount(bob, "Notify")
check(select(2, act(alice, "List", "W_Lava", 1000)) == true, "Alice bietet Lava an")
check(remoteCount(bob, "Notify") == before + 1, "Bob bekommt die Merklisten-Meldung")
check(remoteCount(carl, "Notify") == 0, "Carl nicht")
local notice = lastRemote(bob, "Notify")
check(notice and notice[2].Title == "NEUES ANGEBOT", "Meldung heißt NEUES ANGEBOT")
check(select(2, act(bob, "Unwatch", "W_Lava")) == true and bob:GetAttribute("MarketWatch") == "[]", "von der Merkliste genommen")
check(select(2, act(bob, "Unwatch", "W_Lava")) == false, "nicht gemerkt: nichts zu entfernen")
act(bob, "Watch", "W_Lava")
for i = 1, RapConfig.WatchLimit + 2 do
	ProgressService.Get(bob).MarketWatch["X" .. i] = true
end
check(select(2, act(bob, "Watch", "W_Gletscher")) == false, "Merkliste voll")
for i = 1, RapConfig.WatchLimit + 2 do
	ProgressService.Get(bob).MarketWatch["X" .. i] = nil
end
act(bob, "Unwatch", "W_Lava")

-- Angebote laufen nicht ab
act(alice, "List", "W_Kirsche", 300)
step(86400)
check(#listings(1) == 2 and EconomyService.ReservedCount(alice, "W_Kirsche", "Stand") == 1, "Angebote bleiben auch nach einem Tag")
check(listings(1)[1].Expires == nil, "kein Ablaufdatum am Angebot")
act(alice, "Unlist", 2)

-- Gegenangebote
act(alice, "Unlist", 1)
act(alice, "List", "W_Lava", 1000)
local slot = listings(1)[1].Slot
enter(bob, Vector3.new(-1470, 3, -1516))
check(select(2, act(bob, "Offer", 1, slot, 800)) == false, "zu weit weg für ein Angebot")
enter(bob, Vector3.new(-1512, 3, -1516))
message, ok = act(bob, "Offer", 1, slot, 400)
check(ok == false and string.find(message, "500", 1, true) ~= nil, "unter der Hälfte nicht erlaubt: " .. tostring(message))
check(select(2, act(bob, "Offer", 1, slot, 1000)) == false, "nicht unter dem Preis: kaufen")
check(select(2, act(alice, "Offer", 1, slot, 800)) == false, "eigener Stand")
check(select(2, act(bob, "Offer", 1, slot + 3, 800)) == false, "Angebot gibt es nicht")
ProgressService.Get(carl).Rap = 100
check(select(2, act(carl, "Offer", 1, slot, 800)) == false, "Carl hat nicht genug RAP")
ProgressService.Get(carl).Rap = 5000
message, ok = act(bob, "Offer", 1, slot, 800)
check(ok == true, "Bob bietet 800: " .. tostring(message))
check(select(2, act(bob, "Offer", 1, slot, 850)) == false, "nur ein offenes Angebot pro Stand")
local offers = HttpService:JSONDecode(stand(1):GetAttribute("Offers"))
check(#offers == 1 and offers[1].Price == 800 and offers[1].BuyerName == "Bob" and offers[1].Slot == slot, "Angebot am Stand sichtbar")
notice = lastRemote(alice, "Notify")
check(notice and notice[2].Title == "GEGENANGEBOT", "Besitzer bekommt die Meldung")
-- nur der Besitzer antwortet
check(select(2, act(bob, "Answer", offers[1].Id, true)) == false, "Käufer kann nicht selbst annehmen")
check(select(2, act(carl, "Answer", offers[1].Id, true)) == false, "Fremder kann nicht annehmen")
-- ablehnen
message, ok = act(alice, "Answer", offers[1].Id, false)
check(ok == true and #HttpService:JSONDecode(stand(1):GetAttribute("Offers")) == 0, "abgelehnt: Angebot weg")
status = lastRemote(bob, "MarketStatus")
check(status and string.find(status[1], "abgelehnt", 1, true) ~= nil, "Käufer erfährt es")
-- zurückziehen
act(bob, "Offer", 1, slot, 700)
offers = HttpService:JSONDecode(stand(1):GetAttribute("Offers"))
check(select(2, act(carl, "CancelOffer", offers[1].Id)) == false, "fremdes Angebot nicht zurückziehbar")
check(select(2, act(bob, "CancelOffer", offers[1].Id)) == true and #HttpService:JSONDecode(stand(1):GetAttribute("Offers")) == 0, "zurückgezogen")
-- Ablauf
act(bob, "Offer", 1, slot, 700)
step(RapConfig.OfferSeconds + 3)
check(#HttpService:JSONDecode(stand(1):GetAttribute("Offers")) == 0, "Angebot nach " .. RapConfig.OfferSeconds .. " s weg")
status = lastRemote(bob, "MarketStatus")
check(status and string.find(status[1], "abgelaufen", 1, true) ~= nil, "Käufer erfährt den Ablauf")
check(#listings(1) == 1, "das eigentliche Angebot lebt")
-- Preisänderung macht niedrige Gebote hinfällig, hohe nicht
act(bob, "Offer", 1, slot, 900)
act(carl, "Offer", 1, slot, 600)
check(#HttpService:JSONDecode(stand(1):GetAttribute("Offers")) == 2, "zwei Angebote von zwei Käufern")
act(alice, "SetPrice", slot, 700)
offers = HttpService:JSONDecode(stand(1):GetAttribute("Offers"))
check(#offers == 1 and offers[1].BuyerName == "Carl", "Gebote ab dem neuen Preis fallen weg, niedrigere bleiben")
act(alice, "SetPrice", slot, 1000)
-- annehmen
enter(carl, Vector3.new(-1512, 3, -1502))
message, ok = act(bob, "Offer", 1, slot, 900)
offers = HttpService:JSONDecode(stand(1):GetAttribute("Offers"))
local bobOffer, carlOffer
for _, offer in offers do
	if offer.BuyerName == "Bob" then bobOffer = offer else carlOffer = offer end
end
local aliceRap, bobRap = ProgressService.GetRap(alice), ProgressService.GetRap(bob)
message, ok = act(alice, "Answer", bobOffer.Id, true)
check(ok == true, "Alice nimmt 900 an: " .. tostring(message))
check(ProgressService.GetRap(bob) == bobRap - 900, "Bob zahlt 900")
check(ProgressService.GetRap(alice) == aliceRap + RapConfig.AfterFee(900), "Alice bekommt 900 minus Gebühr (5 %)")
check(ProgressService.ItemCount(bob, "W_Lava") == 1 and ProgressService.ItemCount(alice, "W_Lava") == 2, "Lava gewandert")
check(#listings(1) == 0, "Angebot verkauft")
check(#HttpService:JSONDecode(stand(1):GetAttribute("Offers")) == 0, "andere Gebote auf denselben Skin weg")
status = lastRemote(carl, "MarketStatus")
check(status and string.find(status[1], "verkauft", 1, true) ~= nil, "Carl erfährt, dass der Skin weg ist")
check(select(2, act(alice, "Answer", bobOffer.Id, true)) == false, "erledigtes Angebot nicht nochmal")
-- Käufer hat nicht mehr genug RAP
act(alice, "List", "W_Lava", 1000)
slot = listings(1)[1].Slot
act(bob, "Offer", 1, slot, 900)
offers = HttpService:JSONDecode(stand(1):GetAttribute("Offers"))
ProgressService.Get(bob).Rap = 10
message, ok = act(alice, "Answer", offers[1].Id, true)
check(ok == false and #listings(1) == 1, "Käufer pleite: kein Verkauf, Angebot bleibt (" .. tostring(message) .. ")")
status = lastRemote(bob, "MarketStatus")
check(status and status[2] == false, "Käufer bekommt die Absage")
ProgressService.Get(bob).Rap = 5000
-- Käufer verlässt den Markt: sein Gebot ist weg
act(bob, "Offer", 1, slot, 800)
bob:SetAttribute("Mode", "Hub")
MarketMode.RemovePlayer(bob)
check(#HttpService:JSONDecode(stand(1):GetAttribute("Offers")) == 0, "Gebot weg, wenn der Käufer den Markt verlässt")
enter(bob, Vector3.new(-1512, 3, -1516))
-- Besitzer gibt den Stand ab: Gebote weg
act(bob, "Offer", 1, slot, 800)
act(alice, "Release")
check(#HttpService:JSONDecode(stand(1):GetAttribute("Offers")) == 0 and stand(1):GetAttribute("StandName") == "", "Stand frei: Gebote und Name weg")
act(alice, "Claim", 1)
check(stand(1):GetAttribute("StandName") == "", "neuer Besitzer: kein alter Name")

-- Preisverlauf und Händler-Rangliste
local stats = HttpService:JSONDecode(map:GetAttribute("PriceStats"))
check(stats.W_Lava and stats.W_Lava.N == 1 and stats.W_Lava.Avg == 900 and stats.W_Lava.Last == 900, "Preisverlauf Lava: ein Verkauf zu 900")
act(alice, "List", "W_Lava", 1100)
slot = listings(1)[1].Slot
message, ok = act(bob, "Buy", 1, slot, 1100)
check(ok == true, "Kauf zu 1.100: " .. tostring(message))
stats = HttpService:JSONDecode(map:GetAttribute("PriceStats"))
check(stats.W_Lava.N == 2 and stats.W_Lava.Avg == 1000 and stats.W_Lava.Last == 1100, "Durchschnitt der beiden Verkäufe: 1.000")
step(1)
-- Lebender RAP: Lava startet bei 3.200 und rückt nach jedem Verkauf ein Zehntel Richtung Preis (900, dann 1.100)
local expectedLive = RapConfig.Values.W_Lava
for _, soldFor in { 900, 1100 } do
	expectedLive += (soldFor - expectedLive) / 10
end
check(math.abs(RapConfig.Live.W_Lava - expectedLive) < 1e-6, "lebender RAP nach zwei Verkäufen: " .. tostring(RapConfig.Live.W_Lava) .. " statt " .. tostring(expectedLive))
check(RapConfig.Value("W_Lava") == math.floor(expectedLive + 0.5), "RapConfig.Value liefert den lebenden Wert")
local liveAttr = HttpService:JSONDecode(game:GetService("ReplicatedStorage"):GetAttribute("RapLive"))
check(math.abs(liveAttr.W_Lava - expectedLive) < 1e-6, "an die Clients repliziert (Attribut RapLive)")
check(RapConfig.SellPrice("W_Lava") == math.floor(RapConfig.Values.W_Lava * RapConfig.SellRate), "Rückkauf ans System bleibt am Basiswert")
local historyStore = SIM.DataStore("MarketHistory_v1")
local lavaKey = "shard_" .. MarketService.ShardOf("W_Lava")
check(historyData[lavaKey] == nil, "Verkäufe werden gesammelt, nicht sofort geschrieben")
local calls = historyStore.Calls
MarketService.FlushHistory()
check(historyStore.Calls - calls == 1, "beide Verkäufe mit einem Schreibzugriff gespeichert: " .. historyStore.Calls - calls)
local savedLive = historyData[lavaKey] and historyData[lavaKey].Rap
check(savedLive and math.abs(savedLive.W_Lava - expectedLive) < 1e-6, "lebender RAP im DataStore gespeichert")
check(historyData[lavaKey] and #historyData[lavaKey].Sales.W_Lava == 2, "beide Verkäufe im Eintrag des Skins")
check(historyData.rap.W_Lava == nil and historyData.sales.W_Lava == nil, "alte Einträge werden nicht mehr beschrieben")
stats = HttpService:JSONDecode(map:GetAttribute("PriceStats"))
check(stats.W_Lava.N == 2 and math.abs(RapConfig.Live.W_Lava - expectedLive) < 1e-6, "nach dem Speichern nichts doppelt")
calls = historyStore.Calls
MarketService.FlushHistory()
check(historyStore.Calls == calls, "nichts Neues: kein Schreibzugriff")
local sellersTop = HttpService:JSONDecode(map:GetAttribute("TopSellers"))
check(#sellersTop == 1 and sellersTop[1].Name == "Alice" and sellersTop[1].Sales == 2 and sellersTop[1].Volume == 2000, "Händler-Rangliste: Alice 2 Verkäufe, 2.000 RAP")
-- ein zweiter Händler überholt
act(bob, "Release")
enter(carl, Vector3.new(-1512, 3, -1502))
act(carl, "Claim", 2)
ProgressService.Get(carl).Owned = { W_Kirsche = 5 }
ProgressService.Sync(carl)
for i = 1, 3 do
	act(carl, "List", "W_Kirsche", 200)
end
enter(bob, Vector3.new(-1512, 3, -1502))
for _, entry in listings(2) do
	act(bob, "Buy", 2, entry.Slot, 200)
end
sellersTop = HttpService:JSONDecode(map:GetAttribute("TopSellers"))
check(#sellersTop == 2 and sellersTop[1].Name == "Carl" and sellersTop[1].Sales == 3, "Carl führt mit 3 Verkäufen")
check(sellersTop[2].Name == "Alice", "Alice auf Platz 2")
-- Viele Server: ein anderer Server hat inzwischen Lava verkauft und gespeichert; beim Neuladen kommt der Verkauf dazu
local otherLive = historyData[lavaKey].Rap.W_Lava + (5000 - historyData[lavaKey].Rap.W_Lava) * RapConfig.LiveWeight
table.insert(historyData[lavaKey].Sales.W_Lava, { Time = os.time(), Price = 5000 })
historyData[lavaKey].Rap.W_Lava = otherLive
MarketService.RefreshHistory()
stats = HttpService:JSONDecode(map:GetAttribute("PriceStats"))
check(stats.W_Lava.N == 3 and stats.W_Lava.Last == 5000, "Verkauf des anderen Servers im Preisverlauf")
check(math.abs(RapConfig.Live.W_Lava - otherLive) < 1e-6, "lebender RAP des anderen Servers übernommen")
-- Mehrere Skins in einem Durchgang: höchstens ein Schreibzugriff je Eintrag; schlägt einer fehl, bleibt alles offen
calls = historyStore.Calls
local kirscheKey = "shard_" .. MarketService.ShardOf("W_Kirsche")
local function savedKirsche()
	local data = historyData[kirscheKey]
	return data and data.Sales.W_Kirsche and #data.Sales.W_Kirsche or 0
end
local kirscheBefore = savedKirsche()
historyStore.FailNext = 1
MarketService.FlushHistory()
check(savedKirsche() == kirscheBefore, "Fehler beim Speichern: nichts verloren, noch offen")
MarketService.FlushHistory()
check(savedKirsche() == kirscheBefore + 3, "nächster Versuch speichert die drei Kirsche-Verkäufe")
stats = HttpService:JSONDecode(map:GetAttribute("PriceStats"))
check(stats.W_Kirsche.N == 3, "Kirsche nach dem Speichern nicht doppelt: " .. tostring(stats.W_Kirsche.N))
-- Herunterfahren speichert offene Verkäufe sofort
act(carl, "List", "W_Kirsche", 210)
local closeSlot = listings(2)[1] and listings(2)[1].Slot
act(bob, "Buy", 2, closeSlot, 210)
for _, closer in SIM.Closers do
	task.spawn(closer)
end
step(1)
check(savedKirsche() == kirscheBefore + 4, "Herunterfahren speichert den letzten Verkauf")
-- ohne Anstoß: der Server speichert von selbst spätestens nach HistoryFlush Sekunden
ProgressService.Get(carl).Owned.W_Kirsche = (ProgressService.Get(carl).Owned.W_Kirsche or 0) + 2
ProgressService.Sync(carl)
act(carl, "List", "W_Kirsche", 205)
act(bob, "Buy", 2, listings(2)[1] and listings(2)[1].Slot, 205)
step(RapConfig.HistoryFlush + 1)
check(savedKirsche() == kirscheBefore + 5, "regelmäßiges Speichern")
-- Verkauf im alten Verlauf: ältere als HistoryDays zählen nicht mit
SIM.Run(SIM.Now + RapConfig.HistoryDays * 86400 + 60)
MarketService.Do(alice, "Release")
-- (Die Statistik wird beim nächsten Verkauf neu berechnet – alte Einträge fallen heraus.)
act(carl, "List", "W_Kirsche", 220)
enter(bob, Vector3.new(-1512, 3, -1502))
local newSlot = listings(2)[1] and listings(2)[1].Slot
if newSlot then
	act(bob, "Buy", 2, newSlot, 220)
end
stats = HttpService:JSONDecode(map:GetAttribute("PriceStats"))
check(stats.W_Lava == nil, "Verkäufe älter als " .. RapConfig.HistoryDays .. " Tage zählen nicht mehr")
check(stats.W_Kirsche and stats.W_Kirsche.N == 1 and stats.W_Kirsche.Avg == 220, "nur der neue Kirsche-Verkauf zählt")
-- entfernter Skin, den ein alter Server noch in einen Eintrag geschrieben hat: fällt beim Speichern heraus
historyData[kirscheKey].Sales.A_Ghost_Nebel = { { Time = os.time(), Price = 7000 } }
historyData[kirscheKey].Rap.A_Ghost_Nebel = 8000
MarketService.FlushHistory()
check(historyData[kirscheKey].Sales.A_Ghost_Nebel == nil and historyData[kirscheKey].Rap.A_Ghost_Nebel == nil
	and historyData[kirscheKey].Sales.W_Kirsche ~= nil, "beim Speichern fällt der entfernte Skin aus dem DataStore")

if failures == 0 then
	print("Markt Teil 2: alles in Ordnung")
end

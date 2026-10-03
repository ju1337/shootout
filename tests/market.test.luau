-- Markt: Stand beanspruchen (nur im Markt, nur in der Nähe, einer pro Spieler), Skins anbieten (nur handelbare,
-- nur freie Stücke, höchstens sechs), Preis ändern, kaufen (Nähe, gesehener Preis, genug RAP, Gebühr), zurücknehmen,
-- Stand weg beim Verlassen des Markts oder des Spiels – die Skins sind dann wieder frei
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

-- Spieler: Alice verkauft, Bob kauft, Carl schaut zu
store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = { W_Lava = 2, W_Wald = true, W_Kirsche = 6 }, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 0, Rap = 2000, Owned = {}, Equipped = {} }
store.Data.u3 = { XP = {}, Coins = 0, Rap = 50, Owned = {}, Equipped = {} }
local alice, bob, carl = SIM.Join("Alice"), SIM.Join("Bob"), SIM.Join("Carl")
step(2)
check(ProgressService.IsLoaded(alice) and ProgressService.IsLoaded(bob), "Profile geladen")
check(stand(1):GetAttribute("Owner") == 0 and stand(2):GetAttribute("Owner") == 0, "Stände anfangs frei")

-- Beanspruchen
alice:SetAttribute("Mode", "Hub")
local message, ok = act(alice, "Claim", 1)
check(ok == false, "außerhalb des Markts kein Stand")
enter(alice, Vector3.new(-1480, 3, -1516))
message, ok = act(alice, "Claim", 1)
check(ok == false and string.find(message, "näher", 1, true) ~= nil, "zu weit weg: " .. tostring(message))
enter(alice, Vector3.new(-1514, 3, -1516))
message, ok = act(alice, "Claim", 1)
check(ok == true, "Stand 1 beansprucht: " .. tostring(message))
check(stand(1):GetAttribute("Owner") == alice.UserId and stand(1):GetAttribute("OwnerName") == "Alice", "Besitzer am Stand")
check((alice.Character:GetPivot().Position - Vector3.new(-1525, 3.1, -1516)).Magnitude < 0.01, "hinter die Theke gestellt")
check(act(alice, "Claim", 2) == "Du hast schon Stand 1. Gib ihn erst ab.", "nur ein Stand pro Spieler")
enter(bob, Vector3.new(-1514, 3, -1516))
check(select(2, act(bob, "Claim", 1)) == false, "fremder Stand nicht beanspruchbar")

-- Anbieten
check(select(2, act(alice, "List", "W_Lava", 0)) == false, "Preis 0 ungültig")
check(select(2, act(alice, "List", "W_Lava", "viel")) == false, "Preis muss eine Zahl sein")
check(select(2, act(alice, "List", "W_Wald", 100)) == false, "gebundener Skin nicht handelbar")
check(select(2, act(alice, "List", "W_Galaxie", 100)) == false, "nicht besessener Skin")
check(select(2, act(alice, "List", "W_Lava", 900)) == true, "Lava 1 angeboten")
check(select(2, act(alice, "List", "W_Lava", 950)) == true, "Lava 2 angeboten")
check(select(2, act(alice, "List", "W_Lava", 1000)) == false, "kein drittes Stück Lava")
check(#listings(1) == 2 and listings(1)[1].Item == "W_Lava" and listings(1)[1].Price == 900, "Angebote am Stand")
check(HttpService:JSONDecode(alice:GetAttribute("Reserved")).W_Lava == 2, "beide Lava zurückgelegt")
check(select(2, EconomyService.SellToSystem(alice, "W_Lava")) == false, "angebotener Skin nicht ans System verkaufbar")
check(select(2, act(bob, "List", "W_Lava", 100)) == false, "ohne Stand nichts anbieten")
for _ = 1, 4 do
	act(alice, "List", "W_Kirsche", 300)
end
check(#listings(1) == RapConfig.StandSlots, "Stand voll mit " .. RapConfig.StandSlots .. " Angeboten")
message, ok = act(alice, "List", "W_Kirsche", 300)
check(ok == false and string.find(message, "voll", 1, true) ~= nil, "siebtes Angebot geht nicht")

-- Preis ändern, zurücknehmen
check(select(2, act(alice, "SetPrice", 1, 1000)) == true and listings(1)[1].Price == 1000, "Preis geändert")
check(select(2, act(alice, "SetPrice", 1, -5)) == false, "negativer Preis nicht erlaubt")
check(select(2, act(bob, "SetPrice", 1, 1)) == false, "fremde Preise nicht änderbar")
check(select(2, act(alice, "Unlist", 6)) == true, "Kirsche zurückgenommen")
check(EconomyService.ReservedCount(alice, "W_Kirsche") == 3, "Kirsche wieder frei")

-- Kaufen
enter(bob, Vector3.new(-1470, 3, -1516))
message, ok = act(bob, "Buy", 1, 1, 1000)
check(ok == false and string.find(message, "näher", 1, true) ~= nil, "zu weit weg zum Kaufen")
enter(bob, Vector3.new(-1512, 3, -1516))
message, ok = act(bob, "Buy", 1, 1, 900)
check(ok == false and string.find(message, "1.000", 1, true) ~= nil, "alter Preis: nicht gekauft (" .. tostring(message) .. ")")
check(select(2, act(alice, "Buy", 1, 2, 950)) == false, "nicht am eigenen Stand kaufen")
message, ok = act(bob, "Buy", 1, 1, 1000)
check(ok == true, "Bob kauft Lava für 1.000: " .. tostring(message))
check(bob:GetAttribute("Rap") == 1000, "Bob zahlt 1.000")
check(alice:GetAttribute("Rap") == RapConfig.AfterFee(1000), "Alice bekommt 1.000 minus Gebühr")
check(ProgressService.ItemCount(bob, "W_Lava") == 1 and ProgressService.ItemCount(alice, "W_Lava") == 1, "Lava gewandert")
check(#listings(1) == 4 and listings(1)[1].Slot == 2, "verkauftes Angebot weg")
check(EconomyService.ReservedCount(alice, "W_Lava") == 1, "zweite Lava weiter zurückgelegt")
local notice = lastRemote(alice, "Notify")
check(notice and notice[1] == "Progress" and notice[2].Title == "VERKAUFT", "Verkäufer bekommt eine Meldung")
check(lastRemote(bob, "Reward") ~= nil, "Käufer bekommt eine Karte")
check(select(2, act(bob, "Buy", 1, 1, 1000)) == false, "dasselbe Angebot nicht zweimal")
enter(carl, Vector3.new(-1512, 3, -1517))
message, ok = act(carl, "Buy", 1, 2, 950)
check(ok == false and string.find(message, "RAP", 1, true) ~= nil, "Carl hat zu wenig RAP")
step(2)
check(store.Data.u1.Owned.W_Lava == 1 and store.Data.u2.Owned.W_Lava == 1 and store.Data.u2.Rap == 1000,
	"Kauf sofort gespeichert")

-- Über das Remote (mit Rückmeldung)
Remotes.MarketAction.OnServerEvent:Fire(bob, "Buy", 1, 2, 950)
step(0.3)
local status = lastRemote(bob, "MarketStatus")
check(status and status[2] == true and ProgressService.ItemCount(bob, "W_Lava") == 2, "Kauf über das Remote")

-- Markt verlassen: Stand frei, Skins wieder frei, aber noch im Besitz
check(EconomyService.ReservedCount(alice, "W_Kirsche") == 3, "drei Kirschen am Stand")
alice:SetAttribute("Mode", "Domination")
MarketMode.RemovePlayer(alice)
check(stand(1):GetAttribute("Owner") == 0 and #listings(1) == 0, "Stand nach dem Verlassen frei und leer")
check(EconomyService.ReservedCount(alice, "W_Kirsche") == 0 and ProgressService.ItemCount(alice, "W_Kirsche") == 6,
	"Kirschen zurück im Inventar")
status = lastRemote(alice, "MarketStatus")
check(status and string.find(status[1], "verlassen", 1, true) ~= nil, "Meldung beim Verlassen")
-- Jetzt kann Bob den Stand nehmen
enter(bob, Vector3.new(-1514, 3, -1516))
check(select(2, act(bob, "Claim", 1)) == true, "Bob übernimmt den freien Stand")
check(select(2, act(bob, "List", "W_Lava", 2000)) == true, "Bob bietet an")
-- Spiel verlassen: Stand frei
SIM.Leave(bob)
step(1)
check(stand(1):GetAttribute("Owner") == 0 and #listings(1) == 0, "Stand frei, wenn der Besitzer das Spiel verlässt")
-- Stand abgeben per Aktion
enter(carl, Vector3.new(-1514, 3, -1502))
check(select(2, act(carl, "Claim", 2)) == true and select(2, act(carl, "Release")) == true, "Stand abgeben")
check(stand(2):GetAttribute("Owner") == 0, "abgegebener Stand frei")
check(select(2, act(carl, "Release")) == false, "ohne Stand nichts abzugeben")

if failures == 0 then
	print("Markt: alles in Ordnung")
end

-- Rangliste der roten Zone (RedzoneBoard): Spieler-Kills zählen in der Zone, wenn das Opfer drin stirbt, sonst wenn der
-- Schütze drin steht, draußen gar nicht; sortiert nach Kills (Gleichstand: wer die Zahl früher erreicht hat); jede Runde
-- (alle 20 Minuten zieht die Zone weiter) beginnt bei null mit dem neuen Ort; wer die offene Welt verlässt, fällt raus;
-- Attribut RedzoneBoard an der Karte
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
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
ProgressService.Init()
WeaponService.Init()

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Places" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
-- Orte für die rote Zone: Test (Süden) und Nordheim
for key, info in { Test = { "Testzone", Vector3.new(0, 2, -500) }, Nord = { "Nordheim", Vector3.new(0, 2, 900) } } do
	local part = Instance.new("Part", map.Places)
	part.Name = "Place_" .. key
	part:SetAttribute("Title", info[1])
	part.Size = Vector3.new(200, 4, 200)
	part.CFrame = CFrame.new(CENTER + info[2])
end

local ground = Instance.new("Part", workspace)
ground.Name = "Ground"
SIM.RaycastHandler = function(origin, direction)
	if direction.Y >= 0 then
		return nil
	end
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground, Material = Enum.Material.Grass }
end

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local RedzoneService = require("RedzoneService")
local RedzoneBoard = require("RedzoneBoard")
local HttpService = game:GetService("HttpService")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge -- hier keine Lootdrops
ExtinctionConfig.Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
ExtinctionConfig.HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0 -- keine Zombies: niemand soll hier nebenbei sterben
Extinction.Init({ Join = function() end, Status = function() end })

local players = {}
for i, name in { "Alice", "Bob", "Carl", "Dana" } do
	store.Data["u" .. i] = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
	local player = SIM.Join(name)
	Instance.new("Backpack", player).Name = "Backpack"
	players[name] = player
end
local alice, bob, carl, dana = players.Alice, players.Bob, players.Carl, players.Dana
step(2)
for _, player in { alice, bob, carl, dana } do
	player:SetAttribute("Mode", "Extinction")
	Extinction.AddPlayer(player)
end
step(2)
local function place(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
end
local INSIDE, OUTSIDE = Vector3.new(0, 3, -480), Vector3.new(0, 3, -250)
local function names(list)
	local result = {}
	for _, entry in list do
		table.insert(result, entry.Name .. "=" .. entry.Kills)
	end
	return table.concat(result, ",")
end
local function published()
	local ok, data = pcall(HttpService.JSONDecode, HttpService, map:GetAttribute("RedzoneBoard") or "null")
	return ok and type(data) == "table" and data or {}
end

-- Am Anfang: die Zone mit ihrem Ort und leerer Liste
RedzoneService.MoveNow("Test")
local data = published()
check(type(data.Zones) == "table" and type(data.Zones.Redzone) == "table" and data.Zones.Redzone.Title == "Testzone"
	and #data.Zones.Redzone.List == 0 and data.Total == nil, "leere Rangliste der Zone an der Karte, keine Gesamtliste")
local count = 0
for _ in data.Zones do
	count += 1
end
check(count == 1, "genau eine Liste (eine rote Zone)")

-- Opfer in der Zone (beim Zählen schon tot), Schütze draußen: zählt für die Zone (und Münzen gibt es wie immer)
place(alice, OUTSIDE)
place(bob, INSIDE)
bob.Character:FindFirstChildOfClass("Humanoid").Health = 0
local coins = ProgressService.Get(alice).Coins
Extinction.OnKill(alice, bob)
check(ProgressService.Get(alice).Coins == coins + ExtinctionConfig.PlayerKillCoins, "Kopfgeld wie bisher")
check(names(RedzoneBoard.List("Redzone")) == "Alice=1", "Opfer in der Zone: Kill zählt (" .. names(RedzoneBoard.List("Redzone")) .. ")")
-- Opfer draußen, Schütze in der Zone: zählt auch
place(carl, INSIDE)
place(dana, OUTSIDE)
Extinction.OnKill(carl, dana)
-- beide draußen: zählt nicht; Selbstmord und Kills ohne Spieler-Opfer auch nicht
place(carl, OUTSIDE)
Extinction.OnKill(carl, dana)
Extinction.OnKill(carl, carl)
Extinction.OnKill(carl, nil)
check(names(RedzoneBoard.List("Redzone")) == "Alice=1,Carl=1", "nur Kills mit Zone zählen, Gleichstand: früherer zuerst ("
	.. names(RedzoneBoard.List("Redzone")) .. ")")
-- Carl zieht vorbei, Alice holt auf: bei Gleichstand steht vorn, wer die Zahl zuerst hatte
place(carl, INSIDE)
Extinction.OnKill(carl, bob)
Extinction.OnKill(alice, bob)
check(names(RedzoneBoard.List("Redzone")) == "Carl=2,Alice=2", "Gleichstand: Carl hatte 2 Kills zuerst ("
	.. names(RedzoneBoard.List("Redzone")) .. ")")
data = published()
check(#data.Zones.Redzone.List == 2 and data.Zones.Redzone.List[1].Name == "Carl" and data.Zones.Redzone.List[1].Kills == 2
	and data.Zones.Redzone.List[1].Id == carl.UserId, "Liste mit Id, Name und Kills an der Karte")

-- Wer die offene Welt verlässt, fällt raus
Extinction.RemovePlayer(carl)
check(names(RedzoneBoard.List("Redzone")) == "Alice=2", "Carl ist raus (" .. names(RedzoneBoard.List("Redzone")) .. ")")
data = published()
check(#data.Zones.Redzone.List == 1 and data.Zones.Redzone.List[1].Name == "Alice", "auch an der Karte")

-- Nach Ablauf der Runde zieht die Zone weiter: neue Runde, leere Liste mit dem neuen Ort; am alten Ort zählt nichts mehr
local cfg = ExtinctionConfig.Redzone
step(cfg.Interval - 5)
check(names(RedzoneBoard.List("Redzone")) == "Alice=2", "kurz vor dem Wechsel steht die Liste noch")
step(10)
check(RedzoneService.Current().Key == "Nord", "nach 20 Minuten steht die Zone woanders")
check(#RedzoneBoard.List("Redzone") == 0, "nach dem Wechsel beginnt die Rangliste neu")
data = published()
check(type(data.Zones.Redzone) == "table" and data.Zones.Redzone.Title == "Nordheim" and #data.Zones.Redzone.List == 0,
	"an der Karte: neue Runde mit dem neuen Ort")
place(alice, INSIDE)
place(bob, INSIDE)
Extinction.OnKill(alice, bob)
check(#RedzoneBoard.List("Redzone") == 0, "am alten Ort zählt nichts mehr")
place(dana, Vector3.new(0, 3, 900))
place(bob, Vector3.new(20, 3, 910))
Extinction.OnKill(dana, bob)
Extinction.OnKill(dana, bob)
check(names(RedzoneBoard.List("Redzone")) == "Dana=2", "neue Runde zählt von vorn (" .. names(RedzoneBoard.List("Redzone")) .. ")")
-- auch ein von Hand erzwungener Wechsel (Admin) beginnt eine neue Runde
RedzoneService.MoveNow("Test")
check(#RedzoneBoard.List("Redzone") == 0 and published().Zones.Redzone.Title == "Testzone", "jeder Wechsel: neue Runde")

-- Ohne rote Zone: keine Liste
RedzoneService.Stop()
data = published()
check(data.Zones.Redzone == nil, "ohne Zone keine Liste")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

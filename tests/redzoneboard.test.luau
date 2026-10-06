-- Rangliste der roten Zonen (RedzoneBoard): Spieler-Kills zählen in der Zone des Opfers, sonst in der des Schützen,
-- draußen gar nicht; sortiert nach Kills (Gleichstand: wer die Zahl früher erreicht hat); die Wanderzone beginnt nach
-- jedem Wechsel neu, die Gesamtliste nicht; wer die offene Welt verlässt, fällt raus; Attribut RedzoneBoard an der Karte
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
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Redzones", "Places" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
local redzone = Instance.new("Part", map.Redzones)
redzone.Name = "Redzone_Test"
redzone:SetAttribute("Title", "Testzone")
redzone.Size = Vector3.new(240, 40, 240)
redzone.CFrame = CFrame.new(CENTER + Vector3.new(0, 20, -500))
local north = Instance.new("Part", map.Places) -- Ziel der Wanderzone
north.Name = "Place_Nord"
north:SetAttribute("Title", "Nordheim")
north.Size = Vector3.new(200, 4, 200)
north.CFrame = CFrame.new(CENTER + Vector3.new(0, 2, 900))

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

-- Am Anfang: feste Zone mit Titel und leerer Liste
local data = published()
check(type(data.Zones) == "table" and type(data.Zones.Test) == "table" and data.Zones.Test.Title == "Testzone"
	and #data.Zones.Test.List == 0 and type(data.Total) == "table" and #data.Total == 0, "leere Rangliste an der Karte")
local moving = RedzoneService.MoveNow("Nord")
check(moving ~= nil and moving.Key == "Nord", "Wanderzone steht in Nordheim")
data = published()
check(type(data.Zones.Wanderzone) == "table" and data.Zones.Wanderzone.Title == "Nordheim", "Wanderzone mit Ortsnamen in der Liste")

-- Opfer in der Zone (beim Zählen schon tot), Schütze draußen: zählt für die Zone (und Münzen gibt es wie immer)
place(alice, OUTSIDE)
place(bob, INSIDE)
bob.Character:FindFirstChildOfClass("Humanoid").Health = 0
local coins = ProgressService.Get(alice).Coins
Extinction.OnKill(alice, bob)
check(ProgressService.Get(alice).Coins == coins + ExtinctionConfig.PlayerKillCoins, "Kopfgeld wie bisher")
check(names(RedzoneBoard.List("Test")) == "Alice=1", "Opfer in der Zone: Kill zählt (" .. names(RedzoneBoard.List("Test")) .. ")")
-- Opfer draußen, Schütze in der Zone: zählt auch
place(carl, INSIDE)
place(dana, OUTSIDE)
Extinction.OnKill(carl, dana)
-- beide draußen: zählt nicht; Selbstmord und Kills ohne Spieler-Opfer auch nicht
place(carl, OUTSIDE)
Extinction.OnKill(carl, dana)
Extinction.OnKill(carl, carl)
Extinction.OnKill(carl, nil)
check(names(RedzoneBoard.List("Test")) == "Alice=1,Carl=1", "nur Kills mit Zone zählen, Gleichstand: früherer zuerst ("
	.. names(RedzoneBoard.List("Test")) .. ")")
-- Carl zieht vorbei, Alice holt auf: bei Gleichstand steht vorn, wer die Zahl zuerst hatte
place(carl, INSIDE)
Extinction.OnKill(carl, bob)
Extinction.OnKill(alice, bob)
check(names(RedzoneBoard.List("Test")) == "Carl=2,Alice=2", "Gleichstand: Carl hatte 2 Kills zuerst ("
	.. names(RedzoneBoard.List("Test")) .. ")")
data = published()
check(#data.Zones.Test.List == 2 and data.Zones.Test.List[1].Name == "Carl" and data.Zones.Test.List[1].Kills == 2
	and data.Zones.Test.List[1].Id == carl.UserId, "Liste mit Id, Name und Kills an der Karte")

-- Wanderzone: eigene Liste, Gesamtliste zählt alles zusammen
place(dana, Vector3.new(0, 3, 900))
place(bob, Vector3.new(20, 3, 910))
Extinction.OnKill(dana, bob)
check(names(RedzoneBoard.List("Wanderzone")) == "Dana=1", "Kill in der Wanderzone (" .. names(RedzoneBoard.List("Wanderzone")) .. ")")
check(names(RedzoneBoard.List()) == "Carl=2,Alice=2,Dana=1", "Gesamtliste aller Zonen (" .. names(RedzoneBoard.List()) .. ")")
-- Wechsel der Wanderzone: neue, leere Liste; Gesamtliste bleibt
RedzoneService.MoveNow("Nord")
check(#RedzoneBoard.List("Wanderzone") == 0, "nach dem Wechsel beginnt die Wanderzone neu")
data = published()
check(type(data.Zones.Wanderzone) == "table" and #data.Zones.Wanderzone.List == 0 and #data.Total == 3,
	"Wechsel an der Karte: Wanderzone leer, Gesamtliste unverändert")
check(names(RedzoneBoard.List("Test")) == "Carl=2,Alice=2", "feste Zone bleibt beim Wechsel")

-- Wer die offene Welt verlässt, fällt aus allen Listen
Extinction.RemovePlayer(carl)
check(names(RedzoneBoard.List("Test")) == "Alice=2" and names(RedzoneBoard.List()) == "Alice=2,Dana=1", "Carl ist raus ("
	.. names(RedzoneBoard.List()) .. ")")
data = published()
check(#data.Total == 2 and data.Total[1].Name == "Alice", "auch an der Karte")

-- Ohne Wanderzone (keine Ziele mehr): Liste weg
north:Destroy()
RedzoneService.MoveNow()
data = published()
check(data.Zones.Wanderzone == nil and data.Zones.Test ~= nil, "ohne Wanderzone keine Liste dafür")

RedzoneService.StopMoving()
print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

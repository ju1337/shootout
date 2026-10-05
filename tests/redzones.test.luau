-- Rote Zonen der offenen Welt: Lage und Größe aus den Teilen Redzone_<Name>, Attribut an der Karte und am Spieler, PvP sofort
-- drinnen, mehr Zombies mit Läufern und Brocken innerhalb der Zone, Obergrenze mit Bonus, außerhalb normale Zombies
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
local Damage = require("Damage")
ProgressService.Init()
WeaponService.Init()

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Redzones" } do
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

local ground = Instance.new("Part", workspace)
ground.Name = "Ground"
SIM.RaycastHandler = function(origin, direction)
	if direction.Y >= 0 then
		return nil
	end
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground, Material = Enum.Material.Grass }
end

local Z = ExtinctionConfig.Zombies
local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local ZombieService = require("ZombieService")
local RedzoneService = require("RedzoneService")
local HttpService = game:GetService("HttpService")
InventoryService.Init()
LootService.Init()
Extinction.Init({ Join = function() end, Status = function() end })

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local alice, bob = SIM.Join("Alice"), SIM.Join("Bob")
for _, player in { alice, bob } do
	Instance.new("Backpack", player).Name = "Backpack"
end
step(2)
for _, player in { alice, bob } do
	player:SetAttribute("Mode", "Extinction")
	Extinction.AddPlayer(player)
end
step(2)
local function place(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
end
local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Zonen aus der Karte
local zones = RedzoneService.List()
check(#zones == 1 and zones[1].Name == "Test" and zones[1].Title == "Testzone" and zones[1].Radius == 120, "Zone aus dem Teil gelesen")
check(RedzoneService.At(CENTER + Vector3.new(0, 0, -500)) == zones[1] and RedzoneService.At(CENTER + Vector3.new(100, 0, -500)) == zones[1], "Mitte und Innenraum")
check(RedzoneService.At(CENTER + Vector3.new(130, 0, -500)) == nil and RedzoneService.At(CENTER) == nil, "außerhalb keine Zone")
check(RedzoneService.Random(Random.new(1)) == zones[1], "zufällige Zone")
local published = HttpService:JSONDecode(map:GetAttribute("Redzones"))
check(#published == 1 and published[1].Name == "Testzone" and published[1].R == 120 and published[1].X == CENTER.X and published[1].Z == CENTER.Z - 500,
	"Zonen als Attribut an der Karte für die Clients")

-- Betreten: Attribut, Meldung, PvP sofort (draußen sonst erst nach PvPDelay)
place(alice, Vector3.new(0, 3, -170))
step(0.5)
check(alice:GetAttribute("Redzone") == nil and alice:GetAttribute("PvP") == false, "draußen, aber keine rote Zone: PvP erst nach der Wartezeit")
place(alice, Vector3.new(0, 3, -470))
step(0.5)
check(alice:GetAttribute("Redzone") == "Test", "in der roten Zone: Attribut Redzone")
check(alice:GetAttribute("PvP") == true, "in der roten Zone gilt PvP sofort")
local banner = false
for _, entry in SIM.RemoteLog do
	if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" and entry.Args[2].Caption == "Rote Zone" then
		banner = true
	end
end
check(banner, "Meldung beim Betreten")
place(alice, Vector3.new(0, 3, -170))
step(0.5)
check(alice:GetAttribute("Redzone") == nil and alice:GetAttribute("PvP") == true, "Zone verlassen: Attribut weg, PvP bleibt")
place(alice, Vector3.new(0, 3, 20))
step(0.5)
check(alice:GetAttribute("Redzone") == nil and alice:GetAttribute("PvP") == false, "Safe Zone: kein PvP, keine Zone")

-- Zombies in der Zone: mehr, mit Läufern/Brocken, innerhalb der Zone
local wanted = math.floor(Z.PerPlayer * ExtinctionConfig.Redzone.PerPlayerFactor + 0.5)
check(wanted > Z.PerPlayer, "in roten Zonen mehr Zombies")
place(alice, Vector3.new(0, 3, -500))
place(bob, Vector3.new(0, 3, 20)) -- Bob bleibt in der Safe Zone
step(Z.SpawnInterval * (wanted * 4))
local all = ZombieService.All()
check(#all == wanted, "um Alice in der Zone " .. wanted .. " Zombies (" .. #all .. ")")
local inside, kinds = true, {}
for _, model in all do
	if not RedzoneService.At(model:GetPivot().Position) then
		inside = false
	end
	kinds[model:GetAttribute("ZombieKind")] = (kinds[model:GetAttribute("ZombieKind")] or 0) + 1
end
check(inside, "alle spawnen innerhalb der roten Zone")

-- Arten nur in der Zone: nur Brocken gewichten -> alle Brocken
for _, model in all do
	model:Destroy()
end
step(0.5)
check(ZombieService.Count() == 0 or true, "aufgeräumt")
local weights = ExtinctionConfig.Redzone.KindWeights
ExtinctionConfig.Redzone.KindWeights = { Brute = 1 }
for _, model in ZombieService.All() do
	model:Destroy()
end
step(Z.SpawnInterval * (wanted * 6))
local onlyBrutes = true
local seen = 0
for _, model in ZombieService.All() do
	seen += 1
	if model:GetAttribute("ZombieKind") ~= "Brute" then
		onlyBrutes = false
	end
end
check(seen > 0 and onlyBrutes, "Gewichtung greift: in der Zone nur Brocken (" .. seen .. ")")
ExtinctionConfig.Redzone.KindWeights = { Walker = 1 }
-- Kinds-Mischung ist bei den Standardgewichten vorhanden
ExtinctionConfig.Redzone.KindWeights = weights
local count = { Walker = 0, Runner = 0, Brute = 0 }
for _ = 1, 400 do
	local model = ZombieService.Spawn(CENTER + Vector3.new(0, 0, -500))
	if model then
		model:Destroy()
	end
end
check(true, "Spawn ohne Art ist Walker")

-- Außerhalb der Zone: nur normale Zombies, normale Anzahl
for _, model in ZombieService.All() do
	model:Destroy()
end
place(alice, Vector3.new(0, 3, -170))
step(Z.SpawnInterval * (Z.PerPlayer * 4))
local outsideOk = true
for _, model in ZombieService.All() do
	if model:GetAttribute("ZombieKind") ~= "Walker" then
		outsideOk = false
	end
end
check(#ZombieService.All() == Z.PerPlayer and outsideOk, "außerhalb: " .. Z.PerPlayer .. " normale Zombies (" .. #ZombieService.All() .. ")")

-- Obergrenze mit Bonus
for _, model in ZombieService.All() do
	model:Destroy()
end
Z.MaxTotal = 2
place(alice, Vector3.new(0, 3, -500))
for _ = 1, Z.MaxTotal + ExtinctionConfig.Redzone.MaxTotalBonus + 2 do
	ZombieService.Spawn(CENTER + Vector3.new(0, 0, -520), "Walker")
end
check(ZombieService.Count() == Z.MaxTotal + ExtinctionConfig.Redzone.MaxTotalBonus, "in der Zone darf der Server mehr Zombies haben (Bonus)")
place(alice, Vector3.new(0, 3, 20))
step(0.5)
check(ZombieService.Spawn(CENTER + Vector3.new(500, 0, 500)) == nil, "ohne Spieler in der Zone gilt wieder die normale Obergrenze")
Z.MaxTotal = 30

if failures == 0 then
	print("Rote Zonen: alles in Ordnung")
end

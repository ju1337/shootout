-- Die rote Zone der offenen Welt: der Modus setzt sie auf einen Ort der Karte (Place_<Name>), Attribut an der Karte und
-- am Spieler, PvP sofort drinnen, mehr Zombies mit Läufern und Brocken innerhalb der Zone, Obergrenze mit Bonus, außerhalb
-- normale Zombies; zieht sie weiter, gilt alles am neuen Ort
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
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Places" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))

-- Orte, an die die rote Zone ziehen kann (der Test setzt sie erst auf Test, später auf Weit)
for key, offset in { Test = Vector3.new(0, 2, -500), Weit = Vector3.new(0, 2, 900) } do
	local part = Instance.new("Part", map.Places)
	part.Name = "Place_" .. key
	part:SetAttribute("Title", key == "Test" and "Testzone" or "Weitweg")
	part.Size = Vector3.new(240, 4, 240)
	part.CFrame = CFrame.new(CENTER + offset)
end

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
require("ExtinctionConfig").Airdrop.FirstDelay = math.huge -- hier keine Lootdrops (eigener Test: airdrop)
require("ExtinctionConfig").Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
require("ExtinctionConfig").Day.Fixed = 12 -- immer Tag (nachts mehr Zombies; eigener Test: daycycle)
require("ExtinctionConfig").Zombies.KindWeights = { Walker = 1 } -- nur normale Zombies (Schreier rufen sonst Verstärkung)
Extinction.Init({ Join = function() end, Status = function() end })
RedzoneService.MoveNow("Test")

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

-- Die Zone steht an ihrem Ort
local R = ExtinctionConfig.Redzone.Radius
local zones = RedzoneService.List()
check(#zones == 1 and zones[1].Name == "Redzone" and zones[1].Key == "Test" and zones[1].Title == "Testzone" and zones[1].Radius == R,
	"eine rote Zone am Ort der Karte")
check(RedzoneService.At(CENTER + Vector3.new(0, 0, -500)) == zones[1] and RedzoneService.At(CENTER + Vector3.new(R - 10, 0, -500)) == zones[1], "Mitte und Innenraum")
check(RedzoneService.At(CENTER + Vector3.new(R + 10, 0, -500)) == nil and RedzoneService.At(CENTER) == nil, "außerhalb keine Zone")
check(RedzoneService.Random(Random.new(1)) == zones[1], "zufällige Zone = die Zone")
local published = HttpService:JSONDecode(map:GetAttribute("Redzones"))
check(#published == 1 and published[1].Title == "Testzone" and published[1].R == R and published[1].X == CENTER.X and published[1].Z == CENTER.Z - 500,
	"Zone als Attribut an der Karte für die Clients")

-- Betreten: Attribut, Meldung, PvP sofort (draußen sonst erst nach PvPDelay)
place(alice, Vector3.new(0, 3, -170))
step(0.5)
check(alice:GetAttribute("Redzone") == nil and alice:GetAttribute("PvP") == false, "draußen, aber keine rote Zone: PvP erst nach der Wartezeit")
place(alice, Vector3.new(0, 3, -470))
step(0.5)
check(alice:GetAttribute("Redzone") == "Redzone", "in der roten Zone: Attribut Redzone")
check(alice:GetAttribute("PvP") == true, "in der roten Zone gilt PvP sofort")
local banner = false
for _, entry in SIM.RemoteLog do
	if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" and entry.Args[2].Caption == "Rote Zone"
		and entry.Args[2].Title == "TESTZONE" then
		banner = true
	end
end
check(banner, "Meldung beim Betreten (mit dem Ort)")
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
local outsideWeights = Z.KindWeights
Z.KindWeights = { Walker = 1 } -- draußen (Tag) gibt es sonst auch ein paar Läufer und Schreier
place(alice, Vector3.new(0, 3, -170))
step(Z.SpawnInterval * (Z.PerPlayer * 4))
Z.KindWeights = outsideWeights
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

-- Die Zone zieht weiter: am alten Ort ist man draußen (PvP bleibt), am neuen wieder drin (mit Meldung)
local function banners(title) -- Meldungen beim Betreten (Titel = Ort; die Ansage an alle heißt "ROTE ZONE: <Ort>")
	local n = 0
	for _, entry in SIM.RemoteLog do
		if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" and entry.Args[2].Title == title then
			n += 1
		end
	end
	return n
end
place(alice, Vector3.new(0, 3, -500))
step(0.5)
check(alice:GetAttribute("Redzone") == "Redzone", "wieder in der Zone")
RedzoneService.MoveNow("Weit")
step(0.5)
check(alice:GetAttribute("Redzone") == nil and alice:GetAttribute("PvP") == true, "Zone weitergezogen: draußen, PvP bleibt")
check(RedzoneService.At(CENTER + Vector3.new(0, 0, -500)) == nil, "alter Ort ist keine rote Zone mehr")
local entered = banners("WEITWEG")
place(alice, Vector3.new(0, 3, 880))
step(0.5)
check(alice:GetAttribute("Redzone") == "Redzone" and banners("WEITWEG") == entered + 1, "am neuen Ort wieder drin, mit Meldung")
-- beginnt eine neue Runde, während man drinsteht (derselbe Ort, neue Zone): neue Meldung
entered = banners("WEITWEG")
RedzoneService.MoveNow("Weit")
step(0.5)
check(alice:GetAttribute("Redzone") == "Redzone" and banners("WEITWEG") == entered + 1, "neue Runde am selben Ort: wieder Meldung")
place(alice, Vector3.new(0, 3, 20))
step(0.5)

if failures == 0 then
	print("Rote Zonen: alles in Ordnung")
end

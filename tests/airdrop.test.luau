-- Lootdrops der offenen Welt: kein Abwurf ohne Spieler draußen, Vorwarnung mit Ansage und Attribut an der Karte, Fallschirm-
-- Kiste sinkt, landet mit bester Beute (E halten), Begleiter-Zombies, verschwindet leer oder nach Lifetime, danach Wartezeit bis
-- zum nächsten; Ziel in einer roten Zone, nie nah an der Safe Zone oder im Wasser
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
local A = ExtinctionConfig.Airdrop
A.FirstDelay, A.Warning, A.FallTime, A.OpenTime, A.Lifetime, A.MinInterval, A.MaxInterval = 10, 6, 4, 2, 40, 30, 30
A.Escort = 3
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
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Places", "Loot" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))

local redzone = Instance.new("Part", map.Places) -- einziger Ort für die rote Zone
redzone.Name = "Place_Test"
redzone:SetAttribute("Title", "Testzone")
redzone.Size = Vector3.new(240, 4, 240)
redzone.CFrame = CFrame.new(CENTER + Vector3.new(0, 2, -500))

local ground = Instance.new("Part", workspace)
ground.Name = "Ground"
local water = false
SIM.RaycastHandler = function(origin, direction)
	if direction.Y >= 0 then
		return nil
	end
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground, Material = Enum.Material.Grass }
end

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local ZombieService = require("ZombieService")
local AirdropService = require("AirdropService")
local HttpService = game:GetService("HttpService")
local Inventory = require("Inventory")
InventoryService.Init()
LootService.Init()
require("ExtinctionConfig").Day.Fixed = 12 -- immer Tag (nachts mehr Zombies; eigener Test: daycycle)
require("ExtinctionConfig").Zombies.KindWeights = { Walker = 1 } -- nur normale Zombies (Schreier rufen sonst Verstärkung)
Extinction.Init({ Join = function() end, Status = function() end })
ExtinctionConfig.Zombies.PerPlayer = 0 -- keine Zombies von selbst: nur die Begleiter zählen

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
step(1)
local function place(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
end
local function drops()
	return HttpService:JSONDecode(map:GetAttribute("Airdrops") or "[]")
end
local function banners(player, title)
	local n = 0
	for _, entry in SIM.RemoteLog do
		if entry.Remote == "Notify" and entry.Player == player and entry.Args[1] == "Banner" and entry.Args[2].Title == title then
			n += 1
		end
	end
	return n
end

-- Ohne Spieler draußen kein Abwurf (auch nach der Wartezeit)
step(A.FirstDelay + 5)
check(#AirdropService.Active() == 0 and #drops() == 0, "alle in der Safe Zone: kein Lootdrop")

-- Alice geht raus: der Abwurf kommt, Vorwarnung mit Ansage an alle
place(alice, Vector3.new(0, 3, -300))
step(2)
check(#AirdropService.Active() == 1, "Alice draußen: Lootdrop startet")
local list = drops()
check(#list == 1 and list[1].State == "Warning", "Attribut an der Karte: Warnung")
check(list[1].Eta > workspace:GetServerTimeNow() and list[1].Eta <= workspace:GetServerTimeNow() + A.Warning + A.FallTime + 1, "Eta zeigt die Landung")
check(banners(alice, "VERSORGUNGSABWURF") == 1 and banners(bob, "VERSORGUNGSABWURF") == 1, "Ansage an alle in der offenen Welt (auch in der Safe Zone)")
local target = Vector3.new(list[1].X, list[1].Y, list[1].Z)
check((target - CENTER).Magnitude > 100 + A.SafeMargin - 1, "Landestelle weit genug von der Safe Zone")
check(math.abs(target.X - CENTER.X) <= ExtinctionConfig.WorldSize / 2 - A.EdgeMargin + 1 and math.abs(target.Z - CENTER.Z) <= ExtinctionConfig.WorldSize / 2 - A.EdgeMargin + 1,
	"Landestelle nicht am Rand")
local flare = workspace.ExtinctionDrops:FindFirstChild("AirdropFlare")
check(flare ~= nil and flare:FindFirstChild("Beam") ~= nil, "Leuchtfackel mit Lichtsäule an der Landestelle")
check(AirdropService.Start() == nil, "nie zwei Abwürfe gleichzeitig")

-- Sinkflug (seit dem Start sind 2 s vergangen)
step(A.Warning - 2 + 0.4)
list = drops()
check(list[1].State == "Falling", "nach der Warnung: Kiste fällt")
local falling = workspace.ExtinctionDrops:FindFirstChild("AirdropFall")
check(falling ~= nil and falling:FindFirstChild("Canopy") ~= nil, "Kiste mit Fallschirm")
local high = falling:GetPivot().Position.Y - target.Y
check(high > A.Height * 0.5, "oben beim Start des Falls (" .. math.floor(high) .. ")")
step(1.2)
local lower = falling:GetPivot().Position.Y - target.Y
check(lower < high and lower > 2, "die Kiste sinkt (" .. math.floor(high) .. " -> " .. math.floor(lower) .. ")")
check(#workspace.ExtinctionLoot:GetChildren() == 0, "noch keine Beute am Boden")

-- Gelandet: Kiste mit bester Beute, Begleiter-Zombies
step(A.FallTime - 1.6 + 1)
list = drops()
check(list[1].State == "Landed", "gelandet")
check(workspace.ExtinctionDrops:FindFirstChild("AirdropFall") == nil, "Fallschirm weg")
local crate = nil
for _, model in workspace.ExtinctionLoot:GetChildren() do
	crate = model
end
local bag = crate and LootService.Get(crate.LootBag:GetAttribute("LootBag"))
check(bag ~= nil and bag.Kind == "Airdrop" and bag.Title == "LOOTDROP", "Lootdrop-Kiste")
local n = 0
local table_ = {}
for _, row in ExtinctionConfig.LootTables.Airdrop do
	table_[row.Id] = true
end
local allBest = true
for _, item in bag.Container.Slots do
	n += 1
	if not table_[item.Id] then
		allBest = false
	end
end
-- in der roten Zone ein paar Items mehr (ExtinctionConfig.Redzone.Loot), höchstens so viele, wie die Tabelle hat
local L = ExtinctionConfig.Redzone.Loot
local extra = list[1].Zone and (L.ExtraItems + L.AirdropExtra) or 0
local tableSize = #ExtinctionConfig.LootTables.Airdrop
check(n >= math.min(A.Items[1] + extra, tableSize) and n <= math.min(A.Items[2] + extra, tableSize) and allBest,
	"viele Items aus der Lootdrop-Tabelle (" .. n .. (list[1].Zone and ", rote Zone" or "") .. ")")
check(crate.LootBag.LootPrompt.HoldDuration == A.OpenTime, "E halten zum Öffnen (" .. A.OpenTime .. " s)")
check(crate.LootBag:FindFirstChild("TakeAllPrompt") ~= nil, "F = alles nehmen")
check((crate.LootBag.Position - target).Magnitude < 4, "Kiste liegt an der Landestelle")
check(banners(alice, "LOOTDROP GELANDET") == 1, "Ansage: gelandet")
check(ZombieService.Count() == A.Escort, "Begleiter-Zombies kommen (" .. ZombieService.Count() .. ")")
local escortNear = true
for _, model in ZombieService.All() do
	local d = Vector3.new(model:GetPivot().Position.X - target.X, 0, model:GetPivot().Position.Z - target.Z).Magnitude
	if d < 19 or d > 51 then
		escortNear = false
	end
end
check(escortNear, "Begleiter in 20 bis 50 Studs Abstand")

-- Alice nimmt alles: Kiste weg, Abwurf vorbei, nächster nach der Wartezeit
place(alice, target - CENTER + Vector3.new(0, 3, 4))
local ownedBefore = 0
check(LootService.Take(alice, bag.Id, "All") == false and LootService.Get(bag.Id) ~= nil,
	"ohne Gamepass ALLES LOOTEN kein Alles-Nehmen, die Kiste bleibt")
alice:SetAttribute("Pass_LootAll", true) -- Gamepass ALLES LOOTEN
check(LootService.Take(alice, bag.Id, "All") == true, "Alice nimmt alles")
local owned = 0
for _, entry in Inventory.Items(InventoryService.GetBag(alice)) do
	owned += entry.Count
end
check(owned > 0, "Beute im Inventar")
check(#drops() == 0 and #AirdropService.Active() == 0, "Abwurf beendet")
check(workspace.ExtinctionDrops:FindFirstChild("AirdropFlare") == nil, "Fackel weg")
step(A.MinInterval - 5)
check(#AirdropService.Active() == 0, "während der Wartezeit kein neuer Abwurf")
step(10)
check(#AirdropService.Active() == 1, "nach der Wartezeit der nächste Abwurf")

-- Unberührt: nach Lifetime verschwindet die Kiste
step(A.Warning + A.FallTime + 1)
check(drops()[1] and drops()[1].State == "Landed", "zweiter Abwurf gelandet")
step(A.Lifetime + 2)
check(#AirdropService.Active() == 0 and #workspace.ExtinctionLoot:GetChildren() == 0, "ohne Plünderer verschwindet die Kiste nach Lifetime")

-- Rote Zone: mit Wahrscheinlichkeit 1 landet der Abwurf dort
A.RedzoneChance = 1
step(A.MaxInterval + 2)
local last = drops()[1]
check(last ~= nil, "weiterer Abwurf")
local inZone = last and Vector3.new(last.X - CENTER.X, 0, last.Z - (CENTER.Z - 500)).Magnitude <= ExtinctionConfig.Redzone.Radius
check(inZone, "mit RedzoneChance 1 landet der Abwurf in der roten Zone")
check(last and last.Zone == "Testzone", "Zone steht im Attribut")
check(banners(alice, "VERSORGUNGSABWURF") >= 3, "jede Landung wird angesagt")

-- Zeiten dürfen nie ohne Spieler draußen laufen: alle zurück in die Safe Zone
for _, drop in table.clone(AirdropService.Active()) do
	LootService.Remove(drop.LootId or -1)
end
place(alice, Vector3.new(0, 3, 20))
step(A.MaxInterval + 40)
check(#AirdropService.Active() <= 1, "höchstens ein Abwurf")

if failures == 0 then
	print("Lootdrops: alles in Ordnung")
end

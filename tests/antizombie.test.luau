-- Anti-Zombie-Spritze: am Itemstand und in der Beute; benutzen (dauert UseTime) setzt den Schutz am Charakter, eine zweite
-- Spritze wird nicht verbraucht, solange er wirkt; einzige Wirkung: so lange spawnen bei diesem Spieler keine Zombies – nicht
-- aus der Umgebung, nicht von Schreiern, Nestern oder Lootdrops (nah dran) –, bei anderen Spielern weiter; vorhandene Zombies
-- bleiben; kein Heilen, keine Rüstung; nach Ablauf (oder Tod) spawnen sie wieder
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

local Z = ExtinctionConfig.Zombies
local syringe = ExtinctionConfig.Get("AntiZombie")
check(syringe and syringe.Kind == "Repel" and syringe.Duration > 0 and syringe.Price, "Anti-Zombie-Spritze mit Wirkdauer und Preis")
check(syringe and syringe.Heal == nil and syringe.Armor == nil and syringe.Immunity == nil, "keine anderen Wirkungen (Heilen, Rüstung)")
check(ExtinctionConfig.Infection == nil, "keine Infektion")
check(table.find(ExtinctionConfig.Stands.Stand_Items.Items, "AntiZombie") ~= nil, "Spritze am Itemstand")
local inLoot = {}
for name, rows in ExtinctionConfig.LootTables do
	for _, row in rows do
		if row.Id == "AntiZombie" then
			inLoot[name] = true
		end
	end
end
check(inLoot.Medical and inLoot.Zombie2 and inLoot.Airdrop and inLoot.Tier2, "Spritze auch als Beute (Sanikiste, Läufer, Lootdrop, Industrie)")
check(Z.ShieldRadius and Z.ShieldRadius >= Z.SpawnMin, "Schutzradius mindestens so groß wie der Spawn-Abstand")

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
local itemStand = Instance.new("Part", map.Stands)
itemStand.Name = "Stand_Items"
itemStand.CFrame = CFrame.new(CENTER + Vector3.new(36, 2.5, 34))
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
local ZombieService = require("ZombieService")
local Inventory = require("Inventory")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
ExtinctionConfig.HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.KindWeights = { Walker = 1 }
ExtinctionConfig.Redzone.Enabled = false
Extinction.Init({ Join = function() end, Status = function() end })

store.Data.u1 = { XP = {}, Coins = 2000, Rap = 0, Owned = {}, Equipped = {} }
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
step(0.5)
local function place(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
	step(0.3)
end
local function lastStatus(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "ExtUpdate" and entry.Player == player and entry.Args[1] == "Status" then
			return entry.Args[2]
		end
	end
	return nil
end
local function flat(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function near(player, range)
	local n = 0
	local here = player.Character.HumanoidRootPart.Position
	for _, model in ZombieService.All() do
		if flat(model:GetPivot().Position, here) <= range then
			n += 1
		end
	end
	return n
end
local function clearZombies()
	for _, model in ZombieService.All() do
		model.Humanoid.Health = 0
	end
	step(Z.CorpseLootTime + 1)
end

-- ---------- Kaufen und benutzen ----------
place(alice, Vector3.new(36, 3, 28))
check(InventoryService.Buy(alice, "Stand_Items", "AntiZombie", 2) == true, "zwei Spritzen am Itemstand gekauft")
check(ProgressService.Get(alice).Coins == 2000 - 2 * syringe.Price, "Preis bezahlt")
local slot = nil
for s = 1, ExtinctionConfig.HotbarSlots do
	local item = InventoryService.GetBag(alice).Slots[s]
	if item and item.Id == "AntiZombie" then
		slot = s
	end
end
check(slot ~= nil, "Spritze auf der Hotbar")
place(alice, Vector3.new(0, 3, 400))
local humanoid = alice.Character.Humanoid
humanoid.Health = 60
alice.Character:SetAttribute("Armor", 0)
InventoryService.Use(alice, slot)
check(alice.Character:GetAttribute("UsingItem") == syringe.Name, "Spritze wird benutzt")
step(syringe.UseTime + 0.2)
local left = (alice.Character:GetAttribute("ZombieShieldUntil") or 0) - workspace:GetServerTimeNow()
check(math.abs(left - syringe.Duration) < 1, "Schutz für " .. syringe.Duration .. " s (" .. math.floor(left) .. ")")
check(humanoid.Health == 60 and (alice.Character:GetAttribute("Armor") or 0) == 0, "kein Heilen, keine Rüstung")
check(Inventory.Count(InventoryService.GetBag(alice), "AntiZombie") == 1, "eine Spritze verbraucht")
check(string.find(lastStatus(alice) or "", "keine Zombies", 1, true) ~= nil, "Meldung: keine Zombies bei dir")
InventoryService.Use(alice, slot)
step(syringe.UseTime + 0.2)
check(Inventory.Count(InventoryService.GetBag(alice), "AntiZombie") == 1, "zweite Spritze nicht verbraucht, solange sie wirkt")
check(string.find(lastStatus(alice) or "", "wirkt noch", 1, true) ~= nil, "Meldung: wirkt noch")

-- ---------- Wirkung: bei Alice spawnt nichts, bei Bob schon ----------
-- (während der Benutzung wirkte die Spritze noch nicht: was bis dahin gespawnt ist, weg)
for _, model in ZombieService.All() do
	model.Humanoid.Health = 0
end
step(0.2)
check(#ZombieService.All() == 0, "aufgeräumt")
place(bob, Vector3.new(0, 3, -600))
step(Z.SpawnInterval * Z.PerPlayer * 4)
check(near(alice, Z.SpawnMax + 30) == 0, "bei Alice spawnen keine Zombies (" .. near(alice, Z.SpawnMax + 30) .. ")")
check(near(bob, Z.SpawnMax + 30) >= Z.PerPlayer, "bei Bob schon (" .. near(bob, Z.SpawnMax + 30) .. ")")
-- auch keine aus anderen Quellen (Schreier, Nester, Lootdrop-Begleiter): Spawns nah an Alice scheitern
local here = alice.Character.HumanoidRootPart.Position
check(ZombieService.Spawn(here + Vector3.new(20, -3, 0), "Walker", true) == nil, "direkter Spawn nah an Alice scheitert")
check(#ZombieService.SpawnAround(here, 4, 10, 40, "Walker", true) == 0, "Begleiter/Rufe nah an Alice: keiner")
check(ZombieService.Spawn(here + Vector3.new(Z.ShieldRadius + 20, -3, 0), "Walker", true) ~= nil, "weiter weg geht es")
-- Dungeon-Hallen haben ihre eigene Grenze: dort blockieren weder Spritze noch Server-Obergrenze (sonst friert die Welle ein)
local dungeonZombie = ZombieService.Spawn(here + Vector3.new(20, -3, 0), "Walker", "Dungeon")
check(dungeonZombie ~= nil, "Dungeon-Spawn auch neben der Spritze")
-- vorhandene Zombies bleiben (die Spritze verjagt keine)
local walker = ZombieService.Spawn(here + Vector3.new(Z.ShieldRadius + 30, -3, 0), "Walker", true)
walker:PivotTo(alice.Character:GetPivot() * CFrame.new(0, 0, 4))
step(0.6)
check(walker.Parent ~= nil and walker.Humanoid.Health > 0, "ein vorhandener Zombie bleibt")
clearZombies()

-- ---------- Nach Ablauf wieder Zombies ----------
alice.Character:SetAttribute("ZombieShieldUntil", workspace:GetServerTimeNow() + 1)
step(1.5)
step(Z.SpawnInterval * Z.PerPlayer * 4)
check(near(alice, Z.SpawnMax + 30) >= Z.PerPlayer, "nach Ablauf spawnen wieder Zombies bei Alice (" .. near(alice, Z.SpawnMax + 30) .. ")")

-- ---------- Tod beendet die Wirkung ----------
alice.Character:SetAttribute("ZombieShieldUntil", workspace:GetServerTimeNow() + 120)
alice.Character.Humanoid.Health = 0
step(ExtinctionConfig.RespawnTime + 0.5)
check(alice.Character and alice.Character.Humanoid.Health > 0 and alice.Character:GetAttribute("ZombieShieldUntil") == nil,
	"nach dem Tod: neuer Charakter ohne Schutz")

if failures > 0 then
	error(failures .. " Fehler")
end
print("antizombie: alles ok")

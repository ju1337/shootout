-- Zombies der offenen Welt: spawnen nur um Spieler draußen im weiteren Umkreis (nicht in der Safe Zone, nicht auf
-- Dächern), höchstens PerPlayer pro Spieler und MaxTotal insgesamt, jagen Spieler in Sichtweite (nicht in die
-- Safe Zone hinein), schlagen zu (kein Schaden in der Safe Zone), bringen beim Tod wenige Münzen und manchmal einen
-- Beutel, verschwinden, wenn kein Spieler mehr in der Nähe ist
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
for _, name in { "Zone", "Spawns", "Portals", "Stands" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))

-- Boden: flach auf Höhe 0, im Norden ein breites "Dach" (Höhe 10) zwischen z = 300 und 480
local ground = Instance.new("Part", workspace)
ground.Name = "Ground"
local roof = Instance.new("Part", workspace)
roof.Name = "Roof"
local downRays = 0
SIM.RaycastHandler = function(origin, direction)
	if direction.Y >= 0 then
		return nil
	end
	downRays += 1
	local z = origin.Z - CENTER.Z
	if z > 300 and z < 480 then
		return { Position = Vector3.new(origin.X, 10, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = roof }
	end
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground }
end

local Z = ExtinctionConfig.Zombies
local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local ZombieService = require("ZombieService")
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
step(3)
check(ZombieService.Count() == 0, "in der Safe Zone spawnen keine Zombies")

local function place(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
end
local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Alice geht raus (Süden, knapp vor der Safe Zone): Zombies im weiteren Umkreis um sie, nicht nah an der Safe Zone
place(alice, Vector3.new(0, 3, -170))
step(Z.SpawnInterval * (Z.PerPlayer * 4))
local all = ZombieService.All()
check(#all == Z.PerPlayer, "um Alice genau " .. Z.PerPlayer .. " Zombies (" .. #all .. ")")
local okDistance, okSafe = true, true
for _, model in all do
	local position = model:GetPivot().Position
	local d = flatDistance(position, alice.Character.HumanoidRootPart.Position)
	if d < Z.SpawnMin - 1 or d > Z.SpawnMax + 1 then
		okDistance = false
	end
	if Extinction.InSafeZone(position) or flatDistance(position, CENTER) < 100 + Z.SafeMargin then
		okSafe = false
	end
	check(model:GetAttribute("IsZombie") == true and model.Parent == workspace.Zombies, "Zombie im Ordner Zombies markiert")
end
check(okDistance, "Abstand beim Spawnen zwischen SpawnMin und SpawnMax")
check(okSafe, "kein Zombie in oder nah an der Safe Zone")

-- Nicht auf Dächern: Bob steht neben dem "Dach" – Spawns dort werden verworfen
place(bob, Vector3.new(0, 3, 390))
step(Z.SpawnInterval * 12)
local onRoof = false
for _, model in ZombieService.All() do
	if model:GetPivot().Position.Y > 5 then
		onRoof = true
	end
end
check(not onRoof, "kein Zombie auf dem Dach gespawnt")
check(ZombieService.Spawn(CENTER + Vector3.new(500, 0, 500)) ~= nil, "Spawn direkt (unter der Obergrenze)")
place(bob, Vector3.new(0, 3, 20)) -- Bob zurück in die Safe Zone
step(0.5)

-- Jagen: Zombie in Sichtweite läuft auf Alice zu
local hunter = ZombieService.Spawn(alice.Character.HumanoidRootPart.Position + Vector3.new(40, -3, 0))
step(0.6)
local target = hunter.Humanoid.MoveToTarget
check(target ~= nil and flatDistance(target, alice.Character.HumanoidRootPart.Position) < 1, "Zombie läuft auf Alice zu")
check(hunter.Humanoid.WalkSpeed > Z.WalkSpeed, "jagen ist schneller als schlurfen")

-- Zuschlagen
local health = alice.Character.Humanoid.Health
hunter:PivotTo(alice.Character:GetPivot() * CFrame.new(0, 0, 3))
step(0.6)
check(alice.Character.Humanoid.Health == health - Z.AttackDamage, "Zombie trifft Alice (" .. alice.Character.Humanoid.Health .. ")")
step(Z.AttackDelay)
check(alice.Character.Humanoid.Health == health - 2 * Z.AttackDamage, "nach AttackDelay der nächste Schlag")

-- Safe Zone: Zombies bleiben draußen, kein Schaden
place(alice, Vector3.new(0, 3, -95))
step(0.6)
local inside = alice.Character.Humanoid.Health
hunter:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, -120)))
step(1)
local goal = hunter.Humanoid.MoveToTarget
check(goal == nil or flatDistance(goal, CENTER) >= 100, "Zombie geht nicht in die Safe Zone")
check(alice.Character.Humanoid.Health == inside, "in der Safe Zone kein Schaden")

-- Tod: wenige Münzen für den Schützen, Beutel mit einfacher Beute
ExtinctionConfig.ZombieDropChance = 1
place(alice, Vector3.new(0, 3, -400))
step(0.5)
local coins = ProgressService.Get(alice).Coins
local bags = #workspace.ExtinctionLoot:GetChildren()
local victim = ZombieService.All()[1]
Damage.Apply(victim, victim.Humanoid, 1000, { Player = alice, Weapon = "Rifle" })
step(0.2)
check(ProgressService.Get(alice).Coins == coins + ExtinctionConfig.ZombieCoins, "Münzen für den Zombie: "
	.. ProgressService.Get(alice).Coins - coins)
check(#workspace.ExtinctionLoot:GetChildren() == bags + 1, "Beutel gefallen")
local newest = nil
for _, model in workspace.ExtinctionLoot:GetChildren() do
	newest = model
end
local bag = newest and LootService.Get(newest.LootBag:GetAttribute("LootBag"))
local lowTier = true
for _, item in bag and bag.Container.Slots or {} do
	local config = ExtinctionConfig.Get(item.Id)
	if not config or (config.Tier or 0) > 2 then
		lowTier = false
	end
end
check(bag ~= nil and lowTier, "nur einfache Beute")
step(5)
check(victim.Parent == nil, "Leiche verschwindet")

-- Obergrenze für den ganzen Server
Z.MaxTotal = ZombieService.Count() + 1
place(bob, Vector3.new(400, 3, 200))
step(Z.SpawnInterval * 10)
check(ZombieService.Count() <= Z.MaxTotal, "nicht mehr als MaxTotal Zombies")
Z.MaxTotal = ZombieService.Count()
check(ZombieService.Spawn(CENTER + Vector3.new(500, 0, 200)) == nil, "an der Obergrenze kein Spawn")
Z.MaxTotal = 70

-- Alle in der Safe Zone: nach kurzer Zeit verschwinden die Zombies (nicht sofort)
place(alice, Vector3.new(0, 3, 30))
place(bob, Vector3.new(0, 3, 40))
step(3)
check(ZombieService.Count() > 0, "Zombies verschwinden nicht sofort")
step(10)
check(ZombieService.Count() == 0, "ohne Spieler draußen in der Nähe verschwinden alle Zombies (" .. ZombieService.Count() .. ")")
check(downRays > 0, "Boden wird per Raycast gesucht")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

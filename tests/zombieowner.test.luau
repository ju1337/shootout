-- Zombies pro Spieler (Joel/Julio 2026-10-16): stehen zwei Spieler zusammen draußen, hat jeder seine eigenen Zombies
-- (Attribut ZombieOwnerId), so viele wie allein – nicht doppelt so viele für beide. Ein eigener Zombie jagt und schlägt
-- nur seinen Besitzer, nur der Besitzer kann ihn treffen (keine Bots, keine anderen Spieler) und seine Leiche
-- durchsuchen; Kill, Münzen und XP gehen an ihn. Bosse, Event-Zombies und Dungeon-Wellen gehören allen.
-- Verlässt der Besitzer das Spiel, sind seine Zombies weg. Der Client blendet fremde Zombies aus (ZombieVisibility).
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
local store = SIM.DataStore("PlayerData_v2")
local ExtinctionConfig = require("ExtinctionConfig")
ExtinctionConfig.SpawnProtection = 0
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
local Damage = require("Damage")
local ZombieOwner = require("ZombieOwner")
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
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Horde.Enabled = false
ExtinctionConfig.HeliCrash.Enabled = false
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.KindWeights = { Walker = 1 }
ExtinctionConfig.Redzone.Enabled = false
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
step(1)
local function place(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
end
local function owned(player)
	local list = {}
	for _, model in ZombieService.All() do
		if model:GetAttribute("ZombieOwnerId") == player.UserId then
			table.insert(list, model)
		end
	end
	return list
end

-- ---------- Zwei Spieler zusammen: jeder hat seine eigenen, so viele wie allein ----------
place(alice, Vector3.new(0, 3, -400))
place(bob, Vector3.new(4, 3, -400))
step(Z.SpawnInterval * Z.PerPlayer * 4)
check(#owned(alice) == Z.PerPlayer, "Alice hat " .. Z.PerPlayer .. " eigene Zombies (" .. #owned(alice) .. ")")
check(#owned(bob) == Z.PerPlayer, "Bob hat " .. Z.PerPlayer .. " eigene Zombies (" .. #owned(bob) .. ")")
check(#ZombieService.All() == 2 * Z.PerPlayer, "keine gemeinsamen Zombies aus der Umgebung (" .. #ZombieService.All() .. ")")
local aliceZombie = owned(alice)[1]
local bobZombie = owned(bob)[1]
check(ZombieOwner.CanSee(aliceZombie, alice) and not ZombieOwner.CanSee(aliceZombie, bob), "Alice sieht ihren Zombie, Bob nicht")
local hidden = ZombieOwner.HiddenFrom(bob)
check(table.find(hidden, aliceZombie) ~= nil and table.find(hidden, bobZombie) == nil,
	"Raycast-Filter für Bob: Alices Zombies raus, seine bleiben")

-- ---------- Jagen und Schlagen nur den Besitzer ----------
-- Bob steht direkt neben Alices Zombie, Alice weiter weg (aber in Sichtweite, 40 Studs): der Zombie läuft trotzdem zu Alice
place(alice, Vector3.new(0, 3, -400))
place(bob, Vector3.new(40, 3, -400))
aliceZombie:PivotTo(bob.Character:GetPivot() * CFrame.new(0, 0, 3))
step(0.6)
local goal = aliceZombie.Humanoid.MoveToTarget
check(goal ~= nil and (goal - alice.Character.HumanoidRootPart.Position).Magnitude < 1, "Alices Zombie jagt Alice, nicht Bob")
local bobHealth = bob.Character.Humanoid.Health
Damage.Apply(bob.Character, bob.Character.Humanoid, 10, { Model = aliceZombie, BotName = "Zombie", Weapon = "Zombie" })
check(bob.Character.Humanoid.Health == bobHealth, "Alices Zombie macht Bob keinen Schaden")

-- ---------- Treffen nur der Besitzer ----------
local health = aliceZombie.Humanoid.Health
check(Damage.Apply(aliceZombie, aliceZombie.Humanoid, 10, { Player = bob, Weapon = "Rifle" }) == 0
	and aliceZombie.Humanoid.Health == health, "Bob trifft Alices Zombie nicht")
local bot = Instance.new("Model", workspace)
bot.Name = "Bot"
check(Damage.Apply(aliceZombie, aliceZombie.Humanoid, 10, { Model = bot, BotName = "Bot", Weapon = "Rifle" }) == 0,
	"Bots treffen Alices Zombie nicht")
check(Damage.Apply(aliceZombie, aliceZombie.Humanoid, 10, { Player = alice, Weapon = "Rifle" }) > 0, "Alice trifft ihn")

-- ---------- Kill, Münzen, Leiche nur für den Besitzer ----------
ExtinctionConfig.ZombieKinds.Walker.Drop = 1
local victim = ZombieService.Spawn(alice.Character.HumanoidRootPart.Position + Vector3.new(0, -3, -20), "Walker", true, false, alice)
check(victim ~= nil and victim:GetAttribute("ZombieOwnerId") == alice.UserId, "direkter Spawn mit Besitzer")
local coins = ProgressService.Get(alice).Coins
local kills = alice:GetAttribute("ZombieKills") or 0
Damage.Apply(victim, victim.Humanoid, 1000, { Player = alice, Weapon = "Rifle", Headshot = true })
step(0.2)
check(ProgressService.Get(alice).Coins > coins and (alice:GetAttribute("ZombieKills") or 0) == kills + 1,
	"Alice bekommt Kill und Münzen für ihren Zombie")
check(victim:GetAttribute("ZombieOwnerId") == alice.UserId, "Leiche gehört weiter Alice")
local prompt = victim.HumanoidRootPart:FindFirstChild("CorpsePrompt")
check(prompt ~= nil, "Leiche mit Beute")
place(bob, Vector3.new(0, 3, -400))
victim:PivotTo(CFrame.new(bob.Character.HumanoidRootPart.Position + Vector3.new(0, 0, -2)))
step(0.1)
local bobItems = #require("Inventory").Items(InventoryService.GetBag(bob))
if prompt then
	prompt.Triggered:Fire(bob)
end
check(#require("Inventory").Items(InventoryService.GetBag(bob)) == bobItems and prompt and prompt.Parent ~= nil,
	"Bob kann Alices Leiche nicht durchsuchen")

-- ---------- Bosse, Events, Dungeon: gemeinsam ----------
local boss = ZombieService.Spawn(CENTER + Vector3.new(300, 0, -400), "Boss", true, false, alice)
check(boss ~= nil and boss:GetAttribute("ZombieOwnerId") == nil, "Boss gehört allen (auch wenn ein Besitzer übergeben wird)")
local event = ZombieService.SpawnAround(CENTER + Vector3.new(-300, 0, -400), 2, 20, 40, "Walker", true)
check(#event > 0 and event[1]:GetAttribute("ZombieOwnerId") == nil, "Event-Zombies gehören allen")
local dungeon = ZombieService.Spawn(CENTER + Vector3.new(-300, 0, -500), "Walker", "Dungeon", false, alice)
check(dungeon ~= nil and dungeon:GetAttribute("ZombieOwnerId") == nil, "Dungeon-Zombies gehören allen")
if boss then
	check(Damage.Apply(boss, boss.Humanoid, 5, { Player = bob, Weapon = "Rifle" }) > 0, "Bob trifft den Boss")
end

-- ---------- Client: fremde Zombies ausgeblendet ----------
rawget(SIM.Players, "__props").LocalPlayer = bob
local ZombieVisibility = require("ZombieVisibility")
ZombieVisibility.Init()
step(0.2)
local mine = owned(alice)[1]
check(mine ~= nil and mine.Parent ~= workspace.Zombies, "bei Bob: Alices Zombie aus der Welt genommen")
check(bobZombie.Parent == workspace.Zombies or bobZombie.Parent == nil, "bei Bob: sein eigener Zombie bleibt")
check(boss == nil or boss.Parent == workspace.Zombies, "bei Bob: Boss bleibt sichtbar")
local late = ZombieService.Spawn(CENTER + Vector3.new(200, 0, -300), "Walker", true, false, alice)
step(0.2)
check(late ~= nil and late.Parent ~= workspace.Zombies, "bei Bob: neue Zombies von Alice auch ausgeblendet")

-- ---------- Besitzer weg: seine Zombies weg ----------
local aliceList = owned(alice)
SIM.Leave(alice)
step(2.5)
local left = 0
for _, model in aliceList do
	if ZombieService.Info(model) then
		left += 1
	end
end
check(left == 0, "Alice hat das Spiel verlassen: ihre Zombies sind weg (" .. left .. ")")

if failures > 0 then
	error(failures .. " Fehler")
end
print("zombieowner: alles ok")

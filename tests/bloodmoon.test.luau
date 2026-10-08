-- Blutmond-Ereignis: Warnung und Start nach Plan, 10 Minuten Dauer, Nacht, stärkere Zombies mit besserer Beute, Bosse
-- (Name, Lebensbalken, beste Beute, Ansagen), Ende
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
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground }
end

local B = ExtinctionConfig.BloodMoon
local RS = game:GetService("ReplicatedStorage")
local DayCycle = require("DayCycle")
local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local ZombieService = require("ZombieService")
local BloodMoonService = require("BloodMoonService")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
ExtinctionConfig.HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
ExtinctionConfig.Zombies.KindWeights = { Walker = 1 }
ExtinctionConfig.Zombies.NightKindWeights = { Walker = 1 }
ExtinctionConfig.Day.BloodMoonKindWeights = { Walker = 1 }
B.FirstDelay = 120
B.Interval = 3600
Extinction.Init({ Join = function() end, Status = function() end })

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)
alice:SetAttribute("Mode", "Extinction")
Extinction.AddPlayer(alice)
step(2)

local function banner(title)
	for _, entry in SIM.RemoteLog do
		if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" and string.find(entry.Args[2].Title, title, 1, true) then
			return true
		end
	end
	return false
end

-- normaler Zombie vor dem Ereignis
alice.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 400)))
local normal = ZombieService.Spawn(CENTER + Vector3.new(30, 0, 400), "Walker", true)
local normalHealth = normal:FindFirstChildOfClass("Humanoid").MaxHealth
check(not BloodMoonService.Active(), "am Anfang kein Blutmond")

-- Warnung und Start nach Plan
step(120 - B.Warning + 3)
check(banner("DER BLUTMOND STEIGT AUF") and not BloodMoonService.Active(), "Warnung vorher")
step(B.Warning + 1)
check(BloodMoonService.Active() and banner("BLUTMOND"), "Blutmond beginnt mit Ansage")
local start = RS:GetAttribute("BloodMoonStart")
check(math.abs(RS:GetAttribute("BloodMoonEnd") - start - B.Duration) < 0.01, "dauert " .. B.Duration .. " Sekunden")
check(DayCycle.IsNight(DayCycle.Clock(workspace:GetServerTimeNow())), "beim Blutmond ist es Nacht")

-- stärkere Zombies, bessere Beute
local strong = ZombieService.Spawn(CENTER + Vector3.new(-30, 0, 400), "Walker", true)
local strongHealth = strong:FindFirstChildOfClass("Humanoid").MaxHealth
check(strongHealth > normalHealth * 1.15, "Zombies im Blutmond zäher (" .. normalHealth .. " -> " .. strongHealth .. ")")
local walker = ZombieService.Kind("Walker")
local better = 0
for _ = 1, 30 do
	for _, item in ZombieService.RollCorpseLoot(walker, true) do
		better += 1
		local _ = item
	end
end
local normalItems = 0
for _ = 1, 30 do
	normalItems += #ZombieService.RollCorpseLoot(walker, false)
end
check(better > normalItems, "mehr Beute im Blutmond (" .. normalItems .. " -> " .. better .. ")")

-- Boss nach FirstBoss Sekunden bei Alice
step(B.FirstBoss + 1)
local bosses = BloodMoonService.Bosses()
check(#bosses == 1, "ein Boss erscheint (" .. #bosses .. ")")
local boss = bosses[1]
if boss then
	local humanoid = boss:FindFirstChildOfClass("Humanoid")
	check(boss:GetAttribute("Boss") == true and boss:GetAttribute("ZombieKind") == "Boss", "Boss markiert")
	check(humanoid.MaxHealth >= 1500, "Boss sehr zäh (" .. humanoid.MaxHealth .. ")")
	check(boss:FindFirstChild("BossTag", true) ~= nil and boss:FindFirstChild("BossGlow") ~= nil, "Name, Lebensbalken und Umriss")
	check(banner("EINE BLUTBESTIE IST ERWACHT"), "Ansage beim Erscheinen")
	local distance = (boss:GetPivot().Position - alice.Character:GetPivot().Position).Magnitude
	check(distance > B.BossMinDistance - 15 and distance < B.BossMaxDistance + 25, "in der Nähe des Spielers (" .. math.floor(distance) .. ")")
	-- Alice erledigt den Boss
	local Damage = require("Damage")
	Damage.Apply(boss, humanoid, humanoid.Health + 10, { Player = alice, Weapon = "Rifle" })
	step(0.5)
	check(banner("BLUTBESTIE ERLEDIGT"), "Ansage beim Tod")
	local root = boss:FindFirstChild("HumanoidRootPart")
	check(root and root:FindFirstChild("CorpsePrompt") ~= nil, "Boss lässt Beute in der Leiche")
end
check(#BloodMoonService.Bosses() <= B.MaxBosses, "höchstens " .. B.MaxBosses .. " Bosse")

-- Ende nach 10 Minuten
step(B.Duration)
check(not BloodMoonService.Active(), "nach " .. B.Duration .. " Sekunden vorbei")
check(banner("DER BLUTMOND IST VORBEI"), "Ansage am Ende")
-- Admin: sofort starten und beenden
BloodMoonService.Start(60)
check(BloodMoonService.Active(), "Start per Admin")
BloodMoonService.Stop()
step(0.5)
check(not BloodMoonService.Active(), "Stopp per Admin")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

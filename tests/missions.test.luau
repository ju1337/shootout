-- Aufträge (MissionService): drei verschiedene Aufträge pro Spieler, Fortschritt durch Zombie-Kills (auch Läufer und rote
-- Zone), Aktivitäten, Lootdrops (je Kiste einmal), Orte und Nacht-Minuten; erledigt = Münzen, Beute, Meldung, neuer Auftrag
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
ExtinctionConfig.SpawnProtection = 0 -- Spawnschutz prüft tests/extinction; hier wird gleich nach dem Verlassen geschossen
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
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Activities" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))


local places = Instance.new("Folder", map)
places.Name = "Places"
local village = Instance.new("Part", places)
village.Name = "Place_Testdorf"
village.Size = Vector3.new(120, 4, 120)
village.CFrame = CFrame.new(CENTER + Vector3.new(0, 2, 600))
village:SetAttribute("Title", "TESTDORF")

local function marker(name, offset, title)
	local part = Instance.new("Part", map.Activities)
	part.Name = name
	part.Size = Vector3.new(4, 2, 4)
	part.CFrame = CFrame.new(CENTER + offset + Vector3.new(0, 1, 0))
	part:SetAttribute("Title", title)
	return part
end
marker("Act_Nest", Vector3.new(0, 0, -400), "Testwald")
marker("Act_Cache", Vector3.new(400, 0, 0), "Testlager")
marker("Act_Radio", Vector3.new(-400, 0, 0), "Funkturm")

local ground = Instance.new("Part", workspace)
ground.Name = "Ground"
SIM.RaycastHandler = function(origin, direction)
	if direction.Y >= 0 then
		return nil
	end
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground }
end

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local ZombieService = require("ZombieService")
local MissionService = require("MissionService")
local HttpService = game:GetService("HttpService")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
ExtinctionConfig.HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.KindWeights = { Walker = 1 }
Extinction.Init({ Join = function() end, Status = function() end })

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)
alice:SetAttribute("Mode", "Extinction")
Extinction.AddPlayer(alice)
step(2)
local humanoid = alice.Character:FindFirstChildOfClass("Humanoid")
humanoid.MaxHealth = 1e7
humanoid.Health = 1e7
local function place(offset)
	alice.Character:PivotTo(CFrame.new(CENTER + offset + Vector3.new(0, 3, 0)))
end
local function list()
	local ok, value = pcall(HttpService.JSONDecode, HttpService, alice:GetAttribute("ExtMissions") or "[]")
	return ok and value or {}
end
local function banner(title)
	local n = 0
	for _, entry in SIM.RemoteLog do
		if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" and entry.Args[2].Title == title then
			n += 1
		end
	end
	return n
end
local function defOf(id)
	for _, def in ExtinctionConfig.Missions.Pool do
		if def.Id == id then
			return def
		end
	end
	return nil
end
local state = MissionService.Get(alice)
-- Auftrag gezielt setzen (Platz 1)
local function setMission(id, need, placeInfo)
	local def = defOf(id)
	state.Missions[1] = { Def = def, Need = need, Have = 0, Place = placeInfo,
		Text = placeInfo and string.format(def.Text, placeInfo.Title) or string.format(def.Text, need) }
end

-- drei verschiedene Aufträge
local missions = list()
check(#missions == 3, "drei Aufträge (" .. #missions .. ")")
local ids = {}
for _, mission in state.Missions do
	ids[mission.Def.Id] = true
end
local distinct = 0
for _ in ids do
	distinct += 1
end
check(distinct == 3, "keine zwei gleichen Aufträge")

-- Zombies: echte Kills zählen
setMission("Zombies", 2)
place(Vector3.new(0, 0, -300))
step(1)
local zombie = ZombieService.Spawn(CENTER + Vector3.new(10, 0, -300))
local coins = ProgressService.Get(alice).Coins
Damage.Apply(zombie, zombie:FindFirstChildOfClass("Humanoid"), 1e5, { Player = alice, Weapon = "Test" })
step(0.5)
check(state.Missions[1].Def.Id == "Zombies" and state.Missions[1].Have == 1, "Zombie-Kill zählt (1/2)")
local zombie2 = ZombieService.Spawn(CENTER + Vector3.new(14, 0, -300))
Damage.Apply(zombie2, zombie2:FindFirstChildOfClass("Humanoid"), 1e5, { Player = alice, Weapon = "Test" })
step(0.5)
check(banner("AUFTRAG ERLEDIGT") == 1, "Meldung AUFTRAG ERLEDIGT")
check(ProgressService.Get(alice).Coins >= coins + defOf("Zombies").Coins, "Münzen für den Auftrag")
check(#list() == 3 and state.Missions[#state.Missions].Def.Id ~= nil, "danach wieder drei Aufträge")

-- Läufer zählen als Läufer und als Zombie
setMission("Runners", 1)
local runner = ZombieService.Spawn(CENTER + Vector3.new(12, 0, -300), "Runner")
Damage.Apply(runner, runner:FindFirstChildOfClass("Humanoid"), 1e5, { Player = alice, Weapon = "Test" })
step(0.5)
check(banner("AUFTRAG ERLEDIGT") == 2, "Läufer-Auftrag erledigt")

-- Aktivität (Nest) über ActivityService.OnEvent
setMission("Nest", 1)
MissionService.Progress(alice, "Cache")
check(state.Missions[1].Def.Id == "Nest" and state.Missions[1].Have == 0, "falsches Ereignis zählt nicht")
for _, callback in require("ActivityService").OnEvent do
	callback(alice, "Nest")
end
check(banner("AUFTRAG ERLEDIGT") == 3, "Nest-Auftrag über Aktivität erledigt")

-- Lootdrop: je Kiste nur einmal
setMission("Airdrop", 2)
local bagId = LootService.Create(alice.Character.HumanoidRootPart.Position + Vector3.new(2, 0, 0), { { Id = "Bandage", Count = 1 } },
	"Airdrop", "LOOTDROP")
LootService.Open(alice, bagId)
LootService.Open(alice, bagId)
check(state.Missions[1].Have == 1, "dieselbe Kiste zählt nur einmal")

-- Ort erkunden
setMission("Explore", 1, { Key = "Testdorf", Title = "TESTDORF", Position = village.Position, Radius = 60 })
check(string.find(list()[1] and list()[1].Text or state.Missions[1].Text, "TESTDORF", 1, true) ~= nil or state.Missions[1].Text == "Erkunde: TESTDORF",
	"Ort im Auftragstext")
place(Vector3.new(0, 0, 600))
step(2)
check(banner("AUFTRAG ERLEDIGT") >= 4, "Ort erkundet")

-- Nacht: jede volle Minute draußen zählt
setMission("Night", 2)
ExtinctionConfig.Day.Fixed = 0
step(62)
check(state.Missions[1].Def.Id == "Night" and state.Missions[1].Have == 1, "eine Nacht-Minute gezählt")
ExtinctionConfig.Day.Fixed = 12
step(62)
check(state.Missions[1].Have == 1, "am Tag zählt es nicht")

-- Verlassen: Aufträge weg
Extinction.RemovePlayer(alice)
check(alice:GetAttribute("ExtMissions") == nil and MissionService.Get(alice) == nil, "beim Verlassen keine Aufträge mehr")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

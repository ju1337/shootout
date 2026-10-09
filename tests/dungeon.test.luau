-- Dungeons (DungeonService): Eingang (Gruftkapelle) im Camp, E ohne Schlüssel geht nicht, mit Schlüssel kommt der Squad in der Nähe
-- mit (Schlüssel weg, Fremde bleiben draußen), Welle um Welle Zombies aus den Gittern, nach jeder Welle Portal offen:
-- hindurch = Beute und zurück vor die Kapelle; Tod im Dungeon = Tasche weg, Beute weg; leere Halle wird abgebaut.
-- Dazu: Schlüssel droppen bei normalen Zombies (nicht im Dungeon) und in Event-Beute, Wellen werden größer.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 1, 20) -- mit Heartbeat (Safe-Zone-Prüfung, Magazin-Abgleich)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local HttpService = game:GetService("HttpService")
local Remotes = require("Remotes")
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
local Damage = require("Damage")
ProgressService.Init()
WeaponService.Init()

-- Karte wie aus tools/build_maps.py: Safe Zone (Radius 100) um (0, 0, -6000), Spawns, Stände, Lager, Tor zum Hub
local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("DisplayName", "Ödland")
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Zentrale" } do
	Instance.new("Folder", map).Name = name
end
-- Punkt vor der Gruftkapelle im Camp (tools/camp_phoenix.py crypt_gate), Blick zur Straße (+X)
local gate = Instance.new("Part", map.Zentrale)
gate.Name = "DungeonGate"
gate.CFrame = CFrame.lookAt(CENTER + Vector3.new(-40, 3, 70), CENTER + Vector3.new(0, 3, 70))
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
-- kleine Safe Zone draußen (Safehouse) mit eigenen Spawns
local safehouse = Instance.new("Part", map.Zone)
safehouse.Name = "SafeZone_Test"
safehouse:SetAttribute("Title", "SAFEHOUSE TEST")
safehouse.Size = Vector3.new(80, 80, 80)
safehouse.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 600))
local safehouseSpawns = Instance.new("Folder", map)
safehouseSpawns.Name = "Spawns_Test"
Instance.new("Part", safehouseSpawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 610))
local houseStand = Instance.new("Part", map.Stands) -- zweiter Waffenstand im Safehouse (gleicher Name)
houseStand.Name = "Stand_Weapons"
houseStand.CFrame = CFrame.new(CENTER + Vector3.new(-12, 2.5, 600))
local travelStop = Instance.new("Part", map.Stands)
travelStop.Name = "Travel"
travelStop.CFrame = CFrame.new(CENTER + Vector3.new(-36, 2.5, 16))
local spawnPoint = Instance.new("Part", map.Spawns)
spawnPoint.CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
local portal = Instance.new("Part", map.Portals)
portal.Name = "Portal_Hub"
portal.CFrame = CFrame.new(CENTER + Vector3.new(-62, 0.4, -32))
local standPos = {
	Stand_Weapons = CENTER + Vector3.new(-36, 2.5, 34),
	Stand_Items = CENTER + Vector3.new(36, 2.5, 34),
	Stand_Vehicles = CENTER + Vector3.new(-30, 2.5, -42),
	Stash = CENTER + Vector3.new(52, 2.5, -30),
}
for name, position in standPos do
	local part = Instance.new("Part", map.Stands)
	part.Name = name
	part.CFrame = CFrame.new(position)
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
InventoryService.Init()
LootService.Init()
local statusText = nil
local manager = {
	Join = function(player, modeId)
		if modeId ~= "Extinction" and player:GetAttribute("Mode") == "Extinction" then
			if Extinction.ConfirmLeave(player) then
				Extinction.RemovePlayer(player)
				player:SetAttribute("Mode", modeId)
			end
		end
	end,
	Status = function(_, text)
		statusText = text
	end,
}
require("ExtinctionConfig").Airdrop.FirstDelay = math.huge -- hier keine Lootdrops (eigener Test: airdrop)
require("ExtinctionConfig").Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
require("ExtinctionConfig").HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
require("ExtinctionConfig").Day.Fixed = 12 -- immer Tag (nachts mehr Zombies; eigener Test: daycycle)
require("ExtinctionConfig").Zombies.KindWeights = { Walker = 1 } -- nur normale Zombies (Schreier rufen sonst Verstärkung)
require("ExtinctionConfig").Bounty.Enabled = false
local D = ExtinctionConfig.Dungeon
D.StartDelay = 2
D.BreakTime = 3
D.SpawnEvery = 0.05
Extinction.Init(manager)
local DungeonService = require("DungeonService")
local ZombieService = require("ZombieService")

local function lastBanner(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "Notify" and entry.Player == player and entry.Args[1] == "Banner" then
			return entry.Args[2]
		end
	end
	return nil
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
local function enter(player)
	player:SetAttribute("Mode", "Extinction")
	Extinction.AddPlayer(player)
	step(0.3)
end
local function countIn(player, id)
	local n = 0
	for _, entry in HttpService:JSONDecode(player:GetAttribute("ExtBag") or "[]") do
		if entry.Id == id then
			n += entry.N or 1
		end
	end
	return n
end

-- ---------- Werte ----------
local w1, w5, w8 = ExtinctionConfig.DungeonWave(1, 1), ExtinctionConfig.DungeonWave(5, 1), ExtinctionConfig.DungeonWave(8, 1)
check(w5.Count > w1.Count and w8.Count > w5.Count, "jede Welle mehr Zombies (" .. w1.Count .. ", " .. w5.Count .. ", " .. w8.Count .. ")")
check(w8.Health > w1.Health and w5.Bosses == 1 and w1.Bosses == 0, "Wellen härter, jede 5. mit Blutbestie")
check(ExtinctionConfig.DungeonWave(3, 4).Count > ExtinctionConfig.DungeonWave(3, 1).Count, "mehr Spieler, mehr Zombies")
check(ExtinctionConfig.DungeonReward(6).Coins > ExtinctionConfig.DungeonReward(1).Coins, "spätere Wellen bringen mehr")
local key = ExtinctionConfig.Get(D.KeyItem)
check(key and key.Kind == "Key" and key.Price == nil and ExtinctionConfig.SellPrice(D.KeyItem, 1) > 0,
	"Schlüssel: nicht zu kaufen, aber verkäuflich")
check(D.KeyChances.Zombie == 0.05, "5 % bei normalen Zombies")
for _, source in { "Airdrop", "HeliCrash", "Horde", "Convoy", "Boss", "Storm" } do
	check((D.KeyChances[source] or 0) > 0, "Schlüssel auch aus " .. source)
end
check(#ExtinctionConfig.AddDungeonKey({}, "Gibtsnicht", Random.new(1)) == 0, "unbekannte Quelle: kein Schlüssel")

-- ---------- Eingänge ----------
local entrances = HttpService:JSONDecode(map:GetAttribute("Dungeons") or "[]")
check(#entrances == 1 and entrances[1].Title == D.Title, "Eingang auf der Karte (" .. #entrances .. ")")
local entrance = DungeonService.Entrances()[1]
local model = entrance and entrance.Model
local prompt = model and model:FindFirstChild("DungeonPrompt", true)
check(prompt ~= nil and prompt.ActionText ~= "" and prompt.Parent == gate, "Kapelle mit E-Aufforderung")
check(Extinction.InSafeZone(entrance.Position), "Eingang im Camp (Safe Zone)")
check((entrance.Exit.Position - gate.Position):Dot(gate.CFrame.LookVector) > 3, "Ausgang vor der Tür")

store.Data.u1 = { XP = {}, Coins = 1000, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
local bob = SIM.Join("Bob")
local carl = SIM.Join("Carl")
for _, player in { alice, bob, carl } do
	Instance.new("Backpack", player).Name = "Backpack"
end
step(2)
carl:SetAttribute("IsAdmin", true) -- Admins haben zum Testen Schlüssel dabei
for _, player in { alice, bob, carl } do
	enter(player)
end
check(countIn(carl, D.KeyItem) == D.TestKeys and countIn(alice, D.KeyItem) == 0, "Admin hat " .. D.TestKeys .. " Test-Schlüssel, andere keine")
local function goTo(player, offset)
	player.Character:PivotTo(CFrame.new(entrance.Position + offset))
end
goTo(alice, Vector3.new(0, 3, 0))
goTo(bob, Vector3.new(6, 3, 0))
goTo(carl, Vector3.new(-6, 3, 0))
step(5.5)
for _, player in { alice, bob, carl } do
	Instance.new("ForceField", player.Character) -- Zombies draußen sollen niemanden erledigen
end

-- ohne Schlüssel: nichts
prompt.Triggered:Fire(alice)
step(0.3)
check(DungeonService.RunOf(alice) == nil, "ohne Schlüssel kein Dungeon")
check(string.find(lastStatus(alice) or "", "Dungeon-Schlüssel", 1, true) ~= nil, "Hinweis: Schlüssel nötig")

-- mit Schlüssel: Alice und ihr Squad (Bob), nicht Carl
alice:SetAttribute("SquadId", 7)
bob:SetAttribute("SquadId", 7)
InventoryService.Give(alice, D.KeyItem, 2)
step(0.2)
prompt.Triggered:Fire(alice)
step(0.3)
local run = DungeonService.RunOf(alice)
check(run ~= nil and DungeonService.RunOf(bob) == run, "Alice und Bob im selben Dungeon")
check(DungeonService.RunOf(carl) == nil, "Carl (kein Squad) bleibt draußen")
check(countIn(alice, D.KeyItem) == 1, "ein Schlüssel verbraucht")
local hallY = run and run.Origin.Y or 0
check(math.abs(alice.Character.HumanoidRootPart.Position.Y - hallY) < 10 and math.abs(bob.Character.HumanoidRootPart.Position.Y - hallY) < 10,
	"beide in der Halle")
local state = HttpService:JSONDecode(alice:GetAttribute("Dungeon") or "{}")
check(state.S == "Start" and state.T == entrance.Title, "Anzeige: Countdown bis Welle 1")

-- Welle 1
step(D.StartDelay + 0.5)
check(run.State == "Wave" and run.Wave == 1, "Welle 1 läuft")
check(run.Hall.Prompt.Enabled == false, "Portal während der Welle zu")
step(2)
local spawned, marked = 0, 0
for zombie in run.Zombies do
	spawned += 1
	local info = ZombieService.Info(zombie)
	if info and info.Dungeon then
		marked += 1
	end
end
check(spawned > 0 and marked == spawned, "Zombies aus den Gittern (" .. spawned .. "), als Dungeon-Zombies markiert")
run.Hall.Prompt.Triggered:Fire(alice)
step(0.2)
check(DungeonService.RunOf(alice) == run, "Portal zu: kein Verlassen während der Welle")

-- alle erledigen, bis die Welle geschafft ist
for _ = 1, 40 do
	for zombie in run.Zombies do
		local humanoid = zombie:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end
	step(0.3)
	if run.State == "Break" then
		break
	end
end
check(run.State == "Break" and run.Hall.Prompt.Enabled, "Welle geschafft: Portal offen")
local member = run.Members[alice]
check(member and member.Cleared == 1 and member.Coins == ExtinctionConfig.DungeonReward(1).Coins and #member.Items > 0,
	"Beute für Welle 1 gesammelt")
check((lastBanner(alice) or {}).Title == "WELLE 1 GESCHAFFT", "Ansage: Welle geschafft")

-- Alice geht durchs Portal: Beute, vor der Kapelle
local coins = ProgressService.Get(alice).Coins
local logBefore = #SIM.RemoteLog
run.Hall.Prompt.Triggered:Fire(alice)
step(0.3)
check(DungeonService.RunOf(alice) == nil and alice:GetAttribute("Dungeon") == nil, "Alice ist raus")
check((alice.Character.HumanoidRootPart.Position - entrance.Exit.Position).Magnitude < 5, "Alice steht vor der Kapelle")
check(ProgressService.Get(alice).Coins >= coins + ExtinctionConfig.DungeonReward(1).Coins, "Münzen ausgezahlt")
local cleared = false -- (danach kann die Safe-Zone-Ansage kommen: der Ausgang liegt im Camp)
for i = logBefore + 1, #SIM.RemoteLog do
	local entry = SIM.RemoteLog[i]
	if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" and entry.Args[2].Title == "DUNGEON GESCHAFFT" then
		cleared = true
	end
end
check(cleared, "Ansage: Dungeon geschafft")
check(DungeonService.RunOf(bob) == run, "Bob bleibt drin")

-- nach der Pause: Welle 2
step(D.BreakTime + 0.5)
check(run.State == "Wave" and run.Wave == 2 and not run.Hall.Prompt.Enabled, "Pause vorbei: Welle 2, Portal zu")

-- Bob stirbt im Dungeon: Tasche weg (fällt nirgends), Halle abgebaut
InventoryService.Give(bob, "Bandage", 3)
step(0.2)
local hall = run.Model
bob.Character:FindFirstChildOfClass("ForceField"):Destroy()
bob.Character.Humanoid.Health = 0
step(0.5)
check(DungeonService.RunOf(bob) == nil, "Bob ist raus")
local bagNear = false
for _, bagModel in workspace.ExtinctionLoot:GetChildren() do
	local bagPart = bagModel:FindFirstChild("LootBag")
	if bagPart and (bagPart.Position - entrance.Exit.Position).Magnitude < 12 then
		bagNear = true
	end
end
check(not bagNear and bob:GetAttribute("ExtDeathBag") == nil, "keine Tasche vor der Kapelle")
check(countIn(bob, "Bandage") == 0, "Bobs Tasche ist weg")
check(hall.Parent == nil and next(DungeonService.Runs()) == nil, "leere Halle abgebaut")

-- ---------- Schlüssel bei Zombies ----------
D.KeyChances.Zombie = 1
local normal = ZombieService.Spawn(entrance.Position + Vector3.new(30, 0, 30), "Walker", true)
local info = normal and ZombieService.Info(normal)
normal:FindFirstChildOfClass("Humanoid").Health = 0
step(0.3)
local corpse = info and info.Corpse and LootService.Get(info.Corpse.LootId)
local found = false
for _, item in corpse and corpse.Container.Slots or {} do
	if item.Id == D.KeyItem then
		found = true
	end
end
check(found, "normaler Zombie: Schlüssel in der Leiche")
local inside = ZombieService.Spawn(entrance.Position + Vector3.new(-30, 0, 30), "Walker", true)
ZombieService.MarkDungeon(inside)
local insideInfo = ZombieService.Info(inside)
inside:FindFirstChildOfClass("Humanoid").Health = 0
step(0.3)
local insideCorpse = insideInfo and insideInfo.Corpse and LootService.Get(insideInfo.Corpse.LootId)
local insideKey = false
for _, item in insideCorpse and insideCorpse.Container.Slots or {} do
	if item.Id == D.KeyItem then
		insideKey = true
	end
end
check(not insideKey, "Dungeon-Zombie: nie ein Schlüssel")
D.KeyChances.Zombie = 0.05

if failures == 0 then
	print("Dungeons: alles in Ordnung")
end

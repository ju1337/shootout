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
require("ExtinctionConfig").Airdrop.FirstDelay = math.huge -- hier keine Lootdrops (eigener Test: airdrop)
require("ExtinctionConfig").Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
require("ExtinctionConfig").HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
require("ExtinctionConfig").Day.Fixed = 12 -- immer Tag (nachts mehr Zombies; eigener Test: daycycle)
require("ExtinctionConfig").Zombies.KindWeights = { Walker = 1 } -- nur normale Zombies (Schreier rufen sonst Verstärkung)
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
check(Z.PerPlayer <= 4 and Z.MaxTotal <= 36, "wenige Zombies: höchstens " .. Z.PerPlayer .. " pro Spieler")

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

-- Tod: wenige Münzen für den Schützen, die Beute steckt in der Leiche (kein Beutel am Boden). E öffnet das Beute-Fenster,
-- dort nimmt man einzeln heraus; alles auf einmal (F) nur mit dem Gamepass ALLES LOOTEN
local Inventory = require("Inventory")
local InventoryService = require("InventoryService")
local LootService = require("LootService")
ExtinctionConfig.ZombieKinds.Walker.Drop = 1
place(alice, Vector3.new(0, 3, -400))
step(0.5)
local coins = ProgressService.Get(alice).Coins
local accountXP = ProgressService.Get(alice).AccountXP or 0
local agentId = ProgressService.ActiveAgent(alice)
local agentXP = ProgressService.Get(alice).XP[agentId] or 0
local logStart = #SIM.RemoteLog
local bags = #workspace.ExtinctionLoot:GetChildren()
-- eigener Walker: die Art (und damit Drop) steht beim Spawnen fest, ungepanzert für die normalen Münzen
local victim = ZombieService.Spawn(alice.Character.HumanoidRootPart.Position + Vector3.new(0, -3, -20), "Walker", true, false)
local victimKind = ZombieService.Kind(victim:GetAttribute("ZombieKind"))
Damage.Apply(victim, victim.Humanoid, 1000, { Player = alice, Weapon = "Rifle" })
step(0.2)
check(ProgressService.Get(alice).Coins == coins + ExtinctionConfig.ZombieCoins, "Münzen für den Zombie (XP ohne Münzen): "
	.. ProgressService.Get(alice).Coins - coins)
check(victimKind.XP > 0 and (ProgressService.Get(alice).AccountXP or 0) == accountXP + victimKind.XP,
	"Zombie gibt XP fürs Spielerlevel: " .. (ProgressService.Get(alice).AccountXP or 0) - accountXP)
check((ProgressService.Get(alice).XP[agentId] or 0) == agentXP + victimKind.XP, "XP für den aktiven Agenten")
local xpShown = false
for i = logStart + 1, #SIM.RemoteLog do
	local entry = SIM.RemoteLog[i]
	xpShown = xpShown or (entry.Remote == "XPGain" and entry.Player == alice and entry.Args[1] == victimKind.XP)
end
check(xpShown, "+XP erscheint im HUD")
check(#workspace.ExtinctionLoot:GetChildren() == bags, "kein Beutel am Boden: die Beute steckt in der Leiche")
local prompt = victim.HumanoidRootPart:FindFirstChild("CorpsePrompt")
check(prompt ~= nil and prompt.ActionText == "Durchsuchen" and prompt.HoldDuration == 0,
	"Leiche mit Beute: einmal E (Durchsuchen, ohne Halten)")
check(victim.HumanoidRootPart:FindFirstChild("TakeAllPrompt") ~= nil, "F = alles nehmen (Gamepass)")
check(victim:FindFirstChild("LootHighlight") ~= nil, "Leiche mit Beute leuchtet kurz auf")
check(prompt and string.find(prompt.ObjectText, "Zombie", 1, true) ~= nil, "Prompt zeigt, was drinsteckt: " .. tostring(prompt and prompt.ObjectText))
step(6)
check(victim.Parent ~= nil, "Leiche mit Beute bleibt länger liegen als eine ohne")

local function countItems(player)
	local total = 0
	for _, entry in Inventory.Items(InventoryService.GetBag(player)) do
		total += entry.Count
	end
	return total
end
-- letztes Beute-Fenster, das der Server an den Spieler geschickt hat
local function lastLoot(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "ExtUpdate" and entry.Player == player and entry.Args[1] == "Loot" then
			return entry.Args[2], i
		end
	end
	return nil, 0
end
local lowTier = true
local before = countItems(alice)
-- zu weit weg: nichts passiert
place(alice, Vector3.new(60, 3, -400))
local _, logBefore = lastLoot(alice)
prompt.Triggered:Fire(alice)
local _, logAfter = lastLoot(alice)
check(countItems(alice) == before and prompt.Parent ~= nil and logAfter == logBefore, "zu weit weg: Leiche bleibt unberührt")
place(alice, Vector3.new(0, 3, -400))
victim:PivotTo(CFrame.new(alice.Character.HumanoidRootPart.Position + Vector3.new(0, 0, -2)))
prompt.Triggered:Fire(alice)
local loot = lastLoot(alice)
check(loot ~= nil and #loot.Items > 0 and countItems(alice) == before,
	"E an der Leiche: Beute-Fenster mit dem Inhalt, noch nichts genommen")
check(loot and loot.Title == "LEICHE · ZOMBIE", "Fenstertitel nennt die Leiche (" .. tostring(loot and loot.Title) .. ")")
-- ohne Gamepass nicht alles auf einmal (F öffnet nur das Fenster)
check(loot and LootService.Take(alice, loot.Id, "All") == false and countItems(alice) == before,
	"ohne Gamepass ALLES LOOTEN: nicht alles auf einmal")
victim.HumanoidRootPart.TakeAllPrompt.Triggered:Fire(alice)
check(countItems(alice) == before, "F ohne Gamepass nimmt nichts")
-- einzeln herausnehmen
for _, entry in loot and loot.Items or {} do
	LootService.Take(alice, loot.Id, entry.S)
end
local after = countItems(alice)
check(after > before, "einzeln herausgenommen: Beute im Inventar (" .. before .. " -> " .. after .. ")")
local allowed = {}
for _, entry in ExtinctionConfig.LootTables.Zombie do
	allowed[entry.Id] = true
end
for _, entry in Inventory.Items(InventoryService.GetBag(alice)) do
	if not allowed[entry.Id] then
		lowTier = false
	end
end
check(lowTier, "nur Beute aus der Zombie-Tabelle (einfach)")
check(victim.HumanoidRootPart:FindFirstChild("CorpsePrompt") == nil and victim:FindFirstChild("LootHighlight") == nil,
	"leer geräumt: kein Prompt, kein Leuchten")
step(2)
check(victim.Parent == nil, "durchsuchte Leiche verschwindet")

-- Tasche voll: Beute bleibt in der Leiche, später nehmen (mit Gamepass alles auf einmal)
ExtinctionConfig.ZombieKinds.Walker.Drop = 1
local second = ZombieService.Spawn(alice.Character.HumanoidRootPart.Position + Vector3.new(0, -3, -4))
Damage.Apply(second, second.Humanoid, 1000, { Player = alice, Weapon = "Rifle" })
step(0.2)
local fullBag = InventoryService.GetBag(alice)
local saved = Inventory.Clear(fullBag)
for slot = 1, fullBag.Size do
	fullBag.Slots[slot] = { Id = "Pistol", Count = 1, Mag = 0 }
end
alice:SetAttribute("Pass_LootAll", true) -- Gamepass ALLES LOOTEN
local corpsePrompt = second.HumanoidRootPart:FindFirstChild("CorpsePrompt")
local takeAllPrompt = second.HumanoidRootPart:FindFirstChild("TakeAllPrompt")
takeAllPrompt.Triggered:Fire(alice)
check(corpsePrompt.Parent ~= nil and second.Parent ~= nil, "Tasche voll: Beute bleibt in der Leiche")
local fullMessage = false
for _, entry in SIM.RemoteLog do
	if entry.Remote == "ExtUpdate" and entry.Player == alice and entry.Args[1] == "Status" and string.find(tostring(entry.Args[2]), "voll", 1, true) then
		fullMessage = true
	end
end
check(fullMessage, "Meldung: Tasche voll")
Inventory.Clear(fullBag)
takeAllPrompt.Triggered:Fire(alice)
check(countItems(alice) > 0, "mit Gamepass: F nimmt alles auf einmal")
step(2)
check(second.Parent == nil, "nach Platz schaffen: Beute genommen, Leiche weg")
alice:SetAttribute("Pass_LootAll", nil)
for _, item in saved do
	Inventory.Add(fullBag, item.Id, item.Count, { Mag = item.Mag })
end

-- Zombie ohne Beute: Leiche verschwindet schnell, kein Prompt
ExtinctionConfig.ZombieKinds.Walker.Drop = 0
local empty = ZombieService.Spawn(alice.Character.HumanoidRootPart.Position + Vector3.new(0, -3, -4))
Damage.Apply(empty, empty.Humanoid, 1000, { Player = alice, Weapon = "Rifle" })
step(0.2)
check(empty.HumanoidRootPart:FindFirstChild("CorpsePrompt") == nil, "ohne Beute kein Prompt")
step(Z.CorpseTime + 1)
check(empty.Parent == nil, "Leiche ohne Beute verschwindet nach CorpseTime")
ExtinctionConfig.ZombieKinds.Walker.Drop = 0.55

-- Arten: Läufer sind schneller, Brocken zäh und groß und schlagen hart; alle zusammen langsamer als Spieler
local walker = ZombieService.Kind("Walker")
local runner, brute = ZombieService.Kind("Runner"), ZombieService.Kind("Brute")
check(walker.Run < 16 * 0.6 and walker.Walk < 6, "normale Zombies sind langsam (Spieler laufen 16)")
check(runner.Run > walker.Run and brute.Health > walker.Health * 2.5 and brute.Damage > walker.Damage * 2 and brute.Scale > 1.2,
	"Läufer schneller, Brocken zäh und stark")
check(runner.Run < 16, "auch Läufer sind langsamer als ein rennender Spieler")
check(ZombieService.Kind("Quatsch").Id == "Walker", "unbekannte Art = Walker")
local bruteModel = ZombieService.Spawn(CENTER + Vector3.new(500, 0, 500), "Brute")
check(bruteModel ~= nil and bruteModel:GetAttribute("ZombieKind") == "Brute" and bruteModel.Humanoid.MaxHealth >= brute.Health * 0.8,
	"Brocken gespawnt mit seinen Werten")
bruteModel:Destroy()

-- Messer (V) gegen Zombies: Schaden, beim Tod nur die Zombie-Münzen, kein Spieler-Kill
local Remotes = require("Remotes")
local kills = 0
WeaponService.Killed:Connect(function()
	kills += 1
end)
local stabbed = ZombieService.Spawn(alice.Character.HumanoidRootPart.Position + Vector3.new(0, -3, -3))
SIM.SpherecastHandler = function()
	return { Instance = stabbed.Torso, Position = stabbed.Torso.Position, Normal = Vector3.new(0, 0, 1) }
end
coins = ProgressService.Get(alice).Coins
local head = alice.Character.Head
for _ = 1, 4 do
	Remotes.Melee.OnServerEvent:Fire(alice, head.Position, Vector3.new(0, 0, -1))
	step(1.2)
end
SIM.SpherecastHandler = nil
check(stabbed.Humanoid.Health <= 0, "Zombie mit dem Messer erledigt")
check(kills == 0, "Zombie zählt nicht als Spieler-Kill (" .. kills .. ")")
check(ProgressService.Get(alice).Coins == coins + ExtinctionConfig.ZombieCoins, "nur die Zombie-Münzen fürs Messer")

-- Obergrenze für den ganzen Server
Z.MaxTotal = ZombieService.Count() + 1
place(bob, Vector3.new(400, 3, 200))
step(Z.SpawnInterval * 10)
check(ZombieService.Count() <= Z.MaxTotal, "nicht mehr als MaxTotal Zombies")
Z.MaxTotal = ZombieService.Count()
check(ZombieService.Spawn(CENTER + Vector3.new(500, 0, 200)) == nil, "an der Obergrenze kein Spawn")
Z.MaxTotal = 30

-- Alle in der Safe Zone: nach kurzer Zeit verschwinden die Zombies (nicht sofort)
place(alice, Vector3.new(0, 3, 30))
place(bob, Vector3.new(0, 3, 40))
step(3)
check(ZombieService.Count() > 0, "Zombies verschwinden nicht sofort")
step(10)
check(ZombieService.Count() == 0, "ohne Spieler draußen in der Nähe verschwinden alle Zombies (" .. ZombieService.Count() .. ")")
check(downRays > 0, "Boden wird per Raycast gesucht")

-- Schreier: sieht er einen Spieler, jagen ihn alle Zombies im Umkreis und Verstärkung kommt
place(alice, Vector3.new(0, 3, -300))
step(0.5)
local walkerNear = ZombieService.Spawn(CENTER + Vector3.new(60, 0, -300), "Walker")
local before = ZombieService.Count()
local screamer = ZombieService.Spawn(CENTER + Vector3.new(15, 0, -300), "Screamer")
check(screamer ~= nil and screamer:GetAttribute("ZombieKind") == "Screamer", "Schreier gespawnt")
step(1)
check(ZombieService.Count() >= before + 1 + Z.ScreamCalls, "Schreier ruft Verstärkung (" .. ZombieService.Count() - before .. ")")
check(screamer and screamer:FindFirstChild("Blood") ~= nil, "Zombies haben Blutflecken")
print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

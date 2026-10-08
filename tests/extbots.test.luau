--!expose BotService isEnemy enemies
-- Bots in der offenen Welt (EXTINCTION) aus dem Admin-Panel: spawnen beim Admin (draußen in 25-45 Studs, in einer Safe Zone
-- gleich vor ihrem Rand, ohne Admin in der roten Zone), nie in einer Safe Zone; Ziele sind Spieler draußen (nicht in der
-- Safe Zone), nahe Zombies, keine anderen Bots; Zombies jagen und schlagen Bots; beim Tod eine Tasche mit Waffe, Munition
-- und Beute, Kopfgeld und Rangliste für den Schützen, die Leiche verschwindet; höchstens Max Bots; Admin-Befehle
-- SpawnBot/RemoveBots über das Panel
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
local Remotes = require("Remotes")
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
-- ein Ort für die rote Zone (Süden)
local place = Instance.new("Part", map.Places)
place.Name = "Place_Test"
place:SetAttribute("Title", "Testzone")
place.Size = Vector3.new(200, 4, 200)
place.CFrame = CFrame.new(CENTER + Vector3.new(0, 2, -700))

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
local RedzoneService = require("RedzoneService")
local RedzoneBoard = require("RedzoneBoard")
local BotService = require("BotService")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge -- hier keine Lootdrops
ExtinctionConfig.Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
ExtinctionConfig.HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0 -- Zombies nur, wo der Test sie hinstellt
ExtinctionConfig.Zombies.KindWeights = { Walker = 1 }
local B = ExtinctionConfig.Bots
local manager = { Join = function() end, Status = function() end }
Extinction.Init(manager)

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)
alice:SetAttribute("Mode", "Extinction")
Extinction.AddPlayer(alice)
step(0.5)

local function flat(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function place_(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
	step(0.3)
end
local function newBot(admin)
	local bot = BotService.Create("Extinction")
	local ok, reason = Extinction.AddBot(bot, nil, admin)
	step(0.6) -- Körper bauen
	return bot, ok, reason
end

-- ---------- Spawnen beim Admin ----------
check(B and B.Max >= 5 and B.SpawnMin < B.SpawnMax, "Bot-Einstellungen vorhanden")
place_(alice, Vector3.new(0, 3, 400)) -- draußen im Norden
local here = alice.Character.HumanoidRootPart.Position
local first, ok, reason = newBot(alice)
check(ok == true, "Bot in der offenen Welt gespawnt (" .. tostring(reason) .. ")")
check(first.Model ~= nil and first.Alive, "Bot hat ein Modell und lebt")
local spawned = first.Model and first.Model:GetPivot().Position
check(spawned ~= nil and flat(spawned, here) >= B.SpawnMin - 0.5 and flat(spawned, here) <= B.SpawnMax + 0.5,
	"Bot spawnt " .. B.SpawnMin .. "-" .. B.SpawnMax .. " Studs um den Admin (" .. (spawned and math.floor(flat(spawned, here)) or -1) .. ")")
check(spawned ~= nil and not Extinction.InSafeZone(spawned), "nicht in der Safe Zone")
check(spawned ~= nil and math.abs(spawned.Y - 3) < 0.5, "auf dem Boden (Höhe " .. tostring(spawned and spawned.Y) .. ")")
check(first.Team and first.Team.Name == "Banditen" and first.Model:GetAttribute("TeamName") == "Banditen", "Bots sind ein Team")
check(first.Model:GetAttribute("Mode") == "Extinction" and first.Model:GetAttribute("IsBot") == true, "Modell markiert")
local weaponItem = ExtinctionConfig.Get(first.ItemId)
check(weaponItem and weaponItem.Kind == "Weapon" and first.Weapon == weaponItem.Weapon, "Waffe aus der offenen Welt (" .. tostring(first.ItemId) .. ")")
check(first.Model:FindFirstChildOfClass("Tool") ~= nil and first.Model:FindFirstChildOfClass("Tool").Name ~= "", "Waffe in der Hand")
check(first.GadgetCharges == 0, "keine Gadgets in der offenen Welt")
check(first.Home and flat(first.Home, spawned) < 1, "Bot läuft um seinen Spawnpunkt herum")

-- Admin in der Safe Zone: Bot gleich vor dem Rand, in seiner Richtung (hier Osten)
place_(alice, Vector3.new(60, 3, 0))
local edgeBot = newBot(alice)
local edge = edgeBot.Model and edgeBot.Model:GetPivot().Position
check(edge ~= nil and not Extinction.InSafeZone(edge), "Admin in der Safe Zone: Bot draußen")
check(edge ~= nil and flat(edge, CENTER) >= 100 + B.SafeMargin - 15.5 and flat(edge, CENTER) <= 100 + B.SafeMargin + 15.5,
	"Bot vor dem Rand der Safe Zone (" .. (edge and math.floor(flat(edge, CENTER)) or -1) .. ")")
check(edge ~= nil and edge.X - CENTER.X > 80, "in Richtung des Admins (Osten)")

-- Ohne Admin in der offenen Welt: in der roten Zone
local red = RedzoneService.Current()
check(red ~= nil, "rote Zone steht")
local redBot = newBot(nil)
local redPos = redBot.Model and redBot.Model:GetPivot().Position
check(red and redPos and RedzoneService.At(redPos) ~= nil, "ohne Admin: Bot in der roten Zone")

-- ---------- Ziele ----------
local isEnemy, enemies = BotService.__isEnemy, BotService.__enemies
place_(alice, Vector3.new(0, 3, 400))
check(isEnemy(first, alice.Character) == true, "Spieler draußen ist ein Ziel")
place_(alice, Vector3.new(0, 3, 20))
check(alice.Character:GetAttribute("SafeZone") == true and isEnemy(first, alice.Character) == false,
	"Spieler in der Safe Zone ist kein Ziel")
check(isEnemy(first, edgeBot.Model) == false, "andere Bots sind keine Ziele")
local nearZombie = ZombieService.Spawn(spawned + Vector3.new(10, -3, 0), "Walker", true)
local farZombie = ZombieService.Spawn(spawned + Vector3.new(B.ZombieRange + 30, -3, 0), "Walker", true)
check(nearZombie ~= nil and farZombie ~= nil, "Zombies für den Test gespawnt")
local list = enemies(first)
check(table.find(list, nearZombie) ~= nil, "naher Zombie ist ein Ziel")
check(table.find(list, farZombie) == nil, "Zombie weit weg nicht")
check(table.find(list, alice.Character) == nil, "Alice in der Safe Zone nicht in der Zielliste")

-- Zombies jagen und schlagen Bots
local before = first.Model.Humanoid.Health
step(0.6)
local target = nearZombie.Humanoid.MoveToTarget
check(target ~= nil and flat(target, first.Model:GetPivot().Position) < 2, "Zombie läuft auf den Bot zu")
nearZombie:PivotTo(first.Model:GetPivot() * CFrame.new(0, 0, 3))
step(0.6)
check(first.Model.Humanoid.Health < before, "Zombie schlägt den Bot (" .. first.Model.Humanoid.Health .. ")")
nearZombie.Humanoid.Health = 0
farZombie.Humanoid.Health = 0
step(0.5)

-- ---------- Tod: Tasche, Kopfgeld, Rangliste ----------
local function bagsNear(position)
	local found = {}
	for _, model in workspace.ExtinctionLoot:GetChildren() do
		local part = model:FindFirstChild("LootBag")
		if part and flat(part.Position, position) < 6 and part:GetAttribute("Kind") == "Death" then
			table.insert(found, LootService.Get(part:GetAttribute("LootBag")))
		end
	end
	return found
end
place_(alice, Vector3.new(0, 3, 400))
local coins = ProgressService.Get(alice).Coins
local deathPos = first.Model:GetPivot().Position
Damage.Apply(first.Model, first.Model.Humanoid, 10000, { Player = alice, Weapon = "Rifle" })
step(0.5)
check(not first.Alive, "Bot tot")
local found = bagsNear(deathPos)
check(#found == 1, "eine Tasche, wo der Bot gestorben ist (" .. #found .. ")")
local bag = found[1]
if bag then
	check(string.find(bag.Title, first.Name, 1, true) ~= nil, "Tasche trägt den Namen des Bots: " .. bag.Title)
	local ids = {}
	for _, item in bag.Container.Slots do
		if item then
			ids[item.Id] = (ids[item.Id] or 0) + item.Count
		end
	end
	check(ids[first.ItemId] == 1, "seine Waffe liegt drin")
	local ammoId = ExtinctionConfig.AmmoFor(first.ItemId)
	check(ammoId ~= nil and (ids[ammoId] or 0) >= B.Ammo[1], "Munition dazu")
	local entries = 0
	for _ in ids do
		entries += 1
	end
	check(entries >= 2, "dazu Beute (" .. entries .. " Sorten)")
	-- Alice nimmt alles (E/F an der Tasche)
	alice.Character:PivotTo(CFrame.new(deathPos + Vector3.new(2, 0, 0)))
	step(0.2)
	alice:SetAttribute("Pass_LootAll", true) -- Gamepass ALLES LOOTEN
	check(LootService.Take(alice, bag.Id, "All") == true, "Alice plündert die Tasche des Bots")
	check(InventoryService.GetBag(alice) and require("Inventory").Count(InventoryService.GetBag(alice), first.ItemId) == 1,
		"Waffe des Bots in Alices Tasche")
end
check(ProgressService.Get(alice).Coins == coins + B.KillCoins, "Kopfgeld " .. B.KillCoins .. " Münzen ("
	.. ProgressService.Get(alice).Coins - coins .. ")")
check(#RedzoneBoard.List(red and red.Name or "?") == 0, "Kill außerhalb der roten Zone zählt nicht für die Rangliste")
step(B.CorpseTime + 1)
check(first.Model == nil and not table.find(Extinction.Bots(), first), "Leiche nach CorpseTime weg, Bot abgemeldet")
check(game:GetService("ReplicatedStorage").BotInfo:FindFirstChild(first.Name) == nil, "Bot-Info entfernt")

-- Kill in der roten Zone zählt für die Rangliste
local redRoot = redBot.Model.HumanoidRootPart.Position
alice.Character:PivotTo(CFrame.new(redRoot + Vector3.new(30, 0, 0)))
step(0.3)
Damage.Apply(redBot.Model, redBot.Model.Humanoid, 10000, { Player = alice, Weapon = "Rifle" })
step(0.5)
local board = RedzoneBoard.List(red.Name)
check(#board == 1 and board[1].Name == "Alice" and board[1].Kills == 1, "Bot-Kill in der roten Zone zählt für die Rangliste")
local redBag = bagsNear(redRoot)[1]
local tier3 = {}
for _, entry in ExtinctionConfig.LootTables[B.RedLootTable] do
	tier3[entry.Id] = true
end
local extraOk = redBag ~= nil
for _, item in redBag and redBag.Container.Slots or {} do
	if item and item.Id ~= redBot.ItemId and item.Id ~= ExtinctionConfig.AmmoFor(redBot.ItemId) and not tier3[item.Id] then
		extraOk = false
	end
end
check(extraOk, "Beute eines Bots in der roten Zone aus " .. B.RedLootTable)

-- Bot von einem Zombie erledigt: Tasche ja, Kopfgeld nein (Aufträge wie "Erkunde" können nebenbei Münzen geben,
-- darum zählt hier die Meldung)
local logStart = #SIM.RemoteLog
local zombieKill = ZombieService.Spawn(edge + Vector3.new(5, -3, 0), "Walker", true)
Damage.Apply(edgeBot.Model, edgeBot.Model.Humanoid, 10000, { Model = zombieKill, BotName = "Zombie", Weapon = "Zombie" })
step(0.5)
check(#bagsNear(edge) == 1, "Tasche auch nach Tod durch einen Zombie")
local bounty = false
for i = logStart + 1, #SIM.RemoteLog do
	local entry = SIM.RemoteLog[i]
	if entry.Remote == "ExtUpdate" and entry.Args[1] == "Status" and string.find(tostring(entry.Args[2]), edgeBot.Name, 1, true) then
		bounty = true
	end
end
check(not bounty, "kein Kopfgeld ohne Spieler als Schützen")

-- ---------- Obergrenze ----------
step(B.CorpseTime + 1)
local made = {}
for _ = 1, B.Max do
	local bot, added = newBot(nil)
	if added then
		table.insert(made, bot)
	else
		BotService.Destroy(bot)
	end
end
check(#Extinction.Bots() == B.Max, "höchstens " .. B.Max .. " Bots (" .. #Extinction.Bots() .. ")")
local extra = BotService.Create("Extinction")
local added, why = Extinction.AddBot(extra, nil, nil)
check(added == false and string.find(why or "", tostring(B.Max), 1, true) ~= nil, "über der Obergrenze: Meldung")
BotService.Destroy(extra)

-- ---------- Admin-Panel ----------
SIM.IsStudio = true
local AdminService = require("AdminService")
local modules = { Extinction = Extinction }
AdminService.Init({ GetModule = function(id)
	return modules[id]
end })
step(0.2)
check(alice:GetAttribute("IsAdmin") == true, "in Studio ist jeder Admin")
local function lastStatus()
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "AdminStatus" and entry.Player == alice then
			return entry.Args[1]
		end
	end
	return nil
end
Remotes.AdminAction.OnServerEvent:Fire(alice, "RemoveBots", "Extinction")
step(0.3)
check(#Extinction.Bots() == 0 and #BotService.All("Extinction") == 0, "RemoveBots räumt die offene Welt leer")
check(string.find(lastStatus() or "", "entfernt", 1, true) ~= nil, "Meldung im Panel: " .. tostring(lastStatus()))
place_(alice, Vector3.new(300, 3, 300))
Remotes.AdminAction.OnServerEvent:Fire(alice, "SpawnBot", "Extinction")
step(0.8)
local viaPanel = Extinction.Bots()[1]
check(viaPanel ~= nil and string.find(lastStatus() or "", "Extinction", 1, true) ~= nil, "SpawnBot über das Panel: "
	.. tostring(lastStatus()))
local panelPos = viaPanel and viaPanel.Model and viaPanel.Model:GetPivot().Position
check(panelPos ~= nil and flat(panelPos, alice.Character.HumanoidRootPart.Position) <= B.SpawnMax + 0.5,
	"Panel-Bot spawnt beim Admin")

-- Events der offenen Welt aus dem Panel
Remotes.AdminAction.OnServerEvent:Fire(alice, "ExtAirdrop", "Here")
step(0.3)
local AirdropService = require("AirdropService")
check(#AirdropService.Active() == 1 and string.find(lastStatus() or "", "Lootdrop gestartet", 1, true) ~= nil,
	"Lootdrop beim Admin: " .. tostring(lastStatus()))
Remotes.AdminAction.OnServerEvent:Fire(alice, "ExtAirdrop")
step(0.3)
check(string.find(lastStatus() or "", "schon", 1, true) ~= nil, "zweiter Lootdrop: Meldung " .. tostring(lastStatus()))
Remotes.AdminAction.OnServerEvent:Fire(alice, "ExtRedzone")
step(0.3)
check(string.find(lastStatus() or "", "Rote Zone", 1, true) ~= nil or string.find(lastStatus() or "", "Keine", 1, true) ~= nil,
	"Rote Zone weiter: " .. tostring(lastStatus()))
local ZombieService = require("ZombieService")
local before = ZombieService.Count()
Remotes.AdminAction.OnServerEvent:Fire(alice, "ExtHorde", 5)
step(0.3)
check(ZombieService.Count() >= before + 1 and string.find(lastStatus() or "", "Zombies", 1, true) ~= nil,
	"Zombie-Horde: " .. tostring(lastStatus()) .. " (" .. before .. " -> " .. ZombieService.Count() .. ")")
Remotes.AdminAction.OnServerEvent:Fire(alice, "ExtGive", "Throwables")
step(0.3)
check(string.find(lastStatus() or "", "Items", 1, true) ~= nil and string.find(alice:GetAttribute("ExtBag") or "", "Grenade", 1, true) ~= nil,
	"Granaten ins Inventar: " .. tostring(lastStatus()))
Remotes.AdminAction.OnServerEvent:Fire(alice, "ExtConvoy")
step(0.3)
check(string.find(lastStatus() or "", "Konvoi", 1, true) ~= nil, "Konvoi aus dem Panel: " .. tostring(lastStatus()))

if failures > 0 then
	error(failures .. " Fehler")
end
print("extbots: alles ok")

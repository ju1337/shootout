--!expose ActivityService roll
-- Bessere Beute in der roten Zone (ExtinctionConfig.Redzone.Loot): Tabelle eine Stufe besser, ein Item mehr, größere Stapel
-- (nie über MaxStack, Waffen einzeln); Zombies, die in der Zone sterben, haben immer Beute (Läufer-Tabelle statt normal) und
-- bringen doppelte Münzen, draußen nicht; Nester/Lager in der Zone mehr Items; Lootdrops landen öfter in der Zone und haben
-- dort mehr Items; zieht die Zone weiter, kommt kurz darauf ein Lootdrop in die neue Zone (nur mit Spielern draußen)
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
local L = ExtinctionConfig.Redzone.Loot
local A = ExtinctionConfig.Airdrop
A.FirstDelay, A.Warning, A.FallTime = math.huge, 6, 4
A.Escort = 0
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
local Damage = require("Damage")
ProgressService.Init()
WeaponService.Init()

-- ---------- Würfeln ----------
check(L ~= nil and L.DropBonus > 0 and L.ExtraItems >= 1 and L.StackFactor > 1 and L.CoinFactor > 1, "Boost-Werte vorhanden")
check(A.RedzoneChance >= 0.5, "Lootdrops landen meist in der roten Zone (" .. A.RedzoneChance .. ")")
local random = Random.new(7)
local better, extraOk, stackOk, maxOk = true, true, true, true
for _ = 1, 200 do
	local items = ExtinctionConfig.RedzoneRoll("Zombie", 1, random)
	local allowed = {}
	for _, row in ExtinctionConfig.LootTables[L.BetterTable.Zombie] do
		allowed[row.Id] = row
	end
	if #items ~= 1 + L.ExtraItems then
		extraOk = false
	end
	for _, item in items do
		local row = allowed[item.Id]
		if not row then
			better = false
		else
			local max = ExtinctionConfig.MaxStack(item.Id)
			if item.Count > max then
				maxOk = false
			end
			if max > 1 and item.Count < math.min(max, math.ceil(row.Count[1] * L.StackFactor)) then
				stackOk = false
			end
			if max <= 1 and item.Count ~= 1 then
				maxOk = false
			end
		end
	end
end
check(better, "rote Zone: Zombie-Beute aus " .. L.BetterTable.Zombie)
check(extraOk, "rote Zone: " .. L.ExtraItems .. " Item mehr")
check(stackOk, "rote Zone: größere Stapel")
check(maxOk, "Stapel nie über MaxStack, Waffen und Fahrzeuge einzeln")
local big = ExtinctionConfig.BigStacks({ { Id = "Ammo_9mm", Count = 200 }, { Id = "Rifle", Count = 1 } }, 2)
check(big[1].Count == ExtinctionConfig.MaxStack("Ammo_9mm") and big[2].Count == 1, "BigStacks: gedeckelt, Waffe bleibt 1")

-- ---------- Welt ----------
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
for key, info in { Sued = { "Südfeld", Vector3.new(0, 2, -600) }, Nord = { "Nordheim", Vector3.new(0, 2, 900) } } do
	local part = Instance.new("Part", map.Places)
	part.Name = "Place_" .. key
	part:SetAttribute("Title", info[1])
	part.Size = Vector3.new(200, 4, 200)
	part.CFrame = CFrame.new(CENTER + info[2])
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
local ZombieService = require("ZombieService")
local RedzoneService = require("RedzoneService")
local AirdropService = require("AirdropService")
local ActivityService = require("ActivityService")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0
ExtinctionConfig.Zombies.KindWeights = { Walker = 1 }
Extinction.Init({ Join = function() end, Status = function() end })

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)
alice:SetAttribute("Mode", "Extinction")
Extinction.AddPlayer(alice)
step(0.5)
local red = RedzoneService.MoveNow("Sued")
check(red and red.Key == "Sued", "rote Zone im Süden")
step(5) -- ohne Spieler draußen: kein Lootdrop beim Wechsel
check(#AirdropService.Active() == 0, "Wechsel ohne Spieler draußen: kein Lootdrop")

-- ---------- Zombies ----------
-- nur Münzen für Zombies zählen (erledigte Aufträge geben nebenbei auch welche)
local zombieCoins = 0
local addCoins = ProgressService.AddCoins
ProgressService.AddCoins = function(player, amount, reason)
	if reason == "Zombie" then
		zombieCoins += amount
	end
	return addCoins(player, amount, reason)
end
local walker = ExtinctionConfig.ZombieKinds.Walker
local function killZombie(offset)
	local before = zombieCoins
	local model = ZombieService.Spawn(CENTER + offset, "Walker", true, false) -- ungepanzert (die zählen doppelt)
	Damage.Apply(model, model.Humanoid, 10000, { Player = alice, Weapon = "Rifle" })
	step(0.2)
	local prompt = model:FindFirstChild("CorpsePrompt", true)
	return zombieCoins - before, prompt ~= nil, model
end
alice.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, -560)))
step(0.3)
local redCoins, redLoot = 0, 0
for i = 1, 12 do
	local coins, hasLoot = killZombie(Vector3.new(i * 3, 0, -600))
	redCoins += coins
	if hasLoot then
		redLoot += 1
	end
end
local outCoins, outLoot = 0, 0
alice.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 400)))
step(0.3)
for i = 1, 12 do
	local coins, hasLoot = killZombie(Vector3.new(i * 3, 0, 420))
	outCoins += coins
	if hasLoot then
		outLoot += 1
	end
end
check(redCoins == 12 * walker.Coins * L.CoinFactor, "rote Zone: " .. L.CoinFactor .. "× Münzen (" .. redCoins .. ")")
check(outCoins == 12 * walker.Coins, "draußen: normale Münzen (" .. outCoins .. ")")
if walker.Drop + L.DropBonus >= 1 then
	check(redLoot == 12, "rote Zone: jeder Zombie hat Beute (" .. redLoot .. "/12)")
end
check(redLoot >= outLoot, "rote Zone: nicht weniger Beute als draußen (" .. redLoot .. " zu " .. outLoot .. ")")
-- direkt gewürfelt: in der Zone aus der besseren Tabelle
local zombie2 = {}
for _, row in ExtinctionConfig.LootTables[L.BetterTable[walker.Table]] do
	zombie2[row.Id] = true
end
local stats = ZombieService.Kind("Walker")
local fromBetter = true
for _ = 1, 50 do
	for _, item in ZombieService.RollCorpseLoot(stats, false, true) do
		if not zombie2[item.Id] then
			fromBetter = false
		end
	end
end
check(fromBetter, "Leiche in der roten Zone: Beute aus " .. L.BetterTable[walker.Table])

-- ---------- Nester und Lager ----------
local roll = ActivityService.__roll
local cfg = ExtinctionConfig.Activities.Cache
local redCount, outCount = 0, 0
for _ = 1, 40 do
	redCount += #roll({ Position = red.Center }, cfg)
	outCount += #roll({ Position = CENTER + Vector3.new(0, 0, 400) }, cfg)
end
check(redCount > outCount, "Lager in der roten Zone: mehr Items (" .. redCount .. " zu " .. outCount .. ")")

-- ---------- Lootdrop in der Zone: mehr Items ----------
local function landedItems(drop)
	step(A.Warning + A.FallTime + 1)
	local bag = drop and drop.LootId and LootService.Get(drop.LootId)
	local n = 0
	for _ in bag and bag.Container.Slots or {} do
		n += 1
	end
	return n, bag
end
alice.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, -400)))
step(0.3)
local redDrop = AirdropService.Start(red.Center + Vector3.new(10, 0, 10))
check(redDrop and redDrop.Zone == red, "Lootdrop in der roten Zone")
local redItems, redBag = landedItems(redDrop)
local size = #ExtinctionConfig.LootTables.Airdrop
check(redItems >= math.min(A.Items[1] + L.ExtraItems + L.AirdropExtra, size), "Lootdrop in der roten Zone: mehr Items (" .. redItems .. ")")
if redBag then
	LootService.Remove(redBag.Id)
end
step(0.5)
check(#AirdropService.Active() == 0, "Lootdrop weg")

-- ---------- Wechsel: Lootdrop in die neue Zone ----------
local moved = RedzoneService.MoveNow("Nord")
check(moved and moved.Key == "Nord", "Zone zieht nach Norden")
step(1)
check(#AirdropService.Active() == 0, "Lootdrop erst kurz nach der Ansage des Wechsels")
step(4)
local drop = AirdropService.Active()[1]
check(drop ~= nil and drop.Zone == moved, "Wechsel: Lootdrop in der neuen roten Zone")
check(drop and Vector3.new(drop.Target.X - moved.Center.X, 0, drop.Target.Z - moved.Center.Z).Magnitude <= moved.Radius,
	"Landestelle in der Zone")
-- läuft schon ein Abwurf, kommt beim nächsten Wechsel keiner dazu
RedzoneService.MoveNow("Sued")
step(5)
check(#AirdropService.Active() == 1, "nie zwei Abwürfe gleichzeitig")

if failures > 0 then
	error(failures .. " Fehler")
end
print("redloot: alles ok")

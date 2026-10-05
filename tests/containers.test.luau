-- Lagerkisten der offenen Welt: je Teil Spot_<Art> eine Kiste mit Beute aus der Tabelle der Art, E/F nehmen die Beute,
-- leere Kisten füllen sich nach der Wartezeit neu, Kisten in roten Zonen ziehen aus Tier3, Kisten laufen nicht ab
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
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Redzones", "Loot" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))


local redzone = Instance.new("Part", map.Redzones)
redzone.Name = "Redzone_Test"
redzone.Size = Vector3.new(240, 40, 240)
redzone.CFrame = CFrame.new(CENTER + Vector3.new(0, 20, -500))

-- Spots: zwei Holzkisten (eine in der roten Zone), eine Sanikiste, eine Munitionskiste, eine Militärkiste, ein Fremdteil
local function spot(name, offset, yawDegrees)
	local part = Instance.new("Part", map.Loot)
	part.Name = name
	part.Size = Vector3.new(3, 2, 3)
	part.CFrame = CFrame.new(CENTER + offset + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(yawDegrees or 0), 0)
	return part
end
spot("Spot_Wood", Vector3.new(0, 0, -300), 30)
spot("Spot_Wood", Vector3.new(10, 0, -500)) -- in der roten Zone
spot("Spot_Medical", Vector3.new(30, 0, -300))
spot("Spot_Ammo", Vector3.new(40, 0, -300))
spot("Spot_Military", Vector3.new(50, 0, -300))
spot("Irgendwas", Vector3.new(60, 0, -300))
spot("Spot_Unbekannt", Vector3.new(70, 0, -300))

local ground = Instance.new("Part", workspace)
ground.Name = "Ground"
SIM.RaycastHandler = function(origin, direction)
	if direction.Y >= 0 then
		return nil
	end
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground, Material = Enum.Material.Grass }
end

local Inventory = require("Inventory")
local InventoryService = require("InventoryService")
local LootService = require("LootService")
local ContainerService = require("ContainerService")
local RedzoneService = require("RedzoneService")
InventoryService.Init()
LootService.Init()
RedzoneService.Init(map)
-- Standard: abgeschaltet (keine Beute am Boden) – dann entsteht keine einzige Kiste
ContainerService.Init(map, { RedzoneAt = RedzoneService.At })
check(#ContainerService.Spots() == 0, "Kisten sind standardmäßig aus")
ExtinctionConfig.Containers.Enabled = true
ContainerService.Init(map, { RedzoneAt = RedzoneService.At })

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)
alice:SetAttribute("Mode", "Extinction")
local rig = SIM.MakeRig("Alice")
rig.Parent = workspace
alice.Character = rig
InventoryService.Enter(alice)
local function place(position)
	alice.Character:PivotTo(CFrame.new(CENTER + position))
end

-- Kisten stehen an den Spots (nur gültige Arten)
local spots = ContainerService.Spots()
check(#spots == 5, "fünf Spots mit gültiger Art (" .. #spots .. ")")
local crates = workspace.ExtinctionLoot:GetChildren()
check(#crates == 5, "fünf Kisten in der Welt (" .. #crates .. ")")
local byKind = {}
for _, entry in spots do
	local bag = LootService.Get(entry.Id)
	check(bag ~= nil and bag.Kind == "Crate", "Spot " .. entry.Kind .. " hat eine Kiste")
	byKind[#byKind + 1] = { Spot = entry, Bag = bag }
	check((bag.Part.Position - entry.Part.Position).Magnitude < 1.5, entry.Kind .. ": Kiste steht am Spot")
	local kind = ExtinctionConfig.Containers.Kinds[entry.Kind]
	check(bag.Title == kind.Name, entry.Kind .. ": Titel " .. kind.Name)
	local n = 0
	for _, item in bag.Container.Slots do
		n += 1
		local allowed = false
		for _, row in ExtinctionConfig.LootTables[entry.Redzone and entry.Kind ~= "Medical" and entry.Kind ~= "Ammo" and "Tier3" or kind.Table] do
			if row.Id == item.Id then
				allowed = true
			end
		end
		check(allowed, entry.Kind .. ": " .. item.Id .. " gehört in die Tabelle")
	end
	check(n >= kind.Items[1] and n <= kind.Items[2], entry.Kind .. ": " .. n .. " Items")
	check(bag.Expires == math.huge, entry.Kind .. ": Kiste läuft nicht ab")
	check(bag.Part:FindFirstChild("LootPrompt") ~= nil and bag.Part:FindFirstChild("TakeAllPrompt") ~= nil, entry.Kind .. ": Prompts E und F")
end
local redSpot = nil
for _, entry in spots do
	if entry.Redzone then
		redSpot = entry
	end
end
check(redSpot ~= nil and redSpot.Kind == "Wood", "der Spot in der roten Zone ist als solcher erkannt")

-- Kiste durchsuchen und leeren: Respawn nach der Wartezeit mit neuer Beute
local first = spots[1]
local bag = LootService.Get(first.Id)
place(Vector3.new(0, 3, -300))
local oldId = first.Id
local itemCount = 0
for _, item in bag.Container.Slots do
	itemCount += item.Count
end
check(LootService.Take(alice, oldId, "All") == true, "alles aus der Kiste genommen")
local owned = 0
for _, entry in Inventory.Items(InventoryService.GetBag(alice)) do
	owned += entry.Count
end
check(owned == itemCount, "alle Items im Inventar (" .. owned .. " von " .. itemCount .. ")")
check(LootService.Get(oldId) == nil and first.Id == nil, "leere Kiste ist weg")
check(workspace.ExtinctionLoot:FindFirstChild("Loot_" .. oldId) == nil, "Modell entfernt")
step(ExtinctionConfig.Containers.Respawn * 0.7)
check(first.Id == nil, "noch nicht neu gefüllt")
step(ExtinctionConfig.Containers.Respawn * 0.6)
check(first.Id ~= nil and first.Id ~= oldId and LootService.Get(first.Id) ~= nil, "nach der Wartezeit neu gefüllt")

-- teilweise genommen: bleibt, kein Respawn-Wechsel
local partial = LootService.Get(spots[3].Id)
local slots = 0
for slot, _ in partial.Container.Slots do
	slots += 1
end
place(Vector3.new(40, 3, -300))
local partialId = spots[3].Id
if slots >= 2 then
	LootService.Take(alice, partialId, 1)
	check(spots[3].Id == partialId and LootService.Get(partialId) ~= nil, "teilweise geleerte Kiste bleibt")
else
	check(true, "nur ein Item")
end

-- zu weit weg
place(Vector3.new(0, 3, -100))
check(LootService.Take(alice, spots[4].Id, "All") == false, "zu weit weg: nichts genommen")

-- Kisten laufen nicht ab (länger als die Todestasche)
step(ExtinctionConfig.BagLifetime + 60)
check(LootService.Get(spots[4].Id) ~= nil, "Kiste ist nach " .. (ExtinctionConfig.BagLifetime + 60) .. " s noch da")

-- Rote Zone: Tier3-Beute
local tier3 = {}
for _, row in ExtinctionConfig.LootTables.Tier3 do
	tier3[row.Id] = true
end
local redOk = true
for _ = 1, 40 do
	local fresh = ExtinctionConfig.RollLoot("Tier3", 2, Random.new())
	for _, item in fresh do
		if not tier3[item.Id] then
			redOk = false
		end
	end
end
check(redOk, "RollLoot liefert nur Einträge der Tabelle")
check(#ExtinctionConfig.RollLoot("Gibtsnicht", 3) == 0, "unbekannte Tabelle: nichts")
local rolled = ExtinctionConfig.RollLoot("Airdrop", 99, Random.new(3))
local seenIds = {}
local distinct = true
for _, item in rolled do
	if seenIds[item.Id] then
		distinct = false
	end
	seenIds[item.Id] = true
end
check(distinct and #rolled == #ExtinctionConfig.LootTables.Airdrop, "ohne denselben Eintrag zweimal, höchstens so viele wie die Tabelle hat")

if failures == 0 then
	print("Lagerkisten: alles in Ordnung")
end

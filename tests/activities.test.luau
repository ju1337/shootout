-- Aktivitäten der offenen Welt (ActivityService): Zombienest spawnt Zombies und belohnt beim Zerstören, Vorratslager
-- aufbrechen (Lärm lockt Zombies, Beute ins Inventar, danach leer bis zum Respawn), Funkgerät fordert einen Lootdrop an
-- (Abklingzeit), Überlebende retten; Horden gibt es nicht mehr (alte Punkte Act_Horde werden ignoriert); alles steht im
-- Karten-Attribut Activities
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
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Activities" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))


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
marker("Act_Horde", Vector3.new(0, 0, 500), "Testdorf") -- alter Horden-Punkt einer Karte: wird ignoriert
marker("Act_Survivor", Vector3.new(0, 0, -170), "Testhaus")
marker("Act_Survivor", Vector3.new(250, 0, -250), "Testhof")

local ground = Instance.new("Part", workspace)
ground.Name = "Ground"
SIM.RaycastHandler = function(origin, direction)
	if direction.Y >= 0 then
		return nil
	end
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground }
end

local A = ExtinctionConfig.Activities
local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local ZombieService = require("ZombieService")
local ActivityService = require("ActivityService")
local AirdropService = require("AirdropService")
local HttpService = game:GetService("HttpService")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge -- nur der Notruf startet einen Lootdrop
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
local function bagCount()
	local n = 0
	for _, item in InventoryService.GetBag(alice).Slots do
		n += item.Count
	end
	return n
end
local function banner(title)
	for _, entry in SIM.RemoteLog do
		if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" and entry.Args[2].Title == title then
			return true
		end
	end
	return false
end
local function spotOf(kind)
	for _, spot in ActivityService.Spots() do
		if spot.Kind == kind then
			return spot
		end
	end
	return nil
end
local function published()
	local ok, list = pcall(HttpService.JSONDecode, HttpService, map:GetAttribute("Activities") or "[]")
	return ok and list or {}
end

-- Aufbau: Modelle in der Welt, alles im Karten-Attribut
local folder = workspace:FindFirstChild("ExtinctionActivities")
check(folder ~= nil and folder:FindFirstChild("ZombieNest") and folder:FindFirstChild("SupplyCache") and folder:FindFirstChild("RadioStation"),
	"Nest, Vorratslager und Funkgerät stehen in der Welt")
check(#published() == 5, "fünf Aktivitäten im Karten-Attribut, ohne Horde (" .. #published() .. ")")

-- Zombienest: Spieler in der Nähe -> Zombies kriechen heraus
local nest = spotOf("Nest")
place(Vector3.new(0, 0, -340))
step(A.Nest.SpawnEvery * 2 + 2)
local nearNest = 0
for _, model in ZombieService.All() do
	if (model:GetPivot().Position - nest.Position).Magnitude <= A.Nest.SpawnMax + 6 then
		nearNest += 1
	end
end
check(nearNest >= 1 and nearNest <= A.Nest.MaxAround, "Zombies kommen aus dem Nest (" .. nearNest .. ")")
local coins = ProgressService.Get(alice).Coins
local before = bagCount()
local nestModel = nest.Model
check(nestModel and nestModel:FindFirstChild("Head") and nestModel:FindFirstChild("Head").Material == Enum.Material.Neon, "Nest hat einen leuchtenden Kern")
Damage.Apply(nestModel, nest.Humanoid, A.Nest.Health + 10, { Player = alice, Weapon = "Test" })
step(1)
check(nest.State == "Cleared", "Nest zerstört")
check(ProgressService.Get(alice).Coins >= coins + A.Nest.Coins, "Münzen für das Nest")
check(bagCount() > before, "Beute vom Nest direkt im Inventar")
check(banner("ZOMBIENEST ZERSTÖRT"), "Meldung ZOMBIENEST ZERSTÖRT")
step(A.Nest.Respawn + 2)
check(nest.State == "Active" and nest.Model ~= nil and nest.Model ~= nestModel, "Nest wächst nach")

-- Vorratslager: E halten, Lärm, Beute, danach leer
local cache = spotOf("Cache")
check(cache.Prompt and cache.Prompt.HoldDuration == A.Cache.HoldTime, "Lager: E halten (" .. A.Cache.HoldTime .. " s)")
check(ActivityService.OpenCache(alice, cache) == false, "zu weit weg zum Aufbrechen")
place(Vector3.new(400, 0, -6))
step(1)
local zombiesBefore = ZombieService.Count()
before = bagCount()
check(ActivityService.OpenCache(alice, cache) == true, "Lager aufgebrochen")
check(bagCount() > before, "Beute aus dem Lager im Inventar")
check(ZombieService.Count() > zombiesBefore, "Lärm lockt Zombies an")
check(cache.State == "Opened" and not cache.Prompt.Enabled, "Lager danach leer")
check(ActivityService.OpenCache(alice, cache) == false, "leeres Lager nicht nochmal")
step(A.Cache.Respawn + 2)
check(cache.State == "Ready" and cache.Prompt.Enabled, "Lager füllt sich wieder")

-- Funkgerät: Notruf startet einen Lootdrop, dann Abklingzeit
local radio = spotOf("Radio")
place(Vector3.new(-400, 0, -6))
step(1)
check(#AirdropService.Active() == 0, "vorher kein Lootdrop")
check(ActivityService.UseRadio(alice, radio) == true and #AirdropService.Active() == 1, "Notruf startet einen Lootdrop")
check(radio.State == "Cooldown" and banner("NOTRUF EMPFANGEN"), "Funkgerät lädt, Meldung an alle")
check(ActivityService.UseRadio(alice, radio) == false, "kein zweiter Notruf während der Abklingzeit")

-- Keine Horden: der alte Punkt Act_Horde wird ignoriert, auch nach langer Zeit zieht keine Horde los
place(Vector3.new(0, 0, 470))
step(30)
local hordeSpots, hordeEntries = 0, 0
for _, spot in ActivityService.Spots() do
	if spot.Kind == "Horde" then
		hordeSpots += 1
	end
end
for _, entry in published() do
	if entry.Kind == "Horde" then
		hordeEntries += 1
	end
end
check(hordeSpots == 0 and hordeEntries == 0 and ActivityService.StartHorde == nil and not banner("HORDE IM ANMARSCH"),
	"keine Horden mehr")
check(A.Horde == nil, "keine Horden-Werte in der Konfiguration")
for _, def in ExtinctionConfig.Missions.Pool do
	check(def.Event ~= "Horde", "kein Horden-Auftrag")
end

-- Überlebender: E halten, er folgt, in der Safe Zone gerettet
local survivors = {}
for _, spot in ActivityService.Spots() do
	if spot.Kind == "Survivor" then
		table.insert(survivors, spot)
	end
end
local survivor = survivors[1]
check(survivor and survivor.Model and survivor.Model:FindFirstChildOfClass("Humanoid") and survivor.Prompt.HoldDuration == A.Survivor.HoldTime,
	"Überlebender wartet mit E-Aufforderung")
place(Vector3.new(0, 0, -160))
step(1)
check(ActivityService.Rescue(alice, survivor) == true and survivor.State == "Following", "Rettung beginnt, er folgt")
step(0.6)
local escortEntry = nil
for _, entry in published() do
	if entry.Id == survivor.Id then
		escortEntry = entry
	end
end
check(escortEntry and escortEntry.Escort == alice.UserId, "Karte: Begleiter steht dabei (nur er bekommt den Marker)")
coins = ProgressService.Get(alice).Coins
for z = -140, -20, 15 do
	place(Vector3.new(0, 0, z))
	-- der Simulator bewegt Humanoide nicht (MoveTo): Laufen des Überlebenden nachstellen
	if survivor.Model then
		survivor.Model:PivotTo(CFrame.new(CENTER + Vector3.new(4, 3, z - 5)))
	end
	step(1.5)
end
step(3)
check(survivor.State == "Gone" and banner("ÜBERLEBENDER GERETTET"), "in der Safe Zone gerettet")
check(ProgressService.Get(alice).Coins >= coins + A.Survivor.Coins, "Münzen für die Rettung")
-- zweiter Überlebender: zurückgelassen = gescheitert
local other = survivors[2]
place(Vector3.new(250, 0, -240))
step(1)
check(ActivityService.Rescue(alice, other) == true, "zweite Rettung beginnt")
place(Vector3.new(-300, 0, 300))
step(2)
check(other.State == "Gone" and banner("RETTUNG GESCHEITERT"), "zurückgelassen = gescheitert")
step(A.Survivor.Respawn + 2)
check(other.State == "Ready" and other.Model ~= nil, "Überlebender kommt später wieder")
print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

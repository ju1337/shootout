-- ExtinctionConfig (ModuleScript)
-- Alles für den Modus EXTINCTION (offene Welt): Items mit Preisen, Stände, Inventar-Größen, Safe Zone, PvP,
-- Zombies, Belohnungen und Fahrzeuge. Server (InventoryService, LootService, ZombieService, VehicleService,
-- Modes/Extinction) und Client (ExtinctionClient) lesen dieselben Werte.
--
-- Items (Kind):
--   "Weapon"  Waffe aus WeaponConfig (Weapon), braucht Munition (Ammo); Magazin steht am Item
--   "Ammo"    Munition einer Sorte, stapelbar; ein Kauf gibt Pack Schuss
--   "Heal"    Leben auffüllen (Heal), dauert UseTime Sekunden
--   "Armor"   Rüstung (Attribut "Armor", höchstens MaxArmor), dauert UseTime Sekunden
--   "Vehicle" Fahrzeug aus Vehicles (Vehicle); Taste spawnt es und setzt einen hinein, K packt es wieder ein
-- Price = Kaufpreis in Münzen (nil = nicht zu kaufen, nur zu finden). Verkaufen bringt SellFactor des Preises.

local ExtinctionConfig = {}

ExtinctionConfig.ModeId = "Extinction"
ExtinctionConfig.WorldSize = 1800    -- Kantenlänge der Welt in Studs (EXTINCTION_SIZE in tools/build_maps.py)

-- ---------- Inventar ----------
ExtinctionConfig.HotbarSlots = 9     -- Plätze 1-9 = Tasten 1-9
ExtinctionConfig.BagSlots = 30       -- Tasche gesamt (inkl. Hotbar)
ExtinctionConfig.StashSlots = 40     -- Lager in der Safe Zone (immer sicher)
ExtinctionConfig.StandRange = 14     -- so nah muss man am Stand/Lager sein (Studs)
ExtinctionConfig.SellFactor = 0.4    -- Verkauf: Anteil vom Kaufpreis
ExtinctionConfig.MaxArmor = 100

-- ---------- Safe Zone und PvP ----------
ExtinctionConfig.PvPDelay = 5        -- Sekunden nach dem Verlassen der Safe Zone, bis PvP gilt
ExtinctionConfig.RespawnTime = 5     -- nach dem Tod: Respawn in der Safe Zone
ExtinctionConfig.LeaveConfirmTime = 6 -- Verlassen außerhalb der Safe Zone: zweimal klicken innerhalb dieser Zeit

-- ---------- Belohnungen (Münzen) ----------
ExtinctionConfig.ZombieCoins = 2     -- pro Zombie (sehr wenig)
ExtinctionConfig.PlayerKillCoins = 120 -- pro getötetem Spieler (zusätzlich zum normalen Kill-Lohn)

-- ---------- Taschen (Tod, Verlassen, Zombie-Beute) ----------
ExtinctionConfig.BagLifetime = 300   -- Todestasche bleibt 5 Minuten liegen
ExtinctionConfig.DropLifetime = 90   -- Beutel von Zombies
ExtinctionConfig.LootRange = 10      -- so nah muss man an einer Tasche sein (Studs)

-- ---------- Fahrzeuge ----------
ExtinctionConfig.VehicleCooldown = 8 -- nach dem Einpacken (K) so lange warten bis zum nächsten Spawn
ExtinctionConfig.VehicleStoreRange = 30 -- K wirkt, solange man so nah an seinem Fahrzeug ist (oder drin sitzt)

-- Fahrzeuge: Tempo (Studs/s), Beschleunigung, Lenkung (Grad/s), Leben, Größe des Rumpfs, Farbe, Sitze
ExtinctionConfig.Vehicles = {
	Bicycle = { Name = "Fahrrad", Tier = 0, Speed = 34, Accel = 22, Turn = 120, Health = 80, Kind = "Bike",
		Size = Vector3.new(1.4, 1.6, 5.6), Color = Color3.fromRGB(70, 140, 200), Seats = 1 },
	Quad = { Name = "Quad", Tier = 1, Speed = 58, Accel = 34, Turn = 105, Health = 220, Kind = "Quad",
		Size = Vector3.new(4.6, 2.0, 6.6), Color = Color3.fromRGB(196, 120, 50), Seats = 1 },
	Pickup = { Name = "Geländewagen", Tier = 2, Speed = 72, Accel = 30, Turn = 80, Health = 600, Kind = "Car",
		Size = Vector3.new(6.4, 2.6, 12.5), Color = Color3.fromRGB(86, 104, 70), Seats = 4 },
	Sports = { Name = "Sportwagen", Tier = 3, Speed = 110, Accel = 46, Turn = 85, Health = 380, Kind = "Car",
		Size = Vector3.new(6.2, 1.9, 12), Color = Color3.fromRGB(200, 40, 40), Seats = 2 },
}

-- ---------- Items ----------
ExtinctionConfig.Items = {
	-- Waffen (Magazin startet voll; Munition extra kaufen)
	Pistol = { Kind = "Weapon", Name = "Pistole", Weapon = "Pistol", Ammo = "Ammo_9mm", Price = 120, Tier = 1 },
	Revolver = { Kind = "Weapon", Name = "Revolver", Weapon = "Revolver", Ammo = "Ammo_Magnum", Price = 350, Tier = 2 },
	SMG = { Kind = "Weapon", Name = "MP", Weapon = "SMG", Ammo = "Ammo_9mm", Price = 550, Tier = 2 },
	Shotgun = { Kind = "Weapon", Name = "Schrotflinte", Weapon = "Shotgun", Ammo = "Ammo_Shell", Price = 650, Tier = 2 },
	Rifle = { Kind = "Weapon", Name = "Sturmgewehr", Weapon = "Rifle", Ammo = "Ammo_Rifle", Price = 1100, Tier = 3 },
	DMR = { Kind = "Weapon", Name = "Präzisionsgewehr", Weapon = "DMR", Ammo = "Ammo_Rifle", Price = 1400, Tier = 3 },
	LMG = { Kind = "Weapon", Name = "LMG", Weapon = "LMG", Ammo = "Ammo_Rifle", Price = 2000, Tier = 4 },
	-- Munition
	Ammo_9mm = { Kind = "Ammo", Name = "9mm-Munition", Price = 30, Pack = 30, MaxStack = 240, Tier = 1 },
	Ammo_Magnum = { Kind = "Ammo", Name = "Magnum-Munition", Price = 45, Pack = 12, MaxStack = 96, Tier = 2 },
	Ammo_Shell = { Kind = "Ammo", Name = "Schrotpatronen", Price = 40, Pack = 12, MaxStack = 96, Tier = 2 },
	Ammo_Rifle = { Kind = "Ammo", Name = "Gewehrmunition", Price = 60, Pack = 30, MaxStack = 300, Tier = 3 },
	-- Heilung und Rüstung
	Bandage = { Kind = "Heal", Name = "Verband", Heal = 20, UseTime = 2.5, Price = 25, MaxStack = 10, Tier = 1 },
	Medkit = { Kind = "Heal", Name = "Medikit", Heal = 75, UseTime = 6, Price = 110, MaxStack = 5, Tier = 2 },
	Adrenaline = { Kind = "Heal", Name = "Adrenalin", Heal = 40, UseTime = 1.2, Price = 180, MaxStack = 3, Tier = 3,
		Speed = 1.25, SpeedTime = 6 },
	Vest = { Kind = "Armor", Name = "Schutzweste", Armor = 50, UseTime = 3, Price = 220, MaxStack = 3, Tier = 2 },
	HeavyVest = { Kind = "Armor", Name = "Schwere Weste", Armor = 100, UseTime = 5, Price = 550, MaxStack = 2, Tier = 3 },
	-- Fahrzeuge (Fahrrad gibt es nur bei Zombies)
	V_Bicycle = { Kind = "Vehicle", Name = "Fahrrad", Vehicle = "Bicycle", Tier = 0 },
	V_Quad = { Kind = "Vehicle", Name = "Quad", Vehicle = "Quad", Price = 900, Tier = 1 },
	V_Pickup = { Kind = "Vehicle", Name = "Geländewagen", Vehicle = "Pickup", Price = 2600, Tier = 2 },
	V_Sports = { Kind = "Vehicle", Name = "Sportwagen", Vehicle = "Sports", Price = 5200, Tier = 3 },
}

-- Was die Stände verkaufen (Reihenfolge = Anzeige). Verkaufen kann man an jedem Stand alles.
ExtinctionConfig.Stands = {
	Stand_Weapons = { Title = "WAFFENSTAND", Items = { "Pistol", "Revolver", "SMG", "Shotgun", "Rifle", "DMR", "LMG",
		"Ammo_9mm", "Ammo_Magnum", "Ammo_Shell", "Ammo_Rifle" } },
	Stand_Items = { Title = "ITEMSTAND", Items = { "Bandage", "Medkit", "Adrenaline", "Vest", "HeavyVest" } },
	Stand_Vehicles = { Title = "FAHRZEUGSTAND", Items = { "V_Quad", "V_Pickup", "V_Sports" } },
}

-- ---------- Beute-Tabellen ----------
-- Gewichtete Listen { Id, Count = { min, max }, Weight }. Gezogen wird mit ExtinctionConfig.RollLoot(Tabelle, Anzahl).
-- Zombie / Zombie2 = Leichen (einfach), Tier1-3 = Kisten in der Welt (3 = Militär und rote Zonen), Medical = Sanikisten,
-- Ammo = Munitionskisten, Airdrop = Versorgungsabwürfe (das Beste).
ExtinctionConfig.LootTables = {
	Zombie = {
		{ Id = "Bandage", Count = { 1, 2 }, Weight = 36 },
		{ Id = "Ammo_9mm", Count = { 8, 20 }, Weight = 24 },
		{ Id = "Ammo_Shell", Count = { 3, 6 }, Weight = 8 },
		{ Id = "Ammo_Rifle", Count = { 6, 15 }, Weight = 8 },
		{ Id = "Medkit", Count = { 1, 1 }, Weight = 6 },
		{ Id = "Pistol", Count = { 1, 1 }, Weight = 4 },
		{ Id = "V_Bicycle", Count = { 1, 1 }, Weight = 4 },
		{ Id = "V_Quad", Count = { 1, 1 }, Weight = 1 },
	},
	Zombie2 = { -- Läufer in roten Zonen: etwas besser
		{ Id = "Bandage", Count = { 2, 3 }, Weight = 24 },
		{ Id = "Ammo_9mm", Count = { 14, 30 }, Weight = 20 },
		{ Id = "Ammo_Rifle", Count = { 10, 24 }, Weight = 14 },
		{ Id = "Ammo_Shell", Count = { 5, 10 }, Weight = 10 },
		{ Id = "Medkit", Count = { 1, 1 }, Weight = 12 },
		{ Id = "Vest", Count = { 1, 1 }, Weight = 8 },
		{ Id = "Pistol", Count = { 1, 1 }, Weight = 5 },
		{ Id = "Revolver", Count = { 1, 1 }, Weight = 4 },
		{ Id = "V_Quad", Count = { 1, 1 }, Weight = 3 },
	},
	Tier1 = { -- Häuser, Hinterhöfe
		{ Id = "Bandage", Count = { 1, 2 }, Weight = 30 },
		{ Id = "Ammo_9mm", Count = { 10, 24 }, Weight = 26 },
		{ Id = "Ammo_Magnum", Count = { 6, 12 }, Weight = 6 },
		{ Id = "Ammo_Shell", Count = { 4, 8 }, Weight = 8 },
		{ Id = "Ammo_Rifle", Count = { 8, 16 }, Weight = 8 },
		{ Id = "Pistol", Count = { 1, 1 }, Weight = 6 },
		{ Id = "Medkit", Count = { 1, 1 }, Weight = 4 },
		{ Id = "Vest", Count = { 1, 1 }, Weight = 3 },
		{ Id = "Revolver", Count = { 1, 1 }, Weight = 2 },
		{ Id = "V_Bicycle", Count = { 1, 1 }, Weight = 3 },
	},
	Tier2 = { -- Industrie, Tankstelle, Bauernhof
		{ Id = "Bandage", Count = { 2, 4 }, Weight = 18 },
		{ Id = "Medkit", Count = { 1, 1 }, Weight = 10 },
		{ Id = "Ammo_9mm", Count = { 20, 40 }, Weight = 14 },
		{ Id = "Ammo_Rifle", Count = { 15, 30 }, Weight = 14 },
		{ Id = "Ammo_Shell", Count = { 8, 14 }, Weight = 10 },
		{ Id = "Ammo_Magnum", Count = { 10, 20 }, Weight = 8 },
		{ Id = "Vest", Count = { 1, 1 }, Weight = 9 },
		{ Id = "SMG", Count = { 1, 1 }, Weight = 7 },
		{ Id = "Shotgun", Count = { 1, 1 }, Weight = 7 },
		{ Id = "Revolver", Count = { 1, 1 }, Weight = 6 },
		{ Id = "Adrenaline", Count = { 1, 1 }, Weight = 4 },
		{ Id = "V_Quad", Count = { 1, 1 }, Weight = 2 },
	},
	Tier3 = { -- Militärbasis, rote Zonen
		{ Id = "Rifle", Count = { 1, 1 }, Weight = 10 },
		{ Id = "DMR", Count = { 1, 1 }, Weight = 6 },
		{ Id = "SMG", Count = { 1, 1 }, Weight = 8 },
		{ Id = "Shotgun", Count = { 1, 1 }, Weight = 6 },
		{ Id = "LMG", Count = { 1, 1 }, Weight = 2 },
		{ Id = "HeavyVest", Count = { 1, 1 }, Weight = 9 },
		{ Id = "Vest", Count = { 1, 1 }, Weight = 10 },
		{ Id = "Adrenaline", Count = { 1, 2 }, Weight = 8 },
		{ Id = "Medkit", Count = { 1, 2 }, Weight = 12 },
		{ Id = "Ammo_Rifle", Count = { 30, 60 }, Weight = 14 },
		{ Id = "Ammo_9mm", Count = { 40, 60 }, Weight = 8 },
		{ Id = "Ammo_Shell", Count = { 12, 20 }, Weight = 6 },
		{ Id = "V_Quad", Count = { 1, 1 }, Weight = 3 },
		{ Id = "V_Pickup", Count = { 1, 1 }, Weight = 1 },
	},
	Medical = {
		{ Id = "Bandage", Count = { 3, 6 }, Weight = 40 },
		{ Id = "Medkit", Count = { 1, 2 }, Weight = 28 },
		{ Id = "Adrenaline", Count = { 1, 1 }, Weight = 10 },
		{ Id = "Vest", Count = { 1, 1 }, Weight = 12 },
		{ Id = "HeavyVest", Count = { 1, 1 }, Weight = 4 },
	},
	Ammo = {
		{ Id = "Ammo_9mm", Count = { 30, 60 }, Weight = 30 },
		{ Id = "Ammo_Rifle", Count = { 30, 60 }, Weight = 28 },
		{ Id = "Ammo_Shell", Count = { 12, 24 }, Weight = 20 },
		{ Id = "Ammo_Magnum", Count = { 12, 24 }, Weight = 16 },
	},
	Airdrop = {
		{ Id = "LMG", Count = { 1, 1 }, Weight = 10 },
		{ Id = "DMR", Count = { 1, 1 }, Weight = 14 },
		{ Id = "Rifle", Count = { 1, 1 }, Weight = 18 },
		{ Id = "HeavyVest", Count = { 1, 1 }, Weight = 16 },
		{ Id = "Adrenaline", Count = { 2, 3 }, Weight = 14 },
		{ Id = "Medkit", Count = { 2, 3 }, Weight = 14 },
		{ Id = "Ammo_Rifle", Count = { 60, 120 }, Weight = 18 },
		{ Id = "Ammo_Shell", Count = { 24, 48 }, Weight = 8 },
		{ Id = "V_Pickup", Count = { 1, 1 }, Weight = 4 },
		{ Id = "V_Sports", Count = { 1, 1 }, Weight = 1 },
	},
}

-- Zombies lassen Beute in der Leiche: E durchsucht sie, alles geht direkt ins Inventar (passt etwas nicht mehr hinein,
-- bleibt es in der Leiche). Chance pro Zombie je Art (ZombieKinds), Anzahl und Tabelle ebenfalls dort.
ExtinctionConfig.ZombieDropChance = 0.55 -- Standardwert (ältere Aufrufe); die Art bestimmt mit Drop
ExtinctionConfig.ZombieLoot = ExtinctionConfig.LootTables.Zombie

-- ---------- Lagerkisten in der Welt (Teile "Spot_<Art>" in Gruppe Loot) ----------
-- Jede Art hat eine Beute-Tabelle (Table) und eine Zahl Items (Items); Spots in roten Zonen ziehen immer aus Tier3.
ExtinctionConfig.Containers = {
	Respawn = 480,        -- Sekunden, bis eine geleerte Kiste neu gefüllt ist
	Kinds = {
		Wood = { Name = "KISTE", Table = "Tier1", Items = { 1, 3 }, Size = Vector3.new(3.4, 2.4, 2.4), Color = Color3.fromRGB(128, 96, 62) },
		Toolbox = { Name = "WERKZEUGKISTE", Table = "Tier2", Items = { 1, 3 }, Size = Vector3.new(3.4, 2.0, 2.0), Color = Color3.fromRGB(176, 60, 50) },
		Medical = { Name = "SANI-KISTE", Table = "Medical", Items = { 1, 2 }, Size = Vector3.new(3.0, 2.0, 2.2), Color = Color3.fromRGB(226, 226, 220) },
		Ammo = { Name = "MUNITIONSKISTE", Table = "Ammo", Items = { 1, 2 }, Size = Vector3.new(3.2, 1.8, 2.0), Color = Color3.fromRGB(86, 98, 62) },
		Military = { Name = "MILITÄRKISTE", Table = "Tier3", Items = { 2, 4 }, Size = Vector3.new(4.0, 2.6, 2.6), Color = Color3.fromRGB(70, 82, 56) },
	},
}

-- ---------- Rote Zonen (Teile "Redzone_<Name>" in Gruppe Redzones: Zylinder, Radius = halbe Breite) ----------
-- Drinnen: PvP sofort, mehr und gefährlichere Zombies (Läufer, Brocken), Kisten ziehen aus Tier3, Lootdrops landen
-- bevorzugt dort.
ExtinctionConfig.Redzone = {
	PerPlayerFactor = 2,     -- so viel mehr Zombies um Spieler in einer roten Zone
	MaxTotalBonus = 14,      -- so viele Zombies darf der Server dafür zusätzlich haben
	KindWeights = { Walker = 55, Runner = 33, Brute = 12 },
	ContainerTable = "Tier3",
	PvPDelay = 0,
}

-- ---------- Lootdrops (Versorgungsabwürfe) ----------
ExtinctionConfig.Airdrop = {
	FirstDelay = 150,        -- Sekunden nach dem Serverstart (mit Spielern draußen) bis zum ersten Abwurf
	MinInterval = 420,       -- danach alle 7 bis 11 Minuten
	MaxInterval = 660,
	Warning = 45,            -- Vorwarnung: so lange vorher kommt die Ansage und die Markierung
	FallTime = 25,           -- so lange sinkt die Kiste am Fallschirm
	Height = 320,            -- Starthöhe über dem Boden
	OpenTime = 8,            -- E halten, so lange dauert das Öffnen (Sekunden)
	Lifetime = 300,          -- gelandet bleibt die Kiste so lange
	Items = { 6, 9 },        -- so viele Einträge aus LootTables.Airdrop
	Escort = 5,              -- so viele Zombies kommen um die Landestelle
	RedzoneChance = 0.4,     -- Wahrscheinlichkeit, in einer roten Zone zu landen
	EdgeMargin = 140,        -- Abstand zum Kartenrand
	SafeMargin = 180,        -- Abstand zur Safe Zone
	MinPlayers = 1,          -- ohne Spieler draußen gibt es keinen Abwurf
}

-- ---------- Zombies ----------
-- Wenige und langsame Zombies: man kann ihnen davonlaufen (Spieler laufen 16, sprinten 24). Die Standardwerte gelten für
-- den normalen Zombie (Walker), ZombieKinds überschreibt sie je Art. Läufer und Brocken gibt es nur in roten Zonen.
ExtinctionConfig.Zombies = {
	PerPlayer = 3,         -- so viele Zombies um jeden Spieler draußen
	MaxTotal = 30,         -- höchstens so viele gleichzeitig auf dem Server
	SpawnMin = 80,         -- Abstand zum Spieler beim Spawnen (Studs) ...
	SpawnMax = 150,        -- ... im weiteren Umkreis
	SpawnInterval = 3,     -- Sekunden zwischen zwei Spawn-Runden
	SafeMargin = 40,       -- nicht so nah an der Safe Zone spawnen
	DespawnDistance = 260, -- weiter weg von allen Spielern: verschwinden
	Health = 100,
	WalkSpeed = 4,         -- schlurfen ohne Ziel
	RunSpeed = 8.5,        -- jagen
	SightRange = 45,       -- so weit bemerken sie Spieler
	LoseRange = 90,        -- so weit verfolgen sie ein Ziel, das sie schon haben
	AttackRange = 4.5,
	AttackDamage = 10,
	AttackDelay = 1.4,
	CorpseTime = 4,        -- Leiche ohne Beute bleibt so lange liegen
	CorpseLootTime = 40,   -- Leiche mit Beute (E durchsucht sie) bleibt so lange
}

-- Arten: Health, Walk/Run (Tempo), Damage, Coins, Scale (Größe), Drop (Chance auf Beute), Items (Anzahl), Table (Beute-Tabelle),
-- Eyes (Augenfarbe). Walker fehlt hier bewusst bei Werten, die in ExtinctionConfig.Zombies stehen (siehe ZombieService.Kind).
ExtinctionConfig.ZombieKinds = {
	Walker = { Name = "Zombie", Scale = 1, Drop = 0.55, Items = { 1, 1 }, Table = "Zombie", Coins = 2,
		Eyes = Color3.fromRGB(255, 40, 30) },
	Runner = { Name = "Läufer", Health = 70, Walk = 6, Run = 13, Damage = 8, Coins = 4, Scale = 0.95, Drop = 0.65, Items = { 1, 2 },
		Table = "Zombie2", Eyes = Color3.fromRGB(255, 170, 30) },
	Brute = { Name = "Brocken", Health = 320, Walk = 4, Run = 7.5, Damage = 24, Coins = 12, Scale = 1.3, Drop = 1, Items = { 2, 3 },
		Table = "Tier2", Eyes = Color3.fromRGB(190, 70, 255) },
}

-- ---------- Abfragen ----------

-- Beute ziehen: count Einträge aus der Tabelle (gewichtet, ohne denselben Eintrag zweimal). random = Random.
-- Gibt { { Id, Count } } zurück.
function ExtinctionConfig.RollLoot(tableName, count, random)
	local entries = ExtinctionConfig.LootTables[tableName]
	if not entries then
		return {}
	end
	random = random or Random.new()
	local pool = table.clone(entries)
	local result = {}
	for _ = 1, math.min(count, #pool) do
		local total = 0
		for _, entry in pool do
			total += entry.Weight
		end
		local roll = random:NextNumber(0, total)
		for index, entry in pool do
			roll -= entry.Weight
			if roll <= 0 or index == #pool then
				table.insert(result, { Id = entry.Id, Count = random:NextInteger(entry.Count[1], entry.Count[2]) })
				table.remove(pool, index)
				break
			end
		end
	end
	return result
end

function ExtinctionConfig.Get(id)
	return ExtinctionConfig.Items[id]
end

-- Höchste Stapelgröße eines Items (Waffen und Fahrzeuge: 1)
function ExtinctionConfig.MaxStack(id)
	local item = ExtinctionConfig.Items[id]
	if not item then
		return 0
	end
	return item.MaxStack or 1
end

-- Verkaufspreis für count Stück (Munition: pro Schuss anteilig vom Pack-Preis). Items ohne Preis bringen
-- den Preis ihrer Stufe (gefundene Fahrräder usw.).
function ExtinctionConfig.SellPrice(id, count)
	local item = ExtinctionConfig.Items[id]
	if not item then
		return 0
	end
	local price = item.Price or (item.Tier or 0) * 60 + 40
	local each = item.Pack and price / item.Pack or price
	return math.floor(each * (count or 1) * ExtinctionConfig.SellFactor)
end

-- Munitionssorte einer Waffe (Item-Id oder WeaponConfig-Name)
function ExtinctionConfig.AmmoFor(id)
	local item = ExtinctionConfig.Items[id]
	if item and item.Ammo then
		return item.Ammo
	end
	for _, other in ExtinctionConfig.Items do
		if other.Weapon == id then
			return other.Ammo
		end
	end
	return nil
end

-- Item-Id zur WeaponConfig-Waffe (z.B. "Rifle" -> "Rifle")
function ExtinctionConfig.ItemForWeapon(weaponName)
	for id, item in ExtinctionConfig.Items do
		if item.Weapon == weaponName then
			return id
		end
	end
	return nil
end

return ExtinctionConfig

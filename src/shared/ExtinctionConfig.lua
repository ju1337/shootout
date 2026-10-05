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

-- Beute von Zombies: nur einfache Sachen. Chance pro Zombie, dass überhaupt etwas fällt, dann gewichtete Wahl.
ExtinctionConfig.ZombieDropChance = 0.35
ExtinctionConfig.ZombieLoot = {
	{ Id = "Bandage", Count = { 1, 2 }, Weight = 40 },
	{ Id = "Ammo_9mm", Count = { 8, 20 }, Weight = 24 },
	{ Id = "Ammo_Shell", Count = { 3, 6 }, Weight = 10 },
	{ Id = "Ammo_Rifle", Count = { 6, 15 }, Weight = 10 },
	{ Id = "Medkit", Count = { 1, 1 }, Weight = 6 },
	{ Id = "Pistol", Count = { 1, 1 }, Weight = 4 },
	{ Id = "V_Bicycle", Count = { 1, 1 }, Weight = 4 },
	{ Id = "V_Quad", Count = { 1, 1 }, Weight = 2 },
}

-- ---------- Zombies ----------
ExtinctionConfig.Zombies = {
	PerPlayer = 7,         -- so viele Zombies um jeden Spieler draußen
	MaxTotal = 70,         -- höchstens so viele gleichzeitig auf dem Server
	SpawnMin = 70,         -- Abstand zum Spieler beim Spawnen (Studs) ...
	SpawnMax = 150,        -- ... im weiteren Umkreis
	SpawnInterval = 1.5,   -- Sekunden zwischen zwei Spawn-Runden
	SafeMargin = 40,       -- nicht so nah an der Safe Zone spawnen
	DespawnDistance = 260, -- weiter weg von allen Spielern: verschwinden
	Health = 100,
	WalkSpeed = 9,         -- schlurfen ohne Ziel
	RunSpeed = 15,         -- jagen (Spieler laufen 16, sprinten 24)
	SightRange = 90,       -- so weit bemerken sie Spieler
	AttackRange = 4.5,
	AttackDamage = 12,
	AttackDelay = 1.1,
}

-- ---------- Abfragen ----------

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

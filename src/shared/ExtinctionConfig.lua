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
--   "Repel"   Anti-Zombie-Spritze: Duration Sekunden spawnen beim Benutzer keine Zombies (Charakter-Attribut ZombieShieldUntil)
--   "Throwable" Granate oder Molotow (Throwable = Eintrag in Throwables): Taste wirft in Blickrichtung (ThrowableService)
--   "Attachment" Waffen-Aufsatz (Attachment = Id in AttachmentConfig, Slot = Platz): auf eine Waffe in der Tasche ziehen
--             (oder Taste mit der Waffe in der Hand) hängt ihn an diese Waffe; ein alter Aufsatz desselben Platzes
--             kommt zurück in die Tasche. Er bleibt an der Waffe (Inventar-Feld Att) und geht mit ihr verloren.
-- Price = Kaufpreis in Münzen (nil = nicht zu kaufen, nur zu finden). Verkaufen bringt SellFactor des Preises.

local AttachmentConfig = require(script.Parent.AttachmentConfig)

local ExtinctionConfig = {}

ExtinctionConfig.ModeId = "Extinction"
ExtinctionConfig.WorldSize = 3200    -- Kantenlänge der Welt in Studs (EXTINCTION_SIZE in tools/build_maps.py)

-- ---------- Inventar ----------
ExtinctionConfig.HotbarSlots = 9     -- Plätze 1-9 = Tasten 1-9
ExtinctionConfig.BagSlots = 30       -- Tasche gesamt (inkl. Hotbar)
ExtinctionConfig.StashSlots = 40     -- Lager in der Safe Zone (immer sicher)
ExtinctionConfig.SafeSlots = 20      -- Container: sichere Tasche, überall erreichbar, bleibt beim Tod
ExtinctionConfig.StandRange = 14     -- so nah muss man am Stand/Lager sein (Studs)
ExtinctionConfig.TravelCooldown = 10 -- Sekunden zwischen zwei Reisen (Haltestellen in den Safe Zones)
ExtinctionConfig.SellFactor = 0.4    -- Verkauf: Anteil vom Kaufpreis
ExtinctionConfig.MaxArmor = 100

-- ---------- Safe Zone und PvP ----------
ExtinctionConfig.PvPDelay = 5        -- Sekunden nach dem Verlassen der Safe Zone, bis PvP gilt
-- Im Kampf (Spieler getroffen oder von einem Spieler getroffen): so lange kommt man nicht in eine Safe Zone
-- (Spieler-Attribut CombatUntil = Serverzeit, Damage setzt es; Barriere und Anzeige: CombatBarrier auf dem Client)
ExtinctionConfig.CombatTime = 15
-- Spawnschutz nach dem Verlassen einer Safe Zone (Sekunden): kein Schaden von irgendwem, aber selbst auch nicht schießen,
-- werfen oder Zombies töten (CanFight aus, Spieler-Attribut ProtectedUntil = Serverzeit). Waffe ziehen geht.
ExtinctionConfig.SpawnProtection = 4
-- Zum Entwickeln: Admins (Attribut IsAdmin) spawnen in der offenen Welt immer mit diesen Items (fehlende werden ergänzt)
ExtinctionConfig.AdminLoadout = { { "Rifle", 1 }, { "Ammo_Rifle", 150 }, { "Pistol", 1 }, { "Ammo_9mm", 60 } }
ExtinctionConfig.RespawnTime = 5     -- nach dem Tod: Respawn in der Safe Zone
ExtinctionConfig.LeaveConfirmTime = 6 -- Verlassen außerhalb der Safe Zone: zweimal klicken innerhalb dieser Zeit

-- ---------- Belohnungen (Münzen) ----------
ExtinctionConfig.ZombieCoins = 2     -- pro Zombie (sehr wenig)
ExtinctionConfig.ZombieXP = 10       -- XP pro Zombie für den aktiven Agenten und das Spielerlevel (je Art: ZombieKinds.XP)
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
	-- Helikopter: fliegt (VehicleClient). Climb = Steigen/Sinken (Studs/s), Ceiling = höchste Flughöhe über der Mitte der
	-- Welt (MapCenter), Descent = Sinken ohne Pilot (Autorotation, bis er aufsetzt). Pilot vorne links, Kopilot, zwei hinten.
	Heli = { Name = "Helikopter", Tier = 4, Speed = 90, Accel = 26, Turn = 70, Health = 900, Kind = "Heli",
		Size = Vector3.new(6.4, 2.0, 12), Color = Color3.fromRGB(64, 76, 58), Seats = 4, Climb = 28, Ceiling = 320, Descent = 14 },
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
	-- Anti-Zombie-Spritze: einzige Wirkung – Duration Sekunden lang spawnen bei dir keine Zombies (Zombies.ShieldRadius)
	AntiZombie = { Kind = "Repel", Name = "Anti-Zombie-Spritze", Duration = 180, UseTime = 2, Price = 240, MaxStack = 3, Tier = 2 },
	-- Wurfwaffen (Werte in Throwables)
	Grenade = { Kind = "Throwable", Name = "Granate", Throwable = "Frag", Price = 320, MaxStack = 3, Tier = 2 },
	Molotov = { Kind = "Throwable", Name = "Molotow", Throwable = "Molotov", Price = 240, MaxStack = 3, Tier = 2 },
	-- Fahrzeuge (Fahrrad gibt es nur bei Zombies)
	V_Bicycle = { Kind = "Vehicle", Name = "Fahrrad", Vehicle = "Bicycle", Tier = 0 },
	V_Quad = { Kind = "Vehicle", Name = "Quad", Vehicle = "Quad", Price = 900, Tier = 1 },
	V_Pickup = { Kind = "Vehicle", Name = "Geländewagen", Vehicle = "Pickup", Price = 2600, Tier = 2 },
	V_Sports = { Kind = "Vehicle", Name = "Sportwagen", Vehicle = "Sports", Price = 5200, Tier = 3 },
	V_Heli = { Kind = "Vehicle", Name = "Helikopter", Vehicle = "Heli", Price = 12000, Tier = 4 },
}

-- Kit-Ausführungen (KitConfig): gleiche Werte wie das Original, Id "<Id>_Kit", Name mit "(Kit)", unverkäuflich (weder am
-- Stand noch im Spielermarkt, Kit = true). Munition bleibt die normale (Nachladen sucht die Munitions-Id); die bringt aus
-- Kits beim Verkaufen 0 Münzen (KitConfig.SellSplit).
ExtinctionConfig.KitVariants = { "Pistol", "SMG", "Bandage", "Vest", "V_Bicycle" }
for _, base in ExtinctionConfig.KitVariants do
	local variant = table.clone(ExtinctionConfig.Items[base])
	variant.Price = nil
	variant.Value = 0
	variant.Kit = true
	variant.Base = base
	variant.Name = variant.Name .. " (Kit)"
	ExtinctionConfig.Items[base .. "_Kit"] = variant
end

-- Waffen-Aufsätze als Items ("Att_<Id>"), aus AttachmentConfig. Nicht zu kaufen: es gibt sie nur im Konvoi (sicher 2-3
-- Stück, Convoy.Attachments) und selten in Lootdrops. Value = Wert beim Verkaufen (etwa die Hälfte der Lobby).
ExtinctionConfig.AttachmentItems = {}
for _, att in AttachmentConfig.List do
	local id = "Att_" .. att.Id
	ExtinctionConfig.Items[id] = { Kind = "Attachment", Name = att.Name, Attachment = att.Id, Slot = att.Slot,
		Value = math.floor(att.Price * 0.5 / 10) * 10, MaxStack = 3, Tier = att.Tier or 2 }
	table.insert(ExtinctionConfig.AttachmentItems, id)
end

-- Was die Stände verkaufen (Reihenfolge = Anzeige). Verkaufen kann man an jedem Stand alles.
ExtinctionConfig.Stands = {
	Stand_Weapons = { Title = "WAFFENSTAND", Items = { "Pistol", "Revolver", "SMG", "Shotgun", "Rifle", "DMR", "LMG",
		"Ammo_9mm", "Ammo_Magnum", "Ammo_Shell", "Ammo_Rifle", "Grenade", "Molotov" } },
	Stand_Items = { Title = "ITEMSTAND", Items = { "Bandage", "Medkit", "Adrenaline", "AntiZombie", "Vest", "HeavyVest" } },
	Stand_Vehicles = { Title = "FAHRZEUGSTAND", Items = { "V_Quad", "V_Pickup", "V_Sports", "V_Heli" } },
}


-- ---------- Rote-Zone-Punkte (RZ, RedPointsService) und der Schieber ----------
-- RZ gibt es nur in der roten Zone: Spieler-Kill PlayerKill, Bot-Kill BotKill, Zombie-Kill ZombieKill; zieht die Zone weiter,
-- bekommen die besten drei der Rangliste Rank[1..3]. Gespeichert im Profil (RedPoints), bleiben beim Tod.
-- Der Schieber (Stand_Red, schwarzer Transporter in der Weststraße des Camps) verkauft nur gegen RZ (Stands.Stand_Red.Prices).
ExtinctionConfig.RedPoints = {
	PlayerKill = 2,
	BotKill = 2,
	ZombieKill = 1,
	Rank = { 50, 30, 15 },
}
do
	local prices = {
		LMG = 140, DMR = 110, HeavyVest = 45, Adrenaline = 20, Grenade = 15, Molotov = 12,
	}
	local items = { "LMG", "DMR", "HeavyVest", "Adrenaline", "Grenade", "Molotov" }
	local tierPrice = { [2] = 40, [3] = 80, [4] = 150 }
	for _, id in ExtinctionConfig.AttachmentItems do
		prices[id] = tierPrice[ExtinctionConfig.Items[id].Tier] or 80
		table.insert(items, id)
	end
	-- Optional: nicht jede Karte hat den Schieber (Clients warten nicht auf den Punkt)
	ExtinctionConfig.Stands.Stand_Red = { Title = "DER SCHIEBER", Currency = "RedPoints", Items = items, Prices = prices, Optional = true }
end

-- ---------- Spielermarkt (ExtMarketService, Reiter MARKT im Menü, nur in der Safe Zone) ----------
-- Spieler bieten Items aus der Tasche für Münzen an (höchstens MaxListings gleichzeitig, Preis 1 bis MaxPrice); der Käufer
-- zahlt den Preis, der Verkäufer bekommt ihn minus FeeRate Gebühr. Angebote stehen im Spielstand des Verkäufers und sind
-- sichtbar, solange er auf dem Server ist.
ExtinctionConfig.Market = {
	MaxListings = 8,
	MaxPrice = 100000,
	FeeRate = 0.05,
}

-- ---------- Beute-Tabellen ----------
-- Gewichtete Listen { Id, Count = { min, max }, Weight }. Gezogen wird mit ExtinctionConfig.RollLoot(Tabelle, Anzahl).
-- Zombie / Zombie2 = Leichen (einfach), Tier1-3 = Kisten in der Welt (3 = Militär und rote Zone), Medical = Sanikisten,
-- Ammo = Munitionskisten, Airdrop = Versorgungsabwürfe (das Beste).
ExtinctionConfig.LootTables = {
	Zombie = {
		{ Id = "Bandage", Count = { 1, 2 }, Weight = 36 },
		{ Id = "Ammo_9mm", Count = { 8, 20 }, Weight = 24 },
		{ Id = "Ammo_Shell", Count = { 3, 6 }, Weight = 8 },
		{ Id = "Ammo_Rifle", Count = { 6, 15 }, Weight = 8 },
		{ Id = "Medkit", Count = { 1, 1 }, Weight = 6 },
		{ Id = "AntiZombie", Count = { 1, 1 }, Weight = 3 },
		{ Id = "Pistol", Count = { 1, 1 }, Weight = 4 },
		{ Id = "V_Bicycle", Count = { 1, 1 }, Weight = 4 },
		{ Id = "V_Quad", Count = { 1, 1 }, Weight = 1 },
	},
	Zombie2 = { -- Läufer in der roten Zone: etwas besser
		{ Id = "Bandage", Count = { 2, 3 }, Weight = 24 },
		{ Id = "Ammo_9mm", Count = { 14, 30 }, Weight = 20 },
		{ Id = "Ammo_Rifle", Count = { 10, 24 }, Weight = 14 },
		{ Id = "Ammo_Shell", Count = { 5, 10 }, Weight = 10 },
		{ Id = "Medkit", Count = { 1, 1 }, Weight = 12 },
		{ Id = "AntiZombie", Count = { 1, 1 }, Weight = 6 },
		{ Id = "Vest", Count = { 1, 1 }, Weight = 8 },
		{ Id = "Pistol", Count = { 1, 1 }, Weight = 5 },
		{ Id = "Revolver", Count = { 1, 1 }, Weight = 4 },
		{ Id = "V_Quad", Count = { 1, 1 }, Weight = 3 },
		{ Id = "Molotov", Count = { 1, 1 }, Weight = 2 },
	},
	Tier1 = { -- Häuser, Hinterhöfe
		{ Id = "Bandage", Count = { 1, 2 }, Weight = 30 },
		{ Id = "Ammo_9mm", Count = { 10, 24 }, Weight = 26 },
		{ Id = "Ammo_Magnum", Count = { 6, 12 }, Weight = 6 },
		{ Id = "Ammo_Shell", Count = { 4, 8 }, Weight = 8 },
		{ Id = "Ammo_Rifle", Count = { 8, 16 }, Weight = 8 },
		{ Id = "Pistol", Count = { 1, 1 }, Weight = 6 },
		{ Id = "Medkit", Count = { 1, 1 }, Weight = 4 },
		{ Id = "AntiZombie", Count = { 1, 1 }, Weight = 3 },
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
		{ Id = "AntiZombie", Count = { 1, 1 }, Weight = 7 },
		{ Id = "V_Quad", Count = { 1, 1 }, Weight = 2 },
		{ Id = "Molotov", Count = { 1, 2 }, Weight = 5 },
		{ Id = "Grenade", Count = { 1, 1 }, Weight = 2 },
	},
	Tier3 = { -- Militärbasis, rote Zone
		{ Id = "Rifle", Count = { 1, 1 }, Weight = 10 },
		{ Id = "DMR", Count = { 1, 1 }, Weight = 6 },
		{ Id = "SMG", Count = { 1, 1 }, Weight = 8 },
		{ Id = "Shotgun", Count = { 1, 1 }, Weight = 6 },
		{ Id = "LMG", Count = { 1, 1 }, Weight = 2 },
		{ Id = "HeavyVest", Count = { 1, 1 }, Weight = 9 },
		{ Id = "Vest", Count = { 1, 1 }, Weight = 10 },
		{ Id = "Adrenaline", Count = { 1, 2 }, Weight = 8 },
		{ Id = "Medkit", Count = { 1, 2 }, Weight = 12 },
		{ Id = "AntiZombie", Count = { 1, 2 }, Weight = 8 },
		{ Id = "Ammo_Rifle", Count = { 30, 60 }, Weight = 14 },
		{ Id = "Ammo_9mm", Count = { 40, 60 }, Weight = 8 },
		{ Id = "Ammo_Shell", Count = { 12, 20 }, Weight = 6 },
		{ Id = "V_Quad", Count = { 1, 1 }, Weight = 3 },
		{ Id = "V_Pickup", Count = { 1, 1 }, Weight = 1 },
		{ Id = "Grenade", Count = { 1, 2 }, Weight = 8 },
		{ Id = "Molotov", Count = { 1, 2 }, Weight = 6 },
	},
	Medical = {
		{ Id = "Bandage", Count = { 3, 6 }, Weight = 40 },
		{ Id = "Medkit", Count = { 1, 2 }, Weight = 28 },
		{ Id = "Adrenaline", Count = { 1, 1 }, Weight = 10 },
		{ Id = "AntiZombie", Count = { 1, 2 }, Weight = 18 },
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
		{ Id = "AntiZombie", Count = { 2, 3 }, Weight = 10 },
		{ Id = "Ammo_Rifle", Count = { 60, 120 }, Weight = 18 },
		{ Id = "Ammo_Shell", Count = { 24, 48 }, Weight = 8 },
		{ Id = "V_Pickup", Count = { 1, 1 }, Weight = 4 },
		{ Id = "V_Sports", Count = { 1, 1 }, Weight = 1 },
		{ Id = "Grenade", Count = { 2, 3 }, Weight = 10 },
	},
}

-- ---------- Wurfwaffen (ThrowableService) ----------
-- Speed/Up = Wurf (Studs/s nach vorn und nach oben), Cooldown zwischen zwei Würfen.
-- Frag: explodiert nach Fuse Sekunden; Damage in der Mitte, am Rand (Radius) noch EdgeFactor davon; Wände schützen.
-- Molotov: zerplatzt beim Aufprall (spätestens nach Fuse Sekunden) zu einem Feuer mit Radius, das Duration Sekunden brennt
-- und alle Tick Sekunden TickDamage macht (Zombies ZombieFactor-fach). Spieler nur nach den PvP-Regeln, nie der Werfer
-- selbst und nie der eigene Squad. Fahrzeuge und der Konvoi nehmen Schaden (VehicleFactor).
ExtinctionConfig.Throwables = {
	Frag = { Speed = 70, Up = 20, Fuse = 2.5, Radius = 18, Damage = 120, EdgeFactor = 0.3, VehicleFactor = 3, Cooldown = 1 },
	Molotov = { Speed = 62, Up = 18, Fuse = 3, Radius = 11, Duration = 8, Tick = 0.5, TickDamage = 6, ZombieFactor = 2,
		VehicleFactor = 2, Cooldown = 1 },
}

-- Aufsätze in der Beute: je Tabelle Gewicht pro Seltenheit (2/3/4); fehlende Seltenheit = kommt dort nicht vor.
-- ConvoyAttachments = nur Aufsätze (die sicheren Stücke aus dem Konvoi), sonst nur selten im Lootdrop.
ExtinctionConfig.LootTables.ConvoyAttachments = {}
local ATTACHMENT_LOOT = {
	ConvoyAttachments = { [2] = 5, [3] = 3, [4] = 1.2 },
	Airdrop = { [3] = 1.2, [4] = 0.6 },
}
for tableName, weights in ATTACHMENT_LOOT do
	for _, id in ExtinctionConfig.AttachmentItems do
		local weight = weights[ExtinctionConfig.Items[id].Tier]
		if weight then
			table.insert(ExtinctionConfig.LootTables[tableName], { Id = id, Count = { 1, 1 }, Weight = weight })
		end
	end
end

-- Zombies lassen Beute in der Leiche: einmal E (ohne Halten) hebt sie auf, alles geht direkt ins Inventar (passt etwas nicht mehr hinein,
-- bleibt es in der Leiche). Chance pro Zombie je Art (ZombieKinds), Anzahl und Tabelle ebenfalls dort.
ExtinctionConfig.ZombieDropChance = 0.55 -- Standardwert (ältere Aufrufe); die Art bestimmt mit Drop
ExtinctionConfig.ZombieLoot = ExtinctionConfig.LootTables.Zombie

-- ---------- Lagerkisten in der Welt (Teile "Spot_<Art>" in Gruppe Loot) ----------
-- Jede Art hat eine Beute-Tabelle (Table) und eine Zahl Items (Items); Spots in der roten Zone ziehen aus Tier3.
ExtinctionConfig.Containers = {
	Enabled = false,      -- keine Beute am Boden: Beute gibt es von Zombies, Lootdrops und Ständen (true = Kisten wieder an)
	Respawn = 480,        -- Sekunden, bis eine geleerte Kiste neu gefüllt ist
	Kinds = {
		Wood = { Name = "KISTE", Table = "Tier1", Items = { 1, 3 }, Size = Vector3.new(3.4, 2.4, 2.4), Color = Color3.fromRGB(128, 96, 62) },
		Toolbox = { Name = "WERKZEUGKISTE", Table = "Tier2", Items = { 1, 3 }, Size = Vector3.new(3.4, 2.0, 2.0), Color = Color3.fromRGB(176, 60, 50) },
		Medical = { Name = "SANI-KISTE", Table = "Medical", Items = { 1, 2 }, Size = Vector3.new(3.0, 2.0, 2.2), Color = Color3.fromRGB(226, 226, 220) },
		Ammo = { Name = "MUNITIONSKISTE", Table = "Ammo", Items = { 1, 2 }, Size = Vector3.new(3.2, 1.8, 2.0), Color = Color3.fromRGB(86, 98, 62) },
		Military = { Name = "MILITÄRKISTE", Table = "Tier3", Items = { 2, 4 }, Size = Vector3.new(4.0, 2.6, 2.6), Color = Color3.fromRGB(70, 82, 56) },
	},
}

-- ---------- Rote Zone (RedzoneService): eine Zone, die alle Interval Sekunden an einen anderen Ort zieht ----------
-- Ziele: Orte der Karte (Place_<Name>) außer Exclude, nicht größer als MaxPlaceSize, weit genug von der Safe Zone und den
-- Safehouses, nicht im Wasser, nie zweimal hintereinander derselbe und möglichst weit weg vom alten (MinMove). Drinnen: PvP sofort, mehr und gefährlichere Zombies
-- (Läufer, Brocken), Kisten ziehen aus Tier3, Lootdrops landen bevorzugt dort. Jeder Wechsel beginnt eine neue Runde der
-- Rangliste (RedzoneBoard).
ExtinctionConfig.Redzone = {
	Enabled = true,
	Interval = 20 * 60,      -- Sekunden bis zum nächsten Wechsel (eine Runde der Rangliste)
	Warning = 60,            -- so viele Sekunden vorher kommt die Ansage
	Radius = 170,
	MinMove = 400,           -- der neue Ort liegt mindestens so weit vom alten weg (wenn es so einen gibt)
	MaxPlaceSize = 600,      -- Orte mit größerem Durchmesser (Ödstadt, Innenstadt) sind kein Ziel
	Exclude = { "Camp", "Zentrale", "Oedstadt", "Innenstadt", "Schwarzsee", "Stausee", "Teich" },
	Color = Color3.fromRGB(226, 56, 48),
	WallPanels = 48,         -- flimmernde Wand (ForceField) am Rand
	WallHeight = 70,
	PerPlayerFactor = 2,     -- so viel mehr Zombies um Spieler in der roten Zone
	MaxTotalBonus = 14,      -- so viele Zombies darf der Server dafür zusätzlich haben
	KindWeights = { Walker = 50, Runner = 30, Brute = 12, Screamer = 8 },
	ContainerTable = "Tier3",
	-- Bessere Beute (ExtinctionConfig.RedzoneRoll): Zombies, die in der Zone sterben, haben DropBonus mehr Chance auf Beute,
	-- ziehen aus der nächstbesseren Tabelle (BetterTable), haben ExtraItems mehr und StackFactor größere Stapel (Munition,
	-- Verbände) und bringen CoinFactor mal so viele Münzen. Vorratslager und Nester dort: ExtraItems mehr, größere Stapel.
	-- Lootdrops in der Zone: zusätzlich AirdropExtra Items. MoveDrop: bei jedem Wechsel kommt ein Lootdrop in die neue Zone
	-- (wenn jemand draußen ist und gerade keiner läuft).
	Loot = {
		DropBonus = 0.25,
		BetterTable = { Zombie = "Zombie2", Zombie2 = "Tier2", Tier2 = "Tier3", Tier3 = "Airdrop" },
		ExtraItems = 1,
		StackFactor = 1.5,
		CoinFactor = 2,
		AirdropExtra = 1,
		MoveDrop = true,
	},
}

-- ---------- Bots (Admin-Panel: Gegner zum Testen von PvP, Todestaschen und der Rangliste) ----------
-- Spawnen SpawnMin bis SpawnMax Studs um den Admin (steht er in einer Safe Zone: SafeMargin vor ihrem Rand), ohne Admin in
-- der offenen Welt in der roten Zone. Sie jagen Spieler draußen (nie in einer Safe Zone, höchstens HuntRange weit), schießen
-- auf Zombies in ZombieRange (Zombies jagen sie auch) und lassen beim Tod eine Tasche fallen: ihre Waffe (Weapons = Item-Ids),
-- Munition dazu und LootItems Einträge aus LootTable (in der roten Zone RedLootTable). Wer sie erledigt, bekommt KillCoins,
-- in der roten Zone zählt der Kill für die Rangliste. Kein Respawn: die Leiche verschwindet nach CorpseTime Sekunden.
ExtinctionConfig.Bots = {
	Max = 12,
	SpawnMin = 25,
	SpawnMax = 45,
	SafeMargin = 30,
	HuntRange = 160,
	ZombieRange = 45,
	Weapons = { "Pistol", "Revolver", "SMG", "Shotgun", "Rifle", "DMR" },
	Ammo = { 20, 45 },
	LootTable = "Tier2",
	RedLootTable = "Tier3",
	LootItems = { 1, 2 },
	KillCoins = 80,
	CorpseTime = 8,
}

-- ---------- Konvoi (ConvoyService) ----------
-- Alle MinInterval bis MaxInterval Sekunden (zuerst nach FirstDelay, nur wenn mindestens MinPlayers draußen sind) fährt ein
-- bewaffneter Konvoi eine Landstraße entlang (Routes: Punkte relativ zur Kartenmitte, aus tools/extinction_world.py –
-- zufällig vorwärts oder rückwärts): Begleitfahrzeug, Lkw mit Ladung, Begleitfahrzeug. Warning Sekunden vorher steht er
-- am Start (Ansage, Markierung). Unterwegs schießen die Begleitfahrzeuge auf Spieler in GunRange (alle GunEvery Sekunden,
-- Treffer mit GunChance, GunDamage Schaden). Schüsse auf ein Fahrzeug ziehen vom Konvoi Leben ab (Health); fällt es unter
-- HaltAt (Anteil), hält der Konvoi an und Guards Wachen (Bots mit GuardWeapons) steigen aus. Sind alle Wachen erledigt
-- (oder nach GuardTimeout Sekunden), wird die Ladung frei: Kiste (E halten OpenTime Sekunden) mit Items Einträgen aus
-- Table, dazu Coins Münzen für alle, die den Konvoi beschossen haben. Kommt er ans Ende der Strecke, ist er entkommen.
-- Die Kiste bleibt Lifetime Sekunden. Stand für die Clients: Karten-Attribut "Convoys" [{ Id, X, Z, State, Route }].
ExtinctionConfig.Convoy = {
	Enabled = true,
	FirstDelay = 8 * 60,
	MinInterval = 18 * 60,
	MaxInterval = 28 * 60,
	MinPlayers = 1,
	Warning = 45,
	Speed = 16,
	Spacing = 22,           -- Abstand der Fahrzeuge (Studs entlang der Straße)
	Health = 2400,
	HaltAt = 0.7,
	Guards = 4,
	GuardWeapons = { "SMG", "Rifle", "Shotgun", "Rifle" },
	GuardRange = 140,
	GuardTimeout = 150,
	GunRange = 130,
	GunEvery = 0.9,
	GunChance = 0.45,
	GunDamage = 9,
	Table = "Airdrop",
	Items = { 4, 6 },
	Attachments = { 2, 3 }, -- dazu sicher so viele Waffen-Aufsätze (Tabelle ConvoyAttachments) – nur hier gibt es sie sicher
	Coins = 250,
	OpenTime = 6,
	Lifetime = 300,
}
ExtinctionConfig.Convoy.Routes = {
	{ Name = "Militär → Flugplatz", Points = { { -1020, 1150 }, { -980, 1153 }, { -940, 1157 }, { -900, 1160 }, { -861, 1164 }, { -821, 1168 }, { -781, 1175 }, { -742, 1182 }, { -702, 1186 }, { -663, 1191 }, { -623, 1191 }, { -583, 1191 }, { -543, 1191 }, { -503, 1190 }, { -464, 1179 }, { -426, 1167 }, { -386, 1162 }, { -347, 1159 }, { -307, 1155 }, { -267, 1152 }, { -227, 1146 }, { -188, 1140 }, { -149, 1131 }, { -110, 1120 }, { -73, 1107 }, { -36, 1091 }, { 2, 1078 }, { 40, 1066 }, { 78, 1053 }, { 115, 1039 }, { 153, 1026 }, { 192, 1020 }, { 232, 1014 }, { 271, 1005 }, { 310, 995 }, { 348, 996 }, { 386, 1007 }, { 425, 1019 }, { 463, 1029 }, { 502, 1038 }, { 542, 1045 }, { 581, 1050 }, { 621, 1055 }, { 661, 1060 }, { 700, 1067 }, { 739, 1075 }, { 777, 1087 }, { 815, 1101 }, { 852, 1117 }, { 887, 1134 }, { 925, 1148 }, { 963, 1161 }, { 1002, 1170 }, { 1041, 1178 }, { 1050, 1180 } } },
	{ Name = "Gefängnis → Nordheim", Points = { { -1090, -960 }, { -1098, -921 }, { -1105, -881 }, { -1109, -842 }, { -1113, -802 }, { -1117, -762 }, { -1121, -722 }, { -1128, -683 }, { -1137, -644 }, { -1147, -605 }, { -1158, -567 }, { -1159, -527 }, { -1158, -487 }, { -1153, -448 }, { -1147, -408 }, { -1145, -368 }, { -1143, -328 }, { -1146, -288 }, { -1150, -248 }, { -1141, -209 }, { -1132, -170 }, { -1121, -132 }, { -1110, -94 }, { -1096, -56 }, { -1082, -19 }, { -1067, 18 }, { -1052, 56 }, { -1039, 93 }, { -1027, 131 }, { -1017, 170 }, { -1007, 209 }, { -994, 247 }, { -982, 285 }, { -971, 323 }, { -961, 362 }, { -953, 401 }, { -945, 441 }, { -939, 480 }, { -931, 519 }, { -924, 559 }, { -915, 598 }, { -906, 636 }, { -894, 675 }, { -882, 713 }, { -852, 737 }, { -818, 758 }, { -784, 779 }, { -750, 800 }, { -717, 822 }, { -684, 845 }, { -651, 868 }, { -619, 891 }, { -587, 915 }, { -555, 940 }, { -523, 964 }, { -491, 988 }, { -459, 1012 }, { -427, 1035 }, { -394, 1058 }, { -361, 1080 }, { -327, 1102 }, { -293, 1123 }, { -259, 1144 }, { -250, 1150 } } },
	{ Name = "Hafen → Flugplatz", Points = { { 960, -1050 }, { 922, -1062 }, { 884, -1074 }, { 846, -1087 }, { 808, -1100 }, { 768, -1105 }, { 729, -1109 }, { 689, -1114 }, { 649, -1119 }, { 611, -1129 }, { 572, -1139 }, { 532, -1145 }, { 493, -1150 }, { 453, -1150 }, { 440, -1136 }, { 462, -1102 }, { 483, -1068 }, { 503, -1034 }, { 522, -998 }, { 539, -962 }, { 555, -926 }, { 571, -889 }, { 588, -853 }, { 606, -817 }, { 626, -783 }, { 652, -754 }, { 688, -737 }, { 724, -718 }, { 758, -698 }, { 791, -676 }, { 823, -652 }, { 855, -628 }, { 887, -604 }, { 921, -583 }, { 956, -563 }, { 950, -527 }, { 938, -488 }, { 924, -451 }, { 909, -414 }, { 890, -379 }, { 869, -345 }, { 872, -310 }, { 892, -276 }, { 911, -241 }, { 929, -205 }, { 945, -168 }, { 960, -131 }, { 974, -94 }, { 989, -57 }, { 1006, -20 }, { 1023, 16 }, { 1043, 50 }, { 1061, 86 }, { 1070, 125 }, { 1080, 163 }, { 1091, 202 }, { 1102, 240 }, { 1113, 279 }, { 1122, 318 }, { 1129, 357 }, { 1135, 397 }, { 1139, 436 }, { 1144, 476 }, { 1149, 516 }, { 1157, 555 }, { 1164, 594 }, { 1165, 634 }, { 1164, 674 }, { 1162, 714 }, { 1160, 754 }, { 1157, 794 }, { 1153, 834 }, { 1142, 872 }, { 1132, 911 }, { 1122, 950 }, { 1114, 989 }, { 1111, 1029 }, { 1104, 1068 }, { 1092, 1106 }, { 1074, 1141 }, { 1053, 1175 }, { 1050, 1180 } } },
	{ Name = "Gefängnis → Süd", Points = { { -1090, -960 }, { -1051, -970 }, { -1013, -980 }, { -973, -984 }, { -933, -986 }, { -893, -987 }, { -853, -991 }, { -814, -998 }, { -775, -995 }, { -735, -987 }, { -696, -981 }, { -656, -977 }, { -616, -977 }, { -576, -979 }, { -538, -971 }, { -501, -956 }, { -464, -942 }, { -426, -928 }, { -387, -918 }, { -348, -911 }, { -309, -903 }, { -270, -894 }, { -231, -885 }, { -192, -874 }, { -153, -866 }, { -114, -859 }, { -74, -854 }, { -34, -850 }, { 5, -844 }, { 45, -837 }, { 84, -828 }, { 122, -818 }, { 160, -806 }, { 180, -800 } } },
}

-- ---------- Tag und Nacht (DayCycle) ----------
-- Ein ganzer Tag dauert Length Sekunden (24 Minuten): hell von NightTo bis NightFrom, dazwischen Nacht (ca. 9 Minuten).
-- Nachts kommen mehr Zombies (NightZombies) und sie sehen weiter (NightSight); Feuer und Laternen sind dann die
-- einzigen Lichter.
ExtinctionConfig.Day = {
	Length = 1440,
	StartHour = 9,           -- Uhrzeit bei Serverzeit 0
	NightFrom = 20.5,
	NightTo = 5.5,
	Dusk = 1.5,              -- Stunden Dämmerung am Abend und am Morgen
	NightZombies = 1.6,      -- so viel mehr Zombies pro Spieler (und auf dem Server) in der Nacht
	NightSight = 1.35,       -- so viel weiter bemerken sie Spieler
	-- Blutmond (Ereignis, siehe ExtinctionConfig.BloodMoon): rotes Licht, noch mehr Zombies (×BloodMoonZombies), härtere Arten
	BloodMoonZombies = 1.5,
	BloodMoonKindWeights = { Walker = 40, Runner = 30, Screamer = 12, Brute = 18 },
	-- Nebel: an FogChance der Tage liegt morgens (FogFrom bis FogTo) dichter Nebel
	FogChance = 0.3,
	FogFrom = 4.5,
	FogTo = 10.5,
}

-- ---------- Aktivitäten auf der Karte (ActivityService, Teile "Act_<Art>" in Gruppe Activities) ----------
-- Nest: Zombienest zerstören (schießen); solange es lebt, kriechen Zombies heraus. Belohnung für alle, die Schaden
--       gemacht haben: Münzen und Beute direkt ins Inventar. Wächst nach Respawn Sekunden nach.
-- Cache: verschlossenes Vorratslager, E halten zum Aufbrechen (Lärm lockt Zombies an), Beute direkt ins Inventar.
-- Radio: Funkgerät am Funkturm, E halten = Notruf, ein Lootdrop kommt (Abklingzeit).
-- Survivor: Überlebender wartet in einem Ort, E halten = er folgt dir; in der Safe Zone gibt es Münzen und Beute.
--           Zombies greifen ihn an; stirbt er oder bleibt er zu weit zurück, ist die Rettung gescheitert.
ExtinctionConfig.Activities = {
	Nest = { Health = 900, Respawn = 600, SpawnEvery = 8, SpawnMin = 10, SpawnMax = 26, ActiveRange = 130, MaxAround = 6,
		Coins = 150, Table = "Tier2", Items = { 3, 5 }, RedTable = "Tier3" },
	Cache = { HoldTime = 10, Respawn = 720, Table = "Tier2", RedTable = "Tier3", Items = { 3, 5 }, Alarm = 5 },
	Radio = { HoldTime = 8, Cooldown = 900 },
	-- Überlebender: wartet in einem Ort, E halten = er folgt dir; bring ihn lebend in die Safe Zone
	Survivor = { HoldTime = 2, Respawn = 900, Coins = 250, Table = "Tier2", Items = { 2, 3 }, Speed = 15, Follow = 7,
		Lost = 90, Timeout = 480, Health = 100 },
}

-- ---------- Aufträge (MissionService) ----------
-- Jeder Spieler hat Active Aufträge gleichzeitig; erledigt gibt es Münzen und Beute direkt ins Inventar, dann kommt ein
-- neuer. Text: %d = Anzahl, %s = Ort. Event = was zählt (Zombie, Runner, Brute, RedZombie, Nest, Cache, Airdrop, Place,
-- Survivor, NightMinute).
ExtinctionConfig.Missions = {
	Active = 3,
	Pool = {
		{ Id = "Zombies", Text = "Töte %d Zombies", Event = "Zombie", Count = { 15, 30 }, Coins = 120, Table = "Tier1", Items = { 1, 2 } },
		{ Id = "Runners", Text = "Töte %d Läufer", Event = "Runner", Count = { 4, 8 }, Coins = 160, Table = "Tier2", Items = { 1, 2 } },
		{ Id = "Brutes", Text = "Töte %d Brocken", Event = "Brute", Count = { 1, 3 }, Coins = 220, Table = "Tier2", Items = { 2, 3 } },
		{ Id = "RedZombies", Text = "Töte %d Zombies in der roten Zone", Event = "RedZombie", Count = { 8, 15 }, Coins = 260,
			Table = "Tier3", Items = { 1, 2 } },
		{ Id = "Nest", Text = "Zerstöre %d Zombienest(er)", Event = "Nest", Count = { 1, 2 }, Coins = 250, Table = "Tier2", Items = { 2, 3 } },
		{ Id = "Cache", Text = "Brich %d Vorratslager auf", Event = "Cache", Count = { 2, 3 }, Coins = 180, Table = "Tier1", Items = { 1, 2 } },
		{ Id = "Airdrop", Text = "Öffne einen Lootdrop", Event = "Airdrop", Count = { 1, 1 }, Coins = 200, Table = "Tier2", Items = { 1, 2 } },
		{ Id = "Explore", Text = "Erkunde: %s", Event = "Place", Count = { 1, 1 }, Coins = 100, Table = "Tier1", Items = { 1, 2 } },
		{ Id = "Survivor", Text = "Rette einen Überlebenden", Event = "Survivor", Count = { 1, 1 }, Coins = 250, Table = "Tier2",
			Items = { 1, 2 } },
		{ Id = "Night", Text = "Überlebe %d Minuten nachts draußen", Event = "NightMinute", Count = { 2, 4 }, Coins = 220,
			Table = "Tier2", Items = { 1, 2 } },
	},
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
	RedzoneChance = 0.6,     -- Wahrscheinlichkeit, in der roten Zone zu landen
	EdgeMargin = 140,        -- Abstand zum Kartenrand
	SafeMargin = 180,        -- Abstand zur Safe Zone
	MinPlayers = 1,          -- ohne Spieler draußen gibt es keinen Abwurf
}

-- ---------- Kopfgeld (BountyService) ----------
-- Wer draußen MinKills Spieler hintereinander erledigt (ohne zu sterben), bekommt ein Kopfgeld: Base Münzen, für jeden weiteren
-- Kill PerKill mehr. Es gibt immer nur einen Gesuchten (der mit der längeren Serie übernimmt). Sein Standort blitzt nur ab und zu
-- auf der Karte auf: alle RevealEvery Sekunden für RevealTime Sekunden (der erste gleich beim Markieren), dazwischen nicht.
-- Wer ihn erledigt, kassiert das Kopfgeld. Überlebt er SurviveTime Sekunden draußen (in der Safe Zone läuft die Zeit nicht),
-- bekommt er selbst SurviveFactor davon und ist nicht mehr gesucht. Stirbt er anders (Zombies, Feuer), verfällt es.
-- Stand für die Clients: Karten-Attribut "Bounty" { UserId, Name, Reward, Left, X, Z (nur beim Aufblitzen) } (leer = niemand),
-- Spieler-Attribut "Bounty" (Höhe) beim Gesuchten.
ExtinctionConfig.Bounty = {
	Enabled = true,
	MinKills = 10,
	Base = 1000,
	PerKill = 200,
	SurviveTime = 600,
	SurviveFactor = 0.5,
	RevealEvery = 60,
	RevealTime = 8,
}

-- ---------- Bosse (BossService) ----------
-- Große Zombies, die ein Gebäude bewachen (Place = Ort aus der Gruppe Places der Karte, Teil Place_<Ort>). Ein Boss erscheint,
-- sobald ein Spieler näher als WakeRange ist, und nach dem Tod erst nach RespawnTime Sekunden wieder. Kind = Zombie-Art als
-- Grundlage, dazu Health, Scale (Größe), Damage (pro Schlag), Speed, Color (Kittel/Körper).
-- Fähigkeit "Syringe": alle AbilityEvery Sekunden wirft er eine Spritze auf den nächsten Spieler in AbilityRange: AbilityDamage
-- Schaden und SlowFactor Tempo für SlowTime Sekunden.
-- Beute in der Leiche (Tasche am Boden): Always immer, dazu jede Zeile aus Chances mit ihrer Chance; Coins für den Killer.
-- Stand für die Karte: Attribut "Bosses" [{ Id, Name, X, Z, Alive, RespawnAt }].
ExtinctionConfig.Bosses = {
	Chirurg = {
		Name = "DER CHIRURG",
		Place = "Krankenhaus",
		Kind = "Brute",
		Health = 1600,
		Scale = 1.6,
		Damage = 22,
		Speed = 13,
		Color = Color3.fromRGB(214, 218, 212),
		WakeRange = 220,
		RespawnTime = 25 * 60,
		Ability = "Syringe",
		AbilityEvery = 6,
		AbilityRange = 45,
		AbilityDamage = 12,
		SlowFactor = 0.6,
		SlowTime = 3,
		Coins = 400,
		Always = { { "Medkit", 2 }, { "Bandage", 4 } },
		Chances = {
			{ Chance = 0.05, Id = "AntiZombie", Count = 3 },
			{ Chance = 0.2, Id = "Medkit", Count = 2 },
			{ Chance = 0.12, Id = "Adrenaline", Count = 2 },
			{ Chance = 0.25, Id = "HeavyVest", Count = 1 },
			{ Chance = 0.04, Id = "Att_FastMag", Count = 1 },
		},
	},
}

-- ---------- Heli-Absturz (HeliCrashService) ----------
-- Alle MinInterval bis MaxInterval Sekunden (zuerst nach FirstDelay, nur mit MinPlayers draußen) stürzt ein Militär-Heli ab:
-- er fliegt FlyTime Sekunden mit Rauchfahne über die Karte (Ziel unbekannt) und schlägt irgendwo ein. Das Wrack brennt BurnTime
-- Sekunden (im Umkreis FireRadius alle Tick Sekunden TickDamage für alle, auch Zombies); erst danach liegen Crates Kisten am
-- Wrack (Items aus Table, BonusItems aus BonusTable, mit AttachmentChance ein Waffen-Aufsatz). Der Lärm lockt Zombies Zombies
-- Zombies an. Nach Lifetime Sekunden ist alles weg. Stand für die Clients: Karten-Attribut "HeliCrashes" [{ Id, X, Z, State, Ends }]
-- – erst ab dem Einschlag (vorher weiß niemand, wo).
ExtinctionConfig.HeliCrash = {
	Enabled = true,
	FirstDelay = 14 * 60,
	MinInterval = 20 * 60,
	MaxInterval = 32 * 60,
	MinPlayers = 1,
	FlyTime = 12,
	BurnTime = 60,
	FireRadius = 14,
	Tick = 0.5,
	TickDamage = 6,
	Crates = 2,
	Table = "Tier3",
	Items = { 3, 4 },
	BonusTable = "Airdrop",
	BonusItems = { 1, 1 },
	AttachmentChance = 0.35,
	Zombies = 10,
	Lifetime = 8 * 60,
}

-- ---------- Horden-Kiste (HordeService) ----------
-- Alle MinInterval bis MaxInterval Sekunden (zuerst nach FirstDelay, nur mit MinPlayers draußen) steht irgendwo eine verriegelte
-- Versorgungskiste mit Signalfeuer. E halten startet die Belagerung: solange Spieler im Umkreis Radius sind, läuft der
-- Fortschritt (HoldTime Sekunden für einen Spieler, jeder weitere +50 %), und bei At (Anteil) kommt eine Welle Zombies
-- (Count, Arten KindWeights) zwischen SpawnMin und SpawnMax Studs. Ist niemand mehr da, steht der Fortschritt; nach
-- PauseLimit Sekunden ohne Spieler fällt er auf 0 zurück. Bei 100 % öffnet sich die Kiste: Items aus Table, dazu
-- BonusItems aus BonusTable, Coins für alle, die mitgehalten haben. Ungeöffnet verschwindet sie nach Lifetime Sekunden.
-- Stand für die Clients: Karten-Attribut "Hordes" [{ Id, X, Z, State, Progress, Wave }].
ExtinctionConfig.Horde = {
	Enabled = true,
	FirstDelay = 9 * 60,
	MinInterval = 14 * 60,
	MaxInterval = 22 * 60,
	MinPlayers = 1,
	HoldTime = 90,
	Radius = 16,
	PauseLimit = 60,
	Lifetime = 10 * 60,
	Waves = {
		{ At = 0, Count = 8, KindWeights = { Walker = 70, Runner = 30 } },
		{ At = 0.34, Count = 12, KindWeights = { Walker = 50, Runner = 35, Screamer = 15 } },
		{ At = 0.67, Count = 16, KindWeights = { Walker = 40, Runner = 35, Brute = 25 } },
	},
	SpawnMin = 28,
	SpawnMax = 55,
	Table = "Tier3",
	Items = { 4, 5 },
	BonusTable = "Airdrop",
	BonusItems = { 1, 2 },
	Coins = 150,
}

-- ---------- Zombies ----------
-- Wenige und langsame Zombies: man kann ihnen davonlaufen (Spieler laufen 16, sprinten 24). Die Standardwerte gelten für
-- den normalen Zombie (Walker), ZombieKinds überschreibt sie je Art. Läufer und Brocken gibt es vor allem in der roten Zone und nachts.
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
	ForceExtra = 24,       -- so viele dürfen Nester, Lager-Alarm und Lootdrop-Begleiter zusätzlich über MaxTotal bringen
	KindWeights = { Walker = 86, Runner = 7, Screamer = 7 },                 -- Arten draußen am Tag
	NightKindWeights = { Walker = 64, Runner = 20, Screamer = 9, Brute = 7 }, -- nachts gefährlicher
	ScreamRange = 110,
	ScreamCalls = 3,
	ScreamCooldown = 25,
	LoseRange = 90,        -- so weit verfolgen sie ein Ziel, das sie schon haben
	AttackRange = 4.5,
	AttackDamage = 10,
	AttackDelay = 1.4,
	CorpseTime = 4,        -- Leiche ohne Beute bleibt so lange liegen
	CorpseLootTime = 40,   -- Leiche mit Beute (E durchsucht sie) bleibt so lange
	ShieldRadius = 80,     -- Anti-Zombie-Spritze: so nah am Benutzer spawnt kein Zombie (egal woher: Umgebung, Schreier, Nester ...)
}

-- Arten: Health, Walk/Run (Tempo), Damage, Coins, XP (für Agent, Spielerlevel und Battle Pass, ohne Münzen), Scale (Größe),
-- Drop (Chance auf Beute), Items (Anzahl), Table (Beute-Tabelle),
-- Eyes (Augenfarbe). Walker fehlt hier bewusst bei Werten, die in ExtinctionConfig.Zombies stehen (siehe ZombieService.Kind).
ExtinctionConfig.ZombieKinds = {
	Walker = { Name = "Zombie", Scale = 1, Drop = 0.75, Items = { 1, 1 }, Table = "Zombie", Coins = 2, XP = 10,
		Eyes = Color3.fromRGB(255, 40, 30) },
	Runner = { Name = "Läufer", Health = 70, Walk = 6, Run = 13, Damage = 8, Coins = 4, XP = 20, Scale = 0.95, Drop = 0.85, Items = { 1, 2 },
		Table = "Zombie2", Eyes = Color3.fromRGB(255, 170, 30) },
	-- Schreier: schwach, aber wenn er einen Spieler sieht, schreit er – alle Zombies im Umkreis (ScreamRange) jagen den
	-- Spieler, und ScreamCalls weitere kommen dazu (höchstens alle ScreamCooldown Sekunden)
	Screamer = { Name = "Schreier", Health = 60, Walk = 5, Run = 11, Damage = 4, Coins = 6, XP = 25, Scale = 0.92, Drop = 0.9, Items = { 1, 2 },
		Table = "Zombie2", Eyes = Color3.fromRGB(235, 240, 255), Scream = true },
	Brute = { Name = "Brocken", Health = 320, Walk = 4, Run = 7.5, Damage = 24, Coins = 12, XP = 50, Scale = 1.3, Drop = 1, Items = { 2, 3 },
		Table = "Tier2", Eyes = Color3.fromRGB(190, 70, 255) },
	-- Boss (nur im Blutmond, BloodMoonService): riesig, sehr zäh, schlägt brutal, beste Beute
	Boss = { Name = "Blutbestie", Health = 2400, Walk = 5, Run = 9.5, Damage = 42, Coins = 250, XP = 600, Scale = 2.3, Drop = 1, Items = { 5, 7 },
		Table = "Airdrop", Eyes = Color3.fromRGB(255, 20, 20), Boss = true },
}

-- ---------- Blutmond (BloodMoonService): Ereignis von Duration Sekunden ----------
-- Alle Interval Sekunden (das erste nach FirstDelay), Warnung Warning Sekunden vorher. Es wird Nacht (StartClock), das
-- Licht rot. Zombies: mehr (Day.BloodMoonZombies), härtere Arten (Day.BloodMoonKindWeights), Leben/Schaden/Tempo mal
-- Health/Damage/Speed. Beute: Tabelle eine Stufe besser (BetterTable), Drop-Chance + DropBonus, ExtraItems mehr.
-- Bosse (ZombieKinds.Boss): alle BossInterval Sekunden einer bei einem Spieler draußen, höchstens MaxBosses gleichzeitig.
ExtinctionConfig.BloodMoon = {
	Enabled = true,
	Duration = 600,
	Interval = 60 * 60,
	FirstDelay = 30 * 60,
	Warning = 60,
	StartClock = 20.4,
	Health = 1.5,
	Damage = 1.35,
	Speed = 1.12,
	DropBonus = 0.2,
	ExtraItems = 1,
	BetterTable = { Zombie = "Zombie2", Zombie2 = "Tier2", Tier2 = "Tier3", Tier3 = "Airdrop" },
	BossInterval = 150,
	FirstBoss = 45,
	MaxBosses = 2,
	BossMinDistance = 70,
	BossMaxDistance = 120,
}

-- ---------- Sturmnacht (StormService): heftiges Gewitter als Ereignis von Duration Sekunden ----------
-- Alle Interval Sekunden (das erste nach FirstDelay, nie während des Blutmonds), Warning Sekunden vorher eine Ansage.
-- Während des Sturms ist PvP für alle aus (auch in der roten Zone), danach erst nach Grace Sekunden wieder an.
-- Zombies: Zombies-mal so viele, Arten nach KindWeights, ArmoredChance davon gepanzert; alle WaveInterval Sekunden kommt
-- bei jedem Spieler draußen eine Welle (WaveSize gepanzerte und ein gepanzerter Brocken).
-- Gemeinsames Ziel: Goal gepanzerte Zombies (PerPlayer je Spieler draußen beim Start, zwischen Min und Max). Wer im Sturm
-- mindestens einen Zombie erledigt hat, bekommt am Ende Reward (Ziel erreicht: Münzen, RZ und Items ins Lager) oder
-- FailCoins (nicht erreicht).
-- Blitze: alle MinEvery bis MaxEvery Sekunden bei einem zufälligen Spieler draußen, meist MinDistance bis MaxDistance
-- entfernt, mit NearChance ganz nah (NearMin bis NearMax); Damage im Umkreis Radius für Spieler und Zombies.
-- Stand für alle: Attribute StormStart / StormEnd / StormKills / StormGoal an ReplicatedStorage, Remote StormStrike.
ExtinctionConfig.Storm = {
	Enabled = true,
	FirstDelay = 40 * 60,
	Interval = 70 * 60,
	Warning = 60,
	Duration = 600,
	Grace = 15,
	Zombies = 1.4,
	KindWeights = { Walker = 45, Runner = 30, Screamer = 10, Brute = 15 },
	ArmoredChance = 0.75,
	WaveInterval = 90,
	FirstWave = 20,
	WaveSize = 5,
	Goal = { PerPlayer = 15, Min = 20, Max = 150 },
	Reward = { Coins = 500, RedPoints = 15, Items = { { "Airdrop", 2 }, { "Tier3", 2 } } },
	FailCoins = 150,
	Lightning = { MinEvery = 5, MaxEvery = 12, MinDistance = 25, MaxDistance = 90, NearChance = 0.2, NearMin = 8,
		NearMax = 16, Radius = 9, Damage = 30 },
}

-- ---------- Gepanzerte Zombies (ZombieService, Damage) ----------
-- Helm und Weste schlucken Schaden: Helm nur bei Kopftreffern (HelmetFactor des Schadens, bis Helmet aufgebraucht ist,
-- dann fliegt er weg), Weste bei allen anderen Treffern (VestFactor, bis Vest aufgebraucht). Außerhalb des Sturms ist ein
-- Zombie mit Chance gepanzert, in der roten Zone mit RedzoneChance. Gepanzerte geben CoinFactor-mal Münzen und XPFactor-mal XP.
ExtinctionConfig.ArmoredZombies = {
	Chance = 0.04,
	RedzoneChance = 0.12,
	Helmet = 60,
	HelmetFactor = 0.8,
	Vest = 120,
	VestFactor = 0.7,
	CoinFactor = 2,
	XPFactor = 1.5,
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

-- Stapel größer machen (factor), höchstens bis MaxStack; Waffen und Fahrzeuge bleiben einzeln. Ändert items selbst.
function ExtinctionConfig.BigStacks(items, factor)
	for _, item in items do
		local config = ExtinctionConfig.Items[item.Id]
		local max = config and config.MaxStack or 1
		if max > 1 then
			item.Count = math.min(max, math.ceil(item.Count * factor))
		end
	end
	return items
end

-- Beute in der roten Zone (Redzone.Loot): Tabelle eine Stufe besser, ExtraItems mehr, größere Stapel
function ExtinctionConfig.RedzoneRoll(tableName, count, random)
	local L = ExtinctionConfig.Redzone.Loot
	local items = ExtinctionConfig.RollLoot(L.BetterTable[tableName] or tableName, count + L.ExtraItems, random)
	return ExtinctionConfig.BigStacks(items, L.StackFactor)
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
	if not item or item.Kit then
		return 0
	end
	local price = item.Price or item.Value or (item.Tier or 0) * 60 + 40
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

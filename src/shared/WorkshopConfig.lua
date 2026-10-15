-- WorkshopConfig (ModuleScript, Server und Client)
-- Was man im Versteck selbst machen kann (zusätzlich zu den Modulen in HideoutConfig):
--   WERKBANK      aus Items (Tasche oder Lager) neue herstellen; ein Auftrag gleichzeitig, dauert echte Zeit (auch offline),
--                 fertig ins Lager abholen. Bessere Rezepte ab höherer Versteckstufe; die Werkbank (Modul) macht schneller.
--   FUNKAUFTRÄGE  jeden Tag (UTC) drei Spezialaufträge mit Belohnungen, die es sonst nicht gibt (Dungeon-Schlüssel, RZ …)
--   SCHIESSSTAND  im Camp neben dem Versteck: E am Stand startet eine Runde, Ziele klappen auf, Treffer zählen;
--                 nur dort darf man in der Safe Zone schießen (nur auf die Ziele), Munition ist dort gratis.
-- Stände im Profil unter Hideout: Craft = { Id, Done }, Contracts = { Day, List = { { Base, Claimed } } },
-- RangeBest, RangeDay (Tag der letzten Tagesbelohnung).

local WorkshopConfig = {}

-- ---------- Werkbank ----------
-- Items = { { Id, Anzahl } } aus Tasche oder Lager, Coins dazu; Out = { Id, Anzahl }; Time in Sekunden; Tier = nötige
-- Versteckstufe
WorkshopConfig.Recipes = {
	{ Id = "Medkit", Tier = 1, Items = { { "Bandage", 4 } }, Coins = 0, Out = { "Medkit", 1 }, Time = 60 },
	{ Id = "Shells", Tier = 1, Items = { { "Ammo_9mm", 60 } }, Coins = 20, Out = { "Ammo_Shell", 24 }, Time = 90 },
	{ Id = "Molotov", Tier = 1, Items = { { "Bandage", 2 } }, Coins = 80, Out = { "Molotov", 1 }, Time = 120 },
	{ Id = "RifleAmmo", Tier = 2, Items = { { "Ammo_9mm", 90 } }, Coins = 60, Out = { "Ammo_Rifle", 30 }, Time = 180 },
	{ Id = "Adrenaline", Tier = 2, Items = { { "Medkit", 2 } }, Coins = 60, Out = { "Adrenaline", 1 }, Time = 240 },
	{ Id = "Grenade", Tier = 2, Items = { { "Molotov", 1 }, { "Ammo_Rifle", 30 } }, Coins = 100, Out = { "Grenade", 1 }, Time = 300 },
	{ Id = "AntiZombie", Tier = 3, Items = { { "Adrenaline", 1 }, { "Medkit", 1 } }, Coins = 150, Out = { "AntiZombie", 1 }, Time = 600 },
	{ Id = "HeavyVest", Tier = 3, Items = { { "Vest", 2 } }, Coins = 300, Out = { "HeavyVest", 1 }, Time = 900 },
	{ Id = "DungeonKey", Tier = 4, Items = { { "Grenade", 2 }, { "HeavyVest", 1 } }, Coins = 2000, Out = { "DungeonKey", 1 },
		Time = 1800 },
}
-- Werkbank-Modul (HideoutConfig, Id "Workbench"): je Ausbaustufe so viel Prozent schneller
WorkshopConfig.SpeedPerLevel = 15

function WorkshopConfig.Recipe(id)
	for _, recipe in WorkshopConfig.Recipes do
		if recipe.Id == id then
			return recipe
		end
	end
	return nil
end

-- Dauer eines Rezepts mit der Werkbank-Stufe (Sekunden, ganz)
function WorkshopConfig.CraftTime(recipe, workbenchLevel)
	local factor = 1 - math.clamp((workbenchLevel or 0) * WorkshopConfig.SpeedPerLevel, 0, 60) / 100
	return math.max(5, math.floor(recipe.Time * factor + 0.5))
end

-- ---------- Funkaufträge ----------
WorkshopConfig.ContractsPerDay = 3
WorkshopConfig.ContractTier = 1 -- ab dieser Versteckstufe
-- Stat = Statistik im Profil (zählt ab dem ersten Blick am Tag); Reward = { Coins, RedPoints, XP, Items = { { Id, Anzahl } } }
WorkshopConfig.Contracts = {
	{ Id = "Convoy", Stat = "ExtConvoys", Need = 1, Text = "Fang einen Konvoi ab",
		Reward = { Coins = 1500, RedPoints = 40, XP = 400 } },
	{ Id = "Airdrops", Stat = "ExtAirdrops", Need = 2, Text = "Plündere {1} Lootdrops",
		Reward = { Coins = 800, XP = 300, Items = { { "DungeonKey", 1 } } } },
	{ Id = "Brutes", Stat = "ExtBrutes", Need = 8, Text = "Erledige {1} Brocken",
		Reward = { Coins = 1000, XP = 300, Items = { { "Grenade", 2 } } } },
	{ Id = "Hunter", Stat = "ExtPlayerKills", Need = 5, Text = "Erledige {1} Spieler",
		Reward = { RedPoints = 60, XP = 400 } },
	{ Id = "Nests", Stat = "ExtNests", Need = 2, Text = "Zerstöre {1} Zombienester",
		Reward = { Coins = 600, XP = 300, Items = { { "HeavyVest", 1 } } } },
	{ Id = "Caches", Stat = "ExtCaches", Need = 5, Text = "Brich {1} Vorratslager auf",
		Reward = { Coins = 600, XP = 250, Items = { { "AntiZombie", 2 } } } },
	{ Id = "Survivors", Stat = "ExtSurvivors", Need = 3, Text = "Rette {1} Überlebende",
		Reward = { Coins = 700, XP = 300, Items = { { "Adrenaline", 2 } } } },
	{ Id = "Bandits", Stat = "ExtBotKills", Need = 25, Text = "Erledige {1} Banditen",
		Reward = { Coins = 1500, XP = 350 } },
	{ Id = "Horde", Stat = "ExtZombies", Need = 250, Text = "Erledige {1} Zombies",
		Reward = { Coins = 1000, XP = 300, Items = { { "Medkit", 2 } } } },
}

-- Tag (UTC) als Zahl
function WorkshopConfig.Day(now)
	return math.floor((now or os.time()) / 86400)
end

-- Die drei Aufträge eines Tages (für alle gleich, ohne doppelte): Liste von Auftrags-Einträgen
function WorkshopConfig.ContractsFor(day)
	-- eigene kleine Zufallsfolge aus dem Tag (kein Random-Objekt je Aufruf; die Funktion läuft oft)
	local pool = table.clone(WorkshopConfig.Contracts)
	local state = (day * 7919 + 13) % 2147483647
	local list = {}
	for _ = 1, math.min(WorkshopConfig.ContractsPerDay, #pool) do
		state = (state * 48271) % 2147483647
		table.insert(list, table.remove(pool, state % #pool + 1))
	end
	return list
end

-- ---------- Schießstand ----------
WorkshopConfig.Range = {
	Point = "Range_Start",     -- E-Aufforderung am Stand (Gruppe Zentrale)
	Zone = "Range_Zone",       -- dort darf man schießen (nur auf die Ziele)
	Targets = "Range_Target",  -- Ziele heißen Range_Target1, Range_Target2 … (Gruppe Zentrale)
	Duration = 30,             -- Sekunden je Runde
	UpTime = 2.2,              -- so lange steht ein Ziel
	Gap = 0.35,                -- Pause zwischen zwei Zielen
	Points = 10,               -- je Treffer
	Bullseye = 25,             -- Treffer in die Mitte (Kopf des Ziels)
	DailyScore = 200,          -- ab so vielen Punkten gibt es einmal am Tag die Belohnung
	DailyCoins = 300,
}

return WorkshopConfig

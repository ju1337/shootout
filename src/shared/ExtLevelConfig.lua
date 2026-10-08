-- ExtLevelConfig (ModuleScript)
-- Extinction-Level: eigene Erfahrung für die offene Welt (EP), gesammelt mit Zombies, Spielern, Bots, Nestern, Lagern,
-- Überlebenden, Lootdrops, dem Konvoi und Aufträgen (ExtLevelService). Gespeichert als Statistik "ExtXP" (Profil Stats).
-- Ab bestimmten Leveln gibt es Titel (über dem Kopf, Fenster TITEL), die TitleConfig aus Titles übernimmt.
-- Spieler-Attribute: ExtLevel, ExtXP (gesamt).

local ExtLevelConfig = {}

ExtLevelConfig.MaxLevel = 50
ExtLevelConfig.Stat = "ExtXP"

-- EP pro Ereignis
ExtLevelConfig.Rewards = {
	Zombie = 8,        -- normaler Zombie (Läufer, Brocken, Schreier: siehe Kinds)
	RedZombie = 6,     -- zusätzlich in der roten Zone
	PlayerKill = 120,
	BotKill = 60,
	Nest = 150,
	Cache = 80,
	Survivor = 200,
	Radio = 40,
	Airdrop = 120,
	Convoy = 300,
	Mission = 150,
}
ExtLevelConfig.Kinds = { Runner = 14, Brute = 30, Screamer = 16 }

-- EP von Level l auf l + 1
function ExtLevelConfig.XPForLevel(level)
	return 400 + 120 * (level - 1)
end

-- Gesamt-EP, um Level level zu erreichen (Level 1 = 0)
function ExtLevelConfig.TotalFor(level)
	local total = 0
	for l = 1, math.min(level, ExtLevelConfig.MaxLevel) - 1 do
		total += ExtLevelConfig.XPForLevel(l)
	end
	return total
end

-- Level aus Gesamt-EP: level, EP im aktuellen Level, EP für das nächste (0 auf MaxLevel)
function ExtLevelConfig.FromXP(xp)
	xp = math.max(0, math.floor(tonumber(xp) or 0))
	local level = 1
	while level < ExtLevelConfig.MaxLevel and xp >= ExtLevelConfig.XPForLevel(level) do
		xp -= ExtLevelConfig.XPForLevel(level)
		level += 1
	end
	if level >= ExtLevelConfig.MaxLevel then
		return ExtLevelConfig.MaxLevel, 0, 0
	end
	return level, xp, ExtLevelConfig.XPForLevel(level)
end

-- Titel ab einem Level (TitleConfig übernimmt sie mit Stat = ExtXP und Goal = TotalFor(Level))
ExtLevelConfig.Titles = {
	{ Level = 5, Id = "Ext_Ueberlebender", Name = "Überlebender", Color = Color3.fromRGB(150, 190, 130) },
	{ Level = 10, Id = "Ext_Pluenderer", Name = "Plünderer", Color = Color3.fromRGB(200, 170, 110) },
	{ Level = 20, Id = "Ext_Jaeger", Name = "Ödland-Jäger", Color = Color3.fromRGB(210, 130, 80) },
	{ Level = 30, Id = "Ext_Raeuber", Name = "Konvoi-Räuber", Color = Color3.fromRGB(226, 90, 70) },
	{ Level = 40, Id = "Ext_Legende", Name = "Legende von Ödstadt", Color = Color3.fromRGB(240, 196, 70) },
}

-- Titel, der bei genau diesem Level freigeschaltet wird (oder nil)
function ExtLevelConfig.TitleAt(level)
	for _, title in ExtLevelConfig.Titles do
		if title.Level == level then
			return title
		end
	end
	return nil
end

return ExtLevelConfig

-- LevelConfig (ModuleScript)
-- Spielerlevel (1 bis MaxLevel) aus allen gesammelten XP, unabhängig vom Agenten.
-- Auf MaxLevel kann man prestigen: Level zurück auf 1, Prestige-Stufe +1 (bis MaxPrestige),
-- dafür Münzen und ein farbiges Prestige-Abzeichen. Agenten-Level bleiben erhalten.
-- Spieler-Attribute: AccountXP (XP seit dem letzten Prestige), Prestige (0 bis MaxPrestige)

local LevelConfig = {}

LevelConfig.MaxLevel = 100
LevelConfig.MaxPrestige = 10
LevelConfig.PrestigeCoins = 2500 -- Belohnung pro Prestige (mal Prestige-Stufe)

-- XP, um von Level l auf l + 1 zu kommen (steigt langsam an)
function LevelConfig.XPForLevel(level)
	return 1000 + 25 * (level - 1)
end

-- Gesamt-XP bis Level MaxLevel
local total = 0
for level = 1, LevelConfig.MaxLevel - 1 do
	total += LevelConfig.XPForLevel(level)
end
LevelConfig.MaxXP = total

-- Level aus XP: level, XP im aktuellen Level, XP für das nächste Level (0 auf MaxLevel)
function LevelConfig.FromXP(xp)
	xp = math.clamp(xp or 0, 0, LevelConfig.MaxXP)
	local level = 1
	while level < LevelConfig.MaxLevel and xp >= LevelConfig.XPForLevel(level) do
		xp -= LevelConfig.XPForLevel(level)
		level += 1
	end
	local needed = level < LevelConfig.MaxLevel and LevelConfig.XPForLevel(level) or 0
	return level, xp, needed
end

-- Farben der Prestige-Stufen (Abzeichen); Stufe 0 = Standard-Cyan
LevelConfig.PrestigeColors = {
	[0] = Color3.fromRGB(40, 210, 230),
	Color3.fromRGB(190, 120, 70),   -- 1 Bronze
	Color3.fromRGB(190, 195, 205),  -- 2 Silber
	Color3.fromRGB(240, 195, 60),   -- 3 Gold
	Color3.fromRGB(90, 220, 200),   -- 4 Platin
	Color3.fromRGB(110, 170, 255),  -- 5 Diamant
	Color3.fromRGB(80, 210, 130),   -- 6 Smaragd
	Color3.fromRGB(225, 55, 65),    -- 7 Rubin
	Color3.fromRGB(220, 90, 255),   -- 8 Amethyst
	Color3.fromRGB(255, 140, 40),   -- 9 Inferno
	Color3.fromRGB(255, 255, 255),  -- 10 Legende
}

-- Alles Wichtige zu einem Spieler: { Level, Prestige, XP, Needed, Progress, Color, CanPrestige, Total }
-- Total = Prestige * MaxLevel + Level (z.B. für Level-Voraussetzungen wie Ranked)
function LevelConfig.Get(player)
	local prestige = player:GetAttribute("Prestige") or 0
	local level, xp, needed = LevelConfig.FromXP(player:GetAttribute("AccountXP") or 0)
	return {
		Level = level,
		Prestige = prestige,
		XP = xp,
		Needed = needed,
		Progress = needed > 0 and xp / needed or 1,
		Color = LevelConfig.PrestigeColors[math.min(prestige, LevelConfig.MaxPrestige)],
		CanPrestige = level >= LevelConfig.MaxLevel and prestige < LevelConfig.MaxPrestige,
		Total = prestige * LevelConfig.MaxLevel + level,
	}
end

-- Kurzer Text wie "LV 42" bzw. "P3 · LV 42"
function LevelConfig.Display(player)
	local info = LevelConfig.Get(player)
	return (info.Prestige > 0 and ("P" .. info.Prestige .. " · ") or "") .. "LV " .. info.Level
end

return LevelConfig

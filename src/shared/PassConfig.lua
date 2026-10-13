-- PassConfig (ModuleScript)
-- Kostenloser Battle Pass: Pass-XP gibt es für alle XP im Spiel und für abgeholte Aufträge.
-- Jede Stufe schaltet ihre Belohnung automatisch frei (Münzen oder exklusiver Skin).
-- Saisons laufen automatisch (Julio 2026-10-13): Saison 1 beginnt am Montag, 12.10.2026 (0 Uhr UTC), jede dauert
-- SeasonLength. Mit einer neuen Saison fängt der Pass bei Stufe 0 an (ProgressService setzt PassXP zurück, Profil
-- PassSeason), freigeschaltete Skins bleiben. Jede Saison hat drei eigene Skins (Stufe 10, 20, 30, Pass = true in
-- Cosmetics); gibt es mehr Saisons als Einträge in Seasons, fängt die Liste wieder von vorn an.
-- Spieler-Attribute "PassXP" und "PassSeason".
-- Belohnung pro Stufe: { Coins = n } oder { Item = "<Cosmetics-Id>" }

local PassConfig = {}

PassConfig.SeasonStart = 1791763200 -- Montag, 12.10.2026, 0 Uhr UTC
PassConfig.SeasonLength = 6 * 7 * 24 * 3600 -- 6 Wochen
PassConfig.XPPerTier = 1000
PassConfig.QuestXP = 300 -- Pass-XP pro abgeholtem Auftrag
PassConfig.TierCount = 30

-- Titel und Skins (Stufe 10, 20, 30) je Saison
PassConfig.Seasons = {
	{ Title = "ERSTER EINSATZ", Skins = { "W_Saison", "W_Saison_Elite", "W_Goldrausch" } },
	{ Title = "ASCHEREGEN", Skins = { "W_Asche", "W_Asche_Elite", "W_Glutkern" } },
	{ Title = "EISZEIT", Skins = { "W_Frost", "W_Frost_Elite", "W_Polarlicht" } },
}

-- Nummer der laufenden Saison (ab 1)
function PassConfig.CurrentSeason(now)
	now = now or os.time()
	return math.max(1, math.floor((now - PassConfig.SeasonStart) / PassConfig.SeasonLength) + 1)
end

-- Sekunden bis zum Ende der laufenden Saison
function PassConfig.SeasonLeft(now)
	now = now or os.time()
	local season = PassConfig.CurrentSeason(now)
	return math.max(0, PassConfig.SeasonStart + season * PassConfig.SeasonLength - now)
end

local function seasonEntry(season)
	return PassConfig.Seasons[((math.max(1, season or 1) - 1) % #PassConfig.Seasons) + 1]
end

-- Name der Saison, z.B. "SAISON 2 · ASCHEREGEN"
function PassConfig.SeasonName(season)
	season = season or PassConfig.CurrentSeason()
	return "SAISON " .. season .. " · " .. seasonEntry(season).Title
end

-- Belohnungen aller Stufen einer Saison
local tierCache = {}
function PassConfig.TiersFor(season)
	season = season or PassConfig.CurrentSeason()
	local entry = seasonEntry(season)
	if tierCache[entry] then
		return tierCache[entry]
	end
	local tiers = {}
	for tier = 1, PassConfig.TierCount do
		if tier % 10 == 0 then
			tiers[tier] = { Item = entry.Skins[tier // 10] }
		else
			tiers[tier] = { Coins = tier % 5 == 0 and 300 or 100 }
		end
	end
	tierCache[entry] = tiers
	return tiers
end

-- Stufen der Saison beim Laden (für Prüfungen und alten Code; live immer TiersFor benutzen)
PassConfig.Tiers = PassConfig.TiersFor()

-- Erreichte Stufe (0 bis Anzahl Stufen) und Fortschritt in der nächsten Stufe (0 bis 1)
function PassConfig.TierFromXP(xp)
	local tier = math.min(PassConfig.TierCount, math.floor((xp or 0) / PassConfig.XPPerTier))
	local progress = tier >= PassConfig.TierCount and 1 or ((xp or 0) % PassConfig.XPPerTier) / PassConfig.XPPerTier
	return tier, progress
end

return PassConfig

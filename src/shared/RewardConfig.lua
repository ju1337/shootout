-- RewardConfig (ModuleScript)
-- Belohnungen außer den laufenden XP/Münzen pro Aktion:
--   Killserien (Kills ohne zu sterben), Spielerlevel-Meilensteine (Münzen in jedem Prestige-Durchgang neu,
--   Skins einmalig), Prestige-Belohnungen (exklusive Skins), Rang-Meilensteine pro Saison (erster Aufstieg).
-- Laufende Belohnungen: XP pro Aktion stehen in AgentConfig.XPRewards, Münzen = 25 pro 100 XP
-- (Cosmetics.CoinsPerXP), Aufträge in QuestConfig. Vergeben wird alles vom RewardService (Server).

local RewardConfig = {}

-- Übersicht der laufenden Belohnungen (nur für die Anzeige im Belohnungs-Fenster)
RewardConfig.PerAction = {
	{ "Kill", "100 XP · 25 Münzen" },
	{ "Kopfschuss-Kill", "+25 XP" },
	{ "Assist", "30 XP" },
	{ "Wiederbeleben", "50 XP" },
	{ "Multikill", "+25 XP je Kill in Folge" },
	{ "Clutch / ACE", "100 XP je Gegner / 300 XP" },
	{ "Rundensieg", "150 XP" },
	{ "Matchsieg", "400 XP · 100 Münzen" },
	{ "Rache", "75 Münzen" },
	{ "Serie beendet", "100 Münzen" },
}

-- Kill-Boni: Rache (den letzten eigenen Killer erledigen), Serie beendet (Gegner mit Killserie ab 5 stoppen)
RewardConfig.Revenge = { Coins = 75, Name = "RACHE" }
RewardConfig.Shutdown = { Coins = 100, Name = "SERIE BEENDET", MinStreak = 5 }

-- Killserien: Kills ohne zu sterben (in jedem Modus) -> Münzen
RewardConfig.Streaks = {
	{ Kills = 5, Coins = 150, Name = "KILLSERIE 5" },
	{ Kills = 10, Coins = 400, Name = "KILLSERIE 10 · UNAUFHALTSAM" },
	{ Kills = 15, Coins = 750, Name = "KILLSERIE 15 · LEGENDÄR" },
	{ Kills = 20, Coins = 1200, Name = "KILLSERIE 20 · GÖTTLICH" },
}

-- Spielerlevel: Münzen gibt es in jedem Prestige-Durchgang wieder, Skins nur einmal
RewardConfig.Level = {}
for level = 5, 100, 5 do
	table.insert(RewardConfig.Level, { Level = level, Coins = 200 + level * 12 })
end
local LEVEL_ITEMS = { [10] = "W_Rekrut", [25] = "W_Veteran", [50] = "W_Elite", [75] = "W_Spezialist", [100] = "W_Grossmeister" }
for _, milestone in RewardConfig.Level do
	milestone.Item = LEVEL_ITEMS[milestone.Level]
end

-- Prestige: exklusive Skins (Münzen gibt es beim Prestigen selbst, siehe LevelConfig.PrestigeCoins)
RewardConfig.Prestige = {
	{ Prestige = 1, Item = "W_PrestigeBronze" },
	{ Prestige = 3, Item = "W_PrestigeGold" },
	{ Prestige = 5, Item = "W_PrestigeDiamant" },
	{ Prestige = 7, Item = "W_PrestigeRubin" },
	{ Prestige = 10, Item = "W_PrestigeLegende" },
}

-- Rang: erster Aufstieg in einer Saison (Name wie in RankConfig.Tiers)
RewardConfig.Rank = {
	{ Tier = "Silber", Coins = 300 },
	{ Tier = "Gold", Coins = 600 },
	{ Tier = "Platin", Coins = 1000 },
	{ Tier = "Diamant", Coins = 1500 },
	{ Tier = "Meister", Coins = 2500, Item = "W_SaisonMeister" },
}

-- Saison-Ende: Belohnung nach dem höchsten Rang der abgelaufenen Saison (nur mit abgeschlossenen
-- Platzierungsspielen). Skins gibt es ab Gold; schon im Besitz = nur Münzen.
RewardConfig.SeasonEnd = {
	{ Tier = "Bronze", Coins = 250 },
	{ Tier = "Silber", Coins = 500 },
	{ Tier = "Gold", Coins = 1000, Item = "W_SE_Gold" },
	{ Tier = "Platin", Coins = 1500, Item = "W_SE_Platin" },
	{ Tier = "Diamant", Coins = 2500, Item = "W_SE_Diamant" },
	{ Tier = "Meister", Coins = 4000, Item = "W_SE_Champion" },
}

return RewardConfig

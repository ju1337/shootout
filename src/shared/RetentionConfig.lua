-- RetentionConfig (ModuleScript)
-- Gründe zum Wiederkommen (Julio 2026-10-13), Server: RetentionService, ClanService, LeaderboardService.
--   Comeback      Rückkehr-Bonus: wer AwayDays Tage oder länger nicht da war, bekommt beim nächsten Betreten der offenen
--                 Welt Münzen, Items ins Lager und Doppel-XP (Profil LastSeen, ComebackPending).
--   FriendBonus   Freunde-Bonus: mit mindestens einem Roblox-Freund im selben Squad gibt es Percent Prozent mehr XP und
--                 Münzen aus dem Spiel (nur die Gründe in Reasons, nicht Verkäufe, Markt, Robux, Kisten usw.).
--                 Spieler-Attribut "FriendBonus" (true/nil).
--   DungeonWeek   Dungeon-Wochenrekord: höchste Welle, mit der man diese Woche lebend durchs Portal kam (Profil
--                 DungeonWeek = { Week, Best }). Tafel an der Ruhmeswand (Leaderboard_DungeonWeek). Wer am Ende einer
--                 Woche unter den besten Top Spielern war, bekommt beim nächsten Besuch Münzen (Rewards) und die Statistik
--                 Stat (+1, Titel "Katakomben-Champion").
--   Clan          Clan-Punkte für Zombies und Aufträge der Mitglieder: Clan-Stufe aus allen Punkten, Wochenziel in
--                 Stufen (Stages) mit Münzen für jedes Mitglied mit eigenem Beitrag, Clan-Bestenliste (Leaderboard_Clans).
-- Wochen beginnen montags 0 Uhr UTC (QuestConfig.Week).

local RetentionConfig = {}

RetentionConfig.Comeback = {
	AwayDays = 7,
	Coins = 1000,
	Items = { { "DungeonKey", 1 }, { "Medkit", 2 }, { "Ammo_Rifle", 120 } },
	BoostMinutes = 60, -- Doppel-XP
}

RetentionConfig.FriendBonus = {
	Percent = 10,
	-- Münzen aus diesen Gründen (ProgressService.AddCoins) bekommen den Bonus
	Reasons = {
		Zombie = true, Nest = true, Rettung = true, Sturmnacht = true, Boss = true, Dungeon = true, Kopfgeld = true,
		["Kopfgeld überlebt"] = true, ["Spieler erledigt"] = true, ["Bot erledigt"] = true, Auftrag = true,
		Ereignis = true, -- Lootdrop, Konvoi, Heli-Absturz, Horde (Modes/Extinction)
	},
}

RetentionConfig.DungeonWeek = {
	Top = 10,
	-- Platz bis einschließlich Place: Münzen
	Rewards = { { Place = 1, Coins = 5000 }, { Place = 3, Coins = 3000 }, { Place = 10, Coins = 1500 } },
	Stat = "DungeonTop",
}

RetentionConfig.Clan = {
	-- Punkte je Statistik-Zuwachs eines Mitglieds (ProgressService.AddStat)
	Points = { Zombies = 1, ExtMissions = 25 },
	-- Wochenziel: jede erreichte Stufe gibt jedem Mitglied einmal pro Woche Münzen
	Stages = { { Goal = 2500, Coins = 300 }, { Goal = 7500, Coins = 600 }, { Goal = 15000, Coins = 1200 } },
	MinContribution = 100, -- eigene Punkte in der Woche, damit man die Münzen des Wochenziels bekommt
	LevelPoints = 2000, -- Punkte für Stufe 2; jede weitere Stufe braucht LevelPoints mehr als die davor
	MaxLevel = 50,
	FlushEvery = 30,    -- Sekunden: gesammelte Punkte in den DataStore schreiben
}

-- Münzen für einen Platz im Dungeon-Wochenrekord (nil = kein Preis)
function RetentionConfig.DungeonReward(place)
	for _, entry in RetentionConfig.DungeonWeek.Rewards do
		if place <= entry.Place then
			return entry.Coins
		end
	end
	return nil
end

-- OrderedDataStore der Tafel einer Woche (Schlüssel UserId, Wert beste Welle)
function RetentionConfig.DungeonStoreName(week)
	return "LB_DungeonWeek_" .. week .. "_v1"
end

-- Punkte, die Stufe level insgesamt braucht (Stufe 1 = 0)
function RetentionConfig.ClanLevelPoints(level)
	local n = level - 1
	return RetentionConfig.Clan.LevelPoints * n * (n + 1) / 2
end

-- Clan-Stufe zu allen Punkten und Fortschritt (0 bis 1) zur nächsten
function RetentionConfig.ClanLevel(points)
	points = tonumber(points) or 0
	local level = 1
	while level < RetentionConfig.Clan.MaxLevel and points >= RetentionConfig.ClanLevelPoints(level + 1) do
		level += 1
	end
	if level >= RetentionConfig.Clan.MaxLevel then
		return level, 1
	end
	local from, to = RetentionConfig.ClanLevelPoints(level), RetentionConfig.ClanLevelPoints(level + 1)
	return level, (points - from) / (to - from)
end

-- Erreichte Stufe des Wochenziels (0 bis #Stages)
function RetentionConfig.ClanStage(points)
	local stage = 0
	for i, entry in RetentionConfig.Clan.Stages do
		if (tonumber(points) or 0) >= entry.Goal then
			stage = i
		end
	end
	return stage
end

return RetentionConfig

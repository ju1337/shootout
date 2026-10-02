-- Medals (ModuleScript)
-- Medaillen im Stil von Call of Duty: Mehrfach-Kills, Killserien und besondere Kills. Der Server vergibt sie
-- (KillService, TeamRoundMode, Ziele) und schickt sie über Remotes.Notify ("Medal") an den Spieler, die
-- Anzeige baut Notifications.
--   Title  Text der Medaille (Großbuchstaben)
--   Tier   1 = normal (weiß), 2 = selten (Bernstein), 3 = stark (Orange), 4 = legendär (Rot)
--   Icon   Symbol im Abzeichen (zeichnet Notifications)
--   XP     Bonus-XP (0 = keine)
--   Group  Medaillen derselben Gruppe ersetzen sich sofort (DOPPEL-KILL -> TRIPLE-KILL ...)
--   Count  Zahl im Abzeichen (Mehrfach-Kills, Killserien)
-- Ein Eintrag in der Liste, die der Server schickt: { Id, Xp (vergebene XP), Coins (vergebene Münzen), Sub
-- (Zusatztext), Title (statt des Standard-Titels), Count (statt des Standard-Werts, z.B. Gegner beim Clutch) }

local Medals = {}

Medals.List = {
	-- Mehrfach-Kills: Kills kurz hintereinander (KillService.MULTI_WINDOW)
	DoubleKill = { Title = "DOPPEL-KILL", Tier = 1, Icon = "Multi", XP = 50, Group = "Multi", Count = 2 },
	TripleKill = { Title = "TRIPLE-KILL", Tier = 2, Icon = "Multi", XP = 75, Group = "Multi", Count = 3 },
	FuryKill = { Title = "FURY-KILL", Tier = 3, Icon = "Multi", XP = 100, Group = "Multi", Count = 4 },
	FrenzyKill = { Title = "FRENZY-KILL", Tier = 3, Icon = "Multi", XP = 125, Group = "Multi", Count = 5 },
	SuperKill = { Title = "SUPER-KILL", Tier = 4, Icon = "Multi", XP = 150, Group = "Multi", Count = 6 },
	MegaKill = { Title = "MEGA-KILL", Tier = 4, Icon = "Multi", XP = 175, Group = "Multi", Count = 7 },
	UltraKill = { Title = "ULTRA-KILL", Tier = 4, Icon = "Multi", XP = 200, Group = "Multi", Count = 8 },
	KillChain = { Title = "KILL-KETTE", Tier = 4, Icon = "Multi", XP = 250, Group = "Multi", Count = 9 },

	-- Killserien: Kills ohne zu sterben (Münzen dazu aus RewardConfig.Streaks)
	Streak3 = { Title = "KILLSERIE", Tier = 1, Icon = "Streak", XP = 50, Count = 3 },
	Streak5 = { Title = "GNADENLOS", Tier = 2, Icon = "Streak", XP = 100, Count = 5 },
	Streak10 = { Title = "UNAUFHALTSAM", Tier = 3, Icon = "Streak", XP = 200, Count = 10 },
	Streak15 = { Title = "LEGENDÄR", Tier = 3, Icon = "Streak", XP = 300, Count = 15 },
	Streak20 = { Title = "GÖTTLICH", Tier = 4, Icon = "Streak", XP = 400, Count = 20 },
	Streak25 = { Title = "NUKLEAR", Tier = 4, Icon = "Streak", XP = 500, Count = 25 },
	Streak30 = { Title = "UNANTASTBAR", Tier = 4, Icon = "Streak", XP = 600, Count = 30 },

	-- Besondere Kills
	FirstBlood = { Title = "ERSTES BLUT", Tier = 2, Icon = "Blood", XP = 50 },
	Revenge = { Title = "RACHE", Tier = 1, Icon = "Revenge", XP = 50 },
	Longshot = { Title = "WEITSCHUSS", Tier = 1, Icon = "Longshot", XP = 50 },
	Headshot = { Title = "KOPFSCHUSS", Tier = 1, Icon = "Headshot", XP = 0 }, -- Kopfschuss-XP stecken schon im Kill
	Buzzkill = { Title = "SERIE BEENDET", Tier = 1, Icon = "Buzzkill", XP = 50 },
	Comeback = { Title = "COMEBACK", Tier = 1, Icon = "Comeback", XP = 50 },

	-- Runde und Ziele
	Clutch = { Title = "CLUTCH", Tier = 4, Icon = "Clutch", XP = 0 }, -- XP vergibt TeamRoundMode (100 pro Gegner)
	Ace = { Title = "ACE", Tier = 4, Icon = "Ace", XP = 0 },          -- XP vergibt TeamRoundMode
	BombPlanted = { Title = "BOMBE GELEGT", Tier = 2, Icon = "Bomb", XP = 0 },
	BombDefused = { Title = "ENTSCHÄRFT", Tier = 3, Icon = "Defuse", XP = 0 },
	Captured = { Title = "EINGENOMMEN", Tier = 1, Icon = "Flag", XP = 0 },
	Hacked = { Title = "GEHACKT", Tier = 3, Icon = "Hack", XP = 0 },

	-- Ultimate ausgelöst (wie eine Killstreak-Belohnung bei CoD)
	Ultimate = { Title = "ÜBERLADUNG", Tier = 3, Icon = "Ultimate", XP = 0 },
}

-- Mehrfach-Kills nach Anzahl (ab 9: KILL-KETTE)
local MULTI = { "DoubleKill", "TripleKill", "FuryKill", "FrenzyKill", "SuperKill", "MegaKill", "UltraKill" }

-- Killserien: bei genau diesen Kill-Zahlen gibt es eine Medaille
Medals.StreakSteps = { 3, 5, 10, 15, 20, 25, 30 }

function Medals.Get(id)
	return Medals.List[id]
end

-- Medaille für count Kills kurz hintereinander (nil unter 2)
function Medals.ForMulti(count)
	if count < 2 then
		return nil
	end
	return MULTI[count - 1] or "KillChain"
end

-- Medaille, wenn die Killserie gerade count erreicht hat (sonst nil)
function Medals.ForStreak(count)
	if table.find(Medals.StreakSteps, count) then
		return "Streak" .. count
	end
	return nil
end

-- Reihenfolge innerhalb eines Kills: höhere Stufe zuerst, bei Gleichstand die Liste des Servers
function Medals.Sort(list)
	local order = {}
	for i, entry in list do
		order[entry] = i
	end
	table.sort(list, function(a, b)
		local ma, mb = Medals.Get(a.Id), Medals.Get(b.Id)
		local ta, tb = ma and ma.Tier or 0, mb and mb.Tier or 0
		if ta ~= tb then
			return ta > tb
		end
		return order[a] < order[b]
	end)
	return list
end

return Medals

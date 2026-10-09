-- QuestConfig (ModuleScript)
-- Tägliche Aufträge: Jeden Tag (UTC) bekommt jeder Spieler PerDay zufällige Aufträge aus dem Pool.
-- Wöchentliche Herausforderungen: jeden Montag (0 Uhr UTC) PerWeek größere Aufträge aus WeeklyPool;
-- wer alle schafft, holt zusätzlich den Wochen-Bonus (Münzen + wechselnder exklusiver Skin).
-- Event = welches Spielereignis zählt (Kill, Headshot, RoundWin, RoundPlayed, MatchPlayed, MatchWin, Streak5,
-- Revive, Gadget). Fortschritt kommt vom Server als Spieler-Attribute "Quests" und "Weekly" (JSON).
-- Arcade-Aufträge zählen nur außerhalb von Extinction.
--
-- Extinction (offene Welt) hat eigene Aufträge: ExtPool (täglich, ExtPerDay) und ExtWeeklyPool (wöchentlich, ExtPerWeek).
-- Ihre Ereignisse beginnen mit X (XZombie, XRunner, XBrute, XRedZombie, XArmored, XPlayerKill, XAirdrop, XNest, XCache,
-- XSurvivor, XNightMinute, XStorm, XBoss) und kommen aus Modes/Extinction (über MissionService und die Event-Dienste).
--
-- VIP & BOOSTER (QuestConfig.IsSpecial: Gamepass VIP oder Team-Rang ab BOOSTER): Spezial-Aufträge in beiden Modi,
-- je Tag 2 Arcade + 2 Extinction (SpecialPool) und je Woche 2 Arcade + 2 Extinction (SpecialWeeklyPool).
-- Alle sehen sie, aber nur Berechtigte sammeln Fortschritt und können abholen. Die Wochen-Aufträge geben beim ersten
-- Mal den gebundenen Skin Unterstützer (Item, nicht handelbar).
--
-- Belohnung: Reward = Münzen, dazu optional Spins (Glücksrad-Drehs), Loot = { Tabelle, Anzahl } (ExtinctionConfig.LootTables,
-- ins Lager), RedPoints (RZ) und Item (Skin, nur wenn noch nicht im Besitz). Die neuen Sätze stehen in QuestConfig.Sets (Profilfeld und Attribut = Key).

local HttpService = game:GetService("HttpService")
local StaffConfig = require(script.Parent.StaffConfig)

local QuestConfig = {}

QuestConfig.PerDay = 3

QuestConfig.Pool = {
	{ Id = "Kills5", Text = "Erziele 5 Kills", Event = "Kill", Goal = 5, Reward = 150 },
	{ Id = "Kills15", Text = "Erziele 15 Kills", Event = "Kill", Goal = 15, Reward = 300 },
	{ Id = "Headshots3", Text = "3 Kills per Kopfschuss", Event = "Headshot", Goal = 3, Reward = 200 },
	{ Id = "Wins2", Text = "Gewinne 2 Runden", Event = "RoundWin", Goal = 2, Reward = 200 },
	{ Id = "Revive2", Text = "Belebe 2 Teamkollegen wieder", Event = "Revive", Goal = 2, Reward = 150 },
	{ Id = "Gadget5", Text = "Setze 5 Gadgets ein", Event = "Gadget", Goal = 5, Reward = 120 },
	{ Id = "Play5", Text = "Spiele 5 Runden in Team-Modi", Event = "RoundPlayed", Goal = 5, Reward = 150 },
}

QuestConfig.PerWeek = 4

QuestConfig.WeeklyPool = {
	{ Id = "WK_Kills100", Text = "Erziele 100 Kills", Event = "Kill", Goal = 100, Reward = 1000 },
	{ Id = "WK_Headshots30", Text = "30 Kills per Kopfschuss", Event = "Headshot", Goal = 30, Reward = 900 },
	{ Id = "WK_MatchWins5", Text = "Gewinne 5 Matches", Event = "MatchWin", Goal = 5, Reward = 1000 },
	{ Id = "WK_Matches10", Text = "Spiele 10 Matches", Event = "MatchPlayed", Goal = 10, Reward = 800 },
	{ Id = "WK_Streak3", Text = "Schaffe 3-mal eine 5er-Killserie", Event = "Streak5", Goal = 3, Reward = 1000 },
	{ Id = "WK_Revive10", Text = "Belebe 10 Teamkollegen wieder", Event = "Revive", Goal = 10, Reward = 700 },
	{ Id = "WK_Gadget40", Text = "Setze 40 Gadgets ein", Event = "Gadget", Goal = 40, Reward = 700 },
	{ Id = "WK_Rounds25", Text = "Gewinne 25 Runden", Event = "RoundWin", Goal = 25, Reward = 900 },
}

-- ---------- Extinction ----------

QuestConfig.ExtPerDay = 3

QuestConfig.ExtPool = {
	{ Id = "X_Zombies40", Text = "Töte 40 Zombies", Event = "XZombie", Goal = 40, Reward = 200, Loot = { "Tier2", 2 } },
	{ Id = "X_Runners10", Text = "Töte 10 Läufer", Event = "XRunner", Goal = 10, Reward = 220, Loot = { "Tier2", 2 } },
	{ Id = "X_Brutes3", Text = "Töte 3 Brocken", Event = "XBrute", Goal = 3, Reward = 250, Loot = { "Tier2", 3 } },
	{ Id = "X_Red15", Text = "Töte 15 Zombies in der roten Zone", Event = "XRedZombie", Goal = 15, Reward = 250,
		Loot = { "Tier3", 1 }, RedPoints = 5 },
	{ Id = "X_Drops2", Text = "Öffne 2 Lootdrops oder Event-Kisten", Event = "XAirdrop", Goal = 2, Reward = 250,
		Loot = { "Tier3", 1 } },
	{ Id = "X_Nest1", Text = "Zerstöre ein Zombienest", Event = "XNest", Goal = 1, Reward = 250, Loot = { "Tier2", 3 } },
	{ Id = "X_Cache3", Text = "Brich 3 Vorratslager auf", Event = "XCache", Goal = 3, Reward = 200, Loot = { "Tier2", 2 } },
	{ Id = "X_Night8", Text = "Verbringe 8 Minuten nachts draußen", Event = "XNightMinute", Goal = 8, Reward = 220,
		Loot = { "Tier2", 2 } },
	{ Id = "X_Players3", Text = "Erledige 3 Spieler in Extinction", Event = "XPlayerKill", Goal = 3, Reward = 250,
		Loot = { "Tier3", 1 } },
}

QuestConfig.ExtPerWeek = 3

QuestConfig.ExtWeeklyPool = {
	{ Id = "XW_Zombies400", Text = "Töte 400 Zombies", Event = "XZombie", Goal = 400, Reward = 1200, Loot = { "Tier3", 2 } },
	{ Id = "XW_Red100", Text = "Töte 100 Zombies in der roten Zone", Event = "XRedZombie", Goal = 100, Reward = 1000,
		Loot = { "Tier3", 2 }, RedPoints = 20 },
	{ Id = "XW_Drops8", Text = "Öffne 8 Lootdrops oder Event-Kisten", Event = "XAirdrop", Goal = 8, Reward = 1200,
		Loot = { "Airdrop", 1 } },
	{ Id = "XW_Armored10", Text = "Töte 10 gepanzerte Zombies", Event = "XArmored", Goal = 10, Reward = 1000,
		Loot = { "Tier3", 2 } },
	{ Id = "XW_Storm2", Text = "Schafft 2-mal das Ziel einer Sturmnacht", Event = "XStorm", Goal = 2, Reward = 1200,
		Loot = { "Airdrop", 1 } },
	{ Id = "XW_Players20", Text = "Erledige 20 Spieler in Extinction", Event = "XPlayerKill", Goal = 20, Reward = 1000,
		Loot = { "Tier3", 2 } },
	{ Id = "XW_Nest6", Text = "Zerstöre 6 Zombienester", Event = "XNest", Goal = 6, Reward = 1000, Loot = { "Tier3", 2 } },
	{ Id = "XW_Survivor5", Text = "Rette 5 Überlebende", Event = "XSurvivor", Goal = 5, Reward = 1000, Loot = { "Tier3", 2 } },
}

-- ---------- VIP & BOOSTER ----------

-- Skin für VIP & BOOSTER (Cosmetics, Reward, nicht handelbar): gibt es mit dem ersten Wochen-Auftrag
local SUPPORTER_SKIN = "W_Unterstuetzer"

QuestConfig.SpecialPool = {
	{ Id = "S_Kills20", Mode = "Arcade", Text = "Erziele 20 Kills", Event = "Kill", Goal = 20, Reward = 400, Spins = 1 },
	{ Id = "S_Wins3", Mode = "Arcade", Text = "Gewinne 3 Runden", Event = "RoundWin", Goal = 3, Reward = 400, Spins = 1 },
	{ Id = "S_Headshots6", Mode = "Arcade", Text = "6 Kills per Kopfschuss", Event = "Headshot", Goal = 6, Reward = 400,
		Spins = 1 },
	{ Id = "S_XZombies60", Mode = "Extinction", Text = "Töte 60 Zombies", Event = "XZombie", Goal = 60, Reward = 500,
		Loot = { "Airdrop", 1 } },
	{ Id = "S_XDrops3", Mode = "Extinction", Text = "Öffne 3 Lootdrops oder Event-Kisten", Event = "XAirdrop", Goal = 3,
		Reward = 500, Loot = { "Tier3", 2 } },
	{ Id = "S_XRed25", Mode = "Extinction", Text = "Töte 25 Zombies in der roten Zone", Event = "XRedZombie", Goal = 25,
		Reward = 500, Loot = { "Tier3", 1 }, RedPoints = 10 },
	{ Id = "S_Streak2", Mode = "Arcade", Text = "Schaffe 2-mal eine 5er-Killserie", Event = "Streak5", Goal = 2, Reward = 400,
		Spins = 1 },
	{ Id = "S_Revive4", Mode = "Arcade", Text = "Belebe 4 Teamkollegen wieder", Event = "Revive", Goal = 4, Reward = 400, Spins = 1 },
	{ Id = "S_XBrutes5", Mode = "Extinction", Text = "Töte 5 Brocken", Event = "XBrute", Goal = 5, Reward = 500,
		Loot = { "Tier3", 1 } },
	{ Id = "S_XNest2", Mode = "Extinction", Text = "Zerstöre 2 Zombienester", Event = "XNest", Goal = 2, Reward = 500,
		Loot = { "Tier3", 2 } },
}

QuestConfig.SpecialWeeklyPool = {
	{ Id = "SW_MatchWins8", Mode = "Arcade", Text = "Gewinne 8 Matches", Event = "MatchWin", Goal = 8, Reward = 2000,
		Spins = 3, Item = SUPPORTER_SKIN },
	{ Id = "SW_Kills250", Mode = "Arcade", Text = "Erziele 250 Kills", Event = "Kill", Goal = 250, Reward = 2000, Spins = 3,
		Item = SUPPORTER_SKIN },
	{ Id = "SW_XZombies600", Mode = "Extinction", Text = "Töte 600 Zombies", Event = "XZombie", Goal = 600, Reward = 2500,
		Loot = { "Airdrop", 2 }, Item = SUPPORTER_SKIN },
	{ Id = "SW_XStorm3", Mode = "Extinction", Text = "Schafft 3-mal das Ziel einer Sturmnacht", Event = "XStorm", Goal = 3,
		Reward = 2500, Loot = { "Airdrop", 2 }, RedPoints = 30, Item = SUPPORTER_SKIN },
	{ Id = "SW_Headshots60", Mode = "Arcade", Text = "60 Kills per Kopfschuss", Event = "Headshot", Goal = 60, Reward = 2000,
		Spins = 3, Item = SUPPORTER_SKIN },
	{ Id = "SW_XSurvivor8", Mode = "Extinction", Text = "Rette 8 Überlebende", Event = "XSurvivor", Goal = 8, Reward = 2500,
		Loot = { "Airdrop", 2 }, Item = SUPPORTER_SKIN },
}

-- Weitere Auftrags-Sätze (neben Quests/Weekly): Key = Profilfeld und Spieler-Attribut, Period Day/Week,
-- Picks = { { Pool, Count, Mode } } (Mode filtert den Pool), Special = nur für VIP & BOOSTER
QuestConfig.Sets = {
	{ Key = "ExtQuests", Period = "Day", Picks = { { Pool = QuestConfig.ExtPool, Count = QuestConfig.ExtPerDay } } },
	{ Key = "ExtWeekly", Period = "Week", Picks = { { Pool = QuestConfig.ExtWeeklyPool, Count = QuestConfig.ExtPerWeek } } },
	{ Key = "SpecialQuests", Period = "Day", Special = true, Picks = {
		{ Pool = QuestConfig.SpecialPool, Count = 2, Mode = "Arcade" },
		{ Pool = QuestConfig.SpecialPool, Count = 2, Mode = "Extinction" } } },
	{ Key = "SpecialWeekly", Period = "Week", Special = true, Picks = {
		{ Pool = QuestConfig.SpecialWeeklyPool, Count = 2, Mode = "Arcade" },
		{ Pool = QuestConfig.SpecialWeeklyPool, Count = 2, Mode = "Extinction" } } },
}

-- Alle Wochen-Aufträge geschafft: Münzen + Skin der Woche (wechselt jede Woche; schon im Besitz = nur Münzen)
QuestConfig.WeeklyBonus = { Coins = 1500,
	Skins = { "W_Woche_Kobalt", "W_Woche_Smaragd", "W_Woche_Purpur", "W_Woche_Bernstein", "W_Woche_Titan" } }

local DAY = 24 * 3600
local WEEK = 7 * DAY
local MONDAY_OFFSET = 4 * DAY -- 1.1.1970 war ein Donnerstag, der 5.1. ein Montag

local byId = {}
for _, quest in QuestConfig.Pool do
	byId[quest.Id] = quest
end
for _, quest in QuestConfig.WeeklyPool do
	byId[quest.Id] = quest
	quest.Weekly = true
end
for _, quest in QuestConfig.Pool do
	quest.Mode = "Arcade"
end
for _, quest in QuestConfig.WeeklyPool do
	quest.Mode = "Arcade"
end
for _, set in QuestConfig.Sets do
	for _, pick in set.Picks do
		for _, quest in pick.Pool do
			byId[quest.Id] = quest
			quest.Set = set.Key
			quest.Weekly = set.Period == "Week"
			quest.Special = set.Special
			quest.Mode = quest.Mode or "Extinction"
		end
	end
end

function QuestConfig.GetSet(key)
	for _, set in QuestConfig.Sets do
		if set.Key == key then
			return set
		end
	end
	return nil
end

-- Darf der Spieler VIP & BOOSTER-Aufträge machen? Gamepass VIP oder Team-Rang ab BOOSTER (Team und Creator inklusive)
function QuestConfig.IsSpecial(player)
	if player:GetAttribute("Pass_VIP") == true then
		return true
	end
	local booster = StaffConfig.Get("Booster")
	return StaffConfig.Power(player) >= (booster and booster.Power or math.huge)
end

-- Belohnung als Text, z.B. "500 Münzen · 2× Beute Stufe 3 · 10 RZ" (Beute = zufällige Items aus der Tabelle)
local LOOT_NAMES = { Tier1 = "Beute Stufe 1", Tier2 = "Beute Stufe 2", Tier3 = "Beute Stufe 3", Airdrop = "Lootdrop-Beute" }
-- translate (optional, Client: Locale.Translate) übersetzt jedes Teil einzeln
-- owned (optional): Besitz des Spielers (Cosmetics.GetOwned); einen Skin, den er schon hat, nicht nennen
function QuestConfig.RewardText(quest, translate, owned)
	translate = translate or function(text)
		return text
	end
	local parts = { translate(tostring(quest.Reward) .. " Münzen") }
	if quest.Spins then
		table.insert(parts, translate(quest.Spins .. "× Glücksrad"))
	end
	if quest.Loot then
		table.insert(parts, translate(quest.Loot[2] .. "× " .. (LOOT_NAMES[quest.Loot[1]] or quest.Loot[1])))
	end
	if quest.RedPoints then
		table.insert(parts, quest.RedPoints .. " RZ")
	end
	local item = quest.Item and require(script.Parent.Cosmetics).Get(quest.Item)
	if item and not (owned and owned[item.Id]) then
		table.insert(parts, translate("Skin " .. item.Name))
	end
	return table.concat(parts, " · ")
end

-- Täglicher oder wöchentlicher Auftrag per Id
function QuestConfig.Get(id)
	return byId[id]
end

-- Nummer der aktuellen Woche (ab Montag 0 Uhr UTC)
function QuestConfig.Week(now)
	return math.floor(((now or os.time()) - MONDAY_OFFSET) / WEEK)
end

-- Sekunden bis zu den nächsten täglichen bzw. wöchentlichen Aufträgen (now = Serverzeit)
function QuestConfig.DayLeft(now)
	return DAY - math.floor(now) % DAY
end

function QuestConfig.WeekLeft(now)
	return WEEK - (math.floor(now) - MONDAY_OFFSET) % WEEK
end

-- Skin-Bonus einer Woche
function QuestConfig.BonusSkin(week)
	local skins = QuestConfig.WeeklyBonus.Skins
	return skins[week % #skins + 1]
end

-- Aktueller Tag (UTC) als Text, z.B. "2026-10-02"
function QuestConfig.Today()
	return os.date("!%Y-%m-%d")
end

-- Aufträge des Spielers aus dem Attribut lesen: { Day, Ids = {...}, Progress = {}, Claimed = {} }
-- attribute = "Weekly" für die Wochen-Aufträge: { Week, Ids, Progress, Claimed, Bonus = true wenn abgeholt }
function QuestConfig.Read(player, attribute)
	local raw = player:GetAttribute(attribute or "Quests")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(data) == "table" and data or nil
end

return QuestConfig

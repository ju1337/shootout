-- QuestConfig (ModuleScript)
-- Tägliche Aufträge: Jeden Tag (UTC) bekommt jeder Spieler PerDay zufällige Aufträge aus dem Pool.
-- Wöchentliche Herausforderungen: jeden Montag (0 Uhr UTC) PerWeek größere Aufträge aus WeeklyPool;
-- wer alle schafft, holt zusätzlich den Wochen-Bonus (Münzen + wechselnder exklusiver Skin).
-- Event = welches Spielereignis zählt (Kill, Headshot, RoundWin, RoundPlayed, MatchPlayed, MatchWin, Streak5,
-- Revive, Gadget). Fortschritt kommt vom Server als Spieler-Attribute "Quests" und "Weekly" (JSON).

local HttpService = game:GetService("HttpService")

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

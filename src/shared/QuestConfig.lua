-- QuestConfig (ModuleScript)
-- Tägliche Aufträge: Jeden Tag (UTC) bekommt jeder Spieler PerDay zufällige Aufträge aus dem Pool.
-- Event = welches Spielereignis zählt (Kill, Headshot, RoundWin, RoundPlayed, Revive, Gadget)
-- Fortschritt kommt vom Server als Spieler-Attribut "Quests" (JSON).

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

function QuestConfig.Get(id)
	for _, quest in QuestConfig.Pool do
		if quest.Id == id then
			return quest
		end
	end
	return nil
end

-- Aktueller Tag (UTC) als Text, z.B. "2026-10-02"
function QuestConfig.Today()
	return os.date("!%Y-%m-%d")
end

-- Aufträge des Spielers aus dem Attribut lesen: { Day, Ids = {...}, Progress = {}, Claimed = {} }
function QuestConfig.Read(player)
	local raw = player:GetAttribute("Quests")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(data) == "table" and data or nil
end

return QuestConfig

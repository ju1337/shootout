-- GameSettings (ModuleScript)
-- Einstellungen, die Admins live im Admin-Panel ändern können.
-- Werte liegen als Attribute an ReplicatedStorage ("Setting_<Key>"), damit Client und Server sie sehen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameSettings = {}

GameSettings.List = {
	{ Key = "KillsToWin", Group = "Free-for-All", Label = "Kills zum Sieg", Default = 20, Min = 1, Max = 100, Step = 1 },
	{ Key = "FFARespawnTime", Group = "Free-for-All", Label = "Respawn (Sek.)", Default = 3, Min = 0, Max = 15, Step = 1 },
	{ Key = "SelectTime", Group = "Team-Modi", Label = "Agentenwahl Runde 1 (Sek.)", Default = 20, Min = 5, Max = 60, Step = 5 },
	{ Key = "RoundSelectTime", Group = "Team-Modi", Label = "Agentenwahl danach (Sek.)", Default = 10, Min = 3, Max = 60, Step = 1 },
	{ Key = "Countdown", Group = "Team-Modi", Label = "Countdown (Sek.)", Default = 3, Min = 0, Max = 30, Step = 1 },
	{ Key = "CaptureTime", Group = "Wingman", Label = "Punkt einnehmen (Sek.)", Default = 3, Min = 1, Max = 30, Step = 1 },
	{ Key = "TicketDrain", Group = "Wingman", Label = "Ticket-Abzug alle (Sek.)", Default = 30, Min = 5, Max = 120, Step = 5 },
	{ Key = "WingmanRoundsToWin", Group = "Wingman", Label = "Rundensiege zum Match", Default = 3, Min = 1, Max = 15, Step = 1 },
	{ Key = "WingmanTickets", Group = "Wingman", Label = "Respawn-Tickets pro Team", Default = 4, Min = 1, Max = 30, Step = 1 },
	{ Key = "WingmanRoundTime", Group = "Wingman", Label = "Rundenzeit (Sek.)", Default = 180, Min = 60, Max = 600, Step = 30 },
	{ Key = "ArenaRoundsToWin", Group = "1v1 Arena", Label = "Rundensiege zum Match", Default = 5, Min = 1, Max = 15, Step = 1 },
	{ Key = "DominationScore", Group = "Herrschaft", Label = "Punkte zum Sieg", Default = 200, Min = 50, Max = 1000, Step = 25 },
	{ Key = "DominationRoundTime", Group = "Herrschaft", Label = "Matchzeit (Sek.)", Default = 600, Min = 120, Max = 1800, Step = 60 },
	{ Key = "DominationCapture", Group = "Herrschaft", Label = "Einnehmen (Sek.)", Default = 5, Min = 1, Max = 20, Step = 1 },
	{ Key = "DominationRounds", Group = "Herrschaft", Label = "Runden zum Sieg", Default = 1, Min = 1, Max = 3, Step = 1 },
	-- Einstellungen ausgebauter Modi (zum Wiedereinbauen einkommentieren):
	-- (ausgebaut) { Key = "RoundsToWin", Group = "Drop", Label = "Rundensiege zum Match", Default = 5, Min = 1, Max = 15, Step = 1 },
	-- (ausgebaut) { Key = "StrikeoutRoundsToWin", Group = "Strikeout", Label = "Rundensiege zum Match", Default = 3, Min = 1, Max = 15, Step = 1 },
	-- (ausgebaut) { Key = "StrikeoutTickets", Group = "Strikeout", Label = "Respawn-Tickets pro Team", Default = 10, Min = 1, Max = 50, Step = 1 },
	-- (ausgebaut) { Key = "StrikeoutRoundTime", Group = "Strikeout", Label = "Rundenzeit (Sek.)", Default = 300, Min = 60, Max = 900, Step = 30 },
	-- (ausgebaut) { Key = "DemolitionRoundsToWin", Group = "Demolition", Label = "Rundensiege zum Match", Default = 4, Min = 1, Max = 15, Step = 1 },
	-- (ausgebaut) { Key = "DemolitionRoundTime", Group = "Demolition", Label = "Rundenzeit (Sek.)", Default = 150, Min = 60, Max = 600, Step = 15 },
	-- (ausgebaut) { Key = "BombTime", Group = "Demolition", Label = "Bomben-Timer (Sek.)", Default = 40, Min = 10, Max = 120, Step = 5 },
	-- (ausgebaut) { Key = "RankedRoundsToWin", Group = "Ranked", Label = "Rundensiege zum Match", Default = 4, Min = 1, Max = 15, Step = 1 },
	-- (ausgebaut) { Key = "ExtractionRoundsToWin", Group = "Extraction", Label = "Rundensiege zum Match", Default = 4, Min = 1, Max = 15, Step = 1 },
	-- (ausgebaut) { Key = "ExtractionRoundTime", Group = "Extraction", Label = "Rundenzeit (Sek.)", Default = 150, Min = 60, Max = 600, Step = 15 },
	-- (ausgebaut) { Key = "HackTime", Group = "Extraction", Label = "Hack-Dauer (Sek.)", Default = 25, Min = 5, Max = 90, Step = 5 },
	-- (ausgebaut) { Key = "TDMTickets", Group = "Team Deathmatch", Label = "Leben pro Team", Default = 60, Min = 5, Max = 200, Step = 5 },
	-- (ausgebaut) { Key = "TDMRoundTime", Group = "Team Deathmatch", Label = "Matchzeit (Sek.)", Default = 600, Min = 120, Max = 1800, Step = 60 },
	-- (ausgebaut) { Key = "TDMRounds", Group = "Team Deathmatch", Label = "Runden zum Sieg", Default = 1, Min = 1, Max = 5, Step = 1 },
	{ Key = "DamageMultiplier", Group = "Allgemein", Label = "Schaden ×", Default = 1, Min = 0.1, Max = 5, Step = 0.1 },
	{ Key = "XPMultiplier", Group = "Allgemein", Label = "XP ×", Default = 1, Min = 0, Max = 10, Step = 0.5 },
	{ Key = "AutoFillBots", Group = "Bots", Label = "Auto-Bots (1 = an)", Default = 1, Min = 0, Max = 1, Step = 1 },
	{ Key = "BotSpread", Group = "Bots", Label = "Bot-Streuung (Grad)", Default = 4, Min = 0, Max = 15, Step = 0.5 },
	{ Key = "BotReaction", Group = "Bots", Label = "Bot-Reaktionszeit (Sek.)", Default = 0.5, Min = 0, Max = 2, Step = 0.1 },
	{ Key = "BotDamage", Group = "Bots", Label = "Bot-Schaden ×", Default = 0.6, Min = 0, Max = 3, Step = 0.1 },
}

function GameSettings.Def(key)
	for _, def in GameSettings.List do
		if def.Key == key then
			return def
		end
	end
	return nil
end

-- Aktueller Wert (Standardwert, wenn nie geändert)
function GameSettings.Get(key)
	local value = ReplicatedStorage:GetAttribute("Setting_" .. key)
	if value == nil then
		return GameSettings.Def(key).Default
	end
	return value
end

-- Wert setzen (nur Server). Wird auf Min/Max und Schrittweite gerundet.
function GameSettings.Set(key, value)
	assert(RunService:IsServer(), "GameSettings.Set nur auf dem Server")
	local def = GameSettings.Def(key)
	if not def or typeof(value) ~= "number" or value ~= value then
		return
	end
	value = math.clamp(math.round(value / def.Step) * def.Step, def.Min, def.Max)
	value = math.round(value * 100) / 100 -- Rundungsfehler bei 0.1-Schritten vermeiden
	ReplicatedStorage:SetAttribute("Setting_" .. key, value)
end

return GameSettings

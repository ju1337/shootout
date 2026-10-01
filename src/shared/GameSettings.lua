-- GameSettings (ModuleScript)
-- Einstellungen, die Admins live im Admin-Panel ändern können.
-- Werte liegen als Attribute an ReplicatedStorage ("Setting_<Key>"), damit Client und Server sie sehen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameSettings = {}

GameSettings.List = {
	{ Key = "KillsToWin", Group = "Free-for-All", Label = "Kills zum Sieg", Default = 20, Min = 1, Max = 100, Step = 1 },
	{ Key = "FFARespawnTime", Group = "Free-for-All", Label = "Respawn (Sek.)", Default = 3, Min = 0, Max = 15, Step = 1 },
	{ Key = "SelectTime", Group = "Drop", Label = "Agentenwahl Runde 1 (Sek.)", Default = 20, Min = 5, Max = 60, Step = 5 },
	{ Key = "RoundSelectTime", Group = "Drop", Label = "Agentenwahl danach (Sek.)", Default = 10, Min = 3, Max = 60, Step = 1 },
	{ Key = "Countdown", Group = "Drop", Label = "Countdown (Sek.)", Default = 3, Min = 0, Max = 30, Step = 1 },
	{ Key = "RoundsToWin", Group = "Drop", Label = "Rundensiege zum Match", Default = 5, Min = 1, Max = 15, Step = 1 },
	{ Key = "DamageMultiplier", Group = "Allgemein", Label = "Schaden ×", Default = 1, Min = 0.1, Max = 5, Step = 0.1 },
	{ Key = "XPMultiplier", Group = "Allgemein", Label = "XP ×", Default = 1, Min = 0, Max = 10, Step = 0.5 },
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

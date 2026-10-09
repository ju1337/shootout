-- TitleConfig (ModuleScript)
-- Spieler-Titel: werden durch Leistungen freigeschaltet und stehen unter dem Namen über dem Kopf
-- (neben dem Rang) und auf der Spielerkarte. Ausgewählt wird im Fenster TITEL.
-- Bedingungen: Stat = Statistik-Schlüssel (Stats), Prestige, Level (Spielerlevel), BestElo (höchste ELO je),
-- Mastery = Anzahl Waffen mit Tarnung dieser Stufe. Goal = nötiger Wert.
-- Server prüft beim Auswählen und meldet neue Titel (RewardService). Spieler-Attribut "Title" = Id.

local HttpService = game:GetService("HttpService")

local LevelConfig = require(script.Parent.LevelConfig)
local MasteryConfig = require(script.Parent.MasteryConfig)
local RankConfig = require(script.Parent.RankConfig)
local ExtLevelConfig = require(script.Parent.ExtLevelConfig)

local TitleConfig = {}

local function tierElo(name)
	for _, tier in RankConfig.Tiers do
		if tier.Name == name then
			return tier.Elo
		end
	end
	return math.huge
end

TitleConfig.List = {
	{ Id = "Rekrut", Name = "Rekrut", Text = "Für alle", Color = Color3.fromRGB(150, 156, 166) },
	{ Id = "Veteran", Name = "Veteran", Text = "500 Kills", Stat = "Kills", Goal = 500,
		Color = Color3.fromRGB(150, 175, 120) },
	{ Id = "Legende", Name = "Legende", Text = "2.500 Kills", Stat = "Kills", Goal = 2500,
		Color = Color3.fromRGB(240, 195, 60) },
	{ Id = "Scharfschuetze", Name = "Scharfschütze", Text = "250 Kopfschüsse", Stat = "Headshots", Goal = 250,
		Color = Color3.fromRGB(110, 170, 255) },
	{ Id = "Kettenreaktion", Name = "Kettenreaktion", Text = "Killserie von 10", Stat = "BestStreak", Goal = 10,
		Color = Color3.fromRGB(230, 140, 60) },
	{ Id = "Unaufhaltsam", Name = "Der Unaufhaltsame", Text = "Killserie von 20", Stat = "BestStreak", Goal = 20,
		Color = Color3.fromRGB(225, 55, 65) },
	{ Id = "Raecher", Name = "Rächer", Text = "25-mal RACHE", Stat = "Revenges", Goal = 25,
		Color = Color3.fromRGB(206, 70, 58) },
	{ Id = "Spielverderber", Name = "Spielverderber", Text = "25 Killserien beendet", Stat = "Shutdowns", Goal = 25,
		Color = Color3.fromRGB(190, 110, 230) },
	{ Id = "Sanitaeter", Name = "Sanitäter", Text = "50 Wiederbelebungen", Stat = "Revives", Goal = 50,
		Color = Color3.fromRGB(80, 210, 130) },
	{ Id = "Eroberer", Name = "Eroberer", Text = "100 Punkte erobert (Herrschaft)", Stat = "Captures", Goal = 100,
		Color = Color3.fromRGB(96, 164, 214) },
	{ Id = "Champion", Name = "Champion", Text = "100 Siege", Stat = "Wins", Goal = 100,
		Color = Color3.fromRGB(212, 170, 80) },
	{ Id = "Wochenkrieger", Name = "Wochenkrieger", Text = "5 Wochen-Boni abgeholt", Stat = "WeeklyBonus", Goal = 5,
		Color = Color3.fromRGB(240, 210, 120) },
	{ Id = "Aufsteiger", Name = "Aufsteiger", Text = "Spielerlevel 50", Level = 50, Goal = 50,
		Color = Color3.fromRGB(96, 164, 214) },
	{ Id = "Prestige", Name = "Prestige-Jäger", Text = "Prestige 1", Prestige = true, Goal = 1,
		Color = LevelConfig.PrestigeColors[1] },
	{ Id = "Unsterblich", Name = "Unsterblich", Text = "Prestige 10", Prestige = true, Goal = 10,
		Color = Color3.fromRGB(255, 255, 255) },
	{ Id = "Diamantklasse", Name = "Diamantklasse", Text = "Rang Diamant erreicht", BestElo = true,
		Goal = tierElo("Diamant"), Color = RankConfig.Tiers[5].Color },
	{ Id = "Meister", Name = "Großmeister", Text = "Rang Meister erreicht", BestElo = true,
		Goal = tierElo("Meister"), Color = RankConfig.Tiers[6].Color },
	{ Id = "Waffenmeister", Name = "Waffenmeister", Text = "Dunkle Materie auf einer Waffe", Mastery = "DunkleMaterie",
		Goal = 1, Color = Color3.fromRGB(150, 70, 230) },
	{ Id = "Arsenal", Name = "Arsenal", Text = "Gold-Tarnung auf allen Waffen", Mastery = "Gold",
		Goal = #MasteryConfig.Weapons, Color = Color3.fromRGB(255, 196, 52) },
}

-- Titel der offenen Welt (ab einem Spielerlevel, ExtLevelConfig)
for _, title in ExtLevelConfig.Titles do
	table.insert(TitleConfig.List, { Id = title.Id, Name = title.Name, Text = "Spielerlevel " .. title.Level,
		Level = title.Level, Goal = title.Level, Color = title.Color })
end

local byId = {}
for _, title in TitleConfig.List do
	byId[title.Id] = title
end

TitleConfig.Default = "Rekrut"

function TitleConfig.Get(id)
	return byId[id]
end

-- Daten für die Prüfung: { Stats = {}, Prestige, Level, Owned = {} } (Server aus dem Profil, Client aus Attributen)
local function decode(player, attribute)
	local raw = player:GetAttribute(attribute)
	if type(raw) ~= "string" then
		return {}
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(data) == "table" and data or {}
end

function TitleConfig.DataFromPlayer(player)
	local info = LevelConfig.Get(player)
	return { Stats = decode(player, "Stats"), Prestige = info.Prestige, Level = info.Level, Owned = decode(player, "Owned") }
end

-- Aktueller Wert und Ziel einer Bedingung
function TitleConfig.Progress(title, data)
	local stats = data.Stats or {}
	local value = 0
	if title.Stat then
		value = tonumber(stats[title.Stat]) or 0
	elseif title.Prestige then
		value = data.Prestige or 0
	elseif title.Level then
		-- nach einem Prestige zählt Level 100 als erreicht
		value = (data.Prestige or 0) > 0 and LevelConfig.MaxLevel or (data.Level or 1)
	elseif title.BestElo then
		value = tonumber(stats.BestElo) or 0
	elseif title.Mastery then
		for _, weaponName in MasteryConfig.Weapons do
			if (data.Owned or {})[MasteryConfig.ItemId(weaponName, title.Mastery)] then
				value += 1
			end
		end
	else
		return 1, 1
	end
	return value, title.Goal or 1
end

function TitleConfig.Unlocked(title, data)
	local value, goal = TitleConfig.Progress(title, data)
	return value >= goal
end

return TitleConfig

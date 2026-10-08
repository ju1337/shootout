-- AchievementConfig (ModuleScript)
-- Erfolge-Wand: Erfolge mit drei Stufen (Bronze, Silber, Gold). Jede Stufe hat ein Ziel (Goal) für eine Statistik
-- (Stat, Profil Stats; die Extinction-Statistiken zählt ExtLevelService/HideoutService) und Münzen als Belohnung.
-- Der Server (AchievementService) prüft bei jeder Änderung einer Statistik, vergibt erreichte Stufen (Meldung, Münzen) und
-- merkt sie im Profil (Achievements = { [Id] = Stufe }); Spieler-Attribut "Achievements" (JSON) für die Erfolge-Wand.
-- Icon = gezeichnetes Symbol (ExtinctionClient: Erfolge-Wand).

local HttpService = game:GetService("HttpService")

local ExtLevelConfig = require(script.Parent.ExtLevelConfig)

local AchievementConfig = {}

AchievementConfig.Tiers = {
	{ Name = "BRONZE", Color = Color3.fromRGB(196, 132, 84) },
	{ Name = "SILBER", Color = Color3.fromRGB(196, 204, 214) },
	{ Name = "GOLD", Color = Color3.fromRGB(240, 196, 70) },
}

-- Goals/Coins je Stufe (Bronze, Silber, Gold)
AchievementConfig.List = {
	{ Id = "Zombies", Name = "Zombie-Schlächter", Text = "Zombies erledigen", Stat = "ExtZombies", Icon = "Skull",
		Goals = { 100, 1000, 5000 }, Coins = { 200, 800, 2500 } },
	{ Id = "Brutes", Name = "Brockenbrecher", Text = "Brocken erledigen", Stat = "ExtBrutes", Icon = "Fist",
		Goals = { 10, 100, 500 }, Coins = { 200, 800, 2500 } },
	{ Id = "Players", Name = "Kopfgeldjäger", Text = "Spieler in der offenen Welt erledigen", Stat = "ExtPlayerKills", Icon = "Crosshair",
		Goals = { 5, 50, 250 }, Coins = { 250, 1000, 3000 } },
	{ Id = "Bots", Name = "Banditenschreck", Text = "Banditen und Konvoi-Wachen erledigen", Stat = "ExtBotKills", Icon = "Shield",
		Goals = { 10, 100, 500 }, Coins = { 200, 800, 2500 } },
	{ Id = "Nests", Name = "Nestvernichter", Text = "Zombienester zerstören", Stat = "ExtNests", Icon = "Fire",
		Goals = { 3, 25, 100 }, Coins = { 250, 1000, 3000 } },
	{ Id = "Caches", Name = "Schlossknacker", Text = "Vorratslager aufbrechen", Stat = "ExtCaches", Icon = "Lock",
		Goals = { 5, 50, 200 }, Coins = { 200, 800, 2500 } },
	{ Id = "Survivors", Name = "Retter", Text = "Überlebende in die Safe Zone bringen", Stat = "ExtSurvivors", Icon = "Heart",
		Goals = { 1, 15, 60 }, Coins = { 250, 1000, 3000 } },
	{ Id = "Airdrops", Name = "Glückspilz", Text = "Lootdrops öffnen", Stat = "ExtAirdrops", Icon = "Crate",
		Goals = { 1, 20, 100 }, Coins = { 200, 800, 2500 } },
	{ Id = "Convoys", Name = "Konvoi-Jäger", Text = "Konvois knacken", Stat = "ExtConvoys", Icon = "Truck",
		Goals = { 1, 10, 40 }, Coins = { 400, 1500, 5000 } },
	{ Id = "Missions", Name = "Auftragnehmer", Text = "Aufträge erledigen", Stat = "ExtMissions", Icon = "List",
		Goals = { 5, 50, 250 }, Coins = { 200, 800, 2500 } },
	{ Id = "Hideout", Name = "Bauherr", Text = "Module im Versteck ausbauen", Stat = "ExtHideout", Icon = "House",
		Goals = { 1, 6, 12 }, Coins = { 200, 1000, 3000 } },
	{ Id = "Veteran", Name = "Ödland-Veteran", Text = "Extinction-Level erreichen (10 · 25 · 50)", Stat = ExtLevelConfig.Stat,
		Icon = "Star", Goals = { ExtLevelConfig.TotalFor(10), ExtLevelConfig.TotalFor(25), ExtLevelConfig.TotalFor(50) },
		Coins = { 500, 2000, 6000 } },
}

local byId, byStat = {}, {}
for _, achievement in AchievementConfig.List do
	byId[achievement.Id] = achievement
	byStat[achievement.Stat] = byStat[achievement.Stat] or {}
	table.insert(byStat[achievement.Stat], achievement)
end

function AchievementConfig.Get(id)
	return byId[id]
end

-- Erfolge, die von einer Statistik abhängen
function AchievementConfig.ForStat(stat)
	return byStat[stat] or {}
end

-- Erreichte Stufe für einen Statistik-Wert (0 = noch keine)
function AchievementConfig.TierFor(achievement, value)
	local tier = 0
	for index, goal in achievement.Goals do
		if (tonumber(value) or 0) >= goal then
			tier = index
		end
	end
	return tier
end

-- Vergebene Stufen aus dem Spieler-Attribut (Client)
function AchievementConfig.Data(player)
	local raw = player and player:GetAttribute("Achievements")
	if type(raw) == "string" then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(data) == "table" then
			return data
		end
	end
	return {}
end

return AchievementConfig

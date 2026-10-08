-- BadgeConfig (ModuleScript)
-- Roblox-Badges (Abzeichen auf der Spielseite und im Profil). Server: src/server-shared/Badges.lua vergibt sie.
-- IDs eintragen: Creator Hub → dein Spiel → Engagement → Badges anlegen, die ID hier bei BadgeId einsetzen. Solange eine
-- ID 0 ist, wird das Badge nicht vergeben (aber im Profil gemerkt und nachgetragen, sobald die ID da ist).
--   Trigger "Welcome"    beim ersten Beitritt (Profil geladen)
--   Trigger "Tutorial"   Tutorial der offenen Welt fertig (nicht übersprungen)
--   Trigger "Recruiter"  ein eingeladener Freund ist über die Einladung beigetreten (InviteService)
--   Achievement = Id     Erfolg der Erfolge-Wand (AchievementConfig) auf GOLD

local BadgeConfig = {}

BadgeConfig.List = {
	{ Id = "Welcome", BadgeId = 0, Name = "Willkommen in Camp Phoenix", Trigger = "Welcome" },
	{ Id = "Tutorial", BadgeId = 0, Name = "Überlebenstraining", Trigger = "Tutorial" },
	{ Id = "Recruiter", BadgeId = 0, Name = "Anwerber", Trigger = "Recruiter" },
	{ Id = "Ach_Zombies", BadgeId = 0, Name = "Zombie-Schlächter", Achievement = "Zombies" },
	{ Id = "Ach_Brutes", BadgeId = 0, Name = "Brockenbrecher", Achievement = "Brutes" },
	{ Id = "Ach_Players", BadgeId = 0, Name = "Kopfgeldjäger", Achievement = "Players" },
	{ Id = "Ach_Bots", BadgeId = 0, Name = "Banditenschreck", Achievement = "Bots" },
	{ Id = "Ach_Nests", BadgeId = 0, Name = "Nestvernichter", Achievement = "Nests" },
	{ Id = "Ach_Caches", BadgeId = 0, Name = "Schlossknacker", Achievement = "Caches" },
	{ Id = "Ach_Survivors", BadgeId = 0, Name = "Retter", Achievement = "Survivors" },
	{ Id = "Ach_Airdrops", BadgeId = 0, Name = "Glückspilz", Achievement = "Airdrops" },
	{ Id = "Ach_Convoys", BadgeId = 0, Name = "Konvoi-Jäger", Achievement = "Convoys" },
	{ Id = "Ach_Missions", BadgeId = 0, Name = "Auftragnehmer", Achievement = "Missions" },
}

local byId, byTrigger, byAchievement = {}, {}, {}
for _, badge in BadgeConfig.List do
	byId[badge.Id] = badge
	if badge.Trigger then
		byTrigger[badge.Trigger] = badge
	end
	if badge.Achievement then
		byAchievement[badge.Achievement] = badge
	end
end

function BadgeConfig.Get(id)
	return byId[id]
end

function BadgeConfig.ForTrigger(trigger)
	return byTrigger[trigger]
end

function BadgeConfig.ForAchievement(achievementId)
	return byAchievement[achievementId]
end

return BadgeConfig

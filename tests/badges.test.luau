-- Roblox-Badges (Badges, BadgeConfig) und Freunde einladen (InviteService): Begrüßung nach dem Laden, Tutorial fertig
-- (nicht übersprungen), Erfolg auf GOLD, Anwerber beim ersten Freund über die Einladung (ReferredByPlayerId in den
-- Join-Daten, Münzen und Meldung für den Einladenden, jeder Freund nur einmal). Ohne BadgeId (0) wird nur vorgemerkt
-- und nach dem Eintragen der ID beim nächsten Laden nachgetragen; jedes Badge nur einmal je Spieler.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local store = SIM.DataStore("PlayerData_v1")
local BadgeConfig = require("BadgeConfig")
local Badges = require("Badges")
local InviteService = require("InviteService")
local AchievementService = require("AchievementService")
local AchievementConfig = require("AchievementConfig")
local ProgressService = require("ProgressService")
local Remotes = require("Remotes")
ProgressService.Init()
AchievementService.Init()
Badges.Init()
InviteService.Init()

-- IDs eintragen (wie nach dem Creator Hub), eine bleibt 0
for _, badge in BadgeConfig.List do
	badge.BadgeId = badge.Id == "Ach_Convoys" and 0 or 1000 + #badge.Id
end

local function awarded(player, id)
	for _, entry in Badges.Awarded do
		if entry.Player == player and entry.Id == id then
			return true
		end
	end
	return false
end

local bob = SIM.AddPlayer("Bob", 1001)
SIM.Advance(1)
check(ProgressService.IsLoaded(bob), "Profil geladen")
check(awarded(bob, "Welcome") and Badges.Has(bob, "Welcome"), "Begrüßungs-Badge nach dem Laden")
check(not Badges.Award(bob, "Welcome"), "nur einmal")
check(#Badges.Awarded == 1, "ein Aufruf an BadgeService")

-- Tutorial: Skip gibt nichts, Done das Badge
check(Badges.Trigger(bob, "Tutorial"), "Tutorial-Badge")
check(not Badges.Trigger(bob, "Tutorial"), "Tutorial-Badge nur einmal")

-- Erfolg auf GOLD -> Badge, Bronze/Silber nicht
local zombies = AchievementConfig.Get and AchievementConfig.Get("Zombies") or nil
local goldGoal = 5000
for _, achievement in AchievementConfig.List do
	if achievement.Id == "Zombies" then
		goldGoal = achievement.Goals[3]
	end
end
ProgressService.AddStat(bob, "ExtZombies", goldGoal - 1)
check(not Badges.Has(bob, "Ach_Zombies"), "vor GOLD kein Badge")
ProgressService.AddStat(bob, "ExtZombies", 1)
check(Badges.Has(bob, "Ach_Zombies") and awarded(bob, "Ach_Zombies"), "GOLD-Erfolg vergibt das Badge")

-- Ohne ID: vorgemerkt, nach Eintragen beim Laden nachgetragen
local convoysGoal = 40
for _, achievement in AchievementConfig.List do
	if achievement.Id == "Convoys" then
		convoysGoal = achievement.Goals[3]
	end
end
ProgressService.AddStat(bob, "ExtConvoys", convoysGoal)
check(ProgressService.Get(bob).Badges.Ach_Convoys == "Pending" and not awarded(bob, "Ach_Convoys"), "ohne BadgeId nur vorgemerkt")
SIM.Leave(bob)
SIM.Advance(1)
BadgeConfig.Get("Ach_Convoys").BadgeId = 4242
local bob2 = SIM.AddPlayer("Bob", 1001)
SIM.Advance(1)
check(awarded(bob2, "Ach_Convoys") and Badges.Has(bob2, "Ach_Convoys"), "vorgemerktes Badge nach dem Laden nachgetragen")
check(Badges.Has(bob2, "Welcome") and not awarded(bob2, "Welcome") or #Badges.Awarded == 4, "Welcome nicht nochmal vergeben")

-- Einladung: Freund tritt über Bobs Einladung bei
local coinsBefore = ProgressService.Get(bob2).Coins
SIM.JoinData[2002] = { ReferredByPlayerId = 1001 }
local friend = SIM.AddPlayer("Friend", 2002)
SIM.Advance(2)
check(ProgressService.Get(bob2).Coins == coinsBefore + InviteService.Reward, "Einladender bekommt Münzen")
check(Badges.Has(bob2, "Recruiter"), "Anwerber-Badge")
check(ProgressService.Get(bob2).Stats.Invites == 1, "Statistik Invites")
local banner = nil
for i = #SIM.RemoteLog, 1, -1 do
	local entry = SIM.RemoteLog[i]
	if entry.Remote == "Notify" and entry.Player == bob2 and entry.Args[1] == "Banner" then
		banner = entry.Args[2]
		break
	end
end
check(banner ~= nil and banner.Caption == "Einladung", "Meldung an den Einladenden")
-- derselbe Freund nochmal: nichts
SIM.Leave(friend)
SIM.Advance(1)
SIM.JoinData[2002] = { ReferredByPlayerId = 1001 }
SIM.AddPlayer("Friend", 2002)
SIM.Advance(2)
check(ProgressService.Get(bob2).Coins == coinsBefore + InviteService.Reward, "derselbe Freund zählt nur einmal")
-- Einladender nicht da: nichts, kein Fehler
SIM.JoinData[2003] = { ReferredByPlayerId = 999999 }
SIM.AddPlayer("Other", 2003)
SIM.Advance(2)
-- sich selbst einladen zählt nicht
SIM.JoinData[2004] = { ReferredByPlayerId = 2004 }
SIM.AddPlayer("Selfie", 2004)
SIM.Advance(2)
check(ProgressService.Get(bob2).Coins == coinsBefore + InviteService.Reward, "Fremde und Selbst-Einladung ändern nichts")

if failures == 0 then
	print("ok badges")
end

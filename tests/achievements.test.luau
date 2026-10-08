-- Erfolge-Wand (AchievementService): Stufen aus Statistiken (Bronze, Silber, Gold), Münzen und Meldung je Stufe,
-- Spieler-Attribut Achievements, kein doppeltes Vergeben, beim Laden verpasste Stufen nachtragen.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 1, 20)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local ProgressService = require("ProgressService")
local AchievementService = require("AchievementService")
local AchievementConfig = require("AchievementConfig")
ProgressService.Init()
AchievementService.Init()

-- Bob hat schon 150 Zombies (aus der Zeit vor den Erfolgen): beim Laden Bronze nachgetragen
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {}, Stats = { ExtZombies = 150 } }
store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
local bob = SIM.Join("Bob")
step(3)

local function tiers(player)
	return AchievementConfig.Data(player)
end
check(tiers(bob).Zombies == 1, "beim Laden nachgetragen (Bronze)")
check(ProgressService.Get(bob).Coins == AchievementConfig.Get("Zombies").Coins[1], "Münzen für nachgetragene Stufe")

-- Alice: Stufen nacheinander
ProgressService.AddStat(alice, "ExtZombies", 99)
check(tiers(alice).Zombies == nil, "99: noch nichts")
ProgressService.AddStat(alice, "ExtZombies", 1)
check(tiers(alice).Zombies == 1, "100: Bronze")
local coins = ProgressService.Get(alice).Coins
check(coins == AchievementConfig.Get("Zombies").Coins[1], "Bronze-Münzen")
local banner = nil
for i = #SIM.RemoteLog, 1, -1 do
	local entry = SIM.RemoteLog[i]
	if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" then
		banner = entry.Args[2]
		break
	end
end
check(banner and banner.Title == "ZOMBIE-SCHLÄCHTER" or (banner and string.find(banner.Title, "ZOMBIE", 1, true)), "Meldung")
ProgressService.AddStat(alice, "ExtZombies", 1)
check(ProgressService.Get(alice).Coins == coins, "nicht doppelt")
ProgressService.AddStat(alice, "ExtZombies", 5000)
check(tiers(alice).Zombies == 3, "über Gold: Silber und Gold auf einmal")
check(ProgressService.Get(alice).Coins == coins + AchievementConfig.Get("Zombies").Coins[2] + AchievementConfig.Get("Zombies").Coins[3],
	"Silber- und Gold-Münzen")
check(ProgressService.Get(alice).Achievements.Zombies == 3, "im Profil")

-- andere Statistik betrifft andere Erfolge nicht
ProgressService.AddStat(alice, "Kills", 1000)
check(tiers(alice).Players == nil, "Kills im Match zählen nicht für Kopfgeldjäger")

if failures == 0 then
	print("Erfolge in Ordnung")
end

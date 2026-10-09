-- Main (Script)
-- Startet alle Server-Systeme. Alle Modi laufen in diesem einen Place.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

-- Wächter: hängt der Start irgendwo (Modul, das nicht zurückkommt, DataStore-Aufruf ohne Antwort), steht im Output,
-- wo – sonst bekommt der Spieler nie einen Modus und sieht nur den Ladebildschirm.
local current = "Module laden"
task.spawn(function()
	local waited = 0
	while current do
		waited += task.wait(5)
		if current then
			warn(string.format("[Start] Server hängt seit %d s bei: %s", waited, current))
		end
	end
end)
local function start(name, init, ...)
	current = name
	init(...)
end

local ServerShared = ServerStorage:WaitForChild("ServerShared")
local WeaponService = require(ServerShared.WeaponService)
local KillService = require(ServerShared.KillService)
local AgentService = require(ServerShared.AgentService)
local ProgressService = require(ServerShared.ProgressService)
local ShopService = require(ServerShared.ShopService)
local DownedService = require(ServerShared.DownedService)
local BuyService = require(ServerShared.BuyService)
local GadgetService = require(ServerShared.GadgetService)
local PerkService = require(ServerShared.PerkService)
local PingService = require(ServerShared.PingService)
local LeaderboardService = require(ServerShared.LeaderboardService)
local RewardService = require(ServerShared.RewardService)
local AchievementService = require(ServerShared.AchievementService)
local KillstreakService = require(ServerShared.KillstreakService)
local RobuxService = require(ServerShared.RobuxService)
local ClanService = require(ServerShared.ClanService)
local MovementGuard = require(ServerShared.MovementGuard)
local BackWeapon = require(ServerShared.BackWeapon)
local EconomyService = require(ServerShared.EconomyService)
local TradeService = require(ServerShared.TradeService)
local CrateService = require(ServerShared.CrateService)
local InventoryService = require(ServerShared.InventoryService)
local KitService = require(ServerShared.KitService)
local LootService = require(ServerShared.LootService)
local Telemetry = require(ServerShared.Telemetry)
local DiscordLog = require(ServerShared.DiscordLog)
local PolicyGate = require(ServerShared.PolicyGate)
local BanService = require(ServerShared.BanService)
local Badges = require(ServerShared.Badges)
local InviteService = require(ServerShared.InviteService)
local ModeManager = require(script.Parent.ModeManager)
local AdminService = require(script.Parent.AdminService)
local PartyService = require(script.Parent.PartyService)
local MatchmakingService = require(script.Parent.MatchmakingService)

-- Charaktere spawnen nur, wenn ein Modus es sagt
Players.CharacterAutoLoads = false

start("DiscordLog.Init", DiscordLog.Init) -- Discord-Logs (Secret "DiscordLog"), fängt ab hier Fehler/Warnungen
start("BanService.Init", BanService.Init) -- zuerst: gesperrte Spieler sofort rauswerfen
start("Telemetry.Init", Telemetry.Init) -- Spielanalyse (AnalyticsService)
start("PolicyGate.Init", PolicyGate.Init) -- Roblox-Regeln je Land: bezahlte Zufallsitems (Kisten) und Handel
start("ProgressService.Init", ProgressService.Init)
start("ShopService.Init", ShopService.Init)
start("DownedService.Init", DownedService.Init)
start("BuyService.Init", BuyService.Init)
start("GadgetService.Init", GadgetService.Init)
start("PerkService.Init", PerkService.Init)
start("PingService.Init", PingService.Init)
start("LeaderboardService.Init", LeaderboardService.Init)
start("WeaponService.Init", WeaponService.Init)
start("KillService.Init", KillService.Init)
start("RewardService.Init", RewardService.Init)
start("AchievementService.Init", AchievementService.Init) -- Erfolge-Wand: Stufen bei jeder Statistik-Änderung prüfen
start("Badges.Init", Badges.Init) -- Roblox-Badges (Begrüßung, Tutorial, Anwerber, Erfolge auf GOLD)
start("InviteService.Init", InviteService.Init) -- Freunde einladen: Belohnung für den Einladenden
start("KillstreakService.Init", KillstreakService.Init) -- Killstreak-Belohnungen in Herrschaft (Radar, Luftschlag, Schutzschild)
start("RobuxService.Init", RobuxService.Init) -- Robux-Shop: Gamepässe und Entwicklerprodukte
start("ClanService.Init", ClanService.Init) -- Clans über alle Server
start("MovementGuard.Init", MovementGuard.Init) -- Bewegungs-Check gegen Speedhacks und Teleports
start("BackWeapon.Init", BackWeapon.Init) -- im Markt: Standardwaffe des Agenten auf dem Rücken
start("EconomyService.Init", EconomyService.Init) -- RAP: Rückverkauf, Reservierungen, Austausch (Markt und Tausch)
start("TradeService.Init", TradeService.Init) -- Tauschen zwischen Spielern in der Safe Zone und im Markt
start("CrateService.Init", CrateService.Init) -- Kisten öffnen (Waffen-Kiste) im Markt
start("InventoryService.Init", InventoryService.Init) -- offene Welt (Extinction): Tasche, Hotbar 1-9, Lager, Stände
start("KitService.Init", KitService.Init) -- Kit-Händler am Spawn im Camp (Starter Kit usw.)
start("LootService.Init", LootService.Init) -- offene Welt: Taschen am Boden (Tod, Zombie-Beute) mit E durchsuchen
start("AgentService.Init", AgentService.Init)
start("StaffService.Init", require(script.Parent.StaffService).Init) -- Team-Ränge, IsAdmin / IsMod
start("AdminService.Init", AdminService.Init, ModeManager)
start("PartyService.Init", PartyService.Init, ModeManager)
-- Arcade über mehrere Server: auf Server mit mehr Spielern im Modus wechseln, der Squad kommt mit
start("MatchmakingService.Init", MatchmakingService.Init, ModeManager, { Group = PartyService.Followers, Regroup = PartyService.Regroup })
start("ZentraleService.Init", require(script.Parent.ZentraleService).Init) -- Einsatzzentrale im Camp: Top-3-Statuen
start("ModeManager.Init", ModeManager.Init)
current = nil

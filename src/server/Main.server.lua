-- Main (Script)
-- Startet alle Server-Systeme. Alle Modi laufen in diesem einen Place.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

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
local BanService = require(ServerShared.BanService)
local Badges = require(ServerShared.Badges)
local InviteService = require(ServerShared.InviteService)
local ModeManager = require(script.Parent.ModeManager)
local AdminService = require(script.Parent.AdminService)
local PartyService = require(script.Parent.PartyService)
local MatchmakingService = require(script.Parent.MatchmakingService)

-- Charaktere spawnen nur, wenn ein Modus es sagt
Players.CharacterAutoLoads = false

BanService.Init() -- zuerst: gesperrte Spieler sofort rauswerfen
Telemetry.Init() -- Spielanalyse (AnalyticsService)
ProgressService.Init()
ShopService.Init()
DownedService.Init()
BuyService.Init()
GadgetService.Init()
PerkService.Init()
PingService.Init()
LeaderboardService.Init()
WeaponService.Init()
KillService.Init()
RewardService.Init()
AchievementService.Init() -- Erfolge-Wand: Stufen bei jeder Statistik-Änderung prüfen
Badges.Init() -- Roblox-Badges (Begrüßung, Tutorial, Anwerber, Erfolge auf GOLD)
InviteService.Init() -- Freunde einladen: Belohnung für den Einladenden
KillstreakService.Init() -- Killstreak-Belohnungen in Herrschaft (Radar, Luftschlag, Schutzschild)
RobuxService.Init() -- Robux-Shop: Gamepässe und Entwicklerprodukte
ClanService.Init() -- Clans über alle Server
MovementGuard.Init() -- Bewegungs-Check gegen Speedhacks und Teleports
BackWeapon.Init() -- im Hub: Standardwaffe des Agenten auf dem Rücken
EconomyService.Init() -- RAP: Rückverkauf, Reservierungen, Austausch (Markt und Tausch)
TradeService.Init() -- Tauschen zwischen Spielern im Hub und im Markt
CrateService.Init() -- Kisten öffnen (Waffen-Kiste) im Markt
InventoryService.Init() -- offene Welt (Extinction): Tasche, Hotbar 1-9, Lager, Stände
KitService.Init() -- Kit-Händler am Spawn im Camp (Starter Kit usw.)
LootService.Init() -- offene Welt: Taschen am Boden (Tod, Zombie-Beute) mit E durchsuchen
AgentService.Init()
require(script.Parent.StaffService).Init() -- Team-Ränge, IsAdmin / IsMod
AdminService.Init(ModeManager)
PartyService.Init(ModeManager)
-- Arcade über mehrere Server: auf Server mit mehr Spielern im Modus wechseln, der Squad kommt mit
MatchmakingService.Init(ModeManager, { Group = PartyService.Followers, Regroup = PartyService.Regroup })
ModeManager.Init()

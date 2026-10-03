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
local KillstreakService = require(ServerShared.KillstreakService)
local RobuxService = require(ServerShared.RobuxService)
local ClanService = require(ServerShared.ClanService)
local MovementGuard = require(ServerShared.MovementGuard)
local ModeManager = require(script.Parent.ModeManager)
local AdminService = require(script.Parent.AdminService)
local PartyService = require(script.Parent.PartyService)

-- Charaktere spawnen nur, wenn ein Modus es sagt
Players.CharacterAutoLoads = false

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
KillstreakService.Init() -- Killstreak-Belohnungen in Herrschaft (Radar, Luftschlag, Schutzschild)
RobuxService.Init() -- Robux-Shop: Gamepässe und Entwicklerprodukte
ClanService.Init() -- Clans über alle Server
MovementGuard.Init() -- Bewegungs-Check gegen Speedhacks und Teleports
AgentService.Init()
AdminService.Init(ModeManager)
PartyService.Init(ModeManager)
ModeManager.Init()

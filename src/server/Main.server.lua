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
local ModeManager = require(script.Parent.ModeManager)
local AdminService = require(script.Parent.AdminService)

-- Charaktere spawnen nur, wenn ein Modus es sagt
Players.CharacterAutoLoads = false

ProgressService.Init()
ShopService.Init()
DownedService.Init()
BuyService.Init()
GadgetService.Init()
PerkService.Init()
WeaponService.Init()
KillService.Init()
AgentService.Init()
AdminService.Init(ModeManager)
ModeManager.Init()

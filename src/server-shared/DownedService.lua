-- DownedService (ModuleScript, nur Server)
-- Niederschlagen und Wiederbeleben wie bei Rogue Company (nur im Drop-Modus):
--   * Tödlicher Schaden schlägt nieder statt zu töten: man liegt am Boden, kriecht langsam,
--     kann nicht schießen und verblutet nach BLEEDOUT_TIME Sekunden.
--   * Gegner können Niedergeschlagene "finishen" (weiter draufschießen).
--   * Teammitglieder beleben wieder: E halten (Spieler) bzw. automatisch (Bots), REVIVE_TIME Sekunden.
-- Charakter-Attribute: Downed (true), BleedoutUntil (Serverzeit), ReviveProgress (0 bis 1)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)
local BuyService = require(ServerStorage:WaitForChild("ServerShared").BuyService)
local BuyConfig = require(Shared.BuyConfig)

local DownedService = {}

local DOWNED_MODES = { Drop = true, Strikeout = true, Demolition = true, Wingman = true, Ranked = true,
	Extraction = true, TeamDeathmatch = true } -- hier wird niedergeschlagen statt getötet
local DOWNED_HEALTH = 40             -- Leben am Boden (so viel muss ein Gegner noch zum Finishen machen)
local BLEEDOUT_TIME = 20             -- Sekunden bis zum Verbluten
local REVIVE_TIME = 4                -- Sekunden E halten
local REVIVE_RANGE = 7               -- Studs Abstand zum Wiederbeleben
local REVIVE_HEALTH = 0.35           -- Anteil des Maximallebens nach dem Wiederbeleben

-- Wird gefeuert bei Niederschlagen, Wiederbeleben und Tod eines Niedergeschlagenen: (model)
local changedEvent = Instance.new("BindableEvent")
DownedService.Changed = changedEvent.Event
-- Verblutet: (model, attacker) – attacker = { Player = ..., BotName = ..., Weapon = ... }
local bledOutEvent = Instance.new("BindableEvent")
DownedService.BledOut = bledOutEvent.Event

local downed = {}    -- [model] = { Attacker, Until, Progress, Ticked }
local reviving = {}  -- [Player] = Ziel-Modell

-- Modus und Team eines Charakters (Spieler oder Bot)
local function modeOf(model)
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player:GetAttribute("Mode")
	end
	return model:GetAttribute("Mode")
end

local function teamOf(model)
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player.Team and player.Team.Name or nil
	end
	local teamName = model:GetAttribute("TeamName")
	return teamName ~= "" and teamName or nil
end

local function livingHumanoid(model)
	local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

function DownedService.IsDowned(model)
	return model ~= nil and model:GetAttribute("Downed") == true
end

-- Kann dieser Charakter niedergeschlagen werden (statt sofort zu sterben)?
function DownedService.CanBeDowned(model)
	return DOWNED_MODES[modeOf(model)] == true and not DownedService.IsDowned(model)
end

local function clear(model)
	downed[model] = nil
	if model.Parent then
		model:SetAttribute("Downed", nil)
		model:SetAttribute("BleedoutUntil", nil)
		model:SetAttribute("ReviveProgress", nil)
	end
	changedEvent:Fire(model)
end

-- Niederschlagen (vom Schadens-Modul aufgerufen)
function DownedService.Down(model, humanoid, attacker)
	humanoid.Health = math.min(DOWNED_HEALTH, humanoid.MaxHealth)
	downed[model] = { Attacker = attacker, Until = os.clock() + BLEEDOUT_TIME, Progress = 0, Ticked = false }
	model:SetAttribute("Downed", true)
	model:SetAttribute("BleedoutUntil", workspace:GetServerTimeNow() + BLEEDOUT_TIME)
	model:SetAttribute("ReviveProgress", 0)

	-- Bots steuert der Server: hinlegen
	if model:GetAttribute("IsBot") then
		local root = model:FindFirstChild("HumanoidRootPart")
		humanoid.PlatformStand = true
		if root then
			root.CFrame = CFrame.new(root.Position - Vector3.new(0, 1.5, 0)) * CFrame.Angles(math.rad(-90), 0, 0)
		end
	end

	humanoid.Died:Once(function()
		if downed[model] then
			clear(model)
		end
	end)
	changedEvent:Fire(model)
end

local function revive(model, reviverModel)
	local humanoid = livingHumanoid(model)
	if not humanoid then
		return
	end
	clear(model)
	humanoid.Health = humanoid.MaxHealth * REVIVE_HEALTH
	if model:GetAttribute("IsBot") then
		humanoid.PlatformStand = false
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = CFrame.new(root.Position + Vector3.new(0, 2, 0))
		end
	end
	-- XP für den Retter
	local reviver = reviverModel and Players:GetPlayerFromCharacter(reviverModel)
	if reviver then
		ProgressService.AddXP(reviver, ProgressService.ActiveAgent(reviver), AgentConfig.XPRewards.Revive, "Wiederbelebung")
		BuyService.AddMoney(reviver, BuyConfig.Rewards.Revive, "Wiederbelebung")
		ProgressService.QuestEvent(reviver, "Revive", 1)
		ProgressService.AddStat(reviver, "Revives", 1)
	end
end

-- Ein Schritt Wiederbeleben. Gibt false zurück, wenn es nicht (mehr) geht.
function DownedService.ReviveTick(reviverModel, targetModel, dt)
	local info = downed[targetModel]
	if not info or not livingHumanoid(reviverModel) or DownedService.IsDowned(reviverModel) then
		return false
	end
	if modeOf(reviverModel) ~= modeOf(targetModel) or teamOf(reviverModel) == nil
		or teamOf(reviverModel) ~= teamOf(targetModel) then
		return false
	end
	local a = reviverModel:FindFirstChild("HumanoidRootPart")
	local b = targetModel:FindFirstChild("HumanoidRootPart")
	if not a or not b or (a.Position - b.Position).Magnitude > REVIVE_RANGE then
		return false
	end
	local reviver = Players:GetPlayerFromCharacter(reviverModel)
	local speed = reviver and BuyConfig.Has(reviver, "Medic") and BuyConfig.MedicFactor or 1
	if AgentConfig.PassiveOf(reviverModel, "Revive") then
		speed *= 1.3 -- Passiv MENDER
	end
	info.Progress += dt * speed / REVIVE_TIME
	info.Ticked = true
	targetModel:SetAttribute("ReviveProgress", math.min(info.Progress, 1))
	if info.Progress >= 1 then
		revive(targetModel, reviverModel)
	end
	return true
end

-- Nächster niedergeschlagener Teamkollege in Reichweite
local function nearestDownedMate(reviverModel)
	local root = reviverModel:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best, bestDistance = nil, REVIVE_RANGE
	for model in downed do
		local targetRoot = model:FindFirstChild("HumanoidRootPart")
		if targetRoot and model ~= reviverModel and teamOf(model) ~= nil and teamOf(model) == teamOf(reviverModel) then
			local distance = (targetRoot.Position - root.Position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

-- Liste aller Niedergeschlagenen (für Bots)
function DownedService.All()
	local list = {}
	for model in downed do
		table.insert(list, model)
	end
	return list
end

function DownedService.Init()
	-- Spieler hält E (true) oder lässt los (false)
	Remotes.Revive.OnServerEvent:Connect(function(player, holding)
		if holding == true and player.Character then
			reviving[player] = nearestDownedMate(player.Character)
		else
			reviving[player] = nil
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		reviving[player] = nil
	end)

	-- Wiederbeleben vorantreiben, Fortschritt zurücksetzen wenn unterbrochen, Verbluten prüfen
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 0.1 then
			return
		end
		local step = accumulated
		accumulated = 0

		for player, target in reviving do
			if not DownedService.ReviveTick(player.Character, target, step) then
				reviving[player] = nil
			end
		end
		for model, info in downed do
			if not info.Ticked and info.Progress > 0 then
				info.Progress = 0
				model:SetAttribute("ReviveProgress", 0)
			end
			info.Ticked = false
			if os.clock() >= info.Until then
				local humanoid = livingHumanoid(model)
				local attacker = info.Attacker
				clear(model)
				if humanoid then
					humanoid.Health = 0
					bledOutEvent:Fire(model, attacker)
				end
			end
		end
	end)
end

return DownedService

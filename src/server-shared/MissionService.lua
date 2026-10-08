-- MissionService (ModuleScript, nur Server)
-- Aufträge der offenen Welt (EXTINCTION): jeder Spieler hat ExtinctionConfig.Missions.Active Aufträge gleichzeitig
-- (zufällig aus Pool, keine zwei gleichen). Fortschritt kommt aus den anderen Diensten:
--   Zombie/Runner/Brute/RedZombie  ZombieService.OnKill (Walker zählt als Zombie, jede Art zählt auch für "Zombie")
--   Nest/Cache/Survivor            ActivityService.OnEvent
--   Airdrop                        LootService.OnOpened (Lootdrop-Kiste geöffnet, je Kiste einmal)
--   Place                          Spieler steht im Ort des Auftrags (Gruppe Places der Karte)
--   NightMinute                    jede volle Minute draußen in der Nacht (DayCycle)
-- Erledigt: Münzen und Beute direkt ins Inventar, Meldung, ein neuer Auftrag. Für den Client steht die Liste als JSON im
-- Spieler-Attribut "ExtMissions": [{ Text, Have, Need, Coins }]. Gilt für die Sitzung (nicht gespeichert).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local DayCycle = require(Shared.DayCycle)
local ProgressService = require(script.Parent.ProgressService)
local LootService = require(script.Parent.LootService)
local ZombieService = require(script.Parent.ZombieService)
local ActivityService = require(script.Parent.ActivityService)

local MissionService = {}
MissionService.OnComplete = {} -- Rückrufe function(player, def) nach jedem erledigten Auftrag (z.B. Extinction-EP)

local M = ExtinctionConfig.Missions
local random = Random.new()
local options = nil -- { Map, InSafeZone(position), RedzoneAt(position), IsMember(player) }
local states = {}   -- [Player] = { Missions = { { Def, Need, Have, Place } }, Night = Sekunden, Drops = { [bagId] = true } }
local places = {}   -- { { Key, Title, Position, Radius } } (ohne Camp und große Bereiche)

local function publish(player)
	local state = states[player]
	if not state then
		player:SetAttribute("ExtMissions", nil)
		return
	end
	local list = {}
	for _, mission in state.Missions do
		table.insert(list, { Text = mission.Text, Have = mission.Have, Need = mission.Need, Coins = mission.Def.Coins })
	end
	player:SetAttribute("ExtMissions", HttpService:JSONEncode(list))
end

local function newMission(state)
	local taken = {}
	for _, mission in state.Missions do
		taken[mission.Def.Id] = true
	end
	local choices = {}
	for _, def in M.Pool do
		if not taken[def.Id] and (def.Event ~= "Place" or #places > 0) then
			table.insert(choices, def)
		end
	end
	if #choices == 0 then
		return nil
	end
	local def = choices[random:NextInteger(1, #choices)]
	local need = random:NextInteger(def.Count[1], def.Count[2])
	local mission = { Def = def, Need = need, Have = 0 }
	if def.Event == "Place" then
		local place = places[random:NextInteger(1, #places)]
		mission.Place = place
		mission.Text = string.format(def.Text, place.Title)
	else
		mission.Text = string.format(def.Text, need)
	end
	return mission
end

local function complete(player, state, index)
	local mission = state.Missions[index]
	local def = mission.Def
	ProgressService.AddCoins(player, def.Coins, "Auftrag")
	LootService.Grab(player, ExtinctionConfig.RollLoot(def.Table, random:NextInteger(def.Items[1], def.Items[2]), random))
	Remotes.Notify:FireClient(player, "Banner", { Caption = "Auftrag", Title = "AUFTRAG ERLEDIGT",
		Sub = mission.Text .. " · +" .. def.Coins .. " Münzen", Style = "Good" })
	table.remove(state.Missions, index)
	for _, callback in MissionService.OnComplete do
		task.spawn(callback, player, def)
	end
	local fresh = newMission(state)
	if fresh then
		table.insert(state.Missions, fresh)
	end
end

-- Fortschritt melden: event wie in Pool[].Event, amount (Standard 1), place = Ort-Schlüssel (nur "Place")
function MissionService.Progress(player, event, amount, place)
	local state = states[player]
	if not state then
		return
	end
	local changed = false
	for index = #state.Missions, 1, -1 do
		local mission = state.Missions[index]
		if mission.Def.Event == event and (event ~= "Place" or (mission.Place and mission.Place.Key == place)) then
			mission.Have = math.min(mission.Need, mission.Have + (amount or 1))
			changed = true
			if mission.Have >= mission.Need then
				complete(player, state, index)
			end
		end
	end
	if changed then
		publish(player)
	end
end

function MissionService.Join(player)
	local state = { Missions = {}, Night = 0, Drops = {} }
	states[player] = state
	for _ = 1, M.Active do
		local mission = newMission(state)
		if mission then
			table.insert(state.Missions, mission)
		end
	end
	publish(player)
end

function MissionService.Leave(player)
	states[player] = nil
	if player.Parent then
		publish(player)
	end
end

function MissionService.Get(player)
	return states[player]
end

local function livingRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return root
	end
	return nil
end

-- jede Sekunde: Orte und Nacht-Minuten
function MissionService.Step(seconds)
	local night = DayCycle.IsNight(DayCycle.Clock(workspace:GetServerTimeNow()))
	for player, state in states do
		local root = livingRoot(player)
		if root and not options.InSafeZone(root.Position) then
			for _, mission in state.Missions do
				local place = mission.Place
				if place and Vector3.new(root.Position.X - place.Position.X, 0, root.Position.Z - place.Position.Z).Magnitude <= place.Radius then
					MissionService.Progress(player, "Place", 1, place.Key)
					break
				end
			end
			if night then
				state.Night += seconds
				if state.Night >= 60 then
					state.Night -= 60
					MissionService.Progress(player, "NightMinute", 1)
				end
			end
		end
	end
end

-- opts = { Map, InSafeZone(position), RedzoneAt(position) }
function MissionService.Init(opts)
	options = opts
	places = {}
	local folder = opts.Map:FindFirstChild("Places")
	for _, part in folder and folder:GetChildren() or {} do
		local key = part:IsA("BasePart") and string.match(part.Name, "^Place_(.+)$")
		-- nur Orte, die man gezielt besuchen kann (nicht das Camp und keine riesigen Bereiche)
		if key and key ~= "Camp" and part.Size.X <= 500 then
			table.insert(places, { Key = key, Title = part:GetAttribute("Title") or key, Position = part.Position,
				Radius = part.Size.X / 2 })
		end
	end
	table.insert(ZombieService.OnKill, function(killer, kind, position)
		MissionService.Progress(killer, "Zombie")
		if kind == "Runner" or kind == "Brute" then
			MissionService.Progress(killer, kind)
		end
		if options.RedzoneAt and options.RedzoneAt(position) then
			MissionService.Progress(killer, "RedZombie")
		end
	end)
	table.insert(ActivityService.OnEvent, function(player, kind)
		MissionService.Progress(player, kind)
	end)
	table.insert(LootService.OnOpened, function(player, bag)
		local state = states[player]
		if state and bag.Kind == "Airdrop" and not state.Drops[bag.Id] then
			state.Drops[bag.Id] = true
			MissionService.Progress(player, "Airdrop")
		end
	end)
	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last >= 1 then
			MissionService.Step(now - last)
			last = now
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return MissionService

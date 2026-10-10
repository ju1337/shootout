-- StormService (ModuleScript, nur Server)
-- Sturmnacht der offenen Welt (EXTINCTION), Werte in ExtinctionConfig.Storm:
--   * alle Interval Sekunden (das erste Mal nach FirstDelay, nie während des Blutmonds), Warning Sekunden vorher Ansage,
--   * PvP ist während des Sturms und Grace Sekunden danach für alle aus (Extinction.updateZone liest
--     DayCycle.StormPvPPaused),
--   * mehr Zombies, meist gepanzert (ZombieService liest DayCycle.IsStorm); alle WaveInterval Sekunden eine Welle bei
--     jedem Spieler draußen (WaveSize gepanzerte und ein gepanzerter Brocken),
--   * Blitze bei Spielern draußen: Schaden im Umkreis (Spieler und Zombies), Remote StormStrike für Licht und Donner,
--   * gemeinsames Ziel: Goal gepanzerte Zombies; wer im Sturm einen Zombie erledigt hat, bekommt am Ende die Belohnung
--     (Ziel erreicht: Reward, sonst FailCoins).
-- Zustand für alle: Attribute StormStart / StormEnd / StormKills / StormGoal an ReplicatedStorage.
-- Start(duration) startet sofort (Admin), Stop() beendet (mit Belohnung).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local DayCycle = require(Shared.DayCycle)
local ZombieService = require(script.Parent.ZombieService)
local Damage = require(script.Parent.Damage)
local ProgressService = require(script.Parent.ProgressService)
local RedPointsService = require(script.Parent.RedPointsService)
local InventoryService = require(script.Parent.InventoryService)

local StormService = {}

local S = ExtinctionConfig.Storm
local options = nil -- { Players() -> { Player }, InSafeZone(position) }
local nextStart = math.huge
local warned = false
local active = false      -- läuft gerade (für das Ende mit Belohnung)
local nextWave = math.huge
local nextStrike = math.huge
local fighters = {}       -- [Player] = true: hat im Sturm einen Zombie erledigt
local random = Random.new()
local running = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function announce(title, sub, style)
	if not (options and options.Players) then
		return
	end
	for _, player in options.Players() do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Storm Night", Title = title, Sub = sub, Style = style or "Warning" })
	end
end

-- Lebende Spieler draußen (nicht in einer Safe Zone): { { Player, Root } }
local function outside()
	local list = {}
	for _, player in options and options.Players() or {} do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and not options.InSafeZone(root.Position) then
			table.insert(list, { Player = player, Root = root })
		end
	end
	return list
end

function StormService.Active()
	return DayCycle.IsStorm(now())
end

-- ---------- Wellen ----------

local function wave()
	for _, entry in outside() do
		ZombieService.SpawnAround(entry.Root.Position, S.WaveSize, 40, 80, "Random", true, true)
		ZombieService.SpawnAround(entry.Root.Position, 1, 50, 80, "Brute", true, true)
	end
end

-- ---------- Blitze ----------

-- Einschlag bei position: alle Spieler und Zombies im Umkreis bekommen Schaden (Safe Zone schützt Damage selbst)
local function strikeAt(position)
	Remotes.StormStrike:FireAllClients(position)
	local L = S.Lightning
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, model in ZombieService.All() do
		table.insert(list, model)
	end
	for _, model in list do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			local offset = root.Position - position
			if Vector2.new(offset.X, offset.Z).Magnitude <= L.Radius and math.abs(offset.Y) <= 14 then
				Damage.Apply(model, humanoid, L.Damage, nil)
			end
		end
	end
end

-- Blitz bei einem zufälligen Spieler draußen (meist ein Stück weg, manchmal ganz nah)
local function strike()
	local candidates = outside()
	if #candidates == 0 then
		return
	end
	local L = S.Lightning
	local pick = candidates[random:NextInteger(1, #candidates)]
	local near = random:NextNumber() < L.NearChance
	for _ = 1, 6 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = near and random:NextNumber(L.NearMin, L.NearMax) or random:NextNumber(L.MinDistance, L.MaxDistance)
		local x = pick.Root.Position.X + math.cos(angle) * distance
		local z = pick.Root.Position.Z + math.sin(angle) * distance
		local point = ZombieService.GroundAt(x, z)
		if point and not options.InSafeZone(point) then
			strikeAt(point)
			return
		end
	end
end

-- ---------- Ziel und Belohnung ----------

local function goalFor(count)
	local G = S.Goal
	return math.clamp(count * G.PerPlayer, G.Min, G.Max)
end

local function reward()
	local kills = ReplicatedStorage:GetAttribute("StormKills") or 0
	local goal = ReplicatedStorage:GetAttribute("StormGoal") or 1
	local won = kills >= goal
	-- nur wer noch in der offenen Welt ist (nicht wer inzwischen in einen anderen Modus gewechselt hat)
	local present = {}
	for _, player in options and options.Players() or {} do
		present[player] = true
	end
	for player in fighters do
		if player.Parent and present[player] then
			if won then
				local R = S.Reward
				ProgressService.AddCoins(player, R.Coins, "Storm Night")
				ProgressService.QuestEvent(player, "XStorm", 1)
				RedPointsService.Add(player, R.RedPoints, "Storm Night")
				local names = {}
				local rolled = {}
				for _, roll in R.Items do
					for _, item in ExtinctionConfig.RollLoot(roll[1], roll[2], random) do
						table.insert(rolled, item)
					end
				end
				ExtinctionConfig.AddDungeonKey(rolled, "Storm", random)
				for _, item in rolled do
					local put = InventoryService.GiveStash(player, item.Id, item.Count)
					if put < item.Count then
						put += InventoryService.Give(player, item.Id, item.Count - put)
					end
					local config = ExtinctionConfig.Get(item.Id)
					if put > 0 and config then
						table.insert(names, (put > 1 and (put .. "× ") or "") .. config.Name)
					end
				end
				Remotes.Notify:FireClient(player, "Banner", { Caption = "Storm Night", Title = "STORM CRATE",
					Sub = R.Coins .. " coins · " .. R.RedPoints .. " RZ · " .. table.concat(names, ", ") .. " (in your stash)",
					Style = "Good" })
			else
				ProgressService.AddCoins(player, S.FailCoins, "Storm Night")
			end
		end
	end
	if won then
		announce("THE STORM IS OVER", "Goal reached (" .. kills .. "/" .. goal .. ") · every fighter got a storm crate · PvP in "
			.. S.Grace .. " s", "Good")
	else
		announce("THE STORM IS OVER", "Goal missed (" .. kills .. "/" .. goal .. ") · fighters get " .. S.FailCoins
			.. " coins · PvP in " .. S.Grace .. " s", "Info")
	end
	table.clear(fighters)
end

-- ---------- Ablauf ----------

function StormService.Start(duration)
	local t = now()
	duration = duration or S.Duration
	-- ein laufender Blutmond endet (nie beide gleichzeitig)
	if DayCycle.IsBloodMoon(t) then
		ReplicatedStorage:SetAttribute("BloodMoonEnd", t)
	end
	table.clear(fighters)
	local goal = goalFor(math.max(1, #outside()))
	ReplicatedStorage:SetAttribute("StormStart", t)
	ReplicatedStorage:SetAttribute("StormEnd", t + duration)
	ReplicatedStorage:SetAttribute("StormKills", 0)
	ReplicatedStorage:SetAttribute("StormGoal", goal)
	active = true
	nextWave = t + S.FirstWave
	nextStrike = t + 3
	nextStart = t + math.max(S.Interval, duration + 120)
	warned = false
	announce("STORM NIGHT", "PvP is OFF · everyone vs. armored zombies · together kill " .. goal .. " armored", "Warning")
end

function StormService.Stop()
	local t = now()
	if DayCycle.IsStorm(t) then
		ReplicatedStorage:SetAttribute("StormEnd", t)
	end
end

-- Einmal pro Sekunde: Warnung, Start, Wellen, Blitze, Ende
function StormService.Step()
	local t = now()
	if DayCycle.IsStorm(t) then
		if t >= nextWave then
			nextWave = t + S.WaveInterval
			wave()
		end
		if t >= nextStrike then
			nextStrike = t + random:NextNumber(S.Lightning.MinEvery, S.Lightning.MaxEvery)
			strike()
		end
		return
	end
	if active then
		active = false
		nextWave, nextStrike = math.huge, math.huge
		reward()
	end
	-- nie während des Blutmonds: dann nach seinem Ende
	if DayCycle.IsBloodMoon(t) and t >= nextStart - S.Warning then
		nextStart = (tonumber(ReplicatedStorage:GetAttribute("BloodMoonEnd")) or t) + S.Warning + 120
		warned = false
		return
	end
	if not warned and t >= nextStart - S.Warning then
		warned = true
		announce("A STORM IS COMING", "In " .. S.Warning .. " seconds · PvP will be paused · armored zombies incoming", "Warning")
	end
	if t >= nextStart then
		StormService.Start()
	end
end

-- opts = { Players(), InSafeZone(position), Loop (Standard true) }
function StormService.Init(opts)
	options = opts
	running += 1
	local run = running
	nextStart = S.Enabled and (now() + S.FirstDelay) or math.huge
	-- Zombies im Sturm: wer einen erledigt, kämpft mit; gepanzerte zählen fürs gemeinsame Ziel
	table.insert(ZombieService.OnKill, function(killer, _, _, armored, dungeon)
		if dungeon or not DayCycle.IsStorm(now()) then
			return -- Kills im Dungeon zählen nicht für den Sturm draußen
		end
		fighters[killer] = true
		if armored then
			ReplicatedStorage:SetAttribute("StormKills", (ReplicatedStorage:GetAttribute("StormKills") or 0) + 1)
			local kills, goal = ReplicatedStorage:GetAttribute("StormKills"), ReplicatedStorage:GetAttribute("StormGoal") or 0
			if kills == goal then
				announce("GOAL REACHED", "Everyone who fought gets a storm crate when the storm ends", "Good")
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		fighters[player] = nil
	end)
	if opts.Loop ~= false then
		task.spawn(function()
			while run == running do
				task.wait(1)
				StormService.Step()
			end
		end)
	end
end

return StormService

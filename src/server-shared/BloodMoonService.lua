-- BloodMoonService (ModuleScript, nur Server)
-- Blutmond der offenen Welt (EXTINCTION) als Ereignis von ExtinctionConfig.BloodMoon.Duration Sekunden (10 Minuten):
--   * alle Interval Sekunden (das erste Mal nach FirstDelay), Warning Sekunden vorher eine Ansage an alle draußen,
--   * beim Start wird es Nacht (StartClock, DayCycle.SetClock), das Licht rot (MapAtmosphere),
--   * Zombies: mehr, härtere Arten, zäher/stärker/schneller, bessere Beute (ZombieService liest DayCycle.IsBloodMoon),
--   * Bosse ("Blutbestie", ZombieKinds.Boss): alle BossInterval Sekunden einer in der Nähe eines Spielers draußen,
--     höchstens MaxBosses gleichzeitig; Ansage beim Erscheinen und beim Tod (wer ihn erledigt hat).
-- Zustand für alle: Attribute BloodMoonStart / BloodMoonEnd (Serverzeit) an ReplicatedStorage.
-- Start(duration) startet sofort (Admin), Stop() beendet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local DayCycle = require(Shared.DayCycle)
local ZombieService = require(script.Parent.ZombieService)

local BloodMoonService = {}

local B = ExtinctionConfig.BloodMoon
local options = nil -- { Players() -> { Player }, InSafeZone(position), IsWater(x, z) }
local nextStart = math.huge
local warned = false
local nextBoss = math.huge
local bosses = {} -- [Model] = true
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
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Blutmond", Title = title, Sub = sub, Style = style or "Warning" })
	end
end

function BloodMoonService.Active()
	return DayCycle.IsBloodMoon(now())
end

function BloodMoonService.Bosses()
	local list = {}
	for model in bosses do
		if model.Parent then
			table.insert(list, model)
		else
			bosses[model] = nil
		end
	end
	return list
end

-- Boss bei einem zufälligen Spieler draußen (nil, wenn keiner draußen ist oder kein Platz gefunden wurde)
function BloodMoonService.SpawnBoss()
	if not options then
		return nil
	end
	local candidates = {}
	for _, player in options.Players() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and not options.InSafeZone(root.Position) then
			table.insert(candidates, { Player = player, Root = root })
		end
	end
	if #candidates == 0 then
		return nil
	end
	local pick = candidates[random:NextInteger(1, #candidates)]
	local model = nil
	for _ = 1, 4 do -- nicht in einer Safe Zone auftauchen
		local spawned = ZombieService.SpawnAround(pick.Root.Position, 1, B.BossMinDistance, B.BossMaxDistance, "Boss", true)
		model = spawned and spawned[1]
		if model and options.InSafeZone(model:GetPivot().Position) then
			model:Destroy()
			model = nil
		elseif model then
			break
		end
	end
	if model then
		bosses[model] = true
		announce("EINE BLUTBESTIE IST ERWACHT", "In der Nähe von " .. pick.Player.Name .. " · töte sie für die beste Beute", "Warning")
	end
	return model
end

function BloodMoonService.Start(duration)
	local t = now()
	duration = duration or B.Duration
	ReplicatedStorage:SetAttribute("BloodMoonStart", t)
	ReplicatedStorage:SetAttribute("BloodMoonEnd", t + duration)
	DayCycle.SetClock(B.StartClock, t)
	nextBoss = t + B.FirstBoss
	nextStart = t + math.max(B.Interval, duration + 60)
	warned = false
	announce("BLUTMOND", math.floor(duration / 60) .. " Minuten · stärkere Zombies · bessere Beute · Bosse", "Warning")
end

function BloodMoonService.Stop()
	local t = now()
	if DayCycle.IsBloodMoon(t) then
		ReplicatedStorage:SetAttribute("BloodMoonEnd", t)
	end
	nextBoss = math.huge
end

-- Einmal pro Sekunde: Warnung, Start, Bosse
function BloodMoonService.Step()
	local t = now()
	if DayCycle.IsBloodMoon(t) then
		if t >= nextBoss then
			nextBoss = t + B.BossInterval
			if #BloodMoonService.Bosses() < B.MaxBosses then
				BloodMoonService.SpawnBoss()
			end
		end
		return
	end
	-- nie während der Sturmnacht: dann nach ihrem Ende
	if DayCycle.IsStorm(t) and t >= nextStart - B.Warning then
		nextStart = (tonumber(ReplicatedStorage:GetAttribute("StormEnd")) or t) + B.Warning + 120
		warned = false
		return
	end
	if not warned and t >= nextStart - B.Warning then
		warned = true
		announce("DER BLUTMOND STEIGT AUF", "In " .. B.Warning .. " Sekunden · sucht euch Deckung oder Beute", "Warning")
	end
	if t >= nextStart then
		BloodMoonService.Start()
	end
end

-- opts = { Players(), InSafeZone(position), Loop (Standard true) }
function BloodMoonService.Init(opts)
	options = opts
	running += 1
	local run = running
	nextStart = B.Enabled and (now() + B.FirstDelay) or math.huge
	-- Boss erledigt: Ansage an alle
	table.insert(ZombieService.OnKill, function(killer, kind)
		if kind == "Boss" then
			announce("BLUTBESTIE ERLEDIGT", killer.Name .. " hat sie zur Strecke gebracht · Beute liegt in der Leiche", "Good")
		end
	end)
	if opts.Loop ~= false then
		task.spawn(function()
			while run == running do
				task.wait(1)
				BloodMoonService.Step()
			end
		end)
	end
end

return BloodMoonService

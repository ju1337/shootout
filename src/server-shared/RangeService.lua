-- RangeService (ModuleScript, nur Server)
-- Schießstand im Camp neben dem Versteck (WorkshopConfig.Range, gebaut in tools/camp_phoenix.py): E am Punkt Range_Start
-- startet eine Runde (immer nur ein Spieler gleichzeitig). Solange sie läuft und der Spieler im Feld Range_Zone steht, hat
-- er das Attribut RangeActive und darf in der Safe Zone schießen – WeaponService fragt RangeTargets und trifft nur die
-- gerade stehenden Ziele (Range_Target1 …, Mitte Range_Bull1 …), kein Schaden an irgendwem, Munition gratis.
-- Ziele klappen nacheinander auf (sichtbar und treffbar), ein Treffer zählt Points (Mitte Bullseye) und klappt das Ziel
-- weg. Am Ende: Bestwert im Profil (Hideout.RangeBest), einmal am Tag DailyCoins ab DailyScore.
-- Meldungen an den Spieler über Remotes.RangeUpdate: "Start" { Duration, Ends }, "Hit" { Score, Gain }, "End" { Score, Best,
-- Reward }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorkshopConfig = require(Shared.WorkshopConfig)
local Zentrale = require(Shared.Zentrale)
local Remotes = require(Shared.Remotes)
local ProgressService = require(script.Parent.ProgressService)
local WeaponService = require(script.Parent.WeaponService)
local HideoutService = require(script.Parent.HideoutService)

local RangeService = {}

local R = WorkshopConfig.Range
local startPoint, zone = nil, nil
local targets = {} -- { { Board, Bull, Up } }
local round = nil  -- { Player, Ends, Score, Next, Current }
local random: any = nil -- erst bei der ersten Runde anlegen

function RangeService.SetRandom(r)
	random = r
end

local function setUp(target, up)
	target.Up = up
	for _, part in { target.Board, target.Bull } do
		if part then
			part.Transparency = up and 0 or 1
			part.CanQuery = up
		end
	end
end

local function inZone(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not zone or not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local p = zone.CFrame:PointToObjectSpace(root.Position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y <= half.Y + 4 and p.Y >= -half.Y - 4
end

local function finish()
	local current = round
	if not current then
		return
	end
	round = nil
	for _, target in targets do
		setUp(target, false)
	end
	local player = current.Player
	if not player.Parent then
		return
	end
	player:SetAttribute("RangeActive", nil)
	local profile = ProgressService.Get(player)
	local reward = 0
	local best = current.Score
	if profile then
		profile.Hideout = type(profile.Hideout) == "table" and profile.Hideout or {}
		local data = profile.Hideout
		best = math.max(tonumber(data.RangeBest) or 0, current.Score)
		data.RangeBest = best
		local day = WorkshopConfig.Day()
		if current.Score >= R.DailyScore and data.RangeDay ~= day then
			data.RangeDay = day
			reward = R.DailyCoins
			ProgressService.AddCoins(player, reward, "Schießstand")
		end
		HideoutService.Publish(player)
	end
	Remotes.RangeUpdate:FireClient(player, "End", { Score = current.Score, Best = best, Reward = reward })
end

function RangeService.Start(player)
	if round then
		if round.Player ~= player then
			Remotes.RangeUpdate:FireClient(player, "Busy", { Name = round.Player.DisplayName })
		end
		return false
	end
	if not inZone(player) or #targets == 0 then
		return false
	end
	local now = workspace:GetServerTimeNow()
	round = { Player = player, Ends = now + R.Duration, Score = 0, Next = now + 1, Current = nil }
	player:SetAttribute("RangeActive", true)
	Remotes.RangeUpdate:FireClient(player, "Start", { Duration = R.Duration, Ends = round.Ends })
	return true
end

-- Ziele, auf die player gerade schießen darf (nur während seiner Runde im Feld)
function RangeService.Targets(player)
	if not round or round.Player ~= player or not inZone(player) then
		return nil
	end
	local list = {}
	for _, target in targets do
		if target.Up then
			table.insert(list, target.Board)
			if target.Bull then
				table.insert(list, target.Bull)
			end
		end
	end
	return list
end

function RangeService.Hit(player, part)
	if not round or round.Player ~= player then
		return
	end
	for _, target in targets do
		if target.Up and (part == target.Board or part == target.Bull) then
			local gain = part == target.Bull and R.Bullseye or R.Points
			round.Score += gain
			setUp(target, false)
			round.Current = nil
			round.Next = workspace:GetServerTimeNow() + R.Gap
			Remotes.RangeUpdate:FireClient(player, "Hit", { Score = round.Score, Gain = gain })
			return
		end
	end
end

function RangeService.Step()
	if not round then
		return
	end
	local now = workspace:GetServerTimeNow()
	if not round.Player.Parent or not inZone(round.Player) or now >= round.Ends then
		finish()
		return
	end
	if round.Current and now >= round.Current.Until then
		setUp(round.Current.Target, false) -- verpasst
		round.Current = nil
		round.Next = now + R.Gap
	end
	if not round.Current and now >= round.Next then
		random = random or Random.new()
		local target = targets[random:NextInteger(1, #targets)]
		setUp(target, true)
		round.Current = { Target = target, Until = now + R.UpTime }
	end
end

function RangeService.Current()
	return round
end

-- opts = { Map }
function RangeService.Init(opts)
	local folder = opts.Map and opts.Map:FindFirstChild(Zentrale.Group)
	startPoint = folder and folder:FindFirstChild(R.Point)
	zone = folder and folder:FindFirstChild(R.Zone)
	if not (startPoint and startPoint:IsA("BasePart") and zone and zone:IsA("BasePart")) then
		warn("RangeService: Schießstand fehlt im Camp (" .. R.Point .. ", " .. R.Zone .. ")")
		return
	end
	for i = 1, 20 do
		local board = folder:FindFirstChild(R.Targets .. i)
		if not board then
			break
		end
		local target = { Board = board, Bull = folder:FindFirstChild("Range_Bull" .. i), Up = false }
		setUp(target, false)
		table.insert(targets, target)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RangePrompt"
	prompt.ActionText = "Runde starten"
	prompt.ObjectText = "Schießstand"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = startPoint
	prompt.Triggered:Connect(function(player)
		RangeService.Start(player)
	end)
	WeaponService.RangeTargets = RangeService.Targets
	WeaponService.RangeHit = RangeService.Hit
	Players.PlayerRemoving:Connect(function(player)
		if round and round.Player == player then
			finish()
		end
	end)
	RunService.Heartbeat:Connect(function()
		RangeService.Step()
	end)
end

return RangeService

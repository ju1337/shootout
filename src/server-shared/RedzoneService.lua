-- RedzoneService (ModuleScript, nur Server)
-- Rote Zonen der offenen Welt (EXTINCTION): gefährliche Gebiete mit besserer Beute. Die Karte legt sie als Teile
-- "Redzone_<Name>" in der Gruppe Redzones ab (Block, Breite = Durchmesser; nur die Lage und Größe zählen, die Optik baut die
-- Karte). Drinnen (ExtinctionConfig.Redzone):
--   * PvP gilt sofort (keine Wartezeit nach der Safe Zone),
--   * mehr Zombies um jeden Spieler (PerPlayerFactor) mit Läufern und Brocken, die innerhalb der Zone spawnen,
--   * Lagerkisten in der Zone ziehen aus Tier3 (ContainerService), Lootdrops landen bevorzugt dort (AirdropService).
-- Für die Clients steht die Liste als JSON im Attribut "Redzones" an der Karte: [{ Name, X, Z, R }].
-- Spieler-Attribut "Redzone" (Name der Zone oder nil) setzt der Modus (Modes/Extinction).
--
-- Wanderzone (ExtinctionConfig.MovingZone): eine zusätzliche rote Zone, die alle Interval Sekunden (20 Minuten) an einen
-- anderen Ort der Karte springt (Teile Place_<Name> der Gruppe Places, ohne Camp, Seen, große Flächen und feste rote
-- Zonen). Drinnen gilt dasselbe wie in roten Zonen (At liefert sie). Ansage an alle draußen beim Wechsel und eine Minute
-- vorher; in der Welt steht eine flimmernde Wand (ForceField) mit Lichtsäule in der Mitte. Für die Clients im Attribut
-- "MovingZone" an der Karte: { Name, X, Z, R, Ends } (Ends = Serverzeit des nächsten Wechsels). Jeden Wechsel meldet
-- OnMoved(callback) (RedzoneBoard beginnt dann für die Wanderzone eine neue Rangliste).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Remotes = require(Shared.Remotes)

local RedzoneService = {}

local zones = {} -- { { Name, Center (Vector3), Radius, Title } }
local moving = nil -- { Name, Title, Center, Radius, Moving = true, Ends, Key }
local movingOptions = nil
local movingFolder = nil
local movingRun = 0
local movedCallbacks = {} -- callback(moving) nach jedem Wechsel der Wanderzone (z.B. RedzoneBoard)

-- map = Maps.Extinction (Gruppe Redzones mit Teilen Redzone_<Name>)
function RedzoneService.Init(map)
	zones = {}
	local folder = map:FindFirstChild("Redzones")
	for _, part in folder and folder:GetChildren() or {} do
		local name = string.match(part.Name, "^Redzone_(.+)$")
		if name and part:IsA("BasePart") then
			table.insert(zones, { Name = name, Title = part:GetAttribute("Title") or name, Center = part.Position, Radius = part.Size.X / 2 })
		end
	end
	table.sort(zones, function(a, b)
		return a.Name < b.Name
	end)
	local list = {}
	for _, zone in zones do
		table.insert(list, { Name = zone.Title, X = zone.Center.X, Z = zone.Center.Z, R = zone.Radius })
	end
	map:SetAttribute("Redzones", HttpService:JSONEncode(list))
end

-- Rote Zone an einer Stelle (flacher Abstand) oder nil; die Wanderzone zählt mit
function RedzoneService.At(position)
	for _, zone in zones do
		if Vector3.new(position.X - zone.Center.X, 0, position.Z - zone.Center.Z).Magnitude <= zone.Radius then
			return zone
		end
	end
	if moving and Vector3.new(position.X - moving.Center.X, 0, position.Z - moving.Center.Z).Magnitude <= moving.Radius then
		return moving
	end
	return nil
end

-- ---------- Wanderzone ----------
local function now()
	return workspace:GetServerTimeNow()
end

-- Orte, an die die Wanderzone springen kann: { Key, Title, Center }
function RedzoneService.MovingCandidates()
	local cfg = ExtinctionConfig.MovingZone
	local options = movingOptions or {}
	local map = options.Map
	local list = {}
	local places = map and map:FindFirstChild("Places")
	local radius = cfg.Radius
	local safe, safeRadius = nil, 0
	if options.SafeCenter then
		safe, safeRadius = options.SafeCenter()
	end
	local exclude = {}
	for _, key in cfg.Exclude do
		exclude[key] = true
	end
	for _, part in places and places:GetChildren() or {} do
		local key = string.match(part.Name, "^Place_(.+)$")
		if key and part:IsA("BasePart") and not exclude[key] and string.sub(key, 1, 5) ~= "Safe_" and part.Size.X <= cfg.MaxPlaceSize then
			local center = part.Position
			local ok = true
			if safe and Vector3.new(center.X - safe.X, 0, center.Z - safe.Z).Magnitude < safeRadius + radius + 40 then
				ok = false
			end
			for _, zone in options.SafeZones and options.SafeZones() or {} do -- Safehouses nicht in der Wanderzone
				if Vector3.new(center.X - zone.Center.X, 0, center.Z - zone.Center.Z).Magnitude < zone.Radius + radius + 20 then
					ok = false
				end
			end
			for _, zone in zones do
				if Vector3.new(center.X - zone.Center.X, 0, center.Z - zone.Center.Z).Magnitude < zone.Radius + radius * 0.5 then
					ok = false
				end
			end
			if ok and options.IsWater and options.IsWater(center.X, center.Z) then
				ok = false
			end
			if ok then
				table.insert(list, { Key = key, Title = part:GetAttribute("Title") or key, Center = center })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Key < b.Key
	end)
	return list
end

local function announce(title, sub, style)
	local options = movingOptions
	if not (options and options.Players) then
		return
	end
	for _, player in options.Players() do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Wanderzone", Title = title, Sub = sub, Style = style or "Warning" })
	end
end

-- Wand aus flimmernden Platten (ForceField) im Kreis, Lichtsäule in der Mitte
local function buildVisual()
	if movingFolder then
		movingFolder:Destroy()
		movingFolder = nil
	end
	local options = movingOptions
	if not (moving and options and options.Map) then
		return
	end
	local cfg = ExtinctionConfig.MovingZone
	local folder = Instance.new("Folder")
	folder.Name = "MovingZone"
	local function part(name, size, cframe, material, transparency)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe
		p.Color = cfg.Color
		p.Material = material
		p.Transparency = transparency
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = folder
		return p
	end
	local center, radius = moving.Center, moving.Radius
	local n = cfg.WallPanels
	local width = 2 * math.pi * radius / n + 1
	for k = 1, n do
		local a = 2 * math.pi * (k - 0.5) / n
		local x, z = center.X + math.cos(a) * radius, center.Z + math.sin(a) * radius
		local y = options.GroundY and options.GroundY(x, z) or center.Y
		part("Wall", Vector3.new(width, cfg.WallHeight, 1), CFrame.new(x, y + cfg.WallHeight / 2 - 6, z) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Enum.Material.ForceField, 0.15)
	end
	local y = options.GroundY and options.GroundY(center.X, center.Z) or center.Y
	local beam = part("Beam", Vector3.new(3, 400, 3), CFrame.new(center.X, y + 200, center.Z), Enum.Material.Neon, 0.55)
	local light = Instance.new("PointLight")
	light.Color = cfg.Color
	light.Range = 60
	light.Brightness = 2
	light.Parent = beam
	folder.Parent = options.Map
	movingFolder = folder
end

local function publish()
	local options = movingOptions
	if not (options and options.Map) then
		return
	end
	if moving then
		options.Map:SetAttribute("MovingZone", HttpService:JSONEncode({ Name = moving.Title, X = moving.Center.X, Z = moving.Center.Z,
			R = moving.Radius, Ends = moving.Ends }))
	else
		options.Map:SetAttribute("MovingZone", nil)
	end
end

-- callback(moving) nach jedem Wechsel der Wanderzone (moving = neue Zone oder nil, wenn es keine mehr gibt)
function RedzoneService.OnMoved(callback)
	if not table.find(movedCallbacks, callback) then
		table.insert(movedCallbacks, callback)
	end
end

local function moved()
	for _, callback in movedCallbacks do
		callback(moving)
	end
end

-- Wanderzone an einen neuen Ort setzen (key = Ort erzwingen, sonst zufällig und nicht derselbe wie vorher)
function RedzoneService.MoveNow(key)
	local cfg = ExtinctionConfig.MovingZone
	local list = RedzoneService.MovingCandidates()
	if #list == 0 then
		moving = nil
		publish()
		buildVisual()
		moved()
		return nil
	end
	local pick = nil
	for _, entry in list do
		if entry.Key == key then
			pick = entry
		end
	end
	if not pick then
		local choices = {}
		for _, entry in list do
			if not moving or entry.Key ~= moving.Key then
				table.insert(choices, entry)
			end
		end
		if #choices == 0 then
			choices = list
		end
		local random = movingOptions and movingOptions.Random or Random.new()
		pick = choices[random:NextInteger(1, #choices)]
	end
	moving = { Name = "Wanderzone", Key = pick.Key, Title = pick.Title, Center = pick.Center, Radius = cfg.Radius, Moving = true,
		Ends = now() + cfg.Interval, Warned = false }
	publish()
	buildVisual()
	moved()
	announce("WANDERZONE: " .. string.upper(pick.Title), "PvP sofort · bessere Beute · wechselt in " .. math.floor(cfg.Interval / 60)
		.. " Min", "Warning")
	return moving
end

function RedzoneService.Moving()
	return moving
end

-- Einmal pro Sekunde (oder öfter): Warnung kurz vor dem Wechsel, Wechsel bei Ablauf
function RedzoneService.StepMoving()
	if not moving then
		return
	end
	local cfg = ExtinctionConfig.MovingZone
	local left = moving.Ends - now()
	if left <= 0 then
		RedzoneService.MoveNow()
	elseif left <= cfg.Warning and not moving.Warned then
		moving.Warned = true
		announce("WANDERZONE WECHSELT", "In " .. math.ceil(left) .. " Sekunden zieht die Zone von " .. moving.Title .. " weiter", "Info")
	end
end

-- options = { Map, SafeCenter() -> (Vector3, Radius), IsWater(x, z) (Weltkoordinaten), GroundY(x, z), Players(),
--             Random, Loop (Standard true: eigener Takt) }
function RedzoneService.StartMoving(options)
	if not ExtinctionConfig.MovingZone.Enabled then
		return
	end
	movingOptions = options
	movingRun += 1
	local run = movingRun
	RedzoneService.MoveNow()
	if options.Loop ~= false then
		task.spawn(function()
			while run == movingRun do
				task.wait(1)
				if run ~= movingRun then
					break
				end
				RedzoneService.StepMoving()
			end
		end)
	end
end

function RedzoneService.StopMoving()
	movingRun += 1
	moving = nil
	publish()
	buildVisual()
	moved()
	movingOptions = nil
end

function RedzoneService.List()
	return zones
end

-- Zufällige rote Zone (random = Random), nil ohne Zonen
function RedzoneService.Random(random)
	if #zones == 0 then
		return nil
	end
	return zones[(random or Random.new()):NextInteger(1, #zones)]
end

return RedzoneService

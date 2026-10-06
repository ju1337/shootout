-- RedzoneService (ModuleScript, nur Server)
-- Die rote Zone der offenen Welt (EXTINCTION): ein gefährliches Gebiet mit besserer Beute, das alle Interval Sekunden
-- (20 Minuten, ExtinctionConfig.Redzone) an einen anderen Ort der Karte zieht. Ziele sind die Orte der Karte (Teile
-- Place_<Name> der Gruppe Places) ohne Camp, Seen, große Flächen, Safehouses und Wasser; nie zweimal derselbe hintereinander
-- und möglichst mindestens MinMove vom alten Ort weg.
-- Drinnen:
--   * PvP gilt sofort (keine Wartezeit nach der Safe Zone),
--   * mehr Zombies um jeden Spieler (PerPlayerFactor) mit Läufern und Brocken, die innerhalb der Zone spawnen,
--   * Lagerkisten in der Zone ziehen aus Tier3 (ContainerService), Lootdrops landen bevorzugt dort (AirdropService).
-- Ansage an alle draußen beim Wechsel und eine Minute vorher; in der Welt steht eine flimmernde rote Wand (ForceField) mit
-- Lichtsäule in der Mitte. Jeden Wechsel meldet OnMoved(callback): RedzoneBoard beginnt dann eine neue Runde der Rangliste.
-- Für die Clients steht die Zone als JSON im Attribut "Redzones" an der Karte: [{ Name, Title, X, Z, R, Ends }]
-- (eine Liste, damit später auch mehrere gehen; Ends = Serverzeit des nächsten Wechsels). Das Spieler-Attribut "Redzone"
-- (Name der Zone oder nil) setzt der Modus (Modes/Extinction).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Remotes = require(Shared.Remotes)

local RedzoneService = {}

local NAME = "Redzone" -- Name der Zone (Spieler-Attribut Redzone, Schlüssel der Rangliste)

local current = nil -- { Name, Key, Title, Center (Vector3), Radius, Ends, Warned }
local options = nil
local visual = nil -- Wand und Lichtsäule
local run = 0
local movedCallbacks = {} -- callback(zone) nach jedem Wechsel (z.B. RedzoneBoard)

local function now()
	return workspace:GetServerTimeNow()
end

-- Rote Zone an einer Stelle (flacher Abstand) oder nil
function RedzoneService.At(position)
	if current and Vector3.new(position.X - current.Center.X, 0, position.Z - current.Center.Z).Magnitude <= current.Radius then
		return current
	end
	return nil
end

-- Orte, an die die Zone ziehen kann: { Key, Title, Center }
function RedzoneService.Candidates()
	local cfg = ExtinctionConfig.Redzone
	local opts = options or {}
	local places = opts.Map and opts.Map:FindFirstChild("Places")
	local radius = cfg.Radius
	local safe, safeRadius = nil, 0
	if opts.SafeCenter then
		safe, safeRadius = opts.SafeCenter()
	end
	local exclude = {}
	for _, key in cfg.Exclude do
		exclude[key] = true
	end
	local list = {}
	for _, part in places and places:GetChildren() or {} do
		local key = string.match(part.Name, "^Place_(.+)$")
		if key and part:IsA("BasePart") and not exclude[key] and string.sub(key, 1, 5) ~= "Safe_" and part.Size.X <= cfg.MaxPlaceSize then
			local center = part.Position
			local ok = not (safe and Vector3.new(center.X - safe.X, 0, center.Z - safe.Z).Magnitude < safeRadius + radius + 40)
			for _, zone in opts.SafeZones and opts.SafeZones() or {} do -- Safehouses nicht in der Zone
				if Vector3.new(center.X - zone.Center.X, 0, center.Z - zone.Center.Z).Magnitude < zone.Radius + radius + 20 then
					ok = false
				end
			end
			if ok and opts.IsWater and opts.IsWater(center.X, center.Z) then
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
	if not (options and options.Players) then
		return
	end
	for _, player in options.Players() do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Rote Zone", Title = title, Sub = sub, Style = style or "Warning" })
	end
end

-- Wand aus flimmernden Platten (ForceField) im Kreis, Lichtsäule in der Mitte
local function buildVisual()
	if visual then
		visual:Destroy()
		visual = nil
	end
	if not (current and options and options.Map) then
		return
	end
	local cfg = ExtinctionConfig.Redzone
	local folder = Instance.new("Folder")
	folder.Name = "RedzoneWall"
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
	local center, radius = current.Center, current.Radius
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
	visual = folder
end

local function publish()
	if not (options and options.Map) then
		return
	end
	local list = {}
	for _, zone in RedzoneService.List() do
		table.insert(list, { Name = zone.Name, Title = zone.Title, X = zone.Center.X, Z = zone.Center.Z, R = zone.Radius, Ends = zone.Ends })
	end
	options.Map:SetAttribute("Redzones", HttpService:JSONEncode(list))
end

-- callback(zone) nach jedem Wechsel (zone = die Zone am neuen Ort oder nil, wenn es keine mehr gibt)
function RedzoneService.OnMoved(callback)
	if not table.find(movedCallbacks, callback) then
		table.insert(movedCallbacks, callback)
	end
end

local function moved()
	publish()
	buildVisual()
	for _, callback in movedCallbacks do
		callback(current)
	end
end

-- Zone an einen neuen Ort setzen (key = Ort erzwingen, sonst zufällig: nicht derselbe wie vorher und möglichst weit weg).
-- Jeder Aufruf beginnt eine neue Runde (Rangliste von vorn), auch am selben Ort.
function RedzoneService.MoveNow(key)
	local cfg = ExtinctionConfig.Redzone
	local list = RedzoneService.Candidates()
	if #list == 0 then
		current = nil
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
		local far, other = {}, {}
		for _, entry in list do
			if not current then
				table.insert(far, entry)
			elseif entry.Key ~= current.Key then
				local away = Vector3.new(entry.Center.X - current.Center.X, 0, entry.Center.Z - current.Center.Z).Magnitude
				table.insert(away >= cfg.MinMove and far or other, entry)
			end
		end
		local choices = #far > 0 and far or #other > 0 and other or list
		local random = options and options.Random or Random.new()
		pick = choices[random:NextInteger(1, #choices)]
	end
	current = { Name = NAME, Key = pick.Key, Title = pick.Title, Center = pick.Center, Radius = cfg.Radius, Ends = now() + cfg.Interval,
		Warned = false }
	moved()
	announce("ROTE ZONE: " .. string.upper(pick.Title), "Rangliste neu · PvP sofort · bessere Beute · zieht in "
		.. math.floor(cfg.Interval / 60) .. " Min weiter", "Warning")
	return current
end

-- Die rote Zone (oder nil)
function RedzoneService.Current()
	return current
end

-- Einmal pro Sekunde (oder öfter): Warnung kurz vor dem Wechsel, Wechsel bei Ablauf
function RedzoneService.Step()
	if not current then
		return
	end
	local cfg = ExtinctionConfig.Redzone
	local left = current.Ends - now()
	if left <= 0 then
		RedzoneService.MoveNow()
	elseif left <= cfg.Warning and not current.Warned then
		current.Warned = true
		announce("ROTE ZONE ZIEHT WEITER", "In " .. math.ceil(left) .. " Sekunden zieht die Zone von " .. current.Title
			.. " weiter · die Rangliste beginnt neu", "Info")
	end
end

-- opts = { Map, SafeCenter() -> (Vector3, Radius), SafeZones() -> { { Center, Radius } }, IsWater(x, z) (Weltkoordinaten),
--          GroundY(x, z), Players(), Random, Loop (Standard true: eigener Takt) }
function RedzoneService.Start(opts)
	if not ExtinctionConfig.Redzone.Enabled then
		return
	end
	options = opts
	run += 1
	local myRun = run
	RedzoneService.MoveNow()
	if opts.Loop ~= false then
		task.spawn(function()
			while myRun == run do
				task.wait(1)
				if myRun ~= run then
					break
				end
				RedzoneService.Step()
			end
		end)
	end
end

function RedzoneService.Stop()
	run += 1
	current = nil
	moved()
	options = nil
end

-- Alle roten Zonen (jetzt höchstens eine)
function RedzoneService.List()
	return current and { current } or {}
end

-- Zufällige rote Zone (random = Random), nil ohne Zone
function RedzoneService.Random(random)
	local list = RedzoneService.List()
	if #list == 0 then
		return nil
	end
	return list[(random or Random.new()):NextInteger(1, #list)]
end

return RedzoneService

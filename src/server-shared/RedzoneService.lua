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
	-- Stelle als Ziel erlaubt? (nicht an der Safe Zone, nicht an Safehouses, nicht im Wasser)
	local function allowed(center)
		local ok = not (safe and Vector3.new(center.X - safe.X, 0, center.Z - safe.Z).Magnitude < safeRadius + radius + 40)
		for _, zone in opts.SafeZones and opts.SafeZones() or {} do -- Safehouses nicht in der Zone
			if Vector3.new(center.X - zone.Center.X, 0, center.Z - zone.Center.Z).Magnitude < zone.Radius + radius + 20 then
				ok = false
			end
		end
		if ok and opts.IsWater and opts.IsWater(center.X, center.Z) then
			ok = false
		end
		return ok
	end
	for _, part in places and places:GetChildren() or {} do
		local key = string.match(part.Name, "^Place_(.+)$")
		if key and part:IsA("BasePart") and not exclude[key] and string.sub(key, 1, 5) ~= "Safe_" and part.Size.X <= cfg.MaxPlaceSize
			and allowed(part.Position) then
			table.insert(list, { Key = key, Title = part:GetAttribute("Title") or key, Center = part.Position })
		end
	end
	-- Viertel der Stadt als eigene Ziele (relativ zur Kartenmitte)
	local mapCenter = opts.Map and opts.Map:GetAttribute("Center")
	if typeof(mapCenter) == "Vector3" then
		for _, district in cfg.CityDistricts or {} do
			local center = mapCenter + Vector3.new(district.X, 0, district.Z)
			if allowed(center) then
				table.insert(list, { Key = district.Key, Title = district.Title, Center = center })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Key < b.Key
	end)
	return list
end

local function announce(title, sub, style, sound)
	if not (options and options.Players) then
		return
	end
	for _, player in options.Players() do
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Rote Zone", Title = title, Sub = sub, Style = style or "Warning",
			Sound = sound })
	end
end

-- Rand: flacher Bodendunst im Kreis (unsichtbare Bodenstreifen, wenig Rauch, bleibt unten); Mitte: Signalfackel, deren
-- roter Rauch hoch in den Himmel steigt (von weitem sichtbar, statt Lichtsäule)
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
		local wall = part("Wall", Vector3.new(width, 1, 4), CFrame.new(x, y + 1, z) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Enum.Material.SmoothPlastic, 1)
		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Shape = Enum.ParticleEmitterShape.Box
		smoke.EmissionDirection = Enum.NormalId.Top
		smoke.Color = ColorSequence.new(cfg.SmokeColor)
		smoke.LightInfluence = 0.7
		smoke.Size = NumberSequence.new(cfg.SmokeSize * 0.6, cfg.SmokeSize)
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, cfg.SmokeAlpha),
			NumberSequenceKeypoint.new(0.7, cfg.SmokeAlpha), NumberSequenceKeypoint.new(1, 1) })
		smoke.Lifetime = NumberRange.new(5, 7)
		smoke.Rate = cfg.SmokeRate
		smoke.Speed = NumberRange.new(0.5, 1.5)
		smoke.Drag = 0.5
		smoke.Rotation = NumberRange.new(0, 360)
		smoke.RotSpeed = NumberRange.new(-8, 8)
		smoke.Parent = wall
		-- leuchtende Linie am Boden: Stück von Ecke zu Ecke, folgt dem Gelände (auch an Hängen)
		local a0, a1 = 2 * math.pi * (k - 1) / n, 2 * math.pi * k / n
		local function edge(angle)
			local ex, ez = center.X + math.cos(angle) * radius, center.Z + math.sin(angle) * radius
			return Vector3.new(ex, (options.GroundY and options.GroundY(ex, ez) or center.Y) + 0.25, ez)
		end
		local p0, p1 = edge(a0), edge(a1)
		part("Line", Vector3.new(cfg.LineWidth, 0.2, (p1 - p0).Magnitude + 0.5), CFrame.lookAt((p0 + p1) / 2, p1), Enum.Material.Neon,
			cfg.LineAlpha)
		-- Warnpfosten mit rot leuchtender Kappe (jedes PostEvery-te Stück): von weitem als Ring aus Lichtern zu sehen
		if k % cfg.PostEvery == 0 then
			local post = part("Post", Vector3.new(0.5, cfg.PostHeight, 0.5), CFrame.new(x, y + cfg.PostHeight / 2, z), Enum.Material.Metal, 0)
			post.Color = Color3.fromRGB(40, 40, 42)
			part("PostLight", Vector3.new(0.9, 0.9, 0.9), CFrame.new(x, y + cfg.PostHeight + 0.45, z), Enum.Material.Neon, 0)
		end
	end
	local y = options.GroundY and options.GroundY(center.X, center.Z) or center.Y
	-- Signalfackel: glühender Stab am Boden, roter Rauch steigt schnell und weit nach oben, wird dabei breiter und blasser
	local flare = part("Flare", Vector3.new(0.6, 1.6, 0.6), CFrame.new(center.X, y + 0.8, center.Z), Enum.Material.Neon, 0)
	local light = Instance.new("PointLight")
	light.Color = cfg.Color
	light.Range = 24
	light.Brightness = 3
	light.Parent = flare
	local column = Instance.new("ParticleEmitter")
	column.Name = "FlareSmoke"
	column.Texture = "rbxasset://textures/particles/smoke_main.dds"
	column.EmissionDirection = Enum.NormalId.Top
	column.Color = ColorSequence.new(cfg.Color, cfg.SmokeColor)
	column.LightInfluence = 0.4
	column.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 26) })
	column.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.7, 0.6),
		NumberSequenceKeypoint.new(1, 1) })
	column.Lifetime = NumberRange.new(10, 13)
	column.Rate = 5
	column.Speed = NumberRange.new(22, 28)
	column.Acceleration = Vector3.new(1.5, 0, 0.8) -- leichter Wind
	column.SpreadAngle = Vector2.new(4, 4)
	column.Drag = 0.15
	column.Rotation = NumberRange.new(0, 360)
	column.RotSpeed = NumberRange.new(-15, 15)
	column.Parent = flare
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
		-- ein Fehler in einem Hörer (Belohnung, Rangliste) darf das Weiterziehen nicht für immer anhalten
		local ok, err = pcall(callback, current)
		if not ok then
			warn("RedzoneService: " .. tostring(err))
		end
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
		-- Ziele in der Stadt zählen CityWeight-fach (die Zone soll öfter in der Stadt sein)
		local mapCenter = options and options.Map and options.Map:GetAttribute("Center")
		local function weight(entry)
			if typeof(mapCenter) ~= "Vector3" or not cfg.CityRadius then
				return 1
			end
			local inCity = Vector3.new(entry.Center.X - mapCenter.X, 0, entry.Center.Z - mapCenter.Z).Magnitude <= cfg.CityRadius
			return inCity and (cfg.CityWeight or 1) or 1
		end
		local total = 0
		for _, entry in choices do
			total += weight(entry)
		end
		local roll = random:NextNumber(0, total)
		pick = choices[#choices]
		for _, entry in choices do
			roll -= weight(entry)
			if roll <= 0 then
				pick = entry
				break
			end
		end
	end
	current = { Name = NAME, Key = pick.Key, Title = pick.Title, Center = pick.Center, Radius = cfg.Radius, Ends = now() + cfg.Interval,
		Warned = false }
	moved()
	announce("ROTE ZONE: " .. string.upper(pick.Title), "Rangliste neu · PvP sofort · bessere Beute · zieht in "
		.. math.floor(cfg.Interval / 60) .. " Min weiter", "Warning", "PoliceSiren")
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
				local ok, err = pcall(RedzoneService.Step)
				if not ok then
					warn("RedzoneService.Step: " .. tostring(err))
				end
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

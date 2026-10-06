-- Minimap (ModuleScript, nur Client)
-- Runde Minimap oben links wie bei Rogue Company. Maps können weiter rauszoomen (Attribut MinimapRange) und nur
-- bestimmte Gruppen zeichnen (MinimapFolders); die offene Welt zeigt die Safe Zones und die rote Zone als Punktkreise. Sie dreht sich mit der Kamera (Blickrichtung = oben)
-- und zeigt den Grundriss der aktuellen Map (Böden, Wände, Deckung aus den Parts der Map),
-- Teamkollegen (Cyan, am Boden orange), Gegner nur kurz, wenn sie schießen oder markiert sind (rot),
-- Pings (gelb) und die Ziele (A/B) – Ziele außerhalb der Karte kleben am Rand. In der offenen Welt außerdem die eigene
-- Todestasche (rotes X, Spieler-Attribut ExtDeathBag), ebenfalls am Rand festgehalten.
-- Technik: Ein Rahmen dreht sich um die Mitte, darin verschiebt sich die "Welt" (Positionen als Scale,
-- damit nichts auf Pixel springt). Den Kreis-Zuschnitt rechnet MinimapShapes selbst aus (Stücke am Rand
-- werden gekürzt, alles draußen ausgeblendet) – CanvasGroup/ClipsDescendants schneiden gedrehte Inhalte
-- nicht zuverlässig ab. Neu gerechnet wird nur, wenn man sich bewegt; Drehen kostet nichts.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local TeamCheck = require(Shared.TeamCheck)
local MinimapShapes = require(Shared.MinimapShapes)

local player = Players.LocalPlayer
local make = UITheme.Make

local Minimap = {}

local SIZE = 200              -- Durchmesser in Design-Einheiten
local DEFAULT_RANGE = 75      -- Studs von der Mitte bis zum Rand (Maps können mit dem Attribut MinimapRange weiter rauszoomen)
local RANGE = DEFAULT_RANGE
local K = 1 / (2 * RANGE)     -- Studs -> Anteil der Kartenbreite
local STRIP = 2               -- Flächen am Kreisrand werden in so breite Streifen (Studs) zerlegt
local CELL = 160              -- Rastergröße für die Suche nach Parts in der Nähe (große Maps)
local ZONE_DOT = 9            -- Abstand der Punkte auf Zonengrenzen (Studs)
local MOVE_UPDATE = 0.3       -- ab so viel Bewegung (Studs) wird der Zuschnitt neu gerechnet
local DOT_MARGIN = 4          -- Punkte (Teamkollegen, Gegner, Pings) nur so weit innerhalb des Rands
local SHOT_TIME = 2.5         -- so lange bleibt ein schießender Gegner sichtbar
local PING_TIME = 5
local SKIP_FOLDERS = { Nature = true, Objective = true, Places = true, Redzones = true, Lakes = true, Loot = true, Zone = true }
-- (Bäume, Ziel-Parts – Ziele kommen als Rauten –, unsichtbare Bereiche der offenen Welt; Zonen kommen als Punktkreise)

local COLORS = {
	Back = UITheme.Colors.Background,
	Ground = Color3.fromRGB(34, 38, 42),
	Water = Color3.fromRGB(22, 34, 44),
	Floor = Color3.fromRGB(62, 68, 74),
	Block = Color3.fromRGB(118, 124, 130),
	Wall = Color3.fromRGB(200, 204, 208),
	Mate = UITheme.Colors.Accent,
	Downed = Color3.fromRGB(214, 150, 60),
	Enemy = UITheme.Colors.Bad,
	Ping = UITheme.Colors.Primary,
}

-- Draufsicht eines Parts: Mitte, Breite, Tiefe (Studs) und Drehung (Grad, im Uhrzeigersinn)
local function footprint(part)
	local cf, size = part.CFrame, part.Size
	if math.abs(cf.UpVector.Y) > 0.98 then
		local right = cf.RightVector
		return cf.Position, size.X, size.Z, math.deg(math.atan2(right.Z, right.X))
	end
	-- Schräg (Treppen, Rampen): achsenparallele Hülle
	local half = size / 2
	local ex = math.abs(cf.RightVector.X) * half.X + math.abs(cf.UpVector.X) * half.Y + math.abs(cf.LookVector.X) * half.Z
	local ez = math.abs(cf.RightVector.Z) * half.X + math.abs(cf.UpVector.Z) * half.Y + math.abs(cf.LookVector.Z) * half.Z
	return cf.Position, ex * 2, ez * 2, 0
end

-- Wie wird ein Part gezeichnet? Gibt Farbe und Ebene zurück (nil = gar nicht)
local function styleOf(part, folderName)
	if part.Transparency >= 0.9 or part.Name == "SpawnPoint" then
		return nil
	end
	local size = part.Size
	local thin = math.min(size.X, size.Z) <= 3.5 -- Wände sind in den Maps 1 bis 3 Studs dick
	if folderName == "Decor" then
		-- Deko nur, wenn sie wie eine Wand oder ein großer Block im Weg steht (keine Schilder, Linien, ...)
		if size.Y >= 4 and math.max(size.X, size.Z) >= 6 and thin then
			return COLORS.Wall, 4
		elseif size.Y >= 3 and size.X * size.Z >= 16 then
			return COLORS.Block, 3
		end
		return nil
	end
	if folderName == "Ground" then
		if part.Material == Enum.Material.Water or string.find(part.Name, "Water") then
			return COLORS.Water, 1
		end
		return COLORS.Ground, 1
	end
	if size.Y >= 3 and thin then
		return COLORS.Wall, 4 -- Wand
	end
	if size.Y <= 1.6 or string.find(part.Name, "Stairs") then
		return COLORS.Floor, 2 -- Boden, Dach, Treppe
	end
	return COLORS.Block, 3 -- Kiste, Container, Block
end

-- Map, auf der man gerade ist: MapId vom Server, sonst die Map mit der nächsten Mitte
local function findMap()
	local maps = workspace:FindFirstChild("Maps")
	if not maps then
		return nil
	end
	local id = player:GetAttribute("MapId")
	if id and maps:FindFirstChild(id) then
		return maps[id]
	end
	local camera = workspace.CurrentCamera
	local position = camera and camera.Focus.Position or Vector3.zero
	local best, bestDistance = nil, 900
	for _, map in maps:GetChildren() do
		local center = map:GetAttribute("Center")
		if typeof(center) == "Vector3" then
			local distance = (Vector3.new(center.X, 0, center.Z) - Vector3.new(position.X, 0, position.Z)).Magnitude
			if distance < bestDistance then
				best, bestDistance = map, distance
			end
		end
	end
	return best
end

-- Mittelpunkt der Karte: eigener Charakter bzw. der, dem man gerade zuschaut
local function focusPosition(camera)
	local subject = camera.CameraSubject
	if subject and subject:IsA("Humanoid") and subject.RootPart then
		return subject.RootPart.Position
	elseif subject and subject:IsA("BasePart") then
		return subject.Position
	end
	return camera.Focus.Position
end

-- Liegt ein Punkt (Teamkollege, Gegner, Ping) sicher innerhalb des Kreises um focus?
local function withinRange(position, focus)
	local dx, dz = position.X - focus.X, position.Z - focus.Z
	return dx * dx + dz * dz <= (RANGE - DOT_MARGIN) * (RANGE - DOT_MARGIN)
end

-- Raute mit Buchstabe (Ziele); Kinder einer gedrehten Raute drehen mit, darum Text als Geschwister
local function objectiveIcon(parent, letter, size)
	local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size + 6, size + 6),
		BackgroundTransparency = 1, ZIndex = 7 }, parent)
	local diamond = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.72, size * 0.72), Rotation = 45, BackgroundColor3 = COLORS.Back,
		BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 7 }, holder)
	local stroke = UITheme.Stroke(diamond, Color3.new(1, 1, 1), 1.5)
	local text = UITheme.Label({ Size = UDim2.fromScale(1, 1), Text = letter, TextSize = math.floor(size * 0.5),
		Font = UITheme.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 }, holder)
	return { Holder = holder, Diamond = diamond, Stroke = stroke, Text = text }
end

-- root = skalierte HUD-Ebene. Gibt den Rahmen der Minimap zurück (für das Touch-Layout).
function Minimap.Init(root)
	local holder = make("Frame", { Name = "Minimap", Position = UDim2.fromOffset(24, 66), Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundTransparency = 1, Visible = false }, root)
	-- Ebenen (eindeutig, egal ob ZIndex global oder je Geschwister gilt): Hintergrund 0, Grundriss 1-4,
	-- Punkte 5, Rand 6, Ziele 7-8, Pfeil und Norden 9
	local back = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = COLORS.Back,
		BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 0 }, holder)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, back)
	local rotator = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 }, holder)
	local world = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 }, rotator)
	local layer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1 }, world) -- Grundriss
	local dots = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, world)

	-- Rand, Blickrichtung (Pfeil in der Mitte), Norden am Rand
	local ring = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6 }, holder)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
	local ringStroke = UITheme.Stroke(ring, Color3.fromRGB(150, 156, 164), 1.5, 0.45) -- dünner heller Rand (rot in der roten Zone)
	local overlay = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7 }, holder)
	UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20),
		Text = "▲", TextSize = 15, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, overlay)
	local north = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), Text = "N",
		TextSize = 12, Font = UITheme.Fonts.Display, TextColor3 = UITheme.Colors.Primary, TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, overlay)

	-- ---------- Grundriss ----------
	-- Pro Part ein Rechteck (MinimapShapes) mit eigenen Frames: eins, wenn es ganz im Kreis liegt,
	-- mehrere Streifen, wenn es über den Rand ragt, keins, wenn es draußen ist.
	-- { Rect, Color, Z, Frames = { Frame }, Shown = { {X, Z, W, D} }, Count = sichtbare Frames, RoundFrame }
	local shapes = {}
	local pieces = {}        -- wiederverwendete Stücke aus MinimapShapes.Clip
	local shownMap = nil
	local clippedAt = nil    -- Mittelpunkt (Vector3) beim letzten Zuschnitt

	-- Zonen der offenen Welt als Punktkreise; { Frame, X, Z }: Safe Zones (grün, fest) und die rote Zone (zieht alle
	-- 20 Minuten weiter, Karten-Attribut Redzones, wird bei jedem Wechsel neu gesetzt)
	local zoneDots = {}
	local redDots, redRaw, redzones = {}, nil, {} -- Punkte, zuletzt gelesenes Attribut, Zonen { X, Z, R }
	local buckets, bigShapes = {}, {} -- Raster [cx][cz] = { shape } und Formen, die größer als eine Zelle sind
	local activeShapes = {}           -- [shape] = true: Formen, die gerade Frames zeigen

	local function zoneCircle(x, z, radius, color, list)
		local n = math.max(12, math.floor(2 * math.pi * radius / ZONE_DOT))
		for k = 1, n do
			local a = 2 * math.pi * k / n
			local px, pz = x + math.cos(a) * radius, z + math.sin(a) * radius
			local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(px * K, pz * K),
				Size = UDim2.fromOffset(4, 4), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 4, Visible = false }, layer)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
			table.insert(list or zoneDots, { Frame = frame, X = px, Z = pz })
		end
	end

	-- Rote Zone (Karten-Attribut Redzones, JSON [{ X, Z, R, ... }]): Punktkreis in Rot, neu bei jedem Wechsel.
	-- Gibt true zurück, wenn sich etwas geändert hat.
	local function loadRedzones(map)
		local text = map and map:GetAttribute("Redzones")
		local raw = type(text) == "string" and text or nil
		if raw == redRaw then
			return false
		end
		redRaw = raw
		for _, dotInfo in redDots do
			dotInfo.Frame:Destroy()
		end
		redDots, redzones = {}, {}
		local ok, list = pcall(function()
			return raw and game:GetService("HttpService"):JSONDecode(raw) or nil
		end)
		for _, info in ok and type(list) == "table" and list or {} do
			if type(info) == "table" and tonumber(info.X) and tonumber(info.Z) and tonumber(info.R) then
				zoneCircle(info.X, info.Z, info.R, Color3.fromRGB(226, 56, 48), redDots)
				table.insert(redzones, { X = info.X, Z = info.Z, R = info.R })
			end
		end
		return true
	end

	local function loadMap(map)
		if map == shownMap then
			return
		end
		shownMap = map
		clippedAt = nil
		layer:ClearAllChildren()
		shapes, buckets, bigShapes, activeShapes, zoneDots = {}, {}, {}, {}, {}
		redDots, redRaw, redzones = {}, nil, {}
		RANGE = map and tonumber(map:GetAttribute("MinimapRange")) or DEFAULT_RANGE
		K = 1 / (2 * RANGE)
		STRIP = 2 * RANGE / DEFAULT_RANGE
		if not map then
			return
		end
		-- MinimapFolders (z. B. "Roads,Ground,Buildings"): nur diese Gruppen zeichnen (große Maps mit viel Schutt)
		local only = nil
		local list = map:GetAttribute("MinimapFolders")
		if type(list) == "string" then
			only = {}
			for name in string.gmatch(list, "[^,%s]+") do
				only[name] = true
			end
		end
		for _, folder in map:GetChildren() do
			if not SKIP_FOLDERS[folder.Name] and string.sub(folder.Name, 1, 6) ~= "Spawns" and (not only or only[folder.Name]) then
				for _, part in folder:GetDescendants() do
					if part:IsA("BasePart") then
						local color, z = styleOf(part, folder.Name)
						if color then
							local center, width, depth, angle = footprint(part)
							if z == 4 then
								width, depth = math.max(width, 1.2), math.max(depth, 1.2) -- Wände mindestens 1 Pixel
							end
							local shape = { Rect = MinimapShapes.Rect(center.X, center.Z, width, depth, angle),
								Color = color, Z = z, Frames = {}, Shown = {}, Count = 0 }
							table.insert(shapes, shape)
							if math.max(width, depth) > CELL then
								table.insert(bigShapes, shape)
							else
								local cx, cz = math.floor(center.X / CELL), math.floor(center.Z / CELL)
								buckets[cx] = buckets[cx] or {}
								buckets[cx][cz] = buckets[cx][cz] or {}
								table.insert(buckets[cx][cz], shape)
							end
						end
					end
				end
			end
		end
		-- Safe Zones (Teil Zone.SafeZone und Safehouses); die rote Zone kommt aus loadRedzones
		local zone = map:FindFirstChild("Zone")
		for _, safe in zone and zone:GetChildren() or {} do -- Camp ("SafeZone") und Safehouses ("SafeZone_<Name>")
			if safe:IsA("BasePart") and (safe.Name == "SafeZone" or string.sub(safe.Name, 1, 9) == "SafeZone_") then
				zoneCircle(safe.Position.X, safe.Position.Z, safe.Size.X / 2, Color3.fromRGB(112, 200, 120))
			end
		end
	end

	local function clipShape(shape, px, pz)
		local count = MinimapShapes.Clip(shape.Rect, px, pz, RANGE, STRIP, pieces)
		-- Fläche deckt den ganzen Kreis ab (z.B. Boden unter dem Spieler): ein runder Frame genügt
		if count == 1 and pieces[1].Round then
			local round = shape.RoundFrame
			if not round then
				round = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = shape.Color, BorderSizePixel = 0, ZIndex = shape.Z }, layer)
				make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, round)
				shape.RoundFrame = round
			end
			round.Position = UDim2.fromScale(px * K, pz * K)
			round.Size = UDim2.fromScale(1, 1)
			round.Visible = true
			count = 0
			activeShapes[shape] = true
		elseif shape.RoundFrame then
			shape.RoundFrame.Visible = false
		end
		for i = 1, count do
			local piece = pieces[i]
			local frame = shape.Frames[i]
			if not frame then
				frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Rotation = shape.Rect.Angle,
					BackgroundColor3 = shape.Color, BorderSizePixel = 0, ZIndex = shape.Z }, layer)
				shape.Frames[i] = frame
				shape.Shown[i] = {}
			end
			local shown = shape.Shown[i]
			if shown.X ~= piece.X or shown.Z ~= piece.Z then
				shown.X, shown.Z = piece.X, piece.Z
				frame.Position = UDim2.fromScale(piece.X * K, piece.Z * K)
			end
			if shown.W ~= piece.W or shown.D ~= piece.D then
				shown.W, shown.D = piece.W, piece.D
				frame.Size = UDim2.fromScale(piece.W * K, piece.D * K)
			end
			if i > shape.Count then
				frame.Visible = true
			end
		end
		for i = count + 1, shape.Count do
			shape.Frames[i].Visible = false
		end
		shape.Count = count
		if count > 0 then
			activeShapes[shape] = true
		end
	end

	-- Alle Rechtecke in der Nähe auf den Kreis um (px, pz) zuschneiden; was vorher sichtbar war und jetzt weit weg ist,
	-- wird ausgeblendet. Große Maps durchsuchen nur die Rasterzellen um den Spieler.
	local function clipMap(px, pz)
		local seen = {}
		local reach = math.ceil((RANGE + CELL / 2) / CELL)
		local cx0, cz0 = math.floor(px / CELL), math.floor(pz / CELL)
		for cx = cx0 - reach, cx0 + reach do
			local column = buckets[cx]
			if column then
				for cz = cz0 - reach, cz0 + reach do
					for _, shape in column[cz] or {} do
						seen[shape] = true
						clipShape(shape, px, pz)
					end
				end
			end
		end
		for _, shape in bigShapes do
			seen[shape] = true
			clipShape(shape, px, pz)
		end
		for shape in activeShapes do
			if not seen[shape] then
				for i = 1, shape.Count do
					shape.Frames[i].Visible = false
				end
				shape.Count = 0
				if shape.RoundFrame then
					shape.RoundFrame.Visible = false
				end
				activeShapes[shape] = nil
			elseif shape.Count == 0 and not (shape.RoundFrame and shape.RoundFrame.Visible) then
				activeShapes[shape] = nil
			end
		end
		local limit = (RANGE - 3) * (RANGE - 3)
		for _, list in { zoneDots, redDots } do
			for _, dotInfo in list do
				local dx, dz = dotInfo.X - px, dotInfo.Z - pz
				dotInfo.Frame.Visible = dx * dx + dz * dz <= limit
			end
		end
		-- in der roten Zone: Rand der Minimap rot
		local inside = false
		for _, zone in redzones do
			if (px - zone.X) ^ 2 + (pz - zone.Z) ^ 2 <= zone.R * zone.R then
				inside = true
			end
		end
		ringStroke.Color = inside and Color3.fromRGB(226, 56, 48) or Color3.fromRGB(150, 156, 164)
		ringStroke.Transparency = inside and 0 or 0.45
		ringStroke.Thickness = inside and 2.5 or 1.5
	end

	-- ---------- Punkte: Teamkollegen, Gegner, Pings ----------
	local function dot(color, size)
		local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 5 }, dots)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
		UITheme.Stroke(frame, COLORS.Back, 1.5, 0.2)
		return frame
	end
	local mateDots = {}      -- [Name] = Frame
	local enemySeen = {}     -- [Modell] = { Until, Position }
	local revealed = {}      -- [Modell] = bis wann (Radar-Fähigkeit)
	local pings = {}         -- { Frame, Until, Position }

	-- Schießende Gegner kurz zeigen (wie bei RC)
	Remotes.Shot.OnClientEvent:Connect(function(shooter, startPos)
		if typeof(startPos) ~= "Vector3" then
			return
		end
		local model = nil
		if typeof(shooter) == "Instance" then
			model = shooter:IsA("Player") and shooter.Character or (shooter:IsA("Model") and shooter or nil)
		end
		if model and TeamCheck.IsEnemy(model) then
			enemySeen[model] = { Until = os.clock() + SHOT_TIME, Position = startPos }
		end
	end)
	Remotes.Reveal.OnClientEvent:Connect(function(characters, duration)
		for _, model in characters do
			if typeof(model) == "Instance" then
				revealed[model] = os.clock() + (tonumber(duration) or 3)
			end
		end
	end)
	Remotes.PingShow.OnClientEvent:Connect(function(position)
		if typeof(position) == "Vector3" then
			local frame = dot(COLORS.Ping, 9)
			frame.Rotation = 45
			table.insert(pings, { Frame = frame, Until = os.clock() + PING_TIME, Position = position })
		end
	end)
	local enemyDots = {}     -- [Modell] = Frame

	-- ---------- Ziele (Overlay, am Rand festgehalten) ----------
	local objectiveIcons = {} -- { Icon, Part }
	local shownObjectives = nil
	local function buildObjectives(map, modeInfo)
		local key = tostring(map) .. tostring(modeInfo and modeInfo.Id)
		if key == shownObjectives then
			return
		end
		shownObjectives = key
		for _, entry in objectiveIcons do
			entry.Icon.Holder:Destroy()
		end
		objectiveIcons = {}
		local folder = map and map:FindFirstChild("Objective")
		if not folder or not modeInfo or not modeInfo.Objectives then
			return
		end
		for _, objective in modeInfo.Objectives do
			local part = folder:FindFirstChild(objective.Part)
			if part and part:IsA("BasePart") then
				table.insert(objectiveIcons, { Icon = objectiveIcon(overlay, objective.Label, 26), Part = part })
			end
		end
	end

	local function rotate(dx, dz, degrees)
		local c, s = math.cos(math.rad(degrees)), math.sin(math.rad(degrees))
		return dx * c - dz * s, dx * s + dz * c
	end

	-- Eigene Todestasche (offene Welt): rotes X, außerhalb der Karte am Rand
	local bagIcon = objectiveIcon(overlay, "X", 22)
	bagIcon.Holder.Name = "DeathBag"
	bagIcon.Holder.Visible = false
	bagIcon.Diamond.BackgroundColor3 = COLORS.Enemy
	local bagRaw, bagAt = nil, nil -- zuletzt gelesenes Attribut, Position (Vector3) oder nil
	local function updateBag(focus, rotation)
		local raw = player:GetAttribute("ExtDeathBag")
		if raw ~= bagRaw then
			bagRaw = raw
			bagAt = nil
			local ok, info = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "")
			if ok and type(info) == "table" and tonumber(info.X) and tonumber(info.Z) then
				bagAt = Vector3.new(tonumber(info.X), 0, tonumber(info.Z))
			end
		end
		bagIcon.Holder.Visible = bagAt ~= nil
		if bagAt then
			local radius = SIZE / 2 - 14
			local x, y = rotate((bagAt.X - focus.X) / RANGE * (SIZE / 2), (bagAt.Z - focus.Z) / RANGE * (SIZE / 2), rotation)
			local distance = math.sqrt(x * x + y * y)
			if distance > radius then
				x, y = x / distance * radius, y / distance * radius
			end
			bagIcon.Holder.Position = UDim2.new(0.5, x, 0.5, y)
		end
	end

	local refreshAt = 0
	local fighters, fightersAt = {}, 0
	RunService.RenderStepped:Connect(function()
		local visible = root.Parent ~= nil and (root.Parent :: ScreenGui).Enabled and Modes.IsFighting(player)
		holder.Visible = visible
		if not visible then
			return
		end
		local now = os.clock()
		local camera = workspace.CurrentCamera
		local look = camera.CFrame.LookVector
		local rotation = -math.deg(math.atan2(look.X, -look.Z))
		local focus = focusPosition(camera)

		-- Map und Ziele nur gelegentlich prüfen
		if now >= refreshAt then
			refreshAt = now + 1
			local map = findMap()
			loadMap(map)
			if loadRedzones(map) then
				clippedAt = nil -- Punkte der roten Zone am neuen Ort gleich zeigen
			end
			buildObjectives(map, Modes.Get(player:GetAttribute("Mode")))
		end
		-- Zuschnitt auf den Kreis nur nach Bewegung neu rechnen
		if not clippedAt or Vector2.new(focus.X - clippedAt.X, focus.Z - clippedAt.Z).Magnitude > MOVE_UPDATE then
			clippedAt = focus
			clipMap(focus.X, focus.Z)
		end

		rotator.Rotation = rotation
		world.Position = UDim2.fromScale(0.5 - focus.X * K, 0.5 - focus.Z * K)
		local nx, nz = rotate(0, -1, rotation)
		north.Position = UDim2.new(0.5, nx * (SIZE / 2 - 10), 0.5, nz * (SIZE / 2 - 10))

		-- Teamkollegen (Liste 5x pro Sekunde, Positionen jedes Bild)
		if now >= fightersAt then
			fightersAt = now + 0.2
			fighters = TeamCheck.Fighters()
		end
		local seen = {}
		for _, fighter in fighters do
			if fighter.IsMate and not fighter.IsSelf and fighter.Model then
				local rootPart = fighter.Model:FindFirstChild("HumanoidRootPart")
				local state = TeamCheck.StateOf(fighter.Model)
				if rootPart and state ~= "dead" then
					seen[fighter.Name] = true
					local frame = mateDots[fighter.Name] or dot(COLORS.Mate, 10)
					mateDots[fighter.Name] = frame
					frame.BackgroundColor3 = state == "downed" and COLORS.Downed or COLORS.Mate
					frame.Position = UDim2.fromScale(rootPart.Position.X * K, rootPart.Position.Z * K)
					frame.Visible = withinRange(rootPart.Position, focus)
				end
			end
		end
		for name, frame in mateDots do
			if not seen[name] then
				frame:Destroy()
				mateDots[name] = nil
			end
		end

		-- Gegner: nach Schüssen kurz an der Schuss-Stelle, markierte live
		local shownEnemies = {}
		for model, info in enemySeen do
			if now > info.Until or not model.Parent then
				enemySeen[model] = nil
			else
				shownEnemies[model] = info.Position
			end
		end
		for model, untilTime in revealed do
			local rootPart = model.Parent and model:FindFirstChild("HumanoidRootPart")
			if now > untilTime or not rootPart then
				revealed[model] = nil
			else
				shownEnemies[model] = (rootPart :: BasePart).Position
			end
		end
		for model, position in shownEnemies do
			local frame = enemyDots[model] or dot(COLORS.Enemy, 9)
			enemyDots[model] = frame
			frame.Position = UDim2.fromScale(position.X * K, position.Z * K)
			frame.Visible = withinRange(position, focus)
		end
		for model, frame in enemyDots do
			if not shownEnemies[model] then
				frame:Destroy()
				enemyDots[model] = nil
			end
		end

		updateBag(focus, rotation)

		-- Pings
		for i = #pings, 1, -1 do
			local entry = pings[i]
			if now > entry.Until then
				entry.Frame:Destroy()
				table.remove(pings, i)
			else
				entry.Frame.Position = UDim2.fromScale(entry.Position.X * K, entry.Position.Z * K)
				entry.Frame.Visible = withinRange(entry.Position, focus)
			end
		end

		-- Ziele: innerhalb der Karte an ihrer Stelle, sonst am Rand. Farbe wie die Marker in der Welt:
		-- gehört dem eigenen Team = Cyan, dem Gegner = rot, Bombe gelegt = rot, umkämpft = Rand blinkt
		local radius = SIZE / 2 - 14
		local myTeam = player.Team and player.Team.Name
		local mine, theirs = player:GetAttribute("ObjMine") or 0, player:GetAttribute("ObjEnemy") or 0
		local flash = math.floor(now * 4) % 2 == 0
		for _, entry in objectiveIcons do
			local part = entry.Part :: BasePart
			local offset = part.Position - focus
			local x, y = rotate(offset.X / RANGE * (SIZE / 2), offset.Z / RANGE * (SIZE / 2), rotation)
			local distance = math.sqrt(x * x + y * y)
			if distance > radius then
				x, y = x / distance * radius, y / distance * radius
			end
			entry.Icon.Holder.Position = UDim2.new(0.5, x, 0.5, y)
			local fill, stroke = COLORS.Back, Color3.new(1, 1, 1)
			local owner = part:GetAttribute("FlagOwner")
			if part:GetAttribute("Planted") then
				fill, stroke = COLORS.Enemy, COLORS.Enemy
			elseif owner then
				fill = owner == myTeam and COLORS.Mate or COLORS.Enemy
			elseif part.Name == "CapturePoint" and (mine >= 1 or theirs >= 1) then
				fill = mine >= 1 and COLORS.Mate or COLORS.Enemy
			end
			if part:GetAttribute("Contested") and flash then
				stroke = COLORS.Downed
			end
			entry.Icon.Diamond.BackgroundColor3 = fill
			entry.Icon.Stroke.Color = stroke
		end
	end)

	return holder
end

return Minimap

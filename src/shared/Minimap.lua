-- Minimap (ModuleScript, nur Client)
-- Runde Minimap oben links wie bei Rogue Company. Sie dreht sich mit der Kamera (Blickrichtung = oben)
-- und zeigt den Grundriss der aktuellen Map (Böden, Wände, Deckung aus den Parts der Map),
-- Teamkollegen (Cyan, am Boden orange), Gegner nur kurz, wenn sie schießen oder markiert sind (rot),
-- Pings (gelb) und die Ziele (A/B) – Ziele außerhalb der Karte kleben am Rand.
-- Technik: CanvasGroup mit runder Ecke schneidet kreisförmig ab; darin dreht sich ein Rahmen um die
-- Mitte, darin verschiebt sich die "Welt" (Positionen als Scale, damit nichts auf Pixel springt).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local TeamCheck = require(Shared.TeamCheck)

local player = Players.LocalPlayer
local make = UITheme.Make

local Minimap = {}

local SIZE = 200              -- Durchmesser in Design-Einheiten
local RANGE = 75              -- Studs von der Mitte bis zum Rand
local K = 1 / (2 * RANGE)     -- Studs -> Anteil der Kartenbreite
local SHOT_TIME = 2.5         -- so lange bleibt ein schießender Gegner sichtbar
local PING_TIME = 5
local SKIP_FOLDERS = { Nature = true, Objective = true } -- Bäume, Ziel-Parts (Ziele kommen als Rauten)

local COLORS = {
	Back = Color3.fromRGB(8, 14, 24),
	Ground = Color3.fromRGB(30, 44, 62),
	Water = Color3.fromRGB(14, 30, 52),
	Floor = Color3.fromRGB(56, 74, 96),
	Block = Color3.fromRGB(112, 132, 156),
	Wall = Color3.fromRGB(196, 214, 232),
	Mate = UITheme.Colors.Accent,
	Downed = Color3.fromRGB(255, 170, 40),
	Enemy = UITheme.Colors.Bad,
	Ping = Color3.fromRGB(255, 205, 60),
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

-- Raute mit Buchstabe (Ziele); Kinder einer gedrehten Raute drehen mit, darum Text als Geschwister
local function objectiveIcon(parent, letter, size)
	local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size + 6, size + 6),
		BackgroundTransparency = 1, ZIndex = 6 }, parent)
	local diamond = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.72, size * 0.72), Rotation = 45, BackgroundColor3 = COLORS.Back,
		BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 6 }, holder)
	local stroke = UITheme.Stroke(diamond, Color3.new(1, 1, 1), 1.5)
	local text = UITheme.Label({ Size = UDim2.fromScale(1, 1), Text = letter, TextSize = math.floor(size * 0.5),
		Font = UITheme.Fonts.Title, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 }, holder)
	return { Holder = holder, Diamond = diamond, Stroke = stroke, Text = text }
end

-- root = skalierte HUD-Ebene. Gibt den Rahmen der Minimap zurück (für das Touch-Layout).
function Minimap.Init(root)
	local holder = make("Frame", { Name = "Minimap", Position = UDim2.fromOffset(24, 66), Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundTransparency = 1, Visible = false }, root)
	local canvas = make("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = COLORS.Back,
		BackgroundTransparency = 0.2, BorderSizePixel = 0 }, holder)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, canvas)
	local rotator = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, canvas)
	local world = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, rotator)
	local layer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, world) -- Grundriss
	local dots = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, world)

	-- Rand, Blickrichtung (Pfeil in der Mitte), Norden am Rand
	local ring = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, holder)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
	UITheme.Stroke(ring, Color3.fromRGB(200, 225, 240), 2, 0.35)
	local overlay = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6 }, holder)
	UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20),
		Text = "▲", TextSize = 15, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 }, overlay)
	local north = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), Text = "N",
		TextSize = 13, Font = UITheme.Fonts.Title, TextColor3 = UITheme.Colors.Accent, TextStrokeTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 }, overlay)

	-- ---------- Grundriss ----------
	local shownMap = nil
	local function drawMap(map)
		if map == shownMap then
			return
		end
		shownMap = map
		layer:ClearAllChildren()
		if not map then
			return
		end
		for _, folder in map:GetChildren() do
			if not SKIP_FOLDERS[folder.Name] and string.sub(folder.Name, 1, 6) ~= "Spawns" then
				for _, part in folder:GetDescendants() do
					if part:IsA("BasePart") then
						local color, z = styleOf(part, folder.Name)
						if color then
							local center, width, depth, angle = footprint(part)
							if z == 4 then
								width, depth = math.max(width, 1.2), math.max(depth, 1.2) -- Wände mindestens 1 Pixel
							end
							make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(center.X * K, center.Z * K),
								Size = UDim2.fromScale(width * K, depth * K), Rotation = angle, BackgroundColor3 = color,
								BorderSizePixel = 0, ZIndex = z }, layer)
						end
					end
				end
			end
		end
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
			drawMap(map)
			buildObjectives(map, Modes.Get(player:GetAttribute("Mode")))
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
		end
		for model, frame in enemyDots do
			if not shownEnemies[model] then
				frame:Destroy()
				enemyDots[model] = nil
			end
		end

		-- Pings
		for i = #pings, 1, -1 do
			local entry = pings[i]
			if now > entry.Until then
				entry.Frame:Destroy()
				table.remove(pings, i)
			else
				entry.Frame.Position = UDim2.fromScale(entry.Position.X * K, entry.Position.Z * K)
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

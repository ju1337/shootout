-- ExtinctionMap (ModuleScript, nur Client)
-- Weltkarte der offenen Welt (EXTINCTION), Taste N (oder Knopf KARTE): Straßen und Flächen aus den Gruppen Roads und
-- Ground der Karte, die Safe Zones (grün), die rote Zone (roter Kreis mit der Zeit bis zum Weiterziehen), Orte (Namen),
-- Lootdrops (orange, mit Countdown), der Konvoi (roter Punkt mit Zustand), Vorratslager und Funkgerät, die eigene Todestasche (rotes X mit der Zeit, bis sie
-- verschwindet, Spieler-Attribut ExtDeathBag) und der eigene Standort als Pfeil in Blickrichtung.
-- Norden (+Z) ist oben. Zoomen (1x bis MAX_ZOOM): Mausrad (zum Mauszeiger hin), + und −, Controller L2/R2, Handy mit zwei
-- Fingern; verschieben: ziehen (Maus/Finger) oder rechter Stick; MITTE springt zum eigenen Standort. Planquadrate A-H / 1-8
-- zum Absprechen im Squad, Legende rechts.
-- Zombienester und Überlebende stehen nicht auf der Karte (man findet sie draußen), damit sie übersichtlich bleibt.
-- Daten: Karte workspace.Maps.Extinction (Attribute Center, Redzones, Airdrops, Convoys, Activities; Gruppen Roads, Ground, Places,
-- Zone).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.UITheme)
local ExtinctionConfig = require(Shared.ExtinctionConfig)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label

local ExtinctionMap = {}

local SIZE = 800                    -- Kantenlänge der Karte (Design-Einheiten)
local MAX_ZOOM = 5
local GRID = 8                      -- Planquadrate je Seite (A-H, 1-8)
local WORLD = ExtinctionConfig.WorldSize
local RED = Color3.fromRGB(226, 56, 48)
local SAFE = Color3.fromRGB(112, 200, 120)
local DROP = Color3.fromRGB(255, 170, 60)
local CONVOY = Color3.fromRGB(236, 96, 64)
local HORDE = Color3.fromRGB(200, 90, 220)
local HELI = Color3.fromRGB(255, 120, 40)
local BOSS = Color3.fromRGB(190, 30, 30)
local CONVOY_STATES = { Waiting = "KONVOI WARTET", Driving = "KONVOI", Halted = "KONVOI GESTOPPT", Loot = "KONVOI-LADUNG" }
local GROUND_COLORS = {             -- Flächen der Gruppe Ground nach Name (alles andere wird nicht gezeichnet)
	Sidewalk = Color3.fromRGB(84, 86, 88),
	CampPad = Color3.fromRGB(104, 104, 100),
	Field = Color3.fromRGB(96, 80, 56),
}
local BUILDING_PARTS = { Roof = true, FallenRoof = true, Upper = true, Tower = true, TowerStub = true, PrisonWall = true }

local gui, board, world, layer, markers, arrow, bagView, bagCaption, zoomText
local view = { Zoom = 1, U = 0.5, V = 0.5 } -- Zoom und Kartenmitte (Anteil 0..1)
local smallNames = {} -- Namen kleiner Orte: erst ab Zoom 1.8
local stick = Vector2.zero -- rechter Stick (Controller): verschieben
local built = false
local dropViews = {}       -- Lootdrops und Aktivitäten (Id -> Frame)
local redViews, redRaw = {}, nil -- rote Zone: { Frame, Text, Ends } und zuletzt gelesenes Attribut Redzones
local ACTIVITY_COLORS = { -- nur diese Aktivitäten stehen auf der Karte
	Cache = Color3.fromRGB(255, 210, 90),
	Radio = Color3.fromRGB(110, 190, 255),
}

local function getMap()
	local maps = workspace:FindFirstChild("Maps")
	return maps and maps:FindFirstChild("Extinction")
end

local function center(map)
	local value = map and map:GetAttribute("Center")
	return typeof(value) == "Vector3" and value or Vector3.new(0, 0, -6000)
end

-- Weltposition -> Anteil der Karte (0..1), Norden oben
local function toMap(map, x, z)
	local c = center(map)
	return (x - c.X) / WORLD + 0.5, 0.5 - (z - c.Z) / WORLD
end

local function decode(map, attribute)
	local text = map and map:GetAttribute(attribute)
	if type(text) ~= "string" then
		return {}
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, text)
	return ok and type(list) == "table" and list or {}
end

local function rect(parent, map, part, color, z)
	local u, v = toMap(map, part.Position.X, part.Position.Z)
	local right = part.CFrame.RightVector -- Straßen liegen schräg: Drehung um die Hochachse übernehmen
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(u, v),
		Size = UDim2.fromScale(part.Size.X / WORLD, part.Size.Z / WORLD), BackgroundColor3 = color, BorderSizePixel = 0,
		Rotation = math.deg(math.atan2(-right.Z, right.X)), ZIndex = z }, parent)
	return frame
end

local function circle(parent, map, x, z, radius, color, transparency, z_)
	local u, v = toMap(map, x, z)
	local frame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(u, v),
		Size = UDim2.fromScale(2 * radius / WORLD, 2 * radius / WORLD), BackgroundColor3 = color,
		BackgroundTransparency = transparency, BorderSizePixel = 0, ZIndex = z_ }, parent)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
	UITheme.Stroke(frame, color, 2, 0)
	return frame
end

-- Grundriss einmal aus der Karte bauen
local function build(map)
	layer:ClearAllChildren()
	smallNames = {}
	-- Planquadrate: feine Linien, Buchstaben oben, Zahlen links (wandern beim Zoomen mit)
	for i = 1, GRID - 1 do
		make("Frame", { Name = "GridV", Position = UDim2.fromScale(i / GRID, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.88, BorderSizePixel = 0, ZIndex = 3 }, layer)
		make("Frame", { Name = "GridH", Position = UDim2.fromScale(0, i / GRID), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.88, BorderSizePixel = 0, ZIndex = 3 }, layer)
	end
	for i = 1, GRID do
		label({ Name = "GridCol", Position = UDim2.new((i - 0.5) / GRID, -8, 0, 4), Size = UDim2.fromOffset(16, 14),
			Text = string.char(64 + i), TextSize = 12, Font = F.Display, TextColor3 = Color3.fromRGB(200, 200, 196),
			TextTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, layer)
		label({ Name = "GridRow", Position = UDim2.new(0, 4, (i - 0.5) / GRID, -7), Size = UDim2.fromOffset(16, 14),
			Text = tostring(i), TextSize = 12, Font = F.Display, TextColor3 = Color3.fromRGB(200, 200, 196), TextTransparency = 0.3,
			ZIndex = 3 }, layer)
	end
	local ground = map:FindFirstChild("Ground")
	for _, part in ground and ground:GetChildren() or {} do
		local color = part:IsA("BasePart") and GROUND_COLORS[part.Name]
		if color then
			rect(layer, map, part, color, 2)
		end
	end
	local lakes = map:FindFirstChild("Lakes")
	for _, part in lakes and lakes:GetChildren() or {} do
		if part:IsA("BasePart") then
			local frame = circle(layer, map, part.Position.X, part.Position.Z, part.Size.X / 2, Color3.fromRGB(46, 84, 110), 0, 2)
			frame.Name = "Lake"
		end
	end
	local buildings = map:FindFirstChild("Buildings")
	for _, part in buildings and buildings:GetChildren() or {} do
		if part:IsA("BasePart") and BUILDING_PARTS[part.Name] then
			rect(layer, map, part, Color3.fromRGB(92, 88, 82), 2)
		end
	end
	local roads = map:FindFirstChild("Roads")
	for _, part in roads and roads:GetChildren() or {} do
		if part:IsA("BasePart") and part.Name == "Road" then
			rect(layer, map, part, Color3.fromRGB(128, 130, 134), 3)
		end
	end
	local zone = map:FindFirstChild("Zone")
	for _, safe in zone and zone:GetChildren() or {} do -- Camp und Safehouses (kleine Safe Zones draußen)
		if safe:IsA("BasePart") and (safe.Name == "SafeZone" or string.sub(safe.Name, 1, 9) == "SafeZone_") then
			-- kleine Kreise mindestens gut sichtbar
			local frame = circle(layer, map, safe.Position.X, safe.Position.Z, math.max(safe.Size.X / 2, 45), SAFE, 0.55, 4)
			frame.Name = safe.Name
			local u, v = toMap(map, safe.Position.X, safe.Position.Z)
			local name = label({ Name = "SafeName", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(u, 0, v, 14),
				Size = UDim2.fromOffset(200, 14), Text = UITheme.Upper(safe:GetAttribute("Title") or (safe.Name == "SafeZone" and "CAMP" or "SAFEHOUSE")),
				TextSize = 11, Font = F.Display, TextColor3 = SAFE, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 }, layer)
			UITheme.Outline(name)
		end
	end
	-- Ortsnamen (große Orte heller, kleine Orte dunkler, damit die Viertel nicht alles überdecken). Ohne Namen: Camp,
	-- Tankstellen (Place_Tank<n>) und Seen (gleicher Schlüssel wie ein Teil Lake_<Name>) – die Seen sieht man als Fläche.
	local places = map:FindFirstChild("Places")
	for _, part in places and places:GetChildren() or {} do
		local key = string.match(part.Name, "^Place_(.+)$")
		if part:IsA("BasePart") and key and key ~= "Camp" and not string.match(key, "^Tank%d*$")
			and not (lakes and lakes:FindFirstChild("Lake_" .. key)) then
			local u, v = toMap(map, part.Position.X, part.Position.Z)
			local big = part.Size.X >= 400
			local title = label({ Name = part.Name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(u, v),
				Size = UDim2.fromOffset(180, 16), Text = UITheme.Upper(part:GetAttribute("Title") or string.sub(part.Name, 7)),
				TextSize = big and 13 or 11, Font = big and F.Display or F.Bold,
				TextColor3 = big and Color3.fromRGB(214, 210, 200) or C.Text, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 }, layer)
			UITheme.Outline(title)
			if not big then
				table.insert(smallNames, title)
				title.Visible = view.Zoom >= 1.8
			end
		end
	end
	built = true
end

local function update()
	local map = getMap()
	if not map then
		return
	end
	if not built then
		build(map)
	end
	-- eigener Standort und Blickrichtung
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	arrow.Visible = root ~= nil
	if root then
		local u, v = toMap(map, root.Position.X, root.Position.Z)
		arrow.Position = UDim2.fromScale(u, v)
		local camera = workspace.CurrentCamera
		local look = camera and camera.CFrame.LookVector or Vector3.new(0, 0, 1)
		arrow.Rotation = math.deg(math.atan2(look.X, look.Z))
	end
	-- Rote Zone (zieht alle 20 Minuten weiter, darum bei jedem Update): Kreis mit der Zeit bis zum Weiterziehen
	local now = workspace:GetServerTimeNow()
	local raw = map:GetAttribute("Redzones")
	if raw ~= redRaw then
		redRaw = raw
		for _, view in redViews do
			view.Frame:Destroy()
		end
		redViews = {}
		for _, zoneInfo in decode(map, "Redzones") do
			if type(zoneInfo) == "table" and tonumber(zoneInfo.X) and tonumber(zoneInfo.Z) and tonumber(zoneInfo.R) then
				local frame = circle(markers, map, zoneInfo.X, zoneInfo.Z, zoneInfo.R, RED, 0.55, 5)
				frame.Name = "Redzone"
				local text = label({ Name = "Text", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.new(2.4, 0, 0, 16), TextSize = 12, Font = F.Display, TextColor3 = Color3.new(1, 1, 1),
					TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, frame)
				table.insert(redViews, { Frame = frame, Text = text, Ends = tonumber(zoneInfo.Ends) })
			end
		end
	end
	for _, view in redViews do
		local left = math.max(0, math.floor((view.Ends or now) - now))
		view.Text.Text = string.format("ROTE ZONE %d:%02d", left // 60, left % 60)
	end
	-- Lootdrops
	local seen = {}
	for _, drop in decode(map, "Airdrops") do
		local id = tostring(drop.Id)
		seen[id] = true
		local view = dropViews[id]
		if not view then
			view = make("Frame", { Name = "Airdrop", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14),
				BackgroundColor3 = DROP, BorderSizePixel = 0, Rotation = 45, ZIndex = 8 }, markers)
			UITheme.Stroke(view, Color3.new(0, 0, 0), 1.5, 0.2)
			label({ Name = "Text", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 6), Size = UDim2.fromOffset(120, 14),
				Rotation = -45, TextSize = 11, Font = F.Bold, TextColor3 = DROP, TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 8 }, view)
			dropViews[id] = view
		end
		local u, v = toMap(map, drop.X or 0, drop.Z or 0)
		view.Position = UDim2.fromScale(u, v)
		local text = view:FindFirstChild("Text")
		if text then
			text.Text = drop.State == "Landed" and "LOOTDROP" or ("LOOTDROP " .. math.max(0, math.ceil((drop.Eta or now) - now)) .. " S")
		end
	end
	-- Konvoi: roter Punkt mit Zustand
	for _, convoy in decode(map, "Convoys") do
		local id = "Convoy" .. tostring(convoy.Id)
		seen[id] = true
		local view = dropViews[id]
		if not view then
			view = make("Frame", { Name = "Convoy", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14),
				BackgroundColor3 = CONVOY, BorderSizePixel = 0, ZIndex = 9 }, markers)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, view)
			UITheme.Stroke(view, Color3.new(0, 0, 0), 1.5, 0.2)
			label({ Name = "Text", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(140, 14),
				TextSize = 11, Font = F.Bold, TextColor3 = CONVOY, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, view)
			dropViews[id] = view
		end
		local u, v = toMap(map, convoy.X or 0, convoy.Z or 0)
		view.Position = UDim2.fromScale(u, v)
		local text = view:FindFirstChild("Text")
		if text then
			text.Text = CONVOY_STATES[convoy.State] or "KONVOI"
		end
	end
	-- Horden-Kiste: lila Quadrat mit Fortschritt
	for _, horde in decode(map, "Hordes") do
		local id = "Horde" .. tostring(horde.Id)
		seen[id] = true
		local view = dropViews[id]
		if not view then
			view = make("Frame", { Name = "Horde", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14),
				BackgroundColor3 = HORDE, BorderSizePixel = 0, ZIndex = 9 }, markers)
			UITheme.Stroke(view, Color3.new(0, 0, 0), 1.5, 0.2)
			label({ Name = "Text", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(150, 14),
				TextSize = 11, Font = F.Bold, TextColor3 = HORDE, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, view)
			dropViews[id] = view
		end
		local u, v = toMap(map, horde.X or 0, horde.Z or 0)
		view.Position = UDim2.fromScale(u, v)
		local text = view:FindFirstChild("Text")
		if text then
			text.Text = horde.State == "Siege" and string.format("HORDE %d %%", math.floor((tonumber(horde.Progress) or 0) * 100))
				or "HORDEN-KISTE"
		end
	end
	-- Heli-Wrack: oranges Kreuz-Symbol (Raute) mit Zustand
	for _, crashInfo in decode(map, "HeliCrashes") do
		local id = "Heli" .. tostring(crashInfo.Id)
		seen[id] = true
		local view = dropViews[id]
		if not view then
			view = make("Frame", { Name = "HeliCrash", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 16),
				BackgroundColor3 = HELI, BorderSizePixel = 0, ZIndex = 9 }, markers)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, view)
			UITheme.Stroke(view, Color3.new(0, 0, 0), 1.5, 0.2)
			label({ Name = "Text", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(150, 14),
				TextSize = 11, Font = F.Bold, TextColor3 = HELI, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, view)
			dropViews[id] = view
		end
		local u, v = toMap(map, crashInfo.X or 0, crashInfo.Z or 0)
		view.Position = UDim2.fromScale(u, v)
		local text = view:FindFirstChild("Text")
		if text then
			text.Text = crashInfo.State == "Burning" and ("HELI BRENNT " .. math.max(0, math.ceil((tonumber(crashInfo.Ends) or now) - now)) .. " S")
				or "HELI-WRACK"
		end
	end
	-- Bosse: dunkelrote Raute mit Name, tot mit Zeit bis zur Rückkehr
	for _, bossInfo in decode(map, "Bosses") do
		local id = "Boss" .. tostring(bossInfo.Id)
		seen[id] = true
		local view = dropViews[id]
		if not view then
			view = make("Frame", { Name = "Boss", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14), Rotation = 45,
				BackgroundColor3 = BOSS, BorderSizePixel = 0, ZIndex = 9 }, markers)
			UITheme.Stroke(view, Color3.new(1, 1, 1), 1.5, 0.1)
			local caption = label({ Name = "Text", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 6), Rotation = -45,
				Size = UDim2.fromOffset(160, 14), TextSize = 11, Font = F.Display, TextColor3 = Color3.fromRGB(255, 110, 100),
				TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, view)
			UITheme.Outline(caption)
			dropViews[id] = view
		end
		local u, v = toMap(map, bossInfo.X or 0, bossInfo.Z or 0)
		view.Position = UDim2.fromScale(u, v)
		view.BackgroundColor3 = bossInfo.Alive and BOSS or Color3.fromRGB(80, 70, 70)
		local text = view:FindFirstChild("Text")
		if text then
			local left = math.max(0, math.floor((tonumber(bossInfo.RespawnAt) or now) - now))
			text.Text = tostring(bossInfo.Name) .. ((not bossInfo.Alive and left > 0) and string.format(" %d:%02d", left // 60, left % 60) or "")
		end
	end
	-- Aktivitäten: Vorratslager (gelb, leer grau) und Funkgerät (blau); Nester und Überlebende nicht
	for _, act in decode(map, "Activities") do
		local color = ACTIVITY_COLORS[act.Kind]
		if not color then
			continue
		end
		local id = "Act" .. tostring(act.Id)
		seen[id] = true
		local view = dropViews[id]
		if not view then
			view = make("Frame", { Name = "Activity_" .. tostring(act.Kind), AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(10, 10), BorderSizePixel = 0, ZIndex = 8 }, markers)
			if act.Kind ~= "Cache" then
				make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, view)
			end
			UITheme.Stroke(view, Color3.new(0, 0, 0), 1.2, 0.2)
			if act.Kind == "Radio" then
				label({ Name = "Text", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 3), Size = UDim2.fromOffset(140, 14),
					TextSize = 11, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 }, view)
			end
			dropViews[id] = view
		end
		local u, v = toMap(map, act.X or 0, act.Z or 0)
		view.Position = UDim2.fromScale(u, v)
		local idle = act.State == "Opened" or act.State == "Cooldown"
		view.BackgroundColor3 = idle and Color3.fromRGB(90, 90, 90) or color
		local text = view:FindFirstChild("Text")
		if text then
			text.TextColor3 = color
			text.Text = idle and "FUNK LÄDT" or "FUNK"
		end
	end
	for id, view in dropViews do
		if not seen[id] then
			view:Destroy()
			dropViews[id] = nil
		end
	end
	-- eigene Todestasche
	local ok, bag = pcall(HttpService.JSONDecode, HttpService, tostring(player:GetAttribute("ExtDeathBag") or ""))
	local hasBag = ok and type(bag) == "table" and tonumber(bag.X) ~= nil and tonumber(bag.Z) ~= nil
	bagView.Visible = hasBag
	if hasBag then
		local u, v = toMap(map, tonumber(bag.X), tonumber(bag.Z))
		bagView.Position = UDim2.fromScale(u, v)
		local left = math.max(0, math.floor((tonumber(bag.Ends) or now) - now))
		bagCaption.Text = string.format("DEINE TASCHE %d:%02d", left // 60, left % 60)
	end
end

-- Zoom und Mitte anwenden (Mitte so begrenzt, dass die Karte das Feld immer füllt)
local function applyView()
	local zoom = math.clamp(view.Zoom, 1, MAX_ZOOM)
	view.Zoom = zoom
	local half = 0.5 / zoom
	view.U = math.clamp(view.U, half, 1 - half)
	view.V = math.clamp(view.V, half, 1 - half)
	world.Size = UDim2.fromOffset(SIZE * zoom, SIZE * zoom)
	world.Position = UDim2.fromOffset(SIZE / 2 - view.U * SIZE * zoom, SIZE / 2 - view.V * SIZE * zoom)
	for _, title in smallNames do
		title.Visible = zoom >= 1.8
	end
	if zoomText then
		zoomText.Text = string.format("%.1fx", zoom)
	end
end

-- Zoomen um einen Punkt des Feldes (Design-Einheiten 0..SIZE; nil = Mitte): der Punkt bleibt, wo er ist
local function zoomBy(factor, px, py)
	px, py = px or SIZE / 2, py or SIZE / 2
	local u = view.U + (px - SIZE / 2) / (SIZE * view.Zoom)
	local v = view.V + (py - SIZE / 2) / (SIZE * view.Zoom)
	view.Zoom = math.clamp(view.Zoom * factor, 1, MAX_ZOOM)
	view.U = u - (px - SIZE / 2) / (SIZE * view.Zoom)
	view.V = v - (py - SIZE / 2) / (SIZE * view.Zoom)
	applyView()
end

-- Verschieben um Design-Einheiten
local function panBy(dx, dy)
	view.U -= dx / (SIZE * view.Zoom)
	view.V -= dy / (SIZE * view.Zoom)
	applyView()
end

-- Bildschirm-Pixel -> Design-Einheiten des Feldes
local function boardPoint(screen)
	local scale = board.AbsoluteSize.X > 0 and board.AbsoluteSize.X / SIZE or 1
	return (screen.X - board.AbsolutePosition.X) / scale, (screen.Y - board.AbsolutePosition.Y) / scale, scale
end

-- Zum eigenen Standort
local function centerOnMe()
	local map = getMap()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if map and root then
		view.U, view.V = toMap(map, root.Position.X, root.Position.Z)
		if view.Zoom < 2 then
			view.Zoom = 2.5
		end
		applyView()
	end
end

function ExtinctionMap.IsOpen()
	return gui ~= nil and gui.Enabled
end

function ExtinctionMap.Set(open)
	if not gui then
		return
	end
	gui.Enabled = open == true
	if gui.Enabled then
		-- Maus frei, solange die Karte offen ist (direkt nach der Kamera, die sie sonst wieder sperrt)
		RunService:BindToRenderStep("ExtinctionMapMouse", Enum.RenderPriority.Camera.Value + 1, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
		update()
	else
		RunService:UnbindFromRenderStep("ExtinctionMapMouse")
	end
end

function ExtinctionMap.Toggle()
	ExtinctionMap.Set(not ExtinctionMap.IsOpen())
end

-- Eintrag der Legende: Symbol (Form, Farbe) und Text
local function legendRow(parent, order, shape, color, text)
	local row = make("Frame", { Name = "Legend", Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local symbol = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(10, 11), Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = color, BackgroundTransparency = shape == "Ring" and 0.6 or 0, BorderSizePixel = 0,
		Rotation = shape == "Diamond" and 45 or 0 }, row)
	if shape == "Dot" or shape == "Ring" then
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, symbol)
	end
	if shape == "Ring" then
		UITheme.Stroke(symbol, color, 2, 0)
	end
	label({ Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 1, 0), Text = text, TextSize = 12, Font = F.Bold,
		TextColor3 = Color3.fromRGB(214, 211, 204) }, row)
end

local function mapButton(parent, name, text, position, onClick)
	local button = make("TextButton", { Name = name, Position = position, Size = UDim2.fromOffset(40, 36), BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.9, BorderSizePixel = 0, AutoButtonColor = false, Text = text, TextSize = 20, Font = F.Display,
		TextColor3 = C.Text }, parent)
	UITheme.Corner(button, 3)
	button.Activated:Connect(onClick)
	return button
end

function ExtinctionMap.Init()
	gui = make("ScreenGui", { Name = "ExtinctionMap", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9,
		Enabled = false }, player:WaitForChild("PlayerGui"))
	local root = UITheme.ScaledRoot(gui)
	make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
		BorderSizePixel = 0 }, root)
	local SIDE = 230
	local panel = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SIZE + SIDE + 36, SIZE + 70), BackgroundColor3 = Color3.fromRGB(8, 9, 11), BackgroundTransparency = 0.12,
		BorderSizePixel = 0 }, root)
	-- Kopfzeile wie im Menü: roter Streifen, Titel, rechts der Hinweis
	local header = make("Frame", { Name = "Header", Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 40),
		BackgroundColor3 = Color3.fromRGB(8, 9, 11), BackgroundTransparency = 0.2, BorderSizePixel = 0 }, panel)
	make("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Color3.fromRGB(214, 58, 58), BorderSizePixel = 0 }, header)
	label({ Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -36, 1, 0), Text = "KARTE  ·  ÖDLAND", TextSize = 20,
		Font = F.Display }, header)
	label({ Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -36, 1, 0), Text = "N SCHLIESSEN", TextSize = 12, Font = F.Bold,
		TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, header)
	board = make("Frame", { Name = "Board", Position = UDim2.fromOffset(12, 58), Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Color3.fromRGB(38, 44, 34), BorderSizePixel = 0, ClipsDescendants = true }, panel)
	world = make("Frame", { Name = "World", Size = UDim2.fromOffset(SIZE, SIZE), BackgroundTransparency = 1 }, board)
	layer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, world)
	markers = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8 }, world)
	arrow = label({ Name = "Me", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(24, 24), Text = "▲", TextSize = 22,
		Font = F.Display, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, markers)
	UITheme.Outline(arrow)
	bagView = label({ Name = "DeathBag", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), Text = "X", TextSize = 18,
		Font = F.Display, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9, Visible = false }, markers)
	UITheme.Outline(bagView)
	bagCaption = label({ Name = "Caption", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(150, 14), TextSize = 11, Font = F.Bold, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 9 }, bagView)

	-- rechts: Zoom und Legende
	local side = make("Frame", { Name = "Side", Position = UDim2.fromOffset(SIZE + 24, 58), Size = UDim2.fromOffset(SIDE, SIZE),
		BackgroundTransparency = 1 }, panel)
	label({ Size = UDim2.new(1, 0, 0, 16), Text = "ZOOM", TextSize = 12, Font = F.Display, TextColor3 = C.Muted }, side)
	mapButton(side, "ZoomOut", "−", UDim2.fromOffset(0, 22), function()
		zoomBy(1 / 1.5)
	end)
	zoomText = label({ Name = "ZoomLevel", Position = UDim2.fromOffset(44, 22), Size = UDim2.fromOffset(56, 36), Text = "1.0x", TextSize = 15,
		Font = F.Display, TextXAlignment = Enum.TextXAlignment.Center }, side)
	mapButton(side, "ZoomIn", "+", UDim2.fromOffset(104, 22), function()
		zoomBy(1.5)
	end)
	local me = mapButton(side, "CenterMe", "MITTE", UDim2.fromOffset(150, 22), centerOnMe)
	me.Size = UDim2.fromOffset(80, 36)
	me.TextSize = 13
	label({ Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 30), Text = "Mausrad / zwei Finger zoomen, ziehen verschiebt",
		TextSize = 11, Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, side)
	label({ Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 16), Text = "LEGENDE", TextSize = 12, Font = F.Display,
		TextColor3 = C.Muted }, side)
	local legend = make("Frame", { Name = "LegendList", Position = UDim2.fromOffset(0, 132), Size = UDim2.new(1, 0, 0, 300),
		BackgroundTransparency = 1 }, side)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, legend)
	for i, entry in {
		{ "Dot", Color3.new(1, 1, 1), "DU (PFEIL = BLICKRICHTUNG)" },
		{ "Ring", SAFE, "SAFE ZONE (CAMP, SAFEHOUSES)" },
		{ "Ring", RED, "ROTE ZONE (ZIEHT WEITER)" },
		{ "Diamond", DROP, "LOOTDROP" },
		{ "Dot", CONVOY, "KONVOI" },
		{ "Square", HORDE, "HORDEN-KISTE" },
		{ "Dot", HELI, "HELI-WRACK" },
		{ "Diamond", BOSS, "BOSS (BEWACHT SEIN GEBÄUDE)" },
		{ "Square", ACTIVITY_COLORS.Cache, "VORRATSLAGER" },
		{ "Dot", ACTIVITY_COLORS.Radio, "FUNKGERÄT" },
		{ "Square", RED, "X  DEINE TASCHE" },
	} do
		legendRow(legend, i, entry[1], entry[2], entry[3])
	end

	-- Eingaben auf dem Feld: Mausrad zoomt zum Zeiger, Ziehen verschiebt
	local dragging, last = false, nil
	board.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, last = true, input.Position
		end
	end)
	board.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local px, py = boardPoint(input.Position)
			zoomBy(input.Position.Z > 0 and 1.25 or 1 / 1.25, px, py)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not gui.Enabled then
			return
		end
		if dragging and last and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local _, _, scale = boardPoint(input.Position)
			local delta = input.Position - last
			last = input.Position
			panBy(delta.X / scale, delta.Y / scale)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, last = false, nil
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.zero
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if not gui.Enabled then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.Equals or input.KeyCode == Enum.KeyCode.KeypadPlus then
			zoomBy(1.5)
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 or input.KeyCode == Enum.KeyCode.Minus or input.KeyCode == Enum.KeyCode.KeypadMinus then
			zoomBy(1 / 1.5)
		end
	end)
	-- Handy: zwei Finger zoomen
	if UserInputService.TouchPinch then
		local lastScale = 1
		UserInputService.TouchPinch:Connect(function(_, scale, _, state)
			if not gui.Enabled then
				return
			end
			if state == Enum.UserInputState.Begin then
				lastScale = 1
			end
			dragging = false
			zoomBy(scale / lastScale)
			lastScale = scale
		end)
	end
	applyView()
	RunService.Heartbeat:Connect(function(dt)
		if gui.Enabled then
			if stick.Magnitude > 0.2 then
				panBy(-stick.X * 600 * dt, stick.Y * 600 * dt)
			end
			update()
		end
	end)
end

return ExtinctionMap

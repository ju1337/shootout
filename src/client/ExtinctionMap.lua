-- ExtinctionMap (ModuleScript, nur Client)
-- Weltkarte der offenen Welt (EXTINCTION), Taste N (oder Knopf KARTE): Straßen und Flächen aus den Gruppen Roads und
-- Ground der Karte, die Safe Zones (grün), die rote Zone (roter Kreis mit der Zeit bis zum Weiterziehen), Orte (Namen),
-- Lootdrops (orange, mit Countdown), Vorratslager und Funkgerät, die eigene Todestasche (rotes X mit der Zeit, bis sie
-- verschwindet, Spieler-Attribut ExtDeathBag) und der eigene Standort als Pfeil in Blickrichtung.
-- Norden (+Z) ist oben.
-- Zombienester und Überlebende stehen nicht auf der Karte (man findet sie draußen), damit sie übersichtlich bleibt.
-- Daten: Karte workspace.Maps.Extinction (Attribute Center, Redzones, Airdrops, Activities; Gruppen Roads, Ground, Places,
-- Zone).

local Players = game:GetService("Players")
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

local SIZE = 640                    -- Kantenlänge der Karte (Design-Einheiten)
local WORLD = ExtinctionConfig.WorldSize
local RED = Color3.fromRGB(226, 56, 48)
local SAFE = Color3.fromRGB(112, 200, 120)
local DROP = Color3.fromRGB(255, 170, 60)
local GROUND_COLORS = {             -- Flächen der Gruppe Ground nach Name (alles andere wird nicht gezeichnet)
	Sidewalk = Color3.fromRGB(84, 86, 88),
	CampPad = Color3.fromRGB(104, 104, 100),
	Field = Color3.fromRGB(96, 80, 56),
}
local BUILDING_PARTS = { Roof = true, FallenRoof = true, Upper = true, Tower = true, TowerStub = true, PrisonWall = true }

local gui, board, layer, markers, arrow, bagView, bagCaption
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
			local frame = circle(layer, map, safe.Position.X, safe.Position.Z, math.max(safe.Size.X / 2, 45), SAFE, 0.45, 4)
			frame.Name = safe.Name
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
				TextColor3 = big and C.Muted or C.Text, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 }, layer)
			UITheme.Outline(title)
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

function ExtinctionMap.IsOpen()
	return gui ~= nil and gui.Enabled
end

function ExtinctionMap.Set(open)
	if not gui then
		return
	end
	gui.Enabled = open == true
	if gui.Enabled then
		update()
	end
end

function ExtinctionMap.Toggle()
	ExtinctionMap.Set(not ExtinctionMap.IsOpen())
end

function ExtinctionMap.Init()
	gui = make("ScreenGui", { Name = "ExtinctionMap", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9,
		Enabled = false }, player:WaitForChild("PlayerGui"))
	local root = UITheme.ScaledRoot(gui)
	make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
		BorderSizePixel = 0 }, root)
	local panel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(SIZE + 24, SIZE + 64), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.05, BorderSizePixel = 0 }, root)
	UITheme.Corner(panel, UITheme.Radius.Small)
	UITheme.Stroke(panel, C.Border, 1, 0.2)
	label({ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 26), Text = "KARTE · ÖDLAND", TextSize = 22,
		Font = F.Display, TextColor3 = C.Primary }, panel)
	label({ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 26), Text = "N SCHLIESSEN", TextSize = 12,
		Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, panel)
	board = make("Frame", { Name = "Board", Position = UDim2.fromOffset(12, 44), Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Color3.fromRGB(44, 52, 40), BorderSizePixel = 0, ClipsDescendants = true }, panel)
	layer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, board)
	markers = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8 }, board)
	arrow = label({ Name = "Me", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 22), Text = "▲", TextSize = 20,
		Font = F.Display, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, markers)
	UITheme.Outline(arrow)
	bagView = label({ Name = "DeathBag", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), Text = "X", TextSize = 18,
		Font = F.Display, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9, Visible = false }, markers)
	UITheme.Outline(bagView)
	bagCaption = label({ Name = "Caption", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(150, 14), TextSize = 11, Font = F.Bold, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 9 }, bagView)
	-- Legende
	local legend = label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -6), Size = UDim2.fromOffset(SIZE - 16, 16),
		Text = "▲ DU  ·  GRÜN SAFE ZONE  ·  ROT ROTE ZONE  ·  ◆ LOOTDROP  ·  ■ LAGER  ·  ● FUNK  ·  X DEINE TASCHE", TextSize = 11,
		Font = F.Bold,
		TextColor3 = C.Text, ZIndex = 9 }, board)
	UITheme.Outline(legend)
	RunService.Heartbeat:Connect(function()
		if gui.Enabled then
			update()
		end
	end)
end

return ExtinctionMap

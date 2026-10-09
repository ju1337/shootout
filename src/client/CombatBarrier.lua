-- CombatBarrier (ModuleScript, nur Client)
-- Im Kampf (Spieler-Attribut CombatUntil, setzt Damage bei Treffern Spieler gegen Spieler) kommt man nicht in eine Safe
-- Zone (der Server setzt einen sonst auf den Rand zurück, Modes/Extinction). Sichtbar gemacht:
--   * rote Wand aus Kraftfeld um jede Safe Zone in der Nähe (nur bei diesem Spieler, mit Kollision: man läuft dagegen)
--   * Anzeige oben in der Mitte: IM KAMPF · SAFE ZONE GESPERRT mit Countdown
-- Nach ExtinctionConfig.CombatTime Sekunden ohne neuen Treffer verschwindet beides.
-- Dieselbe Anzeige zeigt in Blau den Spawnschutz nach dem Verlassen einer Safe Zone (Attribut ProtectedUntil).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.UITheme)

local player = Players.LocalPlayer

local CombatBarrier = {}

local RED = Color3.fromRGB(235, 60, 60)
local SEGMENT = 8      -- Länge eines Wandstücks (Studs)
local HEIGHT = 60      -- Höhe der Wand
local SHOW_WITHIN = 400 -- Wände nur um Safe Zones, deren Rand so nah ist

local folder -- Wände (in workspace, nur lokal)
local walls = {} -- [Teil der Safe Zone] = { Wandstücke }
local gui, label

local function inCombat()
	return player:GetAttribute("Mode") == "Extinction"
		and (player:GetAttribute("CombatUntil") or 0) > workspace:GetServerTimeNow()
end

local function zoneParts()
	local maps = workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild("Extinction")
	local zone = map and map:FindFirstChild("Zone")
	local list = {}
	for _, part in zone and zone:GetChildren() or {} do
		if part:IsA("BasePart") and (part.Name == "SafeZone" or string.sub(part.Name, 1, 9) == "SafeZone_") then
			table.insert(list, part)
		end
	end
	return list
end

-- Ring aus Wandstücken um eine Safe Zone (Kreis, Radius = halbe Breite des Teils)
local function buildWall(part)
	local center, radius = part.Position, part.Size.X / 2
	local count = math.max(16, math.ceil(2 * math.pi * radius / SEGMENT))
	local width = 2 * math.pi * radius / count + 0.4
	local list = {}
	for i = 1, count do
		local angle = (i - 0.5) / count * 2 * math.pi
		local position = Vector3.new(center.X + math.cos(angle) * radius, center.Y + HEIGHT / 2 - 8, center.Z + math.sin(angle) * radius)
		local wall = Instance.new("Part")
		wall.Name = "CombatWall"
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
		wall.Material = Enum.Material.ForceField
		wall.Color = RED
		wall.Transparency = 0
		wall.Size = Vector3.new(width, HEIGHT, 1)
		wall.CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
		wall.Parent = folder
		table.insert(list, wall)
	end
	return list
end

local function clearWalls()
	for _, list in walls do
		for _, wall in list do
			wall:Destroy()
		end
	end
	table.clear(walls)
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "CombatBarrier"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 8
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	label = UITheme.Label({ Name = "Combat", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 18,
		Font = UITheme.Fonts.Display, TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.fromRGB(150, 30, 34),
		BackgroundTransparency = 0.15, TextXAlignment = Enum.TextXAlignment.Center }, gui)
	UITheme.Corner(label, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = RED
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label
end

local function setLook(color, back)
	label.BackgroundColor3 = back
	label:FindFirstChildOfClass("UIStroke").Color = color
end

local function update()
	local active = inCombat()
	local protectedLeft = (player:GetAttribute("ProtectedUntil") or 0) - workspace:GetServerTimeNow()
	local protected = not active and protectedLeft > 0 and player:GetAttribute("Mode") == "Extinction"
	gui.Enabled = active or protected
	if protected then
		setLook(Color3.fromRGB(90, 170, 255), Color3.fromRGB(26, 70, 130))
		label.Text = "🛡 SPAWNSCHUTZ  ·  NOCH KEIN SCHIESSEN  ·  " .. math.ceil(protectedLeft) .. " s"
	end
	if not active then
		if next(walls) then
			clearWalls()
		end
		return
	end
	setLook(RED, Color3.fromRGB(150, 30, 34))
	local left = math.ceil((player:GetAttribute("CombatUntil") or 0) - workspace:GetServerTimeNow())
	label.Text = "⚔ IM KAMPF  ·  SAFE ZONE GESPERRT  ·  " .. left .. " s"
	-- Wände um Safe Zones in der Nähe (Streaming: weit entfernte sind evtl. gar nicht geladen)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local seen = {}
	for _, part in zoneParts() do
		local edge = root and (Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z).Magnitude
			- part.Size.X / 2)
		-- nur von außen: wer (z.B. durch eine Granate aus der Zone) drinnen im Kampf ist, darf hinaus
		local near = edge and edge > 0 and edge < SHOW_WITHIN
		if near then
			seen[part] = true
			if not walls[part] then
				walls[part] = buildWall(part)
			end
		end
	end
	for part, list in walls do
		if not seen[part] then
			for _, wall in list do
				wall:Destroy()
			end
			walls[part] = nil
		end
	end
	-- Wand pulsiert leicht
	local pulse = 0.15 + (math.sin(os.clock() * 4) + 1) * 0.1
	for _, list in walls do
		for _, wall in list do
			wall.Transparency = pulse
		end
	end
end

function CombatBarrier.Init()
	folder = Instance.new("Folder")
	folder.Name = "CombatBarrier"
	folder.Parent = workspace
	buildGui()
	local last = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last < 0.1 then
			return
		end
		last = now
		local ok, err = pcall(update)
		if not ok then
			warn("CombatBarrier: " .. tostring(err))
		end
	end)
end

return CombatBarrier

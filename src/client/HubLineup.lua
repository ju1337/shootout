-- HubLineup (ModuleScript, nur Client)
-- Wie in der Rogue-Company-Lobby: Auf der Lineup-Bühne im Hangar steht groß der eigene Agent
-- (mit Skin und gewählter Primärwaffe) und dreht sich langsam. Nur lokal sichtbar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local AgentFigure = require(Shared.AgentFigure)
local Cosmetics = require(Shared.Cosmetics)
local Modes = require(Shared.Modes)
local RankConfig = require(Shared.RankConfig)
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

local HubLineup = {}

local STAGE_POSITION = Vector3.new(0, 1.2, 18) -- Mitte der Bühne im Hangar (Hub-Map)
local SCALE = 1.7

local figure = nil

local function rebuild()
	if figure then
		figure:Destroy()
		figure = nil
	end
	if player:GetAttribute("Mode") ~= "Hub" then
		return
	end
	local agent = AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
	local weapon = AgentConfig.LoadoutFor(player, agent.Id)[1]
	local primary, accent = Cosmetics.AgentColors(player, agent.Id)
	figure = AgentFigure.Build(agent, primary, accent, Cosmetics.WeaponSkin(player, agent.Id, weapon), weapon)
	figure.Name = "LineupAgent"
	figure:ScaleTo(SCALE)
	for _, part in figure:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	figure.Parent = workspace
end

-- Einsatz-Tafel im Hangar: live, wie viele Spieler in welchem Modus sind
local function buildMissionBoard()
	local board = workspace:WaitForChild("Maps"):WaitForChild("Hub"):WaitForChild("Decor"):WaitForChild("MissionBoard", 10)
	if not board then
		return
	end
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.Parent = player:WaitForChild("PlayerGui")
	surface.Adornee = board
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.16, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Oswald
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(40, 210, 230)
	title.Text = "EINSATZ-ÜBERSICHT"
	title.Parent = surface
	local list = Instance.new("TextLabel")
	list.Position = UDim2.new(0.06, 0, 0.2, 0)
	list.Size = UDim2.new(0.88, 0, 0.76, 0)
	list.BackgroundTransparency = 1
	list.Font = Enum.Font.Oswald
	list.TextSize = 30
	list.TextColor3 = Color3.fromRGB(235, 242, 248)
	list.TextXAlignment = Enum.TextXAlignment.Left
	list.TextYAlignment = Enum.TextYAlignment.Top
	list.RichText = true
	list.Parent = surface
	-- Spielerzahl-Felder an den Toren (Parts "GateCount_<ModusId>")
	local gateLabels = {}
	for _, part in board.Parent:GetChildren() do
		local id = string.match(part.Name, "^GateCount_(.+)$")
		if id and part:IsA("BasePart") then
			local gateGui = Instance.new("SurfaceGui")
			gateGui.Face = Enum.NormalId.Front
			gateGui.LightInfluence = 0
			gateGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gateGui.PixelsPerStud = 40
			gateGui.Adornee = part
			gateGui.Parent = player:WaitForChild("PlayerGui")
			local countLabel = Instance.new("TextLabel")
			countLabel.Size = UDim2.new(1, 0, 1, 0)
			countLabel.BackgroundTransparency = 1
			countLabel.Font = Enum.Font.GothamBlack
			countLabel.TextScaled = true
			countLabel.Text = ""
			countLabel.Parent = gateGui
			gateLabels[id] = countLabel
		end
	end

	local function update()
		local ok, counts = pcall(HttpService.JSONDecode, HttpService, ReplicatedStorage:GetAttribute("ModeCounts") or "{}")
		counts = ok and counts or {}
		local lines = {}
		for _, mode in Modes.List do
			if mode.Available then
				local n = counts[mode.Id] or 0
				local color = n > 0 and "#50D282" or "#5A6B80"
				table.insert(lines, mode.Name .. '   <font color="' .. color .. '">' .. n .. " Spieler</font>")
			end
		end
		list.Text = table.concat(lines, "\n")
		-- Spielerzahl unter jedem Tor-Schild
		for id, countLabel in gateLabels do
			local n = counts[id] or 0
			countLabel.Text = n > 0 and ("● " .. n .. " SPIELER") or "○ FREI"
			countLabel.TextColor3 = n > 0 and Color3.fromRGB(80, 210, 130) or Color3.fromRGB(150, 165, 185)
		end
	end
	update()
	ReplicatedStorage:GetAttributeChangedSignal("ModeCounts"):Connect(update)
end

-- Bestenlisten-Tafeln im Hub (Parts "Leaderboard_<Name>", Daten vom LeaderboardService)
local BOARD_INFO = {
	Elo = { Title = "🏆  HÖCHSTE ELO", Color = Color3.fromRGB(250, 205, 70) },
	Kills = { Title = "☠  MEISTE KILLS", Color = Color3.fromRGB(230, 60, 70) },
	Level = { Title = "★  HÖCHSTES LEVEL", Color = Color3.fromRGB(40, 210, 230) },
	Wins = { Title = "✓  MEISTE SIEGE", Color = Color3.fromRGB(90, 220, 110) },
}
local PLACE_COLORS = { Color3.fromRGB(250, 205, 70), Color3.fromRGB(200, 205, 215), Color3.fromRGB(205, 130, 70) }

local function formatValue(board, value)
	value = tonumber(value) or 0
	if board == "Elo" then
		return value .. "  " .. RankConfig.Get(value).Display, RankConfig.Get(value).Color
	elseif board == "Level" then
		local prestige, level = value // 1000, value % 1000
		return (prestige > 0 and ("P" .. prestige .. " · ") or "") .. "LV " .. level, nil
	end
	local text = tostring(math.floor(value))
	return text:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", ""), nil
end

local function buildLeaderboards()
	local decor = workspace:WaitForChild("Maps"):WaitForChild("Hub"):WaitForChild("Decor")
	for board, info in BOARD_INFO do
		local part = decor:WaitForChild("Leaderboard_" .. board, 10)
		if part then
			local surface = Instance.new("SurfaceGui")
			surface.Face = Enum.NormalId.Front
			surface.LightInfluence = 0
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 40
			surface.Adornee = part
			surface.Parent = player:WaitForChild("PlayerGui")
			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, 0, 0.13, 0)
			title.BackgroundColor3 = info.Color
			title.BackgroundTransparency = 0.15
			title.BorderSizePixel = 0
			title.Font = Enum.Font.GothamBlack
			title.TextScaled = true
			title.TextColor3 = Color3.fromRGB(14, 22, 36)
			title.Text = info.Title
			title.Parent = surface
			local rows = {}
			for i = 1, 10 do
				local row = Instance.new("Frame")
				row.Position = UDim2.new(0.03, 0, 0.15 + (i - 1) * 0.084, 0)
				row.Size = UDim2.new(0.94, 0, 0.076, 0)
				row.BackgroundColor3 = Color3.fromRGB(24, 40, 62)
				row.BackgroundTransparency = i % 2 == 0 and 0.4 or 0.75
				row.BorderSizePixel = 0
				row.Parent = surface
				local function cell(x, w, align, font)
					local label = Instance.new("TextLabel")
					label.Position = UDim2.new(x, 0, 0.08, 0)
					label.Size = UDim2.new(w, 0, 0.84, 0)
					label.BackgroundTransparency = 1
					label.Font = font
					label.TextScaled = true
					label.TextColor3 = Color3.fromRGB(235, 242, 248)
					label.TextXAlignment = align
					label.Text = ""
					label.Parent = row
					return label
				end
				rows[i] = {
					Frame = row,
					Place = cell(0.01, 0.1, Enum.TextXAlignment.Center, Enum.Font.GothamBlack),
					Name = cell(0.13, 0.5, Enum.TextXAlignment.Left, Enum.Font.GothamBold),
					Value = cell(0.6, 0.38, Enum.TextXAlignment.Right, Enum.Font.Oswald),
				}
			end
			local function update()
				local ok, list = pcall(HttpService.JSONDecode, HttpService,
					ReplicatedStorage:GetAttribute("Leaderboard_" .. board) or "[]")
				list = ok and type(list) == "table" and list or {}
				for i, row in rows do
					local entry = list[i]
					row.Place.Text = entry and ("#" .. i) or ""
					row.Place.TextColor3 = PLACE_COLORS[i] or Color3.fromRGB(130, 155, 175)
					row.Name.Text = entry and tostring(entry.Name) or (i == 1 and "Noch keine Einträge" or "")
					local isMe = entry and entry.UserId == player.UserId
					row.Name.TextColor3 = isMe and Color3.fromRGB(40, 210, 230) or Color3.fromRGB(235, 242, 248)
					row.Frame.BackgroundColor3 = isMe and Color3.fromRGB(28, 62, 78) or Color3.fromRGB(24, 40, 62)
					if entry then
						local text, color = formatValue(board, entry.Value)
						row.Value.Text = text
						row.Value.TextColor3 = color or info.Color
					else
						row.Value.Text = ""
					end
				end
			end
			update()
			ReplicatedStorage:GetAttributeChangedSignal("Leaderboard_" .. board):Connect(update)
		end
	end
end

-- Leuchtpartikel an den Toren (in Torfarbe) und Funkeln über dem Siegertreppchen
local function addParticles()
	local decor = workspace:WaitForChild("Maps"):WaitForChild("Hub"):WaitForChild("Decor")
	task.wait(1)
	for _, part in decor:GetChildren() do
		if part:IsA("BasePart") and (part.Name == "GateGlow" or part.Name == "PodiumGlow") then
			local emitter = Instance.new("ParticleEmitter")
			local podium = part.Name == "PodiumGlow"
			emitter.Color = ColorSequence.new(podium and Color3.fromRGB(255, 225, 140) or part.Color)
			emitter.LightEmission = 1
			emitter.Rate = podium and 10 or 8
			emitter.Lifetime = NumberRange.new(2, 3.5)
			emitter.Speed = NumberRange.new(2, 4)
			emitter.SpreadAngle = Vector2.new(15, 15)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, podium and 0.35 or 0.5),
				NumberSequenceKeypoint.new(1, 0) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			-- Die Podest-Scheibe ist um 90° gekippt: ihre lokale X-Achse zeigt nach oben
			emitter.EmissionDirection = podium and Enum.NormalId.Right or Enum.NormalId.Top
			emitter.LockedToPart = false
			emitter.Parent = part
		end
	end
end

function HubLineup.Init()
	task.spawn(buildMissionBoard)
	task.spawn(addParticles)
	task.spawn(buildLeaderboards)
	rebuild()
	player.AttributeChanged:Connect(function(name)
		if name == "Mode" or name == "Agent" or name == "Equipped" or name == "Owned" or name == "Loadouts"
			or string.sub(name, 1, 3) == "XP_" then
			rebuild()
		end
	end)
	-- Langsam hin und her drehen, Blick Richtung Spawn (Süden)
	RunService.RenderStepped:Connect(function()
		if figure then
			local angle = math.sin(os.clock() * 0.5) * 0.5
			local height = 3 * SCALE -- Figur steht mit den Füßen auf der Bühne
			figure:PivotTo(CFrame.new(STAGE_POSITION + Vector3.new(0, height, 0)) * CFrame.Angles(0, angle, 0))
		end
	end)
end

return HubLineup

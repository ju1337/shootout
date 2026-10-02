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
local GunModels = require(Shared.GunModels)
local GameMenu = require(Shared.GameMenu)
local UITheme = require(Shared.UITheme)

local player = Players.LocalPlayer

-- Holo-Tafel (Attribut "Holo" am Part): Schrift leuchtet unabhängig vom Licht, mit blauem Schimmer
local function holoSurface(surface, part)
	if part:GetAttribute("Holo") then
		surface.LightInfluence = 0
		surface.Brightness = 2.2
		for _, label in surface:GetDescendants() do
			if label:IsA("TextLabel") then
				label.TextStrokeColor3 = Color3.fromRGB(40, 120, 180)
				label.TextStrokeTransparency = 0.5
			end
		end
	end
end


local HubLineup = {}

-- Bühne mit dem eigenen Agenten: nur wenn die Hub-Map einen Part "LineupSpot" hat (alter Hangar);
-- Position = Füße, LookVector = Blickrichtung der Figur. Der kompakte Hub hat stattdessen den Shop.
local STAGE_POSITION = Vector3.new(0, 1.2, 18)
local STAGE_FACING = Vector3.new(0, 0, -1)
local lineupEnabled = false
local rebuildLineup -- vorab (rebuild steht weiter unten)
task.spawn(function()
	local spot = workspace:WaitForChild("Maps"):WaitForChild("Hub"):WaitForChild("Decor"):WaitForChild("LineupSpot", 10)
	if spot then
		STAGE_POSITION = spot.Position
		STAGE_FACING = spot.CFrame.LookVector
		lineupEnabled = true
		if rebuildLineup then
			rebuildLineup()
		end
	end
end)
local SCALE = 1.7

local figure = nil

local function rebuild()
	rebuildLineup = rebuild
	if figure then
		figure:Destroy()
		figure = nil
	end
	if player:GetAttribute("Mode") ~= "Hub" or not lineupEnabled then
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
	-- Schild über der Bühne: Name des Agenten in seiner Farbe, darunter Level und wo man ihn wechselt
	local banner = workspace:FindFirstChild("Maps") and workspace.Maps:FindFirstChild("Hub")
		and workspace.Maps.Hub:FindFirstChild("Decor") and workspace.Maps.Hub.Decor:FindFirstChild("StageBanner")
	local signGui = banner and banner:FindFirstChild("SignGui")
	if signGui then
		local title, subtitle = signGui:FindFirstChild("Title"), signGui:FindFirstChild("Subtitle")
		if title then
			title.Text = string.upper(agent.Name)
			title.TextColor3 = agent.Color:Lerp(Color3.new(1, 1, 1), 0.25)
		end
		if subtitle then
			subtitle.Text = "DEIN AGENT  ·  LEVEL " .. AgentConfig.LevelFromXP(AgentConfig.GetXP(player, agent.Id))
				.. "  ·  WECHSELN UNTER AGENTEN"
		end
	end
end

-- Agent der Woche: Statue auf dem Sockel in der Hallenmitte (Part "AgentOfWeekSpot") mit Elite-Skin
-- (Gold, glänzend, Leuchtkontur, Funken) und Holo-Schrift darüber ("AgentOfWeekHolo"). Jede Woche
-- (ab Montag 0 Uhr UTC) ist der nächste Agent dran – aus der Serverzeit berechnet, für alle gleich.
local WEEK = 7 * 24 * 3600
local MONDAY_OFFSET = 4 * 24 * 3600 -- 1.1.1970 war ein Donnerstag
local STATUE_SCALE = 1.8
local GOLD = Color3.fromRGB(230, 182, 74)
local HOLO = Color3.fromRGB(140, 210, 245)

function HubLineup.AgentOfWeek()
	local week = math.floor((workspace:GetServerTimeNow() + MONDAY_OFFSET) / WEEK)
	return AgentConfig.Agents[week % #AgentConfig.Agents + 1]
end

-- Elite-Skin: Uniform aus dem besten Shop-Skin des Agenten (sonst dunkel in Agentenfarbe), Weste/Visier Gold
local function eliteColors(agent)
	local best, bestRank = nil, 0
	local ranks = { Rare = 1, Epic = 2, Legendary = 3 }
	for _, item in Cosmetics.List("Agent", agent.Id) do
		local rank = ranks[item.Rarity] or 0
		if rank > bestRank then
			best, bestRank = item, rank
		end
	end
	local primary = best and bestRank >= 2 and best.Primary or agent.Color:Lerp(Color3.new(0, 0, 0), 0.7)
	return primary, GOLD
end

local function buildAgentOfWeek()
	local decor = workspace:WaitForChild("Maps"):WaitForChild("Hub"):WaitForChild("Decor")
	local spot = decor:WaitForChild("AgentOfWeekSpot", 10)
	local holoPoint = decor:WaitForChild("AgentOfWeekHolo", 10)
	if not spot then
		return
	end
	-- Holo-Schrift: schwebt über dem Agenten, schaut immer zur Kamera, leicht flackernd
	local nameLabel, infoLabel, holoLabels = nil, nil, {}
	if holoPoint then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "AgentOfWeekHolo"
		billboard.Adornee = holoPoint
		billboard.Size = UDim2.new(11, 0, 3.4, 0) -- in Studs: wirkt wie ein Hologramm im Raum
		billboard.LightInfluence = 0
		billboard.MaxDistance = 160
		billboard.Parent = player:WaitForChild("PlayerGui")
		local function text(y, h, font, color)
			local label = Instance.new("TextLabel")
			label.Position = UDim2.new(0, 0, y, 0)
			label.Size = UDim2.new(1, 0, h, 0)
			label.BackgroundTransparency = 1
			label.Font = font
			label.TextScaled = true
			label.TextColor3 = color
			label.TextTransparency = 0.1
			label.TextStrokeColor3 = Color3.fromRGB(40, 120, 180)
			label.TextStrokeTransparency = 0.5
			label.Parent = billboard
			table.insert(holoLabels, label)
			return label
		end
		text(0, 0.22, Enum.Font.GothamBold, HOLO).Text = "AGENT DER WOCHE"
		nameLabel = text(0.22, 0.52, Enum.Font.Oswald, Color3.new(1, 1, 1))
		infoLabel = text(0.76, 0.22, Enum.Font.GothamBold, HOLO)
		-- dünne Holo-Linie unter der Überschrift
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0)
		line.Position = UDim2.new(0.5, 0, 0.22, 0)
		line.Size = UDim2.new(0.55, 0, 0, 2)
		line.BackgroundColor3 = HOLO
		line.BackgroundTransparency = 0.3
		line.BorderSizePixel = 0
		line.Parent = billboard
	end

	local statue, shownId = nil, nil
	local function refresh()
		local agent = HubLineup.AgentOfWeek()
		if agent.Id == shownId then
			return
		end
		shownId = agent.Id
		if statue then
			statue:Destroy()
		end
		local primary, accent = eliteColors(agent)
		statue = AgentFigure.Build(agent, primary, accent, Cosmetics.Get("W_Goldrausch"), agent.Loadout[1])
		statue.Name = "AgentOfWeek"
		statue:ScaleTo(STATUE_SCALE)
		for _, part in statue:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				-- Gold glänzt (Foil), Visier leuchtet in der Agentenfarbe
				if part.Color == GOLD then
					part.Material = Enum.Material.Foil
				end
				if part.Name == "Visor" then
					part.Color = agent.Color
				end
			end
		end
		-- Leuchtkontur und Gold-Funken
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineColor = GOLD
		highlight.OutlineTransparency = 0.25
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = statue
		local torso = statue.PrimaryPart
		if torso then
			local sparkles = Instance.new("ParticleEmitter")
			sparkles.Color = ColorSequence.new(GOLD)
			sparkles.LightEmission = 1
			sparkles.Rate = 6
			sparkles.Lifetime = NumberRange.new(1.2, 2)
			sparkles.Speed = NumberRange.new(0.5, 1.5)
			sparkles.SpreadAngle = Vector2.new(180, 180)
			sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
			sparkles.Parent = torso
		end
		statue.Parent = workspace
		if nameLabel then
			nameLabel.Text = string.upper(agent.Name)
			nameLabel.TextColor3 = agent.Color:Lerp(Color3.new(1, 1, 1), 0.35)
			infoLabel.Text = string.upper(agent.Role) .. "  ·  " .. string.upper(agent.Ability.Name)
		end
	end
	refresh()
	-- Langsam drehen, Holo-Schrift leicht flackern/schweben; einmal pro Minute auf neue Woche prüfen
	local lastCheck = os.clock()
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if t - lastCheck > 60 then
			lastCheck = t
			refresh()
		end
		if statue and statue.Parent then
			local base = spot.Position + Vector3.new(0, 3 * STATUE_SCALE, 0)
			statue:PivotTo(CFrame.lookAt(base, base + spot.CFrame.LookVector) * CFrame.Angles(0, t * 0.35, 0))
		end
		local flicker = (math.random() < 0.02) and 0.45 or 0.1
		for _, label in holoLabels do
			label.TextTransparency = flicker
		end
	end)
end

-- Shop-Vitrine im kompakten Hub: drei Angebote des Tages (zwei Waffen-Skins, ein Agenten-Skin) drehen sich in
-- den Vitrinen ("ShopDisplay1..3"), Schilder davor ("ShopPlaque1..3") mit Name, Seltenheit und Preis.
-- An der Theke ("ShopCounter") öffnet E den Shop. Angebote wechseln täglich (Serverzeit, für alle gleich).
local DAY = 24 * 3600

local function dailyOffers()
	local day = math.floor(workspace:GetServerTimeNow() / DAY)
	local random = Random.new(day * 7919 + 17)
	local weapons, agents = {}, {}
	for _, item in Cosmetics.List("Weapon") do
		if not item.Pass then
			table.insert(weapons, item)
		end
	end
	for _, item in Cosmetics.List("Agent") do
		if not item.Pass then
			table.insert(agents, item)
		end
	end
	local offers = {}
	local first = table.remove(weapons, random:NextInteger(1, #weapons))
	local agentItem = agents[random:NextInteger(1, #agents)]
	local second = table.remove(weapons, random:NextInteger(1, #weapons))
	table.insert(offers, first)
	table.insert(offers, agentItem) -- Agent in der Mitte
	table.insert(offers, second)
	return offers, day
end

local function buildShopVitrine()
	local decor = workspace:WaitForChild("Maps"):WaitForChild("Hub"):WaitForChild("Decor")
	local counter = decor:WaitForChild("ShopCounter", 10)
	if not counter then
		return -- alter Hangar ohne Shop
	end
	-- E an der Theke öffnet den Shop (Prompt nur lokal)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Shop öffnen"
	prompt.ObjectText = "SHOP"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	prompt.Triggered:Connect(function()
		GameMenu.Open("Shop")
	end)

	local models, shownDay = {}, nil
	local function plaque(index, item)
		local part = decor:FindFirstChild("ShopPlaque" .. index)
		if not part then
			return
		end
		local surface = part:FindFirstChild("PlaqueGui")
		if not surface then
			surface = Instance.new("SurfaceGui")
			surface.Name = "PlaqueGui"
			surface.Face = Enum.NormalId.Front
			surface.LightInfluence = 0
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 60
			surface.Adornee = part
			surface.Parent = player:WaitForChild("PlayerGui")
			for _, spec in { { "ItemName", 0.04, 0.46, Enum.Font.Oswald }, { "ItemInfo", 0.54, 0.4, Enum.Font.GothamBold } } do
				local label = Instance.new("TextLabel")
				label.Name = spec[1]
				label.Position = UDim2.new(0.05, 0, spec[2], 0)
				label.Size = UDim2.new(0.9, 0, spec[3], 0)
				label.BackgroundTransparency = 1
				label.Font = spec[4]
				label.TextScaled = true
				label.TextColor3 = Color3.new(1, 1, 1)
				label.Parent = surface
			end
		end
		holoSurface(surface, part)
		local rarity = Cosmetics.Rarities[item.Rarity]
		surface.ItemName.Text = string.upper(item.Name)
		surface.ItemInfo.Text = string.upper(rarity and rarity.Name or "") .. "  ·  " .. UITheme.FormatNumber(item.Price or 0)
			.. " MÜNZEN"
		surface.ItemInfo.TextColor3 = rarity and rarity.Color or Color3.new(1, 1, 1)
	end

	local function refresh()
		local offers, day = dailyOffers()
		if day == shownDay then
			return
		end
		shownDay = day
		for _, model in models do
			model.Model:Destroy()
		end
		models = {}
		for index, item in offers do
			local spot = decor:FindFirstChild("ShopDisplay" .. index)
			if spot then
				local model
				if item.Type == "Weapon" then
					model = GunModels.Build("Rifle", item)
					model:ScaleTo(0.7) -- passt drehend in die Vitrine
				else
					local agent = AgentConfig.Get(item.Agent) or AgentConfig.Agents[1]
					model = AgentFigure.Build(agent, item.Primary, item.Accent, nil, agent.Loadout[1])
					model:ScaleTo(0.6)
				end
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
						part.CanQuery = false
					end
				end
				model.Parent = workspace
				-- Waffe um die Mitte ihres Umrisses drehen (nicht um den Griff)
				local box = model:GetBoundingBox()
				table.insert(models, { Model = model, Spot = spot, Agent = item.Type == "Agent",
					Offset = model:GetPivot():ToObjectSpace(box) })
				plaque(index, item)
			end
		end
	end
	refresh()
	local lastCheck = os.clock()
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if t - lastCheck > 60 then
			lastCheck = t
			refresh()
		end
		for i, entry in models do
			local spin = CFrame.Angles(0, t * 0.6 + i, 0)
			if entry.Agent then
				-- Figur steht auf dem Boden der Vitrine
				entry.Model:PivotTo(CFrame.new(entry.Spot.Position + Vector3.new(0, -2.1 + 3 * 0.6, 0)) * spin)
			else
				entry.Model:PivotTo(CFrame.new(entry.Spot.Position) * spin * entry.Offset:Inverse())
			end
		end
	end)
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
	title.TextColor3 = Color3.fromRGB(212, 170, 80)
	title.Text = "EINSATZ-ÜBERSICHT"
	title.Parent = surface
	local list = Instance.new("TextLabel")
	list.Position = UDim2.new(0.06, 0, 0.2, 0)
	list.Size = UDim2.new(0.88, 0, 0.76, 0)
	list.BackgroundTransparency = 1
	list.Font = Enum.Font.Oswald
	list.TextSize = 30
	list.TextColor3 = Color3.fromRGB(228, 231, 235)
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
			countLabel.Font = Enum.Font.Oswald
			countLabel.TextScaled = true
			countLabel.Text = ""
			countLabel.Parent = gateGui
			gateLabels[id] = countLabel
		end
	end

	holoSurface(surface, board)
	for _, countLabel in gateLabels do
		holoSurface(countLabel.Parent, countLabel.Parent.Adornee)
	end

	local function update()
		local ok, counts = pcall(HttpService.JSONDecode, HttpService, ReplicatedStorage:GetAttribute("ModeCounts") or "{}")
		counts = ok and counts or {}
		local lines = {}
		for _, mode in Modes.List do
			if mode.Available then
				local n = counts[mode.Id] or 0
				local color = n > 0 and "#70B270" or "#5E656E"
				table.insert(lines, mode.Name .. '   <font color="' .. color .. '">' .. n .. " Spieler</font>")
			end
		end
		list.Text = table.concat(lines, "\n")
		-- Spielerzahl unter jedem Tor-Schild
		for id, countLabel in gateLabels do
			local n = counts[id] or 0
			countLabel.Text = n > 0 and (n .. " SPIELER") or "FREI"
			countLabel.TextColor3 = n > 0 and Color3.fromRGB(112, 178, 112) or Color3.fromRGB(134, 142, 152)
		end
	end
	update()
	ReplicatedStorage:GetAttributeChangedSignal("ModeCounts"):Connect(update)
end

-- Bestenlisten-Tafeln im Hub (Parts "Leaderboard_<Name>", Daten vom LeaderboardService)
local BOARD_INFO = {
	Elo = { Title = "HÖCHSTE ELO", Color = Color3.fromRGB(212, 170, 80) },
	Kills = { Title = "MEISTE KILLS", Color = Color3.fromRGB(206, 70, 58) },
	Level = { Title = "HÖCHSTES LEVEL", Color = Color3.fromRGB(96, 164, 214) },
	Wins = { Title = "MEISTE SIEGE", Color = Color3.fromRGB(112, 178, 112) },
}
local PLACE_COLORS = { Color3.fromRGB(212, 176, 96), Color3.fromRGB(190, 194, 200), Color3.fromRGB(176, 120, 76) }

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
			-- Holo-Tafel (Attribut "Holo"): durchsichtig, leuchtende Schrift, kaum Hintergrund
			local holo = part:GetAttribute("Holo") == true
			local surface = Instance.new("SurfaceGui")
			surface.Face = Enum.NormalId.Front
			surface.LightInfluence = 0
			surface.Brightness = holo and 2.2 or 1
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 40
			surface.Adornee = part
			surface.Parent = player:WaitForChild("PlayerGui")
			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, 0, 0.13, 0)
			title.BackgroundColor3 = info.Color
			title.BackgroundTransparency = holo and 0.7 or 0.15
			title.BorderSizePixel = 0
			title.Font = Enum.Font.Oswald
			title.TextScaled = true
			title.TextColor3 = holo and Color3.new(1, 1, 1) or Color3.fromRGB(14, 16, 19)
			title.TextStrokeTransparency = holo and 0.6 or 1
			title.Text = info.Title
			title.Parent = surface
			local rows = {}
			for i = 1, 10 do
				local row = Instance.new("Frame")
				row.Position = UDim2.new(0.03, 0, 0.15 + (i - 1) * 0.084, 0)
				row.Size = UDim2.new(0.94, 0, 0.076, 0)
				row.BackgroundColor3 = holo and Color3.fromRGB(60, 130, 170) or Color3.fromRGB(27, 31, 36)
				row.BackgroundTransparency = holo and (i % 2 == 0 and 0.82 or 0.94) or (i % 2 == 0 and 0.4 or 0.75)
				row.BorderSizePixel = 0
				row.Parent = surface
				local function cell(x, w, align, font)
					local label = Instance.new("TextLabel")
					label.Position = UDim2.new(x, 0, 0.08, 0)
					label.Size = UDim2.new(w, 0, 0.84, 0)
					label.BackgroundTransparency = 1
					label.Font = font
					label.TextScaled = true
					label.TextColor3 = holo and Color3.fromRGB(200, 235, 255) or Color3.fromRGB(228, 231, 235)
					label.TextStrokeTransparency = holo and 0.7 or 1
					label.TextXAlignment = align
					label.Text = ""
					label.Parent = row
					return label
				end
				rows[i] = {
					Frame = row,
					Place = cell(0.01, 0.1, Enum.TextXAlignment.Center, Enum.Font.Oswald),
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
					row.Place.TextColor3 = PLACE_COLORS[i] or Color3.fromRGB(134, 142, 152)
					row.Name.Text = entry and tostring(entry.Name) or (i == 1 and "Noch keine Einträge" or "")
					local isMe = entry and entry.UserId == player.UserId
					row.Name.TextColor3 = isMe and Color3.fromRGB(212, 170, 80)
						or (holo and Color3.fromRGB(200, 235, 255) or Color3.fromRGB(228, 231, 235))
					row.Frame.BackgroundColor3 = isMe and Color3.fromRGB(46, 42, 30)
						or (holo and Color3.fromRGB(60, 130, 170) or Color3.fromRGB(27, 31, 36))
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
	task.spawn(buildAgentOfWeek)
	task.spawn(buildShopVitrine)
	rebuild()
	player.AttributeChanged:Connect(function(name)
		if name == "Mode" or name == "Agent" or name == "Equipped" or name == "Owned" or name == "Loadouts"
			or string.sub(name, 1, 3) == "XP_" then
			rebuild()
		end
	end)
	-- Langsam hin und her drehen, Blick in Richtung der Bühnen-Markierung
	RunService.RenderStepped:Connect(function()
		if figure then
			local angle = math.sin(os.clock() * 0.5) * 0.5
			local height = 3 * SCALE -- Figur steht mit den Füßen auf der Bühne
			local base = STAGE_POSITION + Vector3.new(0, height, 0)
			figure:PivotTo(CFrame.lookAt(base, base + STAGE_FACING) * CFrame.Angles(0, angle, 0))
		end
	end)
end

return HubLineup

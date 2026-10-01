-- AgentSelect (ModuleScript, nur Client)
-- Agentenwahl im Drop-Modus vor jeder Runde, aufgebaut wie bei Rogue Company:
--   oben:   Modus, Timer in der Raute, Zeitbalken, Rundenstand als Rauten
--   links:  eigenes Team (Raute + Leiste, "WÄHLT..." bis bestätigt)
--   Mitte:  großer 3D-Agent, der sich langsam dreht
--   rechts: Name, Rolle, Level, Waffen, Fähigkeit
--   unten:  Rollen-Tabs, Agenten-Kacheln, AGENT BESTÄTIGEN
-- Klick auf eine Kachel wählt den Agenten, BESTÄTIGEN sperrt die Wahl für diese Runde.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local GameSettings = require(Shared.GameSettings)
local Cosmetics = require(Shared.Cosmetics)
local AgentFigure = require(Shared.AgentFigure)
local BuyConfig = require(Shared.BuyConfig)

local player = Players.LocalPlayer

local AgentSelect = {}

-- Aufbau für 1600 x 900, wird auf die Bildschirmgröße skaliert
local WIDTH, HEIGHT = 1600, 900
local CYAN = Color3.fromRGB(40, 210, 230)
local RED = Color3.fromRGB(200, 40, 50)
local GOLD = Color3.fromRGB(230, 180, 60)
local GRAY = Color3.fromRGB(170, 175, 190)
local DARK = Color3.fromRGB(14, 18, 26)
local TILE = 84

local gui, canvas
local timerLabel, timeBar, modeLabel, roundLabel, scoreFrame, teamFrame, confirmButton
local viewport, viewportCamera, figure, accent
local infoName, infoRole, infoLevel, infoBar, infoStats, infoWeapons, infoAbility, infoAbilityText
local tiles = {}           -- [agent] = { Button, Stroke }
local buyCards = {}        -- [item] = { Button, State }
local bottomButtons = {}   -- ["Agents"/"Shop"] = Button
local agentArea, shopArea, moneyLabel, buyStatus
local tabButtons = {}      -- [role] = Button
local currentRole = "ALLE"
local previewAgent = nil   -- Agent in der 3D-Ansicht (Maus über Kachel oder gewählter)
local hoverAgent = nil
local confirmed = false
local shown = false
local teamSignature = ""
local scoreSignature = ""

local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function text(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, parent)
end

-- Raute (gedrehtes Quadrat). Kinder würden mitgedreht, darum Texte immer als Geschwister.
local function diamond(parent, size, position, color, strokeColor)
	local d = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.new(0, size, 0, size),
		Rotation = 45,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, parent)
	if strokeColor then
		make("UIStroke", { Color = strokeColor, Thickness = 2 }, d)
	end
	return d
end

local function myAgent()
	return AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
end

local function isLocked()
	return player:GetAttribute("AgentLocked") == true
end

-- ---------- 3D-Figur ----------

local function buildFigure(agent)
	local primary, accent = Cosmetics.AgentColors(player, agent.Id)
	return AgentFigure.Build(agent, primary, accent, Cosmetics.WeaponSkin(player, agent.Id, agent.Loadout[1]))
end

local function showPreview(agent)
	if agent == previewAgent then
		return
	end
	previewAgent = agent
	if figure then
		figure:Destroy()
	end
	figure = buildFigure(agent)
	figure.Parent = viewport
	accent.BackgroundColor3 = agent.Color

	-- Info rechts
	local xp = AgentConfig.GetXP(player, agent.Id)
	infoName.Text = agent.Name
	infoName.TextColor3 = agent.Color
	infoRole.Text = string.upper(agent.Role)
	infoLevel.Text = "LEVEL " .. AgentConfig.LevelFromXP(xp)
	infoBar.Size = UDim2.new(AgentConfig.LevelProgress(xp), 0, 1, 0)
	infoBar.BackgroundColor3 = agent.Color
	infoStats.Text = "♥ " .. agent.Health .. "      TEMPO " .. agent.WalkSpeed
	local weapons = {}
	for _, weapon in agent.Loadout do
		table.insert(weapons, WeaponConfig.Get(weapon).DisplayName)
	end
	infoWeapons.Text = table.concat(weapons, "  ·  ")
	infoAbility.Text = AgentConfig.AbilityKey.Name .. "   " .. string.upper(agent.Ability.Name)
	infoAbility.TextColor3 = agent.Color
	infoAbilityText.Text = agent.Ability.Description .. "\nAbklingzeit " .. agent.Ability.Cooldown .. " s"
end

-- ---------- Aufbau ----------

local function buildTop()
	-- Zeitbalken ganz oben
	local barBack = make("Frame", { Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = Color3.fromRGB(60, 65, 75), BorderSizePixel = 0 }, canvas)
	timeBar = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = CYAN, BorderSizePixel = 0 }, barBack)

	modeLabel = text({ Position = UDim2.new(0, 40, 0, 40), Size = UDim2.new(0, 400, 0, 28), Text = "DROP",
		TextSize = 24, TextColor3 = GRAY }, canvas)
	roundLabel = text({ Position = UDim2.new(0, 40, 0, 70), Size = UDim2.new(0, 400, 0, 26), Text = "",
		TextSize = 20, TextColor3 = GRAY }, canvas)

	-- Timer in der Raute
	diamond(canvas, 78, UDim2.new(0.5, 0, 0, 80), Color3.fromRGB(16, 50, 70), CYAN)
	timerLabel = text({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.new(0, 110, 0, 60), Text = "", TextSize = 46, Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)

	-- Rundenstand oben rechts (wird in updateScore gefüllt)
	scoreFrame = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 40),
		Size = UDim2.new(0, 360, 0, 80), BackgroundTransparency = 1 }, canvas)
end

local function buildCenter()
	-- Farbige Raute hinter dem Agenten
	accent = diamond(canvas, 380, UDim2.new(0.5, 0, 0, 390), CYAN)
	accent.BackgroundTransparency = 0.88

	viewport = make("ViewportFrame", { ZIndex = 2, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.new(0, 560, 0, 540), BackgroundTransparency = 1, Ambient = Color3.fromRGB(120, 125, 140),
		LightColor = Color3.fromRGB(255, 240, 230), LightDirection = Vector3.new(-0.4, -1, 0.7) }, canvas)
	viewportCamera = make("Camera", { FieldOfView = 38 }, viewport)
	viewportCamera.CFrame = AgentFigure.CameraCFrame
	viewport.CurrentCamera = viewportCamera
end

local function buildInfo()
	local x = WIDTH - 420
	infoName = text({ Position = UDim2.new(0, x, 0, 190), Size = UDim2.new(0, 380, 0, 70), Text = "",
		TextSize = 64, Font = Enum.Font.GothamBlack }, canvas)
	infoRole = text({ Position = UDim2.new(0, x, 0, 258), Size = UDim2.new(0, 380, 0, 26), Text = "",
		TextSize = 20, TextColor3 = GRAY }, canvas)
	infoLevel = text({ Position = UDim2.new(0, x, 0, 296), Size = UDim2.new(0, 380, 0, 22), Text = "",
		TextSize = 17, TextColor3 = GOLD }, canvas)
	local barBack = make("Frame", { Position = UDim2.new(0, x, 0, 322), Size = UDim2.new(0, 300, 0, 6),
		BackgroundColor3 = Color3.fromRGB(50, 55, 68), BorderSizePixel = 0 }, canvas)
	infoBar = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, barBack)
	infoStats = text({ Position = UDim2.new(0, x, 0, 344), Size = UDim2.new(0, 380, 0, 24), Text = "",
		TextSize = 18 }, canvas)
	infoWeapons = text({ Position = UDim2.new(0, x, 0, 372), Size = UDim2.new(0, 380, 0, 24), Text = "",
		TextSize = 17, Font = Enum.Font.Gotham, TextColor3 = GRAY }, canvas)
	make("Frame", { Position = UDim2.new(0, x, 0, 410), Size = UDim2.new(0, 340, 0, 1),
		BackgroundColor3 = Color3.fromRGB(60, 65, 80), BorderSizePixel = 0 }, canvas)
	infoAbility = text({ Position = UDim2.new(0, x, 0, 424), Size = UDim2.new(0, 380, 0, 26), Text = "",
		TextSize = 20 }, canvas)
	infoAbilityText = text({ Position = UDim2.new(0, x, 0, 454), Size = UDim2.new(0, 340, 0, 90), Text = "",
		TextSize = 16, Font = Enum.Font.Gotham, TextColor3 = GRAY, TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top }, canvas)
end

local function refreshTiles()
	local chosen = myAgent()
	for agent, entry in tiles do
		entry.Button.Visible = currentRole == "ALLE" or string.upper(agent.Role) == currentRole
		entry.Stroke.Color = agent == chosen and RED or Color3.fromRGB(60, 65, 80)
		entry.Stroke.Thickness = agent == chosen and 3 or 1
		entry.Level.Text = tostring(AgentConfig.LevelFromXP(AgentConfig.GetXP(player, agent.Id)))
	end
	for role, button in tabButtons do
		button.BackgroundColor3 = role == currentRole and RED or Color3.fromRGB(18, 20, 28)
	end
end

local function buildBottom()
	local barWidth = 1060
	-- Rollen-Tabs
	local roles = { "ALLE" }
	for _, agent in AgentConfig.Agents do
		local role = string.upper(agent.Role)
		if not table.find(roles, role) then
			table.insert(roles, role)
		end
	end
	local tabs = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 670),
		Size = UDim2.new(0, barWidth, 0, 32), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BorderSizePixel = 0 }, canvas)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for i, role in roles do
		local tab = make("TextButton", { Size = UDim2.new(1 / #roles, 0, 1, 0), BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(18, 20, 28), Font = Enum.Font.GothamBold, TextSize = 14,
			TextColor3 = Color3.new(1, 1, 1), Text = role, LayoutOrder = i, AutoButtonColor = false }, tabs)
		tab.Activated:Connect(function()
			currentRole = role
			refreshTiles()
		end)
		tabButtons[role] = tab
	end

	-- Agenten-Kacheln
	local grid = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 712),
		Size = UDim2.new(0, barWidth, 0, TILE), BackgroundTransparency = 1 }, canvas)
	make("UIGridLayout", { CellSize = UDim2.new(0, TILE, 0, TILE), CellPadding = UDim2.new(0, 8, 0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, agent in AgentConfig.Agents do
		local tile = make("TextButton", { BackgroundColor3 = agent.Color:Lerp(Color3.new(0, 0, 0), 0.45),
			BorderSizePixel = 0, Text = "", AutoButtonColor = true, LayoutOrder = i }, grid)
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(90, 90, 90)) }, tile)
		local stroke = make("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tile)
		text({ Size = UDim2.new(1, 0, 0.75, 0), Text = string.sub(agent.Name, 1, 1), TextSize = 44,
			Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center }, tile)
		text({ Position = UDim2.new(0, 0, 0.72, 0), Size = UDim2.new(1, 0, 0.26, 0), Text = agent.Name,
			TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center }, tile)
		-- Level-Raute oben rechts
		diamond(tile, 16, UDim2.new(1, -11, 0, 11), GOLD)
		local level = text({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -11, 0, 11),
			Size = UDim2.new(0, 22, 0, 22), Text = "", TextSize = 11, Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.fromRGB(20, 20, 20), TextXAlignment = Enum.TextXAlignment.Center }, tile)

		tile.MouseEnter:Connect(function()
			hoverAgent = agent
		end)
		tile.MouseLeave:Connect(function()
			if hoverAgent == agent then
				hoverAgent = nil
			end
		end)
		tile.Activated:Connect(function()
			if not isLocked() then
				Remotes.SelectAgent:FireServer(agent.Id, false)
			end
		end)
		tiles[agent] = { Button = tile, Stroke = stroke, Level = level }
	end

	-- Bereich AGENTEN (Tabs + Kacheln) und Bereich AUSRÜSTUNG (Kaufphase), umschaltbar
	agentArea = { tabs, grid }
	shopArea = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 670),
		Size = UDim2.new(0, barWidth, 0, 130), BackgroundTransparency = 1, Visible = false }, canvas)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 15),
		SortOrder = Enum.SortOrder.LayoutOrder }, shopArea)
	for i, item in BuyConfig.Items do
		local card = make("TextButton", { Size = UDim2.new(0, 200, 1, 0), BackgroundColor3 = Color3.fromRGB(18, 22, 32),
			BorderSizePixel = 0, Text = "", AutoButtonColor = true, LayoutOrder = i }, shopArea)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, card)
		make("UIStroke", { Color = Color3.fromRGB(60, 65, 80), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
		text({ Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -24, 0, 22), Text = item.Name, TextSize = 17 }, card)
		text({ Position = UDim2.new(0, 12, 0, 34), Size = UDim2.new(1, -24, 0, 44), Text = item.Description,
			TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = GRAY, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top }, card)
		local state = text({ Position = UDim2.new(0, 12, 1, -36), Size = UDim2.new(1, -24, 0, 26), Text = "",
			TextSize = 17, Font = Enum.Font.GothamBlack }, card)
		card.Activated:Connect(function()
			Remotes.Buy:FireServer(item.Id)
		end)
		buyCards[item] = { Button = card, State = state }
	end

	local function showBottom(name)
		for _, part in agentArea do
			part.Visible = name == "Agents"
		end
		shopArea.Visible = name == "Shop"
		for buttonName, b in bottomButtons do
			b.BackgroundColor3 = buttonName == name and CYAN or Color3.fromRGB(18, 22, 32)
			b.TextColor3 = buttonName == name and Color3.fromRGB(10, 20, 30) or Color3.new(1, 1, 1)
		end
	end
	for i, entry in { { "Agents", "AGENTEN" }, { "Shop", "AUSRÜSTUNG" } } do
		local b = make("TextButton", { Position = UDim2.new(0.5, -530 + (i - 1) * 180, 0, 626), Size = UDim2.new(0, 170, 0, 34),
			BorderSizePixel = 0, Font = Enum.Font.GothamBlack, TextSize = 15, Text = entry[2], ZIndex = 3 }, canvas)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		b.Activated:Connect(function()
			showBottom(entry[1])
		end)
		bottomButtons[entry[1]] = b
	end
	buyStatus = text({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 90, 0, 632), Size = UDim2.new(0, 400, 0, 22),
		Text = "", TextSize = 15, TextColor3 = GRAY, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, canvas)
	moneyLabel = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.5, 530, 0, 626), Size = UDim2.new(0, 220, 0, 34),
		Text = "", TextSize = 24, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(120, 230, 140),
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 }, canvas)
	showBottom("Agents")

	confirmButton = make("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 822),
		Size = UDim2.new(0, 320, 0, 50), BackgroundColor3 = RED, BorderSizePixel = 0, Font = Enum.Font.GothamBlack,
		TextSize = 22, TextColor3 = Color3.new(1, 1, 1), Text = "AGENT BESTÄTIGEN" }, canvas)
	confirmButton.Activated:Connect(function()
		if not isLocked() then
			Remotes.SelectAgent:FireServer(myAgent().Id, true)
		end
		confirmed = true
	end)
end

local function build()
	gui = make("ScreenGui", { Name = "AgentSelect", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 5, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	-- Halbtransparent: dahinter fliegt die Kamera langsam über die Map.
	-- Oben und unten etwas dunkler, damit die Texte lesbar bleiben.
	local background = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(10, 20, 35),
		BackgroundTransparency = 0.35, Active = true }, gui)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.25, 0.75),
		NumberSequenceKeypoint.new(0.7, 0.75),
		NumberSequenceKeypoint.new(1, 0.05),
	}) }, background)

	canvas = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, WIDTH, 0, HEIGHT), BackgroundTransparency = 1 }, background)
	local scale = make("UIScale", {}, canvas)
	local function updateScale()
		local viewportSize = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(viewportSize.X / WIDTH, viewportSize.Y / HEIGHT)
	end
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	buildTop()
	buildCenter()
	buildInfo()
	buildBottom()
	teamFrame = make("Frame", { Position = UDim2.new(0, 30, 0, 160), Size = UDim2.new(0, 470, 0, 500),
		BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, teamFrame)
end

-- ---------- Team links ----------

-- Spieler und Bots im eigenen Team: { Name, Agent, Locked, IsMe, IsBot }
local function teamEntries()
	local list = {}
	if not player.Team then
		return list
	end
	for _, p in Players:GetPlayers() do
		if p.Team == player.Team and p:GetAttribute("Mode") == "Drop" then
			table.insert(list, { Name = p.Name, Agent = AgentConfig.Get(p:GetAttribute("Agent")),
				Locked = p:GetAttribute("AgentLocked") == true, IsMe = p == player })
		end
	end
	for _, info in ReplicatedStorage:WaitForChild("BotInfo"):GetChildren() do
		if info:GetAttribute("Mode") == "Drop" and info:GetAttribute("TeamName") == player.Team.Name then
			table.insert(list, { Name = info.Name, Agent = AgentConfig.Get(info:GetAttribute("Agent")),
				Locked = true, IsBot = true })
		end
	end
	return list
end

local function updateTeam()
	local entries = teamEntries()
	local parts = {}
	for _, e in entries do
		table.insert(parts, e.Name .. tostring(e.Agent and e.Agent.Id) .. tostring(e.Locked))
	end
	local signature = table.concat(parts, "|")
	if signature == teamSignature then
		return
	end
	teamSignature = signature

	for _, child in teamFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, e in entries do
		local rowFrame = make("Frame", { Size = UDim2.new(0, 470, 0, 82), BackgroundTransparency = 1, LayoutOrder = i },
			teamFrame)
		local indent = (i % 2 == 0) and 50 or 0 -- versetzt wie im Original
		-- Leiste mit Verlauf
		local bar = make("Frame", { Position = UDim2.new(0, 70 + indent, 0.5, -28), Size = UDim2.new(0, 320, 0, 56),
			BackgroundColor3 = Color3.fromRGB(20, 120, 150), BorderSizePixel = 0 }, rowFrame)
		make("UIGradient", { Transparency = NumberSequence.new(0.1, 0.9) }, bar)
		-- Raute mit Agent oder leer
		local color = (e.Locked and e.Agent) and e.Agent.Color:Lerp(Color3.new(0, 0, 0), 0.3) or Color3.new(0, 0, 0)
		diamond(rowFrame, 56, UDim2.new(0, 55 + indent, 0.5, 0), color, e.IsMe and GOLD or CYAN)
		text({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 55 + indent, 0.5, 0),
			Size = UDim2.new(0, 50, 0, 50), Text = (e.Locked and e.Agent) and string.sub(e.Agent.Name, 1, 1) or "",
			TextSize = 30, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center }, rowFrame)
		-- Texte
		local textX = 110 + indent
		if not e.Locked then
			text({ Position = UDim2.new(0, textX, 0.5, -32), Size = UDim2.new(0, 260, 0, 16), Text = "WÄHLT...",
				TextSize = 13, TextColor3 = GRAY }, rowFrame)
		end
		text({ Position = UDim2.new(0, textX, 0.5, -16), Size = UDim2.new(0, 260, 0, 22),
			Text = e.Name .. (e.IsBot and "  [BOT]" or ""), TextSize = 18,
			TextColor3 = e.IsMe and GOLD or Color3.new(1, 1, 1) }, rowFrame)
		if e.Locked and e.Agent then
			text({ Position = UDim2.new(0, textX, 0.5, 6), Size = UDim2.new(0, 260, 0, 22), Text = "✕ " .. e.Agent.Name,
				TextSize = 18, Font = Enum.Font.GothamBlack, TextColor3 = e.Agent.Color }, rowFrame)
		end
	end
end

-- ---------- Rundenstand oben rechts ----------

local function updateScore()
	local total = GameSettings.Get("RoundsToWin")
	local ours, theirs = 0, 0
	if player.Team then
		local enemyName = player.Team.Name == "Rot" and "Blau" or "Rot"
		ours = ReplicatedStorage:GetAttribute("DropScore" .. player.Team.Name) or 0
		theirs = ReplicatedStorage:GetAttribute("DropScore" .. enemyName) or 0
	end
	local signature = total .. ":" .. ours .. ":" .. theirs
	if signature == scoreSignature then
		return
	end
	scoreSignature = signature
	scoreFrame:ClearAllChildren()
	for rowIndex, data in { { ours, CYAN, "WIR" }, { theirs, RED, "GEGNER" } } do
		local y = (rowIndex - 1) * 38 + 16
		text({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(total * 34 + 10), 0, y),
			Size = UDim2.new(0, 80, 0, 20), Text = data[3], TextSize = 13, TextColor3 = GRAY,
			TextXAlignment = Enum.TextXAlignment.Right }, scoreFrame)
		for i = 1, total do
			local won = i <= data[1]
			local x = -(total - i) * 34 - 14
			diamond(scoreFrame, 20, UDim2.new(1, x, 0, y), won and data[2] or Color3.fromRGB(20, 24, 32), data[2])
			if won then
				text({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, x, 0, y), Size = UDim2.new(0, 20, 0, 20),
					Text = "✓", TextSize = 14, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center },
					scoreFrame)
			end
		end
	end
end

-- ---------- Laufende Aktualisierung ----------

local function setMouseFree(free)
	if free then
		RunService:BindToRenderStep("AgentSelectMouse", Enum.RenderPriority.Camera.Value + 1, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	else
		RunService:UnbindFromRenderStep("AgentSelectMouse")
	end
end

local function update()
	local phase = player:GetAttribute("DropPhase")
	local inDrop = player:GetAttribute("Mode") == "Drop"
	local show = inDrop and (phase == "Waiting" or phase == "Select" or not confirmed)
	gui.Enabled = show
	if show ~= shown then
		shown = show
		setMouseFree(show)
	end
	if not show then
		return
	end

	-- Timer und Zeitbalken
	if phase == "Select" then
		local duration = ReplicatedStorage:GetAttribute("DropSelectDuration") or 1
		local left = math.max(0, (ReplicatedStorage:GetAttribute("DropSelectUntil") or 0) - workspace:GetServerTimeNow())
		timerLabel.Text = tostring(math.ceil(left))
		timeBar.Size = UDim2.new(math.clamp(left / duration, 0, 1), 0, 1, 0)
	else
		timerLabel.Text = "–"
		timeBar.Size = UDim2.new(1, 0, 1, 0)
	end
	modeLabel.Text = "DROP  ·  5v5"
	if phase == "Waiting" then
		roundLabel.Text = player:GetAttribute("ModeText") or "Warte auf Spieler..."
	elseif phase == "Select" then
		roundLabel.Text = "RUNDE " .. (ReplicatedStorage:GetAttribute("DropRound") or 1) .. "  ·  AGENTENWAHL"
	else
		roundLabel.Text = "Runde läuft – du steigst in der nächsten Runde ein"
	end

	-- Bestätigen-Knopf
	if isLocked() then
		confirmButton.Text = "BESTÄTIGT ✓"
		confirmButton.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
	elseif phase == "Select" or phase == "Waiting" then
		confirmButton.Text = "AGENT BESTÄTIGEN"
		confirmButton.BackgroundColor3 = RED
	else
		confirmButton.Text = "BESTÄTIGEN & ZUSCHAUEN"
		confirmButton.BackgroundColor3 = RED
	end

	-- Kaufphase: Geld und Kartenzustand
	local money = player:GetAttribute("Money")
	moneyLabel.Text = money and ("💵 " .. money .. " $") or ""
	local canBuy = phase == "Select" or phase == "Countdown"
	for item, entry in buyCards do
		if BuyConfig.Has(player, item.Id) then
			entry.State.Text = "GEKAUFT ✓"
			entry.State.TextColor3 = Color3.fromRGB(120, 230, 140)
		elseif not canBuy or money == nil then
			entry.State.Text = item.Price .. " $  ·  vor der Runde"
			entry.State.TextColor3 = GRAY
		else
			entry.State.Text = item.Price .. " $"
			entry.State.TextColor3 = money >= item.Price and Color3.new(1, 1, 1) or Color3.fromRGB(255, 110, 110)
		end
	end

	showPreview(hoverAgent or myAgent())
	refreshTiles()
	updateTeam()
	updateScore()
end

function AgentSelect.Init()
	build()

	-- Rückmeldung beim Kaufen
	Remotes.ShopStatus.OnClientEvent:Connect(function(message, success)
		buyStatus.Text = message
		buyStatus.TextColor3 = success and Color3.fromRGB(120, 230, 140) or Color3.fromRGB(255, 120, 120)
	end)

	-- Neu im Drop: erst wählen
	player:GetAttributeChangedSignal("Mode"):Connect(function()
		confirmed = false
	end)
	player:GetAttributeChangedSignal("DropPhase"):Connect(function()
		local phase = player:GetAttribute("DropPhase")
		if phase == "Countdown" then
			confirmed = true -- Match startet: Bildschirm schließt
		elseif phase == "Waiting" or phase == "Select" then
			confirmed = false
		end
	end)
	-- Level/XP geändert: 3D-Figur und Info neu aufbauen
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 3) == "XP_" or name == "Equipped" or name == "Owned" then
			previewAgent = nil
		end
	end)

	-- Figur langsam hin und her drehen
	RunService.RenderStepped:Connect(function()
		if shown and figure then
			local angle = math.sin(os.clock() * 0.6) * 0.45 + 0.3
			figure:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, angle, 0))
		end
	end)

	task.spawn(function()
		while true do
			update()
			task.wait(0.1)
		end
	end)
end

return AgentSelect

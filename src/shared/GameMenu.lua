-- GameMenu (ModuleScript, nur Client)
-- Hauptmenü mit zwei Tabs: SPIELMODI (Teleport) und AGENTEN (Auswahl). Öffnen/Schließen mit M.
-- Im Hub öffnet es sich beim Betreten, in den Modi gibt es zusätzlich "Zurück zum Hub".
-- Ob man im Hub ist, kommt live vom Server (Spieler-Attribut "Mode").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)
local WeaponConfig = require(Shared.WeaponConfig)

local player = Players.LocalPlayer

local GameMenu = {}

local ACCENT = Color3.fromRGB(255, 140, 40)
local BACKGROUND = Color3.fromRGB(10, 12, 18)
local CARD = Color3.fromRGB(24, 27, 36)
local CARD_BORDER = Color3.fromRGB(50, 55, 70)
local GRAY = Color3.fromRGB(170, 175, 190)
local BUTTON = Color3.fromRGB(40, 44, 58)

local CARD_WIDTH = 250
local CARD_HEIGHT = 340
local CARD_GAP = 20

local overlay, subtitle, statusLabel, playButton, openButton, hubButton, closeButton
local currentTab = "Modes"
local modePage, agentPage
local tabButtons = {}
local modeCards = {} -- [mode] = Karte
local agentCards = {} -- [agent] = Karte
local selectedMode
local isOpen = false
local inHub = false

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

local function button(props, parent)
	props.Font = Enum.Font.GothamBlack
	props.AutoButtonColor = true
	props.BorderSizePixel = 0
	local b = make("TextButton", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	return b
end

local function setStatus(message)
	statusLabel.Text = message
end

-- Zeile mit Karten (für beide Tabs)
local function makeRow(count)
	local row = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.53, 0),
		Size = UDim2.new(0, count * CARD_WIDTH + (count - 1) * CARD_GAP, 0, CARD_HEIGHT),
		BackgroundTransparency = 1,
	}, overlay)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, CARD_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	return row
end

-- Leere Karte mit Farbstreifen, Rahmen und Titel
local function makeCard(parent, order, color, title, tag, faded)
	local card = make("TextButton", {
		Size = UDim2.new(0, CARD_WIDTH, 0, CARD_HEIGHT),
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
	make("UIStroke", { Color = CARD_BORDER, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	local stripe = make("Frame", {
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = color,
		BackgroundTransparency = faded and 0.6 or 0,
		BorderSizePixel = 0,
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, stripe)

	local transparency = faded and 0.45 or 0
	text({
		Position = UDim2.new(0, 18, 0, 30),
		Size = UDim2.new(1, -36, 0, 40),
		Text = title,
		Font = Enum.Font.GothamBlack,
		TextSize = 28,
		TextTransparency = transparency,
	}, card)
	text({
		Position = UDim2.new(0, 18, 0, 72),
		Size = UDim2.new(1, -36, 0, 22),
		Text = string.upper(tag),
		TextSize = 15,
		TextColor3 = color,
		TextTransparency = transparency,
	}, card)
	return card, transparency
end

local function bodyText(card, y, height, message, transparency, color)
	return text({
		Position = UDim2.new(0, 18, 0, y),
		Size = UDim2.new(1, -36, 0, height),
		Text = message,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextColor3 = color or GRAY,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextTransparency = transparency or 0,
	}, card)
end

local function badge(card, label, good)
	local b = text({
		Position = UDim2.new(0, 18, 1, -46),
		Size = UDim2.new(0, 130, 0, 28),
		Text = label,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = good and Color3.fromRGB(20, 20, 20) or GRAY,
	}, card)
	b.BackgroundTransparency = 0
	b.BackgroundColor3 = good and Color3.fromRGB(110, 220, 120) or Color3.fromRGB(55, 58, 70)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	return b
end

local function highlight(cards, chosen)
	for item, card in cards do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		stroke.Color = item == chosen and ACCENT or CARD_BORDER
		stroke.Thickness = item == chosen and 3 or 1
	end
end

-- ---------- Tab SPIELMODI ----------

local function selectMode(mode)
	selectedMode = mode
	highlight(modeCards, mode)
	if mode.Available then
		playButton.Text = "SPIELEN  ·  " .. mode.Name
		playButton.BackgroundColor3 = ACCENT
	else
		playButton.Text = "BALD VERFÜGBAR"
		playButton.BackgroundColor3 = Color3.fromRGB(60, 62, 72)
	end
end

local function buildModePage()
	modePage = makeRow(#Modes.List)
	for i, mode in Modes.List do
		local card, transparency = makeCard(modePage, i, mode.Color, mode.Name, mode.Tag, not mode.Available)
		bodyText(card, 110, 120, mode.Description, transparency)
		bodyText(card, CARD_HEIGHT - 78, 22, mode.Players, transparency)
		badge(card, mode.Available and "VERFÜGBAR" or "BALD", mode.Available)
		card.Activated:Connect(function()
			selectMode(mode)
		end)
		modeCards[mode] = card
	end
end

-- ---------- Tab AGENTEN ----------

local function currentAgent()
	return AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
end

local function buildAgentPage()
	agentPage = makeRow(#AgentConfig.Agents)
	agentPage.Visible = false
	for i, agent in AgentConfig.Agents do
		local ability = agent.Ability
		local card = makeCard(agentPage, i, agent.Color, agent.Name, agent.Role, false)
		bodyText(card, 100, 22, "♥ " .. agent.Health .. "   ·   Tempo " .. agent.WalkSpeed, 0, Color3.new(1, 1, 1))
		bodyText(card, 128, 44, agent.Description)
		make("Frame", {
			Position = UDim2.new(0, 18, 0, 182),
			Size = UDim2.new(1, -36, 0, 1),
			BackgroundColor3 = CARD_BORDER,
			BorderSizePixel = 0,
		}, card)
		text({
			Position = UDim2.new(0, 18, 0, 192),
			Size = UDim2.new(1, -36, 0, 24),
			Text = AgentConfig.AbilityKey.Name .. "  ·  " .. string.upper(ability.Name),
			TextSize = 17,
			TextColor3 = agent.Color,
		}, card)
		bodyText(card, 220, 44, ability.Description .. "  (" .. ability.Cooldown .. " s)")
		local weapons = {}
		for _, weapon in agent.Loadout do
			table.insert(weapons, WeaponConfig.Get(weapon).DisplayName)
		end
		bodyText(card, 266, 20, table.concat(weapons, " + "), 0, Color3.new(1, 1, 1))

		-- Level und XP-Balken
		local levelLabel = text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, 30),
			Size = UDim2.new(0, 80, 0, 40),
			Text = "",
			TextSize = 18,
			TextColor3 = ACCENT,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, card)
		local barBack = make("Frame", {
			Position = UDim2.new(0, 18, 1, -58),
			Size = UDim2.new(1, -36, 0, 5),
			BackgroundColor3 = CARD_BORDER,
			BorderSizePixel = 0,
		}, card)
		local bar = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = agent.Color, BorderSizePixel = 0 }, barBack)
		local tag = badge(card, "WÄHLEN", false)
		card.Activated:Connect(function()
			Remotes.SelectAgent:FireServer(agent.Id)
			setStatus(agent.Name .. " gewählt. Aktiv ab dem nächsten Spawn.")
		end)
		agentCards[agent] = { Card = card, Badge = tag, Level = levelLabel, Bar = bar }
	end

	-- Auswahl hervorheben, sobald der Server sie bestätigt
	local function refresh()
		local chosen = currentAgent()
		for agent, entry in agentCards do
			local isChosen = agent == chosen
			local stroke = entry.Card:FindFirstChildOfClass("UIStroke")
			stroke.Color = isChosen and ACCENT or CARD_BORDER
			stroke.Thickness = isChosen and 3 or 1
			entry.Badge.Text = isChosen and "GEWÄHLT" or "WÄHLEN"
			entry.Badge.BackgroundColor3 = isChosen and Color3.fromRGB(110, 220, 120) or Color3.fromRGB(55, 58, 70)
			entry.Badge.TextColor3 = isChosen and Color3.fromRGB(20, 20, 20) or GRAY
			local xp = AgentConfig.GetXP(player, agent.Id)
			entry.Level.Text = "Lv " .. AgentConfig.LevelFromXP(xp)
			entry.Bar.Size = UDim2.new(AgentConfig.LevelProgress(xp), 0, 1, 0)
		end
	end
	refresh()
	player.AttributeChanged:Connect(refresh) -- Agent oder XP geändert
end

-- ---------- Tabs ----------

local function showTab(name)
	currentTab = name
	modePage.Visible = name == "Modes"
	agentPage.Visible = name == "Agents"
	playButton.Visible = name == "Modes"
	subtitle.Text = (inHub and "HUB" or "MENÜ") .. "  ·  " .. (name == "Modes" and "SPIELMODUS WÄHLEN" or "AGENT WÄHLEN")
	for tabName, b in tabButtons do
		local active = tabName == name
		b.TextColor3 = active and ACCENT or GRAY
		b:FindFirstChild("Underline").Visible = active
	end
	setStatus("")
end

local function makeTab(name, label, x)
	local b = make("TextButton", {
		Position = UDim2.new(0, x, 0, 160),
		Size = UDim2.new(0, 170, 0, 40),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		Text = label,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, overlay)
	make("Frame", {
		Name = "Underline",
		Position = UDim2.new(0, 0, 1, -3),
		Size = UDim2.new(0, 120, 0, 3),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
	}, b)
	b.Activated:Connect(function()
		showTab(name)
	end)
	tabButtons[name] = b
end

-- Menü öffnen/schließen. Solange offen, ist die Maus frei (auch in First Person).
function GameMenu.SetOpen(open: boolean)
	isOpen = open
	overlay.Visible = open
	openButton.Visible = inHub and not open
	if open then
		RunService:BindToRenderStep("GameMenuMouse", Enum.RenderPriority.Camera.Value + 1, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	else
		RunService:UnbindFromRenderStep("GameMenuMouse")
	end
end

-- Menü öffnen und direkt einen Tab zeigen ("Modes" oder "Agents")
function GameMenu.Open(tab)
	GameMenu.SetOpen(true)
	showTab(tab or "Modes")
end

function GameMenu.IsOpen()
	return isOpen
end

function GameMenu.Init()

	local gui = make("ScreenGui", {
		Name = "GameMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	overlay = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = BACKGROUND,
		BackgroundTransparency = 0.08,
		Active = true, -- schluckt Klicks, damit im Menü nicht geschossen wird
		Visible = false,
	}, gui)

	-- Alles mitskalieren, damit es auch auf kleinen Bildschirmen passt
	local scale = make("UIScale", {}, overlay)
	local function updateScale()
		local viewport = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / 1250, viewport.Y / 800), 0.45, 1.2)
	end
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	-- Kopfzeile
	text({
		Position = UDim2.new(0, 60, 0, 40),
		Size = UDim2.new(0, 600, 0, 64),
		Text = "SHOOTOUT",
		Font = Enum.Font.GothamBlack,
		TextSize = 60,
		TextColor3 = ACCENT,
	}, overlay)
	subtitle = text({
		Position = UDim2.new(0, 62, 0, 104),
		Size = UDim2.new(0, 600, 0, 28),
		Text = "",
		TextSize = 20,
		TextColor3 = GRAY,
	}, overlay)
	text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -60, 0, 56),
		Size = UDim2.new(0, 300, 0, 24),
		Text = "M  =  Menü     Q  =  Fähigkeit",
		TextSize = 18,
		TextColor3 = GRAY,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, overlay)

	-- Untere Leiste
	statusLabel = text({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -60, 1, -135),
		Size = UDim2.new(0, 700, 0, 26),
		Text = "",
		TextSize = 18,
		TextColor3 = GRAY,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, overlay)

	playButton = button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -60, 1, -50),
		Size = UDim2.new(0, 380, 0, 72),
		TextSize = 26,
		TextColor3 = Color3.fromRGB(20, 20, 20),
		Text = "",
	}, overlay)
	playButton.Activated:Connect(function()
		if selectedMode.Available then
			setStatus("Suche Server für " .. selectedMode.Name .. "...")
			Remotes.JoinMode:FireServer(selectedMode.Id)
		else
			setStatus(selectedMode.Name .. " kommt bald.")
		end
	end)

	hubButton = button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 60, 1, -58),
		Size = UDim2.new(0, 260, 0, 56),
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = BUTTON,
		Text = "ZURÜCK ZUM HUB",
	}, overlay)
	hubButton.Activated:Connect(function()
		setStatus("Zurück zum Hub...")
		Remotes.JoinMode:FireServer(Modes.Hub.Id)
	end)

	closeButton = button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 340, 1, -58),
		Size = UDim2.new(0, 220, 0, 56),
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = BUTTON,
		Text = "",
	}, overlay)
	closeButton.Activated:Connect(function()
		GameMenu.SetOpen(false)
	end)

	-- Seiten und Tabs
	buildModePage()
	buildAgentPage()
	makeTab("Modes", "SPIELMODI", 60)
	makeTab("Agents", "AGENTEN", 240)
	selectMode(Modes.List[1])
	showTab("Modes")

	-- Im Hub: Knopf unten mittig, um das Menü wieder zu öffnen
	openButton = button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.new(0, 260, 0, 56),
		TextSize = 22,
		TextColor3 = Color3.fromRGB(20, 20, 20),
		BackgroundColor3 = ACCENT,
		Text = "SPIELEN  (M)",
		Visible = false,
	}, gui)
	openButton.Activated:Connect(function()
		GameMenu.SetOpen(true)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.M then
			GameMenu.SetOpen(not isOpen)
		end
	end)

	-- Meldungen vom Server (Teleport läuft, Fehler, Portal betreten) -> Menü zeigen
	Remotes.MenuStatus.OnClientEvent:Connect(function(message)
		if not isOpen then
			GameMenu.SetOpen(true)
		end
		showTab("Modes")
		setStatus(message)
	end)

	-- Moduswechsel: im Hub Menü öffnen, beim Betreten eines Modus schließen
	local function onModeChanged()
		local mode = player:GetAttribute("Mode")
		if mode == nil then
			return -- Server hat uns noch keinen Modus gegeben
		end
		inHub = mode == Modes.Hub.Id
		hubButton.Visible = not inHub
		closeButton.Position = UDim2.new(0, inHub and 60 or 340, 1, -58)
		closeButton.Text = inHub and "IM HUB BLEIBEN" or "WEITERSPIELEN"
		showTab(currentTab)
		GameMenu.SetOpen(inHub)
	end
	player:GetAttributeChangedSignal("Mode"):Connect(onModeChanged)
	onModeChanged()
end

return GameMenu

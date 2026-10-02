-- AgentSelect (ModuleScript, nur Client)
-- Agenten- und Ausrüstungswahl in den Team-Modi, aufgebaut wie bei Rogue Company, im Hangar eines
-- Raumschiffs (HangarScene):
--   oben:   Modus, Timer in der Raute, Zeitbalken, Rundenstand als Rauten
--   links:  eigenes Team ("WÄHLT..." bis bestätigt), darunter Name, Rolle, Level, Werte und Fähigkeit
--   Mitte:  großer 3D-Agent auf der Plattform; hält die gewählte (bzw. überfahrene) Primärwaffe
--   rechts: WAFFEN – Primärwaffen zur Wahl mit 3D-Vorschau und Sekundärwaffe –, direkt darunter
--           AUSRÜSTUNG (Rüstung, Upgrades, Perks) mit Geld
--   unten:  Rollen-Tabs, Agenten-Kacheln, BESTÄTIGEN
-- Sichtbar: beim Warten auf Spieler, in der Agentenwahl vor jeder Runde und in Modi mit Respawn nach dem
-- Tod (Spieler-Attribute RespawnAt/RespawnReadyAt vom Server): dann Agent, Waffe und Ausrüstung neu wählen,
-- BEREIT bringt einen zurück in die Runde. Nie zusammen mit Map-Abstimmung oder Match-Zusammenfassung.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local Modes = require(Shared.Modes)
local Cosmetics = require(Shared.Cosmetics)
local AgentFigure = require(Shared.AgentFigure)
local BuyConfig = require(Shared.BuyConfig)
local HUDIcons = require(Shared.HUDIcons)
local HangarScene = require(Shared.HangarScene)

local player = Players.LocalPlayer

local AgentSelect = {}

-- Aufbau für 1600 x 900, wird auf die Bildschirmgröße skaliert
local WIDTH, HEIGHT = 1600, 900
local CYAN = Color3.fromRGB(40, 210, 230)
local RED = Color3.fromRGB(200, 40, 50)
local GOLD = Color3.fromRGB(230, 180, 60)
local GRAY = Color3.fromRGB(170, 175, 190)
local GREEN = Color3.fromRGB(120, 230, 140)
local PURPLE = Color3.fromRGB(170, 90, 230)
local PANEL = Color3.fromRGB(10, 16, 26)
local CARD = Color3.fromRGB(18, 24, 36)
local BORDER = Color3.fromRGB(60, 68, 86)
local TILE = 84
local RIGHT_X, RIGHT_W = 1124, 446    -- rechte Spalte (Waffen, Ausrüstung)
local LEFT_X, LEFT_W = 30, 430        -- linke Spalte (Team, Agent)
local RESPAWN_SHOW_DELAY = 1.5        -- nach dem Tod so lange die Todeskamera, dann die Auswahl

local gui, canvas, scene
local timerLabel, timeBar, modeLabel, roundLabel, scoreFrame, teamFrame, confirmButton
local figure, figureKey
local infoName, infoRole, infoLevel, infoBar, infoStats, infoAbility, infoAbilityText
local tiles = {}           -- [agent] = { Button, Stroke, Level, Lock }
local buyCards = {}        -- [item] = { Button, State, Stroke }
local weaponCards = {}     -- { Frame, Stroke, Name, Tag, Holder, Preview, Shown, Weapon, Selectable }
local moneyLabel, buyStatus
local tabButtons = {}      -- [role] = Button
local currentRole = "ALLE"
local hoverAgent, hoverWeapon = nil, nil
local confirmed = false
local shown = false
local teamSignature = ""
local scoreSignature = ""
local phaseSince = os.clock()          -- seit wann gilt die aktuelle RoundPhase (Client-Zeit)
local respawnTotal = 1                 -- Dauer der aktuellen Auswahl nach dem Tod (für den Zeitbalken)
local respawnSince = 0                 -- seit wann (Client-Zeit) läuft die Auswahl nach dem Tod

local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function text(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, parent)
end

-- Halbdurchsichtige Fläche, damit Texte vor dem Hangar lesbar bleiben
local function panel(props, parent)
	props.BackgroundColor3 = props.BackgroundColor3 or PANEL
	props.BackgroundTransparency = props.BackgroundTransparency or 0.25
	props.BorderSizePixel = 0
	local frame = make("Frame", props, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
	return frame
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

-- Auswahl nach dem Tod (Modi mit Respawn): Restzeit, ob BEREIT schon geht, ob sie gezeigt werden soll
local function respawnState()
	local respawnAt = player:GetAttribute("RespawnAt")
	if type(respawnAt) ~= "number" or player:GetAttribute("RoundPhase") ~= "Round" then
		return nil
	end
	local now = workspace:GetServerTimeNow()
	local readyAt = player:GetAttribute("RespawnReadyAt") or now
	return {
		Left = math.max(0, respawnAt - now),
		ReadyIn = math.max(0, readyAt - now),
		Show = os.clock() - respawnSince >= RESPAWN_SHOW_DELAY, -- erst kurz die Todeskamera zeigen
	}
end

-- ---------- 3D-Agent im Hangar ----------

local function showPreview(agent, weapon)
	local key = agent.Id .. "|" .. tostring(weapon)
	if key == figureKey and figure then
		return
	end
	figureKey = key
	if figure then
		figure:Destroy()
	end
	local primary, accentColor = Cosmetics.AgentColors(player, agent.Id)
	figure = AgentFigure.Build(agent, primary, accentColor, Cosmetics.WeaponSkin(player, agent.Id, weapon), weapon)
	figure.Parent = scene.Viewport
	scene.SetAccent(agent.Color)

	-- Info links
	local xp = AgentConfig.GetXP(player, agent.Id)
	infoName.Text = agent.Name
	infoName.TextColor3 = agent.Color
	infoRole.Text = string.upper(agent.Role)
	infoLevel.Text = "AGENT-LEVEL " .. AgentConfig.LevelFromXP(xp)
	infoBar.Size = UDim2.new(AgentConfig.LevelProgress(xp), 0, 1, 0)
	infoBar.BackgroundColor3 = agent.Color
	infoStats.Text = "♥ " .. agent.Health .. "      TEMPO " .. agent.WalkSpeed
		.. "      GADGET  " .. string.upper(agent.Gadget.Name)
	infoAbility.Text = AgentConfig.AbilityKey.Name .. "   " .. string.upper(agent.Ability.Name)
	infoAbility.TextColor3 = agent.Color
	infoAbilityText.Text = agent.Ability.Description .. "  (" .. agent.Ability.Cooldown .. " s)"
		.. (agent.Passive and ("\nPASSIV · " .. string.upper(agent.Passive.Name) .. ": " .. agent.Passive.Description) or "")
end

-- ---------- Aufbau ----------

local function buildTop()
	-- Dunkler Streifen oben, Zeitbalken ganz oben
	local shade = make("Frame", { Size = UDim2.new(1, 0, 0, 130), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, canvas)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.15, 1) }, shade)
	local barBack = make("Frame", { Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = Color3.fromRGB(60, 65, 75), BorderSizePixel = 0 }, canvas)
	timeBar = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = CYAN, BorderSizePixel = 0 }, barBack)

	modeLabel = text({ Position = UDim2.new(0, 40, 0, 36), Size = UDim2.new(0, 520, 0, 28), Text = "",
		TextSize = 24, TextColor3 = GRAY }, canvas)
	roundLabel = text({ Position = UDim2.new(0, 40, 0, 66), Size = UDim2.new(0, 620, 0, 26), Text = "",
		TextSize = 19, TextColor3 = Color3.new(1, 1, 1) }, canvas)

	-- Timer in der Raute
	diamond(canvas, 78, UDim2.new(0.5, 0, 0, 80), Color3.fromRGB(16, 50, 70), CYAN)
	timerLabel = text({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.new(0, 110, 0, 60), Text = "", TextSize = 46, Font = Enum.Font.Oswald,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)

	-- Rundenstand oben rechts (wird in updateScore gefüllt)
	scoreFrame = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 36),
		Size = UDim2.new(0, 360, 0, 80), BackgroundTransparency = 1 }, canvas)
end

local function buildLeft()
	local back = panel({ Position = UDim2.new(0, LEFT_X - 10, 0, 124), Size = UDim2.new(0, LEFT_W + 20, 0, 534) }, canvas)
	make("UIGradient", { Transparency = NumberSequence.new(0.1, 0.55) }, back)
	text({ Position = UDim2.new(0, LEFT_X, 0, 130), Size = UDim2.new(0, 300, 0, 18), Text = "DEIN TEAM", TextSize = 13,
		TextColor3 = CYAN }, canvas)
	teamFrame = make("Frame", { Position = UDim2.new(0, LEFT_X, 0, 152), Size = UDim2.new(0, LEFT_W, 0, 270),
		BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, teamFrame)

	-- Agent: Name, Rolle, Level, Werte, Fähigkeit
	local y = 430
	make("Frame", { Position = UDim2.new(0, LEFT_X, 0, y - 8), Size = UDim2.new(0, LEFT_W - 30, 0, 1),
		BackgroundColor3 = BORDER, BorderSizePixel = 0 }, canvas)
	infoName = text({ Position = UDim2.new(0, LEFT_X, 0, y), Size = UDim2.new(0, LEFT_W, 0, 56), Text = "",
		TextSize = 52, Font = Enum.Font.Oswald }, canvas)
	infoRole = text({ Position = UDim2.new(0, LEFT_X, 0, y + 56), Size = UDim2.new(0, 200, 0, 22), Text = "",
		TextSize = 18, TextColor3 = GRAY }, canvas)
	infoLevel = text({ Position = UDim2.new(0, LEFT_X + 200, 0, y + 58), Size = UDim2.new(0, 200, 0, 20), Text = "",
		TextSize = 15, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right }, canvas)
	local barBack = make("Frame", { Position = UDim2.new(0, LEFT_X, 0, y + 84), Size = UDim2.new(0, LEFT_W - 30, 0, 5),
		BackgroundColor3 = Color3.fromRGB(50, 55, 68), BorderSizePixel = 0 }, canvas)
	infoBar = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, barBack)
	infoStats = text({ Position = UDim2.new(0, LEFT_X, 0, y + 96), Size = UDim2.new(0, LEFT_W, 0, 20), Text = "",
		TextSize = 15 }, canvas)
	infoAbility = text({ Position = UDim2.new(0, LEFT_X, 0, y + 124), Size = UDim2.new(0, LEFT_W, 0, 22), Text = "",
		TextSize = 18 }, canvas)
	infoAbilityText = text({ Position = UDim2.new(0, LEFT_X, 0, y + 148), Size = UDim2.new(0, LEFT_W - 20, 0, 70), Text = "",
		TextSize = 14, Font = Enum.Font.Gotham, TextColor3 = GRAY, TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top }, canvas)
end

-- Waffen-Karte mit 3D-Vorschau. selectable = Primärwaffe zum Anklicken.
local function makeWeaponCard(x, y, w, h, preview, selectable, index)
	local frame = make("TextButton", { Position = UDim2.new(0, x, 0, y), Size = UDim2.new(0, w, 0, h), BackgroundColor3 = CARD,
		BackgroundTransparency = 0.1, BorderSizePixel = 0, Text = "", AutoButtonColor = selectable }, canvas)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(34, 44, 62), Color3.fromRGB(14, 18, 28)) }, frame)
	local stroke = make("UIStroke", { Color = BORDER, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	local holder = make("Frame", { Position = preview.Position, Size = preview.Size, BackgroundTransparency = 1 }, frame)
	local name = text({ Position = preview.NamePosition, Size = UDim2.new(1, -20, 0, 22), Text = "", TextSize = 18,
		Font = Enum.Font.Oswald }, frame)
	local tag = text({ Position = preview.TagPosition, Size = UDim2.new(1, -20, 0, 16), Text = "", TextSize = 12,
		TextColor3 = GRAY }, frame)
	local card = { Frame = frame, Stroke = stroke, Name = name, Tag = tag, Holder = holder, Preview = nil, Shown = nil,
		Weapon = nil, Selectable = selectable, Width = preview.Size.X.Offset, Height = preview.Size.Y.Offset }
	if selectable then
		frame.MouseEnter:Connect(function()
			hoverWeapon = card.Weapon
		end)
		frame.MouseLeave:Connect(function()
			if hoverWeapon == card.Weapon then
				hoverWeapon = nil
			end
		end)
		frame.Activated:Connect(function()
			local agent = myAgent()
			local weapon = agent.Primaries and agent.Primaries[index]
			if weapon then
				Remotes.ShopAction:FireServer("SelectPrimary", agent.Id, weapon)
			end
		end)
	end
	return card
end

local function buildRight()
	local back = panel({ Position = UDim2.new(0, RIGHT_X - 12, 0, 124), Size = UDim2.new(0, RIGHT_W + 24, 0, 540) }, canvas)
	make("UIGradient", { Transparency = NumberSequence.new(0.55, 0.1) }, back)

	-- WAFFEN: zwei Primärwaffen zur Wahl (wie bei RC) und die Sekundärwaffe, alle mit 3D-Vorschau
	text({ Position = UDim2.new(0, RIGHT_X, 0, 130), Size = UDim2.new(0, 300, 0, 18), Text = "WAFFEN  ·  PRIMÄRWAFFE WÄHLEN",
		TextSize = 13, TextColor3 = CYAN }, canvas)
	local cardW = (RIGHT_W - 10) / 2
	for i = 1, 2 do
		weaponCards[i] = makeWeaponCard(RIGHT_X + (i - 1) * (cardW + 10), 152, cardW, 116, {
			Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(0, cardW - 20, 0, 66),
			NamePosition = UDim2.new(0, 10, 0, 72), TagPosition = UDim2.new(0, 10, 0, 94),
		}, true, i)
	end
	weaponCards[3] = makeWeaponCard(RIGHT_X, 276, RIGHT_W, 62, {
		Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(0, 160, 0, 54),
		NamePosition = UDim2.new(0, 184, 0, 10), TagPosition = UDim2.new(0, 184, 0, 34),
	}, false, 3)

	-- AUSRÜSTUNG direkt darunter: Rüstung, Upgrades und Perks (Kaufphase), Geld rechts
	text({ Position = UDim2.new(0, RIGHT_X, 0, 352), Size = UDim2.new(0, 300, 0, 18), Text = "AUSRÜSTUNG",
		TextSize = 13, TextColor3 = CYAN }, canvas)
	moneyLabel = text({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0, RIGHT_X + RIGHT_W, 0, 346),
		Size = UDim2.new(0, 200, 0, 26), Text = "", TextSize = 22, Font = Enum.Font.Oswald, TextColor3 = GREEN,
		TextXAlignment = Enum.TextXAlignment.Right }, canvas)
	local grid = make("Frame", { Position = UDim2.new(0, RIGHT_X, 0, 376), Size = UDim2.new(0, RIGHT_W, 0, 252),
		BackgroundTransparency = 1 }, canvas)
	make("UIGridLayout", { CellSize = UDim2.new(0, cardW, 0, 44), CellPadding = UDim2.new(0, 10, 0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, item in BuyConfig.Items do
		local card = make("TextButton", { BackgroundColor3 = CARD, BackgroundTransparency = 0.1, BorderSizePixel = 0,
			Text = "", AutoButtonColor = true, LayoutOrder = i }, grid)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, card)
		local stroke = make("UIStroke", { Color = item.Perk and PURPLE or BORDER, Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
		make("Frame", { Size = UDim2.new(0, 3, 1, -10), Position = UDim2.new(0, 4, 0, 5), BorderSizePixel = 0,
			BackgroundColor3 = item.Perk and PURPLE or (item.PerRound and GOLD or CYAN) }, card)
		text({ Position = UDim2.new(0, 14, 0, 4), Size = UDim2.new(1, -20, 0, 20),
			Text = (item.Perk and "✦ " or "") .. item.Name, TextSize = 14 }, card)
		local state = text({ Position = UDim2.new(0, 14, 0, 23), Size = UDim2.new(1, -20, 0, 18), Text = "",
			TextSize = 14, Font = Enum.Font.Oswald }, card)
		card.MouseEnter:Connect(function()
			buyStatus.Text = item.Name .. ": " .. item.Description
			buyStatus.TextColor3 = GRAY
		end)
		card.Activated:Connect(function()
			Remotes.Buy:FireServer(item.Id)
		end)
		buyCards[item] = { Button = card, State = state, Stroke = stroke }
	end
	buyStatus = text({ Position = UDim2.new(0, RIGHT_X, 0, 632), Size = UDim2.new(0, RIGHT_W, 0, 30), Text = "",
		TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = GRAY, TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top }, canvas)
end

local function refreshTiles()
	local chosen = myAgent()
	for agent, entry in tiles do
		entry.Button.Visible = currentRole == "ALLE" or string.upper(agent.Role) == currentRole
		entry.Stroke.Color = agent == chosen and RED or Color3.fromRGB(60, 65, 80)
		entry.Stroke.Thickness = agent == chosen and 3 or 1
		local unlocked = AgentConfig.IsUnlocked(player, agent.Id)
		entry.Level.Text = tostring(AgentConfig.LevelFromXP(AgentConfig.GetXP(player, agent.Id)))
		entry.Lock.Visible = not unlocked
		entry.Button.BackgroundTransparency = unlocked and 0 or 0.5
	end
	for role, button in tabButtons do
		button.BackgroundColor3 = role == currentRole and RED or Color3.fromRGB(18, 20, 28)
	end
end

local function buildBottom()
	local barWidth = 1060
	local shade = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 250), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, canvas)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0.1) }, shade)
	-- Rollen-Tabs
	local roles = { "ALLE" }
	for _, agent in AgentConfig.Agents do
		local role = string.upper(agent.Role)
		if not table.find(roles, role) then
			table.insert(roles, role)
		end
	end
	local tabs = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 674),
		Size = UDim2.new(0, barWidth, 0, 30), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BorderSizePixel = 0 }, canvas)
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
	local grid = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 714),
		Size = UDim2.new(0, barWidth, 0, TILE), BackgroundTransparency = 1 }, canvas)
	make("UIGridLayout", { CellSize = UDim2.new(0, TILE, 0, TILE), CellPadding = UDim2.new(0, 8, 0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, agent in AgentConfig.Agents do
		local tile = make("TextButton", { BackgroundColor3 = agent.Color:Lerp(Color3.new(0, 0, 0), 0.45),
			BorderSizePixel = 0, Text = "", AutoButtonColor = true, LayoutOrder = i }, grid)
		make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(90, 90, 90)) }, tile)
		local stroke = make("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tile)
		text({ Size = UDim2.new(1, 0, 0.75, 0), Text = string.sub(agent.Name, 1, 1), TextSize = 44,
			Font = Enum.Font.Oswald, TextXAlignment = Enum.TextXAlignment.Center }, tile)
		text({ Position = UDim2.new(0, 0, 0.72, 0), Size = UDim2.new(1, 0, 0.26, 0), Text = agent.Name,
			TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center }, tile)
		-- Level-Raute oben rechts
		diamond(tile, 16, UDim2.new(1, -11, 0, 11), GOLD)
		local level = text({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -11, 0, 11),
			Size = UDim2.new(0, 22, 0, 22), Text = "", TextSize = 11, Font = Enum.Font.Oswald,
			TextColor3 = Color3.fromRGB(20, 20, 20), TextXAlignment = Enum.TextXAlignment.Center }, tile)

		tile.MouseEnter:Connect(function()
			hoverAgent = agent
		end)
		tile.MouseLeave:Connect(function()
			if hoverAgent == agent then
				hoverAgent = nil
			end
		end)
		-- Schloss mit Preis für noch nicht freigeschaltete Agenten
		local lock = text({ Size = UDim2.new(1, 0, 1, 0), Text = "🔒\n" .. tostring(agent.Price) .. " 💰", TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0.35, Visible = false }, tile)
		lock.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
		tile.Activated:Connect(function()
			if not AgentConfig.IsUnlocked(player, agent.Id) then
				Remotes.ShopAction:FireServer("UnlockAgent", agent.Id)
			elseif not isLocked() then
				Remotes.SelectAgent:FireServer(agent.Id, false)
			end
		end)
		tiles[agent] = { Button = tile, Stroke = stroke, Level = level, Lock = lock }
	end

	confirmButton = make("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 822),
		Size = UDim2.new(0, 360, 0, 50), BackgroundColor3 = RED, BorderSizePixel = 0, Font = Enum.Font.Oswald,
		TextSize = 22, TextColor3 = Color3.new(1, 1, 1), Text = "AGENT BESTÄTIGEN" }, canvas)
	make("UICorner", { CornerRadius = UDim.new(0, 4) }, confirmButton)
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
	local background = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(3, 5, 12),
		BorderSizePixel = 0, Active = true }, gui)
	-- Hangar des Raumschiffs (3D) als Hintergrund, der Agent steht darin
	scene = HangarScene.new(background)
	scene.Viewport.ZIndex = 0

	canvas = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, WIDTH, 0, HEIGHT), BackgroundTransparency = 1, ZIndex = 1 }, background)
	local scale = make("UIScale", {}, canvas)
	local function updateScale()
		local viewportSize = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(viewportSize.X / WIDTH, viewportSize.Y / HEIGHT)
	end
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	buildTop()
	buildLeft()
	buildRight()
	buildBottom()
end

-- ---------- Team links ----------

-- Spieler und Bots im eigenen Team: { Name, Agent, Locked, IsMe, IsBot }
local function teamEntries()
	local list = {}
	if not player.Team then
		return list
	end
	for _, p in Players:GetPlayers() do
		if p.Team == player.Team and p:GetAttribute("Mode") == player:GetAttribute("Mode") then
			table.insert(list, { Name = p.Name, Agent = AgentConfig.Get(p:GetAttribute("Agent")),
				Locked = p:GetAttribute("AgentLocked") == true, IsMe = p == player })
		end
	end
	for _, info in ReplicatedStorage:WaitForChild("BotInfo"):GetChildren() do
		if info:GetAttribute("Mode") == player:GetAttribute("Mode") and info:GetAttribute("TeamName") == player.Team.Name then
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
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, LayoutOrder = i }, teamFrame)
		-- Leiste mit Verlauf, Raute mit Agent (leer, solange er noch wählt)
		local bar = make("Frame", { Position = UDim2.new(0, 24, 0.5, -19), Size = UDim2.new(0, 340, 0, 38),
			BackgroundColor3 = e.IsMe and Color3.fromRGB(120, 95, 30) or Color3.fromRGB(20, 120, 150), BorderSizePixel = 0 }, row)
		make("UIGradient", { Transparency = NumberSequence.new(0.15, 0.95) }, bar)
		local color = (e.Locked and e.Agent) and e.Agent.Color:Lerp(Color3.new(0, 0, 0), 0.3) or Color3.new(0, 0, 0)
		diamond(row, 36, UDim2.new(0, 24, 0.5, 0), color, e.IsMe and GOLD or CYAN)
		text({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 24, 0.5, 0), Size = UDim2.new(0, 36, 0, 36),
			Text = (e.Locked and e.Agent) and string.sub(e.Agent.Name, 1, 1) or "", TextSize = 22, Font = Enum.Font.Oswald,
			TextXAlignment = Enum.TextXAlignment.Center }, row)
		text({ Position = UDim2.new(0, 60, 0, 4), Size = UDim2.new(0, 300, 0, 20), Text = e.Name .. (e.IsBot and "  [BOT]" or ""),
			TextSize = 16, TextColor3 = e.IsMe and GOLD or Color3.new(1, 1, 1) }, row)
		text({ Position = UDim2.new(0, 60, 0, 24), Size = UDim2.new(0, 300, 0, 18),
			Text = (e.Locked and e.Agent) and ("✓ " .. e.Agent.Name) or "WÄHLT ...", TextSize = 15, Font = Enum.Font.Oswald,
			TextColor3 = (e.Locked and e.Agent) and e.Agent.Color or GRAY }, row)
	end
end

-- ---------- Rundenstand oben rechts ----------

local function updateScore()
	-- Stand kommt vom Server aus Sicht des eigenen Teams
	local total = player:GetAttribute("RoundsToWin") or 5
	local ours = player:GetAttribute("TeamScore") or 0
	local theirs = player:GetAttribute("EnemyScore") or 0
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
					Text = "✓", TextSize = 14, Font = Enum.Font.Oswald, TextXAlignment = Enum.TextXAlignment.Center },
					scoreFrame)
			end
		end
	end
end

-- ---------- Waffen und Ausrüstung rechts ----------

local function setCardWeapon(card, weapon, skin)
	card.Weapon = weapon
	card.Frame.Visible = weapon ~= nil
	if not weapon then
		return
	end
	local config = WeaponConfig.Get(weapon)
	card.Name.Text = string.upper(config and config.DisplayName or weapon)
	local key = weapon .. "|" .. tostring(skin and skin.Name)
	if key ~= card.Shown then
		card.Shown = key
		if card.Preview then
			card.Preview:Destroy()
		end
		card.Preview = HUDIcons.WeaponModel(card.Holder, weapon, card.Width, card.Height, skin)
	end
end

local function updateWeapons(agent)
	local loadout = AgentConfig.LoadoutFor(player, agent.Id)
	local chosen = loadout[1]
	for i = 1, 2 do
		local card = weaponCards[i]
		local weapon = agent.Primaries and agent.Primaries[i] or (i == 1 and chosen or nil)
		setCardWeapon(card, weapon, weapon and Cosmetics.WeaponSkin(player, agent.Id, weapon))
		if weapon then
			local selected = weapon == chosen
			card.Stroke.Color = selected and CYAN or (hoverWeapon == weapon and GRAY or BORDER)
			card.Stroke.Thickness = selected and 2 or 1
			card.Tag.Text = selected and "✓ AUSGEWÄHLT" or "ANKLICKEN ZUM WÄHLEN"
			card.Tag.TextColor3 = selected and CYAN or GRAY
		end
	end
	local secondary = loadout[2]
	setCardWeapon(weaponCards[3], secondary, secondary and Cosmetics.WeaponSkin(player, agent.Id, secondary))
	weaponCards[3].Tag.Text = "SEKUNDÄRWAFFE  ·  GADGET: " .. string.upper(agent.Gadget.Name)
end

local function updateEquipment(phase, respawning)
	local money = player:GetAttribute("Money")
	moneyLabel.Text = money and ("💵 " .. money .. " $") or ""
	local canBuy = phase == "Select" or phase == "Countdown" or respawning
	for item, entry in buyCards do
		if BuyConfig.Has(player, item.Id) then
			entry.State.Text = "GEKAUFT ✓"
			entry.State.TextColor3 = GREEN
			entry.Stroke.Color = GREEN
		elseif not canBuy or money == nil then
			entry.State.Text = item.Price .. " $  ·  vor der Runde"
			entry.State.TextColor3 = GRAY
			entry.Stroke.Color = item.Perk and PURPLE or BORDER
		else
			entry.State.Text = item.Price .. " $"
			entry.State.TextColor3 = money >= item.Price and Color3.new(1, 1, 1) or Color3.fromRGB(255, 110, 110)
			entry.Stroke.Color = item.Perk and PURPLE or BORDER
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

-- Liegt gerade ein anderes Vollbild darüber (Match-Zusammenfassung)?
local function summaryOpen()
	local summary = player.PlayerGui:FindFirstChild("MatchSummary")
	return summary ~= nil and summary:IsA("ScreenGui") and summary.Enabled
end

local function update()
	local phase = player:GetAttribute("RoundPhase")
	local modeInfo = Modes.Get(player:GetAttribute("Mode"))
	local inTeamMode = modeInfo ~= nil and modeInfo.TeamMode == true
	local respawn = inTeamMode and respawnState() or nil
	local respawning = respawn ~= nil
	-- Reihenfolge nach einem Match: Zusammenfassung -> Map-Abstimmung -> Agentenwahl (nie übereinander).
	-- "Waiting" dauert zwischen Match-Ende und Abstimmung nur einen Augenblick: erst nach 1 s zeigen.
	local show = false
	if inTeamMode and not summaryOpen() and phase ~= "MapVote" then
		if respawning then
			show = respawn.Show
		elseif phase == "Waiting" then
			show = os.clock() - phaseSince > 1
		elseif phase == "Select" then
			show = true
		else
			show = not confirmed -- später dazugekommen: wählen und auf die nächste Runde warten
		end
	end
	gui.Enabled = show
	if show ~= shown then
		shown = show
		setMouseFree(show)
	end
	if not show then
		return
	end

	-- Timer und Zeitbalken
	if respawning then
		timerLabel.Text = tostring(math.ceil(respawn.Left))
		timeBar.Size = UDim2.new(math.clamp(respawn.Left / respawnTotal, 0, 1), 0, 1, 0)
		timeBar.BackgroundColor3 = GOLD
	elseif phase == "Select" then
		local duration = player:GetAttribute("SelectDuration") or 1
		local left = math.max(0, (player:GetAttribute("SelectUntil") or 0) - workspace:GetServerTimeNow())
		timerLabel.Text = tostring(math.ceil(left))
		timeBar.Size = UDim2.new(math.clamp(left / duration, 0, 1), 0, 1, 0)
		timeBar.BackgroundColor3 = CYAN
	else
		timerLabel.Text = "–"
		timeBar.Size = UDim2.new(1, 0, 1, 0)
		timeBar.BackgroundColor3 = CYAN
	end
	modeLabel.Text = modeInfo.Name .. "  ·  " .. string.upper(modeInfo.Tag)
		.. (player:GetAttribute("MapName") and ("  ·  MAP: " .. string.upper(player:GetAttribute("MapName"))) or "")
	if respawning then
		roundLabel.Text = "AUSGESCHALTET – Agent, Waffe und Ausrüstung wählen, dann zurück ins Gefecht"
		roundLabel.TextColor3 = GOLD
	elseif phase == "Waiting" then
		roundLabel.Text = player:GetAttribute("ModeText") or "Warte auf Spieler..."
		roundLabel.TextColor3 = Color3.new(1, 1, 1)
	elseif phase == "Select" then
		roundLabel.Text = "RUNDE " .. (player:GetAttribute("RoundNumber") or 1) .. "  ·  AGENT, WAFFE UND AUSRÜSTUNG WÄHLEN"
		roundLabel.TextColor3 = Color3.new(1, 1, 1)
	else
		roundLabel.Text = "Runde läuft – du steigst in der nächsten Runde ein"
		roundLabel.TextColor3 = Color3.new(1, 1, 1)
	end

	-- Bestätigen-Knopf
	if respawning then
		if isLocked() then
			confirmButton.Text = "BEREIT ✓  ·  GLEICH GEHT'S LOS"
			confirmButton.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
		elseif respawn.ReadyIn > 0 then
			confirmButton.Text = "BEREIT  ·  IN " .. math.ceil(respawn.ReadyIn) .. " S ZURÜCK"
			confirmButton.BackgroundColor3 = RED
		else
			confirmButton.Text = "BEREIT  ·  ZURÜCK INS GEFECHT"
			confirmButton.BackgroundColor3 = RED
		end
	elseif isLocked() then
		confirmButton.Text = "BESTÄTIGT ✓"
		confirmButton.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
	elseif phase == "Select" or phase == "Waiting" then
		confirmButton.Text = "AGENT BESTÄTIGEN"
		confirmButton.BackgroundColor3 = RED
	else
		confirmButton.Text = "BESTÄTIGEN & ZUSCHAUEN"
		confirmButton.BackgroundColor3 = RED
	end

	local agent = myAgent()
	local previewAgent = hoverAgent or agent
	-- Vorschau: überfahrene Primärwaffe, sonst die gewählte des gezeigten Agenten
	local weapon = (previewAgent == agent and hoverWeapon) or AgentConfig.LoadoutFor(player, previewAgent.Id)[1]
	showPreview(previewAgent, weapon)
	updateWeapons(agent)
	updateEquipment(phase, respawning)
	refreshTiles()
	updateTeam()
	updateScore()
end

function AgentSelect.Init()
	build()

	-- Rückmeldung beim Kaufen
	Remotes.ShopStatus.OnClientEvent:Connect(function(message, success)
		buyStatus.Text = message
		buyStatus.TextColor3 = success and GREEN or Color3.fromRGB(255, 120, 120)
	end)

	-- Neu im Modus: erst wählen
	player:GetAttributeChangedSignal("Mode"):Connect(function()
		confirmed = false
	end)
	player:GetAttributeChangedSignal("RoundPhase"):Connect(function()
		phaseSince = os.clock()
		local phase = player:GetAttribute("RoundPhase")
		if phase == "Countdown" then
			confirmed = true -- Match startet: Bildschirm schließt
		elseif phase == "Waiting" or phase == "MapVote" or phase == "Select" then
			confirmed = false
		end
	end)
	-- Neue Auswahl nach dem Tod: Gesamtdauer für den Zeitbalken merken
	player:GetAttributeChangedSignal("RespawnAt"):Connect(function()
		local respawnAt = player:GetAttribute("RespawnAt")
		if type(respawnAt) == "number" then
			respawnTotal = math.max(1, respawnAt - workspace:GetServerTimeNow())
			respawnSince = os.clock()
		end
	end)
	-- Level/XP/Skins geändert: 3D-Figur und Info neu aufbauen
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 3) == "XP_" or name == "Equipped" or name == "Owned" or name == "Loadouts" then
			figureKey = nil
			for _, card in weaponCards do
				card.Shown = nil
			end
		end
	end)

	-- Agent langsam hin und her drehen, Kamera im Hangar leicht schweben lassen
	RunService.RenderStepped:Connect(function()
		if shown then
			scene.Update(os.clock())
			if figure then
				local angle = math.sin(os.clock() * 0.6) * 0.45 + 0.3
				figure:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, angle, 0))
			end
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

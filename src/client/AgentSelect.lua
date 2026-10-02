-- AgentSelect (ModuleScript, nur Client)
-- Agenten- und Ausrüstungswahl in den Team-Modi im Design der Lobby ("BLOCKOPS"), im Hangar eines
-- Raumschiffs (HangarScene) als Hintergrund:
--   oben:   Modus und Map, große Überschrift ("WÄHLE DEINEN AGENTEN"), rechts Timer in einer Fläche
--           (die letzten 10 s rot) und der Rundenstand
--   links:  DEIN TEAM (Porträt, Name, Agent, BESTÄTIGT/WÄHLT ...), darunter WAFFE (Primärwaffen zur Wahl
--           mit 3D-Vorschau, Sekundärwaffe) und direkt darunter AUSRÜSTUNG mit Geld
--   Mitte:  großer 3D-Agent auf der Plattform; hält die gewählte (bzw. überfahrene) Primärwaffe
--   rechts: Rolle als Schild, Name in Konturschrift, Beschreibung, Werte als Balken (Leben, Tempo,
--           Fähigkeit), Fähigkeit/Gadget/Passiv mit Tasten-Schild, Agenten-Level
--   unten:  Agenten-Kacheln mit Porträt (aktiv gelb umrandet, gesperrte mit Preis) und BESTÄTIGEN
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
local UITheme = require(Shared.UITheme)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label, upper = UITheme.Make, UITheme.Label, UITheme.Upper

local AgentSelect = {}

-- Aufbau für 1600 x 900, wird auf die Bildschirmgröße skaliert
local WIDTH, HEIGHT = 1600, 900
local LEFT_X, LEFT_W = 32, 330        -- Team, Waffe, Ausrüstung
local RIGHT_X, RIGHT_W = 1248, 320    -- Agent: Rolle, Name, Werte, Fähigkeiten
local TILE = 66                       -- Agenten-Kacheln unten
local PURPLE = Color3.fromRGB(146, 128, 186) -- Perks (gedämpftes Violett)
local RESPAWN_SHOW_DELAY = 1.5        -- nach dem Tod so lange die Todeskamera, dann die Auswahl
local URGENT = 10                     -- ab so vielen Sekunden wird der Timer rot

local gui, canvas, scene
local headerInfo, headerTitle, headerSub, timerPanel, timerStroke, timerLabel, timerIcon, scoreLabel
local teamFrame, confirm, confirmSub
local figure, figureKey
local roleTag, infoName, infoText, statBars, abilityRows, infoLevel, infoBar
local tiles = {}           -- [agent] = { Chunky, Portrait, Lock, Level }
local buyCards = {}        -- [item] = { Button, Name, State, Stroke }
local weaponCards = {}     -- { Frame, Stroke, Name, Tag, Holder, Preview, Shown, Weapon, Width, Height }
local moneyLabel, buyStatus
local hoverAgent, hoverWeapon = nil, nil
local confirmed = false
local shown = false
local teamSignature = ""
local phaseSince = os.clock()          -- seit wann gilt die aktuelle RoundPhase (Client-Zeit)
local respawnSince = 0                 -- seit wann (Client-Zeit) läuft die Auswahl nach dem Tod

local function myAgent()
	return AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
end

local function isLocked()
	return player:GetAttribute("AgentLocked") == true
end

local function formatClock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
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

local function heading(text, x, y, color, parent)
	return label({ Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(240, 20), Text = upper(text), TextSize = 12,
		Font = F.Bold, TextColor3 = color or C.Muted }, parent or canvas)
end

-- ---------- 3D-Agent im Hangar und Infos rechts ----------

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

	roleTag.Text = upper(agent.Role)
	infoName.Text = agent.Name
	infoText.Text = agent.Description or ""
	for stat, bar in statBars do
		local value = AgentConfig.StatValue(stat, agent)
		for i, segment in bar.Segments do
			segment.BackgroundColor3 = i <= value and C.Primary or C.Background
		end
		bar.Value.Text = stat == "Health" and tostring(agent.Health) or stat == "Speed" and tostring(agent.WalkSpeed)
			or (agent.Ability.Cooldown .. " s")
	end
	local rows = {
		{ AgentConfig.AbilityKey.Name, agent.Ability.Name, agent.Ability.Cooldown .. " s", agent.Ability.Description },
		{ AgentConfig.GadgetKey.Name, agent.Gadget.Name, (agent.Gadget.Charges or 1) .. "×",
			AgentConfig.GadgetDescription(agent.Gadget) },
		{ "", agent.Passive and agent.Passive.Name or "–", "PASSIV", agent.Passive and agent.Passive.Description or "" },
	}
	for i, row in rows do
		local entry = abilityRows[i]
		entry.Key.Text = row[1]
		entry.Diamond.Visible = row[1] == "" -- Passiv: kleine Raute statt Taste
		entry.Name.Text = string.format('%s  <font color="#%s">· %s</font>', upper(row[2]), C.Muted:ToHex(), row[3])
		entry.Text.Text = row[4]
	end
	local xp = AgentConfig.GetXP(player, agent.Id)
	infoLevel.Text = "AGENT-LEVEL " .. AgentConfig.LevelFromXP(xp)
	infoBar.Size = UDim2.fromScale(AgentConfig.LevelProgress(xp), 1)
	infoBar.BackgroundColor3 = C.Primary
end

-- ---------- Aufbau ----------

local function buildHeader()
	headerInfo = label({ Position = UDim2.fromOffset(LEFT_X, 26), Size = UDim2.fromOffset(900, 18), Text = "", TextSize = 13,
		Font = F.Bold, TextColor3 = C.Muted }, canvas)
	headerTitle = label({ Position = UDim2.fromOffset(LEFT_X, 44), Size = UDim2.fromOffset(1000, 48), Text = "", TextSize = 44,
		Font = F.Display }, canvas)
	UITheme.Outline(headerTitle, 1)
	UITheme.Outline(headerInfo, 1)
	headerSub = label({ Position = UDim2.fromOffset(LEFT_X, 92), Size = UDim2.fromOffset(1000, 20), Text = "", TextSize = 14,
		Font = F.Bold, TextColor3 = C.Text }, canvas)
	UITheme.Outline(headerSub, 1)

	-- Timer rechts oben (Fläche mit Uhr, die letzten Sekunden rot)
	timerPanel = UITheme.Card({ Name = "Timer", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -LEFT_X, 0, 26),
		Size = UDim2.fromOffset(180, 66) }, canvas)
	timerStroke = timerPanel:FindFirstChildOfClass("UIStroke")
	timerIcon = label({ Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(50, 66), Text = "ZEIT", TextSize = 11,
		Font = F.Bold, TextColor3 = C.Primary, ZIndex = 3 }, timerPanel)
	timerLabel = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.fromOffset(120, 66),
		Text = "", TextSize = 40, Font = F.Display, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 }, timerPanel)
	scoreLabel = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -LEFT_X, 0, 100), Size = UDim2.fromOffset(400, 20),
		Text = "", TextSize = 14, Font = F.Display, RichText = true, TextXAlignment = Enum.TextXAlignment.Right }, canvas)
end

-- Waffen-Karte mit 3D-Vorschau. selectable = Primärwaffe zum Anklicken (index = Nummer in Primaries).
local function makeWeaponCard(x, y, w, h, preview, selectable, index)
	local frame = make("TextButton", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08, BorderSizePixel = 0, Text = "", AutoButtonColor = false }, canvas)
	UITheme.Corner(frame, UITheme.Radius.Large)
	local stroke = UITheme.Stroke(frame, C.Border, 1)
	local holder = make("Frame", { Position = preview.Position, Size = preview.Size, BackgroundTransparency = 1 }, frame)
	local name = label({ Position = preview.NamePosition, Size = UDim2.new(1, -20, 0, 18), Text = "", TextSize = 18,
		Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd }, frame)
	local tag = label({ Position = preview.TagPosition, Size = UDim2.new(1, -20, 0, 14), Text = "", TextSize = 11, Font = F.Bold,
		TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd }, frame)
	local card = { Frame = frame, Stroke = stroke, Name = name, Tag = tag, Holder = holder, Preview = nil, Shown = nil,
		Weapon = nil, Width = preview.Size.X.Offset, Height = preview.Size.Y.Offset }
	if selectable then
		frame.MouseEnter:Connect(function()
			hoverWeapon = card.Weapon
			frame.BackgroundColor3 = C.Card
		end)
		frame.MouseLeave:Connect(function()
			if hoverWeapon == card.Weapon then
				hoverWeapon = nil
			end
			frame.BackgroundColor3 = C.Panel
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

local function buildLeft()
	heading("Dein Team", LEFT_X, 124, C.Accent)
	teamFrame = make("Frame", { Position = UDim2.fromOffset(LEFT_X, 148), Size = UDim2.fromOffset(LEFT_W, 268),
		BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, teamFrame)

	-- WAFFE: zwei Primärwaffen zur Wahl (wie bei RC) und die Sekundärwaffe, alle mit 3D-Vorschau
	heading("Waffe", LEFT_X, 426)
	label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(LEFT_X + LEFT_W, 428), Size = UDim2.fromOffset(200, 16),
		Text = "KLICK = PRIMÄRWAFFE WÄHLEN", TextSize = 10, Font = F.Bold, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right }, canvas)
	local cardW = (LEFT_W - 10) / 2
	for i = 1, 2 do
		weaponCards[i] = makeWeaponCard(LEFT_X + (i - 1) * (cardW + 10), 450, cardW, 96, {
			Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(cardW - 16, 52),
			NamePosition = UDim2.fromOffset(12, 56), TagPosition = UDim2.fromOffset(12, 76),
		}, true, i)
	end
	weaponCards[3] = makeWeaponCard(LEFT_X, 554, LEFT_W, 46, {
		Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(110, 40),
		NamePosition = UDim2.fromOffset(126, 6), TagPosition = UDim2.fromOffset(126, 25),
	}, false, 3)

	-- AUSRÜSTUNG direkt darunter: Upgrades, Rüstung, Perks (Kaufphase bzw. nach dem Tod), Geld rechts
	heading("Ausrüstung", LEFT_X, 614)
	moneyLabel = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(LEFT_X + LEFT_W, 610), Size = UDim2.fromOffset(200, 24),
		Text = "", TextSize = 18, Font = F.Display, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Right }, canvas)
	local grid = make("Frame", { Position = UDim2.fromOffset(LEFT_X, 638), Size = UDim2.fromOffset(LEFT_W, 230),
		BackgroundTransparency = 1 }, canvas)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(cardW, 40), CellPadding = UDim2.fromOffset(10, 6),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, item in BuyConfig.Items do
		local card = make("TextButton", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.08, BorderSizePixel = 0, Text = "",
			AutoButtonColor = false, LayoutOrder = i }, grid)
		UITheme.Corner(card, UITheme.Radius.Medium)
		local stroke = UITheme.Stroke(card, item.Perk and PURPLE or C.Border, 1)
		local name = label({ Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -16, 0, 18),
			Text = item.Name, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		local state = label({ Position = UDim2.fromOffset(10, 20), Size = UDim2.new(1, -16, 0, 16), Text = "", TextSize = 12,
			Font = F.Display }, card)
		card.MouseEnter:Connect(function()
			buyStatus.Text = item.Name .. ": " .. item.Description
			buyStatus.TextColor3 = C.Muted
			card.BackgroundColor3 = C.Card
		end)
		card.MouseLeave:Connect(function()
			card.BackgroundColor3 = C.Panel
		end)
		card.Activated:Connect(function()
			Remotes.Buy:FireServer(item.Id)
		end)
		buyCards[item] = { Button = card, Name = name, State = state, Stroke = stroke }
	end
end

local function buildRight()
	roleTag = UITheme.Tag({ Position = UDim2.fromOffset(RIGHT_X, 124), Text = "", TextSize = 12, BackgroundColor3 = C.Secondary,
		TextColor3 = C.Primary }, canvas)
	infoName = label({ Position = UDim2.fromOffset(RIGHT_X, 150), Size = UDim2.fromOffset(RIGHT_W, 58), Text = "", TextSize = 58,
		Font = F.Display }, canvas)
	UITheme.Outline(infoName, 1)
	infoText = label({ Position = UDim2.fromOffset(RIGHT_X, 210), Size = UDim2.fromOffset(RIGHT_W, 36), Text = "", TextSize = 13,
		Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, canvas)

	-- Werte: je 10 Segmente (wie im Design)
	local stats = UITheme.Card({ Name = "Stats", Position = UDim2.fromOffset(RIGHT_X, 254), Size = UDim2.fromOffset(RIGHT_W, 104) }, canvas)
	statBars = {}
	for i, entry in { { "Health", "LEBEN" }, { "Speed", "TEMPO" }, { "Utility", "FÄHIGKEIT" } } do
		local y = 14 + (i - 1) * 28
		label({ Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(86, 20), Text = entry[2], TextSize = 11, Font = F.Bold,
			TextColor3 = C.Muted, ZIndex = 3 }, stats)
		local segments = {}
		for s = 1, 10 do
			local segment = make("Frame", { Position = UDim2.fromOffset(106 + (s - 1) * 16, y + 7), Size = UDim2.fromOffset(14, 6),
				BackgroundColor3 = C.Background, BorderSizePixel = 0, ZIndex = 3 }, stats)
			table.insert(segments, segment)
		end
		local value = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, y), Size = UDim2.fromOffset(40, 20),
			Text = "", TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 }, stats)
		statBars[entry[1]] = { Segments = segments, Value = value }
	end

	-- Fähigkeit, Gadget, Passiv: Tasten-Schild + Name · Abklingzeit + Beschreibung
	abilityRows = {}
	for i = 1, 3 do
		local y = 372 + (i - 1) * 70
		local row = UITheme.Panel({ Position = UDim2.fromOffset(RIGHT_X, y), Size = UDim2.fromOffset(RIGHT_W, 62),
			BackgroundTransparency = 0.12 }, canvas)
		local key = label({ Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(38, 38), Text = "", TextSize = 16,
			Font = F.Display, TextColor3 = C.Primary, BackgroundTransparency = 0, BackgroundColor3 = C.Background,
			TextXAlignment = Enum.TextXAlignment.Center }, row)
		UITheme.Corner(key, UITheme.Radius.Small)
		UITheme.Stroke(key, C.Primary, 1)
		-- gezeichnete Raute für das Passiv (Oswald hat kein "◆")
		local diamond = UITheme.Diamond(key, 10, UDim2.fromScale(0.5, 0.5), C.Primary)
		diamond.Visible = false
		local name = label({ Position = UDim2.fromOffset(62, 8), Size = UDim2.new(1, -72, 0, 18), Text = "", TextSize = 13,
			RichText = true, TextTruncate = Enum.TextTruncate.AtEnd }, row)
		local text = label({ Position = UDim2.fromOffset(62, 26), Size = UDim2.new(1, -72, 0, 30), Text = "", TextSize = 11,
			Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, row)
		abilityRows[i] = { Key = key, Name = name, Text = text, Diamond = diamond }
	end

	-- Agenten-Level
	infoLevel = label({ Position = UDim2.fromOffset(RIGHT_X, 588), Size = UDim2.fromOffset(RIGHT_W, 18), Text = "", TextSize = 12,
		Font = F.Display, TextColor3 = C.Gold }, canvas)
	local barBack = make("Frame", { Position = UDim2.fromOffset(RIGHT_X, 612), Size = UDim2.fromOffset(RIGHT_W, 4),
		BackgroundColor3 = C.Background, BorderSizePixel = 0 }, canvas)
	infoBar = make("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0 }, barBack)

	-- Rückmeldungen (Kaufen, Beschreibung der Ausrüstung)
	buyStatus = label({ Position = UDim2.fromOffset(RIGHT_X, 640), Size = UDim2.fromOffset(RIGHT_W, 60), Text = "", TextSize = 13,
		Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, canvas)
end

local function buildBottom()
	-- Agenten-Kacheln und BESTÄTIGEN nebeneinander, mittig
	local count = #AgentConfig.Agents
	local confirmW = 204
	local rowW = count * TILE + (count - 1) * 7 + 14 + confirmW
	local row = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(rowW, TILE + 5), BackgroundTransparency = 1 }, canvas)
	local roster = make("Frame", { Size = UDim2.fromOffset(rowW - confirmW - 14, TILE + 5), BackgroundTransparency = 1 }, row)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 7),
		VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }, roster)
	for i, agent in AgentConfig.Agents do
		local chunky = UITheme.Chunky({ Size = UDim2.fromOffset(TILE, TILE), LayoutOrder = i, Color = C.Card, StrokeColor = C.Border,
			Text = "" }, roster)
		local face = chunky.Face
		face.ClipsDescendants = true
		local portrait = HUDIcons.Portrait(face, TILE)
		portrait.Frame.Position = UDim2.fromOffset(0, -4)
		portrait.Set(agent.Id, player)
		local nameStrip = label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 15),
			Text = agent.Name, TextSize = 10, Font = F.Display, BackgroundTransparency = 0.15, BackgroundColor3 = C.Background,
			TextXAlignment = Enum.TextXAlignment.Center }, face)
		local level = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -3, 0, 3), Size = UDim2.fromOffset(18, 14),
			Text = "", TextSize = 10, Font = F.Display, TextColor3 = C.PrimaryText, BackgroundTransparency = 0,
			BackgroundColor3 = C.Primary, TextXAlignment = Enum.TextXAlignment.Center }, face)
		UITheme.Corner(level, UITheme.Radius.Small)
		-- "GESPERRT" mit Preis für noch nicht freigeschaltete Agenten
		local lock = label({ Size = UDim2.new(1, 0, 1, -15), Text = "GESPERRT\n" .. UITheme.FormatNumber(agent.Price or 0), TextSize = 10,
			Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0.3,
			BackgroundColor3 = C.Background, Visible = false }, face)
		chunky.Button.MouseEnter:Connect(function()
			hoverAgent = agent
		end)
		chunky.Button.MouseLeave:Connect(function()
			if hoverAgent == agent then
				hoverAgent = nil
			end
		end)
		chunky.Button.Activated:Connect(function()
			if not AgentConfig.IsUnlocked(player, agent.Id) then
				Remotes.ShopAction:FireServer("UnlockAgent", agent.Id)
			elseif not isLocked() then
				Remotes.SelectAgent:FireServer(agent.Id, false)
			end
		end)
		tiles[agent] = { Chunky = chunky, Portrait = portrait, Lock = lock, Level = level, Strip = nameStrip }
	end

	confirm = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(confirmW, TILE),
		Color = C.Primary, Text = "BESTÄTIGEN", TextSize = 28, TextColor = C.PrimaryText }, row, function()
		if not isLocked() then
			Remotes.SelectAgent:FireServer(myAgent().Id, true)
		end
		confirmed = true
	end)
	confirm.Label.Size = UDim2.new(1, 0, 0, 42)
	confirm.Label.Position = UDim2.fromOffset(0, 4)
	confirmSub = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 42), Size = UDim2.new(1, -16, 0, 14),
		Text = "", TextSize = 10, Font = F.Display, TextColor3 = C.PrimaryText, TextXAlignment = Enum.TextXAlignment.Center },
		confirm.Face)
end

local function build()
	gui = make("ScreenGui", { Name = "AgentSelect", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 5, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	local background = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(5, 6, 8),
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

	-- Keine Abdunklung mehr (sie lag nur auf der 1600x900-Fläche und wirkte als Kasten): alles transparent,
	-- Texte direkt auf der Szene bekommen stattdessen eine leichte Kontur (siehe buildHeader)
	buildHeader()
	buildLeft()
	buildRight()
	buildBottom()
end

-- ---------- Team links ----------

-- Spieler und Bots im eigenen Team: { Name, Agent, Locked, IsMe, IsBot, Player }
local function teamEntries()
	local list = {}
	if not player.Team then
		return list
	end
	for _, p in Players:GetPlayers() do
		if p.Team == player.Team and p:GetAttribute("Mode") == player:GetAttribute("Mode") then
			table.insert(list, { Name = p.Name, Agent = AgentConfig.Get(p:GetAttribute("Agent")),
				Locked = p:GetAttribute("AgentLocked") == true, IsMe = p == player, Player = p })
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
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, e in entries do
		local slot = UITheme.Panel({ Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 0.12, LayoutOrder = i }, teamFrame)
		slot:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, UITheme.Radius.Large)
		if e.IsMe then
			slot:FindFirstChildOfClass("UIStroke").Color = C.Primary
		end
		local pictureBack = make("Frame", { Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = C.Background, BorderSizePixel = 0, ClipsDescendants = true }, slot)
		UITheme.Corner(pictureBack, UITheme.Radius.Medium)
		if e.Agent and (e.Locked or e.IsMe) then
			local portrait = HUDIcons.Portrait(pictureBack, 38)
			portrait.Set(e.Agent.Id, e.Player)
		end
		label({ Position = UDim2.fromOffset(52, 5), Size = UDim2.new(1, -60, 0, 20), Text = e.IsMe and "Du" or e.Name, TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd }, slot)
		local agentName = e.Agent and (e.Locked or e.IsMe) and e.Agent.Name or "—"
		local status = e.IsBot and "BOT" or (e.Locked and "BESTÄTIGT" or "WÄHLT ...")
		local statusColor = (e.IsBot or e.Locked) and C.Accent or C.Muted
		label({ Position = UDim2.fromOffset(52, 25), Size = UDim2.new(1, -60, 0, 16), RichText = true, TextSize = 11, Font = F.Bold,
			TextColor3 = C.Muted, Text = string.format('%s · <font color="#%s">%s</font>', agentName, statusColor:ToHex(), status) }, slot)
	end
end

-- ---------- Waffen und Ausrüstung links ----------

local function setCardWeapon(card, weapon, skin)
	card.Weapon = weapon
	card.Frame.Visible = weapon ~= nil
	if not weapon then
		return
	end
	local config = WeaponConfig.Get(weapon)
	card.Name.Text = upper(config and config.DisplayName or weapon)
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
			card.Stroke.Color = selected and C.Primary or (hoverWeapon == weapon and C.Muted or C.Border)
			card.Stroke.Thickness = selected and 2 or 1
			card.Tag.Text = selected and "GEWÄHLT" or "WÄHLEN"
			card.Tag.TextColor3 = selected and C.Primary or C.Muted
		end
	end
	local secondary = loadout[2]
	setCardWeapon(weaponCards[3], secondary, secondary and Cosmetics.WeaponSkin(player, agent.Id, secondary))
	weaponCards[3].Tag.Text = "SEKUNDÄRWAFFE"
end

local function updateEquipment(phase, respawning)
	local money = player:GetAttribute("Money")
	moneyLabel.Text = money and (UITheme.FormatNumber(money) .. " $") or ""
	local canBuy = phase == "Select" or phase == "Countdown" or respawning
	for item, entry in buyCards do
		if BuyConfig.Has(player, item.Id) then
			entry.State.Text = "GEKAUFT"
			entry.State.TextColor3 = C.Good
			entry.Stroke.Color = C.Good
		elseif not canBuy or money == nil then
			entry.State.Text = item.Price .. " $"
			entry.State.TextColor3 = C.Muted
			entry.Stroke.Color = item.Perk and PURPLE or C.Border
		else
			entry.State.Text = item.Price .. " $"
			entry.State.TextColor3 = money >= item.Price and C.Primary or C.Bad
			entry.Stroke.Color = item.Perk and PURPLE or C.Border
		end
	end
end

local function refreshTiles()
	local chosen = myAgent()
	for agent, entry in tiles do
		local unlocked = AgentConfig.IsUnlocked(player, agent.Id)
		local active = agent == chosen
		entry.Chunky.SetStroke(active and C.Primary or (hoverAgent == agent and C.Muted or C.Border), active and 2 or 1)
		entry.Level.Text = tostring(AgentConfig.LevelFromXP(AgentConfig.GetXP(player, agent.Id)))
		entry.Lock.Visible = not unlocked
		entry.Portrait.Frame.ImageTransparency = unlocked and 0 or 0.55
		entry.Strip.TextColor3 = active and C.Primary or C.Text
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

local function setTimer(seconds, urgentColor)
	if seconds == nil then
		timerLabel.Text = "–:––"
		timerLabel.TextColor3 = C.Muted
		timerStroke.Color = C.Border
		timerIcon.TextColor3 = C.Muted
		return
	end
	local urgent = seconds <= URGENT
	timerLabel.Text = formatClock(seconds)
	timerLabel.TextColor3 = urgent and (urgentColor or C.Bad) or C.Text
	timerStroke.Color = urgent and (urgentColor or C.Bad) or C.Border
	timerIcon.TextColor3 = urgent and (urgentColor or C.Bad) or C.Primary
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

	-- Kopfzeile, Timer, Stand
	local mapName = player:GetAttribute("MapName")
	headerInfo.Text = upper(modeInfo.Name .. "  ·  " .. modeInfo.Tag .. (mapName and ("  ·  MAP: " .. mapName) or ""))
	local ours, theirs = player:GetAttribute("TeamScore") or 0, player:GetAttribute("EnemyScore") or 0
	scoreLabel.Text = string.format('RUNDE %d   <font color="#%s">WIR %d</font> : <font color="#%s">%d GEGNER</font>',
		player:GetAttribute("RoundNumber") or 1, C.Accent:ToHex(), ours, C.Bad:ToHex(), theirs)
	if respawning then
		headerTitle.Text = "ZURÜCK INS GEFECHT"
		headerSub.Text = "AUSGESCHALTET – AGENT, WAFFE UND AUSRÜSTUNG WÄHLEN, DANN BEREIT"
		headerSub.TextColor3 = C.Primary
		setTimer(respawn.Left, C.Primary)
	elseif phase == "Select" then
		headerTitle.Text = "WÄHLE DEINEN AGENTEN"
		headerSub.Text = "RUNDE " .. (player:GetAttribute("RoundNumber") or 1) .. "  ·  AGENT, WAFFE UND AUSRÜSTUNG WÄHLEN"
		headerSub.TextColor3 = C.Text
		setTimer(math.max(0, (player:GetAttribute("SelectUntil") or 0) - workspace:GetServerTimeNow()))
	elseif phase == "Waiting" then
		headerTitle.Text = "WÄHLE DEINEN AGENTEN"
		headerSub.Text = upper(player:GetAttribute("ModeText") or "Warte auf Spieler ...")
		headerSub.TextColor3 = C.Muted
		setTimer(nil)
	else
		headerTitle.Text = "NÄCHSTE RUNDE"
		headerSub.Text = "RUNDE LÄUFT – DU STEIGST IN DER NÄCHSTEN RUNDE EIN"
		headerSub.TextColor3 = C.Muted
		setTimer(nil)
	end

	-- Bestätigen-Knopf
	if respawning then
		if isLocked() then
			confirm.SetText("BEREIT")
			confirmSub.Text = "GLEICH GEHT'S LOS"
			confirm.SetColor(C.Good, C.PrimaryText)
		else
			confirm.SetText("BEREIT")
			confirmSub.Text = respawn.ReadyIn > 0 and ("IN " .. math.ceil(respawn.ReadyIn) .. " S ZURÜCK") or "ZURÜCK INS GEFECHT"
			confirm.SetColor(C.Primary, C.PrimaryText)
		end
	elseif isLocked() then
		confirm.SetText("BESTÄTIGT")
		confirmSub.Text = "WARTE AUF DIE ANDEREN"
		confirm.SetColor(C.Good, C.PrimaryText)
	elseif phase == "Select" or phase == "Waiting" then
		confirm.SetText("BESTÄTIGEN")
		confirmSub.Text = "AGENT FESTLEGEN"
		confirm.SetColor(C.Primary, C.PrimaryText)
	else
		confirm.SetText("BESTÄTIGEN")
		confirmSub.Text = "UND ZUSCHAUEN"
		confirm.SetColor(C.Primary, C.PrimaryText)
	end
	confirmSub.TextColor3 = C.PrimaryText

	local agent = myAgent()
	local previewAgent = hoverAgent or agent
	-- Vorschau: überfahrene Primärwaffe, sonst die gewählte des gezeigten Agenten
	local weapon = (previewAgent == agent and hoverWeapon) or AgentConfig.LoadoutFor(player, previewAgent.Id)[1]
	showPreview(previewAgent, weapon)
	updateWeapons(agent)
	updateEquipment(phase, respawning)
	refreshTiles()
	updateTeam()
end

function AgentSelect.Init()
	build()

	-- Rückmeldung beim Kaufen
	Remotes.ShopStatus.OnClientEvent:Connect(function(message, success)
		buyStatus.Text = message
		buyStatus.TextColor3 = success and C.Good or C.Bad
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
	-- Neue Auswahl nach dem Tod: ab jetzt zählt die Todeskamera
	player:GetAttributeChangedSignal("RespawnAt"):Connect(function()
		if type(player:GetAttribute("RespawnAt")) == "number" then
			respawnSince = os.clock()
		end
	end)
	-- Level/XP/Skins geändert: 3D-Figur, Info und Vorschauen neu aufbauen
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 3) == "XP_" or name == "Equipped" or name == "Owned" or name == "Loadouts" then
			figureKey = nil
			for _, card in weaponCards do
				card.Shown = nil
			end
			for agent, entry in tiles do
				entry.Portrait.Set(agent.Id, player)
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

-- HUD (ModuleScript, nur Client)
-- Leben, Munition, Kills, Schadens-Effekt, Killfeed, Modus-Info und Meldungen.
-- Fadenkreuz, Hitmarker, Schadenszahlen, Treffer-Richtung und Kill-Meldung: CombatHUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local UITheme = require(Shared.UITheme)
local Movement = require(Shared.Movement)
local BuyConfig = require(Shared.BuyConfig)
local LevelConfig = require(Shared.LevelConfig)
local InputActions = require(Shared.InputActions)
local CombatHUD = require(Shared.CombatHUD)

local player = Players.LocalPlayer

local HUD = {}

local KILLFEED_MAX = 5        -- maximale Einträge im Killfeed
local KILLFEED_TIME = 5       -- Sekunden, die ein Eintrag sichtbar bleibt
local ANNOUNCE_TIME = 3       -- Sekunden für große Meldungen

local screen -- ScreenGui (an/aus)
local gui    -- skalierte Vollbild-Ebene darin (alle HUD-Elemente)
local statusLabel

-- Kleiner Helfer: Instanz mit Eigenschaften erzeugen
local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

-- Weißer Text mit Umrandung, ohne Hintergrund
local function label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextStrokeTransparency = 0.5
	return make("TextLabel", props, parent)
end

-- Text unter dem Fadenkreuz setzen (leerer Text = ausblenden), z.B. "Du schaust X zu"
function HUD.SetStatus(text: string)
	if statusLabel then
		statusLabel.Text = text
		statusLabel.Visible = text ~= ""
	end
end

function HUD.Init(weaponClient)
	-- Roblox-Standard-UI ausblenden, die wir selbst ersetzen
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	screen = make("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = true }, player:WaitForChild("PlayerGui"))
	gui = UITheme.ScaledRoot(screen) -- auf Handys kleiner

	-- Halbtransparente dunkle Fläche mit Verlauf (Grundbaustein des HUD)
	local function hudPanel(props)
		props.BackgroundColor3 = UITheme.Colors.Panel
		props.BackgroundTransparency = props.BackgroundTransparency or 0.15
		props.BorderSizePixel = 0
		local frame = make("Frame", props, gui)
		UITheme.Corner(frame, 4)
		UITheme.Stroke(frame, UITheme.Colors.Border, 1, 0.2)
		UITheme.Gradient(frame, Color3.fromRGB(30, 46, 70), UITheme.Colors.Panel)
		return frame
	end

	-- ---------- Agent + Leben unten links (Porträt, Name, große Zahl, Segment-Balken, Rüstung) ----------
	local healthPanel = hudPanel({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.new(0, 390, 0, 84) })
	local portrait = make("Frame", { Position = UDim2.new(0, 10, 0, 10), Size = UDim2.new(0, 64, 0, 64),
		BackgroundColor3 = UITheme.Colors.Accent, BorderSizePixel = 0 }, healthPanel)
	UITheme.Corner(portrait, 4)
	UITheme.Gradient(portrait, Color3.new(1, 1, 1), Color3.fromRGB(110, 110, 120))
	local portraitLetter = label({ Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 42, Font = Enum.Font.Oswald,
		TextXAlignment = Enum.TextXAlignment.Center }, portrait)
	local agentName = label({ Position = UDim2.new(0, 86, 0, 6), Size = UDim2.new(1, -96, 0, 18), Text = "",
		TextSize = 15, Font = Enum.Font.Oswald, TextXAlignment = Enum.TextXAlignment.Left }, healthPanel)
	local healthText = label({ Position = UDim2.new(0, 86, 0, 24), Size = UDim2.new(0, 76, 0, 50), Text = "100",
		TextSize = 44, Font = Enum.Font.Oswald, TextXAlignment = Enum.TextXAlignment.Left }, healthPanel)
	local healthBack = make("Frame", { Position = UDim2.new(0, 168, 0, 52), Size = UDim2.new(1, -182, 0, 14),
		BackgroundColor3 = UITheme.Colors.Background, BorderSizePixel = 0 }, healthPanel)
	local healthFill = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = UITheme.Colors.Text,
		BorderSizePixel = 0 }, healthBack)
	-- Segmente wie bei RC (alle 25 Leben ein Strich)
	for k = 1, 3 do
		make("Frame", { Position = UDim2.new(k / 4, -1, 0, 0), Size = UDim2.new(0, 3, 1, 0),
			BackgroundColor3 = UITheme.Colors.Panel, BorderSizePixel = 0, ZIndex = 2 }, healthBack)
	end
	-- Rüstung (gekauft in der Kaufphase) als blauer Balken über dem Leben
	local armorBack = make("Frame", { Position = UDim2.new(0, 168, 0, 38), Size = UDim2.new(1, -182, 0, 8),
		BackgroundColor3 = UITheme.Colors.Background, BorderSizePixel = 0, Visible = false }, healthPanel)
	local armorFill = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(80, 170, 255),
		BorderSizePixel = 0 }, armorBack)

	-- Agent des aktuellen Lebens anzeigen
	task.spawn(function()
		while true do
			local character = player.Character
			local agent = AgentConfig.Get(character and character:GetAttribute("Agent")) or AgentConfig.Get(player:GetAttribute("Agent"))
			if agent then
				portrait.BackgroundColor3 = agent.Color
				portraitLetter.Text = string.sub(agent.Name, 1, 1)
				agentName.Text = string.upper(agent.Name) .. "  ·  " .. string.upper(agent.Role)
				agentName.TextColor3 = agent.Color
			end
			task.wait(0.5)
		end
	end)

	-- ---------- Munition unten rechts (große Magazinzahl, Reserve klein) ----------
	local ammoPanel = hudPanel({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.new(0, 300, 0, 74) })
	local weaponText = label({ Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 18), Text = "",
		TextSize = 14, TextColor3 = UITheme.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Left }, ammoPanel)
	local ammoText = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 14), Size = UDim2.new(0, 120, 0, 52),
		Text = "", TextSize = 46, Font = Enum.Font.Oswald, TextXAlignment = Enum.TextXAlignment.Right }, ammoPanel)
	local reserveText = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 34), Size = UDim2.new(0, 66, 0, 26),
		Text = "", TextSize = 20, TextColor3 = UITheme.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Left }, ammoPanel)
	-- Magazin als dünner Balken unten im Panel
	local magBack = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -10),
		Size = UDim2.new(0, 120, 0, 4), BackgroundColor3 = UITheme.Colors.Background, BorderSizePixel = 0 }, ammoPanel)
	local magFill = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = UITheme.Colors.Accent,
		BorderSizePixel = 0 }, magBack)
	-- Hinweis bei fast leerem Magazin
	local reloadHint = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 90),
		Size = UDim2.new(0, 300, 0, 24), Text = "", TextSize = 18, Font = Enum.Font.Oswald,
		TextColor3 = UITheme.Colors.Bad, TextXAlignment = Enum.TextXAlignment.Center, Visible = false }, gui)

	-- Geld in Team-Modi (über der Munition) und kurze Meldung "+200 $"
	local moneyText = label({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -106),
		Size = UDim2.new(0, 260, 0, 28), Text = "", TextSize = 22, Font = Enum.Font.Oswald,
		TextColor3 = Color3.fromRGB(120, 230, 140), TextXAlignment = Enum.TextXAlignment.Right, Visible = false }, gui)

	-- Eigene Kills oben links (neben den Roblox-Knöpfen)
	local killsPanel = hudPanel({ Position = UDim2.new(0, 24, 0, 60), Size = UDim2.new(0, 110, 0, 36) })
	local killsText = label({ Size = UDim2.new(1, 0, 1, 0), Text = "☠ 0", TextSize = 20, Font = Enum.Font.Oswald,
		TextXAlignment = Enum.TextXAlignment.Center }, killsPanel)

	-- Modus-Info oben mittig als Banner (Text kommt vom Server als Spieler-Attribut "ModeText")
	local modeBanner = hudPanel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0, 0, 0, 38), AutomaticSize = Enum.AutomaticSize.X })
	make("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }, modeBanner)
	local modeText = label({ Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 18,
		Font = Enum.Font.Oswald, TextXAlignment = Enum.TextXAlignment.Center }, modeBanner)

	-- Roter Bildschirm-Effekt bei Schaden (ganz unten, damit er nichts verdeckt)
	local damageFlash = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(200, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 0,
	}, gui)
	make("UIGradient", {
		-- Mitte durchsichtig, Ränder rot
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.85),
			NumberSequenceKeypoint.new(0.7, 0.85),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, damageFlash)

	-- Fadenkreuz, Hitmarker, Schadenszahlen, Treffer-Richtung, Kill-Meldung, Nachlade-Balken
	CombatHUD.Init(gui, weaponClient)

	statusLabel = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 60),
		Size = UDim2.new(0, 500, 0, 30),
		Text = "",
		TextSize = 22,
		Visible = false,
	}, gui)

	-- Große Meldung (Rundenstart, Sieger)
	local announce = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.26, 0),
		Size = UDim2.new(0, 0, 0, 64),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 40,
		Font = Enum.Font.Oswald,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		BackgroundTransparency = 0.3,
		BackgroundColor3 = Color3.fromRGB(10, 13, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	}, gui)
	UITheme.Corner(announce, 12)
	make("UIPadding", { PaddingLeft = UDim.new(0, 36), PaddingRight = UDim.new(0, 36) }, announce)
	make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, 72, 0, 3),
		BackgroundColor3 = UITheme.Colors.Accent, BorderSizePixel = 0 }, announce)

	-- Killfeed oben rechts
	local killfeed = make("Frame", {
		Position = UDim2.new(1, -420, 0, 20),
		Size = UDim2.new(0, 400, 0, 200),
		BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 4),
	}, killfeed)

	-- Leben: bei jedem Spawn neu verbinden
	local function trackCharacter(character)
		local humanoid = character:WaitForChild("Humanoid")
		local lastHealth = humanoid.Health
		local function update()
			local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			healthFill.Size = UDim2.new(ratio, 0, 1, 0)
			healthText.Text = tostring(math.max(0, math.ceil(humanoid.Health)))
			healthFill.BackgroundColor3 = ratio < 0.3 and UITheme.Colors.Bad or UITheme.Colors.Text
			-- Getroffen: roter Rand blitzt auf, bei wenig Leben bleibt er leicht sichtbar
			local resting = ratio < 0.3 and humanoid.Health > 0 and 0.75 or 1
			if humanoid.Health < lastHealth then
				damageFlash.BackgroundTransparency = 0.45
				TweenService:Create(damageFlash, TweenInfo.new(0.5), { BackgroundTransparency = resting }):Play()
			else
				damageFlash.BackgroundTransparency = resting
			end
			lastHealth = humanoid.Health
		end
		update()
		humanoid.HealthChanged:Connect(update)

		local function updateArmor()
			local armor = character:GetAttribute("Armor") or 0
			armorBack.Visible = armor > 0
			armorFill.Size = UDim2.new(math.clamp(armor / BuyConfig.ArmorAmount, 0, 1), 0, 1, 0)
		end
		updateArmor()
		character:GetAttributeChangedSignal("Armor"):Connect(updateArmor)
	end
	player.CharacterAdded:Connect(trackCharacter)
	if player.Character then
		task.spawn(trackCharacter, player.Character)
	end

	-- Kills aus leaderstats
	task.spawn(function()
		local kills = player:WaitForChild("leaderstats"):WaitForChild("Kills")
		local function update()
			killsText.Text = "☠ " .. kills.Value
		end
		update()
		kills.Changed:Connect(update)
	end)

	-- Modus-Text
	local function updateMode()
		modeText.Text = player:GetAttribute("ModeText") or ""
	end
	updateMode()
	player:GetAttributeChangedSignal("ModeText"):Connect(updateMode)

	-- Eroberungspunkt (Strikeout): Fortschritt beider Teams unter der Modus-Info
	local objective = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.new(0, 420, 0, 52),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local function objectiveBar(y, color, title)
		label({ Position = UDim2.new(0, 0, 0, y), Size = UDim2.new(0, 70, 0, 14), Text = title, TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left }, objective)
		local back = make("Frame", { Position = UDim2.new(0, 75, 0, y + 2), Size = UDim2.new(1, -75, 0, 10),
			BackgroundColor3 = Color3.fromRGB(30, 30, 35), BackgroundTransparency = 0.2, BorderSizePixel = 0 }, objective)
		return make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
	end
	local mineBar = objectiveBar(0, Color3.fromRGB(80, 200, 255), "WIR")
	local enemyBar = objectiveBar(16, Color3.fromRGB(255, 80, 80), "GEGNER")
	local objectiveInfo = label({ Position = UDim2.new(0, 0, 0, 32), Size = UDim2.new(1, 0, 0, 20), Text = "",
		TextSize = 15 }, objective)
	local function updateObjective()
		local mine = player:GetAttribute("ObjMine")
		local info = player:GetAttribute("ObjInfo")
		objective.Visible = mine ~= nil or info ~= nil
		-- Balken nur mit Punkt-Fortschritt (Strikeout), sonst nur die Statuszeile (Demolition)
		for _, child in objective:GetChildren() do
			if child ~= objectiveInfo then
				child.Visible = mine ~= nil
			end
		end
		mineBar.Size = UDim2.new(mine or 0, 0, 1, 0)
		enemyBar.Size = UDim2.new(player:GetAttribute("ObjEnemy") or 0, 0, 1, 0)
		objectiveInfo.Text = info or ""
	end
	updateObjective()
	player:GetAttributeChangedSignal("ObjMine"):Connect(updateObjective)
	player:GetAttributeChangedSignal("ObjEnemy"):Connect(updateObjective)
	player:GetAttributeChangedSignal("ObjInfo"):Connect(updateObjective)

	-- ---------- Team-Rauten oben (wie bei RC): eigenes Team links, Gegner rechts ----------
	local teamBar = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(0, 700, 0, 30), BackgroundTransparency = 1, Visible = false }, gui)
	local function side(anchorX, alignment)
		local frame = make("Frame", { AnchorPoint = Vector2.new(anchorX, 0), Position = UDim2.new(anchorX, 0, 0, 0),
			Size = UDim2.new(0.5, -10, 1, 0), BackgroundTransparency = 1 }, teamBar)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = alignment,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
		return frame
	end
	local mineSide = side(0, Enum.HorizontalAlignment.Right)
	local enemySide = side(1, Enum.HorizontalAlignment.Left)

	-- Zustand eines Modells: "alive", "downed" oder "dead"
	local function stateOf(model)
		local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return "dead"
		end
		return model:GetAttribute("Downed") and "downed" or "alive"
	end

	local function renderSide(frame, entries, color)
		for _, child in frame:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i, state in entries do
			local holder = make("Frame", { Size = UDim2.new(0, 22, 0, 22), BackgroundTransparency = 1, LayoutOrder = i }, frame)
			local fill = state == "alive" and color or (state == "downed" and Color3.fromRGB(255, 170, 40) or Color3.fromRGB(30, 34, 44))
			UITheme.Diamond(holder, 15, UDim2.new(0.5, 0, 0.5, 0), fill, color)
			if state == "dead" then
				label({ Size = UDim2.new(1, 0, 1, 0), Text = "✕", TextSize = 13, TextColor3 = color,
					TextXAlignment = Enum.TextXAlignment.Center }, holder)
			end
		end
	end

	task.spawn(function()
		while true do
			local mode = player:GetAttribute("Mode")
			local inTeamMode = Modes.IsTeamMode(mode) and player.Team ~= nil and player:GetAttribute("RoundPhase") == "Round"
			teamBar.Visible = inTeamMode
			if inTeamMode then
				local mine, enemies = {}, {}
				for _, p in Players:GetPlayers() do
					if p:GetAttribute("Mode") == mode and p.Team then
						table.insert(p.Team == player.Team and mine or enemies, stateOf(p.Character))
					end
				end
				local bots = workspace:FindFirstChild("Bots")
				if bots then
					for _, model in bots:GetChildren() do
						if model:GetAttribute("Mode") == mode then
							local isMate = model:GetAttribute("TeamName") == player.Team.Name
							table.insert(isMate and mine or enemies, stateOf(model))
						end
					end
				end
				-- Lebende zuerst, dann am Boden, dann ausgeschaltet
				local rank = { alive = 1, downed = 2, dead = 3 }
				table.sort(mine, function(a, b) return rank[a] < rank[b] end)
				table.sort(enemies, function(a, b) return rank[a] < rank[b] end)
				renderSide(mineSide, mine, UITheme.Colors.Accent)
				renderSide(enemySide, enemies, UITheme.Colors.Bad)
			end
			task.wait(0.3)
		end
	end)

	-- ---------- Kompass oben (Blickrichtung) ----------
	local COMPASS_WIDTH, PX_PER_DEGREE = 440, 2.4
	local compass = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.new(0, COMPASS_WIDTH, 0, 22), BackgroundColor3 = Color3.fromRGB(10, 13, 22), BackgroundTransparency = 0.45,
		ClipsDescendants = true, BorderSizePixel = 0 }, gui)
	UITheme.Corner(compass, 3)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.2), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, compass)
	local marks = {}
	local names = { [0] = "N", [45] = "NO", [90] = "O", [135] = "SO", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }
	for degree = 0, 345, 15 do
		local isMain = names[degree] ~= nil
		local mark = label({ AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 40, 1, 0),
			Text = isMain and names[degree] or "|", TextSize = isMain and 15 or 9,
			TextColor3 = degree % 90 == 0 and UITheme.Colors.Accent or Color3.fromRGB(200, 210, 225),
			TextXAlignment = Enum.TextXAlignment.Center }, compass)
		table.insert(marks, { Label = mark, Degree = degree })
	end
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0, 2, 0, 6),
		BackgroundColor3 = UITheme.Colors.Accent, BorderSizePixel = 0 }, compass)
	local headingText = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 116), Size = UDim2.new(0, 60, 0, 12),
		Text = "", TextSize = 11, TextColor3 = UITheme.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Center }, gui)
	game:GetService("RunService").RenderStepped:Connect(function()
		if not screen.Enabled then
			return
		end
		local look = workspace.CurrentCamera.CFrame.LookVector
		-- Norden = -Z (wie üblich in Roblox), Grad im Uhrzeigersinn
		local heading = (math.deg(math.atan2(look.X, -look.Z)) + 360) % 360
		headingText.Text = tostring(math.floor(heading + 0.5)) .. "°"
		for _, mark in marks do
			local delta = ((mark.Degree - heading + 180) % 360) - 180
			mark.Label.Position = UDim2.new(0.5, delta * PX_PER_DEGREE, 0.5, 0)
			mark.Label.Visible = math.abs(delta * PX_PER_DEGREE) < COMPASS_WIDTH / 2 + 20
		end
	end)

	-- ---------- Großer Countdown vor Rundenbeginn (3, 2, 1, LOS!) ----------
	local countdown = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 300, 0, 160), Text = "", TextSize = 150, Font = Enum.Font.Oswald,
		TextColor3 = UITheme.Colors.Accent, TextXAlignment = Enum.TextXAlignment.Center, Visible = false }, gui)
	local countdownScale = make("UIScale", {}, countdown)
	local lastShown = nil
	game:GetService("RunService").Heartbeat:Connect(function()
		local finish = player:GetAttribute("CountdownEnd")
		local phase = player:GetAttribute("RoundPhase")
		if not finish or not Modes.IsTeamMode(player:GetAttribute("Mode")) then
			countdown.Visible = false
			return
		end
		local left = finish - workspace:GetServerTimeNow()
		local text
		if phase == "Countdown" and left > 0 then
			text = tostring(math.ceil(left))
		elseif phase == "Round" and left > -1 then
			text = "LOS!"
		end
		countdown.Visible = text ~= nil
		if text and text ~= lastShown then
			lastShown = text
			countdown.Text = text
			countdown.TextColor3 = text == "LOS!" and UITheme.Colors.Play or UITheme.Colors.Accent
			-- kurzer "Puls" bei jeder neuen Zahl
			countdownScale.Scale = 1.4
			TweenService:Create(countdownScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)

	-- Touch-Geräte: links unten liegt der Steuerknüppel, rechts unten die Knöpfe. Darum Leben nach
	-- oben links und Munition über die Fähigkeiten-Leiste in die Mitte.
	local function layoutForDevice()
		if InputActions.IsTouch() then
			healthPanel.AnchorPoint = Vector2.new(0, 0)
			healthPanel.Position = UDim2.new(0, 24, 0, 104)
			ammoPanel.AnchorPoint = Vector2.new(0.5, 1)
			ammoPanel.Position = UDim2.new(0.5, 0, 1, -170)
			moneyText.Position = UDim2.new(0.5, 130, 1, -250)
		else
			healthPanel.AnchorPoint = Vector2.new(0, 1)
			healthPanel.Position = UDim2.new(0, 24, 1, -24)
			ammoPanel.AnchorPoint = Vector2.new(1, 1)
			ammoPanel.Position = UDim2.new(1, -24, 1, -24)
			moneyText.Position = UDim2.new(1, -28, 1, -106)
		end
	end
	layoutForDevice()
	InputActions.DeviceChanged:Connect(layoutForDevice)

	-- HUD nur in Kampfmodi zeigen, nicht im Hub
	local function updateVisible()
		screen.Enabled = Modes.IsFighting(player)
	end
	updateVisible()
	player:GetAttributeChangedSignal("Mode"):Connect(updateVisible)

	-- Munition (im Schießstand unendliche Reserve: "∞")
	weaponClient.AmmoChanged:Connect(function(name, mag, reserve, reloading, magSize, infinite)
		ammoText.Text = tostring(mag)
		ammoText.TextColor3 = mag == 0 and UITheme.Colors.Bad or Color3.new(1, 1, 1)
		local config = WeaponConfig.Get(name)
		local size = magSize or (config and config.MagazineSize) or math.max(mag, 1)
		local ratio = math.clamp(mag / math.max(size, mag, 1), 0, 1)
		magFill.Size = UDim2.new(ratio, 0, 1, 0)
		magFill.BackgroundColor3 = ratio <= 0.25 and UITheme.Colors.Bad or UITheme.Colors.Accent
		-- Nachladen-Hinweis mit Taste des aktuellen Geräts
		local key = InputActions.Hint("Reload")
		reloadHint.Visible = not reloading and ratio <= 0.25 and (reserve > 0 or infinite == true)
		reloadHint.Text = mag == 0 and ((key ~= "" and ("[" .. key .. "] ") or "") .. "NACHLADEN")
			or ((key ~= "" and ("[" .. key .. "] ") or "") .. "WENIG MUNITION")
		reserveText.Text = infinite and "/ ∞" or ("/ " .. reserve)
		local displayName = WeaponConfig.Get(name).DisplayName
		weaponText.Text = string.upper(reloading and (displayName .. " · lädt nach...") or displayName)
	end)

	-- Killfeed-Einträge
	local entryCount = 0
	Remotes.Killfeed.OnClientEvent:Connect(function(killerName, victimName, weaponName, headshot)
		entryCount += 1
		local weapon = WeaponConfig.Get(weaponName)
		local weaponLabel = weapon and weapon.DisplayName or tostring(weaponName or "")
		local function colored(name)
			local color = name == player.Name and "#28D2E6" or "#FFFFFF"
			return '<font color="' .. color .. '">' .. name .. "</font>"
		end
		local text = colored(killerName) .. '  <font color="#9AA3BA">[' .. weaponLabel
			.. (headshot and " · ⊕" or "") .. "]</font>  " .. colored(victimName)
		local involvesMe = killerName == player.Name or victimName == player.Name
		local entry = label({
			Size = UDim2.new(0, 0, 0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "   " .. text .. "   ",
			RichText = true,
			TextSize = 16,
			BackgroundColor3 = involvesMe and Color3.fromRGB(28, 62, 78) or UITheme.Colors.Panel,
			BackgroundTransparency = 0.2,
			TextXAlignment = Enum.TextXAlignment.Right,
			LayoutOrder = entryCount,
		}, killfeed)
		UITheme.Corner(entry, 3)
		-- Älteste Einträge entfernen
		local entries = {}
		for _, child in killfeed:GetChildren() do
			if child:IsA("TextLabel") then
				table.insert(entries, child)
			end
		end
		table.sort(entries, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #entries - KILLFEED_MAX do
			entries[i]:Destroy()
		end
		task.delay(KILLFEED_TIME, function()
			entry:Destroy()
		end)
	end)

	-- XP-Meldung über der Fähigkeits-Box ("+100 XP · Kill"), Level-Up groß
	local xpText = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 124), -- unter dem Fadenkreuz, frei von Fähigkeiten-Leiste und Touch-Knöpfen
		Size = UDim2.new(0, 400, 0, 30),
		Text = "",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(120, 230, 140),
		Visible = false,
	}, gui)
	local xpId = 0
	Remotes.XPGain.OnClientEvent:Connect(function(amount, reason, agentId, levelUp, coins)
		xpId += 1
		local myId = xpId
		xpText.Text = "+" .. amount .. " XP" .. ((coins or 0) > 0 and ("  +" .. coins .. " 💰") or "") .. "  ·  " .. tostring(reason)
		xpText.Visible = true
		task.delay(2, function()
			if xpId == myId then
				xpText.Visible = false
			end
		end)
		local agent = AgentConfig.Get(agentId)
		if levelUp and agent then
			local level = AgentConfig.LevelFromXP(AgentConfig.GetXP(player, agentId))
			local skin = AgentConfig.SkinForLevel(level)
			local message = agent.Name .. " ist jetzt Level " .. level .. "!"
			if skin and skin.Level == level then
				message ..= "  " .. skin.Name .. "-Skin freigeschaltet!"
			end
			HUD.ShowAnnouncement(message)
		end
	end)

	-- Geld (nur während eines Drop-Matches)
	local function updateMoney()
		local money = player:GetAttribute("Money")
		moneyText.Visible = money ~= nil
		moneyText.Text = money and ("💵 " .. money .. " $") or ""
	end
	updateMoney()
	player:GetAttributeChangedSignal("Money"):Connect(updateMoney)
	local moneyId = 0
	Remotes.MoneyGain.OnClientEvent:Connect(function(amount, reason)
		moneyId += 1
		local myId = moneyId
		moneyText.Text = "+" .. amount .. " $  ·  " .. tostring(reason)
		task.delay(1.5, function()
			if moneyId == myId then
				updateMoney()
			end
		end)
	end)

	-- Todesanzeige: wer hat dich ausgeschaltet
	local recap = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.7, 0),
		Size = UDim2.new(0, 440, 0, 74),
		BackgroundColor3 = Color3.fromRGB(20, 10, 12),
		BackgroundTransparency = 0.25,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, recap)
	make("UIStroke", { Color = Color3.fromRGB(220, 60, 60), Thickness = 1.5 }, recap)
	local recapTitle = label({ Position = UDim2.new(0, 16, 0, 8), Size = UDim2.new(1, -32, 0, 28), Text = "",
		TextSize = 20, TextColor3 = Color3.fromRGB(255, 90, 90), TextXAlignment = Enum.TextXAlignment.Left }, recap)
	local recapInfo = label({ Position = UDim2.new(0, 16, 0, 40), Size = UDim2.new(1, -32, 0, 22), Text = "",
		TextSize = 15, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left }, recap)
	local recapId = 0
	Remotes.DeathRecap.OnClientEvent:Connect(function(killerName, weaponName, killerHealth, agentId, killerModel)
		-- Todeskamera: 3 Sekunden auf den Killer schauen (Zuschauen übernimmt danach)
		local killerHumanoid = typeof(killerModel) == "Instance" and killerModel:FindFirstChildOfClass("Humanoid")
		if killerHumanoid then
			local camera = workspace.CurrentCamera
			camera:SetAttribute("KillCam", true)
			player.CameraMode = Enum.CameraMode.Classic
			player.CameraMinZoomDistance = 14
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = killerHumanoid
			task.delay(3, function()
				camera:SetAttribute("KillCam", nil)
				player.CameraMinZoomDistance = 0.5
				-- Schon wieder gespawnt: zurück zur eigenen Kamera
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					camera.CameraSubject = humanoid
					Movement.ApplyCamera()
				end
			end)
		end
		recapId += 1
		local myId = recapId
		local agent = agentId and AgentConfig.Get(agentId)
		recapTitle.Text = "AUSGESCHALTET VON " .. string.upper(tostring(killerName))
		recapInfo.Text = (agent and (agent.Name .. "  ·  ") or "") .. tostring(weaponName or "?")
			.. "  ·  hatte noch " .. tostring(killerHealth) .. " Leben"
		recap.Visible = true
		task.delay(4, function()
			if recapId == myId then
				recap.Visible = false
			end
		end)
	end)

	-- Große Meldungen
	-- Meldungen nacheinander zeigen: kommt eine neue, bleibt die aktuelle noch mindestens
	-- ANNOUNCE_MIN Sekunden stehen (z.B. "ACE!" und direkt danach "Team gewinnt die Runde")
	local ANNOUNCE_MIN = 1.6
	local queue = {}
	local running = false
	function HUD.ShowAnnouncement(text)
		table.insert(queue, text)
		if #queue > 4 then
			table.remove(queue, 1) -- nicht endlos stauen
		end
		if running then
			return
		end
		running = true
		task.spawn(function()
			while #queue > 0 do
				announce.Text = table.remove(queue, 1)
				announce.Visible = true
				local shown = 0
				while shown < ANNOUNCE_TIME and not (shown >= ANNOUNCE_MIN and #queue > 0) do
					shown += task.wait(0.1)
				end
			end
			announce.Visible = false
			running = false
		end)
	end
	Remotes.Announce.OnClientEvent:Connect(HUD.ShowAnnouncement)

	-- Spielerlevel gestiegen: große Meldung (Prestige setzt das Level zurück, das zählt nicht)
	local lastLevel, lastPrestige = LevelConfig.Get(player).Level, player:GetAttribute("Prestige") or 0
	player:GetAttributeChangedSignal("AccountXP"):Connect(function()
		local info = LevelConfig.Get(player)
		if info.Level > lastLevel and info.Prestige == lastPrestige then
			HUD.ShowAnnouncement("▲ LEVEL UP!  LV " .. info.Level)
		end
		lastLevel, lastPrestige = info.Level, info.Prestige
	end)
end

return HUD

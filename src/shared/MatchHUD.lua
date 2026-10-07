-- MatchHUD (ModuleScript, nur Client)
-- Match-Anzeige im nüchternen Taktik-Look (UITheme): dunkle, halbtransparente Flächen ohne Rahmen,
-- schmale Zahlen (Oswald), dünne Balken.
--   oben mittig:   Ziel ("HALTE DIE FLAGGEN"), Punktestand – eigenes Team blau links, Gegner rot rechts, in der
--                  Mitte Runde und Uhr (Tickets klein in den Kästen) –, darunter ein Kästchen pro Spieler (lebt =
--                  gefüllt, am Boden = orange, ausgeschaltet = leer) und eine Zeile mit dem Zustand des Ziels.
--                  Free-for-All: eigene Kills (blau), Ziel in der Mitte, Führender (Gold) mit Namen, die ersten drei
--   rechts oben:   Killfeed: dunkle Zeilen mit farbiger Kante rechts, Waffe als graue Schrift, eigene Kills mit
--                  Bernstein-Kante
--   unten links:   Porträt, Agentenname, Rüstung in 5 Segmenten, Leben als Zahl + Balken
--   unten rechts:  Waffen-Silhouette, Waffenplätze 1/2, Waffenname und Munition "30 / ∞"
--   in der Welt:   Zielmarker (Raute mit A/B, Entfernung in Metern, Zustand)
-- Daten: Spieler-Attribute vom Server (TeamRoundMode), Remotes.Killfeed, WeaponClient.AmmoChanged.
-- Fähigkeit/Gadget/Ultimate (Karten unten in der Mitte): AbilityClient. Minimap: Minimap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local AgentConfig = require(Shared.AgentConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local BuyConfig = require(Shared.BuyConfig)
local UITheme = require(Shared.UITheme)
local GameSettings = require(Shared.GameSettings)
local InputActions = require(Shared.InputActions)
local TeamCheck = require(Shared.TeamCheck)
local HUDIcons = require(Shared.HUDIcons)

local player = Players.LocalPlayer
local make = UITheme.Make
local C = UITheme.Colors
local F = UITheme.Fonts
local upper = UITheme.Upper

local MatchHUD = {}

local ALLY = C.Accent
local ENEMY = C.Bad
local DOWNED = Color3.fromRGB(214, 150, 60)
local ARMOR = C.Accent
local PANEL = C.Background
local MUTED = C.Muted
local WHITE = Color3.new(1, 1, 1)
local KILLFEED_TIME = 6        -- Sekunden pro Eintrag
local ARMOR_SEGMENTS = 5
local METERS_PER_STUD = 0.28
local ROUND_PHASES = { Countdown = true, Round = true, RoundEnd = true }
local SCORE_W, BOX_W, SCORE_H = 300, 74, 56 -- Punktestand oben

-- Text in der schmalen Schrift (klein: Gotham Bold) mit leichter dunkler Kante
local function label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or WHITE
	props.Font = UITheme.FontFor(props.Font or F.Display, props.TextSize)
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0.75
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	return make("TextLabel", props, parent)
end

local function hex(color)
	return color:ToHex()
end

local function formatClock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Aktueller Agent des eigenen Lebens
local function myAgent()
	local character = player.Character
	return AgentConfig.Get(character and character:GetAttribute("Agent")) or AgentConfig.Get(player:GetAttribute("Agent"))
end

-- Punktestand-Fläche: links und rechts farbige Kästen, Mitte für Runde und Uhr.
-- Gibt { Frame, Left, Right, LeftSub, RightSub, Top, Clock } zurück.
local function scoreWidget(parent, leftColor, rightColor, leftText, rightText)
	local card = make("Frame", { Name = "Score", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.fromOffset(SCORE_W, SCORE_H), BackgroundColor3 = PANEL, BackgroundTransparency = 0.3, BorderSizePixel = 0,
		ZIndex = 2 }, parent)
	UITheme.Corner(card, UITheme.Radius.Small)
	local function side(left, color, textColor)
		local box = make("Frame", { Position = left and UDim2.fromOffset(0, 0) or UDim2.new(1, -BOX_W, 0, 0),
			Size = UDim2.fromOffset(BOX_W, SCORE_H), BackgroundColor3 = color, BackgroundTransparency = 0.08, BorderSizePixel = 0,
			ZIndex = 3 }, card)
		UITheme.Corner(box, UITheme.Radius.Small)
		local value = label({ Position = UDim2.fromOffset(0, 1), Size = UDim2.new(1, 0, 0, 38), Text = "0", TextSize = 38,
			TextColor3 = textColor, TextStrokeTransparency = 1, ZIndex = 4 }, box)
		local sub = label({ Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 14), Text = "", TextSize = 9,
			Font = F.Bold, TextColor3 = textColor, TextStrokeTransparency = 1, ZIndex = 4 }, box)
		return value, sub
	end
	local leftValue, leftSub = side(true, leftColor, C.PrimaryText)
	local rightValue, rightSub = side(false, rightColor, rightColor == ENEMY and WHITE or C.PrimaryText)
	local topText = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(140, 14),
		Text = leftText or "", TextSize = 10, Font = F.Bold, TextColor3 = MUTED, TextStrokeTransparency = 1, ZIndex = 3 }, card)
	local clock = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), Size = UDim2.fromOffset(140, 32),
		Text = rightText or "", TextSize = 30, TextStrokeTransparency = 1, ZIndex = 3 }, card)
	return { Frame = card, Left = leftValue, Right = rightValue, LeftSub = leftSub, RightSub = rightSub, Top = topText, Clock = clock }
end

-- root = skalierte HUD-Ebene, weaponClient = WeaponClient-Modul.
-- Gibt { Vitals, Ammo, Killfeed, Top } zurück (für das Touch-Layout im HUD).
function MatchHUD.Init(root, weaponClient)
	local screen = root.Parent :: ScreenGui

	-- =====================================================================
	-- Oben: Ziel, Punktestand, Spieler-Kästchen, Zustand des Ziels
	-- =====================================================================
	local top = make("Frame", { Name = "TopBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(760, 150), BackgroundTransparency = 1 }, root)
	local goalText = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(700, 22),
		Text = "", TextSize = 18, TextStrokeTransparency = 0.6 }, top)
	local bar = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, top)
	local teamScore = scoreWidget(bar, ALLY, ENEMY)

	-- Kästchen pro Spieler: eigenes Team links (Cyan), Gegner rechts (rot)
	local function pipRow(anchorX, x, alignment)
		local row = make("Frame", { AnchorPoint = Vector2.new(anchorX, 0), Position = UDim2.new(0.5, x, 0, 26 + SCORE_H + 12),
			Size = UDim2.fromOffset(150, 14), BackgroundTransparency = 1 }, bar)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = alignment,
			Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		return row
	end
	local myPips = pipRow(1, -8, Enum.HorizontalAlignment.Right)
	local enemyPips = pipRow(0, 8, Enum.HorizontalAlignment.Left)

	-- Schild mit dem Zustand des Ziels ("A: ROT · B: FREI · C: BLAU")
	local statusChip = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26 + SCORE_H + 36),
		Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 11, TextColor3 = C.Text,
		BackgroundTransparency = 0.35, BackgroundColor3 = PANEL, TextStrokeTransparency = 1, Visible = false }, bar)
	UITheme.Corner(statusChip, UITheme.Radius.Small)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, statusChip)

	-- Free-for-All: eigene Kills (Cyan), Ziel in der Mitte, Führender (Gold) mit Namen, darunter die ersten drei
	local ffaBar = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, top)
	local ffaScore = scoreWidget(ffaBar, ALLY, C.Gold, "ZIEL", "")
	label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, -SCORE_W / 2 + BOX_W / 2, 0, 26 + SCORE_H + 10),
		Size = UDim2.fromOffset(120, 16), Text = "DU", TextSize = 12, TextColor3 = ALLY }, ffaBar)
	local ffaLeaderName = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, SCORE_W / 2 - BOX_W / 2, 0, 26 + SCORE_H + 10),
		Size = UDim2.fromOffset(220, 16), Text = "", TextSize = 12, TextColor3 = C.Gold }, ffaBar)
	local ffaRanking = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26 + SCORE_H + 34),
		Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = "", RichText = true, TextSize = 11,
		BackgroundTransparency = 0.35, BackgroundColor3 = PANEL, TextStrokeTransparency = 1, Visible = false }, ffaBar)
	UITheme.Corner(ffaRanking, UITheme.Radius.Small)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, ffaRanking)

	-- Rangliste im Free-for-All: Spieler (leaderstats) und Bots (BotInfo) im eigenen Modus, meiste Kills zuerst
	local function ffaStandings(mode)
		local list = {}
		for _, other in Players:GetPlayers() do
			if other:GetAttribute("Mode") == mode then
				local stats = other:FindFirstChild("leaderstats")
				local kills = stats and stats:FindFirstChild("Kills")
				table.insert(list, { Name = other.Name, Kills = kills and kills:IsA("IntValue") and kills.Value or 0,
					Me = other == player })
			end
		end
		local botInfo = ReplicatedStorage:FindFirstChild("BotInfo")
		if botInfo then
			for _, info in botInfo:GetChildren() do
				if info:GetAttribute("Mode") == mode then
					table.insert(list, { Name = info.Name, Kills = info:GetAttribute("Kills") or 0, Me = false })
				end
			end
		end
		table.sort(list, function(a, b)
			if a.Kills ~= b.Kills then
				return a.Kills > b.Kills
			end
			return a.Name < b.Name
		end)
		return list
	end

	local function updateFFA(mode)
		local target = GameSettings.Get("KillsToWin")
		ffaScore.Clock.Text = tostring(target)
		ffaScore.Top.Text = "ZIEL · KILLS"
		local list = ffaStandings(mode)
		local myRank, myKills = nil, 0
		for i, entry in list do
			if entry.Me then
				myRank, myKills = i, entry.Kills
			end
		end
		ffaScore.Left.Text = tostring(myKills)
		ffaScore.LeftSub.Text = myRank and (myRank .. ". PLATZ") or ""
		local leader = list[1]
		ffaScore.Right.Text = tostring(leader and leader.Kills or 0)
		ffaScore.RightSub.Text = "FÜHRT"
		ffaLeaderName.Text = leader and (leader.Me and "DU FÜHRST" or upper(leader.Name)) or ""
		local parts = {}
		for i = 1, math.min(3, #list) do
			local entry = list[i]
			local color = entry.Me and hex(ALLY) or (i == 1 and hex(C.Gold) or "D7E1EE")
			table.insert(parts, string.format('<font color="#%s">%d. %s  %d</font>', color, i, entry.Name, entry.Kills))
		end
		if myRank and myRank > 3 then
			table.insert(parts, string.format('<font color="#%s">DU: %d. PLATZ</font>', hex(ALLY), myRank))
		end
		ffaRanking.Text = table.concat(parts, "   ·   ")
		ffaRanking.Visible = #parts > 0
	end

	-- Kästchen für Spieler: lebt = gefüllt, am Boden = orange, ausgeschaltet = leer
	local function syncPips(row, entries, color)
		local pips = {}
		for _, child in row:GetChildren() do
			if child:IsA("Frame") then
				table.insert(pips, child)
			end
		end
		while #pips < #entries do
			local pip = make("Frame", { Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0, LayoutOrder = #pips + 1 }, row)
			UITheme.Corner(pip, 1)
			UITheme.Stroke(pip, color, 1)
			table.insert(pips, pip)
		end
		while #pips > #entries do
			local removed = table.remove(pips)
			if removed then
				removed:Destroy()
			end
		end
		for i, entry in entries do
			local pip = pips[i]
			local stroke = pip:FindFirstChildOfClass("UIStroke")
			local dead = entry.State == "dead"
			local downed = entry.State == "downed"
			pip.BackgroundColor3 = downed and DOWNED or color
			pip.BackgroundTransparency = dead and 1 or 0.1
			if stroke then
				stroke.Color = dead and MUTED or (entry.IsSelf and WHITE or (downed and DOWNED or color))
				stroke.Transparency = dead and 0.3 or 0
			end
		end
	end

	-- Zustand oben (5x pro Sekunde): Stand, Tickets, Ziel, Kästchen
	local clockSeconds, clockAlert, overtime = nil, false, false
	local countdownEnd, countingDown = nil, false
	local function updateTop()
		local mode = player:GetAttribute("Mode")
		local phase = player:GetAttribute("RoundPhase")
		local inMatch = Modes.IsTeamMode(mode) and ROUND_PHASES[phase] == true
		local teamMode = inMatch and player.Team ~= nil
		bar.Visible = teamMode
		-- Während der Runde das kurze Ziel, sonst die Info vom Server ("Warte auf Spieler ...").
		-- Im Countdown gelten Seite und Tickets noch von der letzten Runde, darum nur die Rundennummer.
		if inMatch then
			local goal = nil
			if phase == "Round" then
				goal = Modes.GoalText(mode, player:GetAttribute("Attacking"), player:GetAttribute("ClockAlert") == true)
			elseif phase == "Countdown" then
				goal = "RUNDE " .. tostring(player:GetAttribute("RoundNumber") or 1)
			end
			goalText.Text = goal or ""
			goalText.TextSize = 18
			goalText.Font = F.Display
		elseif mode == "FreeForAll" then
			goalText.Text = "JEDER GEGEN JEDEN  ·  " .. GameSettings.Get("KillsToWin") .. " KILLS GEWINNEN"
			goalText.TextSize = 18
			goalText.Font = F.Display
		else
			goalText.Text = player:GetAttribute("ModeText") or ""
			goalText.TextSize = 14
			goalText.Font = F.Bold
		end

		-- Free-for-All: wer führt (oben in der Mitte)
		ffaBar.Visible = mode == "FreeForAll"
		if ffaBar.Visible then
			updateFFA(mode)
		end
		if not teamMode then
			return
		end

		teamScore.Left.Text = tostring(player:GetAttribute("TeamScore") or 0)
		teamScore.Right.Text = tostring(player:GetAttribute("EnemyScore") or 0)
		local mine, theirs = player:GetAttribute("TeamTickets"), player:GetAttribute("EnemyTickets")
		local showTickets = phase ~= "Countdown"
		teamScore.LeftSub.Text = (mine ~= nil and showTickets) and (mine .. " TICKETS") or ""
		teamScore.RightSub.Text = (theirs ~= nil and showTickets) and (theirs .. " TICKETS") or ""
		local info = phase == "Round" and upper(player:GetAttribute("ObjInfo") or "") or ""
		statusChip.Text = info
		statusChip.Visible = info ~= ""

		clockSeconds = nil
		if phase == "Round" then
			clockSeconds = player:GetAttribute("RoundClock")
		elseif phase == "Countdown" and player:GetAttribute("CountdownEnd") then
			countdownEnd = player:GetAttribute("CountdownEnd")
		end
		countingDown = phase == "Countdown" and countdownEnd ~= nil
		clockAlert = player:GetAttribute("ClockAlert") == true
		overtime = player:GetAttribute("Overtime") == true
		teamScore.Top.Text = overtime and "OVERTIME" or ("RUNDE " .. tostring(player:GetAttribute("RoundNumber") or 1))

		local mates, enemies = {}, {}
		for _, fighter in TeamCheck.Fighters() do
			table.insert((fighter.IsSelf or fighter.IsMate) and mates or enemies, fighter)
		end
		syncPips(myPips, mates, ALLY)
		syncPips(enemyPips, enemies, ENEMY)
	end
	task.spawn(function()
		while true do
			if screen.Enabled then
				local ok, err = pcall(updateTop)
				if not ok then
					warn("MatchHUD: " .. tostring(err))
				end
			end
			task.wait(0.2)
		end
	end)

	-- Uhr jedes Bild (Overtime/Bombe pulsieren, die letzten 15 s rot)
	RunService.RenderStepped:Connect(function()
		if not bar.Visible then
			return
		end
		local clockText = teamScore.Clock
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 7)
		if overtime then
			clockText.Text = "OVERTIME"
			clockText.TextSize = 22
			clockText.TextColor3 = C.Primary:Lerp(WHITE, pulse * 0.4)
		elseif clockSeconds then
			clockText.Text = formatClock(clockSeconds)
			clockText.TextSize = 30
			clockText.TextColor3 = (clockAlert or clockSeconds <= 15) and ENEMY:Lerp(WHITE, clockAlert and pulse * 0.4 or 0) or WHITE
		elseif countingDown and countdownEnd then
			clockText.Text = formatClock(math.ceil(math.max(0, countdownEnd - workspace:GetServerTimeNow())))
			clockText.TextSize = 30
			clockText.TextColor3 = C.Primary
		else
			clockText.Text = "–:––"
			clockText.TextSize = 30
			clockText.TextColor3 = MUTED
		end
	end)

	-- =====================================================================
	-- Killfeed rechts oben
	-- =====================================================================
	local killfeed = make("Frame", { Name = "Killfeed", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 96),
		Size = UDim2.fromOffset(460, 160), BackgroundTransparency = 1 }, root)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 4) }, killfeed)
	local entryCount = 0
	local maxEntries = 5

	local function nameColor(name)
		local relation = name and TeamCheck.Relation(name)
		return (relation == "Self" or relation == "Mate") and ALLY or ENEMY
	end

	-- Eintrag ein-/ausblenden (alle Teile gemeinsam)
	local function setEntryAlpha(parts, alpha)
		parts.Row.BackgroundTransparency = 1 - alpha * (parts.Mine and 0.75 or 0.6)
		for _, text in parts.Texts do
			text.TextTransparency = 1 - alpha
		end
		parts.Accent.BackgroundTransparency = 1 - alpha
	end

	Remotes.Killfeed.OnClientEvent:Connect(function(killerName, victimName, weaponName, headshot, kind)
		entryCount += 1
		local mine = killerName == player.Name
		local row = make("Frame", { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = PANEL, BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = entryCount }, killfeed)
		UITheme.Corner(row, UITheme.Radius.Small)
		local content = make("Frame", { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1 }, row)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 14) }, content)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, content)
		-- farbige Kante rechts: Team des Schützen (eigene Kills Bernstein)
		local accent = UITheme.AccentBar(row, mine and C.Primary or nameColor(killerName or victimName),
			{ Side = "Right", Thickness = 2, BackgroundTransparency = 1 })

		local texts = {}
		local function text(value, color, order, size)
			local item = label({ Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Text = value,
				TextSize = size or 13, Font = F.Bold, TextColor3 = color, TextTransparency = 1,
				TextStrokeTransparency = 1, LayoutOrder = order }, content)
			table.insert(texts, item)
			return item
		end
		if killerName then
			text(tostring(killerName), nameColor(killerName), 1)
		end
		-- Waffe als graue Schrift in der Mitte, Kopfschuss als Kreis, Niederschlag als Pfeil
		local config = WeaponConfig.Get(weaponName)
		text(upper(config and config.DisplayName or tostring(weaponName or "")), MUTED, 2, 10)
		if headshot then
			text("◎", C.Gold, 3, 13)
		end
		if kind == "Down" then
			text("▼", DOWNED, 4, 11)
		end
		text(tostring(victimName or "?"), nameColor(victimName), 5)

		local parts = { Row = row, Texts = texts, Accent = accent, Mine = mine }
		local alpha = Instance.new("NumberValue")
		alpha.Changed:Connect(function(value)
			setEntryAlpha(parts, value)
		end)
		TweenService:Create(alpha, TweenInfo.new(0.15), { Value = 1 }):Play()

		-- Älteste Einträge entfernen
		local entries = {}
		for _, child in killfeed:GetChildren() do
			if child:IsA("Frame") then
				table.insert(entries, child)
			end
		end
		table.sort(entries, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #entries - maxEntries do
			entries[i]:Destroy()
		end
		task.delay(KILLFEED_TIME, function()
			if row.Parent then
				local fade = TweenService:Create(alpha, TweenInfo.new(0.4), { Value = 0 })
				fade.Completed:Connect(function()
					row:Destroy()
					alpha:Destroy()
				end)
				fade:Play()
			else
				alpha:Destroy()
			end
		end)
	end)

	-- =====================================================================
	-- Unten links: Porträt, Agent, Rüstung, Leben
	-- =====================================================================
	local vitals = make("Frame", { Name = "Vitals", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(330, 88), BackgroundTransparency = 1 }, root)
	local vitalsCard = UITheme.HudPanel({ Name = "VitalsCard", Size = UDim2.fromScale(1, 1), ZIndex = 2 }, vitals, "Right")
	local portraitCard = make("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(68, 68), BackgroundColor3 = PANEL,
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 3 }, vitalsCard)
	UITheme.Corner(portraitCard, UITheme.Radius.Small)
	local portraitStroke = UITheme.Stroke(portraitCard, C.Border, 1)
	local ownPortrait = HUDIcons.Portrait(portraitCard, 68)
	-- Das HUD rechnet ZIndex für den ganzen Bildschirm (ZIndexBehavior Global): ohne höheren Wert läge das Bild
	-- unter der eigenen Kachel (ZIndex 3) und bliebe unsichtbar
	ownPortrait.Frame.ZIndex = 4
	local agentLine = label({ Position = UDim2.fromOffset(90, 8), Size = UDim2.fromOffset(230, 22), Text = "", TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, vitalsCard)
	-- Rüstung: 5 dünne Segmente
	local armorSegments = {}
	for i = 1, ARMOR_SEGMENTS do
		local segment = make("Frame", { Position = UDim2.fromOffset(90 + (i - 1) * 46, 38), Size = UDim2.fromOffset(42, 4),
			BackgroundColor3 = WHITE, BackgroundTransparency = 0.85, BorderSizePixel = 0, ZIndex = 3 }, vitalsCard)
		table.insert(armorSegments, segment)
	end
	-- Leben: Zahl und Balken (Geister-Balken zeigt kurz den Verlust)
	local healthText = label({ Position = UDim2.fromOffset(90, 46), Size = UDim2.fromOffset(52, 34), Text = "", TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, vitalsCard)
	local healthBack = make("Frame", { Position = UDim2.fromOffset(146, 60), Size = UDim2.fromOffset(174, 6), BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.85, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 3 }, vitalsCard)
	local ghostFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(180, 64, 54), BorderSizePixel = 0,
		ZIndex = 3 }, healthBack)
	local healthFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Text, BorderSizePixel = 0, ZIndex = 4 }, healthBack)

	local shownHealth, ghostHealth, ghostHoldUntil = 0, 0, 0
	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		vitals.Visible = humanoid ~= nil and screen.Enabled
		if not humanoid or not vitals.Visible then
			return
		end
		local maxHealth = math.max(1, humanoid.MaxHealth)
		local health = math.clamp(humanoid.Health, 0, maxHealth)
		if health < shownHealth then
			ghostHoldUntil = os.clock() + 0.4
		end
		shownHealth = health
		if health >= ghostHealth then
			ghostHealth = health
		elseif os.clock() > ghostHoldUntil then
			ghostHealth = math.max(health, ghostHealth - 90 * dt)
		end
		local low = health / maxHealth < 0.3
		local downed = character:GetAttribute("Downed") == true
		healthFill.Size = UDim2.fromScale(health / maxHealth, 1)
		ghostFill.Size = UDim2.fromScale(ghostHealth / maxHealth, 1)
		healthFill.BackgroundColor3 = downed and DOWNED or (low and ENEMY or C.Text)
		healthText.Text = tostring(math.ceil(health))
		healthText.TextColor3 = low and ENEMY or WHITE

		local armor = character:GetAttribute("Armor") or 0
		local filled = armor / BuyConfig.ArmorAmount * ARMOR_SEGMENTS
		for i, segment in armorSegments do
			local amount = math.clamp(filled - (i - 1), 0, 1)
			segment.BackgroundColor3 = amount > 0 and ARMOR or WHITE
			segment.BackgroundTransparency = amount > 0 and (1 - amount) * 0.6 or 0.85
		end
	end)

	-- Agent (Porträt, Name) bei jedem Spawn bzw. Agentenwechsel
	local function updateAgent()
		local agent = myAgent()
		ownPortrait.Set(agent and agent.Id, player)
		agentLine.Text = agent and agent.Name or ""
		portraitStroke.Color = C.Border
	end
	task.spawn(function()
		while true do
			if screen.Enabled then
				updateAgent()
			end
			task.wait(0.5)
		end
	end)

	-- =====================================================================
	-- Unten rechts: Munition, Waffen-Silhouette, Waffenplätze
	-- =====================================================================
	-- Spiegelbild der Lebensanzeige (330 x 88, verläuft zur Bildmitte): oben Waffenname mit Plätzen 1/2 und
	-- links die andere Waffe ("[2] PISTOLE"), in der Mitte das Magazin als dünner Balken (kleine Magazine wie die
	-- Rüstung in Segmenten, eins pro Schuss), unten die Munition groß und links die Waffen-Silhouette.
	-- HUD (Geld darüber) richtet sich nach dieser Größe.
	local AMMO_W, AMMO_H = 330, 88
	local MAG_W = 200 -- Breite des Magazin-Balkens (rechtsbündig)
	local MAX_SEGMENTS = 12 -- bis zu so vielen Schuss einzelne Segmente, sonst ein durchgehender Balken
	local ammo = make("Frame", { Name = "Ammo", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(AMMO_W, AMMO_H), BackgroundTransparency = 1, Visible = false }, root)
	local ammoCard = UITheme.HudPanel({ Name = "AmmoCard", Size = UDim2.fromScale(1, 1), ZIndex = 2 }, ammo, "Left")
	-- Waffenplätze 1 / 2 (aktiv: Bernstein-Rahmen) ganz rechts oben, Name links daneben
	local slotRow = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(46, 18),
		BackgroundTransparency = 1, ZIndex = 3 }, ammoCard)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, slotRow)
	local slotPills = {}
	for i = 1, 2 do
		local pill = label({ Size = UDim2.fromOffset(20, 18), Text = tostring(i), TextSize = 11, BackgroundTransparency = 1,
			TextColor3 = MUTED, TextStrokeTransparency = 1, LayoutOrder = i, ZIndex = 3 }, slotRow)
		UITheme.Corner(pill, UITheme.Radius.Small)
		UITheme.Stroke(pill, C.Primary, 1)
		slotPills[i] = pill
	end
	local weaponName = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -64, 0, 8), Size = UDim2.fromOffset(150, 22),
		Text = "", TextSize = 21, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
		TextTruncate = Enum.TextTruncate.AtEnd }, ammoCard)
	-- Andere Waffe links oben (verblasst zur Mitte hin wie die Fläche)
	local swapText = label({ Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(100, 16), Text = "", TextSize = 11,
		Font = F.Bold, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1, ZIndex = 3,
		TextTruncate = Enum.TextTruncate.AtEnd }, ammoCard)
	-- Magazin: Spur + Füllung (Balken) bzw. Segmente
	local magTrack = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 38),
		Size = UDim2.fromOffset(MAG_W, 4), BackgroundTransparency = 1, ZIndex = 3 }, ammoCard)
	local magBack = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.85,
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 3 }, magTrack)
	local magFill = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, magBack)
	local magSegments = {}
	-- Waffen-Silhouette links unten
	local iconHolder = make("Frame", { Position = UDim2.fromOffset(10, 40), Size = UDim2.fromOffset(108, 40), BackgroundTransparency = 1,
		ZIndex = 3 }, ammoCard)
	-- Munition: Magazin groß, Vorrat klein daneben
	local ammoText = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 46), Size = UDim2.fromOffset(190, 36),
		Text = "", RichText = true, TextSize = 36, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 }, ammoCard)

	local shownWeapon, weaponIcon = nil, nil
	local function setWeaponIcon(name)
		if name == shownWeapon then
			return
		end
		shownWeapon = name
		if weaponIcon then
			weaponIcon:Destroy()
		end
		weaponIcon = HUDIcons.Weapon(iconHolder, name, 108, 40)
		if weaponIcon then
			weaponIcon.ZIndex = 3
		end
	end

	-- Segmente für kleine Magazine (eins pro Schuss, von rechts nach links leer)
	local segmentCount = 0
	local function setSegments(count)
		if count == segmentCount then
			return
		end
		segmentCount = count
		for _, segment in magSegments do
			segment:Destroy()
		end
		magSegments = {}
		magBack.Visible = count == 0
		if count == 0 then
			return
		end
		local gap = 4
		local width = (MAG_W - gap * (count - 1)) / count
		for i = 1, count do
			table.insert(magSegments, make("Frame", { Position = UDim2.fromOffset((i - 1) * (width + gap), 0),
				Size = UDim2.fromOffset(width, 4), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, magTrack))
		end
	end

	-- Magazin anzeigen: fraction 0..1, color; bei Segmenten zählen die vollen Schuss
	local reloadTween = nil
	local function showMagazine(mag, size, color)
		if reloadTween then
			reloadTween:Cancel()
			reloadTween = nil
		end
		setSegments(size <= MAX_SEGMENTS and size or 0)
		if segmentCount > 0 then
			for i, segment in magSegments do
				local full = i > segmentCount - mag -- leer werden sie von links
				segment.BackgroundColor3 = full and color or WHITE
				segment.BackgroundTransparency = full and 0 or 0.85
			end
		else
			magFill.BackgroundColor3 = color
			magFill.Size = UDim2.fromScale(math.clamp(mag / math.max(size, 1), 0, 1), 1)
		end
	end

	-- Nachladen: Magazin füllt sich in Bernstein über die Nachladezeit
	local function showReload(weapon, size)
		setSegments(0)
		magFill.BackgroundColor3 = C.Primary
		magFill.Size = UDim2.fromScale(0, 1)
		local ok, duration = pcall(WeaponConfig.ReloadDuration, player, player.Character, weapon)
		reloadTween = TweenService:Create(magFill, TweenInfo.new(ok and duration or 1.5, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 1) })
		reloadTween:Play()
	end

	-- Waffenplätze und andere Waffe des Loadouts mit Taste fürs aktuelle Gerät
	local function updateSlots(current)
		local character = player.Character
		local text = character and character:GetAttribute("Loadout")
		local loadout = text and string.split(text, ",") or {}
		local slot = table.find(loadout, current) or 1
		for i, pill in slotPills do
			local active = i == slot
			pill.TextColor3 = active and C.Primary or MUTED
			local stroke = pill:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = active and 0 or 1
			end
			pill.Visible = i <= math.max(#loadout, 1)
		end
		local otherSlot = slot == 1 and 2 or 1
		local other = loadout[otherSlot]
		if other and other ~= current then
			local config = WeaponConfig.Get(other)
			local key = InputActions.Hint(otherSlot == 1 and "Weapon1" or "Weapon2")
			if key == "" then
				key = InputActions.Hint("SwapWeapon")
			end
			swapText.Text = (key ~= "" and ("[" .. key .. "]  ") or "") .. upper(config and config.DisplayName or other)
		else
			swapText.Text = ""
		end
	end

	local wasReloading = false
	weaponClient.AmmoChanged:Connect(function(name, mag, reserve, reloading, magSize, infinite)
		local config = WeaponConfig.Get(name)
		ammo.Visible = config ~= nil
		if not config then
			return
		end
		setWeaponIcon(name)
		local size = magSize or config.MagazineSize or math.max(mag, 1)
		local ratio = math.clamp(mag / math.max(size, mag, 1), 0, 1)
		local low = ratio <= 0.25
		local color = (mag == 0 or low) and ENEMY or WHITE
		if reloading then
			ammoText.Text = string.format('<font size="22" color="#%s">LÄDT NACH</font>', hex(C.Primary))
			if not wasReloading then
				showReload(name, size)
			end
		else
			ammoText.Text = string.format('<font color="#%s">%d</font><font size="18" color="#%s">  / %s</font>', hex(color), mag,
				hex(MUTED), infinite and '<font face="Roboto">∞</font>' or tostring(reserve))
			showMagazine(mag, size, color)
		end
		wasReloading = reloading
		weaponName.Text = upper(config.DisplayName)
		if weaponIcon then
			weaponIcon.ImageColor3 = mag == 0 and ENEMY or WHITE
			weaponIcon.ImageTransparency = reloading and 0.45 or 0.1
		end
		updateSlots(name)
	end)
	InputActions.DeviceChanged:Connect(function()
		if shownWeapon then
			updateSlots(shownWeapon)
		end
	end)
	-- Ohne Charakter (tot, Zuschauen) keine Munition zeigen
	RunService.Heartbeat:Connect(function()
		if ammo.Visible and not (player.Character and player.Character:FindFirstChildOfClass("Humanoid")) then
			ammo.Visible = false
			shownWeapon = nil
			if weaponIcon then
				weaponIcon:Destroy()
				weaponIcon = nil
			end
		end
	end)

	-- =====================================================================
	-- Zielmarker in der Welt (A/B)
	-- =====================================================================
	local playerGui = player:WaitForChild("PlayerGui")
	local markers = {} -- { Gui, Part, Diamond, Inner, Stroke, Letter, Distance, State }
	local shownKey = nil
	local buildAt = 0

	local function clearMarkers()
		for _, marker in markers do
			marker.Gui:Destroy()
		end
		markers = {}
	end

	local function buildMarkers()
		local mode = Modes.Get(player:GetAttribute("Mode"))
		local maps = workspace:FindFirstChild("Maps")
		local map = maps and player:GetAttribute("MapId") and maps:FindFirstChild(player:GetAttribute("MapId"))
		local key = tostring(mode and mode.Id) .. "|" .. tostring(map)
		if key == shownKey then
			return
		end
		shownKey = key
		clearMarkers()
		local folder = map and map:FindFirstChild("Objective")
		if not (folder and mode and mode.Objectives) then
			return
		end
		for _, objective in mode.Objectives do
			local part = folder:FindFirstChild(objective.Part)
			if part and part:IsA("BasePart") then
				-- Klein und hoch über dem Ziel, damit der Marker keine Gegner verdeckt; die Gruppe wird
				-- ausgeblendet, wenn der Marker nahe am Fadenkreuz ist oder man zielt (siehe unten)
				local gui = make("BillboardGui", { Name = "ObjectiveMarker", Adornee = part, AlwaysOnTop = true, LightInfluence = 0,
					Size = UDim2.fromOffset(64, 58), StudsOffset = Vector3.new(0, 16, 0), ResetOnSpawn = false, Enabled = false,
					ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
				local group = make("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
				local state = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(64, 12),
					Text = "", TextSize = 11 }, group)
				local diamond = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 28),
					Size = UDim2.fromOffset(20, 20), Rotation = 45, BackgroundColor3 = PANEL, BackgroundTransparency = 0.3,
					BorderSizePixel = 0 }, group)
				local stroke = UITheme.Stroke(diamond, WHITE, 1.5)
				local inner = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(0, 0), BackgroundColor3 = ALLY, BorderSizePixel = 0 }, diamond)
				local letter = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 28), Size = UDim2.fromOffset(20, 20),
					Text = objective.Label, TextSize = 15, TextStrokeTransparency = 0.3 }, group)
				local distance = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 43), Size = UDim2.fromOffset(64, 13),
					Text = "", TextSize = 12 }, group)
				table.insert(markers, { Gui = gui, Group = group, Part = part, Diamond = diamond, Inner = inner, Stroke = stroke,
					Letter = letter, Distance = distance, State = state })
			end
		end
	end

	RunService.RenderStepped:Connect(function()
		local phase = player:GetAttribute("RoundPhase")
		local show = screen.Enabled and (phase == "Round" or phase == "Countdown")
		if show and os.clock() >= buildAt then
			buildAt = os.clock() + 1
			buildMarkers()
		end
		if #markers == 0 then
			return
		end
		local camera = workspace.CurrentCamera
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local from = rootPart and (rootPart :: BasePart).Position or camera.CFrame.Position
		local flash = math.floor(os.clock() * 4) % 2 == 0
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 8)
		local attacking = player:GetAttribute("Attacking")
		local mine, theirs = player:GetAttribute("ObjMine") or 0, player:GetAttribute("ObjEnemy") or 0
		for _, marker in markers do
			marker.Gui.Enabled = show
			if show then
				local part = marker.Part
				local offset = part.Position - from
				local studs = Vector3.new(offset.X, 0, offset.Z).Magnitude
				marker.Distance.Text = math.floor(studs * METERS_PER_STUD + 0.5) .. "m"
				local near = studs < 12
				local back, backTransparency = PANEL, 0.3
				local fill, progress = ALLY, 0
				local stroke, stateText = WHITE, ""
				local letterColor = WHITE
				if part:GetAttribute("Locked") then
					stroke, letterColor, stateText = MUTED, MUTED, "GESPERRT"
				elseif part:GetAttribute("Planted") then
					back, backTransparency = ENEMY, 0.15 + pulse * 0.4
					stroke, stateText = ENEMY:Lerp(WHITE, pulse), "BOMBE"
				elseif part.Name == "CapturePoint" then
					-- Punkt: Besitzer füllt die Raute, Einnehmen wächst von innen
					if mine >= 1 then
						back, backTransparency = ALLY, 0.25
					elseif theirs >= 1 then
						back, backTransparency = ENEMY, 0.25
					end
					if mine > 0 and mine < 1 then
						fill, progress = ALLY, mine
					elseif theirs > 0 and theirs < 1 then
						fill, progress = ENEMY, theirs
					end
				elseif string.sub(part.Name, 1, 4) == "Flag" then
					-- Herrschaft-Flagge: Besitzer füllt die Raute (eigenes Team Cyan, Gegner rot),
					-- Einnehmen wächst in der Farbe des einnehmenden Teams
					local myTeam = player.Team and player.Team.Name
					local owner, capturer = part:GetAttribute("FlagOwner"), part:GetAttribute("Capturer")
					if owner then
						back, backTransparency = owner == myTeam and ALLY or ENEMY, 0.25
					end
					if capturer then
						fill, progress = capturer == myTeam and ALLY or ENEMY, part:GetAttribute("Progress") or 0
					end
				else
					-- Hack-Ziel: Fortschritt in der Farbe der Angreifer
					progress = part:GetAttribute("Progress") or 0
					fill = attacking == false and ENEMY or ALLY
				end
				if part:GetAttribute("Contested") then
					stroke, stateText = flash and DOWNED or WHITE, "UMKÄMPFT"
				end
				marker.Diamond.BackgroundColor3 = back
				marker.Diamond.BackgroundTransparency = near and math.max(backTransparency, 0.6) or backTransparency
				marker.Stroke.Color = stroke
				marker.Stroke.Transparency = near and 0.5 or 0
				marker.Inner.BackgroundColor3 = fill
				marker.Inner.Size = UDim2.fromScale(math.clamp(progress, 0, 1), math.clamp(progress, 0, 1))
				marker.Letter.TextColor3 = letterColor
				marker.Letter.TextTransparency = near and 0.5 or 0
				marker.State.Text = stateText
				marker.State.TextColor3 = stroke
				marker.Distance.Visible = not near
				-- Nahe am Fadenkreuz oder beim Zielen fast unsichtbar, damit man Gegner dahinter sieht
				local screenPos, onScreen = camera:WorldToViewportPoint(part.Position + Vector3.new(0, 16, 0))
				local fade = 0
				if onScreen then
					local viewport = camera.ViewportSize
					local fromCenter = (Vector2.new(screenPos.X, screenPos.Y) - viewport / 2).Magnitude / viewport.Y
					fade = math.clamp(1 - (fromCenter - 0.08) / 0.12, 0, 1) -- innerhalb ~8 % voll ausgeblendet
				end
				local aimBlend = weaponClient and weaponClient.GetAimBlend and weaponClient.GetAimBlend() or 0
				marker.Group.GroupTransparency = math.max(fade * 0.85, aimBlend * 0.8)
			end
		end
	end)
	player:GetAttributeChangedSignal("Mode"):Connect(function()
		shownKey = nil
		buildAt = 0
		clearMarkers()
	end)

	-- Touch: weniger Killfeed-Einträge
	local function layout()
		maxEntries = InputActions.IsTouch() and 4 or 5
	end
	layout()
	InputActions.DeviceChanged:Connect(layout)

	return { Vitals = vitals, Ammo = ammo, Killfeed = killfeed, Top = top }
end

return MatchHUD

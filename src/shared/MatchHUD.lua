-- MatchHUD (ModuleScript, nur Client)
-- Match-Anzeige im Stil von Rogue Company:
--   oben mittig:   Ziel ("NIMM DEN PUNKT EIN"), Teamleiste mit Porträts und Lebensbalken (eigenes Team
--                  Cyan links, Gegner rot rechts), Rundenstand in schrägen Kästen, Uhr, Tickets, Status
--   rechts oben:   Killfeed "Name [Waffe] ▼ Name" (▼ = niedergeschlagen, ☠ = ausgeschaltet)
--   unten links:   Porträt, Leben "100/100", Segment-Balken (25er-Schritte), Rüstung
--   unten rechts:  Munition "20/200", Waffen-Silhouette, Hinweis auf die andere Waffe
--   in der Welt:   Zielmarker (Raute mit A/B, Entfernung in Metern, Zustand)
-- Daten: Spieler-Attribute vom Server (TeamRoundMode), Remotes.Killfeed, WeaponClient.AmmoChanged.
-- Fähigkeit/Gadget (Rauten links neben der Munition): AbilityClient. Minimap: Minimap.

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
local InputActions = require(Shared.InputActions)
local TeamCheck = require(Shared.TeamCheck)
local HUDIcons = require(Shared.HUDIcons)

local player = Players.LocalPlayer
local make = UITheme.Make
local C = UITheme.Colors

local MatchHUD = {}

local ALLY = C.Accent
local ENEMY = C.Bad
local DOWNED = Color3.fromRGB(255, 170, 40)
local ARMOR = Color3.fromRGB(80, 170, 255)
local PANEL = Color3.fromRGB(10, 16, 28)
local MUTED = Color3.fromRGB(150, 165, 185)
local WHITE = Color3.new(1, 1, 1)
local KILLFEED_TIME = 6        -- Sekunden pro Eintrag
local HEALTH_SEGMENT = 25      -- Leben pro Balken-Segment
local METERS_PER_STUD = 0.28
local ROUND_PHASES = { Countdown = true, Round = true, RoundEnd = true }

local function hex(color)
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5))
end

-- Text mit leichter Kontur (schmale RC-Schrift)
local function label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or WHITE
	props.Font = props.Font or UITheme.Fonts.Title
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0.55
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	return make("TextLabel", props, parent)
end

-- Schräger Kasten (Parallelogramm) wie die RC-Punktekästen: harte Kanten über einen gedrehten Verlauf
local function slantedBox(parent, props, slant)
	props.BorderSizePixel = 0
	local frame = make("Frame", props, parent)
	local cut = 0.13
	make("UIGradient", {
		Rotation = slant,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(cut, 1),
			NumberSequenceKeypoint.new(cut + 0.002, 0),
			NumberSequenceKeypoint.new(1 - cut - 0.002, 0),
			NumberSequenceKeypoint.new(1 - cut, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, frame)
	return frame
end

-- Kleines Personen-Symbol (Tickets): Kopf + Schultern aus zwei Flächen
local function personIcon(parent, color)
	local icon = make("Frame", { Size = UDim2.fromOffset(12, 14), BackgroundTransparency = 1 }, parent)
	local head = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = color, BorderSizePixel = 0 }, icon)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, head)
	local body = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(12, 6),
		BackgroundColor3 = color, BorderSizePixel = 0 }, icon)
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, body)
	return icon, head, body
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

-- root = skalierte HUD-Ebene, weaponClient = WeaponClient-Modul.
-- Gibt { Vitals, Ammo, Killfeed } zurück (für das Touch-Layout im HUD).
function MatchHUD.Init(root, weaponClient)
	local screen = root.Parent :: ScreenGui

	-- =====================================================================
	-- Oben: Ziel, Teamleiste, Uhr, Rundenstand, Tickets, Status
	-- =====================================================================
	local top = make("Frame", { Name = "TopBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(980, 116), BackgroundTransparency = 1 }, root)
	local goalText = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(700, 22),
		Text = "", TextSize = 18, TextStrokeTransparency = 0.4 }, top)
	local bar = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, top)

	local clockBox = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.fromOffset(96, 40), BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, bar)
	UITheme.Gradient(clockBox, Color3.fromRGB(34, 48, 70), PANEL)
	local clockText = label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 30 }, clockBox)

	local function scoreBox(anchorX, x, color, slant)
		local box = slantedBox(bar, { AnchorPoint = Vector2.new(anchorX, 0), Position = UDim2.new(0.5, x, 0, 26),
			Size = UDim2.fromOffset(64, 40), BackgroundColor3 = color }, slant)
		local text = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(anchorX == 1 and 0.55 or 0.45, 0, 0.5, 0),
			Size = UDim2.fromScale(0.7, 1), Text = "0", TextSize = 32, TextStrokeTransparency = 0.35 }, box)
		return box, text
	end
	local _, myScore = scoreBox(1, -46, ALLY, 18)
	local _, enemyScore = scoreBox(0, 46, ENEMY, -18)

	-- Tickets unter den Punkte-Kästen: "12 [Person]"
	local function ticketRow(x, color)
		local row = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 0, 70),
			Size = UDim2.fromOffset(70, 18), BackgroundTransparency = 1 }, bar)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		local text = label({ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 18,
			TextColor3 = color, LayoutOrder = 1 }, row)
		local icon = personIcon(row, color)
		icon.LayoutOrder = 2
		return row, text
	end
	local myTicketRow, myTickets = ticketRow(-79, ALLY)
	local enemyTicketRow, enemyTickets = ticketRow(79, ENEMY)

	-- Porträts der beiden Teams
	local function portraitRow(anchorX, x, alignment)
		local row = make("Frame", { AnchorPoint = Vector2.new(anchorX, 0), Position = UDim2.new(0.5, x, 0, 22),
			Size = UDim2.fromOffset(300, 56), BackgroundTransparency = 1 }, bar)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = alignment,
			Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		return row
	end
	local myRow = portraitRow(1, -124, Enum.HorizontalAlignment.Right)
	local enemyRow = portraitRow(0, 124, Enum.HorizontalAlignment.Left)

	local statusText = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(600, 18),
		Text = "", TextSize = 15, TextColor3 = Color3.fromRGB(215, 225, 238), Font = UITheme.Fonts.Bold }, bar)

	-- Kills in Modi ohne Teams (Free-for-All)
	local killsBadge = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26), Size = UDim2.fromOffset(120, 30),
		Text = "", TextSize = 22, BackgroundTransparency = 0.3, BackgroundColor3 = PANEL, Visible = false }, top)
	UITheme.Corner(killsBadge, 3)

	-- Ein Porträt-Feld: Bild, Lebensbalken, Kreuz wenn ausgeschaltet
	local function makeSlot(parent, mate)
		local color = mate and ALLY or ENEMY
		local slot = make("Frame", { Size = UDim2.fromOffset(44, 56), BackgroundTransparency = 1 }, parent)
		local card = make("Frame", { Size = UDim2.fromOffset(44, 44), BackgroundColor3 = WHITE, BackgroundTransparency = 0.15,
			BorderSizePixel = 0, ClipsDescendants = true }, slot)
		UITheme.Gradient(card, color:Lerp(PANEL, 0.55), PANEL)
		local stroke = UITheme.Stroke(card, color, 1.5, 0.1)
		local portrait = HUDIcons.Portrait(card, 44)
		local back = make("Frame", { Position = UDim2.fromOffset(0, 48), Size = UDim2.fromOffset(44, 5), BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.2, BorderSizePixel = 0 }, slot)
		local fill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
		local cross = label({ Size = UDim2.fromOffset(44, 44), Text = "✕", TextSize = 30, TextColor3 = color,
			TextStrokeTransparency = 0.2, Visible = false, ZIndex = 3 }, slot)
		return { Frame = slot, Card = card, Stroke = stroke, Portrait = portrait, Fill = fill, Cross = cross, Color = color }
	end
	local mySlots, enemySlots = {}, {}
	local function syncSlots(slots, row, entries, mate)
		while #slots < #entries do
			local slot = makeSlot(row, mate)
			slot.Frame.LayoutOrder = #slots + 1
			table.insert(slots, slot)
		end
		while #slots > #entries do
			local removed = table.remove(slots)
			if removed then
				removed.Frame:Destroy()
			end
		end
		for i, entry in entries do
			local slot = slots[i]
			slot.Portrait.Set(entry.AgentId, entry.Player)
			local humanoid = entry.Model and entry.Model:FindFirstChildOfClass("Humanoid")
			local ratio = 0
			if entry.State ~= "dead" and humanoid then
				-- Gegner: kein genaues Leben verraten
				ratio = (mate and math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)) or 1
				if entry.State == "downed" then
					ratio = mate and ratio or 0.4
				end
			end
			slot.Fill.Size = UDim2.fromScale(ratio, 1)
			slot.Fill.BackgroundColor3 = entry.State == "downed" and DOWNED or slot.Color
			slot.Cross.Visible = entry.State == "dead"
			slot.Portrait.Frame.ImageColor3 = entry.State == "dead" and Color3.fromRGB(70, 70, 75) or WHITE
			slot.Portrait.Frame.ImageTransparency = entry.State == "dead" and 0.35 or 0
			slot.Stroke.Color = entry.IsSelf and WHITE or (entry.State == "downed" and DOWNED or slot.Color)
			slot.Stroke.Thickness = entry.IsSelf and 2 or 1.5
		end
	end

	-- Zustand oben (5x pro Sekunde): Teamleiste, Stand, Tickets, Ziel, Status
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
			goalText.Font = UITheme.Fonts.Title
		else
			goalText.Text = player:GetAttribute("ModeText") or ""
			goalText.TextSize = 16
			goalText.Font = UITheme.Fonts.Bold
		end

		-- Free-for-All: eigene Kills groß unter der Info
		local stats = player:FindFirstChild("leaderstats")
		local kills = stats and stats:FindFirstChild("Kills")
		killsBadge.Visible = not Modes.IsTeamMode(mode) and mode ~= "Training" and kills ~= nil
		if kills and kills:IsA("IntValue") then
			killsBadge.Text = "☠  " .. kills.Value
		end
		if not teamMode then
			return
		end

		myScore.Text = tostring(player:GetAttribute("TeamScore") or 0)
		enemyScore.Text = tostring(player:GetAttribute("EnemyScore") or 0)
		local mine, theirs = player:GetAttribute("TeamTickets"), player:GetAttribute("EnemyTickets")
		myTicketRow.Visible = mine ~= nil and phase ~= "Countdown"
		enemyTicketRow.Visible = theirs ~= nil and phase ~= "Countdown"
		myTickets.Text = tostring(mine or "")
		enemyTickets.Text = tostring(theirs or "")
		statusText.Text = phase == "Round" and string.upper(player:GetAttribute("ObjInfo") or "") or ""

		clockSeconds = nil
		if phase == "Round" then
			clockSeconds = player:GetAttribute("RoundClock")
		elseif phase == "Countdown" and player:GetAttribute("CountdownEnd") then
			countdownEnd = player:GetAttribute("CountdownEnd")
		end
		countingDown = phase == "Countdown" and countdownEnd ~= nil
		clockAlert = player:GetAttribute("ClockAlert") == true
		overtime = player:GetAttribute("Overtime") == true

		local mates, enemies = {}, {}
		for _, fighter in TeamCheck.Fighters() do
			table.insert((fighter.IsSelf or fighter.IsMate) and mates or enemies, fighter)
		end
		syncSlots(mySlots, myRow, mates, true)
		syncSlots(enemySlots, enemyRow, enemies, false)
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

	-- Uhr jedes Bild (Overtime/Bombe pulsieren)
	RunService.RenderStepped:Connect(function()
		if not bar.Visible then
			return
		end
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 7)
		if overtime then
			clockText.Text = "OVERTIME"
			clockText.TextSize = 20
			clockText.TextColor3 = C.Play:Lerp(WHITE, pulse * 0.6)
		elseif clockSeconds then
			clockText.Text = formatClock(clockSeconds)
			clockText.TextSize = 30
			clockText.TextColor3 = clockAlert and ENEMY:Lerp(WHITE, pulse * 0.5) or WHITE
		elseif countingDown and countdownEnd then
			clockText.Text = formatClock(math.ceil(math.max(0, countdownEnd - workspace:GetServerTimeNow())))
			clockText.TextSize = 30
			clockText.TextColor3 = C.Accent
		else
			clockText.Text = "RUNDE " .. tostring(player:GetAttribute("RoundNumber") or 1)
			clockText.TextSize = 18
			clockText.TextColor3 = WHITE
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
		parts.Row.BackgroundTransparency = 1 - alpha * 0.62
		for _, text in parts.Texts do
			text.TextTransparency = 1 - alpha
			text.TextStrokeTransparency = 1 - alpha * 0.45
		end
		if parts.Icon then
			parts.Icon.ImageTransparency = 1 - alpha
		end
		parts.Accent.BackgroundTransparency = 1 - alpha
	end

	Remotes.Killfeed.OnClientEvent:Connect(function(killerName, victimName, weaponName, headshot, kind)
		entryCount += 1
		local involvesMe = killerName == player.Name or victimName == player.Name
		-- Zeile: Hintergrund (links ausgeblendet), Inhalt nebeneinander, Akzent-Strich rechts
		local row = make("Frame", { Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = involvesMe and Color3.fromRGB(26, 58, 74) or PANEL, BackgroundTransparency = 1,
			BorderSizePixel = 0, LayoutOrder = entryCount }, killfeed)
		make("UIGradient", { Transparency = NumberSequence.new(0.6, 0) }, row)
		local content = make("Frame", { Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1 }, row)
		make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 12) }, content)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, content)
		local accent = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 3, 1, 0),
			BackgroundColor3 = involvesMe and WHITE or nameColor(killerName or victimName), BackgroundTransparency = 1,
			BorderSizePixel = 0 }, row)

		local texts = {}
		local function text(value, color, order, size)
			local item = label({ Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, Text = value, TextSize = size or 18,
				TextColor3 = color, TextTransparency = 1, LayoutOrder = order }, content)
			table.insert(texts, item)
			return item
		end
		if killerName then
			text(tostring(killerName), nameColor(killerName), 1)
		end
		local icon = HUDIcons.Weapon(content, weaponName, 64, 22)
		if icon then
			icon.LayoutOrder = 2
			icon.ImageTransparency = 1
		else
			local config = WeaponConfig.Get(weaponName)
			local weaponLabel = config and config.DisplayName or tostring(weaponName or "")
			text(string.upper(weaponLabel), MUTED, 2, 14)
		end
		if headshot then
			text("◎", C.Gold, 3, 16)
		end
		if kind == "Down" then
			text("▼", DOWNED, 4, 15)
		else
			text("☠", WHITE, 4, 16)
		end
		text(tostring(victimName or "?"), nameColor(victimName), 5)

		local parts = { Row = row, Texts = texts, Icon = icon, Accent = accent }
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
	-- Unten links: Porträt, Leben, Segment-Balken, Rüstung
	-- =====================================================================
	local vitals = make("Frame", { Name = "Vitals", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(350, 84), BackgroundTransparency = 1 }, root)
	local portraitCard = make("Frame", { Size = UDim2.fromOffset(78, 78), BackgroundColor3 = WHITE, BackgroundTransparency = 0.1,
		BorderSizePixel = 0, ClipsDescendants = true }, vitals)
	UITheme.Corner(portraitCard, 4)
	local portraitGradient = UITheme.Gradient(portraitCard, ALLY:Lerp(PANEL, 0.5), PANEL)
	local portraitStroke = UITheme.Stroke(portraitCard, ALLY, 2, 0.1)
	local ownPortrait = HUDIcons.Portrait(portraitCard, 78)
	local agentLine = label({ Position = UDim2.fromOffset(92, 0), Size = UDim2.fromOffset(250, 18), Text = "", TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left }, vitals)
	local healthText = label({ Position = UDim2.fromOffset(92, 14), Size = UDim2.fromOffset(250, 40), Text = "", RichText = true,
		TextSize = 36, TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 0.4 }, vitals)
	local healthBar = make("Frame", { Position = UDim2.fromOffset(92, 58), Size = UDim2.fromOffset(250, 11),
		BackgroundTransparency = 1 }, vitals)
	local armorBack = make("Frame", { Position = UDim2.fromOffset(92, 73), Size = UDim2.fromOffset(250, 4), BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.3, BorderSizePixel = 0, Visible = false }, vitals)
	local armorFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = ARMOR, BorderSizePixel = 0 }, armorBack)

	-- Segmente: je HEALTH_SEGMENT Leben ein Stück, Breite nach Anteil; "Geister"-Balken zeigt kurz den Verlust
	local segments = {}
	local segmentMax = 0
	local function buildSegments(maxHealth)
		if maxHealth == segmentMax then
			return
		end
		segmentMax = maxHealth
		healthBar:ClearAllChildren()
		segments = {}
		local count = math.max(1, math.ceil(maxHealth / HEALTH_SEGMENT))
		local gap, x = 3, 0
		local width = 250 - gap * (count - 1)
		for i = 1, count do
			local capacity = math.min(HEALTH_SEGMENT, maxHealth - (i - 1) * HEALTH_SEGMENT)
			local w = width * capacity / maxHealth
			local back = make("Frame", { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(w, 11), BackgroundColor3 = PANEL,
				BackgroundTransparency = 0.25, BorderSizePixel = 0 }, healthBar)
			local ghost = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(230, 70, 60),
				BorderSizePixel = 0 }, back)
			local fill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2 }, back)
			table.insert(segments, { Ghost = ghost, Fill = fill, From = (i - 1) * HEALTH_SEGMENT, Capacity = capacity })
			x += w + gap
		end
	end

	local shownHealth, ghostHealth, ghostHoldUntil = 0, 0, 0
	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		vitals.Visible = humanoid ~= nil and screen.Enabled
		if not humanoid or not vitals.Visible then
			return
		end
		local maxHealth = math.max(1, math.floor(humanoid.MaxHealth + 0.5))
		local health = math.clamp(humanoid.Health, 0, maxHealth)
		buildSegments(maxHealth)
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
		for _, segment in segments do
			segment.Fill.Size = UDim2.fromScale(math.clamp((health - segment.From) / segment.Capacity, 0, 1), 1)
			segment.Ghost.Size = UDim2.fromScale(math.clamp((ghostHealth - segment.From) / segment.Capacity, 0, 1), 1)
			segment.Fill.BackgroundColor3 = character:GetAttribute("Downed") and DOWNED or (low and ENEMY or WHITE)
		end
		healthText.Text = string.format('%d<font size="20" color="%s">/%d</font>', math.ceil(health), hex(MUTED), maxHealth)
		healthText.TextColor3 = low and ENEMY or WHITE

		local armor = character:GetAttribute("Armor") or 0
		armorBack.Visible = armor > 0
		armorFill.Size = UDim2.fromScale(math.clamp(armor / BuyConfig.ArmorAmount, 0, 1), 1)
	end)

	-- Agent (Porträt, Name, Farbe) bei jedem Spawn bzw. Agentenwechsel
	local function updateAgent()
		local agent = myAgent()
		ownPortrait.Set(agent and agent.Id, player)
		local color = agent and agent.Color or ALLY
		agentLine.Text = agent and (string.upper(agent.Name) .. "  ·  " .. string.upper(agent.Role)) or ""
		agentLine.TextColor3 = color
		portraitStroke.Color = color
		portraitGradient.Color = ColorSequence.new(color:Lerp(PANEL, 0.5), PANEL)
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
	-- Unten rechts: Munition, Waffen-Silhouette, andere Waffe
	-- =====================================================================
	local ammo = make("Frame", { Name = "Ammo", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -22),
		Size = UDim2.fromOffset(320, 94), BackgroundTransparency = 1, Visible = false }, root)
	local iconHolder = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.fromOffset(156, 46), BackgroundTransparency = 1 }, ammo)
	local weaponName = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 50), Size = UDim2.fromOffset(156, 16),
		Text = "", TextSize = 14, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right }, ammo)
	local ammoText = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -168, 0, 0), Size = UDim2.fromOffset(150, 52),
		Text = "", RichText = true, TextSize = 46, TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.4 }, ammo)
	local magBack = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -170, 0, 54), Size = UDim2.fromOffset(110, 3),
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, ammo)
	local magFill = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE, BorderSizePixel = 0 }, magBack)
	-- Andere Waffe: "[2] PISTOLE"
	local swapRow = make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(240, 22),
		BackgroundTransparency = 1 }, ammo)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, swapRow)
	local swapKey = label({ Size = UDim2.fromOffset(24, 20), Text = "", TextSize = 14, BackgroundTransparency = 0.1,
		BackgroundColor3 = PANEL, LayoutOrder = 1 }, swapRow)
	UITheme.Corner(swapKey, 3)
	UITheme.Stroke(swapKey, MUTED, 1, 0.3)
	local swapName = label({ Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Text = "", TextSize = 15,
		TextColor3 = MUTED, LayoutOrder = 2 }, swapRow)

	local shownWeapon, weaponIcon = nil, nil
	local function setWeaponIcon(name)
		if name == shownWeapon then
			return
		end
		shownWeapon = name
		if weaponIcon then
			weaponIcon:Destroy()
		end
		weaponIcon = HUDIcons.Weapon(iconHolder, name, 156, 46)
		if weaponIcon then
			weaponIcon.AnchorPoint = Vector2.new(1, 0)
			weaponIcon.Position = UDim2.fromScale(1, 0)
		end
	end

	-- Andere Waffe des Loadouts mit Taste fürs aktuelle Gerät
	local function updateSwap(current)
		local character = player.Character
		local text = character and character:GetAttribute("Loadout")
		local loadout = text and string.split(text, ",") or {}
		local otherSlot = loadout[1] == current and 2 or 1
		local other = loadout[otherSlot]
		swapRow.Visible = other ~= nil and other ~= current
		if not swapRow.Visible then
			return
		end
		local config = WeaponConfig.Get(other)
		swapName.Text = string.upper(config and config.DisplayName or other)
		local key = InputActions.Hint(otherSlot == 1 and "Weapon1" or "Weapon2")
		if key == "" then
			key = InputActions.Hint("SwapWeapon")
		end
		swapKey.Text = key
		swapKey.Visible = key ~= ""
	end

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
		local color = reloading and MUTED or (mag == 0 and ENEMY or (low and Color3.fromRGB(255, 190, 80) or WHITE))
		ammoText.Text = string.format('<font color="%s">%d</font><font size="22" color="%s"> /%s</font>', hex(color), mag, hex(MUTED),
			infinite and "∞" or tostring(reserve))
		magFill.Size = UDim2.fromScale(ratio, 1)
		magFill.BackgroundColor3 = low and ENEMY or WHITE
		weaponName.Text = reloading and "LÄDT NACH ..." or string.upper(config.DisplayName)
		weaponName.TextColor3 = reloading and C.Play or MUTED
		if weaponIcon then
			weaponIcon.ImageColor3 = mag == 0 and ENEMY or WHITE
			weaponIcon.ImageTransparency = reloading and 0.45 or 0
		end
		updateSwap(name)
	end)
	InputActions.DeviceChanged:Connect(function()
		if shownWeapon then
			updateSwap(shownWeapon)
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
				local gui = make("BillboardGui", { Name = "ObjectiveMarker", Adornee = part, AlwaysOnTop = true, LightInfluence = 0,
					Size = UDim2.fromOffset(90, 84), StudsOffset = Vector3.new(0, 6, 0), ResetOnSpawn = false, Enabled = false,
					ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
				local state = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(90, 14),
					Text = "", TextSize = 13 }, gui)
				local diamond = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 38),
					Size = UDim2.fromOffset(30, 30), Rotation = 45, BackgroundColor3 = PANEL, BackgroundTransparency = 0.3,
					BorderSizePixel = 0 }, gui)
				local stroke = UITheme.Stroke(diamond, WHITE, 2)
				local inner = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(0, 0), BackgroundColor3 = ALLY, BorderSizePixel = 0 }, diamond)
				local letter = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 38), Size = UDim2.fromOffset(30, 30),
					Text = objective.Label, TextSize = 22, TextStrokeTransparency = 0.3 }, gui)
				local distance = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.fromOffset(90, 16),
					Text = "", TextSize = 15 }, gui)
				table.insert(markers, { Gui = gui, Part = part, Diamond = diamond, Inner = inner, Stroke = stroke, Letter = letter,
					Distance = distance, State = state })
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

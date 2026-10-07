-- InspectView (ModuleScript, nur Client)
-- Präsentation beim Inspizieren der Waffe (Taste X, WeaponClient):
--   * Das HUD verschwindet: die HUD-Oberflächen (HUD_GUIS) werden für die Dauer aus der PlayerGui genommen und danach
--     unverändert zurückgelegt (die Module, denen sie gehören, merken davon nichts), der Chat wird ausgeblendet.
--     Die Touch-Knöpfe bleiben, damit man weiter steuern und abbrechen kann.
--   * Kino-Look: schmale Balken oben und unten (unten läuft dünn der Fortschritt mit), dunkle Ränder, der Hintergrund
--     wird weich unscharf (Tiefenschärfe, die Waffe vorne bleibt scharf) und das Sichtfeld etwas enger.
--   * Unten links eine Karte zur Waffe: Name, Skin mit Seltenheit, Meisterschaft mit Fortschritt zur nächsten Stufe,
--     Aufsätze und Werte (Schaden, Feuerrate, Magazin, Reichweite) als Balken; unten rechts die Taste zum Schließen.
-- Alles blendet weich ein und aus.
--   InspectView.Start(weaponName, thirdPerson)  InspectView.SetProgress(t)  InspectView.Stop()  InspectView.IsActive()

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = script.Parent
local UITheme = require(Shared.UITheme)
local WeaponConfig = require(Shared.WeaponConfig)
local Cosmetics = require(Shared.Cosmetics)
local MasteryConfig = require(Shared.MasteryConfig)
local AttachmentConfig = require(Shared.AttachmentConfig)
local InputActions = require(Shared.InputActions)
local Movement = require(Shared.Movement)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make = UITheme.Make
local upper = UITheme.Upper

local InspectView = {}

-- Oberflächen (Namen in der PlayerGui), die beim Inspizieren verschwinden. Menüs sind dann ohnehin zu.
InspectView.HudGuis = { "HUD", "Ability", "ExtinctionHUD", "Killstreaks", "LevelBadge", "Notifications",
	"NotificationCards", "ObjectivePrompt", "Scoreboard", "NoclipHUD", "PartyInvite" }

local FADE_IN, FADE_OUT = 0.4, 0.3
local BAR = 0.07              -- Kino-Balken: Anteil der Bildhöhe
local FOV_IN = 9              -- Ego: Sichtfeld so viel enger (Schulterkamera: FOV_IN_THIRD)
local FOV_IN_THIRD = 5
local BLUR = 0.55             -- Unschärfe im Hintergrund (DepthOfField FarIntensity)
local CARD_WIDTH = 520
local STAT_WIDTH = 230

local gui, root, topBar, bottomBar, progressLine, vignette, card, hint, focus
local vignetteStrips = {}
local hidden = {}             -- weggenommene Oberflächen
local chatWasOn = false
local active = false
local token = 0               -- jede Start/Stop-Runde; späte Tweens der vorigen Runde räumen nicht mehr auf

local function tween(object, time, props, style)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local t = TweenService:Create(object, info, props)
	t:Play()
	return t
end

-- ---------- HUD weg und wieder da ----------

local function hideHud()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for _, name in InspectView.HudGuis do
		local screen = playerGui:FindFirstChild(name)
		if screen and screen:IsA("LayerCollector") then
			table.insert(hidden, screen)
			screen.Parent = nil
		end
	end
	local ok, chatOn = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat)
	chatWasOn = ok and chatOn == true
	if chatWasOn then
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, false)
	end
end

local function showHud()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	for _, screen in hidden do
		pcall(function()
			screen.Parent = playerGui
		end)
	end
	table.clear(hidden)
	if chatWasOn then
		chatWasOn = false
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, true)
	end
end

-- ---------- Werte der Waffe ----------

local function statOf(cfg, kind)
	if kind == "Damage" then
		return cfg.Damage * (cfg.Pellets or 1)
	elseif kind == "Rate" then
		return 60 / math.max(cfg.FireDelay, 0.01)
	elseif kind == "Mag" then
		return cfg.MagazineSize
	end
	return cfg.Range
end

local STATS = {
	{ Kind = "Damage", Label = "SCHADEN" },
	{ Kind = "Rate", Label = "FEUERRATE" },
	{ Kind = "Mag", Label = "MAGAZIN" },
	{ Kind = "Range", Label = "REICHWEITE" },
}

-- Größter Wert aller Waffen (für die Balken)
local function statMax(kind)
	local best = 0
	for _, cfg in WeaponConfig.Weapons do
		best = math.max(best, statOf(cfg, kind))
	end
	return math.max(best, 1)
end

local function statText(cfg, kind)
	if kind == "Damage" then
		return cfg.Pellets and (cfg.Pellets .. " × " .. cfg.Damage) or tostring(cfg.Damage)
	elseif kind == "Rate" then
		return math.floor(statOf(cfg, kind) + 0.5) .. " / MIN"
	end
	return tostring(math.floor(statOf(cfg, kind) + 0.5))
end

-- Skin der Waffe: Name und Farbe (Seltenheit), sonst Standard
local function skinInfo(weaponName)
	local character = player.Character
	local agent = (character and character:GetAttribute("Agent")) or player:GetAttribute("Agent")
	local ok, skin = pcall(Cosmetics.WeaponSkin, player, agent, weaponName)
	if not ok or not skin then
		return "STANDARD", C.Muted
	end
	local rarity = skin.Rarity and Cosmetics.Rarities[skin.Rarity]
	if rarity then
		return upper(skin.Name) .. "  ·  " .. upper(rarity.Name), rarity.Color
	end
	return upper(skin.Name or "SKIN"), skin.Color or C.Primary
end

-- Meisterschaft: erreichte Stufe, Kills, Fortschritt zur nächsten (0..1), Farbe der nächsten Stufe
local function masteryInfo(weaponName)
	if not MasteryConfig.HasMastery(weaponName) then
		return nil
	end
	local kills = MasteryConfig.Kills(player, weaponName)
	local reached = nil
	for _, tier in MasteryConfig.Tiers do
		if kills >= tier.Kills then
			reached = tier
		end
	end
	local nextTier, progress = MasteryConfig.Next(kills)
	return {
		Text = (reached and upper(reached.Name) or "KEINE STUFE") .. "  ·  " .. kills .. " KILLS",
		Color = reached and reached.Color or C.Text,
		Next = nextTier and ("NÄCHSTE: " .. upper(nextTier.Name) .. " (" .. nextTier.Kills .. ")") or "ALLE STUFEN",
		NextColor = nextTier and nextTier.Color or C.Primary,
		Progress = math.clamp(progress or 1, 0, 1),
	}
end

local function attachmentText(weaponName)
	local names = {}
	for _, id in AttachmentConfig.EquippedList(player, weaponName) do
		local item = AttachmentConfig.Get(id)
		if item then
			table.insert(names, upper(item.Name))
		end
	end
	return #names > 0 and table.concat(names, "  ·  ") or "KEINE"
end

-- ---------- Aufbau ----------

local function label(props, parent)
	return UITheme.Label(props, parent)
end

local function bar(parent, x, y, width, fraction, color)
	local back = make("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, 4), BackgroundColor3 = C.Text,
		BackgroundTransparency = 0.82, BorderSizePixel = 0 }, parent)
	UITheme.Corner(back, 2)
	local fill = make("Frame", { Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1), BackgroundColor3 = color,
		BorderSizePixel = 0 }, back)
	UITheme.Corner(fill, 2)
	return back
end

-- Karte zur Waffe neu füllen
local function fillCard(weaponName)
	for _, child in card:GetChildren() do
		if not child:IsA("UIGradient") and child.Name ~= "Back" then
			child:Destroy()
		end
	end
	local cfg = WeaponConfig.Get(weaponName)
	if not cfg then
		return
	end
	local y = 16
	UITheme.Diamond(card, 8, UDim2.fromOffset(24, y + 7), C.Primary)
	label({ Position = UDim2.fromOffset(38, y), Size = UDim2.fromOffset(300, 14), Text = "INSPEKTION", TextSize = 12,
		TextColor3 = C.Primary }, card)
	y += 18
	local title = label({ Position = UDim2.fromOffset(20, y), Size = UDim2.fromOffset(CARD_WIDTH - 40, 56),
		Text = upper(cfg.DisplayName or weaponName), TextSize = 52, Font = F.Display }, card)
	UITheme.Outline(title, 1)
	y += 62
	make("Frame", { Position = UDim2.fromOffset(20, y), Size = UDim2.fromOffset(64, 3), BackgroundColor3 = C.Primary,
		BorderSizePixel = 0 }, card)
	make("Frame", { Position = UDim2.fromOffset(88, y + 1), Size = UDim2.fromOffset(CARD_WIDTH - 128, 1), BackgroundColor3 = C.Text,
		BackgroundTransparency = 0.8, BorderSizePixel = 0 }, card)
	y += 16

	-- Skin, Meisterschaft, Aufsätze
	local function row(name, text, color)
		label({ Position = UDim2.fromOffset(20, y), Size = UDim2.fromOffset(150, 18), Text = name, TextSize = 12,
			TextColor3 = C.Muted }, card)
		local value = label({ Position = UDim2.fromOffset(170, y), Size = UDim2.fromOffset(CARD_WIDTH - 190, 18), Text = text,
			TextSize = 14, TextColor3 = color or C.Text, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		y += 24
		return value
	end
	local skinText, skinColor = skinInfo(weaponName)
	row("SKIN", skinText, skinColor)
	local mastery = masteryInfo(weaponName)
	if mastery then
		-- Stufe und Kills, darunter der Fortschritt zur nächsten Stufe (in deren Farbe)
		row("MEISTERSCHAFT", mastery.Text, mastery.Color)
		bar(card, 170, y - 4, 200, mastery.Progress, mastery.NextColor)
		label({ Position = UDim2.fromOffset(380, y - 10), Size = UDim2.fromOffset(CARD_WIDTH - 390, 14), Text = mastery.Next,
			TextSize = 10, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		y += 10
	end
	row("AUFSÄTZE", attachmentText(weaponName))
	y += 6

	-- Werte als Balken (im Vergleich zur stärksten Waffe)
	for _, stat in STATS do
		label({ Position = UDim2.fromOffset(20, y), Size = UDim2.fromOffset(150, 16), Text = stat.Label, TextSize = 11,
			TextColor3 = C.Muted }, card)
		bar(card, 170, y + 6, STAT_WIDTH, statOf(cfg, stat.Kind) / statMax(stat.Kind), C.Text)
		label({ Position = UDim2.fromOffset(170 + STAT_WIDTH + 12, y), Size = UDim2.fromOffset(100, 16),
			Text = statText(cfg, stat.Kind), TextSize = 12 }, card)
		y += 22
	end
	card.Size = UDim2.fromOffset(CARD_WIDTH, y + 14)
end

-- Taste zum Schließen je nach Gerät (Touch: INSPEKT-Knopf, darum ohne Hinweis)
local function fillHint()
	for _, child in hint:GetChildren() do
		child:Destroy()
	end
	local device = InputActions.Device()
	hint.Visible = device ~= "Touch"
	local key = device == "Gamepad" and "□" or InputActions.Hint("Inspect")
	if key == "" then
		key = "X"
	end
	local cap = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -112, 0.5, 0), Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = C.Text, BackgroundTransparency = 0.88, BorderSizePixel = 0 }, hint)
	UITheme.Corner(cap, 6)
	UITheme.Stroke(cap, C.Text, 1, 0.55)
	label({ Size = UDim2.fromScale(1, 1), Text = key, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center }, cap)
	label({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(100, 20),
		Text = "SCHLIESSEN", TextSize = 13, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Right }, hint)
end

local function build()
	gui = make("ScreenGui", { Name = "Inspect", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 3, Enabled = false },
		player:WaitForChild("PlayerGui"))
	-- dunkle Ränder (vier Verläufe vom Rand nach innen)
	vignette = make("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	for _, side in { { UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0), 90 }, { UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.7), 270 },
		{ UDim2.fromScale(0.24, 1), UDim2.fromScale(0, 0), 0 }, { UDim2.fromScale(0.24, 1), UDim2.fromScale(0.76, 0), 180 } } do
		local strip = make("Frame", { Size = side[1], Position = side[2], BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1, BorderSizePixel = 0 }, vignette)
		make("UIGradient", { Rotation = side[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 1) }) }, strip)
		table.insert(vignetteStrips, strip)
	end
	-- Kino-Balken, unten mit dünner Fortschrittslinie
	topBar = make("Frame", { Name = "TopBar", Size = UDim2.fromScale(1, BAR), Position = UDim2.fromScale(0, -BAR),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.04, BorderSizePixel = 0 }, gui)
	bottomBar = make("Frame", { Name = "BottomBar", AnchorPoint = Vector2.new(0, 1), Size = UDim2.fromScale(1, BAR),
		Position = UDim2.fromScale(0, 1 + BAR), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.04,
		BorderSizePixel = 0 }, gui)
	progressLine = make("Frame", { Name = "Progress", Size = UDim2.new(0, 0, 0, 2), BackgroundColor3 = C.Primary,
		BackgroundTransparency = 0.15, BorderSizePixel = 0 }, bottomBar)
	-- Karte und Hinweis auf der skalierten Ebene
	root = UITheme.ScaledRoot(gui)
	card = make("CanvasGroup", { Name = "Card", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 56, 1 - BAR, -24),
		Size = UDim2.fromOffset(CARD_WIDTH, 300), BackgroundTransparency = 1, GroupTransparency = 1 }, root)
	-- Hintergrund: links dunkel, nach rechts auslaufend (lesbar auch vor hellem Himmel)
	local back = make("Frame", { Name = "Back", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 0 }, card)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.6, 0.78),
		NumberSequenceKeypoint.new(1, 1) }) }, back)
	UITheme.Corner(back, UITheme.Radius.Medium)
	hint = make("CanvasGroup", { Name = "Hint", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -56, 1 - BAR, -24),
		Size = UDim2.fromOffset(160, 34), BackgroundTransparency = 1, GroupTransparency = 1 }, root)
	-- Tiefenschärfe (Waffe scharf, Hintergrund weich)
	focus = Lighting:FindFirstChild("InspectFocus") or make("DepthOfFieldEffect", { Name = "InspectFocus", Enabled = false,
		FarIntensity = 0, NearIntensity = 0, FocusDistance = 2, InFocusRadius = 2.5 }, Lighting)
end

-- ---------- Ablauf ----------

function InspectView.Start(weaponName, thirdPerson)
	if not gui then
		build()
	end
	token += 1
	active = true
	hideHud()
	fillCard(weaponName)
	fillHint()
	gui.Enabled = true
	progressLine.Size = UDim2.new(0, 0, 0, 2)
	-- Balken, Ränder, Karte (gleitet von links herein), Hinweis
	tween(topBar, FADE_IN, { Position = UDim2.fromScale(0, 0) })
	tween(bottomBar, FADE_IN, { Position = UDim2.fromScale(0, 1) })
	for _, strip in vignetteStrips do
		tween(strip, FADE_IN, { BackgroundTransparency = 0 })
	end
	card.Position = UDim2.new(0, 16, 1 - BAR, -24)
	tween(card, FADE_IN + 0.15, { GroupTransparency = 0, Position = UDim2.new(0, 56, 1 - BAR, -24) })
	tween(hint, FADE_IN + 0.3, { GroupTransparency = 0 })
	-- Hintergrund weich, Sichtfeld enger (Ego: Waffe vor der Kamera, Schulterkamera: Charakter einige Studs entfernt)
	focus.FocusDistance = thirdPerson and 6 or 1.6
	focus.InFocusRadius = thirdPerson and 4 or 2.2
	focus.Enabled = true
	tween(focus, FADE_IN, { FarIntensity = BLUR })
	Movement.SetFovOverride(Movement.GetFov() - (thirdPerson and FOV_IN_THIRD or FOV_IN))
end

-- Fortschritt 0..1 (dünne Linie im unteren Balken)
function InspectView.SetProgress(t)
	if active and progressLine then
		progressLine.Size = UDim2.new(math.clamp(t, 0, 1), 0, 0, 2)
	end
end

function InspectView.Stop()
	if not active then
		return
	end
	active = false
	token += 1
	local myToken = token
	showHud()
	Movement.SetFovOverride(nil)
	tween(topBar, FADE_OUT, { Position = UDim2.fromScale(0, -BAR) })
	tween(bottomBar, FADE_OUT, { Position = UDim2.fromScale(0, 1 + BAR) })
	for _, strip in vignetteStrips do
		tween(strip, FADE_OUT, { BackgroundTransparency = 1 })
	end
	tween(card, FADE_OUT, { GroupTransparency = 1, Position = UDim2.new(0, 36, 1 - BAR, -24) })
	tween(hint, FADE_OUT, { GroupTransparency = 1 })
	tween(focus, FADE_OUT, { FarIntensity = 0 })
	task.delay(FADE_OUT + 0.05, function()
		if token == myToken and not active then
			gui.Enabled = false
			focus.Enabled = false
		end
	end)
end

function InspectView.IsActive()
	return active
end

-- Weggenommene Oberflächen (Tests)
function InspectView.Hidden()
	return hidden
end

return InspectView

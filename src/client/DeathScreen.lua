-- DeathScreen (ModuleScript, nur Client)
-- Todesbildschirm der offenen Welt (Extinction): Bild abgedunkelt mit rotem Rand, groß "DU BIST GESTORBEN", darunter
-- eine Karte mit dem Gegner (Name, Waffe, wie viel Leben er noch hatte), was mit der Tasche passiert ist (draußen: liegt
-- an der Todesstelle, sonst nichts verloren) und unten der Respawn mit Countdown, Balken und Ort (Safe Zone, in der man
-- zuletzt war: Spieler-Attribut "ExtHome"). Verschwindet beim Respawn. In den anderen Modi bleibt die kleine
-- Todesanzeige des HUD.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local AgentConfig = require(Shared.AgentConfig)
local ExtinctionConfig = require(Shared.ExtinctionConfig)

local player = Players.LocalPlayer
local C, F = UITheme.Colors, UITheme.Fonts
local make = UITheme.Make

local DeathScreen = {}

local DEFAULT_HOME = "CAMP PHOENIX"
local SHOW_DELAY = 0.6 -- kurz den Tod sehen, dann einblenden

local screen, root, killerCard, killerName, killerInfo, killerBar, bagTitle, bagText, countText, placeText, fill
local diedAt = nil
local lastRecap, lastRecapAt = nil, -math.huge -- die Meldung des Servers kann vor oder nach dem Tod ankommen
local shown = false

local function inSurvival()
	return Modes.IsSurvival(player:GetAttribute("Mode"))
end

local function build()
	screen = make("ScreenGui", { Name = "DeathScreen", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20,
		Enabled = false }, player:WaitForChild("PlayerGui"))
	root = UITheme.ScaledRoot(screen)
	-- Abdunkeln, zum Rand hin rot
	local shade = make("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 4, 4),
		BackgroundTransparency = 0.35, BorderSizePixel = 0 }, root)
	local edge = make("Frame", { Name = "Edge", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(120, 16, 12),
		BackgroundTransparency = 0, BorderSizePixel = 0 }, shade)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.25, 1), NumberSequenceKeypoint.new(0.75, 1), NumberSequenceKeypoint.new(1, 0.35) }) }, edge)

	local column = make("Frame", { Name = "Column", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(560, 420), BackgroundTransparency = 1 }, root)
	UITheme.Label({ Name = "Caption", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 18), Text = "EXTINCTION",
		TextSize = 14, Font = F.Bold, TextColor3 = C.Bad, TextXAlignment = Enum.TextXAlignment.Center }, column)
	UITheme.Label({ Name = "Title", Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 64), Text = "DU BIST GESTORBEN",
		TextSize = 56, Font = F.Display, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Center }, column)

	-- Gegner
	killerCard = UITheme.Card({ Name = "Killer", Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 84) }, column)
	UITheme.AccentBar(killerCard, C.Bad, { Side = "Left" })
	UITheme.Label({ Name = "Caption", Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 14), Text = "GETÖTET VON",
		TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 3 }, killerCard)
	killerName = UITheme.Label({ Name = "Name", Position = UDim2.fromOffset(20, 26), Size = UDim2.new(1, -40, 0, 30), Text = "",
		TextSize = 26, Font = F.Display, TextColor3 = C.Text, ZIndex = 3 }, killerCard)
	killerInfo = UITheme.Label({ Name = "Info", Position = UDim2.fromOffset(20, 56), Size = UDim2.new(1, -200, 0, 18), Text = "",
		TextSize = 14, Font = F.Medium, TextColor3 = C.Muted, ZIndex = 3 }, killerCard)
	local barBack = make("Frame", { Name = "HealthBack", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 62),
		Size = UDim2.fromOffset(150, 6), BackgroundColor3 = C.Card, BorderSizePixel = 0, ZIndex = 3 }, killerCard)
	UITheme.Corner(barBack, 3)
	killerBar = make("Frame", { Name = "Health", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Bad, BorderSizePixel = 0,
		ZIndex = 3 }, barBack)
	UITheme.Corner(killerBar, 3)

	-- Tasche
	local bag = UITheme.Card({ Name = "Bag", Position = UDim2.fromOffset(0, 200), Size = UDim2.new(1, 0, 0, 66) }, column)
	bagTitle = UITheme.Label({ Name = "Title", Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40, 0, 22), Text = "",
		TextSize = 18, Font = F.Display, TextColor3 = C.Primary, ZIndex = 3 }, bag)
	bagText = UITheme.Label({ Name = "Text", Position = UDim2.fromOffset(20, 36), Size = UDim2.new(1, -40, 0, 18), Text = "",
		TextSize = 14, Font = F.Medium, TextColor3 = C.Muted, ZIndex = 3 }, bag)

	-- Respawn
	UITheme.Label({ Name = "RespawnCaption", Position = UDim2.fromOffset(0, 292), Size = UDim2.new(1, 0, 0, 16),
		Text = "RESPAWN IN", TextSize = 13, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }, column)
	countText = UITheme.Label({ Name = "Count", Position = UDim2.fromOffset(0, 308), Size = UDim2.new(1, 0, 0, 56), Text = "",
		TextSize = 52, Font = F.Display, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Center }, column)
	local track = make("Frame", { Name = "Track", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 372),
		Size = UDim2.fromOffset(260, 4), BackgroundColor3 = C.Card, BorderSizePixel = 0 }, column)
	UITheme.Corner(track, 2)
	fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Primary, BorderSizePixel = 0 }, track)
	UITheme.Corner(fill, 2)
	placeText = UITheme.Label({ Name = "Place", Position = UDim2.fromOffset(0, 386), Size = UDim2.new(1, 0, 0, 20), Text = "",
		TextSize = 15, Font = F.Bold, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Center }, column)
end

local function setKiller(name, weapon, health, agentId)
	if not name then
		killerCard.Visible = false
		return
	end
	local agent = agentId and AgentConfig.Get(agentId)
	killerCard.Visible = true
	killerName.Text = UITheme.Upper(tostring(name))
	killerInfo.Text = (agent and (agent.Name .. "  ·  ") or "") .. tostring(weapon or "?")
	local ratio = math.clamp((tonumber(health) or 0) / 100, 0, 1)
	killerBar.Size = UDim2.fromScale(ratio, 1)
	killerBar.BackgroundColor3 = ratio > 0.5 and C.Good or ratio > 0.25 and C.Primary or C.Bad
end

local function show(outside)
	shown = true
	if outside then
		bagTitle.Text = "DEINE TASCHE LIEGT AN DER TODESSTELLE"
		bagText.Text = "Noch " .. math.floor(ExtinctionConfig.BagLifetime / 60) .. " Minuten · auf Minimap und Karte (N) markiert"
			.. " · jeder kann sie plündern"
		bagTitle.TextColor3 = C.Primary
	else
		bagTitle.Text = "NICHTS VERLOREN"
		bagText.Text = "Du warst in der Safe Zone · dein Lager bleibt immer"
		bagTitle.TextColor3 = C.Good
	end
	local home = player:GetAttribute("ExtHome")
	placeText.Text = UITheme.Upper(type(home) == "string" and home ~= "" and home or DEFAULT_HOME)
	screen.Enabled = true
	root.Shade.BackgroundTransparency = 1
	TweenService:Create(root.Shade, TweenInfo.new(0.4), { BackgroundTransparency = 0.35 }):Play()
end

local function hide()
	shown, diedAt = false, nil
	if screen then
		screen.Enabled = false
	end
end

local function track(character)
	hide()
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		if not inSurvival() or player.Character ~= character then
			return
		end
		local outside = player:GetAttribute("InSafeZone") ~= true
		diedAt = os.clock()
		if lastRecap and diedAt - lastRecapAt < 2 then
			setKiller(table.unpack(lastRecap))
		else
			setKiller(nil)
		end
		local myDeath = diedAt
		task.delay(SHOW_DELAY, function()
			if diedAt == myDeath and player.Character == character then
				show(outside)
			end
		end)
	end)
end

function DeathScreen.Init()
	build()
	Remotes.DeathRecap.OnClientEvent:Connect(function(killerName, weaponName, killerHealth, agentId)
		if inSurvival() then
			lastRecap, lastRecapAt = { killerName, weaponName, killerHealth, agentId }, os.clock()
			setKiller(killerName, weaponName, killerHealth, agentId)
		end
	end)
	player.CharacterAdded:Connect(track)
	if player.Character then
		task.spawn(track, player.Character)
	end
	player:GetAttributeChangedSignal("Mode"):Connect(function()
		if not inSurvival() then
			hide()
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not shown or not diedAt then
			return
		end
		local total = ExtinctionConfig.RespawnTime
		local left = math.max(0, total - (os.clock() - diedAt))
		countText.Text = tostring(math.ceil(left))
		fill.Size = UDim2.fromScale(1 - left / total, 1)
	end)
end

-- Für Tests: ist der Todesbildschirm gerade zu sehen?
function DeathScreen.IsShown()
	return shown and screen ~= nil and screen.Enabled
end

return DeathScreen

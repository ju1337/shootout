-- KillstreakHUD (ModuleScript, nur Client)
-- Killstreaks in Herrschaft rechts am Rand in der Mitte: eine Karte pro Belohnung (KillstreakConfig) mit Taste,
-- Name und Fortschritt (Kills dieses Lebens / nötige Kills). Bereite Karten leuchten in ihrer Farbe und werden mit
-- 4/5/6 ausgelöst (Controller: Steuerkreuz rechts = erste bereite, Touch/Maus: Karte antippen).
-- Luftschlag: Ziel ist der Punkt unter dem Fadenkreuz. Daten: Spieler-Attribute Killstreak, KillstreakReady.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)
local KillstreakConfig = require(Shared.KillstreakConfig)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make = UITheme.Make
local label = UITheme.Label

local KillstreakHUD = {}

local CARD_W, CARD_H, GAP = 230, 58, 8

local function readyList()
	local raw = player:GetAttribute("KillstreakReady")
	local ok, data = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "{}")
	return ok and type(data) == "table" and data or {}
end

-- Punkt unter dem Fadenkreuz (Boden oder Wand), für den Luftschlag
local function aimPoint()
	local camera = workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, workspace:FindFirstChild("Bots") }
	local result = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 400, params)
	return result and result.Position or nil
end

local function use(entry)
	if not readyList()[entry.Id] then
		return
	end
	Remotes.UseKillstreak:FireServer(entry.Id, entry.Aim and aimPoint() or nil)
end

function KillstreakHUD.Init()
	local gui = make("ScreenGui", { Name = "Killstreaks", ResetOnSpawn = false, IgnoreGuiInset = true, Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	local root = UITheme.ScaledRoot(gui)
	local count = #KillstreakConfig.List
	local column = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 0),
		Size = UDim2.fromOffset(CARD_W, count * CARD_H + (count - 1) * GAP + 22), BackgroundTransparency = 1 }, root)
	label({ Size = UDim2.new(1, 0, 0, 18), Text = "KILLSTREAKS", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.6 }, column)
	local cards = {}
	for i, entry in KillstreakConfig.List do
		local card = make("TextButton", { Position = UDim2.fromOffset(0, 22 + (i - 1) * (CARD_H + GAP)), Size = UDim2.fromOffset(CARD_W, CARD_H),
			BackgroundColor3 = C.Background, BackgroundTransparency = 0.3, Text = "", AutoButtonColor = false, Selectable = false,
			ClipsDescendants = true }, column)
		UITheme.Corner(card, UITheme.Radius.Small)
		local stroke = UITheme.Stroke(card, entry.Color, 1.5, 1)
		local icon = make("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = entry.Color,
			BackgroundTransparency = 0.7 }, card)
		UITheme.Corner(icon, UITheme.Radius.Small)
		local letter = label({ Size = UDim2.fromScale(1, 1), Text = entry.Short, TextSize = 26, Font = F.Display,
			TextXAlignment = Enum.TextXAlignment.Center }, icon)
		local name = label({ Position = UDim2.fromOffset(60, 7), Size = UDim2.new(1, -110, 0, 22), Text = entry.Name, TextSize = 19,
			Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		local sub = label({ Position = UDim2.fromOffset(60, 30), Size = UDim2.new(1, -70, 0, 16), Text = "", TextSize = 12,
			Font = F.Bold, TextColor3 = C.Muted }, card)
		local key = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(28, 22),
			Text = "", TextSize = 13, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Center }, card)
		UITheme.Corner(key, UITheme.Radius.Small)
		local keyStroke = UITheme.Stroke(key, C.Muted, 1, 0.4)
		local track = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88, BorderSizePixel = 0 }, card)
		local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = entry.Color, BorderSizePixel = 0 }, track)
		card.Activated:Connect(function()
			use(entry)
		end)
		cards[entry.Id] = { Card = card, Stroke = stroke, Icon = icon, Letter = letter, Name = name, Sub = sub, Key = key,
			KeyStroke = keyStroke, Fill = fill, WasReady = false }
	end

	local function refresh()
		local inMode = KillstreakConfig.Modes[player:GetAttribute("Mode")] == true
		gui.Enabled = inMode
		if not inMode then
			return
		end
		local kills = player:GetAttribute("Killstreak") or 0
		local ready = readyList()
		local touch = InputActions.IsTouch()
		local padFirst = true
		for _, entry in KillstreakConfig.List do
			local c = cards[entry.Id]
			local isReady = ready[entry.Id] == true
			c.Card.BackgroundTransparency = isReady and 0.15 or 0.35
			c.Stroke.Transparency = isReady and 0 or 1
			c.Icon.BackgroundTransparency = isReady and 0.2 or 0.75
			c.Letter.TextColor3 = isReady and C.Text or C.Muted
			c.Name.TextColor3 = isReady and C.Text or C.Muted
			c.Fill.Size = UDim2.fromScale(isReady and 1 or math.clamp(kills / entry.Kills, 0, 1), 1)
			-- Taste fürs aktuelle Gerät (Controller: Steuerkreuz rechts für die erste bereite)
			local hint = InputActions.Hint(entry.Action)
			if InputActions.Device() == "Gamepad" then
				hint = (isReady and padFirst) and InputActions.Hint("KillstreakPad") or ""
			end
			if isReady then
				padFirst = false
			end
			c.Key.Visible = not touch and hint ~= ""
			c.Key.Text = hint
			c.KeyStroke.Color = isReady and entry.Color or C.Muted
			c.Sub.Text = isReady and (touch and "BEREIT · ANTIPPEN" or "BEREIT") or (math.min(kills, entry.Kills) .. " / " .. entry.Kills .. " KILLS")
			c.Sub.TextColor3 = isReady and entry.Color or C.Muted
			-- frisch bereit: kurz aufblitzen
			if isReady and not c.WasReady then
				c.Card.BackgroundColor3 = entry.Color
				TweenService:Create(c.Card, TweenInfo.new(0.8), { BackgroundColor3 = C.Background }):Play()
			end
			c.WasReady = isReady
		end
	end
	refresh()
	for _, attribute in { "Killstreak", "KillstreakReady", "Mode" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	InputActions.DeviceChanged:Connect(refresh)

	-- Tasten 4/5/6 und Controller (erste bereite)
	for _, entry in KillstreakConfig.List do
		InputActions.Bind(entry.Action, function(began)
			if began and gui.Enabled then
				use(entry)
			end
		end)
	end
	InputActions.Bind("KillstreakPad", function(began)
		if not began or not gui.Enabled then
			return
		end
		local ready = readyList()
		for _, entry in KillstreakConfig.List do
			if ready[entry.Id] then
				use(entry)
				return
			end
		end
	end)
end

return KillstreakHUD

-- LevelBadge (ModuleScript, nur Client)
-- Spielerlevel immer sichtbar (außer in Menüs): Prestige-Abzeichen mit Level, "LEVEL 23" und XP-Balken.
--   Kampf:   unten links über der Lebensanzeige (Touch: oben links unter Minimap und Leben)
--   Hub:     unten links (Touch: oben links unter der Roblox-Leiste)
-- Ausgeblendet, solange ein Menü offen ist (Spiel- und Seitenmenü, Agentenwahl, Map-Abstimmung,
-- Match-Zusammenfassung, Punktestand).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.UITheme)
local LevelConfig = require(Shared.LevelConfig)
local PrestigeEmblem = require(Shared.PrestigeEmblem)
local Modes = require(Shared.Modes)
local InputActions = require(Shared.InputActions)

local player = Players.LocalPlayer
local make = UITheme.Make
local C = UITheme.Colors

local LevelBadge = {}

local MENU_GUIS = { "AgentSelect", "MapVote", "MatchSummary", "GameMenu", "Scoreboard" }

function LevelBadge.Init()
	local playerGui = player:WaitForChild("PlayerGui")
	local screen = make("ScreenGui", { Name = "LevelBadge", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 2 },
		playerGui)
	local root = UITheme.ScaledRoot(screen)
	local rootScale = root:FindFirstChildOfClass("UIScale")

	local badge = make("Frame", { Name = "Badge", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -118),
		Size = UDim2.fromOffset(250, 46), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, root)
	UITheme.Corner(badge, 4)
	make("UIGradient", { Transparency = NumberSequence.new(0, 0.7) }, badge)
	local emblemHolder = make("Frame", { Position = UDim2.fromOffset(2, 1), Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 1 }, badge)
	local emblem = PrestigeEmblem.new(emblemHolder, 44)
	local levelText = UITheme.Label({ Position = UDim2.fromOffset(54, 3), Size = UDim2.fromOffset(190, 22), Text = "",
		TextSize = 20, Font = UITheme.Fonts.Title, TextStrokeTransparency = 0.5 }, badge)
	local barBack = make("Frame", { Position = UDim2.fromOffset(54, 29), Size = UDim2.fromOffset(180, 5),
		BackgroundColor3 = C.Background, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, badge)
	local barFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, BorderSizePixel = 0 }, barBack)
	local xpText = UITheme.Label({ Position = UDim2.fromOffset(54, 34), Size = UDim2.fromOffset(190, 12), Text = "",
		TextSize = 10, TextColor3 = C.Muted }, badge)

	local function refresh()
		local info = LevelConfig.Get(player)
		emblem:Set(info.Level, info.Prestige)
		levelText.Text = "LEVEL " .. info.Level .. (info.Prestige > 0 and ("  ·  PRESTIGE " .. info.Prestige) or "")
		levelText.TextColor3 = info.Prestige > 0 and info.Color or C.Text
		barFill.Size = UDim2.fromScale(math.clamp(info.Progress, 0, 1), 1)
		barFill.BackgroundColor3 = info.Color
		xpText.Text = info.Needed > 0 and (info.XP .. " / " .. info.Needed .. " XP") or "MAXIMALES LEVEL"
	end
	refresh()
	player:GetAttributeChangedSignal("AccountXP"):Connect(refresh)
	player:GetAttributeChangedSignal("Prestige"):Connect(refresh)

	-- Offenes Menü?
	local function menuOpen()
		if UITheme.IsMenuOpen() then
			return true
		end
		for _, name in MENU_GUIS do
			local gui = playerGui:FindFirstChild(name)
			if gui and gui:IsA("ScreenGui") and gui.Enabled then
				return true
			end
		end
		return false
	end

	-- Platz: über der Lebensanzeige bzw. (Touch) oben links unter Minimap und Leben
	local function place()
		local fighting = Modes.IsFighting(player)
		if InputActions.IsTouch() then
			local inset = GuiService:GetGuiInset()
			local scale = rootScale and rootScale.Scale or 1
			local top = math.max(58, math.ceil((inset.Y + 8) / scale))
			badge.AnchorPoint = Vector2.new(0, 0)
			-- im Kampf liegen Minimap (160) und Leben (84) darüber
			badge.Position = UDim2.new(0, 16, 0, fighting and (top + 172 + 92) or top)
		else
			badge.AnchorPoint = Vector2.new(0, 1)
			badge.Position = UDim2.new(0, 24, 1, fighting and -118 or -24)
		end
	end

	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextCheck then
			return
		end
		nextCheck = now + 0.2
		screen.Enabled = not menuOpen()
		if screen.Enabled then
			place()
		end
	end)
end

return LevelBadge

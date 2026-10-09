-- LevelBadge (ModuleScript, nur Client)
-- Spielerlevel im Match: Prestige-Abzeichen mit Level, "LEVEL 23" und XP-Balken unten links über der
-- Lebensanzeige (Touch: oben links unter Minimap und Leben). Im Markt nicht – dort steht das Level groß
-- in der Lobby. Ausgeblendet, solange ein Menü offen ist (Spiel- und Seitenmenü, Agentenwahl,
-- Map-Abstimmung, Match-Zusammenfassung, Punktestand). In der offenen Welt nicht: dort steht das Level als schmale
-- Zeile unter der Hotbar (ExtinctionClient).

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

	-- Fläche im Design der Lobby (runde Ecken, Rand), etwas durchsichtig
	local badge = make("Frame", { Name = "Badge", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -122),
		Size = UDim2.fromOffset(250, 48), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, root)
	UITheme.Corner(badge, UITheme.Radius.Large)
	UITheme.Stroke(badge, C.Border, 2)
	local emblemHolder = make("Frame", { Position = UDim2.fromOffset(2, 1), Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 1 }, badge)
	local emblem = PrestigeEmblem.new(emblemHolder, 44)
	local levelText = UITheme.Label({ Position = UDim2.fromOffset(54, 5), Size = UDim2.fromOffset(190, 20), Text = "",
		TextSize = 15, Font = UITheme.Fonts.Display }, badge)
	local barBack = make("Frame", { Position = UDim2.fromOffset(54, 28), Size = UDim2.fromOffset(180, 6),
		BackgroundColor3 = C.Background, BorderSizePixel = 0 }, badge)
	UITheme.Corner(barBack, 3)
	local barFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Primary, BorderSizePixel = 0 }, barBack)
	UITheme.Corner(barFill, 3)
	local xpText = UITheme.Label({ Position = UDim2.fromOffset(54, 35), Size = UDim2.fromOffset(190, 12), Text = "",
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

	-- Platz: über der Lebensanzeige bzw. (Touch) oben links unter Minimap (160) und Leben (84)
	local function place()
		if InputActions.IsTouch() then
			local inset = GuiService:GetGuiInset()
			local scale = rootScale and rootScale.Scale or 1
			local top = math.max(58, math.ceil((inset.Y + 8) / scale))
			badge.AnchorPoint = Vector2.new(0, 0)
			badge.Position = UDim2.new(0, 16, 0, top + 172 + 92)
		else
			badge.AnchorPoint = Vector2.new(0, 1)
			badge.Position = UDim2.new(0, 24, 1, -122) -- über der Lebens-Fläche (88 hoch + Schatten)
		end
	end

	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextCheck then
			return
		end
		nextCheck = now + 0.2
		-- im Markt zeigt die Lobby das Level, in der offenen Welt die Zeile unter der Hotbar
		screen.Enabled = Modes.IsFighting(player) and not Modes.IsSurvival(player:GetAttribute("Mode")) and not menuOpen()
		if screen.Enabled then
			place()
		end
	end)
end

return LevelBadge

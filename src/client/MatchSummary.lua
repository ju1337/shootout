-- MatchSummary (ModuleScript, nur Client)
-- Match-Ende-Bildschirm: SIEG/NIEDERLAGE, Endstand, MVP und eigene Werte (wie bei Rogue Company).
-- Verschwindet nach ein paar Sekunden von selbst.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local player = Players.LocalPlayer

local MatchSummary = {}

local SHOW_TIME = 8

local function label(props, parent)
	local obj = Instance.new("TextLabel")
	obj.BackgroundTransparency = 1
	obj.Font = Enum.Font.GothamBlack
	obj.TextColor3 = Color3.new(1, 1, 1)
	obj.TextStrokeTransparency = 0.5
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

function MatchSummary.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchSummary"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 12
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local background = Instance.new("Frame")
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	background.BackgroundTransparency = 0.35
	background.Parent = gui

	local title = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.28, 0),
		Size = UDim2.new(0, 900, 0, 110), TextSize = 96 }, background)
	local sub = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.38, 0),
		Size = UDim2.new(0, 900, 0, 40), TextSize = 28, Font = Enum.Font.GothamBold }, background)
	local mvp = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 900, 0, 40), TextSize = 30, TextColor3 = Color3.fromRGB(255, 210, 80) }, background)
	local stats = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.6, 0),
		Size = UDim2.new(0, 900, 0, 36), TextSize = 24, Font = Enum.Font.GothamBold }, background)
	local rank = label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.68, 0),
		Size = UDim2.new(0, 900, 0, 36), TextSize = 26, TextColor3 = Color3.fromRGB(120, 230, 255) }, background)

	local showId = 0
	Remotes.MatchSummary.OnClientEvent:Connect(function(data)
		showId += 1
		local myId = showId
		title.Text = data.Winner == nil and "UNENTSCHIEDEN" or (data.Won and "SIEG" or "NIEDERLAGE")
		title.TextColor3 = data.Winner == nil and Color3.fromRGB(220, 220, 220)
			or (data.Won and Color3.fromRGB(110, 230, 130) or Color3.fromRGB(255, 90, 90))
		sub.Text = data.Mode .. "  ·  Endstand " .. data.Score
		mvp.Text = data.Mvp and ("★ MVP: " .. data.Mvp .. "  (" .. data.MvpKills .. " Kills)") or ""
		stats.Text = "Deine Werte:  " .. data.Kills .. " Kills  ·  " .. data.Deaths .. " Tode  ·  "
			.. data.Damage .. " Schaden"
		rank.Text = data.Rank or ""
		gui.Enabled = true
		title.TextTransparency = 1
		TweenService:Create(title, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
		task.delay(SHOW_TIME, function()
			if showId == myId then
				gui.Enabled = false
			end
		end)
	end)
end

return MatchSummary

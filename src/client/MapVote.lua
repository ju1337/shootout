-- MapVote (ModuleScript, nur Client)
-- Map-Abstimmung vor einem Team-Match: bis zu 3 Karten mit Map-Namen und Stimmenzahl.
-- Anklicken oder 1/2/3 drücken. Daten kommen als Spieler-Attribute vom Server
-- (MapVoteOptions, MapVoteEnd, MapVoteCounts, MapVoteMine).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)

local player = Players.LocalPlayer
local C = UITheme.Colors
local make = UITheme.Make

local MapVote = {}

local CARD_W, CARD_H = 340, 200
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }

-- Farbstimmung je Map (Hintergrund der Karte)
local MOODS = {
	Fabrik = { Color3.fromRGB(120, 90, 60), Color3.fromRGB(40, 32, 26) },
	Hafen = { Color3.fromRGB(50, 100, 130), Color3.fromRGB(18, 30, 44) },
	Gletscher = { Color3.fromRGB(150, 200, 230), Color3.fromRGB(40, 70, 95) },
	Zellenblock = { Color3.fromRGB(110, 110, 105), Color3.fromRGB(35, 35, 38) },
	["Kanäle"] = { Color3.fromRGB(200, 150, 120), Color3.fromRGB(45, 60, 75) },
	["Windmühlen"] = { Color3.fromRGB(110, 160, 80), Color3.fromRGB(30, 50, 35) },
	Hochhaus = { Color3.fromRGB(90, 120, 170), Color3.fromRGB(20, 26, 44) },
}

local gui, timerLabel
local cards = {}

local function decode(name)
	local raw = player:GetAttribute(name)
	if type(raw) ~= "string" then
		return nil
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and data or nil
end

local function vote(index)
	if gui.Enabled then
		Remotes.MapVote:FireServer(index)
	end
end

local function build()
	gui = make("ScreenGui", { Name = "MapVote", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 7,
		Enabled = false }, player:WaitForChild("PlayerGui"))
	local dim = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Background, BackgroundTransparency = 0.3,
		BorderSizePixel = 0 }, gui)
	local canvas = UITheme.Canvas(dim, 1600, 900)

	UITheme.Diamond(canvas, 18, UDim2.new(0.5, 0, 0, 236), C.Accent)
	UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 252), Size = UDim2.new(0, 800, 0, 56),
		Text = "MAP-ABSTIMMUNG", Font = UITheme.Fonts.Title, TextSize = 52, TextXAlignment = Enum.TextXAlignment.Center }, canvas)
	timerLabel = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 310),
		Size = UDim2.new(0, 800, 0, 26), Text = "", Font = UITheme.Fonts.Title, TextSize = 22, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)

	local row = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 360),
		Size = UDim2.new(0, CARD_W * 3 + 48, 0, CARD_H), BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 24),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for i = 1, 3 do
		-- Modal: gibt die Maus frei, solange die Abstimmung offen ist
		local card = make("TextButton", { Size = UDim2.new(0, CARD_W, 0, CARD_H), BackgroundColor3 = C.Card, Text = "",
			AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = i, Modal = i == 1 }, row)
		UITheme.Corner(card, 4)
		local gradient = UITheme.Gradient(card, C.Card, C.Panel, 120)
		local stroke = UITheme.Stroke(card, C.Border, 1.5)
		local key = UITheme.Label({ Position = UDim2.new(0, 14, 0, 12), Size = UDim2.new(0, 30, 0, 30), Text = tostring(i),
			Font = UITheme.Fonts.Title, TextSize = 20, BackgroundTransparency = 0, BackgroundColor3 = C.Background,
			TextXAlignment = Enum.TextXAlignment.Center }, card)
		UITheme.Corner(key, 3)
		local name = UITheme.Label({ Position = UDim2.new(0, 18, 1, -76), Size = UDim2.new(1, -36, 0, 46), Text = "",
			Font = UITheme.Fonts.Title, TextSize = 40, TextStrokeTransparency = 0.6 }, card)
		local votes = UITheme.Label({ Position = UDim2.new(0, 18, 1, -32), Size = UDim2.new(1, -36, 0, 22), Text = "",
			Font = UITheme.Fonts.Title, TextSize = 18, TextColor3 = C.Muted }, card)
		local bar = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(0, 0, 0, 4), BackgroundColor3 = C.Accent, BorderSizePixel = 0 }, card)
		local check = UITheme.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12),
			Size = UDim2.new(0, 160, 0, 30), Text = "✓ DEINE WAHL", Font = UITheme.Fonts.Title, TextSize = 18,
			TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Right, Visible = false }, card)
		card.Activated:Connect(function()
			vote(i)
		end)
		cards[i] = { Card = card, Gradient = gradient, Stroke = stroke, Name = name, Votes = votes, Bar = bar, Check = check }
	end
	UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 580), Size = UDim2.new(0, 800, 0, 24),
		Text = "Klicken oder 1 / 2 / 3 drücken", Font = UITheme.Fonts.Body, TextSize = 17, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)
end

local function refresh()
	local options = decode("MapVoteOptions")
	local show = options ~= nil and player:GetAttribute("RoundPhase") == "MapVote"
	gui.Enabled = show
	if not show then
		return
	end
	local counts = decode("MapVoteCounts") or {}
	local mine = player:GetAttribute("MapVoteMine")
	local total = 0
	for _, n in counts do
		total += n
	end
	for i, entry in cards do
		local option = options[i]
		entry.Card.Visible = option ~= nil
		if option then
			local mood = MOODS[option.Name] or { C.Card, C.Panel }
			entry.Gradient.Color = ColorSequence.new(mood[1], mood[2])
			entry.Name.Text = string.upper(option.Name)
			local n = counts[i] or 0
			entry.Votes.Text = n .. (n == 1 and " STIMME" or " STIMMEN")
			entry.Bar.Size = UDim2.new(total > 0 and n / total or 0, 0, 0, 4)
			entry.Stroke.Color = mine == i and C.Accent or C.Border
			entry.Stroke.Thickness = mine == i and 3 or 1.5
			entry.Check.Visible = mine == i
		end
	end
end

function MapVote.Init()
	build()
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 7) == "MapVote" or name == "RoundPhase" then
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local index = table.find(KEYS, input.KeyCode)
		if index then
			vote(index)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if gui.Enabled then
			local left = math.max(0, (player:GetAttribute("MapVoteEnd") or 0) - workspace:GetServerTimeNow())
			timerLabel.Text = "NOCH " .. math.ceil(left) .. " SEKUNDEN"
		end
	end)
	refresh()
end

return MapVote

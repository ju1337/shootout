-- MatchSummary (ModuleScript, nur Client)
-- Match-Ende-Bildschirm im Stil von Rogue Company: breites Band mit SIEG/NIEDERLAGE, Endstand,
-- Modus und Map, MVP-Karte, eigene Werte als Kacheln und die ELO-Änderung (Ranked).
-- Verschwindet nach ein paar Sekunden von selbst.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)

local player = Players.LocalPlayer
local C = UITheme.Colors
local make = UITheme.Make

local MatchSummary = {}

local SHOW_TIME = 8

function MatchSummary.Init()
	local gui = make("ScreenGui", { Name = "MatchSummary", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 12,
		Enabled = false }, player:WaitForChild("PlayerGui"))
	local background = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.25, BorderSizePixel = 0 }, gui)
	local canvas = UITheme.Canvas(background, 1600, 900)

	-- Band quer über den Bildschirm
	local band = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.new(1, 0, 0, 170), BackgroundColor3 = C.Panel, BorderSizePixel = 0 }, canvas)
	local bandGradient = make("UIGradient", { Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.1), NumberSequenceKeypoint.new(0.8, 0.1),
		NumberSequenceKeypoint.new(1, 1) }) }, band)
	local lineTop = make("Frame", { Size = UDim2.new(1, 0, 0, 3), BorderSizePixel = 0 }, band)
	local lineBottom = make("Frame", { Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3), BorderSizePixel = 0 }, band)
	bandGradient:Clone().Parent = lineTop
	bandGradient:Clone().Parent = lineBottom
	local diamond = UITheme.Diamond(band, 26, UDim2.new(0.5, 0, 0, 0), C.Panel, C.Accent)

	local title = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.new(1, 0, 0, 110), Font = UITheme.Fonts.Title, TextSize = 104,
		TextXAlignment = Enum.TextXAlignment.Center }, band)
	local titleScale = make("UIScale", {}, title)
	local sub = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 124),
		Size = UDim2.new(1, 0, 0, 30), Font = UITheme.Fonts.Title, TextSize = 22, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center }, band)

	-- Endstand
	local score = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 336),
		Size = UDim2.new(0, 600, 0, 80), Font = UITheme.Fonts.Title, TextSize = 72, RichText = true,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)

	-- MVP-Karte
	local mvpCard = UITheme.Panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 432),
		Size = UDim2.new(0, 520, 0, 74), BackgroundColor3 = C.Card }, canvas)
	make("Frame", { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = C.Gold, BorderSizePixel = 0 }, mvpCard)
	UITheme.Label({ Position = UDim2.new(0, 24, 0, 8), Size = UDim2.new(1, -48, 0, 20), Text = "★  MVP DES MATCHES",
		Font = UITheme.Fonts.Title, TextSize = 16, TextColor3 = C.Gold }, mvpCard)
	local mvpName = UITheme.Label({ Position = UDim2.new(0, 24, 0, 28), Size = UDim2.new(1, -150, 0, 40),
		Font = UITheme.Fonts.Title, TextSize = 32 }, mvpCard)
	local mvpKills = UITheme.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 28),
		Size = UDim2.new(0, 140, 0, 40), Font = UITheme.Fonts.Title, TextSize = 26, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right }, mvpCard)

	-- Eigene Werte
	local tilesFrame = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 530),
		Size = UDim2.new(0, 760, 0, 110), BackgroundTransparency = 1 }, canvas)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, tilesFrame)
	local tiles = {}
	for i, key in { "KILLS", "TODE", "K/D", "SCHADEN" } do
		local tile = UITheme.Panel({ Size = UDim2.new(0, 181, 1, 0), BackgroundColor3 = C.Card, LayoutOrder = i }, tilesFrame)
		make("Frame", { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = i == 3 and C.Accent or C.Border,
			BorderSizePixel = 0 }, tile)
		UITheme.Label({ Position = UDim2.new(0, 0, 0, 14), Size = UDim2.new(1, 0, 0, 20), Text = key,
			Font = UITheme.Fonts.Title, TextSize = 16, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center }, tile)
		tiles[key] = UITheme.Label({ Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 0, 60),
			Font = UITheme.Fonts.Title, TextSize = 52, TextXAlignment = Enum.TextXAlignment.Center }, tile)
	end

	-- Ranked
	local rankBox = UITheme.Panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 662),
		Size = UDim2.new(0, 760, 0, 54), BackgroundColor3 = C.Card }, canvas)
	local rankText = UITheme.Label({ Size = UDim2.new(1, 0, 1, 0), Font = UITheme.Fonts.Title, TextSize = 26,
		TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Center }, rankBox)

	local footer = UITheme.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 760),
		Size = UDim2.new(0, 600, 0, 24), Font = UITheme.Fonts.Title, TextSize = 18, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center }, canvas)

	local showId = 0
	Remotes.MatchSummary.OnClientEvent:Connect(function(data)
		showId += 1
		local myId = showId
		local color = data.Winner == nil and C.Muted or (data.Won and C.Accent or C.Bad)
		title.Text = data.Winner == nil and "UNENTSCHIEDEN" or (data.Won and "SIEG" or "NIEDERLAGE")
		title.TextColor3 = data.Winner == nil and C.Text or (data.Won and C.Accent or C.Bad)
		lineTop.BackgroundColor3 = color
		lineBottom.BackgroundColor3 = color
		diamond:FindFirstChildOfClass("UIStroke").Color = color
		sub.Text = string.upper(tostring(data.Mode)) .. (data.Map and ("  ·  " .. string.upper(data.Map)) or "")

		local mine, theirs = string.match(tostring(data.Score), "(%d+)%s*:%s*(%d+)")
		score.Text = mine and ('<font color="#28D2E6">' .. mine .. '</font>  :  <font color="#E13741">' .. theirs .. "</font>")
			or tostring(data.Score)

		mvpCard.Visible = data.Mvp ~= nil
		mvpName.Text = string.upper(tostring(data.Mvp or ""))
		mvpName.TextColor3 = data.Mvp == player.Name and C.Accent or C.Text
		mvpKills.Text = (data.MvpKills or 0) .. " KILLS"

		local kills, deaths = data.Kills or 0, data.Deaths or 0
		local kd = deaths > 0 and kills / deaths or kills
		tiles.KILLS.Text = tostring(kills)
		tiles.TODE.Text = tostring(deaths)
		tiles["K/D"].Text = string.format("%.2f", kd)
		tiles["K/D"].TextColor3 = kd >= 1 and C.Good or C.Text
		tiles.SCHADEN.Text = tostring(data.Damage or 0)

		rankBox.Visible = data.Rank ~= nil
		rankText.Text = data.Rank or ""
		rankText.TextColor3 = string.find(data.Rank or "", "^%+") and C.Good or C.Bad

		gui.Enabled = true
		-- Einblenden: Titel springt herein, Band klappt auf
		band.Size = UDim2.new(1, 0, 0, 0)
		TweenService:Create(band, TweenInfo.new(0.35, Enum.EasingStyle.Quart), { Size = UDim2.new(1, 0, 0, 170) }):Play()
		titleScale.Scale = 1.6
		title.TextTransparency = 1
		TweenService:Create(titleScale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		TweenService:Create(title, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()

		task.spawn(function()
			for left = SHOW_TIME, 1, -1 do
				if showId ~= myId then
					return
				end
				footer.Text = "WEITER IN " .. left
				task.wait(1)
			end
			if showId == myId then
				gui.Enabled = false
			end
		end)
	end)
end

return MatchSummary

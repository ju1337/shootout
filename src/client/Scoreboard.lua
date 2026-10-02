-- Scoreboard (ModuleScript, nur Client)
-- Tab gedrückt halten: alle Spieler und Bots im eigenen Modus mit Rang, Agent, Kills, Toden, K/D und
-- Schaden. Im Stil von Rogue Company: Kopfzeile mit Modus, Map und Spielstand, darunter die Teams
-- (eigenes Team in Cyan zuerst, Gegner in Rot). In Free-for-All nach Kills sortiert.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local Modes = require(Shared.Modes)
local RankConfig = require(Shared.RankConfig)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)

local player = Players.LocalPlayer
local C = UITheme.Colors
local make = UITheme.Make

local Scoreboard = {}

local WIDTH = 900
local ME = Color3.fromRGB(28, 62, 78)

-- Spalten: { Schlüssel, Überschrift, Breite, Ausrichtung }
local COLUMNS = {
	{ "Name", "SPIELER", 250, Enum.TextXAlignment.Left },
	{ "Rank", "RANG", 140, Enum.TextXAlignment.Left },
	{ "Agent", "AGENT", 130, Enum.TextXAlignment.Left },
	{ "Kills", "K", 70, Enum.TextXAlignment.Center },
	{ "Deaths", "T", 70, Enum.TextXAlignment.Center },
	{ "KD", "K/D", 80, Enum.TextXAlignment.Center },
	{ "Damage", "SCHADEN", 110, Enum.TextXAlignment.Center },
}

local gui, panel, list, titleLabel, subLabel, scoreLabel
local holding = false

local function rowFrame(order, color, height)
	local frame = make("Frame", { Size = UDim2.new(1, 0, 0, height or 34), BackgroundColor3 = color or C.Card,
		BackgroundTransparency = 0.1, BorderSizePixel = 0, LayoutOrder = order }, list)
	UITheme.Corner(frame, 3)
	local inner = make("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, frame)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder }, inner)
	make("UIPadding", { PaddingLeft = UDim.new(0, 16) }, inner)
	return frame, inner
end

-- colors: optionale Farben pro Spaltenschlüssel
local function cells(inner, values, color, font, colors)
	for i, column in COLUMNS do
		UITheme.Label({ Size = UDim2.new(0, column[3], 1, 0), Text = tostring(values[column[1]] or ""),
			Font = font or UITheme.Fonts.Bold, TextSize = 16, TextColor3 = colors and colors[column[1]] or color or C.Text,
			TextXAlignment = column[4], TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = i }, inner)
	end
end

-- Alle Einträge im eigenen Modus
local function entries()
	local mode = player:GetAttribute("Mode")
	local result = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Mode") == mode then
			local stats = p:FindFirstChild("leaderstats")
			local kills = stats and stats:FindFirstChild("Kills")
			local agentId = (p.Character and p.Character:GetAttribute("Agent")) or p:GetAttribute("Agent")
			local rank = RankConfig.Get(p:GetAttribute("Elo") or RankConfig.StartElo)
			table.insert(result, { Name = p.Name, Rank = rank.Display, RankColor = rank.Color,
				Agent = AgentConfig.Get(agentId), Kills = kills and kills.Value or 0,
				Deaths = p:GetAttribute("Deaths") or 0, Damage = p:GetAttribute("Damage") or 0,
				Team = p.Team and p.Team.Name or nil, IsMe = p == player })
		end
	end
	for _, info in ReplicatedStorage:WaitForChild("BotInfo"):GetChildren() do
		if info:GetAttribute("Mode") == mode then
			local team = info:GetAttribute("TeamName")
			table.insert(result, { Name = info.Name, Rank = "BOT", RankColor = C.Muted,
				Agent = AgentConfig.Get(info:GetAttribute("Agent")), Kills = info:GetAttribute("Kills") or 0,
				Deaths = info:GetAttribute("Deaths") or 0, Damage = "–", Team = team ~= "" and team or nil })
		end
	end
	table.sort(result, function(a, b)
		if a.Kills ~= b.Kills then
			return a.Kills > b.Kills
		end
		return a.Name < b.Name
	end)
	return result
end

local function render()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Kopfzeile: Modus, Map, Spielstand
	local mode = Modes.Get(player:GetAttribute("Mode"))
	titleLabel.Text = string.upper(mode and mode.Name or "")
	subLabel.Text = string.upper(player:GetAttribute("MapName") or "")
	local isTeam = Modes.IsTeamMode(player:GetAttribute("Mode"))
	local mine, enemy = player:GetAttribute("TeamScore"), player:GetAttribute("EnemyScore")
	scoreLabel.Visible = isTeam and mine ~= nil
	scoreLabel.Text = '<font color="#28D2E6">' .. tostring(mine or 0) .. '</font>  :  <font color="#E13741">'
		.. tostring(enemy or 0) .. "</font>"

	local order = 0
	local function add(entry, accent)
		order += 1
		local frame, inner = rowFrame(order, entry.IsMe and ME or nil)
		-- Farbstreifen links (Team/Ich)
		make("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = entry.IsMe and C.Accent or accent or C.Border,
			BorderSizePixel = 0 }, frame)
		local kd = entry.Deaths > 0 and entry.Kills / entry.Deaths or entry.Kills
		cells(inner, {
			Name = entry.Name, Rank = entry.Rank, Agent = entry.Agent and string.upper(entry.Agent.Name) or "–",
			Kills = entry.Kills, Deaths = entry.Deaths, KD = string.format("%.2f", kd), Damage = entry.Damage,
		}, nil, nil, {
			Name = entry.IsMe and C.Accent or C.Text, Rank = entry.RankColor,
			Agent = entry.Agent and entry.Agent.Color or C.Muted, KD = kd >= 1 and C.Good or C.Muted,
		})
	end

	order += 1
	local headerValues = {}
	for _, column in COLUMNS do
		headerValues[column[1]] = column[2]
	end
	local _, headerInner = rowFrame(order, C.Background, 28)
	cells(headerInner, headerValues, C.Muted, UITheme.Fonts.Title)

	local all = entries()
	if isTeam then
		-- Eigenes Team zuerst (Cyan), dann das gegnerische Team (Rot)
		local teamNames = {}
		if player.Team then
			table.insert(teamNames, player.Team.Name)
		end
		for _, entry in all do
			if entry.Team and not table.find(teamNames, entry.Team) then
				table.insert(teamNames, entry.Team)
			end
		end
		for _, teamName in teamNames do
			local own = player.Team and teamName == player.Team.Name
			local color = own and C.Accent or C.Bad
			order += 1
			local header = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = order }, list)
			UITheme.Diamond(header, 12, UDim2.new(0, 12, 0.5, 0), color)
			UITheme.Label({ Position = UDim2.new(0, 30, 0, 0), Size = UDim2.new(1, -30, 1, 0),
				Text = "TEAM " .. string.upper(teamName) .. (own and "  ·  DEIN TEAM" or ""), Font = UITheme.Fonts.Title,
				TextSize = 20, TextColor3 = color }, header)
			for _, entry in all do
				if entry.Team == teamName then
					add(entry, color)
				end
			end
		end
	else
		for _, entry in all do
			add(entry)
		end
	end
end

function Scoreboard.Init()
	gui = make("ScreenGui", { Name = "Scoreboard", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8,
		Enabled = false }, player:WaitForChild("PlayerGui"))
	panel = UITheme.Panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.new(0, WIDTH, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.08 }, gui)
	UITheme.Gradient(panel, Color3.fromRGB(22, 34, 52), C.Panel)
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14) }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, panel)
	-- Auf kleinen Bildschirmen verkleinern
	local scale = make("UIScale", {}, panel)
	local function updateScale()
		scale.Scale = math.clamp((workspace.CurrentCamera.ViewportSize.X - 40) / WIDTH, 0.5, 1)
	end
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	-- Kopf: Modus links, Spielstand in der Mitte
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, LayoutOrder = 1 }, panel)
	make("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = C.Accent, BorderSizePixel = 0 }, head)
	titleLabel = UITheme.Label({ Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(0.5, 0, 0, 32), Text = "",
		Font = UITheme.Fonts.Title, TextSize = 30 }, head)
	subLabel = UITheme.Label({ Position = UDim2.new(0, 16, 0, 32), Size = UDim2.new(0.5, 0, 0, 20), Text = "",
		Font = UITheme.Fonts.Title, TextSize = 16, TextColor3 = C.Muted }, head)
	scoreLabel = UITheme.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.new(0, 260, 1, 0), Text = "", Font = UITheme.Fonts.Title, TextSize = 44, RichText = true,
		TextXAlignment = Enum.TextXAlignment.Right }, head)

	list = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 2 }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	-- Tastatur/Controller: halten. Touch: Knopf schaltet um.
	InputActions.Bind("Scoreboard", function(began)
		if InputActions.IsTouch() then
			if began then
				holding = not holding and Modes.IsFighting(player)
			end
		else
			holding = began and Modes.IsFighting(player)
		end
		gui.Enabled = holding
		if holding then
			render()
		end
	end)
	-- Während Tab gehalten wird, laufend aktualisieren
	task.spawn(function()
		while true do
			if holding then
				render()
			end
			task.wait(0.5)
		end
	end)
end

return Scoreboard

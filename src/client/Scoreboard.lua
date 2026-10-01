-- Scoreboard (ModuleScript, nur Client)
-- Tab gedrückt halten: alle Spieler und Bots im eigenen Modus mit Agent, Kills, Toden und Schaden.
-- In Drop nach Teams getrennt, in Free-for-All nach Kills sortiert.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local Modes = require(Shared.Modes)

local player = Players.LocalPlayer

local Scoreboard = {}

local ACCENT = Color3.fromRGB(255, 140, 40)
local ROW = Color3.fromRGB(22, 26, 36)
local GRAY = Color3.fromRGB(170, 175, 190)
local TEAM_COLORS = { Rot = Color3.fromRGB(220, 70, 70), Blau = Color3.fromRGB(70, 130, 230) }

-- Spalten: { Überschrift, Breite, Ausrichtung }
local COLUMNS = {
	{ "SPIELER", 300, Enum.TextXAlignment.Left },
	{ "AGENT", 140, Enum.TextXAlignment.Left },
	{ "K", 70, Enum.TextXAlignment.Center },
	{ "T", 70, Enum.TextXAlignment.Center },
	{ "SCHADEN", 120, Enum.TextXAlignment.Center },
}

local gui, panel, list
local holding = false

local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function rowFrame(order, color)
	local frame = make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = color or ROW,
		BackgroundTransparency = 0.15, BorderSizePixel = 0, LayoutOrder = order }, list)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12) }, frame)
	return frame
end

local function cells(frame, values, color, font)
	for i, column in COLUMNS do
		make("TextLabel", { Size = UDim2.new(0, column[2], 1, 0), BackgroundTransparency = 1, Text = tostring(values[i]),
			Font = font or Enum.Font.GothamBold, TextSize = 16, TextColor3 = color or Color3.new(1, 1, 1),
			TextXAlignment = column[3], LayoutOrder = i }, frame)
	end
end

-- Alle Einträge im eigenen Modus: { Name, Agent, Kills, Deaths, Damage, Team, IsMe }
local function entries()
	local mode = player:GetAttribute("Mode")
	local list = {}
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("Mode") == mode then
			local stats = p:FindFirstChild("leaderstats")
			local kills = stats and stats:FindFirstChild("Kills")
			local agentId = (p.Character and p.Character:GetAttribute("Agent")) or p:GetAttribute("Agent")
			local agent = AgentConfig.Get(agentId)
			table.insert(list, { Name = p.Name, Agent = agent and agent.Name or "–", Kills = kills and kills.Value or 0,
				Deaths = p:GetAttribute("Deaths") or 0, Damage = p:GetAttribute("Damage") or 0,
				Team = p.Team and p.Team.Name or nil, IsMe = p == player })
		end
	end
	for _, info in ReplicatedStorage:WaitForChild("BotInfo"):GetChildren() do
		if info:GetAttribute("Mode") == mode then
			local agent = AgentConfig.Get(info:GetAttribute("Agent"))
			local team = info:GetAttribute("TeamName")
			table.insert(list, { Name = info.Name, Agent = agent and agent.Name or "–", Kills = info:GetAttribute("Kills") or 0,
				Deaths = info:GetAttribute("Deaths") or 0, Damage = "–", Team = team ~= "" and team or nil })
		end
	end
	table.sort(list, function(a, b)
		if a.Kills ~= b.Kills then
			return a.Kills > b.Kills
		end
		return a.Name < b.Name
	end)
	return list
end

local function render()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local order = 0
	local function add(entry)
		order += 1
		local frame = rowFrame(order, entry.IsMe and Color3.fromRGB(70, 55, 25) or nil)
		cells(frame, { entry.Name, entry.Agent, entry.Kills, entry.Deaths, entry.Damage },
			entry.IsMe and ACCENT or nil)
	end

	order += 1
	cells(rowFrame(order, Color3.fromRGB(10, 12, 18)), {
		COLUMNS[1][1], COLUMNS[2][1], COLUMNS[3][1], COLUMNS[4][1], COLUMNS[5][1] }, GRAY, Enum.Font.GothamBlack)

	local all = entries()
	if player:GetAttribute("Mode") == "Drop" then
		-- Eigenes Team zuerst
		local mine = player.Team and player.Team.Name or "Rot"
		for _, teamName in { mine, mine == "Rot" and "Blau" or "Rot" } do
			order += 1
			local header = rowFrame(order, TEAM_COLORS[teamName])
			cells(header, { "TEAM " .. string.upper(teamName), "", "", "", "" }, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
			for _, entry in all do
				if entry.Team == teamName then
					add(entry)
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
	panel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.new(0, 740, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(12, 14, 20),
		BackgroundTransparency = 0.1, BorderSizePixel = 0 }, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
	make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12) }, panel)
	list = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1 }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Tab and Modes.IsFighting(player) then
			holding = true
			gui.Enabled = true
			render()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab then
			holding = false
			gui.Enabled = false
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

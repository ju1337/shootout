-- AdminPanel (ModuleScript, nur Client)
-- Nur für Admins (Attribut "IsAdmin" vom Server). Öffnen/Schließen mit P oder dem ADMIN-Knopf.
-- Alle Befehle prüft der Server noch einmal (AdminService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local GameSettings = require(Shared.GameSettings)
local AgentConfig = require(Shared.AgentConfig)

local player = Players.LocalPlayer

local AdminPanel = {}

local ACCENT = Color3.fromRGB(40, 210, 230)
local PANEL = Color3.fromRGB(13, 22, 36)
local ROW = Color3.fromRGB(18, 30, 48)
local BUTTON = Color3.fromRGB(30, 50, 74)
local DANGER = Color3.fromRGB(190, 50, 60)
local GRAY = Color3.fromRGB(130, 155, 175)

local gui, panel, list, statusLabel, playerSection, toggleButton
local valueLabels = {} -- [Key] = Label
local botCountLabel
local isOpen = false
local playerSignature = ""

local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function label(textValue, size, parent, props)
	props = props or {}
	props.Text = textValue
	props.Size = props.Size or UDim2.new(1, 0, 0, size + 8)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextSize = size
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props, parent)
end

local function button(textValue, width, parent, color, onClick)
	local b = make("TextButton", {
		Size = UDim2.new(0, width, 0, 30),
		BackgroundColor3 = color or BUTTON,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		Text = textValue,
		AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
	b.Activated:Connect(onClick)
	return b
end

-- Zeile mit Knöpfen nebeneinander
local function row(parent, height)
	local frame = make("Frame", { Size = UDim2.new(1, 0, 0, height or 30), BackgroundTransparency = 1 }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	return frame
end

local function send(action, a, b)
	statusLabel.Text = "..."
	Remotes.AdminAction:FireServer(action, a, b)
end

local function section(title)
	label(title, 18, list, { TextColor3 = ACCENT, Font = Enum.Font.Oswald })
end

local function buildControls()
	section("SPIEL STEUERN")
	for _, modeId in { "Domination", "Wingman", "Arena" } do
		local modeRow = row(list)
		label(modeId .. ":", 15, modeRow, { Size = UDim2.new(0, 80, 1, 0) })
		button("JETZT STARTEN", 130, modeRow, Color3.fromRGB(60, 150, 80), function()
			send("ModeStart", modeId)
		end)
		button("Runde beenden", 120, modeRow, nil, function()
			send("ModeEndRound", modeId)
		end)
		button("Reset", 70, modeRow, DANGER, function()
			send("ModeResetMatch", modeId)
		end)
	end
	local ffaRow = row(list)
	label("FFA:", 15, ffaRow, { Size = UDim2.new(0, 60, 1, 0) })
	button("Runde beenden", 120, ffaRow, nil, function()
		send("FFAEndRound")
	end)
	local noclipRow = row(list)
	label("Ich:", 15, noclipRow, { Size = UDim2.new(0, 60, 1, 0) })
	button("NOCLIP (B)", 130, noclipRow, Color3.fromRGB(60, 120, 170), function()
		send("Noclip")
	end)
	button("TAG / NACHT", 130, noclipRow, Color3.fromRGB(150, 120, 50), function()
		send("DayNight")
	end)
	button("BLUTMOND", 120, noclipRow, Color3.fromRGB(150, 40, 36), function()
		send("BloodMoon")
	end)
end

local function buildBots()
	section("BOTS")
	local ffaRow = row(list)
	label("FFA:", 15, ffaRow, { Size = UDim2.new(0, 60, 1, 0) })
	button("+1 Bot", 80, ffaRow, nil, function()
		send("SpawnBot", "FreeForAll")
	end)
	button("+5 Bots", 80, ffaRow, nil, function()
		for _ = 1, 5 do
			send("SpawnBot", "FreeForAll")
		end
	end)
	-- { Modus, Team A, Farbe A, Team B, Farbe B, Plätze }
	for _, entry in {
		{ "Domination", "Rot", Color3.fromRGB(150, 50, 50), "Blau", Color3.fromRGB(50, 80, 160), 10 },
		{ "Wingman", "Alpha", Color3.fromRGB(60, 150, 100), "Bravo", Color3.fromRGB(150, 130, 40), 4 },
		{ "Arena", "Links", Color3.fromRGB(120, 70, 170), "Rechts", Color3.fromRGB(70, 120, 170), 2 },
	} do
		local modeRow = row(list)
		label(entry[1] .. ":", 15, modeRow, { Size = UDim2.new(0, 80, 1, 0) })
		button("+1 " .. entry[2], 75, modeRow, entry[3], function()
			send("SpawnBot", entry[1], entry[2])
		end)
		button("+1 " .. entry[4], 75, modeRow, entry[5], function()
			send("SpawnBot", entry[1], entry[4])
		end)
		button("Auffüllen", 100, modeRow, nil, function()
			for _ = 1, entry[6] do
				send("SpawnBot", entry[1])
			end
		end)
	end
	-- Offene Welt: Bots spawnen beim Admin (draußen; in der Safe Zone vor ihrem Rand), sonst in der roten Zone
	local extRow = row(list)
	label("Extinction:", 15, extRow, { Size = UDim2.new(0, 80, 1, 0) })
	button("+1 Bot", 70, extRow, Color3.fromRGB(150, 70, 40), function()
		send("SpawnBot", "Extinction")
	end)
	button("+5 Bots", 76, extRow, Color3.fromRGB(150, 70, 40), function()
		for _ = 1, 5 do
			send("SpawnBot", "Extinction")
		end
	end)
	button("Entfernen", 90, extRow, DANGER, function()
		send("RemoveBots", "Extinction")
	end)
	local removeRow = row(list)
	button("Alle Bots entfernen", 170, removeRow, DANGER, function()
		send("RemoveBots")
	end)
	botCountLabel = label("", 14, removeRow, { Size = UDim2.new(0, 260, 1, 0), Font = Enum.Font.Gotham,
		TextColor3 = GRAY })
end

local function refreshBots()
	local counts = {}
	for _, info in ReplicatedStorage:WaitForChild("BotInfo"):GetChildren() do
		local mode = info:GetAttribute("Mode")
		counts[mode] = (counts[mode] or 0) + 1
	end
	botCountLabel.Text = "FFA " .. (counts.FreeForAll or 0) .. " · Drop " .. (counts.Drop or 0)
		.. " · Strike " .. (counts.Strikeout or 0) .. " · Demo " .. (counts.Demolition or 0)
		.. " · Wing " .. (counts.Wingman or 0) .. " · Ext " .. (counts.Extinction or 0)
end

local function buildSettings()
	section("EINSTELLUNGEN")
	local lastGroup = nil
	for _, def in GameSettings.List do
		if def.Group ~= lastGroup then
			lastGroup = def.Group
			label(def.Group, 14, list, { TextColor3 = GRAY })
		end
		local r = row(list)
		label(def.Label, 15, r, { Size = UDim2.new(0, 200, 1, 0), Font = Enum.Font.Gotham })
		button("−", 34, r, nil, function()
			send("SetSetting", def.Key, GameSettings.Get(def.Key) - def.Step)
		end)
		valueLabels[def.Key] = label("", 16, r, { Size = UDim2.new(0, 60, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Center })
		button("+", 34, r, nil, function()
			send("SetSetting", def.Key, GameSettings.Get(def.Key) + def.Step)
		end)
	end
end

local function refreshSettings()
	for key, valueLabel in valueLabels do
		valueLabel.Text = tostring(GameSettings.Get(key))
	end
end

-- Spielerliste neu bauen (nur wenn sich etwas geändert hat)
local function refreshPlayers()
	local parts = {}
	for _, p in Players:GetPlayers() do
		table.insert(parts, p.UserId .. ":" .. tostring(p:GetAttribute("Mode")) .. ":" .. tostring(p.Team)
			.. ":" .. tostring(p:GetAttribute("Agent")))
	end
	local signature = table.concat(parts, "|")
	if signature == playerSignature then
		return
	end
	playerSignature = signature

	for _, child in playerSection:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, p in Players:GetPlayers() do
		local box = make("Frame", { Size = UDim2.new(1, 0, 0, 168), BackgroundColor3 = ROW, BorderSizePixel = 0,
			LayoutOrder = i }, playerSection)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6) }, box)
		make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, box)
		local agent = AgentConfig.Get(p:GetAttribute("Agent"))
		label(p.Name .. "  ·  " .. tostring(p:GetAttribute("Mode")) .. (p.Team and ("  ·  " .. p.Team.Name) or "")
			.. "  ·  " .. (agent and agent.Name or "?"), 15, box)
		local moves = row(box)
		local short = { Hub = "Hub", Market = "Markt", FreeForAll = "FFA", Domination = "Herr.", Wingman = "Wing",
			Arena = "1v1", Training = "Train" }
		for _, modeId in { "Hub", "Market", "FreeForAll", "Domination", "Wingman", "Arena", "Training" } do
			button(short[modeId], 46, moves, nil, function()
				send("MovePlayer", p.UserId, modeId)
			end)
		end
		button("Team", 60, moves, nil, function()
			send("SwitchTeam", p.UserId)
		end)
		local actions = row(box)
		button("Heilen", 56, actions, Color3.fromRGB(60, 150, 80), function()
			send("Heal", p.UserId)
		end)
		button("Töten", 52, actions, DANGER, function()
			send("Kill", p.UserId)
		end)
		button("+500 XP", 66, actions, nil, function()
			send("GiveXP", p.UserId, 500)
		end)
		button("+5000 XP", 76, actions, nil, function()
			send("GiveXP", p.UserId, 5000)
		end)
		button("+1000 💰", 80, actions, Color3.fromRGB(150, 120, 30), function()
			send("GiveCoins", p.UserId, 1000)
		end)
		button("+5 Stufen", 80, actions, Color3.fromRGB(40, 140, 120), function()
			send("GivePassXP", p.UserId, 5000)
		end)
		local prestige = row(box)
		button("Max Prestige", 100, prestige, Color3.fromRGB(170, 120, 30), function()
			send("SetPrestige", p.UserId, "max")
		end)
		button("Prestige +1", 90, prestige, Color3.fromRGB(110, 80, 170), function()
			send("SetPrestige", p.UserId, "next")
		end)
		button("Level 100", 80, prestige, nil, function()
			send("SetPrestige", p.UserId, "level100")
		end)
		button("Prestige 0", 84, prestige, DANGER, function()
			send("SetPrestige", p.UserId, 0)
		end)
		local elo = row(box)
		button("Max ELO", 74, elo, Color3.fromRGB(170, 120, 30), function()
			send("SetElo", p.UserId, "max")
		end)
		button("+100", 52, elo, nil, function()
			send("SetElo", p.UserId, 100)
		end)
		button("+1", 40, elo, nil, function()
			send("SetElo", p.UserId, 1)
		end)
		button("−1", 40, elo, nil, function()
			send("SetElo", p.UserId, -1)
		end)
		button("−100", 52, elo, nil, function()
			send("SetElo", p.UserId, -100)
		end)
		button("ELO zurück", 84, elo, DANGER, function()
			send("SetElo", p.UserId, "reset")
		end)
		local season = row(box)
		button("Saisonende testen", 140, season, Color3.fromRGB(110, 80, 170), function()
			send("SetElo", p.UserId, "season")
		end)
		button("+10.000 RAP", 100, season, Color3.fromRGB(40, 150, 115), function()
			send("GiveRap", p.UserId, 10000)
		end)
		button("Handelbarer Skin", 130, season, Color3.fromRGB(40, 150, 115), function()
			send("GiveTradeSkin", p.UserId)
		end)
	end
end

local function setOpen(open)
	isOpen = open
	panel.Visible = open
	if open then
		playerSignature = ""
		refreshSettings()
		refreshPlayers()
		RunService:BindToRenderStep("AdminMouse", Enum.RenderPriority.Camera.Value + 2, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	else
		RunService:UnbindFromRenderStep("AdminMouse")
	end
end

local function build()
	gui = make("ScreenGui", { Name = "AdminPanel", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20 },
		player:WaitForChild("PlayerGui"))

	toggleButton = button("ADMIN (P)", 110, gui, ACCENT, function()
		setOpen(not isOpen)
	end)
	toggleButton.Position = UDim2.new(0, 150, 0, 6)
	toggleButton.TextColor3 = Color3.fromRGB(20, 20, 20)

	panel = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.new(0, 460, 0.85, 0), BackgroundColor3 = PANEL, BackgroundTransparency = 0.05,
		BorderSizePixel = 0, Visible = false, Active = true }, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
	make("UIStroke", { Color = Color3.fromRGB(40, 70, 95), Thickness = 1.5 }, panel)
	make("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, panel)

	label("ADMIN-PANEL", 24, panel, { Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 30),
		Font = Enum.Font.Oswald, TextColor3 = ACCENT })
	statusLabel = label("", 14, panel, { Position = UDim2.new(0, 16, 0, 42), Size = UDim2.new(1, -32, 0, 20),
		Font = Enum.Font.Gotham, TextColor3 = GRAY })

	list = make("ScrollingFrame", { Position = UDim2.new(0, 16, 0, 68), Size = UDim2.new(1, -24, 1, -80),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	buildControls()
	buildBots()
	buildSettings()
	section("SPIELER")
	playerSection = make("Frame", { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1 }, list)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, playerSection)

	-- Reihenfolge = Erstellungsreihenfolge
	for i, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child.LayoutOrder = i
		end
	end
end

function AdminPanel.Init()
	if not player:GetAttribute("IsAdmin") then
		player:GetAttributeChangedSignal("IsAdmin"):Wait()
	end
	if not player:GetAttribute("IsAdmin") then
		return
	end
	build()

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.P then
			setOpen(not isOpen)
		end
	end)
	Remotes.AdminStatus.OnClientEvent:Connect(function(message)
		statusLabel.Text = message
	end)
	ReplicatedStorage.AttributeChanged:Connect(function()
		if isOpen then
			refreshSettings()
		end
	end)
	task.spawn(function()
		while true do
			if isOpen then
				refreshPlayers()
				refreshBots()
			end
			task.wait(1)
		end
	end)
end

return AdminPanel

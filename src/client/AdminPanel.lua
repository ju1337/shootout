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

local ACCENT = Color3.fromRGB(255, 140, 40)
local PANEL = Color3.fromRGB(16, 18, 26)
local ROW = Color3.fromRGB(28, 31, 42)
local BUTTON = Color3.fromRGB(48, 52, 68)
local DANGER = Color3.fromRGB(170, 60, 60)
local GRAY = Color3.fromRGB(170, 175, 190)

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
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
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
	label(title, 18, list, { TextColor3 = ACCENT, Font = Enum.Font.GothamBlack })
end

local function buildControls()
	section("SPIEL STEUERN")
	local dropRow = row(list)
	label("Drop:", 15, dropRow, { Size = UDim2.new(0, 60, 1, 0) })
	button("JETZT STARTEN", 130, dropRow, Color3.fromRGB(60, 150, 80), function()
		send("DropStart")
	end)
	button("Runde beenden", 120, dropRow, nil, function()
		send("DropEndRound")
	end)
	button("Reset", 70, dropRow, DANGER, function()
		send("DropResetMatch")
	end)
	local ffaRow = row(list)
	label("FFA:", 15, ffaRow, { Size = UDim2.new(0, 60, 1, 0) })
	button("Runde beenden", 120, ffaRow, nil, function()
		send("FFAEndRound")
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
	local dropRow = row(list)
	label("Drop:", 15, dropRow, { Size = UDim2.new(0, 60, 1, 0) })
	button("+1 Rot", 75, dropRow, Color3.fromRGB(150, 50, 50), function()
		send("SpawnBot", "Drop", "Rot")
	end)
	button("+1 Blau", 75, dropRow, Color3.fromRGB(50, 80, 160), function()
		send("SpawnBot", "Drop", "Blau")
	end)
	button("Auf 5v5 auffüllen", 140, dropRow, nil, function()
		for _ = 1, 10 do
			send("SpawnBot", "Drop")
		end
	end)
	local removeRow = row(list)
	button("Alle Bots entfernen", 170, removeRow, DANGER, function()
		send("RemoveBots")
	end)
	botCountLabel = label("", 14, removeRow, { Size = UDim2.new(0, 200, 1, 0), Font = Enum.Font.Gotham,
		TextColor3 = GRAY })
end

local function refreshBots()
	local counts = {}
	for _, info in ReplicatedStorage:WaitForChild("BotInfo"):GetChildren() do
		local mode = info:GetAttribute("Mode")
		counts[mode] = (counts[mode] or 0) + 1
	end
	botCountLabel.Text = "FFA: " .. (counts.FreeForAll or 0) .. "   Drop: " .. (counts.Drop or 0)
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
		local box = make("Frame", { Size = UDim2.new(1, 0, 0, 100), BackgroundColor3 = ROW, BorderSizePixel = 0,
			LayoutOrder = i }, playerSection)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6) }, box)
		make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, box)
		local agent = AgentConfig.Get(p:GetAttribute("Agent"))
		label(p.Name .. "  ·  " .. tostring(p:GetAttribute("Mode")) .. (p.Team and ("  ·  " .. p.Team.Name) or "")
			.. "  ·  " .. (agent and agent.Name or "?"), 15, box)
		local moves = row(box)
		for _, modeId in { "Hub", "FreeForAll", "Drop" } do
			button(modeId, 90, moves, nil, function()
				send("MovePlayer", p.UserId, modeId)
			end)
		end
		button("Team", 60, moves, nil, function()
			send("SwitchTeam", p.UserId)
		end)
		local actions = row(box)
		button("Heilen", 70, actions, Color3.fromRGB(60, 150, 80), function()
			send("Heal", p.UserId)
		end)
		button("Töten", 70, actions, DANGER, function()
			send("Kill", p.UserId)
		end)
		button("+500 XP", 80, actions, nil, function()
			send("GiveXP", p.UserId, 500)
		end)
		button("+5000 XP", 90, actions, nil, function()
			send("GiveXP", p.UserId, 5000)
		end)
		button("+1000 💰", 90, actions, Color3.fromRGB(150, 120, 30), function()
			send("GiveCoins", p.UserId, 1000)
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
	make("UIStroke", { Color = ACCENT, Thickness = 2 }, panel)

	label("ADMIN-PANEL", 24, panel, { Position = UDim2.new(0, 16, 0, 10), Size = UDim2.new(1, -32, 0, 30),
		Font = Enum.Font.GothamBlack, TextColor3 = ACCENT })
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

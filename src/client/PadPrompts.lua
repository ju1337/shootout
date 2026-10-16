-- PadPrompts (ModuleScript, nur Client)
-- Controller-Leiste unten in der Mitte, wie auf Konsolen üblich: Solange mit dem Controller gespielt wird und ein Menü
-- offen ist (oder ein Knopf ausgewählt ist, z.B. auf dem Todesbildschirm), stehen dort die Tasten mit ihrer Bedeutung:
-- ✕ AUSWÄHLEN, ○ ZURÜCK und was das offene Fenster dazu meldet (L1/R1 REITER im Menü der offenen Welt).
-- Tasten als Bild, wie Roblox sie auf der Konsole zeigt (PlayStation-Symbole oder Xbox-Buchstaben); ohne Bild als Kappe
-- mit der Beschriftung aus InputActions.PadName.
-- Fenster melden sich mit PadPrompts.Provider(function() return { { Keys = { ... }, Text = "..." }, ... } end) an;
-- { Hide = true } blendet die Leiste aus (z.B. Weltkarte mit eigener Zeile).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)

local C = UITheme.Colors
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label

local PadPrompts = {}

local BAR_H = 36
local GLYPH = 26
local providers = {}
local gui, bar
local lastKey = nil

function PadPrompts.Provider(fn)
	table.insert(providers, fn)
end

-- Einträge, die gerade gelten (leere Liste = Leiste aus)
function PadPrompts.Entries()
	if InputActions.Device() ~= "Gamepad" then
		return {}
	end
	local menu = UITheme.IsMenuOpen()
	local selected = GuiService.SelectedObject
	if not menu and not selected then
		return {}
	end
	local entries = {}
	if selected then
		table.insert(entries, { Keys = { Enum.KeyCode.ButtonA }, Text = "AUSWÄHLEN" })
	end
	if menu then
		table.insert(entries, { Keys = { Enum.KeyCode.ButtonB }, Text = "ZURÜCK" })
	end
	for _, fn in providers do
		local ok, extra = pcall(fn)
		if ok and type(extra) == "table" then
			if extra.Hide then
				return {}
			end
			for _, entry in extra do
				table.insert(entries, entry)
			end
		end
	end
	return entries
end

local function glyph(parent, keyCode, order)
	local image = InputActions.PadImage(keyCode)
	if image then
		make("ImageLabel", { Name = "Glyph", Size = UDim2.fromOffset(GLYPH, GLYPH), BackgroundTransparency = 1, Image = image,
			LayoutOrder = order }, parent)
		return
	end
	local name = InputActions.PadName(keyCode)
	local cap = make("Frame", { Name = "Glyph", Size = UDim2.fromOffset(math.max(GLYPH, 9 * #name + 10), GLYPH),
		BackgroundColor3 = C.Card, BorderSizePixel = 0, LayoutOrder = order }, parent)
	UITheme.Corner(cap, UITheme.Radius.Small)
	UITheme.Stroke(cap, C.Border, 1)
	label({ Size = UDim2.fromScale(1, 1), Text = name, TextSize = 14, Font = F.Display, TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Center }, cap)
end

local function render(entries)
	for _, child in bar:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for index, entry in entries do
		local item = make("Frame", { Name = "Prompt" .. index, Size = UDim2.fromOffset(0, BAR_H), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1, LayoutOrder = index }, bar)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, item)
		for k, keyCode in entry.Keys do
			glyph(item, keyCode, k)
		end
		label({ Name = "Text", Size = UDim2.fromOffset(0, BAR_H), AutomaticSize = Enum.AutomaticSize.X, Text = entry.Text,
			TextSize = 16, Font = F.Bold, TextColor3 = C.Text, LayoutOrder = #entry.Keys + 1 }, item)
	end
end

local function signature(entries)
	local parts = { InputActions.PadStyle() }
	for _, entry in entries do
		local keys = {}
		for _, keyCode in entry.Keys do
			table.insert(keys, keyCode.Name)
		end
		table.insert(parts, table.concat(keys, "+") .. "=" .. entry.Text)
	end
	return table.concat(parts, "|")
end

function PadPrompts.Refresh()
	if not bar then
		return
	end
	local entries = PadPrompts.Entries()
	gui.Enabled = #entries > 0
	local key = signature(entries)
	if key ~= lastKey then
		lastKey = key
		render(entries)
	end
end

function PadPrompts.Init()
	local player = Players.LocalPlayer
	gui = make("ScreenGui", { Name = "PadPrompts", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 150,
		Enabled = false }, player:WaitForChild("PlayerGui"))
	local root = UITheme.ScaledRoot(gui)
	bar = make("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.fromOffset(0, BAR_H), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.15, BorderSizePixel = 0, Active = false }, root)
	UITheme.Corner(bar, UITheme.Radius.Medium)
	UITheme.Stroke(bar, C.Border, 1)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, bar)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now >= nextCheck then
			nextCheck = now + 0.15
			PadPrompts.Refresh()
		end
	end)
	InputActions.DeviceChanged:Connect(PadPrompts.Refresh)
end

return PadPrompts

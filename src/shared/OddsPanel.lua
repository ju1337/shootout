-- OddsPanel (ModuleScript, nur Client)
-- Fenster CHANCEN: alle möglichen Ergebnisse eines Zufallsitems mit ihrer Chance in Prozent (PaidRandom). Roblox
-- verlangt das vor jedem Kauf bzw. Dreh, der direkt oder indirekt Robux kostet (Glücksrad, Waffen-Kiste).
-- OddsPanel.Show(Titel, Zeilen) mit Zeilen { { Text, Chance (0..1), Color } }; WheelRows() liefert die des Glücksrads.
-- Esc, ○ oder SCHLIESSEN macht es zu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.UITheme)
local LoginConfig = require(Shared.LoginConfig)
local Cosmetics = require(Shared.Cosmetics)
local PaidRandom = require(Shared.PaidRandom)
local InputActions = require(Shared.InputActions)

local C = UITheme.Colors
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label
local format = UITheme.FormatNumber

local OddsPanel = {}

local WIDTH, ROW_H = 560, 36

local gui, root, frame = nil, nil, nil

-- Zeilen fürs Glücksrad: was man im Feld bekommt, in der Reihenfolge der Felder
function OddsPanel.WheelRows()
	local odds = LoginConfig.WheelOdds()
	local rows = {}
	for index, field in LoginConfig.Wheel do
		local item = field.Item and Cosmetics.Get(field.Item)
		local text
		if item then
			text = "Skin " .. item.Name
		elseif field.BoostMinutes then
			text = field.BoostMinutes .. " Min. Doppel-XP"
		elseif field.Text == "JACKPOT" then
			text = "JACKPOT: " .. format(field.Coins or 0) .. " Münzen"
		else
			text = format(field.Coins or 0) .. " Münzen"
		end
		table.insert(rows, { Text = text, Chance = odds[index], Color = field.Color })
	end
	return rows
end

function OddsPanel.Close()
	if frame then
		InputActions.Unfocus(frame)
		frame:Destroy()
		frame = nil
	end
end

function OddsPanel.IsOpen()
	return frame ~= nil
end

function OddsPanel.Show(title, rows)
	local player = Players.LocalPlayer
	if not gui then
		gui = make("ScreenGui", { Name = "Odds", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
		root = UITheme.ScaledRoot(gui, nil, nil, 0.55)
		UserInputService.InputBegan:Connect(function(input, processed)
			if frame and (input.KeyCode == Enum.KeyCode.ButtonB or (input.KeyCode == Enum.KeyCode.Escape and not processed)) then
				OddsPanel.Close()
			end
		end)
	end
	OddsPanel.Close()
	local listHeight = math.min(#rows, 12) * ROW_H
	local height = 150 + listHeight
	frame = UITheme.Card({ Name = "OddsWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(WIDTH, height), BackgroundTransparency = 0.03, ZIndex = 20 }, root)
	UITheme.AccentBar(frame, C.Primary, { ZIndex = 20 })
	label({ Position = UDim2.fromOffset(24, 14), Size = UDim2.new(1, -48, 0, 32), Text = "CHANCEN", TextSize = 28, Font = F.Display,
		ZIndex = 20 }, frame)
	label({ Position = UDim2.fromOffset(24, 46), Size = UDim2.new(1, -48, 0, 18), Text = UITheme.Upper(title), TextSize = 12, Font = F.Bold,
		TextColor3 = C.Primary, ZIndex = 20 }, frame)
	local list = make("ScrollingFrame", { Name = "Rows", Position = UDim2.fromOffset(24, 74), Size = UDim2.new(1, -48, 0, listHeight),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Border, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 20 }, frame)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for index, row in rows do
		local line = make("Frame", { Name = "Row" .. index, LayoutOrder = index, Size = UDim2.new(1, -8, 0, ROW_H),
			BackgroundColor3 = C.Card, BackgroundTransparency = index % 2 == 0 and 0.4 or 1, BorderSizePixel = 0, ZIndex = 20 }, list)
		make("Frame", { Position = UDim2.fromOffset(10, ROW_H / 2 - 6), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = row.Color or C.Border,
			BorderSizePixel = 0, ZIndex = 20 }, line)
		label({ Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -150, 1, 0), Text = row.Text, TextSize = 16, Font = F.Bold,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 20 }, line)
		label({ Name = "Chance", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(110, ROW_H),
			Text = PaidRandom.Percent(row.Chance), TextSize = 18, Font = F.Display, TextColor3 = C.Primary,
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 20 }, line)
	end
	label({ Position = UDim2.fromOffset(24, 82 + listHeight), Size = UDim2.new(1, -48, 0, 16), Text = PaidRandom.Note, TextSize = 11,
		Font = F.Medium, TextColor3 = C.Muted, ZIndex = 20 }, frame)
	local close = UITheme.Chunky({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(220, 40),
		Color = C.Card, StrokeColor = C.Border, Text = "SCHLIESSEN", TextSize = 16, ZIndex = 20 }, frame, OddsPanel.Close)
	InputActions.Focus(frame, close.Button)
	return frame
end

return OddsPanel

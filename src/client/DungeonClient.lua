-- DungeonClient (ModuleScript, nur Client)
-- Anzeige oben in der Mitte, solange man in einem Dungeon ist (Spieler-Attribut "Dungeon", DungeonService): Name und
-- Welle, darunter was gerade los ist (Countdown bis Welle 1, Zombies übrig, Portal offen mit Zeit bis zur nächsten Welle)
-- und die gesammelte Beute, die man beim Verlassen durchs Portal bekommt. Reiht sich per TopStack unter den anderen
-- Anzeigen oben ein.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.UITheme)
local setText = require(Shared.Locale).Set -- nur umschreiben, wenn sich der Text ändert (läuft jeden Frame)
local TopStack = require(Shared.TopStack)

local player = Players.LocalPlayer

local DungeonClient = {}

local PURPLE = Color3.fromRGB(190, 120, 255)
local GREEN = Color3.fromRGB(110, 230, 140)
local RED = Color3.fromRGB(235, 80, 70)
local WIDTH, HEIGHT = 360, 74

local gui, panel, titleLabel, stateLabel, lootLabel, stroke
local state = nil -- letzter Stand aus dem Attribut (Tabelle) oder nil

-- Texte für einen Stand (auch für Tests): gibt Titel, Zeile, Farbe der Zeile und Beute-Zeile zurück
function DungeonClient.Lines(info, now)
	local left = math.max(0, math.ceil((tonumber(info.E) or now) - now))
	local title = string.format("DUNGEON · %s", tostring(info.T or ""))
	if (tonumber(info.W) or 0) > 0 then
		title = string.format("DUNGEON · %s · WELLE %d", tostring(info.T or ""), tonumber(info.W) or 0)
	end
	local line, color
	if info.S == "Start" then
		line, color = string.format("WELLE 1 IN %d S", left), PURPLE
	elseif info.S == "Break" then
		line, color = string.format("PORTAL OFFEN · NÄCHSTE WELLE IN %d S", left), GREEN
	else
		line, color = string.format("%d ZOMBIES ÜBRIG", tonumber(info.L) or 0), RED
	end
	local loot = string.format("BEUTE: %d MÜNZEN · %d ITEMS", tonumber(info.C) or 0, tonumber(info.I) or 0)
	return title, line, color, loot
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Dungeon"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 8
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = UITheme.ScaledRoot(gui)
	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 66)
	panel.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	panel.BackgroundColor3 = UITheme.Colors.Panel
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.Parent = root
	UITheme.Corner(panel, UITheme.Radius.Small)
	stroke = UITheme.Stroke(panel, PURPLE, 1, 0.3)
	titleLabel = UITheme.Label({ Name = "Title", Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 22), TextSize = 18,
		Font = UITheme.Fonts.Display, TextColor3 = PURPLE, TextXAlignment = Enum.TextXAlignment.Center }, panel)
	stateLabel = UITheme.Label({ Name = "State", Position = UDim2.fromOffset(0, 29), Size = UDim2.new(1, 0, 0, 20), TextSize = 16,
		Font = UITheme.Fonts.Display, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center }, panel)
	lootLabel = UITheme.Label({ Name = "Loot", Position = UDim2.fromOffset(0, 51), Size = UDim2.new(1, 0, 0, 16), TextSize = 13,
		Font = UITheme.Fonts.Bold, TextColor3 = UITheme.Colors.Gold, TextXAlignment = Enum.TextXAlignment.Center }, panel)
	TopStack.Register(panel, { Order = TopStack.Order.Status + 5, Height = function()
		return HEIGHT
	end })
end

local function readState()
	local raw = player:GetAttribute("Dungeon")
	if type(raw) ~= "string" or raw == "" then
		state = nil
		return
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	state = ok and type(decoded) == "table" and decoded or nil
end

local function update()
	gui.Enabled = state ~= nil
	if not state then
		return
	end
	local title, line, color, loot = DungeonClient.Lines(state, workspace:GetServerTimeNow())
	setText(titleLabel, title)
	setText(stateLabel, line)
	stateLabel.TextColor3 = color
	if stroke then
		stroke.Color = color
	end
	setText(lootLabel, loot)
end

function DungeonClient.Init()
	build()
	readState()
	player:GetAttributeChangedSignal("Dungeon"):Connect(readState)
	local last = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last < 0.2 then
			return
		end
		last = now
		local ok, err = pcall(update)
		if not ok then
			warn("DungeonClient: " .. tostring(err))
		end
	end)
end

return DungeonClient

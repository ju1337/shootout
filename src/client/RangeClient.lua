-- RangeClient (ModuleScript, nur Client)
-- Anzeige am Schießstand (RangeService, Remotes.RangeUpdate): während der Runde oben in der Mitte Punkte und Restzeit,
-- bei jedem Treffer kurz "+10" bzw. "+25 MITTE"; am Ende Ergebnis, Bestwert und Tagesbelohnung.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)
local WorkshopConfig = require(Shared.WorkshopConfig)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label

local RangeClient = {}

local ORANGE = Color3.fromRGB(240, 124, 44)
local ui: any = {}
local state = { Ends = 0, Active = false, HideAt = 0, PopAt = 0 }

local function build()
	local gui = make("ScreenGui", { Name = "Range", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9, Enabled = false },
		player:WaitForChild("PlayerGui"))
	ui.Gui = gui
	local root = UITheme.ScaledRoot(gui)
	local panel = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(340, 92), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.15, BorderSizePixel = 0 }, root)
	UITheme.Corner(panel, 6)
	UITheme.Stroke(panel, ORANGE, 1, 0.3)
	ui.Title = label({ Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -32, 0, 16), Text = "SCHIESSSTAND", TextSize = 13,
		TextColor3 = ORANGE }, panel)
	ui.Score = label({ Name = "Score", Position = UDim2.fromOffset(16, 26), Size = UDim2.new(0.6, -16, 0, 40), Text = "0", TextSize = 38,
		Font = F.Display }, panel)
	ui.Time = label({ Name = "Time", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 26), Size = UDim2.new(0.4, 0, 0, 40),
		Text = "", TextSize = 30, Font = F.Display, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, panel)
	ui.Line = label({ Name = "Line", Position = UDim2.fromOffset(16, 68), Size = UDim2.new(1, -32, 0, 16), Text = "", TextSize = 12,
		TextColor3 = C.Muted }, panel)
	ui.Pop = label({ Name = "Pop", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 170), Size = UDim2.fromOffset(300, 40),
		Text = "", TextSize = 34, Font = F.Display, TextColor3 = ORANGE, TextXAlignment = Enum.TextXAlignment.Center }, root)
end

function RangeClient.Init()
	build()
	Remotes.RangeUpdate.OnClientEvent:Connect(function(kind, data)
		data = data or {}
		if kind == "Start" then
			state.Active, state.Ends, state.HideAt = true, data.Ends or 0, 0
			ui.Title.Text = "SCHIESSSTAND"
			ui.Score.Text = "0"
			ui.Line.Text = "TRIFF DIE ZIELE  ·  MITTE ZÄHLT " .. WorkshopConfig.Range.Bullseye
			ui.Gui.Enabled = true
		elseif kind == "Hit" then
			ui.Score.Text = tostring(data.Score or 0)
			ui.Pop.Text = (data.Gain or 0) >= WorkshopConfig.Range.Bullseye and ("+" .. data.Gain .. " MITTE") or ("+" .. tostring(data.Gain))
			state.PopAt = os.clock()
		elseif kind == "End" then
			state.Active = false
			state.HideAt = os.clock() + 6
			ui.Title.Text = "RUNDE VORBEI"
			ui.Score.Text = tostring(data.Score or 0)
			ui.Time.Text = ""
			ui.Line.Text = "BESTWERT " .. tostring(data.Best or 0)
				.. ((data.Reward or 0) > 0 and ("  ·  +" .. data.Reward .. " MÜNZEN (TAGESBELOHNUNG)") or "")
			ui.Gui.Enabled = true
		elseif kind == "Busy" then
			ui.Title.Text = "SCHIESSSTAND BESETZT"
			ui.Score.Text = ""
			ui.Time.Text = ""
			ui.Line.Text = tostring(data.Name or "") .. " SCHIESST GERADE"
			state.HideAt = os.clock() + 3
			ui.Gui.Enabled = true
		end
	end)
	RunService.Heartbeat:Connect(function()
		if not ui.Gui.Enabled then
			return
		end
		if state.Active then
			ui.Time.Text = math.max(0, math.ceil(state.Ends - workspace:GetServerTimeNow())) .. " S"
		elseif state.HideAt > 0 and os.clock() >= state.HideAt then
			ui.Gui.Enabled = false
			state.HideAt = 0
		end
		ui.Pop.TextTransparency = math.clamp((os.clock() - state.PopAt) / 0.8, 0, 1)
	end)
end

return RangeClient

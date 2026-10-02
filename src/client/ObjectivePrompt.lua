-- ObjectivePrompt (ModuleScript, nur Client)
-- Hinweis und Fortschrittsbalken für Ziele (z.B. "[E] halten: Bombe bei A legen").
-- Der Server setzt die Spieler-Attribute ObjHint und ActionProgress; E halten schickt
-- ObjectiveAction. Wiederbeleben (Downed) hat Vorrang, wenn beides möglich ist.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local InputActions = require(ReplicatedStorage:WaitForChild("Shared").InputActions)
local Downed = require(script.Parent:WaitForChild("Downed"))

local player = Players.LocalPlayer

local ObjectivePrompt = {}

local holding = false

local function setHolding(value)
	if value ~= holding then
		holding = value
		Remotes.ObjectiveAction:FireServer(value)
	end
end

function ObjectivePrompt.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ObjectivePrompt"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0.66, 0)
	panel.Size = UDim2.new(0, 460, 0, 56)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 28)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Oswald
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(255, 120, 120)
	label.TextStrokeTransparency = 0.4
	label.Parent = panel

	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0, 34)
	back.Size = UDim2.new(0, 300, 0, 10)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	back.BorderSizePixel = 0
	back.Parent = panel
	Instance.new("UICorner").Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 90, 90)
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner").Parent = fill

	InputActions.Bind("Interact", function(began)
		if began and player:GetAttribute("ObjHint") and not Downed.HasPrompt() then
			setHolding(true)
		elseif not began then
			setHolding(false)
		end
	end)

	RunService.Heartbeat:Connect(function()
		local hint = player:GetAttribute("ObjHint")
		InputActions.SetInteractAvailable("Objective", hint ~= nil)
		local progress = player:GetAttribute("ActionProgress")
		-- Nicht über dem Wiederbeleben-Hinweis anzeigen
		panel.Visible = hint ~= nil and not Downed.HasPrompt()
		if hint then
			-- "[E]" durch die Taste des aktuellen Geräts ersetzen (Touch: eigener Knopf)
			local key = InputActions.Hint("Interact")
			label.Text = string.gsub(hint, "%[E%]", key ~= "" and ("[" .. key .. "]") or "")
			back.Visible = progress ~= nil
			fill.Size = UDim2.new(math.clamp(progress or 0, 0, 1), 0, 1, 0)
		elseif holding then
			setHolding(false)
		end
	end)
end

return ObjectivePrompt

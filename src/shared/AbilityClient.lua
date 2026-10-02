-- AbilityClient (ModuleScript, nur Client)
-- Fähigkeit mit Q auslösen, Anzeige von Agent und Abklingzeit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local C = UITheme.Colors

local player = Players.LocalPlayer

local AbilityClient = {}

function AbilityClient.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Ability"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Nur in Kampfmodi sichtbar
	local function updateVisible()
		gui.Enabled = Modes.IsFighting(player)
	end
	updateVisible()
	player:GetAttributeChangedSignal("Mode"):Connect(updateVisible)

	-- Agentenname über dem Lebensbalken
	local agentLabel = Instance.new("TextLabel")
	agentLabel.Position = UDim2.new(0, 28, 1, -128) -- über dem Lebens-Panel
	agentLabel.Size = UDim2.new(0, 300, 0, 26)
	agentLabel.BackgroundTransparency = 1
	agentLabel.Font = Enum.Font.Oswald
	agentLabel.TextSize = 20
	agentLabel.TextXAlignment = Enum.TextXAlignment.Left
	agentLabel.TextStrokeTransparency = 0.5
	agentLabel.Parent = gui

	-- Fähigkeits-Box unten mittig
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -24)
	box.Size = UDim2.new(0, 240, 0, 62)
	box.BackgroundColor3 = C.Panel
	box.BackgroundTransparency = 0.15
	box.BorderSizePixel = 0
	box.Parent = gui
	UITheme.Corner(box, 3)
	UITheme.Gradient(box, Color3.fromRGB(26, 40, 60), C.Panel)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = box
	-- Ladebalken unten in der Box
	local cooldownBar = Instance.new("Frame")
	cooldownBar.Name = "Bar"
	cooldownBar.AnchorPoint = Vector2.new(0, 1)
	cooldownBar.Position = UDim2.new(0, 0, 1, 0)
	cooldownBar.Size = UDim2.new(1, 0, 0, 3)
	cooldownBar.BorderSizePixel = 0
	cooldownBar.Parent = box

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Position = UDim2.new(0, 10, 0.5, -18)
	keyLabel.Size = UDim2.new(0, 36, 0, 36)
	keyLabel.BackgroundColor3 = C.Card
	keyLabel.Font = Enum.Font.Oswald
	keyLabel.TextSize = 20
	keyLabel.TextColor3 = Color3.new(1, 1, 1)
	keyLabel.Text = AgentConfig.AbilityKey.Name
	keyLabel.Name = "Key"
	keyLabel.Parent = box
	UITheme.Corner(keyLabel, 3)
	UITheme.Stroke(keyLabel, C.Border, 1)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Title"
	nameLabel.Position = UDim2.new(0, 56, 0, 8)
	nameLabel.Size = UDim2.new(1, -66, 0, 24)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = UITheme.Fonts.Title
	nameLabel.TextSize = 20
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = box

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "State"
	stateLabel.Position = UDim2.new(0, 56, 0, 32)
	stateLabel.Size = UDim2.new(1, -66, 0, 20)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Font = UITheme.Fonts.Title
	stateLabel.TextSize = 15
	stateLabel.TextXAlignment = Enum.TextXAlignment.Left
	stateLabel.Parent = box

	-- Sprint-Stoß: kurzer Schub in Laufrichtung (bzw. Blickrichtung, wenn man steht)
	Remotes.AbilityEffect.OnClientEvent:Connect(function(effect, speed, duration)
		if effect ~= "Dash" then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then
			return
		end
		local direction = humanoid.MoveDirection
		if direction.Magnitude < 0.1 then
			local look = workspace.CurrentCamera.CFrame.LookVector
			direction = Vector3.new(look.X, 0, look.Z)
		end
		direction = direction.Unit
		local started = os.clock()
		local connection
		connection = RunService.Heartbeat:Connect(function()
			if os.clock() - started > duration or not root.Parent then
				connection:Disconnect()
				return
			end
			root.AssemblyLinearVelocity = Vector3.new(direction.X * speed, math.max(root.AssemblyLinearVelocity.Y, 2),
				direction.Z * speed)
		end)
	end)

	-- Radar-Puls: markierte Gegner rot durch Wände anzeigen (nur für uns sichtbar)
	Remotes.Reveal.OnClientEvent:Connect(function(characters, duration)
		for _, character in characters do
			if typeof(character) == "Instance" and character.Parent then
				local highlight = Instance.new("Highlight")
				highlight.FillColor = Color3.fromRGB(255, 60, 60)
				highlight.FillTransparency = 0.5
				highlight.OutlineColor = Color3.fromRGB(255, 60, 60)
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.Parent = character
				Debris:AddItem(highlight, duration)
			end
		end
	end)

	-- Gadget-Box links neben der Fähigkeit
	local gadgetBox = box:Clone()
	gadgetBox.Position = UDim2.new(0.5, -250, 1, -24)
	gadgetBox.Size = UDim2.new(0, 220, 0, 62)
	gadgetBox.Parent = gui
	gadgetBox.Key.Text = AgentConfig.GadgetKey.Name
	gadgetBox:FindFirstChildOfClass("UIStroke").Color = C.Border
	local gadgetName, gadgetCount = gadgetBox.Title, gadgetBox.State
	gadgetBox.Bar.BackgroundColor3 = C.Accent

	-- Gesamtdauer der aktuellen Abklingzeit (für den Ladebalken)
	local cooldownTotal = 1
	player:GetAttributeChangedSignal("AbilityReadyAt"):Connect(function()
		cooldownTotal = math.max(1, (player:GetAttribute("AbilityReadyAt") or 0) - workspace:GetServerTimeNow())
	end)

	-- Weißer Blitz beim Geblendet-werden
	local flash = Instance.new("Frame")
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 10
	flash.Parent = gui
	Remotes.Flash.OnClientEvent:Connect(function(duration)
		flash.BackgroundTransparency = 0
		-- Erst voll weiß halten, dann langsam ausblenden
		task.delay(duration * 0.4, function()
			TweenService:Create(flash, TweenInfo.new(duration * 0.6), { BackgroundTransparency = 1 }):Play()
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Modes.IsFighting(player) then
			return
		end
		if input.KeyCode == AgentConfig.AbilityKey then
			Remotes.UseAbility:FireServer()
		elseif input.KeyCode == AgentConfig.GadgetKey then
			Remotes.UseGadget:FireServer(workspace.CurrentCamera.CFrame.LookVector)
		end
	end)

	-- Anzeige laufend aktualisieren
	RunService.Heartbeat:Connect(function()
		-- Aktiver Agent dieses Lebens, sonst der gewählte
		local character = player.Character
		local agent = AgentConfig.Get(character and character:GetAttribute("Agent"))
			or AgentConfig.Get(player:GetAttribute("Agent"))
			or AgentConfig.Agents[1]
		agentLabel.Text = agent.Name .. "  ·  " .. agent.Role
		agentLabel.TextColor3 = agent.Color
		nameLabel.Text = agent.Ability.Name
		stroke.Color = agent.Color
		local charges = player:GetAttribute("Gadgets") or 0
		gadgetName.Text = agent.Gadget.Name
		gadgetCount.Text = charges > 0 and ("× " .. charges) or "AUFGEBRAUCHT"
		gadgetCount.TextColor3 = charges > 0 and C.Good or C.Muted
		gadgetBox.Bar.Size = UDim2.new(charges > 0 and 1 or 0, 0, 0, 3)

		local now = workspace:GetServerTimeNow()
		local activeLeft = (player:GetAttribute("AbilityActiveUntil") or 0) - now
		local cooldownLeft = (player:GetAttribute("AbilityReadyAt") or 0) - now
		if activeLeft > 0 then
			stateLabel.Text = string.format("AKTIV  %.1fs", activeLeft)
			stateLabel.TextColor3 = agent.Color
			cooldownBar.Size = UDim2.new(1, 0, 0, 3)
			cooldownBar.BackgroundColor3 = agent.Color
		elseif cooldownLeft > 0 then
			stateLabel.Text = string.format("LÄDT  %ds", math.ceil(cooldownLeft))
			stateLabel.TextColor3 = C.Muted
			cooldownBar.Size = UDim2.new(math.clamp(1 - cooldownLeft / cooldownTotal, 0, 1), 0, 0, 3)
			cooldownBar.BackgroundColor3 = C.Muted
		else
			stateLabel.Text = "BEREIT"
			stateLabel.TextColor3 = C.Good
			cooldownBar.Size = UDim2.new(1, 0, 0, 3)
			cooldownBar.BackgroundColor3 = C.Good
		end
	end)
end

return AbilityClient

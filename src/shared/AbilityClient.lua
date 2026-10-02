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
	agentLabel.Font = Enum.Font.GothamBlack
	agentLabel.TextSize = 20
	agentLabel.TextXAlignment = Enum.TextXAlignment.Left
	agentLabel.TextStrokeTransparency = 0.5
	agentLabel.Parent = gui

	-- Fähigkeits-Box unten mittig
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.new(0.5, 0, 1, -24)
	box.Size = UDim2.new(0, 240, 0, 62)
	box.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
	box.BackgroundTransparency = 0.25
	box.BorderSizePixel = 0
	box.Parent = gui
	Instance.new("UICorner").Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = box

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Position = UDim2.new(0, 10, 0.5, -18)
	keyLabel.Size = UDim2.new(0, 36, 0, 36)
	keyLabel.BackgroundColor3 = Color3.fromRGB(40, 44, 58)
	keyLabel.Font = Enum.Font.GothamBlack
	keyLabel.TextSize = 20
	keyLabel.TextColor3 = Color3.new(1, 1, 1)
	keyLabel.Text = AgentConfig.AbilityKey.Name
	keyLabel.Name = "Key"
	keyLabel.Parent = box
	Instance.new("UICorner").Parent = keyLabel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Title"
	nameLabel.Position = UDim2.new(0, 56, 0, 8)
	nameLabel.Size = UDim2.new(1, -66, 0, 24)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = box

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "State"
	stateLabel.Position = UDim2.new(0, 56, 0, 32)
	stateLabel.Size = UDim2.new(1, -66, 0, 20)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Font = Enum.Font.Gotham
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
	gadgetBox:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(255, 140, 40)
	local gadgetName, gadgetCount = gadgetBox.Title, gadgetBox.State

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
		gadgetCount.Text = charges > 0 and ("× " .. charges) or "aufgebraucht"
		gadgetCount.TextColor3 = charges > 0 and Color3.fromRGB(110, 220, 120) or Color3.fromRGB(170, 175, 190)

		local now = workspace:GetServerTimeNow()
		local activeLeft = (player:GetAttribute("AbilityActiveUntil") or 0) - now
		local cooldownLeft = (player:GetAttribute("AbilityReadyAt") or 0) - now
		if activeLeft > 0 then
			stateLabel.Text = string.format("AKTIV  %.1fs", activeLeft)
			stateLabel.TextColor3 = agent.Color
		elseif cooldownLeft > 0 then
			stateLabel.Text = string.format("Lädt  %ds", math.ceil(cooldownLeft))
			stateLabel.TextColor3 = Color3.fromRGB(170, 175, 190)
		else
			stateLabel.Text = "BEREIT"
			stateLabel.TextColor3 = Color3.fromRGB(110, 220, 120)
		end
	end)
end

return AbilityClient

-- Downed (ModuleScript, nur Client)
-- Eigener Charakter am Boden: hinlegen, langsam kriechen, Kamera von hinten, Anzeige mit
-- Verbluten-Timer und Wiederbelebungs-Balken.
-- Teamkollegen am Boden: Symbol "HILFE" über ihnen, in der Nähe "E halten" zum Wiederbeleben.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Movement = require(Shared.Movement)

local player = Players.LocalPlayer

local Downed = {}

local CRAWL_SPEED = 4
local REVIVE_RANGE = 7 -- wie DownedService (Server prüft selbst)
local RED = Color3.fromRGB(230, 60, 60)
local GREEN = Color3.fromRGB(90, 220, 120)

local gui, downedPanel, bleedLabel, reviveBar, promptPanel, promptLabel, promptBar
local isDowned = false
local holdingE = false
local promptTarget = nil

local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.Font = props.Font or Enum.Font.GothamBlack
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextStrokeTransparency = 0.4
	return make("TextLabel", props, parent)
end

local function progressBar(parent, y, color)
	local back = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(0, 300, 0, 10), BackgroundColor3 = Color3.fromRGB(30, 30, 35), BorderSizePixel = 0 }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, back)
	local fill = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, back)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, fill)
	return fill
end

local function build()
	gui = make("ScreenGui", { Name = "Downed", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6 },
		player:WaitForChild("PlayerGui"))

	-- Eigener Zustand am Boden
	downedPanel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.62, 0),
		Size = UDim2.new(0, 420, 0, 110), BackgroundTransparency = 1, Visible = false }, gui)
	label({ Size = UDim2.new(1, 0, 0, 40), Text = "NIEDERGESCHLAGEN", TextSize = 34, TextColor3 = RED }, downedPanel)
	bleedLabel = label({ Position = UDim2.new(0, 0, 0, 42), Size = UDim2.new(1, 0, 0, 24), Text = "", TextSize = 18,
		Font = Enum.Font.GothamBold }, downedPanel)
	reviveBar = progressBar(downedPanel, 76, GREEN)

	-- Hinweis beim Teamkollegen
	promptPanel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.6, 0),
		Size = UDim2.new(0, 420, 0, 60), BackgroundTransparency = 1, Visible = false }, gui)
	promptLabel = label({ Size = UDim2.new(1, 0, 0, 28), Text = "", TextSize = 20 }, promptPanel)
	promptBar = progressBar(promptPanel, 36, GREEN)
end

local function setReviving(holding)
	if holding ~= holdingE then
		holdingE = holding
		Remotes.Revive:FireServer(holding)
	end
end

-- Liegen und kriechen (der eigene Client steuert die Physik des eigenen Charakters)
local function onDownedChanged(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	isDowned = character:GetAttribute("Downed") == true
	if isDowned then
		setReviving(false)
		humanoid.PlatformStand = true
		Movement.SetFirstPerson(false)
	else
		-- Aufstehen: aufrecht hinstellen, Blick waagerecht
		humanoid.PlatformStand = false
		local look = workspace.CurrentCamera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
		local position = root.Position + Vector3.new(0, 2, 0)
		root.CFrame = CFrame.lookAt(position, position + flat)
		Movement.ApplyCamera()
	end
	downedPanel.Visible = isDowned
end

local function crawl(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -10, 0), params)
	local groundY = hit and hit.Position.Y or root.Position.Y - 1
	local look = workspace.CurrentCamera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local position = Vector3.new(root.Position.X, groundY + 1, root.Position.Z)
	-- Bauchlage: Kopf in Blickrichtung
	root.CFrame = CFrame.lookAt(position, position + flat) * CFrame.Angles(math.rad(-90), 0, 0)
	local move = humanoid.MoveDirection * CRAWL_SPEED
	root.AssemblyLinearVelocity = Vector3.new(move.X, 0, move.Z)
	root.AssemblyAngularVelocity = Vector3.zero
end

-- Niedergeschlagene Teamkollegen (Spieler und Bots)
local function downedMates()
	local list = {}
	if not player.Team then
		return list
	end
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Team == player.Team and p.Character and p.Character:GetAttribute("Downed") then
			table.insert(list, p.Character)
		end
	end
	local botFolder = workspace:FindFirstChild("Bots")
	if botFolder then
		for _, model in botFolder:GetChildren() do
			if model:GetAttribute("Downed") and model:GetAttribute("TeamName") == player.Team.Name then
				table.insert(list, model)
			end
		end
	end
	return list
end

-- "HILFE"-Symbol über Teamkollegen am Boden (nur lokal)
local function updateIcons(mates)
	local active = {}
	for _, model in mates do
		active[model] = true
		if not model:FindFirstChild("DownedIcon") then
			local billboard = make("BillboardGui", { Name = "DownedIcon", Size = UDim2.new(0, 90, 0, 40),
				StudsOffset = Vector3.new(0, 3, 0), AlwaysOnTop = true }, model)
			label({ Size = UDim2.new(1, 0, 1, 0), Text = "✚ HILFE", TextSize = 18, TextColor3 = RED }, billboard)
		end
	end
	-- Symbole von nicht mehr Niedergeschlagenen entfernen
	for _, holder in { workspace:FindFirstChild("Bots"), workspace } do
		if holder then
			for _, model in holder:GetChildren() do
				local icon = model:IsA("Model") and model:FindFirstChild("DownedIcon")
				if icon and not active[model] then
					icon:Destroy()
				end
			end
		end
	end
end

function Downed.Init()
	build()

	player.CharacterAdded:Connect(function(character)
		isDowned = false
		downedPanel.Visible = false
		character:GetAttributeChangedSignal("Downed"):Connect(function()
			onDownedChanged(character)
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.E and promptTarget and not isDowned then
			setReviving(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.E then
			setReviving(false)
		end
	end)

	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		-- Selbst am Boden
		if isDowned and character then
			crawl(character)
			local left = math.max(0, (character:GetAttribute("BleedoutUntil") or 0) - workspace:GetServerTimeNow())
			local progress = character:GetAttribute("ReviveProgress") or 0
			bleedLabel.Text = progress > 0 and "Wirst wiederbelebt..." or string.format("Verblutest in %d s · warte auf Hilfe", math.ceil(left))
			reviveBar.Size = UDim2.new(progress, 0, 1, 0)
		end

		-- Teamkollegen am Boden
		local mates = downedMates()
		updateIcons(mates)
		promptTarget = nil
		if root and not isDowned then
			local bestDistance = REVIVE_RANGE
			for _, model in mates do
				local mateRoot = model:FindFirstChild("HumanoidRootPart")
				local distance = mateRoot and (mateRoot.Position - root.Position).Magnitude or math.huge
				if distance <= bestDistance then
					promptTarget, bestDistance = model, distance
				end
			end
		end
		promptPanel.Visible = promptTarget ~= nil
		if promptTarget then
			local progress = promptTarget:GetAttribute("ReviveProgress") or 0
			promptLabel.Text = (holdingE and "Belebe " or "[E] halten: ") .. promptTarget.Name .. (holdingE and " wieder..." or " wiederbeleben")
			promptBar.Size = UDim2.new(progress, 0, 1, 0)
		elseif holdingE then
			setReviving(false)
		end
	end)
end

-- Für andere Module: wird gerade "E halten: wiederbeleben" angeboten? (hat Vorrang vor Zielen)
function Downed.HasPrompt()
	return promptTarget ~= nil
end

-- Für andere Module: liegt der eigene Charakter am Boden?
function Downed.IsDowned()
	return isDowned
end

return Downed

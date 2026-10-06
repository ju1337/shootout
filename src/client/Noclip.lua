-- Noclip (ModuleScript, nur Client, nur Admins)
-- B (oder der Knopf im Admin-Panel) schaltet um; der Server prüft, ob man Admin ist, und setzt das Attribut "Noclip".
-- Solange es an ist: frei fliegen durch alles. W/A/S/D in Blickrichtung, Leertaste hoch, Strg/C runter, Shift schneller.
-- Kein Schaden, der Bewegungs-Check (MovementGuard) setzt einen nicht zurück. Oben in der Mitte steht "NOCLIP".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local player = Players.LocalPlayer

local Noclip = {}

local SPEED = 70        -- Studs pro Sekunde
local FAST = 3          -- mit Shift
local KEY = Enum.KeyCode.B

local restore = {}      -- [Part] = CanCollide vorher
local active = false
local label = nil

local function character()
	local model = player.Character
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return model, humanoid, root
end

local function stop()
	if not active then
		return
	end
	active = false
	local _, humanoid, root = character()
	for part, collide in restore do
		if part.Parent then
			part.CanCollide = collide
		end
	end
	restore = {}
	if humanoid then
		humanoid.PlatformStand = false
	end
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function step(dt)
	local on = player:GetAttribute("Noclip") == true
	if label then
		label.Visible = on
	end
	if not on then
		stop()
		return
	end
	local model, humanoid, root = character()
	if not model or not humanoid or not root then
		return
	end
	active = true
	humanoid.PlatformStand = true
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			if restore[part] == nil then
				restore[part] = true
			end
			part.CanCollide = false
		end
	end
	local camera = workspace.CurrentCamera
	local look = camera and camera.CFrame or root.CFrame
	local move = Vector3.zero
	if not UserInputService:GetFocusedTextBox() then
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			move += look.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			move -= look.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			move += look.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			move -= look.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			move += Vector3.yAxis
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C) then
			move -= Vector3.yAxis
		end
	end
	local speed = SPEED * (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and FAST or 1)
	local velocity = move.Magnitude > 0.01 and move.Unit * speed or Vector3.zero
	-- Position direkt setzen (unabhängig von Schwerkraft und Kollision), Blick in Kamerarichtung
	local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
	local facing = flat.Magnitude > 0.01 and flat.Unit or root.CFrame.LookVector
	local position = root.Position + velocity * dt
	root.CFrame = CFrame.lookAt(position, position + facing)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

function Noclip.Init()
	if not player:GetAttribute("IsAdmin") then
		player:GetAttributeChangedSignal("IsAdmin"):Wait()
	end
	if not player:GetAttribute("IsAdmin") then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "NoclipHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")
	label = Instance.new("TextLabel")
	label.Name = "NoclipLabel"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 4)
	label.Size = UDim2.fromOffset(360, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(120, 220, 255)
	label.TextStrokeTransparency = 0.3
	label.Text = "NOCLIP  ·  WASD + LEERTASTE/STRG  ·  SHIFT SCHNELL  ·  B AUS"
	label.Visible = false
	label.Parent = gui
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == KEY then
			Remotes.AdminAction:FireServer("Noclip")
		end
	end)
	player.CharacterAdded:Connect(function()
		restore = {}
		active = false
	end)
	RunService.RenderStepped:Connect(step)
end

Noclip.Toggle = function()
	Remotes.AdminAction:FireServer("Noclip")
end

return Noclip

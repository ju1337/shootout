-- Pings (ModuleScript, nur Client)
-- Z oder Mausrad-Klick: Ort oder Gegner für das Team markieren. Markierungen erscheinen
-- für alle Teamkollegen als Symbol (durch Wände sichtbar) mit kurzem Ton.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local InputActions = require(Shared.InputActions)

local player = Players.LocalPlayer

local Pings = {}

local PING_TIME = 4        -- Sekunden für Orts-Markierungen
local ENEMY_TIME = 3       -- Sekunden für Gegner-Markierungen
local PING_SOUND = "rbxasset://sounds/electronicpingshort.wav"

local function ping()
	local camera = workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, camera }
	local result = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 600, params)
	if not result then
		return
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local hasHumanoid = model and model:FindFirstChildOfClass("Humanoid") ~= nil
	Remotes.Ping:FireServer(result.Position, hasHumanoid and model or nil)
end

local function showPing(position, model, pingerName, isEnemy)
	-- Der Gegner ist evtl. nicht gestreamt (model = nil), der Server meldet ihn trotzdem
	local enemy = model ~= nil or isEnemy == true
	local adornee
	if model and model:FindFirstChild("HumanoidRootPart") then
		adornee = model.HumanoidRootPart
	else
		local anchor = Instance.new("Attachment")
		anchor.WorldPosition = position
		anchor.Parent = workspace.Terrain
		Debris:AddItem(anchor, enemy and ENEMY_TIME or PING_TIME)
		adornee = anchor
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.new(0, 120, 0, 50)
	billboard.StudsOffset = Vector3.new(0, enemy and 4 or 1.5, 0)
	billboard.Parent = player:WaitForChild("PlayerGui")

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(1, 0, 0.6, 0)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.BuilderSansBold
	icon.TextSize = 26
	icon.Text = enemy and "!" or "▼"
	icon.TextColor3 = enemy and Color3.fromRGB(226, 72, 60) or Color3.fromRGB(212, 170, 80)
	icon.TextStrokeTransparency = 0.3
	icon.Parent = billboard
	local name = Instance.new("TextLabel")
	name.Position = UDim2.new(0, 0, 0.6, 0)
	name.Size = UDim2.new(1, 0, 0.4, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.BuilderSansBold
	name.TextSize = 13
	name.Text = enemy and ("GEGNER · " .. pingerName) or pingerName
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.3
	name.Parent = billboard
	Debris:AddItem(billboard, enemy and ENEMY_TIME or PING_TIME)

	local sound = Instance.new("Sound")
	sound.SoundId = PING_SOUND
	sound.Volume = 0.4
	sound.PlaybackSpeed = enemy and 0.8 or 1.3
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 2)
end

function Pings.Init()
	InputActions.Bind("Ping", function(began)
		if began and Modes.IsFighting(player) then
			ping()
		end
	end)
	-- Mittlere Maustaste pingt zusätzlich
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton3 and Modes.IsFighting(player) then
			ping()
		end
	end)
	Remotes.PingShow.OnClientEvent:Connect(showPing)
end

return Pings

-- Training (ModuleScript, nur Server)
-- Schießstand zum Ausprobieren: Übungspuppen stehen nach dem Umfallen wieder auf, zwei laufen
-- hin und her. Man kann nicht sterben, Agentenwechsel gilt sofort (Neu-Spawn).

local Players = game:GetService("Players")

local SpawnUtil = require(script.Parent.Parent.SpawnUtil)

local Training = {}

local DUMMY_RESPAWN = 2
local DUMMY_HEALTH = 100
local RUN_DISTANCE = 16     -- Laufstrecke der beweglichen Puppen (hin und her)

local members = {}
local map = workspace:WaitForChild("Maps"):WaitForChild("Training")
local dummyFolder = Instance.new("Folder")
dummyFolder.Name = "TrainingDummies"
dummyFolder.Parent = workspace

local function spawnPlayer(player)
	if not members[player] then
		return
	end
	local character = SpawnUtil.Spawn(player, SpawnUtil.Pick(map.Spawns))
	if not character then
		return
	end
	player:SetAttribute("CanFight", true)
	player:SetAttribute("ModeText", "Training · Puppen stehen wieder auf · Agent wechseln mit M")
	-- Im Training kann man nicht sterben
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.HealthChanged:Connect(function(health)
		if health < humanoid.MaxHealth then
			humanoid.Health = humanoid.MaxHealth
		end
	end)
end

-- Übungspuppe an einer Markierung, steht nach dem Umfallen wieder auf
local function spawnDummy(marker)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = Color3.fromRGB(230, 200, 160)
	description.TorsoColor = Color3.fromRGB(200, 60, 60)
	description.LeftArmColor = Color3.fromRGB(200, 60, 60)
	description.RightArmColor = Color3.fromRGB(200, 60, 60)
	description.LeftLegColor = Color3.fromRGB(60, 60, 70)
	description.RightLegColor = Color3.fromRGB(60, 60, 70)
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok or not model then
		warn("Übungspuppe konnte nicht erstellt werden: " .. tostring(model))
		return
	end
	model.Name = "Übungspuppe"
	model:SetAttribute("IsDummy", true)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = DUMMY_HEALTH
	humanoid.Health = DUMMY_HEALTH
	humanoid.DisplayName = "Übungspuppe"
	humanoid.WalkSpeed = 10
	model.Parent = dummyFolder
	model:PivotTo(marker.CFrame * CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(90), 0))

	-- Laufende Puppen pendeln zwischen zwei Punkten
	local running = string.find(marker.Name, "Run") ~= nil
	if running then
		task.spawn(function()
			local a = marker.Position + Vector3.new(0, 0, -RUN_DISTANCE / 2)
			local b = marker.Position + Vector3.new(0, 0, RUN_DISTANCE / 2)
			local target = a
			while humanoid.Health > 0 and model.Parent do
				humanoid:MoveTo(target)
				humanoid.MoveToFinished:Wait()
				target = target == a and b or a
			end
		end)
	end

	humanoid.Died:Connect(function()
		task.delay(DUMMY_RESPAWN, function()
			model:Destroy()
			spawnDummy(marker)
		end)
	end)
end

function Training.Init()
	for _, marker in map:WaitForChild("Dummies"):GetChildren() do
		task.spawn(spawnDummy, marker)
	end
	-- Agent gewechselt: sofort neu spawnen, damit Waffen und Fähigkeit passen
	local function onPlayer(player)
		local function respawn()
			if members[player] then
				task.spawn(spawnPlayer, player)
			end
		end
		player:GetAttributeChangedSignal("Agent"):Connect(respawn)
		player:GetAttributeChangedSignal("Loadouts"):Connect(respawn) -- Primärwaffe gewechselt
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

function Training.CanJoin()
	return true
end

function Training.AddPlayer(player)
	members[player] = true
	spawnPlayer(player)
end

function Training.RemovePlayer(player)
	members[player] = nil
end

return Training

-- Hub (ModuleScript, nur Server)
-- Treffpunkt: kein Kampf, Portale schicken Spieler in die Modi.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RankConfig = require(ReplicatedStorage:WaitForChild("Shared").RankConfig)

local SpawnUtil = require(script.Parent.Parent.SpawnUtil)

local Hub = {}

local RESPAWN_TIME = 2
local PORTAL_COOLDOWN = 3

local manager
local members = {}
local lastTouch = {}
local map = workspace:WaitForChild("Maps"):WaitForChild("Hub")

local function spawnPlayer(player)
	if not members[player] then
		return
	end
	local character = SpawnUtil.Spawn(player, SpawnUtil.Pick(map.Spawns))
	if not character then
		return
	end
	character:WaitForChild("Humanoid").Died:Connect(function()
		task.delay(RESPAWN_TIME, function()
			if members[player] and player.Character == character then
				spawnPlayer(player)
			end
		end)
	end)
end

-- ---------- Siegertreppchen: Avatar-Statuen der Top 3 nach ELO ----------
local statues = {} -- [Platz] = { UserId, Model }

local function placeStatue(place, entry)
	local pad = map:FindFirstChild("Podium") and map.Podium:FindFirstChild("Podium" .. place)
	local current = statues[place]
	if current and entry and current.UserId == entry.UserId then
		return -- gleiche Person, nichts zu tun
	end
	if current and current.Model then
		current.Model:Destroy()
	end
	statues[place] = nil
	if not pad or not entry or not entry.UserId then
		return
	end
	statues[place] = { UserId = entry.UserId }
	local ok, model = pcall(Players.CreateHumanoidModelFromUserId, Players, entry.UserId)
	if not ok or not model then
		return
	end
	model.Name = "Statue" .. place
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		elseif part:IsA("Script") or part:IsA("LocalScript") then
			part:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	-- Auf das Podest stellen, Blick nach Norden (zum Eingang der Ruhmeshalle)
	local top = pad.Position - Vector3.new(0, pad.Size.Y / 2 + 0.1, 0)
	model:PivotTo(CFrame.lookAt(top, top + Vector3.new(0, 0, 1)))
	local box, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, top.Y - (box.Position.Y - size.Y / 2), 0))
	-- Namensschild mit ELO und Rang
	local head = model:FindFirstChild("Head")
	if head then
		local rank = RankConfig.Get(entry.Value)
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(0, 220, 0, 52)
		billboard.StudsOffset = Vector3.new(0, 2.6, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 120
		billboard.Parent = head
		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, 0, 0.55, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBlack
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextStrokeTransparency = 0.3
		name.Text = "#" .. place .. "  " .. tostring(entry.Name)
		name.Parent = billboard
		local info = Instance.new("TextLabel")
		info.Position = UDim2.new(0, 0, 0.55, 0)
		info.Size = UDim2.new(1, 0, 0.45, 0)
		info.BackgroundTransparency = 1
		info.Font = Enum.Font.Oswald
		info.TextScaled = true
		info.TextColor3 = rank.Color
		info.TextStrokeTransparency = 0.3
		info.Text = rank.Display .. "  ·  " .. tostring(entry.Value) .. " ELO"
		info.Parent = billboard
	end
	-- Inzwischen ersetzt? Dann wegwerfen
	if not statues[place] or statues[place].UserId ~= entry.UserId then
		model:Destroy()
		return
	end
	statues[place].Model = model
	model.Parent = map
end

local function updatePodium()
	local ok, list = pcall(HttpService.JSONDecode, HttpService, ReplicatedStorage:GetAttribute("Leaderboard_Elo") or "[]")
	list = ok and type(list) == "table" and list or {}
	for place = 1, 3 do
		task.spawn(placeStatue, place, list[place])
	end
end

function Hub.Init(modeManager)
	manager = modeManager
	updatePodium()
	ReplicatedStorage:GetAttributeChangedSignal("Leaderboard_Elo"):Connect(updatePodium)

	-- Portale: Parts "Portal_<ModusId>" in Maps.Hub.Portals
	for _, pad in map.Portals:GetChildren() do
		local modeId = string.match(pad.Name, "^Portal_(.+)$")
		if pad:IsA("BasePart") and modeId then
			pad.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if not player or not members[player] then
					return
				end
				local now = os.clock()
				if lastTouch[player] and now - lastTouch[player] < PORTAL_COOLDOWN then
					return
				end
				lastTouch[player] = now
				manager.Join(player, modeId)
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player] = nil
	end)
end

function Hub.CanJoin()
	return true
end

function Hub.AddPlayer(player)
	members[player] = true
	spawnPlayer(player)
end

function Hub.RemovePlayer(player)
	members[player] = nil
end

return Hub

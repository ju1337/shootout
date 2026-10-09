-- ZentraleService (ModuleScript, nur Server)
-- Einsatzzentrale in Camp Phoenix (früher der Hub): Siegertreppchen mit Avatar-Statuen der Top 3 nach ELO.
-- Die Teile (Podium1..3) liegen in der Gruppe Zentrale der Map Extinction (siehe Shared/Zentrale).

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RankConfig = require(Shared.RankConfig)
local Zentrale = require(Shared.Zentrale)

local ZentraleService = {}

local folder = nil

-- ---------- Siegertreppchen: Avatar-Statuen der Top 3 nach ELO ----------
local statues = {} -- [Platz] = { UserId, Model }

local function placeStatue(place, entry)
	local pad = folder and folder:FindFirstChild("Podium" .. place)
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
	-- Auf das Podest stellen, Blick wie die Podest-Markierung (LookVector). Ausgerichtet wird an den Füßen:
	-- nur die Körperteile direkt im Modell zählen, nicht Accessoires (die hängen teils weit weg und
	-- würden die Figur sonst über dem Podest schweben lassen).
	local top = pad.Position - Vector3.new(0, pad.Size.Y / 2, 0)
	local facing = Vector3.new(pad.CFrame.LookVector.X, 0, pad.CFrame.LookVector.Z)
	model:PivotTo(CFrame.lookAt(top, top + (facing.Magnitude > 0.1 and facing.Unit or Vector3.new(0, 0, 1))))
	local lowest = math.huge
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			-- tiefster Punkt des (aufrechten) Teils
			local extent = math.abs(part.CFrame.UpVector.Y) * part.Size.Y / 2 + math.abs(part.CFrame.RightVector.Y) * part.Size.X / 2
				+ math.abs(part.CFrame.LookVector.Y) * part.Size.Z / 2
			lowest = math.min(lowest, part.Position.Y - extent)
		end
	end
	if lowest == math.huge then
		-- keine Körperteile gefunden: über Hüfthöhe
		local root = model:FindFirstChild("HumanoidRootPart")
		lowest = root and (root.Position.Y - root.Size.Y / 2 - (humanoid and humanoid.HipHeight or 2)) or top.Y
	end
	model:PivotTo(model:GetPivot() + Vector3.new(0, top.Y - lowest, 0))
	-- Namensschild mit ELO und Rang
	local head = model:FindFirstChild("Head")
	if head then
		local rank = RankConfig.Get(entry.Value)
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(5.5, 0, 1.3, 0) -- in Studs, damit es den Titel dahinter nicht überdeckt
		billboard.StudsOffset = Vector3.new(0, 1.8, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 120
		billboard.Parent = head
		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, 0, 0.55, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.BuilderSansExtraBold
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextStrokeTransparency = 0.3
		name.Text = "#" .. place .. "  " .. tostring(entry.Name)
		name.Parent = billboard
		local info = Instance.new("TextLabel")
		info.Position = UDim2.new(0, 0, 0.55, 0)
		info.Size = UDim2.new(1, 0, 0.45, 0)
		info.BackgroundTransparency = 1
		info.Font = Enum.Font.BuilderSansExtraBold
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
	model.Parent = folder
end

local function updatePodium()
	local ok, list = pcall(HttpService.JSONDecode, HttpService, ReplicatedStorage:GetAttribute("Leaderboard_Elo") or "[]")
	list = ok and type(list) == "table" and list or {}
	for place = 1, 3 do
		task.spawn(placeStatue, place, list[place])
	end
end

function ZentraleService.Init()
	task.spawn(function()
		folder = Zentrale.Folder(30)
		if not folder then
			warn("[Zentrale] Gruppe Zentrale in Maps.Extinction fehlt – keine Statuen")
			return
		end
		updatePodium()
		ReplicatedStorage:GetAttributeChangedSignal("Leaderboard_Elo"):Connect(updatePodium)
	end)
end

return ZentraleService

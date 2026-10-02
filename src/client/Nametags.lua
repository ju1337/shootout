-- Nametags (ModuleScript, nur Client)
-- Eigene Namensschilder statt der Roblox-Namen (die Gegner durch Wände verraten würden):
--   Hub:      alle Spieler mit Rang-Raute, Name und Spielerlevel
--   Kampf:    nur Teamkollegen (Spieler und Bots) mit Name in Teamfarbe, Gegner ohne Namen

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared.LevelConfig)
local RankConfig = require(Shared.RankConfig)

local player = Players.LocalPlayer

local Nametags = {}

local TAG_NAME = "ShootoutNametag"

local function removeTag(model)
	local tag = model and model:FindFirstChild(TAG_NAME)
	if tag then
		tag:Destroy()
	end
end

-- Schild erzeugen bzw. aktualisieren
local function setTag(model, title, subtitle, color)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local tag = model:FindFirstChild(TAG_NAME)
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = TAG_NAME
		tag.Size = UDim2.new(0, 200, 0, 46)
		tag.StudsOffset = Vector3.new(0, 2.6, 0)
		tag.MaxDistance = 120
		tag.AlwaysOnTop = false
		local name = Instance.new("TextLabel")
		name.Name = "Title"
		name.Size = UDim2.new(1, 0, 0.6, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.Oswald
		name.TextScaled = true
		name.TextStrokeTransparency = 0.4
		name.Parent = tag
		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitle"
		sub.Position = UDim2.new(0, 0, 0.6, 0)
		sub.Size = UDim2.new(1, 0, 0.4, 0)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(200, 210, 225)
		sub.TextStrokeTransparency = 0.5
		sub.Parent = tag
		tag.Adornee = head
		tag.Parent = model
	end
	tag.Title.Text = title
	tag.Title.TextColor3 = color
	tag.Subtitle.Text = subtitle or ""
	tag.Subtitle.Visible = subtitle ~= nil
end

local function update()
	local myMode = player:GetAttribute("Mode")
	local inHub = myMode == "Hub"
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and other ~= player then
			local sameMode = other:GetAttribute("Mode") == myMode
			local mate = player.Team ~= nil and other.Team == player.Team
			if inHub and sameMode then
				local rank = RankConfig.Get(other:GetAttribute("Elo") or RankConfig.StartElo)
				setTag(character, "◆ " .. other.Name, LevelConfig.Display(other) .. "  ·  " .. rank.Display, rank.Color)
			elseif sameMode and mate then
				setTag(character, other.Name, nil, other.TeamColor.Color)
			else
				removeTag(character)
			end
		end
	end
	-- Bots: nur Teamkollegen beschriften
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, model in bots:GetChildren() do
			local mate = player.Team ~= nil and model:GetAttribute("TeamName") == player.Team.Name
				and model:GetAttribute("Mode") == myMode
			if mate then
				setTag(model, model.Name, nil, player.TeamColor.Color)
			else
				removeTag(model)
			end
		end
	end
end

function Nametags.Init()
	task.spawn(function()
		while true do
			update()
			task.wait(0.5)
		end
	end)
end

return Nametags

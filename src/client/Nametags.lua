-- Nametags (ModuleScript, nur Client)
-- Eigene Namensschilder statt der Roblox-Namen (die Gegner durch Wände verraten würden):
--   Hub:      alle Spieler mit Prestige-Abzeichen (PrestigeEmblem: Symbol je Stufe), Name und Rang
--             (auch das eigene Schild, sobald man sich von außen sieht)
--   Kampf:    nur Teamkollegen (Spieler und Bots) mit Name in Teamfarbe, Gegner ohne Namen

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared.LevelConfig)
local RankConfig = require(Shared.RankConfig)
local PrestigeEmblem = require(Shared.PrestigeEmblem)

local player = Players.LocalPlayer

local Nametags = {}

local TAG_NAME = "ShootoutNametag"

local function removeTag(model)
	local tag = model and model:FindFirstChild(TAG_NAME)
	if tag then
		tag:Destroy()
	end
end

local emblems = {} -- [Schild] = PrestigeEmblem (wird beim Entfernen des Schilds gelöscht)

local function newLabel(parent, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	for key, value in props do
		label[key] = value
	end
	label.Parent = parent
	return label
end

-- Schild aufbauen: links das Prestige-Abzeichen (Raute mit Level), rechts Name und Unterzeile
local function buildTag(model, head)
	local tag = Instance.new("BillboardGui")
	tag.Name = TAG_NAME
	tag.Size = UDim2.new(0, 250, 0, 64)
	tag.StudsOffset = Vector3.new(0, 2.8, 0)
	tag.MaxDistance = 120
	tag.AlwaysOnTop = false
	tag.LightInfluence = 0

	local holder = Instance.new("Frame")
	holder.Name = "Emblem"
	holder.Size = UDim2.new(0, 60, 0, 60)
	holder.BackgroundTransparency = 1
	holder.Parent = tag
	emblems[tag] = PrestigeEmblem.new(holder, 60)
	tag.Destroying:Connect(function()
		emblems[tag] = nil
	end)

	newLabel(tag, { Name = "Title", Position = UDim2.new(0, 64, 0, 4), Size = UDim2.new(1, -64, 0.55, 0),
		Font = Enum.Font.Oswald, TextXAlignment = Enum.TextXAlignment.Left })
	newLabel(tag, { Name = "Subtitle", Position = UDim2.new(0, 64, 0.58, 0), Size = UDim2.new(1, -64, 0.36, 0),
		Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 0.5 })
	tag.Adornee = head
	tag.Parent = model
	return tag
end

-- Schild erzeugen bzw. aktualisieren. info: { Name, Color, Subtitle, SubColor, Player (für das Abzeichen) }
local function setTag(model, info)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local tag = model:FindFirstChild(TAG_NAME) or buildTag(model, head)
	tag.Title.Text = info.Name
	tag.Title.TextColor3 = info.Color
	tag.Subtitle.Text = info.Subtitle or ""
	tag.Subtitle.TextColor3 = info.SubColor or Color3.fromRGB(200, 210, 225)
	tag.Subtitle.Visible = info.Subtitle ~= nil
	local emblem = tag.Emblem
	emblem.Visible = info.Player ~= nil
	-- Ohne Abzeichen (Bots) Text nach links rücken
	tag.Title.Position = UDim2.new(0, info.Player and 64 or 0, 0, 4)
	tag.Subtitle.Position = UDim2.new(0, info.Player and 64 or 0, 0.58, 0)
	if info.Player then
		local level = LevelConfig.Get(info.Player)
		local emblem = emblems[tag]
		if not emblem then
			-- Abzeichen fehlt (sollte nicht passieren): neu aufbauen
			tag.Emblem:ClearAllChildren()
			emblem = PrestigeEmblem.new(tag.Emblem, 60)
			emblems[tag] = emblem
		end
		emblem:Set(level.Level, level.Prestige)
	end
end

local function update()
	local myMode = player:GetAttribute("Mode")
	local inHub = myMode == "Hub"
	-- Eigenes Schild: nur im Hub (sichtbar, wenn man sich von außen sieht)
	local myCharacter = player.Character
	if myCharacter then
		if inHub then
			local level = LevelConfig.Get(player)
			local rank = RankConfig.Get(player:GetAttribute("Elo") or RankConfig.StartElo)
			setTag(myCharacter, { Name = player.Name, Color = level.Prestige > 0 and level.Color or Color3.new(1, 1, 1),
				Subtitle = "◆ " .. rank.Display, SubColor = rank.Color, Player = player })
		else
			removeTag(myCharacter)
		end
	end
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and other ~= player then
			local sameMode = other:GetAttribute("Mode") == myMode
			local mate = player.Team ~= nil and other.Team == player.Team
			local level = LevelConfig.Get(other)
			if inHub and sameMode then
				-- Hub: Name in Prestige-Farbe (ab Prestige 1), Rang darunter
				local rank = RankConfig.Get(other:GetAttribute("Elo") or RankConfig.StartElo)
				setTag(character, { Name = other.Name, Color = level.Prestige > 0 and level.Color or Color3.new(1, 1, 1),
					Subtitle = "◆ " .. rank.Display, SubColor = rank.Color, Player = other })
			elseif sameMode and mate then
				-- Kampf: nur Teamkollegen, Name in Teamfarbe, Abzeichen bleibt
				setTag(character, { Name = other.Name, Color = other.TeamColor.Color, Player = other })
			else
				removeTag(character)
			end
		end
	end
	-- Bots: nur Teamkollegen beschriften (ohne Abzeichen)
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, model in bots:GetChildren() do
			local mate = player.Team ~= nil and model:GetAttribute("TeamName") == player.Team.Name
				and model:GetAttribute("Mode") == myMode
			if mate then
				setTag(model, { Name = model.Name, Color = player.TeamColor.Color })
			else
				removeTag(model)
			end
		end
	end
end

function Nametags.Init()
	-- Eigenes Schild in der Ego-Ansicht ausblenden (sonst schwebt es vor der Kamera)
	game:GetService("RunService").RenderStepped:Connect(function()
		local character = player.Character
		local tag = character and character:FindFirstChild(TAG_NAME)
		local head = character and character:FindFirstChild("Head")
		if tag and head then
			tag.Enabled = (workspace.CurrentCamera.CFrame.Position - head.Position).Magnitude > 4
		end
	end)
	task.spawn(function()
		while true do
			-- Ein Fehler darf die Schleife nicht beenden (sonst aktualisieren sich die Schilder nie wieder)
			local ok, err = pcall(update)
			if not ok then
				warn("Nametags: " .. tostring(err))
			end
			task.wait(0.5)
		end
	end)
end

return Nametags

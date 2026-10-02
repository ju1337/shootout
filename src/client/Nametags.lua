-- Nametags (ModuleScript, nur Client)
-- Eigene Namensschilder statt der Roblox-Namen (die Gegner durch Wände verraten würden):
--   Hub:      alle Spieler mit Prestige-Abzeichen (Raute mit Level, Farbe je Prestige, ★-Stufe), Name und Rang
--             (auch das eigene Schild, sobald man sich von außen sieht)
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

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
local LEGEND = ColorSequence.new({ -- Prestige 10: Regenbogen-Abzeichen
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 60)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 130)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
})
local legendGradients = {} -- drehende Verläufe der Legenden-Abzeichen

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
	tag.Size = UDim2.new(0, 250, 0, 58)
	tag.StudsOffset = Vector3.new(0, 2.8, 0)
	tag.MaxDistance = 120
	tag.AlwaysOnTop = false
	tag.LightInfluence = 0

	local emblem = Instance.new("Frame")
	emblem.Name = "Emblem"
	emblem.Size = UDim2.new(0, 58, 0, 58)
	emblem.BackgroundTransparency = 1
	emblem.Parent = tag
	-- Äußere Raute in Prestige-Farbe (mit Verlauf), innere dunkle Raute, Level-Zahl darüber
	local outer = Instance.new("Frame")
	outer.Name = "Outer"
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.new(0.5, 0, 0.42, 0)
	outer.Size = UDim2.new(0, 34, 0, 34)
	outer.Rotation = 45
	outer.BorderSizePixel = 0
	outer.Parent = emblem
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = outer
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Gradient"
	gradient.Rotation = 90
	gradient.Parent = outer
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.new(0.5, 0, 0.5, 0)
	inner.Size = UDim2.new(0.66, 0, 0.66, 0)
	inner.BackgroundColor3 = Color3.fromRGB(14, 22, 36)
	inner.BorderSizePixel = 0
	inner.Parent = outer
	newLabel(emblem, { Name = "Level", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 26, 0, 16), Font = Enum.Font.GothamBlack, TextColor3 = Color3.new(1, 1, 1) })
	-- Prestige-Band unter der Raute ("★ III")
	newLabel(emblem, { Name = "Prestige", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 14), Font = Enum.Font.GothamBlack })

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
		local gradient = emblem.Outer.Gradient
		emblem.Level.Text = tostring(level.Level)
		if level.Prestige >= LevelConfig.MaxPrestige then
			emblem.Outer.BackgroundColor3 = Color3.new(1, 1, 1)
			gradient.Color = LEGEND
			legendGradients[gradient] = true
		else
			emblem.Outer.BackgroundColor3 = level.Color
			gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 160))
			legendGradients[gradient] = nil
		end
		emblem.Prestige.Visible = level.Prestige > 0
		emblem.Prestige.Text = "★ " .. (ROMAN[level.Prestige] or tostring(level.Prestige))
		emblem.Prestige.TextColor3 = level.Color
		emblem.Outer.Size = UDim2.new(0, level.Prestige > 0 and 36 or 32, 0, level.Prestige > 0 and 36 or 32)
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
	-- Legenden-Abzeichen (Prestige 10) drehen ihren Regenbogen-Verlauf
	game:GetService("RunService").RenderStepped:Connect(function(dt)
		for gradient in legendGradients do
			if gradient.Parent then
				gradient.Rotation = (gradient.Rotation + dt * 90) % 360
			else
				legendGradients[gradient] = nil
			end
		end
	end)
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
			update()
			task.wait(0.5)
		end
	end)
end

return Nametags

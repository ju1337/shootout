-- Nametags (ModuleScript, nur Client)
-- Eigene Namensschilder statt der Roblox-Namen (die Gegner durch Wände verraten würden):
--   Hub:      alle Spieler mit Prestige-Abzeichen (PrestigeEmblem: Symbol je Stufe), Name und Rang
--             (auch das eigene Schild, sobald man sich von außen sieht)
--   Kampf:    nur Teamkollegen (Spieler und Bots) mit Name in Verbündeten-Blau (wie im HUD), Gegner ohne Namen

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared.LevelConfig)
local RankConfig = require(Shared.RankConfig)
local PrestigeEmblem = require(Shared.PrestigeEmblem)
local UITheme = require(Shared.UITheme)

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

local parts = {} -- [Schild] = { Title, Subtitle, Emblem, Divider } (wird beim Entfernen gelöscht)

-- Schild: kleine Karte (dunkel, halbdurchsichtig, abgerundet), die sich der Textbreite anpasst:
-- [Prestige-Abzeichen] | [Name / Rang]
local function buildTag(model, head)
	local tag = Instance.new("BillboardGui")
	tag.Name = TAG_NAME
	tag.Size = UDim2.new(0, 320, 0, 56)
	tag.StudsOffset = Vector3.new(0, 2.9, 0)
	tag.MaxDistance = 120
	tag.AlwaysOnTop = false
	tag.LightInfluence = 0

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(0, 0, 1, 0)
	card.AutomaticSize = Enum.AutomaticSize.X
	card.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
	card.BackgroundTransparency = 0.35
	card.Parent = tag
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.85
	stroke.Parent = card
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	local holder = Instance.new("Frame")
	holder.Name = "Emblem"
	holder.Size = UDim2.new(0, 50, 0, 50)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = 1
	holder.Parent = card
	emblems[tag] = PrestigeEmblem.new(holder, 50)

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(0, 2, 0, 34)
	divider.BorderSizePixel = 0
	divider.LayoutOrder = 2
	divider.Parent = card

	local column = Instance.new("Frame")
	column.Name = "Text"
	column.Size = UDim2.new(0, 0, 1, 0)
	column.AutomaticSize = Enum.AutomaticSize.X
	column.BackgroundTransparency = 1
	column.LayoutOrder = 3
	column.Parent = card
	local columnLayout = Instance.new("UIListLayout")
	columnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnLayout.Parent = column
	local title = newLabel(column, { Name = "Title", Size = UDim2.new(0, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false, TextSize = 22, Font = Enum.Font.Oswald, TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.7, LayoutOrder = 1 })
	local subtitle = newLabel(column, { Name = "Subtitle", Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false, TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.8, LayoutOrder = 2 })

	parts[tag] = { Title = title, Subtitle = subtitle, Emblem = holder, Divider = divider }
	tag.Destroying:Connect(function()
		emblems[tag] = nil
		parts[tag] = nil
	end)
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
	local tag = model:FindFirstChild(TAG_NAME)
	if not tag or not parts[tag] then
		if tag then
			tag:Destroy()
		end
		tag = buildTag(model, head)
	end
	local p = parts[tag]
	p.Title.Text = info.Name
	p.Title.TextColor3 = info.Color
	p.Subtitle.Text = info.Subtitle or ""
	p.Subtitle.TextColor3 = info.SubColor or Color3.fromRGB(200, 210, 225)
	p.Subtitle.Visible = info.Subtitle ~= nil
	-- Ohne Abzeichen (Bots) nur der Name
	p.Emblem.Visible = info.Player ~= nil
	p.Divider.Visible = info.Player ~= nil
	if info.Player then
		local level = LevelConfig.Get(info.Player)
		local emblem = emblems[tag]
		if not emblem then
			p.Emblem:ClearAllChildren()
			emblem = PrestigeEmblem.new(p.Emblem, 50)
			emblems[tag] = emblem
		end
		emblem:Set(level.Level, level.Prestige)
		p.Divider.BackgroundColor3 = level.Prestige > 0 and level.Color or Color3.fromRGB(120, 185, 235)
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
				Subtitle = rank.Display, SubColor = rank.Color, Player = player })
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
					Subtitle = rank.Display, SubColor = rank.Color, Player = other })
			elseif sameMode and mate then
				-- Kampf: nur Teamkollegen, Name in Verbündeten-Blau, Abzeichen bleibt
				setTag(character, { Name = other.Name, Color = UITheme.Colors.Ally, Player = other })
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
				setTag(model, { Name = model.Name, Color = UITheme.Colors.Ally })
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

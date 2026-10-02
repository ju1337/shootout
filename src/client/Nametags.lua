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

local parts = {} -- [Schild] = { Title, Subtitle, Emblem, RankPill } (wird beim Entfernen gelöscht)

-- Schild: links das Prestige-Abzeichen (frei, ohne Kasten), rechts eine runde dunkle Pille mit dem Namen
-- und darunter eine kleine Pille in Rangfarbe. Passt sich der Textbreite an und bleibt mittig über dem Kopf.
local function pill(parent, name, height, order)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(0, 0, 0, height)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.LayoutOrder = order
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, height * 0.45)
	padding.PaddingRight = UDim.new(0, height * 0.45)
	padding.Parent = frame
	local label = newLabel(frame, { Name = "Label", Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false, TextStrokeTransparency = 1 })
	return frame, label
end

local function buildTag(model, head)
	local tag = Instance.new("BillboardGui")
	tag.Name = TAG_NAME
	tag.Size = UDim2.new(0, 320, 0, 56)
	tag.StudsOffset = Vector3.new(0, 2.9, 0)
	tag.MaxDistance = 120
	tag.AlwaysOnTop = false
	tag.LightInfluence = 0

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.new(0, 0, 1, 0)
	row.AutomaticSize = Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	row.Parent = tag
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local holder = Instance.new("Frame")
	holder.Name = "Emblem"
	holder.Size = UDim2.new(0, 48, 0, 48)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = 1
	holder.Parent = row
	emblems[tag] = PrestigeEmblem.new(holder, 48)

	local column = Instance.new("Frame")
	column.Name = "Text"
	column.Size = UDim2.new(0, 0, 1, 0)
	column.AutomaticSize = Enum.AutomaticSize.X
	column.BackgroundTransparency = 1
	column.LayoutOrder = 2
	column.Parent = row
	local columnLayout = Instance.new("UIListLayout")
	columnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	columnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	columnLayout.Padding = UDim.new(0, 3)
	columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnLayout.Parent = column

	local namePill, title = pill(column, "NamePill", 26, 1)
	namePill.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
	namePill.BackgroundTransparency = 0.25
	title.Font = Enum.Font.Oswald
	title.TextSize = 20
	local rankPill, subtitle = pill(column, "RankPill", 17, 2)
	rankPill.BackgroundTransparency = 0.1
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextSize = 11
	subtitle.TextColor3 = Color3.fromRGB(14, 16, 19)

	parts[tag] = { Title = title, Subtitle = subtitle, Emblem = holder, RankPill = rankPill }
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
	-- Rang-Pille in Rangfarbe (dunkle Schrift), nur wenn es eine Unterzeile gibt
	p.Subtitle.Text = info.Subtitle or ""
	p.RankPill.Visible = info.Subtitle ~= nil
	p.RankPill.BackgroundColor3 = info.SubColor or Color3.fromRGB(150, 160, 175)
	-- Ohne Abzeichen (Bots) nur der Name
	p.Emblem.Visible = info.Player ~= nil
	if info.Player then
		local level = LevelConfig.Get(info.Player)
		local emblem = emblems[tag]
		if not emblem then
			p.Emblem:ClearAllChildren()
			emblem = PrestigeEmblem.new(p.Emblem, 48)
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

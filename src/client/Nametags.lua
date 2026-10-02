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

-- Schild: schmales dunkles Namensschild (leicht abgerundet, dünner Rand in Prestige-Farbe) mit dem Namen und
-- darunter klein "LV 42 · MEISTER". Das kleine Prestige-Abzeichen ist links angedockt (überlappt den Rand).
local function hex(color)
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local function buildTag(model, head)
	local tag = Instance.new("BillboardGui")
	tag.Name = TAG_NAME
	tag.Size = UDim2.new(0, 300, 0, 50)
	tag.StudsOffset = Vector3.new(0, 2.7, 0)
	tag.MaxDistance = 120
	tag.AlwaysOnTop = false
	tag.LightInfluence = 0
	tag.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

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
	layout.Padding = UDim.new(0, -10) -- Abzeichen überlappt den linken Rand des Schilds
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local holder = Instance.new("Frame")
	holder.Name = "Emblem"
	holder.Size = UDim2.new(0, 36, 0, 36)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = 1
	holder.ZIndex = 3
	holder.Parent = row
	emblems[tag] = PrestigeEmblem.new(holder, 36)

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.new(0, 0, 0, 0)
	plate.AutomaticSize = Enum.AutomaticSize.XY
	plate.BackgroundColor3 = Color3.fromRGB(12, 15, 20)
	plate.BackgroundTransparency = 0.25
	plate.LayoutOrder = 2
	plate.ZIndex = 1
	plate.Parent = row
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Edge"
	stroke.Thickness = 1
	stroke.Transparency = 0.45
	stroke.Parent = plate
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = plate
	local lines = Instance.new("UIListLayout")
	lines.SortOrder = Enum.SortOrder.LayoutOrder
	lines.Parent = plate
	local title = newLabel(plate, { Name = "Title", Size = UDim2.new(0, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false, TextSize = 19, Font = Enum.Font.Oswald, TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1, LayoutOrder = 1, ZIndex = 2 })
	local subtitle = newLabel(plate, { Name = "Subtitle", Size = UDim2.new(0, 0, 0, 13), AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false, TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1, RichText = true, TextColor3 = Color3.fromRGB(150, 160, 172), LayoutOrder = 2, ZIndex = 2 })

	parts[tag] = { Title = title, Subtitle = subtitle, Emblem = holder, Plate = plate, Edge = stroke }
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
	-- Ohne Abzeichen (Bots) nur der Name, Schild ohne Platz links
	p.Emblem.Visible = info.Player ~= nil
	p.Plate:FindFirstChildOfClass("UIPadding").PaddingLeft = UDim.new(0, info.Player and 16 or 10)
	local levelText = nil
	if info.Player then
		local level = LevelConfig.Get(info.Player)
		local emblem = emblems[tag]
		if not emblem then
			p.Emblem:ClearAllChildren()
			emblem = PrestigeEmblem.new(p.Emblem, 36)
			emblems[tag] = emblem
		end
		emblem:Set(level.Level, level.Prestige)
		p.Edge.Color = level.Color
		levelText = (level.Prestige > 0 and ("P" .. level.Prestige .. " · ") or "") .. "LV " .. level.Level
	else
		p.Edge.Color = Color3.fromRGB(120, 130, 145)
	end
	-- Zweite Zeile: Level (grau) · Rang (in Rangfarbe); im Kampf ohne Rang nur das Level
	local rank = info.Subtitle and ('<font color="' .. hex(info.SubColor or Color3.new(1, 1, 1)) .. '">'
		.. info.Subtitle .. "</font>")
	if levelText and rank then
		p.Subtitle.Text = levelText .. "  ·  " .. rank
	else
		p.Subtitle.Text = rank or levelText or ""
	end
	p.Subtitle.Visible = p.Subtitle.Text ~= ""
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

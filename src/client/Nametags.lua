-- Nametags (ModuleScript, nur Client)
-- Eigene Namensschilder statt der Roblox-Namen (die Gegner durch Wände verraten würden):
--   Hub/Markt: alle Spieler mit Prestige-Abzeichen (PrestigeEmblem: Symbol je Stufe), Name und Rang, darüber
--             ihr RAP (Guthaben + Wert der handelbaren Skins, RapConfig) in der Farbe seiner Stufe
--             (auch das eigene Schild, sobald man sich von außen sieht)
--   Kampf:    nur Teamkollegen (Spieler und Bots) mit Name in Verbündeten-Blau (wie im HUD), Gegner ohne Namen

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared.LevelConfig)
local RankConfig = require(Shared.RankConfig)
local PrestigeEmblem = require(Shared.PrestigeEmblem)
local RankEmblem = require(Shared.RankEmblem)
local TitleConfig = require(Shared.TitleConfig)
local UITheme = require(Shared.UITheme)
local RapConfig = require(Shared.RapConfig)
local Modes = require(Shared.Modes)

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

local parts = {} -- [Schild] = { Title, Subtitle, SubRow, RankHolder, RankEmblem, Emblem, Bar, Row, Rap, RapText, RapStroke }

-- Schild (ohne Kasten): links das Prestige-Abzeichen mit Level, rechts der Name groß, darunter ein kurzer
-- Strich in Prestige-Farbe und der Rang in Rangfarbe. Alles mittig über dem Kopf, Schrift mit dunkler Kontur.
local function buildTag(model, head)
	local tag = Instance.new("BillboardGui")
	tag.Name = TAG_NAME
	tag.Size = UDim2.new(0, 360, 0, 70)
	tag.StudsOffset = Vector3.new(0, 2.9, 0)
	tag.MaxDistance = 120
	tag.AlwaysOnTop = false
	tag.LightInfluence = 0

	-- dezente, durchsichtige Karte mit feinem Rand um Abzeichen und Text
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.new(0, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
	row.BackgroundTransparency = 0.6
	row.Parent = tag
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = row
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.new(1, 1, 1)
	edge.Transparency = 0.8
	edge.Parent = row
	local inset = Instance.new("UIPadding")
	inset.PaddingLeft = UDim.new(0, 4)
	inset.PaddingRight = UDim.new(0, 12)
	inset.PaddingTop = UDim.new(0, 2)
	inset.PaddingBottom = UDim.new(0, 2)
	inset.Parent = row
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local holder = Instance.new("Frame")
	holder.Name = "Emblem"
	holder.Size = UDim2.new(0, 58, 0, 58)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = 1
	holder.Parent = row
	emblems[tag] = PrestigeEmblem.new(holder, 58)

	local column = Instance.new("Frame")
	column.Name = "Text"
	column.Size = UDim2.new(0, 0, 0, 0)
	column.AutomaticSize = Enum.AutomaticSize.XY
	column.BackgroundTransparency = 1
	column.LayoutOrder = 2
	column.Parent = row
	local lines = Instance.new("UIListLayout")
	lines.SortOrder = Enum.SortOrder.LayoutOrder
	lines.Padding = UDim.new(0, 2)
	lines.Parent = column
	local title = newLabel(column, { Name = "Title", Size = UDim2.new(0, 0, 0, 26), AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false, TextSize = 26, Font = Enum.Font.Oswald, TextXAlignment = Enum.TextXAlignment.Left, RichText = true,
		TextStrokeColor3 = Color3.fromRGB(8, 10, 14), TextStrokeTransparency = 0.35, LayoutOrder = 1 })
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(0, 34, 0, 2)
	bar.BorderSizePixel = 0
	bar.LayoutOrder = 2
	bar.Parent = column
	-- Unterzeile: kleines Rang-Abzeichen + Rang (und Titel)
	local subRow = Instance.new("Frame")
	subRow.Name = "SubRow"
	subRow.Size = UDim2.new(0, 0, 0, 0)
	subRow.AutomaticSize = Enum.AutomaticSize.XY
	subRow.BackgroundTransparency = 1
	subRow.LayoutOrder = 3
	subRow.Parent = column
	local subLayout = Instance.new("UIListLayout")
	subLayout.FillDirection = Enum.FillDirection.Horizontal
	subLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	subLayout.Padding = UDim.new(0, 3)
	subLayout.SortOrder = Enum.SortOrder.LayoutOrder
	subLayout.Parent = subRow
	local rankHolder = Instance.new("Frame")
	rankHolder.Name = "Rank"
	rankHolder.Size = UDim2.new(0, 20, 0, 20)
	rankHolder.BackgroundTransparency = 1
	rankHolder.LayoutOrder = 1
	rankHolder.Parent = subRow
	local rankEmblem = RankEmblem.new(rankHolder, 20)
	local subtitle = newLabel(subRow, { Name = "Subtitle", Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false, TextSize = 15, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeColor3 = Color3.fromRGB(8, 10, 14), TextStrokeTransparency = 0.45, LayoutOrder = 2, RichText = true })

	-- RAP über der Karte (nur Hub und Markt): Raute + Zahl in der Farbe der RAP-Stufe
	local rap = Instance.new("Frame")
	rap.Name = "Rap"
	rap.AnchorPoint = Vector2.new(0.5, 0)
	rap.Position = UDim2.fromScale(0.5, 0)
	rap.Size = UDim2.new(0, 0, 0, 24)
	rap.AutomaticSize = Enum.AutomaticSize.X
	rap.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
	rap.BackgroundTransparency = 0.45
	rap.Visible = false
	rap.Parent = tag
	local rapCorner = Instance.new("UICorner")
	rapCorner.CornerRadius = UDim.new(0, 12)
	rapCorner.Parent = rap
	local rapStroke = Instance.new("UIStroke")
	rapStroke.Thickness = 1
	rapStroke.Transparency = 0.35
	rapStroke.Parent = rap
	local rapPad = Instance.new("UIPadding")
	rapPad.PaddingLeft = UDim.new(0, 7)
	rapPad.PaddingRight = UDim.new(0, 10)
	rapPad.Parent = rap
	local rapLayout = Instance.new("UIListLayout")
	rapLayout.FillDirection = Enum.FillDirection.Horizontal
	rapLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rapLayout.Padding = UDim.new(0, 5)
	rapLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rapLayout.Parent = rap
	UITheme.RapIcon(rap, 15, { LayoutOrder = 1 })
	local rapText = newLabel(rap, { Name = "Amount", Size = UDim2.new(0, 0, 0, 20), AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false, TextSize = 19, Font = Enum.Font.Oswald, TextStrokeColor3 = Color3.fromRGB(8, 10, 14),
		TextStrokeTransparency = 0.4, LayoutOrder = 2 })

	parts[tag] = { Title = title, Subtitle = subtitle, SubRow = subRow, RankHolder = rankHolder, RankEmblem = rankEmblem,
		Emblem = holder, Bar = bar, Row = row, Rap = rap, RapText = rapText, RapStroke = rapStroke }
	tag.Destroying:Connect(function()
		emblems[tag] = nil
		parts[tag] = nil
	end)
	tag.Adornee = head
	tag.Parent = model
	return tag
end

-- Schild erzeugen bzw. aktualisieren. info: { Name, Color, Subtitle, SubColor, Rank (RankConfig.Get, für das
-- Rang-Abzeichen), Player (für das Prestige-Abzeichen), Rap (Zahl: RAP über der Karte zeigen, nil = keins) }
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
	p.SubRow.Visible = info.Subtitle ~= nil
	-- Mit RAP wird das Schild höher: RAP oben, Karte darunter (etwas weiter über dem Kopf)
	local rap = info.Rap
	p.Rap.Visible = rap ~= nil
	tag.Size = UDim2.new(0, 360, 0, rap and 98 or 70)
	tag.StudsOffset = Vector3.new(0, rap and 3.25 or 2.9, 0)
	p.Row.Position = rap and UDim2.new(0.5, 0, 1, -35) or UDim2.fromScale(0.5, 0.5)
	if rap then
		local color = RapConfig.TierColor(rap)
		p.RapText.Text = UITheme.FormatNumber(rap) .. " RAP"
		p.RapText.TextColor3 = color
		p.RapStroke.Color = color
		p.RapStroke.Thickness = rap >= RapConfig.Tiers[5].Min and 2 or 1
	end
	p.RankHolder.Visible = info.Rank ~= nil
	if info.Rank then
		p.RankEmblem:SetRank(info.Rank)
	end
	-- Ohne Abzeichen (Bots) nur der Name
	p.Emblem.Visible = info.Player ~= nil
	p.Bar.Visible = info.Player ~= nil
	if info.Player then
		local level = LevelConfig.Get(info.Player)
		local emblem = emblems[tag]
		if not emblem then
			p.Emblem:ClearAllChildren()
			emblem = PrestigeEmblem.new(p.Emblem, 58)
			emblems[tag] = emblem
		end
		emblem:Set(level.Level, level.Prestige)
		p.Bar.BackgroundColor3 = level.Color
	end
end

-- Name mit Clan-Kürzel und goldenem VIP davor (Gamepass VIP)
local function displayName(target)
	local name = target.Name
	local tag = target:GetAttribute("ClanTag")
	if tag then
		name = '<font color="#8FC3FF">[' .. tag .. ']</font> ' .. name
	end
	if target:GetAttribute("Pass_VIP") == true then
		name = '<font color="#FFD24A">VIP</font> ' .. name
	end
	return name
end

-- Unterzeile: Rang und (falls gewählt) Titel in seiner Farbe
local function subtitleFor(target, rank)
	local title = TitleConfig.Get(target:GetAttribute("Title") or "")
	if not title or title.Id == TitleConfig.Default then
		return rank.Display
	end
	return rank.Display .. '  ·  <font color="#' .. title.Color:ToHex() .. '">' .. UITheme.Upper(title.Name) .. "</font>"
end

-- RAP über dem Kopf: Guthaben + Wert der handelbaren Skins
local function rapOf(target)
	return math.floor((tonumber(target:GetAttribute("Rap")) or 0) + (tonumber(target:GetAttribute("RapValue")) or 0))
end

local function update()
	local myMode = player:GetAttribute("Mode")
	local inHub = myMode ~= nil and Modes.IsSocial(myMode) -- Hub und Markt
	-- Eigenes Schild: nur im Hub (sichtbar, wenn man sich von außen sieht)
	local myCharacter = player.Character
	if myCharacter then
		if inHub then
			local level = LevelConfig.Get(player)
			local rank = RankConfig.Get(player:GetAttribute("Elo") or RankConfig.StartElo)
			setTag(myCharacter, { Name = displayName(player), Color = level.Prestige > 0 and level.Color or Color3.new(1, 1, 1),
				Subtitle = subtitleFor(player, rank), SubColor = rank.Color, Rank = rank, Player = player, Rap = rapOf(player) })
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
				-- Hub/Markt: Name in Prestige-Farbe (ab Prestige 1), Rang darunter, RAP darüber
				local rank = RankConfig.Get(other:GetAttribute("Elo") or RankConfig.StartElo)
				setTag(character, { Name = displayName(other), Color = level.Prestige > 0 and level.Color or Color3.new(1, 1, 1),
					Subtitle = subtitleFor(other, rank), SubColor = rank.Color, Rank = rank, Player = other, Rap = rapOf(other) })
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

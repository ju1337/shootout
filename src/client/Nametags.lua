-- Nametags (ModuleScript, nur Client)
-- Eigene Namensschilder statt der Roblox-Namen (die Gegner durch Wände verraten würden):
--   Markt und Safe Zones in Extinction: alle Spieler (dort wird nicht gekämpft) mit dem vollen Schild
--             (auch das eigene, sobald man sich von außen sieht)
--   Kampf:    nur Teamkollegen (Spieler und Bots) mit Name in Verbündeten-Blau (wie im HUD), Gegner ohne Namen
-- Aussehen wie die Kacheln von Inventar und Hotbar: flache, dunkle, halbdurchsichtige Kachel mit knapper Rundung,
-- ohne Rand, unten ein feiner Strich in Prestige-Farbe (wie der Seltenheits-Strich der Items). Darin links das
-- Prestige-Abzeichen mit Level, rechts oben Team-Rang (DEV, VIP …) als kleines Farbschild und der Name, darunter
-- eine Zeile: Rang-Abzeichen + Rang · RAP (Symbol + kurze Zahl in der Farbe der RAP-Stufe) · gewählter Titel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelConfig = require(Shared.LevelConfig)
local RankConfig = require(Shared.RankConfig)
local PrestigeEmblem = require(Shared.PrestigeEmblem)
local RankEmblem = require(Shared.RankEmblem)
local TitleConfig = require(Shared.TitleConfig)
local StaffConfig = require(Shared.StaffConfig)
local UITheme = require(Shared.UITheme)
local RapConfig = require(Shared.RapConfig)
local Modes = require(Shared.Modes)
local TeamCheck = require(Shared.TeamCheck)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make = UITheme.Make

local Nametags = {}

local TAG_NAME = "ShootoutNametag"
local TILE = Color3.fromRGB(14, 15, 18) -- wie die Kacheln im Inventar (ExtinctionClient Inv.TILE)
local EMBLEM = 38

local function removeTag(model)
	local tag = model and model:FindFirstChild(TAG_NAME)
	if tag then
		tag:Destroy()
	end
end

local emblems = {} -- [Schild] = PrestigeEmblem (wird beim Entfernen des Schilds gelöscht)
local parts = {} -- [Schild] = Teile des Schilds (siehe buildTag)

local function text(parent, props)
	props.BackgroundTransparency = 1
	props.TextScaled = false
	props.AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.X
	props.TextXAlignment = Enum.TextXAlignment.Left
	props.TextColor3 = props.TextColor3 or C.Text
	local label = make("TextLabel", props, parent)
	UITheme.Outline(label)
	return label
end

local function row(parent, name, order, padding)
	local frame = make("Frame", { Name = name, Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1, LayoutOrder = order }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, padding), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	return frame
end

-- kleiner Punkt als Trenner in der Info-Zeile (gezeichnet, nicht jede Schrift hat "·")
local function dot(parent, order)
	local holder = make("Frame", { Name = "Dot" .. order, Size = UDim2.fromOffset(7, 12), BackgroundTransparency = 1,
		LayoutOrder = order }, parent)
	local d = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(3, 3), BackgroundColor3 = C.Muted, BorderSizePixel = 0 }, holder)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
	return holder
end

-- RAP kurz: 950, 12.4K, 3.1M
function Nametags.ShortNumber(n)
	n = math.floor(n or 0)
	local function short(value, suffix)
		local s = string.format("%.1f", value)
		return (string.gsub(s, "%.0$", "")) .. suffix
	end
	if n >= 1e6 then
		return short(math.floor(n / 1e5) / 10, "M")
	elseif n >= 1e4 then
		return short(math.floor(n / 1e2) / 10, "K")
	end
	return UITheme.FormatNumber(n)
end

local function buildTag(model, head)
	local tag = make("BillboardGui", { Name = TAG_NAME, Size = UDim2.fromOffset(340, 64), StudsOffset = Vector3.new(0, 2.6, 0),
		MaxDistance = 120, AlwaysOnTop = false, LightInfluence = 0 }, nil)

	-- Kachel unten mittig im Schild (wächst nach oben und zur Seite)
	local card = make("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = TILE, BackgroundTransparency = 0.35,
		BorderSizePixel = 0 }, tag)
	UITheme.Corner(card, 3)
	local content = row(card, "Row", 1, 7)
	make("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 6) }, content)
	-- Prestige-Strich unten (an den Enden um die Rundung eingerückt)
	local strip = make("Frame", { Name = "Strip", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 3, 1, 0),
		Size = UDim2.new(1, -6, 0, 2), BorderSizePixel = 0, ZIndex = 2 }, card)

	local holder = make("Frame", { Name = "Emblem", Size = UDim2.fromOffset(EMBLEM, EMBLEM), BackgroundTransparency = 1,
		LayoutOrder = 1 }, content)
	emblems[tag] = PrestigeEmblem.new(holder, EMBLEM)

	local column = make("Frame", { Name = "Text", Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1, LayoutOrder = 2 }, content)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1),
		VerticalAlignment = Enum.VerticalAlignment.Center }, column)

	-- oben: Team-Rang als Farbschild + Name
	local top = row(column, "Top", 1, 5)
	local staff = make("TextLabel", { Name = "Staff", Size = UDim2.fromOffset(0, 15), AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 11, Font = F.Display, TextColor3 = C.PrimaryText, BorderSizePixel = 0, Text = "", Visible = false,
		LayoutOrder = 1 }, top)
	UITheme.Corner(staff, 3)
	make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, staff)
	local title = text(top, { Name = "Title", Size = UDim2.fromOffset(0, 21), TextSize = 20, Font = F.Display, RichText = true,
		LayoutOrder = 2 })

	-- darunter: Rang · RAP · Titel
	local info = row(column, "Info", 2, 4)
	local rankHolder = make("Frame", { Name = "Rank", Size = UDim2.fromOffset(15, 15), BackgroundTransparency = 1,
		LayoutOrder = 1 }, info)
	local rankEmblem = RankEmblem.new(rankHolder, 15)
	local rankText = text(info, { Name = "Subtitle", Size = UDim2.fromOffset(0, 14), TextSize = 12, Font = F.Bold, LayoutOrder = 2 })
	local rapDot = dot(info, 3)
	local rapIcon = UITheme.RapIcon(info, 12, { Name = "RapIcon", LayoutOrder = 4 })
	local rapText = text(info, { Name = "Rap", Size = UDim2.fromOffset(0, 14), TextSize = 12, Font = F.Bold, LayoutOrder = 5 })
	local titleDot = dot(info, 6)
	local titleText = text(info, { Name = "PlayerTitle", Size = UDim2.fromOffset(0, 14), TextSize = 12, Font = F.Bold,
		LayoutOrder = 7 })

	parts[tag] = { Card = card, Strip = strip, Emblem = holder, Staff = staff, Title = title, Info = info,
		RankHolder = rankHolder, RankEmblem = rankEmblem, RankText = rankText, RapDot = rapDot, RapIcon = rapIcon,
		RapText = rapText, TitleDot = titleDot, TitleText = titleText }
	tag.Destroying:Connect(function()
		emblems[tag] = nil
		parts[tag] = nil
	end)
	tag.Adornee = head
	tag.Parent = model
	return tag
end

-- Schild erzeugen bzw. aktualisieren. info: { Name, Color, Staff (StaffConfig-Rang), Rank (RankConfig.Get),
-- Player (für Prestige-Abzeichen und -Strich), Rap (Zahl, nil = keins), Title (TitleConfig-Eintrag, nil = keiner) }
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
	-- Instance Streaming: der Kopf kann neu geladen werden, das Schild hängt dann am neuen
	if tag.Adornee ~= head then
		tag.Adornee = head
	end
	local p = parts[tag]
	p.Title.Text = info.Name
	p.Title.TextColor3 = info.Color
	local staff = info.Staff
	p.Staff.Visible = staff ~= nil
	if staff then
		p.Staff.Text = staff.Name
		p.Staff.BackgroundColor3 = staff.Color
	end

	local rank, rap, playerTitle = info.Rank, info.Rap, info.Title
	p.Info.Visible = rank ~= nil or rap ~= nil or playerTitle ~= nil
	p.RankHolder.Visible = rank ~= nil
	p.RankText.Visible = rank ~= nil
	if rank then
		p.RankEmblem:SetRank(rank)
		p.RankText.Text = rank.Display
		p.RankText.TextColor3 = rank.Color
	end
	p.RapDot.Visible = rap ~= nil and rank ~= nil
	p.RapIcon.Visible = rap ~= nil
	p.RapText.Visible = rap ~= nil
	if rap then
		p.RapText.Text = Nametags.ShortNumber(rap)
		p.RapText.TextColor3 = RapConfig.TierColor(rap)
	end
	p.TitleDot.Visible = playerTitle ~= nil and (rank ~= nil or rap ~= nil)
	p.TitleText.Visible = playerTitle ~= nil
	if playerTitle then
		p.TitleText.Text = UITheme.Upper(playerTitle.Name)
		p.TitleText.TextColor3 = playerTitle.Color
	end

	-- Ohne Abzeichen (Bots) nur der Name
	p.Emblem.Visible = info.Player ~= nil
	p.Strip.Visible = info.Player ~= nil
	if info.Player then
		local level = LevelConfig.Get(info.Player)
		local emblem = emblems[tag]
		if not emblem then
			p.Emblem:ClearAllChildren()
			emblem = PrestigeEmblem.new(p.Emblem, EMBLEM)
			emblems[tag] = emblem
		end
		emblem:Set(level.Level, level.Prestige)
		p.Strip.BackgroundColor3 = level.Color
	end
end

-- Name mit Clan-Kürzel davor (Team-Rang steht als eigenes Schild davor)
local function displayName(target)
	local tag = target:GetAttribute("ClanTag")
	if tag then
		return '<font color="#8FC3FF">[' .. tag .. ']</font> ' .. target.Name
	end
	return target.Name
end

-- Gewählter Titel (nil = Standardtitel, dann keiner)
local function titleOf(target)
	local title = TitleConfig.Get(target:GetAttribute("Title") or "")
	if not title or title.Id == TitleConfig.Default then
		return nil
	end
	return title
end

-- RAP: Guthaben + Wert der handelbaren Skins
local function rapOf(target)
	return math.floor((tonumber(target:GetAttribute("Rap")) or 0) + (tonumber(target:GetAttribute("RapValue")) or 0))
end

-- Volles Schild zum Angeben: Prestige-Abzeichen, Team-Rang, Name, Rang, RAP, Titel
local function showcase(target)
	local level = LevelConfig.Get(target)
	return { Name = displayName(target), Color = level.Prestige > 0 and level.Color or C.Text, Staff = StaffConfig.Of(target),
		Rank = RankConfig.Get(target:GetAttribute("Elo") or RankConfig.StartElo), Player = target, Rap = rapOf(target),
		Title = titleOf(target) }
end

-- Zeigt der Spieler im Modus mode gerade sein volles Schild? Markt immer, Extinction in der Safe Zone
-- (Camp und Safehouses: dort ist kein PvP, also verrät der Name niemanden)
function Nametags.Showcase(mode, inSafeZone)
	if mode == nil then
		return false
	end
	return Modes.IsSocial(mode) or (Modes.IsSurvival(mode) and inSafeZone == true)
end

local function update()
	local myMode = player:GetAttribute("Mode")
	-- Eigenes Schild (sichtbar, wenn man sich von außen sieht)
	local myCharacter = player.Character
	if myCharacter then
		if Nametags.Showcase(myMode, player:GetAttribute("InSafeZone")) then
			setTag(myCharacter, showcase(player))
		else
			removeTag(myCharacter)
		end
	end
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and other ~= player then
			local sameMode = myMode ~= nil and other:GetAttribute("Mode") == myMode
			local mate = (player.Team ~= nil and other.Team == player.Team) or TeamCheck.IsSquadMate(other)
			if sameMode and Nametags.Showcase(myMode, other:GetAttribute("InSafeZone")) then
				setTag(character, showcase(other))
			elseif sameMode and mate then
				-- Kampf: nur Teamkollegen, Name in Verbündeten-Blau, Abzeichen bleibt
				setTag(character, { Name = other.Name, Color = C.Ally, Staff = StaffConfig.Of(other), Player = other })
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
				setTag(model, { Name = model.Name, Color = C.Ally })
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

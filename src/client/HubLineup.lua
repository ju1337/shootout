-- HubLineup (ModuleScript, nur Client)
-- Phönixplatz in Camp Phoenix (früher der Hub, Teile in der Gruppe Zentrale der Map Extinction, siehe
-- Shared/Zentrale): Shop-Vitrine mit Theke, Lagebericht (Lage der offenen Welt: Spieler, Blutmond, Sturmnacht),
-- Bestenlisten an der Ruhmeswand, Leuchtpartikel am Siegerpodest. Nur lokal sichtbar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)
local Modes = require(Shared.Modes)
local DayCycle = require(Shared.DayCycle)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local HttpService = game:GetService("HttpService")
local GunModels = require(Shared.GunModels)
local GameMenu = require(Shared.GameMenu)
local UITheme = require(Shared.UITheme)
local Zentrale = require(Shared.Zentrale)

local player = Players.LocalPlayer

-- Holo-Tafel (Attribut "Holo" am Part): Schrift leuchtet unabhängig vom Licht, mit blauem Schimmer
local function holoSurface(surface, part)
	if part:GetAttribute("Holo") then
		surface.LightInfluence = 0
		surface.Brightness = 1.3
		for _, label in surface:GetDescendants() do
			if label:IsA("TextLabel") then
				label.TextStrokeColor3 = Color3.fromRGB(40, 120, 180)
				label.TextStrokeTransparency = 0.5
			end
		end
	end
end


local HubLineup = {}

-- Shop-Vitrine beim Ausrüster im Camp: drei Angebote des Tages (Waffen-Skins) drehen sich in den Vitrinen
-- ("ShopDisplay1..3"), Schilder davor ("ShopPlaque1..3") mit Name, Seltenheit und Preis.
-- An der Theke ("ShopCounter") öffnet E den Shop (offene Welt: SHOP-Reiter im EXTINCTION-Menü). Angebote wechseln
-- täglich (Serverzeit, für alle gleich).
local DAY = 24 * 3600

local function dailyOffers()
	local day = math.floor(workspace:GetServerTimeNow() / DAY)
	local random = Random.new(day * 7919 + 17)
	local weapons = {}
	for _, item in Cosmetics.List("Weapon") do
		if Cosmetics.ForSale(item) then
			table.insert(weapons, item)
		end
	end
	local offers = {}
	for _ = 1, math.min(3, #weapons) do
		table.insert(offers, table.remove(weapons, random:NextInteger(1, #weapons)))
	end
	return offers, day
end

local function buildShopVitrine()
	local decor = Zentrale.Folder(60)
	if not decor then
		return
	end
	local counter = decor:WaitForChild("ShopCounter", 60)
	if not counter then
		return -- Zentrale ohne Shop
	end
	-- E an der Theke öffnet den Shop (Prompt nur lokal)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Shop öffnen"
	prompt.ObjectText = "SHOP"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	prompt.Triggered:Connect(function()
		-- Offene Welt: wie überall dort der SHOP-Reiter des EXTINCTION-Menüs (erst hier laden, damit sich die
		-- Ladereihenfolge der Module nicht ändert); sonst (Arcade) die Lobby
		if Modes.IsSurvival(player:GetAttribute("Mode")) and require(script.Parent.ExtinctionClient).OpenTab("Shop") then
			return
		end
		GameMenu.Open("Shop")
	end)

	local models, shownDay = {}, nil
	local function plaque(index, item)
		local part = decor:FindFirstChild("ShopPlaque" .. index)
		if not part then
			return
		end
		local surface = part:FindFirstChild("PlaqueGui")
		if not surface then
			surface = Instance.new("SurfaceGui")
			surface.ResetOnSpawn = false
			surface.Name = "PlaqueGui"
			surface.Face = Enum.NormalId.Front
			surface.LightInfluence = 0
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 60
			surface.Adornee = part
			surface.Parent = player:WaitForChild("PlayerGui")
			for _, spec in { { "ItemName", 0.04, 0.46, Enum.Font.BuilderSansExtraBold }, { "ItemInfo", 0.54, 0.4, Enum.Font.BuilderSansBold } } do
				local label = Instance.new("TextLabel")
				label.Name = spec[1]
				label.Position = UDim2.new(0.05, 0, spec[2], 0)
				label.Size = UDim2.new(0.9, 0, spec[3], 0)
				label.BackgroundTransparency = 1
				label.Font = spec[4]
				label.TextScaled = true
				label.TextColor3 = Color3.new(1, 1, 1)
				label.Parent = surface
			end
		end
		holoSurface(surface, part)
		local rarity = Cosmetics.Rarities[item.Rarity]
		surface.ItemName.Text = string.upper(item.Name)
		surface.ItemInfo.Text = string.upper(rarity and rarity.Name or "") .. "  ·  " .. UITheme.FormatNumber(item.Price or 0)
			.. " MÜNZEN"
		surface.ItemInfo.TextColor3 = rarity and rarity.Color or Color3.new(1, 1, 1)
	end

	local function refresh()
		local offers, day = dailyOffers()
		if day == shownDay then
			return
		end
		shownDay = day
		for _, model in models do
			model.Model:Destroy()
		end
		models = {}
		for index, item in offers do
			local spot = decor:FindFirstChild("ShopDisplay" .. index)
			if spot then
				local model = GunModels.Build("Rifle", item)
				model:ScaleTo(0.7) -- passt drehend in die Vitrine
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
						part.CanCollide = false
						part.CanQuery = false
					end
				end
				model.Parent = workspace
				-- Waffe um die Mitte ihres Umrisses drehen (nicht um den Griff)
				local box = model:GetBoundingBox()
				table.insert(models, { Model = model, Spot = spot, Offset = model:GetPivot():ToObjectSpace(box) })
				plaque(index, item)
			end
		end
	end
	refresh()
	local lastCheck = os.clock()
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if t - lastCheck > 60 then
			lastCheck = t
			refresh()
		end
		for i, entry in models do
			local spin = CFrame.Angles(0, t * 0.6 + i, 0)
			entry.Model:PivotTo(CFrame.new(entry.Spot.Position) * spin * entry.Offset:Inverse())
		end
	end)
end

-- Lagebericht in der Rathauslaube (Part "MissionBoard"). Offene Welt (Arcade aus): Lage für alle – wie viele Spieler
-- draußen in der Welt und im Markt sind, Blutmond und Sturmnacht (läuft gerade / kommt in etwa N Minuten).
-- Mit Arcade wie früher im Hub: live, wie viele Spieler in welchem Modus sind (nur Modi, die man betreten kann).
local BLOOD, STORM = ExtinctionConfig.BloodMoon, ExtinctionConfig.Storm
local GREEN, GREY = Color3.fromRGB(112, 178, 112), Color3.fromRGB(134, 142, 152)

-- Nächster Start eines Ereignisses, geschätzt wie im Dienst (BloodMoonService/StormService): letzter Start + Pause.
-- Wäre es während des anderen Ereignisses fällig, schiebt der Server es auf dessen Ende (+ Warnung + 2 Minuten).
-- nil = noch keins gelaufen (das erste kommt FirstDelay nach dem Serverstart, den der Client nicht kennt)
local function nextEvent(startAttr, pause, warning, otherActive, otherEndAttr)
	local start = tonumber(ReplicatedStorage:GetAttribute(startAttr))
	if not start then
		return nil
	end
	local nextStart = start + pause
	local otherEnd = tonumber(ReplicatedStorage:GetAttribute(otherEndAttr))
	if otherActive and otherEnd and nextStart - warning <= otherEnd then
		nextStart = otherEnd + warning + 120
	end
	return nextStart
end

-- Text und Farbe für ein Ereignis, das gerade nicht läuft
local function upcoming(enabled, nextStart, now)
	if not enabled or not nextStart then
		return "RUHIG", GREY
	elseif nextStart > now then
		return "IN CA. " .. math.max(1, math.ceil((nextStart - now) / 60)) .. " MIN", Color3.fromRGB(228, 231, 235)
	end
	return "BALD", Color3.fromRGB(240, 196, 120)
end

-- Zeilen der offenen Welt: { Name, function(counts, now) -> Text, Farbe }
local STATUS_LINES = {
	{ "OFFENE WELT", function(counts)
		local n = counts[Zentrale.Map] or 0
		return n .. " SPIELER", n > 0 and GREEN or GREY
	end },
	{ "MARKT", function(counts)
		local n = counts[Modes.Market.Id] or 0
		return n .. " SPIELER", n > 0 and GREEN or GREY
	end },
	{ "BLUTMOND", function(_, now)
		if DayCycle.IsBloodMoon(now) then
			return "AKTIV · NOCH " .. math.max(1, math.ceil(DayCycle.BloodMoonLeft(now) / 60)) .. " MIN", Color3.fromRGB(255, 70, 60)
		end
		return upcoming(BLOOD.Enabled, nextEvent("BloodMoonStart", math.max(BLOOD.Interval, BLOOD.Duration + 60), BLOOD.Warning,
			DayCycle.IsStorm(now), "StormEnd"), now)
	end },
	{ "STURMNACHT", function(_, now)
		if DayCycle.IsStorm(now) then
			return "AKTIV · " .. (ReplicatedStorage:GetAttribute("StormKills") or 0) .. "/"
				.. (ReplicatedStorage:GetAttribute("StormGoal") or 0) .. " GEPANZERTE", Color3.fromRGB(150, 180, 255)
		end
		return upcoming(STORM.Enabled, nextEvent("StormStart", math.max(STORM.Interval, STORM.Duration + 120), STORM.Warning,
			DayCycle.IsBloodMoon(now), "BloodMoonEnd"), now)
	end },
}

local function buildMissionBoard()
	local board = Zentrale.Part("MissionBoard", 60)
	if not board then
		return
	end
	local surface = Instance.new("SurfaceGui")
	surface.ResetOnSpawn = false -- liegt im PlayerGui: sonst beim nächsten Spawn gelöscht
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.Parent = player:WaitForChild("PlayerGui")
	surface.Adornee = board
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.16, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.BuilderSansExtraBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(212, 170, 80)
	title.Text = "LAGEBERICHT"
	title.Parent = surface
	local list, values = nil, {}
	if Modes.ArcadeEnabled then
		list = Instance.new("TextLabel")
		list.Position = UDim2.new(0.06, 0, 0.2, 0)
		list.Size = UDim2.new(0.88, 0, 0.76, 0)
		list.BackgroundTransparency = 1
		list.Font = Enum.Font.BuilderSansExtraBold
		list.TextSize = 30
		list.TextColor3 = Color3.fromRGB(228, 231, 235)
		list.TextXAlignment = Enum.TextXAlignment.Left
		list.TextYAlignment = Enum.TextYAlignment.Top
		list.RichText = true
		list.Parent = surface
	else
		-- je Zeile links der Name, rechts der Wert (einzelne Felder, damit jedes für sich übersetzt wird)
		for i, line in STATUS_LINES do
			local function cell(x, w, align, color)
				local label = Instance.new("TextLabel")
				label.Position = UDim2.new(x, 0, 0.22 + (i - 1) * 0.19, 0)
				label.Size = UDim2.new(w, 0, 0.15, 0)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.BuilderSansExtraBold
				label.TextScaled = true
				label.TextColor3 = color
				label.TextXAlignment = align
				label.Text = ""
				local limit = Instance.new("UITextSizeConstraint")
				limit.MaxTextSize = 30 -- kurze Texte nicht größer als die langen
				limit.Parent = label
				label.Parent = surface
				return label
			end
			cell(0.06, 0.4, Enum.TextXAlignment.Left, Color3.fromRGB(228, 231, 235)).Text = line[1]
			values[i] = cell(0.46, 0.48, Enum.TextXAlignment.Right, GREY)
		end
	end
	-- Spielerzahl-Felder an den Toren (Parts "GateCount_<ModusId>")
	local gateLabels = {}
	for _, part in board.Parent:GetChildren() do
		local id = string.match(part.Name, "^GateCount_(.+)$")
		if id and part:IsA("BasePart") then
			local gateGui = Instance.new("SurfaceGui")
			gateGui.ResetOnSpawn = false -- liegt im PlayerGui: sonst beim nächsten Spawn gelöscht
			gateGui.Face = Enum.NormalId.Front
			gateGui.LightInfluence = 0
			gateGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gateGui.PixelsPerStud = 40
			gateGui.Adornee = part
			gateGui.Parent = player:WaitForChild("PlayerGui")
			local countLabel = Instance.new("TextLabel")
			countLabel.Size = UDim2.new(1, 0, 1, 0)
			countLabel.BackgroundTransparency = 1
			countLabel.Font = Enum.Font.BuilderSansExtraBold
			countLabel.TextScaled = true
			countLabel.Text = ""
			countLabel.Parent = gateGui
			gateLabels[id] = countLabel
		end
	end

	holoSurface(surface, board)
	for _, countLabel in gateLabels do
		holoSurface(countLabel.Parent, countLabel.Parent.Adornee)
	end

	local function update()
		local ok, counts = pcall(HttpService.JSONDecode, HttpService, ReplicatedStorage:GetAttribute("ModeCounts") or "{}")
		counts = ok and type(counts) == "table" and counts or {}
		if list then
			local lines = {}
			for _, mode in Modes.List do
				if mode.Available and Modes.Joinable(mode.Id) then
					local n = counts[mode.Id] or 0
					local color = n > 0 and "#70B270" or "#5E656E"
					table.insert(lines, mode.Name .. '   <font color="' .. color .. '">' .. n .. " Spieler</font>")
				end
			end
			list.Text = table.concat(lines, "\n")
		end
		local now = workspace:GetServerTimeNow()
		for i, label in values do
			local text, color = STATUS_LINES[i][2](counts, now)
			label.Text = text
			label.TextColor3 = color
		end
		-- Spielerzahl unter jedem Tor-Schild
		for id, countLabel in gateLabels do
			local n = counts[id] or 0
			countLabel.Text = n > 0 and (n .. " SPIELER") or "FREI"
			countLabel.TextColor3 = n > 0 and GREEN or GREY
		end
	end
	update()
	ReplicatedStorage:GetAttributeChangedSignal("ModeCounts"):Connect(update)
	if not list then
		-- Ereignisse beginnen und enden sofort, die Minuten zählen nebenher herunter
		for _, name in { "BloodMoonStart", "BloodMoonEnd", "StormStart", "StormEnd", "StormKills", "StormGoal" } do
			ReplicatedStorage:GetAttributeChangedSignal(name):Connect(update)
		end
		task.spawn(function()
			while surface.Parent do
				task.wait(15)
				update()
			end
		end)
	end
end

-- Bestenlisten-Tafeln an der Ruhmeswand im Camp (Parts "Leaderboard_<Name>", Daten vom LeaderboardService)
local BOARD_INFO = {
	Zombies = { Title = "MEISTE ZOMBIES", Color = Color3.fromRGB(212, 170, 80) },
	Kills = { Title = "MEISTE KILLS", Color = Color3.fromRGB(206, 70, 58) },
	Level = { Title = "HÖCHSTES LEVEL", Color = Color3.fromRGB(96, 164, 214) },
	Missions = { Title = "MEISTE AUFTRÄGE", Color = Color3.fromRGB(112, 178, 112) },
}
local PLACE_COLORS = { Color3.fromRGB(212, 176, 96), Color3.fromRGB(190, 194, 200), Color3.fromRGB(176, 120, 76) }

local function formatValue(board, value)
	value = tonumber(value) or 0
	if board == "Level" then
		local prestige, level = value // 1000, value % 1000
		return (prestige > 0 and ("P" .. prestige .. " · ") or "") .. "LV " .. level, nil
	end
	local text = tostring(math.floor(value))
	return text:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", ""), nil
end

local function buildLeaderboards()
	local decor = Zentrale.Folder(60)
	if not decor then
		return
	end
	for board, info in BOARD_INFO do
		local part = decor:WaitForChild("Leaderboard_" .. board, 60)
		if part then
			-- Holo-Tafel (Attribut "Holo"): durchsichtig, leuchtende Schrift, kaum Hintergrund
			local holo = part:GetAttribute("Holo") == true
			local surface = Instance.new("SurfaceGui")
			surface.ResetOnSpawn = false -- liegt im PlayerGui: sonst beim nächsten Spawn gelöscht
			surface.Face = Enum.NormalId.Front
			surface.LightInfluence = 0
			surface.Brightness = holo and 1.3 or 1
			surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 40
			surface.Adornee = part
			surface.Parent = player:WaitForChild("PlayerGui")
			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, 0, 0.13, 0)
			title.BackgroundColor3 = info.Color
			title.BackgroundTransparency = holo and 0.7 or 0.15
			title.BorderSizePixel = 0
			title.Font = Enum.Font.BuilderSansExtraBold
			title.TextScaled = true
			title.TextColor3 = holo and Color3.new(1, 1, 1) or Color3.fromRGB(14, 16, 19)
			title.TextStrokeTransparency = holo and 0.6 or 1
			title.Text = info.Title
			title.Parent = surface
			local rows = {}
			for i = 1, 10 do
				local row = Instance.new("Frame")
				row.Position = UDim2.new(0.03, 0, 0.15 + (i - 1) * 0.084, 0)
				row.Size = UDim2.new(0.94, 0, 0.076, 0)
				row.BackgroundColor3 = holo and Color3.fromRGB(60, 130, 170) or Color3.fromRGB(27, 31, 36)
				row.BackgroundTransparency = holo and (i % 2 == 0 and 0.82 or 0.94) or (i % 2 == 0 and 0.4 or 0.75)
				row.BorderSizePixel = 0
				row.Parent = surface
				local function cell(x, w, align, font)
					local label = Instance.new("TextLabel")
					label.Position = UDim2.new(x, 0, 0.08, 0)
					label.Size = UDim2.new(w, 0, 0.84, 0)
					label.BackgroundTransparency = 1
					label.Font = font
					label.TextScaled = true
					label.TextColor3 = holo and Color3.fromRGB(200, 235, 255) or Color3.fromRGB(228, 231, 235)
					label.TextStrokeTransparency = holo and 0.7 or 1
					label.TextXAlignment = align
					label.Text = ""
					label.Parent = row
					return label
				end
				rows[i] = {
					Frame = row,
					Place = cell(0.01, 0.1, Enum.TextXAlignment.Center, Enum.Font.BuilderSansExtraBold),
					Name = cell(0.13, 0.5, Enum.TextXAlignment.Left, Enum.Font.BuilderSansBold),
					Value = cell(0.6, 0.38, Enum.TextXAlignment.Right, Enum.Font.BuilderSansExtraBold),
				}
			end
			local function update()
				local ok, list = pcall(HttpService.JSONDecode, HttpService,
					ReplicatedStorage:GetAttribute("Leaderboard_" .. board) or "[]")
				list = ok and type(list) == "table" and list or {}
				for i, row in rows do
					local entry = list[i]
					row.Place.Text = entry and ("#" .. i) or ""
					row.Place.TextColor3 = PLACE_COLORS[i] or Color3.fromRGB(134, 142, 152)
					row.Name.Text = entry and tostring(entry.Name) or (i == 1 and "Noch keine Einträge" or "")
					local isMe = entry and entry.UserId == player.UserId
					row.Name.TextColor3 = isMe and Color3.fromRGB(212, 170, 80)
						or (holo and Color3.fromRGB(200, 235, 255) or Color3.fromRGB(228, 231, 235))
					row.Frame.BackgroundColor3 = isMe and Color3.fromRGB(46, 42, 30)
						or (holo and Color3.fromRGB(60, 130, 170) or Color3.fromRGB(27, 31, 36))
					if entry then
						local text, color = formatValue(board, entry.Value)
						row.Value.Text = text
						row.Value.TextColor3 = color or info.Color
					else
						row.Value.Text = ""
					end
				end
			end
			update()
			ReplicatedStorage:GetAttributeChangedSignal("Leaderboard_" .. board):Connect(update)
		end
	end
end

-- Leuchtpartikel an den Toren (in Torfarbe) und Funkeln über dem Siegertreppchen
local function addParticles()
	local decor = Zentrale.Folder(60)
	if not decor then
		return
	end
	task.wait(1)
	for _, part in decor:GetChildren() do
		if part:IsA("BasePart") and (part.Name == "GateGlow" or part.Name == "PodiumGlow") then
			local emitter = Instance.new("ParticleEmitter")
			local podium = part.Name == "PodiumGlow"
			emitter.Color = ColorSequence.new(podium and Color3.fromRGB(255, 225, 140) or part.Color)
			emitter.LightEmission = 1
			emitter.Rate = podium and 10 or 8
			emitter.Lifetime = NumberRange.new(2, 3.5)
			emitter.Speed = NumberRange.new(2, 4)
			emitter.SpreadAngle = Vector2.new(15, 15)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, podium and 0.35 or 0.5),
				NumberSequenceKeypoint.new(1, 0) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			-- Die Podest-Scheibe ist um 90° gekippt: ihre lokale X-Achse zeigt nach oben
			emitter.EmissionDirection = podium and Enum.NormalId.Right or Enum.NormalId.Top
			emitter.LockedToPart = false
			emitter.Parent = part
		end
	end
end

-- Im Markt die Belichtung absenken (Hallen mit vielen Lichtern), in den Modi wieder normal
local HUB_EXPOSURE = 0.1
local normalExposure = nil
local function updateExposure()
	local lighting = game:GetService("Lighting")
	normalExposure = normalExposure or lighting.ExposureCompensation
	lighting.ExposureCompensation = Modes.IsSocial(player:GetAttribute("Mode")) and HUB_EXPOSURE or normalExposure
end

function HubLineup.Init()
	updateExposure()
	player:GetAttributeChangedSignal("Mode"):Connect(updateExposure)
	task.spawn(buildMissionBoard)
	task.spawn(addParticles)
	task.spawn(buildLeaderboards)
	task.spawn(buildShopVitrine)
end

return HubLineup

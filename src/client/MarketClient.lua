-- MarketClient (ModuleScript, nur Client)
-- Markthalle (Modus "Market"; Server: MarketService):
--   * Stände in der Welt: Schild über jedem Stand (FREI bzw. Besitzer und Zahl der Angebote); die angebotenen
--     Skins drehen sich auf Theke und Regal, darüber ein Preisschild (Name in Seltenheitsfarbe, Preis in RAP).
--   * E am Stand: freien Stand beanspruchen, den eigenen verwalten, bei anderen ansehen und kaufen.
--   * Leiste oben: MARKT, eigenes RAP, eigener Stand (MEIN STAND, ABGEBEN) und die Meldungen vom Server.
--   * Fenster MEIN STAND: links die sechs Plätze (Preis ändern, zurücknehmen), rechts die eigenen handelbaren
--     Skins mit Preisfeld (Vorschlag: RAP-Wert) und ANBIETEN.
--   * Fenster STAND: Angebote eines anderen Stands mit Preis, RAP-Wert und Preisverlauf, KAUFEN (zweimal klicken),
--     Gegenangebot machen, Skin merken.
--   * Fenster SUCHE (Knopf oben oder E am Such-Terminal auf dem Marktplatz): alle Angebote aller Stände durchsuchen
--     (MarketSearch), nach Seltenheit, Art, Preis und Merkliste filtern, sortieren; HIN zeigt den Weg zum Stand.
--   * Fenster GEGENANGEBOTE (Knopf oben, nur mit eigenem Stand): Gebote annehmen oder ablehnen.
--   * Stand-Name im Fenster MEIN STAND; Tafeln in der Halle: Übersicht der freien Stände, beliebteste Händler.
-- Verlässt man den Markt, verliert man den Stand (Server); die Skins sind dann sofort wieder frei.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UITheme = require(Shared.UITheme)
local Cosmetics = require(Shared.Cosmetics)
local RapConfig = require(Shared.RapConfig)
local Modes = require(Shared.Modes)
local GunModels = require(Shared.GunModels)
local AgentFigure = require(Shared.AgentFigure)
local AgentConfig = require(Shared.AgentConfig)
local ItemPreview = require(Shared.ItemPreview)
local MarketSearch = require(Shared.MarketSearch)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label, upper = UITheme.Make, UITheme.Label, UITheme.Upper
local format = UITheme.FormatNumber

local MarketClient = {}

local WIN_W, WIN_H = 1040, 620

local marketMap     -- Maps.Market (PriceStats, TopSellers, Tafeln, Such-Terminal)
local refreshBoards   -- Tafeln neu beschriften (weiter unten definiert)
local stands = {}   -- [Nummer] = { Id, Folder, Sign, Prompt, Displays = { [Platz] = {...} }, Shown }
local displayFolder -- Modelle der angebotenen Skins (nur solange man im Markt ist)
local gui, root, toast, barStatus, barRap, manageButton, releaseButton, offersButton
local window = nil  -- offenes Fenster { Frame, Kind = "Manage" | "Stand", Stand, Refresh, Pending }

local function inMarket()
	return player:GetAttribute("Mode") == Modes.Market.Id
end

local function decode(raw)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "")
	return ok and type(data) == "table" and data or {}
end

local function listingsOf(stand)
	return decode(stand.Folder:GetAttribute("Listings"))
end

local function ownerOf(stand)
	return tonumber(stand.Folder:GetAttribute("Owner")) or 0
end

local function myStand()
	for _, stand in stands do
		if ownerOf(stand) == player.UserId then
			return stand
		end
	end
	return nil
end

-- Preisverlauf (Server: PriceStats an der Map): { [Skin] = { Avg, N, Last } } der letzten Tage
local function priceStats()
	return decode(marketMap and marketMap:GetAttribute("PriceStats"))
end

local function averageOf(itemId)
	local entry = priceStats()[itemId]
	return entry and entry.Avg or nil
end

local function historyLine(itemId)
	local entry = priceStats()[itemId]
	if not entry then
		return nil
	end
	return "Ø " .. format(entry.Avg) .. " RAP  ·  " .. entry.N .. (entry.N == 1 and " VERKAUF" or " VERKÄUFE")
		.. " (" .. RapConfig.HistoryDays .. " T)"
end

-- Merkliste des Spielers (Server: Attribut MarketWatch): { [Skin] = true }
local function watchSet()
	local set = {}
	for _, id in decode(player:GetAttribute("MarketWatch")) do
		set[id] = true
	end
	return set
end

local function feeText()
	local parts = {}
	for _, tier in RapConfig.FeeTiers do
		local rate = math.floor(tier.Rate * 100 + 0.5) .. " %"
		if tier.Upto == math.huge then
			table.insert(parts, rate .. " darüber")
		else
			table.insert(parts, rate .. " bis " .. format(tier.Upto) .. " RAP")
		end
	end
	return "Marktgebühr: " .. table.concat(parts, "  ·  ") .. "."
end

local function sound(id, speed, volume)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 2)
end

-- Freie (nicht zurückgelegte) Stücke der eigenen handelbaren Skins: { { Item, Count, Free } }, teuerste zuerst
local function myTradeables()
	local owned = Cosmetics.GetOwned(player)
	local held = decode(player:GetAttribute("Reserved"))
	local list = {}
	for id in owned do
		local item = Cosmetics.Get(id)
		local count = RapConfig.Count(owned, id)
		if item and RapConfig.Tradeable(id) and count > 0 then
			table.insert(list, { Item = item, Count = count, Free = count - (tonumber(held[id]) or 0) })
		end
	end
	table.sort(list, function(a, b)
		return RapConfig.Value(a.Item.Id) > RapConfig.Value(b.Item.Id)
	end)
	return list
end

-- Zahlenfeld (nur Ziffern, höchstens 8)
local function numberBox(props, parent)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Background
	props.TextColor3 = props.TextColor3 or C.Text
	props.PlaceholderColor3 = C.Muted
	props.Font = props.Font or F.Bold
	props.TextSize = props.TextSize or 15
	props.ClearTextOnFocus = false
	props.TextXAlignment = Enum.TextXAlignment.Center
	local box = make("TextBox", props, parent)
	UITheme.Corner(box, UITheme.Radius.Small)
	UITheme.Stroke(box, C.Rap, 1, 0.5)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local digits = string.sub((string.gsub(box.Text, "%D", "")), 1, 8)
		if digits ~= box.Text then
			box.Text = digits
		end
	end)
	return box
end

local function rapLine(parent, props, amount, size)
	local row = make("Frame", { Name = "RapLine", Size = UDim2.fromOffset(0, size + 6), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1, Position = props.Position, AnchorPoint = props.AnchorPoint, LayoutOrder = props.LayoutOrder }, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	UITheme.RapIcon(row, size - 2, { LayoutOrder = 1 })
	local text = label({ Size = UDim2.fromOffset(0, size + 4), AutomaticSize = Enum.AutomaticSize.X, Text = format(amount) .. " RAP",
		TextSize = size, Font = props.Font or F.Display, TextColor3 = props.Color or C.Rap, LayoutOrder = 2 }, row)
	return row, text
end

-- Knopf MERKEN / GEMERKT für einen Skin (Merkliste: Meldung, sobald jemand ihn anbietet)
local function watchChip(parent, itemId, position)
	local watching = watchSet()[itemId] == true
	return UITheme.Chunky({ Position = position, Size = UDim2.fromOffset(88, 24), Color = watching and C.Primary or C.Card,
		StrokeColor = watching and C.Primary or C.Border, Text = watching and "GEMERKT" or "MERKEN", TextSize = 11, Font = F.Bold,
		TextColor = watching and C.PrimaryText or C.Muted, ZIndex = 5 }, parent, function()
		Remotes.MarketAction:FireServer(watching and "Unwatch" or "Watch", itemId)
	end)
end

-- ---------- Meldungen ----------

local toastUntil = 0
local function showToast(message, success)
	if not toast then
		return
	end
	toast.Text = tostring(message)
	toast.TextColor3 = success == false and C.Bad or (success and C.Good or C.Text)
	toast.Visible = true
	toastUntil = os.clock() + 4
	task.delay(4.05, function()
		if os.clock() >= toastUntil then
			toast.Visible = false
		end
	end)
end

-- ---------- Stände in der Welt ----------

local function buildSign(stand)
	local part = stand.Folder:FindFirstChild("Sign")
	if not part then
		return
	end
	local surface = Instance.new("SurfaceGui")
	surface.Name = "StandSign" .. stand.Id
	surface.ResetOnSpawn = false -- liegt im PlayerGui: sonst beim nächsten Spawn gelöscht
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 50
	surface.LightInfluence = 0
	surface.Brightness = 1.5
	surface.Adornee = part
	surface.Parent = player:WaitForChild("PlayerGui")
	local function line(name, props)
		props.Name = name
		props.BackgroundTransparency = 1
		props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
		props.TextStrokeTransparency = 0.55
		props.TextStrokeColor3 = Color3.fromRGB(10, 14, 20)
		return make("TextLabel", props, surface)
	end
	stand.Sign = {
		Number = line("Number", { Position = UDim2.fromScale(0.03, 0.06), Size = UDim2.fromScale(0.3, 0.26),
			Text = "STAND " .. stand.Id, TextScaled = true, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(200, 208, 220) }),
		Info = line("Info", { Position = UDim2.fromScale(0.67, 0.06), Size = UDim2.fromScale(0.3, 0.26), Text = "",
			TextScaled = true, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Right }),
		Main = line("Main", { Position = UDim2.fromScale(0.04, 0.34), Size = UDim2.fromScale(0.92, 0.6), Text = "",
			TextScaled = true, Font = F.Display }),
	}
end

local function clearDisplays(stand)
	for _, display in stand.Displays do
		display.Model:Destroy()
		display.Tag:Destroy()
	end
	stand.Displays = {}
	stand.Shown = nil
end

local function buildDisplay(stand, listing)
	local spot = stand.Folder:FindFirstChild("Display" .. tostring(listing.Slot))
	local item = Cosmetics.Get(listing.Item)
	if not spot or not item then
		return
	end
	local model
	if item.Type == "Weapon" then
		model = GunModels.Build(item.Weapon or "Rifle", item)
		model:ScaleTo(0.55)
	else
		local agent = AgentConfig.Get(item.Agent) or AgentConfig.Agents[1]
		model = AgentFigure.Build(agent, item.Primary, item.Accent)
		model:ScaleTo(0.42)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	model.Parent = displayFolder
	local box, size = model:GetBoundingBox()
	-- Preisschild über dem Skin
	local rarity = Cosmetics.Rarities[item.Rarity]
	local tag = Instance.new("BillboardGui")
	tag.Name = "PriceTag"
	tag.ResetOnSpawn = false
	tag.Size = UDim2.fromOffset(150, 44)
	tag.StudsOffset = Vector3.new(0, item.Type == "Agent" and 1.9 or 1.15, 0)
	tag.MaxDistance = 45
	tag.LightInfluence = 0
	tag.Adornee = spot
	tag.Parent = player:WaitForChild("PlayerGui")
	local plate = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background, BackgroundTransparency = 0.25 }, tag)
	UITheme.Corner(plate, UITheme.Radius.Small)
	UITheme.Stroke(plate, rarity and rarity.Color or C.Border, 1, 0.3)
	label({ Position = UDim2.fromOffset(6, 2), Size = UDim2.new(1, -12, 0, 18), Text = upper(item.Name), TextSize = 13,
		Font = F.Bold, TextColor3 = rarity and rarity.Color or C.Text, TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd }, plate)
	local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, plate)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
	UITheme.RapIcon(holder, 14, { LayoutOrder = 1 })
	label({ Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Text = format(listing.Price) .. " RAP",
		TextSize = 18, Font = F.Display, TextColor3 = C.Rap, LayoutOrder = 2 }, holder)
	stand.Displays[listing.Slot] = { Model = model, Tag = tag, Spot = spot, Agent = item.Type == "Agent",
		Offset = model:GetPivot():ToObjectSpace(box), Height = size.Y, Phase = listing.Slot * 1.3 + stand.Id }
end

-- Schild, Prompt und (im Markt) die ausgestellten Skins eines Stands an seine Attribute anpassen
local function refreshStand(stand)
	local owner = ownerOf(stand)
	local listings = listingsOf(stand)
	local mine = myStand()
	if stand.Sign then
		if owner == 0 then
			stand.Sign.Main.Text = "FREI"
			stand.Sign.Main.TextColor3 = C.Rap
			stand.Sign.Info.Text = "E: BEANSPRUCHEN"
			stand.Sign.Info.TextColor3 = C.Rap
		else
			local standName = tostring(stand.Folder:GetAttribute("StandName") or "")
			stand.Sign.Main.Text = upper(standName ~= "" and standName or tostring(stand.Folder:GetAttribute("OwnerName") or "?"))
			stand.Sign.Main.TextColor3 = owner == player.UserId and C.Primary or Color3.new(1, 1, 1)
			stand.Sign.Info.Text = #listings .. (#listings == 1 and " ANGEBOT" or " ANGEBOTE")
			stand.Sign.Info.TextColor3 = #listings > 0 and C.Rap or Color3.fromRGB(170, 178, 190)
		end
	end
	if stand.Prompt then
		local prompt = stand.Prompt
		if owner == 0 then
			prompt.ActionText = mine and "Du hast schon Stand " .. mine.Id or "Stand beanspruchen"
			prompt.ObjectText = "Stand " .. stand.Id .. " · frei"
			prompt.Enabled = mine == nil and inMarket()
		elseif owner == player.UserId then
			prompt.ActionText = "Stand verwalten"
			prompt.ObjectText = "Dein Stand"
			prompt.Enabled = inMarket()
		else
			prompt.ActionText = "Stand ansehen"
			prompt.ObjectText = tostring(stand.Folder:GetAttribute("OwnerName") or "") .. " · " .. #listings .. " Angebote"
			prompt.Enabled = inMarket()
		end
	end
	-- Ausgestellte Skins nur im Markt (sonst unnötige Teile)
	local key = inMarket() and (stand.Folder:GetAttribute("Listings") or "") or ""
	if key ~= stand.Shown then
		clearDisplays(stand)
		stand.Shown = key
		if inMarket() then
			for _, listing in listings do
				buildDisplay(stand, listing)
			end
		end
	end
end

local function refreshAllStands()
	for _, stand in stands do
		refreshStand(stand)
	end
	if refreshBoards then
		refreshBoards()
	end
end

-- ---------- Fenster ----------

local function closeWindow()
	if window then
		window.Frame:Destroy()
		window = nil
		UITheme.SetBlur("Market", false)
	end
end

local function newWindow(kind, title, stand)
	closeWindow()
	local frame = UITheme.Card({ Name = "MarketWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(WIN_W, WIN_H), BackgroundTransparency = 0.04, ZIndex = 5 }, root)
	make("Frame", { Name = "Accent", Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = C.Rap, BorderSizePixel = 0, ZIndex = 5 }, frame)
	label({ Position = UDim2.fromOffset(28, 18), Size = UDim2.new(1, -300, 0, 40), Text = title, TextSize = 34, Font = F.Display,
		ZIndex = 5 }, frame)
	local close = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.fromOffset(44, 44),
		Color = C.Card, StrokeColor = C.Border, Text = "", ZIndex = 5 }, frame, closeWindow)
	UITheme.Cross(close.Face, 14, C.Text, 2).ZIndex = 5
	local rapHolder, rapText = rapLine(frame, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -76, 0, 26) },
		player:GetAttribute("Rap") or 0, 22)
	rapHolder.ZIndex = 5
	local body = make("Frame", { Name = "Body", Position = UDim2.fromOffset(28, 74), Size = UDim2.new(1, -56, 1, -100),
		BackgroundTransparency = 1, ZIndex = 5 }, frame)
	window = { Frame = frame, Body = body, Kind = kind, Stand = stand, RapText = rapText }
	UITheme.SetBlur("Market", true)
	return window
end

-- Inhalt neu bauen – aber nicht, solange man gerade in ein Preisfeld tippt (danach)
local function refreshWindow()
	if not window or not window.Refresh then
		return
	end
	window.RapText.Text = format(player:GetAttribute("Rap") or 0) .. " RAP"
	local focused = UserInputService:GetFocusedTextBox()
	if focused and focused:IsDescendantOf(window.Frame) and not window.Live then
		window.Pending = true
		return
	end
	window.Pending = false
	window.Refresh()
end

-- Karte für einen Skin (Vorschau links oben, Name, Seltenheit); textWidth = Breite der Texte rechts der Vorschau
-- (schmal: nur die Seltenheit in der Unterzeile). Gibt die Karte zurück.
local function itemCard(parent, item, size, order, textWidth)
	local rarity = Cosmetics.Rarities[item.Rarity]
	local card = make("Frame", { Size = size, BackgroundColor3 = C.Card, BackgroundTransparency = 0.05, LayoutOrder = order or 0,
		ZIndex = 5 }, parent)
	UITheme.Corner(card, UITheme.Radius.Large)
	UITheme.Stroke(card, rarity and rarity.Color or C.Border, 1, 0.55)
	make("Frame", { Size = UDim2.new(0, 3, 1, -16), Position = UDim2.fromOffset(0, 8), BackgroundColor3 = rarity and rarity.Color or C.Border,
		BorderSizePixel = 0, ZIndex = 5 }, card)
	local view = ItemPreview.New(card, { Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(104, 74), ZIndex = 5 })
	ItemPreview.Show(view, item, 104 / 74)
	local width = textWidth and UDim2.fromOffset(textWidth, 0) or UDim2.new(1, -134, 0, 0)
	label({ Position = UDim2.fromOffset(124, 10), Size = width + UDim2.fromOffset(0, 24), Text = upper(item.Name), TextSize = 21,
		Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, card)
	local kind = item.Type == "Agent" and ("  ·  " .. (AgentConfig.Get(item.Agent) or { Name = "" }).Name) or "  ·  WAFFEN-SKIN"
	label({ Position = UDim2.fromOffset(124, 36), Size = width + UDim2.fromOffset(0, 14), Text = upper(rarity and rarity.Name or "")
		.. (textWidth and "" or kind), TextSize = 11, Font = F.Bold, TextColor3 = rarity and rarity.Color or C.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, card)
	return card
end

-- MEIN STAND: links die Plätze, rechts die eigenen Skins
local function openManage()
	local stand = myStand()
	if not stand then
		showToast("Du hast keinen Stand. Geh zu einem freien Stand und drücke E.", false)
		return
	end
	local win = newWindow("Manage", "MEIN STAND  ·  STAND " .. stand.Id, stand)
	local body = win.Body
	function win.Refresh()
		for _, child in body:GetChildren() do
			child:Destroy()
		end
		local current = myStand()
		if not current then
			closeWindow()
			return
		end
		local listings = listingsOf(current)
		-- links: Angebote
		local left = make("Frame", { Size = UDim2.new(0, 480, 1, 0), BackgroundTransparency = 1, ZIndex = 5 }, body)
		label({ Size = UDim2.new(1, 0, 0, 20), Text = "ANGEBOTE  " .. #listings .. " / " .. RapConfig.StandSlots, TextSize = 13,
			Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, left)
		local grid = make("Frame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -112), BackgroundTransparency = 1,
			ZIndex = 5 }, left)
		make("UIGridLayout", { CellSize = UDim2.fromOffset(236, 146), CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		local bySlot = {}
		for _, listing in listings do
			bySlot[listing.Slot] = listing
		end
		for slot = 1, RapConfig.StandSlots do
			local listing = bySlot[slot]
			local item = listing and Cosmetics.Get(listing.Item)
			if item then
				local card = itemCard(grid, item, UDim2.fromOffset(236, 146), slot, 104)
				local average = averageOf(item.Id)
				label({ Position = UDim2.fromOffset(124, 54), Size = UDim2.new(1, -134, 0, 14), Text = "WERT " .. format(RapConfig.Value(item.Id) or 0)
					.. (average and ("  ·  Ø " .. format(average)) or ""), TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, card)
				local price = numberBox({ Position = UDim2.fromOffset(10, 92), Size = UDim2.fromOffset(104, 40), Text = tostring(listing.Price),
					PlaceholderText = "PREIS", ZIndex = 5 }, card)
				UITheme.Chunky({ Position = UDim2.fromOffset(122, 92), Size = UDim2.fromOffset(52, 40), Color = C.Rap, Text = "OK",
					TextSize = 15, TextColor = C.PrimaryText, ZIndex = 5 }, card, function()
					Remotes.MarketAction:FireServer("SetPrice", slot, tonumber(price.Text))
				end)
				price.FocusLost:Connect(function(enter)
					if enter then
						Remotes.MarketAction:FireServer("SetPrice", slot, tonumber(price.Text))
					end
					if window and window.Pending then
						task.defer(refreshWindow)
					end
				end)
				UITheme.Chunky({ Position = UDim2.fromOffset(180, 92), Size = UDim2.fromOffset(46, 40), Color = C.Card, StrokeColor = C.Bad,
					Text = "ZURÜCK", TextSize = 11, Font = F.Bold, TextColor = C.Bad, ZIndex = 5 }, card, function()
					Remotes.MarketAction:FireServer("Unlist", slot)
				end)
			else
				local empty = make("Frame", { BackgroundColor3 = C.Background, BackgroundTransparency = 0.4, LayoutOrder = slot,
					ZIndex = 5 }, grid)
				UITheme.Corner(empty, UITheme.Radius.Large)
				UITheme.Stroke(empty, C.Border, 1, 0.5)
				label({ Size = UDim2.fromScale(1, 1), Text = "FREIER PLATZ " .. slot, TextSize = 13, Font = F.Bold, TextColor3 = C.Muted,
					TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, empty)
			end
		end
		-- Stand-Name (alle sehen ihn auf dem Schild; läuft durch den Textfilter)
		local nameRow = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -48), Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1, ZIndex = 5 }, left)
		label({ Size = UDim2.fromOffset(92, 34), Text = "STAND-NAME", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, nameRow)
		local nameBox = make("TextBox", { Position = UDim2.fromOffset(96, 0), Size = UDim2.fromOffset(290, 34), BackgroundColor3 = C.Background,
			TextColor3 = C.Text, PlaceholderText = "z.B. LAVA-LADEN", PlaceholderColor3 = C.Muted,
			Text = tostring(current.Folder:GetAttribute("StandName") or ""), Font = F.Bold, TextSize = 15, ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 }, nameRow)
		UITheme.Corner(nameBox, UITheme.Radius.Small)
		UITheme.Stroke(nameBox, C.Rap, 1, 0.5)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, nameBox)
		nameBox.FocusLost:Connect(function(enter)
			if enter then
				Remotes.MarketAction:FireServer("Name", nameBox.Text)
			end
			if window and window.Pending then
				task.defer(refreshWindow)
			end
		end)
		UITheme.Chunky({ Position = UDim2.fromOffset(394, 0), Size = UDim2.fromOffset(60, 34), Color = C.Rap, Text = "OK", TextSize = 15,
			TextColor = C.PrimaryText, ZIndex = 5 }, nameRow, function()
			Remotes.MarketAction:FireServer("Name", nameBox.Text)
		end)
		label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 44), TextWrapped = true,
			Text = feeText() .. " Verlässt du den Markt, ist dein Stand weg – deine Skins sind dann wieder frei.",
			TextSize = 11, Font = F.Medium, TextColor3 = C.Muted, ZIndex = 5 }, left)

		-- rechts: eigene Skins zum Anbieten
		local right = make("Frame", { Position = UDim2.fromOffset(500, 0), Size = UDim2.new(1, -500, 1, 0), BackgroundTransparency = 1,
			ZIndex = 5 }, body)
		label({ Size = UDim2.new(1, 0, 0, 20), Text = "DEINE HANDELBAREN SKINS", TextSize = 13, Font = F.Bold, TextColor3 = C.Muted,
			ZIndex = 5 }, right)
		local scroll = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -76), BackgroundTransparency = 1,
			BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Border, CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 5 }, right)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
		local any = false
		for order, entry in myTradeables() do
			if entry.Free > 0 then
				any = true
				local item = entry.Item
				local card = itemCard(scroll, item, UDim2.new(1, -10, 0, 90), order, 112)
				local average = averageOf(item.Id)
				label({ Position = UDim2.fromOffset(124, 56), Size = UDim2.new(0, 200, 0, 14), Text = entry.Free .. " FREI  ·  WERT "
					.. format(RapConfig.Value(item.Id)) .. (average and ("  ·  Ø " .. format(average)) or ""), TextSize = 11, Font = F.Bold,
					TextColor3 = C.Muted, ZIndex = 5 }, card)
				local price = numberBox({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -132, 0.5, 0), Size = UDim2.fromOffset(96, 40),
					Text = tostring(RapConfig.Value(item.Id)), PlaceholderText = "PREIS", ZIndex = 5 }, card)
				price.FocusLost:Connect(function()
					if window and window.Pending then
						task.defer(refreshWindow)
					end
				end)
				UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(112, 40),
					Color = C.Rap, Text = "ANBIETEN", TextSize = 16, TextColor = C.PrimaryText, ZIndex = 5 }, card, function()
					Remotes.MarketAction:FireServer("List", item.Id, tonumber(price.Text))
				end)
			end
		end
		if not any then
			label({ Size = UDim2.new(1, -10, 0, 80), TextWrapped = true, Text = "Keine freien handelbaren Skins. Seltene Skins gibt es im Shop, "
				.. "am Glücksrad, im Login-Kalender, im Battle Pass oder hier an anderen Ständen.", TextSize = 14, Font = F.Medium,
				TextColor3 = C.Muted, ZIndex = 5 }, scroll)
		end
		UITheme.Chunky({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(180, 40), Color = C.Card,
			StrokeColor = C.Bad, Text = "STAND ABGEBEN", TextSize = 16, TextColor = C.Bad, ZIndex = 5 }, right, function()
			Remotes.MarketAction:FireServer("Release")
			closeWindow()
		end)
	end
	win.Refresh()
end

-- STAND eines anderen Spielers: Angebote kaufen (zweimal klicken), Gegenangebot machen, Skin merken
local function openStand(stand)
	local owner = tostring(stand.Folder:GetAttribute("OwnerName") or "")
	local standName = tostring(stand.Folder:GetAttribute("StandName") or "")
	local win = newWindow("Stand", "STAND " .. stand.Id .. "  ·  " .. upper(standName ~= "" and standName or owner), stand)
	local body = win.Body
	local confirm = {} -- [Platz] = os.clock() bis wann die Rückfrage gilt
	local drafts = {}  -- [Platz] = Text im Preisfeld des Gegenangebots (bleibt beim Neuaufbau)
	function win.Refresh()
		for _, child in body:GetChildren() do
			child:Destroy()
		end
		if ownerOf(stand) == 0 or ownerOf(stand) == player.UserId then
			closeWindow()
			showToast("Dieser Stand wurde gerade abgegeben.", false)
			return
		end
		local listings = listingsOf(stand)
		local offers = decode(stand.Folder:GetAttribute("Offers"))
		local scroll = make("ScrollingFrame", { Size = UDim2.new(1, 0, 1, -30), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 5, ScrollBarImageColor3 = C.Border, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ZIndex = 5 }, body)
		make("UIGridLayout", { CellSize = UDim2.fromOffset(310, 300), CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
		local rap = player:GetAttribute("Rap") or 0
		for _, listing in listings do
			local item = Cosmetics.Get(listing.Item)
			if item then
				local card = itemCard(scroll, item, UDim2.fromOffset(310, 300), listing.Slot)
				local value = RapConfig.Value(item.Id) or 0
				label({ Position = UDim2.fromOffset(124, 56), Size = UDim2.new(1, -134, 0, 14), Text = "RAP-WERT " .. format(value),
					TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, card)
				watchChip(card, item.Id, UDim2.new(1, -98, 0, 10))
				-- Preis groß, darunter wie er zum Wert steht und was der Skin zuletzt gekostet hat
				local priceRow = rapLine(card, { Position = UDim2.fromOffset(16, 92) }, listing.Price, 30)
				priceRow.ZIndex = 5
				local diff = value > 0 and math.floor((listing.Price / value - 1) * 100 + 0.5) or 0
				label({ Position = UDim2.fromOffset(16, 130), Size = UDim2.new(1, -32, 0, 16), TextSize = 12, Font = F.Bold, ZIndex = 5,
					Text = diff == 0 and "GENAU DER RAP-WERT" or (math.abs(diff) .. " % " .. (diff > 0 and "ÜBER" or "UNTER") .. " DEM RAP-WERT"),
					TextColor3 = diff > 0 and C.Primary or C.Good }, card)
				label({ Position = UDim2.fromOffset(16, 148), Size = UDim2.new(1, -32, 0, 16), TextSize = 11, Font = F.Bold, ZIndex = 5,
					Text = historyLine(item.Id) or "NOCH KEIN PREISVERLAUF", TextColor3 = C.Muted }, card)
				-- Gegenangebot (oder das eigene offene Angebot)
				local mine = nil
				for _, offer in offers do
					if offer.Slot == listing.Slot and offer.Buyer == player.UserId then
						mine = offer
					end
				end
				if mine then
					label({ Position = UDim2.fromOffset(16, 172), Size = UDim2.new(1, -150, 0, 36), TextSize = 12, Font = F.Bold, ZIndex = 5,
						TextWrapped = true, Text = "DEIN ANGEBOT: " .. format(mine.Price) .. " RAP – WARTET AUF ANTWORT", TextColor3 = C.Rap }, card)
					UITheme.Chunky({ Position = UDim2.new(1, -126, 0, 172), Size = UDim2.fromOffset(112, 36), Color = C.Card, StrokeColor = C.Bad,
						Text = "ZURÜCKZIEHEN", TextSize = 11, Font = F.Bold, TextColor = C.Bad, ZIndex = 5 }, card, function()
						Remotes.MarketAction:FireServer("CancelOffer", mine.Id)
					end)
				else
					local minimum = math.ceil(listing.Price * RapConfig.MinOfferFraction)
					local box = numberBox({ Position = UDim2.fromOffset(14, 172), Size = UDim2.fromOffset(112, 36),
						Text = drafts[listing.Slot] or tostring(math.max(minimum, math.floor(listing.Price * 0.85))),
						PlaceholderText = "DEIN PREIS", ZIndex = 5 }, card)
					box.FocusLost:Connect(function()
						drafts[listing.Slot] = box.Text
						if window and window.Pending then
							task.defer(refreshWindow)
						end
					end)
					UITheme.Chunky({ Position = UDim2.fromOffset(134, 172), Size = UDim2.new(1, -148, 0, 36), Color = C.Card, StrokeColor = C.Rap,
						Text = "ANGEBOT MACHEN", TextSize = 13, TextColor = C.Rap, ZIndex = 5 }, card, function()
						Remotes.MarketAction:FireServer("Offer", stand.Id, listing.Slot, tonumber(box.Text))
					end)
					label({ Position = UDim2.fromOffset(14, 210), Size = UDim2.new(1, -28, 0, 14), TextSize = 10, Font = F.Medium, ZIndex = 5,
						Text = "Gegenangebot ab " .. format(minimum) .. " RAP – der Besitzer hat " .. RapConfig.OfferSeconds .. " Sekunden.",
						TextColor3 = C.Muted }, card)
				end
				local affordable = rap >= listing.Price
				local buy
				buy = UITheme.Chunky({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -28, 0, 44),
					Color = affordable and C.Rap or C.MutedBack, TextColor = affordable and C.PrimaryText or C.Bad, TextSize = 18,
					Text = affordable and ("KAUFEN  ·  " .. format(listing.Price) .. " RAP") or "ZU WENIG RAP", ZIndex = 5 }, card, function()
					if not affordable then
						return
					end
					if os.clock() < (confirm[listing.Slot] or 0) then
						confirm[listing.Slot] = 0
						Remotes.MarketAction:FireServer("Buy", stand.Id, listing.Slot, listing.Price)
						return
					end
					confirm[listing.Slot] = os.clock() + 3
					buy.SetText("SICHER?  " .. format(listing.Price) .. " RAP")
					task.delay(3, function()
						if os.clock() >= (confirm[listing.Slot] or 0) and buy.Button.Parent then
							buy.SetText("KAUFEN  ·  " .. format(listing.Price) .. " RAP")
						end
					end)
				end)
			end
		end
		if #listings == 0 then
			label({ Size = UDim2.fromOffset(600, 60), Text = owner .. " hat gerade nichts im Angebot.", TextSize = 16, Font = F.Medium,
				TextColor3 = C.Muted, ZIndex = 5 }, scroll)
		end
		label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 20), ZIndex = 5,
			Text = "Bezahlt wird mit RAP. Mehr RAP: Skins im SHOP ans System verkaufen oder selbst einen Stand aufmachen.",
			TextSize = 12, Font = F.Medium, TextColor3 = C.Muted }, body)
	end
	win.Refresh()
end

-- ---------- Suche ----------

local searchState = MarketSearch.NewState()
local searchWatchOnly = false
local waypoint = nil -- { Stand, Gui, Distance }
local MAX_ROWS = 60

local function clearWaypoint()
	if waypoint then
		waypoint.Gui:Destroy()
		waypoint = nil
	end
end

-- Pfeil über dem Stand mit Entfernung (verschwindet, sobald man da ist oder den Markt verlässt)
local function setWaypoint(stand)
	clearWaypoint()
	local anchor = stand.Folder:FindFirstChild("Prompt")
	if not anchor then
		return
	end
	local guide = make("BillboardGui", { Name = "MarketWaypoint", Adornee = anchor, AlwaysOnTop = true, ResetOnSpawn = false,
		Size = UDim2.fromOffset(200, 70), StudsOffset = Vector3.new(0, 7, 0) }, player:WaitForChild("PlayerGui"))
	label({ Size = UDim2.new(1, 0, 0, 36), Text = "▼  STAND " .. stand.Id, TextSize = 28, Font = F.Display, TextColor3 = C.Rap,
		TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Center }, guide)
	local distance = label({ Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 24), Text = "", TextSize = 18,
		Font = F.Bold, TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Center }, guide)
	waypoint = { Stand = stand, Gui = guide, Distance = distance }
end

local function updateWaypoint()
	if not waypoint then
		return
	end
	local anchor = waypoint.Stand.Folder:FindFirstChild("Prompt")
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not inMarket() or not anchor or not rootPart then
		clearWaypoint()
		return
	end
	local meters = (rootPart.Position - anchor.Position).Magnitude
	if meters < 11 then
		clearWaypoint()
		showToast("Du bist am Stand – E zum Ansehen.", true)
		return
	end
	waypoint.Distance.Text = math.floor(meters + 0.5) .. " m"
end

-- Alle fremden Angebote: { { Stand, Owner, OwnerName, Slot, Item, Price } }
local function allListings()
	local entries = {}
	for _, stand in stands do
		local owner = ownerOf(stand)
		if owner ~= 0 and owner ~= player.UserId then
			local name = tostring(stand.Folder:GetAttribute("OwnerName") or "")
			for _, listing in listingsOf(stand) do
				table.insert(entries, { Stand = stand.Id, Owner = owner, OwnerName = name, Slot = listing.Slot, Item = listing.Item,
					Price = listing.Price })
			end
		end
	end
	return entries
end

local function searchChip(parent, text, x, y, width, active, onClick)
	return UITheme.Chunky({ Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, 32), Color = active and C.Rap or C.Card,
		StrokeColor = active and C.Rap or C.Border, Text = text, TextSize = 14, TextColor = active and C.PrimaryText or C.Text,
		ZIndex = 5 }, parent, onClick)
end

local function openSearch()
	local win = newWindow("Search", "SUCHE", nil)
	win.Live = true -- Ergebnisse dürfen sich beim Tippen neu aufbauen
	local body = win.Body
	local state = searchState

	local box = make("TextBox", { Name = "Query", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(330, 40),
		BackgroundColor3 = C.Background, TextColor3 = C.Text, PlaceholderText = "SKIN, SELTENHEIT, BESITZER …", PlaceholderColor3 = C.Muted,
		Text = state.Text, Font = F.Bold, TextSize = 16, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 }, body)
	UITheme.Corner(box, UITheme.Radius.Small)
	UITheme.Stroke(box, C.Rap, 1, 0.5)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, box)

	local controls = make("Frame", { Name = "Controls", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 90),
		BackgroundTransparency = 1, ZIndex = 5 }, body)
	local results = make("ScrollingFrame", { Name = "Results", Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 1, -126),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = C.Border,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 5 }, body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, results)
	local footer = label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 20), TextSize = 12,
		Font = F.Medium, TextColor3 = C.Muted, ZIndex = 5 }, body)

	local function fill()
		for _, child in results:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local entries = allListings()
		if searchWatchOnly then
			local watched = watchSet()
			local kept = {}
			for _, entry in entries do
				if watched[entry.Item] then
					table.insert(kept, entry)
				end
			end
			entries = kept
		end
		local found = MarketSearch.Run(entries, state)
		local rap = player:GetAttribute("Rap") or 0
		for index, entry in found do
			if index > MAX_ROWS then
				break
			end
			local item = entry.ItemData
			local rarity = Cosmetics.Rarities[item.Rarity]
			local rarityColor = rarity and rarity.Color or C.Border
			local row = make("Frame", { Size = UDim2.new(1, -12, 0, 68), BackgroundColor3 = C.Card, BackgroundTransparency = 0.05,
				LayoutOrder = index, ZIndex = 5 }, results)
			UITheme.Corner(row, UITheme.Radius.Large)
			UITheme.Stroke(row, rarityColor, 1, 0.6)
			make("Frame", { Size = UDim2.new(0, 4, 1, -16), Position = UDim2.fromOffset(0, 8), BackgroundColor3 = rarityColor,
				BorderSizePixel = 0, ZIndex = 5 }, row)
			label({ Position = UDim2.fromOffset(18, 8), Size = UDim2.fromOffset(300, 26), Text = upper(item.Name), TextSize = 21,
				Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, row)
			local kind = item.Type == "Agent" and ("AGENT  ·  " .. upper((AgentConfig.Get(item.Agent) or { Name = "" }).Name)) or "WAFFEN-SKIN"
			label({ Position = UDim2.fromOffset(18, 38), Size = UDim2.fromOffset(300, 20), Text = upper(rarity and rarity.Name or "")
				.. "  ·  " .. (historyLine(item.Id) or kind), TextSize = 11, Font = F.Bold, TextColor3 = rarityColor,
				TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, row)
			label({ Position = UDim2.fromOffset(330, 12), Size = UDim2.fromOffset(130, 20), Text = "STAND " .. entry.Stand,
				TextSize = 16, Font = F.Display, ZIndex = 5 }, row)
			label({ Position = UDim2.fromOffset(330, 36), Size = UDim2.fromOffset(130, 18), Text = upper(entry.OwnerName), TextSize = 12,
				Font = F.Bold, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, row)
			local percent = math.floor(entry.Diff * 100 + 0.5)
			local value = RapConfig.Value(item.Id) or 0
			label({ Position = UDim2.fromOffset(470, 12), Size = UDim2.fromOffset(150, 18), Text = "RAP-WERT " .. format(value), TextSize = 12,
				Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, row)
			label({ Position = UDim2.fromOffset(470, 36), Size = UDim2.fromOffset(150, 18), TextSize = 13, Font = F.Bold, ZIndex = 5,
				Text = percent == 0 and "GENAU DER WERT" or ((percent > 0 and "+" or "") .. percent .. " % ZUM WERT"),
				TextColor3 = percent < 0 and C.Good or (percent > 0 and C.Primary or C.Muted) }, row)
			local priceRow = rapLine(row, { Position = UDim2.fromOffset(630, 20), Color = rap >= entry.Price and C.Rap or C.Bad },
				entry.Price, 22)
			priceRow.ZIndex = 5
			watchChip(row, item.Id, UDim2.fromOffset(772, 22))
			UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(80, 44),
				Color = C.Rap, Text = "HIN", TextSize = 18, TextColor = C.PrimaryText, ZIndex = 5 }, row, function()
				local target = stands[entry.Stand]
				if target then
					closeWindow()
					setWaypoint(target)
					showToast("Folge dem Pfeil zu Stand " .. entry.Stand .. ".", true)
				end
			end)
		end
		if #entries == 0 then
			label({ Size = UDim2.new(1, 0, 0, 60), TextSize = 16, Font = F.Medium, TextColor3 = C.Muted, ZIndex = 5,
				Text = searchWatchOnly and "Keiner deiner gemerkten Skins wird gerade angeboten." or "Gerade bietet niemand etwas an.",
				TextXAlignment = Enum.TextXAlignment.Center }, results)
		elseif #found == 0 then
			label({ Size = UDim2.new(1, 0, 0, 60), Text = "Nichts gefunden – andere Suche oder Filter lösen.", TextSize = 16, Font = F.Medium,
				TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, results)
		end
		footer.Text = #found .. " VON " .. #entries .. " ANGEBOTEN"
			.. (#found > MAX_ROWS and ("  ·  ERSTE " .. MAX_ROWS .. " – SUCHE EINGRENZEN") or "")
	end

	local function buildControls()
		for _, child in controls:GetChildren() do
			child:Destroy()
		end
		local function change(apply)
			apply()
			buildControls()
			fill()
		end
		-- Zeile 1 rechts vom Suchfeld: Sortierung
		local x = 346
		for _, sort in MarketSearch.Sorts do
			local width = #sort.Name * 9 + 28
			searchChip(controls, sort.Name, x, 4, width, state.Sort == sort.Id, function()
				change(function()
					state.Sort = sort.Id
				end)
			end)
			x += width + 8
		end
		-- Zeile 2: Seltenheit, Art, bezahlbar, Merkliste
		x = 0
		searchChip(controls, "ALLE", x, 52, 64, state.Rarity == nil, function()
			change(function()
				state.Rarity = nil
			end)
		end)
		x += 72
		for _, id in MarketSearch.RarityOrder do
			local info = Cosmetics.Rarities[id]
			local width = #info.Name * 9 + 28
			local chip = searchChip(controls, upper(info.Name), x, 52, width, state.Rarity == id, function()
				change(function()
					state.Rarity = if state.Rarity == id then nil else id
				end)
			end)
			if state.Rarity ~= id then
				chip.Label.TextColor3 = info.Color
			end
			x += width + 8
		end
		x += 12
		for _, kind in MarketSearch.Types do
			local width = #kind.Name * 9 + 28
			searchChip(controls, kind.Name, x, 52, width, state.Type == kind.Id, function()
				change(function()
					state.Type = if state.Type == kind.Id then nil else kind.Id
				end)
			end)
			x += width + 8
		end
		x += 12
		searchChip(controls, "BEZAHLBAR", x, 52, 109, state.MaxPrice ~= nil, function()
			change(function()
				state.MaxPrice = state.MaxPrice == nil and (player:GetAttribute("Rap") or 0) or nil
			end)
		end)
		x += 117
		searchChip(controls, "MERKLISTE", x, 52, 109, searchWatchOnly, function()
			change(function()
				searchWatchOnly = not searchWatchOnly
			end)
		end)
	end

	box:GetPropertyChangedSignal("Text"):Connect(function()
		state.Text = box.Text
		fill()
	end)
	function win.Refresh()
		if state.MaxPrice ~= nil then
			state.MaxPrice = player:GetAttribute("Rap") or 0
		end
		fill()
	end
	buildControls()
	fill()
end

-- ---------- Gegenangebote (Besitzer) ----------

local function openOffers()
	local stand = myStand()
	if not stand then
		showToast("Du hast keinen Stand.", false)
		return
	end
	local win = newWindow("Offers", "GEGENANGEBOTE  ·  STAND " .. stand.Id, stand)
	local body = win.Body
	local timers = {} -- [Angebots-Id] = { Label, Expires }
	function win.Refresh()
		for _, child in body:GetChildren() do
			child:Destroy()
		end
		timers = {}
		local current = myStand()
		if not current then
			closeWindow()
			return
		end
		local offers = decode(current.Folder:GetAttribute("Offers"))
		local askedBySlot = {}
		for _, listing in listingsOf(current) do
			askedBySlot[listing.Slot] = listing.Price
		end
		local list = make("ScrollingFrame", { Size = UDim2.new(1, 0, 1, -30), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 5, ScrollBarImageColor3 = C.Border, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ZIndex = 5 }, body)
		make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		for order, offer in offers do
			local item = Cosmetics.Get(offer.Item)
			if item then
				local rarity = Cosmetics.Rarities[item.Rarity]
				local color = rarity and rarity.Color or C.Border
				local row = make("Frame", { Size = UDim2.new(1, -12, 0, 84), BackgroundColor3 = C.Card, BackgroundTransparency = 0.05,
					LayoutOrder = order, ZIndex = 5 }, list)
				UITheme.Corner(row, UITheme.Radius.Large)
				UITheme.Stroke(row, color, 1, 0.55)
				make("Frame", { Size = UDim2.new(0, 4, 1, -16), Position = UDim2.fromOffset(0, 8), BackgroundColor3 = color,
					BorderSizePixel = 0, ZIndex = 5 }, row)
				label({ Position = UDim2.fromOffset(18, 10), Size = UDim2.fromOffset(320, 26), Text = upper(item.Name), TextSize = 22,
					Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, row)
				local asked = askedBySlot[offer.Slot] or 0
				label({ Position = UDim2.fromOffset(18, 40), Size = UDim2.fromOffset(320, 18), TextSize = 13, Font = F.Bold, ZIndex = 5,
					Text = upper(offer.BuyerName) .. " BIETET", TextColor3 = C.Muted }, row)
				label({ Position = UDim2.fromOffset(18, 58), Size = UDim2.fromOffset(320, 18), TextSize = 12, Font = F.Medium, ZIndex = 5,
					Text = "DEIN PREIS: " .. format(asked) .. " RAP", TextColor3 = C.Muted }, row)
				local priceRow = rapLine(row, { Position = UDim2.fromOffset(360, 16) }, offer.Price, 26)
				priceRow.ZIndex = 5
				local percent = asked > 0 and math.floor((offer.Price / asked - 1) * 100 + 0.5) or 0
				label({ Position = UDim2.fromOffset(360, 50), Size = UDim2.fromOffset(250, 16), TextSize = 12, Font = F.Bold, ZIndex = 5,
					Text = percent .. " % ZUM PREIS  ·  DU BEKOMMST " .. format(RapConfig.AfterFee(offer.Price)) .. " RAP",
					TextColor3 = C.Primary }, row)
				local left = label({ Position = UDim2.fromOffset(360, 66), Size = UDim2.fromOffset(250, 14), TextSize = 11, Font = F.Bold,
					ZIndex = 5, Text = "", TextColor3 = C.Muted }, row)
				timers[offer.Id] = { Label = left, Expires = offer.Expires }
				UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -140, 0.5, 0), Size = UDim2.fromOffset(120, 48),
					Color = C.Rap, Text = "ANNEHMEN", TextSize = 16, TextColor = C.PrimaryText, ZIndex = 5 }, row, function()
					Remotes.MarketAction:FireServer("Answer", offer.Id, true)
				end)
				UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(116, 48),
					Color = C.Card, StrokeColor = C.Bad, Text = "ABLEHNEN", TextSize = 15, TextColor = C.Bad, ZIndex = 5 }, row, function()
					Remotes.MarketAction:FireServer("Answer", offer.Id, false)
				end)
			end
		end
		if #offers == 0 then
			label({ Size = UDim2.new(1, 0, 0, 80), Text = "Gerade hat niemand ein Gegenangebot gemacht.", TextSize = 16, Font = F.Medium,
				TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, list)
		end
		label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 20), ZIndex = 5,
			Text = "Ein Gegenangebot gilt " .. RapConfig.OfferSeconds .. " Sekunden. Nimmst du es an, ist der Skin sofort verkauft.",
			TextSize = 12, Font = F.Medium, TextColor3 = C.Muted }, body)
	end
	win.Refresh()
	task.spawn(function()
		while window == win do
			for _, entry in timers do
				if entry.Label.Parent then
					local left = (entry.Expires or 0) - os.time()
					entry.Label.Text = left > 0 and ("NOCH " .. left .. " SEKUNDEN") or "ABGELAUFEN"
				end
			end
			task.wait(0.5)
		end
	end)
end

-- ---------- Tafeln in der Halle ----------

local boards = {} -- { Overview = { Cells = { [Nummer] = Frame }, Count }, Top = { Rows = { Label } } }

local function boardGui(part, name)
	local surface = Instance.new("SurfaceGui")
	surface.Name = name
	surface.ResetOnSpawn = false
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Brightness = 1.4
	surface.Adornee = part
	surface.Parent = player:WaitForChild("PlayerGui")
	local back = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background, BackgroundTransparency = 0.05,
		BorderSizePixel = 0 }, surface)
	make("Frame", { Size = UDim2.new(1, 0, 0.03, 0), BackgroundColor3 = C.Rap, BorderSizePixel = 0 }, back)
	return back
end

local function buildBoards(map)
	local overview = map:FindFirstChild("OverviewBoard", true)
	if overview then
		local back = boardGui(overview, "MarketOverview")
		label({ Position = UDim2.fromScale(0.03, 0.08), Size = UDim2.fromScale(0.5, 0.22), Text = "STÄNDE", TextSize = 40, Font = F.Display,
			TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left }, back)
		local summary = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.97, 0.1), Size = UDim2.fromScale(0.45, 0.18),
			Text = "", TextScaled = true, Font = F.Bold, TextColor3 = C.Rap, TextXAlignment = Enum.TextXAlignment.Right }, back)
		local grid = make("Frame", { Position = UDim2.fromScale(0.03, 0.34), Size = UDim2.fromScale(0.94, 0.5), BackgroundTransparency = 1 }, back)
		local cells = {}
		local ids = {}
		for id in stands do
			table.insert(ids, id)
		end
		table.sort(ids)
		-- drei Zeilen, so viele Spalten wie nötig (bei 48 Ständen 16)
		local columns = math.max(1, math.ceil(#ids / 3))
		local gapX = 0.0075
		make("UIGridLayout", { CellSize = UDim2.fromScale((1 - (columns - 1) * gapX) / columns - 0.0005, 0.3), CellPadding = UDim2.fromScale(gapX, 0.05),
			SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		for _, id in ids do
			cells[id] = label({ LayoutOrder = id, Text = tostring(id), TextScaled = true, Font = F.Bold,
				TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0.1, BackgroundColor3 = C.Card }, grid)
			UITheme.Corner(cells[id], UITheme.Radius.Small)
		end
		label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0.03, 0.96), Size = UDim2.fromScale(0.94, 0.1),
			Text = "GRÜN = FREI   ·   BERNSTEIN = BELEGT   ·   WEISS = DEIN STAND", TextScaled = true, Font = F.Bold, TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left }, back)
		boards.Overview = { Cells = cells, Summary = summary }
	end
	local top = map:FindFirstChild("TopBoard", true)
	if top then
		local back = boardGui(top, "MarketTop")
		label({ Position = UDim2.fromScale(0.04, 0.06), Size = UDim2.fromScale(0.92, 0.16), Text = "BELIEBTESTE HÄNDLER", TextScaled = true,
			Font = F.Display, TextXAlignment = Enum.TextXAlignment.Left }, back)
		label({ Position = UDim2.fromScale(0.04, 0.21), Size = UDim2.fromScale(0.92, 0.06), Text = "DIESER SERVER  ·  NACH VERKÄUFEN",
			TextScaled = true, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left }, back)
		local rows = {}
		for index = 1, 5 do
			rows[index] = label({ Position = UDim2.fromScale(0.04, 0.3 + (index - 1) * 0.13), Size = UDim2.fromScale(0.92, 0.1), Text = "",
				TextScaled = true, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Left }, back)
		end
		boards.Top = { Rows = rows }
	end
end

function refreshBoards()
	local overview = boards.Overview
	if overview then
		local free = 0
		local total = 0
		for id, cell in overview.Cells do
			local stand = stands[id]
			local owner = stand and ownerOf(stand) or 0
			total += 1
			if owner == 0 then
				free += 1
				cell.BackgroundColor3 = C.Good
				cell.TextColor3 = C.PrimaryText
			elseif owner == player.UserId then
				cell.BackgroundColor3 = Color3.new(1, 1, 1)
				cell.TextColor3 = C.PrimaryText
			else
				cell.BackgroundColor3 = C.Primary
				cell.TextColor3 = C.PrimaryText
			end
		end
		overview.Summary.Text = free .. " VON " .. total .. " FREI"
	end
	local top = boards.Top
	if top then
		local list = marketMap and decode(marketMap:GetAttribute("TopSellers")) or {}
		for index, row in top.Rows do
			local entry = list[index]
			if entry then
				row.Text = index .. ".  " .. upper(entry.Name) .. "  ·  " .. entry.Sales .. (entry.Sales == 1 and " VERKAUF" or " VERKÄUFE")
					.. "  ·  " .. format(entry.Volume) .. " RAP"
				row.TextColor3 = index == 1 and C.Primary or C.Text
			else
				row.Text = index == 1 and "NOCH KEIN VERKAUF – SEI DER ERSTE!" or ""
				row.TextColor3 = C.Muted
			end
		end
	end
end

-- ---------- Leiste oben ----------

local function buildBar()
	local bar = UITheme.Card({ Name = "MarketBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(1000, 56), BackgroundTransparency = 0.1 }, root)
	make("Frame", { Size = UDim2.new(0, 4, 1, -16), Position = UDim2.fromOffset(0, 8), BackgroundColor3 = C.Rap, BorderSizePixel = 0,
		ZIndex = 2 }, bar)
	label({ Position = UDim2.fromOffset(18, 6), Size = UDim2.fromOffset(110, 44), Text = "MARKT", TextSize = 32, Font = F.Display,
		ZIndex = 2 }, bar)
	local rapRow
	rapRow, barRap = rapLine(bar, { Position = UDim2.fromOffset(124, 13) }, 0, 24)
	rapRow.ZIndex = 2
	barStatus = label({ Position = UDim2.fromOffset(262, 8), Size = UDim2.fromOffset(220, 40), Text = "", TextSize = 12, Font = F.Bold,
		TextColor3 = C.Muted, TextWrapped = true, ZIndex = 2 }, bar)
	UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -248, 0.5, 0), Size = UDim2.fromOffset(104, 38),
		Color = C.Card, StrokeColor = C.Rap, Text = "SUCHE", TextSize = 16, TextColor = C.Rap, ZIndex = 2 }, bar, openSearch)
	offersButton = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -360, 0.5, 0), Size = UDim2.fromOffset(150, 38),
		Color = C.Card, StrokeColor = C.Primary, Text = "ANGEBOTE", TextSize = 15, TextColor = C.Primary, ZIndex = 2 }, bar, openOffers)
	manageButton = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -118, 0.5, 0), Size = UDim2.fromOffset(122, 38),
		Color = C.Rap, Text = "MEIN STAND", TextSize = 16, TextColor = C.PrimaryText, ZIndex = 2 }, bar, openManage)
	releaseButton = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 38),
		Color = C.Card, StrokeColor = C.Bad, Text = "ABGEBEN", TextSize = 15, TextColor = C.Bad, ZIndex = 2 }, bar, function()
		Remotes.MarketAction:FireServer("Release")
	end)
	toast = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.fromOffset(1000, 26), Text = "",
		TextSize = 16, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5, Visible = false }, root)
end

local function refreshBar()
	gui.Enabled = inMarket()
	barRap.Text = format(player:GetAttribute("Rap") or 0) .. " RAP"
	local stand = myStand()
	manageButton.Button.Visible = stand ~= nil
	releaseButton.Button.Visible = stand ~= nil
	offersButton.Button.Visible = stand ~= nil
	if stand then
		local count = #listingsOf(stand)
		local offers = #decode(stand.Folder:GetAttribute("Offers"))
		barStatus.Text = "DEIN STAND " .. stand.Id .. "  ·  " .. count .. " / " .. RapConfig.StandSlots .. " ANGEBOTE"
		barStatus.TextColor3 = C.Text
		offersButton.SetText(offers > 0 and ("ANGEBOTE (" .. offers .. ")") or "ANGEBOTE")
		offersButton.Face.BackgroundColor3 = offers > 0 and C.Primary or C.Card
		offersButton.Label.TextColor3 = offers > 0 and C.PrimaryText or C.Primary
	else
		barStatus.Text = "KEIN STAND  ·  FREIEN STAND SUCHEN, E DRÜCKEN"
		barStatus.TextColor3 = C.Muted
	end
end

-- ---------- Start ----------

function MarketClient.Init()
	gui = make("ScreenGui", { Name = "Market", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 12, Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	root = UITheme.ScaledRoot(gui, nil, nil, 0.55)
	buildBar()
	displayFolder = Instance.new("Folder")
	displayFolder.Name = "MarketDisplays"
	displayFolder.Parent = workspace

	local map = workspace:WaitForChild("Maps"):WaitForChild("Market", 30)
	marketMap = map
	if map then
		for _, folder in map:GetChildren() do
			local id = tonumber(string.match(folder.Name, "^Stand_(%d+)$"))
			if id then
				local stand = { Id = id, Folder = folder, Displays = {} }
				stands[id] = stand
				buildSign(stand)
				local anchor = folder:FindFirstChild("Prompt")
				if anchor then
					local prompt = Instance.new("ProximityPrompt")
					prompt.KeyboardKeyCode = Enum.KeyCode.E
					prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
					prompt.HoldDuration = 0
					prompt.MaxActivationDistance = 11
					prompt.RequiresLineOfSight = false
					prompt.Parent = anchor
					prompt.Triggered:Connect(function()
						local owner = ownerOf(stand)
						if owner == 0 then
							Remotes.MarketAction:FireServer("Claim", stand.Id)
						elseif owner == player.UserId then
							openManage()
						else
							openStand(stand)
						end
					end)
					stand.Prompt = prompt
				end
				for _, attribute in { "Owner", "OwnerName", "StandName", "Listings", "Offers" } do
					folder:GetAttributeChangedSignal(attribute):Connect(function()
						refreshAllStands() -- eigener Stand ändert auch die Prompts der anderen
						refreshBar()
						if window and (window.Stand == stand or window.Kind == "Manage" or window.Kind == "Search" or window.Kind == "Offers") then
							refreshWindow()
						end
					end)
				end
			end
		end
	end
	-- Such-Terminal auf dem Marktplatz (Part "SearchTerminal"): E öffnet die Suche
	local terminal = map and map:FindFirstChild("SearchTerminal", true)
	if terminal then
		local prompt = Instance.new("ProximityPrompt")
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.ActionText = "Markt durchsuchen"
		prompt.ObjectText = "Such-Terminal"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = terminal
		prompt.Triggered:Connect(openSearch)
	end
	if map then
		buildBoards(map)
		for _, attribute in { "PriceStats", "TopSellers" } do
			map:GetAttributeChangedSignal(attribute):Connect(function()
				refreshBoards()
				refreshWindow()
			end)
		end
	end
	refreshAllStands()
	refreshBar()

	Remotes.MarketStatus.OnClientEvent:Connect(function(message, success)
		showToast(message, success)
		if success == true then
			sound("rbxasset://sounds/electronicpingshort.wav", 1.3, 0.4)
		elseif success == false then
			sound("rbxasset://sounds/clickfast.wav", 0.7, 0.4)
		end
	end)
	player:GetAttributeChangedSignal("Mode"):Connect(function()
		if not inMarket() then
			closeWindow()
			clearWaypoint()
		end
		refreshAllStands()
		refreshBar()
	end)
	for _, attribute in { "Rap", "Owned", "Reserved", "MarketWatch" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			refreshBar()
			refreshWindow()
		end)
	end
	-- Esc bzw. Controller ○ schließt das Fenster
	UserInputService.InputBegan:Connect(function(input, processed)
		if window and (input.KeyCode == Enum.KeyCode.ButtonB or (input.KeyCode == Enum.KeyCode.Escape and not processed)) then
			closeWindow()
		end
	end)
	-- Ausgestellte Skins drehen sich langsam (nur die in der Nähe der Kamera, die anderen bleiben stehen)
	RunService.RenderStepped:Connect(function()
		if not inMarket() then
			return
		end
		updateWaypoint()
		local t = os.clock()
		local eye = workspace.CurrentCamera.CFrame.Position
		for _, stand in stands do
			for _, display in stand.Displays do
				if (display.Spot.Position - eye).Magnitude > 90 and display.Placed then
					continue
				end
				display.Placed = true
				local spin = CFrame.Angles(0, t * 0.7 + display.Phase, 0)
				if display.Agent then
					-- Figur steht auf Theke bzw. Regal
					local base = display.Spot.Position - Vector3.new(0, 0.85, 0)
					display.Model:PivotTo(CFrame.new(base + Vector3.new(0, display.Height / 2, 0)) * spin * display.Offset:Inverse())
				else
					display.Model:PivotTo(CFrame.new(display.Spot.Position + Vector3.new(0, math.sin(t * 1.6 + display.Phase) * 0.08, 0))
						* spin * display.Offset:Inverse())
				end
			end
		end
	end)
end

-- Für die Tests: Fenster von außen öffnen
MarketClient.OpenManage = openManage
MarketClient.OpenSearch = openSearch
MarketClient.OpenOffers = openOffers
MarketClient.OpenStand = function(id)
	if stands[id] then
		openStand(stands[id])
	end
end

return MarketClient

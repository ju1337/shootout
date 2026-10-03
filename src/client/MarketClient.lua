-- MarketClient (ModuleScript, nur Client)
-- Markthalle (Modus "Market"; Server: MarketService):
--   * Stände in der Welt: Schild über jedem Stand (FREI bzw. Besitzer und Zahl der Angebote); die angebotenen
--     Skins drehen sich auf Theke und Regal, darüber ein Preisschild (Name in Seltenheitsfarbe, Preis in RAP).
--   * E am Stand: freien Stand beanspruchen, den eigenen verwalten, bei anderen ansehen und kaufen.
--   * Leiste oben: MARKT, eigenes RAP, eigener Stand (MEIN STAND, ABGEBEN) und die Meldungen vom Server.
--   * Fenster MEIN STAND: links die sechs Plätze (Preis ändern, zurücknehmen), rechts die eigenen handelbaren
--     Skins mit Preisfeld (Vorschlag: RAP-Wert) und ANBIETEN.
--   * Fenster STAND: Angebote eines anderen Stands mit Preis und RAP-Wert, KAUFEN (zweimal klicken).
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

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label, upper = UITheme.Make, UITheme.Label, UITheme.Upper
local format = UITheme.FormatNumber

local MarketClient = {}

local WIN_W, WIN_H = 1040, 620

local stands = {}   -- [Nummer] = { Id, Folder, Sign, Prompt, Displays = { [Platz] = {...} }, Shown }
local displayFolder -- Modelle der angebotenen Skins (nur solange man im Markt ist)
local gui, root, toast, barStatus, barRap, manageButton, releaseButton
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
			stand.Sign.Main.Text = upper(tostring(stand.Folder:GetAttribute("OwnerName") or "?"))
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
	if focused and focused:IsDescendantOf(window.Frame) then
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
		local grid = make("Frame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -64), BackgroundTransparency = 1,
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
				label({ Position = UDim2.fromOffset(124, 54), Size = UDim2.new(1, -134, 0, 14), Text = "WERT " .. format(RapConfig.Value(item.Id) or 0)
					.. " RAP", TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, card)
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
		label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 30), TextWrapped = true,
			Text = "Marktgebühr " .. math.floor(RapConfig.MarketFee * 100) .. " %. Verlässt du den Markt, ist dein Stand weg – deine Skins sind dann wieder frei.",
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
				label({ Position = UDim2.fromOffset(124, 56), Size = UDim2.new(0, 160, 0, 14), Text = entry.Free .. " FREI  ·  WERT "
					.. format(RapConfig.Value(item.Id)), TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, card)
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

-- STAND eines anderen Spielers: Angebote kaufen (zweimal klicken)
local function openStand(stand)
	local owner = tostring(stand.Folder:GetAttribute("OwnerName") or "")
	local win = newWindow("Stand", "STAND " .. stand.Id .. "  ·  " .. upper(owner), stand)
	local body = win.Body
	local confirm = {} -- [Platz] = os.clock() bis wann die Rückfrage gilt
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
		local grid = make("Frame", { Size = UDim2.new(1, 0, 1, -36), BackgroundTransparency = 1, ZIndex = 5 }, body)
		make("UIGridLayout", { CellSize = UDim2.fromOffset(318, 230), CellPadding = UDim2.fromOffset(14, 14),
			SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		local rap = player:GetAttribute("Rap") or 0
		for _, listing in listings do
			local item = Cosmetics.Get(listing.Item)
			if item then
				local card = itemCard(grid, item, UDim2.fromOffset(318, 230), listing.Slot)
				local value = RapConfig.Value(item.Id) or 0
				label({ Position = UDim2.fromOffset(124, 56), Size = UDim2.new(1, -134, 0, 14), Text = "RAP-WERT " .. format(value),
					TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, card)
				-- Preis groß, darunter wie er zum Wert steht
				local priceRow = rapLine(card, { Position = UDim2.fromOffset(16, 98) }, listing.Price, 30)
				priceRow.ZIndex = 5
				local diff = value > 0 and math.floor((listing.Price / value - 1) * 100 + 0.5) or 0
				label({ Position = UDim2.fromOffset(16, 138), Size = UDim2.new(1, -32, 0, 16), TextSize = 12, Font = F.Bold, ZIndex = 5,
					Text = diff == 0 and "GENAU DER RAP-WERT" or (math.abs(diff) .. " % " .. (diff > 0 and "ÜBER" or "UNTER") .. " DEM RAP-WERT"),
					TextColor3 = diff > 0 and C.Primary or C.Good }, card)
				local affordable = rap >= listing.Price
				local buy
				buy = UITheme.Chunky({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -28, 0, 44),
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
				TextColor3 = C.Muted, ZIndex = 5 }, grid)
		end
		label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 20), ZIndex = 5,
			Text = "Bezahlt wird mit RAP. Mehr RAP: Skins im SHOP ans System verkaufen oder selbst einen Stand aufmachen.",
			TextSize = 12, Font = F.Medium, TextColor3 = C.Muted }, body)
	end
	win.Refresh()
end

-- ---------- Leiste oben ----------

local function buildBar()
	local bar = UITheme.Card({ Name = "MarketBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(820, 56), BackgroundTransparency = 0.1 }, root)
	make("Frame", { Size = UDim2.new(0, 4, 1, -16), Position = UDim2.fromOffset(0, 8), BackgroundColor3 = C.Rap, BorderSizePixel = 0,
		ZIndex = 2 }, bar)
	label({ Position = UDim2.fromOffset(18, 6), Size = UDim2.fromOffset(110, 44), Text = "MARKT", TextSize = 32, Font = F.Display,
		ZIndex = 2 }, bar)
	local rapRow
	rapRow, barRap = rapLine(bar, { Position = UDim2.fromOffset(124, 13) }, 0, 24)
	rapRow.ZIndex = 2
	barStatus = label({ Position = UDim2.fromOffset(262, 8), Size = UDim2.fromOffset(330, 40), Text = "", TextSize = 13, Font = F.Bold,
		TextColor3 = C.Muted, TextWrapped = true, ZIndex = 2 }, bar)
	manageButton = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -118, 0.5, 0), Size = UDim2.fromOffset(122, 38),
		Color = C.Rap, Text = "MEIN STAND", TextSize = 16, TextColor = C.PrimaryText, ZIndex = 2 }, bar, openManage)
	releaseButton = UITheme.Chunky({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 38),
		Color = C.Card, StrokeColor = C.Bad, Text = "ABGEBEN", TextSize = 15, TextColor = C.Bad, ZIndex = 2 }, bar, function()
		Remotes.MarketAction:FireServer("Release")
	end)
	toast = label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.fromOffset(820, 26), Text = "",
		TextSize = 16, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5, Visible = false }, root)
end

local function refreshBar()
	gui.Enabled = inMarket()
	barRap.Text = format(player:GetAttribute("Rap") or 0) .. " RAP"
	local stand = myStand()
	manageButton.Button.Visible = stand ~= nil
	releaseButton.Button.Visible = stand ~= nil
	if stand then
		local count = #listingsOf(stand)
		barStatus.Text = "DEIN STAND " .. stand.Id .. "  ·  " .. count .. " / " .. RapConfig.StandSlots .. " ANGEBOTE"
		barStatus.TextColor3 = C.Text
	else
		barStatus.Text = "KEIN STAND  ·  GEH ZU EINEM FREIEN STAND UND DRÜCKE E"
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
				for _, attribute in { "Owner", "OwnerName", "Listings" } do
					folder:GetAttributeChangedSignal(attribute):Connect(function()
						refreshAllStands() -- eigener Stand ändert auch die Prompts der anderen
						refreshBar()
						if window and (window.Stand == stand or window.Kind == "Manage") then
							refreshWindow()
						end
					end)
				end
			end
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
		end
		refreshAllStands()
		refreshBar()
	end)
	for _, attribute in { "Rap", "Owned", "Reserved" } do
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
MarketClient.OpenStand = function(id)
	if stands[id] then
		openStand(stands[id])
	end
end

return MarketClient

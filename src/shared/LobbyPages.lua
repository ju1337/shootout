-- LobbyPages (ModuleScript, nur Client)
-- Seiten LOADOUT, SHOP und BATTLE PASS der Lobby (GameMenu). Sie liegen direkt in der Lobby unter der
-- Kopfzeile – kein eigenes Fenster – und nutzen das gemeinsame Design (UITheme):
--   LOADOUT:     links die Waffen, Mitte große 3D-Vorschau mit dem ausgerüsteten Skin, rechts die eigenen Skins
--                zum Ausrüsten (Standard + gekaufte) bzw. die Aufsätze (Agenten haben keine Skins)
--   SHOP:        Startseite START: links das Angebot des Tages (ShopOffers: Rabatt, Restzeit, großer KAUFEN-Knopf),
--                rechts vier Kacheln WAFFEN-SKINS, AGENTEN-SKINS, ROBUX, VERKAUFEN, die in den Reiter führen;
--                Reiter WAFFEN-/AGENTEN-SKINS: Karten mit 3D-Vorschau vor der Farbe des Skins, Rand und Schild in der
--                Seltenheit (legendär oben), RAP-Wert, Münzpreis (Angebot durchgestrichen) und KAUFEN / NOCH x MÜNZEN;
--                Reiter VERKAUFEN: eigene handelbare Skins ans System zurückverkaufen (sofort RAP, RapConfig)
--   BATTLE PASS: Saison, Stufe und Fortschritt, alle Stufen als waagerechte Leiste (die nächste hervorgehoben),
--                darunter die nächste Belohnung und wie man Pass-XP sammelt
-- Jede Funktion baut in einen leeren Rahmen (PAGE_W x PAGE_H) und gibt { Refresh, Watch } zurück: Refresh
-- aktualisiert die Seite, Watch nennt die Spieler-Attribute, bei deren Änderung GameMenu Refresh aufruft.
-- Kaufen und Ausrüsten prüft der Server (ShopService); seine Rückmeldung zeigt die Lobby in der Statuszeile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.Cosmetics)
local WeaponConfig = require(Shared.WeaponConfig)
local GunModels = require(Shared.GunModels)
local PassConfig = require(Shared.PassConfig)
local UITheme = require(Shared.UITheme)
local AttachmentConfig = require(Shared.AttachmentConfig)
local MasteryConfig = require(Shared.MasteryConfig)
local AttachmentIcons = require(Shared.AttachmentIcons)
local InputActions = require(Shared.InputActions)
local RobuxConfig = require(Shared.RobuxConfig)
local RapConfig = require(Shared.RapConfig)
local PaidRandom = require(Shared.PaidRandom)
local OddsPanel = require(Shared.OddsPanel)
local WeaponEffects = require(Shared.WeaponEffects)
local AgentConfig = require(Shared.AgentConfig)
local AgentFigure = require(Shared.AgentFigure)
local ShopOffers = require(Shared.ShopOffers)
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label, upper = UITheme.Make, UITheme.Label, UITheme.Upper

local LobbyPages = {}

LobbyPages.PAGE_W, LobbyPages.PAGE_H = 1520, 730
local PAGE_W, PAGE_H = LobbyPages.PAGE_W, LobbyPages.PAGE_H
local CREATOR_COLOR = Color3.fromRGB(190, 100, 255) -- wie der Team-Rang CREATOR
local WEAPON_ORDER = { "Rifle", "SMG", "Shotgun", "DMR", "LMG", "Pistol", "Revolver" }

local function coins()
	return player:GetAttribute("Coins") or 0
end

-- Gerade an einem Stand oder in einem Tausch zurückgelegte Skins ({ [Id] = Stück })
local function reservedItems()
	local ok, data = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Reserved") or "{}")
	return ok and type(data) == "table" and data or {}
end

-- RAP-Wert als kleines Schild (Raute + Zahl) oben rechts auf eine Karte
local function rapBadge(parent, value)
	local badge = make("Frame", { Name = "RapBadge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 12),
		Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.25, ZIndex = 3 }, parent)
	UITheme.Corner(badge, UITheme.Radius.Small)
	UITheme.Stroke(badge, C.Rap, 1, 0.55)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8) }, badge)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, badge)
	UITheme.RapIcon(badge, 13, { LayoutOrder = 1, ZIndex = 3 })
	label({ Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Text = UITheme.FormatNumber(value) .. " RAP",
		TextSize = 12, Font = F.Bold, TextColor3 = C.Rap, LayoutOrder = 2, ZIndex = 3 }, badge)
	return badge
end

local function clear(container)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- 3D-Vorschau mit Licht wie in der Lobby
local function viewport(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Ambient = Color3.fromRGB(130, 135, 150)
	props.LightColor = Color3.fromRGB(255, 245, 235)
	props.LightDirection = Vector3.new(-0.5, -1, 0.6)
	return make("ViewportFrame", props, parent)
end

-- Waffe mit Skin von der Seite zeigen; die Kamera rückt so weit weg, dass die ganze Waffe ins Bild passt
-- (aspect = Breite / Höhe der Vorschau, fill = Anteil der Bildbreite)
local function showWeapon(view, weaponName, skin, aspect, fill, attachments)
	view:ClearAllChildren()
	local model = GunModels.Build(weaponName, skin, attachments)
	model.Parent = view
	local box, size = model:GetBoundingBox()
	local halfV = math.rad(15)
	local halfH = math.atan(math.tan(halfV) * (aspect or 1.4))
	local distance = math.max(size.Z / 2 / math.tan(halfH), size.Y / 2 / math.tan(halfV)) / (fill or 0.8) + size.X / 2
	local camera = make("Camera", { FieldOfView = 30 }, view)
	camera.CFrame = CFrame.lookAt(box.Position + Vector3.new(distance, distance * 0.15, 0), box.Position)
	view.CurrentCamera = camera
end

-- Der eine Agent (AgentConfig.MainId) mit einem Agenten-Skin (nil = Standard-Look) als ganze Figur, leicht gedreht
function LobbyPages.ShowAgent(view, skin, weaponName)
	view:ClearAllChildren()
	local agent = AgentConfig.Get(AgentConfig.MainId) or AgentConfig.Agents[1]
	local primary = skin and skin.Color or agent.Color:Lerp(Color3.new(0, 0, 0), 0.6)
	local figure = AgentFigure.Build(agent, primary, agent.Color, nil, weaponName, skin and skin.Material,
		skin and skin.Model and skin.Id or nil)
	figure:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, 0.45, 0))
	figure.Parent = view
	local camera = make("Camera", { FieldOfView = 30 }, view)
	camera.CFrame = AgentFigure.CameraCFrame * CFrame.new(0, 0, 4.5)
	view.CurrentCamera = camera
	return figure
end

-- Watch-Liste plus alle Gamepässe (Pass_<Id>): Karten im Robux-Shop zeigen nach dem Kauf sofort GEKAUFT
local function robuxWatch(watch)
	for _, pass in RobuxConfig.Passes do
		watch["Pass_" .. pass.Id] = true
	end
	return watch
end

-- Reiter wie die Navigation der Lobby (aktiv: weiß mit Strich in accent, Standard Bernstein). Gibt select(name) zurück.
local function tabs(parent, names, x, y, width, onSelect, accent)
	local bar = make("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, 36), BackgroundTransparency = 1 },
		parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	make("Frame", { Position = UDim2.fromOffset(x, y + 36), Size = UDim2.fromOffset(width, 1), BackgroundColor3 = C.Border,
		BorderSizePixel = 0 }, parent)
	local buttons = {}
	local function select(name)
		for n, b in buttons do
			b.TextColor3 = n == name and C.Text or C.Muted
			b.Underline.Visible = n == name
		end
		onSelect(name)
	end
	for i, name in names do
		local b = make("TextButton", { Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Text = name,
			TextSize = 19, Font = F.Display, TextColor3 = C.Muted, BackgroundTransparency = 1, AutoButtonColor = false,
			LayoutOrder = i }, bar)
		make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, b)
		make("Frame", { Name = "Underline", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -12, 1, 0),
			Size = UDim2.new(1, 24, 0, 2), BackgroundColor3 = accent or C.Primary, BorderSizePixel = 0, Visible = false }, b)
		b.MouseEnter:Connect(function()
			b.TextColor3 = C.Text
		end)
		b.MouseLeave:Connect(function()
			if not b.Underline.Visible then
				b.TextColor3 = C.Muted
			end
		end)
		b.Activated:Connect(function()
			select(name)
		end)
		buttons[name] = b
	end
	return select
end

-- =====================================================================
-- SHOP
-- =====================================================================

-- Farben und Bausteine des SHOP: Design des Menüs der offenen Welt (fast deckende dunkle Flächen, Rot als Akzent)
local SHOP_RED = UITheme.MenuColors.Primary
local SHOP_PANEL = Color3.fromRGB(14, 15, 18)
local RARITY_ORDER = { Legendary = 4, Epic = 3, Rare = 2, Common = 1 }
-- Raster: 6 Karten pro Reihe über die ganze Breite, gleiche Abstände
local GRID_COLUMNS, GRID_GAP, CARD_H = 6, 16, 318
local CARD_W = math.floor((PAGE_W - (GRID_COLUMNS - 1) * GRID_GAP) / GRID_COLUMNS)
local STAGE_H = 170

-- Vorschaufläche: dunkle Fläche, von unten in der Farbe des Skins angeleuchtet, unten ein Strich in der Seltenheit.
-- So unterscheiden sich die Karten auf einen Blick, auch wenn das Modell selbst dunkel ist.
local function stage(props, parent, tint, rarityColor)
	props.BackgroundColor3 = Color3.fromRGB(20, 21, 25)
	props.BorderSizePixel = 0
	props.ClipsDescendants = true
	local frame = make("Frame", props, parent)
	UITheme.Corner(frame, UITheme.Radius.Large)
	local glow = make("Frame", { Name = "Glow", Size = UDim2.fromScale(1, 1), BackgroundColor3 = tint, BorderSizePixel = 0,
		ZIndex = frame.ZIndex }, frame)
	UITheme.Corner(glow, UITheme.Radius.Large)
	make("UIGradient", { Rotation = 270, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.55, 0.85), NumberSequenceKeypoint.new(1, 1) }) }, glow)
	make("Frame", { Name = "Floor", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = rarityColor, BorderSizePixel = 0, ZIndex = frame.ZIndex }, frame)
	return frame
end

-- Agent mit Skin so zeigen, dass die ganze Figur mittig ins Bild passt (Blickrichtung wie in der Lobby)
local function showAgentFit(view, item, aspect, fill)
	local figure = LobbyPages.ShowAgent(view, item)
	local box, size = figure:GetBoundingBox()
	local look = AgentFigure.CameraCFrame.LookVector
	local halfV = math.rad(15)
	local halfH = math.atan(math.tan(halfV) * (aspect or 1))
	local radius = math.max(size.X, size.Z) / 2
	local distance = math.max(size.Y / 2 / math.tan(halfV), radius / math.tan(halfH)) / (fill or 0.82) + radius
	view.CurrentCamera.CFrame = CFrame.lookAt(box.Position - look * distance, box.Position)
end

-- Skin in eine Vorschau stellen (Waffen-Skin am Sturmgewehr, Agenten-Skin am Agenten)
local function showSkin(view, item, aspect)
	if item.Type == "Agent" then
		showAgentFit(view, item, aspect)
	else
		showWeapon(view, "Rifle", item, aspect, 0.86)
	end
end

-- Preiszeile: Münze + Preis, beim Angebot davor der alte Preis durchgestrichen. Gibt die Zeile zurück.
local function priceRow(props, parent, price, oldPrice, size)
	props.BackgroundTransparency = 1
	props.AutomaticSize = Enum.AutomaticSize.X
	local row = make("Frame", props, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, math.floor(size * 0.3)), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	if oldPrice then
		local old = label({ Name = "OldPrice", Size = UDim2.fromOffset(0, size), AutomaticSize = Enum.AutomaticSize.X,
			Text = UITheme.FormatNumber(oldPrice), TextSize = math.floor(size * 0.62), Font = F.Bold, TextColor3 = C.Muted,
			LayoutOrder = 1 }, row)
		make("Frame", { Name = "Strike", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -2, 0.5, 0),
			Size = UDim2.new(1, 4, 0, 2), BackgroundColor3 = SHOP_RED, BorderSizePixel = 0 }, old)
	end
	UITheme.Coin(row, math.floor(size * 0.72), { LayoutOrder = 2 })
	label({ Name = "Price", Size = UDim2.fromOffset(0, size), AutomaticSize = Enum.AutomaticSize.X,
		Text = UITheme.FormatNumber(price), TextSize = size, Font = F.Display, LayoutOrder = 3 }, row)
	return row
end

-- Karte im Raster: überall derselbe Rahmen (dunkel, fast deckend, feiner grauer Rand, beim Überfahren rot).
-- Seltenheit zeigt nur die Vorschau (Strich unten und Schild), nicht der Rahmen.
local function shopCard(props, parent)
	props.BackgroundColor3 = SHOP_PANEL
	props.BackgroundTransparency = 0.02
	props.BorderSizePixel = 0
	local card = make("Frame", props, parent)
	UITheme.Corner(card, UITheme.Radius.XL)
	local stroke = UITheme.Stroke(card, C.Border, 1)
	card.MouseEnter:Connect(function()
		stroke.Color = SHOP_RED
	end)
	card.MouseLeave:Connect(function()
		stroke.Color = C.Border
	end)
	return card
end

-- Kaufen-Knopf je nach Lage: rot = leistbar, grau mit fehlendem Betrag = zu teuer, grün beschriftet = im Besitz
local function setBuyState(button, item, price)
	if Cosmetics.GetOwned(player)[item.Id] then
		button.SetText("IM BESITZ")
		button.SetColor(C.MutedBack, C.Good)
	elseif coins() >= price then
		button.SetText("KAUFEN")
		button.SetColor(SHOP_RED, Color3.new(1, 1, 1))
	else
		local missing = price - coins()
		button.SetText(missing == 1 and "NOCH 1 MÜNZE" or ("NOCH " .. UITheme.FormatNumber(missing) .. " MÜNZEN"))
		button.SetColor(C.MutedBack, C.Muted)
	end
end

-- Teuerster kaufbarer Skin eines Typs (ohne Test-Skins): Aushängeschild der Kategorie auf der Startseite
local function showcase(itemType)
	local best
	for _, item in Cosmetics.List(itemType) do
		if Cosmetics.ForSale(item) and not item.Test and (not best or item.Price > best.Price) then
			best = item
		end
	end
	return best
end

function LobbyPages.Shop(page)
	local currentType = "Home"
	local cards = {} -- [itemId] = { Buy = Chunky, Item = item }
	-- Aktive Angebote (ShopOffers): offer = Hauptangebot der Startseite, offerById = günstigstes Angebot je Skin
	local offer, offerById, offerSignature = nil, {}, ""
	local function loadOffers()
		local active = ShopOffers.Active(workspace:GetServerTimeNow())
		local parts = {}
		offer, offerById = active[1], {}
		for _, entry in active do
			local known = offerById[entry.Item.Id]
			if not known or entry.Price < known.Price then
				offerById[entry.Item.Id] = entry
			end
			table.insert(parts, entry.Item.Id .. ":" .. entry.Price .. ":" .. entry.EndsAt)
		end
		local signature = table.concat(parts, ",")
		local changed = signature ~= offerSignature
		offerSignature = signature
		return changed
	end
	loadOffers()

	local hint = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 12), Size = UDim2.fromOffset(600, 16),
		Text = "", TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, page)
	local grid = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 54), Size = UDim2.fromOffset(PAGE_W, PAGE_H - 54),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Border,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, page)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(CARD_W, CARD_H), CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	-- Startseite: links das Angebot des Tages, rechts die Kategorien
	local home = make("Frame", { Name = "Home", Position = UDim2.fromOffset(0, 54), Size = UDim2.fromOffset(PAGE_W, PAGE_H - 54),
		BackgroundTransparency = 1, Visible = false }, page)

	local function updateButtons()
		for _, card in cards do
			setBuyState(card.Buy, card.Item, card.Price)
		end
	end
	-- Reiter ROBUX: Gamepässe und Entwicklerprodukte (RobuxConfig). Ohne ID: "BALD", sonst Roblox-Kaufdialog.
	-- Glücksrad-Drehs sind bezahlte Zufallsitems: Knopf CHANCEN auf der Karte, und wo Roblox sie verbietet
	-- (PaidRandom.ShowRandom), fehlt die Karte ganz.
	local robuxButtons = {} -- { Buy, Pass } zum Aktualisieren (gekauft?)
	local function updateRobux()
		for _, entry in robuxButtons do
			if entry.Pass and RobuxConfig.Has(player, entry.Pass.Id) then
				entry.Buy.SetText("GEKAUFT")
				entry.Buy.SetColor(C.MutedBack, C.Good)
			end
		end
	end
	local function robuxCard(order, entry, isPass)
		local id = isPass and entry.PassId or entry.ProductId
		local card = shopCard({ LayoutOrder = order }, grid)
		local top = stage({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, STAGE_H) }, card, entry.Color, entry.Color)
		if entry.Items then
			local view = viewport({ Size = UDim2.fromScale(1, 1), ZIndex = 2 }, top)
			showWeapon(view, "Rifle", Cosmetics.Get(entry.Items[1]), (CARD_W - 16) / STAGE_H)
		elseif entry.Coins then
			UITheme.Coin(top, 70, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 2 })
		else
			label({ Size = UDim2.fromScale(1, 1), Text = entry.Spins and "×" .. entry.Spins or (isPass and (entry.Badge or entry.Name) or "2× XP"),
				TextSize = 46, Font = F.Display, TextColor3 = entry.Color, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2 }, top)
		end
		if entry.Tag then
			UITheme.Tag({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Text = entry.Tag, TextSize = 12,
				BackgroundColor3 = entry.Color, TextColor3 = C.PrimaryText, ZIndex = 3 }, top)
		end
		if not isPass and PaidRandom.IsRandomProduct(entry) then
			UITheme.Chunky({ Name = "Odds", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(96, 28), Color = C.Card,
				StrokeColor = entry.Color, Text = "CHANCEN", TextSize = 13 }, top, function()
				OddsPanel.Show("Glücksrad", OddsPanel.WheelRows())
			end)
		end
		label({ Position = UDim2.fromOffset(16, 188), Size = UDim2.new(1, -32, 0, 28), Text = entry.Name, TextSize = 22,
			Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		label({ Position = UDim2.fromOffset(16, 216), Size = UDim2.new(1, -32, 0, 44), Text = isPass and entry.Description
			or RobuxConfig.Describe(entry), TextSize = 12, Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top }, card)
		local buy = UITheme.Chunky({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -28, 0, 40), Color = id ~= 0 and C.Good or C.MutedBack,
			Text = id ~= 0 and ("R$ " .. entry.Robux) or "BALD", TextSize = 18, TextColor = id ~= 0 and C.PrimaryText or C.Muted }, card,
			function()
				if id == 0 or (isPass and RobuxConfig.Has(player, entry.Id)) then
					return
				end
				if isPass then
					MarketplaceService:PromptGamePassPurchase(player, id)
				else
					MarketplaceService:PromptProductPurchase(player, id)
				end
			end)
		table.insert(robuxButtons, { Buy = buy, Pass = isPass and entry or nil })
		-- echten Preis von Roblox holen
		if id ~= 0 then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id,
					isPass and Enum.InfoType.GamePass or Enum.InfoType.Product)
				if ok and info and info.PriceInRobux and buy.Button.Parent and not (isPass and RobuxConfig.Has(player, entry.Id)) then
					buy.SetText("R$ " .. info.PriceInRobux)
				end
			end)
		end
	end

	-- Reiter VERKAUFEN: eigene handelbare Skins (mit Stückzahl) ans System; erster Klick fragt nach, zweiter verkauft
	local sellInfo -- Zeile über dem Raster (Guthaben, Wert, Quote)
	local function sellCard(order, item, count, held)
		local rarity = Cosmetics.Rarities[item.Rarity]
		local value, price = RapConfig.Value(item.Id), RapConfig.SellPrice(item.Id)
		local card = shopCard({ LayoutOrder = order }, grid)
		local preview = stage({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 160) }, card,
			item.Color or rarity.Color, rarity.Color)
		local view = viewport({ Size = UDim2.fromScale(1, 1), ZIndex = 2 }, preview)
		showWeapon(view, "Rifle", item, (CARD_W - 16) / 160)
		rapBadge(card, value).Position = UDim2.new(1, -16, 0, 18)
		if count > 1 then
			UITheme.Tag({ Position = UDim2.fromOffset(10, 12), Text = "×" .. count, TextSize = 13, BackgroundColor3 = C.Secondary,
				TextColor3 = C.Text, ZIndex = 3 }, card)
		end
		label({ Position = UDim2.fromOffset(16, 178), Size = UDim2.new(1, -32, 0, 28), Text = upper(item.Name), TextSize = 24,
			Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		label({ Position = UDim2.fromOffset(16, 208), Size = UDim2.new(1, -32, 0, 16), Text = upper(rarity.Name), TextSize = 11,
			Font = F.Bold, TextColor3 = rarity.Color }, card)
		local free = count - held
		label({ Position = UDim2.fromOffset(16, 224), Size = UDim2.new(1, -32, 0, 16), TextSize = 11, Font = F.Bold,
			TextColor3 = held > 0 and C.Primary or C.Muted,
			Text = held > 0 and (held .. " AM STAND / IM TAUSCH  ·  " .. free .. " FREI") or ("SYSTEM ZAHLT " .. math.floor(RapConfig.SellRate * 100)
				.. " % DES WERTS") }, card)
		local confirmUntil = 0
		local sell
		sell = UITheme.Chunky({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -28, 0, 40), Color = free > 0 and C.Rap or C.MutedBack,
			Text = free > 0 and ("VERKAUFEN  ·  +" .. UITheme.FormatNumber(price) .. " RAP") or "ZURÜCKGELEGT", TextSize = 17,
			TextColor = free > 0 and C.PrimaryText or C.Muted }, card, function()
			if free <= 0 then
				return
			end
			if os.clock() < confirmUntil then
				confirmUntil = 0
				Remotes.ShopAction:FireServer("SellSkin", item.Id, 1)
				return
			end
			confirmUntil = os.clock() + 3
			sell.SetText("SICHER?  NOCHMAL KLICKEN")
			task.delay(3, function()
				if os.clock() >= confirmUntil and sell.Button.Parent then
					sell.SetText("VERKAUFEN  ·  +" .. UITheme.FormatNumber(price) .. " RAP")
				end
			end)
		end)
	end
	local function fillSell()
		local owned = Cosmetics.GetOwned(player)
		local held = reservedItems()
		local list = {}
		for id in owned do
			local item = Cosmetics.Get(id)
			if item and RapConfig.Tradeable(id) and RapConfig.Count(owned, id) > 0 then
				table.insert(list, item)
			end
		end
		table.sort(list, function(a, b)
			return RapConfig.Value(a.Id) > RapConfig.Value(b.Id)
		end)
		for order, item in list do
			sellCard(order, item, RapConfig.Count(owned, item.Id), math.floor(tonumber(held[item.Id]) or 0))
		end
		if #list == 0 then
			label({ Size = UDim2.fromOffset(PAGE_W, 60), Text = "Noch keine handelbaren Skins. Seltene Skins gibt es im Shop, am Glücksrad,"
				.. " im Login-Kalender, im Battle Pass und im MARKT.", TextSize = 15, Font = F.Medium, TextColor3 = C.Muted,
				TextWrapped = true, LayoutOrder = 1 }, grid)
		end
	end
	local function updateSellInfo()
		if sellInfo then
			sellInfo.Text = "GUTHABEN " .. UITheme.FormatNumber(player:GetAttribute("Rap") or 0) .. " RAP   ·   WERT DEINER SKINS "
				.. UITheme.FormatNumber(player:GetAttribute("RapValue") or 0) .. " RAP   ·   DAS SYSTEM ZAHLT SOFORT "
				.. math.floor(RapConfig.SellRate * 100) .. " %, IM MARKT BEKOMMST DU OFT MEHR"
		end
	end

	-- Karte eines Skins im Raster
	local function skinCard(order, item)
		local rarity = Cosmetics.Rarities[item.Rarity]
		local itemOffer = offerById[item.Id]
		local isOffer = itemOffer ~= nil
		local price = isOffer and itemOffer.Price or item.Price
		local card = shopCard({ Name = item.Id, LayoutOrder = order }, grid)
		local preview = stage({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, STAGE_H) }, card,
			item.Color or rarity.Color, rarity.Color)
		local view = viewport({ Size = UDim2.fromScale(1, 1), ZIndex = 2 }, preview)
		showSkin(view, item, (CARD_W - 16) / STAGE_H)
		UITheme.Tag({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Text = upper(rarity.Name),
			TextSize = 11, BackgroundColor3 = rarity.Color, TextColor3 = C.PrimaryText, ZIndex = 3 }, preview)
		-- Farbe des Skins als kleines Feld unten rechts
		local swatch = make("Frame", { Name = "Swatch", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -8),
			Size = UDim2.fromOffset(18, 18), BackgroundColor3 = item.Color or rarity.Color, BorderSizePixel = 0, ZIndex = 3 }, preview)
		UITheme.Corner(swatch, UITheme.Radius.Small)
		UITheme.Stroke(swatch, Color3.new(1, 1, 1), 1, 0.55)
		if isOffer then
			UITheme.Tag({ Name = "Discount", Position = UDim2.fromOffset(18, 18), Text = "-" .. itemOffer.Discount .. " %",
				TextSize = 14, BackgroundColor3 = SHOP_RED, TextColor3 = Color3.new(1, 1, 1), ZIndex = 4 }, card)
		end
		if RapConfig.Value(item.Id) then
			rapBadge(card, RapConfig.Value(item.Id)).Position = UDim2.new(1, -16, 0, 18)
		end
		label({ Position = UDim2.fromOffset(16, 186), Size = UDim2.new(1, -32, 0, 26), Text = upper(item.Name), TextSize = 22,
			Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd }, card)
		priceRow({ Position = UDim2.fromOffset(16, 218), Size = UDim2.fromOffset(0, 24) }, card, price,
			isOffer and itemOffer.OldPrice or nil, 22)
		local buy = UITheme.Chunky({ Name = "BuyButton", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -28, 0, 40), Color = C.MutedBack, Text = "", TextSize = 17 }, card, function()
			if not Cosmetics.GetOwned(player)[item.Id] then
				Remotes.ShopAction:FireServer("Buy", item.Id)
			end
		end)
		cards[item.Id] = { Buy = buy, Item = item, Price = price }
	end

	local selectTab -- aus tabs(): Reiter wechseln (Kacheln der Startseite)
	local countdown -- Restzeit des Angebots
	local sellBalance -- RAP-Guthaben auf der Kachel VERKAUFEN

	-- Kachel einer Kategorie auf der Startseite (ganze Fläche klickbar)
	local function categoryTile(x, y, w, h, title, sub, tabName, decorate)
		local tile = make("TextButton", { Name = "Tile_" .. tabName, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = SHOP_PANEL, BackgroundTransparency = 0.02, BorderSizePixel = 0, Text = "", AutoButtonColor = false },
			home)
		UITheme.Corner(tile, UITheme.Radius.XL)
		local stroke = UITheme.Stroke(tile, C.Border, 1)
		local bar = UITheme.AccentBar(tile, SHOP_RED, { Side = "Left", Thickness = 3, Visible = false })
		local area = make("Frame", { Name = "Stage", Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 0, h - 120),
			BackgroundColor3 = Color3.fromRGB(20, 21, 25), BorderSizePixel = 0, ClipsDescendants = true }, tile)
		UITheme.Corner(area, UITheme.Radius.Large)
		decorate(area, w - 24, h - 120)
		label({ Position = UDim2.new(0, 22, 1, -96), Size = UDim2.new(1, -44, 0, 34), Text = title, TextSize = 30,
			Font = F.Display }, tile)
		local subLabel = label({ Name = "Sub", Position = UDim2.new(0, 22, 1, -60), Size = UDim2.new(1, -130, 0, 18), Text = sub,
			TextSize = 14, Font = F.Medium, TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd }, tile)
		local open = UITheme.Tag({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -22), Text = "ÖFFNEN",
			TextSize = 14, BackgroundColor3 = C.MutedBack, TextColor3 = C.Text }, tile)
		tile.MouseEnter:Connect(function()
			tile.BackgroundColor3 = UITheme.Brighten(SHOP_PANEL, 0.04)
			stroke.Color, bar.Visible = SHOP_RED, true
			open.BackgroundColor3 = SHOP_RED
		end)
		tile.MouseLeave:Connect(function()
			tile.BackgroundColor3 = SHOP_PANEL
			stroke.Color, bar.Visible = C.Border, false
			open.BackgroundColor3 = C.MutedBack
		end)
		tile.Activated:Connect(function()
			selectTab(tabName)
		end)
		return tile, subLabel
	end

	-- Anzahl kaufbarer und eigener Skins eines Typs
	local function catalogCount(itemType)
		local owned, total, cheapest = Cosmetics.GetOwned(player), 0, math.huge
		local have = 0
		for _, item in Cosmetics.List(itemType) do
			if Cosmetics.ForSale(item) then
				total += 1
				cheapest = math.min(cheapest, item.Test and math.huge or item.Price)
				if owned[item.Id] then
					have += 1
				end
			end
		end
		return total, have, cheapest
	end

	local function fillHome()
		clear(home)
		cards = {}
		-- Angebot des Tages
		local OFFER_W = 720
		local panel = make("Frame", { Name = "Offer", Size = UDim2.fromOffset(OFFER_W, PAGE_H - 54), BackgroundColor3 = SHOP_PANEL,
			BackgroundTransparency = 0.02, BorderSizePixel = 0 }, home)
		UITheme.Corner(panel, UITheme.Radius.XL)
		if not offer then
			UITheme.Stroke(panel, C.Border, 1)
			label({ Size = UDim2.fromScale(1, 1), Text = "HEUTE KEIN ANGEBOT", TextSize = 22, Font = F.Display, TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Center }, panel)
		else
			local item = offer.Item
			local rarity = Cosmetics.Rarities[item.Rarity]
			UITheme.Stroke(panel, SHOP_RED, 1.5, 0.15)
			UITheme.AccentBar(panel, SHOP_RED, { Thickness = 4 })
			UITheme.Tag({ Position = UDim2.fromOffset(24, 22), Text = offer.Manual and "SONDERANGEBOT" or "ANGEBOT DES TAGES",
				TextSize = 16, BackgroundColor3 = SHOP_RED,
				TextColor3 = Color3.new(1, 1, 1) }, panel)
			label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -150, 0, 28), Size = UDim2.fromOffset(160, 16),
				Text = "ENDET IN", TextSize = 13, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, panel)
			countdown = label({ Name = "Countdown", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 18),
				Size = UDim2.fromOffset(120, 32), Text = ShopOffers.FormatLeft(offer.EndsAt - workspace:GetServerTimeNow()),
				TextSize = 28, Font = F.Display, TextXAlignment = Enum.TextXAlignment.Right }, panel)
			local preview = stage({ Position = UDim2.fromOffset(20, 68), Size = UDim2.new(1, -40, 0, 340) }, panel,
				item.Color or rarity.Color, rarity.Color)
			local view = viewport({ Size = UDim2.fromScale(1, 1), ZIndex = 2 }, preview)
			showSkin(view, item, 680 / 340)
			UITheme.Tag({ Name = "Discount", Position = UDim2.fromOffset(16, 16), Text = "-" .. offer.Discount .. " %",
				TextSize = 30, BackgroundColor3 = SHOP_RED, TextColor3 = Color3.new(1, 1, 1), ZIndex = 3 }, preview)
			if RapConfig.Value(item.Id) then
				rapBadge(preview, RapConfig.Value(item.Id)).Position = UDim2.new(1, -16, 0, 16)
			end
			label({ Position = UDim2.fromOffset(24, 424), Size = UDim2.new(1, -48, 0, 46), Text = upper(item.Name), TextSize = 44,
				Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd }, panel)
			local line = make("Frame", { Position = UDim2.fromOffset(24, 474), Size = UDim2.fromOffset(500, 20),
				BackgroundTransparency = 1 }, panel)
			make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, line)
			label({ Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Text = upper(rarity.Name), TextSize = 15,
				Font = F.Bold, TextColor3 = rarity.Color, LayoutOrder = 1 }, line)
			label({ Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
				Text = item.Type == "Agent" and "AGENTEN-SKIN" or "WAFFEN-SKIN", TextSize = 15, Font = F.Bold, TextColor3 = C.Muted,
				LayoutOrder = 2 }, line)
			priceRow({ Position = UDim2.fromOffset(24, 512), Size = UDim2.fromOffset(0, 44) }, panel, offer.Price, offer.OldPrice, 40)
			label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 526), Size = UDim2.fromOffset(260, 20),
				Text = "DU SPARST " .. UITheme.FormatNumber(offer.OldPrice - offer.Price) .. " MÜNZEN", TextSize = 15, Font = F.Bold,
				TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Right }, panel)
			local buy = UITheme.Chunky({ Name = "BuyButton", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20),
				Size = UDim2.new(1, -40, 0, 60), Color = SHOP_RED, Text = "", TextSize = 24 }, panel, function()
				if not Cosmetics.GetOwned(player)[item.Id] then
					Remotes.ShopAction:FireServer("Buy", item.Id)
				end
			end)
			cards[item.Id] = { Buy = buy, Item = item, Price = offer.Price }
		end

		-- Kategorien (2 × 2)
		local x0, gap = OFFER_W + 20, 20
		local w = math.floor((PAGE_W - x0 - gap) / 2)
		local h = math.floor((PAGE_H - 54 - gap) / 2)
		local weaponTotal, weaponHave, weaponFrom = catalogCount("Weapon")
		local agentTotal, agentHave, agentFrom = catalogCount("Agent")
		categoryTile(x0, 0, w, h, "WAFFEN-SKINS", weaponHave .. " VON " .. weaponTotal .. " IM BESITZ  ·  AB "
			.. UITheme.FormatNumber(weaponFrom) .. " MÜNZEN", "WAFFEN-SKINS", function(area, aw, ah)
			local item = showcase("Weapon")
			if item then
				local rarity = Cosmetics.Rarities[item.Rarity]
				local s = stage({ Size = UDim2.fromScale(1, 1) }, area, item.Color, rarity.Color)
				showWeapon(viewport({ Size = UDim2.fromScale(1, 1), ZIndex = 2 }, s), "Rifle", item, aw / ah, 0.8)
			end
		end)
		categoryTile(x0 + w + gap, 0, w, h, "AGENTEN-SKINS", agentHave .. " VON " .. agentTotal .. " IM BESITZ  ·  AB "
			.. UITheme.FormatNumber(agentFrom) .. " MÜNZEN", "AGENTEN-SKINS", function(area)
			local item = showcase("Agent")
			if item then
				local rarity = Cosmetics.Rarities[item.Rarity]
				local s = stage({ Size = UDim2.fromScale(1, 1) }, area, item.Color, rarity.Color)
				LobbyPages.ShowAgent(viewport({ Size = UDim2.fromScale(1, 1), ZIndex = 2 }, s), item)
			end
		end)
		categoryTile(x0, h + gap, w, h, "ROBUX", "MÜNZEN, PÄSSE UND BOOSTS", "ROBUX", function(area)
			local s = stage({ Size = UDim2.fromScale(1, 1) }, area, C.Gold, C.Gold)
			UITheme.Coin(s, 96, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.42, 0.5), ZIndex = 2 })
			UITheme.Coin(s, 64, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.6, 0.6), ZIndex = 3 })
		end)
		local _, sub = categoryTile(x0 + w + gap, h + gap, w, h, "VERKAUFEN", "", "VERKAUFEN", function(area)
			local s = stage({ Size = UDim2.fromScale(1, 1) }, area, C.Rap, C.Rap)
			UITheme.RapIcon(s, 110, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 2 })
		end)
		sellBalance = sub
		sellBalance.Text = "SKINS GEGEN RAP  ·  GUTHABEN " .. UITheme.FormatNumber(player:GetAttribute("Rap") or 0) .. " RAP"
		updateButtons()
	end

	local function fill()
		clear(grid)
		cards = {}
		robuxButtons = {}
		countdown = nil
		local order = 0
		home.Visible = currentType == "Home"
		grid.Visible = currentType ~= "Home"
		if sellInfo then
			sellInfo.Visible = currentType == "Sell"
		end
		if currentType == "Home" then
			fillHome()
			return
		end
		if currentType == "Sell" then
			updateSellInfo()
			fillSell()
			return
		end
		if currentType == "Robux" then
			for _, pass in RobuxConfig.Passes do
				order += 1
				robuxCard(order, pass, true)
			end
			for _, product in RobuxConfig.Products do
				if not PaidRandom.IsRandomProduct(product) or PaidRandom.OfferRandom(player) then
					order += 1
					robuxCard(order, product, false)
				end
			end
			updateRobux()
			return
		end
		-- Skins: Angebot zuerst, dann nach Seltenheit (legendär oben) und Preis
		local list = {}
		for _, item in Cosmetics.List(currentType) do
			if Cosmetics.ForSale(item) then
				table.insert(list, item)
			end
		end
		table.sort(list, function(a, b)
			local aOffer, bOffer = offerById[a.Id] ~= nil, offerById[b.Id] ~= nil
			if aOffer ~= bOffer then
				return aOffer
			end
			local ra, rb = RARITY_ORDER[a.Rarity] or 0, RARITY_ORDER[b.Rarity] or 0
			if ra ~= rb then
				return ra > rb
			end
			if a.Price ~= b.Price then
				return a.Price > b.Price
			end
			return a.Id < b.Id
		end)
		for i, item in list do
			skinCard(i, item)
		end
		updateButtons()
	end

	sellInfo = label({ Position = UDim2.fromOffset(0, 42), Size = UDim2.fromOffset(PAGE_W, 12), Text = "", TextSize = 11,
		Font = F.Bold, TextColor3 = C.Rap, Visible = false }, page)
	local HINTS = {
		Home = "WÄHLE, WAS DU KAUFEN MÖCHTEST",
		Weapon = "GEKAUFTE SKINS RÜSTEST DU UNTER LOADOUT AUS",
		Agent = "AGENTEN-SKINS RÜSTEST DU IM MENÜ UNTER SKINS AUS",
		Robux = "",
		Sell = "",
	}
	selectTab = tabs(page, { "START", "WAFFEN-SKINS", "AGENTEN-SKINS", "ROBUX", "VERKAUFEN" }, 0, 0, PAGE_W, function(name)
		currentType = ({ START = "Home", ["WAFFEN-SKINS"] = "Weapon", ["AGENTEN-SKINS"] = "Agent", ROBUX = "Robux",
			VERKAUFEN = "Sell" })[name]
		hint.Text = HINTS[currentType]
		fill()
	end, SHOP_RED)
	selectTab("START")

	-- Restzeit des Angebots jede Sekunde; neuer Tag = neues Angebot, Seite neu aufbauen
	-- Länder-Abfrage kommt erst nach dem Öffnen an: offener ROBUX-Reiter zeigt die Drehs dann nachträglich
	local randomOffered = PaidRandom.OfferRandom(player)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = workspace:GetServerTimeNow()
			local offered = PaidRandom.OfferRandom(player)
			if offered ~= randomOffered then
				randomOffered = offered
				if currentType == "Robux" then
					fill()
				end
			end
			if loadOffers() then
				fill()
			elseif countdown and offer then
				countdown.Text = ShopOffers.FormatLeft(offer.EndsAt - now)
			end
		end
	end)

	return { Refresh = function()
		if currentType == "Sell" then
			fill() -- Karten ändern sich mit dem Besitz (verkauft, Stückzahl)
		end
		updateButtons()
		updateRobux()
		updateSellInfo()
		if sellBalance then
			sellBalance.Text = "SKINS GEGEN RAP  ·  GUTHABEN " .. UITheme.FormatNumber(player:GetAttribute("Rap") or 0) .. " RAP"
		end
	end, Watch = robuxWatch({ Coins = true, Owned = true, Rap = true, RapValue = true, Reserved = true }) }
end

-- =====================================================================
-- LOADOUT
-- =====================================================================

-- goToShop(): Lobby auf die SHOP-Seite wechseln
function LobbyPages.Loadout(page, goToShop)
	local selected = WEAPON_ORDER[1] -- gewählte Waffe
	local STAGE_X, STAGE_W = 340, 720
	local RIGHT_X = STAGE_X + STAGE_W + 30
	local RIGHT_W = PAGE_W - RIGHT_X

	-- links: die Waffen
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 54), Size = UDim2.fromOffset(300, PAGE_H - 54),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Border,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, page)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	-- Mitte: Name, ausgerüsteter Skin und große Vorschau
	local title = label({ Position = UDim2.fromOffset(STAGE_X, -2), Size = UDim2.fromOffset(STAGE_W, 40), Text = "", TextSize = 40,
		Font = F.Display }, page)
	local equippedText = label({ Position = UDim2.fromOffset(STAGE_X, 40), Size = UDim2.fromOffset(STAGE_W, 16), Text = "",
		TextSize = 12, Font = F.Bold, TextColor3 = C.Muted }, page)
	local stage = UITheme.Card({ Position = UDim2.fromOffset(STAGE_X, 70), Size = UDim2.fromOffset(STAGE_W, PAGE_H - 70),
		BackgroundTransparency = 0.35 }, page)
	local view = viewport({ Size = UDim2.fromScale(1, 1), ZIndex = 3 }, stage)

	-- rechts: Reiter SKINS · AUFSÄTZE (Aufsätze nur bei Waffen), darunter die eigenen Skins bzw. die Aufsätze
	local rightMode = "SKINS"
	local selectRight -- vorab (Reiter ruft fillOptions)
	local options = make("Frame", { Position = UDim2.fromOffset(RIGHT_X, 54), Size = UDim2.fromOffset(RIGHT_W, PAGE_H - 200),
		BackgroundTransparency = 1 }, page)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(math.floor((RIGHT_W - 16) / 2), 60), CellPadding = UDim2.fromOffset(16, 12),
		SortOrder = Enum.SortOrder.LayoutOrder }, options)
	local hint = label({ Position = UDim2.fromOffset(RIGHT_X, PAGE_H - 120), Size = UDim2.fromOffset(RIGHT_W, 40), Text = "",
		TextSize = 13, Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, page)
	local shopButton = UITheme.Chunky({ Position = UDim2.fromOffset(RIGHT_X, PAGE_H - 60), Size = UDim2.fromOffset(220, 46),
		Color = C.Card, StrokeColor = C.Border, Text = "ZUM SHOP", TextSize = 20 }, page, goToShop)

	-- Aufsätze: pro Platz (Mündung, Lauf, Griff, Magazin) die Aufsätze als Knöpfe
	local attachPanel = make("Frame", { Position = UDim2.fromOffset(RIGHT_X, 54), Size = UDim2.fromOffset(RIGHT_W, PAGE_H - 54),
		BackgroundTransparency = 1, Visible = false }, page)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, attachPanel)
	-- Werte der Waffe mit Aufsätzen unten auf der Bühne: fünf Balken (Mitte = Grundwert der Waffe),
	-- beim Überfahren eines Aufsatzes zeigt ein farbiger Teil, wie sich der Wert ändern würde
	local statsPanel = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -32, 0, 70), BackgroundColor3 = C.Background, BackgroundTransparency = 0.25, ZIndex = 5 }, stage)
	UITheme.Corner(statsPanel, UITheme.Radius.Medium)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 8) }, statsPanel)
	make("UIGridLayout", { CellSize = UDim2.new(0.2, -8, 0, 54), CellPadding = UDim2.fromOffset(8, 0),
		SortOrder = Enum.SortOrder.LayoutOrder }, statsPanel)
	-- Wertung: höher = besser (Rückstoß/Streuung/Nachladen umgedreht)
	local STATS = {
		{ "RÜCKSTOSS", function(e) return 1 / e.Recoil end },
		{ "STREUUNG", function(e) return 1 / (e.Spread * e.HipSpread * (0.5 + e.MoveSpread * 0.5)) end },
		{ "REICHWEITE", function(e) return e.Range * (0.6 + e.Falloff * 0.4) end },
		{ "MAGAZIN", function(e) return e.Mag end },
		{ "NACHLADEN", function(e) return 1 / e.Reload end },
	}
	local statBars = {}
	for i, stat in STATS do
		local cell = make("Frame", { BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 5 }, statsPanel)
		label({ Size = UDim2.new(1, 0, 0, 14), Text = stat[1], TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 5 }, cell)
		local value = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.5, 0, 0, 14),
			Text = "", TextSize = 11, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 }, cell)
		local back = make("Frame", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = C.Border,
			BorderSizePixel = 0, ZIndex = 5 }, cell)
		UITheme.Corner(back, 3)
		local delta = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Good, BorderSizePixel = 0, ZIndex = 6 }, back)
		local fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = C.Text, BorderSizePixel = 0, ZIndex = 7 }, back)
		UITheme.Corner(fill, 3)
		statBars[i] = { Fill = fill, Delta = delta, Value = value, Rate = stat[2] }
	end

	local function percent(factor)
		local value = math.floor((factor - 1) * 100 + 0.5)
		return (value > 0 and "+" or "") .. value .. " %"
	end

	-- Wirkung mit einem anderen Aufsatz in einem Platz (für die Vorschau beim Überfahren)
	local function effectsWith(weaponName, slotId, itemId)
		local result = { Recoil = 1, Spread = 1, HipSpread = 1, MoveSpread = 1, Range = 1, Falloff = 1, Mag = 1, Reload = 1, Loud = 1 }
		local equipped = table.clone(AttachmentConfig.Equipped(player, weaponName))
		equipped[slotId] = itemId
		for _, id in equipped do
			local item = AttachmentConfig.Get(id)
			if item and (id == itemId or AttachmentConfig.Owns(player, weaponName, id)) then
				for key, factor in item.Effects do
					if type(factor) == "number" then
						result[key] *= factor
					end
				end
			end
		end
		return result
	end

	local function showStats(current, preview)
		for _, bar in statBars do
			local now = bar.Rate(current)
			local fillScale = math.clamp(0.5 * now, 0.05, 1)
			bar.Fill.Size = UDim2.fromScale(fillScale, 1)
			bar.Value.Text = percent(now)
			bar.Value.TextColor3 = now > 1.001 and C.Good or (now < 0.999 and C.Bad or C.Muted)
			if preview then
				local after = bar.Rate(preview)
				local afterScale = math.clamp(0.5 * after, 0.05, 1)
				local better = after > now + 0.001
				bar.Delta.Size = UDim2.fromScale(math.max(fillScale, afterScale), 1)
				bar.Delta.BackgroundColor3 = better and C.Good or C.Bad
				bar.Delta.Visible = math.abs(after - now) > 0.001
				bar.Fill.Size = UDim2.fromScale(math.min(fillScale, afterScale), 1)
				bar.Value.Text = percent(after)
				bar.Value.TextColor3 = better and C.Good or (after < now - 0.001 and C.Bad or C.Muted)
			else
				bar.Delta.Visible = false
			end
		end
	end

	-- Info-Karte neben dem überfahrenen (bzw. mit dem Controller gewählten) Aufsatz: Symbol, Name, Platz,
	-- Vorteile/Nachteile und die fünf Werte der Waffe mit diesem Aufsatz (grün besser, rot schlechter)
	local TIP_W, TIP_H = 310, 352
	local tip = UITheme.Card({ Size = UDim2.fromOffset(TIP_W, TIP_H), ZIndex = 30, Visible = false, BackgroundTransparency = 0.02 },
		page)
	local tipIcon = make("Frame", { Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = C.Background, BackgroundTransparency = 0.2 }, tip)
	UITheme.Corner(tipIcon, UITheme.Radius.Small)
	local tipName = label({ Position = UDim2.fromOffset(72, 14), Size = UDim2.fromOffset(TIP_W - 86, 26), Text = "", TextSize = 22,
		Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd }, tip)
	local tipSlot = label({ Position = UDim2.fromOffset(72, 42), Size = UDim2.fromOffset(TIP_W - 86, 16), Text = "", TextSize = 11,
		Font = F.Bold, TextColor3 = C.Muted }, tip)
	local tipLines = label({ Position = UDim2.fromOffset(14, 72), Size = UDim2.fromOffset(TIP_W - 28, 52), Text = "", TextSize = 13,
		Font = F.Medium, RichText = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, tip)
	make("Frame", { Position = UDim2.fromOffset(14, 130), Size = UDim2.fromOffset(TIP_W - 28, 1), BackgroundColor3 = C.Border,
		BorderSizePixel = 0 }, tip)
	label({ Position = UDim2.fromOffset(14, 138), Size = UDim2.fromOffset(TIP_W - 28, 14), Text = "WERTE DER WAFFE MIT DIESEM AUFSATZ",
		TextSize = 10, Font = F.Bold, TextColor3 = C.Muted }, tip)
	local tipBars = {}
	for i, stat in STATS do
		local y = 160 + (i - 1) * 30
		label({ Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(120, 14), Text = stat[1], TextSize = 11, Font = F.Bold,
			TextColor3 = C.Text }, tip)
		local value = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, y), Size = UDim2.fromOffset(120, 14),
			Text = "", TextSize = 12, Font = F.Bold, TextXAlignment = Enum.TextXAlignment.Right }, tip)
		local back = make("Frame", { Position = UDim2.fromOffset(14, y + 17), Size = UDim2.fromOffset(TIP_W - 28, 5),
			BackgroundColor3 = C.Border, BorderSizePixel = 0 }, tip)
		UITheme.Corner(back, 3)
		local delta = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Good, BorderSizePixel = 0 }, back)
		UITheme.Corner(delta, 3)
		local fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = C.Text, BorderSizePixel = 0 }, back)
		UITheme.Corner(fill, 3)
		tipBars[i] = { Fill = fill, Delta = delta, Value = value, Rate = stat[2] }
	end
	local tipFooter = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = C.Background, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, tip)
	UITheme.Corner(tipFooter, UITheme.Radius.XL)
	local tipState = label({ Size = UDim2.fromScale(1, 1), Text = "", TextSize = 12, Font = F.Bold,
		TextXAlignment = Enum.TextXAlignment.Center }, tipFooter)

	local tipFor = nil -- Kachel, zu der die Karte gerade gehört
	local function showTip(tile, item, slotName, current, preview, stateText, stateColor)
		tipFor = tile
		tipIcon:ClearAllChildren()
		UITheme.Corner(tipIcon, UITheme.Radius.Small)
		local icon = AttachmentIcons.Build(tipIcon, item.Id, 40, C.Text)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		tipName.Text = upper(item.Name)
		tipSlot.Text = "AUFSATZ  ·  " .. upper(slotName)
		local lines = {}
		for _, pro in AttachmentConfig.Pros(item, selected) do
			table.insert(lines, '<font color="#' .. C.Good:ToHex() .. '">+ ' .. pro .. "</font>")
		end
		for _, con in item.Cons or {} do
			table.insert(lines, '<font color="#' .. C.Bad:ToHex() .. '">− ' .. con .. "</font>")
		end
		tipLines.Text = #lines > 0 and table.concat(lines, "\n") or "Keine Nachteile."
		for _, bar in tipBars do
			local now, after = bar.Rate(current), bar.Rate(preview)
			local nowScale, afterScale = math.clamp(0.5 * now, 0.05, 1), math.clamp(0.5 * after, 0.05, 1)
			local better = after > now + 0.001
			local changed = math.abs(after - now) > 0.001
			bar.Fill.Size = UDim2.fromScale(math.min(nowScale, afterScale), 1)
			bar.Delta.Visible = changed
			bar.Delta.Size = UDim2.fromScale(math.max(nowScale, afterScale), 1)
			bar.Delta.BackgroundColor3 = better and C.Good or C.Bad
			bar.Value.Text = changed and (percent(now) .. "  →  " .. percent(after)) or percent(after)
			bar.Value.TextColor3 = not changed and C.Muted or (better and C.Good or C.Bad)
		end
		tipState.Text = stateText
		tipState.TextColor3 = stateColor
		-- rechts neben die Kachel, sonst links daneben; nicht über den Seitenrand hinaus
		local scale = page.AbsoluteSize.X / PAGE_W
		local rel = (tile.AbsolutePosition - page.AbsolutePosition) / scale
		local tileSize = tile.AbsoluteSize / scale
		local x = rel.X + tileSize.X + 10
		if x + TIP_W > PAGE_W + 36 then
			x = rel.X - TIP_W - 10
		end
		tip.Position = UDim2.fromOffset(x, math.clamp(rel.Y - 20, 0, PAGE_H - TIP_H))
		tip.Visible = true
	end
	local function hideTip(tile)
		if tipFor == tile then
			tip.Visible = false
			tipFor = nil
		end
	end

	-- Aufsätze in zwei Stufen: Übersicht mit einem Feld pro Platz (leer = "+", sonst Symbol des Aufsatzes);
	-- ein Klick öffnet die Auswahl für diesen Platz (Ablegen + die Aufsätze mit Kaufen/Ausrüsten).
	local attachSlot = nil -- nil = Übersicht, sonst Platz-Id

	-- Zustand eines Aufsatzes: Text, Farbe und kurze Erklärung für die Info-Karte
	local function itemState(weaponName, item, isOn)
		local owned = AttachmentConfig.Owns(player, weaponName, item.Id)
		if isOn then
			return "AUSGERÜSTET", C.Primary, "AUSGERÜSTET  ·  KLICKEN ZUM ABLEGEN"
		elseif owned then
			return "GEKAUFT", C.Good, "GEKAUFT  ·  KLICKEN ZUM AUSRÜSTEN"
		end
		local price = UITheme.FormatNumber(item.Price) .. " MÜNZEN"
		return price, coins() >= item.Price and C.Text or C.Bad, price .. "  ·  KLICKEN ZUM KAUFEN"
	end

	local function fillAttachments()
		tip.Visible = false
		tipFor = nil
		clear(attachPanel)
		local weaponName = selected
		local equipped = AttachmentConfig.Equipped(player, weaponName)
		local currentEffects = AttachmentConfig.Effects(player, weaponName)
		local function equippedItem(slotId)
			local id = equipped[slotId]
			return id and AttachmentConfig.Fits(weaponName, id) and AttachmentConfig.Owns(player, weaponName, id)
				and AttachmentConfig.Get(id) or nil
		end

		-- quadratisches Feld links in einer Zeile: Symbol oder "+"
		local function iconBox(parent, size, item, color)
			local box = make("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = C.Background, BackgroundTransparency = 0.2 }, parent)
			UITheme.Corner(box, UITheme.Radius.Medium)
			if item then
				local icon = AttachmentIcons.Build(box, item.Id, size - 16, color)
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.Position = UDim2.fromScale(0.5, 0.5)
			else
				UITheme.Stroke(box, C.Border, 1, 0.2)
				label({ Size = UDim2.fromScale(1, 1), Text = "+", TextSize = 44, Font = F.Display, TextColor3 = C.Muted,
					TextXAlignment = Enum.TextXAlignment.Center }, box)
			end
			return box
		end

		if not attachSlot then
			-- Übersicht: ein Feld pro Platz
			label({ Size = UDim2.fromOffset(RIGHT_W, 18), Text = "PLATZ ANKLICKEN, UM EINEN AUFSATZ AUSZUWÄHLEN", TextSize = 11,
				Font = F.Bold, TextColor3 = C.Muted, LayoutOrder = 0 }, attachPanel)
			for order, slot in AttachmentConfig.SlotsFor(weaponName) do -- nur Plätze mit passenden Aufsätzen
				local item = equippedItem(slot.Id)
				local row = make("TextButton", { Size = UDim2.fromOffset(RIGHT_W, 104), BackgroundColor3 = C.Panel,
					BackgroundTransparency = 0.05, Text = "", AutoButtonColor = false, LayoutOrder = order }, attachPanel)
				UITheme.Corner(row, UITheme.Radius.Medium)
				local stroke = UITheme.Stroke(row, item and C.Primary or C.Border, 1, item and 0.3 or 0.35)
				iconBox(row, 84, item, C.Primary)
				label({ Position = UDim2.fromOffset(110, 14), Size = UDim2.new(1, -150, 0, 16), Text = upper(slot.Name), TextSize = 12,
					Font = F.Bold, TextColor3 = C.Muted }, row)
				label({ Position = UDim2.fromOffset(110, 32), Size = UDim2.new(1, -150, 0, 28), Text = item and upper(item.Name) or "LEER",
					TextSize = 26, Font = F.Display, TextColor3 = item and C.Text or C.Muted, TextTruncate = Enum.TextTruncate.AtEnd }, row)
				local summary = {}
				for _, pro in AttachmentConfig.Pros(item, weaponName) do
					table.insert(summary, '<font color="#' .. C.Good:ToHex() .. '">+ ' .. pro .. "</font>")
				end
				for _, con in item and item.Cons or {} do
					table.insert(summary, '<font color="#' .. C.Bad:ToHex() .. '">− ' .. con .. "</font>")
				end
				label({ Position = UDim2.fromOffset(110, 64), Size = UDim2.new(1, -150, 0, 30),
					Text = item and table.concat(summary, "   ") or "Noch kein Aufsatz auf diesem Platz", TextSize = 12, Font = F.Medium,
					RichText = true, TextWrapped = true, TextColor3 = C.Muted, TextYAlignment = Enum.TextYAlignment.Top }, row)
				label({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(24, 40),
					Text = "›", TextSize = 34, Font = F.Display, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, row)
				row.MouseEnter:Connect(function()
					stroke.Transparency = 0
					stroke.Color = C.Text
				end)
				row.MouseLeave:Connect(function()
					stroke.Transparency = item and 0.3 or 0.35
					stroke.Color = item and C.Primary or C.Border
				end)
				row.Activated:Connect(function()
					attachSlot = slot.Id
					fillAttachments()
					InputActions.Focus(attachPanel)
				end)
			end
			showStats(currentEffects)
			return
		end

		-- Auswahl für einen Platz: Zurück, Ablegen, dann die Aufsätze
		local slot
		for _, entry in AttachmentConfig.Slots do
			if entry.Id == attachSlot then
				slot = entry
			end
		end
		local current = equippedItem(slot.Id)
		local header = make("Frame", { Size = UDim2.fromOffset(RIGHT_W, 44), BackgroundTransparency = 1, LayoutOrder = 0 }, attachPanel)
		UITheme.Chunky({ Size = UDim2.fromOffset(120, 40), Color = C.Card, StrokeColor = C.Border, Text = "‹  ZURÜCK", TextSize = 16 },
			header, function()
				attachSlot = nil
				fillAttachments()
				InputActions.Focus(attachPanel)
			end)
		label({ Position = UDim2.fromOffset(136, 0), Size = UDim2.new(1, -136, 1, 0), Text = upper(slot.Name), TextSize = 30,
			Font = F.Display }, header)

		local rows = {}
		if current then
			table.insert(rows, { Remove = true })
		end
		local items = AttachmentConfig.ForSlot(slot.Id, weaponName) -- nur, was auf diese Waffe passt
		table.sort(items, function(x, y) -- günstigste zuerst
			return x.Price < y.Price
		end)
		for _, item in items do
			table.insert(rows, { Item = item })
		end
		for order, entry in rows do
			local item = entry.Item
			local isOn = item ~= nil and current ~= nil and current.Id == item.Id
			local row = make("TextButton", { Name = entry.Remove and "Att_Remove" or ("Att_" .. item.Id),
				Size = UDim2.fromOffset(RIGHT_W, entry.Remove and 56 or 104),
				BackgroundColor3 = isOn and C.Secondary or C.Panel, BackgroundTransparency = 0.05, Text = "", AutoButtonColor = false,
				LayoutOrder = order }, attachPanel)
			UITheme.Corner(row, UITheme.Radius.Medium)
			local stroke = UITheme.Stroke(row, isOn and C.Primary or C.Border, isOn and 2 or 1, isOn and 0 or 0.35)
			if entry.Remove then
				label({ Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -32, 1, 0), Text = "–  KEIN AUFSATZ (ABLEGEN)",
					TextSize = 18, Font = F.Display, TextColor3 = C.Muted }, row)
				row.Activated:Connect(function()
					WeaponEffects.ActionSound("AttachClick")
					Remotes.ShopAction:FireServer("ToggleAttachment", weaponName, current.Id)
				end)
			else
				local owned = AttachmentConfig.Owns(player, weaponName, item.Id)
				iconBox(row, 84, item, isOn and C.Primary or (owned and C.Text or C.Muted))
				label({ Position = UDim2.fromOffset(110, 12), Size = UDim2.new(1, -124, 0, 28), Text = upper(item.Name), TextSize = 24,
					Font = F.Display, TextColor3 = isOn and C.Primary or C.Text, TextTruncate = Enum.TextTruncate.AtEnd }, row)
				local lines = {}
				for _, pro in AttachmentConfig.Pros(item, weaponName) do
					table.insert(lines, '<font color="#' .. C.Good:ToHex() .. '">+ ' .. pro .. "</font>")
				end
				for _, con in item.Cons or {} do
					table.insert(lines, '<font color="#' .. C.Bad:ToHex() .. '">− ' .. con .. "</font>")
				end
				label({ Position = UDim2.fromOffset(110, 42), Size = UDim2.new(1, -124, 0, 32), Text = table.concat(lines, "\n"),
					TextSize = 12, Font = F.Medium, RichText = true, TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top }, row)
				local stateText, stateColor, tipText = itemState(weaponName, item, isOn)
				local state = make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10),
					Size = UDim2.fromOffset(150, 24), BackgroundColor3 = isOn and C.Primary or C.Background,
					BackgroundTransparency = isOn and 0 or 0.2 }, row)
				UITheme.Corner(state, UITheme.Radius.Small)
				label({ Size = UDim2.fromScale(1, 1), Text = stateText, TextSize = 11, Font = F.Bold,
					TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = isOn and C.PrimaryText or stateColor }, state)
				local function enter()
					stroke.Transparency = 0
					stroke.Color = isOn and C.Primary or C.Text
					local preview = effectsWith(weaponName, slot.Id, if isOn then nil else item.Id) -- angelegt: Werte ohne ihn
					showStats(currentEffects, preview)
					showTip(row, item, slot.Name, currentEffects, preview, tipText, stateColor)
				end
				local function leave()
					stroke.Transparency = isOn and 0 or 0.35
					stroke.Color = isOn and C.Primary or C.Border
					showStats(currentEffects)
					hideTip(row)
				end
				row.MouseEnter:Connect(enter)
				row.MouseLeave:Connect(leave)
				row.SelectionGained:Connect(enter) -- Controller
				row.SelectionLost:Connect(leave)
				row.Activated:Connect(function()
					if owned then
						WeaponEffects.ActionSound("AttachClick")
					end
					Remotes.ShopAction:FireServer(owned and "ToggleAttachment" or "BuyAttachment", weaponName, item.Id)
				end)
			end
		end
		showStats(currentEffects)
	end

	local fillList -- vorab, weil sich Liste und Skins gegenseitig neu aufbauen

	local function fillOptions()
		-- Gamepad: lag die Auswahl auf der Seite, nach dem Neuaufbau den gleichnamigen Knopf wieder wählen
		local selectedNow = game:GetService("GuiService").SelectedObject
		local hadFocus = selectedNow ~= nil and selectedNow:IsDescendantOf(page)
		local showAttachments = rightMode == "AUFSÄTZE"
		attachPanel.Visible = showAttachments
		if not showAttachments then
			tip.Visible = false
		end
		options.Visible = not showAttachments
		hint.Visible = not showAttachments
		shopButton.Visible = not showAttachments
		statsPanel.Visible = showAttachments
		if showAttachments then
			fillAttachments()
		end
		clear(options)
		local owned = Cosmetics.GetOwned(player)
		local equipped = Cosmetics.GetEquipped(player)
		local slot = "W:" .. selected
		local current = equipped[slot]
		if current and not owned[current] then
			current = nil
		end
		local entries = { { Id = nil, Name = "Standard", Sub = "STANDARD", Color = C.Muted } }
		for _, item in Cosmetics.List("Weapon") do
			if owned[item.Id] and not item.Mastery then
				local rarity = Cosmetics.Rarities[item.Rarity]
				table.insert(entries, { Id = item.Id, Name = item.Name, Sub = item.Creator and "CREATOR" or upper(rarity.Name),
					Color = item.Creator and CREATOR_COLOR or rarity.Color })
			end
		end
		local ownedCount = #entries - 1
		-- Meisterschaft: alle Tarnungen dieser Waffe, gesperrte mit Kill-Fortschritt
		if MasteryConfig.HasMastery(selected) then
			local kills = MasteryConfig.Kills(player, selected)
			for _, tier in MasteryConfig.Tiers do
				local id = MasteryConfig.ItemId(selected, tier.Id)
				local rarity = Cosmetics.Rarities[tier.Rarity]
				if owned[id] then
					table.insert(entries, { Id = id, Name = tier.Name, Sub = "MEISTERSCHAFT", Color = rarity.Color })
				else
					table.insert(entries, { Id = id, Name = tier.Name, Color = rarity.Color, Locked = true,
						Sub = "GESPERRT · " .. math.min(kills, tier.Kills) .. "/" .. tier.Kills .. " KILLS",
						Progress = math.clamp(kills / tier.Kills, 0, 1) })
				end
			end
		end
		local currentName = "Standard"
		for i, entry in entries do
			local isOn = entry.Id == current
			if isOn then
				currentName = entry.Name
			end
			local option = UITheme.Chunky({ Name = "Skin_" .. (entry.Id or "Standard"), LayoutOrder = i, Size = UDim2.fromOffset(200, 60), Color = isOn and C.Secondary or C.Panel,
				StrokeColor = isOn and C.Primary or entry.Color, Text = "" }, options, function()
				if entry.Id then -- gesperrte Tarnung: der Server sagt, wie viele Kills fehlen
					Remotes.ShopAction:FireServer("Equip", entry.Id, selected)
				else
					Remotes.ShopAction:FireServer("Unequip", slot)
				end
			end)
			option.Stroke.Transparency = isOn and 0 or 0.5
			label({ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 24), Text = upper(entry.Name), TextSize = 21,
				Font = F.Display, TextColor3 = isOn and C.Primary or (entry.Locked and C.Muted or C.Text),
				TextTruncate = Enum.TextTruncate.AtEnd }, option.Face)
			label({ Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 14), Text = isOn and "AUSGERÜSTET" or entry.Sub,
				TextSize = 10, Font = F.Bold, TextColor3 = isOn and C.Primary or entry.Color }, option.Face)
			if entry.Locked then
				-- Fortschritt bis zur Tarnung als dünner Balken unten
				option.Stroke.Transparency = 0.75
				local track = make("Frame", { Position = UDim2.new(0, 14, 1, -9), Size = UDim2.new(1, -28, 0, 3),
					BackgroundColor3 = C.Background, BorderSizePixel = 0 }, option.Face)
				make("Frame", { Size = UDim2.fromScale(entry.Progress, 1), BackgroundColor3 = entry.Color, BorderSizePixel = 0 }, track)
			end
		end
		if MasteryConfig.HasMastery(selected) then
			hint.Text = "Weitere Skins gibt es im SHOP. Meisterschafts-Tarnungen schaltest du mit Kills mit dieser Waffe frei."
		else
			hint.Text = ownedCount == 0 and "Noch keine Skins dafür – im SHOP gibt es Waffen-Skins."
				or "Weitere Skins gibt es im SHOP."
		end

		-- große Vorschau mit dem ausgerüsteten Skin
		title.Text = upper(WeaponConfig.Get(selected).DisplayName)
		showWeapon(view, selected, Cosmetics.WeaponSkin(player, nil, selected), STAGE_W / (PAGE_H - 70), 0.75,
			AttachmentConfig.EquippedList(player, selected))
		equippedText.Text = "AUSGERÜSTET: " .. upper(currentName)
		if hadFocus then
			InputActions.Refocus(page)
		end
	end

	fillList = function()
		clear(list)
		for i, name in WEAPON_ORDER do
			local text = WeaponConfig.Get(name).DisplayName
			local on = name == selected
			local row = UITheme.Chunky({ Size = UDim2.new(1, -8, 0, 46), LayoutOrder = i, Color = on and C.Secondary or C.Panel,
				StrokeColor = on and C.Primary or C.Border, Text = upper(text), TextSize = 20, TextColor = on and C.Primary or C.Text,
				TextXAlignment = Enum.TextXAlignment.Left }, list, function()
				selected = name
				attachSlot = nil -- andere Waffe: Aufsätze wieder in der Übersicht
				fillList()
				fillOptions()
			end)
			row.Stroke.Transparency = on and 0.3 or 0.6
			UITheme.AccentBar(row.Face, C.Primary, { Side = "Left", Visible = on })
		end
	end

	selectRight = tabs(page, { "SKINS", "AUFSÄTZE" }, RIGHT_X, 0, RIGHT_W, function(name)
		rightMode = name
		fillOptions()
	end)
	-- links nur die Waffen (Agenten haben keine Skins): ein Reiter als Überschrift
	tabs(page, { "WAFFEN" }, 0, 0, 300, function() end)("WAFFEN")
	fillList()
	selectRight("AUFSÄTZE") -- Waffen öffnen mit den Aufsätzen
	return { Refresh = fillOptions, Watch = { Owned = true, Equipped = true, Attachments = true, Coins = true, Stats = true } }
end

-- =====================================================================
-- BATTLE PASS
-- =====================================================================

function LobbyPages.Pass(page)
	local CARD_W, CARD_H, GAP = 176, 356, 12
	local max = #PassConfig.Tiers

	label({ Position = UDim2.fromOffset(0, -4), Size = UDim2.fromOffset(900, 46), Text = upper(PassConfig.SeasonName), TextSize = 42,
		Font = F.Display }, page)
	label({ Position = UDim2.fromOffset(0, 44), Size = UDim2.fromOffset(900, 16),
		Text = "KOSTENLOS · JEDE STUFE SCHALTET IHRE BELOHNUNG AUTOMATISCH FREI", TextSize = 11, Font = F.Bold,
		TextColor3 = C.Muted }, page)
	local tierLabel = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -4), Size = UDim2.fromOffset(400, 46),
		Text = "", TextSize = 42, Font = F.Display, TextColor3 = C.Primary, TextXAlignment = Enum.TextXAlignment.Right }, page)
	local xpLabel = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 44), Size = UDim2.fromOffset(500, 16),
		Text = "", TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right }, page)
	local barBack = make("Frame", { Position = UDim2.fromOffset(0, 74), Size = UDim2.fromOffset(PAGE_W, 4), BackgroundColor3 = C.Background,
		BorderSizePixel = 0 }, page)
	local bar = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Primary, BorderSizePixel = 0 }, barBack)

	-- alle Stufen nebeneinander (waagerecht scrollbar)
	local strip = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 98), Size = UDim2.fromOffset(PAGE_W, CARD_H + 14),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Border,
		ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.fromOffset(max * (CARD_W + GAP) - GAP, 0) }, page)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder }, strip)
	local cards = {}
	for tier, reward in PassConfig.Tiers do
		local item = reward.Item and Cosmetics.Get(reward.Item)
		local rarity = item and Cosmetics.Rarities[item.Rarity]
		local card = make("Frame", { Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.1,
			BorderSizePixel = 0, LayoutOrder = tier }, strip)
		UITheme.Corner(card, UITheme.Radius.XL)
		local baseColor, baseTransparency = rarity and rarity.Color or C.Border, rarity and 0.35 or 0
		local stroke = UITheme.Stroke(card, baseColor, 1, baseTransparency)
		if rarity then
			UITheme.AccentBar(card, rarity.Color)
		end
		label({ Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 16), Text = "STUFE " .. tier, TextSize = 11, Font = F.Bold,
			TextColor3 = C.Muted }, card)
		if item then
			local view = viewport({ Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 170) }, card)
			showWeapon(view, "Rifle", item, CARD_W / 170)
			label({ Position = UDim2.fromOffset(14, 212), Size = UDim2.new(1, -28, 0, 52), Text = upper(item.Name), TextSize = 22,
				Font = F.Display, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, card)
			label({ Position = UDim2.fromOffset(14, 268), Size = UDim2.new(1, -28, 0, 14), Text = upper(rarity.Name) .. "  ·  EXKLUSIV",
				TextSize = 10, Font = F.Bold, TextColor3 = rarity.Color }, card)
		else
			UITheme.Coin(card, 64, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86) })
			label({ Position = UDim2.fromOffset(14, 212), Size = UDim2.new(1, -28, 0, 28), Text = tostring(reward.Coins), TextSize = 30,
				Font = F.Display, TextColor3 = C.Gold }, card)
			label({ Position = UDim2.fromOffset(14, 268), Size = UDim2.new(1, -28, 0, 14), Text = "MÜNZEN", TextSize = 10,
				Font = F.Bold, TextColor3 = C.Muted }, card)
		end
		local state = label({ Position = UDim2.fromOffset(14, CARD_H - 34), Size = UDim2.new(1, -28, 0, 18), Text = "", TextSize = 11,
			Font = F.Bold }, card)
		cards[tier] = { Card = card, Stroke = stroke, State = state, BaseColor = baseColor, BaseTransparency = baseTransparency }
	end

	-- unten links: nächste Belohnung mit Vorschau; rechts: wie man Pass-XP sammelt (drei Kacheln)
	local INFO_Y = 98 + CARD_H + 30
	local INFO_H = PAGE_H - INFO_Y
	local nextCard = UITheme.Card({ Position = UDim2.fromOffset(0, INFO_Y), Size = UDim2.fromOffset(740, INFO_H) }, page)
	label({ Position = UDim2.fromOffset(24, 20), Size = UDim2.fromOffset(400, 16), Text = "NÄCHSTE BELOHNUNG", TextSize = 12,
		Font = F.Bold, TextColor3 = C.Muted, ZIndex = 3 }, nextCard)
	local nextName = label({ Position = UDim2.fromOffset(24, 42), Size = UDim2.fromOffset(470, 44), Text = "", TextSize = 42,
		Font = F.Display, ZIndex = 3, TextTruncate = Enum.TextTruncate.AtEnd }, nextCard)
	local nextInfo = label({ Position = UDim2.fromOffset(24, 92), Size = UDim2.fromOffset(470, 18), Text = "", TextSize = 13,
		Font = F.Medium, TextColor3 = C.Muted, ZIndex = 3 }, nextCard)
	local nextBack = make("Frame", { Position = UDim2.fromOffset(24, INFO_H - 44), Size = UDim2.fromOffset(470, 4),
		BackgroundColor3 = C.Background, BorderSizePixel = 0, ZIndex = 3 }, nextCard)
	local nextBar = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Primary, BorderSizePixel = 0, ZIndex = 3 }, nextBack)
	local preview = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(200, INFO_H - 40), BackgroundColor3 = C.Background, BackgroundTransparency = 0.4, BorderSizePixel = 0,
		ZIndex = 3 }, nextCard)
	UITheme.Corner(preview, UITheme.Radius.Small)
	local shownPreview = nil

	local howCard = UITheme.Card({ Position = UDim2.fromOffset(760, INFO_Y), Size = UDim2.fromOffset(PAGE_W - 760, INFO_H) }, page)
	label({ Position = UDim2.fromOffset(24, 20), Size = UDim2.fromOffset(400, 16), Text = "SO SAMMELST DU PASS-XP", TextSize = 12,
		Font = F.Bold, TextColor3 = C.Muted, ZIndex = 3 }, howCard)
	local tileW = math.floor((PAGE_W - 760 - 48 - 2 * 16) / 3)
	-- 1 : 1 zählt nur, was über ProgressService.AddXP läuft (Zombies, Kills, Medaillen); EP der offenen Welt (Nester,
	-- Konvois, Missionen ...) gehen nur ins Spielerlevel
	for i, entry in { { "1 : 1", "XP für Zombies, Kills und Medaillen zählt auch für den Pass" },
		{ "+" .. PassConfig.QuestXP, "Pass-XP pro abgeholtem täglichen Auftrag" },
		{ UITheme.FormatNumber(PassConfig.XPPerTier), "Pass-XP pro Stufe – die Belohnung gibt es sofort" } } do
		local x = 24 + (i - 1) * (tileW + 16)
		make("Frame", { Position = UDim2.fromOffset(x, 54), Size = UDim2.fromOffset(2, 40), BackgroundColor3 = C.Primary,
			BorderSizePixel = 0, ZIndex = 3 }, howCard)
		label({ Position = UDim2.fromOffset(x + 16, 48), Size = UDim2.fromOffset(tileW - 16, 44), Text = entry[1], TextSize = 44,
			Font = F.Display, ZIndex = 3 }, howCard)
		label({ Position = UDim2.fromOffset(x + 16, 98), Size = UDim2.fromOffset(tileW - 20, 60), Text = entry[2], TextSize = 13,
			Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3 }, howCard)
	end

	local function refresh()
		local xp = player:GetAttribute("PassXP") or 0
		local tier, progress = PassConfig.TierFromXP(xp)
		tierLabel.Text = "STUFE " .. tier .. " / " .. max
		bar.Size = UDim2.fromScale(math.clamp(tier >= max and 1 or (tier + progress) / max, 0, 1), 1)
		xpLabel.Text = tier >= max and "PASS ABGESCHLOSSEN"
			or (UITheme.FormatNumber(progress * PassConfig.XPPerTier) .. " / " .. UITheme.FormatNumber(PassConfig.XPPerTier)
				.. " XP BIS STUFE " .. (tier + 1))
		for t, entry in cards do
			local reached = t <= tier
			local isNext = t == tier + 1
			entry.State.Text = reached and "FREIGESCHALTET" or (isNext and "NÄCHSTE STUFE" or "GESPERRT")
			entry.State.TextColor3 = reached and C.Good or (isNext and C.Primary or C.Muted)
			entry.Stroke.Color = isNext and C.Primary or entry.BaseColor
			entry.Stroke.Thickness = isNext and 2 or 1
			entry.Stroke.Transparency = isNext and 0 or entry.BaseTransparency
			entry.Card.BackgroundColor3 = reached and Color3.fromRGB(26, 32, 28) or C.Panel
		end
		-- nächste Belohnung mit Vorschau (Skin in 3D, Münzen als Münze)
		local reward = PassConfig.Tiers[tier + 1]
		local item = reward and reward.Item and Cosmetics.Get(reward.Item)
		if reward then
			nextName.Text = item and upper(item.Name) or (reward.Coins .. " MÜNZEN")
			nextInfo.Text = "Stufe " .. (tier + 1) .. "  ·  noch " .. UITheme.FormatNumber((1 - progress) * PassConfig.XPPerTier) .. " Pass-XP"
			nextBar.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
		else
			nextName.Text = "ALLES FREIGESCHALTET"
			nextInfo.Text = "Du hast den Pass dieser Saison abgeschlossen."
			nextBar.Size = UDim2.fromScale(1, 1)
		end
		local previewKey = item and item.Id or (reward and "coins" or "none")
		if previewKey ~= shownPreview then
			shownPreview = previewKey
			clear(preview)
			if item then
				local view = viewport({ Size = UDim2.fromScale(1, 1), ZIndex = 4 }, preview)
				showWeapon(view, "Rifle", item, 200 / (INFO_H - 40))
			elseif reward then
				UITheme.Coin(preview, 72, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 4 })
			end
		end
		-- die nächste Stufe ins Bild holen
		strip.CanvasPosition = Vector2.new(math.max(0, (math.min(tier + 1, max) - 3) * (CARD_W + GAP)), 0)
	end
	refresh()
	return { Refresh = refresh, Watch = { PassXP = true } }
end

return LobbyPages

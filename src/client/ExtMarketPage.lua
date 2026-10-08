-- ExtMarketPage (ModuleScript, nur Client)
-- Reiter MARKT im Extinction-Menü: Spielermarkt der offenen Welt (ExtMarketService). Der Host (ExtinctionClient) gibt
-- einen leeren Bereich (1304 x 668) und ctx mit Tasche, Angeboten, Symbolen und Senden; die Seite baut alles darin.
--   Links: Umschalter ANGEBOTE / MEINE ANGEBOTE n/Max, Sortierung (BILLIG ZUERST · TEUER ZUERST · NEU), Münzen, Suchfeld und
--     Kategorien (ALLE · WAFFEN · MUNITION · AUSRÜSTUNG · FAHRZEUGE), darunter ein Kartenraster (Symbol, Name, Anzahl,
--     Werte, Verkäufer, Preis, KAUFEN). Eigene Angebote sind dort markiert (ohne KAUFEN) und werden unter MEINE
--     ANGEBOTE verwaltet: ZURÜCKNEHMEN und PREIS ÄNDERN (Feld, - / +, OK).
--   Rechts: VERKAUFEN – Taschenraster des Hosts, gewähltes Item groß mit Werten, Anzahl und Preis mit - / + (Preis auch
--     per Feld und Schieberegler), günstigstes Angebot desselben Items zum Vergleich, Erlös nach Gebühr, ANBIETEN.
--   Außerhalb der Safe Zone liegt eine Sperre über allem (nichts darunter ist bedien- oder auswählbar).
-- Alles geht ohne Tippen (Controller/Touch): Zahlen über - / +, Knöpfe sind GuiButtons mit großen Trefferflächen.
-- Schnittstelle: ExtMarketPage.Build(body, ctx) -> page { Frame, Refresh(), OnBagClick(slot) }

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared.UITheme)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local InputActions = require(Shared.InputActions)

local C = UITheme.MenuColors -- im Menü der offenen Welt: Rot statt Bernstein
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label
local upper = UITheme.Upper
local format = UITheme.FormatNumber
local M = ExtinctionConfig.Market

local ExtMarketPage = {}

local CATEGORIES = {
	{ Key = "All", Text = "ALLE", Width = 64 },
	{ Key = "Weapon", Text = "WAFFEN", Width = 90 },
	{ Key = "Ammo", Text = "MUNITION", Width = 100 },
	{ Key = "Gear", Text = "AUSRÜSTUNG", Width = 120 },
	{ Key = "Attachment", Text = "AUFSÄTZE", Width = 100 },
	{ Key = "Vehicle", Text = "FAHRZEUGE", Width = 108 },
}
-- Pfeile nur in Gotham (Oswald kennt sie nicht): der Sortier-Knopf hat kleine Schrift, also Gotham Bold
local SORTS = {
	{ Key = "PriceAsc", Text = "BILLIG ZUERST" },
	{ Key = "PriceDesc", Text = "TEUER ZUERST" },
	{ Key = "New", Text = "NEU" },
}
local MAX_CARDS = 48 -- mehr Karten (mit 3D-Waffen) baut die Seite nicht auf einmal; Hinweis unten: Suche eingrenzen

-- Aufteilung (Offset im Bereich 1304 x 668)
local LEFT_W = 860
local RIGHT_X, RIGHT_W = 884, 420
local CARD_W, CARD_H, CARD_GAP = 205, 262, 10
local BAG_COLUMNS, BAG_CELL, BAG_GAP = 6, 58, 6

-- Heilung, Rüstung und Spritzen laufen unter AUSRÜSTUNG, Granaten und Molotows unter WAFFEN
local function groupOf(kind)
	if kind == "Heal" or kind == "Armor" or kind == "Repel" then
		return "Gear"
	elseif kind == "Throwable" then
		return "Weapon"
	end
	return kind
end

-- klein, ohne Umlaute: "PRÄZ" findet "Präzisionsgewehr" ebenso wie "prazision"
local function fold(text)
	text = string.lower(tostring(text or ""))
	for from, to in { ["ä"] = "a", ["ö"] = "o", ["ü"] = "u", ["Ä"] = "a", ["Ö"] = "o", ["Ü"] = "u", ["ß"] = "ss" } do
		text = string.gsub(text, from, to)
	end
	return text
end
ExtMarketPage.Fold = fold

-- Was der Verkäufer bekommt (wie ExtMarketService.Buy rechnet: Gebühr abgerundet)
function ExtMarketPage.Earn(price)
	return price - math.floor(price * M.FeeRate)
end

-- Schrittweite der - / +-Knöpfe beim Preis: je teurer, desto gröber
local function priceStep(price)
	if price < 20 then
		return 1
	elseif price < 100 then
		return 5
	elseif price < 500 then
		return 10
	elseif price < 2000 then
		return 50
	elseif price < 10000 then
		return 100
	elseif price < 50000 then
		return 500
	end
	return 1000
end

-- Auf das nächste Vielfache von step nach oben/unten (krumme Werte rasten so auf runde ein)
local function stepUp(value, step, maximum)
	return math.min(maximum, (value // step) * step + step)
end
local function stepDown(value, step, minimum)
	return math.max(minimum, math.ceil(value / step) * step - step)
end
local function priceUp(price)
	return stepUp(price, priceStep(price), M.MaxPrice)
end
local function priceDown(price)
	return stepDown(price, priceStep(math.max(1, price - 1)), 1)
end

local function clampPrice(value)
	return math.clamp(math.floor(tonumber(value) or 1), 1, M.MaxPrice)
end

-- Wann eingestellt ("VOR 5 MIN"), nil ohne Zeitstempel
local function ageText(at)
	at = tonumber(at) or 0
	if at <= 0 then
		return nil
	end
	local seconds = math.max(0, os.time() - at)
	if seconds < 60 then
		return "GERADE EBEN"
	elseif seconds < 3600 then
		return "VOR " .. math.floor(seconds / 60) .. " MIN"
	elseif seconds < 86400 then
		return "VOR " .. math.floor(seconds / 3600) .. " STD"
	end
	return "VOR " .. math.floor(seconds / 86400) .. " TG"
end

function ExtMarketPage.Build(body, ctx)
	local player = Players.LocalPlayer
	local state = { Tab = "Offers", Category = "All", Sort = "PriceAsc", Text = "" }
	-- Verkaufen: gewählter Taschenplatz, Anzahl, Preis (Touched = selbst geändert, dann folgt er nicht mehr dem Vorschlag)
	local sell = { Slot = nil, Id = nil, Count = 1, Price = 1, Touched = false, SliderMax = 100, IconId = nil }
	local drafts = {} -- [Angebots-Id] = neuer Preis unter MEINE ANGEBOTE (noch nicht gesendet)
	local locked = false
	local pending = false -- Neuaufbau wartet, bis ein Preisfeld in der Liste den Fokus verliert
	local offersKey, mineKey = nil, nil
	local lockedObjects = {} -- Knöpfe, die die Sperre unauswählbar gemacht hat (zum Zurücksetzen)
	local connections = {}
	local refresh -- unten (page.Refresh)

	local function coins()
		return tonumber(player:GetAttribute("Coins")) or 0
	end
	local function listings()
		local list = ctx.Listings() or {}
		return type(list) == "table" and list or {}
	end
	local function ownListings(list)
		local own = {}
		for _, offer in list do
			if offer.Seller == player.UserId then
				table.insert(own, offer)
			end
		end
		table.sort(own, function(a, b)
			local at, bt = tonumber(a.At) or 0, tonumber(b.At) or 0
			if at ~= bt then
				return at > bt
			end
			return tostring(a.Id) < tostring(b.Id)
		end)
		return own
	end

	local root = make("Frame", { Name = "MarketPage", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, body)
	local content = make("Frame", { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 5 }, root)

	-- Knopf, der unter der Sperre nichts tut
	local function button(props, parent, onClick)
		props.ZIndex = props.ZIndex or 7
		return UITheme.Chunky(props, parent, function()
			if not locked then
				onClick()
			end
		end)
	end
	local function paintChip(chunky, active)
		chunky.SetColor(active and C.Primary or C.Panel, active and C.PrimaryText or C.Text)
		chunky.SetStroke(active and C.Primary or C.Border, 1)
	end
	-- Knopf - oder + (Striche gezeichnet, unabhängig von der Schrift)
	local function stepButton(name, plus, position, parent, onClick)
		local chunky = button({ Name = name, Position = position, Size = UDim2.fromOffset(44, 44), Color = C.Card,
			StrokeColor = C.Border, Text = "" }, parent, onClick)
		make("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(16, 3), BackgroundColor3 = C.Text, BorderSizePixel = 0, ZIndex = 7 }, chunky.Face)
		if plus then
			make("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(3, 16), BackgroundColor3 = C.Text, BorderSizePixel = 0, ZIndex = 7 }, chunky.Face)
		end
		return chunky
	end
	-- An einer Grenze (kleinster/größter Wert) gedämpft, bleibt aber auswählbar (Controller springt nicht weg)
	local function dimStep(chunky, atLimit)
		for _, bar in chunky.Face:GetChildren() do
			if bar.Name == "Bar" then
				bar.BackgroundTransparency = atLimit and 0.7 or 0
			end
		end
	end
	-- Zahlenfeld: nur Ziffern (höchstens so viele wie MaxPrice hat); onChange(Zahl) beim Tippen, onDone beim Verlassen
	local digitsMax = #tostring(M.MaxPrice)
	local quiet = false -- Text vom Programm gesetzt: kein onChange
	local function setText(box, text)
		if box.Text ~= text then
			quiet = true
			box.Text = text
			quiet = false
		end
	end
	local function numberBox(name, position, size, parent, onChange, onDone)
		local box = make("TextBox", { Name = name, Position = position, Size = size, BackgroundColor3 = C.Background,
			BorderSizePixel = 0, Text = "", PlaceholderText = "PREIS", PlaceholderColor3 = C.Muted, ClearTextOnFocus = false,
			Font = F.Display, TextSize = 22, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Center, Selectable = true,
			ZIndex = 7 }, parent)
		UITheme.Corner(box, UITheme.Radius.Small)
		UITheme.Stroke(box, C.Primary, 1, 0.5)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local digits = string.sub((string.gsub(box.Text, "%D", "")), 1, digitsMax)
			if digits ~= box.Text then
				box.Text = digits -- löst erneut aus, dann mit den Ziffern
				return
			end
			local n = tonumber(digits)
			if not quiet and not locked and n and n >= 1 then
				onChange(n)
			end
		end)
		box.FocusLost:Connect(function()
			onDone()
			if pending then
				refresh()
			end
		end)
		return box
	end
	-- Großes Symbol: das Symbol des Hosts (für Plätze gemacht) per UIScale vergrößert
	local function bigIcon(parent, id, size, position, zIndex)
		local box = make("Frame", { Name = "IconBox", Position = position, Size = size, BackgroundTransparency = 1,
			ZIndex = zIndex }, parent)
		local icon = ctx.BuildIcon(box, id, zIndex)
		local scale = math.max(1, size.Y.Offset / 58)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(1 / scale, 1 / scale)
		make("UIScale", { Scale = scale }, icon)
		return box
	end
	local function clear(container)
		for _, child in container:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	local function focusedIn(container)
		local box = UserInputService:GetFocusedTextBox()
		return box ~= nil and box:IsDescendantOf(container)
	end

	-- ---------- Kopf: Reiter, Münzen, Sortierung ----------
	local tabOffers, tabMine
	local function switchTab(tab)
		state.Tab = tab
		refresh()
	end
	tabOffers = button({ Name = "TabOffers", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(190, 44),
		Text = "ANGEBOTE", TextSize = 18 }, content, function()
		switchTab("Offers")
	end)
	tabMine = button({ Name = "TabMine", Position = UDim2.fromOffset(198, 0), Size = UDim2.fromOffset(250, 44),
		Text = "MEINE ANGEBOTE", TextSize = 18 }, content, function()
		switchTab("Mine")
	end)
	local coinsText = label({ Name = "Coins", Position = UDim2.fromOffset(456, 0), Size = UDim2.fromOffset(180, 44), Text = "",
		TextSize = 24, Font = F.Display, TextColor3 = C.Primary, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 }, content)
	UITheme.Coin(content, 18, { Position = UDim2.fromOffset(642, 13), ZIndex = 6 })
	local sortButton = button({ Name = "Sort", Position = UDim2.fromOffset(LEFT_W - 190, 0), Size = UDim2.fromOffset(190, 44),
		Color = C.Panel, StrokeColor = C.Border, Text = "", TextSize = 14 }, content, function()
		local index = 1
		for i, sort in SORTS do
			if sort.Key == state.Sort then
				index = i
			end
		end
		state.Sort = SORTS[index % #SORTS + 1].Key
		refresh()
	end)

	-- ---------- Suche und Kategorien (nur ANGEBOTE) ----------
	local filterBar = make("Frame", { Name = "Filters", Position = UDim2.fromOffset(0, 54), Size = UDim2.fromOffset(LEFT_W, 44),
		BackgroundTransparency = 1, ZIndex = 5 }, content)
	local search = make("TextBox", { Name = "Search", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(210, 44),
		BackgroundColor3 = C.Background, BorderSizePixel = 0, Text = "", PlaceholderText = "SUCHEN",
		PlaceholderColor3 = C.Muted, ClearTextOnFocus = false, Font = F.Bold, TextSize = 15, TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left, Selectable = true, ZIndex = 7 }, filterBar)
	UITheme.Corner(search, UITheme.Radius.Small)
	UITheme.Stroke(search, C.Border, 1, 0.2)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 46) }, search)
	local searchClear = button({ Name = "SearchClear", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, 206, 0.5, 0),
		Size = UDim2.fromOffset(36, 36), Color = C.Card, Text = "", Visible = false }, filterBar, function()
		search.Text = ""
	end)
	UITheme.Cross(searchClear.Face, 12, C.Muted, 2).ZIndex = 7
	search:GetPropertyChangedSignal("Text"):Connect(function()
		if locked then
			setText(search, state.Text)
			return
		end
		state.Text = search.Text
		refresh()
	end)
	search.FocusLost:Connect(function()
		if pending then
			refresh()
		end
	end)
	local chips = {}
	local x = 216
	for _, info in CATEGORIES do
		chips[info.Key] = button({ Name = "Category_" .. info.Key, Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(info.Width, 44), Color = C.Panel, StrokeColor = C.Border, Text = info.Text, TextSize = 13 },
			filterBar, function()
			state.Category = info.Key
			refresh()
		end)
		x += info.Width + 6
	end
	local mineInfo = label({ Name = "MineInfo", Position = UDim2.fromOffset(0, 54), Size = UDim2.fromOffset(LEFT_W, 44),
		Text = "PREIS ÄNDERN MIT  - / +  UND OK  ·  ZURÜCKNEHMEN LEGT ES IN DIE TASCHE  ·  "
			.. math.floor(M.FeeRate * 100 + 0.5) .. " % GEBÜHR BEIM VERKAUF", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted,
		Visible = false, ZIndex = 6 }, content)

	-- ---------- Ergebnisse ----------
	local function scroller(name)
		return make("ScrollingFrame", { Name = name, Position = UDim2.fromOffset(0, 108), Size = UDim2.fromOffset(LEFT_W, 536),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, ScrollBarImageColor3 = C.Border,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 5 }, content)
	end
	local results = scroller("Results")
	make("UIGridLayout", { CellSize = UDim2.fromOffset(CARD_W, CARD_H), CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder }, results)
	local mineList = scroller("Mine")
	mineList.Visible = false
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, mineList)
	local footer = label({ Name = "Footer", Position = UDim2.fromOffset(0, 648), Size = UDim2.fromOffset(LEFT_W, 20), Text = "",
		TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 6 }, content)

	-- Leerzustand über dem Ergebnisbereich (nicht im Raster, das würde ihn auf Kartengröße zwingen)
	local empty = make("Frame", { Name = "Empty", Position = UDim2.fromOffset(0, 108), Size = UDim2.fromOffset(LEFT_W, 160),
		BackgroundTransparency = 1, Visible = false, ZIndex = 5 }, content)
	local emptyText = label({ Name = "Text", Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 30), Text = "",
		TextSize = 24, Font = F.Display, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, empty)
	local emptySub = label({ Name = "Sub", Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 18), Text = "",
		TextSize = 13, Font = F.Medium, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, empty)
	local function showEmpty(text, sub)
		empty.Visible = text ~= nil
		emptyText.Text = text or ""
		emptySub.Text = sub or ""
	end

	-- Angebote nach Kategorie und Suche (jedes Wort muss in Name, Art oder Verkäufer vorkommen), sortiert
	local function visibleOffers(list)
		local terms = {}
		for word in string.gmatch(fold(state.Text), "%S+") do
			table.insert(terms, word)
		end
		local found = {}
		for _, offer in list do
			local config = ctx.ItemConfig(offer.Item)
			if config and (state.Category == "All" or groupOf(config.Kind) == state.Category) then
				local text = fold(config.Name .. " " .. (ctx.KindNames[config.Kind] or "") .. " " .. tostring(offer.SellerName or ""))
				local ok = true
				for _, term in terms do
					if not string.find(text, term, 1, true) then
						ok = false
						break
					end
				end
				if ok then
					table.insert(found, offer)
				end
			end
		end
		table.sort(found, function(a, b)
			local ap, bp = tonumber(a.Price) or 0, tonumber(b.Price) or 0
			if state.Sort == "New" then
				local at, bt = tonumber(a.At) or 0, tonumber(b.At) or 0
				if at ~= bt then
					return at > bt
				end
			elseif ap ~= bp then
				if state.Sort == "PriceDesc" then
					return ap > bp
				end
				return ap < bp
			end
			if ap ~= bp then
				return ap < bp
			end
			return tostring(a.Id) < tostring(b.Id)
		end)
		return found
	end

	local function buildCard(offer, order, money)
		local config = ctx.ItemConfig(offer.Item)
		local kindColor = ctx.KindColors[config.Kind] or C.Border
		local own = offer.Seller == player.UserId
		local price = tonumber(offer.Price) or 0
		local count = tonumber(offer.Count) or 1
		local card = make("Frame", { Name = "Card", Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = C.Card,
			BackgroundTransparency = 0.05, BorderSizePixel = 0, LayoutOrder = order, ZIndex = 5 }, results)
		card:SetAttribute("ListingId", offer.Id)
		card:SetAttribute("Own", own)
		UITheme.Corner(card, UITheme.Radius.Large)
		UITheme.Stroke(card, own and C.Primary or kindColor, 1, own and 0.15 or 0.6)
		UITheme.AccentBar(card, own and C.Primary or kindColor, { Inset = 14, ZIndex = 6 })
		local stage = make("Frame", { Name = "Stage", Position = UDim2.fromOffset(10, 12), Size = UDim2.new(1, -20, 0, 104),
			BackgroundColor3 = C.Background, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 5 }, card)
		UITheme.Corner(stage, UITheme.Radius.Medium)
		bigIcon(stage, offer.Item, UDim2.new(1, 0, 0, 104), UDim2.new(), 6)
		UITheme.Tag({ Name = "Kind", Position = UDim2.fromOffset(6, 6), Text = ctx.KindNames[config.Kind] or "", TextSize = 10,
			BackgroundColor3 = kindColor:Lerp(C.Shadow, 0.6), TextColor3 = kindColor, ZIndex = 7 }, stage)
		if count > 1 then
			UITheme.Tag({ Name = "Count", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6),
				Text = "×" .. format(count), TextSize = 13, Font = F.Bold, BackgroundColor3 = C.Background, TextColor3 = C.Text,
				ZIndex = 7 }, stage)
		end
		if own then
			UITheme.Tag({ Name = "OwnTag", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -6), Text = "DEIN ANGEBOT",
				TextSize = 10, ZIndex = 7 }, stage)
		end
		label({ Name = "Name", Position = UDim2.fromOffset(12, 122), Size = UDim2.new(1, -24, 0, 24), Text = upper(config.Name),
			TextSize = 20, Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 }, card)
		label({ Name = "Stats", Position = UDim2.fromOffset(12, 148), Size = UDim2.new(1, -24, 0, 30),
			Text = ctx.Describe(offer.Item, { Id = offer.Item, N = count, Mag = offer.Mag }) or "", TextSize = 11, Font = F.Medium,
			TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 6 }, card)
		local age = ageText(offer.At)
		label({ Name = "Seller", Position = UDim2.fromOffset(12, 182), Size = UDim2.new(1, -24, 0, 16),
			Text = (own and "DU" or ("VON " .. upper(tostring(offer.SellerName or "?")))) .. (age and ("  ·  " .. age) or ""),
			TextSize = 11, Font = F.Bold, TextColor3 = own and C.Primary or C.Muted, TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 6 }, card)
		UITheme.Coin(card, 18, { Position = UDim2.fromOffset(12, 218), ZIndex = 6 })
		local affordable = own or money >= price
		label({ Name = "Price", Position = UDim2.fromOffset(34, 206), Size = UDim2.fromOffset(CARD_W - 34 - 98, 42),
			Text = format(price), TextSize = 22, Font = F.Display, TextColor3 = affordable and C.Text or C.Bad,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 }, card)
		local buttonProps = { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 206), Size = UDim2.fromOffset(88, 46),
			TextSize = 16 }
		if own then
			buttonProps.Name, buttonProps.Text, buttonProps.Color, buttonProps.StrokeColor = "Manage", "VERWALTEN", C.Panel, C.Primary
			buttonProps.TextSize = 14
			button(buttonProps, card, function()
				switchTab("Mine")
			end)
		elseif affordable then
			buttonProps.Name, buttonProps.Text, buttonProps.Color, buttonProps.TextColor = "Buy", "KAUFEN", C.Primary, C.PrimaryText
			button(buttonProps, card, function()
				if coins() < price then
					ctx.Toast("Dir fehlen " .. format(price - coins()) .. " Münzen.", false)
					return
				end
				ctx.Send("MarketBuy", offer.Id, price)
			end)
		else
			buttonProps.Name, buttonProps.Text, buttonProps.Color, buttonProps.TextColor = "Buy", "ZU TEUER", C.MutedBack, C.Muted
			buttonProps.TextSize = 14
			local chunky = button(buttonProps, card, function()
				ctx.Toast("Dir fehlen " .. format(price - coins()) .. " Münzen.", false)
			end)
			chunky.Button:SetAttribute("TooExpensive", true)
		end
		return card
	end

	local function buildOffers(list)
		local found = visibleOffers(list)
		local money = coins()
		local parts = { state.Category, state.Sort, state.Text, #list }
		for index, offer in found do
			if index > MAX_CARDS then
				break
			end
			local price = tonumber(offer.Price) or 0
			table.insert(parts, table.concat({ tostring(offer.Id), tostring(price), tostring(offer.Count), tostring(offer.Mag),
				tostring(money >= price) }, ":"))
		end
		local key = table.concat(parts, "|")
		if #list == 0 then
			showEmpty("NOCH KEINE ANGEBOTE", "Biete rechts etwas aus deiner Tasche an.")
		elseif #found == 0 then
			showEmpty("NICHTS GEFUNDEN", "Andere Suche oder Kategorie ALLE wählen.")
		else
			showEmpty(nil)
		end
		footer.Text = (#found > MAX_CARDS and ("ERSTE " .. MAX_CARDS .. " VON " .. #found .. " ANGEBOTEN  ·  SUCHE EINGRENZEN")
			or (#found .. (#found == 1 and " ANGEBOT" or " ANGEBOTE"))) .. "  ·  GEKAUFT WIRD SOFORT ZUM ANGEZEIGTEN PREIS"
		if key == offersKey then
			return
		end
		offersKey = key
		clear(results)
		for index, offer in found do
			if index > MAX_CARDS then
				break
			end
			buildCard(offer, index, money)
		end
	end

	-- Eine Zeile unter MEINE ANGEBOTE: Preis ändern (- / Feld / + / OK) und zurücknehmen
	local function buildMineRow(offer, order)
		local config = ctx.ItemConfig(offer.Item)
		local kindColor = config and ctx.KindColors[config.Kind] or C.Border
		local count = tonumber(offer.Count) or 1
		local current = tonumber(offer.Price) or 1
		local row = make("Frame", { Name = "MyOffer", Size = UDim2.new(1, -10, 0, 92), BackgroundColor3 = C.Card,
			BackgroundTransparency = 0.05, BorderSizePixel = 0, LayoutOrder = order, ZIndex = 5 }, mineList)
		row:SetAttribute("ListingId", offer.Id)
		UITheme.Corner(row, UITheme.Radius.Large)
		UITheme.Stroke(row, kindColor, 1, 0.6)
		UITheme.AccentBar(row, kindColor, { Side = "Left", ZIndex = 6 })
		bigIcon(row, offer.Item, UDim2.fromOffset(90, 72), UDim2.fromOffset(12, 10), 6)
		label({ Name = "Name", Position = UDim2.fromOffset(112, 12), Size = UDim2.fromOffset(296, 24),
			Text = upper(config and config.Name or tostring(offer.Item)) .. (count > 1 and ("  ×" .. format(count)) or ""),
			TextSize = 20, Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 }, row)
		label({ Name = "Stats", Position = UDim2.fromOffset(112, 40), Size = UDim2.fromOffset(296, 16),
			Text = ctx.Describe(offer.Item, { Id = offer.Item, N = count, Mag = offer.Mag }) or "", TextSize = 11, Font = F.Medium,
			TextColor3 = C.Muted, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 }, row)
		local age = ageText(offer.At)
		label({ Name = "Sub", Position = UDim2.fromOffset(112, 60), Size = UDim2.fromOffset(296, 16),
			Text = "PREIS JETZT " .. format(current) .. (age and ("  ·  EINGESTELLT " .. age) or ""), TextSize = 11,
			Font = F.Bold, TextColor3 = C.Muted, ZIndex = 6 }, row)

		local box, save, earn, down, up
		local function draft()
			return drafts[offer.Id] or current
		end
		local function paint()
			local value = draft()
			setText(box, tostring(value))
			local changed = value ~= current
			save.SetColor(changed and C.Primary or C.Panel, changed and C.PrimaryText or C.Muted)
			earn.Text = "DU BEKOMMST " .. format(ExtMarketPage.Earn(value)) .. " MÜNZEN"
			dimStep(down, value <= 1)
			dimStep(up, value >= M.MaxPrice)
		end
		local function set(value)
			value = clampPrice(value)
			drafts[offer.Id] = value ~= current and value or nil
			paint()
		end
		down = stepButton("PriceDown", false, UDim2.fromOffset(420, 14), row, function()
			set(priceDown(draft()))
		end)
		box = numberBox("PriceBox", UDim2.fromOffset(468, 14), UDim2.fromOffset(110, 44), row, function(n)
			local value = clampPrice(n)
			drafts[offer.Id] = value ~= current and value or nil
			paint()
		end, function()
			paint()
		end)
		up = stepButton("PriceUp", true, UDim2.fromOffset(582, 14), row, function()
			set(priceUp(draft()))
		end)
		save = button({ Name = "PriceSave", Position = UDim2.fromOffset(630, 14), Size = UDim2.fromOffset(56, 44), Color = C.Panel,
			StrokeColor = C.Border, Text = "OK", TextSize = 18 }, row, function()
			local value = draft()
			if value == current then
				ctx.Toast("Stell erst mit - / + einen neuen Preis ein.", false)
				return
			end
			drafts[offer.Id] = nil
			ctx.Send("MarketPrice", offer.Id, value)
		end)
		earn = label({ Name = "Earn", Position = UDim2.fromOffset(420, 62), Size = UDim2.fromOffset(266, 18), Text = "",
			TextSize = 11, Font = F.Bold, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, row)
		button({ Name = "Cancel", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(140, 44), Color = C.Panel, StrokeColor = C.Bad, Text = "ZURÜCKNEHMEN", TextSize = 14 }, row,
			function()
				drafts[offer.Id] = nil
				ctx.Send("MarketCancel", offer.Id)
			end)
		paint()
		return row
	end

	local function buildMine(own)
		local parts = {}
		for _, offer in own do
			table.insert(parts, tostring(offer.Id) .. ":" .. tostring(offer.Price) .. ":" .. tostring(offer.Count))
		end
		local key = table.concat(parts, "|")
		-- Entwürfe vergessener Angebote verwerfen
		local alive = {}
		for _, offer in own do
			alive[offer.Id] = true
		end
		for id in drafts do
			if not alive[id] then
				drafts[id] = nil
			end
		end
		if #own == 0 then
			showEmpty("DU HAST NICHTS IM ANGEBOT", "Rechts ein Item aus der Tasche wählen, Preis einstellen, ANBIETEN.")
		else
			showEmpty(nil)
		end
		if key == mineKey then
			return
		end
		mineKey = key
		clear(mineList)
		for index, offer in own do
			buildMineRow(offer, index)
		end
	end

	-- ---------- Verkaufen (rechte Spalte) ----------
	label({ Name = "SellTitle", Position = UDim2.fromOffset(RIGHT_X, 0), Size = UDim2.fromOffset(RIGHT_W, 18),
		Text = "VERKAUFEN  ·  ITEM AUS DER TASCHE WÄHLEN", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 6 }, content)
	local bagSize = ctx.BagSize or ExtinctionConfig.BagSlots
	local bagWidth = BAG_COLUMNS * (BAG_CELL + BAG_GAP) - BAG_GAP
	local bagHeight = math.ceil(bagSize / BAG_COLUMNS) * (BAG_CELL + BAG_GAP) - BAG_GAP
	local bagGrid = ctx.BagGrid(content, BAG_COLUMNS, BAG_CELL, BAG_GAP,
		UDim2.fromOffset(RIGHT_X + math.floor((RIGHT_W - bagWidth) / 2), 22))
	if bagGrid then
		bagGrid.Name = "BagGrid"
	end
	local sellY = 22 + bagHeight + 10
	local panel = make("Frame", { Name = "Sell", Position = UDim2.fromOffset(RIGHT_X, sellY), Size = UDim2.fromOffset(RIGHT_W, 668 - sellY),
		BackgroundColor3 = C.Card, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 5 }, content)
	UITheme.Corner(panel, UITheme.Radius.Large)
	UITheme.Stroke(panel, C.Border, 1, 0.5)
	local iconHolder = make("Frame", { Name = "IconHolder", Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(92, 72),
		BackgroundColor3 = C.Background, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 5 }, panel)
	UITheme.Corner(iconHolder, UITheme.Radius.Medium)
	local itemName = label({ Name = "ItemName", Position = UDim2.fromOffset(114, 8), Size = UDim2.fromOffset(294, 28), Text = "",
		TextSize = 24, Font = F.Display, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 }, panel)
	local itemSub = label({ Name = "ItemSub", Position = UDim2.fromOffset(114, 36), Size = UDim2.fromOffset(294, 16), Text = "",
		TextSize = 11, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 6 }, panel)
	local itemInfo = label({ Name = "Info", Position = UDim2.fromOffset(114, 54), Size = UDim2.fromOffset(294, 30), Text = "",
		TextSize = 11, Font = F.Medium, TextColor3 = C.Muted, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 6 }, panel)
	local controls = make("Frame", { Name = "Controls", Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 170),
		BackgroundTransparency = 1, ZIndex = 5 }, panel)

	local updateSell -- unten
	local function rowLabel(text, y)
		label({ Position = UDim2.fromOffset(12, y), Size = UDim2.fromOffset(70, 44), Text = text, TextSize = 12, Font = F.Bold,
			TextColor3 = C.Muted, ZIndex = 6 }, controls)
	end
	local function sellEntry()
		if not sell.Slot then
			return nil
		end
		local entry = (ctx.Bag() or {})[sell.Slot]
		if not entry or entry.Id ~= sell.Id then
			return nil
		end
		return entry
	end
	-- Höchster Wert des Schiebereglers (doppelter Vorschlag bzw. doppeltes günstigstes Angebot)
	local function marketStats(id)
		local units, lowest = {}, nil
		for _, offer in listings() do
			local count = tonumber(offer.Count) or 1
			local price = tonumber(offer.Price)
			if offer.Item == id and offer.Seller ~= player.UserId and price and count > 0 then
				local unit = price / count
				table.insert(units, unit)
				lowest = lowest and math.min(lowest, unit) or unit
			end
		end
		if #units == 0 then
			return nil, nil
		end
		local sum = 0
		for _, unit in units do
			sum += unit
		end
		return lowest, sum / #units
	end
	local function suggested(id, count)
		return clampPrice(ctx.SuggestedPrice(id, count))
	end
	local function resetSlider()
		local lowest = marketStats(sell.Id)
		local top = math.max(suggested(sell.Id, sell.Count) * 2, lowest and math.ceil(lowest * sell.Count * 2) or 0, 20)
		sell.SliderMax = math.min(M.MaxPrice, top)
	end
	-- Anzahl ändern: Preis folgt dem Vorschlag (oder dem eigenen Stückpreis, wenn man ihn selbst gesetzt hat)
	local function setCount(count)
		local entry = sellEntry()
		if not entry then
			return
		end
		count = math.clamp(math.floor(count), 1, entry.N or 1)
		if count == sell.Count then
			return
		end
		if sell.Touched then
			sell.Price = clampPrice(math.floor(sell.Price / sell.Count * count + 0.5))
		else
			sell.Price = suggested(sell.Id, count)
		end
		sell.Count = count
		resetSlider()
		updateSell()
	end
	local function countStep(entry)
		local config = ctx.ItemConfig(entry.Id)
		if (entry.N or 1) <= 12 then
			return 1
		end
		return config and config.Pack or 5
	end
	local function setPrice(value)
		sell.Price = clampPrice(value)
		sell.Touched = true
		updateSell()
	end

	rowLabel("ANZAHL", 0)
	local countDown = stepButton("CountDown", false, UDim2.fromOffset(84, 0), controls, function()
		local entry = sellEntry()
		if entry then
			setCount(stepDown(sell.Count, countStep(entry), 1))
		end
	end)
	local countValue = label({ Name = "CountValue", Position = UDim2.fromOffset(132, 0), Size = UDim2.fromOffset(110, 44),
		BackgroundTransparency = 0, BackgroundColor3 = C.Background, Text = "1", TextSize = 22, Font = F.Display,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, controls)
	UITheme.Corner(countValue, UITheme.Radius.Small)
	local countUp = stepButton("CountUp", true, UDim2.fromOffset(246, 0), controls, function()
		local entry = sellEntry()
		if entry then
			setCount(stepUp(sell.Count, countStep(entry), entry.N or 1))
		end
	end)
	local countAll = button({ Name = "CountAll", Position = UDim2.fromOffset(298, 0), Size = UDim2.fromOffset(98, 44),
		Color = C.Panel, StrokeColor = C.Border, Text = "ALLE", TextSize = 14 }, controls, function()
		local entry = sellEntry()
		if entry then
			setCount(entry.N or 1)
		end
	end)

	rowLabel("PREIS", 50)
	local priceDownButton = stepButton("PriceDown", false, UDim2.fromOffset(84, 50), controls, function()
		setPrice(priceDown(sell.Price))
	end)
	local priceBox = numberBox("PriceBox", UDim2.fromOffset(132, 50), UDim2.fromOffset(110, 44), controls, function(n)
		sell.Price = clampPrice(n)
		sell.Touched = true
		updateSell(n <= M.MaxPrice) -- zu groß: Feld gleich auf den Höchstpreis setzen
	end, function()
		updateSell()
	end)
	local priceUpButton = stepButton("PriceUp", true, UDim2.fromOffset(246, 50), controls, function()
		setPrice(priceUp(sell.Price))
	end)
	button({ Name = "Suggest", Position = UDim2.fromOffset(298, 50), Size = UDim2.fromOffset(98, 44), Color = C.Panel,
		StrokeColor = C.Border, Text = "VORSCHLAG", TextSize = 13 }, controls, function()
		if sellEntry() then
			sell.Price = suggested(sell.Id, sell.Count)
			sell.Touched = false
			updateSell()
		end
	end)

	-- Schieberegler (Maus/Touch ziehen); per Controller dieselben Werte über - / + (darum nicht auswählbar)
	local slider = make("TextButton", { Name = "Slider", Position = UDim2.fromOffset(12, 100), Size = UDim2.fromOffset(384, 30),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Selectable = false, ZIndex = 6 }, controls)
	local track = make("Frame", { Name = "Track", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = C.Background, BorderSizePixel = 0, ZIndex = 6 }, slider)
	UITheme.Corner(track, 3)
	local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Primary, BorderSizePixel = 0,
		ZIndex = 6 }, track)
	UITheme.Corner(fill, 3)
	local knob = make("Frame", { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(20, 20), BackgroundColor3 = C.Text, BorderSizePixel = 0, ZIndex = 7 }, slider)
	UITheme.Corner(knob, 10)
	UITheme.Stroke(knob, C.Primary, 2)
	local dragging = false
	local function slideTo(screenX)
		if locked or not sellEntry() then
			return
		end
		local width = slider.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local fraction = math.clamp((screenX - slider.AbsolutePosition.X) / width, 0, 1)
		local value = math.max(1, math.floor(fraction * sell.SliderMax + 0.5))
		local step = priceStep(value)
		setPrice(math.max(1, math.floor(value / step + 0.5) * step))
	end
	local function isPress(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	slider.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			slideTo(input.Position.X)
		end
	end)
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			slideTo(input.Position.X)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			dragging = false
		end
	end))

	local cheapest = label({ Name = "Cheapest", Position = UDim2.fromOffset(12, 134), Size = UDim2.fromOffset(384, 16), Text = "",
		TextSize = 12, Font = F.Bold, TextColor3 = C.Muted, ZIndex = 6 }, controls)
	local earnLabel = label({ Name = "Earn", Position = UDim2.fromOffset(12, 152), Size = UDim2.fromOffset(384, 18), Text = "",
		TextSize = 14, Font = F.Bold, TextColor3 = C.Good, ZIndex = 6 }, controls)
	local offerHint = label({ Name = "OfferHint", Position = UDim2.fromOffset(12, 228), Size = UDim2.fromOffset(384, 34), Text = "",
		TextSize = 12, Font = F.Medium, TextColor3 = C.Bad, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false, ZIndex = 7 }, panel)

	-- Warum ANBIETEN gerade nicht geht (kurz für den Knopf, lang als Hinweis) oder nil
	local function offerBlock(entry)
		if not entry then
			return "ANBIETEN", nil
		end
		if entry.Out then
			return "FAHRZEUG IST DRAUSSEN", "Das Fahrzeug ist draußen – erst einpacken (K), dann anbieten."
		end
		if #ownListings(listings()) >= M.MaxListings then
			return "ALLE " .. M.MaxListings .. " ANGEBOTE BELEGT",
				"Du hast schon " .. M.MaxListings .. " Angebote – nimm unter MEINE ANGEBOTE eins zurück."
		end
		return nil, nil
	end

	local offerButton = button({ Name = "Offer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10),
		Size = UDim2.new(1, -24, 0, 44), Color = C.Primary, TextColor = C.PrimaryText, Text = "ANBIETEN", TextSize = 20 }, panel,
		function()
			local entry = sellEntry()
			local blocked, hint = offerBlock(entry)
			if blocked or not entry then
				ctx.Toast(hint or "Wähl erst oben ein Item aus deiner Tasche.", false)
				return
			end
			local count = math.clamp(sell.Count, 1, entry.N or 1)
			ctx.Send("MarketList", sell.Slot, count, sell.Price)
			sell.Slot, sell.Id = nil, nil
			ctx.Select(nil)
			updateSell()
		end)

	function updateSell(keepBox)
		local entry = sellEntry()
		local config = entry and ctx.ItemConfig(entry.Id)
		local blocked, hint = offerBlock(entry)
		controls.Visible = config ~= nil
		if not config or not entry then
			sell.Slot, sell.Id, sell.IconId = nil, nil, nil
			clear(iconHolder)
			itemName.Text = "WÄHLE EIN ITEM"
			itemSub.Text = "DEINE ANGEBOTE " .. #ownListings(listings()) .. "/" .. M.MaxListings
			itemInfo.Text = "Tippe oben ein Item deiner Tasche an. Wenn jemand kauft, bekommst du den Preis minus "
				.. math.floor(M.FeeRate * 100 + 0.5) .. " % Gebühr."
			offerHint.Visible = false
			offerButton.SetColor(C.MutedBack, C.Muted)
			offerButton.SetText("ANBIETEN")
			return
		end
		if sell.IconId ~= entry.Id then
			clear(iconHolder)
			bigIcon(iconHolder, entry.Id, UDim2.fromOffset(92, 72), UDim2.new(), 6)
			sell.IconId = entry.Id
		end
		local n = entry.N or 1
		itemName.Text = upper(config.Name) .. (n > 1 and ("  ×" .. format(n)) or "")
		itemSub.Text = (ctx.KindNames[config.Kind] or "") .. "  ·  PLATZ " .. sell.Slot
			.. (sell.Slot <= (ctx.Hotbar or 0) and " (HOTBAR)" or "")
		itemSub.TextColor3 = ctx.KindColors[config.Kind] or C.Muted
		itemInfo.Text = ctx.Describe(entry.Id, entry) or ""
		local stacked = n > 1
		countValue.Text = format(sell.Count) .. (stacked and (" / " .. format(n)) or "")
		countDown.Button.Visible, countUp.Button.Visible, countAll.Button.Visible = stacked, stacked, stacked
		dimStep(countDown, sell.Count <= 1)
		dimStep(countUp, sell.Count >= n)
		if not keepBox then
			setText(priceBox, tostring(sell.Price))
		end
		dimStep(priceDownButton, sell.Price <= 1)
		dimStep(priceUpButton, sell.Price >= M.MaxPrice)
		local fraction = math.clamp(sell.Price / math.max(1, sell.SliderMax), 0, 1)
		fill.Size = UDim2.fromScale(fraction, 1)
		knob.Position = UDim2.fromScale(fraction, 0.5)
		local lowest, average = marketStats(entry.Id)
		if lowest then
			local low = math.max(1, math.floor(lowest * sell.Count + 0.5))
			local mean = math.max(1, math.floor((average or lowest) * sell.Count + 0.5))
			cheapest.Text = "GÜNSTIGSTES ANGEBOT: " .. format(low) .. "  ·  Ø " .. format(mean)
				.. (sell.Count > 1 and ("  (FÜR " .. format(sell.Count) .. " STÜCK)") or "")
			cheapest.TextColor3 = sell.Price <= low and C.Good or C.Muted
		else
			cheapest.Text = "NOCH KEIN ANGEBOT  ·  DU BIST DER ERSTE"
			cheapest.TextColor3 = C.Muted
		end
		local earned = ExtMarketPage.Earn(sell.Price)
		earnLabel.Text = "DU BEKOMMST: " .. format(earned) .. " MÜNZEN  (" .. format(sell.Price - earned) .. " GEBÜHR)"
		offerHint.Text = hint or ""
		offerHint.Visible = hint ~= nil
		cheapest.Visible = hint == nil
		earnLabel.Visible = hint == nil
		if blocked then
			offerButton.SetColor(C.MutedBack, C.Muted)
			offerButton.SetText(blocked)
		else
			offerButton.SetColor(C.Primary, C.PrimaryText)
			offerButton.SetText("ANBIETEN" .. (sell.Count > 1 and ("  ·  " .. format(sell.Count) .. " STÜCK") or ""))
		end
	end

	-- ---------- Sperre außerhalb der Safe Zone ----------
	local lock = make("TextButton", { Name = "Lock", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.18, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Selectable = false, Active = true,
		Visible = false, ZIndex = 9 }, root)
	UITheme.Corner(lock, UITheme.Radius.Large)
	local padlock = make("Frame", { Name = "Padlock", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, -30),
		Size = UDim2.fromOffset(76, 92), BackgroundTransparency = 1, ZIndex = 9 }, lock)
	local shackle = make("Frame", { Name = "Shackle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(46, 60), BackgroundTransparency = 1, ZIndex = 9 }, padlock)
	UITheme.Corner(shackle, 23)
	UITheme.Stroke(shackle, C.Primary, 7)
	local lockBody = make("Frame", { Name = "Body", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(76, 54), BackgroundColor3 = C.Primary, BorderSizePixel = 0, ZIndex = 9 }, padlock)
	UITheme.Corner(lockBody, 10)
	local keyhole = make("Frame", { Name = "Keyhole", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.PrimaryText, BorderSizePixel = 0, ZIndex = 9 }, lockBody)
	UITheme.Corner(keyhole, 7)
	make("Frame", { Name = "Slot", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.4, 2),
		Size = UDim2.fromOffset(5, 16), BackgroundColor3 = C.PrimaryText, BorderSizePixel = 0, ZIndex = 9 }, lockBody)
	label({ Name = "Title", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, -14), Size = UDim2.fromOffset(900, 44),
		Text = "MARKT NUR IN DER SAFE ZONE", TextSize = 36, Font = F.Display, TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 9 }, lock)
	label({ Name = "Sub", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 34), Size = UDim2.fromOffset(900, 22),
		Text = "Geh zurück in ein Camp, um zu kaufen und zu verkaufen.", TextSize = 17, Font = F.Medium, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, lock)
	label({ Name = "Note", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 62), Size = UDim2.fromOffset(900, 18),
		Text = "DEINE ANGEBOTE BLEIBEN STEHEN UND KÖNNEN WEITER GEKAUFT WERDEN", TextSize = 11, Font = F.Bold,
		TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, lock)

	-- Alles unter der Sperre unbedienbar und für den Controller unauswählbar machen (bzw. zurück)
	local function applyLock()
		lock.Visible = locked
		for _, object in content:GetDescendants() do
			if object:IsA("GuiButton") or object:IsA("TextBox") then
				if locked then
					if object.Selectable then
						lockedObjects[object] = true
						object.Selectable = false
					end
					object.Interactable = false
					if object:IsA("TextBox") then
						object.TextEditable = false
					end
				else
					object.Interactable = true
					if object:IsA("TextBox") then
						object.TextEditable = true
					end
				end
			end
		end
		if not locked then
			for object in lockedObjects do
				if object.Parent then
					object.Selectable = true
				end
			end
			table.clear(lockedObjects)
		end
	end

	local function setLocked(on)
		if on == locked then
			return
		end
		locked = on
		if on then
			dragging = false
			local focused = UserInputService:GetFocusedTextBox()
			if focused and focused:IsDescendantOf(root) then
				focused:ReleaseFocus()
			end
			InputActions.Unfocus(content)
		end
	end

	-- ---------- Schnittstelle ----------
	function refresh()
		if not root.Parent then
			return
		end
		setLocked(not ctx.InSafeZone())
		local list = listings()
		local own = ownListings(list)
		coinsText.Text = format(coins())
		paintChip(tabOffers, state.Tab == "Offers")
		paintChip(tabMine, state.Tab == "Mine")
		tabMine.SetText("MEINE ANGEBOTE  " .. #own .. "/" .. M.MaxListings)
		local sortText = SORTS[1].Text
		for _, sort in SORTS do
			if sort.Key == state.Sort then
				sortText = sort.Text
			end
		end
		sortButton.SetText(sortText)
		for key, chip in chips do
			paintChip(chip, key == state.Category)
		end
		setText(search, state.Text)
		searchClear.Button.Visible = state.Text ~= ""
		local offersTab = state.Tab == "Offers"
		filterBar.Visible, sortButton.Button.Visible, results.Visible = offersTab, offersTab, offersTab
		mineInfo.Visible, mineList.Visible = not offersTab, not offersTab
		-- Ausgewähltes Item noch da? (Tasche geändert, Host hat die Auswahl aufgehoben)
		local entry = sellEntry()
		if sell.Slot and (not entry or (ctx.Selected and ctx.Selected() ~= sell.Slot)) then
			if ctx.Selected and ctx.Selected() == sell.Slot then
				ctx.Select(nil)
			end
			sell.Slot, sell.Id = nil, nil
		elseif entry and sell.Count > (entry.N or 1) then
			sell.Count = entry.N or 1
			if not sell.Touched then
				sell.Price = suggested(sell.Id, sell.Count)
			end
			resetSlider()
		end
		local selection = GuiService.SelectedObject
		local selectedInside = selection ~= nil and selection:IsDescendantOf(root)
		-- Listen nicht neu bauen, solange man in eines ihrer Preisfelder tippt (nach FocusLost nachholen)
		if focusedIn(mineList) or focusedIn(results) then
			pending = true
		else
			pending = false
			if offersTab then
				buildOffers(list)
			else
				footer.Text = #own .. " VON " .. M.MaxListings .. " ANGEBOTEN"
				buildMine(own)
			end
		end
		updateSell(focusedIn(panel))
		applyLock()
		if selectedInside and not locked then
			InputActions.Refocus(root) -- Controller: Auswahl war auf einer neu gebauten Karte -> gleichnamiger Knopf
		end
	end

	local function onBagClick(slot)
		if locked then
			return
		end
		local entry = (ctx.Bag() or {})[slot]
		if not entry or not ctx.ItemConfig(entry.Id) or (sell.Slot == slot and sell.Id == entry.Id) then
			-- leerer Platz oder derselbe noch einmal: Auswahl aufheben
			sell.Slot, sell.Id = nil, nil
			ctx.Select(nil)
		else
			sell.Slot, sell.Id = slot, entry.Id
			sell.Count = entry.N or 1
			sell.Price = suggested(entry.Id, sell.Count)
			sell.Touched = false
			resetSlider()
			ctx.Select(slot)
		end
		updateSell()
		applyLock()
	end

	root.Destroying:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end)

	refresh()
	return { Frame = root, Refresh = refresh, OnBagClick = onBagClick }
end

return ExtMarketPage

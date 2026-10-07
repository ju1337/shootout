-- Reiter MARKT (ExtMarketPage) mit einem nachgebauten Host (ohne ExtinctionClient): Kategorien, Suche und Sortierung
-- filtern und ordnen die Karten, KAUFEN schickt Id und gesehenen Preis (zu teuer: nichts), eigene Angebote nur unter
-- MEINE ANGEBOTE mit ZURÜCKNEHMEN und PREIS ÄNDERN, Verkaufen mit Vorschlag, - / + in Grenzen, Erlös nach Gebühr,
-- günstigstes Angebot, ANBIETEN (nicht bei Fahrzeug draußen, vollen Angeboten, ohne Auswahl), Sperre außerhalb der
-- Safe Zone, Preisfeld mit Fokus bleibt beim Aktualisieren erhalten
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ExtinctionConfig = require("ExtinctionConfig")
local ExtMarketPage = require("ExtMarketPage")
local UITheme = require("UITheme")
local UserInputService = game:GetService("UserInputService")
local M = ExtinctionConfig.Market

local bob = SIM.Join("Bob", 1)
rawget(SIM.Players, "__props").LocalPlayer = bob
bob:SetAttribute("Coins", 1000)

-- ---------- Nachgebauter Host ----------
local bag = {
	[3] = { Id = "Ammo_Rifle", N = 60 },
	[5] = { Id = "Rifle", N = 1, Mag = 20 },
	[7] = { Id = "V_Quad", N = 1, Out = true },
	[12] = { Id = "Medkit", N = 2 },
}
local listings = {
	{ Id = "a1", Seller = 2, SellerName = "Ann", Item = "Rifle", Count = 1, Mag = 30, Price = 900, At = 100 },
	{ Id = "a2", Seller = 2, SellerName = "Ann", Item = "Ammo_Rifle", Count = 60, Price = 90, At = 300 },
	{ Id = "c1", Seller = 3, SellerName = "Cid", Item = "Medkit", Count = 1, Price = 150, At = 200 },
	{ Id = "c2", Seller = 3, SellerName = "Cid", Item = "DMR", Count = 1, Mag = 10, Price = 5000, At = 50 },
	{ Id = "b1", Seller = 1, SellerName = "Bob", Item = "Pistol", Count = 1, Mag = 12, Price = 100, At = 400 },
	{ Id = "c3", Seller = 3, SellerName = "Cid", Item = "Ammo_Rifle", Count = 30, Price = 60, At = 250 },
	{ Id = "a3", Seller = 2, SellerName = "Ann", Item = "V_Quad", Count = 1, Price = 800, At = 10 },
}
local safe = true
local sent, toasts = {}, {}
local selectedSlot = nil
local page
local function suggestedPrice(id, count)
	local config = ExtinctionConfig.Get(id)
	if config and config.Price then
		return math.max(1, math.floor(config.Price / (config.Pack or 1) * count + 0.5))
	end
	return math.max(1, ExtinctionConfig.SellPrice(id, count) * 2)
end
local ctx = {
	Bag = function()
		return bag
	end,
	BagSize = ExtinctionConfig.BagSlots,
	Hotbar = ExtinctionConfig.HotbarSlots,
	ItemConfig = function(id)
		return ExtinctionConfig.Get(id)
	end,
	BuildIcon = function(parent, id, zIndex)
		local icon = Instance.new("Frame")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.46)
		icon.Size = UDim2.fromScale(0.86, 0.62)
		icon.ZIndex = zIndex
		icon:SetAttribute("Item", id)
		icon.Parent = parent
		return icon
	end,
	Describe = function(id, entry)
		return "Werte " .. id .. (entry and entry.Mag and (" Magazin " .. entry.Mag) or "")
	end,
	KindNames = { Weapon = "WAFFE", Ammo = "MUNITION", Heal = "HEILUNG", Armor = "RÜSTUNG", Vehicle = "FAHRZEUG", Repel = "SCHUTZ" },
	KindColors = { Weapon = Color3.new(1, 0.5, 0), Ammo = Color3.new(0.7, 0.6, 0.4), Heal = Color3.new(1, 0, 0),
		Armor = Color3.new(0, 0, 1), Vehicle = Color3.new(0, 1, 0), Repel = Color3.new(0, 1, 0.5) },
	Send = function(...)
		table.insert(sent, table.pack(...))
	end,
	Listings = function()
		return listings
	end,
	InSafeZone = function()
		return safe
	end,
	BagGrid = function(parent, columns, cell, gap, position)
		local holder = Instance.new("Frame")
		holder.Position = position
		holder.Size = UDim2.fromOffset(columns * (cell + gap) - gap, 5 * (cell + gap) - gap)
		holder.Parent = parent
		for slot = 1, ExtinctionConfig.BagSlots do
			local button = Instance.new("TextButton")
			button.Name = "Bag" .. slot
			button.Parent = holder
			button.Activated:Connect(function()
				page.OnBagClick(slot)
			end)
		end
		return holder
	end,
	Select = function(slot)
		selectedSlot = slot
	end,
	Selected = function()
		return selectedSlot
	end,
	SuggestedPrice = suggestedPrice,
	Toast = function(text, ok)
		table.insert(toasts, { Text = text, Ok = ok })
	end,
}

local screen = Instance.new("ScreenGui")
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.fromOffset(1304, 668)
body.Parent = screen
page = ExtMarketPage.Build(body, ctx)

-- ---------- Hilfen ----------
local function find(root, name)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local function findAll(root, name)
	local list = {}
	for _, d in root:GetDescendants() do
		if d.Name == name then
			table.insert(list, d)
		end
	end
	return list
end
local function click(root, name)
	local button = find(root, name)
	check(button ~= nil, "Knopf " .. name .. " vorhanden")
	if button then
		button.Activated:Fire()
	end
end
local function textOf(chunkyButton)
	local text = chunkyButton and find(chunkyButton, "Label")
	return text and text.Text or ""
end
local results = find(body, "Results")
local mine = find(body, "Mine")
local sellPanel = find(body, "Sell")
local empty = find(body, "Empty")
-- Angebots-Ids der Karten in Reihenfolge
local function cardIds()
	local cards = findAll(results, "Card")
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	local ids = {}
	for _, card in cards do
		table.insert(ids, card:GetAttribute("ListingId"))
	end
	return table.concat(ids, ",")
end
local function cardOf(id)
	for _, card in findAll(results, "Card") do
		if card:GetAttribute("ListingId") == id then
			return card
		end
	end
	return nil
end
local function lastSent()
	return sent[#sent]
end
local function setSearch(text)
	find(body, "Search").Text = text
end

-- ---------- Angebote: Raster, Sortierung, eigene markiert ----------
check(find(body, "TabOffers") ~= nil and find(body, "TabMine") ~= nil, "Reiter ANGEBOTE / MEINE ANGEBOTE")
check(string.find(textOf(find(body, "TabMine")), "1/" .. M.MaxListings, 1, true) ~= nil,
	"MEINE ANGEBOTE zeigt 1/Max: " .. textOf(find(body, "TabMine")))
check(cardIds() == "c3,a2,b1,c1,a3,a1,c2", "BILLIG ZUERST: " .. cardIds())
check(not empty.Visible, "mit Angeboten kein Leerzustand")
local own = cardOf("b1")
check(own and own:GetAttribute("Own") == true and find(own, "Buy") == nil and find(own, "Manage") ~= nil,
	"eigenes Angebot markiert, ohne KAUFEN")
check(#findAll(results, "Cancel") == 0 and #findAll(results, "PriceSave") == 0, "im Hauptraster kein Zurücknehmen/Preis ändern")
local rifleCard = cardOf("a1")
check(rifleCard and string.find(find(rifleCard, "Stats").Text, "Magazin 30", 1, true) ~= nil, "Werte-Zeile mit Magazin")
check(rifleCard and string.find(find(rifleCard, "Seller").Text, "VON ANN", 1, true) == 1, "Verkäufer auf der Karte")
check(rifleCard and find(rifleCard, "IconBox") ~= nil and find(find(rifleCard, "IconBox"), "Icon") ~= nil, "Karte mit Symbol")
check(find(cardOf("a2"), "Count") ~= nil and find(cardOf("a2"), "Count").Text == "×60", "Stapel zeigt ×60")

click(body, "Sort")
check(cardIds() == "c2,a1,a3,c1,b1,a2,c3", "TEUER ZUERST: " .. cardIds())
check(string.find(textOf(find(body, "Sort")), "TEUER", 1, true) ~= nil, "Sortier-Knopf zeigt TEUER ZUERST")
click(body, "Sort")
check(cardIds() == "b1,a2,c3,c1,a1,c2,a3", "NEU: " .. cardIds())
click(body, "Sort")
check(cardIds() == "c3,a2,b1,c1,a3,a1,c2", "zurück zu BILLIG ZUERST")

-- ---------- Kategorien ----------
click(body, "Category_Weapon")
check(cardIds() == "b1,a1,c2", "WAFFEN: " .. cardIds())
click(body, "Category_Ammo")
check(cardIds() == "c3,a2", "MUNITION: " .. cardIds())
click(body, "Category_Gear")
check(cardIds() == "c1", "AUSRÜSTUNG: " .. cardIds())
click(body, "Category_Vehicle")
check(cardIds() == "a3", "FAHRZEUGE: " .. cardIds())
click(body, "Category_All")
check(#findAll(results, "Card") == 7, "ALLE: 7 Karten")

-- ---------- Suche ----------
setSearch("präz")
check(cardIds() == "c2", "Suche präz: " .. cardIds())
setSearch("PRAZISION")
check(cardIds() == "c2", "Suche ohne Umlaut, groß: " .. cardIds())
setSearch("PRÄZISIONS")
check(cardIds() == "c2", "Suche mit großem Umlaut: " .. cardIds())
setSearch("munition")
check(cardIds() == "c3,a2", "Suche munition: " .. cardIds())
setSearch("cid gewehr")
check(cardIds() == "c3,c2", "zwei Wörter (Verkäufer + Name): " .. cardIds())
click(body, "Category_Weapon")
check(cardIds() == "c2", "Suche und Kategorie zusammen: " .. cardIds())
click(body, "Category_All")
setSearch("xyz")
check(#findAll(results, "Card") == 0 and empty.Visible and find(empty, "Text").Text == "NICHTS GEFUNDEN", "NICHTS GEFUNDEN")
check(find(body, "SearchClear").Visible, "Suche leeren sichtbar")
click(body, "SearchClear")
check(find(body, "Search").Text == "" and #findAll(results, "Card") == 7 and not empty.Visible, "Suche geleert")

-- ---------- Kaufen ----------
table.clear(sent)
click(cardOf("a1"), "Buy")
check(#sent == 1 and sent[1][1] == "MarketBuy" and sent[1][2] == "a1" and sent[1][3] == 900, "KAUFEN sendet MarketBuy(a1, 900)")
local dmrBuy = find(cardOf("c2"), "Buy")
check(dmrBuy and textOf(dmrBuy) == "ZU TEUER", "zu teuer: ZU TEUER (" .. textOf(dmrBuy) .. ")")
dmrBuy.Activated:Fire()
check(#sent == 1, "zu teuer: nichts gesendet")
check(#toasts > 0 and toasts[#toasts].Ok == false, "zu teuer: Meldung")
-- mehr Münzen: dieselbe Karte wird kaufbar
bob:SetAttribute("Coins", 6000)
page.Refresh()
check(textOf(find(cardOf("c2"), "Buy")) == "KAUFEN", "nach Refresh mit Münzen kaufbar")
find(cardOf("c2"), "Buy").Activated:Fire()
check(lastSent()[1] == "MarketBuy" and lastSent()[2] == "c2" and lastSent()[3] == 5000, "DMR kaufen")
bob:SetAttribute("Coins", 1000)
page.Refresh()

-- ---------- MEINE ANGEBOTE ----------
click(body, "Manage")
check(mine.Visible and not results.Visible, "VERWALTEN wechselt zu MEINE ANGEBOTE")
local rows = findAll(mine, "MyOffer")
check(#rows == 1 and rows[1]:GetAttribute("ListingId") == "b1", "nur das eigene Angebot unter MEINE ANGEBOTE")
check(not find(body, "Filters").Visible, "Suche/Kategorien nur bei ANGEBOTE")
local row = rows[1]
local rowBox = find(row, "PriceBox")
check(rowBox.Text == "100", "Preisfeld zeigt 100 (" .. rowBox.Text .. ")")
table.clear(sent)
click(row, "PriceSave")
check(#sent == 0, "OK ohne Änderung sendet nichts")
click(row, "PriceUp")
check(rowBox.Text == "110", "+ erhöht auf 110 (" .. rowBox.Text .. ")")
check(string.find(find(row, "Earn").Text, tostring(ExtMarketPage.Earn(110)), 1, true) ~= nil, "Erlös in der Zeile")
click(row, "PriceDown")
click(row, "PriceDown")
check(rowBox.Text == "95", "- zweimal: 95 (" .. rowBox.Text .. ")")
click(row, "PriceSave")
check(#sent == 1 and sent[1][1] == "MarketPrice" and sent[1][2] == "b1" and sent[1][3] == 95, "OK sendet MarketPrice(b1, 95)")
rowBox.Text = "3"
for _ = 1, 5 do
	click(row, "PriceDown")
end
check(rowBox.Text == "1", "Preis nicht unter 1 (" .. rowBox.Text .. ")")
rowBox.Text = "9999999"
check(rowBox.Text == tostring(M.MaxPrice), "Preis höchstens MaxPrice (" .. rowBox.Text .. ")")
click(row, "PriceUp")
check(rowBox.Text == tostring(M.MaxPrice), "+ bleibt bei MaxPrice")
click(row, "Cancel")
check(lastSent()[1] == "MarketCancel" and lastSent()[2] == "b1", "ZURÜCKNEHMEN sendet MarketCancel(b1)")

-- Preisfeld mit Fokus wird beim Aktualisieren nicht zerstört, der Neuaufbau kommt nach FocusLost
local focused = nil
rawget(UserInputService, "__methods").GetFocusedTextBox = function()
	return focused
end
row = findAll(mine, "MyOffer")[1]
rowBox = find(row, "PriceBox")
focused = rowBox
listings[5] = { Id = "b1", Seller = 1, SellerName = "Bob", Item = "Pistol", Count = 1, Mag = 12, Price = 95, At = 400 }
page.Refresh()
check(rowBox.Parent ~= nil and find(mine, "MyOffer") == row, "Feld mit Fokus bleibt beim Refresh")
focused = nil
rowBox.FocusLost:Fire(false)
check(rowBox.Parent == nil and find(find(mine, "MyOffer"), "PriceBox").Text == "95", "nach FocusLost neu aufgebaut (Preis 95)")

-- ohne eigene Angebote
table.remove(listings, 5)
page.Refresh()
check(#findAll(mine, "MyOffer") == 0 and empty.Visible and find(empty, "Text").Text == "DU HAST NICHTS IM ANGEBOT",
	"DU HAST NICHTS IM ANGEBOT")
check(string.find(textOf(find(body, "TabMine")), "0/" .. M.MaxListings, 1, true) ~= nil, "MEINE ANGEBOTE 0/Max")
click(body, "TabOffers")
check(results.Visible and not mine.Visible and #findAll(results, "Card") == 6 and not empty.Visible, "zurück zu ANGEBOTE")

-- ---------- Verkaufen ----------
local offer = find(sellPanel, "Offer")
local priceBox = find(sellPanel, "PriceBox")
local countValue = find(sellPanel, "CountValue")
local earn = find(sellPanel, "Earn")
local cheapest = find(sellPanel, "Cheapest")
table.clear(sent)
offer.Activated:Fire()
check(#sent == 0, "ohne Auswahl: kein Angebot")
check(not find(sellPanel, "Controls").Visible, "ohne Auswahl keine Regler")

find(body, "Bag3").Activated:Fire()
check(selectedSlot == 3, "Taschenplatz 3 hervorgehoben")
check(find(sellPanel, "Controls").Visible and string.find(find(sellPanel, "ItemName").Text, "GEWEHRMUNITION", 1, true) ~= nil,
	"gewähltes Item groß: " .. find(sellPanel, "ItemName").Text)
check(find(sellPanel, "IconHolder"):FindFirstChild("IconBox") ~= nil, "Symbol des gewählten Items")
check(string.find(countValue.Text, "60", 1, true) == 1, "Anzahl 60 vorgeschlagen (" .. countValue.Text .. ")")
check(priceBox.Text == tostring(suggestedPrice("Ammo_Rifle", 60)), "Preis vorgeschlagen (" .. priceBox.Text .. ")")
-- Andere Angebote Gewehrmunition: 90 für 60 (1,5/Schuss) und 60 für 30 (2/Schuss) -> für 60: 90, Ø 105
check(string.find(cheapest.Text, "GÜNSTIGSTES ANGEBOT: 90", 1, true) ~= nil and string.find(cheapest.Text, "Ø 105", 1, true) ~= nil,
	"günstigstes Angebot für 60: " .. cheapest.Text)
click(sellPanel, "CountUp")
check(string.find(countValue.Text, "60", 1, true) == 1, "Anzahl nicht über den Stapel")
click(sellPanel, "CountDown")
check(string.find(countValue.Text, "30", 1, true) == 1, "- auf 30 (" .. countValue.Text .. ")")
check(priceBox.Text == tostring(suggestedPrice("Ammo_Rifle", 30)), "Vorschlag folgt der Anzahl (" .. priceBox.Text .. ")")
check(string.find(cheapest.Text, "GÜNSTIGSTES ANGEBOT: 45", 1, true) ~= nil and string.find(cheapest.Text, "Ø 53", 1, true) ~= nil,
	"günstigstes Angebot für 30: " .. cheapest.Text)
for _ = 1, 5 do
	click(sellPanel, "CountDown")
end
check(string.find(countValue.Text, "1 /", 1, true) == 1, "Anzahl nicht unter 1 (" .. countValue.Text .. ")")
click(sellPanel, "CountAll")
check(string.find(countValue.Text, "60", 1, true) == 1, "ALLE: 60")
click(sellPanel, "CountDown")

priceBox.Text = "60"
click(sellPanel, "PriceUp")
check(priceBox.Text == "65", "+ von 60: 65 (" .. priceBox.Text .. ")")
click(sellPanel, "PriceDown")
check(priceBox.Text == "60", "- zurück auf 60 (" .. priceBox.Text .. ")")
check(string.find(earn.Text, "DU BEKOMMST: " .. tostring(60 - math.floor(60 * M.FeeRate)) .. " MÜNZEN", 1, true) ~= nil,
	"Erlös 60: " .. earn.Text)
priceBox.Text = "1000"
check(string.find(earn.Text, "DU BEKOMMST: " .. UITheme.FormatNumber(1000 - math.floor(1000 * M.FeeRate)), 1, true) ~= nil,
	"Erlös 1000: " .. earn.Text)
priceBox.Text = "999999"
check(priceBox.Text == tostring(M.MaxPrice), "Preis höchstens MaxPrice (" .. priceBox.Text .. ")")
click(sellPanel, "PriceUp")
check(priceBox.Text == tostring(M.MaxPrice), "+ bleibt bei MaxPrice")
priceBox.Text = "1"
click(sellPanel, "PriceDown")
check(priceBox.Text == "1", "- bleibt bei 1")
check(string.find(earn.Text, "DU BEKOMMST: 1 MÜNZEN", 1, true) ~= nil, "Erlös bei 1: " .. earn.Text)
-- Schieberegler: Klick in die Mitte setzt etwa die Hälfte des Bereichs
local slider = find(sellPanel, "Slider")
check(slider.Selectable == false, "Schieberegler selbst nicht auswählbar (- / + dafür)")
slider.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1,
	Position = Vector3.new(slider.AbsolutePosition.X + slider.AbsoluteSize.X / 2, slider.AbsolutePosition.Y, 0) })
UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 }, false)
local slid = tonumber(priceBox.Text) or 0
check(slid > 1 and slid < M.MaxPrice, "Schieberegler setzt einen Preis (" .. priceBox.Text .. ")")
click(sellPanel, "Suggest")
check(priceBox.Text == tostring(suggestedPrice("Ammo_Rifle", 30)), "VORSCHLAG setzt zurück")

priceBox.Text = "250"
priceBox.FocusLost:Fire(true)
table.clear(sent)
offer.Activated:Fire()
check(#sent == 1 and sent[1][1] == "MarketList" and sent[1][2] == 3 and sent[1][3] == 30 and sent[1][4] == 250,
	"ANBIETEN sendet MarketList(3, 30, 250)")
check(selectedSlot == nil and not find(sellPanel, "Controls").Visible, "nach ANBIETEN keine Auswahl mehr")

-- Waffe: keine Anzahl-Knöpfe, Werte mit Magazin
find(body, "Bag5").Activated:Fire()
check(not find(sellPanel, "CountUp").Visible and not find(sellPanel, "CountDown").Visible, "Waffe: keine Anzahl-Knöpfe")
check(string.find(find(sellPanel, "Info").Text, "Magazin 20", 1, true) ~= nil, "Waffe: Werte mit Magazin")
check(string.find(cheapest.Text, "GÜNSTIGSTES ANGEBOT: 900", 1, true) ~= nil, "Gewehr: günstigstes 900 (" .. cheapest.Text .. ")")
find(body, "Bag5").Activated:Fire()
check(selectedSlot == nil, "derselbe Platz noch einmal hebt die Auswahl auf")
-- Medikit: kein anderes Angebot außer Cid (150) -> eigenes zählt nicht; Adrenalin hat keins
find(body, "Bag12").Activated:Fire()
check(string.find(cheapest.Text, "GÜNSTIGSTES ANGEBOT: 300", 1, true) ~= nil, "Medikit ×2: 2 × 150 (" .. cheapest.Text .. ")")
bag[14] = { Id = "Adrenaline", N = 1 }
find(body, "Bag14").Activated:Fire()
check(cheapest.Text ~= "" and string.find(cheapest.Text, "NOCH KEIN ANGEBOT", 1, true) ~= nil, "ohne Angebot: NOCH KEIN ANGEBOT")

-- Fahrzeug draußen: kein Angebot
table.clear(sent)
find(body, "Bag7").Activated:Fire()
check(string.find(textOf(offer), "DRAUSSEN", 1, true) ~= nil, "Fahrzeug draußen: Hinweis im Knopf (" .. textOf(offer) .. ")")
check(find(sellPanel, "OfferHint").Visible, "Fahrzeug draußen: Hinweistext")
offer.Activated:Fire()
check(#sent == 0, "Fahrzeug draußen: nichts gesendet")

-- volle Angebote: kein Angebot
for i = 1, M.MaxListings do
	table.insert(listings, { Id = "own" .. i, Seller = 1, SellerName = "Bob", Item = "Bandage", Count = 1, Price = 10 + i, At = 500 + i })
end
page.Refresh()
find(body, "Bag5").Activated:Fire()
check(string.find(textOf(offer), "BELEGT", 1, true) ~= nil, "volle Angebote: Hinweis (" .. textOf(offer) .. ")")
offer.Activated:Fire()
check(#sent == 0, "volle Angebote: nichts gesendet")
for _ = 1, M.MaxListings do
	table.remove(listings)
end
page.Refresh()
check(textOf(offer) == "ANBIETEN", "wieder frei: ANBIETEN (" .. textOf(offer) .. ")")

-- Item verschwindet aus der Tasche: Auswahl weg
bag[5] = nil
page.Refresh()
check(not find(sellPanel, "Controls").Visible, "Item weg: keine Auswahl mehr")
bag[5] = { Id = "Rifle", N = 1, Mag = 20 }

-- ---------- Sperre außerhalb der Safe Zone ----------
local lock = find(body, "Lock")
check(lock and not lock.Visible, "in der Safe Zone keine Sperre")
safe = false
page.Refresh()
check(lock.Visible and lock.Selectable == false, "außerhalb: Sperre sichtbar")
check(string.find(find(lock, "Title").Text, "MARKT NUR IN DER SAFE ZONE", 1, true) ~= nil
	and find(lock, "Sub").Text == "Geh zurück in ein Camp, um zu kaufen und zu verkaufen.", "Sperre: Texte")
check(find(lock, "Padlock") ~= nil, "Sperre: Schloss-Symbol")
local selectable = 0
for _, d in find(body, "Content"):GetDescendants() do
	if (d:IsA("GuiButton") or d:IsA("TextBox")) and (d.Selectable or d.Interactable ~= false) then
		selectable += 1
	end
end
check(selectable == 0, "unter der Sperre nichts auswählbar/bedienbar (" .. selectable .. ")")
table.clear(sent)
find(cardOf("a1"), "Buy").Activated:Fire()
find(body, "Bag3").Activated:Fire()
click(body, "Category_Weapon")
check(#sent == 0 and selectedSlot == nil and #findAll(results, "Card") == 6, "unter der Sperre: kein Kauf, keine Auswahl, kein Filter")
offer.Activated:Fire()
check(#sent == 0, "unter der Sperre kein Angebot")
safe = true
page.Refresh()
check(not lock.Visible, "zurück in der Safe Zone: Sperre weg")
check(find(cardOf("a1"), "Buy").Selectable and find(body, "Search").Selectable and find(body, "Bag3").Selectable,
	"Knöpfe wieder auswählbar")
find(cardOf("a1"), "Buy").Activated:Fire()
check(#sent == 1 and sent[1][1] == "MarketBuy", "nach der Sperre wieder kaufen")
find(body, "Bag3").Activated:Fire()
check(selectedSlot == 3, "nach der Sperre wieder auswählen")

-- ---------- leerer Markt ----------
table.clear(listings)
page.Refresh()
check(#findAll(results, "Card") == 0 and empty.Visible and find(empty, "Text").Text == "NOCH KEINE ANGEBOTE", "NOCH KEINE ANGEBOTE")

if failures > 0 then
	error(failures .. " Fehler")
end
print("extmarketpage: alles ok")

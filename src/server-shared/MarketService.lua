-- MarketService (ModuleScript, nur Server)
-- Stände im Markt (wie die Trading Plaza in Pet Simulator / Sniper Arena):
--   * Claim: Ein freier Stand gehört dem Spieler, solange er im Markt bleibt (einer pro Spieler). Der Spieler bleibt
--     dabei, wo er steht (kein Teleport hinter die Theke).
--   * List / Unlist / SetPrice: bis zu RapConfig.StandSlots handelbare Skins zum selbst gewählten RAP-Preis
--     anbieten. Die Skins bleiben im Inventar, sind aber zurückgelegt (EconomyService, Schlüssel "Stand"). Angebote
--     laufen nicht ab: sie gelten, bis sie verkauft oder zurückgenommen werden oder der Besitzer den Markt verlässt.
--   * Buy: Andere Spieler kaufen am Stand (nur in der Nähe und nur zum angezeigten Preis): Der Skin wandert zum
--     Käufer, das RAP zum Besitzer (minus Marktgebühr nach Preis, RapConfig.FeeRate), beide Spielstände werden
--     gespeichert und beide bekommen eine Meldung.
--   * Offer / Answer / CancelOffer: Gegenangebot unter dem Preis (mindestens RapConfig.MinOfferFraction). Der Besitzer
--     nimmt an oder lehnt ab (RapConfig.OfferSeconds); bei Annahme wird zum Gebot verkauft.
--   * Name: Stand-Name (Textfilter). Watch / Unwatch: Merkliste (im Profil, MarketWatch); wird ein gemerkter Skin
--     angeboten, bekommen alle im Markt eine Meldung.
--   * Preisverlauf: jeder Verkauf wird im DataStore "MarketHistory_v1" gezählt; Durchschnitt der letzten Tage liegt
--     als Attribut PriceStats an der Markt-Map. TopSellers: Händler dieses Servers mit den meisten Verkäufen.
--   * Release: Stand abgeben – auch von selbst, sobald der Besitzer den Markt verlässt (Runde, Hub) oder das Spiel.
--     Seine Skins sind dann wieder frei, jemand anderes kann den Stand nehmen.
-- Zustand für alle Clients als Attribute am Stand-Ordner (Maps.Market.Stand_<n>): Owner (UserId, 0 = frei),
-- OwnerName, StandName, Listings (JSON [{ Slot, Item, Price }]), Offers (JSON [{ Id, Slot, Item, Buyer,
-- BuyerName, Price, Expires }]). An der Map: PriceStats (JSON { [Skin] = { Avg, N, Last } }), TopSellers (JSON).
-- Remotes: MarketAction (Client -> Server), MarketStatus (Server -> Client: Text, Erfolg).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.Cosmetics)
local RapConfig = require(Shared.RapConfig)
local Modes = require(Shared.Modes)
local ProgressService = require(script.Parent.ProgressService)
local EconomyService = require(script.Parent.EconomyService)

local MarketService = {}

MarketService.Key = "Stand"     -- Schlüssel der Reservierungen
MarketService.ClaimRange = 18   -- so nah muss man zum Beanspruchen am Stand sein (Studs)
MarketService.BuyRange = 22     -- und zum Kaufen
local MIN_INTERVAL = 0.15       -- Anfragen pro Spieler höchstens so oft
local TOP_SELLERS = 5

local stands = {}     -- [Nummer] = { Id, Folder, Owner, Name, Listings = { [Platz] = { Item, Price } }, Offers = { ... } }
local standOf = {}    -- [Player] = Stand
local lastAction = {} -- [Player] = os.clock()
local mapFolder = nil -- Maps.Market (für PriceStats und TopSellers)
local nextOfferId = 0
local history = {}    -- [Skin] = { { Time, Price } } (neueste hinten), aus dem DataStore und diesem Server
local sellers = {}    -- [UserId] = { Name, Sales, Volume } (nur dieser Server)
local format = EconomyService.Format

local historyStore = nil
do
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "MarketHistory_v1")
	if ok then
		historyStore = result
	end
end

-- ---------- Veröffentlichen ----------

local function offerList(stand)
	local list = {}
	for _, offer in stand.Offers do
		table.insert(list, { Id = offer.Id, Slot = offer.Slot, Item = offer.Item, Buyer = offer.Buyer.UserId,
			BuyerName = offer.Buyer.Name, Price = offer.Price, Expires = offer.Expires })
	end
	return list
end

local function publish(stand)
	local list = {}
	for slot = 1, RapConfig.StandSlots do
		local listing = stand.Listings[slot]
		if listing then
			table.insert(list, { Slot = slot, Item = listing.Item, Price = listing.Price })
		end
	end
	stand.Folder:SetAttribute("Owner", stand.Owner and stand.Owner.UserId or 0)
	stand.Folder:SetAttribute("OwnerName", stand.Owner and stand.Owner.Name or "")
	stand.Folder:SetAttribute("StandName", stand.Owner and stand.Name or "")
	stand.Folder:SetAttribute("Listings", HttpService:JSONEncode(list))
	stand.Folder:SetAttribute("Offers", HttpService:JSONEncode(offerList(stand)))
end

local function publishStats()
	if not mapFolder then
		return
	end
	local now = os.time()
	local window = RapConfig.HistoryDays * 86400
	local stats = {}
	for id, sales in history do
		local sum, n, last = 0, 0, nil
		for _, sale in sales do
			if now - sale.Time <= window then
				sum += sale.Price
				n += 1
				last = sale.Price
			end
		end
		if n > 0 then
			stats[id] = { Avg = math.floor(sum / n + 0.5), N = n, Last = last }
		end
	end
	mapFolder:SetAttribute("PriceStats", HttpService:JSONEncode(stats))
	local top = {}
	for userId, entry in sellers do
		table.insert(top, { Name = entry.Name, Sales = entry.Sales, Volume = entry.Volume, UserId = userId })
	end
	table.sort(top, function(a, b)
		if a.Sales ~= b.Sales then
			return a.Sales > b.Sales
		end
		if a.Volume ~= b.Volume then
			return a.Volume > b.Volume
		end
		return a.UserId < b.UserId
	end)
	local out = {}
	for index = 1, math.min(TOP_SELLERS, #top) do
		out[index] = { Name = top[index].Name, Sales = top[index].Sales, Volume = top[index].Volume }
	end
	mapFolder:SetAttribute("TopSellers", HttpService:JSONEncode(out))
end

-- Verkauf im Preisverlauf zählen (Zwischenspeicher sofort, DataStore im Hintergrund)
local function recordSale(itemId, price)
	local list = history[itemId] or {}
	history[itemId] = list
	local sale = { Time = os.time(), Price = price }
	table.insert(list, sale)
	while #list > RapConfig.HistoryKeep do
		table.remove(list, 1)
	end
	if historyStore then
		task.spawn(function()
			pcall(historyStore.UpdateAsync, historyStore, "sales", function(old)
				old = type(old) == "table" and old or {}
				local saved = type(old[itemId]) == "table" and old[itemId] or {}
				table.insert(saved, sale)
				while #saved > RapConfig.HistoryKeep do
					table.remove(saved, 1)
				end
				old[itemId] = saved
				return old
			end)
		end)
	end
end

-- ---------- Hilfen ----------

local function inMarket(player)
	return player:GetAttribute("Mode") == Modes.Market.Id
end

-- Abstand des Spielers zum Stand (Prompt-Punkt vor der Theke)
local function distance(player, stand)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local anchor = stand.Folder:FindFirstChild("Prompt") or stand.Folder:FindFirstChild("Counter")
	if not root or not anchor then
		return math.huge
	end
	return (root.Position - anchor.Position).Magnitude
end

local function status(player, message, success)
	if player and player.Parent then
		Remotes.MarketStatus:FireClient(player, message, success)
	end
end

local function banner(player, caption, title, sub)
	if player and player.Parent then
		Remotes.Notify:FireClient(player, "Progress", { Caption = caption, Title = title, Sub = sub, Color = RapConfig.Color })
	end
end

local function itemName(id)
	local item = Cosmetics.Get(id)
	return item and item.Name or "Skin"
end

local function watchOf(player)
	local profile = ProgressService.Get(player)
	if profile and type(profile.MarketWatch) == "table" then
		return profile.MarketWatch
	end
	return nil
end

local function publishWatch(player)
	local list = {}
	for id in watchOf(player) or {} do
		table.insert(list, id)
	end
	table.sort(list)
	player:SetAttribute("MarketWatch", HttpService:JSONEncode(list))
end

-- Stand des Spielers (oder nil)
function MarketService.StandOf(player)
	return standOf[player]
end

function MarketService.Get(id)
	return stands[id]
end

-- Gegenangebote entfernen: slot = Platz (nil = alle), buyer = nur von diesem Käufer (nil = alle); message = Meldung an Käufer
local function dropOffers(stand, slot, buyer, message)
	local kept = {}
	for _, offer in stand.Offers do
		if (slot == nil or offer.Slot == slot) and (buyer == nil or offer.Buyer == buyer) then
			offer.Closed = true
			if message then
				status(offer.Buyer, message, false)
			end
		else
			table.insert(kept, offer)
		end
	end
	stand.Offers = kept
end

-- Stand abgeben: Angebote weg, Skins wieder frei. message = Meldung an den Spieler (nil = keine)
function MarketService.Release(player, message)
	local stand = standOf[player]
	if not stand then
		return false
	end
	standOf[player] = nil
	dropOffers(stand, nil, nil, "Der Stand " .. stand.Id .. " wurde abgegeben – dein Gegenangebot ist hinfällig.")
	stand.Owner = nil
	stand.Name = ""
	stand.Listings = {}
	EconomyService.ClearKey(player, MarketService.Key)
	publish(stand)
	if message and player.Parent then
		Remotes.MarketStatus:FireClient(player, message, true)
	end
	return true
end

-- Markt verlassen: Stand abgeben und eigene Gegenangebote an fremden Ständen zurückziehen
function MarketService.Leave(player, message)
	for _, stand in stands do
		dropOffers(stand, nil, player, nil)
		publish(stand)
	end
	return MarketService.Release(player, message)
end

-- Merkliste im Profil an den Spieler hängen (nach dem Betreten des Markts)
function MarketService.PublishWatch(player)
	publishWatch(player)
end

local function cleanName(text)
	if typeof(text) ~= "string" then
		return nil
	end
	text = (string.gsub(text, "%c", ""))
	text = (string.gsub(text, "^%s+", ""))
	text = (string.gsub(text, "%s+$", ""))
	text = (string.gsub(text, "%s%s+", " "))
	if utf8.len(text) == nil then
		return nil
	end
	if utf8.len(text) > RapConfig.StandNameLength then
		text = string.sub(text, 1, (utf8.offset(text, RapConfig.StandNameLength + 1) or (#text + 1)) - 1)
	end
	return text
end

local actions = {}

function actions.Claim(player, id)
	local stand = stands[tonumber(id) or 0]
	if not stand then
		return "Diesen Stand gibt es nicht.", false
	end
	if not inMarket(player) then
		return "Stände gibt es nur im Markt.", false
	end
	if standOf[player] == stand then
		return "Das ist schon dein Stand.", false
	end
	if standOf[player] then
		return "Du hast schon Stand " .. standOf[player].Id .. ". Gib ihn erst ab.", false
	end
	if stand.Owner then
		return "Stand " .. stand.Id .. " gehört schon " .. stand.Owner.Name .. ".", false
	end
	if distance(player, stand) > MarketService.ClaimRange then
		return "Geh näher an den Stand.", false
	end
	stand.Owner = player
	stand.Name = ""
	stand.Listings = {}
	stand.Offers = {}
	standOf[player] = stand
	publish(stand)
	return "Stand " .. stand.Id .. " gehört dir! Biete jetzt Skins an (MEIN STAND).", true
end

function actions.Release(player)
	if not MarketService.Release(player) then
		return "Du hast keinen Stand.", false
	end
	return "Stand abgegeben – deine Skins sind wieder frei.", true
end

function actions.List(player, itemId, price)
	local stand = standOf[player]
	if not stand then
		return "Du hast keinen Stand. Beanspruche zuerst einen freien.", false
	end
	local item = typeof(itemId) == "string" and Cosmetics.Get(itemId)
	if not item or not RapConfig.Tradeable(itemId) then
		return "Diesen Skin kann man nicht handeln.", false
	end
	price = RapConfig.CleanPrice(price)
	if not price then
		return "Preis zwischen " .. RapConfig.MinPrice .. " und " .. format(RapConfig.MaxPrice) .. " RAP.", false
	end
	local slot = nil
	for s = 1, RapConfig.StandSlots do
		if not stand.Listings[s] then
			slot = s
			break
		end
	end
	if not slot then
		return "Dein Stand ist voll (" .. RapConfig.StandSlots .. " Angebote).", false
	end
	if not ProgressService.IsLoaded(player) or not EconomyService.Reserve(player, itemId, 1, MarketService.Key) then
		return "Kein freies Stück von " .. item.Name .. " (liegt schon am Stand oder in einem Tausch).", false
	end
	stand.Listings[slot] = { Item = itemId, Price = price }
	publish(stand)
	-- Merkliste: wer diesen Skin gemerkt hat und im Markt ist, bekommt eine Meldung
	for _, other in Players:GetPlayers() do
		if other ~= player and inMarket(other) then
			local watch = watchOf(other)
			if watch and watch[itemId] then
				banner(other, "Markt · Merkliste", "NEUES ANGEBOT",
					item.Name .. "  ·  " .. format(price) .. " RAP  ·  Stand " .. stand.Id)
				status(other, item.Name .. " auf deiner Merkliste: Stand " .. stand.Id .. " für " .. format(price) .. " RAP.", true)
			end
		end
	end
	return item.Name .. " für " .. format(price) .. " RAP angeboten.", true
end

function actions.Unlist(player, slot)
	local stand = standOf[player]
	local listing = stand and stand.Listings[tonumber(slot) or 0]
	if not listing then
		return "Dieses Angebot gibt es nicht.", false
	end
	stand.Listings[tonumber(slot)] = nil
	dropOffers(stand, tonumber(slot), nil, "Das Angebot wurde zurückgenommen.")
	EconomyService.Unreserve(player, listing.Item, 1, MarketService.Key)
	publish(stand)
	return itemName(listing.Item) .. " zurückgenommen.", true
end

function actions.SetPrice(player, slot, price)
	local stand = standOf[player]
	local listing = stand and stand.Listings[tonumber(slot) or 0]
	if not listing then
		return "Dieses Angebot gibt es nicht.", false
	end
	price = RapConfig.CleanPrice(price)
	if not price then
		return "Preis zwischen " .. RapConfig.MinPrice .. " und " .. format(RapConfig.MaxPrice) .. " RAP.", false
	end
	listing.Price = price
	-- Gegenangebote, die jetzt nicht mehr unter dem Preis liegen, fallen weg
	local kept = {}
	for _, offer in stand.Offers do
		if offer.Slot == tonumber(slot) and offer.Price >= price then
			offer.Closed = true
			status(offer.Buyer, "Der Preis wurde auf " .. format(price) .. " RAP geändert – dein Gegenangebot ist hinfällig.", false)
		else
			table.insert(kept, offer)
		end
	end
	stand.Offers = kept
	publish(stand)
	return "Neuer Preis: " .. format(price) .. " RAP.", true
end

-- Stand-Name (leer = zurücksetzen). Läuft durch den Textfilter, weil ihn alle lesen.
function actions.Name(player, text)
	local stand = standOf[player]
	if not stand then
		return "Du hast keinen Stand.", false
	end
	text = cleanName(text)
	if text == nil then
		return "Dieser Name geht nicht.", false
	end
	if text ~= "" then
		local ok, result = pcall(function()
			local filtered = TextService:FilterStringAsync(text, player.UserId)
			return filtered:GetNonChatStringForBroadcastAsync()
		end)
		if not ok then
			return "Der Name konnte nicht geprüft werden – versuch es später nochmal.", false
		end
		text = result
	end
	stand.Name = text
	publish(stand)
	return text == "" and "Stand-Name entfernt." or ("Dein Stand heißt jetzt „" .. text .. "“."), true
end

-- Verkauf ausführen (Kauf zum Preis oder angenommenes Gegenangebot)
local function sell(stand, slot, buyer, price)
	local listing = stand.Listings[slot]
	local owner = stand.Owner
	if not listing or not owner then
		return "Dieses Angebot gibt es nicht mehr.", false
	end
	local item = Cosmetics.Get(listing.Item)
	local ok, reason = EconomyService.Exchange(owner, buyer, { Items = { [listing.Item] = 1 } }, { Rap = price },
		MarketService.Key, RapConfig.FeeRate(price))
	if not ok then
		return reason, false
	end
	stand.Listings[slot] = nil
	dropOffers(stand, slot, nil, "Der Skin ist inzwischen verkauft.")
	publish(stand)
	recordSale(listing.Item, price)
	local earned = RapConfig.AfterFee(price)
	local entry = sellers[owner.UserId] or { Name = owner.Name, Sales = 0, Volume = 0 }
	sellers[owner.UserId] = entry
	entry.Name, entry.Sales, entry.Volume = owner.Name, entry.Sales + 1, entry.Volume + price
	publishStats()
	Remotes.Notify:FireClient(owner, "Progress", { Caption = "Markt · Stand " .. stand.Id, Title = "VERKAUFT",
		Sub = item.Name .. " an " .. buyer.Name .. "  ·  +" .. format(earned) .. " RAP", Color = RapConfig.Color })
	Remotes.MarketStatus:FireClient(owner, item.Name .. " an " .. buyer.Name .. " verkauft: +" .. format(earned) .. " RAP", true)
	Remotes.Reward:FireClient(buyer, { Title = "GEKAUFT", Lines = { item.Name, "-" .. format(price) .. " RAP" },
		Rarity = item.Rarity })
	return item.Name .. " gekauft!", true
end

-- Kaufen: expected = Preis, den der Käufer gesehen hat (ändert der Besitzer ihn gerade, wird nicht gekauft)
function actions.Buy(player, id, slot, expected)
	local stand = stands[tonumber(id) or 0]
	local listing = stand and stand.Listings[tonumber(slot) or 0]
	if not stand or not stand.Owner or not listing then
		return "Dieses Angebot gibt es nicht mehr.", false
	end
	local owner = stand.Owner
	if owner == player then
		return "Das ist dein eigener Stand.", false
	end
	if not inMarket(player) then
		return "Kaufen kann man nur im Markt.", false
	end
	if tonumber(expected) ~= listing.Price then
		return "Der Preis hat sich geändert: jetzt " .. format(listing.Price) .. " RAP.", false
	end
	if distance(player, stand) > MarketService.BuyRange then
		return "Geh näher an den Stand.", false
	end
	if ProgressService.GetRap(player) < listing.Price then
		return "Nicht genug RAP (" .. format(listing.Price) .. " nötig).", false
	end
	return sell(stand, tonumber(slot), player, listing.Price)
end

-- Gegenangebot: unter dem Preis, mindestens MinOfferFraction davon; pro Käufer und Stand eins
function actions.Offer(player, id, slot, price)
	local stand = stands[tonumber(id) or 0]
	local listing = stand and stand.Listings[tonumber(slot) or 0]
	if not stand or not stand.Owner or not listing then
		return "Dieses Angebot gibt es nicht mehr.", false
	end
	if stand.Owner == player then
		return "Das ist dein eigener Stand.", false
	end
	if not inMarket(player) then
		return "Angebote machen kann man nur im Markt.", false
	end
	if distance(player, stand) > MarketService.BuyRange then
		return "Geh näher an den Stand.", false
	end
	price = RapConfig.CleanPrice(price)
	local minimum = math.ceil(listing.Price * RapConfig.MinOfferFraction)
	if not price or price < minimum then
		return "Dein Angebot muss mindestens " .. format(minimum) .. " RAP sein.", false
	end
	if price >= listing.Price then
		return "Das ist nicht weniger als der Preis – kauf den Skin einfach.", false
	end
	if ProgressService.GetRap(player) < price then
		return "Nicht genug RAP (" .. format(price) .. " nötig).", false
	end
	for _, offer in stand.Offers do
		if offer.Buyer == player then
			return "Du hast hier schon ein Angebot offen. Zieh es zurück oder warte auf die Antwort.", false
		end
	end
	if #stand.Offers >= RapConfig.MaxOffersPerStand then
		return "An diesem Stand sind gerade zu viele Angebote offen.", false
	end
	nextOfferId += 1
	local offer = { Id = nextOfferId, Slot = tonumber(slot), Item = listing.Item, Buyer = player, Price = price,
		Expires = os.time() + RapConfig.OfferSeconds }
	table.insert(stand.Offers, offer)
	publish(stand)
	banner(stand.Owner, "Markt · Stand " .. stand.Id, "GEGENANGEBOT",
		player.Name .. " bietet " .. format(price) .. " RAP für " .. itemName(listing.Item))
	status(stand.Owner, player.Name .. " bietet " .. format(price) .. " RAP für " .. itemName(listing.Item) .. " (MEIN STAND).", true)
	task.delay(RapConfig.OfferSeconds + 1, function()
		if offer.Closed then
			return
		end
		offer.Closed = true
		for index, other in stand.Offers do
			if other == offer then
				table.remove(stand.Offers, index)
				break
			end
		end
		publish(stand)
		status(player, "Dein Angebot für " .. itemName(offer.Item) .. " ist abgelaufen.", false)
	end)
	return "Angebot gesendet: " .. format(price) .. " RAP für " .. itemName(listing.Item) .. ". Der Besitzer hat "
		.. RapConfig.OfferSeconds .. " Sekunden.", true
end

-- Angebot zurückziehen (Käufer)
function actions.CancelOffer(player, offerId)
	for _, stand in stands do
		for _, offer in stand.Offers do
			if offer.Id == tonumber(offerId) and offer.Buyer == player then
				dropOffers(stand, offer.Slot, player, nil)
				publish(stand)
				return "Angebot zurückgezogen.", true
			end
		end
	end
	return "Dieses Angebot gibt es nicht mehr.", false
end

-- Antwort des Besitzers auf ein Gegenangebot
function actions.Answer(player, offerId, accept)
	local stand = standOf[player]
	local found = nil
	for _, offer in (stand and stand.Offers or {}) do
		if offer.Id == tonumber(offerId) then
			found = offer
		end
	end
	if not stand or not found then
		return "Dieses Angebot gibt es nicht mehr.", false
	end
	local buyer = found.Buyer
	if accept ~= true then
		dropOffers(stand, found.Slot, buyer, nil)
		publish(stand)
		status(buyer, player.Name .. " hat dein Angebot für " .. itemName(found.Item) .. " abgelehnt.", false)
		return "Angebot abgelehnt.", true
	end
	if not buyer.Parent or not inMarket(buyer) then
		dropOffers(stand, found.Slot, buyer, nil)
		publish(stand)
		return "Der Käufer ist nicht mehr im Markt.", false
	end
	local price = found.Price
	local slot = found.Slot
	dropOffers(stand, slot, buyer, nil) -- das eigene Angebot nicht mit "verkauft" melden
	local message, ok = sell(stand, slot, buyer, price)
	if not ok then
		publish(stand)
		status(buyer, "Dein Angebot für " .. itemName(found.Item) .. " ging nicht durch: " .. tostring(message), false)
		return message, false
	end
	return itemName(found.Item) .. " für " .. format(price) .. " RAP an " .. buyer.Name .. " verkauft.", true
end

-- Merkliste
function actions.Watch(player, itemId)
	local item = typeof(itemId) == "string" and Cosmetics.Get(itemId)
	if not item or not RapConfig.Tradeable(itemId) then
		return "Diesen Skin kann man nicht merken.", false
	end
	local profile = ProgressService.Get(player)
	if not profile or not ProgressService.IsLoaded(player) then
		return "Deine Daten sind noch nicht bereit.", false
	end
	if type(profile.MarketWatch) ~= "table" then
		profile.MarketWatch = {}
	end
	if profile.MarketWatch[itemId] then
		return item.Name .. " ist schon gemerkt.", false
	end
	local count = 0
	for _ in profile.MarketWatch do
		count += 1
	end
	if count >= RapConfig.WatchLimit then
		return "Deine Merkliste ist voll (" .. RapConfig.WatchLimit .. " Skins).", false
	end
	profile.MarketWatch[itemId] = true
	publishWatch(player)
	return item.Name .. " gemerkt – du bekommst eine Meldung, sobald jemand ihn anbietet.", true
end

function actions.Unwatch(player, itemId)
	local watch = watchOf(player)
	if not watch or typeof(itemId) ~= "string" or not watch[itemId] then
		return "Dieser Skin ist nicht auf deiner Merkliste.", false
	end
	watch[itemId] = nil
	publishWatch(player)
	return itemName(itemId) .. " von der Merkliste genommen.", true
end

-- Für Tests und andere Dienste: Aktion direkt ausführen (gibt Meldung und Erfolg zurück)
function MarketService.Do(player, action, ...)
	local handler = actions[action]
	if not handler then
		return "Unbekannte Aktion.", false
	end
	return handler(player, ...)
end

-- map = Maps.Market (Ordner "Stand_<n>" mit Prompt, OwnerSpot, Display1..)
function MarketService.Init(map)
	mapFolder = map
	for _, folder in map:GetChildren() do
		local id = tonumber(string.match(folder.Name, "^Stand_(%d+)$"))
		if id then
			stands[id] = { Id = id, Folder = folder, Owner = nil, Name = "", Listings = {}, Offers = {} }
			publish(stands[id])
		end
	end
	publishStats()
	-- Preisverlauf aus dem DataStore (alle Server) dazunehmen
	if historyStore then
		task.spawn(function()
			local ok, saved = pcall(historyStore.GetAsync, historyStore, "sales")
			if ok and type(saved) == "table" then
				for id, sales in saved do
					if type(sales) == "table" and typeof(id) == "string" then
						local merged = {}
						for _, sale in sales do
							if type(sale) == "table" and tonumber(sale.Time) and tonumber(sale.Price) then
								table.insert(merged, { Time = sale.Time, Price = sale.Price })
							end
						end
						for _, sale in history[id] or {} do
							table.insert(merged, sale)
						end
						table.sort(merged, function(a, b)
							return a.Time < b.Time
						end)
						while #merged > RapConfig.HistoryKeep do
							table.remove(merged, 1)
						end
						history[id] = merged
					end
				end
				publishStats()
			end
		end)
	end
	Remotes.MarketAction.OnServerEvent:Connect(function(player, action, a, b, c)
		local handler = typeof(action) == "string" and actions[action]
		if not handler then
			return
		end
		local now = os.clock()
		if lastAction[player] and now - lastAction[player] < MIN_INTERVAL then
			return
		end
		lastAction[player] = now
		local ok, message, success = pcall(handler, player, a, b, c)
		if not ok then
			warn("Markt-Fehler: " .. tostring(message))
			message, success = "Fehler, bitte nochmal versuchen.", false
		end
		if message then
			Remotes.MarketStatus:FireClient(player, message, success)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		MarketService.Leave(player)
		lastAction[player] = nil
	end)
end

return MarketService

-- ShopOffers (ModuleScript, Client und Server)
-- Angebote im SHOP:
--   * Angebot des Tages (automatisch): jeden Tag (UTC) ein kaufbarer Skin mit Rabatt, aus dem Datum berechnet, also auf
--     allen Servern gleich und ohne Speicher. Im Admin-Panel abschaltbar.
--   * Angebote aus dem Admin-Panel (Reiter SHOP): Skin, Rabatt, Dauer, optional HAUPTANGEBOT (groß auf der Startseite).
--     Gespeichert und an alle Server verteilt von ShopOfferService; hier liegen sie als JSON im Attribut "ShopOffers"
--     an ReplicatedStorage: { Offers = { { Id, Discount, Starts, Ends, Featured, By } }, AutoDaily = true }.
-- Der Server verlangt beim Kauf den günstigsten aktiven Angebotspreis (ShopService), der Shop zeigt das Hauptangebot
-- groß auf der Startseite und alle Angebote als Rabatt-Schild auf den Karten im Raster.
-- Zeit immer workspace:GetServerTimeNow() (Client und Server gleich).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Cosmetics = require(ReplicatedStorage:WaitForChild("Shared").Cosmetics)

local ShopOffers = {}

ShopOffers.DayLength = 24 * 3600
ShopOffers.MinPrice = 200 -- Test-Skins (Preis 1) und sehr billige Skins kommen nicht ins Angebot
ShopOffers.Discounts = { 20, 25, 30, 35, 40 } -- Rabatt in Prozent
ShopOffers.Attribute = "ShopOffers"     -- JSON an ReplicatedStorage (ShopOfferService)
ShopOffers.MaxOffers = 12               -- Angebote aus dem Admin-Panel gleichzeitig
ShopOffers.MinDiscount, ShopOffers.MaxDiscount = 5, 90
ShopOffers.MaxHours = 24 * 30           -- längste Dauer eines Angebots

-- Skins, die Angebot werden können (feste Reihenfolge aus Cosmetics.Items)
function ShopOffers.Pool()
	local list = {}
	for _, item in Cosmetics.Items do
		if Cosmetics.ForSale(item) and not item.Test and not item.Creator and item.Price >= ShopOffers.MinPrice then
			table.insert(list, item)
		end
	end
	return list
end

function ShopOffers.Day(now)
	return math.floor(now / ShopOffers.DayLength)
end

-- Ganzzahl-Streuung (deterministisch, keine Zufallsquelle)
local function hash(n)
	local h = (n * 2654435761 + 40503) % 4294967296
	return (h * 1103515245 + 12345) % 2147483648
end

-- Reihenfolge der Skins in einem Block von #pool Tagen: jeder Skin einmal, gemischt nach der Blocknummer
local function order(block, count)
	local list = table.create(count)
	for i = 1, count do
		list[i] = i
	end
	local state = hash(block + 7)
	for i = count, 2, -1 do
		state = (state * 1103515245 + 12345) % 2147483648
		local j = state % i + 1
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- Angebot zum Zeitpunkt now: { Item, Discount (Prozent), Price (Angebotspreis), OldPrice, EndsAt } oder nil
function ShopOffers.Daily(now)
	local pool = ShopOffers.Pool()
	if #pool == 0 then
		return nil
	end
	local day = ShopOffers.Day(now)
	local count = #pool
	local block = day // count
	local list = order(block, count)
	-- nicht zwei Tage hintereinander derselbe Skin (auch nicht über die Blockgrenze)
	if count >= 3 and list[1] == order(block - 1, count)[count] then
		list[1], list[2] = list[2], list[1]
	end
	local index = list[day % count + 1]
	local item = pool[index]
	local discount = ShopOffers.Discounts[hash(day) // 7 % #ShopOffers.Discounts + 1]
	local price = ShopOffers.Discounted(item.Price, discount)
	return { Item = item, Discount = discount, Price = price, OldPrice = item.Price,
		EndsAt = (day + 1) * ShopOffers.DayLength }
end

-- Angebotspreis: auf 10 gerundet, mindestens 1
function ShopOffers.Discounted(price, discount)
	return math.max(1, math.floor(price * (100 - discount) / 1000 + 0.5) * 10)
end

-- Darf dieser Skin ein Angebot aus dem Admin-Panel werden? (kaufbar, kein Creator-Skin)
function ShopOffers.Allowed(item)
	return item ~= nil and Cosmetics.ForSale(item) and not item.Creator
end

-- Einstellungen aus dem Attribut (oder config, z.B. auf dem Server): { Offers = {...}, AutoDaily = bool }
function ShopOffers.Config(config)
	if config == nil then
		local raw = ReplicatedStorage:GetAttribute(ShopOffers.Attribute)
		local ok, data = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "{}")
		config = ok and type(data) == "table" and data or {}
	end
	return { Offers = type(config.Offers) == "table" and config.Offers or {}, AutoDaily = config.AutoDaily ~= false }
end

-- Alle aktiven Angebote zum Zeitpunkt now: Hauptangebote zuerst, dann die aus dem Admin-Panel (neueste zuerst), dann
-- das Angebot des Tages (falls an und sein Skin nicht schon im Angebot ist). Ein Eintrag: { Item, Discount, Price,
-- OldPrice, EndsAt, Featured, Manual }.
function ShopOffers.Active(now, config)
	config = ShopOffers.Config(config)
	local list, seen = {}, {}
	for _, entry in config.Offers do
		local item = type(entry) == "table" and Cosmetics.Get(entry.Id)
		local discount = tonumber(entry.Discount)
		if item and ShopOffers.Allowed(item) and discount and (tonumber(entry.Starts) or 0) <= now
			and now < (tonumber(entry.Ends) or 0) then
			discount = math.clamp(math.floor(discount), ShopOffers.MinDiscount, ShopOffers.MaxDiscount)
			table.insert(list, { Item = item, Discount = discount, Price = ShopOffers.Discounted(item.Price, discount),
				OldPrice = item.Price, EndsAt = tonumber(entry.Ends), Featured = entry.Featured == true, Manual = true,
				Starts = tonumber(entry.Starts) or 0 })
			seen[item.Id] = true
		end
	end
	table.sort(list, function(a, b)
		if a.Featured ~= b.Featured then
			return a.Featured
		end
		return a.Starts > b.Starts
	end)
	if config.AutoDaily then
		local daily = ShopOffers.Daily(now)
		if daily and not seen[daily.Item.Id] then
			table.insert(list, daily)
		end
	end
	return list
end

-- Angebot für die Startseite (das erste aktive) oder nil
function ShopOffers.Featured(now, config)
	return ShopOffers.Active(now, config)[1]
end

-- Preis eines Skins zum Zeitpunkt now: der günstigste aktive Angebotspreis, sonst der normale. Zweiter Wert: das Angebot.
function ShopOffers.PriceFor(item, now, config)
	local best = nil
	for _, offer in ShopOffers.Active(now, config) do
		if offer.Item.Id == item.Id and (not best or offer.Price < best.Price) then
			best = offer
		end
	end
	if best then
		return best.Price, best
	end
	return item.Price, nil
end

-- Restzeit als "HH:MM:SS", ab einem Tag "3 T 04:05:06"
local function clock(seconds)
	return string.format("%02d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
end

function ShopOffers.FormatLeft(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 86400 then
		return (seconds // 86400) .. " T " .. clock(seconds % 86400)
	end
	return clock(seconds)
end

return ShopOffers

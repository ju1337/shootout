-- ShopOffers (ModuleScript, Client und Server)
-- Angebot des Tages im SHOP: jeden Tag (UTC) ein kaufbarer Skin mit Rabatt. Aus dem Datum berechnet, also auf allen
-- Servern gleich und ohne Speicher. Der Server verlangt beim Kauf den Angebotspreis (ShopService), der Shop zeigt ihn
-- groß auf der Startseite und als Rabatt-Schild auf der Karte im Raster.
-- Zeit immer workspace:GetServerTimeNow() (Client und Server gleich).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmetics = require(ReplicatedStorage:WaitForChild("Shared").Cosmetics)

local ShopOffers = {}

ShopOffers.DayLength = 24 * 3600
ShopOffers.MinPrice = 200 -- Test-Skins (Preis 1) und sehr billige Skins kommen nicht ins Angebot
ShopOffers.Discounts = { 20, 25, 30, 35, 40 } -- Rabatt in Prozent

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
	local price = math.max(1, math.floor(item.Price * (100 - discount) / 1000 + 0.5) * 10)
	return { Item = item, Discount = discount, Price = price, OldPrice = item.Price,
		EndsAt = (day + 1) * ShopOffers.DayLength }
end

-- Preis eines Skins zum Zeitpunkt now (Angebotspreis, wenn er gerade das Angebot ist)
function ShopOffers.PriceFor(item, now)
	local offer = ShopOffers.Daily(now)
	if offer and offer.Item.Id == item.Id then
		return offer.Price, offer
	end
	return item.Price, nil
end

-- Restzeit als "HH:MM:SS"
function ShopOffers.FormatLeft(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d:%02d", seconds // 3600, seconds % 3600 // 60, seconds % 60)
end

return ShopOffers

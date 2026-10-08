-- MarketSearch (ModuleScript, geteilt)
-- Suche, Filter und Sortierung für alle Angebote im Markt (Fenster SUCHE im MarketClient). Reine Logik ohne
-- Oberfläche, damit sie sich testen lässt: Eingabe sind die Angebote aller Stände, Ausgabe die gefilterte, sortierte Liste.
--   Eintrag: { Stand = Nummer, Owner = UserId, OwnerName = Name, Slot = Platz, Item = Skin-Id, Price = RAP }
--   Zustand: { Text = "lava rot", Rarity = "Epic" | nil, MaxPrice = Zahl | nil, Sort = Id }
--   Es gibt nur Waffen-Skins, darum gibt es keinen Filter nach Art.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)
local RapConfig = require(Shared.RapConfig)

local MarketSearch = {}

MarketSearch.RarityOrder = { "Common", "Rare", "Epic", "Legendary" }
MarketSearch.Sorts = {
	{ Id = "PriceAsc", Name = "PREIS ▲" },
	{ Id = "PriceDesc", Name = "PREIS ▼" },
	{ Id = "Deal", Name = "SCHNÄPPCHEN" },
	{ Id = "Rarity", Name = "SELTENHEIT" },
}

function MarketSearch.NewState()
	return { Text = "", Rarity = nil, MaxPrice = nil, Sort = "PriceAsc" }
end

-- klein, ohne Umlaute: "Großmeister" findet man auch mit "grossmeister"
local function fold(text)
	text = string.lower(tostring(text))
	text = string.gsub(text, "ä", "a")
	text = string.gsub(text, "ö", "o")
	text = string.gsub(text, "ü", "u")
	text = string.gsub(text, "Ä", "a")
	text = string.gsub(text, "Ö", "o")
	text = string.gsub(text, "Ü", "u")
	text = string.gsub(text, "ß", "ss")
	return text
end
MarketSearch.Fold = fold

-- Wie weit der Preis über (+) oder unter (-) dem RAP-Wert liegt (0 = gleich, ohne Wert ebenfalls 0)
function MarketSearch.Diff(item, price)
	local value = RapConfig.Value(item.Id) or 0
	if value <= 0 then
		return 0
	end
	return price / value - 1
end

-- Suchtext durch Leerzeichen getrennt: jedes Wort muss in Skin-Name, Seltenheit, Art oder Standbesitzer vorkommen
local function matches(entry, item, terms)
	if #terms == 0 then
		return true
	end
	local rarity = Cosmetics.Rarities[item.Rarity]
	local haystack = { item.Name, rarity and rarity.Name or "", entry.OwnerName or "", "stand " .. tostring(entry.Stand),
		"waffe", "waffen-skin" }
	local text = fold(table.concat(haystack, " "))
	for _, term in terms do
		if not string.find(text, term, 1, true) then
			return false
		end
	end
	return true
end

-- Gefilterte und sortierte Liste (neue Tabelle; jeder Eintrag bekommt .ItemData und .Diff)
function MarketSearch.Run(entries, state)
	state = state or MarketSearch.NewState()
	local terms = {}
	for word in string.gmatch(fold(state.Text or ""), "%S+") do
		table.insert(terms, word)
	end
	local rank = {}
	for index, id in MarketSearch.RarityOrder do
		rank[id] = index
	end
	local result = {}
	for _, entry in entries do
		local item = Cosmetics.Get(entry.Item)
		if item
			and (not state.Rarity or item.Rarity == state.Rarity)
			and (not state.MaxPrice or entry.Price <= state.MaxPrice)
			and matches(entry, item, terms)
		then
			table.insert(result, { Stand = entry.Stand, Owner = entry.Owner, OwnerName = entry.OwnerName, Slot = entry.Slot,
				Item = entry.Item, Price = entry.Price, ItemData = item, Diff = MarketSearch.Diff(item, entry.Price) })
		end
	end
	local sort = state.Sort or "PriceAsc"
	table.sort(result, function(a, b)
		local ka, kb
		if sort == "PriceDesc" then
			ka, kb = -a.Price, -b.Price
		elseif sort == "Deal" then
			ka, kb = a.Diff, b.Diff
		elseif sort == "Rarity" then
			ka, kb = -(rank[a.ItemData.Rarity] or 0), -(rank[b.ItemData.Rarity] or 0)
		else
			ka, kb = a.Price, b.Price
		end
		if ka ~= kb then
			return ka < kb
		end
		if a.Price ~= b.Price then
			return a.Price < b.Price
		end
		if a.Stand ~= b.Stand then
			return a.Stand < b.Stand
		end
		return a.Slot < b.Slot
	end)
	return result
end

return MarketSearch

-- Marktsuche: Textsuche (Name, Seltenheit, Besitzer, Art, ohne Umlaute), Filter (Seltenheit, Art, Höchstpreis),
-- Sortierung (Preis, Schnäppchen, Seltenheit) – stabil und ohne fremde Angebote zu verlieren
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local MarketSearch = require("MarketSearch")
local Cosmetics = require("Cosmetics")
local RapConfig = require("RapConfig")

-- ein Skin je Seltenheit (handelbar, mit RAP-Wert), dazu ein Agenten-Skin falls vorhanden
local byRarity, agentItem = {}, nil
for _, item in Cosmetics.Items do
	if RapConfig.Tradeable(item.Id) and (RapConfig.Value(item.Id) or 0) > 0 then
		if item.Type == "Weapon" and not byRarity[item.Rarity] then
			byRarity[item.Rarity] = item
		elseif item.Type == "Agent" and not agentItem then
			agentItem = item
		end
	end
end
check(byRarity.Rare and byRarity.Epic and byRarity.Legendary, "Testdaten: handelbare Skins in drei Seltenheiten")
local rare, epic, legend = byRarity.Rare, byRarity.Epic, byRarity.Legendary

local function entry(stand, slot, item, price, owner)
	return { Stand = stand, Owner = 100 + stand, OwnerName = owner or ("Spieler" .. stand), Slot = slot, Item = item.Id, Price = price }
end
local value = function(item) return RapConfig.Value(item.Id) end
local entries = {
	entry(3, 1, legend, value(legend) * 2, "Bob"),
	entry(1, 1, rare, value(rare)),
	entry(1, 2, epic, math.floor(value(epic) * 0.5), "Alice"),
	entry(2, 1, epic, value(epic) * 3),
	entry(2, 2, legend, value(legend), "Carl"),
}

local function ids(list)
	local out = {}
	for _, e in list do
		table.insert(out, e.Stand .. "." .. e.Slot)
	end
	return table.concat(out, " ")
end

local state = MarketSearch.NewState()
check(#MarketSearch.Run(entries, state) == 5, "ohne Filter alle Angebote")
check(#MarketSearch.Run(entries, nil) == 5, "ohne Zustand ebenfalls")

-- Sortierung
state.Sort = "PriceAsc"
local list = MarketSearch.Run(entries, state)
for i = 2, #list do
	check(list[i - 1].Price <= list[i].Price, "Preis aufsteigend (" .. i .. ")")
end
state.Sort = "PriceDesc"
list = MarketSearch.Run(entries, state)
for i = 2, #list do
	check(list[i - 1].Price >= list[i].Price, "Preis absteigend (" .. i .. ")")
end
state.Sort = "Deal"
list = MarketSearch.Run(entries, state)
check(list[1].Stand == 1 and list[1].Slot == 2, "Schnäppchen: halber RAP-Wert zuerst (" .. ids(list) .. ")")
check(list[#list].Diff > 0, "Schnäppchen: teuerstes zuletzt")
check(list[1].Diff < 0 and math.abs(list[1].Diff + 0.5) < 0.05, "Abstand zum RAP-Wert: etwa -50 %")
state.Sort = "Rarity"
list = MarketSearch.Run(entries, state)
check(list[1].ItemData.Rarity == "Legendary" and list[#list].ItemData.Rarity == "Rare", "Seltenheit: legendär zuerst")

-- Filter
state = MarketSearch.NewState()
state.Rarity = "Epic"
check(#MarketSearch.Run(entries, state) == 2, "Seltenheit Episch")
state.Rarity = nil
state.Type = "Agent"
check(#MarketSearch.Run(entries, state) == 0, "keine Agenten-Skins im Angebot")
state.Type = "Weapon"
check(#MarketSearch.Run(entries, state) == 5, "Art Waffen")
state.Type = nil
state.MaxPrice = value(rare)
list = MarketSearch.Run(entries, state)
check(#list >= 1 and list[#list].Price <= value(rare), "Höchstpreis")

-- Text: Skin-Name, Seltenheit, Besitzer, Stand, mehrere Wörter, Umlaute
state = MarketSearch.NewState()
state.Text = string.lower(legend.Name)
check(#MarketSearch.Run(entries, state) >= 2, "Suche nach Skin-Name")
state.Text = "BOB"
check(ids(MarketSearch.Run(entries, state)) == "3.1", "Suche nach Besitzer, Groß-/Kleinschreibung egal")
state.Text = "stand 2"
check(#MarketSearch.Run(entries, state) == 2, "Suche nach Standnummer")
state.Text = MarketSearch.Rarities and "" or "episch"
check(#MarketSearch.Run(entries, state) == 2, "Suche nach Seltenheit")
state.Text = "episch alice"
check(ids(MarketSearch.Run(entries, state)) == "1.2", "mehrere Wörter: alle müssen passen")
state.Text = "nichtda"
check(#MarketSearch.Run(entries, state) == 0, "nichts gefunden")
check(MarketSearch.Fold("Großmeister Ärger Übung") == "grossmeister arger ubung", "Umlaute und ß werden gefaltet")

-- unbekannte Skins fallen weg, Eingabe wird nicht verändert
local before = #entries
local withGhost = { table.unpack(entries) }
table.insert(withGhost, { Stand = 9, Owner = 1, OwnerName = "x", Slot = 1, Item = "gibt_es_nicht", Price = 5 })
check(#MarketSearch.Run(withGhost, MarketSearch.NewState()) == 5, "unbekannter Skin wird ignoriert")
check(#entries == before and entries[1].ItemData == nil, "Eingabe bleibt unverändert")

if failures == 0 then
	print("Marktsuche: alles in Ordnung")
end

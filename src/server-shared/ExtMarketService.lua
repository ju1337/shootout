-- ExtMarketService (ModuleScript, nur Server)
-- Spielermarkt der offenen Welt (EXTINCTION), Reiter MARKT im Extinction-Menü: Spieler handeln untereinander mit allem
-- aus der Tasche – Waffen (samt Magazin), Munition, Heilung, Rüstung, Spritzen und Fahrzeuge – für Münzen
-- (ExtinctionConfig.Market). Alle Aktionen gehen überall in einer Safe Zone (lebend, im Survival-Modus); draußen nicht.
--   * MarketList(slot, count, price): count Stück vom Platz slot der Tasche anbieten (Stapel auch teilweise). Das Item
--     verlässt die Tasche und liegt als Angebot im Spielstand des Verkäufers (InventoryService.MarketOf) – es geht nicht
--     verloren, wenn er stirbt oder das Spiel verlässt; sichtbar ist es, solange er auf dem Server ist. At = Zeitpunkt
--     des Einstellens (os.time()), damit die Clients nach NEU sortieren können.
--   * MarketBuy(id, price): nur zum gesehenen Preis, mit Platz in der Tasche und genug Münzen. Das Item kommt in die
--     Tasche des Käufers, der Verkäufer bekommt den Preis minus FeeRate (ohne VIP-Verdopplung), beide eine Meldung, beide
--     Spielstände werden sofort gespeichert.
--   * MarketPrice(id, price): der Verkäufer ändert den Preis seines Angebots (gleiche Grenzen wie beim Anbieten; At bleibt).
--   * MarketCancel(id): der Verkäufer nimmt sein Angebot zurück in die Tasche.
-- Für die Clients: Attribut "PlayerMarket" an der Karte (JSON [{ Id, Seller, SellerName, Item, Count, Mag, Price, At }],
-- billigste zuerst). Meldungen über Remotes.ExtUpdate("Status", Text, Erfolg).

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Modes = require(Shared.Modes)
local ProgressService = require(script.Parent.ProgressService)
local InventoryService = require(script.Parent.InventoryService)

local ExtMarketService = {}

local M = ExtinctionConfig.Market
local SAFE_ONLY = "Handeln geht nur in der Safe Zone."
local map = nil
local options = nil -- { Map, InSafeZone(position) -> bool }
local lastPublished = nil

local function status(player, text, ok)
	InventoryService.Status(player, text, ok)
end

-- Ganze Zahl vom Client (NaN und Unendlich abfangen), sonst nil
local function whole(value)
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return math.floor(n)
end

local function itemText(entry)
	local config = ExtinctionConfig.Get(entry.Item)
	return (entry.Count > 1 and (entry.Count .. "× ") or "") .. (config and config.Name or entry.Item)
end

-- Ist der Spieler lebend in einer Safe Zone (in der offenen Welt)? Serverseitig nachgerechnet (InSafeZone aus
-- Extinction), sonst das Attribut "InSafeZone", das Extinction setzt.
local function inSafeZone(player)
	if not Modes.IsSurvival(player:GetAttribute("Mode")) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then
		return false
	end
	if options and options.InSafeZone then
		return options.InSafeZone(root.Position) == true
	end
	return player:GetAttribute("InSafeZone") == true
end

-- Gültiger Preis (ganze Zahl in den Grenzen) oder nil samt Meldung an den Spieler
local function validPrice(player, value)
	local price = whole(value)
	if not price or price < 1 or price > M.MaxPrice then
		status(player, "Preis zwischen 1 und " .. M.MaxPrice .. " Münzen.")
		return nil
	end
	return price
end

-- Eigenes Angebot id des Spielers (aus seinem Spielstand) oder nil
local function ownEntry(player, id)
	for _, candidate in InventoryService.MarketOf(player) or {} do
		if candidate.Id == id then
			return candidate
		end
	end
	return nil
end

-- Alle sichtbaren Angebote (Verkäufer auf dem Server): { Entry, Seller }
local function allListings()
	local list = {}
	for _, seller in Players:GetPlayers() do
		for _, entry in InventoryService.MarketOf(seller) or {} do
			table.insert(list, { Entry = entry, Seller = seller })
		end
	end
	return list
end

local function find(id)
	for _, listing in allListings() do
		if listing.Entry.Id == id then
			return listing
		end
	end
	return nil
end

-- Angebote an die Clients (nur bei Änderung)
function ExtMarketService.Publish()
	if not map then
		return
	end
	local list = {}
	for _, listing in allListings() do
		local entry = listing.Entry
		table.insert(list, { Id = entry.Id, Seller = listing.Seller.UserId, SellerName = listing.Seller.Name, Item = entry.Item,
			Count = entry.Count, Mag = entry.Mag, Att = entry.Att, Price = entry.Price, At = entry.At or 0 })
	end
	table.sort(list, function(a, b)
		if a.Price ~= b.Price then
			return a.Price < b.Price
		end
		return a.Id < b.Id
	end)
	local text = HttpService:JSONEncode(list)
	if text ~= lastPublished then
		lastPublished = text
		map:SetAttribute("PlayerMarket", text)
	end
end

-- Angebot aufgeben: count Stück vom Taschenplatz slot zum Preis price
function ExtMarketService.List(player, slot, count, price)
	if not inSafeZone(player) then
		status(player, SAFE_ONLY)
		return false
	end
	local market = InventoryService.MarketOf(player)
	if not market or type(slot) ~= "number" then
		return false
	end
	if #market >= M.MaxListings then
		status(player, "Du hast schon " .. M.MaxListings .. " Angebote – nimm erst eins zurück.")
		return false
	end
	price = validPrice(player, price)
	if not price then
		return false
	end
	-- Items aus Kits (ExtinctionConfig.KitVariants) sind unverkäuflich
	local bag = InventoryService.GetBag(player)
	local offered = bag and bag.Slots[slot]
	local offeredConfig = offered and ExtinctionConfig.Get(offered.Id)
	if offeredConfig and offeredConfig.Kit then
		status(player, "Items aus Kits kann man nicht verkaufen.")
		return false
	end
	local taken, reason = InventoryService.TakeSlot(player, slot, whole(count))
	if not taken then
		status(player, reason or "Das geht nicht.")
		return false
	end
	local entry = { Id = HttpService:GenerateGUID(false), Item = taken.Id, Count = taken.Count, Mag = taken.Mag, Att = taken.Att, Price = price,
		At = os.time() }
	table.insert(market, entry)
	InventoryService.Changed(player)
	ExtMarketService.Publish()
	status(player, "Angeboten: " .. itemText(entry) .. " für " .. price .. " Münzen", true)
	return true
end

-- Kaufen: Angebot id zum gesehenen Preis price
function ExtMarketService.Buy(player, id, price)
	if not inSafeZone(player) then
		status(player, SAFE_ONLY)
		return false
	end
	local listing = type(id) == "string" and find(id)
	if not listing then
		status(player, "Das Angebot gibt es nicht mehr.")
		return false
	end
	local entry, seller = listing.Entry, listing.Seller
	if seller == player then
		status(player, "Das ist dein eigenes Angebot.")
		return false
	end
	-- beide Profile müssen gerade gespeichert werden können (sonst Doppel-Item bzw. verlorene Münzen beim Verkäufer)
	if not seller.Parent or not ProgressService.IsLoaded(seller) or not ProgressService.IsLoaded(player) then
		status(player, "Gerade nicht möglich, bitte später nochmal.")
		return false
	end
	if whole(price) ~= entry.Price then
		status(player, "Der Preis hat sich geändert.")
		return false
	end
	if not InventoryService.HasSpace(player, entry.Item, entry.Count) then
		status(player, "Kein Platz in deiner Tasche.")
		return false
	end
	if not ProgressService.SpendCoins(player, entry.Price, "Spielermarkt", entry.Item) then
		status(player, "Nicht genug Münzen (" .. entry.Price .. " nötig).")
		return false
	end
	local market = InventoryService.MarketOf(seller)
	local index = market and table.find(market, entry)
	if not index then -- kann nach SpendCoins nicht passieren (kein Warten dazwischen), aber sicher ist sicher
		ProgressService.AddCoins(player, entry.Price, "Verkauf")
		return false
	end
	table.remove(market, index)
	InventoryService.Give(player, entry.Item, entry.Count, { Mag = entry.Mag, Att = entry.Att })
	local earned = entry.Price - math.floor(entry.Price * M.FeeRate)
	ProgressService.AddCoins(seller, earned, "Markt")
	InventoryService.Changed(seller)
	ExtMarketService.Publish()
	status(player, "Gekauft: " .. itemText(entry) .. " von " .. seller.Name .. " für " .. entry.Price .. " Münzen", true)
	status(seller, "Verkauft auf dem Markt: " .. itemText(entry) .. " an " .. player.Name .. " · +" .. earned .. " Münzen", true)
	task.spawn(ProgressService.SaveNow, player)
	task.spawn(ProgressService.SaveNow, seller)
	return true
end

-- Preis eines eigenen Angebots ändern (in der Safe Zone; Einstellzeit At bleibt)
function ExtMarketService.Price(player, id, price)
	if not inSafeZone(player) then
		status(player, SAFE_ONLY)
		return false
	end
	local entry = type(id) == "string" and ownEntry(player, id)
	if not entry then
		status(player, "Das Angebot gibt es nicht mehr.")
		return false
	end
	price = validPrice(player, price)
	if not price then
		return false
	end
	if price == entry.Price then
		return false
	end
	entry.Price = price
	InventoryService.Changed(player)
	ExtMarketService.Publish()
	status(player, "Neuer Preis: " .. itemText(entry) .. " für " .. price .. " Münzen", true)
	return true
end

-- Eigenes Angebot zurücknehmen (in der Safe Zone, mit Platz in der Tasche)
function ExtMarketService.Cancel(player, id)
	if not inSafeZone(player) then
		status(player, SAFE_ONLY)
		return false
	end
	local market = InventoryService.MarketOf(player)
	local entry = ownEntry(player, id)
	if not market or not entry then
		return false
	end
	if not InventoryService.HasSpace(player, entry.Item, entry.Count) then
		status(player, "Kein Platz in deiner Tasche.")
		return false
	end
	table.remove(market, table.find(market, entry))
	InventoryService.Give(player, entry.Item, entry.Count, { Mag = entry.Mag, Att = entry.Att })
	InventoryService.Changed(player)
	ExtMarketService.Publish()
	status(player, "Zurückgenommen: " .. itemText(entry), true)
	return true
end

-- opts = { Map, InSafeZone(position) -> bool (ohne: Spieler-Attribut "InSafeZone") }
function ExtMarketService.Init(opts)
	options = opts
	map = opts.Map
	InventoryService.Handlers.MarketList = ExtMarketService.List
	InventoryService.Handlers.MarketBuy = ExtMarketService.Buy
	InventoryService.Handlers.MarketPrice = ExtMarketService.Price
	InventoryService.Handlers.MarketCancel = ExtMarketService.Cancel
	-- Spieler kommen und gehen (ihre Angebote mit ihnen), Spielstände laden später: regelmäßig nachsehen
	Players.PlayerRemoving:Connect(function()
		task.defer(ExtMarketService.Publish)
	end)
	task.spawn(function()
		while true do
			ExtMarketService.Publish()
			task.wait(3)
		end
	end)
end

return ExtMarketService

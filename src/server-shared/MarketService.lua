-- MarketService (ModuleScript, nur Server)
-- Stände in der Markthalle (wie die Trading Plaza in Pet Simulator / Sniper Arena):
--   * Claim: Ein freier Stand gehört dem Spieler, solange er im Markt bleibt (einer pro Spieler). Er steht danach
--     hinter seiner Theke.
--   * List / Unlist / SetPrice: bis zu RapConfig.StandSlots handelbare Skins zum selbst gewählten RAP-Preis
--     anbieten. Die Skins bleiben im Inventar, sind aber zurückgelegt (EconomyService, Schlüssel "Stand").
--   * Buy: Andere Spieler kaufen am Stand (nur in der Nähe und nur zum angezeigten Preis): Der Skin wandert zum
--     Käufer, das RAP zum Besitzer (minus RapConfig.MarketFee), beide Spielstände werden gespeichert und beide
--     bekommen eine Meldung.
--   * Release: Stand abgeben – auch von selbst, sobald der Besitzer den Markt verlässt (Runde, Hub) oder das Spiel.
--     Seine Skins sind dann wieder frei, jemand anderes kann den Stand nehmen.
-- Zustand für alle Clients als Attribute am Stand-Ordner (Maps.Market.Stand_<n>): Owner (UserId, 0 = frei),
-- OwnerName, Listings (JSON [{ Slot, Item, Price }]). Remotes: MarketAction (Client -> Server), MarketStatus
-- (Server -> Client: Text, Erfolg).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Cosmetics = require(Shared.Cosmetics)
local RapConfig = require(Shared.RapConfig)
local Modes = require(Shared.Modes)
local ProgressService = require(script.Parent.ProgressService)
local EconomyService = require(script.Parent.EconomyService)
local MovementGuard = require(script.Parent.MovementGuard)

local MarketService = {}

MarketService.Key = "Stand"     -- Schlüssel der Reservierungen
MarketService.ClaimRange = 18   -- so nah muss man zum Beanspruchen am Stand sein (Studs)
MarketService.BuyRange = 22     -- und zum Kaufen
local MIN_INTERVAL = 0.15       -- Anfragen pro Spieler höchstens so oft

local stands = {}     -- [Nummer] = { Id, Folder, Owner, Listings = { [Platz] = { Item, Price } } }
local standOf = {}    -- [Player] = Stand
local lastAction = {} -- [Player] = os.clock()
local format = EconomyService.Format

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
	stand.Folder:SetAttribute("Listings", HttpService:JSONEncode(list))
end

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

-- Stand des Spielers (oder nil)
function MarketService.StandOf(player)
	return standOf[player]
end

function MarketService.Get(id)
	return stands[id]
end

-- Stand abgeben: Angebote weg, Skins wieder frei. message = Meldung an den Spieler (nil = keine)
function MarketService.Release(player, message)
	local stand = standOf[player]
	if not stand then
		return false
	end
	standOf[player] = nil
	stand.Owner = nil
	stand.Listings = {}
	EconomyService.ClearKey(player, MarketService.Key)
	publish(stand)
	if message and player.Parent then
		Remotes.MarketStatus:FireClient(player, message, true)
	end
	return true
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
	stand.Listings = {}
	standOf[player] = stand
	publish(stand)
	-- hinter die eigene Theke stellen
	local spot = stand.Folder:FindFirstChild("OwnerSpot")
	local character = player.Character
	if spot and character then
		character:PivotTo(spot.CFrame + Vector3.new(0, 2.7, 0)) -- Füße knapp über dem Podest
		MovementGuard.Teleported(character)
	end
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
	return item.Name .. " für " .. format(price) .. " RAP angeboten.", true
end

function actions.Unlist(player, slot)
	local stand = standOf[player]
	local listing = stand and stand.Listings[tonumber(slot) or 0]
	if not listing then
		return "Dieses Angebot gibt es nicht.", false
	end
	stand.Listings[tonumber(slot)] = nil
	EconomyService.Unreserve(player, listing.Item, 1, MarketService.Key)
	publish(stand)
	local item = Cosmetics.Get(listing.Item)
	return (item and item.Name or "Skin") .. " zurückgenommen.", true
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
	publish(stand)
	return "Neuer Preis: " .. format(price) .. " RAP.", true
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
	local item = Cosmetics.Get(listing.Item)
	local ok, reason = EconomyService.Exchange(owner, player, { Items = { [listing.Item] = 1 } }, { Rap = listing.Price },
		MarketService.Key, RapConfig.MarketFee)
	if not ok then
		return reason, false
	end
	stand.Listings[tonumber(slot)] = nil
	publish(stand)
	local earned = RapConfig.AfterFee(listing.Price)
	Remotes.Notify:FireClient(owner, "Progress", { Caption = "Markt · Stand " .. stand.Id, Title = "VERKAUFT",
		Sub = item.Name .. " an " .. player.Name .. "  ·  +" .. format(earned) .. " RAP", Color = RapConfig.Color })
	Remotes.MarketStatus:FireClient(owner, item.Name .. " an " .. player.Name .. " verkauft: +" .. format(earned) .. " RAP", true)
	Remotes.Reward:FireClient(player, { Title = "GEKAUFT", Lines = { item.Name, "-" .. format(listing.Price) .. " RAP" },
		Rarity = item.Rarity })
	return item.Name .. " gekauft!", true
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
	for _, folder in map:GetChildren() do
		local id = tonumber(string.match(folder.Name, "^Stand_(%d+)$"))
		if id then
			stands[id] = { Id = id, Folder = folder, Owner = nil, Listings = {} }
			publish(stands[id])
		end
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
		MarketService.Release(player)
		lastAction[player] = nil
	end)
end

return MarketService

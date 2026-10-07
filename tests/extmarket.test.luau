-- Spielermarkt der offenen Welt (ExtMarketService): nur am Marktstand; Anbieten nimmt das Item (auch Teile eines Stapels,
-- Waffe mit Magazin) aus der Tasche in den Spielstand; Preis- und Mengengrenzen, höchstens MaxListings, kein draußen
-- stehendes Fahrzeug; Kaufen nur zum gesehenen Preis, mit Münzen und Platz, nicht das eigene; Verkäufer bekommt den Preis
-- minus Gebühr (VIP verdoppelt das nicht); Zurücknehmen; Angebote überleben den Tod und das Verlassen (dann unsichtbar,
-- beim Wiederkommen wieder da); Attribut PlayerMarket an der Karte
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 1, 20)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local HttpService = game:GetService("HttpService")
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
local Remotes = require("Remotes")
ProgressService.Init()
WeaponService.Init()

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
local marketPart = Instance.new("Part", map.Stands)
marketPart.Name = "Stand_Market"
marketPart.CFrame = CFrame.new(CENTER + Vector3.new(64, 2.5, -37))

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local ExtMarketService = require("ExtMarketService")
local Inventory = require("Inventory")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0
ExtinctionConfig.Redzone.Enabled = false
Extinction.Init({ Join = function() end, Status = function() end })
local M = ExtinctionConfig.Market

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 1000, Rap = 0, Owned = {}, Equipped = {} }
local alice, bob = SIM.Join("Alice"), SIM.Join("Bob")
for _, player in { alice, bob } do
	Instance.new("Backpack", player).Name = "Backpack"
end
step(2)
for _, player in { alice, bob } do
	player:SetAttribute("Mode", "Extinction")
	Extinction.AddPlayer(player)
end
step(0.5)
local function place(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
	step(0.2)
end
local function atMarket(player)
	place(player, Vector3.new(60, 3, -34))
end
local function market()
	return HttpService:JSONDecode(map:GetAttribute("PlayerMarket") or "[]")
end
local function lastStatus(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "ExtUpdate" and entry.Player == player and entry.Args[1] == "Status" then
			return entry.Args[2]
		end
	end
	return ""
end
local function slotOf(player, id)
	local bag = InventoryService.GetBag(player)
	for slot = 1, bag.Size do
		local item = bag.Slots[slot]
		if item and item.Id == id then
			return slot, item
		end
	end
	return nil, nil
end
local function action(player, ...)
	Remotes.ExtAction.OnServerEvent:Fire(player, ...)
	step(0.1)
end

-- ---------- Anbieten ----------
InventoryService.Give(alice, "Rifle", 1, { Mag = 25 })
InventoryService.Give(alice, "Ammo_Rifle", 60)
InventoryService.Give(alice, "V_Quad", 1)
local rifleSlot = slotOf(alice, "Rifle")
place(alice, Vector3.new(0, 3, 20))
action(alice, "MarketList", rifleSlot, 1, 500)
check(#market() == 0 and string.find(lastStatus(alice), "Spielermarkt", 1, true) ~= nil, "nur am Marktstand")
atMarket(alice)
for _, bad in { 0, -5, M.MaxPrice + 1, 0 / 0, math.huge } do
	action(alice, "MarketList", rifleSlot, 1, bad)
end
check(#market() == 0 and slotOf(alice, "Rifle") == rifleSlot, "unsinnige Preise abgelehnt, Gewehr bleibt")
action(alice, "MarketList", rifleSlot, 1, 500)
local list = market()
check(#list == 1 and list[1].Item == "Rifle" and list[1].Price == 500 and list[1].Mag == 25 and list[1].SellerName == "Alice"
	and list[1].Seller == alice.UserId, "Gewehr mit Magazin 25 für 500 angeboten")
check(slotOf(alice, "Rifle") == nil, "Gewehr ist aus der Tasche")
local profileMarket = ProgressService.Get(alice).Extinction.Market
check(profileMarket and #profileMarket == 1 and profileMarket[1].Item == "Rifle", "Angebot steht im Spielstand")
-- Teil eines Stapels
action(alice, "MarketList", slotOf(alice, "Ammo_Rifle"), 20, 50)
local _, ammo = slotOf(alice, "Ammo_Rifle")
check(ammo and ammo.Count == 40, "20 von 60 Schuss angeboten, 40 bleiben (" .. (ammo and ammo.Count or 0) .. ")")
-- Fahrzeug, das draußen steht: nicht
local quadSlot, quad = slotOf(alice, "V_Quad")
quad.Out = true
action(alice, "MarketList", quadSlot, 1, 900)
check(slotOf(alice, "V_Quad") == quadSlot and string.find(lastStatus(alice), "Fahrzeug erst ein", 1, true) ~= nil,
	"draußen stehendes Fahrzeug nicht")
quad.Out = nil
action(alice, "MarketList", quadSlot, 1, 900)
check(slotOf(alice, "V_Quad") == nil and #market() == 3, "eingepacktes Fahrzeug angeboten (3 Angebote)")
-- höchstens MaxListings
InventoryService.Give(alice, "Bandage", 10)
for _ = 1, M.MaxListings do
	local slot = slotOf(alice, "Bandage")
	if slot then
		action(alice, "MarketList", slot, 1, 10)
	end
end
check(#InventoryService.MarketOf(alice) == M.MaxListings, "höchstens " .. M.MaxListings .. " Angebote ("
	.. #InventoryService.MarketOf(alice) .. ")")
check(string.find(lastStatus(alice), "schon " .. M.MaxListings, 1, true) ~= nil, "Meldung: alle Angebote belegt")

-- ---------- Kaufen ----------
local rifle = nil
for _, offer in market() do
	if offer.Item == "Rifle" then
		rifle = offer
	end
end
place(bob, Vector3.new(0, 3, 20))
action(bob, "MarketBuy", rifle.Id, 500)
check(ProgressService.Get(bob).Coins == 1000 and string.find(lastStatus(bob), "Spielermarkt", 1, true) ~= nil, "Kaufen nur am Stand")
atMarket(bob)
action(bob, "MarketBuy", rifle.Id, 400)
check(ProgressService.Get(bob).Coins == 1000 and string.find(lastStatus(bob), "Preis", 1, true) ~= nil, "nur zum gesehenen Preis")
action(alice, "MarketBuy", rifle.Id, 500)
check(string.find(lastStatus(alice), "eigenes", 1, true) ~= nil, "eigenes Angebot nicht kaufen")
-- VIP verdoppelt Markt-Erlöse nicht (sonst könnte man Münzen zwischen Konten verdoppeln)
alice:SetAttribute("Pass_VIP", true)
local aliceBefore = ProgressService.Get(alice).Coins
action(bob, "MarketBuy", rifle.Id, 500)
local fee = math.floor(500 * M.FeeRate)
check(ProgressService.Get(bob).Coins == 500, "Bob hat 500 bezahlt (" .. ProgressService.Get(bob).Coins .. ")")
check(ProgressService.Get(alice).Coins == aliceBefore + 500 - fee, "Alice bekommt 500 minus " .. fee .. " Gebühr, ohne VIP-Verdopplung ("
	.. ProgressService.Get(alice).Coins - aliceBefore .. ")")
local _, bought = slotOf(bob, "Rifle")
check(bought and bought.Mag == 25, "Gewehr mit Magazin in Bobs Tasche")
check(#market() == M.MaxListings - 1, "Angebot weg")
check(string.find(lastStatus(alice), "Verkauft", 1, true) ~= nil and string.find(lastStatus(bob), "Gekauft", 1, true) ~= nil,
	"Meldungen an beide")
step(1)
check(store.Data.u2 and store.Data.u2.Coins == 500, "Bobs Kauf ist gespeichert")
-- zu wenig Münzen: nichts passiert
local quadOffer = nil
for _, offer in market() do
	if offer.Item == "V_Quad" then
		quadOffer = offer
	end
end
action(bob, "MarketBuy", quadOffer.Id, 900)
check(ProgressService.Get(bob).Coins == 500 and slotOf(bob, "V_Quad") == nil and #market() == M.MaxListings - 1,
	"zu wenig Münzen: nichts gekauft")
-- Tasche voll: nichts passiert
local bag = InventoryService.GetBag(bob)
for slot = 1, bag.Size do
	if not bag.Slots[slot] then
		bag.Slots[slot] = { Id = "Pistol", Count = 1 }
	end
end
ProgressService.AddCoins(bob, 2000, "Admin")
local bandageOffer = nil
for _, offer in market() do
	if offer.Item == "Bandage" then
		bandageOffer = offer
	end
end
action(bob, "MarketBuy", bandageOffer.Id, bandageOffer.Price)
check(string.find(lastStatus(bob), "Platz", 1, true) ~= nil and #market() == M.MaxListings - 1, "volle Tasche: nichts gekauft")

-- ---------- Zurücknehmen ----------
action(alice, "MarketCancel", quadOffer.Id)
check(slotOf(alice, "V_Quad") ~= nil and #market() == M.MaxListings - 2, "Quad zurückgenommen")

-- ---------- Tod: Angebote bleiben ----------
place(alice, Vector3.new(0, 3, 300))
step(0.3)
alice.Character.Humanoid.Health = 0
step(ExtinctionConfig.RespawnTime + 0.5)
check(#InventoryService.MarketOf(alice) == M.MaxListings - 2, "Tod draußen: Angebote bleiben")

-- ---------- Verlassen und Wiederkommen ----------
SIM.Leave(alice)
step(4)
check(#market() == 0, "Alice weg: ihre Angebote sind nicht mehr zu sehen")
check(store.Data.u1 and #store.Data.u1.Extinction.Market == M.MaxListings - 2, "Angebote im gespeicherten Spielstand")
local alice2 = SIM.Join("Alice", alice.UserId)
Instance.new("Backpack", alice2).Name = "Backpack"
step(2)
alice2:SetAttribute("Mode", "Extinction")
Extinction.AddPlayer(alice2)
step(4)
check(#market() == M.MaxListings - 2, "wieder da: Angebote wieder zu sehen (" .. #market() .. ")")

if failures > 0 then
	error(failures .. " Fehler")
end
print("extmarket: alles ok")

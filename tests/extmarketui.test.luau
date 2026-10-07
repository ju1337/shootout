-- Spielermarkt im Client (ExtinctionClient + ExtMarketPage) zusammen mit dem Server: E am Marktstand öffnet das Menü auf
-- MARKT, Item der Tasche anklicken füllt Anzahl und Preis vor, ANBIETEN schickt das Angebot, unter MEINE ANGEBOTE Preis
-- ändern und zurücknehmen, fremde Angebote mit KAUFEN, Kategorien. In der ganzen Safe Zone offen, draußen gesperrt.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local Remotes = require("Remotes")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
local ExtinctionConfig = require("ExtinctionConfig")
local InputActions = require("InputActions")
ProgressService.Init()
WeaponService.Init()

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Places" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
for name, offset in { Stand_Weapons = Vector3.new(-36, 2.5, 34), Stand_Items = Vector3.new(36, 2.5, 34),
	Stand_Vehicles = Vector3.new(-30, 2.5, -42), Stash = Vector3.new(52, 2.5, -30), Stand_Market = Vector3.new(64, 2.5, -37) } do
	local part = Instance.new("Part", map.Stands)
	part.Name = name
	part.CFrame = CFrame.new(CENTER + offset)
end

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0
ExtinctionConfig.Redzone.Enabled = false
Extinction.Init({ Join = function() end, Status = function() end })

store.Data.u1 = { XP = {}, Coins = 4000, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local bob = SIM.Join("Bob")
local ann = SIM.Join("Ann")
for _, player in { bob, ann } do
	Instance.new("Backpack", player).Name = "Backpack"
end
SIM.Advance(2, 20)
for _, player in { bob, ann } do
	player:SetAttribute("Mode", "Extinction")
	Extinction.AddPlayer(player)
end
SIM.Advance(0.5, 20)

-- Client von Bob starten; Fernaufrufe in beide Richtungen weiterreichen
rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
local ExtinctionClient = require("ExtinctionClient")
ExtinctionClient.Init()
local seen = #SIM.RemoteLog
local function pump()
	while seen < #SIM.RemoteLog do
		seen += 1
		local entry = SIM.RemoteLog[seen]
		if entry.Player == "server" and entry.Remote == "ExtAction" then
			Remotes.ExtAction.OnServerEvent:Fire(bob, table.unpack(entry.Args, 1, entry.Args.n))
		elseif entry.Player == bob and entry.Remote == "ExtUpdate" then
			Remotes.ExtUpdate.OnClientEvent:Fire(table.unpack(entry.Args, 1, entry.Args.n))
		end
	end
end
local function step(seconds)
	local target = SIM.Now + (seconds or 0.5)
	while SIM.Now < target - 1e-6 do
		SIM.Advance(math.min(0.1, target - SIM.Now), 20)
		pump()
	end
end
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
local function texts(root)
	local list = {}
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			table.insert(list, d.Text)
		end
	end
	return table.concat(list, " | ")
end
step(1)
local windowGui = playerGui:FindFirstChild("ExtinctionWindow")

local function textOf(object)
	if not object then
		return ""
	end
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		return object.Text .. " " .. texts(object)
	end
	return texts(object)
end
local function cards()
	return findAll(find(windowGui, "Results"), "Card")
end

-- ---------- Menü auf MARKT öffnen (E am Stand) ----------
InventoryService.Give(bob, "Rifle", 1, { Mag = 20 })
InventoryService.Give(bob, "Ammo_Rifle", 60)
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(60, 3, -34)))
step(0.5)
local prompt = map.Stands.Stand_Market:FindFirstChild("MarketPrompt")
check(prompt ~= nil and prompt.ObjectText == "SPIELERMARKT", "Marktstand hat eine E-Aufforderung")
prompt.Triggered:Fire(bob)
step(0.3)
check(windowGui.Enabled and find(windowGui, "MarketPage") ~= nil, "Menü auf dem Reiter MARKT")
check(bob:GetAttribute("InSafeZone") == true and not find(windowGui, "Lock").Visible, "in der Safe Zone: keine Sperre")
check(string.find(texts(find(windowGui, "Empty")), "NOCH KEINE ANGEBOTE", 1, true) ~= nil, "leerer Markt: Hinweis")

-- ---------- Anbieten: Gewehr anklicken, Preis eintragen ----------
local sell = find(windowGui, "Sell")
find(windowGui, "Bag1").Activated:Fire()
step(0.2)
local priceBox = find(sell, "PriceBox")
check(priceBox.Text == tostring(ExtinctionConfig.Get("Rifle").Price), "Preis vorgeschlagen (" .. priceBox.Text .. ")")
check(not find(sell, "CountUp").Visible, "Waffe: keine Anzahl")
priceBox.Text = "777"
priceBox.FocusLost:Fire(true)
step(0.1)
check(string.find(find(sell, "Earn").Text, tostring(777 - math.floor(777 * ExtinctionConfig.Market.FeeRate)), 1, true) ~= nil,
	"Erlös nach Gebühr: " .. find(sell, "Earn").Text)
find(sell, "Offer").Activated:Fire()
step(4) -- Angebot an den Server, Karten-Attribut zurück
check(#cards() == 1 and string.find(textOf(cards()[1]), "STURMGEWEHR", 1, true) ~= nil, "eigenes Angebot als Karte")
check(find(cards()[1], "Buy") == nil, "eigenes Angebot: kein KAUFEN")
check(InventoryService.GetBag(bob).Slots[1] == nil, "Gewehr ist aus Bobs Tasche")
-- Munition: ganzer Stapel
local ammoSlot = nil
for slot = 1, ExtinctionConfig.BagSlots do
	local item = InventoryService.GetBag(bob).Slots[slot]
	if item and item.Id == "Ammo_Rifle" then
		ammoSlot = slot
	end
end
find(windowGui, "Bag" .. ammoSlot).Activated:Fire()
step(0.2)
check(string.find(find(sell, "CountValue").Text, "60", 1, true) == 1, "Stapel: Anzahl 60 vorgeschlagen")
find(sell, "PriceBox").Text = "45"
find(sell, "PriceBox").FocusLost:Fire(true)
find(sell, "Offer").Activated:Fire()
step(4)
check(InventoryService.GetBag(bob).Slots[ammoSlot] == nil, "Munition angeboten")
check(#cards() == 2, "zwei eigene Angebote")

-- ---------- MEINE ANGEBOTE: Preis ändern ----------
find(windowGui, "TabMine").Activated:Fire()
step(0.2)
local mine = find(windowGui, "Mine")
check(mine.Visible and #findAll(mine, "MyOffer") == 2, "MEINE ANGEBOTE: zwei")
local row = nil
for _, candidate in findAll(mine, "MyOffer") do
	if string.find(texts(candidate), "STURMGEWEHR", 1, true) then
		row = candidate
	end
end
find(row, "PriceBox").Text = "700"
find(row, "PriceBox").FocusLost:Fire(true)
find(row, "PriceSave").Activated:Fire()
step(4)
local repriced = false
for _, entry in InventoryService.MarketOf(bob) do
	if entry.Item == "Rifle" and entry.Price == 700 then
		repriced = true
	end
end
check(repriced, "Preis geändert auf 700")
find(windowGui, "TabOffers").Activated:Fire()
step(0.2)

-- ---------- fremdes Angebot kaufen, Kategorien ----------
InventoryService.Give(ann, "Medkit", 1)
ann.Character:PivotTo(CFrame.new(CENTER + Vector3.new(60, 3, -38)))
SIM.Advance(0.3, 20)
local annSlot = nil
for slot = 1, ExtinctionConfig.BagSlots do
	local item = InventoryService.GetBag(ann).Slots[slot]
	if item and item.Id == "Medkit" then
		annSlot = slot
	end
end
Remotes.ExtAction.OnServerEvent:Fire(ann, "MarketList", annSlot, 1, 150)
step(4)
find(windowGui, "Category_Weapon").Activated:Fire()
step(0.2)
check(#cards() == 1 and string.find(textOf(cards()[1]), "STURMGEWEHR", 1, true) ~= nil, "Kategorie WAFFEN")
find(windowGui, "Category_Gear").Activated:Fire()
step(0.2)
check(#cards() == 1 and string.find(textOf(cards()[1]), "MEDIKIT", 1, true) ~= nil and find(cards()[1], "Buy") ~= nil,
	"Kategorie AUSRÜSTUNG: Anns Medikit mit KAUFEN")
find(cards()[1], "Buy").Activated:Fire()
step(4)
local hasMedkit = false
for _, item in InventoryService.GetBag(bob).Slots do
	if item.Id == "Medkit" then
		hasMedkit = true
	end
end
check(hasMedkit and ProgressService.Get(bob).Coins == 4000 - 150, "Bob hat das Medikit gekauft")
check(ProgressService.Get(ann).Coins == 150 - math.floor(150 * ExtinctionConfig.Market.FeeRate), "Ann bekommt den Erlös")
find(windowGui, "Category_All").Activated:Fire()
step(0.2)
check(#cards() == 2, "alle: Bobs zwei Angebote übrig")

-- ---------- zurücknehmen ----------
find(windowGui, "TabMine").Activated:Fire()
step(0.2)
find(find(windowGui, "Mine"), "Cancel").Activated:Fire()
step(4)
check(#InventoryService.MarketOf(bob) == 1, "ein Angebot zurückgenommen")

-- ---------- Weggehen: in der Safe Zone offen, draußen gesperrt ----------
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 0)))
step(0.5)
check(windowGui.Enabled and not find(windowGui, "Lock").Visible, "Weggehen vom Stand (in der Safe Zone): Markt bleibt offen")
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(400, 3, 0)))
step(1)
check(bob:GetAttribute("InSafeZone") ~= true, "Bob ist draußen")
check(windowGui.Enabled and find(windowGui, "Lock").Visible, "draußen: MARKT gesperrt")
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 0)))
step(1)
check(not find(windowGui, "Lock").Visible, "zurück in der Safe Zone: Sperre weg")

if failures > 0 then
	error(failures .. " Fehler")
end
print("extmarketui: alles ok")

-- Angebot des Tages (ShopOffers): aus dem Datum berechnet (auf allen Servern gleich), nur echte Shop-Skins ohne
-- Test-Skins, Rabatt aus der Liste, nie zwei Tage hintereinander derselbe Skin, der Server verlangt den Angebotspreis
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Run(SIM.Now + (seconds or 1))
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local Cosmetics = require("Cosmetics")
local ShopOffers = require("ShopOffers")
local Remotes = require("Remotes")
local ProgressService = require("ProgressService")
local ShopService = require("ShopService")
ProgressService.Init()
ShopService.Init()

local DAY = ShopOffers.DayLength
local pool = ShopOffers.Pool()
check(#pool >= 5, "genug Skins fürs Angebot")
for _, item in pool do
	check(Cosmetics.ForSale(item) and not item.Test and item.Price >= ShopOffers.MinPrice, item.Id .. ": darf ins Angebot")
end

local seen, previous = {}, nil
for day = 20000, 20060 do
	local a, b = ShopOffers.Daily(day * DAY + 5), ShopOffers.Daily(day * DAY + DAY - 1)
	check(a.Item == b.Item and a.Price == b.Price, "den ganzen Tag dasselbe Angebot (Tag " .. day .. ")")
	check(a.EndsAt == (day + 1) * DAY, "endet um Mitternacht UTC")
	check(table.find(ShopOffers.Discounts, a.Discount) ~= nil, "Rabatt aus der Liste")
	check(a.Price < a.OldPrice and a.Price > 0 and a.Price % 10 == 0, "Angebotspreis glatt und günstiger: " .. a.Price)
	check(a.Item ~= previous, "nicht zweimal hintereinander " .. a.Item.Id)
	previous = a.Item
	seen[a.Item.Id] = true
	local price, offer = ShopOffers.PriceFor(a.Item, day * DAY + 100)
	check(price == a.Price and offer ~= nil, "PriceFor nennt den Angebotspreis")
end
local distinct = 0
for _ in seen do
	distinct += 1
end
check(distinct >= 5, "über zwei Monate wechseln die Skins (" .. distinct .. ")")
check(ShopOffers.FormatLeft(3 * 3600 + 5 * 60 + 9) == "03:05:09", "Restzeit HH:MM:SS")

-- Kauf: Server zieht den Angebotspreis ab, andere Skins kosten den normalen Preis
store.Data.u1 = { XP = {}, Coins = 10000, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
step(2)
local function lastStatus(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "ShopStatus" and entry.Player == player then
			return entry.Args[1], entry.Args[2]
		end
	end
	return nil
end
local offer = ShopOffers.Daily(workspace:GetServerTimeNow())
Remotes.ShopAction.OnServerEvent:Fire(alice, "Buy", offer.Item.Id)
step(0.2)
local message, ok = lastStatus(alice)
check(ok == true and alice:GetAttribute("Coins") == 10000 - offer.Price,
	"Angebot kostet den reduzierten Preis: " .. tostring(message) .. " / " .. tostring(alice:GetAttribute("Coins")))
local other
for _, item in pool do
	if item ~= offer.Item then
		other = item
		break
	end
end
local before = alice:GetAttribute("Coins")
Remotes.ShopAction.OnServerEvent:Fire(alice, "Buy", other.Id)
step(0.2)
check(alice:GetAttribute("Coins") == before - other.Price, "anderer Skin kostet den normalen Preis")

-- Angebote aus dem Admin-Panel (ShopOfferService): gespeichert, an alle verteilt, Server verlangt den Preis
local ShopOfferService = require("ShopOfferService")
ShopOfferService.Init()
step(1)
local chrom = Cosmetics.Get("W_Chrom")
check(string.find(ShopOfferService.Add(alice, "W_Chrom", { Discount = 95, Hours = 5 }), "Rabatt", 1, true) ~= nil,
	"zu hoher Rabatt wird abgelehnt")
check(string.find(ShopOfferService.Add(alice, "W_Chrom", { Discount = 50, Hours = 0 }), "Dauer", 1, true) ~= nil,
	"Dauer 0 wird abgelehnt")
check(string.find(ShopOfferService.Add(alice, "AS_Creator", { Discount = 50, Hours = 5 }), "nicht im Shop", 1, true) ~= nil,
	"Creator-Skin geht nicht ins Angebot")
local msg = ShopOfferService.Add(alice, "W_Chrom", { Discount = 50, Hours = 2, Featured = true })
check(string.find(msg, "gestartet", 1, true) ~= nil, "Angebot starten: " .. msg)
local t = workspace:GetServerTimeNow()
local featured = ShopOffers.Featured(t)
check(featured and featured.Item == chrom and featured.Manual and featured.Price == 700 and featured.Discount == 50,
	"Hauptangebot steht vorne mit 50 %")
check(game:GetService("ReplicatedStorage"):GetAttribute(ShopOffers.Attribute) ~= nil, "Stand liegt im Attribut für die Clients")
local stored = SIM.DataStore("ShopOffers_v1").Data.Config
check(type(stored) == "table" and #stored.Offers == 1, "Angebot ist gespeichert")
check(ShopOffers.PriceFor(chrom, t) == 700, "PriceFor nimmt das Admin-Angebot")
check(ShopOffers.PriceFor(chrom, t + 3 * 3600) == chrom.Price, "nach Ablauf wieder normaler Preis")
before = alice:GetAttribute("Coins")
Remotes.ShopAction.OnServerEvent:Fire(alice, "Buy", "W_Chrom")
step(0.2)
check(alice:GetAttribute("Coins") == before - 700, "Kauf kostet den Admin-Angebotspreis")
ShopOfferService.Add(alice, "W_Lava", { Discount = 20, Hours = 1 })
check(#ShopOffers.Config().Offers == 2, "zwei Angebote gleichzeitig")
check(string.find(ShopOfferService.Remove(alice, "W_Lava"), "beendet", 1, true) ~= nil, "Angebot beenden")
check(#ShopOffers.Config().Offers == 1, "beendetes Angebot ist weg")
ShopOfferService.SetAuto(alice, false)
local onlyManual = true
for _, offer in ShopOffers.Active(workspace:GetServerTimeNow()) do
	onlyManual = onlyManual and offer.Manual == true
end
check(onlyManual and not ShopOffers.Config().AutoDaily, "Angebot des Tages abschaltbar")
ShopOfferService.SetAuto(alice, true)
check(ShopOffers.Config().AutoDaily, "Angebot des Tages wieder an")
check(ShopOffers.FormatLeft(26 * 3600 + 5) == "1 T 02:00:05", "Restzeit über einen Tag")

if failures > 0 then
	error(failures .. " Fehler")
end
print("shopoffers: alles ok")

-- EconomyService (ModuleScript, nur Server)
-- RAP-Wirtschaft (RapConfig):
--   * Rückverkauf ans System (SHOP, Reiter VERKAUFEN): Skin weg, sofort SellRate × RAP-Wert aufs Guthaben
--   * Reservierungen: Skins, die gerade an einem Markt-Stand liegen oder in einem Tausch angeboten sind, bleiben im
--     Inventar, lassen sich aber nicht gleichzeitig verkaufen oder woanders anbieten. Sie leben nur im Speicher
--     des Servers – verlässt ein Spieler den Markt, das Spiel oder stürzt der Server ab, ist nichts verloren, die
--     Skins waren nie weg. Spieler-Attribut Reserved (JSON { [Id] = Stück }) für die Anzeige.
--   * Austausch zwischen zwei Spielern (Markt-Kauf, Tausch): erst alles prüfen (Besitz, Reservierung, Guthaben),
--     dann auf einmal ausführen und beide Spielstände sofort speichern.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)
local RapConfig = require(Shared.RapConfig)
local ProgressService = require(script.Parent.ProgressService)

local EconomyService = {}

local reserved = {} -- [Player] = { [Key] = { [Id] = Stück } }

-- Zahl mit Tausenderpunkten ("12.450")
function EconomyService.Format(n)
	local s = tostring(math.floor(n or 0))
	local formatted = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1.")))
	return (string.gsub(formatted, "^%.", ""))
end
local format = EconomyService.Format

local function publish(player)
	local total = {}
	for _, items in reserved[player] or {} do
		for id, n in items do
			total[id] = (total[id] or 0) + n
		end
	end
	if player.Parent then
		player:SetAttribute("Reserved", HttpService:JSONEncode(total))
	end
end

-- Zurückgelegte Stücke eines Skins (für key oder insgesamt)
function EconomyService.ReservedCount(player, id, key)
	local holders = reserved[player]
	if not holders then
		return 0
	end
	if key then
		return holders[key] and holders[key][id] or 0
	end
	local n = 0
	for _, items in holders do
		n += items[id] or 0
	end
	return n
end

-- Freie Stücke: besessen minus zurückgelegt
function EconomyService.Available(player, id)
	return ProgressService.ItemCount(player, id) - EconomyService.ReservedCount(player, id)
end

-- n Stück für key zurücklegen ("Stand", "Trade"). Nur handelbare Skins und nur freie Stücke.
function EconomyService.Reserve(player, id, n, key)
	n = math.floor(tonumber(n) or 0)
	if n < 1 or not RapConfig.Tradeable(id) or EconomyService.Available(player, id) < n then
		return false
	end
	reserved[player] = reserved[player] or {}
	reserved[player][key] = reserved[player][key] or {}
	reserved[player][key][id] = (reserved[player][key][id] or 0) + n
	publish(player)
	return true
end

-- n Stück wieder freigeben
function EconomyService.Unreserve(player, id, n, key)
	local holders = reserved[player]
	local items = holders and holders[key]
	if not items or not items[id] then
		return
	end
	items[id] -= n
	if items[id] <= 0 then
		items[id] = nil
	end
	if next(items) == nil then
		holders[key] = nil
	end
	publish(player)
end

-- Alles, was für key zurückgelegt ist, freigeben (Stand geräumt, Tausch abgebrochen)
function EconomyService.ClearKey(player, key)
	if reserved[player] and reserved[player][key] then
		reserved[player][key] = nil
		publish(player)
	end
end

-- Skin ans System verkaufen: n Stück (Standard 1), nur freie. Gibt Meldung und Erfolg zurück.
function EconomyService.SellToSystem(player, id, n)
	local item = typeof(id) == "string" and Cosmetics.Get(id)
	n = math.floor(tonumber(n) or 1)
	if not item or not RapConfig.Tradeable(id) then
		return "Diesen Skin kauft das System nicht an.", false
	end
	if n < 1 then
		return "Ungültige Anzahl.", false
	end
	if not ProgressService.IsLoaded(player) then
		return "Daten werden noch geladen.", false
	end
	if EconomyService.Available(player, id) < n then
		if EconomyService.ReservedCount(player, id) > 0 then
			return item.Name .. " liegt gerade an deinem Stand oder in einem Tausch.", false
		end
		return "Du hast " .. item.Name .. " nicht.", false
	end
	local rap = RapConfig.SellPrice(id) * n
	ProgressService.TakeItem(player, id, n)
	ProgressService.AddRap(player, rap)
	task.spawn(ProgressService.SaveNow, player)
	return item.Name .. (n > 1 and (" ×" .. n) or "") .. " verkauft: +" .. format(rap) .. " RAP", true
end

-- Austausch: offerA geht von a an b, offerB von b an a. offer = { Items = { [Id] = Stück }, Rap = Betrag }.
-- Die Skins müssen unter key für ihren Besitzer zurückgelegt sein, das RAP muss reichen. feeRate (0..1): Anteil von
-- offerB.Rap, der unterwegs verloren geht (Marktgebühr, a ist der Verkäufer). Alles oder nichts; danach werden
-- beide Spielstände sofort gespeichert. Gibt true bzw. false und den Grund zurück.
function EconomyService.Exchange(a, b, offerA, offerB, key, feeRate)
	if a == b then
		return false, "Mit dir selbst geht das nicht."
	end
	for _, side in { { a, offerA }, { b, offerB } } do
		local player, offer = side[1], side[2]
		if not player.Parent or not ProgressService.IsLoaded(player) then
			return false, "Die Daten von " .. player.Name .. " sind nicht bereit."
		end
		for id, n in offer.Items or {} do
			if type(n) ~= "number" or n < 1 or EconomyService.ReservedCount(player, id, key) < n
				or ProgressService.ItemCount(player, id) < n then
				return false, player.Name .. " hat den Skin nicht mehr."
			end
		end
		local rap = offer.Rap or 0
		if type(rap) ~= "number" or rap < 0 or ProgressService.GetRap(player) < rap then
			return false, player.Name .. " hat nicht genug RAP."
		end
	end
	-- geprüft: jetzt ausführen
	for _, side in { { a, b, offerA }, { b, a, offerB } } do
		local from, to, offer = side[1], side[2], side[3]
		for id, n in offer.Items or {} do
			EconomyService.Unreserve(from, id, n, key)
			ProgressService.TakeItem(from, id, n)
			ProgressService.GiveItem(to, id, n)
		end
	end
	local rapA, rapB = math.floor(offerA.Rap or 0), math.floor(offerB.Rap or 0)
	if rapA > 0 then
		ProgressService.SpendRap(a, rapA)
		ProgressService.AddRap(b, rapA)
	end
	if rapB > 0 then
		ProgressService.SpendRap(b, rapB)
		ProgressService.AddRap(a, rapB - math.floor(rapB * (feeRate or 0) + 0.5)) -- wie RapConfig.Fee
	end
	task.spawn(ProgressService.SaveNow, a)
	task.spawn(ProgressService.SaveNow, b)
	return true
end

function EconomyService.Init()
	Players.PlayerRemoving:Connect(function(player)
		reserved[player] = nil
	end)
end

return EconomyService

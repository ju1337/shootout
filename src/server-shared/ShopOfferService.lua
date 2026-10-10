-- ShopOfferService (ModuleScript, nur Server)
-- Angebote im SHOP aus dem Admin-Panel (Reiter SHOP): Skin, Rabatt, Dauer, Hauptangebot, und ob das automatische
-- Angebot des Tages läuft. Rechnen und Anzeigen übernimmt ShopOffers (shared).
--   * Gespeichert im DataStore "ShopOffers_v1" unter "Config": { Offers = { { Id, Discount, Starts, Ends, Featured,
--     By } }, AutoDaily = true }. Jeder Server lädt beim Start und alle RefreshEvery Sekunden neu; Änderungen gehen
--     sofort per MessagingService ("ShopOffers") an alle Server.
--   * Für die Clients liegt der Stand als JSON im Attribut ShopOffers.Attribute an ReplicatedStorage.
--   * Abgelaufene Angebote fliegen beim nächsten Speichern raus.
-- Aktionen (AdminService, nur volle Admins): ShopOfferAdd(itemId, { Discount, Hours, Featured }), ShopOfferRemove(itemId),
-- ShopOfferAuto(an/aus).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)
local ShopOffers = require(Shared.ShopOffers)

local ShopOfferService = {}

ShopOfferService.StoreName = "ShopOffers_v1"
ShopOfferService.Key = "Config"
ShopOfferService.Topic = "ShopOffers"
ShopOfferService.RefreshEvery = 60

local config = { Offers = {}, AutoDaily = true }
local store = nil

local function now()
	return workspace:GetServerTimeNow()
end

local function dataStore()
	if store == nil then
		local ok, s = pcall(DataStoreService.GetDataStore, DataStoreService, ShopOfferService.StoreName)
		store = ok and s or false
	end
	return store or nil
end

-- Nur gültige, nicht abgelaufene Einträge behalten
local function clean(data)
	data = ShopOffers.Config(type(data) == "table" and data or {})
	local offers = {}
	for _, entry in data.Offers do
		if type(entry) == "table" and Cosmetics.Get(entry.Id) and (tonumber(entry.Ends) or 0) > now() then
			table.insert(offers, entry)
		end
	end
	return { Offers = offers, AutoDaily = data.AutoDaily }
end

local function apply(data)
	config = clean(data)
	ReplicatedStorage:SetAttribute(ShopOffers.Attribute, HttpService:JSONEncode(config))
end

-- Stand im DataStore ändern: transform(config) -> config; danach überall anwenden
local function update(transform)
	local s = dataStore()
	local result = nil
	if s then
		local ok, err = pcall(function()
			s:UpdateAsync(ShopOfferService.Key, function(old)
				result = clean(transform(clean(old)))
				return result
			end)
		end)
		if not ok then
			-- nicht trotzdem anwenden: sonst sehen alle das Angebot, bis es beim nächsten Laden still verschwindet
			warn("ShopOfferService: Speichern fehlgeschlagen: " .. tostring(err))
			return nil
		end
	end
	result = result or clean(transform(clean(config))) -- ohne DataStore (Studio): nur hier
	apply(result)
	-- nur ein Anstoß zum Neuladen (der ganze Stand kann über die 1-kB-Grenze von MessagingService gehen)
	pcall(MessagingService.PublishAsync, MessagingService, ShopOfferService.Topic, { Reload = true, Server = game.JobId })
	return result
end

local SAVE_FAILED = "Speichern fehlgeschlagen, bitte gleich noch einmal versuchen."

local function load()
	local s = dataStore()
	if not s then
		return
	end
	local ok, result = pcall(s.GetAsync, s, ShopOfferService.Key)
	if ok then
		apply(result)
	else
		warn("ShopOfferService: Laden fehlgeschlagen: " .. tostring(result))
	end
end

function ShopOfferService.Get()
	return config
end

-- Angebot starten (ersetzt ein laufendes Angebot für denselben Skin). Gibt die Meldung fürs Panel zurück.
function ShopOfferService.Add(admin, itemId, options)
	local item = typeof(itemId) == "string" and Cosmetics.Get(itemId)
	if not item or not ShopOffers.Allowed(item) then
		return "Diesen Skin gibt es nicht im Shop."
	end
	options = type(options) == "table" and options or {}
	local discount = math.floor(tonumber(options.Discount) or 0)
	local hours = tonumber(options.Hours) or 0
	if discount < ShopOffers.MinDiscount or discount > ShopOffers.MaxDiscount then
		return "Rabatt muss zwischen " .. ShopOffers.MinDiscount .. " und " .. ShopOffers.MaxDiscount .. " % liegen."
	end
	if hours <= 0 or hours > ShopOffers.MaxHours then
		return "Dauer muss zwischen 1 Stunde und " .. (ShopOffers.MaxHours // 24) .. " Tagen liegen."
	end
	local full = false
	local start = math.floor(now())
	local saved = update(function(data)
		local offers = {}
		for _, entry in data.Offers do
			if entry.Id ~= item.Id then
				table.insert(offers, entry)
			end
		end
		if #offers >= ShopOffers.MaxOffers then
			full = true
			return data
		end
		table.insert(offers, { Id = item.Id, Discount = discount, Starts = start, Ends = start + math.floor(hours * 3600),
			Featured = options.Featured == true, By = admin and admin.Name or "?" })
		data.Offers = offers
		return data
	end)
	if not saved then
		return SAVE_FAILED
	end
	if full then
		return "Schon " .. ShopOffers.MaxOffers .. " Angebote aktiv. Erst eins entfernen."
	end
	return "Angebot gestartet: " .. item.Name .. " -" .. discount .. " % für " .. hours .. " Std."
end

function ShopOfferService.Remove(_, itemId)
	local item = typeof(itemId) == "string" and Cosmetics.Get(itemId)
	if not item then
		return "Unbekannter Skin."
	end
	local found = false
	local saved = update(function(data)
		local offers = {}
		for _, entry in data.Offers do
			if entry.Id == item.Id then
				found = true
			else
				table.insert(offers, entry)
			end
		end
		data.Offers = offers
		return data
	end)
	if not saved then
		return SAVE_FAILED
	end
	return found and ("Angebot beendet: " .. item.Name) or "Für diesen Skin läuft kein Angebot."
end

function ShopOfferService.SetAuto(_, on)
	local value = on == true
	local saved = update(function(data)
		data.AutoDaily = value
		return data
	end)
	if not saved then
		return SAVE_FAILED
	end
	return value and "Angebot des Tages läuft wieder." or "Angebot des Tages ist aus."
end

function ShopOfferService.Init()
	apply(config)
	task.spawn(load)
	task.spawn(pcall, MessagingService.SubscribeAsync, MessagingService, ShopOfferService.Topic, function(message)
		local data = type(message) == "table" and message.Data or nil
		if type(data) == "table" and data.Server ~= game.JobId then
			if type(data.Config) == "table" then
				apply(data.Config) -- (ältere Server schicken noch den ganzen Stand)
			elseif data.Reload then
				task.spawn(load)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(ShopOfferService.RefreshEvery)
			load()
		end
	end)
end

return ShopOfferService

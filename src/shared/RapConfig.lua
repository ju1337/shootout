-- RapConfig (ModuleScript)
-- RAP ist die zweite Währung (wie in Sniper Duels / Sniper Arena): Man bekommt sie nur über Skins. Jeder handelbare Skin –
-- Waffe oder Agent – hat einen RAP-Wert. Er startet bei einem Basiswert (Values) und wandert wie ein "Recent Average
-- Price": nach jedem Verkauf im Markt rückt er ein Zehntel (LiveWeight) Richtung Verkaufspreis, begrenzt auf
-- LiveMin bis LiveMax mal Basiswert (Live, vom Server an alle Clients). Die Werte sind steil gestaffelt wie bei Sniper
-- Duels: gewöhnliche Skins 1 bis 10 RAP, seltene zweistellig, epische dreistellig, legendäre vier- bis fünfstellig,
-- Battle-Pass- und Robux-Skins ab 35.000. Der Rückkauf ans System zahlt immer vom Basiswert (nicht manipulierbar).
-- Wer so einen Skin hat, kann ihn
--   * im SHOP ans System zurückverkaufen (Reiter VERKAUFEN, sofort SellRate × RAP-Wert),
--   * im MARKT an einem eigenen Stand zum selbst gewählten Preis anbieten (Käufer zahlen in RAP, MarketFee geht ab),
--   * mit anderen Spielern tauschen (Skins und RAP).
-- Mit dem RAP kauft man im Markt Skins von anderen Spielern. Handelbare Skins kann man mehrfach besitzen
-- (Duplikate aus Glücksrad, Login-Kalender, Wochen-Bonus, Robux-Paket oder Käufen von anderen Spielern).
-- Gebunden – ohne RAP-Wert, nicht verkauf- oder tauschbar – sind gewöhnliche Skins, Belohnungen für Level,
-- Prestige, Rang und Saison sowie die Meisterschafts-Tarnungen. Neuen Skin handelbar machen: Wert hier eintragen.
-- Spieler-Attribute: Rap (Guthaben), RapValue (Wert aller handelbaren Skins), Reserved (JSON { [Id] = Stück }, die
-- gerade im Markt-Stand oder in einem Tausch liegen). Über dem Kopf (nur Hub und Markt) steht Guthaben + Wert.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local RapConfig = {}

RapConfig.Color = Color3.fromRGB(86, 214, 170) -- Farbe der Währung (Zahlen, Symbol)

RapConfig.SellRate = 0.7       -- Rückverkauf ans System: 70 % des RAP-Werts, sofort
RapConfig.MarketFee = 0.05     -- Grundgebühr (mittlere Stufe, siehe FeeTiers)
-- Marktgebühr nach Preis: kleine Verkäufe sind billiger, teure kosten mehr (Upto = bis einschließlich dieser Preis)
RapConfig.FeeTiers = {
	{ Upto = 50, Rate = 0.02 },
	{ Upto = 1000, Rate = 0.05 },
	{ Upto = 20000, Rate = 0.07 },
	{ Upto = math.huge, Rate = 0.10 },
}
RapConfig.LiveWeight = 0.1  -- RAP nach einem Verkauf: RAP + (Preis - RAP) * LiveWeight
RapConfig.LiveMin = 0.25    -- Untergrenze des lebenden RAP (Vielfaches des Basiswerts)
RapConfig.LiveMax = 8       -- Obergrenze
RapConfig.OfferSeconds = 45    -- so lange gilt ein Gegenangebot, bis der Besitzer antwortet
RapConfig.MinOfferFraction = 0.5 -- Gegenangebote mindestens so hoch wie der halbe Preis
RapConfig.MaxOffersPerStand = 6
RapConfig.StandNameLength = 24 -- Stand-Name (läuft durch den Textfilter)
RapConfig.WatchLimit = 30      -- Skins auf der Merkliste
RapConfig.HistoryDays = 7      -- Preisverlauf: Verkäufe der letzten Tage
RapConfig.HistoryKeep = 40     -- gespeicherte Verkäufe pro Skin
RapConfig.MinPrice = 1
RapConfig.MaxPrice = 10000000
RapConfig.StandSlots = 6       -- Angebote pro Stand
RapConfig.TradeSlots = 8       -- verschiedene Skins pro Seite in einem Tausch
RapConfig.TradeConfirmTime = 4 -- Sekunden Countdown, wenn beide BEREIT sind (jede Änderung bricht ab)
RapConfig.TradeRequestTime = 20 -- so lange gilt eine Anfrage
RapConfig.TradeRange = 40      -- Anfrage nur an Spieler in der Nähe (Studs)

-- Basis-RAP der handelbaren Skins (Startwert, steil gestaffelt nach Seltenheit)
RapConfig.Values = {
	-- gewöhnlich: 1 bis 10 RAP
	W_Wald = 2, W_Wueste = 3,
	-- Shop: Waffen-Skins (selten, episch, legendär)
	W_Kirsche = 30, W_Mitternacht = 35, W_Carbon = 45,
	W_Gletscher = 260, W_Koralle = 340,
	W_Lava = 3200, W_Chrom = 5500, W_Galaxie = 8500,
	-- Shop: Agenten-Skins
	A_Viper_Nacht = 40, A_Bastion_Stahl = 40, A_Mender_Feld = 40, A_Hawk_Wueste = 40,
	A_Ghost_Schatten = 55, A_Blaze_Asche = 55, A_Aegis_Sanitaet = 55, A_Trapper_Wildnis = 55, A_Volt_Kupfer = 55,
	A_Viper_Gift = 420, A_Mender_Neon = 420,
	A_Blaze_Inferno = 520, A_Aegis_Bollwerk = 520, A_Volt_Hochspannung = 520,
	A_Bastion_Royal = 4500, A_Hawk_Phantom = 4800, A_Ghost_Nebel = 7500, A_Trapper_Jaeger = 8000,
	-- Battle Pass (nur in der Saison zu bekommen)
	W_Saison = 2500, W_Goldrausch = 35000, A_Viper_Saison = 45000,
	-- Glücksrad, Login-Kalender (Tag 7), Wochen-Bonus
	W_Gluecksklee = 1800, W_Kalender = 18000,
	W_Woche_Kobalt = 1000, W_Woche_Smaragd = 1100, W_Woche_Purpur = 1200, W_Woche_Bernstein = 1300, W_Woche_Titan = 1500,
	-- Robux-Shop (Royal-Paket)
	W_Royal = 90000, W_Hologramm = 150000,
}

-- Lebender RAP: [Skin] = Zahl (Kommazahl). Der Server füllt ihn aus dem DataStore und nach jedem Verkauf (MarketService)
-- und legt ihn als Attribut "RapLive" an ReplicatedStorage; die Clients lesen ihn von dort.
RapConfig.Live = {}

-- Farbe des RAP-Schilds über dem Kopf nach Gesamt-RAP (Guthaben + Wert der Skins)
RapConfig.Tiers = {
	{ Min = 0, Color = Color3.fromRGB(176, 184, 196) },
	{ Min = 100, Color = RapConfig.Color },
	{ Min = 1000, Color = Color3.fromRGB(96, 164, 230) },
	{ Min = 10000, Color = Color3.fromRGB(170, 120, 240) },
	{ Min = 50000, Color = Color3.fromRGB(240, 190, 70) },
	{ Min = 250000, Color = Color3.fromRGB(255, 92, 112) },
}

-- Basis-RAP eines Skins (nil = gebunden, nicht handelbar)
function RapConfig.Base(id)
	return type(id) == "string" and RapConfig.Values[id] or nil
end

-- Aktueller RAP-Wert (ganze Zahl, mindestens 1): lebender Wert, sonst der Basiswert (nil = gebunden)
function RapConfig.Value(id)
	local base = RapConfig.Base(id)
	if not base then
		return nil
	end
	local live = RapConfig.Live[id]
	if type(live) == "number" then
		return math.max(1, math.floor(live + 0.5))
	end
	return base
end

function RapConfig.Tradeable(id)
	return RapConfig.Base(id) ~= nil
end

-- Neuer lebender RAP nach einem Verkauf zu price: RAP + (price - RAP) / 10, begrenzt (current = bisheriger Wert, sonst Basis)
function RapConfig.NextLive(id, price, current)
	local base = RapConfig.Base(id)
	if not base then
		return nil
	end
	current = type(current) == "number" and current or RapConfig.Live[id] or base
	local nextValue = current + (price - current) * RapConfig.LiveWeight
	return math.clamp(nextValue, base * RapConfig.LiveMin, base * RapConfig.LiveMax)
end

-- Lebende Werte ersetzen (nur bekannte Skins, nur Zahlen)
function RapConfig.SetLive(map)
	local clean = {}
	for id, value in type(map) == "table" and map or {} do
		if RapConfig.Base(id) and type(value) == "number" and value == value then
			clean[id] = value
		end
	end
	RapConfig.Live = clean
end

-- So viel RAP zahlt das System für ein Stück (immer vom Basiswert, mindestens 1)
function RapConfig.SellPrice(id)
	local base = RapConfig.Base(id)
	return base and math.max(1, math.floor(base * RapConfig.SellRate)) or 0
end

-- Gebührensatz (0..1) für einen Verkauf zu diesem Preis
function RapConfig.FeeRate(price)
	for _, tier in RapConfig.FeeTiers do
		if price <= tier.Upto then
			return tier.Rate
		end
	end
	return RapConfig.FeeTiers[#RapConfig.FeeTiers].Rate
end

-- Marktgebühr in RAP für einen Verkauf zu price (gerundet: winzige Preise zahlen oft gar nichts)
function RapConfig.Fee(price)
	return math.floor(price * RapConfig.FeeRate(price) + 0.5)
end

-- Was der Verkäufer am Stand von price behält (nach Marktgebühr)
function RapConfig.AfterFee(price)
	return price - RapConfig.Fee(price)
end

-- Stückzahl eines Skins im Besitz-Eintrag (alte Spielstände: true = 1 Stück)
function RapConfig.Count(owned, id)
	local entry = type(owned) == "table" and owned[id]
	if entry == true then
		return 1
	end
	return math.max(0, math.floor(tonumber(entry) or 0))
end

-- Wert aller handelbaren Skins (Stückzahl × RAP-Wert)
function RapConfig.InventoryValue(owned)
	local total = 0
	for id in (type(owned) == "table" and owned or {}) do
		local value = RapConfig.Value(id)
		if value then
			total += value * RapConfig.Count(owned, id)
		end
	end
	return total
end

function RapConfig.TierColor(total)
	local color = RapConfig.Tiers[1].Color
	for _, tier in RapConfig.Tiers do
		if total >= tier.Min then
			color = tier.Color
		end
	end
	return color
end

-- Ganzzahliger Preis im erlaubten Bereich (nil, wenn ungültig)
function RapConfig.CleanPrice(price)
	price = tonumber(price)
	if not price or price ~= price then
		return nil
	end
	price = math.floor(price)
	if price < RapConfig.MinPrice or price > RapConfig.MaxPrice then
		return nil
	end
	return price
end

-- Clients: lebende Werte vom Server (Attribut RapLive an ReplicatedStorage) übernehmen und mitverfolgen
if RunService:IsClient() then
	local function load()
		local raw = ReplicatedStorage:GetAttribute("RapLive")
		local ok, data = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "{}")
		RapConfig.SetLive(ok and data or {})
	end
	load()
	ReplicatedStorage:GetAttributeChangedSignal("RapLive"):Connect(load)
end

return RapConfig

-- RapConfig (ModuleScript)
-- RAP ist die zweite Währung (wie in Sniper Arena): Man bekommt sie nur über seltene Skins. Jeder seltene Skin –
-- Waffe oder Agent – hat einen festen RAP-Wert (Values). Wer so einen Skin hat, kann ihn
--   * im SHOP ans System zurückverkaufen (Reiter VERKAUFEN, sofort SellRate × RAP-Wert),
--   * im MARKT an einem eigenen Stand zum selbst gewählten Preis anbieten (Käufer zahlen in RAP, MarketFee geht ab),
--   * mit anderen Spielern tauschen (Skins und RAP).
-- Mit dem RAP kauft man im Markt Skins von anderen Spielern. Handelbare Skins kann man mehrfach besitzen
-- (Duplikate aus Glücksrad, Login-Kalender, Wochen-Bonus, Robux-Paket oder Käufen von anderen Spielern).
-- Gebunden – ohne RAP-Wert, nicht verkauf- oder tauschbar – sind gewöhnliche Skins, Belohnungen für Level,
-- Prestige, Rang und Saison sowie die Meisterschafts-Tarnungen. Neuen Skin handelbar machen: Wert hier eintragen.
-- Spieler-Attribute: Rap (Guthaben), RapValue (Wert aller handelbaren Skins), Reserved (JSON { [Id] = Stück }, die
-- gerade im Markt-Stand oder in einem Tausch liegen). Über dem Kopf (nur Hub und Markt) steht Guthaben + Wert.

local RapConfig = {}

RapConfig.Color = Color3.fromRGB(86, 214, 170) -- Farbe der Währung (Zahlen, Symbol)

RapConfig.SellRate = 0.7       -- Rückverkauf ans System: 70 % des RAP-Werts, sofort
RapConfig.MarketFee = 0.05     -- Marktgebühr: 5 % des Preises gehen beim Verkauf am Stand verloren
RapConfig.MinPrice = 1
RapConfig.MaxPrice = 10000000
RapConfig.StandSlots = 6       -- Angebote pro Stand
RapConfig.TradeSlots = 8       -- verschiedene Skins pro Seite in einem Tausch
RapConfig.TradeConfirmTime = 4 -- Sekunden Countdown, wenn beide BEREIT sind (jede Änderung bricht ab)
RapConfig.TradeRequestTime = 20 -- so lange gilt eine Anfrage
RapConfig.TradeRange = 40      -- Anfrage nur an Spieler in der Nähe (Studs)

-- Feste RAP-Werte der handelbaren Skins
RapConfig.Values = {
	-- Shop: Waffen-Skins (selten, episch, legendär)
	W_Kirsche = 180, W_Mitternacht = 180, W_Carbon = 200,
	W_Gletscher = 340, W_Koralle = 360,
	W_Lava = 520, W_Chrom = 600, W_Galaxie = 650,
	-- Shop: Agenten-Skins
	A_Viper_Nacht = 240, A_Bastion_Stahl = 240, A_Mender_Feld = 240, A_Hawk_Wueste = 240,
	A_Ghost_Schatten = 280, A_Blaze_Asche = 280, A_Aegis_Sanitaet = 280, A_Trapper_Wildnis = 280, A_Volt_Kupfer = 280,
	A_Viper_Gift = 420, A_Mender_Neon = 420,
	A_Blaze_Inferno = 460, A_Aegis_Bollwerk = 460, A_Volt_Hochspannung = 460,
	A_Bastion_Royal = 650, A_Hawk_Phantom = 650, A_Ghost_Nebel = 700, A_Trapper_Jaeger = 700,
	-- Battle Pass (nur in der Saison zu bekommen)
	W_Saison = 1500, W_Goldrausch = 3500, A_Viper_Saison = 4000,
	-- Glücksrad, Login-Kalender (Tag 7), Wochen-Bonus
	W_Gluecksklee = 1200, W_Kalender = 2500,
	W_Woche_Kobalt = 900, W_Woche_Smaragd = 900, W_Woche_Purpur = 900, W_Woche_Bernstein = 900, W_Woche_Titan = 900,
	-- Robux-Shop (Royal-Paket)
	W_Royal = 5000, W_Hologramm = 6000,
}

-- Farbe des RAP-Schilds über dem Kopf nach Gesamt-RAP (Guthaben + Wert der Skins)
RapConfig.Tiers = {
	{ Min = 0, Color = Color3.fromRGB(176, 184, 196) },
	{ Min = 1000, Color = RapConfig.Color },
	{ Min = 5000, Color = Color3.fromRGB(96, 164, 230) },
	{ Min = 15000, Color = Color3.fromRGB(170, 120, 240) },
	{ Min = 50000, Color = Color3.fromRGB(240, 190, 70) },
	{ Min = 150000, Color = Color3.fromRGB(255, 92, 112) },
}

-- RAP-Wert eines Skins (nil = gebunden, nicht handelbar)
function RapConfig.Value(id)
	return type(id) == "string" and RapConfig.Values[id] or nil
end

function RapConfig.Tradeable(id)
	return RapConfig.Value(id) ~= nil
end

-- So viel RAP zahlt das System für ein Stück
function RapConfig.SellPrice(id)
	local value = RapConfig.Value(id)
	return value and math.floor(value * RapConfig.SellRate) or 0
end

-- Was der Verkäufer am Stand von price behält (nach Marktgebühr)
function RapConfig.AfterFee(price)
	return price - math.ceil(price * RapConfig.MarketFee)
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

return RapConfig

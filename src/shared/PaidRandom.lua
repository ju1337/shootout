-- PaidRandom (ModuleScript, Server und Client)
-- Roblox-Regeln für bezahlte Zufallsitems (Glücksrad: Drehs für Robux; Waffen-Kiste: Münzen, die man auch für Robux
-- kaufen kann). Chancen müssen vor dem Kauf bzw. Dreh als Prozent je Ergebnis zu sehen sein (Summe 100 %), und
-- PolicyService sagt je Spieler, ob er bezahlte Zufallsitems nutzen und Gekauftes handeln darf (z.B. nicht in Belgien,
-- den Niederlanden, Großbritannien, Australien, Brasilien). Der Server (PolicyGate) setzt dafür die Spieler-Attribute
-- PaidRandomOk und PaidTradeOk; fehlt eins, weiß der Server es noch nicht.
-- https://create.roblox.com/docs/production/monetization/paid-random-items

local PaidRandom = {}

PaidRandom.Note = "Gerundet, die Summe kann leicht von 100 % abweichen."

-- Chance (0..1) als Prozent: ganze Zahlen ohne Nachkommastellen, sonst 4 Stellen ab der ersten von 0 verschiedenen
-- Ziffer (Roblox erlaubt Runden erst danach), Nullen am Ende weg. 0.26 -> "26 %", 1/150 -> "0.6667 %"
function PaidRandom.Percent(chance)
	local value = (tonumber(chance) or 0) * 100
	if math.abs(value - math.floor(value + 0.5)) < 1e-9 then
		return string.format("%d %%", math.floor(value + 0.5))
	end
	local magnitude = math.floor(math.log10(math.abs(value)))
	local decimals = math.clamp(3 - magnitude, 0, 10)
	local text = string.format("%." .. decimals .. "f", value)
	if text:find("%.") then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return text .. " %"
end

-- Ist ein Robux-Produkt ein bezahltes Zufallsitem? (Glücksrad-Drehs)
function PaidRandom.IsRandomProduct(product)
	return product ~= nil and (product.Spins or 0) > 0
end

-- Client: Anzeige nach den Attributen. Unbekannt (nil) gilt als erlaubt, der Server prüft selbst noch einmal.
function PaidRandom.ShowRandom(player)
	return player:GetAttribute("PaidRandomOk") ~= false
end

function PaidRandom.ShowTrade(player)
	return player:GetAttribute("PaidTradeOk") ~= false
end

return PaidRandom

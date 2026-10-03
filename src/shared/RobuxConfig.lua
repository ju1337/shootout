-- RobuxConfig (ModuleScript)
-- Robux-Shop (Lobby: SHOP · ROBUX). Server: RobuxService (Käufe gutschreiben, Gamepässe prüfen).
-- IDs eintragen: Roblox Creator Hub → dein Spiel → Monetarisierung → Gamepässe bzw. Entwicklerprodukte anlegen,
-- dort die ID kopieren und hier bei PassId/ProductId einsetzen. Solange eine ID 0 ist, steht im Shop "BALD".
-- Der Preis in Robux wird in Roblox festgelegt; Robux hier ist nur der Anzeigewert, falls Roblox keinen liefert.

local RobuxConfig = {}

-- Gamepässe: einmal kaufen, für immer. Spieler-Attribut "Pass_<Id>" = true, wenn gekauft.
RobuxConfig.Passes = {
	{ Id = "VIP", PassId = 0, Robux = 399, Name = "VIP",
		Description = "Doppelte Münzen für immer · goldenes VIP über dem Namen", Color = Color3.fromRGB(255, 200, 60) },
	{ Id = "DoubleXP", PassId = 0, Robux = 299, Name = "DOPPEL-XP",
		Description = "Für immer doppelte XP für Level, Agenten und Battle Pass", Color = Color3.fromRGB(150, 120, 210) },
}

-- Entwicklerprodukte: beliebig oft kaufbar. Coins, Spins (Glücksrad), BoostMinutes (Doppel-XP), Items (Skins)
RobuxConfig.Products = {
	{ Id = "Coins1000", ProductId = 0, Robux = 49, Name = "1.000 MÜNZEN", Coins = 1000, Color = Color3.fromRGB(212, 170, 80) },
	{ Id = "Coins5500", ProductId = 0, Robux = 199, Name = "5.500 MÜNZEN", Coins = 5500, Tag = "+10 %",
		Color = Color3.fromRGB(230, 180, 70) },
	{ Id = "Coins12000", ProductId = 0, Robux = 399, Name = "12.000 MÜNZEN", Coins = 12000, Tag = "+20 %",
		Color = Color3.fromRGB(255, 200, 60) },
	{ Id = "Spins5", ProductId = 0, Robux = 79, Name = "5 GLÜCKSRAD-DREHS", Spins = 5, Color = Color3.fromRGB(230, 90, 120) },
	{ Id = "Boost2h", ProductId = 0, Robux = 99, Name = "2 H DOPPEL-XP", BoostMinutes = 120,
		Color = Color3.fromRGB(150, 120, 210) },
	{ Id = "RoyalBundle", ProductId = 0, Robux = 499, Name = "ROYAL-PAKET", Items = { "W_Royal", "W_Hologramm" }, Coins = 2000,
		Tag = "EXKLUSIV", Description = "Skins Royal + Hologramm und 2.000 Münzen", Color = Color3.fromRGB(180, 90, 255) },
}

local byProductId = {}
for _, product in RobuxConfig.Products do
	if product.ProductId ~= 0 then
		byProductId[product.ProductId] = product
	end
end

function RobuxConfig.ByProductId(id)
	return byProductId[id]
end

function RobuxConfig.Pass(id)
	for _, pass in RobuxConfig.Passes do
		if pass.Id == id then
			return pass
		end
	end
	return nil
end

-- Hat der Spieler den Gamepass? (Client und Server, über das Attribut)
function RobuxConfig.Has(player, id)
	return player:GetAttribute("Pass_" .. id) == true
end

-- Kurzer Text, was ein Produkt enthält
function RobuxConfig.Describe(product)
	if product.Description then
		return product.Description
	end
	if product.Coins then
		return "Münzen für Skins, Aufsätze und Agenten"
	elseif product.Spins then
		return "Extra-Drehs am Glücksrad"
	elseif product.BoostMinutes then
		return "Doppelte XP für " .. product.BoostMinutes .. " Minuten"
	end
	return ""
end

return RobuxConfig

-- BuyConfig (ModuleScript)
-- Geld und Kaufphase im Drop-Modus (wie bei Rogue Company). Das Geld gilt nur für ein Match
-- und ist getrennt von den Shop-Münzen. Gekauft wird während Agentenwahl und Countdown.
-- PerRound = gilt nur für die nächste Runde (Rüstung, Extra-Gadget), sonst bis Match-Ende.

local BuyConfig = {}

BuyConfig.StartMoney = 500
BuyConfig.MaxMoney = 9000
BuyConfig.Rewards = {
	Kill = 200,
	Revive = 100,
	RoundWin = 1000,
	RoundLoss = 600,
}

-- Wirkung der Upgrades
BuyConfig.MagFactor = 1.3        -- Magazin x1.3
BuyConfig.ReloadFactor = 0.7     -- Nachladezeit x0.7
BuyConfig.StabilityFactor = 0.65 -- Streuung und Rückstoß x0.65
BuyConfig.ArmorAmount = 25       -- Schild, das zuerst Schaden schluckt

BuyConfig.Items = {
	{ Id = "Mag", Name = "Großes Magazin", Description = "+30 % Magazin für alle Waffen", Price = 600 },
	{ Id = "Reload", Name = "Schnellladen", Description = "Nachladen 30 % schneller", Price = 500 },
	{ Id = "Stability", Name = "Stabilisator", Description = "35 % weniger Streuung und Rückstoß", Price = 700 },
	{ Id = "Armor", Name = "Rüstung", Description = "+25 Schild für diese Runde", Price = 400, PerRound = true },
	{ Id = "ExtraGadget", Name = "Extra-Gadget", Description = "+1 Gadget-Ladung für diese Runde", Price = 300, PerRound = true },
}

function BuyConfig.Get(id)
	for _, item in BuyConfig.Items do
		if item.Id == id then
			return item
		end
	end
	return nil
end

-- Hat der Spieler dieses Upgrade gekauft? (Spieler-Attribut "Buy_<Id>")
function BuyConfig.Has(player, id)
	return player:GetAttribute("Buy_" .. id) == true
end

return BuyConfig

-- BuyConfig (ModuleScript)
-- Geld und Kaufphase in den Team-Modi (wie bei Rogue Company). Das Geld gilt nur für ein Match
-- und ist getrennt von den Shop-Münzen. Gekauft wird während Agentenwahl und Countdown.
-- PerRound = gilt nur für die nächste Runde bzw. bis zum nächsten Tod (Rüstung, Extra-Gadget), sonst bis Match-Ende.
-- In Modi mit Respawn kauft man in der Auswahl nach dem Tod nach.
-- Perk = passiver Vorteil (wie die Perks bei Rogue Company), gilt bis Match-Ende.

local BuyConfig = {}

BuyConfig.StartMoney = 500
BuyConfig.MaxMoney = 9000
BuyConfig.Rewards = {
	Kill = 200,
	Revive = 100,
	Assist = 50,
	RoundWin = 1000,
	RoundLoss = 600,
}

-- Wirkung der Upgrades
BuyConfig.MagFactor = 1.3        -- Magazin x1.3
BuyConfig.ReloadFactor = 0.7     -- Nachladezeit x0.7
BuyConfig.StabilityFactor = 0.65 -- Streuung und Rückstoß x0.65
BuyConfig.ArmorAmount = 25       -- Schild, das zuerst Schaden schluckt
BuyConfig.ToughHealth = 15       -- Perk "Zäh": mehr Max-Leben
BuyConfig.RegenDelay = 5         -- Perk "Regeneration": Sekunden ohne Schaden bis zum Heilen
BuyConfig.RegenPerSecond = 4
BuyConfig.MedicFactor = 1.67     -- Perk "Sanitäter": Wiederbeleben 40 % schneller
BuyConfig.RunnerFactor = 1.08    -- Perk "Leichtfuß": Tempo
BuyConfig.VengeanceTime = 5      -- Perk "Racheblick": Sekunden, die der Killer markiert ist

BuyConfig.Items = {
	{ Id = "Mag", Name = "Großes Magazin", Description = "+30 % Magazin für alle Waffen", Price = 600 },
	{ Id = "Reload", Name = "Schnellladen", Description = "Nachladen 30 % schneller", Price = 500 },
	{ Id = "Stability", Name = "Stabilisator", Description = "35 % weniger Streuung und Rückstoß", Price = 700 },
	{ Id = "Armor", Name = "Rüstung", Description = "+25 Schild bis zum nächsten Tod (bzw. Rundenende)", Price = 400, PerRound = true },
	{ Id = "ExtraGadget", Name = "Extra-Gadget", Description = "+1 Gadget-Ladung bis zum nächsten Tod (bzw. Rundenende)", Price = 300, PerRound = true },
	{ Id = "Tough", Name = "Zäh", Description = "Perk: +15 Max-Leben", Price = 500, Perk = true },
	{ Id = "Regen", Name = "Regeneration", Description = "Perk: Nach 5 s ohne Schaden heilst du langsam", Price = 600, Perk = true },
	{ Id = "Medic", Name = "Sanitäter", Description = "Perk: Wiederbeleben 40 % schneller", Price = 400, Perk = true },
	{ Id = "Runner", Name = "Leichtfuß", Description = "Perk: +8 % Lauftempo", Price = 400, Perk = true },
	{ Id = "Vengeance", Name = "Racheblick", Description = "Perk: Wer dich ausschaltet, wird 5 s für dein Team markiert", Price = 300, Perk = true },
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

-- PassConfig (ModuleScript)
-- Kostenloser Battle Pass: Pass-XP gibt es für alle XP im Spiel und für abgeholte Aufträge.
-- Jede Stufe schaltet ihre Belohnung automatisch frei (Münzen oder exklusiver Skin).
-- Spieler-Attribut "PassXP".

local PassConfig = {}

PassConfig.SeasonName = "SAISON 1 · ERSTER EINSATZ"
PassConfig.XPPerTier = 1000
PassConfig.QuestXP = 300 -- Pass-XP pro abgeholtem Auftrag

-- Belohnung pro Stufe: { Coins = n } oder { Item = "<Cosmetics-Id>" }
PassConfig.Tiers = {}
for tier = 1, 30 do
	if tier == 10 then
		PassConfig.Tiers[tier] = { Item = "W_Saison" }
	elseif tier == 20 then
		PassConfig.Tiers[tier] = { Item = "W_Saison_Elite" }
	elseif tier == 30 then
		PassConfig.Tiers[tier] = { Item = "W_Goldrausch" }
	else
		PassConfig.Tiers[tier] = { Coins = tier % 5 == 0 and 300 or 100 }
	end
end

-- Erreichte Stufe (0 bis Anzahl Stufen) und Fortschritt in der nächsten Stufe (0 bis 1)
function PassConfig.TierFromXP(xp)
	local tier = math.min(#PassConfig.Tiers, math.floor((xp or 0) / PassConfig.XPPerTier))
	local progress = tier >= #PassConfig.Tiers and 1 or ((xp or 0) % PassConfig.XPPerTier) / PassConfig.XPPerTier
	return tier, progress
end

return PassConfig

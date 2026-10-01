-- RankConfig (ModuleScript)
-- Ränge für den Ranked-Modus. Rangpunkte (RP) gibt es pro gewonnenem Match, bei Niederlagen
-- werden welche abgezogen. Spieler-Attribut "RankPoints".

local RankConfig = {}

RankConfig.WinPoints = 25
RankConfig.LossPoints = 15

-- Ab wie vielen RP ein Rang beginnt (aufsteigend)
RankConfig.Tiers = {
	{ Name = "Bronze", Points = 0, Color = Color3.fromRGB(190, 120, 70) },
	{ Name = "Silber", Points = 100, Color = Color3.fromRGB(190, 195, 205) },
	{ Name = "Gold", Points = 250, Color = Color3.fromRGB(240, 195, 60) },
	{ Name = "Platin", Points = 450, Color = Color3.fromRGB(90, 220, 200) },
	{ Name = "Diamant", Points = 700, Color = Color3.fromRGB(110, 170, 255) },
	{ Name = "Meister", Points = 1000, Color = Color3.fromRGB(220, 90, 255) },
}

-- Rang zu einer Punktzahl
function RankConfig.Get(points)
	local current = RankConfig.Tiers[1]
	for _, tier in RankConfig.Tiers do
		if (points or 0) >= tier.Points then
			current = tier
		end
	end
	return current
end

return RankConfig

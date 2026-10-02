-- RankConfig (ModuleScript)
-- Ranked mit ELO: Jeder startet bei StartElo. Nach jedem Ranked-Match ändert sich die ELO nach der
-- klassischen ELO-Formel (Team-Durchschnitt gegen Team-Durchschnitt). Die ersten PlacementMatches
-- zählen stärker (Platzierungsspiele). Ränge mit Divisionen (z.B. "GOLD II") ergeben sich aus der ELO.
-- Spieler-Attribute: Elo, RankedData (JSON: Peak, Wins, Losses, Matches)

local RankConfig = {}

-- Saisons laufen automatisch: Saison 1 beginnt am Montag, 28.09.2026 (0 Uhr UTC), jede dauert SeasonLength.
-- Bei neuer Saison wird die ELO zur Hälfte Richtung Start zurückgesetzt, dafür gibt es eine Belohnung
-- nach dem höchsten Rang der alten Saison (RewardConfig.SeasonEnd, ProgressService).
RankConfig.SeasonStart = 1790553600
RankConfig.SeasonLength = 6 * 7 * 24 * 3600 -- 6 Wochen

-- Aktuelle Saison (Serverzeit) und Sekunden bis zu ihrem Ende
function RankConfig.CurrentSeason(now)
	now = now or workspace:GetServerTimeNow()
	return math.max(1, math.floor((now - RankConfig.SeasonStart) / RankConfig.SeasonLength) + 1)
end

function RankConfig.SeasonLeft(now)
	now = now or workspace:GetServerTimeNow()
	local season = RankConfig.CurrentSeason(now)
	return math.max(0, RankConfig.SeasonStart + season * RankConfig.SeasonLength - now)
end

-- "37 T 4 H" bzw. "5 H 12 MIN"
function RankConfig.FormatLeft(seconds)
	if seconds >= 86400 then
		return math.floor(seconds / 86400) .. " T " .. math.floor(seconds % 86400 / 3600) .. " H"
	end
	return math.floor(seconds / 3600) .. " H " .. math.floor(seconds % 3600 / 60) .. " MIN"
end

RankConfig.Season = RankConfig.CurrentSeason() -- Stand beim Laden; für Live-Werte CurrentSeason() benutzen
RankConfig.StartElo = 1000
RankConfig.PlacementMatches = 5
RankConfig.PlacementK = 48     -- Gewichtung in Platzierungsspielen
RankConfig.K = 24              -- Gewichtung danach
RankConfig.MvpBonus = 3        -- kleiner Bonus für den MVP des Matches
RankConfig.MinChange = 5       -- mindestens so viel gewinnt/verliert man

-- Ränge: ab welcher ELO sie beginnen (aufsteigend). Jeder Rang (außer Meister) hat 3 Divisionen.
RankConfig.Tiers = {
	{ Name = "Bronze", Elo = 0, Color = Color3.fromRGB(190, 120, 70) },
	{ Name = "Silber", Elo = 900, Color = Color3.fromRGB(190, 195, 205) },
	{ Name = "Gold", Elo = 1100, Color = Color3.fromRGB(240, 195, 60) },
	{ Name = "Platin", Elo = 1300, Color = Color3.fromRGB(90, 220, 200) },
	{ Name = "Diamant", Elo = 1500, Color = Color3.fromRGB(110, 170, 255) },
	{ Name = "Meister", Elo = 1700, Color = Color3.fromRGB(220, 90, 255) },
}

local DIVISIONS = { "III", "II", "I" }

-- Rang zu einer ELO: { Name, Color, Division, Display, Progress (0..1 bis zur nächsten Stufe) }
function RankConfig.Get(elo)
	elo = elo or RankConfig.StartElo
	local index = 1
	for i, tier in RankConfig.Tiers do
		if elo >= tier.Elo then
			index = i
		end
	end
	local tier = RankConfig.Tiers[index]
	local nextTier = RankConfig.Tiers[index + 1]
	if not nextTier then
		return { Name = tier.Name, Color = tier.Color, Division = "", Display = string.upper(tier.Name), Progress = 1 }
	end
	-- Bronze beginnt "unten offen": für die Divisionen ab 700 rechnen
	local low = index == 1 and 700 or tier.Elo
	local span = (nextTier.Elo - low) / 3
	local step = math.clamp(math.floor((elo - low) / span), 0, 2)
	local progress = math.clamp(((elo - low) - step * span) / span, 0, 1)
	return {
		Name = tier.Name,
		Color = tier.Color,
		Division = DIVISIONS[step + 1],
		Display = string.upper(tier.Name) .. " " .. DIVISIONS[step + 1],
		Progress = progress,
	}
end

-- ELO-Änderung für ein Team-Ergebnis
-- won: true/false, teamElo/enemyElo: Durchschnitte, matches: bisherige Ranked-Matches des Spielers
function RankConfig.Change(won, teamElo, enemyElo, matches, isMvp)
	local expected = 1 / (1 + 10 ^ ((enemyElo - teamElo) / 400))
	local k = (matches or 0) < RankConfig.PlacementMatches and RankConfig.PlacementK or RankConfig.K
	local change = k * ((won and 1 or 0) - expected)
	if won then
		change = math.max(change, RankConfig.MinChange)
	else
		change = math.min(change, -RankConfig.MinChange)
	end
	if isMvp then
		change += RankConfig.MvpBonus
	end
	return math.floor(change + 0.5)
end

return RankConfig

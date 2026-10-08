-- Modes (ModuleScript)
-- Alle Spielmodi für Menü und Portale. Alle Modi laufen im selben Place,
-- jeder in seinem eigenen Bereich der Welt (Center = Mitte der Map).
-- Center muss zu den Verschiebungen in tools/build_maps.py passen.
-- TeamMode = Team-Runden mit Agentenwahl und Kaufphase (Herrschaft, Wingman, Arena)
-- Category = Gruppe im Menü und im Hub (z.B. "DUELS" für Wingman und 1v1 Arena)
-- Overview = Kameraflug über die Map während der Agentenwahl (Radius, Höhe)
-- Goal = kurzes Ziel oben im HUD (Text, oder { Attack, Defend } bei Angriff/Verteidigung,
--        AttackAlert/DefendAlert solange die Uhr des Ziels läuft, z.B. Bombe gelegt)
-- Objectives = Ziel-Parts der Map (Maps.<Map>.Objective.<Part>) mit Buchstaben für Marker und Minimap
-- Featured = Hauptmodus (groß oben im Menü, eigenes Portal im Hub): EXTINCTION
-- Arcade = Minispiel (im Menü unter ARCADE, kein Portal im Hub)
-- Survival = offene Welt mit eigenem Inventar (Hotbar 1-9 statt Waffe 1/2, keine Standardwaffen),
--            Safe Zone, PvP außerhalb, nur passive Agenten-Fähigkeiten (siehe ExtinctionConfig)

local Modes = {}

Modes.List = {
	{
		Id = "Extinction",
		Name = "EXTINCTION",
		Tag = "Offene Welt · Überleben",
		Description = "Start in der Safe Zone: Waffen, Items und Fahrzeuge für Münzen kaufen, Wertvolles ins Lager legen.\n"
			.. "Draußen kommen Zombies, nach 5 Sekunden ist PvP an. Wer stirbt, lässt seine Tasche fallen.",
		Players = "bis 30 Spieler",
		Color = Color3.fromRGB(215, 85, 45),
		Center = Vector3.new(0, 0, -6000),
		Goal = "ÜBERLEBE DRAUSSEN",
		Featured = true,
		Survival = true,
		Available = true,
	},
	{
		Id = "FreeForAll",
		Name = "FREE-FOR-ALL",
		Tag = "Jeder gegen jeden",
		Description = "Respawn nach 3 Sekunden.\nWer zuerst 20 Kills hat, gewinnt die Runde.",
		Players = "bis 12 Spieler",
		Color = Color3.fromRGB(200, 110, 70),
		Center = Vector3.new(0, 0, 1500),
		Goal = "JEDER GEGEN JEDEN",
		Arcade = true,
		Available = true,
	},
	{
		Id = "Domination",
		Name = "HERRSCHAFT",
		Tag = "5v5 Flaggen",
		Description = "Drei Flaggen A, B und C einnehmen und halten. Jede gehaltene Flagge gibt Punkte.\nUnbegrenzter Respawn, 200 Punkte gewinnen.",
		Players = "10 Spieler",
		Color = Color3.fromRGB(90, 140, 190),
		Center = Vector3.new(1500, 0, 0),
		TeamMode = true,
		Overview = { Radius = 280, Height = 170 },
		Goal = "HALTE DIE FLAGGEN",
		Objectives = { { Part = "FlagA", Label = "A" }, { Part = "FlagB", Label = "B" }, { Part = "FlagC", Label = "C" } },
		Arcade = true,
		Available = true,
	},
	{
		Id = "Wingman",
		Name = "WINGMAN",
		Tag = "Duels · 2v2",
		Category = "DUELS",
		Description = "Zwei gegen zwei um den Punkt in der Mitte: Wer ihn hält, zieht dem Gegner Tickets ab.\n4 Respawn-Tickets pro Team, 3 Rundensiege gewinnen.",
		Players = "4 Spieler",
		Color = Color3.fromRGB(120, 150, 110),
		Center = Vector3.new(1500, 0, -1500),
		TeamMode = true,
		Overview = { Radius = 190, Height = 120 },
		Goal = "NIMM DEN PUNKT EIN",
		Objectives = { { Part = "CapturePoint", Label = "A" } },
		Arcade = true,
		Available = true,
	},
	{
		Id = "Arena",
		Name = "1v1 ARENA",
		Tag = "Duels · 1v1",
		Category = "DUELS",
		Description = "Eins gegen eins auf kleiner Map. Ein Leben pro Runde.\n5 Rundensiege gewinnen.",
		Players = "2 Spieler",
		Color = Color3.fromRGB(180, 80, 70),
		Center = Vector3.new(0, 0, 3000),
		TeamMode = true,
		Overview = { Radius = 70, Height = 50 },
		Goal = "GEWINNE DAS DUELL",
		Arcade = true,
		Available = true,
	},
	{
		Id = "Training",
		Name = "TRAINING",
		Tag = "Schießstand",
		Description = "Waffen, Agenten und Skins ausprobieren. Übungspuppen stehen wieder auf.",
		Players = "beliebig",
		Color = Color3.fromRGB(150, 156, 164),
		Center = Vector3.new(-1500, 0, 1500),
		Arcade = true,
		Available = true,
	},
}

-- Ausgebaute Modi (Code und Configs bleiben, damit man sie wieder einbauen kann:
-- Eintrag zurück nach Modes.List, Modul in ModeManager laden, Maps in tools/build_maps.py wieder erzeugen)
Modes.Disabled = {
	{
		Id = "TeamDeathmatch",
		Name = "TEAM DEATHMATCH",
		Tag = "5v5 Respawn",
		Description = "60 Leben pro Team, unbegrenzt Respawn bis die Leben weg sind.\nWer dem Gegner alle Leben abnimmt, gewinnt.",
		Players = "10 Spieler",
		Color = Color3.fromRGB(120, 210, 80),
		Center = Vector3.new(3000, 0, -1500),
		TeamMode = true,
		Overview = { Radius = 200, Height = 130 },
		Goal = "BRAUCHE DIE GEGNERISCHEN LEBEN AUF",
		Available = true,
	},
	{
		Id = "Drop",
		Name = "DROP",
		Tag = "5v5 Team",
		Description = "Absprung über der Map, Landepunkt selbst wählen.\nKein Respawn. 5 Rundensiege gewinnen.",
		Players = "10 Spieler",
		Color = Color3.fromRGB(80, 160, 255),
		Center = Vector3.new(1500, 0, 0),
		TeamMode = true,
		Overview = { Radius = 230, Height = 150 },
		Goal = "SCHALTE DAS GEGNERTEAM AUS",
		Available = true,
	},
	{
		Id = "Strikeout",
		Name = "STRIKEOUT",
		Tag = "4v4 Team",
		Description = "10 Respawn-Tickets pro Team. Wer den Punkt hält, zieht dem Gegner Tickets ab.\n3 Rundensiege gewinnen.",
		Players = "8 Spieler",
		Color = Color3.fromRGB(255, 170, 50),
		Center = Vector3.new(0, 0, -1500),
		TeamMode = true,
		Overview = { Radius = 190, Height = 120 },
		Goal = "NIMM DEN PUNKT EIN",
		Objectives = { { Part = "CapturePoint", Label = "A" } },
		Available = true,
	},
	{
		Id = "Demolition",
		Name = "DEMOLITION",
		Tag = "4v4 Angriff/Verteidigung",
		Description = "Ein Leben pro Runde. Bombe bei A oder B legen oder entschärfen.\nSeitenwechsel zur Halbzeit, 4 Rundensiege gewinnen.",
		Players = "8 Spieler",
		Color = Color3.fromRGB(230, 70, 90),
		Center = Vector3.new(-1500, 0, 0),
		TeamMode = true,
		Overview = { Radius = 210, Height = 130 },
		Goal = { Attack = "LEGE DIE BOMBE BEI A ODER B", Defend = "VERTEIDIGE A UND B",
			AttackAlert = "BESCHÜTZE DIE BOMBE", DefendAlert = "ENTSCHÄRFE DIE BOMBE" },
		Objectives = { { Part = "SiteA", Label = "A" }, { Part = "SiteB", Label = "B" } },
		Available = true,
	},
	{
		Id = "Extraction",
		Name = "EXTRACTION",
		Tag = "4v4 Hacken",
		Description = "Ein Leben pro Runde. Angreifer hacken Ziel A oder B, Verteidiger stören.\nSeitenwechsel zur Halbzeit.",
		Players = "8 Spieler",
		Color = Color3.fromRGB(60, 200, 190),
		Center = Vector3.new(3000, 0, 1500),
		TeamMode = true,
		Overview = { Radius = 170, Height = 110 },
		Goal = { Attack = "HACKE ZIEL A ODER B", Defend = "VERHINDERE DEN HACK" },
		Objectives = { { Part = "SiteA", Label = "A" }, { Part = "SiteB", Label = "B" } },
		Available = true,
	},
	{
		Id = "Ranked",
		Name = "RANKED",
		Tag = "Demolition gewertet",
		Description = "Demolition um ELO, ab Spielerlevel 10. 5 Platzierungsspiele,\ndann Ränge von Bronze III bis Meister.",
		Players = "8 Spieler",
		Color = Color3.fromRGB(255, 200, 60),
		Center = Vector3.new(1500, 0, 1500),
		TeamMode = true,
		Overview = { Radius = 210, Height = 130 },
		Goal = { Attack = "LEGE DIE BOMBE BEI A ODER B", Defend = "VERTEIDIGE A UND B",
			AttackAlert = "BESCHÜTZE DIE BOMBE", DefendAlert = "ENTSCHÄRFE DIE BOMBE" },
		Objectives = { { Part = "SiteA", Label = "A" }, { Part = "SiteB", Label = "B" } },
		Available = true,
	},
}

-- Der Hub ist kein Modus im Menü, aber ein Ziel ("Zurück zum Hub")
Modes.Hub = {
	Id = "Hub",
	Name = "HUB",
	Color = Color3.fromRGB(255, 140, 40),
	Center = Vector3.new(0, 0, 0),
	Available = true,
}

-- Der Markt: eigene Halle mit Ständen (MarketService), wie der Hub kein Kampfmodus. Erreichbar über das Tor MARKT
-- im Hub und den Knopf MARKT im Seitenmenü, nicht über die Modus-Liste.
Modes.Market = {
	Id = "Market",
	Name = "MARKT",
	Color = Color3.fromRGB(86, 214, 170),
	Center = Vector3.new(-1500, 0, -1500),
	Available = true,
}

-- Arcade über mehrere Server (MatchmakingService): Wer in einen dieser Modi will, wechselt auf einen Server, auf dem dort
-- mehr echte Spieler sind (wenn es einen mit Platz gibt). Die Reihenfolge ist auch die von SCHNELLES SPIEL bei Gleichstand.
Modes.Matchmaking = {
	Modes = { "Domination", "FreeForAll", "Wingman", "Arena" },
	MapName = "ArcadeServers_v1", -- MemoryStore Sorted Map: [JobId] = { Place, Free, Modes = { [Id] = { P, F } } }
	Interval = 10,      -- so oft meldet jeder Server seine Zahlen (Sekunden)
	Expire = 45,        -- so lange gilt eine Meldung (danach gilt der Server als weg)
	Cache = 5,          -- so lange wird die Liste der Server wiederverwendet
	Cooldown = 60,      -- so lange wird ein Spieler nach einem Wechsel (oder Fehlschlag) nicht wieder weitergeschickt
	TeleportTimeout = 30, -- kommt der Teleport so lange nicht an, wird hier gespielt
}

-- Modus per Id holen (inkl. Hub und Markt), nil wenn unbekannt
function Modes.Get(id)
	if id == Modes.Hub.Id then
		return Modes.Hub
	end
	if id == Modes.Market.Id then
		return Modes.Market
	end
	for _, mode in Modes.List do
		if mode.Id == id then
			return mode
		end
	end
	return nil
end

-- Läuft der Modus in Team-Runden (Agentenwahl, Kaufphase, Niederschlagen)?
function Modes.IsTeamMode(id)
	local mode = Modes.Get(id)
	return mode ~= nil and mode.TeamMode == true
end

-- Kurzes Ziel für das HUD. attacking = true/false in Modi mit Angriff/Verteidigung, sonst nil;
-- alert = die Uhr des Ziels läuft (z.B. Bombe gelegt)
function Modes.GoalText(id, attacking, alert)
	local mode = Modes.Get(id)
	local goal = mode and mode.Goal
	if type(goal) == "table" then
		if attacking == nil then
			return nil
		end
		if alert then
			return (attacking and goal.AttackAlert or goal.DefendAlert) or (attacking and goal.Attack or goal.Defend)
		end
		return attacking and goal.Attack or goal.Defend
	end
	return goal
end

-- Offene Welt mit eigenem Inventar und Safe Zone (Extinction)?
function Modes.IsSurvival(id)
	local mode = Modes.Get(id)
	return mode ~= nil and mode.Survival == true
end

-- Minispiele (im Menü unter ARCADE) und der Hauptmodus (groß oben)
function Modes.Arcade()
	local list = {}
	for _, mode in Modes.List do
		if mode.Arcade then
			table.insert(list, mode)
		end
	end
	return list
end

function Modes.Featured()
	for _, mode in Modes.List do
		if mode.Featured then
			return mode
		end
	end
	return nil
end

-- Treffpunkt ohne Kampf (Hub, Markt)?
function Modes.IsSocial(id)
	return id == Modes.Hub.Id or id == Modes.Market.Id
end

-- Ist der Spieler gerade in einem Kampfmodus (nicht im Hub oder Markt)?
function Modes.IsFighting(player)
	local id = player:GetAttribute("Mode")
	return id ~= nil and not Modes.IsSocial(id)
end

return Modes

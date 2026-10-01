-- Modes (ModuleScript)
-- Alle Spielmodi für Menü und Portale. Alle Modi laufen im selben Place,
-- jeder in seinem eigenen Bereich der Welt (Center = Mitte der Map).
-- Center muss zu den Verschiebungen in tools/build_maps.py passen.
-- TeamMode = Team-Runden mit Agentenwahl und Kaufphase (Drop, Strikeout)
-- Overview = Kameraflug über die Map während der Agentenwahl (Radius, Höhe)

local Modes = {}

Modes.List = {
	{
		Id = "FreeForAll",
		Name = "FREE-FOR-ALL",
		Tag = "Jeder gegen jeden",
		Description = "Respawn nach 3 Sekunden.\nWer zuerst 20 Kills hat, gewinnt die Runde.",
		Players = "bis 12 Spieler",
		Color = Color3.fromRGB(255, 120, 60),
		Center = Vector3.new(0, 0, 1500),
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
		Overview = { Radius = 140, Height = 90 },
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
		Overview = { Radius = 170, Height = 110 },
		Available = true,
	},
	{
		Id = "Wingman",
		Name = "WINGMAN",
		Tag = "2v2 Team",
		Description = "Wie Strikeout, aber zu zweit und mit nur 4 Respawn-Tickets pro Team.\n3 Rundensiege gewinnen.",
		Players = "4 Spieler",
		Color = Color3.fromRGB(120, 220, 160),
		Center = Vector3.new(1500, 0, -1500),
		TeamMode = true,
		Overview = { Radius = 140, Height = 90 },
		Available = true,
	},
	{
		Id = "Training",
		Name = "TRAINING",
		Tag = "Schießstand",
		Description = "Waffen, Agenten und Skins ausprobieren. Übungspuppen stehen wieder auf.",
		Players = "beliebig",
		Color = Color3.fromRGB(150, 160, 180),
		Center = Vector3.new(-1500, 0, 1500),
		Available = true,
	},
	{
		Id = "Arena",
		Name = "1v1 ARENA",
		Tag = "Duell",
		Description = "Eins gegen eins auf kleiner Map. Ein Leben pro Runde.\n5 Rundensiege gewinnen.",
		Players = "2 Spieler",
		Color = Color3.fromRGB(170, 100, 255),
		Center = Vector3.new(0, 0, 3000),
		TeamMode = true,
		Overview = { Radius = 70, Height = 50 },
		Available = true,
	},
	{
		Id = "Ranked",
		Name = "RANKED",
		Tag = "Demolition gewertet",
		Description = "Demolition um Rangpunkte: Sieg +25 RP, Niederlage −15 RP.\nVon Bronze bis Meister.",
		Players = "8 Spieler",
		Color = Color3.fromRGB(255, 200, 60),
		Center = Vector3.new(1500, 0, 1500),
		TeamMode = true,
		Overview = { Radius = 170, Height = 110 },
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

-- Modus per Id holen (inkl. Hub), nil wenn unbekannt
function Modes.Get(id)
	if id == Modes.Hub.Id then
		return Modes.Hub
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

-- Ist der Spieler gerade in einem Kampfmodus (nicht im Hub)?
function Modes.IsFighting(player)
	local id = player:GetAttribute("Mode")
	return id ~= nil and id ~= Modes.Hub.Id
end

return Modes

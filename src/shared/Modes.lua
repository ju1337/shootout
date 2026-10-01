-- Modes (ModuleScript)
-- Alle Spielmodi für Menü und Portale. Alle Modi laufen im selben Place,
-- jeder in seinem eigenen Bereich der Welt (Center = Mitte der Map).
-- Center muss zu den Verschiebungen in tools/build_maps.py passen.

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
		Available = true,
	},
	{
		Id = "Arena",
		Name = "1v1 ARENA",
		Tag = "Duell",
		Description = "Eins gegen eins in kleinen Arenen.",
		Players = "2 Spieler",
		Color = Color3.fromRGB(170, 100, 255),
		Available = false,
	},
	{
		Id = "Ranked",
		Name = "RANKED",
		Tag = "Gewertet",
		Description = "Drop mit Rang und Punkten.",
		Players = "10 Spieler",
		Color = Color3.fromRGB(255, 200, 60),
		Available = false,
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

-- Ist der Spieler gerade in einem Kampfmodus (nicht im Hub)?
function Modes.IsFighting(player)
	local id = player:GetAttribute("Mode")
	return id ~= nil and id ~= Modes.Hub.Id
end

return Modes

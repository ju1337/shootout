-- KillstreakConfig (ModuleScript)
-- Killstreak-Belohnungen in Herrschaft: Kills ohne zu sterben schalten sie frei, danach liegen sie bereit
-- (rechts am Rand) und werden per Taste ausgelöst – auch nach dem Tod noch, bis man den Modus verlässt.
-- Server: KillstreakService, Client: KillstreakHUD. Spieler-Attribute: Killstreak (Kills dieses Lebens),
-- KillstreakReady (JSON { [Id] = true }).

local KillstreakConfig = {}

KillstreakConfig.Modes = { Domination = true }

-- Action = InputActions-Aktion (Tastatur 4/5/6), Aim = Ziel wählen (Luftschlag dorthin, wohin man zielt)
KillstreakConfig.List = {
	{ Id = "Radar", Kills = 5, Name = "DROHNE", Short = "D", Action = "Killstreak1",
		Description = "Alle Gegner 10 s fürs Team sichtbar (durch Wände)", Color = Color3.fromRGB(96, 164, 214) },
	{ Id = "Airstrike", Kills = 8, Name = "LUFTSCHLAG", Short = "L", Action = "Killstreak2", Aim = true,
		Description = "Einschlag dort, wohin du zielst (nach 3 s, nur im Freien)", Color = Color3.fromRGB(230, 90, 70) },
	{ Id = "Shield", Kills = 12, Name = "SCHUTZSCHILD", Short = "S", Action = "Killstreak3",
		Description = "Ganzes Team: volles Leben, Rüstung, 4 s unverwundbar", Color = Color3.fromRGB(112, 178, 112) },
}

function KillstreakConfig.Get(id)
	for _, entry in KillstreakConfig.List do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

return KillstreakConfig

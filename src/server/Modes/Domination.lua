-- Domination (ModuleScript, nur Server) – Modus "Herrschaft"
-- 5v5 mit unbegrenztem Respawn: drei Flaggen A/B/C einnehmen und halten. Gehaltene Flaggen geben
-- Punkte, wer zuerst DominationScore Punkte hat (oder bei Zeitablauf mehr), gewinnt das Match.
-- Flaggen-Regeln stehen in Objectives/Domination, der Rest in TeamRoundMode.

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)
local Domination = require(script.Parent.Parent.Objectives.Domination)

return TeamRoundMode.new({
	Id = "Domination",
	Maps = { "Domination" }, -- Map "Kraftwerk" (auch für Team Deathmatch, eigene Kopie)
	TeamSize = 5,
	Teams = {
		{ Name = "Rot", Color = BrickColor.new("Burgundy") },
		{ Name = "Blau", Color = BrickColor.new("Storm blue") },
	},
	DropIn = false,
	GroundStart = 5, -- Start am Team-Spawn mit 5 Sekunden Countdown (kein Absprung)
	Respawn = true,
	RoundsSetting = "DominationRounds",
	RoundTime = "DominationRoundTime",
	Objective = Domination,
})

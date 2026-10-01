-- Drop (ModuleScript, nur Server)
-- 5v5: Alle springen zu Rundenbeginn über ihrer Seite der Map ab, kein Respawn in der Runde.
-- Das Team, das alle Gegner ausschaltet (tot oder am Boden), gewinnt die Runde.
-- Ablauf, Agentenwahl, Kaufphase usw. stehen in TeamRoundMode.

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)

return TeamRoundMode.new({
	Id = "Drop",
	TeamSize = 5,
	Teams = {
		{ Name = "Rot", Color = BrickColor.new("Bright red") },
		{ Name = "Blau", Color = BrickColor.new("Bright blue") },
	},
	DropIn = true,
	RoundsSetting = "RoundsToWin",
})

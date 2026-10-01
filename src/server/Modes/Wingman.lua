-- Wingman (ModuleScript, nur Server)
-- 2v2-Variante von Strikeout: wenige Respawn-Tickets, gleicher Punkt in der Mitte
-- (3 s einnehmen, Halter zieht dem Gegner Tickets ab). Eigene Kopie der Fabrik-Map.

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)

return TeamRoundMode.new({
	Id = "Wingman",
	MapName = "Wingman",
	TeamSize = 2,
	Teams = {
		{ Name = "Alpha", Color = BrickColor.new("Sea green") },
		{ Name = "Bravo", Color = BrickColor.new("Bright yellow") },
	},
	DropIn = false,
	RoundsSetting = "WingmanRoundsToWin",
	Tickets = "WingmanTickets",
	Capture = { UnlockAfter = 15, Radius = 12 },
	RoundTime = "WingmanRoundTime",
})

-- Strikeout (ModuleScript, nur Server)
-- 4v4 mit Respawn-Tickets: Jedes Team hat pro Runde StrikeoutTickets Respawns.
-- Runde gewinnt, wer den Punkt in der Mitte einnimmt (öffnet nach 30 s) oder
-- dem Gegner alle Tickets abnimmt und ihn ausschaltet.
-- Ablauf, Agentenwahl, Kaufphase usw. stehen in TeamRoundMode.

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)

return TeamRoundMode.new({
	Id = "Strikeout",
	MapName = "Strikeout",
	TeamSize = 4,
	Teams = {
		{ Name = "Gold", Color = BrickColor.new("Deep orange") },
		{ Name = "Lila", Color = BrickColor.new("Bright violet") },
	},
	DropIn = false,
	RoundsSetting = "StrikeoutRoundsToWin",
	Tickets = "StrikeoutTickets",
	Capture = { UnlockAfter = 30, Radius = 12 },
})

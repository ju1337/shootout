-- Strikeout (ModuleScript, nur Server)
-- 4v4 mit Respawn-Tickets: Jedes Team hat pro Runde StrikeoutTickets Respawns.
-- Punkt in der Mitte (öffnet nach 20 s): 3 s allein draufstehen nimmt ihn ein, der Halter
-- zieht dem Gegner alle 30 s ein Ticket ab. Runde gewinnt, wer den Gegner ohne Tickets
-- ausschaltet; nach 5 Minuten gewinnt das Team mit mehr Tickets.
-- Ablauf, Agentenwahl, Kaufphase usw. stehen in TeamRoundMode.

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)

return TeamRoundMode.new({
	Id = "Strikeout",
	Maps = { "Strikeout", "Zellenblock", "Kanaele", "Windmuehlen" }, -- Map-Rotation: Fabrik, Zellenblock, Kanäle, Windmühlen
	TeamSize = 4,
	Teams = {
		{ Name = "Gold", Color = BrickColor.new("Deep orange") },
		{ Name = "Lila", Color = BrickColor.new("Bright violet") },
	},
	DropIn = false,
	WingsuitStart = 120, -- Fallschirmsprung zu Rundenbeginn
	RoundsSetting = "StrikeoutRoundsToWin",
	Tickets = "StrikeoutTickets",
	Capture = { UnlockAfter = 20, Radius = 12 },
	RoundTime = "StrikeoutRoundTime",
})

-- TeamDeathmatch (ModuleScript, nur Server)
-- 4v4 mit Respawn: Jedes Team hat TDMTickets Leben. Wer dem Gegner alle Leben abnimmt
-- (und alle ausschaltet), gewinnt. Nach Ablauf der Zeit gewinnt das Team mit mehr Leben.
-- Ein Match = eine lange Runde (TDMRounds = 1).

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)

return TeamRoundMode.new({
	Id = "TeamDeathmatch",
	MapName = "TDM",
	TeamSize = 4,
	Teams = {
		{ Name = "Kobra", Color = BrickColor.new("Lime green") },
		{ Name = "Adler", Color = BrickColor.new("Deep orange") },
	},
	DropIn = false,
	WingsuitStart = 120,
	RoundsSetting = "TDMRounds",
	Tickets = "TDMTickets",
	RoundTime = "TDMRoundTime",
})

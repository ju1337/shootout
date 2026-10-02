-- TeamDeathmatch (ModuleScript, nur Server)
-- 5v5 mit Respawn: Jedes Team hat TDMTickets Leben. Wer dem Gegner alle Leben abnimmt
-- (und alle ausschaltet), gewinnt. Nach Ablauf der Zeit gewinnt das Team mit mehr Leben.
-- Ein Match = eine lange Runde (TDMRounds = 1). Map "Kraftwerk" wie Herrschaft (eigene Kopie ohne Flaggen).

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)

return TeamRoundMode.new({
	Id = "TeamDeathmatch",
	Maps = { "TDM" }, -- Map "Kraftwerk" (zum Wiedereinbauen: build_kraftwerk(TDM_ORIGIN, "TDM.model.json", flags=False))
	TeamSize = 5,
	Teams = {
		{ Name = "Kobra", Color = BrickColor.new("Grime") },
		{ Name = "Adler", Color = BrickColor.new("Brown") },
	},
	DropIn = false,
	GroundStart = 5, -- Start am Team-Spawn mit 5 Sekunden Countdown (kein Absprung)
	RoundsSetting = "TDMRounds",
	Tickets = "TDMTickets",
	RoundTime = "TDMRoundTime",
})

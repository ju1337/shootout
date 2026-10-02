-- Arena (ModuleScript, nur Server)
-- 1v1-Duell: ein Leben pro Runde (kein Niederschlagen, es gibt ja keinen Teamkollegen),
-- Agentenwahl + Kaufphase wie in den anderen Team-Modi, ArenaRoundsToWin Siege gewinnen.

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)

return TeamRoundMode.new({
	Id = "Arena",
	MapName = "Arena",
	TeamSize = 1,
	Teams = {
		{ Name = "Links", Color = BrickColor.new("Rust") },
		{ Name = "Rechts", Color = BrickColor.new("Sand blue") },
	},
	DropIn = false,
	RoundsSetting = "ArenaRoundsToWin",
})

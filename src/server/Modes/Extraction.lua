-- Extraction (ModuleScript, nur Server)
-- 4v4, ein Leben pro Runde: Angreifer hacken Ziel A oder B, Verteidiger stören. Seitenwechsel
-- zur Halbzeit. Hack-Regeln in Objectives/Hack, der Rest in TeamRoundMode.

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)
local Hack = require(script.Parent.Parent.Objectives.Hack)

return TeamRoundMode.new({
	Id = "Extraction",
	Maps = { "Extraktion", "Windmuehlen3" }, -- Map-Rotation: Gletscher, Windmühlen
	TeamSize = 4,
	Teams = {
		{ Name = "Falke", Color = BrickColor.new("Steel blue") },
		{ Name = "Wolf", Color = BrickColor.new("Dusty Rose") },
	},
	DropIn = false,
	WingsuitStart = 120,
	RoundsSetting = "ExtractionRoundsToWin",
	RoundTime = "ExtractionRoundTime",
	Objective = Hack,
})

-- Demolition (ModuleScript, nur Server)
-- 4v4, ein Leben pro Runde (Niederschlagen + Wiederbeleben gilt). Angreifer legen die Bombe
-- bei A oder B, Verteidiger verhindern das oder entschärfen. Seitenwechsel zur Halbzeit.
-- Bomben-Regeln stehen in Objectives/Bomb, der Rest in TeamRoundMode.

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)
local Bomb = require(script.Parent.Parent.Objectives.Bomb)

return TeamRoundMode.new({
	Id = "Demolition",
	Maps = { "Demolition", "Gletscher", "Kanaele2" }, -- Map-Rotation: Hafen, Gletscher, Kanäle
	TeamSize = 4,
	Teams = {
		{ Name = "Nord", Color = BrickColor.new("Cyan") },
		{ Name = "Süd", Color = BrickColor.new("Magenta") },
	},
	DropIn = false,
	WingsuitStart = 120, -- Fallschirmsprung zu Rundenbeginn
	RoundsSetting = "DemolitionRoundsToWin",
	RoundTime = "DemolitionRoundTime",
	Objective = Bomb,
})

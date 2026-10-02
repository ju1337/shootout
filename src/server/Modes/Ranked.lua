-- Ranked (ModuleScript, nur Server)
-- Gewertetes Demolition: gleiche Regeln (Bombe, ein Leben, Seitenwechsel), aber am Match-Ende
-- gibt es Rangpunkte (RankConfig). Eigene Kopie der Hafen-Map.

local TeamRoundMode = require(script.Parent.Parent.TeamRoundMode)
local Bomb = require(script.Parent.Parent.Objectives.Bomb)

return TeamRoundMode.new({
	Id = "Ranked",
	MapName = "Ranked",
	TeamSize = 4,
	Teams = {
		{ Name = "Elite", Color = BrickColor.new("Gold") },
		{ Name = "Vanguard", Color = BrickColor.new("Royal blue") },
	},
	DropIn = false,
	WingsuitStart = 120, -- Fallschirmsprung zu Rundenbeginn
	RoundsSetting = "RankedRoundsToWin",
	RoundTime = "DemolitionRoundTime",
	Objective = Bomb,
	Ranked = true,
	RequiredLevel = 10, -- Summe aller Agenten-Level (Start: 7)
})

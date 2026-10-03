local Modes = require("Modes")
local failures = 0
local function check(cond, msg) if not cond then failures += 1 print("FEHLER: " .. msg) end end
check(Modes.GoalText("Domination", nil, false) == "HALTE DIE FLAGGEN", "Herrschaft")
check(Modes.GoalText("Wingman", nil, false) == "NIMM DEN PUNKT EIN", "Wingman")
check(Modes.GoalText("Arena", nil, false) == "GEWINNE DAS DUELL", "Arena")
check(Modes.GoalText("FreeForAll", nil, false) == "JEDER GEGEN JEDEN", "FFA")
check(Modes.GoalText("Training", nil, false) == nil, "Training ohne Ziel")
check(Modes.GoalText("Unbekannt", nil, false) == nil, "unbekannter Modus")
check(Modes.IsTeamMode("Domination") and Modes.IsTeamMode("Wingman") and not Modes.IsTeamMode("FreeForAll"), "Team-Modi")
for _, mode in Modes.List do
	for _, objective in mode.Objectives or {} do
		check(type(objective.Part) == "string" and type(objective.Label) == "string", mode.Id .. " Ziel unvollständig")
	end
end
print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

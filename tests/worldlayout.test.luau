-- WorldLayout: Grundriss der Weltkarte übersteht Kodieren und Lesen (Server -> Karten-Attribut -> Client)
local WorldLayout = require("WorldLayout")
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local list = {
	{ Group = "Roads", Name = "Road", X = -120.04, Z = -6012.5, W = 24, D = 310.26, Rotation = -33.333 },
	{ Group = "Ground", Name = "CampPad", X = 0, Z = -6000, W = 180, D = 180, Rotation = 0 },
	{ Group = "Buildings", Name = "Roof", X = 512.5, Z = -5480.75, W = 40.5, D = 22, Rotation = 90 },
}
local back = WorldLayout.Decode(WorldLayout.Encode(list))
check(#back == #list, "Anzahl " .. #back)
for i, entry in list do
	local got = back[i]
	check(got ~= nil and got.Group == entry.Group and got.Name == entry.Name, "Gruppe/Name " .. i)
	for _, key in { "X", "Z", "W", "D", "Rotation" } do
		check(got ~= nil and math.abs(got[key] - entry[key]) <= 0.051, string.format("%s von %d: %s", key, i, tostring(got and got[key])))
	end
end
check(#WorldLayout.Decode(nil) == 0 and #WorldLayout.Decode("") == 0, "leeres Attribut")
check(#WorldLayout.Decode("Roads,Road,1,2;kaputt") == 0, "kaputte Einträge werden übersprungen")
print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

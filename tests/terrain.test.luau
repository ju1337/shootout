-- Gelände der offenen Welt (ExtinctionTerrain): Höhenfeld stimmt mit dem der Karte überein (Werte aus tools/extinction_terrain.py),
-- ebene Orte, Seen mit Wasser, Berg am Rand; ein Block Voxel hat die richtigen Maße, Material und Füllung; das ganze Terrain
-- wird in Blöcken geschrieben und deckt die Welt lückenlos ab
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, tolerance)
	return math.abs(a - b) <= tolerance
end

local ExtinctionTerrain = require("ExtinctionTerrain")

-- Werte aus dem Python-Höhenfeld (Catmull-Rom über das 16-Stud-Raster), Abweichung nur durch die Speicherung (< 0,03)
local expected = {
	{ -640, -170, -11.901 }, { -720, -560, 34.45 }, { 250, 700, -9.851 }, { 123.4, -456.7, -0.4 },
	{ -800.2, 311.1, 4.13 }, { 660, 300, -0.4 }, { 310, 0, -0.4 }, { 0, 0, -0.4 }, { 500, -700, -0.834 }, { -850, 850, 7.774 },
}
for _, row in expected do
	local h = ExtinctionTerrain.Height(row[1], row[2])
	check(near(h, row[3], 0.06), string.format("Höhe bei (%g, %g): %.3f, erwartet %.3f", row[1], row[2], h, row[3]))
end

check(ExtinctionTerrain.IsWater(-640, -170) and ExtinctionTerrain.IsWater(250, 700), "Seen sind Wasser")
check(not ExtinctionTerrain.IsWater(0, 0) and not ExtinctionTerrain.IsWater(310, 0) and not ExtinctionTerrain.IsWater(-720, -560),
	"Camp, Ödstadt und Funkturm sind trocken")
check(near(ExtinctionTerrain.Height(0, 0), ExtinctionTerrain.FlatLevel, 0.05), "Camp liegt auf ebener Höhe")
check(ExtinctionTerrain.Height(-720, -560) > 25, "Funkturm steht auf einem Hügel")

-- Rand der Welt: Straßen führen als ebene Schneise hinaus, daneben steigt der Berg
check(near(ExtinctionTerrain.Height(0, 880), ExtinctionTerrain.FlatLevel, 0.3), "Straße bleibt am Rand eben")
local mountain = 0
for t = -800, 800, 100 do
	mountain = math.max(mountain, ExtinctionTerrain.Height(t, 1100), ExtinctionTerrain.Height(1100, t))
end
check(mountain > 25, "hinter dem Spielfeld steigt Gelände an (" .. mountain .. ")")

-- Block: 8 x 8 Voxel um die Mitte
local materials, occupancy = ExtinctionTerrain.BuildChunk(-16, -16, 8, 8)
local ny = (#materials[1])
check(#materials == 8 and #materials[1][1] == 8 and ny == 20, "Block hat 8 x 20 x 8 Voxel (" .. #materials .. " x " .. ny .. ")")
local ground = ExtinctionTerrain.YMin
local flatCell = math.floor((ExtinctionTerrain.FlatLevel - ground) / 4) + 1 -- Voxel, in dem die Oberfläche liegt
check(occupancy[1][flatCell - 1][1] == 1, "unter der Oberfläche voll")
check(near(occupancy[1][flatCell][1], 0.9, 0.05), "oberster Voxel teilweise gefüllt (" .. occupancy[1][flatCell][1] .. ")")
check(occupancy[1][flatCell + 1][1] == 0 and materials[1][flatCell + 1][1] == Enum.Material.Air, "darüber Luft")
check(materials[1][flatCell][1] ~= Enum.Material.Water, "kein Wasser im Camp")

-- See: Wasser über dem Becken, Sand/Schlamm darunter
local lakeMaterials, lakeOccupancy = ExtinctionTerrain.BuildChunk(-644, -172, 4, 4)
local waterCell = math.floor((ExtinctionTerrain.WaterLevel - 0.5 - ground) / 4) + 1
check(lakeMaterials[2][waterCell][2] == Enum.Material.Water and lakeOccupancy[2][waterCell][2] > 0, "im See steht Wasser")
check(lakeMaterials[2][1][2] ~= Enum.Material.Water and lakeOccupancy[2][1][2] == 1, "unten im See Boden")

-- Das ganze Terrain schreiben: Blöcke ohne Lücken, jeder Block 4-Stud-Voxel ausgerichtet
local columns, blocks = 0, 0
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
local ok, count = ExtinctionTerrain.Generate(nil, Vector3.new(0, 0, -6000), {
	Yield = false,
	Write = function(origin, mats, occ, nx, nyy, nz)
		blocks += 1
		columns += nx * nz
		check(origin.X % 4 == 0 and origin.Z % 4 == 0 and origin.Y == ground, "Block liegt auf dem 4-Stud-Raster")
		check(#mats == nx and #occ == nx and #mats[1] == nyy and #mats[1][1] == nz, "Block hat die gemeldeten Maße")
		minX, maxX = math.min(minX, origin.X), math.max(maxX, origin.X + nx * 4)
		minZ, maxZ = math.min(minZ, origin.Z), math.max(maxZ, origin.Z + nz * 4)
	end,
})
check(ok == true and count == blocks and blocks > 100, "Generate schreibt alle Blöcke (" .. tostring(blocks) .. ")")
check(columns == 560 * 560, "jede Säule genau einmal (" .. columns .. ")")
check(minX == -1120 and maxX == 1120 and minZ == -7120 and maxZ == -4880, "deckt die ganze Welt ab")

-- Ohne Terrain-Objekt (Test/Fehler): nichts geschrieben, kein Absturz
check(ExtinctionTerrain.Generate(nil, Vector3.new(0, 0, 0)) == false, "ohne Terrain wird nichts geschrieben")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

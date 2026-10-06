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
	{ -760, 230, -11.863 }, { -560, -760, 53.469 }, { 0, 0, -0.400 }, { 123.4, -456.7, -0.400 }, { -900.2, -311.1, 0.624 },
	{ 330, 320, -0.400 }, { 1130, -1030, -0.400 }, { -250, 1150, -0.400 }, { 1300, 300, -0.345 }, { -1500, 1500, -0.607 },
}
for _, row in expected do
	local h = ExtinctionTerrain.Height(row[1], row[2])
	check(near(h, row[3], 0.06), string.format("Höhe bei (%g, %g): %.3f, erwartet %.3f", row[1], row[2], h, row[3]))
end

check(ExtinctionTerrain.IsWater(-760, 230) and ExtinctionTerrain.IsWater(1380, -1280), "Schwarzsee und Stausee sind Wasser")
check(not ExtinctionTerrain.IsWater(0, 0) and not ExtinctionTerrain.IsWater(330, 320) and not ExtinctionTerrain.IsWater(-560, -760),
	"Camp, Stadt und Funkturm sind trocken")
for _, p in { { 0, 0 }, { 350, -300 }, { -400, 200 }, { -250, 1150 }, { 1150, 520 }, { -1150, -250 }, { 430, -1150 } } do
	check(math.abs(ExtinctionTerrain.Height(p[1], p[2]) - ExtinctionTerrain.FlatLevel) < 0.05, "Ort eben bei " .. p[1] .. ", " .. p[2])
end
check(near(ExtinctionTerrain.Height(0, 0), ExtinctionTerrain.FlatLevel, 0.05), "Camp liegt auf ebener Höhe")
check(ExtinctionTerrain.Height(-560, -760) > 25, "Funkturm steht auf einem Hügel")
check(ExtinctionTerrain.Height(-1380, 820) > 30 and ExtinctionTerrain.Height(1400, 100) > 30, "Außenposten stehen auf Hügeln")

-- Rand der Welt: Straßen führen als ebene Schneise hinaus, daneben steigt der Berg
check(near(ExtinctionTerrain.Height(-60, 800), ExtinctionTerrain.FlatLevel, 0.4), "Landstraße nach Norden ist eben")
local mountain = 0
for t = -1500, 1500, 100 do
	mountain = math.max(mountain, ExtinctionTerrain.Height(t, 1800), ExtinctionTerrain.Height(1800, t))
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
local townMaterial = materials[1][flatCell][1]
check(townMaterial == Enum.Material.Ground or townMaterial == Enum.Material.Mud or townMaterial == Enum.Material.LeafyGrass,
	"Stadt: Erde, Matsch oder Gras statt Pflaster (" .. tostring(townMaterial) .. ")")

-- See: Wasser über dem Becken, Sand/Schlamm darunter
local lakeMaterials, lakeOccupancy = ExtinctionTerrain.BuildChunk(-764, 228, 4, 4)
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
check(columns == 960 * 960, "jede Säule genau einmal (" .. columns .. ")")
check(minX == -1920 and maxX == 1920 and minZ == -7920 and maxZ == -4080, "deckt die ganze Welt ab")

-- Ohne Terrain-Objekt (Test/Fehler): nichts geschrieben, kein Absturz
check(ExtinctionTerrain.Generate(nil, Vector3.new(0, 0, 0)) == false, "ohne Terrain wird nichts geschrieben")

-- Straßen freiräumen: Körper mit Erde, darüber Luft; Hochstraße (weit über dem Boden) bleibt
do
	local fills = {}
	local fake = { FillBlock = function(_, cframe, size, material)
		table.insert(fills, { CFrame = cframe, Size = size, Material = material })
	end }
	local map = Instance.new("Model")
	local roads = Instance.new("Folder", map)
	roads.Name = "Roads"
	local road = Instance.new("Part", roads)
	road.Name = "Road"
	road.Size = Vector3.new(40, 3, 20)
	road.CFrame = CFrame.new(10, -1.25, -6000)
	local deck = Instance.new("Part", roads)
	deck.Name = "Road"
	deck.Size = Vector3.new(60, 2.4, 34)
	deck.CFrame = CFrame.new(10, 22.8, -5400)
	local line = Instance.new("Part", roads)
	line.Name = "CenterLine"
	line.Size = Vector3.new(30, 0.02, 0.5)
	line.CFrame = CFrame.new(10, 0.26, -6000)
	local count = ExtinctionTerrain.ClearRoads(fake, map, Vector3.new(0, 0, -6000), { Yield = false })
	check(count == 1 and #fills == 2, "nur das Straßenteil am Boden (" .. count .. ", " .. #fills .. ")")
	check(fills[1].Material == Enum.Material.Ground and fills[2].Material == Enum.Material.Air, "erst Erde, dann Luft")
	check(fills[2].CFrame.Position.Y - 6 > road.Position.Y + road.Size.Y / 2 - 0.01, "Luft beginnt an der Oberkante der Straße")
end

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

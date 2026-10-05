-- ExtinctionTerrain (ModuleScript, nur Server)
-- Gelände der offenen Welt (EXTINCTION): Hügel, Seen und der Bergrand. Das Höhenfeld steht fertig in
-- ExtinctionTerrainData (erzeugt von tools/build_maps.py, dasselbe Raster benutzt die Karte für Bäume, Felsen, Kisten).
--   Height(x, z)        Geländehöhe (x/z relativ zur Mitte der Welt, Catmull-Rom über das 16-Stud-Raster)
--   IsWater(x, z)       liegt die Stelle unter dem Wasserspiegel (Seen)?
--   Generate(terrain, center, options)  baut echtes Terrain (Voxel, 4 Studs) in Blöcken über mehrere Frames auf:
--                       Gras, Laub, Erde, Fels an Hängen, Sand am Ufer, Wasser in den Seen. Gibt true zurück, wenn
--                       alles geschrieben wurde. options = { Write = function(origin, materials, occupancy) } für Tests,
--                       { Yield = false } ohne Pausen zwischen den Blöcken.
-- Auf ebenen Flächen (Straßen, Orte) liegt das Terrain bei Data.Flat (-0,4); die Karte baut dort bei y = 0.
-- Ohne Terrain (z. B. Fehler beim Schreiben) bleibt der flache Boden der Karte stehen (Extinction hebt ihn dann nicht ab).

local Data = require(script.Parent.ExtinctionTerrainData)

local ExtinctionTerrain = {}

local CELL, HALF, POINTS = Data.Cell, Data.Half, Data.Points
local VOXEL = 4
local CHUNK = 40                -- Voxel pro Block und Achse (160 Studs)
local Y_MIN, Y_MAX = -16, 64    -- Höhenbereich, der geschrieben wird (Vielfache von VOXEL)
local WATER = Data.Water

local heights = nil -- [(i * POINTS) + j + 1], i = x-Index, j = z-Index

local function decode()
	if heights then
		return heights
	end
	local lookup = {}
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #chars do
		lookup[string.byte(chars, i)] = i - 1
	end
	local text = Data.Text
	local list = table.create(POINTS * POINTS)
	local span = Data.MaxHeight - Data.MinHeight
	for k = 1, POINTS * POINTS do
		local a, b = string.byte(text, 2 * k - 1, 2 * k)
		list[k] = Data.MinHeight + ((lookup[a] * 64 + lookup[b]) / 4095) * span
	end
	heights = list
	return list
end

local function cr(p0, p1, p2, p3, t)
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
end

function ExtinctionTerrain.Height(x, z)
	local list = decode()
	local fx = math.clamp((x + HALF) / CELL, 0, POINTS - 1.001)
	local fz = math.clamp((z + HALF) / CELL, 0, POINTS - 1.001)
	local i, j = math.floor(fx), math.floor(fz)
	local tx, tz = fx - i, fz - j
	local function at(a, b)
		return list[math.clamp(a, 0, POINTS - 1) * POINTS + math.clamp(b, 0, POINTS - 1) + 1]
	end
	local r1 = cr(at(i - 1, j - 1), at(i, j - 1), at(i + 1, j - 1), at(i + 2, j - 1), tx)
	local r2 = cr(at(i - 1, j), at(i, j), at(i + 1, j), at(i + 2, j), tx)
	local r3 = cr(at(i - 1, j + 1), at(i, j + 1), at(i + 1, j + 1), at(i + 2, j + 1), tx)
	local r4 = cr(at(i - 1, j + 2), at(i, j + 2), at(i + 1, j + 2), at(i + 2, j + 2), tx)
	return cr(r1, r2, r3, r4, tz)
end

function ExtinctionTerrain.IsWater(x, z)
	return ExtinctionTerrain.Height(x, z) < WATER
end

-- Oberfläche an einer Stelle: Material nach Höhe, Neigung und Wasser
local CITY = Data.City or 0

local function surfaceMaterial(x, z, h, slope)
	if CITY > 0 and math.abs(x) <= CITY and math.abs(z) <= CITY then
		return Enum.Material.Pavement -- Stadt: Pflaster unter Straßen und Gehwegen
	elseif h < WATER - 0.6 then
		return Enum.Material.Mud
	elseif h < WATER + 1.2 then
		return Enum.Material.Sand
	elseif slope > 0.62 or h > 30 then
		return Enum.Material.Rock
	elseif slope > 0.45 then
		return Enum.Material.Ground
	end
	local n = math.noise(x / 95, z / 95, 3.1)
	if n > 0.22 then
		return Enum.Material.Ground
	elseif n < -0.3 then
		return Enum.Material.LeafyGrass
	end
	return Enum.Material.Grass
end

-- Ein Block: x0/z0 = linke untere Ecke (relativ zur Mitte, Vielfaches von VOXEL), nx/nz Voxel.
-- Gibt materials[x][y][z] und occupancy[x][y][z] zurück (y von Y_MIN an).
function ExtinctionTerrain.BuildChunk(x0, z0, nx, nz)
	local ny = (Y_MAX - Y_MIN) // VOXEL
	local air = Enum.Material.Air
	local water = Enum.Material.Water
	local materials, occupancy = table.create(nx), table.create(nx)
	for ix = 1, nx do
		local mx, ox = table.create(ny), table.create(ny)
		for iy = 1, ny do
			mx[iy] = table.create(nz, air)
			ox[iy] = table.create(nz, 0)
		end
		local wx = x0 + (ix - 0.5) * VOXEL
		for iz = 1, nz do
			local wz = z0 + (iz - 0.5) * VOXEL
			local h = ExtinctionTerrain.Height(wx, wz)
			local gx = ExtinctionTerrain.Height(wx + 6, wz) - ExtinctionTerrain.Height(wx - 6, wz)
			local gz = ExtinctionTerrain.Height(wx, wz + 6) - ExtinctionTerrain.Height(wx, wz - 6)
			local slope = math.sqrt(gx * gx + gz * gz) / 12
			local material = surfaceMaterial(wx, wz, h, slope)
			local top = math.max(h, WATER)
			for iy = 1, ny do
				local bottom = Y_MIN + (iy - 1) * VOXEL
				if bottom >= top then
					break
				end
				local ground = math.clamp((h - bottom) / VOXEL, 0, 1)
				if ground >= 1 then
					mx[iy][iz] = material
					ox[iy][iz] = 1
				elseif h < WATER and ground < 0.5 then
					mx[iy][iz] = water
					ox[iy][iz] = math.clamp((WATER - bottom) / VOXEL, 0, 1)
				elseif ground > 0 then
					mx[iy][iz] = material
					ox[iy][iz] = ground
				end
			end
		end
		materials[ix], occupancy[ix] = mx, ox
	end
	return materials, occupancy
end

local function defaultWrite(terrain, origin, materials, occupancy, nx, ny, nz)
	local region = Region3.new(origin, origin + Vector3.new(nx * VOXEL, ny * VOXEL, nz * VOXEL))
	terrain:WriteVoxels(region, VOXEL, materials, occupancy)
end

-- Ganzes Terrain schreiben. center = Mitte der Welt (Weltkoordinaten).
function ExtinctionTerrain.Generate(terrain, center, options)
	options = options or {}
	if not options.Write and not (terrain and terrain.WriteVoxels) then
		return false
	end
	local ny = (Y_MAX - Y_MIN) // VOXEL
	local step = CHUNK * VOXEL
	local anchorX = math.floor(center.X / VOXEL) * VOXEL
	local anchorZ = math.floor(center.Z / VOXEL) * VOXEL
	local count = 0
	for x0 = -HALF, HALF - 1, step do
		for z0 = -HALF, HALF - 1, step do
			local nx = math.min(CHUNK, (HALF - x0) // VOXEL)
			local nz = math.min(CHUNK, (HALF - z0) // VOXEL)
			local materials, occupancy = ExtinctionTerrain.BuildChunk(x0, z0, nx, nz)
			local origin = Vector3.new(anchorX + x0, Y_MIN, anchorZ + z0)
			if options.Write then
				options.Write(origin, materials, occupancy, nx, ny, nz)
			else
				defaultWrite(terrain, origin, materials, occupancy, nx, ny, nz)
			end
			count += 1
			if options.Yield ~= false then
				task.wait()
			end
		end
	end
	return true, count
end

ExtinctionTerrain.Cell = CELL
ExtinctionTerrain.Half = HALF
ExtinctionTerrain.WaterLevel = WATER
ExtinctionTerrain.FlatLevel = Data.Flat
ExtinctionTerrain.YMin = Y_MIN

return ExtinctionTerrain

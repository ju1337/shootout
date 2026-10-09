-- DungeonLayout (ModuleScript)
-- Bauplan der Dungeon-Halle "Die Katakomben" (DungeonService baut sie je Gruppe, tools/dungeon_render.py zeichnet die
-- Draufsicht). Reine Daten ohne Roblox-Typen: Koordinaten relativ zur Halle (x quer, z längs, Boden der Haupthalle y = 0,
-- die Spieler stehen im Süden bei −z, die Zombies kommen von Norden und von den Seiten).
--
-- Aufbau von Süd nach Nord:
--   * LETZTE STELLUNG (Spieler): erhöhte Plattform (y = 3) in einer Nische, hinten das Portal (AUSGANG), vorn eine Brüstung
--     aus Sandsäcken und Brettern. Nur die Treppe in der Mitte führt hinunter – die Engstelle, an der die Wellen ankommen.
--     Feuerschalen, Vorratskisten, die Spawns der Spieler.
--   * KIRCHENSCHIFF (Haupthalle, 64 breit): zwei Säulenreihen (zwei Säulen eingestürzt, Schutt davor), in der Mitte ein
--     Brunnen mit giftgrünem Wasser und Nebel, Sarkophage als Deckung, Kronleuchter, Fackeln an den Wänden.
--   * SEITENGALERIEN (Ost und West): je drei Rundbögen ins Schiff (Engstellen), in den Außenwänden Grabnischen und zwei
--     Gruft-Gitter, ein drittes in der Nordecke; Sarkophage in der Mitte teilen die Galerie in zwei Gänge.
--   * GRUFT (Norden): hinter dem großen Tor in der Nordwand, mit offenen Särgen, rotem Licht und Nebel.
-- Zombies spawnen nur vor den Gittern (ZombieSpawns): sie müssen durch die Bögen bzw. das Tor ins Schiff und über die
-- Treppe hinauf – wer oben steht, hat Überblick, Deckung und das Portal im Rücken.
--
-- Teil: { N = Name, P = Mitte {x, y, z}, S = Größe, R = Drehung um y (Grad), RZ = Drehung um z (Grad), C = Farbe {r, g, b},
--   M = Material (Name aus Enum.Material), K = false (keine Kollision), T = Durchsichtigkeit, Shape = "Cylinder"/"Ball",
--   L = Licht { r, g, b, Reichweite, Helligkeit }, F = Feuer (Größe), Mist = Nebel { r, g, b }, Sign = { Text, Seite,
--   Farbe, Schrift } }

local DungeonLayout = {}

DungeonLayout.Name = "DIE KATAKOMBEN"
DungeonLayout.Height = 24
DungeonLayout.Bounds = { MinX = -66, MaxX = 66, MinZ = -64, MaxZ = 60 }
DungeonLayout.PlatformY = 3

local STONE = { 104, 98, 90 }
local DARK = { 64, 62, 60 }
local FLOOR = { 82, 78, 72 }
local NAVE = { 92, 86, 78 }
local WOOD = { 104, 76, 50 }
local SAND = { 150, 132, 96 }
local IRON = { 52, 52, 56 }
local BONE = { 214, 206, 184 }
local FIRE = { 255, 150, 60 }
local TOXIC = { 110, 230, 110 }
local BLOOD = { 230, 50, 40 }

function DungeonLayout.Build()
	local H = DungeonLayout.Height
	local PY = DungeonLayout.PlatformY
	local parts = {}
	local zombieSpawns = {}
	local playerSpawns = {}

	local function add(spec)
		table.insert(parts, spec)
		return spec
	end
	-- Quader mit Unterkante y0 und Höhe h
	local function block(name, x, z, sx, sz, y0, h, color, material, extra)
		local spec = { N = name, P = { x, y0 + h / 2, z }, S = { sx, h, sz }, C = color, M = material }
		for key, value in extra or {} do
			spec[key] = value
		end
		return add(spec)
	end
	-- Wand von (x1, z1) nach (x2, z2), nur achsparallel
	local function wall(name, x1, z1, x2, z2, thick, y0, h, color, material)
		local sx = math.abs(x2 - x1)
		local sz = math.abs(z2 - z1)
		return block(name, (x1 + x2) / 2, (z1 + z2) / 2, sx > 0 and sx or thick, sz > 0 and sz or thick, y0, h,
			color or STONE, material or "Slate")
	end
	-- Fackel an einer Wand (dir = Richtung in den Raum)
	local function torch(x, z, dirX, dirZ, y)
		y = y or 9
		block("TorchBracket", x, z, 0.6, 0.6, y - 1.2, 1.6, IRON, "Metal", { K = false })
		block("Torch", x + dirX * 0.7, z + dirZ * 0.7, 0.5, 0.5, y, 1.4, WOOD, "Wood", { K = false })
		block("TorchFlame", x + dirX * 0.7, z + dirZ * 0.7, 0.6, 0.6, y + 1.4, 0.8, FIRE, "Neon",
			{ K = false, L = { 255, 160, 80, 26, 1.4 }, F = 2 })
	end
	-- Gruft-Gitter in einer Wand: dunkles Loch, Stäbe, rote Lampe; Zombies spawnen 4 Studs davor (dir = in den Raum)
	local function grate(x, z, dirX, dirZ)
		local alongX = dirZ ~= 0 -- Wand verläuft in x-Richtung
		local w, d = alongX and 8 or 0.5, alongX and 0.5 or 8
		block("GrateHole", x + dirX * 0.4, z + dirZ * 0.4, w, d, 0, 10, { 8, 8, 10 }, "SmoothPlastic", { K = false })
		for k = -3, 3 do
			local ox, oz = alongX and k * 1.15 or 0, alongX and 0 or k * 1.15
			block("GrateBar", x + dirX * 0.9 + ox, z + dirZ * 0.9 + oz, 0.35, 0.35, 6, 4, IRON, "CorrodedMetal", { K = false })
		end
		block("GrateArch", x + dirX * 0.9, z + dirZ * 0.9, alongX and 9.4 or 1, alongX and 1 or 9.4, 10, 1.2, DARK, "Cobblestone")
		block("GrateLamp", x + dirX * 1.1, z + dirZ * 1.1, 0.8, 0.8, 11.6, 0.6, BLOOD, "Neon", { K = false, L = { 255, 60, 40, 16, 1.2 } })
		table.insert(zombieSpawns, { x + dirX * 4, 0, z + dirZ * 4 })
	end
	-- Sarkophag (Deckung, 2.6 hoch), along = "x" oder "z"
	local function sarcophagus(x, z, along, broken)
		local sx, sz = along == "x" and 7 or 3.2, along == "x" and 3.2 or 7
		block("Sarcophagus", x, z, sx, sz, 0, 2.2, STONE, "Limestone")
		if broken then
			block("SarcophagusLid", x + (along == "z" and 2.2 or 0), z + (along == "x" and 2.2 or 0), sx * 0.9, sz * 0.9, 0, 0.6,
				{ 120, 114, 104 }, "Limestone", { R = 12 })
		else
			block("SarcophagusLid", x, z, sx + 0.4, sz + 0.4, 2.2, 0.5, { 120, 114, 104 }, "Limestone")
		end
	end
	local function rubble(x, z, seed)
		local sizes = { { 3, 1.6, 2.4 }, { 2, 1.1, 2.6 }, { 1.6, 0.9, 1.4 }, { 2.6, 1.3, 1.8 } }
		for i, size in sizes do
			local angle = (i + seed) * 1.7
			block("Rubble", x + math.cos(angle) * 2.2, z + math.sin(angle) * 2.2, size[1], size[3], 0, size[2], DARK, "Rock",
				{ R = (i * 37 + seed * 13) % 90 })
		end
	end
	local function mist(x, y, z, color)
		block("Mist", x, z, 4, 4, y, 0.2, color or { 150, 160, 150 }, "SmoothPlastic",
			{ K = false, T = 1, Mist = color or { 150, 160, 150 } })
	end

	-- ---------- Hülle ----------
	block("Ground", 0, -2, 136, 128, -2, 2, FLOOR, "Cobblestone")
	block("Ceiling", 0, -2, 136, 128, H, 2, { 46, 44, 42 }, "Slate")
	wall("OuterWall", -65, -64, -65, 42, 2, 0, H)
	wall("OuterWall", 65, -64, 65, 42, 2, 0, H)
	wall("OuterWall", -66, -64, 66, -64, 2, 0, H)
	-- Nordwand mit großem Tor zur Gruft (x −5..5, 10 hoch)
	wall("NorthWall", -66, 41, -5, 41, 2, 0, H)
	wall("NorthWall", 5, 41, 66, 41, 2, 0, H)
	block("GateLintel", 0, 41, 10, 2, 10, H - 10, STONE, "Slate")
	block("GateArch", 0, 40, 12, 0.8, 9.4, 1.4, DARK, "Cobblestone")
	for k = -4, 4 do -- hochgezogenes Fallgitter
		block("Portcullis", k * 1.1, 41.6, 0.3, 0.3, 10.4, 6, IRON, "CorrodedMetal", { K = false })
	end
	-- Füllung der toten Ecken neben der Nische (damit nichts ins Leere schaut)
	block("Fill", -44, -51, 42, 26, 0, H, DARK, "Slate")
	block("Fill", 44, -51, 42, 26, 0, H, DARK, "Slate")

	-- ---------- Kirchenschiff: Wände zu den Galerien mit je drei Bögen ----------
	local arches = { { -22.5, -13.5 }, { -0.5, 8.5 }, { 21.5, 30.5 } }
	for _, side in { -1, 1 } do
		local x = side * 33.5
		local from = -38
		for _, arch in arches do
			wall("NaveWall", x, from, x, arch[1], 3, 0, H, NAVE, "Brick")
			block("ArchLintel", x, (arch[1] + arch[2]) / 2, 3, arch[2] - arch[1], 11, H - 11, NAVE, "Brick")
			block("ArchTrim", x, (arch[1] + arch[2]) / 2, 3.6, arch[2] - arch[1] + 1.2, 10.4, 1, DARK, "Cobblestone")
			from = arch[2]
		end
		wall("NaveWall", x, from, x, 40, 3, 0, H, NAVE, "Brick")
		-- Fackeln an den Pfeilern zwischen den Bögen (zum Schiff hin)
		for _, z in { -30, -7, 15, 36 } do
			torch(x - side * 1.8, z, -side, 0)
		end
	end
	-- Stirnwand des Schiffs (Süden) bis zur Nische
	wall("NaveFront", -35, -39, -23, -39, 2, 0, H, NAVE, "Brick")
	wall("NaveFront", 23, -39, 35, -39, 2, 0, H, NAVE, "Brick")
	block("AlcoveLintel", 0, -39, 46, 2, 16, H - 16, NAVE, "Brick")
	-- Galerien vorn abschließen
	wall("GalleryEnd", -64, -31, -35, -31, 2, 0, H)
	wall("GalleryEnd", 35, -31, 64, -31, 2, 0, H)

	-- ---------- Letzte Stellung (Spieler) ----------
	wall("AlcoveWall", -23, -63, -23, -38, 2, 0, H)
	wall("AlcoveWall", 23, -63, 23, -38, 2, 0, H)
	block("Platform", 0, -51, 44, 24, 0, PY, DARK, "Slate")
	block("PlatformEdge", 0, -39.3, 44, 0.8, PY - 0.2, 0.4, { 120, 114, 104 }, "Limestone")
	for i = 1, 6 do -- Treppe hinunter ins Schiff (die Engstelle), Stufen je 0.5 hoch
		block("Stair", 0, -39 + (i - 0.5), 16, 1, 0, PY - (i - 1) * PY / 6, DARK, "Slate")
	end
	-- Brüstung links und rechts der Treppe: Sandsäcke, darüber Bretter
	for _, side in { -1, 1 } do
		local cx = side * 15
		block("Sandbags", cx, -40, 14, 2.2, PY, 2, SAND, "Fabric")
		block("Sandbags", cx + side * 0.6, -40, 12, 1.8, PY + 2, 1.4, { 140, 122, 88 }, "Fabric")
		block("Plank", cx, -40.9, 13, 0.4, PY + 3.4, 0.9, WOOD, "WoodPlanks", { R = side * 3 })
		block("BarricadePost", side * 8.6, -40, 0.8, 0.8, PY, 4.4, WOOD, "Wood")
		-- Feuerschalen an den Ecken der Stellung
		block("BrazierStand", side * 19, -43, 1, 1, PY, 3, IRON, "Metal")
		block("Brazier", side * 19, -43, 2.6, 2.6, PY + 3, 0.9, IRON, "CorrodedMetal")
		block("Embers", side * 19, -43, 2, 2, PY + 3.9, 0.3, FIRE, "Neon", { K = false, L = { 255, 150, 70, 32, 2 }, F = 4 })
		-- Vorräte der Überlebenden
		block("Crate", side * 18, -57, 4, 4, PY, 4, WOOD, "WoodPlanks", { R = side * 8 })
		block("Crate", side * 18.5, -52.5, 3, 3, PY, 3, { 92, 70, 46 }, "WoodPlanks", { R = side * -14 })
		block("Bedroll", side * 12, -58.5, 3, 6, PY, 0.4, { 70, 84, 64 }, "Fabric")
	end
	-- Portal an der Rückwand: steinerner Rahmen, Feld, Schild AUSGANG
	local portalZ = -61.6
	for _, x in { -5.6, 5.6 } do
		block("PortalPillar", x, portalZ, 2, 2, PY, 14, STONE, "Limestone")
	end
	block("PortalTop", 0, portalZ, 13.2, 2, PY + 14, 2, STONE, "Limestone")
	add({ N = "PortalField", P = { 0, PY + 6.8, portalZ + 0.2 }, S = { 9.2, 13.4, 0.4 }, C = { 200, 40, 40 }, M = "Neon", K = false,
		T = 0.75, L = { 200, 40, 40, 18, 0.6 } })
	block("ExitSign", 0, portalZ + 0.6, 8, 0.3, PY + 16.4, 1.8, { 20, 22, 20 }, "Metal",
		{ Sign = { "AUSGANG", "Back", { 110, 230, 140 } } })
	for i, x in { -7.5, -2.5, 2.5, 7.5 } do
		playerSpawns[i] = { x, PY + 3, -49 }
	end

	-- ---------- Kirchenschiff: Säulen, Brunnen, Sarkophage, Licht ----------
	local broken = { ["-18,6"] = true, ["18,-10"] = true }
	for _, x in { -18, 18 } do
		for _, z in { -26, -10, 6, 22 } do
			block("ColumnBase", x, z, 6, 6, 0, 1.4, DARK, "Slate")
			if broken[x .. "," .. z] then
				block("Column", x, z, 4, 4, 1.4, 8, STONE, "Limestone")
				block("FallenDrum", x + (x < 0 and 5 or -5), z + 3, 3.4, 7, 0, 3.4, STONE, "Limestone", { R = 70 })
				rubble(x + (x < 0 and 3 or -3), z - 4, z)
			else
				block("Column", x, z, 4, 4, 1.4, H - 3.4, STONE, "Limestone")
				block("Capital", x, z, 5.6, 5.6, H - 2, 2, DARK, "Slate")
			end
		end
	end
	-- Brunnen in der Mitte: achteckiger Rand, giftgrünes Wasser, Nebel
	for i = 0, 7 do
		local angle = i * math.pi / 4
		block("WellRim", math.cos(angle) * 7.2, 8 + math.sin(angle) * 7.2, 6.2, 1.6, 0, 2.6, STONE, "Limestone",
			{ R = -math.deg(angle) + 90 })
	end
	add({ N = "WellWater", P = { 0, 1.2, 8 }, S = { 0.4, 13, 13 }, RZ = 90, Shape = "Cylinder", C = TOXIC, M = "Neon", T = 0.35, K = false,
		L = { 110, 230, 110, 30, 1.6 } })
	mist(0, 1.5, 8, { 120, 200, 120 })
	-- Sarkophage: Deckung vor der Treppe und am Nordende
	sarcophagus(-8, -22, "z")
	sarcophagus(8, -22, "z", true)
	sarcophagus(-8, 30, "x")
	sarcophagus(8, 30, "x", true)
	rubble(-26, 34, 3)
	rubble(25, -32, 5)
	-- Kronleuchter (Eisenringe mit Kerzen) über dem Schiff
	for _, z in { -24, 26 } do
		block("Chain", 0, z, 0.3, 0.3, H - 6, 6, IRON, "Metal", { K = false })
		add({ N = "Chandelier", P = { 0, H - 6.4, z }, S = { 0.6, 8, 8 }, RZ = 90, Shape = "Cylinder", C = IRON, M = "Metal", K = false })
		block("Candles", 0, z, 1.2, 1.2, H - 6, 0.6, { 255, 214, 150 }, "Neon", { K = false, L = { 255, 190, 120, 46, 1.5 } })
	end
	-- Graffiti der Überlebenden an der Stirnwand der Nische
	block("Graffiti", -29, -37.9, 10, 0.2, 9, 4, NAVE, "Brick", { K = false, T = 1,
		Sign = { "KEIN ZURÜCK", "Back", { 150, 24, 20 }, "PermanentMarker" } })

	-- ---------- Seitengalerien ----------
	for _, side in { -1, 1 } do
		local gx = side * 49
		-- Grabnischen in der Außenwand (Regale mit Knochen)
		for _, z in { -24, -2, 30 } do
			block("Niche", side * 63.6, z, 0.6, 9, 3, 9, { 30, 28, 26 }, "Slate", { K = false })
			for row = 0, 2 do
				block("NicheShelf", side * 63.2, z, 1.2, 9, 3 + row * 3, 0.4, DARK, "Slate", { K = false })
				block("Bones", side * 62.9, z + (row - 1) * 2, 0.8, 3, 3.4 + row * 3, 0.5, BONE, "Limestone", { K = false })
			end
		end
		-- Gruft-Gitter: zwei in der Außenwand, eines in der Nordecke
		grate(side * 64, -14, -side, 0)
		grate(side * 64, 18, -side, 0)
		grate(gx + side * 6, 40, 0, -1)
		-- Sarkophage in der Mitte: zwei Gänge
		sarcophagus(gx, -20, "z")
		sarcophagus(gx, 2, "z", true)
		sarcophagus(gx, 24, "z")
		rubble(gx - side * 8, 10, side > 0 and 7 or 2)
		-- fahles Licht: Grablaternen auf den Sarkophagen
		for _, z in { -20, 24 } do
			block("Lantern", gx, z, 0.8, 0.8, 2.7, 1.2, { 160, 220, 200 }, "Neon", { K = false, L = { 150, 210, 200, 28, 1 } })
		end
		torch(gx, -29.8, 0, 1)
		mist(gx, 0.3, -6)
		mist(gx, 0.3, 30)
	end

	-- ---------- Gruft hinter dem Tor ----------
	wall("CryptWall", -15, 42, -15, 59, 2, 0, 16, DARK)
	wall("CryptWall", 15, 42, 15, 59, 2, 0, 16, DARK)
	wall("CryptWall", -16, 59, 16, 59, 2, 0, 16, DARK)
	block("CryptCeiling", 0, 50.5, 32, 17, 16, 2, { 40, 38, 36 }, "Slate")
	for _, x in { -8, 8 } do
		block("OpenCoffin", x, 54, 3, 7, 0, 1.4, WOOD, "WoodPlanks")
		block("CoffinLid", x + (x < 0 and -2.6 or 2.6), 52, 2.8, 6.6, 0, 0.4, { 86, 62, 40 }, "WoodPlanks", { R = x < 0 and 20 or -20 })
	end
	block("CryptLight", 0, 57.6, 1, 0.6, 9, 1, BLOOD, "Neon", { K = false, L = { 255, 50, 40, 30, 1.6 } })
	mist(0, 0.3, 50, { 160, 110, 110 })
	table.insert(zombieSpawns, { -5, 0, 49 })
	table.insert(zombieSpawns, { 5, 0, 49 })

	return { Parts = parts, ZombieSpawns = zombieSpawns, PlayerSpawns = playerSpawns,
		Portal = { 0, PY + 6.8, portalZ + 0.2 } }
end

return DungeonLayout

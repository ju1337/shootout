-- MinimapShapes: Stücke liegen im Kreis und im Rechteck, und innerhalb des Kreises fehlt nichts
local MinimapShapes = require("MinimapShapes")
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		if failures <= 12 then
			print("FEHLER: " .. msg)
		end
	end
end

local seed = 12345
local function rand()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

-- Punkt im (gedrehten) Rechteck? (Mitte x/z, Breite w, Tiefe d, Drehung c/s)
local function inside(px, pz, x, z, w, d, c, s, eps)
	local dx, dz = px - x, pz - z
	local u = dx * c + dz * s
	local v = -dx * s + dz * c
	return math.abs(u) <= w / 2 + eps and math.abs(v) <= d / 2 + eps
end

local out = {}
local radius, strip = 75, 2
local pieces, maxPieces, cases, roundCases = 0, 0, 0, 0
for run = 1, 6000 do
	local px, pz = rand() * 200 - 100, rand() * 200 - 100
	local w = 0.5 + rand() ^ 2 * 160
	local d = 0.5 + rand() ^ 2 * 160
	if run > 4000 then
		-- große Flächen (Boden, Hallen) nahe am Spieler: runder Ausschnitt und breite Ränder
		w, d = 120 + rand() * 480, 120 + rand() * 480
		px, pz = rand() * 300 - 150, rand() * 300 - 150
	end
	local angle = rand() < 0.5 and 0 or (rand() * 360 - 180)
	local rect = MinimapShapes.Rect(rand() * 300 - 150, rand() * 300 - 150, w, d, angle)
	local n = MinimapShapes.Clip(rect, px, pz, radius, strip, out)
	if n == 1 and out[1].Round then
		roundCases += 1
	end
	cases += 1
	pieces += n
	maxPieces = math.max(maxPieces, n)
	for i = 1, n do
		local p = out[i]
		check(p.W > 0 and p.D > 0, "Stück ohne Fläche")
		if p.Round then
			-- runder Ausschnitt: genau der Kreis um den Spieler, nur wenn er ganz im Rechteck liegt
			check(n == 1 and math.abs(p.X - px) < 1e-9 and math.abs(p.Z - pz) < 1e-9 and math.abs(p.W - radius * 2) < 1e-9,
				"runder Ausschnitt falsch")
			for k = 0, 15 do
				local a = k / 16 * math.pi * 2
				check(inside(px + math.cos(a) * radius, pz + math.sin(a) * radius, rect.X, rect.Z, w, d, rect.C, rect.S, 1e-6),
					"runder Ausschnitt ragt aus dem Rechteck")
			end
			continue
		end
		check(p.D <= strip + 0.3 + 1e-9 or p.W <= strip + 0.3 + 1e-9 or n == 1, "Randstreifen zu breit")
		-- alle vier Ecken im Kreis und im Rechteck
		for _, corner in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
			local cu, cv = corner[1] * p.W / 2, corner[2] * p.D / 2
			local cx = p.X + rect.C * cu - rect.S * cv
			local cz = p.Z + rect.S * cu + rect.C * cv
			local dist = math.sqrt((cx - px) ^ 2 + (cz - pz) ^ 2)
			check(dist <= radius + 1e-6, string.format("Ecke außerhalb des Kreises (%.3f)", dist))
			check(inside(cx, cz, rect.X, rect.Z, w, d, rect.C, rect.S, 1e-6), "Ecke außerhalb des Rechtecks")
		end
	end
	-- Abdeckung: Punkte im Rechteck und sicher im Kreis müssen in einem Stück liegen,
	-- Punkte im Rechteck außerhalb des Kreises in keinem
	for _ = 1, 30 do
		local u, v = (rand() - 0.5) * w, (rand() - 0.5) * d
		local qx = rect.X + rect.C * u - rect.S * v
		local qz = rect.Z + rect.S * u + rect.C * v
		local dist = math.sqrt((qx - px) ^ 2 + (qz - pz) ^ 2)
		local covered = false
		for i = 1, n do
			local p = out[i]
			if p.Round and (qx - p.X) ^ 2 + (qz - p.Z) ^ 2 <= (p.W / 2) ^ 2 + 1e-9 then
				covered = true
				break
			elseif not p.Round and inside(qx, qz, p.X, p.Z, p.W, p.D, rect.C, rect.S, 1e-6) then
				covered = true
				break
			end
		end
		if dist <= radius - strip then
			check(covered, string.format("Lücke bei Abstand %.2f", dist))
		elseif dist > radius + 1e-6 then
			check(not covered, "Punkt außerhalb des Kreises gezeichnet")
		end
	end
end

-- Sonderfälle: ganz drin = Rechteck selbst, ganz draußen = nichts
local rect = MinimapShapes.Rect(10, 10, 4, 6, 30)
check(MinimapShapes.Clip(rect, 0, 0, 75, 2, out) == 1 and math.abs(out[1].W - 4) < 1e-9 and math.abs(out[1].D - 6) < 1e-9,
	"kleines Rechteck nahe der Mitte nicht unverändert")
check(MinimapShapes.Clip(MinimapShapes.Rect(200, 0, 10, 10, 0), 0, 0, 75, 2, out) == 0, "weit entferntes Rechteck gezeichnet")
-- Boden 150 x 100 um den Spieler (Schießstand): wie viele Streifen?
local ground = MinimapShapes.Clip(MinimapShapes.Rect(-1500, 1500, 150, 100, 0), -1545, 1500, 75, 2, out)
-- großer Boden unter dem Spieler: ein runder Ausschnitt statt vieler Streifen
local big = MinimapShapes.Clip(MinimapShapes.Rect(0, 0, 400, 400, 0), 10, -20, 75, 2, out)
check(big == 1 and out[1].Round == true, "großer Boden nicht als runder Ausschnitt")
local rounds = 0
print(string.format("%d Fälle (%d rund), Stücke im Schnitt %.1f, höchstens %d; Boden Schießstand: %d Streifen",
	cases, roundCases, pieces / cases, maxPieces, ground))
print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

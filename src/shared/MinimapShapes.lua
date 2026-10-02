-- MinimapShapes (ModuleScript)
-- Reine Geometrie für die Minimap, ohne Roblox-Objekte (darum mit Luau testbar):
-- schneidet die Rechtecke des Grundrisses auf den Kreis um den Spieler zu.
--   * ganz im Kreis      -> das Rechteck selbst
--   * ganz draußen       -> nichts
--   * Kreis ganz drin    -> ein runder Ausschnitt (Round = true), z.B. großer Boden unter dem Spieler
--   * über den Rand      -> Streifen entlang der langen Seite, jeder auf den Kreis gekürzt; benachbarte
--                           Streifen überlappen ein wenig, damit keine feinen Fugen zu sehen sind
-- So bleibt alles im Kreis, ohne CanvasGroup oder ClipsDescendants: Beide schneiden gedrehte
-- Inhalte nicht zuverlässig ab (die Minimap dreht sich mit der Blickrichtung).
-- Koordinaten: X und Z der Welt; Winkel in Grad wie GuiObject.Rotation (lokale X-Achse = (cos, sin)).

local MinimapShapes = {}

local OVERLAP = 0.3 -- Überlappung benachbarter Streifen (Studs)

-- Rechteck aus Mitte, Breite (lokale X-Achse), Tiefe (lokale Z-Achse) und Drehung in Grad
function MinimapShapes.Rect(x, z, width, depth, angle)
	local radians = math.rad(angle)
	local halfWidth, halfDepth = width / 2, depth / 2
	return {
		X = x,
		Z = z,
		HW = halfWidth,
		HD = halfDepth,
		C = math.cos(radians),
		S = math.sin(radians),
		Angle = angle,
		Reach = math.sqrt(halfWidth * halfWidth + halfDepth * halfDepth), -- Abstand Mitte -> Ecke
	}
end

local function put(out, index, x, z, width, depth, round)
	local piece = out[index]
	if piece then
		piece.X, piece.Z, piece.W, piece.D, piece.Round = x, z, width, depth, round
	else
		out[index] = { X = x, Z = z, W = width, D = depth, Round = round }
	end
end

-- Teile von rect, die im Kreis (Mitte px/pz, radius) liegen. strip = höchstens so breite Streifen am Rand.
-- Schreibt die Stücke { X, Z, W, D, Round } (Drehung = rect.Angle; Round = Kreis mit Durchmesser W)
-- nach out und gibt ihre Anzahl zurück.
function MinimapShapes.Clip(rect, px, pz, radius, strip, out)
	local dx, dz = px - rect.X, pz - rect.Z
	local reach = radius + rect.Reach
	if dx * dx + dz * dz > reach * reach then
		return 0 -- weit weg
	end
	-- Spieler in den Achsen des Rechtecks
	local lu = dx * rect.C + dz * rect.S
	local lv = -dx * rect.S + dz * rect.C
	local au, av = math.abs(lu), math.abs(lv)
	local nearU, nearV = math.max(au - rect.HW, 0), math.max(av - rect.HD, 0)
	if nearU * nearU + nearV * nearV >= radius * radius then
		return 0 -- ganz draußen
	end
	local farU, farV = au + rect.HW, av + rect.HD
	if farU * farU + farV * farV <= radius * radius then
		put(out, 1, rect.X, rect.Z, rect.HW * 2, rect.HD * 2, false)
		return 1 -- ganz drin
	end
	if au + radius <= rect.HW and av + radius <= rect.HD then
		put(out, 1, px, pz, radius * 2, radius * 2, true)
		return 1 -- deckt den ganzen Kreis ab
	end

	-- Am Rand: Streifen parallel zur langen Seite. Die Mittellinie wird auf radius - Streifenbreite/2 gekürzt,
	-- dann liegen auch die Ecken jedes Streifens sicher im Kreis.
	local alongU = rect.HW >= rect.HD
	local half = alongU and rect.HW or rect.HD
	local across = alongU and rect.HD or rect.HW
	local count = math.max(1, math.ceil(across * 2 / strip - 1e-6))
	local thickness = across * 2 / count
	local along = alongU and lu or lv
	local side = alongU and lv or lu
	local n = 0
	for i = 1, count do
		-- Streifen etwas breiter (Überlappung), aber nicht über das Rechteck hinaus
		local low = math.max(-across, -across + (i - 1) * thickness - OVERLAP / 2)
		local high = math.min(across, -across + i * thickness + OVERLAP / 2)
		local offset, width = (low + high) / 2, high - low
		local limit = radius - width / 2
		local rest = limit * limit - (offset - side) * (offset - side)
		if limit > 0 and rest > 0 then
			local h = math.sqrt(rest)
			local from, to = math.max(-half, along - h), math.min(half, along + h)
			if to - from > 0.05 then
				local mid = (from + to) / 2
				local cu, cv, w, d
				if alongU then
					cu, cv, w, d = mid, offset, to - from, width
				else
					cu, cv, w, d = offset, mid, width, to - from
				end
				n += 1
				put(out, n, rect.X + rect.C * cu - rect.S * cv, rect.Z + rect.S * cu + rect.C * cv, w, d, false)
			end
		end
	end
	return n
end

return MinimapShapes

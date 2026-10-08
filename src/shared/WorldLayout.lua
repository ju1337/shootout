-- WorldLayout (ModuleScript)
-- Grundriss der offenen Welt für die Weltkarte (ExtinctionMap): Flächen der Gruppe Ground, Dächer der Gruppe Buildings
-- und Straßen der Gruppe Roads als Rechtecke. Mit Streaming hat der Client nur die Teile in seiner Nähe, darum liest
-- der Server (der alle hat) den Grundriss beim Start und legt ihn kompakt als Karten-Attribut "Layout" ab.
-- Format: Einträge mit ";" getrennt, je "Gruppe,Name,X,Z,Breite,Tiefe,Drehung" (Grad um die Hochachse).

local WorldLayout = {}

-- Was die Weltkarte zeichnet: Gruppe -> Namen der Teile
WorldLayout.Drawn = {
	Ground = { Sidewalk = true, CampPad = true, Field = true },
	Buildings = { Roof = true, FallenRoof = true, Upper = true, Tower = true, TowerStub = true, PrisonWall = true },
	Roads = { Road = true },
}

local function round(value)
	return math.floor(value * 10 + 0.5) / 10
end

-- Ein Rechteck aus einem Teil (Drehung wie ExtinctionMap: Straßen liegen schräg)
function WorldLayout.FromPart(group, part)
	local right = part.CFrame.RightVector
	return { Group = group, Name = part.Name, X = part.Position.X, Z = part.Position.Z, W = part.Size.X, D = part.Size.Z,
		Rotation = math.deg(math.atan2(-right.Z, right.X)) }
end

-- Alle gezeichneten Teile einer Map (Server: vollständig; Client: nur, was gerade geladen ist)
function WorldLayout.Collect(map)
	local list = {}
	for group, names in WorldLayout.Drawn do
		local folder = map:FindFirstChild(group)
		for _, part in folder and folder:GetChildren() or {} do
			if part:IsA("BasePart") and names[part.Name] then
				table.insert(list, WorldLayout.FromPart(group, part))
			end
		end
	end
	return list
end

function WorldLayout.Encode(list)
	local out = table.create(#list)
	for i, entry in list do
		out[i] = string.format("%s,%s,%g,%g,%g,%g,%g", entry.Group, entry.Name, round(entry.X), round(entry.Z), round(entry.W),
			round(entry.D), round(entry.Rotation))
	end
	return table.concat(out, ";")
end

function WorldLayout.Decode(text)
	local list = {}
	if type(text) ~= "string" then
		return list
	end
	for entry in string.gmatch(text, "[^;]+") do
		local group, name, x, z, w, d, rotation = string.match(entry, "^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$")
		if group and tonumber(x) and tonumber(z) and tonumber(w) and tonumber(d) and tonumber(rotation) then
			table.insert(list, { Group = group, Name = name, X = tonumber(x), Z = tonumber(z), W = tonumber(w), D = tonumber(d),
				Rotation = tonumber(rotation) })
		end
	end
	return list
end

-- Server: Grundriss als Attribut an die Map hängen
function WorldLayout.Publish(map)
	map:SetAttribute("Layout", WorldLayout.Encode(WorldLayout.Collect(map)))
end

-- Client: Grundriss vom Server, sonst (ohne Attribut, z. B. in alten Places) aus den geladenen Teilen
function WorldLayout.Read(map)
	local text = map:GetAttribute("Layout")
	if type(text) == "string" and text ~= "" then
		return WorldLayout.Decode(text)
	end
	return WorldLayout.Collect(map)
end

return WorldLayout

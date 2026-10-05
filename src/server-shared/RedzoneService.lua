-- RedzoneService (ModuleScript, nur Server)
-- Rote Zonen der offenen Welt (EXTINCTION): gefährliche Gebiete mit besserer Beute. Die Karte legt sie als Teile
-- "Redzone_<Name>" in der Gruppe Redzones ab (Block, Breite = Durchmesser; nur die Lage und Größe zählen, die Optik baut die
-- Karte). Drinnen (ExtinctionConfig.Redzone):
--   * PvP gilt sofort (keine Wartezeit nach der Safe Zone),
--   * mehr Zombies um jeden Spieler (PerPlayerFactor) mit Läufern und Brocken, die innerhalb der Zone spawnen,
--   * Lagerkisten in der Zone ziehen aus Tier3 (ContainerService), Lootdrops landen bevorzugt dort (AirdropService).
-- Für die Clients steht die Liste als JSON im Attribut "Redzones" an der Karte: [{ Name, X, Z, R }].
-- Spieler-Attribut "Redzone" (Name der Zone oder nil) setzt der Modus (Modes/Extinction).

local HttpService = game:GetService("HttpService")

local RedzoneService = {}

local zones = {} -- { { Name, Center (Vector3), Radius, Title } }

-- map = Maps.Extinction (Gruppe Redzones mit Teilen Redzone_<Name>)
function RedzoneService.Init(map)
	zones = {}
	local folder = map:FindFirstChild("Redzones")
	for _, part in folder and folder:GetChildren() or {} do
		local name = string.match(part.Name, "^Redzone_(.+)$")
		if name and part:IsA("BasePart") then
			table.insert(zones, { Name = name, Title = part:GetAttribute("Title") or name, Center = part.Position, Radius = part.Size.X / 2 })
		end
	end
	table.sort(zones, function(a, b)
		return a.Name < b.Name
	end)
	local list = {}
	for _, zone in zones do
		table.insert(list, { Name = zone.Title, X = zone.Center.X, Z = zone.Center.Z, R = zone.Radius })
	end
	map:SetAttribute("Redzones", HttpService:JSONEncode(list))
end

-- Rote Zone an einer Stelle (flacher Abstand) oder nil
function RedzoneService.At(position)
	for _, zone in zones do
		if Vector3.new(position.X - zone.Center.X, 0, position.Z - zone.Center.Z).Magnitude <= zone.Radius then
			return zone
		end
	end
	return nil
end

function RedzoneService.List()
	return zones
end

-- Zufällige rote Zone (random = Random), nil ohne Zonen
function RedzoneService.Random(random)
	if #zones == 0 then
		return nil
	end
	return zones[(random or Random.new()):NextInteger(1, #zones)]
end

return RedzoneService

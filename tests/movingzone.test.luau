-- Wanderzone: Ziele aus den Orten der Karte (ohne Camp, große Flächen, Nähe zur Safe Zone, feste rote Zonen), Wechsel nach
-- Interval mit Ansage vorher, Attribut MovingZone für die Clients, Wand in der Welt, At liefert sie (PvP wie rote Zone)
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ExtinctionConfig = require("ExtinctionConfig")
local RedzoneService = require("RedzoneService")
local HttpService = game:GetService("HttpService")
local cfg = ExtinctionConfig.MovingZone

local map = Instance.new("Model", workspace)
map.Name = "Extinction"
for _, name in { "Redzones", "Places" } do
	Instance.new("Folder", map).Name = name
end
local function place(key, x, z, size)
	local p = Instance.new("Part", map.Places)
	p.Name = "Place_" .. key
	p:SetAttribute("Title", "Ort " .. key)
	p.Size = Vector3.new(size or 200, 4, size or 200)
	p.CFrame = CFrame.new(x, 2, z)
	return p
end
place("Camp", 0, 0, 280)        -- ausgeschlossen (Liste)
place("Nah", 150, 0)            -- zu nah an der Safe Zone
place("Riesig", 900, 900, 1480) -- zu groß
place("Rot", -800, 0)           -- liegt auf der festen roten Zone
place("Nord", 0, 900)
place("Ost", 900, 0)
place("See", 0, -900)           -- im Wasser
local red = Instance.new("Part", map.Redzones)
red.Name = "Redzone_Fest"
red.Size = Vector3.new(300, 40, 300)
red.CFrame = CFrame.new(-800, 20, 0)
RedzoneService.Init(map)

local players = {}
RedzoneService.StartMoving({
	Map = map,
	SafeCenter = function()
		return Vector3.new(0, 40, 0), 100
	end,
	IsWater = function(x, z)
		return z < -800
	end,
	GroundY = function()
		return 0
	end,
	Players = function()
		return players
	end,
	Random = Random.new(3),
	Loop = false,
})

local list = RedzoneService.MovingCandidates()
local keys = {}
for _, entry in list do
	table.insert(keys, entry.Key)
end
check(table.concat(keys, ",") == "Nord,Ost", "nur passende Orte als Ziel: " .. table.concat(keys, ","))

local zone = RedzoneService.Moving()
check(zone ~= nil and zone.Moving and zone.Radius == cfg.Radius, "Zone gesetzt")
check(zone.Key == "Nord" or zone.Key == "Ost", "Ziel aus der Liste")
local info = HttpService:JSONDecode(map:GetAttribute("MovingZone"))
check(info.X == zone.Center.X and info.Z == zone.Center.Z and info.R == cfg.Radius and info.Name == zone.Title, "Attribut für die Clients")
check(math.abs(info.Ends - (workspace:GetServerTimeNow() + cfg.Interval)) < 2, "Wechselzeit im Attribut")
check(RedzoneService.At(zone.Center + Vector3.new(cfg.Radius - 5, 0, 0)) == zone, "drinnen liefert At die Wanderzone")
check(RedzoneService.At(zone.Center + Vector3.new(cfg.Radius + 5, 0, 0)) == nil, "draußen nicht")
check(RedzoneService.At(red.Position) ~= nil and RedzoneService.At(red.Position).Name == "Fest", "feste rote Zone gilt weiter")
local folder = map:FindFirstChild("MovingZone")
local walls = 0
for _, child in folder and folder:GetChildren() or {} do
	if child.Name == "Wall" then
		walls += 1
		check(not child.CanCollide, "Wand ohne Kollision")
	end
end
check(walls == cfg.WallPanels, "Wand im Kreis (" .. walls .. ")")

-- Warnung und Wechsel
local first = zone.Key
local ok = pcall(function()
	SIM.Advance(cfg.Interval - cfg.Warning + 1, 1)
end)
check(ok, "Zeit vorspulen")
RedzoneService.StepMoving()
check(RedzoneService.Moving().Key == first and RedzoneService.Moving().Warned, "kurz vor dem Wechsel: Warnung, Ort bleibt")
SIM.Advance(cfg.Warning + 1, 1)
RedzoneService.StepMoving()
local second = RedzoneService.Moving()
check(second.Key ~= first, "nach Ablauf ein anderer Ort (" .. first .. " -> " .. second.Key .. ")")
check(HttpService:JSONDecode(map:GetAttribute("MovingZone")).X == second.Center.X, "Attribut zeigt den neuen Ort")
local count = 0
for _, child in map:GetChildren() do
	if child.Name == "MovingZone" then
		count += 1
	end
end
check(count == 1, "alte Wand weg, neue steht")

-- Ort erzwingen, Stopp
check(RedzoneService.MoveNow("Ost").Key == "Ost", "Ort erzwingen")
RedzoneService.StopMoving()
check(RedzoneService.Moving() == nil and map:GetAttribute("MovingZone") == nil and map:FindFirstChild("MovingZone") == nil, "gestoppt: alles weg")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

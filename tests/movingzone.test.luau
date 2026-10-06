-- Die rote Zone wandert: genau eine Zone, Ziele aus den Orten der Karte (ohne Camp, große Flächen, Nähe zur Safe Zone,
-- Safehouses, Wasser), Wechsel nach Interval mit Ansage vorher, nie derselbe Ort und möglichst weit weg (MinMove),
-- Attribut Redzones (Liste) für die Clients, rote Wand in der Welt, At liefert sie, OnMoved meldet jeden Wechsel
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
local cfg = ExtinctionConfig.Redzone

local map = Instance.new("Model", workspace)
map.Name = "Extinction"
Instance.new("Folder", map).Name = "Places"
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
place("Haus", -800, 0)          -- am Safehouse
place("Safe_West", -1100, 0)    -- das Safehouse selbst
place("Nord", 0, 900)
place("Ost", 900, 0)
place("Ostdorf", 1000, 150)     -- gleich neben Ost (weniger als MinMove)
place("See", 0, -900)           -- im Wasser

local players = {}
local events = {}
RedzoneService.OnMoved(function(zone)
	table.insert(events, zone or false)
end)
RedzoneService.Start({
	Map = map,
	SafeCenter = function()
		return Vector3.new(0, 40, 0), 100
	end,
	SafeZones = function()
		return { { Center = Vector3.new(-850, 0, 0), Radius = 60 } }
	end,
	IsWater = function(_, z)
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

local keys = {}
for _, entry in RedzoneService.Candidates() do
	table.insert(keys, entry.Key)
end
check(table.concat(keys, ",") == "Nord,Ost,Ostdorf", "nur passende Orte als Ziel: " .. table.concat(keys, ","))

local zone = RedzoneService.Current()
check(zone ~= nil and zone.Name == "Redzone" and zone.Radius == cfg.Radius, "eine rote Zone gesetzt")
check(zone and (zone.Key == "Nord" or zone.Key == "Ost" or zone.Key == "Ostdorf"), "Ziel aus der Liste")
check(#events == 1 and events[1] == zone, "OnMoved meldet die erste Zone")
check(#RedzoneService.List() == 1 and RedzoneService.List()[1] == zone and RedzoneService.Random() == zone, "List/Random: genau diese Zone")
local info = HttpService:JSONDecode(map:GetAttribute("Redzones"))
check(#info == 1 and info[1].X == zone.Center.X and info[1].Z == zone.Center.Z and info[1].R == cfg.Radius
	and info[1].Title == zone.Title and info[1].Name == "Redzone", "Attribut Redzones (Liste) für die Clients")
check(math.abs(info[1].Ends - (workspace:GetServerTimeNow() + cfg.Interval)) < 2, "Wechselzeit im Attribut")
check(RedzoneService.At(zone.Center + Vector3.new(cfg.Radius - 5, 0, 0)) == zone, "drinnen liefert At die Zone")
check(RedzoneService.At(zone.Center + Vector3.new(cfg.Radius + 5, 0, 0)) == nil, "draußen nicht")
check(RedzoneService.At(Vector3.new(-800, 0, 0)) == nil, "keine festen Zonen mehr")
local folder = map:FindFirstChild("RedzoneWall")
local walls = 0
for _, child in folder and folder:GetChildren() or {} do
	if child.Name == "Wall" then
		walls += 1
		check(not child.CanCollide and child.Color == cfg.Color, "Wand rot und ohne Kollision")
	end
end
check(walls == cfg.WallPanels, "Wand im Kreis (" .. walls .. ")")

-- Warnung und Wechsel: nach Ablauf ein anderer Ort, weit genug weg (Ost und Ostdorf liegen zu dicht beieinander)
check(RedzoneService.MoveNow("Ost").Key == "Ost", "Ort erzwingen")
local ok = pcall(function()
	SIM.Advance(cfg.Interval - cfg.Warning + 1, 1)
end)
check(ok, "Zeit vorspulen")
RedzoneService.Step()
check(RedzoneService.Current().Key == "Ost" and RedzoneService.Current().Warned, "kurz vor dem Wechsel: Warnung, Ort bleibt")
local before = #events
SIM.Advance(cfg.Warning + 1, 1)
RedzoneService.Step()
local second = RedzoneService.Current()
check(second.Key == "Nord", "nach Ablauf woanders und weit weg (Ost -> " .. second.Key .. ")")
check(#events == before + 1 and events[#events] == second, "OnMoved meldet den Wechsel")
check(HttpService:JSONDecode(map:GetAttribute("Redzones"))[1].X == second.Center.X, "Attribut zeigt den neuen Ort")
check(math.abs(second.Ends - (workspace:GetServerTimeNow() + cfg.Interval)) < 2, "neue Runde: wieder volle Zeit")
local count = 0
for _, child in map:GetChildren() do
	if child.Name == "RedzoneWall" then
		count += 1
	end
end
check(count == 1, "alte Wand weg, neue steht")
-- von Ost aus nie ins nahe Ostdorf (zu dicht dran), sondern immer nach Nord
for _ = 1, 20 do
	RedzoneService.MoveNow("Ost")
	check(RedzoneService.MoveNow().Key == "Nord", "von Ost aus immer weit weg")
end
-- von Nord aus sind Ost und Ostdorf weit genug weg: beide kommen vor, Nord nie zweimal hintereinander
local seen = {}
for _ = 1, 30 do
	RedzoneService.MoveNow("Nord")
	local key = RedzoneService.MoveNow().Key
	seen[key] = true
	check(key ~= "Nord", "nie zweimal derselbe Ort")
end
check(seen.Ost and seen.Ostdorf, "alle weit entfernten Orte kommen vor")
-- nur noch nahe Orte übrig: dann eben ein naher, aber nie derselbe
map.Places.Place_Nord:Destroy()
RedzoneService.MoveNow("Ost")
check(RedzoneService.MoveNow().Key == "Ostdorf", "ohne weiten Ort der nächstbeste andere")

-- Ansagen gehen an die Spieler draußen
local alice = SIM.Join("Alice")
players = { alice }
RedzoneService.MoveNow("Ost")
local banner = nil
for _, entry in SIM.RemoteLog do
	if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" then
		banner = entry.Args[2]
	end
end
check(banner ~= nil and banner.Caption == "Rote Zone" and banner.Title == "ROTE ZONE: ORT OST"
	and string.find(banner.Sub, "Rangliste neu", 1, true) ~= nil, "Ansage beim Wechsel")

-- Ohne Ziele: keine Zone; Stopp räumt alles weg
for _, part in map.Places:GetChildren() do
	part:Destroy()
end
check(RedzoneService.MoveNow() == nil and RedzoneService.Current() == nil and events[#events] == false, "ohne Ziel keine Zone")
check(#HttpService:JSONDecode(map:GetAttribute("Redzones")) == 0 and map:FindFirstChild("RedzoneWall") == nil, "Attribut leer, Wand weg")
place("Nord", 0, 900)
check(RedzoneService.MoveNow().Key == "Nord", "wieder ein Ziel")
RedzoneService.Stop()
check(RedzoneService.Current() == nil and #HttpService:JSONDecode(map:GetAttribute("Redzones")) == 0
	and map:FindFirstChild("RedzoneWall") == nil, "gestoppt: alles weg")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

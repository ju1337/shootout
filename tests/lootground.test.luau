--!expose LootService groundBelow
-- Taschen landen auf dem Boden unter dem Todesort: Bots, Zombies, Leichen, Fahrzeuge, andere Taschen und Teile ohne
-- Kollision zählen nicht als Boden; Tode im Fall hoch über dem Boden (mehr als 60 Studs) landen trotzdem unten.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ExtinctionConfig = require("ExtinctionConfig")
local LootService = require("LootService")

local function folder(name)
	local f = Instance.new("Folder", workspace)
	f.Name = name
	return f
end
local function slab(name, parent, y, collide)
	local part = Instance.new("Part", parent)
	part.Name = name
	part.CanCollide = collide ~= false
	part:SetAttribute("Top", y)
	return part
end

-- einfache Welt: waagerechte Platten (Oberkante = Attribut Top), der Strahl trifft die höchste darunter
local ground = slab("Ground", workspace, 0)
local bots = folder("Bots")
local bot = Instance.new("Model", bots)
Instance.new("Humanoid", bot)
local botTorso = slab("Torso", bot, 3)
local vehicles = folder("ExtinctionVehicles")
local carRoof = slab("Roof", vehicles, 6)
local leaves = slab("Leaves", workspace, 10, false)
local corpse = Instance.new("Model", workspace)
Instance.new("Humanoid", corpse)
local corpseArm = slab("Arm", corpse, 2)
local roof = slab("HouseRoof", workspace, 300)
roof:SetAttribute("Only", true) -- nur unter x = 500

local slabs = { ground, botTorso, carRoof, leaves, corpseArm, roof }
SIM.RaycastHandler = function(origin, direction, params)
	local best, bestY = nil, -math.huge
	for _, part in slabs do
		local y = part:GetAttribute("Top")
		local excluded = false
		for _, ignore in params.FilterDescendantsInstances do
			if part == ignore or part:IsDescendantOf(ignore) then
				excluded = true
			end
		end
		local reach = y <= origin.Y and y >= origin.Y + direction.Y
		local here = not part:GetAttribute("Only") or origin.X == 500
		if not excluded and reach and here and (part.CanCollide or not params.RespectCanCollide) and y > bestY then
			best, bestY = part, y
		end
	end
	return best and { Position = Vector3.new(origin.X, bestY, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = best,
		Material = Enum.Material.Grass } or nil
end

local groundBelow = LootService.__groundBelow
-- Tod im Sprung über Bot, Leiche, Auto und unter Blättern: landet auf dem Boden
local at = groundBelow(Vector3.new(0, 8, 0))
check(at and at.Y == 0, "Tasche liegt auf dem Boden, nicht auf Bot/Leiche/Auto (y=" .. tostring(at and at.Y) .. ")")
-- Tod im Fall 200 Studs über dem Boden
at = groundBelow(Vector3.new(0, 200, 0))
check(at and at.Y == 0, "Tod hoch in der Luft: Tasche fällt bis zum Boden (y=" .. tostring(at and at.Y) .. ")")
-- Tod auf einem Hausdach: bleibt auf dem Dach
at = groundBelow(Vector3.new(500, 303, 0))
check(at and at.Y == 300, "Tod auf dem Dach: Tasche liegt auf dem Dach (y=" .. tostring(at and at.Y) .. ")")

-- ganze Tasche: Modell steht auf dem Boden
local id = LootService.Create(Vector3.new(0, 120, 0), { { Id = "Bandage", Count = 1 } }, "Death", "TASCHE · Test")
local bag = id and LootService.Get(id)
check(bag ~= nil, "Tasche entsteht")
if bag then
	local bottom = bag.Part.Position.Y - bag.Part.Size.Y / 2
	check(math.abs(bottom) < 0.01, "Tasche steht auf dem Boden (Unterkante y=" .. bottom .. ")")
end
check(ExtinctionConfig.Get("Bandage") ~= nil, "Testgegenstand Bandage existiert")

if failures > 0 then
	error(failures .. " Prüfungen fehlgeschlagen")
end
print("lootground: alles ok")

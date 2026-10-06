-- ContainerService (ModuleScript, nur Server)
-- Lagerkisten in der offenen Welt (EXTINCTION): Die Karte legt Teile "Spot_<Art>" in die Gruppe Loot (Art = Wood, Toolbox,
-- Medical, Ammo, Military, siehe ExtinctionConfig.Containers). An jedem Spot steht eine Kiste (LootService, Art "Crate") mit
-- Beute aus der Tabelle der Art; E durchsucht sie, F nimmt alles. Ist sie leer, füllt sie sich nach Containers.Respawn
-- Sekunden (±20 %) neu. Liegt beim Füllen die rote Zone über dem Spot (sie zieht alle 20 Minuten weiter), zieht die Kiste
-- aus ExtinctionConfig.Redzone.ContainerTable (Tier3), Medical und Ammo behalten ihre Tabelle. Abschaltbar mit
-- ExtinctionConfig.Containers.Enabled = false (Standard: aus). Spots stehen auf dem Boden (die Karte rechnet die
-- Geländehöhe ein), darum keine Boden-Suche.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local LootService = require(script.Parent.LootService)

local ContainerService = {}

local C = ExtinctionConfig.Containers
local random = Random.new()
local options = nil -- { RedzoneAt(position) -> Zone | nil }
local spots = {}    -- { { Part, Kind, Position, Yaw, Id (aktuelle Kiste), Redzone (beim letzten Füllen in der roten Zone) } }

-- Tabelle für einen Spot: rote Zone zieht aus Tier3 (außer Sani- und Munitionskisten)
local function tableFor(spot)
	local kind = C.Kinds[spot.Kind]
	if spot.Redzone and spot.Kind ~= "Medical" and spot.Kind ~= "Ammo" then
		return ExtinctionConfig.Redzone.ContainerTable
	end
	return kind.Table
end

local function fill(spot)
	local kind = C.Kinds[spot.Kind]
	spot.Redzone = options.RedzoneAt ~= nil and options.RedzoneAt(spot.Position) ~= nil
	local items = ExtinctionConfig.RollLoot(tableFor(spot), random:NextInteger(kind.Items[1], kind.Items[2]), random)
	spot.Id = LootService.Create(spot.Position, items, "Crate", kind.Name, {
		Persist = true,
		SpotKind = spot.Kind,
		Size = kind.Size,
		Color = kind.Color,
		Yaw = spot.Yaw,
		NoGround = true,
		Meta = { Spot = spot },
	})
end

-- Alle Spots der Karte (Gruppe Loot) einlesen und füllen. opts = { RedzoneAt }.
function ContainerService.Init(map, opts)
	options = opts or {}
	spots = {}
	if C.Enabled == false then
		return -- abgeschaltet: keine Beute am Boden (ExtinctionConfig.Containers.Enabled)
	end
	local folder = map:FindFirstChild("Loot")
	for _, part in folder and folder:GetChildren() or {} do
		local kind = string.match(part.Name, "^Spot_([A-Za-z]+)")
		if kind and C.Kinds[kind] and part:IsA("BasePart") then
			local position = part.Position
			local ground = Vector3.new(position.X, position.Y - part.Size.Y / 2, position.Z)
			local _, yaw = part.CFrame:ToOrientation()
			table.insert(spots, { Part = part, Kind = kind, Position = ground, Yaw = yaw, Redzone = false })
		end
	end
	LootService.OnRemoved[#LootService.OnRemoved + 1] = function(bag)
		local spot = bag.Meta and bag.Meta.Spot
		if bag.Kind ~= "Crate" or not spot or spot.Id ~= bag.Id then
			return
		end
		spot.Id = nil
		task.delay(C.Respawn * random:NextNumber(0.8, 1.2), function()
			if not spot.Id then
				fill(spot)
			end
		end)
	end
	for _, spot in spots do
		fill(spot)
	end
end

function ContainerService.Spots()
	return spots
end

return ContainerService

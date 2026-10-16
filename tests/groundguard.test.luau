-- Bodenschutz (ExtinctionClient.GroundGuard): Der Server senkt den flachen Ersatzboden ab, sobald das Terrain gebaut ist.
-- Hat der Client das Terrain unter dem Spieler noch nicht, hebt er den Boden sofort lokal wieder an (noch im selben
-- Moment, in dem die Absenkung ankommt); ist man schon durchgefallen, kommt man zurück nach oben; ist das Terrain da,
-- senkt er ihn lokal wieder ab.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local Remotes = require("Remotes") -- als Server anlegen, dann Client
SIM.IsServer = false
local bob = SIM.Join("Bob")
rawget(SIM.Players, "__props").LocalPlayer = bob
bob:SetAttribute("Mode", "Extinction")
bob:LoadCharacter()
SIM.Advance(0.5, 10)
local _ = Remotes

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", CENTER)
local folder = Instance.new("Folder", map)
folder.Name = "Ground"
local ground = Instance.new("Part", folder)
ground.Name = "Ground"
ground.Size = Vector3.new(4000, 4, 4000)
ground.Position = CENTER + Vector3.new(0, -2, 0) -- Oberkante auf 0

-- Terrain: geladen oder (noch) nicht
local loaded = false
workspace.Terrain.ReadVoxels = function(_, region)
	local material = loaded and Enum.Material.Grass or Enum.Material.Air
	return { { { material } } }, { { { 1 } } }
end

local root = bob.Character.HumanoidRootPart
root.CFrame = CFrame.new(CENTER + Vector3.new(0, 3, 0))
local ExtinctionClient = require("ExtinctionClient")
task.spawn(ExtinctionClient.GroundGuard)
SIM.Advance(0.5, 10)

-- Server senkt ab, Terrain noch nicht da: sofort wieder hoch
ground.Position = CENTER + Vector3.new(0, -16, 0)
check(math.abs(ground.Position.Y - (CENTER.Y - 2)) < 0.01 and ground:GetAttribute("HeldLocally") == true,
	"Absenkung kommt an, Terrain fehlt: Boden sofort wieder oben (" .. ground.Position.Y .. ")")

-- schon durchgefallen (unter der Oberkante, kein Terrain): zurück nach oben
ground.Position = CENTER + Vector3.new(0, -16, 0)
ground:SetAttribute("HeldLocally", nil)
root.CFrame = CFrame.new(CENTER + Vector3.new(0, -9, 0))
SIM.Advance(0.4, 8)
check(root.Position.Y >= CENTER.Y + 2, "durchgefallen: zurück auf den Boden (" .. root.Position.Y .. ")")
check(math.abs(ground.Position.Y - (CENTER.Y - 2)) < 0.01, "Boden wieder oben")

-- Terrain geladen: Boden lokal wieder abgesenkt
loaded = true
SIM.Advance(0.4, 8)
check(math.abs(ground.Position.Y - (CENTER.Y - 16)) < 0.01 and ground:GetAttribute("HeldLocally") == nil,
	"Terrain da: Boden wieder abgesenkt (" .. ground.Position.Y .. ")")

-- auf einem Dach (weit über dem Boden) passiert nichts
loaded = false
root.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
SIM.Advance(0.4, 8)
check(math.abs(ground.Position.Y - (CENTER.Y - 16)) < 0.01, "auf dem Dach: Boden bleibt unten")

if failures == 0 then
	print("Bodenschutz: alles in Ordnung")
end

-- SpawnUtil (ModuleScript, nur Server)
-- Charakter neu laden und an eine bestimmte Stelle setzen.

local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")

local MovementGuard = require(ServerStorage:WaitForChild("ServerShared").MovementGuard)

local SpawnUtil = {}

-- Spawnt den Spieler an cframe. protection = Sekunden Schutzschild (0/nil = keins).
-- Gibt den neuen Charakter zurück oder nil, wenn es nicht geklappt hat.
function SpawnUtil.Spawn(player, cframe, protection)
	local ok = pcall(player.LoadCharacter, player)
	local character = player.Character
	if not ok or not character then
		return nil
	end
	character:PivotTo(cframe)
	MovementGuard.Teleported(character) -- neue Stelle ist gültig, kein Teleport-Verstoß

	-- Standard-Schild der SpawnLocation entfernen, eigenes setzen
	local default = character:FindFirstChildOfClass("ForceField")
	if default then
		default:Destroy()
	end
	if protection and protection > 0 then
		local shield = Instance.new("ForceField")
		shield.Parent = character
		Debris:AddItem(shield, protection)
	end
	return character
end

-- Zufälliger Spawnpunkt aus einem Ordner mit Parts (3 Studs darüber)
function SpawnUtil.Pick(folder)
	local points = folder:GetChildren()
	local point = points[math.random(#points)]
	return point.CFrame + Vector3.new(0, 3, 0)
end

return SpawnUtil

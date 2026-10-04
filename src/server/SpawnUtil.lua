-- SpawnUtil (ModuleScript, nur Server)
-- Charakter neu laden und an eine bestimmte Stelle setzen. Jeder Spieler spawnt als Agent: einheitlicher Körper
-- in den Farben seines Agenten bzw. Skins (AgentBody), nicht mit dem eigenen Roblox-Avatar.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Cosmetics = require(ReplicatedStorage:WaitForChild("Shared").Cosmetics)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local MovementGuard = require(ServerShared.MovementGuard)
local AgentBody = require(ServerShared.AgentBody)

local SpawnUtil = {}

-- Charakter mit dem Agenten-Körper laden. Klappt das nicht (z.B. Roblox-Dienst gestört), wird der normale
-- Charakter geladen – AgentService zieht ihn dann trotzdem als Agent an.
local function loadAgentCharacter(player)
	local primary = Cosmetics.AgentColors(player, player:GetAttribute("Agent"))
	local ok, err = pcall(player.LoadCharacterWithHumanoidDescription, player, AgentBody.Description(primary))
	if ok then
		return true
	end
	warn("Agenten-Körper für " .. player.Name .. " nicht geladen (" .. tostring(err) .. "), lade Standard-Charakter")
	return (pcall(player.LoadCharacter, player))
end

-- Spawnt den Spieler an cframe. protection = Sekunden Schutzschild (0/nil = keins).
-- Gibt den neuen Charakter zurück oder nil, wenn es nicht geklappt hat.
function SpawnUtil.Spawn(player, cframe, protection)
	local ok = loadAgentCharacter(player)
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

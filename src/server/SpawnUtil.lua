-- SpawnUtil (ModuleScript, nur Server)
-- Charakter neu laden und an eine bestimmte Stelle setzen. Jeder spawnt mit seinem eigenen Roblox-Avatar.

local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")

local ServerShared = ServerStorage:WaitForChild("ServerShared")
local MovementGuard = require(ServerShared.MovementGuard)

local SpawnUtil = {}

-- Streaming: dem Client die Umgebung von position schon schicken, bevor man ihn dorthin setzt (wartet nicht; bis der
-- Boden da ist, hält Roblox den Charakter an, StreamingIntegrityMode in default.project.json)
function SpawnUtil.Prestream(player, position)
	task.spawn(pcall, player.RequestStreamAroundAsync, player, position, 5)
end

-- Streaming ohne Charakter (Agentenwahl, Warten, Zuschauen): um position streamen, damit der Client die Map sieht.
-- Ein unsichtbarer verankerter Punkt je Spieler dient als ReplicationFocus; SpawnUtil.Spawn schaltet zurück.
local focusParts = {}
function SpawnUtil.FocusOn(player, position)
	local part = focusParts[player]
	if not part or not part.Parent then
		part = Instance.new("Part")
		part.Name = "StreamFocus_" .. player.UserId
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		part.Transparency = 1
		part.Size = Vector3.one
		part.Parent = workspace
		focusParts[player] = part
		player.AncestryChanged:Connect(function()
			if not player.Parent and focusParts[player] then
				focusParts[player]:Destroy()
				focusParts[player] = nil
			end
		end)
	end
	part.Position = position
	player.ReplicationFocus = part
end

-- Spawnt den Spieler an cframe. protection = Sekunden Schutzschild (0/nil = keins).
-- Gibt den neuen Charakter zurück oder nil, wenn es nicht geklappt hat.
function SpawnUtil.Spawn(player, cframe, protection)
	SpawnUtil.Prestream(player, cframe.Position)
	local ok = pcall(player.LoadCharacter, player) -- eigener Roblox-Avatar
	local character = player.Character
	if not ok or not character then
		return nil
	end
	character.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- Streaming: bei den anderen ganz oder gar nicht
	player.ReplicationFocus = nil -- wieder um den Charakter streamen (ohne Charakter: SpawnUtil.FocusOn)
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

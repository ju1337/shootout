-- SpawnUtil (ModuleScript, nur Server)
-- Charakter neu laden und an eine bestimmte Stelle setzen. Jeder Spieler spawnt als Agent: einheitlicher Körper
-- in den Farben seines Agenten (AgentBody), nicht mit dem eigenen Roblox-Avatar.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Cosmetics = require(ReplicatedStorage:WaitForChild("Shared").Cosmetics)
local AgentModels = require(ReplicatedStorage:WaitForChild("Shared").AgentModels)
local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local MovementGuard = require(ServerShared.MovementGuard)
local AgentBody = require(ServerShared.AgentBody)

local SpawnUtil = {}

-- Charakter mit dem Agenten-Körper laden. Klappt das nicht (z.B. Roblox-Dienst gestört), wird der normale
-- Charakter geladen – AgentService zieht ihn dann trotzdem als Agent an.
local function loadAgentCharacter(player)
	local primary = Cosmetics.AgentColors(player, AgentConfig.MainId)
	local ok, err = pcall(player.LoadCharacterWithHumanoidDescription, player, AgentBody.Description(primary))
	if ok then
		return true
	end
	warn("Agenten-Körper für " .. player.Name .. " nicht geladen (" .. tostring(err) .. "), lade Standard-Charakter")
	return (pcall(player.LoadCharacter, player))
end

-- Hat der Agent ein 3D-Modell, wird das Modell selbst der Charakter (wie ein StarterCharacter): der geladene
-- Roblox-Körper wird gelöscht, nur seine Skripte (Animate, Health) wandern ins Modell. Gibt true zurück, wenn getauscht.
local function useAgentModel(player)
	local default = player.Character
	local model = default and AgentModels.BuildCharacter(AgentConfig.MainId)
	if not model then
		return false
	end
	model.Name = player.Name
	for _, name in { "Animate", "Health" } do
		local script = default:FindFirstChild(name)
		if script and script:IsA("LuaSourceContainer") and not model:FindFirstChild(name) then
			script.Parent = model
		end
	end
	model:PivotTo(default:GetPivot())
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- nicht umkippen, solange noch der Server rechnet (der Client schaltet es bei sich auch ab, Movement)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end
	player.Character = model
	model.Parent = workspace
	default:Destroy()
	-- Physik gleich beim Spieler (sonst rechnet kurz der Server, und der Charakter kann umkippen)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		pcall(root.SetNetworkOwner, root, player)
	end
	return true
end

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
	local ok = loadAgentCharacter(player)
	if ok then
		local swapped, err = pcall(useAgentModel, player)
		if not swapped then
			warn("[Agentenmodelle] " .. player.Name .. ": Modell als Charakter fehlgeschlagen (" .. tostring(err) .. ")")
		end
	end
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

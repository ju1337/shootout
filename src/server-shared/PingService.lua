-- PingService (ModuleScript, nur Server)
-- Markierungen für das eigene Team (Taste Z / Mausrad-Klick): Ort oder Gegner.
-- Geht an alle Teamkollegen im selben Modus (ohne Team, z.B. Free-for-All, nur an sich selbst).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)

local PingService = {}

local COOLDOWN = 0.75
local MAX_DISTANCE = 600

local lastPing = {}

local function isEnemyModel(player, model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return false
	end
	local other = Players:GetPlayerFromCharacter(model)
	local mode = other and other:GetAttribute("Mode") or model:GetAttribute("Mode")
	local teamName = other and other.Team and other.Team.Name or model:GetAttribute("TeamName")
	if not other and not model:GetAttribute("IsBot") then
		return false
	end
	return mode == player:GetAttribute("Mode") and not (player.Team and teamName == player.Team.Name) and other ~= player
end

function PingService.Init()
	Remotes.Ping.OnServerEvent:Connect(function(player, position, model)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if typeof(position) ~= "Vector3" or not root or (position - root.Position).Magnitude > MAX_DISTANCE then
			return
		end
		local now = os.clock()
		if lastPing[player] and now - lastPing[player] < COOLDOWN then
			return
		end
		lastPing[player] = now
		local enemy = isEnemyModel(player, model) and model or nil
		for _, mate in Players:GetPlayers() do
			local sameTeam = mate == player
				or (player.Team ~= nil and mate.Team == player.Team and mate:GetAttribute("Mode") == player:GetAttribute("Mode"))
			if sameTeam then
				Remotes.PingShow:FireClient(mate, position, enemy, player.Name)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPing[player] = nil
	end)
end

return PingService

-- Hub (ModuleScript, nur Server)
-- Treffpunkt: kein Kampf, Portale schicken Spieler in die Modi.

local Players = game:GetService("Players")

local SpawnUtil = require(script.Parent.Parent.SpawnUtil)

local Hub = {}

local RESPAWN_TIME = 2
local PORTAL_COOLDOWN = 3

local manager
local members = {}
local lastTouch = {}
local map = workspace:WaitForChild("Maps"):WaitForChild("Hub")

local function spawnPlayer(player)
	if not members[player] then
		return
	end
	local character = SpawnUtil.Spawn(player, SpawnUtil.Pick(map.Spawns))
	if not character then
		return
	end
	character:WaitForChild("Humanoid").Died:Connect(function()
		task.delay(RESPAWN_TIME, function()
			if members[player] and player.Character == character then
				spawnPlayer(player)
			end
		end)
	end)
end

function Hub.Init(modeManager)
	manager = modeManager

	-- Portale: Parts "Portal_<ModusId>" in Maps.Hub.Portals
	for _, pad in map.Portals:GetChildren() do
		local modeId = string.match(pad.Name, "^Portal_(.+)$")
		if pad:IsA("BasePart") and modeId then
			pad.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if not player or not members[player] then
					return
				end
				local now = os.clock()
				if lastTouch[player] and now - lastTouch[player] < PORTAL_COOLDOWN then
					return
				end
				lastTouch[player] = now
				manager.Join(player, modeId)
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player] = nil
	end)
end

function Hub.CanJoin()
	return true
end

function Hub.AddPlayer(player)
	members[player] = true
	spawnPlayer(player)
end

function Hub.RemovePlayer(player)
	members[player] = nil
end

return Hub

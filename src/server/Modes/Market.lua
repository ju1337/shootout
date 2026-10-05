-- Market (ModuleScript, nur Server)
-- Markthalle: kein Kampf. Spieler beanspruchen Stände, bieten Skins für RAP an und kaufen bei anderen
-- (MarketService). Wer den Markt verlässt (Runde, Hub, Spiel verlassen), verliert seinen Stand – die Skins darauf
-- waren nur zurückgelegt und sind sofort wieder frei. Das Tor im Süden ("Portal_Hub") führt zurück in den Hub.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local MarketService = require(ServerStorage:WaitForChild("ServerShared").MarketService)
local SpawnUtil = require(script.Parent.Parent.SpawnUtil)

local Market = {}

local RESPAWN_TIME = 2
local PORTAL_COOLDOWN = 3

local manager
local members = {}
local lastTouch = {}
local map = workspace:WaitForChild("Maps"):WaitForChild("Market")

local function spawnPlayer(player)
	if not members[player] then
		return
	end
	local character = SpawnUtil.Spawn(player, SpawnUtil.Pick(map.Spawns))
	if not character then
		return
	end
	player:SetAttribute("ModeText", "")
	character:WaitForChild("Humanoid").Died:Connect(function()
		task.delay(RESPAWN_TIME, function()
			if members[player] and player.Character == character then
				spawnPlayer(player)
			end
		end)
	end)
end

function Market.Init(modeManager)
	manager = modeManager
	MarketService.Init(map)
	-- Portale: Parts "Portal_<ModusId>" in Maps.Market.Portals (zurück zum Hub)
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

function Market.CanJoin()
	return true
end

function Market.AddPlayer(player)
	members[player] = true
	lastTouch[player] = os.clock() -- nicht gleich wieder durchs Tor
	MarketService.PublishWatch(player)
	spawnPlayer(player)
end

-- Markt verlassen: Stand weg, Skins wieder frei
function Market.RemovePlayer(player)
	members[player] = nil
	MarketService.Leave(player, "Du hast den Markt verlassen – dein Stand ist wieder frei, deine Skins sind zurück im Inventar.")
end

return Market

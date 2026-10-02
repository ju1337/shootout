-- PerkService (ModuleScript, nur Server)
-- Perks, die laufend wirken (gekauft in der Kaufphase, BuyConfig):
--   Regeneration – nach RegenDelay Sekunden ohne Schaden langsam heilen
--   Racheblick   – beim eigenen Tod wird der Angreifer für das eigene Team markiert
-- Zäh (AgentService), Sanitäter (DownedService) und Leichtfuß (Movement) wirken dort direkt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local BuyConfig = require(Shared.BuyConfig)
local AgentConfig = require(Shared.AgentConfig)
local Damage = require(ServerStorage:WaitForChild("ServerShared").Damage)

local PerkService = {}

local TICK = 0.5

local function onCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		if not BuyConfig.Has(player, "Vengeance") then
			return
		end
		local killer = Damage.LastAttacker(character)
		if not killer or not killer.Parent then
			return
		end
		-- An sich selbst und das eigene Team (gleicher Modus)
		for _, mate in Players:GetPlayers() do
			local sameTeam = mate == player
				or (player.Team ~= nil and mate.Team == player.Team and mate:GetAttribute("Mode") == player:GetAttribute("Mode"))
			if sameTeam then
				Remotes.Reveal:FireClient(mate, { killer }, BuyConfig.VengeanceTime)
			end
		end
	end)
end

function PerkService.Init()
	local function onPlayer(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	-- Regeneration
	task.spawn(function()
		while true do
			task.wait(TICK)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local perk = BuyConfig.Has(player, "Regen")
				local passive = character and AgentConfig.PassiveOf(character, "Regen") -- Passiv AEGIS
				local delay = perk and BuyConfig.RegenDelay or 6
				if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth and (perk or passive)
					and not character:GetAttribute("Downed") and now - (character:GetAttribute("LastDamaged") or 0) >= delay then
					local rate = (perk and BuyConfig.RegenPerSecond or 0) + (passive and 2 or 0)
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + rate * TICK)
				end
			end
		end
	end)
end

return PerkService

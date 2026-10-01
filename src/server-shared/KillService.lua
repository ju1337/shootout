-- KillService (ModuleScript, nur Server)
-- Zählt Kills (leaderstats) und schickt die Killfeed-Meldung an alle Spieler.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)
local Modes = require(ReplicatedStorage:WaitForChild("Shared").Modes)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local WeaponService = require(ServerShared.WeaponService)
local ProgressService = require(ServerShared.ProgressService)

local KillService = {}

-- Wird nach dem Zählen gefeuert: (killer: Player, victim: Player, killerKills: number)
local countedEvent = Instance.new("BindableEvent")
KillService.KillCounted = countedEvent.Event

-- Legt die Anzeige "Kills" in der Spielerliste an
local function setupPlayer(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"

	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Value = 0
	kills.Parent = stats

	stats.Parent = player

	-- Tode zählen (fürs Scoreboard), nur in Kampfmodi
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid").Died:Connect(function()
			if Modes.IsFighting(player) then
				player:SetAttribute("Deaths", (player:GetAttribute("Deaths") or 0) + 1)
			end
		end)
	end)
end

-- Kills eines Spielers auf 0 setzen (Moduswechsel, neue Runde)
function KillService.ResetPlayer(player)
	local kills = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Kills")
	if kills then
		kills.Value = 0
	end
	player:SetAttribute("Deaths", 0)
	player:SetAttribute("Damage", 0)
end

-- Kill durch einen Bot: nur Killfeed (Bots sammeln keine Kills)
function KillService.ReportBotKill(modeId, botName, victimName, weaponName, headshot)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Mode") == modeId then
			Remotes.Killfeed:FireClient(player, botName, victimName, weaponName, headshot)
		end
	end
end

-- Kills eines Spielers lesen
function KillService.GetKills(player)
	local kills = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Kills")
	return kills and kills.Value or 0
end

function KillService.Init()
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	WeaponService.Killed:Connect(function(killer, victim, weaponName, headshot, victimName)
		-- Selbstmord zählt nicht
		if killer ~= victim then
			local kills = killer:FindFirstChild("leaderstats") and killer.leaderstats:FindFirstChild("Kills")
			if kills then
				kills.Value += 1
			end
			-- XP für den Agenten des Killers
			local rewards = AgentConfig.XPRewards
			ProgressService.AddXP(killer, ProgressService.ActiveAgent(killer),
				rewards.Kill + (headshot and rewards.Headshot or 0), headshot and "Kopfschuss-Kill" or "Kill")
		end
		-- Killfeed nur an Spieler im selben Modus
		local mode = killer:GetAttribute("Mode")
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Mode") == mode then
				Remotes.Killfeed:FireClient(player, killer.Name, victimName, weaponName, headshot)
			end
		end
		countedEvent:Fire(killer, victim, KillService.GetKills(killer))
	end)
end

return KillService

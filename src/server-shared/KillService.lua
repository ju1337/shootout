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
local DownedService = require(ServerShared.DownedService)
local BuyService = require(ServerShared.BuyService)
local Damage = require(ServerShared.Damage)
local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared").WeaponConfig)
local BuyConfig = require(ReplicatedStorage:WaitForChild("Shared").BuyConfig)

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
			if not Modes.IsFighting(player) then
				return
			end
			player:SetAttribute("Deaths", (player:GetAttribute("Deaths") or 0) + 1)
			ProgressService.AddStat(player, "Deaths", 1)
			-- Todesanzeige: wer, womit, wie viel Leben hatte er noch
			local hit = Damage.LastHit(character)
			if hit and hit.Model ~= character then
				local humanoid = hit.Model.Parent and hit.Model:FindFirstChildOfClass("Humanoid")
				local weapon = hit.Weapon and WeaponConfig.Get(hit.Weapon)
				Remotes.DeathRecap:FireClient(player, hit.Name, weapon and weapon.DisplayName or hit.Weapon,
					humanoid and math.ceil(humanoid.Health) or 0, hit.Model:GetAttribute("Agent"))
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

	local function onKill(killer, victim, weaponName, headshot, victimName)
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
			BuyService.AddMoney(killer, BuyConfig.Rewards.Kill, "Kill") -- nur in laufenden Team-Matches
			ProgressService.QuestEvent(killer, "Kill", 1)
			ProgressService.AddStat(killer, "Kills", 1)
			ProgressService.AddStat(killer, "Kills_" .. ProgressService.ActiveAgent(killer), 1)
			if headshot then
				ProgressService.AddStat(killer, "Headshots", 1)
			end
			-- Assists: alle anderen Spieler mit mindestens 25 Schaden am Opfer
			local victimModel = victim and victim.Character
			if victimModel then
				for helper, dealt in Damage.Contributors(victimModel) do
					if helper ~= killer and helper.Parent and dealt >= 25 then
						ProgressService.AddStat(helper, "Assists", 1)
						ProgressService.AddXP(helper, ProgressService.ActiveAgent(helper), AgentConfig.XPRewards.Assist, "Assist")
						BuyService.AddMoney(helper, BuyConfig.Rewards.Assist, "Assist")
					end
				end
			end
			if headshot then
				ProgressService.QuestEvent(killer, "Headshot", 1)
			end
		end
		-- Killfeed nur an Spieler im selben Modus
		local mode = killer:GetAttribute("Mode")
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("Mode") == mode then
				Remotes.Killfeed:FireClient(player, killer.Name, victimName, weaponName, headshot)
			end
		end
		countedEvent:Fire(killer, victim, KillService.GetKills(killer))
	end
	WeaponService.Killed:Connect(onKill)

	-- Verblutet: Kill für den, der niedergeschlagen hat (Spieler oder Bot)
	DownedService.BledOut:Connect(function(model, attacker)
		local victim = Players:GetPlayerFromCharacter(model)
		local victimName = victim and victim.Name or model.Name
		if attacker and attacker.Player and attacker.Player.Parent then
			onKill(attacker.Player, victim, attacker.Weapon, false, victimName)
		elseif attacker and attacker.BotName then
			KillService.ReportBotKill(victim and victim:GetAttribute("Mode") or model:GetAttribute("Mode"),
				attacker.BotName, victimName, attacker.Weapon, false)
		end
	end)
end

return KillService

-- KillService (ModuleScript, nur Server)
-- Zählt Kills (leaderstats), schickt die Killfeed-Meldung an alle Spieler und vergibt Medaillen im Stil von
-- Call of Duty (Mehrfach-Kills, Killserien, Erstes Blut, Rache, Weitschuss, Kopfschuss, Serie beendet,
-- Comeback). Die Medaillen eines Kills gehen gesammelt als Remotes.Notify("Medal", Liste) an den Killer.
-- Die Kill-Boni aus RewardConfig (Münzen für Rache, Serie beendet und Killserien, Statistik, Wochen-Auftrag
-- "5er-Killserie", beste Killserie) vergibt KillService gleich mit – die Münzen stehen in der Medaille.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)
local Modes = require(ReplicatedStorage:WaitForChild("Shared").Modes)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local WeaponService = require(ServerShared.WeaponService)
local ProgressService = require(ServerShared.ProgressService)
local SpeedEffects = require(ServerShared.SpeedEffects)
local DownedService = require(ServerShared.DownedService)
local BuyService = require(ServerShared.BuyService)
local Damage = require(ServerShared.Damage)
local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared").WeaponConfig)
local BuyConfig = require(ReplicatedStorage:WaitForChild("Shared").BuyConfig)
local Medals = require(ReplicatedStorage:WaitForChild("Shared").Medals)
local RewardConfig = require(ReplicatedStorage:WaitForChild("Shared").RewardConfig)
local SkinEffects = require(ReplicatedStorage:WaitForChild("Shared").SkinEffects)

local KillService = {}

local MULTI_WINDOW = 4       -- Kills innerhalb so vieler Sekunden zählen als Mehrfach-Kill
local COMEBACK_DEATHS = 3    -- so oft hintereinander gestorben: der nächste Kill ist ein COMEBACK
local BUZZKILL_STREAK = 3    -- Killserie des Opfers, ab der es SERIE BEENDET gibt
local LONGSHOT_SHARE = 0.3   -- Weitschuss ab diesem Anteil der Waffenreichweite ...
local LONGSHOT_MIN, LONGSHOT_MAX = 35, 120 -- ... aber mindestens/höchstens so viele Studs

local multis = {}          -- [Player] = { Count, Last }: Kills kurz hintereinander
local lifeKills = {}       -- [Player] = Kills seit dem letzten Tod (Killserie)
local streakAtDeath = {}   -- [Player] = { Count, At }: Serie beim letzten Tod (falls der Tod vor dem Kill ankommt)
local deathsInRow = {}     -- [Player] = Tode seit dem letzten eigenen Kill
local lastKiller = {}      -- [Player] = { Name, Player }: wer einen zuletzt ausgeschaltet hat (Spieler oder Bot)
local firstBloodTaken = {} -- [ModeId] = true, sobald in der laufenden Runde jemand ausgeschaltet wurde

-- Medaillen-Zustand eines Spielers zurücksetzen (neues Match, Moduswechsel)
local function resetMedals(player)
	multis[player] = nil
	lifeKills[player] = nil
	streakAtDeath[player] = nil
	deathsInRow[player] = nil
	lastKiller[player] = nil
end

-- Wird nach dem Zählen gefeuert: (killer: Player, victim: Player, killerKills: number, weaponName: string)
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
		lifeKills[player] = 0 -- Killserie gilt pro Leben
		character:WaitForChild("Humanoid").Died:Connect(function()
			if not Modes.IsFighting(player) then
				return
			end
			player:SetAttribute("Deaths", (player:GetAttribute("Deaths") or 0) + 1)
			ProgressService.AddStat(player, "Deaths", 1)
			-- Killserie endet; die alte Serie kurz merken (für SERIE BEENDET beim Killer)
			streakAtDeath[player] = { Count = lifeKills[player] or 0, At = os.clock() }
			lifeKills[player] = 0
			multis[player] = nil
			deathsInRow[player] = (deathsInRow[player] or 0) + 1
			-- Todesanzeige: wer, womit, wie viel Leben hatte er noch
			local hit = Damage.LastHit(character)
			if hit and hit.Model ~= character then
				lastKiller[player] = { Name = hit.Name, Player = Players:GetPlayerFromCharacter(hit.Model) } -- für RACHE
				local humanoid = hit.Model.Parent and hit.Model:FindFirstChildOfClass("Humanoid")
				local weapon = hit.Weapon and WeaponConfig.Get(hit.Weapon)
				Remotes.DeathRecap:FireClient(player, hit.Name, weapon and weapon.DisplayName or hit.Weapon,
					humanoid and math.ceil(humanoid.Health) or 0, hit.Model:GetAttribute("Agent"), hit.Model)
			end
		end)
	end)
	player:GetAttributeChangedSignal("Mode"):Connect(function()
		resetMedals(player)
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
	resetMedals(player)
end

-- Neue Runde in einem Modus: ERSTES BLUT ist wieder zu haben
function KillService.NewRound(modeId)
	firstBloodTaken[modeId] = nil
end

-- Kill durch einen Bot: nur Killfeed (Bots sammeln keine Kills und keine Medaillen)
function KillService.ReportBotKill(modeId, botName, victimName, weaponName, headshot)
	firstBloodTaken[modeId] = true
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

-- Abstand Killer -> Opfer reicht für WEITSCHUSS? (nur Schusswaffen)
local function isLongshot(killer, victimModel, weaponName)
	local config = weaponName and WeaponConfig.Get(weaponName)
	local from = killer.Character and killer.Character:FindFirstChild("HumanoidRootPart")
	local to = typeof(victimModel) == "Instance" and victimModel:FindFirstChild("HumanoidRootPart")
	if not config or not config.Range or not from or not to then
		return false
	end
	local needed = math.clamp(config.Range * LONGSHOT_SHARE, LONGSHOT_MIN, LONGSHOT_MAX)
	return (from.Position - to.Position).Magnitude >= needed
end

-- Münz-Belohnung für genau diese Killserie (RewardConfig.Streaks) oder nil
local function streakReward(kills)
	for _, reward in RewardConfig.Streaks do
		if reward.Kills == kills then
			return reward
		end
	end
	return nil
end

-- Medaillen für einen Kill sammeln, Bonus-XP und Münzen vergeben und gesammelt an den Killer schicken
local function awardMedals(killer, victim, weaponName, headshot, victimName, victimModel)
	local list = {}
	local agent = ProgressService.ActiveAgent(killer)
	-- reward = { Coins, Name } aus RewardConfig (Name = Grund in der Match-Übersicht)
	local function add(id, sub, reward)
		local medal = Medals.Get(id)
		if medal then
			local xp = medal.XP > 0 and ProgressService.AddXP(killer, agent, medal.XP, medal.Title, true) or 0
			local coins = reward and reward.Coins or 0
			if coins > 0 then
				ProgressService.AddCoins(killer, coins, reward.Name)
			end
			table.insert(list, { Id = id, Xp = xp, Coins = coins > 0 and coins or nil, Sub = sub })
		end
	end

	-- Mehrfach-Kill (Kills innerhalb von MULTI_WINDOW Sekunden)
	local now = os.clock()
	local multi = multis[killer]
	if multi and now - multi.Last <= MULTI_WINDOW then
		multi.Count += 1
	else
		multi = { Count = 1 }
		multis[killer] = multi
	end
	multi.Last = now
	local multiId = Medals.ForMulti(multi.Count)
	if multiId then
		add(multiId, multi.Count >= 9 and (multi.Count .. " KILLS") or nil)
	end

	-- Killserie (ohne zu sterben), Münzen bei den Stufen aus RewardConfig.Streaks
	local streak = (lifeKills[killer] or 0) + 1
	lifeKills[killer] = streak
	local streakId = Medals.ForStreak(streak)
	local reward = streakReward(streak)
	if streakId then
		add(streakId, streak .. " KILLS IN FOLGE", reward)
	elseif reward then
		ProgressService.AddCoins(killer, reward.Coins, reward.Name) -- Stufe ohne eigene Medaille
	end
	if streak == 5 then
		ProgressService.QuestEvent(killer, "Streak5", 1) -- Wochen-Auftrag "5er-Killserie"
	end
	local profile = ProgressService.Get(killer)
	local best = profile and profile.Stats and profile.Stats.BestStreak or 0
	if profile and streak > best then
		ProgressService.AddStat(killer, "BestStreak", streak - best)
	end

	-- Erstes Blut der Runde (nicht in der offenen Welt: dort gibt es keine Runden)
	local mode = killer:GetAttribute("Mode")
	if mode and not Modes.IsSurvival(mode) and not firstBloodTaken[mode] then
		firstBloodTaken[mode] = true
		add("FirstBlood")
	end

	-- Rache: den ausgeschaltet, der einen selbst zuletzt erwischt hat (Münzen und Statistik nur gegen Spieler)
	local last = lastKiller[killer]
	if last and (last.Name == victimName or (victim ~= nil and last.Player == victim)) then
		lastKiller[killer] = nil
		local real = victim ~= nil and last.Player == victim
		add("Revenge", "AN " .. tostring(victimName), real and RewardConfig.Revenge or nil)
		if real then
			ProgressService.AddStat(killer, "Revenges", 1)
		end
	end

	-- Serie des Opfers beendet (Spieler: lebende Serie oder die gerade beim Tod gemerkte)
	if victim then
		local victimStreak = lifeKills[victim] or 0
		local atDeath = streakAtDeath[victim]
		if atDeath and now - atDeath.At < 1 then
			victimStreak = math.max(victimStreak, atDeath.Count)
		end
		streakAtDeath[victim] = nil -- nur einmal zählen
		if victimStreak >= BUZZKILL_STREAK then
			-- Münzen und Statistik erst ab RewardConfig.Shutdown.MinStreak
			local shutdown = victimStreak >= RewardConfig.Shutdown.MinStreak
			add("Buzzkill", tostring(victimName) .. "  ·  " .. victimStreak .. " KILLS", shutdown and RewardConfig.Shutdown or nil)
			if shutdown then
				ProgressService.AddStat(killer, "Shutdowns", 1)
			end
		end
	end

	-- Comeback nach mehreren Toden ohne Kill
	if (deathsInRow[killer] or 0) >= COMEBACK_DEATHS then
		add("Comeback")
	end
	deathsInRow[killer] = 0

	if isLongshot(killer, victimModel, weaponName) then
		add("Longshot")
	end
	if headshot then
		add("Headshot")
	end

	if #list > 0 then
		Remotes.Notify:FireClient(killer, "Medal", Medals.Sort(list))
	end
end

function KillService.Init()
	Players.PlayerRemoving:Connect(function(player)
		resetMedals(player)
	end)
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end

	local function onKill(killer, victim, weaponName, headshot, victimName, victimModel)
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
			-- Passiv BLAZE: nach einem Kill kurz schneller
			local killerCharacter = killer.Character
			if killerCharacter and AgentConfig.PassiveOf(killerCharacter, "KillSpeed") then
				SpeedEffects.Apply(killerCharacter, "KillSpeed", 1.2, 2)
			end
			-- Medaillen (Mehrfach-Kill, Killserie, Erstes Blut ...) mit Bonus-XP
			awardMedals(killer, victim, weaponName, headshot, victimName, victimModel)
			ProgressService.AddStat(killer, "Kills", 1)
			ProgressService.AddStat(killer, "Kills_" .. ProgressService.ActiveAgent(killer), 1)
			if headshot then
				ProgressService.AddStat(killer, "Headshots", 1)
			end
			-- Assists: alle anderen Spieler mit mindestens 25 Schaden am Opfer
			local victimCharacter = victim and victim.Character
			if victimCharacter then
				for helper, dealt in Damage.Contributors(victimCharacter) do
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
		-- Kill-Finisher eines Effekt-Skins (z.B. Splitterlicht): nur mit der Waffe, die den Skin trägt
		local tool = killer ~= victim and killer.Character and killer.Character:FindFirstChildOfClass("Tool")
		local skinFx = tool and tool:GetAttribute("SkinFx")
		local victimCharacter = victimModel or (victim and victim.Character)
		local root = victimCharacter and (victimCharacter:FindFirstChild("HumanoidRootPart") or victimCharacter.PrimaryPart)
		if skinFx and root and tool:GetAttribute("Weapon") == weaponName and SkinEffects.HasFinisher(skinFx) then
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("Mode") == mode then
					Remotes.SkinFinisher:FireClient(player, victimCharacter, root.CFrame, skinFx, weaponName,
						tool:GetAttribute("SkinId"))
				end
			end
		end
		countedEvent:Fire(killer, victim, KillService.GetKills(killer), weaponName)
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

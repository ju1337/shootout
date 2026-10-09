-- ExtLevelService (ModuleScript, nur Server)
-- EP der offenen Welt (Werte in ExtLevelConfig): für Nester, Lager, Überlebende, Funk, Lootdrops, den Konvoi und
-- erledigte Aufträge. Es gibt nur noch EIN Level: die EP gehen ins Spielerlevel (ProgressService.AddAccountXP,
-- LevelConfig; mit XP-Faktor und Doppel-XP). Kills (Zombies, Spieler, Bots) geben Level-XP nur über
-- ProgressService.AddXP (ZombieService, KillService) – hier zählen sie nur in der Statistik (Count).
-- Die Statistik ExtXP zählt alle EP mit (Erfolg Ödland-Veteran).
-- Aufstiegs-Meldung und Titel kommen über das Spielerlevel (Notifications, RewardService, TitleConfig).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local ExtLevelConfig = require(Shared.ExtLevelConfig)
local LevelConfig = require(Shared.LevelConfig)
local ProgressService = require(script.Parent.ProgressService)
local ZombieService = require(script.Parent.ZombieService)
local ActivityService = require(script.Parent.ActivityService)
local LootService = require(script.Parent.LootService)
local MissionService = require(script.Parent.MissionService)

local ExtLevelService = {}

local R = ExtLevelConfig.Rewards
local openedDrops = setmetatable({}, { __mode = "k" }) -- [Player] = { [BagId] = true }

-- Nur Statistik (nur in der offenen Welt): stat steigt um 1 (für die Erfolge, z.B. "ExtZombies"), ExtXP um amount.
-- Keine Level-XP und keine Anzeige (für Kills: deren XP kommen schon über ProgressService.AddXP).
-- Gibt die ganzzahligen EP zurück, nil wenn nichts gezählt wurde.
function ExtLevelService.Count(player, amount, stat)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or not player.Parent or not Modes.IsSurvival(player:GetAttribute("Mode")) or not ProgressService.Get(player) then
		return nil
	end
	if stat then
		ProgressService.AddStat(player, stat, 1)
	end
	ProgressService.AddStat(player, ExtLevelConfig.Stat, amount)
	return amount
end

-- EP geben (nur in der offenen Welt): Statistik wie Count, dazu Spielerlevel-XP (mit XP-Faktor und Doppel-XP) und
-- "+N XP" unter der Hotbar. reason: kurzer Text für die Anzeige. Gibt das neue Spielerlevel zurück.
function ExtLevelService.Add(player, amount, reason, stat)
	amount = ExtLevelService.Count(player, amount, stat)
	if not amount then
		return nil
	end
	local gained, doubled = ProgressService.AddAccountXP(player, amount)
	if gained > 0 then
		Remotes.ExtUpdate:FireClient(player, "ExtXP", gained, doubled and (tostring(reason) .. " · Doppel-XP") or reason)
	end
	return LevelConfig.Get(player).Level
end

-- opts = { RedzoneAt(position) -> Zone | nil }
function ExtLevelService.Init(opts)
	opts = opts or {}
	table.insert(ZombieService.OnKill, function(killer, kind, position)
		if killer then
			local xp = ExtLevelConfig.Kinds[kind] or R.Zombie
			if opts.RedzoneAt and position and opts.RedzoneAt(position) then
				xp += R.RedZombie
			end
			if kind == "Brute" and Modes.IsSurvival(killer:GetAttribute("Mode")) then
				ProgressService.AddStat(killer, "ExtBrutes", 1)
			end
			ExtLevelService.Count(killer, xp, "ExtZombies") -- Level-XP gibt ZombieService (AddXP)
		end
	end)
	table.insert(ActivityService.OnEvent, function(player, kind)
		if R[kind] then
			ExtLevelService.Add(player, R[kind], kind, "Ext" .. kind .. "s")
		end
	end)
	table.insert(LootService.OnOpened, function(player, bag)
		if bag.Kind == "Airdrop" then
			local seen = openedDrops[player] or {}
			openedDrops[player] = seen
			if not seen[bag.Id] then
				seen[bag.Id] = true
				ExtLevelService.Add(player, R.Airdrop, "Lootdrop", "ExtAirdrops")
			end
		end
	end)
	table.insert(MissionService.OnComplete, function(player)
		ExtLevelService.Add(player, R.Mission, "Auftrag", "ExtMissions")
	end)
end

return ExtLevelService

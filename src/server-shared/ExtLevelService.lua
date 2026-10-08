-- ExtLevelService (ModuleScript, nur Server)
-- Extinction-Level (Werte in ExtLevelConfig): EP für Zombies, Spieler, Bots, Nester, Lager, Überlebende, Funk, Lootdrops,
-- den Konvoi und erledigte Aufträge. Gespeichert als Statistik ExtXP (ProgressService.AddStat); Spieler-Attribute ExtLevel
-- und ExtXP für den Client. Beim Aufstieg eine Meldung, bei Titel-Leveln mit dem neuen Titel (den Titel selbst schaltet
-- TitleConfig über die Statistik frei).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local ExtLevelConfig = require(Shared.ExtLevelConfig)
local ProgressService = require(script.Parent.ProgressService)
local ZombieService = require(script.Parent.ZombieService)
local ActivityService = require(script.Parent.ActivityService)
local LootService = require(script.Parent.LootService)
local MissionService = require(script.Parent.MissionService)

local ExtLevelService = {}

local R = ExtLevelConfig.Rewards
local openedDrops = setmetatable({}, { __mode = "k" }) -- [Player] = { [BagId] = true }

local function totalXP(player)
	local profile = ProgressService.Get(player)
	local stats = profile and profile.Stats
	return stats and tonumber(stats[ExtLevelConfig.Stat]) or 0
end

-- Level und EP ans Spieler-Attribut
function ExtLevelService.Publish(player)
	local xp = totalXP(player)
	player:SetAttribute("ExtXP", xp)
	player:SetAttribute("ExtLevel", (ExtLevelConfig.FromXP(xp)))
end

-- EP geben (nur in der offenen Welt). reason: kurzer Text für die Anzeige, stat: Statistik, die um 1 steigt (für die
-- Erfolge, z.B. "ExtZombies"). Gibt das neue Level zurück.
function ExtLevelService.Add(player, amount, reason, stat)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or not player.Parent or not Modes.IsSurvival(player:GetAttribute("Mode")) or not ProgressService.Get(player) then
		return nil
	end
	local before = ExtLevelConfig.FromXP(totalXP(player))
	if stat then
		ProgressService.AddStat(player, stat, 1)
	end
	ProgressService.AddStat(player, ExtLevelConfig.Stat, amount)
	ExtLevelService.Publish(player)
	local after = player:GetAttribute("ExtLevel")
	Remotes.ExtUpdate:FireClient(player, "ExtXP", amount, reason)
	for level = before + 1, after do
		local title = ExtLevelConfig.TitleAt(level)
		Remotes.Notify:FireClient(player, "Banner", { Caption = "Extinction", Title = "LEVEL " .. level,
			Sub = title and ("Neuer Titel: " .. title.Name .. " · im Fenster TITEL auswählen") or "Weiter so, Überlebender",
			Style = "Good" })
	end
	return after
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
			ExtLevelService.Add(killer, xp, "Zombie", "ExtZombies")
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

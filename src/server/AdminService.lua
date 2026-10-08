-- AdminService (ModuleScript, nur Server)
-- Befehle aus dem Admin-Panel. Jeder Befehl wird hier geprüft: nur Admins dürfen.
-- Admin ist: in Studio jeder, sonst der Besitzer des Spiels (bzw. Rang 254+ in der Gruppe)
-- und alle UserIds in ADMIN_IDS.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local GameSettings = require(Shared.GameSettings)
local LevelConfig = require(Shared.LevelConfig)
local RankConfig = require(Shared.RankConfig)
local RapConfig = require(Shared.RapConfig)
local Cosmetics = require(Shared.Cosmetics)
local DayCycle = require(Shared.DayCycle)
local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)
local LeaderboardService = require(ServerStorage:WaitForChild("ServerShared").LeaderboardService)
local BotService = require(script.Parent.BotService)

local AdminService = {}

-- Weitere Admins hier eintragen (Roblox-UserIds), z.B. { 12345678 }
local ADMIN_IDS = {}

local function isAdmin(player)
	if RunService:IsStudio() or table.find(ADMIN_IDS, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
	return ok and rank >= 254
end

function AdminService.Init(manager)
	local ffa = manager.GetModule("FreeForAll")

	-- Team-Modus (Drop/Strikeout) aus dem Panel holen
	local function teamMode(modeId)
		local module = typeof(modeId) == "string" and manager.GetModule(modeId)
		return module and module.AdminStart and module or nil
	end

	local function target(userId)
		return Players:GetPlayerByUserId(tonumber(userId) or 0)
	end

	local function humanoidOf(player)
		return player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	end

	local function serverShared(name)
		return require(ServerStorage:WaitForChild("ServerShared")[name])
	end

	-- Position des Admins (offene Welt) oder nil
	local function adminPosition(admin)
		local root = admin and admin.Character and admin.Character:FindFirstChild("HumanoidRootPart")
		return root and root.Position or nil
	end

	-- Jede Aktion gibt einen Text für das Panel zurück (admin = der Spieler, der den Befehl geschickt hat)
	local actions = {
		-- ---------- Events der offenen Welt (Extinction) ----------
		-- Lootdrop: where = "Here" landet beim Admin, sonst zufällig
		ExtAirdrop = function(where, _, admin)
			local AirdropService = serverShared("AirdropService")
			local position = where == "Here" and adminPosition(admin) or nil
			if where == "Here" and not position then
				return "Kein Charakter – geh in die offene Welt."
			end
			local drop = AirdropService.Start(position)
			return drop and ("Lootdrop gestartet" .. (position and " (bei dir)" or "")) or "Es läuft schon ein Lootdrop (oder kein Ziel gefunden)."
		end,
		ExtHordeCrate = function(where, _, admin)
			local position = where == "Here" and adminPosition(admin) or nil
			if where == "Here" and not position then
				return "Kein Charakter – geh in die offene Welt."
			end
			if position then
				position += (admin.Character.HumanoidRootPart.CFrame.LookVector * Vector3.new(1, 0, 1)) * 10 - Vector3.new(0, 3, 0)
			end
			local horde = serverShared("HordeService").Start(position)
			return horde and ("Horden-Kiste aufgestellt" .. (position and " (vor dir)" or "")) or "Es steht schon eine Horden-Kiste."
		end,
		ExtHeliCrash = function(where, _, admin)
			local position = where == "Here" and adminPosition(admin) or nil
			if where == "Here" and not position then
				return "Kein Charakter – geh in die offene Welt."
			end
			if position then
				position += (admin.Character.HumanoidRootPart.CFrame.LookVector * Vector3.new(1, 0, 1)) * 40 - Vector3.new(0, 3, 0)
			end
			local crash = serverShared("HeliCrashService").Start(position)
			return crash and ("Heli stürzt ab" .. (position and " (40 Studs vor dir)" or "")) or "Es läuft schon ein Heli-Absturz."
		end,
		ExtConvoy = function()
			local convoy = serverShared("ConvoyService").Start()
			return convoy and ("Konvoi gestartet: " .. tostring(convoy.Path and convoy.Path.Name or "")) or "Es fährt schon ein Konvoi."
		end,
		ExtRedzone = function()
			local zone = serverShared("RedzoneService").MoveNow()
			return zone and ("Rote Zone jetzt: " .. zone.Title) or "Keine rote Zone möglich."
		end,
		ExtHorde = function(amount, _, admin)
			local position = adminPosition(admin)
			if not position or admin:GetAttribute("Mode") ~= "Extinction" then
				return "Nur in der offenen Welt."
			end
			amount = math.clamp(tonumber(amount) or 12, 1, 40)
			serverShared("ZombieService").SpawnAround(position, amount, 18, 45, nil, true)
			return amount .. " Zombies um dich herum"
		end,
		-- Items ins eigene Inventar (zum Testen): "Attachments" = je ein Aufsatz, "Throwables" = Granaten und Molotows,
		-- "Kit" = Sturmgewehr, Munition, Medikits, Westen
		ExtGive = function(kind, _, admin)
			if admin:GetAttribute("Mode") ~= "Extinction" then
				return "Nur in der offenen Welt."
			end
			local ExtinctionConfig = require(Shared.ExtinctionConfig)
			local InventoryService = serverShared("InventoryService")
			local list = {}
			if kind == "Attachments" then
				for _, id in ExtinctionConfig.AttachmentItems do
					table.insert(list, { id, 1 })
				end
			elseif kind == "Throwables" then
				list = { { "Grenade", 3 }, { "Molotov", 3 } }
			else
				list = { { "Rifle", 1 }, { "Ammo_Rifle", 120 }, { "Medkit", 3 }, { "HeavyVest", 1 }, { "Adrenaline", 2 } }
			end
			local given, missing = 0, 0
			for _, entry in list do
				local added = InventoryService.Give(admin, entry[1], entry[2])
				given += added
				missing += entry[2] - added
			end
			return "+" .. given .. " Items" .. (missing > 0 and (" (" .. missing .. " passten nicht in die Tasche)") or "")
		end,

		SetSetting = function(key, value)
			if typeof(key) ~= "string" or not GameSettings.Def(key) or typeof(value) ~= "number" then
				return "Ungültige Einstellung."
			end
			GameSettings.Set(key, value)
			return GameSettings.Def(key).Label .. " = " .. GameSettings.Get(key)
		end,
		ModeStart = function(modeId)
			local module = teamMode(modeId)
			return module and module.AdminStart() or "Unbekannter Modus."
		end,
		ModeEndRound = function(modeId)
			local module = teamMode(modeId)
			return module and module.AdminEndRound() or "Unbekannter Modus."
		end,
		ModeResetMatch = function(modeId)
			local module = teamMode(modeId)
			return module and module.AdminResetMatch() or "Unbekannter Modus."
		end,
		FFAEndRound = function()
			return ffa.AdminEndRound()
		end,
		MovePlayer = function(userId, modeId)
			local player = target(userId)
			if not player or typeof(modeId) ~= "string" then
				return "Spieler nicht gefunden."
			end
			manager.Join(player, modeId, true) -- Admin verschiebt auf diesem Server (kein Serverwechsel)
			return player.Name .. " -> " .. modeId
		end,
		SwitchTeam = function(userId)
			local player = target(userId)
			local module = player and teamMode(player:GetAttribute("Mode"))
			if not module then
				return "Spieler ist in keinem Team-Modus."
			end
			return module.AdminSwitchTeam(player)
		end,
		Kill = function(userId)
			local humanoid = humanoidOf(target(userId))
			if not humanoid then
				return "Spieler hat keinen Charakter."
			end
			humanoid.Health = 0
			return "Getötet."
		end,
		Heal = function(userId)
			local humanoid = humanoidOf(target(userId))
			if not humanoid then
				return "Spieler hat keinen Charakter."
			end
			humanoid.Health = humanoid.MaxHealth
			return "Geheilt."
		end,
		-- Bot in einen Modus schicken. teamName nur für Team-Modi ("Rot", "Blau" oder nil = automatisch);
		-- Extinction spawnt den Bot in der Nähe des Admins (draußen), sonst in der roten Zone
		SpawnBot = function(modeId, teamName, admin)
			local module = typeof(modeId) == "string" and manager.GetModule(modeId)
			if not module or not module.AddBot then
				return "Dieser Modus hat keine Bots."
			end
			local bot = BotService.Create(modeId)
			local ok, reason = module.AddBot(bot, typeof(teamName) == "string" and teamName or nil, admin)
			if not ok then
				BotService.Destroy(bot)
				return reason
			end
			return bot.Name .. " (" .. bot.Agent .. ") -> " .. modeId .. (bot.Team and (" · " .. bot.Team.Name) or "")
		end,
		-- Alle Bots entfernen (optional nur in einem Modus)
		RemoveBots = function(modeId)
			local removed = 0
			for _, bot in BotService.All(typeof(modeId) == "string" and modeId or nil) do
				local module = manager.GetModule(bot.Mode)
				if module and module.RemoveBot then
					module.RemoveBot(bot)
				end
				BotService.Destroy(bot)
				removed += 1
			end
			return removed .. " Bots entfernt."
		end,
		GiveCoins = function(userId, amount)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			amount = math.clamp(tonumber(amount) or 1000, 1, 1000000)
			ProgressService.AddCoins(player, amount)
			return player.Name .. " +" .. amount .. " Münzen"
		end,
		-- RAP (zweite Währung) zum Testen von Markt und Tausch
		GiveRap = function(userId, amount)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			amount = math.clamp(math.floor(tonumber(amount) or 10000), 1, 10000000)
			ProgressService.AddRap(player, amount)
			return player.Name .. " +" .. amount .. " RAP"
		end,
		-- Zufälliger handelbarer Skin (mit RAP-Wert), auch als weiteres Stück
		GiveTradeSkin = function(userId)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			local ids = {}
			for id in RapConfig.Values do
				table.insert(ids, id)
			end
			table.sort(ids)
			local id = ids[math.random(#ids)]
			ProgressService.GiveItem(player, id)
			return player.Name .. ": " .. Cosmetics.Get(id).Name .. " (" .. RapConfig.Value(id) .. " RAP)"
		end,
		-- ELO ändern: value = Zahl (+/- relativ), "max" = höchster Rang, "reset" = Start-ELO,
		-- "season" = Saison-Ende testen (Belohnung nach Peak, ELO-Rücksetzung)
		SetElo = function(userId, value)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			if value == "season" then
				ProgressService.TestSeasonEnd(player)
				return player.Name .. ": Saison-Ende getestet (ELO halbiert Richtung Start)"
			end
			local current = ProgressService.GetElo(player)
			local new
			if value == "max" then
				new = RankConfig.Tiers[#RankConfig.Tiers].Elo + 300
			elseif value == "reset" then
				new = RankConfig.StartElo
			else
				new = current + (tonumber(value) or 0)
			end
			local elo = ProgressService.SetElo(player, new)
			LeaderboardService.Submit(player)
			return player.Name .. ": " .. tostring(elo) .. " ELO (" .. RankConfig.Get(elo or 0).Display .. ")"
		end,
		-- Prestige setzen: value = Stufe (0..10), "max" = höchste Stufe auf Level 100, "level100" = Level 100
		SetPrestige = function(userId, value)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			local info = LevelConfig.Get(player)
			local prestige, level = info.Prestige, info.Level
			if value == "max" then
				prestige, level = LevelConfig.MaxPrestige, LevelConfig.MaxLevel
			elseif value == "level100" then
				level = LevelConfig.MaxLevel
			elseif value == "next" then
				prestige = math.min(prestige + 1, LevelConfig.MaxPrestige)
			else
				prestige, level = math.clamp(tonumber(value) or 0, 0, LevelConfig.MaxPrestige), 1
			end
			ProgressService.SetPrestige(player, prestige, level)
			return player.Name .. ": Prestige " .. prestige .. ", Level " .. level
		end,
		GivePassXP = function(userId, amount)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			amount = math.clamp(tonumber(amount) or 5000, 1, 1000000)
			ProgressService.AddPassXP(player, amount)
			return player.Name .. " +" .. amount .. " Pass-XP"
		end,
		GiveXP = function(userId, amount)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			amount = math.clamp(tonumber(amount) or 500, 1, 100000)
			local agentId = player:GetAttribute("Agent")
			ProgressService.AddXP(player, agentId, amount, "Admin")
			return player.Name .. " +" .. amount .. " XP (" .. tostring(agentId) .. ")"
		end,
	}

	Remotes.AdminAction.OnServerEvent:Connect(function(player, action, a, b)
		-- Noclip (frei fliegen, durch Wände): nur für den Admin selbst, Attribut Noclip (Client fliegt, MovementGuard
		-- lässt ihn in Ruhe, kein Schaden)
		if action == "Noclip" and player:GetAttribute("IsAdmin") then
			local on = not player:GetAttribute("Noclip")
			player:SetAttribute("Noclip", on or nil)
			Remotes.AdminStatus:FireClient(player, on and "Noclip AN (B = aus)" or "Noclip AUS")
			return
		end
		-- Tag/Nacht umschalten (offene Welt): Nacht -> 10 Uhr, Tag -> 22 Uhr; danach läuft der Tag normal weiter
		if action == "DayNight" and player:GetAttribute("IsAdmin") then
			local clock = DayCycle.Clock(workspace:GetServerTimeNow())
			local target = DayCycle.IsNight(clock) and 10 or 22
			DayCycle.SetClock(target)
			Remotes.AdminStatus:FireClient(player, target == 10 and "Jetzt Tag (10:00)" or "Jetzt Nacht (22:00)")
			return
		end
		-- Blutmond sofort starten / beenden (offene Welt)
		if action == "BloodMoon" and player:GetAttribute("IsAdmin") then
			local BloodMoonService = require(ServerStorage:WaitForChild("ServerShared").BloodMoonService)
			if BloodMoonService.Active() then
				BloodMoonService.Stop()
				Remotes.AdminStatus:FireClient(player, "Blutmond beendet")
			else
				BloodMoonService.Start()
				Remotes.AdminStatus:FireClient(player, "Blutmond gestartet (10 Minuten)")
			end
			return
		end
		if not player:GetAttribute("IsAdmin") or typeof(action) ~= "string" or not actions[action] then
			return
		end
		local ok, message = pcall(actions[action], a, b, player)
		Remotes.AdminStatus:FireClient(player, ok and tostring(message) or ("Fehler: " .. tostring(message)))
	end)

	local function onPlayerAdded(player)
		player:SetAttribute("IsAdmin", isAdmin(player))
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return AdminService

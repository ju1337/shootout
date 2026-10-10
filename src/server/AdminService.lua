-- AdminService (ModuleScript, nur Server)
-- Befehle aus dem Admin-Panel. Jeder Befehl wird hier geprüft: Admins (Attribut "IsAdmin") dürfen alles,
-- Moderatoren (Team-Rang mit Kick/BanDays/Unban, siehe StaffConfig) nur Kick, Sperren, die Sperrliste und die Suche,
-- und das nur gegen schwächere Ränge. Ränge und Admin-Status setzt StaffService.
-- Auch Admins können schwerwiegende Aktionen (Werte ändern, einfrieren, herholen, Daten zurücksetzen ...) nur gegen
-- schwächere Ränge oder sich selbst ausführen (TARGETED).
-- Umschalter DIESER SERVER / ALLE SERVER: Aktion "AllServers" (Aktion, { A, B }) führt Server-Aktionen aus GLOBAL hier
-- aus und schickt sie über MessagingService (Thema AdminGlobal) an alle anderen Server.
-- Jede Aktion landet im Admin-Log (die letzten LOG_SIZE, Reiter LOGS) und in den Discord-Logs (Moderation).

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local DiscordLog = require(game:GetService("ServerStorage"):WaitForChild("ServerShared").DiscordLog)
local GameSettings = require(Shared.GameSettings)
local LevelConfig = require(Shared.LevelConfig)
local RankConfig = require(Shared.RankConfig)
local RapConfig = require(Shared.RapConfig)
local Cosmetics = require(Shared.Cosmetics)
local DayCycle = require(Shared.DayCycle)
local Locale = require(Shared.Locale)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)
local LeaderboardService = require(ServerStorage:WaitForChild("ServerShared").LeaderboardService)
local BotService = require(script.Parent.BotService)
local SpawnUtil = require(script.Parent.SpawnUtil)

local StaffConfig = require(Shared.StaffConfig)
local StaffService = require(script.Parent.StaffService)

local AdminService = {}

-- Aktionen, die Moderatoren (ohne vollen Admin) benutzen dürfen
local MOD_ACTIONS = { Kick = true, Ban = true, Unban = true, BanList = true, Lookup = true }

-- Aktionen gegen einen Spieler (UserId als erster Wert), die nur gegen schwächere Ränge (oder sich selbst) gehen
local TARGETED = { PlayerValue = true, Bring = true, SendCamp = true, Freeze = true, Respawn = true, Kill = true,
	ResetData = true, HideLeaderboard = true, MovePlayer = true, SwitchTeam = true, Message = true }

-- Aktionen, die auf allen Servern laufen können (Umschalter ALLE SERVER); sie brauchen keinen Admin vor Ort
local GLOBAL = { Announce = true, ExtAirdrop = true, ExtConvoy = true, ExtHeliCrash = true, ExtHordeCrate = true,
	ExtBosses = true, ExtRedzone = true, ExtStop = true, BloodMoon = true, Storm = true, SetClock = true, SetFog = true,
	GiveAllCoins = true, DungeonStopAll = true }

AdminService.Topic = "AdminGlobal"
local LOG_SIZE = 150
local log = {} -- neueste zuerst: { At, Admin, Action, Target, Text }

-- Darf player diese Aktion? Gibt false und einen Grund zurück, wenn nicht.
local function allowed(player, action, a, b)
	local rank = StaffConfig.Of(player)
	if action == "SetRank" then
		local target = StaffConfig.Get(b)
		if not (rank and rank.Assign) then
			return false, "Keine Rechte, Ränge zu vergeben."
		elseif target and target.Power > rank.Assign then
			return false, "Diesen Rang darfst du nicht vergeben."
		elseif StaffService.StoredPower(a) >= rank.Power then
			return false, "Dieser Spieler hat einen gleich hohen oder höheren Rang."
		end
		return true
	end
	if player:GetAttribute("IsAdmin") and not MOD_ACTIONS[action] then
		if TARGETED[action] and rank and tonumber(a) ~= player.UserId and StaffService.StoredPower(a) >= rank.Power then
			return false, "Dieser Spieler hat einen gleich hohen oder höheren Rang."
		end
		return true
	end
	if not MOD_ACTIONS[action] then
		return false
	end
	if player:GetAttribute("IsAdmin") and not rank then
		return true -- Admin ohne sichtbaren Rang (StaffService.AdminIds)
	end
	if not rank then
		return false
	end
	if action == "BanList" or action == "Lookup" then
		return rank.Kick == true
	end
	if action == "Kick" and not rank.Kick then
		return false, "Keine Rechte zum Rauswerfen."
	end
	if action == "Unban" and not rank.Unban then
		return false, "Keine Rechte zum Entsperren."
	end
	if action == "Ban" then
		local days = math.floor(tonumber(type(b) == "table" and b.Days or b) or 0)
		if rank.BanDays == nil then
			return false, "Keine Rechte zum Sperren."
		elseif rank.BanDays > 0 and (days <= 0 or days > rank.BanDays) then
			return false, "Du darfst höchstens " .. rank.BanDays .. " Tage sperren."
		end
	end
	if (action == "Kick" or action == "Ban") and StaffService.StoredPower(a) >= rank.Power then
		return false, "Dieser Spieler hat einen gleich hohen oder höheren Rang."
	end
	return true
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

	-- Text eines Admins für andere Spieler (Ankündigung, Nachricht): gefiltert, höchstens 150 Zeichen
	local function filterText(admin, text)
		text = string.sub(tostring(text or ""), 1, 150)
		if text == "" then
			return nil
		end
		local ok, result = pcall(function()
			return game:GetService("TextService"):FilterStringAsync(text, admin.UserId):GetNonChatStringForBroadcastAsync()
		end)
		return ok and result or nil
	end

	local function rootOf(player)
		local humanoid = humanoidOf(player)
		local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		return humanoid and humanoid.Health > 0 and root or nil
	end

	-- Charakter von who neben die Stelle at (CFrame) setzen
	local function teleport(who, at)
		local character = who.Character
		local spot = at * CFrame.new(0, 0, 4)
		SpawnUtil.Prestream(who, spot.Position)
		character:PivotTo(spot)
		serverShared("MovementGuard").Teleported(character)
	end

	-- Werte eines Spielers (Reiter SPIELER, Kacheln oben): Name für die Rückmeldung, aktueller Wert, setzen
	local function levelOf(profile)
		return (LevelConfig.FromXP(profile.AccountXP or 0))
	end
	local VALUES = {
		Coins = { Name = "Münzen", Max = 1000000000, Get = function(profile)
			return profile.Coins or 0
		end, Set = function(_, profile, value)
			profile.Coins = value
		end },
		RedPoints = { Name = "RZ", Max = 10000000, Get = function(profile)
			return math.floor(tonumber(profile.RedPoints) or 0)
		end, Set = function(player, profile, value)
			profile.RedPoints = value
			serverShared("RedPointsService").Publish(player)
		end },
		Rap = { Name = "RAP", Max = 1000000000, Get = function(profile)
			return math.floor(tonumber(profile.Rap) or 0)
		end, Set = function(_, profile, value)
			profile.Rap = value
		end },
		XP = { Name = "XP", Max = LevelConfig.MaxXP, Get = function(profile)
			return profile.AccountXP or 0
		end, Set = function(_, profile, value)
			profile.AccountXP = value
		end },
		Level = { Name = "Level", Min = 1, Max = LevelConfig.MaxLevel, Get = levelOf, Set = function(player, profile, value)
			ProgressService.SetPrestige(player, profile.Prestige or 0, value)
		end },
		Prestige = { Name = "Prestige", Max = LevelConfig.MaxPrestige, Get = function(profile)
			return profile.Prestige or 0
		end, Set = function(player, profile, value)
			ProgressService.SetPrestige(player, value, levelOf(profile))
		end },
	}

	-- Jede Aktion gibt einen Text für das Panel zurück (admin = der Spieler, der den Befehl geschickt hat;
	-- nil, wenn die Aktion von einem anderen Server kommt, siehe GLOBAL)
	local actions = {
		-- ---------- Spieler (Reiter SPIELER: Detailansicht des gewählten Spielers) ----------
		-- Wert ändern: opts = { Key (VALUES), Op = "Add" | "Set", Amount }
		PlayerValue = function(userId, opts)
			local player = target(userId)
			local profile = player and ProgressService.Get(player)
			if not profile then
				return "Spieler nicht gefunden."
			elseif not ProgressService.IsLoaded(player) then -- nur das Ersatzprofil: Änderung ginge beim Laden verloren
				return "Spielstand lädt noch."
			end
			local def = type(opts) == "table" and VALUES[opts.Key]
			local amount = type(opts) == "table" and tonumber(opts.Amount)
			if not def or not amount or (opts.Op ~= "Add" and opts.Op ~= "Set") or amount ~= amount then
				return "Ungültiger Wert."
			end
			amount = math.clamp(math.floor(amount), -def.Max, def.Max)
			local value = opts.Op == "Add" and def.Get(profile) + amount or amount
			value = math.clamp(value, def.Min or 0, def.Max)
			def.Set(player, profile, value)
			ProgressService.Sync(player)
			return player.Name .. ": " .. def.Name .. " = " .. def.Get(profile)
		end,
		-- Item der offenen Welt in die Tasche (was nicht passt, ins Lager): opts = { Id, Count }
		GiveItem = function(userId, opts)
			local player = target(userId)
			local id = type(opts) == "table" and opts.Id
			local config = typeof(id) == "string" and ExtinctionConfig.Get(id)
			if not player then
				return "Spieler nicht gefunden."
			elseif not ProgressService.IsLoaded(player) then
				return "Spielstand lädt noch."
			elseif not config then
				return "Unbekanntes Item."
			end
			local count = math.clamp(math.floor(tonumber(opts.Count) or 1), 1, 999)
			local InventoryService = serverShared("InventoryService")
			local bag = InventoryService.Give(player, id, count)
			local stash = bag < count and InventoryService.GiveStash(player, id, count - bag) or 0
			local missing = count - bag - stash
			return player.Name .. ": +" .. (bag + stash) .. "× " .. config.Name .. (stash > 0 and (" (" .. stash .. " ins Lager)") or "")
				.. (missing > 0 and (" · " .. missing .. " passten nicht") or "")
		end,
		-- Skin (Cosmetics) geben, auch als weiteres Stück
		GiveSkin = function(userId, skinId)
			local player = target(userId)
			local item = typeof(skinId) == "string" and Cosmetics.Get(skinId)
			if not player then
				return "Spieler nicht gefunden."
			elseif not ProgressService.IsLoaded(player) then
				return "Spielstand lädt noch."
			elseif not item then
				return "Unbekannter Skin."
			end
			ProgressService.GiveItem(player, skinId)
			return player.Name .. ": Skin " .. item.Name
		end,
		-- Doppel-XP für minutes Minuten
		XPBoost = function(userId, minutes)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			elseif not ProgressService.IsLoaded(player) then
				return "Spielstand lädt noch."
			end
			minutes = math.clamp(math.floor(tonumber(minutes) or 30), 1, 1440)
			ProgressService.AddXPBoost(player, minutes)
			return player.Name .. ": Doppel-XP +" .. minutes .. " Min."
		end,
		-- Gottmodus an/aus (kein Schaden, Damage.Apply)
		God = function(userId)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			local on = not player:GetAttribute("AdminGod")
			player:SetAttribute("AdminGod", on or nil)
			return player.Name .. (on and ": Gottmodus AN" or ": Gottmodus AUS")
		end,
		-- Admin springt zum Spieler
		GoTo = function(userId, _, admin)
			local player = target(userId)
			local there, here = rootOf(player), rootOf(admin)
			if not there or not here then
				return "Spieler hat keinen Charakter."
			elseif player:GetAttribute("Mode") ~= admin:GetAttribute("Mode") then
				return "Nicht in derselben Welt."
			end
			teleport(admin, there.CFrame)
			return "Bei " .. player.Name
		end,
		-- Spieler zum Admin holen
		Bring = function(userId, _, admin)
			local player = target(userId)
			local there, here = rootOf(player), rootOf(admin)
			if not there or not here then
				return "Spieler hat keinen Charakter."
			elseif player:GetAttribute("Mode") ~= admin:GetAttribute("Mode") then
				return "Nicht in derselben Welt."
			end
			teleport(player, here.CFrame)
			return player.Name .. " geholt"
		end,
		-- Ins Camp: in der offenen Welt per Teleport (raus aus dem Dungeon), sonst in die offene Welt schicken
		SendCamp = function(userId)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			local extinction = manager.GetModule("Extinction")
			if player:GetAttribute("Mode") == "Extinction" and extinction and extinction.AdminToCamp then
				return extinction.AdminToCamp(player) and (player.Name .. " ist im Camp") or "Spieler hat keinen Charakter."
			end
			manager.Join(player, "Extinction", true)
			return player.Name .. " -> Camp"
		end,
		-- Einfrieren an/aus (Charakter verankert; endet mit dem nächsten Spawn)
		Freeze = function(userId)
			local player = target(userId)
			local root = rootOf(player)
			if not root then
				return "Spieler hat keinen Charakter."
			end
			local on = not player:GetAttribute("AdminFrozen")
			player:SetAttribute("AdminFrozen", on or nil)
			root.Anchored = on
			return player.Name .. (on and " eingefroren" or " aufgetaut")
		end,
		-- Neu spawnen (offene Welt: am Spawnpunkt, ohne Tod und ohne Taschenverlust)
		Respawn = function(userId)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			local extinction = manager.GetModule("Extinction")
			if not (extinction and extinction.AdminRespawn and extinction.AdminRespawn(player)) then
				player:LoadCharacter()
			end
			return player.Name .. " neu gespawnt"
		end,
		-- Vor den Bestenlisten verstecken an/aus (LeaderboardService)
		HideLeaderboard = function(userId)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			elseif not ProgressService.IsLoaded(player) then
				return "Spielstand lädt noch."
			end
			local hidden = not LeaderboardService.IsHidden(player)
			LeaderboardService.SetHidden(player, hidden)
			return player.Name .. (hidden and ": vor den Bestenlisten versteckt" or ": wieder in den Bestenlisten")
		end,
		-- Spielstand komplett zurücksetzen (nur mit confirm = "CONFIRM"), danach Kick zum Neu-Beitreten
		ResetData = function(userId, confirm)
			local player = target(userId)
			if confirm ~= "CONFIRM" then
				return "Nicht bestätigt."
			elseif not player then
				return "Spieler nicht gefunden."
			elseif not ProgressService.Reset(player) then
				return "Spielstand lädt noch."
			end
			local name = player.Name
			player:Kick(Locale.ForPlayer(player, "Dein Spielstand wurde von einem Admin zurückgesetzt. Bitte tritt neu bei."))
			return name .. ": Daten zurückgesetzt"
		end,
		-- Nachricht nur an diesen Spieler (Banner)
		Message = function(userId, text, admin)
			local player = target(userId)
			if not player then
				return "Spieler nicht gefunden."
			end
			text = filterText(admin, text)
			if not text then
				return "Nachricht eingeben."
			end
			Remotes.Notify:FireClient(player, "Banner", { Caption = "Nachricht vom Team", Title = "Nachricht", Sub = text,
				Style = "Info" })
			return "Nachricht an " .. player.Name .. " geschickt"
		end,
		-- Suche (auch offline): query = UserId oder Name. Daten an das Panel (AdminData "Lookup")
		Lookup = function(query, _, admin)
			local id = tonumber(query)
			if not id and typeof(query) == "string" and query ~= "" then
				local ok, result = pcall(Players.GetUserIdFromNameAsync, Players, query)
				id = ok and tonumber(result) or nil
			end
			if not id or id <= 0 then
				return "Spieler nicht gefunden."
			end
			local profile, online, err = ProgressService.Peek(id)
			local okName, name = pcall(Players.GetNameFromUserIdAsync, Players, id)
			local rank = StaffService.StoredRank(id)
			local ban = serverShared("BanService").Get(id)
			local stats = profile and type(profile.Stats) == "table" and profile.Stats or {}
			Remotes.AdminData:FireClient(admin, "Lookup", {
				UserId = id, Name = okName and name or ("#" .. id), Online = online == true, Found = profile ~= nil,
				Error = err, Rank = rank and rank.Id or nil,
				Ban = ban and { Reason = ban.Reason, Until = ban.Until, By = ban.By } or nil,
				Coins = profile and profile.Coins or 0, RedPoints = profile and math.floor(tonumber(profile.RedPoints) or 0) or 0,
				Rap = profile and math.floor(tonumber(profile.Rap) or 0) or 0, Level = profile and levelOf(profile) or 0,
				Prestige = profile and profile.Prestige or 0, Zombies = stats.Zombies or 0, Kills = stats.Kills or 0,
				Missions = stats.ExtMissions or 0, Hidden = profile ~= nil and profile.HideBoards == true,
			})
			return (okName and name or ("#" .. id)) .. (profile and "" or (" · " .. tostring(err or "kein Spielstand")))
		end,
		-- Admin-Log an das Panel (AdminData "Logs")
		Logs = function(_, _, admin)
			Remotes.AdminData:FireClient(admin, "Logs", log)
			return #log .. " Einträge"
		end,

		-- ---------- Server (auch auf allen Servern, siehe GLOBAL) ----------
		-- Ankündigung als Banner an alle
		-- Ankündigung als großes Banner an alle: der Text groß, darüber "Ankündigung · <Rang> <Name>". rank (optional) =
		-- Rang-Name des Absenders (bei ALLE SERVER von dort mitgeschickt)
		Announce = function(text, from, admin)
			if admin then
				text = filterText(admin, text)
				local rank = StaffConfig.Of(admin)
				from = (rank and (rank.Name .. " ") or "") .. admin.Name
			end
			if typeof(text) ~= "string" or text == "" then
				return "Text eingeben."
			end
			Remotes.Notify:FireAllClients("Banner", { Caption = "Ankündigung" .. (typeof(from) == "string" and from ~= ""
				and (" · " .. from) or ""), Title = text, Style = "Alert", Hold = 7 })
			return "Ankündigung gesendet"
		end,
		-- Uhrzeit der offenen Welt setzen (0..24)
		SetClock = function(hour)
			hour = tonumber(hour)
			if not hour then
				return "Ungültige Uhrzeit."
			end
			DayCycle.SetClock(math.clamp(hour, 0, 23.99))
			return "Uhrzeit " .. DayCycle.Label(math.clamp(hour, 0, 23.99))
		end,
		-- Nebel: Zahl 0..1 = fest, sonst wieder automatisch
		SetFog = function(value)
			value = tonumber(value)
			ReplicatedStorage:SetAttribute("FogOverride", value and math.clamp(value, 0, 1) or nil)
			return value and ("Nebel " .. math.floor(math.clamp(value, 0, 1) * 100) .. " %") or "Nebel automatisch"
		end,
		-- Allen Spielern auf dem Server Münzen geben
		GiveAllCoins = function(amount)
			amount = math.clamp(math.floor(tonumber(amount) or 0), 1, 1000000)
			local count = 0
			for _, player in Players:GetPlayers() do
				if ProgressService.IsLoaded(player) then -- nicht ins Ersatzprofil (ginge beim Laden verloren)
					ProgressService.AddCoins(player, amount, "Admin")
					count += 1
				end
			end
			return count .. " Spieler +" .. amount .. " Münzen"
		end,
		-- Alle Dungeon-Läufe beenden
		DungeonStopAll = function()
			return serverShared("DungeonService").StopAll() .. " Dungeon-Läufe beendet"
		end,
		-- Blutmond / Sturmnacht: mode = "Start", "Stop" oder nil (umschalten)
		BloodMoon = function(mode)
			local BloodMoonService = serverShared("BloodMoonService")
			if mode == "Stop" or (mode ~= "Start" and BloodMoonService.Active()) then
				BloodMoonService.Stop()
				return "Blutmond beendet"
			end
			BloodMoonService.Start()
			return "Blutmond gestartet (10 Minuten)"
		end,
		Storm = function(mode)
			local StormService = serverShared("StormService")
			if mode == "Stop" or (mode ~= "Start" and StormService.Active()) then
				StormService.Stop()
				return "Sturmnacht beendet"
			end
			StormService.Start()
			return "Sturmnacht gestartet (10 Minuten)"
		end,

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
		ExtBosses = function()
			local BossService = serverShared("BossService")
			local names = {}
			for id, boss in BossService.All() do
				if BossService.SpawnNow(id) then
					table.insert(names, boss.Config.Name)
				end
			end
			return #names > 0 and ("Boss da: " .. table.concat(names, ", ")) or "Kein Boss (Ort fehlt auf der Karte?)"
		end,
		ExtBountyMe = function(_, _, admin)
			if admin:GetAttribute("Mode") ~= "Extinction" then
				return "Nur in der offenen Welt."
			end
			local bounty = serverShared("BountyService").Force(admin)
			return bounty and ("Kopfgeld auf dich: " .. bounty.Reward .. " Münzen") or "Kopfgeld ging nicht."
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
		-- Event sofort beenden: which = "Airdrop", "Convoy", "HeliCrash", "HordeCrate", "BloodMoon", "Storm", "Bounty",
		-- "Zombies" (alle entfernen) oder "All" (alles davon)
		ExtStop = function(which)
			local done = {}
			local function stop(name, label, fn)
				if which == name or which == "All" then
					local result = fn()
					if result == true or (type(result) == "number" and result > 0) then
						table.insert(done, label .. (type(result) == "number" and (" (" .. result .. ")") or ""))
					end
				end
			end
			local DayCycle = require(Shared.DayCycle)
			local now = workspace:GetServerTimeNow()
			stop("Airdrop", "Lootdrop", function()
				return serverShared("AirdropService").Stop()
			end)
			stop("Convoy", "Konvoi", function()
				return serverShared("ConvoyService").Stop()
			end)
			stop("HeliCrash", "Heli-Absturz", function()
				return serverShared("HeliCrashService").Stop()
			end)
			stop("HordeCrate", "Horden-Kiste", function()
				return serverShared("HordeService").Stop()
			end)
			stop("BloodMoon", "Blutmond", function()
				local active = DayCycle.IsBloodMoon(now)
				serverShared("BloodMoonService").Stop()
				return active
			end)
			stop("Storm", "Sturmnacht", function()
				local active = DayCycle.IsStorm(now)
				serverShared("StormService").Stop()
				return active
			end)
			stop("Bounty", "Kopfgeld", function()
				return serverShared("BountyService").Stop()
			end)
			stop("Zombies", "Zombies", function()
				return serverShared("ZombieService").ClearAll()
			end)
			return #done > 0 and ("Beendet: " .. table.concat(done, ", ")) or "Da lief nichts."
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
			elseif kind == "DungeonKey" then
				list = { { ExtinctionConfig.Dungeon.KeyItem, 1 } }
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

		-- Rote-Zone-Punkte (RZ) für sich selbst, zum Testen des Schiebers: amount aus dem Eingabefeld (1..1.000.000)
		-- Sperrliste (BanService): Kick(userId, Grund), Ban(userId, { Days, Reason }), Unban(userId), BanList
		Kick = function(userId, reason, admin)
			return serverShared("BanService").Kick(admin, userId, reason)
		end,
		Ban = function(userId, options, admin)
			local days = type(options) == "table" and options.Days or options
			local reason = type(options) == "table" and options.Reason or nil
			local result = serverShared("BanService").Ban(admin, userId, days, reason)
			Remotes.AdminData:FireClient(admin, "Bans", serverShared("BanService").List())
			return result
		end,
		Unban = function(userId, _, admin)
			local result = serverShared("BanService").Unban(admin, userId)
			Remotes.AdminData:FireClient(admin, "Bans", serverShared("BanService").List())
			return result
		end,
		-- Team-Rang vergeben (StaffService): rankId nil = Rang entfernen
		SetRank = function(userId, rankId)
			return StaffService.Assign(userId, rankId)
		end,
		BanList = function(_, _, admin)
			local bans = serverShared("BanService").List()
			Remotes.AdminData:FireClient(admin, "Bans", bans)
			return #bans .. " Sperren"
		end,
		GiveRedPoints = function(amount, _, admin)
			amount = math.floor(tonumber(amount) or 0)
			if amount < 1 then
				return "Ungültige Menge."
			end
			amount = math.min(amount, 1000000)
			if not serverShared("RedPointsService").Add(admin, amount) then
				return "Kein Spielstand geladen."
			end
			return "+" .. amount .. " RZ (jetzt " .. serverShared("RedPointsService").Get(admin) .. ")"
		end,

		-- Shop-Angebote (ShopOfferService, alle Server): Skin, { Discount, Hours, Featured } / beenden / Tagesangebot an-aus
		ShopOfferAdd = function(itemId, options, admin)
			return serverShared("ShopOfferService").Add(admin, itemId, options)
		end,
		ShopOfferRemove = function(itemId, _, admin)
			return serverShared("ShopOfferService").Remove(admin, itemId)
		end,
		ShopOfferAuto = function(on, _, admin)
			return serverShared("ShopOfferService").SetAuto(admin, on)
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
		-- Umschalter ALLE SERVER: hier ausführen und an alle anderen Server schicken
		if action == "AllServers" then
			local inner, args = a, type(b) == "table" and b or {}
			if typeof(inner) ~= "string" or not GLOBAL[inner] or not actions[inner] then
				return
			end
			local ok, reason = allowed(player, inner, args.A, args.B)
			if not ok then
				if reason then
					Remotes.AdminStatus:FireClient(player, reason)
				end
				return
			end
			local valueA, valueB = args.A, args.B
			if inner == "Announce" then
				local rank = StaffConfig.Of(player)
				valueB = (rank and (rank.Name .. " ") or "") .. player.Name -- Absender für die anderen Server
				valueA = filterText(player, valueA) -- einmal hier filtern, die anderen Server zeigen den Text nur an
				if not valueA then
					Remotes.AdminStatus:FireClient(player, "Text eingeben.")
					return
				end
			end
			local okRun, message = pcall(actions[inner], valueA, valueB, nil)
			message = okRun and tostring(message) or ("Fehler: " .. tostring(message))
			task.spawn(pcall, MessagingService.PublishAsync, MessagingService, AdminService.Topic,
				{ Action = inner, A = valueA, B = valueB, Server = game.JobId, By = player.Name })
			Remotes.AdminStatus:FireClient(player, "Alle Server: " .. message)
			AdminService.Record(player.Name, inner .. " (alle Server)", valueA, message)
			DiscordLog.Log("Moderation", "Admin: " .. inner .. " (alle Server)", message,
				{ { "Admin", DiscordLog.Who(player) }, { "Wert 1", tostring(valueA) }, { "Wert 2", tostring(args.B) } })
			return
		end
		if typeof(action) ~= "string" or not actions[action] then
			return
		end
		local ok, reason = allowed(player, action, a, b)
		if not ok then
			if reason then
				Remotes.AdminStatus:FireClient(player, reason)
			end
			return
		end
		local okRun, message = pcall(actions[action], a, b, player)
		message = okRun and tostring(message) or ("Fehler: " .. tostring(message))
		Remotes.AdminStatus:FireClient(player, message)
		if action ~= "Logs" and action ~= "BanList" then
			AdminService.Record(player.Name, action, a, message)
		end
		DiscordLog.Log("Moderation", "Admin: " .. action, message,
			{ { "Admin", DiscordLog.Who(player) }, { "Wert 1", tostring(a) }, { "Wert 2", tostring(b) } })
	end)

	-- Aktionen von anderen Servern (ALLE SERVER)
	task.spawn(pcall, MessagingService.SubscribeAsync, MessagingService, AdminService.Topic, function(message)
		local data = type(message) == "table" and message.Data
		if type(data) ~= "table" or data.Server == game.JobId or not GLOBAL[data.Action] or not actions[data.Action] then
			return
		end
		local ok, result = pcall(actions[data.Action], data.A, data.B, nil)
		AdminService.Record(tostring(data.By) .. " (anderer Server)", data.Action, data.A, ok and tostring(result) or "Fehler")
	end)

	-- Einfrieren endet mit dem nächsten Spawn
	local function watch(player)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("AdminFrozen", nil)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

-- Eintrag ins Admin-Log (neueste zuerst, höchstens LOG_SIZE)
function AdminService.Record(adminName, action, targetValue, text)
	local targetPlayer = Players:GetPlayerByUserId(tonumber(targetValue) or 0)
	table.insert(log, 1, { At = os.time(), Admin = tostring(adminName), Action = tostring(action),
		Target = targetPlayer and targetPlayer.Name or (targetValue ~= nil and typeof(targetValue) ~= "table" and tostring(targetValue) or ""),
		Text = string.sub(tostring(text), 1, 200) })
	while #log > LOG_SIZE do
		table.remove(log)
	end
end

function AdminService.Log()
	return log
end

return AdminService

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
local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)
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
	local drop = manager.GetModule("Drop")
	local ffa = manager.GetModule("FreeForAll")

	local function target(userId)
		return Players:GetPlayerByUserId(tonumber(userId) or 0)
	end

	local function humanoidOf(player)
		return player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	end

	-- Jede Aktion gibt einen Text für das Panel zurück
	local actions = {
		SetSetting = function(key, value)
			if typeof(key) ~= "string" or not GameSettings.Def(key) or typeof(value) ~= "number" then
				return "Ungültige Einstellung."
			end
			GameSettings.Set(key, value)
			return GameSettings.Def(key).Label .. " = " .. GameSettings.Get(key)
		end,
		DropStart = function()
			return drop.AdminStart()
		end,
		DropEndRound = function()
			return drop.AdminEndRound()
		end,
		DropResetMatch = function()
			return drop.AdminResetMatch()
		end,
		FFAEndRound = function()
			return ffa.AdminEndRound()
		end,
		MovePlayer = function(userId, modeId)
			local player = target(userId)
			if not player or typeof(modeId) ~= "string" then
				return "Spieler nicht gefunden."
			end
			manager.Join(player, modeId)
			return player.Name .. " -> " .. modeId
		end,
		SwitchTeam = function(userId)
			local player = target(userId)
			return player and drop.AdminSwitchTeam(player) or "Spieler nicht gefunden."
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
		-- Bot in einen Modus schicken. teamName nur für Drop ("Rot", "Blau" oder nil = automatisch)
		SpawnBot = function(modeId, teamName)
			local module = typeof(modeId) == "string" and manager.GetModule(modeId)
			if not module or not module.AddBot then
				return "Dieser Modus hat keine Bots."
			end
			local bot = BotService.Create(modeId)
			local ok, reason = module.AddBot(bot, typeof(teamName) == "string" and teamName or nil)
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
		if not player:GetAttribute("IsAdmin") or typeof(action) ~= "string" or not actions[action] then
			return
		end
		local ok, message = pcall(actions[action], a, b)
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

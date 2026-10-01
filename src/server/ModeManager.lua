-- ModeManager (ModuleScript, nur Server)
-- Verwaltet, welcher Spieler in welchem Modus ist (Hub, Free-for-All, Drop).
-- Ersetzt den Teleport: Moduswechsel = Spieler in den Bereich des Modus setzen.
-- Spieler-Attribute: Mode (Id), CanFight (darf schießen/Fähigkeit), ModeText (Info oben im HUD)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local KillService = require(ServerStorage:WaitForChild("ServerShared").KillService)

local ModeManager = {}

-- Logik pro Modus (Ids wie in Modes.lua)
local modules = {
	Hub = require(script.Parent.Modes.Hub),
	FreeForAll = require(script.Parent.Modes.FreeForAll),
	Drop = require(script.Parent.Modes.Drop),
	Strikeout = require(script.Parent.Modes.Strikeout),
	Demolition = require(script.Parent.Modes.Demolition),
	Wingman = require(script.Parent.Modes.Wingman),
	Training = require(script.Parent.Modes.Training),
	Ranked = require(script.Parent.Modes.Ranked),
	Arena = require(script.Parent.Modes.Arena),
}

local switching = {} -- verhindert doppelte Wechsel gleichzeitig

-- Logik-Modul eines Modus (für das Admin-Panel)
function ModeManager.GetModule(modeId)
	return modules[modeId]
end

function ModeManager.Status(player, text)
	Remotes.MenuStatus:FireClient(player, text)
end

-- Spieler in einen Modus schicken (ersetzt den Teleport)
function ModeManager.Join(player, modeId)
	local info = Modes.Get(modeId)
	local module = modules[modeId]
	if not info or switching[player] then
		return
	end
	if not info.Available or not module then
		ModeManager.Status(player, info.Name .. " kommt bald.")
		return
	end
	local current = player:GetAttribute("Mode")
	if current == modeId then
		ModeManager.Status(player, "Du bist bereits in " .. info.Name .. ".")
		return
	end
	local ok, reason = module.CanJoin(player)
	if not ok then
		ModeManager.Status(player, reason)
		return
	end

	switching[player] = true
	if current and modules[current] then
		modules[current].RemovePlayer(player)
	end
	player.Team = nil
	player:SetAttribute("CanFight", false)
	player:SetAttribute("ModeText", "")
	KillService.ResetPlayer(player)
	player:SetAttribute("Mode", modeId)
	module.AddPlayer(player)
	switching[player] = nil
end

function ModeManager.Init()
	for _, module in modules do
		module.Init(ModeManager)
	end

	Remotes.JoinMode.OnServerEvent:Connect(function(player, modeId)
		if typeof(modeId) == "string" then
			ModeManager.Join(player, modeId)
		end
	end)

	-- Kills an den Modus des Killers weitergeben
	KillService.KillCounted:Connect(function(killer, victim, kills)
		local module = modules[killer:GetAttribute("Mode")]
		if module and module.OnKill then
			module.OnKill(killer, victim, kills)
		end
	end)

	-- Neue Spieler starten im Hub
	local function onPlayerAdded(player)
		ModeManager.Join(player, "Hub")
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local module = modules[player:GetAttribute("Mode")]
		if module then
			module.RemovePlayer(player)
		end
		switching[player] = nil
	end)
end

return ModeManager

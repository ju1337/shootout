-- ModeManager (ModuleScript, nur Server)
-- Verwaltet, welcher Spieler in welchem Modus ist (offene Welt, Markt, Arcade-Modi). Start ist die Safe Zone der offenen
-- Welt (Modes.Home, Camp Phoenix mit dem Phönixplatz); einen eigenen Hub gibt es nicht mehr.
-- Moduswechsel = Spieler in den Bereich des Modus setzen. Nur für Arcade-Modi kann es vorher auf einen anderen Server
-- gehen, auf dem dort mehr Spieler sind (MatchmakingService); dort landet man direkt im Modus.
-- Solange Arcade aus ist (Modes.ArcadeEnabled), lehnt JoinMode Arcade-Modi und SCHNELLES SPIEL ab (der Spieler bleibt,
-- wo er ist); wer per Teleport mit einem Arcade-Modus ankommt, startet in Modes.Home. Admins (AdminService) dürfen
-- weiter direkt verschieben.
-- Spieler-Attribute: Mode (Id), CanFight (darf schießen/Fähigkeit), ModeText (Info oben im HUD)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local KillService = require(ServerShared.KillService)
local ProgressService = require(ServerShared.ProgressService)
local Telemetry = require(ServerShared.Telemetry)
local MatchmakingService = require(script.Parent.MatchmakingService)

local ModeManager = {}

-- Logik pro Modus (Ids wie in Modes.lua)
local modules = {
	Extinction = require(script.Parent.Modes.Extinction), -- offene Welt (Hauptmodus und Start, Modes.Home)
	Market = require(script.Parent.Modes.Market), -- Markthalle mit Ständen (kein Kampf)
	FreeForAll = require(script.Parent.Modes.FreeForAll),
	Domination = require(script.Parent.Modes.Domination),
	Wingman = require(script.Parent.Modes.Wingman),
	Training = require(script.Parent.Modes.Training),
	Arena = require(script.Parent.Modes.Arena),
	-- Ausgebaut (siehe Modes.Disabled): Drop, Strikeout, Demolition, Ranked, Extraction, TeamDeathmatch.
	-- Ihre Module bitte erst wieder laden, wenn ihre Maps wieder erzeugt werden (sonst warten sie ewig).
}

local switching = {} -- verhindert doppelte Wechsel gleichzeitig
local retries = {}   -- [Player] = fehlgeschlagene Wechsel in die offene Welt (neuer Versuch, höchstens 3)

-- Wird nach jedem erfolgreichen Moduswechsel gefeuert: (player, modeId) – z.B. für Squads
local joinedEvent = Instance.new("BindableEvent")
ModeManager.Joined = joinedEvent.Event

-- Logik-Modul eines Modus (für das Admin-Panel)
function ModeManager.GetModule(modeId)
	return modules[modeId]
end

function ModeManager.Status(player, text)
	Remotes.MenuStatus:FireClient(player, text)
end

-- Schnelles Spiel: Arcade-Modus mit den meisten Spielern (hier oder auf einem anderen Server), der noch Platz hat
-- (sonst Herrschaft)
local function quickMode(player)
	local size = #MatchmakingService.Group(player)
	local best, bestCount = "Domination", -1
	for _, modeId in Modes.Matchmaking.Modes do
		local module = modules[modeId]
		local count = -1
		if module and module.CanJoin(player) then
			count = 0
			for _, other in Players:GetPlayers() do
				if other:GetAttribute("Mode") == modeId then
					count += 1
				end
			end
		end
		local remote = MatchmakingService.Best(modeId, size)
		if remote and remote.Players > count then
			count = remote.Players
		end
		if count > bestCount then
			best, bestCount = modeId, count
		end
	end
	return best
end

-- Spieler in einen Modus schicken. here = true: auf diesem Server bleiben (Squad folgt dem Anführer, Ankunft per
-- Matchmaking, fehlgeschlagener Serverwechsel)
function ModeManager.Join(player, modeId, here)
	if switching[player] or player:GetAttribute("Teleporting") then
		return
	end
	if modeId == "Quick" then
		modeId = quickMode(player)
	end
	local info = Modes.Get(modeId)
	local module = modules[modeId]
	if not info then
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
	-- Der alte Modus darf nachfragen (offene Welt: außerhalb der Safe Zone kostet Verlassen die Tasche)
	local currentModule = current and modules[current]
	if currentModule and currentModule.ConfirmLeave and not currentModule.ConfirmLeave(player, modeId) then
		return
	end
	-- Arcade: lieber auf einen Server, auf dem in diesem Modus mehr Spieler sind (der Squad kommt mit)
	if not here and MatchmakingService.Route(player, modeId) then
		return
	end
	local ok, reason = module.CanJoin(player)
	if not ok then
		ModeManager.Status(player, reason)
		return
	end
	if switching[player] or player:GetAttribute("Mode") ~= current then
		return -- während der Suche schon woanders hin
	end

	switching[player] = true
	local ok, err = pcall(function()
		if current and modules[current] then
			modules[current].RemovePlayer(player)
		end
		player.Team = nil
		player:SetAttribute("CanFight", false)
		player:SetAttribute("ModeText", "")
		KillService.ResetPlayer(player)
		player:SetAttribute("Mode", modeId)
		module.AddPlayer(player)
	end)
	switching[player] = nil -- auch nach einem Fehler: sonst ginge für diesen Spieler bis zum Neubeitritt kein Wechsel mehr
	if not ok then
		warn("Moduswechsel nach " .. tostring(modeId) .. " fehlgeschlagen: " .. tostring(err))
		pcall(module.RemovePlayer, player) -- halb hinzugefügt: aufräumen
		player:SetAttribute("Mode", nil)
		-- die offene Welt ist das Zuhause: ein paar Mal neu versuchen statt ohne Charakter stehen zu bleiben
		retries[player] = (retries[player] or 0) + 1
		if modeId == Modes.Home and retries[player] <= 3 then
			task.delay(2, function()
				if player.Parent and player:GetAttribute("Mode") == nil then
					ModeManager.Join(player, Modes.Home, true)
				end
			end)
		end
		return
	end
	retries[player] = nil
	Telemetry.Event(player, "ModeJoin", 1, modeId)
	joinedEvent:Fire(player, modeId)
end

function ModeManager.Init()
	for _, module in modules do
		module.Init(ModeManager)
	end

	Remotes.JoinMode.OnServerEvent:Connect(function(player, modeId)
		if typeof(modeId) ~= "string" then
			return
		end
		-- Arcade aus: Arcade-Modi und SCHNELLES SPIEL nicht vom Client aus
		if not Modes.Joinable(modeId) then
			if modeId == "Quick" or Modes.IsArcade(modeId) then
				ModeManager.Status(player, "Arcade-Modi sind gerade nicht verfügbar.")
			end
			return
		end
		ModeManager.Join(player, modeId)
	end)

	-- Kills an den Modus des Killers weitergeben
	KillService.KillCounted:Connect(function(killer, victim, kills)
		local module = modules[killer:GetAttribute("Mode")]
		if module and module.OnKill then
			module.OnKill(killer, victim, kills)
		end
	end)

	-- Spielerzahlen pro Modus (für Menü-Karten und Einsatz-Tafel im Camp)
	task.spawn(function()
		local HttpService = game:GetService("HttpService")
		while true do
			local counts = {}
			for _, player in Players:GetPlayers() do
				local mode = player:GetAttribute("Mode")
				if mode then
					counts[mode] = (counts[mode] or 0) + 1
				end
			end
			game:GetService("ReplicatedStorage"):SetAttribute("ModeCounts", HttpService:JSONEncode(counts))
			task.wait(2)
		end
	end)

	-- Neue Spieler starten in der Safe Zone der offenen Welt; wer per Matchmaking kommt, gleich in seinem Arcade-Modus.
	-- Beides erst mit geladenem Spielstand (die offene Welt braucht Tasche und Lager; bis dahin bleibt der Ladebildschirm).
	local function onPlayerAdded(player)
		local modeId = MatchmakingService.Arrival(player)
		while player.Parent and not ProgressService.IsLoaded(player) do
			task.wait(0.25)
		end
		if not player.Parent or player:GetAttribute("Mode") ~= nil then
			return
		end
		if modeId and Modes.Joinable(modeId) then
			ModeManager.Join(player, modeId, true)
		end
		if player.Parent and player:GetAttribute("Mode") == nil then
			ModeManager.Join(player, Modes.Home)
		end
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
		retries[player] = nil
	end)
end

return ModeManager

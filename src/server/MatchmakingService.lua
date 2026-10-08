-- MatchmakingService (ModuleScript, nur Server)
-- Arcade über mehrere Server: Ohne das verteilen sich die Spieler jedes Servers auf alle Modi, und Arcade-Runden laufen
-- meist mit Bots. Darum meldet jeder öffentliche Server alle Modes.Matchmaking.Interval Sekunden in der MemoryStore-
-- Sorted-Map "ArcadeServers_v1" (Schlüssel = JobId, verfällt nach Expire Sekunden), wie viele echte Spieler in jedem
-- Arcade-Modus (Modes.Matchmaking.Modes) sind, wie viele Plätze dort frei sind und wie viele auf dem Server.
-- Will jemand in einen dieser Modi (auch SCHNELLES SPIEL), fragt ModeManager.Join zuerst Route: Gibt es einen anderen
-- Server, auf dem in diesem Modus mehr echte Spieler sind als hier und der Platz für den ganzen Squad hat, geht der Squad
-- per Teleport dorthin (TeleportData { Mode, Party }) und landet dort direkt im Modus, im selben Squad (Arrival). Sonst
-- wird wie bisher hier gespielt – so füllt sich ein Server, und die anderen schicken ihre Arcade-Spieler dorthin.
-- Aus: in Studio, auf privaten/reservierten Servern, ohne MemoryStore, wenn die Einstellung CrossServer 0 ist und für
-- Spieler, die gerade erst per Matchmaking gekommen sind (Cooldown). Schlägt der Teleport fehl, wird hier gespielt.
-- Spieler-Attribut "Teleporting" (true/nil): Teleport läuft, solange keine anderen Moduswechsel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modes = require(Shared.Modes)
local GameSettings = require(Shared.GameSettings)

local MatchmakingService = {}

local C = Modes.Matchmaking
local manager = nil
local options = nil   -- { Group(player) -> Spieler, die mitkommen; Regroup(player, party) }
local map = nil       -- Sorted Map aller Server (nil = aus)
local cache, cacheTime = {}, -math.huge
local cooldown = {}   -- [Player] = os.clock(), bis zu der nicht weitergeschickt wird
local teleporting = {} -- [Player] = Modus, solange der Teleport läuft

-- Wird dieser Modus server-übergreifend gefüllt?
function MatchmakingService.Handles(modeId)
	return table.find(C.Modes, modeId) ~= nil
end

local function active()
	return map ~= nil and GameSettings.Get("CrossServer") >= 1
end

-- Echte Spieler und freie Plätze eines Modus auf diesem Server
local function slots(modeId)
	local module = manager.GetModule(modeId)
	if module and module.Slots then
		return module.Slots()
	end
	local n = 0
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Mode") == modeId then
			n += 1
		end
	end
	return n, 0
end

-- Was dieser Server meldet
function MatchmakingService.Snapshot()
	local modes = {}
	for _, modeId in C.Modes do
		local players, free = slots(modeId)
		modes[modeId] = { P = players, F = free }
	end
	return { Place = game.PlaceId, Free = Players.MaxPlayers - #Players:GetPlayers(), Modes = modes }
end

local function publish()
	if map and active() then
		pcall(map.SetAsync, map, game.JobId, MatchmakingService.Snapshot(), C.Expire)
	end
end

-- Die anderen Server (kurz zwischengespeichert)
local function servers()
	if os.clock() - cacheTime < C.Cache then
		return cache
	end
	cacheTime = os.clock()
	cache = {}
	local ok, items = pcall(map.GetRangeAsync, map, Enum.SortDirection.Ascending, 200)
	if ok and type(items) == "table" then
		for _, item in items do
			local value = item.value
			if item.key ~= game.JobId and type(value) == "table" and value.Place == game.PlaceId and type(value.Modes) == "table" then
				table.insert(cache, { JobId = item.key, Free = tonumber(value.Free) or 0, Modes = value.Modes })
			end
		end
	end
	return cache
end

-- Bester anderer Server für modeId und size Spieler: mehr echte Spieler im Modus als hier, Platz im Modus und auf dem
-- Server. Gibt { JobId, Players } oder nil.
function MatchmakingService.Best(modeId, size)
	if not active() or not MatchmakingService.Handles(modeId) then
		return nil
	end
	local here = slots(modeId)
	local best = nil
	for _, server in servers() do
		local info = server.Modes[modeId]
		local players = type(info) == "table" and tonumber(info.P) or 0
		local free = type(info) == "table" and tonumber(info.F) or 0
		if players > here and free >= size and server.Free >= size and (not best or players > best.Players) then
			best = { JobId = server.JobId, Players = players }
		end
	end
	return best
end

-- Wer mit dem Spieler mitgeht (Squad-Anführer: sein Squad, sonst nur er)
function MatchmakingService.Group(player)
	local group = options and options.Group and options.Group(player) or { player }
	local out = {}
	for _, member in group do
		if member.Parent and not teleporting[member] then
			table.insert(out, member)
		end
	end
	if not table.find(out, player) then
		table.insert(out, 1, player)
	end
	return out
end

local function finish(player)
	teleporting[player] = nil
	if player.Parent then
		player:SetAttribute("Teleporting", nil)
	end
end

-- Teleport ist nicht zustande gekommen: hier spielen
local function fallback(player, why)
	local modeId = teleporting[player]
	if not modeId then
		return
	end
	finish(player)
	cooldown[player] = os.clock() + C.Cooldown
	if player.Parent then
		manager.Status(player, why)
		task.spawn(manager.Join, player, modeId, true)
	end
end

-- Spieler (mit seinem Squad) auf einen Server mit mehr Spielern in modeId schicken. true = Teleport läuft.
function MatchmakingService.Route(player, modeId)
	if not active() or not MatchmakingService.Handles(modeId) or teleporting[player]
		or (cooldown[player] or 0) > os.clock() then
		return false
	end
	local group = MatchmakingService.Group(player)
	local best = MatchmakingService.Best(modeId, #group)
	if not best then
		return false
	end
	local ids = {}
	for _, member in group do
		table.insert(ids, member.UserId)
	end
	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions.ServerInstanceId = best.JobId
	teleportOptions:SetTeleportData({ Mode = modeId, Party = #group > 1 and { Leader = player.UserId, Members = ids } or nil })
	local name = Modes.Get(modeId).Name
	for _, member in group do
		teleporting[member] = modeId
		member:SetAttribute("Teleporting", true)
		manager.Status(member, "Wechsle auf einen Server mit " .. best.Players .. " Spielern in " .. name .. " …")
	end
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, group, teleportOptions)
	if not ok then
		warn("Matchmaking: Teleport fehlgeschlagen: " .. tostring(err))
		cacheTime = -math.huge -- Liste neu holen, der Server ist vielleicht voll oder weg
		for _, member in group do
			finish(member) -- der Squad kommt hier wie gewohnt mit dem Anführer mit
		end
		cooldown[player] = os.clock() + C.Cooldown
		manager.Status(player, "Serverwechsel fehlgeschlagen – du spielst hier.")
		return false
	end
	-- Kommt der Teleport nicht an (und meldet keinen Fehler), nach TeleportTimeout Sekunden hier spielen
	for _, member in group do
		task.delay(C.TeleportTimeout, function()
			if teleporting[member] == modeId then
				fallback(member, "Serverwechsel dauert zu lange – du spielst hier.")
			end
		end)
	end
	return true
end

-- Per Matchmaking angekommen? Gibt den Modus zurück (oder nil); bildet den Squad wieder (Regroup)
function MatchmakingService.Arrival(player)
	local ok, data = pcall(player.GetJoinData, player)
	local teleportData = ok and type(data) == "table" and data.TeleportData
	if type(teleportData) ~= "table" or data.SourcePlaceId ~= game.PlaceId
		or not MatchmakingService.Handles(teleportData.Mode) then
		return nil
	end
	cooldown[player] = os.clock() + C.Cooldown -- nicht gleich wieder weiterschicken
	local party = teleportData.Party
	if type(party) == "table" and tonumber(party.Leader) and type(party.Members) == "table" and options and options.Regroup then
		options.Regroup(player, party)
	end
	return teleportData.Mode
end

-- opts = { Group(player) -> { Player }, Regroup(player, { Leader, Members }) }
function MatchmakingService.Init(modeManager, opts)
	manager = modeManager
	options = opts or {}
	Players.PlayerRemoving:Connect(function(player)
		teleporting[player] = nil
		cooldown[player] = nil
	end)
	TeleportService.TeleportInitFailed:Connect(function(player, _, message)
		if teleporting[player] then
			warn("Matchmaking: Teleport von " .. player.Name .. " fehlgeschlagen: " .. tostring(message))
			cacheTime = -math.huge
			fallback(player, "Serverwechsel fehlgeschlagen – du spielst hier.")
		end
	end)
	if RunService:IsStudio() or (game.PrivateServerId or "") ~= "" then
		return -- in Studio geht kein Teleport, private Server bleiben unter sich
	end
	local ok, result = pcall(MemoryStoreService.GetSortedMap, MemoryStoreService, C.MapName)
	if not ok then
		warn("Matchmaking aus: " .. tostring(result))
		return
	end
	map = result
	task.spawn(function()
		while true do
			publish()
			task.wait(C.Interval)
		end
	end)
	game:BindToClose(function()
		pcall(map.RemoveAsync, map, game.JobId)
	end)
end

return MatchmakingService

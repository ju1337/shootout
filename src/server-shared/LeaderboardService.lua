-- LeaderboardService (ModuleScript, nur Server)
-- Globale Bestenlisten (Top 10) über OrderedDataStores: ELO, Kills, Siege und Spielerlevel (inkl. Prestige).
-- Werte werden regelmäßig für alle Spieler eingetragen. Ohne DataStore (z.B. in Studio ohne API-Zugriff)
-- zeigen die Listen die Spieler auf dem Server, damit die Tafeln im Camp nie leer sind.
-- Ergebnis als JSON in ReplicatedStorage-Attributen "Leaderboard_<Name>": { { Name, UserId, Value }, ... }
-- Zusätzlich "RankedLeaderboard" ({ Name, Elo }) für das STATS-Fenster.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RankConfig = require(Shared.RankConfig)
local LevelConfig = require(Shared.LevelConfig)
local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)

local LeaderboardService = {}

local REFRESH = 60 -- Sekunden zwischen zwei Abfragen der Top 10
local SUBMIT = 120 -- Sekunden zwischen zwei Einträgen aller Spieler
local TOP = 10

-- Bestenlisten: Name -> Wert eines Profils
local BOARDS = {
	Elo = function(profile)
		return profile.Ranked and profile.Ranked.Elo or RankConfig.StartElo
	end,
	Kills = function(profile)
		return profile.Stats and profile.Stats.Kills or 0
	end,
	Wins = function(profile)
		return profile.Stats and profile.Stats.Wins or 0
	end,
	-- Level-Wert: Prestige * 1000 + Level (sortiert Prestige zuerst)
	Level = function(profile)
		return (profile.Prestige or 0) * 1000 + LevelConfig.FromXP(profile.AccountXP or 0)
	end,
}

local stores = {} -- [Name] = OrderedDataStore
local names = {}  -- [UserId] = Name (Cache)

local function nameOf(userId)
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = player and player.Name
	if not name then
		local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		name = ok and result or ("Spieler " .. userId)
	end
	names[userId] = name
	return name
end

local function submitPlayer(player)
	local profile = ProgressService.Get(player)
	if not profile then
		return
	end
	for board, getValue in BOARDS do
		local store = stores[board]
		if store then
			local value = math.floor(getValue(profile))
			task.spawn(function()
				local ok, err = pcall(store.SetAsync, store, tostring(player.UserId), value)
				if not ok then
					warn("Bestenliste " .. board .. ": Speichern fehlgeschlagen: " .. tostring(err))
				end
			end)
		end
	end
end

-- ELO nach einem Ranked-Match sofort eintragen (wird von TeamRoundMode aufgerufen)
function LeaderboardService.Submit(player)
	submitPlayer(player)
end

-- Ohne DataStore: Liste aus den Spielern auf dem Server
local function localList(getValue)
	local list = {}
	for _, player in Players:GetPlayers() do
		local profile = ProgressService.Get(player)
		if profile then
			table.insert(list, { Name = player.Name, UserId = player.UserId, Value = math.floor(getValue(profile)) })
		end
	end
	table.sort(list, function(a, b)
		return a.Value > b.Value
	end)
	while #list > TOP do
		table.remove(list)
	end
	return list
end

local function refresh()
	for board, getValue in BOARDS do
		local list
		local store = stores[board]
		if store then
			local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
			if ok then
				list = {}
				for _, entry in pages:GetCurrentPage() do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(list, { Name = nameOf(userId), UserId = userId, Value = entry.value })
					end
				end
			end
		end
		if not list or #list == 0 then
			list = localList(getValue)
		end
		ReplicatedStorage:SetAttribute("Leaderboard_" .. board, HttpService:JSONEncode(list))
		if board == "Elo" then
			local ranked = {}
			for _, entry in list do
				table.insert(ranked, { Name = entry.Name, Elo = entry.Value })
			end
			ReplicatedStorage:SetAttribute("RankedLeaderboard", HttpService:JSONEncode(ranked))
		end
	end
end

function LeaderboardService.Init()
	for board in BOARDS do
		local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService,
			board == "Elo" and "RankedElo_v1" or ("LB_" .. board .. "_v1"))
		if ok then
			stores[board] = result
		end
	end
	task.spawn(function()
		task.wait(5) -- Profile laden lassen
		while true do
			refresh()
			task.wait(REFRESH)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(SUBMIT)
			for _, player in Players:GetPlayers() do
				submitPlayer(player)
			end
		end
	end)
	-- Beim Verlassen noch einmal eintragen
	Players.PlayerRemoving:Connect(submitPlayer)
end

return LeaderboardService

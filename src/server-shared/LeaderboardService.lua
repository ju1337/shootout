-- LeaderboardService (ModuleScript, nur Server)
-- Globale Ranked-Bestenliste (Top 10 nach ELO) über einen OrderedDataStore.
-- Funktioniert erst im veröffentlichten Spiel mit API-Zugriff; sonst bleibt die Liste leer.
-- Ergebnis als JSON im ReplicatedStorage-Attribut "RankedLeaderboard": { { Name, Elo }, ... }

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardService = {}

local REFRESH = 60 -- Sekunden
local TOP = 10

local store = nil
local names = {} -- [UserId] = Name (Cache)

-- ELO eines Spielers eintragen (nach jedem Ranked-Match)
function LeaderboardService.Submit(player, elo)
	if not store then
		return
	end
	task.spawn(function()
		local ok, err = pcall(store.SetAsync, store, tostring(player.UserId), math.floor(elo))
		if not ok then
			warn("Bestenliste: Speichern fehlgeschlagen: " .. tostring(err))
		end
	end)
end

local function refresh()
	if not store then
		return
	end
	local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
	if not ok then
		return
	end
	local list = {}
	for _, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		local name = userId and names[userId]
		if userId and not name then
			local found, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			name = found and result or ("Spieler " .. entry.key)
			names[userId] = name
		end
		table.insert(list, { Name = name, Elo = entry.value })
	end
	ReplicatedStorage:SetAttribute("RankedLeaderboard", HttpService:JSONEncode(list))
end

function LeaderboardService.Init()
	local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "RankedElo_v1")
	if ok then
		store = result
	end
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardService

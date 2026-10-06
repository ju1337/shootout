-- RedzoneBoard (ModuleScript, nur Server)
-- Rangliste der roten Zonen (EXTINCTION): zählt Spieler-Kills (PvP) je Zone, jede Zone hat ihre eigene Liste. Ein Kill
-- zählt für die Zone, in der das Opfer stirbt, sonst für die des Schützen (Modes/Extinction ermittelt sie mit
-- RedzoneService.At). Die Wanderzone beginnt jede Runde neu: nach jedem Wechsel bei null (RedzoneService.OnMoved).
-- Wer die offene Welt verlässt, fällt aus allen Listen. Die Clients zeigen die Liste nur in der Zone selbst.
-- Für die Clients steht alles als JSON im Attribut "RedzoneBoard" an der Karte:
--   { Zones = { [Zonenname] = { Title, List } } },  List = { { Id = UserId, Name, Kills }, ... }
-- Zonenname wie im Spieler-Attribut "Redzone" (feste Zonen: Schlüssel aus Redzone_<Name>, sonst "Wanderzone").
-- Listen sind sortiert: meiste Kills zuerst, bei Gleichstand, wer die Zahl früher erreicht hat.

local HttpService = game:GetService("HttpService")

local RedzoneBoard = {}

local MAX_ENTRIES = 50 -- so viele Einträge je Liste gehen an die Clients (Platz des eigenen Eintrags)
local MOVING = "Wanderzone"

local map = nil
local boards = {} -- [Zonenname] = { Title, Entries = { [UserId] = { Id, Name, Kills, Order } } }
local order = 0 -- steigt mit jedem Kill (Gleichstand: kleinere Zahl = früher erreicht)

local function sorted(entries)
	local list = {}
	for _, entry in entries do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		if a.Kills ~= b.Kills then
			return a.Kills > b.Kills
		end
		return a.Order < b.Order
	end)
	local result = {}
	for i = 1, math.min(#list, MAX_ENTRIES) do
		result[i] = { Id = list[i].Id, Name = list[i].Name, Kills = list[i].Kills }
	end
	return result
end

local function publish()
	if not map then
		return
	end
	local zones = {}
	for name, board in boards do
		zones[name] = { Title = board.Title, List = sorted(board.Entries) }
	end
	map:SetAttribute("RedzoneBoard", HttpService:JSONEncode({ Zones = zones }))
end

-- map = Maps.Extinction, zones = RedzoneService.List() (feste Zonen stehen gleich mit leerer Liste drin)
function RedzoneBoard.Init(newMap, zones)
	map = newMap
	boards, order = {}, 0
	for _, zone in zones or {} do
		boards[zone.Name] = { Title = zone.Title, Entries = {} }
	end
	publish()
end

-- Kill von killer (Player) in zone (Eintrag aus RedzoneService.At) zählen; ohne Zone zählt nichts.
-- Gibt true zurück, wenn gezählt wurde.
function RedzoneBoard.Record(killer, zone)
	if not (zone and killer) then
		return false
	end
	local board = boards[zone.Name]
	if not board then
		board = { Title = zone.Title, Entries = {} }
		boards[zone.Name] = board
	end
	order += 1
	local entry = board.Entries[killer.UserId]
	if not entry then
		entry = { Id = killer.UserId, Name = killer.Name, Kills = 0 }
		board.Entries[killer.UserId] = entry
	end
	entry.Kills += 1
	entry.Order = order
	publish()
	return true
end

-- Wanderzone hat gewechselt (moving = neue Zone oder nil): neue Runde, leere Liste am neuen Ort
function RedzoneBoard.Moved(moving)
	boards[MOVING] = moving and { Title = moving.Title, Entries = {} } or nil
	publish()
end

-- Spieler verlässt die offene Welt: aus allen Listen nehmen
function RedzoneBoard.RemovePlayer(player)
	local changed = false
	for _, board in boards do
		if board.Entries[player.UserId] then
			board.Entries[player.UserId] = nil
			changed = true
		end
	end
	if changed then
		publish()
	end
end

-- Sortierte Liste einer Zone (Zonenname) – für Tests und Auswertungen
function RedzoneBoard.List(zoneName)
	local board = boards[zoneName]
	return board and sorted(board.Entries) or {}
end

return RedzoneBoard

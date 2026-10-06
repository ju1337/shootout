-- RedzoneBoard (ModuleScript, nur Server)
-- Rangliste der roten Zone (EXTINCTION): zählt Spieler-Kills (PvP) in der Zone. Jede Runde beginnt neu: alle 20 Minuten
-- zieht die Zone an einen anderen Ort (RedzoneService.OnMoved), dann steht die Liste wieder bei null. Ein Kill zählt, wenn
-- das Opfer in der Zone stirbt, sonst wenn der Schütze drin steht (Modes/Extinction ermittelt das mit RedzoneService.At).
-- Wer die offene Welt verlässt, fällt aus der Liste. Die Clients zeigen sie nur in der Zone selbst.
-- Für die Clients steht alles als JSON im Attribut "RedzoneBoard" an der Karte:
--   { Zones = { [Zonenname] = { Title, List } } },  List = { { Id = UserId, Name, Kills }, ... }
-- Zonenname wie im Spieler-Attribut "Redzone", Title = Ort der Zone in dieser Runde. Listen sind sortiert: meiste Kills
-- zuerst, bei Gleichstand, wer die Zahl früher erreicht hat.

local HttpService = game:GetService("HttpService")

local RedzoneBoard = {}

local MAX_ENTRIES = 50 -- so viele Einträge je Liste gehen an die Clients (Platz des eigenen Eintrags)

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

-- map = Maps.Extinction, zones = RedzoneService.List() (Zonen, die schon stehen, gleich mit leerer Liste)
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

-- Die rote Zone ist weitergezogen (zone = Zone am neuen Ort oder nil): neue Runde, leere Liste mit dem neuen Ort
function RedzoneBoard.Moved(zone)
	boards = {}
	if zone then
		boards[zone.Name] = { Title = zone.Title, Entries = {} }
	end
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

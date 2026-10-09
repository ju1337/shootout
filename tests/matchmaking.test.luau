-- Arcade über mehrere Server (MatchmakingService + ModeManager): jeder Server meldet seine Zahlen in der MemoryStore-Map;
-- wer in einen Arcade-Modus will, geht auf einen Server mit mehr echten Spielern dort (Platz im Modus und auf dem Server,
-- falscher Place zählt nicht), sonst hier; Squad-Anführer nimmt seinen Squad mit (Squad-Daten im Teleport), Mitglieder
-- folgen dem Anführer hier; Fehlschlag (sofort oder TeleportInitFailed) und Zeitüberschreitung: hier spielen, danach
-- eine Weile nicht weiterschicken; SCHNELLES SPIEL sieht die anderen Server; Ankunft: direkt in den Modus, Squad wieder
-- zusammen (nur gegenseitig), fremder Place zählt nicht; Einstellung CrossServer aus; alte Meldungen verfallen;
-- Extinction/Markt nie; Herunterfahren löscht die eigene Meldung
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Run(SIM.Now + (seconds or 1))
end

game.JobId = "server-1"
game.PlaceId = 777
local Remotes = require("Remotes")
local Modes = require("Modes")
local GameSettings = require("GameSettings")
local C = Modes.Matchmaking

-- Attrappen: Modi mit fester Platzzahl, KillService, Spielstand
local function fakeMode(id, capacity)
	local mode = { Id = id, Members = {} }
	local function count()
		local n = 0
		for _ in mode.Members do
			n += 1
		end
		return n
	end
	function mode.Init() end
	function mode.CanJoin()
		if count() >= capacity then
			return false, id .. " ist voll."
		end
		return true
	end
	function mode.AddPlayer(player)
		mode.Members[player] = true
	end
	function mode.RemovePlayer(player)
		mode.Members[player] = nil
	end
	function mode.Slots()
		return count(), capacity - count()
	end
	return mode
end
local fakes = {}
for id, capacity in { Extinction = 100, Market = 50, FreeForAll = 12, Domination = 10, Wingman = 4, Training = 10,
	Arena = 2 } do
	fakes[id] = fakeMode(id, capacity)
	SIM.Stub("ServerScriptService/Modes/" .. id, fakes[id])
end
local killCounted = Instance.new("BindableEvent")
SIM.Stub("KillService", { ResetPlayer = function() end, KillCounted = killCounted.Event })
local loadedProfiles = {}
SIM.Stub("ProgressService", { IsLoaded = function(player)
	return loadedProfiles[player] ~= false
end })

-- Andere Server in der Sorted Map (wie sie sie selbst melden würden)
local servers = SIM.MemoryStore(C.MapName)
local function remote(jobId, place, free, modes)
	servers.Items[jobId] = { Value = { Place = place, Free = free, Modes = modes }, Expires = SIM.Now + C.Expire }
end
remote("server-2", 777, 10, { Domination = { P = 3, F = 5 }, FreeForAll = { P = 1, F = 11 } })
remote("server-3", 777, 10, { FreeForAll = { P = 5, F = 0 } })   -- Free-for-All voll
remote("server-4", 777, 1, { Wingman = { P = 3, F = 1 } })       -- nur ein Platz auf dem Server
remote("server-5", 999, 30, { Arena = { P = 1, F = 1 } })        -- anderes Spiel/Place

local ModeManager = require("ModeManager")
local PartyService = require("PartyService")
local MatchmakingService = require("MatchmakingService")
PartyService.Init(ModeManager)
MatchmakingService.Init(ModeManager, { Group = PartyService.Followers, Regroup = PartyService.Regroup })
ModeManager.Init()
local TeleportService = game:GetService("TeleportService")

local function status(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "MenuStatus" and entry.Player == player then
			return entry.Args[1]
		end
	end
	return nil
end
local function join(player, modeId)
	Remotes.JoinMode.OnServerEvent:Fire(player, modeId)
	step(0.5)
end
local function lastTeleport()
	return SIM.Teleports[#SIM.Teleports]
end

local alice, bob, carl = SIM.Join("Alice"), SIM.Join("Bob"), SIM.Join("Carl")
step(C.Interval)
check(alice:GetAttribute("Mode") == "Extinction", "neue Spieler in der offenen Welt (Camp)")
local own = servers.Items["server-1"]
check(own and own.Value.Place == 777 and own.Value.Modes.Domination.P == 0 and own.Value.Modes.Domination.F == 10
	and own.Value.Free == game:GetService("Players").MaxPlayers - 3, "Server meldet seine Zahlen")
check(own and own.Value.Modes.Extinction == nil, "nur Arcade-Modi")
check(own and own.Expires - SIM.Now <= C.Expire, "Meldung verfällt")

-- Herrschaft: auf server-2 sind 3 Spieler, hier keiner -> Alice wechselt
join(alice, "Domination")
local teleport = lastTeleport()
check(teleport and teleport.PlaceId == 777 and teleport.Options.ServerInstanceId == "server-2" and #teleport.Players == 1
	and teleport.Players[1] == alice, "Alice geht auf server-2")
local data = teleport and teleport.Options:GetTeleportData()
check(data and data.Mode == "Domination" and data.Party == nil, "Teleport-Daten: Modus, kein Squad")
check(alice:GetAttribute("Mode") == "Extinction" and alice:GetAttribute("Teleporting") == true, "bis zum Teleport im Camp")
check(string.find(status(alice) or "", "3 Spielern", 1, true) ~= nil, "Meldung: " .. tostring(status(alice)))
local count = #SIM.Teleports
join(alice, "Wingman")
check(#SIM.Teleports == count and alice:GetAttribute("Mode") == "Extinction", "während des Teleports kein anderer Wechsel")

-- Free-for-All: server-3 ist voll, server-2 hat nur 1 (nicht mehr als hier, wenn hier schon jemand ist)
join(bob, "FreeForAll")
teleport = lastTeleport()
check(#SIM.Teleports == count + 1 and teleport.Options.ServerInstanceId == "server-2", "Bob: nicht auf den vollen server-3, aber server-2 (1 > 0)")
SIM.Teleports = {}
fakes.FreeForAll.Members[carl] = true -- hier ist jetzt auch einer
carl:SetAttribute("Mode", "FreeForAll")
local dana = SIM.Join("Dana")
step(1)
join(dana, "FreeForAll")
check(#SIM.Teleports == 0 and dana:GetAttribute("Mode") == "FreeForAll", "gleich viele hier wie dort: hier bleiben")

-- Wingman: server-4 hat nur einen Platz auf dem Server -> allein ja, als Squad zu zweit nein
local eve, finn = SIM.Join("Eve"), SIM.Join("Finn")
step(1)
finn:SetAttribute("InSafeZone", true) -- im Camp: kommt mit (draußen in der Welt bliebe er dort)
Remotes.PartyAction.OnServerEvent:Fire(eve, "Invite", finn.UserId)
Remotes.PartyAction.OnServerEvent:Fire(finn, "Accept", eve.UserId)
step(0.5)
check(PartyService.Leader(finn) == eve, "Eve führt den Squad")
join(eve, "Wingman")
check(#SIM.Teleports == 0 and eve:GetAttribute("Mode") == "Wingman" and finn:GetAttribute("Mode") == "Wingman",
	"Squad zu zweit passt nicht auf server-4: hier, Finn folgt")
-- Herrschaft als Squad: beide gehen zusammen, mit Squad-Daten
join(eve, "Extinction")
join(eve, "Domination")
teleport = lastTeleport()
check(teleport and #teleport.Players == 2 and table.find(teleport.Players, finn) ~= nil, "Squad geht zusammen")
data = teleport and teleport.Options:GetTeleportData()
check(data and data.Party and data.Party.Leader == eve.UserId and #data.Party.Members == 2, "Squad in den Teleport-Daten")
check(finn:GetAttribute("Teleporting") == true, "auch Finn wartet auf den Teleport")
-- ein Mitglied wählt selbst: geht allein (Squad-Mitglieder werden nur vom Anführer mitgenommen)
check(#MatchmakingService.Group(finn) == 1, "Mitglied: nur er selbst")

-- Teleport schlägt sofort fehl: hier spielen, eine Weile nicht weiterschicken
local gus = SIM.Join("Gus")
step(1)
SIM.Teleports = {}
SIM.TeleportFail = 1
join(gus, "Domination")
check(gus:GetAttribute("Mode") == "Domination" and gus:GetAttribute("Teleporting") == nil, "Fehlschlag: Gus spielt hier")
join(gus, "Extinction")
join(gus, "Domination")
check(#SIM.Teleports == 0 and gus:GetAttribute("Mode") == "Domination", "nach einem Fehlschlag erst einmal hier")
-- TeleportInitFailed (Server voll): Alice spielt hier
TeleportService.TeleportInitFailed:Fire(alice, Enum.TeleportResult.GameFull, "voll")
step(0.5)
check(alice:GetAttribute("Mode") == "Domination" and alice:GetAttribute("Teleporting") == nil, "TeleportInitFailed: Alice spielt hier")
-- Teleport kommt nie an: nach TeleportTimeout hier
step(C.TeleportTimeout + 1)
check(eve:GetAttribute("Mode") == "Domination" and finn:GetAttribute("Mode") == "Domination", "Zeitüberschreitung: Squad spielt hier")

-- SCHNELLES SPIEL: Wingman auf server-6 mit 6 Spielern schlägt alles hier
remote("server-6", 777, 10, { Wingman = { P = 3, F = 1 }, Arena = { P = 0, F = 2 } })
servers.Items["server-6"].Value.Modes.Domination = { P = 8, F = 2 }
local hank = SIM.Join("Hank")
step(C.Cache + 1)
SIM.Teleports = {}
join(hank, "Quick")
teleport = lastTeleport()
data = teleport and teleport.Options:GetTeleportData()
check(teleport and teleport.Options.ServerInstanceId == "server-6" and data.Mode == "Domination",
	"Schnelles Spiel: Herrschaft auf server-6 (8 Spieler)")

-- Offene Welt und Markt bleiben immer hier
local ivy = SIM.Join("Ivy")
step(1)
SIM.Teleports = {}
join(ivy, "Extinction")
join(ivy, "Market")
check(#SIM.Teleports == 0 and ivy:GetAttribute("Mode") == "Market", "Extinction und Markt: kein Serverwechsel")

-- Einstellung aus: alles hier
GameSettings.Set("CrossServer", 0)
join(ivy, "Domination")
check(#SIM.Teleports == 0 and ivy:GetAttribute("Mode") == "Domination", "CrossServer = 0: hier")
GameSettings.Set("CrossServer", 1)

-- Ankunft per Matchmaking: direkt in den Modus, Squad wieder zusammen (nur, wer sich gegenseitig nennt)
SIM.JoinData[901] = { SourcePlaceId = 777, TeleportData = { Mode = "Arena", Party = { Leader = 901, Members = { 901, 902 } } } }
SIM.JoinData[902] = { SourcePlaceId = 777, TeleportData = { Mode = "Arena", Party = { Leader = 901, Members = { 901, 902 } } } }
SIM.JoinData[903] = { SourcePlaceId = 777, TeleportData = { Mode = "Arena", Party = { Leader = 901, Members = { 903 } } } }
SIM.JoinData[904] = { SourcePlaceId = 555, TeleportData = { Mode = "Arena" } }
local member = SIM.AddPlayer("Member", 902)
step(0.5)
local leader = SIM.AddPlayer("Leader", 901)
step(0.5)
local intruder = SIM.AddPlayer("Intruder", 903)
local stranger = SIM.AddPlayer("Stranger", 904)
step(1)
check(leader:GetAttribute("Mode") == "Arena" and member:GetAttribute("Mode") == "Arena", "Ankunft: direkt in der Arena")
check(PartyService.Leader(member) == leader and leader:GetAttribute("SquadId") == member:GetAttribute("SquadId"),
	"Squad nach dem Wechsel wieder zusammen")
check(PartyService.Leader(intruder) == nil, "wer nicht in der Liste des Anführers steht, kommt nicht in den Squad")
check(stranger:GetAttribute("Mode") == "Extinction", "Teleport aus einem anderen Spiel zählt nicht")
-- Angekommene werden nicht gleich wieder weitergeschickt
join(leader, "Extinction")
SIM.Teleports = {}
join(leader, "Domination")
check(#SIM.Teleports == 0, "gerade angekommen: nicht gleich weiter")

-- Alte Meldungen verfallen: ohne neue Meldung gibt es server-6 nach Expire Sekunden nicht mehr
step(C.Expire + 1)
local jack = SIM.Join("Jack")
step(C.Cache + 1)
SIM.Teleports = {}
join(jack, "Domination")
check(#SIM.Teleports == 0 and jack:GetAttribute("Mode") == "Domination", "verfallene Server zählen nicht")
check(servers.Items["server-1"] ~= nil, "die eigene Meldung wird erneuert")
local own2 = servers.Items["server-1"].Value
check(own2.Modes.Domination.P >= 5, "Meldung zählt die Spieler hier: " .. tostring(own2.Modes.Domination.P))

-- MemoryStore gestört: hier spielen
remote("server-7", 777, 10, { Wingman = { P = 3, F = 1 } })
step(C.Cache + 1)
servers.FailNext = 5
local kim = SIM.Join("Kim")
step(1)
servers.FailNext = 5
join(kim, "Wingman")
check(kim:GetAttribute("Mode") == "Wingman", "MemoryStore gestört: hier")

-- Herunterfahren: eigene Meldung weg
servers.FailNext = 0
for _, closer in SIM.Closers do
	closer()
end
check(servers.Items["server-1"] == nil, "Herunterfahren löscht die Meldung")

if failures == 0 then
	print("Matchmaking: alles in Ordnung")
end

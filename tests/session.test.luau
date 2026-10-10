-- Test der Sitzungssperre (SessionStore) mit nachgebautem DataStore und zwei Servern A und B (virtuelle Zeit)
local SessionStore = require("SessionStore")
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function deepcopy(v)
	if type(v) ~= "table" then
		return v
	end
	local t = {}
	for k, x in v do
		t[k] = deepcopy(x)
	end
	return t
end
-- DataStore: Anfrage braucht `latency` Sekunden hin und zurück; Lesen-Ändern-Schreiben ist atomar wie in Roblox.
-- failNext = so viele Aufrufe schlagen fehl (oder math.huge)
local function mockStore(latency)
	local store = { Data = {}, Calls = 0, FailNext = 0, Latency = latency or 0.5 }
	function store:UpdateAsync(key, fn)
		self.Calls += 1
		task.wait(self.Latency)
		if self.FailNext > 0 then
			self.FailNext -= 1
			error("DataStore-Anfrage fehlgeschlagen (simuliert)")
		end
		local new = fn(deepcopy(self.Data[key]))
		if new ~= nil then
			self.Data[key] = deepcopy(new)
		end
		task.wait(self.Latency)
		return new
	end
	return store
end
local function server(store, id)
	return SessionStore.new(store, { SessionId = id, Now = function() return math.floor(SIM.Now) end,
		Clock = function() return SIM.Now end })
end
local function run(name, fn)
	local done = false
	task.spawn(function()
		fn()
		done = true
	end)
	SIM.Run(SIM.Now + 600)
	check(done, name .. ": nicht fertig geworden")
	print((done and "ok   " or "?    ") .. name)
end

-- 1. Normal: A lädt (neu), speichert und gibt frei, B lädt den Stand
run("Laden, Speichern, Freigeben, Weiterladen", function()
	local store = mockStore()
	local A, B = server(store, "A"), server(store, "B")
	local status, data = A:Load("u1")
	check(status == "ok" and type(data) == "table", "A lädt neuen Spieler")
	check(store.Data.u1.Session.Id == "A", "A hält die Sperre")
	data.Coins = 100
	check(A:Save("u1", data, false) == "ok", "A speichert")
	check(store.Data.u1.Session.Id == "A", "Sperre bleibt beim Autosave")
	check(A:Save("u1", data, true) == "ok", "A speichert und gibt frei")
	check(store.Data.u1.Session == nil, "Sperre frei")
	local status2, data2 = B:Load("u1")
	check(status2 == "ok" and data2.Coins == 100, "B lädt Coins 100")
	check(data2.Session == nil, "Session nicht in den Spieldaten")
end)

-- 2. Schneller Serverwechsel: A speichert beim Verlassen (langsam), B lädt gleichzeitig -> B wartet, bekommt den neuen Stand
run("Schneller Serverwechsel", function()
	local store = mockStore(1.5)
	local A, B = server(store, "A"), server(store, "B")
	local _, data = A:Load("u1")
	data.Coins = 50
	A:Save("u1", data, false)
	data.Coins = 150 -- im Match verdient
	task.spawn(function()
		A:Save("u1", data, true) -- Spieler verlässt A
	end)
	local status, loaded = B:Load("u1") -- Spieler ist schon auf B
	check(status == "ok", "B lädt nach der Freigabe")
	check(loaded and loaded.Coins == 150, "B hat den neuesten Stand (150): " .. tostring(loaded and loaded.Coins))
end)

-- 2b. Der alte Server gibt erst nach 4 s frei: B wartet sichtbar und lädt dann den neuen Stand
run("Warten auf Freigabe", function()
	local store = mockStore(0.5)
	local A, B = server(store, "A"), server(store, "B")
	local _, data = A:Load("u1")
	data.Coins = 10
	A:Save("u1", data, false)
	task.delay(4, function()
		data.Coins = 75
		A:Save("u1", data, true)
	end)
	local start = SIM.Now
	local status, loaded = B:Load("u1")
	check(status == "ok" and loaded.Coins == 75, "B lädt den Stand nach der Freigabe (75): " .. tostring(loaded and loaded.Coins))
	check(SIM.Now - start >= 4, string.format("B hat gewartet (%.1f s)", SIM.Now - start))
	check(SIM.Now - start < B.LockWait, "aber nicht bis zur Übernahme")
end)

-- 3. Absturz: A hält die Sperre und gibt nie frei -> B übernimmt nach LockWait; A (Zombie) darf nicht mehr schreiben
run("Abgestürzter Server", function()
	local store = mockStore()
	local A, B = server(store, "A"), server(store, "B")
	local _, data = A:Load("u1")
	data.Coins = 200
	A:Save("u1", data, false)
	local start = SIM.Now
	local status, loaded = B:Load("u1")
	check(status == "ok" and loaded.Coins == 200, "B übernimmt mit Coins 200")
	check(SIM.Now - start >= B.LockWait and SIM.Now - start < B.LockWait + 10,
		string.format("B wartet etwa LockWait (%.1f s)", SIM.Now - start))
	data.Coins = 999
	check(A:Save("u1", data, false) == "lost", "A merkt, dass B übernommen hat")
	check(store.Data.u1.Coins == 200 and store.Data.u1.Session.Id == "B", "Stand von B bleibt")
end)

-- 4. Verwaiste Sperre (lange nicht erneuert): sofort übernehmen
run("Verwaiste Sperre", function()
	local store = mockStore()
	store.Data.u1 = { Coins = 7, Session = { Id = "X", Time = math.floor(SIM.Now) - 1000 } }
	local B = server(store, "B")
	local start = SIM.Now
	local status, loaded = B:Load("u1")
	check(status == "ok" and loaded.Coins == 7, "B lädt")
	check(SIM.Now - start < 5, "ohne Warten")
end)

-- 5. Kurze DataStore-Störung: Wiederholungen
run("Wiederholung bei Fehlern", function()
	local store = mockStore()
	store.Data.u1 = { Coins = 5 }
	store.FailNext = 2
	local A = server(store, "A")
	local status, loaded = A:Load("u1")
	check(status == "ok" and loaded.Coins == 5, "lädt nach 2 Fehlern")
	store.FailNext = 3
	loaded.Coins = 6
	check(A:Save("u1", loaded, false) == "ok", "speichert nach 3 Fehlern")
	check(store.Data.u1.Coins == 6, "Stand gespeichert")
end)

-- 6. Dauerhafte Störung: Fehler melden (ProgressService kickt dann)
run("Dauerhafter Fehler", function()
	local store = mockStore()
	store.FailNext = math.huge
	local A = server(store, "A")
	local status = A:Load("u1")
	check(status == "error", "Laden meldet Fehler: " .. tostring(status))
	check(store.Calls == A.Retries, "genau Retries Versuche: " .. store.Calls)
end)

-- 7. Spieler geht während des Wartens: kein Laden, keine hängende Sperre
run("Spieler geht beim Laden", function()
	local store = mockStore()
	local A, B = server(store, "A"), server(store, "B")
	A:Load("u1")
	local gone = false
	task.delay(5, function()
		gone = true
	end)
	local status = B:Load("u1", function()
		return not gone
	end)
	check(status == "gone", "B bricht ab: " .. tostring(status))
	check(store.Data.u1.Session.Id == "A", "Sperre von A unverändert")
	-- B holt die Sperre, der Spieler ist aber gerade weg: gleich wieder freigeben
	A:Save("u1", {}, true)
	local status2 = B:Load("u1", function()
		return false
	end)
	check(status2 == "gone" and store.Data.u1.Session == nil, "geholte Sperre wieder frei")
end)

-- 8. Gleichzeitige Speichervorgänge: nacheinander, Freigabe zuletzt bleibt frei
run("Speichervorgänge nacheinander", function()
	local store = mockStore(1)
	local A = server(store, "A")
	local _, data = A:Load("u1")
	data.Coins = 1
	local finished = 0
	task.spawn(function()
		A:Save("u1", data, false) -- Autosave
		finished += 1
	end)
	task.spawn(function()
		A:Save("u1", data, true) -- Verlassen
		finished += 1
	end)
	while finished < 2 do
		task.wait(0.5)
	end
	check(store.Data.u1.Session == nil, "nach Autosave + Verlassen ist die Sperre frei")
end)

-- 8b. Speichern nach dem Freigeben (z.B. Kauf, der hinter dem Verlassen wartete): schreibt, sperrt aber nicht neu
run("kein Neusperren nach Freigabe", function()
	local store = mockStore()
	local A = server(store, "A")
	local _, data = A:Load("u1")
	A:Save("u1", data, true)
	data.Coins = 5
	check(A:Save("u1", data, false) == "ok", "späte Speicherung klappt")
	check(store.Data.u1.Coins == 5 and store.Data.u1.Session == nil, "geschrieben, Sperre bleibt frei")
	A:Load("u1")
	A:Save("u1", data, false)
	check(store.Data.u1.Session ~= nil and store.Data.u1.Session.Id == "A", "nach erneutem Laden wieder gesperrt")
end)

-- 9. Altes Format ohne Session: wird normal geladen
run("Alter Stand ohne Sperre", function()
	local store = mockStore()
	store.Data.u1 = { XP = { Viper = 10 }, Coins = 3 }
	local A = server(store, "A")
	local status, loaded = A:Load("u1")
	check(status == "ok" and loaded.Coins == 3 and loaded.XP.Viper == 10, "alter Stand geladen")
end)

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

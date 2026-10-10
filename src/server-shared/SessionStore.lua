-- SessionStore (ModuleScript, nur Server)
-- Spielstände mit Sitzungssperre im DataStore. Jeder Server sperrt die Einträge seiner Spieler (Feld Session im
-- gespeicherten Eintrag: { Id = Server-Kennung, Time = os.time() }, bei jedem Speichern erneuert) und schreibt nur,
-- solange er die Sperre hält (UpdateAsync). So überschreibt ein alter Server nach einem schnellen Serverwechsel
-- keinen neueren Stand.
--   Load: wartet auf die Freigabe durch einen anderen Server (der speichert beim Verlassen und gibt frei); hängt die
--         Sperre an einem abgestürzten Server, wird sie nach LockWait Sekunden übernommen, eine länger als
--         LockTimeout nicht erneuerte Sperre sofort.
--   Save: schreibt nur mit eigener Sperre ("lost", wenn ein anderer Server übernommen hat); release gibt frei.
-- DataStore-Fehler werden mit wachsender Pause wiederholt (Retries Versuche). Speichervorgänge für denselben
-- Schlüssel laufen nacheinander.

local SessionStore = {}
SessionStore.__index = SessionStore

local DEFAULTS = {
	LockTimeout = 300, -- so alt (Sekunden) darf die Sperre eines anderen Servers sein, sonst gilt sie als verwaist
	LockWait = 20,     -- so lange beim Laden auf die Freigabe warten, dann übernehmen
	LockPoll = 3,      -- Abstand der Versuche dabei
	Retries = 4,       -- Versuche bei DataStore-Fehlern (Pausen 2, 4, 8 s)
}

-- dataStore: DataStore (GetDataStore). options: SessionId (Pflicht), LockTimeout, LockWait, LockPoll, Retries,
-- Now (Uhrzeit in Sekunden, Standard os.time), Clock (Standard os.clock)
function SessionStore.new(dataStore, options)
	local self = setmetatable({}, SessionStore)
	self.Store = dataStore
	self.SessionId = assert(options.SessionId, "SessionId fehlt")
	for name, value in DEFAULTS do
		self[name] = options[name] or value
	end
	self.Now = options.Now or os.time
	self.Clock = options.Clock or os.clock
	self.Saving = {} -- [Schlüssel] = true, solange gespeichert wird
	return self
end

-- DataStore-Aufruf mit Wiederholungen. Gibt true oder false, Fehler zurück.
function SessionStore:Try(fn)
	local lastError
	for attempt = 1, self.Retries do
		local ok, err = pcall(fn)
		if ok then
			return true
		end
		lastError = err
		if attempt < self.Retries then
			task.wait(2 ^ attempt)
		end
	end
	return false, lastError
end

function SessionStore:LockedByOther(entry)
	local session = type(entry) == "table" and entry.Session
	return type(session) == "table" and session.Id ~= self.SessionId
end

-- Eintrag lesen und für diesen Server sperren (force: auch eine fremde Sperre übernehmen).
-- Gibt "ok", Daten (ohne Session) | "locked" | "error", Fehler zurück.
function SessionStore:Acquire(key, force)
	local data, locked = nil, false
	local ok, err = self:Try(function()
		data, locked = nil, false
		self.Store:UpdateAsync(key, function(old)
			data, locked = nil, false -- UpdateAsync kann die Funktion bei Konflikten mehrmals aufrufen
			local session = type(old) == "table" and old.Session
			if not force and self:LockedByOther(old) and type(session) == "table" and type(session.Time) == "number"
				and self.Now() - session.Time < self.LockTimeout then
				locked = true
				return nil -- nichts schreiben
			end
			local entry = type(old) == "table" and old or {}
			entry.Session = { Id = self.SessionId, Time = self.Now() }
			data = entry
			return entry
		end)
	end)
	if not ok then
		return "error", err
	end
	if locked or data == nil then
		return "locked"
	end
	local copy = table.clone(data)
	copy.Session = nil
	return "ok", copy
end

-- Laden und sperren. stillThere(): false, sobald der Spieler gegangen ist (dann wird nicht weiter gewartet und eine
-- schon geholte Sperre gleich wieder freigegeben). Gibt "ok", Daten (ohne Session) | "gone" | "error", Fehler zurück.
function SessionStore:Load(key, stillThere)
	-- Wiederkommen auf denselben Server, während das Speichern beim Verlassen noch läuft: erst danach lesen (sonst
	-- alte Daten, und das Freigeben der Sperre träfe die neue Sitzung)
	local waitUntil = self.Clock() + self.LockWait
	while self.Saving[key] and self.Clock() < waitUntil do
		task.wait(0.1)
	end
	local deadline = self.Clock() + self.LockWait
	while true do
		local status, result = self:Acquire(key, self.Clock() >= deadline)
		if stillThere and not stillThere() then
			if status == "ok" then
				self:Release(key)
			end
			return "gone"
		end
		if status ~= "locked" then
			return status, result
		end
		task.wait(self.LockPoll) -- der andere Server speichert gerade und gibt gleich frei
	end
end

-- data speichern (nur mit eigener Sperre); release = Sperre dabei freigeben.
-- Gibt "ok" | "lost" (anderer Server hat übernommen, nichts geschrieben) | "error", Fehler zurück.
function SessionStore:Save(key, data, release)
	while self.Saving[key] do
		task.wait(0.1) -- ein anderer Speichervorgang für diesen Schlüssel läuft noch
	end
	self.Saving[key] = true
	local lost = false
	local ok, err = self:Try(function()
		lost = false
		self.Store:UpdateAsync(key, function(old)
			lost = false
			if self:LockedByOther(old) then
				lost = true
				return nil -- ein anderer Server hat übernommen: nicht überschreiben
			end
			local entry = table.clone(data)
			entry.Session = if release then nil else { Id = self.SessionId, Time = self.Now() }
			return entry
		end)
	end)
	self.Saving[key] = nil
	if lost then
		return "lost"
	end
	if not ok then
		return "error", err
	end
	return "ok"
end

-- Nur die eigene Sperre aufheben, ohne Daten zu schreiben
function SessionStore:Release(key)
	self:Try(function()
		self.Store:UpdateAsync(key, function(old)
			if type(old) ~= "table" or old.Session == nil or self:LockedByOther(old) then
				return nil
			end
			old.Session = nil
			return old
		end)
	end)
end

return SessionStore

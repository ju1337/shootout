-- BanService (ModuleScript, nur Server)
-- Sperrliste: Spieler rauswerfen (Kick) oder sperren (Ban) – aus dem Admin-Panel (Reiter SPIELER / SPERREN).
--   * Die Liste liegt im DataStore "Bans_v1" unter dem Schlüssel "List": { [UserId als Text] = { Name, Reason, Until,
--     By, At } }, Until = Unix-Zeit des Ablaufs (0 = dauerhaft). Jeder Server lädt sie beim Start und alle RefreshEvery
--     Sekunden neu; Änderungen gehen sofort per MessagingService ("Bans") an alle Server.
--   * Zusätzlich Players:BanAsync/UnbanAsync (Sperre von Roblox selbst, wirkt auch gegen Zweitkonten); fehlt das (Studio,
--     alte Server), greift allein die eigene Liste – gesperrte Spieler werden beim Beitreten gekickt.
--   * Gründe laufen durch den Roblox-Textfilter (der Gesperrte sieht ihn); die Kick-Nachricht ist in der Sprache
--     des Spielers (Locale.ForPlayer).
-- Aktionen (AdminService): Kick(userId, reason), Ban(userId, { Days, Reason }), Unban(userId), BanList -> Remotes.AdminData.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale"))

local BanService = {}

BanService.StoreName = "Bans_v1"
BanService.Key = "List"
BanService.Topic = "Bans"
BanService.RefreshEvery = 60        -- Sekunden: Liste aus dem DataStore erneuern
BanService.DefaultReason = "Regelverstoß"
BanService.MaxDays = 3650
BanService.UseRobloxBans = true     -- Players:BanAsync zusätzlich zur eigenen Liste

local list = {}      -- [userId als Text] = Eintrag
local store = nil
local loadedOnce = false

-- ---------- Hilfen ----------

local function key(userId)
	return tostring(math.floor(tonumber(userId) or 0))
end

local function active(entry, now)
	if type(entry) ~= "table" then
		return false
	end
	local untilTime = tonumber(entry.Until) or 0
	return untilTime == 0 or untilTime > (now or os.time())
end

local function dataStore()
	if store == nil then
		local ok, s = pcall(DataStoreService.GetDataStore, DataStoreService, BanService.StoreName)
		store = ok and s or false
	end
	return store or nil
end

-- Liste im DataStore ändern: transform(list) -> list
local function update(transform)
	local s = dataStore()
	if not s then
		list = transform(list) or list
		return true
	end
	local ok, err = pcall(function()
		s:UpdateAsync(BanService.Key, function(old)
			local fresh = transform(type(old) == "table" and old or {})
			list = fresh
			return fresh
		end)
	end)
	if not ok then
		warn("BanService: Speichern fehlgeschlagen: " .. tostring(err))
	end
	return ok
end

local function load()
	local s = dataStore()
	if not s then
		loadedOnce = true
		return
	end
	local ok, result = pcall(s.GetAsync, s, BanService.Key)
	if ok then
		list = type(result) == "table" and result or {}
		loadedOnce = true
	else
		warn("BanService: Laden fehlgeschlagen: " .. tostring(result))
	end
end

local function publish(action, userId, entry)
	pcall(MessagingService.PublishAsync, MessagingService, BanService.Topic, { Action = action, UserId = key(userId), Entry = entry })
end

local function filtered(admin, text)
	text = string.sub(tostring(text or ""), 1, 120)
	if text == "" then
		return BanService.DefaultReason
	end
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, admin.UserId):GetNonChatStringForBroadcastAsync()
	end)
	return ok and result or BanService.DefaultReason
end

local function nameOf(userId)
	local online = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if online then
		return online.Name
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, tonumber(userId) or 0)
	return ok and name or ("#" .. key(userId))
end

local function describe(entry)
	local untilTime = tonumber(entry and entry.Until) or 0
	if untilTime == 0 then
		return "dauerhaft"
	end
	local left = untilTime - os.time()
	if left >= 86400 then
		return "noch " .. math.ceil(left / 86400) .. " Tage"
	end
	return "noch " .. math.max(1, math.ceil(left / 3600)) .. " Stunden"
end

local function kickBanned(player, entry)
	local text = "Du bist gesperrt (" .. describe(entry) .. "): " .. tostring(entry.Reason or BanService.DefaultReason)
	player:Kick(Locale.ForPlayer(player, text))
end

-- ---------- Öffentlich ----------

-- Eintrag oder nil, wenn nicht (mehr) gesperrt
function BanService.Get(userId)
	local entry = list[key(userId)]
	return active(entry) and entry or nil
end

function BanService.IsBanned(userId)
	return BanService.Get(userId) ~= nil
end

-- Alle aktiven Sperren als Liste (neueste zuerst) für das Admin-Panel
function BanService.List()
	local result = {}
	local now = os.time()
	for id, entry in list do
		if active(entry, now) then
			table.insert(result, { UserId = tonumber(id), Name = entry.Name, Reason = entry.Reason, Until = entry.Until or 0,
				By = entry.By, At = entry.At or 0, Left = describe(entry) })
		end
	end
	table.sort(result, function(a, b)
		return (a.At or 0) > (b.At or 0)
	end)
	return result
end

-- Spieler rauswerfen (nur diesen Server)
function BanService.Kick(admin, userId, reason)
	local player = Players:GetPlayerByUserId(tonumber(userId) or 0)
	if not player then
		return "Spieler ist nicht auf diesem Server."
	end
	if admin and player == admin then
		return "Dich selbst kannst du nicht rauswerfen."
	end
	local text = filtered(admin, reason)
	player:Kick(Locale.ForPlayer(player, "Rausgeworfen: " .. text))
	return player.Name .. " rausgeworfen"
end

-- Sperren: days = 0 oder nil = dauerhaft, sonst Tage
function BanService.Ban(admin, userId, days, reason)
	local id = tonumber(userId)
	if not id or id <= 0 then
		return "Keine gültige UserId."
	end
	if admin and admin.UserId == id then
		return "Dich selbst kannst du nicht sperren."
	end
	days = math.clamp(math.floor(tonumber(days) or 0), 0, BanService.MaxDays)
	local text = filtered(admin, reason)
	local now = os.time()
	local entry = { Name = nameOf(id), Reason = text, Until = days > 0 and now + days * 86400 or 0,
		By = admin and admin.Name or "Server", At = now }
	if not update(function(current)
		current[key(id)] = entry
		return current
	end) then
		return "Sperre konnte nicht gespeichert werden (DataStore)."
	end
	if BanService.UseRobloxBans then
		pcall(function()
			Players:BanAsync({ UserIds = { id }, Duration = days > 0 and days * 86400 or -1, DisplayReason = text,
				PrivateReason = "Admin-Panel: " .. (admin and admin.Name or "Server"), ExcludeAltAccounts = false,
				ApplyToUniverse = true })
		end)
	end
	local online = Players:GetPlayerByUserId(id)
	if online then
		kickBanned(online, entry)
	end
	publish("Ban", id, entry)
	return entry.Name .. " gesperrt (" .. describe(entry) .. ")"
end

function BanService.Unban(admin, userId)
	local id = tonumber(userId)
	if not id or not list[key(id)] then
		return "Keine Sperre für diese UserId."
	end
	local name = list[key(id)].Name or key(id)
	if not update(function(current)
		current[key(id)] = nil
		return current
	end) then
		return "Entsperren konnte nicht gespeichert werden (DataStore)."
	end
	if BanService.UseRobloxBans then
		pcall(function()
			Players:UnbanAsync({ UserIds = { id }, ApplyToUniverse = true })
		end)
	end
	publish("Unban", id)
	return tostring(name) .. " entsperrt"
end

-- Beim Beitreten: gesperrt -> sofort raus
local function onPlayerAdded(player)
	local entry = BanService.Get(player.UserId)
	if entry then
		kickBanned(player, entry)
	end
end

function BanService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	-- DataStore und MessagingService im Hintergrund: antworten sie nicht (Studio, Ausfall), darf der Serverstart
	-- nicht daran hängen. Wer vor dem Laden beitritt, wird danach geprüft.
	task.spawn(function()
		load()
		for _, player in Players:GetPlayers() do
			onPlayerAdded(player)
		end
	end)
	-- Änderungen anderer Server sofort übernehmen
	task.spawn(pcall, MessagingService.SubscribeAsync, MessagingService, BanService.Topic, function(message)
		local data = type(message) == "table" and message.Data or nil
		if type(data) ~= "table" or type(data.UserId) ~= "string" then
			return
		end
		if data.Action == "Ban" and type(data.Entry) == "table" then
			list[data.UserId] = data.Entry
			local online = Players:GetPlayerByUserId(tonumber(data.UserId) or 0)
			if online and active(data.Entry) then
				kickBanned(online, data.Entry)
			end
		elseif data.Action == "Unban" then
			list[data.UserId] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(BanService.RefreshEvery)
			load()
			for _, player in Players:GetPlayers() do
				onPlayerAdded(player)
			end
		end
	end)
end

-- Für Tests
function BanService._Reset()
	list, store, loadedOnce = {}, nil, false
end

function BanService._Loaded()
	return loadedOnce
end

return BanService

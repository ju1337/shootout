-- ClanService (ModuleScript, nur Server)
-- Clans über alle Server: gründen (kostet Münzen), per Kürzel beitreten, verlassen, Mitglieder entfernen (Leiter).
-- Daten im DataStore "Clans_v<SaveVersion.Wipe>", Schlüssel = Kürzel: { Tag, Name, Owner (UserId), Members = { [UserId] = Name }, Created }.
-- Im Profil steht nur das Kürzel (profile.Clan). Ohne DataStore (Studio) liegen Clans nur im Speicher dieses Servers.
-- Spieler-Attribute: ClanTag, ClanName, ClanData (JSON: Owner, Members, Points, WeekPoints, By) für Namensschild,
-- Spielerkarte und Seite CLAN.
-- Name und Kürzel laufen durch den Roblox-Textfilter (Pflicht für Texte, die andere sehen).
-- Clan-Punkte (RetentionConfig.Clan, Julio 2026-10-13): Zombies und Aufträge der Mitglieder (ProgressService.OnStat)
-- sammeln sich pro Server und gehen alle FlushEvery Sekunden in den DataStore: Points (alle, ergibt die Clan-Stufe),
-- Week = { Id, Points, By = { [UserId] = Punkte } } (Wochenziel, montags neu), LastWeek (die Woche davor). Jede erreichte
-- Stufe des Wochenziels gibt jedem Mitglied, das selbst mindestens MinContribution Punkte beigetragen hat, einmal pro Woche
-- Münzen (Profil ClanPaid = { [Woche] = Stufe }, gilt auch nach einem Clan-Wechsel). Clan-Bestenliste über den
-- OrderedDataStore "LB_Clans_v1" (Schlüssel Kürzel, Wert Points) als ReplicatedStorage-Attribut "Leaderboard_Clans"
-- (JSON [{ Tag, Name, Value }]).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local QuestConfig = require(Shared.QuestConfig)
local RetentionConfig = require(Shared.RetentionConfig)
local SaveVersion = require(Shared.SaveVersion)
local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)

local ClanService = {}

ClanService.CreateCost = 2500
ClanService.MaxMembers = 20

local store = nil
do
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, SaveVersion.Name("Clans"))
	if ok then
		store = result
	end
end
local memory = {} -- Ersatz ohne DataStore und Zwischenspeicher: [Tag] = Daten
local rankStore = nil -- Clan-Bestenliste
do
	local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, SaveVersion.Name("LB_Clans"))
	if ok then
		rankStore = result
	end
end
local R = RetentionConfig.Clan
local pending = {} -- noch nicht gespeicherte Punkte: [Tag] = { Points, By = { [UserId] = Punkte } }

-- Gibt die Daten zurück und als zweiten Wert, ob sie sicher stimmen (false: DataStore-Fehler und nichts zwischengespeichert)
local function fetch(tag)
	if store then
		local ok, data = pcall(store.GetAsync, store, tag)
		if ok then
			memory[tag] = data
			return data, true
		end
		return memory[tag], memory[tag] ~= nil
	end
	return memory[tag], true
end

-- Daten ändern: fn(alt) gibt neu zurück (nil = löschen). Gibt die neuen Daten zurück.
local function change(tag, fn)
	if store then
		local result
		local ok, err = pcall(store.UpdateAsync, store, tag, function(old)
			result = fn(old)
			return result
		end)
		if not ok then
			warn("Clan-Daten nicht gespeichert: " .. tostring(err))
			if not RunService:IsStudio() then
				return nil, false
			end
			-- Studio ohne DataStore-Zugriff: im Speicher weitertesten
			memory[tag] = fn(memory[tag])
			return memory[tag], true
		end
		memory[tag] = result
		return result, true
	end
	memory[tag] = fn(memory[tag])
	return memory[tag], true
end

local function count(members)
	local n = 0
	for _ in members do
		n += 1
	end
	return n
end

-- Punkte der laufenden Woche (0, wenn die gespeicherte Woche schon vorbei ist)
local function weekOf(data, week)
	local entry = type(data.Week) == "table" and data.Week or nil
	if entry and entry.Id == week then
		return entry
	end
	return { Id = week, Points = 0, By = {} }
end

-- Clan-Daten auf die laufende Woche bringen: die alte wird LastWeek (nur wenn sie direkt davor lag)
local function rollWeek(data, week)
	local entry = type(data.Week) == "table" and data.Week or nil
	if entry and entry.Id == week then
		return
	end
	data.LastWeek = (entry and entry.Id == week - 1) and entry or nil
	data.Week = { Id = week, Points = 0, By = {} }
end

-- Münzen für neu erreichte Stufen des Wochenziels (einmal pro Spieler und Woche, nur mit eigenem Beitrag)
local function payStages(player, profile, entry)
	if not entry or type(entry.Id) ~= "number" then
		return
	end
	local mine = tonumber(type(entry.By) == "table" and entry.By[tostring(player.UserId)]) or 0
	if mine < R.MinContribution then
		return
	end
	profile.ClanPaid = type(profile.ClanPaid) == "table" and profile.ClanPaid or {}
	local key = tostring(entry.Id)
	local paid = tonumber(profile.ClanPaid[key]) or 0
	local stage = RetentionConfig.ClanStage(entry.Points)
	if stage <= paid then
		return
	end
	profile.ClanPaid[key] = stage
	for old in profile.ClanPaid do
		if (tonumber(old) or 0) < QuestConfig.Week() - 1 then
			profile.ClanPaid[old] = nil
		end
	end
	local coins = 0
	for index = paid + 1, stage do
		coins += R.Stages[index].Coins
	end
	ProgressService.AddCoins(player, coins, "Clan-Wochenziel")
	Remotes.Notify:FireClient(player, "Banner", { Caption = "Clan-Wochenziel", Title = "STUFE " .. stage .. " GESCHAFFT",
		Sub = "+" .. coins .. " Münzen · danke für deinen Beitrag", Style = "Good" })
end

local function publish(player, data)
	if data then
		local week = QuestConfig.Week()
		local entry = weekOf(data, week)
		player:SetAttribute("ClanTag", data.Tag)
		player:SetAttribute("ClanName", data.Name)
		player:SetAttribute("ClanData", HttpService:JSONEncode({ Owner = data.Owner, Members = data.Members,
			Points = data.Points or 0, WeekPoints = entry.Points or 0, By = entry.By or {} }))
		local profile = ProgressService.IsLoaded(player) and ProgressService.Get(player)
		if profile then
			payStages(player, profile, entry.Points > 0 and entry or nil)
			local last = type(data.LastWeek) == "table" and data.LastWeek or nil
			if last and last.Id == week - 1 then
				payStages(player, profile, last)
			end
		end
	else
		player:SetAttribute("ClanTag", nil)
		player:SetAttribute("ClanName", nil)
		player:SetAttribute("ClanData", nil)
	end
end

-- Alle Clan-Mitglieder auf diesem Server neu anzeigen
local function publishMembers(tag, data)
	for _, other in Players:GetPlayers() do
		local profile = ProgressService.Get(other)
		if profile and profile.Clan == tag then
			if data and data.Members[tostring(other.UserId)] then
				publish(other, data)
			else
				profile.Clan = nil
				publish(other, nil)
			end
		end
	end
end

-- Text prüfen: filtern lassen, bei Änderung ablehnen
local function filtered(player, text)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	return ok and result == text
end

-- Gründen, Beitreten und Verlassen warten auf DataStore und Textfilter: pro Spieler nur eine Anfrage gleichzeitig,
-- sonst kommen mehrere gleichzeitige Anfragen alle an den Prüfungen vorbei (mehrere Clans, Gründung ohne Bezahlen)
local busy = {}
local function once(handler)
	return function(player, ...)
		if busy[player] then
			return nil, false
		end
		busy[player] = true
		local ok, message, success = pcall(handler, player, ...)
		busy[player] = nil
		if not ok then
			error(message, 0)
		end
		return message, success
	end
end

function ClanService.Create(player, name, tag)
	local profile = ProgressService.Get(player)
	if not profile then
		return "Daten werden noch geladen.", false
	end
	if profile.Clan then
		return "Du bist schon in einem Clan.", false
	end
	if typeof(name) ~= "string" or typeof(tag) ~= "string" then
		return "Name und Kürzel eingeben.", false
	end
	name = string.gsub(name, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	tag = string.upper(tag)
	if #name < 3 or #name > 20 then
		return "Der Name braucht 3 bis 20 Zeichen.", false
	end
	if not string.match(tag, "^%w%w%w?%w?$") then
		return "Das Kürzel braucht 2 bis 4 Buchstaben oder Ziffern.", false
	end
	if (profile.Coins or 0) < ClanService.CreateCost then
		return "Ein Clan kostet " .. ClanService.CreateCost .. " Münzen.", false
	end
	if not filtered(player, name) or not filtered(player, tag) then
		return "Name oder Kürzel ist nicht erlaubt.", false
	end
	-- erst bezahlen, dann eintragen (zurück, wenn es nicht klappt)
	if not ProgressService.SpendCoins(player, ClanService.CreateCost, "Clan") then
		return "Ein Clan kostet " .. ClanService.CreateCost .. " Münzen.", false
	end
	local function refund()
		ProgressService.AddCoins(player, ClanService.CreateCost, "Admin")
	end
	local taken = false
	local data = change(tag, function(old)
		if old then
			taken = true
			return old
		end
		return { Tag = tag, Name = name, Owner = player.UserId, Members = { [tostring(player.UserId)] = player.Name },
			Created = os.time() }
	end)
	if taken then
		refund()
		return "Das Kürzel [" .. tag .. "] ist schon vergeben.", false
	end
	if not data then
		refund()
		return "Gerade nicht möglich, bitte später nochmal.", false
	end
	profile.Clan = tag
	publish(player, data)
	return "Clan [" .. tag .. "] " .. name .. " gegründet!", true
end

function ClanService.Join(player, tag)
	local profile = ProgressService.Get(player)
	if not profile then
		return "Daten werden noch geladen.", false
	end
	if profile.Clan then
		return "Erst den aktuellen Clan verlassen.", false
	end
	if typeof(tag) ~= "string" or not string.match(string.upper(tag), "^%w%w%w?%w?$") then
		return "Kürzel eingeben (2–4 Zeichen).", false
	end
	tag = string.upper(tag)
	local problem = nil
	local data = change(tag, function(old)
		if not old then
			problem = "Diesen Clan gibt es nicht."
			return nil
		end
		if count(old.Members) >= ClanService.MaxMembers then
			problem = "Der Clan ist voll (" .. ClanService.MaxMembers .. ")."
			return old
		end
		old.Members[tostring(player.UserId)] = player.Name
		return old
	end)
	if problem then
		return problem, false
	end
	if not data then
		return "Gerade nicht möglich, bitte später nochmal.", false
	end
	profile.Clan = tag
	publishMembers(tag, data)
	return "Willkommen im Clan [" .. tag .. "] " .. data.Name .. "!", true
end

function ClanService.Leave(player)
	local profile = ProgressService.Get(player)
	local tag = profile and profile.Clan
	if not tag then
		return "Du bist in keinem Clan.", false
	end
	local data, saved = change(tag, function(old)
		if not old then
			return nil
		end
		old.Members[tostring(player.UserId)] = nil
		if count(old.Members) == 0 then
			return nil -- letzter raus: Clan aufgelöst
		end
		if old.Owner == player.UserId then
			-- Leitung an das nächste Mitglied
			for id in old.Members do
				old.Owner = tonumber(id)
				break
			end
		end
		return old
	end)
	if not saved then -- DataStore-Fehler: sonst wären alle hier ohne Clan, stünden aber weiter in der Liste
		return "Gerade nicht möglich, bitte später nochmal.", false
	end
	profile.Clan = nil
	publish(player, nil)
	publishMembers(tag, data)
	if not data and rankStore then -- aufgelöst: raus aus der Clan-Bestenliste
		task.spawn(pcall, rankStore.RemoveAsync, rankStore, tag)
	end
	return "Clan verlassen.", true
end

function ClanService.Kick(player, userId)
	local profile = ProgressService.Get(player)
	local tag = profile and profile.Clan
	userId = tonumber(userId)
	if not tag or not userId or userId == player.UserId then
		return "Ungültig.", false
	end
	local allowed = true
	local data, saved = change(tag, function(old)
		if not old or old.Owner ~= player.UserId then
			allowed = false
			return old
		end
		old.Members[tostring(userId)] = nil
		return old
	end)
	if not allowed then
		return "Nur der Clan-Leiter kann Mitglieder entfernen.", false
	end
	if not saved then
		return "Gerade nicht möglich, bitte später nochmal.", false
	end
	publishMembers(tag, data)
	return "Mitglied entfernt.", true
end

-- ---------- Clan-Punkte, Wochenziel, Bestenliste ----------

-- Statistik eines Mitglieds gestiegen: Punkte für seinen Clan vormerken
local function onStat(player, key, _, amount)
	local per = R.Points[key]
	local profile = per and ProgressService.Get(player)
	local tag = profile and profile.Clan
	if not tag or player:GetAttribute("ClanTag") ~= tag then -- (nur bestätigte Mitgliedschaft, siehe load)
		return
	end
	local points = per * (tonumber(amount) or 1)
	if points <= 0 then
		return
	end
	local entry = pending[tag] or { Points = 0, By = {} }
	pending[tag] = entry
	entry.Points += points
	local id = tostring(player.UserId)
	entry.By[id] = (entry.By[id] or 0) + points
end

-- Vorgemerkte Punkte speichern (pro Clan ein UpdateAsync), danach Mitglieder hier neu anzeigen und Stufen auszahlen
function ClanService.Flush()
	local week = QuestConfig.Week()
	for tag, entry in pending do
		pending[tag] = nil
		local data, saved = change(tag, function(old)
			if not old then
				return nil
			end
			rollWeek(old, week)
			old.Points = (tonumber(old.Points) or 0) + entry.Points
			old.Week.Points += entry.Points
			old.Week.By = old.Week.By or {}
			for id, points in entry.By do
				if old.Members[id] then -- wer inzwischen raus ist, zählt nicht mehr
					old.Week.By[id] = (old.Week.By[id] or 0) + points
				end
			end
			return old
		end)
		if not saved then
			-- DataStore-Fehler: beim nächsten Mal noch einmal (zu den inzwischen neuen Punkten dazu)
			local now = pending[tag] or { Points = 0, By = {} }
			now.Points += entry.Points
			for id, points in entry.By do
				now.By[id] = (now.By[id] or 0) + points
			end
			pending[tag] = now
		elseif data then
			publishMembers(tag, data)
			if rankStore then
				task.spawn(pcall, rankStore.SetAsync, rankStore, tag, math.floor(data.Points))
			end
		end
	end
end

-- Clan-Bestenliste (Top 10) als Attribut Leaderboard_Clans; ohne DataStore aus den Clans im Speicher
local names = {} -- [Tag] = Name (Cache)
function ClanService.RefreshBoard()
	local list = {}
	if rankStore then
		local ok, pages = pcall(rankStore.GetSortedAsync, rankStore, false, 10)
		if ok then
			for _, entry in pages:GetCurrentPage() do
				local tag = tostring(entry.key)
				if not names[tag] then
					local data = fetch(tag)
					names[tag] = data and data.Name or nil
				end
				if names[tag] then
					table.insert(list, { Tag = tag, Name = names[tag], Value = entry.value })
				end
			end
		end
	end
	if #list == 0 then
		for tag, data in memory do
			if type(data) == "table" and (tonumber(data.Points) or 0) > 0 then
				table.insert(list, { Tag = tag, Name = data.Name, Value = math.floor(data.Points) })
			end
		end
		table.sort(list, function(a, b)
			return a.Value > b.Value
		end)
		while #list > 10 do
			table.remove(list)
		end
	end
	ReplicatedStorage:SetAttribute("Leaderboard_Clans", HttpService:JSONEncode(list))
	return list
end

-- Beim Beitreten (sobald das Profil da ist) Clan laden und prüfen, ob man noch Mitglied ist
local function load(player)
	-- so lange wie nötig (Sperre eines alten Servers kann über 30 s dauern), sonst fehlt der Clan die ganze Sitzung
	while player.Parent and not ProgressService.IsLoaded(player) do
		task.wait(0.5)
	end
	local profile = player.Parent and ProgressService.Get(player)
	if not profile or not profile.Clan then
		return
	end
	local data, sure = fetch(profile.Clan)
	for _ = 1, 4 do -- DataStore antwortet gerade nicht: kurz warten statt den Clan aus dem Profil zu löschen
		if sure or not player.Parent then
			break
		end
		task.wait(5)
		data, sure = fetch(profile.Clan)
	end
	if not sure then
		return -- weiter nicht erreichbar: Clan bleibt im Profil, beim nächsten Beitritt wird neu geprüft
	end
	if data and data.Members[tostring(player.UserId)] then
		if data.Members[tostring(player.UserId)] ~= player.Name then
			data = change(profile.Clan, function(old)
				if old then
					old.Members[tostring(player.UserId)] = player.Name
				end
				return old
			end) or data
		end
		publishMembers(profile.Clan, data)
	else
		profile.Clan = nil
		publish(player, nil)
	end
end

ClanService.Create = once(ClanService.Create)
ClanService.Join = once(ClanService.Join)
ClanService.Leave = once(ClanService.Leave)

function ClanService.Init()
	table.insert(ProgressService.OnStat, onStat)
	task.spawn(function()
		while true do
			task.wait(R.FlushEvery)
			local ok, err = pcall(ClanService.Flush)
			if not ok then
				warn("Clan-Punkte: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		while true do
			pcall(ClanService.RefreshBoard)
			task.wait(60)
		end
	end)
	game:BindToClose(function()
		pcall(ClanService.Flush)
	end)
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	-- Mitgliederlisten ab und zu auffrischen (Beitritte auf anderen Servern)
	task.spawn(function()
		while true do
			task.wait(90)
			local tags = {}
			for _, player in Players:GetPlayers() do
				local profile = ProgressService.Get(player)
				if profile and profile.Clan then
					tags[profile.Clan] = true
				end
			end
			for tag in tags do
				publishMembers(tag, fetch(tag))
			end
		end
	end)
end

return ClanService

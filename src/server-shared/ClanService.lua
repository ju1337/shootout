-- ClanService (ModuleScript, nur Server)
-- Clans über alle Server: gründen (kostet Münzen), per Kürzel beitreten, verlassen, Mitglieder entfernen (Leiter).
-- Daten im DataStore "Clans_v1", Schlüssel = Kürzel: { Tag, Name, Owner (UserId), Members = { [UserId] = Name }, Created }.
-- Im Profil steht nur das Kürzel (profile.Clan). Ohne DataStore (Studio) liegen Clans nur im Speicher dieses Servers.
-- Spieler-Attribute: ClanTag, ClanName, ClanData (JSON: Owner, Members) für Namensschild, Spielerkarte und Fenster CLAN.
-- Name und Kürzel laufen durch den Roblox-Textfilter (Pflicht für Texte, die andere sehen).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)

local ClanService = {}

ClanService.CreateCost = 2500
ClanService.MaxMembers = 20

local store = nil
do
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, "Clans_v1")
	if ok then
		store = result
	end
end
local memory = {} -- Ersatz ohne DataStore und Zwischenspeicher: [Tag] = Daten

local function fetch(tag)
	if store then
		local ok, data = pcall(store.GetAsync, store, tag)
		if ok then
			memory[tag] = data
			return data
		end
	end
	return memory[tag]
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

local function publish(player, data)
	if data then
		player:SetAttribute("ClanTag", data.Tag)
		player:SetAttribute("ClanName", data.Name)
		player:SetAttribute("ClanData", HttpService:JSONEncode({ Owner = data.Owner, Members = data.Members }))
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

-- Beim Beitreten (sobald das Profil da ist) Clan laden und prüfen, ob man noch Mitglied ist
local function load(player)
	for _ = 1, 60 do
		if ProgressService.IsLoaded(player) then
			break
		end
		task.wait(0.5)
	end
	local profile = ProgressService.Get(player)
	if not profile or not profile.Clan then
		return
	end
	local data = fetch(profile.Clan)
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

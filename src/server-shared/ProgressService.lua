-- ProgressService (ModuleScript, nur Server)
-- Alle gespeicherten Spielerdaten: XP pro Agent, Münzen, gekaufte und ausgerüstete Skins,
-- tägliche Belohnung, eingelöste Codes und tägliche Aufträge. Gespeichert im DataStore (funktioniert erst, wenn
-- das Spiel veröffentlicht ist und in Studio "API Services" erlaubt sind - sonst nur für die Sitzung).
-- Spieler-Attribute für die Clients: XP_<AgentId>, Coins, Owned (JSON), Equipped (JSON), LastDaily,
-- Quests (JSON)

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local GameSettings = require(Shared.GameSettings)
local Cosmetics = require(Shared.Cosmetics)
local QuestConfig = require(Shared.QuestConfig)
local PassConfig = require(Shared.PassConfig)
local RankConfig = require(Shared.RankConfig)
local LevelConfig = require(Shared.LevelConfig)
local RewardConfig = require(Shared.RewardConfig)
local TitleConfig = require(Shared.TitleConfig)
local AttachmentConfig = require(Shared.AttachmentConfig)
local WeaponConfig = require(Shared.WeaponConfig)

local ProgressService = {}

local AUTOSAVE_INTERVAL = 120 -- Sekunden

local store = nil
local profiles = {} -- [Player] = Profil
local loaded = {}   -- [Player] = true, wenn erfolgreich geladen (nur dann speichern)

local function defaultProfile()
	return { XP = {}, Coins = 0, Owned = {}, Equipped = {}, LastDaily = 0, Codes = {}, Quests = {}, RankPoints = 0, PassXP = 0, Agents = {}, Settings = {},
		Stats = {}, Loadouts = {}, Attachments = { Owned = {}, Equipped = {} }, AccountXP = 0, Prestige = 0, Ranked = { Elo = RankConfig.StartElo, Peak = RankConfig.StartElo, Wins = 0, Losses = 0, Matches = 0,
		Season = RankConfig.CurrentSeason() } }
end

-- Gespeicherte Daten in ein Profil übernehmen (auch das alte Format { Viper = xp, ... })
local function toProfile(data)
	local profile = defaultProfile()
	if type(data) ~= "table" then
		return profile
	end
	if data.XP == nil then
		for _, agent in AgentConfig.Agents do
			profile.XP[agent.Id] = tonumber(data[agent.Id]) or 0
		end
		return profile
	end
	for key, value in data do
		profile[key] = value
	end
	-- Spielerlevel gab es früher nicht: aus den bisherigen Agenten-XP übernehmen
	if data.AccountXP == nil then
		local sum = 0
		for _, xp in profile.XP do
			sum += tonumber(xp) or 0
		end
		profile.AccountXP = math.min(sum, LevelConfig.MaxXP)
	end
	return profile
end

-- Aufträge für heute anlegen, falls ein neuer Tag begonnen hat (pro Spieler und Tag gleich)
local function ensureQuests(player, profile)
	local today = QuestConfig.Today()
	if profile.Quests.Day == today then
		return
	end
	local random = Random.new(player.UserId + tonumber((string.gsub(today, "-", ""))))
	local pool = table.clone(QuestConfig.Pool)
	local ids = {}
	for _ = 1, math.min(QuestConfig.PerDay, #pool) do
		local quest = table.remove(pool, random:NextInteger(1, #pool))
		table.insert(ids, quest.Id)
	end
	profile.Quests = { Day = today, Ids = ids, Progress = {}, Claimed = {} }
end

-- Wochen-Aufträge anlegen, falls eine neue Woche begonnen hat (pro Spieler und Woche gleich)
local function ensureWeekly(player, profile)
	local week = QuestConfig.Week()
	if type(profile.Weekly) == "table" and profile.Weekly.Week == week then
		return
	end
	local random = Random.new(player.UserId * 7 + week)
	local pool = table.clone(QuestConfig.WeeklyPool)
	local ids = {}
	for _ = 1, math.min(QuestConfig.PerWeek, #pool) do
		local quest = table.remove(pool, random:NextInteger(1, #pool))
		table.insert(ids, quest.Id)
	end
	profile.Weekly = { Week = week, Ids = ids, Progress = {}, Claimed = {}, Bonus = false }
end

-- Profil als Attribute an den Spieler hängen (damit Client und andere Skripte es lesen können)
function ProgressService.Sync(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	for _, agent in AgentConfig.Agents do
		player:SetAttribute("XP_" .. agent.Id, profile.XP[agent.Id] or 0)
	end
	player:SetAttribute("Coins", profile.Coins)
	player:SetAttribute("Owned", HttpService:JSONEncode(profile.Owned))
	player:SetAttribute("Equipped", HttpService:JSONEncode(profile.Equipped))
	player:SetAttribute("LastDaily", profile.LastDaily)
	player:SetAttribute("PassXP", profile.PassXP or 0)
	player:SetAttribute("UnlockedAgents", HttpService:JSONEncode(profile.Agents or {}))
	player:SetAttribute("ClientSettings", HttpService:JSONEncode(profile.Settings or {}))
	player:SetAttribute("Stats", HttpService:JSONEncode(profile.Stats or {}))
	player:SetAttribute("Loadouts", HttpService:JSONEncode(profile.Loadouts or {}))
	player:SetAttribute("Attachments", HttpService:JSONEncode(profile.Attachments or { Owned = {}, Equipped = {} }))
	player:SetAttribute("MatchHistory", HttpService:JSONEncode(profile.History or {}))
	player:SetAttribute("AccountXP", profile.AccountXP or 0)
	player:SetAttribute("Prestige", profile.Prestige or 0)
	local ranked = profile.Ranked or {}
	player:SetAttribute("Elo", ranked.Elo or RankConfig.StartElo)
	player:SetAttribute("RankedData", HttpService:JSONEncode(ranked))
	ensureQuests(player, profile)
	player:SetAttribute("Quests", HttpService:JSONEncode(profile.Quests))
	ensureWeekly(player, profile)
	player:SetAttribute("Weekly", HttpService:JSONEncode(profile.Weekly))
	player:SetAttribute("Title", profile.Title or TitleConfig.Default)
end

-- Daten für die Titel-Prüfung (TitleConfig.Progress)
function ProgressService.TitleData(player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	return { Stats = profile.Stats or {}, Prestige = profile.Prestige or 0,
		Level = (LevelConfig.FromXP(profile.AccountXP or 0)), Owned = profile.Owned or {} }
end

-- Titel auswählen (nur freigeschaltete)
function ProgressService.SetTitle(player, id)
	local profile = profiles[player]
	local title = typeof(id) == "string" and TitleConfig.Get(id)
	if not profile or not title then
		return "Unbekannter Titel.", false
	end
	if not TitleConfig.Unlocked(title, ProgressService.TitleData(player)) then
		return "Titel noch gesperrt: " .. title.Text .. ".", false
	end
	profile.Title = id
	player:SetAttribute("Title", id)
	return "Titel \"" .. title.Name .. "\" ausgewählt.", true
end

-- Battle-Pass-XP: neue Stufen schalten ihre Belohnung sofort frei
function ProgressService.AddPassXP(player, amount)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	local before = PassConfig.TierFromXP(profile.PassXP or 0)
	profile.PassXP = (profile.PassXP or 0) + amount
	local after = PassConfig.TierFromXP(profile.PassXP)
	for tier = before + 1, after do
		local reward = PassConfig.Tiers[tier]
		local text
		if reward.Coins then
			profile.Coins += reward.Coins
			text = "+" .. reward.Coins .. " Münzen"
		elseif reward.Item then
			profile.Owned[reward.Item] = true
			local item = Cosmetics.Get(reward.Item)
			text = "Skin \"" .. (item and item.Name or reward.Item) .. "\" freigeschaltet!"
		end
		Remotes.Announce:FireClient(player, "Battle Pass Stufe " .. tier .. ": " .. text)
	end
	ProgressService.Sync(player)
end

-- ---------- Statistik ----------
-- Dauerhafte Werte (Kills, Deaths, Assists, Headshots, Damage, ShotsFired, ShotsHit, Revives,
-- Plants, Defuses, Matches, Wins, Losses, RoundsWon, Kills_<AgentId>). Wird gebündelt gesynct.
local dirty = {}

function ProgressService.AddStat(player, key, amount)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Stats = profile.Stats or {}
	profile.Stats[key] = (profile.Stats[key] or 0) + (amount or 1)
	dirty[player] = true
end

-- ---------- Match-Abrechnung ----------
-- Sammelt XP und Münzen nach Grund (Kill, Matchsieg, Killserie, ...) seit Matchbeginn bzw. seit der letzten
-- Zusammenfassung, dazu Level, Prestige und ELO vom Anfang. Daraus baut TakeLedger die Belohnungs-Übersicht
-- am Matchende. Beim Moduswechsel fängt sie neu an (entsteht beim ersten Gewinn, also vor der Änderung).
local ledgers = {} -- [Player] = { Lines, Order, XP, Coins, Items, AccountXP, Prestige, Elo, AgentOfWeek }

local function ledgerOf(player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local ledger = ledgers[player]
	if not ledger then
		ledger = { Lines = {}, Order = {}, XP = 0, Coins = 0, Items = {}, AccountXP = profile.AccountXP or 0,
			Prestige = profile.Prestige or 0, Elo = ProgressService.GetElo(player) }
		ledgers[player] = ledger
	end
	return ledger
end

local function record(player, reason, xp, coins)
	local ledger = ledgerOf(player)
	if not ledger or (xp <= 0 and coins <= 0) then
		return
	end
	reason = tostring(reason or "Bonus")
	-- "Kill · Agent der Woche" zählt als "Kill", der Bonus steht einmal unten in der Übersicht
	local suffix = string.find(reason, " · Agent der Woche", 1, true)
	if suffix then
		ledger.AgentOfWeek = true
		reason = string.sub(reason, 1, suffix - 1)
	end
	local line = ledger.Lines[reason]
	if not line then
		line = { Name = reason, Count = 0, XP = 0, Coins = 0 }
		ledger.Lines[reason] = line
		table.insert(ledger.Order, line)
	end
	line.Count += 1
	line.XP += xp
	line.Coins += coins
	ledger.XP += xp
	ledger.Coins += coins
end

-- Neuer Gegenstand (z.B. Belohnungs-Skin) für die Übersicht
function ProgressService.LedgerItem(player, name, rarity)
	local ledger = ledgerOf(player)
	if ledger then
		table.insert(ledger.Items, { Name = name, Rarity = rarity })
	end
end

-- Übersicht für die Match-Zusammenfassung holen und neu anfangen:
-- { Lines = { { Name, Count, XP, Coins } }, XP, Coins, Items, AgentOfWeek,
--   Level = { Before, BeforeProgress, After, AfterProgress, PrestigeBefore, Prestige },
--   Elo = { Before, After, Matches } }
function ProgressService.TakeLedger(player)
	local ledger = ledgerOf(player)
	local profile = profiles[player]
	if not ledger or not profile then
		return nil
	end
	ledgers[player] = nil
	local lines = table.clone(ledger.Order)
	table.sort(lines, function(a, b)
		return a.XP + a.Coins * 4 > b.XP + b.Coins * 4
	end)
	local beforeLevel, beforeXP, beforeNeeded = LevelConfig.FromXP(ledger.AccountXP)
	local afterLevel, afterXP, afterNeeded = LevelConfig.FromXP(profile.AccountXP or 0)
	return {
		Lines = lines,
		XP = ledger.XP,
		Coins = ledger.Coins,
		Items = ledger.Items,
		AgentOfWeek = ledger.AgentOfWeek == true,
		Level = {
			Before = beforeLevel,
			BeforeProgress = beforeNeeded > 0 and beforeXP / beforeNeeded or 1,
			After = afterLevel,
			AfterProgress = afterNeeded > 0 and afterXP / afterNeeded or 1,
			XPLeft = afterNeeded > 0 and afterNeeded - afterXP or 0,
			PrestigeBefore = ledger.Prestige,
			Prestige = profile.Prestige or 0,
		},
		Elo = {
			Before = ledger.Elo,
			After = ProgressService.GetElo(player),
			Matches = ProgressService.GetRankedMatches(player),
		},
	}
end

-- ---------- Ranked (ELO) ----------

function ProgressService.GetElo(player)
	local profile = profiles[player]
	return profile and profile.Ranked and profile.Ranked.Elo or RankConfig.StartElo
end

-- Match-Verlauf: die letzten Matches (neuestes zuerst)
-- entry = { Mode, Map, Won (true/false/nil), Score, Kills, Deaths, Elo (Änderung oder nil) }
local HISTORY_SIZE = 10
function ProgressService.AddHistory(player, entry)
	local profile = profiles[player]
	if not profile then
		return
	end
	entry.Time = os.time()
	profile.History = profile.History or {}
	table.insert(profile.History, 1, entry)
	while #profile.History > HISTORY_SIZE do
		table.remove(profile.History)
	end
	player:SetAttribute("MatchHistory", HttpService:JSONEncode(profile.History))
end

function ProgressService.GetRankedMatches(player)
	local profile = profiles[player]
	return profile and profile.Ranked and profile.Ranked.Matches or 0
end

-- Ergebnis eines Ranked-Matches eintragen. Gibt die neue ELO zurück.
function ProgressService.ApplyRanked(player, change, won)
	local profile = profiles[player]
	if not profile then
		return RankConfig.StartElo
	end
	ledgerOf(player) -- ELO vor dem Match merken
	local ranked = profile.Ranked or { Elo = RankConfig.StartElo, Peak = RankConfig.StartElo, Wins = 0, Losses = 0, Matches = 0 }
	ranked.Elo = math.max(0, (ranked.Elo or RankConfig.StartElo) + change)
	ranked.Peak = math.max(ranked.Peak or 0, ranked.Elo)
	profile.Stats = profile.Stats or {}
	profile.Stats.BestElo = math.max(profile.Stats.BestElo or 0, ranked.Elo) -- höchste ELO je (Titel)
	ranked.Matches = (ranked.Matches or 0) + 1
	if won then
		ranked.Wins = (ranked.Wins or 0) + 1
	else
		ranked.Losses = (ranked.Losses or 0) + 1
	end
	profile.Ranked = ranked
	ProgressService.Sync(player)
	return ranked.Elo
end

-- Spielereignis für Aufträge zählen (event wie in QuestConfig, z.B. "Kill")
function ProgressService.QuestEvent(player, event, amount)
	local profile = profiles[player]
	if not profile then
		return
	end
	ensureQuests(player, profile)
	ensureWeekly(player, profile)
	local changed = false
	for _, set in { profile.Quests, profile.Weekly } do
		for _, id in set.Ids do
			local quest = QuestConfig.Get(id)
			if quest and quest.Event == event and not set.Claimed[id] then
				local before = set.Progress[id] or 0
				if before < quest.Goal then
					set.Progress[id] = math.min(quest.Goal, before + (amount or 1))
					changed = true
				end
			end
		end
	end
	if changed then
		ProgressService.Sync(player)
	end
end

-- Belohnung eines fertigen Auftrags abholen. Gibt Text und Erfolg zurück.
function ProgressService.ClaimQuest(player, id)
	local profile = profiles[player]
	local quest = typeof(id) == "string" and QuestConfig.Get(id)
	if not profile or not quest then
		return "Unbekannter Auftrag.", false
	end
	ensureWeekly(player, profile)
	local set = quest.Weekly and profile.Weekly or profile.Quests
	if not table.find(set.Ids or {}, id) then
		return "Unbekannter Auftrag.", false
	end
	if set.Claimed[id] then
		return "Schon abgeholt.", false
	end
	if (set.Progress[id] or 0) < quest.Goal then
		return "Auftrag noch nicht geschafft.", false
	end
	set.Claimed[id] = true
	ProgressService.AddCoins(player, quest.Reward, quest.Weekly and "Wochen-Auftrag" or "Auftrag") -- synct auch die Aufträge
	ProgressService.AddPassXP(player, quest.Weekly and PassConfig.QuestXP * 3 or PassConfig.QuestXP)
	return "+" .. quest.Reward .. " Münzen für \"" .. quest.Text .. "\"!", true
end

-- Wochen-Bonus abholen: alle Wochen-Aufträge abgeholt → Münzen + Skin der Woche
function ProgressService.ClaimWeeklyBonus(player)
	local profile = profiles[player]
	if not profile then
		return "Profil nicht geladen.", false
	end
	ensureWeekly(player, profile)
	local weekly = profile.Weekly
	if weekly.Bonus then
		return "Wochen-Bonus schon abgeholt.", false
	end
	for _, id in weekly.Ids do
		if not weekly.Claimed[id] then
			return "Erst alle Wochen-Aufträge abschließen und abholen.", false
		end
	end
	weekly.Bonus = true
	ProgressService.AddStat(player, "WeeklyBonus", 1)
	local lines = { "+" .. QuestConfig.WeeklyBonus.Coins .. " Münzen" }
	local skinId = QuestConfig.BonusSkin(weekly.Week)
	local skin = Cosmetics.Get(skinId)
	if skin and not profile.Owned[skinId] then
		profile.Owned[skinId] = true
		ProgressService.LedgerItem(player, skin.Name, skin.Rarity)
		table.insert(lines, "Neuer Skin: " .. skin.Name)
	end
	ProgressService.AddCoins(player, QuestConfig.WeeklyBonus.Coins, "Wochen-Bonus") -- synct alles
	Remotes.Reward:FireClient(player, { Title = "WOCHEN-BONUS", Lines = lines, Rarity = skin and skin.Rarity or nil })
	return "Wochen-Bonus abgeholt!", true
end

function ProgressService.Get(player)
	return profiles[player]
end

local function key(player)
	return "u" .. player.UserId
end

-- Neue Saison: Belohnung nach dem höchsten Rang der alten Saison (mit abgeschlossenen Platzierungsspielen),
-- dann ELO zur Hälfte Richtung Start, Platzierungsspiele neu. Gibt true zurück, wenn sich etwas geändert hat.
local function checkSeason(player, profile, test)
	local ranked = profile.Ranked
	local season = RankConfig.CurrentSeason()
	if not ranked or ((ranked.Season or 1) == season and not test) then
		return false
	end
	local oldSeason = ranked.Season or 1
	local played = (ranked.Matches or 0) > 0
	local reward, peakRank = nil, nil
	if (ranked.Matches or 0) >= RankConfig.PlacementMatches then
		peakRank = RankConfig.Get(ranked.Peak or ranked.Elo)
		for _, entry in RewardConfig.SeasonEnd do
			if entry.Tier == peakRank.Name then
				reward = entry
			end
		end
	end
	ranked.LastSeason = oldSeason
	ranked.LastSeasonPeak = ranked.Peak
	ranked.Elo = math.floor(((ranked.Elo or RankConfig.StartElo) + RankConfig.StartElo) / 2)
	ranked.Peak = ranked.Elo
	ranked.Matches, ranked.Wins, ranked.Losses = 0, 0, 0
	ranked.Season = season

	local lines, rarity = {}, nil
	if reward then
		table.insert(lines, "Höchster Rang: " .. peakRank.Display)
		profile.Coins += reward.Coins
		table.insert(lines, "+" .. reward.Coins .. " Münzen")
		local item = reward.Item and Cosmetics.Get(reward.Item)
		if item and not profile.Owned[item.Id] then
			profile.Owned[item.Id] = true
			table.insert(lines, "Neuer Skin: " .. item.Name)
			rarity = item.Rarity
		end
	end
	if played then
		table.insert(lines, "Saison " .. season .. " beginnt – ELO zur Hälfte zurückgesetzt")
		-- kurz warten, damit der Client das Popup schon anzeigen kann (beim Beitreten)
		task.delay(test and 0 or 8, function()
			if player.Parent then
				Remotes.Reward:FireClient(player, { Title = test and "SAISON-ENDE (TEST)" or ("SAISON " .. oldSeason .. " BEENDET"),
					Lines = lines, Rarity = rarity })
			end
		end)
	end
	return true
end

-- Admin: Saison-Ende mit der aktuellen ELO testen (Belohnung + Zurücksetzen, Saison bleibt gleich)
function ProgressService.TestSeasonEnd(player)
	local profile = profiles[player]
	if not profile or not profile.Ranked then
		return false
	end
	profile.Ranked.Matches = math.max(profile.Ranked.Matches or 0, RankConfig.PlacementMatches)
	checkSeason(player, profile, true)
	ProgressService.Sync(player)
	return true
end

local function load(player)
	-- Neuer Modus = neue Match-Abrechnung
	player:GetAttributeChangedSignal("Mode"):Connect(function()
		ledgers[player] = nil
	end)
	profiles[player] = defaultProfile()
	ProgressService.Sync(player)
	if not store then
		return
	end
	local ok, result = pcall(store.GetAsync, store, key(player))
	if ok then
		profiles[player] = toProfile(result)
		checkSeason(player, profiles[player]) -- neue Ranked-Saison seit dem letzten Besuch?
		loaded[player] = true
		ProgressService.Sync(player)
	else
		warn("Spielerdaten konnten nicht geladen werden: " .. tostring(result))
	end
end

local function save(player)
	local profile = profiles[player]
	if not store or not loaded[player] or not profile then
		return
	end
	local ok, err = pcall(store.SetAsync, store, key(player), profile)
	if not ok then
		warn("Spielerdaten konnten nicht gespeichert werden: " .. tostring(err))
	end
end

-- Agent, mit dem der Spieler gerade spielt (sonst der gewählte)
function ProgressService.ActiveAgent(player)
	local character = player.Character
	return (character and character:GetAttribute("Agent")) or player:GetAttribute("Agent") or AgentConfig.Agents[1].Id
end

-- ---------- Münzen ----------

-- reason: wofür (erscheint in der Belohnungs-Übersicht am Matchende)
function ProgressService.AddCoins(player, amount, reason)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	ledgerOf(player)
	profile.Coins += math.floor(amount)
	record(player, reason, 0, math.floor(amount))
	ProgressService.Sync(player)
end

-- Gibt true zurück, wenn genug Münzen da waren
function ProgressService.SpendCoins(player, amount)
	local profile = profiles[player]
	if not profile or profile.Coins < amount then
		return false
	end
	profile.Coins -= amount
	ProgressService.Sync(player)
	return true
end

-- ---------- Waffen-Aufsätze (Lobby) ----------

local function attachmentData(profile)
	profile.Attachments = profile.Attachments or {}
	profile.Attachments.Owned = profile.Attachments.Owned or {}
	profile.Attachments.Equipped = profile.Attachments.Equipped or {}
	return profile.Attachments
end

-- Aufsatz für eine Waffe kaufen (gilt für alle Agenten mit dieser Waffe) und gleich ausrüsten
function ProgressService.BuyAttachment(player, weaponName, id)
	local profile = profiles[player]
	local item = AttachmentConfig.Get(id)
	if not profile or not item or not WeaponConfig.Get(weaponName) then
		return "Unbekannter Aufsatz.", false
	end
	local data = attachmentData(profile)
	data.Owned[weaponName] = data.Owned[weaponName] or {}
	if data.Owned[weaponName][id] then
		return "Schon gekauft.", false
	end
	if profile.Coins < item.Price then
		return "Nicht genug Münzen (" .. item.Price .. " nötig).", false
	end
	profile.Coins -= item.Price
	data.Owned[weaponName][id] = true
	data.Equipped[weaponName] = data.Equipped[weaponName] or {}
	data.Equipped[weaponName][item.Slot] = id
	ProgressService.Sync(player)
	return item.Name .. " gekauft und ausgerüstet.", true
end

-- Aufsatz ausrüsten bzw. (nochmal angeklickt) wieder abnehmen
function ProgressService.ToggleAttachment(player, weaponName, id)
	local profile = profiles[player]
	local item = AttachmentConfig.Get(id)
	if not profile or not item then
		return "Unbekannter Aufsatz.", false
	end
	local data = attachmentData(profile)
	if not (data.Owned[weaponName] and data.Owned[weaponName][id]) then
		return "Noch nicht gekauft.", false
	end
	data.Equipped[weaponName] = data.Equipped[weaponName] or {}
	local slots = data.Equipped[weaponName]
	if slots[item.Slot] == id then
		slots[item.Slot] = nil
		ProgressService.Sync(player)
		return item.Name .. " abgenommen.", true
	end
	slots[item.Slot] = id
	ProgressService.Sync(player)
	return item.Name .. " ausgerüstet.", true
end

-- ---------- Skins ----------

function ProgressService.Owns(player, itemId)
	local profile = profiles[player]
	return profile ~= nil and profile.Owned[itemId] == true
end

function ProgressService.GiveItem(player, itemId)
	local profile = profiles[player]
	if profile then
		profile.Owned[itemId] = true
		ProgressService.Sync(player)
	end
end

-- slot = "W:<Waffe>" oder "A:<Agent>", itemId = nil zum Ablegen
function ProgressService.SetEquipped(player, slot, itemId)
	local profile = profiles[player]
	if profile then
		profile.Equipped[slot] = itemId
		ProgressService.Sync(player)
	end
end

-- ---------- XP ----------

-- XP für einen Agenten vergeben (+ Münzen, außer bei Admin-XP). reason wird angezeigt.
function ProgressService.AddXP(player, agentId, amount, reason)
	local profile = profiles[player]
	if not profile or not AgentConfig.Get(agentId) then
		return
	end
	amount = math.floor(amount * GameSettings.Get("XPMultiplier"))
	-- Agent der Woche: +50 % XP
	if reason ~= "Admin" and agentId == AgentConfig.AgentOfWeek().Id then
		amount = math.floor(amount * AgentConfig.AgentOfWeekXP)
		reason = tostring(reason) .. " · Agent der Woche"
	end
	if amount <= 0 then
		return
	end
	ledgerOf(player) -- Stand vor diesen XP merken (Level-Fortschritt in der Übersicht)
	local before = profile.XP[agentId] or 0
	local maxXP = AgentConfig.XPPerLevel * (AgentConfig.MaxLevel - 1)
	local after = math.min(before + amount, maxXP)
	profile.XP[agentId] = after
	-- Spielerlevel: alle XP zählen (auch wenn der Agent schon Max-Level ist)
	profile.AccountXP = math.min((profile.AccountXP or 0) + amount, LevelConfig.MaxXP)

	local coins = reason ~= "Admin" and math.floor(amount * Cosmetics.CoinsPerXP) or 0
	profile.Coins += coins
	record(player, reason, amount, coins)
	ProgressService.Sync(player)

	local levelUp = AgentConfig.LevelFromXP(after) > AgentConfig.LevelFromXP(before)
	Remotes.XPGain:FireClient(player, after - before, reason, agentId, levelUp, coins)
	-- Alle XP zählen auch für den Battle Pass (auch wenn der Agent schon Max-Level ist)
	if reason ~= "Admin" then
		ProgressService.AddPassXP(player, amount)
	end
end

-- Prestige: nur auf Max-Level. Level zurück auf 1, Prestige +1, Münzen als Belohnung.
function ProgressService.Prestige(player)
	local profile = profiles[player]
	if not profile then
		return "Profil nicht geladen.", false
	end
	local level = LevelConfig.FromXP(profile.AccountXP or 0)
	local prestige = profile.Prestige or 0
	if level < LevelConfig.MaxLevel then
		return "Prestige erst ab Level " .. LevelConfig.MaxLevel .. ".", false
	end
	if prestige >= LevelConfig.MaxPrestige then
		return "Du hast schon das höchste Prestige.", false
	end
	profile.Prestige = prestige + 1
	profile.AccountXP = 0
	local coins = LevelConfig.PrestigeCoins * profile.Prestige
	profile.Coins += coins
	ProgressService.Sync(player)
	Remotes.Announce:FireClient(player, "PRESTIGE " .. profile.Prestige .. "!  +" .. coins .. " Münzen")
	return "Prestige " .. profile.Prestige .. " erreicht!", true
end

-- Admin: ELO direkt setzen (Peak steigt mit, Spiele/Siege bleiben)
function ProgressService.SetElo(player, elo)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local ranked = profile.Ranked or { Elo = RankConfig.StartElo, Peak = RankConfig.StartElo, Wins = 0, Losses = 0, Matches = 0 }
	ranked.Elo = math.clamp(math.floor(tonumber(elo) or RankConfig.StartElo), 0, 5000)
	ranked.Peak = math.max(ranked.Peak or 0, ranked.Elo)
	profile.Stats = profile.Stats or {}
	profile.Stats.BestElo = math.max(profile.Stats.BestElo or 0, ranked.Elo)
	profile.Ranked = ranked
	ProgressService.Sync(player)
	return ranked.Elo
end

-- Admin: Prestige und Level direkt setzen (prestige 0..MaxPrestige, level 1..MaxLevel)
function ProgressService.SetPrestige(player, prestige, level)
	local profile = profiles[player]
	if not profile then
		return false
	end
	profile.Prestige = math.clamp(math.floor(tonumber(prestige) or 0), 0, LevelConfig.MaxPrestige)
	local xp = 0
	for l = 1, math.clamp(math.floor(tonumber(level) or 1), 1, LevelConfig.MaxLevel) - 1 do
		xp += LevelConfig.XPForLevel(l)
	end
	profile.AccountXP = xp
	ProgressService.Sync(player)
	return true
end

function ProgressService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("PlayerData_v1")
	end)
	if ok then
		store = result
	else
		warn("DataStore nicht verfügbar, Fortschritt wird nicht gespeichert: " .. tostring(result))
	end

	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
		loaded[player] = nil
		ledgers[player] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			save(player)
		end
	end)
	-- Saisonwechsel, während Spieler online sind
	task.spawn(function()
		while true do
			task.wait(60)
			for player, profile in profiles do
				if loaded[player] and checkSeason(player, profile) then
					ProgressService.Sync(player)
				end
			end
		end
	end)
	-- Statistik gebündelt alle 2 Sekunden an die Clients
	task.spawn(function()
		while true do
			task.wait(2)
			for player in dirty do
				dirty[player] = nil
				if player.Parent then
					player:SetAttribute("Stats", HttpService:JSONEncode(profiles[player] and profiles[player].Stats or {}))
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				task.spawn(save, player)
			end
		end
	end)
end

return ProgressService

-- ProgressService (ModuleScript, nur Server)
-- Alle gespeicherten Spielerdaten: XP pro Agent, Münzen, gekaufte und ausgerüstete Skins,
-- tägliche Belohnung, eingelöste Codes und tägliche Aufträge. Gespeichert im DataStore (funktioniert erst, wenn
-- das Spiel veröffentlicht ist und in Studio "API Services" erlaubt sind - sonst nur für die Sitzung).
-- Spieler-Attribute für die Clients: XP_<AgentId>, Coins, Owned (JSON { [Id] = Stückzahl }), Equipped (JSON),
-- LastDaily, Quests (JSON), Rap (RAP-Guthaben), RapValue (RAP-Wert aller handelbaren Skins, RapConfig)
-- Sicherheit der Spielstände: Laden und Speichern über SessionStore (Sitzungssperre pro Server, Speichern nur mit
-- eigener Sperre, Wiederholungen bei DataStore-Fehlern). Lässt sich ein Profil gar nicht laden, wird der Spieler im
-- Live-Spiel mit Hinweis gekickt (sonst spielte er ohne Speichern weiter, Fortschritt und Käufe gingen verloren).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local AgentConfig = require(Shared.AgentConfig)
local GameSettings = require(Shared.GameSettings)
local Cosmetics = require(Shared.Cosmetics)
local QuestConfig = require(Shared.QuestConfig)
local PassConfig = require(Shared.PassConfig)
local RankConfig = require(Shared.RankConfig)
local LevelConfig = require(Shared.LevelConfig)
local ExtLevelConfig = require(Shared.ExtLevelConfig)
local RewardConfig = require(Shared.RewardConfig)
local TitleConfig = require(Shared.TitleConfig)
local LoginConfig = require(Shared.LoginConfig)
local RobuxConfig = require(Shared.RobuxConfig)
local AttachmentConfig = require(Shared.AttachmentConfig)
local WeaponConfig = require(Shared.WeaponConfig)
local RapConfig = require(Shared.RapConfig)
local SessionStore = require(script.Parent.SessionStore)

local Telemetry = require(script.Parent.Telemetry)
local DiscordLog = require(script.Parent.DiscordLog)

local ProgressService = {}

local AUTOSAVE_INTERVAL = 120 -- Sekunden (erneuert auch die Sitzungssperre, siehe SessionStore.LockTimeout)
local SHUTDOWN_WAIT = 25      -- beim Herunterfahren höchstens so lange auf das Speichern warten
local LOAD_FAILED = "Dein Spielstand konnte gerade nicht geladen werden. Bitte tritt gleich noch einmal bei."

local store = nil   -- SessionStore (nil ohne DataStore, z.B. Studio ohne API-Zugriff)
local beforeSave = {} -- Rückrufe vor jedem Speichern (z.B. Inventar der offenen Welt ins Profil schreiben)
local leaving = {}    -- Rückrufe, wenn ein Spieler das Spiel verlässt, vor dem letzten Speichern
local shuttingDown = false
local profiles = {} -- [Player] = Profil
local loaded = {}   -- [Player] = true, wenn erfolgreich geladen und gesperrt (nur dann speichern)
local sessionOnly = {} -- [Player] = true: in Studio ließ sich nicht laden – Stand gilt nur für diese Sitzung

-- Endliche Zahl (kein NaN, kein ±∞): Beträge von Münzen und RAP prüfen. NaN rutscht sonst durch jeden Vergleich
-- ("x < NaN" und "x > NaN" sind beide falsch) und macht den Kontostand unbegrenzt.
local function finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function defaultProfile()
	return { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {}, LastDaily = 0, Codes = {}, Quests = {}, RankPoints = 0, PassXP = 0, Agents = {}, Settings = {},
		Stats = {}, Loadouts = {}, Attachments = { Owned = {}, Equipped = {} }, AccountXP = 0, Prestige = 0, LevelMerged = true, Ranked = { Elo = RankConfig.StartElo, Peak = RankConfig.StartElo, Wins = 0, Losses = 0, Matches = 0,
		Season = RankConfig.CurrentSeason() } }
end

-- Alte Spielstände: Skins, die es nicht mehr gibt (z.B. die entfernten Agenten-Skins), fallen aus Besitz und
-- Merkliste weg; ausgerüstet bleiben nur bekannte Waffen-Skins ("W:<Waffe>") und der Agenten-Skin ("Agent"; die alten
-- Plätze "A:<Agent>" je Agent gibt es nicht mehr). So sehen Inventar, RAP-Wert, Markt und Tausch nur Skins aus Cosmetics.
local function cleanItems(profile)
	local owned = {}
	for id, count in type(profile.Owned) == "table" and profile.Owned or {} do
		if Cosmetics.Get(id) then
			owned[id] = count
		end
	end
	profile.Owned = owned
	local equipped = {}
	for slot, id in type(profile.Equipped) == "table" and profile.Equipped or {} do
		local item = Cosmetics.Get(id)
		if type(slot) == "string" and item and ((string.sub(slot, 1, 2) == "W:" and item.Type == "Weapon")
			or (slot == "Agent" and item.Type == "Agent")) then
			equipped[slot] = id
		end
	end
	profile.Equipped = equipped
	if type(profile.MarketWatch) == "table" then
		local watch = {}
		for id, on in profile.MarketWatch do
			if Cosmetics.Get(id) then
				watch[id] = on
			end
		end
		profile.MarketWatch = watch
	end
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
	-- Früher gab es ein eigenes Extinction-Level (Statistik ExtXP): einmalig ins Spielerlevel übernehmen. Die EP kommen
	-- dazu, mindestens aber so viel, dass das Spielerlevel nicht unter dem alten Extinction-Level liegt.
	if data.LevelMerged == nil then
		local extXP = tonumber(type(profile.Stats) == "table" and profile.Stats[ExtLevelConfig.Stat]) or 0
		if extXP > 0 then
			local extLevel = ExtLevelConfig.FromXP(extXP)
			local floor = 0
			for level = 1, math.min(extLevel, LevelConfig.MaxLevel) - 1 do
				floor += LevelConfig.XPForLevel(level)
			end
			local accountXP = tonumber(profile.AccountXP) or 0
			profile.AccountXP = math.min(math.max(accountXP + extXP, floor), LevelConfig.MaxXP)
		end
		profile.LevelMerged = true
	end
	cleanItems(profile)
	return profile
end

-- Aufträge für heute anlegen, falls ein neuer Tag begonnen hat (pro Spieler und Tag gleich)
local function ensureQuests(player, profile)
	local today = QuestConfig.Today()
	if profile.Quests.Day == today then
		return
	end
	local random = Random.new(player.UserId + tonumber((string.gsub(today, "-", ""))))
	-- Arcade aus: keine neuen Arcade-Aufträge (der Satz bleibt leer, bis Arcade wieder an ist)
	local pool = QuestConfig.ModeActive("Arcade") and table.clone(QuestConfig.Pool) or {}
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
	local pool = QuestConfig.ModeActive("Arcade") and table.clone(QuestConfig.WeeklyPool) or {}
	local ids = {}
	for _ = 1, math.min(QuestConfig.PerWeek, #pool) do
		local quest = table.remove(pool, random:NextInteger(1, #pool))
		table.insert(ids, quest.Id)
	end
	profile.Weekly = { Week = week, Ids = ids, Progress = {}, Claimed = {}, Bonus = false }
end

-- Weitere Sätze (QuestConfig.Sets: Extinction, VIP & BOOSTER) für den aktuellen Tag bzw. die aktuelle Woche anlegen
local function ensureSet(player, profile, set)
	local period = set.Period == "Week" and QuestConfig.Week() or QuestConfig.Today()
	local current = profile[set.Key]
	if type(current) == "table" and current.Period == period then
		return current
	end
	local seed = set.Period == "Week" and period or tonumber((string.gsub(period, "-", "")))
	local random = Random.new(player.UserId * 13 + seed + #set.Key * 101)
	local ids = {}
	for _, pick in set.Picks do
		local pool = {}
		for _, quest in pick.Pool do
			-- Arcade aus: keine Arcade-Aufträge (auch nicht bei VIP & BOOSTER)
			if (not pick.Mode or quest.Mode == pick.Mode) and QuestConfig.ModeActive(quest.Mode) then
				table.insert(pool, quest)
			end
		end
		for _ = 1, math.min(pick.Count, #pool) do
			local quest = table.remove(pool, random:NextInteger(1, #pool))
			if quest then
				table.insert(ids, quest.Id)
			end
		end
	end
	profile[set.Key] = { Period = period, Ids = ids, Progress = {}, Claimed = {} }
	return profile[set.Key]
end

-- Nur die Aufträge als Attribute senden (QuestEvent: jeder Zombie-Kill zählt, da wäre ein ganzes Sync viel zu teuer)
local function publishQuests(player, profile)
	ensureQuests(player, profile)
	player:SetAttribute("Quests", HttpService:JSONEncode(profile.Quests))
	ensureWeekly(player, profile)
	player:SetAttribute("Weekly", HttpService:JSONEncode(profile.Weekly))
	for _, set in QuestConfig.Sets do
		player:SetAttribute(set.Key, HttpService:JSONEncode(ensureSet(player, profile, set)))
	end
end

-- Extra-Belohnung von Extinction-Aufträgen (Loot ins Lager, RZ): setzt Modes/Extinction,
-- function(player, quest) -> Liste von Texten
ProgressService.QuestExtras = nil

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
	player:SetAttribute("Rap", math.floor(tonumber(profile.Rap) or 0))
	player:SetAttribute("RapValue", RapConfig.InventoryValue(profile.Owned))
	-- Creator-Skins stehen nicht im Spielstand: nur anzeigen, solange der Team-Rang reicht
	local owned = profile.Owned
	if Cosmetics.CreatorUnlocked(player) then
		owned = table.clone(profile.Owned)
		for _, id in Cosmetics.CreatorItems() do
			owned[id] = 1
		end
	end
	player:SetAttribute("Owned", HttpService:JSONEncode(owned))
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
	publishQuests(player, profile)
	player:SetAttribute("Title", profile.Title or TitleConfig.Default)
	player:SetAttribute("LoginData", HttpService:JSONEncode(profile.Login or {}))
	player:SetAttribute("WheelData", HttpService:JSONEncode(profile.Wheel or {}))
	player:SetAttribute("XPBoostUntil", profile.XPBoostUntil or 0)
end

-- ---------- Doppel-XP, Login-Kalender, Glücksrad (LoginConfig) ----------

-- Doppel-XP für minutes Minuten (verlängert einen laufenden Boost)
function ProgressService.AddXPBoost(player, minutes)
	local profile = profiles[player]
	if profile then
		profile.XPBoostUntil = math.max(profile.XPBoostUntil or 0, os.time()) + minutes * 60
		ProgressService.Sync(player)
	end
end

-- Extra-Drehs fürs Glücksrad (Kalender-Tag 7, später Robux-Shop)
function ProgressService.AddSpins(player, amount)
	local profile = profiles[player]
	if profile then
		profile.Wheel = profile.Wheel or {}
		profile.Wheel.Spins = (profile.Wheel.Spins or 0) + amount
		ProgressService.Sync(player)
	end
end

-- Skin als Belohnung geben: handelbare Skins (mit RAP-Wert) gibt es auch als weiteres Stück (Duplikat zum
-- Verkaufen oder Tauschen), gebundene nur einmal. Gibt "new", "copy" oder nil (schon im Besitz) zurück.
local function grantSkin(profile, itemId)
	local count = RapConfig.Count(profile.Owned, itemId)
	if count > 0 and not RapConfig.Tradeable(itemId) then
		return nil
	end
	profile.Owned[itemId] = count + 1
	return count > 0 and "copy" or "new"
end

-- Für andere Dienste (Robux-Paket): wie grantSkin, mit Sync
function ProgressService.GrantSkin(player, itemId)
	local profile = profiles[player]
	local result = profile and Cosmetics.Get(itemId) and grantSkin(profile, itemId) or nil
	if result then
		ProgressService.Sync(player)
	end
	return result
end

-- Belohnung (Coins, BoostMinutes, Spins, Item) geben; gibt die Textzeilen fürs Popup zurück
local function giveBundle(player, profile, reward, reason)
	local lines = {}
	local coins = reward.Coins or 0
	local item = reward.Item and Cosmetics.Get(reward.Item)
	local granted = item and grantSkin(profile, item.Id)
	if item and granted then
		ProgressService.LedgerItem(player, item.Name, item.Rarity)
		table.insert(lines, (granted == "copy" and "Skin-Duplikat: " or "Neuer Skin: ") .. item.Name)
		if reward.Item and reward.Coins and reward.Text == "SKIN" then
			coins = 0 -- Glücksrad: Skin statt Münzen
		end
	end
	if coins > 0 then
		ProgressService.AddCoins(player, coins, reason)
		table.insert(lines, 1, "+" .. coins .. " Münzen")
	end
	if reward.BoostMinutes then
		ProgressService.AddXPBoost(player, reward.BoostMinutes)
		table.insert(lines, reward.BoostMinutes .. " Min. Doppel-XP")
	end
	if reward.Spins then
		ProgressService.AddSpins(player, reward.Spins)
		table.insert(lines, "+" .. reward.Spins .. " Glücksrad-Dreh")
	end
	ProgressService.Sync(player)
	return lines
end

-- Login-Kalender: heutigen Tag abholen
function ProgressService.ClaimLogin(player)
	local profile = profiles[player]
	if not profile then
		return "Daten werden noch geladen.", false
	end
	local now = workspace:GetServerTimeNow()
	profile.Login = profile.Login or {}
	if not LoginConfig.CanClaim(profile.Login, now) then
		return "Heute schon abgeholt – morgen geht's weiter.", false
	end
	local day = LoginConfig.NextDay(profile.Login, now)
	profile.Login = { Day = day, Date = LoginConfig.Date(now) }
	local lines = giveBundle(player, profile, LoginConfig.Days[day], "Login-Bonus")
	Remotes.Reward:FireClient(player, { Title = "LOGIN-BONUS · TAG " .. day, Lines = lines,
		Rarity = day == #LoginConfig.Days and "Legendary" or nil })
	return "Tag " .. day .. " abgeholt!", true
end

-- Glücksrad drehen (einmal am Tag gratis, sonst mit Extra-Dreh). Das Ergebnis geht als WheelResult an den
-- Client, der das Rad dorthin dreht; die Meldung kommt erst danach (darum hier kein Text).
function ProgressService.SpinWheel(player)
	local profile = profiles[player]
	if not profile then
		return "Daten werden noch geladen.", false
	end
	local now = workspace:GetServerTimeNow()
	profile.Wheel = profile.Wheel or {}
	if profile.Wheel.Date == LoginConfig.Date(now) then
		if (profile.Wheel.Spins or 0) <= 0 then
			return "Heute schon gedreht. Extra-Drehs gibt es im Login-Kalender.", false
		end
		profile.Wheel.Spins -= 1
	else
		profile.Wheel.Date = LoginConfig.Date(now)
	end
	local total = 0
	for _, field in LoginConfig.Wheel do
		total += field.Weight
	end
	local roll, index = math.random() * total, #LoginConfig.Wheel
	for i, field in LoginConfig.Wheel do
		roll -= field.Weight
		if roll <= 0 then
			index = i
			break
		end
	end
	local field = LoginConfig.Wheel[index]
	local lines = giveBundle(player, profile, field, "Glücksrad")
	Remotes.WheelResult:FireClient(player, index, table.concat(lines, "  ·  "))
	if index == #LoginConfig.Wheel then -- letztes Feld = JACKPOT
		DiscordLog.Log("Highlight", "Glücksrad-Jackpot", table.concat(lines, " · "), { { "Spieler", DiscordLog.Who(player) } })
	end
	return nil
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
			profile.Owned[reward.Item] = math.max(RapConfig.Count(profile.Owned, reward.Item), 1)
			local item = Cosmetics.Get(reward.Item)
			text = "Skin " .. (item and item.Name or reward.Item) .. " freigeschaltet"
		end
		Remotes.Notify:FireClient(player, "Progress", { Caption = "Battle Pass", Title = "Stufe " .. tier, Sub = text,
			Badge = tostring(tier), Style = "Pass" })
	end
	ProgressService.Sync(player)
end

-- ---------- Statistik ----------
-- Dauerhafte Werte (Kills, Deaths, Assists, Headshots, Damage, ShotsFired, ShotsHit, Revives,
-- Plants, Defuses, Matches, Wins, Losses, RoundsWon, Kills_<AgentId>). Wird gebündelt gesynct.
local dirty = {}
-- Rückrufe function(player, key, value) nach jeder Änderung einer Statistik (z.B. Erfolge)
ProgressService.OnLoaded = {} -- Rückrufe function(player) nach dem Laden des Profils (Badges, …)
ProgressService.OnStat = {}

function ProgressService.AddStat(player, key, amount)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Stats = profile.Stats or {}
	profile.Stats[key] = (profile.Stats[key] or 0) + (amount or 1)
	dirty[player] = true
	for _, callback in ProgressService.OnStat do
		local ok, err = pcall(callback, player, key, profile.Stats[key])
		if not ok then
			warn("ProgressService.OnStat: " .. tostring(err))
		end
	end
end

-- ---------- Match-Abrechnung ----------
-- Sammelt XP und Münzen nach Grund (Kill, Matchsieg, Killserie, ...) seit Matchbeginn bzw. seit der letzten
-- Zusammenfassung, dazu Level, Prestige und ELO vom Anfang. Daraus baut TakeLedger die Belohnungs-Übersicht
-- am Matchende. Beim Moduswechsel fängt sie neu an (entsteht beim ersten Gewinn, also vor der Änderung).
local ledgers = {} -- [Player] = { Lines, Order, XP, Coins, Items, AccountXP, Prestige, Elo, DoubleXP }

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
	-- "Kill · Doppel-XP" zählt als "Kill", der Bonus steht einmal unten in der Übersicht
	if string.find(reason, " · Doppel-XP", 1, true) then
		ledger.DoubleXP = true
	end
	local suffix = string.find(reason, " · ", 1, true)
	if suffix then
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
-- { Lines = { { Name, Count, XP, Coins } }, XP, Coins, Items, DoubleXP,
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
		DoubleXP = ledger.DoubleXP == true,
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
	local sets = { profile.Quests, profile.Weekly }
	for _, def in QuestConfig.Sets do
		table.insert(sets, ensureSet(player, profile, def))
	end
	-- Arcade-Aufträge zählen nicht in der offenen Welt, VIP & BOOSTER nur für Berechtigte
	local inExtinction = player:GetAttribute("Mode") == "Extinction"
	local special = QuestConfig.IsSpecial(player)
	local changed = false
	for _, set in sets do
		for _, id in set.Ids do
			local quest = QuestConfig.Get(id)
			if quest and quest.Event == event and not set.Claimed[id]
				and not (quest.Mode == "Arcade" and inExtinction) and (special or not quest.Special) then
				local before = set.Progress[id] or 0
				if before < quest.Goal then
					set.Progress[id] = math.min(quest.Goal, before + (amount or 1))
					changed = true
				end
			end
		end
	end
	if changed then
		publishQuests(player, profile)
	end
end

-- Belohnung eines fertigen Auftrags abholen. Gibt Text und Erfolg zurück.
function ProgressService.ClaimQuest(player, id)
	local profile = profiles[player]
	local quest = typeof(id) == "string" and QuestConfig.Get(id)
	if not profile or not quest then
		return "Unbekannter Auftrag.", false
	end
	ensureQuests(player, profile)
	ensureWeekly(player, profile)
	local def = quest.Set and QuestConfig.GetSet(quest.Set)
	local set = def and ensureSet(player, profile, def) or (quest.Weekly and profile.Weekly or profile.Quests)
	if quest.Special and not QuestConfig.IsSpecial(player) then
		return "Nur für VIP & BOOSTER.", false
	end
	if not table.find(set.Ids or {}, id) then
		publishQuests(player, profile) -- meist ein neuer Tag: die neuen Aufträge sofort zeigen
		return "Neuer Tag – die Aufträge wurden erneuert.", false
	end
	if set.Claimed[id] then
		return "Schon abgeholt.", false
	end
	if (set.Progress[id] or 0) < quest.Goal then
		return "Auftrag noch nicht geschafft.", false
	end
	set.Claimed[id] = true
	local lines = { "+" .. quest.Reward .. " Münzen" }
	if quest.Spins then
		ProgressService.AddSpins(player, quest.Spins)
		table.insert(lines, "+" .. quest.Spins .. " Glücksrad-Drehs")
	end
	local item = quest.Item and Cosmetics.Get(quest.Item)
	if item and grantSkin(profile, item.Id) then
		ProgressService.LedgerItem(player, item.Name, item.Rarity)
		table.insert(lines, "Neuer Skin: " .. item.Name)
	end
	if (quest.Loot or quest.RedPoints) and ProgressService.QuestExtras then
		local ok, extra = pcall(ProgressService.QuestExtras, player, quest)
		if ok and type(extra) == "table" then
			table.move(extra, 1, #extra, #lines + 1, lines)
		end
	end
	ProgressService.AddCoins(player, quest.Reward, quest.Weekly and "Wochen-Auftrag" or "Auftrag") -- synct auch die Aufträge
	ProgressService.AddPassXP(player, quest.Weekly and PassConfig.QuestXP * 3 or PassConfig.QuestXP)
	if #lines > 1 then
		Remotes.Reward:FireClient(player, { Title = quest.Special and "VIP-AUFTRAG" or "AUFTRAG", Lines = lines })
	end
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
	if #weekly.Ids == 0 then
		return "Erst alle Wochen-Aufträge abschließen und abholen.", false -- Arcade aus: keine Wochen-Aufträge, kein Bonus
	end
	for _, id in weekly.Ids do
		if QuestConfig.Get(id) and not weekly.Claimed[id] then -- entfernte Aufträge sperren den Bonus nicht
			return "Erst alle Wochen-Aufträge abschließen und abholen.", false
		end
	end
	weekly.Bonus = true
	ProgressService.AddStat(player, "WeeklyBonus", 1)
	local lines = { "+" .. QuestConfig.WeeklyBonus.Coins .. " Münzen" }
	local skinId = QuestConfig.BonusSkin(weekly.Week)
	local skin = Cosmetics.Get(skinId)
	local granted = skin and grantSkin(profile, skinId)
	if skin and granted then
		ProgressService.LedgerItem(player, skin.Name, skin.Rarity)
		table.insert(lines, (granted == "copy" and "Skin-Duplikat: " or "Neuer Skin: ") .. skin.Name)
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
		-- kurz warten, damit der Client die Belohnungs-Karte schon anzeigen kann (beim Beitreten)
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
	-- Team-Rang geändert: Creator-Skins frei bzw. gesperrt
	player:GetAttributeChangedSignal("StaffRank"):Connect(function()
		ProgressService.Sync(player)
	end)
	profiles[player] = defaultProfile()
	ProgressService.Sync(player)
	if not store then
		return
	end
	local status, result = store:Load(key(player), function()
		return player.Parent ~= nil
	end)
	if status == "gone" then
		return
	end
	if status ~= "ok" then
		warn("Spielerdaten konnten nicht geladen werden: " .. tostring(result))
		if not RunService:IsStudio() then
			player:Kick(LOAD_FAILED) -- nicht ohne Speichern weiterspielen
		else
			sessionOnly[player] = true -- Studio ohne DataStore-Zugriff: mit leerem Stand weitertesten (wird nicht gespeichert)
		end
		return
	end
	local profile = toProfile(result)
	profiles[player] = profile
	local refund = ProgressService.RefundUnfitAttachments(profile) -- Aufsätze, die nicht (mehr) auf ihre Waffe passen
	if refund > 0 then
		Telemetry.Economy(player, "Source", "Coins", refund, profile.Coins, "Gameplay", "UnfitAttachments", "Aufsatz passt nicht")
	end
	checkSeason(player, profile) -- neue Ranked-Saison seit dem letzten Besuch?
	loaded[player] = true
	ProgressService.Sync(player)
	Telemetry.Onboarding(player, 1, "Joined")
	for _, callback in ProgressService.OnLoaded do
		task.spawn(callback, player)
	end
end

-- Speichern (nur mit eigener Sperre). release = Sperre dabei freigeben (Spieler geht, Server fährt herunter).
-- Gibt true zurück, wenn der Stand sicher gespeichert ist.
local function save(player, release)
	for _, callback in beforeSave do
		local ok, err = pcall(callback, player)
		if not ok then
			warn("Vor dem Speichern: " .. tostring(err))
		end
	end
	local profile = profiles[player]
	if not store or not loaded[player] or not profile then
		return false
	end
	local status, err = store:Save(key(player), profile, release)
	if status == "lost" then
		loaded[player] = nil -- ein anderer Server hat das Profil übernommen: hier nicht mehr speichern
		warn("Spielerdaten von " .. player.Name .. " werden inzwischen auf einem anderen Server gespeichert")
	elseif status ~= "ok" then
		warn("Spielerdaten konnten nicht gespeichert werden: " .. tostring(err))
	end
	return status == "ok"
end

-- callback(player) läuft vor jedem Speichern (auch beim Verlassen und Herunterfahren)
function ProgressService.OnBeforeSave(callback)
	table.insert(beforeSave, callback)
end

-- callback(player) läuft, wenn ein Spieler das Spiel verlässt, vor dem letzten Speichern – nicht beim
-- Herunterfahren des Servers (dann darf niemand etwas verlieren, siehe IsShuttingDown)
function ProgressService.OnLeaving(callback)
	table.insert(leaving, callback)
end

-- Fährt der Server gerade herunter (BindToClose)?
function ProgressService.IsShuttingDown()
	return shuttingDown
end

-- Sofort speichern (z.B. nach einem Robux-Kauf). Gibt true zurück, wenn der Stand sicher gespeichert ist – ohne
-- DataStore (unveröffentlichter Ort in Studio) gibt es nichts zu speichern, der Stand gilt nur für die Sitzung.
function ProgressService.SaveNow(player)
	if not store then
		return profiles[player] ~= nil
	end
	return save(player)
end

-- Admin (Suche): Profil einer UserId nur lesen, auch offline (ohne Sperre, ändert nichts).
-- Gibt Profil, online? zurück; nil, false, Fehler wenn nichts zu lesen ist.
function ProgressService.Peek(userId)
	local id = math.floor(tonumber(userId) or 0)
	local online = Players:GetPlayerByUserId(id)
	if online and profiles[online] then
		return profiles[online], true
	end
	if not store then
		return nil, false, "Kein DataStore (Studio ohne API-Zugriff?)"
	end
	local ok, data = pcall(store.Store.GetAsync, store.Store, "u" .. id)
	if not ok then
		return nil, false, tostring(data)
	end
	if data == nil then
		return nil, false, "Kein Spielstand"
	end
	return toProfile(data), false
end

-- Admin: Spielstand komplett zurücksetzen (wie ein neuer Spieler) und sofort speichern. Danach muss der Spieler neu
-- beitreten (AdminService kickt ihn), damit alle Dienste mit dem leeren Stand anfangen. Gibt true zurück, wenn ein
-- Profil da war.
function ProgressService.Reset(player)
	if not profiles[player] then
		return false
	end
	profiles[player] = defaultProfile()
	ProgressService.Sync(player)
	ProgressService.SaveNow(player)
	return true
end

-- Profil fertig geladen? Ohne DataStore oder wenn er in Studio nicht erreichbar ist: sobald das Profil da ist
-- (dann gilt der Stand nur für die Sitzung, gespeichert wird nur ein wirklich geladenes Profil)
function ProgressService.IsLoaded(player)
	return loaded[player] == true or (profiles[player] ~= nil and (store == nil or sessionOnly[player] == true))
end

-- Agent, mit dem der Spieler gerade spielt (sonst der gewählte)
function ProgressService.ActiveAgent(player)
	local character = player.Character
	return (character and character:GetAttribute("Agent")) or player:GetAttribute("Agent") or AgentConfig.Agents[1].Id
end

-- ---------- Münzen ----------

-- Sync nach Münzen: einzeln sofort (wie immer), aber höchstens alle 0,25 s; was in der Zwischenzeit kommt, wird gesammelt
-- und kurz danach einmal gesynct. Zombie-Kills geben Münzen am laufenden Band, und ein ganzes Sync pro Kill (Besitz,
-- Statistik, Aufträge ... als JSON) kostet in der Sturmnacht spürbar Serverzeit. Münzen selbst stehen immer sofort.
local SYNC_GAP = 0.25
local lastCoinSync = {}
local syncPending = {}
local function syncSoon(player, profile)
	player:SetAttribute("Coins", profile.Coins)
	local now = os.clock()
	if now - (lastCoinSync[player] or 0) >= SYNC_GAP and not syncPending[player] then
		lastCoinSync[player] = now
		ProgressService.Sync(player)
		return
	end
	if syncPending[player] then
		return
	end
	syncPending[player] = true
	task.delay(SYNC_GAP, function()
		syncPending[player] = nil
		lastCoinSync[player] = os.clock()
		if player.Parent then
			ProgressService.Sync(player)
		end
	end)
end

-- reason: wofür (erscheint in der Belohnungs-Übersicht am Matchende)
function ProgressService.AddCoins(player, amount, reason)
	local profile = profiles[player]
	if not profile or not finite(amount) or amount <= 0 then
		return
	end
	ledgerOf(player)
	-- Gamepass VIP: im Spiel verdiente Münzen doppelt (nicht bei Käufen, Codes, Admin, Verkäufen in der offenen Welt und
	-- Erlösen im Spielermarkt – das Geld kommt dort von anderen Spielern)
	if RobuxConfig.Has(player, "VIP") and reason and reason ~= "Robux" and reason ~= "Code" and reason ~= "Admin"
		and reason ~= "Verkauf" and reason ~= "Markt" and string.sub(reason, 1, 6) ~= "Kiste:" then -- Kisten-Erstattung nicht doppelt
		amount *= 2
	end
	profile.Coins += math.floor(amount)
	record(player, reason, 0, math.floor(amount))
	syncSoon(player, profile)
	Telemetry.Economy(player, "Source", "Coins", math.floor(amount), profile.Coins,
		reason == "Robux" and "IAP" or (reason == "Markt" or reason == "Verkauf") and "Shop" or "Gameplay", nil, reason)
end

-- Gibt true zurück, wenn genug Münzen da waren. reason/sku (optional) nur für die Analyse (Telemetry): wofür, welches Item
function ProgressService.SpendCoins(player, amount, reason, sku)
	local profile = profiles[player]
	if not profile or not finite(amount) or amount < 0 or profile.Coins < amount then
		return false
	end
	profile.Coins -= amount
	ProgressService.Sync(player)
	Telemetry.Economy(player, "Sink", "Coins", amount, profile.Coins, "Shop", sku, reason or "Unbekannt")
	return true
end

-- ---------- Waffen-Aufsätze (Lobby) ----------

local function attachmentData(profile)
	profile.Attachments = profile.Attachments or {}
	profile.Attachments.Owned = profile.Attachments.Owned or {}
	profile.Attachments.Equipped = profile.Attachments.Equipped or {}
	return profile.Attachments
end

-- Alte Spielstände (vor AttachmentConfig.ByWeapon): Aufsätze, die nicht auf ihre Waffe passen, werden abgelegt und
-- der Kaufpreis zurückgegeben (sie wären an dieser Waffe sonst wertlos). Gibt die erstatteten Münzen zurück.
local function refundUnfitAttachments(profile)
	local data = attachmentData(profile)
	local refund = 0
	for weaponName, owned in data.Owned do
		if type(owned) == "table" then
			for id in owned do
				local item = AttachmentConfig.Get(id)
				if item and not AttachmentConfig.Fits(weaponName, id) then
					owned[id] = nil
					refund += item.Price
				end
			end
		end
	end
	for weaponName, slots in data.Equipped do
		if type(slots) == "table" then
			for slot, id in slots do
				if not AttachmentConfig.Fits(weaponName, id) then
					slots[slot] = nil
				end
			end
		end
	end
	profile.Coins = (profile.Coins or 0) + refund
	return refund
end
ProgressService.RefundUnfitAttachments = refundUnfitAttachments

-- Aufsatz für eine Waffe kaufen (gilt für alle Agenten mit dieser Waffe) und gleich ausrüsten
function ProgressService.BuyAttachment(player, weaponName, id)
	local profile = profiles[player]
	local item = AttachmentConfig.Get(id)
	if not profile or not item or not WeaponConfig.Get(weaponName) then
		return "Unbekannter Aufsatz.", false
	end
	if not AttachmentConfig.Fits(weaponName, id) then
		return "Passt nicht auf diese Waffe.", false
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
	if not AttachmentConfig.Fits(weaponName, id) then
		return "Passt nicht auf diese Waffe.", false
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

-- Besitz: profile.Owned[Id] = Stückzahl (alte Spielstände: true = 1). Handelbare Skins (RapConfig) kann man
-- mehrfach haben, alle anderen einmal.
function ProgressService.ItemCount(player, itemId)
	local profile = profiles[player]
	return profile and RapConfig.Count(profile.Owned, itemId) or 0
end

function ProgressService.Owns(player, itemId)
	local item = Cosmetics.Get(itemId)
	if item and item.Creator then
		return Cosmetics.CreatorUnlocked(player)
	end
	return ProgressService.ItemCount(player, itemId) > 0
end

-- n Stück dazugeben (Standard 1)
function ProgressService.GiveItem(player, itemId, n)
	local profile = profiles[player]
	if profile then
		profile.Owned[itemId] = RapConfig.Count(profile.Owned, itemId) + (n or 1)
		ProgressService.Sync(player)
	end
end

-- n Stück wegnehmen (Standard 1); geht das letzte, wird der Skin überall abgelegt. Gibt true zurück, wenn genug da
-- waren (sonst ändert sich nichts).
function ProgressService.TakeItem(player, itemId, n)
	local profile = profiles[player]
	n = n or 1
	local count = profile and RapConfig.Count(profile.Owned, itemId) or 0
	if not profile or n < 1 or count < n then
		return false
	end
	profile.Owned[itemId] = count - n > 0 and count - n or nil
	if count - n <= 0 then
		for slot, equipped in profile.Equipped do
			if equipped == itemId then
				profile.Equipped[slot] = nil
			end
		end
	end
	ProgressService.Sync(player)
	return true
end

-- ---------- RAP (zweite Währung, RapConfig) ----------

function ProgressService.GetRap(player)
	local profile = profiles[player]
	local rap = profile and tonumber(profile.Rap)
	return finite(rap) and math.floor(rap) or 0
end

function ProgressService.AddRap(player, amount)
	local profile = profiles[player]
	amount = math.floor(tonumber(amount) or 0)
	if not profile or not finite(amount) or amount <= 0 then
		return
	end
	profile.Rap = ProgressService.GetRap(player) + amount
	ProgressService.Sync(player)
	Telemetry.Economy(player, "Source", "RAP", amount, profile.Rap, "Gameplay")
end

-- Gibt true zurück, wenn genug RAP da war
function ProgressService.SpendRap(player, amount)
	local profile = profiles[player]
	amount = math.floor(tonumber(amount) or 0)
	if not profile or not finite(amount) or amount < 0 or ProgressService.GetRap(player) < amount then
		return false
	end
	profile.Rap = ProgressService.GetRap(player) - amount
	ProgressService.Sync(player)
	Telemetry.Economy(player, "Sink", "RAP", amount, profile.Rap, "Shop")
	return true
end

-- slot = "W:<Waffe>", itemId = nil zum Ablegen
function ProgressService.SetEquipped(player, slot, itemId)
	local profile = profiles[player]
	if profile then
		profile.Equipped[slot] = itemId
		ProgressService.Sync(player)
	end
end

-- ---------- XP ----------

-- XP für einen Agenten vergeben (+ Münzen, außer bei Admin-XP). reason wird angezeigt.
-- quiet = keine "+XP"-Zeile im HUD (z.B. Medaillen zeigen ihre XP selbst), noCoins = keine Münzen dazu (Zombies zahlen
-- ihre Münzen selbst). Gibt die vergebenen XP zurück.
function ProgressService.AddXP(player, agentId, amount, reason, quiet, noCoins)
	local profile = profiles[player]
	if not profile or not AgentConfig.Get(agentId) then
		return 0
	end
	amount = math.floor(amount * GameSettings.Get("XPMultiplier"))
	-- Doppel-XP (Login-Kalender, Glücksrad, Gamepass)
	if reason ~= "Admin" and ((profile.XPBoostUntil or 0) > os.time() or RobuxConfig.Has(player, "DoubleXP")) then
		amount *= 2
		reason = tostring(reason) .. " · Doppel-XP"
	end
	if amount <= 0 then
		return 0
	end
	ledgerOf(player) -- Stand vor diesen XP merken (Level-Fortschritt in der Übersicht)
	local before = profile.XP[agentId] or 0
	local maxXP = AgentConfig.XPPerLevel * (AgentConfig.MaxLevel - 1)
	local after = math.min(before + amount, maxXP)
	profile.XP[agentId] = after
	-- Spielerlevel: alle XP zählen (auch wenn der Agent schon Max-Level ist)
	profile.AccountXP = math.min((profile.AccountXP or 0) + amount, LevelConfig.MaxXP)

	local coins = (reason ~= "Admin" and not noCoins) and math.floor(amount * Cosmetics.CoinsPerXP) or 0
	if RobuxConfig.Has(player, "VIP") then
		coins *= 2 -- Gamepass VIP: doppelte Münzen
	end
	profile.Coins += coins
	record(player, reason, amount, coins)
	ProgressService.Sync(player)
	if coins > 0 then
		Telemetry.Economy(player, "Source", "Coins", coins, profile.Coins, "Gameplay", nil, "XP")
	end

	local levelUp = AgentConfig.LevelFromXP(after) > AgentConfig.LevelFromXP(before)
	if levelUp then
		Telemetry.Progression(player, "Agent", "Complete", AgentConfig.LevelFromXP(after), tostring(agentId))
	end
	Remotes.XPGain:FireClient(player, amount, reason, agentId, levelUp, coins, quiet == true) -- auch bei Agent auf Max-Level
	-- Alle XP zählen auch für den Battle Pass (auch wenn der Agent schon Max-Level ist)
	if reason ~= "Admin" then
		ProgressService.AddPassXP(player, amount)
	end
	return amount
end

-- Nur Spielerlevel-XP (ohne Agent, Münzen und Battle Pass), z.B. die EP der offenen Welt (ExtLevelService).
-- Mit XP-Faktor (GameSettings) und Doppel-XP (Login-Kalender, Glücksrad, Gamepass) wie AddXP.
-- Gibt die vergebenen XP zurück und ob sie verdoppelt wurden.
function ProgressService.AddAccountXP(player, amount)
	local profile = profiles[player]
	amount = math.floor(tonumber(amount) or 0)
	if not profile or amount <= 0 then
		return 0, false
	end
	amount = math.floor(amount * GameSettings.Get("XPMultiplier"))
	local doubled = (profile.XPBoostUntil or 0) > os.time() or RobuxConfig.Has(player, "DoubleXP")
	if doubled then
		amount *= 2
	end
	if amount <= 0 then
		return 0, false
	end
	profile.AccountXP = math.min((profile.AccountXP or 0) + amount, LevelConfig.MaxXP)
	player:SetAttribute("AccountXP", profile.AccountXP) -- (reicht für Anzeige und Belohnungen, ohne ganzen Sync)
	return amount, doubled
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
	Remotes.Notify:FireClient(player, "Progress", { Caption = "Prestige erreicht", Title = "Prestige " .. profile.Prestige,
		Sub = "+" .. coins .. " Münzen", Badge = tostring(profile.Prestige), Style = "Prestige",
		Key = "Prestige" .. profile.Prestige, Primary = true })
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
	Telemetry.BindProfile(function(player)
		local profile = profiles[player]
		return profile and profile.OnboardingStep or nil
	end, function(player, step)
		local profile = profiles[player]
		if profile then
			profile.OnboardingStep = step
		end
	end)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("PlayerData_v1")
	end)
	if ok then
		store = SessionStore.new(result, {
			-- Kennung dieses Servers für die Sperre (in Studio ist JobId leer)
			SessionId = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false)),
			Retries = RunService:IsStudio() and 1 or nil, -- ohne API-Zugriff in Studio hilft Warten nicht
		})
	else
		warn("DataStore nicht verfügbar, Fortschritt wird nicht gespeichert: " .. tostring(result))
	end

	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastCoinSync[player] = nil
		if not shuttingDown then
			for _, callback in leaving do
				local ok, err = pcall(callback, player)
				if not ok then
					warn("Beim Verlassen: " .. tostring(err))
				end
			end
		end
		save(player, true)
		profiles[player] = nil
		loaded[player] = nil
		sessionOnly[player] = nil
		ledgers[player] = nil
	end)
	-- Herunterfahren: alle gleichzeitig speichern (nacheinander reicht die Zeit bei vielen Spielern nicht)
	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + SHUTDOWN_WAIT
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
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

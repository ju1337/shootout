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

local ProgressService = {}

local AUTOSAVE_INTERVAL = 120 -- Sekunden

local store = nil
local profiles = {} -- [Player] = Profil
local loaded = {}   -- [Player] = true, wenn erfolgreich geladen (nur dann speichern)

local function defaultProfile()
	return { XP = {}, Coins = 0, Owned = {}, Equipped = {}, LastDaily = 0, Codes = {}, Quests = {}, RankPoints = 0, PassXP = 0, Agents = {} }
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
	player:SetAttribute("RankPoints", profile.RankPoints or 0)
	player:SetAttribute("PassXP", profile.PassXP or 0)
	player:SetAttribute("UnlockedAgents", HttpService:JSONEncode(profile.Agents or {}))
	ensureQuests(player, profile)
	player:SetAttribute("Quests", HttpService:JSONEncode(profile.Quests))
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

-- Rangpunkte ändern (Ranked), nie unter 0
function ProgressService.AddRankPoints(player, amount)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.RankPoints = math.max(0, (profile.RankPoints or 0) + amount)
	ProgressService.Sync(player)
end

-- Spielereignis für Aufträge zählen (event wie in QuestConfig, z.B. "Kill")
function ProgressService.QuestEvent(player, event, amount)
	local profile = profiles[player]
	if not profile then
		return
	end
	ensureQuests(player, profile)
	local changed = false
	for _, id in profile.Quests.Ids do
		local quest = QuestConfig.Get(id)
		if quest and quest.Event == event and not profile.Quests.Claimed[id] then
			local before = profile.Quests.Progress[id] or 0
			if before < quest.Goal then
				profile.Quests.Progress[id] = math.min(quest.Goal, before + (amount or 1))
				changed = true
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
	if not profile or not quest or not table.find(profile.Quests.Ids or {}, id) then
		return "Unbekannter Auftrag.", false
	end
	if profile.Quests.Claimed[id] then
		return "Schon abgeholt.", false
	end
	if (profile.Quests.Progress[id] or 0) < quest.Goal then
		return "Auftrag noch nicht geschafft.", false
	end
	profile.Quests.Claimed[id] = true
	ProgressService.AddCoins(player, quest.Reward) -- synct auch die Aufträge
	ProgressService.AddPassXP(player, PassConfig.QuestXP)
	return "+" .. quest.Reward .. " Münzen für \"" .. quest.Text .. "\"!", true
end

function ProgressService.Get(player)
	return profiles[player]
end

local function key(player)
	return "u" .. player.UserId
end

local function load(player)
	profiles[player] = defaultProfile()
	ProgressService.Sync(player)
	if not store then
		return
	end
	local ok, result = pcall(store.GetAsync, store, key(player))
	if ok then
		profiles[player] = toProfile(result)
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

function ProgressService.AddCoins(player, amount)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	profile.Coins += math.floor(amount)
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
	if amount <= 0 then
		return
	end
	local before = profile.XP[agentId] or 0
	local maxXP = AgentConfig.XPPerLevel * (AgentConfig.MaxLevel - 1)
	local after = math.min(before + amount, maxXP)
	profile.XP[agentId] = after

	local coins = reason ~= "Admin" and math.floor(amount * Cosmetics.CoinsPerXP) or 0
	profile.Coins += coins
	ProgressService.Sync(player)

	local levelUp = AgentConfig.LevelFromXP(after) > AgentConfig.LevelFromXP(before)
	Remotes.XPGain:FireClient(player, after - before, reason, agentId, levelUp, coins)
	-- Alle XP zählen auch für den Battle Pass (auch wenn der Agent schon Max-Level ist)
	if reason ~= "Admin" then
		ProgressService.AddPassXP(player, amount)
	end
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
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			save(player)
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

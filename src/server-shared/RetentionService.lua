-- RetentionService (ModuleScript, nur Server)
-- Gründe zum Wiederkommen (Werte in RetentionConfig):
--   Rückkehr-Bonus   ProgressService merkt beim Laden, ob jemand Comeback.AwayDays Tage weg war (Profil ComebackPending).
--                    Beim Betreten der offenen Welt (Modes/Extinction ruft ClaimComeback): Münzen, Items ins Lager (Rest in
--                    die Tasche), Doppel-XP und ein Banner ohne Sound.
--   Freunde-Bonus    Sobald zwei Roblox-Freunde im selben Squad sind (Spieler-Attribut SquadId, PartyService), bekommen beide
--                    das Attribut "FriendBonus"; ProgressService rechnet den Bonus auf XP und Münzen.
--   Dungeon-Woche    DungeonService meldet nach dem Portal die geschafften Wellen (DungeonRecord): bester Wert der Woche im
--                    Profil (DungeonWeek = { Week, Best }), die Tafel trägt LeaderboardService ein. Nach dem Ende einer
--                    Woche bekommen die besten Spieler beim nächsten Besuch Münzen und den Titel (Profil DungeonWeekPaid).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local QuestConfig = require(Shared.QuestConfig)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local RetentionConfig = require(Shared.RetentionConfig)
local ProgressService = require(script.Parent.ProgressService)
local InventoryService = require(script.Parent.InventoryService)

local RetentionService = {}

local CHECK_EVERY = 600 -- Sekunden: Wochenwechsel für Spieler prüfen, die gerade online sind
local SETTLE = 900      -- Sekunden nach Wochenbeginn, bevor die Preise der letzten Woche verteilt werden

-- ---------- Rückkehr-Bonus ----------

-- Beim Betreten der offenen Welt: Bonus geben, falls fällig. Gibt true zurück, wenn es ihn gab.
function RetentionService.ClaimComeback(player)
	local profile = ProgressService.Get(player)
	if not profile or not profile.ComebackPending then
		return false
	end
	profile.ComebackPending = nil -- vor dem Verteilen: kein zweites Mal bei einem Fehler
	local C = RetentionConfig.Comeback
	for _, item in C.Items do
		local id, count = item[1], item[2]
		if ExtinctionConfig.Get(id) then
			local put = InventoryService.GiveStash(player, id, count)
			if put < count then
				InventoryService.Give(player, id, count - put)
			end
		end
	end
	ProgressService.AddCoins(player, C.Coins, "Rückkehr-Bonus")
	if C.BoostMinutes > 0 then
		ProgressService.AddXPBoost(player, C.BoostMinutes)
	end
	-- etwas später als der Spawn (kein Banner mitten im Laden), ohne Sound
	task.delay(4, function()
		if player.Parent then
			Remotes.Notify:FireClient(player, "Banner", { Caption = "Rückkehr-Bonus", Title = "WILLKOMMEN ZURÜCK",
				Sub = string.format("+%d Münzen · %d Min. Doppel-XP · Dungeon-Schlüssel im Lager", C.Coins, C.BoostMinutes),
				Style = "Info" })
		end
	end)
	return true
end

-- ---------- Freunde-Bonus ----------

local friendCache = {} -- ["kleinere:größere UserId"] = true/false

local function friends(a, b)
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	local key = low .. ":" .. high
	if friendCache[key] == nil then
		local ok, result = pcall(a.IsFriendsWith, a, b.UserId)
		if not ok then
			return false -- nicht merken: beim nächsten Squad-Wechsel neu fragen
		end
		friendCache[key] = result == true
	end
	return friendCache[key]
end

-- Bonus für alle im Squad neu bestimmen (squadId nil: nur player selbst ohne Squad)
local function updateSquad(squadId, player)
	local members = {}
	if squadId ~= nil then
		for _, other in Players:GetPlayers() do
			if other:GetAttribute("SquadId") == squadId then
				table.insert(members, other)
			end
		end
	end
	if player and not table.find(members, player) and player.Parent then
		player:SetAttribute("FriendBonus", nil)
	end
	for _, member in members do
		local bonus = false
		for _, other in members do
			if other ~= member and friends(member, other) then
				bonus = true
				break
			end
		end
		if member.Parent and member:GetAttribute("SquadId") == squadId then
			member:SetAttribute("FriendBonus", bonus or nil)
		end
	end
end

local function watchSquad(player)
	local current = player:GetAttribute("SquadId")
	if current ~= nil then
		task.spawn(updateSquad, current, player)
	end
	player:GetAttributeChangedSignal("SquadId"):Connect(function()
		local old = current
		current = player:GetAttribute("SquadId")
		if old ~= nil and old ~= current then
			task.spawn(updateSquad, old, nil) -- der alte Squad hat einen weniger
		end
		task.spawn(updateSquad, current, player)
	end)
end

-- ---------- Dungeon-Wochenrekord ----------

-- Nach dem Portal: geschaffte Wellen eintragen, falls besser als bisher diese Woche. Gibt den Wochenbestwert zurück.
function RetentionService.DungeonRecord(player, waves)
	local profile = ProgressService.Get(player)
	waves = math.floor(tonumber(waves) or 0)
	if not profile or waves <= 0 then
		return 0
	end
	local week = QuestConfig.Week()
	local data = type(profile.DungeonWeek) == "table" and profile.DungeonWeek or {}
	if data.Week ~= week then
		data = { Week = week, Best = 0 }
	end
	if waves > (tonumber(data.Best) or 0) then
		data.Best = waves
		profile.DungeonWeek = data
		player:SetAttribute("DungeonWeekBest", waves)
		local ok, LeaderboardService = pcall(require, script.Parent.LeaderboardService)
		if ok and LeaderboardService.Submit then
			task.spawn(pcall, LeaderboardService.Submit, player)
		end
	end
	return data.Best
end

local lastWeekTop = {} -- [Woche] = { [UserId] = Platz } (pro Server einmal gelesen)

local function topOf(week)
	if lastWeekTop[week] then
		return lastWeekTop[week]
	end
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, RetentionConfig.DungeonStoreName(week))
	if not ok then
		return nil
	end
	local fetched, pages = pcall(store.GetSortedAsync, store, false, RetentionConfig.DungeonWeek.Top)
	if not fetched then
		return nil
	end
	local places = {}
	for place, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId and (tonumber(entry.value) or 0) > 0 then
			places[userId] = place
		end
	end
	lastWeekTop[week] = places
	return places
end

-- Preis der letzten Woche abholen (einmal pro Woche). Gibt den Platz zurück, wenn es einen Preis gab.
function RetentionService.CheckDungeonWeek(player)
	local profile = ProgressService.Get(player)
	if not profile or not ProgressService.IsLoaded(player) then
		return nil
	end
	local now = os.time()
	local last = QuestConfig.Week(now) - 1
	if (tonumber(profile.DungeonWeekPaid) or -1) >= last then
		return nil
	end
	-- die ersten Minuten der neuen Woche abwarten: andere Server tragen ihre letzten Werte noch ein
	if 7 * 86400 - QuestConfig.WeekLeft(now) < SETTLE then
		return nil
	end
	local places = topOf(last)
	if not places then
		return nil -- DataStore gerade nicht erreichbar: beim nächsten Mal
	end
	profile.DungeonWeekPaid = last
	local place = places[player.UserId]
	local coins = place and RetentionConfig.DungeonReward(place)
	if not coins then
		return nil
	end
	ProgressService.AddCoins(player, coins, "Dungeon-Wochenrekord")
	ProgressService.AddStat(player, RetentionConfig.DungeonWeek.Stat, 1)
	Remotes.Notify:FireClient(player, "Banner", { Caption = "Dungeon-Wochenrekord", Title = "PLATZ " .. place .. " LETZTE WOCHE",
		Sub = "+" .. coins .. " Münzen · Titel Katakomben-Champion", Style = "Good" })
	return place
end

function RetentionService.Init()
	for _, player in Players:GetPlayers() do
		watchSquad(player)
	end
	Players.PlayerAdded:Connect(watchSquad)
	Players.PlayerRemoving:Connect(function(player)
		local squadId = player:GetAttribute("SquadId")
		if squadId ~= nil then
			task.defer(updateSquad, squadId, nil)
		end
	end)
	table.insert(ProgressService.OnLoaded, function(player)
		local profile = ProgressService.Get(player)
		local data = profile and profile.DungeonWeek
		if type(data) == "table" and data.Week == QuestConfig.Week() then
			player:SetAttribute("DungeonWeekBest", data.Best)
		end
		RetentionService.CheckDungeonWeek(player)
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			for _, player in Players:GetPlayers() do
				local profile = ProgressService.Get(player)
				local data = profile and profile.DungeonWeek
				if not (type(data) == "table" and data.Week == QuestConfig.Week()) then
					player:SetAttribute("DungeonWeekBest", nil)
				end
				task.spawn(RetentionService.CheckDungeonWeek, player)
			end
		end
	end)
end

return RetentionService

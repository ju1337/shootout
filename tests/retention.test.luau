-- Gründe zum Wiederkommen (Julio 2026-10-13): Battle Pass mit Saisons (neue Saison = Pass ab Stufe 0, eigene Skins),
-- Rückkehr-Bonus nach 7 Tagen Pause (einmal, beim Betreten der offenen Welt), Freunde-Bonus im Squad (nur mit einem
-- Roblox-Freund, nur Münzen aus dem Spiel), Dungeon-Wochenrekord (Bestwert der Woche, Tafel, Preis in der Woche danach)
-- und Clan-Punkte (Stufe, Wochenziel mit Münzen nur bei eigenem Beitrag, Clan-Bestenliste).
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
local store = SIM.DataStore("PlayerData_v2")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PassConfig = require("PassConfig")
local Cosmetics = require("Cosmetics")
local RapConfig = require("RapConfig")
local QuestConfig = require("QuestConfig")
local TitleConfig = require("TitleConfig")
local RetentionConfig = require("RetentionConfig")
local ProgressService = require("ProgressService")
local InventoryService = require("InventoryService")
local RetentionService = require("RetentionService")
local LeaderboardService = require("LeaderboardService")
local ClanService = require("ClanService")
ProgressService.Init()
RetentionService.Init()
LeaderboardService.Init()
ClanService.Init()

-- Items der offenen Welt mitschreiben (das Inventar braucht sonst die ganze Karte)
local given = {}
InventoryService.GiveStash = function(player, id, count)
	table.insert(given, { Player = player, Id = id, Count = count })
	return count
end
InventoryService.Give = function()
	return 0
end

local function banners(player, caption)
	local n = 0
	for _, entry in SIM.RemoteLog do
		if entry.Remote == "Notify" and entry.Player == player and entry.Args[1] == "Banner"
			and entry.Args[2].Caption == caption then
			n += 1
		end
	end
	return n
end

-- Tafel der letzten Woche (für den Preis weiter unten): Dave war Zweiter, Eve nicht in den Top 10
local lastStore = SIM.DataStore(RetentionConfig.DungeonStoreName(QuestConfig.Week() - 1))
for i = 1, 11 do
	lastStore.Data[tostring(900 + i)] = 100 - i
end
lastStore.Data["104"] = 98.5 -- Platz 2
lastStore.Data["105"] = 1 -- Platz 13

-- ---------- Battle Pass mit Saisons ----------
local S1 = PassConfig.SeasonStart
check(PassConfig.CurrentSeason(S1 - 100) == 1 and PassConfig.CurrentSeason(S1) == 1, "vor und zu Beginn: Saison 1")
check(PassConfig.CurrentSeason(S1 + PassConfig.SeasonLength) == 2, "nach 6 Wochen: Saison 2")
check(PassConfig.SeasonLeft(S1 + PassConfig.SeasonLength - 3600) == 3600, "Restzeit der Saison")
check(PassConfig.SeasonName(2) == "SAISON 2 · ASCHEREGEN", "Name Saison 2: " .. PassConfig.SeasonName(2))
check(PassConfig.SeasonName(4) == "SAISON 4 · ERSTER EINSATZ", "nach der letzten Saison beginnt die Liste von vorn")
for season = 1, #PassConfig.Seasons do
	local tiers = PassConfig.TiersFor(season)
	check(#tiers == PassConfig.TierCount, "Saison " .. season .. ": 30 Stufen")
	for tier = 10, 30, 10 do
		local item = Cosmetics.Get(tiers[tier].Item)
		check(item ~= nil and item.Pass == true and item.Type == "Weapon" and not Cosmetics.ForSale(item),
			"Saison " .. season .. " Stufe " .. tier .. ": exklusiver Pass-Skin")
		check(item ~= nil and RapConfig.Tradeable(item.Id), "Pass-Skin handelbar mit RAP-Wert: " .. tostring(tiers[tier].Item))
	end
end
check(PassConfig.TiersFor(2)[10].Item == "W_Asche" and PassConfig.TiersFor(3)[30].Item == "W_Polarlicht", "Skins je Saison")

local legacy = { PassXP = 4200 }
check(ProgressService.CheckPassSeason(legacy, S1 + 10) == false and legacy.PassXP == 4200 and legacy.PassSeason == 1,
	"alter Spielstand ohne Saison: Fortschritt bleibt in der laufenden Saison")
check(ProgressService.CheckPassSeason(legacy, S1 + 20) == false and legacy.PassXP == 4200, "gleiche Saison: nichts passiert")
check(ProgressService.CheckPassSeason(legacy, S1 + PassConfig.SeasonLength + 5) == true and legacy.PassXP == 0
	and legacy.PassSeason == 2, "neue Saison: Pass fängt bei Stufe 0 an")

-- Spieler in Saison 2 (gespeichert): Stufe 10 gibt den Skin der Saison 2
local now = os.time()
local season = PassConfig.CurrentSeason(now)
store.Data.u101 = { XP = {}, Coins = 0, Owned = {}, Equipped = {}, PassXP = 9000, PassSeason = season, LastSeen = now - 2 * 86400 }
local alice = SIM.Join("Alice", 101)
step(2)
check(ProgressService.IsLoaded(alice), "Alice geladen")
check(alice:GetAttribute("PassSeason") == season, "Attribut PassSeason")
local tierTen = PassConfig.TiersFor(season)[10].Item
ProgressService.AddPassXP(alice, 1000)
check(ProgressService.Owns(alice, tierTen), "Stufe 10 der Saison gibt " .. tierTen)

-- ---------- Rückkehr-Bonus ----------
local aliceProfile = ProgressService.Get(alice)
check(not aliceProfile.ComebackPending, "2 Tage weg: kein Rückkehr-Bonus")
check(math.abs((aliceProfile.LastSeen or 0) - os.time()) <= 2, "LastSeen beim Laden aktualisiert")
check(RetentionService.ClaimComeback(alice) == false, "ohne Anspruch nichts")

store.Data.u102 = { XP = {}, Coins = 100, Owned = {}, Equipped = {}, LastSeen = now - 8 * 86400 }
local bob = SIM.Join("Bob", 102)
step(2)
local bobProfile = ProgressService.Get(bob)
check(bobProfile.ComebackPending == true, "8 Tage weg: Rückkehr-Bonus vorgemerkt")
check(RetentionService.ClaimComeback(bob) == true, "Bonus beim Betreten der offenen Welt")
check(bobProfile.Coins == 100 + RetentionConfig.Comeback.Coins, "Münzen des Bonus: " .. bobProfile.Coins)
check((bobProfile.XPBoostUntil or 0) >= os.time() + RetentionConfig.Comeback.BoostMinutes * 60 - 5, "Doppel-XP läuft")
local keys = 0
for _, entry in given do
	if entry.Player == bob and entry.Id == "DungeonKey" then
		keys += entry.Count
	end
end
check(keys == 1, "Dungeon-Schlüssel ins Lager")
check(RetentionService.ClaimComeback(bob) == false and bobProfile.Coins == 100 + RetentionConfig.Comeback.Coins, "nur einmal")
step(5)
check(banners(bob, "Rückkehr-Bonus") == 1, "ein Banner WILLKOMMEN ZURÜCK")

local carl = SIM.Join("Carl", 103) -- ganz neu: kein Bonus
step(2)
check(not ProgressService.Get(carl).ComebackPending, "neuer Spieler: kein Rückkehr-Bonus")

-- ---------- Freunde-Bonus ----------
SIM.Friends["101:102"] = true -- Alice und Bob sind Freunde, Carl kennt keinen
alice:SetAttribute("SquadId", 7)
carl:SetAttribute("SquadId", 7)
step(1)
check(alice:GetAttribute("FriendBonus") == nil and carl:GetAttribute("FriendBonus") == nil, "Squad ohne Freunde: kein Bonus")
bob:SetAttribute("SquadId", 7)
step(1)
check(alice:GetAttribute("FriendBonus") == true and bob:GetAttribute("FriendBonus") == true, "Freunde im Squad: Bonus")
check(carl:GetAttribute("FriendBonus") == nil, "wer keinen Freund im Squad hat, bekommt keinen")
local before = ProgressService.Get(alice).Coins
ProgressService.AddCoins(alice, 100, "Zombie")
check(ProgressService.Get(alice).Coins - before == 110, "Münzen aus dem Spiel +10 %: " .. (ProgressService.Get(alice).Coins - before))
before = ProgressService.Get(alice).Coins
ProgressService.AddCoins(alice, 100, "Verkauf")
check(ProgressService.Get(alice).Coins - before == 100, "Verkauf ohne Bonus")
before = ProgressService.Get(alice).Coins
ProgressService.AddCoins(alice, 100, "Robux")
check(ProgressService.Get(alice).Coins - before == 100, "Robux ohne Bonus")
check(math.floor(ProgressService.FriendBonus(alice, 100)) == 110 and ProgressService.FriendBonus(carl, 100) == 100, "XP +10 % nur mit Freund")
bob:SetAttribute("SquadId", nil)
step(1)
check(alice:GetAttribute("FriendBonus") == nil and bob:GetAttribute("FriendBonus") == nil, "Freund verlässt den Squad: Bonus weg")
alice:SetAttribute("SquadId", nil)
carl:SetAttribute("SquadId", nil)

-- ---------- Dungeon-Wochenrekord ----------
check(RetentionService.DungeonRecord(alice, 4) == 4, "erster Lauf der Woche: Welle 4")
check(RetentionService.DungeonRecord(alice, 2) == 4, "schlechterer Lauf ändert nichts")
check(RetentionService.DungeonRecord(alice, 9) == 9 and alice:GetAttribute("DungeonWeekBest") == 9, "Bestwert 9")
RetentionService.DungeonRecord(bob, 6)
step(1)
local week = QuestConfig.Week()
local weekStore = SIM.DataStore(RetentionConfig.DungeonStoreName(week))
check(weekStore.Data["101"] == 9 and weekStore.Data["102"] == 6, "Tafel der Woche eingetragen")
check(weekStore.Data["103"] == nil, "wer nichts geschafft hat, steht nicht auf der Tafel")
step(65)
local board = HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Leaderboard_DungeonWeek") or "[]")
check(#board == 2 and board[1].UserId == 101 and board[1].Value == 9, "Tafel DUNGEON-WOCHE: Alice vorn")

store.Data.u104 = { XP = {}, Coins = 0, Owned = {}, Equipped = {} }
store.Data.u105 = { XP = {}, Coins = 0, Owned = {}, Equipped = {} }
local dave = SIM.Join("Dave", 104)
local eve = SIM.Join("Eve", 105)
step(3)
local daveProfile = ProgressService.Get(dave)
check(daveProfile.Coins == RetentionConfig.DungeonReward(2), "Platz 2 letzte Woche: Münzen " .. daveProfile.Coins)
check(daveProfile.Stats.DungeonTop == 1 and TitleConfig.Unlocked(TitleConfig.Get("KatakombenChampion"),
	{ Stats = daveProfile.Stats }), "Titel Katakomben-Champion frei")
check(daveProfile.DungeonWeekPaid == week - 1, "Woche als bezahlt gemerkt")
check(RetentionService.CheckDungeonWeek(dave) == nil and daveProfile.Coins == RetentionConfig.DungeonReward(2), "nur einmal")
check(ProgressService.Get(eve).Coins == 0 and ProgressService.Get(eve).DungeonWeekPaid == week - 1, "Platz 13: kein Preis")
check(RetentionConfig.DungeonReward(1) > RetentionConfig.DungeonReward(3) and RetentionConfig.DungeonReward(11) == nil,
	"Preise nach Platz")

-- ---------- Clan-Punkte ----------
ProgressService.Get(alice).Coins = 10000
local message, ok = ClanService.Create(alice, "Phoenix Squad", "PHX")
check(ok, "Clan gegründet: " .. tostring(message))
message, ok = ClanService.Join(bob, "PHX")
check(ok, "Bob im Clan: " .. tostring(message))
step(1)
ProgressService.AddStat(alice, "Zombies", 2400)
ProgressService.AddStat(alice, "ExtMissions", 4) -- 4 Aufträge = 100 Punkte
ProgressService.AddStat(bob, "Zombies", 50)     -- zu wenig für die Münzen des Wochenziels
ProgressService.AddStat(carl, "Zombies", 500)    -- nicht im Clan
local aliceCoins, bobCoins = ProgressService.Get(alice).Coins, ProgressService.Get(bob).Coins
ClanService.Flush()
step(1)
local clan = SIM.DataStore("Clans_v2").Data.PHX
check(clan.Points == 2550 and clan.Week.Points == 2550 and clan.Week.Id == week, "Clan-Punkte gespeichert: " .. tostring(clan.Points))
check(clan.Week.By["101"] == 2500 and clan.Week.By["102"] == 50 and clan.Week.By["103"] == nil, "Beitrag je Mitglied")
local data = HttpService:JSONDecode(alice:GetAttribute("ClanData"))
check(data.Points == 2550 and data.WeekPoints == 2550, "ClanData mit Punkten für die Seite")
check(ProgressService.Get(alice).Coins - aliceCoins == RetentionConfig.Clan.Stages[1].Coins, "Stufe 1 des Wochenziels: Münzen für Alice")
check(ProgressService.Get(bob).Coins == bobCoins, "Bob hat zu wenig beigetragen: keine Münzen")
check(banners(alice, "Clan-Wochenziel") == 1, "Banner Wochenziel")
ClanService.Flush()
check(ProgressService.Get(alice).Coins - aliceCoins == RetentionConfig.Clan.Stages[1].Coins, "Stufe nur einmal pro Woche")
ProgressService.AddStat(bob, "Zombies", 60)
ClanService.Flush()
step(1)
check(ProgressService.Get(bob).Coins - bobCoins == RetentionConfig.Clan.Stages[1].Coins, "Bob mit 110 Punkten: jetzt auch Münzen")
check(RetentionConfig.ClanLevel(0) == 1 and RetentionConfig.ClanLevel(RetentionConfig.Clan.LevelPoints) == 2, "Clan-Stufen")
check(RetentionConfig.ClanStage(7500) == 2 and RetentionConfig.ClanStage(100) == 0, "Stufen des Wochenziels")
local clans = ClanService.RefreshBoard()
check(#clans == 1 and clans[1].Tag == "PHX" and clans[1].Value == 2610, "Clan-Bestenliste: " .. HttpService:JSONEncode(clans))

-- Neue Woche: Wochenpunkte fangen bei 0 an, die alte Woche bleibt als LastWeek
local data2 = SIM.DataStore("Clans_v2").Data.PHX
data2.Week.Id = week - 1
ProgressService.AddStat(alice, "Zombies", 10)
ClanService.Flush()
clan = SIM.DataStore("Clans_v2").Data.PHX
check(clan.Week.Id == week and clan.Week.Points == 10 and clan.LastWeek.Points == 2610 and clan.Points == 2620,
	"Wochenwechsel: neue Woche bei 0, alte als LastWeek")

if failures > 0 then
	error(failures .. " Fehler")
end
print("retention ok")

-- VIP & BOOSTER-Aufträge: je Tag und Woche 2 Arcade + 2 Extinction, nur Berechtigte (Gamepass VIP, Team-Rang ab
-- BOOSTER) zählen und holen ab; Wochen-Aufträge geben einmal den gebundenen Skin Unterstützer.
-- Arcade aus (Modes.ArcadeEnabled = false, Standard): keine neuen Arcade-Aufträge (VIP & BOOSTER nur Extinction,
-- tägliche/wöchentliche Arcade-Sätze leer, kein Wochen-Bonus ohne Wochen-Aufträge)
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
local store = SIM.DataStore("PlayerData_v1")
local Modes = require("Modes")
Modes.ArcadeEnabled = true -- erst mit Arcade (Arcade-Aufträge), unten ohne
local QuestConfig = require("QuestConfig")
local Cosmetics = require("Cosmetics")
local RapConfig = require("RapConfig")
local ProgressService = require("ProgressService")
ProgressService.Init()

check(Cosmetics.Get("W_Unterstuetzer") ~= nil and not RapConfig.Tradeable("W_Unterstuetzer")
	and not Cosmetics.ForSale(Cosmetics.Get("W_Unterstuetzer")), "Skin Unterstützer: gebunden, nicht im Shop")
for _, quest in QuestConfig.SpecialWeeklyPool do
	check(quest.Item == "W_Unterstuetzer", quest.Id .. ": gibt den Skin")
end

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local booster, normal = SIM.Join("Booster"), SIM.Join("Normal")
booster:SetAttribute("StaffRank", "Booster")
step(2)

local function count(player, key, mode)
	local data = QuestConfig.Read(player, key) or {}
	local n = 0
	for _, id in data.Ids or {} do
		if QuestConfig.Get(id).Mode == mode then
			n += 1
		end
	end
	return n, data
end
for _, key in { "SpecialQuests", "SpecialWeekly" } do
	check(count(booster, key, "Arcade") == 2 and count(booster, key, "Extinction") == 2, key .. ": 2 Arcade + 2 Extinction")
end

-- einen Arcade-Wochen-Auftrag schaffen und abholen
local _, weekly = count(booster, "SpecialWeekly", "Arcade")
local questId
for _, id in weekly.Ids do
	if QuestConfig.Get(id).Mode == "Arcade" then
		questId = id
		break
	end
end
local quest = QuestConfig.Get(questId)
check(string.find(QuestConfig.RewardText(quest), "Skin Unterstützer", 1, true) ~= nil, "Belohnung nennt den Skin")
ProgressService.QuestEvent(booster, quest.Event, quest.Goal)
ProgressService.QuestEvent(normal, quest.Event, quest.Goal)
local message, ok = ProgressService.ClaimQuest(booster, questId)
check(ok == true, "abholen: " .. tostring(message))
check(ProgressService.Owns(booster, "W_Unterstuetzer"), "Skin bekommen")
check(QuestConfig.RewardText(quest, nil, Cosmetics.GetOwned(booster)):find("Skin", 1, true) == nil, "im Besitz: Skin nicht mehr genannt")

-- zweiter Wochen-Auftrag: kein zweites Stück
for _, id in weekly.Ids do
	local other = QuestConfig.Get(id)
	if id ~= questId then
		ProgressService.QuestEvent(booster, other.Event, other.Goal)
		ProgressService.ClaimQuest(booster, id)
		break
	end
end
check(ProgressService.ItemCount(booster, "W_Unterstuetzer") == 1, "nur ein Stück")

-- ohne Berechtigung: nichts
message, ok = ProgressService.ClaimQuest(normal, questId)
check(ok == false and not ProgressService.Owns(normal, "W_Unterstuetzer"), "ohne VIP/Booster kein Abholen: " .. tostring(message))

-- Arcade aus: neue Spieler bekommen keine Arcade-Aufträge
Modes.ArcadeEnabled = false
store.Data.u3 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local vip = SIM.Join("Vip")
vip:SetAttribute("StaffRank", "Booster")
step(2)
for _, key in { "SpecialQuests", "SpecialWeekly" } do
	check(count(vip, key, "Arcade") == 0 and count(vip, key, "Extinction") == 2, key .. ": Arcade aus: 0 Arcade + 2 Extinction")
end
for _, key in { "Quests", "Weekly" } do
	local data = QuestConfig.Read(vip, key)
	check(data ~= nil and #data.Ids == 0, key .. ": Arcade aus: keine Arcade-Aufträge")
end
check(#(QuestConfig.Read(vip, "ExtQuests") or { Ids = {} }).Ids > 0, "Arcade aus: Extinction-Aufträge gibt es weiter")
message, ok = ProgressService.ClaimWeeklyBonus(vip)
check(ok == false, "Arcade aus: kein Wochen-Bonus ohne Wochen-Aufträge: " .. tostring(message))
check(not QuestConfig.ModeActive("Arcade") and QuestConfig.ModeActive("Extinction"), "ModeActive")
-- Auftrag von gestern (nicht mehr im Satz): klare Meldung, die neuen Aufträge werden sofort geschickt
local todays = (QuestConfig.Read(vip, "ExtQuests") or { Ids = {} }).Ids
local stale
for _, quest in QuestConfig.ExtPool do
	if not table.find(todays, quest.Id) then
		stale = quest.Id
		break
	end
end
vip:SetAttribute("ExtQuests", nil)
message, ok = ProgressService.ClaimQuest(vip, stale)
check(ok == false and string.find(message, "Neuer Tag", 1, true) ~= nil, "alter Auftrag: neuer Tag (" .. tostring(message) .. ")")
check(QuestConfig.Read(vip, "ExtQuests") ~= nil, "alter Auftrag: aktuelle Aufträge neu geschickt")
Modes.ArcadeEnabled = true

if failures > 0 then
	error(failures .. " Fehler")
end
print("supporterquests: alles ok")

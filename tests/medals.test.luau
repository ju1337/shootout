--!signals immediate deferred
-- Test: Medaillen im KillService (Mehrfach-Kill, Killserie, Erstes Blut, Rache, Serie beendet, Comeback, Weitschuss)
-- Die übrigen Dienste sind Attrappen, die aufzeichnen, was der KillService auslöst; Meldungen an die Clients
-- stehen in SIM.RemoteLog.
local function noop() end
local KILL = { XP = {}, Coins = {}, Quests = {}, LastHits = {}, Killed = SIM.Signal(), BledOut = SIM.Signal() }
SIM.Stub("WeaponService", { Killed = KILL.Killed })
SIM.Stub("DownedService", { BledOut = KILL.BledOut })
SIM.Stub("BuyService", { AddMoney = noop })
SIM.Stub("Damage", {
	LastHit = function(model)
		return KILL.LastHits[model]
	end,
	Contributors = function()
		return {}
	end,
})
do
	local profiles = {}
	local function profileOf(player)
		profiles[player] = profiles[player] or { Stats = {} }
		return profiles[player]
	end
	SIM.Stub("ProgressService", {
		AddXP = function(player, _, amount, reason, quiet)
			table.insert(KILL.XP, { Player = player, Amount = amount, Reason = reason, Quiet = quiet })
			return amount
		end,
		AddCoins = function(player, amount, reason)
			table.insert(KILL.Coins, { Player = player, Amount = amount, Reason = reason })
		end,
		AddStat = function(player, key, amount)
			local stats = profileOf(player).Stats
			stats[key] = (stats[key] or 0) + amount
		end,
		Get = profileOf,
		QuestEvent = function(player, event, amount)
			table.insert(KILL.Quests, { Player = player, Event = event, Amount = amount })
		end,
		ActiveAgent = function()
			return "Viper"
		end,
	})
end
KILL.Fired = SIM.RemoteLog
local KillService = require("KillService")
-- SIM.Run nimmt eine absolute Zeit: um dt Sekunden weiterlaufen lassen
local function advance(dt)
	SIM.Run(SIM.Now + dt, dt, function() end)
end
local fails = 0
local function check(cond, text)
	if not cond then
		fails += 1
		print("FEHLER: " .. text)
	end
end

local players = {}
for _, name in { "Alpha", "Bravo", "Charlie", "Delta" } do
	local p = SIM.AddPlayer(name)
	p:SetAttribute("Mode", "FreeForAll")
	players[name] = p
end
KillService.Init()
for _, p in players do
	p:LoadCharacter()
end
advance(0.1)
local A, B, C, D = players.Alpha, players.Bravo, players.Charlie, players.Delta

-- Medaillen-Ids der letzten Notify-Meldung an player seit Index from
local function medalsSince(from, player)
	local ids = {}
	for i = from + 1, #KILL.Fired do
		local f = KILL.Fired[i]
		if f.Remote == "Notify" and f.Player == player and f.Args[1] == "Medal" then
			for _, m in f.Args[2] do
				ids[m.Id] = m
			end
		end
	end
	return ids
end

-- killer tötet victim (Spieler): Treffer merken, Leben auf 0, Kill melden (Reihenfolge wählbar)
local function kill(killer, victim, opts)
	opts = opts or {}
	local from = #KILL.Fired
	local model = victim.Character
	KILL.LastHits[model] = { Model = killer.Character, Name = killer.Name, Weapon = "Rifle" }
	local function report()
		KILL.Killed:Fire(killer, victim, opts.Weapon or "Rifle", opts.Headshot == true, victim.Name, model)
	end
	if opts.KillFirst then
		report()
		model:FindFirstChildOfClass("Humanoid").Health = 0
	else
		model:FindFirstChildOfClass("Humanoid").Health = 0
		report()
	end
	advance(0.1)
	victim:LoadCharacter()
	return medalsSince(from, killer)
end

-- 1) Erstes Blut + Kopfschuss
local m = kill(A, B, { Headshot = true })
check(m.FirstBlood ~= nil, "ERSTES BLUT beim ersten Kill")
check(m.Headshot ~= nil, "KOPFSCHUSS bei Kopfschuss")
check(m.DoubleKill == nil, "kein Mehrfach-Kill beim ersten Kill")

-- 2) Doppel-Kill und Triple-Kill kurz hintereinander, kein zweites Erstes Blut
m = kill(A, C)
check(m.DoubleKill ~= nil and m.FirstBlood == nil, "DOPPEL-KILL ohne zweites ERSTES BLUT")
m = kill(A, D)
check(m.TripleKill ~= nil, "TRIPLE-KILL")
check(m.Streak3 ~= nil, "KILLSERIE bei 3 Kills ohne Tod")
check(m.Streak3 and m.Streak3.Xp == 50, "Killserie gibt 50 XP")

-- 3) Nach der Pause kein Mehrfach-Kill mehr, Serie läuft weiter bis 5
advance(5)
m = kill(A, B)
check(m.DoubleKill == nil and m.QuadraKill == nil and m.FuryKill == nil, "nach 5 s kein Mehrfach-Kill")
m = kill(A, C)
check(m.DoubleKill ~= nil, "neuer DOPPEL-KILL")
check(m.Streak5 ~= nil, "GNADENLOS bei 5 Kills")
check(m.Streak5 and m.Streak5.Coins == 150, "5er-Killserie gibt 150 Münzen (RewardConfig)")
local function stat(player, key)
	local profile = require("ProgressService").Get(player)
	return profile.Stats[key] or 0
end
local quest = false
for _, q in KILL.Quests do
	quest = quest or (q.Player == A and q.Event == "Streak5")
end
check(quest, "Wochen-Auftrag 5er-Killserie gezählt")
check(stat(A, "BestStreak") == 5, "beste Killserie 5: " .. stat(A, "BestStreak"))

-- 4) Serie beendet: B tötet A (A hatte 5) – Reihenfolge Tod zuerst
m = kill(B, A)
check(m.Buzzkill ~= nil, "SERIE BEENDET (Tod vor Kill-Meldung)")
check(m.Buzzkill and m.Buzzkill.Coins == 100, "SERIE BEENDET ab 5 gibt 100 Münzen")
check(m.Revenge ~= nil, "RACHE: A hatte B zuletzt getötet")
check(m.Revenge and m.Revenge.Coins == 75, "RACHE gegen Spieler gibt 75 Münzen")
check(stat(B, "Shutdowns") == 1 and stat(B, "Revenges") == 1, "Statistik Shutdowns/Revenges")

-- 5) Rache in die andere Richtung, Kill-Meldung vor dem Tod
m = kill(A, B, { KillFirst = true })
check(m.Revenge ~= nil, "RACHE für A")
check(m.Buzzkill == nil, "B hatte nur 1 Kill: keine SERIE BEENDET")

-- 6) Serie beendet, wenn die Kill-Meldung vor dem Tod ankommt
advance(5)
kill(C, D)
kill(C, B)
advance(5)
kill(C, D)
advance(5)
m = kill(D, C, { KillFirst = true })
check(m.Buzzkill ~= nil, "SERIE BEENDET (Kill-Meldung vor dem Tod)")
check(m.Buzzkill and m.Buzzkill.Coins == nil, "SERIE BEENDET unter 5 Kills ohne Münzen")

-- 7) Comeback: B stirbt dreimal ohne Kill, dann Kill
advance(5)
kill(A, B)
advance(5)
kill(C, B)
advance(5)
kill(D, B)
advance(5)
m = kill(B, A)
check(m.Comeback ~= nil, "COMEBACK nach 3 Toden")
advance(5)
m = kill(B, C)
check(m.Comeback == nil, "kein zweites COMEBACK")

-- 8) Weitschuss: Abstand größer als die Grenze der Waffe
advance(5)
A.Character.HumanoidRootPart.Position = Vector3.new(0, 3, 0)
C.Character.HumanoidRootPart.Position = Vector3.new(150, 3, 0)
m = kill(A, C)
check(m.Longshot ~= nil, "WEITSCHUSS auf 150 Studs mit dem Sturmgewehr")
advance(5)
A.Character.HumanoidRootPart.Position = Vector3.new(0, 3, 0)
D.Character.HumanoidRootPart.Position = Vector3.new(30, 3, 0)
m = kill(A, D)
check(m.Longshot == nil, "kein WEITSCHUSS auf 30 Studs")
advance(5)
B.Character.HumanoidRootPart.Position = Vector3.new(0, 3, 0)
D.Character.HumanoidRootPart.Position = Vector3.new(40, 3, 0)
m = kill(B, D, { Weapon = "Shotgun" })
check(m.Longshot ~= nil, "WEITSCHUSS mit der Schrotflinte auf 40 Studs")

-- 8b) Rache an einem Bot: Medaille, aber keine Münzen
advance(5)
local bot = SIM.MakeRig("BOT Echo")
bot.Parent = workspace
KILL.LastHits[A.Character] = { Model = bot, Name = "BOT Echo", Weapon = "Rifle" }
A.Character:FindFirstChildOfClass("Humanoid").Health = 0
advance(0.1)
A:LoadCharacter()
advance(5)
local from = #KILL.Fired
KILL.Killed:Fire(A, nil, "Rifle", false, "BOT Echo", bot)
advance(0.1)
m = medalsSince(from, A)
check(m.Revenge ~= nil and m.Revenge.Coins == nil, "RACHE am Bot ohne Münzen")

-- 9) Neue Runde: Erstes Blut wieder frei; Bot-Kill nimmt es weg
KillService.NewRound("FreeForAll")
KillService.ReportBotKill("FreeForAll", "BOT Echo", "Alpha", "Rifle", false)
advance(5)
m = kill(C, D)
check(m.FirstBlood == nil, "Bot hatte ERSTES BLUT schon")
KillService.NewRound("FreeForAll")
advance(5)
m = kill(D, C)
check(m.FirstBlood ~= nil, "ERSTES BLUT nach neuer Runde")

-- 10) Medaillen-XP leise, Liste sortiert (höchste Stufe zuerst)
local loud = 0
for _, entry in KILL.XP do
	if entry.Reason ~= "Kill" and entry.Reason ~= "Kopfschuss-Kill" and not entry.Quiet then
		loud += 1
	end
end
check(loud == 0, "Medaillen-XP werden leise vergeben")
for _, f in KILL.Fired do
	if f.Remote == "Notify" and f.Args[1] == "Medal" then
		local list = f.Args[2]
		local Medals = require("Medals")
		for i = 2, #list do
			check(Medals.Get(list[i - 1].Id).Tier >= Medals.Get(list[i].Id).Tier, "Medaillen nach Stufe sortiert")
		end
	end
end

-- 11) Mehrfach-Kill-Namen bis zur Kill-Kette
local Medals = require("Medals")
check(Medals.ForMulti(1) == nil and Medals.ForMulti(2) == "DoubleKill" and Medals.ForMulti(8) == "UltraKill"
	and Medals.ForMulti(12) == "KillChain", "Medals.ForMulti")
check(Medals.ForStreak(10) == "Streak10" and Medals.ForStreak(11) == nil, "Medals.ForStreak")
for id, medal in Medals.List do
	check(medal.Title ~= nil and medal.Tier >= 1 and medal.Tier <= 4 and medal.Icon ~= nil, "Medaille vollständig: " .. id)
end

print(fails == 0 and "ALLE TESTS OK" or ("FEHLER: " .. fails))

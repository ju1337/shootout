-- EP der offenen Welt (ExtLevelService, ExtLevelConfig): nur in der offenen Welt, für Aktivitäten, Lootdrops (je Kiste
-- einmal) und Aufträge. Es gibt nur EIN Level: die EP gehen ins Spielerlevel (AccountXP, LevelConfig, mit Doppel-XP),
-- die Statistik ExtXP zählt mit; Titel der offenen Welt ab Spielerlevel 5. Kills (Zombies, Spieler, Bots) zählen hier
-- nur in der Statistik (Count) – ihre Level-XP kommen einmal über ProgressService.AddXP.
-- Alte Spielstände mit eigenem Extinction-Level werden einmal ins Spielerlevel übernommen (ohne Verlust).
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 1, 20) -- mit Heartbeat (Safe-Zone-Prüfung, Magazin-Abgleich)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local HttpService = game:GetService("HttpService")
local Remotes = require("Remotes")
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
local Damage = require("Damage")
ProgressService.Init()
WeaponService.Init()

-- Karte wie aus tools/build_maps.py: Safe Zone (Radius 100) um (0, 0, -6000), Spawns, Stände, Lager, Tor zum Hub
local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("DisplayName", "Ödland")
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
-- kleine Safe Zone draußen (Safehouse) mit eigenen Spawns
local safehouse = Instance.new("Part", map.Zone)
safehouse.Name = "SafeZone_Test"
safehouse:SetAttribute("Title", "SAFEHOUSE TEST")
safehouse.Size = Vector3.new(80, 80, 80)
safehouse.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 600))
local safehouseSpawns = Instance.new("Folder", map)
safehouseSpawns.Name = "Spawns_Test"
Instance.new("Part", safehouseSpawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 610))
local houseStand = Instance.new("Part", map.Stands) -- zweiter Waffenstand im Safehouse (gleicher Name)
houseStand.Name = "Stand_Weapons"
houseStand.CFrame = CFrame.new(CENTER + Vector3.new(-12, 2.5, 600))
local travelStop = Instance.new("Part", map.Stands)
travelStop.Name = "Travel"
travelStop.CFrame = CFrame.new(CENTER + Vector3.new(-36, 2.5, 16))
local spawnPoint = Instance.new("Part", map.Spawns)
spawnPoint.CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
local portal = Instance.new("Part", map.Portals)
portal.Name = "Portal_Hub"
portal.CFrame = CFrame.new(CENTER + Vector3.new(-62, 0.4, -32))
local standPos = {
	Stand_Weapons = CENTER + Vector3.new(-36, 2.5, 34),
	Stand_Items = CENTER + Vector3.new(36, 2.5, 34),
	Stand_Vehicles = CENTER + Vector3.new(-30, 2.5, -42),
	Stash = CENTER + Vector3.new(52, 2.5, -30),
}
for name, position in standPos do
	local part = Instance.new("Part", map.Stands)
	part.Name = name
	part.CFrame = CFrame.new(position)
end

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
InventoryService.Init()
LootService.Init()
local statusText = nil
local manager = {
	Join = function(player, modeId)
		if modeId ~= "Extinction" and player:GetAttribute("Mode") == "Extinction" then
			if Extinction.ConfirmLeave(player) then
				Extinction.RemovePlayer(player)
				player:SetAttribute("Mode", modeId)
			end
		end
	end,
	Status = function(_, text)
		statusText = text
	end,
}
require("ExtinctionConfig").Airdrop.FirstDelay = math.huge -- hier keine Lootdrops (eigener Test: airdrop)
require("ExtinctionConfig").Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
require("ExtinctionConfig").HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
require("ExtinctionConfig").Day.Fixed = 12 -- immer Tag (nachts mehr Zombies; eigener Test: daycycle)
require("ExtinctionConfig").Zombies.KindWeights = { Walker = 1 } -- nur normale Zombies (Schreier rufen sonst Verstärkung)
Extinction.Init(manager)

local function bagOf(player)
	return HttpService:JSONDecode(player:GetAttribute("ExtBag") or "[]")
end
local function slot(player, s)
	for _, entry in bagOf(player) do
		if entry.S == s then
			return entry
		end
	end
	return nil
end
local function lastExt(player, kind)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "ExtUpdate" and entry.Player == player and entry.Args[1] == kind then
			return entry.Args
		end
	end
	return nil
end
local function lastAmmo(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "AmmoUpdate" and entry.Player == player then
			return entry.Args
		end
	end
	return nil
end
local function moveTo(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
	step(0.3)
end
local function enter(player)
	player:SetAttribute("Mode", "Extinction")
	Extinction.AddPlayer(player)
	step(0.3)
end

local ExtLevelConfig = require("ExtLevelConfig")
local ExtLevelService = require("ExtLevelService")
local TitleConfig = require("TitleConfig")
local ZombieService = require("ZombieService")
local ActivityService = require("ActivityService")
local MissionService = require("MissionService")

local LevelConfig = require("LevelConfig")
local function accountXP(player)
	return player:GetAttribute("AccountXP") or 0
end
local function extXP(player)
	return ProgressService.Get(player).Stats.ExtXP or 0
end

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {}, AccountXP = 0, LevelMerged = true }
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)

-- Kurve
check(ExtLevelConfig.FromXP(0) == 1, "Start Level 1")
local level, into, need = ExtLevelConfig.FromXP(ExtLevelConfig.TotalFor(5) + 10)
check(level == 5 and into == 10 and need == ExtLevelConfig.XPForLevel(5), "Level aus EP")
check(ExtLevelConfig.FromXP(10 ^ 9) == ExtLevelConfig.MaxLevel, "höchstens MaxLevel")

-- außerhalb der offenen Welt: keine EP
alice:SetAttribute("Mode", "FreeForAll")
check(ExtLevelService.Add(alice, 100, "Test") == nil, "keine EP außerhalb")
enter(alice)
check(alice:GetAttribute("ExtLevel") == nil, "kein eigenes Extinction-Level mehr")
-- (in den Ereignissen kommen nur EP der offenen Welt dazu: Agenten-XP für Zombies gibt der echte ZombieService)
local startXP = accountXP(alice)

-- Ereignisse
local function fire(list, ...)
	for _, callback in list do
		callback(...)
	end
end
-- Zombie-Kills: nur Statistik (keine zweiten Level-XP, keine zweite "+XP"-Anzeige)
fire(ZombieService.OnKill, alice, "Walker", CENTER + Vector3.new(0, 0, 300))
check(accountXP(alice) == startXP, "Zombie: keine EP aufs Spielerlevel (XP gibt nur AddXP)")
check(extXP(alice) == ExtLevelConfig.Rewards.Zombie, "Statistik ExtXP zählt mit")
check(ProgressService.Get(alice).Stats.ExtZombies == 1, "Statistik ExtZombies zählt mit")
fire(ZombieService.OnKill, alice, "Brute", CENTER + Vector3.new(0, 0, 300))
check(accountXP(alice) == startXP, "Brocken: auch keine EP aufs Spielerlevel")
check(extXP(alice) == ExtLevelConfig.Rewards.Zombie + ExtLevelConfig.Kinds.Brute, "Brocken zählt mehr in der Statistik")
check(lastExt(alice, "ExtXP") == nil, "keine EP-Anzeige für Kills")
local before = accountXP(alice)
fire(ActivityService.OnEvent, alice, "Nest")
check(accountXP(alice) == before + ExtLevelConfig.Rewards.Nest, "Nest zerstört")
local popup = lastExt(alice, "ExtXP")
check(popup and popup[2] == ExtLevelConfig.Rewards.Nest and popup[3] == "Nest", "Anzeige +XP an den Client")
-- Doppel-XP (Gamepass/Boost) gilt auch für die EP
alice:SetAttribute("Pass_DoubleXP", true)
before = accountXP(alice)
local beforeStat = extXP(alice)
fire(ActivityService.OnEvent, alice, "Nest")
check(accountXP(alice) == before + 2 * ExtLevelConfig.Rewards.Nest, "Doppel-XP: doppelte EP aufs Spielerlevel")
check(extXP(alice) == beforeStat + ExtLevelConfig.Rewards.Nest, "Statistik zählt die einfachen EP")
popup = lastExt(alice, "ExtXP")
check(popup and popup[2] == 2 * ExtLevelConfig.Rewards.Nest and popup[3] == "Nest · Doppel-XP", "Anzeige mit Doppel-XP")
alice:SetAttribute("Pass_DoubleXP", nil)
before = accountXP(alice)
local bag = { Kind = "Airdrop", Id = 77 }
fire(LootService.OnOpened, alice, bag)
step(0.1) -- (kann nebenbei einen Lootdrop-Auftrag erledigen: dann kommen dessen EP dazu)
local afterFirst = accountXP(alice)
check(afterFirst >= before + ExtLevelConfig.Rewards.Airdrop, "Lootdrop gibt XP")
fire(LootService.OnOpened, alice, bag)
step(0.1)
check(accountXP(alice) == afterFirst, "dieselbe Kiste zählt nur einmal")
before = accountXP(alice)
fire(MissionService.OnComplete, alice, {})
step(0.1)
check(accountXP(alice) == before + ExtLevelConfig.Rewards.Mission, "Auftrag erledigt")
check(ProgressService.Get(alice).AccountXP == accountXP(alice), "XP im Profil")

-- Spielerlevel 5: Titel der offenen Welt frei (Meldung kommt über das Spielerlevel, keine eigene Extinction-Meldung)
local toFive = 0
for l = 1, 4 do
	toFive += LevelConfig.XPForLevel(l)
end
local level = ExtLevelService.Add(alice, toFive - accountXP(alice), "Test")
check(level == 5 and LevelConfig.Get(alice).Level == 5, "Spielerlevel 5")
local title = TitleConfig.Get("Ext_Ueberlebender")
check(title ~= nil and TitleConfig.Unlocked(title, ProgressService.TitleData(alice)), "Titel Überlebender frei")
check(not TitleConfig.Unlocked(TitleConfig.Get("Ext_Pluenderer"), ProgressService.TitleData(alice)), "Plünderer noch gesperrt")
for _, entry in SIM.RemoteLog do
	if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" and entry.Args[2]
		and entry.Args[2].Caption == "Extinction" then
		check(false, "keine eigene Extinction-Level-Meldung mehr")
		break
	end
end

-- Übernahme alter Spielstände: EP kommen aufs Spielerlevel, mindestens bis zum alten Extinction-Level
local function totalFor(level_)
	local xp = 0
	for l = 1, level_ - 1 do
		xp += LevelConfig.XPForLevel(l)
	end
	return xp
end
-- (a) altes Extinction-Level 12, Spielerlevel 3: Spielerlevel mindestens 12
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {}, AccountXP = totalFor(3),
	Stats = { ExtXP = ExtLevelConfig.TotalFor(12) + 5 } }
local bob = SIM.Join("Bob")
step(2)
local bobProfile = ProgressService.Get(bob)
check(bobProfile.LevelMerged == true, "Übernahme vermerkt")
check(LevelConfig.FromXP(bobProfile.AccountXP) >= 12, "Spielerlevel nicht unter dem alten Extinction-Level")
check(bobProfile.AccountXP >= totalFor(3) + ExtLevelConfig.TotalFor(12), "XP addiert (Spielerlevel-Fortschritt bleibt)")
check(bobProfile.Stats.ExtXP == ExtLevelConfig.TotalFor(12) + 5, "Statistik bleibt (Erfolg)")
-- (b) hohes Spielerlevel, kleines Extinction-Level: XP addiert
store.Data.u3 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {}, AccountXP = totalFor(40), Prestige = 2,
	Stats = { ExtXP = 300 } }
local cara = SIM.Join("Cara")
step(2)
check(ProgressService.Get(cara).AccountXP == totalFor(40) + 300, "XP addiert")
check(ProgressService.Get(cara).Prestige == 2, "Prestige bleibt")
-- (c) schon übernommen: nicht noch einmal
store.Data.u4 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {}, AccountXP = 1000, LevelMerged = true,
	Stats = { ExtXP = 5000 } }
local dora = SIM.Join("Dora")
step(2)
check(ProgressService.Get(dora).AccountXP == 1000, "nur einmal übernommen")
-- (d) neuer Spieler: gilt als übernommen
local eve = SIM.Join("Eve")
step(2)
check(ProgressService.Get(eve).LevelMerged == true, "neues Profil gilt als übernommen")

if failures == 0 then
	print("Spielerlevel aus der offenen Welt in Ordnung")
end

-- Extinction-Level (ExtLevelService, ExtLevelConfig): EP nur in der offenen Welt, für Zombies (Art und rote Zone),
-- Aktivitäten, Lootdrops (je Kiste einmal), Aufträge, Spieler- und Bot-Kills; Level aus der Statistik ExtXP mit
-- Meldung beim Aufstieg (Titel-Level mit Titel); Titel ab Level 5 über TitleConfig freigeschaltet; Spieler-Attribute.
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

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
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
check(alice:GetAttribute("ExtLevel") == 1 and alice:GetAttribute("ExtXP") == 0, "Attribute beim Betreten")

-- Ereignisse
local function fire(list, ...)
	for _, callback in list do
		callback(...)
	end
end
fire(ZombieService.OnKill, alice, "Walker", CENTER + Vector3.new(0, 0, 300))
check(alice:GetAttribute("ExtXP") == ExtLevelConfig.Rewards.Zombie, "Zombie: " .. ExtLevelConfig.Rewards.Zombie .. " EP")
fire(ZombieService.OnKill, alice, "Brute", CENTER + Vector3.new(0, 0, 300))
check(alice:GetAttribute("ExtXP") == ExtLevelConfig.Rewards.Zombie + ExtLevelConfig.Kinds.Brute, "Brocken gibt mehr")
local popup = lastExt(alice, "ExtXP")
check(popup and popup[2] == ExtLevelConfig.Kinds.Brute, "Anzeige +EP an den Client")
local before = alice:GetAttribute("ExtXP")
fire(ActivityService.OnEvent, alice, "Nest")
check(alice:GetAttribute("ExtXP") == before + ExtLevelConfig.Rewards.Nest, "Nest zerstört")
before = alice:GetAttribute("ExtXP")
local bag = { Kind = "Airdrop", Id = 77 }
fire(LootService.OnOpened, alice, bag)
step(0.1) -- (kann nebenbei einen Lootdrop-Auftrag erledigen: dann kommen dessen EP dazu)
local afterFirst = alice:GetAttribute("ExtXP")
check(afterFirst >= before + ExtLevelConfig.Rewards.Airdrop, "Lootdrop gibt EP")
fire(LootService.OnOpened, alice, bag)
step(0.1)
check(alice:GetAttribute("ExtXP") == afterFirst, "dieselbe Kiste zählt nur einmal")
before = alice:GetAttribute("ExtXP")
fire(MissionService.OnComplete, alice, {})
step(0.1)
check(alice:GetAttribute("ExtXP") == before + ExtLevelConfig.Rewards.Mission, "Auftrag erledigt")

-- Aufstieg bis Level 5: Meldung mit Titel, Titel freigeschaltet
local toFive = ExtLevelConfig.TotalFor(5) - alice:GetAttribute("ExtXP")
ExtLevelService.Add(alice, toFive, "Test")
check(alice:GetAttribute("ExtLevel") == 5, "Level 5")
local banner = nil
for i = #SIM.RemoteLog, 1, -1 do
	local entry = SIM.RemoteLog[i]
	if entry.Remote == "Notify" and entry.Player == alice and entry.Args[1] == "Banner" then
		banner = entry.Args[2]
		break
	end
end
check(banner and banner.Title == "LEVEL 5" and string.find(banner.Sub, "Überlebender", 1, true) ~= nil, "Meldung mit neuem Titel")
local title = TitleConfig.Get("Ext_Ueberlebender")
check(title ~= nil and TitleConfig.Unlocked(title, ProgressService.TitleData(alice)), "Titel Überlebender frei")
check(not TitleConfig.Unlocked(TitleConfig.Get("Ext_Pluenderer"), ProgressService.TitleData(alice)), "Plünderer noch gesperrt")
check(ProgressService.Get(alice).Stats.ExtXP == ExtLevelConfig.TotalFor(5), "EP im Profil (Statistik)")

if failures == 0 then
	print("Extinction-Level in Ordnung")
end

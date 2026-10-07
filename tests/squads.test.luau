-- Squads in der offenen Welt (PartyService): Einladen und Annehmen setzen dieselbe SquadId, Verlassen/Auflösen löscht sie;
-- im Squad kein Friendly Fire (Schüsse), gegen andere schon; Pings gehen an den Squad (nicht an andere, im Free-for-All nicht
-- an Squad-Mitglieder), ein Squad-Mitglied ist kein gepingter Gegner; verlässt der Anführer die offene Welt, bleiben die anderen
-- dort, betritt er sie, kommt der Squad mit
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 1, 20)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local Remotes = require("Remotes")
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
ProgressService.Init()
WeaponService.Init()

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local PartyService = require("PartyService")
local PingService = require("PingService")
InventoryService.Init()
LootService.Init()
PingService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0
ExtinctionConfig.Redzone.Enabled = false

-- Modus-Verwaltung (vereinfacht): Hub und offene Welt, Joined meldet jeden Wechsel
local joinedEvent = Instance.new("BindableEvent")
local manager
manager = {
	Joined = joinedEvent.Event,
	Status = function() end,
	Join = function(player, modeId)
		local current = player:GetAttribute("Mode")
		if current == modeId then
			return
		end
		if current == "Extinction" then
			Extinction.RemovePlayer(player)
		end
		player:SetAttribute("Mode", modeId)
		if modeId == "Extinction" then
			Extinction.AddPlayer(player)
		end
		joinedEvent:Fire(player, modeId)
	end,
}
Extinction.Init(manager)
PartyService.Init(manager)

local players = {}
for i, name in { "Alice", "Bob", "Carl" } do
	store.Data["u" .. i] = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
	local player = SIM.Join(name)
	Instance.new("Backpack", player).Name = "Backpack"
	players[name] = player
end
local alice, bob, carl = players.Alice, players.Bob, players.Carl
step(2)
for _, player in { alice, bob, carl } do
	manager.Join(player, "Extinction")
end
step(0.5)
local function lastRemote(remote, player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == remote and entry.Player == player then
			return entry.Args, i
		end
	end
	return nil, 0
end
local function party(action, player, target)
	Remotes.PartyAction.OnServerEvent:Fire(player, action, target and target.UserId)
	step(0.1)
end

-- ---------- Squad bilden ----------
party("Invite", alice, bob)
local invite = lastRemote("PartyInvite", bob)
check(invite and invite[1] == "Alice" and invite[2] == alice.UserId, "Bob bekommt die Einladung")
party("Accept", bob, alice)
local squad = alice:GetAttribute("SquadId")
check(squad ~= nil and bob:GetAttribute("SquadId") == squad, "gleiche SquadId für Alice und Bob (" .. tostring(squad) .. ")")
check(carl:GetAttribute("SquadId") == nil, "Carl ist nicht im Squad")
check(PartyService.SameSquad(alice, bob) and not PartyService.SameSquad(alice, carl), "SameSquad")
check(bob:GetAttribute("Mode") == "Extinction", "Bob bleibt in der offenen Welt (wie Alice)")

-- ---------- kein Friendly Fire ----------
local function place(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
end
place(alice, Vector3.new(0, 3, 200))
place(bob, Vector3.new(0, 3, 215))
place(carl, Vector3.new(10, 3, 200))
step(ExtinctionConfig.PvPDelay + 0.6)
check(alice:GetAttribute("PvP") and bob:GetAttribute("PvP") and carl:GetAttribute("PvP"), "alle draußen mit PvP")
InventoryService.Give(alice, "Rifle", 1)
InventoryService.Give(alice, "Ammo_Rifle", 60)
InventoryService.Use(alice, 1)
step(0.5)
check(WeaponService.CarriedWeapon(alice) == "Rifle", "Alice hat das Gewehr in der Hand")
local function shoot(shooter, target, id)
	local origin = shooter.Character.Head.Position
	local direction = (target.Character.Head.Position - origin).Unit
	Remotes.Fire.OnServerEvent:Fire(shooter, origin, direction, false, id,
		{ { Part = target.Character.Head, Position = target.Character.Head.Position } })
	step(0.3)
end
shoot(alice, bob, 1)
check(bob.Character.Humanoid.Health == bob.Character.Humanoid.MaxHealth, "Squad-Mitglied nimmt keinen Schaden")
shoot(alice, carl, 2)
check(carl.Character.Humanoid.Health < carl.Character.Humanoid.MaxHealth, "Carl (nicht im Squad) schon")

-- ---------- Pings nur an den Squad ----------
local _, before = lastRemote("PingShow", carl)
Remotes.Ping.OnServerEvent:Fire(alice, CENTER + Vector3.new(0, 0, 230), nil)
local seenAlice = lastRemote("PingShow", alice)
local seenBob = lastRemote("PingShow", bob)
local _, after = lastRemote("PingShow", carl)
check(seenAlice ~= nil and seenBob ~= nil and seenBob[3] == "Alice", "Ping erscheint bei Alice und Bob")
check(after == before, "Carl sieht den Ping nicht")
step(1)
Remotes.Ping.OnServerEvent:Fire(alice, bob.Character.HumanoidRootPart.Position, bob.Character)
check(lastRemote("PingShow", bob)[2] == nil, "Squad-Mitglied ist kein gepingter Gegner")
step(1)
Remotes.Ping.OnServerEvent:Fire(alice, carl.Character.HumanoidRootPart.Position, carl.Character)
check(lastRemote("PingShow", bob)[2] == carl.Character, "Carl als Gegner gepingt")

-- ---------- Anführer verlässt die offene Welt: Bob bleibt ----------
place(alice, Vector3.new(0, 3, 20))
step(0.5)
manager.Join(alice, "Hub")
step(0.2)
check(alice:GetAttribute("Mode") == "Hub" and bob:GetAttribute("Mode") == "Extinction", "Bob wird nicht aus der offenen Welt gezogen")
-- Anführer betritt die offene Welt: der Squad kommt mit
place(bob, Vector3.new(0, 3, 20))
step(0.5)
manager.Join(bob, "Hub")
step(0.2)
check(bob:GetAttribute("Mode") == "Hub", "Bob im Hub")
manager.Join(alice, "Extinction")
step(0.2)
check(bob:GetAttribute("Mode") == "Extinction", "Anführerin betritt die offene Welt: Bob kommt mit")

-- Im Free-for-All bekommen Squad-Mitglieder die Pings nicht (dort sind sie Gegner)
alice:SetAttribute("Mode", "FreeForAll")
bob:SetAttribute("Mode", "FreeForAll")
step(1)
local _, ffaBefore = lastRemote("PingShow", bob)
Remotes.Ping.OnServerEvent:Fire(alice, alice.Character.HumanoidRootPart.Position + Vector3.new(0, 0, 10), nil)
local _, ffaAfter = lastRemote("PingShow", bob)
check(ffaAfter == ffaBefore, "Free-for-All: kein Squad-Ping")
alice:SetAttribute("Mode", "Extinction")
bob:SetAttribute("Mode", "Extinction")

-- ---------- Verlassen löst den Zweier-Squad auf ----------
party("Leave", bob)
check(bob:GetAttribute("SquadId") == nil and alice:GetAttribute("SquadId") == nil, "Squad aufgelöst: keine SquadId mehr")

if failures > 0 then
	error(failures .. " Fehler")
end
print("squads: alles ok")

-- Konvoi (ConvoyService): wartet am Start (Ansage, Karten-Attribut Convoys), fährt die Strecke entlang, Schüsse auf ein
-- Fahrzeug kosten Leben, unter HaltAt hält er an und Wachen (Bots) steigen aus, sind sie erledigt, liegt die Ladung als
-- Kiste am Lkw und alle Angreifer bekommen Münzen; Kiste weg = vorbei; ein zweiter Konvoi, der nicht aufgehalten wird,
-- entkommt am Ende der Strecke; Treffer aus der Safe Zone zählen nicht.
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
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
local Damage = require("Damage")
local Remotes = require("Remotes")
ProgressService.Init()
WeaponService.Init()

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Places" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
-- ein Ort für die rote Zone (Süden)
local place = Instance.new("Part", map.Places)
place.Name = "Place_Test"
place:SetAttribute("Title", "Testzone")
place.Size = Vector3.new(200, 4, 200)
place.CFrame = CFrame.new(CENTER + Vector3.new(0, 2, -700))

local ground = Instance.new("Part", workspace)
ground.Name = "Ground"
SIM.RaycastHandler = function(origin, direction)
	if direction.Y >= 0 then
		return nil
	end
	return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0), Instance = ground, Material = Enum.Material.Grass }
end

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local ZombieService = require("ZombieService")
local RedzoneService = require("RedzoneService")
local RedzoneBoard = require("RedzoneBoard")
local BotService = require("BotService")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge -- hier keine Lootdrops
ExtinctionConfig.Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
ExtinctionConfig.Convoy.FirstDelay = math.huge -- Konvoi startet der Test selbst
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0 -- Zombies nur, wo der Test sie hinstellt
ExtinctionConfig.Zombies.KindWeights = { Walker = 1 }
local manager = { Join = function() end, Status = function() end }
Extinction.Init(manager)

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
step(2)
alice:SetAttribute("Mode", "Extinction")
Extinction.AddPlayer(alice)
step(0.5)

local HttpService = game:GetService("HttpService")
local ConvoyService = require("ConvoyService")
local K = ExtinctionConfig.Convoy

local function convoys()
	return HttpService:JSONDecode(map:GetAttribute("Convoys") or "[]")
end
local function lastBanner(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "Notify" and entry.Player == player and entry.Args[1] == "Banner" then
			return entry.Args[2]
		end
	end
	return nil
end

check(#K.Routes >= 3, "mehrere Strecken")
check(#convoys() == 0, "anfangs kein Konvoi")

-- Start: wartet
alice.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 300))) -- draußen
step(0.5)
local convoy = ConvoyService.Start(1)
check(convoy ~= nil and convoy.State == "Waiting", "Konvoi wartet am Start")
check(ConvoyService.Start(2) == nil, "nur ein Konvoi gleichzeitig")
step(0.3)
local list = convoys()
check(#list == 1 and list[1].State == "Waiting", "Karte: Konvoi wartet")
local banner = lastBanner(alice)
check(banner and banner.Title == "KONVOI GESICHTET", "Ansage: gesichtet")
local trucks = workspace.ExtinctionConvoy:GetChildren()
check(#trucks == 3, "drei Fahrzeuge (" .. #trucks .. ")")
local truck = workspace.ExtinctionConvoy:FindFirstChild("ConvoyTruck")
check(truck and truck:GetAttribute("Convoy") == true and truck:GetAttribute("VehicleId") == nil, "Lkw: Konvoi, kein Spieler-Fahrzeug")
check(WeaponService.OnConvoyHit == ConvoyService.Hit, "WeaponService meldet Konvoi-Treffer")

-- fährt los
local startPos = truck:GetPivot().Position
step(K.Warning + 1)
check(convoy.State == "Driving", "fährt nach der Wartezeit los")
step(3)
local moved = (truck:GetPivot().Position - startPos).Magnitude
check(moved > K.Speed * 2, "Lkw fährt die Strecke entlang (" .. math.floor(moved) .. " Studs)")
check(math.abs(truck:GetPivot().Position.Y - 0) < 1, "auf dem Boden")

-- Treffer aus der Safe Zone zählen nicht
alice.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 0)))
step(0.5)
WeaponService.OnConvoyHit(alice, truck, 5000)
check(convoy.Health == K.Health, "Schüsse aus der Safe Zone zählen nicht")
alice.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 300)))
step(0.5)

-- beschießen bis zum Anhalten
local coinsBefore = ProgressService.Get(alice).Coins
WeaponService.OnConvoyHit(alice, truck, K.Health * 0.2)
check(convoy.State == "Driving", "ein paar Treffer: fährt weiter")
WeaponService.OnConvoyHit(alice, truck, K.Health * 0.2)
check(convoy.State == "Halted", "unter HaltAt: angehalten")
step(1) -- Wachen bauen
check(#convoy.Guards == K.Guards, "Wachen steigen aus (" .. #convoy.Guards .. ")")
banner = lastBanner(alice)
check(banner and banner.Title == "KONVOI GESTOPPT", "Ansage: gestoppt")
local haltedAt = truck:GetPivot().Position
step(2)
check((truck:GetPivot().Position - haltedAt).Magnitude < 0.1, "steht still")
check(convoys()[1].State == "Halted", "Karte: gestoppt")

-- Wachen erledigen: Ladung frei
for _, guard in convoy.Guards do
	local humanoid = guard.Model and guard.Model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end
step(1)
check(convoy.State == "Loot" and convoy.LootId ~= nil, "Ladung frei (Kiste am Lkw)")
check(ProgressService.Get(alice).Coins >= coinsBefore + K.Coins, "Münzen für den Angreifer")
banner = lastBanner(alice)
check(banner and banner.Title == "KONVOI GEKNACKT", "Ansage: geknackt")
local bag = LootService.Get(convoy.LootId)
check(bag ~= nil and bag.Kind == "Airdrop", "Kiste wie ein Lootdrop (E halten)")
local attachments = 0
for _, item in bag and bag.Container.Slots or {} do
	if string.sub(item.Id, 1, 4) == "Att_" then
		attachments += 1
	end
end
check(attachments >= K.Attachments[1], "Ladung mit sicheren Waffen-Aufsätzen (" .. attachments .. ")")

-- Kiste weg: vorbei, Fahrzeuge weg
LootService.Remove(convoy.LootId)
step(0.5)
check(ConvoyService.Current() == nil and #convoys() == 0, "vorbei, Karte leer")
check(#workspace.ExtinctionConvoy:GetChildren() == 0, "Fahrzeuge weg")

-- zweiter Konvoi entkommt
local second = ConvoyService.Start(4)
check(second ~= nil, "nächster Konvoi")
step(K.Warning + 1)
second.Distance = second.Path.Total + 3 * K.Spacing
step(0.5)
check(ConvoyService.Current() == nil, "am Ende der Strecke entkommen")
banner = lastBanner(alice)
check(banner and banner.Title == "KONVOI ENTKOMMEN", "Ansage: entkommen")

if failures == 0 then
	print("Konvoi in Ordnung")
end

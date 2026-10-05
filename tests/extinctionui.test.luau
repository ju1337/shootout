-- Oberfläche der offenen Welt (ExtinctionClient) im Simulator, zusammen mit dem Server: Hotbar zeigt die Tasche,
-- Anzeige SAFE ZONE / PVP IN / PVP AKTIV, Taste 1 benutzt Platz 1, TAB öffnet und schließt das Inventar,
-- anklicken und dann Zielplatz anklicken verschiebt, Stand per E öffnen und kaufen, Lager öffnen und hinüberlegen,
-- Tasche am Boden durchsuchen und alles nehmen – es darf nichts abstürzen und die Anzeigen müssen stimmen
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local Remotes = require("Remotes")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
local InputActions = require("InputActions")
ProgressService.Init()
WeaponService.Init()


local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
for _, name in { "Zone", "Spawns", "Portals", "Stands", "Places" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))
for name, offset in { Stand_Weapons = Vector3.new(-36, 2.5, 34), Stand_Items = Vector3.new(36, 2.5, 34),
	Stand_Vehicles = Vector3.new(-30, 2.5, -42), Stash = Vector3.new(52, 2.5, -30) } do
	local part = Instance.new("Part", map.Stands)
	part.Name = name
	part.CFrame = CFrame.new(CENTER + offset)
end

local town = Instance.new("Part", map.Places)
town.Name = "Place_Oedstadt"
town.Size = Vector3.new(200, 4, 200)
town.CFrame = CFrame.new(CENTER + Vector3.new(0, 2, 500))
town:SetAttribute("Title", "Ödstadt")

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
InventoryService.Init()
LootService.Init()
require("ExtinctionConfig").Airdrop.FirstDelay = math.huge -- hier keine Lootdrops (eigener Test: airdrop)
require("ExtinctionConfig").Day.Fixed = 12 -- immer Tag (nachts mehr Zombies; eigener Test: daycycle)
Extinction.Init({ Join = function() end, Status = function() end })

store.Data.u1 = { XP = {}, Coins = 4000, Rap = 0, Owned = {}, Equipped = {} }
local bob = SIM.Join("Bob")
Instance.new("Backpack", bob).Name = "Backpack"
SIM.Advance(2, 20)
bob:SetAttribute("Mode", "Extinction")
Extinction.AddPlayer(bob)
SIM.Advance(0.5, 20)

-- Client von Bob starten; Fernaufrufe in beide Richtungen weiterreichen
rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
local ExtinctionClient = require("ExtinctionClient")
ExtinctionClient.Init()
local seen = #SIM.RemoteLog
local function pump()
	while seen < #SIM.RemoteLog do
		seen += 1
		local entry = SIM.RemoteLog[seen]
		if entry.Player == "server" and entry.Remote == "ExtAction" then
			Remotes.ExtAction.OnServerEvent:Fire(bob, table.unpack(entry.Args, 1, entry.Args.n))
		elseif entry.Player == bob and entry.Remote == "ExtUpdate" then
			Remotes.ExtUpdate.OnClientEvent:Fire(table.unpack(entry.Args, 1, entry.Args.n))
		end
	end
end
local function step(seconds)
	local target = SIM.Now + (seconds or 0.5)
	while SIM.Now < target - 1e-6 do
		SIM.Advance(math.min(0.1, target - SIM.Now), 20)
		pump()
	end
end
local function find(root, name)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end
local function texts(root)
	local list = {}
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			table.insert(list, d.Text)
		end
	end
	return table.concat(list, " | ")
end
local function lastAction(kind)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Player == "server" and entry.Remote == "ExtAction" and entry.Args[1] == kind then
			return entry.Args
		end
	end
	return nil
end
step(1)

local hud = playerGui:FindFirstChild("ExtinctionHUD")
local windowGui = playerGui:FindFirstChild("ExtinctionWindow")
check(hud ~= nil and hud.Enabled, "HUD in der offenen Welt sichtbar")
check(windowGui ~= nil and not windowGui.Enabled, "kein Fenster offen")
local hotbar = hud and find(hud, "Hotbar")
check(hotbar ~= nil and #hotbar:GetChildren() == 9, "Hotbar mit 9 Plätzen")
check(string.find(texts(hud), "SAFE ZONE", 1, true) ~= nil, "Anzeige SAFE ZONE")
local missionPanel = find(hud, "Missions")
check(missionPanel ~= nil and missionPanel.Visible and string.find(texts(missionPanel), "AUFTRÄGE", 1, true) ~= nil,
	"Aufträge links im HUD")
local missionRows = 0
for _, child in missionPanel:GetChildren() do
	if child.Name == "Mission" then
		missionRows += 1
	end
end
check(missionRows == 3, "drei Auftragszeilen (" .. missionRows .. ")")
check(find(hud, "Clock") ~= nil and string.find(find(hud, "Clock").Text, "TAG", 1, true) ~= nil, "Uhrzeit oben rechts (Tag)")

-- Kaufen am Stand (E-Aufforderung des Clients)
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(-36, 3, 28)))
step(0.5)
local prompt = map.Stands.Stand_Weapons:FindFirstChildOfClass("ProximityPrompt")
check(prompt ~= nil and prompt.Enabled, "Stand hat eine E-Aufforderung")
prompt.Triggered:Fire(bob)
step(0.3)
check(windowGui.Enabled and string.find(texts(windowGui), "WAFFENSTAND", 1, true) ~= nil, "Waffenstand-Fenster offen")
local buyButton = nil
for _, d in windowGui:GetDescendants() do
	if d:IsA("TextLabel") and d.Text == "1100" then
		buyButton = d:FindFirstAncestorWhichIsA("TextButton")
	end
end
check(buyButton ~= nil, "Kaufknopf mit Preis 1100 (Sturmgewehr)")
if buyButton then
	buyButton.Activated:Fire()
end
step(0.5)
check(ProgressService.Get(bob).Coins == 2900, "Sturmgewehr gekauft (2900 Münzen übrig)")
check(string.find(texts(hud), "STURMGEWEHR", 1, true) ~= nil, "Hotbar zeigt das Sturmgewehr")
check(string.find(texts(windowGui), "2.900 MÜNZEN", 1, true) ~= nil, "Fenster zeigt die neuen Münzen")

-- Verkaufen: Platz in der Tasche anklicken, dann VERKAUFEN
local slotButton = find(windowGui, "Bag1")
check(slotButton ~= nil, "eigene Tasche im Standfenster")
slotButton.Activated:Fire()
step(0.2)
check(string.find(texts(windowGui), "VERKAUFEN", 1, true) ~= nil, "Verkaufen-Knopf erscheint")

-- Inventar mit TAB, Item verschieben (anklicken, Ziel anklicken)
InputActions.Trigger("Inventory", true)
InputActions.Trigger("Inventory", false)
step(0.2)
check(not windowGui.Enabled, "TAB schließt das offene Fenster")
InputActions.Trigger("Inventory", true)
InputActions.Trigger("Inventory", false)
step(0.2)
check(windowGui.Enabled and string.find(texts(windowGui), "INVENTAR", 1, true) ~= nil, "TAB öffnet das Inventar")
find(windowGui, "Bag1").Activated:Fire()
step(0.1)
check(string.find(texts(windowGui), "AUF DIE HOTBAR", 1, true) == nil and string.find(texts(windowGui), "IN DIE TASCHE", 1, true) ~= nil,
	"Details zum gewählten Item mit Aktionen")
find(windowGui, "Bag14").Activated:Fire()
step(0.3)
local move = lastAction("Move")
check(move and move[2] == "Bag" and move[3] == 1 and move[5] == 14, "Verschieben 1 -> 14 geschickt")
check(InventoryService.GetBag(bob).Slots[14] and InventoryService.GetBag(bob).Slots[14].Id == "Rifle", "Server hat verschoben")
check(string.find(texts(hud), "STURMGEWEHR", 1, true) == nil, "Hotbar wieder leer")

-- Taste 1 benutzt Platz 1
InputActions.Trigger("Hotbar1", true)
InputActions.Trigger("Hotbar1", false)
step(0.1)
check(lastAction("Use") and lastAction("Use")[2] == 1, "Taste 1 schickt Use(1)")

-- Draußen: PvP-Anzeige zählt herunter
InputActions.Trigger("Inventory", true)
InputActions.Trigger("Inventory", false)
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 150)))
step(1)
check(string.find(texts(hud), "PVP IN", 1, true) ~= nil, "Anzeige PVP IN ...")
step(5)
check(string.find(texts(hud), "PVP AKTIV", 1, true) ~= nil, "Anzeige PVP AKTIV")

-- Rote Zone und Lootdrop: Anzeige, Rand, Marker mit Entfernung
map:SetAttribute("Redzones", '[{"Name":"Werk","X":0,"Z":-5600,"R":60}]')
map:SetAttribute("Airdrops", '[{"Id":1,"X":100,"Y":0,"Z":-5900,"State":"Warning","Eta":' .. (workspace:GetServerTimeNow() + 30) .. ',"Zone":false}]')
step(0.3)
local markers = find(hud, "Markers")
check(markers ~= nil and markers:FindFirstChild("Marker1").Visible and markers:FindFirstChild("Marker2").Visible, "zwei Marker (Lootdrop, rote Zone)")
check(string.find(texts(markers), "LOOTDROP", 1, true) ~= nil and string.find(texts(markers), "ROTE ZONE  WERK", 1, true) ~= nil,
	"Marker nennen Lootdrop und rote Zone")
check(not markers:FindFirstChild("Marker3").Visible, "nur zwei Marker sichtbar")
-- Weltkarte (N): rote Zone als Kreis, Lootdrop als Raute, eigener Pfeil; nochmal N schließt
InputActions.Trigger("WorldMap", true)
InputActions.Trigger("WorldMap", false)
step(0.2)
local mapGui = playerGui:FindFirstChild("ExtinctionMap")
check(mapGui ~= nil and mapGui.Enabled, "N öffnet die Weltkarte")
check(mapGui and find(mapGui, "Redzone") ~= nil and find(mapGui, "Airdrop") ~= nil and find(mapGui, "Me").Visible,
	"Karte zeigt rote Zone, Lootdrop und den eigenen Standort")
check(mapGui and string.find(texts(mapGui), "LOOTDROP", 1, true) ~= nil, "Lootdrop mit Text auf der Karte")
InputActions.Trigger("WorldMap", true)
InputActions.Trigger("WorldMap", false)
step(0.2)
check(mapGui and not mapGui.Enabled, "N schließt die Weltkarte")

bob:SetAttribute("Redzone", "Werk")
step(0.3)
check(find(hud, "RedzoneVignette").Visible and string.find(texts(hud), "ROTE ZONE  ·  PVP AKTIV", 1, true) ~= nil,
	"in der roten Zone: roter Rand und Anzeige")
bob:SetAttribute("Redzone", nil)
step(0.3)
check(not find(hud, "RedzoneVignette").Visible, "draußen kein roter Rand")
map:SetAttribute("Redzones", nil)
map:SetAttribute("Airdrops", nil)
step(0.3)
check(not markers:FindFirstChild("Marker1").Visible, "ohne Daten keine Marker")

-- Ort betreten: Banner mit dem Namen, blendet wieder aus
local placeBanner = find(hud, "PlaceBanner")
check(placeBanner ~= nil and not placeBanner.Visible, "kein Banner draußen im Nichts")
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 500)))
step(0.4)
check(placeBanner.Visible and placeBanner.Text == "ÖDSTADT", "Banner nennt den Ort (" .. placeBanner.Text .. ")")
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 150)))
step(5)
check(not placeBanner.Visible, "Banner blendet wieder aus")

-- Tasche am Boden: durchsuchen, alles nehmen
local id = LootService.Create(bob.Character.HumanoidRootPart.Position + Vector3.new(2, 0, 0),
	{ { Id = "Bandage", Count = 2 }, { Id = "Ammo_9mm", Count = 15 } }, "Drop", "BEUTEL")
LootService.Open(bob, id)
step(0.3)
check(windowGui.Enabled and string.find(texts(windowGui), "BEUTEL", 1, true) ~= nil, "Taschen-Fenster offen")
local takeAll = nil
for _, d in windowGui:GetDescendants() do
	if d:IsA("TextLabel") and d.Text == "ALLES NEHMEN" then
		takeAll = d:FindFirstAncestorWhichIsA("TextButton")
	end
end
check(takeAll ~= nil, "Knopf ALLES NEHMEN")
if takeAll then
	takeAll.Activated:Fire()
end
step(0.5)
check(LootService.Get(id) == nil, "Tasche leer genommen und weg")
check(not windowGui.Enabled, "Fenster schließt, wenn die Tasche weg ist")
local hasBandage = false
for _, item in InventoryService.GetBag(bob).Slots do
	if item.Id == "Bandage" and item.Count == 2 then
		hasBandage = true
	end
end
check(hasBandage, "Verbände in Bobs Tasche")

-- Lager: nur in der Nähe, anklicken legt hinüber
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(52, 3, -24)))
step(0.5)
local stashPrompt = map.Stands.Stash:FindFirstChildOfClass("ProximityPrompt")
check(stashPrompt ~= nil, "Lager hat eine E-Aufforderung")
stashPrompt.Triggered:Fire(bob)
step(0.3)
check(windowGui.Enabled and string.find(texts(windowGui), "LAGER", 1, true) ~= nil, "Lager-Fenster offen")
find(windowGui, "Bag14").Activated:Fire()
step(0.5)
check(ProgressService.Get(bob).Extinction.Stash[1] and ProgressService.Get(bob).Extinction.Stash[1].Id == "Rifle",
	"Gewehr liegt im Lager")
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 0)))
step(0.5)
check(not windowGui.Enabled, "Weggehen schließt das Lager")

-- Modus verlassen: HUD weg
bob:SetAttribute("Mode", "Hub")
step(0.2)
check(not hud.Enabled, "HUD außerhalb der offenen Welt aus")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

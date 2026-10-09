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
local UITheme = require("UITheme")
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
	Stand_Vehicles = Vector3.new(-30, 2.5, -42), Stash = Vector3.new(52, 2.5, -30), Stand_Market = Vector3.new(24, 2.5, 40) } do
	local part = Instance.new("Part", map.Stands)
	part.Name = name
	part.CFrame = CFrame.new(CENTER + offset)
end
local travelStop = Instance.new("Part", map.Stands)
travelStop.Name = "Travel"
travelStop.CFrame = CFrame.new(CENTER + Vector3.new(-36, 2.5, 16))
local house = Instance.new("Part", map.Zone)
house.Name = "SafeZone_Nord"
house:SetAttribute("Title", "SAFEHOUSE NORD")
house.Size = Vector3.new(88, 80, 88)
house.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 700))
local houseSpawns = Instance.new("Folder", map)
houseSpawns.Name = "Spawns_Nord"
Instance.new("Part", houseSpawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 710))

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
require("ExtinctionConfig").Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
require("ExtinctionConfig").HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
require("ExtinctionConfig").Day.Fixed = 12 -- immer Tag (nachts mehr Zombies; eigener Test: daycycle)
require("ExtinctionConfig").Zombies.KindWeights = { Walker = 1 } -- nur normale Zombies (Schreier rufen sonst Verstärkung)
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

-- Symbole über allen Ständen, dem Lager und der Haltestelle: Scheibe mit Symbol und kurzem Namen, nur in der Safe Zone
local BUBBLE_WANT = {
	Stand_Weapons = { "Rifle", "WAFFEN" },
	Stand_Items = { "Medkit", "APOTHEKE" },
	Stand_Vehicles = { "V_Pickup", "FAHRZEUGE" },
	Stand_Market = { "Coins", "TAUSCHMARKT" },
	Stash = { "Crate", "LAGER" },
	Travel = { "Route", "REISEN" },
}
bob:SetAttribute("InSafeZone", true)
step(0.2)
for name, want in BUBBLE_WANT do
	local part = map.Stands:FindFirstChild(name)
	local bubble = part and part:FindFirstChild("StandBubble")
	check(bubble ~= nil and bubble:IsA("BillboardGui") and bubble.Enabled, name .. ": Symbol über dem Stand in der Safe Zone")
	if bubble then
		local icon = find(bubble, "Icon_" .. want[1])
		check(icon ~= nil and #icon:GetDescendants() > 0, name .. ": Symbol " .. want[1])
		local label = find(bubble, "Label")
		check(label ~= nil and label.Text == want[2], name .. ": Name " .. want[2])
		check(find(bubble, "Disc") ~= nil, name .. ": Scheibe")
		check(bubble.Size.X.Offset <= 160 and bubble.Size.Y.Offset <= 80, name .. ": schlicht, nicht riesig")
		check(bubble.StudsOffset.Y > 15 and bubble.MaxDistance >= 150 and not bubble.AlwaysOnTop,
			name .. ": hoch über dem Dach, von weitem sichtbar, Wände verdecken")
	end
end
bob:SetAttribute("InSafeZone", false)
step(0.2)
local weapons = map.Stands:FindFirstChild("Stand_Weapons")
check(weapons ~= nil and not weapons.StandBubble.Enabled, "außerhalb der Safe Zone keine Symbole")
bob:SetAttribute("InSafeZone", true)
step(0.2)
check(weapons ~= nil and weapons.StandBubble.Enabled, "zurück in der Safe Zone wieder Symbole")
local rifleIcon = find(map.Stands.Stand_Weapons.StandBubble, "Icon_Rifle")
check(rifleIcon and rifleIcon:FindFirstChildWhichIsA("ViewportFrame", true) == nil and #rifleIcon:GetChildren() >= 4,
	"Waffensymbol flach gezeichnet (kein 3D-Modell, das auf der dunklen Scheibe verschwindet)")
local disc = find(map.Stands.Stand_Weapons.StandBubble, "Disc")
local corner = disc and disc:FindFirstChildWhichIsA("UICorner")
check(corner ~= nil and corner.CornerRadius.Scale == 0.5, "Scheibe ist rund")
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

-- Eine Tastenzeile unter der Hotbar (die allgemeine des HUD ist in der offenen Welt aus)
local hintText = find(hud, "Hints") and find(hud, "Hints").Text or ""
check(string.find(hintText, "LMB  SCHIESSEN", 1, true) ~= nil and string.find(hintText, "1-9  BENUTZEN", 1, true) ~= nil
	and string.find(hintText, "TAB  INVENTAR", 1, true) ~= nil and string.find(hintText, "E  INTERAGIEREN", 1, true) ~= nil
	and string.find(hintText, "K  FAHRZEUG EINPACKEN", 1, true) ~= nil and string.find(hintText, "N  KARTE", 1, true) ~= nil,
	"Tastenzeile unter der Hotbar (" .. hintText .. ")")
-- Controller: R1/L1 wechseln die Waffe, □ lädt nach oder interagiert (eine Angabe für beides)
local UserInputService = game:GetService("UserInputService")
InputActions.Init()
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
step(0.1)
hintText = find(hud, "Hints").Text
check(string.find(hintText, "R2  SCHIESSEN", 1, true) ~= nil and string.find(hintText, "□  NACHLADEN / INTERAGIEREN", 1, true) ~= nil
	and string.find(hintText, "R1 / L1  WAFFE", 1, true) ~= nil and select(2, string.gsub(hintText, "□", "")) == 1,
	"Controller-Tastenzeile (" .. hintText .. ")")
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
step(0.1)
check(string.find(find(hud, "Hints").Text, "1-9  BENUTZEN", 1, true) ~= nil, "zurück auf Tastatur")

-- Aufträge stehen mit Abstand unter dem VERLASSEN-Knopf des HUD und rutschen mit ihm (hier ein nachgebautes HUD)
local fakeHud = Instance.new("ScreenGui", playerGui)
fakeHud.Name = "HUD"
local fakeRoot = Instance.new("Frame", fakeHud)
fakeRoot.Name = "Root"
local fakeLeave = Instance.new("TextButton", fakeRoot)
fakeLeave.Name = "LeaveButton"
fakeLeave.Position = UDim2.new(0, 48, 0, 278)
fakeLeave.Size = UDim2.new(0, 152, 0, 30)
local fakeVitals = Instance.new("Frame", fakeRoot) -- PC: Lebensanzeige unten links, zählt nicht
fakeVitals.Name = "Vitals"
fakeVitals.AnchorPoint = Vector2.new(0, 1)
fakeVitals.Position = UDim2.new(0, 24, 1, -24)
fakeVitals.Size = UDim2.new(0, 330, 0, 88)
step(0.2)
check(missionPanel.Position.Y.Offset == 278 + 30 + 24, "Aufträge 24 unter VERLASSEN (" .. missionPanel.Position.Y.Offset .. ")")
fakeLeave.Position = UDim2.new(0, 48, 0, 320)
step(0.2)
check(missionPanel.Position.Y.Offset == 320 + 30 + 24, "Aufträge rutschen mit dem Knopf (" .. missionPanel.Position.Y.Offset .. ")")
fakeLeave.Position = UDim2.new(0, 188, 0, 58) -- Touch: VERLASSEN neben der Minimap, Lebensanzeige darunter
fakeVitals.AnchorPoint = Vector2.new(0, 0)
fakeVitals.Position = UDim2.new(0, 16, 0, 230)
step(0.2)
check(missionPanel.Position.Y.Offset == 230 + 88 + 24, "Touch: Aufträge unter der Lebensanzeige (" .. missionPanel.Position.Y.Offset .. ")")
fakeHud:Destroy()

-- Rangliste rechts oben: nur in der roten Zone zu sehen
local board = find(hud, "RedzoneBoard")
check(board ~= nil and not board.Visible, "außerhalb der roten Zone keine Rangliste")
local zoneLine = find(hud, "RedzoneInfo")
check(board and board.Position.Y.Offset >= zoneLine.Position.Y.Offset + zoneLine.Size.Y.Offset
	and board.AnchorPoint.X == 1 and board.Position.X.Scale == 1, "Rangliste rechts oben unter Uhr und Zeile der roten Zone")

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
check(string.find(texts(windowGui), "2,900 MÜNZEN", 1, true) ~= nil or string.find(texts(windowGui), "2.900 MÜNZEN", 1, true) ~= nil, "Fenster zeigt die neuen Münzen")

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
check(find(windowGui, "Safe1") ~= nil and find(windowGui, "Safe" .. require("ExtinctionConfig").SafeSlots) ~= nil
	and string.find(texts(windowGui), "CONTAINER", 1, true) ~= nil, "Inventar zeigt den Container mit allen Plätzen")
check(find(windowGui, "Sidebar") ~= nil and find(windowGui, "Filter_Weapon") ~= nil, "Seitenleiste und Filter")
find(windowGui, "Bag1").Activated:Fire()
step(0.1)
check(string.find(texts(windowGui), "AUF DIE HOTBAR", 1, true) == nil and string.find(texts(windowGui), "IN DIE TASCHE", 1, true) ~= nil,
	"Details zum gewählten Item mit Aktionen")
check(find(windowGui, "ItemPopup") and find(windowGui, "ItemPopup").Visible and find(windowGui, "AttSlot_Muzzle") ~= nil
	and find(windowGui, "AttSlot_Magazine") ~= nil, "Info-Fenster der Waffe mit Aufsatz-Plätzen")
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

-- Rote Zone und Lootdrop: keine Richtungsanzeiger; die rote Zone (zieht alle 20 Minuten weiter) als Zeile unter der Uhr
-- mit Ort, Zeit bis zum Wechsel und Entfernung
local zoneLine0 = zoneLine.Visible
map:SetAttribute("Redzones", '[{"Name":"Redzone","Title":"Nordheim","X":0,"Z":-5000,"R":170,"Ends":'
	.. (workspace:GetServerTimeNow() + 125) .. '}]')
map:SetAttribute("Airdrops", '[{"Id":1,"X":100,"Y":0,"Z":-5900,"State":"Warning","Eta":' .. (workspace:GetServerTimeNow() + 30) .. ',"Zone":false}]')
step(0.3)
local markers = find(hud, "Markers")
check(markers ~= nil and not markers.Visible, "keine Richtungsanzeiger mit Entfernung (Lootdrop, rote Zone)")
check(not zoneLine0 and zoneLine.Visible and string.find(zoneLine.Text, "ROTE ZONE  NORDHEIM  ·  WECHSEL IN 2:0", 1, true) ~= nil
	and string.find(zoneLine.Text, " M", 1, true) ~= nil, "rote Zone unter der Uhr: " .. zoneLine.Text)
check(zoneLine.TextColor3 == Color3.fromRGB(226, 56, 48), "Zeile in Rot")
-- Weltkarte (N): rote Zone als Kreis, Lootdrop als Raute, eigener Pfeil; nochmal N schließt.
-- Tankstellen und Seen ohne Namen (zu unübersichtlich), die Seen bleiben als Fläche
for key, title in { Tank0 = "Tankstelle", Teich = "Mühlteich" } do
	local part = Instance.new("Part", map.Places)
	part.Name = "Place_" .. key
	part:SetAttribute("Title", title)
	part.Size = Vector3.new(90, 4, 90)
	part.CFrame = CFrame.new(CENTER + Vector3.new(900, 2, -900))
end
local lakes = Instance.new("Folder", map)
lakes.Name = "Lakes"
local lake = Instance.new("Part", lakes)
lake.Name = "Lake_Teich"
lake.Size = Vector3.new(120, 1, 120)
lake.CFrame = CFrame.new(CENTER + Vector3.new(900, 0, -900))
InputActions.Trigger("WorldMap", true)
InputActions.Trigger("WorldMap", false)
step(0.2)
local mapGui = playerGui:FindFirstChild("ExtinctionMap")
check(mapGui ~= nil and mapGui.Enabled, "N öffnet die Weltkarte")
check(mapGui and find(mapGui, "Place_Oedstadt") ~= nil and string.find(texts(mapGui), "ÖDSTADT", 1, true) ~= nil, "Ortsname auf der Karte")
check(mapGui and find(mapGui, "Place_Tank0") == nil and find(mapGui, "Place_Teich") == nil
	and string.find(texts(mapGui), "TANKSTELLE", 1, true) == nil and string.find(texts(mapGui), "TEICH", 1, true) == nil,
	"keine Namen für Tankstellen und Seen")
check(mapGui and find(mapGui, "Lake") ~= nil, "See als Fläche auf der Karte")
check(mapGui and find(mapGui, "Redzone") ~= nil and find(mapGui, "Airdrop") ~= nil and find(mapGui, "Me").Visible,
	"Karte zeigt rote Zone, Lootdrop und den eigenen Standort")
check(mapGui and string.find(texts(mapGui), "ROTE ZONE 2:0", 1, true) ~= nil, "rote Zone mit Zeit bis zum Wechsel auf der Karte")
check(mapGui and string.find(texts(mapGui), "WANDERZONE", 1, true) == nil, "keine Wanderzone mehr in der Legende")
-- die Zone zieht weiter: Kreis am neuen Ort
local circleBefore = find(mapGui, "Redzone")
map:SetAttribute("Redzones", '[{"Name":"Redzone","Title":"Altenfeld","X":-1150,"Z":-6250,"R":170,"Ends":'
	.. (workspace:GetServerTimeNow() + 1200) .. '}]')
step(0.2)
local circleAfter = find(mapGui, "Redzone")
check(circleAfter ~= nil and circleAfter ~= circleBefore and circleAfter.Position.X.Scale < 0.3, "Kreis zieht mit")
local circles = 0
for _, d in mapGui:GetDescendants() do
	if d.Name == "Redzone" then
		circles += 1
	end
end
check(circles == 1, "nur ein Kreis für die rote Zone (" .. circles .. ")")
check(mapGui and string.find(texts(mapGui), "LOOTDROP", 1, true) ~= nil, "Lootdrop mit Text auf der Karte")
InputActions.Trigger("WorldMap", true)
InputActions.Trigger("WorldMap", false)
step(0.2)
check(mapGui and not mapGui.Enabled, "N schließt die Weltkarte")

-- Rangliste: nur in der roten Zone, deren Top 3 dieser Runde und der eigene Platz darunter (eigener Name in den Top 3
-- hervorgehoben); jede Runde (neuer Ort) beginnt leer
local savedBoard = map:GetAttribute("RedzoneBoard")
local me = tostring(bob.UserId)
map:SetAttribute("RedzoneBoard", '{"Zones":{"Redzone":{"Title":"Chemiewerk","List":[{"Id":11,"Name":"Ann","Kills":5},'
	.. '{"Id":12,"Name":"Ben","Kills":3},{"Id":13,"Name":"Cem","Kills":2},{"Id":' .. me .. ',"Name":"Bob","Kills":1}]}}}')
step(0.2)
check(not board.Visible, "draußen bleibt die Rangliste aus, auch mit Kills")
bob:SetAttribute("Redzone", "Redzone")
step(0.3)
check(find(hud, "RedzoneVignette").Visible and string.find(texts(hud), "ROTE ZONE  ·  PVP AKTIV", 1, true) ~= nil,
	"in der roten Zone: roter Rand und Anzeige")
check(string.find(texts(board), "ROTE ZONE  ·  TOP KILLS", 1, true) ~= nil and string.find(texts(board), "CHEMIEWERK", 1, true) ~= nil,
	"Rangliste der Zone mit ihrem Namen: " .. texts(board))
check(find(board, "Top1").Player.Text == "Ann" and find(board, "Top1").Kills.Text == "5" and find(board, "Top2").Player.Text == "Ben"
	and find(board, "Top3").Player.Text == "Cem" and find(board, "Top3").Kills.Text == "2", "Top 3 der Zone")
local own = find(board, "Own")
check(own.Visible and own.Player.Text == "DU  ·  PLATZ 4" and own.Kills.Text == "1" and board.Size.Y.Offset > 120,
	"eigener Platz unter den Top 3 (" .. own.Player.Text .. ")")
map:SetAttribute("RedzoneBoard", '{"Zones":{"Redzone":{"Title":"Nordheim","List":[{"Id":' .. me
	.. ',"Name":"Bob","Kills":4},{"Id":11,"Name":"Ann","Kills":2}]}}}')
step(0.2)
local top1 = find(board, "Top1")
check(board.Visible and string.find(texts(board), "ROTE ZONE  ·  TOP KILLS", 1, true) ~= nil
	and string.find(texts(board), "NORDHEIM", 1, true) ~= nil, "Rangliste mit neuem Stand: " .. texts(board))
check(top1.Player.Text == "Bob" and top1.Kills.Text == "4" and top1.Player.TextColor3 == UITheme.Colors.Primary
	and find(board, "Top2").Player.Text == "Ann" and find(board, "Top3").Player.Text == "—" and not own.Visible,
	"eigener Name vorn und hervorgehoben, leerer Platz 3 (" .. top1.Player.Text .. " " .. top1.Kills.Text .. ")")
map:SetAttribute("RedzoneBoard", '{"Zones":{"Redzone":{"Title":"Altenfeld","List":[]}}}') -- nächste Runde: leer
step(0.2)
check(string.find(texts(board), "ALTENFELD", 1, true) ~= nil and find(board, "Top1").Player.Text == "—"
	and find(board, "Top1").Kills.Text == "", "neue Runde: leere Liste mit dem neuen Ort")
map:SetAttribute("RedzoneBoard", savedBoard)
bob:SetAttribute("Redzone", nil)
step(0.3)
check(not find(hud, "RedzoneVignette").Visible, "draußen kein roter Rand")
check(not board.Visible, "Zone verlassen: Rangliste weg")
map:SetAttribute("Redzones", nil)
map:SetAttribute("Airdrops", nil)
step(0.3)
check(not markers:FindFirstChild("Marker1").Visible, "ohne Daten keine Marker")
check(not zoneLine.Visible, "ohne rote Zone keine Zeile unter der Uhr")

-- Ort betreten: Banner mit dem Namen, blendet wieder aus
local placeBanner = find(hud, "PlaceBanner")
check(placeBanner ~= nil and not placeBanner.Visible, "kein Banner draußen im Nichts")
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 500)))
step(0.4)
local placeTitle = find(placeBanner, "PlaceTitle")
check(placeBanner.Visible and placeTitle.Text == "ÖDSTADT", "Banner nennt den Ort (" .. placeTitle.Text .. ")")
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(0, 3, 150)))
step(5)
check(not placeBanner.Visible, "Banner blendet wieder aus")

-- Tasche am Boden: durchsuchen, einzeln nehmen; ALLES NEHMEN (und F) nur mit dem Gamepass ALLES LOOTEN
local id = LootService.Create(bob.Character.HumanoidRootPart.Position + Vector3.new(2, 0, 0),
	{ { Id = "Bandage", Count = 2 }, { Id = "Ammo_9mm", Count = 15 } }, "Drop", "BEUTEL")
step(0.1)
local bagPart = LootService.Get(id).Part
check(bagPart.TakeAllPrompt.Enabled == false, "ohne Gamepass kein F-Prompt (nur bei Bob)")
LootService.Open(bob, id)
step(0.3)
check(windowGui.Enabled and string.find(texts(windowGui), "BEUTEL", 1, true) ~= nil, "Taschen-Fenster offen")
local function takeAllButton()
	for _, d in windowGui:GetDescendants() do
		if d:IsA("TextLabel") and string.sub(d.Text, 1, 12) == "ALLES NEHMEN" then
			return d:FindFirstAncestorWhichIsA("TextButton"), d.Text
		end
	end
	return nil, nil
end
local takeAll, takeAllText = takeAllButton()
check(takeAll ~= nil and takeAllText == "ALLES NEHMEN · GAMEPASS", "ohne Gamepass: Knopf führt zum Gamepass ("
	.. tostring(takeAllText) .. ")")
local logBefore = #SIM.RemoteLog
if takeAll then
	takeAll.Activated:Fire()
end
step(0.3)
local sentAll = false
for i = logBefore + 1, #SIM.RemoteLog do
	local entry = SIM.RemoteLog[i]
	if entry.Remote == "ExtAction" and entry.Args[1] == "Loot" and entry.Args[3] == "All" then
		sentAll = true
	end
end
check(not sentAll and LootService.Get(id) ~= nil, "ohne Gamepass: nichts auf einmal genommen")
check(string.find(texts(hud), "ALLES LOOTEN", 1, true) ~= nil, "Hinweis auf den Gamepass")
-- einzeln: Verband anklicken
find(windowGui, "Loot1").Activated:Fire()
step(0.3)
local function bobHas(itemId, count)
	for _, item in InventoryService.GetBag(bob).Slots do
		if item.Id == itemId and item.Count == count then
			return true
		end
	end
	return false
end
check(bobHas("Bandage", 2) and LootService.Get(id) ~= nil, "einzeln genommen: Verbände in Bobs Tasche, Munition bleibt liegen")
-- Gamepass gekauft: Knopf und F-Prompt gehen sofort
bob:SetAttribute("Pass_LootAll", true)
step(0.2)
takeAll, takeAllText = takeAllButton()
check(takeAllText == "ALLES NEHMEN" and bagPart.TakeAllPrompt.Enabled, "mit Gamepass: ALLES NEHMEN und F-Prompt")
local ammoBefore = require("Inventory").Count(InventoryService.GetBag(bob), "Ammo_9mm")
if takeAll then
	takeAll.Activated:Fire()
end
step(0.5)
check(LootService.Get(id) == nil, "Tasche leer genommen und weg")
check(not windowGui.Enabled, "Fenster schließt, wenn die Tasche weg ist")
check(require("Inventory").Count(InventoryService.GetBag(bob), "Ammo_9mm") == ammoBefore + 15, "Munition in Bobs Tasche")
bob:SetAttribute("Pass_LootAll", nil)

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

-- Reisen: Haltestelle -> Fenster mit den Safe Zones -> Klick reist dorthin
bob.Character:PivotTo(CFrame.new(CENTER + Vector3.new(-36, 3, 12)))
step(0.5)
local travelPrompt = map.Stands.Travel:FindFirstChildOfClass("ProximityPrompt")
check(travelPrompt ~= nil, "Haltestelle hat eine E-Aufforderung")
travelPrompt.Triggered:Fire(bob)
step(0.3)
check(windowGui.Enabled and string.find(texts(windowGui), "REISEN", 1, true) ~= nil, "Reise-Fenster offen")
check(string.find(texts(windowGui), "CAMP PHOENIX  ·  DU BIST HIER", 1, true) ~= nil, "Camp als aktueller Ort")
check(string.find(texts(windowGui), "SAFEHOUSE NORD", 1, true) ~= nil, "Safehouse in der Liste")
find(windowGui, "Travel_Nord").Activated:Fire()
step(0.5)
local bobRoot = bob.Character:FindFirstChild("HumanoidRootPart")
check(bobRoot and (bobRoot.Position - (CENTER + Vector3.new(0, 0, 710))).Magnitude < 12, "Klick reist ins Safehouse")
check(not windowGui.Enabled, "Fenster danach zu")

-- Anti-Zombie-Spritze wirkt: Zeile unter der Zonen-Anzeige mit Restzeit
local shield = find(hud, "ZombieShield")
check(shield ~= nil and not shield.Visible, "ohne Spritze keine Anzeige")
bob.Character:SetAttribute("ZombieShieldUntil", workspace:GetServerTimeNow() + 95)
step(0.2)
check(shield and shield.Visible and string.find(texts(shield), "ANTI-ZOMBIE-SPRITZE  1:3", 1, true) ~= nil
	and string.find(texts(shield), "KEINE ZOMBIES", 1, true) ~= nil, "Spritze wirkt: Restzeit (" .. (shield and texts(shield) or "") .. ")")
bob.Character:SetAttribute("ZombieShieldUntil", workspace:GetServerTimeNow() - 1)
step(0.2)
check(shield and not shield.Visible, "abgelaufen: Anzeige weg")
-- Spritze in der Tasche: eigenes Symbol
InventoryService.Give(bob, "AntiZombie", 1)
step(0.3)
check(string.find(texts(hud), "ANTI-ZOMBIE-SPRITZE", 1, true) ~= nil or string.find(texts(hud), "SPRITZE", 1, true) ~= nil,
	"Spritze auf der Hotbar")

-- ---------- Squad: J öffnet das Fenster, Einladen, Einladung annehmen, Liste im HUD, Squad = Team ----------
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local ann = SIM.Join("Ann")
Instance.new("Backpack", ann).Name = "Backpack"
step(2)
ann:SetAttribute("Mode", "Extinction")
Extinction.AddPlayer(ann)
step(0.5)
local function lastParty(kind)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Player == "server" and entry.Remote == "PartyAction" and entry.Args[1] == kind then
			return entry.Args
		end
	end
	return nil
end
check(find(hud, "SquadButton") ~= nil and string.find(texts(find(hud, "SquadButton")), "SQUAD", 1, true) ~= nil, "Knopf SQUAD im HUD")
check(string.find(find(hud, "Hints").Text, "J  SQUAD", 1, true) ~= nil, "Tastenzeile: J SQUAD")
InputActions.Trigger("Squad", true)
InputActions.Trigger("Squad", false)
step(0.2)
check(windowGui.Enabled and string.find(texts(windowGui), "SQUAD", 1, true) ~= nil, "J öffnet das Squad-Fenster")
check(string.find(texts(windowGui), "DU SPIELST ALLEIN", 1, true) ~= nil, "allein: Hinweis")
local players = find(windowGui, "SquadPlayers")
check(players and string.find(texts(players), "ANN", 1, true) ~= nil, "Ann steht in der Liste der Spieler")
local invite = players and find(players, "Invite")
check(invite ~= nil, "Knopf EINLADEN")
if invite then
	invite.Activated:Fire()
	step(0.1)
end
local sent = lastParty("Invite")
check(sent and sent[2] == ann.UserId, "Einladung an Ann geschickt")
-- Einladung von Ann: Hinweis, im Fenster annehmen
Remotes.PartyInvite.OnClientEvent:Fire("Ann", ann.UserId)
step(0.2)
check(string.find(texts(windowGui), "EINLADUNG VON ANN", 1, true) ~= nil, "Einladung im Squad-Fenster")
local accept = find(windowGui, "AcceptInvite")
check(accept ~= nil, "Knopf ANNEHMEN")
if accept then
	accept.Activated:Fire()
	step(0.1)
end
local accepted = lastParty("Accept")
check(accepted and accepted[2] == ann.UserId, "Annahme an den Server geschickt")
InputActions.Trigger("Squad", true)
InputActions.Trigger("Squad", false)
step(0.2)
check(not windowGui.Enabled, "J schließt das Squad-Fenster")
-- im Squad (so setzt es der PartyService): Liste im HUD, Ann ist Teamkollegin
local TeamCheck = require("TeamCheck")
local HttpService = game:GetService("HttpService")
check(not TeamCheck.IsSquadMate(ann) and TeamCheck.IsEnemy(ann.Character), "ohne Squad ist Ann eine Gegnerin")
local partyData = HttpService:JSONEncode({ Leader = ann.UserId, Members = { { UserId = ann.UserId, Name = "Ann" },
	{ UserId = bob.UserId, Name = "Bob" } } })
for _, member in { ann, bob } do
	member:SetAttribute("Party", partyData)
	member:SetAttribute("SquadId", 7)
end
ann.Character:PivotTo(CFrame.new(bob.Character:GetPivot().Position + Vector3.new(80, 0, 0))) -- draußen vor dem Safehouse
step(0.5)
local squadPanel = find(hud, "Squad")
check(squadPanel and squadPanel.Visible and string.find(texts(squadPanel), "ANN", 1, true) ~= nil, "Squad-Liste im HUD mit Ann")
check(squadPanel and string.find(texts(squadPanel), "80 M", 1, true) ~= nil, "Entfernung zu Ann (" .. (squadPanel and texts(squadPanel) or "") .. ")")
check(string.find(texts(find(hud, "SquadButton")), "2/4", 1, true) ~= nil, "Knopf zeigt 2/4")
check(TeamCheck.IsSquadMate(ann) and TeamCheck.Relation("Ann") == "Mate" and not TeamCheck.IsEnemy(ann.Character),
	"im Squad ist Ann Teamkollegin")
local mateListed = false
for _, fighter in TeamCheck.Fighters() do
	if fighter.Name == "Ann" and fighter.IsMate then
		mateListed = true
	end
end
check(mateListed, "Ann als Teamkollegin für die Minimap")
InputActions.Trigger("Squad", true)
InputActions.Trigger("Squad", false)
step(0.2)
local members = find(windowGui, "SquadMembers")
check(members and string.find(texts(members), "★  ANN", 1, true) ~= nil and find(windowGui, "LeaveSquad").Visible,
	"Fenster: Ann als Anführerin, VERLASSEN sichtbar")
check(find(members, "Kick") == nil, "nur die Anführerin kann entfernen")
find(windowGui, "LeaveSquad").Activated:Fire()
step(0.1)
check(lastParty("Leave") ~= nil, "Verlassen an den Server geschickt")
InputActions.Trigger("Squad", true)
InputActions.Trigger("Squad", false)
step(0.2)
for _, member in { ann, bob } do
	member:SetAttribute("Party", nil)
	member:SetAttribute("SquadId", nil)
end
step(0.3)
check(not find(hud, "Squad").Visible and not TeamCheck.IsSquadMate(ann), "Squad aufgelöst: Liste weg, Ann wieder Gegnerin")

-- Modus verlassen: HUD und Blasen weg
bob:SetAttribute("Mode", "Hub")
step(0.2)
check(not hud.Enabled, "HUD außerhalb der offenen Welt aus")
check(not map.Stands.Stand_Weapons.StandBubble.Enabled and not map.Stands.Travel.StandBubble.Enabled,
	"Blasen außerhalb der offenen Welt aus")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

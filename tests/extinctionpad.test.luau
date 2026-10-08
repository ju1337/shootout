-- Controller in der offenen Welt (ExtinctionClient): dieselben Tasten tragen angetippt und gehalten zwei Aktionen
--   Steuerkreuz oben: antippen = Ping, halten = Weltkarte
--   Select:           antippen = Inventar, halten = Squad
--   △:                antippen = heilen (Heil-Item aus der Hotbar), halten = Fahrzeug einpacken
-- Heilen wählt das Medikit, wenn mindestens 50 Leben fehlen, sonst den Verband, sonst irgendein Heil-Item der Hotbar;
-- ohne Heil-Item in der Hotbar kommt eine Meldung. Außerhalb der offenen Welt gelten wieder die normalen Belegungen.
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
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
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

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local ExtinctionConfig = require("ExtinctionConfig")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Horde.Enabled = false -- keine Horden-Kiste (eigener Test: horde)
ExtinctionConfig.HeliCrash.Enabled = false -- kein Heli-Absturz (eigener Test: helicrash)
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0
ExtinctionConfig.Redzone.Enabled = false
Extinction.Init({ Join = function() end, Status = function() end })

store.Data.u1 = { XP = {}, Coins = 4000, Rap = 0, Owned = {}, Equipped = {} }
local bob = SIM.Join("Bob")
Instance.new("Backpack", bob).Name = "Backpack"
SIM.Advance(2, 20)
bob:SetAttribute("Mode", "Extinction")
Extinction.AddPlayer(bob)
SIM.Advance(0.5, 20)

-- Client von Bob starten (Fernaufrufe an den Server werden hier nur mitgelesen, nicht ausgeführt)
rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
local ExtinctionClient = require("ExtinctionClient")
InputActions.Init()
ExtinctionClient.Init()
local function step(seconds)
	SIM.Advance(seconds or 0.2, 20)
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
local function actionsSince(mark, kind)
	local list = {}
	for i = mark + 1, #SIM.RemoteLog do
		local entry = SIM.RemoteLog[i]
		if entry.Player == "server" and entry.Remote == "ExtAction" and entry.Args[1] == kind then
			table.insert(list, entry.Args)
		end
	end
	return list
end
local function pad(keyCode)
	return { KeyCode = keyCode, UserInputType = Enum.UserInputType.Gamepad1 }
end
-- Controller-Taste kurz antippen bzw. lange halten (danach loslassen)
local function tap(keyCode)
	local input = pad(keyCode)
	UserInputService.InputBegan:Fire(input, false)
	step(0.1)
	UserInputService.InputEnded:Fire(input, false)
	step(0.1)
end
local function hold(keyCode)
	local input = pad(keyCode)
	UserInputService.InputBegan:Fire(input, false)
	step(InputActions.HoldTime + 0.15)
	UserInputService.InputEnded:Fire(input, false)
	step(0.1)
end
local pings = 0
InputActions.Bind("Ping", function(began)
	if began then
		pings += 1
	end
end)
step(1)

local hud = playerGui:FindFirstChild("ExtinctionHUD")
local windowGui = playerGui:FindFirstChild("ExtinctionWindow")
local mapGui = playerGui:FindFirstChild("ExtinctionMap")
check(hud ~= nil and hud.Enabled and windowGui ~= nil and mapGui ~= nil, "HUD, Fenster und Karte angelegt")

-- ---------- Belegung in der offenen Welt ----------
local B = InputActions.Bindings
local function holdCode(action)
	return B[action] and B[action].PadHold and B[action].PadHold[1]
end
check(holdCode("WorldMap") == Enum.KeyCode.DPadUp, "Weltkarte: Steuerkreuz oben halten")
check(holdCode("Squad") == Enum.KeyCode.ButtonSelect, "Squad: Select halten")
check(holdCode("StoreVehicle") == Enum.KeyCode.ButtonY, "Fahrzeug einpacken: △ halten")
check(B.QuickHeal and B.QuickHeal.Pad[1] == Enum.KeyCode.ButtonY, "Heilen: △ antippen")
check(B.Ping.Pad[1] == Enum.KeyCode.DPadUp and #B.WorldMap.Pad == 0, "Steuerkreuz oben angetippt bleibt Ping")
check(B.Inventory.Pad[1] == Enum.KeyCode.ButtonSelect and #B.Squad.Pad == 0, "Select angetippt bleibt Inventar")
check(#B.StoreVehicle.Pad == 0, "Fahrzeug einpacken nicht mehr auf △ antippen")
check(B.WorldMap.Keys[1] == Enum.KeyCode.N and B.Squad.Keys[1] == Enum.KeyCode.J and B.StoreVehicle.Keys[1] == Enum.KeyCode.K,
	"Tastatur unverändert (N, J, K)")

-- Tastenzeile auf dem Controller
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
step(0.1)
local hintText = find(hud, "Hints").Text
for _, want in { "△  HEILEN", "TOUCH  INVENTAR", "△ HALTEN  FAHRZEUG EINPACKEN", "↑ HALTEN  KARTE", "TOUCH HALTEN  SQUAD" } do
	check(string.find(hintText, want, 1, true) ~= nil, "Controller-Tastenzeile enthält '" .. want .. "' (" .. hintText .. ")")
end
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
step(0.1)
hintText = find(hud, "Hints").Text
check(string.find(hintText, "HEILEN", 1, true) == nil and string.find(hintText, "HALTEN", 1, true) == nil
	and string.find(hintText, "N  KARTE", 1, true) ~= nil, "Tastatur: kein HEILEN/HALTEN (" .. hintText .. ")")
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
step(0.1)

-- ---------- echte Controller-Eingaben ----------
-- Steuerkreuz oben: angetippt Ping (Karte bleibt zu), gehalten Karte (ohne Ping)
tap(Enum.KeyCode.DPadUp)
check(pings == 1 and not mapGui.Enabled, "↑ angetippt: Ping, keine Karte")
hold(Enum.KeyCode.DPadUp)
check(mapGui.Enabled and pings == 1, "↑ gehalten: Weltkarte, kein Ping")
hold(Enum.KeyCode.DPadUp)
check(not mapGui.Enabled, "↑ nochmal gehalten: Karte zu")

-- Select: angetippt Inventar, gehalten Squad
tap(Enum.KeyCode.ButtonSelect)
check(windowGui.Enabled and string.find(texts(windowGui), "INVENTAR", 1, true) ~= nil, "Select angetippt: Inventar")
tap(Enum.KeyCode.ButtonSelect)
check(not windowGui.Enabled, "Select angetippt: Inventar zu")
hold(Enum.KeyCode.ButtonSelect)
local menuTitle = windowGui:FindFirstChild("Title", true)
check(windowGui.Enabled and menuTitle ~= nil and menuTitle.Text == "SQUAD", "Select gehalten: Menü auf SQUAD, nicht INVENTAR")
hold(Enum.KeyCode.ButtonSelect)
check(not windowGui.Enabled, "Select gehalten: Squad-Fenster zu")

-- Hotbar setzen (wie vom Server: Liste mit Platz S, Id, Anzahl N)
local function setBag(list)
	bob:SetAttribute("ExtBag", HttpService:JSONEncode(list))
	step(0.1)
end
local humanoid = bob.Character:FindFirstChildOfClass("Humanoid")
local function setHealth(value)
	humanoid.MaxHealth = 100
	humanoid.Health = value
end

-- △ gehalten: Fahrzeug einpacken (kein Heilen); △ angetippt: heilen (kein Einpacken)
setBag({ { S = 1, Id = "Rifle", N = 1 }, { S = 2, Id = "Bandage", N = 3 }, { S = 5, Id = "Medkit", N = 1 } })
setHealth(100)
local mark = #SIM.RemoteLog
hold(Enum.KeyCode.ButtonY)
check(#actionsSince(mark, "StoreVehicle") == 1 and #actionsSince(mark, "Use") == 0, "△ gehalten: Fahrzeug einpacken, nicht heilen")
mark = #SIM.RemoteLog
tap(Enum.KeyCode.ButtonY)
local uses = actionsSince(mark, "Use")
check(#uses == 1 and #actionsSince(mark, "StoreVehicle") == 0, "△ angetippt: einmal heilen, kein Einpacken")
check(uses[1] and uses[1][2] == 2, "volles Leben: Verband (Platz 2) statt Medikit")

-- ---------- Auswahl des Heil-Items ----------
local function quickHeal()
	local before = #SIM.RemoteLog
	InputActions.Trigger("QuickHeal", true)
	InputActions.Trigger("QuickHeal", false)
	step(0.1)
	local list = actionsSince(before, "Use")
	return list[1] and list[1][2], #list
end
setHealth(40)
check(quickHeal() == 5, "60 Leben fehlen: Medikit (Platz 5)")
setHealth(50)
check(quickHeal() == 5, "genau 50 Leben fehlen: Medikit")
setHealth(51)
check(quickHeal() == 2, "49 Leben fehlen: Verband")
setBag({ { S = 1, Id = "Rifle", N = 1 }, { S = 4, Id = "Medkit", N = 1 } })
setHealth(95)
check(quickHeal() == 4, "nur Medikit in der Hotbar: auch bei wenig Schaden das Medikit")
setBag({ { S = 1, Id = "Rifle", N = 1 }, { S = 3, Id = "Adrenaline", N = 1 }, { S = 6, Id = "Bandage", N = 1 } })
setHealth(20)
check(quickHeal() == 6, "Verband vor Adrenalin")
setBag({ { S = 1, Id = "Rifle", N = 1 }, { S = 3, Id = "Adrenaline", N = 1 }, { S = 7, Id = "Vest", N = 1 } })
check(quickHeal() == 3, "ohne Verband und Medikit: irgendein Heil-Item (Adrenalin)")
-- Heil-Item nur in der Tasche (nicht in der Hotbar): nichts benutzen, Meldung
setBag({ { S = 1, Id = "Rifle", N = 1 }, { S = 7, Id = "Vest", N = 1 }, { S = 14, Id = "Medkit", N = 2 } })
local slot, count = quickHeal()
check(slot == nil and count == 0, "kein Heil-Item in der Hotbar: nichts benutzt")
local toast = nil
for _, d in hud:GetDescendants() do
	if d:IsA("TextLabel") and d.Text == "Kein Heil-Item in der Hotbar." then
		toast = d
	end
end
check(toast ~= nil and toast.Visible, "Meldung: Kein Heil-Item in der Hotbar.")
step(4)
check(toast and not toast.Visible, "Meldung verschwindet wieder")

-- ---------- außerhalb der offenen Welt: normale Belegung ----------
bob:SetAttribute("Mode", "Hub")
step(0.2)
check(holdCode("WorldMap") == nil and holdCode("Squad") == nil and holdCode("StoreVehicle") == nil,
	"außerhalb der offenen Welt keine Halten-Belegungen")
check(#B.QuickHeal.Pad == 0, "außerhalb der offenen Welt kein Heilen auf △")
check(InputActions.Hint("QuickHeal") == "" and InputActions.Hint("StoreVehicle") == "", "keine Hinweise HEILEN / HALTEN")
setBag({ { S = 2, Id = "Bandage", N = 3 } })
mark = #SIM.RemoteLog
pings = 0
local up = pad(Enum.KeyCode.DPadUp)
UserInputService.InputBegan:Fire(up, false)
check(pings == 1, "außerhalb: Ping sofort beim Drücken (ohne Warten auf Loslassen)")
step(InputActions.HoldTime + 0.2)
UserInputService.InputEnded:Fire(up, false)
step(0.1)
check(pings == 1 and not mapGui.Enabled, "außerhalb: gehalten keine Karte")
tap(Enum.KeyCode.ButtonY)
hold(Enum.KeyCode.ButtonY)
check(#actionsSince(mark, "Use") == 0 and #actionsSince(mark, "StoreVehicle") == 0, "außerhalb: △ heilt nicht und packt nichts ein")

-- zurück in die offene Welt: Belegung wieder da
bob:SetAttribute("Mode", "Extinction")
step(0.2)
check(holdCode("WorldMap") == Enum.KeyCode.DPadUp and holdCode("Squad") == Enum.KeyCode.ButtonSelect
	and holdCode("StoreVehicle") == Enum.KeyCode.ButtonY and B.QuickHeal.Pad[1] == Enum.KeyCode.ButtonY,
	"wieder in der offenen Welt: Controller-Belegung wieder da")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

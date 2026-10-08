-- Menü der offenen Welt (ExtinctionClient): TAB öffnet es auf INVENTAR, M auf dem zuletzt offenen Reiter, beides schließt
-- es wieder. Reiter INVENTAR · MARKT · LOOT · GUIDE · SQUAD · ERFOLGE (eigene Seiten) und SHOP · BATTLE PASS · STATISTIK ·
-- CODES · OPTIONEN (aus der Lobby ausgeliehen, verkleinert, beim Schließen zurückgegeben). Controller: L1/R1 blättert, Auswahl startet im Inhalt.
-- Das Menü ist kleiner als der Bildschirm (Leinwand 1600 x 900).
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
local GameMenu = require("GameMenu")
local SideMenu = require("SideMenu")
InputActions.Init()
GameMenu.Init()
SideMenu.Init()
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

local function key(code)
	local input = { KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }
	UserInputService.InputBegan:Fire(input, false)
	step(0.05)
	UserInputService.InputEnded:Fire(input, false)
	step(0.1)
end
local windowGui = playerGui:FindFirstChild("ExtinctionWindow")
local function menu()
	return windowGui and windowGui.Enabled and windowGui:FindFirstChild("Menu", true) or nil
end
local function title()
	local m = menu()
	local t = m and m:FindFirstChild("Title", true)
	return t and t.Text
end
local function activeTab()
	local m = menu()
	for _, tab in m and m:FindFirstChild("Tabs", true):GetChildren() or {} do
		local line = tab:FindFirstChild("Underline")
		if line and line.Visible then
			return string.sub(tab.Name, 5)
		end
	end
	return nil
end

-- TAB: Menü auf INVENTAR, kleiner als der Bildschirm
key(Enum.KeyCode.Tab)
check(menu() ~= nil and title() == "INVENTAR" and activeTab() == "Inventory", "TAB: Menü auf INVENTAR")
local size = menu() and menu().Size
check(size and size.X.Offset < 1600 and size.Y.Offset < 900, "Menü kleiner als der Bildschirm")
local names = {}
for _, tab in menu():FindFirstChild("Tabs", true):GetChildren() do
	if tab:IsA("TextButton") then
		names[tab.LayoutOrder] = tab.Text
	end
end
check(table.concat(names, ",") == "INVENTAR,MARKT,LOOT,GUIDE,SQUAD,ERFOLGE,SHOP,BATTLE PASS,STATISTIK,CODES,OPTIONEN",
	"Reiter in der Reihenfolge (" .. table.concat(names, ",") .. ")")
check(find(menu(), "Slot_Bag_10") ~= nil or #menu():GetDescendants() > 50, "Inventar mit Plätzen gebaut")
key(Enum.KeyCode.Tab)
check(menu() == nil, "TAB nochmal: zu")

-- Reiter wechseln per Klick; M öffnet den zuletzt offenen Reiter
key(Enum.KeyCode.Tab)
menu():FindFirstChild("Tabs", true).Tab_Squad.Activated:Fire()
step(0.1)
check(title() == "SQUAD" and activeTab() == "Squad", "Klick auf SQUAD")
key(Enum.KeyCode.M)
check(menu() == nil, "M schließt")
key(Enum.KeyCode.M)
check(title() == "SQUAD", "M öffnet den letzten Reiter (SQUAD)")
menu():FindFirstChild("Tabs", true).Tab_Achievements.Activated:Fire()
step(0.1)
check(title() == "ERFOLGE" and activeTab() == "Achievements", "Klick auf ERFOLGE")
check(find(menu(), "Achievement_Zombies") ~= nil and find(menu(), "Achievement_Veteran") ~= nil, "Erfolge-Wand mit Karten")

-- Lobby-Seiten: ausgeliehen, verkleinert, beim Schließen zurück in die Lobby
for _, id in { "Shop", "Pass", "Stats", "Codes", "Settings" } do
	menu():FindFirstChild("Tabs", true)["Tab_" .. id].Activated:Fire()
	step(0.1)
	check(activeTab() == id, id .. ": Reiter aktiv")
	local holder = menu() and menu():FindFirstChild("PageHolder", true)
	local page = holder and holder:FindFirstChild(id .. "Page")
	check(page ~= nil and page.Visible, id .. ": Seite der Lobby im Menü")
	local scale = holder and holder:FindFirstChildOfClass("UIScale")
	check(scale ~= nil and scale.Scale < 1 and scale.Scale > 0.8, id .. ": verkleinert")
end
key(Enum.KeyCode.M)
check(menu() == nil, "M schließt (auf OPTIONEN)")
local lobbyGui = playerGui:FindFirstChild("GameMenu")
check(lobbyGui ~= nil and lobbyGui:FindFirstChild("SettingsPage", true) ~= nil, "OPTIONEN zurück in der Lobby")
check(not lobbyGui.Enabled, "Lobby bleibt in der offenen Welt zu")
key(Enum.KeyCode.M)
check(activeTab() == "Settings", "M: wieder OPTIONEN")

-- Controller: R1/L1 blättern (rundum), Auswahl im Inhalt, nicht auf den Reitern
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
step(0.1)
local function pad(code)
	local input = { KeyCode = code, UserInputType = Enum.UserInputType.Gamepad1 }
	UserInputService.InputBegan:Fire(input, false)
	step(0.05)
	UserInputService.InputEnded:Fire(input, false)
	step(0.1)
end
pad(Enum.KeyCode.ButtonR1)
check(activeTab() == "Inventory", "R1 auf OPTIONEN: rundum zu INVENTAR")
pad(Enum.KeyCode.ButtonR1)
check(activeTab() == "Market", "R1: MARKT")
pad(Enum.KeyCode.ButtonL1)
pad(Enum.KeyCode.ButtonL1)
check(activeTab() == "Settings", "L1 zweimal: OPTIONEN")
pad(Enum.KeyCode.ButtonR1)
step(0.2)
local GuiService = game:GetService("GuiService")
local selected = GuiService.SelectedObject
check(selected ~= nil and selected:IsDescendantOf(menu():FindFirstChild("Content", true)), "Controller-Auswahl im Inhalt")
pad(Enum.KeyCode.ButtonB)
check(menu() == nil, "○ schließt das Menü")
check(GuiService.SelectedObject == nil or not GuiService.SelectedObject:IsDescendantOf(windowGui), "Auswahl aufgehoben")

if failures == 0 then
	print("Menü der offenen Welt: alles in Ordnung")
end

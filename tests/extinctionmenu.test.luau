-- Menü der offenen Welt (ExtinctionClient): TAB öffnet es auf INVENTAR, M auf dem zuletzt offenen Reiter, beides schließt
-- es wieder. Reiter INVENTAR · MARKT · AUFTRÄGE · LOOT · GUIDE · SQUAD · ERFOLGE (eigene Seiten) und SHOP · BATTLE PASS ·
-- STATISTIK · CODES · OPTIONEN (aus der Lobby ausgeliehen, verkleinert, beim Schließen zurückgegeben), AGENTEN als Link in
-- die Lobby. Controller: L1/R1 blättert, Auswahl startet im Inhalt.
-- Arcade aus (Modes.ArcadeEnabled = false, Standard): kein SPIELEN · ARCADE im Menü (LOADOUT bleibt), AUFTRÄGE ohne Reiter
-- ARCADE, die Lobby ohne SPIELEN (Modi, SCHNELLES SPIEL); GameMenu.Open("Play") zeigt AGENTEN.
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
check(table.concat(names, ",") == "INVENTAR,MARKT,AUFTRÄGE,LOOT,GUIDE,SQUAD,ERFOLGE,LOADOUT,SHOP,BATTLE PASS,STATISTIK,CODES,OPTIONEN,AGENTEN",
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
-- Sichtbar auf dem Bildschirm (alle Vorfahren sichtbar)?
local function shown(object)
	local current = object
	while current and not current:IsA("LayerCollector") do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current == nil or current.Enabled
end
local function shownTexts(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) then
			out[d.Text] = true
		end
	end
	return out
end

-- AUFTRÄGE: ohne Arcade nur EXTINCTION
menu():FindFirstChild("Tabs", true).Tab_Quests.Activated:Fire()
step(0.1)
local questTexts = shownTexts(menu())
check(title() == "AUFTRÄGE" and questTexts.EXTINCTION and not questTexts.ARCADE, "AUFTRÄGE: kein Reiter ARCADE")

for _, id in { "Loadout", "Shop", "Pass", "Stats", "Codes", "Settings" } do
	menu():FindFirstChild("Tabs", true)["Tab_" .. id].Activated:Fire()
	step(0.1)
	check(activeTab() == id, id .. ": Reiter aktiv")
	local holder = menu() and menu():FindFirstChild("PageHolder", true)
	local page = holder and holder:FindFirstChild((if id == "Loadout" then "Inventory" else id) .. "Page")
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
-- AGENTEN: Link in die Lobby (Menü zu, Lobby auf der Seite AGENTEN), Lobby wieder zu
menu():FindFirstChild("Tabs", true).Tab_Agents.Activated:Fire()
step(0.1)
check(menu() == nil and lobbyGui.Enabled, "AGENTEN: Menü zu, Lobby offen")
local agentsPage = lobbyGui:FindFirstChild("AgentsPage", true)
check(agentsPage ~= nil and agentsPage.Visible, "AGENTEN: Seite der Lobby sichtbar")
-- Lobby ohne Arcade: kein SPIELEN, ARCADE, SCHNELLES SPIEL; Open("Play") und Open() zeigen AGENTEN
local lobbyTexts = shownTexts(lobbyGui)
check(lobbyTexts.AGENTEN and lobbyTexts.LOADOUT and lobbyTexts.SHOP and lobbyTexts["BATTLE PASS"] and lobbyTexts.STATISTIK,
	"Lobby: AGENTEN, SHOP, BATTLE PASS, STATISTIK, LOADOUT da")
for _, text in { "SPIELEN", "ARCADE", "SCHNELLES SPIEL", "SPIELMODUS", "FREE-FOR-ALL", "HERRSCHAFT" } do
	check(not lobbyTexts[text], "Lobby ohne Arcade: kein " .. text)
end
for _, tab in { "Play", "Modes" } do
	GameMenu.Open(tab)
	step(0.1)
	local playPage = lobbyGui:FindFirstChild("PlayPage", true)
	check(agentsPage.Visible and not (playPage and playPage.Visible), "GameMenu.Open(" .. tab .. "): AGENTEN statt SPIELEN")
end
GameMenu.Open()
step(0.1)
check(agentsPage.Visible, "GameMenu.Open(): AGENTEN")
GameMenu.SetOpen(false)
step(0.1)
key(Enum.KeyCode.M)
check(activeTab() == "Settings", "M nach dem Lobby-Link: wieder OPTIONEN")

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

-- VERLASSEN-Knopf: in der offenen Welt ausgeblendet (kein LOBBY mehr), im Markt zurück ins Camp
local LeaveButton = require("LeaveButton")
local leaveGui = Instance.new("ScreenGui", playerGui)
local leave = LeaveButton.new(leaveGui, { Name = "LeaveButton", Size = UDim2.fromOffset(152, 30) })
check(not leave.Button.Visible, "VERLASSEN: in der offenen Welt ausgeblendet")
bob:SetAttribute("Mode", "Market")
step(0.1)
check(leave.Button.Visible and leave.Label.Text == "VERLASSEN", "VERLASSEN: im Markt sichtbar")
bob:SetAttribute("Mode", "Extinction")
step(0.1)
check(not leave.Button.Visible, "VERLASSEN: zurück in der offenen Welt wieder aus")

if failures == 0 then
	print("Menü der offenen Welt: alles in Ordnung")
end

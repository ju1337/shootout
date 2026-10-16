-- Pflicht-Tutorial der offenen Welt (ExtTutorial, TutorialConfig): neuer Spieler bekommt es ohne Überspringen, alter
-- Spieler (GuideHinted) nicht. Server: Camp-Sperre (TutorialLock) bis zum Schritt "Leave" (über den Rand gelaufen =
-- zurück nach innen, weit weg = Teleport bleibt), Flags für echte Aktionen (Kit, Container, Kauf, Verkauf, Markt),
-- Fortsetzen nach erneutem Beitritt beim gemerkten Schritt. Client: Karte WILLKOMMEN nur mit LOS GEHT'S, im GUIDE
-- kein Beenden, Tafel mit Schrittzähler, Wegpunkt (nächster Kit-Händler), Coach-Karten mit rotem Rahmen im Menü
-- (WEITER bzw. warten auf die Aktion), Rahmen um den Hotbar-Platz der Waffe, Pfeil am Rand bei Ziel außer Sicht,
-- Minimap-Raute, alle 15 Schritte bis "Done".
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
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
for name, offset in { Stand_Weapons = Vector3.new(-36, 2.5, 34), Stash = Vector3.new(52, 2.5, -30),
	Kits = Vector3.new(12, 2.5, 20), Stand_Market = Vector3.new(-20, 2.5, -40), Stand_Items = Vector3.new(40, 2.5, 640),
	Stand_Vehicles = Vector3.new(-40, 2.5, 640) } do
	local part = Instance.new("Part", map.Stands)
	part.Name = name
	part.CFrame = CFrame.new(CENTER + offset)
end
-- zweiter Kit-Händler weit weg (Safehouse): der Wegpunkt zeigt auf den nächsten
local farKits = Instance.new("Part", map.Stands)
farKits.Name = "Kits"
farKits.CFrame = CFrame.new(CENTER + Vector3.new(0, 2.5, 700))

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
local ExtinctionConfig = require("ExtinctionConfig")
local TutorialConfig = require("TutorialConfig")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Horde.Enabled = false
ExtinctionConfig.HeliCrash.Enabled = false
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0
ExtinctionConfig.Redzone.Enabled = false
Extinction.Init({ Join = function() end, Status = function() end })

-- ---------- Server: neuer Spieler bekommt das Pflicht-Tutorial, alter Spieler (GuideHinted) nicht ----------
store.Data.u1 = { XP = {}, Coins = 4000, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 4000, Rap = 0, Owned = {}, Equipped = {}, GuideHinted = true }
local bob = SIM.Join("Bob")
local old = SIM.Join("Veteran")
for _, p in { bob, old } do
	Instance.new("Backpack", p).Name = "Backpack"
end
SIM.Advance(2, 20)
for _, p in { bob, old } do
	p:SetAttribute("Mode", "Extinction")
	Extinction.AddPlayer(p)
end
SIM.Advance(0.5, 20)
check(bob:GetAttribute("ExtTutorial") == true and bob:GetAttribute("TutorialForced") == true, "neuer Spieler: Pflicht-Tutorial")
check(bob:GetAttribute("TutorialStep") == "Kit" and bob:GetAttribute("TutorialLock") == true, "beginnt bei Kit, Camp gesperrt")
check(old:GetAttribute("ExtTutorial") == nil and old:GetAttribute("TutorialLock") == nil, "alter Spieler (GuideHinted): kein Tutorial")
check(#TutorialConfig.Steps == 15 and TutorialConfig.Locked("Market") and not TutorialConfig.Locked("Leave"),
	"15 Schritte, Camp-Teil bis zum Markt")

-- Camp-Sperre: über den Rand gelaufen -> wieder innen; weit weg (Teleport) bleibt; der Veteran darf hinaus
local function place(p, offset)
	p.Character:PivotTo(CFrame.new(CENTER + offset))
	SIM.Advance(0.4, 20)
end
place(bob, Vector3.new(0, 3, 90))
check(bob:GetAttribute("InSafeZone") == true, "Bob im Camp")
place(bob, Vector3.new(0, 3, 112))
local root = bob.Character.HumanoidRootPart
check(bob:GetAttribute("InSafeZone") == true and (root.Position - CENTER).Magnitude < 100, "Camp-Sperre: zurück nach innen")
place(old, Vector3.new(0, 3, 90))
place(old, Vector3.new(0, 3, 112))
check(old:GetAttribute("InSafeZone") == false, "ohne Tutorial: hinaus geht")
place(old, Vector3.new(0, 3, 0))
place(bob, Vector3.new(0, 3, 0))

-- Überspringen meldet der Server beim Pflicht-Tutorial nicht als erledigt
InventoryService.Handlers.Tutorial(bob, "Skip")
check(bob:GetAttribute("ExtTutorial") == true and ProgressService.Get(bob).TutorialDone ~= true, "Pflicht: Skip wirkungslos")

-- Flags: was der Server wirklich gesehen hat
InventoryService.Notify(bob, "Sell")
InventoryService.Notify(old, "Sell")
check(string.find(bob:GetAttribute("TutorialFlags") or "", "Sell", 1, true) ~= nil, "Flag Verkauf beim Tutorial-Spieler")
check(old:GetAttribute("TutorialFlags") == nil, "kein Flag ohne Tutorial")
bob:SetAttribute("TutorialFlags", "{}")

-- Fortsetzen: Schritt im Profil, nach Moduswechsel/Beitritt geht es dort weiter
InventoryService.Handlers.Tutorial(bob, "Step", 5, "Trader")
check(ProgressService.Get(bob).TutorialStep == "Trader" and bob:GetAttribute("TutorialLock") == true, "Schritt gemerkt")
Extinction.RemovePlayer(bob)
check(bob:GetAttribute("TutorialStep") == nil, "beim Verlassen weg")
Extinction.AddPlayer(bob)
SIM.Advance(0.5, 20)
check(bob:GetAttribute("TutorialStep") == "Trader" and bob:GetAttribute("TutorialForced") == true, "weiter bei Trader")
InventoryService.Handlers.Tutorial(bob, "Step", 8, "Leave")
check(bob:GetAttribute("TutorialLock") == nil, "ab Leave darf er hinaus")
-- zurück auf Anfang für den Client-Durchlauf
ProgressService.Get(bob).TutorialStep = nil
Extinction.RemovePlayer(bob)
Extinction.AddPlayer(bob)
SIM.Advance(0.5, 20)
check(bob:GetAttribute("TutorialStep") == "Kit", "neu: wieder bei Kit")

-- ---------- Client von Bob (Fernaufrufe an den Server werden nur mitgelesen) ----------
rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
local ExtinctionClient = require("ExtinctionClient")
local ExtTutorial = require("ExtTutorial")
local GameMenu = require("GameMenu")
local SideMenu = require("SideMenu")
InputActions.Init()
GameMenu.Init()
SideMenu.Init()
ExtinctionClient.Init()
local function step(seconds)
	SIM.Advance(seconds or 0.2, 20)
end
local function key(code)
	local input = { KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }
	UserInputService.InputBegan:Fire(input, false)
	step(0.05)
	UserInputService.InputEnded:Fire(input, false)
	step(0.1)
end
local function sentTutorial()
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "ExtAction" and entry.Player == "server" and entry.Args[1] == "Tutorial" then
			return entry.Args[2], entry.Args[4]
		end
	end
	return nil
end
local function setFlags(flags)
	bob:SetAttribute("TutorialFlags", HttpService:JSONEncode(flags))
end
step(1)

local gui = playerGui:FindFirstChild("ExtTutorial")
local focus = playerGui:FindFirstChild("ExtTutorialFocus")
local intro = gui and gui:FindFirstChild("Intro", true)
check(intro ~= nil, "Karte WILLKOMMEN erscheint")
check(intro and intro:FindFirstChild("Skip", true) == nil, "kein Überspringen")
local start = intro and intro:FindFirstChild("Start", true)
check(start ~= nil and start:IsA("TextButton"), "Knopf LOS GEHT'S")
if start then
	start.Activated:Fire()
end
step(0.3)
local panel = gui:FindFirstChild("Panel", true)
check(ExtTutorial.CurrentStep() == "Kit" and panel and panel.Visible, "Schritt 1: Starter-Kit, Tafel sichtbar")
check(panel and panel:FindFirstChild("Step", true).Text == "TUTORIAL  ·  SCHRITT 1/15", "Schrittzähler 1/15")
check(panel and panel:FindFirstChild("Phase", true).Text == "IM CAMP", "Phase IM CAMP")
-- Tafel und Karte wachsen mit dem Inhalt (AutomaticSize Y + Liste): kein Kind darf seine Höhe von ihnen nehmen,
-- sonst schaukelt sich die Höhe auf (riesige leere Tafel, Julio 2026-10-16)
for _, holder in { panel, playerGui.ExtTutorialFocus.Callout } do
	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then
			check(child.Size.Y.Scale == 0, "feste Höhe in " .. holder.Name .. ": " .. child.Name)
		end
	end
end
check(string.find(panel:FindFirstChild("Foot", true).Text, "PFLICHT", 1, true) ~= nil, "Fußzeile: Pflicht, kein Skip-Hinweis")
local waypoint = playerGui:FindFirstChild("TutorialWaypoint")
local kitsPos = (CENTER + Vector3.new(12, 2.5, 20))
check(waypoint ~= nil and waypoint.Enabled and waypoint.Adornee ~= nil
	and (waypoint.Adornee.WorldPosition - kitsPos).Magnitude < 1, "Wegpunkt zum nächsten Kit-Händler")
check(waypoint and waypoint.Text.Text == "KIT-HÄNDLER", "Wegpunkt mit Namen")
check(string.find(panel:FindFirstChild("Target", true).Text, "ZIEL: KIT-HÄNDLER", 1, true) ~= nil, "Tafel: Ziel und Entfernung")
local guideAt = require("Minimap").Guide()
check(guideAt ~= nil and (guideAt - kitsPos).Magnitude < 1, "Minimap: Raute am Ziel")

-- Pfeil am Rand: Kamera schaut weg vom Ziel
local camera = workspace.CurrentCamera
local bobRoot = bob.Character.HumanoidRootPart
camera.CFrame = CFrame.lookAt(bobRoot.Position + Vector3.new(0, 5, 0), bobRoot.Position + (bobRoot.Position - kitsPos) + Vector3.new(0, 5, 0))
step(0.3)
local edge = focus:FindFirstChild("EdgeArrow")
check(edge and edge.Visible, "Ziel hinter der Kamera: Pfeil am Rand")
camera.CFrame = CFrame.lookAt(bobRoot.Position + Vector3.new(0, 5, 0), kitsPos + Vector3.new(0, 7, 0))
step(0.3)
check(edge and not edge.Visible, "Ziel im Bild: kein Pfeil")

-- GUIDE: kein Beenden-Knopf beim Pflicht-Tutorial
key(Enum.KeyCode.M)
local windowGui = playerGui:FindFirstChild("ExtinctionWindow")
local menu = windowGui and windowGui:FindFirstChild("Menu", true)
local tabs = menu and menu:FindFirstChild("Tabs", true)
if tabs then
	tabs.Tab_Guide.Activated:Fire()
end
step(0.1)
check(windowGui:FindFirstChild("Tutorial", true) == nil and windowGui:FindFirstChild("TutorialForced", true) ~= nil,
	"GUIDE: Pflicht-Tutorial lässt sich nicht beenden")
ExtTutorial.Stop()
check(ExtTutorial.IsActive(), "Stop wirkt beim Pflicht-Tutorial nicht")
local callout = focus:FindFirstChild("Callout")
step(0.3)
check(callout.Visible and string.find(callout.Text.Text, "Kit-Händler", 1, true) ~= nil,
	"anderes Menü offen: Anweisung als Karte über dem Menü")
key(Enum.KeyCode.M)
step(0.3)
check(not windowGui.Enabled and not callout.Visible, "Menü zu, Karte weg")

-- Kits: Coach-Karte am Knopf ABHOLEN, bis das Kit da ist
map.Stands.Kits:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(bob)
step(0.4)
local _, highlighted = ExtTutorial.CurrentCoach()
check(highlighted ~= nil and highlighted.Name == "Claim" and focus.Highlight.Visible, "Kits: roter Rahmen um ABHOLEN")
check(callout.Visible and not callout.Next.Visible and callout.Wait.Text == "MACH ES JETZT", "Kits: Karte wartet auf die Aktion")
bob:SetAttribute("ExtBag", HttpService:JSONEncode({ { S = 2, Id = "Pistol", N = 1 }, { S = 6, Id = "Bandage", N = 5 } }))
step(0.4)
check(ExtTutorial.CurrentStep() == "Inventory", "Schritt 2: Inventar")
check(not focus.Highlight.Visible, "Rahmen weg")
key(Enum.KeyCode.Tab) -- Kits zu
key(Enum.KeyCode.Tab)
step(0.4)
check(ExtTutorial.CurrentStep() == "Safe", "TAB: Schritt 3, Tasche und Container")

-- Coach im Inventar: Tasche (WEITER), Schnellleiste (WEITER), Container (warten auf Flag Safe)
local coach, object = ExtTutorial.CurrentCoach()
check(coach == 1 and object and object.Name == "Grid_Bag" .. (ExtinctionConfig.HotbarSlots + 1), "Tipp 1: Tasche")
check(callout.Visible and callout.Next.Visible, "Tipp 1 mit WEITER")
callout.Next.Activated:Fire()
step(0.3)
coach, object = ExtTutorial.CurrentCoach()
check(coach == 2 and object and object.Name == "Grid_Bag1", "Tipp 2: Schnellleiste")
callout.Next.Activated:Fire()
step(0.3)
coach, object = ExtTutorial.CurrentCoach()
check(coach == 3 and object and object.Name == "Grid_Safe1" and not callout.Next.Visible, "Tipp 3: Container, wartet")
step(1)
check(ExtTutorial.CurrentStep() == "Safe", "ohne Container-Aktion geht es nicht weiter")
setFlags({ Safe = true })
step(0.4)
check(ExtTutorial.CurrentStep() == "Equip", "Item im Container: Schritt 4, Waffe")
key(Enum.KeyCode.Tab)
step(0.4)
check(panel.Visible, "Tafel wieder da")
check(string.find(panel:FindFirstChild("Text", true).Text, "[2]", 1, true) ~= nil, "Text nennt die Taste der Waffe (2)")
_, object = ExtTutorial.CurrentCoach()
check(object ~= nil and object.Name == "Hotbar2" and focus.Highlight.Visible and not callout.Visible,
	"Rahmen um den Hotbar-Platz der Waffe")
bob:SetAttribute("ExtEquipped", 2)
step(0.4)
check(ExtTutorial.CurrentStep() == "Trader", "Schritt 5: Händler")
check((waypoint.Adornee.WorldPosition - (CENTER + Vector3.new(-36, 2.5, 34))).Magnitude < 1, "Wegpunkt zum Händler")

-- Händler: Erklärung (WEITER), Munition kaufen (Flag Buy), Verkaufen (WEITER)
bob.Character:PivotTo(map.Stands.Stand_Weapons.CFrame + Vector3.new(0, 1, 4))
step(0.2)
map.Stands.Stand_Weapons:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(bob)
step(0.4)
_, object = ExtTutorial.CurrentCoach()
check(object and object.Name == "Offer", "Händler: Angebotsliste")
callout.Next.Activated:Fire()
step(0.3)
_, object = ExtTutorial.CurrentCoach()
check(object and object.Name == "Buy" and object.Parent.Name == "Offer_Ammo_9mm", "Händler: Kaufen-Knopf der 9mm-Munition")
setFlags({ Safe = true, Buy = true })
step(0.4)
_, object = ExtTutorial.CurrentCoach()
check(object and object.Name == "SellHint", "Händler: Verkaufen erklärt")
callout.Next.Activated:Fire()
step(0.4)
check(ExtTutorial.CurrentStep() == "Stash", "Schritt 6: Lager")
key(Enum.KeyCode.Tab)
step(0.2)

bob.Character:PivotTo(map.Stands.Stash.CFrame + Vector3.new(0, 1, 4))
step(0.2)
map.Stands.Stash:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(bob)
step(0.4)
_, object = ExtTutorial.CurrentCoach()
check(object and object.Name == "Grid_Stash1", "Lager: Raster")
callout.Next.Activated:Fire()
step(0.3)
callout.Next.Activated:Fire()
step(0.4)
check(ExtTutorial.CurrentStep() == "Market", "Schritt 7: Spielermarkt")
key(Enum.KeyCode.Tab)
step(0.2)

-- Spielermarkt: alle Tipps (fehlt ein Element im offenen Markt, geht es nach kurzer Zeit weiter)
bob.Character:PivotTo(map.Stands.Stand_Market.CFrame + Vector3.new(0, 1, 4))
step(0.2)
map.Stands.Stand_Market:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(bob)
step(0.4)
_, object = ExtTutorial.CurrentCoach()
check(object and object.Name == "Results", "Markt: Angebote")
local seen = {}
for _ = 1, 10 do
	_, object = ExtTutorial.CurrentCoach()
	if object then
		seen[object.Name] = true
	end
	if ExtTutorial.CurrentStep() ~= "Market" then
		break
	end
	if callout.Visible and callout.Next.Visible then
		callout.Next.Activated:Fire()
	end
	step(2.5)
end
check(seen.Results and seen.Filters and seen.Sell and seen.TabMine, "Markt: Angebote, Filter, Verkaufen, Meine Angebote")
check(ExtTutorial.CurrentStep() == "Leave", "Schritt 8: Camp verlassen")
check(select(2, sentTutorial()) == "Leave", "Schritt an den Server gemeldet")
key(Enum.KeyCode.Tab)
step(0.4)
check(panel:FindFirstChild("Phase", true).Text == "DRAUSSEN" and waypoint.Enabled, "Leave: Phase DRAUSSEN, Wegpunkt zum Tor")
bob:SetAttribute("InSafeZone", false)
step(0.4)
check(ExtTutorial.CurrentStep() == "Zombie", "Schritt 9: Zombie töten")

-- Zombie: Wegpunkt zum nächsten eigenen Zombie, fremde zählen nicht
local zombies = workspace:FindFirstChild("Zombies") or Instance.new("Folder", workspace)
zombies.Name = "Zombies"
local function zombie(offset, owner)
	local model = Instance.new("Model", zombies)
	local zroot = Instance.new("Part", model)
	zroot.Name = "HumanoidRootPart"
	zroot.CFrame = CFrame.new(bobRoot.Position + offset)
	local humanoid = Instance.new("Humanoid", model)
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	model:SetAttribute("ZombieOwnerId", owner)
	return model, zroot
end
zombie(Vector3.new(10, 0, 0), 999)
local mine, mineRoot = zombie(Vector3.new(0, 0, 40), bob.UserId)
step(0.4)
check(waypoint.Enabled and (waypoint.Adornee.WorldPosition - mineRoot.Position).Magnitude < 1, "Wegpunkt zum eigenen Zombie")
bob:SetAttribute("ZombieKills", (bob:GetAttribute("ZombieKills") or 0) + 1)
mine.Humanoid.Health = 0
local prompt = Instance.new("ProximityPrompt", mineRoot)
prompt.Name = "CorpsePrompt"
prompt.Enabled = true
step(0.4)
check(ExtTutorial.CurrentStep() == "Loot", "Schritt 10: Leiche durchsuchen")
check((waypoint.Adornee.WorldPosition - mineRoot.Position).Magnitude < 1, "Wegpunkt zur Leiche")
step(5)
check(ExtTutorial.CurrentStep() == "Loot", "Beute-Schritt wartet, solange Beute da ist")
require("Remotes").ExtUpdate.OnClientEvent:Fire("Picked", { { Id = "Bandage", Count = 1 } })
step(0.4)
check(ExtTutorial.CurrentStep() == "Map", "Schritt 11: Karte öffnen")
local mapGui = playerGui:FindFirstChild("ExtinctionMap") or Instance.new("ScreenGui", playerGui)
mapGui.Name = "ExtinctionMap"
mapGui.Enabled = true
step(0.4)
mapGui.Enabled = false
check(ExtTutorial.CurrentStep() == "Redzone", "Schritt 12: rote Zone")
step(14.5)
check(ExtTutorial.CurrentStep() == "Return", "Schritt 13: zurück in Sicherheit")
check(waypoint.Enabled, "Wegpunkt zur Safe Zone")
bob:SetAttribute("InSafeZone", true)
step(0.4)
check(ExtTutorial.CurrentStep() == "Sell", "Schritt 14: Beute verkaufen")
-- Beute in der Tasche: wartet auf Verkauf oder Marktangebot
bob:SetAttribute("ExtBag", HttpService:JSONEncode({ { S = 2, Id = "Pistol", N = 1 }, { S = 8, Id = "Medkit", N = 1 } }))
step(1)
check(ExtTutorial.CurrentStep() == "Sell", "wartet auf den Verkauf")
setFlags({ Safe = true, Buy = true, MarketList = true })
step(0.4)
check(ExtTutorial.CurrentStep() == "Ready", "Marktangebot zählt: Schritt 15")
step(14.5)
check(not ExtTutorial.IsActive() and not panel.Visible and not waypoint.Enabled, "Tutorial fertig")
check(sentTutorial() == "Done", "fertig an den Server gemeldet")
InventoryService.Handlers.Tutorial(bob, "Done")
check(ProgressService.Get(bob).TutorialDone == true and bob:GetAttribute("TutorialForced") == nil
	and bob:GetAttribute("TutorialLock") == nil, "Server: fertig, keine Sperre mehr")

-- Wiederholung über GUIDE: freiwillig, mit BEENDEN
ExtTutorial.Start(false)
check(sentTutorial() == "Step", "Wiederholung: Server bekommt Start und Schritt")
InventoryService.Handlers.Tutorial(bob, "Start") -- was der Server darauf tut (Fernaufrufe kommen im Test nicht an)
step(0.3)
check(bob:GetAttribute("TutorialForced") == nil and bob:GetAttribute("TutorialLock") == nil, "Wiederholung: keine Pflicht, keine Sperre")
check(ExtTutorial.IsActive() and bob:GetAttribute("ExtTutorial") == true, "Wiederholung läuft (Kit schon erledigt)")
check(string.find(panel:FindFirstChild("Foot", true).Text, "BEENDEN", 1, true) ~= nil, "Wiederholung: Beenden-Hinweis")
bob:SetAttribute("Mode", "Hub")
step(0.4)
check(not panel.Visible, "im Hub keine Tafel")
bob:SetAttribute("Mode", "Extinction")
ExtTutorial.Stop()
step(0.3)
check(not ExtTutorial.IsActive(), "Stop beendet die Wiederholung")

if failures == 0 then
	print("Tutorial: alles in Ordnung")
end

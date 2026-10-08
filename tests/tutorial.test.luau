-- Tutorial der offenen Welt (ExtTutorial): neuer Spieler bekommt die Karte WELCOME (START / SKIP), Überspringen merkt
-- sich der Server (TutorialDone), alte Spieler (GuideHinted) bekommen es nicht. Aus dem GUIDE gestartet führt die Tafel
-- durch alle Schritte (Kit, Inventar, Waffe, Safe Zone verlassen, Zombie, Schluss), jeder geht erst weiter, wenn er
-- erledigt ist; der Kit-Schritt zeigt einen Wegpunkt zum Kit-Händler. Am Ende meldet der Client "Tutorial" "Done".
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
	Kits = Vector3.new(12, 2.5, 20) } do
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
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Horde.Enabled = false
ExtinctionConfig.HeliCrash.Enabled = false
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0
ExtinctionConfig.Redzone.Enabled = false
Extinction.Init({ Join = function() end, Status = function() end })

-- Server: neuer Spieler bekommt das Tutorial, alter Spieler (GuideHinted) nicht
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
check(bob:GetAttribute("ExtTutorial") == true, "neuer Spieler: Tutorial an")
check(old:GetAttribute("ExtTutorial") == nil, "alter Spieler (GuideHinted): kein Tutorial")

-- Client von Bob (Fernaufrufe an den Server werden nur mitgelesen)
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
			return entry.Args[2]
		end
	end
	return nil
end
step(1)

local gui = playerGui:FindFirstChild("ExtTutorial")
local intro = gui and gui:FindFirstChild("Intro", true)
check(intro ~= nil, "Karte WELCOME erscheint")
check(ExtTutorial.IsActive() and ExtTutorial.CurrentStep() == nil, "Karte offen, noch kein Schritt")

-- SKIP: Karte weg, Server erfährt es, Profil merkt es sich
local skip = intro and intro:FindFirstChild("Skip", true)
check(skip ~= nil and skip:IsA("TextButton"), "Knopf SKIP")
if skip then
	skip.Activated:Fire()
end
step(0.3)
check(gui:FindFirstChild("Intro", true) == nil and not ExtTutorial.IsActive(), "SKIP schließt die Karte")
check(sentTutorial() == "Skip", "SKIP an den Server gemeldet")
InventoryService.Handlers.Tutorial(bob, "Skip")
check(ProgressService.Get(bob).TutorialDone == true and bob:GetAttribute("ExtTutorial") == nil, "Server: TutorialDone gesetzt")
Extinction.RemovePlayer(bob)
Extinction.AddPlayer(bob)
step(0.5)
check(bob:GetAttribute("ExtTutorial") == nil, "nach SKIP kommt es nicht wieder")

-- GUIDE: START TUTORIAL führt durch alle Schritte
key(Enum.KeyCode.M)
local windowGui = playerGui:FindFirstChild("ExtinctionWindow")
local menu = windowGui and windowGui:FindFirstChild("Menu", true)
local tabs = menu and menu:FindFirstChild("Tabs", true)
if tabs then
	tabs.Tab_Guide.Activated:Fire()
end
step(0.1)
local startButton = windowGui:FindFirstChild("Tutorial", true)
check(startButton ~= nil and startButton.Text == "START TUTORIAL", "GUIDE: Knopf START TUTORIAL")
if startButton then
	startButton.Activated:Fire()
end
step(0.3)
check(not windowGui.Enabled, "Menü schließt beim Start")
local panel = gui:FindFirstChild("Panel", true)
check(ExtTutorial.CurrentStep() == "Kit" and panel and panel.Visible, "Schritt 1: Starter-Kit, Tafel sichtbar")
check(panel and panel:FindFirstChild("Step", true).Text == "TUTORIAL  ·  STEP 1/6", "Schrittzähler 1/6")
local waypoint = playerGui:FindFirstChild("TutorialWaypoint")
check(waypoint ~= nil and waypoint.Enabled and waypoint.Adornee ~= nil and waypoint.Adornee ~= farKits,
	"Wegpunkt zum nächsten Kit-Händler")

-- bleibt stehen, bis eine Waffe in der Tasche ist
step(2)
check(ExtTutorial.CurrentStep() == "Kit", "Kit-Schritt wartet")
bob:SetAttribute("ExtBag", HttpService:JSONEncode({ { S = 2, Id = "Pistol", N = 1 }, { S = 6, Id = "Bandage", N = 5 } }))
step(0.4)
check(ExtTutorial.CurrentStep() == "Inventory", "Schritt 2: Inventar")
check(not waypoint.Enabled, "Wegpunkt weg")

key(Enum.KeyCode.Tab)
step(0.4)
check(ExtTutorial.CurrentStep() == "Equip", "TAB: Schritt 3, Waffe in die Hand")
check(not panel.Visible, "Tafel aus, solange das Menü offen ist")
key(Enum.KeyCode.Tab)
step(0.4)
check(panel.Visible, "Tafel wieder da")
local body = panel:FindFirstChild("Text", true).Text
check(string.find(body, "[2]", 1, true) ~= nil, "Text nennt die Taste der Waffe (2): " .. body)
bob:SetAttribute("ExtEquipped", 2)
step(0.4)
check(ExtTutorial.CurrentStep() == "Leave", "Schritt 4: Safe Zone verlassen")
bob:SetAttribute("InSafeZone", false)
step(0.4)
check(ExtTutorial.CurrentStep() == "Zombie", "Schritt 5: Zombie töten")
step(1)
check(ExtTutorial.CurrentStep() == "Zombie", "Zombie-Schritt wartet")
bob:SetAttribute("ZombieKills", (bob:GetAttribute("ZombieKills") or 0) + 1)
step(0.4)
check(ExtTutorial.CurrentStep() == "Ready", "Schritt 6: Schluss")
step(13)
check(not ExtTutorial.IsActive() and not panel.Visible, "Tutorial fertig")
check(sentTutorial() == "Done", "fertig an den Server gemeldet")

-- außerhalb der offenen Welt keine Tafel
ExtTutorial.Start(false)
step(0.3)
check(panel.Visible, "neu gestartet")
bob:SetAttribute("Mode", "Hub")
step(0.4)
check(not panel.Visible, "im Hub keine Tafel")
bob:SetAttribute("Mode", "Extinction")
ExtTutorial.Stop()
step(0.3)
check(not ExtTutorial.IsActive(), "Stop beendet es")

if failures == 0 then
	print("Tutorial: alles in Ordnung")
end

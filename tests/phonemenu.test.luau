-- Menü der offenen Welt am Handy (Bildschirm niedriger als 560 px): eigene Leinwand (Höhe 520 statt 900), damit alles
-- größer ist; das Menü füllt den Bildschirm, die Reiter stehen als Leiste oben (wischen), der Inhalt scrollt.
-- Am PC bleibt alles wie gehabt (zurück auf 1920 × 1080: Leinwand 1600 × 900, Seitenleiste links).
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
workspace.CurrentCamera.ViewportSize = Vector2.new(844, 390) -- Handy quer
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
local function key(code)
	local input = { KeyCode = code, UserInputType = Enum.UserInputType.Keyboard }
	UserInputService.InputBegan:Fire(input, false)
	step(0.05)
	UserInputService.InputEnded:Fire(input, false)
	step(0.1)
end
local windowGui = playerGui:FindFirstChild("ExtinctionWindow")
local canvas = windowGui:FindFirstChildOfClass("Frame")
for _, child in windowGui:GetChildren() do
	if child:IsA("Frame") and child:FindFirstChildOfClass("UIScale") then
		canvas = child
	end
end
local function menu()
	return windowGui and windowGui.Enabled and windowGui:FindFirstChild("Menu", true) or nil
end

local scale = canvas:FindFirstChildOfClass("UIScale").Scale
check(canvas.Size.Y.Offset == 520 and scale > 0.7, ("Leinwand am Handy 520 hoch, Maßstab > 0.7 (statt 0.43): %d, %.2f")
	:format(canvas.Size.Y.Offset, scale))
check(math.abs(canvas.Size.X.Offset * scale - 844) < 2, "Leinwand so breit wie der Bildschirm")

key(Enum.KeyCode.Tab)
local m = menu()
check(m ~= nil, "TAB öffnet das Menü")
check(m and m.Size.X.Offset == canvas.Size.X.Offset and m.Size.Y.Offset == canvas.Size.Y.Offset, "Menü füllt den Bildschirm")
local tabs = m and m:FindFirstChild("Tabs", true)
check(tabs ~= nil and tabs:IsA("ScrollingFrame") and tabs.ScrollingDirection == Enum.ScrollingDirection.X, "Reiter als Leiste zum Wischen")
check(tabs and tabs.Parent.Position.Y.Offset == 0 and tabs.Parent.Size.X.Scale == 1, "Reiter-Leiste oben über die ganze Breite")
local content = m and m:FindFirstChild("Content", true)
check(content ~= nil and content:IsA("ScrollingFrame"), "Inhalt scrollt")
local bar = m and m:FindFirstChild("Sidebar")
check(bar and bar:FindFirstChild("Close") ~= nil and bar:FindFirstChild("Coins") ~= nil, "Münzen und X oben in der Leiste")
-- Inventar: Kopfzeile bleibt (Filter), Inhalt ist höher als der Platz und scrollt
step(0.5)
check(content and content.CanvasSize.Y.Offset > content.Size.Y.Offset, "Inventar höher als der Platz: Scrollfläche wächst mit ("
	.. tostring(content and content.CanvasSize.Y.Offset) .. ")")
-- Reiter wechseln über die Leiste
tabs:FindFirstChild("Tab_Stats").Activated:Fire()
step(0.5)
m = menu()
local underline = m and m:FindFirstChild("Tab_Stats", true) and m:FindFirstChild("Tab_Stats", true):FindFirstChild("Underline")
check(underline ~= nil and underline.Visible, "STATISTIK aktiv")
local header = m and m:FindFirstChild("Header", true)
check(header ~= nil and not header.Visible, "STATISTIK: leere Kopfzeile fällt weg")
key(Enum.KeyCode.Tab)
check(menu() == nil, "TAB schließt")

-- zurück auf PC-Größe: Seitenleiste links wie gehabt
workspace.CurrentCamera.ViewportSize = Vector2.new(1920, 1080)
step(0.2)
check(canvas.Size.Y.Offset == 900 and canvas.Size.X.Offset == 1600, "PC: Leinwand 1600 × 900")
key(Enum.KeyCode.Tab)
m = menu()
tabs = m and m:FindFirstChild("Tabs", true)
check(tabs ~= nil and not tabs:IsA("ScrollingFrame") and tabs.Parent.Name == "Sidebar", "PC: Reiter in der Seitenleiste")
check(m and m:FindFirstChild("Content", true) and not m:FindFirstChild("Content", true):IsA("ScrollingFrame"), "PC: Inhalt ohne Scrollen")
key(Enum.KeyCode.Tab)

if failures == 0 then
	print("Menü am Handy in Ordnung")
end

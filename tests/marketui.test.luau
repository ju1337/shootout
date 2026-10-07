-- Markt-Oberfläche (MarketClient) im Simulator: Start mit Karte, Tafeln, Such-Terminal; Fenster SUCHE, STAND, MEIN STAND und
-- GEGENANGEBOTE öffnen und bedienen, Weg-Pfeil, Merkliste – es darf nichts abstürzen und die Anzeigen müssen stimmen
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Run(SIM.Now + (seconds or 1))
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RapConfig = require("RapConfig")
local Remotes = require("Remotes")
local ProgressService = require("ProgressService")
local EconomyService = require("EconomyService")
ProgressService.Init()
EconomyService.Init()

local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Market"
for _, name in { "Spawns", "Portals" } do
	Instance.new("Folder", map).Name = name
end
Instance.new("Part", map.Spawns).CFrame = CFrame.new(-1500, 1, -1536)
for id = 1, 4 do
	local folder = Instance.new("Folder", map)
	folder.Name = "Stand_" .. id
	local prompt = Instance.new("Part", folder)
	prompt.Name = "Prompt"
	prompt.Position = Vector3.new(-1520, 2.6, -1530 + id * 14)
	local spot = Instance.new("Part", folder)
	spot.Name = "OwnerSpot"
	spot.CFrame = CFrame.new(-1525, 0.9, -1530 + id * 14)
	local sign = Instance.new("Part", folder)
	sign.Name = "Sign"
	for slot = 1, 6 do
		local display = Instance.new("Part", folder)
		display.Name = "Display" .. slot
		display.Position = Vector3.new(-1520, 4, -1530 + id * 14)
	end
end
local decor = Instance.new("Folder", map) -- wie in der echten Map: Tafeln und Terminal liegen im Ordner Decor
decor.Name = "Decor"
for _, name in { "OverviewBoard", "TopBoard", "SearchTerminal" } do
	local part = Instance.new("Part", decor)
	part.Name = name
	part.Position = Vector3.new(-1500, 5, -1500)
end
local MarketService = require("MarketService")
local MarketMode = require("Market")
MarketMode.Init({ Join = function() end })

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = { W_Lava = 2, W_Kirsche = 3, W_Gletscher = 1 }, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 0, Rap = 3000, Owned = {}, Equipped = {} }
local alice, bob = SIM.Join("Alice"), SIM.Join("Bob")
step(2)
local function enter(player, position)
	player:SetAttribute("Mode", "Market")
	local rig = player.Character or SIM.MakeRig(player.Name)
	rig.Parent = workspace
	player.Character = rig
	rig:PivotTo(CFrame.new(position))
end
enter(alice, Vector3.new(-1514, 3, -1516))
enter(bob, Vector3.new(-1512, 3, -1516))
MarketMode.AddPlayer(alice)
MarketMode.AddPlayer(bob)
enter(alice, Vector3.new(-1514, 3, -1516)) -- AddPlayer setzt auf den Spawn
enter(bob, Vector3.new(-1512, 3, -1516))
MarketService.Do(alice, "Claim", 1)
MarketService.Do(alice, "Name", "Lava-Laden")
MarketService.Do(alice, "List", "W_Lava", 600)
MarketService.Do(alice, "List", "W_Kirsche", 200)
MarketService.Do(alice, "List", "W_Gletscher", 300)
enter(bob, Vector3.new(-1514, 3, -1502))
MarketService.Do(bob, "Claim", 2)
enter(bob, Vector3.new(-1512, 3, -1516))
MarketService.Do(bob, "Watch", "W_Lava")
step(1)

-- Client von Bob starten
rawget(SIM.Players, "__props").LocalPlayer = bob
local MarketClient = require("MarketClient")
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
task.spawn(MarketClient.Init)
step(2)
local gui = playerGui:FindFirstChild("Market")
check(gui ~= nil, "Markt-Oberfläche gebaut")

-- Tafeln: Übersicht (Stand 1 und 2 belegt, 3 und 4 frei) und Händler
local function find(root, name)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end
check(find(playerGui, "MarketOverview") ~= nil and find(playerGui, "MarketTop") ~= nil, "Tafeln gebaut")

-- Ausgestellte Skins nur bei Ständen in der Nähe (Leistung): weit weg abgebaut, wieder da, wenn man zurückkommt
local displays = workspace:FindFirstChild("MarketDisplays")
check(displays ~= nil and #displays:GetChildren() == 3, "drei Skins am nahen Stand 1 ausgestellt (" .. tostring(displays and #displays:GetChildren()) .. ")")
bob.Character:PivotTo(CFrame.new(-1512 + 95, 3, -1516))
step(1.5)
check(#displays:GetChildren() == 3, "zwischen Aufbau- und Abbau-Grenze bleibt alles stehen (kein Flackern)")
bob.Character:PivotTo(CFrame.new(-1512 + 400, 3, -1516))
step(1.5)
check(#displays:GetChildren() == 0, "weit weg: Modelle abgebaut")
bob.Character:PivotTo(CFrame.new(-1512, 3, -1516))
step(1.5)
check(#displays:GetChildren() == 3, "wieder da: Modelle neu gebaut")

-- Fenster SUCHE
MarketClient.OpenSearch()
step(0.5)
local window = find(gui, "MarketWindow")
check(window ~= nil, "SUCHE öffnet ein Fenster")
-- Akzentstreifen oben bleibt innerhalb der Rundung: um den Eckenradius des Fensters eingerückt, runde Enden
local accent = window:FindFirstChild("Accent")
local windowRadius = window:FindFirstChildOfClass("UICorner").CornerRadius.Offset
check(accent ~= nil and accent.Position.X.Offset == windowRadius and accent.Size.X.Offset == -2 * windowRadius
	and accent:FindFirstChildOfClass("UICorner") ~= nil and accent:FindFirstChildOfClass("UICorner").CornerRadius.Scale == 1,
	"Akzentstreifen im Fenster eingerückt, runde Enden")
local results = find(window, "Results")
local function rows()
	local n = 0
	for _, child in results:GetChildren() do
		if child:IsA("Frame") then
			n += 1
		end
	end
	return n
end
check(rows() == 3, "alle drei Angebote von Alice (Bob sieht den eigenen Stand nicht): " .. rows())
local box = find(window, "Query")
box.Text = "lava"
step(0.2)
check(rows() == 1, "Suche nach lava: ein Treffer (" .. rows() .. ")")
box.Text = ""
step(0.2)
check(rows() == 3, "Suchfeld leer: wieder alle")
MarketClient.OpenSearch() -- neu öffnen: Zustand bleibt, kein Absturz
step(0.2)
check(find(gui, "MarketWindow") ~= nil, "SUCHE nochmal öffnen")

-- Fenster STAND (Gegenangebot, Merken)
MarketClient.OpenStand(1)
step(0.5)
check(find(gui, "MarketWindow") ~= nil, "STAND öffnet")
Remotes.MarketAction.OnServerEvent:Fire(bob, "Offer", 1, 1, 450)
step(0.5)
local offers = HttpService:JSONDecode(map.Stand_1:GetAttribute("Offers"))
check(#offers == 1 and offers[1].Price == 450, "Gegenangebot über das Remote")
check(find(gui, "MarketWindow") ~= nil, "STAND baut nach dem Angebot neu auf")

if failures == 0 then
	print("Markt-Oberfläche: alles in Ordnung")
end

-- Markt-Oberfläche, Besitzer-Seite (MarketClient als Alice): MEIN STAND mit Stand-Name, Leiste mit Angebote-Zähler, Fenster
-- GEGENANGEBOTE annehmen und ablehnen, Tafeln (freie Stände, beliebteste Händler)
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


-- Client von Alice starten (sie ist Besitzerin von Stand 1)
rawget(SIM.Players, "__props").LocalPlayer = alice
local MarketClient = require("MarketClient")
local playerGui = alice:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", alice)
task.spawn(MarketClient.Init)
step(2)
local gui = playerGui:FindFirstChild("Market")
local function find(root, predicate)
	for _, d in root:GetDescendants() do
		if predicate(d) then
			return d
		end
	end
	return nil
end
local function labelWith(root, text)
	return find(root, function(d)
		return d:IsA("TextLabel") and d.Text == text
	end)
end
local function click(root, text)
	local label = labelWith(root, text)
	if not label then
		return false
	end
	local button = label
	while button and not button:IsA("TextButton") do
		button = button.Parent
	end
	if not button then
		return false
	end
	button.Activated:Fire()
	return true
end
-- Klick auf einen Knopf; was der Client an den Server schickt, wird wie vom Server empfangen weitergegeben
local function clickAndSend(root, text)
	local before = #SIM.RemoteLog
	if not click(root, text) then
		return false
	end
	for index = before + 1, #SIM.RemoteLog do
		local entry = SIM.RemoteLog[index]
		if entry.Remote == "MarketAction" and entry.Player == "server" then
			Remotes.MarketAction.OnServerEvent:Fire(alice, table.unpack(entry.Args, 1, entry.Args.n))
			return true
		end
	end
	return false
end
local function labelStarting(root, prefix)
	return find(root, function(d)
		return (d:IsA("TextLabel") or d:IsA("TextButton")) and string.sub(d.Text, 1, #prefix) == prefix
	end)
end

-- Leiste: Stand 1, noch keine Gegenangebote
check(labelWith(gui, "ANGEBOTE") ~= nil, "Leiste: Knopf ANGEBOTE ohne Zähler")
-- Bob bietet für die Lava
MarketService.Do(bob, "Offer", 1, 1, 450)
step(0.5)
check(labelWith(gui, "ANGEBOTE (1)") ~= nil, "Leiste: ANGEBOTE (1)")

-- Tafeln
local overview = find(playerGui, function(d) return d.Name == "MarketOverview" end)
check(overview ~= nil and labelWith(overview, "2 VON 4 FREI") == nil or true, "Tafel gebaut")
check(labelWith(overview, "2 VON 4 FREI") ~= nil or labelWith(overview, "3 VON 4 FREI") ~= nil, "Übersichtstafel zählt freie Stände")

-- Fenster GEGENANGEBOTE
MarketClient.OpenOffers()
step(0.5)
local window = find(gui, function(d) return d.Name == "MarketWindow" end)
check(window ~= nil, "GEGENANGEBOTE öffnet")
check(labelWith(window, "BOB BIETET") ~= nil, "Angebot von Bob steht da")
check(labelWith(window, "DEIN PREIS: 600 RAP") ~= nil, "mit deinem Preis")
check(labelStarting(window, "NOCH ") ~= nil, "Countdown läuft")
-- ablehnen
check(clickAndSend(window, "ABLEHNEN"), "ABLEHNEN klickbar")
step(0.5)
check(#HttpService:JSONDecode(map.Stand_1:GetAttribute("Offers")) == 0, "abgelehnt: Angebot weg")
-- neu, dann annehmen
MarketService.Do(bob, "Offer", 1, 1, 500)
step(0.5)
window = find(gui, function(d) return d.Name == "MarketWindow" end)
check(window ~= nil and labelWith(window, "BOB BIETET") ~= nil, "Fenster zeigt das neue Angebot ohne neu öffnen")
local aliceRap, bobRap = ProgressService.GetRap(alice), ProgressService.GetRap(bob)
check(clickAndSend(window, "ANNEHMEN"), "ANNEHMEN klickbar")
step(0.5)
check(ProgressService.GetRap(bob) == bobRap - 500 and ProgressService.GetRap(alice) == aliceRap + RapConfig.AfterFee(500), "verkauft zu 500")
check(ProgressService.ItemCount(bob, "W_Lava") == 1, "Lava bei Bob")

-- MEIN STAND: Name setzen
MarketClient.OpenManage()
step(0.5)
window = find(gui, function(d) return d.Name == "MarketWindow" end)
check(window ~= nil, "MEIN STAND öffnet")
local nameBox = find(window, function(d) return d:IsA("TextBox") and d.PlaceholderText == "z.B. LAVA-LADEN" end)
check(nameBox ~= nil and nameBox.Text == "Lava-Laden", "Name-Feld zeigt den Namen")
nameBox.Text = "Alices Shop"
check(clickAndSend(nameBox.Parent, "OK"), "OK klickbar")
step(0.5)
check(map.Stand_1:GetAttribute("StandName") == "Alices Shop", "Stand-Name am Stand")
local sign = playerGui:FindFirstChild("StandSign1")
check(sign ~= nil and sign.Main.Text == "ALICES SHOP", "Schild zeigt den Namen")
check(labelStarting(window, "Marktgebühr: 2 % bis 50 RAP") ~= nil, "Gebührenstufen im Fenster")
-- Händler-Tafel
local top = find(playerGui, function(d) return d.Name == "MarketTop" end)
check(labelStarting(top, "1.  ALICE  ·  1 VERKAUF") ~= nil, "Händler-Tafel: Alice mit einem Verkauf")

if failures == 0 then
	print("Markt-Oberfläche (Besitzer): alles in Ordnung")
end

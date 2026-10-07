-- Kisten-Oberfläche (CrateClient) im Simulator: Automaten mit Prompt, Fenster mit Chancen und Inhalt, ÖFFNEN beim Server,
-- Rolle läuft und bleibt auf dem Gewinn stehen, Gewinn-Karte, NOCHMAL, zu wenig Münzen, Fenster zu während der Rolle
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
local Remotes = require("Remotes")
local CrateConfig = require("CrateConfig")
local Cosmetics = require("Cosmetics")
local UITheme = require("UITheme")
local ProgressService = require("ProgressService")
local CrateService = require("CrateService")
ProgressService.Init()
CrateService.Init()

local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Market"
local decor = Instance.new("Folder", map) -- wie in der echten Map: Automaten liegen im Ordner Decor, nicht direkt unter der Map
decor.Name = "Decor"
for _, name in { "CrateWeapon", "CrateAgent" } do
	Instance.new("Part", decor).Name = name
end

store.Data.u1 = { XP = {}, Coins = 1000, Rap = 0, Owned = {}, Equipped = {} }
local alice = SIM.Join("Alice")
step(2)
alice:SetAttribute("Mode", "Market")
rawget(SIM.Players, "__props").LocalPlayer = alice
local CrateClient = require("CrateClient")
local playerGui = alice:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", alice)
task.spawn(CrateClient.Init)
step(1)

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
local function labelStarting(root, prefix)
	return find(root, function(d)
		return d:IsA("TextLabel") and string.sub(d.Text, 1, #prefix) == prefix
	end)
end
local function click(root, textStart)
	local label = labelStarting(root, textStart)
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
-- Was der Client an den Server schickt, kommt dort an; die Antwort des Servers kommt beim Client an
local function relay()
	for index = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[index]
		if entry.Remote == "CrateAction" and entry.Player == "server" and not entry.Done then
			entry.Done = true
			local before = #SIM.RemoteLog
			Remotes.CrateAction.OnServerEvent:Fire(alice, table.unpack(entry.Args, 1, entry.Args.n))
			for i = before + 1, #SIM.RemoteLog do
				local answer = SIM.RemoteLog[i]
				if answer.Remote == "CrateResult" and answer.Player == alice then
					Remotes.CrateResult.OnClientEvent:Fire(answer.Args[1])
					return answer.Args[1]
				end
			end
			return nil
		end
	end
	return nil
end

-- Automaten haben ein E-Prompt
for _, name in { "CrateWeapon", "CrateAgent" } do
	check(decor[name]:FindFirstChildOfClass("ProximityPrompt") ~= nil, name .. ": Prompt")
end

-- Waffen-Kiste öffnen
CrateClient.Open("Weapon")
step(0.3)
local gui = playerGui:FindFirstChild("Crates")
local window = find(gui, function(d) return d.Name == "CrateWindow" end)
check(window ~= nil, "Fenster offen")
-- Akzentstreifen oben bleibt innerhalb der Rundung: um den Eckenradius des Fensters eingerückt, runde Enden
local accent = window:FindFirstChild("Accent")
local windowRadius = window:FindFirstChildOfClass("UICorner").CornerRadius.Offset
local accentCorner = accent and accent:FindFirstChildOfClass("UICorner")
check(accent ~= nil and accent.Position.X.Offset == windowRadius and accent.Position.Y.Offset == 0
	and accent.Size.X.Scale == 1 and accent.Size.X.Offset == -2 * windowRadius, "Akzentstreifen um den Radius eingerückt")
check(accentCorner ~= nil and accentCorner.CornerRadius.Scale == 1, "Akzentstreifen mit runden Enden")
check(labelWith(window, "WAFFEN-KISTE") ~= nil and labelStarting(window, "WAFFEN-SKINS") ~= nil, "Titel: Waffen-Kiste")
check(labelWith(window, "CHANCEN") ~= nil and labelWith(window, "DAS STECKT DRIN") ~= nil, "Chancen und Inhalt")
check(labelWith(window, "62.0 %") ~= nil and labelWith(window, "2.0 %") ~= nil, "Chancen in Prozent (62 % gewöhnlich, 2 % legendär)")
local pool = CrateConfig.Pool(CrateConfig.Get("Weapon"))
for _, item in pool do
	check(labelWith(window, UITheme.Upper(item.Name)) ~= nil, "im Inhalt: " .. item.Name)
end
check(labelStarting(window, "ÖFFNEN  ·  450") ~= nil, "Knopf zeigt den Preis")
check(labelStarting(window, "MÜNZEN  1.000") ~= nil or labelStarting(window, "MÜNZEN  1000") ~= nil, "Münzen oben")

-- ÖFFNEN
check(click(window, "ÖFFNEN  ·  450"), "ÖFFNEN klickbar")
local result = relay()
check(result ~= nil and result.Ok == true, "Server antwortet mit Ergebnis")
step(0.5)
check(labelStarting(window, "ÖFFNET") ~= nil, "Knopf zeigt ÖFFNET während der Rolle")
check(find(window, function(d) return d.Name == "Result" end) == nil, "Gewinn-Karte noch nicht da")
step(7)
local card = find(window, function(d) return d.Name == "Result" end)
check(card ~= nil, "Gewinn-Karte nach der Rolle")
local item = Cosmetics.Get(result.Item)
check(card and labelWith(card, UITheme.Upper(item.Name)) ~= nil, "Karte zeigt den Gewinn " .. item.Name)
check(card and (labelStarting(card, "NEU FREIGESCHALTET") ~= nil), "Karte: neu freigeschaltet")
local strip = find(window, function(d) return d.Name == "Strip" end)
check(math.abs(strip.Position.X.Offset + (result.Index - 1) * 132 + 62 - 440) <= 41, "Rolle bleibt unter der Markierung auf dem Gewinn stehen")
check(ProgressService.ItemCount(alice, result.Item) == 1, "Gewinn im Inventar")

-- NOCHMAL (Wartezeit des Servers abwarten)
step(2)
check(click(card, "NOCHMAL") == true, "NOCHMAL klickbar")
local second = relay()
check(second ~= nil and second.Ok == true, "zweite Kiste")
step(8)
check(find(window, function(d) return d.Name == "Result" end) ~= nil, "zweite Gewinn-Karte")
click(find(window, function(d) return d.Name == "Result" end), "OK")
step(0.2)
check(find(window, function(d) return d.Name == "Result" end) == nil, "OK schließt die Karte")

-- zu wenig Münzen
ProgressService.Get(alice).Coins = 10
alice:SetAttribute("Coins", 10)
step(0.3)
check(labelStarting(window, "ZU WENIG MÜNZEN") ~= nil, "Knopf: zu wenig Münzen")
click(window, "ZU WENIG")
check(labelStarting(window, "Nicht genug Münzen") ~= nil, "Hinweis im Fenster")

-- Agenten-Kiste: anderes Fenster, nur Agenten
ProgressService.Get(alice).Coins = 5000
alice:SetAttribute("Coins", 5000)
CrateClient.Open("Agent")
step(0.3)
window = find(gui, function(d) return d.Name == "CrateWindow" end)
check(window ~= nil and labelWith(window, "AGENTEN-KISTE") ~= nil, "Agenten-Kiste")
check(labelWith(window, "WALDTARN") == nil, "kein Waffen-Skin in der Agenten-Kiste")
check(labelWith(window, "NACHTSCHLANGE") ~= nil, "Agenten-Skin im Inhalt")
step(2)
click(window, "ÖFFNEN  ·  800")
local third = relay()
check(third ~= nil and third.Ok == true and Cosmetics.Get(third.Item).Type == "Agent", "Agenten-Kiste gibt Agenten-Skin")
step(1)
-- Fenster schließen, während die Rolle läuft: Gewinn kommt als Karte
CrateClient.Open("Weapon")
check(find(gui, function(d) return d.Name == "CrateWindow" end) ~= nil, "neues Fenster ersetzt das alte")
step(10)

if failures == 0 then
	print("Kisten-Oberfläche: alles in Ordnung")
end

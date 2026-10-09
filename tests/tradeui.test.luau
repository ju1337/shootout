-- Tausch-Oberfläche (TradeClient): Spielerliste mit T, Entfernung, TAUSCH ANFRAGEN schickt die Anfrage, zu weit weg ist gesperrt,
-- Hinweis nur im Hub/Markt, Esc schließt
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
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RapConfig = require("RapConfig")
local ProgressService = require("ProgressService")
ProgressService.Init()

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u3 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local alice, bob, carl = SIM.Join("Alice"), SIM.Join("Bob"), SIM.Join("Carl")
step(2)
local function place(player, mode, position)
	player:SetAttribute("Mode", mode)
	local rig = player.Character or SIM.MakeRig(player.Name)
	rig.Parent = workspace
	player.Character = rig
	rig:PivotTo(CFrame.new(position))
end
place(alice, "Market", Vector3.new(0, 3, 0))
place(bob, "Market", Vector3.new(12, 3, 0))
place(carl, "Market", Vector3.new(RapConfig.TradeRange + 30, 3, 0))
bob:SetAttribute("RapValue", 1234)

rawget(SIM.Players, "__props").LocalPlayer = alice
local TradeClient = require("TradeClient")
local playerGui = alice:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", alice)
TradeClient.Init()
step(0.5)

local function find(root, predicate)
	for _, d in root:GetDescendants() do
		if predicate(d) then
			return d
		end
	end
	return nil
end
local function named(name)
	return find(playerGui, function(d) return d.Name == name end)
end
local function labelStarting(root, prefix)
	return find(root, function(d) return d:IsA("TextLabel") and string.sub(d.Text, 1, #prefix) == prefix end)
end
local function press(keyCode)
	UserInputService.InputBegan:Fire({ KeyCode = keyCode, UserInputType = Enum.UserInputType.Keyboard }, false)
end

-- Hinweis im Markt sichtbar
local hint = named("TradeHint")
check(hint ~= nil and hint.Visible == true, "Hinweis T im Markt sichtbar")

-- T öffnet die Liste
press(Enum.KeyCode.T)
step(0.3)
local window = named("TradeListWindow")
check(window ~= nil, "T öffnet die Spielerliste")
check(hint.Visible == false, "Hinweis weg, solange die Liste offen ist")
local bobRow, carlRow = named("Player" .. bob.UserId), named("Player" .. carl.UserId)
check(bobRow ~= nil and carlRow ~= nil and named("Player" .. alice.UserId) == nil, "Bob und Carl stehen drin, Alice (du) nicht")
check(labelStarting(bobRow, "INVENTAR  1.234") ~= nil or labelStarting(bobRow, "INVENTAR  1,234") ~= nil or labelStarting(bobRow, "INVENTAR  1234") ~= nil, "Inventarwert von Bob")
check(labelStarting(bobRow, "12 M") ~= nil, "Entfernung zu Bob")
check(labelStarting(carlRow, "ZU WEIT") ~= nil, "Carl ist zu weit weg")
check(bobRow.LayoutOrder < carlRow.LayoutOrder, "Nähere Spieler stehen oben")

-- Anfrage
local function click(row)
	local button = find(row, function(d) return d.Name == "RequestButton" end)
	button.Activated:Fire()
end
local before = #SIM.RemoteLog
click(carlRow)
check(#SIM.RemoteLog == before, "zu weit weg: keine Anfrage")
click(bobRow)
local sent = nil
for index = before + 1, #SIM.RemoteLog do
	local entry = SIM.RemoteLog[index]
	if entry.Remote == "TradeAction" and entry.Player == "server" then
		sent = entry.Args
	end
end
check(sent and sent[1] == "Request" and sent[2] == bob.UserId, "Anfrage an Bob geschickt")

-- Liste aktualisiert sich (Carl kommt näher)
place(carl, "Market", Vector3.new(5, 3, 0))
step(1.5)
carlRow = named("Player" .. carl.UserId)
check(carlRow ~= nil and labelStarting(carlRow, "TAUSCH ANFRAGEN") ~= nil, "Carl jetzt nah: TAUSCH ANFRAGEN")
-- Spieler in anderem Bereich fehlen
bob:SetAttribute("Mode", "Domination")
step(1.5)
check(named("Player" .. bob.UserId) == nil, "Bob ist in einer Runde: nicht in der Liste")

-- Esc und T schließen
press(Enum.KeyCode.Escape)
step(0.2)
check(named("TradeListWindow") == nil, "Esc schließt")
press(Enum.KeyCode.T)
step(0.2)
check(named("TradeListWindow") ~= nil, "T öffnet nochmal")
press(Enum.KeyCode.T)
step(0.2)
check(named("TradeListWindow") == nil, "T schließt")

-- Im Match geht es nicht
alice:SetAttribute("Mode", "Domination")
step(0.2)
check(hint.Visible == false, "Hinweis im Match weg")
press(Enum.KeyCode.T)
step(0.2)
check(named("TradeListWindow") == nil, "im Match keine Spielerliste")

if failures == 0 then
	print("Tausch-Oberfläche: alles in Ordnung")
end

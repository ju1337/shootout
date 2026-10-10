-- Controller im Tauschfenster (TradeClient, Spielerliste): Beim Öffnen landet die Auswahl (GuiService.SelectedObject)
-- auf dem ersten Knopf im Fenster – das Schließen-Kreuz oben rechts (NoFocus) wird übersprungen. Nach dem Neuaufbau
-- der Liste (jede Sekunde) bleibt die Auswahl im Fenster (Refocus), beim Schließen wird sie aufgehoben (Unfocus).
-- Mit Tastatur/Maus wird nichts ausgewählt.
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
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
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
place(bob, "Market", Vector3.new(10, 3, 0))
place(carl, "Market", Vector3.new(math.min(20, RapConfig.TradeRange - 2), 3, 0))

rawget(SIM.Players, "__props").LocalPlayer = alice
local playerGui = alice:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", alice)
local InputActions = require("InputActions")
local TradeClient = require("TradeClient")
InputActions.Init()
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
local function requestButton(player)
	local row = named("Player" .. player.UserId)
	return row and find(row, function(d) return d.Name == "RequestButton" end)
end
local function selected()
	return GuiService.SelectedObject
end
local function closeCross(window)
	for _, d in window:GetDescendants() do
		if d:IsA("GuiButton") and d:GetAttribute("NoFocus") then
			return d
		end
	end
	return nil
end

-- Tastatur: Öffnen wählt nichts aus
TradeClient.OpenPlayers()
step(0.3)
check(named("TradeListWindow") ~= nil, "Spielerliste offen")
check(selected() == nil, "Tastatur: keine Auswahl")
TradeClient.TogglePlayers()
step(0.2)
check(named("TradeListWindow") == nil, "Spielerliste zu")

-- Controller: Auswahl auf TAUSCH ANFRAGEN beim nächsten Spieler, nicht auf das Kreuz
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
check(InputActions.Device() == "Gamepad", "Gerät ist der Controller")
TradeClient.OpenPlayers()
local window = named("TradeListWindow")
check(selected() == nil, "Auswahl erst nach dem Aufbau (verzögert)")
step(0.1)
local cross = window and closeCross(window)
check(cross ~= nil and cross.Selectable, "Schließen-Kreuz hat NoFocus")
check(cross and cross.AbsolutePosition.Y < requestButton(bob).AbsolutePosition.Y, "Kreuz liegt oben (wäre sonst zuerst dran)")
check(selected() ~= nil and selected() ~= cross, "Auswahl nicht auf dem Schließen-Kreuz")
check(selected() == requestButton(bob), "Auswahl auf TAUSCH ANFRAGEN bei Bob (oben in der Liste)")
check(selected() and selected():IsDescendantOf(window), "Auswahl liegt im Fenster")

-- Ohne Änderung wird die Liste nicht neu gebaut (Klicks über einen Neuaufbau gingen sonst verloren)
local before = selected()
step(1.2)
check(before ~= nil and before.Parent ~= nil and selected() == before, "ohne Änderung bleibt der Knopf derselbe")

-- Neuaufbau der Liste (Zustand geändert): Auswahl bleibt im Fenster auf einem gültigen Knopf
bob:SetAttribute("RapValue", 1234)
step(1.2)
check(before ~= nil and before.Parent == nil, "alter Knopf beim Neuaufbau ersetzt")
check(selected() ~= nil and selected().Parent ~= nil and selected():IsDescendantOf(window), "nach dem Neuaufbau: Auswahl wieder im Fenster")
check(selected() ~= cross, "nach dem Neuaufbau: nicht auf dem Kreuz")

-- Auswahl auf Carl (zweite Zeile): Neuaufbau sollte sie dort lassen
GuiService.SelectedObject = requestButton(carl)
bob:SetAttribute("RapValue", 2345)
step(1.2)
check(selected() == requestButton(carl),
	"Neuaufbau: Auswahl bleibt auf Carl (nicht zurück auf " .. (selected() == requestButton(bob) and "Bob" or tostring(selected())) .. ")")

-- Refocus lässt eine gültige Auswahl im Fenster in Ruhe
local keep = requestButton(bob)
GuiService.SelectedObject = keep
InputActions.Refocus(window)
step(0.1)
check(selected() == keep, "Refocus: gültige Auswahl im Fenster bleibt")
-- Auswahl außerhalb des Fensters: Refocus holt sie ins Fenster
local outside = Instance.new("TextButton", playerGui:FindFirstChildWhichIsA("ScreenGui"))
outside.Size = UDim2.fromOffset(50, 50)
GuiService.SelectedObject = outside
InputActions.Refocus(window)
step(0.1)
check(selected() ~= outside and selected() and selected():IsDescendantOf(window), "Refocus: Auswahl außerhalb kommt ins Fenster")
outside:Destroy()

-- ○ schließt (mit Auswahl meldet Roblox die Taste als verarbeitet – processed = true)
local b = { KeyCode = Enum.KeyCode.ButtonB, UserInputType = Enum.UserInputType.Gamepad1 }
UserInputService.InputBegan:Fire(b, true)
UserInputService.InputEnded:Fire(b, true)
step(0.2)
check(named("TradeListWindow") == nil, "○ schließt die Spielerliste auch, wenn ein Knopf ausgewählt ist")

-- Schließen hebt die Auswahl auf
TradeClient.OpenPlayers()
step(0.1)
window = named("TradeListWindow")
check(selected() and selected():IsDescendantOf(window), "wieder geöffnet: Auswahl im Fenster")
TradeClient.TogglePlayers()
step(0.1)
check(named("TradeListWindow") == nil and selected() == nil, "Schließen: Auswahl aufgehoben")
-- Unfocus lässt eine Auswahl außerhalb des Fensters stehen
TradeClient.OpenPlayers()
step(0.1)
window = named("TradeListWindow")
local other = Instance.new("TextButton", playerGui:FindFirstChildWhichIsA("ScreenGui"))
other.Size = UDim2.fromOffset(50, 50)
GuiService.SelectedObject = other
TradeClient.TogglePlayers()
step(0.1)
check(selected() == other, "Unfocus: fremde Auswahl bleibt")
GuiService.SelectedObject = nil
other:Destroy()

-- Kreuz schließt per Klick weiterhin
TradeClient.OpenPlayers()
step(0.1)
window = named("TradeListWindow")
cross = closeCross(window)
cross.Activated:Fire()
step(0.1)
check(named("TradeListWindow") == nil and selected() == nil, "Kreuz schließt, Auswahl weg")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

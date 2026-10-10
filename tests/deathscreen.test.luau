-- Todesbildschirm der offenen Welt (DeathScreen): erscheint kurz nach dem Tod in Extinction mit Gegner (auch wenn die
-- Meldung des Servers vor dem Tod ankommt), Tasche (draußen: liegt an der Todesstelle, in der Safe Zone: nichts
-- verloren), Respawn-Ort (ExtHome) und Countdown; verschwindet beim Respawn; in anderen Modi nie.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local bob = SIM.Join("Bob")
rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
bob:SetAttribute("Mode", "Extinction")
bob:SetAttribute("ExtHome", "Safehouse Nord")
bob:LoadCharacter()
SIM.Advance(1, 20)

local Remotes = require("Remotes")
local DeathScreen = require("DeathScreen")
DeathScreen.Init()
SIM.Advance(0.5, 10)

local screen = playerGui:FindFirstChild("DeathScreen")
check(screen ~= nil and not screen.Enabled, "angelegt, aber aus")
local function find(name)
	for _, d in screen:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

-- draußen gestorben; die Meldung des Servers kommt vor dem Tod beim Client an
bob:SetAttribute("InSafeZone", false)
Remotes.DeathRecap.OnClientEvent:Fire("Alice", "Sturmgewehr", 40, nil, nil)
SIM.Advance(0.1, 2)
bob.Character.Humanoid.Health = 0
SIM.Advance(0.3, 6)
check(not DeathScreen.IsShown(), "nicht sofort (erst den Tod sehen)")
SIM.Advance(0.6, 12)
check(DeathScreen.IsShown(), "nach kurzer Zeit zu sehen")
local name = find("Name")
check(name ~= nil and name.Text == "ALICE", "Gegner: ALICE (" .. tostring(name and name.Text) .. ")")
check(find("Killer").Visible, "Gegner-Karte sichtbar")
check(string.find(find("Bag"):FindFirstChild("Title").Text, "TASCHE", 1, true) ~= nil, "Tasche liegt draußen")
check(find("Place").Text == "SAFEHOUSE NORD", "Respawn-Ort aus ExtHome")
local count = tonumber(find("Count").Text)
check(count ~= nil and count >= 1 and count <= 5, "Countdown läuft (" .. tostring(find("Count").Text) .. ")")

-- Respawn: weg
bob:LoadCharacter()
SIM.Advance(0.5, 10)
check(not DeathScreen.IsShown(), "beim Respawn weg")

-- in der Safe Zone gestorben, ohne Gegner: nichts verloren, keine Gegner-Karte
bob:SetAttribute("InSafeZone", true)
SIM.Advance(3, 30) -- ältere Meldung des Servers zählt nicht mehr
bob.Character.Humanoid.Health = 0
SIM.Advance(1, 20)
check(DeathScreen.IsShown(), "auch in der Safe Zone")
check(find("Bag"):FindFirstChild("Title").Text == "NICHTS VERLOREN", "Safe Zone: nichts verloren")
check(not find("Killer").Visible, "ohne Gegner keine Gegner-Karte")

-- im Dungeon gestorben: Tasche verloren (nicht "liegt an der Todesstelle")
bob:LoadCharacter()
SIM.Advance(0.5, 10)
bob:SetAttribute("InSafeZone", false)
bob:SetAttribute("Dungeon", "{}")
bob.Character.Humanoid.Health = 0
SIM.Advance(1, 20)
check(find("Bag"):FindFirstChild("Title").Text == "TASCHE IM DUNGEON VERLOREN", "Dungeon: Tasche verloren")
bob:SetAttribute("Dungeon", nil)

-- draußen mit leerer Tasche: nichts verloren
bob:LoadCharacter()
SIM.Advance(0.5, 10)
bob:SetAttribute("ExtBag", "[]")
bob.Character.Humanoid.Health = 0
SIM.Advance(1, 20)
check(find("Bag"):FindFirstChild("Title").Text == "NICHTS VERLOREN", "leere Tasche: nichts verloren")

-- anderer Modus: nie
bob:LoadCharacter()
bob:SetAttribute("Mode", "FreeForAll")
SIM.Advance(0.5, 10)
bob.Character.Humanoid.Health = 0
SIM.Advance(1.5, 30)
check(not DeathScreen.IsShown(), "in anderen Modi kein Todesbildschirm")

if failures == 0 then
	print("Todesbildschirm in Ordnung")
end

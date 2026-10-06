-- Match-HUD (HUD, MatchHUD) auf dem Client: Das eigene Porträt liegt über seiner Kachel (das HUD rechnet ZIndex für den
-- ganzen Bildschirm, sonst bleibt das Bild unsichtbar); die allgemeine Tastenzeile ist in der offenen Welt aus (dort
-- hat die Hotbar eine eigene, beide lägen übereinander); der Killfeed rückt dort unter die Redzone-Rangliste
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
bob:SetAttribute("Mode", "FreeForAll")
SIM.Advance(1, 20)

local HUD = require("HUD")
local function none()
	return nil
end
local weaponClient = { AmmoChanged = SIM.Signal(), Fired = SIM.Signal(), Hit = SIM.Signal(), GetWeapon = none,
	GetReloadProgress = none, GetAimBlend = function()
		return 0
	end, IsFirstPerson = function()
		return false
	end, GetSpread = function()
		return 0
	end }
HUD.Init(weaponClient)
SIM.Advance(1, 20)

local screen = playerGui:FindFirstChild("HUD")
check(screen ~= nil, "HUD angelegt")
local function find(root, name)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

-- Porträt: höherer ZIndex als jede Fläche darunter (Kachel, Lebensanzeige)
local portrait = find(screen, "Portrait")
check(portrait ~= nil, "Porträt in der Lebensanzeige")
if portrait then
	local highest = 0
	local parent = portrait.Parent
	while parent and parent ~= screen do
		if parent:IsA("GuiObject") and parent.BackgroundTransparency < 1 then
			highest = math.max(highest, parent.ZIndex)
		end
		parent = parent.Parent
	end
	check(highest > 0 and portrait.ZIndex > highest, "Porträt über seiner Kachel (" .. portrait.ZIndex .. " > " .. highest .. ")")
end

-- Tastenzeile und Killfeed im Kampfmodus
local keyHints = find(screen, "KeyHints")
local killfeed = find(screen, "Killfeed")
check(keyHints ~= nil and keyHints.Visible and string.find(keyHints.Text, "SCHIESSEN", 1, true) ~= nil, "Tastenzeile im Kampfmodus")
check(killfeed ~= nil and killfeed.Position.Y.Offset < 200, "Killfeed rechts oben (" .. (killfeed and killfeed.Position.Y.Offset or -1) .. ")")

-- Offene Welt: eigene Tastenzeile unter der Hotbar, Rangliste rechts oben
bob:SetAttribute("Mode", "Extinction")
SIM.Advance(0.2, 20)
check(not keyHints.Visible, "keine allgemeine Tastenzeile in der offenen Welt")
check(killfeed.Position.Y.Offset >= 244, "Killfeed unter der Redzone-Rangliste (" .. killfeed.Position.Y.Offset .. ")")

bob:SetAttribute("Mode", "FreeForAll")
SIM.Advance(0.2, 20)
check(keyHints.Visible and killfeed.Position.Y.Offset < 200, "zurück im Kampfmodus: Tastenzeile und Killfeed wie vorher")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

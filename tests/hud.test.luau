-- Match-HUD (HUD, MatchHUD) auf dem Client: Das eigene Porträt liegt über seiner Kachel (das HUD rechnet ZIndex für den
-- ganzen Bildschirm, sonst bleibt das Bild unsichtbar); die allgemeine Tastenzeile ist in der offenen Welt aus (dort
-- hat die Hotbar eine eigene, beide lägen übereinander); der Killfeed rückt in der roten Zone unter die Rangliste; die
-- Minimap zeigt die rote Zone als roten Punktkreis, der bei jedem Wechsel mitzieht, und färbt ihren Rand drinnen rot
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

-- Offene Welt: eigene Tastenzeile unter der Hotbar; in einer roten Zone steht rechts oben die Rangliste, der Killfeed
-- rückt dann darunter
bob:SetAttribute("Mode", "Extinction")
SIM.Advance(0.2, 20)
check(not keyHints.Visible, "keine allgemeine Tastenzeile in der offenen Welt")
check(killfeed.Position.Y.Offset < 200, "außerhalb roter Zonen Killfeed oben (" .. killfeed.Position.Y.Offset .. ")")
bob:SetAttribute("Redzone", "Redzone")
SIM.Advance(0.2, 20)
check(killfeed.Position.Y.Offset >= 244, "in der roten Zone Killfeed unter der Rangliste (" .. killfeed.Position.Y.Offset .. ")")
bob:SetAttribute("Redzone", nil)
SIM.Advance(0.2, 20)
check(killfeed.Position.Y.Offset < 200, "Zone verlassen: Killfeed wieder oben")

bob:SetAttribute("Mode", "FreeForAll")
SIM.Advance(0.2, 20)
check(keyHints.Visible and killfeed.Position.Y.Offset < 200, "zurück im Kampfmodus: Tastenzeile und Killfeed wie vorher")

-- Minimap in der offenen Welt (Karten-Attribut Redzones)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", Vector3.new(0, 0, 0))
bob:SetAttribute("MapId", "Extinction")
bob:SetAttribute("Mode", "Extinction")
workspace.CurrentCamera.Focus = CFrame.new(0, 0, 0) -- Mitte der Minimap (ohne Charakter: Fokus der Kamera)
SIM.IsServer = false -- Client-Takt (RenderStepped)
local RED = Color3.fromRGB(226, 56, 48)
local minimap = find(screen, "Minimap")
local function redDots()
	local list = {}
	for _, d in minimap and minimap:GetDescendants() or {} do
		if d:IsA("Frame") and d.BackgroundColor3 == RED and d.Size == UDim2.fromOffset(4, 4) then
			table.insert(list, d)
		end
	end
	return list
end
local function ringRed()
	for _, d in minimap and minimap:GetDescendants() or {} do
		if d:IsA("UIStroke") and d.Color == RED then
			return true
		end
	end
	return false
end
map:SetAttribute("Redzones", '[{"Name":"Redzone","Title":"Nordheim","X":0,"Z":60,"R":170,"Ends":0}]')
SIM.Advance(1.2, 20)
local first = redDots()
check(minimap ~= nil and minimap.Visible and #first >= 12, "rote Zone als Punktkreis auf der Minimap (" .. #first .. ")")
check(ringRed(), "in der roten Zone: Rand der Minimap rot")
map:SetAttribute("Redzones", '[{"Name":"Redzone","Title":"Altenfeld","X":900,"Z":900,"R":170,"Ends":0}]')
SIM.Advance(1.2, 20)
local second = redDots()
check(#second == #first and first[1] ~= nil and first[1].Parent == nil, "Wechsel: alte Punkte weg, gleich viele am neuen Ort")
check(second[1] ~= nil and second[1].Position.X.Scale > first[1].Position.X.Scale, "neue Punkte liegen am neuen Ort")
check(not ringRed(), "draußen: Rand nicht mehr rot")
map:SetAttribute("Redzones", "[]")
SIM.Advance(1.2, 20)
check(#redDots() == 0, "ohne rote Zone keine roten Punkte")
SIM.IsServer = true

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

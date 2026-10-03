-- HitFeedback: Treffer-Art, alle Hitmarker- und Schadenszahl-Stile laufen fehlerfrei durch und räumen auf,
-- Kombo lässt den Ton steigen, Kill setzt sie zurück, Vorschau der Seite OPTIONEN
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Run(SIM.Now + seconds)
end

-- Lokaler Spieler mit PlayerGui (HitFeedback ist ein Client-Modul)
local player = SIM.AddPlayer("Spieler")
Instance.new("Folder", player).Name = "PlayerGui"
rawget(SIM.Players, "__props").LocalPlayer = player
local HitFeedback = require("HitFeedback")
local PlayerSettings = require("PlayerSettings")
local SoundService = game:GetService("SoundService")

-- Treffer-Art
check(HitFeedback.KindOf(true, true, false, 40, 0) == "Kill", "Kill vor Kopf")
check(HitFeedback.KindOf(true, false, true, 40, 0) == "Down", "Niederschlag vor Kopf")
check(HitFeedback.KindOf(true, false, false, 40, 0) == "Head", "Kopf")
check(HitFeedback.KindOf(false, false, false, 15, 15) == "Armor", "nur Rüstung")
check(HitFeedback.KindOf(false, false, false, 30, 15) == "Body", "Rüstung und Körper = Körper")
check(HitFeedback.KindOf(false, false, false, nil, nil) == "Body", "ohne Angaben = Körper")
for kind in { Body = true, Head = true, Armor = true, Down = true, Kill = true } do
	check(typeof(HitFeedback.Colors[kind]) == "Color3", "Farbe für " .. kind)
	for _, style in HitFeedback.HitmarkerStyles do
		check(HitFeedback.Sounds[style][kind] ~= nil, "Ton für " .. style .. "/" .. kind)
	end
end

-- Sichtbare Teile (nicht völlig durchsichtig) unter root zählen
local function visibleParts(root)
	local count = 0
	for _, child in root:GetDescendants() do
		if child:IsA("UIStroke") then
			if child.Transparency < 0.99 then
				count += 1
			end
		elseif child:IsA("TextLabel") then
			if child.TextTransparency < 0.99 then
				count += 1
			end
		elseif child:IsA("Frame") and child.BackgroundTransparency < 0.99 then
			count += 1
		end
	end
	return count
end

local screen = Instance.new("ScreenGui", player.PlayerGui)
screen.Enabled = true
for _, style in HitFeedback.HitmarkerStyles do
	local holder = Instance.new("Frame", screen)
	local marker = HitFeedback.NewHitmarker(holder, style)
	for combo, kind in { "Body", "Body", "Head", "Armor", "Down", "Kill" } do
		marker.Hit(kind, combo)
		check(visibleParts(holder) > 0, style .. "/" .. kind .. ": nichts zu sehen")
		step(0.02)
	end
	step(1.5)
	check(visibleParts(holder) == 0, style .. ": nach dem Treffer bleibt etwas sichtbar (" .. visibleParts(holder) .. ")")
	marker.Destroy()
	check(#holder:GetChildren() == 0, style .. ": Destroy räumt auf")
end

-- Schadenszahlen in einer Testfläche (wie die Vorschau)
local surface = Instance.new("Frame", screen)
local mounts, destroyed = 0, 0
local function mount(anchor)
	mounts += 1
	local frame = Instance.new("Frame", surface)
	frame.Position = anchor.Point
	return frame, function()
		destroyed += 1
		frame:Destroy()
	end
end
local function texts()
	local list = {}
	for _, child in surface:GetDescendants() do
		if child:IsA("TextLabel") and child.TextTransparency < 0.99 then
			table.insert(list, child.Text)
		end
	end
	return list
end

-- STAPELN: eine Zahl pro Ziel zählt hoch, „+X“ je Treffer, Kill beendet den Stapel
local stack = HitFeedback.NewNumbers("Stack", mount)
local A, B = {}, {}
stack.Hit(A, { Point = UDim2.new() }, 22, "Body")
step(0.1)
stack.Hit(A, { Point = UDim2.new() }, 44.4, "Head")
stack.Hit(B, { Point = UDim2.new() }, 10, "Armor")
check(mounts == 2, "STAPELN: ein Rahmen pro Ziel, waren " .. mounts)
check(table.find(texts(), "66") and table.find(texts(), "+44") and table.find(texts(), "10"), "STAPELN: Summe und +X")
step(0.3)
stack.Hit(A, { Point = UDim2.new() }, 31, "Kill")
check(table.find(texts(), "97") ~= nil, "STAPELN: Kill zählt weiter (97)")
step(3)
check(destroyed == 2 and #surface:GetChildren() == 0, "STAPELN: alles aufgeräumt")
stack.Hit(A, { Point = UDim2.new() }, 5, "Body")
check(mounts == 3, "STAPELN: nach dem Ende neuer Stapel")
step(3)

-- EINZELN: jeder Treffer eine Zahl, alle verschwinden wieder
mounts, destroyed = 0, 0
local float = HitFeedback.NewNumbers("Float", mount)
for i, kind in { "Body", "Head", "Armor", "Down", "Kill" } do
	float.Hit(A, { Point = UDim2.new() }, 10 * i, kind)
end
check(mounts == 5, "EINZELN: fünf Zahlen, waren " .. mounts)
step(2)
check(destroyed == 5 and #surface:GetChildren() == 0, "EINZELN: alles aufgeräumt")

-- AUS: nichts
mounts = 0
HitFeedback.NewNumbers(false, mount).Hit(A, { Point = UDim2.new() }, 20, "Body")
check(mounts == 0, "AUS: keine Zahl")

-- Im Spiel: Hitmarker im HUD, Zahl als BillboardGui am Ziel, Kombo lässt den Ton steigen
local hud = Instance.new("Frame", screen)
HitFeedback.Init(hud)
local dummy = SIM.MakeRig("Gegner")
dummy.Parent = workspace
local function tones()
	local list = {}
	for _, sound in SoundService:GetChildren() do
		if sound:IsA("Sound") then
			table.insert(list, sound.PlaybackSpeed)
		end
	end
	table.sort(list)
	return list
end
local function clearSounds()
	for _, sound in SoundService:GetChildren() do
		sound:Destroy()
	end
end
clearSounds()
HitFeedback.Hit(false, false, 22, Vector3.new(0, 3, 0), false, 0, dummy)
local first = tones()
step(0.2)
clearSounds()
HitFeedback.Hit(false, false, 22, Vector3.new(0, 3, 0), false, 0, dummy)
HitFeedback.Hit(false, false, 22, Vector3.new(0, 3, 0), false, 0, dummy)
local third = tones()
check(#first > 0 and third[#third] > first[#first], "Kombo: dritter Treffer klingt höher")
local billboards = 0
for _, child in player.PlayerGui:GetChildren() do
	if child:IsA("BillboardGui") then
		billboards += 1
		check(child.AlwaysOnTop and child.Adornee ~= nil, "Schadenszahl über allem und am Ziel")
	end
end
check(billboards == 3, "EINZELN im Spiel: drei Zahlen, waren " .. billboards)
check(visibleParts(hud) > 0, "Hitmarker im HUD sichtbar")
clearSounds()
HitFeedback.Hit(true, true, 40, Vector3.new(0, 4.5, 0), false, 0, dummy)
step(0.3)
clearSounds()
HitFeedback.Hit(false, false, 22, Vector3.new(0, 3, 0), false, 0, dummy)
check(#tones() > 0 and math.abs(tones()[#tones()] - 2.7) < 1e-6, "nach dem Kill beginnt die Kombo von vorn")
step(2)
local left = 0
for _, child in player.PlayerGui:GetChildren() do
	if child:IsA("BillboardGui") then
		left += 1
	end
end
check(left == 0, "alle Schadenszahlen verschwinden wieder, übrig " .. left)
check(#workspace.Terrain:GetChildren() == 0, "Ankerpunkte werden mit aufgeräumt")

-- Stilwechsel in den Einstellungen baut den Hitmarker neu
PlayerSettings.Set("HitmarkerStyle", "Precision")
PlayerSettings.Set("DamageNumbers", "Stack")
step(0.1)
HitFeedback.Hit(false, false, 30, Vector3.new(0, 3, 0), false, 0, dummy)
check(#hud:GetChildren() == 1, "nur ein Hitmarker nach dem Umschalten, waren " .. #hud:GetChildren())
local stackBoards = 0
for _, child in player.PlayerGui:GetChildren() do
	if child:IsA("BillboardGui") then
		stackBoards += 1
		check(child.Adornee == dummy.Head, "STAPELN im Spiel: über dem Kopf")
	end
end
check(stackBoards == 1, "STAPELN im Spiel: eine Zahl")
step(3)

-- Vorschau: läuft in Schleife, solange zu sehen; Play(true) mit Ton
local page = Instance.new("Frame", screen)
page.Size = UDim2.fromOffset(708, 202)
local preview = HitFeedback.Preview(page)
step(0.05)
check(preview.Playing, "Vorschau startet von selbst")
step(3)
clearSounds()
preview.Play(true)
step(1.4)
check(#tones() > 0, "Vorschau mit Ton")
page.Visible = false
step(6)
check(not preview.Playing, "unsichtbare Vorschau läuft nicht weiter")
page:Destroy()
step(3)

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

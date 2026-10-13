-- Glücksrad im Camp: Feld unter dem Zeiger und Zielwinkel (Rad bleibt auf dem ausgelosten Feld stehen), Dreiecke
-- aus zwei Keilen, Aufbau des Rads (Teile, Drehrichtung), Server dreht nur in der
-- Camp in der Nähe des Rads
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, eps)
	return (a - b).Magnitude < (eps or 1e-3)
end

-- Lokaler Spieler (HubWheel ist ein Client-Modul)
local player = SIM.AddPlayer("Spieler")
Instance.new("Folder", player).Name = "PlayerGui"
rawget(SIM.Players, "__props").LocalPlayer = player
local HubWheel = require("HubWheel")
local LoginConfig = require("LoginConfig")
local count = #LoginConfig.Wheel
local slice = 360 / count

-- Feld unter dem Zeiger
check(HubWheel.IndexAt(0) == 1, "in Ruhe steht Feld 1 oben")
check(HubWheel.IndexAt(-slice) == 2, "gegen den Uhrzeigersinn: Feld 2")
check(HubWheel.IndexAt(slice) == count, "im Uhrzeigersinn: letztes Feld")
check(HubWheel.IndexAt(360 * 7 + slice * 0.4) == 1, "Feldgrenze: knapp vor der Hälfte noch Feld 1")

-- Zielwinkel: mindestens 4 Runden weiter, genau auf dem Feld, auch mit Versatz innerhalb des Felds
for _, current in { 0, 17.5, 359, 1234.5, -90 } do
	for index = 1, count do
		for _, jitter in { 0, slice * 0.34, -slice * 0.34 } do
			local target = HubWheel.TargetRotation(current, index, 4, jitter)
			check(HubWheel.IndexAt(target) == index, ("Feld %d von %s (Versatz %.1f): stand auf %d"):format(index,
				tostring(current), jitter, HubWheel.IndexAt(target)))
			check(target >= current + 4 * 360 and target < current + 5 * 360 + slice,
				("4 bis 5 Runden: %.1f -> %.1f"):format(current, target))
		end
	end
end

-- Auslaufkurve: 0 -> 1, steigt immer, am Ende langsam (Spannung), kein Ruck
check(HubWheel.SpinCurve(0) == 0 and HubWheel.SpinCurve(1) == 1, "Kurve von 0 bis 1")
local previous = 0
for k = 1, 100 do
	local v = HubWheel.SpinCurve(k / 100)
	check(v >= previous, "Kurve steigt")
	previous = v
end
check(1 - HubWheel.SpinCurve(0.85) > 0.002, "in den letzten 15 % kriecht das Rad noch")

-- Felder: Chancen summieren sich zu 1, zwei neue Rad-Skins drin, Seltenheiten, JACKPOT am Ende
local Cosmetics = require("Cosmetics")
local RapConfig = require("RapConfig")
local total = 0
for _, odd in LoginConfig.WheelOdds() do
	total += odd
end
check(math.abs(total - 1) < 1e-9, "Chancen summieren sich zu 100 %")
local skins = {}
for index, field in LoginConfig.Wheel do
	if field.Item then
		local item = Cosmetics.Get(field.Item)
		check(item ~= nil and item.Reward == true, "Rad-Skin existiert und ist nicht kaufbar: " .. field.Item)
		check(field.Fallback == true and (field.Coins or 0) > 0, "Skin-Feld hat Münzen als Ersatz: " .. field.Item)
		check(HubWheel.FieldRarity(index) == item.Rarity, "Seltenheit nach dem Skin: " .. field.Item)
		skins[field.Item] = true
	end
end
for _, id in { "W_Sternschnuppe", "W_Fortuna" } do
	check(skins[id], "Rad-Skin im Rad: " .. id)
	local item = Cosmetics.Get(id)
	check(item and item.Effects ~= nil and require("SkinEffects").Styles[item.Effects] ~= nil, "Effekt-Skin: " .. id)
	check(RapConfig.Tradeable(id), "handelbar (RAP-Wert): " .. id)
end
check(LoginConfig.Wheel[count].Text == "JACKPOT" and HubWheel.FieldRarity(count) == "Legendary", "JACKPOT zuletzt, legendär")
check(HubWheel.FieldRarity(1) == "Common", "50 Münzen: gewöhnlich")
local rows = require("OddsPanel").WheelRows()
check(#rows == count, "Chancen-Fenster zeigt jedes Feld")
local shown = {}
for _, row in rows do
	shown[row.Text] = true
end
check(shown["Skin Sternschnuppe"] and shown["Skin Fortuna"], "neue Skins im Chancen-Fenster")

-- Dreieck aus zwei Keilen: Eckpunkte der Keile = Ecken des Dreiecks (+ Fußpunkt), Flächen addieren sich
local function wedgeCorners(spec)
	local hy, hz = spec.Size.Y / 2, spec.Size.Z / 2
	return { spec.CFrame * Vector3.new(0, -hy, -hz), spec.CFrame * Vector3.new(0, -hy, hz), spec.CFrame * Vector3.new(0, hy, hz) }
end
local function area(a, b, c)
	return (b - a):Cross(c - a).Magnitude / 2
end
for _, tri in {
	{ Vector3.new(0, 0, 0), Vector3.new(4, 0, 0), Vector3.new(1, 3, 0) },
	{ Vector3.new(2, 1, -3), Vector3.new(-1, 5, 2), Vector3.new(3, -2, 1) },
	{ Vector3.new(0, 0, 0), Vector3.new(math.sin(0.3) * 6, math.cos(0.3) * 6, 0), Vector3.new(math.sin(0.55) * 6, math.cos(0.55) * 6, 0) },
} do
	local specs = HubWheel.Triangle(tri[1], tri[2], tri[3], 0.05)
	local total = 0
	for _, spec in specs do
		local c = wedgeCorners(spec)
		total += area(c[1], c[2], c[3])
		for _, corner in c do
			-- jede Keil-Ecke liegt in der Ebene des Dreiecks und im Dreieck
			local n = (tri[2] - tri[1]):Cross(tri[3] - tri[1]).Unit
			check(math.abs((corner - tri[1]):Dot(n)) < 1e-6, "Keil-Ecke in der Ebene")
			local a1 = area(corner, tri[2], tri[3]) + area(tri[1], corner, tri[3]) + area(tri[1], tri[2], corner)
			check(math.abs(a1 - area(tri[1], tri[2], tri[3])) < 1e-6, "Keil-Ecke im Dreieck")
		end
	end
	check(math.abs(total - area(tri[1], tri[2], tri[3])) < 1e-6, "zwei Keile füllen das Dreieck genau")
	local hits = 0
	for _, v in tri do
		for _, spec in specs do
			for _, corner in wedgeCorners(spec) do
				if near(corner, v) then
					hits += 1
					break
				end
			end
		end
	end
	check(hits >= 4, "alle drei Ecken werden getroffen (zwei davon von beiden Keilen geteilt)")
end

-- Rad bauen: Teile, Vorderseite zur Halle, Drehrichtung passt zu IndexAt
local spot = Instance.new("Part")
spot.CFrame = CFrame.new(40, 9.4, -29.5) * CFrame.Angles(0, math.pi, 0) -- Vorderseite nach +z
local holder = Instance.new("Folder", workspace)
local wheel = HubWheel.Build(spot, holder)
local wedges, labels = 0, {}
for _, part in wheel.Spin:GetDescendants() do
	if part:IsA("WedgePart") then
		wedges += 1
	elseif part:IsA("BasePart") and string.match(part.Name, "^Label%d") then
		labels[tonumber(string.sub(part.Name, 6))] = part
	end
end
check(wedges == count * 3 * 2, "je Feld drei Dreiecke aus je zwei Keilen, waren " .. wedges)
check(#wheel.Bulbs == 30, "30 Birnen am Rand")
for i = 1, count do
	check(labels[i] ~= nil and labels[i]:FindFirstChildOfClass("SurfaceGui") ~= nil, "Beschriftung für Feld " .. i)
end
-- Feld 1 oben, vor dem Rad (Richtung Halle = +z)
check(labels[1].Position.Y > spot.Position.Y + 2 and math.abs(labels[1].Position.X - 40) < 0.01, "Feld 1 steht oben")
check(labels[1].Position.Z > spot.Position.Z, "Beschriftung vorn (zur Halle)")
-- Feld 2 liegt im Uhrzeigersinn rechts daneben – wer vor dem Rad steht (bei +z, Blick nach -z), hat +x rechts
check(labels[2].Position.X > 40, "Feld 2 rechts von Feld 1 (von vorn gesehen)")
-- Eine Feldbreite im Uhrzeigersinn drehen: Feld 1 steht dort, wo Feld 2 war; unter dem Zeiger ist das letzte Feld
local before2 = labels[2].Position
wheel.Spin:PivotTo(wheel.Face * CFrame.Angles(0, 0, -math.rad(slice)))
check(near(labels[1].Position, before2, 1e-3), "Drehung im Uhrzeigersinn schiebt Feld 1 nach rechts")
check(HubWheel.IndexAt(slice) == count, "dann zeigt der Zeiger aufs letzte Feld")
local top = wheel.Face * Vector3.new(0, 3.6, 0.36)
check(near(labels[count].Position, top, 1e-3), "letztes Feld steht jetzt oben")

-- Server: nur in der offenen Welt (Camp im Camp) und in der Nähe des Rads
local Remotes = require("Remotes")
local ShopService = require("ShopService")
local ProgressService = require("ProgressService")
ProgressService.Init()
ShopService.Init()
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local world = Instance.new("Model", maps)
world.Name = "Extinction"
local decor = Instance.new("Model", world)
decor.Name = "Zentrale"
local wheelSpot = Instance.new("Part", decor)
wheelSpot.Name = "WheelSpot"
wheelSpot.CFrame = spot.CFrame
local spinner = SIM.AddPlayer("Dreher")
SIM.Run(SIM.Now + 1)
local rig = SIM.MakeRig("Dreher")
rig.Parent = workspace
spinner.Character = rig
local function spinResult()
	local before = #SIM.RemoteLog
	Remotes.ShopAction.OnServerEvent:Fire(spinner, "SpinWheel")
	SIM.Run(SIM.Now + 0.1)
	for i = before + 1, #SIM.RemoteLog do
		local entry = SIM.RemoteLog[i]
		if entry.Player == spinner and (entry.Remote == "WheelResult" or entry.Remote == "ShopStatus") then
			return entry.Remote, entry.Args[1]
		end
	end
	return nil
end
spinner:SetAttribute("Mode", "Domination")
rig:PivotTo(CFrame.new(40, 3, -20))
check(spinResult() == "ShopStatus", "im Match kein Dreh")
spinner:SetAttribute("Mode", "Extinction")
rig:PivotTo(CFrame.new(0, 3, -31))
check(spinResult() == "ShopStatus", "am Spawn zu weit weg")
rig:PivotTo(CFrame.new(40, 3, -20))
local before = #SIM.RemoteLog
local remote, index = spinResult()
check(remote == "WheelResult" and type(index) == "number" and index >= 1 and index <= count, "am Pult: Rad dreht")
local broadcast = false
for i = before + 1, #SIM.RemoteLog do
	local entry = SIM.RemoteLog[i]
	if entry.Remote == "WheelSpin" and entry.Player == "all" and entry.Args[1] == spinner and entry.Args[2] == index then
		broadcast = true
	end
end
check(broadcast, "alle sehen den Dreh mit (WheelSpin)")
-- Rad besetzt: ein zweiter Spieler muss warten, auch mit Gratis-Dreh
local other = SIM.AddPlayer("Zweiter")
SIM.Run(SIM.Now + 1)
local rig2 = SIM.MakeRig("Zweiter")
rig2.Parent = workspace
other.Character = rig2
other:SetAttribute("Mode", "Extinction")
rig2:PivotTo(CFrame.new(41, 3, -20))
local function spinOther()
	local start = #SIM.RemoteLog
	Remotes.ShopAction.OnServerEvent:Fire(other, "SpinWheel")
	SIM.Run(SIM.Now + 0.1)
	for i = start + 1, #SIM.RemoteLog do
		local entry = SIM.RemoteLog[i]
		if entry.Player == other and (entry.Remote == "WheelResult" or entry.Remote == "ShopStatus") then
			return entry.Remote
		end
	end
	return nil
end
check(spinOther() == "ShopStatus", "Rad dreht noch: der Nächste wartet")
SIM.Run(SIM.Now + LoginConfig.WheelBusy)
check(spinOther() == "WheelResult", "danach darf der Nächste drehen")
SIM.Run(SIM.Now + LoginConfig.WheelBusy)
check(spinResult() == "ShopStatus", "heute schon gedreht (ohne Extra-Dreh)")
-- Admin: in Studio beliebig oft (nur auf das Rad warten), live nicht
spinner:SetAttribute("IsAdmin", true)
check(spinResult() == "ShopStatus", "Admin live: auch nur einmal am Tag")
SIM.IsStudio = true
for round = 1, 3 do
	check(spinResult() == "WheelResult", "Admin in Studio: Dreh " .. round)
	SIM.Run(SIM.Now + LoginConfig.WheelBusy)
end
SIM.IsStudio = false
spinner:SetAttribute("IsAdmin", nil)

if failures == 0 then
	print("Glücksrad: alles in Ordnung")
end

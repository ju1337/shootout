-- Namensschilder (Nametags): volles Schild (Prestige, Team-Rang, Name, Rang nur mit Arcade, RAP, Titel) im Markt und in der Safe Zone
-- von Extinction, draußen in der offenen Welt keins für Fremde; RAP kurz (12.4K); Kopf neu geladen (Streaming).
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local bob = SIM.Join("Bob")
rawget(SIM.Players, "__props").LocalPlayer = bob
local alice = SIM.Join("Alice")
bob:SetAttribute("Mode", "Market")
alice:SetAttribute("Mode", "Market")
alice:SetAttribute("Rap", 12000)
alice:SetAttribute("RapValue", 450)
bob:LoadCharacter()
alice:LoadCharacter()
SIM.Advance(1, 20)

local Nametags = require("Nametags")
check(Nametags.ShortNumber(950) == "950", "950 bleibt (" .. Nametags.ShortNumber(950) .. ")")
check(Nametags.ShortNumber(12450) == "12.4K", "12.4K (" .. Nametags.ShortNumber(12450) .. ")")
check(Nametags.ShortNumber(50000) == "50K", "50K (" .. Nametags.ShortNumber(50000) .. ")")
check(Nametags.ShortNumber(3160000) == "3.1M", "3.1M (" .. Nametags.ShortNumber(3160000) .. ")")
check(Nametags.Showcase("Market", nil), "Markt zeigt das volle Schild")
check(Nametags.Showcase("Extinction", true), "Safe Zone zeigt das volle Schild")
check(not Nametags.Showcase("Extinction", false), "draußen nicht")
check(not Nametags.Showcase("FreeForAll", true), "Kampfmodus nicht")

Nametags.Init()
SIM.Advance(1, 20)

local function tagOf(p)
	return p.Character and p.Character:FindFirstChild("ShootoutNametag")
end
local function find(tag, name)
	for _, d in tag:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local tag = tagOf(alice)
check(tag ~= nil, "Markt: Schild über Alice")
if tag then
	check(find(tag, "Title").Text == "Alice", "Name (" .. tostring(find(tag, "Title").Text) .. ")")
	check(find(tag, "Rap").Visible and find(tag, "Rap").Text == "12.4K", "RAP kurz in der Info-Zeile")
	-- Ranked-Rang nur mit Arcade (ohne Arcade gibt es kein Ranked)
	if require("Modes").ArcadeEnabled then
		check(find(tag, "Subtitle").Visible and find(tag, "Subtitle").Text ~= "", "Rang steht da")
	else
		check(not find(tag, "Subtitle").Visible, "ohne Arcade kein Rang")
	end
	check(find(tag, "Strip").Visible, "Prestige-Strich")
	check(not find(tag, "Staff").Visible, "kein Team-Rang-Schild ohne Rang")
	check(tag.Adornee == alice.Character:FindFirstChild("Head"), "hängt am Kopf")
end

-- Extinction: draußen kein Schild, in der Safe Zone das volle
bob:SetAttribute("Mode", "Extinction")
alice:SetAttribute("Mode", "Extinction")
bob:SetAttribute("InSafeZone", true)
alice:SetAttribute("InSafeZone", false)
SIM.Advance(1, 20)
check(tagOf(alice) == nil, "Extinction draußen: kein Schild über Fremden")
alice:SetAttribute("InSafeZone", true)
SIM.Advance(1, 20)
tag = tagOf(alice)
check(tag ~= nil and find(tag, "Rap").Visible, "Extinction Safe Zone: volles Schild")
check(tagOf(bob) ~= nil, "eigenes Schild in der Safe Zone")
bob:SetAttribute("InSafeZone", false)
SIM.Advance(1, 20)
check(tagOf(bob) == nil, "eigenes Schild draußen weg")

-- Streaming: Kopf neu geladen -> Schild hängt am neuen Kopf
if tag then
	local head = alice.Character:FindFirstChild("Head")
	local copy = head:Clone()
	head:Destroy()
	copy.Parent = alice.Character
	SIM.Advance(1, 20)
	tag = tagOf(alice)
	check(tag ~= nil and tag.Adornee == copy, "neuer Kopf nach Streaming")
end

if failures == 0 then
	print("Namensschilder: alles ok")
end

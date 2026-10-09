-- Welt-Ambiente (Ambience): 2D-Schleifen je nach Lage – draußen am Tag Wind und Vögel, nachts Wind und Grillen, in
-- der Safe Zone das Camp-Feuer, in der roten Zone dazu ein Dröhnen, beim Blutmond ein Schlag zum Start und ein
-- dunkleres Dröhnen, in der Sturmnacht leiser; alles überblendet in etwa 2 Sekunden, außerhalb der offenen Welt stumm.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

require("Remotes") -- legt den Remotes-Ordner an (noch als Server), den Sfx auf dem Client erwartet
SIM.IsServer = false
local bob = SIM.AddPlayer("Bob", 1001)
rawget(SIM.Players, "__props").LocalPlayer = bob
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local ExtinctionConfig = require("ExtinctionConfig")
local SoundLibrary = require("SoundLibrary")
local Ambience = require("Ambience")
local D = ExtinctionConfig.Day

for _, name in { "AmbientWindDay", "AmbientBirds", "AmbientNight", "AmbientCamp", "AmbientRedzone", "AmbientBloodMoon",
	"BloodMoonStinger" } do
	local def = SoundLibrary.Get(name)
	check(def ~= nil and def.Range == 0 and #def.Clips >= 1, "Eintrag " .. name .. " (2D)")
	check(def ~= nil and (def.Looped == true) == (name ~= "BloodMoonStinger"), name .. ": Schleife oder Stinger")
end

local function sound(name)
	return Ambience.Sounds()[name]
end
local function volume(name)
	local s = sound(name)
	return s and s.Volume or 0
end
local function audible(name)
	local s = sound(name)
	return s ~= nil and s.IsPlaying and s.Volume > 0.01
end
local function stingers()
	local n = 0
	for _, child in SoundService:GetChildren() do
		if child.Name == "Sfx_BloodMoonStinger" then
			n += 1
		end
	end
	return n
end

-- außerhalb der offenen Welt: nichts
D.Fixed = 12
Ambience.Init()
SIM.Advance(3, 10)
check(next(Ambience.Sounds()) == nil, "ohne Extinction keine Schleifen")

-- draußen am Tag: Wind und Vögel, keine Grillen, kein Camp
bob:SetAttribute("Mode", "Extinction")
bob:SetAttribute("InSafeZone", false)
SIM.Advance(0.6, 10)
check(sound("AmbientWindDay") ~= nil and sound("AmbientWindDay").Parent == SoundService, "Wind-Schleife liegt in SoundService (2D)")
check(sound("AmbientWindDay").Looped == true, "Wind läuft als Schleife")
check(volume("AmbientWindDay") < 0.05, "Wind blendet erst ein (noch leise)")
SIM.Advance(2.5, 10)
check(audible("AmbientWindDay") and audible("AmbientBirds"), "Tag draußen: Wind und Vögel hörbar")
check(not audible("AmbientNight") and not audible("AmbientCamp") and not audible("AmbientRedzone"), "Tag draußen: keine Nacht, Camp, rote Zone")
local dayWind = volume("AmbientWindDay")

-- Nacht draußen: Grillen, Vögel aus, Wind bleibt (etwas leiser)
D.Fixed = 23
SIM.Advance(3, 10)
check(audible("AmbientNight") and not audible("AmbientBirds"), "Nacht draußen: Grillen statt Vögel")
check(audible("AmbientWindDay") and volume("AmbientWindDay") < dayWind, "Nacht: Wind bleibt, leiser als am Tag")

-- Safe Zone: Camp statt der wilden Schichten
bob:SetAttribute("InSafeZone", true)
SIM.Advance(3, 10)
check(audible("AmbientCamp"), "Safe Zone: Camp-Feuer hörbar")
check(not audible("AmbientNight") and not audible("AmbientWindDay"), "Safe Zone: Wind und Grillen weggeblendet")
check(sound("AmbientNight") ~= nil, "weggeblendete Schleife bleibt liegen (kein Neuanlegen)")

-- rote Zone (draußen): Dröhnen dazu; in der Safe Zone zählt das Attribut nicht
bob:SetAttribute("Redzone", "Fabrik")
SIM.Advance(3, 10)
check(not audible("AmbientRedzone"), "rote Zone zählt nicht in der Safe Zone")
bob:SetAttribute("InSafeZone", false)
SIM.Advance(3, 10)
check(audible("AmbientRedzone") and audible("AmbientNight"), "rote Zone draußen: Dröhnen über der Nacht")
bob:SetAttribute("Redzone", nil)
SIM.Advance(3, 10)
check(not audible("AmbientRedzone"), "rote Zone verlassen: Dröhnen weg")

-- Blutmond: Stinger einmal beim Start, dunkleres Dröhnen; am Tag wird es dabei zur Nacht
D.Fixed = 12
SIM.Advance(3, 10)
check(audible("AmbientBirds"), "wieder Tag: Vögel")
local before = stingers()
local now = workspace:GetServerTimeNow()
RS:SetAttribute("BloodMoonStart", now)
RS:SetAttribute("BloodMoonEnd", now + 600)
SIM.Advance(0.6, 10)
check(stingers() == before + 1, "Blutmond-Start: ein Stinger (" .. (stingers() - before) .. ")")
SIM.Advance(3, 10)
check(stingers() == before + 1, "Stinger nur einmal")
check(audible("AmbientBloodMoon") and audible("AmbientNight") and not audible("AmbientBirds"), "Blutmond: dunkles Dröhnen, Nachtstimmung")
local moonFull = volume("AmbientBloodMoon")
RS:SetAttribute("BloodMoonStart", nil)
RS:SetAttribute("BloodMoonEnd", nil)
SIM.Advance(3, 10)
check(not audible("AmbientBloodMoon") and audible("AmbientBirds"), "Blutmond vorbei: Dröhnen weg, wieder Tag")

-- Sturmnacht: Ambiente leiser (Regen und Wind macht StormClient)
local windBefore = volume("AmbientWindDay")
now = workspace:GetServerTimeNow()
RS:SetAttribute("StormStart", now - 60)
RS:SetAttribute("StormEnd", now + 600)
SIM.Advance(3, 10)
check(audible("AmbientWindDay") and volume("AmbientWindDay") < windBefore * 0.5, "Sturmnacht: Ambiente deutlich leiser")
RS:SetAttribute("StormStart", nil)
RS:SetAttribute("StormEnd", nil)
SIM.Advance(3, 10)
check(math.abs(volume("AmbientWindDay") - windBefore) < 1e-6, "nach dem Sturm wieder normal")
check(moonFull > 0, "Blutmond-Dröhnen hatte Lautstärke")

-- Extinction verlassen: alles aus
bob:SetAttribute("Mode", nil)
SIM.Advance(3, 10)
check(not audible("AmbientWindDay") and not audible("AmbientBirds"), "außerhalb der offenen Welt stumm")
D.Fixed = nil

check(SIM.Errors == 0, "keine Fehler in Threads (" .. SIM.Errors .. ")")
if failures == 0 then
	print("OK ambience")
end

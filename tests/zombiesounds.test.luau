-- Zombie-Stimmen wie in Unturned: tief gestimmt, dumpf und rau gefiltert, leises Stöhnen nur in der Nähe, der Schrei
-- beim Entdecken weit zu hören, beim Jagen eigenes Knurren
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local SoundLibrary = require("SoundLibrary")
local Sfx = require("Sfx")

local S = SoundLibrary.Sounds
for _, name in { "ZombieIdle", "ZombieAggro", "ZombieChase", "ZombieAttack", "ZombieHurt", "ZombieDeath", "ZombieScream" } do
	local def = S[name]
	check(def ~= nil, name .. " fehlt")
	if def then
		check(#def.Clips > 0, name .. " ohne Aufnahmen")
		check(def.Voice ~= nil and def.Voice.Muffle < 0, name .. " ohne dumpfen Stimmfilter")
		check(def.Pitch < 1, name .. " ist nicht tiefer gestimmt")
		for _, c in def.Clips do
			check(string.match(c.Id, "^rbxassetid://%d+$") ~= nil, name .. ": ungültige Asset-ID " .. tostring(c.Id))
		end
	end
end
check(S.ZombieIdle.Range < S.ZombieAggro.Range, "Stöhnen soll leiser/näher sein als der Schrei beim Entdecken")

-- abgespielt: Equalizer (Höhen runter) und Verzerrung hängen am Sound, mit Raumklang
local part = Instance.new("Part", workspace)
local sound = Sfx.At("ZombieIdle", part)
check(sound ~= nil, "Sfx.At liefert keinen Sound")
if sound then
	local eq = sound:FindFirstChildOfClass("EqualizerSoundEffect")
	check(eq ~= nil and eq.HighGain < 0, "kein Equalizer mit gesenkten Höhen")
	check(sound:FindFirstChildOfClass("DistortionSoundEffect") ~= nil, "keine Verzerrung")
	check(sound.RollOffMaxDistance == S.ZombieIdle.Range, "Hörweite falsch")
	check(sound.PlaybackSpeed < 1, "nicht tiefer gestimmt")
end
-- andere Geräusche bleiben ungefiltert
local plain = Sfx.At("CrateOpen", part)
check(plain ~= nil and plain:FindFirstChildOfClass("EqualizerSoundEffect") == nil, "Filter auch an Nicht-Stimmen")

if failures > 0 then
	error(failures .. " Prüfung(en) fehlgeschlagen")
end
print("zombiesounds ok")

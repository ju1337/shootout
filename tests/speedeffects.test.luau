-- Tempo-Effekte (SpeedEffects): jede Quelle läuft für sich ab, SpeedMultiplier ist das Produkt der laufenden. Früher
-- beendete z. B. die Spritze des Chirurgen ein laufendes Adrenalin.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local SpeedEffects = require("SpeedEffects")
local character = SIM.MakeRig("Tester")
character.Parent = workspace

SpeedEffects.Apply(character, "Item", 1.25, 6)
check(character:GetAttribute("SpeedMultiplier") == 1.25, "Adrenalin: schneller")
SIM.Advance(1)
SpeedEffects.Apply(character, "Syringe", 0.6, 3)
check(math.abs(character:GetAttribute("SpeedMultiplier") - 0.75) < 1e-6, "Spritze dazu: beide wirken (1,25 × 0,6)")
SIM.Advance(3.2)
check(character:GetAttribute("SpeedMultiplier") == 1.25, "Spritze vorbei: Adrenalin läuft weiter")
SIM.Advance(2)
check(character:GetAttribute("SpeedMultiplier") == 1, "Adrenalin vorbei: normal")
SpeedEffects.Apply(character, "Item", 1.25, 2)
SIM.Advance(1.5)
SpeedEffects.Apply(character, "Item", 1.25, 2)
SIM.Advance(1)
check(character:GetAttribute("SpeedMultiplier") == 1.25, "erneut genommen: verlängert, nicht vom alten Ablauf beendet")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

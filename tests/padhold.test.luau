-- Controller: Antippen und Halten auf derselben Taste (InputActions.PadHold). Kurz gedrückt löst beim Loslassen nur die
-- Antippen-Aktion aus, lange gehalten nach InputActions.HoldTime nur die Halten-Aktion (Ende beim Loslassen).
-- Tasten ohne PadHold lösen wie bisher sofort aus. Hint zeigt "△ HALTEN", wenn eine Aktion nur gehalten auf dem Controller liegt.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local UserInputService = game:GetService("UserInputService")
local InputActions = require("InputActions")
InputActions.Init()
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
check(InputActions.Device() == "Gamepad", "Gerät ist der Controller")
check(type(InputActions.HoldTime) == "number" and InputActions.HoldTime > 0.1 and InputActions.HoldTime < 1,
	"HoldTime sinnvoll (" .. tostring(InputActions.HoldTime) .. ")")
local HOLD = InputActions.HoldTime

-- Test-Aktionen auf einer sonst freien Taste (Start): antippen = TestTap, halten = TestHold
InputActions.Bindings.TestTap = { Keys = {}, Pad = { Enum.KeyCode.ButtonStart } }
InputActions.Bindings.TestHold = { Keys = { Enum.KeyCode.J }, Pad = {}, PadHold = { Enum.KeyCode.ButtonStart } }
local log = {}
for _, action in { "TestTap", "TestHold", "Fire" } do
	InputActions.Bind(action, function(began)
		table.insert(log, { Action = action, Began = began, At = SIM.Now })
	end)
end
local function count(action, began)
	local n = 0
	for _, entry in log do
		if entry.Action == action and (began == nil or entry.Began == began) then
			n += 1
		end
	end
	return n
end
local function pad(keyCode)
	return { KeyCode = keyCode, UserInputType = Enum.UserInputType.Gamepad1 }
end
local function press(input, processed)
	UserInputService.InputBegan:Fire(input, processed == true)
end
local function release(input)
	UserInputService.InputEnded:Fire(input, false)
end

-- 1) kurz antippen: beim Drücken noch nichts, beim Loslassen einmal TestTap (drücken + loslassen), nie TestHold
local start = pad(Enum.KeyCode.ButtonStart)
press(start)
SIM.Advance(0.1)
check(#log == 0, "kurz gedrückt: vor dem Loslassen löst nichts aus (" .. #log .. ")")
release(start)
check(count("TestTap", true) == 1 and count("TestTap", false) == 1, "kurz gedrückt: Antippen-Aktion beim Loslassen")
check(log[1] and log[1].Began == true and log[2] and log[2].Began == false, "Antippen: erst gedrückt, dann losgelassen")
check(not InputActions.IsHeld("TestTap"), "Antippen-Aktion danach nicht mehr gedrückt")
SIM.Advance(HOLD + 0.2)
check(count("TestHold") == 0, "kurz gedrückt: Halten-Aktion löst auch später nicht aus")

-- 2) lange halten: nach HoldTime nur TestHold, beim Loslassen endet TestHold, TestTap bleibt still
table.clear(log)
press(start)
SIM.Advance(HOLD * 0.6)
check(count("TestHold") == 0, "vor Ablauf von HoldTime noch keine Halten-Aktion")
SIM.Advance(HOLD * 0.6)
check(count("TestHold", true) == 1 and count("TestHold", false) == 0, "nach HoldTime: Halten-Aktion beginnt")
check(InputActions.IsHeld("TestHold"), "Halten-Aktion gilt als gedrückt")
SIM.Advance(1)
check(count("TestHold", true) == 1, "Halten-Aktion beginnt nur einmal")
release(start)
check(count("TestHold", false) == 1 and not InputActions.IsHeld("TestHold"), "Loslassen beendet die Halten-Aktion")
check(count("TestTap") == 0, "lange gehalten: keine Antippen-Aktion")

-- 3) kurz antippen und gleich wieder drücken: die Zeit zählt ab dem zweiten Druck
table.clear(log)
press(start)
SIM.Advance(HOLD * 0.5)
release(start)
SIM.Advance(0.05)
press(start)
SIM.Advance(HOLD * 0.7) -- vom ersten Druck aus wäre HoldTime vorbei
check(count("TestHold") == 0, "zweiter Druck: Halten-Aktion nicht vom ersten Druck ausgelöst")
SIM.Advance(HOLD * 0.5)
check(count("TestHold", true) == 1, "zweiter Druck lange gehalten: Halten-Aktion")
release(start)
check(count("TestTap", true) == 1 and count("TestHold", false) == 1, "einmal angetippt, einmal gehalten")

-- 4) auch wenn ein Menüknopf ausgewählt ist (processed), zählt die Controller-Taste
table.clear(log)
press(start, true)
SIM.Advance(0.05)
release(start)
check(count("TestTap", true) == 1, "processed: Antippen-Aktion trotzdem")

-- 5) Taste ohne PadHold (R2 = Schießen) löst sofort aus wie bisher und endet beim Loslassen
table.clear(log)
local r2 = pad(Enum.KeyCode.ButtonR2)
press(r2)
check(count("Fire", true) == 1, "ohne PadHold: sofort beim Drücken")
SIM.Advance(1)
check(count("Fire", false) == 0 and InputActions.IsHeld("Fire"), "ohne PadHold: gedrückt, solange gehalten")
release(r2)
check(count("Fire", false) == 1 and not InputActions.IsHeld("Fire"), "ohne PadHold: Ende beim Loslassen")

-- 6) Tastatur: PadHold gilt nur für den Controller, J löst TestHold sofort aus
table.clear(log)
local j = { KeyCode = Enum.KeyCode.J, UserInputType = Enum.UserInputType.Keyboard }
press(j)
check(count("TestHold", true) == 1, "Tastatur: Taste der Halten-Aktion löst sofort aus")
release(j)
check(count("TestHold", false) == 1, "Tastatur: Ende beim Loslassen")
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)

-- 7) PadHold wieder weg: dieselbe Taste löst die Antippen-Aktion sofort aus
InputActions.Bindings.TestHold.PadHold = nil
table.clear(log)
press(start)
check(count("TestTap", true) == 1, "ohne PadHold: Antippen-Aktion wieder sofort beim Drücken")
release(start)
check(count("TestTap", false) == 1, "ohne PadHold: Ende beim Loslassen")
InputActions.Bindings.TestHold.PadHold = { Enum.KeyCode.ButtonStart }

-- 8) wie in der offenen Welt: △ antippen (zusätzlich zu Waffe wechseln) und △ halten
InputActions.Bindings.TestHeal = { Keys = {}, Pad = { Enum.KeyCode.ButtonY } }
InputActions.Bindings.TestPark = { Keys = { Enum.KeyCode.K }, Pad = {}, PadHold = { Enum.KeyCode.ButtonY } }
local swaps = 0
InputActions.Bind("SwapWeapon", function(began)
	if began then
		swaps += 1
	end
end)
for _, action in { "TestHeal", "TestPark" } do
	InputActions.Bind(action, function(began)
		table.insert(log, { Action = action, Began = began, At = SIM.Now })
	end)
end
table.clear(log)
local y = pad(Enum.KeyCode.ButtonY)
press(y)
SIM.Advance(0.1)
release(y)
check(count("TestHeal", true) == 1 and count("TestPark") == 0 and swaps == 1, "△ angetippt: alle Antippen-Aktionen, kein Halten")
press(y)
SIM.Advance(HOLD + 0.05)
release(y)
check(count("TestPark", true) == 1 and count("TestPark", false) == 1 and count("TestHeal", true) == 1 and swaps == 1,
	"△ gehalten: nur die Halten-Aktion")

-- 9) Hinweise: Controller zeigt "HALTEN", wenn die Aktion nur gehalten auf dem Controller liegt
check(InputActions.Hint("TestPark") == "△ HALTEN", "Hint △ HALTEN (" .. InputActions.Hint("TestPark") .. ")")
check(InputActions.Hint("TestHeal") == "△", "Hint △ für die Antippen-Aktion (" .. InputActions.Hint("TestHeal") .. ")")
InputActions.Bindings.TestUp = { Keys = { Enum.KeyCode.N }, Pad = {}, PadHold = { Enum.KeyCode.DPadUp } }
check(InputActions.Hint("TestUp") == "↑ HALTEN", "Hint ↑ HALTEN (" .. InputActions.Hint("TestUp") .. ")")
InputActions.Bindings.TestNothing = { Keys = {}, Pad = {} }
check(InputActions.Hint("TestNothing") == "", "ohne Controller-Taste kein Hint")
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
check(InputActions.Hint("TestPark") == "K" and InputActions.Hint("TestUp") == "N", "Tastatur: Hint ohne HALTEN")
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
check(InputActions.Hint("TestPark") == "", "Touch: kein Hint")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

-- Konsole (PlayStation, Xbox): Tastenbeschriftung im Stil der Konsole (PlayStation-Symbole oder Xbox-Buchstaben, je nach
-- UserInputService:GetStringForKeyCode), HUD auf dem Fernseher bis zur vollen Bildschirmgröße (am PC höchstens 1:1),
-- Fenster mit Rand, Select/Touchpad wählt keinen Knopf (AutoSelectGuiEnabled aus), HUD-Knöpfe nie auswählbar
-- (NoSelect), die Auswahl bleibt im Fenster (SelectionGroup) und kommt zurück, wenn sie im offenen Menü verloren geht
-- (Wächter), roter Auswahlrahmen, Controller-Leiste unten (PadPrompts) mit ✕ AUSWÄHLEN / ○ ZURÜCK und Einträgen der Fenster.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 0.5, 20)
end

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
-- Konsole vortäuschen: Fernseher-Oberfläche, Tasten heißen wie auf der PlayStation
local style = "ButtonCross"
rawget(GuiService, "__methods").IsTenFootInterface = function()
	return true
end
rawget(UserInputService, "__methods").GetStringForKeyCode = function(_, keyCode)
	if keyCode == Enum.KeyCode.ButtonA then
		return style
	end
	return keyCode.Name
end

SIM.IsServer = false
local bob = SIM.AddPlayer("Bob", 1001)
rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)

local InputActions = require("InputActions")
local UITheme = require("UITheme")
InputActions.Init()
step(0.2)

-- ---------- Tastenbeschriftung ----------
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
check(InputActions.Device() == "Gamepad", "Gerät ist der Controller")
check(InputActions.IsConsole(), "Konsole erkannt")
check(InputActions.PadStyle() == "PlayStation", "PlayStation erkannt")
check(InputActions.Hint("Reload") == "□", "PlayStation: Nachladen auf □ (" .. InputActions.Hint("Reload") .. ")")
check(InputActions.Hint("Ultimate") == "L1+R1", "PlayStation: Ultimate L1+R1")
check(InputActions.PadName(Enum.KeyCode.ButtonB) == "○", "PlayStation: ○")

-- Xbox (oder PC mit Controller): Buchstaben und LB/RB/LT/RT
style = "ButtonA"
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
check(InputActions.PadStyle() == "Xbox", "Xbox erkannt")
check(InputActions.Hint("Reload") == "X", "Xbox: Nachladen auf X (" .. InputActions.Hint("Reload") .. ")")
check(InputActions.Hint("Fire") == "RT", "Xbox: Schießen auf RT")
check(InputActions.Hint("Ultimate") == "LB+RB", "Xbox: Ultimate LB+RB")
check(InputActions.PadName(Enum.KeyCode.ButtonSelect) == "VIEW", "Xbox: Select heißt VIEW")
InputActions.Bindings.TestHold = { Keys = {}, Pad = {}, PadHold = { Enum.KeyCode.ButtonY } }
check(InputActions.Hint("TestHold") == "Y HALTEN", "Xbox: Halten-Hinweis mit Y (" .. InputActions.Hint("TestHold") .. ")")
style = "ButtonCross"
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)

-- ---------- Select wählt nichts, Auswahlrahmen ----------
check(GuiService.AutoSelectGuiEnabled == false, "Select/Touchpad wählt keinen Knopf (AutoSelectGuiEnabled aus)")
local frame = playerGui.SelectionImageObject
check(frame ~= nil and frame:FindFirstChildOfClass("UIStroke") ~= nil, "eigener Auswahlrahmen mit Rand")
check(frame and frame:FindFirstChildOfClass("UIStroke").Color == InputActions.SelectionColor, "Auswahlrahmen rot")

-- ---------- HUD-Knöpfe nie auswählbar ----------
local hud = Instance.new("ScreenGui", playerGui)
local hudRoot = Instance.new("Frame", hud)
local early = Instance.new("TextButton", hudRoot)
InputActions.NoSelect(hudRoot)
local late = Instance.new("ImageButton", hudRoot)
step(0.1)
check(early.Selectable == false, "HUD-Knopf von vorher nicht auswählbar")
check(late.Selectable == false, "später dazugekommener HUD-Knopf nicht auswählbar")

-- ---------- Auswahl bleibt im Fenster und kommt zurück ----------
local menuGui = Instance.new("ScreenGui", playerGui)
local canvas = Instance.new("Frame", menuGui)
canvas.Size = UDim2.fromOffset(800, 600)
local content = Instance.new("Frame", canvas)
content.Name = "Content"
content.Size = UDim2.fromScale(1, 1)
local first = Instance.new("TextButton", content)
first.Name = "First"
first.Size = UDim2.fromOffset(100, 40)
first.Position = UDim2.fromOffset(10, 10)
local second = Instance.new("TextButton", content)
second.Name = "Second"
second.Size = UDim2.fromOffset(100, 40)
second.Position = UDim2.fromOffset(10, 80)
UITheme.SetBlur("Test", true)
InputActions.Focus(content)
step(0.1)
check(GuiService.SelectedObject == first, "Focus: oberster Knopf ausgewählt")
check(canvas.SelectionGroup == true and canvas.SelectionBehaviorUp == Enum.SelectionBehavior.Stop,
	"Fenster hält die Auswahl (SelectionGroup, Stop)")
-- Knopf verschwindet (Neuaufbau ohne Refocus): der Wächter holt die Auswahl zurück
first:Destroy()
GuiService.SelectedObject = nil
step(0.8)
check(GuiService.SelectedObject == second, "Wächter: Auswahl zurück im offenen Fenster")
-- Menü zu: der Wächter wählt nichts mehr aus
UITheme.SetBlur("Test", false)
GuiService.SelectedObject = nil
step(0.8)
check(GuiService.SelectedObject == nil, "ohne offenes Menü wählt der Wächter nichts")

-- ---------- Fernseher: HUD größer, Fenster mit Rand ----------
check(UITheme.TenFoot(), "UITheme erkennt den Fernseher")
local scale = UITheme.RootScale(Vector2.new(1920, 1080))
check(math.abs(scale - 1.2) < 0.001, "Fernseher 1080p: HUD auf 1,2 statt 1:1 (" .. scale .. ")")
local holder = Instance.new("ScreenGui", playerGui)
local windowCanvas = UITheme.Canvas(holder, 1600, 900)
local canvasScale = windowCanvas:FindFirstChildOfClass("UIScale").Scale
check(math.abs(canvasScale - 1.2 * UITheme.TenFootCanvas) < 0.001, "Fenster auf der Konsole mit Rand (" .. canvasScale .. ")")
local scaledRoot = UITheme.ScaledRoot(Instance.new("ScreenGui", playerGui))
local window = Instance.new("Frame", scaledRoot)
local ok = pcall(UITheme.PhoneFit, window, 900, 600)
check(ok, "PhoneFit geht auch mit Ebene größer als 1:1")

-- ---------- Controller-Leiste ----------
local PadPrompts = require("PadPrompts")
PadPrompts.Init()
PadPrompts.Provider(function()
	return { { Keys = { Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1 }, Text = "REITER" } }
end)
step(0.3)
local bar = playerGui:FindFirstChild("PadPrompts")
check(bar ~= nil and bar.Enabled == false, "Leiste aus, solange kein Menü offen ist")
UITheme.SetBlur("Test", true)
GuiService.SelectedObject = second
step(0.3)
local texts = {}
for _, entry in PadPrompts.Entries() do
	texts[entry.Text] = entry.Keys
end
check(bar.Enabled == true, "Leiste an im offenen Menü mit Controller")
check(texts["AUSWÄHLEN"] and texts["AUSWÄHLEN"][1] == Enum.KeyCode.ButtonA, "✕ AUSWÄHLEN")
check(texts["ZURÜCK"] and texts["ZURÜCK"][1] == Enum.KeyCode.ButtonB, "○ ZURÜCK")
check(texts["REITER"] ~= nil and #texts["REITER"] == 2, "Eintrag des Fensters: L1/R1 REITER")
local glyphs = 0
for _, d in bar:GetDescendants() do
	if d.Name == "Glyph" then
		glyphs += 1
	end
end
check(glyphs == 4, "vier Tasten in der Leiste (" .. glyphs .. ")")
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.MouseMovement)
step(0.3)
check(bar.Enabled == false, "mit der Maus keine Controller-Leiste")
UITheme.SetBlur("Test", false)

if failures > 0 then
	error(failures .. " Prüfung(en) fehlgeschlagen")
end
print("console: alles ok")

-- Zuschauen auf dem Handy (Spectator): Wer im Team-Modus tot ist, schaut einem Teammitglied zu. Auf Touch erscheinen
-- unten die Knöpfe ZURÜCK und WEITER (lösen SpectatePrev/SpectateNext aus und wechseln das Ziel); auf Tastatur und
-- Controller nicht (dort gibt es Tasten). Beim Beenden des Zuschauens (Respawn) und ohne lebendes Teammitglied sind sie weg.
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
local team = Instance.new("Team")
team.Name = "Blau"
local others = Instance.new("Team")
others.Name = "Rot"
local bob, ann, carl, dave = SIM.Join("Bob"), SIM.Join("Ann"), SIM.Join("Carl"), SIM.Join("Dave")
local humanoids = {}
for _, p in { bob, ann, carl, dave } do
	local rig, humanoid = SIM.MakeRig(p.Name)
	rig.Parent = workspace
	p.Character = rig
	p.Team = p == dave and others or team
	p:SetAttribute("Mode", "Domination")
	humanoids[p] = humanoid
end

rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
local InputActions = require("InputActions")
local Spectator = require("Spectator")
InputActions.Init()
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
check(InputActions.IsTouch(), "Gerät ist Touch")
local triggered = {}
for _, action in { "SpectatePrev", "SpectateNext" } do
	InputActions.Bind(action, function(began)
		table.insert(triggered, action .. (began and "+" or "-"))
	end)
end
Spectator.Init()
step(0.5)

local function gui()
	return playerGui:FindFirstChild("SpectatorTouch")
end
local function shown()
	return gui() ~= nil and gui().Enabled
end
local camera = workspace.CurrentCamera
check(not shown(), "lebendig: keine Zuschauer-Knöpfe")

-- Bob stirbt: Zuschauen bei einem Teammitglied, Knöpfe ZURÜCK / WEITER unten
humanoids[bob].Health = 0
step(0.5)
check(shown(), "tot auf Touch: Zuschauer-Knöpfe sichtbar")
local prev = gui() and gui():FindFirstChild("SpectatePrev")
local nextButton = gui() and gui():FindFirstChild("SpectateNext")
check(prev ~= nil and prev:IsA("GuiButton") and prev.Text == "ZURÜCK", "Knopf ZURÜCK")
check(nextButton ~= nil and nextButton:IsA("GuiButton") and nextButton.Text == "WEITER", "Knopf WEITER")
check(prev and nextButton and prev.Position.X.Offset < nextButton.Position.X.Offset, "ZURÜCK links, WEITER rechts")
check(prev and prev.Position.Y.Scale == 1 and prev.AnchorPoint.Y == 1, "Knöpfe unten am Bildschirm")
check(gui() and gui().ResetOnSpawn == false, "Knöpfe überstehen den Respawn (ResetOnSpawn aus)")
check(camera.CameraSubject == humanoids[ann], "schaut Ann zu (erstes Teammitglied)")

-- WEITER: nächstes Teammitglied (Dave ist im anderen Team), ZURÜCK: wieder Ann
nextButton.Activated:Fire()
step(0.1)
check(table.concat(triggered, " ") == "SpectateNext+ SpectateNext-", "WEITER löst SpectateNext aus (" .. table.concat(triggered, " ") .. ")")
check(camera.CameraSubject == humanoids[carl], "WEITER: schaut Carl zu")
nextButton.Activated:Fire()
step(0.1)
check(camera.CameraSubject == humanoids[ann], "WEITER am Ende: wieder Ann (Dave übersprungen)")
table.clear(triggered)
prev.Activated:Fire()
step(0.1)
check(table.concat(triggered, " ") == "SpectatePrev+ SpectatePrev-", "ZURÜCK löst SpectatePrev aus (" .. table.concat(triggered, " ") .. ")")
check(camera.CameraSubject == humanoids[carl], "ZURÜCK: schaut Carl zu")
local guis = 0
for _, child in playerGui:GetChildren() do
	if child.Name == "SpectatorTouch" then
		guis += 1
	end
end
check(guis == 1, "nur eine SpectatorTouch-Oberfläche (" .. guis .. ")")

-- Tastatur: keine Knöpfe (Tasten Q/E), zurück auf Touch: wieder da
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Keyboard)
step(0.5)
check(not shown(), "Tastatur: keine Zuschauer-Knöpfe")
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
step(0.5)
check(not shown(), "Controller: keine Zuschauer-Knöpfe")
UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
step(0.5)
check(shown(), "wieder Touch: Knöpfe wieder da")

-- kein Teammitglied lebt mehr: Blick von oben, keine Knöpfe
humanoids[ann].Health = 0
humanoids[carl].Health = 0
step(0.5)
check(not shown(), "ohne lebendes Teammitglied: keine Knöpfe")
humanoids[ann].Health = 100
step(0.5)
check(shown() and camera.CameraSubject == humanoids[ann], "Ann lebt wieder: Knöpfe und Zuschauen")

-- Respawn: Zuschauen endet, Knöpfe weg
local rig, humanoid = SIM.MakeRig("Bob")
rig.Parent = workspace
bob.Character:Destroy()
bob.Character = rig
humanoids[bob] = humanoid
bob.CharacterAdded:Fire(rig)
step(0.5)
check(not shown(), "Respawn: Zuschauer-Knöpfe weg")
check(camera.CameraSubject == humanoid, "Kamera wieder beim eigenen Charakter")

-- außerhalb eines Team-Modus nie
humanoid.Health = 0
bob:SetAttribute("Mode", "FreeForAll")
step(0.5)
check(not shown(), "Jeder gegen jeden: kein Zuschauen, keine Knöpfe")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

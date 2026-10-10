-- Touch-Knöpfe auf kleinen Bildschirmen (Handy quer, 800 x 360): die kleinen Knöpfe oben rechts (PING, KAMERA,
-- INSPEKT) stehen als Reihe oben statt als Spalte, die auf LADEN, FEUER und SPRUNG läge; auf großen Bildschirmen
-- bleibt die Spalte.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

SIM.IsServer = false
local alice = SIM.AddPlayer("Alice", 1001)
rawget(SIM.Players, "__props").LocalPlayer = alice
local playerGui = alice:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", alice)
alice:SetAttribute("Mode", "Extinction")
local camera = workspace.CurrentCamera
camera.ViewportSize = Vector2.new(800, 360)

local InputActions = require("InputActions")
InputActions.Init()
game:GetService("UserInputService").LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
check(InputActions.IsTouch(), "Gerät ist Touch")
local TouchControls = require("TouchControls")
TouchControls.Init()
SIM.Advance(0.1, 10)

local gui = playerGui:FindFirstChild("TouchControls")
local root = gui and gui:FindFirstChild("Root")
local function button(name)
	return root and root:FindFirstChild(name)
end
check(gui and gui.Enabled, "Touch-Knöpfe an")
local ping, cameraButton, inspect = button("Ping"), button("Camera"), button("Inspect")
check(ping and cameraButton and inspect, "PING, KAMERA, INSPEKT da")
if ping and cameraButton and inspect then
	check(ping.Position.Y.Offset == cameraButton.Position.Y.Offset and ping.Position.Y.Offset == inspect.Position.Y.Offset
		and ping.Position.Y.Scale == 0, "Handy: die drei stehen in einer Reihe oben (" .. tostring(ping.Position) .. ")")
	check(ping.Position.X.Offset > cameraButton.Position.X.Offset and cameraButton.Position.X.Offset > inspect.Position.X.Offset,
		"Reihe von rechts nach links: PING, KAMERA, INSPEKT")
	-- kein Kreis der Reihe überlappt einen der großen Knöpfe rechts (Abstand der Mitten > Summe der Radien)
	local layer = Vector2.new(800, 360) / 0.7
	local function center(b)
		return Vector2.new(b.Position.X.Scale * layer.X + b.Position.X.Offset, b.Position.Y.Scale * layer.Y + b.Position.Y.Offset)
	end
	for _, small in { ping, cameraButton, inspect } do
		for _, child in root:GetChildren() do
			if child:IsA("TextButton") and child.Visible and child ~= ping and child ~= cameraButton and child ~= inspect then
				local distance = (center(small) - center(child)).Magnitude
				check(distance > (small.Size.X.Offset + child.Size.X.Offset) / 2,
					small.Name .. " überlappt " .. child.Name .. " (" .. math.floor(distance) .. ")")
			end
		end
	end
end

-- großer Bildschirm (Tablet): wieder die Spalte
camera.ViewportSize = Vector2.new(1024, 768)
SIM.Advance(0.1, 10)
if ping and cameraButton then
	check(ping.Position.X.Offset == cameraButton.Position.X.Offset and ping.Position.Y.Offset < cameraButton.Position.Y.Offset,
		"Tablet: Spalte oben rechts")
end

if failures == 0 then
	print("ok touchlayout")
end

-- InputActions (ModuleScript, nur Client)
-- Eine Stelle für alle Spiel-Aktionen auf Tastatur/Maus, Controller (PlayStation/Xbox) und Touch.
-- Module melden sich mit InputActions.Bind("Fire", function(began) ... end) an, statt selbst
-- Tasten abzufragen. Touch-Knöpfe (TouchControls) lösen dieselben Aktionen über InputActions.Trigger aus.
-- Hint(action) liefert die passende Tastenbeschriftung für das zuletzt benutzte Gerät ("Q", "L1", ...).

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local InputActions = {}

-- Belegung: Keys = Tastatur/Maus, Pad = Controller (antippen), PadHold = Controller gedrückt halten (HOLD_TIME).
-- Liegt auf einer Controller-Taste auch eine Halten-Aktion, lösen die Antippen-Aktionen erst beim Loslassen aus
-- (kurz gedrückt), sonst nach HOLD_TIME die Halten-Aktion. Namen der Controller-Tasten im PlayStation-Stil.
InputActions.Bindings = {
	Fire = { Keys = { Enum.UserInputType.MouseButton1 }, Pad = { Enum.KeyCode.ButtonR2 } },
	Aim = { Keys = { Enum.UserInputType.MouseButton2 }, Pad = { Enum.KeyCode.ButtonL2 } },
	Reload = { Keys = { Enum.KeyCode.R }, Pad = { Enum.KeyCode.ButtonX } },
	Interact = { Keys = { Enum.KeyCode.E }, Pad = { Enum.KeyCode.ButtonX } }, -- Vorrang vor Nachladen, wenn möglich
	Melee = { Keys = { Enum.KeyCode.V }, Pad = { Enum.KeyCode.ButtonR3 } },
	Weapon1 = { Keys = { Enum.KeyCode.One }, Pad = {} },
	Weapon2 = { Keys = { Enum.KeyCode.Two }, Pad = {} },
	SwapWeapon = { Keys = {}, Pad = { Enum.KeyCode.ButtonY } },
	Ability = { Keys = { Enum.KeyCode.Q }, Pad = { Enum.KeyCode.ButtonL1 } },
	Gadget = { Keys = { Enum.KeyCode.G }, Pad = { Enum.KeyCode.ButtonR1 } },
	Ultimate = { Keys = { Enum.KeyCode.F }, Pad = {} }, -- Controller: L1 + R1 zusammen (siehe InputBegan)
	Sprint = { Keys = { Enum.KeyCode.LeftShift }, Pad = { Enum.KeyCode.ButtonL3 } },
	Crouch = { Keys = { Enum.KeyCode.LeftControl, Enum.KeyCode.C }, Pad = { Enum.KeyCode.ButtonB } },
	Ping = { Keys = { Enum.KeyCode.Z }, Pad = { Enum.KeyCode.DPadUp } },
	Scoreboard = { Keys = { Enum.KeyCode.Tab }, Pad = { Enum.KeyCode.ButtonSelect } },
	-- Select/Touchpad lässt Roblox auf Konsolen die Menü-Knöpfe auswählen, darum Steuerkreuz unten
	Menu = { Keys = { Enum.KeyCode.M }, Pad = { Enum.KeyCode.DPadDown } },
	Camera = { Keys = { Enum.KeyCode.T }, Pad = { Enum.KeyCode.DPadLeft } },
	Shoulder = { Keys = { Enum.KeyCode.H }, Pad = { Enum.KeyCode.DPadRight } },
	-- Killstreaks (Herrschaft): Tasten 4/5/6, Controller: Steuerkreuz rechts löst die erste bereite aus
	Killstreak1 = { Keys = { Enum.KeyCode.Four }, Pad = {} },
	Killstreak2 = { Keys = { Enum.KeyCode.Five }, Pad = {} },
	Killstreak3 = { Keys = { Enum.KeyCode.Six }, Pad = {} },
	KillstreakPad = { Keys = {}, Pad = { Enum.KeyCode.DPadRight } },
	SpectatePrev = { Keys = { Enum.KeyCode.Q }, Pad = { Enum.KeyCode.ButtonL1 } },
	SpectateNext = { Keys = { Enum.KeyCode.E }, Pad = { Enum.KeyCode.ButtonR1 } },
	Jump = { Keys = {}, Pad = {} }, -- nur der Touch-Knopf (Tastatur/Controller springen über Roblox)
	-- Waffe inspizieren; Controller: □ bei vollem Magazin (WeaponClient), Touch: Knopf INSPEKT
	Inspect = { Keys = { Enum.KeyCode.X }, Pad = {} },
}

-- Beschriftungen für Controller-Tasten: PlayStation-Symbole oder Xbox-Buchstaben (je nach Konsole, siehe PadStyle)
local PAD_NAMES = {
	PlayStation = {
		[Enum.KeyCode.ButtonR2] = "R2", [Enum.KeyCode.ButtonL2] = "L2", [Enum.KeyCode.ButtonR1] = "R1",
		[Enum.KeyCode.ButtonL1] = "L1", [Enum.KeyCode.ButtonR3] = "R3", [Enum.KeyCode.ButtonL3] = "L3",
		[Enum.KeyCode.ButtonX] = "□", [Enum.KeyCode.ButtonY] = "△", [Enum.KeyCode.ButtonB] = "○",
		[Enum.KeyCode.ButtonA] = "✕", [Enum.KeyCode.ButtonSelect] = "TOUCH", [Enum.KeyCode.DPadUp] = "↑",
		[Enum.KeyCode.DPadDown] = "↓", [Enum.KeyCode.DPadLeft] = "←", [Enum.KeyCode.DPadRight] = "→",
		[Enum.KeyCode.Thumbstick1] = "L-STICK", [Enum.KeyCode.Thumbstick2] = "R-STICK",
	},
	Xbox = {
		[Enum.KeyCode.ButtonR2] = "RT", [Enum.KeyCode.ButtonL2] = "LT", [Enum.KeyCode.ButtonR1] = "RB",
		[Enum.KeyCode.ButtonL1] = "LB", [Enum.KeyCode.ButtonR3] = "RS", [Enum.KeyCode.ButtonL3] = "LS",
		[Enum.KeyCode.ButtonX] = "X", [Enum.KeyCode.ButtonY] = "Y", [Enum.KeyCode.ButtonB] = "B",
		[Enum.KeyCode.ButtonA] = "A", [Enum.KeyCode.ButtonSelect] = "VIEW", [Enum.KeyCode.DPadUp] = "↑",
		[Enum.KeyCode.DPadDown] = "↓", [Enum.KeyCode.DPadLeft] = "←", [Enum.KeyCode.DPadRight] = "→",
		[Enum.KeyCode.Thumbstick1] = "L-STICK", [Enum.KeyCode.Thumbstick2] = "R-STICK",
	},
}
local KEY_NAMES = {
	[Enum.UserInputType.MouseButton1] = "LMB", [Enum.UserInputType.MouseButton2] = "RMB",
	[Enum.KeyCode.LeftShift] = "SHIFT", [Enum.KeyCode.LeftControl] = "STRG", [Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2", [Enum.KeyCode.Tab] = "TAB", [Enum.KeyCode.Four] = "4", [Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6", [Enum.KeyCode.Three] = "3", [Enum.KeyCode.Seven] = "7", [Enum.KeyCode.Eight] = "8",
	[Enum.KeyCode.Nine] = "9",
}

-- Welche Tastensymbole? Roblox nennt die Tasten auf der PlayStation "ButtonCross" usw., auf Xbox und am PC "ButtonA".
-- Ohne Antwort (älterer Client, Tests): PlayStation wie bisher.
local padStyle = nil
function InputActions.PadStyle()
	if not padStyle then
		local ok, name = pcall(function()
			return UserInputService:GetStringForKeyCode(Enum.KeyCode.ButtonA)
		end)
		padStyle = (ok and name == "ButtonA") and "Xbox" or "PlayStation"
	end
	return padStyle
end

-- Beschriftung einer Controller-Taste im Stil der Konsole ("✕" / "A", "R1" / "RB")
function InputActions.PadName(keyCode)
	local names = PAD_NAMES[InputActions.PadStyle()]
	return names[keyCode] or keyCode.Name
end

-- Bild der Controller-Taste, wie Roblox es auf dieser Konsole zeigt (nil, wenn es keins gibt)
function InputActions.PadImage(keyCode)
	local ok, image = pcall(function()
		return UserInputService:GetImageForKeyCode(keyCode)
	end)
	return (ok and type(image) == "string" and image ~= "") and image or nil
end

-- Fernseher-Oberfläche (PlayStation, Xbox): größere Schrift und Bedienung nur mit dem Controller
function InputActions.IsConsole()
	local ok, result = pcall(function()
		return GuiService:IsTenFootInterface()
	end)
	return ok and result == true
end

InputActions.HoldTime = 0.35 -- so lange halten, bis eine PadHold-Aktion auslöst

local handlers = {}  -- [Aktion] = { Callback, ... }
local held = {}      -- [Aktion] = true, solange gedrückt
local device = "Keyboard" -- "Keyboard", "Gamepad" oder "Touch"
local deviceChanged = Instance.new("BindableEvent")
InputActions.DeviceChanged = deviceChanged.Event

-- Gibt es gerade etwas zum Interagieren (Wiederbeleben, Bombe)? Dann hat □ Vorrang vor Nachladen.
local interactSources = {}
function InputActions.SetInteractAvailable(source, available)
	interactSources[source] = available or nil
end
local function interactAvailable()
	return next(interactSources) ~= nil
end
InputActions.InteractAvailable = interactAvailable

function InputActions.Bind(action, callback)
	handlers[action] = handlers[action] or {}
	table.insert(handlers[action], callback)
end

function InputActions.IsHeld(action)
	return held[action] == true
end

-- Aktion auslösen (auch von Touch-Knöpfen). began = true beim Drücken, false beim Loslassen.
function InputActions.Trigger(action, began)
	if began then
		held[action] = true
	else
		held[action] = nil
	end
	for _, callback in handlers[action] or {} do
		task.spawn(callback, began)
	end
end

function InputActions.Device()
	return device
end

function InputActions.IsTouch()
	return device == "Touch"
end

-- Ist ein Knopf wirklich zu sehen (er selbst und alle Eltern bis zum ScreenGui sichtbar)?
local function shown(object)
	local current = object
	while current and not current:IsA("LayerCollector") do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current ~= nil and current.Enabled and object.AbsoluteSize.X > 0
end

local focusContainer = nil -- zuletzt mit Focus gewähltes Fenster (Wächter in Init holt die Auswahl dorthin zurück)

-- Controller: Auswahl auf einen Knopf setzen, damit Menüs ohne Maus bedienbar sind.
-- preferred = gewünschter Knopf; sonst der oberste linke sichtbare Knopf in container.
-- Knöpfe mit Attribut NoFocus (z.B. Schließen-Kreuz) werden dabei übersprungen. Ohne Controller passiert nichts.
function InputActions.Focus(container, preferred)
	if device ~= "Gamepad" or not container then
		return
	end
	task.defer(function() -- erst nach dem Aufbau/Layout der Seite
		local target = preferred and preferred:IsA("GuiObject") and shown(preferred) and preferred or nil
		if not target then
			for _, object in container:GetDescendants() do
				if object:IsA("GuiButton") and object.Selectable and not object:GetAttribute("NoFocus") and shown(object) then
					local pos, best = object.AbsolutePosition, target and target.AbsolutePosition
					if not best or pos.Y < best.Y - 4 or (math.abs(pos.Y - best.Y) <= 4 and pos.X < best.X) then
						target = object
					end
				end
			end
		end
		if target then
			GuiService.SelectedObject = target
		end
	end)
	-- Steuerkreuz und Stick bleiben im Fenster: Roblox würde sonst zu Knöpfen anderer Ebenen springen (HUD, Abzeichen)
	local top = container
	while top.Parent and top.Parent:IsA("GuiObject") do
		top = top.Parent
	end
	if top:IsA("GuiObject") then
		top.SelectionGroup = true
		top.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
		top.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
		top.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
		top.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	end
	focusContainer = container
end

-- Knöpfe einer Ebene (HUD, Touch-Knöpfe) nie mit dem Controller auswählbar: sonst landet die Auswahl dort, und der
-- Stick bewegt die Auswahl statt der Spielfigur
function InputActions.NoSelect(root)
	local function apply(object)
		if object:IsA("GuiButton") or object:IsA("TextBox") then
			object.Selectable = false
		end
	end
	for _, object in root:GetDescendants() do
		apply(object)
	end
	root.DescendantAdded:Connect(apply)
end

-- Namenspfad der zuletzt gewählten Auswahl (vom ScreenGui abwärts), damit Refocus nach einem Neuaufbau den
-- gleichnamigen neuen Knopf wiederfindet
local lastPath = nil
local function pathOf(object)
	local path = {}
	local current = object
	while current and not current:IsA("LayerCollector") do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end
	return current and path or nil, current
end
GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
	local selected = GuiService.SelectedObject
	if selected then
		local path, gui = pathOf(selected)
		lastPath = path and { Gui = gui, Names = path } or nil
	end
end)

-- Den Knopf mit demselben Namenspfad wie die letzte Auswahl in container suchen (nil, wenn es ihn nicht mehr gibt)
local function sameAsLast(container)
	local own, gui = pathOf(container)
	if not (lastPath and own and gui == lastPath.Gui and #lastPath.Names > #own) then
		return nil
	end
	for index, name in own do
		if lastPath.Names[index] ~= name then
			return nil
		end
	end
	local current = container
	for index = #own + 1, #lastPath.Names do
		current = current:FindFirstChild(lastPath.Names[index])
		if not current then
			return nil
		end
	end
	return current:IsA("GuiButton") and current or nil
end

-- Nach einem Neuaufbau: nur dann neu auswählen, wenn die Auswahl nicht mehr in container liegt (z.B. weil der
-- gewählte Knopf beim Neuaufbau verschwand). Dann bevorzugt den gleichnamigen neuen Knopf an derselben Stelle,
-- sonst den ersten – so springt die Auswahl nicht bei jedem Update zurück an den Anfang
function InputActions.Refocus(container)
	if device ~= "Gamepad" or not container then
		return
	end
	task.defer(function()
		local selected = GuiService.SelectedObject
		if not (selected and selected:IsDescendantOf(container)) and container.Parent then
			InputActions.Focus(container, sameAsLast(container))
		end
	end)
end

-- Auswahl aufheben, falls sie in container liegt (z.B. wenn ein Fenster schließt)
function InputActions.Unfocus(container)
	local selected = GuiService.SelectedObject
	if selected and container and selected:IsDescendantOf(container) then
		GuiService.SelectedObject = nil
	end
end

-- Tastenbeschriftung für das aktuelle Gerät ("" bei Touch: dort gibt es eigene Knöpfe)
function InputActions.Hint(action)
	local binding = InputActions.Bindings[action]
	if not binding or device == "Touch" then
		return ""
	end
	if device == "Gamepad" then
		if action == "Ultimate" then
			return InputActions.PadName(Enum.KeyCode.ButtonL1) .. "+" .. InputActions.PadName(Enum.KeyCode.ButtonR1)
		end
		local code = binding.Pad[1]
		if code then
			return InputActions.PadName(code)
		end
		local hold = binding.PadHold and binding.PadHold[1]
		return hold and (InputActions.PadName(hold) .. " HALTEN") or ""
	end
	local code = binding.Keys[1]
	return code and (KEY_NAMES[code] or code.Name) or ""
end

-- Auswahlrahmen im Stil des Spiels (roter Rand statt des dünnen Roblox-Rahmens, auf dem Fernseher gut zu sehen) und
-- Wächter: Ist ein Fenster offen, aber nichts ausgewählt (Knopf beim Neuaufbau verschwunden, Fenster noch im Aufbau),
-- holt er die Auswahl ins zuletzt fokussierte Fenster zurück – sonst liefe die Figur hinter dem Menü los
InputActions.SelectionColor = Color3.fromRGB(214, 58, 58)
function InputActions.SetupSelection()
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player and player:WaitForChild("PlayerGui", 30)
	if playerGui then
		local frame = Instance.new("Frame")
		frame.Name = "PadSelection"
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.BackgroundTransparency = 0.9
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, 8, 1, 8)
		frame.Position = UDim2.fromOffset(-4, -4)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = InputActions.SelectionColor
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
		pcall(function()
			(playerGui :: any).SelectionImageObject = frame
		end)
	end
	local UITheme = require(script.Parent:WaitForChild("UITheme")) :: any
	local nextCheck = 0
	game:GetService("RunService").Heartbeat:Connect(function()
		local now = os.clock()
		if device ~= "Gamepad" or now < nextCheck then
			return
		end
		nextCheck = now + 0.3
		local container = focusContainer
		if not (container and container.Parent and UITheme.IsMenuOpen() and shown(container)) then
			return
		end
		local selected = GuiService.SelectedObject
		if selected and selected.Parent and shown(selected) then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return -- Bildschirmtastatur offen
		end
		InputActions.Focus(container, sameAsLast(container))
	end)
end

local function matches(list, input)
	for _, code in list do
		if input.KeyCode == code or input.UserInputType == code then
			return true
		end
	end
	return false
end

-- Halten-Aktionen dieser Controller-Taste (PadHold)
local function holdActionsFor(input)
	local result = {}
	if input.UserInputType.Name:sub(1, 7) ~= "Gamepad" then
		return result
	end
	for action, binding in InputActions.Bindings do
		if binding.PadHold and matches(binding.PadHold, input) then
			table.insert(result, action)
		end
	end
	return result
end

-- Welche Aktionen gehören zu dieser Eingabe?
local function actionsFor(input)
	local isPad = input.UserInputType.Name:sub(1, 7) == "Gamepad"
	local result = {}
	for action, binding in InputActions.Bindings do
		if matches(isPad and binding.Pad or binding.Keys, input) then
			table.insert(result, action)
		end
	end
	-- □ auf dem Controller: entweder Interagieren oder Nachladen, nicht beides
	if isPad and input.KeyCode == Enum.KeyCode.ButtonX then
		local keep = interactAvailable() and "Interact" or "Reload"
		for i = #result, 1, -1 do
			if (result[i] == "Interact" or result[i] == "Reload") and result[i] ~= keep then
				table.remove(result, i)
			end
		end
	end
	return result
end

local function setDevice(new)
	if new ~= device then
		device = new
		padStyle = nil -- neu bestimmen (anderer Controller angesteckt)
		deviceChanged:Fire(new)
	end
end

local function updateDevice(inputType)
	if inputType == Enum.UserInputType.Touch then
		setDevice("Touch")
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		setDevice("Gamepad")
	elseif inputType == Enum.UserInputType.Keyboard or inputType.Name:sub(1, 5) == "Mouse" then
		setDevice("Keyboard")
	end
end

-- Merkt sich, welche Aktionen durch welche Eingabe gestartet wurden (für das Loslassen)
local active = {}
local pending = {} -- [input] = { Tap = Liste, Hold = Liste, Fired = bool }: Taste mit Antippen/Halten, noch offen

function InputActions.Init()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		device = "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		device = "Gamepad"
	end
	UserInputService.LastInputTypeChanged:Connect(updateDevice)
	-- Konsole: Select/Touchpad soll nicht irgendeinen Knopf auswählen (Roblox-Standard) – die Taste öffnet das
	-- Inventar, die Auswahl setzen die Fenster selbst (Focus)
	pcall(function()
		GuiService.AutoSelectGuiEnabled = false
	end)
	task.spawn(InputActions.SetupSelection)

	UserInputService.InputBegan:Connect(function(input, processed)
		-- Controller-Tasten zählen auch, wenn gerade ein Knopf ausgewählt ist (nur nicht ✕/○ im Menü)
		if processed and not (input.UserInputType.Name:sub(1, 7) == "Gamepad" and input.KeyCode ~= Enum.KeyCode.ButtonA
			and input.KeyCode ~= Enum.KeyCode.ButtonB) then
			return
		end
		-- Steuerkreuz bei ausgewähltem Knopf ist Menü-Navigation (sonst schließt ↓ das Menü, ↑ pingt …)
		if processed and GuiService.SelectedObject ~= nil and input.KeyCode.Name:sub(1, 4) == "DPad" then
			return
		end
		local list = actionsFor(input)
		-- Controller: L1 + R1 zusammen = Ultimate (die zweite Taste löst dann nicht ihre eigene Aktion aus)
		if (input.KeyCode == Enum.KeyCode.ButtonL1 and held.Gadget) or (input.KeyCode == Enum.KeyCode.ButtonR1 and held.Ability) then
			list = { "Ultimate" }
		end
		-- Antippen oder Halten? Erst entscheiden, wenn klar ist, wie lange die Taste gedrückt ist
		local holdList = holdActionsFor(input)
		if #holdList > 0 then
			local entry = { Tap = list, Hold = holdList, Fired = false }
			pending[input] = entry
			task.delay(InputActions.HoldTime, function()
				if pending[input] == entry then
					entry.Fired = true
					for _, action in holdList do
						InputActions.Trigger(action, true)
					end
				end
			end)
			return
		end
		if #list > 0 then
			active[input] = list
			for _, action in list do
				InputActions.Trigger(action, true)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local entry = pending[input]
		if entry then
			pending[input] = nil
			if entry.Fired then
				for _, action in entry.Hold do
					InputActions.Trigger(action, false)
				end
			else
				-- kurz gedrückt: die Antippen-Aktionen einmal drücken und loslassen
				for _, action in entry.Tap do
					InputActions.Trigger(action, true)
				end
				for _, action in entry.Tap do
					InputActions.Trigger(action, false)
				end
			end
			return
		end
		local list = active[input] or actionsFor(input)
		active[input] = nil
		for _, action in list do
			if held[action] then
				InputActions.Trigger(action, false)
			end
		end
	end)
end

return InputActions

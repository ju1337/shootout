-- InputActions (ModuleScript, nur Client)
-- Eine Stelle für alle Spiel-Aktionen auf Tastatur/Maus, Controller (PlayStation/Xbox) und Touch.
-- Module melden sich mit InputActions.Bind("Fire", function(began) ... end) an, statt selbst
-- Tasten abzufragen. Touch-Knöpfe (TouchControls) lösen dieselben Aktionen über InputActions.Trigger aus.
-- Hint(action) liefert die passende Tastenbeschriftung für das zuletzt benutzte Gerät ("Q", "L1", ...).

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local InputActions = {}

-- Belegung: Keys = Tastatur/Maus, Pad = Controller. Namen der Controller-Tasten im PlayStation-Stil.
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
}

-- Beschriftungen für Controller-Tasten (PlayStation)
local PAD_NAMES = {
	[Enum.KeyCode.ButtonR2] = "R2", [Enum.KeyCode.ButtonL2] = "L2", [Enum.KeyCode.ButtonR1] = "R1",
	[Enum.KeyCode.ButtonL1] = "L1", [Enum.KeyCode.ButtonR3] = "R3", [Enum.KeyCode.ButtonL3] = "L3",
	[Enum.KeyCode.ButtonX] = "□", [Enum.KeyCode.ButtonY] = "△", [Enum.KeyCode.ButtonB] = "○",
	[Enum.KeyCode.ButtonA] = "✕", [Enum.KeyCode.ButtonSelect] = "TOUCH", [Enum.KeyCode.DPadUp] = "↑",
	[Enum.KeyCode.DPadDown] = "↓", [Enum.KeyCode.DPadLeft] = "←", [Enum.KeyCode.DPadRight] = "→",
}
local KEY_NAMES = {
	[Enum.UserInputType.MouseButton1] = "LMB", [Enum.UserInputType.MouseButton2] = "RMB",
	[Enum.KeyCode.LeftShift] = "SHIFT", [Enum.KeyCode.LeftControl] = "STRG", [Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2", [Enum.KeyCode.Tab] = "TAB", [Enum.KeyCode.Four] = "4", [Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
}

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
			return "L1+R1"
		end
		local code = binding.Pad[1]
		return code and (PAD_NAMES[code] or code.Name) or ""
	end
	local code = binding.Keys[1]
	return code and (KEY_NAMES[code] or code.Name) or ""
end

local function matches(list, input)
	for _, code in list do
		if input.KeyCode == code or input.UserInputType == code then
			return true
		end
	end
	return false
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

function InputActions.Init()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		device = "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		device = "Gamepad"
	end
	UserInputService.LastInputTypeChanged:Connect(updateDevice)

	UserInputService.InputBegan:Connect(function(input, processed)
		-- Controller-Tasten zählen auch, wenn gerade ein Knopf ausgewählt ist (nur nicht ✕/○ im Menü)
		if processed and not (input.UserInputType.Name:sub(1, 7) == "Gamepad" and input.KeyCode ~= Enum.KeyCode.ButtonA
			and input.KeyCode ~= Enum.KeyCode.ButtonB) then
			return
		end
		local list = actionsFor(input)
		-- Controller: L1 + R1 zusammen = Ultimate (die zweite Taste löst dann nicht ihre eigene Aktion aus)
		if (input.KeyCode == Enum.KeyCode.ButtonL1 and held.Gadget) or (input.KeyCode == Enum.KeyCode.ButtonR1 and held.Ability) then
			list = { "Ultimate" }
		end
		if #list > 0 then
			active[input] = list
			for _, action in list do
				InputActions.Trigger(action, true)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
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

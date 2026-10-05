-- TouchControls (ModuleScript, nur Client)
-- Bildschirm-Knöpfe für Handy/Tablet. Jeder Knopf löst eine Aktion aus InputActions aus, damit
-- Schießen, Fähigkeiten usw. genauso funktionieren wie auf Tastatur und Controller.
-- Sichtbar nur auf Touch-Geräten in Kampfmodi. Der Standard-Springen-Knopf von Roblox wird durch einen
-- eigenen ersetzt, damit er nicht unter den anderen Knöpfen liegt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local InputActions = require(Shared.InputActions)
local C = UITheme.Colors
local make = UITheme.Make

local player = Players.LocalPlayer

local TouchControls = {}

-- { Aktion, Beschriftung, Größe, X von rechts, Y von unten, Art } – Art: "hold" (gedrückt halten),
-- "tap" (antippen) oder "toggle" (an/aus). Positionen in Design-Einheiten (1600 x 900).
-- Beschriftung: kurze Wörter statt Symbole (Symbole fehlen teils in den Schriften, Emojis wirken verspielt).
local RIGHT = {
	{ "Fire", "FEUER", 130, 130, 170, "hold" },
	{ "Jump", "SPRUNG", 80, 90, 55, "tap" },
	{ "Aim", "ZIELEN", 84, 290, 130, "toggle" },
	{ "Crouch", "DUCKEN", 70, 235, 48, "tap" },
	{ "Reload", "LADEN", 70, 70, 290, "tap" },
	{ "Ability", "FÄHIGK.", 84, 200, 305, "tap" },
	{ "Gadget", "GADGET", 72, 305, 245, "tap" },
	{ "Melee", "MESSER", 60, 60, 375, "tap" },
	{ "SwapWeapon", "WAFFE", 64, 380, 60, "tap" },
	{ "Interact", "AKTION", 84, 420, 200, "hold" },
}
-- Kleine Knöpfe oben rechts
local TOP = {
	{ "Ping", "PING", 56, 60, 250, "tap" },
	{ "Scoreboard", "PUNKTE", 56, 60, 316, "tap" },
	{ "Camera", "KAMERA", 56, 60, 382, "tap" },
	{ "Ultimate", "ULT", 56, 60, 448, "tap" },
}
-- Links über dem Steuerknüppel
local LEFT = {
	{ "Sprint", "SPRINT", 66, 110, 330, "toggle" },
}
-- Nur in der offenen Welt (EXTINCTION): Inventar und Fahrzeug einpacken, an den Plätzen von Fähigkeit und Gadget
-- (dort gibt es nur passive Fähigkeiten). WAFFE wechselt dort durch die Waffen der Hotbar (ExtinctionClient).
local SURVIVAL = {
	{ "Inventory", "TASCHE", 84, 200, 305, "tap" },
	{ "StoreVehicle", "PARKEN", 72, 305, 245, "tap" },
}
local SURVIVAL_HIDDEN = { Ability = true, Gadget = true, Ultimate = true, Scoreboard = true }

local gui
local buttons = {} -- [Aktion] = Knopf

local function makeButton(parent, entry, anchor)
	local action, icon, size, x, y, kind = table.unpack(entry)
	local position
	if anchor == "right" then
		position = UDim2.new(1, -x, 1, -y)
	elseif anchor == "top" then
		position = UDim2.new(1, -x, 0, y)
	else
		position = UDim2.new(0, x, 1, -y)
	end
	-- Wörter kleiner als einzelne Zeichen
	local word = (utf8.len(icon) or 1) > 2
	local button = make("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = position,
		Size = UDim2.new(0, size, 0, size), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.35, Text = icon,
		TextSize = math.floor(size * (word and 0.2 or 0.45)), Font = UITheme.Fonts.Bold, TextColor3 = C.Text,
		AutoButtonColor = false, BorderSizePixel = 0, Name = action }, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, button)
	local stroke = UITheme.Stroke(button, action == "Fire" and C.Bad or C.Border, 1.5, 0.1)
	local on = false
	local function setVisual(pressed)
		button.BackgroundTransparency = pressed and 0.05 or 0.35
		button.BackgroundColor3 = pressed and (action == "Fire" and C.Bad or C.AccentDark) or C.Panel
	end
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if kind == "toggle" then
			on = not on
			setVisual(on)
			InputActions.Trigger(action, on)
		else
			setVisual(true)
			InputActions.Trigger(action, true)
			if kind == "tap" then
				task.delay(0.08, function()
					InputActions.Trigger(action, false)
				end)
			end
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or kind == "toggle" then
			return
		end
		setVisual(false)
		if kind == "hold" then
			InputActions.Trigger(action, false)
		end
	end)
	buttons[action] = { Button = button, Stroke = stroke, Reset = function()
		if on then
			on = false
			setVisual(false)
			InputActions.Trigger(action, false)
		end
	end }
	return button
end

-- Roblox-Standard-Springen-Knopf im Kampf ausblenden (wir haben einen eigenen), im Hub zeigen
local function setDefaultJump(visible)
	local touchGui = player.PlayerGui:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if jump then
		jump.Visible = visible
	end
end

function TouchControls.Init()
	gui = make("ScreenGui", { Name = "TouchControls", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 4,
		Enabled = false }, player:WaitForChild("PlayerGui"))
	-- Etwas größer skaliert als das HUD, damit die Knöpfe gut mit dem Daumen treffbar bleiben
	local root = UITheme.ScaledRoot(gui, 1600, 900, 0.7)
	for _, entry in RIGHT do
		makeButton(root, entry, "right")
	end
	for _, entry in TOP do
		makeButton(root, entry, "top")
	end
	for _, entry in LEFT do
		makeButton(root, entry, "left")
	end
	for _, entry in SURVIVAL do
		makeButton(root, entry, "right")
	end

	-- Springen: Charakter springen lassen (Klettern an Kanten erledigt Movement über dieselbe Aktion)
	InputActions.Bind("Jump", function(began)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if began and humanoid then
			humanoid.Jump = true
		end
	end)

	local lastCheck = 0
	RunService.Heartbeat:Connect(function()
		local show = InputActions.IsTouch() and Modes.IsFighting(player)
		if show ~= gui.Enabled then
			gui.Enabled = show
			if not show then
				-- Umschalter zurücksetzen (z.B. Zielen), damit nichts "hängen" bleibt
				for _, entry in buttons do
					entry.Reset()
				end
			end
		end
		if os.clock() - lastCheck > 1 then
			lastCheck = os.clock()
			setDefaultJump(not show)
		end
		if not show then
			return
		end
		-- Interagieren nur zeigen, wenn es etwas gibt (Wiederbeleben, Bombe, Hacken)
		buttons.Interact.Button.Visible = player:GetAttribute("ObjHint") ~= nil or InputActions.InteractAvailable()
		-- offene Welt: TASCHE und PARKEN statt Fähigkeit, Gadget, Ultimate und Punkte
		local survival = Modes.IsSurvival(player:GetAttribute("Mode"))
		for action in SURVIVAL_HIDDEN do
			buttons[action].Button.Visible = not survival
		end
		for _, entry in SURVIVAL do
			buttons[entry[1]].Button.Visible = survival
		end
		-- Gadget leer: Knopf abdunkeln
		local charges = player:GetAttribute("Gadgets") or 0
		buttons.Gadget.Button.TextTransparency = charges > 0 and 0 or 0.6
		-- Fähigkeit lädt: Knopf abdunkeln
		local ready = (player:GetAttribute("AbilityReadyAt") or 0) <= workspace:GetServerTimeNow()
		buttons.Ability.Button.TextTransparency = ready and 0 or 0.6
		buttons.Ability.Stroke.Color = ready and C.Accent or C.Border
		-- Ultimate erst bei voller Ladung hervorheben
		local ultReady = (player:GetAttribute("UltCharge") or 0) >= 100
		buttons.Ultimate.Button.TextTransparency = ultReady and 0 or 0.6
		buttons.Ultimate.Stroke.Color = ultReady and C.Primary or C.Border
	end)
end

return TouchControls

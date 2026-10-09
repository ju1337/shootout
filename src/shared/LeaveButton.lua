-- LeaveButton (ModuleScript, nur Client)
-- VERLASSEN-Knopf: der erste Klick fragt nach (rot, "WIRKLICH VERLASSEN?"), ein zweiter Klick innerhalb von
-- CONFIRM_TIME Sekunden bringt einen zurück ins Camp (Safe Zone der offenen Welt, Modes.Home). Im Match-HUD unter der
-- Minimap und in der Map-Abstimmung (die das HUD verdeckt). In der offenen Welt selbst gibt es nichts zu verlassen:
-- dort heißt der Knopf LOBBY und öffnet das Spielmenü (Arcade-Modi, Shop, Loadout, Agenten, Battle Pass).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)

local player = Players.LocalPlayer

local LeaveButton = {}

local CONFIRM_TIME = 3 -- so lange wartet VERLASSEN auf den zweiten Klick

-- Öffnet das Spielmenü (setzt GameMenu beim Start; LeaveButton kennt GameMenu nicht selbst)
LeaveButton.OpenMenu = nil :: (() -> ())?

-- Im Startmodus (offene Welt) öffnet der Knopf die Lobby statt zu verlassen
local function atHome()
	return player:GetAttribute("Mode") == Modes.Home
end

-- props wie bei UITheme.Chunky (Name, Size, Position, AnchorPoint ...). Gibt den Knopf (UITheme.Chunky) zurück.
function LeaveButton.new(parent, props)
	props.Color = props.Color or UITheme.Colors.Background
	props.StrokeColor = props.StrokeColor or UITheme.Colors.Border
	props.Text = atHome() and "LOBBY" or "VERLASSEN"
	props.TextSize = props.TextSize or 17
	local button = UITheme.Chunky(props, parent)
	button.Face.BackgroundTransparency = 0.3
	local confirmUntil = 0
	local clicks = 0 -- zählt Klicks, damit verspätete Rücksetzer nur den eigenen Zustand zurücksetzen
	local function reset()
		confirmUntil = 0
		button.SetText(atHome() and "LOBBY" or "VERLASSEN")
		button.SetColor(UITheme.Colors.Background, UITheme.Colors.Text)
		button.SetStroke(UITheme.Colors.Border, 1)
	end
	button.Button.Activated:Connect(function()
		if atHome() then
			if LeaveButton.OpenMenu then
				LeaveButton.OpenMenu()
			end
			return
		end
		clicks += 1
		local click = clicks
		if os.clock() < confirmUntil then
			confirmUntil = 0
			button.SetText("VERLASSE ...")
			Remotes.JoinMode:FireServer(Modes.Home)
			-- Falls der Wechsel ausbleibt, nach kurzer Zeit wieder bedienbar machen
			task.delay(5, function()
				if clicks == click then
					reset()
				end
			end)
			return
		end
		confirmUntil = os.clock() + CONFIRM_TIME
		button.SetText("WIRKLICH VERLASSEN?")
		button.SetColor(UITheme.Colors.Bad, UITheme.Colors.Text)
		button.SetStroke(UITheme.Colors.Bad, 1)
		task.delay(CONFIRM_TIME, function()
			if clicks == click and confirmUntil ~= 0 then
				reset()
			end
		end)
	end)
	player:GetAttributeChangedSignal("Mode"):Connect(reset)
	return button
end

return LeaveButton

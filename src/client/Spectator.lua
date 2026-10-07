-- Spectator (ModuleScript, nur Client)
-- In allen Team-Modi: Wer tot ist (oder mitten in der Runde beitritt), schaut einem
-- lebenden Teammitglied zu (auch Bot-Teamkollegen). Mit E/Q (Controller R1/L1, Handy: Knöpfe ZURÜCK/WEITER unten)
-- wechseln. Ohne Teammitglied: Blick von oben auf die Map.
-- Außerdem bekommen Teammitglieder einen Umriss in Verbündeten-Blau (wie im HUD).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Movement = require(Shared.Movement)
local HUD = require(Shared.HUD)
local Modes = require(Shared.Modes)
local InputActions = require(Shared.InputActions)
local UITheme = require(Shared.UITheme)

local player = Players.LocalPlayer

local Spectator = {}

-- Handy: Knöpfe zum Wechseln (Tastatur und Controller haben Tasten)
local touchGui
local function showTouchButtons(on)
	on = on and InputActions.IsTouch()
	if not on then
		if touchGui then
			touchGui.Enabled = false
		end
		return
	end
	if not touchGui then
		touchGui = UITheme.Make("ScreenGui", { Name = "SpectatorTouch", ResetOnSpawn = false, DisplayOrder = 6 },
			player:WaitForChild("PlayerGui"))
		for i, entry in { { "SpectatePrev", "ZURÜCK" }, { "SpectateNext", "WEITER" } } do
			local button = UITheme.Make("TextButton", { Name = entry[1], AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, (i == 1 and -1 or 1) * 90, 1, -120), Size = UDim2.fromOffset(150, 52),
				BackgroundColor3 = UITheme.Colors.Panel, BackgroundTransparency = 0.25, Text = entry[2], TextSize = 18,
				Font = UITheme.Fonts.Bold, TextColor3 = UITheme.Colors.Text, AutoButtonColor = true, BorderSizePixel = 0 }, touchGui)
			UITheme.Corner(button, 12)
			button.Activated:Connect(function()
				InputActions.Trigger(entry[1], true)
				InputActions.Trigger(entry[1], false)
			end)
		end
	end
	touchGui.Enabled = true
end

-- Kameraflug über die Map des aktuellen Team-Modus (Werte aus Modes.Overview)
local OVERVIEW_SPEED = 0.05  -- Drehgeschwindigkeit (Bogenmaß pro Sekunde), langsamer Kameraflug

-- Kamera kreist langsam um die Drop-Map (Hintergrund der Agentenwahl)
local function overview()
	local info = Modes.Get(player:GetAttribute("Mode")) or Modes.Get("Domination")
	local center = player:GetAttribute("MapCenter") or info.Center -- Map-Rotation
	local overviewInfo = info.Overview or { Radius = 200, Height = 120 }
	local angle = os.clock() * OVERVIEW_SPEED
	local position = center + Vector3.new(math.cos(angle) * overviewInfo.Radius, overviewInfo.Height,
		math.sin(angle) * overviewInfo.Radius)
	return CFrame.lookAt(position, center)
end

local spectating = false
local inOverview = false
local target = nil

-- p: Spieler oder Bot-Modell
local function livingHumanoid(p)
	local character = p:IsA("Player") and p.Character or p
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function livingTeammates()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Team ~= nil and p.Team == player.Team and livingHumanoid(p) then
			table.insert(list, p)
		end
	end
	local botFolder = workspace:FindFirstChild("Bots")
	if botFolder and player.Team then
		for _, model in botFolder:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("TeamName") == player.Team.Name and livingHumanoid(model) then
				table.insert(list, model)
			end
		end
	end
	return list
end

local function isMate(p)
	if p:IsA("Player") then
		return p.Team ~= nil and p.Team == player.Team
	end
	return player.Team ~= nil and p.Parent ~= nil and p:GetAttribute("TeamName") == player.Team.Name
end

-- Nächstes (step = 1) bzw. vorheriges (step = -1) Teammitglied wählen
local function nextTarget(step)
	local list = livingTeammates()
	if #list == 0 then
		return nil
	end
	local index = table.find(list, target) or 0
	return list[(index - 1 + (step or 1)) % #list + 1]
end

local function stopSpectating()
	if not spectating then
		return
	end
	spectating = false
	inOverview = false
	target = nil
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local myHumanoid = livingHumanoid(player)
	if myHumanoid then
		camera.CameraSubject = myHumanoid
	end
	Movement.ApplyCamera()
	HUD.SetStatus("")
	showTouchButtons(false)
end

local function update()
	if workspace.CurrentCamera:GetAttribute("KillCam") then
		return -- Todeskamera zeigt gerade den Killer
	end
	-- Zuschauen nur in Team-Modi (Drop, Strikeout)
	if not Modes.IsTeamMode(player:GetAttribute("Mode")) or livingHumanoid(player) then
		stopSpectating()
		return
	end

	local camera = workspace.CurrentCamera
	if not spectating then
		spectating = true
		Movement.SetFirstPerson(false)
	end
	if not target or not livingHumanoid(target) or not isMate(target) then
		target = nextTarget()
	end
	inOverview = false
	if target then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = livingHumanoid(target)
		local agent = target:IsA("Player") and target.Character and target.Character:GetAttribute("Agent")
			or not target:IsA("Player") and target:GetAttribute("Agent")
		HUD.SetStatus("ZUSCHAUER  ·  " .. string.upper(target.Name) .. (agent and ("  ·  " .. string.upper(agent)) or "")
			.. (InputActions.IsTouch() and "" or ("   [" .. InputActions.Hint("SpectatePrev") .. "] ZURÜCK   WEITER ["
				.. InputActions.Hint("SpectateNext") .. "]")))
		showTouchButtons(true)
	else
		showTouchButtons(false)
		camera.CameraType = Enum.CameraType.Scriptable
		inOverview = true
		HUD.SetStatus("Warte auf Respawn bzw. die nächste Runde...")
	end
end

local function setOutline(character, isMate, color)
	local highlight = character:FindFirstChild("TeamHighlight")
	if isMate and not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "TeamHighlight"
		highlight.FillTransparency = 1
		highlight.OutlineColor = color
		highlight.Parent = character
	elseif not isMate and highlight then
		highlight:Destroy()
	end
end

-- Umriss in Verbündeten-Blau für Teammitglieder und Bot-Teammitglieder (sichtbar durch Wände)
local function updateHighlights()
	local botFolder = workspace:FindFirstChild("Bots")
	if botFolder then
		for _, model in botFolder:GetChildren() do
			local isMate = player.Team ~= nil and model:GetAttribute("TeamName") == player.Team.Name
			setOutline(model, isMate, UITheme.Colors.Ally)
		end
	end
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if character and p ~= player then
			local highlight = character:FindFirstChild("TeamHighlight")
			local isMate = p.Team ~= nil and p.Team == player.Team
			if isMate and not highlight then
				highlight = Instance.new("Highlight")
				highlight.Name = "TeamHighlight"
				highlight.FillTransparency = 1
				highlight.OutlineColor = UITheme.Colors.Ally
				highlight.Parent = character
			elseif not isMate and highlight then
				highlight:Destroy()
			end
		end
	end
end

function Spectator.Init()
	InputActions.Bind("SpectateNext", function(began)
		if began and spectating then
			target = nextTarget(1)
			update()
		end
	end)
	InputActions.Bind("SpectatePrev", function(began)
		if began and spectating then
			target = nextTarget(-1)
			update()
		end
	end)

	-- Neuer eigener Charakter: sofort zurück zur normalen Kamera
	player.CharacterAdded:Connect(function()
		task.defer(update)
	end)

	-- Kameraflug jedes Bild weiterbewegen
	RunService.RenderStepped:Connect(function()
		if inOverview then
			workspace.CurrentCamera.CFrame = overview()
		end
	end)

	task.spawn(function()
		while true do
			update()
			updateHighlights()
			task.wait(0.3)
		end
	end)
end

return Spectator

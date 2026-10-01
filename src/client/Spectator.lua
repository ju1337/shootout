-- Spectator (ModuleScript, nur Client)
-- Nur im Drop-Modus: Wer tot ist (oder mitten in der Runde beitritt), schaut einem
-- lebenden Teammitglied zu. Mit E wechseln. Ohne Teammitglied: Blick von oben auf die Map.
-- Außerdem bekommen Teammitglieder einen Umriss in Teamfarbe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Movement = require(Shared.Movement)
local HUD = require(Shared.HUD)
local Modes = require(Shared.Modes)

local player = Players.LocalPlayer

local Spectator = {}

local DROP_CENTER = Modes.Get("Drop").Center
local OVERVIEW = CFrame.lookAt(DROP_CENTER + Vector3.new(0, 160, -220), DROP_CENTER)

local spectating = false
local target = nil

local function livingHumanoid(p)
	local character = p.Character
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
	return list
end

-- Nächstes Teammitglied wählen (nach dem aktuellen in der Liste)
local function nextTarget()
	local list = livingTeammates()
	if #list == 0 then
		return nil
	end
	local index = table.find(list, target) or 0
	return list[index % #list + 1]
end

local function stopSpectating()
	if not spectating then
		return
	end
	spectating = false
	target = nil
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local myHumanoid = livingHumanoid(player)
	if myHumanoid then
		camera.CameraSubject = myHumanoid
	end
	Movement.SetFirstPerson(Modes.IsFighting(player))
	HUD.SetStatus("")
end

local function update()
	local inDrop = player:GetAttribute("Mode") == "Drop"
	if not inDrop or livingHumanoid(player) then
		stopSpectating()
		return
	end

	local camera = workspace.CurrentCamera
	if not spectating then
		spectating = true
		Movement.SetFirstPerson(false)
	end
	if not target or not livingHumanoid(target) or target.Team ~= player.Team then
		target = nextTarget()
	end
	if target then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = livingHumanoid(target)
		HUD.SetStatus("Du schaust " .. target.Name .. " zu  ·  E = wechseln")
	else
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = OVERVIEW
		HUD.SetStatus("Warte auf die nächste Runde...")
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

-- Umriss in Teamfarbe für Teammitglieder und Bot-Teammitglieder (sichtbar durch Wände)
local function updateHighlights()
	local botFolder = workspace:FindFirstChild("Bots")
	if botFolder then
		for _, model in botFolder:GetChildren() do
			local isMate = player.Team ~= nil and model:GetAttribute("TeamName") == player.Team.Name
			setOutline(model, isMate, player.Team and player.TeamColor.Color or Color3.new(1, 1, 1))
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
				highlight.OutlineColor = p.TeamColor.Color
				highlight.Parent = character
			elseif not isMate and highlight then
				highlight:Destroy()
			end
		end
	end
end

function Spectator.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and spectating and input.KeyCode == Enum.KeyCode.E then
			target = nextTarget()
			update()
		end
	end)

	-- Neuer eigener Charakter: sofort zurück zur normalen Kamera
	player.CharacterAdded:Connect(function()
		task.defer(update)
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

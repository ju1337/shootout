-- HubLineup (ModuleScript, nur Client)
-- Wie in der Rogue-Company-Lobby: Auf der Lineup-Bühne im Hangar steht groß der eigene Agent
-- (mit Skin und gewählter Primärwaffe) und dreht sich langsam. Nur lokal sichtbar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local AgentFigure = require(Shared.AgentFigure)
local Cosmetics = require(Shared.Cosmetics)
local Modes = require(Shared.Modes)
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

local HubLineup = {}

local STAGE_POSITION = Vector3.new(0, 1.2, 18) -- Mitte der Bühne im Hangar (Hub-Map)
local SCALE = 1.7

local figure = nil

local function rebuild()
	if figure then
		figure:Destroy()
		figure = nil
	end
	if player:GetAttribute("Mode") ~= "Hub" then
		return
	end
	local agent = AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
	local weapon = AgentConfig.LoadoutFor(player, agent.Id)[1]
	local primary, accent = Cosmetics.AgentColors(player, agent.Id)
	figure = AgentFigure.Build(agent, primary, accent, Cosmetics.WeaponSkin(player, agent.Id, weapon), weapon)
	figure.Name = "LineupAgent"
	figure:ScaleTo(SCALE)
	for _, part in figure:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	figure.Parent = workspace
end

-- Einsatz-Tafel im Hangar: live, wie viele Spieler in welchem Modus sind
local function buildMissionBoard()
	local board = workspace:WaitForChild("Maps"):WaitForChild("Hub"):WaitForChild("Decor"):WaitForChild("MissionBoard", 10)
	if not board then
		return
	end
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.Parent = player:WaitForChild("PlayerGui")
	surface.Adornee = board
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.16, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Oswald
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(40, 210, 230)
	title.Text = "EINSATZ-ÜBERSICHT"
	title.Parent = surface
	local list = Instance.new("TextLabel")
	list.Position = UDim2.new(0.06, 0, 0.2, 0)
	list.Size = UDim2.new(0.88, 0, 0.76, 0)
	list.BackgroundTransparency = 1
	list.Font = Enum.Font.Oswald
	list.TextSize = 30
	list.TextColor3 = Color3.fromRGB(235, 242, 248)
	list.TextXAlignment = Enum.TextXAlignment.Left
	list.TextYAlignment = Enum.TextYAlignment.Top
	list.RichText = true
	list.Parent = surface
	local function update()
		local ok, counts = pcall(HttpService.JSONDecode, HttpService, ReplicatedStorage:GetAttribute("ModeCounts") or "{}")
		counts = ok and counts or {}
		local lines = {}
		for _, mode in Modes.List do
			if mode.Available then
				local n = counts[mode.Id] or 0
				local color = n > 0 and "#50D282" or "#5A6B80"
				table.insert(lines, mode.Name .. '   <font color="' .. color .. '">' .. n .. " Spieler</font>")
			end
		end
		list.Text = table.concat(lines, "\n")
	end
	update()
	ReplicatedStorage:GetAttributeChangedSignal("ModeCounts"):Connect(update)
end

function HubLineup.Init()
	task.spawn(buildMissionBoard)
	rebuild()
	player.AttributeChanged:Connect(function(name)
		if name == "Mode" or name == "Agent" or name == "Equipped" or name == "Owned" or name == "Loadouts"
			or string.sub(name, 1, 3) == "XP_" then
			rebuild()
		end
	end)
	-- Langsam hin und her drehen, Blick Richtung Spawn (Süden)
	RunService.RenderStepped:Connect(function()
		if figure then
			local angle = math.sin(os.clock() * 0.5) * 0.5
			local height = 3 * SCALE -- Figur steht mit den Füßen auf der Bühne
			figure:PivotTo(CFrame.new(STAGE_POSITION + Vector3.new(0, height, 0)) * CFrame.Angles(0, angle, 0))
		end
	end)
end

return HubLineup

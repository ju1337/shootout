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

function HubLineup.Init()
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

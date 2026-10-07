--!assets art/templates
-- Agenten-Modelle auf dem Client: AgentModels hält den Start nicht auf, wenn der Ordner Assets.Agents (noch) fehlt
-- (z.B. im Place noch nicht angelegt oder noch nicht übertragen). Kommen Ordner oder Modelle später an, werden sie
-- dann geladen. Auf dem Server meldet Studio im Output, was mit jedem Modell los ist.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = ReplicatedStorage.Assets
local folder = assets.Agents
local template = folder.Agent
folder.Parent = nil -- Ordner fehlt beim Start

SIM.IsServer = false
local started = SIM.Now
local AgentModels = require("AgentModels")
check(SIM.Now == started, "require wartet nicht auf den fehlenden Ordner")
check(not AgentModels.HasAsset("Viper") and next(AgentModels.AssetReport()) == nil, "noch keine Modelle")

-- Ordner kommt an (mit einem Modell darin)
local viper = template:Clone()
viper.Name = "Viper"
viper.Parent = folder
folder.Parent = assets
check(AgentModels.HasAsset("Viper"), "Modell im nachgereichten Ordner geladen")
check(AgentModels.AssetReport().Agent ~= nil and not AgentModels.AssetReport().Agent.Loaded,
	"Vorlage unter ihrem eigenen Namen gemeldet")
-- Ein Modell kommt später an
local ghost = template:Clone()
ghost.Name = "Ghost"
ghost.Parent = folder
SIM.Advance(0.1) -- geladen wird am Ende des Moments (mehrere Änderungen = einmal laden)
check(AgentModels.HasAsset("Ghost"), "später angekommenes Modell geladen")
SIM.IsServer = true

if failures == 0 then
	print("Agenten-Modelle auf dem Client: alles in Ordnung")
end

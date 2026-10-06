-- GraphicsQuality (ModuleScript, nur Client)
-- Einstellung "Grafik" (PlayerSettings): HOCH = alles an, MITTEL = ohne Sonnenstrahlen, NIEDRIG = ohne Schatten,
-- Leuchten (Bloom), Sonnenstrahlen, Partikel, Feuer und Rauch – für schwache Geräte. Wirkt nur beim eigenen Spieler.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared").PlayerSettings)

local player = Players.LocalPlayer

local GraphicsQuality = {}

local level = "High"

-- Partikel ein/aus; der ursprüngliche Zustand bleibt als Attribut am Emitter (zum Zurückschalten)
local function setEmitter(emitter)
	if emitter:GetAttribute("GfxEnabled") == nil then
		emitter:SetAttribute("GfxEnabled", emitter.Enabled)
	end
	emitter.Enabled = level ~= "Low" and emitter:GetAttribute("GfxEnabled") == true
end

local function onDescendant(object)
	if object:IsA("ParticleEmitter") or object:IsA("Fire") or object:IsA("Smoke") or object:IsA("Sparkles") then
		setEmitter(object)
	end
end

local function apply()
	level = PlayerSettings.Get("Graphics")
	Lighting.GlobalShadows = level ~= "Low"
	for _, effect in Lighting:GetChildren() do
		if effect:IsA("BloomEffect") then
			effect.Enabled = level ~= "Low"
		elseif effect:IsA("SunRaysEffect") then
			effect.Enabled = level == "High"
		end
	end
	for _, root in { workspace, player:WaitForChild("PlayerGui") } do
		for _, object in root:GetDescendants() do
			onDescendant(object)
		end
	end
end

function GraphicsQuality.Init()
	apply()
	workspace.DescendantAdded:Connect(onDescendant)
	player:WaitForChild("PlayerGui").DescendantAdded:Connect(onDescendant)
	PlayerSettings.Changed:Connect(function(key)
		if key == "Graphics" then
			apply()
		end
	end)
end

return GraphicsQuality

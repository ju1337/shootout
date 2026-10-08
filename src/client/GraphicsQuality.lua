-- GraphicsQuality (ModuleScript, nur Client)
-- Einstellung "Grafik" (PlayerSettings): HOCH = alles an, MITTEL = ohne Sonnenstrahlen, NIEDRIG = ohne Schatten,
-- Leuchten (Bloom), Sonnenstrahlen, Partikel, Feuer und Rauch – für schwache Geräte. Wirkt nur beim eigenen Spieler.
-- Schilder, Graffiti und Bodenschriften der Maps (SurfaceGui, allein in der offenen Welt über 800) werden nur bis zu
-- einer Sichtweite gezeichnet (GUI_DISTANCE je Stufe); ohne Grenze zeichnet Roblox jede davon in jedem Bild.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared").PlayerSettings)

local player = Players.LocalPlayer

local GraphicsQuality = {}

local level = "High"

-- Sichtweite der Map-Schilder in Studs je Stufe
local GUI_DISTANCE = { High = 300, Medium = 200, Low = 120 }

-- Partikel ein/aus; der ursprüngliche Zustand bleibt als Attribut am Emitter (zum Zurückschalten)
local function setEmitter(emitter)
	if emitter:GetAttribute("GfxEnabled") == nil then
		emitter:SetAttribute("GfxEnabled", emitter.Enabled)
	end
	emitter.Enabled = level ~= "Low" and emitter:GetAttribute("GfxEnabled") == true
end

-- Schild einer Map: nur solche ohne eigene Sichtweite (MaxDistance 0 = unbegrenzt) bekommen die der Stufe
local function setSurfaceGui(gui)
	local maps = workspace:FindFirstChild("Maps")
	if not maps or not gui:IsDescendantOf(maps) then
		return
	end
	if gui:GetAttribute("GfxMaxDistance") == nil then
		gui:SetAttribute("GfxMaxDistance", gui.MaxDistance)
	end
	if gui:GetAttribute("GfxMaxDistance") == 0 then
		gui.MaxDistance = GUI_DISTANCE[level] or GUI_DISTANCE.High
	end
end

local function onDescendant(object)
	if object:IsA("ParticleEmitter") or object:IsA("Fire") or object:IsA("Smoke") or object:IsA("Sparkles") then
		setEmitter(object)
	elseif object:IsA("SurfaceGui") then
		setSurfaceGui(object)
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

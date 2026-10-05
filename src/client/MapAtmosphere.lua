-- MapAtmosphere (ModuleScript, nur Client)
-- Lichtstimmung je Map: Maps mit dem Attribut "Atmosphere" bekommen eigenes Licht, solange man auf ihnen ist
-- (aktuelle Map = Spieler-Attribut MapId, gesetzt von den Modi). Sonst gilt das normale Licht aus dem Projekt.
--   "Space"    Nacht mit Sternen, kühles Umgebungslicht, kaum Dunst, stärkeres Leuchten (Neon)
--   "Tropical" Mittagssonne, satte Farben, leichter heller Dunst (Rogue-Company-Stil)
--   "Wasteland" Ödland der offenen Welt (Extinction): später Nachmittag, staubiger Dunst, entsättigt
-- Wechsel werden kurz eingeblendet. ExposureCompensation bleibt dem Hub (HubLineup) überlassen.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modes = require(ReplicatedStorage:WaitForChild("Shared").Modes)

local player = Players.LocalPlayer

local MapAtmosphere = {}

-- Werte je Stimmung: Lighting-Eigenschaften und Effekte (Atmosphere, ColorCorrection, Bloom)
local PRESETS = {
	Space = {
		Lighting = { ClockTime = 0, Brightness = 1.4, Ambient = Color3.fromRGB(80, 86, 120),
			OutdoorAmbient = Color3.fromRGB(110, 112, 150) },
		Atmosphere = { Density = 0.05, Haze = 0, Glare = 0, Color = Color3.fromRGB(60, 70, 110),
			Decay = Color3.fromRGB(30, 30, 60) },
		ColorCorrection = { Saturation = 0.1, Contrast = 0.15, TintColor = Color3.fromRGB(232, 238, 255) },
		Bloom = { Intensity = 0.9, Threshold = 1.1 },
	},
	Wasteland = {
		Lighting = { ClockTime = 16.6, Brightness = 2.1, Ambient = Color3.fromRGB(96, 96, 88),
			OutdoorAmbient = Color3.fromRGB(128, 126, 114) },
		Atmosphere = { Density = 0.36, Haze = 2.1, Glare = 0.2, Color = Color3.fromRGB(184, 176, 156),
			Decay = Color3.fromRGB(118, 108, 92) },
		ColorCorrection = { Saturation = -0.22, Contrast = 0.12, TintColor = Color3.fromRGB(255, 244, 228) },
		Bloom = { Intensity = 0.25, Threshold = 1.7 },
	},
	Tropical = {
		Lighting = { ClockTime = 13.5, Brightness = 3.2, Ambient = Color3.fromRGB(120, 116, 110),
			OutdoorAmbient = Color3.fromRGB(150, 150, 146) },
		Atmosphere = { Density = 0.2, Haze = 0.6, Glare = 0.3, Color = Color3.fromRGB(200, 225, 255),
			Decay = Color3.fromRGB(150, 180, 220) },
		ColorCorrection = { Saturation = 0.22, Contrast = 0.08, TintColor = Color3.fromRGB(255, 252, 245) },
		Bloom = { Intensity = 0.35, Threshold = 1.5 },
	},
}

local TWEEN = TweenInfo.new(1.2, Enum.EasingStyle.Quad)

-- Ziel-Objekte je Abschnitt
local function targets()
	return {
		Lighting = Lighting,
		Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere"),
		ColorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect"),
		Bloom = Lighting:FindFirstChildOfClass("BloomEffect"),
	}
end

-- Ausgangswerte merken (aus dem Projekt), damit man zurückwechseln kann
local defaults = {}
local function remember()
	local objects = targets()
	for _, preset in PRESETS do
		for section, values in preset do
			local object = objects[section]
			if object then
				defaults[section] = defaults[section] or {}
				for key in values do
					if defaults[section][key] == nil then
						defaults[section][key] = object[key]
					end
				end
			end
		end
	end
end

local current = nil
local function apply(name)
	if name == current then
		return
	end
	current = name
	local preset = PRESETS[name] or defaults
	local objects = targets()
	for section, values in preset do
		local object = objects[section]
		if object then
			-- Uhrzeit springt nicht über Mitternacht zurück: direkt setzen statt tweenen
			local tweened = {}
			for key, value in values do
				if key == "ClockTime" then
					object[key] = value
				else
					tweened[key] = value
				end
			end
			TweenService:Create(object, TWEEN, tweened):Play()
		end
	end
end

-- Stimmung der Map, auf der man gerade ist (nur in Kampfmodi, nicht im Hub oder Markt)
local function update()
	local mode = player:GetAttribute("Mode")
	local id = player:GetAttribute("MapId")
	local maps = workspace:FindFirstChild("Maps")
	local map = mode and not Modes.IsSocial(mode) and id and maps and maps:FindFirstChild(id)
	apply(map and map:GetAttribute("Atmosphere") or nil)
end

function MapAtmosphere.Init()
	remember()
	update()
	player:GetAttributeChangedSignal("MapId"):Connect(update)
	player:GetAttributeChangedSignal("Mode"):Connect(update)
end

return MapAtmosphere

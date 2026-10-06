-- MapAtmosphere (ModuleScript, nur Client)
-- Lichtstimmung je Map: Maps mit dem Attribut "Atmosphere" bekommen eigenes Licht, solange man auf ihnen ist
-- (aktuelle Map = Spieler-Attribut MapId, gesetzt von den Modi). Sonst gilt das normale Licht aus dem Projekt.
--   "Space"    Nacht mit Sternen, kühles Umgebungslicht, kaum Dunst, stärkeres Leuchten (Neon)
--   "Tropical" Mittagssonne, satte Farben, leichter heller Dunst (Rogue-Company-Stil)
--   "Wasteland" Ödland der offenen Welt (Extinction): staubiger Dunst, entsättigt, mit Tag und Nacht (DayCycle):
--               die Uhrzeit läuft mit der Serverzeit, nachts blaues Mondlicht und dichterer Dunst (NIGHT)
-- Wechsel werden kurz eingeblendet. ExposureCompensation bleibt dem Hub (HubLineup) überlassen.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modes = require(Shared.Modes)
local DayCycle = require(Shared.DayCycle)

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
		-- Zombie-Apokalypse: fahles, entsättigtes Licht, gelbgrauer Dunst
		Lighting = { ClockTime = 16.6, Brightness = 1.8, Ambient = Color3.fromRGB(86, 88, 78),
			OutdoorAmbient = Color3.fromRGB(116, 116, 100) },
		Atmosphere = { Density = 0.42, Haze = 2.6, Glare = 0.15, Color = Color3.fromRGB(168, 164, 136),
			Decay = Color3.fromRGB(98, 94, 72) },
		ColorCorrection = { Saturation = -0.35, Contrast = 0.15, TintColor = Color3.fromRGB(240, 236, 212) },
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

-- Nachtwerte für "Wasteland" (zwischen Wasteland und NIGHT wird nach DayCycle.Darkness gemischt)
local NIGHT = {
	-- hell genug zum Spielen: kräftiges bläuliches Umgebungslicht statt Schwarz, weniger Dunst
	Lighting = { Brightness = 2.2, Ambient = Color3.fromRGB(96, 102, 128), OutdoorAmbient = Color3.fromRGB(132, 140, 176) },
	Atmosphere = { Density = 0.34, Haze = 1.0, Glare = 0, Color = Color3.fromRGB(96, 104, 134), Decay = Color3.fromRGB(60, 64, 92) },
	ColorCorrection = { Saturation = -0.28, Contrast = 0.06, TintColor = Color3.fromRGB(214, 222, 255) },
	Bloom = { Intensity = 0.5, Threshold = 1.2 },
}
-- Blutmond (rot) und Nebel (dicht, grau) werden über Tag/Nacht gelegt
local BLOOD = {
	Atmosphere = { Color = Color3.fromRGB(120, 40, 36), Decay = Color3.fromRGB(70, 20, 18), Density = 0.5 },
	ColorCorrection = { TintColor = Color3.fromRGB(255, 160, 150), Saturation = -0.1 },
	Lighting = { Ambient = Color3.fromRGB(120, 66, 62), OutdoorAmbient = Color3.fromRGB(160, 86, 80) },
}
local CYCLE_STEP = 0.25 -- so oft wird das Licht nachgeführt (Sekunden)

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
	if name == "Wasteland" and MapAtmosphere.Cycle then
		MapAtmosphere.Cycle() -- Tag und Nacht setzen die Werte direkt
		return
	end
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

local function mix(a, b, t)
	if typeof(a) == "Color3" then
		return a:Lerp(b, t)
	end
	return a + (b - a) * t
end

-- Tag und Nacht: Uhrzeit setzen und zwischen Tag- und Nachtwerten mischen (nur auf "Wasteland")
local function cycle()
	if current ~= "Wasteland" then
		return
	end
	local serverTime = workspace:GetServerTimeNow()
	local clock = DayCycle.Clock(serverTime)
	local dark = DayCycle.Darkness(clock)
	local blood = DayCycle.IsBloodMoon(serverTime) and dark or 0
	local fog = DayCycle.Fog(serverTime)
	Lighting.ClockTime = clock
	local objects = targets()
	for section, values in PRESETS.Wasteland do
		local object = objects[section]
		local night = NIGHT[section]
		if object and night then
			for key, day in values do
				if key ~= "ClockTime" and night[key] ~= nil then
					local value = mix(day, night[key], dark)
					local red = BLOOD[section] and BLOOD[section][key]
					if red ~= nil and blood > 0 then
						value = mix(value, red, blood)
					end
					object[key] = value
				end
			end
		end
	end
	local atmosphere = objects.Atmosphere
	if atmosphere and fog > 0 then
		atmosphere.Density = mix(atmosphere.Density, 0.72, fog)
		atmosphere.Haze = mix(atmosphere.Haze, 6, fog)
		atmosphere.Color = atmosphere.Color:Lerp(Color3.fromRGB(176, 178, 172), fog)
	end
end
MapAtmosphere.Cycle = cycle

function MapAtmosphere.Init()
	remember()
	update()
	local nextAt = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now >= nextAt then
			nextAt = now + CYCLE_STEP
			cycle()
		end
	end)
	player:GetAttributeChangedSignal("MapId"):Connect(update)
	player:GetAttributeChangedSignal("Mode"):Connect(update)
end

return MapAtmosphere

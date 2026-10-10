-- Ambience (ModuleScript, nur Client)
-- Welt-Ambiente der offenen Welt (EXTINCTION): 2D-Schleifen aus SoundLibrary (Ambient…), die zur Lage des Spielers
-- passen. Alle 0,5 Sekunden wird die Lage neu bewertet, jede Schicht blendet in 2 Sekunden (TweenService) auf ihre
-- Ziel-Lautstärke:
--   draußen am Tag     Wind (leise) und Vögel          draußen nachts   Wind und Grillen/Eule
--   Safe Zone          Camp (knisterndes Feuer) statt der wilden Schichten
--   rote Zone          dazu ein tiefes Dröhnen         Blutmond         dumpfer Schlag zum Start, noch dunkleres Dröhnen
--   Sturmnacht         alles leiser (Regen und Wind kommen von StormClient)
-- Lage: Spieler-Attribute Mode, InSafeZone, Redzone (Server, Extinction), Uhrzeit DayCycle (Serverzeit), Blutmond und
-- Sturm über DayCycle (Attribute an ReplicatedStorage). Die Lautstärke-Einstellung greift über die SoundGroup, in die
-- PlayerSettings jeden Sound unter SoundService einhängt. Außerhalb der offenen Welt ist alles stumm.
--   Ambience.Init()     starten
--   Ambience.Levels()   { Name = Ziel-Lautstärke } (Tests)
--   Ambience.Sounds()   { Name = Sound } (Tests)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DayCycle = require(Shared.DayCycle)
local Modes = require(Shared.Modes)
local Sfx = require(Shared.Sfx)
local SoundLibrary = require(Shared.SoundLibrary)

local player = Players.LocalPlayer

local Ambience = {}

local INTERVAL = 0.5 -- Sekunden zwischen zwei Bewertungen
local FADE = 2 -- Sekunden Überblenden
local STORM_DUCK = 0.35 -- so leise wird das Ambiente in der Sturmnacht (bei voller Sturmstärke)

-- Schichten: Name in SoundLibrary = Grundlautstärke (1 = Gain des Eintrags)
local LAYERS = {
	AmbientWindDay = 0.35,
	AmbientBirds = 0.3,
	AmbientNight = 0.35,
	AmbientCamp = 0.3,
	AmbientRedzone = 0.45,
	AmbientBloodMoon = 0.5,
}

local sounds: { [string]: Sound } = {} -- laufende Schleifen je Schicht (angelegt, sobald sie zum ersten Mal hörbar ist)
local levels: { [string]: number } = {} -- Ziel-Lautstärke je Schicht (0..1, mal Grundlautstärke)
local tweens: { [string]: Tween } = {}
local bloodMoonWas = false
local started = false

local function inWorld()
	-- in der Gruft (Dungeon, abseits der Karte) keine Vögel, Wind oder Zonen-Brummen
	local dungeon = player:GetAttribute("Dungeon")
	return Modes.IsSurvival(player:GetAttribute("Mode")) and not (type(dungeon) == "string" and dungeon ~= "")
end

-- Lage des Spielers: Ziel 0..1 je Schicht
local function evaluate(): { [string]: number }
	local target = {}
	for name in LAYERS do
		target[name] = 0
	end
	if not inWorld() then
		return target
	end
	local now = workspace:GetServerTimeNow()
	local night = DayCycle.IsNight(DayCycle.Clock(now))
	local safe = player:GetAttribute("InSafeZone") == true
	local red = not safe and player:GetAttribute("Redzone") ~= nil and player:GetAttribute("Redzone") ~= false
	local bloodMoon = DayCycle.IsBloodMoon(now)
	-- Sturmnacht: Ambiente leiser, je stärker der Sturm
	local duck = 1 - DayCycle.StormFactor(now) * (1 - STORM_DUCK)
	if safe then
		target.AmbientCamp = 1
	elseif night or bloodMoon then
		target.AmbientWindDay = 0.7
		target.AmbientNight = 1
	else
		target.AmbientWindDay = 1
		target.AmbientBirds = 1
	end
	if red then
		target.AmbientRedzone = 1
	end
	if bloodMoon then
		target.AmbientBloodMoon = safe and 0.5 or 1
	end
	for name, value in target do
		target[name] = value * duck
	end
	return target
end

-- Schicht auf ihre Ziel-Lautstärke blenden; still stehende Schleifen bleiben liegen (Volume 0), bis sie wieder gebraucht werden
local function fade(name, level)
	local sound = sounds[name]
	if not sound then
		if level <= 0 then
			return
		end
		sound = Sfx.Loop2D(name, { Volume = 0 })
		if not sound then
			return
		end
		sound.Volume = 0
		sounds[name] = sound
	end
	if tweens[name] then
		tweens[name]:Cancel()
	end
	local def = SoundLibrary.Get(name)
	local gain = def and def.Clips[1] and def.Clips[1].Gain or 1
	local goal = math.min(10, level * LAYERS[name] * gain)
	local tween = TweenService:Create(sound, TweenInfo.new(FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Volume = goal })
	tweens[name] = tween
	tween:Play()
end

local function step()
	local target = evaluate()
	-- nach Modus, nicht inWorld(): sonst käme der Stinger beim Verlassen der Gruft im Blutmond noch einmal
	local bloodMoon = Modes.IsSurvival(player:GetAttribute("Mode")) and DayCycle.IsBloodMoon(workspace:GetServerTimeNow()) or false
	if bloodMoon and not bloodMoonWas then
		Sfx.UI("BloodMoonStinger")
	end
	bloodMoonWas = bloodMoon
	for name, level in target do
		if levels[name] ~= level then
			levels[name] = level
			fade(name, level)
		end
	end
end

function Ambience.Init()
	if started or not RunService:IsClient() then
		return
	end
	started = true
	task.spawn(function()
		while true do
			local ok, err = pcall(step)
			if not ok then
				warn("Ambience: " .. tostring(err))
			end
			task.wait(INTERVAL)
		end
	end)
end

function Ambience.Levels()
	return levels
end

function Ambience.Sounds()
	return sounds
end

return Ambience

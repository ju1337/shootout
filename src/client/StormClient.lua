-- StormClient (ModuleScript, nur Client)
-- Sturmnacht der offenen Welt (StormService, Stärke DayCycle.StormFactor): Regen um die Kamera, Regen und Wind als
-- Dauerklang, Wetterleuchten mit fernem Donner, und Blitzeinschläge (Remote StormStrike): Blitz aus Neon-Stücken, heller
-- Lichtblitz, Einschlag-Krachen an der Stelle – der Donner kommt mit der Entfernung später an (Schall ~1200 Studs/s).
-- Licht und Wolken macht MapAtmosphere. Sounds: Pro Sound Effects (Roblox-Bibliothek), Gain gleicht die Aufnahmen an.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local DayCycle = require(Shared.DayCycle)
local Modes = require(Shared.Modes)

local player = Players.LocalPlayer

local StormClient = {}

-- Blitzeinschlag nah (Region überspringt das Anschwellen vor dem Krachen)
local STRIKES = {
	{ Id = "rbxassetid://9116282544", Gain = 1.0, Region = { 1.65, 9.1 } },
	{ Id = "rbxassetid://9116282647", Gain = 1.0, Region = { 1.75, 11 } },
	{ Id = "rbxassetid://9116282791", Gain = 1.1, Region = { 1.8, 9.5 } },
	{ Id = "rbxassetid://9116282875", Gain = 1.0, Region = { 1.2, 7 } },
}
-- Donner in der Ferne (Wetterleuchten)
local THUNDER = {
	{ Id = "rbxassetid://9120019063", Gain = 2.2, Region = { 1.4, 9.5 } },
	{ Id = "rbxassetid://9120019110", Gain = 2.6, Region = { 1.2, 10.8 } },
	{ Id = "rbxassetid://9120019293", Gain = 2.9, Region = { 1.9, 10.5 } },
	{ Id = "rbxassetid://9120018172", Gain = 3.0, Region = { 0.2, 4.5 } },
	{ Id = "rbxassetid://9120016021", Gain = 2.2, Region = { 0.2, 7.1 } },
}
local RAIN_SOUND = "rbxassetid://9112794090" -- Starkregen auf Beton (Schleife)
local WIND_SOUND = "rbxassetid://9114057128" -- Wind mit Böen (Schleife)
local SOUND_SPEED = 1200 -- Studs pro Sekunde (Verzögerung des Donners)

local function inWorld()
	return Modes.IsSurvival(player:GetAttribute("Mode"))
end

local function newSound(clip, volume, parent)
	local sound = Instance.new("Sound")
	sound.SoundId = clip.Id
	sound.Volume = math.min(10, volume * (clip.Gain or 1))
	sound.PlaybackSpeed = 0.95 + math.random() * 0.1
	if clip.Region then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(clip.Region[1], clip.Region[2])
	end
	sound.Parent = parent
	return sound, (clip.Region and (clip.Region[2] - clip.Region[1]) or 10) + 0.5
end

-- Kurz heller (ColorCorrection.Brightness gehört nicht zu den Werten, die MapAtmosphere setzt)
local flashTween = nil
local function flash(strength)
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not cc then
		return
	end
	if flashTween then
		flashTween:Cancel()
	end
	cc.Brightness = strength
	flashTween = TweenService:Create(cc, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Brightness = 0 })
	task.delay(0.06, function()
		flashTween:Play()
	end)
end

-- ---------- Blitz ----------

local function boltSegment(from, to, width, parent)
	local length = (to - from).Magnitude
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(220, 230, 255)
	part.Size = Vector3.new(width, width, length)
	part.CFrame = CFrame.lookAt((from + to) / 2, to)
	part.Parent = parent
end

-- Zickzack vom Himmel bis zum Boden, mit ein, zwei Ästen
local function bolt(position)
	local model = Instance.new("Model")
	model.Name = "Lightning"
	local top = position + Vector3.new(math.random(-30, 30), 320, math.random(-30, 30))
	local points = { top }
	local steps = 14
	for i = 1, steps - 1 do
		local t = i / steps
		local base = top:Lerp(position, t)
		table.insert(points, base + Vector3.new(math.random(-12, 12), 0, math.random(-12, 12)) * (1 - t * 0.6))
	end
	table.insert(points, position)
	for i = 1, #points - 1 do
		boltSegment(points[i], points[i + 1], 1.1, model)
	end
	for _ = 1, 2 do
		local from = points[math.random(3, #points - 4)]
		local to = from + Vector3.new(math.random(-40, 40), -math.random(30, 70), math.random(-40, 40))
		boltSegment(from, from:Lerp(to, 0.5) + Vector3.new(math.random(-6, 6), 0, math.random(-6, 6)), 0.5, model)
		boltSegment(from:Lerp(to, 0.5), to, 0.4, model)
	end
	local glow = Instance.new("Part")
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.Transparency = 1
	glow.Size = Vector3.one
	glow.Position = position + Vector3.new(0, 4, 0)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 215, 255)
	light.Range = 60
	light.Brightness = 8
	light.Parent = glow
	glow.Parent = model
	model.Parent = workspace
	-- zweimal flackern, dann weg
	task.delay(0.08, function()
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child ~= glow then
				child.Transparency = 0.7
			end
		end
	end)
	task.delay(0.14, function()
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child ~= glow then
				child.Transparency = 0
			end
		end
	end)
	Debris:AddItem(model, 0.3)
end

local function onStrike(position)
	if typeof(position) ~= "Vector3" or not inWorld() then
		return
	end
	bolt(position)
	local camera = workspace.CurrentCamera
	local distance = camera and (camera.CFrame.Position - position).Magnitude or 0
	flash(distance < 120 and 0.45 or 0.22)
	-- Krachen an der Einschlagstelle, mit Schall-Verzögerung
	task.delay(math.min(distance / SOUND_SPEED, 2.5), function()
		local anchor = Instance.new("Attachment")
		anchor.WorldPosition = position
		anchor.Parent = workspace.Terrain
		local sound, life = newSound(STRIKES[math.random(1, #STRIKES)], 1.4, anchor)
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 40
		sound.RollOffMaxDistance = 1800
		sound:Play()
		Debris:AddItem(anchor, life)
	end)
end

-- ---------- Regen, Wind, Wetterleuchten ----------

local rainPart, rainEmitter, rainSound, windSound
local function ensureRain()
	if rainPart then
		return
	end
	rainPart = Instance.new("Part")
	rainPart.Name = "StormRain"
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.CanQuery = false
	rainPart.CanTouch = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(140, 1, 140)
	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	rainEmitter.Speed = NumberRange.new(110, 140)
	rainEmitter.Lifetime = NumberRange.new(0.5, 0.75)
	rainEmitter.Size = NumberSequence.new(0.18)
	rainEmitter.Squash = NumberSequence.new(4)
	rainEmitter.Transparency = NumberSequence.new(0.45)
	rainEmitter.Color = ColorSequence.new(Color3.fromRGB(190, 200, 215))
	rainEmitter.Acceleration = Vector3.new(14, 0, 6) -- Wind treibt den Regen schräg
	rainEmitter.LightInfluence = 0.6
	rainEmitter.Rate = 0
	rainEmitter.Parent = rainPart
	rainPart.Parent = workspace
	rainSound = Instance.new("Sound")
	rainSound.SoundId = RAIN_SOUND
	rainSound.Looped = true
	rainSound.Volume = 0
	rainSound.Parent = SoundService
	windSound = Instance.new("Sound")
	windSound.SoundId = WIND_SOUND
	windSound.Looped = true
	windSound.Volume = 0
	windSound.Parent = SoundService
end

local nextRumble = 0
local function step()
	local storm = inWorld() and DayCycle.StormFactor(workspace:GetServerTimeNow()) or 0
	if storm <= 0 and not rainPart then
		return
	end
	ensureRain()
	local camera = workspace.CurrentCamera
	if camera then
		rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
	end
	rainEmitter.Rate = 650 * storm
	rainSound.Volume = 0.9 * storm
	windSound.Volume = 1.6 * storm
	if storm > 0 and not rainSound.IsPlaying then
		rainSound:Play()
		windSound:Play()
	elseif storm <= 0 and rainSound.IsPlaying then
		rainSound:Stop()
		windSound:Stop()
	end
	-- Wetterleuchten: heller Himmel, kurz darauf ferner Donner
	local now = os.clock()
	if storm > 0.5 and now >= nextRumble then
		nextRumble = now + 6 + math.random() * 12
		flash(0.12)
		task.delay(0.6 + math.random() * 2.4, function()
			local sound, life = newSound(THUNDER[math.random(1, #THUNDER)], 0.35 + math.random() * 0.3, SoundService)
			sound:Play()
			Debris:AddItem(sound, life)
		end)
	end
end

function StormClient.Init()
	Remotes.StormStrike.OnClientEvent:Connect(onStrike)
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if rainPart and workspace.CurrentCamera then
			rainPart.CFrame = CFrame.new(workspace.CurrentCamera.CFrame.Position + Vector3.new(0, 45, 0))
		end
		if elapsed >= 0.25 then
			elapsed = 0
			step()
		end
	end)
end

return StormClient

-- WeaponEffects (ModuleScript, nur Client)
-- Optik und Klang von Schüssen: Schuss-Sound, Mündungsfeuer mit Licht, fliegende Leuchtspur,
-- Einschläge (Funken, Staub, Einschusslöcher in festen Wänden, Treffer-Blitz an Charakteren),
-- Hülsenauswurf, fallende Magazine und Geräusche beim Nachladen.

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponConfig = require(ReplicatedStorage:WaitForChild("Shared").WeaponConfig)

local WeaponEffects = {}

local TRACER_SPEED = 1100     -- Studs/s der Leuchtspur
local TRACER_LENGTH = 7
local MAX_HOLES = 50          -- so viele Einschusslöcher bleiben gleichzeitig liegen
local HOLE_TIME = 10
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local BRASS = Color3.fromRGB(205, 165, 75)
local FLASH_COLOR = Color3.fromRGB(255, 205, 110)

local folder = Instance.new("Folder")
folder.Name = "WeaponEffects"
folder.Parent = workspace

-- Teil für reine Optik (keine Kollision, keine Treffer, kein Schatten)
local function effectPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		part[key] = value
	end
	part.Parent = folder
	return part
end

-- ---------- Sounds ----------
-- Aufnahmen aus WeaponConfig.SoundSets / ActionSounds: Gain gleicht sie an, Region spielt nur einen Teil.
-- Schüsse anderer: 3D an der Mündung; ab DISTANT_FROM Studs klingt es dumpfer (Höhen weg), wie Schüsse in der Ferne.

local DISTANT_FROM = 140

-- Alle Aufnahmen vorab laden, damit der erste Schuss nicht stumm bleibt
task.defer(function()
	local ContentProvider = game:GetService("ContentProvider")
	local list = {}
	for _, set in WeaponConfig.SoundSets do
		for _, clip in set do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
	end
	for _, clip in WeaponConfig.ActionSounds do
		local sound = Instance.new("Sound")
		sound.SoundId = clip.Id
		table.insert(list, sound)
	end
	pcall(ContentProvider.PreloadAsync, ContentProvider, list)
end)

-- Sound für eine Aufnahme (clip = { Id, Gain, Region }); volume/speed kommen dazu. Gibt Sound und Dauer zurück.
local function makeSound(clip, volume, speed)
	local sound = Instance.new("Sound")
	sound.SoundId = clip.Id
	sound.Volume = math.min(10, volume * (clip.Gain or 1))
	sound.PlaybackSpeed = speed
	local length = 4
	if clip.Region then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(clip.Region[1], clip.Region[2])
		length = clip.Region[2] - clip.Region[1]
	end
	return sound, length / speed + 0.3
end

local function playAt(clip, position, volume, speed, rolloff, distant)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	local sound, life = makeSound(clip, volume, speed)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = rolloff
	if distant then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = 2
		eq.MidGain = -5
		eq.HighGain = -20
		eq.Parent = sound
	end
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, life)
end

local function play2D(clip, volume, speed)
	local sound, life = makeSound(clip, volume, speed)
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, life)
end

-- Zufällige Aufnahme aus einem Set, nie zweimal hintereinander dieselbe
local lastClip = {}
local function pickClip(setName)
	local set = WeaponConfig.SoundSets[setName]
	if not set or #set == 0 then
		return nil
	end
	local index = math.random(1, #set)
	if #set > 1 and index == lastClip[setName] then
		index = index % #set + 1
	end
	lastClip[setName] = index
	return set[index]
end

-- Schuss-Sound. own = eigener Schuss (ohne Raumklang, sofort). Mehrere Kugeln eines Schrotschusses
-- kommen als einzelne Meldungen: dann nur ein Sound.
local lastKey, lastTime = nil, 0
-- suppressed = mit Schalldämpfer (eigener Klang, leiser, nur in der Nähe zu hören). Alte Aufrufe übergeben eine Zahl < 1.
function WeaponEffects.GunSound(weaponName, position, own, suppressed)
	local def = WeaponConfig.Sounds[weaponName]
	if not def then
		return
	end
	if type(suppressed) == "number" then
		suppressed = suppressed < 1
	end
	local key = tostring(position) .. weaponName
	if key == lastKey and os.clock() - lastTime < 0.05 then
		return
	end
	lastKey, lastTime = key, os.clock()
	local clip = pickClip(suppressed and def.Suppressed or def.Set)
	if not clip then
		return
	end
	local pitch = (suppressed and def.SuppressedPitch or def.Pitch or 1) * (0.97 + math.random() * 0.06)
	local volume = (def.Volume or 1) * (suppressed and WeaponConfig.SuppressedVolume or 1)
	if own then
		play2D(clip, 0.5 * volume, pitch)
	else
		local camera = workspace.CurrentCamera
		local distance = camera and (camera.CFrame.Position - position).Magnitude or 0
		playAt(clip, position, 0.9 * volume, pitch, suppressed and 120 or 700, not suppressed and distance > DISTANT_FROM)
	end
end

-- Hantier-Geräusch (WeaponConfig.ActionSounds). position = nil: eigenes, ohne Raumklang.
-- weaponName (optional): Waffe, deren Variante gilt (ActionSoundsByWeapon, z.B. Pistolenmagazin)
function WeaponEffects.ActionSound(name, position, weaponName)
	local byWeapon = weaponName and WeaponConfig.ActionSoundsByWeapon[weaponName]
	local clip = WeaponConfig.ActionSounds[byWeapon and byWeapon[name] or name] or WeaponConfig.ActionSounds[name]
	if not clip then
		return
	end
	local speed = 0.97 + math.random() * 0.06
	if position then
		playAt(clip, position, (clip.Volume or 0.5) * 0.8, speed, 60, false)
	else
		play2D(clip, clip.Volume or 0.5, speed)
	end
end

-- ---------- Mündungsfeuer ----------

-- cframe: an der Mündung, LookVector = Schussrichtung. scale = Größe (Waffe vor der Kamera ist kleiner)
function WeaponEffects.MuzzleFlash(cframe, scale)
	scale = scale or 1
	local spin = CFrame.Angles(0, 0, math.random() * math.pi)
	local core = effectPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.45 * scale,
		CFrame = cframe,
		Material = Enum.Material.Neon,
		Color = FLASH_COLOR,
		Transparency = 0.1,
	})
	-- Flammenzunge nach vorne und ein flacher Stern quer dazu
	local flame = effectPart({
		Size = Vector3.new(0.16, 0.16, 0.9) * scale * (0.8 + math.random() * 0.5),
		Material = Enum.Material.Neon,
		Color = FLASH_COLOR,
		Transparency = 0.25,
	})
	flame.CFrame = cframe * spin * CFrame.new(0, 0, -flame.Size.Z / 2)
	local star = effectPart({
		Size = Vector3.new(0.9, 0.07, 0.07) * scale,
		CFrame = cframe * spin * CFrame.new(0, 0, -0.1 * scale),
		Material = Enum.Material.Neon,
		Color = FLASH_COLOR,
		Transparency = 0.35,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Range = 12 * math.max(scale, 0.6)
	light.Brightness = 2.5
	light.Shadows = false
	light.Parent = core
	Debris:AddItem(core, 0.05)
	Debris:AddItem(flame, 0.04)
	Debris:AddItem(star, 0.035)
end

-- ---------- Leuchtspur ----------

local tracers = {}

function WeaponEffects.Tracer(startPos, endPos, own)
	local delta = endPos - startPos
	local distance = delta.Magnitude
	if distance < 1 then
		return
	end
	local length = math.min(TRACER_LENGTH, distance)
	local part = effectPart({
		Size = Vector3.new(0.06, 0.06, length),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 225, 130),
		Transparency = own and 0.4 or 0.2,
	})
	table.insert(tracers, { Part = part, Start = startPos, Dir = delta / distance, Distance = distance, Traveled = 0,
		Length = length })
end

RunService.RenderStepped:Connect(function(dt)
	for i = #tracers, 1, -1 do
		local tracer = tracers[i]
		tracer.Traveled += TRACER_SPEED * dt
		local head = math.min(tracer.Traveled, tracer.Distance)
		local tail = math.max(0, tracer.Traveled - tracer.Length)
		if tail >= tracer.Distance then
			tracer.Part:Destroy()
			table.remove(tracers, i)
		else
			local length = math.max(head - tail, 0.05)
			local mid = tracer.Start + tracer.Dir * ((head + tail) / 2)
			tracer.Part.Size = Vector3.new(0.06, 0.06, length)
			tracer.Part.CFrame = CFrame.lookAt(mid, mid + tracer.Dir)
		end
	end
end)

-- ---------- Einschläge ----------

-- Ausrichtung mit +Y entlang der Normalen (für Partikel nach außen)
local function alongNormal(position, normal)
	local up = math.abs(normal.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	return CFrame.lookAt(position, position + normal, up) * CFrame.Angles(-math.pi / 2, 0, 0)
end

-- Einmaliger Partikel-Ausstoß an einer Stelle
local function burst(cframe, count, props)
	local anchor = Instance.new("Attachment")
	anchor.WorldCFrame = cframe
	anchor.Parent = workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.EmissionDirection = Enum.NormalId.Top
	for key, value in props do
		emitter[key] = value
	end
	emitter.Parent = anchor
	emitter:Emit(count)
	Debris:AddItem(anchor, 1.5)
end

local holes = {}

local function bulletHole(position, normal)
	local hole = effectPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.02, 0.22, 0.22),
		Color = Color3.fromRGB(28, 26, 24),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.1,
	})
	-- Zylinder-Achse (X) entlang der Normalen, knapp vor der Oberfläche
	hole.CFrame = CFrame.lookAt(position + normal * 0.012, position + normal * 2) * CFrame.Angles(0, math.pi / 2, 0)
	Debris:AddItem(hole, HOLE_TIME)
	table.insert(holes, hole)
	while #holes > MAX_HOLES do
		local oldest = table.remove(holes, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

-- Farbe der getroffenen Oberfläche (für den Staub)
local function surfaceColor(position, normal)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local result = workspace:Raycast(position + normal * 0.2, -normal * 0.6, params)
	if result and result.Instance:IsA("BasePart") then
		return result.Instance.Color
	end
	return Color3.fromRGB(150, 145, 135)
end

-- kind: "Character" (Treffer-Blitz), "World" (Funken, Staub, Einschussloch), "Prop" (ohne Loch)
function WeaponEffects.Impact(position, normal, kind)
	if typeof(position) ~= "Vector3" then
		return
	end
	normal = typeof(normal) == "Vector3" and normal.Magnitude > 0.5 and normal.Unit or Vector3.yAxis
	local cframe = alongNormal(position, normal)
	if kind == "Character" then
		burst(cframe, 8, {
			Texture = SPARK_TEXTURE,
			Color = ColorSequence.new(Color3.fromRGB(255, 235, 235), Color3.fromRGB(255, 70, 60)),
			LightEmission = 0.8,
			Size = NumberSequence.new(0.35, 0),
			Lifetime = NumberRange.new(0.08, 0.18),
			Speed = NumberRange.new(6, 14),
			SpreadAngle = Vector2.new(70, 70),
		})
		return
	end
	burst(cframe, 6, {
		Texture = SPARK_TEXTURE,
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 140, 40)),
		LightEmission = 1,
		Size = NumberSequence.new(0.18, 0),
		Lifetime = NumberRange.new(0.08, 0.2),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(55, 55),
		Acceleration = Vector3.new(0, -60, 0),
	})
	burst(cframe, 4, {
		Texture = SMOKE_TEXTURE,
		Color = ColorSequence.new(surfaceColor(position, normal)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(35, 35),
		Drag = 4,
		Rotation = NumberRange.new(0, 360),
	})
	if kind == "World" then
		bulletHole(position, normal)
	end
end

-- Kompletter Schuss-Effekt (Sound, Mündungsfeuer, Leuchtspur, Einschlag)
function WeaponEffects.Shot(weaponName, startPos, endPos, normal, hitKind, own)
	WeaponEffects.GunSound(weaponName, startPos, own)
	local direction = endPos - startPos
	if direction.Magnitude > 0.01 then
		WeaponEffects.MuzzleFlash(CFrame.lookAt(startPos, endPos), own and 0.8 or 1)
	end
	WeaponEffects.Tracer(startPos, endPos, own)
	if hitKind then
		WeaponEffects.Impact(endPos, normal, hitKind)
	end
end

-- ---------- Hülsen und Magazine ----------

-- Fliegende Hülse. cframe = Auswurf, right = Richtung nach rechts, inherit = Geschwindigkeit des Schützen
function WeaponEffects.EjectShell(cframe, scale, right, inherit, color)
	local shell = effectPart({
		Size = Vector3.new(0.05, 0.05, 0.15) * scale,
		CFrame = cframe * CFrame.Angles(0, math.pi / 2, 0),
		Color = color or BRASS,
		Material = Enum.Material.Metal,
		Anchored = false,
	})
	local up = cframe.UpVector
	shell.AssemblyLinearVelocity = (inherit or Vector3.zero)
		+ right * (9 + math.random() * 4) * scale + up * (7 + math.random() * 3) * scale
	shell.AssemblyAngularVelocity = Vector3.new(math.random() * 30 - 15, math.random() * 30 - 15, math.random() * 30 - 15)
	Debris:AddItem(shell, 0.6)
end

-- Fallende Kopie von Teilen (z.B. leeres Magazin). collide = bleibt am Boden liegen statt durchzufallen
function WeaponEffects.DropCopy(parts, velocity, collide, lifetime)
	local main = nil
	for _, original in parts do
		if original:IsA("BasePart") then
			local copy = effectPart({
				Size = original.Size,
				CFrame = original.CFrame,
				Color = original.Color,
				Material = original.Material,
				Shape = original:IsA("Part") and original.Shape or Enum.PartType.Block,
				Anchored = false,
				CanCollide = collide == true,
			})
			if main then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = main
				weld.Part1 = copy
				weld.Parent = copy
			else
				main = copy
			end
			Debris:AddItem(copy, lifetime or 2)
		end
	end
	if main then
		main.AssemblyLinearVelocity = velocity or Vector3.zero
		main.AssemblyAngularVelocity = Vector3.new(math.random() * 6 - 3, math.random() * 6 - 3, math.random() * 6 - 3)
	end
end

-- Herausfallende Hülsen (Revolver)
function WeaponEffects.Spill(position, count, scale, inherit)
	for _ = 1, count do
		local shell = effectPart({
			Size = Vector3.new(0.05, 0.05, 0.12) * scale,
			CFrame = CFrame.new(position + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.1 * scale)
				* CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Color = BRASS,
			Material = Enum.Material.Metal,
			Anchored = false,
		})
		shell.AssemblyLinearVelocity = (inherit or Vector3.zero) + Vector3.new(math.random() - 0.5, -1, math.random() - 0.5) * 3 * scale
		Debris:AddItem(shell, 0.8)
	end
end

return WeaponEffects

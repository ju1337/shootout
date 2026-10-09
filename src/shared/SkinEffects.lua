-- SkinEffects (ModuleScript)
-- Effekte besonderer Waffen-Skins (Cosmetics: Effects = "<Stil>", z.B. "Drachengold"):
--   * Glitzer-Sterne auf der Waffe, aufsteigende Glutfunken, warmes Licht (GunModels.Build -> Apply)
--   * pulsierendes Glühen ("Atem") der Skin-Texturen und des Lichts (Client, Init)
--   * Feuerstoß mit Lichtblitz an der Mündung bei jedem Schuss (WeaponClient -> Breath)
-- Bilder: Attribute FX_Glitzer, FX_Glut, FX_Flamme (Asset-Id) am Skin-Ordner der Waffe
-- (ReplicatedStorage.Assets.Weapons.<Waffe>.Skins.<Skin-Id>), sonst Roblox-Standardbilder.
-- Texturen im Skin-Ordner: SurfaceAppearances benannt wie die Teile (Skin_Body, Magazine, ...); eine namens
-- "Aufsaetze" bekommen alle angebauten Aufsätze (außer Glas und Leuchtpunkt).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SkinStyles = require(script.Parent.SkinStyles)

local SkinEffects = {}

SkinEffects.Tag = "SkinFx" -- am Hauptteil jeder Waffe mit Effekt-Skin (Attribut SkinFx = Stil)

-- Werte wie im Drachengold-Paket (Drachengold_Setup.lua)
SkinEffects.Styles = {
	Drachengold = {
		Glow = Color3.fromRGB(255, 110, 25), -- Farbe der Lava
		GlowMin = 1.5, -- schwächstes Leuchten im Puls
		GlowMax = 8, -- stärkstes Leuchten im Puls
		Pulse = 2.6, -- Sekunden pro Atemzug
		BreathParticles = 12, -- Größe des Feuerstoßes beim Schießen
		GlitterParts = 6, -- so viele der größten Teile glitzern
	},
}
-- Skins mit eigenen Partikeln, Leuchtspur, Einschlag und Finisher (Daten in SkinStyles, z.B. Splitterlicht)
for name, style in SkinStyles do
	if type(style) == "table" and style.Weapon then
		style.Generic = true
		SkinEffects.Styles[name] = style
	end
end

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SKIP = { "glass", "neon", "reticle", "point_", "pivot_" }

local function skipped(part)
	if part.Name == "Handle" or part.Transparency >= 0.95 then
		return true
	end
	local name = string.lower(part.Name)
	for _, word in SKIP do
		if string.find(name, word, 1, true) then
			return true
		end
	end
	return false
end

local function NS(points)
	local list = {}
	for _, p in points do
		table.insert(list, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(list)
end

local function CS(points)
	local list = {}
	for _, p in points do
		table.insert(list, ColorSequenceKeypoint.new(p[1], p[2]))
	end
	return ColorSequence.new(list)
end

local function make(className, name, props, parent)
	local obj = Instance.new(className)
	obj.Name = name
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

-- Skin-Ordner der Waffe (oder nil)
function SkinEffects.Folder(weaponName, skinId)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local weapons = assets and assets:FindFirstChild("Weapons")
	local weapon = weapons and weaponName and weapons:FindFirstChild(weaponName)
	local skins = weapon and weapon:FindFirstChild("Skins")
	return skins and skinId and skins:FindFirstChild(skinId) or nil
end

-- Bild aus dem Skin-Ordner (Attribut FX_<key>), sonst fallback
local function image(folder, key, fallback)
	local id = folder and folder:GetAttribute("FX_" .. key)
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. string.format("%.0f", id)
	elseif type(id) == "string" and id ~= "" and id ~= "0" then
		return string.match(id, "^%d+$") and "rbxassetid://" .. id or id
	end
	return fallback
end

local function volume(part)
	return part.Size.X * part.Size.Y * part.Size.Z
end

-- Effekte an ein fertiges Waffenmodell (Teile direkt im Modell, Waffe ~4 Studs lang, noch nicht skaliert).
-- textures = Skin-Ordner der Waffe (oder nil). Gibt das Teil mit den Effekten zurück (oder nil).
local applyGeneric -- (unten) Effekte der Skins aus SkinStyles

function SkinEffects.Apply(model, skin, textures, info)
	local style = skin and skin.Effects and SkinEffects.Styles[skin.Effects]
	if not style then
		return nil
	end
	-- Aufsätze bekommen die Skin-Textur "Aufsaetze"
	local attachmentLook = textures and textures:FindFirstChild("Aufsaetze")
	local visible = {}
	local minZ, maxZ = math.huge, -math.huge
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and not skipped(part) then
			if attachmentLook and attachmentLook:IsA("SurfaceAppearance") and part:IsA("MeshPart")
				and string.sub(part.Name, 1, 3) == "Att" then
				for _, old in part:GetChildren() do
					if old:IsA("SurfaceAppearance") then
						old:Destroy()
					end
				end
				attachmentLook:Clone().Parent = part
			end
			table.insert(visible, part)
			local z, half = part.Position.Z, part.Size.Magnitude / 2
			minZ, maxZ = math.min(minZ, z - half), math.max(maxZ, z + half)
		end
	end
	if #visible == 0 then
		return nil
	end
	table.sort(visible, function(a, b)
		return volume(a) > volume(b)
	end)
	local main = visible[1]
	local S = math.clamp((maxZ - minZ) / 4, 0.25, 2) -- Effektgröße relativ zu einer ~4 Studs langen Waffe

	-- Glühen: alle Skin-Texturen pulsieren (Client)
	for _, obj in model:GetDescendants() do
		if obj:IsA("SurfaceAppearance") then
			obj:SetAttribute("SkinGlow", true)
		end
	end
	if style.Generic then
		return applyGeneric(model, skin, style, textures, info)
	end

	-- Glitzer auf den größten Teilen, verteilt nach Fläche
	local chosen, total = {}, 0
	for i = 1, math.min(style.GlitterParts, #visible) do
		local s = visible[i].Size
		local area = 2 * (s.X * s.Y + s.Y * s.Z + s.X * s.Z)
		table.insert(chosen, { visible[i], area })
		total += area
	end
	for _, entry in chosen do
		make("ParticleEmitter", "SkinFx_Glitzer", {
			Texture = image(textures, "Glitzer", SPARKLE),
			Rate = math.max(0.6, 7 * entry[2] / total),
			Lifetime = NumberRange.new(0.25, 0.55),
			Speed = NumberRange.new(0, 0),
			Size = NS({ { 0, 0 }, { 0.3, 0.32 * S }, { 1, 0 } }),
			Rotation = NumberRange.new(0, 90),
			RotSpeed = NumberRange.new(-40, 40),
			LightEmission = 1,
			LightInfluence = 0,
			Brightness = 4,
			Color = CS({ { 0, Color3.fromRGB(255, 248, 225) }, { 1, Color3.fromRGB(255, 205, 120) } }),
			LockedToPart = true,
			ZOffset = 0.25,
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		}, entry[1])
	end

	-- aufsteigende Glutfunken
	make("ParticleEmitter", "SkinFx_Glut", {
		Texture = image(textures, "Glut", SPARKLE),
		Rate = 9,
		Lifetime = NumberRange.new(1.0, 2.2),
		Speed = NumberRange.new(0.2 * S, 0.9 * S),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 2.2 * S, 0),
		Drag = 1.2,
		Size = NS({ { 0, 0.05 * S }, { 0.5, 0.07 * S }, { 1, 0 } }),
		Transparency = NS({ { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } }),
		Color = CS({ { 0, Color3.fromRGB(255, 236, 160) }, { 0.4, Color3.fromRGB(255, 140, 40) },
			{ 1, Color3.fromRGB(200, 40, 10) } }),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 5,
		LockedToPart = false,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	}, main)

	-- warmes, pulsierendes Licht
	make("PointLight", "SkinFx_Licht", {
		Color = style.Glow,
		Brightness = 1,
		Range = math.clamp(6 * S, 4, 16),
		Shadows = false,
	}, main)

	main:SetAttribute("SkinFx", skin.Effects)
	CollectionService:AddTag(main, SkinEffects.Tag)
	return main
end

-- Feuerstoß an der Mündung (nur Client). cframe: Mündung, LookVector = Schussrichtung; scale wie beim Mündungsfeuer
function SkinEffects.Breath(cframe, scale, weaponName, skinId, styleName)
	local style = SkinEffects.Styles[styleName or ""]
	if not style or style.Generic then
		return
	end
	local S = scale or 1
	local folder = SkinEffects.Folder(weaponName, skinId)
	local holder = Instance.new("Part")
	holder.Name = "SkinFx_Drachenatem"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.05, 0.05, 0.05)
	holder.CFrame = cframe
	local emitter = make("ParticleEmitter", "Atem", {
		Texture = image(folder, "Flamme", FIRE),
		Enabled = false,
		Rate = 0,
		Lifetime = NumberRange.new(0.18, 0.4),
		Speed = NumberRange.new(0.5 * S, 2.5 * S),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 5,
		Acceleration = Vector3.new(0, 1.5 * S, 0),
		Size = NS({ { 0, 0.15 * S }, { 0.35, 0.45 * S }, { 1, 0.1 * S } }),
		Transparency = NS({ { 0, 0.1 }, { 0.6, 0.35 }, { 1, 1 } }),
		Color = CS({ { 0, Color3.fromRGB(255, 240, 180) }, { 0.3, Color3.fromRGB(255, 150, 40) },
			{ 1, Color3.fromRGB(160, 30, 10) } }),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-180, 180),
		LightEmission = 1,
		LightInfluence = 0,
		Brightness = 4,
		LockedToPart = false,
	}, holder)
	local flash = make("PointLight", "Blitz", {
		Color = Color3.fromRGB(255, 150, 60),
		Brightness = 6,
		Range = math.clamp(7 * S, 4, 18),
		Shadows = false,
	}, holder)
	holder.Parent = workspace
	emitter:Emit(style.BreathParticles)
	task.delay(0.07, function()
		flash.Brightness = 0
	end)
	task.delay(0.6, function()
		holder:Destroy()
	end)
end

-- ---------- Skins aus SkinStyles (z.B. Splitterlicht) ----------

local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function colors(points)
	local list = {}
	for _, p in points do
		table.insert(list, { p[1], rgb(p[2]) })
	end
	return CS(list)
end

local function pick(value, fp) -- Zahl oder { TP, FP }
	if type(value) == "table" then
		return fp and value[2] or value[1]
	end
	return value
end

local function range(v, default)
	v = v or default
	return NumberRange.new(v[1], v[2])
end

-- ParticleEmitter aus einem Eintrag in SkinStyles (fp = eigene Waffe vor der Kamera: eigene Größen/Helligkeit)
local function emitterFrom(spec, folder, fp, name)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = image(folder, spec.Image, SkinStyles.Fallback[spec.Image] or SPARKLE)
	e.Lifetime = range(spec.Lifetime, { 0.5, 0.5 })
	e.Speed = range(spec.Speed, { 0, 0 })
	local spread = spec.Spread or { 0, 0 }
	e.SpreadAngle = Vector2.new(spread[1], spread[2])
	e.EmissionDirection = Enum.NormalId[spec.Direction or "Top"]
	e.Size = NS(fp and spec.SizeFP or spec.Size)
	e.Transparency = NS(fp and spec.TransparencyFP or spec.Transparency or { { 0, 0 }, { 1, 1 } })
	e.Color = colors(spec.Color)
	e.LightEmission = spec.LightEmission or 0
	e.LightInfluence = spec.LightInfluence or 0
	e.Brightness = pick(spec.Brightness or 1, fp)
	e.Drag = spec.Drag or 0
	local a = spec.Acceleration or { 0, 0, 0 }
	e.Acceleration = Vector3.new(a[1], a[2], a[3])
	if spec.Shape == "Box" then
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	end
	e.Rotation = range(spec.Rotation, { 0, 0 })
	e.RotSpeed = range(spec.RotSpeed, { 0, 0 })
	e.Orientation = Enum.ParticleOrientation[spec.Orientation or "FacingCamera"]
	e.LockedToPart = spec.Locked == true
	e.ZOffset = spec.ZOffset or 0
	return e
end

local function holderPart(name, cframe, size)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Transparency = 1
	part.Size = size or Vector3.new(0.05, 0.05, 0.05)
	part.CFrame = cframe
	return part
end

-- Kurze Partikel an einer Stelle (Schuss, Einschlag): Emitter einmal auslösen, Halter danach weg
local function burstAt(cframe, specs, folder, fp, filter)
	local holder = holderPart("SkinFx_Burst", cframe)
	local emitters = {}
	for i, spec in specs do
		if not filter or filter(i, spec) then
			local e = emitterFrom(spec, folder, fp, "SkinFx_" .. i)
			e.Enabled = false
			e.Rate = 0
			e.Parent = holder
			table.insert(emitters, { e, pick(spec.Emit or 1, fp) })
		end
	end
	if #emitters == 0 then
		holder:Destroy()
		return nil
	end
	holder.Parent = workspace
	for _, entry in emitters do
		entry[1]:Emit(entry[2])
	end
	task.delay(0.6, function()
		holder:Destroy()
	end)
	return holder
end

-- Dauer-Effekte an der Waffe: unsichtbare Box unter dem Verschluss mit Partikeln, Licht und Laufglut
applyGeneric = function(model, skin, style, textures, info)
	local handle = model.PrimaryPart or model:FindFirstChild("Handle")
	local base = handle and handle.CFrame or CFrame.new()
	local o, size = style.Box.Offset, style.Box.Size
	local box = holderPart("SkinFx_Box", base * CFrame.new(o[1], o[2], o[3]), Vector3.new(size[1], size[2], size[3]))
	for _, spec in style.Weapon do
		local e = emitterFrom(spec, textures, false, "SkinFx_Dauer")
		e.Rate = pick(spec.Rate, false)
		e:SetAttribute("RateTP", pick(spec.Rate, false))
		e:SetAttribute("RateFP", pick(spec.Rate, true))
		e.Parent = box
	end
	make("PointLight", "SkinFx_Licht", {
		Color = rgb(style.Light.Color),
		Brightness = style.Light.TP[1],
		Range = style.Light.TP.Range,
		Shadows = false,
	}, box)
	if style.Heat then
		local muzzle = info and info.Muzzle or Vector3.new(0, 0.5, -2.7)
		local mid = Instance.new("Attachment")
		mid.Name = "SkinFx_Laufmitte"
		mid.CFrame = box.CFrame:ToObjectSpace(base * CFrame.new(muzzle * 0.6))
		mid.Parent = box
		make("PointLight", "SkinFx_Laufglut", { Color = rgb(style.Heat.Cold), Brightness = 0, Range = 3,
			Shadows = false }, mid)
	end
	box:SetAttribute("SkinFx", skin.Effects)
	box:SetAttribute("SkinId", skin.Id)
	box.Parent = model
	CollectionService:AddTag(box, SkinEffects.Tag)
	return box
end

-- ---------- Client: Glühen und Licht pulsieren lassen, Glitzer-Burst beim Ausrüsten ----------
local tracked = {} -- [Hauptteil] = { Style, Glow = { SurfaceAppearance }, Lights = { PointLight }, ... }
local aiming = false

local function collect(main)
	local root = main.Parent
	local entry = { Style = SkinEffects.Styles[main:GetAttribute("SkinFx") or ""], Glow = {}, Lights = {},
		Emitters = {}, Heat = 0, Shown = 0, LastShot = -math.huge }
	if not entry.Style or not root then
		return nil
	end
	for _, obj in root:GetDescendants() do
		if obj:IsA("SurfaceAppearance") and obj:GetAttribute("SkinGlow") then
			table.insert(entry.Glow, obj)
		elseif obj:IsA("PointLight") and obj.Name == "SkinFx_Licht" then
			table.insert(entry.Lights, obj)
		elseif obj:IsA("PointLight") and obj.Name == "SkinFx_Laufglut" then
			entry.HeatLight = obj
		elseif obj:IsA("ParticleEmitter") and obj.Name == "SkinFx_Dauer" then
			table.insert(entry.Emitters, obj)
		end
	end
	return entry
end

local function burst(main)
	local root = main.Parent
	for _, obj in root and root:GetDescendants() or {} do
		if obj:IsA("ParticleEmitter") and obj.Name == "SkinFx_Glitzer" then
			obj:Emit(5)
		end
	end
end

local function track(main)
	if tracked[main] ~= nil or not main:IsA("BasePart") then
		return
	end
	tracked[main] = collect(main) or false
	if main:IsDescendantOf(workspace) then
		burst(main)
	end
	-- Ausrüsten: Tool wandert aus dem Rucksack in den Charakter (in workspace)
	main.AncestryChanged:Connect(function()
		if main.Parent == nil then
			tracked[main] = nil
		elseif main:IsDescendantOf(workspace) then
			local old = tracked[main]
			tracked[main] = collect(main) or false
			if old and tracked[main] then
				tracked[main].Heat, tracked[main].Shown, tracked[main].LastShot = old.Heat, old.Shown, old.LastShot
			end
			burst(main)
		end
	end)
end

-- Stärke des Glühens (0..1) zur Zeit t
function SkinEffects.PulseAt(style, t)
	if style.Generic then -- sanfter Sinus, kein Flackern
		return 0.5 - 0.5 * math.cos(2 * math.pi * t / style.Glow.Period)
	end
	local breath = (0.5 - 0.5 * math.cos(t / math.max(0.2, style.Pulse) * 2 * math.pi)) ^ 1.6
	return math.clamp(breath + math.noise(t * 3.1, 0.5) * 0.15, 0, 1)
end

local function setGlow(entry, strength, tint)
	for _, appearance in entry.Glow do
		pcall(function()
			appearance.EmissiveStrength = strength
			appearance.EmissiveTint = tint
		end)
	end
end

local lastUpdate = nil
local function updateGeneric(main, entry, t, dt)
	local style = entry.Style
	local camera = workspace.CurrentCamera
	local fp = camera ~= nil and main:IsDescendantOf(camera)
	local k = SkinEffects.PulseAt(style, t)
	-- Laufglühen: Hitze steigt pro Schuss, fällt nach einer Pause, angezeigter Wert läuft weich hinterher
	local heat = style.Heat
	if heat then
		if t - entry.LastShot > heat.Delay then
			entry.Heat = math.max(0, entry.Heat - heat.Cool * dt)
		end
		entry.Shown += (entry.Heat - entry.Shown) * math.min(1, heat.Smooth * dt)
	end
	local h = entry.Shown
	setGlow(entry, style.Glow.Min + (style.Glow.Max - style.Glow.Min) * k + (heat and heat.Glow * h or 0),
		rgb(style.Glow.Tint))
	local light = fp and style.Light.FP or style.Light.TP
	for _, l in entry.Lights do
		l.Brightness = light[1] + (light[2] - light[1]) * k
		l.Range = light.Range
	end
	for _, e in entry.Emitters do
		e.Rate = fp and (aiming and 0 or e:GetAttribute("RateFP")) or e:GetAttribute("RateTP")
	end
	if heat and entry.HeatLight then
		entry.HeatLight.Color = rgb(heat.Cold):Lerp(rgb(heat.Hot), h)
		entry.HeatLight.Brightness = h > 0.001 and (heat.Brightness[1] + heat.Brightness[2] * h) * (fp and heat.FPFactor or 1) or 0
		entry.HeatLight.Range = heat.Range[1] + heat.Range[2] * h
	end
end

function SkinEffects.Update(t)
	local dt = lastUpdate and math.clamp(t - lastUpdate, 0, 0.25) or 0
	lastUpdate = t
	for main, entry in tracked do
		if entry and main:IsDescendantOf(workspace) then
			if entry.Style.Generic then
				updateGeneric(main, entry, t, dt)
			else
				local k = SkinEffects.PulseAt(entry.Style, t)
				setGlow(entry, entry.Style.GlowMin + (entry.Style.GlowMax - entry.Style.GlowMin) * k, entry.Style.Glow)
				for _, light in entry.Lights do
					light.Brightness = 0.3 + 1.7 * k
					light.Color = entry.Style.Glow
				end
			end
		end
	end
end

-- Beim Zielen keine Dauer-Partikel an der eigenen Waffe (WeaponClient)
function SkinEffects.SetAiming(on)
	aiming = on == true
end

-- Ein Schuss aus dieser Waffe (Tool oder Waffe vor der Kamera): Laufglühen steigt
function SkinEffects.Fired(container, t)
	for _, obj in container and container:GetDescendants() or {} do
		local entry = obj:IsA("BasePart") and tracked[obj]
		if entry and entry.Style.Heat then
			entry.Heat = math.min(1, entry.Heat + entry.Style.Heat.PerShot)
			entry.LastShot = t or os.clock()
		end
	end
end

local shotCount = 0
-- Schuss-Effekt an der Mündung. own = eigener Schuss, fp = Ego-Ansicht, silenced = Schalldämpfer.
-- true = ersetzt das normale Mündungsfeuer (Splitterlicht), false = normales Mündungsfeuer bleibt (Drachengold)
function SkinEffects.Shot(cframe, scale, weaponName, skinId, styleName, own, fp, silenced)
	local style = SkinEffects.Styles[styleName or ""]
	if not style then
		return false
	end
	if not style.Generic then
		if own or not silenced then
			SkinEffects.Breath(cframe, scale, weaponName, skinId, styleName)
		end
		return false
	end
	shotCount += 1
	local specs = style.Muzzle
	if silenced then
		specs = own and style.Silenced or nil -- Gegner sehen mit Schalldämpfer kein Mündungsfeuer
	end
	if specs then
		burstAt(cframe, specs, SkinEffects.Folder(weaponName, skinId), fp, function(_, spec)
			return not (fp and spec.EveryFP and shotCount % spec.EveryFP ~= 0)
		end)
	end
	return true
end

-- Leuchtspur als Beam von start nach endPos. true = ersetzt die normale Leuchtspur
function SkinEffects.Tracer(startPos, endPos, weaponName, skinId, styleName, fp)
	local style = SkinEffects.Styles[styleName or ""]
	local spec = style and style.Tracer
	if not spec or (endPos - startPos).Magnitude < 1 then
		return spec ~= nil
	end
	local look = fp and spec.FP or spec.TP
	local holder = holderPart("SkinFx_Spur", CFrame.new(startPos))
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.CFrame = CFrame.new(endPos - startPos)
	a1.Parent = holder
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	local texture = image(SkinEffects.Folder(weaponName, skinId), spec.Image, "")
	if texture ~= "" then
		beam.Texture = texture
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureLength = 1
	end
	beam.Color = colors(spec.Color)
	beam.Transparency = NS(look.Transparency)
	beam.Width0, beam.Width1 = look.Width[1], look.Width[2]
	beam.LightEmission, beam.LightInfluence, beam.Brightness = 1, 0, spec.Brightness
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = holder
	holder.Parent = workspace
	-- voll sichtbar, dann gleichmäßig ausblenden, dann weg
	task.delay(look.Hold, function()
		for step = 1, 4 do
			local f = step / 4
			local points = {}
			for _, p in look.Transparency do
				table.insert(points, { p[1], p[2] + (1 - p[2]) * f })
			end
			beam.Transparency = NS(points)
			task.wait(look.Fade / 4)
		end
		holder:Destroy()
	end)
	return true
end

-- Ausrichtung mit +Y entlang der Normalen (Partikel fliegen vom Treffer weg)
local function alongNormal(position, normal)
	local up = math.abs(normal.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	return CFrame.lookAt(position, position + normal, up) * CFrame.Angles(-math.pi / 2, 0, 0)
end

local impacts = {}
-- Einschlag-Effekt des Skins (zusätzlich zum normalen Einschlag); höchstens 12 gleichzeitig
function SkinEffects.Impact(position, normal, weaponName, skinId, styleName)
	local style = SkinEffects.Styles[styleName or ""]
	if not (style and style.Impact) or typeof(normal) ~= "Vector3" or normal.Magnitude < 0.5 then
		return
	end
	while #impacts >= 12 do
		local old = table.remove(impacts, 1)
		if old.Parent then
			old:Destroy()
		end
	end
	local holder = burstAt(alongNormal(position, normal.Unit), style.Impact, SkinEffects.Folder(weaponName, skinId), false)
	if holder then
		table.insert(impacts, holder)
	end
end

-- Hat der Stil einen Kill-Finisher? (Server, KillService)
function SkinEffects.HasFinisher(styleName)
	local style = SkinEffects.Styles[styleName or ""]
	return style ~= nil and style.Finisher ~= nil
end

local function lowGraphics()
	local ok, low = pcall(function()
		local PlayerSettings = require(script.Parent.PlayerSettings)
		return PlayerSettings.Get("Graphics") == "Low"
	end)
	return ok and low == true
end

-- Kill-Finisher an der Stelle des Gegners (Client, alle Spieler im Modus). model = Charakter des Opfers (oder nil)
function SkinEffects.Finisher(model, rootCFrame, styleName, weaponName, skinId)
	local style = SkinEffects.Styles[styleName or ""]
	local spec = style and style.Finisher
	if not spec or typeof(rootCFrame) ~= "CFrame" then
		return nil
	end
	local folder = SkinEffects.Folder(weaponName, skinId)
	local low = lowGraphics()
	local part = holderPart("SkinFx_Finisher", rootCFrame, Vector3.new(2, 4.5, 1))
	local function attachment(name, y)
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = CFrame.new(0, y, 0)
		a.Parent = part
		return a
	end
	local floor, chest, emblem = attachment("Boden", -3), attachment("Brust", 1), attachment("Emblem", 1.5)
	local function emit(entry, parent)
		local e = emitterFrom(entry, folder, false, "SkinFx_Finisher")
		e.Enabled = false
		e.Rate = 0
		e.Parent = parent
		e:Emit(low and entry.EmitLow or entry.Emit or 1)
	end
	local light = make("PointLight", "Licht", { Color = rgb(spec.Light.Color), Brightness = 0,
		Range = spec.Light.Range, Shadows = false }, chest)
	local highlight = nil
	if model and model.Parent then
		highlight = make("Highlight", "SkinFx_Kristall", {
			Adornee = model, FillColor = rgb(spec.Highlight.Fill), FillTransparency = 0.6,
			OutlineColor = rgb(spec.Highlight.Outline), OutlineTransparency = spec.Highlight.OutlineTransparency,
			DepthMode = Enum.HighlightDepthMode.Occluded,
		}, part)
	end
	part.Parent = workspace
	local function tween(obj, time, props)
		if obj and obj.Parent then
			TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Sine), props):Play()
		end
	end
	-- 0.00 s: Kristall, Bodenring, Licht an
	tween(highlight, 0.3, { FillTransparency = 0.25 })
	emit(spec.Ring, floor)
	tween(light, 0.3, { Brightness = spec.Light.Brightness })
	task.delay(0.3, function()
		tween(light, 0.9, { Brightness = 0 })
	end)
	-- 0.10 s: Kristallglanz im Körper
	task.delay(0.1, function()
		emit(spec.Shine, part)
	end)
	-- 0.35 s: Zerspringen (Körper verschwindet, Splitter, Kernblitz)
	task.delay(0.35, function()
		if model and model.Parent then
			for _, obj in model:GetDescendants() do
				if obj:IsA("BasePart") and obj.Transparency < 1 then
					tween(obj, 0.15, { Transparency = 1 })
				elseif obj:IsA("Decal") then
					tween(obj, 0.15, { Transparency = 1 })
				end
			end
		end
		tween(highlight, 0.1, { FillTransparency = 0.6 })
		emit(spec.Shatter, part)
		emit(spec.Core, chest)
	end)
	-- 0.60 s: Emblem steigt auf, Prismenstaub
	task.delay(0.6, function()
		emit(spec.Emblem, emblem)
		emit(spec.Dust, part)
	end)
	-- 1.20 s: Kristall ausblenden, 1.6 s: weg
	task.delay(1.2, function()
		tween(highlight, 0.3, { FillTransparency = 1, OutlineTransparency = 1 })
	end)
	task.delay(1.6, function()
		part:Destroy()
	end)
	return part
end

local started = false
function SkinEffects.Init()
	if started or not RunService:IsClient() then
		return
	end
	started = true
	CollectionService:GetInstanceAddedSignal(SkinEffects.Tag):Connect(track)
	for _, main in CollectionService:GetTagged(SkinEffects.Tag) do
		track(main)
	end
	-- die eigene Waffe vor der Kamera entsteht auf dem Client und wird direkt angemeldet (Track)
	RunService.Heartbeat:Connect(function()
		SkinEffects.Update(os.clock())
	end)
	-- Kill-Finisher (Server schickt ihn an alle im Modus)
	local Remotes = require(script.Parent.Remotes)
	if Remotes.SkinFinisher then
		Remotes.SkinFinisher.OnClientEvent:Connect(function(model, rootCFrame, styleName, weaponName, skinId)
			SkinEffects.Finisher(model, rootCFrame, styleName, weaponName, skinId)
		end)
	end
end

-- Modelle, die der Client selbst baut (Waffe vor der Kamera), direkt anmelden
function SkinEffects.Track(model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("SkinFx") then
			track(part)
		end
	end
end

return SkinEffects

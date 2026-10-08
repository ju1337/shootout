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
function SkinEffects.Apply(model, skin, textures)
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
	if not style then
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

-- Client: Glühen und Licht pulsieren lassen, Glitzer-Burst beim Ausrüsten
local tracked = {} -- [Hauptteil] = { Style, Glow = { SurfaceAppearance }, Lights = { PointLight } }

local function collect(main)
	local root = main.Parent
	local entry = { Style = SkinEffects.Styles[main:GetAttribute("SkinFx") or ""], Glow = {}, Lights = {} }
	if not entry.Style or not root then
		return nil
	end
	for _, obj in root:GetDescendants() do
		if obj:IsA("SurfaceAppearance") and obj:GetAttribute("SkinGlow") then
			table.insert(entry.Glow, obj)
		elseif obj:IsA("PointLight") and obj.Name == "SkinFx_Licht" then
			table.insert(entry.Lights, obj)
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
			tracked[main] = collect(main) or false
			burst(main)
		end
	end)
end

-- Stärke des Glühens (0..1) zur Zeit t
function SkinEffects.PulseAt(style, t)
	local breath = (0.5 - 0.5 * math.cos(t / math.max(0.2, style.Pulse) * 2 * math.pi)) ^ 1.6
	return math.clamp(breath + math.noise(t * 3.1, 0.5) * 0.15, 0, 1)
end

function SkinEffects.Update(t)
	for main, entry in tracked do
		if entry and main:IsDescendantOf(workspace) then
			local k = SkinEffects.PulseAt(entry.Style, t)
			local strength = entry.Style.GlowMin + (entry.Style.GlowMax - entry.Style.GlowMin) * k
			for _, appearance in entry.Glow do
				pcall(function()
					appearance.EmissiveStrength = strength
					appearance.EmissiveTint = entry.Style.Glow
				end)
			end
			for _, light in entry.Lights do
				light.Brightness = 0.3 + 1.7 * k
				light.Color = entry.Style.Glow
			end
		end
	end
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

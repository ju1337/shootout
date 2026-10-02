-- HangarScene (ModuleScript, nur Client)
-- Hintergrund der Agentenwahl: Hangar eines Raumschiffs als 3D-Szene in einem ViewportFrame.
-- Der Agent steht auf einer runden Plattform (Ursprung, Blick nach -Z zur Kamera), dahinter ein großes
-- Fenster ins All mit Sternen, Planet und Mond, an den Seiten Rippen mit Lichtleisten, ein geparktes
-- Landungsschiff und Frachtkisten. Ring und Lichtleisten leuchten in der Farbe des gewählten Agenten.
-- Kamera: so eingestellt, dass der Agent zwischen Kopfzeile und Agenten-Leiste der Auswahl steht
-- (Füße ~640, Kopf ~130 von 900); das Fenster füllt die obere Bildhälfte. Achtung: die Kamera schaut
-- nach +Z, Welt-+X liegt also im Bild LINKS.

local HangarScene = {}

local CAMERA_POSITION = Vector3.new(0, 3.4, -15)
local CAMERA_TARGET = Vector3.new(0, 2.1, 0)
local FOV = 36

local METAL = Color3.fromRGB(34, 40, 52)
local METAL_DARK = Color3.fromRGB(20, 24, 32)
local METAL_LIGHT = Color3.fromRGB(70, 78, 94)
local SPACE = Color3.fromRGB(3, 5, 12)
local GRID = Color3.fromRGB(26, 80, 110)

local function part(model, size, cframe, color, neon, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

-- Scheibe (Zylinder mit senkrechter Achse) bzw. Scheibe mit Achse nach Z (im Fenster)
local function disc(model, diameter, height, position, color, neon, facingZ)
	local rotation = facingZ and CFrame.Angles(0, math.rad(90), 0) or CFrame.Angles(0, 0, math.rad(90))
	return part(model, Vector3.new(height, diameter, diameter), CFrame.new(position) * rotation, color, neon,
		Enum.PartType.Cylinder)
end

local function buildHangar(model)
	local accents = {}

	-- Boden mit Leuchtraster
	part(model, Vector3.new(140, 1, 100), CFrame.new(0, -1.1, 25), METAL_DARK)
	for x = -48, 48, 8 do
		part(model, Vector3.new(0.15, 0.05, 100), CFrame.new(x, -0.58, 25), GRID, true)
	end
	for z = -20, 70, 8 do
		part(model, Vector3.new(140, 0.05, 0.15), CFrame.new(0, -0.58, z), GRID, true)
	end
	-- Plattform mit Leuchtring (Agentenfarbe)
	disc(model, 9, 0.6, Vector3.new(0, -0.3, 0), METAL)
	disc(model, 7.2, 0.06, Vector3.new(0, 0.01, 0), METAL_LIGHT)
	table.insert(accents, disc(model, 9.8, 0.25, Vector3.new(0, -0.45, 0), Color3.new(1, 1, 1), true))
	table.insert(accents, disc(model, 7.4, 0.03, Vector3.new(0, 0.02, 0), Color3.new(1, 1, 1), true))

	-- Rückwand mit großem Fenster (x -22..22, y 2..14) ins All
	local wallZ = 30
	part(model, Vector3.new(140, 30, 1), CFrame.new(0, 29, wallZ + 0.5), METAL_DARK)         -- über dem Fenster
	part(model, Vector3.new(140, 3, 1), CFrame.new(0, 0.5, wallZ + 0.5), METAL_DARK)         -- unter dem Fenster
	part(model, Vector3.new(48, 12, 1), CFrame.new(-46, 8, wallZ + 0.5), METAL_DARK)         -- links
	part(model, Vector3.new(48, 12, 1), CFrame.new(46, 8, wallZ + 0.5), METAL_DARK)          -- rechts
	-- Weltraum hinter dem Fenster: Sterne und ein Planet mit leuchtender Atmosphäre
	local spaceZ = wallZ + 12
	part(model, Vector3.new(80, 40, 1), CFrame.new(0, 8, spaceZ), SPACE)
	local random = Random.new(7)
	for _ = 1, 90 do
		local size = random:NextNumber(0.08, 0.22)
		part(model, Vector3.new(size, size, 0.05), CFrame.new(random:NextNumber(-34, 34), random:NextNumber(-4, 22), spaceZ - 0.6),
			Color3.fromRGB(220, 230, 255), true)
	end
	-- Planet im Bild links neben dem Agenten (zwischen Team-Spalte und Agent), Mond rechts über dem Kopf
	disc(model, 10.6, 0.1, Vector3.new(10, 9, spaceZ - 0.8), Color3.fromRGB(70, 140, 255), true, true)  -- Atmosphäre
	disc(model, 10, 0.1, Vector3.new(10, 9, spaceZ - 0.9), Color3.fromRGB(40, 70, 120), false, true)     -- Planet
	disc(model, 7, 0.1, Vector3.new(11.3, 10.2, spaceZ - 1), Color3.fromRGB(55, 95, 150), false, true)   -- helle Seite
	disc(model, 2.2, 0.1, Vector3.new(-6, 13, spaceZ - 0.8), Color3.fromRGB(150, 150, 165), false, true) -- Mond
	-- Fensterrahmen und Streben
	part(model, Vector3.new(46, 0.8, 1.2), CFrame.new(0, 14.4, wallZ), METAL_LIGHT)
	part(model, Vector3.new(46, 0.8, 1.2), CFrame.new(0, 1.6, wallZ), METAL_LIGHT)
	for x = -22.5, 22.5, 9 do
		part(model, Vector3.new(0.6, 13, 1.2), CFrame.new(x, 8, wallZ), METAL_LIGHT)
	end
	table.insert(accents, part(model, Vector3.new(46, 0.15, 0.2), CFrame.new(0, 1.15, wallZ - 0.7), Color3.new(1, 1, 1), true))

	-- Seitenwände mit Rippen und Lichtleisten
	for _, side in { -1, 1 } do
		local x = side * 32
		part(model, Vector3.new(1, 40, 60), CFrame.new(x + side * 1.5, 18, 5), METAL_DARK)
		for z = -22, 28, 6 do
			part(model, Vector3.new(1.6, 40, 1.2), CFrame.new(x, 18, z), METAL)
		end
		table.insert(accents, part(model, Vector3.new(0.2, 0.2, 60), CFrame.new(x - side * 0.9, 1.2, 5), Color3.new(1, 1, 1), true))
		part(model, Vector3.new(0.2, 0.2, 60), CFrame.new(x - side * 0.9, 9, 5), Color3.fromRGB(60, 90, 120), true)
	end

	-- Landungsschiff hinten, im Bild rechts (schräg geparkt, Nase zur Mitte)
	local ship = CFrame.new(-16, 0, 18) * CFrame.Angles(0, math.rad(35), 0)
	part(model, Vector3.new(6, 3, 13), ship * CFrame.new(0, 2.6, 0), METAL_LIGHT)                         -- Rumpf
	part(model, Vector3.new(6, 1.6, 4), ship * CFrame.new(0, 3.2, -8.4), METAL_LIGHT)                     -- Nase
	part(model, Vector3.new(4.4, 1, 3), ship * CFrame.new(0, 4.4, -6.6), Color3.fromRGB(30, 70, 110), true) -- Cockpit
	part(model, Vector3.new(18, 0.5, 5), ship * CFrame.new(0, 2.4, 2.5), METAL)                           -- Flügel
	part(model, Vector3.new(0.6, 3.5, 3), ship * CFrame.new(0, 5.6, 5), METAL)                            -- Leitwerk
	for _, x in { -2, 2 } do
		disc(model, 1.8, 0.4, (ship * CFrame.new(x, 2.6, 6.7)).Position, Color3.fromRGB(255, 140, 50), true, true) -- Triebwerk
		part(model, Vector3.new(0.6, 1.2, 0.6), ship * CFrame.new(x * 1.4, 0.6, -2), METAL_DARK)          -- Landebein
		part(model, Vector3.new(0.6, 1.2, 0.6), ship * CFrame.new(x * 1.4, 0.6, 3), METAL_DARK)
	end

	-- Frachtkisten, im Bild links
	local crateColor = Color3.fromRGB(60, 66, 58)
	for _, data in { { 17, 0, 12, 0 }, { 14.5, 0, 12.5, 12 }, { 15.8, 2.4, 12.2, -8 }, { 20, 0, 18, 20 } } do
		local crate = CFrame.new(data[1], data[2] + 1.2, data[3]) * CFrame.Angles(0, math.rad(data[4]), 0)
		part(model, Vector3.new(2.4, 2.4, 2.4), crate, crateColor)
		part(model, Vector3.new(2.46, 0.3, 2.46), crate * CFrame.new(0, 0.5, 0), Color3.fromRGB(200, 150, 40))
	end
	return accents
end

-- Szene in parent bauen. Gibt { Viewport, Camera, SetAccent(color), Update(time) } zurück.
-- Der Agent kommt mit scene.Viewport als Parent hinein (steht am Ursprung, Blick nach -Z).
function HangarScene.new(parent)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Hangar"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundColor3 = SPACE
	viewport.BackgroundTransparency = 0
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(105, 115, 140)
	viewport.LightColor = Color3.fromRGB(225, 232, 255)
	viewport.LightDirection = Vector3.new(-0.35, -1, 0.55)
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.CFrame = CFrame.lookAt(CAMERA_POSITION, CAMERA_TARGET)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local model = Instance.new("Model")
	model.Name = "Hangar"
	local accents = buildHangar(model)
	model.Parent = viewport
	viewport.Parent = parent

	local scene = { Viewport = viewport, Camera = camera }
	function scene.SetAccent(color)
		for _, accent in accents do
			accent.Color = color
		end
	end
	-- Ganz leichtes Schweben der Kamera, damit der Hangar lebt
	function scene.Update(time)
		local sway = Vector3.new(math.sin(time * 0.23) * 0.5, math.sin(time * 0.31) * 0.15, 0)
		camera.CFrame = CFrame.lookAt(CAMERA_POSITION + sway, CAMERA_TARGET)
	end
	scene.SetAccent(Color3.fromRGB(40, 210, 230))
	return scene
end

return HangarScene

-- KitCrate (ModuleScript, nur Client)
-- 3D-Kiste für das KITS-Fenster (ExtinctionClient): eine Kiste aus Teilen in einem ViewportFrame, die sich leicht hin
-- und her dreht. Bereit zum Abholen hüpft sie sanft und leuchtet, gesperrt ist sie dunkel.
--   KitCrate.View(parent, { Color, Style = "Wood" | "Metal" | "Gold", ZIndex, Size, Position }) -> view
--   view.SetState("Ready" | "Wait" | "Locked"), view.Pop() (kurzer Sprung nach dem Abholen)

local RunService = game:GetService("RunService")

local KitCrate = {}

local WOOD = Color3.fromRGB(124, 84, 50)
local STEEL = Color3.fromRGB(58, 62, 70)
local GOLD = Color3.fromRGB(214, 168, 64)

local function part(model, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- Kiste bauen (Mitte unten bei 0, 0, 0; Vorderseite zeigt nach -Z)
function KitCrate.Build(color, style)
	local model = Instance.new("Model")
	model.Name = "KitCrate"
	local bodyColor, bodyMaterial = WOOD, Enum.Material.WoodPlanks
	local trim, trimMaterial = STEEL, Enum.Material.DiamondPlate
	if style == "Metal" then
		bodyColor, bodyMaterial = color:Lerp(STEEL, 0.55), Enum.Material.Metal
	elseif style == "Gold" then
		bodyColor, bodyMaterial = Color3.fromRGB(34, 34, 40), Enum.Material.Metal
		trim, trimMaterial = GOLD, Enum.Material.Foil
	end
	local w, h, d = 4, 2.4, 2.8
	local body = part(model, "Body", Vector3.new(w, h, d), CFrame.new(0, h / 2, 0), bodyColor, bodyMaterial)
	model.PrimaryPart = body
	-- Deckel mit Rand und leuchtendem Streifen
	part(model, "Lid", Vector3.new(w + 0.2, 0.5, d + 0.2), CFrame.new(0, h + 0.2, 0), bodyColor:Lerp(Color3.new(0, 0, 0), 0.15),
		bodyMaterial)
	part(model, "LidStripe", Vector3.new(w * 0.62, 0.08, 0.42), CFrame.new(0, h + 0.48, 0), color, Enum.Material.Neon)
	-- Eckpfosten und Bänder
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			part(model, "Corner", Vector3.new(0.32, h + 0.5, 0.32), CFrame.new(x * (w / 2), h / 2 + 0.1, z * (d / 2)), trim,
				trimMaterial)
		end
		part(model, "Band", Vector3.new(0.34, h + 0.62, d + 0.12), CFrame.new(x * w * 0.3, h / 2 + 0.12, 0), trim, trimMaterial)
		-- Griffe an den Seiten
		part(model, "Handle", Vector3.new(0.16, 0.26, 1.3), CFrame.new(x * (w / 2 + 0.16), h * 0.62, 0), trim, trimMaterial)
	end
	-- Schloss vorne (leuchtet in der Kit-Farbe) und Schild darunter
	part(model, "LatchPlate", Vector3.new(0.9, 0.8, 0.1), CFrame.new(0, h - 0.15, -d / 2 - 0.05), trim, trimMaterial)
	part(model, "Latch", Vector3.new(0.46, 0.34, 0.08), CFrame.new(0, h - 0.15, -d / 2 - 0.12), color, Enum.Material.Neon)
	part(model, "Plate", Vector3.new(1.6, 0.5, 0.06), CFrame.new(0, h * 0.38, -d / 2 - 0.03), color:Lerp(Color3.new(1, 1, 1), 0.15),
		Enum.Material.SmoothPlastic)
	return model
end

function KitCrate.View(parent, options)
	local color = options.Color or Color3.new(1, 1, 1)
	local z = options.ZIndex or 1
	local holder = Instance.new("Frame")
	holder.Name = "CrateStage"
	holder.BackgroundTransparency = 1
	holder.Size = options.Size or UDim2.fromScale(1, 1)
	holder.Position = options.Position or UDim2.new()
	holder.ZIndex = z
	holder.Parent = parent

	-- Leuchten hinter der Kiste (runder, weicher Fleck) und Schatten auf dem Boden
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(0.78, 0.92)
	glow.BackgroundColor3 = color
	glow.BorderSizePixel = 0
	glow.ZIndex = z
	glow.Parent = holder
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = glow
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1, 1) })
	fade.Rotation = 90
	fade.Parent = glow
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.86)
	shadow.Size = UDim2.fromScale(0.62, 0.1)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.5
	shadow.BorderSizePixel = 0
	shadow.ZIndex = z
	shadow.Parent = holder
	local shadowRound = Instance.new("UICorner")
	shadowRound.CornerRadius = UDim.new(1, 0)
	shadowRound.Parent = shadow

	local view = Instance.new("ViewportFrame")
	view.Name = "Crate"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(140, 140, 150)
	view.LightColor = Color3.fromRGB(255, 245, 230)
	view.LightDirection = Vector3.new(-0.6, -1, 0.5)
	view.ZIndex = z + 1
	view.Parent = holder

	local model = KitCrate.Build(color, options.Style)
	model.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(5.2, 5.4, -10.5), Vector3.new(0, 1.35, 0))
	camera.Parent = view
	view.CurrentCamera = camera

	-- Teile mit ihrer Lage zur Kistenmitte (zum Drehen und Hüpfen)
	local base = {}
	for _, p in model:GetChildren() do
		base[p] = p.CFrame
	end

	local state = "Wait"
	local popUntil = 0
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not holder.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock() - started
		local yaw = math.sin(t * 0.7) * 0.42 + 0.15
		local lift = 0
		if state == "Ready" then
			lift = math.abs(math.sin(t * 2.4)) * 0.35
			glow.BackgroundTransparency = 0.2 + math.sin(t * 2.4) * 0.15
		end
		local now = os.clock()
		if now < popUntil then
			local k = 1 - (popUntil - now) / 0.5
			lift += math.sin(k * math.pi) * 1.2
		end
		local turn = CFrame.new(0, lift, 0) * CFrame.Angles(0, yaw, 0)
		for p, cf in base do
			p.CFrame = turn * cf
		end
		shadow.Size = UDim2.fromScale(0.62 - lift * 0.08, 0.1)
	end)

	local handle = { Frame = holder }

	function handle.SetState(newState)
		state = newState
		local locked = newState == "Locked"
		view.ImageTransparency = locked and 0.25 or 0
		view.ImageColor3 = locked and Color3.fromRGB(110, 110, 120) or Color3.new(1, 1, 1)
		glow.BackgroundTransparency = newState == "Ready" and 0.25 or (locked and 0.92 or 0.7)
	end

	function handle.Pop()
		popUntil = os.clock() + 0.5
	end

	handle.SetState("Wait")
	return handle
end

return KitCrate

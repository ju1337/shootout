-- ItemPreview (ModuleScript, nur Client)
-- 3D-Vorschau eines Skins in einem ViewportFrame (Markt, Tausch): Waffen-Skins auf dem Sturmgewehr von der Seite
-- (die Kamera rückt so weit weg, dass die ganze Waffe ins Bild passt), Agenten-Skins als Figur. Licht wie in der
-- Lobby (LobbyPages).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunModels = require(Shared.GunModels)
local AgentFigure = require(Shared.AgentFigure)
local AgentConfig = require(Shared.AgentConfig)

local ItemPreview = {}

-- Neuer ViewportFrame mit Lobby-Licht (props wie bei Instance-Eigenschaften)
function ItemPreview.New(parent, props)
	local view = Instance.new("ViewportFrame")
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(130, 135, 150)
	view.LightColor = Color3.fromRGB(255, 245, 235)
	view.LightDirection = Vector3.new(-0.5, -1, 0.6)
	for key, value in props or {} do
		view[key] = value
	end
	view.Parent = parent
	return view
end

-- Skin item in view zeigen; aspect = Breite / Höhe der Vorschau
function ItemPreview.Show(view, item, aspect)
	view:ClearAllChildren()
	if not item then
		return
	end
	local camera = Instance.new("Camera")
	if item.Type == "Weapon" then
		local model = GunModels.Build(item.Weapon or "Rifle", item)
		model.Parent = view
		local box, size = model:GetBoundingBox()
		local halfV = math.rad(15)
		local halfH = math.atan(math.tan(halfV) * (aspect or 1.4))
		local distance = math.max(size.Z / 2 / math.tan(halfH), size.Y / 2 / math.tan(halfV)) / 0.8 + size.X / 2
		camera.FieldOfView = 30
		camera.CFrame = CFrame.lookAt(box.Position + Vector3.new(distance, distance * 0.15, 0), box.Position)
	else
		local agent = AgentConfig.Get(item.Agent) or AgentConfig.Agents[1]
		local figure = AgentFigure.Build(agent, item.Primary, item.Accent, nil, nil, item.Id)
		figure:PivotTo(CFrame.new(0, 3, 0) * CFrame.Angles(0, 0.4, 0))
		figure.Parent = view
		camera.FieldOfView = 36
		camera.CFrame = AgentFigure.CameraCFrame
	end
	camera.Parent = view
	view.CurrentCamera = camera
end

return ItemPreview

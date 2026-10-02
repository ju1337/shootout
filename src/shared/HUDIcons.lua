-- HUDIcons (ModuleScript, nur Client)
-- Kleine 3D-Bilder fürs HUD im Stil von Rogue Company:
--   Weapon   = flache weiße Waffen-Silhouette von der Seite, Lauf nach rechts (Killfeed, Munition).
--              Einfärben über ImageColor3 des ViewportFrames.
--   WeaponModel = dieselbe Ansicht in Farbe und mit Licht (Vorschau in der Agentenwahl), optional mit Skin
--   Portrait = Kopf und Schultern eines Agenten (Teamleiste, Lebensanzeige)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunModels = require(Shared.GunModels)
local AgentConfig = require(Shared.AgentConfig)
local AgentFigure = require(Shared.AgentFigure)
local Cosmetics = require(Shared.Cosmetics)

local HUDIcons = {}

local WHITE = Color3.new(1, 1, 1)
local SILHOUETTE_FOV = 12
local PORTRAIT_CAMERA = CFrame.lookAt(Vector3.new(1.1, 4.65, -3.75), Vector3.new(0, 4.42, 0))

-- Gibt es für diese Waffe eine Silhouette? (Messer, Granate und Fähigkeiten nicht)
function HUDIcons.HasWeapon(weaponName)
	return type(weaponName) == "string" and GunModels.Info[weaponName] ~= nil
end

-- Waffe von der Seite (Lauf nach rechts) in einen neuen ViewportFrame width x height.
-- colored = false: flache weiße Silhouette; true: Originalfarben (bzw. Skin) mit Licht.
local function weaponView(parent, weaponName, width, height, colored, skin)
	if not HUDIcons.HasWeapon(weaponName) then
		return nil
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = colored and "WeaponModel" or "WeaponIcon"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromOffset(width, height)
	if colored then
		viewport.Ambient = Color3.fromRGB(150, 155, 170)
		viewport.LightColor = Color3.fromRGB(255, 248, 235)
		viewport.LightDirection = Vector3.new(-0.6, -1, -0.35)
	else
		viewport.Ambient = WHITE
		viewport.LightColor = Color3.new(0, 0, 0)
	end
	viewport.ImageColor3 = WHITE

	-- Nur sichtbare Teile; Silhouette flach weiß
	local model = GunModels.Build(weaponName, colored and skin or nil)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			if part.Transparency >= 1 then
				part:Destroy()
			else
				if not colored then
					part.Color = WHITE
					part.Material = Enum.Material.SmoothPlastic
				end
				-- Achsenparallele Hülle des (evtl. gedrehten) Teils
				local cf, half = part.CFrame, part.Size / 2
				local extent = Vector3.new(
					math.abs(cf.RightVector.X) * half.X + math.abs(cf.UpVector.X) * half.Y + math.abs(cf.LookVector.X) * half.Z,
					math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z,
					math.abs(cf.RightVector.Z) * half.X + math.abs(cf.UpVector.Z) * half.Y + math.abs(cf.LookVector.Z) * half.Z)
				low = low:Min(cf.Position - extent)
				high = high:Max(cf.Position + extent)
			end
		end
	end
	model.Parent = viewport

	-- Kamera von rechts (+X): Lauf (-Z) zeigt im Bild nach rechts. Kleines Sichtfeld = kaum Perspektive.
	local center, size = (low + high) / 2, high - low
	local tanHalf = math.tan(math.rad(SILHOUETTE_FOV / 2))
	local distance = math.max(size.Y / 2, size.Z / 2 / (width / height)) * 1.08 / tanHalf + size.X / 2
	local camera = Instance.new("Camera")
	camera.FieldOfView = SILHOUETTE_FOV
	camera.CFrame = CFrame.lookAt(center + Vector3.new(distance, 0, 0), center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = parent
	return viewport
end

-- Weiße Silhouette (Killfeed, Munition). Gibt den ViewportFrame zurück, nil bei unbekannter Waffe.
function HUDIcons.Weapon(parent, weaponName, width, height)
	return weaponView(parent, weaponName, width, height, false, nil)
end

-- Farbige Vorschau mit Licht (Agentenwahl), skin = Waffen-Skin oder nil
function HUDIcons.WeaponModel(parent, weaponName, width, height, skin)
	return weaponView(parent, weaponName, width, height, true, skin)
end

-- Porträt-Feld (ViewportFrame size x size). Gibt { Frame, Set(agentId, player) } zurück;
-- player (oder nil bei Bots) bestimmt die Skin-Farben.
function HUDIcons.Portrait(parent, size)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Portrait"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromOffset(size, size)
	viewport.Ambient = Color3.fromRGB(150, 155, 170)
	viewport.LightColor = Color3.fromRGB(255, 245, 235)
	viewport.LightDirection = Vector3.new(-0.4, -0.7, 0.9)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.CFrame = PORTRAIT_CAMERA
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = parent

	local portrait = { Frame = viewport }
	local shownKey, figure = nil, nil
	function portrait.Set(agentId, owner)
		local agent = AgentConfig.Get(agentId)
		local primary, accent
		if agent then
			primary, accent = Cosmetics.AgentColors(owner, agent.Id)
		end
		local key = agent and (agent.Id .. tostring(primary) .. tostring(accent)) or ""
		if key == shownKey then
			return
		end
		shownKey = key
		if figure then
			figure:Destroy()
			figure = nil
		end
		if agent then
			figure = AgentFigure.Build(agent, primary, accent, nil)
			figure.Parent = viewport
		end
	end
	return portrait
end

return HUDIcons

-- AgentFigure (ModuleScript, nur Client)
-- 3D-Figur eines Agenten für Vorschauen (Agentenwahl, Lobby, Shop, Markt, Hub, Symbole), Waffe in der Hand.
-- Hat der Agent ein fertiges 3D-Modell (AgentModels, Assets.Agents), steht der Agenten-Körper aus dem Spiel mit
-- dieser Ausrüstung da; sonst die stilisierte Figur mit Kapuze, getöntem Visier und Weste. Körper so schlank wie im
-- Spiel (AgentConfig.BodyScale). Die Figur steht um den Ursprung (Füße auf 0, Blick nach -Z), ihr Drehpunkt liegt
-- wie bisher auf Höhe 3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunModels = require(Shared.GunModels)
local AgentConfig = require(Shared.AgentConfig)
local AgentModels = require(Shared.AgentModels)

local AgentFigure = {}

-- Kamera-Position, die die ganze Figur zeigt (Figur steht um den Ursprung, Blick nach -Z)
AgentFigure.CameraCFrame = CFrame.lookAt(Vector3.new(0, 3.1, -9.5), Vector3.new(0, 2.8, 0))

local SKIN = Color3.fromRGB(205, 160, 130)
local ARM_RAISE = math.rad(70) -- rechter Arm nach vorne angehoben (hält die Waffe)
local RIGHT_ARM = { "RightUpperArm", "RightLowerArm", "RightHand" }

-- Figur mit dem 3D-Modell: Spielkörper in Ruhelage (rechter Arm gehoben), Ausrüstung wie im Spiel
local function buildWithAsset(agent, primary, accent, weaponSkin, weaponName, agentSkinId)
	local model = Instance.new("Model")
	local pants = primary:Lerp(Color3.new(0, 0, 0), 0.5)
	local shoulder = AgentModels.RightShoulder
	local raise = CFrame.new(shoulder) * CFrame.Angles(ARM_RAISE, 0, 0) * CFrame.new(-shoulder)
	local parts = {}
	for _, name in AgentModels.BodyParts do
		local body = AgentModels.Body[name]
		local part = Instance.new("Part")
		part.Name = name
		part.Size = body.Size
		part.CFrame = table.find(RIGHT_ARM, name) and raise * body.CFrame or body.CFrame
		part.Color = name == "Head" and SKIN or ((string.find(name, "Leg") or string.find(name, "Foot")) and pants or primary)
		part.Material = Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = true
		part.Parent = model
		parts[name] = part
	end
	AgentModels.Attach(model, parts, agent.Id, primary, accent, agentSkinId, false)
	local gun = GunModels.Build(weaponName or agent.Loadout[1], weaponSkin)
	gun:PivotTo(CFrame.new(parts.RightHand.Position + Vector3.new(0, -0.12, -0.05)))
	gun.Parent = model
	model.WorldPivot = CFrame.new(0, 3, 0)
	return model
end

-- primary = Uniform, accent = Visier/Weste, weaponSkin = Skin der Waffe (oder nil),
-- weaponName = gezeigte Waffe (Standard: erste Waffe des Agenten), agentSkinId = Agenten-Skin (für Textur-Skins
-- eines 3D-Modells, optional)
function AgentFigure.Build(agent, primary, accent, weaponSkin, weaponName, agentSkinId)
	if AgentModels.HasAsset(agent.Id) then
		return buildWithAsset(agent, primary, accent, weaponSkin, weaponName, agentSkinId)
	end
	local model = Instance.new("Model")
	local function part(name, size, cframe, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.Parent = model
		return p
	end
	local pants = primary:Lerp(Color3.new(0, 0, 0), 0.5)
	-- Körper schmaler und flacher (Kopf bleibt): Breiten/Tiefen und seitliche Abstände skaliert
	local w, d = AgentConfig.BodyScale.Width, AgentConfig.BodyScale.Depth
	local function body(x, y, z)
		return Vector3.new(x * w, y, z * d)
	end
	local root = part("Torso", body(2, 2, 1), CFrame.new(0, 3, 0), primary)
	part("Vest", body(2.1, 1.1, 1.15), CFrame.new(0, 3.4, 0), accent, Enum.Material.Metal)
	part("Belt", body(2.05, 0.3, 1.05), CFrame.new(0, 2.1, 0), Color3.fromRGB(30, 30, 30))
	part("Head", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 4.6, 0), Color3.fromRGB(205, 160, 130))
	part("Hood", Vector3.new(1.4, 1.45, 1.3), CFrame.new(0, 4.68, 0.2), primary, Enum.Material.Fabric)
	part("Mask", Vector3.new(0.95, 0.4, 0.12), CFrame.new(0, 4.3, -0.56), Color3.fromRGB(45, 45, 50))
	local visor = part("Visor", Vector3.new(1.0, 0.22, 0.12), CFrame.new(0, 4.72, -0.57), AgentConfig.VisorColor(accent),
		AgentConfig.VisorMaterial)
	visor.Reflectance = 0.25
	local armX = 1.45 * w
	part("LeftPad", body(1, 0.4, 1), CFrame.new(-armX, 4.05, 0), accent, Enum.Material.Metal)
	part("RightPad", body(1, 0.4, 1), CFrame.new(armX, 4.05, 0), accent, Enum.Material.Metal)
	part("LeftArm", body(0.85, 2, 0.85), CFrame.new(-armX, 3, 0), primary)
	-- Rechter Arm nach vorne angehoben (hält die Waffe)
	part("RightArm", body(0.85, 2, 0.85), CFrame.new(armX, 3.3, -0.6) * CFrame.Angles(math.rad(70), 0, 0), primary)
	part("LeftLeg", body(0.95, 2, 0.95), CFrame.new(-0.5 * w, 1, 0), pants)
	part("RightLeg", body(0.95, 2, 0.95), CFrame.new(0.5 * w, 1, 0), pants)

	local gun = GunModels.Build(weaponName or agent.Loadout[1], weaponSkin)
	gun:PivotTo(CFrame.new(armX, 2.95, -1.55))
	gun.Parent = model

	model.PrimaryPart = root
	return model
end

return AgentFigure

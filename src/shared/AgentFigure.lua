-- AgentFigure (ModuleScript, nur Client)
-- Stilisierte 3D-Figur eines Agenten für Vorschauen (Agentenwahl, Shop, Rucksack):
-- Kapuze, getöntes Visier, Weste, Waffe in der Hand. Körper so schlank wie im Spiel (AgentConfig.BodyScale).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunModels = require(ReplicatedStorage:WaitForChild("Shared").GunModels)
local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)

local AgentFigure = {}

-- Kamera-Position, die die ganze Figur zeigt (Figur steht um den Ursprung, Blick nach -Z)
AgentFigure.CameraCFrame = CFrame.lookAt(Vector3.new(0, 3.1, -9.5), Vector3.new(0, 2.8, 0))

-- primary = Uniform, accent = Visier/Weste, weaponSkin = Skin der Waffe (oder nil),
-- weaponName = gezeigte Waffe (Standard: erste Waffe des Agenten)
function AgentFigure.Build(agent, primary, accent, weaponSkin, weaponName)
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

-- AgentFigure (ModuleScript, nur Client)
-- 3D-Figur für Vorschauen (Menü, Spielerkarte, Siegerpodest): der eigene Roblox-Avatar eines Spielers (Avatar). Ohne
-- Charakter (noch nicht gespawnt, Bot) eine einfache Figur im Roblox-Standard-Look (Build: runder Kopf in Hautfarbe mit
-- dem Roblox-Gesicht, Oberkörper und Arme in einer Farbe, Beine dunkler), Waffe in der Hand. Die Figur steht um den
-- Ursprung (Füße auf 0, Blick nach -Z), Drehpunkt auf Höhe 3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunModels = require(Shared.GunModels)
local AgentConfig = require(Shared.AgentConfig)

local AgentFigure = {}

-- Eigener Roblox-Avatar eines Spielers als Figur: Kopie seines Charakters, verankert, ohne Skripte und Töne, gleich
-- aufgestellt wie Build (Füße auf 0, Blick nach -Z, Drehpunkt auf Höhe 3). nil, wenn der Spieler gerade keinen
-- Charakter hat (dann nimmt der Aufrufer Build).
function AgentFigure.Avatar(player)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, clone = pcall(character.Clone, character)
	character.Archivable = wasArchivable
	if not ok or not clone then
		return nil
	end
	for _, item in clone:GetDescendants() do
		if item:IsA("LuaSourceContainer") or item:IsA("Sound") or item:IsA("ForceField") or item:IsA("BillboardGui")
			or item:IsA("ProximityPrompt") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
		end
	end
	local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
	local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid")
	if not cloneRoot or not cloneHumanoid then
		clone:Destroy()
		return nil
	end
	cloneHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	cloneRoot.Transparency = 1
	-- Füße auf 0: R15 steht die Hüfte HipHeight über dem Boden, R6 sitzt der Rumpf auf 2 Studs Beinen
	local rootY = humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.HipHeight + cloneRoot.Size.Y / 2 or 3
	clone.PrimaryPart = nil
	clone.WorldPivot = cloneRoot.CFrame
	clone:PivotTo(CFrame.new(0, rootY, 0))
	clone.WorldPivot = CFrame.new(0, 3, 0)
	clone.Name = "Avatar"
	return clone
end

-- Kamera-Position, die die ganze Figur zeigt (Figur steht um den Ursprung, Blick nach -Z)
AgentFigure.CameraCFrame = CFrame.lookAt(Vector3.new(0, 3.1, -9.5), Vector3.new(0, 2.8, 0))

-- Figur ohne Avatar: R15 mit klassischen Proportionen, schlank wie AgentConfig.BodyScale. Ruhelage: Ursprung = Boden
-- zwischen den Füßen, Blick nach -Z, Arme hängen.
local W, D = AgentConfig.BodyScale.Width, AgentConfig.BodyScale.Depth
local function bodyPart(width, height, depth, x, y)
	return { Size = Vector3.new(width, height, depth), CFrame = CFrame.new(x, y, 0) }
end
local BODY = {
	Head = bodyPart(1.2, 1.2, 1.2, 0, 4.5),
	UpperTorso = bodyPart(2 * W, 1.6, D, 0, 3.2),
	LowerTorso = bodyPart(2 * W, 0.4, D, 0, 2.2),
	LeftUpperArm = bodyPart(W, 1.169, D, -1.5 * W, 3.369),
	LeftLowerArm = bodyPart(W, 1.052, D, -1.5 * W, 2.776),
	LeftHand = bodyPart(W, 0.3, D, -1.5 * W, 2.15),
	RightUpperArm = bodyPart(W, 1.169, D, 1.5 * W, 3.369),
	RightLowerArm = bodyPart(W, 1.052, D, 1.5 * W, 2.776),
	RightHand = bodyPart(W, 0.3, D, 1.5 * W, 2.15),
	LeftUpperLeg = bodyPart(W, 1.217, D, -0.5 * W, 1.58),
	LeftLowerLeg = bodyPart(W, 1.193, D, -0.5 * W, 0.8),
	LeftFoot = bodyPart(W, 0.3, D, -0.5 * W, 0.15),
	RightUpperLeg = bodyPart(W, 1.217, D, 0.5 * W, 1.58),
	RightLowerLeg = bodyPart(W, 1.193, D, 0.5 * W, 0.8),
	RightFoot = bodyPart(W, 0.3, D, 0.5 * W, 0.15),
}
local RIGHT_SHOULDER = Vector3.new(W, 3.763, 0) -- rechtes Schultergelenk in Ruhelage
local SKIN_COLOR = Color3.fromRGB(205, 160, 130)
local FACE_TEXTURE = "rbxasset://textures/face.png" -- Roblox-Standardgesicht

local ARM_RAISE = math.rad(70) -- rechter Arm nach vorne angehoben (hält die Waffe)
local RIGHT_ARM = { "RightUpperArm", "RightLowerArm", "RightHand" }

-- primary = Farbe von Oberkörper und Armen, weaponSkin = Skin der Waffe (oder nil), weaponName = gezeigte Waffe
-- (Standard: erste Waffe des Agenten), material = Material des Körpers (nil = Standard); das 3. Argument (früher
-- zweite Farbe) wird ignoriert
function AgentFigure.Build(agent, primary, _accent, weaponSkin, weaponName, material)
	local model = Instance.new("Model")
	local pants = primary:Lerp(Color3.new(0, 0, 0), 0.5)
	local raise = CFrame.new(RIGHT_SHOULDER) * CFrame.Angles(ARM_RAISE, 0, 0) * CFrame.new(-RIGHT_SHOULDER)
	local parts = {}
	for name, body in BODY do
		local part = Instance.new("Part")
		part.Name = name
		part.Size = body.Size
		part.CFrame = table.find(RIGHT_ARM, name) and raise * body.CFrame or body.CFrame
		part.Color = name == "Head" and SKIN_COLOR
			or ((string.find(name, "Leg") or string.find(name, "Foot")) and pants or primary)
		part.Material = name ~= "Head" and material or Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = true
		part.Parent = model
		parts[name] = part
	end
	-- Kopf rund wie der Roblox-Kopf, vorne das Standardgesicht
	local headShape = Instance.new("SpecialMesh")
	headShape.MeshType = Enum.MeshType.Head
	headShape.Parent = parts.Head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = FACE_TEXTURE
	face.Face = Enum.NormalId.Front
	face.Parent = parts.Head
	-- Waffe in der rechten Hand
	local gun = GunModels.Build(weaponName or agent.Loadout[1], weaponSkin)
	gun:PivotTo(CFrame.new(parts.RightHand.Position + Vector3.new(0, -0.12, -0.05)))
	gun.Parent = model
	model.WorldPivot = CFrame.new(0, 3, 0)
	return model
end

return AgentFigure

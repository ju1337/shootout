-- AgentFigure (ModuleScript, nur Client)
-- 3D-Figur eines Agenten für Vorschauen (Agentenwahl, Lobby, Shop, Markt, Camp, Symbole), Waffe in der Hand. Sieht aus
-- wie im Spiel: das 3D-Modell des Agenten (AgentModels, Assets.Agents) genau wie gebaut, ohne Modell der
-- Agenten-Körper im Roblox-Standard-Look (runder Kopf in Hautfarbe mit dem Roblox-Gesicht, Oberkörper und Arme in der
-- Uniformfarbe, Beine dunkler). Die Figur steht um den Ursprung (Füße auf 0, Blick nach -Z), Drehpunkt auf Höhe 3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunModels = require(Shared.GunModels)
local AgentModels = require(Shared.AgentModels)

local AgentConfig = require(Shared.AgentConfig)

local AgentFigure = {}

-- Eigener Roblox-Avatar eines Spielers als Figur (AgentConfig.RobloxAvatar): Kopie seines Charakters, verankert, ohne
-- Skripte und Töne, gleich aufgestellt wie Build (Füße auf 0, Blick nach -Z, Drehpunkt auf Höhe 3). nil, wenn der
-- Avatar aus ist oder der Spieler gerade keinen Charakter hat (dann nimmt der Aufrufer Build).
function AgentFigure.Avatar(player)
	local character = AgentConfig.RobloxAvatar and player and player.Character
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

local ARM_RAISE = math.rad(70) -- rechter Arm nach vorne angehoben (hält die Waffe)
local RIGHT_ARM = { "RightUpperArm", "RightLowerArm", "RightHand" }

-- primary = Uniform (Standard-Look), weaponSkin = Skin der Waffe (oder nil), weaponName = gezeigte Waffe (Standard:
-- erste Waffe des Agenten), material = Material des Körpers (Agenten-Skin, nil = Standard); das 3. Argument (früher
-- zweite Farbe) wird ignoriert; look = Id eines Modells in Assets.Agents (Agenten-Skin mit Modell, Standard: der Agent)
function AgentFigure.Build(agent, primary, _accent, weaponSkin, weaponName, material, look)
	local model = Instance.new("Model")
	local pants = AgentModels.PantsColor(primary)
	local shoulder = AgentModels.RightShoulder
	local raise = CFrame.new(shoulder) * CFrame.Angles(ARM_RAISE, 0, 0) * CFrame.new(-shoulder)
	local parts = {}
	for _, name in AgentModels.BodyParts do
		local body = AgentModels.Body[name]
		local part = Instance.new("Part")
		part.Name = name
		part.Size = body.Size
		part.CFrame = table.find(RIGHT_ARM, name) and raise * body.CFrame or body.CFrame
		part.Color = name == "Head" and AgentModels.SkinColor
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
	face.Texture = AgentModels.FaceTexture
	face.Face = Enum.NormalId.Front
	face.Parent = parts.Head
	-- 3D-Modell des Agenten (blendet den Körper samt Gesicht aus)
	local worn = AgentModels.Attach(model, parts, look and AgentModels.HasAsset(look) and look or agent.Id, false)
	-- Waffe in der rechten Hand (ein Rig steht wie gebaut: dann in seiner Hand)
	local hand = worn and worn:FindFirstChildOfClass("Humanoid") and worn:FindFirstChild("RightHand", true)
	hand = hand and hand:IsA("BasePart") and hand or parts.RightHand
	local gun = GunModels.Build(weaponName or agent.Loadout[1], weaponSkin)
	gun:PivotTo(CFrame.new(hand.Position + Vector3.new(0, -0.12, -0.05)))
	gun.Parent = model
	model.WorldPivot = CFrame.new(0, 3, 0)
	return model
end

return AgentFigure

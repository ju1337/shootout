-- AgentFigure (ModuleScript, nur Client)
-- 3D-Figur eines Agenten für Vorschauen (Agentenwahl, Lobby, Shop, Markt, Hub, Symbole), Waffe in der Hand. Sieht aus
-- wie im Spiel: der Agenten-Körper im Roblox-Standard-Look (runder Kopf in Hautfarbe mit dem Roblox-Gesicht, Oberkörper
-- und Arme in der Uniformfarbe, Beine dunkler) – hat der Agent ein fertiges 3D-Modell (AgentModels, Assets.Agents),
-- trägt die Figur dieses Modell. Körper so schlank wie im Spiel (AgentConfig.BodyScale). Die Figur steht um den
-- Ursprung (Füße auf 0, Blick nach -Z), ihr Drehpunkt liegt auf Höhe 3.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GunModels = require(Shared.GunModels)
local AgentModels = require(Shared.AgentModels)

local AgentFigure = {}

-- Kamera-Position, die die ganze Figur zeigt (Figur steht um den Ursprung, Blick nach -Z)
AgentFigure.CameraCFrame = CFrame.lookAt(Vector3.new(0, 3.1, -9.5), Vector3.new(0, 2.8, 0))

local ARM_RAISE = math.rad(70) -- rechter Arm nach vorne angehoben (hält die Waffe)
local RIGHT_ARM = { "RightUpperArm", "RightLowerArm", "RightHand" }

-- primary = Uniform, accent = zweite Farbe (Farbzonen eines 3D-Modells), weaponSkin = Skin der Waffe (oder nil),
-- weaponName = gezeigte Waffe (Standard: erste Waffe des Agenten); ein 6. Argument (früher Agenten-Skin) wird ignoriert
function AgentFigure.Build(agent, primary, accent, weaponSkin, weaponName, _oldAgentSkin)
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
		part.Material = Enum.Material.SmoothPlastic
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
	-- 3D-Modell des Agenten (ein ganzer Charakter blendet die Körperteile aus, die er abdeckt – samt Gesicht)
	AgentModels.Attach(model, parts, agent.Id, primary, accent, false)
	local gun = GunModels.Build(weaponName or agent.Loadout[1], weaponSkin)
	gun:PivotTo(CFrame.new(parts.RightHand.Position + Vector3.new(0, -0.12, -0.05)))
	gun.Parent = model
	model.WorldPivot = CFrame.new(0, 3, 0)
	return model
end

return AgentFigure

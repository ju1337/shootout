-- Waffe vor der Kamera mit den echten Armen des Charakters (Spielkörper, Rig bzw. 3D-Modell ohne Rig) statt
-- Ärmel und Handschuhe; der Waffen-Skin bleibt auf der Waffe
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Run(SIM.Now + (seconds or 1))
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder", ReplicatedStorage)
assets.Name = "Assets"
local folder = assets:FindFirstChild("Agents") or Instance.new("Folder", assets)
folder.Name = "Agents"

-- Modell ohne Rig: ein Teil pro Körperteil (Viper), Boden = Point_Root
local SUIT = {
	{ "Head_Suit", Vector3.new(1.3, 1.2, 1.3), Vector3.new(0, 4.6, 0) },
	{ "UpperTorso_Suit", Vector3.new(1.5, 1.6, 0.8), Vector3.new(0, 3.2, 0) },
	{ "LowerTorso_Suit", Vector3.new(1.5, 0.4, 0.8), Vector3.new(0, 2.2, 0) },
	{ "LeftUpperArm_Suit", Vector3.new(0.75, 0.915, 0.8), Vector3.new(-1.125, 3.4925, 0) },
	{ "LeftLowerArm_Suit", Vector3.new(0.75, 0.76, 0.8), Vector3.new(-1.125, 2.655, 0) },
	{ "LeftHand_Suit", Vector3.new(0.75, 0.275, 0.8), Vector3.new(-1.125, 2.1375, 0) },
	{ "RightUpperArm_Suit", Vector3.new(0.75, 0.915, 0.8), Vector3.new(1.125, 3.4925, 0) },
	{ "RightLowerArm_Suit", Vector3.new(0.75, 0.76, 0.8), Vector3.new(1.125, 2.655, 0) },
	{ "RightHand_Suit", Vector3.new(0.75, 0.275, 0.8), Vector3.new(1.125, 2.1375, 0) },
	{ "LeftUpperLeg_Suit", Vector3.new(0.75, 0.82, 0.8), Vector3.new(-0.375, 1.59, 0) },
	{ "RightUpperLeg_Suit", Vector3.new(0.75, 0.82, 0.8), Vector3.new(0.375, 1.59, 0) },
}
local viper = Instance.new("Model")
viper.Name = "Viper"
for i, def in SUIT do
	local part = Instance.new("MeshPart")
	part.Name = def[1]
	part.Size = def[2]
	part.CFrame = CFrame.new(def[3])
	part.Color = Color3.fromRGB(10 + i, 200, 30)
	part.Parent = viper
end
local marker = Instance.new("Part")
marker.Name = "Point_Root"
marker.Size = Vector3.new(0.05, 0.05, 0.05)
marker.Parent = viper
viper.Parent = folder

local AgentModels = require("AgentModels")
local ViewModel = require("ViewModel")
local GunModels = require("GunModels")
local Cosmetics = require("Cosmetics")

-- Standard-R15-Körper in Ruhelage, Gelenke an den Übergängen, irgendwo gedreht in der Welt
local JOINTS = { Head = { "Neck", "UpperTorso" }, UpperTorso = { "Waist", "LowerTorso" }, LowerTorso = { "Root", "HumanoidRootPart" },
	RightUpperArm = { "RightShoulder", "UpperTorso" }, RightLowerArm = { "RightElbow", "RightUpperArm" },
	RightHand = { "RightWrist", "RightLowerArm" }, LeftUpperArm = { "LeftShoulder", "UpperTorso" },
	LeftLowerArm = { "LeftElbow", "LeftUpperArm" }, LeftHand = { "LeftWrist", "LeftLowerArm" } }
local function standardBody(where, color)
	local model = Instance.new("Model")
	model.Name = "Body"
	Instance.new("Humanoid", model)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CFrame = where * CFrame.new(0, 3, 0)
	root.Parent = model
	for _, name in AgentModels.BodyParts do
		local rest = AgentModels.Body[name]
		local part = Instance.new("MeshPart")
		part.Name = name
		part.Size = rest.Size
		part.CFrame = where * rest.CFrame
		part.Color = color
		part.Parent = model
	end
	for name, joint in JOINTS do
		local part, parent = model[name], model[joint[2]]
		local motor = Instance.new("Motor6D")
		motor.Name = joint[1]
		motor.Part0, motor.Part1 = parent, part
		-- Gelenkpunkt: Oberkante des Teils (Arme hängen)
		local point = part.CFrame * CFrame.new(0, part.Size.Y / 2 - 0.1, 0)
		motor.C0 = parent.CFrame:ToObjectSpace(point)
		motor.C1 = part.CFrame:ToObjectSpace(point)
		motor.Parent = part
	end
	-- Animation: Arm gehoben (die Ruhelage zählt, nicht die aktuelle Haltung)
	model.RightUpperArm.RightShoulder.Transform = CFrame.Angles(math.rad(80), 0, 0)
	local accessory = Instance.new("WeldConstraint", model.RightHand)
	accessory.Part0 = model.RightHand
	return model
end

local function armParts(vm)
	local list = {}
	for _, part in vm.Model:GetChildren() do
		if part:IsA("BasePart") and (string.match(part.Name, "^%a+Arm_%d+$") or string.match(part.Name, "^%a+Hand_%d+$")) then
			list[part.Name] = part
		end
	end
	return list
end

local camera = CFrame.new(5, 8, -3) * CFrame.Angles(0.1, 2.2, 0)
local function run(vm, aim)
	vm.DrawStart = os.clock() - 5
	for _ = 1, 3 do
		vm:Update(1 / 60, { Camera = camera, Aim = aim, Sprinting = false, Speed = 0 })
	end
end

-- ---------- Standard-Spielkörper ----------
local uniform = Color3.fromRGB(70, 120, 200)
local body = standardBody(CFrame.new(30, 0, 12) * CFrame.Angles(0, 1.3, 0), uniform)
body.Parent = workspace
local arms = AgentModels.ArmPieces(body)
check(arms ~= nil and arms.Right and arms.Left and #arms.Right.Pieces == 3 and #arms.Left.Pieces == 3,
	"Spielkörper: je Seite Oberarm, Unterarm und Hand gefunden")
check(arms and (arms.Right.Shoulder - Vector3.new(1.125, 0.8535, 0)).Magnitude < 1e-3
	and arms.Right.Shoulder.Y > arms.Right.Elbow.Y and arms.Right.Elbow.Y > arms.Right.Wrist.Y,
	"Spielkörper: Gelenke in Ruhelage (Schulter über Ellbogen über Handgelenk)")

for _, weaponName in { "Rifle", "Pistol" } do
	local vm = ViewModel.new(weaponName, nil, Color3.new(0, 0, 0), nil, AgentModels.ArmPieces(body))
	run(vm, 0)
	local info = GunModels.Info[weaponName]
	check(vm.Model:FindFirstChild("LeftGlove") == nil and vm.Model:FindFirstChild("RightFore") == nil,
		weaponName .. ": keine Ärmel und Handschuhe mehr")
	local list = armParts(vm)
	local count, hands = 0, {}
	for name, part in list do
		count += 1
		check(part.Color == uniform and part.Anchored and not part.CanCollide and not part.CanQuery
			and part.CastShadow == false and part.LocalTransparencyModifier == 0, weaponName .. ": " .. name .. " wie am Körper, ohne Kollision")
		check(part:FindFirstChildWhichIsA("JointInstance") == nil and part:FindFirstChildWhichIsA("WeldConstraint") == nil,
			weaponName .. ": " .. name .. " ohne Gelenke")
		check(part.Size.X > 0.05 and part.Size.Y > 0.05 and part.Size.Z > 0.05, weaponName .. ": " .. name .. " sichtbar groß")
		if string.find(name, "Hand") then
			hands[string.sub(name, 1, 4)] = part
		end
	end
	check(count == 6, weaponName .. ": sechs Armteile vor der Kamera (" .. count .. ")")
	-- Hände an der Waffe: rechts am Griff, links am Handschutz
	local s = ViewModel.Scale()
	local grip = vm.GunWorld.Position
	local guard = (vm.GunWorld * (info.LeftHand * s))
	check(hands.Righ and (hands.Righ.Position - grip).Magnitude < 0.35, weaponName .. ": rechte Hand am Griff")
	check(hands.Left and (hands.Left.Position - guard).Magnitude < 0.35, weaponName .. ": linke Hand an der Waffe")
	-- Arme kommen von unten hinter der Kamera ins Bild
	for name, part in list do
		local p = camera:PointToObjectSpace(part.Position)
		check(p.Y < 0.05, weaponName .. ": " .. name .. " unterhalb der Bildmitte")
	end
	-- Zielen: Hände bleiben an der Waffe
	run(vm, 1)
	check((hands.Righ.Position - vm.GunWorld.Position).Magnitude < 0.35, weaponName .. ": beim Zielen rechte Hand am Griff")
	vm:Destroy()
end

-- ---------- Spielkörper mit Modell daran (AgentModels.Attach): die Teile des Modells ----------
local worn = standardBody(CFrame.new(-4, 0, 9), uniform)
local parts = {}
for _, name in AgentModels.BodyParts do
	parts[name] = worn[name]
end
local holder = AgentModels.Attach(worn, parts, "Viper", true)
check(holder ~= nil, "Modell am Spielkörper")
local wornArms = AgentModels.ArmPieces(worn)
local segments = {}
for _, piece in wornArms and wornArms.Right.Pieces or {} do
	segments[piece.Segment] = string.match(piece.Part.Name, "^Right%a+_%d+$") ~= nil
end
check(wornArms ~= nil and #wornArms.Right.Pieces == 3 and segments.Upper and segments.Lower and segments.Hand,
	"Modell am Körper: die Armteile des Modells (nicht der unsichtbare Körper)")
check(wornArms and wornArms.Right.Pieces[1].Part.Color ~= uniform, "Modell am Körper: Farbe aus dem Modell")

-- ---------- Modell ohne Rig als eigener Charakter (BuildCharacter) ----------
local character = AgentModels.BuildCharacter("Viper")
check(character ~= nil, "Viper als Charakter")
character:PivotTo(CFrame.new(12, 3, -40) * CFrame.Angles(0, -0.7, 0))
character.Parent = workspace
local own = AgentModels.ArmPieces(character)
check(own ~= nil and #own.Right.Pieces == 3 and #own.Left.Pieces == 3, "Modell als Charakter: Arme über die Namen gefunden")
local vm = ViewModel.new("Rifle", nil, Color3.new(0, 0, 0), nil, own)
run(vm, 0)
local list = armParts(vm)
local modelColored = 0
for _, part in list do
	modelColored += part.Color.G > 0.7 and 1 or 0 -- Farbe aus der Datei (…, 200, 30)
end
check(modelColored == 6, "Modell als Charakter: sechs Armteile mit dem Aussehen des Modells (" .. modelColored .. ")")
-- Der Charakter selbst bleibt unverändert (Kopien)
check(character:FindFirstChild(AgentModels.ModelName):FindFirstChild("RightHand_Suit") ~= nil, "Charakter behält seine Teile")
vm:Destroy()

-- ---------- Ohne erkennbare Arme: Ärmel und Handschuhe wie bisher ----------
check(AgentModels.ArmPieces(nil) == nil, "ohne Charakter: nil")
local stump = Instance.new("Model")
Instance.new("Humanoid", stump)
local fallback = ViewModel.new("Rifle", nil, Color3.new(0.2, 0.2, 0.2), nil, AgentModels.ArmPieces(stump))
run(fallback, 0)
check(fallback.Model:FindFirstChild("LeftGlove") ~= nil and fallback.Model:FindFirstChild("RightFore") ~= nil,
	"ohne Arme: Ärmel und Handschuhe")

-- ---------- Waffen-Skin bleibt auf der Waffe ----------
local skinned = ViewModel.new("Rifle", Cosmetics.Get("W_Drachengold"), Color3.new(0, 0, 0), nil, AgentModels.ArmPieces(body))
run(skinned, 0)
for name, part in armParts(skinned) do
	check(part.Color == uniform and part.Material ~= Enum.Material.Foil and part:FindFirstChildWhichIsA("SurfaceAppearance") == nil
		and part:FindFirstChildWhichIsA("ParticleEmitter") == nil and not part:GetAttribute("SkinFx"),
		"Drachengold: " .. name .. " ohne Skin")
end
skinned:Destroy()

step(0.1)
if failures == 0 then
	print("OK: Ego-Arme")
end

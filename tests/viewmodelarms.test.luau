-- Waffe vor der Kamera mit den echten Armen des Roblox-Avatars (Ober- und Unterarm samt Shirt) und gebauten Händen mit
-- Fingern in der Hautfarbe der echten Hand; der Waffen-Skin bleibt auf der Waffe
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

local AvatarArms = require("AvatarArms")
local ViewModel = require("ViewModel")
ViewModel.ShowArms = true -- dieser Test prüft auch die Arme vor der Kamera
local GunModels = require("GunModels")
local Cosmetics = require("Cosmetics")

-- Standard-R15-Körper (schlank wie AgentConfig.BodyScale) in Ruhelage: Ursprung = Boden zwischen den Füßen, Blick -Z
local W, D = 0.75, 0.8
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
}
-- Gelenke an den Übergängen, irgendwo gedreht in der Welt
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
	for name, rest in BODY do
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

-- ---------- Avatar (R15) ----------
local uniform = Color3.fromRGB(70, 120, 200)
local skinTone = Color3.fromRGB(204, 142, 105)
local body = standardBody(CFrame.new(30, 0, 12) * CFrame.Angles(0, 1.3, 0), uniform)
body.RightHand.Color = skinTone
body.LeftHand.Color = skinTone
body.Parent = workspace
local arms = AvatarArms.ArmPieces(body)
check(arms ~= nil and arms.Right and arms.Left and #arms.Right.Pieces == 3 and #arms.Left.Pieces == 3,
	"Avatar: je Seite Oberarm, Unterarm und Hand gefunden")
check(arms and (arms.Right.Shoulder - Vector3.new(1.125, 0.8535, 0)).Magnitude < 1e-3
	and arms.Right.Shoulder.Y > arms.Right.Elbow.Y and arms.Right.Elbow.Y > arms.Right.Wrist.Y,
	"Avatar: Gelenke in Ruhelage (Schulter über Ellbogen über Handgelenk)")

for _, weaponName in { "Rifle", "Pistol" } do
	local vm = ViewModel.new(weaponName, nil, Color3.new(0, 0, 0), nil, AvatarArms.ArmPieces(body))
	run(vm, 0)
	local info = GunModels.Info[weaponName]
	check(vm.Model:FindFirstChild("RightFore") == nil and vm.Model:FindFirstChild("LeftUpper") == nil,
		weaponName .. ": keine gebauten Ärmel")
	local list = armParts(vm)
	local count = 0
	for name, part in list do
		count += 1
		check(not string.find(name, "Hand"), weaponName .. ": " .. name .. ": echte Roblox-Hand ersetzt")
		check(part.Color == uniform and part.Anchored and not part.CanCollide and not part.CanQuery
			and part.CastShadow == false and part.LocalTransparencyModifier == 0, weaponName .. ": " .. name .. " wie am Körper, ohne Kollision")
		check(part:FindFirstChildWhichIsA("JointInstance") == nil and part:FindFirstChildWhichIsA("WeldConstraint") == nil,
			weaponName .. ": " .. name .. " ohne Gelenke")
		check(part.Size.X > 0.05 and part.Size.Y > 0.05 and part.Size.Z > 0.05, weaponName .. ": " .. name .. " sichtbar groß")
	end
	check(count == 4, weaponName .. ": Ober- und Unterarme vor der Kamera (" .. count .. ")")
	-- gebaute Hände mit Fingern und Daumen in der Hautfarbe
	local hands = { Righ = vm.Model:FindFirstChild("RightGlove"), Left = vm.Model:FindFirstChild("LeftGlove") }
	for _, side in { "Right", "Left" } do
		for _, piece in { "Glove", "Fingers", "Tips", "Thumb", "Wrist" } do
			local part = vm.Model:FindFirstChild(side .. piece)
			check(part and part.Color == skinTone and part.Material == Enum.Material.SmoothPlastic and not part.CanCollide,
				weaponName .. ": " .. side .. piece .. " in Hautfarbe")
		end
	end
	check(vm.Model:FindFirstChild("RightIndex") ~= nil, weaponName .. ": Zeigefinger am Abzug")
	-- Unterarm endet an der gebauten Hand
	local wrist = hands.Righ and hands.Righ.CFrame * (vm.Arms.Right.WristLocal * ViewModel.Scale())
	local fore
	for name, part in list do
		if string.match(name, "^RightLowerArm") then
			fore = part
		end
	end
	local wristPart = vm.Model:FindFirstChild("RightWrist")
	check(fore and wristPart and (wristPart.Position - wrist).Magnitude < (fore.Position - wrist).Magnitude
		and (wristPart.Position - hands.Righ.Position).Magnitude < 0.2, weaponName .. ": Handgelenk zwischen Unterarm und Hand")
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

-- ---------- Ohne erkennbare Arme: Ärmel und Handschuhe wie bisher ----------
check(AvatarArms.ArmPieces(nil) == nil, "ohne Charakter: nil")
local stump = Instance.new("Model")
Instance.new("Humanoid", stump)
local fallback = ViewModel.new("Rifle", nil, Color3.new(0.2, 0.2, 0.2), nil, AvatarArms.ArmPieces(stump))
run(fallback, 0)
check(fallback.Model:FindFirstChild("LeftGlove") ~= nil and fallback.Model:FindFirstChild("RightFore") ~= nil,
	"ohne Arme: Ärmel und Handschuhe")

-- ---------- Waffen-Skin bleibt auf der Waffe ----------
local skinned = ViewModel.new("Rifle", Cosmetics.Get("W_Drachengold"), Color3.new(0, 0, 0), nil, AvatarArms.ArmPieces(body))
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

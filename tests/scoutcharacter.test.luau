-- Scout (AS_Scout) mit seinen echten Maßen (models/Agents/AS_Scout.rbxmx, Boden = Point_Root): als Charakter bewegen
-- sich Arme und Beine mit (R15-Gelenke: Laufen, Waffenhaltung), und in der Ego-Perspektive liegen seine Hände an der Waffe
local failures = 0
local function step(seconds)
	SIM.Run(SIM.Now + (seconds or 0.1))
end
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder", ReplicatedStorage)
assets.Name = "Assets"
local folder = assets:FindFirstChild("Agents") or Instance.new("Folder", assets)
folder.Name = "Agents"

local SCOUT = {
	{ "LowerTorso_Suit", Vector3.new(1.57, 0.66, 1.20), Vector3.new(0.01, 2.16, 0.03) },
	{ "Head_Suit", Vector3.new(1.45, 1.41, 1.56), Vector3.new(0.01, 4.52, -0.03) },
	{ "LeftFoot_Suit", Vector3.new(0.89, 0.69, 1.43), Vector3.new(-0.67, 0.37, -0.14) },
	{ "LeftHand_Suit", Vector3.new(0.83, 0.74, 0.87), Vector3.new(-1.24, 2.25, 0.09) },
	{ "LeftLowerArm_Suit", Vector3.new(0.87, 1.12, 0.91), Vector3.new(-1.19, 2.84, 0.08) },
	{ "LeftLowerLeg_Suit", Vector3.new(0.90, 1.07, 1.16), Vector3.new(-0.58, 0.87, -0.04) },
	{ "LeftUpperArm_Suit", Vector3.new(0.80, 1.08, 0.95), Vector3.new(-1.11, 3.30, 0.09) },
	{ "LeftUpperLeg_Suit", Vector3.new(0.95, 1.23, 1.08), Vector3.new(-0.44, 1.57, -0.09) },
	{ "RightFoot_Suit", Vector3.new(0.88, 0.68, 1.42), Vector3.new(0.61, 0.38, -0.16) },
	{ "RightHand_Suit", Vector3.new(0.81, 0.72, 0.85), Vector3.new(1.24, 2.27, -0.13) },
	{ "RightLowerArm_Suit", Vector3.new(0.84, 1.05, 0.92), Vector3.new(1.21, 2.75, -0.08) },
	{ "RightLowerLeg_Suit", Vector3.new(0.90, 1.12, 1.15), Vector3.new(0.53, 0.85, -0.07) },
	{ "RightUpperArm_Suit", Vector3.new(0.84, 1.00, 0.90), Vector3.new(1.12, 3.37, -0.01) },
	{ "RightUpperLeg_Suit", Vector3.new(0.97, 1.14, 1.07), Vector3.new(0.40, 1.62, -0.11) },
	{ "UpperTorso_Suit", Vector3.new(2.39, 1.78, 1.65), Vector3.new(0.01, 3.08, 0.04) }
}
local scout = Instance.new("Model")
scout.Name = "AS_Scout"
for _, def in SCOUT do
	local part = Instance.new("MeshPart")
	part.Name = def[1]
	part.Size = def[2]
	part.CFrame = CFrame.new(def[3])
	part.Parent = scout
end
local marker = Instance.new("Part")
marker.Name = "Point_Root"
marker.Size = Vector3.new(0.05, 0.05, 0.05)
marker.Parent = scout
scout.Parent = folder

local AgentModels = require("AgentModels")
local ViewModel = require("ViewModel")
local GunModels = require("GunModels")

local character = AgentModels.BuildCharacter("AS_Scout")
check(character ~= nil, "Scout als Charakter")
character:PivotTo(CFrame.new(-20, 3, 14) * CFrame.Angles(0, 0.9, 0))
character.Parent = workspace

-- Gelenke: jedes Teil hängt an seinem Körperteil, und jedes Körperteil über R15-Gelenke am HumanoidRootPart (Roblox
-- bewegt sie beim Laufen, die Waffenhaltung hebt die Arme)
for _, def in SCOUT do
	local part = character.AgentModel:FindFirstChild(def[1])
	local bodyName = string.match(def[1], "^[^_]+")
	local weld = part and part:FindFirstChildOfClass("WeldConstraint")
	check(weld and weld.Part0 == character:FindFirstChild(bodyName), def[1] .. ": hängt an " .. bodyName)
	-- Kette bis zum HumanoidRootPart
	local body, hops = character:FindFirstChild(bodyName), 0
	while body and body.Name ~= "HumanoidRootPart" and hops < 6 do
		local motor = body:FindFirstChildOfClass("Motor6D")
		body = motor and motor.Part1 == body and motor.Part0 or nil
		hops += 1
	end
	check(body and body.Name == "HumanoidRootPart", bodyName .. ": über Gelenke am HumanoidRootPart")
end
local function jointPoint(motor)
	return (motor.Part0.CFrame * motor.C0).Position, (motor.Part1.CFrame * motor.C1).Position
end
for _, motor in character:GetDescendants() do
	if motor:IsA("Motor6D") then
		local a, b = jointPoint(motor)
		check((a - b).Magnitude < 1e-3, motor.Name .. ": Gelenk passt in Ruhelage (nichts springt)")
	end
end

-- Ego-Perspektive: Hände des Scouts an der Waffe
local arms = AgentModels.ArmPieces(character)
check(arms ~= nil and #arms.Right.Pieces == 3 and #arms.Left.Pieces == 3, "Arme des Scouts gefunden")
check(arms and (arms.Right.Pieces[1].Part.Size - Vector3.new(0.84, 1, 0.9)).Magnitude < 0.2 or false,
	"Ego-Arme sind die Teile des Scouts")
local camera = CFrame.new(5, 8, -3) * CFrame.Angles(0.1, 2.2, 0)
for _, weaponName in { "Rifle", "SMG", "Pistol" } do
	local vm = ViewModel.new(weaponName, nil, Color3.new(0, 0, 0), nil, AgentModels.ArmPieces(character))
	for _, aim in { 0, 1 } do
		vm.DrawStart = os.clock() - 5
		for _ = 1, 3 do
			vm:Update(1 / 60, { Camera = camera, Aim = aim, Sprinting = false, Speed = 0 })
		end
		local hands = {}
		for _, part in vm.Model:GetChildren() do
			if part:IsA("BasePart") and string.match(part.Name, "^%a+Hand_%d+$") then
				hands[string.sub(part.Name, 1, 4)] = part
			end
		end
		local info = GunModels.Info[weaponName]
		local grip = vm.GunWorld.Position
		local guard = vm.GunWorld * (info.LeftHand * ViewModel.Scale())
		local r = hands.Righ and (hands.Righ.Position - grip).Magnitude or math.huge
		local l = hands.Left and (hands.Left.Position - guard).Magnitude or math.huge
		print(string.format("HINWEIS %s Zielen %d: rechte Hand %.2f vom Griff, linke %.2f vom Handschutz", weaponName, aim, r, l))
		check(r < 0.35, weaponName .. ": rechte Hand des Scouts am Griff (" .. r .. ")")
		if aim == 0 then
			check(l < 0.35, weaponName .. ": linke Hand des Scouts an der Waffe (" .. l .. ")")
		end
	end
	vm:Destroy()
end

if failures == 0 then
	print("OK: Scout")
end

--!expose BotService rigTemplate
--!expose WeaponService validClaim
-- Agenten-Körper: Spieler spawnen überall als Agent mit derselben Körper-Beschreibung wie Bots (gleiche Trefferzonen),
-- der eigene Avatar (Kleidung, Accessoires) ist weg. Ohne 3D-Modell: Roblox-Standard-Look in den Agentenfarben (Gesicht
-- bleibt, keine Quader-Ausrüstung). Accessoires sind nie Trefferzone – auch später angehängte, auch nicht über einen
-- vom Client gemeldeten Treffer.
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

game.JobId = "server-1"
SIM.DataStore("PlayerData_v1")
local AgentConfig = require("AgentConfig")
local Cosmetics = require("Cosmetics")
local AgentBody = require("AgentBody")

-- ---------- Beschreibung: feste Maße, nur die Farben unterscheiden sich ----------
local primary = Color3.fromRGB(40, 60, 50)
local description = AgentBody.Description(primary)
check(description.WidthScale == AgentConfig.BodyScale.Width and description.DepthScale == AgentConfig.BodyScale.Depth,
	"schlank wie AgentConfig.BodyScale")
check(description.HeightScale == 1 and description.HeadScale == 1 and description.BodyTypeScale == 0
	and description.ProportionScale == 0, "Standard-Größe, klassische R15-Proportionen (kein Rthro)")
check(description.TorsoColor == primary and description.LeftArmColor == primary and description.RightArmColor == primary,
	"Uniform in der Agentenfarbe")
check(description.LeftLegColor == AgentBody.PantsColor(primary), "Hose abgedunkelt")

-- ---------- Accessoires: nie Trefferzone, auch später angehängte ----------
local function rig()
	local model = Instance.new("Model")
	model.Name = "Avatar"
	Instance.new("Humanoid", model)
	local function part(name, size, position)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(position)
		p.Parent = model
		return p
	end
	part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
	part("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0))
	part("UpperTorso", Vector3.new(1.5, 1.6, 0.8), Vector3.new(0, 3.4, 0))
	part("LowerTorso", Vector3.new(1.5, 0.4, 0.8), Vector3.new(0, 2.4, 0))
	part("LeftUpperArm", Vector3.new(0.75, 1.2, 0.8), Vector3.new(-1.1, 3.6, 0))
	part("RightUpperArm", Vector3.new(0.75, 1.2, 0.8), Vector3.new(1.1, 3.6, 0))
	model.Parent = workspace
	return model
end
local function accessory(parent, name)
	local acc = Instance.new("Accessory")
	acc.Name = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(2, 1, 2)
	handle.Parent = acc
	acc.Parent = parent
	return acc, handle
end

local avatar = rig()
local hat, hatHandle = accessory(avatar, "BigHat")
AgentBody.Protect(avatar)
check(hatHandle.CanQuery == false and hatHandle.CanTouch == false, "Hut ist nicht treffbar")
check(avatar.Head.CanQuery == true and avatar.UpperTorso.CanQuery == true, "Körperteile bleiben treffbar")
local _, wingHandle = accessory(avatar, "Wings")
check(wingHandle.CanQuery == false, "später angehängte Flügel sind auch nicht treffbar")

-- ---------- Anziehen: Avatar weg, Roblox-Standard-Look in den Agentenfarben ----------
local shirt = Instance.new("Shirt", avatar)
local face = Instance.new("Decal", avatar.Head)
face.Name = "face"
AgentBody.Dress(avatar, primary)
check(hat.Parent == nil and shirt.Parent == nil, "Accessoires und Kleidung des eigenen Avatars entfernt")
check(avatar:FindFirstChildOfClass("Accessory") == nil, "keine Accessoires mehr")
check(face.Parent == avatar.Head and face.Transparency == 0, "Roblox-Gesicht bleibt")
check(avatar:GetAttribute("AgentLook") == "Standard", "Standard-Look (kein Modell)")
local gearCount = 0
for _, child in avatar:GetDescendants() do
	if child:GetAttribute("AgentGear") then
		gearCount += 1
	end
end
check(gearCount == 0, "keine Ausrüstung (keine Quader mehr)")
local colors = avatar:FindFirstChildOfClass("BodyColors")
check(colors ~= nil and colors.TorsoColor3 == primary and colors.LeftArmColor3 == primary
	and colors.HeadColor3 == AgentBody.SkinColor and colors.LeftLegColor3 == AgentBody.PantsColor(primary),
	"Körperfarben: Haut, Uniform, Hose")
for _, name in { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm" } do
	check(avatar[name].Transparency == 0, name .. ": sichtbar")
end
-- Ausrüstung von früher (z.B. Quader einer älteren Version) verschwindet beim Anziehen
local leftover = Instance.new("Part")
leftover.Name = "AgentVest"
leftover:SetAttribute("AgentGear", true)
leftover.Parent = avatar
AgentBody.Dress(avatar, primary)
check(leftover.Parent == nil, "alte Ausrüstung entfernt")
-- War vorher ein ganzer Charakter angezogen (Kopf und Gesicht unsichtbar), ist beides danach wieder da
face.Transparency = 1
avatar.Head.Transparency = 1
AgentBody.Dress(avatar, primary)
check(face.Transparency == 0 and avatar.Head.Transparency == 0, "Kopf und Gesicht wieder sichtbar")

-- ---------- Gemeldete Treffer: nur Körperteile ----------
local WeaponService = require("WeaponService")
local WeaponConfig = require("WeaponConfig")
local shooter = rig()
shooter:PivotTo(CFrame.new(0, 0, 30))
local target = rig()
target.Humanoid.Health = 100
local hat2, hatHandle2 = accessory(target, "Hat")
hatHandle2.CFrame = target.Head.CFrame * CFrame.new(0, 0.9, 0)
AgentBody.Dress(target, primary)
check(hat2.Parent == nil, "Ziel als Agent angezogen")
local _, lateHandle = accessory(target, "LateHat") -- z.B. von einem Skript nachträglich angehängt
lateHandle.CFrame = target.Head.CFrame * CFrame.new(0, 0.9, 0)
local origin = shooter.Head.Position
local function claim(part)
	local direction = (part.Position - origin).Unit
	return WeaponService.__validClaim(shooter, origin, direction, WeaponConfig.Weapons.Rifle,
		{ Part = part, Position = part.Position })
end
check(claim(target.Head) == target.Head, "Kopftreffer zählt")
check(claim(lateHandle) == nil, "Treffer auf ein Accessoire zählt nicht")
shooter:Destroy()
target:Destroy()
avatar:Destroy()

-- ---------- Spieler spawnen als Agent ----------
local AgentService = require("AgentService")
local SpawnUtil = require("SpawnUtil")
AgentService.Init()
local alice = SIM.Join("Alice")
step(1)
alice:SetAttribute("Mode", "Hub")
alice:SetAttribute("Agent", "Viper")
local character = SpawnUtil.Spawn(alice, CFrame.new(10, 5, 10))
step(0.5)
local loaded = character and SIM.DescriptionOf[character]
local vPrimary = Cosmetics.AgentColors(alice, "Viper")
check(loaded ~= nil, "Spieler mit Agenten-Körper geladen (nicht mit dem eigenen Avatar)")
check(loaded and loaded.TorsoColor == vPrimary and loaded.WidthScale == AgentConfig.BodyScale.Width,
	"Körper in Viper-Farben, schlank")
check(character and character:GetAttribute("AgentLook") == "Standard" and character:FindFirstChild("AgentVest") == nil,
	"Standard-Look auch im Hub (Agent überall), ohne Quader")
check(character and character.Head:FindFirstChildOfClass("Decal") ~= nil, "mit Roblox-Gesicht")

-- Agentenwechsel im Hub: sofort in den neuen Farben
alice:SetAttribute("Agent", "Bastion")
step(0.1)
local bPrimary = Cosmetics.AgentColors(alice, "Bastion")
check(character.BodyColors.TorsoColor3 == bPrimary and character:GetAttribute("AgentLookOf") == "Bastion",
	"Agentenwechsel im Hub sofort")
-- Im Match erst beim nächsten Spawn
alice:SetAttribute("Mode", "FreeForAll")
alice:SetAttribute("Agent", "Viper")
step(0.1)
check(character:GetAttribute("AgentLookOf") == "Bastion", "im Match ändert sich der Look erst beim nächsten Spawn")
character = SpawnUtil.Spawn(alice, CFrame.new(0, 5, 0))
step(0.5)
check(character and character:GetAttribute("AgentLookOf") == "Viper" and character.BodyColors.TorsoColor3 == vPrimary,
	"nächster Spawn als Viper")

-- Kann der Agenten-Körper nicht geladen werden: normaler Charakter, aber trotzdem als Agent angezogen
SIM.Quiet = true
SIM.FailDescriptionLoad = true
character = SpawnUtil.Spawn(alice, CFrame.new(0, 5, 0))
step(0.5)
SIM.FailDescriptionLoad = false
SIM.Quiet = false
check(character ~= nil and SIM.DescriptionOf[character] == nil, "Rückfall auf den normalen Charakter")
check(character and character:GetAttribute("AgentLook") == "Standard" and character:GetAttribute("AgentLookOf") == "Viper",
	"auch dann als Agent angezogen")

-- ---------- Bots: derselbe Körper wie Spieler mit diesem Agenten ----------
local BotService = require("BotService")
local viper = AgentConfig.Get("Viper")
local template
task.spawn(function()
	template = BotService.__rigTemplate(viper)
end)
step(1)
local botDescription = template and SIM.DescriptionOf[template]
check(botDescription ~= nil, "Bot-Körper aus einer Beschreibung gebaut")
if botDescription and loaded then
	for _, key in { "WidthScale", "DepthScale", "HeightScale", "HeadScale", "BodyTypeScale", "ProportionScale" } do
		check(botDescription[key] == loaded[key], "Bot und Spieler gleich: " .. key)
	end
	local defaultPrimary = Cosmetics.AgentColors(nil, "Viper")
	check(botDescription.TorsoColor == defaultPrimary, "Bot in den Standardfarben seines Agenten (nicht in Teamfarbe)")
	check(template:GetAttribute("AgentLook") == "Standard" and template.BodyColors.TorsoColor3 == defaultPrimary,
		"Bot im selben Standard-Look")
end
local again
task.spawn(function()
	again = BotService.__rigTemplate(viper)
end)
step(0.2)
check(again == template, "Vorlage pro Agent nur einmal gebaut")

if failures == 0 then
	print("Agenten-Körper: alles in Ordnung")
end

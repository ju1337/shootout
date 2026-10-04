--!expose BotService rigTemplate
--!expose WeaponService validClaim
-- Agenten-Körper (bis die Agenten-Modelle aus Blender da sind): Spieler spawnen überall als Agent mit derselben
-- Körper-Beschreibung wie Bots (gleiche Trefferzonen), der eigene Avatar (Kleidung, Accessoires, Gesicht) ist weg,
-- Ausrüstung in Agentenfarben bzw. Skin. Accessoires und Ausrüstung sind nie Trefferzone – auch später angehängte,
-- auch nicht über einen vom Client gemeldeten Treffer.
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
local HttpService = game:GetService("HttpService")
local AgentConfig = require("AgentConfig")
local Cosmetics = require("Cosmetics")
local AgentBody = require("AgentBody")

-- ---------- Beschreibung: feste Maße, nur die Farben unterscheiden sich ----------
local primary, accent = Color3.fromRGB(40, 60, 50), Color3.fromRGB(90, 160, 110)
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

-- ---------- Anziehen: Avatar weg, Ausrüstung dran, Farben ----------
local shirt = Instance.new("Shirt", avatar)
local face = Instance.new("Decal", avatar.Head)
face.Name = "face"
AgentBody.Dress(avatar, primary, accent)
check(hat.Parent == nil and shirt.Parent == nil and face.Parent == nil, "Accessoires, Kleidung und Gesicht entfernt")
check(avatar:FindFirstChildOfClass("Accessory") == nil, "keine Accessoires mehr")
for _, name in AgentBody.GearNames do
	local gear = avatar:FindFirstChild(name)
	check(gear ~= nil, "Ausrüstung " .. name)
	if gear then
		check(gear.CanQuery == false and gear.CanCollide == false and gear.CanTouch == false and gear.Massless == true,
			name .. ": kein Teil der Trefferzone, ohne Kollision und Gewicht")
		local weld = gear:FindFirstChildOfClass("WeldConstraint")
		check(weld ~= nil and weld.Part1 == gear and weld.Part0 ~= nil and weld.Part0.Parent == avatar,
			name .. ": am Körperteil festgeschweißt")
	end
end
check(avatar.AgentVest.Color == accent and avatar.AgentHoodTop.Color == primary
	and avatar.AgentVisor.Color == AgentBody.VisorColor(accent), "Ausrüstung in Agentenfarben")
check(avatar.AgentVisor.Material == Enum.Material.SmoothPlastic and avatar.AgentVisor.Reflectance > 0,
	"Visier dunkel und glänzend (kein Glas, das im Hub hell wirkt)")
local colors = avatar:FindFirstChildOfClass("BodyColors")
check(colors ~= nil and colors.TorsoColor3 == primary and colors.HeadColor3 == AgentBody.SkinColor, "Körperfarben")
-- Lage: Visier über den Augen (etwas über der Kopfmitte), Maske über Mund und Kinn, beide vorne im Gesicht;
-- Kapuze als offener Rahmen (oben, hinten, seitlich), vorne frei; Weste am Oberkörper
local head = avatar.Head
local function headLocal(part)
	return head.CFrame:PointToObjectSpace(part.Position)
end
local visorLocal, maskLocal = headLocal(avatar.AgentVisor), headLocal(avatar.AgentMask)
-- Augen des Standard-Kopfs liegen etwa 0,2 bis 0,25 Kopfhöhen über der Mitte: das Visier muss sie abdecken
local visorTop = visorLocal.Y + avatar.AgentVisor.Size.Y / 2
local visorBottom = visorLocal.Y - avatar.AgentVisor.Size.Y / 2
check(visorLocal.Z < -head.Size.Z * 0.45 and visorTop >= head.Size.Y * 0.25 and visorBottom <= head.Size.Y * 0.15,
	string.format("Visier vorne über den Augen (%.2f bis %.2f Kopfhöhen)", visorBottom / head.Size.Y, visorTop / head.Size.Y))
check(maskLocal.Z < -head.Size.Z * 0.45 and maskLocal.Y < 0 and maskLocal.Y - avatar.AgentMask.Size.Y / 2 > -head.Size.Y / 2,
	"Maske unten im Gesicht, nicht unter dem Kinn")
check(visorLocal.Y - avatar.AgentVisor.Size.Y / 2 > maskLocal.Y + avatar.AgentMask.Size.Y / 2 - 0.05,
	"Visier und Maske überdecken sich nicht")
check(headLocal(avatar.AgentHoodTop).Y > head.Size.Y / 2 and headLocal(avatar.AgentHoodBack).Z > head.Size.Z / 2
	and headLocal(avatar.AgentHoodLeft).X < -head.Size.X / 2 and headLocal(avatar.AgentHoodRight).X > head.Size.X / 2,
	"Kapuze oben, hinten und seitlich um den Kopf")
for _, name in { "AgentHoodTop", "AgentHoodBack", "AgentHoodLeft", "AgentHoodRight" } do
	local part = avatar[name]
	local front = headLocal(part).Z - part.Size.Z / 2
	check(front > -head.Size.Z / 2 - 0.05, name .. ": Gesicht bleibt frei (nichts vor dem Gesicht)")
end
check((avatar.AgentVest.Position - avatar.UpperTorso.Position).Magnitude < 0.5, "Weste am Oberkörper")
-- Gesicht: auch ein später angehängtes Decal (Roblox lädt das Aussehen teils nach) verschwindet
local lateFace = Instance.new("Decal")
lateFace.Name = "face"
lateFace.Parent = head
step(0.1)
check(lateFace.Parent == nil and head:FindFirstChildOfClass("Decal") == nil, "nachträglich angehängtes Gesicht entfernt")
-- nochmal anziehen (anderer Skin): nichts doppelt, nur umgefärbt
local accent2 = Color3.fromRGB(200, 40, 40)
AgentBody.Dress(avatar, primary, accent2)
local vests = 0
for _, child in avatar:GetChildren() do
	if child.Name == "AgentVest" then
		vests += 1
	end
end
check(vests == 1 and avatar.AgentVest.Color == accent2, "erneutes Anziehen: nichts doppelt, neue Farbe")
-- Wird der Kopf größer (z.B. Skalierung nach dem Laden), passt sich die Ausrüstung beim nächsten Anziehen an
head.Size = head.Size * 1.25
AgentBody.Dress(avatar, primary, accent2)
check(math.abs(avatar.AgentVisor.Size.X - head.Size.X * 0.94) < 1e-6, "Ausrüstung an neue Kopfgröße angepasst")
local weldCount = 0
for _, child in avatar.AgentVisor:GetChildren() do
	if child:IsA("WeldConstraint") then
		weldCount += 1
	end
end
check(weldCount == 1, "genau eine Schweißnaht pro Ausrüstungsteil")

-- ---------- Gemeldete Treffer: nur Körperteile ----------
local WeaponService = require("WeaponService")
local WeaponConfig = require("WeaponConfig")
local shooter = rig()
shooter:PivotTo(CFrame.new(0, 0, 30))
local target = rig()
target.Humanoid.Health = 100
local hat2, hatHandle2 = accessory(target, "Hat")
hatHandle2.CFrame = target.Head.CFrame * CFrame.new(0, 0.9, 0)
AgentBody.Dress(target, primary, accent)
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
check(claim(target.AgentHoodTop) == nil and claim(target.AgentVest) == nil, "Treffer auf die Ausrüstung zählt nicht")
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
local vPrimary, vAccent = Cosmetics.AgentColors(alice, "Viper")
check(loaded ~= nil, "Spieler mit Agenten-Körper geladen (nicht mit dem eigenen Avatar)")
check(loaded and loaded.TorsoColor == vPrimary and loaded.WidthScale == AgentConfig.BodyScale.Width,
	"Körper in Viper-Farben, schlank")
check(character and character:FindFirstChild("AgentVisor") and character.AgentVest.Color == vAccent,
	"Ausrüstung auch im Hub (Agent überall)")

-- Skin-Wechsel im Hub: sofort sichtbar
local skin = Cosmetics.Get("A_Viper_Nacht")
alice:SetAttribute("Owned", HttpService:JSONEncode({ A_Viper_Nacht = 1 }))
alice:SetAttribute("Equipped", HttpService:JSONEncode({ ["A:Viper"] = "A_Viper_Nacht" }))
step(0.1)
check(character.AgentVest.Color == skin.Accent and character.AgentHoodTop.Color == skin.Primary,
	"Skin im Hub sofort angezogen")
-- Im Match erst beim nächsten Spawn
alice:SetAttribute("Mode", "FreeForAll")
alice:SetAttribute("Equipped", HttpService:JSONEncode({}))
step(0.1)
check(character.AgentVest.Color == skin.Accent, "im Match ändert sich der Look erst beim nächsten Spawn")
character = SpawnUtil.Spawn(alice, CFrame.new(0, 5, 0))
step(0.5)
check(character and character.AgentVest.Color == vAccent, "nächster Spawn ohne Skin")

-- Kann der Agenten-Körper nicht geladen werden: normaler Charakter, aber trotzdem als Agent angezogen
SIM.Quiet = true
SIM.FailDescriptionLoad = true
character = SpawnUtil.Spawn(alice, CFrame.new(0, 5, 0))
step(0.5)
SIM.FailDescriptionLoad = false
SIM.Quiet = false
check(character ~= nil and SIM.DescriptionOf[character] == nil, "Rückfall auf den normalen Charakter")
check(character and character:FindFirstChild("AgentVisor") ~= nil, "auch dann als Agent angezogen")

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
	local defaultPrimary, defaultAccent = Cosmetics.AgentColors(nil, "Viper")
	check(botDescription.TorsoColor == defaultPrimary, "Bot in den Standardfarben seines Agenten (nicht in Teamfarbe)")
	check(template:FindFirstChild("AgentVest") and template.AgentVest.Color == defaultAccent, "Bot trägt dieselbe Ausrüstung")
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

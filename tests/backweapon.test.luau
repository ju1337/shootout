-- BackWeapon: im Hub hängt die Standardwaffe des aktiven Agenten am Rücken, folgt Agent, Waffenwahl und Skin und
-- verschwindet in den Kampfmodi und beim Tod.
local BackWeapon = require("BackWeapon")
local AgentConfig = require("AgentConfig")
local GunModels = require("GunModels")
local Cosmetics = require("Cosmetics")
local HttpService = game:GetService("HttpService")

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step()
	SIM.Run(SIM.Now + 0.1)
end

BackWeapon.Init()
local player = SIM.AddPlayer("Spieler")
player:SetAttribute("Mode", "Hub")
player:SetAttribute("Agent", "Viper")
player:LoadCharacter()
local character = player.Character
-- Oberkörper wie beim schlanken R15-Avatar (Breite 75 %, Tiefe 80 %), Charakter gedreht irgendwo im Hub
local torso = character.UpperTorso
torso.Size = Vector3.new(1.5, 1.6, 0.8)
character:PivotTo(CFrame.new(40, 6, -25) * CFrame.Angles(0, math.rad(130), 0))
step()

local builds = 0
character.ChildAdded:Connect(function(child)
	if child.Name == BackWeapon.Name then
		builds += 1
	end
end)

local function backWeapon()
	return character:FindFirstChild(BackWeapon.Name)
end

-- Lage prüfen: alles hinter dem Rücken, Lauf oben rechts, Waffe mittig, an diesem Oberkörper festgeschweißt
local function checkPlacement(weapon, label)
	local model = backWeapon()
	check(model ~= nil and model:GetAttribute("Weapon") == weapon, label .. ": " .. weapon .. " auf dem Rücken, war "
		.. tostring(model and model:GetAttribute("Weapon")))
	if not model then
		return
	end
	local back = torso.Size.Z / 2
	local minZ, lowX, highX, lowY, highY = math.huge, math.huge, -math.huge, math.huge, -math.huge
	local muzzleY, stockY, muzzleX, stockX
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local weld = part:FindFirstChild("BackWeld")
			check(weld ~= nil and weld.Part0 == torso and weld.Part1 == part, label .. ": " .. part.Name .. " nicht am Oberkörper")
			check(part.Massless and not part.CanCollide and not part.CanQuery and not part.Anchored,
				label .. ": " .. part.Name .. " stört die Physik")
			local rel = torso.CFrame:ToObjectSpace(part.CFrame)
			if part.Transparency < 1 then
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local corner = rel * (part.Size / 2 * Vector3.new(sx, sy, sz))
							minZ = math.min(minZ, corner.Z)
							lowX, highX = math.min(lowX, corner.X), math.max(highX, corner.X)
							lowY, highY = math.min(lowY, corner.Y), math.max(highY, corner.Y)
						end
					end
				end
			end
			if part.Name == "Handle" then
				-- Mündung und Schaft der Waffe im Oberkörper-Raum
				local info = GunModels.Info[weapon]
				local muzzle = rel * (info.Muzzle * 0.8)
				local stock = rel * ((info.Stock or Vector3.new(0, 0, 0.5)) * 0.8)
				muzzleY, stockY, muzzleX, stockX = muzzle.Y, stock.Y, muzzle.X, stock.X
			end
		end
	end
	check(minZ >= back - 1e-3, string.format("%s: Waffe ragt in den Rücken (z %.2f < %.2f)", label, minZ, back))
	check(minZ <= back + 0.2, string.format("%s: Waffe steht vom Rücken ab (z %.2f)", label, minZ))
	check(math.abs((lowX + highX) / 2) < 0.25 and math.abs((lowY + highY) / 2) < 0.25,
		string.format("%s: Waffe nicht mittig (%.2f, %.2f)", label, (lowX + highX) / 2, (lowY + highY) / 2))
	check(muzzleY and muzzleY > stockY + 1 and muzzleX > stockX, label .. ": Lauf zeigt nicht schräg nach oben rechts")
	local tilt = muzzleY and math.deg(math.atan2(muzzleX - stockX, muzzleY - stockY)) or 0
	check(tilt > 30 and tilt < 50, string.format("%s: Lauf %.0f° aus der Senkrechten", label, tilt))
	check(highY < 2.2, string.format("%s: Waffe ragt über den Kopf (%.2f)", label, highY))
	check((model.PrimaryPart.Position - (torso.CFrame * torso.CFrame:ToObjectSpace(model.PrimaryPart.CFrame)).Position).Magnitude < 1e-6,
		label .. ": Griff nicht dort, wo der Weld ihn hinsetzt")
end

-- 1) Standard: Viper trägt ihre erste Primärwaffe
checkPlacement(AgentConfig.LoadoutFor(player, "Viper")[1], "Standard")

-- 2) Andere Waffe gewählt (AGENTEN-Seite)
builds = 0
player:SetAttribute("Loadouts", HttpService:JSONEncode({ Viper = "Rifle" }))
step()
checkPlacement("Rifle", "Waffenwahl")
check(builds == 1, "Waffenwahl: einmal neu gebaut, waren " .. builds)

-- 3) Gleichzeitige Änderungen ergeben nur einen Neubau; unveränderter Stand baut nicht neu
builds = 0
player:SetAttribute("Agent", "Bastion")
player:SetAttribute("Loadouts", HttpService:JSONEncode({ Viper = "Rifle", Bastion = "SMG" }))
player:SetAttribute("Coins", 500)
step()
checkPlacement("SMG", "Agentenwechsel")
check(builds == 1, "mehrere Änderungen auf einmal: ein Neubau, waren " .. builds)
builds = 0
player:SetAttribute("Coins", 600)
player:SetAttribute("Loadouts", HttpService:JSONEncode({ Viper = "Rifle", Bastion = "SMG", Hawk = "DMR" }))
step()
check(builds == 0, "ohne sichtbare Änderung kein Neubau, waren " .. builds)

-- 4) Skin ausgerüstet: Waffe auf dem Rücken trägt ihn
local skin
for _, item in Cosmetics.Items do
	if item.Type == "Weapon" and Cosmetics.FitsWeapon(item, "SMG") and item.Color then
		skin = item
		break
	end
end
player:SetAttribute("Owned", HttpService:JSONEncode({ [skin.Id] = true }))
player:SetAttribute("Equipped", HttpService:JSONEncode({ ["W:SMG"] = skin.Id }))
step()
local skinned = false
for _, part in backWeapon():GetDescendants() do
	if part:IsA("BasePart") and part.Color == skin.Color then
		skinned = true
	end
end
check(skinned, "Skin " .. skin.Name .. " auf der Rückenwaffe")

-- 5) Alle Primärwaffen aller Agenten liegen richtig
for _, agent in AgentConfig.Agents do
	for _, weapon in agent.Primaries do
		player:SetAttribute("Agent", agent.Id)
		player:SetAttribute("Loadouts", HttpService:JSONEncode({ [agent.Id] = weapon }))
		step()
		checkPlacement(weapon, agent.Name)
	end
end

-- 6) Körper ändert sich (Skalierung, neuer Oberkörper nach dem Laden des Aussehens)
torso.Size = Vector3.new(2, 1.6, 1)
step()
checkPlacement(AgentConfig.LoadoutFor(player, player:GetAttribute("Agent"))[1], "breiterer Oberkörper")
local oldTorso = torso
torso = Instance.new("Part")
torso.Name = "UpperTorso"
torso.Size = Vector3.new(1.5, 1.6, 0.8)
torso.CFrame = oldTorso.CFrame
oldTorso:Destroy()
torso.Parent = character
step()
checkPlacement(AgentConfig.LoadoutFor(player, player:GetAttribute("Agent"))[1], "neuer Oberkörper")

-- 7) Kampfmodus: keine Rückenwaffe; zurück im Hub wieder da
player:SetAttribute("Mode", "FreeForAll")
step()
check(backWeapon() == nil, "im Kampfmodus keine Rückenwaffe")
player:SetAttribute("Mode", "Hub")
step()
check(backWeapon() ~= nil, "zurück im Hub wieder auf dem Rücken")

-- 8) Tod: Waffe weg
character:FindFirstChildOfClass("Humanoid").Health = 0
step()
check(backWeapon() == nil, "tot: keine Rückenwaffe")

-- 9) Neuer Charakter im Hub (Respawn)
player:LoadCharacter()
character = player.Character
torso = character.UpperTorso
step()
check(backWeapon() ~= nil and backWeapon():FindFirstChildWhichIsA("Weld", true).Part0 == torso, "nach dem Respawn wieder da")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

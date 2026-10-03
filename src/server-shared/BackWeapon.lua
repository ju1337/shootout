-- BackWeapon (ModuleScript, nur Server)
-- Im Hub (und im Markt) trägt jeder Spieler die Standardwaffe seines aktiven Agenten (AGENTEN-Seite: eine der zwei Primärwaffen)
-- auf dem Rücken: flach am Rücken, Lauf schräg nach oben über die rechte Schulter, mit ausgerüstetem Skin und
-- Aufsätzen. Wechselt der Spieler im Menü Agent, Waffe, Skin oder Aufsätze, hängt sofort die neue Waffe dort.
-- In den Kampfmodi hält man die Waffen in der Hand (WeaponService), dann gibt es keine Rückenwaffe.
-- Die Teile hängen über Welds am Oberkörper (UpperTorso bzw. Torso bei R6), sind masselos und ohne Kollision.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AgentConfig = require(Shared.AgentConfig)
local GunModels = require(Shared.GunModels)
local Cosmetics = require(Shared.Cosmetics)
local AttachmentConfig = require(Shared.AttachmentConfig)
local Modes = require(Shared.Modes)

local BackWeapon = {}

BackWeapon.Name = "BackWeapon"
local SCALE = 0.8          -- etwas kleiner als in der Hand (GunModels.ToolScale), damit der Lauf nicht über den Kopf ragt
local TILT = math.rad(40)  -- Lauf um so viel aus der Senkrechten zur rechten Schulter geneigt
local GAP = 0.06           -- Abstand zwischen Rücken und Waffe (Studs)
-- Spieler-Attribute, bei deren Änderung die Waffe neu gebaut wird
local WATCHED = { Mode = true, Agent = true, Loadouts = true, Equipped = true, Owned = true, Attachments = true }

local pending = {} -- [Player] = true, solange ein Neubau ansteht (mehrere Auslöser im selben Moment = ein Neubau)

local function torsoOf(character)
	return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
end

-- Achsenparallele Hülle aller sichtbaren Teile im Raum des Griffs (Ursprung des Waffenmodells)
local function bounds(model, handle)
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local cf = handle.CFrame:ToObjectSpace(part.CFrame)
			local half = part.Size / 2
			local extent = Vector3.new(
				math.abs(cf.RightVector.X) * half.X + math.abs(cf.UpVector.X) * half.Y + math.abs(cf.LookVector.X) * half.Z,
				math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z,
				math.abs(cf.RightVector.Z) * half.X + math.abs(cf.UpVector.Z) * half.Y + math.abs(cf.LookVector.Z) * half.Z)
			low = low:Min(cf.Position - extent)
			high = high:Max(cf.Position + extent)
		end
	end
	return low, high
end

-- Lage der Waffe (Griffpunkt) im Raum des Oberkörpers. low/high = Hülle der Waffe im Griff-Raum, torsoSize = Größe
-- des Oberkörpers. Der Charakter schaut nach -Z, der Rücken ist +Z: Die Waffe liegt mit der Seite am Rücken, ihre
-- Mitte hinter der Mitte des Oberkörpers, der Lauf (-Z der Waffe) zeigt schräg nach oben zur rechten Schulter (+X).
function BackWeapon.Placement(low, high, torsoSize)
	local rotation = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(-math.cos(TILT), math.sin(TILT), 0))
	local center = (low + high) / 2
	local depth = torsoSize.Z / 2 + (high.X - low.X) / 2 + GAP
	return CFrame.new(0, 0, depth) * rotation * CFrame.new(-center)
end

-- Welche Waffe gehört auf den Rücken? (nil = keine). Dazu ein Schlüssel, der sich bei jeder sichtbaren Änderung ändert.
local function wanted(player, character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local torso = character and torsoOf(character)
	if not Modes.IsSocial(player:GetAttribute("Mode")) or not humanoid or humanoid.Health <= 0 or not torso then
		return nil
	end
	local agent = AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
	local weapon = AgentConfig.LoadoutFor(player, agent.Id)[1]
	if not GunModels.Info[weapon] then
		return nil
	end
	local skin = Cosmetics.WeaponSkin(player, agent.Id, weapon)
	local attachments = AttachmentConfig.EquippedList(player, weapon)
	local key = table.concat({ weapon, tostring(skin and (skin.Id or skin.Name)), table.concat(attachments, ","),
		tostring(torso.Size) }, "|")
	return { Weapon = weapon, Skin = skin, Attachments = attachments, Torso = torso, Key = key }
end

-- Waffe bauen und am Oberkörper festschweißen
local function attach(character, info)
	local model = GunModels.Build(info.Weapon, info.Skin, info.Attachments)
	model:ScaleTo(SCALE)
	local handle = model.PrimaryPart
	local low, high = bounds(model, handle)
	local placement = BackWeapon.Placement(low, high, info.Torso.Size)
	local torso = info.Torso
	local origin = handle.CFrame -- vor der Schleife merken: der Griff wird darin selbst versetzt
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local offset = placement * origin:ToObjectSpace(part.CFrame)
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local weld = Instance.new("Weld")
			weld.Name = "BackWeld"
			weld.Part0 = torso
			weld.Part1 = part
			weld.C0 = offset
			weld.Parent = part
			part.CFrame = torso.CFrame * offset
		end
	end
	model.Name = BackWeapon.Name
	model:SetAttribute("Key", info.Key)
	model:SetAttribute("Weapon", info.Weapon)
	model.Parent = character
	return model
end

-- Rückenwaffe des Spielers an den aktuellen Stand anpassen (neu bauen, entfernen oder lassen)
function BackWeapon.Update(player)
	local character = player.Character
	if not character then
		return
	end
	local info = wanted(player, character)
	local current = character:FindFirstChild(BackWeapon.Name)
	if current then
		local weld = current:FindFirstChildWhichIsA("Weld", true)
		local intact = weld and weld.Part0 == (info and info.Torso)
		if info and intact and current:GetAttribute("Key") == info.Key then
			return -- hängt schon richtig
		end
		current:Destroy()
	end
	if info then
		attach(character, info)
	end
end

-- Neubau etwas verzögert: mehrere Auslöser im selben Moment (Attribute, neuer Körper) ergeben nur einen
local function schedule(player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		if player.Parent then
			BackWeapon.Update(player)
		end
	end)
end

local function watchCharacter(player, character)
	schedule(player)
	-- Avatar-Aussehen und Körperbau kommen teils erst nach dem Spawn: Oberkörper neu oder anders groß
	character.ChildAdded:Connect(function(child)
		if child.Name == "UpperTorso" or child.Name == "Torso" then
			schedule(player)
		end
	end)
	for _, name in { "UpperTorso", "Torso" } do
		local torso = character:FindFirstChild(name)
		if torso then
			torso:GetPropertyChangedSignal("Size"):Connect(function()
				schedule(player)
			end)
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			schedule(player)
		end)
	end
end

local function setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	player.CharacterAppearanceLoaded:Connect(function()
		schedule(player)
	end)
	player.AttributeChanged:Connect(function(name)
		if WATCHED[name] or string.sub(name, 1, 3) == "XP_" then -- XP: Level-Skins der Waffe
			schedule(player)
		end
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
end

function BackWeapon.Init()
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

return BackWeapon

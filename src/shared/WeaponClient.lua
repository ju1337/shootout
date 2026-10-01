-- WeaponClient (ModuleScript, nur Client)
-- Eingaben (Klick, R, 1/2), Waffe vor der Kamera und Schuss-Effekte.
-- Schaden und Munition entscheidet der Server, der Client zeigt nur an.
-- Welche Waffen man hat, steht im Charakter-Attribut "Loadout" (vom Server, je nach Agent).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.WeaponConfig)
local Remotes = require(Shared.Remotes)
local GunModels = require(Shared.GunModels)
local Modes = require(Shared.Modes)
local Cosmetics = require(Shared.Cosmetics)

local player = Players.LocalPlayer

local WeaponClient = {}

-- Signale für das HUD: AmmoChanged(name, mag, reserve, reloading), Hit(headshot, killed)
local ammoChanged = Instance.new("BindableEvent")
local hit = Instance.new("BindableEvent")
WeaponClient.AmmoChanged = ammoChanged.Event
WeaponClient.Hit = hit.Event

-- Position der Waffe vor der Kamera (rechts unten)
local LONG_OFFSET = CFrame.new(0.8, -0.85, -2.0)
local SHORT_OFFSET = CFrame.new(0.7, -0.75, -1.6)
local SHORT_WEAPONS = { Pistol = true, Revolver = true, SMG = true }

local current = nil -- aktuelle Waffe (kommt vom Server)
local mag, reserve = 0, 0
local reloading = false
local synced = false -- erst schießen, wenn der Server die Munition gemeldet hat
local mouseDown = false
local lastShot = 0
local viewModel

local function notifyAmmo()
	if current then
		ammoChanged:Fire(current, mag, reserve, reloading)
	end
end

-- Skin der aktuellen Waffe (gekauft oder Level-Belohnung des aktiven Agenten)
local function currentSkin()
	local character = player.Character
	local agentId = (character and character:GetAttribute("Agent")) or player:GetAttribute("Agent")
	return Cosmetics.WeaponSkin(player, agentId, current)
end

-- Waffenmodell vor der Kamera (nur für einen selbst sichtbar)
local function updateViewModel()
	if viewModel then
		viewModel:Destroy()
		viewModel = nil
	end
	if current then
		viewModel = GunModels.Build(current, currentSkin())
		viewModel.Parent = workspace.CurrentCamera
	end
end

-- Waffen des aktuellen Charakters (Slot 1, Slot 2)
local function loadout()
	local character = player.Character
	local text = character and character:GetAttribute("Loadout")
	return text and string.split(text, ",") or {}
end

local function requestReload()
	if not synced or reloading or not current then
		return
	end
	local cfg = WeaponConfig.Get(current)
	if mag >= cfg.MagazineSize or reserve <= 0 then
		return
	end
	reloading = true
	notifyAmmo()
	Remotes.Reload:FireServer()
end

local function tryFire()
	if not synced or reloading or not current or not Modes.IsFighting(player) then
		return
	end
	if mag <= 0 then
		requestReload() -- leer: automatisch nachladen
		return
	end
	local cfg = WeaponConfig.Get(current)
	local now = os.clock()
	if now - lastShot < cfg.FireDelay then
		return
	end
	lastShot = now
	mag -= 1
	notifyAmmo()

	local camera = workspace.CurrentCamera
	Remotes.Fire:FireServer(camera.CFrame.Position, camera.CFrame.LookVector)
end

local function equip(slot)
	local name = loadout()[slot]
	if not name or name == current then
		return
	end
	current = name
	reloading = false
	synced = false
	updateViewModel()
	Remotes.Equip:FireServer(name)
end

-- Nach Spawn/Respawn: auf den Stand vom Server warten (Equip ohne Namen fragt ihn an)
local function resetWeapon()
	current = nil
	reloading = false
	synced = false
	mouseDown = false
	updateViewModel()
	Remotes.Equip:FireServer(nil)
end

-- Kurze gelbe Leuchtspur für jeden Schuss (von allen Spielern)
local function showTracer(startPos, endPos)
	local distance = (endPos - startPos).Magnitude
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 220, 90)
	tracer.Size = Vector3.new(0.06, 0.06, distance)
	tracer.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance / 2)
	tracer.Parent = workspace
	Debris:AddItem(tracer, 0.06)
end

function WeaponClient.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Modes.IsFighting(player) then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDown = true
			tryFire()
		elseif input.KeyCode == Enum.KeyCode.R then
			requestReload()
		elseif input.KeyCode == Enum.KeyCode.One then
			equip(1)
		elseif input.KeyCode == Enum.KeyCode.Two then
			equip(2)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDown = false
		end
	end)

	-- Dauerfeuer bei automatischen Waffen
	RunService.Heartbeat:Connect(function()
		if mouseDown and current and WeaponConfig.Get(current).Automatic then
			tryFire()
		end
	end)

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local isAlive = humanoid ~= nil and humanoid.Health > 0 and Modes.IsFighting(player)

		-- Eigenes Tool in der Hand ausblenden (das sehen nur die anderen)
		if character then
			for _, obj in character:GetChildren() do
				if obj:IsA("Tool") then
					for _, part in obj:GetChildren() do
						if part:IsA("BasePart") then
							part.LocalTransparencyModifier = 1
						end
					end
				end
			end
		end

		-- Kamera-Waffe nur sichtbar, solange man selbst lebt (nicht beim Zuschauen)
		if viewModel then
			viewModel.Parent = isAlive and workspace.CurrentCamera or nil
			if isAlive then
				local offset = SHORT_WEAPONS[current] and SHORT_OFFSET or LONG_OFFSET
				viewModel:PivotTo(workspace.CurrentCamera.CFrame * offset)
			end
		end
	end)

	-- Server ist die Wahrheit für Munition und aktuelle Waffe
	Remotes.AmmoUpdate.OnClientEvent:Connect(function(name, newMag, newReserve, isReloading)
		if name ~= current or not viewModel then
			current = name
			updateViewModel()
		end
		mag, reserve, reloading = newMag, newReserve, isReloading
		synced = true
		notifyAmmo()
	end)

	Remotes.Shot.OnClientEvent:Connect(function(shooter, startPos, endPos)
		-- Eigene Schüsse starten optisch an der Laufmündung
		local barrel = shooter == player and viewModel and viewModel.Parent and viewModel:FindFirstChild("Barrel")
		if barrel then
			startPos = (barrel.CFrame * CFrame.new(0, 0, -barrel.Size.Z / 2)).Position
		end
		showTracer(startPos, endPos)
	end)

	Remotes.Hitmarker.OnClientEvent:Connect(function(headshot, killed)
		hit:Fire(headshot, killed)
	end)

	player.CharacterAdded:Connect(resetWeapon)
end

return WeaponClient

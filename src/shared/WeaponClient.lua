-- WeaponClient (ModuleScript, nur Client)
-- Eingaben (Klick, Rechtsklick = Zielen, R, 1/2), Waffe vor der Kamera, leichter Rückstoß
-- und Schuss-Effekte.
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
local Movement = require(Shared.Movement)
local BuyConfig = require(Shared.BuyConfig)

local player = Players.LocalPlayer

local WeaponClient = {}

-- Signale für das HUD: AmmoChanged(name, mag, reserve, reloading),
-- Hit(headshot, killed, damage, position, victimName), AimChanged(aiming)
local ammoChanged = Instance.new("BindableEvent")
local hit = Instance.new("BindableEvent")
local aimChanged = Instance.new("BindableEvent")
WeaponClient.AmmoChanged = ammoChanged.Event
WeaponClient.Hit = hit.Event
WeaponClient.AimChanged = aimChanged.Event

-- Position der Waffe vor der Kamera (rechts unten)
local LONG_OFFSET = CFrame.new(0.8, -0.85, -2.0)
local SHORT_OFFSET = CFrame.new(0.7, -0.75, -1.6)
local SHORT_WEAPONS = { Pistol = true, Revolver = true, SMG = true }
-- Beim Zielen: Waffe mittig, Visier auf Höhe des Fadenkreuzes
local LONG_AIM_OFFSET = CFrame.new(0, -0.68, -1.7)
local SHORT_AIM_OFFSET = CFrame.new(0, -0.42, -1.4)
local AIM_SPEED = 12          -- wie schnell die Waffe in die Zielposition gleitet
local RECOIL_RECOVERY = 10    -- wie schnell sich der Rückstoß zurückstellt (höher = schneller)

local current = nil -- aktuelle Waffe (kommt vom Server)
local mag, reserve = 0, 0
local magSize = 0 -- Magazingröße vom Server (mit gekauftem "Großes Magazin")
local reloading = false
local synced = false -- erst schießen, wenn der Server die Munition gemeldet hat
local mouseDown = false
local lastShot = 0
local viewModel
local aiming = false
local aimBlend = 0            -- 0 = Hüfte, 1 = Zielen
local recoilPitch = 0         -- aktueller Rückstoß (Grad), stellt sich von selbst zurück
local recoilYaw = 0
local appliedPitch = 0        -- schon auf die Kamera gelegter Teil
local appliedYaw = 0
local kick = 0                -- Waffe ruckt kurz nach hinten
local knife = nil             -- Messer-Modell während des Stichs
local lastMelee = 0

local function setAiming(on)
	if on == aiming then
		return
	end
	aiming = on
	local cfg = current and WeaponConfig.Get(current)
	Movement.SetAiming(on, cfg and cfg.AimFov or 50)
	aimChanged:Fire(on)
end

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
	if mag >= magSize or reserve <= 0 then
		return
	end
	reloading = true
	notifyAmmo()
	Remotes.Reload:FireServer()
end

-- Am Boden (niedergeschlagen) kann man nicht schießen
local function isDowned()
	return player.Character ~= nil and player.Character:GetAttribute("Downed") == true
end

local function tryFire()
	if not synced or reloading or not current or not Modes.IsFighting(player) or isDowned() then
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
	Remotes.Fire:FireServer(camera.CFrame.Position, camera.CFrame.LookVector, aiming)

	-- Leichter Rückstoß: nach oben, minimal zur Seite, beim Zielen etwas weniger
	local recoil = (cfg.Recoil or 0) * (aiming and 0.7 or 1)
		* (BuyConfig.Has(player, "Stability") and BuyConfig.StabilityFactor or 1)
	recoilPitch = math.min(recoilPitch + recoil, 4)
	recoilYaw += recoil * (math.random() - 0.5) * 0.6
	kick = 1
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
	if aiming then
		Movement.SetAiming(true, WeaponConfig.Get(name).AimFov)
	end
	Remotes.Equip:FireServer(name)
end

-- Messer (V): kurzer Stich nach vorne, Waffe wird kurz weggezogen
local function melee()
	local cfg = WeaponConfig.Melee
	if os.clock() - lastMelee < cfg.Cooldown or not Modes.IsFighting(player) or isDowned() then
		return
	end
	lastMelee = os.clock()
	local camera = workspace.CurrentCamera
	Remotes.Melee:FireServer(camera.CFrame.Position, camera.CFrame.LookVector)

	-- Messer aus zwei Teilen: Griff + Klinge
	if knife then
		knife:Destroy()
	end
	knife = Instance.new("Model")
	for _, def in { { Vector3.new(0.15, 0.15, 0.5), Vector3.new(0, 0, 0.3), Color3.fromRGB(30, 30, 30) },
		{ Vector3.new(0.06, 0.18, 0.9), Vector3.new(0, 0, -0.4), Color3.fromRGB(200, 205, 215) } } do
		local part = Instance.new("Part")
		part.Size = def[1]
		part.CFrame = CFrame.new(def[2])
		part.Color = def[3]
		part.Material = Enum.Material.Metal
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = knife
	end
	knife.Parent = camera
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / 0.25
		if t >= 1 or not knife then
			connection:Disconnect()
			if knife then
				knife:Destroy()
				knife = nil
			end
			return
		end
		-- Bogen von rechts unten nach vorne-mitte
		local swing = math.sin(t * math.pi)
		knife:PivotTo(workspace.CurrentCamera.CFrame * CFrame.new(0.9 - swing * 0.8, -0.8 + swing * 0.3, -1.2 - swing * 0.8)
			* CFrame.Angles(0, math.rad(-30 + swing * 40), math.rad(-60)))
	end)
end

-- Nach Spawn/Respawn: auf den Stand vom Server warten (Equip ohne Namen fragt ihn an)
local function resetWeapon()
	current = nil
	reloading = false
	synced = false
	mouseDown = false
	setAiming(false)
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
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			setAiming(current ~= nil)
		elseif input.KeyCode == Enum.KeyCode.R then
			requestReload()
		elseif input.KeyCode == Enum.KeyCode.V then
			melee()
		elseif input.KeyCode == Enum.KeyCode.One then
			equip(1)
		elseif input.KeyCode == Enum.KeyCode.Two then
			equip(2)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDown = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			setAiming(false)
		end
	end)

	-- Rückstoß auf die Kamera legen. Die Kamera rechnet vom aktuellen Blick aus weiter,
	-- darum wird nur die Änderung pro Bild aufgetragen: erst hoch, dann sanft zurück.
	RunService:BindToRenderStep("WeaponRecoil", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local decay = math.exp(-RECOIL_RECOVERY * dt)
		recoilPitch *= decay
		recoilYaw *= decay
		kick *= math.exp(-18 * dt)
		local deltaPitch = recoilPitch - appliedPitch
		local deltaYaw = recoilYaw - appliedYaw
		if math.abs(deltaPitch) > 0.0001 or math.abs(deltaYaw) > 0.0001 then
			local camera = workspace.CurrentCamera
			camera.CFrame *= CFrame.Angles(math.rad(deltaPitch), math.rad(deltaYaw), 0)
			appliedPitch, appliedYaw = recoilPitch, recoilYaw
		end
	end)

	-- Dauerfeuer bei automatischen Waffen
	RunService.Heartbeat:Connect(function()
		if mouseDown and current and WeaponConfig.Get(current).Automatic then
			tryFire()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local isAlive = humanoid ~= nil and humanoid.Health > 0 and Modes.IsFighting(player) and not isDowned()

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

		if aiming and (not isAlive or reloading) then
			setAiming(false) -- beim Nachladen oder Tod nicht weiter zielen
		end

		-- Kamera-Waffe nur sichtbar, solange man selbst lebt (nicht beim Zuschauen)
		if viewModel then
			viewModel.Parent = isAlive and workspace.CurrentCamera or nil
			if isAlive then
				-- Während des Messerstichs Waffe nach unten wegziehen
				local meleeDrop = knife and CFrame.new(0, -1.2, 0.4) or CFrame.new()
				aimBlend += ((aiming and 1 or 0) - aimBlend) * math.min(1, AIM_SPEED * dt)
				local short = SHORT_WEAPONS[current]
				local hip = short and SHORT_OFFSET or LONG_OFFSET
				local aim = short and SHORT_AIM_OFFSET or LONG_AIM_OFFSET
				local offset = hip:Lerp(aim, aimBlend) * CFrame.new(0, 0, kick * 0.12) * CFrame.Angles(math.rad(kick * 2), 0, 0)
					* meleeDrop
				viewModel:PivotTo(workspace.CurrentCamera.CFrame * offset)
			end
		end
	end)

	-- Server ist die Wahrheit für Munition und aktuelle Waffe
	Remotes.AmmoUpdate.OnClientEvent:Connect(function(name, newMag, newReserve, isReloading, newSize)
		if name ~= current or not viewModel then
			current = name
			updateViewModel()
		end
		mag, reserve, reloading = newMag, newReserve, isReloading
		magSize = newSize or WeaponConfig.Get(name).MagazineSize
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

	Remotes.Hitmarker.OnClientEvent:Connect(function(headshot, killed, damage, position, victimName, downed)
		hit:Fire(headshot, killed, damage, position, victimName, downed)
	end)

	player.CharacterAdded:Connect(resetWeapon)
end

return WeaponClient

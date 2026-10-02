-- WeaponClient (ModuleScript, nur Client)
-- Eingaben (Schießen, Zielen, Nachladen, Waffenwechsel, Messer), Rückstoß, Streuung und alle eigenen
-- Schuss-Effekte – sofort, ohne auf den Server zu warten. Schaden und Munition entscheidet der Server;
-- der Client rechnet die Munition über Schuss-Nummern vor, damit die Anzeige beim Dauerfeuer nicht flackert.
-- Ego-Perspektive: Waffe mit Armen vor der Kamera (ViewModel), Zielen über Kimme und Korn.
-- Schulterkamera: der Charakter hält die Waffe mit beiden Händen (CharacterPose), dazu das Fadenkreuz (HUD).
-- Welche Waffen man hat, steht im Charakter-Attribut "Loadout" (vom Server, je nach Agent).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.WeaponConfig)
local Remotes = require(Shared.Remotes)
local GunModels = require(Shared.GunModels)
local Modes = require(Shared.Modes)
local Cosmetics = require(Shared.Cosmetics)
local Movement = require(Shared.Movement)
local AttachmentConfig = require(Shared.AttachmentConfig)
local InputActions = require(Shared.InputActions)
local ViewModel = require(Shared.ViewModel)
local WeaponAnimations = require(Shared.WeaponAnimations)
local WeaponEffects = require(Shared.WeaponEffects)
local CharacterPose = require(Shared.CharacterPose)

local player = Players.LocalPlayer

local WeaponClient = {}

-- Signale für das HUD: AmmoChanged(name, mag, reserve, reloading, magSize, infinite),
-- Hit(headshot, killed, damage, position, victimName, downed, armor, victimModel), AimChanged(aiming), Fired(name)
local ammoChanged = Instance.new("BindableEvent")
local hit = Instance.new("BindableEvent")
local aimChanged = Instance.new("BindableEvent")
local fired = Instance.new("BindableEvent")
WeaponClient.AmmoChanged = ammoChanged.Event
WeaponClient.Hit = hit.Event
WeaponClient.AimChanged = aimChanged.Event
WeaponClient.Fired = fired.Event

local AIM_SPEED = 9            -- Übergang Hüfte <-> Zielen (pro Sekunde)
local RECOIL_RISE = 30         -- wie schnell der Rückstoß die Kamera hebt
local RECOIL_RETURN = 6        -- wie schnell der Blick nach dem Feuern zurückwandert
local RECOIL_HOLD = 0.12       -- so lange nach dem letzten Schuss bleibt der Rückstoß stehen
local SPRINT_BLOCK = 0.35      -- nach einem Schuss so lange nicht sprinten
local DRAW_TIME = 0.35         -- Waffe ziehen: so lange kein Schuss
local THIRD_PERSON_DISTANCE = 3

local current = nil      -- aktuelle Waffe (kommt vom Server)
local serverMag, reserve, magSize, infinite = 0, 0, 0, false
local serverShotId = 0   -- letzte vom Server verarbeitete Schuss-Nummer
local shotCounter = 0    -- eigene Schuss-Nummern (laufen über alle Leben weiter, wie auf dem Server)
local reloading = false
local reload = nil       -- { Weapon, Anim, Start, Duration, LastT } – Nachlade-Animation
local fireAnim = nil     -- { Anim, Start, LastT } – Schuss-Animation (Schlitten, Pumpe, Hülse)
local synced = false     -- erst schießen, wenn der Server die Munition gemeldet hat
local fireHeld = false
local aimHeld = false
local aiming = false
local aimBlend = 0       -- 0 = Hüfte, 1 = Zielen
local lastShot = 0
local lastDryClick = 0
local drawUntil = 0
local equipTime = 0
local bloom, bloomTime = 0, 0
local recoilPitch, recoilYaw = 0, 0   -- Ziel des Rückstoßes (Grad)
local shownPitch, shownYaw = 0, 0     -- schon erreichter Rückstoß
local appliedPitch, appliedYaw = 0, 0 -- schon auf die Kamera gelegt
local viewModel = nil
local knife = nil        -- Messer-Modell während des Stichs
local lastMelee = 0
local wasAirborne, fallSpeed = false, 0
local random = Random.new()

local function isDowned()
	return player.Character ~= nil and player.Character:GetAttribute("Downed") == true
end

local function alive()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and Modes.IsFighting(player) and not isDowned()
end

-- Magazin mit allen Schüssen, die der Server noch nicht bestätigt hat
local function displayedMag()
	return math.max(0, serverMag - math.max(0, shotCounter - serverShotId))
end

local function notifyAmmo()
	if current then
		ammoChanged:Fire(current, displayedMag(), reserve, reloading, magSize, infinite)
	end
end

local function setAiming(on)
	if on == aiming then
		return
	end
	aiming = on
	local cfg = current and WeaponConfig.Get(current)
	Movement.SetAiming(on, cfg and cfg.AimFov or 50)
	aimChanged:Fire(on)
end

-- Skin der aktuellen Waffe (gekauft oder Level-Belohnung des aktiven Agenten) und Uniformfarbe für die Ärmel
local function agentId()
	local character = player.Character
	return (character and character:GetAttribute("Agent")) or player:GetAttribute("Agent")
end

-- Waffe mit Armen vor der Kamera (nur für einen selbst sichtbar)
local function updateViewModel()
	if viewModel then
		viewModel:Destroy()
		viewModel = nil
	end
	if current and GunModels.Info[current] then
		local sleeve = Cosmetics.AgentColors(player, agentId())
		viewModel = ViewModel.new(current, Cosmetics.WeaponSkin(player, agentId(), current), sleeve,
			AttachmentConfig.EquippedList(player, current))
		viewModel:Draw()
	end
end

-- Waffen des aktuellen Charakters (Slot 1, Slot 2)
local function loadout()
	local character = player.Character
	local text = character and character:GetAttribute("Loadout")
	return text and string.split(text, ",") or {}
end

local function ownTool()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("Weapon") == current then
		return tool
	end
	return nil
end

local function firstPersonView()
	return viewModel ~= nil and viewModel.Model.Parent ~= nil
end

local function movementState()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return 0, false, Vector3.zero
	end
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude, humanoid.FloorMaterial == Enum.Material.Air, velocity
end

-- ---------- Nachladen ----------

local function startReloadAnim(shells)
	local duration = WeaponConfig.ReloadDuration(player, player.Character, current)
	local anim, total = WeaponAnimations.Reload(current, duration, shells)
	reload = anim and { Weapon = current, Anim = anim, Start = os.clock(), Duration = total, LastT = -1 } or nil
end

local function requestReload()
	if not synced or reloading or not current then
		return
	end
	local mag = displayedMag()
	if mag >= magSize or (reserve <= 0 and not infinite) then
		return
	end
	local cfg = WeaponConfig.Get(current)
	reloading = true
	fireAnim = nil
	local shells = nil
	if cfg.ShellReload then
		shells = infinite and (magSize - mag) or math.min(magSize - mag, reserve)
	end
	startReloadAnim(shells)
	notifyAmmo()
	Remotes.Reload:FireServer()
end

-- ---------- Effekte ----------

-- Mündung der eigenen Waffe: vor der Kamera (Ego) oder in der Hand (Schulter)
local function muzzle()
	if firstPersonView() then
		return viewModel:MuzzleCFrame(), 0.55
	end
	local tool = ownTool()
	local handle = tool and tool:FindFirstChild("Handle")
	if handle then
		return handle.CFrame * CFrame.new(GunModels.Info[current].Muzzle * GunModels.ToolScale), 1
	end
	local camera = workspace.CurrentCamera
	return camera.CFrame * CFrame.new(0.6, -0.5, -2), 1
end

local function ejectShell()
	local _, _, velocity = movementState()
	if firstPersonView() then
		local scale = ViewModel.Scale()
		WeaponEffects.EjectShell(viewModel:EjectCFrame(), scale, workspace.CurrentCamera.CFrame.RightVector, velocity)
		return
	end
	local tool = ownTool()
	local handle = tool and tool:FindFirstChild("Handle")
	if handle then
		local point = handle.CFrame * CFrame.new(GunModels.Info[current].Eject * GunModels.ToolScale)
		WeaponEffects.EjectShell(point, GunModels.ToolScale, handle.CFrame.RightVector, velocity)
	end
end

-- Ereignis aus einer eigenen Animation (Sound, fallendes Magazin, Hülse)
local function handleEvent(event)
	local kind = event[2]
	if kind == "Sound" then
		WeaponEffects.ActionSound(event[3])
	elseif kind == "Eject" then
		ejectShell()
	elseif kind == "Drop" or kind == "Spill" then
		local _, _, velocity = movementState()
		local parts, scale, collide
		if firstPersonView() then
			parts, scale, collide = viewModel:GroupParts(event[3]), ViewModel.Scale(), false
		else
			local tool = ownTool()
			parts, scale, collide = tool and GunModels.GroupParts(tool, event[3]) or {}, GunModels.ToolScale, true
		end
		if kind == "Drop" then
			WeaponEffects.DropCopy(parts, velocity + Vector3.new(0, -4, 0) * scale, collide, collide and 3 or 0.7)
		elseif parts[1] then
			WeaponEffects.Spill(parts[1].Position, event[4] or 6, scale, velocity)
		end
	end
end

-- Animation weiterlaufen lassen: Ereignisse zwischen letztem und jetzigem Zeitpunkt auslösen
local function advance(state, duration)
	local t = math.clamp((os.clock() - state.Start) / duration, 0, 1)
	for _, event in WeaponAnimations.Events(state.Anim, state.LastT, t) do
		handleEvent(event)
	end
	state.LastT = t
	return t
end

local function hitKindOf(result)
	if not result then
		return nil
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return "Character"
	end
	return result.Instance.Anchored and "World" or "Prop"
end

-- Eigenen Schuss sofort zeigen: gleicher Weg wie auf dem Server (Schulterkamera: Zielpunkt, dann vom Kopf aus),
-- dieselben Kugelrichtungen (Seed aus Spieler + Schuss-Nummer). Gibt die getroffenen Charakter-Teile pro Kugel
-- zurück ({ Part, Position } oder false) – der Server prüft sie und nimmt sie als Treffer (Ping-Ausgleich).
local function showOwnShot(cfg, origin, look, spreadAngle, shotId)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, workspace.CurrentCamera }
	local shotOrigin, aimDirection = origin, look
	if head and (origin - head.Position).Magnitude > THIRD_PERSON_DISTANCE then
		local skip = math.max(0, (head.Position - origin):Dot(look))
		local start = origin + look * skip
		local aimHit = workspace:Raycast(start, look * cfg.Range, params)
		local aimPoint = aimHit and aimHit.Position or (start + look * cfg.Range)
		shotOrigin = head.Position
		if (aimPoint - shotOrigin).Magnitude > 0.5 then
			aimDirection = (aimPoint - shotOrigin).Unit
		end
	end
	local muzzleCF, flashScale = muzzle()
	WeaponEffects.GunSound(current, muzzleCF.Position, true, AttachmentConfig.Effects(player, current).Silenced and 0.45 or 1)
	WeaponEffects.MuzzleFlash(muzzleCF, flashScale)
	local claims = {}
	local directions = WeaponConfig.PelletDirections(aimDirection, spreadAngle, cfg.Pellets or 1,
		WeaponConfig.ShotSeed(player.UserId, shotId))
	for i, direction in directions do
		local result = workspace:Raycast(shotOrigin, direction * cfg.Range, params)
		local endPos = result and result.Position or (shotOrigin + direction * cfg.Range)
		WeaponEffects.Tracer(muzzleCF.Position, endPos, true)
		local kind = hitKindOf(result)
		if kind then
			WeaponEffects.Impact(endPos, result.Normal, kind)
		end
		claims[i] = kind == "Character" and { Part = result.Instance, Position = result.Position } or false
	end
	return claims
end

-- ---------- Schießen ----------

local function tryFire()
	if not synced or not current or not alive() then
		return
	end
	local cfg = WeaponConfig.Get(current)
	local now = os.clock()
	if now < drawUntil or now - lastShot < cfg.FireDelay then
		return
	end
	local mag = displayedMag()
	if reloading then
		if not (cfg.ShellReload and mag > 0) then
			return
		end
		-- Schrotflinte: Schuss bricht das Nachladen ab (Server macht dasselbe)
		reloading = false
		reload = nil
	end
	if mag <= 0 then
		if reserve > 0 or infinite then
			requestReload() -- leer: automatisch nachladen
		elseif now - lastDryClick > 0.3 then
			lastDryClick = now
			WeaponEffects.ActionSound("Empty")
		end
		return
	end
	-- Dauerfeuer bleibt im Takt der Waffe, auch wenn die Bildrate nicht genau passt (Schuss kam höchstens ein
	-- Bild zu spät: Takt beibehalten, sonst neu ansetzen – so kann sich kein Vorsprung ansammeln)
	lastShot = now - lastShot <= cfg.FireDelay + 1 / 30 and lastShot + cfg.FireDelay or now
	shotCounter += 1
	Movement.SuppressSprint(SPRINT_BLOCK)

	-- Streuung wie auf dem Server: Bloom, Bewegung, Sprung, Zielen, Stabilisator
	local speed, airborne = movementState()
	local shotBloom
	shotBloom, bloom = WeaponConfig.StepBloom(cfg, bloom, now - bloomTime)
	bloomTime = now
	local effects = AttachmentConfig.Effects(player, current)
	local spreadAngle = WeaponConfig.SpreadFor(cfg, shotBloom, speed, airborne, aiming, effects)

	local camera = workspace.CurrentCamera
	local origin, look = camera.CFrame.Position, camera.CFrame.LookVector
	local claims = showOwnShot(WeaponConfig.WithAttachments(cfg, effects), origin, look, spreadAngle, shotCounter)
	Remotes.Fire:FireServer(origin, look, aiming, shotCounter, claims)

	-- Rückstoß: hoch und etwas zur Seite, beim Zielen weniger (Aufsätze: Kompensator, Vertikalgriff).
	-- Nach dem Feuern wandert der Blick zurück.
	local strength = (aiming and 0.75 or 1) * effects.Recoil
	recoilPitch = math.min(recoilPitch + (cfg.Recoil or 0) * strength, cfg.MaxRecoil or 5)
	recoilYaw += (random:NextNumber() - 0.5) * 2 * (cfg.RecoilSide or 0) * strength
	recoilYaw = math.clamp(recoilYaw, -(cfg.MaxRecoil or 5) * 0.4, (cfg.MaxRecoil or 5) * 0.4)
	if viewModel then
		viewModel:Fire(cfg.Kick or 1, aiming)
	end
	if player.Character then
		CharacterPose.Fired(player.Character, current)
	end
	local fire = WeaponAnimations.Fire(current)
	if fire then
		fireAnim = { Anim = fire, Start = now, LastT = -1 }
	end
	notifyAmmo()
	fired:Fire(current)
end

local function equip(slot)
	local name = loadout()[slot]
	if not name or name == current then
		return
	end
	current = name
	reloading = false
	reload = nil
	fireAnim = nil
	synced = false
	bloom = 0
	drawUntil = os.clock() + DRAW_TIME
	equipTime = os.clock()
	updateViewModel()
	WeaponEffects.ActionSound("Draw")
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
	reload = nil
	fireAnim = nil
	synced = false
	fireHeld = false
	aimHeld = false
	bloom = 0
	recoilPitch, recoilYaw = 0, 0
	setAiming(false)
	updateViewModel()
	Remotes.Equip:FireServer(nil)
end

-- ---------- Abfragen fürs HUD ----------

-- Aktuelle Streuung in Grad (für das Fadenkreuz), weich zwischen Hüfte und Zielen
function WeaponClient.GetSpread()
	local cfg = current and WeaponConfig.Get(current)
	if not cfg then
		return 0
	end
	local speed, airborne = movementState()
	local currentBloom = WeaponConfig.DecayBloom(cfg, bloom, os.clock() - bloomTime)
	local effects = AttachmentConfig.Effects(player, current)
	local hip = WeaponConfig.SpreadFor(cfg, currentBloom, speed, airborne, false, effects)
	local ads = WeaponConfig.SpreadFor(cfg, currentBloom, speed, airborne, true, effects)
	return hip + (ads - hip) * aimBlend
end

function WeaponClient.GetAimBlend()
	return aimBlend
end

function WeaponClient.GetWeapon()
	return current
end

-- Fortschritt des Nachladens (0..1) oder nil
function WeaponClient.GetReloadProgress()
	if not reloading or not reload then
		return nil
	end
	return math.clamp((os.clock() - reload.Start) / reload.Duration, 0, 1)
end

function WeaponClient.IsFirstPerson()
	return firstPersonView()
end

function WeaponClient.Init()
	-- Eingaben über InputActions (Tastatur, Controller und Touch-Knöpfe)
	local function fighting()
		return Modes.IsFighting(player)
	end
	InputActions.Bind("Fire", function(began)
		fireHeld = began and fighting()
		if fireHeld then
			tryFire()
		end
	end)
	InputActions.Bind("Aim", function(began)
		aimHeld = began and fighting()
	end)
	InputActions.Bind("Reload", function(began)
		if began and fighting() then
			requestReload()
		end
	end)
	InputActions.Bind("Melee", function(began)
		if began and fighting() then
			melee()
		end
	end)
	InputActions.Bind("Weapon1", function(began)
		if began and fighting() then
			equip(1)
		end
	end)
	InputActions.Bind("Weapon2", function(began)
		if began and fighting() then
			equip(2)
		end
	end)
	-- Controller/Touch: zwischen den beiden Waffen wechseln
	InputActions.Bind("SwapWeapon", function(began)
		if began and fighting() then
			equip(loadout()[1] == current and 2 or 1)
		end
	end)

	-- Rückstoß auf die Kamera legen. Die Kamera rechnet vom aktuellen Blick aus weiter, darum wird nur die
	-- Änderung pro Bild aufgetragen: schnell hoch, nach dem Feuern sanft zurück.
	RunService:BindToRenderStep("WeaponRecoil", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if os.clock() - lastShot > RECOIL_HOLD then
			local decay = math.exp(-RECOIL_RETURN * dt)
			recoilPitch *= decay
			recoilYaw *= decay
		end
		local rise = math.min(1, RECOIL_RISE * dt)
		shownPitch += (recoilPitch - shownPitch) * rise
		shownYaw += (recoilYaw - shownYaw) * rise
		local deltaPitch = shownPitch - appliedPitch
		local deltaYaw = shownYaw - appliedYaw
		if math.abs(deltaPitch) > 0.0001 or math.abs(deltaYaw) > 0.0001 then
			local camera = workspace.CurrentCamera
			camera.CFrame *= CFrame.Angles(math.rad(deltaPitch), math.rad(deltaYaw), 0)
			appliedPitch, appliedYaw = shownPitch, shownYaw
		end
	end)

	-- Dauerfeuer bei automatischen Waffen
	RunService.Heartbeat:Connect(function()
		if fireHeld and current and WeaponConfig.Get(current).Automatic then
			tryFire()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local isAlive = alive()
		local thirdPerson = Movement.IsThirdPerson()

		-- Eigenes Tool in der Hand ausblenden (das sehen nur die anderen) – außer in der Schulterkamera
		if character then
			for _, obj in character:GetChildren() do
				if obj:IsA("Tool") then
					for _, part in obj:GetChildren() do
						if part:IsA("BasePart") then
							part.LocalTransparencyModifier = thirdPerson and 0 or 1
						end
					end
				end
			end
		end

		-- Zielen: solange gehalten, außer beim Nachladen, Sprinten-Stopp macht Movement
		setAiming(aimHeld and isAlive and current ~= nil and not reloading)
		aimBlend += ((aiming and 1 or 0) - aimBlend) * math.min(1, AIM_SPEED * dt)

		-- Nachlade-Animation: Ereignisse auslösen, Ende abwarten (Server bestätigt das Nachladen)
		local reloadPose = nil
		if reload then
			if reload.Weapon ~= current then
				reload = nil
			else
				local t = advance(reload, reload.Duration)
				if t >= 1 and not reloading then
					reload = nil
				else
					reloadPose = { Anim = reload.Anim, T = t }
				end
			end
		end
		local firePose = nil
		if fireAnim then
			local t = advance(fireAnim, fireAnim.Anim.Duration)
			if t >= 1 then
				fireAnim = nil
			elseif fireAnim.Anim.Groups or fireAnim.Anim.Gun then
				firePose = { Anim = fireAnim.Anim, T = t }
			end
		end

		-- Landen: Waffe taucht kurz ein
		local speed, airborne, velocity = movementState()
		if wasAirborne and not airborne and viewModel then
			viewModel:Land(fallSpeed)
		end
		wasAirborne = airborne
		fallSpeed = math.max(0, -velocity.Y)

		-- Kamera-Waffe nur sichtbar, solange man selbst lebt (nicht beim Zuschauen) und in der Ego-Perspektive
		if viewModel then
			local showViewModel = isAlive and not thirdPerson
			viewModel:SetParent(showViewModel and workspace.CurrentCamera or nil)
			if showViewModel then
				viewModel:Update(dt, {
					Camera = workspace.CurrentCamera.CFrame,
					Aim = aimBlend,
					Sprinting = Movement.IsSprinting(),
					Speed = airborne and 0 or speed,
					Reload = reloadPose,
					Fire = firePose,
					Melee = knife ~= nil,
				})
			end
		end

		-- Third-Person-Haltung des eigenen Charakters
		CharacterPose.SetLocal(aiming, Movement.IsSprinting(),
			reloadPose and reload and { Weapon = reload.Weapon, Anim = reload.Anim, Start = reload.Start, Duration = reload.Duration },
			isAlive and thirdPerson)
	end)

	-- Server ist die Wahrheit für Munition und aktuelle Waffe
	Remotes.AmmoUpdate.OnClientEvent:Connect(function(name, newMag, newReserve, isReloading, newSize, lastShotId, isInfinite)
		-- Alte Meldung für die vorige Waffe, während der Wechsel noch läuft: ignorieren
		-- (antwortet der Server nicht auf den Wechsel, gilt nach kurzer Zeit wieder seine Waffe)
		if current and name ~= current and not synced and os.clock() - equipTime < 1.5 then
			return
		end
		if name ~= current or not viewModel then
			current = name
			updateViewModel()
		end
		serverMag, reserve = newMag, newReserve
		magSize = newSize or WeaponConfig.Get(name).MagazineSize
		infinite = isInfinite == true
		if typeof(lastShotId) == "number" then
			serverShotId = lastShotId
		end
		if isReloading and not reloading then
			reloading = true
			if not reload then
				local cfg = WeaponConfig.Get(name)
				startReloadAnim(cfg.ShellReload and (magSize - newMag) or nil)
			end
		elseif not isReloading and reloading then
			reloading = false
			-- Vom Server abgebrochen/abgelehnt: Animation stoppen; fast fertig: zu Ende laufen lassen
			if reload and (os.clock() - reload.Start) / reload.Duration < 0.8 then
				reload = nil
			end
		end
		synced = true
		notifyAmmo()
	end)

	-- Schüsse der anderen (Spieler, Bots, Geschütztürme). Eigene zeigt der Client schon selbst.
	local lastShotEffect = setmetatable({}, { __mode = "k" })
	Remotes.Shot.OnClientEvent:Connect(function(shooter, startPos, endPos, weaponName, normal, hitKind, silenced)
		if shooter == player or typeof(startPos) ~= "Vector3" or typeof(endPos) ~= "Vector3" then
			return
		end
		local model = nil
		if typeof(shooter) == "Instance" then
			if shooter:IsA("Player") then
				model = shooter.Character
			elseif shooter:IsA("Model") then
				model = shooter
			end
		end
		-- Schrotflinte: mehrere Kugeln pro Schuss, Mündungsfeuer und Rückstoß nur einmal
		local now = os.clock()
		local key = model or "turret"
		local firstPellet = not lastShotEffect[key] or now - lastShotEffect[key] > 0.03
		lastShotEffect[key] = now
		local start = startPos
		if model then
			local tool = model:FindFirstChildOfClass("Tool")
			local handle = tool and tool:FindFirstChild("Handle")
			local info = tool and GunModels.Info[tool:GetAttribute("Weapon")]
			if handle and info then
				start = GunModels.PointWorld(handle, info.Muzzle, GunModels.ToolScale)
			end
			if firstPellet then
				CharacterPose.Fired(model, weaponName)
			end
		end
		if firstPellet then
			WeaponEffects.GunSound(weaponName, start, false, silenced and 0.3 or 1)
			if not silenced and (endPos - start).Magnitude > 0.01 then
				WeaponEffects.MuzzleFlash(CFrame.lookAt(start, endPos), 1)
			end
		end
		if not silenced then
			WeaponEffects.Tracer(start, endPos, false)
		end
		if hitKind then
			WeaponEffects.Impact(endPos, normal, hitKind)
		end
	end)

	Remotes.Hitmarker.OnClientEvent:Connect(function(...)
		hit:Fire(...)
	end)

	player.CharacterAdded:Connect(resetWeapon)
end

return WeaponClient

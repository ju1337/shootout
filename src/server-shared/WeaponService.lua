-- WeaponService (ModuleScript, nur Server)
-- Verwaltet Munition, Nachladen, Waffenwechsel und berechnet Schaden.
-- Der Client schickt nur "ich schieße von der Kamera in Richtung B", alles andere prüft der Server.
-- Schulterkamera (wie bei Rogue Company): Der Server sucht zuerst den Punkt unter dem Fadenkreuz und
-- schießt dann vom Kopf des Charakters dorthin. Was nur die Kamera, aber nicht der Charakter sieht
-- (z.B. hinter einer Ecke), trifft man so nicht.
-- Welche Waffen ein Spieler hat, kommt vom gewählten Agenten (AgentConfig.Loadout).
-- Reserve-Munition ist unendlich (WeaponConfig.InfiniteAmmoEverywhere bzw. InfiniteAmmoModes), nachladen muss man trotzdem.
-- Offene Welt (Extinction, Modes.IsSurvival): keine Waffen vom Agenten. Die Waffe in der Hand setzt das Inventar
-- (WeaponService.SetCarried, Taste 1-9), Munition kommt aus dem Inventar (source.Count/Take), das Magazin steht am
-- Item (source.SetMag). PvP nur, wenn beide Spieler draußen sind und ihre PvP-Zeit läuft (Attribut "PvP").
-- Charakter-Attribute für die Third-Person-Animationen aller Clients:
--   ReloadStart (Serverzeit), ReloadTime (Nachladezeit mit Upgrades), ReloadShells (Patronen, Schrotflinte –
--   die Zeitleiste ergibt sich dann aus WeaponConfig.ShellTiming),
--   AimPitch (Blick nach oben/unten in Grad), Aiming (zielt)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.WeaponConfig)
local AgentConfig = require(Shared.AgentConfig)
local GameSettings = require(Shared.GameSettings)
local Remotes = require(Shared.Remotes)
local GunModels = require(Shared.GunModels)
local Modes = require(Shared.Modes)
local Cosmetics = require(Shared.Cosmetics)
local AttachmentConfig = require(Shared.AttachmentConfig)
local Damage = require(ServerStorage:WaitForChild("ServerShared").Damage)
local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)

local WeaponService = {}

-- Treffer auf ein Fahrzeug der offenen Welt: function(player, vehicleModel, damage) (setzt VehicleService)
WeaponService.OnVehicleHit = nil

-- Wird gefeuert, wenn ein Spieler einen anderen Spieler tötet:
-- (killer: Player, victim: Player oder nil bei Bots, weaponName, headshot, victimName, victimModel oder nil)
local killedEvent = Instance.new("BindableEvent")
WeaponService.Killed = killedEvent.Event

-- Wie weit der gemeldete Schussursprung vom Kopf entfernt sein darf (Anti-Cheat, Studs)
local MAX_ORIGIN_DISTANCE = 15
-- Ab diesem Abstand Kamera - Kopf gilt der Schuss als Schulterkamera (Zielpunkt-Verfahren)
local THIRD_PERSON_DISTANCE = 3

local states = {} -- [Player] = { Loadout, Current, Ammo, NextShot, Bloom, BloomTime, Reloading, ReloadId, Tools }
local lastShotIds = {} -- [Player] = letzte Schuss-Nummer des Clients (über alle Leben)
local lastAimState = {} -- [Player] = os.clock() der letzten AimState-Meldung

local function selectedAgent(player)
	return AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
end

local function newState(player)
	local loadout = AgentConfig.LoadoutFor(player, selectedAgent(player).Id)
	if Modes.IsSurvival(player:GetAttribute("Mode")) then
		loadout = {} -- offene Welt: nur was im Inventar liegt
	end
	local state = {
		Loadout = loadout,
		Current = loadout[1],
		Ammo = {},
		NextShot = 0,
		Bloom = 0,
		BloomTime = 0,
		Reloading = false,
		ReloadId = 0,
	}
	for _, name in loadout do
		local cfg = WeaponConfig.Get(name)
		-- Aufsatz "Erweitertes Magazin" (Lobby) vergrößert das Magazin dieser Waffe
		local size = math.floor(cfg.MagazineSize * AttachmentConfig.Effects(player, name).Mag)
		state.Ammo[name] = { Mag = size, Reserve = cfg.ReserveAmmo, Size = size }
	end
	return state
end

-- Schickt dem Spieler den aktuellen Munitionsstand der gewählten Waffe
local function sendAmmo(player)
	local state = states[player]
	if not state then
		return
	end
	local ammo = state.Current and state.Ammo[state.Current]
	if not ammo then
		-- keine Waffe in der Hand (offene Welt)
		Remotes.AmmoUpdate:FireClient(player, nil, 0, 0, false, 0, lastShotIds[player] or 0, false)
		return
	end
	local reserve = state.Source and state.Source.Count() or ammo.Reserve
	Remotes.AmmoUpdate:FireClient(player, state.Current, ammo.Mag, reserve, state.Reloading, ammo.Size,
		lastShotIds[player] or 0, WeaponConfig.HasInfiniteAmmo(player) and not state.Source)
end

-- Magazin an das Item im Inventar melden (offene Welt)
local function reportMag(state, ammo)
	if state.Source and state.Source.SetMag then
		state.Source.SetMag(ammo.Mag)
	end
end

-- PvP-Regel der offenen Welt: Spieler gegen Spieler nur, wenn beide ihre PvP-Zeit haben (draußen, 5 s nach der Safe Zone)
local function pvpBlocked(attacker, victim)
	if not victim or victim == attacker or not Modes.IsSurvival(attacker:GetAttribute("Mode")) then
		return false
	end
	return attacker:GetAttribute("PvP") ~= true or victim:GetAttribute("PvP") ~= true
end

-- Nachladen für die Animationen der anderen Spieler sichtbar machen (nil = vorbei)
local function setReloadAttributes(player, duration, shells)
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute("ReloadStart", duration and workspace:GetServerTimeNow() or nil)
	character:SetAttribute("ReloadTime", duration)
	character:SetAttribute("ReloadShells", duration and shells or nil)
end

local function cancelReload(player, state)
	state.ReloadId += 1
	if state.Reloading then
		state.Reloading = false
		setReloadAttributes(player, nil)
	end
end

-- Waffe in der Hand des Charakters anzeigen (für andere Spieler sichtbar)
local function showToolInHand(player)
	local state = states[player]
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not state or not state.Tools or not humanoid or humanoid.Health <= 0 then
		return
	end
	local tool = state.Tools[state.Current]
	if tool and tool.Parent ~= player.Character then
		humanoid:EquipTool(tool)
	end
end

-- Für jede Waffe des Loadouts ein Tool in den Rucksack legen (mit gekauftem Skin oder Level-Skin)
local function giveTools(player, state)
	local agent = selectedAgent(player)
	local backpack = player:WaitForChild("Backpack")
	state.Tools = {}
	for _, name in state.Loadout do
		local skin = Cosmetics.WeaponSkin(player, agent.Id, name)
		local tool = GunModels.BuildTool(name, WeaponConfig.Get(name).DisplayName, skin,
			AttachmentConfig.EquippedList(player, name))
		tool.Parent = backpack
		state.Tools[name] = tool
	end
	showToolInHand(player)
end

local function getLivingHumanoid(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid, character
	end
	return nil, nil
end


-- ---------- Ping-Ausgleich ("was du triffst, triffst du") ----------
-- Der Client meldet pro Kugel, was er getroffen hat. Der Server prüft das streng (Sichtlinie, Reichweite,
-- Richtung, und ob das Ziel in der letzten halben Sekunde wirklich dort war) und nimmt dann den Treffer des
-- Clients. Dafür merkt sich der Server kurz, wo jeder Charakter war.
local HISTORY_TIME = 0.6     -- Sekunden Verlauf
local HISTORY_STEP = 0.05
local HIT_TOLERANCE = 6      -- Studs: Abstand gemeldeter Treffer – Körpermitte (Kopf bis Füße + Bewegung)
local CLAIM_ANGLE = math.rad(4)
local history = setmetatable({}, { __mode = "k" }) -- [Model] = { { Time, Position }, ... }

local function trackedModels()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, folderName in { "Bots", "Zombies" } do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, model in folder:GetChildren() do
				if model:IsA("Model") then
					table.insert(list, model)
				end
			end
		end
	end
	return list
end

local lastSample = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastSample < HISTORY_STEP then
		return
	end
	lastSample = now
	for _, model in trackedModels() do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			local list = history[model] or {}
			history[model] = list
			table.insert(list, { Time = now, Position = root.Position })
			while list[1] and now - list[1].Time > HISTORY_TIME do
				table.remove(list, 1)
			end
		end
	end
end)

-- War das Modell kürzlich nah an dieser Stelle?
local function wasNear(model, position)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and (root.Position - position).Magnitude <= HIT_TOLERANCE then
		return true
	end
	for _, sample in history[model] or {} do
		if (sample.Position - position).Magnitude <= HIT_TOLERANCE then
			return true
		end
	end
	return false
end

-- Gemeldeten Treffer prüfen. claim = { Part = BasePart, Position = Vector3 }. Gibt Part und Position zurück
-- oder nil, wenn der Treffer nicht glaubwürdig ist (dann zählt der eigene Raycast des Servers).
local function validClaim(character, shotOrigin, direction, cfg, claim)
	if type(claim) ~= "table" or typeof(claim.Part) ~= "Instance" or typeof(claim.Position) ~= "Vector3" then
		return nil
	end
	local part = claim.Part
	-- nur Teile der Trefferzone: Accessoires und Ausrüstung (CanQuery = false) treffen auch Kugeln nicht
	if not part:IsA("BasePart") or not part.CanQuery or not part:IsDescendantOf(workspace) or part:IsDescendantOf(character) then
		return nil
	end
	local model = part:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local position = claim.Position
	local offset = position - shotOrigin
	local distance = offset.Magnitude
	if distance > cfg.Range + 2 or distance < 0.1 then
		return nil
	end
	-- Richtung: der Treffer muss auf (oder sehr nah an) der Flugbahn dieser Kugel liegen
	local along = offset:Dot(direction)
	local sideways = (offset - direction * along).Magnitude
	if along <= 0 or sideways > math.max(2.5, distance * math.tan(CLAIM_ANGLE)) then
		return nil
	end
	-- Das Ziel war wirklich dort (jetzt oder in der letzten halben Sekunde)
	if not wasNear(model, position) then
		return nil
	end
	-- Keine Wand dazwischen (Charaktere zählen nicht als Hindernis)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = trackedModels()
	local blocked = workspace:Raycast(shotOrigin, offset.Unit * math.max(0, distance - 0.6), params)
	if blocked and blocked.Instance.CanCollide and blocked.Instance.Transparency < 0.9 then
		return nil
	end
	return part, position
end

-- Steht der Charakter in der Luft? (kurzer Strahl nach unten, R6 und R15)
local function isAirborne(character, root, humanoid)
	if not root then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local legs = humanoid.RigType == Enum.HumanoidRigType.R6 and 2 or humanoid.HipHeight
	local depth = legs + root.Size.Y / 2 + 1.2
	return workspace:Raycast(root.Position, Vector3.new(0, -depth, 0), params) == nil
end

-- Was wurde getroffen? "Character" (Lebewesen), "World" (feste Wand/Boden) oder "Prop" (lose Teile)
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

-- Schuss-Effekt an alle Spieler im selben Modus (Tracer, Sound, Einschlag).
-- shooter = Player, Bot-Modell oder nil (z.B. Geschützturm)
-- silenced = Schalldämpfer: andere sehen kein Mündungsfeuer und keine Leuchtspur, der Schuss ist leiser
function WeaponService.BroadcastShot(modeId, shooter, startPos, endPos, weaponName, normal, hitKind, silenced)
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Mode") == modeId then
			Remotes.Shot:FireClient(other, shooter, startPos, endPos, weaponName, normal, hitKind, silenced)
		end
	end
end

-- Ein einzelner Schuss/Kugel: Raycast, Effekt, Schaden.
-- Gibt bei einem Treffer { Humanoid, Damage, Headshot, Killed, Downed, Armor, Position, Name, Model } zurück.
local function fireRay(player, character, origin, direction, cfg, weaponName, params, claim)
	local result = workspace:Raycast(origin, direction * cfg.Range, params)
	local hitPart, hitPosition = result and result.Instance, result and result.Position
	-- Treffer des Clients übernehmen, wenn er glaubwürdig ist (Ping-Ausgleich)
	local claimedPart, claimedPosition = validClaim(character, origin, direction, cfg, claim)
	if claimedPart then
		hitPart, hitPosition = claimedPart, claimedPosition
	end
	local endPos = hitPosition or (origin + direction * cfg.Range)
	WeaponService.BroadcastShot(player:GetAttribute("Mode"), player, origin, endPos, weaponName,
		(not claimedPart) and result and result.Normal or nil, claimedPart and "Character" or hitKindOf(result),
		AttachmentConfig.Effects(player, weaponName).Silenced)
	if not hitPart then
		return
	end

	-- Fahrzeug der offenen Welt getroffen (VehicleService prüft Safe Zone und PvP)
	local model = hitPart:FindFirstAncestorOfClass("Model")
	if model and model:GetAttribute("VehicleId") and WeaponService.OnVehicleHit then
		WeaponService.OnVehicleHit(player, model, cfg.Damage * WeaponConfig.FalloffFactor(cfg, (hitPosition - origin).Magnitude)
			* GameSettings.Get("DamageMultiplier"))
		return
	end

	-- Getroffenes Lebewesen suchen
	local targetHumanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return
	end

	local victim = Players:GetPlayerFromCharacter(model)
	local isBot = model:GetAttribute("IsBot") == true
	-- Kein Schaden an Spielern/Bots in anderen Modi oder an Teammitgliedern
	if victim and victim:GetAttribute("Mode") ~= player:GetAttribute("Mode") then
		return
	end
	if victim and victim.Team and victim.Team == player.Team then
		return
	end
	if isBot and model:GetAttribute("Mode") ~= player:GetAttribute("Mode") then
		return
	end
	if isBot and player.Team and model:GetAttribute("TeamName") == player.Team.Name then
		return
	end
	if pvpBlocked(player, victim) then
		return -- Safe Zone oder PvP-Zeit noch nicht erreicht (offene Welt)
	end

	-- Schaden: Körperteil (Kopf mehr, Arme/Beine weniger) und Entfernung (Fall-off)
	local headshot = hitPart.Name == "Head"
	local distance = (hitPosition - origin).Magnitude
	local damage = cfg.Damage * WeaponConfig.PartMultiplier(hitPart.Name) * WeaponConfig.FalloffFactor(cfg, distance)
		* GameSettings.Get("DamageMultiplier")
	local dealt, killed, downed, armor = Damage.Apply(model, targetHumanoid, damage,
		{ Player = player, Weapon = weaponName, Headshot = headshot })
	-- Passiv HAWK: getroffene Gegner kurz für das Team markieren
	if dealt > 0 and not killed and AgentConfig.PassiveOf(character, "MarkOnHit") then
		for _, mate in Players:GetPlayers() do
			if mate == player or (player.Team and mate.Team == player.Team and mate:GetAttribute("Mode") == player:GetAttribute("Mode")) then
				Remotes.Reveal:FireClient(mate, { model }, 2)
			end
		end
	end
	local victimName = victim and victim.Name or model.Name
	-- Spieler und Bots zählen als Kill (Test-Dummies nicht)
	if killed and (victim or isBot) then
		killedEvent:Fire(player, victim, weaponName, headshot, victimName, model)
	end
	return { Humanoid = targetHumanoid, Damage = dealt, Headshot = headshot, Killed = killed, Downed = downed,
		Armor = armor or 0, Position = hitPosition, Name = victimName, Model = model }
end

-- Schuss auswerten. aiming = Spieler zielt (Rechtsklick): weniger Streuung. Gibt true zurück, wenn geschossen.
local function fire(player, state, origin, direction, aiming, shotId, claims)
	-- CanFight setzt der Modus (z.B. aus zwischen Runden und im Hub)
	if not player:GetAttribute("CanFight") then
		return false
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return false
	end
	if not (direction.Magnitude > 0.01) then
		return false
	end

	local humanoid, character = getLivingHumanoid(player)
	local head = character and character:FindFirstChild("Head")
	if not humanoid or not head or character:GetAttribute("Downed") then
		return false
	end
	-- Ursprung muss nah am eigenen Kopf sein (sonst Schuss durch Wände möglich)
	if not ((origin - head.Position).Magnitude <= MAX_ORIGIN_DISTANCE) then
		return false
	end

	local weaponName = state.Current
	if not weaponName or character:GetAttribute("UsingItem") then
		return false -- keine Waffe in der Hand oder gerade beim Verbinden (offene Welt)
	end
	local effects = AttachmentConfig.Effects(player, weaponName)
	local cfg = WeaponConfig.WithAttachments(WeaponConfig.Get(weaponName), effects)
	local ammo = state.Ammo[weaponName]
	if ammo.Mag <= 0 or (state.Reloading and not cfg.ShellReload) then
		return false
	end
	-- Feuerrate mit kleinem Puffer: Schüsse, die durch Netzwerkschwankungen dicht hintereinander ankommen,
	-- zählen trotzdem, im Schnitt bleibt es bei der Feuerrate der Waffe
	local now = os.clock()
	local slack = math.min(0.08, cfg.FireDelay * 0.5)
	if now < state.NextShot - slack then
		return false
	end
	if state.Reloading then
		cancelReload(player, state) -- Schrotflinte: Schießen bricht das Nachladen ab
	end
	state.NextShot = math.max(state.NextShot, now - slack) + cfg.FireDelay
	ammo.Mag -= 1
	reportMag(state, ammo)
	if character:GetAttribute("Cloaked") then
		character:SetAttribute("Cloaked", false) -- Schießen verrät dich
	end

	-- Streuung: Waffe, Dauerfeuer (Bloom), Bewegung, Sprung, Zielen, Stabilisator (gleiche Formel wie das Fadenkreuz)
	local root = character:FindFirstChild("HumanoidRootPart")
	local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local bloom
	bloom, state.Bloom = WeaponConfig.StepBloom(cfg, state.Bloom, now - state.BloomTime)
	state.BloomTime = now
	local spreadAngle = WeaponConfig.SpreadFor(cfg, bloom, speed, isAirborne(character, root, humanoid), aiming, effects)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	-- Schulterkamera: Punkt unter dem Fadenkreuz suchen (erst ab Höhe des Kopfes, damit nichts zwischen
	-- Kamera und Charakter getroffen wird) und dann vom Kopf aus dorthin schießen
	local look = direction.Unit
	local shotOrigin, aimDirection = origin, look
	if (origin - head.Position).Magnitude > THIRD_PERSON_DISTANCE then
		local skip = math.max(0, (head.Position - origin):Dot(look))
		local start = origin + look * skip
		local aimHit = workspace:Raycast(start, look * cfg.Range, params)
		local aimPoint = aimHit and aimHit.Position or (start + look * cfg.Range)
		shotOrigin = head.Position
		if (aimPoint - shotOrigin).Magnitude > 0.5 then
			aimDirection = (aimPoint - shotOrigin).Unit
		end
	end

	-- Treffer pro Ziel zusammenfassen (Schrotflinte: eine Schadenszahl statt acht)
	-- Dieselben Kugelrichtungen wie beim Client (gemeinsamer Seed aus Spieler und Schuss-Nummer)
	local directions = WeaponConfig.PelletDirections(aimDirection, spreadAngle, cfg.Pellets or 1,
		WeaponConfig.ShotSeed(player.UserId, shotId or 0))
	claims = type(claims) == "table" and claims or {}
	local hits = {}
	for i, pelletDirection in directions do
		local hit = fireRay(player, character, shotOrigin, pelletDirection, cfg, weaponName, params, claims[i])
		if hit then
			local total = hits[hit.Humanoid]
			if total then
				total.Damage += hit.Damage
				total.Armor += hit.Armor
				total.Headshot = total.Headshot or hit.Headshot
				total.Killed = total.Killed or hit.Killed
				total.Downed = total.Downed or hit.Downed
			else
				hits[hit.Humanoid] = hit
			end
		end
	end
	ProgressService.AddStat(player, "ShotsFired", 1)
	if next(hits) then
		ProgressService.AddStat(player, "ShotsHit", 1)
	end
	for _, hit in hits do
		ProgressService.AddStat(player, "Damage", math.floor(hit.Damage + 0.5))
		player:SetAttribute("Damage", (player:GetAttribute("Damage") or 0) + math.floor(hit.Damage + 0.5))
		Remotes.Hitmarker:FireClient(player, hit.Headshot, hit.Killed, hit.Damage, hit.Position, hit.Name, hit.Downed,
			hit.Armor, hit.Model)
	end
	return true
end

-- shotId = laufende Nummer des Clients: Er rechnet damit seine Munitionsanzeige ohne Flackern vor
-- claims = vom Client gemeldete Treffer pro Kugel ({ Part, Position } oder false), werden geprüft
local function onFire(player, origin, direction, aiming, shotId, claims)
	local state = states[player]
	if not state then
		return
	end
	local validId = typeof(shotId) == "number" and shotId == shotId and math.abs(shotId) < 1e9
	if validId and shotId > (lastShotIds[player] or 0) then
		lastShotIds[player] = math.floor(shotId)
	end
	fire(player, state, origin, direction, aiming == true, validId and shotId or 0, claims)
	sendAmmo(player)
end

local function onReload(player)
	local state = states[player]
	if not state or state.Reloading then
		return
	end
	local humanoid, character = getLivingHumanoid(player)
	if not humanoid or character:GetAttribute("Downed") then
		sendAmmo(player)
		return
	end

	local weaponName = state.Current
	if not weaponName then
		sendAmmo(player)
		return
	end
	local effects = AttachmentConfig.Effects(player, weaponName)
	local cfg = WeaponConfig.WithAttachments(WeaponConfig.Get(weaponName), effects)
	local ammo = state.Ammo[weaponName]
	local source = state.Source
	local infinite = WeaponConfig.HasInfiniteAmmo(player) and not source
	-- Reserve: aus dem Inventar (offene Welt) oder vom Zustand
	local function reserveLeft()
		return source and source.Count() or ammo.Reserve
	end
	local function takeReserve(n)
		if infinite then
			return n
		end
		if source then
			return source.Take(n)
		end
		local taken = math.min(n, ammo.Reserve)
		ammo.Reserve -= taken
		return taken
	end
	if ammo.Mag >= ammo.Size or (reserveLeft() <= 0 and not infinite) then
		sendAmmo(player) -- Client hat schon "lädt nach" angezeigt: korrigieren
		return
	end

	state.Reloading = true
	state.ReloadId += 1
	local myId = state.ReloadId
	local duration = WeaponConfig.ReloadDuration(player, character, weaponName)
	-- Abbruch bei Waffenwechsel, Tod, Schuss (Schrotflinte) oder neuem Zustand
	local function stillValid()
		return states[player] == state and state.ReloadId == myId and state.Current == weaponName
	end

	if cfg.ShellReload then
		-- Patrone für Patrone, jede zählt sofort
		local start, per, finish = WeaponConfig.ShellTiming(cfg, duration)
		local shells = ammo.Size - ammo.Mag
		if not infinite then
			shells = math.min(shells, reserveLeft())
		end
		setReloadAttributes(player, duration, shells)
		sendAmmo(player)
		task.spawn(function()
			task.wait(start)
			for _ = 1, shells do
				task.wait(per)
				if not stillValid() then
					return
				end
				if takeReserve(1) <= 0 then
					break -- Munition inzwischen weg (z.B. verkauft)
				end
				ammo.Mag += 1
				reportMag(state, ammo)
				sendAmmo(player)
			end
			task.wait(finish)
			if not stillValid() then
				return
			end
			state.Reloading = false
			setReloadAttributes(player, nil)
			sendAmmo(player)
		end)
		return
	end

	setReloadAttributes(player, duration)
	sendAmmo(player)
	task.delay(duration, function()
		if not stillValid() then
			return
		end
		ammo.Mag += takeReserve(ammo.Size - ammo.Mag)
		reportMag(state, ammo)
		state.Reloading = false
		setReloadAttributes(player, nil)
		sendAmmo(player)
	end)
end

-- Waffe wechseln. Ohne gültigen Namen schickt der Server nur den aktuellen Stand.
local function onEquip(player, weaponName)
	local state = states[player]
	if not state then
		return
	end
	if typeof(weaponName) == "string" and table.find(state.Loadout, weaponName) and state.Current ~= weaponName then
		-- Wechsel bricht Nachladen ab
		cancelReload(player, state)
		state.Current = weaponName
		state.Bloom = 0
		-- Wartezeit einer langsamen Waffe nicht auf die neue übertragen (Ziehen dauert ohnehin kurz)
		state.NextShot = math.min(state.NextShot, os.clock() + 0.25)
	end
	showToolInHand(player)
	sendAmmo(player)
end

-- Blick nach oben/unten und Zielen des Spielers, damit alle Clients seine Arme passend bewegen
local function onAimState(player, pitch, aiming)
	if typeof(pitch) ~= "number" or pitch ~= pitch then
		return
	end
	local now = os.clock()
	if lastAimState[player] and now - lastAimState[player] < 0.05 then
		return
	end
	lastAimState[player] = now
	local character = player.Character
	if character then
		character:SetAttribute("AimPitch", math.clamp(math.round(pitch), -85, 85))
		character:SetAttribute("Aiming", aiming == true)
	end
end

local function setupPlayer(player)
	states[player] = newState(player)
	-- Bei jedem Spawn: volle Munition, Waffen des aktuellen Agenten
	local function onCharacter(character)
		local state = newState(player)
		states[player] = state
		character:WaitForChild("Humanoid")
		character:SetAttribute("Loadout", table.concat(state.Loadout, ","))
		if Modes.IsFighting(player) and #state.Loadout > 0 then
			giveTools(player, state)
		end
		sendAmmo(player)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

-- Messer: kurzer Stich nach vorne. Gegner am Boden werden sofort erledigt (Finish).
local lastMelee = {}
local function onMelee(player, origin, direction)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or not (direction.Magnitude > 0.01) then
		return
	end
	if not player:GetAttribute("CanFight") then
		return
	end
	local humanoid, character = getLivingHumanoid(player)
	local head = character and character:FindFirstChild("Head")
	if not humanoid or not head or character:GetAttribute("Downed") then
		return
	end
	if not ((origin - head.Position).Magnitude <= MAX_ORIGIN_DISTANCE) then
		return
	end
	local melee = WeaponConfig.Melee
	local now = os.clock()
	if lastMelee[player] and now - lastMelee[player] < melee.Cooldown * 0.9 then
		return
	end
	lastMelee[player] = now

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Spherecast(head.Position, melee.Radius, direction.Unit * melee.Range, params)
	local model = result and result.Instance:FindFirstAncestorOfClass("Model")
	local target = model and model:FindFirstChildOfClass("Humanoid")
	if not target or target.Health <= 0 then
		return
	end
	local victim = Players:GetPlayerFromCharacter(model)
	local isBot = model:GetAttribute("IsBot") == true
	local mode = player:GetAttribute("Mode")
	local victimMode = victim and victim:GetAttribute("Mode") or model:GetAttribute("Mode")
	local victimTeam = victim and victim.Team and victim.Team.Name or model:GetAttribute("TeamName")
	local isDummy = model:GetAttribute("IsDummy") == true or model:GetAttribute("IsZombie") == true
	if not isDummy and ((not victim and not isBot) or victimMode ~= mode or (player.Team and victimTeam == player.Team.Name)) then
		return
	end
	if pvpBlocked(player, victim) then
		return
	end

	-- Am Boden: Finish mit vollem Restleben
	local amount = model:GetAttribute("Downed") and target.Health + 1 or melee.Damage * GameSettings.Get("DamageMultiplier")
	local dealt, killed, downed, armor = Damage.Apply(model, target, amount, { Player = player, Weapon = melee.DisplayName })
	local victimName = victim and victim.Name or model.Name
	player:SetAttribute("Damage", (player:GetAttribute("Damage") or 0) + math.floor(dealt + 0.5))
	Remotes.Hitmarker:FireClient(player, false, killed, dealt, result.Position, victimName, downed, armor, model)
	if killed then
		killedEvent:Fire(player, victim, melee.DisplayName, false, victimName, model)
	end
end

-- ---------- Offene Welt (Extinction): Waffe aus dem Inventar ----------

-- Waffe in die Hand geben (weaponName = WeaponConfig-Name) oder wegstecken (nil). mag = Magazin des Items,
-- source = { Count = function() -> Reserve, Take = function(n) -> genommen, SetMag = function(mag) } (Inventar)
function WeaponService.SetCarried(player, weaponName, mag, source)
	local state = states[player]
	if not state then
		return false
	end
	if weaponName and not WeaponConfig.Get(weaponName) then
		return false
	end
	cancelReload(player, state)
	for _, tool in state.Tools or {} do
		tool:Destroy()
	end
	state.Tools = {}
	state.Source = source
	state.Bloom = 0
	if weaponName then
		local cfg = WeaponConfig.Get(weaponName)
		local size = math.floor(cfg.MagazineSize * AttachmentConfig.Effects(player, weaponName).Mag)
		state.Loadout = { weaponName }
		state.Current = weaponName
		state.Ammo = { [weaponName] = { Mag = math.clamp(math.floor(tonumber(mag) or size), 0, size), Reserve = 0, Size = size } }
		state.NextShot = math.max(state.NextShot, os.clock() + 0.3) -- Waffe ziehen
	else
		state.Loadout = {}
		state.Current = nil
		state.Ammo = {}
	end
	local character = player.Character
	if character then
		character:SetAttribute("Loadout", table.concat(state.Loadout, ","))
	end
	if weaponName and character then
		giveTools(player, state)
	end
	sendAmmo(player)
	return true
end

-- Magazin der Waffe in der Hand (nil = keine)
function WeaponService.CarriedMag(player)
	local state = states[player]
	local ammo = state and state.Current and state.Ammo[state.Current]
	return ammo and ammo.Mag or nil
end

-- Waffe in der Hand (WeaponConfig-Name) oder nil
function WeaponService.CarriedWeapon(player)
	local state = states[player]
	return state and state.Current or nil
end

-- Munitionsanzeige neu schicken (z.B. nachdem sich die Munition im Inventar geändert hat)
function WeaponService.RefreshAmmo(player)
	sendAmmo(player)
end

-- Kill von außerhalb melden (z.B. Granate), läuft wie ein Waffen-Kill
function WeaponService.ReportKill(killer, victim, weaponName, headshot, victimName, victimModel)
	killedEvent:Fire(killer, victim, weaponName, headshot, victimName, victimModel)
end

function WeaponService.Init()
	Remotes.Fire.OnServerEvent:Connect(onFire)
	Remotes.Reload.OnServerEvent:Connect(onReload)
	Remotes.Equip.OnServerEvent:Connect(onEquip)
	Remotes.Melee.OnServerEvent:Connect(onMelee)
	Remotes.AimState.OnServerEvent:Connect(onAimState)

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		lastMelee[player] = nil
		lastShotIds[player] = nil
		lastAimState[player] = nil
	end)
end

return WeaponService

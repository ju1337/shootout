-- WeaponService (ModuleScript, nur Server)
-- Verwaltet Munition, Nachladen, Waffenwechsel und berechnet Schaden.
-- Der Client schickt nur "ich schieße von A in Richtung B", alles andere prüft der Server.
-- Welche Waffen ein Spieler hat, kommt vom gewählten Agenten (AgentConfig.Loadout).

local Players = game:GetService("Players")
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
local BuyConfig = require(Shared.BuyConfig)
local Damage = require(ServerStorage:WaitForChild("ServerShared").Damage)

local WeaponService = {}

-- Wird gefeuert, wenn ein Spieler einen anderen Spieler tötet:
-- (killer: Player, victim: Player oder nil bei Bots, weaponName, headshot, victimName)
local killedEvent = Instance.new("BindableEvent")
WeaponService.Killed = killedEvent.Event

-- Wie weit der gemeldete Schussursprung vom Kopf entfernt sein darf (Anti-Cheat, Studs)
local MAX_ORIGIN_DISTANCE = 15

local states = {} -- [Player] = { Loadout, Current, Ammo, LastShot, Reloading, ReloadId, Tools }
local random = Random.new()

local function selectedAgent(player)
	return AgentConfig.Get(player:GetAttribute("Agent")) or AgentConfig.Agents[1]
end

local function newState(player)
	local loadout = selectedAgent(player).Loadout
	local state = {
		Loadout = loadout,
		Current = loadout[1],
		Ammo = {},
		LastShot = 0,
		Reloading = false,
		ReloadId = 0,
	}
	for _, name in loadout do
		local cfg = WeaponConfig.Get(name)
		-- Gekauftes "Großes Magazin" (Drop) vergrößert jedes Magazin
		local size = math.floor(cfg.MagazineSize * (BuyConfig.Has(player, "Mag") and BuyConfig.MagFactor or 1))
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
	local ammo = state.Ammo[state.Current]
	Remotes.AmmoUpdate:FireClient(player, state.Current, ammo.Mag, ammo.Reserve, state.Reloading, ammo.Size)
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
		local tool = GunModels.BuildTool(name, WeaponConfig.Get(name).DisplayName, skin)
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

-- Richtung zufällig im Kegel streuen (Grad)
local function spread(direction, degrees)
	if not degrees or degrees <= 0 then
		return direction.Unit
	end
	local angle = math.rad(degrees) * math.sqrt(random:NextNumber())
	local spin = random:NextNumber() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)).LookVector
end

-- Ein einzelner Schuss/Kugel: Raycast, Effekt, Schaden.
-- Gibt bei einem Treffer { Humanoid, Damage, Headshot, Killed, Position, Name } zurück.
local function fireRay(player, character, origin, direction, cfg, weaponName)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(origin, direction * cfg.Range, params)
	local endPos = result and result.Position or (origin + direction * cfg.Range)
	Remotes.Shot:FireAllClients(player, origin, endPos)
	if not result then
		return
	end

	-- Getroffenes Lebewesen suchen
	local model = result.Instance:FindFirstAncestorOfClass("Model")
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

	local headshot = result.Instance.Name == "Head"
	local damage = cfg.Damage * (headshot and WeaponConfig.HeadshotMultiplier or 1) * GameSettings.Get("DamageMultiplier")
	local dealt, killed, downed = Damage.Apply(model, targetHumanoid, damage,
		{ Player = player, Weapon = weaponName, Headshot = headshot })
	local victimName = victim and victim.Name or model.Name
	-- Spieler und Bots zählen als Kill (Test-Dummies nicht)
	if killed and (victim or isBot) then
		killedEvent:Fire(player, victim, weaponName, headshot, victimName)
	end
	return { Humanoid = targetHumanoid, Damage = dealt, Headshot = headshot, Killed = killed, Downed = downed,
		Position = result.Position, Name = victimName }
end

-- Schuss auswerten. aiming = Spieler zielt (Rechtsklick): weniger Streuung
local function onFire(player, origin, direction, aiming)
	local state = states[player]
	-- CanFight setzt der Modus (z.B. aus zwischen Runden und im Hub)
	if not state or not player:GetAttribute("CanFight") then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if not (direction.Magnitude > 0.01) then
		return
	end

	local humanoid, character = getLivingHumanoid(player)
	local head = character and character:FindFirstChild("Head")
	if not humanoid or not head or character:GetAttribute("Downed") then
		return
	end
	-- Ursprung muss nah am eigenen Kopf sein (sonst Schuss durch Wände möglich)
	if not ((origin - head.Position).Magnitude <= MAX_ORIGIN_DISTANCE) then
		return
	end

	local cfg = WeaponConfig.Get(state.Current)
	local ammo = state.Ammo[state.Current]
	local now = os.clock()
	if state.Reloading or ammo.Mag <= 0 then
		return
	end
	-- Feuerrate prüfen (10% Toleranz wegen Netzwerkschwankungen)
	if now - state.LastShot < cfg.FireDelay * 0.9 then
		return
	end
	state.LastShot = now
	ammo.Mag -= 1

	local spreadAngle = (cfg.Spread or 0) * (aiming == true and WeaponConfig.AimSpreadFactor or 1)
		* (BuyConfig.Has(player, "Stability") and BuyConfig.StabilityFactor or 1)
	-- Treffer pro Ziel zusammenfassen (Schrotflinte: eine Schadenszahl statt acht)
	local hits = {}
	for _ = 1, cfg.Pellets or 1 do
		local hit = fireRay(player, character, origin, spread(direction, spreadAngle), cfg, state.Current)
		if hit then
			local total = hits[hit.Humanoid]
			if total then
				total.Damage += hit.Damage
				total.Headshot = total.Headshot or hit.Headshot
				total.Killed = total.Killed or hit.Killed
				total.Downed = total.Downed or hit.Downed
			else
				hits[hit.Humanoid] = hit
			end
		end
	end
	for _, hit in hits do
		player:SetAttribute("Damage", (player:GetAttribute("Damage") or 0) + math.floor(hit.Damage + 0.5))
		Remotes.Hitmarker:FireClient(player, hit.Headshot, hit.Killed, hit.Damage, hit.Position, hit.Name, hit.Downed)
	end
	sendAmmo(player)
end

local function onReload(player)
	local state = states[player]
	if not state or state.Reloading then
		return
	end
	if not getLivingHumanoid(player) then
		return
	end

	local weaponName = state.Current
	local cfg = WeaponConfig.Get(weaponName)
	local ammo = state.Ammo[weaponName]
	if ammo.Mag >= ammo.Size or ammo.Reserve <= 0 then
		return
	end

	state.Reloading = true
	state.ReloadId += 1
	local myId = state.ReloadId
	sendAmmo(player)

	local reloadTime = cfg.ReloadTime * (BuyConfig.Has(player, "Reload") and BuyConfig.ReloadFactor or 1)
	task.delay(reloadTime, function()
		-- Abbruch bei Waffenwechsel, Tod oder neuem Zustand
		if states[player] ~= state or state.ReloadId ~= myId then
			return
		end
		local take = math.min(ammo.Size - ammo.Mag, ammo.Reserve)
		ammo.Mag += take
		ammo.Reserve -= take
		state.Reloading = false
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
		state.ReloadId += 1
		state.Reloading = false
		state.Current = weaponName
	end
	showToolInHand(player)
	sendAmmo(player)
end

local function setupPlayer(player)
	states[player] = newState(player)
	-- Bei jedem Spawn: volle Munition, Waffen des aktuellen Agenten
	local function onCharacter(character)
		local state = newState(player)
		states[player] = state
		character:WaitForChild("Humanoid")
		character:SetAttribute("Loadout", table.concat(state.Loadout, ","))
		if Modes.IsFighting(player) then
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
	local isDummy = model:GetAttribute("IsDummy") == true
	if not isDummy and ((not victim and not isBot) or victimMode ~= mode or (player.Team and victimTeam == player.Team.Name)) then
		return
	end

	-- Am Boden: Finish mit vollem Restleben
	local amount = model:GetAttribute("Downed") and target.Health + 1 or melee.Damage * GameSettings.Get("DamageMultiplier")
	local dealt, killed, downed = Damage.Apply(model, target, amount, { Player = player, Weapon = melee.DisplayName })
	local victimName = victim and victim.Name or model.Name
	player:SetAttribute("Damage", (player:GetAttribute("Damage") or 0) + math.floor(dealt + 0.5))
	Remotes.Hitmarker:FireClient(player, false, killed, dealt, result.Position, victimName, downed)
	if killed then
		killedEvent:Fire(player, victim, melee.DisplayName, false, victimName)
	end
end

-- Kill von außerhalb melden (z.B. Granate), läuft wie ein Waffen-Kill
function WeaponService.ReportKill(killer, victim, weaponName, headshot, victimName)
	killedEvent:Fire(killer, victim, weaponName, headshot, victimName)
end

function WeaponService.Init()
	Remotes.Fire.OnServerEvent:Connect(onFire)
	Remotes.Reload.OnServerEvent:Connect(onReload)
	Remotes.Equip.OnServerEvent:Connect(onEquip)
	Remotes.Melee.OnServerEvent:Connect(onMelee)

	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		lastMelee[player] = nil
	end)
end

return WeaponService

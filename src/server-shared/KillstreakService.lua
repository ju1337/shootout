-- KillstreakService (ModuleScript, nur Server)
-- Killstreak-Belohnungen in Herrschaft (KillstreakConfig): Kills ohne zu sterben schalten sie frei, dann liegen sie
-- bereit, bis der Spieler sie auslöst (Remotes.UseKillstreak, Tasten 4/5/6 – KillstreakHUD rechts am Rand).
--   5 Kills   DROHNE        alle Gegner 10 s fürs eigene Team markiert (durch Wände)
--   8 Kills   LUFTSCHLAG    roter Kreis dort, wohin man zielt (sonst größte Gegnergruppe), nach 3 s Einschlag
--  12 Kills   SCHUTZSCHILD  eigenes Team: volles Leben, volle Rüstung und 4 s unverwundbar
-- Spieler-Attribute: Killstreak (Kills dieses Lebens), KillstreakReady (JSON { [Id] = true }).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local BuyConfig = require(Shared.BuyConfig)
local KillstreakConfig = require(Shared.KillstreakConfig)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local KillService = require(ServerShared.KillService)
local Damage = require(ServerShared.Damage)
local WeaponService = require(ServerShared.WeaponService)

local KillstreakService = {}

local MODES = KillstreakConfig.Modes
local MAX_AIM_DISTANCE = 400 -- so weit darf der Zielpunkt des Luftschlags vom Spieler weg sein
local RADAR_TIME = 10
local STRIKE_DELAY = 3
local STRIKE_RADIUS = 16
local STRIKE_DAMAGE = 160
local SHIELD_TIME = 4

local function teamName(player)
	return player.Team and player.Team.Name
end

local function living(model)
	local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.Health > 0 and humanoid or nil
end

-- Lebende Gegner (Spieler und Bots) im selben Modus
local function enemies(owner)
	local mode, team = owner:GetAttribute("Mode"), teamName(owner)
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= owner and other:GetAttribute("Mode") == mode and teamName(other) ~= team and living(other.Character) then
			table.insert(list, other.Character)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, model in bots:GetChildren() do
			if model:GetAttribute("Mode") == mode and model:GetAttribute("TeamName") ~= team and living(model) then
				table.insert(list, model)
			end
		end
	end
	return list
end

-- Mitspieler (inkl. owner) im selben Modus und Team
local function teammates(owner)
	local list = {}
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Mode") == owner:GetAttribute("Mode") and teamName(other) == teamName(owner) then
			table.insert(list, other)
		end
	end
	return list
end

-- Meldung an alle im Modus: eigene Seite blau, Gegner rot
local function announce(owner, text)
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Mode") == owner:GetAttribute("Mode") then
			local mine = teamName(other) == teamName(owner)
			Remotes.Notify:FireClient(other, "Objective", { Text = text .. "  ·  " .. owner.Name, Side = mine and "Ally" or "Alert",
				Icon = "!" })
		end
	end
end

local function radar(owner)
	local targets = enemies(owner)
	for _, mate in teammates(owner) do
		Remotes.Reveal:FireClient(mate, targets, RADAR_TIME)
	end
	announce(owner, "DROHNE AKTIV")
end

local function airstrike(owner, aim)
	local targets = enemies(owner)
	-- Ziel: gezielter Punkt (vom Client, geprüft), sonst Gegner mit den meisten anderen Gegnern in der Nähe
	local root0 = owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
	local best, bestCount = nil, -1
	if typeof(aim) == "Vector3" and root0 and (aim - root0.Position).Magnitude <= MAX_AIM_DISTANCE then
		best, bestCount = aim + Vector3.new(0, 2.8, 0), math.huge
	end
	for _, model in targets do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and bestCount ~= math.huge then
			local n = 0
			for _, other in targets do
				local otherRoot = other:FindFirstChild("HumanoidRootPart")
				if otherRoot and (otherRoot.Position - root.Position).Magnitude <= STRIKE_RADIUS then
					n += 1
				end
			end
			if n > bestCount then
				best, bestCount = root.Position, n
			end
		end
	end
	if not best then
		return
	end
	local ground = best - Vector3.new(0, 2.8, 0)
	-- Warnkreis für alle sichtbar
	local marker = Instance.new("Part")
	marker.Name = "AirstrikeMarker"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.4, STRIKE_RADIUS * 2, STRIKE_RADIUS * 2)
	marker.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 60, 50)
	marker.Transparency = 0.55
	marker.Parent = workspace
	Debris:AddItem(marker, STRIKE_DELAY + 0.5)
	announce(owner, "LUFTSCHLAG IM ANFLUG")
	task.delay(STRIKE_DELAY, function()
		for i = 1, 4 do
			local offset = Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
			local explosion = Instance.new("Explosion")
			explosion.Position = ground + offset
			explosion.BlastRadius = 8
			explosion.BlastPressure = 0
			explosion.DestroyJointRadiusPercent = 0
			explosion.ExplosionType = Enum.ExplosionType.NoCraters
			explosion.Parent = workspace
			if i < 4 then
				task.wait(0.12)
			end
		end
		if not owner.Parent then
			return
		end
		-- Schaden nur im Freien: von oben muss der Weg frei sein (Dächer schützen)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace:FindFirstChild("Maps") }
		for _, model in enemies(owner) do
			local root = model:FindFirstChild("HumanoidRootPart")
			local humanoid = living(model)
			local distance = root and (Vector3.new(root.Position.X, ground.Y, root.Position.Z) - ground).Magnitude or math.huge
			if humanoid and distance <= STRIKE_RADIUS then
				local covered = workspace:Raycast(root.Position + Vector3.new(0, 3, 0), Vector3.new(0, 60, 0), params)
				if not covered then
					local victim = Players:GetPlayerFromCharacter(model)
					local victimName = victim and victim.Name or model.Name
					local amount = STRIKE_DAMAGE * (1 - distance / STRIKE_RADIUS * 0.5)
					local dealt, killed, downed, armor = Damage.Apply(model, humanoid, amount,
						{ Player = owner, Weapon = "Luftschlag" })
					Remotes.Hitmarker:FireClient(owner, false, killed, dealt, root.Position, victimName, downed, armor, model)
					if killed then
						WeaponService.ReportKill(owner, victim, "Luftschlag", false, victimName, model)
					end
				end
			end
		end
	end)
end

local function shield(owner)
	for _, mate in teammates(owner) do
		local character = mate.Character
		local humanoid = living(character)
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
			character:SetAttribute("Armor", BuyConfig.ArmorAmount)
			local field = Instance.new("ForceField")
			field.Visible = true
			field.Parent = character
			Debris:AddItem(field, SHIELD_TIME)
		end
	end
	announce(owner, "SCHUTZSCHILD FÜRS TEAM")
end

local ACTIONS = { Radar = radar, Airstrike = airstrike, Shield = shield }

local ready = {} -- [Player] = { [Id] = true }

local function publish(player)
	player:SetAttribute("KillstreakReady", HttpService:JSONEncode(ready[player] or {}))
end

local function reset(player)
	ready[player] = {}
	player:SetAttribute("Killstreak", 0)
	publish(player)
end

function KillstreakService.Init()
	local function watch(player)
		reset(player)
		player.CharacterAdded:Connect(function(character)
			player:SetAttribute("Killstreak", 0)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid then
				humanoid.Died:Connect(function()
					player:SetAttribute("Killstreak", 0) -- Serie zählt neu, bereite Belohnungen bleiben
				end)
			end
		end)
		player:GetAttributeChangedSignal("Mode"):Connect(function()
			reset(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
	end)
	-- Kills zählen, Belohnungen freischalten
	KillService.KillCounted:Connect(function(killer, victim)
		if typeof(killer) ~= "Instance" or not killer:IsA("Player") or victim == killer then
			return
		end
		if not MODES[killer:GetAttribute("Mode")] then
			return
		end
		local count = (tonumber(killer:GetAttribute("Killstreak")) or 0) + 1
		killer:SetAttribute("Killstreak", count)
		for _, streak in KillstreakConfig.List do
			if count == streak.Kills then
				ready[killer] = ready[killer] or {}
				ready[killer][streak.Id] = true
				publish(killer)
				Remotes.Notify:FireClient(killer, "Banner", { Caption = "Killserie " .. count, Title = streak.Name .. " BEREIT",
					Sub = "Rechts am Rand auslösen", Style = "Info" })
			end
		end
	end)
	-- Auslösen: nur bereit, im Modus und lebend
	Remotes.UseKillstreak.OnServerEvent:Connect(function(player, id, aim)
		local action = type(id) == "string" and ACTIONS[id]
		if not action or not (ready[player] and ready[player][id]) or not MODES[player:GetAttribute("Mode")] then
			return
		end
		if not living(player.Character) or player:GetAttribute("CanFight") == false then
			return
		end
		ready[player][id] = nil
		publish(player)
		task.spawn(action, player, aim)
	end)
end

return KillstreakService

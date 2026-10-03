-- KillstreakService (ModuleScript, nur Server)
-- Killstreak-Belohnungen in Herrschaft: Kills ohne zu sterben lösen automatisch aus.
--   4 Kills   RADAR         alle Gegner 10 s fürs eigene Team markiert (durch Wände)
--   7 Kills   LUFTSCHLAG    roter Kreis auf der größten Gegnergruppe, nach 3 s Einschlag (nur im Freien)
--  10 Kills   SCHUTZSCHILD  eigenes Team: volles Leben, volle Rüstung und 4 s unverwundbar
-- Spieler-Attribut "Killstreak" (Kills dieses Lebens) für die Anzeige im HUD (AbilityClient).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local BuyConfig = require(Shared.BuyConfig)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local KillService = require(ServerShared.KillService)
local Damage = require(ServerShared.Damage)
local WeaponService = require(ServerShared.WeaponService)

local KillstreakService = {}

KillstreakService.Streaks = {
	{ Kills = 4, Id = "Radar", Name = "RADAR" },
	{ Kills = 7, Id = "Airstrike", Name = "LUFTSCHLAG" },
	{ Kills = 10, Id = "Shield", Name = "SCHUTZSCHILD" },
}
local MODES = { Domination = true }
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
	announce(owner, "RADAR AKTIV")
end

local function airstrike(owner)
	local targets = enemies(owner)
	if #targets == 0 then
		return
	end
	-- Ziel: Gegner mit den meisten anderen Gegnern in der Nähe
	local best, bestCount = nil, -1
	for _, model in targets do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
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

function KillstreakService.Init()
	local function watch(player)
		player:SetAttribute("Killstreak", 0)
		player.CharacterAdded:Connect(function(character)
			player:SetAttribute("Killstreak", 0)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid then
				humanoid.Died:Connect(function()
					player:SetAttribute("Killstreak", 0)
				end)
			end
		end)
		player:GetAttributeChangedSignal("Mode"):Connect(function()
			player:SetAttribute("Killstreak", 0)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	KillService.KillCounted:Connect(function(killer, victim)
		if typeof(killer) ~= "Instance" or not killer:IsA("Player") or victim == killer then
			return
		end
		if not MODES[killer:GetAttribute("Mode")] then
			return
		end
		local count = (killer:GetAttribute("Killstreak") or 0) + 1
		killer:SetAttribute("Killstreak", count)
		for _, streak in KillstreakService.Streaks do
			if count == streak.Kills then
				Remotes.Notify:FireClient(killer, "Banner", { Caption = "Killserie " .. count, Title = streak.Name,
					Sub = "Belohnung ausgelöst", Style = "Info" })
				task.spawn(ACTIONS[streak.Id], killer)
			end
		end
	end)
end

return KillstreakService

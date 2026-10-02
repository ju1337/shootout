-- Bomb (ModuleScript, nur Server) – Ziel für Demolition
-- Angreifer bringen eine Bombe zu Ziel A oder B und legen sie (E halten). Danach läuft
-- der Bomben-Timer; Verteidiger müssen entschärfen (E halten, Timer pausiert dabei).
--   Bombe explodiert      -> Angreifer gewinnen
--   Bombe entschärft      -> Verteidiger gewinnen
--   Zeit abgelaufen       -> Verteidiger gewinnen (solange nichts gelegt ist)
--   Alle Gegner raus      -> wie gewohnt (gelegte Bombe muss trotzdem entschärft werden)
-- Stirbt der Träger, fällt die Bombe zu Boden; ein Angreifer hebt sie durch Drüberlaufen auf.
-- Nach der ersten Hälfte (RoundsToWin - 1 Runden) wechseln die Seiten.
-- Spieler-Attribute: ObjHint (Hinweis "[E] halten: ..."), ActionProgress (0 bis 1)
-- Part-Attribut fürs HUD: Planted (true) am Zielbereich mit der gelegten Bombe

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local GameSettings = require(Shared.GameSettings)
local BuyService = require(ServerStorage:WaitForChild("ServerShared").BuyService)
local ProgressService = require(ServerStorage:WaitForChild("ServerShared").ProgressService)

local PLANT_TIME = 4         -- Sekunden E halten zum Legen
local DEFUSE_TIME = 6        -- Sekunden E halten zum Entschärfen
local SITE_RADIUS = 10       -- Größe der Zielbereiche A/B
local PICKUP_RANGE = 4       -- Bombe aufheben (Angreifer)
local DEFUSE_RANGE = 5       -- Abstand zum Entschärfen
local REWARD = 300           -- Geld fürs Legen bzw. Entschärfen

-- Wer hält gerade E? (gilt für das aktuelle Ziel des Spielers)
local holding = {}
Remotes.ObjectiveAction.OnServerEvent:Connect(function(player, isHolding)
	holding[player] = isHolding == true or nil
end)
Players.PlayerRemoving:Connect(function(player)
	holding[player] = nil
end)

local function rootOf(model)
	return model and model.Parent and model:FindFirstChild("HumanoidRootPart")
end

local function bombPart(position, parent)
	local part = Instance.new("Part")
	part.Name = "Bomb"
	part.Size = Vector3.new(1.6, 0.8, 1.2)
	part.Color = Color3.fromRGB(220, 40, 40)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Position = position
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 50, 50)
	light.Range = 12
	light.Parent = part
	part.Parent = parent
	return part
end

return function(api)
	local objective = {}

	local sites = {}
	-- Zielbereiche der aktuellen Map (Map-Rotation: kann sich pro Match ändern)
	local function loadSites()
		local objectiveFolder = api.GetMap():WaitForChild("Objective")
		sites.A = objectiveFolder:WaitForChild("SiteA")
		sites.B = objectiveFolder:WaitForChild("SiteB")
	end
	loadSites()
	local attackers, defenders = api.TeamA, api.TeamB
	local carrier = nil          -- Modell, das die Bombe trägt
	local dropped = nil          -- Bombe am Boden (Part)
	local planted = nil          -- gelegte Bombe (Part)
	local plantedSite = nil
	local bombTimer = 0
	local plantProgress = 0
	local defuseProgress = 0
	local botTargetSite = "A"    -- Ziel der Angreifer-Bots in dieser Runde

	-- In welchem Zielbereich steht position? ("A", "B" oder nil)
	local function siteAt(position)
		for name, part in sites do
			local offset = position - part.Position
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= SITE_RADIUS and math.abs(offset.Y) < 10 then
				return name
			end
		end
		return nil
	end

	local function entryOf(model)
		for _, team in { attackers, defenders } do
			for _, entry in api.Participants(team) do
				if entry.Model == model then
					return entry
				end
			end
		end
		return nil
	end

	local function giveBomb(model)
		if dropped then
			dropped:Destroy()
			dropped = nil
		end
		carrier = model
		model:SetAttribute("HasBomb", true)
		-- Rucksack mit der Bombe am Rücken (für alle sichtbar)
		local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
		if torso then
			local pack = bombPart(Vector3.zero, model)
			pack.Name = "BombPack"
			pack.Anchored = false
			pack.Massless = true
			pack.CFrame = torso.CFrame * CFrame.new(0, 0, torso.Size.Z / 2 + 0.4)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = pack
			weld.Parent = pack
		end
	end

	local function dropBomb()
		local root = rootOf(carrier)
		local position = root and root.Position or sites.A.Position
		if carrier then
			carrier:SetAttribute("HasBomb", nil)
			local pack = carrier:FindFirstChild("BombPack")
			if pack then
				pack:Destroy()
			end
		end
		carrier = nil
		dropped = bombPart(position - Vector3.new(0, 2.4, 0), api.GetMap())
		api.Notify("Objective", function(player)
			local mine = player.Team == attackers
			return { Text = mine and "Bombe verloren  ·  aufheben!" or "Bombe fallen gelassen",
				Side = mine and "Alert" or "Ally", Icon = "!" }
		end)
	end

	local function plant(site, position, entry)
		if carrier then
			carrier:SetAttribute("HasBomb", nil)
			local pack = carrier:FindFirstChild("BombPack")
			if pack then
				pack:Destroy()
			end
		end
		carrier = nil
		planted = bombPart(position - Vector3.new(0, 2.4, 0), api.GetMap())
		plantedSite = site
		sites[site]:SetAttribute("Planted", true)
		bombTimer = GameSettings.Get("BombTime")
		defuseProgress = 0
		api.Notify("Objective", function(player)
			local mine = player.Team == attackers
			return { Text = "Bombe bei " .. site .. " gelegt  ·  " .. (mine and "verteidigen!" or "entschärfen!"),
				Side = mine and "Ally" or "Enemy", Icon = site }
		end)
		if entry and entry.Player then
			BuyService.AddMoney(entry.Player, REWARD, "Bombe gelegt")
			ProgressService.AddStat(entry.Player, "Plants", 1)
			Remotes.Notify:FireClient(entry.Player, "Medal",
				{ { Id = "BombPlanted", Sub = "Ziel " .. site .. "  ·  +" .. REWARD .. " $" } })
		end
	end

	local function cleanup()
		for _, part in { dropped, planted } do
			if part then
				part:Destroy()
			end
		end
		if carrier then
			carrier:SetAttribute("HasBomb", nil)
			local pack = carrier:FindFirstChild("BombPack")
			if pack then
				pack:Destroy()
			end
		end
		carrier, dropped, planted, plantedSite = nil, nil, nil, nil
		for _, part in sites do
			part:SetAttribute("Planted", nil)
		end
		plantProgress, defuseProgress = 0, 0
		for _, team in { attackers, defenders } do
			for _, entry in api.Participants(team) do
				if entry.Player then
					entry.Player:SetAttribute("ObjHint", nil)
					entry.Player:SetAttribute("ActionProgress", nil)
				elseif entry.Bot then
					entry.Bot.Objective = nil
				end
			end
		end
	end

	-- ---------- Rundenablauf ----------

	function objective.RoundStart(roundNumber)
		cleanup()
		loadSites()
		local half = math.max(1, api.RoundsToWin() - 1)
		attackers = roundNumber <= half and api.TeamA or api.TeamB
		defenders = api.OtherTeam(attackers)
		if roundNumber == half + 1 then
			api.Notify("Objective", function(player)
				local attacking = player.Team == attackers
				return { Text = "Seitenwechsel  ·  " .. (attacking and "ihr greift jetzt an" or "ihr verteidigt jetzt"),
					Side = "Alert", Icon = "!" }
			end)
		end
		botTargetSite = math.random() < 0.5 and "A" or "B"
	end

	function objective.SpawnFolder(team)
		return team == attackers and "SpawnsAtk" or "SpawnsDef"
	end

	-- Bombe an einen Angreifer geben (Spieler bevorzugt)
	function objective.AfterSpawn()
		local players, bots = {}, {}
		for _, entry in api.Participants(attackers) do
			if entry.Model and api.IsActive(entry.Model) then
				table.insert(entry.Player and players or bots, entry.Model)
			end
		end
		local pool = #players > 0 and players or bots
		if #pool > 0 then
			giveBomb(pool[math.random(#pool)])
		end
	end

	function objective.Tick(dt)
		local hints = {} -- [Player] = { Text, Progress }

		-- Träger tot oder am Boden: Bombe fällt
		if carrier and not api.IsActive(carrier) then
			dropBomb()
		end
		-- Aufheben durch Drüberlaufen
		if dropped then
			for _, entry in api.Participants(attackers) do
				local root = rootOf(entry.Model)
				if root and api.IsActive(entry.Model) and (root.Position - dropped.Position).Magnitude <= PICKUP_RANGE + 2 then
					giveBomb(entry.Model)
					break
				end
			end
		end

		-- Legen (Spieler halten E, Bots legen automatisch)
		if not planted and carrier then
			local entry = entryOf(carrier)
			local root = rootOf(carrier)
			local site = root and siteAt(root.Position)
			if site and entry then
				local acting = (entry.Player and holding[entry.Player]) or entry.Bot ~= nil
				plantProgress = acting and plantProgress + dt / PLANT_TIME or 0
				if entry.Player then
					hints[entry.Player] = { "[E] halten: Bombe bei " .. site .. " legen", plantProgress }
				end
				if plantProgress >= 1 then
					plant(site, root.Position, entry)
				end
			else
				plantProgress = 0
				if entry and entry.Player then
					hints[entry.Player] = { "Du trägst die Bombe – bring sie zu A oder B", nil }
				end
			end
		end

		-- Entschärfen (Timer pausiert, solange jemand entschärft)
		if planted then
			local defusing = false
			for _, entry in api.Participants(defenders) do
				local root = rootOf(entry.Model)
				if root and api.IsActive(entry.Model) and (root.Position - planted.Position).Magnitude <= DEFUSE_RANGE then
					local acting = (entry.Player and holding[entry.Player]) or entry.Bot ~= nil
					if acting and not defusing then
						defusing = true
						defuseProgress += dt / DEFUSE_TIME
						if defuseProgress >= 1 then
							if entry.Player then
								BuyService.AddMoney(entry.Player, REWARD, "Bombe entschärft")
								ProgressService.AddStat(entry.Player, "Defuses", 1)
								Remotes.Notify:FireClient(entry.Player, "Medal",
									{ { Id = "BombDefused", Sub = "+" .. REWARD .. " $" } })
							end
							api.EndRound(defenders, "Bombe entschärft")
							return
						end
					end
					if entry.Player then
						hints[entry.Player] = { "[E] halten: Bombe entschärfen", defuseProgress }
					end
				end
			end
			if not defusing then
				defuseProgress = 0
				bombTimer -= dt
			end
			if bombTimer <= 0 then
				local explosion = Instance.new("Explosion")
				explosion.Position = planted.Position
				explosion.BlastRadius = 30
				explosion.BlastPressure = 0
				explosion.DestroyJointRadiusPercent = 0
				explosion.Parent = workspace
				api.EndRound(attackers, "Bombe explodiert")
				return
			end
		end

		-- Ziele der Bots
		local carrierRoot = rootOf(carrier)
		for _, entry in api.Participants(attackers) do
			if entry.Bot then
				entry.Bot.Objective = (planted and planted.Position) or (dropped and dropped.Position)
					or (entry.Model == carrier and sites[botTargetSite].Position)
					or (carrierRoot and carrierRoot.Position) or sites[botTargetSite].Position
			end
		end
		for i, entry in api.Participants(defenders) do
			if entry.Bot then
				entry.Bot.Objective = planted and planted.Position or sites[i % 2 == 0 and "A" or "B"].Position
			end
		end

		-- Hinweise und Status an alle
		for _, team in { attackers, defenders } do
			for _, entry in api.Participants(team) do
				if entry.Player then
					local hint = hints[entry.Player]
					entry.Player:SetAttribute("ObjHint", hint and hint[1] or nil)
					entry.Player:SetAttribute("ActionProgress", hint and hint[2] or nil)
				end
			end
		end
		local info
		if planted then
			info = string.format("Bombe bei %s gelegt · %d s", plantedSite, math.ceil(bombTimer))
		elseif dropped then
			info = "Die Bombe liegt am Boden!"
		else
			info = "Team " .. attackers.Name .. " muss die Bombe bei A oder B legen"
		end
		api.SetInfo(info)
	end

	-- Angreifer alle raus, Bombe liegt: Verteidiger müssen noch entschärfen
	function objective.KeepsRoundAlive(aAlive, bAlive)
		if not planted then
			return false
		end
		local attackersAlive = attackers == api.TeamA and aAlive or bAlive
		local defendersAlive = defenders == api.TeamA and aAlive or bAlive
		return attackersAlive == 0 and defendersAlive > 0
	end

	-- Gelegte Bombe: Rundenzeit steht, nur noch der Bomben-Timer zählt
	function objective.TimeFrozen()
		return planted ~= nil
	end

	function objective.TimeOutWinner()
		return defenders
	end

	function objective.Attackers()
		return attackers
	end

	-- Gelegte Bombe: die Uhr oben im HUD zeigt den Bomben-Timer
	function objective.Clock()
		return planted and math.max(0, bombTimer) or nil
	end

	function objective.RoundInfo()
		return "   ·   Angriff: " .. attackers.Name
	end

	function objective.RoundEnd()
		cleanup()
		api.SetInfo(nil)
	end

	return objective
end

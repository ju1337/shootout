-- Hack (ModuleScript, nur Server) – Ziel für Extraction (Stil: Rogue Company "Extraction")
-- Angreifer hacken Ziel A oder B, indem sie im Zielbereich stehen. Der Fortschritt steigt nur,
-- solange kein Verteidiger im selben Bereich ist (dann pausiert er). Ein fertiger Hack gewinnt
-- die Runde. Läuft die Zeit ab, gewinnen die Verteidiger. Seitenwechsel zur Halbzeit.
-- Part-Attribute fürs HUD: Progress (0 bis 1) und Contested (true) an SiteA/SiteB

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameSettings = require(ReplicatedStorage:WaitForChild("Shared").GameSettings)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local BuyService = require(ServerShared.BuyService)
local ProgressService = require(ServerShared.ProgressService)

local SITE_RADIUS = 10
local REWARD = 300

return function(api)
	local objective = {}

	local sites = {}
	local progress = { A = 0, B = 0 }
	local attackers, defenders = api.TeamA, api.TeamB
	local botTargetSite = "A"

	local function loadSites()
		local folder = api.GetMap():WaitForChild("Objective")
		sites.A = folder:WaitForChild("SiteA")
		sites.B = folder:WaitForChild("SiteB")
	end
	loadSites()

	-- Wer steht (lebend, nicht am Boden) im Bereich? Gibt Liste der Teilnehmer zurück.
	local function inSite(team, site)
		local list = {}
		for _, entry in api.Participants(team) do
			local root = entry.Model and entry.Model:FindFirstChild("HumanoidRootPart")
			if root and api.IsActive(entry.Model) then
				local offset = root.Position - site.Position
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= SITE_RADIUS and math.abs(offset.Y) < 10 then
					table.insert(list, entry)
				end
			end
		end
		return list
	end

	function objective.RoundStart(roundNumber)
		loadSites()
		progress.A, progress.B = 0, 0
		local half = math.max(1, api.RoundsToWin() - 1)
		attackers = roundNumber <= half and api.TeamA or api.TeamB
		defenders = api.OtherTeam(attackers)
		if roundNumber == half + 1 then
			api.Announce("Seitenwechsel! Team " .. attackers.Name .. " greift jetzt an.")
		end
		botTargetSite = math.random() < 0.5 and "A" or "B"
		for name, site in sites do
			site.Color = Color3.fromRGB(255, 80, 80)
			site.Transparency = 0.6
			site:SetAttribute("Progress", 0)
			site:SetAttribute("Contested", nil)
		end
	end

	function objective.SpawnFolder(team)
		return team == attackers and "SpawnsAtk" or "SpawnsDef"
	end

	function objective.Tick(dt)
		local hackTime = GameSettings.Get("HackTime")
		local status = {}
		for name, site in sites do
			local hackers = inSite(attackers, site)
			local guards = inSite(defenders, site)
			if #hackers > 0 and #guards == 0 then
				-- Mehr Angreifer hacken etwas schneller (max. doppelt so schnell)
				progress[name] = math.min(1, progress[name] + dt / hackTime * math.min(2, 1 + (#hackers - 1) * 0.35))
				site.Color = attackers.TeamColor.Color
			elseif #hackers > 0 then
				site.Color = Color3.fromRGB(255, 255, 255) -- umkämpft
			else
				site.Color = Color3.fromRGB(255, 80, 80)
			end
			site.Transparency = 0.6 - progress[name] * 0.4
			site:SetAttribute("Progress", progress[name])
			site:SetAttribute("Contested", (#hackers > 0 and #guards > 0) or nil)
			table.insert(status, name .. ": " .. math.floor(progress[name] * 100) .. " %")
			if progress[name] >= 1 then
				for _, entry in hackers do
					if entry.Player then
						BuyService.AddMoney(entry.Player, REWARD, "Hack abgeschlossen")
						ProgressService.AddStat(entry.Player, "Plants", 1)
					end
				end
				api.EndRound(attackers, "Ziel " .. name .. " gehackt!")
				return
			end
		end

		-- Bots: Angreifer zum Ziel, Verteidiger verteilen sich und gehen zum am weitesten gehackten
		local hottest = progress.A >= progress.B and "A" or "B"
		for _, entry in api.Participants(attackers) do
			if entry.Bot then
				entry.Bot.Objective = sites[botTargetSite].Position
			end
		end
		for i, entry in api.Participants(defenders) do
			if entry.Bot then
				local target = (progress[hottest] > 0 and i % 2 == 1) and hottest or (i % 2 == 0 and "A" or "B")
				entry.Bot.Objective = sites[target].Position
			end
		end
		api.SetInfo("Team " .. attackers.Name .. " hackt  ·  " .. table.concat(status, "   "))
	end

	function objective.TimeOutWinner()
		return defenders
	end

	function objective.Attackers()
		return attackers
	end

	function objective.RoundInfo()
		return "   ·   Angriff: " .. attackers.Name
	end

	function objective.RoundEnd()
		for _, site in sites do
			site:SetAttribute("Progress", nil)
			site:SetAttribute("Contested", nil)
		end
		for _, team in { attackers, defenders } do
			for _, entry in api.Participants(team) do
				if entry.Bot then
					entry.Bot.Objective = nil
				end
			end
		end
		api.SetInfo(nil)
	end

	return objective
end

-- Domination (ModuleScript, nur Server) – Ziel für den Modus "Herrschaft"
-- Drei Flaggen A, B und C. Wer allein auf einer Flagge steht, nimmt sie ein (DominationCapture Sekunden,
-- mit mehreren schneller). Stehen beide Teams drauf, ist sie umkämpft und nichts passiert.
-- Jede gehaltene Flagge gibt dem Team pro Sekunde einen Punkt. Wer zuerst DominationScore Punkte hat,
-- gewinnt. Läuft die Zeit ab, gewinnt das Team mit mehr Punkten. Respawn ist unbegrenzt (config.Respawn).
-- Flaggen-Attribute (für Marker im HUD): FlagOwner (Teamname), Progress (0..1), Capturer (Teamname), Contested

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameSettings = require(ReplicatedStorage:WaitForChild("Shared").GameSettings)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local BuyService = require(ServerShared.BuyService)
local ProgressService = require(ServerShared.ProgressService)

local FLAG_RADIUS = 9
local FLAG_NAMES = { "A", "B", "C" }
local NEUTRAL = Color3.fromRGB(230, 230, 235)
local CAPTURE_REWARD = 150 -- Geld fürs Einnehmen

return function(api)
	local objective = {}

	local flags = {}  -- [Name] = { Part, Owner, Capturer, Progress }
	local points = {} -- [Team] = Punkte
	local secondTimer = 0

	local function loadFlags()
		local folder = api.GetMap():WaitForChild("Objective")
		for _, name in FLAG_NAMES do
			local part = folder:WaitForChild("Flag" .. name)
			flags[name] = { Part = part, Owner = nil, Capturer = nil, Progress = 0 }
		end
	end
	loadFlags()

	local function publishFlag(flag, contested)
		local part = flag.Part
		part.Color = flag.Owner and flag.Owner.TeamColor.Color or NEUTRAL
		part.Transparency = flag.Owner and 0.35 or 0.5
		part:SetAttribute("FlagOwner", flag.Owner and flag.Owner.Name or nil)
		part:SetAttribute("Capturer", flag.Capturer and flag.Capturer.Name or nil)
		part:SetAttribute("Progress", flag.Progress)
		part:SetAttribute("Contested", contested or nil)
	end

	-- Teilnehmer eines Teams auf der Flagge (lebend, nicht am Boden)
	local function onFlag(team, part)
		local list = {}
		for _, entry in api.Participants(team) do
			local root = entry.Model and entry.Model:FindFirstChild("HumanoidRootPart")
			if root and api.IsActive(entry.Model) then
				local offset = root.Position - part.Position
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= FLAG_RADIUS and math.abs(offset.Y) < 10 then
					table.insert(list, entry)
				end
			end
		end
		return list
	end

	local function statusText()
		local parts = {}
		for _, name in FLAG_NAMES do
			local owner = flags[name].Owner
			table.insert(parts, name .. ": " .. (owner and owner.Name or "frei"))
		end
		return table.concat(parts, "   ·   ")
	end

	function objective.RoundStart()
		loadFlags()
		points[api.TeamA], points[api.TeamB] = 0, 0
		secondTimer = 0
		for _, flag in flags do
			publishFlag(flag, false)
		end
		api.SetInfo(statusText())
	end

	function objective.Score(team)
		return points[team] or 0
	end

	-- Spawn-Wahl: an einer eigenen, nicht umkämpften Flagge (Spieler-Attribut SpawnChoice), sonst nil = Basis.
	-- Gesucht wird ein freier Platz 11–15 Studs neben der Zone, eher zur eigenen Basis hin, Blick zur Flagge.
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	function objective.SpawnFor(player, team)
		local choice = player:GetAttribute("SpawnChoice")
		local flag = type(choice) == "string" and flags[choice]
		if not flag or flag.Owner ~= team or not api.IsRoundActive() then
			return nil
		end
		local enemy = team == api.TeamA and api.TeamB or api.TeamA
		if #onFlag(enemy, flag.Part) > 0 or (flag.Capturer and flag.Capturer ~= team) then
			return nil -- umkämpft
		end
		local map = api.GetMap()
		local spawns = map:FindFirstChild(team == api.TeamA and "SpawnsA" or "SpawnsB")
		local center = flag.Part.Position
		local home = center
		if spawns and #spawns:GetChildren() > 0 then
			home = spawns:GetChildren()[1].Position
		end
		local toward = Vector3.new(home.X - center.X, 0, home.Z - center.Z)
		local baseAngle = toward.Magnitude > 1 and math.atan2(toward.Z, toward.X) or 0
		overlap.FilterDescendantsInstances = { map }
		for _ = 1, 12 do
			local angle = baseAngle + math.rad(math.random(-70, 70))
			local distance = math.random(11, 15)
			local spot = center + Vector3.new(math.cos(angle) * distance, 3, math.sin(angle) * distance)
			if #workspace:GetPartBoundsInBox(CFrame.new(spot), Vector3.new(3, 5, 3), overlap) == 0 then
				return CFrame.lookAt(spot, Vector3.new(center.X, spot.Y, center.Z))
			end
		end
		return nil
	end

	function objective.Tick(dt)
		local captureTime = GameSettings.Get("DominationCapture")
		local changed = false
		for name, flag in flags do
			local a, b = onFlag(api.TeamA, flag.Part), onFlag(api.TeamB, flag.Part)
			local contested = #a > 0 and #b > 0
			if not contested and (#a > 0 or #b > 0) then
				local team = #a > 0 and api.TeamA or api.TeamB
				local here = #a > 0 and a or b
				if flag.Owner ~= team then
					if flag.Capturer ~= team then
						flag.Capturer, flag.Progress = team, 0
					end
					-- Mehr Spieler nehmen schneller ein (höchstens doppelt so schnell)
					flag.Progress = math.min(1, flag.Progress + dt / captureTime * math.min(2, 1 + (#here - 1) * 0.35))
					if flag.Progress >= 1 then
						local previous = flag.Owner
						flag.Owner, flag.Capturer, flag.Progress = team, nil, 0
						changed = true
						-- Aus Sicht des Spielers: eingenommen, verloren oder vom Gegner eingenommen
						api.Notify("Objective", function(player)
							if player.Team == team then
								return { Text = "Flagge " .. name .. " eingenommen", Side = "Ally", Icon = name }
							end
							return { Text = previous == player.Team and ("Flagge " .. name .. " verloren")
								or ("Gegner hat Flagge " .. name), Side = "Enemy", Icon = name }
						end)
						for _, entry in here do
							if entry.Player then
								BuyService.AddMoney(entry.Player, CAPTURE_REWARD, "Flagge " .. name)
								ProgressService.AddStat(entry.Player, "Captures", 1)
								Remotes.Notify:FireClient(entry.Player, "Medal", { { Id = "Captured",
									Sub = "Flagge " .. name .. "  ·  +" .. CAPTURE_REWARD .. " $" } })
							end
						end
					end
				end
			elseif not contested and flag.Capturer then
				-- Niemand drauf: angefangenes Einnehmen läuft langsam zurück
				flag.Progress = math.max(0, flag.Progress - dt / (captureTime * 2))
				if flag.Progress <= 0 then
					flag.Capturer = nil
				end
			end
			publishFlag(flag, contested)
		end

		-- Punkte: jede gehaltene Flagge 1 Punkt pro Sekunde
		secondTimer += dt
		while secondTimer >= 1 do
			secondTimer -= 1
			for _, flag in flags do
				if flag.Owner then
					points[flag.Owner] = (points[flag.Owner] or 0) + 1
					changed = true
				end
			end
		end
		if changed then
			api.PublishScore()
			api.SetInfo(statusText())
		end
		local limit = GameSettings.Get("DominationScore")
		for _, team in { api.TeamA, api.TeamB } do
			if (points[team] or 0) >= limit then
				api.EndRound(team, limit .. " Punkte erreicht")
				return
			end
		end

		-- Bots: zur nächsten Flagge, die ihrem Team nicht gehört (sonst eine zufällige verteidigen)
		for _, team in { api.TeamA, api.TeamB } do
			for i, entry in api.Participants(team) do
				local root = entry.Bot and entry.Model and entry.Model:FindFirstChild("HumanoidRootPart")
				if root then
					local best, bestDistance = nil, math.huge
					for _, flag in flags do
						if flag.Owner ~= team then
							local distance = (flag.Part.Position - root.Position).Magnitude
							if distance < bestDistance then
								best, bestDistance = flag, distance
							end
						end
					end
					best = best or flags[FLAG_NAMES[(i - 1) % 3 + 1]]
					entry.Bot.Objective = best.Part.Position
				end
			end
		end
	end

	-- Kein Rundenende, nur weil ein Team gerade komplett tot ist (Respawn)
	function objective.KeepsRoundAlive()
		return true
	end

	function objective.TimeOutWinner()
		local a, b = points[api.TeamA] or 0, points[api.TeamB] or 0
		if a == b then
			return nil
		end
		return a > b and api.TeamA or api.TeamB
	end

	function objective.RoundInfo()
		return "   ·   " .. (points[api.TeamA] or 0) .. " : " .. (points[api.TeamB] or 0) .. " Punkte"
	end

	function objective.RoundEnd()
		for _, team in { api.TeamA, api.TeamB } do
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

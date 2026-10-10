-- DungeonService (ModuleScript, nur Server)
-- Dungeons der offenen Welt (Werte in ExtinctionConfig.Dungeon): Der Eingang ist die Gruftkapelle KATAKOMBEN im Camp
-- Phoenix (Punkt Dungeon.Gate) mit flimmerndem Durchgang. E am Eingang verbraucht einen Dungeon-Schlüssel (Item "DungeonKey" aus Tasche oder Container) und
-- bringt den Spieler samt Squad (wer nah genug am Eingang steht) in eine eigene, abgeschlossene Halle abseits der Karte.
-- Dort kommen Welle um Welle Zombies aus Gittern in den Wänden, jede Welle größer und härter (ExtinctionConfig.DungeonWave).
-- Ist eine Welle erledigt, leuchtet das Portal an der Stirnseite für Dungeon.BreakTime Sekunden grün: wer hindurchgeht (E),
-- kommt vor der Kapelle wieder heraus und bekommt die Beute aller Wellen, die er lebend geschafft hat (Münzen, Items in die
-- Tasche bzw. ins Lager, EP). Danach schließt es, und die nächste Welle beginnt. Wer im Dungeon stirbt, verliert die
-- Dungeon-Beute und seine Tasche: es fällt keine (Extinction.dropBag fragt RunOf), nur das Lager bleibt. Ist niemand mehr drin,
-- wird die Halle abgebaut.
-- Stand für die Clients: Karten-Attribut "Dungeons" [{ Key, Title, X, Z }] (Weltkarte), Spieler-Attribut "Dungeon" (JSON
-- { T = Titel, S = "Start"/"Wave"/"Break", W = Welle, L = Zombies übrig, E = Serverzeit bis Start/Ende der Pause,
-- C = Münzen, I = Items, K = geschaffte Wellen }) solange man drin ist (DungeonClient).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Sfx = require(Shared.Sfx)
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local DungeonLayout = require(Shared.DungeonLayout)
local Zentrale = require(Shared.Zentrale)
local ZombieService = require(script.Parent.ZombieService)
local InventoryService = require(script.Parent.InventoryService)
local ProgressService = require(script.Parent.ProgressService)
local ExtLevelService = require(script.Parent.ExtLevelService)
local MovementGuard = require(script.Parent.MovementGuard)

local DungeonService = {}

local D = ExtinctionConfig.Dungeon
local STEP = 0.25
local random = Random.new()
local options = nil  -- { Map, Center, Players(), IsMember(player), InSafeZone(position), GroundY(x, z), IsWater(x, z) }
local entrances = {} -- { Key, Title, Position, CFrame, Exit (CFrame), Model }
local runs = {}      -- [Slot] = Lauf (siehe startRun)
local playerRun = {} -- [Player] = Lauf
local folder = workspace:FindFirstChild("ExtinctionDungeons") or Instance.new("Folder")
folder.Name = "ExtinctionDungeons"
folder.Parent = workspace

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return root, character, humanoid
	end
	return nil, nil, nil
end

local function status(player, text)
	InventoryService.Status(player, text)
end

local function banner(player, title, sub, style)
	Remotes.Notify:FireClient(player, "Banner", { Caption = "Dungeon", Title = title, Sub = sub, Style = style or "Info" })
end

local function part(model, name, size, cframe, color, material, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.CanTouch = false
	p.CanQuery = collide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Schrift auf einer Seite eines Teils (Schild, Graffiti)
local function sign(target, face, text, color, font)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0.6
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = font or Enum.Font.BuilderSansExtraBold
	label.TextColor3 = color
	label.Parent = gui
	return label
end

local function publishEntrances()
	local list = {}
	for _, entrance in entrances do
		table.insert(list, { Key = entrance.Key, Title = entrance.Title, X = math.round(entrance.Position.X),
			Z = math.round(entrance.Position.Z) })
	end
	options.Map:SetAttribute("Dungeons", HttpService:JSONEncode(list))
end

-- ---------- Eingang ----------

-- Eingang im Camp: Punkt Dungeon.Gate (Gruppe Zentrale der Map, immer geladen) vor der Gruftkapelle KATAKOMBEN
-- (tools/camp_phoenix.py crypt_gate). Daran hängt die E-Aufforderung; wer rauskommt, steht ein paar Schritte davor.
local function setupGate()
	local zentrale = options.Map:FindFirstChild(Zentrale.Group)
	local gate = zentrale and zentrale:FindFirstChild(D.Gate)
	if not gate or not gate:IsA("BasePart") then
		warn("DungeonService: Punkt " .. tostring(D.Gate) .. " fehlt im Camp, kein Dungeon-Eingang")
		return nil
	end
	local base = gate.CFrame -- Blick (−Z) = von der Tür weg zur Straße
	local entrance = { Key = "Camp", Title = D.Title, Position = gate.Position, CFrame = base, Exit = base * CFrame.new(0, 0, -5),
		Model = gate }
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DungeonPrompt"
	prompt.ActionText = "Betreten (Dungeon-Schlüssel)"
	prompt.ObjectText = "Katakomben"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = D.EntranceRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = gate
	prompt.Triggered:Connect(function(player)
		DungeonService.Enter(player, entrance)
	end)
	return entrance
end

-- ---------- Halle ----------

-- Halle nach dem Bauplan DungeonLayout ("Die Katakomben"): Teile relativ zu origin (Boden des Schiffs y = 0). Gibt Modell
-- und Stellen zurück: Grates (Zombie-Spawns, Weltpunkte), Spawns (Spieler, CFrames), Portal-Feld mit Licht und Prompt.
local function rgb(c)
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function buildHall(origin)
	local layout = DungeonLayout.Build()
	local model = Instance.new("Model")
	model.Name = "DungeonHall"
	local field, glow
	for _, spec in layout.Parts do
		local cframe = origin * CFrame.new(spec.P[1], spec.P[2], spec.P[3]) * CFrame.Angles(0, math.rad(spec.R or 0), 0)
			* CFrame.Angles(0, 0, math.rad(spec.RZ or 0))
		local material = Enum.Material[spec.M or "SmoothPlastic"] or Enum.Material.SmoothPlastic
		local p = part(model, spec.N, Vector3.new(spec.S[1], spec.S[2], spec.S[3]), cframe, rgb(spec.C), material, spec.K ~= false)
		p.Transparency = spec.T or 0
		if spec.Shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		elseif spec.Shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		end
		if (spec.T or 0) >= 1 or spec.M == "Neon" or spec.K == false then
			p.CastShadow = false
		end
		local l = spec.L and light(p, Color3.fromRGB(spec.L[1], spec.L[2], spec.L[3]), spec.L[4], spec.L[5])
		if spec.F then
			local fire = Instance.new("Fire")
			fire.Size = spec.F
			fire.Heat = spec.F * 2
			fire.Color = Color3.fromRGB(255, 140, 50)
			fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
			fire.Parent = p
		end
		if spec.Mist then
			local mist = Instance.new("ParticleEmitter")
			mist.Name = "Mist"
			mist.Color = ColorSequence.new(rgb(spec.Mist))
			mist.Size = NumberSequence.new(9, 14)
			mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.82),
				NumberSequenceKeypoint.new(1, 1) })
			mist.Lifetime = NumberRange.new(6, 9)
			mist.Rate = 3
			mist.Speed = NumberRange.new(0.5, 1.5)
			mist.SpreadAngle = Vector2.new(180, 10)
			mist.RotSpeed = NumberRange.new(-8, 8)
			mist.LightInfluence = 0.6
			mist.Parent = p
		end
		if spec.Sign then
			sign(p, Enum.NormalId[spec.Sign[2]] or Enum.NormalId.Front, spec.Sign[1], rgb(spec.Sign[3]),
				spec.Sign[4] and Enum.Font[spec.Sign[4]] or nil)
		end
		if spec.N == "Ground" then
			model.PrimaryPart = p
		elseif spec.N == "PortalField" then
			field, glow = p, l
		end
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PortalPrompt"
	prompt.ActionText = "Dungeon verlassen"
	prompt.ObjectText = "Portal"
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = field
	model.Parent = folder
	local grates, spawns = {}, {}
	for _, point in layout.ZombieSpawns do
		table.insert(grates, origin * Vector3.new(point[1], point[2], point[3]))
	end
	for _, point in layout.PlayerSpawns do
		-- Blick nach Norden ins Schiff (−z der Halle zeigt zum Portal)
		table.insert(spawns, origin * CFrame.new(point[1], point[2], point[3]) * CFrame.Angles(0, math.pi, 0))
	end
	return model, { Grates = grates, Spawns = spawns, Field = field, Glow = glow, Prompt = prompt }
end

local function setPortal(run, open)
	local hall = run.Hall
	hall.Prompt.Enabled = open
	hall.Field.Color = open and Color3.fromRGB(80, 230, 140) or Color3.fromRGB(200, 40, 40)
	hall.Field.Transparency = open and 0.25 or 0.75
	hall.Glow.Color = hall.Field.Color
	hall.Glow.Brightness = open and 2.4 or 0.6
	hall.Glow.Range = open and 28 or 18
end

-- ---------- Läufe ----------

local function memberCount(run)
	local n = 0
	for _ in run.Members do
		n += 1
	end
	return n
end

local function aliveZombies(run)
	local n = 0
	for model in run.Zombies do
		local humanoid = model.Parent and model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root.Position.Y > run.Origin.Y - 30 then
			n += 1
		else
			-- tot, weg oder aus der Halle gefallen
			if model.Parent and humanoid and humanoid.Health > 0 then
				model:Destroy()
			end
			run.Zombies[model] = nil
		end
	end
	return n
end

local function publish(run)
	local left = run.ToSpawn + run.Bosses
	for _ in run.Zombies do
		left += 1
	end
	for player, member in run.Members do
		player:SetAttribute("Dungeon", HttpService:JSONEncode({ T = run.Entrance.Title, S = run.State, W = run.Wave,
			L = run.State == "Wave" and left or 0, E = run.EndsAt, C = member.Coins, I = member.ItemCount, K = member.Cleared }))
	end
end

local function teleport(player, cframe)
	local _, character, humanoid = rootOf(player)
	if not character or not humanoid then
		return
	end
	task.spawn(pcall, player.RequestStreamAroundAsync, player, cframe.Position, 5)
	character:PivotTo(cframe)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	MovementGuard.Teleported(character)
end

local function endRun(run)
	for model in run.Zombies do
		if model.Parent then
			model:Destroy()
		end
	end
	run.Zombies = {}
	if run.Model then
		run.Model:Destroy()
		run.Model = nil
	end
	runs[run.Slot] = nil
end

-- Spieler verlässt den Lauf. reason: "Portal" (Beute auszahlen, vor die Kapelle), "Dead" (Beute verloren), sonst still.
local function leaveRun(run, player, reason)
	local member = run.Members[player]
	if not member then
		return
	end
	run.Members[player] = nil
	playerRun[player] = nil
	if player.Parent then
		player:SetAttribute("Dungeon", nil)
	end
	if reason == "Portal" then
		teleport(player, run.Entrance.Exit)
		Sfx.At("AbilityCloak", run.Entrance.Exit.Position)
		if member.Coins > 0 then
			ProgressService.AddCoins(player, member.Coins, "Dungeon")
		end
		local stashed, rest = 0, {}
		for _, item in member.Items do
			local put = InventoryService.Give(player, item.Id, item.Count)
			if put < item.Count then
				local stored = InventoryService.GiveStash(player, item.Id, item.Count - put)
				stashed += stored
				if put + stored < item.Count then
					table.insert(rest, { Id = item.Id, Count = item.Count - put - stored })
				end
			end
		end
		-- Tasche und Lager voll: der Rest liegt als Beutel am Ausgang statt zu verschwinden
		if #rest > 0 then
			require(script.Parent.LootService).Create(run.Entrance.Exit.Position, rest, "Death", "DUNGEON-BEUTE · " .. player.Name,
				{ Meta = { Owner = player.UserId } })
		end
		if member.Cleared > 0 then
			ExtLevelService.Add(player, D.XPPerWave * member.Cleared, "Dungeon")
		end
		banner(player, "DUNGEON GESCHAFFT", string.format("%d Wellen · %d Münzen · %d Items", member.Cleared, member.Coins,
			member.ItemCount) .. (#rest > 0 and " · Rest liegt am Ausgang" or (stashed > 0 and " · Rest im Lager" or "")), "Good")
	elseif reason == "Dead" and player.Parent then
		status(player, "Im Dungeon gestorben: die Dungeon-Beute ist verloren.")
	end
	if not next(run.Members) then
		endRun(run)
	else
		publish(run)
	end
end

local function rollKind(weights)
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll = random:NextNumber(0, total)
	for kind, weight in weights do
		roll -= weight
		if roll <= 0 then
			return kind
		end
	end
	return "Walker"
end

-- nächstes Mitglied (für Zombies ohne Ziel)
local function nearestMember(run, position)
	local best, bestDistance = nil, math.huge
	for player in run.Members do
		local root = rootOf(player)
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

local function spawnOne(run, kind)
	local grate = run.Hall.Grates[random:NextInteger(1, #run.Hall.Grates)]
	local position = grate + Vector3.new(random:NextNumber(-2, 2), 0, random:NextNumber(-2, 2))
	local armored = kind ~= "Boss" and random:NextNumber() < run.WaveInfo.Armored or false
	local model = ZombieService.Spawn(position, kind, "Dungeon", armored)
	if not model then
		return false -- Obergrenze des Servers erreicht: gleich noch einmal
	end
	ZombieService.MarkDungeon(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local factor = run.WaveInfo.Health * (kind == "Boss" and 0.6 or 1)
		humanoid.MaxHealth = math.floor(humanoid.MaxHealth * factor)
		humanoid.Health = humanoid.MaxHealth
	end
	local info = ZombieService.Info(model)
	if info then
		info.Target = nearestMember(run, position)
	end
	run.Zombies[model] = true
	return true
end

local function startWave(run, n)
	run.Wave = n
	run.State = "Wave"
	run.EndsAt = nil
	run.WaveInfo = ExtinctionConfig.DungeonWave(n, memberCount(run))
	run.ToSpawn = run.WaveInfo.Count
	run.Bosses = run.WaveInfo.Bosses
	run.NextSpawn = 0
	setPortal(run, false)
	Sfx.At("WaveSting", run.Origin.Position + Vector3.new(0, 4, 0))
	for player in run.Members do
		local count = run.ToSpawn + run.Bosses
		banner(player, "WELLE " .. n, run.Bosses > 0 and string.format("%d Zombies kommen · mit Blutbestie", count)
			or string.format("%d Zombies kommen", count), "Warning")
	end
	publish(run)
end

local function waveCleared(run)
	local reward = ExtinctionConfig.DungeonReward(run.Wave)
	for player, member in run.Members do
		member.Cleared = run.Wave
		member.Coins += reward.Coins
		for _, item in ExtinctionConfig.RollLoot(reward.Table, reward.Items, random) do
			table.insert(member.Items, item)
			member.ItemCount += item.Count or 1
		end
		banner(player, "WELLE " .. run.Wave .. " GESCHAFFT", string.format("Portal offen für %d s · Beute: %d Münzen · %d Items",
			D.BreakTime, member.Coins, member.ItemCount), "Good")
	end
	run.State = "Break"
	run.Ends = os.clock() + D.BreakTime
	run.EndsAt = workspace:GetServerTimeNow() + D.BreakTime
	setPortal(run, true)
	publish(run)
end

local function tickRun(run, now)
	-- Mitglieder prüfen: weg, tot (der Tod selbst kommt über OnDeath, hier nur zur Sicherheit), aus der Halle
	-- (Teleport von außen) = raus ohne Beute
	for player, member in run.Members do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not player.Parent then
			leaveRun(run, player, nil)
		elseif not humanoid or not root or humanoid.Health <= 0 then
			member.DeadSince = member.DeadSince or now
			if now - member.DeadSince > 3 then
				leaveRun(run, player, "Dead")
			end
		else
			member.DeadSince = nil
			local localPos = run.Origin:PointToObjectSpace(root.Position)
			local b = DungeonLayout.Bounds
			if localPos.X < b.MinX - 20 or localPos.X > b.MaxX + 20 or localPos.Z < b.MinZ - 20 or localPos.Z > b.MaxZ + 20
				or localPos.Y < -30 or localPos.Y > DungeonLayout.Height + 20 then
				leaveRun(run, player, nil)
			end
		end
	end
	if not runs[run.Slot] then
		return
	end
	if run.State == "Start" then
		if now >= run.Ends then
			startWave(run, 1)
		end
	elseif run.State == "Wave" then
		local alive = aliveZombies(run)
		if (run.ToSpawn > 0 or run.Bosses > 0) and alive < D.MaxAlive and now >= run.NextSpawn then
			run.NextSpawn = now + D.SpawnEvery
			if run.Bosses > 0 then
				if spawnOne(run, "Boss") then
					run.Bosses -= 1
				end
			elseif spawnOne(run, rollKind(run.WaveInfo.Weights)) then
				run.ToSpawn -= 1
			end
		end
		-- Zombies ohne Ziel jagen das nächste Mitglied (die Halle ist größer als ihre Sichtweite)
		for model in run.Zombies do
			local info = ZombieService.Info(model)
			if info and (not info.Target or not run.Members[info.Target]) then
				info.Target = nearestMember(run, info.Root.Position)
			end
		end
		if run.ToSpawn <= 0 and run.Bosses <= 0 and aliveZombies(run) == 0 then
			waveCleared(run)
			return
		end
		if now >= (run.NextPublish or 0) then
			run.NextPublish = now + 1
			publish(run)
		end
	elseif run.State == "Break" then
		if now >= run.Ends then
			startWave(run, run.Wave + 1)
		end
	end
end

local function freeSlot()
	for slot = 1, D.MaxRuns do
		if not runs[slot] then
			return slot
		end
	end
	return nil
end

local function startRun(slot, entrance, group)
	local origin = CFrame.new(options.Center + D.Origin + Vector3.new((slot - 1) * D.SlotSpacing, 0, 0))
	local model, hall = buildHall(origin)
	local run = { Slot = slot, Origin = origin, Entrance = entrance, Model = model, Hall = hall, Members = {}, Zombies = {},
		State = "Start", Wave = 0, ToSpawn = 0, Bosses = 0, Ends = os.clock() + D.StartDelay,
		EndsAt = workspace:GetServerTimeNow() + D.StartDelay }
	runs[slot] = run
	local prompt = hall.Prompt
	prompt.Triggered:Connect(function(player)
		if playerRun[player] == run and run.State == "Break" then
			leaveRun(run, player, "Portal")
		end
	end)
	for index, player in group do
		run.Members[player] = { Coins = 0, Items = {}, ItemCount = 0, Cleared = 0 }
		playerRun[player] = run
		local _, character = rootOf(player)
		if character then
			character:SetAttribute("ZombieShieldUntil", nil) -- Anti-Zombie-Spritze wirkt im Dungeon nicht
		end
		teleport(player, hall.Spawns[(index - 1) % #hall.Spawns + 1])
		banner(player, entrance.Title, string.format("Welle 1 in %d s · nach jeder Welle öffnet sich das Portal", D.StartDelay), "Warning")
	end
	setPortal(run, false)
	publish(run)
	return run
end

-- ---------- Schnittstelle ----------

-- Spieler betritt den Dungeon an entrance (E an der Kapelle): Schlüssel nehmen, Squad in der Nähe mitnehmen. Gibt den Lauf zurück.
function DungeonService.Enter(player, entrance)
	if not options or not D.Enabled or not entrance or playerRun[player] or not options.IsMember(player) then
		return nil
	end
	local root, _, humanoid = rootOf(player)
	if not root or not humanoid or (root.Position - entrance.Position).Magnitude > D.EntranceRange + 12 then
		return nil
	end
	if humanoid.SeatPart then
		status(player, "Steig erst aus dem Fahrzeug.")
		return nil
	end
	if InventoryService.CountCarried(player, D.KeyItem) < 1 then
		status(player, "Du brauchst einen Dungeon-Schlüssel (Lootdrops, Events, selten von Zombies).")
		return nil
	end
	local slot = freeSlot()
	if not slot then
		status(player, "Alle Dungeons sind gerade belegt. Versuch es gleich noch einmal.")
		return nil
	end
	local group = { player }
	local squad = player:GetAttribute("SquadId")
	if squad ~= nil then
		for _, other in options.Players() do
			local otherRoot, _, otherHumanoid = rootOf(other)
			if other ~= player and other:GetAttribute("SquadId") == squad and not playerRun[other] and otherRoot and otherHumanoid
				and not otherHumanoid.SeatPart and (otherRoot.Position - entrance.Position).Magnitude <= D.SquadRange then
				table.insert(group, other)
			end
		end
	end
	if InventoryService.TakeCarried(player, D.KeyItem, 1) < 1 then
		return nil
	end
	return startRun(slot, entrance, group)
end

-- Lauf eines Spielers (nil = nicht im Dungeon)
function DungeonService.RunOf(player)
	return playerRun[player]
end

-- Tod (Extinction.OnDeath): raus aus dem Lauf, Beute verloren
function DungeonService.OnDeath(player)
	local run = playerRun[player]
	if run then
		leaveRun(run, player, "Dead")
	end
end

-- Offene Welt verlassen (Extinction.OnLeave)
function DungeonService.OnLeave(player)
	local run = playerRun[player]
	if run then
		leaveRun(run, player, nil)
	end
end

function DungeonService.Entrances()
	return entrances
end

function DungeonService.Runs()
	return runs
end

-- Admin: alle Läufe beenden (Spieler kommen vor die Kapelle, ohne Beute). Gibt die Anzahl zurück.
function DungeonService.StopAll()
	local count = 0
	for _, run in runs do
		count += 1
		for player in run.Members do
			local exit = run.Entrance.Exit
			leaveRun(run, player, nil)
			teleport(player, exit)
		end
		if runs[run.Slot] then
			endRun(run)
		end
	end
	return count
end

-- opts = { Map, Center (Vector3), Players(), IsMember(player), InSafeZone(position), GroundY(x, z), IsWater(x, z) }
function DungeonService.Init(opts)
	options = opts
	entrances = {}
	if D.Enabled then
		local entrance = setupGate()
		if entrance then
			table.insert(entrances, entrance)
		end
	end
	publishEntrances()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < STEP then
			return
		end
		elapsed = 0
		local now = os.clock()
		for _, run in runs do
			local ok, err = pcall(tickRun, run, now)
			if not ok then
				warn("Dungeon: " .. tostring(err))
			end
		end
	end)
	-- Verlassen des Spiels: über Extinction.RemovePlayer (erst Taschen-Strafe, dann OnLeave), nicht über ein eigenes
	-- PlayerRemoving – sonst ist der Lauf je nach Reihenfolge schon weg und die Tasche läge in der Halle
end

return DungeonService

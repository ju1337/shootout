-- Extinction (ModuleScript, nur Server)
-- Offene Welt: Spieler kommen über das große Tor im Hub und landen in der Safe Zone ("Camp Phoenix", Mitte der Map
-- Maps.Extinction). Dort gibt es keinen Schaden und keine Waffen in der Hand, aber Stände, Lager und das Tor
-- zurück zum Hub. Draußen spawnen Zombies (ZombieService), 5 Sekunden nach dem Verlassen der Safe Zone ist PvP an.
-- Wer draußen stirbt, lässt seine ganze Tasche fallen (LootService) und spawnt wieder in der Safe Zone. Wer den
-- Modus oder das Spiel draußen verlässt, verliert die Tasche genauso (im Menü erst nach einem zweiten Klick).
-- Inventar und Lager: InventoryService. Agenten: nur passive Fähigkeiten (siehe AgentService / GadgetService).
-- Rote Zone (RedzoneService): eine Zone, die alle 20 Minuten an einen anderen Ort zieht; drinnen gilt PvP sofort,
-- Attribut Redzone (Name) für die Anzeige. Spieler-Kills dort zählen für die Rangliste (RedzoneBoard, Anzeige rechts
-- oben), die mit jedem Wechsel neu beginnt.
-- Spieler-Attribute: InSafeZone, PvP (draußen und PvP-Zeit erreicht), PvPAt (Serverzeit, ab der PvP gilt), Redzone,
-- MapId / MapName / MapCenter (Minimap, Lichtstimmung). Charakter-Attribut "SafeZone" schützt vor jedem Schaden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local DayCycle = require(Shared.DayCycle)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local ProgressService = require(ServerShared.ProgressService)
local InventoryService = require(ServerShared.InventoryService)
local LootService = require(ServerShared.LootService)
local ZombieService = require(ServerShared.ZombieService)
local RedzoneService = require(ServerShared.RedzoneService)
local BloodMoonService = require(ServerShared.BloodMoonService)
local RedzoneBoard = require(ServerShared.RedzoneBoard)
local ContainerService = require(ServerShared.ContainerService)
local AirdropService = require(ServerShared.AirdropService)
local ActivityService = require(ServerShared.ActivityService)
local MissionService = require(ServerShared.MissionService)
local VehicleService = require(ServerShared.VehicleService)
local ExtinctionTerrain = require(ServerShared.ExtinctionTerrain)
local SpawnUtil = require(script.Parent.Parent.SpawnUtil)
local MovementGuard = require(ServerShared.MovementGuard)

local Extinction = {}

local ZONE_STEP = 0.2 -- so oft wird geprüft, wer in der Safe Zone ist (Sekunden)

local manager
local bloodMoon = nil -- letzter Stand des Blutmonds (nil = noch nicht geprüft, dann keine Ansage)
local members = {} -- [Player] = { Inside, PvPAt, LeaveAsked }
local map = workspace:WaitForChild("Maps"):WaitForChild("Extinction")
local zonePart = map:WaitForChild("Zone"):WaitForChild("SafeZone")

-- Dienste, die sich später anmelden (Zombies, Fahrzeuge), ohne dass dieses Modul sie kennen muss
Extinction.OnDeath = {}  -- callback(player, position, outside)
Extinction.OnLeave = {}  -- callback(player)

-- Alle Safe Zones: das große Camp (Teil "SafeZone", Schlüssel "") und die kleinen Safehouses draußen
-- (Teile "SafeZone_<Schlüssel>" mit Title, Spawns im Ordner "Spawns_<Schlüssel>"). Kreis, Radius = halbe Breite.
function Extinction.SafeZones()
	local list = {}
	for _, part in map.Zone:GetChildren() do
		if part:IsA("BasePart") then
			local key = part.Name == "SafeZone" and "" or string.match(part.Name, "^SafeZone_(.+)$")
			if key then
				table.insert(list, { Key = key, Title = part:GetAttribute("Title") or (key == "" and "CAMP PHOENIX" or key),
					Center = part.Position, Radius = part.Size.X / 2, Part = part })
			end
		end
	end
	return list
end

-- Safe Zone an einer Stelle (Eintrag aus SafeZones) oder nil
function Extinction.SafeZoneAt(position)
	for _, zone in Extinction.SafeZones() do
		if Vector3.new(position.X - zone.Center.X, 0, position.Z - zone.Center.Z).Magnitude <= zone.Radius then
			return zone
		end
	end
	return nil
end

-- Liegt die Stelle in einer Safe Zone (Camp oder Safehouse)?
function Extinction.InSafeZone(position)
	return Extinction.SafeZoneAt(position) ~= nil
end

function Extinction.SafeZoneCenter()
	return zonePart.Position, zonePart.Size.X / 2
end

function Extinction.IsMember(player)
	return members[player] ~= nil
end

local function rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return root, character
	end
	return nil, nil
end

local function notify(player, kind, data)
	Remotes.Notify:FireClient(player, kind, data)
end

-- Status Safe Zone / draußen setzen (Spieler und Charakter)
local function setInside(player, info, inside, character)
	info.Inside = inside
	player:SetAttribute("InSafeZone", inside)
	player:SetAttribute("CanFight", not inside)
	if character then
		character:SetAttribute("SafeZone", inside or nil)
	end
	if inside then
		info.PvPAt = nil
		info.Redzone = nil
		player:SetAttribute("PvP", false)
		player:SetAttribute("PvPAt", nil)
		player:SetAttribute("Redzone", nil)
		InventoryService.Holster(player) -- Waffen bleiben in der Safe Zone gesichert
	else
		info.PvPAt = os.clock() + ExtinctionConfig.PvPDelay
		player:SetAttribute("PvP", false)
		player:SetAttribute("PvPAt", workspace:GetServerTimeNow() + ExtinctionConfig.PvPDelay)
	end
end

local function updateZone(player, info)
	local root, character = rootOf(player)
	if not root then
		return
	end
	local safe = Extinction.SafeZoneAt(root.Position)
	local inside = safe ~= nil
	-- Spawnpunkt: die zuletzt betretene Safe Zone (Camp oder Safehouse)
	if safe and info.Home ~= safe.Key then
		local first = info.Home == nil
		info.Home = safe.Key
		player:SetAttribute("ExtHome", safe.Title)
		if not first then
			notify(player, "Banner", { Caption = "Spawnpunkt gesetzt", Title = string.upper(safe.Title),
				Sub = "Nach dem Tod spawnst du hier", Style = "Good" })
		end
	end
	player:SetAttribute("SafeZoneTitle", safe and safe.Title or nil)
	-- Rote Zone: PvP sofort, Anzeige und Meldung beim Betreten/Verlassen
	local zone = not inside and RedzoneService.At(root.Position) or nil
	if zone ~= info.Redzone then -- neue Zone (auch dieselbe nach einem Wechsel des Ortes) oder raus
		info.Redzone = zone
		player:SetAttribute("Redzone", zone and zone.Name or nil)
		if zone then
			notify(player, "Banner", { Caption = "Rote Zone", Title = string.upper(zone.Title),
				Sub = "PvP sofort · mehr Zombies · bessere Beute · Rangliste rechts oben", Style = "Info" })
		elseif not inside then
			notify(player, "Banner", { Caption = "Rote Zone verlassen", Title = "WEITER VORSICHT", Sub = "PvP bleibt aktiv", Style = "Info" })
		end
	end
	if zone and not player:GetAttribute("PvP") then
		info.PvPAt = nil
		player:SetAttribute("PvP", true)
	end
	if inside ~= info.Inside then
		setInside(player, info, inside, character)
		if inside then
			notify(player, "Banner", { Caption = "Safe Zone", Title = safe and string.upper(safe.Title) or "SAFE ZONE",
				Sub = safe and safe.Key ~= "" and "Kein PvP · Spawnpunkt" or "Kein PvP · Handel · Lager",
				Style = "Info" })
		else
			notify(player, "Banner", { Caption = "Safe Zone verlassen", Title = "VORSICHT",
				Sub = "Zombies · PvP in " .. ExtinctionConfig.PvPDelay .. " Sekunden", Style = "Info" })
		end
	elseif not inside and info.PvPAt and os.clock() >= info.PvPAt then
		info.PvPAt = nil
		player:SetAttribute("PvP", true)
	end
	-- Schutz gilt pro Charakter (nach dem Respawn neu setzen)
	if character:GetAttribute("SafeZone") ~= (inside or nil) then
		character:SetAttribute("SafeZone", inside or nil)
	end
end

-- Tasche fallen lassen (Tod oder Verlassen draußen). Gibt true zurück, wenn etwas gefallen ist.
local function dropBag(player, position)
	local items = InventoryService.TakeAll(player)
	if #items == 0 then
		return false
	end
	LootService.Create(position, items, "Death", "TASCHE · " .. player.Name)
	return true
end

local function spawnPlayer(player)
	local info = members[player]
	if not info then
		return
	end
	local folder = info.Home and info.Home ~= "" and map:FindFirstChild("Spawns_" .. info.Home) or map.Spawns
	local character = SpawnUtil.Spawn(player, SpawnUtil.Pick(folder))
	if not character then
		return
	end
	setInside(player, info, true, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		local current = members[player]
		local root = character:FindFirstChild("HumanoidRootPart")
		local position = root and root.Position
		local outside = position ~= nil and not Extinction.InSafeZone(position)
		if current and outside then
			dropBag(player, position)
		end
		for _, callback in Extinction.OnDeath do
			task.spawn(callback, player, position, outside)
		end
		task.delay(ExtinctionConfig.RespawnTime, function()
			if members[player] and player.Character == character then
				spawnPlayer(player)
			end
		end)
	end)
end

-- Draußen und am Leben? Dann kostet Verlassen die Tasche.
local function leavingOutside(player)
	local root = rootOf(player)
	return root ~= nil and not Extinction.InSafeZone(root.Position)
end

-- Verlassen draußen: Tasche fällt (nicht beim Herunterfahren des Servers)
local function leavePenalty(player)
	local info = members[player]
	if not info or info.Penalized or ProgressService.IsShuttingDown() then
		return
	end
	local root = rootOf(player)
	if root and not Extinction.InSafeZone(root.Position) then
		info.Penalized = true
		dropBag(player, root.Position)
	end
end

-- ---------- Reisen zwischen den Safe Zones (Haltestellen "Travel" / "Travel_<Name>" in der Gruppe Stands) ----------
local travelAt = {} -- [Player] = os.clock() der letzten Reise

local function nearTravelStop(position)
	local stands = map:FindFirstChild("Stands")
	for _, part in stands and stands:GetChildren() or {} do
		if part:IsA("BasePart") and (part.Name == "Travel" or string.sub(part.Name, 1, 7) == "Travel_")
			and (part.Position - position).Magnitude <= ExtinctionConfig.StandRange then
			return part
		end
	end
	return nil
end

-- Spieler an der Haltestelle reist zur Safe Zone key ("" = Camp): Teleport auf einen ihrer Spawns, wird Spawnpunkt
function Extinction.Travel(player, key)
	local info = members[player]
	if not info or type(key) ~= "string" then
		return false
	end
	local root, character = rootOf(player)
	if not root then
		return false
	end
	local function status(text)
		Remotes.ExtUpdate:FireClient(player, "Status", text, false)
	end
	if not nearTravelStop(root.Position) or not Extinction.InSafeZone(root.Position) then
		status("Reisen geht nur an einer Haltestelle in einer Safe Zone.")
		return false
	end
	local target = nil
	for _, zone in Extinction.SafeZones() do
		if zone.Key == key then
			target = zone
		end
	end
	local here = Extinction.SafeZoneAt(root.Position)
	if not target then
		return false
	elseif here and here.Key == key then
		status("Du bist schon in " .. target.Title .. ".")
		return false
	end
	local cooldown = ExtinctionConfig.TravelCooldown or 10
	if travelAt[player] and os.clock() - travelAt[player] < cooldown then
		status("Der Fahrer braucht noch einen Moment.")
		return false
	end
	local folder = key == "" and map:FindFirstChild("Spawns") or map:FindFirstChild("Spawns_" .. key)
	if not folder or #folder:GetChildren() == 0 then
		return false
	end
	travelAt[player] = os.clock()
	character:PivotTo(SpawnUtil.Pick(folder))
	MovementGuard.Teleported(character)
	info.Home = key
	player:SetAttribute("ExtHome", target.Title)
	notify(player, "Banner", { Caption = "Angekommen", Title = string.upper(target.Title),
		Sub = "Spawnpunkt gesetzt · kein PvP", Style = "Good" })
	return true
end

function Extinction.Init(modeManager)
	manager = modeManager
	InventoryService.Handlers.Travel = function(player, key)
		Extinction.Travel(player, key)
	end

	-- Tor zurück zum Hub (in der Safe Zone, darum ohne Verlust)
	local lastTouch = {}
	for _, pad in map:WaitForChild("Portals"):GetChildren() do
		local target = string.match(pad.Name, "^Portal_(.+)$")
		if pad:IsA("BasePart") and target then
			pad.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if not player or not members[player] then
					return
				end
				local now = os.clock()
				if lastTouch[player] and now - lastTouch[player] < 3 then
					return
				end
				lastTouch[player] = now
				manager.Join(player, target)
			end)
		end
	end

	-- Gelände: Hügel, Seen und Bergrand als echtes Terrain (Höhenfeld ExtinctionTerrainData). Der flache Boden der Karte trägt
	-- solange und bleibt als Rückfall, falls das Schreiben scheitert; nach dem Aufbau wird er unter das Terrain abgesenkt.
	local center = map:GetAttribute("Center") or Vector3.new(zonePart.Position.X, 0, zonePart.Position.Z)
	local function isWater(x, z)
		return ExtinctionTerrain.IsWater(x - center.X, z - center.Z)
	end
	task.spawn(function()
		local folder = map:FindFirstChild("Ground")
		local ground = folder and folder:FindFirstChild("Ground")
		local ok, written = pcall(ExtinctionTerrain.Generate, workspace.Terrain, center)
		if not ok then
			warn("[Extinction] Terrain nicht geschrieben: " .. tostring(written))
		elseif written then
			if ground and ground:IsA("BasePart") then
				ground.Position -= Vector3.new(0, 14, 0)
			end
			local cleared, err = pcall(ExtinctionTerrain.ClearRoads, workspace.Terrain, map, center)
			if not cleared then
				warn("[Extinction] Straßen nicht freigeräumt: " .. tostring(err))
			end
		end
	end)

	-- Rote Zone: zieht alle 20 Minuten an einen anderen Ort; die Rangliste der PvP-Kills beginnt dann neu
	RedzoneBoard.Init(map, RedzoneService.List())
	RedzoneService.OnMoved(RedzoneBoard.Moved)
	RedzoneService.Start({
		Map = map,
		SafeCenter = Extinction.SafeZoneCenter,
		SafeZones = Extinction.SafeZones,
		IsWater = isWater,
		GroundY = function(x, z)
			return center.Y + ExtinctionTerrain.Height(x - center.X, z - center.Z)
		end,
		Players = function()
			local list = {}
			for player in members do
				table.insert(list, player)
			end
			return list
		end,
	})
	-- Lagerkisten (Teile Spot_<Art> in der Gruppe Loot)
	ContainerService.Init(map, { RedzoneAt = RedzoneService.At })

	-- Zombies um die Spieler draußen
	ZombieService.Init({
		Map = map,
		RedzoneAt = RedzoneService.At,
		IsWater = isWater,
		Center = center,
		InSafeZone = Extinction.InSafeZone,
		SafeCenter = Extinction.SafeZoneCenter,
		SafeZones = Extinction.SafeZones,
		Players = function()
			local list = {}
			for player in members do
				table.insert(list, player)
			end
			return list
		end,
	})

	-- Lootdrops (Versorgungsabwürfe): Ansage, Fackel, Fallschirm-Kiste mit bester Beute
	AirdropService.Init({
		Map = map,
		Center = center,
		InSafeZone = Extinction.InSafeZone,
		SafeCenter = Extinction.SafeZoneCenter,
		SafeZones = Extinction.SafeZones,
		RedzoneAt = RedzoneService.At,
		RedzoneRandom = function()
			return RedzoneService.Random()
		end,
		Players = function()
			local list = {}
			for player in members do
				table.insert(list, player)
			end
			return list
		end,
	})

	-- Aktivitäten: Zombienester, Vorratslager, Funkgerät (Notruf), Überlebende (Teile Act_<Art> in der Gruppe Activities)
	ActivityService.Init({
		Map = map,
		InSafeZone = Extinction.InSafeZone,
		RedzoneAt = RedzoneService.At,
		Players = function()
			local list = {}
			for player in members do
				table.insert(list, player)
			end
			return list
		end,
	})

	-- Blutmond-Ereignis (10 Minuten, stärkere Zombies, bessere Beute, Bosse)
	BloodMoonService.Init({
		InSafeZone = Extinction.InSafeZone,
		Players = function()
			local list = {}
			for player in members do
				table.insert(list, player)
			end
			return list
		end,
	})

	-- Aufträge (je Spieler drei: Zombies, Nester, Lager, Überlebende, Orte, Nacht ...)
	MissionService.Init({ Map = map, InSafeZone = Extinction.InSafeZone, RedzoneAt = RedzoneService.At })

	-- Fahrzeuge (Taste spawnt, K packt ein); Tod oder Verlassen: Fahrzeug weg
	VehicleService.Init({ InSafeZone = Extinction.InSafeZone })
	table.insert(Extinction.OnDeath, function(player)
		VehicleService.Despawn(player)
	end)
	table.insert(Extinction.OnLeave, VehicleService.Despawn)

	-- Spiel verlassen: vor dem letzten Speichern die Strafe anwenden (draußen = Tasche weg)
	ProgressService.OnLeaving(function(player)
		leavePenalty(player)
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < ZONE_STEP then
			return
		end
		elapsed = 0
		for player, info in members do
			updateZone(player, info)
		end
		-- Blutmond beginnt/endet: Ansage an alle in der offenen Welt
		local blood = DayCycle.IsBloodMoon(workspace:GetServerTimeNow())
		if blood ~= bloodMoon then
			local started = blood and bloodMoon ~= nil
			local ended = not blood and bloodMoon == true
			bloodMoon = blood
			for player in members do
				if started then
					-- die Ansage beim Start kommt vom BloodMoonService
				elseif ended then
					notify(player, "Banner", { Caption = "Morgen", Title = "DER BLUTMOND IST VORBEI", Sub = "Du hast überlebt", Style = "Good" })
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTouch[player] = nil
	end)
end

function Extinction.CanJoin(player)
	if not ProgressService.IsLoaded(player) then
		return false, "Dein Spielstand lädt noch – gleich noch einmal versuchen."
	end
	return true
end

-- Vor dem Wechsel in einen anderen Modus: draußen erst nach einem zweiten Klick (Tasche geht verloren)
function Extinction.ConfirmLeave(player)
	local info = members[player]
	if not info or not leavingOutside(player) then
		return true
	end
	local now = os.clock()
	if info.LeaveAsked and now - info.LeaveAsked <= ExtinctionConfig.LeaveConfirmTime then
		return true
	end
	info.LeaveAsked = now
	manager.Status(player, "Du bist außerhalb der Safe Zone: Beim Verlassen fällt deine Tasche zu Boden. "
		.. "Nochmal klicken zum Verlassen – oder geh zurück in die Safe Zone.")
	return false
end

function Extinction.AddPlayer(player)
	members[player] = { Inside = true }
	player:SetAttribute("MapId", map.Name)
	player:SetAttribute("MapName", map:GetAttribute("DisplayName") or "Ödstadt")
	player:SetAttribute("MapCenter", map:GetAttribute("Center"))
	player:SetAttribute("ModeText", "")
	InventoryService.Enter(player)
	MissionService.Join(player)
	spawnPlayer(player)
end

function Extinction.RemovePlayer(player)
	leavePenalty(player)
	for _, callback in Extinction.OnLeave do
		pcall(callback, player)
	end
	InventoryService.Leave(player)
	MissionService.Leave(player)
	RedzoneBoard.RemovePlayer(player)
	members[player] = nil
	local character = player.Character
	if character then
		character:SetAttribute("SafeZone", nil)
	end
	for _, attribute in { "InSafeZone", "PvP", "PvPAt", "Redzone", "MapId", "MapName", "MapCenter", "ExtHome", "SafeZoneTitle" } do
		player:SetAttribute(attribute, nil)
	end
end

-- Rote Zone, in der ein Spieler gerade steht oder gestorben ist (nicht in einer Safe Zone), sonst nil
local function redzoneOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or Extinction.SafeZoneAt(root.Position) then
		return nil
	end
	return RedzoneService.At(root.Position)
end

-- Spieler-Kill: Kopfgeld in Münzen (Zombies bringen viel weniger, siehe ZombieService) und Rangliste der roten Zone
-- (zählt in der Zone des Opfers, sonst in der des Schützen)
function Extinction.OnKill(killer, victim)
	if victim and victim ~= killer and members[killer] then
		ProgressService.AddCoins(killer, ExtinctionConfig.PlayerKillCoins, "Spieler erledigt")
		InventoryService.Status(killer, "+" .. ExtinctionConfig.PlayerKillCoins .. " Münzen für " .. victim.Name, true)
		RedzoneBoard.Record(killer, redzoneOf(victim) or redzoneOf(killer))
	end
end

return Extinction

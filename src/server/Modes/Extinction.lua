-- Extinction (ModuleScript, nur Server)
-- Offene Welt: Spieler kommen über das große Tor im Hub und landen in der Safe Zone ("Camp Phoenix", Mitte der Map
-- Maps.Extinction). Dort gibt es keinen Schaden und keine Waffen in der Hand, aber Stände, Lager und das Tor
-- zurück zum Hub. Draußen spawnen Zombies (ZombieService), 5 Sekunden nach dem Verlassen der Safe Zone ist PvP an.
-- Wer draußen stirbt, lässt seine ganze Tasche fallen (LootService) und spawnt wieder in der Safe Zone. Wer den
-- Modus oder das Spiel draußen verlässt, verliert die Tasche genauso (im Menü erst nach einem zweiten Klick).
-- Inventar und Lager: InventoryService. Agenten: nur passive Fähigkeiten (siehe AgentService / GadgetService).
-- Rote Zonen (RedzoneService): drinnen gilt PvP sofort, Attribut Redzone (Name) für die Anzeige.
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
local ContainerService = require(ServerShared.ContainerService)
local AirdropService = require(ServerShared.AirdropService)
local ActivityService = require(ServerShared.ActivityService)
local MissionService = require(ServerShared.MissionService)
local VehicleService = require(ServerShared.VehicleService)
local ExtinctionTerrain = require(ServerShared.ExtinctionTerrain)
local SpawnUtil = require(script.Parent.Parent.SpawnUtil)

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

-- Liegt die Stelle in der Safe Zone? (Kreis um die Mitte, Radius = halbe Breite des Teils "SafeZone")
function Extinction.InSafeZone(position)
	local center = zonePart.Position
	local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	return flat.Magnitude <= zonePart.Size.X / 2
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
	local inside = Extinction.InSafeZone(root.Position)
	-- Rote Zone: PvP sofort, Anzeige und Meldung beim Betreten/Verlassen
	local zone = not inside and RedzoneService.At(root.Position) or nil
	local zoneName = zone and zone.Name or nil
	if zoneName ~= info.Redzone then
		info.Redzone = zoneName
		player:SetAttribute("Redzone", zoneName)
		if zone then
			notify(player, "Banner", { Caption = "Rote Zone", Title = string.upper(zone.Title), Sub = "PvP sofort · mehr Zombies · bessere Beute",
				Style = "Info" })
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
			notify(player, "Banner", { Caption = "Extinction", Title = "SAFE ZONE", Sub = "Kein PvP · Handel · Lager",
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
	local character = SpawnUtil.Spawn(player, SpawnUtil.Pick(map.Spawns))
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

function Extinction.Init(modeManager)
	manager = modeManager

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
		elseif written and ground and ground:IsA("BasePart") then
			ground.Position -= Vector3.new(0, 14, 0)
		end
	end)

	-- Rote Zonen (aus den Teilen Redzone_<Name> der Karte) und Lagerkisten (Teile Spot_<Art> in der Gruppe Loot)
	RedzoneService.Init(map)
	ContainerService.Init(map, { RedzoneAt = RedzoneService.At })

	-- Zombies um die Spieler draußen
	ZombieService.Init({
		Map = map,
		RedzoneAt = RedzoneService.At,
		IsWater = isWater,
		Center = center,
		InSafeZone = Extinction.InSafeZone,
		SafeCenter = Extinction.SafeZoneCenter,
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

	-- Aktivitäten: Zombienester, Vorratslager, Funkgerät (Notruf), Horden (Teile Act_<Art> in der Gruppe Activities)
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

	-- Aufträge (je Spieler drei: Zombies, Nester, Lager, Horden, Orte, Nacht ...)
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
					notify(player, "Banner", { Caption = "Nacht", Title = "BLUTMOND", Sub = "Die Toten sind heute Nacht zahlreich und hungrig",
						Style = "Warning" })
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
	members[player] = nil
	local character = player.Character
	if character then
		character:SetAttribute("SafeZone", nil)
	end
	for _, attribute in { "InSafeZone", "PvP", "PvPAt", "Redzone", "MapId", "MapName", "MapCenter" } do
		player:SetAttribute(attribute, nil)
	end
end

-- Spieler-Kill: Kopfgeld in Münzen (Zombies bringen viel weniger, siehe ZombieService)
function Extinction.OnKill(killer, victim)
	if victim and victim ~= killer and members[killer] then
		ProgressService.AddCoins(killer, ExtinctionConfig.PlayerKillCoins, "Spieler erledigt")
		InventoryService.Status(killer, "+" .. ExtinctionConfig.PlayerKillCoins .. " Münzen für " .. victim.Name, true)
	end
end

return Extinction

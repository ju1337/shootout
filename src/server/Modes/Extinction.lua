-- Extinction (ModuleScript, nur Server)
-- Offene Welt: Spieler kommen über das große Tor im Hub und landen in der Safe Zone ("Camp Phoenix", Mitte der Map
-- Maps.Extinction). Dort gibt es keinen Schaden und keine Waffen in der Hand, aber Stände, Lager und das Tor
-- zurück zum Hub. Draußen spawnen Zombies (ZombieService), 5 Sekunden nach dem Verlassen der Safe Zone ist PvP an.
-- Wer draußen stirbt, lässt seine ganze Tasche fallen (LootService) und spawnt wieder in der Safe Zone. Wer den
-- Modus oder das Spiel draußen verlässt, verliert die Tasche genauso (im Menü erst nach einem zweiten Klick).
-- Inventar und Lager: InventoryService. Agenten: nur passive Fähigkeiten (siehe AgentService / GadgetService).
-- Spielermarkt (Reiter MARKT im Menü, nur in der Safe Zone): ExtMarketService.
-- Rote Zone (RedzoneService): eine Zone, die alle 20 Minuten an einen anderen Ort zieht; drinnen gilt PvP sofort,
-- Attribut Redzone (Name) für die Anzeige. Spieler-Kills dort zählen für die Rangliste (RedzoneBoard, Anzeige rechts
-- oben), die mit jedem Wechsel neu beginnt.
-- Spieler-Attribute: InSafeZone, PvP (draußen und PvP-Zeit erreicht), PvPAt (Serverzeit, ab der PvP gilt), Redzone,
-- MapId / MapName / MapCenter (Minimap, Lichtstimmung), ExtDeathBag (JSON { Id, X, Z, Ends }: die eigene Todestasche, solange
-- sie liegt – Markierung auf Minimap und Weltkarte). Charakter-Attribut "SafeZone" schützt vor jedem Schaden.
-- Bots (Admin-Panel, ExtinctionConfig.Bots): spawnen beim Admin draußen (oder in der roten Zone), jagen Spieler draußen,
-- wehren sich gegen Zombies und lassen beim Tod eine Tasche mit Beute fallen; ihr Kill zählt wie ein Spieler-Kill.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local DayCycle = require(Shared.DayCycle)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local ExtLevelConfig = require(Shared.ExtLevelConfig)
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
local ExtMarketService = require(ServerShared.ExtMarketService)
local VehicleService = require(ServerShared.VehicleService)
local ConvoyService = require(ServerShared.ConvoyService)
local HideoutService = require(ServerShared.HideoutService)
local ExtLevelService = require(ServerShared.ExtLevelService)
local ExtinctionTerrain = require(ServerShared.ExtinctionTerrain)
local SpawnUtil = require(script.Parent.Parent.SpawnUtil)
local BotService = require(script.Parent.Parent.BotService)
local MovementGuard = require(ServerShared.MovementGuard)
local Damage = require(ServerShared.Damage)

local Extinction = {}

local ZONE_STEP = 0.2 -- so oft wird geprüft, wer in der Safe Zone ist (Sekunden)

local manager
local bloodMoon = nil -- letzter Stand des Blutmonds (nil = noch nicht geprüft, dann keine Ansage)
local members = {} -- [Player] = { Inside, PvPAt, LeaveAsked, BagNotice }
local deathBags = {} -- [Player] = Id der letzten eigenen Todestasche (Attribut ExtDeathBag)
local bots = {} -- [bot] = true (Bots aus dem Admin-Panel, siehe Extinction.AddBot)
local BOT_TEAM = { Name = "Banditen" } -- alle Bots ein Team: sie schießen nicht aufeinander
local isWaterAt = nil -- function(x, z) -> bool (Weltkoordinaten), ab Init
local random = Random.new()
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

-- Tasche fallen lassen (Tod oder Verlassen draußen). Gibt true zurück, wenn etwas gefallen ist. Der Besitzer sieht sie auf
-- Minimap und Weltkarte (Attribut ExtDeathBag), bis sie leer geräumt oder abgelaufen ist; plündern kann sie jeder.
local function dropBag(player, position)
	local items = InventoryService.TakeAll(player)
	if #items == 0 then
		return false
	end
	local id = LootService.Create(position, items, "Death", "TASCHE · " .. player.Name, { Meta = { Owner = player.UserId } })
	local bag = id and LootService.Get(id)
	if bag and player.Parent then
		deathBags[player] = id
		local at = bag.Part.Position
		player:SetAttribute("ExtDeathBag", HttpService:JSONEncode({ Id = id, X = math.round(at.X), Z = math.round(at.Z),
			Ends = math.round(workspace:GetServerTimeNow() + ExtinctionConfig.BagLifetime) }))
	end
	return true
end

-- Eine Tasche ist weg (leer geräumt, abgelaufen): Markierung des Besitzers löschen, wenn es seine letzte war
local function bagRemoved(bag)
	for player, id in deathBags do
		if id == bag.Id then
			deathBags[player] = nil
			if player.Parent then
				player:SetAttribute("ExtDeathBag", nil)
			end
		end
	end
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
	-- nach dem Tod: Hinweis, wo die eigene Tasche liegt (bzw. dass nichts verloren ging)
	if info.BagNotice then
		local dropped = info.BagNotice == "Dropped"
		info.BagNotice = nil
		notify(player, "Banner", dropped
			and { Caption = "Gestorben", Title = "DEINE TASCHE LIEGT DRAUSSEN", Sub = "Noch " .. math.floor(ExtinctionConfig.BagLifetime / 60)
				.. " Minuten · Markierung auf Minimap und Karte (N) · jeder kann sie plündern", Style = "Info" }
			or { Caption = "Gestorben", Title = "NICHTS VERLOREN", Sub = "Deine Tasche war leer · das Lager bleibt immer", Style = "Info" })
	end
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		local current = members[player]
		local root = character:FindFirstChild("HumanoidRootPart")
		local position = root and root.Position
		local outside = position ~= nil and not Extinction.InSafeZone(position)
		if current and outside then
			current.BagNotice = dropBag(player, position) and "Dropped" or "Empty"
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
	isWaterAt = isWater
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

	-- Zombies um die Spieler draußen (sie jagen auch die Bots)
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
		Bots = function()
			local list = {}
			for bot in bots do
				if bot.Alive and bot.Model then
					table.insert(list, bot.Model)
				end
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

	-- Bei jedem Wechsel der roten Zone kommt ein Lootdrop in die neue Zone (kurz nach der Ansage des Wechsels)
	if ExtinctionConfig.Redzone.Loot and ExtinctionConfig.Redzone.Loot.MoveDrop then
		RedzoneService.OnMoved(function(zone)
			if zone then
				task.delay(4, function()
					if RedzoneService.Current() == zone then
						AirdropService.StartInZone(zone)
					end
				end)
			end
		end)
	end

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

	-- Spielermarkt (Reiter im Extinction-Menü): Spieler handeln Items gegen Münzen, überall in der Safe Zone
	ExtMarketService.Init({ Map = map, InSafeZone = Extinction.InSafeZone })

	-- Aufträge (je Spieler drei: Zombies, Nester, Lager, Überlebende, Orte, Nacht ...)
	MissionService.Init({ Map = map, InSafeZone = Extinction.InSafeZone, RedzoneAt = RedzoneService.At })

	-- Extinction-Level: EP für Zombies, Spieler, Bots, Aktivitäten, Lootdrops, Konvoi und Aufträge
	ExtLevelService.Init({ RedzoneAt = RedzoneService.At })

	-- Fahrzeuge (Taste spawnt, K packt ein); Tod oder Verlassen: Fahrzeug weg
	VehicleService.Init({ InSafeZone = Extinction.InSafeZone })
	table.insert(Extinction.OnDeath, function(player)
		VehicleService.Despawn(player)
	end)
	table.insert(Extinction.OnLeave, VehicleService.Despawn)

	-- Eigenes Versteck: Module ausbauen, Generator abholen (Haus VERSTECK im Camp)
	HideoutService.Init()

	-- Konvoi: fährt eine Landstraße entlang, anhalten (Schüsse), Wachen erledigen, Ladung holen
	ConvoyService.Init({
		Map = map,
		Center = center,
		InSafeZone = Extinction.InSafeZone,
		Players = function()
			local list = {}
			for player in members do
				table.insert(list, player)
			end
			return list
		end,
		SpawnGuard = function(cframe, itemId)
			return Extinction.AddGuard(cframe, itemId)
		end,
		GuardAlive = function(bot)
			return bots[bot] == true and not bot.Dead
		end,
		RemoveGuard = function(bot)
			if bots[bot] and not bot.Dead then
				bots[bot] = nil
				BotService.Destroy(bot)
			end
		end,
		Reward = function(player, coins, text)
			if members[player] then
				ProgressService.AddCoins(player, coins, text)
				InventoryService.Status(player, "+" .. coins .. " Münzen: " .. text, true)
				ExtLevelService.Add(player, ExtLevelConfig.Rewards.Convoy, "Konvoi")
			end
		end,
	})

	-- Spiel verlassen: vor dem letzten Speichern die Strafe anwenden (draußen = Tasche weg)
	ProgressService.OnLeaving(function(player)
		leavePenalty(player)
	end)
	-- Todestasche weg: Markierung beim Besitzer löschen
	table.insert(LootService.OnRemoved, bagRemoved)

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
		deathBags[player] = nil
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
	HideoutService.Publish(player) -- vor dem Spawn: Feldbett zählt schon beim ersten Leben
	ExtLevelService.Publish(player)
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
	deathBags[player] = nil
	for _, attribute in { "InSafeZone", "PvP", "PvPAt", "Redzone", "MapId", "MapName", "MapCenter", "ExtHome", "SafeZoneTitle",
		"ExtDeathBag" } do
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
-- (zählt in der Zone des Opfers, sonst in der des Schützen). Bot-Kills belohnt botDied (Position der Leiche).
function Extinction.OnKill(killer, victim)
	if victim and victim ~= killer and members[killer] then
		ProgressService.AddCoins(killer, ExtinctionConfig.PlayerKillCoins, "Spieler erledigt")
		ExtLevelService.Add(killer, ExtLevelConfig.Rewards.PlayerKill, "Spieler")
		InventoryService.Status(killer, "+" .. ExtinctionConfig.PlayerKillCoins .. " Münzen für " .. victim.Name, true)
		RedzoneBoard.Record(killer, redzoneOf(victim) or redzoneOf(killer))
	end
end

-- ---------- Bots (Admin-Panel) ----------

-- Boden bei (x, z) als Spawn-Lage (Charaktere, Bots, Zombies und Taschen zählen nicht als Boden), nil ohne Boden
local function groundCFrame(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, name in { "Bots", "Zombies", "ExtinctionLoot" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, zonePart.Position.Y + 500, z), Vector3.new(0, -1000, 0), params)
	if not hit then
		return nil
	end
	return CFrame.new(hit.Position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
end

-- Spawnpunkt für einen Bot: um near (Position des Admins) herum, steht er in einer Safe Zone, gleich vor ihrem Rand in
-- seiner Richtung; ohne near in der roten Zone (sonst vor dem Camp). Nie in einer Safe Zone oder im Wasser. nil = keiner.
function Extinction.BotSpawnPoint(near)
	local cfg = ExtinctionConfig.Bots
	local origin, minRadius, maxRadius
	local zone = near and Extinction.SafeZoneAt(near)
	if zone then
		local flat = Vector3.new(near.X - zone.Center.X, 0, near.Z - zone.Center.Z)
		local direction = flat.Magnitude > 1 and flat.Unit or Vector3.new(1, 0, 0)
		origin = Vector3.new(zone.Center.X, near.Y, zone.Center.Z) + direction * (zone.Radius + cfg.SafeMargin)
		minRadius, maxRadius = 0, 15
	elseif near then
		origin, minRadius, maxRadius = near, cfg.SpawnMin, cfg.SpawnMax
	else
		local red = RedzoneService.Current()
		if red then
			origin, minRadius, maxRadius = red.Center, 0, red.Radius * 0.6
		else
			local campCenter, campRadius = Extinction.SafeZoneCenter()
			origin, minRadius, maxRadius = campCenter, campRadius + cfg.SafeMargin, campRadius + cfg.SafeMargin + 60
		end
	end
	for _ = 1, 30 do
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(minRadius, maxRadius)
		local x, z = origin.X + math.cos(angle) * distance, origin.Z + math.sin(angle) * distance
		if not Extinction.InSafeZone(Vector3.new(x, 0, z)) and not (isWaterAt and isWaterAt(x, z)) then
			local cframe = groundCFrame(x, z)
			if cframe then
				return cframe
			end
		end
	end
	return nil
end

-- Inhalt der Tasche eines toten Bots: seine Waffe, Munition dazu und etwas Beute
local function botLoot(bot, inRedzone)
	local cfg = ExtinctionConfig.Bots
	local items = {}
	if bot.ItemId then
		table.insert(items, { Id = bot.ItemId, Count = 1 })
		local ammoId = ExtinctionConfig.AmmoFor(bot.ItemId)
		if ammoId then
			table.insert(items, { Id = ammoId, Count = random:NextInteger(cfg.Ammo[1], cfg.Ammo[2]) })
		end
	end
	local extra = ExtinctionConfig.RollLoot(inRedzone and cfg.RedLootTable or cfg.LootTable,
		random:NextInteger(cfg.LootItems[1], cfg.LootItems[2]), random)
	for _, item in extra do
		table.insert(items, item)
	end
	return items
end

-- Bot tot: Tasche am Boden, Kopfgeld und Rangliste für den Spieler, der zuletzt getroffen hat; Leiche später weg
local function botDied(bot)
	bot.Dead = true
	local model = bot.Model
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if root then
		local zone = RedzoneService.At(root.Position)
		LootService.Create(root.Position, botLoot(bot, zone ~= nil), "Death", "TASCHE · " .. bot.Name)
		local hit = Damage.LastHit(model)
		local killer = hit and hit.Model and Players:GetPlayerFromCharacter(hit.Model)
		if killer and members[killer] then
			local coins = ExtinctionConfig.Bots.KillCoins
			ProgressService.AddCoins(killer, coins, "Bot erledigt")
			InventoryService.Status(killer, "+" .. coins .. " Münzen für " .. bot.Name, true)
			ExtLevelService.Add(killer, ExtLevelConfig.Rewards.BotKill, "Bot")
			RedzoneBoard.Record(killer, zone or redzoneOf(killer))
		end
	end
	task.delay(ExtinctionConfig.Bots.CorpseTime, function()
		if bots[bot] then
			bots[bot] = nil
			BotService.Destroy(bot)
		end
	end)
end

-- Bot in die offene Welt (Admin-Panel). admin = Spieler, der ihn gerufen hat (Spawn in seiner Nähe, sonst rote Zone)
function Extinction.AddBot(bot, _teamName, admin)
	local cfg = ExtinctionConfig.Bots
	local count = 0
	for _ in bots do
		count += 1
	end
	if count >= cfg.Max then
		return false, "Schon " .. count .. " Bots in der offenen Welt (höchstens " .. cfg.Max .. ")."
	end
	local adminRoot = admin and members[admin] and rootOf(admin)
	local cframe = Extinction.BotSpawnPoint(adminRoot and adminRoot.Position)
	if not cframe then
		return false, "Kein freier Platz für einen Bot gefunden."
	end
	local itemId = cfg.Weapons[random:NextInteger(1, #cfg.Weapons)]
	bots[bot] = true
	BotService.SetTeam(bot, BOT_TEAM)
	bot.ItemId = itemId
	bot.Weapon = ExtinctionConfig.Get(itemId).Weapon
	bot.Home = cframe.Position
	bot.HuntRange = cfg.HuntRange
	bot.ZombieRange = cfg.ZombieRange
	bot.AllowPoint = function(position)
		return not Extinction.InSafeZone(position)
	end
	bot.NoGadgets = true -- wie Spieler: in der offenen Welt nur passive Fähigkeiten
	bot.CanFight = true
	-- Körper bauen kann beim ersten Bot eines Agenten dauern: nicht auf das Panel warten lassen
	task.spawn(BotService.SpawnModel, bot, cframe, function()
		botDied(bot)
	end)
	return true
end

-- Wache an einer festen Stelle (Konvoi): wie ein Bot aus dem Admin-Panel, aber ohne Obergrenze, mit gegebener Waffe und
-- kleinerem Jagdradius um die Stelle. Gibt den Bot zurück.
function Extinction.AddGuard(cframe, itemId)
	local item = itemId and ExtinctionConfig.Get(itemId)
	if not item or item.Kind ~= "Weapon" then
		itemId = ExtinctionConfig.Bots.Weapons[1]
	end
	local bot = BotService.Create(ExtinctionConfig.ModeId)
	bot.Name = "KONVOI-WACHE"
	bots[bot] = true
	BotService.SetTeam(bot, BOT_TEAM)
	bot.ItemId = itemId
	bot.Weapon = ExtinctionConfig.Get(itemId).Weapon
	bot.Home = cframe.Position
	bot.HuntRange = ExtinctionConfig.Convoy.GuardRange
	bot.ZombieRange = ExtinctionConfig.Bots.ZombieRange
	bot.AllowPoint = function(position)
		return not Extinction.InSafeZone(position)
	end
	bot.NoGadgets = true
	bot.CanFight = true
	task.spawn(BotService.SpawnModel, bot, cframe, function()
		botDied(bot)
	end)
	return bot
end

function Extinction.RemoveBot(bot)
	bots[bot] = nil
end

-- Bots in der offenen Welt (für Tests und das Admin-Panel)
function Extinction.Bots()
	local list = {}
	for bot in bots do
		table.insert(list, bot)
	end
	return list
end

return Extinction

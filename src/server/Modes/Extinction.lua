-- Extinction (ModuleScript, nur Server)
-- Offene Welt und Start des Spiels (Modes.Home): Spieler beginnen in der Safe Zone ("Camp Phoenix", Mitte der Map
-- Maps.Extinction). Dort gibt es keinen Schaden und keine Waffen in der Hand, aber Stände, Lager und die
-- Camp (früher der Hub: Shop, Bestenlisten, Glücksrad, Tor zum Markt; Gruppe Zentrale, ZentraleService).
-- Draußen spawnen Zombies (ZombieService), 5 Sekunden nach dem Verlassen der Safe Zone ist PvP an.
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
local WorldLayout = require(Shared.WorldLayout)
local Inventory = require(Shared.Inventory)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local ExtLevelConfig = require(Shared.ExtLevelConfig)
local ServerShared = ServerStorage:WaitForChild("ServerShared")
local ProgressService = require(ServerShared.ProgressService)
local InventoryService = require(ServerShared.InventoryService)
local LootService = require(ServerShared.LootService)
local ZombieService = require(ServerShared.ZombieService)
local RedzoneService = require(ServerShared.RedzoneService)
local BloodMoonService = require(ServerShared.BloodMoonService)
local StormService = require(ServerShared.StormService)
local RedzoneBoard = require(ServerShared.RedzoneBoard)
local ContainerService = require(ServerShared.ContainerService)
local AirdropService = require(ServerShared.AirdropService)
local ActivityService = require(ServerShared.ActivityService)
local MissionService = require(ServerShared.MissionService)
local ExtMarketService = require(ServerShared.ExtMarketService)
local VehicleService = require(ServerShared.VehicleService)
local ConvoyService = require(ServerShared.ConvoyService)
local HideoutService = require(ServerShared.HideoutService)
local ThrowableService = require(ServerShared.ThrowableService)
local HordeService = require(ServerShared.HordeService)
local HeliCrashService = require(ServerShared.HeliCrashService)
local BossService = require(ServerShared.BossService)
local BountyService = require(ServerShared.BountyService)
local DungeonService = require(ServerShared.DungeonService)
local Telemetry = require(ServerShared.Telemetry)
local Badges = require(ServerShared.Badges)

local TUTORIAL_DONE_STEP = 9 -- Onboarding-Trichter: 1 Beitritt, 2 offene Welt, 3-8 Tutorial-Schritte, 9 fertig
local RedPointsService = require(ServerShared.RedPointsService)
local KitService = require(ServerShared.KitService)
local ExtLevelService = require(ServerShared.ExtLevelService)
local ExtDailyService = require(ServerShared.ExtDailyService)
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
-- Die Liste wird zwischengespeichert (Zombies fragen sie tausende Male pro Sekunde ab) und neu gebaut, sobald sich im
-- Ordner Zone etwas ändert (Teil dazu/weg, verschoben, Größe oder Titel). Aufrufer lesen die Liste nur.
local zoneCache = nil
local watchedZones = {} -- [Teil] = true: Änderungen an diesem Teil leeren den Zwischenspeicher
local zoneFolderWatched = false
local function invalidateZones()
	zoneCache = nil
end
function Extinction.SafeZones()
	if zoneCache then
		return zoneCache
	end
	local folder = map.Zone
	if not zoneFolderWatched then
		zoneFolderWatched = true
		folder.ChildAdded:Connect(invalidateZones)
		folder.ChildRemoved:Connect(invalidateZones)
	end
	local list = {}
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			local key = part.Name == "SafeZone" and "" or string.match(part.Name, "^SafeZone_(.+)$")
			if key then
				table.insert(list, { Key = key, Title = part:GetAttribute("Title") or (key == "" and "CAMP PHOENIX" or key),
					Center = part.Position, Radius = part.Size.X / 2, Part = part })
			end
			if not watchedZones[part] then
				watchedZones[part] = true
				for _, property in { "Position", "CFrame", "Size", "Name" } do
					part:GetPropertyChangedSignal(property):Connect(invalidateZones)
				end
				part:GetAttributeChangedSignal("Title"):Connect(invalidateZones)
				part.AncestryChanged:Connect(function()
					watchedZones[part] = nil
					invalidateZones()
				end)
			end
		end
	end
	zoneCache = list
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
	player:SetAttribute("CanFight", false) -- drinnen nie, draußen erst nach dem Spawnschutz (updateZone)
	if character then
		character:SetAttribute("SafeZone", inside or nil)
	end
	if inside then
		info.PvPAt = nil
		info.Redzone = nil
		player:SetAttribute("PvP", false)
		player:SetAttribute("PvPAt", nil)
		player:SetAttribute("Redzone", nil)
		info.ProtectAt = nil
		player:SetAttribute("ProtectedUntil", nil)
		InventoryService.Holster(player) -- Waffen bleiben in der Safe Zone gesichert
	else
		player:SetAttribute("TutorialEquip", nil) -- Tutorial: draußen gilt wieder die normale Regel
		-- Spawnschutz: ein paar Sekunden unverwundbar, dafür selbst noch kein Schießen (Damage, CanFight)
		info.ProtectAt = os.clock() + ExtinctionConfig.SpawnProtection
		player:SetAttribute("ProtectedUntil", workspace:GetServerTimeNow() + ExtinctionConfig.SpawnProtection)
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
	-- Im Kampf (CombatUntil, Damage): nicht hinein. Wer es trotzdem über den Rand schafft, kommt auf den Rand zurück
	if safe and not info.Inside and (player:GetAttribute("CombatUntil") or 0) > workspace:GetServerTimeNow() then
		local flat = Vector3.new(root.Position.X - safe.Center.X, 0, root.Position.Z - safe.Center.Z)
		local direction = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(1, 0, 0)
		local out = Vector3.new(safe.Center.X, root.Position.Y, safe.Center.Z) + direction * (safe.Radius + 4)
		local seat = character:FindFirstChildOfClass("Humanoid").SeatPart
		local mover = seat and seat:FindFirstAncestorOfClass("Model") or character
		mover:PivotTo(CFrame.new(out - root.Position) * mover:GetPivot())
		root.AssemblyLinearVelocity = Vector3.zero
		MovementGuard.Teleported(character)
		if not info.CombatNotice or os.clock() - info.CombatNotice > 3 then
			info.CombatNotice = os.clock()
			InventoryService.Status(player, "Im Kampf kommst du nicht in die Safe Zone.")
		end
		return
	end
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
	-- Sturmnacht: PvP für alle aus (auch in der roten Zone), bis Storm.Grace Sekunden nach dem Sturm
	local paused, resumeAt = DayCycle.StormPvPPaused(workspace:GetServerTimeNow())
	if zone and not paused and not player:GetAttribute("PvP") then
		info.PvPAt = nil
		player:SetAttribute("PvP", true)
	end
	if inside ~= info.Inside then
		setInside(player, info, inside, character)
		if inside then
			notify(player, "Banner", { Caption = "Safe Zone", Title = safe and string.upper(safe.Title) or "SAFE ZONE",
				Sub = safe and safe.Key ~= "" and "Kein PvP · Spawnpunkt" or "Kein PvP · Handel · Lager",
				Style = "Info" })
		end
		-- Verlassen: kein Banner mehr (Julio, 2026-10-10); den PvP-Countdown zeigt die Zonen-Anzeige oben
	elseif not inside and not paused and info.PvPAt and os.clock() >= info.PvPAt then
		info.PvPAt = nil
		player:SetAttribute("PvP", true)
	end
	-- Spawnschutz vorbei: ab jetzt schießen (und getroffen werden)
	if not inside and info.ProtectAt and os.clock() >= info.ProtectAt then
		info.ProtectAt = nil
		player:SetAttribute("ProtectedUntil", nil)
		player:SetAttribute("CanFight", true)
	end
	if not inside and paused then
		info.StormPaused = true
		info.PvPAt = nil
		if player:GetAttribute("PvP") then
			player:SetAttribute("PvP", false)
		end
		if player:GetAttribute("PvPAt") ~= resumeAt then
			player:SetAttribute("PvPAt", resumeAt)
		end
	elseif info.StormPaused then
		info.StormPaused = nil
		if not inside then -- Pause vorbei: draußen gilt PvP sofort wieder
			player:SetAttribute("PvP", true)
			player:SetAttribute("PvPAt", nil)
		end
	end
	-- Schutz gilt pro Charakter (nach dem Respawn neu setzen)
	if character:GetAttribute("SafeZone") ~= (inside or nil) then
		character:SetAttribute("SafeZone", inside or nil)
	end
end

-- Tasche fallen lassen (Tod oder Verlassen draußen). Gibt "Dropped" zurück, wenn etwas gefallen ist, "Lost" im Dungeon
-- (dort ist die Tasche weg, es fällt nichts), sonst "Empty". Der Besitzer sieht sie auf Minimap und Weltkarte (Attribut
-- ExtDeathBag), bis sie leer geräumt oder abgelaufen ist; plündern kann sie jeder.
local function dropBag(player, position)
	local inDungeon = DungeonService.RunOf(player) ~= nil
	local items = InventoryService.TakeAll(player)
	if #items == 0 then
		return "Empty"
	elseif inDungeon then
		return "Lost"
	end
	local id = LootService.Create(position, items, "Death", "TASCHE · " .. player.Name, { Meta = { Owner = player.UserId } })
	local bag = id and LootService.Get(id)
	if bag and player.Parent then
		deathBags[player] = id
		local at = bag.Part.Position
		player:SetAttribute("ExtDeathBag", HttpService:JSONEncode({ Id = id, X = math.round(at.X), Z = math.round(at.Z),
			Ends = math.round(workspace:GetServerTimeNow() + ExtinctionConfig.BagLifetime) }))
	end
	return "Dropped"
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

-- Zum Entwickeln: Admins spawnen in Studio immer mit ExtinctionConfig.AdminLoadout (fehlende Waffen kommen dazu, Munition
-- wird bis zur Menge aufgefüllt; was nicht passt, bleibt weg). Nur in Studio: im echten Spiel könnte man sonst Waffen ins
-- Lager legen, neu spawnen und beliebig viele erzeugen (und im Markt verkaufen).
local function giveAdminLoadout(player)
	if not RunService:IsStudio() or not player:GetAttribute("IsAdmin") or not ExtinctionConfig.AdminLoadout then
		return
	end
	for _, entry in ExtinctionConfig.AdminLoadout do
		local id, count = entry[1], entry[2]
		local bag = InventoryService.GetBag(player)
		local have = bag and Inventory.Count(bag, id) or 0 -- nur die Tasche zählt (Lager ist zum Testen egal)
		if have < count then
			InventoryService.Give(player, id, count - have)
		end
	end
end

-- Zum Testen der Dungeons: Admins haben nach jedem Spawn mindestens Dungeon.TestKeys Schlüssel dabei (Tasche oder Container;
-- auch im echten Spiel, 0 schaltet es ab)
local function giveTestKeys(player)
	local D = ExtinctionConfig.Dungeon
	if not player:GetAttribute("IsAdmin") or (D.TestKeys or 0) <= 0 then
		return
	end
	local have = InventoryService.CountCarried(player, D.KeyItem)
	if have < D.TestKeys then
		InventoryService.Give(player, D.KeyItem, D.TestKeys - have)
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
	-- keine automatische Lebensregeneration: Roblox' Standard-Skript "Health" heilt sonst ständig nach,
	-- geheilt wird hier nur mit Items (Verband, Medkit ...)
	local regen = character:FindFirstChild("Health")
	if regen and regen:IsA("LuaSourceContainer") then
		regen:Destroy()
	end
	player:SetAttribute("CombatUntil", nil) -- nach dem Tod nicht mehr im Kampf
	setInside(player, info, true, character)
	giveAdminLoadout(player)
	giveTestKeys(player)
	-- nach dem Tod: Hinweis, wo die eigene Tasche liegt (bzw. dass nichts verloren ging)
	if info.BagNotice then
		local notice = info.BagNotice
		info.BagNotice = nil
		if notice == "Dropped" then
			notify(player, "Banner", { Caption = "Gestorben", Title = "DEINE TASCHE LIEGT DRAUSSEN", Sub = "Noch "
				.. math.floor(ExtinctionConfig.BagLifetime / 60) .. " Minuten · Markierung auf Minimap und Karte (N) · jeder kann sie plündern",
				Style = "Info" })
		elseif notice == "Lost" then
			notify(player, "Banner", { Caption = "Gestorben", Title = "TASCHE IM DUNGEON VERLOREN",
				Sub = "Wer im Dungeon stirbt, verliert alles, was er dabei hatte · das Lager bleibt immer", Style = "Warning" })
		else
			notify(player, "Banner", { Caption = "Gestorben", Title = "NICHTS VERLOREN", Sub = "Deine Tasche war leer · das Lager bleibt immer",
				Style = "Info" })
		end
	end
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		local current = members[player]
		local root = character:FindFirstChild("HumanoidRootPart")
		local position = root and root.Position
		local outside = position ~= nil and not Extinction.InSafeZone(position)
		local lastHit = Damage.LastHit(character)
		local cause = lastHit and lastHit.Model and (Players:GetPlayerFromCharacter(lastHit.Model) and "Player"
			or lastHit.Model:GetAttribute("IsZombie") and "Zombie" or "Other") or "Other"
		Telemetry.Event(player, "Death", 1, "Extinction", cause,
			(position and RedzoneService.At(position)) and "Redzone" or "Open")
		if current and outside then
			current.BagNotice = dropBag(player, position)
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
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart then
		status("Steig erst aus dem Fahrzeug.")
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
	local spot = SpawnUtil.Pick(folder)
	SpawnUtil.Prestream(player, spot.Position)
	character:PivotTo(spot)
	MovementGuard.Teleported(character)
	info.Home = key
	player:SetAttribute("ExtHome", target.Title)
	notify(player, "Banner", { Caption = "Angekommen", Title = string.upper(target.Title),
		Sub = "Spawnpunkt gesetzt · kein PvP", Style = "Good" })
	return true
end

-- Admin: Spieler ins Camp bringen (raus aus einem Dungeon, Spawnpunkt wird das Camp). Gibt true zurück, wenn es ging.
function Extinction.AdminToCamp(player)
	local info = members[player]
	local root, character = rootOf(player)
	local folder = map:FindFirstChild("Spawns")
	if not info or not root or not folder or #folder:GetChildren() == 0 then
		return false
	end
	DungeonService.OnLeave(player)
	local spot = SpawnUtil.Pick(folder)
	SpawnUtil.Prestream(player, spot.Position)
	character:PivotTo(spot)
	MovementGuard.Teleported(character)
	info.Home = ""
	for _, zone in Extinction.SafeZones() do
		if zone.Key == "" then
			player:SetAttribute("ExtHome", zone.Title)
		end
	end
	return true
end

-- Admin: Spieler sofort neu spawnen (an seinem Spawnpunkt, ohne Tod und ohne Taschenverlust)
function Extinction.AdminRespawn(player)
	if not members[player] then
		return false
	end
	DungeonService.OnLeave(player)
	spawnPlayer(player)
	return true
end

function Extinction.Init(modeManager)
	manager = modeManager
	InventoryService.Handlers.Travel = function(player, key)
		Extinction.Travel(player, key)
	end
	-- Tutorial (ExtTutorial): "Step", n, Id = Schritt n erreicht (nur Analyse: Onboarding-Trichter 3 ff.);
	-- "Done"/"Skip" = fertig oder übersprungen, danach nie wieder von selbst (Profil TutorialDone).
	-- Ab dem Schritt "Equip" darf man im Tutorial die Waffe auch in der Safe Zone ziehen (Attribut TutorialEquip,
	-- InventoryService); schießen geht dort trotzdem nicht (CanFight aus, kein Schaden in der Safe Zone).
	InventoryService.Handlers.Tutorial = function(player, result, index, stepId)
		if result == "Step" then
			if type(index) == "number" and index >= 1 and index <= 20 then
				Telemetry.Onboarding(player, 2 + math.floor(index), "Tutorial:" .. tostring(stepId))
			end
			if stepId == "Equip" or stepId == "Leave" then
				player:SetAttribute("TutorialEquip", true)
			end
			return
		end
		if player:GetAttribute("TutorialEquip") then
			player:SetAttribute("TutorialEquip", nil)
			if player:GetAttribute("InSafeZone") then
				InventoryService.Holster(player)
			end
		end
		local profile = ProgressService.Get(player)
		if profile then
			profile.TutorialDone = true
		end
		player:SetAttribute("ExtTutorial", nil)
		Telemetry.Onboarding(player, TUTORIAL_DONE_STEP, result == "Skip" and "TutorialSkipped" or "TutorialDone")
		if result ~= "Skip" then
			Badges.Trigger(player, "Tutorial")
		end
	end

	-- Grundriss für die Weltkarte (Clients haben mit Streaming nur die Teile in ihrer Nähe)
	WorldLayout.Publish(map)

	-- Tore (Portal_<ModusId>, z.B. zum Markt im Camp; in der Safe Zone, darum ohne Verlust)
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
	-- vor dem Zurücksetzen der Rangliste: die besten drei der alten Runde bekommen Rote-Zone-Punkte
	RedzoneService.OnMoved(function()
		local ranks = ExtinctionConfig.RedPoints.Rank
		for place, entry in RedzoneBoard.List("Redzone") do
			local player = Players:GetPlayerByUserId(entry.Id)
			if place > #ranks then
				break
			end
			if player and members[player] and entry.Kills > 0 then
				RedPointsService.Add(player, ranks[place], "Platz " .. place .. " der roten Zone")
			end
		end
	end)
	RedzoneService.OnMoved(RedzoneBoard.Moved)
	-- Zombies in der roten Zone: je 1 RZ; gepanzerte zählen für die Aufträge (XArmored)
	table.insert(ZombieService.OnKill, function(killer, _, position, armored)
		if members[killer] and RedzoneService.At(position) then
			RedPointsService.Add(killer, ExtinctionConfig.RedPoints.ZombieKill, nil)
		end
		if armored and members[killer] then
			ProgressService.QuestEvent(killer, "XArmored", 1)
		end
	end)
	-- Belohnung der Extinction-Aufträge (QuestConfig): Beute ins Lager (passt nichts: Tasche), RZ
	ProgressService.QuestExtras = function(player, quest)
		local lines = {}
		if quest.Loot then
			for _, item in ExtinctionConfig.RollLoot(quest.Loot[1], quest.Loot[2], random) do
				local put = InventoryService.GiveStash(player, item.Id, item.Count)
				if put < item.Count then
					put += InventoryService.Give(player, item.Id, item.Count - put)
				end
				local config = ExtinctionConfig.Get(item.Id)
				if put > 0 and config then
					table.insert(lines, (put > 1 and (put .. "× ") or "") .. config.Name .. " (Lager)")
				end
			end
		end
		if quest.RedPoints then
			RedPointsService.Add(player, quest.RedPoints, nil)
			table.insert(lines, "+" .. quest.RedPoints .. " RZ")
		end
		return lines
	end
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

	-- Sturmnacht (10 Minuten Gewitter, PvP aus, gepanzerte Zombies, gemeinsames Ziel)
	StormService.Init({
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

	-- EP der offenen Welt (zählen fürs Spielerlevel): Zombies, Spieler, Bots, Aktivitäten, Lootdrops, Konvoi und Aufträge
	ExtLevelService.Init({ RedzoneAt = RedzoneService.At })

	-- Fahrzeuge (Taste spawnt, K packt ein); Tod oder Verlassen: Fahrzeug weg
	VehicleService.Init({ InSafeZone = Extinction.InSafeZone })
	table.insert(Extinction.OnDeath, function(player)
		VehicleService.Despawn(player)
	end)
	table.insert(Extinction.OnLeave, VehicleService.Despawn)

	-- Eigenes Versteck: Module ausbauen, Generator abholen (Haus VERSTECK im Camp)
	HideoutService.Init()

	-- Granaten und Molotows (Hotbar-Taste wirft in Blickrichtung)
	ThrowableService.Init()

	-- Horden-Kiste: Kiste gegen Zombiewellen halten, dann Beute
	HordeService.Init({
		Map = map,
		InSafeZone = Extinction.InSafeZone,
		PickTarget = AirdropService.PickTarget,
		Players = function()
			local list = {}
			for player in members do
				table.insert(list, player)
			end
			return list
		end,
		Reward = function(player, coins, text)
			if members[player] then
				ProgressService.AddCoins(player, coins, text)
			end
		end,
	})

	-- Heli-Absturz: Wrack brennt, dann Militärkisten
	HeliCrashService.Init({
		Map = map,
		InSafeZone = Extinction.InSafeZone,
		PickTarget = AirdropService.PickTarget,
		Players = function()
			local list = {}
			for player in members do
				table.insert(list, player)
			end
			return list
		end,
	})

	-- Bosse an ihren Gebäuden (Chirurg am Krankenhaus)
	BossService.Init({
		Map = map,
		InSafeZone = Extinction.InSafeZone,
		Players = function()
			local list = {}
			for player in members do
				table.insert(list, player)
			end
			return list
		end,
	})

	-- Kopfgeld: wer mehrere Spieler in Folge erledigt, wird gesucht (rot auf der Karte)
	BountyService.Init({
		Map = map,
		InSafeZone = Extinction.InSafeZone,
		Players = function()
			local list = {}
			for player in members do
				table.insert(list, player)
			end
			return list
		end,
	})
	table.insert(Extinction.OnDeath, function(player)
		BountyService.OnDeath(player)
	end)

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
				ExtLevelService.Add(player, ExtLevelConfig.Rewards.Convoy, "Konvoi", "ExtConvoys")
			end
		end,
	})

	-- Dungeons: Gruftkapelle im Camp, E mit Dungeon-Schlüssel, eigene Halle mit Zombiewellen, Portal nach jeder Welle
	DungeonService.Init({
		Map = map,
		Center = center,
		IsMember = Extinction.IsMember,
		InSafeZone = Extinction.InSafeZone,
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
	table.insert(Extinction.OnDeath, function(player)
		DungeonService.OnDeath(player)
	end)
	table.insert(Extinction.OnLeave, DungeonService.OnLeave)

	-- Spiel verlassen: vor dem letzten Speichern die Strafe anwenden (draußen = Tasche weg)
	ProgressService.OnLeaving(function(player)
		leavePenalty(player)
	end)
	-- Todestasche weg: Markierung beim Besitzer löschen
	table.insert(LootService.OnRemoved, bagRemoved)

	local elapsed, publishAt = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < ZONE_STEP then
			return
		end
		elapsed = 0
		publishAt += 1
		local publish = publishAt % 5 == 0 -- einmal pro Sekunde
		for player, info in members do
			updateZone(player, info)
			-- Streaming: Squad-Liste und Karte brauchen Ort und Leben auch, wenn der Charakter beim Mitspieler nicht geladen ist
			local character = publish and player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local health = humanoid and root and humanoid.Health > 0 and humanoid.Health / math.max(1, humanoid.MaxHealth) or 0
			if publish then
				player:SetAttribute("ExtHealth", math.floor(health * 100 + 0.5) / 100)
			end
			if root then -- nur bei publish gesetzt (root ist sonst nil): einmal pro Sekunde reicht für Squad und Karte
				local p = root.Position
				player:SetAttribute("ExtPos", Vector3.new(math.floor(p.X), 0, math.floor(p.Z)))
			end
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
	if DungeonService.RunOf(player) then
		manager.Status(player, "Du bist im Dungeon: Beim Verlassen sind deine Tasche und die Dungeon-Beute weg. "
			.. "Nochmal klicken zum Verlassen – oder erst durchs Portal gehen.")
		return false
	end
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
	RedPointsService.Publish(player)
	KitService.Publish(player)
	MissionService.Join(player)
	Telemetry.Onboarding(player, 2, "EnteredExtinction")
	spawnPlayer(player)
	ExtDailyService.Claim(player) -- tägliche Kiste ins Lager (einmal am Tag)
	-- Neue Spieler: geführtes Tutorial (ExtTutorial auf dem Client), bis es fertig oder übersprungen ist (Profil
	-- TutorialDone). Wer die offene Welt schon kannte (GuideHinted aus der Zeit vor dem Tutorial), bekommt es nicht.
	local profile = ProgressService.Get(player)
	if profile and not profile.TutorialDone and not profile.GuideHinted then
		player:SetAttribute("ExtTutorial", true)
	end
end

function Extinction.RemovePlayer(player)
	leavePenalty(player)
	for _, callback in Extinction.OnLeave do
		pcall(callback, player)
	end
	InventoryService.Leave(player)
	MissionService.Leave(player)
	RedzoneBoard.RemovePlayer(player)
	BountyService.RemovePlayer(player)
	members[player] = nil
	travelAt[player] = nil
	local character = player.Character
	if character then
		character:SetAttribute("SafeZone", nil)
	end
	deathBags[player] = nil
	for _, attribute in { "InSafeZone", "PvP", "PvPAt", "Redzone", "MapId", "MapName", "MapCenter", "ExtHome", "SafeZoneTitle",
		"ExtDeathBag", "ExtTutorial", "TutorialEquip", "CombatUntil", "ProtectedUntil", "ExtPos", "ExtHealth" } do
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
		ExtLevelService.Count(killer, ExtLevelConfig.Rewards.PlayerKill, "ExtPlayerKills") -- Level-XP: KillService (AddXP)
		InventoryService.Status(killer, "+" .. ExtinctionConfig.PlayerKillCoins .. " Münzen für " .. victim.Name, true)
		local zone = redzoneOf(victim) or redzoneOf(killer)
		RedzoneBoard.Record(killer, zone)
		if zone then
			RedPointsService.Add(killer, ExtinctionConfig.RedPoints.PlayerKill, "Spieler in der roten Zone")
		end
		BountyService.OnKill(killer, victim)
		ProgressService.QuestEvent(killer, "XPlayerKill", 1)
		Telemetry.Event(killer, "PlayerKill", 1, "Extinction", zone and "Redzone" or "Open")
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
		local killer = hit and ((hit.Player and hit.Player.Parent and hit.Player) or (hit.Model and Players:GetPlayerFromCharacter(hit.Model)))
		if killer and members[killer] then
			local coins = ExtinctionConfig.Bots.KillCoins
			ProgressService.AddCoins(killer, coins, "Bot erledigt")
			InventoryService.Status(killer, "+" .. coins .. " Münzen für " .. bot.Name, true)
			ExtLevelService.Count(killer, ExtLevelConfig.Rewards.BotKill, "ExtBotKills") -- Level-XP: KillService (AddXP)
			RedzoneBoard.Record(killer, zone or redzoneOf(killer))
			if zone or redzoneOf(killer) then
				RedPointsService.Add(killer, ExtinctionConfig.RedPoints.BotKill, "Bot in der roten Zone")
			end
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

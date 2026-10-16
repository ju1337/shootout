-- Anti-Cheat beim Schießen (WeaponService): was ein manipulierter Client über Remotes.Fire schicken kann, darf keinen
-- Schaden machen und den Server nicht stören. Kaputte Argumente, Ursprung weit weg vom Kopf, schneller als die
-- Feuerrate, leeres Magazin, Treffer neben der Flugbahn, außer Reichweite, durch eine Wand, an einer Stelle, an der
-- das Ziel nie war, am eigenen Körper, ohne Waffe oder am Boden liegend. Ein ehrlicher Treffer zählt (Gegenprobe).
-- (Kopftreffer am falschen Punkt, Teleport und Fahrzeug-Deckung prüft der Test extinction.)
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 1, 20)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v2")
local Remotes = require("Remotes")
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
local WeaponConfig = require("WeaponConfig")
ProgressService.Init()
WeaponService.Init()

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Horde.Enabled = false
ExtinctionConfig.HeliCrash.Enabled = false
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0
ExtinctionConfig.Redzone.Enabled = false

local joinedEvent = Instance.new("BindableEvent")
local manager = {
	Joined = joinedEvent.Event,
	Status = function() end,
	Join = function(player, modeId)
		player:SetAttribute("Mode", modeId)
		if modeId == "Extinction" then
			Extinction.AddPlayer(player)
		end
		joinedEvent:Fire(player, modeId)
	end,
}
Extinction.Init(manager)

local players = {}
for i, name in { "Alice", "Bob" } do
	store.Data["u" .. i] = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {}, TutorialDone = true } -- kein Pflicht-Tutorial (Camp-Sperre)
	local player = SIM.Join(name)
	Instance.new("Backpack", player).Name = "Backpack"
	players[name] = player
end
local alice, bob = players.Alice, players.Bob
step(2)
for _, player in { alice, bob } do
	manager.Join(player, "Extinction")
end
step(0.5)

-- beide draußen mit PvP, 15 Studs auseinander; Alice mit Gewehr
local function place(player, offset)
	player.Character:PivotTo(CFrame.new(CENTER + offset))
end
place(alice, Vector3.new(0, 3, 200))
place(bob, Vector3.new(0, 3, 215))
step(ExtinctionConfig.PvPDelay + 0.6)
check(alice:GetAttribute("PvP") and bob:GetAttribute("PvP"), "beide draußen mit PvP")
InventoryService.Give(alice, "Rifle", 1, nil, "Hotbar")
InventoryService.Give(alice, "Ammo_Rifle", 120)
InventoryService.Use(alice, 1)
step(0.5)
check(WeaponService.CarriedWeapon(alice) == "Rifle", "Alice hat das Gewehr in der Hand")

local bobHumanoid = bob.Character.Humanoid
local function heal()
	bobHumanoid.Health = bobHumanoid.MaxHealth
end
local function damageTaken()
	return bobHumanoid.MaxHealth - bobHumanoid.Health
end
local function bodyClaim(position)
	local torso = bob.Character:FindFirstChild("UpperTorso") or bob.Character:FindFirstChild("Torso")
	return { { Part = torso, Position = position or torso.Position } }
end
local function torsoPosition()
	local torso = bob.Character:FindFirstChild("UpperTorso") or bob.Character:FindFirstChild("Torso")
	return torso.Position
end
-- Schuss vom Kopf auf den Oberkörper, sofern nichts anderes angegeben
local function fire(origin, direction, claims)
	local head = alice.Character.Head.Position
	origin = origin or head
	direction = direction or (torsoPosition() - origin).Unit
	Remotes.Fire.OnServerEvent:Fire(alice, origin, direction, false, 0, claims or bodyClaim())
end

-- ---------- Gegenprobe: ehrlicher Treffer zählt ----------
heal()
step(1)
fire()
step(0.3)
local honest = damageTaken()
check(honest > 0, "ehrlicher Treffer macht Schaden (" .. honest .. ")")

-- ---------- kaputte Argumente: kein Schaden, kein Fehler ----------
heal()
step(1)
local magBefore = WeaponService.CarriedMag(alice)
Remotes.Fire.OnServerEvent:Fire(alice, nil, nil, nil, nil, nil)
Remotes.Fire.OnServerEvent:Fire(alice, "x", Vector3.new(0, 0, 1), true, "id", "claims")
Remotes.Fire.OnServerEvent:Fire(alice, alice.Character.Head.Position, Vector3.zero, false, 0, bodyClaim())
Remotes.Fire.OnServerEvent:Fire(alice, alice.Character.Head.Position, Vector3.new(0 / 0, 0, 1), false, 0, bodyClaim())
Remotes.Fire.OnServerEvent:Fire(alice, alice.Character.Head.Position, Vector3.new(0, 0, 1), false, 0, { "kein Treffer", 5 })
step(0.3)
check(damageTaken() == 0, "kaputte Argumente machen keinen Schaden (" .. damageTaken() .. ")")
check(WeaponService.CarriedMag(alice) >= magBefore - 1, "kaputte Argumente verbrauchen höchstens einen Schuss")

-- ---------- Ursprung weit weg vom eigenen Kopf (Schuss durch Wände) ----------
heal()
step(1)
magBefore = WeaponService.CarriedMag(alice)
local farOrigin = torsoPosition() + Vector3.new(0, 0, 3)
fire(farOrigin, (torsoPosition() - farOrigin).Unit)
step(0.3)
check(damageTaken() == 0, "Ursprung weit weg vom Kopf zählt nicht")
check(WeaponService.CarriedMag(alice) == magBefore, "abgelehnter Schuss kostet keine Munition")

-- ---------- schneller als die Feuerrate ----------
heal()
step(1)
local rifle = WeaponConfig.Get("Rifle")
local burst = 10
for _ = 1, burst do
	fire() -- alle im selben Augenblick
end
step(0.3)
check(damageTaken() > 0 and damageTaken() <= honest * 2,
	burst .. " Schüsse auf einmal zählen höchstens zweimal (Puffer für Netz-Schwankungen; Schaden "
	.. damageTaken() .. ", ein Schuss " .. honest .. ")")
check(rifle.FireDelay > 0, "Gewehr hat eine Feuerrate")

-- ---------- leeres Magazin ----------
heal()
step(1)
WeaponService.SetCarried(alice, "Rifle", 0)
step(1)
check(WeaponService.CarriedMag(alice) == 0, "Magazin leer")
fire()
step(0.3)
check(damageTaken() == 0, "mit leerem Magazin kein Schuss")
WeaponService.SetCarried(alice, "Rifle", rifle.MagazineSize)
step(1)

-- ---------- gemeldeter Treffer neben der Flugbahn (Silent Aim) ----------
heal()
step(1)
fire(nil, Vector3.new(1, 0, 0)) -- schaut zur Seite, meldet aber Bobs Oberkörper
step(0.3)
check(damageTaken() == 0, "Treffer neben der Flugbahn zählt nicht (" .. damageTaken() .. ")")

-- ---------- Ziel war nie an der gemeldeten Stelle ----------
heal()
step(1)
local ghost = torsoPosition() + Vector3.new(0, 0, 20)
fire(nil, (ghost - alice.Character.Head.Position).Unit, bodyClaim(ghost))
step(0.3)
check(damageTaken() == 0, "Treffer an einer Stelle, an der Bob nie war, zählt nicht")

-- ---------- außer Reichweite ----------
heal()
place(bob, Vector3.new(0, 3, 200 + rifle.Range + 40))
step(1)
fire()
step(0.3)
check(damageTaken() == 0, "Treffer außer Reichweite zählt nicht")
place(bob, Vector3.new(0, 3, 215))
step(1)

-- ---------- feste Wand dazwischen ----------
heal()
step(1)
local wall = Instance.new("Part")
wall.CanCollide = true
wall.Parent = workspace
SIM.RaycastHandler = function(origin, direction)
	if direction.Magnitude > 4 and math.abs(direction.Y) < direction.Magnitude * 0.5 then
		return { Instance = wall, Position = origin + direction.Unit * 4, Normal = -direction.Unit, Distance = 4,
			Material = Enum.Material.Concrete }
	end
	return nil
end
fire()
step(0.3)
SIM.RaycastHandler = nil
check(damageTaken() == 0, "Treffer durch eine feste Wand zählt nicht")
-- durchsichtiges, nicht festes Teil (z.B. Zonen-Markierung) ist keine Deckung
heal()
step(1)
wall.CanCollide = false
wall.Transparency = 1
SIM.RaycastHandler = function(origin, direction)
	if direction.Magnitude > 4 and math.abs(direction.Y) < direction.Magnitude * 0.5 then
		return { Instance = wall, Position = origin + direction.Unit * 4, Normal = -direction.Unit, Distance = 4,
			Material = Enum.Material.Plastic }
	end
	return nil
end
fire()
step(0.3)
SIM.RaycastHandler = nil
wall:Destroy()
check(damageTaken() > 0, "durchsichtiges Teil ohne Kollision gibt keine Deckung")

-- ---------- Treffer am eigenen Körper ----------
heal()
local aliceHumanoid = alice.Character.Humanoid
aliceHumanoid.Health = aliceHumanoid.MaxHealth
step(1)
local ownTorso = alice.Character:FindFirstChild("UpperTorso") or alice.Character:FindFirstChild("Torso")
fire(nil, nil, { { Part = ownTorso, Position = ownTorso.Position } })
step(0.3)
check(aliceHumanoid.Health == aliceHumanoid.MaxHealth, "eigener Körper zählt nicht als Treffer")

-- ---------- Teil ohne Humanoid (z.B. Kiste) ----------
heal()
step(1)
local crate = Instance.new("Model")
local box = Instance.new("Part", crate)
box.CFrame = CFrame.new(torsoPosition())
crate.Parent = workspace
fire(nil, nil, { { Part = box, Position = box.Position } })
step(0.3)
crate:Destroy()
check(damageTaken() == 0, "Teil ohne Humanoid macht keinen Schaden")

-- ---------- ohne Waffe in der Hand ----------
heal()
WeaponService.SetCarried(alice, nil)
step(1)
fire()
step(0.3)
check(damageTaken() == 0, "ohne Waffe in der Hand kein Schuss")
WeaponService.SetCarried(alice, "Rifle", rifle.MagazineSize)
step(1)

-- ---------- am Boden liegend (Downed) und ohne CanFight ----------
heal()
step(1)
alice.Character:SetAttribute("Downed", true)
fire()
step(0.3)
alice.Character:SetAttribute("Downed", nil)
check(damageTaken() == 0, "am Boden liegend kein Schuss")
heal()
step(1)
local canFight = alice:GetAttribute("CanFight")
alice:SetAttribute("CanFight", false)
fire()
step(0.3)
alice:SetAttribute("CanFight", canFight)
check(damageTaken() == 0, "ohne CanFight (z.B. im Markt) kein Schuss")

-- ---------- Safe Zone: Waffe ziehen ja, Schaden nie (von drinnen, nach drinnen, auch wenn ein Schuss durchkommt) ----------
do
	local Damage = require("Damage")
	local function stab()
		local head = alice.Character.Head.Position
		Remotes.Melee.OnServerEvent:Fire(alice, head, (torsoPosition() - head).Unit)
	end
	-- Kampfsperre der vorigen Treffer aufheben (sonst kommt niemand in die Safe Zone)
	alice:SetAttribute("CombatUntil", nil)
	bob:SetAttribute("CombatUntil", nil)
	-- Alice knapp drinnen (Rand bei 100), Bob 15 Studs davor draußen
	place(alice, Vector3.new(0, 3, 90))
	place(bob, Vector3.new(0, 3, 105))
	step(0.5)
	check(alice:GetAttribute("InSafeZone") == true and bob:GetAttribute("InSafeZone") ~= true, "Alice drinnen, Bob draußen")
	check(WeaponService.CarriedWeapon(alice) == "Rifle", "Waffe bleibt in der Safe Zone in der Hand")
	heal()
	step(1)
	local mag = WeaponService.CarriedMag(alice)
	fire()
	step(0.3)
	check(damageTaken() == 0 and WeaponService.CarriedMag(alice) == mag, "aus der Safe Zone kein Schuss")
	-- selbst wenn CanFight fälschlich an ist (Schuss kommt durch): kein Schuss, kein Schaden
	local canFightBefore = alice:GetAttribute("CanFight")
	alice:SetAttribute("CanFight", true)
	step(1)
	fire()
	step(0.3)
	check(damageTaken() == 0 and WeaponService.CarriedMag(alice) == mag, "Safe Zone sperrt auch mit CanFight")
	-- Schießstand (RangeService): mit laufender Runde darf Alice schießen, trifft aber nur die Ziele, Bob bleibt heil
	local target = Instance.new("Part", workspace)
	target.Name = "Range_Target1"
	target.Size = Vector3.new(4, 8, 1)
	target.CFrame = CFrame.new(alice.Character.Head.Position:Lerp(torsoPosition(), 0.5))
	local rangeHits = {}
	WeaponService.RangeTargets = function(player)
		return player == alice and { target } or nil
	end
	WeaponService.RangeHit = function(player, part)
		table.insert(rangeHits, { player, part })
	end
	-- Strahl gegen die Ziel-Liste (Include): trifft die Scheibe (die Simulation kennt sonst keine Teile)
	local oldHandler = SIM.RaycastHandler
	SIM.RaycastHandler = function(origin, direction, params)
		if params and params.FilterType == Enum.RaycastFilterType.Include then
			return table.find(params.FilterDescendantsInstances, target) and { Instance = target, Position = target.Position,
				Normal = Vector3.yAxis, Material = Enum.Material.Plastic } or nil
		end
		return oldHandler and oldHandler(origin, direction, params) or nil
	end
	step(1)
	fire()
	step(0.3)
	SIM.RaycastHandler = oldHandler
	check(#rangeHits == 1 and rangeHits[1][2] == target and damageTaken() == 0 and WeaponService.CarriedMag(alice) == mag - 1,
		"Schießstand: Schuss zählt am Ziel, kein Schaden an Bob")
	WeaponService.RangeTargets, WeaponService.RangeHit = nil, nil
	target:Destroy()
	mag = WeaponService.CarriedMag(alice)
	step(1)
	stab()
	step(0.3)
	check(damageTaken() == 0, "aus der Safe Zone kein Messer")
	alice:SetAttribute("CanFight", canFightBefore)
	-- letzte Sperre in Damage: Angreifer (Spieler oder Bot) drinnen, Ziel draußen
	check(Damage.Apply(bob.Character, bobHumanoid, 40, { Player = alice, Weapon = "Rifle" }) == 0 and damageTaken() == 0,
		"Damage: Angreifer in der Safe Zone macht keinen Schaden")
	check(Damage.Apply(bob.Character, bobHumanoid, 40, { Model = alice.Character, BotName = "Bot", Weapon = "Rifle" }) == 0
		and damageTaken() == 0, "Damage: Modell in der Safe Zone macht keinen Schaden")

	-- umgekehrt: Bob drinnen, Alice draußen schießt hinein
	alice:SetAttribute("CombatUntil", nil)
	bob:SetAttribute("CombatUntil", nil)
	place(bob, Vector3.new(0, 3, 90))
	place(alice, Vector3.new(0, 3, 105))
	step(ExtinctionConfig.PvPDelay + 0.6)
	check(bob:GetAttribute("InSafeZone") == true and alice:GetAttribute("PvP") == true, "Bob drinnen, Alice draußen mit PvP")
	heal()
	step(1)
	fire()
	step(0.3)
	check(damageTaken() == 0, "Schuss in die Safe Zone macht keinen Schaden")
	step(1)
	stab()
	step(0.3)
	check(damageTaken() == 0, "Messer in die Safe Zone macht keinen Schaden")
	check(Damage.Apply(bob.Character, bobHumanoid, 40, { Player = alice, Weapon = "Granate" }) == 0
		and Damage.Apply(bob.Character, bobHumanoid, 40, { BotName = "Zombie", Weapon = "Zombie" }) == 0
		and damageTaken() == 0, "Explosion und Zombie/Bot: in der Safe Zone kein Schaden")

	-- zurück wie vorher: beide draußen
	place(alice, Vector3.new(0, 3, 200))
	place(bob, Vector3.new(0, 3, 215))
	step(ExtinctionConfig.PvPDelay + 0.6)
end

-- ---------- zum Schluss wieder die Gegenprobe ----------
heal()
step(1)
fire()
step(0.3)
check(damageTaken() > 0, "danach zählt ein ehrlicher Treffer wieder")

-- ---------- nach dem Schießen: ExtinctionConfig.SafeShotCooldown Sekunden nichts in den Container ----------
InventoryService.Give(alice, "Bandage", 3)
local function bandageSlot()
	for s, item in InventoryService.GetBag(alice).Slots do
		if item.Id == "Bandage" then
			return s
		end
	end
	return nil
end
check(InventoryService.Move(alice, "Bag", bandageSlot(), "Safe") == false, "gleich nach dem Schuss: nicht in den Container")
step(ExtinctionConfig.SafeShotCooldown + 0.3)
check(InventoryService.Move(alice, "Bag", bandageSlot(), "Safe") == true, "nach der Sperre: in den Container")

-- ---------- Verband benutzen: Waffe weg, kein Schuss, danach wieder in der Hand ----------
InventoryService.Give(alice, "Bandage", 1, nil, "Hotbar")
local hotbarBandage = bandageSlot()
alice.Character.Humanoid.Health = alice.Character.Humanoid.MaxHealth - 30
check(hotbarBandage and hotbarBandage <= ExtinctionConfig.HotbarSlots, "Verband auf der Schnellleiste")
InventoryService.Use(alice, hotbarBandage)
step(0.2)
check(alice.Character:GetAttribute("UsingItem") ~= nil and WeaponService.CarriedWeapon(alice) == nil, "beim Verbinden: Waffe weggesteckt")
heal()
fire()
step(0.3)
check(damageTaken() == 0, "beim Verbinden kein Schuss")
step(ExtinctionConfig.Items.Bandage.UseTime + 0.5)
check(alice.Character:GetAttribute("UsingItem") == nil and WeaponService.CarriedWeapon(alice) == "Rifle", "danach wieder das Gewehr in der Hand")

-- ---------- Medikit: hinknien (UseKneel), Springen bricht ab, Weglaufen wirkt nicht ----------
local function medkits()
	for s, item in InventoryService.GetBag(alice).Slots do
		if item.Id == "Medkit" then
			return s, item.Count
		end
	end
	return nil, 0
end
local aliceHumanoid = alice.Character.Humanoid
InventoryService.Give(alice, "Medkit", 2, nil, "Hotbar")
aliceHumanoid.Health = aliceHumanoid.MaxHealth - 60
InventoryService.Use(alice, (medkits()))
step(0.2)
check(alice.Character:GetAttribute("UseKneel") == true, "Medikit: kniet")
check(WeaponService.CarriedWeapon(alice) == nil, "Medikit: Waffe weggesteckt")
Remotes.ExtAction.OnServerEvent:Fire(alice, "CancelUse")
step(0.2)
check(alice.Character:GetAttribute("UseKneel") == nil and alice.Character:GetAttribute("UsingItem") == nil,
	"abgebrochen: steht wieder auf")
check(select(2, medkits()) == 2, "abgebrochen: Medikit bleibt")
check(WeaponService.CarriedWeapon(alice) == "Rifle", "abgebrochen: Gewehr wieder in der Hand")
step(ExtinctionConfig.Items.Medkit.UseTime + 0.5)
check(aliceHumanoid.Health == aliceHumanoid.MaxHealth - 60, "abgebrochen: heilt auch später nicht")

InventoryService.Use(alice, (medkits()))
step(0.2)
local aliceRoot = alice.Character.HumanoidRootPart
aliceRoot.CFrame = aliceRoot.CFrame + Vector3.new(ExtinctionConfig.KneelMoveLimit + 6, 0, 0)
step(ExtinctionConfig.Items.Medkit.UseTime + 0.5)
check(select(2, medkits()) == 2 and aliceHumanoid.Health == aliceHumanoid.MaxHealth - 60, "beim Knien weggelaufen: wirkt nicht")
check(WeaponService.CarriedWeapon(alice) == "Rifle", "weggelaufen: Gewehr wieder in der Hand")

InventoryService.Use(alice, (medkits()))
step(ExtinctionConfig.Items.Medkit.UseTime + 0.5)
check(select(2, medkits()) == 1 and aliceHumanoid.Health > aliceHumanoid.MaxHealth - 60, "still gekniet: Medikit heilt")
check(alice.Character:GetAttribute("UseKneel") == nil, "danach: steht wieder")
check(ExtinctionConfig.Items.Adrenaline.Kneel ~= true, "Spritzen: ohne Knien")

if failures > 0 then
	error(failures .. " Prüfungen fehlgeschlagen")
end
print("shotguard: alles ok")

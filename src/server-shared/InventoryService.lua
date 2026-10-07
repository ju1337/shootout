-- InventoryService (ModuleScript, nur Server)
-- Inventar der offenen Welt (EXTINCTION): Tasche mit ExtinctionConfig.BagSlots Plätzen (Plätze 1-9 = Hotbar,
-- Tasten 1-9) und das Lager in der Safe Zone (StashSlots Plätze, immer sicher). Beides steht im Profil
-- (ProgressService) unter Extinction = { Bag = Liste, Stash = Liste } und bleibt beim Verlassen in der Safe Zone
-- genau so angeordnet erhalten. Die Regeln für Plätze und Stapel stehen in Inventory (shared).
-- Taste 1-9 (Use): Waffe in die Hand / wegstecken (nur außerhalb der Safe Zone), Heilung, Rüstung und die Anti-Zombie-Spritze
-- benutzen (dauert UseTime Sekunden; die Spritze setzt das Charakter-Attribut ZombieShieldUntil: so lange spawnen bei einem
-- keine Zombies, siehe ZombieService), Fahrzeug spawnen (VehicleService meldet sich als UseVehicle an).
-- Stände: kaufen (Münzen) und verkaufen (SellFactor) nur in der Nähe des Stands; Lager nur in seiner Nähe.
-- Spieler-Attribute für den Client: ExtBag, ExtStash (JSON-Listen, siehe Inventory.ToList), ExtEquipped (Platz der
-- Waffe in der Hand, 0 = keine). Charakter-Attribute beim Benutzen: UsingItem (Name), UseEnd (Serverzeit).
-- Meldungen an den Client: Remotes.ExtUpdate("Status", Text, Erfolg).

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Inventory = require(Shared.Inventory)
local Modes = require(Shared.Modes)
local ProgressService = require(script.Parent.ProgressService)
local WeaponService = require(script.Parent.WeaponService)

local InventoryService = {}

local HOTBAR = ExtinctionConfig.HotbarSlots

local states = {} -- [Player] = { Profile, Bag, Stash, Equipped (Item-Tabelle), Using, Dirty }

-- Andere Dienste hängen sich hier an (sie brauchen InventoryService, nicht umgekehrt):
-- Handlers[Aktion] = function(player, ...) für Remotes.ExtAction (LootService: Loot/Drop, VehicleService: StoreVehicle)
-- UseVehicle(player, slot, item) für Fahrzeuge auf der Hotbar, DropItems(player, items, position) für "Fallen lassen"
InventoryService.Handlers = {}
InventoryService.UseVehicle = nil
InventoryService.DropItems = nil

local function status(player, text, ok)
	Remotes.ExtUpdate:FireClient(player, "Status", text, ok == true)
end
InventoryService.Status = status

-- Ganze Zahl vom Client (NaN und Unendlich abfangen), sonst fallback
local function wholeNumber(value, fallback)
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return math.floor(n)
end

local function inExtinction(player)
	return Modes.IsSurvival(player:GetAttribute("Mode"))
end

local function livingCharacter(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil, nil, nil
end

-- Zustand des Spielers (aus dem Profil geladen). Wird das Profil ersetzt (Laden fertig), neu lesen.
local function stateOf(player)
	local profile = ProgressService.Get(player)
	if not profile then
		return nil
	end
	local state = states[player]
	if state and state.Profile == profile then
		return state
	end
	local data = type(profile.Extinction) == "table" and profile.Extinction or {}
	state = {
		Profile = profile,
		Bag = Inventory.FromList(data.Bag, ExtinctionConfig.BagSlots),
		Stash = Inventory.FromList(data.Stash, ExtinctionConfig.StashSlots),
	}
	states[player] = state
	return state
end

local function slotOf(container, item)
	for slot = 1, container.Size do
		if container.Slots[slot] == item then
			return slot
		end
	end
	return nil
end

-- Stand ins Profil schreiben und an den Client schicken
local function flush(player, state)
	state.Dirty = false
	local bag, stash = Inventory.ToList(state.Bag), Inventory.ToList(state.Stash)
	state.Profile.Extinction = { Bag = bag, Stash = stash }
	if player.Parent then
		player:SetAttribute("ExtBag", HttpService:JSONEncode(bag))
		player:SetAttribute("ExtStash", HttpService:JSONEncode(stash))
		local equipped = state.Equipped and slotOf(state.Bag, state.Equipped)
		player:SetAttribute("ExtEquipped", equipped or 0)
	end
end

-- Nach jeder Änderung: speichern, Anzeige und Munition (Reserve kann sich geändert haben) aktualisieren
local function changed(player, state)
	flush(player, state)
	WeaponService.RefreshAmmo(player)
end

-- ---------- Waffe in der Hand ----------

-- Munition und Magazin der Waffe kommen aus dem Inventar
local function sourceFor(player, state, item)
	local ammoId = ExtinctionConfig.AmmoFor(item.Id)
	return {
		Count = function()
			return ammoId and Inventory.Count(state.Bag, ammoId) or 0
		end,
		Take = function(n)
			local taken = ammoId and Inventory.Remove(state.Bag, ammoId, n) or 0
			if taken > 0 then
				flush(player, state)
			end
			return taken
		end,
		SetMag = function(mag)
			item.Mag = mag
			state.Dirty = true
		end,
	}
end

-- Magazin der Waffe in der Hand ans Item schreiben
local function syncMag(player, state)
	if state.Equipped then
		local mag = WeaponService.CarriedMag(player)
		if mag then
			state.Equipped.Mag = mag
		end
	end
end

local function holster(player, state)
	if not state.Equipped then
		return
	end
	syncMag(player, state)
	state.Equipped = nil
	WeaponService.SetCarried(player, nil)
end

-- Waffe wegstecken (z.B. beim Betreten der Safe Zone oder beim Einsteigen)
function InventoryService.Holster(player)
	local state = states[player]
	if state and state.Equipped then
		holster(player, state)
		flush(player, state)
	end
end

local function equip(player, state, item)
	holster(player, state)
	local config = ExtinctionConfig.Get(item.Id)
	if WeaponService.SetCarried(player, config.Weapon, item.Mag, sourceFor(player, state, item)) then
		state.Equipped = item
	end
	flush(player, state)
end

-- Waffe in der Hand nicht mehr auf der Hotbar (verschoben, verkauft, ins Lager): wegstecken
local function checkEquipped(player, state)
	if state.Equipped then
		local slot = slotOf(state.Bag, state.Equipped)
		if not slot or slot > HOTBAR then
			holster(player, state)
		end
	end
end

-- ---------- Benutzen (Heilung, Rüstung) ----------

local function cancelUse(player, state)
	state.Using = nil
	local character = player.Character
	if character then
		character:SetAttribute("UsingItem", nil)
		character:SetAttribute("UseEnd", nil)
	end
end

local function finishUse(player, state, item, config, character, humanoid)
	local slot = slotOf(state.Bag, item)
	if not slot or player.Character ~= character or humanoid.Health <= 0 then
		return
	end
	if config.Kind == "Repel" then
		-- Anti-Zombie-Spritze: einzige Wirkung – eine Weile spawnen bei dir keine Zombies
		character:SetAttribute("ZombieShieldUntil", workspace:GetServerTimeNow() + config.Duration)
		status(player, "Anti-Zombie-Spritze: " .. math.floor(config.Duration / 60) .. " Min spawnen bei dir keine Zombies", true)
	elseif config.Kind == "Heal" then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + config.Heal)
		if config.Speed then
			character:SetAttribute("SpeedMultiplier", config.Speed)
			task.delay(config.SpeedTime or 5, function()
				if character.Parent and character:GetAttribute("SpeedMultiplier") == config.Speed then
					character:SetAttribute("SpeedMultiplier", 1)
				end
			end)
		end
	else
		local armor = character:GetAttribute("Armor") or 0
		character:SetAttribute("Armor", math.min(ExtinctionConfig.MaxArmor, armor + config.Armor))
	end
	item.Count -= 1
	if item.Count <= 0 then
		state.Bag.Slots[slot] = nil
	end
	Remotes.ExtUpdate:FireClient(player, "UseEnd", config.Name, true)
	changed(player, state)
end

local function startUse(player, state, item, config)
	local character, humanoid = livingCharacter(player)
	if not character or not humanoid then
		return
	end
	if state.Using then
		status(player, "Du benutzt schon etwas.")
		return
	end
	if config.Kind == "Heal" and humanoid.Health >= humanoid.MaxHealth and not config.Speed then
		status(player, "Du hast volles Leben.")
		return
	end
	if config.Kind == "Armor" and (character:GetAttribute("Armor") or 0) >= ExtinctionConfig.MaxArmor then
		status(player, "Deine Rüstung ist voll.")
		return
	end
	if config.Kind == "Repel" and (character:GetAttribute("ZombieShieldUntil") or 0) > workspace:GetServerTimeNow() then
		status(player, "Die Anti-Zombie-Spritze wirkt noch.")
		return
	end
	local token = {}
	state.Using = token
	character:SetAttribute("UsingItem", config.Name)
	character:SetAttribute("UseEnd", workspace:GetServerTimeNow() + config.UseTime)
	Remotes.ExtUpdate:FireClient(player, "UseStart", config.Name, config.UseTime)
	task.delay(config.UseTime, function()
		if state.Using ~= token then
			return -- abgebrochen
		end
		cancelUse(player, state)
		finishUse(player, state, item, config, character, humanoid)
	end)
end

-- ---------- Aktionen ----------

-- Taste 1-9: Item auf diesem Hotbar-Platz benutzen
function InventoryService.Use(player, slot)
	if not inExtinction(player) or type(slot) ~= "number" or slot < 1 or slot > HOTBAR or slot ~= math.floor(slot) then
		return
	end
	local state = stateOf(player)
	local character, humanoid = livingCharacter(player)
	if not state or not character or not humanoid then
		return
	end
	local item = state.Bag.Slots[slot]
	if not item then
		if state.Equipped then
			holster(player, state) -- leerer Platz: Hände frei
			flush(player, state)
		end
		return
	end
	local config = ExtinctionConfig.Get(item.Id)
	if config.Kind == "Weapon" then
		if state.Equipped == item then
			holster(player, state)
			flush(player, state)
		elseif player:GetAttribute("InSafeZone") then
			status(player, "In der Safe Zone bleiben Waffen gesichert.")
		elseif humanoid.SeatPart then
			status(player, "Im Fahrzeug kannst du keine Waffe ziehen.")
		else
			equip(player, state, item)
		end
	elseif config.Kind == "Heal" or config.Kind == "Armor" or config.Kind == "Repel" then
		startUse(player, state, item, config)
	elseif config.Kind == "Vehicle" then
		if InventoryService.UseVehicle then
			InventoryService.UseVehicle(player, slot, item)
		end
	elseif config.Kind == "Ammo" then
		status(player, config.Name .. " wird beim Nachladen benutzt.")
	end
end

-- Nah genug an einem Stand / am Lager? (Teile in Maps.Extinction.Stands, ein Name kann mehrfach vorkommen)
local function nearPoint(player, name)
	local _, _, root = livingCharacter(player)
	local maps = workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild("Extinction")
	local stands = map and map:FindFirstChild("Stands")
	if not root or not stands then
		return false
	end
	-- es kann mehrere Stände mit demselben Namen geben (Camp und Safehouses)
	for _, point in stands:GetChildren() do
		if point.Name == name and point:IsA("BasePart") and (root.Position - point.Position).Magnitude <= ExtinctionConfig.StandRange then
			return true
		end
	end
	return false
end

local function nearAnyStand(player)
	for key in ExtinctionConfig.Stands do
		if nearPoint(player, key) then
			return true
		end
	end
	return false
end

local function container(player, state, name)
	if name == "Bag" then
		return state.Bag
	elseif name == "Stash" and nearPoint(player, "Stash") then
		return state.Stash
	end
	return nil
end

-- Fahrzeug gerade draußen? (Item darf dann nicht weg)
local function isOut(item)
	return item and item.Out == true
end

-- Item verschieben: innerhalb der Tasche (Hotbar anordnen) oder zwischen Tasche und Lager.
-- toSlot = nil: automatisch einsortieren.
function InventoryService.Move(player, fromName, fromSlot, toName, toSlot)
	if not inExtinction(player) or type(fromSlot) ~= "number" or (toSlot ~= nil and type(toSlot) ~= "number") then
		return false
	end
	local state = stateOf(player)
	if not state then
		return false
	end
	local from, to = container(player, state, fromName), container(player, state, toName)
	if not from or not to then
		status(player, "Das Lager erreichst du nur in der Safe Zone direkt am Lager.")
		return false
	end
	local item = from.Slots[fromSlot]
	local target = toSlot and to.Slots[toSlot]
	if from ~= to and (isOut(item) or isOut(target)) then
		status(player, "Pack das Fahrzeug erst ein (K).")
		return false
	end
	if from == to and toSlot == nil then
		return false
	end
	if not Inventory.Move(from, fromSlot, to, toSlot) then
		if toSlot == nil then
			status(player, toName == "Stash" and "Das Lager ist voll." or "Deine Tasche ist voll.")
		end
		return false
	end
	checkEquipped(player, state)
	changed(player, state)
	return true
end

-- Am Stand kaufen. qty = Anzahl (Munition: Packungen), höchstens 10
function InventoryService.Buy(player, standKey, itemId, qty)
	if not inExtinction(player) or type(standKey) ~= "string" or type(itemId) ~= "string" then
		return false
	end
	local stand = ExtinctionConfig.Stands[standKey]
	local config = ExtinctionConfig.Get(itemId)
	if not stand or not config or not config.Price or not table.find(stand.Items, itemId) then
		return false
	end
	if not nearPoint(player, standKey) then
		status(player, "Geh näher an den Stand.")
		return false
	end
	local state = stateOf(player)
	if not state then
		return false
	end
	qty = math.clamp(wholeNumber(qty, 1), 1, 10)
	if (config.MaxStack or 1) <= 1 then
		qty = 1
	end
	local count = (config.Pack or 1) * qty
	if Inventory.SpaceFor(state.Bag, itemId) < count then
		status(player, "Kein Platz in deiner Tasche.")
		return false
	end
	local price = config.Price * qty
	if not ProgressService.SpendCoins(player, price) then
		status(player, "Nicht genug Münzen (" .. price .. " nötig).")
		return false
	end
	Inventory.Add(state.Bag, itemId, count)
	changed(player, state)
	status(player, "Gekauft: " .. (count > 1 and (count .. "× ") or "") .. config.Name .. " für " .. price .. " Münzen", true)
	return true
end

-- An einem Stand verkaufen (Platz der Tasche, count = Anzahl oder nil = alles)
function InventoryService.Sell(player, slot, count)
	if not inExtinction(player) or type(slot) ~= "number" then
		return false
	end
	local state = stateOf(player)
	local item = state and state.Bag.Slots[slot]
	if not item then
		return false
	end
	if not nearAnyStand(player) then
		status(player, "Verkaufen kannst du nur an einem Stand.")
		return false
	end
	if isOut(item) then
		status(player, "Pack das Fahrzeug erst ein (K).")
		return false
	end
	count = math.clamp(wholeNumber(count, item.Count), 1, item.Count)
	if state.Equipped == item then
		holster(player, state)
	end
	local price = ExtinctionConfig.SellPrice(item.Id, count)
	local name = ExtinctionConfig.Get(item.Id).Name
	item.Count -= count
	if item.Count <= 0 then
		state.Bag.Slots[slot] = nil
	end
	if price > 0 then
		ProgressService.AddCoins(player, price, "Verkauf")
	end
	changed(player, state)
	status(player, "Verkauft: " .. (count > 1 and (count .. "× ") or "") .. name .. " für " .. price .. " Münzen", true)
	return true
end

-- Stapel auf den Boden legen (kleine Tasche, die jeder aufheben kann)
function InventoryService.Drop(player, slot)
	if not inExtinction(player) or type(slot) ~= "number" then
		return false
	end
	local state = stateOf(player)
	local _, _, root = livingCharacter(player)
	local item = state and state.Bag.Slots[slot]
	if not item or not root or not InventoryService.DropItems then
		return false
	end
	if isOut(item) then
		status(player, "Pack das Fahrzeug erst ein (K).")
		return false
	end
	if state.Equipped == item then
		holster(player, state)
	end
	state.Bag.Slots[slot] = nil
	InventoryService.DropItems(player, { { Id = item.Id, Count = item.Count, Mag = item.Mag } },
		root.Position + root.CFrame.LookVector * 3)
	changed(player, state)
	return true
end

-- ---------- Für andere Dienste ----------

-- Tasche des Spielers (Inventory-Container) oder nil
function InventoryService.GetBag(player)
	local state = stateOf(player)
	return state and state.Bag
end

-- Nach einer Änderung von außen (Looten, Fahrzeug): speichern und anzeigen
function InventoryService.Changed(player)
	local state = states[player]
	if state then
		checkEquipped(player, state)
		changed(player, state)
	end
end

-- Items in die Tasche legen, gibt die Anzahl zurück, die gepasst hat
function InventoryService.Give(player, id, count, extra)
	local state = stateOf(player)
	if not state or not ExtinctionConfig.Get(id) then
		return 0
	end
	local added = Inventory.Add(state.Bag, id, count, extra)
	if added > 0 then
		changed(player, state)
	end
	return added
end

-- Tod oder Verlassen außerhalb der Safe Zone: ganze Tasche leeren (inkl. Waffe in der Hand mit ihrem Magazin),
-- gibt die Items zurück (für die Tasche am Boden). Das Lager bleibt.
function InventoryService.TakeAll(player)
	local state = stateOf(player)
	if not state then
		return {}
	end
	syncMag(player, state)
	if state.Equipped then
		state.Equipped = nil
		WeaponService.SetCarried(player, nil)
	end
	cancelUse(player, state)
	for _, item in state.Bag.Slots do
		item.Out = nil
	end
	local items = Inventory.Clear(state.Bag)
	changed(player, state)
	return items
end

-- Betreten der offenen Welt: Stand laden und anzeigen
function InventoryService.Enter(player)
	local state = stateOf(player)
	if state then
		state.Equipped = nil
		flush(player, state)
	end
end

-- Verlassen (in der Safe Zone): Waffe weg, Magazin sichern, Inventar bleibt
function InventoryService.Leave(player)
	local state = states[player]
	if not state then
		return
	end
	holster(player, state)
	cancelUse(player, state)
	for _, item in state.Bag.Slots do
		item.Out = nil
	end
	flush(player, state)
	for _, attribute in { "ExtBag", "ExtStash", "ExtEquipped" } do
		player:SetAttribute(attribute, nil)
	end
end

function InventoryService.Init()
	Remotes.ExtAction.OnServerEvent:Connect(function(player, action, ...)
		if type(action) ~= "string" then
			return
		end
		if action == "Use" then
			InventoryService.Use(player, ...)
		elseif action == "Move" then
			InventoryService.Move(player, ...)
		elseif action == "Buy" then
			InventoryService.Buy(player, ...)
		elseif action == "Sell" then
			InventoryService.Sell(player, ...)
		elseif action == "Drop" then
			InventoryService.Drop(player, ...)
		elseif action == "Holster" then
			InventoryService.Holster(player)
		elseif InventoryService.Handlers[action] then
			InventoryService.Handlers[action](player, ...)
		end
	end)

	-- Neuer Charakter: keine Waffe in der Hand, nichts in Benutzung
	local function onPlayer(player)
		player.CharacterAdded:Connect(function()
			local state = states[player]
			if state then
				state.Equipped = nil
				state.Using = nil
				if inExtinction(player) then
					flush(player, state)
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		task.defer(function()
			states[player] = nil
		end)
	end)

	-- Vor jedem Speichern: Magazin der Waffe in der Hand ins Profil
	ProgressService.OnBeforeSave(function(player)
		local state = states[player]
		if state and state.Profile == ProgressService.Get(player) then
			syncMag(player, state)
			state.Profile.Extinction = { Bag = Inventory.ToList(state.Bag), Stash = Inventory.ToList(state.Stash) }
		end
	end)

	-- Magazin-Änderungen (Schießen) gebündelt an Profil und Anzeige
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		for player, state in states do
			if state.Dirty and player.Parent then
				flush(player, state)
			end
		end
	end)
end

return InventoryService

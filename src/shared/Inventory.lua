-- Inventory (ModuleScript)
-- Reine Logik für Plätze mit Items (Tasche des Spielers, Lager, Taschen am Boden) – ohne Roblox-Objekte, damit
-- Server und Tests dieselben Regeln benutzen.
-- Container = { Size = n, Slots = { [Platz] = item } }, item = { Id = "Rifle", Count = 1, Mag = 30 }
-- Plätze 1..HotbarSlots der Tasche sind die Hotbar (Tasten 1-9). Stapelgrößen aus ExtinctionConfig.MaxStack.
-- Gespeichert/übertragen wird als Liste { { S = Platz, Id = ..., N = Anzahl, Mag = ..., Out = Fahrzeug draußen } }
-- (keine Lücken im JSON). Out gilt nur zur Laufzeit und wird beim Laden ignoriert.

local ExtinctionConfig = require(script.Parent.ExtinctionConfig)

local Inventory = {}

function Inventory.New(size)
	return { Size = size, Slots = {} }
end

local function copyItem(item)
	return { Id = item.Id, Count = item.Count, Mag = item.Mag }
end

-- Liste (gespeichert/JSON) -> Container. Unbekannte Items und Plätze außerhalb fallen weg.
function Inventory.FromList(list, size)
	local container = Inventory.New(size)
	if type(list) ~= "table" then
		return container
	end
	for _, entry in list do
		local slot = type(entry) == "table" and tonumber(entry.S)
		local id = type(entry) == "table" and entry.Id
		local count = type(entry) == "table" and math.floor(tonumber(entry.N) or 1)
		if slot and slot == math.floor(slot) and slot >= 1 and slot <= size and type(id) == "string"
			and ExtinctionConfig.Get(id) and count and count >= 1 and not container.Slots[slot] then
			container.Slots[slot] = { Id = id, Count = math.min(count, ExtinctionConfig.MaxStack(id)),
				Mag = tonumber(entry.Mag) and math.max(0, math.floor(entry.Mag)) or nil }
		end
	end
	return container
end

-- Container -> Liste, nach Platz sortiert
function Inventory.ToList(container)
	local list = {}
	for slot = 1, container.Size do
		local item = container.Slots[slot]
		if item then
			table.insert(list, { S = slot, Id = item.Id, N = item.Count, Mag = item.Mag, Out = item.Out })
		end
	end
	return list
end

function Inventory.Get(container, slot)
	return container.Slots[slot]
end

-- Stückzahl eines Items im ganzen Container
function Inventory.Count(container, id)
	local n = 0
	for _, item in container.Slots do
		if item.Id == id then
			n += item.Count
		end
	end
	return n
end

function Inventory.IsEmpty(container)
	return next(container.Slots) == nil
end

function Inventory.FreeSlots(container)
	local n = 0
	for slot = 1, container.Size do
		if not container.Slots[slot] then
			n += 1
		end
	end
	return n
end

-- Reihenfolge der leeren Plätze: prefer = "Hotbar" (erst 1..HotbarSlots), "Bag" (erst dahinter) oder nil (der Reihe nach)
local function emptySlots(container, prefer)
	local hotbar = ExtinctionConfig.HotbarSlots
	local first, second = {}, {}
	for slot = 1, container.Size do
		if not container.Slots[slot] then
			if prefer == "Bag" and slot <= hotbar then
				table.insert(second, slot)
			elseif prefer == "Hotbar" and slot > hotbar then
				table.insert(second, slot)
			else
				table.insert(first, slot)
			end
		end
	end
	for _, slot in second do
		table.insert(first, slot)
	end
	return first
end

-- Wo neue Items hin sollen: Munition lieber hinten in die Tasche, alles andere lieber auf die Hotbar
function Inventory.PreferFor(id)
	local item = ExtinctionConfig.Get(id)
	return item and item.Kind == "Ammo" and "Bag" or "Hotbar"
end

-- Wie viele Stück von id passen noch hinein (auf vorhandene Stapel und leere Plätze)?
function Inventory.SpaceFor(container, id)
	local max = ExtinctionConfig.MaxStack(id)
	if max <= 0 then
		return 0
	end
	local space = 0
	for slot = 1, container.Size do
		local item = container.Slots[slot]
		if not item then
			space += max
		elseif item.Id == id then
			space += math.max(0, max - item.Count)
		end
	end
	return space
end

-- count Stück hinzufügen: erst auf vorhandene Stapel, dann auf leere Plätze. extra = { Mag = ... } für Waffen.
-- Gibt zurück, wie viele hineingepasst haben (der Rest bleibt draußen).
function Inventory.Add(container, id, count, extra, prefer)
	local max = ExtinctionConfig.MaxStack(id)
	if max <= 0 or not count or count <= 0 then
		return 0
	end
	local left = math.floor(count)
	if max > 1 then
		for slot = 1, container.Size do
			local item = container.Slots[slot]
			if left <= 0 then
				break
			end
			if item and item.Id == id and item.Count < max then
				local put = math.min(left, max - item.Count)
				item.Count += put
				left -= put
			end
		end
	end
	for _, slot in emptySlots(container, prefer or Inventory.PreferFor(id)) do
		if left <= 0 then
			break
		end
		local put = math.min(left, max)
		container.Slots[slot] = { Id = id, Count = put, Mag = extra and extra.Mag or nil }
		left -= put
	end
	return math.floor(count) - left
end

-- count Stück von id entfernen (erst aus den hinteren Plätzen). Gibt zurück, wie viele entfernt wurden.
function Inventory.Remove(container, id, count)
	local left = math.floor(count or 0)
	for slot = container.Size, 1, -1 do
		if left <= 0 then
			break
		end
		local item = container.Slots[slot]
		if item and item.Id == id then
			local take = math.min(left, item.Count)
			item.Count -= take
			left -= take
			if item.Count <= 0 then
				container.Slots[slot] = nil
			end
		end
	end
	return math.floor(count or 0) - left
end

-- Einen Platz leeren und das Item zurückgeben
function Inventory.TakeSlot(container, slot)
	local item = container.Slots[slot]
	container.Slots[slot] = nil
	return item
end

-- Item von (from, fromSlot) nach (to, toSlot) bewegen. toSlot = nil: automatisch einsortieren (Stapel, freier Platz).
-- Gleiche stapelbare Items werden zusammengelegt (Rest bleibt liegen), sonst werden die Plätze getauscht.
-- Gibt true zurück, wenn sich etwas bewegt hat.
function Inventory.Move(from, fromSlot, to, toSlot)
	local item = from.Slots[fromSlot]
	if not item then
		return false
	end
	if toSlot == nil then
		if from == to then
			return false -- im selben Container braucht es einen Zielplatz
		end
		local moved = Inventory.Add(to, item.Id, item.Count, item, Inventory.PreferFor(item.Id))
		if moved <= 0 then
			return false
		end
		item.Count -= moved
		if item.Count <= 0 then
			from.Slots[fromSlot] = nil
		end
		return true
	end
	if type(toSlot) ~= "number" or toSlot < 1 or toSlot > to.Size or toSlot ~= math.floor(toSlot) then
		return false
	end
	if from == to and fromSlot == toSlot then
		return false
	end
	local target = to.Slots[toSlot]
	local max = ExtinctionConfig.MaxStack(item.Id)
	if target and target.Id == item.Id and max > 1 then
		local put = math.min(item.Count, max - target.Count)
		if put <= 0 then
			-- Ziel-Stapel voll: tauschen wie bei verschiedenen Items
			from.Slots[fromSlot], to.Slots[toSlot] = target, item
			return true
		end
		target.Count += put
		item.Count -= put
		if item.Count <= 0 then
			from.Slots[fromSlot] = nil
		end
		return true
	end
	from.Slots[fromSlot], to.Slots[toSlot] = target, item
	return true
end

-- Alle Items (Kopien) als Liste, z.B. für eine Tasche am Boden
function Inventory.Items(container)
	local list = {}
	for slot = 1, container.Size do
		local item = container.Slots[slot]
		if item then
			table.insert(list, copyItem(item))
		end
	end
	return list
end

-- Container leeren, Items (Kopien) zurückgeben
function Inventory.Clear(container)
	local list = Inventory.Items(container)
	container.Slots = {}
	return list
end

return Inventory

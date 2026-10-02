-- AttachmentConfig (ModuleScript)
-- Waffen-Aufsätze: werden in der Lobby (LOADOUT · AUFSÄTZE) mit Münzen gekauft und ausgerüstet, nicht im Match.
-- Gekauft und ausgerüstet wird pro WAFFE: haben zwei Agenten dieselbe Waffe, gelten auch dieselben Aufsätze.
-- Pro Platz (Mündung, Lauf, Griff, Magazin) ist höchstens ein Aufsatz ausgerüstet.
-- Spieler-Attribut "Attachments" (JSON): { Owned = { [Waffe] = { [Id] = true } }, Equipped = { [Waffe] = { [Platz] = Id } } }
-- Client (Fadenkreuz, Rückstoß) und Server (Schuss, Magazin, Nachladen) lesen die Wirkung über Effects().

local HttpService = game:GetService("HttpService")

local AttachmentConfig = {}

AttachmentConfig.Slots = {
	{ Id = "Muzzle", Name = "Mündung" },
	{ Id = "Barrel", Name = "Lauf" },
	{ Id = "Grip", Name = "Griff" },
	{ Id = "Magazine", Name = "Magazin" },
}

-- Wirkung als Faktoren: Recoil (Rückstoß), Spread (Streuung immer), HipSpread (Streuung ohne Zielen),
-- MoveSpread (zusätzliche Streuung in Bewegung), Range (Reichweite), Mag (Magazingröße), Reload (Nachladezeit)
AttachmentConfig.List = {
	{ Id = "Compensator", Slot = "Muzzle", Name = "Kompensator", Description = "−20 % Rückstoß", Price = 800,
		Effects = { Recoil = 0.8 } },
	{ Id = "MuzzleBrake", Slot = "Muzzle", Name = "Mündungsbremse", Description = "−15 % Streuung", Price = 900,
		Effects = { Spread = 0.85 } },
	{ Id = "LongBarrel", Slot = "Barrel", Name = "Langer Lauf", Description = "+30 % Reichweite, etwas mehr Streuung in Bewegung",
		Price = 900, Effects = { Range = 1.3, MoveSpread = 1.15 } },
	{ Id = "ShortBarrel", Slot = "Barrel", Name = "Kurzer Lauf", Description = "−25 % Streuung in Bewegung, −15 % Reichweite",
		Price = 700, Effects = { MoveSpread = 0.75, Range = 0.85 } },
	{ Id = "VerticalGrip", Slot = "Grip", Name = "Vertikalgriff", Description = "−20 % Rückstoß", Price = 700,
		Effects = { Recoil = 0.8 } },
	{ Id = "Laser", Slot = "Grip", Name = "Laser", Description = "−25 % Streuung aus der Hüfte", Price = 800,
		Effects = { HipSpread = 0.75 } },
	{ Id = "ExtendedMag", Slot = "Magazine", Name = "Erweitertes Magazin", Description = "+30 % Magazin", Price = 900,
		Effects = { Mag = 1.3 } },
	{ Id = "FastMag", Slot = "Magazine", Name = "Schnellmagazin", Description = "Nachladen 25 % schneller", Price = 800,
		Effects = { Reload = 0.75 } },
}

local byId = {}
for _, item in AttachmentConfig.List do
	byId[item.Id] = item
end

function AttachmentConfig.Get(id)
	return byId[id]
end

-- Aufsätze eines Platzes (für die Lobby)
function AttachmentConfig.ForSlot(slotId)
	local list = {}
	for _, item in AttachmentConfig.List do
		if item.Slot == slotId then
			table.insert(list, item)
		end
	end
	return list
end

-- Daten des Spielers aus dem Attribut
function AttachmentConfig.Data(player)
	local raw = player:GetAttribute("Attachments")
	if type(raw) == "string" then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(data) == "table" then
			data.Owned = data.Owned or {}
			data.Equipped = data.Equipped or {}
			return data
		end
	end
	return { Owned = {}, Equipped = {} }
end

function AttachmentConfig.Owns(player, weaponName, id)
	local owned = AttachmentConfig.Data(player).Owned[weaponName]
	return owned ~= nil and owned[id] == true
end

-- Ausgerüstete Aufsätze einer Waffe: { [Platz] = Id }
function AttachmentConfig.Equipped(player, weaponName)
	return AttachmentConfig.Data(player).Equipped[weaponName] or {}
end

-- Ausgerüstete und gekaufte Aufsätze einer Waffe als Liste von Ids (für die 3D-Modelle)
function AttachmentConfig.EquippedList(player, weaponName)
	local list = {}
	for _, id in AttachmentConfig.Equipped(player, weaponName) do
		if byId[id] and AttachmentConfig.Owns(player, weaponName, id) then
			table.insert(list, id)
		end
	end
	return list
end

local NEUTRAL = { Recoil = 1, Spread = 1, HipSpread = 1, MoveSpread = 1, Range = 1, Mag = 1, Reload = 1 }

-- Zusammengerechnete Wirkung der ausgerüsteten Aufsätze einer Waffe (alle Faktoren, 1 = keine Änderung)
function AttachmentConfig.Effects(player, weaponName)
	local result = table.clone(NEUTRAL)
	if not player or not weaponName then
		return result
	end
	for _, id in AttachmentConfig.Equipped(player, weaponName) do
		local item = byId[id]
		if item and AttachmentConfig.Owns(player, weaponName, id) then
			for key, factor in item.Effects do
				result[key] = (result[key] or 1) * factor
			end
		end
	end
	return result
end

return AttachmentConfig

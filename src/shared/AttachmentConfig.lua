-- AttachmentConfig (ModuleScript)
-- Waffen-Aufsätze: werden in der Lobby (LOADOUT · AUFSÄTZE) mit Münzen gekauft und ausgerüstet, nicht im Match.
-- Gekauft und ausgerüstet wird pro WAFFE: haben zwei Agenten dieselbe Waffe, gelten auch dieselben Aufsätze.
-- Pro Platz (Mündung, Lauf, Griff, Magazin, Visier) ist höchstens ein Aufsatz ausgerüstet.
-- Spieler-Attribut "Attachments" (JSON): { Owned = { [Waffe] = { [Id] = true } }, Equipped = { [Waffe] = { [Platz] = Id } } }
-- Client (Fadenkreuz, Rückstoß) und Server (Schuss, Magazin, Nachladen) lesen die Wirkung über Effects().
-- Offene Welt (Extinction): Dort gelten die Lobby-Aufsätze nicht. Aufsätze sind Items, die an einer Waffe im Inventar
-- hängen; der Server schreibt die der Waffe in der Hand ins Spieler-Attribut "ExtAttach" ({ W = Waffe, A = { [Platz] = Id } }).
-- Tier = Seltenheit als Item in Extinction (2 = häufig, 3 = selten, 4 = sehr selten, nur zu finden).

local HttpService = game:GetService("HttpService")

local Modes = require(script.Parent.Modes)

local AttachmentConfig = {}

AttachmentConfig.Slots = {
	{ Id = "Muzzle", Name = "Mündung" },
	{ Id = "Barrel", Name = "Lauf" },
	{ Id = "Grip", Name = "Griff" },
	{ Id = "Magazine", Name = "Magazin" },
	{ Id = "Optic", Name = "Visier" },
}

-- Wirkung als Faktoren: Recoil (Rückstoß), Spread (Streuung immer), HipSpread (Streuung ohne Zielen),
-- MoveSpread (zusätzliche Streuung in Bewegung), Range (Reichweite), Falloff (ab wann der Schaden sinkt),
-- Mag (Magazingröße), Reload (Nachladezeit). Silenced = true: Gegner sehen kein Mündungsfeuer/keine Leuchtspur.
-- Pros/Cons: kurze Plus-/Minus-Texte für die Lobby (grün/rot)
AttachmentConfig.List = {
	-- Mündung
	{ Id = "Compensator", Tier = 2, Slot = "Muzzle", Name = "Kompensator", Description = "−20 % Rückstoß", Price = 800,
		Effects = { Recoil = 0.8 }, Pros = { "−20 % Rückstoß" }, Cons = {} },
	{ Id = "MuzzleBrake", Tier = 3, Slot = "Muzzle", Name = "Mündungsbremse", Description = "−15 % Streuung", Price = 900,
		Effects = { Spread = 0.85 }, Pros = { "−15 % Streuung" }, Cons = {} },
	{ Id = "Suppressor", Tier = 4, Slot = "Muzzle", Name = "Schalldämpfer", Description = "Leise, für Gegner kein Mündungsfeuer",
		Price = 1100, Effects = { Silenced = true, Range = 0.9 }, Pros = { "Leise, kein Feuer/Leuchtspur" },
		Cons = { "−10 % Reichweite" } },
	-- Lauf
	{ Id = "LongBarrel", Tier = 3, Slot = "Barrel", Name = "Langer Lauf", Description = "+30 % Reichweite, etwas mehr Streuung in Bewegung",
		Price = 900, Effects = { Range = 1.3, MoveSpread = 1.15 }, Pros = { "+30 % Reichweite" },
		Cons = { "+15 % Streuung in Bewegung" } },
	{ Id = "ShortBarrel", Tier = 2, Slot = "Barrel", Name = "Kurzer Lauf", Description = "−25 % Streuung in Bewegung, −15 % Reichweite",
		Price = 700, Effects = { MoveSpread = 0.75, Range = 0.85 }, Pros = { "−25 % Streuung in Bewegung" },
		Cons = { "−15 % Reichweite" } },
	{ Id = "HeavyBarrel", Tier = 3, Slot = "Barrel", Name = "Schwerer Lauf", Description = "Schaden fällt erst viel später ab",
		Price = 1000, Effects = { Falloff = 1.6, HipSpread = 1.1 }, Pros = { "Schaden fällt 60 % später ab" },
		Cons = { "+10 % Streuung aus der Hüfte" } },
	-- Griff
	{ Id = "VerticalGrip", Tier = 2, Slot = "Grip", Name = "Vertikalgriff", Description = "−20 % Rückstoß", Price = 700,
		Effects = { Recoil = 0.8 }, Pros = { "−20 % Rückstoß" }, Cons = {} },
	{ Id = "Laser", Tier = 2, Slot = "Grip", Name = "Laser", Description = "−25 % Streuung aus der Hüfte", Price = 800,
		Effects = { HipSpread = 0.75 }, Pros = { "−25 % Streuung aus der Hüfte" }, Cons = {} },
	{ Id = "AngledGrip", Tier = 3, Slot = "Grip", Name = "Winkelgriff", Description = "Etwas weniger Rückstoß und Hüftstreuung",
		Price = 900, Effects = { Recoil = 0.9, HipSpread = 0.88 }, Pros = { "−10 % Rückstoß", "−12 % Hüftstreuung" },
		Cons = {} },
	-- Magazin
	{ Id = "ExtendedMag", Tier = 3, Slot = "Magazine", Name = "Erweitertes Magazin", Description = "+30 % Magazin", Price = 900,
		Effects = { Mag = 1.3 }, Pros = { "+30 % Magazin" }, Cons = {} },
	{ Id = "FastMag", Tier = 2, Slot = "Magazine", Name = "Schnellmagazin", Description = "Nachladen 25 % schneller", Price = 800,
		Effects = { Reload = 0.75 }, Pros = { "−25 % Nachladezeit" }, Cons = {} },
	{ Id = "DrumMag", Tier = 4, Slot = "Magazine", Name = "Trommelmagazin", Description = "+60 % Magazin, langsameres Nachladen",
		Price = 1200, Effects = { Mag = 1.6, Reload = 1.3 }, Pros = { "+60 % Magazin" }, Cons = { "+30 % Nachladezeit" } },
	-- Visier (nur lange Waffen mit fertigem 3D-Modell; Modell in Assets.Attachments.HoloSight)
	{ Id = "HoloSight", Tier = 3, Slot = "Optic", Name = "Holo-Visier", Description = "Klares Zielbild mit Leuchtpunkt",
		Price = 900, Effects = { Spread = 0.95 }, Pros = { "Klares Zielbild", "−5 % Streuung" }, Cons = {} },
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

-- Offene Welt: Aufsätze der Waffe in der Hand (Attribut "ExtAttach"), sonst keine
local function survivalData(player)
	local data = { Owned = {}, Equipped = {} }
	local raw = player:GetAttribute("ExtAttach")
	if type(raw) ~= "string" then
		return data
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(decoded) ~= "table" or type(decoded.W) ~= "string" or type(decoded.A) ~= "table" then
		return data
	end
	local equipped, owned = {}, {}
	for slot, id in decoded.A do
		local item = byId[id]
		if item and item.Slot == slot then
			equipped[slot] = id
			owned[id] = true
		end
	end
	data.Equipped[decoded.W] = equipped
	data.Owned[decoded.W] = owned
	return data
end

-- Daten des Spielers aus dem Attribut
function AttachmentConfig.Data(player)
	if Modes.IsSurvival(player:GetAttribute("Mode")) then
		return survivalData(player)
	end
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

local NEUTRAL = { Recoil = 1, Spread = 1, HipSpread = 1, MoveSpread = 1, Range = 1, Falloff = 1, Mag = 1, Reload = 1,
	Silenced = false }

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
				if type(factor) == "boolean" then
					result[key] = result[key] or factor
				else
					result[key] = (result[key] or 1) * factor
				end
			end
		end
	end
	return result
end

return AttachmentConfig

-- HideoutConfig (ModuleScript)
-- Eigenes Versteck in der offenen Welt (EXTINCTION), wie das Hideout in Tarkov: Am Haus VERSTECK im Camp (Punkt "Hideout"
-- in der Gruppe Stands) baut man Module in Stufen aus. Jede Stufe kostet Münzen und Items (aus Tasche oder Lager) und gibt
-- einen Bonus in der offenen Welt:
--   Bed        Feldbett: mehr Leben (Value = zusätzliche Lebenspunkte)
--   Workbench  Werkbank: Rabatt beim Kaufen an den Ständen (Value = Prozent)
--   Medical    Sanistation: Heilen und Westen anlegen geht schneller (Value = Prozent weniger Zeit)
--   Generator  Generator: Münzen pro Stunde, auch offline, höchstens GeneratorCap Sekunden lang; im Versteck abholen
-- Gespeichert im Profil unter Hideout = { [Modul] = Stufe, GenAt = Zeitpunkt (os.time) der letzten Abholung }.
-- Spieler-Attribut "Hideout" (JSON, gleiche Form) für den Client und für die Boni (Server und Client lesen Value).

local HttpService = game:GetService("HttpService")

local HideoutConfig = {}

HideoutConfig.Point = "Hideout"
HideoutConfig.GeneratorCap = 8 * 3600

-- Levels[i] = { Coins, Items = { { Id, Anzahl } }, Value }
HideoutConfig.Modules = {
	{ Id = "Bed", Name = "Feldbett", Text = "Mehr Leben in Extinction", Format = "+%d Leben",
		Levels = {
			{ Coins = 300, Items = {}, Value = 10 },
			{ Coins = 900, Items = { { "Bandage", 3 } }, Value = 20 },
			{ Coins = 2500, Items = { { "Medkit", 2 } }, Value = 30 },
		} },
	{ Id = "Workbench", Name = "Werkbank", Text = "Rabatt bei den Händlern", Format = "-%d %% beim Kaufen",
		Levels = {
			{ Coins = 600, Items = {}, Value = 5 },
			{ Coins = 1800, Items = { { "Ammo_9mm", 60 } }, Value = 10 },
			{ Coins = 4500, Items = { { "Att_ExtendedMag", 1 } }, Value = 15 },
		} },
	{ Id = "Medical", Name = "Sanistation", Text = "Heilen und Westen anlegen geht schneller", Format = "%d %% schneller heilen",
		Levels = {
			{ Coins = 500, Items = {}, Value = 15 },
			{ Coins = 1500, Items = { { "Medkit", 2 } }, Value = 30 },
			{ Coins = 4000, Items = { { "Adrenaline", 2 } }, Value = 45 },
		} },
	{ Id = "Generator", Name = "Generator", Text = "Münzen pro Stunde, auch wenn du offline bist", Format = "%d Münzen pro Stunde",
		Levels = {
			{ Coins = 1000, Items = {}, Value = 120 },
			{ Coins = 3000, Items = { { "V_Quad", 1 } }, Value = 300 },
			{ Coins = 7000, Items = { { "V_Pickup", 1 } }, Value = 600 },
		} },
}

local byId = {}
for _, module in HideoutConfig.Modules do
	byId[module.Id] = module
end

function HideoutConfig.Get(id)
	return byId[id]
end

-- Daten aus dem Spieler-Attribut (Server und Client)
function HideoutConfig.Data(player)
	local raw = player and player:GetAttribute("Hideout")
	if type(raw) == "string" then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(data) == "table" then
			return data
		end
	end
	return {}
end

-- Ausgebaute Stufe eines Moduls (0 = nicht gebaut)
function HideoutConfig.Level(data, id)
	local module = byId[id]
	local level = math.floor(tonumber(data and data[id]) or 0)
	return module and math.clamp(level, 0, #module.Levels) or 0
end

-- Bonus eines Moduls für einen Spieler (0 ohne Ausbau)
function HideoutConfig.Value(player, id)
	local data = HideoutConfig.Data(player)
	local level = HideoutConfig.Level(data, id)
	return level > 0 and byId[id].Levels[level].Value or 0
end

-- Münzen, die der Generator seit der letzten Abholung erzeugt hat (abgerundet)
function HideoutConfig.Pending(data, now)
	local level = HideoutConfig.Level(data, "Generator")
	if level == 0 then
		return 0
	end
	local since = math.clamp((now or os.time()) - (tonumber(data.GenAt) or now or os.time()), 0, HideoutConfig.GeneratorCap)
	return math.floor(byId.Generator.Levels[level].Value * since / 3600)
end

return HideoutConfig

-- HideoutConfig (ModuleScript)
-- Eigenes Versteck in der offenen Welt (EXTINCTION), wie das Hideout in Tarkov: Am Haus VERSTECK im Camp (Punkt "Hideout"
-- in der Gruppe Stands) baut man erst das Versteck selbst in Stufen aus (Tiers) und darin Module in Ausbaustufen. Jede
-- Ausbaustufe kostet Münzen und Items (aus Tasche oder Lager) und braucht eine Mindest-Versteckstufe (Module.Tiers[i]).
-- Die Boni sind Komfort und kleine, gedeckelte Vorteile, keine rohe Kampfkraft:
--   Bed        Feldbett: etwas mehr Leben (Value = zusätzliche Lebenspunkte)
--   Workbench  Werkbank: Rabatt beim Kaufen an den Ständen (Value = Prozent)
--   Medical    Sanistation: Heilen und Westen anlegen geht schneller (Value = Prozent weniger Zeit)
--   Generator  Generator: Münzen pro Stunde, auch offline, höchstens GeneratorCap Sekunden lang; im Versteck abholen
--   Shelf      Lagerregal: mehr Plätze im Lager (Value = zusätzliche Plätze)
--   AmmoPress  Munitionspresse: Munitionspakete pro Stunde (wie der Generator, höchstens PressCap), Sorte wählbar
-- Dazu ohne Ausbau: Funkgerät (ab Stufe Features.Radio, ein Tagesauftrag) und Trophäenwand (ab Stufe Features.Trophies).
-- Versteckstufe 1 gibt es gratis ab Spielerlevel MinLevel (LevelConfig, inkl. Prestige). Die Stufen 2 bis 4 kauft man mit
-- Münzen und Items (ab ihrem Spielerlevel) oder direkt mit Robux (RobuxConfig, Produkt HideoutTier<n>, ohne Level-Grenze).
-- Gespeichert im Profil unter Hideout = { Tier = gekaufte Stufe, [Modul] = Ausbau, GenAt, PressAt (os.time der letzten
-- Abholung), PressAmmo (Item-Id), Radio = { Day, Base, Claimed } }.
-- Spieler-Attribut "Hideout" (JSON, gleiche Form) für den Client und für die Boni (Server und Client lesen Value).

local HttpService = game:GetService("HttpService")
local LevelConfig = require(script.Parent.LevelConfig)

local HideoutConfig = {}

HideoutConfig.Point = "Hideout"
HideoutConfig.MinLevel = 4
HideoutConfig.GeneratorCap = 8 * 3600
HideoutConfig.PressCap = 8 * 3600

-- Versteckstufen: MinLevel (Spielerlevel für den Kauf mit Münzen), Coins, Items, Product (Robux, Id in RobuxConfig.Products),
-- Text (was die Stufe bringt, im Versteck-Fenster)
HideoutConfig.Tiers = {
	{ Name = "Unterschlupf", MinLevel = 4, Coins = 0, Items = {},
		Text = "Feldbett, Werkbank, Sanistation und Generator bis Ausbau 1" },
	{ Name = "Werkstatt", MinLevel = 10, Coins = 5000, Items = { { "Ammo_Rifle", 60 }, { "Medkit", 2 } }, Product = "HideoutTier2",
		Text = "Module bis Ausbau 2, neu: Lagerregal" },
	{ Name = "Bunker", MinLevel = 20, Coins = 15000, Items = { { "Adrenaline", 2 }, { "V_Quad", 1 } }, Product = "HideoutTier3",
		Text = "Module bis Ausbau 3, neu: Munitionspresse und Funkgerät" },
	{ Name = "Kommandozentrale", MinLevel = 35, Coins = 40000, Items = { { "Adrenaline", 3 }, { "V_Pickup", 1 } },
		Product = "HideoutTier4", Text = "Lagerregal und Munitionspresse bis Ausbau 2, neu: Trophäenwand" },
}

-- Funktionen ohne Ausbau: ab welcher Versteckstufe
HideoutConfig.Features = { Radio = 3, Trophies = 4 }

-- Munitionspresse: wählbare Sorten (ein Paket = Pack der Sorte aus ExtinctionConfig)
HideoutConfig.PressAmmo = { "Ammo_9mm", "Ammo_Magnum", "Ammo_Shell", "Ammo_Rifle" }

-- Funkgerät: ein Auftrag pro Tag (UTC), reihum aus dieser Liste; Stat = Statistik im Profil (wie bei den Erfolgen)
HideoutConfig.Radio = {
	Coins = 600,
	XP = 300,
	Tasks = {
		{ Stat = "ExtZombies", Need = 60, Text = "Erledige {1} Zombies" },
		{ Stat = "ExtCaches", Need = 3, Text = "Brich {1} Vorratslager auf" },
		{ Stat = "ExtMissions", Need = 3, Text = "Erledige {1} Aufträge" },
		{ Stat = "ExtBotKills", Need = 12, Text = "Erledige {1} Banditen" },
		{ Stat = "ExtBrutes", Need = 3, Text = "Erledige {1} Brocken" },
		{ Stat = "ExtNests", Need = 1, Text = "Zerstöre {1} Zombienest" },
	},
}

-- Trophäenwand: diese Statistiken (Profil-Stats, Spieler-Attribut "Stats") mit Namen
HideoutConfig.Trophies = {
	{ Stat = "ExtZombies", Name = "Zombies" },
	{ Stat = "ExtBrutes", Name = "Brocken" },
	{ Stat = "ExtPlayerKills", Name = "Spieler" },
	{ Stat = "ExtConvoys", Name = "Konvois" },
	{ Stat = "ExtMissions", Name = "Aufträge" },
}

-- Levels[i] = { Coins, Items = { { Id, Anzahl } }, Value }; Tiers[i] = nötige Versteckstufe für Ausbau i
HideoutConfig.Modules = {
	{ Id = "Bed", Name = "Feldbett", Text = "Etwas mehr Leben in Extinction", Format = "+%d Leben", Tiers = { 1, 2, 3 },
		Levels = {
			{ Coins = 300, Items = {}, Value = 5 },
			{ Coins = 900, Items = { { "Bandage", 3 } }, Value = 10 },
			{ Coins = 2500, Items = { { "Medkit", 2 } }, Value = 15 },
		} },
	{ Id = "Workbench", Name = "Werkbank", Text = "Rabatt bei den Händlern", Format = "-%d %% beim Kaufen", Tiers = { 1, 2, 3 },
		Levels = {
			{ Coins = 600, Items = {}, Value = 5 },
			{ Coins = 1800, Items = { { "Ammo_9mm", 60 } }, Value = 10 },
			{ Coins = 4500, Items = { { "Att_Rifle_ExtendedMag", 1 } }, Value = 15 },
		} },
	{ Id = "Medical", Name = "Sanistation", Text = "Heilen und Westen anlegen geht schneller", Format = "%d %% schneller heilen",
		Tiers = { 1, 2, 3 },
		Levels = {
			{ Coins = 500, Items = {}, Value = 15 },
			{ Coins = 1500, Items = { { "Medkit", 2 } }, Value = 30 },
			{ Coins = 4000, Items = { { "Adrenaline", 2 } }, Value = 45 },
		} },
	{ Id = "Generator", Name = "Generator", Text = "Münzen pro Stunde, auch wenn du offline bist", Format = "%d Münzen pro Stunde",
		Tiers = { 1, 2, 3 },
		Levels = {
			{ Coins = 1000, Items = {}, Value = 120 },
			{ Coins = 3000, Items = { { "V_Quad", 1 } }, Value = 300 },
			{ Coins = 7000, Items = { { "V_Pickup", 1 } }, Value = 600 },
		} },
	{ Id = "Shelf", Name = "Lagerregal", Text = "Mehr Plätze im Lager", Format = "+%d Lagerplätze", Tiers = { 2, 4 },
		Levels = {
			{ Coins = 2000, Items = {}, Value = 10 },
			{ Coins = 8000, Items = { { "V_Quad", 1 } }, Value = 20 },
		} },
	{ Id = "AmmoPress", Name = "Munitionspresse", Text = "Munition pro Stunde, auch wenn du offline bist",
		Format = "%d Pakete pro Stunde", Tiers = { 3, 4 },
		Levels = {
			{ Coins = 6000, Items = { { "Ammo_Rifle", 90 } }, Value = 1 },
			{ Coins = 12000, Items = { { "Adrenaline", 2 } }, Value = 2 },
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

-- Versteckstufe: gekaufte Stufe (data.Tier), Stufe 1 gibt es gratis ab Spielerlevel MinLevel (0 = noch gesperrt)
function HideoutConfig.Tier(player, data)
	data = data or HideoutConfig.Data(player)
	local bought = math.clamp(math.floor(tonumber(data.Tier) or 0), 0, #HideoutConfig.Tiers)
	local free = (player and LevelConfig.Get(player).Total >= HideoutConfig.MinLevel) and 1 or 0
	return math.max(bought, free)
end

-- Versteck schon freigeschaltet? (Spielerlevel ab MinLevel oder eine Stufe mit Robux gekauft)
function HideoutConfig.Unlocked(player, data)
	return player ~= nil and HideoutConfig.Tier(player, data) >= 1
end

-- Funktion ohne Ausbau ("Radio", "Trophies") schon da?
function HideoutConfig.HasFeature(player, feature, data)
	return HideoutConfig.Tier(player, data) >= (HideoutConfig.Features[feature] or math.huge)
end

-- Tageszahl (UTC) und Tagesauftrag des Funkgeräts für diesen Tag
function HideoutConfig.Day(now)
	return math.floor((now or os.time()) / 86400)
end

function HideoutConfig.RadioTask(day)
	local tasks = HideoutConfig.Radio.Tasks
	return tasks[math.floor(day) % #tasks + 1]
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

-- Zusätzliche Lagerplätze aus den Versteck-Daten (Profil oder Attribut)
function HideoutConfig.StashBonus(data)
	local level = HideoutConfig.Level(data, "Shelf")
	return level > 0 and byId.Shelf.Levels[level].Value or 0
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

-- Munitionspakete der Presse seit der letzten Abholung (abgerundet)
function HideoutConfig.PressPending(data, now)
	local level = HideoutConfig.Level(data, "AmmoPress")
	if level == 0 then
		return 0
	end
	local since = math.clamp((now or os.time()) - (tonumber(data.PressAt) or now or os.time()), 0, HideoutConfig.PressCap)
	return math.floor(byId.AmmoPress.Levels[level].Value * since / 3600)
end

-- Gewählte Munitionssorte der Presse
function HideoutConfig.PressAmmoOf(data)
	local id = data and data.PressAmmo
	return table.find(HideoutConfig.PressAmmo, id) and id or HideoutConfig.PressAmmo[1]
end

return HideoutConfig

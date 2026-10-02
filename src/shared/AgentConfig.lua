-- AgentConfig (ModuleScript)
-- Alle Agenten mit Werten, Waffen (Loadout) und Fähigkeit, dazu das Level-System.
-- Fähigkeits-Typen: "Boost" (schneller), "Wall" (Deckungswand), "Heal" (Selbstheilung),
-- "Reveal" (zeigt Gegner durch Wände), "Cloak" (fast unsichtbar), "Dash" (Sprung nach vorne),
-- "TeamHeal" (heilt Teamkollegen in der Nähe), "Trap" (Stacheldraht: verlangsamt + Schaden),
-- "Turret" (Geschützturm schießt selbstständig)
-- Primaries = wählbare Primärwaffen (wie bei RC zwei zur Auswahl), Loadout[2] = Sekundärwaffe
-- Passive = passive Eigenschaft (wie bei RC), Wirkung in den jeweiligen Diensten
-- Price = Münzen zum Freischalten (ohne Price: von Anfang an verfügbar)
-- Gadget-Typen (Taste G): "Frag" (Splittergranate), "Flash" (Blendgranate), "Smoke" (Rauch),
-- "Sensor" (Mine, die vorbeilaufende Gegner markiert)

local HttpService = game:GetService("HttpService")

local AgentConfig = {}

AgentConfig.AbilityKey = Enum.KeyCode.Q
AgentConfig.GadgetKey = Enum.KeyCode.G
AgentConfig.UltimateKey = Enum.KeyCode.F

-- Ultimate (Taste F, Touch-Knopf, Controller L1+R1): lädt über Schaden, Kills und langsam über die Zeit
-- (Spieler-Attribut "UltCharge" 0-100). Voll ausgelöst: ÜBERLADUNG für jeden Agenten gleich.
AgentConfig.Ultimate = {
	Name = "Überladung",
	Description = "Volles Leben, +25 Rüstung, Fähigkeit sofort bereit und +1 Gadget-Ladung.",
	ChargePerDamage = 0.25, -- Prozent pro Schadenspunkt (400 Schaden = voll)
	ChargePerKill = 15,     -- Prozent pro Kill bzw. Niederschlag
	ChargePerSecond = 0.3,  -- Prozent pro Sekunde, solange man im Kampf lebt
	Armor = 25,
}

-- ---------- Level-System ----------
AgentConfig.XPPerLevel = 500   -- XP pro Level
AgentConfig.MaxLevel = 20
AgentConfig.XPRewards = {
	Kill = 100,
	Headshot = 25,   -- zusätzlich zum Kill
	RoundWin = 150,  -- Drop: Runde gewonnen (ganzes Team)
	MatchWin = 400,  -- Drop: Match gewonnen (ganzes Team)
	FFAWin = 400,    -- Free-for-All: Runde gewonnen
	Revive = 50,     -- Teamkollegen wiederbelebt
	Assist = 30,     -- mindestens 25 Schaden am Opfer, aber nicht der Kill
}
-- Waffen-Skins als Belohnung (höchstes erreichtes Level zuerst)
AgentConfig.Skins = {
	{ Level = 10, Name = "Diamant", Color = Color3.fromRGB(90, 220, 255), Material = Enum.Material.Neon },
	{ Level = 5, Name = "Gold", Color = Color3.fromRGB(212, 175, 55), Material = Enum.Material.Metal },
}

-- Visier am Helm: dunkel getöntes Glas mit leichtem Schimmer in der Agentenfarbe (kein Leuchten)
AgentConfig.VisorMaterial = Enum.Material.Glass
function AgentConfig.VisorColor(accent)
	return Color3.fromRGB(16, 18, 22):Lerp(accent, 0.35)
end

-- ---------- Agenten ----------
-- Color = Erkennungsfarbe (gedeckt): Uniform (abgedunkelt), Weste, Visier-Schimmer, Menüs
AgentConfig.Agents = {
	{
		Id = "Viper",
		Name = "VIPER",
		Role = "Scout",
		Description = "Schnell und wendig, hält dafür weniger aus.",
		Color = Color3.fromRGB(92, 166, 118),
		Health = 90,
		WalkSpeed = 18,
		Loadout = { "SMG", "Pistol" },
		Primaries = { "SMG", "Rifle" }, -- wählbare Primärwaffen (erste = Standard)
		Gadget = { Type = "Frag", Name = "Splittergranate", Charges = 1, Damage = 90, Radius = 14, Fuse = 2 },
		Passive = { Type = "Reload", Name = "Schnelle Hände", Description = "Lädt 15 % schneller nach." },
		Ability = {
			Type = "Boost",
			Name = "Adrenalin",
			Description = "4 Sekunden lang 60% schneller.",
			Cooldown = 15,
			Duration = 4,
			SpeedMultiplier = 1.6,
		},
	},
	{
		Id = "Bastion",
		Name = "BASTION",
		Role = "Verteidiger",
		Description = "Viel Leben, dafür etwas langsamer. Stark auf kurze Distanz.",
		Color = Color3.fromRGB(88, 124, 186),
		Health = 125,
		WalkSpeed = 15,
		Loadout = { "Shotgun", "Revolver" },
		Primaries = { "Shotgun", "SMG" }, -- wählbare Primärwaffen (erste = Standard)
		Gadget = { Type = "Flash", Name = "Blendgranate", Charges = 1, Radius = 40, Duration = 3, Fuse = 1.5 },
		Passive = { Type = "Armor", Name = "Panzerung", Description = "Startet jedes Leben mit 15 Rüstung." },
		Ability = {
			Type = "Wall",
			Name = "Schutzwand",
			Description = "Stellt 10 Sekunden eine Wand vor dir auf, die Schüsse blockt.",
			Cooldown = 20,
			Duration = 10,
			Size = Vector3.new(10, 7, 1.5),
		},
	},
	{
		Id = "Mender",
		Name = "MENDER",
		Role = "Sanitäter",
		Description = "Ausgeglichen und kann sich selbst heilen.",
		Color = Color3.fromRGB(196, 92, 86),
		Health = 100,
		WalkSpeed = 16,
		Loadout = { "Rifle", "Pistol" },
		Primaries = { "Rifle", "DMR" }, -- wählbare Primärwaffen (erste = Standard)
		Gadget = { Type = "Smoke", Name = "Rauchgranate", Charges = 1, Radius = 14, Duration = 12, Fuse = 1.5 },
		Passive = { Type = "Revive", Name = "Feldarzt", Description = "Belebt Teamkollegen 30 % schneller wieder." },
		Ability = {
			Type = "Heal",
			Name = "Nano-Heilung",
			Description = "Heilt 50 Leben über 2 Sekunden.",
			Cooldown = 18,
			Duration = 2,
			Amount = 50,
		},
	},
	{
		Id = "Hawk",
		Name = "HAWK",
		Role = "Aufklärer",
		Description = "Präzise auf große Distanz, findet versteckte Gegner.",
		Color = Color3.fromRGB(200, 168, 84),
		Health = 95,
		WalkSpeed = 16,
		Loadout = { "DMR", "Pistol" },
		Primaries = { "DMR", "Rifle" }, -- wählbare Primärwaffen (erste = Standard)
		Gadget = { Type = "Sensor", Name = "Sensor-Mine", Charges = 1, Radius = 18, Duration = 30 },
		Passive = { Type = "MarkOnHit", Name = "Adlerauge", Description = "Getroffene Gegner werden 2 s für das Team markiert." },
		Ability = {
			Type = "Reveal",
			Name = "Radar-Puls",
			Description = "Zeigt deinem Team 4 Sekunden lang alle Gegner in 120 Studs durch Wände.",
			Cooldown = 22,
			Duration = 4,
			Radius = 120,
		},
	},
	{
		Id = "Ghost",
		Name = "GHOST",
		Price = 1500,
		Role = "Infiltrator",
		Description = "Schleicht sich unbemerkt hinter die Linien.",
		Color = Color3.fromRGB(136, 140, 152),
		Health = 90,
		WalkSpeed = 17,
		Loadout = { "SMG", "Revolver" },
		Primaries = { "SMG", "Shotgun" }, -- wählbare Primärwaffen (erste = Standard)
		Gadget = { Type = "Flash", Name = "Blendgranate", Charges = 1, Radius = 40, Duration = 3, Fuse = 1.5 },
		Passive = { Type = "SensorImmune", Name = "Leise", Description = "Sensor-Minen erkennen Ghost nicht." },
		Ability = {
			Type = "Cloak",
			Name = "Tarnung",
			Description = "5 Sekunden fast unsichtbar. Endet, sobald du schießt.",
			Cooldown = 20,
			Duration = 5,
		},
	},
	{
		Id = "Blaze",
		Name = "BLAZE",
		Price = 1500,
		Role = "Stürmer",
		Description = "Geht als Erster rein – schnell und auf kurze Distanz tödlich.",
		Color = Color3.fromRGB(206, 112, 58),
		Health = 100,
		WalkSpeed = 17,
		Loadout = { "Shotgun", "Pistol" },
		Primaries = { "Shotgun", "SMG" }, -- wählbare Primärwaffen (erste = Standard)
		Gadget = { Type = "Frag", Name = "Splittergranate", Charges = 1, Damage = 90, Radius = 14, Fuse = 2 },
		Passive = { Type = "KillSpeed", Name = "Blutrausch", Description = "Nach einem Kill 2 s lang 20 % schneller." },
		Ability = {
			Type = "Dash",
			Name = "Sprint-Stoß",
			Description = "Blitzschneller Sprung in Laufrichtung.",
			Cooldown = 8,
			Duration = 0.25,
			Speed = 90,
		},
	},
	{
		Id = "Aegis",
		Name = "AEGIS",
		Price = 2000,
		Role = "Unterstützung",
		Description = "Hält das Team im Kampf – viel Feuerkraft und Heilung.",
		Color = Color3.fromRGB(110, 160, 196),
		Health = 110,
		WalkSpeed = 15,
		Loadout = { "LMG", "Revolver" },
		Primaries = { "LMG", "Rifle" }, -- wählbare Primärwaffen (erste = Standard)
		Gadget = { Type = "Sensor", Name = "Sensor-Mine", Charges = 1, Radius = 18, Duration = 30 },
		Passive = { Type = "Regen", Name = "Selbstheilung", Description = "Heilt langsam nach 6 s ohne Schaden." },
		Ability = {
			Type = "TeamHeal",
			Name = "Feldlazarett",
			Description = "Heilt dich und alle Teamkollegen im Umkreis von 25 Studs um 40.",
			Cooldown = 25,
			Duration = 1,
			Amount = 40,
			Radius = 25,
		},
	},
	{
		Id = "Trapper",
		Name = "TRAPPER",
		Role = "Kontrolle",
		Description = "Sperrt Wege ab und hält Gegner auf.",
		Color = Color3.fromRGB(156, 132, 92),
		Price = 2000,
		Health = 100,
		WalkSpeed = 16,
		Loadout = { "Rifle", "Pistol" },
		Primaries = { "Rifle", "SMG" }, -- wählbare Primärwaffen (erste = Standard)
		Gadget = { Type = "Smoke", Name = "Rauchgranate", Charges = 1, Radius = 14, Duration = 12, Fuse = 1.5 },
		Passive = { Type = "ExtraGadget", Name = "Fallensteller", Description = "+1 Gadget-Ladung pro Leben." },
		Ability = {
			Type = "Trap",
			Name = "Stacheldraht",
			Description = "12 Sekunden Stacheldraht vor dir: Gegner darin sind 50 % langsamer und nehmen Schaden.",
			Cooldown = 22,
			Duration = 12,
			Size = Vector3.new(12, 1, 8),
			DamagePerSecond = 6,
		},
	},
	{
		Id = "Volt",
		Name = "VOLT",
		Role = "Techniker",
		Description = "Baut einen Geschützturm, der Gegner selbstständig beschießt.",
		Color = Color3.fromRGB(204, 190, 86),
		Price = 2000,
		Health = 95,
		WalkSpeed = 16,
		Loadout = { "SMG", "Pistol" },
		Primaries = { "SMG", "Shotgun" }, -- wählbare Primärwaffen (erste = Standard)
		Gadget = { Type = "Sensor", Name = "Sensor-Mine", Charges = 1, Radius = 18, Duration = 30 },
		Passive = { Type = "Cooldown", Name = "Ingenieur", Description = "Fähigkeit lädt 20 % schneller." },
		Ability = {
			Type = "Turret",
			Name = "Geschützturm",
			Description = "15 Sekunden ein Turm, der den nächsten sichtbaren Gegner beschießt (Reichweite 60).",
			Cooldown = 28,
			Duration = 15,
			Range = 60,
			Damage = 8,
			FireDelay = 0.3,
		},
	},
}

-- Agent per Id holen, nil wenn unbekannt
-- Werte-Balken für Menüs (1 bis 10): schwächster Agent ~3, stärkster 10.
-- "Health" = Leben, "Speed" = Lauftempo, "Utility" = Fähigkeit (kurze Abklingzeit = stark)
local STAT_GETTERS = {
	Health = function(agent) return agent.Health end,
	Speed = function(agent) return agent.WalkSpeed end,
	Utility = function(agent) return -agent.Ability.Cooldown end,
}
function AgentConfig.StatValue(key, agent)
	local get = STAT_GETTERS[key]
	local low, high = math.huge, -math.huge
	for _, other in AgentConfig.Agents do
		local value = get(other)
		low, high = math.min(low, value), math.max(high, value)
	end
	if high <= low then
		return 7
	end
	return math.clamp(math.floor(3 + 7 * (get(agent) - low) / (high - low) + 0.5), 1, 10)
end

-- Kurzbeschreibung eines Gadgets aus seinen Werten (Menüs)
function AgentConfig.GadgetDescription(gadget)
	if gadget.Type == "Frag" then
		return string.format("Granate: %d Schaden im Umkreis von %d Studs.", gadget.Damage or 0, gadget.Radius or 0)
	elseif gadget.Type == "Flash" then
		return string.format("Blendet Gegner im Umkreis von %d Studs für %s s.", gadget.Radius or 0, tostring(gadget.Duration or 0))
	elseif gadget.Type == "Smoke" then
		return "Rauchwolke, die die Sicht versperrt."
	elseif gadget.Type == "Sensor" then
		return "Mine, die vorbeilaufende Gegner für dein Team markiert."
	end
	return "Gadget – mit " .. AgentConfig.GadgetKey.Name .. " einsetzen."
end

function AgentConfig.Get(id)
	for _, agent in AgentConfig.Agents do
		if agent.Id == id then
			return agent
		end
	end
	return nil
end

-- Level aus XP berechnen (1 bis MaxLevel)
function AgentConfig.LevelFromXP(xp)
	return math.min(AgentConfig.MaxLevel, math.floor((xp or 0) / AgentConfig.XPPerLevel) + 1)
end

-- Fortschritt im aktuellen Level (0 bis 1)
function AgentConfig.LevelProgress(xp)
	if AgentConfig.LevelFromXP(xp) >= AgentConfig.MaxLevel then
		return 1
	end
	return ((xp or 0) % AgentConfig.XPPerLevel) / AgentConfig.XPPerLevel
end

-- Waffen-Skin für ein Level (nil = Standard)
function AgentConfig.SkinForLevel(level)
	for _, skin in AgentConfig.Skins do
		if level >= skin.Level then
			return skin
		end
	end
	return nil
end

-- Hat der Spieler den Agenten freigeschaltet? (Spieler-Attribut "UnlockedAgents", JSON)
-- Agent der Woche: wechselt jeden Montag (0 Uhr UTC), für alle gleich (Serverzeit). Diese Woche gratis
-- spielbar und +50 % XP (AgentOfWeekXP), wenn man mit ihm spielt. Steht als Statue in der Hub-Mitte.
AgentConfig.AgentOfWeekXP = 1.5
local WEEK = 7 * 24 * 3600
local MONDAY_OFFSET = 4 * 24 * 3600 -- 1.1.1970 war ein Donnerstag
function AgentConfig.AgentOfWeek()
	local week = math.floor((workspace:GetServerTimeNow() + MONDAY_OFFSET) / WEEK)
	return AgentConfig.Agents[week % #AgentConfig.Agents + 1]
end

function AgentConfig.IsUnlocked(player, agentId)
	local agent = AgentConfig.Get(agentId)
	if not agent then
		return false
	end
	if not agent.Price or agent.Id == AgentConfig.AgentOfWeek().Id then
		return true -- kostenlos oder Agent der Woche
	end
	local raw = player:GetAttribute("UnlockedAgents")
	if type(raw) ~= "string" then
		return false
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	return ok and type(data) == "table" and data[agentId] == true
end

-- Waffen des Spielers für einen Agenten: gewählte Primärwaffe (Spieler-Attribut "Loadouts", JSON
-- { [AgentId] = Waffe }) + Sekundärwaffe
function AgentConfig.LoadoutFor(player, agentId)
	local agent = AgentConfig.Get(agentId) or AgentConfig.Agents[1]
	local primary = agent.Loadout[1]
	local raw = player and player:GetAttribute("Loadouts")
	if type(raw) == "string" then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		local chosen = ok and type(data) == "table" and data[agent.Id]
		if chosen and table.find(agent.Primaries or {}, chosen) then
			primary = chosen
		end
	end
	return { primary, agent.Loadout[2] }
end

-- Passive Eigenschaft des aktiven Agenten eines Charakters (oder nil)
function AgentConfig.PassiveOf(model, passiveType)
	local agent = model and AgentConfig.Get(model:GetAttribute("Agent"))
	local passive = agent and agent.Passive
	return passive ~= nil and passive.Type == passiveType
end

-- Spielerlevel inkl. Prestige (Prestige * 100 + Level, siehe LevelConfig), z.B. für Ranked
function AgentConfig.PlayerLevel(player)
	return require(script.Parent.LevelConfig).Get(player).Total
end

-- XP eines Spielers für einen Agenten (Spieler-Attribut "XP_<Id>")
function AgentConfig.GetXP(player, agentId)
	return player:GetAttribute("XP_" .. agentId) or 0
end

return AgentConfig

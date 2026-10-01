-- AgentConfig (ModuleScript)
-- Alle Agenten mit Werten, Waffen (Loadout) und Fähigkeit, dazu das Level-System.
-- Fähigkeits-Typen: "Boost" (schneller), "Wall" (Deckungswand), "Heal" (Selbstheilung),
-- "Reveal" (zeigt Gegner durch Wände)

local AgentConfig = {}

AgentConfig.AbilityKey = Enum.KeyCode.Q

-- ---------- Level-System ----------
AgentConfig.XPPerLevel = 500   -- XP pro Level
AgentConfig.MaxLevel = 20
AgentConfig.XPRewards = {
	Kill = 100,
	Headshot = 25,   -- zusätzlich zum Kill
	RoundWin = 150,  -- Drop: Runde gewonnen (ganzes Team)
	MatchWin = 400,  -- Drop: Match gewonnen (ganzes Team)
	FFAWin = 400,    -- Free-for-All: Runde gewonnen
}
-- Waffen-Skins als Belohnung (höchstes erreichtes Level zuerst)
AgentConfig.Skins = {
	{ Level = 10, Name = "Diamant", Color = Color3.fromRGB(90, 220, 255), Material = Enum.Material.Neon },
	{ Level = 5, Name = "Gold", Color = Color3.fromRGB(212, 175, 55), Material = Enum.Material.Metal },
}

-- ---------- Agenten ----------
AgentConfig.Agents = {
	{
		Id = "Viper",
		Name = "VIPER",
		Role = "Scout",
		Description = "Schnell und wendig, hält dafür weniger aus.",
		Color = Color3.fromRGB(80, 220, 140),
		Health = 90,
		WalkSpeed = 18,
		Loadout = { "SMG", "Pistol" },
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
		Color = Color3.fromRGB(90, 140, 255),
		Health = 125,
		WalkSpeed = 15,
		Loadout = { "Shotgun", "Revolver" },
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
		Color = Color3.fromRGB(255, 110, 110),
		Health = 100,
		WalkSpeed = 16,
		Loadout = { "Rifle", "Pistol" },
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
		Color = Color3.fromRGB(240, 200, 80),
		Health = 95,
		WalkSpeed = 16,
		Loadout = { "DMR", "Pistol" },
		Ability = {
			Type = "Reveal",
			Name = "Radar-Puls",
			Description = "Zeigt deinem Team 4 Sekunden lang alle Gegner in 120 Studs durch Wände.",
			Cooldown = 22,
			Duration = 4,
			Radius = 120,
		},
	},
}

-- Agent per Id holen, nil wenn unbekannt
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

-- XP eines Spielers für einen Agenten (Spieler-Attribut "XP_<Id>")
function AgentConfig.GetXP(player, agentId)
	return player:GetAttribute("XP_" .. agentId) or 0
end

return AgentConfig

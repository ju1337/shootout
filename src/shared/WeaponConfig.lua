-- WeaponConfig (ModuleScript)
-- Alle Waffenwerte an einer Stelle. Hier kannst du alles anpassen.
-- Welche Waffen ein Agent trägt, steht in AgentConfig (Loadout).
-- Pellets = Kugeln pro Schuss (Schrotflinte), Spread = Grund-Streuung in Grad (aus der Hüfte, im Stand)
-- Bloom = zusätzliche Streuung pro Schuss bei Dauerfeuer (höchstens MaxBloom), baut sich in Feuerpausen ab
-- Recoil = Kamera-Rückstoß nach oben pro Schuss in Grad, RecoilSide = zufällig zur Seite,
--   MaxRecoil = Obergrenze. Nach dem Loslassen wandert der Blick von selbst zurück.
-- Kick = wie stark die Waffe in der Hand zurückschlägt (nur Optik)
-- AimFov = Sichtfeld beim Zielen (Rechtsklick)
-- ShellReload = Patronen einzeln nachladen (Schrotflinte): Schießen bricht das Nachladen ab

local AttachmentConfig = require(script.Parent.AttachmentConfig)

local WeaponConfig = {}

-- Faktor für Kopfschüsse (2 = doppelter Schaden)
WeaponConfig.HeadshotMultiplier = 2

-- Streuung beim Zielen = Spread * dieser Faktor
WeaponConfig.AimSpreadFactor = 0.25

-- Streuung durch Bewegung (aus der Hüfte und beim Zielen):
-- bei MoveSpeedFull Studs/s kommt MoveSpread dazu (0.5 = +50 %), in der Luft AirSpread Grad
WeaponConfig.MoveSpread = 0.5
WeaponConfig.MoveSpeedFull = 16
WeaponConfig.AirSpread = 2.5

-- Bloom baut sich ab, wenn länger als BloomDelay * FireDelay nicht geschossen wurde (BloomRecovery Grad/s)
WeaponConfig.BloomDelay = 1.6
WeaponConfig.BloomRecovery = 6

-- Unendliche Reserve-Munition: überall (nachladen muss man trotzdem). Auf false stellen, dann gilt sie nur
-- in den Modi aus InfiniteAmmoModes (Schießstand).
WeaponConfig.InfiniteAmmoEverywhere = true
WeaponConfig.InfiniteAmmoModes = { Training = true }

-- Schuss-Sounds (Roblox-Audio-IDs). Bleibt ein Sound stumm, ist die ID nicht (mehr) öffentlich:
-- in Studio unter Toolbox → Audio einen freien Schuss-Sound suchen und dessen ID hier eintragen.
WeaponConfig.Sounds = {
	Rifle = "rbxassetid://92011177452282",
	SMG = "rbxassetid://92011177452282",
	LMG = "rbxassetid://92011177452282",
	DMR = "rbxassetid://3102797479",
	Shotgun = "rbxassetid://3102797479",
	Pistol = "rbxassetid://6240772711",
	Revolver = "rbxassetid://3102797479",
}

-- Geräusche beim Nachladen und Hantieren (in Roblox eingebaute Sounds, keine Asset-ID nötig).
-- { Sound, Lautstärke, Tonhöhe }
WeaponConfig.ActionSounds = {
	MagOut = { "rbxasset://sounds/clickfast.wav", 0.5, 0.75 },
	MagIn = { "rbxasset://sounds/clickfast.wav", 0.6, 1.0 },
	Bolt = { "rbxasset://sounds/switch.wav", 0.5, 0.85 },
	Slide = { "rbxasset://sounds/switch.wav", 0.45, 1.15 },
	Shell = { "rbxasset://sounds/clickfast.wav", 0.4, 1.3 },
	Pump = { "rbxasset://sounds/switch.wav", 0.55, 0.7 },
	Cylinder = { "rbxasset://sounds/clickfast.wav", 0.45, 1.5 },
	Empty = { "rbxasset://sounds/clickfast.wav", 0.5, 1.8 },
	Draw = { "rbxasset://sounds/switch.wav", 0.3, 1.3 },
}

WeaponConfig.Weapons = {
	Rifle = {
		DisplayName = "Sturmgewehr",
		Damage = 20,          -- Schaden pro Treffer (Körper)
		FireDelay = 0.1,      -- Sekunden zwischen zwei Schüssen
		Automatic = true,     -- true = Maustaste gedrückt halten feuert weiter
		MagazineSize = 30,
		ReserveAmmo = 90,
		ReloadTime = 2.0,
		Range = 500,
		Spread = 1.2,
		Bloom = 0.12,
		MaxBloom = 1.2,
		Recoil = 0.42,
		RecoilSide = 0.18,
		MaxRecoil = 5,
		Kick = 1,
		AimFov = 50,
	},
	SMG = {
		DisplayName = "MP",
		Damage = 14,
		FireDelay = 0.07,
		Automatic = true,
		MagazineSize = 35,
		ReserveAmmo = 140,
		ReloadTime = 1.8,
		Range = 250,
		Spread = 1.5,
		Bloom = 0.1,
		MaxBloom = 1.5,
		Recoil = 0.3,
		RecoilSide = 0.22,
		MaxRecoil = 4,
		Kick = 0.8,
		AimFov = 55,
	},
	Shotgun = {
		DisplayName = "Schrotflinte",
		Damage = 11,          -- pro Kugel
		Pellets = 8,
		Spread = 6,
		MoveSpread = 0,       -- Schrotkegel bleibt auch im Laufen gleich
		AirSpread = 0,
		FireDelay = 0.85,
		Automatic = false,
		MagazineSize = 6,
		ReserveAmmo = 24,
		ReloadTime = 2.5,     -- für ein leeres Magazin, Patronen einzeln (siehe ShellTiming)
		ShellReload = true,
		Range = 90,
		Recoil = 2.5,
		RecoilSide = 0.5,
		MaxRecoil = 6,
		Kick = 2.6,
		AimFov = 60,
	},
	DMR = {
		DisplayName = "Präzisionsgewehr",
		Damage = 45,
		FireDelay = 0.4,
		Automatic = false,
		MagazineSize = 10,
		ReserveAmmo = 30,
		ReloadTime = 2.3,
		Range = 900,
		Spread = 2.5,
		Bloom = 0.8,
		MaxBloom = 2.4,
		Recoil = 1.4,
		RecoilSide = 0.3,
		MaxRecoil = 5,
		Kick = 1.8,
		AimFov = 30,
	},
	LMG = {
		DisplayName = "LMG",
		Damage = 17,
		FireDelay = 0.09,
		Automatic = true,
		MagazineSize = 60,
		ReserveAmmo = 120,
		ReloadTime = 3.2,
		Range = 450,
		Spread = 2.2,
		Bloom = 0.08,
		MaxBloom = 1.6,
		Recoil = 0.36,
		RecoilSide = 0.25,
		MaxRecoil = 6,
		Kick = 1.1,
		AimFov = 55,
	},
	Pistol = {
		DisplayName = "Pistole",
		Damage = 25,
		FireDelay = 0.25,
		Automatic = false,
		MagazineSize = 12,
		ReserveAmmo = 48,
		ReloadTime = 1.3,
		Range = 300,
		Spread = 0.8,
		Bloom = 0.35,
		MaxBloom = 1.4,
		Recoil = 0.9,
		RecoilSide = 0.25,
		MaxRecoil = 4,
		Kick = 1.4,
		AimFov = 55,
	},
	Revolver = {
		DisplayName = "Revolver",
		Damage = 40,
		FireDelay = 0.55,
		Automatic = false,
		MagazineSize = 6,
		ReserveAmmo = 30,
		ReloadTime = 2.0,
		Range = 400,
		Spread = 1.0,
		Bloom = 0.7,
		MaxBloom = 2.0,
		Recoil = 2.2,
		RecoilSide = 0.4,
		MaxRecoil = 6,
		Kick = 2.2,
		AimFov = 50,
	},
}

-- Nahkampf-Messer (Taste V): bei Gegnern am Boden sofortiger Finish
WeaponConfig.Melee = {
	DisplayName = "Messer",
	Damage = 55,
	Range = 6,       -- Reichweite in Studs
	Radius = 1.5,    -- Breite des Stichs
	Cooldown = 0.8,
}

-- Waffe per Name holen (nil, wenn es sie nicht gibt)
function WeaponConfig.Get(name)
	return WeaponConfig.Weapons[name]
end

-- Streuung in Grad für den nächsten Schuss. Client (Fadenkreuz) und Server (Schuss) nutzen dieselbe Formel.
-- bloom = aufgebauter Bloom, speed = Laufgeschwindigkeit (Studs/s), airborne = in der Luft,
-- aiming = zielt (Rechtsklick), effects = Wirkung der Aufsätze (AttachmentConfig.Effects) oder nil
function WeaponConfig.SpreadFor(cfg, bloom, speed, airborne, aiming, effects)
	effects = type(effects) == "table" and effects or nil
	local spread = (cfg.Spread or 0) + (bloom or 0)
	local move = math.clamp((speed or 0) / WeaponConfig.MoveSpeedFull, 0, 1.5)
	spread *= 1 + move * (cfg.MoveSpread or WeaponConfig.MoveSpread) * (effects and effects.MoveSpread or 1)
	if airborne then
		spread += cfg.AirSpread or WeaponConfig.AirSpread
	end
	if aiming then
		spread *= WeaponConfig.AimSpreadFactor
	elseif effects then
		spread *= effects.HipSpread
	end
	if effects then
		spread *= effects.Spread
	end
	return spread
end

-- Waffenwerte mit der Reichweite der Aufsätze (für Raycasts); alles andere bleibt wie in cfg
function WeaponConfig.WithAttachments(cfg, effects)
	if not effects or effects.Range == 1 then
		return cfg
	end
	return setmetatable({ Range = cfg.Range * effects.Range }, { __index = cfg })
end

-- Bloom nach einer Feuerpause von sinceLast Sekunden (bloom = Wert direkt nach dem letzten Schuss)
function WeaponConfig.DecayBloom(cfg, bloom, sinceLast)
	local idle = sinceLast - cfg.FireDelay * WeaponConfig.BloomDelay
	if idle <= 0 then
		return bloom
	end
	return math.max(0, bloom - idle * WeaponConfig.BloomRecovery)
end

-- Ein Schuss: liefert (Bloom für diesen Schuss, Bloom direkt danach)
function WeaponConfig.StepBloom(cfg, bloom, sinceLast)
	local current = WeaponConfig.DecayBloom(cfg, bloom, sinceLast)
	return current, math.min(cfg.MaxBloom or 0, current + (cfg.Bloom or 0))
end

-- Nachladezeit mit Aufsatz (z.B. Schnellmagazin) und Passiv "Schnelle Hände" (VIPER)
function WeaponConfig.ReloadDuration(player, character, weaponName)
	local cfg = WeaponConfig.Get(weaponName)
	local AgentConfig = require(script.Parent.AgentConfig)
	return cfg.ReloadTime * AttachmentConfig.Effects(player, weaponName).Reload
		* (AgentConfig.PassiveOf(character, "Reload") and 0.85 or 1)
end

-- Patronenweises Nachladen (Schrotflinte): Zeit zum Ansetzen, pro Patrone und zum Durchladen am Ende.
-- duration = Nachladezeit für ein ganz leeres Magazin (Grundgröße).
function WeaponConfig.ShellTiming(cfg, duration)
	local start = duration * 0.14
	local finish = duration * 0.14
	return start, (duration - start - finish) / cfg.MagazineSize, finish
end

-- Unendliche Reserve-Munition im aktuellen Modus? (Schießstand)
function WeaponConfig.HasInfiniteAmmo(player)
	return WeaponConfig.InfiniteAmmoEverywhere or WeaponConfig.InfiniteAmmoModes[player:GetAttribute("Mode")] == true
end

return WeaponConfig

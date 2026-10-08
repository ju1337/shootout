-- WeaponConfig (ModuleScript)
-- Alle Waffenwerte an einer Stelle. Hier kannst du alles anpassen.
-- Welche Waffen ein Agent trägt, steht in AgentConfig (Loadout).
-- Pellets = Kugeln pro Schuss (Schrotflinte), Spread = Grund-Streuung in Grad (aus der Hüfte, im Stand)
-- FalloffStart / MinDamageFactor (optional) = ab welcher Entfernung der Schaden sinkt und wie weit (siehe FalloffFactor)
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

-- Schuss-Sounds: echte Aufnahmen aus der Roblox-Soundbibliothek (Pro Sound Effects, in jedem Spiel frei nutzbar).
-- SoundSets: je Klang mehrere Aufnahmen (werden zufällig abgewechselt). Gain gleicht die Aufnahmen aneinander an,
-- Region = { Start, Ende } spielt nur diesen Teil der Aufnahme (Sekunden; ohne Region die ganze).
-- Rifle M4A1, SMG 9mm Beretta (trocken, kurz), LMG Galil .223 (tiefer gestimmt), DMR Barrett M82, Shotgun Remington 870
-- und Savage, Pistol 9mm Beretta, Revolver S&W .357 Magnum; SupPistol schallgedämpfte 9mm / H&K SOCOM .45,
-- SupRifle Schalldämpfer für Gewehre.
WeaponConfig.SoundSets = {
	Rifle = { { Id = "rbxassetid://9113198012", Gain = 1.10, Region = { 0, 0.9 } },
		{ Id = "rbxassetid://9113185301", Gain = 0.86, Region = { 0, 0.9 } },
		{ Id = "rbxassetid://9113185655", Gain = 0.91, Region = { 0, 0.9 } },
		{ Id = "rbxassetid://9113185628", Gain = 0.89, Region = { 0, 0.9 } } },
	SMG = { { Id = "rbxassetid://9114694336", Gain = 0.92, Region = { 0, 0.5 } },
		{ Id = "rbxassetid://9114694435", Gain = 0.85, Region = { 0, 0.5 } },
		{ Id = "rbxassetid://9114694481", Gain = 0.94, Region = { 0, 0.5 } },
		{ Id = "rbxassetid://9114694502", Gain = 0.88, Region = { 0, 0.5 } },
		{ Id = "rbxassetid://9114695068", Gain = 0.84, Region = { 0, 0.5 } } },
	LMG = { { Id = "rbxassetid://9114550557", Gain = 0.92, Region = { 0, 0.9 } },
		{ Id = "rbxassetid://9114550686", Gain = 1.01, Region = { 0, 0.9 } },
		{ Id = "rbxassetid://9114550847", Gain = 1.01, Region = { 0, 0.9 } },
		{ Id = "rbxassetid://9114551018", Gain = 1.05, Region = { 0, 0.9 } } },
	DMR = { { Id = "rbxassetid://9118173999", Gain = 1.74 },
		{ Id = "rbxassetid://9118173739", Gain = 1.82, Region = { 0, 1.05 } },
		{ Id = "rbxassetid://9118173988", Gain = 1.95, Region = { 0, 1.05 } } },
	Shotgun = { { Id = "rbxassetid://9114724281", Gain = 1.07 },
		{ Id = "rbxassetid://9114708745", Gain = 0.86 },
		{ Id = "rbxassetid://9112912844", Gain = 2.09, Region = { 0, 1.2 } } },
	Pistol = { { Id = "rbxassetid://9114717487", Gain = 1.11 },
		{ Id = "rbxassetid://9114713313", Gain = 1.86 },
		{ Id = "rbxassetid://9114713446", Gain = 2.07 },
		{ Id = "rbxassetid://9114717607", Gain = 0.98 } },
	Revolver = { { Id = "rbxassetid://9119296692", Gain = 1.72 },
		{ Id = "rbxassetid://9119296693", Gain = 1.45, Region = { 0, 0.58 } },
		{ Id = "rbxassetid://9119296682", Gain = 1.58, Region = { 0, 0.95 } },
		{ Id = "rbxassetid://9119296944", Gain = 1.57, Region = { 0, 1.85 } } },
	SupPistol = { { Id = "rbxassetid://9117399808", Gain = 2.88, Region = { 0, 0.42 } },
		{ Id = "rbxassetid://9117398178", Gain = 2.60, Region = { 0, 0.32 } },
		{ Id = "rbxassetid://9119134538", Gain = 0.99, Region = { 0, 0.32 } } },
	SupRifle = { { Id = "rbxassetid://9119136817", Gain = 0.90, Region = { 0, 0.29 } },
		{ Id = "rbxassetid://9119136875", Gain = 0.90, Region = { 0, 0.29 } },
		{ Id = "rbxassetid://9119137181", Gain = 0.94, Region = { 0, 0.25 } } },
}

-- Klang je Waffe: Set (Schuss), Volume, Pitch (Tonhöhe); mit Schalldämpfer Suppressed (Set) und SuppressedPitch
WeaponConfig.Sounds = {
	Rifle = { Set = "Rifle", Volume = 1, Pitch = 1, Suppressed = "SupRifle", SuppressedPitch = 1 },
	SMG = { Set = "SMG", Volume = 0.85, Pitch = 1.06, Suppressed = "SupPistol", SuppressedPitch = 1.05 },
	LMG = { Set = "LMG", Volume = 1.05, Pitch = 0.9, Suppressed = "SupRifle", SuppressedPitch = 0.88 },
	DMR = { Set = "DMR", Volume = 1, Pitch = 1.08, Suppressed = "SupRifle", SuppressedPitch = 0.92 },
	Shotgun = { Set = "Shotgun", Volume = 1.1, Pitch = 1, Suppressed = "SupRifle", SuppressedPitch = 0.75 },
	Pistol = { Set = "Pistol", Volume = 0.85, Pitch = 1, Suppressed = "SupPistol", SuppressedPitch = 1 },
	Revolver = { Set = "Revolver", Volume = 1, Pitch = 0.97, Suppressed = "SupPistol", SuppressedPitch = 0.85 },
}
WeaponConfig.SuppressedVolume = 0.55 -- Schalldämpfer: so viel leiser (und nur in der Nähe zu hören)

-- Geräusche beim Nachladen und Hantieren (ebenfalls Pro Sound Effects): Id, Gain, Region wie oben, Volume.
-- Die Animationen nennen den Namen (MagOut, Pump …); ActionSoundsByWeapon ersetzt ihn je Waffe.
WeaponConfig.ActionSounds = {
	MagOut = { Id = "rbxassetid://9116347612", Gain = 0.44, Region = { 0.2, 0.6 }, Volume = 0.6 },
	MagIn = { Id = "rbxassetid://9116347432", Gain = 0.58, Region = { 0.6, 1 }, Volume = 0.7 },
	PistolMagOut = { Id = "rbxassetid://9113104176", Gain = 1.15, Region = { 0, 0.27 }, Volume = 0.6 },
	PistolMagIn = { Id = "rbxassetid://9113104176", Gain = 0.45, Region = { 0.27, 0.7 }, Volume = 0.6 },
	Bolt = { Id = "rbxassetid://9116345318", Gain = 2.48, Region = { 0.9, 1.4 }, Volume = 0.6 },
	Slide = { Id = "rbxassetid://9113104509", Gain = 1.78, Region = { 0.75, 1.15 }, Volume = 0.6 },
	Shell = { Id = "rbxassetid://9117396156", Gain = 1.26, Region = { 0, 0.35 }, Volume = 0.5 },
	Pump = { Id = "rbxassetid://9112910934", Gain = 1.22, Region = { 0, 0.48 }, Volume = 0.7 },
	Cylinder = { Id = "rbxassetid://9114764731", Gain = 3.24, Region = { 0.15, 0.5 }, Volume = 0.5 },
	Empty = { Id = "rbxassetid://9117402073", Gain = 4.00, Region = { 1.83, 2.2 }, Volume = 0.5 },
	Draw = { Id = "rbxassetid://9114701864", Gain = 0.44, Region = { 0, 0.6 }, Volume = 0.4 },
	RifleDraw = { Id = "rbxassetid://9116362330", Gain = 4.00, Region = { 0.25, 0.75 }, Volume = 0.4 },
}
WeaponConfig.ActionSoundsByWeapon = {
	Pistol = { MagOut = "PistolMagOut", MagIn = "PistolMagIn" },
	Revolver = { MagOut = "PistolMagOut", MagIn = "PistolMagIn" },
	Rifle = { Draw = "RifleDraw" },
	SMG = { Draw = "RifleDraw" },
	LMG = { Draw = "RifleDraw" },
	DMR = { Draw = "RifleDraw" },
	Shotgun = { Draw = "RifleDraw" },
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
		FalloffStart = 22,     -- Schrotflinte: ab hier deutlich weniger Schaden
		MinDamageFactor = 0.35,
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

-- ---------- Treffer: gleiche Streuung auf Client und Server, Schaden nach Entfernung und Körperteil ----------

-- Seed eines Schusses: Spieler + laufende Schuss-Nummer. Client und Server würfeln damit dieselben Richtungen,
-- so landet die Kugel auf dem Server dort, wo man die Leuchtspur sieht.
function WeaponConfig.ShotSeed(userId, shotId)
	return (math.abs(userId) % 1000003) * 7919 + (math.floor(shotId) % 1000000)
end

-- Richtungen aller Kugeln eines Schusses (Schrotflinte: mehrere) im Streukegel (Grad)
function WeaponConfig.PelletDirections(direction, degrees, pellets, seed)
	local random = Random.new(seed)
	local list = {}
	for i = 1, pellets or 1 do
		if not degrees or degrees <= 0 then
			list[i] = direction.Unit
		else
			local angle = math.rad(degrees) * math.sqrt(random:NextNumber())
			local spin = random:NextNumber() * math.pi * 2
			list[i] = (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, spin) * CFrame.Angles(angle, 0, 0)).LookVector
		end
	end
	return list
end

-- Schaden fällt mit der Entfernung ab: volle Wirkung bis FalloffStart (Standard 45 % der Reichweite),
-- dann linear bis MinDamageFactor (Standard 60 %) am Ende der Reichweite
function WeaponConfig.FalloffFactor(cfg, distance)
	local start = cfg.FalloffStart or cfg.Range * 0.45
	local minFactor = cfg.MinDamageFactor or 0.6
	if distance <= start then
		return 1
	end
	local t = math.clamp((distance - start) / math.max(1, cfg.Range - start), 0, 1)
	return 1 + (minFactor - 1) * t
end

-- Körperteil: Kopf mehr Schaden, Arme und Beine etwas weniger
WeaponConfig.LimbMultiplier = 0.85
function WeaponConfig.PartMultiplier(partName)
	if partName == "Head" then
		return WeaponConfig.HeadshotMultiplier
	end
	if string.find(partName, "Arm") or string.find(partName, "Hand") or string.find(partName, "Leg")
		or string.find(partName, "Foot") then
		return WeaponConfig.LimbMultiplier
	end
	return 1
end

-- Waffenwerte mit der Reichweite der Aufsätze (für Raycasts); alles andere bleibt wie in cfg
function WeaponConfig.WithAttachments(cfg, effects)
	if not effects or (effects.Range == 1 and effects.Falloff == 1) then
		return cfg
	end
	return setmetatable({ Range = cfg.Range * effects.Range,
		FalloffStart = (cfg.FalloffStart or cfg.Range * 0.45) * (effects.Falloff or 1) * effects.Range }, { __index = cfg })
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

-- Unendliche Reserve-Munition im aktuellen Modus? (Schießstand). Nie in der offenen Welt (Extinction): dort kommt
-- die Munition aus dem Inventar.
function WeaponConfig.HasInfiniteAmmo(player)
	local mode = player:GetAttribute("Mode")
	local Modes = require(script.Parent.Modes)
	if Modes.IsSurvival(mode) then
		return false
	end
	return WeaponConfig.InfiniteAmmoEverywhere or WeaponConfig.InfiniteAmmoModes[mode] == true
end

return WeaponConfig

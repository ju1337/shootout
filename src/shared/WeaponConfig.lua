-- WeaponConfig (ModuleScript)
-- Alle Waffenwerte an einer Stelle. Hier kannst du alles anpassen.
-- Welche Waffen ein Agent trägt, steht in AgentConfig (Loadout).
-- Pellets = Kugeln pro Schuss (Schrotflinte), Spread = Streuung in Grad (aus der Hüfte)
-- Recoil = Kamera-Rückstoß pro Schuss in Grad (bewusst klein, stellt sich von selbst zurück)
-- AimFov = Sichtfeld beim Zielen (Rechtsklick)

local WeaponConfig = {}

-- Faktor für Kopfschüsse (2 = doppelter Schaden)
WeaponConfig.HeadshotMultiplier = 2

-- Streuung beim Zielen = Spread * dieser Faktor
WeaponConfig.AimSpreadFactor = 0.25

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
		Recoil = 0.35,
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
		Recoil = 0.25,
		AimFov = 55,
	},
	Shotgun = {
		DisplayName = "Schrotflinte",
		Damage = 11,          -- pro Kugel
		Pellets = 8,
		Spread = 6,
		FireDelay = 0.85,
		Automatic = false,
		MagazineSize = 6,
		ReserveAmmo = 24,
		ReloadTime = 2.5,
		Range = 90,
		Recoil = 1.5,
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
		Recoil = 0.9,
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
		Recoil = 0.3,
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
		Recoil = 0.5,
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
		Recoil = 1.2,
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

return WeaponConfig

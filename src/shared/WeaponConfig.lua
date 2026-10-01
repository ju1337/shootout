-- WeaponConfig (ModuleScript)
-- Alle Waffenwerte an einer Stelle. Hier kannst du alles anpassen.
-- Welche Waffen ein Agent trägt, steht in AgentConfig (Loadout).
-- Pellets = Kugeln pro Schuss (Schrotflinte), Spread = Streuung in Grad

local WeaponConfig = {}

-- Faktor für Kopfschüsse (2 = doppelter Schaden)
WeaponConfig.HeadshotMultiplier = 2

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
	},
}

-- Waffe per Name holen (nil, wenn es sie nicht gibt)
function WeaponConfig.Get(name)
	return WeaponConfig.Weapons[name]
end

return WeaponConfig

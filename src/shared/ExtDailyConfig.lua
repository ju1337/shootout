-- ExtDailyConfig (ModuleScript)
-- Tägliche Kiste der offenen Welt: Beim ersten Betreten von EXTINCTION an einem Tag (UTC) liegt eine Kiste im Lager.
-- Wer am Vortag eine bekommen hat, rückt einen Tag weiter (1 bis 7, danach wieder 1); wer einen Tag auslässt, fängt bei 1
-- an. Tag 7 ist der große Preis: eine seltene Waffe mit sehr seltenem Aufsatz.
-- Days[n] = { Items = { { Id, Anzahl } }, Pick = { Liste, aus der ein Item zufällig kommt }, Coins }
-- Profil: ExtDaily = { Date = "YYYY-MM-DD", Day = n }; Spieler-Attribut "ExtDaily" (JSON, gleiche Form).

local ExtDailyConfig = {}

ExtDailyConfig.Enabled = true

ExtDailyConfig.Days = {
	{ Items = { { "Bandage", 3 }, { "Ammo_9mm", 60 } } },
	{ Items = { { "Vest", 1 }, { "Medkit", 1 } } },
	{ Items = { { "Ammo_Rifle", 60 } }, Pick = { "Att_Compensator", "Att_ShortBarrel", "Att_VerticalGrip", "Att_Laser", "Att_FastMag" } },
	{ Items = { { "AntiZombie", 2 }, { "Medkit", 2 } } },
	{ Items = { { "HeavyVest", 1 } }, Pick = { "Att_MuzzleBrake", "Att_LongBarrel", "Att_HeavyBarrel", "Att_AngledGrip", "Att_ExtendedMag" } },
	{ Items = { { "Adrenaline", 2 }, { "Ammo_Rifle", 120 } } },
	{ Items = { { "Ammo_Rifle", 120 } }, Pick = { "LMG", "DMR" }, Pick2 = { "Att_Suppressor", "Att_DrumMag" }, Coins = 400 },
}

-- Datum (UTC) zu einem Zeitpunkt
function ExtDailyConfig.Date(t)
	return os.date("!%Y-%m-%d", t or os.time())
end

-- Nächster Tag der Serie aus dem gespeicherten Stand (nil = heute schon bekommen)
function ExtDailyConfig.NextDay(data, now)
	now = now or os.time()
	local today = ExtDailyConfig.Date(now)
	if type(data) == "table" and data.Date == today then
		return nil
	end
	local yesterday = ExtDailyConfig.Date(now - 86400)
	local last = type(data) == "table" and tonumber(data.Day) or 0
	if type(data) == "table" and data.Date == yesterday and last >= 1 then
		return last % #ExtDailyConfig.Days + 1
	end
	return 1
end

return ExtDailyConfig

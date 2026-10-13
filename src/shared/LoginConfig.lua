-- LoginConfig (ModuleScript)
-- Login-Kalender und Glücksrad (Server: ShopService, Client: SideMenu-Fenster LOGIN-BONUS und GLÜCKSRAD).
--   Login-Kalender: jeden Tag (UTC) einmal abholen. Wer am Vortag abgeholt hat, rückt einen Tag weiter
--   (1 bis 7, danach wieder Tag 1), wer einen Tag auslässt, fängt bei Tag 1 an. Tag 7 ist der große Preis.
--   Glücksrad: einmal pro Tag gratis drehen, Extra-Drehs gibt es an Tag 7 des Kalenders (und später im Shop).
-- Spieler-Attribute (JSON): LoginData { Day = zuletzt abgeholter Tag, Date = "YYYY-MM-DD" },
--   WheelData { Date = Tag des letzten Gratis-Drehs, Spins = Extra-Drehs }; XPBoostUntil (Serverzeit)

local LoginConfig = {}

-- Belohnung pro Kalendertag: Coins, BoostMinutes (Doppel-XP), Spins (Extra-Drehs), Item (Skin; handelbare Skins
-- mit RAP-Wert gibt es auch als weiteres Stück, gebundene nur einmal)
LoginConfig.Days = {
	{ Coins = 100 },
	{ Coins = 150 },
	{ Coins = 200, BoostMinutes = 30 },
	{ Coins = 300 },
	{ Coins = 400, Spins = 1 },
	{ Coins = 500 },
	{ Coins = 1000, Spins = 1, Item = "W_Kalender" },
}

-- Felder des Glücksrads (im Uhrzeigersinn ab oben). Weight = relative Chance (Summe 100 = Prozent).
-- Item = Skin; mit Fallback gibt es die Coins nur, wenn der Skin nicht vergeben werden kann (gebunden, schon da).
-- Hohe und niedrige Gewinne wechseln sich ab, das letzte Feld ist der JACKPOT (Server, HubWheel).
LoginConfig.Wheel = {
	{ Text = "50", Coins = 50, Weight = 24, Color = Color3.fromRGB(36, 104, 196) },
	{ Text = "1000", Coins = 1000, Weight = 6, Color = Color3.fromRGB(196, 34, 64) },
	{ Text = "100", Coins = 100, Weight = 22, Color = Color3.fromRGB(32, 138, 74) },
	{ Text = "STERNSCHNUPPE", Item = "W_Sternschnuppe", Coins = 1500, Fallback = true, Weight = 3,
		Color = Color3.fromRGB(46, 40, 150) },
	{ Text = "250", Coins = 250, Weight = 16, Color = Color3.fromRGB(214, 130, 20) },
	{ Text = "GLÜCKSKLEE", Item = "W_Gluecksklee", Coins = 750, Fallback = true, Weight = 5,
		Color = Color3.fromRGB(20, 160, 110) },
	{ Text = "2× XP", BoostMinutes = 30, Weight = 10, Color = Color3.fromRGB(118, 56, 196) },
	{ Text = "FORTUNA", Item = "W_Fortuna", Coins = 2500, Fallback = true, Weight = 2,
		Color = Color3.fromRGB(34, 30, 26), TextColor = Color3.fromRGB(255, 206, 90) },
	{ Text = "500", Coins = 500, Weight = 10, Color = Color3.fromRGB(214, 74, 30) },
	{ Text = "JACKPOT", Coins = 2500, Weight = 2, Color = Color3.fromRGB(240, 176, 20) },
}

-- So lange (Sekunden) ist das Rad nach einem Dreh besetzt: Anlauf, Drehen, Gewinn-Show (HubWheel)
LoginConfig.WheelBusy = 9

-- Chance je Feld (0..1, gleiche Reihenfolge wie Wheel, Summe 1). Muss sichtbar sein, weil man Drehs für Robux kauft.
function LoginConfig.WheelOdds()
	local total = 0
	for _, field in LoginConfig.Wheel do
		total += field.Weight
	end
	local odds = {}
	for index, field in LoginConfig.Wheel do
		odds[index] = total > 0 and field.Weight / total or 0
	end
	return odds
end

-- Heutiges und gestriges Datum (UTC) zur Serverzeit now
function LoginConfig.Date(now)
	return os.date("!%Y-%m-%d", math.floor(now))
end

function LoginConfig.Yesterday(now)
	return os.date("!%Y-%m-%d", math.floor(now) - 86400)
end

-- Welcher Kalendertag ist heute dran? (bei Lücke wieder Tag 1)
function LoginConfig.NextDay(data, now)
	data = data or {}
	if data.Date == LoginConfig.Yesterday(now) then
		return (data.Day or 0) % #LoginConfig.Days + 1
	end
	return 1
end

-- Kann heute (noch) abgeholt werden?
function LoginConfig.CanClaim(data, now)
	return (data or {}).Date ~= LoginConfig.Date(now)
end

return LoginConfig

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

-- Felder des Glücksrads (im Kreis, gegen den Uhrzeigersinn ab oben). Weight = relative Chance.
LoginConfig.Wheel = {
	{ Text = "50", Coins = 50, Weight = 26, Color = Color3.fromRGB(96, 164, 214) },
	{ Text = "100", Coins = 100, Weight = 24, Color = Color3.fromRGB(112, 178, 112) },
	{ Text = "250", Coins = 250, Weight = 17, Color = Color3.fromRGB(212, 170, 80) },
	{ Text = "2× XP", BoostMinutes = 30, Weight = 10, Color = Color3.fromRGB(150, 120, 210) },
	{ Text = "500", Coins = 500, Weight = 10, Color = Color3.fromRGB(206, 110, 80) },
	{ Text = "SKIN", Item = "W_Gluecksklee", Coins = 750, Weight = 4, Color = Color3.fromRGB(80, 200, 140) },
	{ Text = "1000", Coins = 1000, Weight = 7, Color = Color3.fromRGB(230, 90, 120) },
	{ Text = "JACKPOT", Coins = 2500, Weight = 2, Color = Color3.fromRGB(255, 200, 60) },
}

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

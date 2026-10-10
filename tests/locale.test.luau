-- Sprache (Locale): Anzeige standardmäßig Englisch (US) – jeder Text in TextLabel/TextButton (und PlaceholderText) wird
-- beim Setzen in LocaleStrings nachgeschlagen und ersetzt, genau oder per Muster mit {1}, {2}; veränderliche Teile
-- werden selbst noch einmal nachgeschlagen. Deutsch nur bei Roblox-Sprache "de-…" oder Option Language = "de";
-- die Option wirkt sofort (Refresh). Eingetippter Text in TextBoxen bleibt unangetastet, Zähler ohne Buchstaben auch.
-- Dazu: jedes Muster in LocaleStrings hat in der Übersetzung dieselben Platzhalter.
--!signals immediate deferred
local failures = 0
local function flush()
	SIM.Advance(0.05)
end
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

SIM.IsServer = false
local bob = SIM.AddPlayer("Bob", 1001)
rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
bob.LocaleId = "en-us"

local Locale = require("Locale")
local LocaleStrings = require("LocaleStrings")
local PlayerSettings = require("PlayerSettings")

-- ---------- Wörterbuch prüfen ----------
local count = 0
for source, target in LocaleStrings do
	count += 1
	check(type(source) == "string" and type(target) == "string" and #source > 0 and #target > 0,
		"LocaleStrings: Eintrag ungültig: " .. tostring(source))
	local placeholders = {}
	for n in string.gmatch(source, "{(%d)}") do
		placeholders[n] = true
	end
	for n in string.gmatch(target, "{(%d)}") do
		check(placeholders[n], "LocaleStrings: Platzhalter {" .. n .. "} fehlt im Original: " .. source)
	end
	for n in placeholders do
		check(string.find(target, "{" .. n .. "}", 1, true) ~= nil,
			"LocaleStrings: Platzhalter {" .. n .. "} fehlt in der Übersetzung: " .. source)
	end
end
check(count > 100, "LocaleStrings ist fast leer (" .. count .. " Einträge)")
check(LocaleStrings["SPIELEN"] == "PLAY", "LocaleStrings: SPIELEN fehlt")

-- ---------- Übersetzen ----------
-- Objekt, das schon vor Init da ist, bekommt beim Init die Übersetzung
local screen = Instance.new("ScreenGui", playerGui)
local early = Instance.new("TextButton", screen)
early.Text = "SPIELEN"
flush()
check(early.Text == "SPIELEN", "ohne Init bleibt Deutsch")
Locale.Init(PlayerSettings)
flush()
check(early.Text == "PLAY", "vorhandener Knopf nach Init übersetzt: " .. early.Text)
check(Locale.Language() == "en", "Standard ist Englisch (" .. tostring(Locale.Language()) .. ")")
check(Locale.Translate("SPIELEN") == "PLAY", "genauer Text übersetzt")
check(Locale.Translate("30 / 90") == "30 / 90", "Zahlen bleiben")
check(Locale.Translate("Kein Eintrag dafür xyz") == "Kein Eintrag dafür xyz", "ohne Eintrag unverändert")
check(Locale.Translate("") == "", "leerer Text bleibt leer")
-- Listen und verschachtelte Item-Namen (Beute-Hinweis, Kauf-Meldung, Kit-Items)
local function expect(source, wanted, label)
	local got = Locale.Translate(source)
	check(got == wanted, label .. ": " .. got)
end
expect("Zombie · Verband ×2, 9mm-Munition ×12", "Zombie · Bandage ×2, 9mm Ammo ×12", "Beute-Liste")
expect("Gekauft: 30× 9mm-Munition für 30 Münzen", "Purchased: 30× 9mm Ammo for 30 Coins", "Kauf mit Anzahl")
expect("Fahrrad (Kit) eingepackt.", "Bicycle (Kit) packed up.", "Kit-Item in einer Meldung")
expect("+ Verband ×2, Fahrrad", "+ Bandage ×2, Bicycle", "Beute-Meldung")
expect("Volles Leben  ·  +", "Volles Leben  ·  +", "Bruchstück ohne Eintrag: nicht halb übersetzen")
expect("R  NACHLADEN  ·  M  KARTE", "R  RELOAD  ·  M  MAP", "gekürzte Tasten-Zeile: Wörter mit Eintrag sind keine Tasten")
expect("Im Lager: 120× Gewehrmunition, 400 Münzen", "In your stash: 120× Rifle Ammo, 400 coins", "Münzen als Listen-Stück")
expect("W / S  VOR / ZURÜCK  ·  A / D  DREHEN  ·  LEERTASTE  STEIGEN  ·  SHIFT  SINKEN  ·  F  AUSSTEIGEN  ·  G  EINPACKEN (GELANDET)",
	"W / S  FORWARD / BACK  ·  A / D  TURN  ·  SPACE  CLIMB  ·  SHIFT  DESCEND  ·  F  GET OUT  ·  G  STORE (LANDED)", "Hubschrauber-Tasten")
expect("L-STICK  FLIEGEN  ·  R2  STEIGEN  ·  L2  SINKEN  ·  ✕  AUSSTEIGEN  ·  △ HALTEN  EINPACKEN (GELANDET)",
	"L-STICK  FLY  ·  R2  CLIMB  ·  L2  DESCEND  ·  ✕  GET OUT  ·  HOLD △  STORE (LANDED)", "Hubschrauber-Tasten (Gamepad)")
expect("2× Quatschding, Fahrrad", "2× Quatschding, Fahrrad", "unbekanntes Wort in einem Mengen-Stück: Liste nicht halb übersetzen")
expect("1.  ADLER  ·  3 VERKÄUFE", "1.  ADLER  ·  3 VERKÄUFE", "Liste mit Spielername (Adler ist auf dem Server)")
expect("LMB  SCHIESSEN  ·  □  NACHLADEN / INTERAGIEREN  ·  △ HALTEN  FAHRZEUG EINPACKEN",
	"LMB  FIRE  ·  □  RELOAD / INTERACT  ·  HOLD △  STORE VEHICLE", "Tasten-Zeile nach benutzten Tasten")
check(Locale.Translate("Adler") == "Eagle", "Wort ohne gleichnamigen Spieler übersetzt")
SIM.AddPlayer("Adler", 1003)
check(Locale.Translate("Adler") == "Adler", "Spielername bleibt, auch wenn er wie ein Wort heißt")
expect("1.  ADLER  ·  ZOMBIE", "1.  ADLER  ·  ZOMBIE", "Spielername als Listen-Stück mit eigenem Eintrag")
-- großgeschriebene Fassung (Anzeigen schreiben mit UITheme.Upper groß, bevor der Text gesetzt wird)
check(Locale.Translate("TÖTE 19 ZOMBIES") == "KILL 19 ZOMBIES", "Muster in Großbuchstaben: " .. Locale.Translate("TÖTE 19 ZOMBIES"))
check(Locale.Translate("TÖTE 14 ZOMBIES IN DER ROTEN ZONE") == "KILL 14 ZOMBIES IN THE RED ZONE",
	"längeres Muster in Großbuchstaben: " .. Locale.Translate("TÖTE 14 ZOMBIES IN DER ROTEN ZONE"))
check(Locale.Translate("TÖTE 3 BROCKEN") == "KILL 3 BRUTES", "genauer Text in Großbuchstaben")
-- Muster, dessen erstes Wort einen Platzhalter enthält ("+{1} Leben"): der Text beginnt dann mit "+25", nicht mit "+"
check(Locale.Translate("+25 Leben · 2,5 s") == "+25 health · 2,5 s", "Muster mit Platzhalter im ersten Wort: " .. Locale.Translate("+25 Leben · 2,5 s"))

-- Muster mit Platzhaltern und verschachteltem Nachschlagen (echte Einträge aus LocaleStrings)
local sample = nil
for source, target in LocaleStrings do
	if string.find(source, "{1}") and not string.find(source, "{2}") and string.find(source, "^%S+ ") then
		sample = { source, target }
		break
	end
end
check(sample ~= nil, "mindestens ein Muster mit {1} im Wörterbuch")
if sample then
	local filled = string.gsub(sample[1], "{1}", "Verband")
	local expected = string.gsub(sample[2], "{1}", LocaleStrings["Verband"] or "Verband")
	check(Locale.Translate(filled) == expected, "Muster übersetzt: " .. filled .. " -> " .. Locale.Translate(filled)
		.. " (erwartet " .. expected .. ")")
	local numeric = string.gsub(sample[1], "{1}", "12")
	check(Locale.Translate(numeric) == string.gsub(sample[2], "{1}", "12"), "Muster mit Zahl: " .. numeric)
end

-- ---------- Textobjekte ----------
local label = Instance.new("TextLabel", screen)
label.Text = "SPIELEN"
flush()
check(label.Text == "PLAY", "Label beim Setzen übersetzt: " .. label.Text)
label.Text = "30 / 90"
flush()
check(label.Text == "30 / 90", "Zähler bleibt")
label.Text = "PLAY"
flush()
check(label.Text == "PLAY", "englischer Text bleibt")

-- Locale.Set: jeden Frame denselben deutschen Text setzen schreibt das Label nicht jedes Mal um
local ticker = Instance.new("TextLabel", screen)
flush()
local changes = 0
ticker:GetPropertyChangedSignal("Text"):Connect(function()
	changes += 1
end)
Locale.Set(ticker, "SPIELEN")
flush()
check(ticker.Text == "PLAY", "Locale.Set übersetzt wie eine Zuweisung: " .. ticker.Text)
local afterFirst = changes
for _ = 1, 5 do
	Locale.Set(ticker, "SPIELEN")
	flush()
end
check(changes == afterFirst and ticker.Text == "PLAY", "Locale.Set mit gleichem Text ändert nichts (" .. (changes - afterFirst) .. " Änderungen)")
Locale.Set(ticker, "30 / 90")
flush()
check(ticker.Text == "30 / 90", "Locale.Set mit neuem Text setzt ihn")

-- TextBox: PlaceholderText ja, eingetippter Text nein
local box = Instance.new("TextBox", screen)
box.PlaceholderText = "SPIELEN"
flush()
box.Text = "SPIELEN"
flush()
check(box.PlaceholderText == "PLAY", "PlaceholderText übersetzt")
check(box.Text == "SPIELEN", "eingetippter Text bleibt")

-- Schilder in der Welt (SurfaceGui/BillboardGui)
local part = Instance.new("Part", workspace)
local surface = Instance.new("SurfaceGui", part)
local sign = Instance.new("TextLabel", surface)
sign.Text = "SPIELEN"
flush()
check(sign.Text == "PLAY", "Schild in der Welt übersetzt")

-- ---------- Sprache wechseln ----------
PlayerSettings.Set("Language", "de")
flush()
check(Locale.Language() == "de", "Option DEUTSCH wirkt")
check(label.Text == "PLAY" or label.Text == "SPIELEN", "Label-Text gültig: " .. label.Text)
check(early.Text == "SPIELEN", "nach Wechsel auf Deutsch steht wieder das Original: " .. early.Text)
label.Text = "SPIELEN"
flush()
check(label.Text == "SPIELEN", "auf Deutsch wird nichts ersetzt")
PlayerSettings.Set("Language", "auto")
flush()
check(Locale.Language() == "en", "Automatisch mit en-us = Englisch")
check(label.Text == "PLAY", "zurück auf Englisch übersetzt wieder: " .. label.Text)
check(require("UITheme").FormatNumber(22526) == "22,526", "Englisch: Tausenderkomma (" .. require("UITheme").FormatNumber(22526) .. ")")

-- Automatisch mit deutscher Roblox-Sprache = Deutsch (Init neu, nur Sprache und Translate – die Hörer bleiben)
Locale._Reset()
bob.LocaleId = "de-de"
Locale.Init(PlayerSettings)
flush()
check(Locale.Language() == "de", "de-de automatisch Deutsch")
check(Locale.Translate("SPIELEN") == "SPIELEN", "auf Deutsch bleibt der Text")
check(Locale.Translate("SPIELEN", "en") == "PLAY", "Translate mit Sprache en")
check(require("UITheme").FormatNumber(22526) == "22.526", "Deutsch: Tausenderpunkt")

-- Server-Seite: ForPlayer nach Roblox-Sprache
local alice = SIM.AddPlayer("Alice", 1002)
alice.LocaleId = "fr-fr"
check(Locale.ForPlayer(alice, "SPIELEN") == "PLAY", "ForPlayer: fr -> Englisch")
check(Locale.ForPlayer(bob, "SPIELEN") == "SPIELEN", "ForPlayer: de -> Deutsch")

if failures == 0 then
	print("ok locale (" .. count .. " Einträge)")
end

-- ProximityPrompt: ActionText und ObjectText
Locale._Reset()
bob.LocaleId = "en-us"
Locale.Init(PlayerSettings)
local prompt = Instance.new("ProximityPrompt", part)
prompt.ActionText = "SPIELEN"
prompt.ObjectText = "SPIELEN"
flush()
check(prompt.ActionText == "PLAY" and prompt.ObjectText == "PLAY", "ProximityPrompt übersetzt: " .. prompt.ActionText .. "/" .. prompt.ObjectText)

-- PlayerSettings: Prüfen und Speichern der Einstellungen (auch AUS-Werte), Umstellung der Schadenszahlen vom
-- Schalter auf die Stilwahl, Kategorien der Seite OPTIONEN
local PlayerSettings = require("PlayerSettings")

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

-- Jede Einstellung gehört zu einer bekannten Kategorie, Auswahl-Standards sind gültige Optionen
local categories = {}
for _, category in PlayerSettings.Categories do
	categories[category.Id] = category
	check(category.Column == 1 or category.Column == 2, category.Id .. ": Spalte 1 oder 2")
end
for _, setting in PlayerSettings.List do
	check(categories[setting.Category] ~= nil, setting.Key .. ": unbekannte Kategorie " .. tostring(setting.Category))
	if setting.Type == "Choice" then
		local found = false
		for _, option in setting.Options do
			found = found or option[1] == setting.Default
		end
		check(found, setting.Key .. ": Standard ist keine Option")
	end
end
check(categories.Hits and categories.Hits.Preview == "HitFeedback", "TREFFER-Karte mit Vorschau")

-- Server: false bleibt erhalten (Schalter aus, Schadenszahlen AUS)
local saved = PlayerSettings.Sanitize({ KeyHints = false, DamageNumbers = false, HitmarkerStyle = "Precision", Fov = 140,
	Sensitivity = "viel", Unbekannt = 5 }, nil)
check(saved.KeyHints == false, "Tastenhinweise AUS wird gespeichert")
check(saved.DamageNumbers == false, "Schadenszahlen AUS wird gespeichert")
check(saved.HitmarkerStyle == "Precision", "Hitmarker-Stil wird gespeichert")
check(saved.Fov == 100, "Sichtfeld auf das Maximum begrenzt, war " .. tostring(saved.Fov))
check(saved.Sensitivity == nil and saved.Unbekannt == nil, "ungültige und unbekannte Werte fallen weg")

-- Fehlende Werte kommen aus dem bisherigen Profil, auch false
local merged = PlayerSettings.Sanitize({ Fov = 80 }, { KeyHints = false, DamageNumbers = "Stack", Fov = 90 })
check(merged.Fov == 80 and merged.KeyHints == false and merged.DamageNumbers == "Stack", "Zusammenführen mit altem Profil")

-- Alte Profile: Schadenszahlen als Schalter. true -> Standard-Stil, false -> AUS
local old = PlayerSettings.Sanitize({}, { DamageNumbers = true })
check(old.DamageNumbers == nil, "altes true fällt weg (dann gilt der Standard)")
check(PlayerSettings.Definition("DamageNumbers").Default == "Float", "Standard der Schadenszahlen: EINZELN")
check(PlayerSettings.Sanitize({}, { DamageNumbers = false }).DamageNumbers == false, "altes false bleibt AUS")
check(PlayerSettings.Sanitize({ HitmarkerStyle = "Riesig" }, nil).HitmarkerStyle == nil, "unbekannter Stil fällt weg")

-- Zielen je Waffe: false = folgt der allgemeinen Einstellung, eigener Wert wird gespeichert, LMG fehlt (kann nicht zielen)
check(PlayerSettings.Definition("AimSens_LMG") == nil, "LMG hat keine Zielen-Empfindlichkeit")
for _, entry in PlayerSettings.AimWeapons do
	local def = PlayerSettings.Definition(entry.Key)
	check(def ~= nil and def.Follows == "AimSensitivity" and def.Default == false, entry.Key .. ": folgt Zielen allgemein")
end
local aimSaved = PlayerSettings.Sanitize({ AimSens_DMR = 0.4, AimSens_Rifle = false, AimSens_SMG = "x" }, nil)
check(math.abs(aimSaved.AimSens_DMR - 0.4) < 1e-6, "eigener Wert je Waffe wird gespeichert")
check(aimSaved.AimSens_Rifle == false, "folgt allgemein bleibt false")
check(aimSaved.AimSens_SMG == nil, "ungültiger Wert je Waffe fällt weg")

-- Client: Set/Get, auch auf false; gespeichert wird gebündelt nach 1 s
local changes = {}
PlayerSettings.Changed:Connect(function(key, value)
	table.insert(changes, { key, value })
end)
check(PlayerSettings.Get("KeyHints") == true, "Tastenhinweise standardmäßig an")
PlayerSettings.Set("KeyHints", false)
check(PlayerSettings.Get("KeyHints") == false, "Schalter lässt sich ausschalten")
PlayerSettings.Set("DamageNumbers", false)
check(PlayerSettings.Get("DamageNumbers") == false, "Schadenszahlen lassen sich ausschalten")
PlayerSettings.Set("DamageNumbers", "Stack")
PlayerSettings.Set("HitmarkerStyle", "Classic")
PlayerSettings.Set("HitmarkerStyle", "Unsinn")
check(PlayerSettings.Get("HitmarkerStyle") == "Classic", "ungültiger Stil wird ignoriert")
check(#changes == 4, "vier Änderungen gemeldet, waren " .. #changes)
SIM.Run(SIM.Now + 1.5)
local saves = 0
local last
for _, entry in SIM.RemoteLog do
	if entry.Remote == "ShopAction" and entry.Args[1] == "SaveSettings" then
		saves += 1
		last = entry.Args[2]
	end
end
check(saves == 1, "einmal gebündelt gespeichert, waren " .. saves)
check(last and last.KeyHints == false and last.DamageNumbers == "Stack" and last.HitmarkerStyle == "Classic",
	"gespeicherte Werte vollständig")
local server = PlayerSettings.Sanitize(last, nil)
check(server.KeyHints == false and server.DamageNumbers == "Stack" and server.HitmarkerStyle == "Classic",
	"Server übernimmt die gespeicherten Werte")

-- Client: Zielen je Waffe folgt dem allgemeinen Wert, bis ein eigener gesetzt wird; zurück mit false
PlayerSettings.Set("AimSensitivity", 0.8)
check(PlayerSettings.AimSensitivityFor("DMR") == 0.8, "DMR folgt Zielen allgemein")
PlayerSettings.Set("AimSens_DMR", 0.3)
check(math.abs(PlayerSettings.AimSensitivityFor("DMR") - 0.3) < 1e-6, "DMR mit eigenem Wert")
check(PlayerSettings.AimSensitivityFor("Rifle") == 0.8, "andere Waffen bleiben beim allgemeinen Wert")
check(PlayerSettings.AimSensitivityFor("LMG") == 0.8 and PlayerSettings.AimSensitivityFor(nil) == 0.8,
	"unbekannte Waffe: allgemeiner Wert")
PlayerSettings.Set("AimSens_DMR", false)
check(PlayerSettings.AimSensitivityFor("DMR") == 0.8, "DMR wieder zurück auf allgemein")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))

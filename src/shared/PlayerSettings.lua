-- PlayerSettings (ModuleScript)
-- Persönliche Einstellungen (Steuerung, Kamera, Anzeige, Treffer, Ton). Die Liste mit Grenzen gilt für beide Seiten:
--   Server: ShopService.SaveSettings prüft mit Sanitize und speichert im Profil (Spieler-Attribut "ClientSettings").
--   Client: Get/Set, Changed-Signal (key, value), speichert gebündelt kurz nach der letzten Änderung.
-- Module lesen Get(key) bzw. hören auf Changed (Movement: Kamera/Maus, CombatHUD: Fadenkreuz, HitFeedback: Hitmarker
-- und Schadenszahlen, HUD: Tastenhinweise, WeaponClient: Zielen umschalten, GraphicsQuality: Grafik). Die Seite
-- OPTIONEN (SideMenu) baut sich aus List: Karten je Kategorie in zwei Spalten (Column), Preview = Vorschau darunter.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")

local PlayerSettings = {}

PlayerSettings.Categories = {
	{ Id = "Controls", Name = "STEUERUNG", Column = 1 },
	{ Id = "Camera", Name = "KAMERA", Column = 2 },
	{ Id = "Display", Name = "ANZEIGE", Column = 1 },
	{ Id = "Hits", Name = "TREFFER", Column = 2, Preview = "HitFeedback" },
	{ Id = "Audio", Name = "TON", Column = 1 },
}

-- Type: Slider (Min/Max/Step, Format), Toggle (true/false), Choice (Options = { { Wert, "TEXT" } })
PlayerSettings.List = {
	-- Umschauen gilt für Maus, Controller und Touch (Movement skaliert die Drehung der Roblox-Kamera)
	{ Key = "Sensitivity", Category = "Controls", Label = "Umschauen", Type = "Slider", Default = 1,
		Min = 0.1, Max = 3, Step = 0.05, Format = "%.2f", Hint = "Maus, Controller und Touch" },
	{ Key = "AimSensitivity", Category = "Controls", Label = "Zielen (alle Waffen)", Type = "Slider", Default = 0.6,
		Min = 0.2, Max = 1.5, Step = 0.05, Format = "%.2f", Hint = "Faktor auf Umschauen beim Zielen",
		Expand = "AimWeapons" },
	{ Key = "ToggleAim", Category = "Controls", Label = "Zielen", Type = "Choice", Default = false,
		Options = { { false, "HALTEN" }, { true, "UMSCHALTEN" } } },
	{ Key = "ToggleSprint", Category = "Controls", Label = "Sprinten", Type = "Choice", Default = false,
		Options = { { false, "HALTEN" }, { true, "UMSCHALTEN" } } },
	-- Controller (AimAssist): abbremsen am Ziel, beim Anlegen auf Zombies einrasten; Y-Achse umkehren
	{ Key = "AimAssist", Category = "Controls", Label = "Zielhilfe (Controller)", Type = "Toggle", Default = true,
		Hint = "Bremst am Ziel, rastet beim Zielen auf Zombies ein" },
	{ Key = "InvertY", Category = "Controls", Label = "Y-Achse umkehren (Controller)", Type = "Toggle", Default = false },
	{ Key = "Fov", Category = "Camera", Label = "Sichtfeld (FOV)", Type = "Slider", Default = 70, Min = 60, Max = 100, Step = 1,
		Format = "%d" },
	{ Key = "ThirdPerson", Category = "Camera", Label = "Kamera im Kampf", Type = "Choice", Default = false,
		Options = { { false, "EGO" }, { true, "SCHULTER" } }, Hint = "Taste T, Controller ←" },
	{ Key = "ShoulderLeft", Category = "Camera", Label = "Schulter beim Start", Type = "Choice", Default = false,
		Options = { { false, "RECHTS" }, { true, "LINKS" } }, Hint = "Im Spiel wechseln: Taste H, Controller →" },
	{ Key = "CrosshairColor", Category = "Display", Label = "Fadenkreuz-Farbe", Type = "Choice", Default = "White",
		Options = { { "White", "WEISS" }, { "Green", "GRÜN" }, { "Yellow", "GELB" }, { "Cyan", "CYAN" }, { "Pink", "PINK" } } },
	{ Key = "KeyHints", Category = "Display", Label = "Tastenhinweise unten", Type = "Toggle", Default = true },
	-- Anzeigesprache (Locale): Automatisch = Englisch, Deutsch nur bei deutscher Roblox-Sprache
	{ Key = "Language", Category = "Display", Label = "Sprache", Type = "Choice", Default = "auto",
		Options = { { "auto", "AUTOMATISCH" }, { "en", "ENGLISH" }, { "de", "DEUTSCH" } },
		Hint = "Auto: nach deiner Roblox-Sprache, sonst Englisch" },
	{ Key = "Graphics", Category = "Display", Label = "Grafik", Type = "Choice", Default = "High",
		Options = { { "High", "HOCH" }, { "Medium", "MITTEL" }, { "Low", "NIEDRIG" } },
		Hint = "Niedrig: ohne Schatten, Partikel und Leuchteffekte (mehr FPS)" },
	-- Treffer-Rückmeldung (HitFeedback). Schadenszahlen war früher ein Schalter: false = AUS bleibt, true wird zum Standard
	{ Key = "HitmarkerStyle", Category = "Hits", Label = "Hitmarker", Type = "Choice", Default = "Impulse",
		Options = { { "Classic", "KLASSISCH" }, { "Impulse", "IMPULS" }, { "Precision", "PRÄZISION" } },
		Hint = "Mit eigenen Treffer-Tönen" },
	{ Key = "DamageNumbers", Category = "Hits", Label = "Schadenszahlen", Type = "Choice", Default = "Float",
		Options = { { false, "AUS" }, { "Stack", "STAPELN" }, { "Float", "EINZELN" } },
		Hint = "Stapeln: eine Zahl pro Ziel zählt hoch" },
	{ Key = "Volume", Category = "Audio", Label = "Lautstärke (Effekte)", Type = "Slider", Default = 100, Min = 0, Max = 100,
		Step = 5, Format = "%d %%" },
}

-- Zielen je Waffe (aufklappbar unter „Zielen (alle Waffen)“): false = folgt der allgemeinen Einstellung, sonst eigener
-- Faktor. Das LMG fehlt, es kann nicht zielen (HipOnly).
PlayerSettings.AimWeapons = {
	{ Weapon = "Rifle", Label = "Sturmgewehr" },
	{ Weapon = "SMG", Label = "MP" },
	{ Weapon = "DMR", Label = "Präzisionsgewehr" },
	{ Weapon = "Shotgun", Label = "Schrotflinte" },
	{ Weapon = "Pistol", Label = "Pistole" },
	{ Weapon = "Revolver", Label = "Revolver" },
}
for _, entry in PlayerSettings.AimWeapons do
	entry.Key = "AimSens_" .. entry.Weapon
	table.insert(PlayerSettings.List, { Key = entry.Key, Category = "Controls", Group = "AimWeapons", Label = entry.Label,
		Type = "Slider", Default = false, Follows = "AimSensitivity", Min = 0.2, Max = 1.5, Step = 0.05, Format = "%.2f" })
end

PlayerSettings.CrosshairColors = {
	White = Color3.new(1, 1, 1),
	Green = Color3.fromRGB(90, 255, 120),
	Yellow = Color3.fromRGB(255, 230, 70),
	Cyan = Color3.fromRGB(70, 230, 255),
	Pink = Color3.fromRGB(255, 110, 210),
}

local byKey = {}
for _, setting in PlayerSettings.List do
	byKey[setting.Key] = setting
end

function PlayerSettings.Definition(key)
	return byKey[key]
end

-- Einen Wert prüfen: gültiger Wert oder nil
local function clean(setting, value)
	if setting.Type == "Slider" then
		if setting.Follows and value == false then
			return false -- folgt der allgemeinen Einstellung
		end
		value = tonumber(value)
		if not value or value ~= value then
			return nil
		end
		value = math.clamp(value, setting.Min, setting.Max)
		local steps = math.floor((value - setting.Min) / setting.Step + 0.5)
		return math.clamp(setting.Min + steps * setting.Step, setting.Min, setting.Max)
	elseif setting.Type == "Toggle" then
		if type(value) == "boolean" then
			return value
		end
		return nil
	else
		for _, option in setting.Options do
			if option[1] == value then
				return value
			end
		end
		return nil
	end
end

-- Server: nur bekannte, gültige Werte übernehmen; fehlende aus old (bisheriges Profil) behalten.
-- false ist ein gültiger Wert (Schalter aus, Schadenszahlen AUS) und darf nicht wie „fehlt“ behandelt werden.
function PlayerSettings.Sanitize(data, old)
	local result = {}
	for _, setting in PlayerSettings.List do
		local value = nil
		if type(data) == "table" then
			value = clean(setting, data[setting.Key])
		end
		if value == nil and type(old) == "table" then
			value = clean(setting, old[setting.Key])
		end
		result[setting.Key] = value
	end
	return result
end

-- ---------- Client ----------

local values = {}
local touched = {} -- [Key] = true, sobald hier geändert (das erste Laden überschreibt das nicht)
local changedEvent = Instance.new("BindableEvent")
PlayerSettings.Changed = changedEvent.Event -- (key, value)

function PlayerSettings.Get(key)
	local value = values[key]
	if value == nil then
		local setting = byKey[key]
		return setting and setting.Default
	end
	return value
end

-- Wert eines Reglers, der einer anderen Einstellung folgt (Follows), solange er keinen eigenen Wert hat
function PlayerSettings.Effective(key)
	local setting = byKey[key]
	local value = PlayerSettings.Get(key)
	if setting and setting.Follows and type(value) ~= "number" then
		return PlayerSettings.Get(setting.Follows)
	end
	return value
end

-- Empfindlichkeit beim Zielen für eine Waffe: eigener Wert der Waffe oder der allgemeine
function PlayerSettings.AimSensitivityFor(weapon)
	local key = weapon and "AimSens_" .. tostring(weapon)
	if key and byKey[key] then
		return PlayerSettings.Effective(key)
	end
	return PlayerSettings.Get("AimSensitivity")
end

local saveToken = 0
local function scheduleSave()
	saveToken += 1
	local myToken = saveToken
	task.delay(1, function()
		if myToken == saveToken then
			local Remotes = require(script.Parent.Remotes)
			Remotes.ShopAction:FireServer("SaveSettings", values)
		end
	end)
end

function PlayerSettings.Set(key, value)
	local setting = byKey[key]
	value = setting and clean(setting, value)
	if value == nil or value == PlayerSettings.Get(key) then
		return
	end
	values[key] = value
	touched[key] = true
	changedEvent:Fire(key, value)
	scheduleSave()
end

-- Alles auf Standard
function PlayerSettings.Reset()
	for _, setting in PlayerSettings.List do
		PlayerSettings.Set(setting.Key, setting.Default)
	end
end

-- Lautstärke: alle Töne laufen über eine SoundGroup, deren Lautstärke die Einstellung ist
local effects = nil
local function hookSound(sound)
	if sound:IsA("Sound") and sound.SoundGroup == nil then
		sound.SoundGroup = effects
	end
end

function PlayerSettings.Init()
	if not RunService:IsClient() then
		return
	end
	local player = Players.LocalPlayer
	effects = Instance.new("SoundGroup")
	effects.Name = "Effekte"
	effects.Volume = PlayerSettings.Get("Volume") / 100
	effects.Parent = SoundService
	for _, root in { workspace, SoundService, player:WaitForChild("PlayerGui") } do
		for _, child in root:GetDescendants() do
			hookSound(child)
		end
		root.DescendantAdded:Connect(hookSound)
	end
	PlayerSettings.Changed:Connect(function(key, value)
		if key == "Volume" then
			effects.Volume = value / 100
		end
	end)

	-- Gespeicherte Werte einmal übernehmen, sobald das Profil sie liefert (spätere Syncs nicht, sonst würden
	-- noch nicht gespeicherte Änderungen überschrieben)
	local loaded = false
	local function load()
		if loaded then
			return
		end
		local raw = player:GetAttribute("ClientSettings")
		local ok, data = pcall(HttpService.JSONDecode, HttpService, type(raw) == "string" and raw or "")
		if not ok or type(data) ~= "table" or next(data) == nil then
			return
		end
		loaded = true
		for _, setting in PlayerSettings.List do
			local value = clean(setting, data[setting.Key])
			-- schon vor dem Laden hier geändert: die eigene Änderung gilt (sie wird gleich gespeichert)
			if value ~= nil and not touched[setting.Key] and value ~= PlayerSettings.Get(setting.Key) then
				values[setting.Key] = value
				changedEvent:Fire(setting.Key, value)
			end
		end
	end
	load()
	player:GetAttributeChangedSignal("ClientSettings"):Connect(load)
end

return PlayerSettings

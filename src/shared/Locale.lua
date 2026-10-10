-- Locale (ModuleScript)
-- Sprache der Anzeige. Der Code schreibt alle Texte auf Deutsch; auf dem Bildschirm erscheint das Spiel aber
-- **standardmäßig auf Englisch (US)**: Jeder Text, der in einem TextLabel, TextButton oder als PlaceholderText einer
-- TextBox landet, wird beim Setzen in LocaleStrings (Deutsch -> Englisch) nachgeschlagen und ersetzt. Deutsch sehen
-- nur Spieler, deren Roblox-Sprache Deutsch ist (Player.LocaleId "de-de"), oder wer in OPTIONEN › ANZEIGE › SPRACHE
-- DEUTSCH wählt (PlayerSettings "Language": "auto" | "en" | "de").
--
-- Einträge in LocaleStrings:
--   ["SPIELEN"] = "PLAY"                      genauer Text
--   ["Töte {1} Zombies"] = "Kill {1} zombies"  Muster: {1}, {2} … stehen für veränderliche Teile (Zahlen, Namen);
--                                              die Teile werden selbst noch einmal genau nachgeschlagen ("Verband")
-- Texte ohne Eintrag bleiben, wie sie sind (so bleiben englische Texte und Namen der Welt unverändert).
-- Fehlende Einträge findet `python3 tools/locale_scan.py`. Der Server nutzt Locale.Translate nur für Texte,
-- die nicht über ein Textfeld laufen (z.B. Kick-Nachrichten).
--
-- Technik: Locale.Init (Client) hängt sich an alle Textobjekte in PlayerGui und Workspace (Schilder, Blasen, auch
-- ProximityPrompts: ActionText/ObjectText) und an GetPropertyChangedSignal("Text"); das Ersetzen passiert sofort im selben Aufruf, in dem der Code den Text setzt.
-- Eigene Zuweisungen erkennt der Hörer am gemerkten Ergebnis und lässt sie durch. Texte ohne Buchstaben
-- (Zähler, Uhrzeiten) werden gar nicht erst nachgeschlagen. Muster sind nach ihrem ersten Wort sortiert, damit
-- pro Text nur wenige Muster geprüft werden; Ergebnisse werden zwischengespeichert.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Locale = {}

Locale.Default = "en"                 -- Sprache für alle, die nicht Deutsch eingestellt haben
Locale.Languages = { "en", "de" }     -- bekannte Sprachen (de = Quelltext, en = LocaleStrings)

local strings = nil                   -- Deutsch -> Englisch (genau)
local patterns = nil                  -- { [erstesWort] = { { Pattern, Template, Count } } }, "" = beginnt mit Platzhalter
local cache = {}
local cacheSize = 0
local CACHE_LIMIT = 3000
local language = Locale.Default
local setting = "auto"                -- "auto" | "en" | "de"
local lastSet = setmetatable({}, { __mode = "k" }) -- [Textobjekt] = { [Eigenschaft] = zuletzt von uns gesetzter Text }
local started = false

local LETTERS = "[%a\128-\255]"      -- Buchstabe (auch Umlaute in UTF-8)

-- Sprache aus Roblox-Locale ("de-de" -> "de"), sonst Standard
local function fromLocaleId(localeId)
	local code = string.lower(string.match(tostring(localeId or ""), "^(%a%a)") or "")
	if code == "de" then
		return "de"
	end
	return Locale.Default
end

-- ---------- Wörterbuch ----------

local function escapePattern(s)
	return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- wie UITheme.Upper (Umlaute in UTF-8 mit)
local function upperText(s)
	local loud = string.upper(s)
	loud = string.gsub(loud, "ä", "Ä")
	loud = string.gsub(loud, "ö", "Ö")
	loud = string.gsub(loud, "ü", "Ü")
	return loud
end

local function firstWord(s)
	return string.match(s, "^(%S+)") or ""
end

local function load()
	if strings then
		return
	end
	strings, patterns = {}, {}
	local ok, table_ = pcall(function()
		return require(script.Parent:WaitForChild("LocaleStrings"))
	end)
	if not ok or type(table_) ~= "table" then
		return
	end
	-- Großgeschriebene Fassung jedes Eintrags dazu: viele Anzeigen schreiben veränderliche Texte (Aufträge, Aktionen)
	-- erst mit UITheme.Upper groß und setzen sie dann; "TÖTE 19 ZOMBIES" findet so "Töte {1} Zombies".
	-- Eigene Einträge in Großbuchstaben haben Vorrang.
	local entries = {}
	for source, target in table_ do
		if type(source) == "string" and type(target) == "string" then
			entries[source] = target
		end
	end
	for source, target in table_ do
		if type(source) == "string" and type(target) == "string" then
			local loud = upperText(source)
			if entries[loud] == nil then
				entries[loud] = upperText(target)
			end
		end
	end
	for source, target in entries do
		if string.find(source, "{%d}") then
			-- Muster: Text um die Platzhalter herum wörtlich, Platzhalter fangen alles (auch leer)
			local count = 0
			local pattern = "^" .. string.gsub(escapePattern(source), "{(%d)}", function()
				count += 1
				return "(.-)"
			end) .. "$"
			-- Schlüssel = erstes Wort (bis zum Leerzeichen), wenn darin kein {n} steckt – sonst "" ("+{1} Leben" fängt mit "+25" an)
			local head = string.match(source, "^(%S+)")
			local key = (head and not string.find(head, "{")) and head or ""
			patterns[key] = patterns[key] or {}
			local words = string.find((string.gsub(string.gsub(source, "{%d}", ""), "×", "")), LETTERS) ~= nil -- × ist kein Wort
			table.insert(patterns[key], { Pattern = pattern, Template = target, Source = source, Count = count, Wordy = words })
		else
			strings[source] = target
		end
	end
	-- längere Muster zuerst: sie sind genauer als kurze mit frühem Platzhalter
	for _, list in patterns do
		table.sort(list, function(a, b)
			return #a.Source > #b.Source
		end)
	end
end

local translateList -- (weiter unten) Listen Stück für Stück
local isPlayerName -- (weiter unten)

-- Text in die Zielsprache übersetzen (nil = kein Eintrag). Reihenfolge: genau, dann Muster.
local function lookup(text, depth, strict)
	local exact = strings[text]
	if exact then
		return exact
	end
	local function try(list, broad)
		if not list then
			return nil
		end
		for _, entry in list do
			-- strict (Stücke einer Liste): breite Muster mit Wörtern ("{1} Leben") würden Bruchstücke halb übersetzen
			local captures = { string.match(text, entry.Pattern) }
			if captures[1] ~= nil and broad and strict and entry.Wordy then
				-- … außer alle Platzhalter sind Zahlen ("400 Münzen" in einer Liste)
				for _, value in captures do
					if not string.match(value, "^[%d%.,]+$") then
						captures = {}
						break
					end
				end
			end
			if captures[1] ~= nil then
				local missing = false
				local result = string.gsub(entry.Template, "{(%d)}", function(index)
					local value = captures[tonumber(index) or 0] or ""
					-- veränderliche Teile genau nachschlagen (Item-Namen, Orte, …)
					-- (zwei Ebenen: "Fahrrad (Kit) eingepackt." → "{1} eingepackt." → "{1} (Kit)" → "Bicycle")
					if depth < 2 and string.find(value, LETTERS) and not isPlayerName(value) then -- Namen nie übersetzen
						-- eine Liste als Platzhalter ("+ Verband ×2, Fahrrad"): erst stückweise, sonst fängt ein allgemeines
						-- Muster nur den Anfang
						local translated = translateList(value, depth + 1) or lookup(value, depth + 1)
						-- Listen-Stück mit unbekanntem Wort ("2× Quatschding"): nicht als übersetzt zählen
						missing = missing or (strict and (translated == nil or translated == value))
						value = translated or value
					elseif strict and string.find(value, LETTERS) and not isPlayerName(value) then
						missing = true
					end
					return value
				end)
				if missing then
					return nil
				end
				return result
			end
		end
		return nil
	end
	if strict then
		return try(patterns[""], true) -- Stücke: nur reine Mengen-Muster ("{1} ×{2}"), keine Satzanfänge
	end
	return try(patterns[firstWord(text)]) or try(patterns[""], true)
end

-- Spielername? (auch großgeschrieben, wie auf vielen Anzeigen)
function isPlayerName(text)
	local loud = string.upper(text)
	for _, other in Players:GetPlayers() do
		if string.upper(other.Name) == loud or string.upper(other.DisplayName) == loud then
			return true
		end
	end
	return false
end

-- Stück ohne Übersetzung, das trotzdem passt: ohne Buchstaben ("1-9", "□"), Spielername oder kurze Taste ("LMB", "TAB")
local function neutral(piece)
	-- (\195 = Anfang von Ä/Ö/Ü/ä/ö/ü/ß in UTF-8; Zeichen wie □ △ zählen nicht als Buchstaben)
	return not string.find(piece, "[%a\195]") or isPlayerName(piece) or (#piece <= 6 and not string.find(piece, "[%l\195]"))
end

-- Listen ohne eigenen Eintrag ("Verband ×2, 9mm-Munition ×12", "Zombie · …"): Stück für Stück übersetzen, aber nur, wenn
-- jedes Stück einen Eintrag hat (sonst käme halb Deutsch, halb Englisch heraus). Gibt sonst nil zurück.
-- (auch Tasten-Zeilen wie "LMB  SCHIESSEN  ·  R  NACHLADEN / INTERAGIEREN": Taste und Text mit zwei Leerzeichen)
local LIST_SEPARATORS = { "  ·  ", " · ", ", ", "  ", " / " }
function translateList(text, depth)
	if depth > 3 then
		return nil
	end
	for _, separator in LIST_SEPARATORS do
		if string.find(text, separator, 1, true) then
			local parts, changed = {}, false
			for piece in string.gmatch(text .. separator, "(.-)" .. escapePattern(separator)) do
				-- eigener Eintrag zuerst ("KARTE" ist kein Tastenname), aber nie für Spielernamen ("ADLER" bleibt ADLER)
				local translated = not isPlayerName(piece) and strings[piece] or nil
				if translated == nil and not neutral(piece) then
					translated = translateList(piece, depth + 1) or lookup(piece, depth, true)
					if translated == nil then
						return nil
					end
				end
				changed = changed or translated ~= nil
				table.insert(parts, translated or piece)
			end
			return changed and table.concat(parts, separator) or nil
		end
	end
	return nil
end

-- Übersetzung für die aktuelle Sprache (oder lang). Ohne Eintrag oder auf Deutsch kommt der Text unverändert zurück.
function Locale.Translate(text, lang)
	if type(text) ~= "string" or text == "" or (lang or language) == "de" then
		return text
	end
	-- reine Zahlen mit höchstens einem Einheiten-Buchstaben ("123 M", "45 s", "3/10"): nichts zu übersetzen, und
	-- nicht jedes Mal alle Muster durchprobieren (Abstände ändern sich mehrmals pro Sekunde)
	if string.match(text, "^[%d%s%.,:/%%%+%-]*%a?$") then
		return text
	end
	-- Spielernamen sind keine Wörter: "Adler" auf dem Namensschild bleibt "Adler", nicht "Eagle"
	if isPlayerName(text) then
		return text
	end
	load()
	local hit = cache[text]
	if hit ~= nil then
		return hit or text
	end
	local result = nil
	if string.find(text, LETTERS) then
		result = lookup(text, 0)
		if result == nil or result == text then
			result = translateList(text, 0) or result -- allgemeine Muster ändern an Listen oft nichts
		end
	end
	if cacheSize >= CACHE_LIMIT then
		cache, cacheSize = {}, 0
	end
	cache[text] = result or false
	cacheSize += 1
	return result or text
end

-- Übersetzung für einen bestimmten Spieler (Server): dessen Roblox-Sprache entscheidet, Einstellung "Language" zählt
-- über das Attribut ClientSettings nicht – das reicht für Kick-Nachrichten und Ähnliches.
function Locale.ForPlayer(player, text)
	local lang = Locale.Default
	if player then
		local ok, localeId = pcall(function()
			return player.LocaleId
		end)
		lang = fromLocaleId(ok and localeId or nil)
	end
	return Locale.Translate(text, lang)
end

function Locale.Language()
	return language
end

-- Sprache bestimmen: Einstellung vor Roblox-Sprache
local function resolve()
	if setting == "de" or setting == "en" then
		return setting
	end
	local player = Players.LocalPlayer
	local ok, localeId = pcall(function()
		return player and player.LocaleId
	end)
	return fromLocaleId(ok and localeId or nil)
end

-- ---------- Textobjekte (Client) ----------

local function isTextObject(obj)
	return obj:IsA("TextLabel") or obj:IsA("TextButton")
end

local function apply(obj, property)
	local current = obj[property]
	if type(current) ~= "string" or current == "" then
		return
	end
	local translated = Locale.Translate(current)
	if translated ~= current then
		lastSet[obj] = lastSet[obj] or {}
		lastSet[obj][property] = translated
		obj[property] = translated
	end
end

local sources = setmetatable({}, { __mode = "k" }) -- [Textobjekt] = { { Property, Source } … }

-- Welche Eigenschaften eines Objekts Anzeigetext tragen
local function textProperties(obj)
	if isTextObject(obj) then
		return { "Text" }
	elseif obj:IsA("TextBox") then
		return { "PlaceholderText" } -- den eingetippten Text nie anfassen
	elseif obj:IsA("ProximityPrompt") then
		return { "ActionText", "ObjectText" }
	end
	return nil
end

local function hook(obj)
	local properties = textProperties(obj)
	if not properties then
		return
	end
	local entries = {}
	sources[obj] = entries
	for _, property in properties do
		local entry = { Property = property, Source = obj[property] }
		table.insert(entries, entry)
		lastSet[obj] = lastSet[obj] or {}
		obj:GetPropertyChangedSignal(property):Connect(function()
			local now = obj[property]
			if lastSet[obj][property] == now then
				lastSet[obj][property] = nil -- das Echo der eigenen Zuweisung (einmal verbrauchen)
				return
			end
			entry.Source = now -- der Code hat selbst neuen Text gesetzt
			apply(obj, property)
		end)
		apply(obj, property)
	end
end

local function hookTree(root)
	for _, obj in root:GetDescendants() do
		hook(obj)
	end
	root.DescendantAdded:Connect(hook)
end

-- Text setzen, aber nur wenn er sich wirklich ändert. Für Anzeigen, die jeden Frame neu beschrieben werden (Uhr,
-- Zonen-Zeile, Marker): steht dort schon die Übersetzung desselben deutschen Texts, passiert nichts. Eine normale
-- Zuweisung würde jeden Frame zweimal umschreiben (deutsch, dann wieder englisch) und das Layout neu rechnen.
function Locale.Set(obj, text, property)
	property = property or "Text"
	local entries = sources[obj]
	if entries then
		for _, entry in entries do
			if entry.Property == property then
				if entry.Source == text and obj[property] == Locale.Translate(text) then
					return
				end
				break
			end
		end
	elseif obj[property] == text then
		return
	end
	obj[property] = text
end

-- Nach einem Sprachwechsel alle bekannten Texte vom Original aus neu übersetzen
function Locale.Refresh()
	cache, cacheSize = {}, 0
	for obj, entries in sources do
		for _, entry in entries do
			local original = entry.Source
			if type(original) == "string" and original ~= "" then
				local translated = Locale.Translate(original)
				if obj[entry.Property] ~= translated then
					lastSet[obj] = lastSet[obj] or {}
					lastSet[obj][entry.Property] = translated
					obj[entry.Property] = translated
				end
			end
		end
	end
end

-- Einstellung "Language" ("auto" | "en" | "de") übernehmen
function Locale.SetSetting(value)
	setting = (value == "de" or value == "en") and value or "auto"
	local before = language
	language = resolve()
	if started and language ~= before then
		Locale.Refresh()
	end
end

-- Client: Sprache bestimmen und alle Textobjekte übersetzen (PlayerGui und Workspace). settingsModule = PlayerSettings
-- (Get("Language") und Changed), damit die Option OPTIONEN › SPRACHE sofort wirkt.
function Locale.Init(settingsModule)
	if started or not RunService:IsClient() then
		return
	end
	started = true
	if settingsModule then
		Locale.SetSetting(settingsModule.Get("Language"))
		settingsModule.Changed:Connect(function(key, value)
			if key == "Language" then
				Locale.SetSetting(value)
			end
		end)
	else
		language = resolve()
	end
	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChild("PlayerGui")
	if gui then
		hookTree(gui)
	elseif player then
		player.ChildAdded:Connect(function(child)
			if child.Name == "PlayerGui" then
				hookTree(child)
			end
		end)
	end
	hookTree(workspace)
end

-- Für Tests: Zustand zurücksetzen
function Locale._Reset()
	strings, patterns, cache, cacheSize = nil, nil, {}, 0
	language, setting, started = Locale.Default, "auto", false
	lastSet = setmetatable({}, { __mode = "k" })
	sources = setmetatable({}, { __mode = "k" })
end

return Locale

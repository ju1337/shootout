-- DiscordLog (ModuleScript, nur Server)
-- Wichtige Ereignisse live in einen Discord-Channel (Webhook). Nur der Server sendet – die Webhook-Adresse steht
-- NICHT im Code, sondern als Roblox-Secret "DiscordLog" (Creator Hub › Experience › Secrets, erlaubte Domain
-- discord.com bzw. die Domain eines eigenen Proxys). Ohne Secret, in Studio und in Tests wird nichts gesendet.
--
--   DiscordLog.Log(kind, title, text, fields)  kind = "Moderation" | "Anticheat" | "Economy" | "Error" | "Server"
--                                              | "Highlight"; fields = { { Name, Wert }, ... } (optional)
--
-- Automatisch: Serverstart/-ende, Zusammenfassung alle 30 Minuten, Fehler und Warnungen aus dem Output (gleiche
-- Meldungen zusammengefasst, MovementGuard -> Anticheat). Gesendet wird gesammelt alle FlushEvery Sekunden (Discord
-- sperrt Webhooks, die zu oft senden), höchstens MaxPerFlush Einträge pro Runde, Rest wird gezählt.
-- Datenschutz: nur Spielername/UserId und Spiel-Ereignisse, keine Chat-Texte.

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DiscordLog = {}

DiscordLog.SecretName = "DiscordLog"
DiscordLog.Enabled = not RunService:IsStudio()
DiscordLog.FlushEvery = 6 -- Sekunden
DiscordLog.MaxPerFlush = 10 -- Discord: höchstens 10 Embeds pro Nachricht
DiscordLog.SummaryEvery = 30 * 60
DiscordLog.Sent = {} -- für Tests: zuletzt gebaute Nachrichten (Tabellen wie an Discord)

local KINDS = {
	Moderation = { Label = "🛡️ Moderation", Color = 0x5865F2 },
	Anticheat = { Label = "🚨 Anti-Cheat", Color = 0xED4245 },
	Economy = { Label = "💰 Wirtschaft", Color = 0xF1C40F },
	Error = { Label = "❌ Fehler", Color = 0xE67E22 },
	Server = { Label = "🖥️ Server", Color = 0x95A5A6 },
	Highlight = { Label = "⭐ Highlight", Color = 0x57F287 },
}
local SELF = "[DiscordLog]" -- eigene Warnungen nicht wieder loggen

local queue = {}
local repeats = {} -- [Schlüssel] = Eintrag in queue (gleiche Meldungen zählen hoch statt neu)
local dropped = 0
local secret = nil
local pausedUntil = 0

local function clip(text, limit)
	text = tostring(text or "")
	if #text > limit then
		return string.sub(text, 1, limit - 1) .. "…"
	end
	return text
end

function DiscordLog.Log(kind, title, text, fields, key)
	local info = KINDS[kind] or KINDS.Server
	if key and repeats[key] then
		repeats[key].Count += 1
		return
	end
	if #queue >= DiscordLog.MaxPerFlush * 3 then
		dropped += 1
		return
	end
	local okTime, at = pcall(function()
		return DateTime.now():ToIsoDate()
	end)
	local entry = { Kind = info, Title = clip(title, 200), Text = clip(text, 1500), Fields = fields, Count = 1,
		At = okTime and at or nil, Key = key }
	table.insert(queue, entry)
	if key then
		repeats[key] = entry
	end
end

-- Spieler als "Name (UserId)"
function DiscordLog.Who(player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		return player.Name .. " (" .. player.UserId .. ")"
	end
	return tostring(player)
end

local function serverTag()
	local job = game.JobId ~= "" and string.sub(game.JobId, 1, 8) or "studio"
	return "Server " .. job .. " · v" .. tostring(game.PlaceVersion) .. " · " .. #Players:GetPlayers() .. " Spieler"
end

-- Nächste Nachricht aus der Warteschlange (nil = nichts zu senden)
function DiscordLog.Build()
	if #queue == 0 and dropped == 0 then
		return nil
	end
	local embeds = {}
	for i = 1, math.min(DiscordLog.MaxPerFlush, #queue) do
		local entry = table.remove(queue, 1)
		if entry.Key then
			repeats[entry.Key] = nil -- gesendet: gleiche Meldung zählt ab jetzt neu
		end
		local fields = {}
		for _, field in entry.Fields or {} do
			table.insert(fields, { name = clip(field[1], 250), value = clip(field[2], 1000), inline = true })
		end
		local title = entry.Kind.Label .. " · " .. entry.Title .. (entry.Count > 1 and (" ×" .. entry.Count) or "")
		embeds[i] = { title = clip(title, 250), description = entry.Text ~= "" and entry.Text or nil,
			color = entry.Kind.Color, fields = #fields > 0 and fields or nil, timestamp = entry.At,
			footer = { text = serverTag() } }
	end
	local content = nil
	if dropped > 0 then
		content = "… " .. dropped .. " weitere Einträge übersprungen (zu viele auf einmal)"
		dropped = 0
	end
	local message = { username = "Shootout Logs", content = content, embeds = embeds,
		allowed_mentions = { parse = {} } } -- niemals @everyone/@here auslösen
	table.insert(DiscordLog.Sent, message)
	if #DiscordLog.Sent > 20 then
		table.remove(DiscordLog.Sent, 1)
	end
	return message
end

local function send(message)
	if not secret or os.clock() < pausedUntil then
		return
	end
	local ok, err = pcall(function()
		HttpService:PostAsync(secret, HttpService:JSONEncode(message), Enum.HttpContentType.ApplicationJson)
	end)
	if not ok then
		pausedUntil = os.clock() + 30 -- z.B. Discord-Ratenlimit (429) oder kein HTTP erlaubt: kurz Pause
		warn(SELF .. " Senden fehlgeschlagen: " .. tostring(err))
	end
end

function DiscordLog.Flush()
	local message = DiscordLog.Build()
	if message and DiscordLog.Enabled then
		send(message)
	end
end

-- Meldungen aus dem Output: Fehler immer, Warnungen nur, wenn sie wichtig aussehen
local WARN_WORDS = { "konnte", "konnten", "fehlgeschlagen", "Fehler", "DataStore", "nicht gespeichert", "hängt",
	"Wächter", "failed", "error" }
local function onMessage(text, messageType)
	if string.find(text, SELF, 1, true) then
		return
	end
	local key = string.gsub(text, "%d+", "#") -- gleiche Meldung mit anderen Zahlen zählt zusammen
	if string.find(text, "MovementGuard", 1, true) then
		DiscordLog.Log("Anticheat", "Bewegung zurückgesetzt", text, nil, "mg" .. key)
	elseif messageType == Enum.MessageType.MessageError then
		DiscordLog.Log("Error", "Skriptfehler", "```" .. clip(text, 1400) .. "```", nil, "err" .. key)
	elseif messageType == Enum.MessageType.MessageWarning then
		for _, word in WARN_WORDS do
			if string.find(text, word, 1, true) then
				DiscordLog.Log("Error", "Warnung", text, nil, "warn" .. key)
				return
			end
		end
	end
end

local function summary()
	local modes = {}
	for _, player in Players:GetPlayers() do
		local mode = tostring(player:GetAttribute("Mode") or "Hub")
		modes[mode] = (modes[mode] or 0) + 1
	end
	local fields = {}
	for mode, count in modes do
		table.insert(fields, { mode, tostring(count) })
	end
	table.sort(fields, function(a, b)
		return a[1] < b[1]
	end)
	DiscordLog.Log("Server", "Zusammenfassung", #Players:GetPlayers() .. " Spieler online", fields)
end

local started = false
function DiscordLog.Init()
	if started or not RunService:IsServer() then
		return
	end
	started = true
	local ok, result = pcall(function()
		return HttpService:GetSecret(DiscordLog.SecretName)
	end)
	secret = ok and result or nil
	if DiscordLog.Enabled and not secret then
		warn(SELF .. " Secret \"" .. DiscordLog.SecretName .. "\" fehlt – Discord-Logs aus")
	end
	LogService.MessageOut:Connect(onMessage)
	local startedAt = os.clock()
	DiscordLog.Log("Server", "Server gestartet", "Place-Version " .. tostring(game.PlaceVersion))
	task.spawn(function()
		local nextSummary = os.clock() + DiscordLog.SummaryEvery
		while true do
			task.wait(DiscordLog.FlushEvery)
			if os.clock() >= nextSummary then
				nextSummary += DiscordLog.SummaryEvery
				summary()
			end
			DiscordLog.Flush()
		end
	end)
	game:BindToClose(function()
		DiscordLog.Log("Server", "Server fährt herunter", string.format("lief %d Minuten",
			math.floor((os.clock() - startedAt) / 60)))
		DiscordLog.Flush()
	end)
end

return DiscordLog

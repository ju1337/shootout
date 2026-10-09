-- DiscordLog (ModuleScript, nur Server)
-- Wichtige Ereignisse live in einen Discord-Channel (Webhook). Nur der Server sendet – die Webhook-Adresse steht
-- NICHT im Code, sondern als Roblox-Secret "DiscordLog" (Creator Hub › Experience › Secrets, erlaubte Domain
-- discord.com bzw. die Domain eines eigenen Proxys). Ohne Secret, in Studio und in Tests wird nichts gesendet.
-- Getrennte Channels (optional): weitere Secrets mit den Webhooks der Channels, siehe CHANNELS – "DiscordLogMod"
-- (Moderation, Anti-Cheat), "DiscordLogEconomy" (Wirtschaft, Highlights) und "DiscordLogError" (Fehler). Fehlt eins,
-- landet der Bereich im Haupt-Channel (Secret "DiscordLog"), Server-Meldungen immer dort.
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
	Moderation = { Label = "🛡️ Moderation", Color = 0x5865F2, Channel = "Mod" },
	Anticheat = { Label = "🚨 Anti-Cheat", Color = 0xED4245, Channel = "Mod" },
	Economy = { Label = "💰 Wirtschaft", Color = 0xF1C40F, Channel = "Economy" },
	Error = { Label = "❌ Fehler", Color = 0xE67E22, Channel = "Error" },
	Server = { Label = "🖥️ Server", Color = 0x95A5A6 },
	Highlight = { Label = "⭐ Highlight", Color = 0x57F287, Channel = "Economy" },
}
-- Channel -> Secret mit seinem Webhook ("Main" = Haupt-Channel, Secret DiscordLog.SecretName)
local CHANNELS = { Mod = "DiscordLogMod", Economy = "DiscordLogEconomy", Error = "DiscordLogError" }
DiscordLog.Channels = CHANNELS
local SELF = "[DiscordLog]" -- eigene Warnungen nicht wieder loggen

-- Je Channel eine Warteschlange: { Queue, Repeats ([Schlüssel] = Eintrag, gleiche Meldungen zählen hoch statt neu),
-- Dropped, Secret, PausedUntil }
local channels = {}
local function channel(name)
	local state = channels[name]
	if not state then
		state = { Queue = {}, Repeats = {}, Dropped = 0, Secret = nil, PausedUntil = 0 }
		channels[name] = state
	end
	return state
end
channel("Main")

-- Wohin geht ein Bereich? In seinen Channel, wenn dessen Secret da ist, sonst in den Haupt-Channel
local function route(info)
	local name = info.Channel
	return (name and channels[name] and channels[name].Secret) and name or "Main"
end

local function clip(text, limit)
	text = tostring(text or "")
	if #text > limit then
		return string.sub(text, 1, limit - 1) .. "…"
	end
	return text
end

function DiscordLog.Log(kind, title, text, fields, key)
	local info = KINDS[kind] or KINDS.Server
	local state = channel(route(info))
	local queue, repeats = state.Queue, state.Repeats
	if key and repeats[key] then
		repeats[key].Count += 1
		return
	end
	if #queue >= DiscordLog.MaxPerFlush * 3 then
		state.Dropped += 1
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

-- Nächste Nachricht aus der Warteschlange eines Channels (Standard "Main"; nil = nichts zu senden)
function DiscordLog.Build(name)
	local state = channel(name or "Main")
	local queue, repeats = state.Queue, state.Repeats
	if #queue == 0 and state.Dropped == 0 then
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
	if state.Dropped > 0 then
		content = "… " .. state.Dropped .. " weitere Einträge übersprungen (zu viele auf einmal)"
		state.Dropped = 0
	end
	local message = { username = "Shootout Logs", content = content, embeds = embeds,
		allowed_mentions = { parse = {} } } -- niemals @everyone/@here auslösen
	table.insert(DiscordLog.Sent, message)
	if #DiscordLog.Sent > 20 then
		table.remove(DiscordLog.Sent, 1)
	end
	return message
end

local function send(state, name, message)
	if not state.Secret or os.clock() < state.PausedUntil then
		return
	end
	local ok, err = pcall(function()
		HttpService:PostAsync(state.Secret, HttpService:JSONEncode(message), Enum.HttpContentType.ApplicationJson)
	end)
	if not ok then
		state.PausedUntil = os.clock() + 30 -- z.B. Discord-Ratenlimit (429) oder kein HTTP erlaubt: kurz Pause
		warn(SELF .. " Senden fehlgeschlagen (" .. name .. "): " .. tostring(err))
	end
end

function DiscordLog.Flush()
	for name, state in channels do
		local message = DiscordLog.Build(name)
		if message and DiscordLog.Enabled then
			send(state, name, message)
		end
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
		local mode = tostring(player:GetAttribute("Mode") or "-")
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

-- Für Tests: so tun, als gäbe es das Secret eines Channels (Route ohne echtes Senden)
function DiscordLog.SetChannelSecret(name, value)
	channel(name).Secret = value
end

local started = false
function DiscordLog.Init()
	if started or not RunService:IsServer() then
		return
	end
	started = true
	local function secretOf(name)
		local ok, result = pcall(function()
			return HttpService:GetSecret(name)
		end)
		return ok and result or nil
	end
	channel("Main").Secret = secretOf(DiscordLog.SecretName)
	for name, secretName in CHANNELS do
		channel(name).Secret = secretOf(secretName)
	end
	if DiscordLog.Enabled and not channel("Main").Secret then
		warn(SELF .. " Secret \"" .. DiscordLog.SecretName .. "\" fehlt – Discord-Logs nur in eigenen Channels")
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

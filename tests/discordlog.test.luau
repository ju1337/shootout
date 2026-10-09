--!expose DiscordLog onMessage
-- Discord-Logs: sammeln, gleiche Meldungen zusammenfassen, max. 10 pro Nachricht, nie @everyone, Fehler aus dem
-- Output landen im richtigen Bereich. (Gesendet wird in Tests nie – kein Secret, Studio.)
local failures = 0
local function check(c, m) if not c then failures += 1 print("FEHLER: " .. m) end end

local DiscordLog = require("DiscordLog")
check(DiscordLog.Build() == nil, "leere Warteschlange baut eine Nachricht")

DiscordLog.Log("Moderation", "Admin: Ban", "Spieler gesperrt @everyone", { { "Admin", "Osman (1)" } })
local m = DiscordLog.Build()
check(m ~= nil and #m.embeds == 1, "kein Embed")
check(m and m.allowed_mentions and #m.allowed_mentions.parse == 0, "Erwähnungen nicht abgeschaltet")
check(m and string.find(m.embeds[1].title, "Moderation", 1, true) ~= nil, "Bereich fehlt im Titel")
check(m and m.embeds[1].fields[1].name == "Admin", "Felder fehlen")

-- gleiche Fehlermeldung mit anderen Zahlen: ein Eintrag mit Zähler
for i = 1, 5 do
	DiscordLog.__onMessage("Workspace.Script:" .. i .. ": attempt to index nil", Enum.MessageType.MessageError)
end
DiscordLog.__onMessage("MovementGuard: Hacker zurückgesetzt (90 Studs waagerecht, 0 nach oben; 3. Mal)",
	Enum.MessageType.MessageWarning)
DiscordLog.__onMessage("Spieler hat Level 5 erreicht", Enum.MessageType.MessageWarning) -- unwichtig: nicht loggen
DiscordLog.__onMessage("Spielerdaten konnten nicht gespeichert werden: 503", Enum.MessageType.MessageWarning)
DiscordLog.__onMessage("[DiscordLog] Senden fehlgeschlagen", Enum.MessageType.MessageWarning) -- eigene: nie
m = DiscordLog.Build()
check(m ~= nil and #m.embeds == 3, "erwartet 3 Einträge (Fehler ×5, Anti-Cheat, Speichern), sind " .. (m and #m.embeds or 0))
check(m and string.find(m.embeds[1].title, "×5", 1, true) ~= nil, "gleiche Fehler nicht zusammengefasst")
check(m and string.find(m.embeds[2].title, "Anti-Cheat", 1, true) ~= nil, "MovementGuard nicht unter Anti-Cheat")

-- viele Einträge: 10 pro Nachricht, Überschuss gezählt
for i = 1, 40 do
	DiscordLog.Log("Economy", "Tausch " .. i, "x")
end
m = DiscordLog.Build()
check(m and #m.embeds == 10, "mehr als 10 Embeds in einer Nachricht")
check(m and m.content and string.find(m.content, "10 weitere", 1, true) ~= nil, "übersprungene nicht gemeldet")
check(#DiscordLog.Build().embeds == 10 and #DiscordLog.Build().embeds == 10 and DiscordLog.Build() == nil,
	"Rest nicht in weiteren Nachrichten")
-- sehr lange Texte werden gekürzt
DiscordLog.Log("Error", string.rep("T", 400), string.rep("x", 5000))
m = DiscordLog.Build()
check(#m.embeds[1].title <= 250 * 3 and #m.embeds[1].description <= 1500 * 3, "Texte nicht gekürzt")

-- getrennte Channels: mit Secret eigener Channel, sonst Haupt-Channel; Server-Meldungen immer im Haupt-Channel
DiscordLog.SetChannelSecret("Mod", "https://example.invalid/mod")
DiscordLog.Log("Moderation", "Admin: Kick", "x")
DiscordLog.Log("Anticheat", "Bewegung zurückgesetzt", "x")
DiscordLog.Log("Error", "Skriptfehler", "x") -- ohne eigenes Secret
DiscordLog.Log("Server", "Server gestartet", "x")
local mod, main = DiscordLog.Build("Mod"), DiscordLog.Build()
check(mod and #mod.embeds == 2, "Moderation und Anti-Cheat im Mod-Channel")
check(main and #main.embeds == 2 and string.find(main.embeds[1].title, "Fehler", 1, true) ~= nil
	and string.find(main.embeds[2].title, "Server", 1, true) ~= nil, "Fehler (ohne Secret) und Server im Haupt-Channel")
check(DiscordLog.Build("Economy") == nil, "Wirtschaft leer")
check(DiscordLog.Channels.Mod == "DiscordLogMod" and DiscordLog.Channels.Economy == "DiscordLogEconomy"
	and DiscordLog.Channels.Error == "DiscordLogError", "Secret-Namen")

if failures == 0 then print("alles ok") end

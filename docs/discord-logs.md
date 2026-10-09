# Discord-Logs

Der Spiel-Server schickt wichtige Ereignisse in einen Discord-Channel (`src/server-shared/DiscordLog.lua`).

| Bereich | Was |
|---|---|
| 🛡️ Moderation | jede Aktion im Admin-Panel (wer, was, Werte, Ergebnis) – z.B. Bann, Kick, Münzen geben |
| 🚨 Anti-Cheat | MovementGuard setzt jemanden zurück (Speedhack/Teleport), gleiche Meldungen zusammengefasst |
| 💰 Wirtschaft | Robux-Käufe (Produkt, Robux), Tausche zwischen Spielern (beide Seiten) |
| ❌ Fehler | Skriptfehler und wichtige Warnungen (DataStore, Speichern/Laden, Start-Wächter), gezählt statt gespammt |
| 🖥️ Server | Start, Herunterfahren, alle 30 Minuten Spieler je Modus |
| ⭐ Highlight | Boss besiegt (wer), legendärer Skin aus der Kiste, Glücksrad-Jackpot |

Gesendet wird gesammelt alle 6 Sekunden (max. 10 Einträge pro Nachricht), nie aus Studio, nie vom Client.
Keine Chat-Texte, nur Spielername/UserId.

## Einrichten (einmal)

1. Discord: Channel › Bearbeiten › Integrationen › Webhooks › Neuer Webhook › **Webhook-URL kopieren**.
   Die URL ist geheim – nie in den Code, nie auf GitHub.
2. Roblox: Creator Hub › Experience › **Secrets** › Neu:
   - Name: `DiscordLog`
   - Wert: die Webhook-URL
   - Domain: `discord.com`
3. Studio: Game Settings › Security › **Allow HTTP Requests** an, dann Publish.
4. Server starten (echtes Spiel, nicht Studio) – im Channel erscheint „Server gestartet“.

### Getrennte Channels (optional)

Für jeden weiteren Channel einen eigenen Webhook anlegen und als weiteres Secret eintragen (Domain wie oben):

| Secret | Channel bekommt |
|---|---|
| `DiscordLogMod` | 🛡️ Moderation, 🚨 Anti-Cheat |
| `DiscordLogEconomy` | 💰 Wirtschaft, ⭐ Highlights |
| `DiscordLogError` | ❌ Fehler |

Fehlt eins, landen diese Einträge im Haupt-Channel (`DiscordLog`); 🖥️ Server-Meldungen kommen immer dorthin.

**Kommt nichts an** und steht im Server-Log `[DiscordLog] Senden fehlgeschlagen: HTTP 403`, blockt Discord Roblox.
Dann den Proxy nutzen: `tools/discord-proxy/worker.js` als Cloudflare Worker anlegen (kostenlos), dort `WEBHOOK`
und `KEY` als Secrets eintragen und in Roblox das Secret `DiscordLog` auf `https://<worker>.workers.dev/<KEY>`
ändern (Domain `*.workers.dev`).

## Neue Logs

```lua
local DiscordLog = require(ServerStorage.ServerShared.DiscordLog)
DiscordLog.Log("Highlight", "Boss besiegt", "Der Schlächter fiel", { { "Spieler", DiscordLog.Who(player) } })
```
Bereiche: Moderation, Anticheat, Economy, Error, Server, Highlight.

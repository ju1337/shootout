# Shootout

Roblox-Shooter im Stil von Rogue Company. Alles läuft in **einem** Place: Hub, Modi und Training
sind eigene Bereiche der Welt, Moduswechsel funktionieren deshalb auch direkt in Studio.

## Entwickeln

    ./rojo serve                           # dann in Studio: Rojo → Connect
    ./rojo build -o build/shootout.rbxlx   # fertige Place-Datei bauen
    python3 tools/build_maps.py            # Maps neu erzeugen (nach Änderungen am Map-Skript)

## Modi

| Modus | Kurz | Map (Mitte) |
|---|---|---|
| Hub | Große Hangar-Halle: 10 farbige Einsatz-Tore mit Live-Spielerzahl, Lineup-Bühne; Ruhmeshalle (Bestenlisten, Top-3-Statuen) hinter dem Spawn | Hangar (0, 0, 0) |
| Free-for-All | jeder gegen jeden, Respawn | Raffinerie 250x250 (0, 0, 1500) |
| Drop | 5v5, Absprung über der Map, ein Leben | Tal (1500, 0, 0) |
| Strikeout | 4v4, Respawn-Tickets, Punkt zieht Tickets ab, Overtime auf dem Punkt | Rotation: Fabrik / Zellenblock / Kanäle / Windmühlen |
| Demolition | 4v4, Bombe legen/entschärfen, Seitenwechsel | Rotation: Hafen / Gletscher / Kanäle / Windmühlen |
| Extraction | 4v4, Ziel hacken, Seitenwechsel | Rotation: Gletscher / Windmühlen |
| Team Deathmatch | 4v4, 40 Leben pro Team | Rotation: Fabrik / Hochhaus |
| Wingman | 2v2, Strikeout-Regeln | Rotation: Fabrik / Hochhaus |
| Ranked | Demolition mit ELO, ab Spielerlevel 10 | Rotation: Hafen / Windmühlen / Hochhaus |
| 1v1 Arena | Duell | Arena (0, 0, 3000) |
| Training | Schießstand mit Übungspuppen | (-1500, 0, 1500) |

Team-Modi teilen sich die Logik in `src/server/TeamRoundMode.lua` (Agentenwahl, Kaufphase,
Niederschlagen/Wiederbeleben, Bots). Ein neuer Team-Modus ist eine kurze Konfiguration in
`src/server/Modes/`, eigene Ziele (z.B. die Bombe) liegen in `src/server/Objectives/`.

## Systeme

- **Statistik** (dauerhaft): Kills, Tode, K/D, Assists, Kopfschuss- und Trefferquote, Siegquote, ..., Verlauf der letzten 10 Matches (STATS-Fenster)
- **Ranked mit ELO**: Start 1000, 5 Platzierungsspiele, Ränge Bronze III bis Meister, Peak, globale Top 10
- **Squads**: bis 4 Spieler, folgen dem Anführer, landen im selben Team
- **Agenten**: 9 Stück mit Passiv, je 2 wählbare Primärwaffen, Fähigkeit (Q) und Gadget (G), Level + Skins
- **Kaufphase**: Geld pro Match, Upgrades, Rüstung, Perks
- **Battle Pass, tägliche Aufträge, Shop, Codes**
- **Map-Rotation** pro Match, Multikills und ACE, Todeskamera, Schnelles Spiel
- **Auto-Bots** füllen leere Plätze (auch allein spielbar), Bot-Schwierigkeit im Admin-Panel
- **HUD im RC-Stil**: Team-Rauten, Kompass, Treffer-Richtung, großer Countdown, Namensschilder nur fürs Team
- **Kamera**: Ego oder Schulter (T), Schulter wechseln (X)

## Steuerung

WASD/Leertaste · Shift Sprint · STRG/C Ducken (im Sprint: Slide) · Springen vor Kanten: Klettern ·
Linksklick Schießen · Rechtsklick Zielen · R Nachladen · 1/2 Waffe · V Messer · Q Fähigkeit ·
G Gadget · E Wiederbeleben/Bombe · Z Ping · T Kamera (Ego/Schulter) · X Schulter wechseln · Tab Punkte · M Menü · P Admin-Panel

## Wo stelle ich was ein?

| Was | Datei |
|---|---|
| Waffen (Schaden, Feuerrate, Rückstoß, Sounds) | `src/shared/WeaponConfig.lua` |
| Agenten (Leben, Tempo, Waffen, Fähigkeit, Gadget), Level | `src/shared/AgentConfig.lua` |
| Kaufphase, Geld, Perks | `src/shared/BuyConfig.lua` |
| Skins und Preise im Shop | `src/shared/Cosmetics.lua` |
| Battle Pass | `src/shared/PassConfig.lua` |
| Tägliche Aufträge | `src/shared/QuestConfig.lua` |
| Ränge (Ranked) | `src/shared/RankConfig.lua` |
| Live-Einstellungen (auch im Admin-Panel) | `src/shared/GameSettings.lua` |
| Modi im Menü | `src/shared/Modes.lua` |
| Admins | `ADMIN_IDS` in `src/server/AdminService.lua` |
| Codes | `CODES` in `src/server-shared/ShopService.lua` |

## Speichern

XP, Münzen, Skins, Rangpunkte, Battle Pass und Aufträge liegen im DataStore. Das funktioniert erst,
wenn das Spiel veröffentlicht ist und in Studio "Enable Studio Access to API Services" an ist –
vorher gilt alles nur für die Sitzung.

## Ordner

- `src/shared` – Client + Server: Konfigurationen, Waffen-Client, HUD, Menü, Bewegung
- `src/server-shared` – Server-Dienste: Schaden, Kills, Agenten, Fortschritt, Shop, Gadgets, Perks, Pings
- `src/server` – Modus-Verwaltung, Team-Runden-Logik, Modi, Bots, Admin
- `src/client` – Agentenwahl, Seitenleiste, Admin-Panel, Scoreboard, Gleiten, Zuschauen, ...
- `src/maps` – generierte Maps (nicht von Hand bearbeiten)
- `tools/build_maps.py` – erzeugt alle Maps

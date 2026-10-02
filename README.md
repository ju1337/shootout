# Shootout

Roblox-Shooter im Stil von Rogue Company. Alles läuft in **einem** Place: Hub, Modi und Training
sind eigene Bereiche der Welt, Moduswechsel funktionieren deshalb auch direkt in Studio.

## Entwickeln

    ./rojo serve                           # dann in Studio: Rojo → Connect
    ./rojo build -o build/shootout.rbxlx   # fertige Place-Datei bauen
    python3 tools/build_maps.py            # Maps neu erzeugen (nach Änderungen am Map-Skript)

## Modi

| Modus | Kurz | Map |
|---|---|---|
| Hub | Hangar mit Einsatz-Toren, Lineup-Bühne, Ruhmeshalle (Bestenlisten, Top-3-Statuen) | Hangar (0, 0, 0) |
| Free-for-All | jeder gegen jeden, Respawn | Raffinerie (0, 0, 1500) |
| Herrschaft | 5v5, Flaggen A/B/C halten, unbegrenzter Respawn, 200 Punkte gewinnen | Tal (1500, 0, 0) |
| Wingman (DUELS) | 2v2, Punkt halten, Respawn-Tickets | Rotation: Fabrik / Hochhaus / Gletscher / Zellenblock / Kanäle / Windmühlen |
| 1v1 Arena (DUELS) | Duell | Arena (0, 0, 3000) |
| Training | Schießstand mit Übungspuppen | (-1500, 0, 1500) |

ELO gibt es in jedem Modus (kein eigenes Ranked-Matchmaking). Ausgebaute Modi (Drop, Strikeout, Demolition,
Ranked, Extraction, TDM) stehen in `Modes.Disabled`; ihr Code liegt noch in `src/server/Modes/`.

Team-Modi teilen sich die Logik in `src/server/TeamRoundMode.lua` (Agentenwahl, Kaufphase,
Niederschlagen/Wiederbeleben, Bots). Ein neuer Team-Modus ist eine kurze Konfiguration in
`src/server/Modes/`, eigene Ziele (z.B. die Bombe) liegen in `src/server/Objectives/`.

## Systeme

- **Statistik** (dauerhaft): Kills, Tode, K/D, Assists, Kopfschuss- und Trefferquote, Siegquote, ..., Verlauf der letzten 10 Matches (STATS-Fenster)
- **ELO in jedem Modus**: Start 1000, 5 Platzierungsspiele, Ränge Bronze III bis Meister, Peak, globale Top 10
- **Squads**: bis 4 Spieler, folgen dem Anführer, landen im selben Team
- **Agenten**: 9 Stück mit Passiv, je 2 wählbare Primärwaffen, Fähigkeit (Q) und Gadget (G), Level + Skins
- **Kaufphase**: Geld pro Match, Upgrades, Rüstung, Perks
- **Battle Pass, tägliche Aufträge, Shop, Codes**
- **Map-Rotation** pro Match, Multikills und ACE, Todeskamera, Schnelles Spiel
- **Auto-Bots** füllen leere Plätze (auch allein spielbar), Bot-Schwierigkeit im Admin-Panel
- **Match-HUD wie bei Rogue Company**:
  - oben: Ziel des eigenen Teams („NIMM DEN PUNKT EIN“, „LEGE DIE BOMBE BEI A ODER B“ …), Teamleiste mit
    Agenten-Porträts und Lebensbalken (eigenes Team Cyan links, Gegner rot rechts, ✕ = ausgeschaltet),
    Rundenstand in schrägen Kästen, Rundenuhr (Bomben-Timer rot, OVERTIME), Tickets, Status des Ziels
  - oben links: runde Minimap, dreht sich mit der Blickrichtung; Grundriss der Map, Teamkollegen, Pings,
    Gegner nur kurz, wenn sie schießen oder per Radar markiert sind; Ziele A/B kleben am Rand
  - rechts: Killfeed „Name [Waffen-Silhouette] ▼ Name“ (▼ niedergeschlagen, ☠ ausgeschaltet, ◎ Kopfschuss)
  - unten links: Porträt, Leben „100/100“ mit Segment-Balken (25er-Schritte, Verlust blitzt rot nach), Rüstung
  - unten rechts: Fähigkeit und Gadget als Rauten (Taste, Abklingzeit, Aufladungen), Munition „20 /200“,
    Waffen-Silhouette, Taste + Name der anderen Waffe
  - in der Welt: Zielmarker (Raute mit Buchstabe, Entfernung in Metern, Einnahme-Fortschritt, UMKÄMPFT/BOMBE)
  - dazu Treffer-Richtung, großer Countdown, Namensschilder nur fürs Team; auf Touch-Geräten angepasstes Layout
- **Kamera**: Ego oder Schulter (T), Schulter wechseln (X); beim Zielen rückt die Schulterkamera näher heran
- **Schießen wie bei Rogue Company**:
  - Schulterkamera: dynamisches Fadenkreuz (Abstand = echte Streuung durch Laufen, Springen, Dauerfeuer),
    zieht sich beim Zielen zu einem kleinen Kreuz zusammen, wird über Gegnern rot; Schrotflinte mit Kreis.
    Der Server sucht den Punkt unter dem Fadenkreuz und schießt vom Charakter aus dorthin – ist etwas im Weg,
    zeigt ein rotes ⊘ die Stelle
  - Ego-Perspektive: jede Waffe hat Kimme und Korn (mit Leuchtpunkt), beim Zielen liegt die Visierlinie genau
    in der Bildmitte; Waffe mit Armen, schwankt beim Umsehen, wippt beim Laufen, gesenkt beim Sprinten
  - Nachlade-Animation je Waffe (Magazin fällt heraus, Schlitten, Spannhebel, LMG-Deckel, Revolver-Trommel,
    Schrotflinte Patrone für Patrone – Schießen bricht dort das Nachladen ab), auch in der Third-Person bei allen
    Spielern und Bots sichtbar: Charaktere halten die Waffe mit beiden Händen und zielen mit
  - Rückstoß mit Rückkehr, Bloom bei Dauerfeuer, Mündungsfeuer, fliegende Leuchtspuren, Funken/Staub und
    Einschusslöcher, Hülsen; eigene Schüsse erscheinen sofort (ohne Ping-Verzögerung)
  - Hitmarker je Treffer-Art (Körper weiß, Kopf gelb, Rüstung blau, niedergeschlagen orange, ausgeschaltet rot)
    mit eigenem Ton, hochzählende Schadenszahlen pro Ziel, rote Treffer-Richtungsbögen, Kill-Meldung
  - Schießstand: unendliche Reserve-Munition (Anzeige „∞“)

## Steuerung

WASD/Leertaste · Shift Sprint · STRG/C Ducken (im Sprint: Slide) · Springen vor Kanten: Klettern ·
Linksklick Schießen · Rechtsklick Zielen · R Nachladen · 1/2 Waffe · V Messer · Q Fähigkeit ·
G Gadget · E Wiederbeleben/Bombe · Z Ping · T Kamera (Ego/Schulter) · X Schulter wechseln · Tab Punkte · M Menü · P Admin-Panel

## Wo stelle ich was ein?

| Was | Datei |
|---|---|
| Waffen (Schaden, Feuerrate, Streuung/Bloom, Rückstoß, Sounds, unendliche Munition je Modus) | `src/shared/WeaponConfig.lua` |
| Waffenmodelle, Kimme/Korn, Handpositionen | `src/shared/GunModels.lua` |
| Nachlade- und Schuss-Animationen | `src/shared/WeaponAnimations.lua` |
| Fadenkreuz, Hitmarker, Schadenszahlen, Treffer-Richtung | `src/shared/CombatHUD.lua` |
| Match-HUD (Teamleiste, Killfeed, Leben, Munition, Zielmarker) | `src/shared/MatchHUD.lua` |
| Minimap (Farben, Zoom) | `src/shared/Minimap.lua` |
| Ziel-Text und Zielmarker je Modus | `Goal` / `Objectives` in `src/shared/Modes.lua` |
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

- `src/shared` – Client + Server: Konfigurationen, Waffen-Client (ViewModel = Ego-Waffe, CharacterPose =
  Third-Person-Haltung, WeaponEffects = Schuss-Effekte), HUD (MatchHUD, Minimap, CombatHUD, HUDIcons =
  Porträts/Waffen-Silhouetten, TeamCheck = wer ist Freund/Feind), Menü, Bewegung
- `src/server-shared` – Server-Dienste: Schaden, Kills, Agenten, Fortschritt, Shop, Gadgets, Perks, Pings
- `src/server` – Modus-Verwaltung, Team-Runden-Logik, Modi, Bots, Admin
- `src/client` – Agentenwahl, Seitenleiste, Admin-Panel, Scoreboard, Gleiten, Zuschauen, ...
- `src/maps` – generierte Maps (nicht von Hand bearbeiten)
- `tools/build_maps.py` – erzeugt alle Maps

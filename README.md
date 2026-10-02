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
- **Menü-Design „BLOCKOPS“** (`src/shared/UITheme.lua`): Stahl-Navy, Signalgelb für aktiv/Hauptknöpfe, Cyan fürs
  eigene Team, Rot für Gegner; klobige Knöpfe mit Schatten, die beim Drücken nach unten rutschen
  (`UITheme.Chunky`), Flächen mit runden Ecken, 2 px Rand und Schatten (`UITheme.Card`), große Namen in
  schwerer Schrift mit Kontur (`UITheme.Outline`)
- **Lobby** (M bzw. SPIELEN im Hub): oben Logo, Navigation SPIELEN · AGENTEN · LOADOUT · SHOP · BATTLE PASS,
  Münzen, Level, Statistik, Codes, Einstellungen; links Spielmodi (aktiv gelb mit Haken, live Spielerzahl) und der
  Squad (Anführer mit Krone, Level, BEREIT/NICHT BEREIT zum Umschalten, freie Plätze laden ein); Mitte der
  gewählte Agent groß in 3D mit Rolle und Namen; rechts Battle Pass (Stufe, Fortschritt, nächste Belohnung),
  täglicher Auftrag (bzw. tägliche Belohnung) und der große SPIELEN-Knopf mit Modus, Spielerzahl und Ping.
  AGENTEN zeigt alle Agenten als Karten; LOADOUT, SHOP, BATTLE PASS und die Symbole öffnen die Fenster darüber
- **Hub**: große Spielerkarte (Level, Prestige, Rang, Münzen), Kachel-Leiste (Shop, Loadout, Agenten, Pass,
  Aufträge, Täglich, Squad, Stats, Codes, Optionen) und SPIELEN-Knopf
- **Agenten**: 9 Stück mit Passiv, je 2 wählbare Primärwaffen, Fähigkeit (Q) und Gadget (G), Level + Skins
- **Ultimate „Überladung“** (F, Controller L1+R1, Touch ✦): lädt über Schaden (400 = voll), Kills/Niederschläge
  und langsam im Kampf; voll ausgelöst: volles Leben, +25 Rüstung, Fähigkeit sofort bereit, +1 Gadget
  (`AgentConfig.Ultimate`)
- **Kaufphase**: Geld pro Match, Upgrades, Rüstung, Perks
- **Agentenwahl im Hangar eines Raumschiffs** (3D-Hintergrund, Design der Lobby): oben Modus/Map, große
  Überschrift und Timer (letzte 10 s rot); links DEIN TEAM (Porträt, Agent, BESTÄTIGT/WÄHLT), darunter WAFFE
  (Primärwaffen mit 3D-Vorschau, überfahren = Vorschau in der Hand) und direkt darunter AUSRÜSTUNG mit Geld;
  Mitte der Agent; rechts Rolle, Name, Beschreibung, Werte-Balken (Leben, Tempo, Fähigkeit) und Fähigkeit,
  Gadget, Passiv mit Tasten-Schild; unten Agenten-Kacheln mit Porträt und BESTÄTIGEN bzw. BEREIT
- **Ablauf**: nach dem Match erst die Zusammenfassung, dann die Map-Abstimmung, danach die Agentenwahl –
  nie übereinander
- **Respawn-Modi** (Herrschaft, Wingman mit Tickets): nach dem Tod kurz die Todeskamera, dann zurück in die
  Auswahl (Agent, Primärwaffe, Ausrüstung kaufen); BEREIT bringt einen zurück (frühestens nach 3 s, spätestens
  nach 9 s). Rüstung und Extra-Gadget gelten bis zum nächsten Tod. Wer während Herrschaft dazukommt, wählt kurz
  und steigt sofort ein
- **Unendliche Reserve-Munition in allen Modi** (nachladen muss man trotzdem; `WeaponConfig.InfiniteAmmoEverywhere`)
- **Level im Match** (außer in Menüs): Prestige-Abzeichen, Level und XP-Balken unten links; im Hub steht das Level
  groß auf der Spielerkarte
- **Battle Pass, tägliche Aufträge, Shop, Codes**
- **Map-Rotation** pro Match, Multikills und ACE, Todeskamera, Schnelles Spiel
- **Auto-Bots** füllen leere Plätze (auch allein spielbar), Bot-Schwierigkeit im Admin-Panel. Bot-Körper werden
  einmal pro Farbe gebaut und dann geklont; ein abgebrochener oder überholter Spawn baut kein zweites Modell,
  und Modelle ohne gültigen Bot räumt der BotService nach spätestens 2 s weg (keine „Bot-Massen“ mehr)
- **Match-HUD im Design der Lobby**:
  - oben: Ziel des eigenen Teams („HALTE DIE FLAGGEN“ …), Punktestand-Fläche (eigenes Team Cyan links, Gegner
    rot rechts, Mitte Runde und Uhr, Tickets klein in den Kästen), darunter ein Kästchen pro Spieler (lebt / am
    Boden / ☠) und ein Schild mit dem Zustand des Ziels
  - oben links (unter der Roblox-Leiste): runde Minimap, dreht sich mit der Blickrichtung; Grundriss der Map
    (Böden, Wände, Deckung), Teamkollegen, Pings, Gegner nur kurz, wenn sie schießen oder per Radar markiert
    sind; Ziele/Flaggen in der Farbe des Besitzers, außerhalb kleben sie am Rand
  - darunter links ein MENÜ-Knopf (öffnet das Menü mit „Zurück zum Hub“), ganz unten die Tastenzeile
  - rechts: Killfeed-Zeilen mit farbigem Rand, Waffe als Schild, eigene Kills gelb (▼ niedergeschlagen,
    ☠ ausgeschaltet, ◎ Kopfschuss)
  - unten links: Fläche mit Porträt, Agentenname, Rüstung in 5 Segmenten und Leben als Zahl + Balken
    (Verlust blitzt rot nach)
  - unten mittig: Fähigkeit (Q) und Gadget (G) als klobige Knöpfe (Abklingzeit als Abdeckung + Sekunden,
    Aufladungen), daneben der runde ULT-Knopf (Ladung in Prozent)
  - unten rechts: Fläche mit Waffen-Silhouette, Waffenplätzen 1/2, Waffenname, Munition „30 / ∞“ und der
    anderen Waffe
  - in der Welt: Zielmarker (Raute mit Buchstabe, Entfernung in Metern, Einnahme-Fortschritt, UMKÄMPFT/BOMBE)
  - Free-for-All: oben in der Mitte die eigenen Kills, das Ziel und wer führt, darunter die ersten drei
  - dazu Treffer-Richtung, großer Countdown, Namensschilder nur fürs Team; auf Touch-Geräten angepasstes Layout;
    im Kampf kein Mauszeiger über dem Fadenkreuz
- **Kamera**: Ego oder Schulter (T), Schulter wechseln (X). Schulterkamera wie bei RC: Charakter links im Bild,
  das Fadenkreuz bleibt frei – auch beim Zielen, wenn die Kamera näher heranrückt; steht rechts eine Wand,
  rückt die Kamera seitlich an den Kopf statt durch die Wand zu schauen (Werte oben in `src/shared/Movement.lua`)
- **Schießen wie bei Rogue Company**:
  - Schulterkamera: dynamisches Fadenkreuz (Abstand = echte Streuung durch Laufen, Springen, Dauerfeuer),
    zieht sich beim Zielen zu einem kleinen Kreuz zusammen, wird über Gegnern rot; Schrotflinte mit Kreis.
    Der Server sucht den Punkt unter dem Fadenkreuz und schießt vom Charakter aus dorthin – ist etwas im Weg,
    zeigt ein rotes ⊘ die Stelle
  - Ego-Perspektive: jede Waffe hat Kimme und Korn (mit Leuchtpunkt), das Sturmgewehr ein Rotpunktvisier (Gehäuse,
    Rahmen mit getöntem Glas, roter Punkt mittig im Fenster); beim Zielen liegt die Visierlinie genau
    in der Bildmitte; Waffe mit Armen, schwankt beim Umsehen, wippt beim Laufen, gesenkt beim Sprinten
  - Nachlade-Animation je Waffe (Magazin fällt heraus, Schlitten, Spannhebel, LMG-Deckel, Revolver-Trommel,
    Schrotflinte Patrone für Patrone – Schießen bricht dort das Nachladen ab), auch in der Third-Person bei allen
    Spielern und Bots sichtbar: Charaktere halten die Waffe mit beiden Händen und zielen mit
  - Rückstoß mit Rückkehr, Bloom bei Dauerfeuer, Mündungsfeuer, fliegende Leuchtspuren, Funken/Staub und
    Einschusslöcher, Hülsen; eigene Schüsse erscheinen sofort (ohne Ping-Verzögerung)
  - Hitmarker je Treffer-Art (Körper weiß, Kopf gelb, Rüstung blau, niedergeschlagen orange, ausgeschaltet rot)
    mit eigenem Ton, hochzählende Schadenszahlen pro Ziel, rote Treffer-Richtungsbögen, Kill-Meldung
  - unendliche Reserve-Munition in allen Modi (Anzeige „∞“)

## Steuerung

WASD/Leertaste · Shift Sprint · STRG/C Ducken (im Sprint: Slide) · Springen vor Kanten: Klettern ·
Linksklick Schießen · Rechtsklick Zielen · R Nachladen · 1/2 Waffe · V Messer · Q Fähigkeit ·
G Gadget · E Wiederbeleben/Bombe · Z Ping · T Kamera (Ego/Schulter) · X Schulter wechseln · Tab Punkte · M Menü · P Admin-Panel

## Wo stelle ich was ein?

| Was | Datei |
|---|---|
| Waffen (Schaden, Feuerrate, Streuung/Bloom, Rückstoß, Sounds, unendliche Munition je Modus) | `src/shared/WeaponConfig.lua` |
| Waffenmodelle, Kimme/Korn, Rotpunkt, Handpositionen | `src/shared/GunModels.lua` |
| Nachlade- und Schuss-Animationen | `src/shared/WeaponAnimations.lua` |
| Fadenkreuz, Hitmarker, Schadenszahlen, Treffer-Richtung | `src/shared/CombatHUD.lua` |
| Menü-Design (Farben, Schriften, Knöpfe, Flächen) | `src/shared/UITheme.lua` |
| Lobby (Navigation, Modi, Squad, Battle Pass, SPIELEN) | `src/shared/GameMenu.lua`, Fenster und Hub-Leiste in `src/client/SideMenu.lua` |
| Match-HUD (Punktestand, Killfeed, Leben, Munition, Zielmarker) | `src/shared/MatchHUD.lua`, Anordnung und Größe der Munitionsanzeige (`AMMO_SCALE`) in `src/shared/HUD.lua` |
| Fähigkeits- und ULT-Knöpfe | `src/shared/AbilityClient.lua`, Ultimate-Werte in `AgentConfig.Ultimate` |
| Schulterkamera (Versatz, Abstand, beim Zielen) | `SHOULDER_*` in `src/shared/Movement.lua` |
| Minimap (Farben, Zoom) | `src/shared/Minimap.lua`, Zuschnitt auf den Kreis in `src/shared/MinimapShapes.lua` |
| Ziel-Text und Zielmarker je Modus | `Goal` / `Objectives` in `src/shared/Modes.lua` |
| Agenten (Leben, Tempo, Waffen, Fähigkeit, Gadget), Level | `src/shared/AgentConfig.lua` |
| Kaufphase, Geld, Perks | `src/shared/BuyConfig.lua` |
| Agentenwahl (Aufbau) und Hangar-Hintergrund | `src/client/AgentSelect.lua`, `src/shared/HangarScene.lua` |
| Respawn-Auswahl (Dauer, frühestes BEREIT), Pause nach dem Match | `RESPAWN_SELECT_TIME`, `RESPAWN_MIN_TIME`, `SUMMARY_TIME` in `src/server/TeamRoundMode.lua` |
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

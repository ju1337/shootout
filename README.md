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
| Hub | Kompakte Einsatzzentrale: Tore nebeneinander an der Nordwand (DUELS rechts), Kartentisch mit Einsatz-Tafel, Bühne mit eigenem Agenten, Wand der Bestenlisten + Top-3-Statuen. Alter Hangar: `HUB_STYLE = "classic"` in `tools/build_maps.py` (fertig auch in `tools/saved/Hub_classic.model.json`) | Hub (0, 0, 0) |
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
- **Realistischer Taktik-Look** (`src/shared/UITheme.lua`): Graphit als Grund, gedecktes Bernstein als einzige
  Signalfarbe (aktiv, Hauptknöpfe), Stahlblau fürs eigene Team, Rot für Gegner; flache Knöpfe und Flächen mit
  kaum gerundeten Ecken und 1 px Rand, keine Schatten-Lippen oder Comic-Konturen; Überschriften, Zahlen und
  Knöpfe in der schmalen Oswald, kleine Beschriftungen automatisch in Gotham (`UITheme.FontFor`); keine bunten
  Emojis mehr (Münzen als gezeichnete Münze bzw. „MÜNZEN“, Touch-Knöpfe mit Wörtern). Oswald kennt in Roblox
  nur lateinische Zeichen – Symbole wie ✕ ✓ ★ ◆ → erscheinen dort als Kästchen; darum werden Schließen-Kreuz
  (`UITheme.Cross`), Raute und Münze gezeichnet und ∞ kommt aus Roboto. Dazu passend: gedeckte
  Agenten-, Modus- und Team-Uniformfarben (Burgund/Sturmblau, Erdgrün/Rehbraun, Rost/Sandblau – über alle Modi
  eindeutig), getönte Glas-Visiere statt Neon, weniger Sättigung und Bloom in der Farbkorrektur
  (`default.project.json`), die Arena aus Beton statt lila Plastik, im Hub Bernstein-Lichtleisten und
  gedeckte Tore, Schilder in Oswald (`tools/build_maps.py`)
- **Lobby** (M bzw. SPIELEN im Hub): oben Logo, Reiter SPIELEN · AGENTEN · LOADOUT · SHOP · BATTLE PASS (aktiv mit
  Bernstein-Strich), Münzen, Level, STATISTIK, CODES, OPTIONEN. Jeder Reiter ist eine eigene Seite in der Lobby
  (kein Extra-Fenster):
  - SPIELEN: links Spielmodi (aktiv heller mit Bernstein-Balken, live Spielerzahl) und der Squad (Anführer mit
    Stern, Level, BEREIT/NICHT BEREIT zum Umschalten, freie Plätze laden ein); Mitte der gewählte Agent groß in
    3D; rechts Battle Pass, täglicher Auftrag und der große SPIELEN-Knopf mit Modus, Spielerzahl und Ping
  - AGENTEN: links eine Detailkarte (überfahrener bzw. angeklickter Agent: Rolle, Beschreibung, Werte, Fähigkeit,
    Gadget, Passiv, Agenten-Level, Kills und WÄHLEN/FREISCHALTEN), rechts alle Agenten als Karten. Ein Klick
    wählt einen freien Agenten; gesperrte schaltet man nur bewusst über den Knopf der Detailkarte frei
  - LOADOUT: links Waffen bzw. Agenten, Mitte große 3D-Vorschau mit ausgerüstetem Skin, rechts die eigenen Skins
    zum Ausrüsten und ZUM SHOP
  - SHOP: Waffen- und Agenten-Skins als Karten mit 3D-Vorschau, Seltenheit und KAUFEN · Preis
  - BATTLE PASS: Saison, Stufe, Fortschritt, alle 30 Stufen als Leiste (nächste hervorgehoben), darunter die
    nächste Belohnung mit Vorschau und wie man Pass-XP sammelt
  - Statistik, Codes, Optionen, Aufträge, tägliche Belohnung und Squad öffnen weiterhin ein Fenster darüber
- **Hub**: Spielerkarte (Level, Prestige, Rang, Münzen), schlichte Menüliste (Shop, Loadout, Agenten, Battle
  Pass öffnen die Lobby auf der passenden Seite; Aufträge, Täglich, Squad, Statistik, Codes, Optionen als
  Fenster) und SPIELEN-Knopf
- **Agenten**: 9 Stück mit Passiv, je 2 wählbare Primärwaffen, Fähigkeit (Q) und Gadget (G), Level + Skins
- **Ultimate „Überladung“** (F, Controller L1+R1, Touch-Knopf ULT): lädt über Schaden (400 = voll), Kills/Niederschläge
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
- **Match-HUD** (dunkle, halbtransparente Flächen ohne Rahmen, schmale Zahlen, dünne Balken):
  - oben: Ziel des eigenen Teams („HALTE DIE FLAGGEN“ …), Punktestand (eigenes Team blau links, Gegner rot
    rechts, Mitte Runde und Uhr, Tickets klein in den Kästen), darunter ein Kästchen pro Spieler (gefüllt = lebt,
    orange = am Boden, leer = ausgeschaltet) und eine Zeile mit dem Zustand des Ziels
  - oben links (unter der Roblox-Leiste): runde Minimap, dreht sich mit der Blickrichtung; Grundriss der Map
    (Böden, Wände, Deckung), Teamkollegen, Pings, Gegner nur kurz, wenn sie schießen oder per Radar markiert
    sind; Ziele/Flaggen in der Farbe des Besitzers, außerhalb kleben sie am Rand
  - darunter ein VERLASSEN-Knopf: erster Klick fragt rot nach („WIRKLICH VERLASSEN?“), ein zweiter Klick
    innerhalb von 3 s bringt einen zurück in den Hub (auf Touch-Geräten rechts neben der Minimap); ganz unten
    eine dezente Tastenzeile
  - rechts: Killfeed – dunkle Zeilen mit farbiger Kante, Waffe als graue Schrift, eigene Kills mit
    Bernstein-Kante (▼ niedergeschlagen, ◎ Kopfschuss)
  - unten links: Porträt, Agentenname, Rüstung in 5 dünnen Segmenten und Leben als Zahl + Balken
    (Verlust blitzt rot nach)
  - unten rechts: Waffen-Silhouette, Waffenplätze 1/2, Waffenname, Munition „30 / ∞“ und die andere Waffe;
    direkt links daneben, genauso hoch, Fähigkeit (Q), Gadget (G) und Ultimate (F) als drei schlanke Zeilen:
    Taste, Name, rechts Abklingzeit in Sekunden, Aufladungen „×1“ bzw. Ladung „64 %“/BEREIT, unten ein dünner
    Balken (Bernstein = bereit, grau = lädt, blau = Fähigkeit läuft)
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
G Gadget · F Ultimate · E Wiederbeleben/Bombe · Z Ping · T Kamera (Ego/Schulter) · X Schulter wechseln · Tab Punkte ·
M Menü (im Hub; im Match: VERLASSEN-Knopf unter der Minimap) · P Admin-Panel

## Wo stelle ich was ein?

| Was | Datei |
|---|---|
| Waffen (Schaden, Feuerrate, Streuung/Bloom, Rückstoß, Sounds, unendliche Munition je Modus) | `src/shared/WeaponConfig.lua` |
| Waffenmodelle, Kimme/Korn, Rotpunkt, Handpositionen | `src/shared/GunModels.lua` |
| Nachlade- und Schuss-Animationen | `src/shared/WeaponAnimations.lua` |
| Fadenkreuz, Hitmarker, Schadenszahlen, Treffer-Richtung | `src/shared/CombatHUD.lua` |
| Design (Farben, Schriften, Knöpfe, Flächen, HUD-Flächen) | `src/shared/UITheme.lua` |
| Lobby (Navigation, Seiten SPIELEN und AGENTEN, Modi, Squad, SPIELEN-Knopf) | `src/shared/GameMenu.lua` |
| Lobby-Seiten LOADOUT, SHOP, BATTLE PASS | `src/shared/LobbyPages.lua` |
| Fenster (Statistik, Codes, Optionen, Aufträge, Täglich, Squad) und Hub-Menüliste | `src/client/SideMenu.lua` |
| Match-HUD (Punktestand, Killfeed, Leben, Munition, Zielmarker) | `src/shared/MatchHUD.lua`, Anordnung und Größe der Munitionsanzeige (`AMMO_SCALE`) in `src/shared/HUD.lua` |
| Fähigkeits-Zeilen (Fähigkeit, Gadget, Ultimate) | `src/shared/AbilityClient.lua`, Ultimate-Werte in `AgentConfig.Ultimate` |
| VERLASSEN-Knopf im Match (Bestätigungszeit) | `LEAVE_CONFIRM` in `src/shared/HUD.lua` |
| Licht und Farbkorrektur der Welt | `Lighting` in `default.project.json` |
| Team-Uniformfarben (je Modus eindeutig) | `Teams` in `src/server/Modes/*.lua` |
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

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
| Markt | Handelshalle ohne Kampf: Stände beanspruchen, Skins für RAP anbieten und kaufen (Tor MARKT im Hub, Knopf MARKT im Seitenmenü) | Markthalle (-1500, 0, -1500) |
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
  - AGENTEN: links eine Detailkarte (überfahrener bzw. angeklickter Agent: Rolle, Beschreibung, Werte,
    STANDARDWAFFE, Fähigkeit, Gadget, Passiv, Agenten-Level, Kills und WÄHLEN/FREISCHALTEN), rechts alle Agenten
    als Karten. Ein Klick wählt einen freien Agenten; gesperrte schaltet man nur bewusst über den Knopf der
    Detailkarte frei. STANDARDWAFFE: die zwei Primärwaffen des Agenten als Karten mit 3D-Vorschau (mit Skin) –
    ein Klick rüstet eine aus (Bernstein-Rahmen, AUSGERÜSTET), daneben die feste Zweitwaffe. Die Wahl gilt pro
    Agent für jeden Spawn, in der Agentenwahl vor dem Match lässt sie sich weiter ändern; auf den Agentenkarten
    steht die ausgerüstete Waffe hell
  - LOADOUT: links Waffen bzw. Agenten, Mitte große 3D-Vorschau mit ausgerüstetem Skin, rechts die eigenen Skins
    zum Ausrüsten und ZUM SHOP
  - SHOP: Waffen- und Agenten-Skins als Karten mit 3D-Vorschau, Seltenheit und KAUFEN · Preis
  - BATTLE PASS: Saison, Stufe, Fortschritt, alle 30 Stufen als Leiste (nächste hervorgehoben), darunter die
    nächste Belohnung mit Vorschau und wie man Pass-XP sammelt
  - OPTIONEN: Karten STEUERUNG, ANZEIGE und TON links, KAMERA und TREFFER rechts; unter TREFFER (Hitmarker,
    Schadenszahlen) eine Live-Vorschau: Puppe mit Fadenkreuz, auf die eine Trefferfolge mit Kopftreffer und Kill
    läuft – leise in Schleife, nach dem Umschalten oder per Klick mit Ton. Alles wirkt sofort und wird gespeichert
  - Statistik, Codes, Optionen, Aufträge, tägliche Belohnung und Squad öffnen weiterhin ein Fenster darüber
- **Hub**: Spielerkarte (Level, Prestige, Rang, Münzen), schlichte Menüliste (Shop, Loadout, Agenten, Battle
  Pass öffnen die Lobby auf der passenden Seite; Aufträge, Täglich, Squad, Statistik, Codes, Optionen als
  Fenster) und SPIELEN-Knopf unten mittig (Bernstein mit rundem Play-Symbol, darunter gewählter Modus und
  Spielerzahl, rechts die Taste M bzw. Steuerkreuz unten; ein Rand breitet sich immer wieder aus, alle paar
  Sekunden läuft ein Glanz darüber, Überfahren vergrößert ihn leicht)
- **Glücksrad im Hub** (`src/client/HubWheel.lua`, in der Ecke links vom Spawn am Ende eines eigenen Teppichs, schräg zur Hallenmitte gedreht): großes Rad mit acht
  Feldern (`LoginConfig.Wheel`), Rand mit Lichtern und Zeiger oben; Podest, Ständer, Schild und Pult kommen aus
  der Map, das drehende Rad baut der Client an `WheelSpot`. Am Pult **E** (Controller □, Touch: Antippen): der Server
  lost das Feld aus, das Rad dreht ein paar Runden, der Zeiger klackt an jedem Steg, die Lichter laufen mit, das
  Rad hält genau auf dem Gewinn, das Feld blinkt und eine Belohnungs-Karte erscheint. Die Tafel am Pult zeigt
  GRATIS-DREH BEREIT, Extra-Drehs oder die Zeit bis zum nächsten Gratis-Dreh. Einmal am Tag gratis, Extra-Drehs aus
  dem Login-Kalender; gedreht wird nur im Hub in der Nähe des Rads (Server prüft). Den Knopf im Seitenmenü gibt
  es nicht mehr
- **RAP – zweite Währung** (`src/shared/RapConfig.lua`, Server `src/server-shared/EconomyService.lua`): RAP bekommt
  man nur über seltene Skins. Jeder seltene Skin (Waffe oder Agent) hat einen festen RAP-Wert; man kann ihn
  - im **SHOP** unter **VERKAUFEN** ans System zurückverkaufen: sofort 70 % des Werts (`RapConfig.SellRate`),
    erster Klick fragt nach, zweiter verkauft,
  - im **MARKT** am eigenen Stand zum eigenen Preis anbieten (5 % Marktgebühr, `RapConfig.MarketFee`),
  - mit anderen Spielern tauschen.
  Mit dem RAP kauft man im Markt Skins von anderen Spielern. Handelbare Skins kann man mehrfach besitzen
  (Duplikate aus Glücksrad, Login-Kalender, Wochen-Bonus, Robux-Paket oder Markt); gebunden – ohne RAP-Wert –
  bleiben gewöhnliche Skins, Belohnungen für Level, Prestige, Rang und Saison und die Meisterschafts-Tarnungen.
  Angezeigt wird RAP in der Lobby-Kopfzeile (neben den Münzen), auf der Spielerkarte im Hub, als Wert-Schild auf
  den Shop-Karten und **über dem Kopf jedes Spielers** (nur im Hub und im Markt): Guthaben + Wert seiner
  handelbaren Skins, die Farbe zeigt die Stufe (grau, mint ab 1.000, blau ab 5.000, lila ab 15.000, gold ab
  50.000, rot ab 150.000). Skins, die gerade an einem Stand oder in einem Tausch liegen, bleiben im Inventar,
  lassen sich aber nicht gleichzeitig verkaufen. Alte Spielstände (Besitz = true) zählen als 1 Stück.
  Admin-Panel: **+10.000 RAP** und **Handelbarer Skin** zum Testen
- **Markt** (Halle mit 12 Ständen; Server `src/server-shared/MarketService.lua` + `src/server/Modes/Market.lua`,
  Client `src/client/MarketClient.lua`, Map `build_market()` in `tools/build_maps.py`): wie die Trading Plaza in
  Sniper Arena / Pet Simulator. Hin über das grüne Tor MARKT an der Ostwand des Hubs oder den Knopf MARKT im
  Seitenmenü (im Markt heißt er ZUM HUB), zurück durchs Tor im Süden der Halle.
  - **Stand beanspruchen**: an einem freien Stand **E** – man steht dann hinter seiner Theke, das Schild über
    dem Stand zeigt den eigenen Namen. Einer pro Spieler.
  - **MEIN STAND** (E am eigenen Stand oder Knopf in der Markt-Leiste oben): links sechs Plätze (Preis ändern,
    ZURÜCK nimmt das Angebot zurück), rechts die eigenen handelbaren Skins mit Preisfeld (Vorschlag: RAP-Wert)
    und ANBIETEN. Angebotene Skins drehen sich auf Theke und Regal, darüber ein Preisschild.
  - **Kaufen**: E an einem fremden Stand öffnet seine Angebote (Preis, RAP-Wert, wie viel darüber/darunter);
    KAUFEN zweimal klicken. Bezahlt wird mit RAP, 5 % Marktgebühr gehen beim Verkäufer ab; beide Spielstände
    werden sofort gespeichert, der Verkäufer bekommt eine Meldung. Der Server prüft Nähe zum Stand, ob der
    angezeigte Preis noch stimmt und ob genug RAP da ist.
  - **Stand weg**: Wer den Markt verlässt (in eine Runde, in den Hub, Spiel verlassen) oder ABGEBEN drückt, verliert
    den Stand – die angebotenen Skins waren nur zurückgelegt und sind sofort wieder frei im Inventar, jemand anderes
    kann den Stand nehmen. Squads werden nicht mit in den Markt gezogen
- **Tauschen** (Server `src/server-shared/TradeService.lua`, Client `src/client/TradeClient.lua`): im Hub oder im
  Markt an einem anderen Spieler **G** halten (Controller △, Touch: Antippen) schickt eine Anfrage; sie erscheint
  rechts als Karte mit ANNEHMEN / ABLEHNEN (20 s gültig, fragen sich beide gegenseitig, geht der Tausch sofort auf).
  Im Tausch-Fenster legt jeder handelbare Skins (**+** aus der eigenen Liste, **-** nimmt wieder raus) und RAP
  hinein, der RAP-Wert beider Seiten steht oben. Sind beide **BEREIT**, läuft ein Countdown von 4 s, dann wird
  alles auf einmal getauscht und gespeichert. Jede Änderung nimmt BEREIT bei beiden zurück (niemand kann im letzten
  Moment etwas austauschen); Abbruch per Knopf, Moduswechsel oder Verlassen – angebotene Skins sind dann sofort
  wieder frei
- **Agenten**: 9 Stück mit Passiv, je 2 wählbare Primärwaffen, Fähigkeit (Q) und Gadget (G), Level + Skins
- **Rückenwaffe im Hub** (`src/server-shared/BackWeapon.lua`): Im Hub trägt jeder Spieler die Standardwaffe seines
  Agenten auf dem Rücken – flach am Rücken, Lauf schräg über die rechte Schulter, mit Skin und Aufsätzen, für alle
  sichtbar. Wechselt man Agent, Waffe, Skin oder Aufsätze, hängt sofort die neue Waffe dort; in den Kampfmodi
  (Waffe in der Hand) und nach dem Tod ist sie weg
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
- **Map-Abstimmung** (`src/client/MapVote.lua`): eigener Vollbild-Screen mit undurchsichtigem Hintergrund über
  dem ganzen HUD (Minimap, VERLASSEN, Fähigkeiten, Killstreaks, Geld, Tastenzeile, Statuszeile sind solange
  verdeckt). Oben Modus, Titel, Restzeit mit schrumpfendem Balken; drei große Karten mit **Vorschaubild**: die
  echte Map-Geometrie schräg von oben in einem ViewportFrame (Licht je Map-Stimmung, ferne Deko wie Planeten
  bleibt weg), darüber Name, Stimmen, Stimmenbalken und DEINE WAHL. Die Vorschau wird beim ersten Mal über
  mehrere Bilder verteilt kopiert und für spätere Abstimmungen behalten (höchstens 6 Maps). Wählen per Klick,
  1/2/3, Steuerkreuz + A oder Antippen. Unten links ein eigenes VERLASSEN (gleicher Knopf wie im HUD,
  `src/shared/LeaveButton.lua`: zweimal klicken)
- **Respawn-Modi** (Herrschaft, Wingman mit Tickets): nach dem Tod kurz die Todeskamera, dann zurück in die
  Auswahl (Agent, Primärwaffe, Ausrüstung kaufen); BEREIT bringt einen zurück (frühestens nach 3 s, spätestens
  nach 9 s). Rüstung und Extra-Gadget gelten bis zum nächsten Tod. Wer während Herrschaft dazukommt, wählt kurz
  und steigt sofort ein
- **Unendliche Reserve-Munition in allen Modi** (nachladen muss man trotzdem; `WeaponConfig.InfiniteAmmoEverywhere`)
- **Level im Match** (außer in Menüs): Prestige-Abzeichen, Level und XP-Balken unten links; im Hub steht das Level
  groß auf der Spielerkarte
- **Battle Pass, tägliche Aufträge, Shop, Codes**
- **Map-Rotation** pro Match, Todeskamera, Schnelles Spiel
- **Meldungen im Stil von Call of Duty** (eigene Ebene über HUD und Menüs, mit Klang):
  - Medaillen im unteren Drittel (mit Abstand zum Fadenkreuz): Abzeichen mit Symbol schlägt ein, Blitz-Ring,
    großer Titel mit Glanz, seitliche Linien, darunter Bonus-XP, Münzen und weitere Medaillen desselben Kills als
    kleine Schilder; Farbe und Größe nach Stufe (weiß, Bernstein, Orange mit Strahlen, Rot). Mehrfach-Kills innerhalb von 4 s
    (DOPPEL-, TRIPLE-, FURY-, FRENZY-, SUPER-, MEGA-, ULTRA-KILL, KILL-KETTE) ersetzen sich sofort,
    Killserien ohne Tod (3 KILLSERIE, 5 GNADENLOS, 10 UNAUFHALTSAM, 15 LEGENDÄR, 20 GÖTTLICH, 25 NUKLEAR,
    30 UNANTASTBAR), ERSTES BLUT, RACHE, SERIE BEENDET, COMEBACK, WEITSCHUSS, KOPFSCHUSS, ACE, CLUTCH,
    BOMBE GELEGT/ENTSCHÄRFT, EINGENOMMEN, GEHACKT und das Ultimate (ÜBERLADUNG). Die Kill-Boni aus
    `RewardConfig` (Münzen für RACHE an Spielern, SERIE BEENDET ab 5 Kills und die Killserien 5/10/15/20)
    stehen direkt in der Medaille statt in einem eigenen Popup
  - Banner im oberen Drittel aus Sicht des Spielers: RUNDE 3 mit Angriff/Verteidigung, Matchpunkt und Stand,
    RUNDE GEWONNEN/VERLOREN mit Grund (Gegnerteam ausgeschaltet, Bombe entschärft, Zeit abgelaufen …),
    in der letzten Runde groß SIEG/NIEDERLAGE, OVERTIME, Map-Wahl; im Free-for-All NEUE RUNDE (Sieger und
    Platz zeigt dort die Top-3-Bühne mit Zusammenfassung)
  - Ziel-Meldungen unter dem Punktestand in Team-, Gegner- oder Warnfarbe (FLAGGE A EINGENOMMEN/VERLOREN,
    BOMBE BEI A GELEGT · ENTSCHÄRFEN!, SEITENWECHSEL, LETZTER ÜBERLEBENDER · 1 GEGEN 3)
  - Level-Aufstieg (Spieler und Agent), Battle-Pass-Stufe, Prestige und alle Belohnungen (Level-Meilensteine,
    Meisterschaft, neue Titel, Wochen-Bonus, Saison-Ende) als Karte, die links hereinfährt – Farbe nach
    Seltenheit, Zahl im Abzeichen; Level-Aufstieg und die Münzen dafür kommen als eine Karte. Die Karten liegen
    über Menüs und Match-Zusammenfassung. XP stehen rechts neben dem Fadenkreuz
- **Auto-Bots** füllen leere Plätze (auch allein spielbar), Bot-Schwierigkeit im Admin-Panel. Bot-Körper werden
  einmal pro Farbe gebaut und dann geklont; ein abgebrochener oder überholter Spawn baut kein zweites Modell,
  und Modelle ohne gültigen Bot räumt der BotService nach spätestens 2 s weg (keine „Bot-Massen“ mehr).
  Tote Bots fallen als Ragdoll um (Gelenke – Motor6D oder AnimationConstraint – werden durch Kugelgelenke
  ersetzt) und sind nach gut 2 s ausgeblendet, statt steif als „leeres“ Gegner-Modell stehen zu bleiben; der Tod
  zählt auch, wenn nur das Leben auf 0 fällt, und die Bot-KI startet nach einem Fehler neu, statt den Bot
  stehen zu lassen
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
  - rechts in der Mitte (Herrschaft): Killstreaks (`src/client/KillstreakHUD.lua`) – oben die Killserie dieses
    Lebens als große Zahl (springt bei jedem Kill auf) und die nächste Belohnung („LUFTSCHLAG IN 2 KILLS“),
    darunter je Belohnung eine Karte mit gezeichnetem Symbol (Drohne, Jet, Schild), Name und einem Segment pro
    nötigem Kill. Wird eine bereit, fährt ihre Karte herein, blitzt auf, ein Glanz läuft darüber und das Symbol
    pulsiert, bis man sie auslöst: 4/5/6 (Controller: Steuerkreuz rechts, Touch/Maus: Karte antippen)
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
- **Bewegungs-Check** (`src/server-shared/MovementGuard.lua`): Der Server vergleicht 5-mal pro Sekunde die
  zurückgelegte Strecke jedes Spielers mit dem erlaubten Tempo (waagerecht 62 Studs/s, nach oben 50, dazu ein
  Vorrat von 100 bzw. 40 Studs für Sprint-Stoß und Lag-Spitzen; Fallen ist frei). Wer schneller ist (Speedhack)
  oder springt (Teleport), wird an die letzte gültige Stelle zurückgesetzt, im Server-Log steht eine Warnung.
  Legale Bewegungen (Sprint mit allen Boni, Rutschen, Sprint-Stoß, Fallschirmsprung, Treppen, Klettern, Lag bis
  ca. 1,5 s) liegen darunter. Versetzt der Server einen Charakter selbst, ruft er danach
  `MovementGuard.Teleported(character)` auf (macht `SpawnUtil.Spawn` schon)
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
    Spielern und Bots sichtbar: Charaktere halten die Waffe mit beiden Händen im Schulteranschlag auf
    Schulterhöhe (rechter Ellbogen locker unten, damit die Waffe aus der Schulterkamera zu sehen ist) und zielen
    mit; beim Zielen legen sie die Waffe an wie bei Rogue Company (Visier vor dem rechten Auge, Kopf am Schaft,
    Oberkörper eingedreht und leicht vorgelehnt), Pistolen beidhändig auf Augenhöhe. Die Waffe in der Hand ist
    größer als früher (90 % der Modellgröße statt 70 %). Die Haltung funktioniert mit klassischen
    Motor6D-Gelenken und mit dem „Avatar Joint Upgrade“ von Roblox (AnimationConstraints statt Motor6D, Standard
    bei Spieler-Avataren) – vorher wurden solche Rigs nicht erkannt und die Charaktere hielten die Waffe nur mit
    der Standard-Animation (ein Arm nach vorne)
  - Schlanker Körperbau für alle Charaktere: Spieler-Avatare (R15), Bots, Übungspuppen und die Figuren in den
    Menüs haben schmalere Schultern und einen flacheren Oberkörper (`AgentConfig.BodyScale`, Breite 75 %,
    Tiefe 80 %) – damit sind auch die Trefferflächen etwas schmaler. R6-Avatare lassen sich nicht skalieren und
    bekommen nur eine vereinfachte Haltung: dafür in den Spieleinstellungen (Avatar) R15 einstellen
  - Rückstoß mit Rückkehr, Bloom bei Dauerfeuer, Mündungsfeuer, fliegende Leuchtspuren, Funken/Staub und
    Einschusslöcher, Hülsen; eigene Schüsse erscheinen sofort (ohne Ping-Verzögerung)
  - Treffer-Rückmeldung (`src/shared/HitFeedback.lua`) in Farben je Treffer-Art (Körper weiß, Kopf gold, nur
    Rüstung blau, niedergeschlagen orange, ausgeschaltet rot), in OPTIONEN → TREFFER wählbar:
    - Hitmarker KLASSISCH (X, das kurz aufspringt), IMPULS (Standard: vier Klingen schlagen von außen ein, dazu
      eine Druckwelle; Kopftreffer blitzen mit goldener Raute, ein Kill zündet Blitz, doppelte Welle und vier
      Splitter) oder PRÄZISION (Ring mit vier Strichen wie im Zielfernrohr; ein Kill sprengt den Ring in vier
      Bögen). Jeder Stil hat eigene Treffer-Töne, beim Kill einen aufsteigenden Klang
    - Kombo: schnelle Treffer hintereinander am selben Ziel lassen Hitmarker und Ton ansteigen
    - Schadenszahlen EINZELN (Standard: jeder Treffer eine eigene Zahl, die im Bogen abwechselnd links/rechts
      wegfliegt; Kopftreffer groß und gold mit Raute, Kill groß und rot mit Ruck), STAPELN (eine Zahl pro Ziel
      zählt hoch, jeder Treffer fliegt als „+X“ daneben weg, ein Kill streicht sie rot an) oder AUS
    - dazu rote Treffer-Richtungsbögen und die Kill-Meldung
  - unendliche Reserve-Munition in allen Modi (Anzeige „∞“)

## Steuerung

WASD/Leertaste · Shift Sprint · STRG/C Ducken (im Sprint: Slide) · Springen vor Kanten: Klettern ·
Linksklick Schießen · Rechtsklick Zielen · R Nachladen · 1/2 Waffe · V Messer · Q Fähigkeit ·
G Gadget · F Ultimate · E Wiederbeleben/Bombe · Z Ping · T Kamera (Ego/Schulter) · X Schulter wechseln · Tab Punkte ·
M Menü (im Hub; im Match: VERLASSEN-Knopf unter der Minimap) · P Admin-Panel · 4/5/6 Killstreaks (Herrschaft)

Im Hub und im Markt: E am Pult dreht das Glücksrad, E am Stand beansprucht/verwaltet/öffnet ihn,
G an einem anderen Spieler (gedrückt halten) schickt eine Tausch-Anfrage, E an der Shop-Theke öffnet den Shop

## Wo stelle ich was ein?

| Was | Datei |
|---|---|
| Waffen (Schaden, Feuerrate, Streuung/Bloom, Rückstoß, Sounds, unendliche Munition je Modus) | `src/shared/WeaponConfig.lua` |
| Waffenmodelle, Kimme/Korn, Rotpunkt, Handpositionen | `src/shared/GunModels.lua` |
| Nachlade- und Schuss-Animationen | `src/shared/WeaponAnimations.lua` |
| Fadenkreuz, Treffer-Richtung, Kill-Meldung | `src/shared/CombatHUD.lua` |
| Hitmarker- und Schadenszahl-Stile, Farben je Treffer-Art, Treffer-Töne (`HitFeedback.Sounds`), Kombo | `src/shared/HitFeedback.lua` |
| Persönliche Einstellungen (OPTIONEN: Liste, Standardwerte, Karten) | `src/shared/PlayerSettings.lua` |
| Medaillen (Name, Stufe, Bonus-XP) | `src/shared/Medals.lua`; Auslöser (Mehrfach-Kill-Fenster, Weitschuss, Comeback, Serie beendet) oben in `src/server-shared/KillService.lua`, Münzen der Kill-Boni in `src/shared/RewardConfig.lua` |
| Meldungen (Medaillen, Banner, Ziel-Meldungen, Level-Karte: Position, Standzeit, Farben, Klang) | `src/shared/Notifications.lua` |
| Third-Person-Haltung (Schulteranschlag, Ellbogen) und Anlegen beim Zielen | `HIP_POCKET`, `RIGHT_POLE*`, `ADS_*` in `src/shared/CharacterPose.lua` |
| Größe der Waffe in der Hand (Third-Person) | `GunModels.ToolScale` in `src/shared/GunModels.lua` |
| Körperbau aller Charaktere (Breite/Tiefe) | `AgentConfig.BodyScale` in `src/shared/AgentConfig.lua` |
| Design (Farben, Schriften, Knöpfe, Flächen, HUD-Flächen) | `src/shared/UITheme.lua` |
| Lobby (Navigation, Seiten SPIELEN und AGENTEN, Modi, Squad, SPIELEN-Knopf) | `src/shared/GameMenu.lua` |
| Lobby-Seiten LOADOUT, SHOP, BATTLE PASS | `src/shared/LobbyPages.lua` |
| Fenster (Statistik, Codes, Optionen, Aufträge, Täglich, Squad) und Hub-Menüliste | `src/client/SideMenu.lua` |
| Match-HUD (Punktestand, Killfeed, Leben, Munition, Zielmarker) | `src/shared/MatchHUD.lua`, Anordnung und Größe der Munitionsanzeige (`AMMO_SCALE`) in `src/shared/HUD.lua` |
| Fähigkeits-Zeilen (Fähigkeit, Gadget, Ultimate) | `src/shared/AbilityClient.lua`, Ultimate-Werte in `AgentConfig.Ultimate` |
| VERLASSEN-Knopf (Bestätigungszeit) | `CONFIRM_TIME` in `src/shared/LeaveButton.lua` |
| Licht und Farbkorrektur der Welt | `Lighting` in `default.project.json` |
| Team-Uniformfarben (je Modus eindeutig) | `Teams` in `src/server/Modes/*.lua` |
| Schulterkamera (Versatz, Abstand, beim Zielen) | `SHOULDER_*` in `src/shared/Movement.lua` |
| Minimap (Farben, Zoom) | `src/shared/Minimap.lua`, Zuschnitt auf den Kreis in `src/shared/MinimapShapes.lua` |
| Ziel-Text und Zielmarker je Modus | `Goal` / `Objectives` in `src/shared/Modes.lua` |
| Agenten (Leben, Tempo, Waffen, Fähigkeit, Gadget), Level | `src/shared/AgentConfig.lua` |
| Kaufphase, Geld, Perks | `src/shared/BuyConfig.lua` |
| Agentenwahl (Aufbau) und Hangar-Hintergrund | `src/client/AgentSelect.lua`, `src/shared/HangarScene.lua` |
| Map-Abstimmung: Kartengröße, Vorschau-Kamera (`PREVIEW_YAW/PITCH/FOV/ZOOM`), Farbstimmung je Map (`MOODS`) | `src/client/MapVote.lua` |
| Respawn-Auswahl (Dauer, frühestes BEREIT), Pause nach dem Match | `RESPAWN_SELECT_TIME`, `RESPAWN_MIN_TIME`, `SUMMARY_TIME` in `src/server/TeamRoundMode.lua` |
| Skins und Preise im Shop | `src/shared/Cosmetics.lua` |
| RAP: Werte der handelbaren Skins, Rückkaufquote, Marktgebühr, Plätze pro Stand, Tausch (Countdown, Reichweite), Farbstufen über dem Kopf | `src/shared/RapConfig.lua` |
| Markt-Stände (Reichweite zum Beanspruchen/Kaufen) | `ClaimRange`, `BuyRange` in `src/server-shared/MarketService.lua`; Halle in `build_market()` in `tools/build_maps.py` |
| Glücksrad: Felder, Gewichte, Farben | `LoginConfig.Wheel` in `src/shared/LoginConfig.lua`; Dreh-Dauer und Runden in `src/client/HubWheel.lua` |
| Killstreaks (Kills, Namen, Farben) | `src/shared/KillstreakConfig.lua`; Anzeige in `src/client/KillstreakHUD.lua` |
| Battle Pass | `src/shared/PassConfig.lua` |
| Tägliche Aufträge | `src/shared/QuestConfig.lua` |
| Ränge (Ranked) | `src/shared/RankConfig.lua` |
| Live-Einstellungen (auch im Admin-Panel) | `src/shared/GameSettings.lua` |
| Modi im Menü | `src/shared/Modes.lua` |
| Rückenwaffe im Hub (Größe `SCALE`, Neigung `TILT`, Abstand zum Rücken) | `src/server-shared/BackWeapon.lua` |
| Bewegungs-Check (erlaubtes Tempo, Vorrat) | `FLAT_*`, `UP_*` in `src/server-shared/MovementGuard.lua` |
| Admins | `ADMIN_IDS` in `src/server/AdminService.lua` |
| Codes | `CODES` in `src/server-shared/ShopService.lua` |

## Speichern

XP, Münzen, Skins, Rangpunkte, Battle Pass und Aufträge liegen im DataStore. Das funktioniert erst,
wenn das Spiel veröffentlicht ist und in Studio "Enable Studio Access to API Services" an ist –
vorher gilt alles nur für die Sitzung.

Schutz der Spielstände (`src/server-shared/SessionStore.lua`, genutzt von `ProgressService`):
- **Sitzungssperre:** Jeder Server sperrt die Profile seiner Spieler (Feld `Session` im gespeicherten Profil, beim
  Autosave alle 2 Minuten erneuert) und speichert nur, solange er die Sperre hält (`UpdateAsync`). Nach einem
  schnellen Serverwechsel kann der alte Server so keinen neueren Stand überschreiben; der neue Server wartet, bis
  der alte beim Verlassen gespeichert und freigegeben hat. Hängt die Sperre an einem abgestürzten Server, wird sie
  nach 20 s übernommen (eine 5 Minuten lang nicht erneuerte sofort).
- **Wiederholungen:** DataStore-Fehler werden bis zu 4-mal mit wachsender Pause wiederholt. Lässt sich ein Profil
  gar nicht laden, wird der Spieler im Live-Spiel mit Hinweis gekickt – sonst spielte er ohne Speichern weiter.
- **Herunterfahren:** alle Spieler werden gleichzeitig gespeichert und freigegeben (höchstens 25 s).
- **Robux-Käufe** (`RobuxService`): Ein Kauf wird Roblox erst bestätigt, wenn der Stand mit dem Kauf sicher
  gespeichert ist; sonst fragt Roblox später erneut (jede Kauf-Nummer wird trotzdem nur einmal gutgeschrieben).

## Tests und automatische Prüfung

Bei jedem Push (und bei Pull Requests) prüft GitHub Actions den Stand automatisch
(`.github/workflows/checks.yml`). Das Ergebnis steht auf GitHub unter **Actions** und als Haken bzw. rotes Kreuz
am Commit:
1. **Statische Analyse** aller Skripte mit [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) und den
   Roblox-Typen. Typ- und Syntaxfehler lassen die Prüfung scheitern, Stil-Warnungen (z. B. unbenutzte Variablen)
   stehen nur im Log.
2. **Tests** (`tests/*.test.luau`) im normalen Luau-Interpreter, ohne Roblox. `tests/lib/engine.luau` bildet die
   nötigen Teile von Roblox nach (Zeit und `task`, Instanzen, Spieler, DataStores, Remotes, ...), `tests/run.py`
   bündelt jeden Test mit allen Modulen des Projekts unter denselben Pfaden wie in Studio.

| Test | prüft |
|---|---|
| `weapons` | Arm-IK (PoseMath), Visierlinien aller Waffen, Nachlade-Animationen, Waffenwerte |
| `pose`, `pose_r6`, `rig` | Third-Person-Haltung: Waffe im Anschlag, Hände an der Waffe; Gelenk-Erkennung (Motor6D und Avatar Joint Upgrade), R6 |
| `viewmodel` | Ego-Waffe: Kimme und Korn beim Zielen genau in der Bildmitte |
| `minimap`, `modes` | Minimap-Zuschnitt auf den Kreis, Modus-Liste |
| `session` | Sitzungssperre der Spielstände (Serverwechsel, Absturz, DataStore-Fehler) |
| `progress` | Spielstand laden/speichern mit Sperre, Robux-Käufe erst nach dem Speichern bestätigt, Kick bei Ladefehler, Speichern beim Herunterfahren |
| `medals` | Medaillen im KillService (Mehrfach-Kill, Serien, Rache, Weitschuss, ...), mit beiden Signal-Modi von Roblox |
| `backweapon` | Rückenwaffe im Hub: Lage hinter dem Rücken für alle Primärwaffen, folgt Agent, Waffenwahl und Skin, weg im Kampfmodus und beim Tod |
| `settings`, `hitfeedback` | Einstellungen speichern (auch AUS-Werte), Stilwahl; alle Hitmarker- und Schadenszahl-Stile laufen durch und räumen auf, Kombo-Ton, Vorschau |
| `movement` | Bewegungs-Check: legale Bewegungen (Sprint, Sprint-Stoß, Fallschirm, Lag) nie zurückgesetzt, Speedhacks und Teleports schon |
| `economy` | RAP: alte Spielstände, Stückzahlen und Duplikate, Rückverkauf ans System (Skin weg und abgelegt, RAP drauf, gespeichert), Reservierungen, Austausch mit Marktgebühr (alles oder nichts) |
| `market` | Markt: Stand beanspruchen (Markt, Nähe, einer pro Spieler), anbieten (handelbar, freie Stücke, höchstens sechs), Preis ändern, kaufen (Nähe, gesehener Preis, RAP, Gebühr, gespeichert), Stand frei beim Verlassen |
| `trade` | Tauschen: Anfrage (Hub/Markt, Nähe), ablehnen, ablaufen, annehmen, gegenseitig, Angebote, BEREIT + Countdown, Änderung nimmt BEREIT zurück, Abschluss gespeichert, Abbruch bei Knopf/Moduswechsel/Verlassen, fehlgeschlagener Tausch ändert nichts |
| `wheel` | Glücksrad: Rad hält auf dem ausgelosten Feld (alle Felder, mit Versatz), Dreiecke aus Keilen, Aufbau und Drehrichtung, Drehen nur im Hub am Rad |

Selbst ausführen (Python 3 und der Luau-Interpreter `luau` aus den
[Luau-Releases](https://github.com/luau-lang/luau/releases) werden gebraucht):

    python3 tests/run.py                  # alle Tests
    python3 tests/run.py movement         # nur bestimmte Tests
    python3 tests/run.py --keep build/tests   # gebündelte Dateien zum Nachsehen behalten

Neuer Test: Datei `tests/name.test.luau` anlegen. Module lädt `require("Name")`, die Nachbildung steht unter `SIM`
(z. B. `SIM.AddPlayer`, `SIM.Run`/`SIM.Advance` für die Zeit, `SIM.Stub` für Attrappen anderer Module,
`SIM.DataStore`, `SIM.RemoteLog`). Ein Test schlägt fehl, wenn er mit einem Fehler abbricht oder eine Zeile mit
`FEHLER` ausgibt.

## Ordner

- `src/shared` – Client + Server: Konfigurationen, Waffen-Client (ViewModel = Ego-Waffe, CharacterPose =
  Third-Person-Haltung, WeaponEffects = Schuss-Effekte), HUD (MatchHUD, Minimap, CombatHUD, HUDIcons =
  Porträts/Waffen-Silhouetten, TeamCheck = wer ist Freund/Feind, Notifications + Medals = Meldungen im
  CoD-Stil), Menü, Bewegung, RapConfig (RAP-Werte), ItemPreview (3D-Vorschau eines Skins)
- `src/server-shared` – Server-Dienste: Schaden, Kills, Agenten, Fortschritt, Shop, Gadgets, Perks, Pings,
  EconomyService (RAP, Rückverkauf, Reservierungen), MarketService (Stände), TradeService (Tauschen)
- `src/server` – Modus-Verwaltung, Team-Runden-Logik, Modi (inkl. Hub und Markt), Bots, Admin
- `src/client` – Agentenwahl, Seitenleiste, Admin-Panel, Scoreboard, Gleiten, Zuschauen, HubWheel (Glücksrad),
  MarketClient (Markt), TradeClient (Tauschen), KillstreakHUD, ...
- `src/maps` – generierte Maps (nicht von Hand bearbeiten)
- `tools/build_maps.py` – erzeugt alle Maps
- `tools/sourcemap.py` – Sourcemap für luau-lsp (wie `rojo sourcemap`, ohne Rojo)
- `tests` – Tests und Roblox-Nachbildung (`tests/run.py` startet sie), `.github/workflows` – automatische Prüfung

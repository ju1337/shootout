# Shootout

Roblox-Shooter im Stil von Rogue Company. Alles läuft in **einem** Place: Hub, Modi und Training
sind eigene Bereiche der Welt, Moduswechsel funktionieren deshalb auch direkt in Studio.

## Entwickeln

    ./rojo serve                           # dann in Studio: Rojo → Connect
    ./rojo build -o build/shootout.rbxlx   # fertige Place-Datei bauen
    python3 tools/build_maps.py            # Maps neu erzeugen (nach Änderungen am Map-Skript)
    python3 tools/weapon_templates.py      # Blender-Vorlagen der Waffen neu erzeugen (art/templates/Weapons)

3D-Modelle für die Waffen kommen aus Blender: Anleitung und Spezifikation in [docs/waffen-modelle.md](docs/waffen-modelle.md).

## Modi

| Modus | Kurz | Map |
|---|---|---|
| Hub | Kompakte Einsatzzentrale: an der Nordwand nur noch das große Tor nach EXTINCTION (Tafeln SAFE ZONE / DRAUSSEN links und rechts, Banner ARCADE darüber), Kartentisch mit Einsatz-Tafel, Bühne mit eigenem Agenten, Wand der Bestenlisten + Top-3-Statuen. Alter Hangar: `HUB_STYLE = "classic"` in `tools/build_maps.py` (fertig auch in `tools/saved/Hub_classic.model.json`) | Hub (0, 0, 0) |
| **EXTINCTION** (Hauptmodus) | Offene Welt mit Safe Zone, Inventar, Lager, Ständen, PvP draußen – siehe [Extinction](#extinction-offene-welt) | Ödland (0, 0, -6000), 1800 × 1800 |
| Markt | Handelshalle ohne Kampf: Stände beanspruchen, Skins für RAP anbieten und kaufen (Tor MARKT im Hub, Knopf MARKT im Seitenmenü) | Markthalle (-1500, 0, -1500) |
| Free-for-All (Arcade) | jeder gegen jeden, Respawn | Raffinerie (0, 0, 1500) |
| Herrschaft (Arcade) | 5v5, Flaggen A/B/C halten, unbegrenzter Respawn, 200 Punkte gewinnen | Tal (1500, 0, 0) |
| Wingman (Arcade) | 2v2, Punkt halten, Respawn-Tickets | Rotation: Fabrik / Hochhaus / Gletscher / Zellenblock / Kanäle / Windmühlen |
| 1v1 Arena (Arcade) | Duell | Arena (0, 0, 3000) |
| Training (Arcade) | Schießstand mit Übungspuppen | (-1500, 0, 1500) |

Die Minispiele haben kein Tor mehr im Hub: Man startet sie im Menü (M) unter **ARCADE** (dort auch SCHNELLES
SPIEL = vollster Arcade-Modus mit freiem Platz). Oben im Menü steht groß EXTINCTION und ist vorgewählt
(`Featured` / `Arcade` in `src/shared/Modes.lua`).

ELO gibt es in jedem Modus (kein eigenes Ranked-Matchmaking). Ausgebaute Modi (Drop, Strikeout, Demolition,
Ranked, Extraction, TDM) stehen in `Modes.Disabled`; ihr Code liegt noch in `src/server/Modes/`.

Team-Modi teilen sich die Logik in `src/server/TeamRoundMode.lua` (Agentenwahl, Kaufphase,
Niederschlagen/Wiederbeleben, Bots). Ein neuer Team-Modus ist eine kurze Konfiguration in
`src/server/Modes/`, eigene Ziele (z.B. die Bombe) liegen in `src/server/Objectives/`.

## Extinction (offene Welt)

Vorbild: Überlebens-Server wie „GLife Extinction“. Man geht im Hub durch das große Tor und landet in der
**Safe Zone** „Camp Phoenix“ in der Mitte der Welt (Map `Extinction`, erzeugt von `build_extinction()` in
`tools/build_maps.py`: Straßenkreuz und Ringstraße, Kleinstadt im Osten, Tankstelle, Bauernhof, Militärbasis,
Industrie, See, Wald und Felsen am Rand).

- **Safe Zone** (grüner Ring, Radius 100): kein Schaden, Waffen bleiben gesichert (Taste zieht keine Waffe,
  beim Betreten wird sie weggesteckt). Dort stehen der **Waffenstand**, der **Itemstand**, der
  **Fahrzeugstand**, das **Lager** und das Tor zurück zum Hub (E an Stand/Lager).
- **Draußen**: sofort schießen auf Zombies möglich, **PvP erst 5 Sekunden nach dem Verlassen** (Anzeige oben:
  SAFE ZONE · PVP IN 3 S · PVP AKTIV). Schaden zwischen Spielern nur, wenn beide ihre PvP-Zeit haben.
- **Keine Standardwaffen**: Alles kommt aus der Tasche. **TAB** öffnet das Inventar: 30 Plätze, davon 1-9 die
  Hotbar (Tasten **1-9**). Items ziehen und ablegen oder anklicken und den Zielplatz anklicken, Rechtsklick legt
  zwischen Hotbar und Tasche hin und her. Waffe: Taste zieht sie (nochmal = wegstecken), Heilung/Rüstung: Taste
  benutzt sie (dauert ein paar Sekunden, dabei kein Schuss).
- **Munition** kaufen oder finden: Nachladen nimmt Schuss aus der Tasche (9mm, Magnum, Schrot, Gewehr), das
  Magazin bleibt am Item gespeichert. Ohne passende Munition kein Nachladen.
- **Stände**: kaufen mit Münzen (Munition auch ×5), verkaufen an jedem Stand für 40 % des Preises.
- **Lager**: 40 Plätze, immer sicher (auch beim Tod).
- **Tod draußen**: die ganze Tasche fällt als **Tasche am Boden** (5 Minuten, jeder kann sie mit E durchsuchen und
  Items oder ALLES nehmen), Respawn nach 5 s in der Safe Zone. Spieler-Kill: +120 Münzen Kopfgeld (dazu der
  normale Kill-Lohn).
- **Verlassen**: in der Safe Zone bleibt alles genau so angeordnet in der Tasche (gespeichert im Profil). Draußen
  kostet Verlassen die Tasche (im Menü erst nach einem zweiten Klick, beim Spiel-Verlassen sofort vor dem
  Speichern); fährt der Server herunter, verliert niemand etwas.
- **Agenten**: nur passive Fähigkeiten (keine Q/G/F), Leben und Tempo wie sonst.

Code: `src/server/Modes/Extinction.lua` (Safe Zone, PvP, Tod/Verlassen), `src/server-shared/InventoryService.lua`
(Tasche, Hotbar, Lager, Stände, Benutzen), `src/server-shared/LootService.lua` (Taschen am Boden),
`src/shared/Inventory.lua` (Regeln für Plätze und Stapel), `src/client/ExtinctionClient.lua` (HUD, Fenster),
Werte in `src/shared/ExtinctionConfig.lua`.

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
- **Agent der Woche** (Hub-Mitte, `src/client/HubLineup.lua`): goldene Statue des Agenten der Woche dreht sich
  auf dem Sockel, darüber schwebt eine Holo-Schrift (Name, Rolle, +50 % XP, diese Woche gratis). Kommt die Kamera
  nah heran (rausgezoomt neben der Statue, steil von oben), blendet die Schrift weich aus (ab 16 Studs, unter 9
  ganz weg), statt riesig vor dem Bild zu hängen
- **Glücksrad im Hub** (`src/client/HubWheel.lua`, in der Ecke links vom Spawn am Ende eines eigenen Teppichs, schräg zur Hallenmitte gedreht): großes Rad mit acht
  Feldern (`LoginConfig.Wheel`), Rand mit Lichtern und Zeiger oben; Podest, Ständer, Schild und Pult kommen aus
  der Map, das drehende Rad baut der Client an `WheelSpot`. Am Pult **E** (Controller □, Touch: Antippen): der Server
  lost das Feld aus, das Rad dreht ein paar Runden, der Zeiger klackt an jedem Steg, die Lichter laufen mit, das
  Rad hält genau auf dem Gewinn, das Feld blinkt und eine Belohnungs-Karte erscheint. Die Tafel am Pult zeigt
  GRATIS-DREH BEREIT, Extra-Drehs oder die Zeit bis zum nächsten Gratis-Dreh. Einmal am Tag gratis, Extra-Drehs aus
  dem Login-Kalender; gedreht wird nur im Hub in der Nähe des Rads (Server prüft). Den Knopf im Seitenmenü gibt
  es nicht mehr
- **RAP – zweite Währung** (`src/shared/RapConfig.lua`, Server `src/server-shared/EconomyService.lua`): RAP bekommt
  man nur über Skins. Jeder handelbare Skin (Waffe oder Agent) hat einen RAP-Wert, **steil gestaffelt wie bei Sniper
  Duels**: gewöhnliche Skins 1-10 RAP (Waldtarn 2, Wüste 3), seltene zweistellig (30-55), epische dreistellig (260-520,
  Battle-Pass-Skin Saison-Neon 2.500), legendäre vier- bis fünfstellig (Lava 3.200 bis Galaxie 8.500, Kalender-Skin
  18.000), Battle-Pass-Goldrausch 35.000, Saison-Agentin 45.000 und die Robux-Skins Royal 90.000 / Hologramm 150.000.
  RAP heißt *Recent Average Price*: Der Wert startet beim Basiswert (`RapConfig.Values`) und rückt nach **jedem Verkauf im
  Markt** ein Zehntel Richtung Verkaufspreis (`RAP + (Preis - RAP) / 10`, begrenzt auf 0,25- bis 8-fach des Basiswerts;
  `RapConfig.NextLive`). Der lebende Wert liegt im DataStore `MarketHistory_v1` (Schlüssel `rap`, gilt für alle Server)
  und kommt als Attribut `RapLive` an ReplicatedStorage zu allen Clients; alle Anzeigen (Shop, Markt, Suche, Tausch, Schild
  über dem Kopf) und die Schnäppchen-Sortierung benutzen ihn. Man kann einen Skin
  - im **SHOP** unter **VERKAUFEN** ans System zurückverkaufen: sofort 70 % des **Basiswerts** (`RapConfig.SellRate`, mindestens 1 RAP; der Rückkauf folgt dem lebenden RAP nicht, damit er sich nicht manipulieren lässt),
    erster Klick fragt nach, zweiter verkauft,
  - im **MARKT** am eigenen Stand zum eigenen Preis anbieten (Marktgebühr nach Preis, `RapConfig.FeeTiers`: 2 % bis 50 RAP, 5 % bis 1.000, 7 % bis 20.000, darüber 10 %; gerundet, winzige Preise zahlen nichts),
  - mit anderen Spielern tauschen.
  Mit dem RAP kauft man im Markt Skins von anderen Spielern. Handelbare Skins kann man mehrfach besitzen
  (Duplikate aus Glücksrad, Login-Kalender, Wochen-Bonus, Robux-Paket oder Markt); gebunden – ohne RAP-Wert –
  bleiben gewöhnliche Skins, Belohnungen für Level, Prestige, Rang und Saison und die Meisterschafts-Tarnungen.
  Angezeigt wird RAP in der Lobby-Kopfzeile (neben den Münzen), auf der Spielerkarte im Hub, als Wert-Schild auf
  den Shop-Karten und **über dem Kopf jedes Spielers** (nur im Hub und im Markt): Guthaben + Wert seiner
  handelbaren Skins, die Farbe zeigt die Stufe (grau, mint ab 100, blau ab 1.000, lila ab 10.000, gold ab
  50.000, rot ab 250.000). Skins, die gerade an einem Stand oder in einem Tausch liegen, bleiben im Inventar,
  lassen sich aber nicht gleichzeitig verkaufen. Alte Spielstände (Besitz = true) zählen als 1 Stück.
  Admin-Panel: **+10.000 RAP** und **Handelbarer Skin** zum Testen
- **Markt** (Theater-Rund mit 48 Ständen; Server `src/server-shared/MarketService.lua` + `src/server/Modes/Market.lua`,
  Client `src/client/MarketClient.lua`, Map `build_market()` in `tools/build_maps.py`): wie die Trading Plaza in
  Sniper Arena / Pet Simulator. Hin über das grüne Tor MARKT an der Ostwand des Hubs oder den Knopf MARKT im
  Seitenmenü (im Markt heißt er ZUM HUB), zurück durchs Tor im Süden der Halle.
  - **Aufbau**: Man spawnt in der Mitte auf dem großen, ruhigen **Marktplatz** (Such-Terminal in der Mitte; am Rand zwei
    Kisten-Automaten, die Übersichtstafel mit freien/belegten Ständen und die Tafel **beliebteste Händler** nach Verkäufen).
    Das Tor zurück zum Hub steht am Ende der Südrampe (oberster Rang); schneller geht es über den Knopf ZUM HUB im Seitenmenü. Darum liegen wie in einem
    Theater drei Ränge, die nach außen stufenweise höher werden (Stände 1-12, 13-28, 29-48); alle Stände zeigen zur Mitte.
    Vier Rampen (Norden, Osten, Süden, Westen) führen über alle Ränge nach oben, die Stufen kann man auch springen.
  - **SUCHE** (Knopf oben oder E am Such-Terminal, Logik in `src/shared/MarketSearch.lua`): alle Angebote aller Stände
    durchsuchen (Skin, Seltenheit, Besitzer, Stand), filtern nach Seltenheit, Waffen/Agenten, nur Bezahlbares oder
    Merkliste, sortieren nach Preis, **Schnäppchen** (am weitesten unter dem RAP-Wert) oder Seltenheit. **HIN** zeigt
    einen Pfeil mit Entfernung über dem Stand.
  - **Preisverlauf**: Durchschnittspreis der Verkäufe der letzten 7 Tage je Skin (DataStore `MarketHistory_v1`,
    gilt für alle Server) steht in Suche, Stand-Fenstern und MEIN STAND.
  - **Merkliste**: MERKEN an einem Skin – bietet jemand ihn an, kommt eine Meldung (im Profil gespeichert).
  - **Gegenangebote**: an fremden Ständen ANGEBOT MACHEN (mindestens der halbe Preis, 45 s gültig, eins pro Stand).
    Der Besitzer sieht sie unter **ANGEBOTE** in der Leiste und nimmt an (Verkauf zum Gebot) oder lehnt ab.
  - **Stand-Name**: in MEIN STAND, erscheint auf dem Schild (läuft durch den Textfilter).
  - **Stand beanspruchen**: an einem freien Stand **E** – man bleibt, wo man steht (kein Teleport), das Schild über dem
    Stand zeigt den eigenen Namen. Einer pro Spieler.
  - **Kisten** (Automaten in der Mitte, Server `src/server-shared/CrateService.lua`, Client `src/client/CrateClient.lua`,
    Chancen und Preise in `src/shared/CrateConfig.lua`): **WAFFEN-KISTE** (450 Münzen) und **AGENTEN-KISTE** (800 Münzen),
    getrennt. E am Automaten öffnet das Fenster: Chancen je Seltenheit, alle Skins der Kiste, ÖFFNEN lässt die Rolle
    laufen und zeigt den Gewinn. Gezogen wird aus den im Shop kaufbaren Skins der jeweiligen Art. Schon besessene
    gebundene Skins geben 30 % ihres Shop-Preises als Münzen zurück; handelbare Skins (mit RAP-Wert) landen als weiteres
    Stück im Inventar und lassen sich im Markt verkaufen. Der Server würfelt und bucht, die Rolle ist nur die Show.
  - **MEIN STAND** (E am eigenen Stand oder Knopf in der Markt-Leiste oben): links sechs Plätze (Preis ändern,
    ZURÜCK nimmt das Angebot zurück), rechts die eigenen handelbaren Skins mit Preisfeld (Vorschlag: RAP-Wert)
    und ANBIETEN. Angebotene Skins drehen sich auf Theke und Regal, darüber ein Preisschild.
  - **Kaufen**: E an einem fremden Stand öffnet seine Angebote (Preis, RAP-Wert, wie viel darüber/darunter);
    KAUFEN zweimal klicken. Bezahlt wird mit RAP, die Marktgebühr (nach Preis gestaffelt) geht beim Verkäufer ab; beide Spielstände
    werden sofort gespeichert, der Verkäufer bekommt eine Meldung. Der Server prüft Nähe zum Stand, ob der
    angezeigte Preis noch stimmt und ob genug RAP da ist.
  - **Stand weg**: Wer den Markt verlässt (in eine Runde, in den Hub, Spiel verlassen) oder ABGEBEN drückt, verliert
    den Stand – die angebotenen Skins waren nur zurückgelegt und sind sofort wieder frei im Inventar, jemand anderes
    kann den Stand nehmen. Squads werden nicht mit in den Markt gezogen
- **Tauschen** (Server `src/server-shared/TradeService.lua`, Client `src/client/TradeClient.lua`): im Hub oder im
  Markt die Taste **T** drücken (im Markt auch der Knopf **TAUSCH** oben): Die Spielerliste zeigt alle Spieler im selben
  Bereich mit Entfernung und Inventarwert, **TAUSCH ANFRAGEN** schickt die Anfrage (nah genug herangehen,
  `RapConfig.TradeRange`). Alternativ an einem anderen Spieler **G** halten (Controller △, Touch: Antippen) schickt eine Anfrage; sie erscheint
  rechts als Karte mit ANNEHMEN / ABLEHNEN (20 s gültig, fragen sich beide gegenseitig, geht der Tausch sofort auf).
  Im Tausch-Fenster legt jeder handelbare Skins (**+** aus der eigenen Liste, **-** nimmt wieder raus) und RAP
  hinein, der RAP-Wert beider Seiten steht oben. Sind beide **BEREIT**, läuft ein Countdown von 4 s, dann wird
  alles auf einmal getauscht und gespeichert. Jede Änderung nimmt BEREIT bei beiden zurück (niemand kann im letzten
  Moment etwas austauschen); Abbruch per Knopf, Moduswechsel oder Verlassen – angebotene Skins sind dann sofort
  wieder frei
- **Agenten**: 9 Stück mit Passiv, je 2 wählbare Primärwaffen, Fähigkeit (Q) und Gadget (G), Level + Skins
- **Alle spielen als Agent** (`src/server-shared/AgentBody.lua`, gespawnt über `src/server/SpawnUtil.lua`): Im Hub, im
  Markt und im Match trägt jeder Spieler statt seines Roblox-Avatars denselben schlanken R15-Körper in den Farben
  seines Agenten bzw. Agenten-Skins, mit Kapuze, Maske, getöntem Visier, Weste, Schulterpolstern und Gürtel wie die
  Menü-Figur. Bots tragen genau denselben Körper in den Standardfarben ihres Agenten (keine Teamfarben mehr – das
  Team erkennt man wie bei Spielern am Namensschild), die Übungspuppen haben dieselben Trefferzonen. Im Hub und im
  Markt sieht man einen Agenten- oder Skin-Wechsel sofort, im Match ab dem nächsten Spawn. Das ist der Übergang,
  bis die eigenen Agenten-Modelle aus Blender da sind
- **Gleiche Trefferzonen für alle**: Getroffen werden nur Körperteile. Accessoires (auch später angehängte) und die
  Ausrüstung sind für Schüsse unsichtbar (`CanQuery = false`); der Server nimmt auch vom Client gemeldete Treffer
  nur auf treffbaren Teilen an
- **Waffenmodelle aus Blender** (`src/shared/GunModels.lua`, Anleitung [docs/waffen-modelle.md](docs/waffen-modelle.md)):
  Liegt in Studio unter ReplicatedStorage › Assets › Weapons ein Modell mit dem Namen einer Waffe, ersetzt es die
  Quader-Waffe überall (Ego-Waffe, Hand, Rücken, Vorschauen, Symbole). Marker im Modell legen Griff, Visierlinie,
  Mündung, Hülsenauswurf, Hände und Schaft fest – wie das Modell beim Import gedreht ist, ist egal. Teilnamen
  bestimmen Animationsgruppen, Skin-Zonen, Leuchtpunkte und Glas; epische/legendäre Skins können eigene Texturen
  bekommen (Ordner `Skins`). Fehlt etwas, bleibt die Quader-Waffe und Studio sagt im Output, was fehlt. Vorlagen
  für Blender (`.obj`) und Studio (`.rbxmx`) in `art/templates/Weapons`
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
  - Schlanker Körperbau für alle Charaktere: Spieler, Bots, Übungspuppen und die Figuren in den Menüs haben
    schmalere Schultern und einen flacheren Oberkörper (`AgentConfig.BodyScale`, Breite 75 %, Tiefe 80 %) – damit
    sind auch die Trefferflächen etwas schmaler. R6-Körper lassen sich nicht skalieren und bekommen nur eine
    vereinfachte Haltung: dafür in den Spieleinstellungen (Avatar) R15 einstellen
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
  - unendliche Reserve-Munition in allen Arcade-Modi (Anzeige „∞“), in EXTINCTION Munition aus dem Inventar

## Steuerung

WASD/Leertaste · Shift Sprint · STRG/C Ducken (im Sprint: Slide) · Springen vor Kanten: Klettern ·
Linksklick Schießen · Rechtsklick Zielen · R Nachladen · 1/2 Waffe · V Messer · Q Fähigkeit ·
G Gadget · F Ultimate · E Wiederbeleben/Bombe · Z Ping · T Kamera (Ego/Schulter) · X Schulter wechseln · Tab Punkte ·
M Menü (im Hub; im Match: VERLASSEN-Knopf unter der Minimap) · P Admin-Panel · 4/5/6 Killstreaks (Herrschaft)

In EXTINCTION: 1-9 Hotbar benutzen · TAB Inventar · E Stand/Lager/Tasche · K Fahrzeug einpacken ·
Controller: R1/L1 Waffe der Hotbar wechseln, Select Inventar, △ Fahrzeug einpacken

Im Hub und im Markt: T öffnet die Tausch-Spielerliste, E am Pult dreht das Glücksrad, E am Stand beansprucht/verwaltet/öffnet ihn,
G an einem anderen Spieler (gedrückt halten) schickt eine Tausch-Anfrage, E an der Shop-Theke öffnet den Shop

## Wo stelle ich was ein?

| Was | Datei |
|---|---|
| Waffen (Schaden, Feuerrate, Streuung/Bloom, Rückstoß, Sounds, unendliche Munition je Modus) | `src/shared/WeaponConfig.lua` |
| EXTINCTION: Items, Preise, Stände, Plätze, PvP-Zeit, Taschen, Zombies, Fahrzeuge, Belohnungen | `src/shared/ExtinctionConfig.lua` |
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
| Agenten-Körper: Ausrüstung (Kapuze, Visier, Weste …), Hautfarbe, Körper-Beschreibung | `src/server-shared/AgentBody.lua` |
| Waffenmodelle (Blender): Marker, Teilnamen, Skins, Prüfungen | `docs/waffen-modelle.md`; Lader in `src/shared/GunModels.lua` |
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
| Kisten: Preise, Chancen (Gewichte je Seltenheit), Duplikat-Rückgabe, Wartezeit | `src/shared/CrateConfig.lua` |
| Markt: Gebührenstufen, Gegenangebote (Mindestgebot, Dauer), Stand-Name, Merkliste, Preisverlauf | `FeeTiers`, `MinOfferFraction`, `OfferSeconds`, `StandNameLength`, `WatchLimit`, `HistoryDays` in `src/shared/RapConfig.lua` |
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
| `maps` (tests/maps_check.py) | Markt-Karte: Teile, die Server und Client suchen (Such-Terminal, Kisten-Automaten, Tafeln, Portal), Spawns auf dem Platz, Stände lückenlos mit Prompt und Ausstellplätzen, alle zur Mitte gerichtet, nicht zu dicht, drei Ränge |
| `tradeui` | Tausch-Oberfläche: Spielerliste mit T, Entfernung, Anfrage, zu weit weg gesperrt, Hinweis nur im Hub/Markt, Esc schließt |
| `crate`, `crateui` | Kisten: getrennte Pools (Waffen/Agenten, alle handelbar), steile Chancen (Waffen 62/28/8/2 %, Agenten 75/20/5 %), Öffnen (Ort, Münzen, Wartezeit), weitere Stücke, Rolle mit dem Gewinn an festem Platz; Fenster mit Rolle, Gewinn-Karte, NOCHMAL |
| `marketsearch` | Marktsuche: Text (ohne Umlaute, mehrere Wörter), Filter (Seltenheit, Art, Höchstpreis), Sortierung (Preis, Schnäppchen, Seltenheit) |
| `market2` | Markt Teil 2: Gebühr nach Preis, Gegenangebote (annehmen, ablehnen, zurückziehen, Ablauf, Preisänderung), Stand-Name, Merkliste samt Meldung, Preisverlauf, Händler-Rangliste |
| `marketui`, `marketui2` | Markt-Oberfläche im Simulator: Suche, Stand-Fenster, Gegenangebote, MEIN STAND mit Stand-Name, Tafeln |
| `market` | Markt: Stand beanspruchen (Markt, Nähe, einer pro Spieler), anbieten (handelbar, freie Stücke, höchstens sechs), Preis ändern, kaufen (Nähe, gesehener Preis, RAP, Gebühr, gespeichert), Stand frei beim Verlassen |
| `trade` | Tauschen: Anfrage (Hub/Markt, Nähe), ablehnen, ablaufen, annehmen, gegenseitig, Angebote, BEREIT + Countdown, Änderung nimmt BEREIT zurück, Abschluss gespeichert, Abbruch bei Knopf/Moduswechsel/Verlassen, fehlgeschlagener Tausch ändert nichts |
| `hubholo` | Holo-Schrift „Agent der Woche“: hängt über der Statue, bleibt nach dem Respawn, blendet in Kameranähe aus (rausgezoomt daneben, steil von oben), weiter weg voll sichtbar |
| `agentbody` | Agenten-Körper: gleiche Beschreibung für Spieler und Bots, Avatar-Teile weg, Ausrüstung in Agentenfarben, Skin-Wechsel im Hub sofort, Rückfall auf den normalen Charakter; Accessoires und Ausrüstung nie Trefferzone (auch nicht als gemeldeter Treffer) |
| `weaponmodels` | Waffen-Lader: gedreht importierte Modelle werden an den Markern ausgerichtet, Ruhelage, Gruppen, Drehpunkte, Skin-Zonen und Textur-Skins, Aufsätze, Werkzeug, Zielen, Nachladen; kaputte Modelle bleiben mit klarer Meldung Quader |
| `rbxmx`, `templates` | Studio-Dateien (.rbxmx) einlesen; alle Blender-Vorlagen sind selbst gültige Modelle |
| `weaponassets` | deine Modelle in `assets/Weapons` gegen die Spezifikation (laden ohne Fehler, Textur-Skins passen); mit ihnen laufen auch weapons, viewmodel und pose |
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
- `tools/weapon_templates.py` – erzeugt die Blender-Vorlagen der Waffen (`art/templates/Weapons`)
- `docs` – Anleitungen (Waffenmodelle aus Blender)
- `assets/Weapons` – Kopien deiner Waffenmodelle (.rbxmx) für die automatische Prüfung (das Spiel lädt die Modelle
  aus dem Place, siehe docs/waffen-modelle.md)
- `tools/sourcemap.py` – Sourcemap für luau-lsp (wie `rojo sourcemap`, ohne Rojo)
- `tests` – Tests und Roblox-Nachbildung (`tests/run.py` startet sie, `tests/lib/rbxmx.py` liest Studio-Modelle,
  `tests/fixtures` Beispieldateien), `.github/workflows` – automatische Prüfung

# Shootout

Roblox-Shooter im Stil von Rogue Company. Alles läuft in **einem** Place: Hub, Modi und Training
sind eigene Bereiche der Welt, Moduswechsel funktionieren deshalb auch direkt in Studio.

## Entwickeln

    ./rojo serve                           # dann in Studio: Rojo → Connect
    ./rojo build -o build/shootout.rbxlx   # fertige Place-Datei bauen
    python3 tools/build_maps.py            # Maps neu erzeugen (nach Änderungen am Map-Skript)
    python3 tools/weapon_templates.py      # Blender-Vorlagen der Waffen neu erzeugen (art/templates/Weapons)
    python3 tools/asset_templates.py       # Blender-Vorlagen der Fahrzeuge und Items (art/templates/Vehicles, Items)

**Streaming:** `Workspace.StreamingEnabled` ist an (Radius 1024, mindestens 192, entfernte Teile werden wieder entladen).
Der Client hat nur die Teile in seiner Nähe; Client-Skripte dürfen sich also nicht darauf verlassen, dass ein Teil einer
Map existiert (nil prüfen, `WaitForChild` mit Zeitlimit, auf `DescendantAdded` hören). Immer vollständig geladen sind Hub
und Markt sowie die Gruppen Zone, Places, Stands, Lakes und Objective jeder Map (`tools/streaming.py`, setzt
`ModelStreamingMode = Persistent`). Den Grundriss der Weltkarte schickt der Server als Karten-Attribut `Layout`
(`WorldLayout`), Ort und Leben von Squad-Mitgliedern als Spieler-Attribute `ExtPos` / `ExtHealth`. Vom Server erzeugte
Modelle (Bots, Zombies, Fahrzeuge, Beute …) sind `Atomic`.

3D-Modelle (Waffen, Fahrzeuge, Items, Agenten) kommen aus Blender oder Meshy. Was der 3D-Designer beachten muss –
Vorlagen, Export-Einstellungen, Maße, Namen, Marker, Budgets, Texturen, Stil, Abgabe-Checkliste – steht in
[docs/3d-richtlinien.md](docs/3d-richtlinien.md); Waffen und Agenten im Detail in [docs/waffen-modelle.md](docs/waffen-modelle.md)
und [docs/agenten-modelle.md](docs/agenten-modelle.md).
Fertig vorbereitet für den Studio-Import: `art/sources/Rifle.glb` (Sturmgewehr) und `art/sources/SMG.glb`.

## Modi

| Modus | Kurz | Map |
|---|---|---|
| Hub | Kompakte Einsatzzentrale: an der Nordwand nur noch das große Tor nach EXTINCTION (Tafeln SAFE ZONE / DRAUSSEN links und rechts, Banner ARCADE darüber), Kartentisch mit Einsatz-Tafel, Bühne mit eigenem Agenten, Wand der Bestenlisten + Top-3-Statuen. Alter Hangar: `HUB_STYLE = "classic"` in `tools/build_maps.py` (fertig auch in `tools/saved/Hub_classic.model.json`) | Hub (0, 0, 0) |
| **EXTINCTION** (Hauptmodus) | Offene Welt mit Safe Zone, Inventar, Lager, Ständen, PvP draußen – siehe [Extinction](#extinction-offene-welt) | Ödland (0, 0, -6000), 3200 × 3200 |
| Markt | Handelshalle ohne Kampf: Stände beanspruchen, Skins für RAP anbieten und kaufen (Tor MARKT im Hub, Knopf MARKT im Seitenmenü) | Markthalle (-1500, 0, -1500) |
| Free-for-All (Arcade) | jeder gegen jeden, Respawn | Raffinerie (0, 0, 1500) |
| Herrschaft (Arcade) | 5v5, Flaggen A/B/C halten, unbegrenzter Respawn, 200 Punkte gewinnen | Tal (1500, 0, 0) |
| Wingman (Arcade) | 2v2, Punkt halten, Respawn-Tickets | Rotation: Fabrik / Hochhaus / Gletscher / Zellenblock / Kanäle / Windmühlen |
| 1v1 Arena (Arcade) | Duell | Arena (0, 0, 3000) |
| Training (Arcade) | Schießstand mit Übungspuppen | (-1500, 0, 1500) |

Die Minispiele haben kein Tor mehr im Hub: Man startet sie im Menü (M) unter **ARCADE** (dort auch SCHNELLES
SPIEL = vollster Arcade-Modus mit freiem Platz, auch auf anderen Servern). Oben im Menü steht groß EXTINCTION und ist
vorgewählt (`Featured` / `Arcade` in `src/shared/Modes.lua`).

**Arcade über mehrere Server** (`src/server/MatchmakingService.lua`, Einstellungen in `Modes.Matchmaking`): Damit
Arcade-Runden nicht mit Bots laufen, nur weil sich die Spieler eines Servers auf alle Modi verteilen, meldet jeder
öffentliche Server alle 10 Sekunden in der MemoryStore-Map `ArcadeServers_v1`, wie viele echte Spieler in Herrschaft,
Free-for-All, Wingman und 1v1 Arena sind und wie viele Plätze frei sind (Meldung verfällt nach 45 Sekunden). Wählt
jemand einen dieser Modi (oder SCHNELLES SPIEL), sucht der Server zuerst einen anderen Server, auf dem dort **mehr echte
Spieler** sind als hier und der Platz für den ganzen Squad hat (im Modus und auf dem Server). Gibt es einen, geht es per
Teleport dorthin („Wechsle auf einen Server mit 3 Spielern in HERRSCHAFT …“): der Squad-Anführer nimmt seinen Squad mit
(außer denen in der offenen Welt), drüben landet man direkt im Modus, und der Squad ist wieder zusammen (nur wer sich
gegenseitig in den Teleport-Daten nennt). Sonst wird wie bisher hier gespielt – so sammeln sich die Arcade-Spieler auf
wenigen Servern. Schlägt der Teleport fehl (Server voll, Fehler, nach 30 Sekunden nicht angekommen), spielt man hier;
danach und nach der Ankunft wird man eine Minute lang nicht weitergeschickt. Aus in Studio (kein Teleport), auf privaten
Servern, ohne MemoryStore und mit der Live-Einstellung **Arcade über Server** = 0. Hub, offene Welt, Markt und Training
bleiben immer auf dem eigenen Server. Squad-Mitglieder, die dem Anführer folgen, bleiben auf seinem Server.

ELO gibt es in jedem Modus (kein eigenes Ranked-Matchmaking). Ausgebaute Modi (Drop, Strikeout, Demolition,
Ranked, Extraction, TDM) stehen in `Modes.Disabled`; ihr Code liegt noch in `src/server/Modes/`.

Team-Modi teilen sich die Logik in `src/server/TeamRoundMode.lua` (Agentenwahl, Kaufphase,
Niederschlagen/Wiederbeleben, Bots). Ein neuer Team-Modus ist eine kurze Konfiguration in
`src/server/Modes/`, eigene Ziele (z.B. die Bombe) liegen in `src/server/Objectives/`.

## Extinction (offene Welt)

Vorbild: Überlebens-Server wie „GLife Extinction“. Man geht im Hub durch das große Tor und landet in der
**Safe Zone** „Camp Phoenix“ in der Mitte der Welt (Map `Extinction`, erzeugt von `build_extinction()` in
`tools/build_maps.py`, Radius 120): ein Überlebenden-Bollwerk aus Schrott – die Mauer aus gestapelten Autowracks,
Containern und Wellblech mit Stacheldraht, davor Holzspieße, tote Infizierte und ein brennender Leichenhaufen. Vier Tore
zwischen hochkant gestellten Containern mit Sandsack-Nest, MG und Scheinwerfer, gesprühte Warnungen („SAFE ZONE ·
KEINE INFIZIERTEN“, „DRAUSSEN STIRBT MAN“), Gerüsttürme in den Ecken. Drinnen Schlamm und Bretterwege, eine Feuerstelle mit
Kochtopf, Reifen und Kisten als Sitze (Spawn) mit Überlebenden, die am Feuer sitzen, daneben ein Wach- und Funkturm aus Gerüst (Sandsäcke, Scheinwerfer,
Lautsprecher, Antenne mit Blinklicht, rote PHOENIX-Banner, Wache oben), Wachen auf Toren und Ecktürmen, Feuertonnen,
verbarrikadierte Häuser, Sanitätszelt, Quarantäne-Käfig,
MG-Stellungen an den Toren, grelles Flutlicht am Generator, Treibstoff, Regentonnen; Händler unter Planen hinter
Paletten-Theken (WAFFEN, SANI, WERKSTATT, dazu der SPIELERMARKT dem Waffenstand gegenüber), das LAGER im Container,
die Haltestelle REISEN, eine Werkstatt und der Landeplatz mit Hubschrauber als Rückweg zum Hub (EVAKUIERUNG).
Über jedem Stand, dem Lager und jeder Haltestelle (auch in den Safehouses) schwebt eine **Hinweis-Blase** mit Namen
und Symbolen der Ware (Waffen als 3D-Modell, Munition, Medikit, Weste, Fahrzeuge, Münzen, Kiste, Wegweiser), damit man
schon von weitem sieht, wo was ist (`addBubble` in `src/client/ExtinctionClient.lua`, bis 180 Studs, Wände verdecken).

**Tutorial** (`src/client/ExtTutorial.lua`): Wer zum ersten Mal in die offene Welt kommt, bekommt eine Karte WELCOME mit
START TUTORIAL / SKIP. Danach führt eine Tafel oben in der Mitte durch sechs Schritte, jeder geht erst weiter, wenn er
erledigt ist: Starter-Kit holen (Wegpunkt zum nächsten Kit-Händler), Inventar öffnen, Waffe in die Hand, Safe Zone
verlassen, einen Zombie töten, zum Schluss die wichtigsten Regeln (Tasche fällt beim Tod draußen, alles Weitere im
GUIDE). Fertig oder übersprungen steht im Profil (`TutorialDone`), danach kommt es nicht mehr von selbst; im Menü unter
GUIDE startet oder überspringt ein Knopf es jederzeit. Spieler, die vor dem Tutorial schon da waren (`GuideHinted`),
bekommen es nicht.

**Reisen**: An der Haltestelle im Camp und in jedem Safehouse (Fahrer, Teil `Travel` / `Travel_<Name>`) öffnet **E** das
Fenster REISEN mit allen Safe Zones samt Entfernung; ein Klick bringt einen dorthin, die Zone wird zum Spawnpunkt
(`Extinction.Travel`, nur aus einer Safe Zone, `ExtinctionConfig.TravelCooldown` Sekunden Pause).

**Safehouses** (4 kleine Safe Zones draußen: NORD, OST, SÜD, WEST, Teile `SafeZone_<Name>` in der Gruppe Zone, Radius 64,
Hof 90 × 90 Studs). **Jedes sieht anders aus** (`SAFEHOUSE_STYLES` in `tools/extinction_world.py`, je Stil eine Methode
`_safehouse_<stil>`; `tests/maps_check.py` prüft eigenen Boden und eigene Bauteile):
- **NORD – Gehöft**: Schlammboden mit Bretterwegen, Palisade aus Brettern, Wellblech und gestapelten Autowracks mit
  Stacheldraht und Spießen davor, Holztor mit Torbogen, Holzhaus mit Veranda und Schornstein, Wasserturm, hölzerne
  Wachtürme, Pickup, Zelte, Generator, rote Fahne.
- **OST – Raststätte**: Asphalt mit Parkplätzen und abgestellten Autos, Mauer aus gestapelten bunten Containern (hochkant an
  den Ecken, vorne mit Plattform und Scheinwerfer), Tor mit Stahlträger, rot-weißer Schranke und Betonsperren davor; flaches
  Rasthaus mit vernagelter Glasfront, rotem Vordach und Leuchtschild RASTSTÄTTE, Tankstellen-Dach mit Zapfsäulen,
  Preis-Mast, Wohnmobile, Getränkeautomaten, Straßenlaternen mit kaltem Licht.
- **SÜD – Kloster**: Kopfsteinpflaster mit Steinplatten-Weg, Feldsteinmauer mit Zinnen (Lücken mit Brettern und Sandsäcken
  geflickt), weiße Banner mit rotem Kreuz, runde Ecktürme (hinten mit Spitzdach), Steinbogen-Tor mit offenem Eisengitter
  und Glocke, Kapelle mit Rosette, bunten Fenstern und Glockenturm mit Kreuz, Friedhof hinter Eisenzaun, Gemüsebeete,
  Brunnen, Krankenwagen.
- **WEST – Militärposten**: Kies mit Betonplatten, Mauer aus HESCO-Sandkörben mit NATO-Draht, Checkpoint zwischen
  Beton-T-Wänden mit Wachhäuschen, Schranke, Nagelband und HALT-Schild; Baracke aus Wohncontainern (Schild FOB WEST) mit
  Funkmast und Blinklicht, Stahl-Wachtürme mit Tarnnetz, Hubschrauber-Landeplatz, Armeezelte, Geländewagen unter
  Tarnnetz, Munitionskisten.

Gleich in allen: Tor mit Schild zur Zufahrtsstraße, tote Infizierte davor, Feuerstelle mit Bänken (Spawn) in der Mitte,
Feuertonnen und Flutlicht, MG-Stellung links hinter dem Tor. An den Seiten **eigene Händler** (links WAFFEN, WERKSTATT und
die Haltestelle REISEN, rechts SANI und ein LAGER-Container – dasselbe Lager wie im Camp) an denselben Stellen, wie im Camp
mindestens 30 Studs auseinander, damit sich die E-Aufforderungen nicht überlappen; die Planen der Händler haben die Farben
des Stils. Mehrere Stände dürfen denselben Namen haben (Server und Client prüfen den nächsten).
Jedes Safehouse hat seinen eigenen Zufall, Änderungen daran würfeln den Rest der Welt nicht neu (die eigenen Schilder der
Stile – `FRESH_SIGNS` – bleiben dafür beim Altern der Schilder außen vor).
Drinnen kein PvP,
Zombies bleiben draußen. Die zuletzt betretene Safe Zone (Camp oder Safehouse) ist der **Spawnpunkt** nach dem Tod
(Spawns im Ordner `Spawns_<Name>`, Meldung „Spawnpunkt gesetzt“); grün auf Minimap und Weltkarte.

**Die Welt** (3200 × 3200, `tools/extinction_world.py`) ist ein verwüstetes Land nach dem Ausbruch: in der Mitte die
zerstörte Großstadt **Ödstadt** (Durchmesser 1450, rund 700 Gebäude: vier Ringstraßen, zwölf Radialen und schräge
Querstraßen statt Raster; innen Hochhäuser, außen Geschäfte, Wohnblöcke und Vorstadthäuser; Hochhaus-Ruinen mit
Brandlöchern und abgebrochenen Spitzen, Wohnblöcke mit weggesprengten Ecken, Läden mit schiefen Schildern), mitten
darin der Platz mit der Safe Zone. Drumherum, über Landstraßen verbunden: die Dörfer **Nordheim** (mit Kirche),
**Sandbach**, **Altenfeld** und **Mühldorf**, das **Evakuierungslager**, die **Polizeiwache**, drei Tankstellen, zwei
Bauernhöfe, einzelne Häuser und Scheunen an allen Landstraßen, **zehn Außenposten auf Hügeln** (Wolfshöhe, Adlerhorst,
Steinkuppe, Krähenberg, Bärenkopf, Fuchsbau, Hoher Stein, Schwarzer Buckel, Kahlenberg, Rabenstein: Lagerhaus mit Schild,
Wachturm, Palisade, Sandsäcke, Feuer, Vorratslager, teils ein Zombienest), der **Funkturm** auf dem Hügel, der **Flugplatz** mit Flugzeugwrack, Schwarzsee, Stausee und Mühlteich.
**FPS**: Beim Bauen der Karte (`optimize` in `tools/extinction_world.py`) werfen nur große Gebäude- und Mauerteile
Schatten (rund 10 000 von 40 000 Teilen), Berührungs-Ereignisse gibt es nur an den Toren. Grafik NIEDRIG schaltet
zusätzlich Schatten, Leuchten, Partikel, Feuer und Rauch ab.
**Hochhäuser haben Form** (`skyscraper`): Stufen (oben schmaler, hinten eine Dachterrasse), Zwillingstürme auf einem
Sockel, L-Form (Turm mit niedrigem Flügel) oder Sockel mit schlankem Turm und Spitze – jeder Teil begehbar, die Treppe
des Sockels endet auf der Terrasse, der Eingang des oberen Teils liegt hinten. Dazu Leben: Bettlaken mit „SOS“, „HILFE“,
„WIR LEBEN NOCH“ aus den Fenstern, Rauch aus einem Fenster, Feuer in einem Stockwerk, Treppenhaus, Satellitenschüsseln
oder ein Landeplatz auf dem Dach (keine Firmennamen). Vor einzelnen Fenstern kleine Balkone, oft kaputt: zur Seite
abgesackt, Geländer verbogen oder weg und Bewehrung schaut heraus, manchmal Kisten oder Blumenkästen darauf.
**Hochhäuser und Wohnblöcke sind von unten bis aufs Dach begehbar** (`walk_block`): Stockwerke mit Decken, Rampen als
Treppen bis aufs Dach (Brüstung), wenige eingeschlagene Fenster (nur einzelne Achsen, Rückseite und Schmalseiten meist zu;
offen, teils Glassplitter oder vernagelt), Kisten, Möbel und
Schutt als Deckung in jedem Stockwerk, Ranken mit Blätterbüscheln, die vom Dach herunterhängen, Ruß über Fenstern,
Wassertanks, Antennen und Klimakästen auf dem Dach. Jedes Gebäude hat eine eigene Fassade (Stil zufällig, dazu Farbe,
Material, Fensterbreite und -abstand, Stockwerkshöhe): Plattenbau mit Fugen, Altbau aus Ziegeln mit Gesimsen, Glas-Büro
mit Metallrahmen und getönten Glasresten, Balkon-Block, farbige Brüstungsbänder, Feuertreppe aus Metall; manche mit
weggebrochenem obersten Stockwerk und Bewehrungseisen, selten nur ein eingestürzter Stumpf.
Alle Häuser sind kaputt: Löcher in den Wänden, abgebrochene Mauerkronen, Dächer ganz, halb oder gar nicht
(eingestürzte Platten), vernagelte Fenster, Schutt, Ruß, Ranken, Graffiti („SIE SIND DRINNEN“, „EVAKUIERUNG -> CAMP
PHOENIX“ …); auf den Straßen ausgebrannte Autos, Blutflecken, Sperren aus Beton und Sandsäcken, brennende Tonnen
und Rauchsäulen, die meisten Laternen sind tot. Gebäude sind Prefabs, die gedreht an die Straße gesetzt werden.
Straßen sind dunkler Asphalt mit Schlaglöchern, deren Körper bis in den Boden reicht (nichts schwebt); das Gelände ist
unter jeder Landstraße eben, Hügel und Seen weichen ihr aus. In Ödstadt sind es richtige Stadtstraßen: Gehwege mit
Bordstein (an Kreuzungen unterbrochen), weiße Rand- und Mittelstriche, Zebrastreifen, Gullydeckel, tote Ampeln. Über den
Norden der Stadt läuft die **A7** als Hochstraße auf Pfeilern (Rampen an beiden Enden, ein eingestürztes Feld, Wracks,
Schilderbrücken), durch den Süden die **Bahnstrecke** vom Westrand in den Hafen mit Bahnübergängen und dem **Bahnhof
Ödstadt Süd** (zwei Bahnsteige, Bahnhofsgebäude, entgleister Zug). Von den Landstraßen führen **Feldwege** (Erde, folgen
dem Hang) hinauf zu jedem Außenposten und zum Funkturm. Alle Schilder sind alt und verwittert (Bretter,
rostiges Blech oder Stoff, mit Marker gemalt, schief, ohne Leuchten) statt moderner Leuchttafeln.
Das Gelände ist echtes **Terrain** (Höhenfeld aus `tools/extinction_terrain.py` in
`src/server-shared/ExtinctionTerrainData.lua`, `ExtinctionTerrain.lua` baut es beim Serverstart: in den
Ortskernen zertrampelte Erde, Matsch und verdorrtes Gras (kein Pflaster), außen Gras, Erde, Fels, Sand und Wasser); bis dahin trägt der flache Boden der Karte (Rückfall). Danach räumt
`ExtinctionTerrain.ClearRoads` das Terrain im Grundriss jeder Straße, jedes Gehwegs, Feldwegs, des Gleisbetts und
der Basis-Platte aus (nur Luft ab 2,5 Studs unter der Oberkante, keine Erde – das Voxel-Terrain würde sonst auf ganze
4-Stud-Blöcke runden und über die Fahrbahn wachsen), damit die Straßen sichtbar obenauf liegen.
**Rote Zone** (`RedzoneService.lua`, `ExtinctionConfig.Redzone`): es gibt **genau eine** rote Zone (Radius 170). Sie
zieht alle **20 Minuten** an einen anderen Ort der Karte (Dörfer, Krankenhaus, Militärbasis, Hafen, Gefängnis, Flugplatz,
Höfe, Außenposten, Tankstellen, Bahnhof … – nicht Camp, Seen, die ganze Stadt, Safehouses oder Wasser), nie zweimal
hintereinander an denselben und möglichst mindestens 400 Studs vom alten weg (`MinMove`). Drinnen gilt PvP sofort, mehr
Zombies und **deutlich bessere Beute** (`ExtinctionConfig.Redzone.Loot`): Zombies, die dort sterben, haben 25 % öfter
Beute, aus der nächstbesseren Tabelle (normale wie Läufer, Läufer wie Industrie, Brocken wie Militär), ein Item mehr,
1,5× so große Stapel und doppelte Münzen; Vorratslager und Nester dort geben mehr; Lootdrops landen öfter in der Zone
und haben dort mehr Items, und bei jedem Wechsel kommt kurz nach der Ansage ein Lootdrop in die neue Zone. Ansage an alle beim Wechsel und eine Minute vorher; in der Welt eine flimmernde rote Wand und
eine Lichtsäule; eine rote Zeile unter der Uhr nennt Ort, Zeit bis zum Wechsel und Entfernung (Karten-Attribut
`Redzones`, eine Liste – vorbereitet für später mehrere Zonen). Mit jedem Wechsel beginnt die **Rangliste** neu. Feste
rote Zonen auf der Karte gibt es nicht mehr. Es gibt keine Richtungsanzeiger mit Entfernung oben am Bildschirm (Ziele
zeigen Minimap und Weltkarte).
Die Nacht ist hell genug zum Spielen (bläuliches Umgebungslicht, wenig Dunst). Admin-Panel: Knopf **TAG / NACHT**
springt auf 10 bzw. 22 Uhr (Attribut `DayOffset` an ReplicatedStorage, `DayCycle.SetClock`).
**Minimap** (oben links) zoomt in der offenen Welt weiter raus (240 Studs, Karten-Attribut `MinimapRange`), zeigt nur
Straßen und Gebäude und die Zonen als Punktkreise (grün Safe Zones, rot die rote Zone – der Kreis zieht mit); in der
roten Zone wird ihr Rand rot. **Weltkarte** mit **N** (oder Knopf KARTE oben rechts): Straßen, Gebäude, Seen, Orte,
Safe Zones, die rote Zone mit der Zeit bis zum Wechsel, Lootdrops mit Countdown, Vorratslager, Funkgerät und der
eigene Standort. Tankstellen und Seen stehen
ohne Namen auf der Karte (die Seen sieht man als Fläche), Zombienester und Überlebende gar nicht, damit sie übersichtlich
bleibt. Beim Betreten eines Ortes erscheint sein Name.
**Tag und Nacht** (`src/shared/DayCycle.lua`, `ExtinctionConfig.Day`): ein Tag dauert 24 Minuten, davon etwa
9 Minuten Nacht (blaues Mondlicht, dichter Dunst – Feuer und die wenigen Laternen sind dann die Lichter). Die Uhrzeit
hängt an der Serverzeit, alle sehen dieselbe; Anzeige oben rechts. Nachts kommen mehr Zombies (×1,6) und sie sehen
weiter. An manchen Morgen liegt **dichter Nebel** (bis etwa 10:30 Uhr).
**Blutmond-Event** (`BloodMoonService`, `ExtinctionConfig.BloodMoon`): alle 60 Minuten (das erste nach 30) für
**10 Minuten**, eine Minute vorher eine Warnung. Es wird Nacht mit rotem Licht, die Uhr oben zeigt die Restzeit. Zombies:
×1,5 so viele, härtere Arten, ×1,5 Leben, ×1,35 Schaden, schneller – dafür **bessere Beute** (Tabelle eine Stufe höher,
höhere Chance, ein Item mehr). **Bosse**: die *Blutbestie* (riesig, 2400 Leben, Name und Lebensbalken über dem Kopf, roter
Umriss) erscheint alle 2,5 Minuten bei einem Spieler draußen (höchstens 2 gleichzeitig), Ansage beim Erscheinen und beim
Tod, 250 Münzen und Beute wie aus einem Lootdrop. Admin-Panel: Knopf **BLUTMOND** startet/beendet sofort.
**Bots in der offenen Welt** (Admin-Panel, Zeile *Extinction*: **+1 Bot**, **+5 Bots**, **Entfernen**;
`ExtinctionConfig.Bots`): Gegner zum Testen von PvP, Todestaschen und Rangliste. Sie spawnen 25-45 Studs um den Admin
(steht er in einer Safe Zone, gleich vor ihrem Rand in seiner Richtung; ist er nicht in der offenen Welt, in der roten
Zone), nie in einer Safe Zone oder im Wasser, höchstens 12. Jeder trägt eine Waffe der offenen Welt (Pistole bis
Präzisionsgewehr), jagt Spieler draußen bis 160 Studs weit (nie in einer Safe Zone), schießt auf Zombies in der Nähe –
und Zombies jagen ihn. Bots sind ein Team (*Banditen*) und schießen nicht aufeinander, Gadgets haben sie wie Spieler
dort keine. Beim Tod fällt eine **Tasche** mit seiner Waffe, Munition und Beute (Tier 2, in der roten Zone Tier 3);
der Schütze bekommt 80 Münzen, in der roten Zone zählt der Kill für die Rangliste. Kein Respawn: die Leiche verschwindet
nach 8 Sekunden.
**Parkhaus** (`parking_garage`, am Ostrand von Ödstadt an einer Straße, Ortsname PARKHAUS): großes Parkhaus im
GTA-Stil (100 × 72 Studs) mit Erdgeschoss, drei Parkdecks und offenem Dach; jede Ebene hat ihre Farbe (P0 rot, P1 gelb,
P2 grün, P3 blau, DACH violett) an den Fassadenbändern, Säulenringen und Ebenen-Nummern. Zufahrt von der Straße, Einfahrt
mit offener Schranke, Kassenhäuschen und Durchfahrtshöhe, die Ausfahrt mit Wracks zugestellt, daneben ein verlassener
Militärposten. Innen Stellplätze vorne, als Doppelreihe in der Mitte und hinten, Fahrgassen mit Pfeilen und Bodenwellen,
Deckenlampen (fast alle kaputt), Wracks in den Buchten, Rampen hinten von Ebene zu Ebene bis aufs Dach (flach genug für
Fahrzeuge). Zwei Treppen- und Aufzugstürme mit P-Schild, ein großes PARKHAUS-Schild auf der Dachkante, im zweiten Deck
eine eingestürzte Ecke (die Platte hängt ins erste Deck), Ranken und Graffiti. Auf dem Dach lagern Überlebende: Zelte,
Feuer, Sandsack-Nester an den vorderen Ecken, zwei Container, ein abgestürzter Hubschrauber mit Rauch, Betonsperren, SOS.
**Dächer für Hubschrauber**: zwei Hochhäuser haben ein freies Dach mit Landefläche (gelber Rand, H, Randlichter, Windsack).

- **Safe Zone** (grüner Ring, Radius 100): kein Schaden, Waffen bleiben gesichert (Taste zieht keine Waffe,
  beim Betreten wird sie weggesteckt). Dort stehen der **Waffenstand**, der **Itemstand**, der
  **Fahrzeugstand**, das **Lager** und das Tor zurück zum Hub (E an Stand/Lager).
- **Draußen**: sofort schießen auf Zombies möglich, **PvP erst 5 Sekunden nach dem Verlassen** (Anzeige oben:
  SAFE ZONE · PVP IN 3 S · PVP AKTIV). Schaden zwischen Spielern nur, wenn beide ihre PvP-Zeit haben.
- **Menü** (**TAB** öffnet es auf INVENTAR, **M** auf dem zuletzt offenen Reiter; Controller: Select, L1/R1 blättert, ○
  schließt): etwas kleiner als der Bildschirm, Reiter INVENTAR · MARKT · SQUAD · SHOP · BATTLE PASS · STATISTIK · CODES ·
  OPTIONEN. Die letzten fünf sind die Seiten der Lobby (`GameMenu.BorrowPage`), verkleinert – ohne Spielmodi und
  Startseite. Die Welt läuft weiter, während das Menü offen ist.
- **Keine Standardwaffen**: Alles kommt aus der Tasche. Der Reiter **INVENTAR** zeigt die Tasche: 30 Plätze, davon 1-9 die
  Hotbar (Tasten **1-9**). Items ziehen und ablegen oder anklicken und den Zielplatz anklicken, Rechtsklick legt
  zwischen Hotbar und Tasche hin und her. Waffe: Taste zieht sie (nochmal = wegstecken), Heilung/Rüstung: Taste
  benutzt sie (dauert ein paar Sekunden, dabei kein Schuss).
- **Munition** kaufen oder finden: Nachladen nimmt Schuss aus der Tasche (9mm, Magnum, Schrot, Gewehr), das
  Magazin bleibt am Item gespeichert. Ohne passende Munition kein Nachladen.
- **Stände**: kaufen mit Münzen (Munition auch ×5), verkaufen an jedem Stand für 40 % des Preises.
- **Spielermarkt** (`ExtMarketService`, Reiter **MARKT** im Extinction-Menü, überall in einer Safe Zone – draußen nicht): Spieler handeln untereinander mit
  allem aus der Tasche – Waffen (samt Magazin), Munition (auch Teile eines Stapels), Heilung, Westen, Spritzen und
  Fahrzeuge – für Münzen. Die Seite (`ExtMarketPage`): links alle Angebote als Karten mit Symbol, Werten, Verkäufer und
  Preis (Suche, Kategorien ALLE/WAFFEN/MUNITION/AUSRÜSTUNG/FAHRZEUGE, Sortierung BILLIG ZUERST/TEUER ZUERST/NEU, KAUFEN
  bzw. ZU TEUER), Umschalter MEINE ANGEBOTE (PREIS ÄNDERN mit ±/Feld/OK, ZURÜCKNEHMEN); rechts VERKAUFEN: Item der Tasche
  anklicken, Anzahl und Preis mit ±, Feld oder Schieberegler (Vorschlag: der Preis am Stand), darunter günstigstes Angebot
  und Ø desselben Items und der Erlös nach Gebühr, ANBIETEN. Außerhalb der Safe Zone liegt eine Sperre über der Seite.
  Die Einstellzeit `At` bleibt beim Preisändern (für die Sortierung NEU). Höchstens 8 Angebote je Spieler, Preis 1-100.000, der Verkäufer bekommt den Preis minus 5 %
  Gebühr (ohne VIP-Verdopplung). Angebote stehen im Spielstand des Verkäufers (`Extinction.Market`): sie überleben Tod und
  Verlassen und sind zu sehen, solange er auf dem Server ist; Käufe werden sofort gespeichert. Ein Fahrzeug, das draußen
  steht, muss erst eingepackt werden (`ExtinctionConfig.Market`, Karten-Attribut `PlayerMarket`).
- **Squads** (`PartyService`, Fenster mit **J** oder dem Knopf SQUAD unter KARTE): bis zu 4 Spieler. Im Fenster stehen
  links dein Squad (Anführer mit ★, Ort bzw. Entfernung, ENTFERNEN für den Anführer, SQUAD VERLASSEN), rechts alle anderen
  Spieler der offenen Welt mit EINLADEN; eine Einladung kommt als Hinweis und wird im Fenster angenommen (die Maus ist im
  Spiel gefangen). In der offenen Welt ist der Squad ein **Team**: kein Friendly Fire (auch nicht an Fahrzeugen), Namen
  über dem Kopf, Punkte auf der Minimap, Liste links unter den Aufträgen (Ort/Entfernung und Leben) – und **Pings** (Z,
  Mausrad-Klick) sehen nur die Squad-Mitglieder. Spieler-Attribut `SquadId`. Wer im Squad ist, wird nicht aus der offenen
  Welt gezogen, wenn der Anführer sie verlässt; betritt der Anführer sie, kommt der Squad mit.
- **Anti-Zombie-Spritze** (`AntiZombie`, Itemstand 240 Münzen, auch in Sanikisten, bei Läufern, in Lootdrops): einzige
  Wirkung – **3 Minuten lang spawnen bei dir keine Zombies**, aus keiner Quelle (Umgebung, rote Zone, Schreier, Nester,
  Lootdrop-Begleiter, Bosse) näher als 80 Studs (`Zombies.ShieldRadius`). Zombies, die schon da sind, bleiben; bei
  anderen Spielern spawnen sie normal. Restzeit oben unter der Zonen-Anzeige; eine zweite Spritze geht erst, wenn die
  erste abgelaufen ist; der Tod beendet die Wirkung.
- **Lager**: 40 Plätze, immer sicher (auch beim Tod).
- **Tod draußen**: die ganze Tasche fällt als **Tasche am Boden** (Rucksack mit rotem Licht und Lichtsäule, Name des
  Toten darüber; 5 Minuten, jeder kann sie mit E durchsuchen und Items einzeln nehmen), Respawn nach 5 s in der
  Safe Zone. Der Tote sieht seine Tasche als **rotes X** auf Minimap (am Rand, wenn sie weit weg ist) und Weltkarte (mit
  Restzeit) und bekommt nach dem Respawn einen Hinweis; war die Tasche leer, fällt nichts („NICHTS VERLOREN“).
  Spieler-Kill: +120 Münzen Kopfgeld (dazu der normale Kill-Lohn).
- **Verlassen**: in der Safe Zone bleibt alles genau so angeordnet in der Tasche (gespeichert im Profil). Draußen
  kostet Verlassen die Tasche (im Menü erst nach einem zweiten Klick, beim Spiel-Verlassen sofort vor dem
  Speichern); fährt der Server herunter, verliert niemand etwas.
- **Zombies** (`src/server-shared/ZombieService.lua`): wenige und langsam – spawnen nur um Spieler draußen im
  weiteren Umkreis (80-150 Studs, nicht auf Dächern, nicht im Wasser, nicht nah an der Safe Zone), höchstens 3 pro
  Spieler und 30 auf dem Server. Sie schlurfen herum, bemerken Spieler erst auf 45 Studs und schlagen langsam zu; in
  die Safe Zone gehen sie nicht. In der roten Zone gibt es mehr (doppelt so viele pro Spieler) und dazu **Läufer**
  (schnell, wenig Leben) und **Brocken** (groß, viel Leben, harte Schläge, immer Beute).
- **Zombie-Arten**: alle mit Blutflecken und Wunden. Draußen am Tag fast nur normale Zombies, ein paar **Läufer** und
  **Schreier** (weiße Augen): sieht ein Schreier dich, schreit er (roter Ring) – alle Zombies im Umkreis jagen dich und
  drei weitere kommen dazu. Nachts mehr Läufer, Schreier und auch **Brocken**; in der roten Zone die meisten.
- **Zombie-Beute**: tote Zombies bleiben mit Beute 40 Sekunden liegen (leuchten). **Einmal E** (ohne Halten) öffnet
  das Beute-Fenster wie bei einer Tasche: Items einzeln anklicken (passt etwas nicht, bleibt es in der Leiche); leer
  geräumt verschwindet die Leiche. Zombies lassen öfter etwas fallen (75 %, Läufer 85 %, Brocken immer), weil es keine
  Beute mehr am Boden gibt.
- **Zombie-XP**: jeder erledigte Zombie gibt **XP** für den aktiven Agenten, das Spielerlevel und den Battle Pass
  (Zombie 10, Läufer 20, Schreier 25, Brocken 50, Blutbestie 600; `XP` in `ExtinctionConfig.ZombieKinds`). Doppel-XP und
  Agent der Woche wirken mit; Münzen gibt es dafür keine extra (nur die wenigen Zombie-Münzen).
- **Taschen am Boden** (Todestasche, Lootdrop, Kisten): **E** öffnet das Fenster, Items **einzeln** anklicken; das
  Schild zeigt die Anzahl der Items. Meldung unten „+ 2 Verband, 30 9mm …“.
- **Alles looten = Gamepass** (`RobuxConfig.Passes`, Id `LootAll`, Attribut `Pass_LootAll`): Alles auf einmal nehmen –
  **F** an Taschen, Kisten, Lootdrops und Leichen oder der Knopf **ALLES NEHMEN** im Fenster – gibt es nur mit dem
  Gamepass **ALLES LOOTEN** aus dem Robux-Shop (SHOP › ROBUX). Ohne ihn ist der F-Prompt ausgeblendet, der Knopf heißt
  „ALLES NEHMEN · GAMEPASS“ und öffnet den Kauf; der Server lehnt „alles“ ohne Pass ab (F öffnet dann nur das Fenster).
  Solange in `RobuxConfig` noch keine PassId eingetragen ist, steht im Shop „BALD“.
- **Aktivitäten** (`ActivityService.lua`, Teile `Act_<Art>` in der Gruppe Activities, Werte
  `ExtinctionConfig.Activities`); auf der Weltkarte stehen nur Vorratslager und Funkgerät:
  - **Zombienester** (15, in Ödstadt, den Dörfern, Wäldern, Gefängnis, Militärbasis, Hafen): leuchtender Kern aus Fleisch, man schießt
    darauf (900 Leben). Solange es lebt und jemand in der Nähe ist, kriechen Zombies heraus. Zerstört: jeder, der
    Schaden gemacht hat, bekommt 150 Münzen und Beute direkt ins Inventar; nach 10 Minuten wächst es nach.
  - **Vorratslager** (21, an Polizei, Krankenhaus, Tankstellen, Höfen, Flugplatz, Militärbasis …): **E 10 Sekunden
    halten** zum Aufbrechen – der Lärm lockt sofort Zombies an. Beute direkt ins Inventar (in der roten Zone die beste),
    danach leer
    für 12 Minuten.
  - **Funkgerät** am Funkturm: **E halten = Notruf**, ein Lootdrop kommt (alle 15 Minuten).
  - **Überlebende** (10, in Dörfern, Höfen, Ödstadt, Flugplatz): **E halten** – er folgt dir. Bring ihn lebend in die
    Safe Zone (Marker oben zeigt den Weg): 250 Münzen und Beute. Zombies greifen ihn an; stirbt er, bleibt er mehr als
    90 Studs zurück oder dauert es zu lange, ist die Rettung gescheitert. Kommt nach 15 Minuten wieder.
  - Horden gibt es nicht mehr (alte Punkte `Act_Horde` einer Karte werden ignoriert). Zombienester und Überlebende
    stehen nicht auf der Weltkarte – man findet sie draußen.
- **Aufträge** (`MissionService.lua`, `ExtinctionConfig.Missions`): immer drei gleichzeitig, links mit etwas Abstand
  unter dem VERLASSEN-Knopf (rutscht mit ihm, auf Touch unter der Lebensanzeige), mit Fortschrittsbalken – z. B.
  „Töte 20 Zombies“, „Töte 5 Läufer“, „Töte 10 Zombies in der roten Zone“, „Zerstöre ein Zombienest“, „Brich 2
  Vorratslager auf“, „Rette einen Überlebenden“, „Öffne einen Lootdrop“, „Erkunde: NORDHEIM“, „Überlebe 3 Minuten
  nachts draußen“. Erledigt: Münzen und Beute direkt ins Inventar, dann kommt ein neuer Auftrag.
- **Apokalypse**: Fluchtstaus mit umgekipptem Schulbus auf den Ausfallstraßen, verlassene Quarantäne-Sperren an den
  Dorfeingängen („INFIZIERT · NICHT BETRETEN“), Massengrab beim Evakuierungslager, verlassene Überlebenden-Camps im
  Wald (SOS am Boden), Leichen auf den Straßen, Notstands-Plakate („AUSGANGSSPERRE AB 20 UHR · SCHIESSBEFEHL“),
  abgestürzte Hubschrauber; fahles, gelbgraues Licht.
- **Keine Beute am Boden**: die Lagerkisten (`ContainerService.lua`) sind abgeschaltet
  (`ExtinctionConfig.Containers.Enabled = false`). Beute gibt es von Zombies, aus Lootdrops und an den Ständen.
- **Rote Zone** (`RedzoneService.lua`): eine Zone, die alle 20 Minuten weiterzieht (siehe oben). Drinnen gilt
  **PvP sofort**, Anzeige „ROTE ZONE · PVP AKTIV“ mit rotem Bildschirmrand, mehr und härtere Zombies, bessere Beute.
  Beim Betreten (auch wenn eine neue Runde beginnt, während man drinsteht) kommt eine Meldung mit dem Ort.
- **Redzone-Rangliste** (`src/server-shared/RedzoneBoard.lua`, Anzeige im `ExtinctionClient`): nur solange man in
  der roten Zone steht, rechts oben unter der Uhr die **Top 3 der Spieler-Kills (PvP) dieser Runde**. Jede Runde
  dauert 20 Minuten: zieht die Zone weiter, beginnt die Liste mit dem neuen Ort wieder bei null. Ein Kill zählt, wenn
  das Opfer in der Zone stirbt, sonst wenn der Schütze drinsteht; bei Gleichstand steht vorn, wer die Zahl zuerst
  hatte. Wer nicht unter den ersten drei steht, sieht darunter seinen Platz („DU · PLATZ 5“); wer
  die offene Welt verlässt, fällt raus. Solange die Liste zu sehen ist, rückt der Killfeed darunter (Karten-Attribut
  `RedzoneBoard`).
- **Lootdrops** (`AirdropService.lua`): 2,5 Minuten nach Serverstart, danach alle 7-11 Minuten eine Ansage
  „VERSORGUNGSABWURF“ mit Fackel (Lichtsäule) an der Landestelle, 45 s Vorwarnung, dann sinkt die Kiste 25 s am
  Fallschirm (60 % Chance in der roten Zone, dort 2 Items mehr; bei jedem Wechsel der roten Zone kommt außerdem ein
  Abwurf in die neue Zone). Gelandet: **E 8 Sekunden halten** öffnet sie – beste Beute, dazu Begleiter-Zombies. Bleibt
  5 Minuten.
- **Fahrzeuge** (`src/server-shared/VehicleService.lua`, Steuerung `src/client/VehicleClient.lua`): am
  Fahrzeugstand kaufen (Quad, Geländewagen mit 4 Sitzen, Sportwagen; Fahrräder und Quads auch von Zombies), auf
  einen Hotbar-Platz legen – die Taste spawnt das Fahrzeug vor einem und setzt einen direkt hinein. **K** packt es
  wieder ins Inventar (nur drin oder nah dran), danach **8 Sekunden** warten bis zum nächsten Spawn. Höchstens ein
  Fahrzeug pro Spieler draußen (Hotbar zeigt DRAUSSEN), gleiche Taste in der Nähe = wieder einsteigen. Mitfahrer
  steigen mit E ein, fahren darf nur der Besitzer; im Fahrzeug keine Waffe. W/S Gas und Bremse, A/D lenken
  (Controller/Touch über Roblox), Leertaste aussteigen, Verfolgerkamera. Fahrzeuge haben Leben (Schüsse nur
  draußen mit PvP), kaputt = ausgebrannt und weg; Zombies kann man umfahren. Stirbt der Besitzer, liegt das
  Fahrzeug in seiner Tasche am Boden. Technik: unsichtbarer Rumpf auf vier reibungsfreien Kugeln, LinearVelocity
  (nur waagerecht) und AlignOrientation, der Fahrer rechnet die Physik; der Server prüft das Tempo.
- **Waffe inspizieren** (überall mit Waffe in der Hand: **X**, Controller □ bei vollem Magazin, Touch INSPEKT): jede
  Waffe hat ihren eigenen Ablauf (`WeaponAnimations.Inspect`) – Sturmgewehr rollt auf die Auswurfseite und prüft das
  Magazin, MP wirbelt um den Lauf und zieht den Spannhebel, Schrotflinte schiebt eine Patrone nach und pumpt halb,
  Präzisionsgewehr tippt den Verschluss an, LMG klappt den Deckel auf und klopft auf den Kasten, Pistole dreht sich auf
  den Rücken, Schlitten-Check und Wirbel um den Abzugsfinger, Revolver lässt die Trommel rattern und wirbelt zweimal.
  Ein Arcade-Trick mitten im Spiel: HUD und Kamera bleiben, wie sie sind, und es geht auch beim Laufen und Sprinten
  (die Waffe wird dabei nicht in die Sprint-Haltung gesenkt). Schießen, Zielen, Nachladen, Messer, Wechsel oder nochmal
  X beenden es. Geht es gerade nicht (keine Waffe in der Hand, in der Safe Zone sind Waffen gesichert, im Hub, beim
  Nachladen/Zielen, im Fahrzeug), erscheint unten kurz ein Hinweis (`src/shared/InspectView.lua`). Andere Spieler sehen
  es in der Third-Person (Remotes.Inspect ->
  Charakter-Attribute InspectStart/InspectWeapon). Test: `tests/inspect.test.luau`.
- **Helikopter** (Fahrzeugstand, 12 000 Münzen, Tier 4): fliegt mit **bis zu 4 Leuten** – Pilot (der Besitzer) links
  vorne, Kopilot und zwei Plätze hinten (Mitfahrer per E). Steuerung: **W/S** vor/zurück, **A/D** drehen,
  **Leertaste** steigen, **Shift** (oder Strg/C) sinken, **F** aussteigen; Controller: Stick, R2/L2 steigen/sinken, ✕
  aussteigen; Touch: Stick, Knöpfe STEIGEN/SINKEN statt FEUER/ZIELEN, RAUS. Am Boden erst abheben, ohne Eingabe hält er die
  Höhe; er neigt sich beim Fliegen und in Kurven, die Rotoren drehen sich. Höchstens 320 Studs hoch (über der Mitte der
  Welt), am Rand der Welt geht es nicht weiter. Wer hoch oben aussteigt, gleitet mit dem Fallschirmsprung zu Boden.
  Ohne Pilot sinkt er langsam senkrecht und setzt auf (Autorotation); einpacken (K) nur gelandet; zerschossen stürzt er
  ab. HUD: Tempo, **Höhe**, Zustand, die Tastenzeile zeigt die Flugsteuerung. Technik: LinearVelocity in alle Richtungen
  (trägt das Gewicht), Rotoren an Motor6D (jeder Client dreht sie), Tasten schluckt eine ContextActionService-Aktion mit
  hohem Vorrang; der Server prüft zusätzlich Steigen, Flughöhe und Weltrand (Test: `tests/heli.test.luau`).
- **Agenten**: nur passive Fähigkeiten (keine Q/G/F), Leben und Tempo wie sonst.

Code: `src/server/Modes/Extinction.lua` (Safe Zone, PvP, Tod/Verlassen), `src/server-shared/InventoryService.lua`
(Tasche, Hotbar, Lager, Stände, Benutzen), `src/server-shared/LootService.lua` (Taschen, Kisten, Lootdrops am Boden),
`ZombieService.lua`, `RedzoneService.lua`, `ContainerService.lua`, `AirdropService.lua`, `ExtinctionTerrain.lua`,
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
  - LOADOUT: links die Waffen, Mitte große 3D-Vorschau mit ausgerüstetem Skin, rechts die eigenen Skins
    zum Ausrüsten und ZUM SHOP
  - SHOP: Waffen-Skins als Karten mit 3D-Vorschau, Seltenheit und KAUFEN · Preis (Agenten-Skins gibt es nicht mehr:
    Agenten haben den Standard-Look oder ihr 3D-Modell)
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
  man nur über Skins. Jeder handelbare Waffen-Skin hat einen RAP-Wert, **steil gestaffelt wie bei Sniper
  Duels**: gewöhnliche Skins 1-10 RAP (Waldtarn 2, Wüste 3), seltene zweistellig (30-55), epische dreistellig (260-520,
  Battle-Pass-Skin Saison-Neon 2.500), legendäre vier- bis fünfstellig (Lava 3.200 bis Galaxie 8.500, Kalender-Skin
  18.000), Battle-Pass-Goldrausch 35.000, Battle-Pass-Saison-Elite 45.000 (Stufe 20) und die Robux-Skins Royal 90.000 / Hologramm 150.000.
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
  - **Aufbau**: Man spawnt in der Mitte auf dem großen, ruhigen **Marktplatz** (Such-Terminal in der Mitte; am Rand der
    Kisten-Automat, die Übersichtstafel mit freien/belegten Ständen und die Tafel **beliebteste Händler** nach Verkäufen).
    Das Tor zurück zum Hub steht am Ende der Südrampe (oberster Rang); schneller geht es über den Knopf ZUM HUB im Seitenmenü. Darum liegen wie in einem
    Theater drei Ränge, die nach außen stufenweise höher werden (Stände 1-12, 13-28, 29-48); alle Stände zeigen zur Mitte.
    Vier Rampen (Norden, Osten, Süden, Westen) führen über alle Ränge nach oben, die Stufen kann man auch springen.
  - **SUCHE** (Knopf oben oder E am Such-Terminal, Logik in `src/shared/MarketSearch.lua`): alle Angebote aller Stände
    durchsuchen (Skin, Seltenheit, Besitzer, Stand), filtern nach Seltenheit, nur Bezahlbares oder
    Merkliste, sortieren nach Preis, **Schnäppchen** (am weitesten unter dem RAP-Wert) oder Seltenheit. **HIN** zeigt
    einen Pfeil mit Entfernung über dem Stand.
  - **Preisverlauf**: Durchschnittspreis der Verkäufe der letzten 7 Tage je Skin (DataStore `MarketHistory_v1`,
    gilt für alle Server) steht in Suche, Stand-Fenstern und MEIN STAND. Damit auch viele Server nicht in dieselben
    Einträge drängeln, sind die Skins nach Namen auf 8 Einträge `shard_<n>` verteilt (Verkäufe und lebender RAP
    zusammen); jeder Server sammelt seine Verkäufe und schreibt höchstens einmal pro Minute je Eintrag (mit eigenem
    Versatz, beim Herunterfahren sofort, bei einem Fehler beim nächsten Mal), alle 5 Minuten lädt er die Verkäufe der
    anderen Server neu (`HistoryShards`, `HistoryFlush`, `HistoryRefresh` in `RapConfig`). Die alten Einträge `sales`
    und `rap` werden nur noch gelesen.
  - **Merkliste**: MERKEN an einem Skin – bietet jemand ihn an, kommt eine Meldung (im Profil gespeichert).
  - **Gegenangebote**: an fremden Ständen ANGEBOT MACHEN (mindestens der halbe Preis, 45 s gültig, eins pro Stand).
    Der Besitzer sieht sie unter **ANGEBOTE** in der Leiste und nimmt an (Verkauf zum Gebot) oder lehnt ab.
  - **Stand-Name**: in MEIN STAND, erscheint auf dem Schild (läuft durch den Textfilter).
  - **Stand beanspruchen**: an einem freien Stand **E** – man bleibt, wo man steht (kein Teleport), das Schild über dem
    Stand zeigt den eigenen Namen. Einer pro Spieler.
  - **Kisten** (Automaten in der Mitte, Server `src/server-shared/CrateService.lua`, Client `src/client/CrateClient.lua`,
    Chancen und Preise in `src/shared/CrateConfig.lua`): **WAFFEN-KISTE** (450 Münzen; die
    Agenten-Kiste gibt es nicht mehr). E am Automaten öffnet das Fenster: Chancen je Seltenheit, alle Skins der Kiste, ÖFFNEN lässt die Rolle
    laufen und zeigt den Gewinn. Gezogen wird aus den im Shop kaufbaren Waffen-Skins. Schon besessene
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
- **Agenten**: 9 Stück mit Passiv, je 2 wählbare Primärwaffen, Fähigkeit (Q) und Gadget (G), Level
- **Alle spielen als Agent** (`src/server-shared/AgentBody.lua`, gespawnt über `src/server/SpawnUtil.lua`): Im Hub, im
  Markt und im Match trägt jeder Spieler statt seines Roblox-Avatars denselben schlanken R15-Körper im
  Roblox-Standard-Look in den Farben seines Agenten: Kopf in Hautfarbe mit dem Roblox-Gesicht, Oberkörper und Arme in
  der Agentenfarbe, Beine dunkler (keine Kapuze/Weste/Quader-Ausrüstung mehr). Bots tragen genau denselben Körper
  (keine Teamfarben – das Team erkennt man wie bei Spielern am Namensschild), die Übungspuppen haben dieselben
  Trefferzonen. Im Hub und im Markt sieht man einen Agentenwechsel sofort, im Match ab dem nächsten Spawn. Hat ein
  Agent ein fertiges 3D-Modell (siehe Agentenmodelle), tragen Spieler und Bots mit diesem Agenten automatisch dieses
  Modell, auch in allen Menü-Figuren
- **Gleiche Trefferzonen für alle**: Getroffen werden nur Körperteile. Accessoires (auch später angehängte) und die
  Ausrüstung sind für Schüsse unsichtbar (`CanQuery = false`); der Server nimmt auch vom Client gemeldete Treffer
  nur auf treffbaren Teilen an
- **Waffenmodelle aus Blender** (`src/shared/GunModels.lua`, Anleitung [docs/waffen-modelle.md](docs/waffen-modelle.md)):
  Liegt in Studio unter ReplicatedStorage › Assets › Weapons ein Modell mit dem Namen einer Waffe, ersetzt es die
  Quader-Waffe überall (Ego-Waffe, Hand, Rücken, Vorschauen, Symbole). Marker im Modell legen Griff, Visierlinie,
  Mündung, Hülsenauswurf, Hände und Schaft fest – wie das Modell beim Import gedreht ist, ist egal. Teilnamen
  bestimmen Animationsgruppen, Skin-Zonen, Leuchtpunkte und Glas; epische/legendäre Skins können eigene Texturen
  bekommen (Ordner `Skins`). Fehlt etwas, bleibt die Quader-Waffe und Studio sagt im Output, was fehlt. Vorlagen
  für Blender (`.obj`) und Studio (`.rbxmx`) in `art/templates/Weapons`. Fertige Modelle aus anderen Quellen
  (z.B. Meshy-GLB) bereiten Skripte vor: `tools/attachments/ar15_v2.py` macht das Sturmgewehr `art/sources/Rifle.glb`
  (AR-15 ohne Aufsätze, Magazin als `Magazine`, Marker gesetzt; Aufsätze siehe `tools/attachments/README.md`), das alte
  Gewehr mit fest eingebautem Holo-Visier liegt noch als `art/sources/Rifle_alt.glb` (`tools/rifle_glb.py`); dafür `tools/fbx_read.py` (FBX ohne Blender lesen) und `tools/mesh_ops.py` (schneiden, Löcher
  schließen, GLB mit Texturen schreiben)
- **Agentenmodelle** (`src/shared/AgentModels.lua`, Anleitung [docs/agenten-modelle.md](docs/agenten-modelle.md)):
  Liegt in Studio unter ReplicatedStorage › Assets › Agents ein Modell mit dem Namen eines Agenten, sieht der Agent
  überall so aus: an Spielern (Hub, Markt, Match), an Bots und in allen Vorschauen (Agentenwahl, Lobby, Shop, Markt,
  Hub, Podest, HUD-Symbol) – **genau wie in Blender bzw. in einer leeren Experience**: nichts wird umgefärbt,
  gestreckt, zerlegt oder umgebogen. Ein **Rig** (Humanoid, HumanoidRootPart, R15-Gelenke, z.B. StarterCharacter
  oder Avatar-Setup) bleibt komplett (gehäutete Meshes, Bones, Accessoires, Layered Clothing), hängt am
  HumanoidRootPart des Spielkörpers und übernimmt jedes Bild dessen Gelenkbewegung (`AgentModels.SyncJoints` aus
  CharacterPose); beim Tod fällt es mit. **Starre Teile** ohne Rig hängen am Körperteil, mit dem ihr Name beginnt
  (`Head_Suit`, `LeftUpperArm_Suit`), sonst am nächsten; Boden = `Point_Root` oder der tiefste Punkt. Nur bei offensichtlich falscher
  Import-Einheit wird das ganze Modell auf 5,1 Studs gebracht. Der normale Agentenkörper bleibt unsichtbar als
  Trefferzone (alle Agenten gleich leicht zu treffen, Teile des Modells nie Trefferzone); macht etwas ihn wieder
  sichtbar oder tauscht Roblox Körperteile aus, blendet der Server ihn sofort wieder aus bzw. zieht neu an. Fehlt
  etwas, bleibt der Standard-Look und Studio sagt im Output, was fehlt (`[Agentenmodelle] …`)
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
    eine dezente Tastenzeile (in EXTINCTION ersetzt durch die Zeile unter der Hotbar mit Schießen, Nachladen, 1-9,
    Inventar, Interagieren, Fahrzeug und Karte)
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
  - Namensschild zum Angeben (Hub, Markt und Safe Zones in Extinction): flache Kachel im Stil der Hotbar mit
    Prestige-Abzeichen, Team-Rang (DEV, VIP …), Name, darunter Rang · RAP (kurz, z.B. 12.4K) · Titel
- **Kamera**: Ego oder Schulter (T), Schulter wechseln (X). Schulterkamera wie bei RC: Charakter links im Bild,
  das Fadenkreuz bleibt frei – auch beim Zielen, wenn die Kamera näher heranrückt; steht rechts eine Wand,
  rückt die Kamera seitlich an den Kopf statt durch die Wand zu schauen (Werte oben in `src/shared/Movement.lua`)
- **Bewegung** (`src/shared/Movement.lua`, Rechnungen und alle Werte in `src/shared/MovementPhysics.lua`):
  - Tempo läuft weich an (Gehen -> Sprint in gut 0,2 s) und schneller wieder ab; in der Luft hält der Schwung vom
    Absprung (Sprint loslassen bremst nicht mitten im Sprung)
  - **Rutschen** (im Sprint ducken, Tippen reicht): Schub aus dem aktuellen Tempo (+9), Reibung (flach ca. 1 s und
    20-30 Studs), bergab schneller und länger (bis 50 Studs/s), bergauf kürzer, mit WASD lenkbar (110°/s). Springen
    aus dem Rutschen nimmt den Schwung mit in die Luft; mit gehaltener Ducken-Taste landen = weiter rutschen. Der
    Schub lädt erst in 1,4 s wieder auf – Rutsch-Sprung-Ketten bleiben nahe am Sprinttempo
  - **Springen**: Coyote-Time (0,12 s nach dem Verlassen einer Kante geht der Sprung noch), Sprungpuffer (0,15 s vor
    dem Landen gedrückt = Sprung beim Landen), harte Landungen (ab ca. 18 Studs Fall) bremsen kurz
  - **Hindernisse**: Springen vor einem niedrigen, dünnen Hindernis (1,3-4,4 hoch, bis 4,5 tief) im Lauf = drüber
    (Vault, der Schwung bleibt), langsam oder an höheren Kanten (bis 7,8 über den Füßen) = hochziehen – auch aus dem
    Sprung heraus (Leertaste/✕ gehalten, auf die Kante zu; höchstens 9,5 über dem letzten Boden)
  - Kamera: Sichtfeld weitet sich beim Sprinten und noch mehr beim Rutschen, leichte Neigung beim Seitwärtslaufen
    und deutliche beim Rutschen, dezentes Wippen beim Laufen (Ego, höchstens 0,02 Studs), Eintauchen bei harten Landungen; in der Ego-Ansicht
    kippt die Waffe beim Rutschen weg. Ducken gleitet (Hüfte in 0,12 s)
- **Bewegungs-Check** (`src/server-shared/MovementGuard.lua`): Der Server vergleicht 5-mal pro Sekunde die
  zurückgelegte Strecke jedes Spielers mit dem erlaubten Tempo (waagerecht 62 Studs/s, nach oben 50, dazu ein
  Vorrat von 100 bzw. 40 Studs für Sprint-Stoß und Lag-Spitzen; Fallen ist frei). Wer schneller ist (Speedhack)
  oder springt (Teleport), wird an die letzte gültige Stelle zurückgesetzt, im Server-Log steht eine Warnung.
  Legale Bewegungen (Sprint mit allen Boni, Rutschen bergab mit 50 Studs/s, Rutsch-Sprünge, Vault, Hochziehen,
  Sprint-Stoß, Fallschirmsprung, Treppen, Lag bis ca. 1,5 s) liegen darunter. Versetzt der Server einen Charakter selbst, ruft er danach
  `MovementGuard.Teleported(character)` auf (macht `SpawnUtil.Spawn` schon)
- **Schießen wie bei Rogue Company**:
  - Schulterkamera: dynamisches Fadenkreuz (Abstand = echte Streuung durch Laufen, Springen, Dauerfeuer),
    zieht sich beim Zielen zu einem kleinen Kreuz zusammen, wird über Gegnern rot; Schrotflinte mit Kreis.
    Der Server sucht den Punkt unter dem Fadenkreuz und schießt vom Charakter aus dorthin – ist etwas im Weg,
    zeigt ein rotes ⊘ die Stelle
  - Ego-Perspektive: jede Waffe hat Kimme und Korn (mit Leuchtpunkt), das Sturmgewehr ein Rotpunktvisier (Gehäuse,
    Rahmen mit getöntem Glas, roter Punkt mittig im Fenster); beim Zielen liegt die Visierlinie genau
    in der Bildmitte; Waffe mit Armen, schwankt beim Umsehen, wippt beim Laufen nur leicht, gesenkt beim Sprinten, gekippt beim Rutschen
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

## Sprache

Das Spiel erscheint **standardmäßig auf Englisch (US)**. Der Code schreibt alle Texte weiter auf Deutsch; der Client
(`src/shared/Locale.lua`, Start in `ClientMain`) schlägt jeden Text, der in ein TextLabel, einen TextButton, den
PlaceholderText einer TextBox oder einen ProximityPrompt kommt (auch Schilder und Blasen in der Welt), in
`src/shared/LocaleStrings.lua` (Deutsch → Englisch, rund 2100 Einträge) nach und ersetzt ihn beim Setzen. Deutsch sehen
nur Spieler mit deutscher Roblox-Sprache (`Player.LocaleId` „de-…“) oder wer in OPTIONEN › ANZEIGE › **SPRACHE** DEUTSCH
wählt (AUTOMATISCH = Englisch, Deutsch nur bei deutscher Roblox-Sprache; die Wahl wirkt sofort auf alle Texte).
Einträge: `["SPIELEN"] = "PLAY"` für genaue Texte, `["Töte {1} Zombies"] = "Kill {1} zombies"` für zusammengesetzte
(Platzhalter {1}, {2} … für Zahlen und Namen; die Teile werden selbst noch einmal nachgeschlagen, z. B. „Verband“).
Texte ohne Eintrag bleiben, wie sie sind – darum stehen Ortsnamen (Nordheim, Ödstadt) und englische Texte nicht drin.
Eingetippter Text in Eingabefeldern wird nie angefasst. Der Server übersetzt mit `Locale.ForPlayer` nur, was nicht über
ein Textfeld läuft (Kick-Nachrichten).

Neue Texte: auf Deutsch in den Code schreiben und den Eintrag in `LocaleStrings.lua` ergänzen (Schlüssel = genau der
Text auf dem Bildschirm, bei `string.upper`/`UITheme.Upper` also die Großschreibung). `python3 tools/locale_scan.py`
listet deutsche Texte ohne Eintrag (`-v` alle einzeln); `tools/locale_merge.py` setzt Teil-Wörterbücher zusammen.
Test: `tests/locale.test.luau` (prüft auch, dass jedes Muster in beiden Sprachen dieselben Platzhalter hat).

## Spielanalyse (Analytics)

`src/server-shared/Telemetry.lua` schickt Spiel-Ereignisse an den Roblox **AnalyticsService** (Creator Hub › Analytics;
in Studio wird nichts gesendet, alles läuft über pcall):
- **Wirtschaft** (`LogEconomyEvent`): jede Münz- und RAP-Bewegung aus `ProgressService` – Quelle mit Grund (Zombie,
  Auftrag, XP, Robux = IAP, Markt/Verkauf = Shop …), Senke mit Grund und Item (`SpendCoins(player, amount, reason, sku)`:
  Stand, Skin, Agent, Versteck, Spielermarkt, Clan, Kiste) und dem Kontostand danach.
- **Onboarding-Trichter** (`LogOnboardingFunnelStepEvent`): 1 Beigetreten (Profil geladen), 2 Offene Welt betreten,
  3–8 die Tutorial-Schritte (der Client meldet `ExtAction "Tutorial", "Step", n`), 9 Tutorial fertig oder übersprungen.
  Jeder Schritt zählt je Spieler nur einmal (höchster Schritt im Profil `OnboardingStep`).
- **Ereignisse** (`LogCustomEvent`): `ModeJoin` (Modus), `PlayerKill` und `Death` in der offenen Welt (Ursache
  Spieler/Zombie, rote Zone oder nicht), `MissionDone` (Auftrag), `ZombieKills` gesammelt je Spieler (alle 60 s und
  beim Verlassen als Summe, damit nicht jeder Kill ein Aufruf ist).
- **Fortschritt** (`LogProgressionEvent`): Level-Aufstieg eines Agenten.
Neue Ereignisse: `Telemetry.Event(player, name, value, feld1, feld2, feld3)`. Test: `tests/telemetry.test.luau`.

## Freunde einladen und Badges

**Freunde einladen** (`src/shared/Invites.lua`, Knopf **FREUNDE EINLADEN** im Squad-Fenster der Lobby und der offenen
Welt): öffnet die Roblox-Einladung (SocialService). Tritt ein Freund über die Einladung bei (ReferredByPlayerId in seinen
Join-Daten), bekommt der Einladende, wenn er auf dem Server ist, `InviteService.Reward` Münzen (300), eine Meldung,
die Statistik `Invites` und beim ersten Mal das Badge ANWERBER; jeder Freund zählt nur einmal (Profil `Invited`).
Analytics-Ereignis `InviteJoin` (`src/server-shared/InviteService.lua`).

**Badges** (`src/shared/BadgeConfig.lua`, Server `src/server-shared/Badges.lua`): Willkommen (erster Beitritt),
Überlebenstraining (Tutorial fertig, nicht übersprungen), Anwerber (erster Freund über eine Einladung) und je ein Badge
für jeden Erfolg der Erfolge-Wand auf GOLD. IDs eintragen: Creator Hub › dein Spiel › Engagement › Badges anlegen und
die ID bei `BadgeId` einsetzen; solange sie 0 ist, wird das Badge im Profil vorgemerkt und beim nächsten Laden
nachgetragen (`Badges = { [Id] = true | "Pending" }`). Jedes Badge wird je Spieler nur einmal bei Roblox angefragt.
Test: `tests/badges.test.luau`.

## Sperrliste (Kick und Ban)

Admin-Panel (P) › Reiter **SPIELER**: oben das Feld **Grund** (sieht der Spieler), daneben Sperren per **UserId** (auch
für Spieler, die nicht auf dem Server sind), die **Sperrliste** mit ENTSPERREN und AKTUALISIEREN, darunter jeder
Spieler des Servers mit **KICK**, **BAN 1 TAG**, **BAN 7 TAGE**, **BAN DAUERHAFT**. `src/server-shared/BanService.lua`:
Sperren liegen im DataStore `Bans_v1` (Schlüssel `List`: UserId → Name, Grund, Ablauf, von wem, wann), jeder Server
lädt die Liste beim Start und jede Minute neu, Änderungen gehen sofort per MessagingService („Bans“) an alle Server;
gesperrte Spieler werden beim Beitreten gekickt (Nachricht in ihrer Sprache mit Grund und Restzeit). Zusätzlich
`Players:BanAsync`/`UnbanAsync` (Sperre von Roblox, wirkt auch gegen Zweitkonten; fehlt das, greift die Liste allein).
Gründe laufen durch den Textfilter. Aktionen (`AdminService`): `Kick`, `Ban` (UserId, { Days, Reason }), `Unban`,
`BanList` → `Remotes.AdminData "Bans"`. Test: `tests/bans.test.luau`.

## Steuerung

WASD/Leertaste · Shift Sprint · STRG/C Ducken (im Sprint: Rutschen, Springen daraus nimmt den Schwung mit) ·
Springen vor Hindernissen: drüber (im Lauf) oder hochziehen ·
Linksklick Schießen · Rechtsklick Zielen · R Nachladen · X Waffe inspizieren · 1/2 Waffe · V Messer · Q Fähigkeit ·
G Gadget · F Ultimate · E Wiederbeleben/Bombe · Z Ping · T Kamera (Ego/Schulter) · H Schulter wechseln · Tab Punkte ·
M Menü (im Hub; im Match: VERLASSEN-Knopf unter der Minimap) · P Admin-Panel · B Noclip (nur Admins: frei fliegen durch Wände, WASD + Leertaste/Strg, Shift schneller, kein Schaden) · 4/5/6 Killstreaks (Herrschaft)

In EXTINCTION: 1-9 Hotbar benutzen (Waffe, Heilung, Fahrzeug) · TAB Menü (Inventar) · M Menü (letzter Reiter) · E Stand/Lager/Tasche/Mitfahren ·
K Fahrzeug einpacken · N Weltkarte · J Squad · Z Ping (nur an den Squad) · im Fahrzeug W/S/A/D, Leertaste aussteigen ·
im Helikopter W/S/A/D, Leertaste steigen, Shift sinken, F aussteigen ·
Controller: siehe Konsole · Touch: Hotbar-Plätze antippen,
Knöpfe TASCHE (Inventar), PARKEN (Fahrzeug einpacken), WAFFE (nächste Waffe der Hotbar)

Konsole (Controller, Tasten im PlayStation-Stil): R2 Schießen · L2 Zielen · □ Nachladen bzw. Wiederbeleben/Bombe
(bei vollem Magazin: inspizieren) · △ Waffe wechseln · R3 Messer · L1 Fähigkeit · R1 Gadget · L1+R1 Ultimate ·
L3 Sprint · ○ Ducken · ↑ Ping · ← Kamera · → Schulter bzw. Killstreak · ↓ Menü · Touchpad/Select Punkte ·
beim Zuschauen L1/R1 voriges/nächstes Teammitglied.
In EXTINCTION tragen drei Tasten zwei Belegungen, kurz antippen bzw. gedrückt halten (ab 0,35 s,
`InputActions.HoldTime`): **↑** Ping / halten Weltkarte · **Select** Inventar / halten Squad ·
**△** heilen (Medikit, wenn mindestens 50 Leben fehlen, sonst Verband, sonst ein anderes Heil-Item der Hotbar) /
halten Fahrzeug parken; dazu R1/L1 Waffe der Hotbar. Die Tastenzeile zeigt das als z. B. „↑ HALTEN  KARTE“.
Menüs und Fenster (Markt, Tausch, Kisten, Inventar, ...): beim Öffnen springt die Controller-Auswahl auf den ersten
Knopf (das Schließen-Kreuz wird übersprungen), Steuerkreuz/Stick wählen, ✕ drückt, ○ schließt.

Handy (Touch): Stick links, Knöpfe rechts (FEUER, ZIELEN, SPRUNG, DUCKEN, LADEN, FÄHIGK., GADGET, MESSER, WAFFE,
AKTION), oben rechts PING, PUNKTE, KAMERA, ULT, INSPEKT, links SPRINT; in EXTINCTION TASCHE und PARKEN statt
Fähigkeit/Gadget, im Helikopter STEIGEN/SINKEN und RAUS. Beim Zuschauen unten **ZURÜCK** / **WEITER** (voriges/nächstes
Teammitglied).

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
| Anzeigesprache (Englisch Standard): Wörterbuch Deutsch → Englisch | `src/shared/LocaleStrings.lua`, Technik `src/shared/Locale.lua` |
| Spielanalyse (AnalyticsService), Sperrliste (DataStore `Bans_v1`) | `src/server-shared/Telemetry.lua`, `src/server-shared/BanService.lua` |
| Badges (IDs aus dem Creator Hub), Einladungs-Belohnung | `src/shared/BadgeConfig.lua`, `InviteService.Reward` in `src/server-shared/InviteService.lua` |
| Medaillen (Name, Stufe, Bonus-XP) | `src/shared/Medals.lua`; Auslöser (Mehrfach-Kill-Fenster, Weitschuss, Comeback, Serie beendet) oben in `src/server-shared/KillService.lua`, Münzen der Kill-Boni in `src/shared/RewardConfig.lua` |
| Meldungen (Medaillen, Banner, Ziel-Meldungen, Level-Karte: Position, Standzeit, Farben, Klang) | `src/shared/Notifications.lua` |
| Third-Person-Haltung (Schulteranschlag, Ellbogen) und Anlegen beim Zielen | `HIP_POCKET`, `RIGHT_POLE*`, `ADS_*` in `src/shared/CharacterPose.lua` |
| Größe der Waffe in der Hand (Third-Person) | `GunModels.ToolScale` in `src/shared/GunModels.lua` |
| Körperbau aller Charaktere (Breite/Tiefe) | `AgentConfig.BodyScale` in `src/shared/AgentConfig.lua` |
| Agenten-Körper: Standard-Look (Hautfarbe, Gesicht, Agentenfarben), Körper-Beschreibung | `src/server-shared/AgentBody.lua` |
| Agentenmodelle (genau wie in Blender): Anleitung, Prüfungen | `docs/agenten-modelle.md`; Lader in `src/shared/AgentModels.lua` |
| Waffenmodelle (Blender): Marker, Teilnamen, Skins, Prüfungen | `docs/waffen-modelle.md`; Lader in `src/shared/GunModels.lua` |
| Vorgaben für alle 3D-Modelle (Waffen, Fahrzeuge, Items, Agenten) | `docs/3d-richtlinien.md`; Vorlagen in `art/templates` |
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
| Bewegung (Sprint, Rutschen, Sprünge, Vault, Hochziehen, Kamera-Neigung) | `src/shared/MovementPhysics.lua` |
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
| Markt: Gebührenstufen, Gegenangebote (Mindestgebot, Dauer), Stand-Name, Merkliste, Preisverlauf (Tage, Einträge, Speichern/Neuladen) | `FeeTiers`, `MinOfferFraction`, `OfferSeconds`, `StandNameLength`, `WatchLimit`, `HistoryDays`, `HistoryShards`, `HistoryFlush`, `HistoryRefresh` in `src/shared/RapConfig.lua` |
| Markt-Stände (Reichweite zum Beanspruchen/Kaufen) | `ClaimRange`, `BuyRange` in `src/server-shared/MarketService.lua`; Halle in `build_market()` in `tools/build_maps.py` |
| Glücksrad: Felder, Gewichte, Farben | `LoginConfig.Wheel` in `src/shared/LoginConfig.lua`; Dreh-Dauer und Runden in `src/client/HubWheel.lua` |
| Killstreaks (Kills, Namen, Farben) | `src/shared/KillstreakConfig.lua`; Anzeige in `src/client/KillstreakHUD.lua` |
| Battle Pass | `src/shared/PassConfig.lua` |
| Tägliche Aufträge | `src/shared/QuestConfig.lua` |
| Ränge (Ranked) | `src/shared/RankConfig.lua` |
| Live-Einstellungen (auch im Admin-Panel) | `src/shared/GameSettings.lua` |
| Modi im Menü | `src/shared/Modes.lua` |
| Arcade über mehrere Server: Modi, Meldeintervall, Verfall, Wartezeiten | `Modes.Matchmaking` in `src/shared/Modes.lua`; an/aus: Einstellung `CrossServer` |
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
  Gamepässe (`RobuxConfig.Passes`): VIP, DOPPEL-XP und ALLES LOOTEN – die PassId aus dem Creator Hub eintragen, dann
  zeigt der Shop den Preis und prüft den Besitz beim Beitreten und nach dem Kauf.

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
| `pose`, `pose_r6`, `rig` | Third-Person-Haltung: Waffe im Anschlag, Hände an der Waffe; Gelenk-Erkennung (Motor6D und Avatar Joint Upgrade), R6; ganzer Charakter ohne Waffe: Arme nicht seitlich abgespreizt |
| `viewmodel` | Ego-Waffe: Kimme und Korn beim Zielen genau in der Bildmitte |
| `minimap`, `modes` | Minimap-Zuschnitt auf den Kreis, Modus-Liste |
| `session` | Sitzungssperre der Spielstände (Serverwechsel, Absturz, DataStore-Fehler) |
| `progress` | Spielstand laden/speichern mit Sperre, Robux-Käufe erst nach dem Speichern bestätigt, Kick bei Ladefehler, Speichern beim Herunterfahren |
| `medals` | Medaillen im KillService (Mehrfach-Kill, Serien, Rache, Weitschuss, ...), mit beiden Signal-Modi von Roblox |
| `backweapon` | Rückenwaffe im Hub: Lage hinter dem Rücken für alle Primärwaffen, folgt Agent, Waffenwahl und Skin, weg im Kampfmodus und beim Tod |
| `settings`, `hitfeedback` | Einstellungen speichern (auch AUS-Werte), Stilwahl; alle Hitmarker- und Schadenszahl-Stile laufen durch und räumen auf, Kombo-Ton, Vorschau |
| `movement` | Bewegungs-Check: legale Bewegungen (Sprint, Rutschen bergab, Rutsch-Sprünge, Vault, Hochziehen, Sprint-Stoß, Fallschirm, Lag) nie zurückgesetzt, Speedhacks und Teleports schon |
| `movementfeel` | Bewegungsgefühl: Tempo-Rampe, Rutschen (Schub, Reibung, Hang, Lenken, keine Tempo-Ketten), Rutsch-Sprung mit Schwung, Schwung in der Luft, Coyote-Time, Sprungpuffer, harte Landung, Vault über dünne Mauern, Hochziehen (auch aus dem Sprung), zu hohe Wände nicht, Kamera-Neigung nur bei Roblox-Kamera |
| `economy` | RAP: alte Spielstände, Stückzahlen und Duplikate, Rückverkauf ans System (Skin weg und abgelegt, RAP drauf, gespeichert), Reservierungen, Austausch mit Marktgebühr (alles oder nichts) |
| `maps` (tests/maps_check.py) | Markt-Karte: Teile, die Server und Client suchen (Such-Terminal, Kisten-Automat, Tafeln, Portal), Spawns auf dem Platz, Stände lückenlos mit Prompt und Ausstellplätzen, alle zur Mitte gerichtet, nicht zu dicht, drei Ränge |
| `tradeui` | Tausch-Oberfläche: Spielerliste mit T, Entfernung, Anfrage, zu weit weg gesperrt, Hinweis nur im Hub/Markt, Esc schließt |
| `padhold`, `extinctionpad` | Controller antippen/halten: kurz = Antippen-Aktion beim Loslassen, lang = Halten-Aktion bis zum Loslassen, Tasten ohne Halten sofort, Hinweis „△ HALTEN“; EXTINCTION-Belegung (↑ Ping/Karte, Select Inventar/Squad, △ heilen/parken) mit echten Tasten, Heil-Item-Wahl (Medikit/Verband/anderes, Meldung ohne), außerhalb der offenen Welt normale Belegung |
| `spectatortouch`, `tradefocus` | Zuschauen auf dem Handy: Knöpfe ZURÜCK/WEITER wechseln das Ziel, nur auf Touch, weg nach Respawn; Controller-Auswahl in der Tausch-Spielerliste: erster Knopf statt Schließen-Kreuz, bleibt nach dem Neuaufbau im Fenster, weg beim Schließen |
| `crate`, `crateui` | Kisten: nur die Waffen-Kiste (alle handelbar), steile Chancen (62/28/8/2 %), Öffnen (Ort, Münzen, Wartezeit), weitere Stücke, Rolle mit dem Gewinn an festem Platz; Fenster mit Rolle, Gewinn-Karte, NOCHMAL |
| `marketsearch` | Marktsuche: Text (ohne Umlaute, mehrere Wörter), Filter (Seltenheit, Höchstpreis), Sortierung (Preis, Schnäppchen, Seltenheit) |
| `market2` | Markt Teil 2: Gebühr nach Preis, Gegenangebote (annehmen, ablehnen, zurückziehen, Ablauf, Preisänderung), Stand-Name, Merkliste samt Meldung, Preisverlauf (gesammelt und verteilt gespeichert, ein Schreibzugriff je Eintrag, Fehler und Herunterfahren, Verkäufe anderer Server, alte Einträge lesen), Händler-Rangliste |
| `marketui`, `marketui2` | Markt-Oberfläche im Simulator: Suche, Stand-Fenster, Gegenangebote, MEIN STAND mit Stand-Name, Tafeln |
| `market` | Markt: Stand beanspruchen (Markt, Nähe, einer pro Spieler), anbieten (handelbar, freie Stücke, höchstens sechs), Preis ändern, kaufen (Nähe, gesehener Preis, RAP, Gebühr, gespeichert), Stand frei beim Verlassen |
| `skins` | Nur noch Waffen-Skins: keine Agenten-Skins (Cosmetics, RAP, Kisten), Agentenfarben immer Standard, Battle-Pass-Stufe 20 = Saison-Elite, alte Spielstände verlieren entfernte Skins (Besitz, Plätze "A:", Merkliste), SHOP/LOADOUT/BATTLE PASS ohne Agenten-Skins |
| `trade` | Tauschen: Anfrage (Hub/Markt, Nähe), ablehnen, ablaufen, annehmen, gegenseitig, Angebote, BEREIT + Countdown, Änderung nimmt BEREIT zurück, Abschluss gespeichert, Abbruch bei Knopf/Moduswechsel/Verlassen, fehlgeschlagener Tausch ändert nichts |
| `hubholo` | Holo-Schrift „Agent der Woche“: hängt über der Statue, bleibt nach dem Respawn, blendet in Kameranähe aus (rausgezoomt daneben, steil von oben), weiter weg voll sichtbar |
| `agentbody` | Agenten-Körper: gleiche Beschreibung für Spieler und Bots, Avatar-Teile weg, Standard-Look in Agentenfarben mit Roblox-Gesicht (keine Quader), Agentenwechsel im Hub sofort, Rückfall auf den normalen Charakter; Accessoires nie Trefferzone (auch nicht als gemeldeter Treffer) |
| `weaponmodels` | Waffen-Lader: gedreht importierte Modelle werden an den Markern ausgerichtet, Ruhelage, Gruppen, Drehpunkte, Skin-Zonen und Textur-Skins, Aufsätze, Werkzeug, Zielen, Nachladen; kaputte Modelle bleiben mit klarer Meldung Quader |
| `rbxmx`, `templates` | Studio-Dateien (.rbxmx) einlesen; alle Blender-Vorlagen sind selbst gültige Modelle |
| `weaponassets` | deine Modelle in `assets/Weapons` gegen die Spezifikation (laden ohne Fehler, Textur-Skins passen); mit ihnen laufen auch weapons, viewmodel und pose |
| `agentmodels` | Agenten-Lader mit den Maßen von Viper_3.glb (15 Teile `<Körperteil>_Suit`, Haare): jedes Teil sitzt, liegt und ist so groß wie im Modell, Farbe/Material/Textur unverändert, Teile ohne Körperteil-Namen am nächsten Körperteil, ohne `Point_Root`, falsche Einheit, Prüfmeldungen, Neuladen; Spieler, Bots und Menü-Figur tragen das Modell |
| `agentcharacter` | Agentenmodell als Rig gedreht importiert: bleibt komplett (Gelenke, Rig-Attachments, Bones, Humanoid ohne Steuerung, keine Skripte), Füße auf dem Boden, Blick nach vorne, am Spielkörper angeschweißt, Gelenke übernehmen die Bewegung (auch nach Austausch), beim Tod angeschweißt, Figur mit Waffe in seiner Hand; der Server hält den Spielkörper unsichtbar und zieht neu an, wenn Roblox Teile austauscht |
| `agentclient` | Agenten-Modelle auf dem Client: kein Warten beim Start, wenn Assets.Agents fehlt; später ankommende Ordner und Modelle werden geladen |
| `agentassets` | deine Modelle in `assets/Agents` gegen die Anleitung (laden ohne Fehler, jedes Teil angeschweißt und nie Trefferzone, Spielkörper unsichtbar) |
| `wheel` | Glücksrad: Rad hält auf dem ausgelosten Feld (alle Felder, mit Versatz), Dreiecke aus Keilen, Aufbau und Drehrichtung, Drehen nur im Hub am Rad |
| `hud` | Match-HUD: eigenes Porträt liegt über seiner Kachel (sonst unsichtbar), allgemeine Tastenzeile nicht in EXTINCTION, Killfeed in der roten Zone unter der Redzone-Rangliste; Minimap: rote Zone als Punktkreis, zieht bei jedem Wechsel mit, Rand drinnen rot; eigene Todestasche als rotes X (weit weg am Rand) |
| `movingzone`, `redzones` | Rote Zone: genau eine, Ziele aus den Orten der Karte (ohne Camp, große Flächen, Safehouses, Wasser), Wechsel nach 20 Minuten mit Ansage vorher, nie derselbe Ort und möglichst weit weg, Attribut `Redzones`, rote Wand; drinnen PvP sofort, mehr Zombies mit Läufern und Brocken, Obergrenze mit Bonus; zieht sie weiter, ist man am alten Ort draußen und am neuen mit Meldung wieder drin |
| `extmarket`, `extmarketui` | Spielermarkt: nur in der Safe Zone (auch weit weg vom Stand), Anbieten (Waffe mit Magazin, Teil eines Stapels, kein draußen stehendes Fahrzeug, Preisgrenzen, höchstens 8), Kaufen zum gesehenen Preis mit Münzen und Platz, nicht das eigene, Gebühr, keine VIP-Verdopplung, Preis ändern (nur eigenes, Grenzen, At bleibt), Zurücknehmen, Angebote überleben Tod und Verlassen; Seite im Spiel: E am Stand öffnet MARKT, Vorschlag für Anzahl und Preis, Erlös nach Gebühr, ANBIETEN, Preis ändern, fremde mit KAUFEN, Kategorien, weg vom Stand offen, außerhalb der Safe Zone gesperrt |
| `extmarketpage` | Markt-Seite für sich (Mock): Suche, Kategorien, Sortierung, Karten, KAUFEN/ZU TEUER, MEINE ANGEBOTE (Preis ändern, zurücknehmen), Verkaufen mit ±, Schieberegler, günstigstem Angebot und Erlös, Sperre außerhalb der Safe Zone |
| `extinctionmenu` | Menü der offenen Welt: TAB/M öffnen und schließen, Reiter in der Reihenfolge, Lobby-Seiten ausgeliehen, verkleinert und zurückgegeben, Controller L1/R1 rundum, Auswahl im Inhalt, ○ schließt |
| `matchmaking` | Arcade über mehrere Server: eigene Meldung (nur Arcade-Modi, verfällt), Wechsel auf einen Server mit mehr echten Spielern (nicht auf volle, nicht bei Gleichstand, nicht zu einem anderen Place, Platz für den ganzen Squad), Teleport-Daten, Squad geht zusammen und folgt hier, Fehlschlag sofort / TeleportInitFailed / Zeitüberschreitung: hier spielen und eine Weile nicht weiterschicken, SCHNELLES SPIEL sieht andere Server, Hub/Extinction/Markt bleiben, Einstellung aus, Ankunft direkt im Modus mit Squad (nur gegenseitig, kein fremder Place), verfallene Server, MemoryStore gestört, Herunterfahren |
| `squads` | Squads der offenen Welt: Einladen/Annehmen setzen dieselbe SquadId, kein Friendly Fire, Schaden an anderen schon, Pings nur an den Squad (nicht an andere, im Free-for-All nicht), Squad-Mitglied kein gepingter Gegner, Anführer verlässt die offene Welt: Squad bleibt, betritt sie: Squad kommt mit, Verlassen löst auf |
| `antizombie` | Anti-Zombie-Spritze: Itemstand und Beute, Benutzen setzt den Schutz (keine anderen Wirkungen), zweite Spritze erst nach Ablauf; bei dem Spieler spawnt kein Zombie (auch nicht über Rufe, Begleiter, direkte Spawns), bei anderen schon, vorhandene bleiben; nach Ablauf und nach dem Tod wieder normal |
| `redloot` | Beute der roten Zone: Tabelle eine Stufe besser, ein Item mehr, größere Stapel (nie über MaxStack), Zombies dort mit doppelten Münzen und mehr Beute, Lager mehr Items, Lootdrop dort mehr Items, beim Wechsel Lootdrop in die neue Zone (nur mit Spielern draußen, nie zwei) |
| `extbots` | Bots der offenen Welt: Spawn beim Admin (draußen, vor dem Rand der Safe Zone, sonst rote Zone), Ziele (Spieler draußen ja, in der Safe Zone nein, andere Bots nein, nahe Zombies ja), Zombies jagen und schlagen Bots, Tasche mit Waffe, Munition und Beute (rote Zone Tier 3), Kopfgeld und Rangliste nur für Spieler-Kills, Leiche weg, Obergrenze, Admin-Befehle |
| `tutorial` | Tutorial der offenen Welt: Karte für neue Spieler (nicht für alte), SKIP merkt sich der Server, Start aus dem GUIDE, alle sechs Schritte warten, bis sie erledigt sind, Wegpunkt zum nächsten Kit-Händler, Tafel aus bei offenem Menü und außerhalb der offenen Welt |
| `redzoneboard`, `extinctionui` | Squad-Fenster (J, Einladen, Einladung annehmen, Verlassen), Squad-Liste im HUD, Squad = Team (TeamCheck); Redzone-Rangliste: eine Liste pro Runde, nach 20 Minuten (Wechsel) wieder bei null mit dem neuen Ort, Kill zählt in der Zone des Opfers bzw. des Schützen, Gleichstand, Verlassen; Oberfläche der offenen Welt: Rangliste nur in der roten Zone, rote Zeile unter der Uhr (Ort, Wechsel, Entfernung), Kreis auf der Weltkarte zieht mit, Aufträge unter VERLASSEN, eine Tastenzeile unter der Hotbar (Tastatur und Controller), Weltkarte ohne Namen für Tankstellen und Seen, Hinweis-Blasen über allen Ständen, Lager und Haltestelle (Titel, Symbole der Ware, Waffen als 3D-Modell, von weitem sichtbar, außerhalb der offenen Welt aus) |

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
- `tools/asset_templates.py` – erzeugt die Blender-Vorlagen der Fahrzeuge (aus dem Spiel, `art/templates/Vehicles`)
  und der Items, Gadgets und Behälter (Zielgrößen, `art/templates/Items`)
- `docs` – Anleitungen: Vorgaben für alle 3D-Modelle (`3d-richtlinien.md`), Waffenmodelle aus Blender
  (`waffen-modelle.md`), Agentenmodelle (`agenten-modelle.md`)
- `assets/Weapons`, `assets/Agents` – Kopien deiner Waffen- und Agentenmodelle (.rbxmx) für die automatische
  Prüfung (das Spiel lädt die Modelle aus dem Place, siehe docs/waffen-modelle.md und docs/agenten-modelle.md)
- `tools/sourcemap.py` – Sourcemap für luau-lsp (wie `rojo sourcemap`, ohne Rojo)
- `tools/locale_scan.py`, `tools/locale_merge.py` – Übersetzung: fehlende Texte finden, Wörterbücher zusammensetzen
- `tests` – Tests und Roblox-Nachbildung (`tests/run.py` startet sie, `tests/lib/rbxmx.py` liest Studio-Modelle,
  `tests/fixtures` Beispieldateien), `.github/workflows` – automatische Prüfung

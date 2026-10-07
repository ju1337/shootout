# 3D-Richtlinien: Waffen, Fahrzeuge, Items und Agenten

Für alle, die 3D-Modelle für das Spiel bauen (Blender, Meshy oder andere Werkzeuge). Ziel: Jedes Modell geht **ohne
Nacharbeit** ins Spiel. Ein Modell, das diese Regeln erfüllt, wird direkt eingebaut. Ein Modell, das sie nicht
erfüllt, kommt mit einer Liste der Punkte zurück, damit es nicht jedes Mal von Hand repariert werden muss.

Waffen und Agenten haben zusätzlich je eine eigene, ausführliche Anleitung: [waffen-modelle.md](waffen-modelle.md)
und [agenten-modelle.md](agenten-modelle.md).

## Auf einen Blick

1. **Um die Vorlage herum bauen.** Für jedes Modell gibt es eine Vorlage in Originalgröße
   (`art/templates/<Kategorie>/<Id>.obj`). Sie legt Größe, Lage, Boden und Vorderseite fest.
2. **1 Blender-Einheit = 1 Stud.** Nicht nach echten Metern bauen, sondern nach den Stud-Maßen in diesem Dokument.
3. **Vorne ist vorne:** Die Vorderseite zeigt in Blender in der Vorderansicht (Numpad 1) zu dir, oben ist +Z, der
   Boden liegt auf Höhe 0. Die Vorlagen liegen schon so.
4. **Export mit den Roblox-Einstellungen** (Abschnitt 2), Probelauf einmal am Anfang.
5. **Was sich bewegt, leuchtet, durchsichtig ist oder umgefärbt wird, ist ein eigenes Objekt.** Alles andere wird zu
   einem Objekt zusammengefügt.
6. **Namen genau wie in den Listen** (englische Wörter mit `_`, keine Leerzeichen, keine Umlaute).
7. **Marker** (kleine Würfel `Point_…`, `Pivot_…`, `Seat_…`) aus der Vorlage übernehmen und an die richtige Stelle
   schieben.
8. **Budget einhalten:** Dreiecke, Anzahl Teile und Texturgröße (Tabelle in Abschnitt 3).
9. **Saubere Geometrie:** geschlossen, Normalen nach außen, keine doppelten Flächen, keine verschmolzenen beweglichen
   Teile.
10. **Ein Textur-Set pro Modell** (PBR: Farbe, Normal im OpenGL-Format, Rauheit, Metall) als PNG.
11. **Keine echten Marken, Logos oder geschützten Zeichen.**
12. **Liefern** mit `.blend`, Export (FBX oder GLB), Texturen, Vorschaubild und ausgefüllter Checkliste
    (Abschnitt 8).

## 1. Arbeiten mit Vorlagen

| Kategorie | Vorlagen | Inhalt |
|---|---|---|
| Waffen | `art/templates/Weapons/<Waffe>.obj` | heutige Quader-Waffe mit allen Markern (siehe [waffen-modelle.md](waffen-modelle.md)) |
| Fahrzeuge | `art/templates/Vehicles/<Id>.obj` | heutiges Spielfahrzeug: Rumpf `Ref_Chassis`, Räder `Wheel_*`, Sitze `Seat_*`, Boden `Ref_Ground`; Helikopter: Drehpunkte `Point_Rotor`, `Point_TailRotor` |
| Items, Gadgets, Behälter | `art/templates/Items/<Id>.obj` | Zielgröße `Ref_<Id>` (Boden bei 0) und Griff `Point_Grip` |

So gehst du vor:

1. Vorlage in Blender importieren (Einstellungen in Abschnitt 2).
2. Dein Modell um die Vorlage herum bauen. Alles mit `Ref_` ist nur Maßstab und wird vor dem Export gelöscht. Agenten
   haben keine Vorlage, sie werden nach den Körpermaßen gebaut (Abschnitt 7).
3. Teile benennen und die Marker (magenta Würfel) übernehmen.
4. Texturieren.
5. Exportieren (Abschnitt 2), wenn möglich in Studio testen, liefern (Abschnitt 8).

Fehlt eine Vorlage, zum Beispiel für ein neues Fahrzeug oder eine neue Waffe: vorher Bescheid geben. Dann gibt es
zuerst die Werte im Spiel und eine Vorlage. Erst danach modellieren.

## 2. Einstellungen in Blender und Studio

Diese Einstellungen stammen aus der offiziellen Roblox-Anleitung. Einmal einstellen und immer benutzen.

**Vorlage importieren (Blender):** Datei › Importieren › Wavefront (.obj), rechts unter *General*:

- Scale **1**
- Forward Axis **Z**
- Up Axis **Y**

**Exportieren (Blender):** Datei › Exportieren › FBX (.fbx):

- Include: **Limit to Selected Objects** (nur die Teile des Modells samt Markern auswählen)
- Transform: **Apply Scalings = FBX Unit Scale**, **Forward = Z Forward**, **Up = Y Up**
- alles andere Standard, Skalierung 1,0; keine Animation mit exportieren

Ohne „FBX Unit Scale“ kommt das Modell in Studio 100-mal zu groß an. Alternativ geht **glTF 2.0 (.glb)** mit
„Selected Objects“ und „+Y Up“; dort gibt es das Größenproblem nicht.

**Importieren (Studio):** Import 3D, im Fenster:

- World Forward **Front**, World Up **Top**
- Scale Unit **Stud**
- **Merge Meshes AUS** (sonst werden alle Teile zu einem verschmolzen, Marker und bewegliche Teile gehen verloren)

**Probelauf (einmal, ca. 10 Minuten):** eine Vorlage importieren, sofort wieder exportieren und in Studio
importieren. Stimmen Größe und Richtung (das Sturmgewehr ist 4,13 Studs lang, der Quad-Rumpf 6,6 Studs lang, vorne
zeigt nach vorne), passen deine Einstellungen. Wenn nicht, erst die Einstellungen reparieren, dann modellieren.

## 3. Regeln für alle Modelle

### Maßstab und Lage

- **1 Blender-Einheit = 1 Stud.** Die Spielwelt hat eigene Proportionen: Ein Agent ist etwa 5 Studs groß, und
  Waffen sind bewusst größer als in echt. Maßgeblich sind die Vorlagen und Tabellen, nicht echte Meter.
- **Vorderseite** in Blender zur Vorderansicht (Numpad 1), **oben = +Z**, **Boden = Höhe 0**. Mit den
  Export-Einstellungen oben ist das in Roblox richtig (vorne = −Z).
- **Rotation und Skalierung anwenden** (Strg+A › Rotation & Skalierung). Keine negativen Skalierungen.
- Das Modell bleibt dort stehen, wo die Vorlage steht. Nicht verschieben, nicht drehen.

### Geometrie

- **Geschlossen** (keine Löcher), **Normalen nach außen** (Blender: Overlays › Face Orientation, alles blau),
  keine doppelten Punkte (Merge by Distance), keine doppelten oder versteckten inneren Flächen, keine losen
  Einzelpunkte.
- Roblox zeigt Flächen **nur von vorne**. Dünne Teile wie Riemen, Planen oder Blätter bekommen eine Dicke, sonst
  sind sie von hinten unsichtbar.
- Vierecke oder Dreiecke. Keine Flächen mit 5 oder mehr Ecken.
- Höchstens **20.000 Dreiecke pro Objekt** (Grenze von Roblox). Die Budgets unten liegen weit darunter.

### Teile, Namen, Materialien

- **Eigene Objekte** nur für Teile, die sich bewegen, leuchten, durchsichtig sind oder eine eigene Farbzone haben.
  Alles andere in Blender zusammenfügen (Strg+J). Jedes zusätzliche Objekt kostet Leistung auf Handys.
- **Ein Material pro Objekt.** Roblox kann pro Teil nur eines. Mehrere Materialien also auf eine Textur backen oder
  in eigene Objekte trennen.
- **Namen** bestehen aus englischen Wörtern mit `_` dazwischen, genau wie in den Listen dieses Dokuments.
  Groß-/Kleinschreibung zählt, die Reihenfolge der Wörter nicht. Keine Leerzeichen, Umlaute oder Sonderzeichen.
  Blender-Endungen wie `.001` sind egal.
- Wörter, die überall gelten:

| Wort | Bedeutung |
|---|---|
| `Glass` | durchsichtig (Scheiben, Visiere) |
| `Neon` | leuchtet (Lampen, Leuchtpunkte, Displays) |
| `Skin` (Waffen), `Paint` (Fahrzeuge) | Farbzone: wird vom Spiel bzw. vom Skin umgefärbt (Agenten werden nie umgefärbt) |
| `Ref` | nur Maßstab aus der Vorlage: vor dem Export löschen |

### Marker

- Marker sind **kleine Würfel**. Die Größe ist egal, nur ihre **Mitte** zählt. Im Spiel werden sie unsichtbar.
- Namen genau wie angegeben: `Point_…` (Punkte), `Pivot_…` (Drehpunkte), `Seat_…` (Sitze).
- **Keine Empties** benutzen: Sie kommen beim Import nicht an. In Studio gehen statt Würfeln auch Attachments mit
  demselben Namen.

### Texturen (PBR)

- **Ein Textur-Set pro Modell** (alle Teile auf einer Textur, „Atlas“):

| Textur | Format | Dateiname |
|---|---|---|
| Farbe (Albedo) | RGB | `<Id>_Color.png` |
| Normal | RGB, **OpenGL-Format, Tangent Space** | `<Id>_Normal.png` |
| Rauheit (Roughness) | Graustufen | `<Id>_Roughness.png` |
| Metall (Metalness) | Graustufen | `<Id>_Metalness.png` |
| Leuchten (optional) | Graustufen | `<Id>_Emissive.png` |

- **Normal Map im OpenGL-Format.** Substance Painter exportiert standardmäßig DirectX: dort auf „OpenGL“
  umstellen. Sonst sehen alle Beulen falsch herum beleuchtet aus.
- **Kein eingebackenes Licht und keine Schatten** (Ambient Occlusion nur leicht). Das Licht macht das Spiel.
- **Farbzonen** (`Skin`, `Paint`, `Primary`, `Accent`): Die Flächen, die das Spiel umfärbt, sind in der Farbtextur
  **durchsichtig** (Alpha 0). Details wie Kratzer, Kanten, Schrauben und Schrift bleiben deckend. Rauheit, Metall
  und Normal wirken trotzdem.
- PNG. Größe nach der Budget-Tabelle. Roblox kann bis 4096 × 4096, aber größere Texturen bringen auf Handys nichts
  und werden dort ohnehin verkleinert.

### Budget (Handys)

| Modell | Dreiecke (ganzes Modell) | Objekte | Textur |
|---|---|---|---|
| Lange Waffe | 3.000 – 6.000 | ≤ 20 | 1024 × 1024 |
| Pistole, Revolver | 2.000 – 3.500 | ≤ 12 | 512 × 512 |
| Auto (Geländewagen, Sportwagen) | 6.000 – 12.000 | ≤ 25 | 1024 × 1024 |
| Quad | 3.000 – 6.000 | ≤ 15 | 1024 × 1024 |
| Fahrrad | 1.500 – 3.000 | ≤ 10 | 512 × 512 |
| Item (Heilung, Munition, Spritze, Weste) | 200 – 1.200 | ≤ 3 | 256 × 256 bis 512 × 512 |
| Gadget (Granaten, Sensor-Mine) | 300 – 800 | ≤ 3 | 256 × 256 |
| Behälter (Taschen, Kisten) | 500 – 2.500 | ≤ 5 | 512 × 512 (Airdrop 1024 × 1024) |
| Agent | so wenig wie möglich | ≤ 40 (sonst Hinweis) | 1024 × 1024 |

Man sieht jedes Modell oft gleichzeitig: Jeder Spieler und jeder Bot trägt Waffe und Ausrüstung, und auf der Karte
stehen viele Fahrzeuge.

### Stil

- **Realistisch-taktisch, leicht vereinfacht.** Gedeckte Farben, Gebrauchsspuren. Wir sind in einer
  Zombie-Apokalypse: Rost, Dreck, Kratzer, abgeplatzter Lack, Blut nur sparsam als dunkle Flecken.
- **Klare Silhouette.** Ein Item muss als kleines Symbol (ca. 64 Pixel) erkennbar sein, ein Fahrzeug auf 100 Studs
  Entfernung. Mikrodetails, die man nicht sieht, kosten nur Dreiecke.
- **Nicht erlaubt:** echte Marken, Logos, Hersteller- und Modellnamen, echte Kennzeichen und Typenschilder.
  Kein **rotes Kreuz auf Weiß** (das Zeichen ist geschützt), stattdessen ein grünes Kreuz oder ein Herz. Nichts,
  was gegen die Roblox-Regeln verstößt.

### Modelle aus Meshy und anderen KI-Werkzeugen

Erlaubt, aber was Meshy liefert, ist ein **Rohling**. Beim Sturmgewehr aus Meshy musste nachträglich gemacht werden:

- das ins Gewehr verschmolzene Magazin herausschneiden und das Loch schließen;
- den Spannhebel als eigenes Teil heraustrennen (er bewegt sich beim Nachladen);
- das Holo-Visier öffnen: Es war ein geschlossener Block, beim Zielen hätte man gegen eine Wand geschaut;
- das hochgeklappte Korn umlegen: Es stand mitten im Sichtfeld;
- die Größe ändern (190 Einheiten statt 4,13 Studs), das Modell drehen (der Lauf zeigte zur Seite) und Marker
  setzen;
- die Texturen von 4096 auf 1024 verkleinern (12 MB pro Bild).

Darum gilt für Modelle aus KI-Werkzeugen:

- Im **Low-Poly-Modus** erzeugen. Teile, die sich bewegen oder getrennt gebraucht werden (Magazin, Spannhebel,
  Räder, Lenker, Deckel), **einzeln** erzeugen.
- Danach **in Blender fertig machen**: auf die Vorlage ausrichten, Größe anpassen, Teile trennen und benennen,
  Marker setzen, Visiere öffnen, Löcher schließen, Dreiecke reduzieren, Texturen verkleinern.
- Erst dann liefern. Rohdateien ohne diese Schritte sind keine fertige Lieferung.

## 4. Waffen

Alles Wichtige steht in [waffen-modelle.md](waffen-modelle.md). Waffen und Agenten lädt das Spiel heute schon als
fertige Modelle: ein Modell nach dieser Anleitung wird direkt benutzt (Ego-Waffe, Hand, Rücken, Vorschauen,
Symbole).

Die wichtigsten Punkte:

| Name | Waffe | Länge (Studs) | Bewegliche Teile |
|---|---|---|---|
| `Rifle` | Sturmgewehr | 4,13 | Magazine, Bolt |
| `SMG` | Maschinenpistole | 2,38 | Magazine, Bolt |
| `Shotgun` | Schrotflinte | 3,95 | Pump, Shell |
| `DMR` | Präzisionsgewehr | 4,58 | Magazine, Bolt |
| `LMG` | MG | 4,33 | Magazine, Bolt, Cover |
| `Pistol` | Pistole | 1,05 | Magazine, Slide |
| `Revolver` | Revolver | 1,47 | Cylinder, Hammer, Loader |

- **Pflicht-Marker:** `Point_Grip` (rechte Hand), `Point_SightRear` und `Point_SightFront` (beide genau auf der
  Visierlinie), `Point_Muzzle`, `Point_Eject`, `Point_LeftHand`, bei langen Waffen `Point_Stock`.
- **Bewegliche Teile sind eigene Objekte** mit dem Namen ihrer Gruppe, z.B. `Magazine`, `Bolt`, `Slide`. Nichts
  davon in den Rumpf verschmelzen.
- **Freie Visierlinie:** Rotpunkt- und Holo-Visiere sind **offen** (das Glas als eigenes Objekt mit `Glass`).
  Kimme und Korn liegen mit ihrer Oberkante genau auf der Linie. Nichts ragt in die Sichtlinie.
- Griff, Magazin und Mündung ungefähr dort lassen, wo sie in der Vorlage sind. Dann passen Haltung, Zielen und
  Nachladen ohne Nacharbeit.
- Farbzonen für Skins heißen `Skin_…` (Gehäuse, Schaft, Handschutz).
- **Neue Waffe:** vorher Bescheid geben (Name, Art wie Pistole, MP, Gewehr, Schrot, MG oder Präzision, Vorbild,
  Visier). Dann gibt es zuerst Werte und eine Vorlage.
- **Aufsätze** (Schalldämpfer, Griffe, Laser, Visiere): baut das Spiel vorerst selbst an Mündung, Handschutz und
  Schiene. Deshalb Mündung und obere Schiene frei lassen. Eigene Aufsatz-Modelle kommen später.

## 5. Fahrzeuge

Heute baut das Spiel die Fahrzeuge aus Quadern. Fertige Modelle kommen nach diesen Regeln in
**ReplicatedStorage › Assets › Vehicles** und heißen wie die Fahrzeug-Id.

**So funktioniert ein Fahrzeug im Spiel:** Ein unsichtbarer Rumpf (`Ref_Chassis` in der Vorlage) gleitet auf vier
unsichtbaren Kugeln über den Boden. Er kollidiert, wird getroffen und gefahren. Dein Modell ist die **Optik**: Es
wird am Rumpf befestigt und kollidiert selbst nicht. Damit Treffer und Zusammenstöße zum Aussehen passen, füllt die
Karosserie den Rumpf ungefähr aus (Länge und Breite ±10 %).

| Id | Fahrzeug | Rumpf B × H × L | Räder Ø × Breite | Achsen (z) | Spur (x) | Sitze | Farbe heute |
|---|---|---|---|---|---|---|---|
| `Bicycle` | Fahrrad | 1,4 × 1,6 × 5,6 | 2,6 × 0,25 | −2,2 / +2,2 | – | 1 | blau |
| `Quad` | Quad | 4,6 × 2,0 × 6,6 | 2,4 × 1,2 | −1,9 / +1,9 | ±2,0 | 1 | orange |
| `Pickup` | Geländewagen | 6,4 × 2,6 × 12,5 | 2,6 × 1,0 | −4,85 / +4,85 | ±3,0 | 4 | oliv |
| `Sports` | Sportwagen | 6,2 × 1,9 × 12,0 | 2,6 × 1,0 | −4,6 / +4,6 | ±2,9 | 2 | rot |
| `Heli` | Helikopter | 6,4 × 2,0 × 12,0 | Kufen statt Rädern | – | ±2,7 | 4 | oliv |

Alle Maße in Studs. Die Unterkante des Rumpfs liegt 1,4 Studs über dem Boden. Vorne ist −z, die Mitte des Rumpfs
liegt bei x = z = 0.

**Lage:**

- Ursprung: **Boden, Mitte** (Höhe 0 = Unterkante der Räder, x = z = 0 = Mitte des Rumpfs). Vorderseite nach vorne
  (siehe Abschnitt 2).
- **Räder** stehen auf dem Boden (Unterkante auf 0). Achsen und Spur wie in der Tabelle, ±10 %. Raddurchmesser 2 bis
  3 Studs.
- Der **Unterboden** reicht nicht tiefer als 0,6 Studs über den Boden, sonst schleift er an Bordsteinen.

**Teile und Namen:**

| Teil | Name | Hinweis |
|---|---|---|
| Karosserie | `Body` | alles Feste in einem Objekt |
| Lack (umfärbbar) | `Body_Paint` | lackierte Flächen. Die Farbe kommt vom Spiel bzw. später von Skins |
| Scheiben | `Glass_…` | z.B. `Glass_Windshield`; die Insassen müssen zu sehen sein |
| Räder | `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` | je ein Objekt, rund, Ursprung in der Radmitte (sie drehen sich). Fahrrad: `Wheel_F`, `Wheel_R` |
| Lenkrad bzw. Lenker | `Steer` | dreht sich beim Lenken, Drehachse mit Marker `Pivot_Steer` |
| Lichter | `Neon_HeadLight`, `Neon_TailLight` | leuchten nachts |

**Marker:**

- `Seat_Driver` (Pflicht) und `Seat_2`, `Seat_3`, `Seat_4` (je Sitz): **Mitte der Sitzfläche**, oben auf dem Polster.
  Der Fahrer sitzt links vorne.
- `Point_Exhaust` (optional): Auspuff, für Rauch.

**Weitere Regeln:**

- Die **Insassen bleiben sichtbar und treffbar:** offenes Dach, Cabrio, Überrollbügel oder Fenster aus `Glass`.
  Über der Sitzfläche mindestens **3,2 Studs** Platz für den Kopf, vor dem Sitz Platz für die Beine.
- Türen, Hauben und Klappen bleiben geschlossen und sind kein eigenes Teil.
- Optional ein zweites Textur-Set **ausgebrannt** (`<Id>_Burned_…`). Damit können die Autowracks auf der Karte
  dasselbe Modell benutzen.
- **Neues Fahrzeug** (Motorrad, LKW, Bus …): vorher Bescheid geben. Dann gibt es zuerst Werte und eine Vorlage.

**Helikopter (`Heli`):** Der Rumpf ist der Kabinenboden. Dazu kommen ein Heckausleger bis etwa z = +14,7, ein Hauptrotor
mit Ø 24 und ein Heckrotor mit Ø 4,4 (Vorlage `art/templates/Vehicles/Heli.obj`). Pilot links vorne (`Seat_Driver`),
Kopilot rechts vorne (`Seat_2`), zwei Plätze hinten (`Seat_3`, `Seat_4`).

| Teil | Name | Hinweis |
|---|---|---|
| Kufen | `Skid_L`, `Skid_R` | statt Rädern; Unterkante auf 0, bei x = ±2,7; vorne hochgebogen |
| Hauptrotor | `Rotor_Main` | eigenes Objekt, dreht um +Y. Ursprung genau auf `Point_Rotor` |
| Heckrotor | `Rotor_Tail` | eigenes Objekt, dreht um +X. Ursprung genau auf `Point_TailRotor`, rechts am Leitwerk |
| Scheiben | `Glass_Windshield`, `Glass_…` | Front verglast. Die Seiten sind offen oder aus `Glass`, die Insassen bleiben sichtbar |
| Lichter | `Neon_NavLeft` (rot), `Neon_NavRight` (grün), `Neon_Tail` | Positionslichter. Optional `Point_Searchlight` unter der Nase |

- Die Rotorblätter sind flach und rundum gleich (2 gekreuzte oder 4 Blätter), damit die Drehung rund aussieht. Sie
  kollidieren nicht und dürfen über den Rumpf hinausragen.
- Über den hinteren Sitzen bleiben mindestens 3,2 Studs bis zum Dach frei, der Rotor sitzt darüber.

## 6. Items, Gadgets und Behälter

Fertige Modelle kommen in **ReplicatedStorage › Assets › Items** und heißen wie die Id. Wo man sie sieht:

- als **Symbol** im Inventar und in der Schnellleiste (klein, ca. 64 Pixel);
- groß am **Stand** im Camp;
- am **Boden** (Beute);
- später **in der Hand** beim Benutzen.

**Lage:** Ursprung **unten in der Mitte** (das Item steht oder liegt auf Höhe 0). Die erkennbare Seite (Symbol,
Etikett) zeigt nach **vorne**. Marker `Point_Grip` dort, wo die rechte Hand greift (bei Items und Gadgets Pflicht).

| Id | Item | Zielgröße B × H × T (Studs) | Form und Erkennungszeichen |
|---|---|---|---|
| `Bandage` | Verband | 0,45 × 0,6 × 0,6 | Rolle (liegt quer), loses Ende |
| `Medkit` | Medikit | 1,4 × 1,0 × 0,45 | Koffer, Griff oben, grünes Kreuz vorne |
| `Adrenaline` | Adrenalin | 1,2 × 0,28 × 0,28 | Autoinjektor, gelb |
| `AntiZombie` | Anti-Zombie-Spritze | 1,2 × 0,26 × 0,26 | Spritze mit grünem Serum, Nadel nach +x |
| `Vest` | Schutzweste | 1,7 × 1,9 × 0,6 | Plattenträger, steht aufrecht, Vorderseite vorne |
| `HeavyVest` | Schwere Weste | 1,9 × 2,1 × 0,8 | wie Weste, mit Kragen und Schulterschutz |
| `Ammo_9mm` | 9mm-Munition | 0,8 × 0,55 × 0,5 | kleine Pappschachtel, gelb/braun |
| `Ammo_Magnum` | Magnum-Munition | 0,7 × 0,5 × 0,5 | kleine Schachtel, dunkelrot |
| `Ammo_Shell` | Schrotpatronen | 1,0 × 0,6 × 0,6 | Schachtel, rote Patronen sichtbar |
| `Ammo_Rifle` | Gewehrmunition | 1,3 × 0,9 × 0,6 | Munitionskiste aus Metall, oliv, Griff oben |
| `Gadget_Frag` | Splittergranate | 0,55 × 0,75 × 0,55 | mit Bügel und Ring |
| `Gadget_Flash` | Blendgranate | 0,45 × 0,85 × 0,45 | Zylinder, Löcher |
| `Gadget_Smoke` | Rauchgranate | 0,5 × 0,95 × 0,5 | Zylinder, farbiger Streifen |
| `Gadget_Sensor` | Sensor-Mine | 1,0 × 0,3 × 1,0 | flache Scheibe, kleine Antenne, `Neon`-Lämpchen |
| `Loot_Death` | Todestasche | 2,4 × 1,7 × 1,8 | großer Rucksack |
| `Loot_Drop` | fallen gelassener Beutel | 1,5 × 1,1 × 1,3 | Seesack oder Beutel |
| `Crate_Wood` | Holzkiste | 3,4 × 2,4 × 2,4 | |
| `Crate_Toolbox` | Werkzeugkiste | 3,4 × 2,0 × 2,0 | rot |
| `Crate_Medical` | Sani-Kiste | 3,0 × 2,0 × 2,2 | weiß, grünes Kreuz |
| `Crate_Ammo` | Munitionskiste | 3,2 × 1,8 × 2,0 | oliv |
| `Crate_Military` | Militärkiste | 4,0 × 2,6 × 2,6 | oliv, Schablonenschrift ohne echte Kennungen |
| `Airdrop` | Versorgungsabwurf | 5,0 × 3,6 × 5,0 | Kiste, Fallschirm optional als eigenes Teil |

Die Größen sind bewusst etwas größer als in echt, damit die Items in der Hand und als Symbol gut zu erkennen sind.
Abweichung ±15 %.

- **Gut lesbar als Symbol:** eindeutige Silhouette und feste Farben. Heilung weiß mit grünem Kreuz, Adrenalin gelb,
  Spritze grün, Westen oliv oder schwarz, Munition je Sorte in einer eigenen Farbe.
- **Behälter:** Deckel bzw. Klappe als eigenes Objekt `Lid` (für eine spätere Öffnen-Animation), optional Marker
  `Point_Light` für das Licht.
- **Gadgets** liegen wie alle Items mit der Unterseite auf Höhe 0. Beim Wurf dreht das Spiel sie um ihre Mitte.
- Fähigkeits-Objekte der Agenten (Schutzwand, Stacheldraht, Geschützturm) kommen später, nach denselben Regeln.

## 7. Agenten

**Grundsatz: alle Agenten haben dieselbe Trefferzone.** Spieler und Bots werden am (unsichtbaren) Spielkörper
getroffen: Roblox R15, klassische Proportionen, **Breite 0,75, Tiefe 0,8**, etwa 5,1 Studs groß. So ist kein Agent
schwerer zu treffen als ein anderer. Teile eines Agentenmodells zählen nie als Treffer, Schüsse gehen durch.

**So kommt ein Agent ins Spiel:** in Blender auf dem Spielkörper bauen (Ruhelage, Arme hängen, ein starres Teil pro
Körperteil, Namen wie `Head_Suit`, `LeftUpperArm_Suit`), exportieren, in Studio importieren und nach
ReplicatedStorage › Assets › Agents legen, benannt wie der Agent. Das Spiel zeigt das Modell **genau so wie in
Blender** an Spielern, Bots und in allen Vorschauen: nichts wird umgefärbt, gestreckt oder gedreht, jedes Teil folgt
seinem Körperteil. Körpermaße, Gelenkhöhen und die Schritt-für-Schritt-Anleitung stehen in
[agenten-modelle.md](agenten-modelle.md).

**Regeln:**

- **Ein Teil, ein Körperteil:** Nichts geht über ein Gelenk hinweg, sonst reißt es beim Laufen auseinander.
- **Ruhelage:** Füße auf Höhe 0, Blick nach vorne, Arme hängen gerade nach unten (keine T- oder A-Pose).
- **Arme und Hände frei** lassen: Sie halten die Waffe. Schulterpolster nicht so breit, dass sie die Waffe verdecken.
- **Nah an der Körperform bleiben:** Was weit absteht (Flügel, Umhänge, lange Antennen), sieht wie ein Ziel aus,
  zählt aber nicht als Treffer, und das wäre unfair.

| Id | Name | Rolle | Farbe (RGB) | Idee für den Look |
|---|---|---|---|---|
| `Viper` | VIPER | Scout | 92, 166, 118 | leicht und schnell: wenig Panzerung, Kapuze, Läufer-Ausrüstung |
| `Bastion` | BASTION | Verteidiger | 88, 124, 186 | schwer: dicke Weste, Helm mit Visier, große Schulterplatten (eng anliegend) |
| `Mender` | MENDER | Sanitäter | 196, 92, 86 | Sanitäts-Taschen, Spritzen am Gürtel, grünes Kreuz |
| `Hawk` | HAWK | Aufklärer | 200, 168, 84 | Fernglas oder Zielfernrohr am Helm, Funkgerät, Tarnmuster |
| `Ghost` | GHOST | Infiltrator | 136, 140, 152 | dunkel und schlank, eng anliegende Tarnkleidung, Maske |
| `Blaze` | BLAZE | Stürmer | 206, 112, 58 | Angreifer: Brandspuren, Stoßschutz vorne |
| `Aegis` | AEGIS | Unterstützung | 110, 160, 196 | Heiler und Schutz: Medizin-Pack, Schild-Emblem |
| `Trapper` | TRAPPER | Kontrolle | 156, 132, 92 | Fallensteller: Werkzeuggürtel, Draht, Handschuhe |
| `Volt` | VOLT | Techniker | 204, 190, 86 | Ingenieur: Akku-Pack, Kabel, Werkzeug, `Neon`-Anzeigen |

**Eigener Körper:** Das Modell ist nur zu sehen; die Trefferzone bleibt der Spielkörper, darum muss das Modell nicht
genau dessen Maße haben. Liegen die Grenzen der Teile auf seinen Gelenken, bleibt beim Bewegen alles lückenlos.

## 8. Abgabe

**Ordner pro Modell**, zum Beispiel `Vehicles/Quad/`:

| Datei | Inhalt |
|---|---|
| `Quad.blend` | Blender-Quelldatei |
| `Quad.fbx` oder `Quad.glb` | Export nach Abschnitt 2 |
| `Quad_Color.png`, `Quad_Normal.png`, `Quad_Roughness.png`, `Quad_Metalness.png` | Texturen einzeln (auch wenn sie im Export stecken) |
| `Quad_Vorschau.png` | Bild des Modells, wenn möglich aus Studio |
| `LIZENZ.txt` | nur bei fremden Modellen: Quelle, Autor, Link, Lizenz (z.B. CC-BY 4.0) |

Hochladen nach `art/sources/<Kategorie>/<Id>/` (GitHub) oder als ZIP an die Projektleitung.

**Checkliste vor der Abgabe:**

- [ ] Um die Vorlage herum gebaut, Probelauf gemacht, Größe und Richtung stimmen in Studio
- [ ] Alle `Ref_`-Objekte gelöscht, alle Marker da und richtig benannt
- [ ] Bewegliche Teile, Glas, Leuchtteile und Farbzonen sind eigene Objekte mit den Namen aus der Liste
- [ ] Rotation und Skalierung angewendet, keine negativen Skalierungen
- [ ] Geschlossen, Normalen außen, keine doppelten Flächen, keine Flächen mit 5+ Ecken
- [ ] Budget eingehalten (Dreiecke, Objekte, Texturgröße)
- [ ] Ein Material pro Objekt, ein Textur-Set pro Modell, Normal Map im OpenGL-Format
- [ ] Keine echten Marken, Logos, Kennzeichen, kein rotes Kreuz
- [ ] Waffen: Visier offen, Visierlinie frei, Magazin und Verschluss getrennt
- [ ] Fahrzeuge: Räder auf dem Boden, Sitz-Marker, Insassen sichtbar
- [ ] Agenten: Ruhelage mit hängenden Armen, ein Teil pro Körperteil (`<Körperteil>_<Name>`), höchstens 40 Teile
- [ ] Lieferordner vollständig (Quelldatei, Export, Texturen, Vorschau, ggf. Lizenz)

**In Studio testen** (wenn du Zugriff hast): Import 3D mit den Einstellungen aus Abschnitt 2, das Modell nach
ReplicatedStorage › Assets › `<Kategorie>` ziehen und so nennen wie die Id, dann Play. Bei Waffen steht im Output
`[Waffenmodelle] <Waffe>: 3D-Modell geladen`, bei Agenten `[Agentenmodelle] <Agent>: Modell geladen` oder, was
fehlt.

## 9. Häufige Fehler

| Fehler | Folge | Richtig |
|---|---|---|
| Bewegliches Teil (Magazin, Spannhebel, Rad) ins Modell verschmolzen | Es muss herausgeschnitten und das Loch geschlossen werden | als eigenes Objekt bauen bzw. erzeugen |
| Visier geschlossen, Korn hochgeklappt | Beim Zielen sieht man nichts | Glas als eigenes `Glass`-Objekt, Sichtlinie frei |
| Falsche Größe, Modell liegt oder zeigt zur Seite | Neu ausrichten und skalieren | um die Vorlage bauen, Probelauf, Export-Einstellungen |
| „Merge Meshes“ an oder alles in einem Objekt | Marker und bewegliche Teile weg | Merge Meshes aus, Teile getrennt lassen |
| Empties als Marker | kommen nicht an | kleine Würfel |
| 4K-Texturen, mehrere Materialien pro Objekt | Speicher voll, Teile werden grau | ein Textur-Set in Budget-Größe, ein Material pro Objekt |
| Normal Map im DirectX-Format | Beulen falsch beleuchtet | OpenGL-Format exportieren |
| Dünne Flächen ohne Dicke | von hinten unsichtbar | Dicke geben |
| Echte Logos, Marken, rotes Kreuz | Roblox-Moderation | Fantasie-Namen, grünes Kreuz |

## 10. Für die Projektleitung: Modelle ins Spiel bringen

**Waffen und Agenten** lädt das Spiel schon, das geht ohne Hilfe:

1. Lieferung prüfen: Checkliste abgehakt, alle Dateien da.
2. Den Place in Studio öffnen, **Import 3D**, die `.fbx` oder `.glb` wählen. Im Fenster: World Forward **Front**,
   World Up **Top**, Scale Unit **Stud**, **Merge Meshes aus**. Importieren.
3. Das Modell im Explorer nach **ReplicatedStorage › Assets › Weapons** ziehen und genau wie die Waffe nennen
   (`Rifle`, `SMG`, `Shotgun`, `DMR`, `LMG`, `Pistol`, `Revolver`), bzw. nach **Assets › Agents** und genau wie der
   Agent (`Viper`, `Bastion`, `Mender`, `Hawk`, `Ghost`, `Blaze`, `Aegis`, `Trapper`, `Volt`). Ein älteres Modell
   mit demselben Namen vorher löschen.
4. Bleiben Teile weiß oder grau: im Teil eine **SurfaceAppearance** einfügen und die Bilder aus der Lieferung setzen
   (ColorMap, NormalMap, RoughnessMap, MetalnessMap).
5. **Play** und ins Output schauen: `[Waffenmodelle] Rifle: 3D-Modell geladen` bzw.
   `[Agentenmodelle] Viper: Modell geladen`. Steht dort ein Fehler, die Meldung an den Designer schicken
   (erklärt in [waffen-modelle.md](waffen-modelle.md), „Meldungen und was zu tun ist“, bzw.
   [agenten-modelle.md](agenten-modelle.md), „Häufige Probleme“).
6. **Aus Studio veröffentlichen** (Datei › Publish to Roblox). Die Modelle leben im Place: nicht mit `rojo build`
   neu bauen und veröffentlichen, sonst fehlen sie.
7. Empfohlen: Rechtsklick auf das Modell › **Save to File…** › `<Id>.rbxmx`, auf GitHub in `assets/Weapons` bzw.
   `assets/Agents` hochladen (Add file › Upload files). Dann prüft GitHub das Modell bei jedem Push. Die Lieferung
   selbst (Quelldatei, Texturen) kommt nach `art/sources/<Kategorie>/<Id>/`.

**Fahrzeuge und Items** baut das Spiel heute noch aus Quadern; Modelle in Assets › Vehicles oder Items werden noch
nicht gelesen. Mit dem ersten fertigen Modell einer Kategorie bekommt das Spiel einmal einen Lader nach genau diesen
Regeln (mit Prüfmeldungen wie bei Waffen und Agenten). Danach gilt derselbe Ablauf, nur mit dem Ordner der Kategorie.
- **Vorlagen neu erzeugen**, wenn sich Fahrzeuge im Spiel ändern: `python3 tools/asset_templates.py` (Fahrzeuge und
  Items) bzw. `python3 tools/weapon_templates.py` (Waffen).

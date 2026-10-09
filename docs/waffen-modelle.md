# Waffenmodelle: von Blender ins Spiel

Das Spiel benutzt für jede Waffe ein fertiges 3D-Modell, sobald es in Studio unter
**ReplicatedStorage › Assets › Weapons** liegt und so heißt wie die Waffe (`Rifle`, `SMG`, …). Solange es keins gibt
oder dem Modell etwas Wichtiges fehlt, bleibt die heutige Quader-Waffe – nichts geht kaputt. Das Modell wird
überall benutzt: Ego-Waffe mit Armen, Waffe in der Hand (Third-Person), Rückenwaffe im Markt, Vorschauen in Lobby,
Shop und Markt, Waffen-Symbole im HUD.

Der Code dazu steht in `src/shared/GunModels.lua` (Abschnitt „Fertige 3D-Modelle“). Allgemeine Regeln für alle
Modelle (Export-Einstellungen, Geometrie, Texturen, Stil, Abgabe-Checkliste) stehen in
[3d-richtlinien.md](3d-richtlinien.md).

## Ablauf

0. **Probelauf mit der Vorlage** (einmal, ca. 10 Minuten): Vorlage in Blender importieren, sofort wieder als FBX
   exportieren, in Studio importieren und wie unten einsetzen. Steht im Output „3D-Modell geladen“, stimmen deine
   Export- und Import-Einstellungen. Meldet es „stimmt die Einheit beim Import?“, die Einheit im Import-Fenster von
   Studio umstellen, bis das Sturmgewehr etwa 4,1 Studs lang ist – diese Einstellung dann immer benutzen.
1. **Vorlage öffnen**: Blender › Datei › Importieren › Wavefront (.obj) › `art/templates/Weapons/<Waffe>.obj`.
   Die Vorlage ist die heutige Quader-Waffe in Originalgröße (1 Blender-Einheit = 1 Stud) mit allen Markern.
2. **Modellieren** um die Vorlage herum: Griff, Visierlinie, Magazin und Mündung ungefähr dort lassen, wo sie
   sind – dann passen Haltung, Zielen und Nachlade-Animationen ohne Nacharbeit. Die Quader-Objekte danach löschen.
3. **Benennen** (siehe [Teilnamen](#teilnamen)) und die **Marker** aus der Vorlage auf dein Modell schieben
   (siehe [Marker](#marker)).
4. **Texturieren** (PBR, siehe [Texturen und Skins](#texturen-und-skins)).
5. **Exportieren**: alle Objekte der Waffe samt Markern auswählen, `Strg+A › Alle Transformationen`, dann
   Datei › Exportieren › FBX (.fbx) mit „Nur Auswahl“ und Skalierung 1,0. Wie die Achsen eingestellt sind, ist
   egal: Das Spiel richtet die Waffe an den Markern aus.
6. **Importieren** in Studio: Import 3D. Teile **nicht** zusammenführen (sonst verschwinden Marker und
   bewegliche Teile). Das Modell nach **ReplicatedStorage › Assets › Weapons** ziehen und umbenennen
   (`Rifle`, `SMG`, `Shotgun`, `DMR`, `LMG`, `Pistol`, `Revolver`).
7. **Spielen** (Play): Im Output steht für jedes Modell `[Waffenmodelle] Rifle: 3D-Modell geladen` oder, was
   fehlt. Hinweise (z.B. eine fehlende Animationsgruppe) stehen darunter.
8. **Speichern**: den Place speichern bzw. veröffentlichen – die Modelle leben im Place, Rojo lässt sie dort in
   Ruhe. Zusätzlich eine Kopie ins Repo: Rechtsklick auf das Modell › „Save to File…“ › als
   `assets/Weapons/<Waffe>.rbxmx` speichern und committen. GitHub prüft die Kopie dann bei jedem Push
   (siehe [Prüfen](#prüfen)).

Zum Ausprobieren ohne Blender: `art/templates/Weapons/<Waffe>.rbxmx` per Datei › „Insert from File…“ in Studio
einfügen und nach Assets › Weapons legen – die Vorlage ist selbst ein gültiges Modell.

Die `SMG` ist bereits fertig (MP7 A1, siehe `art/sources/README.md`, erzeugt mit `python3 tools/mp7_model.py`).

**Modelle aus Meshy oder anderen Quellen** (fertige FBX/GLB ohne Marker): einfach in `art/sources/` hochladen
(Waffe und Magazin als eigene Dateien, Texturen dazu). Dann bereite ich sie vor wie das Sturmgewehr
(`tools/attachments/ar15_v2.py`, Ergebnis `art/sources/Rifle.glb`): Teile benennen, Marker setzen, Größe und Richtung,
Magazin einpassen, Visier freischneiden. Werkzeuge dafür: `tools/fbx_read.py` (FBX lesen ohne Blender) und
`tools/mesh_ops.py` (Schneiden, Löcher schließen, GLB mit Texturen schreiben).

So kommt eine vorbereitete GLB ins Spiel:

1. In Studio **Import 3D** › die `.glb` wählen. Im Import-Fenster **Merge Meshes aus** (Teile nicht zusammenführen)
   und als Einheit **Stud**. Importieren.
2. Das Modell im Explorer nach **ReplicatedStorage › Assets › Weapons** ziehen und so nennen wie die Waffe
   (z.B. `Rifle`).
3. **Texturen prüfen**: Die Teile sollten ihre Farben zeigen. Falls ein Teil weiß/grau bleibt: im Teil eine
   **SurfaceAppearance** einfügen und ColorMap, MetalnessMap und RoughnessMap mit den Bildern aus dem
   Texturen-Ordner (z.B. `art/sources/Rifle_Texturen/`) setzen.
4. **Play**: Im Output muss `[Waffenmodelle] Rifle: 3D-Modell geladen` stehen.
5. Place veröffentlichen, dann Rechtsklick auf das Modell › „Save to File…“ › `assets/Weapons/<Waffe>.rbxmx` ins
   Repo (automatische Prüfung bei jedem Push).

## Die Waffen

Maße der Vorlagen (Studs). „Visier“ = Höhe der Visierlinie über dem Griff.

| Name im Modell | Waffe | Länge | Visier | Bewegliche Gruppen | Besonderes |
|---|---|---|---|---|---|
| `Rifle` | Sturmgewehr | 4,13 | 0,97 | Magazine, Bolt | Rotpunktvisier (roter Punkt = `Point_SightRear`); fertig: `art/sources/Rifle.glb` (AR-15 ohne Aufsätze, Kimme/Korn als Visierlinie; Holo-Visier als Aufsatz) |
| `SMG` | Maschinenpistole | 2,38 | 0,81 | Magazine, Bolt | |
| `Shotgun` | Schrotflinte | 3,95 | 0,76 | Pump, Shell | Shell = Patrone, nur beim Nachladen sichtbar |
| `DMR` | Präzisionsgewehr | 4,58 | 0,93 | Magazine, Bolt | |
| `LMG` | MG | 4,33 | 0,97 | Magazine, Bolt, Cover | Magazin = Kasten + Gurt, Cover = Deckel |
| `Pistol` | Pistole | 1,05 | 0,62 | Magazine, Slide | Kimme und Korn sitzen auf dem Schlitten (Slide) |
| `Revolver` | Revolver | 1,47 | 0,62 | Cylinder, Hammer, Loader | Loader = Schnelllader, nur beim Nachladen sichtbar |

Ob eine Waffe ein Rotpunktvisier hat, steht im Code (`Reflex` in `GunModels.Info`) – wer beim Sturmgewehr
lieber Kimme und Korn will, sagt Bescheid.

## Marker

Marker sind kleine Objekte (z.B. Würfel, Größe egal – nur ihre **Mitte** zählt). Sie kommen nicht ins Spiel. In
der Vorlage sind sie magenta (Punkte) bzw. türkis (Drehpunkte). Statt Marker-Objekten gehen in Studio auch
Attachments mit denselben Namen (ohne `Point_`).

| Marker | Pflicht | Wo |
|---|---|---|
| `Point_Grip` | ja | rechte Hand am Pistolengriff – wird zum Ursprung der Waffe |
| `Point_SightRear` | ja | Mitte der Kimme bzw. der rote Punkt im Rotpunktvisier |
| `Point_SightFront` | ja | Spitze des Korns bzw. Mitte der Vorderkante des Rotpunktvisiers |
| `Point_Muzzle` | ja | Mündung (Mündungsfeuer, Leuchtspur, Schalldämpfer, Kompensator) |
| `Point_Eject` | ja | Hülsenauswurf |
| `Point_LeftHand` | ja | linke Hand: Handschutz bzw. bei Pistole/Revolver die Stützhand |
| `Point_Stock` | lange Waffen | hinteres Ende der Schulterstütze (alle außer Pistole und Revolver) |
| `Point_LeftHandTP` | nein | linke Hand in der Third-Person, falls näher am Griff (kürzere Arme) |
| `Pivot_<Gruppe>` | nein | Drehpunkt einer beweglichen Gruppe, z.B. `Pivot_Cover` |

**Die Visierlinie ist das Wichtigste**: `Point_SightRear` und `Point_SightFront` liegen genau auf der Linie, über
die man zielt. Beim Zielen landet diese Linie exakt in der Bildmitte – sitzen die Marker daneben, schießt man
daneben vorbei. Der Griff muss unterhalb der Linie liegen. Aus Griff und Visierlinie berechnet das Spiel, wo vorne
und oben ist; darum ist egal, wie das Modell nach dem Import gedreht ist.

Die Drehpunkte in der Vorlage stehen da, wo die Nachlade-Animationen heute drehen. Bleiben sie dort, sehen die
Animationen aus wie jetzt; ohne `Pivot_…` dreht eine Gruppe um die Mitte ihres Hauptteils.

## Teilnamen

Ein Name besteht aus Wörtern mit `_` dazwischen, Reihenfolge egal, Groß-/Kleinschreibung beachten. Blender-Endungen
wie `.001` zählen nicht. Diese Wörter haben eine Bedeutung:

| Wort | Bedeutung |
|---|---|
| `Magazine`, `Bolt`, `Slide`, `Pump`, `Cylinder`, `Hammer`, `Cover`, `Shell`, `Loader` | Animationsgruppe: das Teil bewegt sich beim Nachladen mit. Welche eine Waffe braucht, steht oben in der Tabelle. |
| `Skin` | Skin-Zone: bekommt die Farbe des ausgerüsteten Skins |
| `Neon` | leuchtet (z.B. die Leuchtpunkte auf Kimme und Korn) |
| `Glass` | Glas (Fenster des Rotpunktvisiers) |
| `Reticle` | der rote Punkt (fehlt er beim Rotpunktvisier, setzt das Spiel einen auf `Point_SightRear`) |

Beispiele: `Skin_Receiver`, `Magazine`, `Magazine_Rounds`, `Skin_Slide`, `Bolt`, `Neon_FrontDot`, `Glass_Optic`.
Alle anderen Namen sind frei.

- **Hauptteil einer Gruppe** ist das Teil, das genau so heißt wie die Gruppe (z.B. `Magazine`), sonst das
  größte. An ihm sitzen die Magazin-Aufsätze (langes Magazin, Trommel, Schnellmagazin), und ihn greift die linke
  Hand beim Nachladen.
- **Wenige Teile**: Was sich nicht bewegt und keine eigene Skin-Zone ist, in Blender zu einem Objekt zusammenfügen
  (`Strg+J`). Ab 40 Teilen gibt es einen Hinweis.
- Shell und Loader sind nur während der Animation zu sehen.
- Die Aufsätze (Schalldämpfer, Griffe, Laser, Läufe, Magazine) baut das Spiel vorerst weiter aus einfachen Teilen
  an Mündung, Handschutz und Magazin deines Modells. Eigene Modelle für Aufsätze kommen in einem zweiten Schritt.

## Texturen und Skins

**Texturen (PBR)**: pro Waffe ein Textur-Set mit Farbe (Albedo), Normal, Rauheit (Roughness) und Metall
(Metalness), 1024 × 1024 Pixel (Roblox kann mehr, auf Handys bringt das nichts; für Pistole und Revolver reichen
512 × 512). Die Normal Map im **OpenGL-Format** (in Substance Painter umstellen, Standard ist DirectX). In Studio
bekommt jedes texturierte Teil eine **SurfaceAppearance** mit ColorMap, NormalMap, RoughnessMap und MetalnessMap.

**Skins – Mischform**:

- **Gewöhnliche und seltene Skins färben die Skin-Zonen um.** Damit die Farbe durchkommt, bekommt jede Skin-Zone
  eine SurfaceAppearance mit **AlphaMode = Overlay**. In ihrer ColorMap sind die umfärbbaren Flächen durchsichtig
  (Alpha 0), Details wie Kratzer, Kanten, Schrift und Schrauben deckend. Normal-, Rauheits- und Metall-Map wirken
  trotzdem. Ohne Skin zeigt die Zone die Farbe des Teils (Eigenschaft Color in Studio).
- **Epische und legendäre Skins können eine eigene Textur haben.** Dafür im Waffenmodell einen Ordner `Skins`
  anlegen, darin je Skin einen Ordner mit der Skin-Id und darin SurfaceAppearances, die genau so heißen wie die
  Teile, die sie bekommen: z.B. `Skins › W_Lava › Skin_Receiver`. Ohne eigene Textur bekommt der Skin wie heute
  seine Farbe – du kannst also klein anfangen und Texturen nach und nach ergänzen.
- Skin-Ids stehen in `src/shared/Cosmetics.lua`. Epische und legendäre Waffen-Skins sind u.a. `W_Lava`,
  `W_Galaxie`, `W_Goldrausch`, `W_Gletscher`, `W_Royal`, `W_Hologramm`, `W_Chrom`, `W_Spezialist`,
  `W_Grossmeister`, `W_Gluecksklee` und die Saison-, Wochen- und Prestige-Skins (insgesamt 29 von 37).

## Budget (Handys)

Richtwerte, damit das Spiel auch auf schwächeren Handys flüssig läuft:

| | Dreiecke (ganze Waffe) | Teile | Textur |
|---|---|---|---|
| Lange Waffen | 3.000 – 6.000 | höchstens ca. 20 | 1024 × 1024 |
| Pistole, Revolver | 2.000 – 3.500 | höchstens ca. 12 | 512 × 512 |

Die Ego-Waffe ist nah an der Kamera und darf Details haben; dieselbe Waffe sieht man aber auch bei jedem anderen
Spieler und Bot. Glas nur im Visier.

## Prüfen

- **In Studio**: beim Spielstart im Output (`[Waffenmodelle] …`).
- **Auf GitHub**: liegt eine Kopie als `assets/Weapons/<Waffe>.rbxmx` im Repo, prüft jeder Push automatisch:
  Das Modell lädt ohne Fehler, Textur-Skins gehören zu echten Skins dieser Waffe, beim Zielen liegt die
  Visierlinie in der Bildmitte, die Hände sitzen an der Waffe, und jede Animationsgruppe, die das Nachladen
  braucht, ist da. Hinweise stehen als `HINWEIS` im Log.
- **Lokal**: `python3 tests/run.py` (siehe README).

## Meldungen und was zu tun ist

| Meldung | Lösung |
|---|---|
| `Marker Point_… fehlt` | Marker aus der Vorlage übernehmen; Name genau so schreiben |
| `Unbekannter Marker …` | Tippfehler im Namen (z.B. `Point_Muzle`) |
| `Waffe ist … Studs lang, vorgesehen sind etwa … – stimmt die Einheit beim Import?` | Einheit im Import-Fenster von Studio umstellen (siehe Probelauf) oder in Blender skalieren und Transformationen anwenden |
| `Mündung liegt hinter der Kimme – sind Point_SightRear und Point_SightFront vertauscht?` | die beiden Marker tauschen |
| `Point_Grip liegt auf der Visierlinie` | Griff-Marker an den Pistolengriff, unter die Visierlinie |
| `Point_Stock liegt vor dem Griff` | Marker ans hintere Ende der Schulterstütze |
| `Animationsgruppe … fehlt` | das bewegliche Teil so benennen, dass das Wort darin vorkommt (z.B. `Magazine`) |
| `Skins/…/…: kein Teil mit diesem Namen` | SurfaceAppearance im Skin-Ordner genau wie das Teil benennen |
| `unbekannter Name – Modelle heißen wie die Waffe` | Modell umbenennen: `Rifle`, `SMG`, `Shotgun`, `DMR`, `LMG`, `Pistol` oder `Revolver` |

## Vorlagen neu erzeugen

Ändern sich die Quader-Waffen in `src/shared/GunModels.lua`, die Vorlagen neu bauen:

    python3 tools/weapon_templates.py

Das schreibt `art/templates/Weapons/<Waffe>.obj`, `.mtl` und `.rbxmx`. Der Test `templates` stellt sicher, dass
jede Vorlage selbst ein gültiges Modell ist.

## Hinweis zu Rojo

Rojo legt den Ordner ReplicatedStorage › Assets › Weapons an und lässt die Modelle darin stehen; sie leben im
Place. Eine mit `rojo build` gebaute Place-Datei enthält sie deshalb nicht (dort gibt es dann die Quader-Waffen) –
veröffentlicht wird aus Studio.

## Fahrzeuge, Items und Agenten

Die Vorgaben dafür stehen in [3d-richtlinien.md](3d-richtlinien.md), die Vorlagen in `art/templates/Vehicles` und
`art/templates/Items` (erzeugt mit `python3 tools/asset_templates.py`). Agenten lädt das Spiel schon wie die Waffen:
Das Modell ist genau wie in Blender zu sehen, die Trefferzone bleibt der einheitliche Körper, Anleitung in
[agenten-modelle.md](agenten-modelle.md).

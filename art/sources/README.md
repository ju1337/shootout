# Quellmodelle

- `DMR.glb`: Präzisionsgewehr (Scharfschützengewehr AWM-Bauart mit Zielfernrohr aus Meshy,
  `Meshy_AI_roblox_magnum_sniper_1012115921_texture.glb`), erzeugt mit `tools/attachments/sniper_v1.py`: volle Qualität
  (308.108 Dreiecke in 16 Stücken `Skin_Body_01…16`, Texturen 4096 mit Normal Map), Zweibein nach vorn unter den Lauf
  geklappt, `Magazine` und `Bolt` (Kammerstängel) herausgeschnitten, Visierlinie durch die Mitte des Zielfernrohrs,
  4,58 Studs lang. In Studio: Import 3D > DMR.glb (Einheit Stud, Merge Meshes aus), nach ReplicatedStorage > Assets >
  Weapons, "DMR" nennen.

- `Rifle.glb`: aktuelles Sturmgewehr (AR-15 aus Meshy, ohne Aufsätze, 30er-Magazin als `Magazine`), erzeugt mit
  `tools/attachments/ar15_v2.py`; der Lauf vor dem Handschutz ist ein eigenes Teil `Skin_Body_Barrel`
  (`tools/attachments/rifle_barrel.py`), das Lauf-Aufsätze ausblenden. Aufsätze (Holo-Visier, Schalldämpfer, Winkelgriff) in `Attachments/`.
  In Studio: Import 3D > Rifle.glb (Einheit Stud, Merge Meshes aus), nach ReplicatedStorage > Assets > Weapons, "Rifle" nennen.

- `Meshy_AI_roblox_ar556_lowpoly_*` (Gewehr) und `Meshy_AI_roblox_ar_mag_lowpoly_*` (Magazin): mit Meshy AI erzeugt,
  je eine FBX und vier Texturen (Farbe, Metall, Rauheit, Metall+Rauheit). Daraus macht `python3 tools/rifle_glb.py`
  das ALTE Sturmgewehr `Rifle_alt.glb` (ersetzt durch `Rifle.glb` oben): eingebautes Magazin herausgeschnitten und das separate Magazin an seine Stelle gesetzt
  (gleiche Größe und Neigung), Fenster des Holo-Visiers geöffnet (es war ein geschlossener Block), vorderes
  Klappkorn umgelegt (stand mitten im Sichtfeld), Spannhebel als `Bolt` herausgetrennt, Marker gesetzt, 4,13 Studs
  lang, Lauf nach -Z, Texturen 1024 x 1024 im GLB. Die Texturen liegen zusätzlich einzeln in `Rifle_Texturen/`.
  Wird nicht mehr benutzt, bleibt nur als Vorlage.

- `mp7a1.glb`: "low-poly HK MP7 A1" von D_U (https://sketchfab.com/DU1701), Lizenz CC-BY-4.0
  (http://creativecommons.org/licenses/by/4.0/), Quelle: https://sketchfab.com/3d-models/low-poly-hk-mp7-a1-4715a09c0d054bdba7c0fbf0929a9878
  Daraus erzeugt `python3 tools/mp7_model.py` die SMG (`assets/Weapons/SMG.rbxmx`, aus Quadern nachgebaut;
  der Schalldämpfer des Modells bleibt weg, den baut das Spiel als Aufsatz). Für das echte Mesh in Studio:
  Import 3D mit dieser GLB, Teile benennen und Marker setzen wie in `docs/waffen-modelle.md`.
- `SMG.glb`: die fertig vorbereitete Studio-Version (`python3 tools/mp7_glb.py`): Teile benannt, Marker gesetzt, ohne
  Schalldämpfer, in Studs, Lauf nach -Z, volle Qualität (14.344 Dreiecke mit den Original-Normalen, nicht vereinfacht). In Studio: Import 3D > SMG.glb (Teile nicht zusammenführen), Modell nach
  ReplicatedStorage > Assets > Weapons ziehen, "SMG" nennen. Dann ersetzt das echte Mesh den Nachbau aus Quadern.

- `mk23.glb`: "low-poly HK Mark 23 SOCOM" von D_U (https://sketchfab.com/DU1701), Lizenz CC-BY-4.0
  (http://creativecommons.org/licenses/by/4.0/), Quelle: https://sketchfab.com/3d-models/low-poly-hk-mark-23-socom-b6426adeae9d45999610453df5a68c43
- `Pistol.glb`: die fertig vorbereitete Studio-Version für die Pistole (`python3 tools/mk23_glb.py`): Teile benannt
  (Schlitten = Skin-Zone und Gruppe `Slide`, Magazin, Leuchtpunkte), Marker gesetzt (Visierlinie über die Oberkante der
  Kimme und die Kornspitze), ohne Schalldämpfer, Laser-Modul und lose Patronen, 1,05 Studs lang, Lauf nach -Z. In Studio:
  Import 3D > Pistol.glb (Teile nicht zusammenführen, Einheit Stud), nach ReplicatedStorage > Assets > Weapons, "Pistol" nennen.

- `m60.glb`: "low-poly M60 Machine Gun" von D_U (https://sketchfab.com/DU1701), Lizenz CC-BY-4.0
  (http://creativecommons.org/licenses/by/4.0/), Quelle: https://sketchfab.com/3d-models/low-poly-m60-machine-gun-9defc3535972489c817c5f47551cbebf
- `LMG.glb`: die fertig vorbereitete Studio-Version für das MG (`python3 tools/m60_glb.py`): Teile benannt (Gehäuse,
  Schaft, Handschutz und Zuführdeckel = Skin-Zonen, Deckel = Gruppe `Cover`, Munitionskasten links = `Magazine`,
  Spannhebel = `Bolt`, Leuchtpunkt auf dem Korn), Marker gesetzt (Visierlinie über die Kimmen-Ohren der Klappkimme und
  die Kornspitze), ohne lose Patronen, Gurtstücke und den zweiten Kasten, 4,33 Studs lang, Lauf nach -Z. In Studio:
  Import 3D > LMG.glb (Teile nicht zusammenführen, Einheit Stud), nach ReplicatedStorage > Assets > Weapons, "LMG" nennen.

- `gen12.glb`: "low-poly GEN-12" von D.U. (https://sketchfab.com/D.U.), Lizenz CC-BY-4.0
  (http://creativecommons.org/licenses/by/4.0/), Quelle: https://sketchfab.com/3d-models/low-poly-gen-12-5a8e85a2375948498d76d379e915f3bf
- `Shotgun.glb`: die fertig vorbereitete Studio-Version für die Schrotflinte (`python3 tools/gen12_glb.py`): Teile benannt,
  loses zweites Magazin und lose Patrone entfernt, Notvisiere (Kimme und Korn) auf der Schiene ergänzt, Marker gesetzt.
  Import 3D > Shotgun.glb (Teile nicht zusammenführen, Einheit Stud), nach ReplicatedStorage > Assets > Weapons, "Shotgun" nennen.

- `Rifle_Texturen/Skin_Body_Overlay.png`: Farb-Grundtextur für Farb-Skins am aktuellen Sturmgewehr (Farbe aus
  `Rifle.glb`, gleichmäßige Flächen teilweise durchsichtig), erzeugt mit `python3 tools/models/rifle_overlay.py`.

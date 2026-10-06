# Quellmodelle

- `Meshy_AI_roblox_ar556_lowpoly_*` (Gewehr) und `Meshy_AI_roblox_ar_mag_lowpoly_*` (Magazin): mit Meshy AI erzeugt,
  je eine FBX und vier Texturen (Farbe, Metall, Rauheit, Metall+Rauheit). Daraus macht `python3 tools/rifle_glb.py`
  das Sturmgewehr `Rifle.glb`: eingebautes Magazin herausgeschnitten und das separate Magazin an seine Stelle gesetzt
  (gleiche Größe und Neigung), Fenster des Holo-Visiers geöffnet (es war ein geschlossener Block), vorderes
  Klappkorn umgelegt (stand mitten im Sichtfeld), Spannhebel als `Bolt` herausgetrennt, Marker gesetzt, 4,13 Studs
  lang, Lauf nach -Z, Texturen 1024 x 1024 im GLB. Die Texturen liegen zusätzlich einzeln in `Rifle_Texturen/`.
  In Studio: Import 3D > Rifle.glb (Teile nicht zusammenführen, Einheit Stud), Modell nach ReplicatedStorage >
  Assets > Weapons ziehen, "Rifle" nennen.

- `mp7a1.glb`: "low-poly HK MP7 A1" von D_U (https://sketchfab.com/DU1701), Lizenz CC-BY-4.0
  (http://creativecommons.org/licenses/by/4.0/), Quelle: https://sketchfab.com/3d-models/low-poly-hk-mp7-a1-4715a09c0d054bdba7c0fbf0929a9878
  Daraus erzeugt `python3 tools/mp7_model.py` die SMG (`assets/Weapons/SMG.rbxmx`, aus Quadern nachgebaut;
  der Schalldämpfer des Modells bleibt weg, den baut das Spiel als Aufsatz). Für das echte Mesh in Studio:
  Import 3D mit dieser GLB, Teile benennen und Marker setzen wie in `docs/waffen-modelle.md`.
- `SMG.glb`: die fertig vorbereitete Studio-Version (`python3 tools/mp7_glb.py`): Teile benannt, Marker gesetzt, ohne
  Schalldämpfer, in Studs, Lauf nach -Z. In Studio: Import 3D > SMG.glb (Teile nicht zusammenführen), Modell nach
  ReplicatedStorage > Assets > Weapons ziehen, "SMG" nennen. Dann ersetzt das echte Mesh den Nachbau aus Quadern.

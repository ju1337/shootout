# Quellmodelle

- `mp7a1.glb`: "low-poly HK MP7 A1" von D_U (https://sketchfab.com/DU1701), Lizenz CC-BY-4.0
  (http://creativecommons.org/licenses/by/4.0/), Quelle: https://sketchfab.com/3d-models/low-poly-hk-mp7-a1-4715a09c0d054bdba7c0fbf0929a9878
  Daraus erzeugt `python3 tools/mp7_model.py` die SMG (`assets/Weapons/SMG.rbxmx`, aus Quadern nachgebaut;
  der Schalldämpfer des Modells bleibt weg, den baut das Spiel als Aufsatz). Für das echte Mesh in Studio:
  Import 3D mit dieser GLB, Teile benennen und Marker setzen wie in `docs/waffen-modelle.md`.
- `SMG.glb`: die fertig vorbereitete Studio-Version (`python3 tools/mp7_glb.py`): Teile benannt, Marker gesetzt, ohne
  Schalldämpfer, in Studs, Lauf nach -Z. In Studio: Import 3D > SMG.glb (Teile nicht zusammenführen), Modell nach
  ReplicatedStorage > Assets > Weapons ziehen, "SMG" nennen. Dann ersetzt das echte Mesh den Nachbau aus Quadern.

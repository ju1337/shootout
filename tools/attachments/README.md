# Meshy-Modelle für Waffen und Aufsätze vorbereiten

Jedes Skript nimmt die GLB von Meshy unverändert (Geometrie und Texturen, keine Reduzierung) und macht daraus eine
Datei für Studio (Import 3D, Scale Unit Stud, Merge Meshes aus). Teile über 20.000 Dreiecke werden geteilt.

    python3 tools/attachments/ar15_v2.py  <meshy.glb> art/sources/Rifle_AR15v2.glb     # Sturmgewehr -> Assets/Weapons/Rifle
    python3 tools/attachments/supp_v2.py  <meshy.glb> art/sources/Attachments/Suppressor.glb
    python3 tools/attachments/holo_v2.py  <meshy.glb> art/sources/Attachments/HoloSight.glb
    python3 tools/attachments/grip_v2.py  <meshy.glb> art/sources/Attachments/AngledGrip.glb

- **ar15_v2**: Magazin entlang der schrägen Kante des Schachts als `Magazine` herausgeschnitten, Marker Point_* (Kimme
  und Korn als Visierlinie), 4,13 Studs lang. Die Maße (Kimme, Korn, Griff, Schacht) gelten für dieses eine Meshy-Modell.
- **supp_v2**: Point_Mount (über dem Mündungsfeuerdämpfer), Point_Muzzle (vorderes Ende), 0,21 Studs dick.
- **holo_v2**: Sichtfenster durch das Gehäuse geschnitten (Innenwände, Glas), ein Leuchtpunkt (`Neon_Reticle`, im Spiel
  rund), Point_Mount, Point_SightRear/SightFront.
- **grip_v2**: Point_Mount (Oberkante der Schienenklemme), Point_Front (Richtung zum Lauf).

Modelle in Studio: ReplicatedStorage › Assets › Weapons (`Rifle`) bzw. Assets › Attachments (`Suppressor`, `HoloSight`,
`AngledGrip`). Lader: `src/shared/GunModels.lua`.

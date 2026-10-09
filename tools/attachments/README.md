# Meshy-Modelle für Waffen und Aufsätze vorbereiten

Jedes Skript nimmt die GLB von Meshy unverändert (Geometrie und Texturen, keine Reduzierung) und macht daraus eine
Datei für Studio (Import 3D, Scale Unit Stud, Merge Meshes aus). Teile über 20.000 Dreiecke werden geteilt.

    python3 tools/attachments/ar15_v2.py  <meshy.glb> art/sources/Rifle.glb     # Sturmgewehr -> Assets/Weapons/Rifle
    python3 tools/attachments/supp_v2.py  <meshy.glb> art/sources/Attachments/Suppressor.glb
    python3 tools/attachments/holo_v2.py  <meshy.glb> art/sources/Attachments/HoloSight.glb
    python3 tools/attachments/grip_v2.py  <meshy.glb> art/sources/Attachments/AngledGrip.glb
    python3 tools/attachments/mag_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/ExtendedMag.glb
    python3 tools/attachments/muzzle_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/Compensator.glb Compensator
    python3 tools/attachments/muzzle_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/MuzzleBrake.glb MuzzleBrake

- **ar15_v2**: Magazin entlang der schrägen Kante des Schachts als `Magazine` herausgeschnitten, Marker Point_* (Kimme
  und Korn als Visierlinie), 4,13 Studs lang. Die Maße (Kimme, Korn, Griff, Schacht) gelten für dieses eine Meshy-Modell.
- **supp_v2**: Point_Mount (über dem Mündungsfeuerdämpfer), Point_Muzzle (vorderes Ende), 0,21 Studs dick.
- **holo_v2**: Sichtfenster durch das Gehäuse geschnitten (Innenwände, Glas), ein Leuchtpunkt (`Neon_Reticle`, im Spiel
  rund), Point_Mount, Point_SightRear/SightFront.
- **mag_full**: Magazin in voller Qualität (414.690 Dreiecke in 22 Teilen `Magazine_Ext_01…`), an der Stelle des
  eingebauten AR-Magazins; Point_Mount = Mitte des eingebauten Magazins, um 0,07 Studs versetzt (SEAT_UP/SEAT_BACK),
  damit der Magazinkörper im Schacht steckt (sonst stecken nur die Lippen drin und es sieht schwebend aus). Im Spiel ersetzt es das eingebaute Magazin
  und wandert beim Nachladen mit.
- **muzzle_full**: Mündungsaufsätze in voller Qualität (Kompensator 800 Dreiecke, 0,47 lang; Mündungsbremse 832 Dreiecke,
  0,54 lang; Texturen 4096), 0,15 Studs dick, Ports oben;
  Point_Mount = AR-Mündung (Körper reicht 0,28 dahinter und deckt den Mündungsfeuerdämpfer ab), Point_Muzzle = vorn.
- **grip_v2**: Point_Mount (Oberkante der Schienenklemme), Point_Front (Richtung zum Lauf).

Modelle in Studio: ReplicatedStorage › Assets › Weapons (`Rifle`) bzw. Assets › Attachments (`Suppressor`, `HoloSight`,
`AngledGrip`, `ExtendedMag`, `Compensator`, `MuzzleBrake`). Lader: `src/shared/GunModels.lua`.

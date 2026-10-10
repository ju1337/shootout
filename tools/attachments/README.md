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
    python3 tools/attachments/rifle_barrel.py art/sources/Rifle.glb art/sources/Rifle.glb   # einmalig: Lauf als eigenes Teil
    python3 tools/attachments/barrel_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/LongBarrel.glb LongBarrel 0.65 1 -0.13 2.37
    python3 tools/attachments/barrel_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/ShortBarrel.glb ShortBarrel 0.5 -1 -0.953 2.60
    python3 tools/attachments/barrel_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/HeavyBarrel.glb HeavyBarrel 0.57 -1 -0.952 2.80 0.106
    python3 tools/attachments/grip_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/VerticalGrip.glb VerticalGrip 0.46 1
    python3 tools/attachments/laser_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/Laser.glb

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
- **rifle_barrel**: schneidet den Lauf vor dem Handschutz (Lauf + Mündungsfeuerdämpfer) und sein vorderes Stück im
  Handschutz (ab 1,95) aus `Skin_Body` als `Skin_Body_Barrel` heraus (Schnittflächen geschlossen, alles andere Byte für Byte gleich). Mit Lauf-Aufsatz blendet das
  Spiel ihn aus; Skin-Texturen von `Skin_Body` gelten auch für `Skin_Body_Barrel`.
- **barrel_full**: Lauf-Aufsätze in voller Qualität, auf der Laufachse; das hintere Ende steckt im Handschutz (Skript
  prüft den Innenradius 0,088). Marker Point_Mount (eingebaute Mündung), Point_Front (Richtung), Point_Muzzle (neue
  Mündung: dort sitzen Mündungsaufsätze, Mündungsfeuer und Leuchtspur). Langer Lauf: 924 Dreiecke, Faktor 0,65,
  Mündung 0,35 weiter vorn, Stufe dick/dünn an der Stirnseite des Handschutzes. Kurzer Lauf: 835 Dreiecke, Faktor 0,5,
  Mündung 0,12 weiter hinten (nur der Feuerdämpfer schaut aus dem Handschutz), Laufmutter im Handschutz (Radius 0,084). Schwerer Lauf: 839 Dreiecke, Faktor 0,57, 0,117 dick (statt
  0,09), Gewindeschutzkappe vorn, Mündung 0,08 weiter vorn; die Laufmutter (Radius 0,104) steckt in der Wand des
  Handschutzes (außen 0,112) und ist nur durch die Schlitze zu sehen.
- **grip_full**: Griffe in voller Qualität (Vertikalgriff: 860 Dreiecke, 0,46 hoch), Oberkante der Schienenklemme
  bündig an Point_LeftHand (Unterseite des Handschutzes), Klemmschraube seitlich; Point_Mount, Point_Front.
- **laser_full**: Laser (Seitenmontage) in voller Qualität: 903.568 Dreiecke in 47 Teilen `Laser_01…` (je < 19.500),
  Texturen mit Normal Map in Originalgröße, 0,42 lang; Klemme an der rechten Seitenfläche des Handschutzes, Austritts-
  öffnung nach vorn kurz hinter der Stirnseite. Point_Mount = Point_LeftHand (gleicher Platz wie die Griffe).
- **grip_v2**: Point_Mount (Oberkante der Schienenklemme), Point_Front (Richtung zum Lauf).

Modelle in Studio: ReplicatedStorage › Assets › Weapons (`Rifle`) bzw. Assets › Attachments (`Suppressor`, `HoloSight`,
`AngledGrip`, `ExtendedMag`, `Compensator`, `MuzzleBrake`, `LongBarrel`, `ShortBarrel`, `HeavyBarrel`, `VerticalGrip`, `Laser`). Lader: `src/shared/GunModels.lua`.

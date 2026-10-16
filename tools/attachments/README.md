# Meshy-Modelle für Waffen und Aufsätze vorbereiten

Jedes Skript nimmt die GLB von Meshy unverändert (Geometrie und Texturen, keine Reduzierung) und macht daraus eine
Datei für Studio (Import 3D, Scale Unit Stud, Merge Meshes aus). Teile über 20.000 Dreiecke werden geteilt.

    python3 tools/attachments/ar15_v2.py  <meshy.glb> art/sources/Rifle.glb     # Sturmgewehr -> Assets/Weapons/Rifle
    python3 tools/attachments/sniper_v1.py <meshy.glb> art/sources/DMR.glb      # Präzisionsgewehr -> Assets/Weapons/DMR
    python3 tools/attachments/meshy_weapon.py <Waffe> <meshy-fbx.zip> art/sources/<Waffe>.glb   # Pistol, Revolver, SMG, LMG, Shotgun
    python3 tools/attachments/meshy_attachment.py SMG <Aufsatz> <meshy-zip> <mp-meshy-zip> art/sources/SMG.glb art/sources/Attachments/<Aufsatz>_SMG.glb
                                         # FastMag, Suppressor, Compensator, HoloSight (Rotpunkt) nur für die MP
    python3 tools/attachments/meshy_attachment.py Shotgun <Aufsatz> <meshy-zip> <schrotflinte-meshy-zip> art/sources/Shotgun.glb art/sources/Attachments/<Aufsatz>_Shotgun.glb
                                         # LongBarrel, ShortBarrel, MuzzleBrake, VerticalGrip, Laser, HoloSight nur für die Schrotflinte
    python3 tools/attachments/meshy_attachment.py DMR <Aufsatz> <meshy-zip> art/sources/Meshy_AI_roblox_magnum_sniper_1012115921_texture.glb art/sources/DMR.glb art/sources/Attachments/<Aufsatz>_DMR.glb
                                         # FastMag, ExtendedMag, LongBarrel, HeavyBarrel, Suppressor nur für das Präzisionsgewehr
    python3 tools/attachments/supp_v2.py  <meshy.glb> art/sources/Attachments/Suppressor.glb
    python3 tools/attachments/holo_v2.py  <meshy.glb> art/sources/Attachments/HoloSight.glb
    python3 tools/attachments/grip_v2.py  <meshy.glb> art/sources/Attachments/AngledGrip.glb
    python3 tools/attachments/mag_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/ExtendedMag.glb
    python3 tools/attachments/mag_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/FastMag.glb Magazine_Fast 0.07 0.05 0.5
    python3 tools/attachments/mag_full.py <meshy.fbx> art/sources/Rifle.glb art/sources/Attachments/DrumMag.glb Magazine_Drum 0.06 0.02 0.6
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
- **meshy_weapon**: Meshy-FBX-Export (PNG-Texturen, 4096, als JPEG Qualität 92 in die GLB, Metall+Rauheit in einer Map;
  `meshy_fbx.py`) für Pistole, Revolver, MP, MG und Schrotflinte: Maße, Schnitte und Marker je Waffe in `WEAPONS`.
  Pistol (Glock 17): `Skin_Slide` (Schlitten ab Unterkante) und `Magazine` (Magazinboden, Drehpunkt in der Magazinmitte),
  1,05 Studs. `Extras` = Kopien (nichts wird entfernt): Patrone `Shell` der Schrotflinte (rote Patrone vom Seitenhalter),
  Schnelllader `Loader` des Revolvers (kurze Kopie der Trommel). `Sights` = Kimme und Korn verbessern: `Notch` fräst die
  Kimmenkerbe auf eine Breite, in der das Korn mit Lichtspalt sitzt (Wände und Boden geschlossen), `Dots` setzt
  Leuchtpunkte `Neon_…` bündig auf die Rückseiten (Korn orange, Kimme weiß). Pistole: Kerbe 0,023 → 0,068.
- **meshy_attachment**: Aufsätze für eine bestimmte Meshy-Waffe, im Koordinatensystem ihrer GLB gebaut (gleicher
  Ursprung und Maßstab wie meshy_weapon). Studio-Name `<Aufsatz>_<Waffe>` (z.B. `FastMag_SMG`), an dieser Waffe hat es
  Vorrang vor dem allgemeinen Modell. MP: Schnellmagazin (184.764 Dreiecke, 10 Teile) an die Kontur des eingebauten
  Magazins angepasst (18° geneigt, Abweichung 0,004), Point_Mount = Mitte des größten Magazin-Stücks; Schalldämpfer
  (1.362.272 Dreiecke, 70 Teile, 0,25 Studs dick) und Kompensator (223.448, 12 Teile) mit dem Klemmring über dem
  Laufende; Rotpunkt (633.612, 33 Teile) auf `Point_Optic` der MP (Gehäuserippe), Glas im Fenster, `Neon_Reticle` auf
  der Visierlinie 0,03 Studs über Kimme und Korn. Keine Spiegelung (Schrift bleibt lesbar), nichts reduziert.
  Schrotflinte: `Shotgun.glb` hat dafür Lauf (`Skin_Barrel`, mit Korn) und Röhrenmagazin vor dem Vorderschaft
  (`Skin_Tube`) als eigene Teile. Langer Lauf (98.742 Dreiecke, gleichmäßig skaliert, Mündung 0,73 Studs weiter vorn,
  Perlkorn) und kurzer Lauf (114.650, leicht gestreckt 1,19, Mündung kurz vor dem Vorderschaft, blendet mit `Hide_Tube`
  das Röhrenmagazin davor aus) sitzen hinten am Gehäuse, beide blenden mit `Hide_FrontDot` den Leuchtpunkt des alten
  Korns aus. Mündungsbremse (573.250, 30 Teile): Gewinde steckt in der Laufwand. Vertikalgriff (572.066) unter und
  Laser (660.998, Klemme an der rechten Seite) am Vorderschaft, beide mit `Group_Pump` (gehen beim Repetieren mit).
  Rotpunkt (geschlossenes Rohr, 651.276 Dreiecke): Objektiv und Okular als 24-Eck herausgeschnitten, dazwischen ein
  dunkles Innenrohr, rote Beschichtung am Rand der Öffnung dunkel gefärbt, Glas hinter dem Objektiv mit
  `Neon_Reticle` in der Mitte; Klemme auf der flachen Oberseite des Gehäuses (`Point_Optic`), Visierlinie 0,08 Studs
  über Kimme und Korn.
  Präzisionsgewehr: `DMR.glb` (sniper_v1) hat Lauf (`Skin_Barrel`) und Mündungsbremse (`Skin_Barrel_Brake`) als eigene
  Teile, das Magazin ohne den Schaftboden davor. Langer Lauf (203.118 Dreiecke, Streckung 1,36, Mündung 0,72 Studs
  weiter vorn), schwerer Lauf (1.034.408, 54 Teile, Rippen 1,5-mal so dick, Streckung 1,4, Mündung 0,24 Studs weiter
  vorn) mit Laufmutter am Vorderschaft; Schalldämpfer (832.032) ersetzt nur die Bremse (`Hide_Brake`), Gewinde im
  Laufende; Schnellmagazin (258.858, Zugschlaufe) und erweitertes Magazin (217.506, ragt 0,41 Studs tiefer) in Tiefe
  des eingebauten Magazins, oben im Schacht.
- **sniper_v1**: Scharfschützengewehr mit Zielfernrohr: Zweibein eingeklappt (Beine am Gelenk abgetrennt und nach vorn
  gedreht), `Magazine` und `Bolt` herausgeschnitten, Visierlinie durch Okular- und Objektivmitte (waagrecht), Rumpf in
  Stücke `Skin_Body_01…` unter 19.500 Dreiecken. Lesen/Schreiben der GLB in `glb_io.py`.
- **supp_v2**: Point_Mount (über dem Mündungsfeuerdämpfer), Point_Muzzle (vorderes Ende), 0,21 Studs dick.
- **holo_v2**: Sichtfenster durch das Gehäuse geschnitten (Innenwände, Glas), ein Leuchtpunkt (`Neon_Reticle`, im Spiel
  rund), Point_Mount, Point_SightRear/SightFront.
- **mag_full**: Magazin in voller Qualität (414.690 Dreiecke in 22 Teilen `Magazine_Ext_01…`), an der Stelle des
  eingebauten AR-Magazins; Point_Mount = Mitte des eingebauten Magazins, um 0,07 Studs versetzt (SEAT_UP/SEAT_BACK),
  damit der Magazinkörper im Schacht steckt (sonst stecken nur die Lippen drin und es sieht schwebend aus).
  Schnellmagazin: 30er mit Zugschlaufe, 752 Dreiecke, Faktor 0,5 (Tiefe 0,31 wie der Schacht), 0,07 hoch / 0,05 nach
  hinten versetzt (Körper mittig im Schacht).
  Trommelmagazin: 1.110 Dreiecke, Faktor 0,6 (Trommel 0,74 Durchmesser, 0,44 breit); der Hals des Meshy-Modells ist
  im Verhältnis zur Trommel schmal (0,15 tief statt 0,31 wie der Schacht) – er steckt mittig im Schacht, die Lippen
  enden an der Unterkante (0,06 hoch versetzt), damit nichts seitlich aus dem Gehäuse ragt. Im Spiel ersetzt es das eingebaute Magazin
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
`AngledGrip`, `ExtendedMag`, `Compensator`, `MuzzleBrake`, `LongBarrel`, `ShortBarrel`, `HeavyBarrel`, `VerticalGrip`, `Laser`, `FastMag`, `DrumMag`;
nur MP: `FastMag_SMG`, `Suppressor_SMG`, `Compensator_SMG`, `HoloSight_SMG`; nur Schrotflinte: `LongBarrel_Shotgun`,
`ShortBarrel_Shotgun`, `MuzzleBrake_Shotgun`, `VerticalGrip_Shotgun`, `Laser_Shotgun`, `HoloSight_Shotgun`; nur
Präzisionsgewehr: `FastMag_DMR`, `ExtendedMag_DMR`, `LongBarrel_DMR`, `HeavyBarrel_DMR`, `Suppressor_DMR`). Lader: `src/shared/GunModels.lua`.

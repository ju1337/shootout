# Splitterlicht – Effekt-Werte für Roblox

Legendärer Skin für das Sturmgewehr (AR-15, ca. 4 Studs, Lauf zeigt nach −Z).

**So sind die Werte zu lesen**
- Einheiten: Studs und Sekunden. Zahlen mit Dezimalpunkt, so wie in Roblox Studio.
- Kurven (Size, Transparency): `Zeit → Wert`, Zeit von 0 (Geburt) bis 1 (Lebensende). Beispiel `0 → 0 · 0.25 → 0.22 · 1 → 0` = drei Keypoints.
- Farbverläufe (Color): `Zeit → (R, G, B)` mit Werten von 0–255.
- Bereiche wie `0.35 – 0.6` sind NumberRange (Min – Max).
- **TP** = Third-Person bzw. was andere Spieler sehen. **FP** = Ego-Ansicht des Schützen. **ADS** = Ego-Ansicht beim Zielen.
- Alle Partikelbilder liegen in `Effekte/`. Weiße Bilder werden über `Color` eingefärbt; nur `SL_Emblem.png` ist schon farbig.

## 0. Farbpalette

| Name | RGB |
|---|---|
| Eisweiß (Glühkern) | (230, 250, 255) |
| Cyan | (70, 220, 255) |
| Türkis | (40, 236, 204) |
| Saphir | (52, 110, 245) |
| Violett | (140, 90, 240) |
| Magenta | (235, 80, 200) |
| Rosé | (255, 140, 200) |
| Rosé-Gold (Metall) | (236, 150, 160) |
| Licht | (110, 170, 255) |

## 1. Texturen – SurfaceAppearance

| Eigenschaft | Wert |
|---|---|
| ColorMap | `Texturen/Splitterlicht_Color.png` |
| NormalMap | `Texturen/Splitterlicht_Normal.png` (OpenGL, +Y) |
| RoughnessMap | `Texturen/Splitterlicht_Roughness.png` |
| MetalnessMap | `Texturen/Splitterlicht_Metalness.png` |
| EmissiveMaskContent | `Texturen/Splitterlicht_Emissive.png` |
| EmissiveTint | (255, 255, 255) – weiß, die Aderfarbe (Eisblau/Rosé) kommt aus der ColorMap |
| EmissiveStrength | 2 fest **oder** sanfter Puls 1.6 ↔ 2.4, Periode 3 s (Sinus, synchron zum Waffenlicht) |
| AlphaMode | Overlay (Standard) |

- Größe 1024 × 1024, nahtlos kachelbar. Leuchtende Fläche: **8.6 %** der Textur (nur die Adern zwischen den Kristallplatten).
- Das Muster ist richtungslos und kleinteilig: Kristallplatten von ca. 50 px, zerbrochen in Splitter von ca. 24 px, ohne Text, Streifen oder Vorzugsrichtung. Es verträgt deshalb die zerstückelten, gedrehten UV-Inseln aus Meshy.
- Rosé-Gold-Splitter sind voll metallisch, die übrigen Splitter halb metallisch (wie Folie), die Adern nicht metallisch, damit sie sauber leuchten.

## 2. Effekte an der Waffe (dauerhaft)

### Hilfsobjekte an der Waffe

| Objekt | Typ | Werte |
|---|---|---|
| SL_FX_Unten | Part, unsichtbar | Size (0.3, 0.3, 1.5) (X, Y, Z), Transparency 1, CanCollide/CanQuery/CanTouch = false, Massless = true, an die Waffe geschweißt. Lage: unter dem Verschlussgehäuse, vom Griff bis zum Magazinschacht; Oberkante mind. 0.25 Studs unter der Visierlinie. |
| SL_Muendung | Attachment | vorne am Laufende (bzw. vorne am Schalldämpfer), gleiche Ausrichtung wie die Waffe: −Z = Schussrichtung, also EmissionDirection `Front`. |
| SL_Laufmitte | Attachment | Mitte des Laufs / Handschutzes (für das optionale Laufglühen). |

Warum ein eigener Part: Die Partikel entstehen nur in dieser Box unterhalb der Visierlinie und nie oben auf der Schiene, im Visier oder in der Bildmitte.

### E1 · Kristallglitzer (ParticleEmitter)

_sitzt als Funkeln direkt auf der unteren Waffenhälfte._

| Eigenschaft | TP | FP |
|---|---|---|
| Texture | `SL_Glitzer.png` | = |
| Parent / Ort | SL_FX_Unten (Part) | = |
| Rate (pro s) | 4 | 2 (beim Zielen: 0) |
| Lifetime | 0.35 – 0.6 | = |
| Speed | 0 | = |
| SpreadAngle | (0, 0) | = |
| EmissionDirection | Top | = |
| Size | 0 → 0 · 0.25 → 0.22 · 1 → 0 | = |
| Transparency | 0 → 0.1 · 0.6 → 0.2 · 1 → 1 | = |
| Color | 0 → (230, 250, 255) · 0.5 → (70, 220, 255) · 1 → (255, 140, 200) | = |
| LightEmission | 1 | = |
| LightInfluence | 0 | = |
| Brightness | 2.5 | = |
| Drag | 0 | = |
| Acceleration | (0, 0, 0) | = |
| Shape | Box · Volume · Outward | = |
| Rotation | 0 – 45 | = |
| RotSpeed | 0 | = |
| Orientation | FacingCamera | = |
| LockedToPart | true | = |
| ZOffset | 0.1 | = |
| Max. gleichzeitig | ≈ 3 | ≈ 2 (ADS 0) |

### E2 · Prismensplitter (ParticleEmitter)

_kleine Kristallsplitter, die langsam nach unten wegschweben._

| Eigenschaft | TP | FP |
|---|---|---|
| Texture | `SL_Splitter.png` | = |
| Parent / Ort | SL_FX_Unten (Part) | = |
| Rate (pro s) | 2.5 | 1.2 (beim Zielen: 0) |
| Lifetime | 1.2 – 1.8 | = |
| Speed | 0.15 – 0.35 | = |
| SpreadAngle | (60, 60) | = |
| EmissionDirection | Bottom | = |
| Size | 0 → 0 · 0.15 → 0.09 · 0.8 → 0.08 · 1 → 0 | = |
| Transparency | 0 → 0.3 · 0.2 → 0.1 · 0.75 → 0.25 · 1 → 1 | = |
| Color | 0 → (70, 220, 255) · 0.5 → (140, 90, 240) · 1 → (255, 140, 200) | = |
| LightEmission | 0.6 | = |
| LightInfluence | 0.4 | = |
| Brightness | 1.5 | = |
| Drag | 0.8 | = |
| Acceleration | (0, -0.25, 0) | = |
| Shape | Box · Volume · Outward | = |
| Rotation | 0 – 360 | = |
| RotSpeed | -90 – 90 | = |
| Orientation | FacingCamera | = |
| LockedToPart | false | = |
| ZOffset | 0 | = |
| Max. gleichzeitig | ≈ 5 | ≈ 3 (ADS 0) |

### E3 · Prismenstaub (ParticleEmitter)

_feiner Leuchtstaub, sinkt ganz langsam._

| Eigenschaft | TP | FP |
|---|---|---|
| Texture | `SL_Staub.png` | = |
| Parent / Ort | SL_FX_Unten (Part) | = |
| Rate (pro s) | 5 | 2.5 (beim Zielen: 0) |
| Lifetime | 1 – 1.6 | = |
| Speed | 0.05 – 0.15 | = |
| SpreadAngle | (180, 180) | = |
| EmissionDirection | Bottom | = |
| Size | 0 → 0 · 0.2 → 0.04 · 1 → 0 | = |
| Transparency | 0 → 0.4 · 0.3 → 0.2 · 1 → 1 | = |
| Color | 0 → (230, 250, 255) · 0.5 → (70, 220, 255) · 1 → (140, 90, 240) | = |
| LightEmission | 1 | = |
| LightInfluence | 0 | = |
| Brightness | 2 | = |
| Drag | 1 | = |
| Acceleration | (0, -0.05, 0) | = |
| Shape | Box · Volume · Outward | = |
| Rotation | 0 | = |
| RotSpeed | 0 | = |
| Orientation | FacingCamera | = |
| LockedToPart | false | = |
| ZOffset | 0 | = |
| Max. gleichzeitig | ≈ 8 | ≈ 4 (ADS 0) |

### E4 · Waffenlicht (PointLight)

| Eigenschaft | TP | FP |
|---|---|---|
| Parent | SL_FX_Unten | = |
| Color | (110, 170, 255) | = |
| Brightness | 0.6 ↔ 1 | 0.35 ↔ 0.55 |
| Range | 5 | 3 |
| Puls-Dauer | 3 s pro Zyklus, Sinus (kein Flackern) | = |
| Shadows | false | = |

Puls-Formel: `Brightness = Min + (Max − Min) · (0.5 − 0.5 · cos(2π · t / 3.0))`. Gleiche Formel für EmissiveStrength 1.6 ↔ 2.4, damit Adern und Licht gemeinsam „atmen“.

## 3. Schüsse

Alle Schuss-Emitter: `Enabled = false`, pro Schuss nur `Emit(Anzahl)`. Kein Licht-Blitz pro Schuss (sonst flackert es bei Dauerfeuer). Licht kommt nur über das sanfte Laufglühen (S5).

### S1 · Mündungsblitz

_kurzer Prismenblitz direkt an der Mündung._

| Eigenschaft | TP | FP |
|---|---|---|
| Texture | `SL_Muendungsblitz.png` | = |
| Parent / Ort | SL_Muendung (Attachment) | = |
| Emit pro Schuss | 2 | 1 |
| Lifetime | 0.05 – 0.08 | = |
| Speed | 0 | = |
| SpreadAngle | (0, 0) | = |
| EmissionDirection | Front | = |
| Size | 0 → 0.35 · 0.4 → 0.6 · 1 → 0.3 | 0 → 0.2 · 0.4 → 0.35 · 1 → 0.17 |
| Transparency | 0 → 0 · 0.6 → 0.3 · 1 → 1 | 0 → 0.3 · 0.6 → 0.5 · 1 → 1 |
| Color | 0 → (230, 250, 255) · 0.4 → (70, 220, 255) · 1 → (235, 80, 200) | = |
| LightEmission | 1 | = |
| LightInfluence | 0 | = |
| Brightness | 3 | 2 |
| Drag | 0 | = |
| Acceleration | (0, 0, 0) | = |
| Shape | – (Attachment) | = |
| Rotation | 0 – 360 | = |
| RotSpeed | 0 | = |
| Orientation | FacingCamera | = |
| LockedToPart | true | = |
| ZOffset | 0.2 | 0 |
| Sichtbar max. | 0.08 s | = |

### S2a · Prismaring (Zusatzeffekt vorne)

_liegt quer zum Lauf und gleitet ca. 0.3 Studs nach vorne._

| Eigenschaft | TP | FP |
|---|---|---|
| Texture | `SL_Prismaring.png` | = |
| Parent / Ort | SL_Muendung (Attachment) | = |
| Emit pro Schuss | 1 | 1 (nur jeder 2. Schuss) |
| Lifetime | 0.12 | = |
| Speed | 3 | = |
| SpreadAngle | (0, 0) | = |
| EmissionDirection | Front | = |
| Size | 0 → 0.15 · 1 → 0.55 | 0 → 0.1 · 1 → 0.33 |
| Transparency | 0 → 0.1 · 0.5 → 0.4 · 1 → 1 | 0 → 0.35 · 0.5 → 0.6 · 1 → 1 |
| Color | 0 → (230, 250, 255) · 0.5 → (140, 90, 240) · 1 → (255, 140, 200) | = |
| LightEmission | 1 | = |
| LightInfluence | 0 | = |
| Brightness | 2 | 1.5 |
| Drag | 4 | = |
| Acceleration | (0, 0, 0) | = |
| Shape | – (Attachment) | = |
| Rotation | 0 – 60 | = |
| RotSpeed | 0 | = |
| Orientation | VelocityPerpendicular | = |
| LockedToPart | false | = |
| ZOffset | 0 | = |
| Sichtbar max. | 0.12 s | = |

### S2b · Kristallfunken (Zusatzeffekt vorne)

_kurze Funken nach vorne._

| Eigenschaft | TP | FP |
|---|---|---|
| Texture | `SL_Staub.png` | = |
| Parent / Ort | SL_Muendung (Attachment) | = |
| Emit pro Schuss | 4 | 2 |
| Lifetime | 0.08 – 0.14 | = |
| Speed | 6 – 10 | = |
| SpreadAngle | (18, 18) | = |
| EmissionDirection | Front | = |
| Size | 0 → 0.05 · 1 → 0 | 0 → 0.04 · 1 → 0 |
| Transparency | 0 → 0 · 1 → 1 | 0 → 0.2 · 1 → 1 |
| Color | 0 → (230, 250, 255) · 1 → (255, 140, 200) | = |
| LightEmission | 1 | = |
| LightInfluence | 0 | = |
| Brightness | 2.5 | 2 |
| Drag | 6 | = |
| Acceleration | (0, 0, 0) | = |
| Shape | – (Attachment) | = |
| Rotation | 0 | = |
| RotSpeed | 0 | = |
| Orientation | VelocityParallel | = |
| LockedToPart | false | = |
| ZOffset | 0 | = |
| Sichtbar max. | 0.14 s | = |

### S3 · Leuchtspur

**Variante A – Beam (Hitscan, empfohlen):** Attachment0 = `SL_Muendung`, Attachment1 = Attachment am Trefferpunkt.

| Eigenschaft | TP | FP |
|---|---|---|
| Texture | `SL_Leuchtspur.png` | = |
| TextureMode / TextureLength / TextureSpeed | Stretch / 1 / 0 | = |
| Color (0 = Mündung, 1 = Treffer) | 0 → (230, 250, 255) · 0.25 → (70, 220, 255) · 0.7 → (140, 90, 240) · 1 → (255, 140, 200) | = |
| Transparency (entlang der Spur) | 0 → 0.1 · 0.6 → 0.25 · 1 → 0.55 | 0 → 0.35 · 0.7 → 0.6 · 1 → 1 (blendet vor dem Ziel aus) |
| Width0 / Width1 | 0.1 / 0.04 | 0.06 / 0.02 |
| LightEmission / LightInfluence / Brightness | 1 / 0 / 2 | = |
| FaceCamera / Segments | true / 1 | = |
| Lebensdauer | 0.06 s voll sichtbar, dann in 0.08 s ausblenden (alle Transparency-Werte gleichmäßig Richtung 1), dann löschen; gesamt 0.14 s | 0.04 s + 0.06 s = 0.1 s |

**Variante B – Trail (sichtbares Projektil):** Projektil mit zwei Attachments übereinander (±0.035 Studs) → Spurbreite 0.07 Studs.

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Leuchtspur.png` (TextureMode Stretch) |
| Lifetime | 0.06 s |
| MinLength / MaxLength (= Länge) | 0.05 / 6 Studs |
| WidthScale | 0 → 1 · 1 → 0.3 |
| Color | 0 → (230, 250, 255) · 0.25 → (70, 220, 255) · 0.7 → (140, 90, 240) · 1 → (255, 140, 200) |
| Transparency | 0 → 0.1 · 1 → 1 |
| LightEmission / Brightness / FaceCamera | 1 / 2 / true |

### S4 · Einschlag (max. 0.4 s)

Attachment am Trefferpunkt, so gedreht, dass seine Oberseite (+Y) entlang der Oberflächennormale zeigt; dann wirkt `EmissionDirection = Top` vom Treffer weg. Kein Licht. Für Handys: höchstens 4 Einschläge gleichzeitig je Spieler, ältere sofort entfernen.

#### S4a · Einschlag-Blitz

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Einschlag.png` |
| Emit | 1 |
| Lifetime | 0.1 – 0.14 |
| Speed | 0 |
| SpreadAngle | (0, 0) |
| EmissionDirection | Top |
| Size | 0 → 0.3 · 0.3 → 0.7 · 1 → 0.5 |
| Transparency | 0 → 0 · 0.5 → 0.3 · 1 → 1 |
| Color | 0 → (230, 250, 255) · 0.5 → (70, 220, 255) · 1 → (140, 90, 240) |
| LightEmission | 1 |
| LightInfluence | 0 |
| Brightness | 2.5 |
| Drag | 0 |
| Acceleration | (0, 0, 0) |
| Shape | – (Attachment) |
| Rotation | 0 – 360 |
| RotSpeed | 0 |
| Orientation | FacingCamera |
| LockedToPart | true |

#### S4b · Einschlag-Splitter

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Splitter.png` |
| Emit | 6 |
| Lifetime | 0.25 – 0.4 |
| Speed | 4 – 8 |
| SpreadAngle | (55, 55) |
| EmissionDirection | Top |
| Size | 0 → 0.12 · 1 → 0.04 |
| Transparency | 0 → 0 · 0.7 → 0.2 · 1 → 1 |
| Color | 0 → (70, 220, 255) · 0.5 → (140, 90, 240) · 1 → (255, 140, 200) |
| LightEmission | 0.7 |
| LightInfluence | 0.3 |
| Brightness | 1.8 |
| Drag | 5 |
| Acceleration | (0, -12, 0) |
| Shape | – (Attachment) |
| Rotation | 0 – 360 |
| RotSpeed | -360 – 360 |
| Orientation | FacingCamera |
| LockedToPart | false |

#### S4c · Einschlag-Glitzer

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Glitzer.png` |
| Emit | 2 |
| Lifetime | 0.2 – 0.3 |
| Speed | 1 – 2 |
| SpreadAngle | (40, 40) |
| EmissionDirection | Top |
| Size | 0 → 0 · 0.3 → 0.2 · 1 → 0 |
| Transparency | 0 → 0 · 1 → 1 |
| Color | 0 → (230, 250, 255) · 1 → (255, 140, 200) |
| LightEmission | 1 |
| LightInfluence | 0 |
| Brightness | 2.5 |
| Drag | 0 |
| Acceleration | (0, 0, 0) |
| Shape | – (Attachment) |
| Rotation | 0 – 45 |
| RotSpeed | 0 |
| Orientation | FacingCamera |
| LockedToPart | false |

### S5 · Laufglühen bei Dauerfeuer (optional)

| Wert | Einstellung |
|---|---|
| Hitze h | 0 bis 1; pro Schuss +0.06; nach 0.25 s ohne Schuss −0.5 pro Sekunde |
| Glättung | angezeigter Wert läuft mit Faktor 8/s zu h hin (kein Springen, kein Flackern) |
| Licht | SL_Laufglut (PointLight) an SL_Laufmitte (Attachment); Shadows false |
| Licht-Farbe | linear von (110, 170, 255) bei h = 0 nach (255, 140, 200) bei h = 1 |
| Licht-Brightness | 0.2 + 1.2 · h (FP × 0.6) |
| Licht-Range | 3 + 2 · h |
| EmissiveStrength | Grundwert (2.0 bzw. Puls) + 3 · h |

Beispiel: nach 10 Schüssen ist h = 0.6 → Brightness 0.92, Range 4.2, EmissiveStrength +1.8.

### S6 · Mit Schalldämpfer

- **Andere Spieler:** kein S1, kein S2a, kein S2b; diese Emitter werden für andere gar nicht ausgelöst und nie repliziert.
- **Leuchtspur:** bleibt erlaubt. Optional dezenter: Width × 0.6, alle Transparency-Werte +0.2.
- **Eigene Ansicht (FP):** nur der Kristallhauch unten, vorne am Schalldämpfer, ohne Licht.

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Staub.png` |
| Emit pro Schuss | 2 |
| Lifetime | 0.06 – 0.1 |
| Speed | 1 – 2 |
| SpreadAngle | (25, 25) |
| EmissionDirection | Front |
| Size | 0 → 0.04 · 1 → 0 |
| Transparency | 0 → 0.2 · 1 → 1 |
| Color | 0 → (230, 250, 255) · 1 → (70, 220, 255) |
| LightEmission | 1 |
| LightInfluence | 0 |
| Brightness | 1.5 |
| Drag | 2 |
| Acceleration | (0, 0, 0) |
| Orientation | FacingCamera |
| LockedToPart | false |

## 4. Kill-Finisher „Kristallbruch“ (1.5 s)

Der Gegner erstarrt kurz zu Kristall und zerspringt in schillernde Splitter. Über der Stelle steigt ein Kristall-Emblem auf. Kein Blut, kein Bildschirmeffekt, alles nur an der Position des Gegners.

### Hilfsobjekte

| Objekt | Werte |
|---|---|
| SL_Finisher | unsichtbarer, verankerter Part an der Position (CFrame) des HumanoidRootPart beim Tod; Size (2, 4.5, 1), Anchored, Transparency 1, CanCollide/CanQuery/CanTouch = false. Nach 1.6 s löschen. |
| Attachment „Boden“ | im SL_Finisher, auf Fußhöhe (3 Studs unter dem Root) |
| Attachment „Brust“ | 1.0 Stud über dem Root |
| Attachment „Emblem“ | 1.5 Studs über dem Root |

Auf jedem Client lokal abspielen (z. B. ein Event an alle). So sehen es alle Spieler, und es kostet kaum Netzwerk.

### Ablauf

| Zeit | Was passiert |
|---|---|
| 0.00 s | K1 Highlight auf den Gegner (FillColor (110, 170, 255), FillTransparency 0.6 → 0.25 in 0.30 s, OutlineColor (230, 250, 255), OutlineTransparency 0.35, **DepthMode = Occluded**, damit es nicht durch Wände sichtbar ist). K2 Bodenring Emit 1. K3 Licht beginnt (0 → 1.5 in 0.3 s). |
| 0.10 s | K4 Kristallglanz Emit 10: der Körper funkelt. |
| 0.35 s | K5 Zerspringen: alle Körperteile und Accessoires Transparency 0 → 1 in 0.15 s. K6 Splitter-Explosion Emit 24, K7 Kernblitz Emit 1. Highlight FillTransparency → 0.6. |
| 0.60 s | K8 Kristall-Emblem Emit 1 (steigt auf), K9 Prismenstaub Emit 14. |
| 1.20 s | Highlight in 0.3 s ausblenden (Fill/Outline → 1). Licht ist bei 0. |
| 1.50 s | Alle Partikel sind abgelaufen (spätestes: Emblem 0.6 + 0.9 s). SL_Finisher bei 1.6 s löschen. |

**Licht K3 (PointLight im Attachment „Brust“):** Color (110, 170, 255), Brightness 0 → 1.5 (0.00–0.3 s) → 0 (bis 1.2 s), Range 8, Shadows false.

### K2 · Bodenring (ab 0 s)

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Prismaring.png` |
| Parent / Ort | Attachment „Boden“ (Füße) |
| Emit | 1 |
| Lifetime | 0.8 |
| Speed | 0.01 |
| SpreadAngle | (0, 0) |
| EmissionDirection | Top |
| Size | 0 → 1 · 1 → 6 |
| Transparency | 0 → 0.25 · 0.6 → 0.5 · 1 → 1 |
| Color | 0 → (70, 220, 255) · 1 → (140, 90, 240) |
| LightEmission | 1 |
| LightInfluence | 0 |
| Brightness | 1.5 |
| Drag | 0 |
| Acceleration | (0, 0, 0) |
| Shape | – (Attachment) |
| Rotation | 0 – 60 |
| RotSpeed | 0 |
| Orientation | VelocityPerpendicular |
| LockedToPart | true |

### K4 · Kristallglanz (ab 0.1 s)

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Glitzer.png` |
| Parent / Ort | SL_Finisher (Part) |
| Emit | 10 |
| Lifetime | 0.3 – 0.5 |
| Speed | 0 |
| SpreadAngle | (0, 0) |
| EmissionDirection | Top |
| Size | 0 → 0 · 0.3 → 0.35 · 1 → 0 |
| Transparency | 0 → 0 · 1 → 1 |
| Color | 0 → (230, 250, 255) · 1 → (70, 220, 255) |
| LightEmission | 1 |
| LightInfluence | 0 |
| Brightness | 2.5 |
| Drag | 0 |
| Acceleration | (0, 0, 0) |
| Shape | Box · Volume · Outward |
| Rotation | 0 – 45 |
| RotSpeed | 0 |
| Orientation | FacingCamera |
| LockedToPart | true |

### K6 · Splitter-Explosion (ab 0.35 s)

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Splitter.png` |
| Parent / Ort | SL_Finisher (Part) |
| Emit | 24 |
| Lifetime | 0.6 – 1 |
| Speed | 4 – 7 |
| SpreadAngle | (180, 180) |
| EmissionDirection | Top |
| Size | 0 → 0.25 · 0.7 → 0.2 · 1 → 0 |
| Transparency | 0 → 0 · 0.6 → 0.2 · 1 → 1 |
| Color | 0 → (70, 220, 255) · 0.5 → (140, 90, 240) · 1 → (255, 140, 200) |
| LightEmission | 0.6 |
| LightInfluence | 0.3 |
| Brightness | 2 |
| Drag | 3.5 |
| Acceleration | (0, 1.5, 0) |
| Shape | Box · Volume · Outward |
| Rotation | 0 – 360 |
| RotSpeed | -240 – 240 |
| Orientation | FacingCamera |
| LockedToPart | false |

### K7 · Kernblitz (ab 0.35 s)

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Einschlag.png` |
| Parent / Ort | Attachment „Brust“ (1.0 Stud über Root) |
| Emit | 1 |
| Lifetime | 0.25 |
| Speed | 0 |
| SpreadAngle | (0, 0) |
| EmissionDirection | Top |
| Size | 0 → 1.5 · 0.4 → 3 · 1 → 2.5 |
| Transparency | 0 → 0.3 · 0.5 → 0.6 · 1 → 1 |
| Color | 0 → (230, 250, 255) · 1 → (140, 90, 240) |
| LightEmission | 1 |
| LightInfluence | 0 |
| Brightness | 1.5 |
| Drag | 0 |
| Acceleration | (0, 0, 0) |
| Shape | – (Attachment) |
| Rotation | 0 – 360 |
| RotSpeed | 0 |
| Orientation | FacingCamera |
| LockedToPart | true |

### K8 · Kristall-Emblem (ab 0.6 s)

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Emblem.png` |
| Parent / Ort | Attachment „Emblem“ (1.5 Studs über Root) |
| Emit | 1 |
| Lifetime | 0.9 |
| Speed | 1.5 |
| SpreadAngle | (0, 0) |
| EmissionDirection | Top |
| Size | 0 → 0.5 · 0.25 → 2.2 · 0.8 → 2.2 · 1 → 2.6 |
| Transparency | 0 → 1 · 0.2 → 0.1 · 0.75 → 0.3 · 1 → 1 |
| Color | 0 → (255, 255, 255) · 1 → (255, 255, 255) |
| LightEmission | 0.8 |
| LightInfluence | 0 |
| Brightness | 1.6 |
| Drag | 1 |
| Acceleration | (0, 0, 0) |
| Shape | – (Attachment) |
| Rotation | 0 |
| RotSpeed | 0 |
| Orientation | FacingCameraWorldUp |
| LockedToPart | false |

### K9 · Aufsteigender Prismenstaub (ab 0.6 s)

| Eigenschaft | Wert |
|---|---|
| Texture | `SL_Staub.png` |
| Parent / Ort | SL_Finisher (Part) |
| Emit | 14 |
| Lifetime | 0.6 – 0.9 |
| Speed | 0.5 – 1.5 |
| SpreadAngle | (25, 25) |
| EmissionDirection | Top |
| Size | 0 → 0.08 · 1 → 0 |
| Transparency | 0 → 0.2 · 1 → 1 |
| Color | 0 → (230, 250, 255) · 0.5 → (70, 220, 255) · 1 → (255, 140, 200) |
| LightEmission | 1 |
| LightInfluence | 0 |
| Brightness | 2 |
| Drag | 0.5 |
| Acceleration | (0, 0, 0) |
| Shape | Box · Volume · Outward |
| Rotation | 0 |
| RotSpeed | 0 |
| Orientation | FacingCamera |
| LockedToPart | false |

**Größe** (Root ca. 3 Studs über dem Boden): Bodenring max. 6 Studs Durchmesser. Splitter fliegen max. ca. 1.9 Studs aus dem Körper heraus, Gesamtbreite also ca. 5.9 Studs und höchster Punkt ca. 7.9 Studs über dem Boden. Das Emblem endet ca. 6.7 Studs über dem Boden. Alles bleibt innerhalb von 8 Studs.

**Für Handys:** K6 auf 12 und K9 auf 7 halbieren, wenn die Grafikqualität niedrig ist.

## 5. Partikel-Budget an der Waffe

Maximal gleichzeitig sichtbare Partikel (Rate × längste Lifetime, Schüsse bei 10 Schuss/s Dauerfeuer):

| Effekt | TP | FP | FP beim Zielen |
|---|---|---|---|
| E1 Kristallglitzer | 2.4 | 1.2 | 0.0 |
| E2 Prismensplitter | 4.5 | 2.2 | 0.0 |
| E3 Prismenstaub | 8.0 | 4.0 | 0.0 |
| S1 Mündungsblitz (bei 10 Schuss/s) | 1.6 | 0.8 | 0.8 |
| S2a Prismaring (Zusatzeffekt vorne) (bei 10 Schuss/s) | 1.2 | 0.6 | 0.6 |
| S2b Kristallfunken (Zusatzeffekt vorne) (bei 10 Schuss/s) | 5.6 | 2.8 | 2.8 |
| **Summe** | **23.3** | **11.6** | **4.2** |

Grenze 30 Partikel: TP 23 ✓. FP ist höchstens halb so viel wie TP (11.6 ≤ 11.7) ✓. Beim Zielen schweben keine Dauer-Partikel ✓.

## 6. Regel-Check

| Regel | Umsetzung |
|---|---|
| Nichts vor dem Visier / in der Bildmitte | Dauer-Partikel nur im SL_FX_Unten unter der Visierlinie, in FP beim Zielen Rate 0; Leuchtspur in FP blendet vor dem Ziel aus. |
| FP höchstens halb so viele Partikel | alle Raten in FP halbiert, Prismaring in FP nur bei jedem 2. Schuss (siehe Budget). |
| Kein Flackern, keine Bildschirmblitze, kein Kamerawackeln | Licht pulsiert langsam (3 s Sinus), kein Licht-Blitz pro Schuss, keine ScreenGui- oder Kamera-Effekte. |
| Max. ca. 30 Partikel an der Waffe | siehe Budget. |
| Mündungsfeuer max. 0.15 s | längste Schuss-Lifetime 0.14 s (Funken), Blitz 0.08 s. |
| Einschlag max. 0.4 s | längste Lifetime 0.40 s. |
| Schalldämpfer | Gegner sehen kein Mündungsfeuer; nur eigener Kristallhauch (S6). |
| Finisher max. 1.5 s, max. 8 Studs, kein Gore, keine Vollbild-Blitze | siehe Abschnitt 4; Highlight mit DepthMode Occluded. |


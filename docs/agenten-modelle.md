# Agentenmodelle: von Blender ins Spiel

Das Spiel benutzt für jeden Agenten seine fertige 3D-Ausrüstung, sobald sie in Studio unter
**ReplicatedStorage › Assets › Agents** liegt und so heißt wie der Agent (`Viper`, `Bastion`, …). Solange es kein
Modell gibt oder dem Modell etwas Wichtiges fehlt, trägt der Agent die heutige Quader-Ausrüstung. Dabei geht nichts
kaputt. Das Modell wird überall benutzt:

- an **Spielern** im Hub, im Markt und im Match;
- an **Bots** mit diesem Agenten;
- in allen **Vorschauen**: Agentenwahl, AGENTEN-Seite, Shop, Markt, Hub (Aufstellung, Statue „Agent der Woche“,
  Vitrinen), Siegerpodest nach dem Match und das Agenten-Symbol im HUD.

Der Code steht in `src/shared/AgentModels.lua` (Lader und Prüfungen), angezogen wird in
`src/server-shared/AgentBody.lua` (Spieler und Bots) und `src/shared/AgentFigure.lua` (Vorschauen). Allgemeine
Regeln für alle Modelle (Export-Einstellungen, Geometrie, Texturen, Stil, Abgabe-Checkliste) stehen in
[3d-richtlinien.md](3d-richtlinien.md).

## Grundsatz: ein Körper, eigene Ausrüstung

Alle Agenten haben **denselben Körper**: Roblox R15, klassische Proportionen, schlank (Breite 0,75, Tiefe 0,8),
etwa 5,1 Studs groß. Getroffen werden nur die Körperteile, darum sind alle Agenten gleich leicht zu treffen. Ein
Agent unterscheidet sich durch seine **Ausrüstung** und seine **Farben**.

Dein Modell ist also **nur die Ausrüstung**: starre Teile wie Helm, Visier, Maske, Weste, Taschen, Polster, Gürtel,
Holster, Handschuhe oder Knieschoner. Jedes Teil hängt an **genau einem Körperteil** und bewegt sich mit ihm. Die
Ausrüstung zählt nie als Treffer: Schüsse gehen hindurch. Das stellt das Spiel selbst ein.

## Ablauf

0. **Probelauf mit der Vorlage** (einmal, ca. 10 Minuten): Vorlage in Blender importieren, sofort wieder als FBX
   exportieren, in Studio importieren, in `Viper` umbenennen und nach Assets › Agents legen. Steht beim Spielstart
   im Output `[Agentenmodelle] Viper: 3D-Modell geladen (10 Teile)`, stimmen deine Einstellungen. Meldet es
   „stimmt die Einheit beim Import?“, die Einheit im Import-Fenster von Studio umstellen, bis der Agent etwa
   5 Studs groß ist. Diese Einstellung dann immer benutzen.
1. **Vorlage öffnen**: Blender › Datei › Importieren › Wavefront (.obj) › `art/templates/Agents/Agent.obj`
   (Einstellungen aus [3d-richtlinien.md](3d-richtlinien.md), Abschnitt 2). Darin:
   - der **Agenten-Körper** aus dem Spiel in Ruhelage (Arme hängen, Füße auf dem Boden). Seine 15 Teile heißen genau
     wie die Körperteile (`Head`, `UpperTorso`, …);
   - die **heutige Ausrüstung** (Kapuze, Visier, Maske, Weste, Schulterpolster, Gürtel), schon richtig benannt, in
     den Farben von VIPER;
   - der Marker **`Point_Root`** (magenta) auf 0/0/0 und der Boden `Ref_Ground`.
2. **Modellieren** um den Körper herum, in seiner Ruhelage. Den Körper nicht verschieben, drehen oder verformen. Die
   Quader-Ausrüstung kannst du als Maßstab benutzen und danach löschen oder ersetzen.
3. **Benennen**: jedes Teil `<Körperteil>_<Name>`, bei Bedarf mit `Primary`, `Accent`, `Glass` oder `Neon`
   (siehe [Teilnamen](#teilnamen)).
4. **Körper und `Point_Root` im Modell lassen.** Der Körper wird im Spiel nicht angezeigt. Das Spiel richtet aber die
   Ausrüstung an ihm aus und misst jedes Teil an seinem Körperteil. Dann ist es egal, wie das Modell nach dem Import
   gedreht oder verschoben ist.
5. **Texturieren** (siehe [Farben, Texturen und Skins](#farben-texturen-und-skins)).
6. **Exportieren**: Ausrüstung, Körper und `Point_Root` auswählen, `Strg+A › Alle Transformationen`, dann
   Datei › Exportieren › FBX (.fbx) mit „Nur Auswahl“ und den Einstellungen aus Abschnitt 2 der Richtlinien.
7. **Importieren** in Studio: Import 3D, **Merge Meshes aus** (sonst verschmilzt alles zu einem Teil). Das Modell
   nach **ReplicatedStorage › Assets › Agents** ziehen und genau wie der Agent nennen (Tabelle unten). Ein älteres
   Modell mit demselben Namen vorher löschen.
8. **Spielen** (Play): Im Output steht `[Agentenmodelle] Viper: 3D-Modell geladen (… Teile)` oder, was fehlt.
   Hinweise stehen darunter.
9. **Speichern**: den Place speichern bzw. veröffentlichen. Die Modelle leben im Place, Rojo lässt sie dort in Ruhe.
   Zusätzlich eine Kopie ins Repo: Rechtsklick auf das Modell › „Save to File…“ › als
   `assets/Agents/<Agent>.rbxmx` speichern und committen. GitHub prüft die Kopie dann bei jedem Push
   (siehe [Prüfen](#prüfen)).

**Zum Ausprobieren ohne Blender:** `art/templates/Agents/Agent.rbxmx` per Datei › „Insert from File…“ in Studio
einfügen, in einen Agenten umbenennen (z.B. `Viper`) und nach Assets › Agents legen. Die Vorlage ist selbst ein
gültiges Modell: Der Agent sieht dann genauso aus wie heute, trägt die Ausrüstung aber schon „aus dem Modell“. So
lässt sich der ganze Weg testen.

## Die Agenten

| Name im Modell | Agent | Rolle | Farbe (RGB) | Idee für den Look |
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

Die Farbe ist die Erkennungsfarbe. Im Spiel ist die Uniform (`Primary`) eine abgedunkelte Version davon, die
zweite Farbe (`Accent`) die Farbe selbst. Skins ersetzen beide.

## Körperteile

Maße in Studs (Breite × Höhe × Tiefe) und Höhe der Mitte über dem Boden, wie in der Vorlage. Links und rechts aus
Sicht des Agenten: In der Vorderansicht schaut er dich an, seine linke Hand ist auf deiner rechten Seite.

| Körperteil | Größe | Mitte (Höhe) | Beispiele für Ausrüstung |
|---|---|---|---|
| `Head` | 1,20 × 1,20 × 1,20 | 4,50 | Helm, Kapuze, Visier, Maske, Brille, Headset |
| `UpperTorso` | 1,50 × 1,60 × 0,80 | 3,20 | Weste, Brusttaschen, Funkgerät, kleines Rückenpack |
| `LowerTorso` | 1,50 × 0,40 × 0,80 | 2,20 | Gürtel, Gürteltaschen, Holster |
| `LeftUpperArm`, `RightUpperArm` | 0,75 × 1,17 × 0,80 | 3,37 | Schulterpolster, Abzeichen |
| `LeftLowerArm`, `RightLowerArm` | 0,75 × 1,05 × 0,80 | 2,78 | Armschützer, Display am Unterarm |
| `LeftHand`, `RightHand` | 0,75 × 0,30 × 0,80 | 2,15 | Handschuhe |
| `LeftUpperLeg`, `RightUpperLeg` | 0,75 × 1,22 × 0,80 | 1,58 | Beintasche, Holster am Oberschenkel |
| `LeftLowerLeg`, `RightLowerLeg` | 0,75 × 1,19 × 0,80 | 0,80 | Knieschoner (oben am Unterschenkel), Schienbeinschutz |
| `LeftFoot`, `RightFoot` | 0,75 × 0,30 × 0,80 | 0,15 | Stiefel |

Die Arme hängen 1,125 Studs neben der Mitte, die Beine 0,375. Wie beim echten R15-Körper überlappen die Teile an den
Gelenken.

## Teilnamen

Ein Name besteht aus Wörtern mit `_` dazwischen. Das **erste Wort ist das Körperteil**, an dem das Teil hängt. Danach
folgt ein freier Name, bei Bedarf mit einem dieser Wörter (Groß-/Kleinschreibung beachten):

| Wort | Bedeutung |
|---|---|
| `Primary` | Farbzone Uniform: bekommt die Uniformfarbe des Agenten bzw. Skins |
| `Accent` | Farbzone Akzent: bekommt die zweite Farbe (Weste, Polster, Leuchtstreifen) |
| `Glass` | getöntes Visier: fast schwarz, glänzend, mit einem Schimmer der Akzentfarbe |
| `Neon` | leuchtet (Lämpchen, Anzeigen). Weiß importiert, leuchtet es in der Akzentfarbe |
| `Ref` | nur Maßstab, wird ignoriert (z.B. `Ref_Ground`) |

Beispiele: `Head_Helmet_Primary`, `Head_Visor_Glass`, `Head_Mask`, `UpperTorso_Vest_Accent`,
`UpperTorso_Radio`, `LeftUpperArm_Pad_Accent`, `LowerTorso_Belt`, `RightUpperLeg_Holster`,
`LeftLowerLeg_KneePad`, `LeftLowerArm_Display_Neon`.

- Blender-Endungen wie `.001` zählen nicht. Heißen zwei Teile gleich, hängt das Spiel `_2`, `_3` an.
- Teile, die genau wie ein Körperteil heißen (`Head`, `UpperTorso`, …), sind der **Körper**: Bezug, nicht sichtbar.
- **Ein Material pro Teil**, und was nicht umgefärbt wird, am selben Körperteil zu einem Teil zusammenfügen
  (`Strg+J`).

## Marker

| Marker | Pflicht | Wo |
|---|---|---|
| `Point_Root` | ja (steckt in der Vorlage) | Boden zwischen den Füßen, also 0/0/0 der Vorlage |

Marker sind kleine Würfel, nur ihre Mitte zählt. In Studio geht statt des Würfels auch ein Attachment mit dem Namen
`Point_Root`. Ist der Körper im Modell, richtet sich das Spiel nach ihm. Fehlt dann `Point_Root`, gibt es nur einen
Hinweis.

## Regeln für die Ausrüstung

- **Eng am Körper:** höchstens 0,25 Studs Abstand zur Körperoberfläche, ein Helm höchstens 0,3. Ab 0,45 gibt es
  einen Hinweis. Liegt die Mitte eines Teils mehr als 0,75 neben seinem Körperteil, lädt das Modell nicht. Was weit
  absteht, sieht wie ein Ziel aus, zählt aber nicht als Treffer, und das wäre unfair. Keine großen Rucksäcke,
  Umhänge, Flügel oder langen Antennen.
- **Ein Teil, ein Körperteil:** Nichts geht über ein Gelenk hinweg. Eine Weste sitzt nur am `UpperTorso`, der Gürtel
  ist ein eigenes Teil am `LowerTorso`, ein Knieschoner gehört zum `LowerLeg`. Sonst reißt es beim Laufen
  auseinander.
- **Arme und Hände frei** lassen: Sie halten die Waffe. Schulterpolster nicht so breit, dass sie die Waffe
  verdecken.
- **Gesicht:** Vor dem Gesicht nur Visier (`Glass`) und Maske. Statt eines Roblox-Gesichts tragen alle Agenten Visier
  und Maske. Lässt du beides weg, sieht man einen leeren Kopf.
- Ist ein Körperteil im Spiel etwas anders groß als in der Vorlage (z.B. durch Skalierung), wächst die Ausrüstung je
  Achse mit.

## Farben, Texturen und Skins

**Ohne Textur** färbt das Spiel die Zonen: `Primary` und `Accent` bekommen die Farben des Agenten bzw. seines Skins,
`Glass` wird zum getönten Visier. Teile ohne Zone behalten ihre Farbe aus Studio. Kommen sie ohne Farbe (weiß) an,
werden sie dunkelgrau.

**Texturen (PBR):** ein Textur-Set pro Agent (1024 × 1024) mit Farbe, Normal (OpenGL-Format), Rauheit und Metall. In
Studio bekommt jedes texturierte Teil eine **SurfaceAppearance**. Für Farbzonen **AlphaMode = Overlay**: In der
ColorMap sind die umfärbbaren Flächen durchsichtig (Alpha 0), Details wie Nähte, Kratzer, Schnallen und Schrift
bleiben deckend. So passen die Skins weiter.

**Textur-Skins** (episch, legendär): im Modell einen Ordner `Skins` anlegen, darin je Skin einen Ordner mit der
Skin-Id und darin SurfaceAppearances, die genau so heißen wie die Teile, die sie bekommen, z.B.
`Skins › A_Bastion_Royal › UpperTorso_Vest_Accent`. Ohne eigene Textur bekommt der Skin wie heute nur seine Farben.

| Agent | Skin-Ids (`src/shared/Cosmetics.lua`) |
|---|---|
| `Viper` | `A_Viper_Nacht`, `A_Viper_Gift`, `A_Viper_Saison` |
| `Bastion` | `A_Bastion_Stahl`, `A_Bastion_Royal` |
| `Mender` | `A_Mender_Feld`, `A_Mender_Neon` |
| `Hawk` | `A_Hawk_Wueste`, `A_Hawk_Phantom` |
| `Ghost` | `A_Ghost_Schatten`, `A_Ghost_Nebel` |
| `Blaze` | `A_Blaze_Inferno`, `A_Blaze_Asche` |
| `Aegis` | `A_Aegis_Bollwerk`, `A_Aegis_Sanitaet` |
| `Trapper` | `A_Trapper_Wildnis`, `A_Trapper_Jaeger` |
| `Volt` | `A_Volt_Hochspannung`, `A_Volt_Kupfer` |

## Budget (Handys)

| | Dreiecke | Teile | Textur |
|---|---|---|---|
| Ausrüstung pro Agent | höchstens 6.000, je Teil höchstens 4.000 | höchstens 12 (sonst Hinweis) | 1024 × 1024 |

Jeder Spieler und jeder Bot trägt seine Ausrüstung, im Match sieht man viele Agenten gleichzeitig.

## Prüfen

- **In Studio**: beim Spielstart im Output (`[Agentenmodelle] …`).
- **Auf GitHub**: Liegt eine Kopie als `assets/Agents/<Agent>.rbxmx` im Repo, prüft jeder Push automatisch (Test
  `agentassets`): Das Modell lädt ohne Fehler, Textur-Skins gehören zu echten Skins dieses Agenten, und an einem
  Körper hängt jedes Teil angeschweißt an seinem Körperteil und zählt nie als Treffer. Hinweise stehen als `HINWEIS`
  im Log.
- **Lokal**: `python3 tests/run.py` (siehe README).

## Meldungen und was zu tun ist

| Meldung | Lösung |
|---|---|
| `unbekannter Name – Modelle heißen wie der Agent` | Modell umbenennen: `Viper`, `Bastion`, `Mender`, `Hawk`, `Ghost`, `Blaze`, `Aegis`, `Trapper` oder `Volt` |
| `Marker Point_Root fehlt` | Marker aus der Vorlage übernehmen oder den Körper im Modell lassen |
| `…: der Name beginnt nicht mit einem Körperteil` | Teil umbenennen: `<Körperteil>_<Name>`, z.B. `Head_Helmet` |
| `keine Ausrüstung im Modell` | Ausrüstungsteile wie oben benennen. Nur Körper und Marker reichen nicht |
| `… hängt nicht am Körperteil … (Mitte … Studs daneben)` | Name nennt das falsche Körperteil, oder das Modell ist verschoben, gedreht oder falsch skaliert. Am einfachsten: den Körper aus der Vorlage im Modell lassen |
| `Körper ist …-mal so groß wie im Spiel – stimmt die Einheit beim Import?` | Einheit im Import-Fenster von Studio umstellen (siehe Probelauf) |
| `… steht … Studs vom Körperteil … ab` | Teil enger an den Körper bauen |
| `… Ausrüstungsteile – höchstens 12` | Teile am selben Körperteil ohne eigene Farbzone zusammenfügen |
| `Körperteil … ist … groß, im Spiel …` | den schlanken Agenten-Körper aus der Vorlage benutzen (nicht den Roblox-Standard) |
| `Unbekannter Marker …` | Tippfehler im Namen (z.B. `Point_Rot`) |
| `Skins/…/…: kein Teil mit diesem Namen` | SurfaceAppearance im Skin-Ordner genau wie das Teil benennen |
| `Marker Point_Root fehlt – ausgerichtet am mitgelieferten Körper` | nur ein Hinweis, das Modell lädt |

## Vorlage neu erzeugen

Ändert sich der Agenten-Körper (`AgentModels.Body`) oder die Quader-Ausrüstung (`AgentBody`), die Vorlage neu bauen:

    python3 tools/agent_templates.py

Das schreibt `art/templates/Agents/Agent.obj`, `.mtl` und `.rbxmx`. Der Test `agentmodels` stellt sicher, dass die
Vorlage selbst ein gültiges Modell ist und genauso aussieht wie die Quader-Ausrüstung, auch gedreht und verschoben
importiert.

## Hinweis zu Rojo

Rojo legt den Ordner ReplicatedStorage › Assets › Agents an und lässt die Modelle darin stehen, sie leben im Place.
Eine mit `rojo build` gebaute Place-Datei enthält sie deshalb nicht (dort tragen alle die Quader-Ausrüstung).
Veröffentlicht wird aus Studio.

## Später: eigener Körper

Ein eigener Körper statt des Standard-R15 nur nach Absprache, siehe [3d-richtlinien.md](3d-richtlinien.md),
Abschnitt 7. Jedes Körperteil müsste so groß bleiben wie heute, damit die Trefferzonen gleich bleiben.

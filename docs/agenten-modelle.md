# Agentenmodelle: eigene Figuren ins Spiel bringen

Jeder Agent kann ein eigenes 3D-Modell bekommen. Es reicht, das Modell in Studio an die richtige Stelle zu legen und
richtig zu benennen. Das Spiel benutzt es dann überall:

- an **Spielern** im Hub, im Markt und im Match;
- an **Bots** mit diesem Agenten;
- in allen **Vorschauen**: Agentenwahl, AGENTEN-Seite, Shop, Markt, Hub (Aufstellung, Statue „Agent der Woche“,
  Vitrinen), Siegerpodest nach dem Match und das Agenten-Symbol im HUD.

Solange es kein Modell gibt oder mit dem Modell etwas nicht stimmt, sieht der Agent aus wie bisher (Standardkörper
mit Quader-Ausrüstung). Kaputt geht dabei nichts, und Studio schreibt in den Output, was fehlt.

**Der empfohlene Weg:** Du machst aus deinem Modell in Studio mit dem **Avatar-Setup** einen fertigen
Roblox-Charakter (R15) und legst diesen Charakter in den Ordner der Agenten. Blender, Marker oder besondere
Teilnamen brauchst du dafür nicht.

## In 5 Minuten: Agent einfügen

Du brauchst: Roblox Studio, den Place des Spiels und dein Modell als Datei (`.fbx`, `.obj` oder `.glb`).

1. **Place öffnen:** Studio starten und den Place des Spiels öffnen.
2. **Fenster einblenden:** Reiter **View** › **Explorer**, **Properties** und **Output** anklicken, damit alle
   drei offen sind.
3. **Modell importieren:** Reiter **Home** › **Import 3D** › deine Datei auswählen › im Import-Fenster unten
   **Import** klicken. Das Modell steht jetzt in der Welt und im Explorer unter **Workspace**.
4. **Zum Charakter machen:** Das Modell im Explorer anklicken › Reiter **Avatar** › **Avatar Setup**. Den Schritten
   im Fenster folgen, bis Studio einen fertigen Charakter zeigt. Hat dein Modell noch kein Skelett, richtet Studio
   es dabei automatisch ein.
   - So erkennst du, dass es geklappt hat: Klappst du das Modell im Explorer auf, siehst du einen **Humanoid**, ein
     **HumanoidRootPart** und 15 Körperteile: `Head`, `UpperTorso`, `LowerTorso`, `LeftUpperArm`, `LeftLowerArm`,
     `LeftHand`, `RightUpperArm`, `RightLowerArm`, `RightHand`, `LeftUpperLeg`, `LeftLowerLeg`, `LeftFoot`,
     `RightUpperLeg`, `RightLowerLeg`, `RightFoot`.
   - **Nur ausprobieren, ohne eigenes Modell:** Reiter **Avatar** › **Rig Builder** › **R15** › einen Körper
     auswählen (z.B. Block Avatar). Es entsteht ein „Dummy“ im Workspace. Mit ihm bei Schritt 5 weitermachen.
5. **In den Agenten-Ordner ziehen:** Im Explorer **ReplicatedStorage** › **Assets** › **Agents** aufklappen. Den
   Charakter mit der Maus auf den Ordner **Agents** ziehen. Er muss direkt darin liegen, nicht in einem weiteren
   Ordner.
   - Fehlt der Ordner: Rechtsklick auf ReplicatedStorage › **Insert Object** › **Folder**, `Assets` nennen. Darin
     genauso einen Ordner `Agents` anlegen.
6. **Umbenennen:** Den Charakter anklicken, **F2** drücken (oder Rechtsklick › **Rename**) und **genau wie den
   Agenten** nennen, z.B. `Viper` (alle Namen in der [Liste der Agenten](#liste-der-agenten), Groß- und
   Kleinschreibung beachten). Liegt dort schon ein älteres Modell mit demselben Namen, das alte vorher löschen.
7. **Testen:** Das Modell **vor** dem Start einfügen (nicht während Play – in Play gehören Änderungen im Explorer
   nur zu deinem Bildschirm, der Server sieht sie nicht). Dann Reiter **Home** › **Play** (oder **F5**) und im Spiel
   **genau diesen Agenten** wählen. Im Output steht dann zum Beispiel:

       [Agentenmodelle] Viper: Charakter geladen (15 Teile)
       [Agentenmodelle] DeinName als Viper: ganzer Charakter aus dem Modell

   Steht dort stattdessen „NICHT geladen“, steht direkt darunter, was fehlt (siehe
   [Häufige Probleme](#häufige-probleme)). Mit **Stop** (oder **Umschalt+F5**) beendest du den Test.
8. **Speichern:** **File** › **Publish to Roblox**. Die Modelle leben im Place, nur so bleiben sie erhalten.
   Empfohlen, aber nicht nötig: eine Kopie ins Repo legen, siehe [Prüfen (GitHub)](#prüfen-github).

Fertig. Spieler und Bots mit diesem Agenten sehen jetzt aus wie dein Modell.

## Was das Spiel automatisch macht

Du musst das Modell nicht ausrichten, nicht skalieren und nicht in eine bestimmte Haltung bringen. Das erledigt das
Spiel beim Laden:

- **Erkennen:** Hat das Modell irgendwo einen **Humanoid**, gilt es als ganzer Charakter. Dann müssen alle 15
  Körperteile da sein. Ein Modell ohne Humanoid wird nach der alten Methode geladen (siehe
  [ganz unten](#fortgeschritten-nur-ausrüstung-alte-methode)). Decken seine Teile dabei Kopf, Rumpf, Arme und Beine
  ab, ist es ebenfalls ein ganzer Charakter, und zu sehen ist nur das Modell.
- **Größe:** Das Modell wird auf die Größe des Spielkörpers gebracht (5,1 Studs vom Scheitel bis zu den Füßen), egal
  wie groß es war. Die Proportionen bleiben. Musste es stark verkleinert oder vergrößert werden, kommt ein Hinweis.
- **Blickrichtung:** Vorne ist dort, wohin das **HumanoidRootPart** schaut.
- **Boden:** Der tiefste Punkt der Körperteile (die Füße) steht auf dem Boden.
- **Gelenke:** Jedes Körperteil wird an seinem Gelenk angesetzt (Schulter, Ellbogen, Hüfte, Knie …). Dafür nimmt das
  Spiel die Gelenkpunkte aus dem Avatar-Setup (Attachments wie `LeftShoulderRigAttachment`), sonst die Gelenke
  (Motor6D) des Modells.
- **Haltung:** Arme und Beine werden in die Richtung der Körperteile im Spiel gedreht. Darum geht jede Haltung:
  T-Pose (Arme waagerecht), A-Pose (Arme schräg) oder hängende Arme.
- **Accessoires** (Haare, Helm, Rucksack, Taschen …): Jedes weitere Teil hängt an dem Körperteil, an das es
  geschweißt ist (Accessoires aus Studio sind das automatisch), sonst an dem nächstgelegenen. Ganz unsichtbare Teile
  (Transparency 1) werden weggelassen.
- **Bewegung:** Jedes Teil folgt seinem Körperteil. Laufen, Springen, Zielen und Waffe halten bewegen also dein
  Modell mit, mit den Animationen des Spiels. Eigene Animationen oder Skripte im Modell werden nicht benutzt.
- **Neu laden:** Fügst du ein Modell ein, ersetzt, benennst um oder löschst es, lädt das Spiel es sofort neu und zieht
  alle Spieler und Bots mit diesem Agenten neu an (im laufenden Spiel nur, wenn die Änderung auch auf dem Server
  passiert, z.B. in Studio im Server-Fenster oder im Modus **Run**).
- **Treffer:** Zu sehen ist nur dein Modell. Der normale Agentenkörper bleibt unsichtbar an derselben Stelle und ist
  die **Trefferzone**. So sind alle Agenten gleich leicht zu treffen, egal wie breit oder schmal das Modell ist.
  Teile deines Modells zählen nie als Treffer, Schüsse gehen hindurch. Darum: Sehr breite Teile (große Flügel,
  Umhänge, riesige Schulterplatten) sehen wie ein Ziel aus, sind aber keins. Bleib ungefähr bei der Körperform.
- **Im Explorer während Play:** Dein Modell hängt im Charakter unter **Workspace** › *DeinName* › **AgentModel**. Seine
  Teile heißen wie im Avatar-Setup (`Head`, `UpperTorso` …), damit gehäutete Meshes an den Gelenken sauber bleiben.
  Die Teile direkt im Charakter mit denselben Namen sind der unsichtbare Spielkörper (Transparency 1). Macht ihn
  etwas wieder sichtbar, blendet der Server ihn sofort wieder aus.
- **Aussehen:** Farben, Materialien und Texturen der Teile bleiben, wie du sie in Studio siehst (SurfaceAppearance
  oder die Textur eines MeshParts). Gesichter als Decal am Kopf bleiben auch. Klassische Kleidung (Shirt- und
  Pants-Objekte) wird **nicht** übernommen: Kleidung gehört in das Modell bzw. seine Textur.
- **Farben des Agenten:** Ein Charakter-Modell wird nicht umgefärbt. Es sieht immer so aus, wie du es gebaut hast.
  Für Skins siehe [Textur-Skins](#textur-skins).

## Häufige Probleme

Die Meldungen stehen beim Spielstart im Output, Zeilen mit `[Agentenmodelle]`.

| Meldung oder was du siehst | Was du tun kannst |
|---|---|
| `es fehlen Körperteile: …` | Das Avatar-Setup ist nicht fertig geworden, oder Körperteile wurden umbenannt oder gelöscht. Avatar-Setup bis zum Ende durchlaufen. Die 15 Körperteile müssen genau so heißen wie in Schritt 4. |
| `unbekannter Name – Modelle heißen wie der Agent` | Modell umbenennen: `Viper`, `Bastion`, `Mender`, `Hawk`, `Ghost`, `Blaze`, `Aegis`, `Trapper` oder `Volt`. |
| Im Output steht gar nichts zu deinem Modell | Es liegt nicht direkt in ReplicatedStorage › Assets › Agents (z.B. noch im Workspace oder in einem Unterordner). |
| Der Agent schaut nach hinten oder zur Seite | Die Blickrichtung kommt aus dem HumanoidRootPart. Im Avatar-Setup die Blickrichtung korrigieren. Oder: das importierte Modell vor dem Avatar-Setup so drehen, dass das Gesicht nach vorne zeigt, und das Avatar-Setup neu machen. |
| Arme oder Beine sind verdreht oder abgeknickt | Die Gelenke sitzen an der falschen Stelle. Im Avatar-Setup prüfen, ob Schultern, Ellbogen, Hüfte und Knie richtig gesetzt sind, und es notfalls neu machen. |
| Haare oder Helm wackeln mit der Schulter statt mit dem Kopf | Das Teil ist an kein Körperteil geschweißt und hängt deshalb am nächstgelegenen. Als Accessoire am Kopf anbringen (oder eine WeldConstraint mit Part0 = `Head` und Part1 = das Teil einfügen). |
| `… Teile – für Handys besser höchstens 40` | Nur ein Hinweis, das Modell lädt. Für Handys besser: kleine Accessoires zusammenfassen (im 3D-Programm zu einem Teil verbinden) oder unnötige löschen. |
| `auf … % skaliert (Modell war … Studs hoch …)` | Nur ein Hinweis, das Modell lädt. Sieht es seltsam aus, beim Import die Einheit prüfen. |
| `das Modell ist flach oder leer` | Falsches Modell erwischt oder die Teile haben keine Größe. Neu importieren. |
| `… lässt sich nicht kopieren (Archivable ist aus)` | Teil anklicken, in den Properties **Archivable** anhaken. |
| `Fehler beim Laden: …` | Die ganze Meldung an die Projektleitung schicken. |
| Nach dem Neustart von Studio ist das Modell weg | Den Place mit **File** › **Publish to Roblox** speichern. |
| `… als Viper: Quader-Ausrüstung (kein Modell "Viper" in Assets.Agents)` | Der Server kennt das Modell nicht: Name falsch geschrieben, nicht direkt im Ordner `Agents`, oder während Play nur auf deinem Bildschirm eingefügt. Stop drücken, Modell richtig einfügen, neu starten. |
| Im Spiel steht der normale Körper da – mit Roblox-Gesicht, ohne Modell und ohne Ausrüstung | Das Einkleiden ist nicht gelaufen, oder Roblox hat danach Körperteile ausgetauscht. Der Server prüft das laufend: nach dem Spawn mehrmals, danach alle 5 Sekunden. Er zieht dann neu an, im Output steht `Aussehen verändert (…) – neu angezogen` mit dem Grund in Klammern. Bleibt der Körper so, im Output nach roten Fehlermeldungen suchen (auch weiter oben) und nach der Zeile `… als …:`. Den ganzen Output (Rechtsklick › Alles kopieren) an die Projektleitung schicken. |
| `… als Viper: Ausrüstung aus dem Modell`, und der Spielkörper ist unter dem Modell zu sehen | Das Modell hat keinen Humanoid und deckt nicht Kopf, Rumpf, Arme und Beine ab. Deshalb gilt es nur als Ausrüstung auf dem sichtbaren Körper. Entweder mit dem Avatar-Setup zu einem R15-Rig machen (empfohlen, siehe oben) oder für jedes Körperteil ein Teil `<Körperteil>_<Name>` bauen (siehe [alte Methode](#fortgeschritten-nur-ausrüstung-alte-methode)). |
| Spielkörper und Modell liegen übereinander (der schmale Körper in Agentenfarben schaut durch das Modell) | Der Spielkörper ist die unsichtbare Trefferzone. Macht ihn etwas wieder sichtbar (Roblox beim Laden des Aussehens oder ein Skript), blendet der Server ihn sofort wieder aus. Im Output steht dann einmal `… wieder sichtbar gemacht – sofort wieder ausgeblendet`. Siehst du ihn trotzdem, alle Output-Zeilen mit `[Agentenmodelle]` an die Projektleitung schicken. |
| `Modell konnte nicht angezogen werden (…) – Quader-Ausrüstung` | Beim Anziehen ist ein Fehler passiert, der Agent trägt deshalb die Quader-Ausrüstung. Die Meldung in Klammern an die Projektleitung schicken. |

## Textur-Skins

Die Texturen deines Modells bleiben im Spiel, wie sie sind. Ein Agenten-Skin (episch, legendär) kann zusätzlich
eigene Texturen bekommen:

1. Rechtsklick auf dein Modell (z.B. `Viper`) › **Insert Object** › **Folder**, den Ordner `Skins` nennen. Er muss
   direkt im Modell liegen.
2. In `Skins` je Skin einen Ordner anlegen, benannt mit der **Skin-Id** (Tabelle unten), z.B. `A_Viper_Nacht`.
3. In diesen Ordner je Teil eine **SurfaceAppearance** legen (Rechtsklick › Insert Object › SurfaceAppearance),
   **genau benannt wie das Teil**, das sie bekommen soll, z.B. `UpperTorso`, `Head` oder `LeftUpperLeg`. Die Bilder
   (ColorMap, NormalMap, RoughnessMap, MetalnessMap) in den Properties setzen.

Im Spiel ersetzt diese SurfaceAppearance dann die Textur des Teils, solange der Skin ausgerüstet ist. Teile ohne
eigene SurfaceAppearance im Skin-Ordner behalten ihre normale Textur.

- **Accessoires:** Die Teile in Accessoires heißen oft alle `Handle`. Eine SurfaceAppearance `Handle` bekämen dann
  alle. Willst du einem Accessoire eine eigene Skin-Textur geben, das Teil vorher eindeutig umbenennen (z.B.
  `Haare`, `Helm`) und die SurfaceAppearance genauso nennen.
- **Namen genau prüfen:** Bei einem Charakter-Modell meldet das Spiel keinen Tippfehler im Namen einer
  SurfaceAppearance. Heißt sie anders als das Teil, bleibt einfach die normale Textur.
- **Skins ohne eigenen Ordner:** Sie färben ein Charakter-Modell nicht um. Der Agent sieht mit so einem Skin genauso
  aus wie ohne. Soll jeder Skin anders aussehen, für jeden Skin einen Ordner anlegen.

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

## Liste der Agenten

Das Modell muss genau so heißen wie in der ersten Spalte (die Ids aus `src/shared/AgentConfig.lua`).

| Name im Modell | Agent | Rolle | Farbe (RGB) | Idee für den Look |
|---|---|---|---|---|
| `Viper` | VIPER | Scout | 92, 166, 118 | leicht und schnell: wenig Panzerung, Kapuze, Läufer-Ausrüstung |
| `Bastion` | BASTION | Verteidiger | 88, 124, 186 | schwer: dicke Weste, Helm mit Visier, Schulterplatten (eng anliegend) |
| `Mender` | MENDER | Sanitäter | 196, 92, 86 | Sanitäts-Taschen, Spritzen am Gürtel, grünes Kreuz |
| `Hawk` | HAWK | Aufklärer | 200, 168, 84 | Fernglas oder Zielfernrohr am Helm, Funkgerät, Tarnmuster |
| `Ghost` | GHOST | Infiltrator | 136, 140, 152 | dunkel und schlank, eng anliegende Tarnkleidung, Maske |
| `Blaze` | BLAZE | Stürmer | 206, 112, 58 | Angreifer: Brandspuren, Stoßschutz vorne |
| `Aegis` | AEGIS | Unterstützung | 110, 160, 196 | Heiler und Schutz: Medizin-Pack, Schild-Emblem |
| `Trapper` | TRAPPER | Kontrolle | 156, 132, 92 | Fallensteller: Werkzeuggürtel, Draht, Handschuhe |
| `Volt` | VOLT | Techniker | 204, 190, 86 | Ingenieur: Akku-Pack, Kabel, Werkzeug, leuchtende Anzeigen |

Die Farbe ist die Erkennungsfarbe des Agenten. Es hilft, wenn sie im Modell gut zu sehen ist.

## Prüfen (GitHub)

- **In Studio:** beim Spielstart im Output (Zeilen mit `[Agentenmodelle]`).
- **Kopie ins Repo (empfohlen):** Rechtsklick auf das Modell unter Assets › Agents › **Save to File…** › als
  `<Agent>.rbxmx` speichern (z.B. `Viper.rbxmx`). Die Datei auf GitHub in den Ordner `assets/Agents` hochladen
  (**Add file** › **Upload files**). Das Spiel lädt die Modelle weiter aus dem Place, die Kopie ist nur für die
  Prüfung.
- **Was GitHub dann bei jedem Push prüft** (Test `agentassets`): Das Modell lädt ohne Fehler (bei einem Charakter:
  alle 15 Körperteile da), die Ordner in `Skins` heißen wie echte Skins dieses Agenten, und an einem Testkörper
  hängt jedes Teil des Modells angeschweißt an einem Körperteil und zählt nie als Treffer. Hinweise (z.B. zu viele
  Teile) stehen als `HINWEIS` im Log, sie lassen die Prüfung nicht scheitern.
- **Lokal** (für Entwickler): `python3 tests/run.py` (siehe README).

**Hinweis zu Rojo:** Rojo legt den Ordner ReplicatedStorage › Assets › Agents an und lässt die Modelle darin
stehen. Eine mit `rojo build` gebaute Place-Datei enthält sie aber nicht (dort sehen alle Agenten aus wie ohne
Modell). Veröffentlicht wird deshalb immer aus Studio.

## Fortgeschritten: nur Ausrüstung (alte Methode)

Der ältere Weg funktioniert weiter, ist aber aufwendiger. Er gilt für Modelle **ohne Humanoid**. Dann ist dein Modell
nur die **Ausrüstung** (Helm, Visier, Maske, Weste, Taschen, Polster, Gürtel …), und der Agent behält den sichtbaren
Standardkörper in seinen Farben. Jedes Teil wird an genau ein Körperteil geschweißt und zählt nie als Treffer.

**Ganzer Charakter auf der Vorlage:** Baust du so den kompletten Charakter (mindestens ein Teil für `Head`,
`UpperTorso`, `LowerTorso` und jedes Arm- und Beinteil, z.B. `UpperTorso_Shirt`, `LeftLowerLeg_Hose`), erkennt das
Spiel ihn als ganzen Charakter. Dann ist nur dein Modell zu sehen, der Standardkörper bleibt unsichtbar als
Trefferzone. Im Output steht `Viper: Charakter geladen (… Teile)` und `… als Viper: ganzer Charakter aus dem Modell`.
Fehlen Hände oder Füße, bleibt dort der Standardkörper zu sehen (Hinweis `ganzer Charakter ohne …`).

**Ablauf in Kürze**

1. Vorlage öffnen: Blender › Datei › Importieren › Wavefront (.obj) › `art/templates/Agents/Agent.obj`
   (Einstellungen aus [3d-richtlinien.md](3d-richtlinien.md), Abschnitt 2). Darin: der Spielkörper (15 Teile, die
   wie die Körperteile heißen), die heutige Quader-Ausrüstung schon richtig benannt und der Marker `Point_Root`
   (Boden zwischen den Füßen, auf 0/0/0). Ohne Blender zum Ausprobieren: `art/templates/Agents/Agent.rbxmx` per
   **File** › **Insert from File…** in Studio einfügen, umbenennen, nach Assets › Agents legen.
2. Um den Körper herum modellieren, in seiner Ruhelage (Arme hängen). Den Körper nicht verändern.
3. Jedes Teil `<Körperteil>_<Name>` nennen (siehe unten).
4. **Körper und `Point_Root` im Modell lassen.** Der Körper wird nicht angezeigt, aber das Spiel richtet die
   Ausrüstung an ihm aus. Dann sind Drehung, Lage und Größe nach dem Import egal.
5. Exportieren: alles auswählen, `Strg+A` › Alle Transformationen, Datei › Exportieren › FBX mit „Nur Auswahl“.
6. In Studio: **Import 3D** mit **Merge Meshes aus**, nach Assets › Agents ziehen, wie den Agenten benennen, Play.
   Im Output steht `[Agentenmodelle] Viper: 3D-Modell geladen (… Teile)` oder, was fehlt.

**Teilnamen:** Wörter mit `_` dazwischen, das **erste Wort ist das Körperteil** (`Head`, `UpperTorso`, `LowerTorso`,
`LeftUpperArm`, … wie oben). Danach ein freier Name, bei Bedarf mit einem dieser Wörter:

| Wort | Bedeutung |
|---|---|
| `Primary` | Farbzone Uniform: bekommt die Uniformfarbe des Agenten bzw. Skins |
| `Accent` | Farbzone Akzent: bekommt die zweite Farbe |
| `Glass` | getöntes Visier |
| `Neon` | leuchtet (weiß importiert: in der Akzentfarbe) |
| `Ref` | nur Maßstab, wird ignoriert (z.B. `Ref_Ground`) |

Beispiele: `Head_Helmet_Primary`, `Head_Visor_Glass`, `UpperTorso_Vest_Accent`, `LowerTorso_Belt`,
`LeftLowerLeg_KneePad`. Blender-Endungen wie `.001` zählen nicht. Teile ohne Farbzone, die weiß ankommen, werden
dunkelgrau.

**Körpermaße** (Breite × Höhe × Tiefe in Studs, Höhe der Mitte über dem Boden): `Head` 1,20 × 1,20 × 1,20 (4,50),
`UpperTorso` 1,50 × 1,60 × 0,80 (3,20), `LowerTorso` 1,50 × 0,40 × 0,80 (2,20), Oberarme 0,75 × 1,17 × 0,80 (3,37),
Unterarme 0,75 × 1,05 × 0,80 (2,78), Hände 0,75 × 0,30 × 0,80 (2,15), Oberschenkel 0,75 × 1,22 × 0,80 (1,58),
Unterschenkel 0,75 × 1,19 × 0,80 (0,80), Füße 0,75 × 0,30 × 0,80 (0,15). Die Arme hängen 1,125 Studs neben der
Mitte, die Beine 0,375.

**Regeln:** Eng am Körper bauen (höchstens 0,25 Studs Abstand, Helm 0,3; ab 0,45 kommt ein Hinweis, liegt die Mitte
eines Teils mehr als 0,75 neben seinem Körperteil, lädt das Modell nicht). Nichts über ein Gelenk hinweg (Weste nur am
`UpperTorso`, Gürtel extra am `LowerTorso`). Arme und Hände frei lassen. Höchstens 12 Teile (sonst Hinweis), ein
Material pro Teil, eine Textur 1024 × 1024. Textur-Skins wie oben, die SurfaceAppearances heißen dann wie die
Ausrüstungsteile (z.B. `Skins` › `A_Bastion_Royal` › `UpperTorso_Vest_Accent`). Für Farbzonen mit Textur
**AlphaMode = Overlay** benutzen (umfärbbare Flächen in der ColorMap durchsichtig).

**Meldungen der alten Methode**

| Meldung | Lösung |
|---|---|
| `Marker Point_Root fehlt` | Marker aus der Vorlage übernehmen oder den Körper im Modell lassen |
| `Marker Point_Root fehlt – ausgerichtet am mitgelieferten Körper` | nur ein Hinweis, das Modell lädt |
| `…: der Name beginnt nicht mit einem Körperteil` | Teil umbenennen: `<Körperteil>_<Name>`, z.B. `Head_Helmet` |
| `keine Ausrüstung im Modell` | Ausrüstungsteile wie oben benennen. Nur Körper und Marker reichen nicht |
| `… hängt nicht am Körperteil … (Mitte … Studs daneben)` | falsches Körperteil im Namen, oder das Modell ist verschoben, gedreht oder falsch skaliert. Am einfachsten den Körper aus der Vorlage im Modell lassen |
| `Körper ist …-mal so groß wie im Spiel – stimmt die Einheit beim Import?` | Einheit im Import-Fenster von Studio umstellen, bis der Agent etwa 5 Studs groß ist |
| `… steht … Studs vom Körperteil … ab` | Teil enger an den Körper bauen |
| `… Ausrüstungsteile – höchstens 12` | Teile am selben Körperteil ohne eigene Farbzone zusammenfügen |
| `Körperteil … ist … groß, im Spiel …` | den schlanken Körper aus der Vorlage benutzen, nicht den Roblox-Standard |
| `Unbekannter Marker …` | Tippfehler im Namen (z.B. `Point_Rot`) |
| `Skins/…/…: kein Teil mit diesem Namen` | SurfaceAppearance im Skin-Ordner genau wie das Teil benennen |

**Vorlage neu erzeugen** (wenn sich der Spielkörper `AgentModels.Body` oder die Quader-Ausrüstung in `AgentBody`
ändert): `python3 tools/agent_templates.py`. Das schreibt `art/templates/Agents/Agent.obj`, `.mtl` und `.rbxmx`;
der Test `agentmodels` prüft, dass die Vorlage selbst ein gültiges Modell ist.

**Für Entwickler:** Der Lader mit allen Prüfungen steht in `src/shared/AgentModels.lua`, angezogen wird in
`src/server-shared/AgentBody.lua` (Spieler und Bots) und `src/shared/AgentFigure.lua` (Vorschauen). Allgemeine
Regeln für alle 3D-Modelle stehen in [3d-richtlinien.md](3d-richtlinien.md).

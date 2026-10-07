# Agentenmodelle: eigene Figuren ins Spiel bringen

Jeder Agent kann ein eigenes 3D-Modell bekommen. Das Spiel zeigt es **genau so, wie es in Blender bzw. Studio
aussieht**: dieselben Teile an derselben Stelle, gleich groß, gleich gedreht, mit denselben Farben, Materialien und
Texturen. Nichts wird umgefärbt, gestreckt oder umgebogen. Zu sehen ist das Modell überall:

- an **Spielern** im Hub, im Markt und im Match;
- an **Bots** mit diesem Agenten;
- in allen **Vorschauen**: Agentenwahl, AGENTEN-Seite, Shop, Markt, Hub (Aufstellung, Statue „Agent der Woche“,
  Vitrinen), Siegerpodest nach dem Match und das Agenten-Symbol im HUD.

Solange es kein Modell gibt oder es nicht lädt, hat der Agent den **Standard-Look**: den Roblox-Körper mit dem
Roblox-Gesicht in seinen Farben. Kaputt geht dabei nichts, und Studio schreibt in den Output, was fehlt.

## Am einfachsten: ein fertiger Charakter (Rig)

Funktioniert dein Modell in einer leeren Roblox-Experience als Charakter (z.B. als `StarterCharacter` oder aus dem
**Avatar-Setup**: Humanoid, HumanoidRootPart, R15-Gelenke), dann nimm **genau dieses Modell** und leg es in den
Ordner (Schritte unten). Das Spiel lässt es komplett, wie es ist: Gelenke, gehäutete Meshes, Bones, Accessoires,
Layered Clothing. Es steht mit den Füßen auf dem Boden, hängt am unsichtbaren Spielkörper und übernimmt jedes Bild
dessen Bewegung (Laufen, Springen, Zielen, Waffe halten) über die gleichnamigen Gelenke (`Root`, `Waist`, `Neck`,
`LeftShoulder`, `RightElbow` …). Es sieht also aus und bewegt sich wie in der leeren Experience. Skripte im Modell
(z.B. `Animate`) laufen nicht mit, bewegt wird es vom Spiel.

## Ohne Rig: starre Teile aus Blender

Bau den Agenten auf dem Spielkörper, **in Ruhelage**: Füße auf dem Boden (Höhe 0), Blick nach vorne, **Arme hängen
gerade nach unten**. 1 Blender-Einheit = 1 Stud, der Spielkörper ist 5,1 Studs groß.

- **Ein Teil pro Körperteil** (starre Teile): Jedes Teil bewegt sich mit seinem Körperteil. Nichts über ein Gelenk
  hinweg bauen (Oberarm und Unterarm sind getrennte Teile), sonst reißt es beim Laufen auseinander.
- **Namen:** Das Teil heißt wie das Körperteil oder beginnt damit: `Head_Suit`, `UpperTorso_Suit`,
  `LeftUpperArm_Suit` usw. (`Head`, `UpperTorso`, `LowerTorso`, `LeftUpperArm`, `LeftLowerArm`, `LeftHand`,
  `RightUpperArm`, `RightLowerArm`, `RightHand`, `LeftUpperLeg`, `LeftLowerLeg`, `LeftFoot`, `RightUpperLeg`,
  `RightLowerLeg`, `RightFoot`). Teile mit anderem Namen (Haare, Helm, Rucksack …) hängen an dem Körperteil, dem
  sie am nächsten sind. Blender-Endungen wie `.001` sind egal.
- **Boden (optional):** ein kleiner Würfel `Point_Root` auf 0/0/0 (Boden zwischen den Füßen). Ohne ihn steht der
  tiefste Punkt des Modells auf dem Boden, mittig unter dem Rumpf.
- **Nicht gezeigt** werden: unsichtbare Teile (Transparency 1), Marker `Point_…` und Maßstab-Teile `Ref_…`.

**Körpermaße** zum Bauen (Breite × Höhe × Tiefe in Studs, Höhe der Mitte über dem Boden): `Head` 1,20 × 1,20 × 1,20
(4,50), `UpperTorso` 1,50 × 1,60 × 0,80 (3,20), `LowerTorso` 1,50 × 0,40 × 0,80 (2,20), Oberarme 0,75 × 1,17 × 0,80
(3,37), Unterarme 0,75 × 1,05 × 0,80 (2,78), Hände 0,75 × 0,30 × 0,80 (2,15), Oberschenkel 0,75 × 1,22 × 0,80 (1,58),
Unterschenkel 0,75 × 1,19 × 0,80 (0,80), Füße 0,75 × 0,30 × 0,80 (0,15). Die Arme hängen 1,125 Studs neben der
Mitte, die Beine 0,375. Die Gelenke: Schulter auf 3,76, Ellbogen 3,04, Handgelenk 2,28, Hüfte 2,0, Knie 1,16,
Knöchel 0,25. Liegen die Grenzen deiner Teile auf diesen Gelenken, bleibt beim Bewegen alles lückenlos.

**Exportieren:** alles auswählen, `Strg+A` › Alle Transformationen, Datei › Exportieren › FBX oder glTF (.glb).

## Ins Spiel bringen (Studio)

1. **Place öffnen** und über Reiter **View** die Fenster **Explorer**, **Properties** und **Output** einblenden.
2. **Importieren:** Reiter **Home** › **Import 3D** › deine Datei. Im Fenster: Scale Unit **Stud**, **Merge Meshes
   aus**. **Import** klicken.
3. **In den Ordner ziehen:** Im Explorer **ReplicatedStorage** › **Assets** › **Agents** aufklappen und das Modell
   direkt auf den Ordner **Agents** ziehen (nicht in einen Unterordner).
   - Fehlt der Ordner: Rechtsklick auf ReplicatedStorage › **Insert Object** › **Folder**, `Assets` nennen. Darin
     genauso einen Ordner `Agents` anlegen.
4. **Umbenennen:** genau wie der Agent, z.B. `Viper` (siehe [Liste](#liste-der-agenten), Groß- und Kleinschreibung
   beachten). Ein älteres Modell mit demselben Namen vorher löschen.
5. **Testen:** Das Modell **vor** dem Start einfügen, dann **Play** (F5) und genau diesen Agenten wählen. Im Output:

       [Agentenmodelle] Viper: Rig geladen (17 Teile)        (bzw. "Modell geladen" bei starren Teilen)
       [Agentenmodelle] DeinName als Viper: Modell aus Assets.Agents

6. **Speichern:** **File** › **Publish to Roblox**. Die Modelle leben im Place, nur so bleiben sie erhalten.

## Was das Spiel macht

- **Nichts am Aussehen:** Lage, Größe, Drehung, Farben, Materialien, Texturen (SurfaceAppearance, TextureID) und
  Decals bleiben. Nur wenn das Modell offensichtlich in der falschen Einheit importiert wurde (kleiner als 4 oder
  größer als 6,5 Studs), wird es als Ganzes auf 5,1 Studs gebracht, die Proportionen bleiben.
- **Bewegung:** Ein Rig übernimmt die Gelenkbewegung des Spielkörpers. Starre Teile sind an ihr Körperteil
  geschweißt; ohne Waffe spreizt das Spiel dann die Arme nicht seitlich ab, damit unter den Achseln keine Lücke
  klafft. Beim Tod fällt das Modell mit dem Körper.
- **Treffer:** Der normale Agentenkörper bleibt unsichtbar an derselben Stelle und ist die **Trefferzone**. So sind
  alle Agenten gleich leicht zu treffen. Teile des Modells zählen nie als Treffer, Schüsse gehen hindurch. Darum
  ungefähr bei der Körperform bleiben: Was weit absteht (Flügel, Umhänge), sieht wie ein Ziel aus, ist aber keins.
- **Im Explorer während Play:** Das Modell hängt unter **Workspace** › *DeinName* › **AgentModel** (ein Rig mit
  seinem eigenen Humanoid, der aber nichts steuert). Die Teile direkt im Charakter mit den Körperteil-Namen sind der
  unsichtbare Spielkörper. Macht ihn etwas wieder sichtbar, blendet
  der Server ihn sofort wieder aus.
- **Neu laden:** Fügst du ein Modell ein, ersetzt, benennst um oder änderst es, lädt das Spiel es sofort neu und zieht
  alle Spieler und Bots mit diesem Agenten neu an (im laufenden Spiel nur, wenn die Änderung auf dem Server passiert,
  z.B. im Modus **Run**).

## Häufige Probleme

Die Meldungen stehen beim Spielstart im Output, Zeilen mit `[Agentenmodelle]`.

| Meldung oder was du siehst | Was du tun kannst |
|---|---|
| `unbekannter Name – Modelle heißen wie der Agent` | Modell umbenennen: `Viper`, `Bastion`, `Mender`, `Hawk`, `Ghost`, `Blaze`, `Aegis`, `Trapper` oder `Volt`. |
| Im Output steht gar nichts zu deinem Modell | Es liegt nicht direkt in ReplicatedStorage › Assets › Agents. |
| `… als Viper: Standard-Look (kein Modell "Viper" in Assets.Agents)` | Der Server kennt das Modell nicht: Name falsch, nicht direkt im Ordner, oder während Play nur auf deinem Bildschirm eingefügt. Stop, richtig einfügen, neu starten. |
| `keine sichtbaren Teile im Modell` | Alle Teile sind unsichtbar (Transparency 1) oder das Modell ist leer. Neu importieren. |
| `Modell ist … Studs hoch, auf 5.1 gebracht` | Beim Import stimmte die Einheit nicht (z.B. Zentimeter). Lädt trotzdem; besser mit Scale Unit **Stud** neu importieren. |
| `zu … gehört kein Teil – dort ist nichts zu sehen` | Nur ein Hinweis. An diesem Körperteil hat das Modell nichts (z.B. Hände). |
| `… Teile – für Handys besser höchstens 40` | Nur ein Hinweis. Kleine Teile in Blender zusammenfügen. |
| `… lässt sich nicht kopieren (Archivable ist aus)` | Teil anklicken, in den Properties **Archivable** anhaken. |
| Der Agent schaut nach hinten oder zur Seite | In Blender nach vorne (-Y in Blender, -Z in Roblox) ausrichten bzw. beim Import World Forward **Front** wählen. Bei einem R15-Rig zählt die Blickrichtung des HumanoidRootPart. |
| Ein Teil (z.B. Haare) bewegt sich mit dem falschen Körperteil | Teil umbenennen, sodass es mit dem Körperteil beginnt, z.B. `Head_Hair`. |
| Arme stehen waagerecht ab | Starre Teile in T-Haltung gebaut: in Blender die Arme hängend modellieren. |
| Output sagt `Modell geladen` statt `Rig geladen` | Das Modell ist kein Rig (es fehlt der Humanoid oder das HumanoidRootPart). Dann hängt es starr am Körper, ein Modell mit Bones als Ganzes am Unterkörper (Arme und Beine bewegen sich nicht). Abhilfe: Modell in den Workspace ziehen, anklicken › Reiter **Avatar** › **Avatar Setup** bis zum Ende durchlaufen, das fertige Ergebnis nach Assets.Agents legen und wie den Agenten nennen. Danach steht `Rig geladen` im Output. |
| `Rig ohne Gelenke` oder `Gelenke heißen nicht wie im R15-Rig` | Das Rig hat keine R15-Gelenke und steht deshalb steif. Ebenfalls mit dem Avatar-Setup zu einem R15-Rig machen. |
| Ein Rig bewegt sich nicht (steht steif) | Seine Gelenke heißen nicht wie im R15-Rig (z.B. ein R6-Rig mit `Left Shoulder`). Mit dem Avatar-Setup ein R15-Rig daraus machen. |
| `Modell konnte nicht angezogen werden (…)` oder `Fehler beim Laden: …` | Die ganze Meldung an die Projektleitung schicken. |
| Nach dem Neustart von Studio ist das Modell weg | Den Place mit **File** › **Publish to Roblox** speichern. |

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

## Prüfen (GitHub)

- **Kopie ins Repo (empfohlen):** Rechtsklick auf das Modell unter Assets › Agents › **Save to File…** › als
  `<Agent>.rbxmx` speichern und auf GitHub in den Ordner `assets/Agents` hochladen. Das Spiel lädt die Modelle weiter
  aus dem Place, die Kopie ist nur für die Prüfung.
- **Was GitHub bei jedem Push prüft** (Test `agentassets`): Das Modell lädt ohne Fehler, und an einem Testkörper hängt
  jedes Teil angeschweißt an einem Körperteil und zählt nie als Treffer. Hinweise stehen als `HINWEIS` im Log.
- **Lokal** (für Entwickler): `python3 tests/run.py` (siehe README).

**Hinweis zu Rojo:** Rojo legt den Ordner ReplicatedStorage › Assets › Agents an und lässt die Modelle darin stehen.
Eine mit `rojo build` gebaute Place-Datei enthält sie aber nicht. Veröffentlicht wird deshalb immer aus Studio.

**Für Entwickler:** Der Lader steht in `src/shared/AgentModels.lua`, angezogen wird in
`src/server-shared/AgentBody.lua` (Spieler und Bots) und `src/shared/AgentFigure.lua` (Vorschauen); die Gelenke
eines Rigs übernimmt `AgentModels.SyncJoints`, aufgerufen jedes Bild aus `src/shared/CharacterPose.lua`.

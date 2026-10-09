# Fertige Modelle, die Rojo automatisch in Studio legt

| Datei | landet in Studio unter |
|---|---|
| `Weapons/Rifle.rbxmx` | ReplicatedStorage › Assets › Weapons › Rifle |
| `Attachments/HoloSight.rbxmx` | ReplicatedStorage › Assets › Attachments › HoloSight |
| `Attachments/Suppressor.rbxmx` | ReplicatedStorage › Assets › Attachments › Suppressor |
| `Attachments/AngledGrip.rbxmx` | ReplicatedStorage › Assets › Attachments › AngledGrip |
| `Agents/AS_Scout.rbxmx` | ReplicatedStorage › Assets › Agents › AS_Scout (Agenten-Skin Scout) |
| `Agents/AS_TacticalScout.rbxmx` | ReplicatedStorage › Assets › Agents › AS_TacticalScout (Agenten-Skin Tactical Scout) |
| `Agents/AS_ShadowScout.rbxmx` | ReplicatedStorage › Assets › Agents › AS_ShadowScout (Agenten-Skin Shadow Scout) |
| `Skins/Rifle.rbxmx` | ReplicatedStorage › Assets › Weapons › Rifle › Skins (Texturen + Effekt-Bilder aller Skins) |

Eingetragen in `default.project.json`. Wer Rojo verbindet (`rojo serve` + Connect; Rojo 7.7.1 empfohlen – ältere Versionen lesen die Dateien auch, übertragen MeshParts aber erst ab 7.6), hat die Modelle
– niemand muss mehr die GLB-Dateien importieren. Die Meshes und Texturen sind schon bei Roblox hochgeladen, die
Dateien zeigen nur auf ihre Nummern (rbxassetid).

**Modell ändern:** in Studio neu importieren (Import 3D, Scale Unit Stud, Merge Meshes aus), richtig benennen,
Rechtsklick › Save to File… › als `.rbxm` speichern und umwandeln (Studio speichert neue Typen, die Rojo vor 7.7 nicht lesen kann):

    lune run tools/models/rbxm_to_rbxmx.luau Rifle.rbxm models/Weapons/Rifle.rbxmx
    python3 tools/models/rbxmx_legacy.py models/Weapons/Rifle.rbxmx ContentId:TexturePack

(lune 0.10.5 oder neuer.) Änderungen direkt am Modell in Studio
überschreibt Rojo beim nächsten Sync.

**Ausnahme:** Unter `Rifle` darf Studio eigene Ordner behalten (`$ignoreUnknownInstances`), z.B. die Skin-Texturen
`Skins › W_Drachengold` aus `art/sources/Skins/Drachengold/Drachengold_Studio.lua`. Liegt in einem Place noch das
alte Sturmgewehr, vorher dort `Assets › Weapons › Rifle` löschen, sonst bleiben alte Teile daneben liegen.

Quellen (GLB) und Skripte: `art/sources/`, `tools/attachments/`.

**Skins:** `Skins/Rifle.rbxmx` wird mit `lune run tools/models/skins.luau models/Skins/Rifle.rbxmx` und
`python3 tools/models/skins_legacy.py models/Skins/Rifle.rbxmx` erzeugt (Asset-IDs stehen oben im Skript). Braucht
Rojo ab 7.5 (Lava-Glühen = neuer Content-Typ), empfohlen 7.7.1.

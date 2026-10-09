# Fertige Modelle, die Rojo automatisch in Studio legt

| Datei | landet in Studio unter |
|---|---|
| `Weapons/Rifle.rbxm` | ReplicatedStorage › Assets › Weapons › Rifle |
| `Attachments/HoloSight.rbxm` | ReplicatedStorage › Assets › Attachments › HoloSight |
| `Attachments/Suppressor.rbxm` | ReplicatedStorage › Assets › Attachments › Suppressor |
| `Attachments/AngledGrip.rbxm` | ReplicatedStorage › Assets › Attachments › AngledGrip |

Eingetragen in `default.project.json`. Wer Rojo verbindet (`rojo serve` + Connect, Rojo ab 7.6), hat die Modelle
– niemand muss mehr die GLB-Dateien importieren. Die Meshes und Texturen sind schon bei Roblox hochgeladen, die
Dateien zeigen nur auf ihre Nummern (rbxassetid).

**Modell ändern:** in Studio neu importieren (Import 3D, Scale Unit Stud, Merge Meshes aus), richtig benennen,
Rechtsklick › Save to File… › als `.rbxm` hier überschreiben und pushen. Änderungen direkt am Modell in Studio
überschreibt Rojo beim nächsten Sync.

**Ausnahme:** Unter `Rifle` darf Studio eigene Ordner behalten (`$ignoreUnknownInstances`), z.B. die Skin-Texturen
`Skins › W_Drachengold` aus `art/sources/Skins/Drachengold/Drachengold_Studio.lua`. Liegt in einem Place noch das
alte Sturmgewehr, vorher dort `Assets › Weapons › Rifle` löschen, sonst bleiben alte Teile daneben liegen.

Quellen (GLB) und Skripte: `art/sources/`, `tools/attachments/`.

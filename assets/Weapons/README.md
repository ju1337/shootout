# Waffenmodelle (Kopien für die automatische Prüfung)

Hier liegen Kopien deiner fertigen Waffenmodelle als `.rbxmx`: in Studio Rechtsklick auf das Modell unter
ReplicatedStorage › Assets › Weapons › „Save to File…“ › hier als `<Waffe>.rbxmx` speichern (z.B. `Rifle.rbxmx`).

Das Spiel selbst lädt die Modelle aus dem Place. Die Kopien hier prüft GitHub bei jedem Push (Test `weaponassets`,
dazu laufen `weapons`, `viewmodel` und `pose` mit deinem Modell). Anleitung: [docs/waffen-modelle.md](../../docs/waffen-modelle.md)

`SMG.rbxmx` ist eine Kopie von `models/Weapons/SMG.rbxmx` (MP7 aus Studio) – bei Änderungen beide ersetzen.

`Pistol.rbxmx` ist eine Kopie von `models/Weapons/Pistol.rbxmx` (Mark 23 aus Studio) – bei Änderungen beide ersetzen.

`LMG.rbxmx` ist ein Quader-Nachbau des M60 aus `tools/m60_glb.py --boxes` (gleiche Marker wie `art/sources/LMG.glb`),
bis die Studio-Kopie da ist.

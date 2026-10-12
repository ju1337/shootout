# Waffenmodelle (Kopien für die automatische Prüfung)

Hier liegen Kopien deiner fertigen Waffenmodelle als `.rbxmx`: in Studio Rechtsklick auf das Modell unter
ReplicatedStorage › Assets › Weapons › „Save to File…“ › hier als `<Waffe>.rbxmx` speichern (z.B. `Rifle.rbxmx`).

Das Spiel selbst lädt die Modelle aus dem Place. Die Kopien hier prüft GitHub bei jedem Push (Test `weaponassets`,
dazu laufen `weapons`, `viewmodel` und `pose` mit deinem Modell). Anleitung: [docs/waffen-modelle.md](../../docs/waffen-modelle.md)

`SMG.rbxmx` ist eine Kopie von `models/Weapons/SMG.rbxmx` (MP7 aus Studio) – bei Änderungen beide ersetzen.

`Pistol.rbxmx` ist ein Quader-Nachbau der Mark 23 aus `tools/mk23_glb.py` (gleiche Marker wie `art/sources/Pistol.glb`),
bis die Studio-Kopie da ist.

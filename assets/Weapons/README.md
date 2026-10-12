# Waffenmodelle (Kopien für die automatische Prüfung)

Hier liegen Kopien deiner fertigen Waffenmodelle als `.rbxmx`: in Studio Rechtsklick auf das Modell unter
ReplicatedStorage › Assets › Weapons › „Save to File…“ › hier als `<Waffe>.rbxmx` speichern (z.B. `Rifle.rbxmx`).

Das Spiel selbst lädt die Modelle aus dem Place. Die Kopien hier prüft GitHub bei jedem Push (Test `weaponassets`,
dazu laufen `weapons`, `viewmodel` und `pose` mit deinem Modell). Anleitung: [docs/waffen-modelle.md](../../docs/waffen-modelle.md)

`SMG.rbxmx` ist eine Kopie von `models/Weapons/SMG.rbxmx` (MP7 aus Studio) – bei Änderungen beide ersetzen.

`Pistol.rbxmx` ist eine Kopie von `models/Weapons/Pistol.rbxmx` (Mark 23 aus Studio) – bei Änderungen beide ersetzen.

`LMG.rbxmx` ist eine Kopie von `models/Weapons/LMG.rbxmx` (M60 aus Studio) – bei Änderungen beide ersetzen.

`Revolver.rbxmx` ist eine Kopie von `models/Weapons/Revolver.rbxmx` (Chiappa Rhino aus Studio) – bei Änderungen beide ersetzen.

`Shotgun.rbxmx` ist vorerst ein Quader-Nachbau der Gen-12 (`python3 tools/gen12_glb.py --boxes`), bis die Studio-Kopie kommt.

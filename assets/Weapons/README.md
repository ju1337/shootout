# Waffenmodelle (Kopien für die automatische Prüfung)

Hier liegen Kopien deiner fertigen Waffenmodelle als `.rbxmx`: in Studio Rechtsklick auf das Modell unter
ReplicatedStorage › Assets › Weapons › „Save to File…“ › hier als `<Waffe>.rbxmx` speichern (z.B. `Rifle.rbxmx`).

Das Spiel selbst lädt die Modelle aus dem Place. Die Kopien hier prüft GitHub bei jedem Push (Test `weaponassets`,
dazu laufen `weapons`, `viewmodel` und `pose` mit deinem Modell). Anleitung: [docs/waffen-modelle.md](../../docs/waffen-modelle.md)

Die Kopien `Pistol`, `SMG` und `LMG` entsprechen `models/Weapons/<Waffe>.rbxmx` (Meshy-Waffen aus Studio: Glock 17,
MP5, MG mit Gurtkasten) – bei Änderungen beide ersetzen. Revolver und Schrotflinte folgen nach dem Neuimport mit
Schnelllader bzw. Patrone.

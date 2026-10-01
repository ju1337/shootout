# Shootout

Roblox-Shooter im Stil von Rogue Company: Hub mit Menü und Portalen, Free-for-All, Drop (5v5) und Agenten mit Fähigkeiten.
Alles läuft in **einem** Place – Moduswechsel funktionieren deshalb auch direkt in Studio.

## Entwickeln

    ./rojo serve                 # dann in Studio: Rojo → Connect
    ./rojo build -o build/shootout.rbxlx   # fertige Place-Datei bauen

Maps ändern: `tools/build_maps.py` anpassen und `python3 tools/build_maps.py` ausführen.

## Welt

| Bereich | Mitte | Map |
|---|---|---|
| Hub | (0, 0, 0) | `Workspace.Maps.Hub` |
| Free-for-All | (0, 0, 1500) | `Workspace.Maps.FreeForAll` |
| Drop | (1500, 0, 0) | `Workspace.Maps.Drop` |

## Ordner

- `src/shared` – Client + Server: Waffen-, Agenten- und Moduswerte, Waffen-Client, HUD, Menü, Bewegung
- `src/server-shared` – Server-Dienste: Schaden, Kills, Agenten
- `src/server` – Modus-Verwaltung und Logik pro Modus (`Modes/Hub`, `Modes/FreeForAll`, `Modes/Drop`)
- `src/client` – Client-Start, Gleiten und Zuschauen (Drop)
- `src/maps` – generierte Maps (nicht von Hand bearbeiten)

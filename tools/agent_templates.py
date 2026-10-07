#!/usr/bin/env python3
"""Vorlage für die Agenten-Modelle: art/templates/Agents/Agent.obj (+ .mtl) für Blender und Agent.rbxmx für Studio.

Inhalt (1 Einheit = 1 Stud, oben +Y, vorne -Z wie in Roblox, Boden bei y = 0):
- der Agenten-Körper aus dem Spiel in Ruhelage (src/shared/AgentModels.lua): 15 Teile, die genau wie die
  R15-Körperteile heißen (Head, UpperTorso, ...). Er bleibt im Modell: Das Spiel richtet die Ausrüstung an ihm aus.
- die heutige Quader-Ausrüstung (src/server-shared/AgentBody.lua), schon nach der Spezifikation benannt
  (docs/agenten-modelle.md), z.B. Head_Visor_Glass, UpperTorso_Vest_Accent.
- Marker Point_Root auf 0/0/0 (Boden zwischen den Füßen) und Ref_Ground (Boden, nur Maßstab).
Blender: Datei > Import > Wavefront (.obj). Studio: Datei > Insert from File... (.rbxmx) – nach ReplicatedStorage >
Assets > Agents gelegt und wie ein Agent benannt (z.B. Viper), verhält sie sich genau wie ein fertiges Modell.

Neu erzeugen (z.B. nach Änderungen an AgentModels.Body oder an der Quader-Ausrüstung):
    python3 tools/agent_templates.py [--luau PFAD]
Gebraucht wird der Luau-Interpreter wie für die Tests.
"""
import argparse
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import run  # noqa: E402  (tests/run.py: Bündeln mit der Roblox-Nachbildung)
from asset_templates import write_obj  # noqa: E402
from weapon_templates import write_rbxmx  # noqa: E402

SCRIPT = os.path.join(ROOT, "tools", "agent_templates.luau")
OUT = os.path.join(ROOT, "art", "templates", "Agents")
NAME = "Agent"
MARKER = (255, 0, 255)  # Marker magenta wie bei den Waffen
IDENTITY = (1, 0, 0, 0, 1, 0, 0, 0, 1)


def collect(luau):
    """[Teil] aus tools/agent_templates.luau (läuft in der Test-Engine)"""
    bundle, _ = run.build(SCRIPT, run.project_modules(), "immediate", "{}")
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "agent_templates.luau")
        with open(path, "w", encoding="utf-8") as f:
            f.write(bundle)
        result = subprocess.run([luau, path], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("Luau-Fehler:\n" + result.stdout + result.stderr)
    parts = []
    for line in result.stdout.splitlines():
        fields = line.split("\t")
        if fields[0] != "PART":
            continue
        numbers = [float(v) for v in fields[3:21]]
        parts.append({"name": fields[1], "shape": fields[2], "cframe": numbers[0:12], "size": numbers[12:15],
                      "color": tuple(round(v) for v in numbers[15:18]), "material": fields[21],
                      "transparency": float(fields[22])})
    return parts


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--luau", default=os.environ.get("LUAU", "luau"), help="Luau-Interpreter")
    args = parser.parse_args()
    parts = collect(args.luau)
    parts.append({"name": "Point_Root", "shape": "Block", "cframe": [0, 0, 0, *IDENTITY], "size": (0.1, 0.1, 0.1),
                  "color": MARKER, "material": "SmoothPlastic", "transparency": 0.0})
    parts.append({"name": "Ref_Ground", "shape": "Block", "cframe": [0, -0.03, 0, *IDENTITY], "size": (3.5, 0.05, 3.5),
                  "color": (70, 72, 76), "material": "SmoothPlastic", "transparency": 0.0})
    write_obj(OUT, NAME, parts, [
        "Vorlage Agent - 1 Einheit = 1 Stud, oben +Y, vorne -Z (Roblox), Boden y = 0, Point_Root = Boden zwischen den Füßen.",
        "Head, UpperTorso, ... = der Agenten-Körper aus dem Spiel (im Modell lassen, das Spiel richtet sich danach).",
        "<Körperteil>_<Name> = Ausrüstung (heute: Quader), Ref_Ground nur Maßstab. Spezifikation: docs/agenten-modelle.md"])
    write_rbxmx(NAME, parts, OUT)
    body = sum(1 for p in parts if "_" not in p["name"])
    print("%s: %d Körperteile, %d Ausrüstungsteile -> art/templates/Agents/%s.obj/.mtl/.rbxmx"
          % (NAME, body, len(parts) - body - 2, NAME))


if __name__ == "__main__":
    main()

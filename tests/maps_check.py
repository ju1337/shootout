"""Prüft die erzeugte Markt-Karte (src/maps/Market.model.json) auf alles, was Server und Client darin suchen.

Läuft als Teil von tests/run.py (Test "maps"). Gefangen werden Fehler, die die Luau-Tests nicht sehen, weil sie ihre
eigene kleine Karte bauen: fehlende Teile (z.B. SearchTerminal), Stände ohne Prompt oder Ausstellplätze, Stände, die
nicht zur Mitte zeigen, Rampen, die nicht von Rang zu Rang passen, zu wenig Spawns.
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIGIN = (-1500, 0, -1500)  # MARKET_ORIGIN in tools/build_maps.py
STAND_PARTS = ("Base", "Counter", "Prompt", "Sign", "Display1", "Display2", "Display3", "Display4", "Display5", "Display6")
CLIENT_PARTS = ("SearchTerminal", "CrateWeapon", "CrateAgent", "OverviewBoard", "TopBoard")


def _parts(node, found=None, path=""):
    found = found if found is not None else []
    for child in node.get("Children", []):
        name = child.get("Name", "")
        if child.get("ClassName") in ("Part", "SpawnLocation"):
            found.append((path, child))
        _parts(child, found, name)
    return found


def _pos(part):
    p = part["Properties"]["CFrame"]["CFrame"]["position"]
    return (p[0] - ORIGIN[0], p[1] - ORIGIN[1], p[2] - ORIGIN[2])


def check():
    """Gibt eine Liste von Fehlermeldungen zurück (leer = alles in Ordnung)."""
    problems = []
    with open(os.path.join(ROOT, "src", "maps", "Market.model.json"), encoding="utf-8") as f:
        model = json.load(f)
    parts = _parts(model)
    by_name = {}
    for group, part in parts:
        by_name.setdefault(part["Name"], []).append((group, part))

    # Teile, die der Client sucht (rekursiv unter der Map) und das Tor zurück
    for name in CLIENT_PARTS:
        if len(by_name.get(name, [])) != 1:
            problems.append("%s: genau ein Teil erwartet, gefunden %d" % (name, len(by_name.get(name, []))))
    portals = [part for group, part in parts if group == "Portals" and part["Name"].startswith("Portal_")]
    if [p["Name"] for p in portals] != ["Portal_Hub"]:
        problems.append("Gruppe Portals: genau Portal_Hub erwartet")
    spawns = [part for group, part in parts if group == "Spawns"]
    if len(spawns) < 6:
        problems.append("zu wenige Spawns: %d" % len(spawns))
    for spawn in spawns:
        x, y, z = _pos(spawn)
        if math.hypot(x, z) > 20:
            problems.append("Spawn liegt nicht auf dem Marktplatz: (%.0f, %.0f)" % (x, z))

    # Stände: Ordner Stand_<n> direkt unter der Karte, lückenlos nummeriert, alle Teile da, Vorderseite zur Mitte
    stands = {}
    for folder in model.get("Children", []):
        if folder.get("Name", "").startswith("Stand_"):
            stands[int(folder["Name"].split("_")[1])] = {c["Name"]: c for c in folder.get("Children", [])}
    if sorted(stands) != list(range(1, len(stands) + 1)) or len(stands) < 40:
        problems.append("Stände nicht lückenlos nummeriert oder zu wenige: %d" % len(stands))
    for number, children in stands.items():
        missing = [n for n in STAND_PARTS if n not in children]
        if missing:
            problems.append("Stand %d: fehlt %s" % (number, ", ".join(missing)))
            continue
        base, prompt, display = _pos(children["Base"]), _pos(children["Prompt"]), _pos(children["Display2"])
        if math.hypot(prompt[0], prompt[2]) > math.hypot(base[0], base[2]) - 3:
            problems.append("Stand %d: Prompt liegt nicht vor dem Stand (zur Mitte)" % number)
        o = children["Display2"]["Properties"]["CFrame"]["CFrame"]["orientation"]
        look = (-o[0][2], -o[2][2])  # LookVector des Ausstellplatzes
        to_center = (-display[0], -display[2])
        n = math.hypot(*to_center) or 1
        if (look[0] * to_center[0] + look[1] * to_center[1]) / n < 0.99:
            problems.append("Stand %d: Ausstellplatz schaut nicht zur Mitte" % number)
        # Keine zwei Stände übereinander
    centers = {n: _pos(c["Base"]) for n, c in stands.items() if "Base" in c}
    for a in centers:
        for b in centers:
            if a < b:
                (ax, ay, az), (bx, by, bz) = centers[a], centers[b]
                if abs(ay - by) < 1 and math.hypot(ax - bx, az - bz) < 11:
                    problems.append("Stände %d und %d stehen zu dicht beieinander" % (a, b))

    # Ränge: Stände stehen auf Höhen, die zu den Rampen passen (Oberkante der Rampen trifft die Ränge)
    heights = sorted({round(c[1], 1) for c in centers.values()})
    if len(heights) != 3:
        problems.append("erwartet drei Ränge, gefunden Höhen %s" % heights)
    return problems


if __name__ == "__main__":
    found = check()
    for line in found:
        print("FEHLER: " + line)
    print("Karte in Ordnung" if not found else "%d Fehler" % len(found))

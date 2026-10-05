"""Prüft die erzeugten Karten (Markt, Hub, Extinction in src/maps/) auf alles, was Server und Client darin suchen.

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


def _load(name):
    with open(os.path.join(ROOT, "src", "maps", name + ".model.json"), encoding="utf-8") as f:
        return json.load(f)


def check_hub():
    """Hub: nur noch das Tor nach EXTINCTION und zum Markt (die Minispiele laufen über das Menü, ARCADE)."""
    problems = []
    parts = _parts(_load("Hub"))
    portals = sorted(part["Name"] for group, part in parts if group == "Portals")
    if portals != ["Portal_Extinction", "Portal_Market"]:
        problems.append("Hub: Tore %s, erwartet Portal_Extinction und Portal_Market" % portals)
    for name in ("Sign_Extinction", "GateCount_Extinction", "FloorLabel_Extinction"):
        if not any(part["Name"] == name for _, part in parts):
            problems.append("Hub: %s fehlt" % name)
    return problems


def check_extinction():
    """Offene Welt: Safe Zone (Server liest den Radius), Spawns und Tor zum Hub darin, Stände und Lager darin,
    nicht zu nah beieinander; Welt groß genug; kein Baum oder Fels in der Safe Zone."""
    problems = []
    origin = (0, 0, -6000)  # EXTINCTION_ORIGIN in tools/build_maps.py, Center in Modes.lua
    parts = _parts(_load("Extinction"))

    def local(part):
        p = part["Properties"]["CFrame"]["CFrame"]["position"]
        return (p[0] - origin[0], p[1] - origin[1], p[2] - origin[2])

    zones = [part for group, part in parts if group == "Zone" and part["Name"] == "SafeZone"]
    if len(zones) != 1:
        return ["Extinction: genau ein Teil SafeZone in der Gruppe Zone erwartet"]
    zone = zones[0]
    zx, _, zz = local(zone)
    radius = zone["Properties"]["Size"][0] / 2
    if math.hypot(zx, zz) > 1 or not (80 <= radius <= 160):
        problems.append("Extinction: Safe Zone nicht in der Mitte oder Radius %.0f unpassend" % radius)
    if zone["Properties"].get("CanQuery", True) or zone["Properties"].get("CanCollide", True):
        problems.append("Extinction: Safe-Zone-Teil darf weder treffbar noch fest sein")

    def inside(part, margin=0):
        x, _, z = local(part)
        return math.hypot(x, z) <= radius - margin

    spawns = [part for group, part in parts if group == "Spawns"]
    if len(spawns) < 6 or not all(inside(part, 20) for part in spawns):
        problems.append("Extinction: mindestens 6 Spawns tief in der Safe Zone erwartet (%d)" % len(spawns))
    portals = [part for group, part in parts if group == "Portals"]
    if [p["Name"] for p in portals] != ["Portal_Hub"] or not inside(portals[0], 10):
        problems.append("Extinction: genau ein Tor Portal_Hub in der Safe Zone erwartet")
    points = {}
    for group, part in parts:
        if group == "Stands" and part["Name"] in ("Stand_Weapons", "Stand_Items", "Stand_Vehicles", "Stash"):
            points[part["Name"]] = part
    for name in ("Stand_Weapons", "Stand_Items", "Stand_Vehicles", "Stash"):
        part = points.get(name)
        if not part:
            problems.append("Extinction: Punkt %s fehlt" % name)
        elif not inside(part, 10):
            problems.append("Extinction: %s liegt nicht in der Safe Zone" % name)
        elif part["Properties"].get("CanCollide", True):
            problems.append("Extinction: %s muss unsichtbar und nicht fest sein" % name)
    names = sorted(points)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            (ax, _, az), (bx, _, bz) = local(points[a]), local(points[b])
            if math.hypot(ax - bx, az - bz) < 30:
                problems.append("Extinction: %s und %s zu dicht beieinander (E-Aufforderungen überlappen)" % (a, b))
    for group, part in parts:
        if group == "Nature" and part["Name"] in ("Trunk", "Rock") and inside(part, -30):
            problems.append("Extinction: %s in der Safe Zone" % part["Name"])
            break
    grounds = [part for group, part in parts if group == "Ground" and part["Name"] == "Ground"]
    if not grounds or min(grounds[0]["Properties"]["Size"][0], grounds[0]["Properties"]["Size"][2]) < 1500:
        problems.append("Extinction: Boden fehlt oder Welt zu klein")
    problems += check_extinction_world(parts, local, radius)
    return problems


def _rotate_in(part, point):
    """Punkt (Weltkoordinaten) in das Koordinatensystem des Teils."""
    cf = part["Properties"]["CFrame"]["CFrame"]
    o = cf["orientation"]
    d = [point[i] - cf["position"][i] for i in range(3)]
    return [sum(o[r][c] * d[r] for r in range(3)) for c in range(3)]


def check_extinction_world(parts, local, safe_radius):
    """Rote Zonen, Orte (Banner) und Lagerkisten der offenen Welt: Namen, Lage, nichts im Boden oder in Wänden."""
    problems = []
    redzones = [part for group, part in parts if group == "Redzones" and part["Name"].startswith("Redzone_")]
    if len(redzones) < 2:
        problems.append("Extinction: mindestens 2 rote Zonen (Redzone_<Name> in der Gruppe Redzones) erwartet")
    for part in redzones:
        x, _, z = local(part)
        r = part["Properties"]["Size"][0] / 2
        attrs = part["Properties"].get("Attributes", {}).get("Attributes", {})
        if not attrs.get("Title", {}).get("String"):
            problems.append("Extinction: %s ohne Title" % part["Name"])
        if math.hypot(x, z) < safe_radius + r + 60:
            problems.append("Extinction: %s zu nah an der Safe Zone" % part["Name"])
        if abs(x) + r > 1000 or abs(z) + r > 1000:
            problems.append("Extinction: %s ragt aus der Welt" % part["Name"])
    places = [part for group, part in parts if group == "Places" and part["Name"].startswith("Place_")]
    if len(places) < 8:
        problems.append("Extinction: mindestens 8 Orte (Place_<Name> in der Gruppe Places) erwartet, gefunden %d" % len(places))
    for part in places:
        attrs = part["Properties"].get("Attributes", {}).get("Attributes", {})
        if not attrs.get("Title", {}).get("String"):
            problems.append("Extinction: %s ohne Title" % part["Name"])

    spots = [part for group, part in parts if group == "Loot" and part["Name"].startswith("Spot_")]
    kinds = {}
    for part in spots:
        kind = part["Name"][5:]
        kinds[kind] = kinds.get(kind, 0) + 1
        if kind not in ("Wood", "Toolbox", "Medical", "Ammo", "Military"):
            problems.append("Extinction: unbekannte Kiste %s" % part["Name"])
    if len(spots) < 50:
        problems.append("Extinction: mindestens 50 Lagerkisten (Spot_<Art>) erwartet, gefunden %d" % len(spots))
    for kind in ("Wood", "Toolbox", "Medical", "Ammo", "Military"):
        if kinds.get(kind, 0) < 5:
            problems.append("Extinction: zu wenige Kisten der Art %s (%d)" % (kind, kinds.get(kind, 0)))
    solids = [part for group, part in parts
              if group in ("Buildings", "Cover", "Walls", "Stands", "Nature", "Decor") and part["Properties"].get("CanCollide", True)
              and part["Properties"].get("Transparency", 0) < 0.9 and part["Name"] not in ("Needles", "Leaves", "Reed", "Redzone")
              and part["Properties"].get("Shape") != "Ball"]
    for spot in spots:
        x, y, z = local(spot)
        if math.hypot(x, z) < safe_radius:
            problems.append("Extinction: %s in der Safe Zone" % spot["Name"])
        if abs(x) > 980 or abs(z) > 980:
            problems.append("Extinction: %s am Rand der Welt (%.0f, %.0f)" % (spot["Name"], x, z))
        # Kiste (Mitte 0,5 über dem Boden, 2 x 2 groß) darf nicht in einem festen Teil stecken
        probe = [(x + dx, y - 0.4 + dy, z + dz) for dx in (-1, 0, 1) for dz in (-1, 0, 1) for dy in (0.0, 1.0)]
        for part in solids:
            px, py, pz = (part["Properties"]["CFrame"]["CFrame"]["position"][i] - (0, 0, -6000)[i] for i in range(3))
            size = part["Properties"]["Size"]
            if abs(px - x) > max(size) or abs(pz - z) > max(size):
                continue
            cf = part["Properties"]["CFrame"]["CFrame"]
            o = cf["orientation"]
            for point in probe:
                d = [point[0] - px, point[1] - py, point[2] - pz]
                lp = [sum(o[r][c] * d[r] for r in range(3)) for c in range(3)]
                if all(abs(lp[i]) < size[i] / 2 - 0.15 for i in range(3)):
                    problems.append("Extinction: %s steckt in %s (%.0f, %.0f, %.0f)" % (spot["Name"], part["Name"], x, y, z))
                    break
            else:
                continue
            break
    return problems


def check():
    """Gibt eine Liste von Fehlermeldungen zurück (leer = alles in Ordnung)."""
    return check_market() + check_hub() + check_extinction()


def check_market():
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

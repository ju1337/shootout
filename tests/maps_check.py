"""Prüft die erzeugten Karten (Markt, Hub, Extinction in src/maps/) auf alles, was Server und Client darin suchen.

Läuft als Teil von tests/run.py (Test "maps"). Gefangen werden Fehler, die die Luau-Tests nicht sehen, weil sie ihre
eigene kleine Karte bauen: fehlende Teile (z.B. SearchTerminal), Stände ohne Prompt oder Ausstellplätze, Stände, die
nicht zur Mitte zeigen, Rampen, die nicht von Rang zu Rang passen, zu wenig Spawns.
"""
import json
import math
import os
import re

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
    points = {}  # je Name der Punkt im Camp (Safehouses haben eigene Stände mit denselben Namen; den Spielermarkt gibt es nur im Camp)
    camp_points = ("Stand_Weapons", "Stand_Items", "Stand_Vehicles", "Stash", "Stand_Market", "Hideout")
    for group, part in parts:
        if group == "Stands" and part["Name"] in camp_points and inside(part, 10):
            points[part["Name"]] = part
    for name in camp_points:
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
    # Safehouses: kleine Safe Zones draußen (SafeZone_<Name> mit Title), je mindestens 3 Spawns in Spawns_<Name> darin
    houses = [part for group, part in parts if group == "Zone" and part["Name"].startswith("SafeZone_")]
    if len(houses) < 3:
        problems.append("Extinction: mindestens 3 Safehouses (SafeZone_<Name>) erwartet, gefunden %d" % len(houses))
    for house in houses:
        key = house["Name"][len("SafeZone_"):]
        hx, _, hz = local(house)
        hr = house["Properties"]["Size"][0] / 2
        if not house["Properties"].get("Attributes", {}).get("Attributes", {}).get("Title"):
            problems.append("Extinction: %s ohne Title" % house["Name"])
        if math.hypot(hx, hz) < radius + 300:
            problems.append("Extinction: %s zu nah am Camp" % house["Name"])
        own = [part for group, part in parts if group == "Spawns_" + key]
        if len(own) < 3 or not all(math.hypot(local(p)[0] - hx, local(p)[2] - hz) <= hr - 8 for p in own):
            problems.append("Extinction: %s braucht mindestens 3 Spawns in Spawns_%s darin" % (house["Name"], key))
    # Safehouses haben alle Händler und ein Lager; die Punkte (samt Haltestelle) liegen wie im Camp mindestens 30 Studs
    # auseinander, damit sich die E-Aufforderungen nicht überlappen
    for house in houses:
        key = house["Name"][len("SafeZone_"):]
        hx, _, hz = local(house)
        hr = house["Properties"]["Size"][0] / 2
        own = {}
        for name in ("Stand_Weapons", "Stand_Items", "Stand_Vehicles", "Stash", "Travel_" + key):
            for group, part in parts:
                if group == "Stands" and part["Name"] == name and math.hypot(local(part)[0] - hx, local(part)[2] - hz) <= hr - 4:
                    own[name] = local(part)
            if name not in own and not name.startswith("Travel_"):
                problems.append("Extinction: %s ohne %s" % (house["Name"], name))
        names = sorted(own)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                if math.hypot(own[a][0] - own[b][0], own[a][2] - own[b][2]) < 30:
                    problems.append("Extinction: %s: %s und %s zu dicht beieinander (E-Aufforderungen überlappen)"
                                    % (house["Name"], a, b))
    # Haltestellen zum Reisen: eine im Camp ("Travel"), eine je Safehouse ("Travel_<Name>"), jeweils in ihrer Safe Zone
    stops = {part["Name"]: part for group, part in parts if group == "Stands" and part["Name"].startswith("Travel")}
    if "Travel" not in stops or not inside(stops["Travel"], 10):
        problems.append("Extinction: Haltestelle Travel im Camp fehlt")
    for house in houses:
        key = house["Name"][len("SafeZone_"):]
        stop = stops.get("Travel_" + key)
        hx, _, hz = local(house)
        if not stop or math.hypot(local(stop)[0] - hx, local(stop)[2] - hz) > house["Properties"]["Size"][0] / 2 - 4:
            problems.append("Extinction: Haltestelle Travel_%s fehlt oder liegt nicht im Safehouse" % key)
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


def _redzone_config():
    """Radius, MaxPlaceSize und Exclude der roten Zone aus src/shared/ExtinctionConfig.lua (ExtinctionConfig.Redzone)."""
    with open(os.path.join(ROOT, "src", "shared", "ExtinctionConfig.lua"), encoding="utf-8") as f:
        block = re.search(r"\nExtinctionConfig\.Redzone = \{(.*?)\n\}", f.read(), re.S).group(1)
    radius = float(re.search(r"\bRadius = (\d+)", block).group(1))
    biggest = float(re.search(r"\bMaxPlaceSize = (\d+)", block).group(1))
    exclude = set(re.findall(r'"(\w+)"', re.search(r"\bExclude = \{(.*?)\}", block).group(1)))
    return radius, biggest, exclude


def check_extinction_world(parts, local, safe_radius):
    """Orte (Banner, Ziele der roten Zone) und Lagerkisten der offenen Welt: Namen, Lage, nichts im Boden oder in Wänden."""
    problems = []
    # Es gibt genau eine rote Zone, und die wandert (RedzoneService): feste Zonen auf der Karte darf es nicht mehr geben
    for group, part in parts:
        if group == "Redzones" or part["Name"].startswith("Redzone_"):
            problems.append("Extinction: feste rote Zone %s/%s – die rote Zone wandert (RedzoneService)" % (group, part["Name"]))
            break
    places = [part for group, part in parts if group == "Places" and part["Name"].startswith("Place_")]
    if len(places) < 8:
        problems.append("Extinction: mindestens 8 Orte (Place_<Name> in der Gruppe Places) erwartet, gefunden %d" % len(places))
    for part in places:
        attrs = part["Properties"].get("Attributes", {}).get("Attributes", {})
        if not attrs.get("Title", {}).get("String"):
            problems.append("Extinction: %s ohne Title" % part["Name"])
    # Ziele der roten Zone wie RedzoneService.Candidates (ohne Wasser): genug, damit sie alle 20 Minuten woanders steht
    radius, biggest, exclude = _redzone_config()
    houses = [part for group, part in parts if group == "Zone" and part["Name"].startswith("SafeZone_")]
    targets = []
    for part in places:
        key = part["Name"][len("Place_"):]
        x, _, z = local(part)
        if key in exclude or key.startswith("Safe_") or part["Properties"]["Size"][0] > biggest:
            continue
        if math.hypot(x, z) < safe_radius + radius + 40:
            continue
        if any(math.hypot(x - local(h)[0], z - local(h)[2]) < h["Properties"]["Size"][0] / 2 + radius + 20 for h in houses):
            continue
        targets.append(key)
    if len(targets) < 6:
        problems.append("Extinction: zu wenige Orte für die rote Zone (%d: %s)" % (len(targets), ", ".join(sorted(targets))))

    # Lagerkisten (Spot_<Art>) sind abgeschaltet (keine Beute am Boden, ContainerService.Enabled); falls die Karte
    # wieder welche bekommt, müssen die Arten stimmen
    for group, part in parts:
        if group == "Loot" and part["Name"].startswith("Spot_") and part["Name"][5:] not in ("Wood", "Toolbox", "Medical", "Ammo", "Military"):
            problems.append("Extinction: unbekannte Kiste %s" % part["Name"])
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

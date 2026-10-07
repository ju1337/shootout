#!/usr/bin/env python3
"""Blender-Vorlagen für Fahrzeuge und Items: art/templates/Vehicles/<Id>.obj und art/templates/Items/<Id>.obj (+ .mtl).

Maßstab 1 Einheit = 1 Stud, oben = +Y, vorne = -Z (Roblox), Boden bei y = 0. Spezifikation: docs/3d-richtlinien.md.
- Fahrzeuge: das heutige Quader-Fahrzeug aus dem Spiel (VehicleService) in Ruhelage. Ref_Chassis ist der unsichtbare
  Rumpf, der im Spiel kollidiert und getroffen wird; Wheel_* sind die Räder an ihrer Achse (Durchmesser wie im Spiel);
  Seat_* sind Marker auf der Sitzfläche (Seat_Driver = Fahrer). Helikopter: Point_Rotor / Point_TailRotor sind die
  Drehpunkte der Rotoren (Hauptrotor dreht um +Y, Heckrotor um +X). Ref_* nur zum Drumherum-Bauen, vor dem Export löschen.
- Items, Gadgets, Behälter: Ref_<Id> ist die Zielgröße (Boden bei y = 0), Point_Grip die Stelle der rechten Hand.

Neu erzeugen (z.B. nach Änderungen an ExtinctionConfig.Vehicles oder VehicleService):
    python3 tools/asset_templates.py [--luau PFAD]
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
from weapon_templates import outward, shape_faces, transform  # noqa: E402

SCRIPT = os.path.join(ROOT, "tools", "asset_templates.luau")
OUT_VEHICLES = os.path.join(ROOT, "art", "templates", "Vehicles")
OUT_ITEMS = os.path.join(ROOT, "art", "templates", "Items")
MARKER = (255, 0, 255)       # Marker magenta wie bei den Waffen
REF = (150, 156, 166)        # Vorlagen-Quader grau
REF_ALPHA = 0.35
IDENTITY = (1, 0, 0, 0, 1, 0, 0, 0, 1)

# Items, Gadgets und Behälter: (Id, Form, Größe x/y/z, Griff der rechten Hand oder None, Notiz).
# Größen in Studs (bewusst etwas größer als echt, damit sie in der Hand und als Symbol gut lesbar sind),
# Zylinder liegen wie in Roblox entlang X. Behälter wie heute im Spiel (ExtinctionConfig.Loot / Containers).
ITEMS = [
    ("Bandage", "Cylinder", (0.45, 0.6, 0.6), (0, 0.3, 0), "Verband: Rolle, Ende lose"),
    ("Medkit", "Block", (1.4, 1.0, 0.45), (0, 1.0, 0), "Medikit: Koffer mit Griff oben, Symbol vorne (-Z)"),
    ("Adrenaline", "Cylinder", (1.2, 0.28, 0.28), (0, 0.14, 0), "Adrenalin: Autoinjektor, gelb"),
    ("AntiZombie", "Cylinder", (1.2, 0.26, 0.26), (0.25, 0.13, 0), "Anti-Zombie-Spritze: grünes Serum, Nadel nach +X"),
    ("Vest", "Block", (1.7, 1.9, 0.6), (0, 1.9, 0), "Schutzweste: Plattenträger, aufrecht, Vorderseite -Z"),
    ("HeavyVest", "Block", (1.9, 2.1, 0.8), (0, 2.1, 0), "Schwere Weste: mit Kragen und Schulterschutz"),
    ("Ammo_9mm", "Block", (0.8, 0.55, 0.5), (0, 0.275, 0), "9mm: kleine Pappschachtel"),
    ("Ammo_Magnum", "Block", (0.7, 0.5, 0.5), (0, 0.25, 0), "Magnum: kleine Schachtel, dunkelrot"),
    ("Ammo_Shell", "Block", (1.0, 0.6, 0.6), (0, 0.3, 0), "Schrot: Schachtel, rote Patronen sichtbar"),
    ("Ammo_Rifle", "Block", (1.3, 0.9, 0.6), (0, 0.9, 0), "Gewehrmunition: Munitionskiste aus Metall, oliv"),
    ("Gadget_Frag", "Block", (0.55, 0.75, 0.55), (0, 0.35, 0), "Splittergranate (wird geworfen)"),
    ("Gadget_Flash", "Block", (0.45, 0.85, 0.45), (0, 0.4, 0), "Blendgranate: Zylinder stehend"),
    ("Gadget_Smoke", "Block", (0.5, 0.95, 0.5), (0, 0.45, 0), "Rauchgranate: Zylinder stehend"),
    ("Gadget_Sensor", "Block", (1.0, 0.3, 1.0), (0, 0.15, 0), "Sensor-Mine: flache Scheibe, kleine Antenne"),
    ("Loot_Death", "Block", (2.4, 1.7, 1.8), None, "Todestasche: großer Rucksack (rotes Licht oben)"),
    ("Loot_Drop", "Block", (1.5, 1.1, 1.3), None, "Fallen gelassener Beutel"),
    ("Crate_Wood", "Block", (3.4, 2.4, 2.4), None, "Holzkiste"),
    ("Crate_Toolbox", "Block", (3.4, 2.0, 2.0), None, "Werkzeugkiste, rot"),
    ("Crate_Medical", "Block", (3.0, 2.0, 2.2), None, "Sani-Kiste, weiß"),
    ("Crate_Ammo", "Block", (3.2, 1.8, 2.0), None, "Munitionskiste, oliv"),
    ("Crate_Military", "Block", (4.0, 2.6, 2.6), None, "Militärkiste"),
    ("Airdrop", "Block", (5.0, 3.6, 5.0), None, "Versorgungsabwurf (Kiste, Fallschirm optional)"),
]


# ---------- Daten aus dem Spiel ----------

def collect_vehicles(luau):
    """{ Fahrzeug: [Teil] } aus tools/asset_templates.luau (läuft in der Test-Engine)"""
    bundle, _ = run.build(SCRIPT, run.project_modules(), "immediate", "{}")
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "asset_templates.luau")
        with open(path, "w", encoding="utf-8") as f:
            f.write(bundle)
        result = subprocess.run([luau, path], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("Luau-Fehler:\n" + result.stdout + result.stderr)
    vehicles = {}
    for line in result.stdout.splitlines():
        fields = line.split("\t")
        if fields[0] != "PART":
            continue
        numbers = [float(v) for v in fields[5:23]]
        vehicles.setdefault(fields[1], []).append({
            "name": fields[2], "class": fields[3], "shape": fields[4], "cframe": numbers[0:12], "size": numbers[12:15],
            "color": tuple(round(v) for v in numbers[15:18]), "material": fields[23], "transparency": float(fields[24]),
        })
    return vehicles


def template_parts(vehicle, parts):
    """Spielteile -> Vorlage: Rumpf als Ref_Chassis, Räder nach Lage benannt, Sitze als Marker, Rest als Ref_*."""
    out = []
    wheels = [p for p in parts if p["name"] == "Wheel"]
    for part in parts:
        name, x, y, z = part["name"], part["cframe"][0], part["cframe"][1], part["cframe"][2]
        if name == "Skid":
            continue  # unsichtbare Gleitkugeln (Physik), nicht Teil des Aussehens
        if name == "Wheel":
            if len(wheels) == 2:
                name = "Wheel_F" if z < 0 else "Wheel_R"
            else:
                name = "Wheel_" + ("F" if z < 0 else "R") + ("L" if x < 0 else "R")
            out.append(dict(part, name=name, color=(40, 40, 44), transparency=0.0))
        elif part["class"] in ("VehicleSeat", "Seat"):
            seat = "Seat_Driver" if part["class"] == "VehicleSeat" else "Seat_" + name.replace("Seat", "")
            top = y + part["size"][1] / 2
            out.append(marker(seat, (x, top, z), 0.12))
        elif name == "Chassis":
            out.append(dict(part, name="Ref_Chassis", color=(230, 120, 40), transparency=0.7))
        elif name in ("RotorHub", "TailRotorHub"):
            # Drehpunkt (Motor6D im Spiel) als Marker, die Nabe selbst als Maßstab
            out.append(marker("Point_Rotor" if name == "RotorHub" else "Point_TailRotor", (x, y, z), 0.2))
            out.append(dict(part, name="Ref_" + name, color=part["color"], transparency=part["transparency"]))
        else:
            out.append(dict(part, name="Ref_" + name, color=part["color"], transparency=part["transparency"]))
    # Boden als dünne Platte (Unterkante der Räder = Boden)
    chassis = next(p for p in parts if p["name"] == "Chassis")
    sx, sz = chassis["size"][0] + 3, chassis["size"][2] + 3
    out.append({"name": "Ref_Ground", "shape": "Block", "cframe": [0, -0.025, 0, *IDENTITY], "size": (sx, 0.05, sz),
                "color": (70, 72, 76), "material": "SmoothPlastic", "transparency": 0.0})
    return out


def marker(name, position, size):
    return {"name": name, "shape": "Block", "cframe": [*position, *IDENTITY], "size": (size, size, size), "color": MARKER,
            "material": "SmoothPlastic", "transparency": 0.0}


def item_parts(item):
    item_id, shape, size, grip, _ = item
    parts = [{"name": "Ref_" + item_id, "shape": shape, "cframe": [0, size[1] / 2, 0, *IDENTITY], "size": size,
              "color": REF, "material": "SmoothPlastic", "transparency": 1 - REF_ALPHA}]
    if grip:
        parts.append(marker("Point_Grip", grip, 0.05))
    return parts


# ---------- Blender: OBJ + MTL ----------

def write_obj(folder, name, parts, header):
    os.makedirs(folder, exist_ok=True)
    materials, lines, offset = {}, ["# " + line for line in header] + ["mtllib %s.mtl" % name], 1
    for part in parts:
        local, faces = shape_faces(part["shape"], part["size"])
        verts = [transform(part["cframe"], v) for v in local]
        center = part["cframe"][0:3]
        alpha = round(1 - part["transparency"], 2)
        key = "c_%02x%02x%02x_%d" % (*part["color"], round(alpha * 100))
        materials[key] = (part["color"], alpha)
        lines.append("o " + part["name"])
        lines += ["v %.6f %.6f %.6f" % v for v in verts]
        lines.append("usemtl " + key)
        for face in faces:
            lines.append("f " + " ".join(str(offset + i) for i in outward(face, verts, center)))
        offset += len(verts)
    with open(os.path.join(folder, name + ".obj"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    mtl = []
    for key, (color, alpha) in sorted(materials.items()):
        mtl += ["newmtl " + key, "Kd %.4f %.4f %.4f" % tuple(c / 255 for c in color), "d %.2f" % alpha, ""]
    with open(os.path.join(folder, name + ".mtl"), "w", encoding="utf-8") as f:
        f.write("\n".join(mtl))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--luau", default=os.environ.get("LUAU", "luau"), help="Luau-Interpreter")
    args = parser.parse_args()
    for vehicle, parts in sorted(collect_vehicles(args.luau).items()):
        out = template_parts(vehicle, parts)
        rotors = any(p["name"] == "Point_Rotor" for p in out)
        write_obj(OUT_VEHICLES, vehicle, out, [
            "Vorlage Fahrzeug %s - 1 Einheit = 1 Stud, oben +Y, vorne -Z (Roblox), Boden y = 0." % vehicle,
            "Ref_Chassis = Rumpf im Spiel (kollidiert, wird getroffen). "
            + ("Point_Rotor / Point_TailRotor = Drehpunkte der Rotoren (um +Y bzw. +X), Seat_* = Sitzflächen."
               if rotors else "Wheel_* = Räder an der Achse, Seat_* = Sitzflächen."),
            "Ref_* nur als Maßstab: vor dem Export löschen. Spezifikation: docs/3d-richtlinien.md"])
        print("%-8s %2d Teile -> art/templates/Vehicles/%s.obj/.mtl" % (vehicle, len(out), vehicle))
    for item in ITEMS:
        write_obj(OUT_ITEMS, item[0], item_parts(item), [
            "Vorlage %s (%s) - 1 Einheit = 1 Stud, oben +Y, vorne -Z (Roblox), Boden y = 0." % (item[0], item[4]),
            "Ref_%s = Zielgröße (vor dem Export löschen), Point_Grip = rechte Hand. Spezifikation: docs/3d-richtlinien.md"
            % item[0]])
    print("%d Items/Gadgets/Behälter -> art/templates/Items/" % len(ITEMS))


if __name__ == "__main__":
    main()

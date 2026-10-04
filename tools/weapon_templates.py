#!/usr/bin/env python3
"""Vorlagen für die Waffenmodelle: art/templates/Weapons/<Waffe>.obj (+ .mtl) für Blender und <Waffe>.rbxmx für Studio.

Inhalt: die Quader-Waffe aus dem Spiel in Originalgröße (1 Einheit = 1 Stud), Teilnamen schon nach der
Spezifikation (docs/waffen-modelle.md) und alle Marker (Point_..., Pivot_...) an der richtigen Stelle.
- Blender: Datei > Import > Wavefront (.obj) – die Vorlage ist der Maßstab, um den du die echte Waffe baust.
- Studio: Datei > Insert from File... (.rbxmx) – zum Ausprobieren: in ReplicatedStorage > Assets > Weapons
  gelegt, verhält sie sich genau wie ein fertiges Modell.

Neu erzeugen (z.B. nach Änderungen an src/shared/GunModels.lua):
    python3 tools/weapon_templates.py [--luau PFAD]
Gebraucht wird der Luau-Interpreter wie für die Tests.
"""
import argparse
import math
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
import run  # noqa: E402  (tests/run.py: Bündeln mit der Roblox-Nachbildung)
import rbxmx  # noqa: E402  (tests/lib/rbxmx.py)

OUT = os.path.join(ROOT, "art", "templates", "Weapons")
SCRIPT = os.path.join(ROOT, "tools", "weapon_templates.luau")
MARKER_SIZE = {"Point": 0.04, "Pivot": 0.06}
MARKER_COLOR = {"Point": (255, 0, 255), "Pivot": (0, 220, 255)}
MATERIAL_TOKENS = {name: number for number, name in rbxmx.MATERIALS.items()}


# ---------- Daten aus dem Spiel ----------

def collect(luau):
    """{ Waffe: { "parts": [...], "points": [(Name, (x, y, z))] } } aus tools/weapon_templates.luau"""
    bundle, _ = run.build(SCRIPT, run.project_modules(), "immediate", "{}")
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "weapon_templates.luau")
        with open(path, "w", encoding="utf-8") as f:
            f.write(bundle)
        result = subprocess.run([luau, path], capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("Luau-Fehler:\n" + result.stdout + result.stderr)
    weapons = {}
    for line in result.stdout.splitlines():
        fields = line.split("\t")
        if fields[0] == "PART":
            numbers = [float(v) for v in fields[4:22]]
            weapons.setdefault(fields[1], {"parts": [], "points": []})["parts"].append({
                "name": fields[2], "shape": fields[3], "cframe": numbers[0:12], "size": numbers[12:15],
                "color": tuple(round(v) for v in numbers[15:18]), "material": fields[22],
                "transparency": float(fields[23]),
            })
        elif fields[0] == "POINT":
            weapons.setdefault(fields[1], {"parts": [], "points": []})["points"].append(
                (fields[2], tuple(float(v) for v in fields[3:6])))
    return weapons


# ---------- Geometrie ----------

def transform(c, v):
    x, y, z = v
    return (c[3] * x + c[4] * y + c[5] * z + c[0],
            c[6] * x + c[7] * y + c[8] * z + c[1],
            c[9] * x + c[10] * y + c[11] * z + c[2])


def shape_faces(shape, size):
    """(Eckpunkte, Flächen) im Teilraum. Zylinder liegen wie in Roblox entlang X."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    if shape == "Cylinder":
        r, n = min(hy, hz), 16
        ring = [(math.cos(2 * math.pi * k / n) * r, math.sin(2 * math.pi * k / n) * r) for k in range(n)]
        verts = [(-hx, a, b) for a, b in ring] + [(hx, a, b) for a, b in ring]
        faces = [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
        faces += [tuple(range(n)), tuple(range(n, 2 * n))]
        return verts, faces
    if shape == "Ball":
        r, lat, lon = min(hx, hy, hz), 6, 12
        verts = [(0, r, 0)]
        for i in range(1, lat):
            t = math.pi * i / lat
            for k in range(lon):
                p = 2 * math.pi * k / lon
                verts.append((r * math.sin(t) * math.cos(p), r * math.cos(t), r * math.sin(t) * math.sin(p)))
        verts.append((0, -r, 0))
        bottom = len(verts) - 1
        faces = [(0, 1 + k, 1 + (k + 1) % lon) for k in range(lon)]
        for i in range(lat - 2):
            row, nxt = 1 + i * lon, 1 + (i + 1) * lon
            faces += [(row + k, nxt + k, nxt + (k + 1) % lon, row + (k + 1) % lon) for k in range(lon)]
        last = 1 + (lat - 2) * lon
        faces += [(last + k, bottom, last + (k + 1) % lon) for k in range(lon)]
        return verts, faces
    verts = [(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return verts, faces


def outward(face, verts, center):
    """Fläche so herum, dass die Normale nach außen zeigt (Blender zeigt sonst dunkle Flächen)."""
    pts = [verts[i] for i in face]
    nx = ny = nz = 0.0
    for a, b in zip(pts, pts[1:] + pts[:1]):  # Newell
        nx += (a[1] - b[1]) * (a[2] + b[2])
        ny += (a[2] - b[2]) * (a[0] + b[0])
        nz += (a[0] - b[0]) * (a[1] + b[1])
    mid = [sum(p[i] for p in pts) / len(pts) for i in range(3)]
    if nx * (mid[0] - center[0]) + ny * (mid[1] - center[1]) + nz * (mid[2] - center[2]) < 0:
        return tuple(reversed(face))
    return face


def marker_parts(points):
    parts = []
    for name, position in points:
        kind = name.split("_")[0]
        size = MARKER_SIZE[kind]
        parts.append({"name": name, "shape": "Block", "cframe": [*position, 1, 0, 0, 0, 1, 0, 0, 0, 1],
                      "size": (size, size, size), "color": MARKER_COLOR[kind], "material": "SmoothPlastic",
                      "transparency": 0.0})
    return parts


# ---------- Blender: OBJ + MTL ----------

def write_obj(weapon, parts):
    materials, lines, offset = {}, ["# Vorlage %s – 1 Einheit = 1 Stud, Lauf zeigt nach -Z (Roblox)." % weapon,
                                    "# Spezifikation: docs/waffen-modelle.md", "mtllib %s.mtl" % weapon], 1
    for part in parts:
        local, faces = shape_faces(part["shape"], part["size"])
        verts = [transform(part["cframe"], v) for v in local]
        center = part["cframe"][0:3]
        key = "c_%02x%02x%02x" % part["color"] + ("_glass" if part["material"] == "Glass" else "")
        materials[key] = (part["color"], 0.25 if part["material"] == "Glass" else 1.0)
        lines.append("o " + part["name"])
        lines += ["v %.6f %.6f %.6f" % v for v in verts]
        lines.append("usemtl " + key)
        for face in faces:
            lines.append("f " + " ".join(str(offset + i) for i in outward(face, verts, center)))
        offset += len(verts)
    with open(os.path.join(OUT, weapon + ".obj"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    mtl = []
    for key, (color, alpha) in sorted(materials.items()):
        mtl += ["newmtl " + key, "Kd %.4f %.4f %.4f" % tuple(c / 255 for c in color), "d %.2f" % alpha, ""]
    with open(os.path.join(OUT, weapon + ".mtl"), "w", encoding="utf-8") as f:
        f.write("\n".join(mtl))


# ---------- Studio: RBXMX ----------

def _xml_text(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def write_rbxmx(weapon, parts):
    counter = [0]

    def ref():
        counter[0] += 1
        return "RBX%08X" % (0x7E3A0000 + counter[0])

    keys = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")
    shapes = {"Ball": 0, "Block": 1, "Cylinder": 2}
    items = []
    for part in parts:
        r, g, b = part["color"]
        props = [
            '<bool name="Anchored">true</bool>',
            '<CoordinateFrame name="CFrame">%s</CoordinateFrame>' % "".join(
                "<%s>%.6f</%s>" % (k, v, k) for k, v in zip(keys, part["cframe"])),
            '<bool name="CanCollide">false</bool>',
            '<Color3uint8 name="Color3uint8">%d</Color3uint8>' % ((0xFF << 24) | (r << 16) | (g << 8) | b),
            '<token name="Material">%d</token>' % MATERIAL_TOKENS.get(part["material"], 256),
            '<string name="Name">%s</string>' % _xml_text(part["name"]),
            '<float name="Transparency">%.3f</float>' % part["transparency"],
            '<Vector3 name="size"><X>%.6f</X><Y>%.6f</Y><Z>%.6f</Z></Vector3>' % tuple(part["size"]),
            '<token name="shape">%d</token>' % shapes[part["shape"]],
        ]
        items.append('\t\t<Item class="Part" referent="%s"><Properties>%s</Properties></Item>' % (ref(), "".join(props)))
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
           '\t<Item class="Model" referent="%s"><Properties><string name="Name">%s</string></Properties>\n%s\n\t</Item>\n'
           '</roblox>\n') % (ref(), weapon, "\n".join(items))
    with open(os.path.join(OUT, weapon + ".rbxmx"), "w", encoding="utf-8") as f:
        f.write(xml)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--luau", default=os.environ.get("LUAU", "luau"), help="Luau-Interpreter")
    args = parser.parse_args()
    weapons = collect(args.luau)
    os.makedirs(OUT, exist_ok=True)
    for weapon, data in sorted(weapons.items()):
        parts = data["parts"] + marker_parts(data["points"])
        write_obj(weapon, data["parts"] + marker_parts(data["points"]))
        write_rbxmx(weapon, parts)
        print("%-9s %2d Teile, %2d Marker -> art/templates/Weapons/%s.obj/.mtl/.rbxmx"
              % (weapon, len(data["parts"]), len(data["points"]), weapon))


if __name__ == "__main__":
    main()

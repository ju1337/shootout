#!/usr/bin/env python3
"""Bereitet das Chiappa-Rhino-Modell für den Studio-Import vor: art/sources/rhino.glb -> art/sources/Revolver.glb.

Die Datei ist fertig nach docs/waffen-modelle.md: Teile benannt (Skin_Frame = Rahmen mit Laufmantel, Skin_Cylinder =
Trommel, Cylinder_Crane = Kran und Ausstoßerstange, beide Gruppe Cylinder; Hammer, Grip, Metal, Neon_FrontDot), die zwei
losen Patronen neben der Waffe entfernt, ein Schnelllader (Loader, nur beim Nachladen sichtbar) dazugebaut, Größe in
Studs (1,47 lang wie der alte Revolver), Lauf nach -Z, Marker (Point_*, Pivot_Cylinder) als kleine Würfel.
Der Rhino schießt aus der unteren Kammer: die Mündung sitzt tief, die Visierlinie liegt auf der flachen Oberseite.
Visierlinie: Oberkante der Kimmen-Ohren = Oberkante des Korns (beide gleich hoch); beim Zielen sitzt das Korn so in der
Kimmenkerbe in der Bildmitte.

Mit --boxes zusätzlich ein Quader-Nachbau als assets/Weapons/Revolver.rbxmx (je Teil ein Quader so groß wie das Mesh,
Marker gleich), zum Prüfen ohne Studio. Achtung: überschreibt eine echte Studio-Kopie.

Dann in Studio: Import 3D > Revolver.glb (Teile NICHT zusammenführen, Einheit Stud), Modell nach
ReplicatedStorage > Assets > Weapons ziehen, "Revolver" nennen.
    python3 tools/rhino_glb.py
"""
import math, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import glb_read as G  # noqa: E402
import weapon_templates as wt  # noqa: E402
from mp7_glb import cube, write  # noqa: E402

SRC = os.path.join(ROOT, "art", "sources", "rhino.glb")
OUT = os.path.join(ROOT, "art", "sources", "Revolver.glb")
X_FRONT_END, X_BACK = -1.889, 0.911  # Mündung bis Griffende (GLB-Einheiten, Lauf zeigt nach -x)
SCALE = 1.47 / (X_BACK - X_FRONT_END)  # -> 1,47 Studs wie der alte Revolver
Y_SIGHT = 0.475  # Oberkante der Kimmen-Ohren = Oberkante des Korns (GLB-Einheiten)
X_REAR, X_FRONT = 0.205, -1.70  # Kimme, Korn
X_DRUM, Y_DRUM, R_DRUM = -0.10, 0.194, 0.17  # Trommel: Mitte und Radius
X_DRUM_BACK = 0.114  # Hinterkante der Trommel
Y_BORE = 0.082  # Laufachse (untere Kammer)

# (GLB-Gruppe, Material) -> Teilname im Spiel; nicht genannte fallen weg (lose Patronen "Cylinder_0", "Cylinder.002_1")
PART_OF = {
    ("Cube_2", "material_1"): "Skin_Frame", ("Cube_2", "material_2"): "Metal", ("Cube_2", "material_3"): "Grip",
    ("Cylinder.004_5", "material_1"): "Skin_Cylinder",  # Kran und Ausstoßerstange werden unten abgetrennt
    ("Cube.001_6", "material_2"): "Hammer",
}
# Farben (sRGB 0-255); Skin_ bekommen die Farbe vom Skin (ohne Skin dunkelt GunModels sie ab)
SRGB = {"Skin_Frame": (36, 36, 40), "Skin_Cylinder": (40, 40, 44), "Cylinder_Crane": (48, 48, 52), "Grip": (24, 24, 26),
        "Metal": (26, 26, 28), "Hammer": (30, 30, 32), "Loader": (30, 30, 32), "Neon_FrontDot": (255, 190, 60)}
# alles matt (SmoothPlastic, auch Metallteile): Metal spiegelt in der Sonne den Himmel, die Waffe wirkt dann fast weiß

# Marker (GLB-Einheiten: x = nach hinten, y = oben, z = links)
POINTS = [
    ("Point_Grip", (0.64, -0.30, 0)),
    ("Point_SightRear", (X_REAR, Y_SIGHT, 0)),
    ("Point_SightFront", (X_FRONT, Y_SIGHT, 0)),
    ("Point_Muzzle", (X_FRONT_END, Y_BORE, 0)),
    ("Point_Eject", (X_DRUM, Y_DRUM + R_DRUM, 0)),
    ("Point_LeftHand", (0.60, -0.49, 0.23)),
    ("Pivot_Cylinder", (X_DRUM, Y_DRUM, 0)),
]
# Schnelllader in Ruhelage: hinter der ausgeschwenkten Trommel (WeaponAnimations: Trommel 0,28 nach links, 0,1 runter)
LOADER = (X_DRUM_BACK + 0.06, Y_DRUM - 0.1 / SCALE, 0.28 / SCALE)


def rb(p, scale=SCALE):  # GLB-Welt -> Roblox (Lauf nach -Z), Studs
    x, y, z = p
    return (-z * scale, y * scale, x * scale)


def linear(c):  # write() rechnet linear -> sRGB um
    return tuple((v / 255) ** 2.2 for v in c)


def tri_arrays(j, b):
    out = {}
    def walk(n, m, top):
        nd = j["nodes"][n]; m = G.mmul(m, nd.get("matrix", G.ident()))
        if "mesh" in nd:
            for prim in j["meshes"][nd["mesh"]]["primitives"]:
                name = PART_OF.get((top, j["materials"][prim["material"]]["name"]))
                if not name:
                    continue
                pos = G.positions(j, b, prim["attributes"]["POSITION"])
                nor = G.positions(j, b, prim["attributes"]["NORMAL"])
                world = [tuple(m[r] * v[0] + m[4 + r] * v[1] + m[8 + r] * v[2] + m[12 + r] for r in range(3)) for v in pos]
                if name == "Skin_Cylinder" and min(v[0] for v in world) < -0.32:
                    name = "Cylinder_Crane"  # Kran vor der Trommel und Ausstoßerstange schwenken mit aus
                P, N = out.setdefault(name, ([], []))
                for i in G.indices(j, b, prim["indices"]):
                    n3 = nor[i]
                    q = tuple(m[r] * n3[0] + m[4 + r] * n3[1] + m[8 + r] * n3[2] for r in range(3))
                    ln = math.sqrt(sum(c * c for c in q)) or 1
                    P.append(rb(world[i])); N.append(rb(tuple(c / ln for c in q), 1))
        for c in nd.get("children", []):
            walk(c, m, top)
    root = G.ident()
    for n in (0, 1, 2):
        root = G.mmul(root, j["nodes"][n].get("matrix", G.ident()))
    for c in j["nodes"][2]["children"]:
        walk(c, root, j["nodes"][c]["name"])
    return out


def prism(center, radius, length, sides):
    """Prisma entlang x (GLB), als Dreiecke in Roblox-Koordinaten."""
    cx, cy, cz = center
    ring = [(math.cos(2 * math.pi * (k + 0.5) / sides), math.sin(2 * math.pi * (k + 0.5) / sides)) for k in range(sides)]
    P, N = [], []
    def tri(a, b, c, n):
        for v in (a, b, c):
            P.append(rb(v)); N.append(rb(n, 1))
    for k in range(sides):
        (ay, az), (by, bz) = ring[k], ring[(k + 1) % sides]
        a0, b0 = (cx - length / 2, cy + ay * radius, cz + az * radius), (cx - length / 2, cy + by * radius, cz + bz * radius)
        a1, b1 = (cx + length / 2, cy + ay * radius, cz + az * radius), (cx + length / 2, cy + by * radius, cz + bz * radius)
        mid = math.pi * 2 * (k + 1) / sides
        n = (0, math.cos(mid), math.sin(mid))
        tri(a0, b0, b1, n); tri(a0, b1, a1, n)
        tri((cx - length / 2, cy, cz), b0, a0, (-1, 0, 0)); tri((cx + length / 2, cy, cz), a1, b1, (1, 0, 0))
    return P, N


def build():
    j, b = G.load(SRC)
    parts = {k: (P, N, linear(SRGB[k])) for k, (P, N) in tri_arrays(j, b).items()}
    # Leuchtpunkt im Korn, Oberkante auf der Visierlinie (wie beim alten Revolver)
    dot = 0.014
    p, n = cube(rb((X_FRONT, Y_SIGHT - dot / 2 / SCALE, 0)), dot, None)
    parts["Neon_FrontDot"] = (p, n, linear(SRGB["Neon_FrontDot"]))
    # Schnelllader: Scheibe in Trommelgröße plus Drehknopf hinten
    lp, ln = prism(LOADER, R_DRUM * 0.95, 0.10, 12)
    kp, kn = prism((LOADER[0] + 0.09, LOADER[1], LOADER[2]), 0.06, 0.08, 10)
    parts["Loader"] = (lp + kp, ln + kn, linear(SRGB["Loader"]))
    for name, pt in POINTS:
        p, n = cube(rb(pt), 0.03, None)
        parts[name] = (p, n, (1.0, 0.0, 1.0))
    return parts


def write_boxes(parts):
    """Testkopie: je Teil ein Quader über die Ausdehnung des Meshes, Marker wie im GLB."""
    material = {"Neon_FrontDot": "Neon"}
    boxes = []
    for name, (P, _, _) in parts.items():
        if name.startswith(("Point", "Pivot")):
            continue
        lo = [min(v[i] for v in P) for i in range(3)]; hi = [max(v[i] for v in P) for i in range(3)]
        boxes.append({"name": name, "shape": "Block", "cframe": [*((a + c) / 2 for a, c in zip(lo, hi)), 1, 0, 0, 0, 1, 0, 0, 0, 1],
                      "size": tuple(max(c - a, 0.01) for a, c in zip(lo, hi)), "color": SRGB[name],
                      "material": material.get(name, "SmoothPlastic"), "transparency": 0.0})
    boxes += wt.marker_parts([(name, rb(pt)) for name, pt in POINTS])
    wt.write_rbxmx("Revolver", boxes, os.path.join(ROOT, "assets", "Weapons"))


def main():
    parts = build()
    write(parts, OUT, {"license": "CC-BY-4.0", "author": "D.U. (https://sketchfab.com/D.U.)"})
    if "--boxes" in sys.argv:
        write_boxes(parts)
    total = 0
    for k, (P, _, _) in parts.items():
        if not k.startswith(("Point", "Pivot")):
            total += len(P) // 3
            print("  %-16s %5d Dreiecke" % (k, len(P) // 3))
    zs = [v[2] for k, (P, _, _) in parts.items() if not k.startswith(("Point", "Pivot", "Loader")) for v in P]
    print("Revolver.glb: %d Teile, %d Dreiecke, Länge %.2f Studs, Visierlinie %.3f über dem Griff -> art/sources/Revolver.glb"
          % (len(parts), total, max(zs) - min(zs), (Y_SIGHT - POINTS[0][1][1]) * SCALE))


if __name__ == "__main__":
    main()

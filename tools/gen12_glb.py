#!/usr/bin/env python3
"""Bereitet das Gen-12-Modell (Schrotflinte mit Kastenmagazin) für den Studio-Import vor:
art/sources/gen12.glb -> art/sources/Shotgun.glb.

Die Datei ist fertig nach docs/waffen-modelle.md: Teile benannt (Skin_Receiver = Oberteil, Skin_Lower = Unterteil,
Skin_Handguard, Skin_Stock, Grip, Magazine = eingesetztes Magazin, Bolt = Verschluss samt Spannhebel rechts, Barrel,
Metal, Neon_FrontDot), das lose zweite Magazin, die lose Patrone und der Schriftzug-Aufkleber entfernt, Größe in Studs
(3,95 lang wie die alte Schrotflinte), Lauf nach -Z, Marker (Point_*) als kleine Würfel.
Das Original hat nur eine Picatinny-Schiene und kein Visier: hinten und vorn auf der Schiene sitzen hochgeklappte
Notvisiere (Sights, Quader). Visierlinie = Oberkante der Kimmen-Ohren und Spitze des Korns, beide auf Y_SIGHT.

Mit --boxes zusätzlich ein Quader-Nachbau als assets/Weapons/Shotgun.rbxmx (je Teil ein Quader so groß wie das Mesh,
Marker gleich), zum Prüfen ohne Studio. Achtung: überschreibt die echte Studio-Kopie (Kopie von models/Weapons/Shotgun.rbxmx).

Dann in Studio: Import 3D > Shotgun.glb (Teile NICHT zusammenführen, Einheit Stud), Modell nach
ReplicatedStorage > Assets > Weapons ziehen, "Shotgun" nennen.
    python3 tools/gen12_glb.py
"""
import math, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import glb_read as G  # noqa: E402
import weapon_templates as wt  # noqa: E402
from mp7_glb import cube, write  # noqa: E402

SRC = os.path.join(ROOT, "art", "sources", "gen12.glb")
OUT = os.path.join(ROOT, "art", "sources", "Shotgun.glb")
X_BACK, X_FRONT_END = -4.714, 6.236  # Schaftkappe bis Mündung (GLB-Einheiten)
SCALE = 3.95 / (X_FRONT_END - X_BACK)  # -> 3,95 Studs wie die alte Schrotflinte
X_HANDGUARD, X_BARREL = 0.62, 4.6  # Oberteil | Handschutz | freier Lauf (Dreiecke nach ihrer Mitte)
Y_BORE, R_BARREL = 0.35, 0.13  # Laufachse und -radius: was so dünn ist, ist auch im Handschutz Lauf
Y_RAIL = 0.737  # Oberkante der Schiene
Y_SIGHT = 1.05  # Visierlinie: Oberkante der Kimmen-Ohren = Spitze des Korns (gut 1 Zoll über der Schiene)
X_REAR, X_FRONT = -1.46, 5.70  # Kimme (hinten auf der Schiene), Korn (vorn auf der Schiene)

# (GLB-Gruppe, Material) -> Teilname im Spiel; nicht genannte fallen weg (loses Magazin, Patrone, Schriftzug)
PART_OF = {
    ("gen-12_5", "material_2"): "Skin_Receiver", ("gen-12_5", "material_5"): "Skin_Lower",
    ("gen-12_5", "material_3"): "Grip",
    ("gen12 stock_10", "material_3"): "Skin_Stock", ("gen12 stock_10", "material_2"): "Metal",
    ("1276 gen12 mag empty 5rnd _1", "material_2"): "Magazine", ("1276 gen12 mag empty 5rnd _1", "material_3"): "Magazine",
    ("gen12 bolt_4", "material_4"): "Bolt",
    ("gen12 muzzle_3", "material_2"): "Barrel",
    ("gen12 mag release_6", "material_2"): "Metal", ("gen12 trigga_7", "material_2"): "Metal",
    ("gen12 mode_8", "material_2"): "Metal", ("gen12 bollt release_9", "material_2"): "Metal",
}
# Farben (sRGB 0-255); Skin_ bekommen die Farbe vom Skin (ohne Skin dunkelt GunModels sie ab)
SRGB = {"Skin_Receiver": (36, 36, 40), "Skin_Lower": (34, 34, 38), "Skin_Handguard": (32, 32, 35),
        "Skin_Stock": (28, 28, 30), "Grip": (26, 26, 28), "Magazine": (30, 30, 32), "Bolt": (48, 48, 52),
        "Barrel": (40, 40, 43), "Metal": (26, 26, 28), "Sights": (24, 24, 26), "Neon_FrontDot": (255, 190, 60)}
# alles matt (SmoothPlastic, auch Metallteile): Metal spiegelt in der Sonne den Himmel, die Waffe wirkt dann fast weiß

# Marker (GLB-Einheiten: x = nach vorn, y = oben, z = rechts)
POINTS = [
    ("Point_Grip", (-1.50, -0.55, 0)),
    ("Point_SightRear", (X_REAR, Y_SIGHT, 0)),
    ("Point_SightFront", (X_FRONT, Y_SIGHT, 0)),
    ("Point_Muzzle", (X_FRONT_END, 0.35, 0)),
    ("Point_Eject", (-0.25, 0.33, 0.26)),
    ("Point_LeftHand", (2.2, -0.02, -0.03)),
    ("Point_LeftHandTP", (1.6, -0.02, -0.03)),
    ("Point_Stock", (X_BACK, 0.1, 0)),
]
# Notvisiere als Quader (x0, x1, y0, y1, z0, z1): Kimme mit zwei Ohren und Kerbe, Korn mit Schutzflügeln
SIGHT_BOXES = [
    (-1.62, -1.30, Y_RAIL, 0.83, -0.12, 0.12),     # Kimme: Fuß auf der Schiene
    (-1.50, -1.42, 0.83, 0.93, -0.11, 0.11),       # Kimme: Steg unter der Kerbe
    (-1.50, -1.42, 0.93, Y_SIGHT, 0.03, 0.11),     # Kimme: rechtes Ohr
    (-1.50, -1.42, 0.93, Y_SIGHT, -0.11, -0.03),   # Kimme: linkes Ohr
    (5.55, 5.85, Y_RAIL, 0.83, -0.12, 0.12),       # Korn: Fuß
    (5.66, 5.74, 0.83, 1.10, 0.08, 0.12),          # Korn: rechter Schutzflügel
    (5.66, 5.74, 0.83, 1.10, -0.12, -0.08),        # Korn: linker Schutzflügel
    (5.68, 5.72, 0.83, Y_SIGHT, -0.02, 0.02),      # Korn
]


def rb(p):  # GLB-Welt -> Roblox (Lauf nach -Z), Studs
    x, y, z = p
    return (z * SCALE, y * SCALE, -x * SCALE)


def linear(c):  # write() rechnet linear -> sRGB um
    return tuple((v / 255) ** 2.2 for v in c)


def box(x0, x1, y0, y1, z0, z1):
    """Quader in GLB-Einheiten als Dreiecke (Roblox-Raum)."""
    P, N = [], []
    c = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    faces = [((0, 1, 3, 2), (-1, 0, 0)), ((4, 6, 7, 5), (1, 0, 0)), ((0, 4, 5, 1), (0, -1, 0)),
             ((2, 3, 7, 6), (0, 1, 0)), ((0, 2, 6, 4), (0, 0, -1)), ((1, 5, 7, 3), (0, 0, 1))]
    for q, n in faces:
        for k in (0, 1, 2, 0, 2, 3):
            P.append(rb(c[q[k]])); N.append(rb(n))
    return P, N


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
                idx = G.indices(j, b, prim["indices"])
                for t in range(0, len(idx), 3):
                    ws, ns = [], []
                    for i in idx[t:t + 3]:
                        v, n3 = pos[i], nor[i]
                        ws.append(tuple(m[r] * v[0] + m[4 + r] * v[1] + m[8 + r] * v[2] + m[12 + r] for r in range(3)))
                        q = tuple(m[r] * n3[0] + m[4 + r] * n3[1] + m[8 + r] * n3[2] for r in range(3))
                        ln = math.sqrt(sum(c * c for c in q)) or 1
                        ns.append(tuple(c / ln for c in q))
                    part = name
                    if name == "Skin_Receiver":  # ein Objekt im Original: Oberteil, Handschutz und Lauf
                        x = sum(w[0] for w in ws) / 3
                        thin = all(math.hypot(w[1] - Y_BORE, w[2]) < R_BARREL for w in ws)
                        part = ("Barrel" if x > X_BARREL or thin and x > X_HANDGUARD
                                else "Skin_Handguard" if x > X_HANDGUARD else name)
                    P, N = out.setdefault(part, ([], []))
                    P.extend(rb(w) for w in ws); N.extend(rb(n3) for n3 in ns)
        for c in nd.get("children", []):
            walk(c, m, top)
    root = G.ident()
    for n in (0, 1, 2):
        root = G.mmul(root, j["nodes"][n].get("matrix", G.ident()))
    for c in j["nodes"][2]["children"]:
        walk(c, root, j["nodes"][c]["name"])
    return out


def build():
    j, b = G.load(SRC)
    parts = {k: (P, N, linear(SRGB[k])) for k, (P, N) in tri_arrays(j, b).items()}
    P, N = [], []
    for bx in SIGHT_BOXES:
        p, n = box(*bx)
        P += p; N += n
    parts["Sights"] = (P, N, linear(SRGB["Sights"]))
    # Leuchtpunkt auf der Kornspitze (Mitte auf der Visierlinie, wie bei der MP7)
    p, n = cube(rb((X_FRONT, Y_SIGHT, 0)), 0.02, None)
    parts["Neon_FrontDot"] = (p, n, linear(SRGB["Neon_FrontDot"]))
    for name, pt in POINTS:
        p, n = cube(rb(pt), 0.04, None)
        parts[name] = (p, n, (1.0, 0.0, 1.0))
    return parts


def write_boxes(parts):
    """Testkopie: je Teil ein Quader über die Ausdehnung des Meshes, Marker wie im GLB (Visiere einzeln)."""
    material = {"Neon_FrontDot": "Neon"}
    boxes = []
    def add(name, P, color):
        lo = [min(v[i] for v in P) for i in range(3)]; hi = [max(v[i] for v in P) for i in range(3)]
        boxes.append({"name": name, "shape": "Block", "cframe": [*((a + c) / 2 for a, c in zip(lo, hi)), 1, 0, 0, 0, 1, 0, 0, 0, 1],
                      "size": tuple(max(c - a, 0.01) for a, c in zip(lo, hi)), "color": color,
                      "material": material.get(name, "SmoothPlastic"), "transparency": 0.0})
    for name, (P, _, _) in parts.items():
        if name.startswith(("Point", "Pivot")) or name == "Sights":
            continue
        add(name, P, SRGB[name])
    for bx in SIGHT_BOXES:
        add("Sights", box(*bx)[0], SRGB["Sights"])
    boxes += wt.marker_parts([(name, rb(pt)) for name, pt in POINTS])
    wt.write_rbxmx("Shotgun", boxes, os.path.join(ROOT, "assets", "Weapons"))


def main():
    parts = build()
    write(parts, OUT, {"license": "CC-BY-4.0", "author": "D.U. (https://sketchfab.com/D.U.)",
                       "source": "https://sketchfab.com/3d-models/low-poly-gen-12-5a8e85a2375948498d76d379e915f3bf"})
    if "--boxes" in sys.argv:
        write_boxes(parts)
    total = 0
    for k, (P, _, _) in parts.items():
        if not k.startswith(("Point", "Pivot")):
            total += len(P) // 3
            print("  %-16s %5d Dreiecke" % (k, len(P) // 3))
    zs = [v[2] for k, (P, _, _) in parts.items() if not k.startswith(("Point", "Pivot")) for v in P]
    print("Shotgun.glb: %d Teile, %d Dreiecke, Länge %.2f Studs, Visierlinie %.3f über dem Griff -> art/sources/Shotgun.glb"
          % (len(parts), total, max(zs) - min(zs), (Y_SIGHT - POINTS[0][1][1]) * SCALE))


if __name__ == "__main__":
    main()

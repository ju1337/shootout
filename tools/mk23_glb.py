#!/usr/bin/env python3
"""Bereitet das HK-Mark-23-Modell für den Studio-Import vor: art/sources/mk23.glb -> art/sources/Pistol.glb.

Die Datei ist fertig nach docs/waffen-modelle.md: Teile benannt (Skin_Slide, Neon_Slide_Dots, Magazine, Frame, Metal,
Steel, Barrel), Schalldämpfer, Laser-Modul (LAM), lose Patronen und das zweite Magazin entfernt (Schalldämpfer und Laser
baut das Spiel als Aufsatz an), Größe in Studs (1,05 lang wie die alte Pistole), Lauf nach -Z, Marker (Point_*) als
kleine Würfel. Die Visierlinie läuft über die Oberkante der Kimmen-Ohren und die Spitze des Korns (beide gleich hoch);
beim Zielen sitzt das Korn so in der Kimmenlücke in der Bildmitte.

Dazu eine Testkopie assets/Weapons/Pistol.rbxmx (je Teil ein Quader so groß wie das Mesh, Marker gleich): Mit ihr
prüft CI Marker, Visierlinie und Haltung, bis die echte Studio-Kopie da ist.

Dann in Studio: Import 3D > Pistol.glb (Teile NICHT zusammenführen, Einheit Stud), Modell nach
ReplicatedStorage > Assets > Weapons ziehen, "Pistol" nennen.
    python3 tools/mk23_glb.py
"""
import math, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import glb_read as G  # noqa: E402
import weapon_templates as wt  # noqa: E402
from mp7_glb import cube, write  # noqa: E402

SRC = os.path.join(ROOT, "art", "sources", "mk23.glb")
OUT = os.path.join(ROOT, "art", "sources", "Pistol.glb")
X_BACK, X_FRONT_END = -1.929, 0.530  # Griffrücken bis Laufende (GLB-Einheiten)
SCALE = 1.05 / (X_FRONT_END - X_BACK)  # -> 1,05 Studs wie die alte Pistole
Y_SIGHT = 0.843  # Oberkante der Kimmen-Ohren = Spitze des Korns (GLB-Einheiten)
X_REAR, X_FRONT = -1.70, 0.273  # Kimme, Korn

# (GLB-Gruppe, Material) -> Teilname im Spiel; nicht genannte fallen weg (Patronen, volles Magazin, Schalldämpfer, LAM)
PART_OF = {
    ("mk23 slide_10", "h-190"): "Skin_Slide", ("mk23 slide_10", "polymer"): "Skin_Slide",
    ("mk23 slide_10", "tritium"): "Neon_Slide_Dots",
    ("mk23 12rnd empty _2", "h-190"): "Magazine", ("mk23 12rnd empty _2", "polymer"): "Magazine",
    ("mk23 frame_5", "polymer"): "Frame", ("mk23 frame_5", "stell"): "Steel", ("mk23 frame_5", "h-190"): "Metal",
    ("mk23 barrel_4", "h-190"): "Barrel",
    ("mk23 hammer_6", "h-190"): "Metal", ("mk23 safety_8", "h-190"): "Metal", ("mk23 safety_8", "polymer"): "Frame",
    ("mk23 slide catch_11", "h-190"): "Metal", ("mk23 trigga_12", "h-190"): "Metal",
}
# Farben (sRGB 0-255); Skin_Slide bekommt die Farbe vom Skin (ohne Skin dunkelt GunModels sie ab)
SRGB = {"Skin_Slide": (36, 36, 40), "Neon_Slide_Dots": (90, 255, 110), "Magazine": (30, 30, 32), "Frame": (34, 34, 36),
        "Metal": (26, 26, 28), "Steel": (48, 48, 52), "Barrel": (40, 40, 43)}
# alles matt (SmoothPlastic, auch Metallteile): Metal spiegelt in der Sonne den Himmel, die Waffe wirkt dann fast weiß

# Marker (GLB-Einheiten: x = nach vorn, y = oben, z = rechts)
POINTS = [
    ("Point_Grip", (-1.48, -0.15, 0)),
    ("Point_SightRear", (X_REAR, Y_SIGHT, 0)),
    ("Point_SightFront", (X_FRONT, Y_SIGHT, 0)),
    ("Point_Muzzle", (X_FRONT_END, 0.627, 0)),
    ("Point_Eject", (-0.75, 0.80, 0.12)),
    ("Point_LeftHand", (-1.53, -0.38, -0.28)),
]


def rb(p):  # GLB-Welt -> Roblox (Lauf nach -Z), Studs
    x, y, z = p
    return (z * SCALE, y * SCALE, -x * SCALE)


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
                P, N = out.setdefault(name, ([], []))
                for i in G.indices(j, b, prim["indices"]):
                    v, n3 = pos[i], nor[i]
                    w = tuple(m[r] * v[0] + m[4 + r] * v[1] + m[8 + r] * v[2] + m[12 + r] for r in range(3))
                    q = tuple(m[r] * n3[0] + m[4 + r] * n3[1] + m[8 + r] * n3[2] for r in range(3))
                    ln = math.sqrt(sum(c * c for c in q)) or 1
                    P.append(rb(w)); N.append(rb(tuple(c / ln for c in q)))
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
    for name, pt in POINTS:
        p, n = cube(rb(pt), 0.03, None)
        parts[name] = (p, n, (1.0, 0.0, 1.0))
    return parts


def write_boxes(parts):
    """Testkopie: je Teil ein Quader über die Ausdehnung des Meshes, Marker wie im GLB."""
    material = {"Neon_Slide_Dots": "Neon"}
    boxes = []
    for name, (P, _, _) in parts.items():
        if name.startswith("Point"):
            continue
        lo = [min(v[i] for v in P) for i in range(3)]; hi = [max(v[i] for v in P) for i in range(3)]
        boxes.append({"name": name, "shape": "Block", "cframe": [*((a + c) / 2 for a, c in zip(lo, hi)), 1, 0, 0, 0, 1, 0, 0, 0, 1],
                      "size": tuple(c - a for a, c in zip(lo, hi)), "color": SRGB[name],
                      "material": material.get(name, "SmoothPlastic"), "transparency": 0.0})
    boxes += wt.marker_parts([(name, rb(pt)) for name, pt in POINTS])
    wt.write_rbxmx("Pistol", boxes, os.path.join(ROOT, "assets", "Weapons"))


def main():
    parts = build()
    write(parts, OUT)
    write_boxes(parts)
    for k, (P, _, _) in parts.items():
        if not k.startswith("Point"):
            print("  %-16s %5d Dreiecke" % (k, len(P) // 3))
    zs = [v[2] for k, (P, _, _) in parts.items() if not k.startswith("Point") for v in P]
    print("Pistol.glb: %d Teile, Länge %.2f Studs, Visierlinie %.3f über dem Griff -> art/sources/Pistol.glb"
          % (len(parts), max(zs) - min(zs), (Y_SIGHT - POINTS[0][1][1]) * SCALE))


if __name__ == "__main__":
    main()

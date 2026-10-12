#!/usr/bin/env python3
"""Bereitet das M60-Modell für den Studio-Import vor: art/sources/m60.glb -> art/sources/LMG.glb.

Die Datei ist fertig nach docs/waffen-modelle.md: Teile benannt (Skin_Receiver, Skin_Stock, Skin_Handguard, Skin_Cover
= Deckel und Gruppe Cover, Magazine = Munitionskasten links, Bolt = Spannhebel, Steel, Barrel, Metal, Neon_FrontDot),
lose Patronen, Gurtstücke und der zweite (volle) Munitionskasten entfernt, Größe in Studs (4,33 lang wie das alte MG),
Lauf nach -Z, Marker (Point_*, Pivot_Cover) als kleine Würfel. Der Zuführdeckel ist im Original mit dem Gehäuse-Oberteil
ein Objekt; alles vor X_COVER wird zum Deckel, der Rest zum Gehäuse.
Visierlinie: Oberkante der Kimmen-Ohren auf der Klappkimme (Kerbe) und Spitze des Korns; beim Zielen sitzt das Korn so
in der Kimmenkerbe in der Bildmitte.

Mit --boxes zusätzlich ein Quader-Nachbau als assets/Weapons/LMG.rbxmx (je Teil ein Quader so groß wie das Mesh,
Marker gleich), zum Prüfen ohne Studio. Achtung: überschreibt die echte Studio-Kopie (models/Weapons/LMG.rbxmx).

Dann in Studio: Import 3D > LMG.glb (Teile NICHT zusammenführen, Einheit Stud), Modell nach
ReplicatedStorage > Assets > Weapons ziehen, "LMG" nennen.
    python3 tools/m60_glb.py
"""
import math, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import glb_read as G  # noqa: E402
import weapon_templates as wt  # noqa: E402
from mp7_glb import cube, write  # noqa: E402

SRC = os.path.join(ROOT, "art", "sources", "m60.glb")
OUT = os.path.join(ROOT, "art", "sources", "LMG.glb")
X_BACK, X_FRONT_END = -5.521, 5.551  # Schaftkappe bis Mündungsfeuerdämpfer (GLB-Einheiten)
SCALE = 4.33 / (X_FRONT_END - X_BACK)  # -> 4,33 Studs wie das alte MG
X_COVER = -2.45  # Dreiecke des Deckel-Objekts vor dieser Linie = Zuführdeckel, dahinter Gehäuse-Oberteil
Y_REAR, Y_FRONT = 0.952, 1.015  # Oberkante der Kimmen-Ohren, Spitze des Korns (GLB-Einheiten)
X_REAR, X_FRONT = -1.022, 4.461  # Klappkimme, Korn

# (GLB-Gruppe, Material) -> Teilname im Spiel; nicht genannte fallen weg (lose Patronen, Gurt, voller Kasten)
PART_OF = {
    ("m60 receiver_7", "h-190"): "Skin_Receiver", ("m60 receiver_7", "stell"): "Steel",
    ("m60 receiver_7", "polymer"): "Skin_Stock",
    ("m60 cover_9", "h-190"): "Skin_Cover",
    ("m60 handguard_13", "polymer"): "Skin_Handguard", ("m60 handguard_13", "h-190"): "Barrel",
    ("m60 handguard_13", "stell"): "Steel",  # Tragegriff
    ("m60 barrel 22in_5", "h-190"): "Barrel", ("m60 flash hider_10", "h-190"): "Barrel",
    ("m60 bipod base_14", "h-190"): "Barrel", ("m60 bipod R leg_15", "h-190"): "Barrel",
    ("m60 bipod L leg_16", "h-190"): "Barrel",
    ("m60 bolt carrier_6", "stell"): "Steel",  # Gasstange, durch die Löcher im Handschutz zu sehen
    ("m60 charging handle_8", "h-190"): "Bolt",
    ("m60 trigga_11", "h-190"): "Metal", ("m60 safety_12", "h-190"): "Metal",
    ("m60 100rnd empty ammo box_17", "polymer"): "Magazine",
}
# Farben (sRGB 0-255); Skin_ bekommen die Farbe vom Skin (ohne Skin dunkelt GunModels sie ab)
SRGB = {"Skin_Receiver": (36, 36, 40), "Skin_Stock": (30, 30, 32), "Skin_Handguard": (30, 30, 32),
        "Skin_Cover": (36, 36, 40), "Steel": (48, 48, 52), "Barrel": (40, 40, 43), "Metal": (26, 26, 28),
        "Bolt": (40, 40, 43), "Magazine": (46, 50, 40), "Neon_FrontDot": (255, 190, 60)}
# alles matt (SmoothPlastic, auch Metallteile): Metal spiegelt in der Sonne den Himmel, die Waffe wirkt dann fast weiß

# Marker (GLB-Einheiten: x = nach vorn, y = oben, z = rechts)
COVER_HINGE = (X_COVER, 0.40, 0)  # Hinterkante des Deckels: die Nachlade-Animation klappt ihn 0,4 Studs hinter dem Drehpunkt auf
POINTS = [
    ("Point_Grip", (-2.33, -0.62, 0)),
    ("Point_SightRear", (X_REAR, Y_REAR, 0)),
    ("Point_SightFront", (X_FRONT, Y_FRONT, 0)),
    ("Point_Muzzle", (X_FRONT_END, 0.179, 0)),
    ("Point_Eject", (-1.75, 0.15, 0.30)),
    ("Point_LeftHand", (0.75, -0.42, -0.08)),
    ("Point_LeftHandTP", (0.15, -0.42, -0.08)),
    ("Point_Stock", (X_BACK, -0.07, 0)),
    ("Pivot_Cover", (COVER_HINGE[0] + 0.4 / SCALE, COVER_HINGE[1], 0)),
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
                    if name == "Skin_Cover" and sum(w[0] for w in ws) / 3 < X_COVER:
                        part = "Skin_Receiver"  # Gehäuse-Oberteil hinter dem Zuführdeckel
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
    # Leuchtpunkt auf der Kornspitze (Mitte auf der Visierlinie, wie bei der MP7)
    p, n = cube(rb((X_FRONT, Y_FRONT, 0)), 0.02, None)
    parts["Neon_FrontDot"] = (p, n, linear(SRGB["Neon_FrontDot"]))
    for name, pt in POINTS:
        p, n = cube(rb(pt), 0.04, None)
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
    wt.write_rbxmx("LMG", boxes, os.path.join(ROOT, "assets", "Weapons"))


def main():
    parts = build()
    write(parts, OUT)
    if "--boxes" in sys.argv:
        write_boxes(parts)
    total = 0
    for k, (P, _, _) in parts.items():
        if not k.startswith(("Point", "Pivot")):
            total += len(P) // 3
            print("  %-16s %5d Dreiecke" % (k, len(P) // 3))
    zs = [v[2] for k, (P, _, _) in parts.items() if not k.startswith(("Point", "Pivot")) for v in P]
    print("LMG.glb: %d Teile, %d Dreiecke, Länge %.2f Studs, Visierlinie %.3f über dem Griff -> art/sources/LMG.glb"
          % (len(parts), total, max(zs) - min(zs), (Y_REAR - POINTS[0][1][1]) * SCALE))


if __name__ == "__main__":
    main()

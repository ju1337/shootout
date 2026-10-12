# Meshy-Scharfschützengewehr ("magnum sniper", AWM-Bauart mit Zielfernrohr und Zweibein) -> Präzisionsgewehr DMR.
#
#   python3 tools/attachments/sniper_v1.py <meshy.glb> art/sources/DMR.glb
#
# Geometrie und Texturen bleiben unverändert (keine Reduzierung, Texturen 1:1 mit Normal Map). Das Skript
#  - klappt die Beine des Zweibeins am Gelenk nach vorn unter den Lauf (ausgeklappt hingen sie 0,6 Studs herunter),
#  - schneidet Magazin (`Magazine`) und Kammerstängel (`Bolt`) als bewegliche Teile heraus (Schnittflächen geschlossen),
#  - setzt die Marker: Visierlinie durch die Mitte von Okular und Objektiv (waagrecht wie der Lauf), Griff hinter dem
#    Abzugsbügel, linke Hand unter dem Handschutz, Mündung vorn an der Mündungsbremse, Schaft hinten an der Schaftkappe,
#  - skaliert auf 4,58 Studs (Länge des DMR), Lauf nach -Z, Griff = Ursprung,
#  - teilt den Rumpf in Stücke unter 20.000 Dreiecken (`Skin_Body_01` …; Skin-Texturen namens Skin_Body gelten für alle).
# Maße in Meshy-Einheiten (Lauf nach -x, oben +y, Kammerstängel auf der rechten Seite = -z); gelten nur für dieses Modell.
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_io import M, read_glb, write_glb

SRC, OUT = sys.argv[1], sys.argv[2]
LENGTH = 4.575
MAX_TRIS = 19500
SIGHT_Y = (0.1786 + 0.1968) / 2   # Mitte Okular (0.1786) und Objektiv (0.1968): waagrechte Linie wie der Lauf
POINTS = {
    "Point_Grip": (0.495, -0.045, 0.0),
    "Point_SightRear": (0.5125, SIGHT_Y, -0.001),     # Okular-Linse
    "Point_SightFront": (-0.075, SIGHT_Y, -0.001),    # Objektiv-Linse
    "Point_Muzzle": (None, 0.0949, 0.0),              # vorn an der Mündungsbremse, Höhe der Laufachse
    "Point_Eject": (0.30, 0.115, -0.035),             # Auswurf rechts über dem Magazin
    "Point_LeftHand": (-0.03, 0.06, 0.0),             # unter dem Handschutz
    "Point_Stock": (None, -0.0025, 0.0),              # Mitte der Schaftkappe
    "Pivot_Magazine": (0.265, -0.003, 0.0),
    "Pivot_Bolt": (0.40, 0.10, -0.04),
}
MAG = dict(x=(0.172, 0.358), y_top=-0.003)
BOLT = dict(x=(0.36, 0.46), y=(0.0, 0.12), z=-0.046)
BIPOD = dict(x=(-0.33, -0.18), y_cut=-0.027, hinge=(-0.238, 0.0), fold=(-1.0, 0.06, 0.0))


def dark_uv(mesh, point):
    c = mesh.P.mean(1)
    return tuple(mesh.UV[np.argmin(np.linalg.norm(c - np.asarray(point), axis=1))].mean(0))


def cut_out(mesh, region, cap_index, uv):
    """(Rest, Teil) mit geschlossenen Schnittflächen an Ebene cap_index."""
    rest, part = M.split(mesh, region)
    cap_rest, o1 = M.cap_cut(mesh, region, [cap_index], -1, uv)
    cap_part, o2 = M.cap_cut(mesh, region, [cap_index], 1, uv)
    return M.Mesh.concat(rest, cap_rest), M.Mesh.concat(part, cap_part), o1 + o2


def rotation(a, b):
    """Kleinste Drehung, die Richtung a auf Richtung b bringt."""
    a, b = np.asarray(a, float) / np.linalg.norm(a), np.asarray(b, float) / np.linalg.norm(b)
    v, c = np.cross(a, b), float(a @ b)
    K = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + K + K @ K / (1 + c)


def fold_bipod(gun):
    x0, x1 = BIPOD["x"]
    legs = []
    for side in (1, -1):
        region = [M.plane((0, 1, 0), (0, BIPOD["y_cut"], 0)), M.plane((-1, 0, 0), (x0, 0, 0)),
                  M.plane((1, 0, 0), (x1, 0, 0)), M.plane((0, 0, -side), (0, 0, 0))]
        uv = dark_uv(gun, (BIPOD["hinge"][0], BIPOD["y_cut"] - 0.05, side * 0.06))
        gun, leg, open_ = cut_out(gun, region, 0, uv)
        top = leg.P.reshape(-1, 3)
        top = top[np.abs(top[:, 1] - BIPOD["y_cut"]) < 1e-4]
        hinge = np.array([BIPOD["hinge"][0], BIPOD["hinge"][1], top[:, 2].mean()])
        foot = leg.P.reshape(-1, 3)[leg.P.reshape(-1, 3)[:, 1] < leg.bounds()[0][1] + 0.03].mean(0)
        R = rotation(foot - hinge, BIPOD["fold"])
        folded = M.Mesh((leg.P - hinge) @ R.T + hinge, leg.UV, leg.N @ R.T)
        lo, hi = folded.bounds()
        print("Zweibein %s: %d Dreiecke, eingeklappt x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f (offen %d)"
              % ("links" if side > 0 else "rechts", len(leg), lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], open_))
        legs.append(folded)
    return M.Mesh.concat(gun, *legs)


def main():
    gun, images = read_glb(SRC)
    lo, hi = gun.bounds()
    muzzle_x, stock_x = lo[0], hi[0]
    print("Meshy: %d Dreiecke, %.3f lang" % (len(gun), stock_x - muzzle_x))
    gun = fold_bipod(gun)
    region = [M.plane((0, 1, 0), (0, MAG["y_top"], 0)), M.plane((-1, 0, 0), (MAG["x"][0], 0, 0)),
              M.plane((1, 0, 0), (MAG["x"][1], 0, 0))]
    gun, mag, o1 = cut_out(gun, region, 0, dark_uv(gun, (0.265, -0.05, 0.02)))
    region = [M.plane((0, 0, 1), (0, 0, BOLT["z"])), M.plane((-1, 0, 0), (BOLT["x"][0], 0, 0)),
              M.plane((1, 0, 0), (BOLT["x"][1], 0, 0)), M.plane((0, -1, 0), (0, BOLT["y"][0], 0)),
              M.plane((0, 1, 0), (0, BOLT["y"][1], 0))]
    gun, bolt, o2 = cut_out(gun, region, 0, dark_uv(gun, (0.40, 0.05, -0.085)))
    print("Magazin %d, Kammerstängel %d Dreiecke (offene Stellen %d/%d)" % (len(mag), len(bolt), o1, o2))

    pts = {k: np.array([muzzle_x if k == "Point_Muzzle" else stock_x if x is None else x, y, z], float)
           for k, (x, y, z) in POINTS.items()}
    s = LENGTH / (stock_x - muzzle_x)
    R = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)   # Lauf -x -> -Z, rechts (-z) -> +X
    origin = pts["Point_Grip"]
    conv = lambda m: M.Mesh((m.P - origin) @ R.T * s, m.UV, m.N @ R.T)  # noqa: E731
    body = conv(gun)
    order = np.argsort(body.P.mean(1)[:, 2], kind="stable")       # Stücke entlang des Laufs
    chunks = int(np.ceil(len(body) / MAX_TRIS))
    parts = []
    for i, idx in enumerate(np.array_split(order, chunks)):
        parts.append(("Skin_Body_%02d" % (i + 1), body.select(np.sort(idx)), 0))
    parts += [("Magazine", conv(mag), 0), ("Bolt", conv(bolt), 0)]
    for k, p in sorted(pts.items()):
        q = (p - origin) @ R.T * s
        size = 0.06 if k.startswith("Pivot") else 0.04
        parts.append((k, M.box(q, (size, size, size)), 1))
        print("  %-17s (%6.3f %6.3f %6.3f)" % (k, *q))
    write_glb(OUT, parts, [{"Name": "DMR", **images}, {"Name": "Marker", "Factor": (1.0, 0.0, 1.0)}])
    total = sum(len(m) for n, m, _ in parts if not n.startswith(("Point", "Pivot")))
    print("Länge %.3f Studs, %d Dreiecke in %d Rumpf-Stücken (max %d) -> %s %.1f MB"
          % ((stock_x - muzzle_x) * s, total, chunks, max(len(m) for n, m, _ in parts), OUT, os.path.getsize(OUT) / 1e6))


main()

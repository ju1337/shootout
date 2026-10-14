# Meshy-Waffen (FBX-Export mit PNG-Texturen) spielfertig machen: Animationsgruppen herausschneiden (Schnittflächen
# geschlossen), Marker setzen, auf die Länge der Vorlage skalieren, Lauf nach -Z, Griff = Ursprung, Teile über
# 19.500 Dreiecken in Stücke teilen (Name_01 …). Geometrie unverändert (keine Reduzierung), Texturen in voller
# Auflösung (meshy_fbx.py).
#
#   python3 tools/attachments/meshy_weapon.py <Waffe> <meshy-ordner-oder-zip> art/sources/<Waffe>.glb
#
# Maße in Meshy-Einheiten / 100 (Lauf nach -x, oben +y, rechts = -z); gelten nur für das jeweilige Meshy-Modell.
import os, sys, tempfile, zipfile
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_io import M, write_glb
import meshy_fbx

MAX_TRIS = 19500


def box(x=None, y=None, z=None):
    """Bereich als Ebenen: x/y/z = (min, max), None = offen. Reihenfolge: x-min, x-max, y-min, y-max, z-min, z-max."""
    planes = []
    for axis, rng in ((0, x), (1, y), (2, z)):
        if rng is None:
            continue
        lo, hi = rng
        if lo is not None:
            n = [0, 0, 0]; n[axis] = -1; p = [0, 0, 0]; p[axis] = lo
            planes.append(M.plane(n, p))
        if hi is not None:
            n = [0, 0, 0]; n[axis] = 1; p = [0, 0, 0]; p[axis] = hi
            planes.append(M.plane(n, p))
    return planes


# Je Waffe: Länge (Studs, wie die Vorlage), Teile, die herausgeschnitten werden (Name, Bereich, Ebenen mit Deckel,
# Punkt für die Deckelfarbe), Marker. Muzzle/Stock mit x=None: vorderstes bzw. hinterstes Ende des Modells.
WEAPONS = {
    "Pistol": {
        "Length": 1.046,
        "Body": "Skin_Body",
        "Cuts": [
            ("Skin_Slide", box(y=(0.405, None)), [0], (0.0, 0.5, 0.1)),
            ("Magazine", box(x=(0.3, None), y=(None, -0.535)), [1], (0.6, -0.6, 0.0)),
        ],
        "Points": {
            "Point_Grip": (0.57, 0.02, 0.0),
            "Point_SightRear": (0.76, 0.6566, -0.0033),
            "Point_SightFront": (-0.80, 0.6566, -0.0033),
            "Point_Muzzle": (None, 0.50, 0.0),
            "Point_Eject": (-0.10, 0.60, -0.06),
            "Point_LeftHand": (0.62, -0.16, 0.22),
            "Pivot_Slide": (0.0, 0.50, 0.0),
            "Pivot_Magazine": (0.58, -0.135, 0.0),
        },
        # Kimme und Korn: Die Kimmenkerbe des Meshy-Modells war schmaler (0,023) als das Korn (0,045) – das Korn deckte
        # sie ganz zu, Kimme und Korn sahen aus wie ein Block. Kerbe auf 1,5-mal die Kornbreite verbreitert (gleiche
        # Tiefe), mittig über dem Korn. Leuchtpunkte bündig auf den Rückseiten: einer am Korn (orange), zwei an der Kimme
        # neben der Kerbe (weiß). Visierlinie = Kornspitze (0,6566) mittig in der Kerbe, bündig mit der Kimmen-Oberkante.
        "Sights": {
            "Notch": {"x": (0.70, 0.82), "bottom": 0.614, "z": -0.0033, "half": 0.034},
            "Dots": [("Neon_FrontDot", (-0.7341, 0.641, -0.0033), 0.012, "front"),
                     ("Neon_RearDot_L", (0.8029, 0.637, 0.055), 0.011, "rear"),
                     ("Neon_RearDot_R", (0.8063, 0.637, -0.061), 0.011, "rear")],
        },
    },
    # Revolver (.44 Magnum): Trommel im Rahmenfenster (Oberschiene bleibt), Hahn hinter der schrägen Rahmenkante.
    # Kein Schnelllader im Modell (Gruppe Loader fehlt: beim Nachladen ohne Schnelllader).
    "Revolver": {
        "Length": 1.47,
        "Body": "Skin_Body",
        "Cuts": [
            ("Cylinder", box(x=(-0.025, 0.262), y=(0.075, 0.395)), [0, 1, 2, 3], (0.12, 0.40, 0.0)),
            ("Hammer", [M.plane((-0.15, -0.13, 0), (0.40, 0.42, 0)), *box(x=(None, 0.62), y=(0.27, 0.45))], [0],
             (0.5, 0.36, 0.0)),
        ],
        # Schnelllader: Kopie der Trommel, kurz (ein Drittel so lang) und etwas schmaler, links hinter der Trommel
        # (nur beim Nachladen sichtbar)
        "Extras": [("Loader", "Cylinder", None, (0.35, 0.85, 0.85), None, (0.60, 0.34, 0.36))],
        "Points": {
            "Point_Grip": (0.62, -0.02, 0.0),
            "Point_SightRear": (0.33, 0.517, 0.0),
            "Point_SightFront": (-0.87, 0.517, 0.0),
            "Point_Muzzle": (None, 0.315, 0.0),
            "Point_Eject": (0.12, 0.30, 0.0),
            "Point_LeftHand": (0.63, -0.15, 0.156),
            "Pivot_Cylinder": (0.12, 0.235, 0.0),
            "Pivot_Hammer": (0.43, 0.32, 0.0),
            "Pivot_Loader": (0.60, 0.34, 0.36),
        },
        # Kimme und Korn: Kerbe (0,046) und Korn (0,087, aber weiter vom Auge) waren aus Sicht des Auges gleich breit –
        # kein Lichtspalt. Kerbe auf 0,066 verbreitert; Visierlinie von 0,505 (Kornmitte) auf die Kornspitze 0,517.
        "Sights": {
            "Notch": {"x": (0.26, 0.345), "bottom": 0.488, "z": 0.0, "half": 0.033},
            "Dots": [("Neon_FrontDot", (-0.8427, 0.502, -0.0008), 0.011, "front"),
                     ("Neon_RearDot_L", (0.3357, 0.503, 0.054), 0.0085, "rear"),
                     ("Neon_RearDot_R", (0.3357, 0.503, -0.054), 0.0085, "rear")],
        },
    },
    # MP (MP5): gebogenes Magazin unter dem Schacht, Spannhebel oben auf dem Rohr vor dem Gehäuse als Bolt
    "SMG": {
        "Length": 2.375,
        "Body": "Skin_Body",
        "Cuts": [
            ("Magazine", box(x=(-0.48, -0.115), y=(None, 0.04)), [2], (-0.3, -0.1, 0.0)),
            ("Bolt", box(x=(-0.585, -0.495), y=(0.366, None), z=(-0.015, 0.017)), [2], (-0.54, 0.37, 0.0)),
        ],
        "Points": {
            "Point_Grip": (0.20, 0.03, 0.0),
            "Point_SightRear": (0.245, 0.425, 0.0),
            "Point_SightFront": (-0.80, 0.425, 0.0),
            "Point_Muzzle": (None, 0.245, 0.0),
            "Point_Eject": (0.0, 0.26, -0.06),
            "Point_LeftHand": (-0.50, 0.25, 0.0),
            "Point_Stock": (None, 0.125, 0.0),
            "Pivot_Magazine": (-0.20, 0.04, 0.0),
            "Pivot_Bolt": (-0.54, 0.37, 0.0),
        },
    },
    # Schrotflinte (taktisch, Vorderschaft-Repetierer): Vorderschaft samt Röhrenmagazin-Stück darin als Pump.
    # Keine einzelne Patrone im Modell (Shell fehlt: beim Nachladen ohne sichtbare Patrone).
    "Shotgun": {
        "Length": 3.95,
        "Body": "Skin_Body",
        "Cuts": [
            ("Pump", box(x=(-0.60, -0.17), y=(-0.06, 0.09)), [0, 1], (-0.4, 0.02, 0.06)),
        ],
        # Patrone fürs Nachladen: Kopie der oberen roten Patrone am Seitenhalter (der Halter bleibt voll), längs zum
        # Lauf gedreht, doppelt so lang, vor der Ladeklappe unter dem Gehäuse (nur beim Nachladen sichtbar)
        "Extras": [("Shell", "red", box(x=(0.22, 0.32), y=(0.06, 0.12), z=(0.02, None)),
                    (1.0, 2.0, 1.0), "y_to_x", (0.06, -0.02, 0.0))],
        "Points": {
            "Point_Grip": (0.46, 0.03, 0.0),
            "Point_SightRear": (0.22, 0.205, 0.0),
            "Point_SightFront": (-0.85, 0.205, 0.0),
            "Point_Muzzle": (None, 0.125, 0.0),
            "Point_Eject": (0.05, 0.11, -0.04),
            "Point_LeftHand": (-0.38, 0.02, 0.0),
            "Point_Stock": (None, -0.05, 0.0),
            "Pivot_Pump": (-0.38, 0.02, 0.0),
            "Pivot_Shell": (0.06, -0.02, 0.0),
        },
    },
    # MG (taktisch, Gurt aus Kasten): Patronenkasten unter dem Gehäuse als Magazine (der Gurt im Zuführfenster bleibt
    # – Gurt und Gehäusewände sind dort eins), Deckel mit Schiene als Cover, Klappe vor dem Gehäuse als Bolt.
    # Visierlinie waagrecht über die Kornspitze, der hintere Block liegt knapp darunter.
    "LMG": {
        "Length": 4.33,
        "Body": "Skin_Body",
        "Cuts": [
            ("Magazine", box(x=(-0.08, 0.145), y=(None, -0.035)), [2], (0.03, -0.15, 0.1)),
            ("Skin_Cover", box(x=(-0.06, 0.40), y=(0.19, None)), [0, 1, 2], (0.17, 0.2, 0.0)),
            ("Bolt", box(x=(-0.15, -0.065), y=(0.152, None)), [2], (-0.11, 0.18, 0.0)),
        ],
        "Points": {
            "Point_Grip": (0.35, -0.08, 0.0),
            "Point_SightRear": (0.405, 0.274, 0.0),
            "Point_SightFront": (-0.83, 0.274, 0.0),
            "Point_Muzzle": (None, 0.113, 0.0),
            "Point_Eject": (0.20, 0.05, -0.06),
            "Point_LeftHand": (-0.42, 0.03, 0.0),
            "Point_LeftHandTP": (-0.27, 0.03, 0.0),
            "Point_Stock": (None, 0.03, 0.0),
            "Pivot_Magazine": (0.03, -0.04, 0.0),
            "Pivot_Cover": (0.17, 0.20, 0.0),
            "Pivot_Bolt": (-0.11, 0.155, 0.0),
        },
    },
}


def hull2(points):
    """Konvexe Hülle (2D, gegen den Uhrzeigersinn)."""
    pts = sorted(set(map(tuple, np.round(points, 6))))
    if len(pts) < 3:
        return pts
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def wall(mesh, cut, clip, axes, fixed, normal, uv):
    """Fläche in der Schnittebene cut, begrenzt durch clip (Ebenen, d <= 0 bleibt): Hülle der Schnittpunkte."""
    segs = M.section(mesh, cut, clip)
    if not segs:
        return M.Mesh(np.zeros((0, 3, 3)))
    pts2 = np.array([[p[axes[0]], p[axes[1]]] for s_ in segs for p in s_])
    ring = hull2(pts2)
    pts3 = []
    for a, b in ring:
        q = [0.0, 0.0, 0.0]
        q[axes[0]], q[axes[1]], q[fixed[0]] = a, b, fixed[1]
        pts3.append(q)
    return M.cap(pts3, normal, uv)


def notch(gun, cfg):
    """Rechteckige Kimmenkerbe: Bereich herausschneiden, Seitenwände und Boden schließen."""
    x0, x1 = cfg["x"]
    zc, h, yb = cfg["z"], cfg["half"], cfg["bottom"]
    region = box(x=(x0, x1), y=(yb, None), z=(zc - h, zc + h))
    keep, _cut = M.split(gun, region)
    uv = dark_uv(gun, ((x0 + x1) / 2, yb + 0.04, zc + h + 0.03))   # Oberseite der Kimme neben der Kerbe (dunkel)
    above = M.plane((0, -1, 0), (0, yb, 0))
    xs = [M.plane((-1, 0, 0), (x0, 0, 0)), M.plane((1, 0, 0), (x1, 0, 0))]
    left = wall(gun, M.plane((0, 0, 1), (0, 0, zc - h)), [above] + xs, (0, 1), (2, zc - h), (0, 0, 1), uv)
    right = wall(gun, M.plane((0, 0, 1), (0, 0, zc + h)), [above] + xs, (0, 1), (2, zc + h), (0, 0, -1), uv)
    inside = [M.plane((0, 0, -1), (0, 0, zc - h)), M.plane((0, 0, 1), (0, 0, zc + h))] + xs
    floor = wall(gun, M.plane((0, 1, 0), (0, yb, 0)), inside, (0, 2), (1, yb), (0, 1, 0), uv)
    print("  Kimmenkerbe: %d Dreiecke entfernt, Wände %d/%d, Boden %d" % (len(gun) - len(keep), len(left), len(right), len(floor)))
    return M.Mesh.concat(keep, left, right, floor)


def dot(centre, radius, depth=0.005, sides=12):
    """Runder Leuchtpunkt: flache Scheibe, Achse entlang x (zum Auge)."""
    c = np.asarray(centre, float)
    ring = [(radius * np.cos(a), radius * np.sin(a)) for a in np.linspace(0, 2 * np.pi, sides, endpoint=False)]
    back = [c + (-depth / 2, y, z) for y, z in ring]
    fwd = [c + (depth / 2, y, z) for y, z in ring]
    tris = []
    for i in range(sides):
        j = (i + 1) % sides
        tris += [[c + (depth / 2, 0, 0), fwd[i], fwd[j]], [c + (-depth / 2, 0, 0), back[j], back[i]],
                 [back[i], back[j], fwd[j]], [back[i], fwd[j], fwd[i]]]
    return M.Mesh(np.array(tris))


def load(src):
    if src.endswith(".zip"):
        tmp = tempfile.mkdtemp()
        zipfile.ZipFile(src).extractall(tmp)
        src = tmp
    return meshy_fbx.load(src)


def dark_uv(mesh, point):
    c = mesh.P.mean(1)
    return tuple(mesh.UV[np.argmin(np.linalg.norm(c - np.asarray(point), axis=1))].mean(0))


def build(name, src, out):
    cfg = WEAPONS[name]
    gun, images = load(src)
    lo, hi = gun.bounds()
    print("%s: Meshy %d Dreiecke, %.3f lang" % (name, len(gun), hi[0] - lo[0]))
    sights = cfg.get("Sights", {})
    if "Notch" in sights:
        gun = notch(gun, sights["Notch"])
    parts = []
    for part_name, region, caps, uv_point in cfg["Cuts"]:
        uv = dark_uv(gun, uv_point)
        rest, piece = M.split(gun, region)
        cap_rest, o1 = M.cap_cut(gun, region, caps, -1, uv) if caps else (None, 0)
        cap_piece, o2 = M.cap_cut(gun, region, caps, 1, uv) if caps else (None, 0)
        gun = M.Mesh.concat(rest, cap_rest)
        piece = M.Mesh.concat(piece, cap_piece)
        print("  %-14s %7d Dreiecke (offene Stellen %d/%d)" % (part_name, len(piece), o1, o2))
        parts.append((part_name, piece))
    parts.insert(0, (cfg["Body"], gun))
    for extra_name, source, region, scale, turn, target in cfg.get("Extras", []):
        if source == "red":   # rote Flächen (Textur) im Bereich, z.B. eine Schrotpatrone
            import io
            from PIL import Image
            tex = np.asarray(Image.open(io.BytesIO(images["Color"][0])).convert("RGB")).astype(float)
            h, w, _ = tex.shape
            uv = gun.UV.mean(1)
            col = tex[np.clip(((1 - uv[:, 1]) * h).astype(int), 0, h - 1), np.clip((uv[:, 0] * w).astype(int), 0, w - 1)]
            c = gun.P.mean(1)
            inside = np.all([c @ n - k <= 0 for n, k in region], axis=0)
            piece = gun.select(inside & (col[:, 0] > 1.6 * col[:, 1]) & (col[:, 0] > 90))
        else:                 # Kopie eines schon herausgeschnittenen Teils
            piece = dict(parts)[source]
        lo_p, hi_p = piece.bounds()
        centre = (lo_p + hi_p) / 2
        Rt = np.eye(3)
        if turn == "y_to_x":
            Rt = np.array([[0, 1, 0], [-1, 0, 0], [0, 0, 1]], float)   # Hochachse wird Laufachse
        P = ((piece.P - centre) * np.asarray(scale)) @ Rt.T + np.asarray(target)
        N = (piece.N / np.asarray(scale)) @ Rt.T
        N /= np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-12)
        parts.append((extra_name, M.Mesh(P, piece.UV, N)))
        print("  %-14s %7d Dreiecke (Kopie von %s)" % (extra_name, len(piece), source))

    pts = {k: np.array([lo[0] if k == "Point_Muzzle" and x is None else hi[0] if x is None else x, y, z], float)
           for k, (x, y, z) in cfg["Points"].items()}
    s = cfg["Length"] / (hi[0] - lo[0])
    R = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)   # Lauf -x -> -Z, rechts (-z) -> +X
    origin = pts["Point_Grip"]
    conv = lambda m: M.Mesh((m.P - origin) @ R.T * s, m.UV, m.N @ R.T)  # noqa: E731
    out_parts = []
    for part_name, mesh in parts:
        mesh = conv(mesh)
        chunks = int(np.ceil(len(mesh) / MAX_TRIS))
        if chunks <= 1:
            out_parts.append((part_name, mesh, 0))
            continue
        order = np.argsort(mesh.P.mean(1)[:, 2], kind="stable")      # Stücke entlang des Laufs
        for i, idx in enumerate(np.array_split(order, chunks)):
            out_parts.append(("%s_%02d" % (part_name, i + 1), mesh.select(np.sort(idx)), 0))
    for dot_name, centre, radius, kind in sights.get("Dots", []):
        out_parts.append((dot_name, conv(dot(centre, radius)), 2 if kind == "front" else 3))
    for k, p in sorted(pts.items()):
        q = (p - origin) @ R.T * s
        size = 0.06 if k.startswith("Pivot") else 0.04
        out_parts.append((k, M.box(q, (size, size, size)), 1))
        print("  %-17s (%6.3f %6.3f %6.3f)" % (k, *q))
    write_glb(out, out_parts, [{"Name": name, **images}, {"Name": "Marker", "Factor": (1.0, 0.0, 1.0)},
                               {"Name": "Neon_Front", "Factor": (1.0, 0.47, 0.16)},
                               {"Name": "Neon_Rear", "Factor": (0.92, 0.94, 0.94)}])
    meshes = [(n, m) for n, m, mat in out_parts if mat != 1]
    print("  Länge %.3f Studs, %d Dreiecke in %d Teilen (max %d) -> %s %.1f MB"
          % ((hi[0] - lo[0]) * s, sum(len(m) for _, m in meshes), len(meshes), max(len(m) for _, m in meshes), out,
             os.path.getsize(out) / 1e6))


if __name__ == "__main__":
    build(sys.argv[1], sys.argv[2], sys.argv[3])

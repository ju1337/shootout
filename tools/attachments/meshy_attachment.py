# Meshy-Aufsätze (FBX-Export mit PNG-Texturen) für eine bestimmte Meshy-Waffe spielfertig machen. Der Aufsatz wird im
# Koordinatensystem der Waffen-GLB gebaut (gleicher Ursprung, gleiche Skalierung wie meshy_weapon.py), so passt er
# genau an diese Waffe; im Spiel heißt das Modell <Aufsatz>_<Waffe> (z.B. FastMag_SMG) und hat Vorrang vor dem
# allgemeinen Modell <Aufsatz>.
#
#   python3 tools/attachments/meshy_attachment.py <Waffe> <Aufsatz> <meshy-zip> <waffen-meshy-zip> <waffe.glb> <aus.glb>
#
# Nichts wird reduziert (keine Dreiecke weg, Texturen in voller Größe); Teile über 19.500 Dreiecken werden entlang des
# Laufs in Stücke Name_01 … geteilt. Nur gedreht (keine Spiegelung: Schrift bleibt lesbar), gleichmäßig skaliert und
# verschoben. Maße in Meshy-Einheiten der Waffe (Lauf nach -x, oben +y), wie in meshy_weapon.WEAPONS.
#
# Marker (wie GunModels.attachmentSource):
#   Magazin:  Point_Mount = Mitte des größten eingebauten Magazin-Teils (dort setzt das Spiel den Aufsatz hin),
#             Point_Front = davor (Laufrichtung)
#   Mündung:  Point_Mount = Point_Muzzle der Waffe, Point_Muzzle = neues vorderes Ende
#   Visier:   Point_Mount = Point_Optic der Waffe (Unterkante des Fußes), Point_SightRear/SightFront = Visierlinie durch
#             den Leuchtpunkt Neon_Reticle; Glas im Fenster (Glass)
import json, os, struct, sys, tempfile, zipfile
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_io import M, write_glb
import meshy_fbx
import meshy_weapon as W

MAX_TRIS = 19500

# Je Waffe und Aufsatz: turn = Drehung um die Hochachse (180: vorn und hinten tauschen), scale = Faktor auf die
# Meshy-Einheiten des Aufsatzes, tilt = Neigung um die Querachse (Grad), dann die Lage (siehe place()).
ATTACHMENTS = {
    # Schnellmagazin (30er mit Zugschlaufe): an die Kontur des eingebauten Magazins angepasst (Vorder- und Hinterkante
    # von y -0,40 bis 0,03, mittlere Abweichung 0,004), 18° geneigt wie dieses; oben steckt es im Schacht.
    ("SMG", "FastMag"): {"Kind": "Magazine", "Name": "Magazine_Fast", "turn": 180, "scale": 0.4164, "tilt": -18.22,
                         "at": (-0.2783, -0.1657, 0.0)},
    # Schalldämpfer: 0,20 dick (Lauf 0,092), Klemmring hinten über dem ganzen Laufstück vor dem Korn (bis -0,862)
    ("SMG", "Suppressor"): {"Kind": "Muzzle", "Name": "Suppressor", "turn": 0, "diameter": 0.20, "rear": -0.862},
    # Kompensator: 0,13 dick, Ring hinten 0,05 über dem Laufende
    ("SMG", "Compensator"): {"Kind": "Muzzle", "Name": "Compensator", "turn": 0, "diameter": 0.13, "rear": -0.902},
    # Rotpunkt (offenes Fenster vorn, Sender hinten): Fuß auf der Gehäuserippe (Oberkante 0,36, Fuß 0,335),
    # hinteres Ende 0,16 (vor der Trommel der Kimme). Fenster in Meshy-Einheiten des Visiers: y 0,07–0,585,
    # z -0,49–0,47, Glas bei x 0,70 (Haube 0,617–0,78).
    ("SMG", "HoloSight"): {"Kind": "Optic", "Name": "RedDot", "turn": 180, "scale": 0.10, "bottom": 0.335,
                           "rear": 0.16, "window": {"x": 0.70, "y": (0.07, 0.585), "z": (-0.49, 0.47)}},
}

# Achse des Laufs vorn (Messung am Meshy-Modell der Waffe): Mitte y/z, Radius
MUZZLE_AXIS = {"SMG": (0.2503, 0.0002, 0.046)}


def unzip(src):
    if src.endswith(".zip"):
        tmp = tempfile.mkdtemp()
        zipfile.ZipFile(src).extractall(tmp)
        return tmp
    return src


def rotation(turn, tilt=0.0):
    t, a = np.radians(turn), np.radians(tilt)
    ry = np.array([[np.cos(t), 0, np.sin(t)], [0, 1, 0], [-np.sin(t), 0, np.cos(t)]])
    rz = np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1]])
    return rz @ ry


def glb_nodes(path):
    """Teile einer GLB: Name -> (min, max) aus den Accessoren (ohne Knoten-Transform, wie meshy_weapon sie schreibt)."""
    data = open(path, "rb").read()
    doc = json.loads(data[20:20 + struct.unpack("<I", data[12:16])[0]])
    out = {}
    for node in doc["nodes"]:
        acc = doc["accessors"][doc["meshes"][node["mesh"]]["primitives"][0]["attributes"]["POSITION"]]
        out[node["name"]] = (np.array(acc["min"]), np.array(acc["max"]))
    return out


def build(weapon, att, src, weapon_src, weapon_glb, out):
    cfg = ATTACHMENTS[(weapon, att)]
    wcfg = W.WEAPONS[weapon]
    mesh, images = meshy_fbx.load(unzip(src))
    lo, hi = mesh.bounds()
    print("%s %s: Meshy %d Dreiecke, %s" % (weapon, att, len(mesh), np.round(hi - lo, 3)))
    kind = cfg["Kind"]
    if kind == "Muzzle":
        cfg = {**cfg, "scale": cfg["diameter"] / max(hi[1] - lo[1], hi[2] - lo[2])}
    s = cfg["scale"]
    Rm = rotation(cfg["turn"], cfg.get("tilt", 0.0))
    P = (mesh.P * s) @ Rm.T
    N = mesh.N @ Rm.T
    plo, phi = P.reshape(-1, 3).min(0), P.reshape(-1, 3).max(0)
    extra, points = [], {}
    if kind == "Magazine":
        P = P + np.asarray(cfg["at"])
    elif kind == "Muzzle":
        y0, z0, radius = MUZZLE_AXIS[weapon]
        P = P + np.array([cfg["rear"] - phi[0], y0 - (plo[1] + phi[1]) / 2, z0 - (plo[2] + phi[2]) / 2])
        print("  Durchmesser %.3f (Lauf %.3f), Länge %.3f" % (cfg["diameter"], 2 * radius, phi[0] - plo[0]))
    elif kind == "Optic":
        win = cfg["window"]
        centre = np.array([win["x"], sum(win["y"]) / 2, sum(win["z"]) / 2]) * s @ Rm.T
        shift = np.array([cfg["rear"] - phi[0], cfg["bottom"] - plo[1], -centre[2]])
        P = P + shift
        lens = centre + shift
        # Glas: beidseitig, etwas größer als die (im Raster 0,04 gemessene) Öffnung, Ecken abgeschrägt wie der Rahmen –
        # die Ränder stecken im Rahmen der Haube
        (y0, y1), (z0, z1) = win["y"], win["z"]
        e, c = 0.03, 0.14
        y0, y1, z0, z1 = y0 - e, y1 + e, z0 - e, z1 + e
        ring = [(y0, z0 + c), (y0, z1 - c), (y0 + c, z1), (y1 - c, z1), (y1, z1 - c), (y1, z0 + c), (y1 - c, z0), (y0 + c, z0)]
        corners = [np.array([win["x"], y, z]) * s @ Rm.T + shift for y, z in ring]
        glass = M.Mesh.concat(M.cap(corners, (1, 0, 0), (0.5, 0.5)), M.cap(corners[::-1], (-1, 0, 0), (0.5, 0.5)))
        extra += [("Glass", glass, 2), ("Neon_Reticle", M.box(lens, (0.004, 0.004, 0.004)), 3)]
        points["Point_SightFront"] = lens
        points["Point_SightRear"] = np.array([cfg["rear"], lens[1], lens[2]])
        points["Point_Mount"] = np.array(wcfg["Points"]["Point_Optic"], float)
        print("  Visierlinie y %.4f (Kimme/Korn %.3f), Fenster %.3f x %.3f, Glas bei x %.3f"
              % (lens[1], wcfg["Points"]["Point_SightRear"][1], (y1 - y0) * s, (z1 - z0) * s, lens[0]))
    part = M.Mesh(P, mesh.UV, N)
    alo, ahi = part.bounds()
    print("  Lage x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % (alo[0], ahi[0], alo[1], ahi[1], alo[2], ahi[2]))

    # in die Waffen-GLB umrechnen (wie meshy_weapon.build)
    gun, _ = meshy_fbx.load(unzip(weapon_src))
    glo, ghi = gun.bounds()
    ws = wcfg["Length"] / (ghi[0] - glo[0])
    R = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)
    origin = np.array(wcfg["Points"]["Point_Grip"], float)
    to_glb = lambda p: (np.asarray(p, float) - origin) @ R.T * ws  # noqa: E731
    conv = lambda m: M.Mesh(to_glb(m.P), m.UV, m.N @ R.T)  # noqa: E731

    if kind == "Muzzle":
        mz = wcfg["Points"]["Point_Muzzle"]
        mount = np.array([glo[0] if mz[0] is None else mz[0], mz[1], mz[2]])
        points["Point_Mount"] = mount
        points["Point_Muzzle"] = np.array([alo[0], mount[1], mount[2]])
    glb_points = {k: to_glb(v) for k, v in points.items()}
    if kind == "Magazine":
        # Point_Mount = Mitte des größten Magazin-Teils der Waffen-GLB (so setzt GunModels den Aufsatz)
        nodes = glb_nodes(weapon_glb)
        mags = [(np.prod(b - a), (a + b) / 2) for n, (a, b) in nodes.items() if n.split("_")[0] == "Magazine"]
        glb_points["Point_Mount"] = max(mags, key=lambda m: m[0])[1]
        glb_points["Point_Front"] = glb_points["Point_Mount"] + np.array([0, 0, -1.0])

    g = conv(part)
    parts = []
    chunks = int(np.ceil(len(g) / MAX_TRIS))
    order = np.argsort(g.P.mean(1)[:, 2], kind="stable")
    for i, idx in enumerate(np.array_split(order, chunks)):
        parts.append(((cfg["Name"] + "_%02d" % (i + 1)) if chunks > 1 else cfg["Name"], g.select(np.sort(idx)), 0))
    for name, m, mat in extra:
        parts.append((name, conv(m), mat))
    for k, p in sorted(glb_points.items()):
        parts.append((k, M.box(p, (0.03, 0.03, 0.03)), 1))
        print("  %-17s (%6.3f %6.3f %6.3f)" % (k, *p))
    write_glb(out, parts, [{"Name": att, **images}, {"Name": "Marker", "Factor": (1.0, 0.0, 1.0)},
                           {"Name": "Glass", "Factor": (0.75, 0.85, 0.9)},
                           {"Name": "Reticle", "Factor": (1.0, 0.1, 0.1)}])
    meshes = [m for n, m, mat in parts if mat == 0]
    print("  %d Dreiecke in %d Teilen (max %d) -> %s %.1f MB"
          % (sum(len(m) for m in meshes), len(meshes), max(len(m) for m in meshes), out, os.path.getsize(out) / 1e6))


if __name__ == "__main__":
    build(*sys.argv[1:7])

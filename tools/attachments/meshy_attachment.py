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
from glb_io import M, read_glb, write_glb
import meshy_fbx
import meshy_weapon as W

MAX_TRIS = 19500

# Je Waffe und Aufsatz: turn = Drehung um die Hochachse (180: vorn und hinten tauschen), scale = Faktor auf die
# Meshy-Einheiten des Aufsatzes (Läufe: (längs, quer) – Länge und Dicke getrennt), tilt = Neigung um die Querachse,
# roll = Drehung um die Laufachse (Grad), dann die Lage: at (Verschiebung), rear/axis (Läufe und Mündung), place
# (Kante oder Mitte der Hülle je Achse auf einen Wert: {"y": ("max", -0.04)}).
# hide = Teile der Waffe mit diesem Wort ausblenden (Marker Hide_<Wort>), group = Animationsgruppe (Marker Group_<Gruppe>).
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

ATTACHMENTS.update({
    # Schrotflinte (Pump): Lauf y 0,109 (Radius 0,036, Stirnseite des Gehäuses x -0,04, Mündung -0,949), Röhrenmagazin
    # Achse 0,02 (Radius 0,037, vorn bis -0,866), Vorderschaft x -0,60..-0,17, z ±0,070, Unterkante -0,047.
    # Langer Lauf: gleichmäßig 0,66 (Radius 0,037, 1,26 lang: Mündung 0,35 weiter vorn = 0,73 Studs), hinten am Gehäuse;
    # Perlkorn 0,02 unter der Visierlinie. Altes Korn samt Leuchtpunkt ist mit dem Lauf weg.
    ("Shotgun", "LongBarrel"): {"Kind": "Barrel", "Name": "LongBarrel", "turn": 0, "scale": 0.66, "axis": (0.0, 0.0),
                                "rear": -0.045, "hide": ["FrontDot"]},
    # Kurzer Lauf: Mündung 0,06 vor dem Vorderschaft (-0,65); dafür 0,27 dick und 0,32 lang (leicht gestreckt, sonst
    # wäre er dicker als der Vorderschaft breit). Das Röhrenmagazin vor dem Vorderschaft fällt weg (würde über die
    # Mündung ragen); die Laufhalterung hinten greift ans Röhrenmagazin zwischen Gehäuse und Vorderschaft.
    ("Shotgun", "ShortBarrel"): {"Kind": "Barrel", "Name": "ShortBarrel", "turn": 0, "scale": (0.32, 0.27),
                                 "axis": (0.0125, 0.0), "rear": -0.045, "hide": ["FrontDot", "Tube"]},
    # Mündungsbremse (Würgebohrung): Gewinde hinten (180° gedreht), 0,108 dick; das Gewinde (Radius 0,031) steckt in
    # der Laufwand (innen 0,023, außen 0,036), 0,0225 tief
    ("Shotgun", "MuzzleBrake"): {"Kind": "Muzzle", "Name": "MuzzleBrake", "turn": 180, "diameter": 0.108,
                                 "rear": -0.9265},
    # Vertikalgriff 0,22 hoch (0,46 Studs wie am Sturmgewehr), Klemme unter dem Vorderschaft (Oberkante -0,040, steckt
    # in der Rundung), vor der linken Hand; geht beim Repetieren mit
    ("Shotgun", "VerticalGrip"): {"Kind": "Grip", "Name": "VerticalGrip", "turn": 0, "scale": 0.1156,
                                  "place": {"x": ("center", -0.42), "y": ("max", -0.040), "z": ("center", 0.0)},
                                  "group": "Pump"},
    # Laser (Seitenmontage) 0,20 lang: Klemme (Unterseite des Modells) an der rechten Seite des Vorderschafts
    # (z -0,070), Knöpfe nach außen, vorn bündig mit dem Vorderschaft; geht beim Repetieren mit
    ("Shotgun", "Laser"): {"Kind": "Grip", "Name": "Laser", "turn": 0, "roll": -90, "scale": 0.105,
                           "place": {"x": ("min", -0.615), "y": ("center", 0.03), "z": ("max", -0.068)},
                           "group": "Pump"},
})

ATTACHMENTS.update({
    # Rotpunkt (geschlossenes Rohr): Objektiv vorn (-x, rot beschichtet, 0,14 tief in der Haube bei x -0,81, Mitte
    # y 0,178 z -0,110, Radius 0,27), Okular hinten (x 0,951, Mitte 0,228/-0,105, Radius 0,30); beide Linsen sind
    # undurchsichtig. Linsen herausgeschnitten (24-Eck), innen ein dunkles Rohr dazwischen, Glas hinter dem Objektiv und
    # ein kleiner Leuchtpunkt in dessen Mitte. Klemme (Schienenkanal: Decke y -0,68, Backen bis -0,81) auf der flachen
    # Oberseite des Gehäuses (y 0,147, x -0,04..0,15), Backen greifen seitlich; Rohr hinten bei 0,19 (vor der Kimme).
    ("Shotgun", "HoloSight"): {"Kind": "Optic", "Name": "RedDot", "turn": 0, "scale": 0.11, "bottom": 0.147,
                               "bottom_ref": -0.68, "rear": 0.19,
                               "tube": {"front": (-0.81, 0.178, -0.110, 0.27), "rear": (0.951, 0.228, -0.105, 0.30),
                                        "sides": 24, "dark": (0.0, 0.587, -0.11)}},
})

# Waffen, die nicht mit meshy_weapon.py gebaut sind (Maße wie in deren Skript): Präzisionsgewehr aus sniper_v1.py
# (Quelle art/sources/Meshy_AI_roblox_magnum_sniper_1012115921_texture.glb)
OTHER_WEAPONS = {
    "DMR": {"Length": 4.575, "Points": {"Point_Grip": (0.495, -0.045, 0.0), "Point_Muzzle": (None, 0.0949, 0.0),
                                        "Point_LeftHand": (-0.03, 0.06, 0.0)}},
}

ATTACHMENTS.update({
    # Präzisionsgewehr: Lauf y 0,0949 (Radius 0,0257) vom Vorderschaft (Stirnseite -0,246) bis -0,775, davor die
    # Mündungsbremse (bis -0,952, Radius 0,042). Magazin x 0,227..0,356, z ±0,0156, unten -0,111.
    # Langer Lauf: Radius 0,026 (quer 0,385), Mündung 0,30 weiter vorn als die Bremse (-1,25; längs 0,525,
    # Streckung 1,36), Laufmutter hinten am Vorderschaft
    ("DMR", "LongBarrel"): {"Kind": "Barrel", "Name": "LongBarrel", "turn": 0, "scale": (0.525, 0.385),
                            "axis": (0.0, 0.0), "rear": -0.25},
    # Schwerer Lauf: quer 0,30 (Rippen Radius 0,04, gut 1,5-mal so dick), längs 0,42 (Streckung 1,4, sonst wirkt er
    # wie ein Klotz), Mündung 0,10 weiter vorn als die Bremse (-1,05)
    ("DMR", "HeavyBarrel"): {"Kind": "Barrel", "Name": "HeavyBarrel", "turn": 0, "scale": (0.42, 0.30),
                             "axis": (0.013, 0.0), "rear": -0.25},
    # Schalldämpfer: ersetzt die Mündungsbremse (Hide_Brake), Gewinde hinten (180° gedreht, Radius 0,025) steckt
    # 0,024 tief im Laufende (-0,775); 0,088 dick
    ("DMR", "Suppressor"): {"Kind": "Muzzle", "Name": "Suppressor", "turn": 180, "diameter": 0.088,
                            "rear": -0.751, "hide": ["Brake"]},
    # Magazine: Tiefe wie das eingebaute (0,129), Körper oben 0,04 im Schacht, mittig über x 0,2915
    # Schnellmagazin mit Zugschlaufe: 0,137 (Körper 0,21 hoch, 0,03 länger als das eingebaute)
    ("DMR", "FastMag"): {"Kind": "Magazine", "Name": "Magazine_Fast", "turn": 0, "scale": 0.137,
                         "at": (0.2915, 0.04 - 0.73 * 0.137, 0.0)},
    # Erweitertes Magazin: 0,193 (0,044 breit, ragt 0,17 tiefer heraus)
    ("DMR", "ExtendedMag"): {"Kind": "Magazine", "Name": "Magazine_Ext", "turn": 0, "scale": 0.193,
                             "at": (0.2915 + 0.0035 * 0.193, 0.04 - 0.73 * 0.193, 0.0)},
})

# Achse des Laufs vorn (Messung am Meshy-Modell der Waffe): Mitte y/z, Radius
MUZZLE_AXIS = {"SMG": (0.2503, 0.0002, 0.046), "Shotgun": (0.109, 0.0, 0.036), "DMR": (0.0949, 0.0, 0.0257)}


def unzip(src):
    if src.endswith(".zip"):
        tmp = tempfile.mkdtemp()
        zipfile.ZipFile(src).extractall(tmp)
        return tmp
    return src


def rotation(turn, tilt=0.0, roll=0.0):
    t, a, r = np.radians(turn), np.radians(tilt), np.radians(roll)
    ry = np.array([[np.cos(t), 0, np.sin(t)], [0, 1, 0], [-np.sin(t), 0, np.cos(t)]])
    rz = np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1]])
    rx = np.array([[1, 0, 0], [0, np.cos(r), -np.sin(r)], [0, np.sin(r), np.cos(r)]])
    return rz @ ry @ rx


def _ring(x, yc, zc, r, n):
    """Ecken eines n-Ecks mit Inkreis r (Kanten berühren den Kreis) in der Ebene x."""
    a = np.arange(n) * 2 * np.pi / n
    rr = r / np.cos(np.pi / n)
    return [np.array([x, yc + rr * np.cos(t + np.pi / n), zc + rr * np.sin(t + np.pi / n)]) for t in a]


def open_tube(mesh, tube, images):
    """Geschlossenes Visierrohr durchsichtig machen: Linsen vorn und hinten als n-Eck herausschneiden, dazwischen eine
    Innenwand (Kegelstumpf, Flächen nach innen, dunkle Farbe der Rohr-Oberseite). Gibt (Mesh, Glas) zurück."""
    n = tube["sides"]
    uv = dark_uv(mesh, tube["dark"])
    for (x, yc, zc, r), sign in ((tube["front"], -1), (tube["rear"], 1)):
        planes = [M.plane((-1, 0, 0), (x - 0.012, 0, 0)), M.plane((1, 0, 0), (x + 0.012, 0, 0))]
        for t in np.arange(n) * 2 * np.pi / n:
            d = np.array([0, np.cos(t), np.sin(t)])
            planes.append(M.plane(d, np.array([x, yc, zc]) + r * d))
        mesh, cut = M.split(mesh, planes)
        print("  Linse bei x %.3f: %d Dreiecke entfernt" % (x, len(cut)))
    # rote Beschichtung am Rand der Öffnung vorn (Rest der Linse, Fase der Haube) dunkel färben
    import io
    from PIL import Image
    tex = np.asarray(Image.open(io.BytesIO(images["Color"][0])).convert("RGB")).astype(float)
    h, w, _ = tex.shape
    x, yc, zc, r = tube["front"]
    c = mesh.P.mean(1)
    near = (c[:, 0] > x - 0.16) & (c[:, 0] < x + 0.03) & (np.hypot(c[:, 1] - yc, c[:, 2] - zc) < r + 0.08)
    uvm = mesh.UV.mean(1)
    col = tex[np.clip(((1 - uvm[:, 1]) * h).astype(int), 0, h - 1), np.clip((uvm[:, 0] * w).astype(int), 0, w - 1)]
    red = near & (col[:, 0] > 1.5 * col[:, 1]) & (col[:, 0] > 70)
    UV = mesh.UV.copy()
    UV[red] = uv
    mesh = M.Mesh(mesh.P, UV, mesh.N)
    print("  rote Flächen vorn dunkel gefärbt: %d" % red.sum())
    f = _ring(*tube["front"], n)
    b = _ring(*tube["rear"], n)
    walls = []
    ax = np.array([tube["front"][0], tube["front"][1], tube["front"][2]])
    for i in range(n):
        j = (i + 1) % n
        mid = (f[i] + f[j] + b[i] + b[j]) / 4
        centre = ax + np.array([mid[0] - ax[0], 0, 0])
        inward = centre - mid
        inward[0] = 0
        walls.append(M.quad(f[i], f[j], b[j], b[i], inward, uv))
    x, yc, zc, r = tube["front"]
    disc = [p + np.array([0.01, 0, 0]) for p in _ring(x, yc, zc, r + 0.01, n)]
    glass = M.Mesh.concat(M.cap(disc, (1, 0, 0), (0.5, 0.5)), M.cap(disc[::-1], (-1, 0, 0), (0.5, 0.5)))
    return M.Mesh.concat(mesh, *walls), glass


def dark_uv(mesh, point):
    c = mesh.P.mean(1)
    return tuple(mesh.UV[np.argmin(np.linalg.norm(c - np.asarray(point), axis=1))].mean(0))


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
    wcfg = W.WEAPONS.get(weapon) or OTHER_WEAPONS[weapon]
    mesh, images = meshy_fbx.load(unzip(src))
    lo, hi = mesh.bounds()
    print("%s %s: Meshy %d Dreiecke, %s" % (weapon, att, len(mesh), np.round(hi - lo, 3)))
    kind = cfg["Kind"]
    tube_glass = None
    if "tube" in cfg:
        mesh, tube_glass = open_tube(mesh, cfg["tube"], images)
    if kind == "Muzzle":
        cfg = {**cfg, "scale": cfg["diameter"] / max(hi[1] - lo[1], hi[2] - lo[2])}
    s = cfg["scale"]
    S = np.array([s[0], s[1], s[1]], float) if isinstance(s, tuple) else np.array([s, s, s], float)
    s = S[1]
    Rm = rotation(cfg["turn"], cfg.get("tilt", 0.0), cfg.get("roll", 0.0))
    P = (mesh.P * S) @ Rm.T
    N = (mesh.N / S) @ Rm.T
    N /= np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-12)
    plo, phi = P.reshape(-1, 3).min(0), P.reshape(-1, 3).max(0)
    extra, points = [], {}
    if kind == "Magazine":
        P = P + np.asarray(cfg["at"])
    elif kind == "Barrel":
        y0, z0, radius = MUZZLE_AXIS[weapon]
        ay, az = cfg["axis"]
        P = P + np.array([cfg["rear"] - phi[0], y0 - ay * S[1], z0 - az * S[2]])
        print("  Lauf: Länge %.3f, Streckung %.2f (eingebauter Radius %.3f)" % (phi[0] - plo[0], S[0] / S[1], radius))
    elif kind == "Grip":
        shift = np.zeros(3)
        for i, axis in enumerate("xyz"):
            if axis in cfg["place"]:
                how, v = cfg["place"][axis]
                ref = {"min": plo[i], "max": phi[i], "center": (plo[i] + phi[i]) / 2}[how]
                shift[i] = v - ref
        P = P + shift
    elif kind == "Muzzle":
        y0, z0, radius = MUZZLE_AXIS[weapon]
        P = P + np.array([cfg["rear"] - phi[0], y0 - (plo[1] + phi[1]) / 2, z0 - (plo[2] + phi[2]) / 2])
        print("  Durchmesser %.3f (Lauf %.3f), Länge %.3f" % (cfg["diameter"], 2 * radius, phi[0] - plo[0]))
    elif kind == "Optic" and "tube" in cfg:
        x, yc, zc, r = cfg["tube"]["front"]
        centre = np.array([x + 0.01, yc, zc]) * s @ Rm.T
        shift = np.array([cfg["rear"] - phi[0], cfg["bottom"] - cfg["bottom_ref"] * s, -centre[2]])
        P = P + shift
        lens = centre + shift
        gl = M.Mesh(((tube_glass.P * S) @ Rm.T) + shift, tube_glass.UV, tube_glass.N @ Rm.T)
        extra += [("Glass", gl, 2), ("Neon_Reticle", M.box(lens, (0.004, 0.004, 0.004)), 3)]
        points["Point_SightFront"] = lens
        points["Point_SightRear"] = np.array([cfg["rear"], lens[1], lens[2]])
        points["Point_Mount"] = np.array(wcfg["Points"]["Point_Optic"], float)
        print("  Visierlinie y %.4f (Kimme/Korn %.3f), Öffnung Radius %.4f, Glas bei x %.3f"
              % (lens[1], wcfg["Points"]["Point_SightRear"][1], r * s, lens[0]))
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
    gun = read_glb(weapon_src)[0] if weapon_src.endswith(".glb") else meshy_fbx.load(unzip(weapon_src))[0]
    glo, ghi = gun.bounds()
    ws = wcfg["Length"] / (ghi[0] - glo[0])
    R = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)
    origin = np.array(wcfg["Points"]["Point_Grip"], float)
    to_glb = lambda p: (np.asarray(p, float) - origin) @ R.T * ws  # noqa: E731
    conv = lambda m: M.Mesh(to_glb(m.P), m.UV, m.N @ R.T)  # noqa: E731

    if kind in ("Muzzle", "Barrel"):
        mz = wcfg["Points"]["Point_Muzzle"]
        mount = np.array([glo[0] if mz[0] is None else mz[0], mz[1], mz[2]])
        points["Point_Mount"] = mount
        points["Point_Muzzle"] = np.array([alo[0], mount[1], mount[2]])
        if kind == "Barrel":
            points["Point_Front"] = mount + np.array([-0.3, 0, 0])
            print("  neue Mündung %.3f (eingebaut %.3f)" % (alo[0], mount[0]))
    elif kind == "Grip":
        lh = np.array(wcfg["Points"]["Point_LeftHand"], float)
        points["Point_Mount"] = np.array([lh[0], lh[1], 0.0])
        points["Point_Front"] = points["Point_Mount"] + np.array([-0.3, 0, 0])
    for word in cfg.get("hide", []):
        points["Hide_" + word] = points["Point_Mount"] + np.array([0, -0.02, 0])
    if cfg.get("group"):
        points["Group_" + cfg["group"]] = points["Point_Mount"] + np.array([0, 0.02, 0])
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

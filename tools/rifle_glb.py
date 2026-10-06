#!/usr/bin/env python3
"""Bereitet das Sturmgewehr (AR-556 aus Meshy) für den Studio-Import vor:
art/sources/Meshy_AI_roblox_ar556_*.fbx + Meshy_AI_roblox_ar_mag_*.fbx -> art/sources/Rifle.glb

Fertig nach docs/waffen-modelle.md:
  * Skin_Body: das Gewehr. Das eingebaute Magazin ist herausgeschnitten (der Schacht unten geschlossen), das Fenster
    des Holo-Visiers ist offen (Tunnel mit dunklen Innenwänden, sonst sähe man beim Zielen gegen eine Wand), das
    vordere Klappkorn ist umgelegt (es stand mitten im Sichtfeld).
  * Magazine: das separate Magazin, so groß und schräg wie das eingebaute und an seiner Stelle.
  * Bolt: der Spannhebel (T-Griff hinten oben), herausgetrennt – die Nachlade-Animation zieht ihn zurück.
  * Glass_Window: Scheibe im Visierfenster.
  * Marker Point_* und Pivot_* (kleine Würfel), Länge 4,13 Studs wie die Quader-Waffe, Lauf nach -Z, Ursprung im Griff.
Texturen: Farbe und Metall/Rauheit (glTF), auf 1024 x 1024 verkleinert, im GLB. Zusätzlich einzeln in
art/sources/Rifle_Texturen/ (falls man sie in Studio von Hand in eine SurfaceAppearance setzen will).

    python3 tools/rifle_glb.py            (dauert ca. 20 s)
Dann in Studio: Import 3D > Rifle.glb (Teile NICHT zusammenführen), Modell nach ReplicatedStorage > Assets > Weapons
ziehen, "Rifle" nennen.
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import fbx_read as F  # noqa: E402
import mesh_ops as M  # noqa: E402

SRC = os.path.join(ROOT, "art", "sources")
GUN = "Meshy_AI_roblox_ar556_lowpoly_1006184328_texture"
MAG = "Meshy_AI_roblox_ar_mag_lowpoly_1006184342_texture"
OUT = os.path.join(SRC, "Rifle.glb")
TEX_DIR = os.path.join(SRC, "Rifle_Texturen")
LENGTH = 4.13   # Studs, so lang wie die Quader-Waffe (blockoutLength in GunModels)
TEX = 1024      # Roblox nimmt höchstens 1024 x 1024

# Alle Maße unten in Meshy-Einheiten (Gewehr 190 lang): Lauf nach -x, oben +y, rechte Seite -z.
BORE = (15.5, 0.45)                       # Laufachse (y, z)
MAG_AXIS = 0.2236                         # eingebautes Magazin: Mitte x = MAG_AXIS * y + MAG_AXIS_X (12,6° nach vorn)
MAG_AXIS_X = 0.583
MAG_CUT = -0.4                            # Schnitt knapp unter der Schachtkante (Abstand entlang der Magazinachse)
MAG_X = (-22.0, 7.8)                      # dort liegt das Magazin (dahinter Abzugsbügel, davor Vordergriff)
BOLT_REGION = (32.85, 37.5, 22.25)        # Spannhebel: x von, x bis, ab Höhe y
WINDOW = {"x": (-4.6, 9.6), "y": (32.0, 37.5), "z": (-3.0, 5.0)}  # Fenster des Holo-Visiers (Tunnel)
FRONT_SIGHT = {"x": (-77.0, -66.0), "y": 24.6, "keep": 0.3}       # Klappkorn: über y stauchen (umgelegt)
POINTS = {
    "Point_Grip": (35.0, -15.0, 0.5),     # Mitte des Pistolengriffs (rechte Hand)
    "Point_Muzzle": (None, 15.5, 0.45),    # x = Mündung (vorderste Stelle)
    "Point_Eject": (10.0, 15.5, -5.7),    # Auswurf rechts am Gehäuse
    "Point_LeftHand": (-43.1, 1.5, 0.5),  # Vordergriff
    "Point_LeftHandTP": (-22.0, 7.5, 0.5),  # Third-Person: Handschutz hinten unten (kürzere Arme)
    "Point_Stock": (None, 3.85, 0.55),    # x = Schaftende
}


def load(name):
    (entry,), _settings = F.load_meshes(os.path.join(SRC, name + ".fbx"))
    return M.Mesh.from_fbx(entry)


def texture(name, suffix, mode="RGB"):
    Image.MAX_IMAGE_PIXELS = None
    return Image.open(os.path.join(SRC, name + suffix + ".png")).convert(mode).resize((TEX, TEX), Image.LANCZOS)


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def cut_and_cap(mesh, region, cut_planes, uv, keep_inside_caps=True):
    """Bereich herausschneiden; Schnittflächen auf den Ebenen cut_planes (Indizes in region) schließen.
    Gibt (Rest mit Deckel, herausgeschnittener Teil mit Deckel) zurück."""
    outside, inside = M.split(mesh, region)
    rest_cap, open_ends = M.cap_cut(mesh, region, cut_planes, -1, uv)
    if open_ends:
        print("  Achtung: Schnittkante nicht ganz geschlossen (%d offene Stellen)" % open_ends)
    outside = M.Mesh.concat(outside, rest_cap)
    if keep_inside_caps:
        inside = M.Mesh.concat(inside, M.cap_cut(mesh, region, cut_planes, 1, uv)[0])
    return outside, inside


def main():
    gun, mag = load(GUN), load(MAG)
    print("Gewehr %d Dreiecke, Magazin %d Dreiecke" % (len(gun), len(mag)))
    lo, hi = gun.bounds()
    muzzle_x, stock_x = lo[0], hi[0]

    # dunkle Stellen der Textur für Deckel und Innenwände: Fenster des Visiers, Unterseite der Schachtkante
    dark_window = M.uv_at(gun, (40, 34.75, 1.0), (-1, 0, 0))
    up = unit((MAG_AXIS, 1, 0))                       # Magazinachse nach oben (oben liegt weiter hinten)
    dark_mag = M.uv_at(gun, (-1.0, -15, 5.8), (0, 1, 0))  # Unterseite des Kragens (neben dem Magazinkörper)

    # 1) Eingebautes Magazin heraus, Schacht unten schließen. Schnitt senkrecht zur Magazinachse, knapp unter dem
    #    breiten Kragen der Schachtkante (dort wird der Querschnitt schmal: Magazinkörper)
    band = np.array([MAG_AXIS_X + MAG_AXIS * -3.6, -3.6, 0])  # Mitte der Schachtkante
    sides = [M.plane((-1, 0, 0), (MAG_X[0], 0, 0)), M.plane((1, 0, 0), (MAG_X[1], 0, 0))]
    offsets = np.arange(3.0, -6.01, -0.25)                     # entlang der Achse, + = nach oben
    widths = []
    for a in offsets:
        segs = M.section(gun, M.plane(up, band + up * a), sides)
        zs = [p[2] for seg in segs for p in seg]
        widths.append(max(zs) - min(zs) if zs else 0)
    body_width = widths[-1]
    collar = [a for a, w in zip(offsets, widths) if w > body_width + 1.0]
    collar_end = min(collar)
    cut_point = band + up * (collar_end + MAG_CUT)
    mag_region = [M.plane(up, cut_point)] + sides   # drinnen (d <= 0) = unter dem Schnitt
    gun, built_in = cut_and_cap(gun, mag_region, [0], dark_mag, keep_inside_caps=False)
    print("Magazin herausgeschnitten: Kragen endet %.2f unter der Kantenmitte, %d Dreiecke entfernt"
          % (-collar_end, len(built_in)))

    # 2) Spannhebel als eigenes Teil
    x0, x1, y0 = BOLT_REGION
    bolt_region = [M.plane((0, -1, 0), (0, y0, 0)), M.plane((-1, 0, 0), (x0, 0, 0)), M.plane((1, 0, 0), (x1, 0, 0))]
    gun, bolt = cut_and_cap(gun, bolt_region, [0, 1], dark_mag)
    print("Spannhebel: %d Dreiecke" % len(bolt))

    # 3) Fenster des Holo-Visiers öffnen: Tunnel (Box) heraus, Innenwände einsetzen
    (wx0, wx1), (wy0, wy1), (wz0, wz1) = WINDOW["x"], WINDOW["y"], WINDOW["z"]
    window_region = [M.plane((-1, 0, 0), (wx0, 0, 0)), M.plane((1, 0, 0), (wx1, 0, 0)), M.plane((0, -1, 0), (0, wy0, 0)),
                     M.plane((0, 1, 0), (0, wy1, 0)), M.plane((0, 0, -1), (0, 0, wz0)), M.plane((0, 0, 1), (0, 0, wz1))]
    original = gun
    gun, _ = M.split(gun, window_region)

    def faces_at(y, z):
        """Vorder- und Hinterfläche des Visiers entlang x an (y, z)."""
        t = M.ray_hits(original, (wx1 + 20, y, z), (-1, 0, 0))
        xs = (wx1 + 20) - t
        xs = xs[(xs > wx0 - 1) & (xs < wx1 + 1)]
        return (xs.min(), xs.max()) if len(xs) else (wx0, wx1)
    walls = []
    steps = 8
    edges = [  # (Punkt auf der Kante als Funktion von s in 0..1, Normale ins Fenster)
        (lambda s: (wy1, wz0 + s * (wz1 - wz0)), (0, -1, 0)),   # oben
        (lambda s: (wy0, wz0 + s * (wz1 - wz0)), (0, 1, 0)),    # unten
        (lambda s: (wy0 + s * (wy1 - wy0), wz0), (0, 0, 1)),    # rechts
        (lambda s: (wy0 + s * (wy1 - wy0), wz1), (0, 0, -1)),   # links
    ]
    for edge, normal in edges:
        for k in range(steps):
            (ya, za), (yb, zb) = edge(k / steps), edge((k + 1) / steps)
            # knapp außerhalb des Fensters messen: dort stehen Vorder- und Rückseite noch (der Rahmen), so reicht die
            # Innenwand genau von Fläche zu Fläche
            out = 0.15
            fa = faces_at(ya - normal[1] * out, za - normal[2] * out)
            fb = faces_at(yb - normal[1] * out, zb - normal[2] * out)
            walls.append(M.quad((fa[0], ya, za), (fa[1], ya, za), (fb[1], yb, zb), (fb[0], yb, zb), normal, dark_window))
    gun = M.Mesh.concat(gun, *walls)
    front_x, rear_x = faces_at(wy1 + 0.15, (wz0 + wz1) / 2)   # Rahmen oben in der Mitte: Fensterebenen
    glass_x = front_x + 0.8
    glass = M.quad((glass_x, wy0, wz0), (glass_x, wy0, wz1), (glass_x, wy1, wz1), (glass_x, wy1, wz0), (1, 0, 0), (0.5, 0.5))
    print("Visierfenster offen: vorn x=%.2f, hinten x=%.2f" % (front_x, rear_x))

    # 4) Klappkorn umlegen (stauchen)
    fx0, fx1 = FRONT_SIGHT["x"]
    base, keep = FRONT_SIGHT["y"], FRONT_SIGHT["keep"]
    P = gun.P.copy()
    sel = (P[..., 0] >= fx0) & (P[..., 0] <= fx1) & (P[..., 1] > base)
    P[..., 1] = np.where(sel, base + (P[..., 1] - base) * keep, P[..., 1])
    N = gun.N.copy()
    N[..., 1] = np.where(sel, N[..., 1] / keep, N[..., 1])
    N /= np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-12)
    gun = M.Mesh(P, gun.UV, N)

    # 5) Separates Magazin einpassen: Achse, Unterkante, Tiefe und Mitte wie das eingebaute
    forward = unit((-1, MAG_AXIS, 0))                 # senkrecht zur Achse, Richtung Mündung
    side = np.cross(forward, up)
    bi = built_in.P.reshape(-1, 3)
    bottom = (bi @ up).min()
    along = bi @ up
    middle = bi[(along > bottom + 8) & (along < bottom + 20)]
    depth_built = (middle @ forward).max() - (middle @ forward).min()
    centre_built = ((middle @ forward).max() + (middle @ forward).min()) / 2
    z_built = (bi[:, 2].max() + bi[:, 2].min()) / 2
    mp = mag.P.reshape(-1, 3)
    mid_mag = mp[(mp[:, 1] > -60) & (mp[:, 1] < 60)]
    scale = depth_built / (mid_mag[:, 0].max() - mid_mag[:, 0].min())
    # Magazin-Achsen: +x vorn (Patronenspitze), +y oben, +z Breite -> forward, up, side
    R = np.column_stack([forward, up, side])
    placed = mag.transformed(R, scale)
    pp = placed.P.reshape(-1, 3)
    shift = up * (bottom - (pp @ up).min()) + forward * (centre_built - ((pp @ forward).max() + (pp @ forward).min()) / 2)
    shift[2] += z_built - (pp[:, 2].max() + pp[:, 2].min()) / 2
    placed = M.Mesh(placed.P + shift, placed.UV, placed.N)
    print("Magazin: Maßstab %.4f, Tiefe %.2f, Höhe %.2f" % (scale, depth_built, 190.2 * scale))

    # 6) Marker (Quelle) und Umrechnung nach Roblox: x = -z, y = y, z = x (Lauf nach -Z), Studs, Ursprung im Griff
    points = {}
    for name, (x, y, z) in POINTS.items():
        if x is None:
            x = muzzle_x if name == "Point_Muzzle" else stock_x
        points[name] = np.array([x, y, z], float)
    window_mid = ((wy0 + wy1) / 2, (wz0 + wz1) / 2)
    points["Point_SightRear"] = np.array([rear_x, *window_mid])
    points["Point_SightFront"] = np.array([front_x, *window_mid])
    mlo, mhi = placed.bounds()
    points["Pivot_Magazine"] = (mlo + mhi) / 2
    blo, bhi = bolt.bounds()
    points["Pivot_Bolt"] = (blo + bhi) / 2
    s = LENGTH / (stock_x - muzzle_x)
    to_roblox = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)
    origin = points["Point_Grip"]

    def convert(mesh):
        return M.Mesh((mesh.P - origin) @ to_roblox.T * s, mesh.UV, mesh.N @ to_roblox.T)
    parts_src = {"Skin_Body": gun, "Magazine": placed, "Bolt": bolt, "Glass_Window": glass}
    parts = {name: convert(mesh) for name, mesh in parts_src.items()}
    markers = {name: ((p - origin) @ to_roblox.T * s) for name, p in points.items()}

    # 7) Texturen
    os.makedirs(TEX_DIR, exist_ok=True)
    images = {}
    for key, name in (("Body", GUN), ("Magazine", MAG)):
        color = texture(name, "")
        metal_rough = texture(name, "_metallic_roughness")
        metal = texture(name, "_metallic", "L")
        rough = texture(name, "_roughness", "L")
        color.save(os.path.join(TEX_DIR, "%s_Color.png" % key), optimize=True)
        metal.save(os.path.join(TEX_DIR, "%s_Metalness.png" % key), optimize=True)
        rough.save(os.path.join(TEX_DIR, "%s_Roughness.png" % key), optimize=True)
        images[key] = (M.png_bytes(color), M.png_bytes(metal_rough))
    materials = [
        {"Name": "Body", "Color": images["Body"][0], "MetalRough": images["Body"][1]},
        {"Name": "Magazine", "Color": images["Magazine"][0], "MetalRough": images["Magazine"][1]},
        {"Name": "Glass", "Color": M.solid_png((0.55, 0.62, 0.66)), "Factor": (0.55, 0.62, 0.66), "Roughness": 0.1},
        {"Name": "Marker", "Color": M.solid_png((1.0, 0.0, 1.0)), "Factor": (1.0, 0.0, 1.0)},
    ]
    material_of = {"Skin_Body": 0, "Bolt": 0, "Magazine": 1, "Glass_Window": 2}
    glb_parts = [(name, mesh, material_of[name]) for name, mesh in parts.items()]
    for name, p in sorted(markers.items()):
        size = 0.06 if name.startswith("Pivot") else 0.04
        glb_parts.append((name, M.box(p, (size, size, size)), 3))
    M.write_glb(OUT, glb_parts, materials, generator="tools/rifle_glb.py",
                extras={"source": "Meshy AI (AR-556 + Magazin), vorbereitet nach docs/waffen-modelle.md"})

    total = sum(len(mesh) for mesh in parts.values())
    lo2 = np.min([m.bounds()[0] for m in parts.values()], axis=0)
    hi2 = np.max([m.bounds()[1] for m in parts.values()], axis=0)
    print("Teile: " + ", ".join("%s %d" % (name, len(mesh)) for name, mesh in parts.items()) + " Dreiecke (gesamt %d)" % total)
    print("Länge %.2f Studs, Visierlinie %.3f über dem Griff" % (hi2[2] - lo2[2], markers["Point_SightRear"][1]))
    for name, p in sorted(markers.items()):
        print("  %-17s (%6.3f %6.3f %6.3f)" % (name, *p))
    print("-> %s (%.1f MB)" % (os.path.relpath(OUT, ROOT), os.path.getsize(OUT) / 1e6))
    return parts, markers


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Bereitet das MP7-Modell für den Studio-Import vor: art/sources/mp7a1.glb -> art/sources/SMG.glb.

Die Datei ist fertig nach docs/waffen-modelle.md: Teile benannt (Skin_Receiver, Magazine, Bolt, Body, Neon_FrontDot),
Schalldämpfer, lose Patronen und das zweite Magazin entfernt, Größe in Studs (2,38 lang), Lauf nach -Z, Marker
(Point_*) als kleine Würfel an den Stellen aus tools/mp7_model.py.

Dann in Studio: Import 3D > SMG.glb (Teile NICHT zusammenführen), Modell nach ReplicatedStorage > Assets > Weapons
ziehen, "SMG" nennen.
    python3 tools/mp7_glb.py
"""
import json, math, os, struct, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import glb_read as G  # noqa: E402
import mp7_model as M  # noqa: E402

SRC = os.path.join(ROOT, "art", "sources", "mp7a1.glb")
OUT = os.path.join(ROOT, "art", "sources", "SMG.glb")
S = M.SCALE
# GLB-Gruppe -> Teilname im Spiel (nicht genannte Gruppen fallen weg: Patronen, zweites Magazin, Schalldämpfer)
PART_OF = {
    "mp7a1 receiver_6": "Skin_Receiver", "mp7a1 stock_10": "Skin_Stock",
    "4630 mp7 30rnd empty mag_2": "Magazine",
    "mp7a1 bolt carrier_7": "Bolt", "mp7a1 charging handle_8": "Bolt",
    "mp7a1 front iron sight_14": "Body", "mp7a1 reaar iron sight_15": "Body", "mp7a1 7in barrel_4": "Body",
    "mp7a1 flash hider_5": "Body", "mp7a1 integrated folding foregrip_9": "Body", "mp7a1 selector_11": "Body",
    "mp7a1 bolt release_12": "Body", "mp7a1 trigga_13": "Body",
}


def rb(p):  # GLB-Welt (x vorn, y oben, z rechts) -> Roblox, Studs
    return M.to_roblox(p)


def tri_arrays(j, b):
    """{Teil: (positions, normals, material)} je Teilname, in Roblox-Studs; Normalen mit gleicher Drehung."""
    out = {}
    def walk(n, m, top):
        nd = j["nodes"][n]; m = G.mmul(m, nd.get("matrix", G.ident()))
        if "mesh" in nd and top in PART_OF:
            for prim in j["meshes"][nd["mesh"]]["primitives"]:
                pos = G.positions(j, b, prim["attributes"]["POSITION"])
                nor = G.positions(j, b, prim["attributes"]["NORMAL"])
                P, N, mat = out.setdefault(PART_OF[top], ([], [], set()))
                mat.add(prim["material"])
                for v, n3 in zip(pos, nor):
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


def cube(center, size, color):
    h = size / 2; P = []; N = []
    faces = [((0, 0, 1), (1, 0, 0), (0, 1, 0)), ((0, 0, -1), (-1, 0, 0), (0, 1, 0)), ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
             ((-1, 0, 0), (0, 0, 1), (0, 1, 0)), ((0, 1, 0), (1, 0, 0), (0, 0, -1)), ((0, -1, 0), (1, 0, 0), (0, 0, 1))]
    for n, u, v in faces:
        c = [tuple(center[i] + h * (n[i] + su * u[i] + sv * v[i]) for i in range(3)) for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        for k in (0, 1, 2, 0, 2, 3):
            P.append(c[k]); N.append(n)
    return P, N


def write(parts, path):
    # Materialien: Farbe je Teil (Skin_/Magazine/Bolt/Body dunkel bis stahl) aus dem GLB
    mats, meshes, nodes, accessors, views, blob = [], [], [], [], [], bytearray()
    def add(data, comp_fmt, typ, ctype, count, minmax=None, target=34962):
        while len(blob) % 4: blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        a = {"bufferView": len(views) - 1, "componentType": ctype, "count": count, "type": typ}
        if minmax: a["min"], a["max"] = minmax
        accessors.append(a); return len(accessors) - 1
    for name, (P, N, color) in parts.items():
        pa = add(b"".join(struct.pack("<3f", *p) for p in P), "f", "VEC3", 5126, len(P),
                 ([min(p[i] for p in P) for i in range(3)], [max(p[i] for p in P) for i in range(3)]))
        na = add(b"".join(struct.pack("<3f", *n) for n in N), "f", "VEC3", 5126, len(N))
        mats.append({"name": name, "doubleSided": True, "pbrMetallicRoughness": {
            "baseColorFactor": [*color, 1.0], "metallicFactor": 0.0 if name.startswith(("Skin", "Magazine")) else 0.4, "roughnessFactor": 0.6}})
        meshes.append({"name": name, "primitives": [{"attributes": {"POSITION": pa, "NORMAL": na}, "material": len(mats) - 1}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})
    doc = {"asset": {"version": "2.0", "generator": "tools/mp7_glb.py",
                     "extras": {"license": "CC-BY-4.0", "author": "D_U (https://sketchfab.com/DU1701)"}},
           "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": meshes,
           "materials": mats, "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(blob)}]}
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    while len(blob) % 4: blob.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob))


def main():
    j, b = G.load(SRC)
    arr = tri_arrays(j, b)
    colors = {"Skin_Receiver": (0.15, 0.15, 0.16), "Skin_Stock": (0.15, 0.15, 0.16), "Magazine": (0.11, 0.11, 0.12),
              "Bolt": (0.11, 0.11, 0.12), "Body": (0.35, 0.35, 0.38)}
    parts = {k: (P, N, colors[k]) for k, (P, N, _) in arr.items()}
    # Leuchtpunkt auf dem Korn
    p, n = cube(rb((0.95, 0.935, 0)), 0.02, None)
    parts["Neon_FrontDot"] = (p, n, (1.0, 0.75, 0.25))
    for name, pt in M.POINTS:
        p, n = cube(rb(pt), 0.05, None)
        parts[name] = (p, n, (1.0, 0.0, 1.0))
    write(parts, OUT)
    allp = [v for k, (P, _, _) in parts.items() if not k.startswith(("Point", "Pivot")) for v in P]
    zs = [v[2] for v in allp]
    print("SMG.glb: %d Teile, Länge %.2f Studs -> art/sources/SMG.glb" % (len(parts), max(zs) - min(zs)))


if __name__ == "__main__":
    main()

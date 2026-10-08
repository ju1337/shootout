import json, os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # tools/mesh_ops.py
import mesh_ops as M
SRC, OUT = sys.argv[1], sys.argv[2]
LENGTH = 4.13
MAX_TRIS = 19500
ZC = 0.01
POINTS = {
    "Point_Grip": (0.30, -0.07, ZC),
    "Point_SightRear": (0.28, 0.268, ZC),
    "Point_SightFront": (-0.733, 0.283, ZC),
    "Point_Muzzle": (None, 0.172, ZC),
    "Point_Eject": (0.25, 0.20, -0.035),
    "Point_LeftHand": (-0.43, 0.12, ZC),
    "Point_LeftHandTP": (-0.22, 0.12, ZC),
    "Point_Stock": (None, 0.115, ZC),
}
MAG_X, MAG_CUT_Y = (-0.15, 0.086), 0.0
def read_glb(path):
    data = open(path, "rb").read()
    jl = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jl])
    blob = data[20 + jl + 8:]

    def accessor(i):
        a = doc["accessors"][i]
        v = doc["bufferViews"][a["bufferView"]]
        n = {"VEC3": 3, "VEC2": 2, "SCALAR": 1}[a["type"]]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a["componentType"]]
        return np.frombuffer(blob, dt, a["count"] * n, v.get("byteOffset", 0) + a.get("byteOffset", 0)).reshape(a["count"], n)

    def image(i):
        im = doc["images"][i]
        v = doc["bufferViews"][im["bufferView"]]
        return blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]], im["mimeType"]

    prim = doc["meshes"][0]["primitives"][0]
    idx = accessor(prim["indices"]).reshape(-1).astype(np.int64)
    pos = accessor(prim["attributes"]["POSITION"]).astype(np.float64)[idx].reshape(-1, 3, 3)
    nor = accessor(prim["attributes"]["NORMAL"]).astype(np.float64)[idx].reshape(-1, 3, 3)
    uv = accessor(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)[idx].reshape(-1, 3, 2)
    uv[..., 1] = 1 - uv[..., 1]                         # mesh_ops rechnet mit v nach oben
    mat = doc["materials"][prim["material"]]
    tex = lambda key: image(doc["textures"][key["index"]]["source"])  # noqa: E731
    pbr = mat["pbrMetallicRoughness"]
    images = {"Color": tex(pbr["baseColorTexture"]), "MetalRough": tex(pbr["metallicRoughnessTexture"]),
              **({"Normal": tex(mat["normalTexture"])} if "normalTexture" in mat else {})}
    return M.Mesh(pos, uv, nor), images


def write_glb(path, parts, materials):
    """Wie mesh_ops.write_glb, aber Bilder unverändert (JPEG bleibt JPEG) und mit Normal Map."""
    blob, views, accessors, images, textures, mats, meshes, nodes = bytearray(), [], [], [], [], [], [], []

    def view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        v = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        blob.extend(data)
        return len(views) - 1

    def acc(array, ctype, typ, target, minmax=False):
        a = {"bufferView": view(np.ascontiguousarray(array).tobytes(), target), "componentType": ctype,
             "count": len(array), "type": typ}
        if minmax:
            a["min"], a["max"] = [float(x) for x in array.min(0)], [float(x) for x in array.max(0)]
        accessors.append(a)
        return len(accessors) - 1

    def tex(img):
        data, mime = img
        images.append({"bufferView": view(data), "mimeType": mime})
        textures.append({"source": len(images) - 1, "sampler": 0})
        return {"index": len(textures) - 1}

    for m in materials:
        pbr = {"baseColorFactor": [*m.get("Factor", (1, 1, 1)), 1.0], "metallicFactor": m.get("Metallic", 0.0),
               "roughnessFactor": m.get("Roughness", 0.6)}
        mat = {"name": m["Name"], "doubleSided": False, "pbrMetallicRoughness": pbr}
        if "Color" in m:
            pbr["baseColorTexture"] = tex(m["Color"])
        if "MetalRough" in m:
            pbr["metallicRoughnessTexture"] = tex(m["MetalRough"])
            pbr["metallicFactor"], pbr["roughnessFactor"] = 1.0, 1.0
        if "Normal" in m:
            mat["normalTexture"] = tex(m["Normal"])
        mats.append(mat)

    for name, mesh, material in parts:
        rows = np.concatenate([mesh.P.reshape(-1, 3), mesh.N.reshape(-1, 3), mesh.UV.reshape(-1, 2)], axis=1)
        unique, index = np.unique(rows, axis=0, return_inverse=True)
        first = np.zeros(len(unique), dtype=np.int64)
        first[index.reshape(-1)[::-1]] = np.arange(len(rows))[::-1]
        verts = rows[first]
        nor = verts[:, 3:6].astype(np.float32)
        nor /= np.maximum(np.linalg.norm(nor, axis=1, keepdims=True), 1e-12)
        attrs = {"POSITION": acc(verts[:, 0:3].astype(np.float32), 5126, "VEC3", 34962, True),
                 "NORMAL": acc(nor, 5126, "VEC3", 34962),
                 "TEXCOORD_0": acc(np.c_[verts[:, 6], 1 - verts[:, 7]].astype(np.float32), 5126, "VEC2", 34962)}
        flat = index.reshape(-1)
        small = len(verts) < 65536            # verlustfrei: 16-Bit-Indizes, wenn es reicht
        prim = {"attributes": attrs, "indices": acc(flat.astype(np.uint16 if small else np.uint32),
                                                    5123 if small else 5125, "SCALAR", 34963),
                "material": material}
        meshes.append({"name": name, "primitives": [prim]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})

    doc = {"asset": {"version": "2.0", "generator": "tools/ar15_glb.py"}, "scene": 0,
           "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": meshes, "materials": mats,
           "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(blob)}],
           "images": images, "textures": textures,
           "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]}
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    while len(blob) % 4:
        blob.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob))



def main():
    gun, images = read_glb(SRC)
    lo, hi = gun.bounds()
    muzzle_x, stock_x = lo[0], hi[0]
    centers = gun.P.mean(1)
    dark = tuple(gun.UV[np.argmin(np.linalg.norm(centers - np.array([0.0, 0.05, 0.05]), axis=1))].mean(0))
    nrm = np.array([0.04, 0.155, 0.0]); nrm /= np.linalg.norm(nrm)
    region = [M.plane(tuple(nrm), (-0.075, 0.020, 0)), M.plane((-1, 0, 0), (MAG_X[0], 0, 0)), M.plane((1, 0, 0), (MAG_X[1], 0, 0))]
    body, mag = M.split(gun, region)
    cap_b, o1 = M.cap_cut(gun, region, [0], -1, dark)
    cap_m, o2 = M.cap_cut(gun, region, [0], 1, dark)
    body, mag = M.Mesh.concat(body, cap_b), M.Mesh.concat(mag, cap_m)
    print("Rumpf %d, Magazin %d Dreiecke, offene Stellen %d/%d" % (len(body), len(mag), o1, o2))
    pts = {k: np.array([muzzle_x if k == "Point_Muzzle" else stock_x if x is None else x, y, z], float) for k, (x, y, z) in POINTS.items()}
    mlo, mhi = mag.bounds()
    pts["Pivot_Magazine"] = np.array([0.0, 0.0, ZC])
    s = LENGTH / (stock_x - muzzle_x)
    R = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)
    origin = pts["Point_Grip"]
    conv = lambda m: M.Mesh((m.P - origin) @ R.T * s, m.UV, m.N @ R.T)
    parts = [("Skin_Body", conv(body), 0), ("Magazine", conv(mag), 0)]
    for k, p in sorted(pts.items()):
        q = (p - origin) @ R.T * s
        size = 0.06 if k.startswith("Pivot") else 0.04
        parts.append((k, M.box(q, (size, size, size)), 1))
        print("  %-17s (%6.3f %6.3f %6.3f)" % (k, *q))
    write_glb(OUT, parts, [{"Name": "Rifle", **images}, {"Name": "Marker", "Factor": (1.0, 0.0, 1.0)}])
    print("Laenge %.2f Studs, %d Dreiecke -> %s %.1f MB" % ((stock_x - muzzle_x) * s, len(body) + len(mag), OUT, os.path.getsize(OUT) / 1e6))
main()

import json, os, struct, sys, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # tools/mesh_ops.py
import mesh_ops as M
SRC, OUT = sys.argv[1], sys.argv[2]
SCALE = 0.24                      # Studs pro Meshy-Einheit (Visier ca. 0,46 Studs lang)
TUN = {"x": (-0.8, 0.85), "y": (0.06, 0.48), "z": (-0.28, 0.28)}   # Sichttunnel durch das Gehäuse
AXIS_Y = 0.27
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
    src, images = read_glb(SRC)
    centers = src.P.mean(1)
    import io
    from PIL import Image
    img = np.asarray(Image.open(io.BytesIO(images["Color"][0])).convert("L"), dtype=float)
    h, w = img.shape
    uvc = src.UV.mean(1)
    px = img[np.clip(((1 - uvc[:, 1]) * (h - 1)).astype(int), 0, h - 1), np.clip((uvc[:, 0] * (w - 1)).astype(int), 0, w - 1)]
    dark = tuple(uvc[np.argmin(px)])   # dunkelste Stelle der Textur für die Innenwände
    (x0, x1), (y0, y1), (z0, z1) = TUN["x"], TUN["y"], TUN["z"]
    box = [M.plane((-1, 0, 0), (x0, 0, 0)), M.plane((1, 0, 0), (x1, 0, 0)), M.plane((0, -1, 0), (0, y0, 0)),
           M.plane((0, 1, 0), (0, y1, 0)), M.plane((0, 0, -1), (0, 0, z0)), M.plane((0, 0, 1), (0, 0, z1))]
    body, removed = M.split(src, box)
    def span(y, z):
        t = M.ray_hits(src, (-3, y, z), (1, 0, 0)); xs = -3 + t
        return (xs.min(), xs.max()) if len(xs) else (-0.6, 0.5)
    walls, steps, out = [], 10, 0.03
    edges = [(lambda u: (y1, z0 + u * (z1 - z0)), (0, -1, 0)), (lambda u: (y0, z0 + u * (z1 - z0)), (0, 1, 0)),
             (lambda u: (y0 + u * (y1 - y0), z0), (0, 0, 1)), (lambda u: (y0 + u * (y1 - y0), z1), (0, 0, -1))]
    for edge, n in edges:
        for k in range(steps):
            (ya, za), (yb, zb) = edge(k / steps), edge((k + 1) / steps)
            fa = span(ya - n[1] * out, za - n[2] * out); fb = span(yb - n[1] * out, zb - n[2] * out)
            walls.append(M.quad((fa[0], ya, za), (fa[1], ya, za), (fb[1], yb, zb), (fb[0], yb, zb), n, dark))
    body = M.Mesh.concat(body, *walls)
    rear, front = span(AXIS_Y, 0.0)
    gx = rear + 0.03
    glass = M.Mesh.concat(M.quad((gx, y0, z0), (gx, y0, z1), (gx, y1, z1), (gx, y1, z0), (-1, 0, 0), (0.5, 0.5)),
                          M.quad((gx, y0, z0), (gx, y1, z0), (gx, y1, z1), (gx, y0, z1), (1, 0, 0), (0.5, 0.5)))
    rx = gx + 0.01
    reticle = M.box((rx, AXIS_Y, 0), (0.005, 0.04, 0.04))   # ein Punkt in der Mitte (das Spiel macht ihn rund)
    print("Tunnel: %d Dreiecke entfernt, hinten x=%.2f, vorne x=%.2f" % (len(removed), rear, front))
    lo, hi = src.bounds()
    pts = {"Point_Mount": np.array([(lo[0] + hi[0]) / 2, lo[1], 0.0]),
           "Point_SightRear": np.array([rear, AXIS_Y, 0.0]), "Point_SightFront": np.array([front, AXIS_Y, 0.0])}
    R = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], float)
    origin = pts["Point_Mount"]
    conv = lambda m: M.Mesh((m.P - origin) @ R.T * SCALE, m.UV, m.N @ R.T)
    parts = [("HoloSight", conv(body), 0), ("Glass_Window", conv(glass), 1), ("Neon_Reticle", conv(reticle), 2)]
    for k, p in pts.items():
        q = (p - origin) @ R.T * SCALE
        parts.append((k, M.box(q, (0.02, 0.02, 0.02)), 3))
        print("  %-17s (%6.3f %6.3f %6.3f)" % (k, *q))
    mats = [{"Name": "HoloSight", **images}, {"Name": "Glass", "Factor": (0.55, 0.65, 0.7), "Roughness": 0.1},
            {"Name": "Reticle", "Factor": (1.0, 0.1, 0.1)}, {"Name": "Marker", "Factor": (1.0, 0.0, 1.0)}]
    write_glb(OUT, parts, mats)
    print("%d Dreiecke, %.2f x %.2f x %.2f Studs -> %.1f MB" % (len(body), (hi[0]-lo[0])*SCALE, (hi[1]-lo[1])*SCALE, (hi[2]-lo[2])*SCALE, os.path.getsize(OUT) / 1e6))
main()

import json, os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # tools/mesh_ops.py
import mesh_ops as M
SRC, OUT = sys.argv[1], sys.argv[2]
SCALE = 0.22          # Studs pro Meshy-Einheit: Griff ca. 0,42 lang, 0,35 hoch
MAX_TRIS = 19500      # Roblox: höchstens 20.000 Dreiecke pro Teil
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



def chunks(mesh, name):
    if len(mesh) <= MAX_TRIS:
        return [(name, mesh)]
    order = np.argsort(mesh.P.mean(1)[:, 1], kind="stable")
    count = int(np.ceil(len(mesh) / MAX_TRIS))
    out = []
    for k, part in enumerate(np.array_split(order, count)):
        mask = np.zeros(len(mesh), bool); mask[part] = True
        out.append(("%s_%02d" % (name, k + 1), mesh.select(mask)))
    return out

def main():
    m, images = read_glb(SRC)
    lo, hi = m.bounds()
    top = hi[1]
    pts = {"Point_Mount": np.array([0.0, top, 0.0]), "Point_Front": np.array([lo[0], top, 0.0])}
    R = np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]], float)
    origin = pts["Point_Mount"]
    conv = lambda q: M.Mesh((q.P - origin) @ R.T * SCALE, q.UV, q.N @ R.T)
    body = conv(m)
    parts = [(n, c, 0) for n, c in chunks(body, "AngledGrip")]
    for k, p in pts.items():
        parts.append((k, M.box((p - origin) @ R.T * SCALE, (0.02, 0.02, 0.02)), 1))
    write_glb(OUT, parts, [{"Name": "AngledGrip", **images}, {"Name": "Marker", "Factor": (1.0, 0.0, 1.0)}])
    blo, bhi = body.bounds()
    print("%d Dreiecke in %d Teilen, Groesse %s Studs -> %.1f MB" % (len(body), len(parts) - 2, np.round(bhi - blo, 3), os.path.getsize(OUT) / 1e6))
main()

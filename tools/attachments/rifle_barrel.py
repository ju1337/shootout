# Lauf des Sturmgewehrs als eigenes Teil herausschneiden (für die Lauf-Aufsätze LongBarrel, ShortBarrel, HeavyBarrel):
#   python3 tools/attachments/rifle_barrel.py art/sources/Rifle.glb art/sources/Rifle.glb
# Alles vor der Stirnseite des Handschutzes (Lauf + Mündungsfeuerdämpfer) wird aus Skin_Body herausgeschnitten und zu
# Skin_Body_Barrel; beide Schnittflächen werden geschlossen. Alle anderen Teile, Marker, UVs und Texturen bleiben
# Byte für Byte unverändert. Ist ein Lauf-Aufsatz angebaut, blendet das Spiel Skin_Body_Barrel aus.
import json, os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # tools/mesh_ops.py
import mesh_ops as M
SRC, OUT = sys.argv[1], sys.argv[2]
CUT = 2.388   # Studs vor dem Griff: Stirnseite des Handschutzes liegt bei 2,375 bis 2,385, der Feuerdämpfer ab 2,445
BARREL = "Skin_Body_Barrel"


def read_all(path):
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

    parts = []
    for node in doc["nodes"]:
        prim = doc["meshes"][node["mesh"]]["primitives"][0]
        assert "translation" not in node and "rotation" not in node and "scale" not in node
        idx = accessor(prim["indices"]).reshape(-1).astype(np.int64)
        pos = accessor(prim["attributes"]["POSITION"]).astype(np.float64)[idx].reshape(-1, 3, 3)
        nor = accessor(prim["attributes"]["NORMAL"]).astype(np.float64)[idx].reshape(-1, 3, 3)
        uv = accessor(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)[idx].reshape(-1, 3, 2)
        uv[..., 1] = 1 - uv[..., 1]
        parts.append((node["name"], M.Mesh(pos, uv, nor), prim["material"]))
    materials = []
    for mat in doc["materials"]:
        pbr = mat["pbrMetallicRoughness"]
        m = {"Name": mat["name"], "Factor": tuple(pbr.get("baseColorFactor", [1, 1, 1, 1])[:3]),
             "Metallic": pbr.get("metallicFactor", 0.0), "Roughness": pbr.get("roughnessFactor", 0.6)}
        tex = lambda key: image(doc["textures"][key["index"]]["source"])  # noqa: E731
        if "baseColorTexture" in pbr:
            m["Color"] = tex(pbr["baseColorTexture"])
        if "metallicRoughnessTexture" in pbr:
            m["MetalRough"] = tex(pbr["metallicRoughnessTexture"])
        if "normalTexture" in mat:
            m["Normal"] = tex(mat["normalTexture"])
        materials.append(m)
    return parts, materials


def patch_glb(src, out, meshes):
    """GLB src kopieren; nur die genannten Teile neu schreiben bzw. anhängen (neue Teile mit dem Material von Skin_Body).
    Alle anderen Teile behalten ihre Daten Byte für Byte, Bilder bleiben unverändert."""
    data = open(src, "rb").read()
    jl = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jl])
    blob = bytearray(data[20 + jl + 8:])

    def view(raw, target):
        while len(blob) % 4:
            blob.append(0)
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw), "target": target})
        blob.extend(raw)
        return len(doc["bufferViews"]) - 1

    def acc(array, ctype, typ, target, minmax=False):
        a = {"bufferView": view(np.ascontiguousarray(array).tobytes(), target), "componentType": ctype,
             "count": len(array), "type": typ}
        if minmax:
            a["min"], a["max"] = [float(x) for x in array.min(0)], [float(x) for x in array.max(0)]
        doc["accessors"].append(a)
        return len(doc["accessors"]) - 1

    def primitive(mesh, material):
        rows = np.concatenate([mesh.P.reshape(-1, 3), mesh.N.reshape(-1, 3), mesh.UV.reshape(-1, 2)], axis=1)
        unique, index = np.unique(rows, axis=0, return_inverse=True)
        first = np.zeros(len(unique), dtype=np.int64)
        first[index.reshape(-1)[::-1]] = np.arange(len(rows))[::-1]
        verts = rows[first]
        nor = verts[:, 3:6].astype(np.float32)
        nor /= np.maximum(np.linalg.norm(nor, axis=1, keepdims=True), 1e-12)
        flat = index.reshape(-1)
        small = len(verts) < 65536
        return {"attributes": {"POSITION": acc(verts[:, 0:3].astype(np.float32), 5126, "VEC3", 34962, True),
                               "NORMAL": acc(nor, 5126, "VEC3", 34962),
                               "TEXCOORD_0": acc(np.c_[verts[:, 6], 1 - verts[:, 7]].astype(np.float32), 5126, "VEC2", 34962)},
                "indices": acc(flat.astype(np.uint16 if small else np.uint32), 5123 if small else 5125, "SCALAR", 34963),
                "material": material}

    byname = {n["name"]: n for n in doc["nodes"]}
    material = doc["meshes"][byname["Skin_Body"]["mesh"]]["primitives"][0]["material"]
    for name, mesh in meshes.items():
        if name in byname:
            doc["meshes"][byname[name]["mesh"]]["primitives"] = [primitive(mesh, material)]
        else:
            doc["meshes"].append({"name": name, "primitives": [primitive(mesh, material)]})
            doc["nodes"].append({"name": name, "mesh": len(doc["meshes"]) - 1})
            doc["scenes"][0]["nodes"].append(len(doc["nodes"]) - 1)
    # nicht mehr benutzte Daten (altes Skin_Body) entfernen: nur benutzte Ansichten neu packen
    used = set()
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            used.update(doc["accessors"][i]["bufferView"] for i in [*prim["attributes"].values(), prim["indices"]])
    used.update(im["bufferView"] for im in doc.get("images", []))
    keep_acc = sorted({i for mesh in doc["meshes"] for prim in mesh["primitives"]
                       for i in [*prim["attributes"].values(), prim["indices"]]})
    acc_map = {old: new for new, old in enumerate(keep_acc)}
    view_map, packed, views = {}, bytearray(), []
    for old in sorted(used):
        v = doc["bufferViews"][old]
        raw = blob[v["byteOffset"]:v["byteOffset"] + v["byteLength"]]
        while len(packed) % 4:
            packed.append(0)
        nv = dict(v, byteOffset=len(packed))
        packed.extend(raw)
        view_map[old] = len(views)
        views.append(nv)
    accessors = []
    for old in keep_acc:
        a = dict(doc["accessors"][old]); a["bufferView"] = view_map[a["bufferView"]]; accessors.append(a)
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            prim["attributes"] = {k: acc_map[i] for k, i in prim["attributes"].items()}
            prim["indices"] = acc_map[prim["indices"]]
    for im in doc.get("images", []):
        im["bufferView"] = view_map[im["bufferView"]]
    doc["accessors"], doc["bufferViews"] = accessors, views
    while len(packed) % 4:
        packed.append(0)
    doc["buffers"] = [{"byteLength": len(packed)}]
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(out, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(packed)))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(packed), b"BIN\0") + bytes(packed))


parts, materials = read_all(SRC)
names = [p[0] for p in parts]
assert BARREL not in names, "Lauf ist schon herausgeschnitten"
i = names.index("Skin_Body")
name, body, mat = parts[i]
# glTF: Lauf nach -Z; Bereich "Lauf" = z <= -CUT
region = [M.plane((0, 0, 1), (0, 0, -CUT))]
rest, barrel = M.split(body, region)
centers = barrel.P.mean(1)
dark = tuple(barrel.UV[np.argmin(np.linalg.norm(centers - np.array([0.0, 0.5261, -2.55]), axis=1))].mean(0))
cap_rest, o1 = M.cap_cut(body, region, [0], -1, dark)
cap_barrel, o2 = M.cap_cut(body, region, [0], 1, dark)
rest, barrel = M.Mesh.concat(rest, cap_rest), M.Mesh.concat(barrel, cap_barrel)
lo, hi = barrel.bounds()
print("Rumpf %d, Lauf %d Dreiecke (offen %d/%d), Lauf x %.3f..%.3f y %.3f..%.3f vorne %.3f..%.3f" % (
    len(rest), len(barrel), o1, o2, lo[0], hi[0], lo[1], hi[1], -hi[2], -lo[2]))
patch_glb(SRC, OUT, {"Skin_Body": rest, BARREL: barrel})
print("->", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6))

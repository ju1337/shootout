"""FBX-Dateien lesen (Binärformat, Version 7.x) – ohne Blender oder FBX-SDK.

Liest den Knotenbaum und daraus die Meshes mit Weltlage: Eckpunkte, Dreiecke, UVs und Normalen je Ecke. Reicht für
die Modelle aus Blender und Meshy (eine oder wenige Meshes, Euler-Drehung XYZ).

    import fbx_read as F
    meshes = F.load_meshes("art/sources/x.fbx")   # [{Name, Positions (N,3), Triangles (M,3), UV (M,3,2), Normals (M,3,3)}]
"""
import struct
import zlib

import numpy as np

MAGIC = b"Kaydara FBX Binary  \x00"


class Node:
    __slots__ = ("name", "props", "children")

    def __init__(self, name, props, children):
        self.name, self.props, self.children = name, props, children

    def find(self, name):
        for child in self.children:
            if child.name == name:
                return child
        return None

    def all(self, name):
        return [child for child in self.children if child.name == name]

    def __repr__(self):
        return "Node(%s, %d props, %d children)" % (self.name, len(self.props), len(self.children))


def _array(data, pos, code):
    length, encoding, size = struct.unpack_from("<III", data, pos)
    pos += 12
    raw = data[pos:pos + size]
    pos += size
    if encoding == 1:
        raw = zlib.decompress(raw)
    dtype = {"f": "<f4", "d": "<f8", "l": "<i8", "i": "<i4", "b": "u1"}[code]
    return np.frombuffer(raw, dtype=dtype, count=length).copy(), pos


def _property(data, pos):
    code = chr(data[pos])
    pos += 1
    if code == "Y":
        return struct.unpack_from("<h", data, pos)[0], pos + 2
    if code == "C":
        return data[pos] != 0, pos + 1
    if code == "I":
        return struct.unpack_from("<i", data, pos)[0], pos + 4
    if code == "F":
        return struct.unpack_from("<f", data, pos)[0], pos + 4
    if code == "D":
        return struct.unpack_from("<d", data, pos)[0], pos + 8
    if code == "L":
        return struct.unpack_from("<q", data, pos)[0], pos + 8
    if code in "fdlib":
        return _array(data, pos, code)
    if code in "SR":
        size = struct.unpack_from("<I", data, pos)[0]
        raw = data[pos + 4:pos + 4 + size]
        return (raw.decode("utf-8", "replace") if code == "S" else raw), pos + 4 + size
    raise ValueError("unbekannter Eigenschaftstyp %r bei %d" % (code, pos - 1))


def parse(path):
    """Knotenbaum einer binären FBX-Datei (Wurzel: Node('', [], [oberste Knoten]))."""
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(MAGIC):
        raise ValueError("%s ist keine binäre FBX-Datei (ASCII-FBX bitte in Blender als binär exportieren)" % path)
    version = struct.unpack_from("<I", data, 23)[0]
    wide = version >= 7500
    head = 25 if wide else 13

    def node(pos):
        if wide:
            end, count, _length = struct.unpack_from("<QQQ", data, pos)
        else:
            end, count, _length = struct.unpack_from("<III", data, pos)
        if end == 0:
            return None, pos + head
        name_len = data[pos + head - 1]
        name = data[pos + head:pos + head + name_len].decode("ascii", "replace")
        pos += head + name_len
        props = []
        for _ in range(count):
            value, pos = _property(data, pos)
            props.append(value)
        children = []
        while pos < end:
            child, pos = node(pos)
            if child is None:
                break
            children.append(child)
        return Node(name, props, children), end

    top, pos = [], 27
    while pos < len(data) - head:
        child, pos = node(pos)
        if child is None:
            break
        top.append(child)
    root = Node("", [], top)
    root.props = [version]
    return root


def properties70(node):
    """{Name: Werte} aus einem Properties70-Block."""
    out = {}
    block = node.find("Properties70") if node else None
    for p in block.children if block else []:
        if p.name == "P" and len(p.props) >= 4:
            out[p.props[0]] = p.props[4:]
    return out


def _rotation(degrees):
    """Euler XYZ (FBX-Standard): erst um X, dann Y, dann Z."""
    x, y, z = np.radians(degrees)
    rx = np.array([[1, 0, 0], [0, np.cos(x), -np.sin(x)], [0, np.sin(x), np.cos(x)]])
    ry = np.array([[np.cos(y), 0, np.sin(y)], [0, 1, 0], [-np.sin(y), 0, np.cos(y)]])
    rz = np.array([[np.cos(z), -np.sin(z), 0], [np.sin(z), np.cos(z), 0], [0, 0, 1]])
    return rz @ ry @ rx


def _local(props, prefix=""):
    """4x4-Matrix aus Lcl Translation/Rotation/Scaling (+ PreRotation, Pivots), bzw. Geometric… mit prefix."""
    def vec(key, default):
        value = props.get(key)
        return np.array(value[:3], dtype=float) if value and len(value) >= 3 else np.array(default, dtype=float)
    m = np.eye(4)
    if prefix:
        t, r, s = vec("GeometricTranslation", (0, 0, 0)), vec("GeometricRotation", (0, 0, 0)), vec("GeometricScaling", (1, 1, 1))
        m[:3, :3] = _rotation(r) @ np.diag(s)
        m[:3, 3] = t
        return m
    t, r, s = vec("Lcl Translation", (0, 0, 0)), vec("Lcl Rotation", (0, 0, 0)), vec("Lcl Scaling", (1, 1, 1))
    pre, post = vec("PreRotation", (0, 0, 0)), vec("PostRotation", (0, 0, 0))
    rp, sp = vec("RotationPivot", (0, 0, 0)), vec("ScalingPivot", (0, 0, 0))
    roff, soff = vec("RotationOffset", (0, 0, 0)), vec("ScalingOffset", (0, 0, 0))

    def trans(v):
        a = np.eye(4)
        a[:3, 3] = v
        return a

    def rot(deg):
        a = np.eye(4)
        a[:3, :3] = _rotation(deg)
        return a
    scale = np.eye(4)
    scale[:3, :3] = np.diag(s)
    # FBX: T * Roff * Rp * Rpre * R * Rpost^-1 * Rp^-1 * Soff * Sp * S * Sp^-1
    m = (trans(t) @ trans(roff) @ trans(rp) @ rot(pre) @ rot(r) @ np.linalg.inv(rot(post)) @ trans(-rp)
         @ trans(soff) @ trans(sp) @ scale @ trans(-sp))
    return m


def _layer(geometry, name, field, index_field, poly_vertex_count, polygon_of_corner, control_of_corner):
    """Werte eines LayerElement (Normalen/UVs) je Polygon-Ecke."""
    layer = geometry.find(name)
    if not layer:
        return None
    values = layer.find(field)
    if values is None:
        return None
    width = 3 if field == "Normals" else 2
    data = values.props[0].reshape(-1, width)
    mapping = (layer.find("MappingInformationType").props[0] if layer.find("MappingInformationType") else "ByPolygonVertex")
    reference = (layer.find("ReferenceInformationType").props[0] if layer.find("ReferenceInformationType") else "Direct")
    if mapping in ("ByPolygonVertex",):
        keys = np.arange(poly_vertex_count)
    elif mapping in ("ByVertice", "ByVertex", "ByControlPoint"):
        keys = control_of_corner
    elif mapping == "ByPolygon":
        keys = polygon_of_corner
    elif mapping == "AllSame":
        keys = np.zeros(poly_vertex_count, dtype=int)
    else:
        return None
    if reference in ("IndexToDirect", "Index"):
        index = layer.find(index_field)
        if index is not None:
            keys = index.props[0][keys]
    return data[keys]


def load_meshes(path):
    """Alle Meshes mit Weltlage (in Datei-Einheiten, ohne Achsen-Umrechnung) und Infos aus GlobalSettings.

    Gibt (meshes, settings) zurück: meshes = [{Name, Positions, Triangles, UV, Normals, Material}],
    settings = Properties70 von GlobalSettings (UpAxis, UnitScaleFactor, …)."""
    root = parse(path)
    objects = root.find("Objects")
    settings = properties70(root.find("GlobalSettings"))
    nodes = {}
    for child in objects.children:
        if child.props and isinstance(child.props[0], int):
            nodes[child.props[0]] = child
    parent_of, geometry_of, materials_of = {}, {}, {}
    for c in root.find("Connections").all("C"):
        kind, child, parent = c.props[0], c.props[1], c.props[2]
        if kind != "OO" or child not in nodes:
            continue
        child_node, parent_node = nodes[child], nodes.get(parent)
        if child_node.name == "Model" and (parent == 0 or (parent_node and parent_node.name == "Model")):
            parent_of[child] = parent
        elif child_node.name == "Geometry" and parent_node and parent_node.name == "Model":
            geometry_of[parent] = child
        elif child_node.name == "Material" and parent_node and parent_node.name == "Model":
            materials_of.setdefault(parent, []).append(child)

    def world(model_id):
        m = _local(properties70(nodes[model_id]))
        parent = parent_of.get(model_id, 0)
        return world(parent) @ m if parent else m

    meshes = []
    for model_id, geometry_id in geometry_of.items():
        model, geometry = nodes[model_id], nodes[geometry_id]
        props = properties70(model)
        matrix = world(model_id) @ _local(props, "Geometric")
        verts = geometry.find("Vertices").props[0].reshape(-1, 3)
        index = geometry.find("PolygonVertexIndex").props[0].astype(np.int64)
        ends = index < 0
        control = np.where(ends, -index - 1, index)
        corner_count = len(control)
        polygon = np.cumsum(np.concatenate(([0], ends[:-1].astype(np.int64))))
        uv = _layer(geometry, "LayerElementUV", "UV", "UVIndex", corner_count, polygon, control)
        normals = _layer(geometry, "LayerElementNormal", "Normals", "NormalsIndex", corner_count, polygon, control)
        # Polygone als Fächer triangulieren: Ecken (start, k, k+1)
        starts = np.concatenate(([0], np.nonzero(ends)[0][:-1] + 1))
        stops = np.nonzero(ends)[0]
        tri_corners = []
        for a, b in zip(starts, stops):
            for k in range(a + 1, b):
                tri_corners.append((a, k, k + 1))
        tri_corners = np.array(tri_corners, dtype=np.int64)
        positions = (np.c_[verts, np.ones(len(verts))] @ matrix.T)[:, :3]
        normal_matrix = np.linalg.inv(matrix[:3, :3]).T
        entry = {
            "Name": model.props[1].split("\x00")[0] if len(model.props) > 1 else str(model_id),
            "Positions": positions,
            "Triangles": control[tri_corners],
            "UV": uv[tri_corners] if uv is not None else None,
            "Normals": None,
            "Materials": [nodes[m].props[1].split("\x00")[0] for m in materials_of.get(model_id, [])],
        }
        if normals is not None:
            n = normals @ normal_matrix.T
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
            entry["Normals"] = n[tri_corners]
        meshes.append(entry)
    return meshes, settings


def dump(node, depth=0, limit=3):
    """Knotenbaum zum Ansehen (Arrays nur als Länge)."""
    for child in node.children:
        shown = []
        for p in child.props[:6]:
            if isinstance(p, np.ndarray):
                shown.append("<%s x%d>" % (p.dtype, len(p)))
            elif isinstance(p, bytes):
                shown.append("<%d bytes>" % len(p))
            else:
                shown.append(repr(p)[:60])
        print("  " * depth + child.name, ", ".join(shown))
        if depth + 1 < limit:
            dump(child, depth + 1, limit)

"""Werkzeuge für Waffenmodelle aus fremden Quellen (Meshy, Sketchfab …): Dreiecks-Meshes schneiden, Schnittflächen
schließen, Teile verschieben und als GLB (mit Texturen) für den Studio-Import schreiben.

Ein Mesh speichert jede Dreiecksecke einzeln (Position, UV, Normale) – so lassen sich Dreiecke beliebig zerschneiden,
ohne gemeinsame Eckpunkte zu verwalten. Beim Schreiben werden gleiche Ecken wieder zusammengefasst.
UVs sind im FBX-Format (v nach oben); write_glb dreht sie für glTF um.
"""
import io
import json
import struct

import numpy as np
from PIL import Image

EPS = 1e-7


def face_normals(P):
    n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    return np.repeat(n[:, None, :], 3, axis=1)


class Mesh:
    """Dreiecke: P (M,3,3) Positionen, UV (M,3,2), N (M,3,3) Normalen je Ecke."""

    def __init__(self, P, UV=None, N=None):
        self.P = np.asarray(P, float).reshape(-1, 3, 3)
        self.UV = np.zeros((len(self.P), 3, 2)) if UV is None else np.asarray(UV, float).reshape(-1, 3, 2)
        self.N = face_normals(self.P) if N is None else np.asarray(N, float).reshape(-1, 3, 3)

    def __len__(self):
        return len(self.P)

    @staticmethod
    def from_fbx(entry):
        T = entry["Triangles"]
        return Mesh(entry["Positions"][T], entry["UV"], entry["Normals"])

    @staticmethod
    def concat(*meshes):
        meshes = [m for m in meshes if m is not None and len(m)]
        if not meshes:
            return Mesh(np.zeros((0, 3, 3)))
        return Mesh(np.concatenate([m.P for m in meshes]), np.concatenate([m.UV for m in meshes]),
                    np.concatenate([m.N for m in meshes]))

    def select(self, mask):
        return Mesh(self.P[mask], self.UV[mask], self.N[mask])

    def transformed(self, R, scale=1.0, offset=(0, 0, 0)):
        """p -> scale * R p + offset (R = Drehung 3x3)."""
        R = np.asarray(R, float)
        return Mesh(scale * self.P @ R.T + np.asarray(offset, float), self.UV.copy(), self.N @ R.T)

    def bounds(self):
        flat = self.P.reshape(-1, 3)
        return flat.min(0), flat.max(0)


# ---------- Schneiden ----------
# Ebene (n, c): Abstand d(p) = n·p - c. Ein Bereich ist eine Liste von Ebenen; drinnen heißt d <= 0 für alle.

def plane(normal, point):
    n = np.asarray(normal, float)
    n = n / np.linalg.norm(n)
    return n, float(n @ np.asarray(point, float))


def _clip(poly, n, c, keep_inside):
    """Polygon (k,8: xyz uv nxnynz) an einer Ebene beschneiden; keep_inside: Teil mit d <= 0 behalten, sonst d >= 0."""
    if len(poly) == 0:
        return poly
    d = poly[:, :3] @ n - c
    if not keep_inside:
        d = -d
    out = []
    k = len(poly)
    for i in range(k):
        a, b = poly[i], poly[(i + 1) % k]
        da, db = d[i], d[(i + 1) % k]
        if da <= EPS:
            out.append(a)
        if (da < -EPS and db > EPS) or (da > EPS and db < -EPS):
            t = da / (da - db)
            out.append(a + t * (b - a))
    return np.array(out) if len(out) >= 3 else np.zeros((0, 8))


def _fan(poly):
    """Polygon -> Dreiecke (Fächer); Normalen der Ecken werden neu normiert, winzige Dreiecke fallen weg."""
    tris = []
    for i in range(1, len(poly) - 1):
        tri = np.array([poly[0], poly[i], poly[i + 1]])
        area = np.linalg.norm(np.cross(tri[1, :3] - tri[0, :3], tri[2, :3] - tri[0, :3]))
        if area > 1e-9:
            tris.append(tri)
    return tris


def _pack(mesh, index):
    return np.concatenate([mesh.P[index], mesh.UV[index], mesh.N[index]], axis=1)


def _unpack(tris):
    if not tris:
        return Mesh(np.zeros((0, 3, 3)))
    a = np.array(tris)
    n = a[:, :, 5:8]
    n = n / np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-12)
    return Mesh(a[:, :, 0:3], a[:, :, 3:5], n)


def split(mesh, region):
    """(außen, innen): Dreiecke außerhalb bzw. innerhalb des konvexen Bereichs; Dreiecke auf der Grenze werden geteilt."""
    if not len(mesh):
        return mesh, mesh
    d = np.stack([mesh.P @ n - c for n, c in region])  # (Ebenen, M, 3)
    fully_out = (d > EPS).all(axis=2).any(axis=0)
    fully_in = (d <= EPS).all(axis=2).all(axis=0)
    crossing = ~fully_out & ~fully_in
    outside, inside = [], []
    for index in np.nonzero(crossing)[0]:
        poly = _pack(mesh, index)
        inner = poly
        for n, c in region:
            inner = _clip(inner, n, c, True)
        inside.extend(_fan(inner))
        rest = poly
        for n, c in region:  # außen = Teil jenseits Ebene i, aber diesseits der Ebenen davor
            outer = _clip(rest, n, c, False)
            outside.extend(_fan(outer))
            rest = _clip(rest, n, c, True)
            if not len(rest):
                break
    out_mesh = Mesh.concat(mesh.select(fully_out), _unpack(outside))
    in_mesh = Mesh.concat(mesh.select(fully_in), _unpack(inside))
    return out_mesh, in_mesh


def section(mesh, cut, region=(), tol=1e-6):
    """Schnittstrecken des Meshes mit der Ebene cut, auf die übrigen Ebenen region zugeschnitten (d <= 0). [(a, b)]"""
    n, c = cut
    d = mesh.P @ n - c
    segs = []
    for i in np.nonzero((d.min(1) < -EPS) & (d.max(1) > EPS))[0]:
        pts = []
        for a, b in ((0, 1), (1, 2), (2, 0)):
            da, db = d[i, a], d[i, b]
            if (da < -EPS) != (db < -EPS) and abs(da - db) > EPS:
                t = da / (da - db)
                pts.append(mesh.P[i, a] + t * (mesh.P[i, b] - mesh.P[i, a]))
        if len(pts) != 2:
            continue
        a, b = pts
        t0, t1 = 0.0, 1.0
        for m, k in region:  # Strecke an den Nachbarebenen abschneiden
            da, db = m @ a - k, m @ b - k
            if da > tol and db > tol:
                t0, t1 = 1.0, 0.0
                break
            if da > tol or db > tol:
                t = da / (da - db)
                if da > tol:
                    t0 = max(t0, t)
                else:
                    t1 = min(t1, t)
        if t1 - t0 > 1e-9:
            pa, pb = a + t0 * (b - a), a + t1 * (b - a)
            if np.linalg.norm(pb - pa) > 1e-6:
                segs.append((pa, pb))
    return segs


def loops(segs, tol=1e-3):
    """Strecken zu geschlossenen Linienzügen verketten. Gibt (Liste geschlossener Züge, Anzahl offener Enden) zurück."""
    def key(p):
        return tuple(np.round(np.asarray(p) / tol).astype(int))
    neighbours, points = {}, {}
    for a, b in segs:
        ka, kb = key(a), key(b)
        if ka == kb:
            continue
        points[ka], points[kb] = a, b
        neighbours.setdefault(ka, []).append(kb)
        neighbours.setdefault(kb, []).append(ka)
    used, result, open_ends = set(), [], 0
    for start in list(neighbours):
        if start in used:
            continue
        chain, prev, cur = [start], None, start
        used.add(start)
        while True:
            nxt = [k for k in neighbours[cur] if k != prev and (k not in used or (k == start and len(chain) > 2))]
            if not nxt:
                open_ends += 1
                break
            prev, cur = cur, nxt[0]
            if cur == start:
                break
            chain.append(cur)
            used.add(cur)
        if cur == start and len(chain) >= 3:
            result.append([points[k] for k in chain])
    return result, open_ends


def _basis(normal):
    n = np.asarray(normal, float)
    helper = np.array([1.0, 0, 0]) if abs(n[0]) < 0.9 else np.array([0, 1.0, 0])
    e1 = np.cross(n, helper)
    e1 /= np.linalg.norm(e1)
    return e1, np.cross(n, e1)


def _ear_clip(pts2):
    """Einfaches Polygon (k,2) gegen den Uhrzeigersinn -> Dreiecke als Index-Tripel."""
    idx = list(range(len(pts2)))
    tris = []

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        found = False
        for i in range(len(idx)):
            a, b, c = idx[i - 1], idx[i], idx[(i + 1) % len(idx)]
            pa, pb, pc = pts2[a], pts2[b], pts2[c]
            if cross(pa, pb, pc) <= 1e-12:
                continue  # nicht konvex
            inside = False
            for j in idx:
                if j in (a, b, c):
                    continue
                p = pts2[j]
                if cross(pa, pb, p) >= -1e-12 and cross(pb, pc, p) >= -1e-12 and cross(pc, pa, p) >= -1e-12:
                    inside = True
                    break
            if inside:
                continue
            tris.append((a, b, c))
            idx.pop(i)
            found = True
            break
        if not found:  # entartet (z.B. überschneidend): Rest als Fächer
            break
    for i in range(1, len(idx) - 1):
        tris.append((idx[0], idx[i], idx[i + 1]))
    return tris


def cap(loop_points, normal, uv):
    """Fläche in einem geschlossenen ebenen Linienzug; Vorderseite zeigt nach normal; alle Ecken bekommen die UV uv."""
    pts = np.array(loop_points, float)
    e1, e2 = _basis(normal)
    p2 = np.c_[pts @ e1, pts @ e2]
    area = 0.5 * np.sum(p2[:, 0] * np.roll(p2[:, 1], -1) - np.roll(p2[:, 0], -1) * p2[:, 1])
    if area < 0:
        pts, p2 = pts[::-1], p2[::-1]
    tris = _ear_clip(p2)
    n = np.asarray(normal, float)
    P = np.array([[pts[a], pts[b], pts[c]] for a, b, c in tris])
    if not len(P):
        return Mesh(np.zeros((0, 3, 3)))
    # Ausrichtung prüfen (e1 x e2 = normal, gegen den Uhrzeigersinn = Vorderseite)
    fn = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    flip = fn @ n < 0
    P[flip] = P[flip][:, ::-1]
    return Mesh(P, np.tile(np.asarray(uv, float), (len(P), 3, 1)), np.tile(n, (len(P), 3, 1)))


def cap_cut(mesh, region, cut_indices, outward, uv, tol=1e-4):
    """Schnittfläche eines Bereichs schließen – auch wenn die Schnittkante über zwei Ebenen geknickt ist.
    outward = +1: Deckel zeigt aus dem Bereich heraus (für das herausgeschnittene Teil), -1: in den Bereich hinein
    (für den Rest). Gibt (Mesh, Anzahl Stellen, die nicht geschlossen werden konnten) zurück."""
    segs = []
    for i in cut_indices:
        segs += section(mesh, region[i], [p for j, p in enumerate(region) if j != i])
    rings, open_ends = loops(segs)
    caps = []
    planes = [region[i] for i in cut_indices]

    def on(p, k):
        n, c = planes[k]
        return abs(n @ p - c) < tol
    for ring in rings:
        pts = [np.asarray(p, float) for p in ring]
        homes = [k for k in range(len(planes)) if all(on(p, k) for p in pts)]
        if homes:
            caps.append(cap(pts, outward * planes[homes[0]][0], uv))
            continue
        # Ring an den Knickpunkten (auf zwei Ebenen) in Stücke teilen; jedes Stück liegt in einer Ebene
        kinks = [i for i, p in enumerate(pts) if sum(on(p, k) for k in range(len(planes))) >= 2]
        if len(kinks) < 2:
            open_ends += 1
            continue
        pieces = []
        for a, b in zip(kinks, kinks[1:] + [kinks[0] + len(pts)]):
            chain = [pts[i % len(pts)] for i in range(a, b + 1)]
            inner = chain[1:-1] or [(chain[0] + chain[-1]) / 2]
            home = [k for k in range(len(planes)) if all(on(p, k) for p in inner)]
            if not home:
                open_ends += 1
                continue
            pieces.append((home[0], chain))
        for k in range(len(planes)):
            mine = [chain for home, chain in pieces if home == k]
            if not mine:
                continue
            # Knickkante: Richtung = Schnitt der beiden Ebenen; Enden der Stücke entlang der Kante paarweise verbinden
            other = [j for j in range(len(planes)) if j != k][0]
            direction = np.cross(planes[k][0], planes[other][0])
            ends = sorted([(chain[0] @ direction, ci, 0) for ci, chain in enumerate(mine)]
                          + [(chain[-1] @ direction, ci, 1) for ci, chain in enumerate(mine)])
            partner = {}
            for e in range(0, len(ends) - 1, 2):
                a, b = ends[e][1:], ends[e + 1][1:]
                partner[a], partner[b] = b, a
            used = set()
            for ci in range(len(mine)):
                if ci in used:
                    continue
                poly, cur, side = [], ci, 0
                while cur not in used:
                    used.add(cur)
                    chain = mine[cur] if side == 0 else mine[cur][::-1]
                    poly.extend(chain)
                    end = (cur, 1 if side == 0 else 0)
                    if end not in partner:
                        break
                    cur, side = partner[end]
                if len(poly) >= 3:
                    caps.append(cap(poly, outward * planes[k][0], uv))
    return Mesh.concat(*caps), open_ends


def quad(a, b, c, d, normal, uv):
    """Viereck a-b-c-d (eben, in Reihenfolge) mit Vorderseite nach normal."""
    P = np.array([[a, b, c], [a, c, d]], float)
    n = np.asarray(normal, float) / np.linalg.norm(normal)
    fn = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    flip = fn @ n < 0
    P[flip] = P[flip][:, ::-1]
    return Mesh(P, np.tile(np.asarray(uv, float), (2, 3, 1)), np.tile(n, (2, 3, 1)))


def box(center, size, uv=(0.5, 0.5)):
    """Quader (für Marker)."""
    c, h = np.asarray(center, float), np.asarray(size, float) / 2
    meshes = []
    for axis in range(3):
        for sign in (-1, 1):
            n = np.zeros(3)
            n[axis] = sign
            u, v = np.zeros(3), np.zeros(3)
            u[(axis + 1) % 3] = h[(axis + 1) % 3]
            v[(axis + 2) % 3] = h[(axis + 2) % 3]
            f = c + n * h
            meshes.append(quad(f - u - v, f + u - v, f + u + v, f - u + v, n, uv))
    return Mesh.concat(*meshes)


def uv_at(mesh, origin, direction):
    """UV am ersten Treffer eines Strahls (zum Auswählen einer passenden Farbe der Textur), sonst None."""
    o, dvec = np.asarray(origin, float), np.asarray(direction, float)
    v0, v1, v2 = mesh.P[:, 0], mesh.P[:, 1], mesh.P[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    h = np.cross(dvec, e2)
    a = np.einsum("ij,ij->i", e1, h)
    ok = np.abs(a) > 1e-12
    f = np.where(ok, 1 / np.where(ok, a, 1), 0)
    s = o - v0
    u = f * np.einsum("ij,ij->i", s, h)
    q = np.cross(s, e1)
    v = f * (q @ dvec)
    t = f * np.einsum("ij,ij->i", e2, q)
    m = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
    if not m.any():
        return None
    i = np.nonzero(m)[0][np.argmin(t[m])]
    w = np.array([1 - u[i] - v[i], u[i], v[i]])
    return w @ mesh.UV[i]


def ray_hits(mesh, origin, direction):
    """Alle Treffer-Parameter t (sortiert) eines Strahls."""
    o, dvec = np.asarray(origin, float), np.asarray(direction, float)
    v0, v1, v2 = mesh.P[:, 0], mesh.P[:, 1], mesh.P[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    h = np.cross(dvec, e2)
    a = np.einsum("ij,ij->i", e1, h)
    ok = np.abs(a) > 1e-12
    f = np.where(ok, 1 / np.where(ok, a, 1), 0)
    s = o - v0
    u = f * np.einsum("ij,ij->i", s, h)
    q = np.cross(s, e1)
    v = f * (q @ dvec)
    t = f * np.einsum("ij,ij->i", e2, q)
    m = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-9)
    return np.sort(t[m])


# ---------- Texturen ----------

def png_bytes(image):
    buf = io.BytesIO()
    image.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def solid_png(rgb):
    return png_bytes(Image.new("RGB", (4, 4), tuple(int(round(c * 255)) for c in rgb)))


# ---------- GLB ----------

def write_glb(path, parts, materials, generator="tools/mesh_ops.py", extras=None):
    """parts: [(Name, Mesh, Material-Index)]; materials: [{Name, Color (PNG-Bytes), MetalRough (PNG-Bytes oder None),
    Factor (RGB), Metallic, Roughness}]. Positionen/Normalen unverändert, UV v wird für glTF umgedreht."""
    blob = bytearray()
    views, accessors, images, textures, mats, meshes, nodes = [], [], [], [], [], [], []

    def add_view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        blob.extend(data)
        return len(views) - 1

    def add_accessor(array, ctype, typ, target, minmax=False):
        data = np.ascontiguousarray(array).tobytes()
        acc = {"bufferView": add_view(data, target), "componentType": ctype, "count": len(array), "type": typ}
        if minmax:
            acc["min"] = [float(x) for x in array.min(0)]
            acc["max"] = [float(x) for x in array.max(0)]
        accessors.append(acc)
        return len(accessors) - 1

    def add_image(data):
        images.append({"bufferView": add_view(data), "mimeType": "image/png"})
        textures.append({"source": len(images) - 1, "sampler": 0})
        return len(textures) - 1

    for m in materials:
        pbr = {"baseColorFactor": [*m.get("Factor", (1, 1, 1)), 1.0], "metallicFactor": m.get("Metallic", 0.0),
               "roughnessFactor": m.get("Roughness", 0.6)}
        if m.get("Color"):
            pbr["baseColorTexture"] = {"index": add_image(m["Color"])}
        if m.get("MetalRough"):
            pbr["metallicRoughnessTexture"] = {"index": add_image(m["MetalRough"])}
            pbr["metallicFactor"], pbr["roughnessFactor"] = 1.0, 1.0
        mats.append({"name": m["Name"], "doubleSided": False, "pbrMetallicRoughness": pbr})

    for name, mesh, material in parts:
        rows = np.concatenate([mesh.P.reshape(-1, 3), mesh.N.reshape(-1, 3), mesh.UV.reshape(-1, 2)], axis=1)
        keyed = np.round(rows, 5)
        unique, index = np.unique(keyed, axis=0, return_inverse=True)
        first = np.zeros(len(unique), dtype=int)
        first[index[::-1]] = np.arange(len(rows))[::-1]
        verts = rows[first]
        pos = verts[:, 0:3].astype(np.float32)
        nor = verts[:, 3:6].astype(np.float32)
        nor /= np.maximum(np.linalg.norm(nor, axis=1, keepdims=True), 1e-12)
        uv = np.c_[verts[:, 6], 1 - verts[:, 7]].astype(np.float32)
        idx = index.reshape(-1).astype(np.uint32)
        attrs = {"POSITION": add_accessor(pos, 5126, "VEC3", 34962, True), "NORMAL": add_accessor(nor, 5126, "VEC3", 34962),
                 "TEXCOORD_0": add_accessor(uv, 5126, "VEC2", 34962)}
        prim = {"attributes": attrs, "indices": add_accessor(idx, 5125, "SCALAR", 34963), "material": material}
        meshes.append({"name": name, "primitives": [prim]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})

    doc = {"asset": {"version": "2.0", "generator": generator}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}],
           "nodes": nodes, "meshes": meshes, "materials": mats, "accessors": accessors, "bufferViews": views,
           "buffers": [{"byteLength": len(blob)}]}
    if extras:
        doc["asset"]["extras"] = extras
    if images:
        doc["images"], doc["textures"] = images, textures
        doc["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    while len(blob) % 4:
        blob.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob))

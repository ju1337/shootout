# Magazin-Aufsatz (z.B. 60er-Magazin) in voller Meshy-Qualität für das Sturmgewehr vorbereiten:
#   python3 tools/attachments/mag_full.py <meshy.fbx> <art/sources/Rifle.glb> <ausgabe.glb>
# Neben der FBX müssen die Meshy-Texturen liegen (<name>.png, _normal.png, _roughness.png, _metallic.png).
#
# Nichts wird reduziert: alle Dreiecke und die Texturen in Originalgröße bleiben. Roblox erlaubt höchstens 20.000
# Dreiecke pro Teil, deshalb wird das Magazin entlang seiner Länge in Stücke Magazine_Ext_01, _02 … geteilt.
# Lage: an der Stelle des eingebauten AR-Magazins (gleiche Neigung, Oberkante im Schacht, Tiefe wie das Original).
# Point_Mount = Mitte des eingebauten Magazins (dort setzt das Spiel den Aufsatz hin), um SEAT_UP/SEAT_BACK versetzt,
# damit das Magazin tief genug im Schacht sitzt; Point_Front = Richtung Lauf.
# Eingabe stehend: lange Achse Z (Lippen oben), vorne = +X, Dicke = Y.
import bpy, sys, numpy as np
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
FBX, RIFLE, OUT = args[0], args[1], args[2]
PREFIX = FBX[:-4]
MAX_TRIS = 19500
# Sitz im Schacht: das Meshy-Magazin ist oben schmaler (nur die Lippen) – so weit tiefer in den Schacht (entlang des
# Magazins) bzw. nach hinten, damit der Körper im Schacht steckt und keine Lücke bleibt
SEAT_UP, SEAT_BACK = 0.07, 0.02

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=RIFLE)
ar = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith("Magazine"))
aco = np.array([ar.matrix_world @ v.co for v in ar.data.vertices])
for o in list(bpy.context.scene.objects):
    bpy.data.objects.remove(o)

c = aco.mean(0)
_, _, vt = np.linalg.svd(aco - c)
up = vt[0] if vt[0][2] > 0 else -vt[0]
up = np.array([0.0, up[1], up[2]]); up /= np.linalg.norm(up)
fwd = np.array([0.0, up[2], -up[1]])
h = (aco - c) @ up
top = aco[h > h.max() - 0.03].mean(0)
depth = np.ptp((aco - c) @ fwd)
mount = (aco.min(0) + aco.max(0)) / 2

bpy.ops.import_scene.fbx(filepath=FBX)
mag = next(o for o in bpy.context.scene.objects if o.type == "MESH")
for o in list(bpy.context.scene.objects):
    if o != mag:
        bpy.data.objects.remove(o)
bpy.context.view_layer.objects.active = mag
mag.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Material: Farbe, Normal, Metall+Rauheit (für glTF in einem Bild), Originalgröße
mat = bpy.data.materials.new("Magazine"); mat.use_nodes = True; nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
def tex(path, data=False):
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(path)
    if data: t.image.colorspace_settings.name = "Non-Color"
    return t
nt.links.new(tex(PREFIX + ".png").outputs[0], bsdf.inputs["Base Color"])
nm = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(tex(PREFIX + "_normal.png", True).outputs[0], nm.inputs["Color"]); nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
r = bpy.data.images.load(PREFIX + "_roughness.png"); m = bpy.data.images.load(PREFIX + "_metallic.png")
w, hgt = r.size
rp = np.array(r.pixels[:]).reshape(-1, 4); mp = np.array(m.pixels[:]).reshape(-1, 4)
mr = bpy.data.images.new("MetalRough", w, hgt); px = np.zeros((w * hgt, 4)); px[:, 1] = rp[:, 0]; px[:, 2] = mp[:, 0]; px[:, 3] = 1
mr.pixels = px.ravel().tolist(); mr.filepath_raw = OUT + "_mr.png"; mr.file_format = "PNG"; mr.save()
mrt = tex(OUT + "_mr.png", True); sep = nt.nodes.new("ShaderNodeSeparateColor")
nt.links.new(mrt.outputs[0], sep.inputs[0]); nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"]); nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
mag.data.materials.clear(); mag.data.materials.append(mat)

# Ausrichten an das AR-Magazin
mco = np.array([v.co for v in mag.data.vertices])
mtop = mco[mco[:, 2] > mco[:, 2].max() - 0.03].mean(0)
s = depth / np.ptp(mco[mco[:, 2] > mco[:, 2].max() - 0.4][:, 0])
Rs = np.eye(4)
Rs[:3, :3] = np.column_stack([fwd, np.cross(up, fwd), up]) * s
mag.data.transform(Matrix.Translation(Vector(top)) @ Matrix(Rs.tolist()) @ Matrix.Translation(-Vector(mtop)))
mag.data.update()
tris = sum(len(p.vertices) - 2 for p in mag.data.polygons)
print("Magazin: %d Dreiecke, Faktor %.3f" % (tris, s))

# In Stücke < MAX_TRIS teilen (entlang der Länge)
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.quads_convert_to_tris(); bpy.ops.object.mode_set(mode="OBJECT")
count = int(np.ceil(len(mag.data.polygons) / MAX_TRIS))
cen = np.zeros(len(mag.data.polygons) * 3); mag.data.polygons.foreach_get("center", cen)
proj = np.sort(cen.reshape(-1, 3) @ up)
cuts = [proj[int(len(proj) * k / count)] for k in range(1, count)]  # Grenzen entlang der Länge
for k in range(count - 1, 0, -1):
    n = len(mag.data.polygons)
    cen = np.zeros(n * 3); mag.data.polygons.foreach_get("center", cen)
    sel = (cen.reshape(-1, 3) @ up) >= cuts[k - 1]
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="DESELECT"); bpy.ops.object.mode_set(mode="OBJECT")
    mag.data.polygons.foreach_set("select", sel.tolist())
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.separate(type="SELECTED"); bpy.ops.object.mode_set(mode="OBJECT")
parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
parts.sort(key=lambda o: -max((o.matrix_world @ v.co) @ Vector(up) for v in o.data.vertices[:200]))
for i, o in enumerate(parts, 1):
    o.name = o.data.name = "Magazine_Ext_%02d" % i
    print(o.name, len(o.data.polygons))

def marker(name, pos):
    bpy.ops.mesh.primitive_cube_add(size=0.03, location=tuple(pos))
    mk = bpy.context.active_object
    mk.name = mk.data.name = name
# Marker statt Teile verschieben: Point_Mount landet im Spiel auf der Mitte des eingebauten Magazins
seat = mount - up * SEAT_UP + fwd * SEAT_BACK
marker("Point_Mount", seat)
marker("Point_Front", seat + np.array([0, 0.3, 0]))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True, export_animations=False)

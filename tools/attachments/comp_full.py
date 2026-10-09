# Kompensator (Mündungsaufsatz) in voller Meshy-Qualität für das Sturmgewehr vorbereiten:
#   python3 tools/attachments/comp_full.py <meshy.fbx> <art/sources/Rifle.glb> <ausgabe.glb>
# Neben der FBX müssen die Meshy-Texturen liegen (<name>.png, _roughness.png, _metallic.png, _normal.png optional).
#
# Nichts wird reduziert: alle Dreiecke und die Texturen in Originalgröße bleiben (Teile über 20.000 Dreiecke würden
# entlang der Länge geteilt). Nur gedreht, verschoben und gleichmäßig skaliert.
# Eingabe liegend: lange Achse X (Gewinde -X, Mündung +X), Ports oben (+Z).
# Lage: an der AR-Mündung, Körper überdeckt den eingebauten Mündungsfeuerdämpfer (DIAMETER etwas dicker als dieser).
# Point_Mount = Point_Muzzle des Gewehrs (dort setzt das Spiel den Aufsatz hin), Point_Muzzle = vorderes Ende.
import bpy, sys, numpy as np
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
FBX, RIFLE, OUT = args[0], args[1], args[2]
PREFIX = FBX[:-4]
MAX_TRIS = 19500
DIAMETER = 0.15   # Studs, Körper (AR-Mündungsfeuerdämpfer ca. 0,125)
REAR = 0.28       # so weit reicht der Kompensator hinter die Mündung (deckt den Mündungsfeuerdämpfer ab)
import os

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=RIFLE)
pts = {}
for o in bpy.context.scene.objects:
    if o.type == "MESH" and o.name.startswith("Point_"):
        co = np.array([o.matrix_world @ v.co for v in o.data.vertices])
        pts[o.name] = (co.min(0) + co.max(0)) / 2
muzzle = pts["Point_Muzzle"]
for o in list(bpy.context.scene.objects):
    bpy.data.objects.remove(o)
for me in list(bpy.data.meshes):
    bpy.data.meshes.remove(me)   # sonst heißen die neuen Marker "Point_Muzzle.001"

bpy.ops.import_scene.fbx(filepath=FBX)
comp = next(o for o in bpy.context.scene.objects if o.type == "MESH")
for o in list(bpy.context.scene.objects):
    if o != comp:
        bpy.data.objects.remove(o)
bpy.context.view_layer.objects.active = comp
comp.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

mat = bpy.data.materials.new("Compensator"); mat.use_nodes = True; nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
def tex(path, data=False):
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(path)
    if data: t.image.colorspace_settings.name = "Non-Color"
    return t
nt.links.new(tex(PREFIX + ".png").outputs[0], bsdf.inputs["Base Color"])
if os.path.exists(PREFIX + "_normal.png"):
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tex(PREFIX + "_normal.png", True).outputs[0], nm.inputs["Color"]); nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
r = bpy.data.images.load(PREFIX + "_roughness.png"); m = bpy.data.images.load(PREFIX + "_metallic.png")
w, hgt = r.size
rp = np.array(r.pixels[:]).reshape(-1, 4); mp = np.array(m.pixels[:]).reshape(-1, 4)
mr = bpy.data.images.new("MetalRough", w, hgt); px = np.zeros((w * hgt, 4)); px[:, 1] = rp[:, 0]; px[:, 2] = mp[:, 0]; px[:, 3] = 1
mr.pixels = px.ravel().tolist(); mr.filepath_raw = OUT + "_mr.png"; mr.file_format = "PNG"; mr.save()
mrt = tex(OUT + "_mr.png", True); sep = nt.nodes.new("ShaderNodeSeparateColor")
nt.links.new(mrt.outputs[0], sep.inputs[0]); nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"]); nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
comp.data.materials.clear(); comp.data.materials.append(mat)

# Gewinde-Ende in den Ursprung, lange Achse -> Laufrichtung (+Y im Gewehr), oben bleibt oben (+Z)
co = np.array([v.co for v in comp.data.vertices])
lo, hi = co.min(0), co.max(0)
s = DIAMETER / max(hi[1] - lo[1], hi[2] - lo[2])
rear = np.array([lo[0], (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2])
R = np.eye(4)
R[:3, :3] = np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]], float) * s   # X -> +Y, Y -> -X, Z -> Z
start = muzzle - np.array([0, REAR, 0])
comp.data.transform(Matrix.Translation(Vector(start)) @ Matrix(R.tolist()) @ Matrix.Translation(-Vector(rear)))
comp.data.update()
L = (hi[0] - lo[0]) * s
comp.name = comp.data.name = "Compensator"
tris = sum(len(p.vertices) - 2 for p in comp.data.polygons)
print("Kompensator: %d Dreiecke, Laenge %.3f, Durchmesser %.3f" % (tris, L, DIAMETER))
assert tris <= MAX_TRIS, "zu viele Dreiecke fuer ein Teil – wie mag_full.py teilen"

def marker(name, pos):
    bpy.ops.mesh.primitive_cube_add(size=0.03, location=tuple(pos))
    mk = bpy.context.active_object
    mk.name = mk.data.name = name
marker("Point_Mount", muzzle)
marker("Point_Muzzle", start + np.array([0, L, 0]))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True, export_animations=False)
os.remove(OUT + "_mr.png")  # steckt jetzt in der GLB

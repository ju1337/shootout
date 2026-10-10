# Griff-Aufsatz (z.B. VerticalGrip) in voller Meshy-Qualität für das Sturmgewehr vorbereiten:
#   python3 tools/attachments/grip_full.py <meshy.fbx> <art/sources/Rifle.glb> <ausgabe.glb> <Name> <Höhe> <vorn +1|-1>
# Name = Teilname in Studio, Höhe = Gesamthöhe in Studs (gleichmäßig skaliert), vorn = welche x-Richtung des
# Meshy-Modells zum Lauf zeigt. Eingabe stehend: Höhe = z (Schienenklemme oben), Schiene entlang x.
# Nichts wird reduziert (alle Dreiecke, Texturen in Originalgröße); nur gedreht, verschoben, gleichmäßig skaliert.
# Lage: Oberkante der Klemme an Point_LeftHand des Gewehrs (Unterseite des Handschutzes, dort hält die linke Hand),
# mittig unter dem Lauf. Point_Mount = Oberkante der Klemme (dort setzt das Spiel den Griff an), Point_Front = vorn.
import bpy, os, sys, numpy as np
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
FBX, RIFLE, OUT, NAME = args[0], args[1], args[2], args[3]
HEIGHT, FRONT = float(args[4]), float(args[5])
PREFIX = FBX[:-4]
MAX_TRIS = 19500

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=RIFLE)
pts = {}
for o in bpy.context.scene.objects:
    if o.type == "MESH" and o.name.startswith("Point_"):
        co = np.array([o.matrix_world @ v.co for v in o.data.vertices])
        pts[o.name] = (co.min(0) + co.max(0)) / 2
hand = pts["Point_LeftHand"]
for o in list(bpy.context.scene.objects):
    bpy.data.objects.remove(o)
for me in list(bpy.data.meshes):
    bpy.data.meshes.remove(me)

bpy.ops.import_scene.fbx(filepath=FBX)
part = next(o for o in bpy.context.scene.objects if o.type == "MESH")
for o in list(bpy.context.scene.objects):
    if o != part:
        bpy.data.objects.remove(o)
bpy.context.view_layer.objects.active = part
part.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

mat = bpy.data.materials.new(NAME); mat.use_nodes = True; nt = mat.node_tree
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
part.data.materials.clear(); part.data.materials.append(mat)

co = np.array([v.co for v in part.data.vertices])
lo, hi = co.min(0), co.max(0)
s = HEIGHT / (hi[2] - lo[2])
top = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, hi[2]])
R = np.eye(4)
R[:3, :3] = np.array([[0, -FRONT, 0], [FRONT, 0, 0], [0, 0, 1]], float) * s   # x*FRONT -> +Y (Lauf), z bleibt oben
part.data.transform(Matrix.Translation(Vector(hand)) @ Matrix(R.tolist()) @ Matrix.Translation(-Vector(top)))
part.data.update()
part.name = part.data.name = NAME
P = np.array([v.co for v in part.data.vertices])
tris = sum(len(p.vertices) - 2 for p in part.data.polygons)
print("%s: %d Dreiecke, Groesse %s Studs, Oberkante %.3f (LeftHand %.3f)" % (
    NAME, tris, np.round(P.max(0) - P.min(0), 3), P[:, 2].max(), hand[2]))
assert tris <= MAX_TRIS, "zu viele Dreiecke fuer ein Teil – wie mag_full.py teilen"

def marker(name, pos):
    bpy.ops.mesh.primitive_cube_add(size=0.02, location=tuple(pos))
    mk = bpy.context.active_object
    mk.name = mk.data.name = name
marker("Point_Mount", hand)
marker("Point_Front", hand + np.array([0, 0.2, 0]))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True, export_animations=False)
os.remove(OUT + "_mr.png")  # steckt jetzt in der GLB

# Laser-Aufsatz (Seitenmontage, PEQ-15-Stil) in voller Meshy-Qualität für das Sturmgewehr vorbereiten:
#   python3 tools/attachments/laser_full.py <meshy.fbx> <art/sources/Rifle.glb> <ausgabe.glb>
# Neben der FBX liegen die Meshy-Texturen (<name>.png, _normal.png, _roughness.png, _metallic.png).
# Nichts wird reduziert: alle Dreiecke (Meshy: ca. 900.000) und die Texturen in Originalgröße bleiben. Roblox erlaubt
# höchstens 20.000 Dreiecke pro Teil, deshalb wird der Laser entlang seiner Länge in Stücke Laser_01, _02 … geteilt.
# Eingabe: lange Achse x (Austrittsöffnung bei -x), Einstellräder oben (+z), Klemme hinten auf der -y-Seite.
# Lage: rechte Seite des Handschutzes, Klemme liegt an der Seitenfläche an (x = SIDE), Klemme mittig auf der
# Seitenfläche (Höhe AXIS_Z), Austrittsöffnung kurz hinter der Stirnseite (FRONT_AT).
# Point_Mount = Point_LeftHand des Gewehrs (dort setzt das Spiel Griff-Aufsätze an), Point_Front = Richtung nach vorn.
import bpy, os, sys, numpy as np
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
FBX, RIFLE, OUT = args[0], args[1], args[2]
NAME = "Laser"
PREFIX = FBX[:-4]
MAX_TRIS = 19500
SCALE = 0.22       # Studs pro Meshy-Einheit: 0,42 lang, 0,2 hoch (Handschutz 0,22 breit, 0,28 hoch)
SIDE = 0.108       # Seitenfläche des Handschutzes rechts (x 0,107-0,110 bei 1,85-2,10)
AXIS_Z = 0.525     # Mitte der Seitenfläche (Laufachse)
FRONT_AT = 2.33    # Austrittsöffnung (Stirnseite des Handschutzes 2,375-2,385)

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

# Klemme: Teil an der -y-Seite (Anlagefläche y min); Mitte ihrer Höhe -> AXIS_Z
n = len(part.data.vertices)
co = np.zeros(n * 3); part.data.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
lo, hi = co.min(0), co.max(0)
clamp = co[co[:, 1] < lo[1] + 0.15]
clamp_z = (clamp[:, 2].min() + clamp[:, 2].max()) / 2
# Drehung: -x (Austritt) -> +Y (vorn), -y (Klemme) -> -X (zur Waffe), z bleibt oben
R = np.eye(4)
R[:3, :3] = np.array([[0, 1, 0], [-1, 0, 0], [0, 0, 1]], float) * SCALE
anchor = np.array([lo[0], lo[1], clamp_z])              # Austrittsende, Anlagefläche, Mitte der Klemme
target = np.array([SIDE, FRONT_AT, AXIS_Z])
part.data.transform(Matrix.Translation(Vector(target)) @ Matrix(R.tolist()) @ Matrix.Translation(-Vector(anchor)))
part.data.update()
co = np.zeros(n * 3); part.data.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
print("Laser: %d Dreiecke, Groesse %s Studs, x %.3f..%.3f, vorn %.3f..%.3f, z %.3f..%.3f" % (
    len(part.data.polygons), np.round(co.max(0) - co.min(0), 3), co[:, 0].min(), co[:, 0].max(),
    co[:, 1].min(), co[:, 1].max(), co[:, 2].min(), co[:, 2].max()))

# In Stücke < MAX_TRIS teilen (entlang der Länge, gleich viele Dreiecke je Stück)
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.quads_convert_to_tris(); bpy.ops.object.mode_set(mode="OBJECT")
total = len(part.data.polygons)
count = int(np.ceil(total / MAX_TRIS))
cen = np.zeros(total * 3); part.data.polygons.foreach_get("center", cen)
proj = np.sort(cen.reshape(-1, 3)[:, 1])
cuts = [proj[int(len(proj) * k / count)] for k in range(1, count)]
for k in range(count - 1, 0, -1):
    t = len(part.data.polygons)
    cen = np.zeros(t * 3); part.data.polygons.foreach_get("center", cen)
    sel = cen.reshape(-1, 3)[:, 1] >= cuts[k - 1]
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="DESELECT"); bpy.ops.object.mode_set(mode="OBJECT")
    part.data.polygons.foreach_set("select", sel.tolist())
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.separate(type="SELECTED"); bpy.ops.object.mode_set(mode="OBJECT")
parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
def front(o):
    c = np.zeros(len(o.data.vertices) * 3); o.data.vertices.foreach_get("co", c); return c.reshape(-1, 3)[:, 1].mean()
parts.sort(key=lambda o: -front(o))
sizes = []
for i, o in enumerate(parts, 1):
    o.name = o.data.name = "%s_%02d" % (NAME, i)
    sizes.append(len(o.data.polygons))
print("%d Teile, je %d..%d Dreiecke, zusammen %d" % (len(parts), min(sizes), max(sizes), sum(sizes)))
assert max(sizes) <= MAX_TRIS and sum(sizes) == total

def marker(name, pos):
    bpy.ops.mesh.primitive_cube_add(size=0.02, location=tuple(pos))
    mk = bpy.context.active_object
    mk.name = mk.data.name = name
marker("Point_Mount", hand)
marker("Point_Front", hand + np.array([0, 0.2, 0]))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True, export_animations=False)
os.remove(OUT + "_mr.png")  # steckt jetzt in der GLB
print("->", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6))

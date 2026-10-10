# Lauf-Aufsatz (LongBarrel, ShortBarrel, HeavyBarrel) in voller Meshy-Qualität für das Sturmgewehr vorbereiten:
#   python3 tools/attachments/barrel_full.py <meshy.fbx> <art/sources/Rifle.glb> <ausgabe.glb> <Name> <Faktor>
#                                            <Mündung +1|-1> <Stufe> <Stufe vorn> [max. Radius im Handschutz]
# Name = Teilname in Studio, Faktor = Meshy-Einheiten -> Studs (gleichmäßig), Mündung = an welchem Ende (x) des
# Meshy-Modells die Mündung ist, Stufe = x-Stelle im Meshy-Modell (z.B. Übergang dick -> dünn), die genau auf
# "Stufe vorn" Studs vor dem Griff landet (Stirnseite des Handschutzes: 2,375-2,385).
# Nichts wird reduziert (alle Dreiecke, Texturen in Originalgröße); nur gedreht, verschoben, gleichmäßig skaliert.
# Der Lauf liegt auf der Laufachse des Gewehrs (Mitte des eingebauten Mündungsfeuerdämpfers); sein hinteres Ende
# steckt im Handschutz (innen ca. 0,09 Studs Radius – das Skript prüft, dass nichts durch die Wand ragt). Im Spiel
# wird der eingebaute Lauf (Skin_Body_Barrel, tools/attachments/rifle_barrel.py) ausgeblendet.
# Marker: Point_Mount = eingebaute Mündung (dort setzt das Spiel den Aufsatz an), Point_Front = Richtung nach vorn,
# Point_Muzzle = neue Mündung (dort sitzen Mündungsaufsätze, Mündungsfeuer und Leuchtspur).
import bpy, os, sys, numpy as np
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
FBX, RIFLE, OUT, NAME = args[0], args[1], args[2], args[3]
SCALE, MUZZLE_END, STEP, STEP_AT = float(args[4]), float(args[5]), float(args[6]), float(args[7])
PREFIX = FBX[:-4]
MAX_TRIS = 19500
INNER = float(args[8]) if len(args) > 8 else 0.088  # Innenradius des Handschutzes (0,089-0,1); bis 0,108 steckt ein
                  # Teil noch in der Wand (außen 0,112) und ist nur durch die Schlitze zu sehen
FACE = 2.385      # Stirnseite des Handschutzes
INNER_CUT = 1.95  # bis hier ist der eingebaute Lauf ausgeblendet (rifle_barrel.py) – der neue muss weiter zurück reichen

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

# Achse: Mitte der Querschnitte (y, z); x * MUZZLE_END -> nach vorn (+Y im Gewehr), oben bleibt oben (+Z)
co = np.array([v.co for v in part.data.vertices])
lo, hi = co.min(0), co.max(0)
axis = np.array([STEP, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2])
R = np.eye(4)
R[:3, :3] = np.array([[0, -MUZZLE_END, 0], [MUZZLE_END, 0, 0], [0, 0, 1]], float) * SCALE
target = np.array([muzzle[0], STEP_AT, muzzle[2]])
part.data.transform(Matrix.Translation(Vector(target)) @ Matrix(R.tolist()) @ Matrix.Translation(-Vector(axis)))
part.data.update()
part.name = part.data.name = NAME
P = np.array([v.co for v in part.data.vertices])
tip = P[:, 1].max()
radius = np.hypot(P[:, 0] - muzzle[0], P[:, 2] - muzzle[2])
inside = P[:, 1] < FACE - 0.005
tris = sum(len(p.vertices) - 2 for p in part.data.polygons)
print("%s: %d Dreiecke, Laenge %.3f, hinten %.3f, Muendung %.3f (eingebaut %.3f), dickste Stelle %.3f, im Handschutz max. Radius %.4f (Wand %.3f)" % (
    NAME, tris, P[:, 1].max() - P[:, 1].min(), P[:, 1].min(), tip, muzzle[1], 2 * radius.max(),
    radius[inside].max() if inside.any() else 0, INNER))
assert tris <= MAX_TRIS, "zu viele Dreiecke fuer ein Teil – wie mag_full.py teilen"
assert not inside.any() or radius[inside].max() < INNER, "Lauf ragt im Handschutz durch die Wand"
assert P[:, 1].min() < INNER_CUT - 0.05, "Lauf endet vor dem Rest des eingebauten Laufs (Lücke im Handschutz)"

def marker(name, pos):
    bpy.ops.mesh.primitive_cube_add(size=0.03, location=tuple(pos))
    mk = bpy.context.active_object
    mk.name = mk.data.name = name
marker("Point_Mount", muzzle)
marker("Point_Front", muzzle + np.array([0, 0.3, 0]))
marker("Point_Muzzle", np.array([muzzle[0], tip, muzzle[2]]))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True, export_animations=False)
os.remove(OUT + "_mr.png")  # steckt jetzt in der GLB

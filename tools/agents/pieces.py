# Meshy-Charakter OHNE Skelett (statische GLB, Arme hängen) in 15 starre Teile <Körperteil>_Suit zerlegen, wie es
# AgentModels für Modelle ohne Rig erwartet (docs/agenten-modelle.md). Gleichmäßig auf 5,2 Studs skaliert, Füße auf 0,
# Blick nach -Z. Dreiecke an einer Schnittkante gehören zu beiden Teilen (keine Löcher beim Bewegen). Textur bleibt.
#
#   python3 tools/agents/pieces.py <meshy.glb> <ausgabe.glb> [NECK WAIST HIP ELBOW WRIST KNEE ANKLE ARM_X]
#
# Schnitthöhen in Studs (nach dem Skalieren) für den Scout: Hals 3.87, Gürtel 2.35, Hüfte 1.95, Ellbogen 3.05,
# Handschuh 2.38, Knie 1.16, Stiefel 0.5; Arme ab |x| 0.85. Für andere Modelle anpassen (Vorschau rendern!).
import bpy, bmesh, sys, numpy as np
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
SRC, OUT = args[0], args[1]
cuts = [float(a) for a in args[2:]] or [3.87, 2.35, 1.95, 3.05, 2.38, 1.16, 0.5, 0.85]
H = 5.2
NECK, WAIST, HIP, ELBOW, WRIST, KNEE, ANKLE, ARM_X = cuts
RINGS = 3

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
src = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
for o in bpy.context.scene.objects: o.select_set(o == src)
bpy.context.view_layer.objects.active = src
src.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = np.array([v.co for v in src.data.vertices]); lo, hi = co.min(0), co.max(0)
s = H / (hi[2] - lo[2])
co = (co - [(lo[0]+hi[0])/2, (lo[1]+hi[1])/2, lo[2]]) * s
src.data.vertices.foreach_set("co", co.ravel()); src.data.update()

me = src.data
nf = len(me.polygons)
cen = np.zeros(nf*3); me.polygons.foreach_get("center", cen); cen = cen.reshape(-1, 3)
x, z = cen[:, 0], cen[:, 2]
def label(X, Z):
    side = "Right" if X < 0 else "Left"
    if Z >= NECK: return "Head"
    if abs(X) >= ARM_X and Z >= 1.85:
        return side + ("UpperArm" if Z >= ELBOW else "LowerArm" if Z >= WRIST else "Hand")
    if Z >= WAIST: return "UpperTorso"
    if Z >= HIP: return "LowerTorso"
    return side + ("UpperLeg" if Z >= KNEE else "LowerLeg" if Z >= ANKLE else "Foot")
lab = [label(X, Z) for X, Z in zip(x, z)]
vco = np.array([v.co for v in me.vertices])
vlab = [label(X, Z) for X, Z in zip(vco[:, 0], vco[:, 2])]
fparts = [set([lab[i]]) | {vlab[v] for v in p.vertices} for i, p in enumerate(me.polygons)]
names = sorted(set(lab))
parts = {}
for n in names:
    keep = np.array([n in fp for fp in fparts])
    own = sum(1 for l in lab if l == n)
    obj = src.copy(); obj.data = src.data.copy(); bpy.context.scene.collection.objects.link(obj)
    obj.name = obj.data.name = n + "_Suit"
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.scene.objects: o.select_set(o == obj)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="DESELECT"); bpy.ops.object.mode_set(mode="OBJECT")
    obj.data.polygons.foreach_set("select", (~keep).tolist())
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.delete(type="FACE"); bpy.ops.object.mode_set(mode="OBJECT")
    parts[n] = obj
    print("%-14s %6d Dreiecke (+%d Überlappung)" % (n, len(obj.data.polygons), len(obj.data.polygons) - own))
bpy.data.objects.remove(src)
bpy.ops.mesh.primitive_cube_add(size=0.05, location=(0, 0, 0)); r = bpy.context.active_object
r.name = r.data.name = "Point_Root"
m = bpy.data.materials.new("Marker"); m.diffuse_color = (1, 0, 1, 1); r.data.materials.append(m)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True, export_animations=False)

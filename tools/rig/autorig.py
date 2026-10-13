# Statischen Meshy-Agenten (ganzes Mesh, Arme hängen) in einen echten R15-Charakter mit Skelett und Skinning umbauen –
# statt 15 starrer Teile (tools/agents/pieces.py), die an den Gelenken aufreißen.
#
#   python3 tools/rig/autorig.py <ganz.glb> <out.glb|out.fbx> [NECK WAIST HIP ELBOW WRIST KNEE ANKLE ARM_X [BLEND [ARM_Z [HEAD_X]]]]
#
# Fehlt die Meshy-GLB: python3 tools/agents/merge_pieces.py <teile.glb> <ganz.glb>. Schnitthöhen wie bei pieces.py
# (Scout: 3.87 2.35 1.95 3.05 2.38 1.16 0.5 0.85). Das Modell wird auf 5,2 Studs skaliert, Füße auf 0, Blick nach -Y.
#
# Gewichte: dieselben Körperteile wie pieces.py, aber an jeder Schnittkante weich überblendet (Gauß-Kern mit Radius
# BLEND, Standard 0.16): eine Ecke 5 cm über dem Ellbogen folgt z.B. zu 70 % dem Oberarm und zu 30 % dem Unterarm.
# Dadurch biegt sich die Hülle an Ellbogen, Knie, Hüfte und Schulter, statt aufzureißen. Arm und Rumpf/Bein mischen
# nur an der Schulter (hängende Hände neben der Hüfte bleiben getrennt), die Innenseite der Arme gehört zum Arm.
# Höchstens 4 Knochen je Ecke (Roblox). Export wie tools/rig/meshy_to_r15.py: Knochen senkrecht mit Roll 0,
# Mesh in die 15 Teile geteilt (jedes an alle Knochen gebunden), HumanoidRootPart-Box, FBX in Studs.
# In Studio: Import 3D, Rig General > Rig Type R15, Einheit Stud.
import os, sys
# tools/rig/inspect.py würde sonst das Standardmodul inspect verdecken (bpy stürzt beim Import ab)
sys.path = [x for x in sys.path if os.path.abspath(x or ".") != os.path.dirname(os.path.abspath(__file__))]
import bpy, bmesh
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
SRC, OUT = args[0], args[1]
cuts = [float(a) for a in args[2:]] or [3.87, 2.35, 1.95, 3.05, 2.38, 1.16, 0.5, 0.85]
NECK, WAIST, HIP, ELBOW, WRIST, KNEE, ANKLE, ARM_X = cuts[:8]
BLEND = cuts[8] if len(cuts) > 8 else 0.16
ARM_Z = cuts[9] if len(cuts) > 9 else 1.85
HEAD_X = cuts[10] if len(cuts) > 10 else float("inf")
ARM_IN = 0.2
H = 5.2
PARTS = ["Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
         "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg",
         "RightFoot"]
PARENT = {"LowerTorso": "HumanoidRootPart", "UpperTorso": "LowerTorso", "Head": "UpperTorso",
          "LeftUpperArm": "UpperTorso", "LeftLowerArm": "LeftUpperArm", "LeftHand": "LeftLowerArm",
          "RightUpperArm": "UpperTorso", "RightLowerArm": "RightUpperArm", "RightHand": "RightLowerArm",
          "LeftUpperLeg": "LowerTorso", "LeftLowerLeg": "LeftUpperLeg", "LeftFoot": "LeftLowerLeg",
          "RightUpperLeg": "LowerTorso", "RightLowerLeg": "RightUpperLeg", "RightFoot": "RightLowerLeg"}
IDX = {p: i for i, p in enumerate(PARTS)}
LIMB = np.array(["Arm" in p or "Hand" in p for p in PARTS])


def label(X, Z):
    """Körperteil je Punkt wie pieces.py (vektorisiert), als Index in PARTS."""
    X, Z = np.asarray(X, float), np.asarray(Z, float)
    left = X >= 0
    out = np.empty(X.shape, int)
    arm = (np.abs(X) >= ARM_X) & (Z >= ARM_Z)
    side = lambda l, r: np.where(left, IDX[l], IDX[r])  # noqa: E731
    leg = np.where(Z >= KNEE, side("LeftUpperLeg", "RightUpperLeg"),
                   np.where(Z >= ANKLE, side("LeftLowerLeg", "RightLowerLeg"), side("LeftFoot", "RightFoot")))
    out[:] = np.where(Z >= WAIST, IDX["UpperTorso"], np.where(Z >= HIP, IDX["LowerTorso"], leg))
    armlab = np.where(Z >= ELBOW, side("LeftUpperArm", "RightUpperArm"),
                      np.where(Z >= WRIST, side("LeftLowerArm", "RightLowerArm"), side("LeftHand", "RightHand")))
    out = np.where(arm, armlab, out)
    out = np.where((Z >= NECK) & (np.abs(X) < HEAD_X), IDX["Head"], out)
    return out


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.startswith("Point")]
for o in list(bpy.context.scene.objects):
    if o not in meshes:
        bpy.data.objects.remove(o)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
mesh = bpy.context.view_layer.objects.active
mesh.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = mesh.data
co = np.array([v.co for v in me.vertices])
lo, hi = co.min(0), co.max(0)
s = H / (hi[2] - lo[2])
co = (co - [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]]) * s
me.vertices.foreach_set("co", co.ravel())
me.update()
mesh.name = "Body"

# ---- Gewichte ----
X, Z = co[:, 0], co[:, 2]
own = label(X, Z)
nrm = np.array([v.normal for v in me.vertices])
inner = (np.abs(X) >= ARM_X - ARM_IN) & (np.abs(X) < ARM_X) & (Z >= ARM_Z) & (Z < NECK) & (nrm[:, 0] * np.sign(X) < -0.3)
own = np.where(inner, label(np.sign(X) * ARM_X, Z), own)
W = np.zeros((len(co), len(PARTS)))
k = 9
g = np.linspace(-BLEND, BLEND, k)
for dx in g:
    for dz in g:
        r2 = (dx * dx + dz * dz) / (BLEND * BLEND)
        if r2 > 1:
            continue
        w = np.exp(-3 * r2)
        lab = label(X + dx, Z + dz)
        # Arm <-> Rumpf/Bein nur an der Schulter (über dem Ellbogen) und nicht an der Arm-Innenseite
        ok = (LIMB[lab] == LIMB[own]) | ((Z >= ELBOW) & ~inner)
        W[np.arange(len(co))[ok], lab[ok]] += w
W[np.arange(len(co)), own] += 1e-6
# höchstens 4 Knochen, normieren, kleine Anteile weg
order = np.argsort(-W, axis=1)
W2 = np.zeros_like(W)
rows = np.arange(len(co))[:, None]
W2[rows, order[:, :4]] = W[rows, order[:, :4]]
W2[W2 < 0.02 * W2.sum(1, keepdims=True)] = 0
W2 /= W2.sum(1, keepdims=True)
groups = {p: mesh.vertex_groups.new(name=p) for p in PARTS}
for j, p in enumerate(PARTS):
    idx = np.nonzero(W2[:, j] > 0)[0]
    for i in idx:
        groups[p].add([int(i)], float(W2[i, j]), "REPLACE")
blended = int((W2 > 0).sum(1).__gt__(1).sum())
print("REPORT weights: %d Ecken, %d davon an mehreren Knochen" % (len(co), blended))

# Flächen unter dem Ellbogen, die Arm und Rumpf/Bein verbinden (z.B. Fingerspitzen, die bis an den Oberschenkel
# reichen), würden beim Heben des Arms zu langen Spießen: abtrennen und ganz dem Arm (in der Arm-Spalte) bzw. dem
# Rumpf/Bein geben
limb_groups = {groups[p].index for p in PARTS if LIMB[IDX[p]]}
bm = bmesh.new(); bm.from_mesh(me)
dl = bm.verts.layers.deform.verify()


def is_limb(v):
    d = v[dl]
    return bool(d) and max(d.items(), key=lambda kv: kv[1])[0] in limb_groups


cross = [f for f in bm.faces if f.calc_center_median().z < ELBOW and len({is_limb(v) for v in f.verts}) > 1]
for f0 in cross:
    out = bmesh.ops.split(bm, geom=[f0], use_only_faces=True)["geom"]
    f = next(e for e in out if isinstance(e, bmesh.types.BMFace))
    flags = [is_limb(v) for v in f.verts]
    major = abs(f.calc_center_median().x) >= ARM_X - 0.02   # in der Arm-Spalte: Hand/Arm, sonst Rumpf/Bein
    donors = [v for v, fl in zip(f.verts, flags) if fl == major]
    for v, fl in zip(f.verts, flags):
        if fl != major:
            donor = min(donors, key=lambda d: (d.co - v.co).length)
            v[dl].clear()
            for gidx, w in donor[dl].items():
                v[dl][gidx] = w
bm.to_mesh(me); bm.free()
print("REPORT %d Flächen zwischen Arm und Rumpf/Bein (unter dem Ellbogen) abgetrennt" % len(cross))
gi = {g.index: IDX[g.name] for g in mesh.vertex_groups}
W2 = np.zeros((len(me.vertices), len(PARTS)))
for v in me.vertices:
    for ge in v.groups:
        W2[v.index, gi[ge.group]] = ge.weight


# ---- Gelenke ----
def column(zc, arm, band=0.04):
    pts = []
    for sgn in (1, -1):
        sx = X * sgn
        m = (np.abs(Z - zc) < band) & ((sx >= ARM_X) if arm else ((sx > 0.02) & (sx < ARM_X)))
        if not m.any():
            m = (np.abs(Z - zc) < band * 3) & ((sx >= ARM_X) if arm else ((sx > 0.02) & (sx < ARM_X)))
        c = co[m]
        pts.append(((c[:, 0].min() + c[:, 0].max()) / 2 * sgn, (c[:, 1].min() + c[:, 1].max()) / 2))
    return (pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2


torso = co[(np.abs(X) < ARM_X) & (np.abs(Z - WAIST) < 0.1)]
yc = (torso[:, 1].min() + torso[:, 1].max()) / 2
arm_top = Z[LIMB[own]].max()
J = {}
J["LowerTorso"] = Vector((0, yc, HIP))
J["UpperTorso"] = Vector((0, yc, WAIST))
J["Head"] = Vector((0, yc, NECK))
sx, sy = column(arm_top - 0.35, True)
ex, ey = column(ELBOW, True)
wx, wy = column(WRIST, True)
hx, hy = column(ARM_Z + 0.1, True)
lx, ly = column(KNEE + 0.35, False)
kx, ky = column(KNEE, False)
ax, ay = column(ANKLE + 0.15, False)
toe_y = co[(Z < ANKLE) & (np.abs(X) < ARM_X)][:, 1].min()
for side, sgn in (("Left", 1), ("Right", -1)):
    J[side + "UpperArm"] = Vector((sgn * (ARM_X + 0.2), sy, arm_top - 0.35))
    J[side + "LowerArm"] = Vector((sgn * ex, ey, ELBOW))
    J[side + "Hand"] = Vector((sgn * wx, wy, WRIST))
    J[side + "UpperLeg"] = Vector((sgn * lx, ly, HIP - 0.1))
    J[side + "LowerLeg"] = Vector((sgn * kx, ky, KNEE))
    J[side + "Foot"] = Vector((sgn * ax, ay, ANKLE))
for p in PARTS:
    print("REPORT joint %-14s (%6.3f %6.3f %6.3f)" % (p, *J[p]))

# ---- Skelett (wie meshy_to_r15: senkrecht, Roll 0) ----
arm_data = bpy.data.armatures.new("Armature")
arm = bpy.data.objects.new("Armature", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones
root = eb.new("Root"); root.head = (0, 0, 0); root.tail = (0, 0, 0.5)
hrp = eb.new("HumanoidRootPart"); hrp.head = J["LowerTorso"]; hrp.tail = J["LowerTorso"] + Vector((0, 0, 0.5))
hrp.parent = root
bones = {"HumanoidRootPart": hrp}
for p in PARTS:
    b = eb.new(p)
    b.head = J[p]
    b.tail = J[p] + Vector((0, 0, 0.3))
    b.roll = 0
    bones[p] = b
for p in PARTS:
    bones[p].parent = bones[PARENT[p]]
    bones[p].use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
mesh.modifiers.new("Armature", "ARMATURE").object = arm

# ---- in 15 Teile trennen (Fläche geht an den Knochen mit dem höchsten Gewicht ihrer Ecken) ----
best = np.argmax(W2, axis=1)
fv = [list(p.vertices) for p in me.polygons]
face_part = [np.bincount(best[v], minlength=len(PARTS)).argmax() for v in fv]
parts = {}
for j, p in enumerate(PARTS):
    o = mesh.copy(); o.data = mesh.data.copy(); o.name = o.data.name = p
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new(); bm.from_mesh(o.data); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if face_part[f.index] != j], context="FACES")
    bm.to_mesh(o.data); bm.free()
    parts[p] = o
bpy.data.objects.remove(mesh)

bpy.ops.mesh.primitive_cube_add(size=1, location=J["LowerTorso"] + Vector((0, 0, 0.3)))
box = bpy.context.object; box.name = box.data.name = "HumanoidRootPart"
box.scale = (2, 1, 2)
bpy.ops.object.transform_apply(scale=True)
vg = box.vertex_groups.new(name="HumanoidRootPart"); vg.add([v.index for v in box.data.vertices], 1.0, "REPLACE")
box.modifiers.new("Armature", "ARMATURE").object = arm
if parts["LowerTorso"].data.materials:
    box.data.materials.append(parts["LowerTorso"].data.materials[0])
for o in list(parts.values()) + [box]:
    o.parent = arm

for p, o in parts.items():
    print("REPORT part %-14s %6d Dreiecke" % (p, sum(len(f.vertices) - 2 for f in o.data.polygons)))

bpy.ops.object.select_all(action="DESELECT")
for o in [arm, box, *parts.values()]:
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
if OUT.endswith(".blend"):
    bpy.ops.wm.save_as_mainfile(filepath=OUT)
elif OUT.endswith(".glb"):   # GLB behält alle PBR-Maps (Farbe, Normal, Metall/Rauheit), FBX nur Farbe und Normal
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                              export_skins=True, export_animations=False, export_apply=False)
else:
    bpy.ops.export_scene.fbx(
        filepath=OUT, use_selection=True, object_types={"ARMATURE", "MESH"},
        add_leaf_bones=False, bake_anim=False, path_mode="COPY", embed_textures=True,
        apply_scale_options="FBX_SCALE_UNITS", mesh_smooth_type="FACE", use_armature_deform_only=False,
    )
print("REPORT exported", OUT)

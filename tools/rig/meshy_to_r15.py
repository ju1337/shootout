# Baut einen Meshy-AI-Charakter (Mixamo-ähnliche Knochen) in einen Roblox-R15-Charakter um.
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/rig/meshy_to_r15.py -- <in.fbx> <out.fbx> [preview.png]
#
# Ergebnis: Root > HumanoidRootPart > LowerTorso > ... (15 R15-Knochen), das Mesh ist in 15 Teile mit den
# R15-Namen geteilt (plus HumanoidRootPart-Box), jedes Teil bleibt an alle Knochen gebunden (keine Risse an den Nähten).
# Arme werden in eine leichte A-Pose gebracht, weil Roblox-Animationen hängende Arme erwarten.

import bpy, bmesh, math, sys
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
PREVIEW = argv[2] if len(argv) > 2 else None

TARGET_HEIGHT = 5.3      # in Studs, wenn im Importer „Stud“ als Einheit gewählt wird
ARM_SPREAD_DEG = 8       # Winkel der Oberarme zur Senkrechten nach dem Umposen

# Meshy-Knochen -> R15-Teil (Gewichte werden zusammengelegt)
MERGE = {
    "Hips": "LowerTorso", "Spine02": "UpperTorso",  # Taille tief: die ganze Weste gehört zur Brust
    "Spine01": "UpperTorso", "Spine": "UpperTorso",
    "LeftShoulder": "UpperTorso", "RightShoulder": "UpperTorso",
    "neck": "Head", "Head": "Head",
    "LeftArm": "LeftUpperArm", "LeftForeArm": "LeftLowerArm", "LeftHand": "LeftHand",
    "RightArm": "RightUpperArm", "RightForeArm": "RightLowerArm", "RightHand": "RightHand",
    "LeftUpLeg": "LeftUpperLeg", "LeftLeg": "LeftLowerLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftFoot",
    "RightUpLeg": "RightUpperLeg", "RightLeg": "RightLowerLeg", "RightFoot": "RightFoot", "RightToeBase": "RightFoot",
}
# R15-Knochen: (Elternknochen, Meshy-Knochen, dessen Kopf das Gelenk ist)
R15 = {
    "LowerTorso": ("HumanoidRootPart", "Hips"),
    "UpperTorso": ("LowerTorso", "Spine02"),
    "Head": ("UpperTorso", "neck"),
    "LeftUpperArm": ("UpperTorso", "LeftArm"), "LeftLowerArm": ("LeftUpperArm", "LeftForeArm"), "LeftHand": ("LeftLowerArm", "LeftHand"),
    "RightUpperArm": ("UpperTorso", "RightArm"), "RightLowerArm": ("RightUpperArm", "RightForeArm"), "RightHand": ("RightLowerArm", "RightHand"),
    "LeftUpperLeg": ("LowerTorso", "LeftUpLeg"), "LeftLowerLeg": ("LeftUpperLeg", "LeftLeg"), "LeftFoot": ("LeftLowerLeg", "LeftFoot"),
    "RightUpperLeg": ("LowerTorso", "RightUpLeg"), "RightLowerLeg": ("RightUpperLeg", "RightLeg"), "RightFoot": ("RightLowerLeg", "RightFoot"),
}
PARTS = list(R15)


def select_only(*objs):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
arm.animation_data_clear()
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)

# 1) Transformationen anwenden und auf Zielgröße skalieren (Füße auf den Boden)
select_only(arm, mesh)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
zs = [(mesh.matrix_world @ v.co).z for v in mesh.data.vertices]
s = TARGET_HEIGHT / (max(zs) - min(zs))
arm.scale = (s, s, s)
arm.location.z = -min(zs) * s
select_only(arm, mesh)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# 2) Arme absenken, Pose als neue Ruhepose übernehmen
select_only(arm)
bpy.ops.object.mode_set(mode="POSE")
for side, sign in (("Left", 1), ("Right", -1)):
    pb = arm.pose.bones[side + "Arm"]
    cur = (pb.tail - pb.head).normalized()
    a = math.radians(ARM_SPREAD_DEG)
    want = Vector((sign * math.sin(a), cur.y, -math.cos(a))).normalized()
    rot = cur.rotation_difference(want).to_matrix().to_4x4()
    head = pb.head.copy()
    pb.matrix = Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ pb.matrix
    bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode="OBJECT")
select_only(mesh)
mod = next(m for m in mesh.modifiers if m.type == "ARMATURE")
bpy.ops.object.modifier_apply(modifier=mod.name)
select_only(arm)
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode="OBJECT")

# 3) Gewichte auf R15-Gruppen zusammenlegen
vg = {g.name: g for g in mesh.vertex_groups}
new = {p: mesh.vertex_groups.new(name="_" + p) for p in PARTS}
for v in mesh.data.vertices:
    acc = {}
    for ge in v.groups:
        name = mesh.vertex_groups[ge.group].name
        if name in MERGE:
            acc[MERGE[name]] = acc.get(MERGE[name], 0.0) + ge.weight
    tot = sum(acc.values())
    for p, w in acc.items():
        if tot > 0:
            new[p].add([v.index], w / tot, "REPLACE")
for g in list(mesh.vertex_groups):
    if not g.name.startswith("_"):
        mesh.vertex_groups.remove(g)
for g in mesh.vertex_groups:
    g.name = g.name[1:]

# 4) Skelett neu aufbauen: alle Knochen senkrecht, Roll 0 (achsenparallel wie das Roblox-Standard-Rig)
select_only(arm)
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
joint = {p: eb[src].head.copy() for p, (_, src) in R15.items()}
tops = {"UpperTorso": eb["Spine"].tail.z, "Head": eb["head_end"].tail.z}
for b in list(eb):
    eb.remove(b)
root = eb.new("Root"); root.head = (0, 0, 0); root.tail = (0, 0, 0.5)
hrp = eb.new("HumanoidRootPart"); hrp.head = joint["LowerTorso"].copy(); hrp.tail = hrp.head + Vector((0, 0, 0.5)); hrp.parent = root
bones = {"HumanoidRootPart": hrp}
for p in PARTS:
    b = eb.new(p)
    b.head = joint[p]
    b.tail = joint[p] + Vector((0, 0, 0.3))
    b.roll = 0
    bones[p] = b
for p, (parent, _) in R15.items():
    bones[p].parent = bones[parent]
    bones[p].use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
mesh.modifiers.new("Armature", "ARMATURE").object = arm

# 5) Mesh in die 15 Teile trennen (Fläche geht an den Knochen mit dem höchsten Gewicht ihrer Ecken)
gi = {g.index: g.name for g in mesh.vertex_groups}
best = []
for v in mesh.data.vertices:
    w = {}
    for ge in v.groups:
        w[gi[ge.group]] = ge.weight
    best.append(max(w, key=w.get) if w else "LowerTorso")
face_part = []
for f in mesh.data.polygons:
    votes = {}
    for vi in f.vertices:
        votes[best[vi]] = votes.get(best[vi], 0) + 1
    face_part.append(max(votes, key=votes.get))

parts = {}
for p in PARTS:
    o = mesh.copy(); o.data = mesh.data.copy(); o.name = p; o.data.name = p
    bpy.context.collection.objects.link(o)
    bm = bmesh.new(); bm.from_mesh(o.data); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if face_part[f.index] != p], context="FACES")
    bm.to_mesh(o.data); bm.free()
    parts[p] = o
bpy.data.objects.remove(mesh)

# HumanoidRootPart-Box (unsichtbar im Spiel, wird vom Importer erwartet)
lt = [parts["LowerTorso"].matrix_world @ v.co for v in parts["LowerTorso"].data.vertices]
c = joint["LowerTorso"]
bpy.ops.mesh.primitive_cube_add(size=1, location=c)
box = bpy.context.object; box.name = "HumanoidRootPart"; box.data.name = "HumanoidRootPart"
box.scale = (TARGET_HEIGHT * 0.38, TARGET_HEIGHT * 0.19, TARGET_HEIGHT * 0.38)
bpy.ops.object.transform_apply(scale=True)
g = box.vertex_groups.new(name="HumanoidRootPart"); g.add([v.index for v in box.data.vertices], 1.0, "REPLACE")
box.modifiers.new("Armature", "ARMATURE").object = arm
if parts["LowerTorso"].data.materials:
    box.data.materials.append(parts["LowerTorso"].data.materials[0])

for o in list(parts.values()) + [box]:
    o.parent = arm
    o.matrix_parent_inverse = arm.matrix_world.inverted()

# Bericht
print("REPORT bones", [b.name for b in arm.data.bones])
for p, o in parts.items():
    print("REPORT part", p, "tris", sum(len(f.vertices) - 2 for f in o.data.polygons))
print("REPORT height", round(max((o.matrix_world @ v.co).z for o in parts.values() for v in o.data.vertices), 3))

# 6) Export
select_only(arm, box, *parts.values())
bpy.ops.export_scene.fbx(
    filepath=OUT, use_selection=True, object_types={"ARMATURE", "MESH"},
    add_leaf_bones=False, bake_anim=False, path_mode="COPY", embed_textures=True,
    apply_scale_options="FBX_SCALE_UNITS",  # 1 Blender-Einheit = 1 Stud in der Datei (Standard rechnet in cm um: x100)
    mesh_smooth_type="FACE", use_armature_deform_only=False,
)
print("REPORT exported", OUT)

# 7) Testbild: Knochen bewegen und rendern (vorne Ruhepose, daneben bewegt)
if PREVIEW:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 1200, 900
    select_only(arm)
    bpy.ops.object.mode_set(mode="POSE")
    pose = {"LeftUpperArm": (0, -70, 0), "RightUpperArm": (-80, 0, 0), "RightLowerArm": (-60, 0, 0),
            "LeftUpperLeg": (-50, 0, 0), "LeftLowerLeg": (60, 0, 0), "Head": (0, 0, 35), "UpperTorso": (0, 0, -20)}
    for n, (x, y, z) in pose.items():
        pb = arm.pose.bones[n]; pb.rotation_mode = "XYZ"
        pb.rotation_euler = (math.radians(x), math.radians(y), math.radians(z))
    bpy.ops.object.mode_set(mode="OBJECT")
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.collection.objects.link(cam)
    cam.location = (TARGET_HEIGHT * 0.9, -TARGET_HEIGHT * 1.6, TARGET_HEIGHT * 0.55)
    cam.rotation_euler = (math.radians(85), 0, math.radians(30))
    sc.camera = cam
    box.hide_render = True
    sc.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    print("REPORT preview", PREVIEW)

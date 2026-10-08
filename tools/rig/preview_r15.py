# Lädt eine R15-FBX und rendert sie von vorne: links Ruhepose, rechts mit bewegten Knochen.
#   Blender -b --python tools/rig/preview_r15.py -- <in.fbx> <out_prefix>
import bpy, math, sys

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=SRC)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
print("REPORT meshes", sorted(o.name for o in meshes))
print("REPORT bones", [b.name for b in arm.data.bones])
for o in meshes:
    if o.name == "HumanoidRootPart":
        o.hide_render = True

sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "TEXTURE"
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.55, 0.6, 0.65)
sc.render.resolution_x, sc.render.resolution_y = 700, 900
sc.view_settings.exposure = 1.5

zs = [(o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices]
h = max(zs) - min(zs)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.data.ortho_scale = h * 1.35
cam.location = (0, -h * 3, min(zs) + h / 2)
cam.rotation_euler = (math.radians(90), 0, 0)
sc.camera = cam


def render(name):
    sc.render.filepath = f"{OUT}_{name}.png"
    bpy.ops.render.render(write_still=True)
    print("REPORT render", sc.render.filepath)


render("rest")
# Pose in Weltachsen: Arm links seitlich hoch, rechter Arm nach vorne, Knie anheben, Kopf drehen
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
pose = {"LeftUpperArm": (2, 75), "RightUpperArm": (0, 70), "RightLowerArm": (0, 60),
        "LeftUpperLeg": (0, 60), "LeftLowerLeg": (0, -70), "Head": (1, 40), "UpperTorso": (1, 20)}
for n, (axis, deg) in pose.items():
    pb = arm.pose.bones[n]; pb.rotation_mode = "XYZ"
    e = [0.0, 0.0, 0.0]; e[axis] = math.radians(deg)
    pb.rotation_euler = e
bpy.ops.object.mode_set(mode="OBJECT")
render("posed")

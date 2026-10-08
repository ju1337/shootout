import bpy, sys
argv = sys.argv[sys.argv.index("--")+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=argv[0])
for o in bpy.data.objects:
    print("OBJ", o.name, o.type, "parent=", o.parent.name if o.parent else None, "scale", tuple(round(s,4) for s in o.scale), "rot", tuple(round(r,3) for r in o.rotation_euler), "dims", tuple(round(d,3) for d in o.dimensions))
    if o.type == "MESH":
        print("  verts", len(o.data.vertices), "groups", [g.name for g in o.vertex_groups], "mods", [(m.type, getattr(m,'object',None) and m.object.name) for m in o.modifiers])
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
for b in arm.data.bones:
    h = arm.matrix_world @ b.head_local; t = arm.matrix_world @ b.tail_local
    print("BONE", b.name, "parent=", b.parent.name if b.parent else None, "head", tuple(round(x,3) for x in h), "tail", tuple(round(x,3) for x in t))
print("ACTIONS", [(a.name, a.frame_range[:]) for a in bpy.data.actions])

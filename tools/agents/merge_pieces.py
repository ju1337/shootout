# Eine zerlegte Agenten-GLB (Teile <Körperteil>_Suit aus pieces.py) wieder zu EINEM Mesh zusammensetzen, z.B. wenn
# die Meshy-Original-GLB fehlt und neu zerlegt werden soll. Doppelte Dreiecke (Überstand) fallen weg, Textur bleibt.
#
#   python3 tools/agents/merge_pieces.py <teile.glb> <ganz.glb>
import bpy, bmesh, sys, numpy as np
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
SRC, OUT = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.context.scene.objects):
    if o.type != "MESH" or o.name.startswith("Point"):
        bpy.data.objects.remove(o)
objs = list(bpy.context.scene.objects)
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.join()
obj = bpy.context.active_object
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
obj.name = obj.data.name = "Body"
bm = bmesh.new(); bm.from_mesh(obj.data)
uv = bm.loops.layers.uv.active
seen, dupes = set(), []
for f in bm.faces:
    key = tuple(sorted((tuple(np.round(l.vert.co, 5)), tuple(np.round(l[uv].uv, 5)) if uv else ()) for l in f.loops))
    if key in seen:
        dupes.append(f)
    else:
        seen.add(key)
bmesh.ops.delete(bm, geom=dupes, context="FACES")
bm.to_mesh(obj.data); bm.free()
print("Body %d Dreiecke (%d doppelte entfernt)" % (len(obj.data.polygons), len(dupes)))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True, export_animations=False)

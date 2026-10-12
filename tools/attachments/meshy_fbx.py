"""Meshy-FBX-Export (Ordner mit .fbx und den PNG-Texturen) laden: ein Mesh in Meshy-Einheiten / 100 (Länge ~1,9,
y oben) und die Texturen für glb_io.write_glb. Auflösung bleibt (4096); als JPEG (Qualität 92) gespeichert, damit die
GLB unter 30 MB bleibt; Metall und Rauheit in einer Map (glTF: G = Rauheit, B = Metall)."""
import glob, io, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # tools/
import fbx_read as F
import mesh_ops as M

Image.MAX_IMAGE_PIXELS = None
QUALITY = 92


def _jpeg(img):
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "JPEG", quality=QUALITY, subsampling=0, optimize=True)
    return buf.getvalue(), "image/jpeg"


def load(folder):
    fbx = glob.glob(os.path.join(folder, "**", "*.fbx"), recursive=True)[0]
    base = fbx[:-4]
    meshes, _ = F.load_meshes(fbx)
    mesh = M.Mesh.concat(*[M.Mesh.from_fbx(e) for e in meshes])
    mesh = M.Mesh(mesh.P / 100.0, mesh.UV, mesh.N)
    color = Image.open(base + ".png")
    rough = Image.open(base + "_roughness.png").convert("L")
    metal = Image.open(base + "_metallic.png").convert("L")
    if metal.size != rough.size:
        metal = metal.resize(rough.size, Image.NEAREST)
    mr = Image.merge("RGB", (Image.new("L", rough.size, 0), rough, metal))
    images = {"Color": _jpeg(color), "MetalRough": _jpeg(mr)}
    if os.path.exists(base + "_normal.png"):
        images["Normal"] = _jpeg(Image.open(base + "_normal.png"))
    return mesh, images


def raw_glb(folder, out):
    """Unverändert als GLB (zum Ansehen/Vermessen)."""
    from glb_io import write_glb
    mesh, images = load(folder)
    write_glb(out, [("Body", mesh, 0)], [{"Name": "Body", **images}])
    return mesh, images

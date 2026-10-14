# Visierbild einer Meshy-Waffe vermessen: Flächen um Kimme (grau) und Korn (orange) perspektivisch vom Auge aus
# projiziert (Auge EyeRelief hinter Point_SightRear auf der Visierlinie), Gitter in Meshy-Einheiten an Kimme und Korn.
#
#   python3 tools/attachments/sight_probe.py <Waffe> <meshy-fbx.zip> <out.png> [EyeRelief]
#
# Hilft beim Einstellen von "Sights" in meshy_weapon.py: Wo liegt die Kornspitze, wie breit ist die Kerbe, deckt die
# Kimme das Korn?
import os, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_weapon as W

EYE_RELIEF = {"Pistol": 1.0, "Revolver": 1.05, "SMG": 0.55, "Shotgun": 0.6, "LMG": 0.65}


def probe(name, src, out, eye_relief=None, half=0.10, size=900, mesh=None):
    cfg = W.WEAPONS[name]
    gun = mesh if mesh is not None else W.load(src)[0]
    lo, hi = gun.bounds()
    s = cfg["Length"] / (hi[0] - lo[0])
    rear = np.array(cfg["Points"]["Point_SightRear"], float)
    front = np.array(cfg["Points"]["Point_SightFront"], float)
    eye = rear + np.array([(eye_relief or EYE_RELIEF[name]) / s, 0, 0])
    mid = (rear[0] + front[0]) / 2
    c = gun.P.mean(1)
    near = (c[:, 0] > front[0] - 0.15) & (c[:, 0] < eye[0] - 0.02)
    # Projektion: Winkel (rechts = -z, oben = +y) geteilt durch den Abstand zum Auge
    def proj(p):
        d = eye[0] - p[..., 0]
        return np.stack([-(p[..., 2] - eye[2]) / d, (p[..., 1] - eye[1]) / d], -1)
    img = Image.new("RGB", (size, size), (150, 190, 235))
    dr = ImageDraw.Draw(img)
    to_px = lambda a: (size / 2 + a[0] / half * size / 2, size / 2 - a[1] / half * size / 2)  # noqa: E731
    order = np.argsort(c[near][:, 0])          # vorne (Korn) zuerst, Kimme darüber
    tris = gun.P[near][order]
    for t in tris:
        if (eye[0] - t[:, 0]).min() < 0.01:
            continue
        col = (230, 120, 40) if t[:, 0].mean() < mid else (60, 64, 72)
        dr.polygon([to_px(q) for q in proj(t)], fill=col)
    # Gitter: Höhen (y) an der Kornposition, Breiten (z) an der Kimme und am Korn
    for y in np.arange(np.floor((eye[1] - 0.06) * 100) / 100, eye[1] + 0.06, 0.01):
        a = proj(np.array([front[0], y, eye[2]]))
        dr.line([(0, to_px(a)[1]), (size, to_px(a)[1])], fill=(255, 255, 255) if abs(y - round(y, 1)) < 1e-6 else (200, 215, 235))
        dr.text((4, to_px(a)[1] - 11), "%.2f" % y, fill=(20, 20, 20))
    for z in np.arange(-0.05, 0.051, 0.01):
        a = proj(np.array([front[0], eye[1], z])); b = proj(np.array([rear[0], eye[1], z]))
        dr.line([(to_px(a)[0], size / 2 - 6), (to_px(a)[0], size / 2 + 6)], fill=(230, 120, 40))
        dr.line([(to_px(b)[0], size - 30), (to_px(b)[0], size - 10)], fill=(40, 40, 40))
        dr.text((to_px(b)[0] - 12, size - 44), "%.2f" % z, fill=(20, 20, 20))
    dr.line([(size / 2 - 14, size / 2), (size / 2 + 14, size / 2)], fill=(0, 200, 90), width=2)
    dr.line([(size / 2, size / 2 - 14), (size / 2, size / 2 + 14)], fill=(0, 200, 90), width=2)
    img.save(out)
    return gun


if __name__ == "__main__":
    probe(sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else None)

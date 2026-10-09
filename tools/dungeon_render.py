#!/usr/bin/env python3
"""Draufsicht der Dungeon-Halle (src/shared/DungeonLayout.lua) als PNG – zum Prüfen des Layouts ohne Studio.

Liest den Bauplan über den Luau-Interpreter (DungeonLayout.Build als JSON), schneidet die Halle auf 8 Studs Höhe
(Decke, Kronleuchter und Bögen oben weg) und zeichnet die Teile von unten nach oben, heller je höher. Dazu: Lichter
als Schein, Zombie-Spawns (rot), Spieler-Spawns (blau), Portal (grün), Namen der Bereiche, Laufwege der Zombies.

Aufruf: python3 tools/dungeon_render.py [ausgabe.png] [--luau PFAD]
"""
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCALE = 7
MARGIN = 60
CUT = 8  # Schnitthöhe: Teile, die erst darüber beginnen, fehlen

DUMP = r'''
local L = require("./DungeonLayout")
local function enc(v)
	local t = type(v)
	if t == "number" or t == "boolean" then return tostring(v) end
	if t == "string" then return string.format("%q", v) end
	if t == "table" then
		local out = {}
		if #v > 0 or next(v) == nil then
			for _, x in ipairs(v) do table.insert(out, enc(x)) end
			return "[" .. table.concat(out, ",") .. "]"
		end
		for k, x in pairs(v) do table.insert(out, string.format("%q", k) .. ":" .. enc(x)) end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end
print(enc(L.Build()))
'''


def load(luau):
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy(os.path.join(ROOT, "src", "shared", "DungeonLayout.lua"), os.path.join(tmp, "DungeonLayout.luau"))
        script = os.path.join(tmp, "dump.luau")
        with open(script, "w", encoding="utf-8") as f:
            f.write(DUMP)
        out = subprocess.run([luau, script], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def font(size):
    for name in ("DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main():
    args = sys.argv[1:]
    luau = os.environ.get("LUAU", "luau")
    if "--luau" in args:
        i = args.index("--luau")
        luau = args[i + 1]
        del args[i:i + 2]
    out = args[0] if args else "dungeon.png"
    data = load(luau)
    xs, zs = [], []
    for p in data["Parts"]:
        xs += [p["P"][0] - p["S"][0] / 2, p["P"][0] + p["S"][0] / 2]
        zs += [p["P"][2] - p["S"][2] / 2, p["P"][2] + p["S"][2] / 2]
    min_x, max_x, min_z, max_z = min(xs), max(xs), min(zs), max(zs)
    w = int((max_x - min_x) * SCALE + 2 * MARGIN)
    h = int((max_z - min_z) * SCALE + 2 * MARGIN)

    def px(x, z):  # Norden (+z) oben
        return (MARGIN + (x - min_x) * SCALE, MARGIN + (max_z - z) * SCALE)

    img = Image.new("RGB", (w, h), (14, 14, 16))
    draw = ImageDraw.Draw(img)
    parts = [p for p in data["Parts"] if p["P"][1] - p["S"][1] / 2 < CUT and p.get("T", 0) < 1]
    parts.sort(key=lambda p: min(p["P"][1] + p["S"][1] / 2, CUT))
    for p in parts:
        x, y, z = p["P"]
        sx, sy, sz = p["S"]
        top = min(y + sy / 2, CUT)
        shade = 0.55 + 0.45 * max(0.0, min(1.0, (top + 1) / (CUT + 1)))
        color = tuple(int(min(255, c * shade)) for c in p["C"])
        if p.get("M") == "Neon":
            color = tuple(p["C"])
        if p.get("Shape") == "Cylinder" and p.get("RZ") == 90:
            r = sy / 2
            a, b = px(x - r, z + r), px(x + r, z - r)
            draw.ellipse([a, b], fill=color)
            continue
        if p.get("RZ") == 90:  # liegender Teil: Breite in x ist die Höhe
            sx = sy
        yaw = math.radians(p.get("R", 0))
        corners = []
        for cx, cz in ((-sx / 2, -sz / 2), (sx / 2, -sz / 2), (sx / 2, sz / 2), (-sx / 2, sz / 2)):
            wx = x + cx * math.cos(yaw) + cz * math.sin(yaw)
            wz = z - cx * math.sin(yaw) + cz * math.cos(yaw)
            corners.append(px(wx, wz))
        draw.polygon(corners, fill=color, outline=tuple(max(0, c - 30) for c in color))

    # Lichtschein
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for p in data["Parts"]:
        light = p.get("L")
        if light and p["P"][1] < 30:
            r = light[3] * SCALE * 0.45
            cx, cy = px(p["P"][0], p["P"][2])
            k = min(1.0, light[4] / 2.2) * 0.55
            gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=tuple(int(c * k) for c in light[:3]))
    glow = glow.filter(ImageFilter.GaussianBlur(SCALE * 3))
    img = ImageChops.add(img, glow)
    draw = ImageDraw.Draw(img)

    # Nebel
    for p in data["Parts"]:
        if p.get("Mist"):
            cx, cy = px(p["P"][0], p["P"][2])
            r = 7 * SCALE
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(170, 190, 170), width=1)

    # Laufwege der Zombies: von jedem Spawn zur Treppe (über Bögen bzw. Tor)
    path_color = (200, 70, 60)
    arches = [-18, 4, 26]
    stair = (0, -35)
    for sx_, _, sz_ in data["ZombieSpawns"]:
        pts = [(sx_, sz_)]
        if abs(sx_) > 34:  # Galerie: zum nächsten Bogen, ins Schiff, an den Säulen vorbei
            side = 1 if sx_ > 0 else -1
            arch = min(arches, key=lambda a: abs(a - sz_))
            pts += [(side * 41, arch), (side * 26, arch)]
            if arch > -10:
                pts += [(side * 12, -4)]
        else:  # Gruft: durchs Tor, am Brunnen vorbei
            side = 1 if sx_ > 0 else -1
            pts += [(sx_, 38), (side * 12, 20), (side * 12, -4)]
        pts += [(pts[-1][0] * 0.4, -26), stair]
        for a, b in zip(pts, pts[1:]):
            draw.line([px(*a), px(*b)], fill=path_color, width=2)
    for sx_, _, sz_ in data["ZombieSpawns"]:
        cx, cy = px(sx_, sz_)
        draw.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=(220, 40, 30), outline=(255, 200, 190), width=2)
    for sx_, _, sz_ in data["PlayerSpawns"]:
        cx, cy = px(sx_, sz_)
        draw.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=(80, 150, 255), outline=(220, 235, 255), width=2)
    pxp = px(data["Portal"][0], data["Portal"][2])
    draw.rectangle([pxp[0] - 34, pxp[1] - 6, pxp[0] + 34, pxp[1] + 6], fill=(90, 230, 140))

    big, small = font(20), font(14)

    def label(text, x, z, f=small, fill=(235, 230, 220)):
        cx, cy = px(x, z)
        box = draw.textbbox((0, 0), text, font=f)
        tw, th = box[2] - box[0], box[3] - box[1]
        draw.rectangle([cx - tw / 2 - 5, cy - th / 2 - 4, cx + tw / 2 + 5, cy + th / 2 + 6], fill=(10, 10, 12))
        draw.text((cx - tw / 2, cy - th / 2), text, font=f, fill=fill)

    label("LETZTE STELLUNG", 0, -54, big, (150, 200, 255))
    label("PORTAL / AUSGANG", 0, -58.3, small, (110, 230, 140))
    label("TREPPE (ENGSTELLE)", 0, -31)
    label("KIRCHENSCHIFF", 0, -14, big)
    label("GIFTBRUNNEN", 0, 8, small, (140, 240, 140))
    label("WESTGALERIE", -49, -27)
    label("OSTGALERIE", 49, -27)
    label("GRUFT", 0, 54, big, (255, 140, 120))
    label("BOGEN", -33.5, -18)
    label("BOGEN", -33.5, 4)
    label("BOGEN", -33.5, 26)
    label("BOGEN", 33.5, -18)
    label("BOGEN", 33.5, 4)
    label("BOGEN", 33.5, 26)
    draw.text((MARGIN, 18), "DUNGEON · DIE KATAKOMBEN · Draufsicht (Norden oben, 1 Kästchen = 10 Studs)", font=small,
              fill=(220, 210, 255))
    # Legende
    lx, ly = w - MARGIN - 250, 14
    for i, (color, text) in enumerate([((80, 150, 255), "Spieler-Spawn"), ((220, 40, 30), "Zombie-Gitter"),
                                       ((90, 230, 140), "Portal"), ((200, 70, 60), "Laufweg der Zombies")]):
        draw.ellipse([lx + (i % 2) * 125, ly + (i // 2) * 18, lx + (i % 2) * 125 + 10, ly + (i // 2) * 18 + 10], fill=color)
        draw.text((lx + (i % 2) * 125 + 15, ly + (i // 2) * 18 - 3), text, font=font(12), fill=(220, 220, 220))
    # 10-Studs-Raster am Rand
    for gx in range(int(min_x // 10) * 10, int(max_x) + 1, 10):
        a = px(gx, min_z)
        draw.line([a, (a[0], a[1] + 6)], fill=(90, 90, 96))
    for gz in range(int(min_z // 10) * 10, int(max_z) + 1, 10):
        a = px(min_x, gz)
        draw.line([a, (a[0] - 6, a[1])], fill=(90, 90, 96))
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()

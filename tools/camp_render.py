#!/usr/bin/env python3
"""Draufsicht auf Camp Phoenix (aus src/maps/Extinction.model.json) als PNG – zum Prüfen des Layouts ohne Studio.

Zeichnet alle Teile im Umkreis RADIUS um die Mitte von unten nach oben (Grundriss jedes gedrehten Quaders, Zylinder
und Kugeln als Kreise), etwas heller je höher, mit leichtem Schatten. Dazu: Stand-Punkte (gelb, mit Namen), Spawns
(blau), Teile der Gruppe Zentrale, die Server und Client suchen (grün), das Markt-Tor und der Dungeon-Eingang.

Aufruf: python3 tools/camp_render.py [ausgabe.png] [--radius 120] [--scale 6] [--cut 40]
"""
import argparse
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIGIN = (0, 0, -6000)  # EXTINCTION_ORIGIN in tools/build_maps.py
LABELS = ("Stand_Weapons", "Stand_Items", "Stand_Market", "Stash", "Stand_Vehicles", "Travel", "Hideout", "Kits",
          "Stand_Red", "ShopCounter", "WheelSpot", "MissionBoard", "Podium1", "Portal_Market", "DungeonGate")


def parts(node, group=""):
    for child in node.get("Children", []):
        if child.get("ClassName") in ("Part", "SpawnLocation", "WedgePart"):
            yield group, child
        yield from parts(child, child.get("Name", "") if child.get("ClassName") in ("Folder", "Model") else group)


def footprint(part):
    """(Punkte des Grundrisses in x/z, Unterkante, Oberkante, Kreis oder None)."""
    p = part["Properties"]
    cf = p["CFrame"]["CFrame"]
    cx, cy, cz = (cf["position"][i] - ORIGIN[i] for i in range(3))
    o = cf["orientation"]
    sx, sy, sz = p["Size"]
    shape = p.get("Shape")
    corners = []
    for dx in (-sx / 2, sx / 2):
        for dy in (-sy / 2, sy / 2):
            for dz in (-sz / 2, sz / 2):
                corners.append((cx + o[0][0] * dx + o[0][1] * dy + o[0][2] * dz,
                                cy + o[1][0] * dx + o[1][1] * dy + o[1][2] * dz,
                                cz + o[2][0] * dx + o[2][1] * dy + o[2][2] * dz))
    lo, hi = min(c[1] for c in corners), max(c[1] for c in corners)
    if shape == "Ball":
        return None, lo, hi, (cx, cz, min(sx, sy, sz) / 2)
    if shape == "Cylinder" and abs(o[1][0]) > 0.9:  # Achse (lokal X) steht senkrecht: von oben ein Kreis
        return None, cy - sx / 2, cy + sx / 2, (cx, cz, min(sy, sz) / 2)
    return hull([(c[0], c[2]) for c in corners]), lo, hi, None


def hull(points):
    pts = sorted(set((round(x, 3), round(z, 3)) for x, z in points))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out", nargs="?", default="camp.png")
    ap.add_argument("--radius", type=float, default=122)
    ap.add_argument("--scale", type=float, default=6)
    ap.add_argument("--cut", type=float, default=1e9, help="Teile, die erst über dieser Höhe beginnen, weglassen")
    args = ap.parse_args()
    with open(os.path.join(ROOT, "src", "maps", "Extinction.model.json"), encoding="utf-8") as f:
        model = json.load(f)
    R, S = args.radius, args.scale
    size = int(2 * R * S)
    img = Image.new("RGB", (size, size), (40, 44, 40))
    draw = ImageDraw.Draw(img)

    def px(x, z):  # Norden (+Z) oben, Osten (+X) rechts
        return ((x + R) * S, (R - z) * S)
    items, marks = [], []
    for group, part in parts(model):
        p = part["Properties"]
        x, _, z = (p["CFrame"]["CFrame"]["position"][i] - ORIGIN[i] for i in range(3))
        if math.hypot(x, z) > R * 1.45 or group == "Zone":
            continue
        if part["Name"] in LABELS or group.startswith("Spawns"):
            marks.append((group, part["Name"], x, z))
        if p.get("Transparency", 0) >= 0.99 or part["Name"] == "Ground":
            continue
        poly, lo, hi, circle = footprint(part)
        if lo > args.cut:
            continue
        items.append((hi, poly, circle, p.get("Color", [0.5, 0.5, 0.5]), p.get("Transparency", 0)))
    items.sort(key=lambda it: it[0])
    for hi, poly, circle, color, transp in items:
        shade = 0.72 + min(0.4, max(0.0, hi) / 60)
        rgb = tuple(int(min(255, c * 255 * shade)) for c in color)
        if transp > 0.5:
            rgb = tuple(int(c * 0.5 + 40) for c in rgb)
        shadow = tuple(int(c * 0.55) for c in rgb)
        off = min(10, hi * 0.12) * S / 6
        if circle:
            cx, cz, r = circle
            x0, y0 = px(cx - r, cz + r)
            x1, y1 = px(cx + r, cz - r)
            if hi > 3:
                draw.ellipse((x0 + off, y0 + off, x1 + off, y1 + off), fill=shadow)
            draw.ellipse((x0, y0, x1, y1), fill=rgb)
        elif poly and len(poly) >= 3:
            pts = [px(x, z) for x, z in poly]
            if hi > 3:
                draw.polygon([(a + off, b + off) for a, b in pts], fill=shadow)
            draw.polygon(pts, fill=rgb, outline=tuple(int(c * 0.8) for c in rgb))
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", int(3 * S))
    except OSError:
        font = ImageFont.load_default()
    for group, name, x, z in marks:
        X, Y = px(x, z)
        if group.startswith("Spawns"):
            draw.ellipse((X - S, Y - S, X + S, Y + S), fill=(80, 150, 255))
            continue
        color = (255, 214, 60) if group == "Stands" else (90, 230, 140) if group in ("Zentrale", "Portals") else (255, 255, 255)
        draw.ellipse((X - 1.2 * S, Y - 1.2 * S, X + 1.2 * S, Y + 1.2 * S), fill=color, outline=(0, 0, 0))
        draw.text((X + 1.8 * S, Y - 1.6 * S), name, fill=color, font=font, stroke_width=2, stroke_fill=(0, 0, 0))
    img.save(args.out)
    print("gespeichert:", args.out)


if __name__ == "__main__":
    main()

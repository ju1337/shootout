"""Erzeugt die Maps als Rojo-Modelle (src/maps/*.model.json).

Aufruf:  python3 tools/build_maps.py
Alle Maps liegen im selben Place (Workspace.Maps.Hub / FreeForAll / Drop), jeweils
an einer eigenen Stelle der Welt. Die Verschiebungen müssen zu "Center" in
src/shared/Modes.lua passen.
"""

import json
import math
import os
import random

# Anzeigenamen der Maps (z.B. in der Agentenwahl)
MAP_NAMES = {"TDM": "Fabrik", "FreeForAll": "Raffinerie", "Drop": "Tal", "Strikeout": "Fabrik", "Wingman": "Fabrik", "Demolition": "Hafen",
             "Ranked": "Hafen", "Arena": "Arena", "Training": "Schießstand", "Hub": "Hangar"}

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "maps")

# Mitte jeder Map in der Welt (wie Center in Modes.lua)
HUB_ORIGIN = (0, 0, 0)
FFA_ORIGIN = (0, 0, 1500)
DROP_ORIGIN = (1500, 0, 0)
STRIKEOUT_ORIGIN = (0, 0, -1500)
DEMOLITION_ORIGIN = (-1500, 0, 0)
WINGMAN_ORIGIN = (1500, 0, -1500)
TRAINING_ORIGIN = (-1500, 0, 1500)
RANKED_ORIGIN = (1500, 0, 1500)
ARENA_ORIGIN = (0, 0, 3000)


# ---------- Helfer ----------

def rot(rx=0.0, ry=0.0, rz=0.0):
    """Rotationsmatrix wie CFrame.Angles(rx, ry, rz) in Grad (R = Rx * Ry * Rz)."""
    a, b, c = (math.radians(v) for v in (rx, ry, rz))
    ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    rx_m = [[1, 0, 0], [0, ca, -sa], [0, sa, ca]]
    ry_m = [[cb, 0, sb], [0, 1, 0], [-sb, 0, cb]]
    rz_m = [[cc, -sc, 0], [sc, cc, 0], [0, 0, 1]]

    def mul(m, n):
        return [[sum(m[i][k] * n[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    m = mul(mul(rx_m, ry_m), rz_m)
    return [[round(v, 6) for v in row] for row in m]


def rgb(r, g, b):
    return [round(r / 255, 4), round(g / 255, 4), round(b / 255, 4)]


HOLO_TINT = (100, 180, 230)  # Glas-Tönung der Holo-Schilder


def lighten(color, amount=0.35):
    return tuple(int(c + (255 - c) * amount) for c in color)


class Builder:
    def __init__(self, origin=(0, 0, 0)):
        self.groups = {}
        self.origin = origin
        self.holo = False  # True: Schilder als Hologramme (durchsichtiges Glas, leuchtende Schrift, Leuchtkanten)

    def holo_edges(self, name, size, pos, angles, color):
        """Dünne Leuchtkanten oben und unten an einem (gedrehten) Holo-Schild."""
        m = rot(*angles)
        for sy in (-1, 1):
            local = (0, sy * size[1] / 2, 0)
            off = [sum(m[i][k] * local[k] for k in range(3)) for i in range(3)]
            self.box("Decor", name + "HoloEdge", (size[0] + 0.2, 0.1, 0.1), (pos[0] + off[0], pos[1] + off[1], pos[2] + off[2]),
                     color, "Neon", angles=angles, props={"Transparency": 0.15 if sy > 0 else 0.4, "CanCollide": False,
                                                            "CanQuery": False})

    def holo_panel(self, group, name, size, pos, angles=(0, 0, 0), children=None, props=None):
        """Durchsichtige, leicht getönte Glasfläche (Träger für Holo-Schrift)."""
        p = {"Transparency": 0.86, "CanCollide": False, "CanQuery": False,
             "Attributes": {"Attributes": {"Holo": {"Bool": True}}}}
        if props:
            p.update(props)
        self.add(group, name, size, pos, HOLO_TINT, "Glass", angles=angles, props=p, children=children)

    def add(self, group, name, size, pos, color, material="SmoothPlastic", angles=(0, 0, 0),
            cls="Part", props=None, children=None):
        p = {
            "Anchored": True,
            "Size": [round(v, 3) for v in size],
            "CFrame": {"CFrame": {"position": [round(v + o, 3) for v, o in zip(pos, self.origin)],
                                  "orientation": rot(*angles)}},
            "Color": rgb(*color),
            "Material": material,
            "TopSurface": "Smooth",
            "BottomSurface": "Smooth",
        }
        if props:
            p.update(props)
        inst = {"Name": name, "ClassName": cls, "Properties": p}
        if children:
            inst["Children"] = children
        self.groups.setdefault(group, []).append(inst)

    def box(self, group, name, size, pos, color, material="SmoothPlastic", **kw):
        self.add(group, name, size, pos, color, material, **kw)

    # Boden, Oberkante bei y = 0
    def ground(self, sx, sz, color, material):
        self.box("Ground", "Ground", (sx, 4, sz), (0, -2, 0), color, material)

    # Umrandung: sichtbare Mauer + unsichtbare hohe Barriere
    def border(self, sx, sz, height, color, material, barrier=0):
        t = 3
        for name, size, pos in (
            ("North", (sx + t * 2, height, t), (0, height / 2, sz / 2 + t / 2)),
            ("South", (sx + t * 2, height, t), (0, height / 2, -sz / 2 - t / 2)),
            ("East", (t, height, sz), (sx / 2 + t / 2, height / 2, 0)),
            ("West", (t, height, sz), (-sx / 2 - t / 2, height / 2, 0)),
        ):
            self.box("Border", "Wall" + name, size, pos, color, material)
            if barrier:
                bs = (size[0], barrier, size[2])
                self.box("Border", "Barrier" + name, bs, (pos[0], barrier / 2, pos[2]), (255, 255, 255),
                         props={"Transparency": 1})

    # Begehbares Haus mit Türöffnungen. doors: Seiten aus "N","S","E","W"
    def house(self, name, x, z, w, d, h, color, roof_color, doors=("N", "S"), material="Brick"):
        t, dw, dh = 1, 6, 9  # Wandstärke, Türbreite, Türhöhe
        group = "Buildings"

        def wall(side, length, center, along_x):
            cx, cz = center
            if side not in doors:
                size = (length, h, t) if along_x else (t, h, length)
                self.box(group, f"{name}_{side}", size, (cx, h / 2, cz), color, material)
                return
            seg = (length - dw) / 2
            for sign in (-1, 1):
                off = sign * (dw / 2 + seg / 2)
                size = (seg, h, t) if along_x else (t, h, seg)
                pos = (cx + off, h / 2, cz) if along_x else (cx, h / 2, cz + off)
                self.box(group, f"{name}_{side}", size, pos, color, material)
            top = h - dh
            size = (dw, top, t) if along_x else (t, top, dw)
            self.box(group, f"{name}_{side}Top", size, (cx, dh + top / 2, cz), color, material)

        wall("N", w, (x, z + d / 2 - t / 2), True)
        wall("S", w, (x, z - d / 2 + t / 2), True)
        wall("E", d - 2 * t, (x + w / 2 - t / 2, z), False)
        wall("W", d - 2 * t, (x - w / 2 + t / 2, z), False)
        self.box(group, f"{name}_Roof", (w + 1, 1, d + 1), (x, h + 0.5, z), roof_color, "Slate")
        self.box(group, f"{name}_Floor", (w - 2 * t, 0.2, d - 2 * t), (x, 0.1, z), (110, 85, 60), "WoodPlanks")

    def crate(self, x, z, s=5, y=0, color=(160, 120, 70)):
        self.box("Cover", "Crate", (s, s, s), (x, y + s / 2, z), color, "WoodPlanks")

    def cover_wall(self, x, z, length, along_x=True, height=6, color=(150, 150, 150)):
        size = (length, height, 2) if along_x else (2, height, length)
        self.box("Cover", "CoverWall", size, (x, height / 2, z), color, "Concrete")

    def ramp(self, name, x, z, width, run, rise, direction):
        """Rampe vom Boden (bei z/x + run) hoch auf Höhe rise (bei z/x). direction: N/S/E/W = Richtung nach unten."""
        length = math.hypot(run, rise)
        angle = math.degrees(math.atan2(rise, run))
        cy = rise / 2 - 0.3
        if direction == "N":
            self.box("Buildings", name, (width, 1, length), (x, cy, z + run / 2), (130, 130, 135), "DiamondPlate",
                     angles=(angle, 0, 0))
        elif direction == "S":
            self.box("Buildings", name, (width, 1, length), (x, cy, z - run / 2), (130, 130, 135), "DiamondPlate",
                     angles=(-angle, 0, 0))
        elif direction == "E":
            self.box("Buildings", name, (length, 1, width), (x + run / 2, cy, z), (130, 130, 135), "DiamondPlate",
                     angles=(0, 0, -angle))
        else:
            self.box("Buildings", name, (length, 1, width), (x - run / 2, cy, z), (130, 130, 135), "DiamondPlate",
                     angles=(0, 0, angle))

    def tree(self, x, z, rng):
        h = rng.uniform(10, 16)
        self.box("Nature", "Trunk", (1.6, h, 1.6), (x, h / 2, z), (100, 70, 45), "Wood")
        r = rng.uniform(9, 13)
        self.add("Nature", "Leaves", (r, r, r), (x, h + r / 3, z), (60, 120, 50), "Grass", cls="Part",
                 props={"Shape": "Ball"})

    def rock(self, x, z, rng):
        s = rng.uniform(4, 9)
        self.box("Nature", "Rock", (s, s * 0.7, s * 1.2), (x, s * 0.25, z), (115, 115, 110), "Slate",
                 angles=(rng.uniform(-10, 10), rng.uniform(0, 360), rng.uniform(-10, 10)))

    def spawn(self, x, z, yaw=0, real=False, group="Spawns", hidden=False):
        """real=True: echte SpawnLocation (nur im Hub). Sonst unsichtbarer Spawnpunkt für die Modus-Logik."""
        if real:
            self.add(group, "Spawn", (6, 1, 6), (x, 0.5, z), (255, 140, 40), "Neon", angles=(0, yaw, 0),
                     cls="SpawnLocation", props={"Transparency": 1 if hidden else 0.6, "Neutral": True, "Duration": 0,
                                                 "AllowTeamChangeOnTouch": False, "CanCollide": False})
        else:
            self.add(group, "SpawnPoint", (4, 1, 4), (x, 0.5, z), (90, 160, 255), "SmoothPlastic",
                     angles=(0, yaw, 0), props={"Transparency": 1, "CanCollide": False, "CanQuery": False,
                                                "CanTouch": False})

    def sign(self, name, size, pos, text, bg, fg, angles=(0, 0, 0)):
        label = {
            "Name": "Text", "ClassName": "TextLabel",
            "Properties": {
                "Size": {"UDim2": [[1, 0], [1, 0]]},
                "BackgroundTransparency": 1,
                "Text": text,
                "TextScaled": True,
                "Font": "Oswald",
                "TextColor3": rgb(*fg),
            },
        }
        if self.holo:
            label["Properties"]["TextColor3"] = rgb(*lighten(fg))
            label["Properties"]["TextStrokeColor3"] = rgb(40, 120, 180)
            label["Properties"]["TextStrokeTransparency"] = 0.5
            gui = {"Name": "SignGui", "ClassName": "SurfaceGui", "Properties": {"Face": "Front", "LightInfluence": 0,
                   "Brightness": 1.4}, "Children": [label]}
            self.holo_panel("Decor", name, size, pos, angles, children=[gui])
            return
        gui = {"Name": "SignGui", "ClassName": "SurfaceGui", "Properties": {"Face": "Front"}, "Children": [label]}
        self.box("Decor", name, size, pos, bg, "SmoothPlastic", angles=angles, children=[gui])

    # ---------- Bausteine für größere, verwinkelte Maps ----------

    def wall_line(self, name, a, b, fixed, along_x, h, color, material="Concrete", openings=(), y0=0, t=1.2,
                  group="Buildings"):
        """Gerade Wand von a bis b (entlang x, wenn along_x, sonst entlang z) bei fixed (z bzw. x).
        openings: (Mitte, Breite, Unterkante, Oberkante) relativ zu y0 – Unterkante 0 = Tür, sonst Fenster."""
        cuts = sorted(openings)
        pos = a

        def seg(p0, p1, lo, hi):
            if p1 - p0 < 0.05 or hi - lo < 0.05:
                return
            mid, length, cy = (p0 + p1) / 2, p1 - p0, y0 + (lo + hi) / 2
            size = (length, hi - lo, t) if along_x else (t, hi - lo, length)
            center = (mid, cy, fixed) if along_x else (fixed, cy, mid)
            self.box(group, name, size, center, color, material)

        for center, width, lo, hi in cuts:
            o0, o1 = center - width / 2, center + width / 2
            seg(pos, o0, 0, h)
            seg(o0, o1, 0, lo)
            seg(o0, o1, min(hi, h), h)
            pos = o1
        seg(pos, b, 0, h)

    def stairs(self, name, x, z, width, rise, direction, color=(110, 112, 118), step_rise=1.0, step_run=1.3, y0=0):
        """Massive Treppe: beginnt bei (x, z) auf Höhe y0 und steigt in Richtung direction (N/S/E/W) um rise."""
        n = int(math.ceil(rise / step_rise))
        dx, dz = {"N": (0, 1), "S": (0, -1), "E": (1, 0), "W": (-1, 0)}[direction]
        for k in range(n):
            top = min(rise, (k + 1) * step_rise)
            off = (k + 0.5) * step_run
            cx, cz = x + dx * off, z + dz * off
            size = (width, top, step_run) if dx == 0 else (step_run, top, width)
            self.box("Buildings", name, size, (cx, y0 + top / 2, cz), color, "Concrete")
        return n * step_run  # Länge der Treppe

    def slab(self, name, x0, x1, z0, z1, y, color, holes=(), material="Concrete", t=1):
        """Decke/Boden von x0..x1, z0..z1 auf Höhe y (Oberkante), mit rechteckigen Löchern (hx0, hx1, hz0, hz1)."""
        rects = [(x0, x1, z0, z1)]
        for hx0, hx1, hz0, hz1 in holes:
            new = []
            for rx0, rx1, rz0, rz1 in rects:
                if hx1 <= rx0 or hx0 >= rx1 or hz1 <= rz0 or hz0 >= rz1:
                    new.append((rx0, rx1, rz0, rz1))
                    continue
                if rz0 < hz0:
                    new.append((rx0, rx1, rz0, hz0))
                if hz1 < rz1:
                    new.append((rx0, rx1, hz1, rz1))
                mz0, mz1 = max(rz0, hz0), min(rz1, hz1)
                if rx0 < hx0:
                    new.append((rx0, hx0, mz0, mz1))
                if hx1 < rx1:
                    new.append((hx1, rx1, mz0, mz1))
            rects = new
        for rx0, rx1, rz0, rz1 in rects:
            if rx1 - rx0 > 0.05 and rz1 - rz0 > 0.05:
                self.box("Buildings", name, (rx1 - rx0, t, rz1 - rz0), ((rx0 + rx1) / 2, y - t / 2, (rz0 + rz1) / 2),
                         color, material)

    def building2(self, name, x, z, w, d, color, roof_color, doors=None, windows1=None, windows2=None,
                  stairs_at=("W",), h1=10, h2=9, material="Concrete"):
        """Zweistöckiges Gebäude. doors/windows: {Seite: [Versatz, ...]} (Versatz entlang der Wand, 0 = Mitte).
        Unten Türen (6 breit) und Fenster, oben viele Fenster zum Spähen. Treppe innen an den Seiten stairs_at."""
        doors = doors or {}
        windows1 = windows1 or {}
        windows2 = windows2 or {}
        x0, x1, z0, z1 = x - w / 2, x + w / 2, z - d / 2, z + d / 2
        t = 1.2
        walls = {"N": (x0, x1, z1 - t / 2, True), "S": (x0, x1, z0 + t / 2, True),
                 "E": (z0 + t, z1 - t, x1 - t / 2, False), "W": (z0 + t, z1 - t, x0 + t / 2, False)}
        for side, (a, b, fixed, along_x) in walls.items():
            base = (x if along_x else z)
            ops = [(base + o, 6, 0, 8) for o in doors.get(side, [])]
            ops += [(base + o, 4, 3.2, 6.6) for o in windows1.get(side, [])]
            self.wall_line(name, a, b, fixed, along_x, h1, color, material, ops)
            ops2 = [(base + o, 4.5, 2.8, 6.4) for o in windows2.get(side, [])]
            self.wall_line(name, a, b, fixed, along_x, h2, color, material, ops2, y0=h1)
        # Treppen innen an der Wand, Loch in der Decke darüber
        holes = []
        for side in stairs_at:
            sw = 4.5
            if side == "W":
                sx, run_dir = x0 + t + sw / 2, "N"
                length = self.stairs(name + "_Stairs", sx, z0 + t + 2, sw, h1, run_dir)
                holes.append((sx - sw / 2, sx + sw / 2, z0 + t + 2, z0 + t + 2 + length + 1))
            elif side == "E":
                sx, run_dir = x1 - t - sw / 2, "S"
                length = self.stairs(name + "_Stairs", sx, z1 - t - 2, sw, h1, run_dir)
                holes.append((sx - sw / 2, sx + sw / 2, z1 - t - 2 - length - 1, z1 - t - 2))
            elif side == "S":
                sz, run_dir = z0 + t + sw / 2, "E"
                length = self.stairs(name + "_Stairs", x0 + t + 2, sz, sw, h1, run_dir)
                holes.append((x0 + t + 2, x0 + t + 2 + length + 1, sz - sw / 2, sz + sw / 2))
            else:
                sz, run_dir = z1 - t - sw / 2, "W"
                length = self.stairs(name + "_Stairs", x1 - t - 2, sz, sw, h1, run_dir)
                holes.append((x1 - t - 2 - length - 1, x1 - t - 2, sz - sw / 2, sz + sw / 2))
        self.slab(name + "_Floor2", x0 + t, x1 - t, z0 + t, z1 - t, h1 + 0.5, (110, 90, 70), holes, "WoodPlanks")
        self.box("Buildings", name + "_Roof", (w + 1, 1, d + 1), (x, h1 + h2 + 0.5, z), roof_color, "Slate")
        self.box("Buildings", name + "_Floor", (w - 2 * t, 0.2, d - 2 * t), (x, 0.1, z), (120, 110, 100), "Concrete")

    def container(self, x, z, along_x=True, level=0, color=(90, 120, 80), length=20):
        """Schiffscontainer (8 hoch), level 1 = auf einen anderen gestapelt (begehbare Oberseite)."""
        size = (length, 8, 8) if along_x else (8, 8, length)
        self.box("Cover", "Container", size, (x, 4 + level * 8, z), color, "Metal")

    def half_wall(self, x, z, length, along_x=True, color=(150, 150, 150)):
        """Brusthohe Deckung (man kann darüber schießen)."""
        self.cover_wall(x, z, length, along_x=along_x, height=3.4, color=color)

    def sign2(self, name, size, pos, title, subtitle, bg, fg, sub_fg, angles=(0, 0, 0), glow=None):
        """Schild mit großer Überschrift und kleiner Unterzeile (z.B. Modus-Tore im Hub)."""
        def text(label_name, y, h, value, color, font):
            return {"Name": label_name, "ClassName": "TextLabel", "Properties": {
                "Position": {"UDim2": [[0.04, 0], [y, 0]]}, "Size": {"UDim2": [[0.92, 0], [h, 0]]},
                "BackgroundTransparency": 1, "Text": value, "TextScaled": True, "Font": font,
                "TextColor3": rgb(*color), "TextStrokeTransparency": 0.55}}
        bar = {"Name": "Bar", "ClassName": "Frame", "Properties": {
            "Position": {"UDim2": [[0, 0], [0.94, 0]]}, "Size": {"UDim2": [[1, 0], [0.06, 0]]},
            "BackgroundColor3": rgb(*fg), "BorderSizePixel": 0}}
        gui = {"Name": "SignGui", "ClassName": "SurfaceGui",
               "Properties": {"Face": "Front", "LightInfluence": 0, "Brightness": 1.6,
                              "SizingMode": "PixelsPerStud", "PixelsPerStud": 40},
               "Children": [text("Title", 0.06, 0.58, title, fg, "Oswald"),
                            text("Subtitle", 0.64, 0.26, subtitle, sub_fg, "GothamBold"), bar]}
        children = [gui]
        if glow:
            children.append({"Name": "Glow", "ClassName": "SurfaceLight", "Properties": {
                "Face": "Front", "Range": 16, "Brightness": 1.2, "Angle": 80, "Color": rgb(*glow)}})
        if self.holo:
            # Hologramm: Glas statt Tafel, Schrift heller mit blauem Schimmer, Leuchtkanten oben/unten
            gui["Properties"]["Brightness"] = 1.4
            for child in gui["Children"]:
                props = child["Properties"]
                if child["ClassName"] == "TextLabel":
                    props["TextColor3"] = rgb(*lighten(fg if child["Name"] == "Title" else sub_fg, 0.3))
                    props["TextStrokeColor3"] = rgb(40, 120, 180)
                    props["TextStrokeTransparency"] = 0.45
                else:
                    props["BackgroundTransparency"] = 0.3
            self.holo_panel("Decor", name, size, pos, angles, children=children)
            self.holo_edges(name, size, pos, angles, lighten(fg, 0.2))
            return
        self.box("Decor", name, size, pos, bg, "SmoothPlastic", angles=angles, children=children)

    def floor_text(self, name, size, pos, text, color, bg=None, yaw=180):
        """Flache Schrift auf dem Boden (Face Top). yaw=180: lesbar, wenn man nach Norden (+Z) schaut."""
        label = {"Name": "Text", "ClassName": "TextLabel", "Properties": {
            "Size": {"UDim2": [[1, 0], [1, 0]]}, "BackgroundTransparency": 1, "Text": text, "TextScaled": True,
            "Font": "Oswald", "TextColor3": rgb(*color), "TextTransparency": 0.1}}
        gui = {"Name": "FloorGui", "ClassName": "SurfaceGui", "Properties": {
            "Face": "Top", "LightInfluence": 0, "Brightness": 1.3, "SizingMode": "PixelsPerStud", "PixelsPerStud": 30},
            "Children": [label]}
        self.add("Ground", name, size, pos, bg or (30, 33, 40), "SmoothPlastic", angles=(0, yaw, 0),
                 props={"Transparency": 1 if bg is None else 0, "CanCollide": False, "CanQuery": False},
                 children=[gui])

    def save(self, filename, display_name=None):
        model = {
            "ClassName": "Model",
            "Properties": {"Attributes": {"Attributes": {
                "DisplayName": {"String": display_name or MAP_NAMES.get(filename.replace(".model.json", ""),
                                                                         filename.replace(".model.json", ""))},
                "Center": {"Vector3": [float(v) for v in self.origin]},
            }}},
            "Children": [{"Name": g, "ClassName": "Folder", "Children": c} for g, c in self.groups.items()],
        }
        os.makedirs(OUT_DIR, exist_ok=True)
        with open(os.path.join(OUT_DIR, filename), "w") as f:
            json.dump(model, f, indent=1)
        print(filename, sum(len(c) for c in self.groups.values()), "Parts")


# ---------- Free-for-All: "Lagerhof" (180 x 180) ----------

def build_ffa():
    """Raffinerie (250 x 250): Tanklager in der Mitte (Brücken als zweite Ebene), Rohrbrücken,
    zweistöckige Kontrollhäuser im Norden/Süden und Werkstätten im Osten/Westen mit Fenstern,
    Containerecken mit Trennwänden zum Spähen."""
    b = Builder(FFA_ORIGIN)
    size = 250
    steel, pipe, tank, concrete = (90, 96, 104), (160, 120, 60), (205, 205, 200), (120, 122, 126)
    cyl = {"Shape": "Cylinder"}
    b.ground(size + 10, size + 10, concrete, "Concrete")
    b.border(size, size, 14, (110, 105, 100), "Brick", barrier=120)
    for x in (-50, 50):
        b.box("Ground", "Lane", (0.6, 0.05, 220), (x, 0.03, 0), (230, 190, 40), "SmoothPlastic")

    # Tanklager: vier Tanks, oben über Brücken verbunden (Ebene auf 16)
    top = 16
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.add("Buildings", "Tank", (top, 18, 18), (sx * 24, top / 2, sz * 24), tank, "Metal",
                  angles=(0, 0, 90), props=cyl)
            b.add("Buildings", "TankRoof", (0.6, 18.4, 18.4), (sx * 24, top + 0.3, sz * 24), steel, "DiamondPlate",
                  angles=(0, 0, 90), props=cyl)
            b.box("Buildings", "TankStripe", (18.2, 1.2, 0.4), (sx * 24, top - 3, sz * 24 - sz * 9.05), (200, 70, 50),
                  "SmoothPlastic")
    for z in (-24, 24):
        b.box("Buildings", "Bridge", (30, 0.8, 4), (0, top + 0.2, z), steel, "DiamondPlate")
    for x in (-24, 24):
        b.box("Buildings", "Bridge", (4, 0.8, 30), (x, top + 0.2, 0), steel, "DiamondPlate")
    b.box("Buildings", "CrossBridge", (4, 0.8, 48), (0, top + 0.2, 0), steel, "DiamondPlate")
    for z in (-24, 24):
        b.box("Buildings", "Railing", (30, 1.2, 0.3), (0, top + 1.2, z - 2 if z > 0 else z + 2), (220, 180, 40), "Metal")
    b.ramp("TankRampN", 0, 26, 6, 30, top + 0.6, "N")
    b.ramp("TankRampS", 0, -26, 6, 30, top + 0.6, "S")
    # Deckung unter den Brücken
    for x, z in ((-8, -8), (8, 8)):
        b.half_wall(x, z, 8, along_x=x < 0)

    # Rohrbrücken (Deckung darunter)
    for x in (-62, 62):
        for z in range(-70, 71, 20):
            b.box("Buildings", "PipeSupport", (1.2, 7, 1.2), (x, 3.5, z), steel, "Metal")
        for dx in (-1.6, 0, 1.6):
            b.add("Buildings", "Pipe", (144, 1.4, 1.4), (x + dx, 7.6, 0), pipe, "Metal", angles=(0, 90, 0), props=cyl)

    # Zweistöckige Kontrollhäuser (Nord/Süd) mit Fensterfront zum Tanklager
    b.building2("ControlN", 0, 98, 46, 22, (150, 155, 160), (60, 65, 70),
                doors={"S": [-14, 14], "E": [0], "W": [0]}, windows1={"S": [0]},
                windows2={"S": [-18, -9, 0, 9, 18], "E": [-4, 4], "W": [-4, 4]}, stairs_at=("N",))
    b.building2("ControlS", 0, -98, 46, 22, (150, 155, 160), (60, 65, 70),
                doors={"N": [-14, 14], "E": [0], "W": [0]}, windows1={"N": [0]},
                windows2={"N": [-18, -9, 0, 9, 18], "E": [-4, 4], "W": [-4, 4]}, stairs_at=("S",))
    # Werkstätten (Ost/West)
    b.building2("WorkshopW", -100, 0, 24, 44, (140, 110, 90), (70, 60, 55),
                doors={"E": [-12, 12], "N": [0], "S": [0]}, windows1={"E": [0]},
                windows2={"E": [-16, -6, 6, 16], "N": [0], "S": [0]}, stairs_at=("W",), material="Brick")
    b.building2("WorkshopE", 100, 0, 24, 44, (140, 110, 90), (70, 60, 55),
                doors={"W": [-12, 12], "N": [0], "S": [0]}, windows1={"W": [0]},
                windows2={"W": [-16, -6, 6, 16], "N": [0], "S": [0]}, stairs_at=("E",), material="Brick")

    # Ecken: Container, Kisten, Trennwände mit Fenstern
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.container(sx * 88, sz * 70, along_x=True, color=(70, 110, 150) if sx < 0 else (150, 70, 60))
            b.container(sx * 40, sz * 72, along_x=False, color=(90, 130, 80), length=16)
            b.crate(sx * 70, sz * 50)
            b.crate(sx * 106, sz * 100, s=6)
            b.wall_line("CornerWall", min(sx * 30, sx * 54), max(sx * 30, sx * 54), sz * 45, True, 7, concrete, "Concrete",
                        openings=[(sx * 42, 4, 3, 5.4)], group="Cover")
            b.half_wall(sx * 38, sz * 30, 8, along_x=False)

    # Spawns verteilt an den Rändern (Blick zur Mitte)
    for x, z in ((-115, 40), (115, -40), (40, 115), (-40, -115), (-115, -60), (115, 60), (-80, 115), (80, -115),
                 (-115, 100), (115, -100)):
        yaw = math.degrees(math.atan2(x, z))
        b.spawn(x, z, yaw=yaw)

    b.save("FreeForAll.model.json", "Raffinerie")


# ---------- Drop: "Tal" (420 x 320), Teams springen bei x = -150 / +150 ab ----------

def build_drop():
    b = Builder(DROP_ORIGIN)
    rng = random.Random(7)
    sx_total, sz_total = 420, 320
    b.ground(sx_total + 10, sz_total + 10, (85, 130, 60), "Grass")
    b.border(sx_total, sz_total, 5, (120, 115, 105), "Slate", barrier=400)

    # Straßen durch die Stadt
    b.box("Ground", "Road", (220, 0.2, 14), (0, 0.1, 0), (60, 60, 65), "Asphalt")
    b.box("Ground", "Road", (14, 0.2, 220), (0, 0.1, 0), (60, 60, 65), "Asphalt")

    # Basen beider Teams (Rot links bei -x, Blau rechts bei +x)
    for side, color in ((-1, (170, 70, 70)), (1, (70, 100, 170))):
        bx = side * 165
        b.box("Ground", "BasePad", (60, 0.4, 110), (bx, 0.2, 0), (130, 130, 130), "Concrete")
        b.house(f"Bunker{side}", side * 185, 0, 20, 30, 10, color, (60, 60, 60),
                doors=("E" if side < 0 else "W", "N", "S"), material="Concrete")
        for z in (-40, -15, 15, 40):
            b.cover_wall(side * 140, z, 10, along_x=False, height=3.5, color=(150, 140, 110))
        for z in (-30, 30):
            b.crate(side * 155, z)
            b.crate(side * 155, z + 5.5)
        # Team-Spawns (Herrschaft: Respawn an der eigenen Basis)
        for z in (-12, -4, 4, 12):
            b.spawn(side * 160, z, yaw=90 * side, group="SpawnsA" if side < 0 else "SpawnsB")

    # Herrschaft: Flaggen A (Westen), B (Kreuzung in der Mitte), C (Osten)
    for name, x, color in (("A", -110, (255, 120, 120)), ("B", 0, (240, 240, 240)), ("C", 110, (120, 160, 255))):
        b.add("Objective", "Flag" + name, (0.3, 18, 18), (x, 0.25, 0), (230, 230, 235), "Neon",
              angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.5, "CanCollide": False})
        b.box("Decor", "FlagPole" + name, (0.6, 14, 0.6), (x + 7, 7, 7), (60, 60, 65), "Metal")
        b.box("Decor", "FlagCloth" + name, (4, 2.6, 0.2), (x + 9, 12.5, 7), color, "Fabric")
        b.sign("FlagSign" + name, (4, 4, 0.4), (x + 7, 16.5, 7), name, (25, 25, 30), (255, 255, 255))

    # Stadt in der Mitte: begehbare Häuser
    houses = (
        (-55, -55, 24, 20, 12, ("N", "E")), (55, 55, 24, 20, 12, ("S", "W")),
        (-55, 55, 22, 22, 12, ("S", "E")), (55, -55, 22, 22, 12, ("N", "W")),
        (0, -95, 30, 18, 14, ("N",)), (0, 95, 30, 18, 14, ("S",)),
        (-100, -25, 18, 24, 11, ("E", "W")), (100, 25, 18, 24, 11, ("E", "W")),
    )
    colors = ((180, 160, 120), (160, 100, 80), (200, 190, 170), (140, 130, 120))
    # Zweistöckig mit Fenstern auf allen Seiten oben; Treppe an einer Wand ohne Tür
    for i, (x, z, w, d, h, doors) in enumerate(houses):
        stair = next(side for side in ("W", "E", "N", "S") if side not in doors)
        b.building2(f"House{i}", x, z, w, d, colors[i % len(colors)], (80, 60, 55),
                    doors={side: [0] for side in doors},
                    windows1={side: [-6, 6] for side in doors},
                    windows2={side: [-5, 5] for side in ("N", "S", "E", "W")},
                    stairs_at=(stair,), material="Brick")

    # Hohe Gebäude (Landeplätze auf dem Dach)
    for i, (x, z, w, h, d) in enumerate(((-25, -30, 16, 28, 16), (25, 30, 16, 24, 16), (-30, 28, 14, 18, 14),
                                         (30, -28, 14, 20, 14))):
        b.box("Buildings", f"Tower{i}", (w, h, d), (x, h / 2, z), (150, 150, 160), "Concrete")
        b.box("Buildings", f"Tower{i}_Roof", (w + 1, 1, d + 1), (x, h + 0.5, z), (90, 90, 95), "DiamondPlate")

    # Deckung in der Stadt
    for x, z in ((-12, 20), (12, -20), (-80, 10), (80, -10), (20, 75), (-20, -75), (70, 0), (-70, 0)):
        b.crate(x, z)
    for x, z, length, ax in ((0, 40, 14, True), (0, -40, 14, True), (40, 0, 14, False), (-40, 0, 14, False),
                             (-85, 60, 12, True), (85, -60, 12, True)):
        b.cover_wall(x, z, length, along_x=ax)

    # Natur zwischen Stadt und Basen und am Rand
    def free(x, z):
        if abs(z) < 16 and abs(x) < 130:
            return False  # Flaggen A/C freihalten
        return (abs(x) > 115 and abs(x) < 130) or (abs(z) > 115 and abs(x) < 190)

    placed = 0
    while placed < 45:
        x, z = rng.uniform(-200, 200), rng.uniform(-150, 150)
        if free(x, z):
            if placed % 3 == 0:
                b.rock(x, z, rng)
            else:
                b.tree(x, z, rng)
            placed += 1

    b.save("Drop.model.json")


# ---------- Strikeout: "Fabrik" (300 x 200), Team Gold bei -x, Team Lila bei +x ----------

def build_strikeout(origin=STRIKEOUT_ORIGIN, filename="Strikeout.model.json"):
    """Fabrik (300 x 200): drei Wege. Norden: zweistöckige Fabrikhalle (begehbar, Fenster zur Mitte).
    Mitte: Hof mit Eroberungspunkt und viel brusthoher Deckung. Süden: Containerhof mit Laufsteg oben.
    Trennwände mit Fenstern und Durchgängen zwischen den Wegen, Spawnhäuser mit erhöhter Position."""
    b = Builder(origin)
    W, D = 300, 200
    concrete, brick, metal = (112, 108, 102), (150, 95, 75), (85, 90, 98)
    b.ground(W + 10, D + 10, (105, 100, 95), "Concrete")
    b.border(W, D, 16, (90, 85, 80), "Brick", barrier=120)
    # Bodenmarkierungen der Wege
    for z in (-45, 45):
        b.box("Ground", "LaneLine", (W - 20, 0.05, 0.5), (0, 0.03, z), (230, 190, 40), "SmoothPlastic")

    # ---------- Spawns ----------
    for side, group, color in ((-1, "SpawnsA", (200, 120, 40)), (1, "SpawnsB", (130, 70, 180))):
        b.box("Ground", "SpawnPad", (20, 0.3, 46), (side * 138, 0.15, 0), color, "SmoothPlastic")
        for z in (-15, -5, 5, 15):
            b.spawn(side * 138, z, yaw=90 * side, group=group)
        # Deckung vor dem Spawn, drei Ausgänge
        b.cover_wall(side * 122, -22, 14, along_x=False, height=7, color=concrete)
        b.cover_wall(side * 122, 22, 14, along_x=False, height=7, color=concrete)
        b.half_wall(side * 112, 0, 10, along_x=False, color=concrete)
        # Spawnhaus im Norden (zweistöckig, Fenster zur Halle und zum Hof)
        b.building2("SpawnHouse", side * 122, 62, 26, 22, brick, (70, 60, 55),
                    doors={"S": [0], "E" if side < 0 else "W": [4]},
                    windows1={"S": [-8, 8]}, windows2={"S": [-8, 0, 8], "E" if side < 0 else "W": [-5, 5]},
                    stairs_at=("W" if side < 0 else "E",), material="Brick")
        # Kisten und Container im Süden beim Spawn
        b.container(side * 128, -62, along_x=False, color=color)
        b.crate(side * 112, -40)
        b.crate(side * 112, -35, s=4, y=0)
        b.crate(side * 104, -78, s=6)

    # ---------- Norden: Fabrikhalle (zweistöckig, Weg führt hindurch) ----------
    b.building2("Hall", 0, 70, 112, 34, brick, (60, 55, 50),
                doors={"W": [8], "E": [-8], "S": [-36, 0, 36], "N": [-20, 20]},  # neben den Treppen
                windows1={"S": [-48, -20, 20, 48], "N": [-44, 0, 44]},
                windows2={"S": [-50, -38, -26, -14, -2, 10, 22, 34, 46], "N": [-40, -20, 0, 20, 40],
                          "W": [-8, 8], "E": [-8, 8]},
                stairs_at=("W", "E"), h1=11, h2=10, material="Brick")
    # Maschinen in der Halle (Deckung innen)
    for x in (-34, -12, 12, 34):
        b.box("Cover", "Machine", (8, 4.5, 10), (x, 2.25, 72), metal, "Metal")
        b.box("Cover", "MachineTop", (4, 2, 6), (x, 5.5, 72), (200, 160, 40), "Metal")
    # Hintergasse nördlich der Halle mit Fässern
    for x in (-40, -10, 25, 50):
        b.add("Cover", "Barrel", (4, 3, 3), (x, 2, 93), (60, 90, 140), "Metal", angles=(0, 0, 90), props={"Shape": "Cylinder"})

    # ---------- Süden: Containerhof mit Laufsteg ----------
    for x in (-70, -46, 46, 70):
        b.container(x, -58, along_x=True, color=(70, 110, 150) if x < 0 else (150, 70, 60))
    # Kisten oben auf den Containern als Deckung
    for x in (-58, 58):
        b.crate(x, -58, s=4, y=8)
    # Laufsteg quer über die Mitte, auf Containerhöhe, mit halbhoher Brüstung zur Mitte
    b.box("Buildings", "Catwalk", (72, 1, 6), (0, 7.6, -58), metal, "DiamondPlate")
    b.box("Cover", "CatwalkRail", (72, 2.6, 0.5), (0, 9.4, -55.2), (200, 170, 40), "Metal")
    for x in (-30, 0, 30):
        b.box("Buildings", "CatwalkPost", (1, 7.2, 1), (x, 3.6, -58), metal, "Metal")
    # Rampen auf die Container (von außen)
    b.ramp("YardRampW", -80, -58, 6, 22, 8.1, "W")
    b.ramp("YardRampE", 80, -58, 6, 22, 8.1, "E")
    # Südgasse: Container quer und Kisten
    for x in (-24, 24):
        b.container(x, -84, along_x=False, color=(90, 120, 80), length=14)
    for x, z in ((-90, -84), (90, -84), (0, -80), (-50, -88), (50, -88)):
        b.crate(x, z)

    # ---------- Trennwände zwischen den Wegen (Fenster zum Spähen, Durchgänge) ----------
    for side in (-1, 1):
        for zl in (-45, 45):
            # von x = ±58 bis ±104, Tür in der Mitte, zwei Fenster
            a0, a1 = sorted((side * 58, side * 104))
            mid = side * 81
            b.wall_line("LaneWall", a0, a1, zl, True, 7, concrete, "Concrete",
                        openings=[(mid, 6, 0, 7), (mid - 14, 4, 3, 5.4), (mid + 14, 4, 3, 5.4)], group="Cover")

    # ---------- Mitte: Hof mit Eroberungspunkt ----------
    b.add("Objective", "CapturePoint", (0.3, 24, 24), (0, 0.2, 0), (230, 230, 235), "Neon",
          angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.35, "CanCollide": False})
    for x, z in ((-12, -12), (12, -12), (-12, 12), (12, 12)):
        b.box("Objective", "PointPost", (1, 5, 1), (x, 2.5, z), (60, 60, 65), "Metal")
    # Ring aus brusthohen Mauern mit Lücken, dazu hohe Deckung zum Herumspähen
    for x, z, length, ax in ((-20, -18, 10, True), (20, 18, 10, True), (-20, 18, 8, True), (20, -18, 8, True),
                             (-28, 0, 10, False), (28, 0, 10, False)):
        b.half_wall(x, z, length, along_x=ax, color=concrete)
    for x, z in ((0, -30), (0, 30)):
        b.box("Cover", "Kiosk", (10, 8, 6), (x, 4, z), (60, 80, 100), "Metal")
    for x, z in ((-42, -24), (42, 24), (-42, 24), (42, -24), (-60, 0), (60, 0)):
        b.crate(x, z, s=5)
    b.crate(-60, 0, s=4, y=5)
    b.crate(60, 0, s=4, y=5)
    # Schornstein als Orientierung
    b.add("Decor", "Chimney", (40, 7, 7), (0, 20, 95), (130, 90, 75), "Brick", angles=(0, 0, 90), props={"Shape": "Cylinder"})

    b.save(filename)


# ---------- Demolition: "Hafen" (260 x 180), Angreifer bei -x, Ziele A/B bei +x ----------

def build_demolition(origin=DEMOLITION_ORIGIN, filename="Demolition.model.json"):
    """Hafen (330 x 220): Angreifer im Westen, Ziele A (Süden) und B (Norden) im Osten.
    Mitte: zweistöckiges Lagerhaus. Norden: Kai mit Containern und Schiff an B. Süden: Bürogebäude
    mit Fenstern auf den A-Weg. Vor den Zielen eine Mauer mit Durchgang und Fenstern (Mitte-Tür)."""
    b = Builder(origin)
    W, D = 330, 220
    asphalt, concrete, brick, metal = (80, 82, 88), (125, 125, 128), (140, 100, 80), (85, 90, 98)
    b.ground(W + 10, D + 10, asphalt, "Asphalt")
    b.border(W, D, 14, (110, 100, 90), "Brick", barrier=120)
    # Wasser an der Nordkante (Optik) mit Kaimauer
    b.box("Ground", "Water", (W, 0.4, 12), (0, 0.05, D / 2 - 6), (40, 90, 140), "Glass", props={"Transparency": 0.3,
          "CanCollide": False})
    b.box("Cover", "QuayEdge", (W, 1.2, 1), (0, 0.6, D / 2 - 12.5), (180, 170, 40), "Concrete")

    # ---------- Angreifer-Seite (Westen) ----------
    b.box("Ground", "AttackPad", (20, 0.3, 50), (-150, 0.15, 0), (200, 80, 80), "SmoothPlastic")
    b.cover_wall(-132, -24, 14, along_x=False, height=7, color=concrete)
    b.cover_wall(-132, 24, 14, along_x=False, height=7, color=concrete)
    for x, z, ax in ((-118, -60, True), (-118, 60, True), (-105, 0, False)):
        b.container(x, z, along_x=ax, color=(90, 120, 80))
    b.crate(-120, -30)
    b.crate(-120, 30)
    # Trennwände zwischen den Wegen auf Angreifer-Seite (Tür + Fenster)
    for zl in (-42, 42):
        b.wall_line("LaneWall", -95, -55, zl, True, 8, concrete, "Concrete",
                    openings=[(-75, 6, 0, 7.5), (-88, 4, 3, 5.6), (-62, 4, 3, 5.6)], group="Cover")

    # ---------- Mitte: Lagerhaus (zweistöckig) ----------
    b.building2("Warehouse", -15, 0, 56, 40, brick, (70, 65, 60),
                doors={"W": [0], "E": [0], "N": [-14], "S": [14]},
                windows1={"W": [-12, 12], "E": [-12, 12]},
                windows2={"W": [-12, 0, 12], "E": [-14, -4, 6, 14], "N": [-18, -6, 6, 18], "S": [-18, -6, 6, 18]},
                stairs_at=("N", "S"), h1=11, h2=9, material="Brick")
    for x, z in ((-28, -6), (-2, 6)):
        b.box("Cover", "PalletStack", (6, 4, 6), (x, 2, z), (150, 120, 80), "WoodPlanks")

    # ---------- Mauer vor den Zielen (Mitte-Tür) ----------
    b.wall_line("MidWall", -40, 40, 50, False, 9, concrete, "Concrete",
                openings=[(0, 7, 0, 8), (-22, 4, 3.2, 5.8), (22, 4, 3.2, 5.8)], group="Cover")
    b.half_wall(62, 0, 8, along_x=False, color=concrete)

    # ---------- Norden: Kai mit Containern, Kran, Schiff an B ----------
    for x, z, ax, lvl, color in ((-60, 70, True, 0, (70, 110, 150)), (-64, 70, True, 1, (160, 120, 50)),
                                 (-20, 86, True, 0, (150, 70, 60)), (10, 64, False, 0, (90, 120, 80)),
                                 (40, 82, True, 0, (70, 110, 150))):
        b.container(x, z, along_x=ax, level=lvl, color=color, length=20 if lvl == 0 else 10)
    b.ramp("StackRamp", -54, 66, 5, 18, 8.1, "S")  # auf den unteren Container (oberer dient als Deckung)
    for x, z in ((-90, 88), (-35, 62), (25, 92)):
        b.crate(x, z)
    b.box("Decor", "CraneLeg", (2, 32, 2), (-40, 16, 96), (220, 170, 40), "Metal")
    b.box("Decor", "CraneArm", (40, 2, 2), (-30, 33, 96), (220, 170, 40), "Metal")
    # Schiff am Kai bei B (Rumpf als hohe Deckung, Aufbau begehbar über Rampe)
    b.box("Cover", "ShipHull", (44, 7, 12), (110, 3.5, 92), (60, 70, 85), "Metal")
    b.box("Buildings", "ShipCabin", (12, 8, 10), (124, 11, 92), (220, 220, 225), "Metal")
    b.ramp("ShipRamp", 92, 86, 5, 14, 7.1, "S")

    # ---------- Süden: Bürogebäude (zweistöckig) mit Blick auf den A-Weg ----------
    b.building2("Office", -55, -78, 36, 26, (175, 170, 160), (70, 72, 78),
                doors={"N": [-8], "E": [4], "W": [0]},
                windows1={"N": [6], "E": [-6]},
                windows2={"N": [-12, -2, 8], "E": [-6, 6], "S": [-8, 8]},
                stairs_at=("S",), h1=10, h2=9)
    for x, z in ((-10, -70), (10, -92), (30, -66)):
        b.crate(x, z)
    b.container(-5, -96, along_x=True, color=(150, 70, 60))
    b.half_wall(20, -80, 10, along_x=False, color=concrete)

    # ---------- Ziele A und B: Deckung ----------
    for name, z in (("A", -62), ("B", 62)):
        sgn = 1 if z > 0 else -1
        b.container(112, z - sgn * 14, along_x=True, color=(60, 110, 160), length=16)
        b.crate(84, z + sgn * 9)
        b.crate(84, z + sgn * 9, s=4, y=5)
        b.crate(104, z + sgn * 2, s=4)
        b.half_wall(78, z - sgn * 4, 8, along_x=False, color=concrete)
    # Verbindung der Verteidiger zwischen A und B (hinter den Zielen)
    for z in (-24, 24):
        b.cover_wall(140, z, 12, along_x=False, height=7, color=concrete)
    b.crate(150, 0)
    b.box("Decor", "Tower", (8, 26, 8), (150, 13, -95), (200, 200, 205), "Concrete")

    team_objectives(b, -150, 125, (95, -62), (95, 62), spawn_x=150, capture=False)
    b.save(filename, "Hafen")


# ---------- Training: Schießstand (140 x 90), Spieler bei -x, Puppen bei +x ----------

def build_training():
    b = Builder(TRAINING_ORIGIN)
    b.ground(150, 100, (70, 75, 85), "Concrete")
    b.border(140, 90, 10, (60, 62, 72), "SmoothPlastic", barrier=80)
    b.box("Ground", "ShootingLine", (2, 0.3, 80), (-40, 0.15, 0), (255, 200, 60), "Neon")
    for z in (-20, -6, 6, 20):
        b.spawn(-55, z, yaw=-90, group="Spawns")
    # Bahnen mit Entfernungsschildern (Studs ab der Schusslinie)
    for distance in (15, 35, 60, 90):
        x = -40 + distance
        if x < 65:
            b.sign("Distance" + str(distance), (6, 2.5, 0.4), (x, 9, -38), str(distance), (25, 25, 30), (255, 200, 60))
    for z in (-26, 0, 26):
        b.box("Decor", "LaneDivider", (100, 1.2, 0.6), (15, 0.6, z - 13 if z > 0 else z + 13), (90, 95, 110), "SmoothPlastic")
    # Puppen-Positionen (Server spawnt hier Übungspuppen)
    for name, x, z in (("Near", -20, -18), ("Mid", 0, 0), ("Far", 25, 18), ("Wall", 45, -10), ("Run1", 10, -28), ("Run2", 30, 28)):
        b.add("Dummies", "Dummy_" + name, (2, 0.2, 2), (x, 0.1, z), (200, 60, 60), "Neon",
              props={"Transparency": 0.5, "CanCollide": False})
    # Etwas Deckung zum Üben von Peeks
    b.cover_wall(10, 10, 8, along_x=False, height=4)
    b.cover_wall(35, -18, 10, height=5)
    b.crate(-10, 22)
    b.box("Decor", "BackWall", (2, 16, 90), (68, 8, 0), (50, 52, 60), "Concrete")
    b.sign("TrainingSign", (40, 8, 1), (68 - 1.2, 20, 0), "TRAINING", (25, 25, 30), (255, 140, 40), angles=(0, 90, 0))
    b.save("Training.model.json")


# ---------- 1v1 Arena (90 x 70), punktsymmetrisch ----------

def build_arena():
    b = Builder(ARENA_ORIGIN)
    b.ground(100, 80, (92, 90, 86), "Concrete")
    b.border(90, 70, 12, (108, 106, 100), "Concrete", barrier=60)
    b.add("Ground", "CenterRing", (0.2, 16, 16), (0, 0.1, 0), (196, 186, 160), "SmoothPlastic",
          angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.55, "CanCollide": False})
    for side, group in ((-1, "SpawnsA"), (1, "SpawnsB")):
        b.spawn(side * 38, 0, yaw=90 * side, group=group)
        # Deckung gespiegelt
        b.cover_wall(side * 22, side * 12, 10, along_x=False, height=5, color=(124, 122, 116))
        b.cover_wall(side * 10, side * -18, 12, height=5, color=(124, 122, 116))
        b.crate(side * 30, side * -20)
        b.crate(side * 30, side * 20, s=4)
        b.box("Cover", "Pillar", (4, 10, 4), (side * 8, 5, side * 8), (132, 130, 124), "Concrete")
    b.save("Arena.model.json")


# ---------- Gemeinsame Ziel-Ordner für Team-Maps ----------
# Jede Rotations-Map bekommt alles, was Demolition UND Strikeout brauchen:
# SpawnsAtk/SpawnsDef + SiteA/SiteB (Demolition), SpawnsA/SpawnsB + CapturePoint (Strikeout).

def team_objectives(b, atk_x, def_x, site_a, site_b, spawn_x=105, site_color=(255, 80, 80), capture=True,
                    sites=True):
    for z in (-15, -5, 5, 15):
        b.spawn(atk_x, z, yaw=-90, group="SpawnsAtk")
        b.spawn(-spawn_x, z, yaw=-90, group="SpawnsA")
        b.spawn(spawn_x, z, yaw=90, group="SpawnsB")
    for x, z in ((def_x, -10), (def_x, 10), (def_x + 8, -20), (def_x + 8, 20)):
        b.spawn(x, z, yaw=90, group="SpawnsDef")
    for name, (x, z) in ((("A", site_a), ("B", site_b)) if sites else ()):
        b.add("Objective", "Site" + name, (0.3, 20, 20), (x, 0.2, z), site_color, "Neon",
              angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.6, "CanCollide": False})
        b.box("Decor", "SitePost" + name, (1, 10, 1), (x, 5, z), (60, 60, 65), "Metal")
        b.sign("SiteSign" + name, (6, 6, 0.5), (x, 13, z), name, (25, 25, 30), site_color, angles=(0, 90, 0))
    if capture:
        b.add("Objective", "CapturePoint", (0.3, 24, 24), (0, 0.2, 0), (230, 230, 235), "Neon",
              angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.35, "CanCollide": False})


# ---------- "Gletscher": Forschungsstation im Eis (Stil: RC "Glacier") ----------

GLACIER_ORIGIN = (3000, 0, 0)


def build_glacier(origin=GLACIER_ORIGIN, filename="Gletscher.model.json"):
    """Gletscher (300 x 210): Forschungsstation. Zweistöckige Labore an den Zielen mit Fenstern,
    Kantine und Garage auf Angreiferseite, Radarkuppel und Eisschollen als Deckung, Trennwände."""
    b = Builder(origin)
    rng = random.Random(11)
    snow, ice, module, accent = (235, 240, 245), (170, 215, 240), (200, 205, 210), (230, 110, 40)
    W, D = 300, 210
    b.ground(W + 10, D + 10, snow, "Snow")
    b.border(W, D, 10, (210, 225, 235), "Ice", barrier=120)
    # Eisschollen und Schneewehen als Deckung (nicht in Spawns und Zielen)
    for _ in range(22):
        x, z = rng.uniform(-125, 125), rng.uniform(-90, 90)
        if abs(x) < 110 and not (abs(x) < 20 and abs(z) < 20) and not (60 < x < 100 and 40 < abs(z) < 70):
            sx, sz, sy = rng.uniform(5, 10), rng.uniform(4, 9), rng.uniform(3, 6)
            b.box("Cover", "IceBlock", (sx, sy, sz), (x, sy / 2, z), ice, "Glass",
                  angles=(0, rng.uniform(0, 90), rng.uniform(-6, 6)), props={"Transparency": 0.25})
    # Zweistöckige Labore hinter den Zielen (Fenster zum Ziel), Kantine und Garage vorne
    for side in (-1, 1):
        inward = "S" if side > 0 else "N"
        b.building2("Lab", 92, side * 84, 36, 22, module, (90, 95, 100),
                    doors={inward: [-10, 10], "W": [0]}, windows1={inward: [0]},
                    windows2={inward: [-12, -4, 4, 12], "W": [-5, 5]}, stairs_at=("E",), material="Metal")
        b.box("Buildings", "LabStripe", (36.2, 1, 22.2), (92, 9.5, side * 84), accent, "SmoothPlastic")
        b.building2("Mess", -60, side * 66, 26, 20, module, (90, 95, 100),
                    doors={inward: [0], "E": [0]}, windows1={inward: [-8, 8]},
                    windows2={inward: [-8, 0, 8], "E": [-4, 4]}, stairs_at=("W",), material="Metal")
        b.box("Buildings", "MessStripe", (26.2, 1, 20.2), (-60, 9.5, side * 66), accent, "SmoothPlastic")
        # Trennwände mit Fenstern (Angreifer-Seite)
        b.wall_line("SnowWall", -110, -76, side * 36, True, 7, (215, 225, 235), "Ice",
                    openings=[(-93, 6, 0, 7), (-104, 4, 3, 5.4), (-82, 4, 3, 5.4)], group="Cover")
        # Treibstofftanks an den Zielen
        b.add("Cover", "FuelTank", (12, 7, 7), (104, 3.5, side * 40), (220, 200, 60), "Metal", angles=(0, 90, 0),
              props={"Shape": "Cylinder"})
        b.crate(70, side * 62, color=(150, 120, 80))
        b.crate(70, side * 62, s=4, y=5, color=(150, 120, 80))
        b.half_wall(58, side * 46, 10, along_x=False, color=(190, 200, 210))
    # Radarkuppel und Antennenmast in der Mitte
    b.add("Buildings", "RadarBase", (4, 18, 18), (0, 2, 40), module, "Metal", angles=(0, 0, 90), props={"Shape": "Cylinder"})
    b.add("Buildings", "RadarDome", (14, 14, 14), (0, 7, 40), (240, 240, 245), "SmoothPlastic", props={"Shape": "Ball"})
    b.box("Buildings", "Mast", (1.5, 34, 1.5), (0, 17, -40), (90, 95, 100), "Metal")
    b.box("Buildings", "MastLight", (2, 2, 2), (0, 34.5, -40), (255, 60, 50), "Neon")
    # Mitte: Container-Station und Deckung
    b.container(26, 0, along_x=False, color=(200, 90, 40), length=16)
    b.container(-26, 0, along_x=False, color=(200, 90, 40), length=16)
    for x, z in ((40, -24), (40, 24), (-40, -24), (-40, 24), (0, -16), (0, 16)):
        b.crate(x, z, color=(150, 120, 80))
    for x, z, length, ax in ((118, -18, 10, False), (118, 18, 10, False), (-128, -26, 12, False), (-128, 26, 12, False)):
        b.cover_wall(x, z, length, along_x=ax, height=6, color=(190, 200, 210))
    team_objectives(b, -140, 124, (80, -55), (80, 55), spawn_x=140)
    b.save(filename, "Gletscher")


# ---------- "Zellenblock": Gefängnis mit Wachtürmen (Stil: RC "Lockdown") ----------

CELLBLOCK_ORIGIN = (-3000, 0, 0)


def build_cellblock():
    """Zellenblock (300 x 210, symmetrisch für Strikeout): Hof mit Punkt, zweistöckige Zellentrakte im
    Norden/Süden (Galerie mit Fenstern zum Hof), Verwaltung und Krankenstation an den Seiten,
    Küche und Wäscherei, Zäune und Wachtürme."""
    b = Builder(CELLBLOCK_ORIGIN)
    concrete, wall, bars, yard = (150, 148, 140), (120, 118, 112), (60, 62, 66), (110, 112, 108)
    W, D = 300, 210
    b.ground(W + 10, D + 10, yard, "Concrete")
    b.border(W, D, 18, wall, "Concrete", barrier=120)
    b.box("Ground", "Court", (40, 0.1, 24), (0, 0.06, 0), (170, 90, 50), "SmoothPlastic")
    b.box("Ground", "CourtLine", (0.4, 0.12, 24), (0, 0.08, 0), (240, 240, 240), "SmoothPlastic")
    for x, z in ((-140, -95), (140, -95), (-140, 95), (140, 95)):
        b.box("Buildings", "TowerLeg", (6, 20, 6), (x, 10, z), wall, "Concrete")
        b.box("Buildings", "TowerHut", (10, 6, 10), (x, 23, z), concrete, "Concrete")
        b.box("Buildings", "TowerLight", (2, 1, 2), (x, 26.5, z), (255, 240, 200), "Neon")

    for side in (-1, 1):
        inward = "S" if side > 0 else "N"
        # Zellentrakt: unten Türen und Gitterfenster, oben eine Fensterreihe zum Hof
        b.building2("CellBlock", 0, side * 70, 84, 24, concrete, (80, 80, 85),
                    doors={inward: [-28, 0, 28], "W": [side * 4], "E": [-side * 4]},
                    windows1={inward: [-38, -14, 14, 38]},
                    windows2={inward: [-36, -27, -18, -9, 0, 9, 18, 27, 36], "W": [0], "E": [0]},
                    stairs_at=("N" if side > 0 else "S",), h1=10, h2=9)
        # Zellen nur auf der Seite ohne Treppe
        for k in (range(-3, 2) if side > 0 else range(-1, 4)):
            x = k * 11
            b.box("Buildings", "CellWall", (0.6, 9.5, 7), (x, 4.75, side * 78), wall, "Concrete")
            for bar in range(5):
                b.box("Buildings", "Bar", (0.25, 8, 0.25), (x - 4 + bar * 2, 4, side * 74.4), bars, "Metal")
        # Küche / Wäscherei (einstöckig)
        for sx in (-1, 1):
            b.house("Annex", sx * 66, side * 40, 20, 14, 10, (160, 165, 170), (70, 70, 75),
                    doors=(inward, "E" if sx < 0 else "W"), material="Concrete")
        # Verwaltung (Osten) und Krankenstation (Westen): zweistöckig, Türen auf allen Seiten
        b.building2("Admin" if side > 0 else "Infirmary", side * 100, 0, 24, 32, (170, 165, 155), (70, 70, 75),
                    doors={"W": [-8], "E": [8], "N": [0], "S": [0]},
                    windows2={"W" if side > 0 else "E": [-10, 0, 10], "N": [0], "S": [0]},
                    stairs_at=("E" if side > 0 else "W",), material="Brick")
        # Zaun im Hof (durchsichtig) und Deckung
        b.box("Cover", "Fence", (0.3, 6, 26), (side * 30, 3, 0), (130, 135, 140), "Metal", props={"Transparency": 0.4})
        b.half_wall(side * 18, 18, 10, along_x=True, color=concrete)
        b.half_wall(-side * 18, -18, 10, along_x=True, color=concrete)
        b.crate(side * 44, 0)
        b.crate(side * 44, 0, s=4, y=5)
        for z in (-28, 28):
            b.crate(side * 80, z, color=(120, 100, 75))
        b.cover_wall(side * 122, -24, 12, along_x=False, height=7, color=concrete)
        b.cover_wall(side * 122, 24, 12, along_x=False, height=7, color=concrete)
    team_objectives(b, -140, 124, (80, -55), (80, 55), spawn_x=140, sites=False)
    b.save("Zellenblock.model.json", "Zellenblock")


# ---------- "Kanäle": Altstadt am Wasser (Stil: RC "Canals") ----------

def build_canals(origin, filename):
    """Kanäle (300 x 210): Altstadt mit zwei Kanälen (Gräben mit Stufen und Brücken), zweistöckige
    Häuser mit Balkonfenstern, Glockenturm, Marktplatz in der Mitte."""
    b = Builder(origin)
    stone, quay = (190, 180, 160), (150, 140, 120)
    pastel = ((235, 180, 150), (240, 215, 150), (170, 200, 220), (215, 170, 190), (190, 215, 170), (240, 235, 220))
    rng = random.Random(21)
    W, D = 300, 210
    canal_x, canal_w = 42, 14
    for x0, x1 in ((-W / 2, -canal_x - canal_w / 2), (-canal_x + canal_w / 2, canal_x - canal_w / 2),
                   (canal_x + canal_w / 2, W / 2)):
        b.box("Ground", "Ground", (x1 - x0, 4, D), ((x0 + x1) / 2, -2, 0), stone, "Cobblestone")
    for side in (-1, 1):
        x = side * canal_x
        b.box("Ground", "CanalBed", (canal_w, 1, D), (x, -4.5, 0), (60, 70, 70), "Slate")
        b.box("Ground", "Water", (canal_w, 0.4, D), (x, -1.8, 0), (50, 110, 140), "Glass",
              props={"Transparency": 0.35, "CanCollide": False})
        for edge in (-1, 1):
            b.box("Ground", "Quay", (0.8, 0.8, D), (x + edge * (canal_w / 2 + 0.4), 0.4, 0), quay, "Brick")
        for z in (-66, 0, 66):
            b.box("Buildings", "Bridge", (canal_w + 4, 1, 8), (x, 0.5, z), quay, "Brick")
            for rail in (-1, 1):
                b.box("Buildings", "BridgeRail", (canal_w + 4, 1.4, 0.6), (x, 1.7, z + rail * 3.7), stone, "Brick")
        for zs, direction in ((92, -1), (-92, 1), (33, -1), (-33, 1)):
            for edge in (-1, 1):
                sx = x + edge * (canal_w / 2 - 2.2)
                for k in range(4):
                    b.box("Buildings", "Step", (4, 1, 2.2), (sx, -3.5 + k, zs + direction * k * 2.2), quay, "Brick")
    b.border(W, D, 14, (170, 160, 140), "Brick", barrier=120)

    # Zweistöckige Häuser in Pastellfarben (oben Fenster zum Spähen)
    houses = (
        (-108, -72, 26, 20, "N", "E"), (-108, 72, 26, 20, "S", "E"), (-80, 0, 20, 26, "E", "W"),
        (0, -80, 36, 18, "N", None), (0, 80, 36, 18, "S", None),
        (112, -82, 24, 16, "N", "W"), (112, 82, 24, 16, "S", "W"),
    )
    for i, (x, z, w, d, main, extra) in enumerate(houses):
        doors = {main: [0] if main in ("E", "W") else [-6]}
        if extra:
            doors[extra] = [0]
        stairs_side = "W" if main in ("N", "S") and x <= 0 else ("E" if main in ("N", "S") else "N")
        b.building2("House" + str(i), x, z, w, d, pastel[i % len(pastel)], (150, 80, 60), doors=doors,
                    windows1={main: [6] if main in ("N", "S") else [-6, 6]},
                    windows2={main: [-8, 0, 8] if w > 22 or main in ("E", "W") else [-5, 5]},
                    stairs_at=(stairs_side,), material="Plaster")
    # Glockenturm als Orientierungspunkt
    b.box("Buildings", "BellTower", (8, 34, 8), (-12, 17, 46), (200, 160, 120), "Brick")
    b.box("Buildings", "BellTowerTop", (9, 2, 9), (-12, 35, 46), (150, 80, 60), "Slate")
    # Marktstände, Kisten, Mauern
    for x, z in ((-14, -24), (14, 22), (-14, 18), (14, -18)):
        b.box("Cover", "MarketStall", (6, 3.5, 4), (x, 1.75, z), (130, 100, 70), "WoodPlanks")
        b.box("Cover", "Awning", (7, 0.3, 5), (x, 4.2, z), pastel[rng.randint(0, 5)], "Fabric")
    for x, z in ((-120, -30), (-120, 30), (120, 0), (70, -18), (70, 18), (-58, -44), (-58, 44), (24, -50), (-24, 50)):
        b.crate(x, z, color=(140, 105, 70))
    for x, z, length, ax in ((-22, 0, 10, False), (22, 0, 10, False), (90, -38, 10, True), (90, 38, 10, True),
                             (-125, -60, 10, False), (-125, 60, 10, False)):
        b.half_wall(x, z, length, along_x=ax, color=stone)
    for zl in (-40, 40):
        b.wall_line("CanalWall", 54, 76, zl, True, 6, stone, "Brick",
                    openings=[(65, 5, 0, 6)], group="Cover")
    team_objectives(b, -140, 124, (84, -58), (84, 58), spawn_x=140)
    b.save(filename, "Kanäle")


# ---------- "Windmühlen": Küstendorf mit Windmühlen und Hügeln (Stil: RC "Windward") ----------

def build_windmills(origin, filename):
    """Windmühlen (300 x 210): Küstendorf. Zwei Windmühlen, Terrassen im Norden/Süden, zweistöckige
    Cottages und eine Scheune mit Fenstern auf Punkt und Ziele, Trockenmauern mit Fenstern trennen die Wege."""
    b = Builder(origin)
    rng = random.Random(31)
    grass, path, stone, plaster = (95, 140, 70), (165, 150, 120), (160, 155, 145), (235, 228, 210)
    W, D = 300, 210
    b.ground(W + 10, D + 10, grass, "Grass")
    b.border(W, D, 8, (130, 125, 115), "Slate", barrier=120)
    b.box("Ground", "Path", (W, 0.1, 10), (0, 0.06, 0), path, "Ground")
    b.box("Ground", "PathNS", (10, 0.1, D), (0, 0.06, 0), path, "Ground")

    def windmill(name, x, z, face):
        b.box("Buildings", name + "_Tower", (10, 26, 10), (x, 13, z), plaster, "Plaster")
        b.box("Buildings", name + "_Base", (12, 4, 12), (x, 2, z), stone, "Slate")
        b.box("Buildings", name + "_Cap", (11, 3, 11), (x, 27.5, z), (120, 70, 50), "WoodPlanks")
        b.box("Buildings", name + "_Top", (7, 3, 7), (x, 30.5, z), (120, 70, 50), "WoodPlanks", angles=(0, 45, 0))
        hx = x + face * 6
        b.box("Buildings", name + "_Hub", (2, 2.4, 2.4), (hx, 23, z), (70, 60, 50), "Wood")
        for angle in (20, 110):
            b.box("Decor", name + "_Blade", (0.6, 38, 3), (hx + face * 1.2, 23, z), (240, 235, 225), "Fabric",
                  angles=(angle, 0, 0))

    windmill("MillWest", -72, 0, 1)
    windmill("MillEast", 100, 0, -1)

    # Terrassen (erhöhte Positionen) mit Rampen zur Mitte und zu den Seiten
    for side in (-1, 1):
        zc = side * 70
        b.box("Buildings", "Terrace", (40, 6, 34), (0, 3, zc), (120, 115, 100), "Slate")
        b.box("Buildings", "TerraceTop", (40, 0.3, 34), (0, 6.15, zc), grass, "Grass")
        edge = side * 53
        b.ramp("TerraceRamp", -10, edge, 8, 14, 6, "S" if side > 0 else "N")
        b.ramp("TerraceRamp", 10, edge, 8, 14, 6, "S" if side > 0 else "N")
        b.ramp("TerraceRampW", -20, zc, 8, 14, 6, "W")
        b.ramp("TerraceRampE", 20, zc, 8, 14, 6, "E")
        b.box("Cover", "TerraceWall", (12, 3, 1.2), (0, 7.5, zc - side * 10), stone, "Slate")

    # Zweistöckige Cottages
    for side in (-1, 1):
        inward = "S" if side > 0 else "N"
        b.building2("CottageW", -108, side * 72, 26, 20, plaster, (90, 60, 45),
                    doors={inward: [0], "E": [0]}, windows1={inward: [-8, 8]},
                    windows2={inward: [-8, 0, 8], "E": [-4, 4]}, stairs_at=("W",), material="Plaster")
        b.building2("CottageMid", -52, side * 80, 22, 18, plaster, (90, 60, 45),
                    doors={inward: [-5], "W": [0]}, windows1={inward: [5]},
                    windows2={inward: [-6, 6], "E": [0]}, stairs_at=("E",), material="Plaster")
        b.building2("CottageEast", 122, side * 86, 24, 16, plaster, (90, 60, 45),
                    doors={inward: [-6], "W": [0]}, windows2={inward: [-6, 6], "W": [0]}, stairs_at=("E",),
                    material="Plaster")
    # Scheune östlich der Mitte: Fenster auf den Punkt (Westen) und die Ziele (Norden/Süden)
    b.building2("Barn", 46, 0, 18, 28, (150, 70, 50), (80, 50, 40),
                doors={"E": [0], "W": [-8]}, windows1={"W": [6]},
                windows2={"W": [-8, 0, 8], "N": [0], "S": [0], "E": [-6, 6]}, stairs_at=("N",), material="WoodPlanks")

    # Trockenmauern mit Fenstern und Durchgängen
    for zl in (-36, 36):
        b.wall_line("StoneWall", -100, -62, zl, True, 6, stone, "Slate",
                    openings=[(-81, 6, 0, 6), (-93, 4, 2.6, 4.6), (-69, 4, 2.6, 4.6)], group="Cover")
        b.wall_line("StoneWall", 60, 100, zl * 0.6, True, 5, stone, "Slate",
                    openings=[(72, 5, 0, 5), (88, 4, 2.4, 4.2)], group="Cover")
    for x, z, length, ax in ((-30, -24, 12, False), (-30, 24, 12, False), (20, -30, 10, True), (20, 30, 10, True),
                             (112, -40, 10, False), (112, 40, 10, False)):
        b.half_wall(x, z, length, along_x=ax, color=stone)
    for x, z in ((-120, 0), (-44, -46), (-44, 46), (62, -30), (62, 30), (8, -20), (-8, 20)):
        b.add("Cover", "HayBale", (5, 5, 5), (x, 2.5, z), (215, 185, 95), "Fabric", angles=(0, 0, 90),
              props={"Shape": "Cylinder"})
    for x, z in ((-80, -55), (-80, 55), (92, -22), (92, 22), (70, -70), (70, 70)):
        b.crate(x, z, color=(140, 105, 70))
    for z in (-100, 100):
        for k in range(-7, 8):
            b.box("Decor", "FencePost", (0.6, 3, 0.6), (k * 19, 1.5, z), (110, 80, 55), "Wood")
    for _ in range(16):
        x, z = rng.uniform(-140, 140), rng.choice((-1, 1)) * rng.uniform(95, 101)
        if abs(x) > 15:
            b.tree(x, z, rng)

    team_objectives(b, -140, 122, (80, -55), (80, 55), spawn_x=140)
    b.save(filename, "Windmühlen")


# ---------- "Hochhaus": Dach eines Wolkenkratzers (Stil: RC "Hightower") ----------

def build_hightower(origin, filename):
    """Hochhaus (260 x 180): Dach eines Wolkenkratzers. Zweistöckige Penthäuser im Norden/Süden mit
    Fensterfront zum Landeplatz, Treppenhaus-Türme, Klimageräte, Solarfelder und Oberlichter als Deckung."""
    b = Builder(origin)
    rng = random.Random(41)
    roof, dark, metal, glass = (120, 122, 128), (70, 72, 78), (150, 155, 160), (120, 160, 190)
    W, D = 260, 180
    b.ground(W + 10, D + 10, roof, "Concrete")
    b.border(W, D, 4, dark, "Concrete", barrier=120)
    for _ in range(28):
        angle = rng.uniform(0, math.tau)
        dist = rng.uniform(210, 300)
        x, z = math.cos(angle) * dist * 1.2, math.sin(angle) * dist
        w, h = rng.uniform(25, 45), rng.uniform(40, 140)
        b.box("Decor", "Skyscraper", (w, h, w), (x, h / 2 - 60, z),
              rng.choice(((95, 110, 130), (80, 90, 105), (120, 130, 145))), "Glass")
    b.box("Decor", "Facade", (W + 6, 60, D + 6), (0, -32, 0), (85, 95, 110), "Glass")

    # Landeplatz in der Mitte
    b.add("Ground", "Helipad", (0.1, 30, 30), (0, 0.05, 0), (55, 57, 62), "SmoothPlastic", angles=(0, 0, 90),
          props={"Shape": "Cylinder"})
    for size, pos in (((1.6, 0.12, 10), (-3, 0.07, 0)), ((1.6, 0.12, 10), (3, 0.07, 0)), ((6, 0.12, 1.6), (0, 0.07, 0))):
        b.box("Ground", "HelipadH", size, pos, (240, 200, 50), "SmoothPlastic")

    for side in (-1, 1):
        b.box("Ground", "SpawnPad", (22, 0.2, 46), (side * 116, 0.1, 0), dark, "DiamondPlate")
        for z in (-28, 28):
            b.box("Cover", "ACUnit", (7, 5, 9), (side * 90, 2.5, z), metal, "Metal")
            b.box("Decor", "ACFan", (5, 0.3, 5), (side * 90, 5.15, z), dark, "Metal")
        b.box("Cover", "Duct", (3, 3.2, 30), (side * 46, 1.6, 0), metal, "Metal")
        b.box("Buildings", "StairTower", (9, 13, 9), (side * 68, 6.5, 0), (100, 102, 108), "Concrete")
        for z in (-36, 36):
            for k in range(3):
                b.box("Cover", "Solar", (8, 0.4, 4), (side * 28, 1.6, z + (k - 1) * 5), (40, 55, 90), "Glass",
                      angles=(0, 0, side * 20))
                b.box("Cover", "SolarFrame", (6, 1.4, 0.5), (side * 28, 0.7, z + (k - 1) * 5), dark, "Metal")
        for z in (-14, 14):
            b.box("Cover", "Skylight", (8, 2, 6), (side * 20, 1, z), glass, "Glass", props={"Transparency": 0.3})
        b.add("Cover", "WaterTank", (10, 9, 9), (side * 104, 5, side * 66), (130, 100, 75), "WoodPlanks",
              props={"Shape": "Cylinder"})
        # Penthaus (zweistöckig) mit Glasfront zum Landeplatz
        inward = "S" if side > 0 else "N"
        b.building2("Penthouse", 0, side * 64, 46, 24, (200, 200, 205), (60, 62, 68),
                    doors={inward: [-14, 14], "E": [0], "W": [0]}, windows1={inward: [0]},
                    windows2={inward: [-18, -9, 0, 9, 18], "E": [-5, 5], "W": [-5, 5]},
                    stairs_at=("N" if side > 0 else "S",), h1=10, h2=9)
        b.box("Buildings", "GlassBand", (46.2, 1.2, 24.2), (0, 9.6, side * 64), glass, "Glass", props={"Transparency": 0.2})
        b.half_wall(side * 38, side * 46, 10, along_x=True, color=(150, 152, 158))
    # Werbetafel und Antenne
    for x in (-12, 12):
        b.box("Decor", "BillboardPost", (1, 10, 1), (x, 25, 70), dark, "Metal")
    b.sign("Billboard", (30, 9, 0.6), (0, 33, 70), "SHOOTOUT", (15, 22, 36), (40, 210, 230), angles=(0, 180, 0))
    b.box("Decor", "Antenna", (1.2, 30, 1.2), (8, 34, -70), metal, "Metal")
    b.box("Decor", "AntennaLight", (1.8, 1.8, 1.8), (8, 49.5, -70), (255, 50, 40), "Neon")

    team_objectives(b, -118, 100, (70, -40), (70, 40), spawn_x=118)
    b.save(filename, "Hochhaus")


# ---------- Hub (Lobby): Hangar/Safehouse im Stil der Rogue-Company-Lobby ----------

# Einsatz-Tore an den Hallenwänden (Ids wie in src/shared/Modes.lua): je Seite 5, jedes in eigener Farbe
# (Id, Titel, Unterzeile, Farbe)
# Westen: normale Modi, Osten: Kategorie DUELS (mit eigenem Banner)
HUB_GATES_WEST = (
    ("FreeForAll", "FREE-FOR-ALL", "JEDER GEGEN JEDEN", (200, 110, 70), -30),
    ("Domination", "HERRSCHAFT", "5v5 · FLAGGEN HALTEN", (90, 140, 190), 6),
    ("Training", "TRAINING", "SCHIESSSTAND", (180, 184, 190), 42),
)
HUB_GATES_EAST = (
    ("Wingman", "WINGMAN", "DUELS · 2v2", (120, 150, 110), -12),
    ("Arena", "1v1 ARENA", "DUELS · 1v1", (180, 80, 70), 24),
)
AMBER = (212, 170, 80)  # Signalfarbe des Hubs (wie im UI)


def build_lobby_classic():
    """Alter Hub (große Hangar-Halle mit Toren an den Seitenwänden, Ruhmeshalle, Rollfeld).
    Aktivieren: HUB_STYLE = "classic". Fertige Datei liegt auch in tools/saved/Hub_classic.model.json."""
    b = Builder(HUB_ORIGIN)
    rng = random.Random(3)
    cyl = {"Shape": "Cylinder"}
    # Dunkle Halle (helle Flächen blenden), Farbe kommt von Toren, Schildern und Lichtleisten
    floor = (26, 28, 34)
    steel = (40, 43, 50)
    wall = (30, 33, 40)
    navy = (20, 22, 26)  # Graphit für Schilder und Teppich

    # Außen: Vorfeld und Rollfeld
    b.ground(300, 380, (62, 64, 68), "Asphalt")
    b.border(290, 360, 3, (90, 90, 95), "Metal", barrier=90)

    # ---------- Halle (innen x -75..75, z -60..75, 36 hoch) ----------
    W, D0, D1, H = 75, -60, 75, 36
    zc = (D0 + D1) / 2
    b.box("Ground", "HangarFloor", (2 * W, 0.2, D1 - D0), (0, 0.1, zc), floor, "Slate")
    # Teppich-Laufsteg vom Spawn zur Bühne, Lichtleisten am Rand
    b.box("Ground", "Runner", (12, 0.06, 64), (0, 0.23, -26), navy, "Fabric")
    for x in (-6.2, 6.2):
        b.box("Ground", "RunnerEdge", (0.5, 0.08, 64), (x, 0.24, -26), AMBER, "Neon", props={"Transparency": 0.2})
    # Team-Raute in der Mitte
    b.box("Ground", "EmblemOuter", (18, 0.06, 18), (0, 0.25, 0), AMBER, "Neon", angles=(0, 45, 0), props={"Transparency": 0.3})
    b.box("Ground", "EmblemInner", (14, 0.08, 14), (0, 0.27, 0), navy, "SmoothPlastic", angles=(0, 45, 0))

    # Wände: Süd geschlossen, Nord mit großem Hallentor
    # Südwand mit Durchgang (14 breit, 13 hoch) zur Ruhmeshalle
    b.wall_line("WallSouth", -W - 2, W + 2, D0 - 1, True, H, wall, "Metal", openings=[(0, 14, 0, 13)], t=2,
                group="Walls")
    b.box("Walls", "WallWest", (2, H, D1 - D0), (-W - 1, H / 2, zc), wall, "Metal")
    b.box("Walls", "WallEast", (2, H, D1 - D0), (W + 1, H / 2, zc), wall, "Metal")
    # Dunkler Sockel unten an den Wänden
    for x in (-W + 0.1, W - 0.1):
        b.box("Walls", "WallBase", (0.2, 3, D1 - D0), (x, 1.5, zc), (16, 18, 22), "Metal")
    door = 36
    for side in (-1, 1):
        seg = W - door
        b.box("Walls", "WallNorth", (seg + 2, H, 2), (side * (door + seg / 2 + 1), H / 2, D1 + 1), wall, "Metal")
        b.box("Walls", "DoorPanel", (14, 28, 1.2), (side * (door + 8), 14, D1 + 3), (50, 54, 60), "CorrodedMetal")
    b.box("Walls", "DoorLintel", (2 * door, H - 28, 2), (0, 28 + (H - 28) / 2, D1 + 1), wall, "Metal")
    # Dach, Stahlträger, viele helle Deckenlampen
    b.box("Walls", "Roof", (2 * W + 4, 1, D1 - D0 + 4), (0, H + 0.5, zc), (18, 20, 24), "Metal")
    for z in range(D0 + 8, D1, 13):
        b.box("Walls", "Truss", (2 * W, 1.6, 1.2), (0, H - 1.5, z), steel, "Metal")
        for x in (-50, -25, 0, 25, 50):
            b.box("Decor", "CeilingLamp", (6, 0.3, 0.8), (x, H - 2.6, z), (150, 185, 205), "Neon",
                  children=[{"Name": "Light", "ClassName": "PointLight",
                             "Properties": {"Range": 34, "Brightness": 0.9, "Color": rgb(190, 215, 235)}}])
    for x in (-55, -25, 25, 55):
        b.box("Walls", "Beam", (1.2, 1.6, D1 - D0), (x, H - 3.4, zc), steel, "Metal")
    # Großes Banner unter dem Dach (zum Spawn gerichtet)
    b.sign2("Banner", (56, 11, 0.6), (0, 27, -6), "SHOOTOUT", "WÄHLE DEINEN EINSATZ  ·  LAUF DURCH EIN TOR",
            navy, AMBER, (228, 231, 235), glow=AMBER)
    for x in (-24, 24):
        b.box("Decor", "BannerCable", (0.3, 4, 0.3), (x, 34.5, -6), (40, 40, 45), "Metal")

    # Spawn im Süden, Blick zur Bühne und zum Hallentor
    b.spawn(0, -46, yaw=180, real=True)

    # ---------- Lineup-Bühne mit Spotlights und Bildschirm ----------
    b.box("Decor", "Stage", (40, 1.2, 10), (0, 0.6, 18), (30, 34, 42), "DiamondPlate")
    b.box("Decor", "StageEdge", (40, 0.2, 0.4), (0, 1.25, 13), AMBER, "Neon")
    b.add("Decor", "LineupSpot", (1, 0.2, 1), (0, 1.2, 18), AMBER, "SmoothPlastic",
          props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
    for x in (-15, -5, 5, 15):
        b.add("Decor", "Spotlight", (H - 4, 4, 4), (x, (H - 4) / 2 + 1, 18), (255, 250, 235), "Neon", angles=(0, 0, 90),
              props={"Shape": "Cylinder", "Transparency": 0.9, "CanCollide": False, "CanQuery": False})
    b.sign("BriefingScreen", (34, 10, 0.6), (0, 14, 26), "TACTICAL OPERATIONS", navy, AMBER)
    # Einsatz-Tafel (Client zeigt darauf live die Spielerzahlen pro Modus)
    b.box("Decor", "MissionBoard", (26, 12, 0.6), (0, 24, D0 + 0.4), navy, "SmoothPlastic", angles=(0, 180, 0))

    # ---------- Ruhmeshalle: eigener Raum hinter der Südwand (Bestenlisten + Siegertreppchen) ----------
    gold = (212, 176, 96)
    R0, RW, RH = D0 - 46, 36, 22  # Raum: z R0..D0, x -RW..RW, Höhe RH
    rz = (R0 + D0) / 2
    b.box("Ground", "FameFloor", (2 * RW, 0.2, D0 - R0), (0, 0.1, rz), (20, 22, 28), "Marble")
    b.box("Ground", "FameCarpet", (14, 0.06, D0 - R0 - 6), (0, 0.23, rz + 3), (90, 20, 30), "Fabric")
    b.box("Walls", "FameWallW", (2, RH, D0 - R0), (-RW - 1, RH / 2, rz), wall, "Metal")
    b.box("Walls", "FameWallE", (2, RH, D0 - R0), (RW + 1, RH / 2, rz), wall, "Metal")
    b.box("Walls", "FameWallS", (2 * RW + 4, RH, 2), (0, RH / 2, R0 - 1), wall, "Metal")
    b.box("Walls", "FameRoof", (2 * RW + 4, 1, D0 - R0 + 2), (0, RH + 0.5, rz), (18, 20, 24), "Metal")
    for x in (-20, 0, 20):
        for z in (R0 + 12, R0 + 32):
            b.box("Decor", "FameLamp", (5, 0.3, 0.8), (x, RH - 0.6, z), (220, 190, 120), "Neon",
                  children=[{"Name": "Light", "ClassName": "PointLight",
                             "Properties": {"Range": 28, "Brightness": 1, "Color": rgb(255, 225, 170)}}])
    # Siegertreppchen (Top 3 Ranked), Statuen setzt der Server, Blick zum Eingang (Norden)
    pz = R0 + 14
    for place, x, h, color in ((1, 0, 4.5, gold), (2, -8, 3.2, (200, 205, 215)), (3, 8, 2.2, (205, 130, 70))):
        b.box("Decor", "PodiumBase", (7.6, h, 7.6), (x, h / 2, pz), (30, 34, 42), "Metal")
        b.box("Decor", "PodiumTop", (7.8, 0.4, 7.8), (x, h + 0.2, pz), color, "Metal")
        b.box("Decor", "PodiumEdge", (7.8, 0.3, 0.3), (x, h - 0.4, pz + 3.9), color, "Neon")
        b.add("Podium", "Podium" + str(place), (2, 0.2, 2), (x, h + 0.5, pz), color, "SmoothPlastic", angles=(0, 180, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
        b.sign("PodiumNumber", (3, 2, 0.3), (x, h / 2, pz + 3.95), str(place), (30, 34, 42), color, angles=(0, 180, 0))
    b.add("Decor", "PodiumGlow", (0.2, 26, 26), (0, 0.3, pz), gold, "Neon", angles=(0, 0, 90),
          props={"Shape": "Cylinder", "Transparency": 0.75, "CanCollide": False},
          children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {
              "Range": 20, "Brightness": 1.5, "Color": rgb(255, 220, 140)}}])
    b.sign2("PodiumTitle", (24, 5, 0.4), (0, 15, R0 + 3), "TOP 3 · ELO", "DIE BESTEN SPIELER DER SAISON",
            navy, gold, (228, 231, 235), angles=(0, 180, 0), glow=gold)
    # Bestenlisten an den Seitenwänden (je zwei, zur Raummitte gerichtet)
    for x, yaw, inward, boards in ((-RW + 0.4, -90, 1, (("Elo", gold, R0 + 32), ("Kills", (206, 70, 58), R0 + 12))),
                                   (RW - 0.4, 90, -1, (("Level", (96, 164, 214), R0 + 32), ("Wins", (112, 178, 112), R0 + 12)))):
        for board, color, z in boards:
            b.box("Decor", "LeaderboardFrame", (19, 15, 0.4), (x, 10, z), (30, 34, 42), "Metal", angles=(0, yaw, 0))
            b.box("Decor", "Leaderboard_" + board, (18, 14, 0.6), (x + inward * 0.5, 10, z), navy, "SmoothPlastic",
                  angles=(0, yaw, 0))
            b.box("Decor", "LeaderboardTopStrip", (19, 0.5, 0.8), (x + inward * 0.5, 17.6, z), color, "Neon",
                  angles=(0, yaw, 0))
    # Durchgang in der Südwand der Haupthalle mit Schild
    b.sign2("FameSign", (22, 4, 0.4), (0, 16, D0 + 0.6), "RUHMESHALLE", "BESTENLISTEN · TOP 3",
            navy, gold, (228, 231, 235), angles=(0, 180, 0), glow=gold)

    # ---------- Einsatz-Tore: groß, farbig, mit Schild und Spielerzahl ----------
    def gate(x, z, yaw, inward, mode_id, title, subtitle, color):
        dark = (24, 28, 36)
        gw, gh = 18, 20  # Öffnung
        for dz in (-gw / 2 - 1, gw / 2 + 1):
            b.box("Decor", "GatePillar", (2.4, gh + 2, 2.4), (x + inward * 0.6, (gh + 2) / 2, z + dz), dark, "Metal")
            b.box("Decor", "GateStrip", (0.4, gh, 0.6), (x + inward * 1.9, gh / 2 + 1, z + dz), color, "Neon")
        b.box("Decor", "GateHeader", (2.4, 2, gw + 4.8), (x + inward * 0.6, gh + 2, z), dark, "Metal")
        b.box("Decor", "GateHeaderStrip", (0.3, 0.5, gw + 4.8), (x + inward * 1.85, gh + 1.4, z), color, "Neon")
        b.box("Decor", "GateGlow", (0.3, gh, gw), (x + inward * 0.3, gh / 2, z), color, "ForceField",
              props={"Transparency": 0.2, "CanCollide": False},
              children=[{"Name": "Light", "ClassName": "PointLight",
                         "Properties": {"Range": 22, "Brightness": 2.2, "Color": rgb(*color)}}])
        # Großes Schild über dem Tor
        b.sign2("Sign_" + mode_id, (24, 7, 0.5), (x + inward * 1.2, gh + 7.2, z), title, subtitle,
                navy, color, (228, 231, 235), angles=(0, yaw, 0), glow=color)
        # Spielerzahl (füllt der Client)
        b.box("Decor", "GateCount_" + mode_id, (12, 2.2, 0.4), (x + inward * 1.2, gh + 2.4, z), navy, "SmoothPlastic",
              angles=(0, yaw, 0))
        # Farbige Bodenspur von der Mitte zum Tor und leuchtendes Feld davor
        lane = W - 26
        b.box("Ground", "Lane", (lane, 0.05, 1.4), (x + inward * (lane / 2 + 6), 0.24, z), color, "Neon",
              props={"Transparency": 0.35})
        b.add("Portals", "Portal_" + mode_id, (8, 0.3, gw - 2), (x + inward * 5, 0.4, z), color, "Neon",
              props={"CanCollide": False, "Transparency": 0.45})
    for mode_id, title, sub, color, z in HUB_GATES_WEST:
        gate(-W + 0.6, z, -90, 1, mode_id, title, sub, color)
    for mode_id, title, sub, color, z in HUB_GATES_EAST:
        gate(W - 0.6, z, 90, -1, mode_id, title, sub, color)
    # Kategorie-Banner über den Duell-Toren
    b.sign2("DuelsBanner", (44, 5, 0.5), (W - 1.4, 33.3, 6), "DUELS", "WINGMAN 2v2  ·  1v1 ARENA",
            navy, AMBER, (228, 231, 235), angles=(0, 90, 0), glow=AMBER)

    # ---------- Ausstattung: Spinde, Waffenregale, Werkbänke, Kisten ----------
    for x in range(-44, 45, 5):
        if abs(x) > 15:
            b.box("Decor", "Locker", (4.4, 9, 2.4), (x, 4.5, D0 + 1.4), (55, 70, 85), "Metal")
            b.box("Decor", "LockerVent", (3.6, 0.3, 0.1), (x, 7.5, D0 + 2.65), (25, 30, 36), "Metal")
    for x in (-30, 30):
        b.box("Decor", "WeaponRack", (14, 7, 1.2), (x, 3.5, D0 + 6), (40, 44, 52), "Metal")
        for k in range(4):
            b.box("Decor", "RackGun", (0.4, 4.4, 0.6), (x - 5 + k * 3.3, 3.8, D0 + 6.8), (25, 25, 28), "Metal",
                  angles=(0, 0, 8))
    for x, z in ((-52, 68), (52, 68)):
        b.box("Decor", "Workbench", (12, 3.2, 5), (x, 1.6, z), (80, 70, 60), "WoodPlanks")
        b.sign("Monitor", (5, 3, 0.3), (x, 5.2, z - 2.2), "BRIEFING", navy, AMBER)
    for x, z, size in ((-64, 70, 5), (-64, 65, 4), (64, 70, 5), (64, 65, 4)):
        b.crate(x, z, s=size, color=(110, 95, 70))

    # ---------- Draußen: Rollfeld mit Absetzflugzeug ----------
    b.box("Ground", "Runway", (290, 0.12, 40), (0, 0.06, 140), (45, 47, 52), "Asphalt")
    for x in range(-130, 131, 20):
        b.box("Ground", "RunwayMark", (10, 0.13, 1.2), (x, 0.07, 140), (235, 235, 235), "SmoothPlastic")
    b.box("Ground", "Apron", (80, 0.1, 40), (0, 0.05, 98), (55, 57, 62), "Concrete")
    plane = (150, 158, 150)
    b.add("Decor", "Fuselage", (64, 11, 11), (0, 8, 138), plane, "Metal", angles=(0, 90, 0), props=cyl)
    b.add("Decor", "Nose", (11, 11, 11), (0, 8, 106), plane, "Metal", props={"Shape": "Ball"})
    b.box("Decor", "Cockpit", (6, 2.5, 4), (0, 12, 108), (40, 70, 90), "Glass")
    b.box("Decor", "Wings", (78, 1.4, 13), (0, 10, 134), plane, "Metal")
    b.box("Decor", "TailFin", (1.4, 12, 9), (0, 18, 166), plane, "Metal")
    b.box("Decor", "TailWing", (26, 1.2, 7), (0, 12, 166), plane, "Metal")
    for x in (-26, -14, 14, 26):
        b.add("Decor", "Engine", (8, 3.6, 3.6), (x, 8, 132), (60, 64, 70), "Metal", angles=(0, 90, 0), props=cyl)
    for x in range(-135, 136, 27):
        b.box("Decor", "RunwayLightPost", (0.6, 3, 0.6), (x, 1.5, 162), (50, 50, 55), "Metal")
        b.add("Decor", "RunwayLight", (1, 1, 1), (x, 3.3, 162), (255, 60, 50), "Neon", props={"Shape": "Ball"})
    for x in range(-140, 141, 8):
        b.box("Decor", "FencePost", (0.4, 5, 0.4), (x, 2.5, 175), (80, 80, 85), "Metal")
    b.box("Decor", "FenceMesh", (280, 4.4, 0.15), (0, 2.6, 175), (120, 125, 130), "Metal", props={"Transparency": 0.6})
    placed = 0
    while placed < 16:
        x, z = rng.uniform(-135, 135), rng.uniform(-170, -75)
        if abs(x) > 48 or z < -118:  # nicht auf der Ruhmeshalle
            b.tree(x, z, rng)
            placed += 1

    b.save("Hub.model.json")



# ---------- Hub (kompakt): Einsatzzentrale ----------
# Eine Halle (110 x 84): Spawn im Süden, Laufsteg zum Kartentisch (Hologramm), Ring um den Tisch und weiter
# bis vor die Tore; alle Tore nebeneinander an der Nordwand (DUELS rechts), farbige Spuren vom Tisch bis in
# die Portale, Modus-Namen groß am Boden. Westen: Bühne mit dem eigenen Agenten. Osten: Bestenlisten und
# Siegertreppchen. Rückwand: Einsatz-Bildschirm, Logo, Plakate.

HUB_STYLE = "compact"  # "classic" = alter großer Hangar (build_lobby_classic)
HOLO_SIGNS = True      # alle Schilder im Hub als Hologramme (False = dunkle Tafeln)

HUB_GATES_NORTH = (
    ("FreeForAll", "FREE-FOR-ALL", "JEDER GEGEN JEDEN", (210, 120, 80), -40),
    ("Domination", "HERRSCHAFT", "5v5 · FLAGGEN HALTEN", (100, 150, 205), -20),
    ("Training", "TRAINING", "SCHIESSSTAND", (190, 194, 200), 0),
    ("Wingman", "WINGMAN", "DUELS · 2v2", (130, 170, 115), 20),
    ("Arena", "1v1 ARENA", "DUELS · 1v1", (205, 90, 80), 40),
)


def build_lobby():
    if HUB_STYLE == "classic":
        build_lobby_classic()
        return
    b = Builder(HUB_ORIGIN)
    b.holo = HOLO_SIGNS
    rng = random.Random(5)

    def client_board(name, size, pos, angles=(0, 0, 0)):
        """Tafel, die der Client beschreibt: als Hologramm (Glas) oder dunkle Fläche."""
        if b.holo:
            b.holo_panel("Decor", name, size, pos, angles)
        else:
            b.box("Decor", name, size, pos, graphite, "SmoothPlastic", angles=angles)
    # Mittelhell: zwischen der ganz dunklen und der hellen Version, Akzent kühles Hellblau
    # gedämpft: dunkler Boden und Wände, damit nichts blendet
    floor, wall, steel, graphite = (34, 37, 43), (46, 50, 57), (62, 66, 74), (22, 25, 30)
    walkway, accent = (30, 33, 40), (120, 185, 235)
    x0, x1, z0, z1, H = -55, 55, -38, 46, 26
    zc = (z0 + z1) / 2
    tz = 0          # Kartentisch
    gate_z = z1 - 0.6

    b.ground(160, 160, (40, 42, 46), "Asphalt")
    b.border(150, 150, 2, (60, 60, 65), "Metal", barrier=80)

    # ---------- Boden, Wände, Dach ----------
    b.box("Ground", "HubFloor", (x1 - x0, 0.2, z1 - z0), (0, 0.1, zc), floor, "Concrete")
    for x in range(-50, 51, 10):
        b.box("Ground", "GridLine", (0.12, 0.04, z1 - z0), (x, 0.21, zc), (48, 52, 60), "SmoothPlastic")
    for z in range(-30, 46, 10):
        b.box("Ground", "GridLine", (x1 - x0, 0.04, 0.12), (0, 0.21, z), (48, 52, 60), "SmoothPlastic")
    b.box("Walls", "WallSouth", (x1 - x0 + 4, H, 2), (0, H / 2, z0 - 1), wall, "Metal")
    b.box("Walls", "WallNorth", (x1 - x0 + 4, H, 2), (0, H / 2, z1 + 1), wall, "Metal")
    b.box("Walls", "WallWest", (2, H, z1 - z0), (x0 - 1, H / 2, zc), wall, "Metal")
    b.box("Walls", "WallEast", (2, H, z1 - z0), (x1 + 1, H / 2, zc), wall, "Metal")
    for x in (x0 + 0.1, x1 - 0.1):
        b.box("Walls", "WallBase", (0.2, 2.4, z1 - z0), (x, 1.2, zc), (34, 37, 43), "Metal")
    b.box("Walls", "Roof", (x1 - x0 + 4, 1, z1 - z0 + 4), (0, H + 0.5, zc), (26, 28, 32), "Metal")
    for z in range(-30, 46, 12):
        b.box("Walls", "Truss", (x1 - x0, 1.2, 1), (0, H - 1, z), steel, "Metal")
        for x in (-36, -12, 12, 36):
            b.box("Decor", "CeilingLamp", (5, 0.2, 0.6), (x, H - 1.75, z), (150, 158, 170), "Neon",
                  children=[{"Name": "Light", "ClassName": "PointLight",
                             "Properties": {"Range": 26, "Brightness": 0.5, "Color": rgb(210, 220, 235)}}])
    for x in (x0 + 0.45, x1 - 0.45):
        b.box("Decor", "WallBand", (0.15, 0.25, z1 - z0 - 4), (x, 10.5, zc), accent, "Neon", props={"Transparency": 0.6})
    for x, z in ((-31, 24), (31, 24)):
        b.box("Walls", "Pillar", (2.4, H, 2.4), (x, H / 2, z), steel, "Metal")
        b.box("Decor", "PillarStrip", (2.5, 0.3, 2.5), (x, 3.2, z), accent, "Neon", props={"Transparency": 0.5})

    b.spawn(0, -31, yaw=180, real=True, hidden=True)

    # ---------- Teppich: Spawn -> Ring um den Tisch -> je eine Bahn bis in jedes Portal ----------
    # Alle Teppichteile liegen auf derselben Höhe, ihre Leuchtränder etwas tiefer und breiter darunter:
    # wo sich Bahnen überlappen, deckt der Teppich die Ränder ab – sichtbar bleibt nur der Außenrand.
    ring_r = 13
    def carpet(name, start, finish, width):
        (ax, az), (bx, bz) = start, finish
        length = math.hypot(bx - ax, bz - az)
        yaw = math.degrees(math.atan2(bx - ax, bz - az))
        center = ((ax + bx) / 2, (az + bz) / 2)
        b.box("Ground", name + "Edge", (width + 0.7, 0.03, length + 0.7), (center[0], 0.215, center[1]), accent, "Neon",
              angles=(0, yaw, 0), props={"Transparency": 0.5})
        b.box("Ground", name, (width, 0.05, length), (center[0], 0.245, center[1]), walkway, "SmoothPlastic",
              angles=(0, yaw, 0))
    carpet("CarpetSpawn", (0, z0 + 2), (0, tz - ring_r + 3), 10)
    b.add("Ground", "CarpetRingEdge", (0.03, ring_r * 2 + 0.7, ring_r * 2 + 0.7), (0, 0.215, tz), accent, "Neon",
          angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.3})
    b.add("Ground", "CarpetRing", (0.05, ring_r * 2, ring_r * 2), (0, 0.245, tz), walkway, "SmoothPlastic",
          angles=(0, 0, 90), props={"Shape": "Cylinder"})
    # gerade weiter nach Norden und eine breite Fläche vor der ganzen Torreihe (man läuft gerade in jedes Tor)
    plaza_z = 27
    carpet("CarpetNorth", (0, tz + ring_r - 3), (0, plaza_z + 1), 10)
    carpet("CarpetPlaza", (0, plaza_z), (0, gate_z - 1), 100)

    # ---------- Mitte: Agent der Woche (Statue setzt der Client, wechselt jede Woche) ----------
    b.add("Decor", "AgentPedestalBase", (1.2, 15, 15), (0, 0.6, tz), steel, "Metal", angles=(0, 0, 90),
          props={"Shape": "Cylinder"})
    b.add("Decor", "AgentPedestal", (2.4, 10.5, 10.5), (0, 2.4, tz), (34, 37, 43), "Metal", angles=(0, 0, 90),
          props={"Shape": "Cylinder"})
    b.add("Decor", "AgentPedestalRing", (0.2, 10.9, 10.9), (0, 3.5, tz), accent, "Neon", angles=(0, 0, 90),
          props={"Shape": "Cylinder", "Transparency": 0.2})
    b.add("Decor", "AgentPedestalGlow", (0.2, 15.4, 15.4), (0, 1.15, tz), accent, "Neon", angles=(0, 0, 90),
          props={"Shape": "Cylinder", "Transparency": 0.55},
          children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {
              "Range": 14, "Brightness": 0.7, "Color": rgb(170, 210, 240)}}])
    # Standpunkt der Statue (Füße, Blick zum Spawn nach Süden)
    b.add("Decor", "AgentOfWeekSpot", (1, 0.2, 1), (0, 3.6, tz), accent, "SmoothPlastic", angles=(0, 180, 0),
          props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
    # Holo-Schrift schwebt über der Statue (setzt der Client an diesen Punkt)
    b.add("Decor", "AgentOfWeekHolo", (1, 1, 1), (0, 17, tz), accent, "SmoothPlastic",
          props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
    # Lichtkegel von oben
    for x in (-3, 3):
        b.add("Decor", "Spotlight", (H - 6, 2.6, 2.6), (x, (H - 6) / 2 + 3.5, tz), (255, 248, 230), "Neon",
              angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.93, "CanCollide": False, "CanQuery": False})

    # ---------- Nordwand: große Tore, Schilder leicht zum Spawn geneigt ----------
    gw, gh = 14, 15
    for mode_id, title, subtitle, color, x in HUB_GATES_NORTH:
        for dx in (-gw / 2 - 1, gw / 2 + 1):
            b.box("Decor", "GatePillar", (2, gh + 2, 2), (x + dx, (gh + 2) / 2, gate_z), (28, 31, 37), "Metal")
            b.box("Decor", "GateStrip", (0.5, gh, 0.4), (x + dx, gh / 2 + 1, gate_z - 1.2), color, "Neon")
        b.box("Decor", "GateHeader", (gw + 4, 2, 2), (x, gh + 2, gate_z), (28, 31, 37), "Metal")
        b.box("Decor", "GateGlow", (gw, gh, 0.3), (x, gh / 2, gate_z + 0.2), color, "ForceField",
              props={"Transparency": 0.25, "CanCollide": False},
              children=[{"Name": "Light", "ClassName": "PointLight",
                         "Properties": {"Range": 16, "Brightness": 0.8, "Color": rgb(*color)}}])
        b.sign2("Sign_" + mode_id, (17.5, 6, 0.4), (x, gh + 5.2, gate_z - 1.6), title, subtitle, graphite, color,
                (236, 239, 243), angles=(-12, 0, 0), glow=color)
        client_board("GateCount_" + mode_id, (10, 1.8, 0.3), (x, gh + 1.4, gate_z - 1.15))
        # Modus-Name gerade vor dem Portal auf der Fläche (lesbar vom Spawn aus)
        b.floor_text("FloorLabel_" + mode_id, (13, 0.1, 3.6), (x, 0.3, gate_z - 11.5), title, color)
        b.add("Portals", "Portal_" + mode_id, (gw - 1, 0.3, 7), (x, 0.4, gate_z - 4), color, "Neon",
              props={"CanCollide": False, "Transparency": 0.45})
    b.sign2("DuelsBanner", (36, 2.4, 0.4), (30, H - 1.4, z1 - 0.5), "DUELS", "WINGMAN 2v2  ·  1v1 ARENA",
            graphite, (205, 90, 80), (236, 239, 243), glow=(205, 90, 80))
    b.sign2("ModesBanner", (56, 2.4, 0.4), (-20, H - 1.4, z1 - 0.5), "EINSÄTZE", "LAUF DURCH EIN TOR",
            graphite, accent, (236, 239, 243), glow=accent)

    # ---------- Westen: Shop-Vitrine (Angebote des Tages setzt der Client, E an der Theke öffnet den Shop) ----------
    vx = x0 + 6
    for k, vz in enumerate((-11, 0, 11), start=1):
        b.box("Decor", "VitrineBase", (5, 2.5, 5), (vx, 1.25, vz), (32, 35, 41), "Metal")
        b.box("Decor", "VitrineBaseStrip", (5.1, 0.25, 5.1), (vx, 2.4, vz), accent, "Neon", props={"Transparency": 0.2})
        b.box("Decor", "VitrineGlass", (4.6, 5, 4.6), (vx, 5, vz), (200, 225, 240), "Glass",
              props={"Transparency": 0.8, "CanCollide": True})
        b.box("Decor", "VitrineCap", (5, 0.4, 5), (vx, 7.7, vz), (32, 35, 41), "Metal")
        b.box("Decor", "VitrineLight", (3, 0.1, 3), (vx, 7.45, vz), (255, 248, 235), "Neon",
              children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                  "Face": "Bottom", "Range": 10, "Brightness": 1.1, "Angle": 70, "Color": rgb(255, 245, 230)}}])
        b.add("Decor", "ShopDisplay" + str(k), (1, 1, 1), (vx, 4.6, vz), accent, "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
        client_board("ShopPlaque" + str(k), (4.4, 1.6, 0.2), (vx + 2.7, 1.3, vz), angles=(0, -90, 0))
    # Theke mit E-Aufforderung (Client legt den Prompt an)
    cxs = x0 + 15
    b.box("Decor", "ShopCounter", (2.6, 3.4, 12), (cxs, 1.7, 0), (36, 39, 46), "Metal")
    b.box("Decor", "ShopCounterTop", (3, 0.25, 12.4), (cxs, 3.5, 0), (24, 27, 32), "SmoothPlastic")
    b.box("Decor", "ShopCounterStrip", (0.15, 0.25, 12.2), (cxs + 1.35, 2.8, 0), accent, "Neon", props={"Transparency": 0.2})
    b.box("Decor", "ShopTerminal", (0.3, 1.6, 2.4), (cxs, 4.4, 0), graphite, "SmoothPlastic", angles=(0, -90, 15))
    b.sign2("ShopSign", (22, 5.5, 0.5), (x0 + 0.6, 13, 0), "SHOP", "ANGEBOTE DES TAGES  ·  AN DER THEKE E DRÜCKEN",
            graphite, (212, 170, 80), (236, 239, 243), angles=(0, -90, 0), glow=(212, 170, 80))
    carpet("CarpetShop", (-(ring_r - 3), tz), (cxs + 1.3, tz), 8)

    # ---------- Osten (Mitte): Holo-Station mit den Bestenlisten, Teppich vom Ring dorthin ----------
    holo = (90, 175, 225)
    # gerade Bahn vom Ring und eine rechteckige Fläche vor der Reihe der Tafeln
    carpet("CarpetBoards", (ring_r - 3, tz), (32, tz), 8)
    carpet("CarpetHolo", (36, tz - 22), (36, tz + 22), 10)
    # vier schwebende Holo-Tafeln in einer Reihe, zur Hallenmitte (Westen) gerichtet
    for board, color, pz in (("Elo", (200, 166, 92), tz - 16.5), ("Kills", (206, 70, 58), tz - 5.5),
                             ("Level", (96, 164, 214), tz + 5.5), ("Wins", (112, 178, 112), tz + 16.5)):
        px, yaw = 44, 90
        b.add("Decor", "Leaderboard_" + board, (10, 8.5, 0.15), (px, 8.6, pz), holo, "Glass", angles=(0, yaw, 0),
              props={"Transparency": 0.82, "CanCollide": False, "CanQuery": False,
                     "Attributes": {"Attributes": {"Holo": {"Bool": True}}}})
        b.box("Decor", "HoloFrameTop", (10.2, 0.12, 0.12), (px, 12.9, pz), color, "Neon", angles=(0, yaw, 0),
              props={"Transparency": 0.2})
        b.box("Decor", "HoloFrameBottom", (10.2, 0.12, 0.12), (px, 4.3, pz), holo, "Neon", angles=(0, yaw, 0),
              props={"Transparency": 0.3})
        # Projektor am Boden mit Lichtkegel
        b.box("Decor", "HoloProjector", (3, 0.8, 1.6), (px, 0.65, pz), (34, 37, 43), "Metal", angles=(0, yaw, 0))
        b.box("Decor", "HoloLens", (2.4, 0.1, 1), (px, 1.1, pz), holo, "Neon", angles=(0, yaw, 0))
        b.box("Decor", "HoloBeam", (9.6, 3.2, 0.1), (px, 2.7, pz), holo, "Neon", angles=(0, yaw, 0),
              props={"Transparency": 0.88, "CanCollide": False, "CanQuery": False})
    b.sign2("BoardsTitle", (30, 4, 0.4), (x1 - 0.6, 19, tz), "BESTENLISTEN", "GLOBALE TOP 10",
            graphite, holo, (236, 239, 243), angles=(0, 90, 0), glow=holo)

    # ---------- Ecke hinten links: längliches Siegertreppchen, schräg zur Hallenmitte ----------
    gold = (200, 166, 92)
    cx, cz = -40, -26
    fx, fz = -cx, tz + 4 - cz
    flen = math.hypot(fx, fz)
    fx, fz = fx / flen, fz / flen          # Blickrichtung der Statuen (zur Hallenmitte)
    rx, rz = -fz, fx                       # entlang des Podests
    long_yaw = math.degrees(math.atan2(rx, rz))
    face_yaw = math.degrees(math.atan2(-fx, -fz))
    # Rückwand schräg in der Ecke, oben eine goldene Leiste, Titel darüber
    wx, wz = cx - fx * 6.5, cz - fz * 6.5
    b.box("Walls", "PodiumWall", (0.8, 12, 24), (wx, 6, wz), steel, "Metal", angles=(0, long_yaw, 0))
    b.box("Decor", "PodiumWallStrip", (0.2, 0.3, 24), (wx + fx * 0.5, 11.5, wz + fz * 0.5), gold, "Neon",
          angles=(0, long_yaw, 0), props={"Transparency": 0.2})
    b.sign2("PodiumTitle", (18, 3.6, 0.4), (wx + fx * 0.6, 14.2, wz + fz * 0.6), "TOP 3 · ELO",
            "DIE BESTEN SPIELER DER SAISON", graphite, gold, (236, 239, 243), angles=(0, face_yaw, 0), glow=gold)
    # schmaler Sockel, darauf die drei Podeste (kleiner als vorher)
    b.box("Decor", "PodiumPlinth", (7, 0.5, 21), (cx, 0.25, cz), (32, 35, 41), "Metal", angles=(0, long_yaw, 0))
    for place, off, h, color in ((1, 0, 3.2, gold), (2, 6.8, 2.3, (190, 194, 200)), (3, -6.8, 1.5, (180, 120, 70))):
        px, pz = cx + rx * off, cz + rz * off
        b.box("Decor", "PodiumBase", (5.6, h, 5.6), (px, 0.5 + h / 2, pz), (32, 35, 41), "Metal", angles=(0, long_yaw, 0))
        b.box("Decor", "PodiumTop", (5.8, 0.35, 5.8), (px, 0.68 + h, pz), color, "Metal", angles=(0, long_yaw, 0))
        b.add("Podium", "Podium" + str(place), (2, 0.2, 2), (px, 0.95 + h, pz), color, "SmoothPlastic", angles=(0, face_yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
        b.sign("PodiumNumber", (1.6, 1.3, 0.3), (px + fx * 2.95, 0.5 + h / 2, pz + fz * 2.95), str(place), (32, 35, 41), color,
               angles=(0, face_yaw, 0))

    # ---------- Süden (Rückwand): Einsatz-Bildschirm, Logo, Plakate ----------
    if not b.holo:
        b.box("Decor", "MissionBoardFrame", (25, 12, 0.4), (0, 14, z0 + 0.2), steel, "Metal")
    client_board("MissionBoard", (24, 11, 0.5), (0, 14, z0 + 0.8), angles=(0, 180, 0))
    if b.holo:
        b.holo_edges("MissionBoard", (24, 11, 0.5), (0, 14, z0 + 0.8), (0, 180, 0), accent)
    b.sign2("BackLogo", (30, 4.5, 0.4), (0, 22.5, z0 + 0.5), "SHOOTOUT", "TACTICAL OPERATIONS",
            graphite, accent, (236, 239, 243), angles=(0, 180, 0), glow=accent)
    for x, title, sub, color in ((-27, "WERDE AGENT", "9 AGENTEN · EIGENE FÄHIGKEITEN", (150, 120, 210)),
                                 (27, "WAFFEN-AUFSÄTZE", "JETZT IM LOADOUT", (112, 178, 112))):
        if not b.holo:
            b.box("Decor", "PosterFrame", (15, 10, 0.3), (x, 15, z0 + 0.2), steel, "Metal")
        b.sign2("Poster", (14, 9, 0.4), (x, 15, z0 + 0.45), title, sub, graphite, color, (236, 239, 243),
                angles=(0, 180, 0), glow=color)
    for x in (-45, -38, 38, 45):
        b.box("Walls", "WallRib", (1.2, H - 9, 0.8), (x, (H - 9) / 2 + 8, z0 + 0.4), steel, "Metal")
    b.box("Decor", "WallBand", (x1 - x0 - 4, 0.25, 0.15), (0, 7.8, z0 + 0.45), accent, "Neon", props={"Transparency": 0.6})
    for x in range(-48, 49, 5):
        if abs(x) > 12 and x > -26:  # linke Ecke bleibt frei fürs Siegertreppchen
            b.box("Decor", "Locker", (4.4, 7.5, 2.2), (x, 3.75, z0 + 1.2), (48, 58, 70), "Metal")
            b.box("Decor", "LockerVent", (3.6, 0.3, 0.1), (x, 6, z0 + 2.35), (26, 28, 32), "Metal")
    for x, z, size in ((-50, 41, 4), (-46, 41, 3), (50, -33, 4), (46, -33, 3)):
        b.crate(x, z, s=size, color=(90, 80, 62))

    b.save("Hub.model.json")

if __name__ == "__main__":
    build_ffa()
    build_drop()
    # Herrschaft spielt auf "Tal" (Drop.model.json). Wingman-Rotation: Fabrik, Hochhaus, Gletscher,
    # Zellenblock, Kanäle, Windmühlen. Ausgebaute Modi (Strikeout, Demolition, Ranked, Extraction, TDM)
    # brauchen ihre Kopien nicht mehr: build_demolition(), build_strikeout() usw. bleiben zum Wiedereinbauen.
    build_strikeout(WINGMAN_ORIGIN, "Wingman.model.json")
    build_training()
    build_arena()
    build_glacier()
    build_cellblock()
    build_canals((-3000, 0, 1500), "Kanaele.model.json")
    build_windmills((4500, 0, 0), "Windmuehlen.model.json")
    build_hightower((-4500, 0, 0), "Hochhaus.model.json")
    build_lobby()

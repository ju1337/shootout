"""Erzeugt die Maps als Rojo-Modelle (src/maps/*.model.json).

Aufruf:  python3 tools/build_maps.py
Alle Maps liegen im selben Place (Workspace.Maps.Extinction / Market), jeweils
an einer eigenen Stelle der Welt. Die Verschiebungen müssen zu "Center" in
src/shared/Modes.lua passen.
"""

import json
import math
import os
import random

import streaming

# Anzeigenamen der Maps
MAP_NAMES = {"Market": "Markt"}

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "maps")

# Mitte jeder Map in der Welt (wie Center in Modes.lua); die offene Welt steht unten (EXTINCTION_ORIGIN)
MARKET_ORIGIN = (-1500, 0, -1500)


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


def yaw_tilt(yaw, tilt):
    """Winkel für rot()/angles, die ein Teil erst um seine eigene x-Achse neigen (tilt) und dann um die
    Hochachse drehen (yaw): R = Ry(yaw) * Rx(tilt). Zerlegt in R = Rx * Ry * Rz (wie CFrame.Angles)."""
    ry, rx = rot(0, yaw, 0), rot(tilt, 0, 0)
    m = [[sum(ry[i][k] * rx[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    b = math.asin(max(-1.0, min(1.0, m[0][2])))
    a = math.atan2(-m[1][2], m[2][2])
    c = math.atan2(-m[0][1], m[0][0])
    return (math.degrees(a), math.degrees(b), math.degrees(c))


def rgb(r, g, b):
    return [round(r / 255, 4), round(g / 255, 4), round(b / 255, 4)]


HOLO_TINT = (100, 180, 230)  # Glas-Tönung der Holo-Schilder


def lighten(color, amount=0.35):
    """Heller (amount > 0) bzw. dunkler (amount < 0) machen."""
    if amount < 0:
        return tuple(int(c * (1 + amount)) for c in color)
    return tuple(int(c + (255 - c) * amount) for c in color)


def scale_xz(pos, m, size, f):
    """Teil in der Fläche um f strecken (Höhe bleibt): Mitte, Ausrichtung und Größe. Für gedrehte/geneigte Teile wird
    die längste Achse exakt abgebildet und der Rest orthogonal ergänzt (bei Rampen ändert sich nur die Neigung)."""
    cols = [[m[i][k] for i in range(3)] for k in range(3)]  # lokale Achsen in Weltkoordinaten
    vecs = [[c[0] * f, c[1], c[2] * f] for c in cols]
    lens = [math.sqrt(sum(v * v for v in vec)) for vec in vecs]
    new_size = [size[k] * lens[k] for k in range(3)]
    order = sorted(range(3), key=lambda k: -new_size[k])
    u = [None, None, None]
    p = order[0]
    u[p] = [v / lens[p] for v in vecs[p]]
    q = order[1]
    d = sum(vecs[q][i] * u[p][i] for i in range(3))
    w = [vecs[q][i] - d * u[p][i] for i in range(3)]
    n = math.sqrt(sum(v * v for v in w)) or 1
    u[q] = [v / n for v in w]
    r = order[2]
    a, b = u[(r + 1) % 3], u[(r + 2) % 3]
    u[r] = [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
    new_m = [[round(u[k][i], 6) for k in range(3)] for i in range(3)]
    return (pos[0] * f, pos[1], pos[2] * f), new_m, new_size


class Builder:
    def __init__(self, origin=(0, 0, 0), scale=1.0):
        self.groups = {}
        self.origin = origin
        self.scale = scale  # > 1: ganze Map in der Fläche strecken (Abstände, Wände, Plätze), Höhen bleiben
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
        orientation = rot(*angles)
        if self.scale != 1:
            keep = size  # Flaggen-Zonen behalten ihre Größe (Radius steht im Spielcode)
            pos, orientation, size = scale_xz(pos, orientation, size, self.scale)
            if group == "Objective":
                size = keep
        p = {
            "Anchored": True,
            "Size": [round(v, 3) for v in size],
            "CFrame": {"CFrame": {"position": [round(v + o, 3) for v, o in zip(pos, self.origin)],
                                  "orientation": orientation}},
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
        """real=True: echte SpawnLocation. Sonst unsichtbarer Spawnpunkt für die Modus-Logik."""
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
                  stairs_at=("W",), h1=10, h2=9, material="Concrete", doors2=None):
        """Zweistöckiges Gebäude. doors/windows: {Seite: [Versatz, ...]} (Versatz entlang der Wand, 0 = Mitte).
        Unten Türen (6 breit) und Fenster, oben viele Fenster zum Spähen. Treppe innen an den Seiten stairs_at.
        doors2: Türen im Obergeschoss (z.B. auf einen Steg oder Balkon)."""
        doors = doors or {}
        windows1 = windows1 or {}
        windows2 = windows2 or {}
        doors2 = doors2 or {}
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
            ops2 += [(base + o, 5, 0.5, 7) for o in doors2.get(side, [])]
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

    # ---------- Bausteine für die neuen Maps (Kraftwerk, Altstadt) ----------

    def cylinder(self, group, name, diameter, height, pos, color, material="Metal", y0=None, props=None):
        """Stehender Zylinder (Roblox-Zylinder liegen entlang X, darum um 90° gekippt). pos = (x, Mitte y, z)."""
        p = {"Shape": "Cylinder"}
        if props:
            p.update(props)
        self.add(group, name, (height, diameter, diameter), pos, color, material, angles=(0, 0, 90), props=p)

    def catwalk(self, name, x0, x1, z0, z1, y, rails=(), color=(70, 74, 80), rail_color=(210, 170, 50)):
        """Gitter-Laufsteg (Oberkante y) mit Geländern an den Seiten rails (N/S/E/W)."""
        self.box("Buildings", name, (x1 - x0, 0.6, z1 - z0), ((x0 + x1) / 2, y - 0.3, (z0 + z1) / 2), color, "DiamondPlate")
        for side in rails:
            if side in ("N", "S"):
                zz = z1 - 0.15 if side == "N" else z0 + 0.15
                self.box("Buildings", name + "Rail", (x1 - x0, 1.1, 0.3), ((x0 + x1) / 2, y + 1.1, zz), rail_color, "Metal")
                self.box("Buildings", name + "RailLow", (x1 - x0, 0.2, 0.2), ((x0 + x1) / 2, y + 0.55, zz), rail_color, "Metal")
            else:
                xx = x1 - 0.15 if side == "E" else x0 + 0.15
                self.box("Buildings", name + "Rail", (0.3, 1.1, z1 - z0), (xx, y + 1.1, (z0 + z1) / 2), rail_color, "Metal")
                self.box("Buildings", name + "RailLow", (0.2, 0.2, z1 - z0), (xx, y + 0.55, (z0 + z1) / 2), rail_color, "Metal")

    def pillar(self, x, z, h, s=1.4, color=(80, 84, 90), material="Metal", group="Buildings"):
        self.box(group, "Pillar", (s, h, s), (x, h / 2, z), color, material)

    def stall(self, x, z, along_x=True, canopy=(180, 60, 50)):
        """Marktstand: Theke (brusthoch, Deckung), vier Pfosten und farbiges Dach."""
        w, d = (7, 3) if along_x else (3, 7)
        self.box("Cover", "StallCounter", (w, 3.2, d), (x, 1.6, z), (120, 92, 64), "WoodPlanks")
        for dx in (-1, 1):
            for dz in (-1, 1):
                px = x + dx * (w / 2 - 0.3) if along_x else x + dx * (d / 2 + 0.6)
                pz = z + dz * (d / 2 + 0.6) if along_x else z + dz * (w / 2 - 0.3)
                self.box("Decor", "StallPost", (0.3, 6.6, 0.3), (px, 3.3, pz), (70, 60, 50), "Wood")
        cw, cd = (w + 1, d + 2.4) if along_x else (d + 2.4, w + 1)
        self.box("Decor", "StallRoof", (cw, 0.3, cd), (x, 6.7, z), canopy, "Fabric")

    def barrier(self, x, z, along_x=True, length=6):
        """Beton-Leitwand (brusthoch, Fahrbahn-Absperrung)."""
        size = (length, 3.2, 1.6) if along_x else (1.6, 3.2, length)
        self.box("Cover", "Barrier", size, (x, 1.6, z), (165, 162, 155), "Concrete")
        stripe = (length, 0.5, 1.7) if along_x else (1.7, 0.5, length)
        self.box("Cover", "BarrierStripe", stripe, (x, 2.6, z), (220, 170, 40), "SmoothPlastic")

    def flat_house(self, name, x, z, w, d, h, color, doors=None, windows=None, y0=0, parapet=("N", "S", "E", "W"),
                   roof_color=None, trim=None, gaps=None):
        """Einfaches Haus mit flachem, begehbarem Dach (Oberkante y0 + h + 1) und Brüstung.
        doors/windows: {Seite: [Versatz]} wie bei building2. gaps: {Seite: [Versatz]} Lücken in der Brüstung
        (dort kommen Stege oder Treppen an). Gibt die Dachhöhe zurück."""
        doors, windows, gaps = doors or {}, windows or {}, gaps or {}
        x0, x1, z0, z1 = x - w / 2, x + w / 2, z - d / 2, z + d / 2
        t = 1
        walls = {"N": (x0, x1, z1 - t / 2, True), "S": (x0, x1, z0 + t / 2, True),
                 "E": (z0 + t, z1 - t, x1 - t / 2, False), "W": (z0 + t, z1 - t, x0 + t / 2, False)}
        for side, (a, b, fixed, along_x) in walls.items():
            base = x if along_x else z
            ops = [(base + o, 5, 0, 7) for o in doors.get(side, [])]
            ops += [(base + o, 3.4, 3, 5.6) for o in windows.get(side, [])]
            self.wall_line(name, a, b, fixed, along_x, h, color, "Concrete", ops, y0=y0, t=t)
        top = y0 + h + 1
        self.box("Buildings", name + "_Roof", (w, 1, d), (x, top - 0.5, z), roof_color or lighten(color, -0.25), "Concrete")
        if trim:
            # farbiges Band außen um die Fassade (vier schmale Leisten, innen bleibt frei)
            ty = y0 + h - 0.6
            self.box("Decor", name + "_Trim", (w + 0.4, 0.5, 0.2), (x, ty, z1 + 0.1), trim, "SmoothPlastic")
            self.box("Decor", name + "_Trim", (w + 0.4, 0.5, 0.2), (x, ty, z0 - 0.1), trim, "SmoothPlastic")
            self.box("Decor", name + "_Trim", (0.2, 0.5, d), (x1 + 0.1, ty, z), trim, "SmoothPlastic")
            self.box("Decor", name + "_Trim", (0.2, 0.5, d), (x0 - 0.1, ty, z), trim, "SmoothPlastic")
        for side in parapet:
            a, b, fixed, along_x = {"N": (x0, x1, z1 - 0.3, True), "S": (x0, x1, z0 + 0.3, True),
                                    "E": (z0, z1, x1 - 0.3, False), "W": (z0, z1, x0 + 0.3, False)}[side]
            base = x if along_x else z
            ops = [(base + o, 4, 0, 1.4) for o in gaps.get(side, [])]
            self.wall_line(name + "_Parapet", a, b, fixed, along_x, 1.4, lighten(color, 0.15), "Concrete", ops, y0=top,
                           t=0.6, group="Cover")
        return top

    def plank(self, name, a, b, width=3, color=(130, 96, 64)):
        """Gerader Steg von Punkt a = (x, y, z) nach b (auch schräg, z.B. zwischen zwei Dächern)."""
        dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        flat = math.hypot(dx, dz)
        length = math.hypot(flat, dy)
        yaw = math.degrees(math.atan2(-dz, dx))
        pitch = math.degrees(math.atan2(dy, flat))
        center = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 - 0.3, (a[2] + b[2]) / 2)
        self.box("Buildings", name, (length, 0.6, width), center, color, "WoodPlanks", angles=(0, yaw, pitch))

    def palm(self, x, z, h=14, lean=6, rng=None):
        """Palme: geneigter Stamm und ein Kranz aus Blättern."""
        rng = rng or random.Random(int(x * 7 + z * 13))
        ang = rng.uniform(0, 360)
        lx, lz = math.cos(math.radians(ang)) * lean, math.sin(math.radians(ang)) * lean
        self.plank("PalmTrunk", (x, 0, z), (x + lx, h, z + lz), width=1.2, color=(120, 92, 60))
        for k in range(6):
            a = math.radians(k * 60 + ang)
            self.box("Nature", "PalmLeaf", (7, 0.3, 2.2), (x + lx + math.cos(a) * 3.2, h - 0.6, z + lz + math.sin(a) * 3.2),
                     (60, 150, 60), "Grass", angles=(0, -math.degrees(a), -14))

    def crater(self, name, x, z, r, color=(96, 96, 102), height=2.2, segments=14):
        """Krater: Ring aus Wällen (brusthoch) mit dunklerem Boden in der Mitte."""
        self.add("Ground", name + "Floor", (0.2, r * 2, r * 2), (x, 0.08, z), lighten(color, -0.25), "Slate",
                 angles=(0, 0, 90), props={"Shape": "Cylinder"})
        seg = 2 * math.pi * r / segments + 1
        for k in range(segments):
            a = 2 * math.pi * k / segments
            self.box("Cover", name + "Rim", (seg, height, 3), (x + math.cos(a) * r, height / 2, z + math.sin(a) * r),
                     color, "Slate", angles=(0, -math.degrees(a) + 90, 0))

    def solar_panel(self, x, z, along_x=True, length=12):
        """Schräges Solarpaneel auf Stützen (Deckung zum Ducken, man kann drunter durchschauen)."""
        size = (length, 0.3, 4) if along_x else (4, 0.3, length)
        angles = (25, 0, 0) if along_x else (0, 0, 25)
        self.box("Cover", "SolarPanel", size, (x, 3, z), (30, 40, 80), "Glass", angles=angles)
        for d in (-1, 1):
            px, pz = (x + d * (length / 2 - 1), z) if along_x else (x, z + d * (length / 2 - 1))
            self.box("Decor", "SolarPost", (0.4, 3, 0.4), (px, 1.5, pz), (150, 150, 155), "Metal")

    def half_wall(self, x, z, length, along_x=True, color=(150, 150, 150)):
        """Brusthohe Deckung (man kann darüber schießen)."""
        self.cover_wall(x, z, length, along_x=along_x, height=3.4, color=color)

    def sign2(self, name, size, pos, title, subtitle, bg, fg, sub_fg, angles=(0, 0, 0), glow=None):
        """Schild mit großer Überschrift und kleiner Unterzeile (z.B. Tore und Tafeln des Camps)."""
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

    def save(self, filename, display_name=None, atmosphere=None):
        """atmosphere: Lichtstimmung auf dem Client (MapAtmosphere: "Space", "Tropical"), sonst normales Licht."""
        attrs = {
            "DisplayName": {"String": display_name or MAP_NAMES.get(filename.replace(".model.json", ""),
                                                                    filename.replace(".model.json", ""))},
            "Center": {"Vector3": [float(v) for v in self.origin]},
        }
        if atmosphere:
            attrs["Atmosphere"] = {"String": atmosphere}
        model = {
            "ClassName": "Model",
            "Properties": {"Attributes": {"Attributes": attrs}},
            "Children": [{"Name": g, "ClassName": "Folder", "Children": c} for g, c in self.groups.items()],
        }
        streaming.apply(model, filename.replace(".model.json", ""))  # was der Client immer braucht (Streaming)
        os.makedirs(OUT_DIR, exist_ok=True)
        with open(os.path.join(OUT_DIR, filename), "w") as f:
            json.dump(model, f, indent=1)
        print(filename, sum(len(c) for c in self.groups.values()), "Parts")


# ---------- Markt: Handelshalle mit 12 Ständen (MarketService / MarketClient) ----------
MARKET_CANOPIES = ((186, 72, 60), (64, 120, 186), (72, 150, 96), (206, 158, 64), (132, 84, 170), (206, 112, 54))


def build_market():
    """Markt als Theater-Rund (Radius 94, ohne Dach): In der Mitte der Marktplatz (Spawns, Such-Terminal,
    Tafeln, Tor zurück ins Camp). Darum drei breite Ränge, die nach außen stufenweise höher werden
    (2,4 / 5,4 / 8,4 m); auf jedem Rang stehen die Stände mit der Vorderseite zur Mitte (12 + 16 + 20 = 48). Das Tor
    zurück ins Camp steht am Ende der Südrampe (oberster Rang), damit der Platz frei bleibt. Vier
    Rampen (Himmelsrichtungen) führen vom Platz über alle Ränge nach oben, die Stufen dazwischen kann man auch
    springen. Ein Stand ist ein Ordner "Stand_<n>" mit Theke, Regal, Vordach, Schild ("Sign", beschreibt der Client),
    sechs Ausstellplätzen ("Display1".."Display6": Mitte des Skins, LookVector zum Gang) und dem Prompt-Punkt vor der
    Theke ("Prompt"). Besitzer, Name und Angebote setzt der Server als Attribute an den Ordner. Der Client beschreibt
    außerdem "OverviewBoard" und "TopBoard" und hängt an "SearchTerminal" ein E-Prompt. Winkel phi: 0 = +x, 90 = +z (Norden)."""
    b = Builder(MARKET_ORIGIN)
    b.holo = True
    floor, steel, graphite = (96, 78, 60), (78, 72, 68), (22, 25, 30)
    wood, wood_dark, top = (128, 92, 62), (94, 68, 48), (62, 54, 48)
    warm, rap = (255, 198, 128), (86, 214, 170)
    stone, plaza = (150, 142, 132), (58, 54, 56)
    R0, R_WALL = 32, 94
    tiers = ((36, 54, 2.4, 3), (54, 72, 5.4, 4), (72, 90, 8.4, 5))  # (innen, außen, Höhe, Stände je Viertel)
    ramp_w = 10

    def polar(r, phi_deg):
        a = math.radians(phi_deg)
        return r * math.cos(a), r * math.sin(a)

    def frame(cx, cz, y0, yaw):
        """Ortsrahmen: Punkt (lx, ly, lz) im Rahmen -> Welt. Drehung um die Hochachse wie CFrame.Angles(0, yaw, 0)."""
        c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        return lambda lx, ly, lz: (cx + lx * c + lz * sn, y0 + ly, cz - lx * sn + lz * c)

    b.ground(250, 250, (44, 42, 40), "Asphalt")
    b.border(240, 240, 2, (60, 60, 65), "Metal", barrier=80)

    # ---------- Ringe (Platz, Ränge, Außenmauer) aus Segmenten ----------
    def ring(group, name, r_in, r_out, y0, height, color, material, n=72, **kw):
        step = 360.0 / n
        rm = (r_in + r_out) / 2
        length = 2 * r_out * math.tan(math.radians(step / 2)) + 0.4
        for k in range(n):
            phi = (k + 0.5) * step
            x, z = polar(rm, phi)
            b.box(group, name, (r_out - r_in, height, length), (x, y0 + height / 2, z), color, material, angles=(0, -phi, 0), **kw)

    b.cylinder("Ground", "PlazaRim", 2 * R0 + 1.6, 0.18, (0, 0.09, 0), rap, "Neon", props={"Transparency": 0.5})
    b.cylinder("Ground", "PlazaFloor", 2 * R0, 0.24, (0, 0.12, 0), plaza, "Slate")
    b.cylinder("Ground", "PlazaInlay", 44, 0.06, (0, 0.27, 0), rap, "Neon", props={"Transparency": 0.78})
    b.cylinder("Ground", "PlazaInlayCore", 41, 0.07, (0, 0.28, 0), (46, 42, 44), "Slate")
    for i, (r_in, r_out, h, _) in enumerate(tiers):
        ring("Ground", "Tier%d" % (i + 1), r_in, r_out, 0, h, floor, "WoodPlanks")
        ring("Decor", "TierEdge%d" % (i + 1), r_in - 0.05, r_in + 0.35, h - 0.05, 0.12, rap, "Neon", n=48,
             props={"Transparency": 0.35})
    ring("Walls", "OuterWall", R_WALL - 3, R_WALL, 0, 16, (70, 60, 52), "Brick")
    ring("Walls", "OuterWallCap", R_WALL - 3.4, R_WALL + 0.4, 16, 0.8, steel, "Metal", n=48)

    # ---------- Wege: vier Rampen über alle Ränge ----------
    def slope(name, phi, r0, y0, r1, y1, color=(150, 138, 118), material="Concrete"):
        """Schräge Fläche in Richtung phi von (r0, y0) nach (r1, y1), Oberkante läuft genau durch beide Punkte."""
        length = math.hypot(r1 - r0, y1 - y0)
        tilt = math.degrees(math.atan2(y1 - y0, r1 - r0))
        x, z = polar((r0 + r1) / 2, phi)
        b.box("Ground", name, (length, 0.6, ramp_w), (x, (y0 + y1) / 2 - 0.3 * math.cos(math.radians(tilt)), z), color, material,
              angles=(0, -phi, tilt))

    def flat_path(name, phi, r0, r1, y):
        x, z = polar((r0 + r1) / 2, phi)
        b.box("Ground", name, (r1 - r0, 0.12, ramp_w), (x, y + 0.04, z), (150, 138, 118), "Concrete", angles=(0, -phi, 0))

    for phi in (0, 90, 180, 270):
        slope("RampPlaza", phi, R0 - 0.5, 0.24, 36, 2.4)
        flat_path("PathTier1", phi, 36, 47, 2.4)
        slope("RampTier1", phi, 47, 2.4, 54, 5.4)
        flat_path("PathTier2", phi, 54, 65, 5.4)
        slope("RampTier2", phi, 65, 5.4, 72, 8.4)
        flat_path("PathTier3", phi, 72, 90, 8.4)
        # leuchtende Randstreifen an den Rampen
        for side in (-1, 1):
            for r0, y0, r1, y1 in ((36, 2.4, 47, 2.4), (47, 2.4, 54, 5.4), (54, 5.4, 65, 5.4), (65, 5.4, 72, 8.4), (72, 8.4, 90, 8.4)):
                length = math.hypot(r1 - r0, y1 - y0)
                tilt = math.degrees(math.atan2(y1 - y0, r1 - r0))
                a = math.radians(phi)
                mx, mz = polar((r0 + r1) / 2, phi)
                ox, oz = -math.sin(a) * side * (ramp_w / 2 - 0.2), math.cos(a) * side * (ramp_w / 2 - 0.2)
                b.box("Decor", "PathStrip", (length, 0.1, 0.3), (mx + ox, (y0 + y1) / 2 + 0.12, mz + oz), rap, "Neon",
                      angles=(0, -phi, tilt), props={"Transparency": 0.35})

    # ---------- Platz in der Mitte (bewusst leer und ruhig) ----------
    # Spawns im Kreis um das Such-Terminal
    for k in range(8):
        x, z = polar(12, k * 45 + 22.5)
        b.spawn(x, z, yaw=math.degrees(math.atan2(-math.cos(math.radians(k * 45 + 22.5)), -math.sin(math.radians(k * 45 + 22.5)))))  # Blick nach außen
    # Such-Terminal: niedrige Säule mit leuchtendem Bildschirm (E), keine Schilder
    b.cylinder("Decor", "KioskColumn", 3.4, 3.0, (0, 1.75, 0), (30, 32, 38), "Metal")
    b.cylinder("Decor", "KioskTrim", 3.8, 0.2, (0, 3.35, 0), rap, "Neon", props={"Transparency": 0.3})
    b.add("Decor", "SearchTerminal", (1.2, 2.8, 2.8), (0, 4.2, 0), rap, "Neon", props={"Transparency": 0.2, "Shape": "Cylinder"},
          angles=(0, 0, 90),
          children=[{"Name": "Light", "ClassName": "PointLight",
                     "Properties": {"Range": 20, "Brightness": 0.9, "Color": rgb(*rap)}}])

    # (Der Kisten-Automat stand hier bis 2026-10-16; er steht jetzt im Camp Phoenix, tools/camp_phoenix.py)

    # Tafeln am Platzrand: freie Stände (Viertel 2), beliebteste Händler (Viertel 3), Vorderseite zur Mitte
    for name, phi, width in (("OverviewBoard", 135, 16), ("TopBoard", 225, 14)):
        cx, cz = polar(29, phi)
        yaw = 90 - phi
        at = frame(cx, cz, 0.24, yaw)
        b.box("Decor", name, (width, 8, 0.5), at(0, 5.2, 0), graphite, "SmoothPlastic", angles=(0, yaw, 0))
        b.box("Decor", name + "Frame", (width + 0.6, 0.3, 0.6), at(0, 9.35, 0), rap, "Neon", angles=(0, yaw, 0), props={"Transparency": 0.2})
        b.box("Decor", name + "Foot", (width + 0.6, 0.3, 0.6), at(0, 1.05, 0), rap, "Neon", angles=(0, yaw, 0), props={"Transparency": 0.4})
        for dx in (-width / 2 + 1, width / 2 - 1):
            b.box("Decor", name + "Post", (0.6, 5.2, 0.6), at(dx, 2.6, 0.8), (40, 38, 38), "Metal", angles=(0, yaw, 0))

    # Tor zurück ins Camp: am Ende der Südrampe auf dem obersten Rang, damit der Spawn frei bleibt
    gx, gz = polar(R_WALL - 4, 270)
    gyaw = 90 - 270
    gate = frame(gx, gz, 8.4, gyaw)
    gw, gh = 10, 9
    for dx in (-gw / 2 - 1, gw / 2 + 1):
        b.box("Decor", "GatePillar", (2, gh + 2, 2), gate(dx, (gh + 2) / 2, 0), (28, 31, 37), "Metal", angles=(0, gyaw, 0))
        b.box("Decor", "GateStrip", (0.5, gh, 0.4), gate(dx, gh / 2 + 1, -1.2), (120, 185, 235), "Neon", angles=(0, gyaw, 0))
    b.box("Decor", "GateHeader", (gw + 4, 2, 2), gate(0, gh + 2, 0), (28, 31, 37), "Metal", angles=(0, gyaw, 0))
    b.box("Decor", "GateGlow", (gw, gh, 0.3), gate(0, gh / 2, 0.4), (120, 185, 235), "ForceField", angles=(0, gyaw, 0),
          props={"Transparency": 0.25, "CanCollide": False},
          children=[{"Name": "Light", "ClassName": "PointLight",
                     "Properties": {"Range": 16, "Brightness": 0.8, "Color": rgb(120, 185, 235)}}])
    b.sign2("ExitSign", (11, 3.2, 0.4), gate(0, gh + 3.8, -1.2), "ZUM CAMP", "ZURÜCK INS CAMP PHOENIX", graphite,
            (120, 185, 235), (236, 239, 243), angles=(0, gyaw, 0), glow=(120, 185, 235))
    b.add("Portals", "Portal_Extinction", (gw - 1, 0.3, 4), gate(0, 0.15, -2.6), (120, 185, 235), "Neon", angles=(0, gyaw, 0),
          props={"CanCollide": False, "Transparency": 0.45})

    # Bäume im Platz (Zierde) und Laternen am Rand
    for k in range(12):
        phi = 15 + k * 30
        if min(phi % 90, 90 - phi % 90) < 18 or abs(phi - 45) < 28 or abs(phi - 135) < 33 or abs(phi - 225) < 33:
            continue
        x, z = polar(29.5, phi)
        b.box("Decor", "Planter", (3.2, 1.2, 3.2), (x, 0.84, z), wood_dark, "WoodPlanks")
        b.add("Decor", "Bush", (3.4, 3.4, 3.4), (x, 2.7, z), (64, 112, 60), "Grass", props={"Shape": "Ball"})
    for i, (r_in, r_out, h, _) in enumerate(tiers):
        for k in range(12):
            phi = 15 + k * 30
            x, z = polar(r_in + 1.2, phi)
            b.box("Decor", "LampPost", (0.3, 6.5, 0.3), (x, h + 3.25, z), (20, 20, 22), "Metal")
            lamp = []
            if k % 2 == 0:
                lamp = [{"Name": "Light", "ClassName": "PointLight",
                         "Properties": {"Range": 30, "Brightness": 1.0, "Color": rgb(*warm)}}]
            b.add("Decor", "Lamp", (1.0, 1.0, 1.0), (x, h + 6.9, z), warm, "Neon", props={"Shape": "Ball"}, children=lamp)

    # Banner an der Außenmauer (über den vier Rampen)
    for phi in (0, 90, 180, 270):
        cx, cz = polar(R_WALL - 3.3, phi)
        at = frame(cx, cz, 0, 90 - phi)
        b.sign2("MarketBanner", (22, 4.6, 0.4), at(0, 12, 0), "MARKT", "STAND BEANSPRUCHEN  ·  SKINS ANBIETEN  ·  MIT RAP KAUFEN",
                graphite, rap, (236, 239, 243), angles=(0, 90 - phi, 0), glow=rap)

    # ---------- Stände: pro Rang und Viertel mehrere, Vorderseite zur Mitte ----------
    n = 0
    for r_in, r_out, h, per_quadrant in tiers:
        rc = r_in + 13
        gap = math.degrees(math.asin(12.2 / rc))
        usable = 90 - 2 * gap
        for quadrant in range(4):
            for k in range(per_quadrant):
                phi = quadrant * 90 + gap + (k + 0.5) * usable / per_quadrant
                n += 1
                cx, cz = polar(rc, phi)
                psi = 180 - phi  # Drehung des Stand-Rahmens: lokal +x (Vorderseite) zeigt zur Mitte
                at = frame(cx, cz, h, psi)
                g = "Stand_%d" % n
                canopy = MARKET_CANOPIES[(n - 1) % len(MARKET_CANOPIES)]
                light = lighten(canopy, 0.3)
                yaw = psi - 90  # für Teile, deren LookVector (-Z) zur Mitte zeigen soll
                b.box(g, "Base", (7.4, 0.4, 12.4), at(0, 0.2, 0), wood_dark, "WoodPlanks", angles=(0, psi, 0))
                b.box(g, "BackWall", (0.8, 7.6, 12.4), at(-3.3, 4.2, 0), wood, "WoodPlanks", angles=(0, psi, 0))
                b.box(g, "Shelf", (1.8, 0.35, 11.6), at(-2.5, 4.4, 0), wood_dark, "WoodPlanks", angles=(0, psi, 0))
                b.box(g, "Counter", (1.8, 3.0, 11.2), at(2.3, 1.9, 0), wood, "WoodPlanks", angles=(0, psi, 0))
                b.box(g, "CounterTop", (2.3, 0.25, 11.6), at(2.3, 3.52, 0), top, "Marble", angles=(0, psi, 0))
                b.box(g, "CounterStrip", (0.15, 0.25, 11.3), at(3.24, 2.9, 0), canopy, "Neon", angles=(0, psi, 0),
                      props={"Transparency": 0.2})
                for dz in (-5.9, 5.9):
                    b.box(g, "Post", (0.5, 8.8, 0.5), at(3.3, 4.6, dz), wood_dark, "Wood", angles=(0, psi, 0))
                # Vordach: fällt zur Mitte hin ab, vorn ein Volant in hellerer Farbe
                b.box(g, "Canopy", (8.2, 0.3, 13), at(0, 9.4, 0), canopy, "Fabric", angles=(0, psi, -10))
                b.box(g, "Valance", (0.2, 1.0, 13), at(4.05, 8.25, 0), light, "Fabric", angles=(0, psi, 0))
                # Schild über dem Vordach (beschreibt der Client: Name oder Besitzer, FREI, Nummer)
                b.holo_panel(g, "Sign", (11, 2.2, 0.2), at(3.9, 11.4, 0), angles=(0, yaw, 0))
                b.holo_edges("Sign", (11, 2.2, 0.2), at(3.9, 11.4, 0), (0, yaw, 0), lighten(canopy, 0.2))
                for dz in (-5.9, 5.9):
                    lantern = []
                    if n % 2 == 1:
                        lantern = [{"Name": "Light", "ClassName": "PointLight",
                                    "Properties": {"Range": 10, "Brightness": 0.7, "Color": rgb(*warm)}}]
                    b.add(g, "Lantern", (0.7, 0.7, 0.7), at(3.3, 7.6, dz), warm, "Neon", props={"Shape": "Ball"}, children=lantern)
                # Ausstellplätze: drei auf der Theke, drei im Regal dahinter (Mitte des Skins)
                for kk, (dx, y, dz) in enumerate(((2.3, 4.5, -3.7), (2.3, 4.5, 0), (2.3, 4.5, 3.7),
                                                  (-2.5, 5.6, -3.7), (-2.5, 5.6, 0), (-2.5, 5.6, 3.7)), start=1):
                    b.add(g, "Display%d" % kk, (1, 1, 1), at(dx, y, dz), canopy, "SmoothPlastic", angles=(0, yaw, 0),
                          props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
                b.add(g, "Prompt", (1, 1, 1), at(3.8, 2.6, 0), canopy, "SmoothPlastic", angles=(0, yaw, 0),
                      props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
                # Nummer am Boden vor dem Stand
                b.floor_text("StandNumber", (5, 0.1, 1.8), at(6.2, 0.3, 0), "STAND %d" % n, lighten(canopy, 0.25), yaw=psi + 90)

    b.save("Market.model.json")


# ---------- Extinction: offene Welt (3200 x 3200) ----------
# Gebaut in tools/extinction_world.py (verwüstete Stadt Ödstadt mit Safe Zone in der Mitte, Dörfer, Militärbasis, Hafen,
# Gefängnis, Flugplatz, Höfe, Seen; Terrain-Höhenfeld in tools/extinction_terrain.py). Mitte wie Center in Modes.lua.
EXTINCTION_ORIGIN = (0, 0, -6000)


def build_extinction():
    import sys
    import extinction_world
    return extinction_world.build(sys.modules[__name__])


if __name__ == "__main__":
    # Nur noch Markt und offene Welt. Die Arcade-Maps (Altstadt, Favela, Orbit, Kraftwerk, Lagune, Mondbasis, Fabrik,
    # Gletscher, Zellenblock, Kanäle, Windmühlen, Hochhaus, Arena, Schießstand) und ihre Bau-Funktionen wurden am
    # 2026-10-13 entfernt (Arcade ist aus); bei Bedarf aus der Git-Geschichte holen.
    build_market()
    build_extinction()

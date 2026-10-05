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
MAP_NAMES = {"TDM": "Kraftwerk", "Domination": "Kraftwerk", "FreeForAll": "Altstadt", "Favela": "Favela", "Orbit": "Orbit",
             "Lagune": "Lagune", "Mondbasis": "Mondbasis", "Drop": "Tal", "Strikeout": "Fabrik", "Wingman": "Fabrik", "Demolition": "Hafen",
             "Ranked": "Hafen", "Arena": "Arena", "Training": "Schießstand", "Hub": "Hangar", "Market": "Markt"}

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
TDM_ORIGIN = (3000, 0, -1500)
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

# Nordwand: ein großes Tor in die offene Welt (Hauptmodus). Die Minispiele (FFA, Herrschaft, Wingman, 1v1 Arena,
# Training) haben kein Tor mehr, sie stehen im Menü unter ARCADE. Alte Torreihe: HUB_GATES_NORTH_ARCADE.
HUB_MAIN_GATE = ("Extinction", "EXTINCTION", "OFFENE WELT  ·  SAFE ZONE  ·  ZOMBIES", (215, 85, 45))
HUB_GATES_NORTH_ARCADE = (
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
    floor, wall, steel, graphite = (40, 44, 51), (54, 58, 66), (70, 74, 82), (22, 25, 30)
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
                             "Properties": {"Range": 30, "Brightness": 0.95, "Color": rgb(220, 228, 240)}}])
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
    carpet("CarpetPlaza", (0, plaza_z), (0, gate_z - 1), 40)

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
    # Licht von oben auf die Statue (ohne sichtbare Lichtsäulen)
    b.add("Decor", "StatueLight", (0.2, 3, 3), (0, H - 1.6, tz), (255, 248, 230), "Neon", angles=(0, 0, 90),
          props={"Shape": "Cylinder", "Transparency": 0.3},
          children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
              "Face": "Bottom", "Range": 26, "Brightness": 1.6, "Angle": 35, "Color": rgb(255, 245, 230)}}])

    # ---------- Nordwand: das große Tor nach EXTINCTION (offene Welt), Schild leicht zum Spawn geneigt ----------
    mode_id, title, subtitle, color = HUB_MAIN_GATE
    gw, gh = 28, 17
    hazard = (226, 178, 52)
    for dx in (-gw / 2 - 1.5, gw / 2 + 1.5):
        b.box("Decor", "GatePillar", (3, gh + 2, 3), (dx, (gh + 2) / 2, gate_z), (28, 31, 37), "Metal")
        b.box("Decor", "GateStrip", (0.6, gh, 0.4), (dx, gh / 2 + 1, gate_z - 1.7), color, "Neon")
        # Warnstreifen unten an den Pfeilern
        for k in range(3):
            b.box("Decor", "GateHazard", (3.1, 0.7, 3.1), (dx, 0.9 + k * 1.6, gate_z), hazard if k % 2 == 0 else (30, 30, 30),
                  "SmoothPlastic")
    b.box("Decor", "GateHeader", (gw + 6, 2, 3), (0, gh + 2, gate_z), (28, 31, 37), "Metal")
    b.box("Decor", "GateGlow", (gw, gh, 0.3), (0, gh / 2, gate_z + 0.2), color, "ForceField",
          props={"Transparency": 0.2, "CanCollide": False},
          children=[{"Name": "Light", "ClassName": "PointLight",
                     "Properties": {"Range": 26, "Brightness": 1.1, "Color": rgb(*color)}}])
    b.sign2("Sign_" + mode_id, (30, 6, 0.4), (0, gh + 6, gate_z - 1.9), title, subtitle, graphite, color,
            (236, 239, 243), angles=(-12, 0, 0), glow=color)
    client_board("GateCount_" + mode_id, (12, 1.8, 0.3), (0, gh + 1.4, gate_z - 1.65))
    # Modus-Name groß vor dem Portal auf der Fläche (lesbar vom Spawn aus)
    b.floor_text("FloorLabel_" + mode_id, (24, 0.1, 5.4), (0, 0.3, gate_z - 13), title, color)
    b.add("Portals", "Portal_" + mode_id, (gw - 1, 0.3, 7), (0, 0.4, gate_z - 4), color, "Neon",
          props={"CanCollide": False, "Transparency": 0.45})
    # Tafeln links und rechts vom Tor: was einen drinnen erwartet, und wo die Minispiele sind
    b.sign2("InfoSafeZone", (22, 6, 0.4), (-34, 12, z1 - 0.5), "SAFE ZONE", "HANDEL  ·  LAGER  ·  FAHRZEUGE  ·  KEIN PVP",
            graphite, (112, 200, 120), (236, 239, 243), glow=(112, 200, 120))
    b.sign2("InfoOutside", (22, 6, 0.4), (34, 12, z1 - 0.5), "DRAUSSEN", "ZOMBIES  ·  LOOT  ·  PVP NACH 5 SEKUNDEN",
            graphite, color, (236, 239, 243), glow=color)
    b.sign2("ArcadeBanner", (40, 2.4, 0.4), (0, H - 1.4, z1 - 0.5), "ARCADE",
            "FFA  ·  HERRSCHAFT  ·  WINGMAN  ·  1v1 ARENA  ·  TRAINING  –  IM MENÜ (M)", graphite, accent, (236, 239, 243),
            glow=accent)
    # ---------- Ostwand (vorn): Tor zum MARKT (eigene Halle mit Ständen, kein Kampf) ----------
    rap = (86, 214, 170)
    mz, mgw, mgh, mgx = 31, 12, 13, x1 - 0.6
    for dz in (-mgw / 2 - 1, mgw / 2 + 1):
        b.box("Decor", "GatePillar", (2, mgh + 2, 2), (mgx, (mgh + 2) / 2, mz + dz), (28, 31, 37), "Metal")
        b.box("Decor", "GateStrip", (0.4, mgh, 0.5), (mgx - 1.2, mgh / 2 + 1, mz + dz), rap, "Neon")
    b.box("Decor", "GateHeader", (2, 2, mgw + 4), (mgx, mgh + 2, mz), (28, 31, 37), "Metal")
    b.box("Decor", "GateGlow", (0.3, mgh, mgw), (mgx + 0.2, mgh / 2, mz), rap, "ForceField",
          props={"Transparency": 0.25, "CanCollide": False},
          children=[{"Name": "Light", "ClassName": "PointLight",
                     "Properties": {"Range": 16, "Brightness": 0.8, "Color": rgb(*rap)}}])
    b.sign2("Sign_Market", (15, 5.2, 0.4), (mgx - 1.6, mgh + 4.4, mz), "MARKT", "STÄNDE · HANDEL · RAP",
            graphite, rap, (236, 239, 243), angles=(0, 90, 0), glow=rap)
    client_board("GateCount_Market", (9, 1.6, 0.3), (mgx - 1.15, mgh + 1.3, mz), angles=(0, 90, 0))
    b.add("Portals", "Portal_Market", (7, 0.3, mgw - 1), (mgx - 4, 0.4, mz), rap, "Neon",
          props={"CanCollide": False, "Transparency": 0.45})


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
    # Große Bildtafel links (das Bild setzt der Client: HubLineup, PHOTO_IMAGE)
    b.box("Decor", "PhotoBoardFrame", (17, 17, 0.4), (-29, 16, z0 + 0.2), steel, "Metal")
    b.box("Decor", "PhotoBoard", (16, 16, 0.4), (-29, 16, z0 + 0.6), graphite, "SmoothPlastic", angles=(0, 180, 0))
    for dy in (-8.6, 8.6):
        b.box("Decor", "PhotoBoardGlow", (17, 0.3, 0.3), (-29, 16 + dy, z0 + 0.7), accent, "Neon")
    for dx in (-8.6, 8.6):
        b.box("Decor", "PhotoBoardGlow", (0.3, 17.5, 0.3), (-29 + dx, 16, z0 + 0.7), accent, "Neon")
    b.add("Decor", "PhotoBoardLight", (1, 0.3, 1), (-29, 25.5, z0 + 3), (255, 248, 230), "Neon",
          props={"Transparency": 0.4},
          children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
              "Face": "Bottom", "Range": 22, "Brightness": 1.2, "Angle": 60, "Color": rgb(255, 245, 230)}}])
    for x, title, sub, color in ((23, "WAFFEN-AUFSÄTZE", "JETZT IM LOADOUT", (112, 178, 112)),):
        if not b.holo:
            b.box("Decor", "PosterFrame", (15, 10, 0.3), (x, 15, z0 + 0.2), steel, "Metal")
        b.sign2("Poster", (14, 9, 0.4), (x, 15, z0 + 0.45), title, sub, graphite, color, (236, 239, 243),
                angles=(0, 180, 0), glow=color)
    for x in (-45, -38, 38, 45):
        b.box("Walls", "WallRib", (1.2, H - 9, 0.8), (x, (H - 9) / 2 + 8, z0 + 0.4), steel, "Metal")
    b.box("Decor", "WallBand", (x1 - x0 - 4, 0.25, 0.15), (0, 7.8, z0 + 0.45), accent, "Neon", props={"Transparency": 0.6})
    for x in range(-48, 49, 5):
        if abs(x) > 12 and -26 < x < 26:  # Ecken bleiben frei: links Siegertreppchen, rechts Glücksrad
            b.box("Decor", "Locker", (4.4, 7.5, 2.2), (x, 3.75, z0 + 1.2), (48, 58, 70), "Metal")
            b.box("Decor", "LockerVent", (3.6, 0.3, 0.1), (x, 6, z0 + 2.35), (26, 28, 32), "Metal")
    for x, z, size in ((-50, 41, 4), (-46, 41, 3)):
        b.crate(x, z, s=size, color=(90, 80, 62))

    # ---------- Ecke links vom Spawn (Südosten): Glücksrad ----------
    # Das drehende Rad (Felder, Nabe, Rand mit Lichtern, Zeiger) baut der Client (HubWheel) an "WheelSpot":
    # Mitte des Rads, LookVector = Vorderseite. Das Rad steht schräg in der Ecke und schaut zur Hallenmitte – so
    # sieht man es vom Spawn, vom Teppich und aus der Halle von vorn. Hier: Podest, Ständer mit Achse, Schild und
    # das Pult mit der Tafel ("WheelBoard", beschreibt der Client) – am Pult öffnet E den Dreh.
    wheel_gold = (212, 170, 80)
    wx, wz, wy, wr = 40, -29.5, 9.4, 6
    face_x, face_z = 0 - wx, (tz + 0) - wz                   # Blick zur Hallenmitte
    flen = math.hypot(face_x, face_z)
    fx, fz = face_x / flen, face_z / flen                    # Vorderseite des Rads
    wyaw = math.degrees(math.atan2(-fx, -fz))                # angles=(0, wyaw, 0): LookVector = (fx, 0, fz)
    sx, sz = -fz, fx                                         # lokale x-Achse (in der Radebene, waagrecht)

    def wpos(side, y, front):
        """Punkt side Studs entlang der Radebene und front Studs vor dem Rad (negativ = dahinter)."""
        return (wx + sx * side + fx * front, y, wz + sz * side + fz * front)

    b.add("Decor", "WheelPlatform", (0.5, 15, 15), (wx, 0.25, wz), (34, 37, 43), "Metal", angles=(0, 0, 90),
          props={"Shape": "Cylinder"})
    b.add("Decor", "WheelPlatformGlow", (0.12, 15.4, 15.4), (wx, 0.3, wz), wheel_gold, "Neon", angles=(0, 0, 90),
          props={"Shape": "Cylinder", "Transparency": 0.45})
    # Ständer und Achse hinter dem Rad
    for side in (-(wr + 1.7), wr + 1.7):
        b.box("Decor", "WheelPillar", (1.6, 17, 1.6), wpos(side, 8.5, -1), (28, 31, 37), "Metal", angles=(0, wyaw, 0))
        b.box("Decor", "WheelPillarStrip", (0.4, 15, 0.2), wpos(side, 8.5, -0.1), wheel_gold, "Neon",
              angles=(0, wyaw, 0), props={"Transparency": 0.15})
    b.box("Decor", "WheelAxle", (2 * wr + 3.4, 0.9, 0.9), wpos(0, wy, -1.2), (28, 31, 37), "Metal", angles=(0, wyaw, 0))
    b.box("Decor", "WheelHeader", (2 * wr + 5, 1.6, 1.6), wpos(0, 17.8, -1), (28, 31, 37), "Metal", angles=(0, wyaw, 0))
    b.sign2("WheelSign", (15, 3.6, 0.4), wpos(0, 20.4, -0.1), "GLÜCKSRAD", "TÄGLICH GRATIS DREHEN",
            graphite, wheel_gold, (236, 239, 243), angles=(0, wyaw, 0), glow=wheel_gold)
    b.add("Decor", "WheelSpot", (1, 1, 1), (wx, wy, wz), wheel_gold, "SmoothPlastic", angles=(0, wyaw, 0),
          props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
    # Pult vorn am Podest, darauf die schräge Tafel (Vorderseite zum Spieler)
    b.box("Decor", "WheelConsole", (5.6, 2.2, 1.6), wpos(0, 1.1, 7.4), (36, 39, 46), "Metal", angles=(0, wyaw, 0))
    b.box("Decor", "WheelConsoleStrip", (5.7, 0.2, 1.7), wpos(0, 2.1, 7.4), wheel_gold, "Neon", angles=(0, wyaw, 0),
          props={"Transparency": 0.2})
    client_board("WheelBoard", (5.2, 1.9, 0.15), wpos(0, 2.75, 7.55), angles=yaw_tilt(wyaw, 35))
    b.add("Decor", "WheelLight", (0.2, 3, 3), wpos(0, H - 1.6, 4), (255, 248, 230), "Neon", angles=(0, 0, 90),
          props={"Shape": "Cylinder", "Transparency": 0.3},
          children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
              "Face": "Bottom", "Range": 26, "Brightness": 1.3, "Angle": 45, "Color": rgb(255, 245, 230)}}])
    # Teppich vom Spawn-Teppich bis direkt vor das Pult
    front = wpos(0, 0, 10)
    carpet("CarpetWheel", (4, front[2] + 2), (front[0], front[2]), 7)

    b.save("Hub.model.json")

# ---------- Markt: Handelshalle mit 12 Ständen (MarketService / MarketClient) ----------
MARKET_CANOPIES = ((186, 72, 60), (64, 120, 186), (72, 150, 96), (206, 158, 64), (132, 84, 170), (206, 112, 54))


def build_market():
    """Markt als Theater-Rund (Radius 94, ohne Dach): In der Mitte der Marktplatz (Spawns, Such-Terminal, zwei
    Kisten-Automaten, Tafeln, Tor zurück zum Hub). Darum drei breite Ränge, die nach außen stufenweise höher werden
    (2,4 / 5,4 / 8,4 m); auf jedem Rang stehen die Stände mit der Vorderseite zur Mitte (12 + 16 + 20 = 48). Das Tor
    zurück zum Hub steht am Ende der Südrampe (oberster Rang), damit der Platz frei bleibt. Vier
    Rampen (Himmelsrichtungen) führen vom Platz über alle Ränge nach oben, die Stufen dazwischen kann man auch
    springen. Ein Stand ist ein Ordner "Stand_<n>" mit Theke, Regal, Vordach, Schild ("Sign", beschreibt der Client),
    sechs Ausstellplätzen ("Display1".."Display6": Mitte des Skins, LookVector zum Gang) und dem Prompt-Punkt vor der
    Theke ("Prompt"). Besitzer, Name und Angebote setzt der Server als Attribute an den Ordner. Der Client beschreibt
    außerdem "OverviewBoard" und "TopBoard" und hängt an "SearchTerminal" sowie "CrateWeapon" / "CrateAgent" ein
    E-Prompt. Winkel phi: 0 = +x, 90 = +z (Norden)."""
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

    # Kisten-Automaten am Platzrand (Viertel 1), Vorderseite zur Mitte
    def crate_machine(key, title, sub, phi, color):
        cx, cz = polar(25, phi)
        yaw = 90 - phi  # lokal: -Z = Vorderseite zur Mitte
        at = frame(cx, cz, 0.24, yaw)
        b.box("Decor", "CrateBase" + key, (6, 0.8, 5), at(0, 0.4, 0), (30, 32, 38), "Metal", angles=(0, yaw, 0))
        b.box("Decor", "CrateBody" + key, (5, 3.6, 4), at(0, 2.6, 0), color, "Metal", angles=(0, yaw, 0))
        b.box("Decor", "CrateLid" + key, (5.4, 0.7, 4.4), at(0, 4.75, 0), lighten(color, 0.25), "Metal", angles=(0, yaw, 0))
        for dx in (-2.2, 2.2):
            b.box("Decor", "CrateBand" + key, (0.4, 3.8, 4.2), at(dx, 2.6, 0), (30, 32, 38), "Metal", angles=(0, yaw, 0))
        b.add("Decor", "Crate" + key, (3.2, 2, 0.3), at(0, 2.8, -2.1), lighten(color, 0.4), "Neon", angles=(0, yaw, 0),
              props={"Transparency": 0.15},
              children=[{"Name": "Light", "ClassName": "PointLight",
                         "Properties": {"Range": 16, "Brightness": 1.0, "Color": rgb(*color)}}])
        b.sign2("CrateSign" + key, (5, 1.5, 0.2), at(0, 6.3, -2.0), title, sub, graphite, color, (236, 239, 243), angles=(0, yaw, 0))
        # schwebende Kiste mit Lichtsäule: von weitem zu erkennen, welche Kiste das ist
        b.box("Decor", "CrateIcon" + key, (1.8, 1.8, 1.8), at(0, 9.6, 0), lighten(color, 0.3), "Neon", angles=(45, yaw + 45, 0),
              props={"Transparency": 0.1})
        b.box("Decor", "CrateIconBand" + key, (2.0, 0.35, 2.0), at(0, 9.6, 0), (30, 32, 38), "Metal", angles=(45, yaw + 45, 0))
        b.cylinder("Decor", "CrateBeam" + key, 2.2, 7, at(0, 6.4, 0), color, "Neon", props={"Transparency": 0.8, "CanCollide": False})

    crate_machine("Weapon", "WAFFEN-KISTE", "450 MÜNZEN", 58, (212, 170, 80))
    crate_machine("Agent", "AGENTEN-KISTE", "800 MÜNZEN", 32, (96, 164, 214))

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

    # Tor zurück zum Hub: am Ende der Südrampe auf dem obersten Rang, damit der Spawn frei bleibt
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
    b.sign2("ExitSign", (11, 3.2, 0.4), gate(0, gh + 3.8, -1.2), "ZUM HUB", "ZURÜCK IN DIE EINSATZZENTRALE", graphite,
            (120, 185, 235), (236, 239, 243), angles=(0, gyaw, 0), glow=(120, 185, 235))
    b.add("Portals", "Portal_Hub", (gw - 1, 0.3, 4), gate(0, 0.15, -2.6), (120, 185, 235), "Neon", angles=(0, gyaw, 0),
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


# ---------- Free-for-All: "Altstadt" (230 x 230) für bis zu 12 Spieler ----------

def build_altstadt():
    """Altstadt: Markthalle in der Mitte (offen, umlaufende Galerie auf 7 m über zwei Treppen, Brunnen),
    Ringgasse und vier Hauptgassen mit Marktständen, vier zweistöckige Eckhäuser (Fenster in alle Richtungen,
    Türen auf beiden Ebenen zu Balkonen), kleine Häuser mit Treppe aufs Dach (Brüstung zum Spähen),
    Gärten mit Mauern in den Ecken. 16 Spawns am Rand, jeder mit Deckung davor."""
    b = Builder(FFA_ORIGIN)
    size = 230
    cobble, plaster, plaster2, timber = (122, 114, 104), (196, 182, 160), (170, 140, 112), (92, 66, 48)
    roof_red, roof_dark, stone = (150, 70, 52), (84, 70, 64), (138, 132, 124)
    b.ground(size + 10, size + 10, cobble, "Cobblestone")
    b.border(size, size, 20, (150, 132, 112), "Brick", barrier=140)
    # Gassen etwas dunkler gepflastert (Ring um die Halle und vier Hauptgassen)
    b.box("Ground", "Ring", (76, 0.1, 76), (0, 0.05, 0), (104, 98, 92), "Cobblestone")
    for ax in (True, False):
        size_lane = (16, 0.1, 76) if ax else (76, 0.1, 16)
        for d in (-1, 1):
            pos = (0, 0.06, d * 76) if ax else (d * 76, 0.06, 0)
            b.box("Ground", "Lane", size_lane, pos, (104, 98, 92), "Cobblestone")

    # ---------- Markthalle (44 x 44), Galerie auf 7, Dach auf 14 mit Oberlicht ----------
    H, G = 14, 7
    for x in (-22, -11, 11, 22):
        for z in (-22, 22):
            b.pillar(x, z, H, s=1.6, color=stone, material="Concrete")
            b.pillar(z, x, H, s=1.6, color=stone, material="Concrete")
    b.slab("HallRoof", -24, 24, -24, 24, H + 1, roof_red, holes=[(-10, 10, -10, 10)], material="Slate")
    b.box("Decor", "HallRoofRidge", (48.6, 0.6, 0.6), (0, H + 1.3, 24.3), timber, "Wood")
    b.box("Decor", "HallRoofRidge", (48.6, 0.6, 0.6), (0, H + 1.3, -24.3), timber, "Wood")
    # Galerie: vier Streifen, Brüstung innen und außen (mit Lücken für die Treppen)
    b.catwalk("Gallery", -22, 22, 16, 22, G, color=(110, 84, 60))
    b.catwalk("Gallery", -22, 22, -22, -16, G, color=(110, 84, 60))
    b.catwalk("Gallery", -22, -16, -16, 16, G, color=(110, 84, 60))
    b.catwalk("Gallery", 16, 22, -16, 16, G, color=(110, 84, 60))
    rail = (90, 64, 44)
    for z in (22, -22):  # außen (brusthoch: Deckung beim Schießen nach draußen)
        b.box("Cover", "GalleryParapet", (44, 2.4, 0.6), (0, G + 1.2, z + (0.3 if z < 0 else -0.3)), plaster2, "Brick")
    for x in (22, -22):
        b.box("Cover", "GalleryParapet", (0.6, 2.4, 32), (x + (0.3 if x < 0 else -0.3), G + 1.2, 0), plaster2, "Brick")
    for z, gap in ((16, -12), (-16, 12)):  # innen, Lücke an der Treppe
        for x0, x1 in ((-16, gap - 2.5), (gap + 2.5, 16)):
            b.box("Buildings", "GalleryRail", (x1 - x0, 1.1, 0.3), ((x0 + x1) / 2, G + 1.1, z), rail, "Wood")
    for x in (16, -16):
        b.box("Buildings", "GalleryRail", (0.3, 1.1, 32), (x, G + 1.1, 0), rail, "Wood")
    # zwei Treppen im Innenhof hinauf zur Galerie
    b.stairs("GalleryStairs", -12, 6.9, 4, G, "N", color=(110, 84, 60))
    b.stairs("GalleryStairs", 12, -6.9, 4, G, "S", color=(110, 84, 60))
    # Brunnen in der Mitte (Deckung), Stände unter der Galerie
    b.cylinder("Cover", "Fountain", 10, 2.4, (0, 1.2, 0), stone, "Concrete")
    b.cylinder("Decor", "FountainWater", 8.6, 0.3, (0, 2.3, 0), (90, 150, 190), "Glass", props={"Transparency": 0.3})
    b.cylinder("Cover", "FountainColumn", 2, 6, (0, 3, 0), stone, "Concrete")
    for x, z, ax in ((-19, -6, False), (19, 6, False), (6, 19, True), (-6, -19, True)):
        b.stall(x, z, along_x=ax, canopy=(160, 60, 50))

    # ---------- Hauptgassen: Marktstände, Karren, Fässer ----------
    canopies = ((170, 60, 50), (60, 110, 150), (190, 150, 60), (80, 130, 80))
    for i, (x, z, ax) in enumerate(((-5, 46, True), (5, 66, True), (-5, 88, True),
                                    (5, -46, True), (-5, -66, True), (5, -88, True),
                                    (46, 5, False), (66, -5, False), (88, 5, False),
                                    (-46, -5, False), (-66, 5, False), (-88, -5, False))):
        b.stall(x, z, along_x=not ax, canopy=canopies[i % 4])
    for x, z in ((30, 30), (-30, -30), (30, -30), (-30, 30)):
        b.cylinder("Cover", "Barrel", 2.6, 3.4, (x + 1.5, 1.7, z), (110, 76, 50), "Wood")
        b.cylinder("Cover", "Barrel", 2.6, 3.4, (x - 1.5, 1.7, z + 1), (110, 76, 50), "Wood")
        b.crate(x, z - 3, s=3)

    # ---------- Vier Eckhäuser (zweistöckig, Balkone Richtung Halle) ----------
    for sx in (-1, 1):
        for sz in (-1, 1):
            hx, hz = sx * 66, sz * 66
            inner_x = "W" if sx > 0 else "E"  # Seite zur Mittelgasse (x)
            inner_z = "S" if sz > 0 else "N"  # Seite zur Mittelgasse (z)
            outer_x = "E" if sx > 0 else "W"
            outer_z = "N" if sz > 0 else "S"
            b.building2(f"Corner{sx}{sz}", hx, hz, 32, 26, plaster if (sx * sz) > 0 else plaster2, roof_red,
                        doors={inner_x: [-6, 6], inner_z: [-8, 8], outer_x: [0]},
                        windows1={inner_x: [0], inner_z: [0], outer_z: [-8, 8]},
                        windows2={inner_x: [-8, 8], outer_x: [-8, 8], outer_z: [-10, 0, 10]},
                        doors2={inner_z: [0]}, stairs_at=(outer_z,), material="Brick")
            # Balkon vor der Obergeschoss-Tür (Richtung Halle) mit Brüstung
            bz = hz - sz * 13 - sz * 2.5
            b.catwalk("Balcony", hx - 7, hx + 7, min(bz - 2.5, bz + 2.5), max(bz - 2.5, bz + 2.5), 10.5,
                      rails=("S" if sz > 0 else "N", "E", "W"), color=(110, 84, 60), rail_color=rail)
            for dx in (-6, 6):
                b.box("Buildings", "BalconyPost", (0.6, 10, 0.6), (hx + dx, 5, bz - sz * 2), timber, "Wood")
            # Fachwerk-Balken an der Fassade
            b.box("Decor", "Timber", (32.2, 0.6, 26.2), (hx, 10.2, hz), timber, "Wood")

    # ---------- Kleine Häuser mit Dachterrasse (Treppe außen) ----------
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * 30, sz * 100
            b.house(f"Small{sx}{sz}", x, z, 16, 12, 10, plaster2 if sx > 0 else plaster, roof_dark,
                    doors=("S" if sz > 0 else "N", "W" if sx > 0 else "E"), material="Brick")
            # Treppe an der Seite zur Hauptgasse hinauf aufs Dach (Oberkante 11)
            b.stairs("RoofStairs", sx * 18, z - sz * 7.4, 4, 11, "N" if sz > 0 else "S", color=stone)
            # Brüstung auf dem Dach (zur Mitte und zur Gasse)
            b.box("Cover", "RoofParapet", (16.6, 1.8, 0.6), (x, 11.9, z - sz * 6.2), stone, "Brick")
            b.box("Cover", "RoofParapet", (0.6, 1.8, 12.6), (x + sx * 8.2, 11.9, z), stone, "Brick")
            # Haus Ost/West (eingeschossig, Durchgang)
            x2, z2 = sx * 100, sz * 30
            b.house(f"Side{sx}{sz}", x2, z2, 12, 16, 10, plaster if sz > 0 else plaster2, roof_dark,
                    doors=("W" if sx > 0 else "E", "N" if sz > 0 else "S"), material="Brick")

    # ---------- Ecken: Gärten mit Mauern und Bäumen (Spawn-Bereiche) ----------
    rng = random.Random(12)
    for sx in (-1, 1):
        for sz in (-1, 1):
            gx, gz = sx * 98, sz * 98
            b.wall_line("GardenWall", min(sx * 84, sx * 112), max(sx * 84, sx * 112), sz * 84, True, 4, stone, "Brick",
                        openings=[(sx * 96, 5, 0, 4)], group="Cover")
            b.wall_line("GardenWall", min(sz * 84, sz * 112), max(sz * 84, sz * 112), sx * 84, False, 4, stone, "Brick",
                        openings=[(sz * 100, 5, 0, 4)], group="Cover")
            b.tree(gx + sx * 6, gz - sz * 6, rng)
            b.crate(gx - sx * 4, gz + sz * 2, s=3)

    # ---------- Hofmauern mit Durchgang und Guckfenster (zwischen Gassen und Eckhäusern) ----------
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.wall_line("CourtWall", min(sx * 14, sx * 46), max(sx * 14, sx * 46), sz * 56, True, 4.4, stone, "Brick",
                        openings=[(sx * 24, 5, 0, 4.4), (sx * 38, 3, 1.8, 3.4)], group="Cover")
            b.wall_line("CourtWall", min(sz * 14, sz * 46), max(sz * 14, sz * 46), sx * 56, False, 4.4, stone, "Brick",
                        openings=[(sz * 24, 5, 0, 4.4), (sz * 38, 3, 1.8, 3.4)], group="Cover")
    # Halle: brusthohe Mauern zwischen den äußeren Pfeilern (offen bleiben die Mitten und die Ecken)
    for d in (-1, 1):
        for a in (-1, 1):
            b.half_wall(a * 16.5, d * 22, 9, along_x=True, color=plaster2)
            b.half_wall(d * 22, a * 16.5, 9, along_x=False, color=plaster2)

    # ---------- Deckung auf den Plätzen zwischen Häusern ----------
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.half_wall(sx * 42, sz * 42, 8, along_x=True, color=stone)
            b.half_wall(sx * 30, sz * 66, 6, along_x=False, color=stone)
            b.half_wall(sx * 66, sz * 30, 6, along_x=True, color=stone)
            b.crate(sx * 44, sz * 88, s=4)
            b.crate(sx * 88, sz * 44, s=4)
            b.cylinder("Cover", "Well", 5, 3, (sx * 102, 1.5, sz * 66 if sz > 0 else sz * 66), stone, "Concrete")

    # Laternen an der Ringgasse
    for x, z in ((-30, 38), (30, 38), (-30, -38), (30, -38), (38, 30), (38, -30), (-38, 30), (-38, -30)):
        b.box("Decor", "LanternPost", (0.4, 8, 0.4), (x, 4, z), (40, 40, 44), "Metal")
        b.add("Decor", "Lantern", (1, 1.4, 1), (x, 8.4, z), (255, 210, 140), "Neon",
              children=[{"Name": "Light", "ClassName": "PointLight",
                         "Properties": {"Range": 18, "Brightness": 0.9, "Color": rgb(255, 210, 150)}}])

    # ---------- Spawns (16) am Rand, Blick zur Mitte, je mit Deckung davor ----------
    points = [(sx * 104, sz * 104) for sx in (-1, 1) for sz in (-1, 1)]
    points += [(0, 106), (0, -106), (106, 0), (-106, 0)]
    points += [(sx * 60, sz * 106) for sx in (-1, 1) for sz in (-1, 1)]
    points += [(sx * 106, sz * 60) for sx in (-1, 1) for sz in (-1, 1)]
    for x, z in points:
        b.spawn(x, z, yaw=face(x, z))
    for x, z in ((0, 98), (0, -98), (98, 0), (-98, 0)):
        b.barrier(x, z, along_x=abs(z) > abs(x), length=6)

    b.save("FreeForAll.model.json", "Altstadt")


# ---------- Free-for-All: "Favela" (220 x 220), Rogue-Company-Stil ----------

FAVELA_ORIGIN = (0, 0, -1500)
ORBIT_ORIGIN = (-1500, 0, 0)
LAGUNE_ORIGIN = (1500, 0, 1500)
MONDBASIS_ORIGIN = (3000, 0, -1500)
RC_COLORS = [(255, 120, 150), (80, 200, 190), (250, 205, 80), (255, 150, 70), (150, 210, 90), (120, 150, 235),
             (235, 110, 95), (200, 125, 225)]


def build_favela():
    """Favela: Bolzplatz mit Tribünen in der Mitte, zwei Ringe aus bunten Flachdach-Häusern (innen 8 hoch,
    außen 10 hoch) mit engen Gassen und Durchgängen. Über die Dächer ein zusammenhängendes Netz aus Stegen
    (innerer Ring rundum, äußerer Ring in vier Bögen, Rampen dazwischen), Treppen von den Gassen hinauf,
    Wassertanks auf den Dächern als Deckung. Plätze an den Hauptgassen mit Kiosk und Palmen (keine langen
    Sichtlinien vom Rand zum Platz). 16 Spawns außen."""
    b = Builder(FAVELA_ORIGIN)
    rng = random.Random(23)
    size = 220
    b.ground(size + 10, size + 10, (196, 170, 132), "Concrete")
    b.border(size, size, 22, (214, 126, 96), "Brick", barrier=140)
    colors = iter(RC_COLORS * 8)
    white, wood = (245, 245, 240), (130, 96, 64)

    # ---------- Bolzplatz ----------
    b.box("Ground", "Court", (44, 0.1, 30), (0, 0.05, 0), (60, 150, 100), "SmoothPlastic")
    for size_l, pos in (((44, 0.06, 0.3), (0, 0.12, 15)), ((44, 0.06, 0.3), (0, 0.12, -15)),
                        ((0.3, 0.06, 30), (22, 0.12, 0)), ((0.3, 0.06, 30), (-22, 0.12, 0)), ((0.3, 0.06, 30), (0, 0.12, 0))):
        b.box("Ground", "CourtLine", size_l, pos, white, "SmoothPlastic")
    b.add("Ground", "CourtCircle", (0.06, 9, 9), (0, 0.11, 0), white, "SmoothPlastic", angles=(0, 0, 90),
          props={"Shape": "Cylinder"})
    b.add("Ground", "CourtCircleIn", (0.06, 8.4, 8.4), (0, 0.13, 0), (60, 150, 100), "SmoothPlastic", angles=(0, 0, 90),
          props={"Shape": "Cylinder"})
    for sx in (-1, 1):
        for dz in (-3.2, 3.2):
            b.box("Decor", "GoalPost", (0.4, 3.4, 0.4), (sx * 22, 1.7, dz), white, "Metal")
        b.box("Decor", "GoalBar", (0.4, 0.4, 6.8), (sx * 22, 3.4, 0), white, "Metal")
        b.box("Decor", "GoalNet", (2, 3.2, 6.4), (sx * 23.2, 1.6, 0), (230, 230, 230), "Fabric",
              props={"Transparency": 0.55, "CanCollide": False})
        # brusthohe Bande mit Lücken (Mitte der Längsseiten, Ecken)
        b.half_wall(sx * 13, 16.2, 14, along_x=True, color=(250, 205, 80))
        b.half_wall(sx * 13, -16.2, 14, along_x=True, color=(250, 205, 80))
        b.half_wall(sx * 24.5, 0, 14, along_x=False, color=(250, 205, 80))
    # Tribünen (drei Stufen) nördlich und südlich
    for sz in (-1, 1):
        for k, (h, depth) in enumerate(((1.2, 6), (2.4, 4), (3.6, 2))):
            b.box("Buildings", "Bleacher", (30, h, depth), (0, h / 2, sz * (18 + 3 - depth / 2 + 3)), (120, 150, 235)
                  if k % 2 == 0 else (90, 120, 210), "Concrete")

    # ---------- Innerer Ring (8 hoch, Dach 9): Reihen N/S, Spalten O/W ----------
    inner = []
    for sz in (-1, 1):
        for x in (-36, -12, 12, 36):
            inner.append(("Row", x, sz * 40, 16, 12, sz))
    for sx in (-1, 1):
        for z in (-16, 16):
            inner.append(("Col", sx * 44, z, 12, 16, sx))
    for kind, x, z, w, d, side in inner:
        if kind == "Row":
            inside = "S" if side > 0 else "N"
            outside = "N" if side > 0 else "S"
            gaps = {inside: [5 if x > 0 else -5]} if abs(x) == 36 else {}
            b.flat_house(f"InnerRow{x}{z}", x, z, w, d, 8, next(colors), doors={inside: [0], outside: [0]},
                         windows={inside: [-5, 5], outside: [-5, 5]}, parapet=(inside,), gaps=gaps, trim=white)
        else:
            inside = "W" if side > 0 else "E"
            outside = "E" if side > 0 else "W"
            b.flat_house(f"InnerCol{x}{z}", x, z, w, d, 8, next(colors), doors={inside: [0], outside: [0]},
                         windows={inside: [-5, 5], outside: [-5]}, parapet=(inside,), trim=white)
    # Stege auf dem inneren Ring (rundum verbunden)
    for sz in (-1, 1):
        for x0, x1 in ((-28, -20), (-4, 4), (20, 28)):
            b.plank("RoofBridge", (x0, 9, sz * 40), (x1, 9, sz * 40))
        for sx in (-1, 1):
            b.plank("RoofBridge", (sx * 41, 9, sz * 24), (sx * 41, 9, sz * 34))
    for sx in (-1, 1):
        b.plank("RoofBridge", (sx * 44, 9, -8), (sx * 44, 9, 8))
    # Treppen von außen hinauf (je zwei pro Seite)
    for sz in (-1, 1):
        for sx in (-1, 1):
            b.stairs("RoofStairs", sx * 20, sz * 49, 4, 9, "W" if sx > 0 else "E", color=(160, 150, 140))
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.stairs("RoofStairs", sx * 53, sz * 24, 4, 9, "S" if sz > 0 else "N", color=(160, 150, 140))

    # ---------- Äußerer Ring (10 hoch, Dach 11) ----------
    for sz in (-1, 1):
        for x in (-80, -54, -28, 28, 54, 80):
            inside = "S" if sz > 0 else "N"
            outside = "N" if sz > 0 else "S"
            gaps = {inside: [4 if x > 0 else -4]} if abs(x) == 28 else {}
            b.flat_house(f"OuterRow{x}{sz}", x, sz * 76, 18, 14, 10, next(colors), doors={inside: [-4], outside: [4]},
                         windows={inside: [4], outside: [-4]}, parapet=(inside,), gaps=gaps, trim=white)
    for sx in (-1, 1):
        for z in (-48, -22, 22, 48):
            inside = "W" if sx > 0 else "E"
            outside = "E" if sx > 0 else "W"
            gaps = {inside: [-4 if z > 0 else 4]} if abs(z) == 22 else {}
            b.flat_house(f"OuterCol{sx}{z}", sx * 78, z, 14, 18, 10, next(colors), doors={inside: [4], outside: [-4]},
                         windows={inside: [-4], outside: [4]}, parapet=(inside,), gaps=gaps, trim=white)
    for sz in (-1, 1):
        for sx in (-1, 1):
            b.plank("RoofBridge", (sx * 37, 11, sz * 76), (sx * 45, 11, sz * 76))
            b.plank("RoofBridge", (sx * 63, 11, sz * 76), (sx * 71, 11, sz * 76))
            b.plank("RoofBridge", (sx * 78, 11, sz * 31), (sx * 78, 11, sz * 39))
            b.plank("RoofBridge", (sx * 78, 11, sz * 57), (sx * 78, 11, sz * 69))
            # Rampen vom inneren auf den äußeren Ring
            b.plank("RoofRamp", (sx * 32, 9, sz * 46), (sx * 32, 11, sz * 69))
            b.plank("RoofRamp", (sx * 50, 9, sz * 18), (sx * 71, 11, sz * 18))
            # Treppen von außen auf den äußeren Ring
            b.stairs("RoofStairs", sx * 46, sz * 86, 4, 11, "E" if sx > 0 else "W", color=(160, 150, 140))
            b.stairs("RoofStairs", sx * 88, sz * 40, 4, 11, "N" if sz > 0 else "S", color=(160, 150, 140))
    # Wassertanks und Schüsseln auf den Dächern (Deckung oben)
    for x, z, top in ((-12, 43, 9), (12, -43, 9), (-46, 13, 9), (46, -13, 9), (54, 79, 11), (-54, -79, 11),
                      (-81, 48, 11), (81, -48, 11), (80, 76, 11), (-80, -76, 11)):
        b.cylinder("Cover", "WaterTank", 3.4, 4, (x, top + 2, z), (60, 120, 210), "SmoothPlastic")
    for x, z, top in ((36, 43, 9), (-36, -43, 9), (-28, 79, 11), (28, -79, 11)):
        b.add("Decor", "Dish", (0.3, 3, 3), (x, top + 1.8, z), (235, 235, 235), "Metal", angles=(0, 30, 70),
              props={"Shape": "Cylinder"})

    # ---------- Plätze an den Hauptgassen: Kiosk (bricht die Sichtlinie), Palmen, Stände ----------
    for sx, sz, ax in ((0, 1, True), (0, -1, True), (1, 0, False), (-1, 0, False)):
        kx, kz = sx * 60, sz * 60
        w, d = (14, 9) if ax else (9, 14)
        b.flat_house(f"Kiosk{sx}{sz}", kx, kz, w, d, 7, next(colors),
                     doors={"E": [0], "W": [0]} if ax else {"N": [0], "S": [0]},
                     windows={"N": [-3, 3], "S": [-3, 3]} if ax else {"E": [-3, 3], "W": [-3, 3]}, parapet=(), trim=white)
        for dd in (-1, 1):
            px, pz = (kx + dd * 13, kz + sz * 14) if ax else (kx + sx * 14, kz + dd * 13)
            b.palm(px, pz, h=rng.uniform(12, 16), rng=rng)
        stall_pos = (kx + 12, kz - sz * 10) if ax else (kx - sx * 10, kz + 12)
        b.stall(stall_pos[0], stall_pos[1], along_x=ax, canopy=next(colors))
    # Diagonale Plätze: Palme, Kisten, halbhohe Mauer, Moped
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.palm(sx * 60, sz * 58, h=rng.uniform(12, 15), rng=rng)
            b.crate(sx * 54, sz * 62, s=3, color=(150, 110, 70))
            b.half_wall(sx * 63, sz * 63, 7, along_x=sx * sz > 0, color=next(colors))
            b.box("Cover", "Moped", (3.6, 2.4, 1.4), (sx * 56, 1.2, sz * 54), next(colors), "SmoothPlastic")
            # Wäscheleinen über den Gassen (Deko)
            b.box("Decor", "Laundry", (0.1, 0.1, 10), (sx * 24, 7, sz * 29), (60, 60, 60), "Fabric",
                  props={"CanCollide": False})
            for k in range(3):
                b.box("Decor", "Cloth", (0.1, 1.6, 1.6), (sx * 24, 6.1, sz * 29 + (k - 1) * 3), next(colors), "Fabric",
                      props={"CanCollide": False})

    # ---------- Außenring: Spawns mit Deckung, Graffiti-Schild ----------
    points = [(sx * 100, sz * 100) for sx in (-1, 1) for sz in (-1, 1)]
    points += [(0, 100), (0, -100), (100, 0), (-100, 0)]
    points += [(sx * 50, sz * 100) for sx in (-1, 1) for sz in (-1, 1)]
    points += [(sx * 100, sz * 50) for sx in (-1, 1) for sz in (-1, 1)]
    for x, z in points:
        b.spawn(x, z, yaw=face(x, z))
        cx, cz = x * 0.9, z * 0.9
        b.crate(cx + (3 if x == 0 else 0), cz + (3 if z == 0 else 0), s=3.4, color=(150, 110, 70))
    b.sign("FavelaSign", (30, 6, 0.4), (0, 16, 108.5), "FAVELA", (40, 40, 50), (255, 120, 150), angles=(0, 180, 0))
    b.sign("FavelaSignS", (30, 6, 0.4), (0, 16, -108.5), "FAVELA", (40, 40, 50), (80, 200, 190))

    b.save("Favela.model.json", "Favela", atmosphere="Tropical")


# ---------- Free-for-All: "Orbit" (210 x 210), Raumstation ----------

def build_orbit():
    """Orbit: Raumstation unter Sternenhimmel. Mitte: Reaktorraum mit leuchtendem Kern, Kühltanks als Deckung und
    Laufstegen an zwei Wänden. Vier geschlossene Korridore (Fensterschlitze, Seitentüren) führen zu den Modulen:
    Kommandozentrale (zweistöckig, N), Hangar mit Shuttle (S), Labor (zweistöckig, O), Gewächshaus aus Glas (W).
    Dazwischen offene Decks: Landeplattform, Antennenturm mit Aussichtsplattform, Frachtbereich (zwei Ebenen),
    Solarfarm. 16 Spawns am Rand."""
    b = Builder(ORBIT_ORIGIN)
    size = 210
    deck, wall, white = (44, 48, 58), (66, 72, 86), (214, 220, 232)
    cyan, magenta, dark = (60, 220, 255), (230, 80, 255), (26, 28, 36)
    b.ground(size + 10, size + 10, deck, "DiamondPlate")
    b.border(size, size, 20, (34, 38, 48), "Metal", barrier=140)
    for d in (-1, 1):
        b.box("Decor", "BorderGlow", (size, 0.4, 0.4), (0, 19.6, d * (size / 2 + 0.3)), cyan, "Neon")
        b.box("Decor", "BorderGlow", (0.4, 0.4, size), (d * (size / 2 + 0.3), 19.6, 0), cyan, "Neon")
    # Leuchtlinien im Boden
    for k in range(-90, 91, 30):
        b.box("Ground", "FloorLine", (size, 0.06, 0.25), (0, 0.04, k), cyan, "Neon", props={"Transparency": 0.7})
        b.box("Ground", "FloorLine", (0.25, 0.06, size), (k, 0.04, 0), cyan, "Neon", props={"Transparency": 0.7})
    # Planet mit Ring am Himmel (nur Deko)
    b.add("Decor", "Planet", (180, 180, 180), (-180, 230, 260), (210, 120, 90), "SmoothPlastic",
          props={"Shape": "Ball", "CanCollide": False, "CanQuery": False, "CastShadow": False})
    b.add("Decor", "PlanetRing", (1, 320, 320), (-180, 230, 260), (230, 200, 150), "SmoothPlastic", angles=(20, 0, 70),
          props={"Shape": "Cylinder", "CanCollide": False, "CanQuery": False, "CastShadow": False, "Transparency": 0.5})

    # ---------- Reaktorraum (52 x 52, Höhe 16) ----------
    R, RH = 26, 16
    for z, name in ((R, "ReactorN"), (-R, "ReactorS")):
        b.wall_line(name, -R, R, z, True, RH, wall, "Metal", openings=[(0, 10, 0, 9), (-15, 4, 10, 13), (15, 4, 10, 13)])
    for x, name in ((R, "ReactorE"), (-R, "ReactorW")):
        b.wall_line(name, -R + 1.2, R - 1.2, x, False, RH, wall, "Metal",
                    openings=[(0, 10, 0, 9), (-15, 4, 10, 13), (15, 4, 10, 13)])
    for z in (R + 0.7, -R - 0.7):
        b.box("Decor", "ReactorGlow", (R * 2, 0.4, 0.3), (0, RH - 0.5, z), magenta, "Neon")
    for x in (R + 0.7, -R - 0.7):
        b.box("Decor", "ReactorGlow", (0.3, 0.4, R * 2), (x, RH - 0.5, 0), magenta, "Neon")
    b.cylinder("Buildings", "CoreBase", 16, 2, (0, 1, 0), (80, 86, 100), "Metal")
    b.cylinder("Buildings", "Core", 7, 30, (0, 15, 0), cyan, "Neon")
    for y in (6, 12, 18, 24):
        b.cylinder("Decor", "CoreRing", 9.4, 0.6, (0, y, 0), magenta, "Neon")
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.cylinder("Cover", "CoolantTank", 4.4, 6, (sx * 13, 3, sz * 13), white, "Metal")
            b.cylinder("Decor", "CoolantBand", 4.6, 0.4, (sx * 13, 4.5, sz * 13), cyan, "Neon")
    for x, z in ((0, 13), (0, -13)):
        b.half_wall(x, z, 6, along_x=True, color=(90, 96, 110))
    # Laufstege an Nord- und Südwand (Höhe 8), Treppen an beiden Enden
    for dz in (-1, 1):
        z0, z1 = (20, 25.4) if dz > 0 else (-25.4, -20)
        b.catwalk("ReactorWalk", -14.6, 14.6, z0, z1, 8, rails=("S" if dz > 0 else "N",), rail_color=cyan)
        b.stairs("ReactorStairs", -25.2, dz * 22.7, 4, 8, "E", color=(80, 86, 100))
        b.stairs("ReactorStairs", 25.2, dz * 22.7, 4, 8, "W", color=(80, 86, 100))

    # ---------- Korridore zu den Modulen (Breite 14, Höhe 9, Dach mit Lichtband) ----------
    for d in (-1, 1):
        # Nord/Süd
        za, zb = sorted((d * (R + 0.6), d * 53))
        for x in (-7, 7):
            b.wall_line("Corridor", za, zb, x, False, 9, wall, "Metal",
                        openings=[(d * 39.5, 5, 0, 7.5), (d * 33, 4, 3, 6), (d * 46, 4, 3, 6)])
        b.box("Buildings", "CorridorRoof", (15.2, 1, zb - za), (0, 9.5, (za + zb) / 2), (54, 58, 70), "Metal")
        b.box("Decor", "CorridorLight", (2, 0.2, zb - za), (0, 8.9, (za + zb) / 2), white, "Neon")
        # Ost/West
        xa, xb = sorted((d * (R + 0.6), d * 56))
        for z in (-7, 7):
            b.wall_line("Corridor", xa, xb, z, True, 9, wall, "Metal",
                        openings=[(d * 41, 5, 0, 7.5), (d * 34, 4, 3, 6), (d * 48, 4, 3, 6)])
        b.box("Buildings", "CorridorRoof", (xb - xa, 1, 15.2), ((xa + xb) / 2, 9.5, 0), (54, 58, 70), "Metal")
        b.box("Decor", "CorridorLight", (xb - xa, 0.2, 2), ((xa + xb) / 2, 8.9, 0), white, "Neon")

    # ---------- Module ----------
    b.building2("Command", 0, 64, 34, 22, white, (50, 54, 66), doors={"S": [0], "E": [0], "W": [0]},
                windows1={"S": [-11, 11], "E": [-5], "W": [5]}, windows2={"S": [-12, -4, 4, 12], "N": [-8, 8], "E": [0], "W": [0]},
                stairs_at=("N",), material="Metal")
    b.box("Decor", "CommandGlow", (34.4, 0.4, 22.4), (0, 10.2, 64), cyan, "Neon", props={"Transparency": 0.5})
    b.building2("Lab", 68, 0, 22, 34, white, (50, 54, 66), doors={"W": [0], "N": [0], "S": [0]},
                windows1={"W": [-11, 11], "N": [5], "S": [-5]}, windows2={"W": [-12, -4, 4, 12], "E": [-8, 8], "N": [0], "S": [0]},
                stairs_at=("E",), material="Metal")
    b.box("Decor", "LabGlow", (22.4, 0.4, 34.4), (68, 10.2, 0), magenta, "Neon", props={"Transparency": 0.5})
    # Hangar (offen nach Norden mit zwei großen Toren) mit Shuttle
    hx0, hx1, hz0, hz1, hh = -22, 22, -84, -54, 18
    b.wall_line("Hangar", hx0, hx1, hz1, True, hh, wall, "Metal", openings=[(0, 8, 0, 8), (-14, 10, 0, 11), (14, 10, 0, 11)])
    b.wall_line("Hangar", hx0, hx1, hz0, True, hh, wall, "Metal")
    for x in (hx0, hx1):
        b.wall_line("Hangar", hz0 + 1.2, hz1 - 1.2, x, False, hh, wall, "Metal", openings=[(-69, 6, 0, 8)])
    b.box("Buildings", "HangarRoof", (hx1 - hx0, 1, hz1 - hz0), (0, hh + 0.5, (hz0 + hz1) / 2), (50, 54, 66), "Metal")
    b.box("Cover", "Shuttle", (8, 5, 16), (0, 3.4, -70), white, "Metal")
    b.box("Cover", "ShuttleWing", (20, 0.8, 6), (0, 2.6, -72), (180, 186, 200), "Metal")
    b.add("Decor", "ShuttleCockpit", (6, 4, 6), (0, 4, -61.5), (40, 60, 90), "Glass", props={"Shape": "Ball"})
    for x in (-2.5, 2.5):
        b.add("Decor", "ShuttleEngine", (2.4, 3, 3), (x, 3.4, -79), (60, 64, 76), "Metal", angles=(0, 90, 0),
              props={"Shape": "Cylinder"})
        b.add("Decor", "ShuttleFlame", (0.3, 2.4, 2.4), (x, 3.4, -80.4), cyan, "Neon", angles=(0, 90, 0),
              props={"Shape": "Cylinder"})
    for x, z in ((-16, -78), (16, -78), (-15, -62), (15, -62)):
        b.crate(x, z, s=4, color=(70, 76, 92))
    # Gewächshaus aus Glas mit Pflanzbeeten
    gx0, gx1, gz0, gz1, gh = -79, -57, -17, 17, 10
    for z in (gz0, gz1):
        b.wall_line("Greenhouse", gx0, gx1, z, True, gh, (170, 220, 230), "Glass", openings=[(-68, 5, 0, 7.5)])
    b.wall_line("Greenhouse", gz0 + 1.2, gz1 - 1.2, gx1, False, gh, (170, 220, 230), "Glass", openings=[(0, 6, 0, 8)])
    b.wall_line("Greenhouse", gz0 + 1.2, gz1 - 1.2, gx0, False, gh, (170, 220, 230), "Glass", openings=[(-8, 5, 0, 7.5)])
    b.box("Buildings", "GreenhouseRoof", (gx1 - gx0, 0.5, gz1 - gz0), ((gx0 + gx1) / 2, gh + 0.25, 0), (170, 220, 230),
          "Glass", props={"Transparency": 0.5})
    for z in (-10, 0, 10):
        b.box("Cover", "Planter", (14, 2.4, 3), (-68, 1.2, z), (80, 64, 50), "Wood")
        b.box("Decor", "Plants", (13, 1.2, 2.4), (-68, 3, z), (80, 200, 110), "Grass")

    # ---------- Decks in den Ecken ----------
    # NO: Landeplattform mit kleinem Schiff
    b.cylinder("Ground", "LandingPad", 34, 0.4, (62, 0.2, 62), (60, 66, 80), "Metal")
    b.cylinder("Ground", "LandingRing", 30, 0.45, (62, 0.22, 62), cyan, "Neon", props={"Transparency": 0.5})
    b.cylinder("Ground", "LandingCenter", 28.6, 0.5, (62, 0.25, 62), (60, 66, 80), "Metal")
    b.box("Cover", "Ship", (6, 4, 12), (62, 3, 62), (200, 205, 220), "Metal", angles=(0, 45, 0))
    b.box("Cover", "ShipWing", (16, 0.8, 4), (62, 2.2, 62), (150, 156, 170), "Metal", angles=(0, 45, 0))
    for a in range(0, 360, 60):
        b.box("Decor", "PadLight", (0.8, 0.6, 0.8), (62 + math.cos(math.radians(a)) * 16, 0.6, 62 + math.sin(math.radians(a)) * 16),
              magenta, "Neon")
    # NW: Antennenturm mit Aussichtsplattform (Höhe 8)
    tx, tz = -62, 62
    for dx in (-5, 5):
        for dz in (-5, 5):
            b.pillar(tx + dx, tz + dz, 8, s=1, color=(90, 96, 110))
    b.catwalk("TowerDeck", tx - 6, tx + 6, tz - 6, tz + 6, 8, rails=("N", "W"), rail_color=cyan)
    b.box("Cover", "TowerParapet", (12, 1.6, 0.6), (tx, 8.8, tz - 5.7), (70, 76, 90), "Metal")
    b.box("Cover", "TowerParapet", (0.6, 1.6, 12), (tx + 5.7, 8.8, tz), (70, 76, 90), "Metal")
    b.stairs("TowerStairs", tx - 8.5, tz - 16.4, 4, 8, "N", color=(90, 96, 110))
    b.box("Decor", "Antenna", (0.6, 18, 0.6), (tx - 4, 17, tz + 4), (200, 200, 210), "Metal")
    b.box("Decor", "AntennaTip", (1, 1, 1), (tx - 4, 26.5, tz + 4), (255, 60, 60), "Neon")
    # SO: Frachtbereich (Kisten, zwei Ebenen mit Rampe)
    for x, z, lvl in ((56, -56, 0), (66, -56, 0), (56, -66, 0), (66, -66, 1), (76, -66, 0), (66, -76, 0), (56, -76, 0)):
        b.box("Cover", "Cargo", (8, 8, 8), (x, 4 + lvl * 8, z), (70, 76, 92), "Metal")
        b.box("Decor", "CargoStripe", (8.2, 0.5, 8.2), (x, 6 + lvl * 8, z), magenta if (x + z) % 20 else cyan, "Neon")
    b.ramp("CargoRamp", 52, -61, 5, 10, 8, "W")
    # SW: Solarfarm und Satellitenschüssel
    for x in (-80, -64, -48):
        for z in (-50, -64, -78):
            b.solar_panel(x, z, along_x=True, length=12)
    b.cylinder("Buildings", "DishBase", 4, 6, (-86, 3, -88), (90, 96, 110), "Metal")
    b.add("Decor", "Dish", (1, 14, 14), (-86, 10, -88), white, "Metal", angles=(0, 45, 60),
          props={"Shape": "Cylinder", "CanCollide": False})

    # Kuppel-Pods am Außenring (brechen die langen Sichtlinien am Rand)
    for x, z in ((40, 76), (-40, 76), (40, -76), (-40, -76), (76, 40), (-76, 40), (76, -40), (-76, -40)):
        b.cylinder("Cover", "Pod", 7, 5, (x, 2.5, z), (90, 96, 112), "Metal")
        b.add("Decor", "PodDome", (7, 5, 7), (x, 5, z), (120, 200, 230), "Glass", props={"Shape": "Ball", "Transparency": 0.35})
        b.cylinder("Decor", "PodGlow", 7.2, 0.3, (x, 4.4, z), magenta, "Neon")
    b.sign("OrbitSignS", (26, 5, 0.4), (0, 15, -104), "ORBIT STATION", dark, magenta)

    # Energie-Barrieren als Deckung zwischen den Decks
    for x, z, ax in ((36, 36, True), (-36, 36, False), (36, -36, False), (-36, -36, True), (86, 30, False), (-86, -30, False),
                     (30, -90, True), (-30, 90, True)):
        b.half_wall(x, z, 8, along_x=ax, color=(70, 76, 90))
        size_g = (8, 0.3, 0.3) if ax else (0.3, 0.3, 8)
        b.box("Decor", "BarrierGlow", size_g, (x, 3.5, z), cyan, "Neon")

    # ---------- Spawns (16) ----------
    points = [(sx * 95, sz * 95) for sx in (-1, 1) for sz in (-1, 1)]
    points += [(0, 96), (0, -96), (96, 0), (-96, 0)]
    points += [(sx * 40, sz * 96) for sx in (-1, 1) for sz in (-1, 1)]
    points += [(sx * 96, sz * 40) for sx in (-1, 1) for sz in (-1, 1)]
    for x, z in points:
        b.spawn(x, z, yaw=face(x, z))
    b.sign("OrbitSign", (26, 5, 0.4), (0, 15, 104), "ORBIT STATION", dark, cyan, angles=(0, 180, 0))

    b.save("Orbit.model.json", "Orbit", atmosphere="Space")


# ---------- Gemeinsame Teile der Herrschaft-Maps (340 x 230, Rot im Westen, Blau im Osten) ----------

def team_base(b, sx, team_col, folder, tag, wall_col, roof_col, roof_mat="Metal", pad_col=(100, 102, 106)):
    """Überdachte Basis an der Schmalseite (x = sx * 138..170): Front mit drei Ausgängen, an den Seiten je ein
    Tor, 8 Spawns mit Blick zur Mitte, Deckung im Spawn."""
    b.box("Ground", "BasePad", (32, 0.2, 70), (sx * 154, 0.1, 0), pad_col, "Concrete")
    b.box("Buildings", "BaseRoof", (32, 1, 70), (sx * 154, 11.5, 0), roof_col, roof_mat)
    b.box("Decor", "BaseRoofEdge", (0.4, 0.4, 70), (sx * 138.2, 11, 0), team_col, "Neon")
    for z in (-34, -12, 12, 34):
        b.pillar(sx * 139, z, 11, s=1.6, color=wall_col)
    b.wall_line("BaseFront", -35, 35, sx * 138, False, 11, wall_col, "Concrete",
                openings=[(-23, 9, 0, 8), (0, 12, 0, 8), (23, 9, 0, 8)])
    for z in (-35.6, 35.6):
        b.wall_line("BaseSide", min(sx * 138, sx * 170), max(sx * 138, sx * 170), z, True, 11, wall_col, "Concrete",
                    openings=[(sx * 152, 10, 0, 8)])
    b.box("Decor", "BaseStrip", (0.3, 0.4, 70), (sx * (138 - 0.8), 8.6, 0), team_col, "Neon")
    b.sign("BaseSign" + tag, (14, 3, 0.4), (sx * 137.1, 13.6, 0), "TEAM " + tag.upper(), (28, 30, 34), team_col,
           angles=(0, 90 * sx, 0))
    for z in (-26, -9, 9, 26):
        for x in (sx * 160, sx * 148):
            b.spawn(x, z, yaw=face(x, z, 0, z), group=folder)
    for z in (-17, 17):
        b.crate(sx * 144, z, s=4, color=(110, 100, 80))


DOM_SCALE = 1.2  # Herrschaft-Maps 20 % größer (Fläche), Höhen bleiben


def sniper_tower(b, x, z, sx, color, accent, h=10):
    """Sniper-Turm am Basis-Ende einer Lane: überdachte Plattform auf h, Brüstung zur Mitte und zur Lane,
    Treppe von der Basis-Seite (Norden). Starke Sicht die Lane hinunter, aber von unten und von drüben angreifbar."""
    for dx in (-4, 4):
        for dz in (-4, 4):
            b.box("Buildings", "SniperLeg", (1, h + 6, 1), (x + dx, (h + 6) / 2, z + dz), color, "Metal")
    b.catwalk("SniperDeck", x - 4.5, x + 4.5, z - 4.5, z + 4.5, h, rails=(), color=color)
    b.box("Cover", "SniperParapet", (0.6, 1.6, 9), (x - sx * 4.2, h + 0.8, z), color, "Metal")
    b.box("Cover", "SniperParapet", (9, 1.6, 0.6), (x, h + 0.8, z - 4.2), color, "Metal")
    b.box("Cover", "SniperParapet", (3.5, 1.6, 0.6), (x - sx * 2.75, h + 0.8, z + 4.2), color, "Metal")
    b.box("Decor", "SniperStripe", (0.3, 0.3, 9.2), (x - sx * 4.5, h + 1.7, z), accent, "Neon")
    b.box("Buildings", "SniperRoof", (10, 0.6, 10), (x, h + 6.3, z), color, "Metal")
    b.stairs("SniperStairs", x + sx * 2.5, z + 17.6, 4, h, "S", color=color)


def flank_tunnel(b, sx, x_inner, x_outer, z_n, z_s, wall_col, roof_col, light_col, exits_n=(), exits_s=(), slits=(),
                 h=7, material="Concrete"):
    """Überdachter Flankengang (Rusher-Weg) von der Flagge zur Mitte: geschützt vor Snipern, Ausgänge zu den
    Seiten, schmale Schlitze zur Lane (Camper können rausschauen, man sieht aber auch rein)."""
    x0, x1 = sorted((sx * x_inner, sx * x_outer))
    for z, exits, side_slits in ((z_n, exits_n, ()), (z_s, exits_s, slits)):
        ops = [(sx * e, 6, 0, 6.5) for e in exits] + [(sx * e, 3, 3.4, 5) for e in side_slits]
        b.wall_line("FlankTunnel", x0, x1, z, True, h, wall_col, material, ops)
    b.box("Buildings", "FlankTunnelRoof", (x1 - x0, 1, abs(z_n - z_s) + 1.2), ((x0 + x1) / 2, h + 0.5, (z_n + z_s) / 2),
          roof_col, material)
    b.box("Decor", "FlankTunnelLight", (x1 - x0 - 2, 0.2, 0.8), ((x0 + x1) / 2, h - 0.1, (z_n + z_s) / 2), light_col, "Neon")


def window_climb(b, x, z, color=(110, 100, 80)):
    """Kisten an einer Hallenwand bis unter ein Fenster (Rusher springen über die Kisten in die Halle)."""
    b.crate(x, z, s=4, color=color)
    b.crate(x, z, s=4, y=4, color=color)
    b.crate(x + 4.2, z, s=4, color=color)


def flag_marker(b, name, x, color, pole_side=1):
    """Flaggen-Zone (Scheibe, Radius 9) und Mast mit Tuch und Buchstabe neben der Zone."""
    b.add("Objective", "Flag" + name, (0.3, 18, 18), (x, 0.25, 0), (230, 230, 235), "Neon",
          angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.5, "CanCollide": False})
    px = x + pole_side * 10.5
    b.box("Decor", "FlagPole" + name, (0.6, 14, 0.6), (px, 7, 0), (60, 60, 65), "Metal")
    b.box("Decor", "FlagCloth" + name, (0.2, 2.6, 4), (px, 12.5, 2.2), color, "Fabric")
    b.sign("FlagSign" + name, (4, 4, 0.4), (px, 16.5, 0), name, (25, 25, 30), (255, 255, 255),
           angles=(0, -90 * pole_side, 0))


# ---------- Herrschaft: "Lagune" (340 x 230), Rogue-Company-Stil ----------

def build_lagune():
    """Lagune: Hotel-Insel im Meer. Mitte: Hotel mit offenem Innenhof (Flagge B) und umlaufender Galerie im
    ersten Stock (Treppen in zwei Ecken, Fenster nach außen). A und C auf Pool-Terrassen (zwei Becken links und
    rechts der Flagge, Liegen, Schirme, Cabana), dazwischen zweistöckige Villen. Norden: Strand mit
    Rettungstürmen (erhöhte Plattform), Booten, Beachvolleyball, Felsen. Süden: Garten mit Hecken,
    Tennisplatz und Pavillons. Basen überdacht (Stroh), spiegelgleich."""
    b = Builder(LAGUNE_ORIGIN, scale=DOM_SCALE)
    rng = random.Random(77)
    SX, SZ = 340, 230
    paving, sand, grass = (232, 224, 208), (238, 218, 168), (110, 175, 85)
    stucco, terracotta, wood = (246, 242, 234), (200, 110, 70), (150, 110, 70)
    pool, teal, pink = (60, 190, 220), (60, 190, 180), (240, 120, 150)
    b.ground(SX + 10, SZ + 10, paving, "Concrete")
    b.border(SX, SZ, 3.5, (200, 190, 170), "Sandstone", barrier=140)
    # Meer rund um die Insel (Deko) mit Sandstrand am Rand
    for x, z, w, d in ((0, 425, 1200, 600), (0, -425, 1200, 600), (475, 0, 600, 250), (-475, 0, 600, 250)):
        b.box("Decor", "Ocean", (w, 1, d), (x, -0.7, z), (40, 160, 200), "Glass",
              props={"Transparency": 0.15, "CanCollide": False, "CanQuery": False, "CastShadow": False})
    b.box("Ground", "Beach", (SX, 0.08, 80), (0, 0.04, 75), sand, "Sand")
    b.box("Ground", "Garden", (SX - 80, 0.08, 80), (0, 0.04, -75), grass, "Grass")
    b.box("Ground", "Shallows", (SX, 0.06, 10), (0, 0.06, 110), (90, 200, 220), "Glass", props={"Transparency": 0.2})

    for sx, team_col, folder, tag in ((-1, (210, 80, 70), "SpawnsA", "Rot"), (1, (60, 120, 210), "SpawnsB", "Blau")):
        team_base(b, sx, team_col, folder, tag, stucco, (170, 130, 70), "Wood", pad_col=(222, 212, 192))
        # Leitwände vor der Basis als Blumenkübel
        for z in (-18, 0, 18):
            b.box("Cover", "Planter", (2, 2.8, 7), (sx * 126, 1.4, z), terracotta, "Brick")
            b.box("Decor", "Flowers", (1.8, 1, 6.6), (sx * 126, 3.2, z), pink, "Grass")

        # ---------- Pool-Terrasse mit Flagge A / C ----------
        fx = sx * 95
        b.box("Ground", "PoolDeck", (42, 0.15, 50), (fx, 0.08, 0), (214, 196, 160), "WoodPlanks")
        for dz in (-1, 1):
            pz = dz * 17
            b.box("Ground", "PoolWater", (24, 0.1, 7), (fx, 0.2, pz), pool, "Glass", props={"Transparency": 0.1})
            for wz in (pz - 3.9, pz + 3.9):
                b.box("Cover", "PoolRim", (25.6, 1.3, 0.8), (fx, 0.65, wz), stucco, "Concrete")
            for wx in (fx - 12.4, fx + 12.4):
                b.box("Cover", "PoolRim", (0.8, 1.3, 7), (wx, 0.65, pz), stucco, "Concrete")
            # Liegen und Schirme
            for k in (-8, 0, 8):
                b.box("Cover", "Lounger", (2.2, 0.9, 5), (fx + k, 0.45, dz * 25), (250, 250, 250), "SmoothPlastic")
            for ux in (-14, 14):
                b.box("Decor", "UmbrellaPole", (0.3, 6, 0.3), (fx + ux, 3, dz * 24), (240, 240, 240), "Metal")
                b.add("Decor", "Umbrella", (0.4, 7, 7), (fx + ux, 6.2, dz * 24), teal if ux > 0 else pink, "Fabric",
                      angles=(0, 0, 90), props={"Shape": "Cylinder"})
        # Cabana an der Basis-Seite der Terrasse (Dach, Bar-Theke als Deckung)
        cx = fx + sx * 16
        for dz in (-5, 5):
            for dx in (-4, 4):
                b.box("Decor", "CabanaPost", (0.5, 7, 0.5), (cx + dx, 3.5, dz), wood, "Wood")
        b.box("Decor", "CabanaRoof", (10, 0.6, 12), (cx, 7.2, 0), (190, 160, 100), "Grass")
        b.box("Cover", "BarCounter", (2, 3.4, 9), (cx - sx * 2.5, 1.7, 0), wood, "WoodPlanks")
        flag_marker(b, "A" if sx < 0 else "C", fx, (255, 120, 120) if sx < 0 else (120, 160, 255), pole_side=-sx)
        b.palm(fx - sx * 20, 22, h=15, rng=rng)
        b.palm(fx - sx * 20, -22, h=14, rng=rng)

        # ---------- Villa zwischen Terrasse und Hotel ----------
        vx = sx * 56
        b.building2("Villa" + tag, vx, 0, 22, 28, stucco, terracotta,
                    doors={"E": [-6, 6], "W": [-6, 6], "N": [0], "S": [0]}, windows1={"E": [0], "W": [0]},
                    windows2={"E": [-8, 0, 8], "W": [-8, 0, 8], "N": [-5, 5], "S": [-5, 5]}, stairs_at=("N",),
                    material="Concrete")
        b.box("Decor", "VillaShutters", (22.3, 0.5, 28.3), (vx, 10.2, 0), teal if sx > 0 else pink, "SmoothPlastic")
        for dz in (-1, 1):
            b.box("Cover", "Hedge", (8, 3.2, 2), (sx * 38, 1.6, dz * 20), (70, 130, 60), "Grass")
            b.crate(sx * 72, dz * 19, s=3.4, color=wood)

        # ---------- Norden: Strand ----------
        lx = sx * 62
        for dx in (-3, 3):
            for dz in (-3, 3):
                b.box("Buildings", "LifeguardLeg", (0.6, 7, 0.6), (lx + dx, 3.5, 72 + dz), (240, 240, 240), "Wood")
        b.catwalk("LifeguardDeck", lx - 3.6, lx + 3.6, 68.4, 75.6, 7, rails=("N", "E", "W"), color=(220, 80, 70),
                  rail_color=(240, 240, 240))
        b.box("Cover", "LifeguardWall", (7.2, 1.6, 0.5), (lx, 7.8, 68.6), (220, 80, 70), "Wood")
        b.box("Decor", "LifeguardRoof", (8, 0.4, 8), (lx, 11.5, 72), (240, 240, 240), "Fabric")
        for dx in (-3.4, 3.4):
            b.box("Decor", "LifeguardRoofPost", (0.3, 4.5, 0.3), (lx + dx, 9.3, 75.4), (240, 240, 240), "Wood")
        b.stairs("LifeguardStairs", lx, 60.9, 3, 7, "N", color=(240, 240, 240))
        for x, z, ang in ((sx * 110, 88, 30), (sx * 30, 96, -20)):
            b.box("Cover", "Boat", (12, 3, 4.4), (x, 1.5, z), (245, 245, 245), "SmoothPlastic", angles=(0, ang, 0))
            b.box("Decor", "BoatStripe", (12.2, 0.6, 4.6), (x, 2.4, z), teal, "SmoothPlastic", angles=(0, ang, 0))
        for x, z in ((sx * 88, 54), (sx * 130, 70), (sx * 40, 60), (sx * 100, 104)):
            b.palm(x, z, h=rng.uniform(12, 16), rng=rng)
        b.rock(sx * 80, 78, rng)
        b.rock(sx * 140, 96, rng)
        for x in (sx * 20, sx * 44):
            b.box("Cover", "Cabana", (6, 3.2, 3), (x, 1.6, 44), (250, 250, 250), "Fabric")
            b.add("Decor", "BeachUmbrella", (0.4, 6, 6), (x, 6, 47), pink if sx < 0 else teal, "Fabric", angles=(0, 0, 90),
                  props={"Shape": "Cylinder"})
            b.box("Decor", "BeachUmbrellaPole", (0.3, 6, 0.3), (x, 3, 47), (240, 240, 240), "Metal")

        # ---------- Süden: Garten ----------
        for x, z, ax, length in ((40, -44, True, 18), (78, -52, False, 14), (112, -46, True, 16), (64, -80, True, 20),
                                 (102, -88, False, 16), (30, -100, True, 14), (130, -74, False, 18)):
            size_h = (length, 4.4, 2.4) if ax else (2.4, 4.4, length)
            b.box("Cover", "Hedge", size_h, (sx * x, 2.2, z), (60, 125, 55), "Grass")
        gx, gz = sx * 60, -66
        for k in range(6):
            a = math.radians(k * 60)
            b.box("Decor", "GazeboPost", (0.5, 7, 0.5), (gx + math.cos(a) * 5, 3.5, gz + math.sin(a) * 5), stucco, "Concrete")
        b.add("Decor", "GazeboRoof", (0.6, 12, 12), (gx, 7.2, gz), terracotta, "Slate", angles=(0, 0, 90),
              props={"Shape": "Cylinder"})
        b.half_wall(gx, gz - 4.6, 6, along_x=True, color=stucco)
        b.cylinder("Cover", "Fountain", 7, 2.2, (sx * 120, 1.1, -30), stucco, "Concrete")
        b.cylinder("Decor", "FountainWater", 6, 0.3, (sx * 120, 2.1, -30), pool, "Glass", props={"Transparency": 0.2})
        b.building2("GardenVilla" + tag, sx * 118, -96, 26, 18, (240, 220, 200), terracotta,
                    doors={"N": [-6, 6], "E": [0], "W": [0]}, windows1={"N": [0]}, windows2={"N": [-8, 0, 8], "E": [0], "W": [0]},
                    stairs_at=("S",))
        b.building2("BeachVilla" + tag, sx * 118, 92, 26, 18, (230, 240, 245), (70, 140, 170),
                    doors={"S": [-6, 6], "E": [0], "W": [0]}, windows1={"S": [0]}, windows2={"S": [-8, 0, 8], "E": [0], "W": [0]},
                    stairs_at=("N",))

    # ---------- Mitte: Hotel mit offenem Innenhof (Flagge B) ----------
    ox, oz, ix, iz, H1, H2 = 34, 26, 20, 13, 9.5, 17.5
    for z, side in ((oz, 1), (-oz, -1)):
        # obere Tür (Rusher-Weg über die Außentreppe) im Norden östlich, im Süden westlich (punktsymmetrisch)
        b.wall_line("Hotel", -ox, ox, z, True, H2, stucco, "Concrete",
                    openings=[(-10, 6, 0, 7.5), (10, 6, 0, 7.5), (-25, 4, 3, 6.2), (25, 4, 3, 6.2),
                              (-13, 4, 11.5, 14.5), (0, 4, 11.5, 14.5), (13, 4, 11.5, 14.5),
                              (side * 30.5, 4, H1, H1 + 6.5), (-side * 26, 4, 11.5, 14.5)])
        b.stairs("HotelOuterStairs", side * 16, z + side * 2.6, 4, H1, "E" if side > 0 else "W", color=(200, 170, 130))
    for x in (ox, -ox):
        b.wall_line("Hotel", -oz + 1.2, oz - 1.2, x, False, H2, stucco, "Concrete",
                    openings=[(0, 8, 0, 8), (-14, 4, 3, 6.2), (14, 4, 3, 6.2), (-12, 4, 11.5, 14.5), (12, 4, 11.5, 14.5)])
    holes = [(-ix, ix, -iz, iz), (-30, -16, 20.5, 24.5), (16, 30, -24.5, -20.5)]
    b.slab("HotelFloor2", -ox + 0.6, ox - 0.6, -oz + 0.6, oz - 0.6, H1, (200, 170, 130), holes, "WoodPlanks")
    b.slab("HotelRoof", -ox, ox, -oz, oz, H2 + 1, terracotta, [(-ix, ix, -iz, iz)], "Slate")
    b.stairs("HotelStairs", -30, 22.5, 4, H1, "E", color=(200, 170, 130))
    b.stairs("HotelStairs", 30, -22.5, 4, H1, "W", color=(200, 170, 130))
    # Säulengang um den Hof und Geländer der Galerie
    for x in (-ix, -10, 0, 10, ix):
        for z in (-iz, iz):
            b.pillar(x, z, H1 - 1, s=1.2, color=stucco, material="Concrete")
    for z in (-6.5, 0, 6.5):
        for x in (-ix, ix):
            b.pillar(x, z, H1 - 1, s=1.2, color=stucco, material="Concrete")
    for z in (iz, -iz):
        b.box("Cover", "GalleryRail", (ix * 2, 1.4, 0.4), (0, H1 + 0.7, z), (250, 250, 250), "Concrete")
    for x in (ix, -ix):
        b.box("Cover", "GalleryRail", (0.4, 1.4, iz * 2), (x, H1 + 0.7, 0), (250, 250, 250), "Concrete")
    # Hof: Brunnen-Becken außerhalb der Zone, Palmen in Kübeln, Liegen als Deckung
    for x, z in ((-14, 8), (14, -8)):
        b.cylinder("Cover", "Planter", 3, 2.4, (x, 1.2, z), terracotta, "Brick")
        b.palm(x, z, h=11, lean=2, rng=rng)
    for x, z in ((-11, -9), (11, 9)):
        b.box("Cover", "Lounger", (5, 0.9, 2.2), (x, 0.45, z), (250, 250, 250), "SmoothPlastic")
    # Galerie oben: Möbel als Deckung
    for x, z, ax in ((-26, 0, False), (26, 0, False), (0, 19, True), (0, -19, True)):
        b.box("Cover", "Sofa", (6, 2, 2.2) if ax else (2.2, 2, 6), (x, H1 + 1, z), teal, "Fabric")
    b.sign("HotelSign", (26, 4, 0.4), (0, 21, oz + 0.9), "HOTEL LAGUNA", (250, 250, 250), (220, 90, 120), angles=(0, 180, 0))
    b.sign("HotelSignS", (26, 4, 0.4), (0, 21, -oz - 0.9), "HOTEL LAGUNA", (250, 250, 250), (60, 170, 190))
    b.add("Objective", "FlagB", (0.3, 18, 18), (0, 0.25, 0), (230, 230, 235), "Neon",
          angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.5, "CanCollide": False})
    b.box("Decor", "FlagSignBCable", (0.2, 3, 0.2), (0, 19.5, 0.2), (30, 30, 30), "Metal")
    b.sign("FlagSignB", (5, 5, 0.4), (0, 15.5, 0), "B", (25, 25, 30), (255, 255, 255))
    b.sign("FlagSignB2", (5, 5, 0.4), (0, 15.5, 0.45), "B", (25, 25, 30), (255, 255, 255), angles=(0, 180, 0))

    # ---------- Spielweisen: Sniper-Türme (Garten-Lane), Pergola-Gang (Rusher) ----------
    for sx in (-1, 1):
        sniper_tower(b, sx * 136, -64, sx, (240, 236, 226), pink if sx < 0 else teal)
        flank_tunnel(b, sx, 36, 112, -28, -36, (90, 150, 80), wood, (255, 220, 160), exits_n=(56, 96), exits_s=(76,),
                     slits=(62, 90, 104), material="Grass")

    # Strand Mitte: Beachvolleyball, Tennisplatz im Garten
    b.box("Decor", "VolleyNet", (0.2, 2, 18), (0, 4.6, 70), (250, 250, 250), "Fabric", props={"Transparency": 0.4})
    for z in (61, 79):
        b.box("Decor", "VolleyPost", (0.4, 6, 0.4), (0, 3, z), (240, 240, 240), "Metal")
    for x in (-12, 12):
        b.box("Cover", "SandBags", (6, 2.4, 2), (x, 1.2, 64 if x < 0 else 76), (200, 180, 140), "Fabric")
    b.box("Ground", "TennisCourt", (30, 0.1, 22), (0, 0.1, -76), (70, 120, 170), "SmoothPlastic")
    b.box("Decor", "TennisNet", (0.2, 1.4, 22), (0, 0.8, -76), (250, 250, 250), "Fabric", props={"Transparency": 0.3})
    for z in (-64, -88):
        b.box("Cover", "CourtFence", (30, 2.6, 0.4), (0, 1.3, z), (60, 90, 70), "Metal")

    b.save("Lagune.model.json", "Lagune", atmosphere="Tropical")


# ---------- Herrschaft: "Mondbasis" (340 x 230), Weltraum ----------

def build_mondbasis():
    """Mondbasis unter Sternenhimmel, Erde am Horizont. Mitte: Kuppelhalle (Flagge B) mit Glasdach, Neon,
    Laufstegen an den Längswänden und Generatoren als Deckung. A: Bohrturm über dem Abbaufeld (Plattform auf 7,
    Erzwagen, Gesteinshaufen). C: Radarstation mit großer Schüssel und Technikschränken. Zwischen den Flaggen
    und der Halle je ein Wohnmodul (zweistöckig). Norden: Kraterfeld mit Rovern und Felsen. Süden: Solarfarm
    (Reihen schräger Paneele) mit Wartungshütte. Basen: Landeplätze mit Rakete, überdacht. Spiegelgleich."""
    b = Builder(MONDBASIS_ORIGIN, scale=DOM_SCALE)
    rng = random.Random(91)
    SX, SZ = 340, 230
    regolith, rock, hull = (118, 118, 124), (92, 92, 98), (222, 226, 234)
    cyan, orange, magenta, dark = (70, 220, 255), (255, 150, 60), (230, 80, 255), (30, 32, 40)
    b.ground(SX + 10, SZ + 10, regolith, "Slate")
    b.border(SX, SZ, 6, rock, "Rock", barrier=140)
    # Erde und Sterne am Himmel (Deko)
    b.add("Decor", "Earth", (120, 120, 120), (260, 200, 320), (70, 120, 200), "SmoothPlastic",
          props={"Shape": "Ball", "CanCollide": False, "CanQuery": False, "CastShadow": False})
    b.add("Decor", "EarthClouds", (122, 122, 122), (260, 200, 320), (240, 245, 255), "SmoothPlastic",
          props={"Shape": "Ball", "CanCollide": False, "CanQuery": False, "CastShadow": False, "Transparency": 0.7})
    # Felsenkranz hinter der Grenze
    for k in range(40):
        a = 2 * math.pi * k / 40
        r = 240 + rng.uniform(-15, 25)
        b.box("Decor", "Ridge", (rng.uniform(30, 60), rng.uniform(15, 40), rng.uniform(20, 40)),
              (math.cos(a) * r * 1.0, 6, math.sin(a) * r * 0.75), rock, "Rock",
              angles=(0, rng.uniform(0, 360), rng.uniform(-8, 8)), props={"CanCollide": False, "CastShadow": False})

    for sx, team_col, folder, tag in ((-1, (230, 80, 70), "SpawnsA", "Rot"), (1, (70, 130, 240), "SpawnsB", "Blau")):
        team_base(b, sx, team_col, folder, tag, hull, (70, 76, 90), "Metal", pad_col=(80, 84, 92))
        # Rakete hinter der Basis (Landmarke)
        b.cylinder("Decor", "Rocket", 8, 40, (sx * 158, 31.5, 96), hull, "Metal")
        b.add("Decor", "RocketNose", (8, 10, 8), (sx * 158, 52, 96), team_col, "Metal", props={"Shape": "Ball"})
        b.cylinder("Decor", "RocketBand", 8.4, 1.4, (sx * 158, 24, 96), team_col, "Neon")
        for d in (-1, 1):
            b.box("Decor", "RocketFin", (0.8, 10, 6), (sx * 158 + d * 4.5, 15, 96), team_col, "Metal")
        b.cylinder("Buildings", "LaunchPad", 16, 11.5, (sx * 158, 5.75, 96), (70, 74, 84), "Metal")
        # Sniper: Treppe auf die Startrampe (Ring um die Rakete, Blick über das Kraterfeld)
        b.stairs("LaunchStairs", sx * 158, 72.4, 4, 11.5, "N", color=(80, 84, 94))
        for z in (-18, 0, 18):
            b.box("Cover", "Barricade", (2, 3.2, 7), (sx * 126, 1.6, z), (90, 94, 104), "Metal")
            b.box("Decor", "BarricadeGlow", (2.1, 0.3, 7.1), (sx * 126, 3.2, z), team_col, "Neon")

        # ---------- A: Bohrturm (Rot) / C: Radarstation (Blau) ----------
        fx = sx * 95
        b.box("Ground", "SitePad", (40, 0.15, 46), (fx, 0.08, 0), (96, 98, 106), "DiamondPlate")
        if sx < 0:
            # Bohrturm: vier Beine, Plattform auf 7 rund um die Zone (Mitte offen), Bohrer in der Mitte
            for dx in (-11, 11):
                for dz in (-11, 11):
                    b.box("Buildings", "RigLeg", (1.4, 22, 1.4), (fx + dx, 11, dz), orange, "Metal")
            for x0, x1, z0, z1, rails in ((fx - 12, fx + 12, 9, 13, ("N",)), (fx - 12, fx + 12, -13, -9, ("S",))):
                b.catwalk("RigDeck", x0, x1, z0, z1, 7, rails=rails, rail_color=orange)
            b.stairs("RigStairs", fx - 12 - 9.4, 11, 4, 7, "E", color=(80, 84, 94))
            b.stairs("RigStairs", fx + 12 + 9.4, -11, 4, 7, "W", color=(80, 84, 94))
            b.box("Buildings", "RigTop", (24, 1.4, 24), (fx, 22.7, 0), orange, "Metal")
            b.cylinder("Decor", "Drill", 2.4, 14, (fx, 15, 0), (60, 60, 66), "Metal")
            for x, z in ((fx + 16, 16), (fx - 16, -16)):
                b.box("Cover", "OreCart", (5, 3, 3.4), (x, 1.9, z), (110, 90, 70), "Metal")
                b.add("Cover", "Ore", (4, 2, 3), (x, 3.6, z), (200, 120, 60), "Slate", props={"Shape": "Ball"})
            for x, z in ((fx + 17, -15), (fx - 17, 15)):
                b.add("Cover", "RockPile", (8, 4, 8), (x, 1.4, z), rock, "Rock", props={"Shape": "Ball"})
        else:
            # Radarstation: Schüssel auf Sockel (Deckung), Technikschränke
            b.cylinder("Cover", "RadarBase", 7, 6, (fx + 14, 3, 14), (80, 84, 96), "Metal")
            b.add("Decor", "RadarDish", (1, 18, 18), (fx + 14, 12, 14), hull, "Metal", angles=(0, -40, 55),
                  props={"Shape": "Cylinder", "CanCollide": False})
            b.cylinder("Cover", "RadarBase", 7, 6, (fx - 14, 3, -14), (80, 84, 96), "Metal")
            b.add("Decor", "RadarDish", (1, 18, 18), (fx - 14, 12, -14), hull, "Metal", angles=(0, 140, 55),
                  props={"Shape": "Cylinder", "CanCollide": False})
            for x, z in ((fx + 15, -14), (fx - 15, 14), (fx, 15), (fx, -15)):
                b.box("Cover", "ServerRack", (5, 4.4, 2.4), (x, 2.2, z), dark, "Metal")
                b.box("Decor", "RackGlow", (5.1, 0.3, 2.5), (x, 3.6, z), cyan, "Neon")
            # Plattform auf 7 auf der Nordseite (wie der Bohrturm: gleiche Höhe, fair)
            b.catwalk("RadarDeck", fx - 12, fx + 12, 9, 13, 7, rails=("N",), rail_color=cyan)
            b.catwalk("RadarDeck", fx - 12, fx + 12, -13, -9, 7, rails=("S",), rail_color=cyan)
            for dx in (-11, 11):
                for dz in (-11, 11):
                    b.box("Buildings", "DeckLeg", (1, 7, 1), (fx + dx, 3.5, dz), (90, 94, 104), "Metal")
            b.stairs("RadarStairs", fx + 12 + 9.4, 11, 4, 7, "W", color=(80, 84, 94))
            b.stairs("RadarStairs", fx - 12 - 9.4, -11, 4, 7, "E", color=(80, 84, 94))
        b.add("Objective", "Flag" + ("A" if sx < 0 else "C"), (0.3, 18, 18), (fx, 0.25, 0), (230, 230, 235), "Neon",
              angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.5, "CanCollide": False})
        b.sign("FlagSign" + ("A" if sx < 0 else "C"), (5, 5, 0.4), (fx, 18, -0.2), "A" if sx < 0 else "C", dark, (255, 255, 255),
               angles=(0, 180, 0))
        b.sign("FlagSign2" + ("A" if sx < 0 else "C"), (5, 5, 0.4), (fx, 18, 0.25), "A" if sx < 0 else "C", dark, (255, 255, 255))

        # ---------- Wohnmodul zwischen Flagge und Halle ----------
        mx = sx * 56
        b.building2("HabModule" + tag, mx, 0, 22, 30, hull, (70, 76, 90),
                    doors={"E": [-7, 7], "W": [-7, 7], "N": [0], "S": [0]}, windows1={"E": [0], "W": [0]},
                    windows2={"E": [-9, 0, 9], "W": [-9, 0, 9], "N": [-5, 5], "S": [-5, 5]}, stairs_at=("N",),
                    material="Metal")
        b.box("Decor", "HabGlow", (22.4, 0.4, 30.4), (mx, 10.2, 0), team_col, "Neon", props={"Transparency": 0.4})
        for dz in (-1, 1):
            b.box("Cover", "SupplyCrate", (4, 4, 4), (sx * 39, 2, dz * 21), (80, 84, 96), "Metal")
            b.box("Cover", "SupplyCrate", (4, 4, 4), (sx * 72, 2, dz * 21), (80, 84, 96), "Metal")

        # ---------- Norden: Kraterfeld mit Rovern ----------
        for x, z, r in ((sx * 40, 62, 11), (sx * 96, 74, 14), (sx * 128, 50, 9), (sx * 60, 98, 8)):
            b.crater(f"Crater{sx}{x}", x, z, r)
        for x, z, ang in ((sx * 70, 46, 20), (sx * 20, 92, -30)):
            b.box("Cover", "Rover", (9, 3.6, 5), (x, 2.4, z), hull, "Metal", angles=(0, ang, 0))
            b.box("Decor", "RoverCab", (4, 2, 4.6), (x, 5, z), (60, 90, 130), "Glass", angles=(0, ang, 0))
            for dx in (-3, 3):
                for dz in (-2.8, 2.8):
                    b.add("Decor", "RoverWheel", (1, 2, 2), (x + dx, 1, z + dz), dark, "Rubber", angles=(0, 90 + ang, 0),
                          props={"Shape": "Cylinder"})
        for _ in range(6):
            b.rock(sx * rng.uniform(20, 140), rng.uniform(40, 108), rng)

        # ---------- Süden: Solarfarm mit Wartungshütte ----------
        for x in (24, 44, 64, 84, 104, 124):
            for z in (-48, -66, -84, -102):
                if (x, z) not in ((84, -84), (104, -84)):
                    b.solar_panel(sx * x, z, along_x=False, length=12)
        b.flat_house("Maintenance" + tag, sx * 94, -84, 18, 12, 8, (90, 96, 108),
                     doors={"N": [0], "S": [0], "E": [0], "W": [0]}, windows={"N": [-5, 5], "S": [-5, 5]},
                     parapet=("N", "S"), trim=cyan)

    # ---------- Mitte: Kuppelhalle mit Flagge B ----------
    hx, hz, hh = 32, 22, 16
    for z, name in ((hz, "DomeN"), (-hz, "DomeS")):
        b.wall_line(name, -hx, hx, z, True, hh, hull, "Metal",
                    openings=[(-12, 7, 0, 8), (12, 7, 0, 8), (-24, 5, 9.5, 12.5), (0, 6, 9.5, 15), (24, 5, 9.5, 12.5),
                              (-4, 3, 3, 6), (4, 3, 3, 6)])
        window_climb(b, -2.1, z + (2.6 if z > 0 else -2.6), color=(80, 84, 96))
    for x, name in ((-hx, "DomeW"), (hx, "DomeE")):
        b.wall_line(name, -hz + 1.2, hz - 1.2, x, False, hh, hull, "Metal",
                    openings=[(-11, 7, 0, 8), (11, 7, 0, 8), (0, 4, 3, 6.5)])
    b.box("Buildings", "DomeGlass", (hx * 2, 0.6, hz * 2), (0, hh + 0.3, 0), (140, 200, 240), "Glass",
          props={"Transparency": 0.55})
    for x in range(-24, 25, 12):
        b.box("Decor", "DomeRib", (0.8, 0.8, hz * 2), (x, hh + 0.8, 0), (90, 96, 110), "Metal")
    b.box("Ground", "DomeFloor", (hx * 2 - 2, 0.12, hz * 2 - 2), (0, 0.06, 0), (60, 64, 76), "DiamondPlate")
    for z in (hz + 0.7, -hz - 0.7):
        b.box("Decor", "DomeStripe", (hx * 2, 0.5, 0.3), (0, 14.5, z), cyan, "Neon")
    for dz in (-1, 1):
        z0, z1 = (15, 21) if dz > 0 else (-21, -15)
        b.catwalk("DomeCatwalk", -21, 21, z0, z1, 7, rails=("S" if dz > 0 else "N",), rail_color=cyan)
        b.stairs("DomeStairs", -30.4, dz * 18, 4, 7, "E", color=(80, 84, 94))
        b.stairs("DomeStairs", 30.4, dz * 18, 4, 7, "W", color=(80, 84, 94))
    for sx in (-1, 1):
        b.box("Buildings", "GeneratorBase", (12, 1.2, 9), (sx * 21, 0.6, 0), dark, "Metal")
        b.box("Cover", "Generator", (9, 7, 7), (sx * 21, 4.7, 0), (90, 96, 110), "Metal")
        b.cylinder("Decor", "GeneratorCore", 3, 7.2, (sx * 21, 4.7, 0), magenta, "Neon")
    for x, z in ((-7, 12), (7, -12)):
        b.box("Cover", "SupplyCrate", (4, 4, 4), (x, 2, z), (80, 84, 96), "Metal")
    for x, z in ((0, 12.5), (0, -12.5)):
        b.half_wall(x, z, 6, along_x=True, color=(110, 116, 130))
    b.add("Objective", "FlagB", (0.3, 18, 18), (0, 0.25, 0), (230, 230, 235), "Neon",
          angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.5, "CanCollide": False})
    b.box("Decor", "FlagSignBCable", (0.2, 2.4, 0.2), (0, 15.8, 0.2), (30, 30, 30), "Metal")
    b.sign("FlagSignB", (5, 5, 0.4), (0, 12.5, 0), "B", dark, (255, 255, 255))
    b.sign("FlagSignB2", (5, 5, 0.4), (0, 12.5, 0.45), "B", dark, (255, 255, 255), angles=(0, 180, 0))
    b.sign("DomeSign", (24, 4, 0.4), (0, 19, hz + 0.9), "MONDBASIS", dark, cyan, angles=(0, 180, 0))
    b.sign("DomeSignS", (24, 4, 0.4), (0, 19, -hz - 0.9), "MONDBASIS", dark, magenta)
    # ---------- Spielweisen: Sniper-Türme (Solar-Lane), Verbindungsröhren (Rusher) ----------
    for sx in (-1, 1):
        sniper_tower(b, sx * 136, -64, sx, (90, 96, 110), cyan)
        flank_tunnel(b, sx, 36, 118, -28, -36, hull, (70, 76, 90), cyan, exits_n=(56, 96), exits_s=(76,),
                     slits=(62, 90, 108), material="Metal")

    # Mitte Nord/Süd: Röhren-Verbindungen als Deckung über der Freifläche
    for z in (44, -44):
        b.add("Cover", "Tube", (40, 6, 6), (0, 3, z), hull, "Metal", props={"Shape": "Cylinder"})
        b.box("Decor", "TubeGlow", (40.2, 0.3, 0.3), (0, 6, z), cyan, "Neon")
    b.save("Mondbasis.model.json", "Mondbasis", atmosphere="Space")


# ---------- Herrschaft / Team Deathmatch: "Kraftwerk" (340 x 230) ----------

def face(x, z, tx=0.0, tz=0.0):
    """Drehung (Grad), mit der ein Spawn bei (x, z) zum Punkt (tx, tz) schaut."""
    return math.degrees(math.atan2(x - tx, z - tz))


def build_kraftwerk(origin, filename, flags=True):
    """Kraftwerk für Herrschaft (mit Flaggen A/B/C) und Team Deathmatch (eigene Kopie ohne Flaggen).
    Team Rot startet im Westen (-x), Blau im Osten (+x), spiegelgleich. Drei Wege:
      Norden  – breite Straße und dahinter der Hof der Kühltürme mit Leitstand und Förderband (weite Sicht)
      Mitte   – Pumpenhöfe mit Flagge A/C vor den Basen, Pumpenhäuser, Turbinenhalle mit Flagge B
                (Laufstege an den Längswänden, Fenster nach außen: enge Kämpfe auf zwei Ebenen)
      Süden   – Straße und Containerhof mit begehbaren Containern und Portalkran (zwei Ebenen)
    Basen überdacht mit drei Ausgängen nach vorn und je einem Tor zu Nord- und Südstraße."""
    b = Builder(origin, scale=DOM_SCALE)
    rng = random.Random(41)
    SX, SZ = 340, 230
    concrete, asphalt, steel, dark = (118, 120, 124), (56, 58, 62), (84, 88, 96), (44, 47, 53)
    brick, hall_col, roof_col = (128, 88, 70), (146, 150, 156), (66, 70, 76)
    warn, white = (220, 170, 40), (225, 228, 232)
    b.ground(SX + 10, SZ + 10, concrete, "Concrete")
    b.border(SX, SZ, 16, (92, 94, 100), "Concrete", barrier=140)

    # Straßen (Nord/Süd) mit Mittellinie, Wege von den Basen
    for z in (44, -44):
        b.box("Ground", "Road", (276, 0.1, 36), (0, 0.05, z), asphalt, "Asphalt")
        for x in range(-124, 125, 16):
            b.box("Ground", "RoadLine", (8, 0.05, 0.5), (x, 0.12, z), white, "SmoothPlastic")
    # Lampen an den Straßen
    for sx in (-1, 1):
        for x in (40, 80, 120):
            for z in (25.5, -25.5):
                b.box("Decor", "LampPost", (0.5, 10, 0.5), (sx * x, 5, z), dark, "Metal")
                b.add("Decor", "Lamp", (2.4, 0.4, 1), (sx * x, 10, z - 0.8 * (1 if z > 0 else -1)), (255, 238, 200), "Neon",
                      children=[{"Name": "Light", "ClassName": "PointLight",
                                 "Properties": {"Range": 22, "Brightness": 0.8, "Color": rgb(255, 230, 190)}}])

    for sx, team_col, folder, tag in ((-1, (190, 70, 60), "SpawnsA", "Rot"), (1, (60, 110, 190), "SpawnsB", "Blau")):
        # ---------- Basis (überdacht) ----------
        b.box("Ground", "BasePad", (32, 0.2, 70), (sx * 154, 0.1, 0), (100, 102, 106), "Concrete")
        b.box("Buildings", "BaseRoof", (32, 1, 70), (sx * 154, 11.5, 0), roof_col, "Metal")
        b.box("Decor", "BaseRoofEdge", (0.4, 0.4, 70), (sx * 138.2, 11, 0), team_col, "Neon")
        for z in (-34, -12, 12, 34):
            b.pillar(sx * 139, z, 11, s=1.6, color=steel)
        # Front mit drei Ausgängen, Seiten mit je einem Tor zur Straße
        b.wall_line("BaseFront", -35, 35, sx * 138, False, 11, steel, "Metal",
                    openings=[(-23, 9, 0, 8), (0, 12, 0, 8), (23, 9, 0, 8)])
        for z in (-35.6, 35.6):
            b.wall_line("BaseSide", min(sx * 138, sx * 170), max(sx * 138, sx * 170), z, True, 11, steel, "Metal",
                        openings=[(sx * 152, 10, 0, 8)])
        b.box("Decor", "BaseStrip", (0.3, 0.4, 70), (sx * (138 - 0.8), 8.6, 0), team_col, "Neon")
        b.sign("BaseSign" + tag, (14, 3, 0.4), (sx * 137.1, 13.6, 0), "TEAM " + tag.upper(), (28, 30, 34), team_col,
               angles=(0, 90 * sx, 0))
        # Spawns (8 pro Team), Blick zur Mitte
        for z in (-26, -9, 9, 26):
            for x in (sx * 160, sx * 148):
                b.spawn(x, z, yaw=face(x, z, 0, z), group=folder)
        # Deckung im Spawn (gegen Blick durch die Ausgänge)
        for z in (-17, 17):
            b.crate(sx * 144, z, s=4, color=(110, 100, 80))
        # Vorplatz zwischen Basis und Pumpenhof: Leitwände
        for z in (-18, 0, 18):
            b.barrier(sx * 126, z, along_x=False, length=7)

        # ---------- Pumpenhof mit Flagge A (Rot) bzw. C (Blau) ----------
        fx = sx * 95
        b.box("Ground", "YardPad", (40, 0.15, 44), (fx, 0.08, 0), (92, 95, 100), "DiamondPlate")
        for dz in (-1, 1):
            b.box("Ground", "YardStripe", (40, 0.06, 1.2), (fx, 0.17, dz * 21.4), warn, "SmoothPlastic")
        # vier L-Ecken (brusthoch) mit Lücken in jeder Seite
        for dx in (-1, 1):
            for dz in (-1, 1):
                b.half_wall(fx + dx * 14, dz * 10, 8, along_x=False, color=(150, 146, 138))
                b.half_wall(fx + dx * 10, dz * 14, 7, along_x=True, color=(150, 146, 138))
        # Rohre und Ventile am Hofrand (Deckung zum Ducken)
        for dz in (-1, 1):
            b.add("Cover", "YardPipe", (14, 2.4, 2.4), (fx + sx * 4, 1.2, dz * 19), (150, 120, 60), "Metal",
                  props={"Shape": "Cylinder"})
            b.box("Cover", "Valve", (2.4, 3.6, 2.4), (fx - sx * 6, 1.8, dz * 19), (170, 60, 50), "Metal")

        # ---------- Pumpenhaus zwischen Hof und Halle (zweistöckig) ----------
        px = sx * 56
        b.building2("PumpHouse" + tag, px, 0, 24, 30, brick, roof_col,
                    doors={"E": [-7, 7], "W": [-7, 7], "N": [0], "S": [0]},
                    windows1={"E": [0], "W": [0]},
                    windows2={"E": [-9, 0, 9], "W": [-9, 0, 9], "N": [-5, 5], "S": [-5, 5]},
                    stairs_at=("N",), material="Brick")
        b.box("Decor", "PumpHouseStripe", (24.2, 0.4, 30.2), (px, 10.1, 0), team_col, "Neon",
              props={"Transparency": 0.4})
        # Gassen nördlich/südlich am Pumpenhaus: Kabeltrommeln und Kisten
        for dz in (-1, 1):
            b.add("Cover", "CableDrum", (3, 6, 6), (sx * 40, 3, dz * 21), (130, 100, 70), "Wood",
                  props={"Shape": "Cylinder"})
            b.crate(sx * 70, dz * 21, s=4)

        # ---------- Nordstraße: Leitwände, LKW, Rohrbrücke ----------
        for x, z, ax in ((26, 36, True), (26, 52, True), (62, 44, False), (102, 34, True), (102, 54, True)):
            b.barrier(sx * x, z, along_x=ax, length=7)
        b.box("Cover", "Truck", (14, 6, 6.5), (sx * 84, 3.3, 52), (90, 110, 130), "Metal")
        b.box("Cover", "TruckCab", (5, 7.4, 6.5), (sx * 93.5, 3.7, 52), (200, 200, 205), "Metal")
        for z in (27.5, 60.5):
            b.box("Buildings", "PipeBridgeLeg", (1.4, 10, 1.4), (sx * 44, 5, z), steel, "Metal")
        for dz in (-0.9, 0.9):
            b.add("Decor", "PipeBridge", (34, 1.4, 1.4), (sx * 44, 10.6 + dz * 0.8, 44 + dz), (150, 120, 60), "Metal",
                  angles=(0, 90, 0), props={"Shape": "Cylinder"})
        # ---------- Südstraße: Leitwände, Tankwagen ----------
        for x, z, ax in ((26, -40, True), (26, -54, True), (62, -46, False), (102, -44, True), (102, -56, True)):
            b.barrier(sx * x, z, along_x=ax, length=7)
        b.add("Cover", "TankTruck", (14, 6, 6), (sx * 84, 3.6, -52), (210, 210, 205), "Metal",
              props={"Shape": "Cylinder"})
        b.box("Cover", "TankTruckBase", (16, 1.2, 6), (sx * 84, 0.6, -52), dark, "Metal")

        # ---------- Norden: Kühlturm, Förderband, Kohlelager ----------
        tx = sx * 56
        b.cylinder("Buildings", "CoolingTower", 34, 26, (tx, 13, 88), (178, 180, 182), "Concrete")
        b.cylinder("Buildings", "CoolingTowerTop", 30, 18, (tx, 35, 88), (186, 188, 190), "Concrete")
        b.cylinder("Decor", "CoolingTowerRim", 30.6, 0.6, (tx, 44.2, 88), (200, 70, 60), "SmoothPlastic")
        b.cylinder("Decor", "CoolingTowerBand", 34.4, 1.2, (tx, 8, 88), warn, "SmoothPlastic")
        # Förderband auf Stützen (begehbar, Treppe am Basis-Ende)
        cx0, cx1 = 80, 126
        for x in range(cx0, cx1 + 1, 9):
            b.pillar(sx * x, 79, 6, s=1, color=steel)
            b.pillar(sx * x, 83, 6, s=1, color=steel)
        b.catwalk("Conveyor", min(sx * cx0, sx * cx1), max(sx * cx0, sx * cx1), 78, 84, 6.6, rails=("N", "S"))
        b.box("Decor", "ConveyorBelt", (cx1 - cx0, 0.3, 2.2), (sx * (cx0 + cx1) / 2, 6.75, 81), (30, 30, 32), "Rubber")
        b.stairs("ConveyorStairs", sx * (cx1 + 9.6), 81, 5, 6.6, "W" if sx > 0 else "E")
        for x, z, r in ((104, 102, 9), (120, 64, 7), (84, 104, 6)):
            b.add("Cover", "CoalPile", (r * 2, r * 0.9, r * 2), (sx * x, r * 0.3, z), (40, 38, 36), "Slate",
                  props={"Shape": "Ball"})
        b.house("Shed" + tag, sx * 128, 102, 16, 12, 8, (110, 100, 90), roof_col, doors=("S", "E" if sx < 0 else "W"),
                material="Concrete")

        # ---------- Süden: Containerhof (Ramps auf die Container) ----------
        conts = ((22, -74, True, 20), (66, -74, True, 20), (110, -74, True, 20),
                 (12, -94, False, 16), (46, -96, False, 16), (88, -92, False, 16), (128, -96, False, 16),
                 (30, -108, True, 16), (70, -108, True, 16), (110, -108, True, 16))
        colors = ((70, 110, 150), (150, 70, 60), (90, 130, 80), (180, 140, 60), (110, 90, 140))
        for i, (x, z, ax, length) in enumerate(conts):
            b.container(sx * x, z, along_x=ax, color=colors[i % len(colors)], length=length)
        # gestapelt (zweite Ebene) und Rampen hinauf
        b.container(sx * 66, -74, along_x=True, level=1, color=(160, 160, 165), length=12)
        b.ramp("ContainerRamp", sx * 12, -74, 6, 11, 8, "E" if sx < 0 else "W")
        b.ramp("ContainerRamp", sx * 120, -74, 6, 11, 8, "W" if sx < 0 else "E")
        b.catwalk("ContainerBridge", min(sx * 32, sx * 56), max(sx * 32, sx * 56), -77, -71, 8.6, rails=("N", "S"))
        b.catwalk("ContainerBridge", min(sx * 76, sx * 100), max(sx * 76, sx * 100), -77, -71, 8.6, rails=("N", "S"))
        for x, z in ((30, -86), (64, -100), (100, -84), (122, -84)):
            b.crate(sx * x, z, s=4)

        # Schornstein in der Ecke (Landmarke)
        b.cylinder("Decor", "Chimney", 7, 60, (sx * 150, 30, 98), (150, 120, 100), "Brick")
        b.cylinder("Decor", "ChimneyBand", 7.4, 1.4, (sx * 150, 54, 98), (200, 60, 50), "SmoothPlastic")

    # ---------- Mitte: Turbinenhalle mit Flagge B ----------
    hx, hz, hh = 32, 22, 16
    for z, name in ((hz, "HallN"), (-hz, "HallS")):
        b.wall_line(name, -hx, hx, z, True, hh, hall_col, "Concrete",
                    openings=[(-12, 7, 0, 8), (12, 7, 0, 8), (-24, 5, 9.5, 12.5), (0, 6, 9.5, 15), (24, 5, 9.5, 12.5),
                              (-4, 3, 3, 6), (4, 3, 3, 6)])
        # Rusher: über Kisten durchs Mittelfenster direkt auf den Laufsteg
        window_climb(b, -2.1, z + (2.6 if z > 0 else -2.6))
    for x, name in ((-hx, "HallW"), (hx, "HallE")):
        b.wall_line(name, -hz + 1.2, hz - 1.2, x, False, hh, hall_col, "Concrete",
                    openings=[(-11, 7, 0, 8), (11, 7, 0, 8), (0, 4, 3, 6.5)])
    b.slab("HallRoof", -hx, hx, -hz, hz, hh + 1, roof_col, holes=[(-14, 14, -7, 7)], material="Metal")
    b.box("Ground", "HallFloor", (hx * 2 - 2, 0.12, hz * 2 - 2), (0, 0.06, 0), (88, 92, 98), "DiamondPlate")
    b.box("Decor", "HallSkylightGlow", (28, 0.2, 0.3), (0, hh + 1.1, 7), (180, 220, 255), "Neon", props={"Transparency": 0.3})
    b.box("Decor", "HallSkylightGlow", (28, 0.2, 0.3), (0, hh + 1.1, -7), (180, 220, 255), "Neon", props={"Transparency": 0.3})
    for z in (hz + 0.7, -hz - 0.7):
        b.box("Decor", "HallStripe", (hx * 2, 0.5, 0.3), (0, 14.5, z), warn, "Neon", props={"Transparency": 0.2})
    b.sign("HallSign", (24, 4, 0.4), (0, 18.6, hz + 0.9), "KRAFTWERK", (30, 32, 36), (240, 200, 90), angles=(0, 180, 0))
    b.sign("HallSignS", (24, 4, 0.4), (0, 18.6, -hz - 0.9), "KRAFTWERK", (30, 32, 36), (240, 200, 90))
    # Laufstege an den Längswänden (Höhe 7), Treppen an beiden Enden
    for dz in (-1, 1):
        z0, z1 = (15, 21) if dz > 0 else (-21, -15)
        b.catwalk("HallCatwalk", -21, 21, z0, z1, 7, rails=("S" if dz > 0 else "N",))
        b.stairs("HallStairs", -30.4, dz * 18, 4, 7, "E")
        b.stairs("HallStairs", 30.4, dz * 18, 4, 7, "W")
    # Turbinen (liegende Zylinder) als Deckung neben der Flagge
    for sx in (-1, 1):
        b.box("Buildings", "TurbineBase", (16, 1.2, 9), (sx * 21, 0.6, 0), dark, "Metal")
        b.add("Cover", "Turbine", (14, 8, 8), (sx * 21, 5, 0), (110, 130, 150), "Metal", props={"Shape": "Cylinder"})
        b.add("Decor", "TurbineHub", (2, 9, 9), (sx * 13.6, 5, 0), (200, 170, 60), "Metal", props={"Shape": "Cylinder"})
    for x, z in ((-7, 12), (7, -12)):
        b.crate(x, z, s=4, color=(120, 104, 80))
    for x, z in ((0, 12.5), (0, -12.5)):
        b.half_wall(x, z, 6, along_x=True, color=(140, 140, 136))

    # ---------- Straßen Mitte: Busse (keine Sichtlinie von Basis zu Basis) ----------
    for z in (51, -37):
        b.box("Cover", "Bus", (22, 7, 7), (0, 3.9, z), (200, 170, 50), "Metal")
        b.box("Decor", "BusWindows", (20, 1.6, 7.2), (0, 5.4, z), (40, 50, 60), "Glass", props={"Transparency": 0.3})
        for x in (-7, 7):
            b.add("Decor", "BusWheel", (1.2, 2.4, 2.4), (x, 1.2, z - 3.6 if z > 0 else z + 3.6), (25, 25, 25), "Rubber",
                  angles=(0, 90, 0), props={"Shape": "Cylinder"})
    b.barrier(0, 36, along_x=True, length=8)
    b.barrier(0, -52, along_x=True, length=8)

    # ---------- Spielweisen: Sniper-Türme (Süd-Lane), Flankentunnel (Rusher), Camper-Nester ----------
    for sx in (-1, 1):
        sniper_tower(b, sx * 136, -64, sx, steel, warn)
        flank_tunnel(b, sx, 36, 118, -28, -36, (126, 128, 132), roof_col, warn, exits_n=(56, 96), exits_s=(76,),
                     slits=(62, 90, 108))
        # Camper-Nest: Sandsack-Ring auf dem Förderband-Ende und an der Hallenecke
        for dz in (-1, 1):
            b.box("Cover", "Sandbags", (5, 2, 1.6), (sx * 40, 1, dz * 27.5), (170, 150, 110), "Fabric")

    # ---------- Norden Mitte: Leitstand zwischen den Kühltürmen ----------
    b.building2("ControlRoom", 0, 92, 26, 16, (150, 156, 162), roof_col,
                doors={"S": [-6, 6], "E": [0], "W": [0]}, windows1={"S": [0]},
                windows2={"S": [-8, 0, 8], "E": [0], "W": [0], "N": [-6, 6]}, stairs_at=("N",))
    for x, z in ((-24, 74), (24, 74), (-26, 108), (26, 108)):
        b.crate(x, z, s=5, color=(110, 100, 80))
    b.barrier(0, 72, along_x=True, length=10)

    # ---------- Süden Mitte: Portalkran über dem Containerhof ----------
    for x in (-24, 24):
        for z in (-82, -102):
            b.box("Buildings", "CraneLeg", (2.2, 26, 2.2), (x, 13, z), warn, "Metal")
    for z in (-82, -102):
        b.box("Buildings", "CraneBeam", (52, 2.4, 2.4), (0, 27, z), warn, "Metal")
    b.box("Buildings", "CraneTrolley", (6, 3, 24), (0, 25.5, -92), dark, "Metal")
    b.box("Decor", "CraneCable", (0.3, 16, 0.3), (0, 16, -92), (30, 30, 30), "Metal")
    b.container(0, -92, along_x=True, level=0, color=(200, 120, 40), length=8)

    # ---------- Flaggen ----------
    if flags:
        for name, x, color in (("A", -95, (255, 120, 120)), ("B", 0, (240, 240, 240)), ("C", 95, (120, 160, 255))):
            b.add("Objective", "Flag" + name, (0.3, 18, 18), (x, 0.25, 0), (230, 230, 235), "Neon",
                  angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.5, "CanCollide": False})
            pole_z = 13 if name == "B" else 0
            pole_x = x if name == "B" else x + (8 if x < 0 else -8)
            if name == "B":
                b.box("Decor", "FlagSignBCable", (0.2, 2.4, 0.2), (0, 15.8, 0.2), (30, 30, 30), "Metal")
                b.sign("FlagSignB", (5, 5, 0.4), (0, 12.5, 0), "B", (25, 25, 30), (255, 255, 255))
                b.sign("FlagSignB2", (5, 5, 0.4), (0, 12.5, 0.45), "B", (25, 25, 30), (255, 255, 255), angles=(0, 180, 0))
            else:
                b.box("Decor", "FlagPole" + name, (0.6, 14, 0.6), (pole_x, 7, pole_z), (60, 60, 65), "Metal")
                b.box("Decor", "FlagCloth" + name, (0.2, 2.6, 4), (pole_x, 12.5, pole_z + 2.2), color, "Fabric")
                b.sign("FlagSign" + name, (4, 4, 0.4), (pole_x, 16.5, pole_z), name, (25, 25, 30), (255, 255, 255),
                       angles=(0, 90 if x < 0 else -90, 0))

    b.save(filename, "Kraftwerk")



# ---------- Extinction: offene Welt (2000 x 2000), große Stadt mit Safe Zone in der Mitte ----------
# Mitte der Welt bei EXTINCTION_ORIGIN (wie Center in Modes.lua). Die Safe Zone ist ein Kreis um die Mitte (Teil
# "SafeZone" in der Gruppe "Zone": Radius = Size.X / 2, liest der Server) auf dem Platz "Camp Phoenix". Darin: Spawns,
# Waffenstand, Itemstand, Fahrzeugstand, Lager und das Tor zurück zum Hub (unsichtbare Punkte in der Gruppe "Stands").
# Drumherum die Stadt (1400 x 1400, Straßenraster alle 140 Studs): Hochhäuser in der Innenstadt, Geschäfte und
# Wohnhäuser außen, Polizeipräsidium, Rathaus, Einkaufszentrum, Schule, Kirche, Parks und die drei roten Zonen
# (Krankenhaus, Industriegebiet, Militärsperrgebiet) mit Kontrollpunkten an jeder Straße. Außerhalb nur wenig:
# Hügel, Wald, ein See, ein Bauernhof und der Funkturm. Zombies spawnen draußen auf Boden und Straßen (ZombieService).

EXTINCTION_ORIGIN = (0, 0, -6000)
EXTINCTION_SIZE = 2000
EXTINCTION_SAFE_RADIUS = 100
EXT_CITY = 700       # Stadt von -700 bis 700 (äußerste Straße)
EXT_PITCH = 140      # Abstand der Straßen
EXT_STREET = 20      # Straßenbreite
EXT_ROAD_W = EXT_STREET
EXT_SLAB = EXT_PITCH - EXT_STREET  # Gehweg-Block (120 x 120, 0,5 hoch)
# Orte: Schlüssel -> (Titel, x, z, Radius). Der Client zeigt den Titel beim Betreten (kleinster Ort gewinnt) und auf der Karte.
EXT_PLACES = {
    "Camp": ("CAMP PHOENIX", 0, 0, 130),
    "Innenstadt": ("INNENSTADT", 0, 0, 300),
    "Nordstadt": ("NORDSTADT", -120, 540, 200),
    "Suedstadt": ("SÜDSTADT", 120, -540, 200),
    "Ostviertel": ("OSTVIERTEL", 540, 0, 200),
    "Westviertel": ("WESTVIERTEL", -540, -60, 200),
    "Militaer": ("MILITÄRSPERRGEBIET", -560, 560, 150),
    "Industrie": ("INDUSTRIEGEBIET", 560, -560, 150),
    "Krankenhaus": ("ST. MARIEN KRANKENHAUS", 560, 490, 110),
    "Polizei": ("POLIZEIPRÄSIDIUM", -350, 70, 60),
    "Rathaus": ("RATHAUS", 70, 210, 60),
    "Einkaufszentrum": ("EINKAUFSZENTRUM", 210, -210, 60),
    "Schule": ("GESAMTSCHULE", -490, -210, 60),
    "Kirche": ("ST. PETRI KIRCHE", -70, -490, 60),
    "Stadtpark": ("STADTPARK", -350, -350, 60),
    "Tankstelle": ("TANKSTELLE", 630, 70, 60),
    "Bauernhof": ("BAUERNHOF", -830, -640, 110),
    "Schwarzsee": ("SCHWARZSEE", -840, 300, 130),
    "Funkturm": ("FUNKTURM", 830, 830, 60),
}
# Rote Zonen: Schlüssel des Orts -> Radius der Zone
EXT_REDZONES = {"Militaer": 190, "Industrie": 190, "Krankenhaus": 150}
EXT_LAKES = [("Schwarzsee", -840, 300, 110, 10)]
# Blöcke mit eigenem Inhalt (Mitte des Blocks -> Art); alle anderen füllt build_extinction nach Ring
EXT_SPECIAL_BLOCKS = {
    (-70, -70): "Plaza", (70, -70): "Plaza", (-70, 70): "Plaza", (70, 70): "Plaza",
    (-350, 70): "Polizei", (70, 210): "Rathaus", (210, -210): "Einkaufszentrum", (-490, -210): "Schule",
    (-70, -490): "Kirche", (-350, -350): "Park", (350, 210): "Park", (630, 70): "Tankstelle",
    (490, 490): "Krankenhaus", (630, 490): "Krankenhaus",
    (-630, 490): "Militaer", (-490, 490): "Militaer", (-630, 630): "Militaer", (-490, 630): "Militaer",
    (490, -490): "Industrie", (630, -490): "Industrie", (490, -630): "Industrie", (630, -630): "Industrie",
    (-210, -630): "Parkplatz", (350, 630): "Parkplatz",
}


def extinction_terrain():
    """Höhenfeld der offenen Welt (tools/extinction_terrain.py): Stadt eben, außen Hügel, ein See, Bergrand."""
    import extinction_terrain as et
    t = et.Terrain(7)
    t.city = EXT_CITY + 14
    t.edge = EXTINCTION_SIZE // 2 - 40
    t.flat_rect(-EXT_CITY - 16, -EXT_CITY - 16, EXT_CITY + 16, EXT_CITY + 16, 90)
    for key in ("Bauernhof",):
        _, x, z, r = EXT_PLACES[key]
        t.flat(x, z, r, 60)
    half = EXTINCTION_SIZE // 2
    for s in (-1, 1):  # Landstraßen aus der Stadt bis zum Rand
        t.road(0, s * EXT_CITY, 0, s * half, EXT_STREET)
        t.road(s * EXT_CITY, 0, s * half, 0, EXT_STREET)
    for _, x, z, r, depth in EXT_LAKES:
        t.lake(x, z, r, depth)
    t.hill(830, 830, 150, 26, 34)  # Funkturm-Hügel
    t.build()
    return t


def build_extinction():
    b = Builder(EXTINCTION_ORIGIN)
    rng = random.Random(11)
    half = EXTINCTION_SIZE / 2
    R = EXTINCTION_SAFE_RADIUS
    C, P, ST, SLAB = EXT_CITY, EXT_PITCH, EXT_STREET, EXT_SLAB
    grass = (88, 100, 66)
    asphalt, line_yellow, concrete = (50, 52, 56), (200, 170, 70), (128, 126, 120)
    sand, dark = (176, 158, 118), (34, 36, 40)
    sidewalk = (146, 144, 138)
    safe = (96, 210, 120)
    danger = (215, 85, 45)
    red = (226, 56, 48)
    glass_blue = (60, 90, 110)
    BASE = 0.5  # Oberkante der Gehweg-Blöcke

    def frame(cx, cz, yaw):
        c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        return lambda lx, ly, lz: (cx + lx * c + lz * sn, ly, cz - lx * sn + lz * c)

    def facing(x, z, tx=0.0, tz=0.0):
        """yaw, mit dem die Vorderseite (-Z) eines Teils bei (x, z) zum Punkt (tx, tz) zeigt."""
        return math.degrees(math.atan2(x - tx, z - tz))

    def in_safe(x, z, margin=0.0):
        return math.hypot(x, z) < R + margin

    # ---------- Gelände ----------
    # Das Terrain (Stadt eben mit Pflaster, außen Hügel, See, Bergrand) baut der Server beim Start aus dem Höhenfeld
    # (ExtinctionTerrainData.lua, hier erzeugt). Der flache Boden darunter bleibt als Rückfall liegen; Extinction.lua
    # senkt ihn ab, sobald das Terrain steht. H(x, z) = Geländehöhe für Bäume, Felsen, Kisten außerhalb der Stadt.
    import extinction_terrain as et
    terrain = extinction_terrain()
    et.write_lua(terrain)
    H = terrain.sample
    b.box("Ground", "Ground", (EXTINCTION_SIZE + 120, 4, EXTINCTION_SIZE + 120), (0, -2, 0), grass, "Grass")
    b.border(EXTINCTION_SIZE, EXTINCTION_SIZE, 3, (96, 94, 88), "Slate", barrier=160)

    # ---------- Straßenraster ----------
    lines = list(range(-C, C + 1, P))          # Straßen bei -700, -560, ..., 700
    centers = [v + P / 2 for v in lines[:-1]]  # Blockmitten bei -630, ..., 630
    road_w = ST

    def block_kind(bx, bz):
        return EXT_SPECIAL_BLOCKS.get((bx, bz))

    def compound(bx, bz):
        """Teil einer Anlage, die mehrere Blöcke überspannt (dort keine Straßen dazwischen)."""
        return block_kind(bx, bz) in ("Militaer", "Industrie", "Krankenhaus", "Plaza")

    def segment_free(vertical, line, t):
        """Straßenstück auf Linie line von t bis t + P: nur, wenn es nicht zwischen zwei Blöcken derselben Anlage liegt."""
        mid = t + P / 2
        if vertical:
            left, right = (line - P / 2, mid), (line + P / 2, mid)
        else:
            left, right = (mid, line - P / 2), (mid, line + P / 2)
        ka, kb = block_kind(*left), block_kind(*right)
        return not (ka is not None and ka == kb and compound(*left))

    def street(x0, z0, x1, z1, lines_on=True):
        if abs(x1 - x0) > abs(z1 - z0):
            length, cx, cz = abs(x1 - x0), (x0 + x1) / 2, z0
            b.box("Roads", "Road", (length, 0.12, road_w), (cx, 0.06, cz), asphalt, "Asphalt")
            if lines_on and length > road_w + 4:
                b.box("Roads", "CenterLine", (length - road_w, 0.02, 0.5), (cx, 0.13, cz), line_yellow, "SmoothPlastic")
        else:
            length, cx, cz = abs(z1 - z0), x0, (z0 + z1) / 2
            b.box("Roads", "Road", (road_w, 0.13, length), (cx, 0.065, cz), asphalt, "Asphalt")
            if lines_on and length > road_w + 4:
                b.box("Roads", "CenterLine", (0.5, 0.02, length - road_w), (cx, 0.14, cz), line_yellow, "SmoothPlastic")

    for line in lines:
        for t in lines[:-1]:
            # senkrecht (entlang z) auf x = line, waagerecht (entlang x) auf z = line
            if segment_free(True, line, t) and not (line == 0 and -P <= t < P):
                street(line, t, line, t + P)
            if segment_free(False, line, t) and not (line == 0 and -P <= t < P):
                street(t, line, t + P, line)
    # Zufahrten zur Safe Zone (Tore auf den Achsen) und Landstraßen aus der Stadt
    for s in (-1, 1):
        street(0, s * (R - 2), 0, s * P, lines_on=False)
        street(s * (R - 2), 0, s * P, 0, lines_on=False)
        street(0, s * C, 0, s * half)
        street(s * C, 0, s * half, 0)

    def on_road(x, z, margin=8):
        w = road_w / 2 + margin
        if abs(x) <= C + w and abs(z) <= C + w:
            return True  # die ganze Stadt
        return abs(x) < w or abs(z) < w

    # Straßenlaternen an jeder Kreuzung (Ecke Nordost)
    for x in lines:
        for z in lines:
            lx, lz = x + ST / 2 + 2, z + ST / 2 + 2
            if in_safe(lx, lz, 40):
                continue
            b.cylinder("Decor", "StreetLamp", 0.5, 12, (lx, 6.5, lz), dark)
            b.box("Decor", "StreetLampArm", (3.4, 0.4, 0.4), (lx - 1.6, 12.4, lz - 1.6), dark, "Metal", angles=(0, 45, 0))
            b.box("Decor", "StreetLampHead", (1.4, 0.4, 1.4), (lx - 3, 12.2, lz - 3), (255, 236, 200), "Neon",
                  children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {
                      "Range": 30, "Brightness": 0.8, "Color": rgb(255, 226, 190)}}])

    # ---------- Safe Zone "Camp Phoenix" ----------
    b.add("Ground", "CampFloor", (0.2, 2 * R + 6, 2 * R + 6), (0, 0.08, 0), (118, 116, 110), "Concrete",
          angles=(0, 0, 90), props={"Shape": "Cylinder"})
    b.add("Zone", "SafeZone", (2 * R, 80, 2 * R), (0, 40, 0), safe, "SmoothPlastic",
          props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
    # Grenze: Wall aus Sandkörben mit vier Toren für die Straßen (dazu der grüne Leuchtring am Boden, siehe unten)
    gate_half = math.degrees((road_w / 2 + 3) / (R + 3))
    k = 0
    phi = 0.0
    while phi < 360:
        nearest_gate = min(abs(((phi - g) + 180) % 360 - 180) for g in (0, 90, 180, 270))
        if nearest_gate > gate_half:
            a = math.radians(phi)
            b.box("Walls", "Hesco", (5, 5.5, 5), (math.cos(a) * (R + 3), 2.75, math.sin(a) * (R + 3)), sand, "Fabric",
                  angles=(0, -phi + 90, 0))
            k += 1
        phi += math.degrees(5.1 / (R + 3))
    for gx, gz in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        yaw = facing(gx, gz)  # Vorderseite zur Mitte
        f = frame(gx * (R + 3), gz * (R + 3), yaw)
        for side in (-1, 1):
            b.box("Walls", "GatePost", (1.6, 12, 1.6), f(side * (road_w / 2 + 2), 6, 0), dark, "Metal", angles=(0, yaw, 0))
        b.box("Walls", "GateBeam", (road_w + 6, 1.6, 1.6), f(0, 12.4, 0), dark, "Metal", angles=(0, yaw, 0))
        # außen: Schild SAFE ZONE, innen: Hinweis auf PvP draußen
        b.sign2("GateSignOut", (18, 3.6, 0.3), f(0, 15, 0.4), "SAFE ZONE", "KEIN PVP  ·  HANDEL  ·  LAGER",
                (24, 28, 26), safe, (230, 235, 230), angles=(0, yaw + 180, 0), glow=safe)
        b.sign2("GateSignIn", (18, 3.6, 0.3), f(0, 15, -0.4), "AUSGANG", "ZOMBIES  ·  PVP NACH 5 SEKUNDEN",
                (30, 24, 22), danger, (235, 230, 228), angles=(0, yaw, 0), glow=danger)
        for side in (-1, 1):
            b.barrier(*f(side * (road_w / 2 + 6), 0, -6)[0::2], along_x=abs(gz) > 0, length=6)

    # Spawns um den Fahnenmast, Blick nach außen
    for k in range(10):
        a = 2 * math.pi * k / 10
        x, z = math.cos(a) * 13, math.sin(a) * 13
        b.spawn(x, z, yaw=facing(x, z) + 180)
    b.add("Decor", "FlagBase", (1.2, 9, 9), (0, 0.6, 0), concrete, "Concrete", angles=(0, 0, 90), props={"Shape": "Cylinder"})
    b.cylinder("Decor", "FlagPole", 0.6, 22, (0, 12, 0), (200, 200, 205))
    b.box("Decor", "Flag", (9, 5, 0.2), (4.8, 20.4, 0), safe, "Fabric")
    b.sign2("CampSign", (16, 4, 0.3), (0, 8, -0.8), "CAMP PHOENIX", "SAFE ZONE  ·  SPAWN", (24, 28, 26), safe,
            (230, 235, 230), angles=(0, 0, 0), glow=safe)
    b.sign2("CampSignBack", (16, 4, 0.3), (0, 8, 0.8), "CAMP PHOENIX", "SAFE ZONE  ·  SPAWN", (24, 28, 26), safe,
            (230, 235, 230), angles=(0, 180, 0), glow=safe)

    def stand(key, title, subtitle, cx, cz, color, goods):
        """Verkaufsstand mit Theke (Vorderseite zur Mitte), Dach, Schild und Prompt-Punkt davor."""
        yaw = facing(cx, cz)
        f = frame(cx, cz, yaw)
        rot_y = (0, yaw, 0)
        b.box("Stands", "StandFloor", (16, 0.4, 11), f(0, 0.3, 0.5), (84, 80, 74), "WoodPlanks", angles=rot_y)
        b.box("Stands", "StandCounter", (13, 3.4, 1.6), f(0, 1.9, -3.4), (96, 72, 52), "WoodPlanks", angles=rot_y)
        b.box("Stands", "StandCounterTop", (13.6, 0.3, 2.2), f(0, 3.7, -3.4), dark, "Metal", angles=rot_y)
        b.box("Stands", "StandBack", (16, 10, 0.8), f(0, 5.4, 5.6), (70, 72, 70), "CorrodedMetal", angles=rot_y)
        for side in (-1, 1):
            b.box("Stands", "StandSide", (0.8, 10, 10), f(side * 7.6, 5.4, 0.9), (70, 72, 70), "CorrodedMetal", angles=rot_y)
        b.box("Stands", "StandRoof", (17.5, 0.5, 13), f(0, 10.6, 0), color, "Fabric", angles=rot_y)
        b.box("Stands", "StandRoofEdge", (17.5, 1.2, 0.3), f(0, 10.2, -6.4), lighten(color, -0.3), "Fabric", angles=rot_y)
        b.sign2("StandSign_" + key, (13, 3.4, 0.3), f(0, 12.8, -5.6), title, subtitle, (26, 26, 28), color, (230, 230, 230),
                angles=rot_y, glow=color)
        # Händler hinter der Theke (einfache Figur)
        b.box("Stands", "Vendor", (2, 2.2, 1.1), f(0, 4.9, -1.2), (60, 64, 58), "Fabric", angles=rot_y)
        b.box("Stands", "VendorHead", (1.2, 1.2, 1.2), f(0, 6.7, -1.2), (196, 156, 126), "SmoothPlastic", angles=rot_y)
        b.box("Stands", "VendorCap", (1.3, 0.4, 1.4), f(0, 7.4, -1.25), color, "Fabric", angles=rot_y)
        for lx, ly, sx, sy, sz, col, mat in goods:
            b.box("Stands", "Goods", (sx, sy, sz), f(lx, ly, 5.0), col, mat, angles=rot_y)
        b.add("Stands", key, (2, 2, 2), f(0, 2.5, -5.4), color, "SmoothPlastic", angles=rot_y,
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
        b.box("Stands", "StandLamp", (8, 0.2, 0.6), f(0, 10.1, -3), (255, 236, 200), "Neon", angles=rot_y,
              children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                  "Face": "Bottom", "Range": 16, "Brightness": 1.2, "Angle": 90, "Color": rgb(255, 236, 210)}}])

    gun = (40, 42, 46)
    stand("Stand_Weapons", "WAFFEN", "WAFFEN  ·  MUNITION", -36, 40, (196, 120, 60),
          [(-4.5, 6.8, 4.6, 0.7, 0.4, gun, "Metal"), (0.5, 6.8, 4.0, 0.6, 0.4, gun, "Metal"),
           (4.6, 6.8, 2.6, 0.7, 0.4, gun, "Metal"), (-4.5, 4.8, 3.6, 0.6, 0.4, gun, "Metal"),
           (0.5, 4.8, 5.0, 0.7, 0.4, gun, "Metal"), (4.6, 4.8, 3.0, 0.6, 0.4, gun, "Metal")])
    med = (230, 232, 230)
    stand("Stand_Items", "ITEMS", "HEILUNG  ·  RÜSTUNG", 36, 40, (200, 70, 70),
          [(-4.5, 4.6, 2.4, 1.6, 1.4, med, "SmoothPlastic"), (-1.5, 4.6, 2.4, 1.6, 1.4, med, "SmoothPlastic"),
           (1.5, 4.6, 2.4, 1.6, 1.4, med, "SmoothPlastic"), (4.5, 4.6, 2.4, 1.6, 1.4, med, "SmoothPlastic"),
           (-3, 6.6, 3.0, 1.6, 1.4, (70, 90, 70), "Fabric"), (3, 6.6, 3.0, 1.6, 1.4, (70, 90, 70), "Fabric")])
    stand("Stand_Vehicles", "FAHRZEUGE", "KAUFEN  ·  AUF TASTE LEGEN", -34, -48, (90, 150, 210),
          [(-4, 6.2, 5, 2.4, 0.2, (40, 60, 80), "SmoothPlastic"), (3.5, 6.2, 5, 2.4, 0.2, (40, 60, 80), "SmoothPlastic")])

    # Ausstellungsfahrzeuge neben dem Fahrzeugstand
    def car(x, z, yaw, color, group="Decor", wreck=False):
        f = frame(x, z, yaw)
        body = lighten(color, -0.35) if wreck else color
        b.box(group, "CarBody", (5.6, 2.2, 11), f(0, 2.0, 0), body, "Metal" if not wreck else "CorrodedMetal",
              angles=(0, yaw, 0 if not wreck else rng.uniform(-4, 4)))
        b.box(group, "CarCabin", (5.0, 2.0, 5.4), f(0, 4.0, 0.6), lighten(body, -0.2), "Metal", angles=(0, yaw, 0))
        b.box(group, "CarGlass", (5.1, 1.4, 4.0), f(0, 4.1, 0.4), (40, 52, 60), "Glass", angles=(0, yaw, 0),
              props={"Transparency": 0.3 if not wreck else 0.6})
        for sx in (-1, 1):
            for sz in (-1, 1):
                b.add(group, "CarWheel", (0.9, 2.4, 2.4), f(sx * 2.7, 1.2, sz * 3.6), (24, 24, 26), "Rubber",
                      angles=(0, yaw, 0), props={"Shape": "Cylinder"})

    car(-58, -36, 30, (180, 60, 50))
    car(-52, -62, 40, (60, 120, 180))

    # Lager: Container mit offener Tür zur Mitte (neben der Straße nach Osten)
    lx, lz = 62, -32
    yaw = facing(lx, lz)
    f = frame(lx, lz, yaw)
    for side in (-1, 1):
        b.box("Stands", "StashWall", (0.6, 8.6, 20), f(side * 4.2, 4.3, 0), (60, 96, 70), "CorrodedMetal", angles=(0, yaw, 0))
    b.box("Stands", "StashRoof", (9, 0.6, 20), f(0, 8.9, 0), (52, 84, 62), "CorrodedMetal", angles=(0, yaw, 0))
    b.box("Stands", "StashBack", (9, 8.6, 0.6), f(0, 4.3, 9.7), (52, 84, 62), "CorrodedMetal", angles=(0, yaw, 0))
    b.box("Stands", "StashFloor", (8.4, 0.4, 20), f(0, 0.3, 0), (70, 70, 72), "DiamondPlate", angles=(0, yaw, 0))
    for side in (-1, 1):
        b.box("Stands", "StashDoor", (0.3, 8.4, 4.2), f(side * 6.2, 4.3, -11.6), (60, 96, 70), "CorrodedMetal",
              angles=(0, yaw + side * 60, 0))
    for k in range(4):
        b.box("Stands", "StashCrate", (2.6, 2.6, 2.6), f(rng.uniform(-2, 2), 1.8 + (k % 2) * 2.6, 4 + (k // 2) * 3),
              (120, 96, 64), "WoodPlanks", angles=(0, yaw + rng.uniform(-10, 10), 0))
    b.sign2("StandSign_Stash", (10, 3, 0.3), f(0, 10.8, -9.6), "LAGER", "IMMER SICHER  ·  E DRÜCKEN", (26, 26, 28),
            (226, 178, 52), (230, 230, 230), angles=(0, yaw, 0), glow=(226, 178, 52))
    b.add("Stands", "Stash", (2, 2, 2), f(0, 2.5, -12), (226, 178, 52), "SmoothPlastic", angles=(0, yaw, 0),
          props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    # Tor zurück zum Hub (neben der Straße nach Westen)
    hx, hz = -62, -32
    yaw = facing(hx, hz)
    f = frame(hx, hz, yaw)
    hub = (120, 185, 235)
    for side in (-1, 1):
        b.box("Decor", "HubGatePillar", (1.6, 12, 1.6), f(side * 6, 6, 0), dark, "Metal", angles=(0, yaw, 0))
    b.box("Decor", "HubGateBeam", (14, 1.4, 1.6), f(0, 12.4, 0), dark, "Metal", angles=(0, yaw, 0))
    b.box("Decor", "HubGateGlow", (10.4, 11.4, 0.3), f(0, 5.9, 0.2), hub, "ForceField", angles=(0, yaw, 0),
          props={"Transparency": 0.25, "CanCollide": False})
    b.sign2("HubGateSign", (12, 3, 0.3), f(0, 14.8, -0.2), "ZURÜCK ZUM HUB", "INVENTAR BLEIBT ERHALTEN", (26, 26, 28),
            hub, (230, 230, 230), angles=(0, yaw, 0), glow=hub)
    b.add("Portals", "Portal_Hub", (10, 0.3, 5), f(0, 0.4, -1.8), hub, "Neon", angles=(0, yaw, 0),
          props={"CanCollide": False, "Transparency": 0.45})

    # Hubschrauber-Landeplatz, Zelte, Wachtürme, Flutlicht
    b.add("Decor", "Helipad", (0.3, 26, 26), (44, 0.2, -58), (70, 72, 76), "Concrete", angles=(0, 0, 90),
          props={"Shape": "Cylinder"})
    b.floor_text("HelipadH", (10, 0.1, 10), (44, 0.4, -58), "H", (236, 236, 236))
    for tx, tz in ((-60, 36), (-72, 22), (60, 36), (72, 22)):
        yaw = facing(tx, tz)
        f = frame(tx, tz, yaw)
        tent_col = (96, 108, 78)
        b.box("Decor", "TentFloor", (8, 0.2, 10), f(0, 0.2, 0), (70, 70, 64), "Fabric", angles=(0, yaw, 0))
        b.add("Decor", "Tent", (8, 5, 5), f(0, 2.6, -2.5), tent_col, "Fabric", angles=(0, yaw, 0), cls="WedgePart")
        b.add("Decor", "Tent", (8, 5, 5), f(0, 2.6, 2.5), tent_col, "Fabric", angles=(0, yaw + 180, 0), cls="WedgePart")
    for k in range(4):
        a = math.radians(45 + 90 * k)
        x, z = math.cos(a) * 86, math.sin(a) * 86
        for dx in (-2, 2):
            for dz in (-2, 2):
                b.box("Decor", "TowerLeg", (0.8, 14, 0.8), (x + dx, 7, z + dz), (96, 74, 52), "Wood")
        b.box("Decor", "TowerDeck", (7, 0.6, 7), (x, 14.2, z), (110, 86, 60), "WoodPlanks")
        b.box("Decor", "TowerRoof", (7.6, 0.4, 7.6), (x, 18.6, z), (70, 80, 60), "Fabric")
        b.box("Decor", "TowerLamp", (1.2, 1.2, 1.2), (x, 16, z), (255, 236, 200), "Neon",
              children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                  "Face": "Bottom", "Range": 40, "Brightness": 1.4, "Angle": 70, "Color": rgb(255, 236, 210)}}])
    for k in range(4):
        a = math.radians(45 + 90 * k)
        x, z = math.cos(a) * 32, math.sin(a) * 32
        b.cylinder("Decor", "LampPost", 0.6, 12, (x, 6, z), dark)
        b.box("Decor", "LampHead", (1.6, 0.6, 1.6), (x, 12.2, z), (255, 240, 210), "Neon",
              children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {
                  "Range": 34, "Brightness": 0.9, "Color": rgb(255, 232, 200)}}])
    for k in range(8):
        a = math.radians(rng.uniform(0, 360))
        r = rng.uniform(70, 88)
        x, z = math.cos(a) * r, math.sin(a) * r
        if min(abs(x), abs(z)) < road_w:
            continue
        b.box("Decor", "SupplyCrate", (3, 3, 3), (x, 1.5, z), (110, 90, 62), "WoodPlanks", angles=(0, rng.uniform(0, 90), 0))

    # ---------- Helfer: Kisten, Schilder, Bäume ----------
    spot_count = {"Wood": 0, "Toolbox": 0, "Medical": 0, "Ammo": 0, "Military": 0}

    def spot(kind, x, z, y=BASE, yaw=0.0):
        """Lagerkiste (ContainerService): unsichtbares Teil Spot_<Art> in der Gruppe Loot, y = Höhe des Bodens darunter."""
        spot_count[kind] += 1
        b.add("Loot", "Spot_" + kind, (3, 2, 3), (x, y + 1, z), (200, 160, 80), "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    def ground_spot(kind, x, z, yaw=None):
        """Kiste im Freien auf dem Gelände (außerhalb der Stadt)."""
        spot(kind, x, z, H(x, z), rng.uniform(0, 360) if yaw is None else yaw)

    obstacles = []  # (x, z) von Bäumen und Felsen, damit verstreute Kisten nicht darin stehen

    def tree_at(x, z, y=None):
        obstacles.append((x, z))
        g = H(x, z) if y is None else y
        if rng.random() < 0.6:  # Kiefer: Stamm und vier schrumpfende, gedrehte Nadelblöcke
            h = rng.uniform(13, 21)
            b.box("Nature", "Trunk", (1.5, h, 1.5), (x, g + h / 2 - 0.6, z), (92, 66, 44), "Wood")
            tone = rng.randint(-8, 8)
            for w, level in ((10.5, 0.36), (8.0, 0.55), (5.6, 0.74), (3.0, 0.92)):
                b.box("Nature", "Needles", (w, 3.6, w), (x, g + h * level + 1.2, z), (44 + tone, 88 + tone, 48), "Grass",
                      angles=(0, rng.uniform(0, 90), 0), props={"CanCollide": False})
        else:                   # Laubbaum
            h = rng.uniform(9, 14)
            b.box("Nature", "Trunk", (1.8, h, 1.8), (x, g + h / 2 - 0.6, z), (100, 70, 45), "Wood")
            r = rng.uniform(9, 13)
            b.add("Nature", "Leaves", (r, r, r), (x, g + h + r / 3, z), (rng.randint(54, 74), rng.randint(110, 130), 48), "Grass",
                  props={"Shape": "Ball", "CanCollide": False})

    def rock_at(x, z, s=None):
        s = s or rng.uniform(4, 11)
        obstacles.append((x, z))
        g = H(x, z)
        b.box("Nature", "Rock", (s, s * 0.7, s * 1.2), (x, g + s * 0.15, z),
              rng.choice(((115, 115, 110), (104, 102, 98), (126, 120, 108))), "Slate",
              angles=(rng.uniform(-12, 12), rng.uniform(0, 360), rng.uniform(-12, 12)))

    def wall_sign(name, title, subtitle, x, z, face, w, d, y, color, width=14):
        """Schild an der Fassade (face = Seite N/S/E/W eines Gebäudes mit Mitte x, z und Größe w x d)."""
        if face == "N":
            pos, yaw = (x, y, z + d / 2 + 0.35), 180
        elif face == "S":
            pos, yaw = (x, y, z - d / 2 - 0.35), 0
        elif face == "E":
            pos, yaw = (x + w / 2 + 0.35, y, z), -90
        else:
            pos, yaw = (x - w / 2 - 0.35, y, z), 90
        b.sign2(name, (width, 3.2, 0.3), pos, title, subtitle, (26, 26, 28), color, (230, 230, 230), angles=(0, yaw, 0), glow=color)

    def face_to_street(ox, oz):
        """Seite eines Grundstücks (Versatz ox, oz von der Blockmitte), die zur nächsten Straße zeigt."""
        if abs(ox) >= abs(oz):
            return "E" if ox > 0 else "W"
        return "N" if oz > 0 else "S"

    def into(face, x, z, depth):
        """Punkt depth Studs von der Tür nach innen (Tür auf Seite face eines Gebäudes bei x, z)."""
        dx, dz = {"N": (0, -1), "S": (0, 1), "E": (-1, 0), "W": (1, 0)}[face]
        return x + dx * depth, z + dz * depth

    def slab(bx, bz, color=sidewalk, material="Concrete", name="Sidewalk", size=SLAB):
        b.box("Ground", name, (size, BASE, size), (bx, BASE / 2, bz), color, material)

    car_cols = ((130, 60, 50), (70, 90, 120), (120, 120, 110), (90, 100, 70), (160, 150, 130), (60, 60, 64))

    def car(x, z, yaw, color, group="Cover", wreck=True, y=0.0):
        f = frame(x, z, yaw)
        body = lighten(color, -0.35) if wreck else color
        b.box(group, "CarBody", (5.6, 2.2, 11), f(0, y + 2.0, 0), body, "Metal" if not wreck else "CorrodedMetal",
              angles=(0, yaw, 0 if not wreck else rng.uniform(-4, 4)))
        b.box(group, "CarCabin", (5.0, 2.0, 5.4), f(0, y + 4.0, 0.6), lighten(body, -0.2), "Metal", angles=(0, yaw, 0))
        b.box(group, "CarGlass", (5.1, 1.4, 4.0), f(0, y + 4.1, 0.4), (40, 52, 60), "Glass", angles=(0, yaw, 0),
              props={"Transparency": 0.3 if not wreck else 0.6})
        for sx in (-1, 1):
            for sz in (-1, 1):
                b.add(group, "CarWheel", (0.9, 2.4, 2.4), f(sx * 2.7, y + 1.2, sz * 3.6), (24, 24, 26), "Rubber",
                      angles=(0, yaw, 0), props={"Shape": "Cylinder"})

    # ---------- Gebäudetypen ----------
    counter = [0]

    def nm(prefix):
        counter[0] += 1
        return "%s%d" % (prefix, counter[0])

    tower_cols = ((150, 156, 164), (176, 170, 160), (110, 118, 128), (196, 190, 178), (132, 126, 120), (90, 98, 110),
                  (168, 150, 130))
    glass_cols = ((46, 66, 84), (52, 74, 70), (40, 48, 60), (70, 84, 96))
    shop_cols = ((196, 186, 168), (176, 160, 140), (150, 158, 166), (210, 204, 190), (168, 140, 120), (140, 150, 136))
    house_cols = ((176, 160, 140), (150, 132, 116), (190, 184, 170), (140, 146, 150), (168, 140, 120), (186, 170, 150),
                  (160, 170, 156))
    signs = (("APOTHEKE", "MEDIKAMENTE · TAG UND NACHT", (90, 200, 120), ["Medical"]),
             ("WAFFEN-HANDEL", "JAGD · SPORT · NOTWEHR", (215, 85, 45), ["Ammo"]),
             ("BAUMARKT", "WERKZEUG · HOLZ · FARBEN", (226, 160, 52), ["Toolbox"]),
             ("SUPERMARKT", "24 H GEÖFFNET", (200, 70, 60), ["Wood"]),
             ("KIOSK", "ZEITUNG · TABAK · SNACKS", (220, 200, 90), ["Wood"]),
             ("ELEKTRO", "HANDY · TV · BATTERIEN", (90, 150, 230), ["Toolbox"]),
             ("BAR ZUM ZOMBIE", "GESCHLOSSEN", (200, 90, 200), ["Wood"]),
             ("DINER", "BURGER · KAFFEE", (230, 120, 60), ["Wood"]),
             ("ARZTPRAXIS", "DR. MED. KRÄMER", (120, 200, 220), ["Medical"]),
             ("PFANDHAUS", "ANKAUF · VERKAUF", (210, 180, 90), ["Toolbox"]),
             ("SPORTLADEN", "OUTDOOR · CAMPING", (90, 190, 160), ["Wood"]),
             ("BANK", "SPARKASSE ÖDLAND", (200, 60, 60), ["Military"]))

    def tower(x, z, w, d, h, color):
        """Hochhaus (nicht begehbar): Körper, Fensterbänder rundherum, dunkle Lobby, Dachaufbau."""
        tone = rng.choice(glass_cols)
        b.box("Buildings", "Tower", (w, h, d), (x, h / 2, z), color, "Concrete")
        b.box("Decor", "TowerLobby", (w + 0.4, 5.2, d + 0.4), (x, BASE + 2.6, z), (30, 36, 42), "Glass")
        y = 9.5
        while y < h - 4:
            b.box("Decor", "TowerWindows", (w + 0.3, 2.6, d + 0.3), (x, y, z), tone, "Glass")
            y += 5.5
        b.box("Buildings", "TowerTop", (w - 8, 3.4, d - 8), (x, h + 1.7, z), lighten(color, -0.25), "Concrete")
        if h > 70:
            b.box("Decor", "TowerAntenna", (0.6, 16, 0.6), (x + w / 4, h + 8, z), (200, 200, 205), "Metal")
            b.box("Decor", "TowerBeacon", (0.9, 0.9, 0.9), (x + w / 4, h + 16.4, z), (255, 40, 30), "Neon")

    def windows_for(face, w, d, n_face=2):
        along = w if face in "NS" else d
        offs = [-along / 2 + 6, along / 2 - 6] if n_face == 2 else [0]
        return {face: offs}

    def opposite(face):
        return {"N": "S", "S": "N", "E": "W", "W": "E"}[face]

    def shop(x, z, w, d, face, color=None, sign=None, upstairs=0.2):
        """Zweistöckiges Geschäft mit Schild über der Tür, Kisten unten (und manchmal oben)."""
        color = color or rng.choice(shop_cols)
        title, subtitle, sign_col, kinds = sign or rng.choice(signs)
        name = nm("Shop")
        sides = {"N": [-w / 4, w / 4], "S": [-w / 4, w / 4], "E": [-d / 4, d / 4], "W": [-d / 4, d / 4]}
        b.building2(name, x, z, w, d, color, lighten(color, -0.35), doors={face: [0]},
                    windows1={face: windows_for(face, w, d)[face], opposite(face): [0]},
                    windows2=sides, stairs_at=("E",) if face == "W" else ("W",))
        wall_sign(name + "Sign", title, subtitle, x, z, face, w, d, 9.6, sign_col, width=min(16, (w if face in "NS" else d) - 4))
        spot(kinds[0], *into(face, x, z, (d if face in "NS" else w) / 2 - 7))
        if rng.random() < upstairs:
            spot(rng.choice(("Wood", "Wood", "Toolbox", "Medical")), x, z, 10.5)

    def apartment(x, z, w, d, face):
        color = rng.choice(house_cols)
        name = nm("Apartment")
        sides = {"N": [-w / 4, w / 4], "S": [-w / 4, w / 4], "E": [-d / 4, d / 4], "W": [-d / 4, d / 4]}
        b.building2(name, x, z, w, d, color, lighten(color, -0.35), doors={face: [0]},
                    windows1={face: windows_for(face, w, d)[face], opposite(face): [0]}, windows2=sides,
                    stairs_at=("E",) if face == "W" else ("W",), material="Brick" if rng.random() < 0.4 else "Concrete")
        if rng.random() < 0.3:
            spot(rng.choice(("Wood", "Wood", "Medical", "Toolbox")), x, z, BASE if rng.random() < 0.5 else 10.5)

    def house(x, z, w, d, face, h=9):
        color = rng.choice(house_cols)
        back = opposite(face)
        b.flat_house(nm("House"), x, z, w, d, h, color, doors={face: [0]},
                     windows={face: windows_for(face, w, d)[face], back: [0]}, parapet=(),
                     roof_color=lighten(color, -0.35))
        if rng.random() < 0.2:
            spot(rng.choice(("Wood", "Wood", "Wood", "Toolbox", "Medical")), x, z)

    def yard_tree(x, z):
        b.box("Ground", "Yard", (9, 0.1, 9), (x, BASE + 0.05, z), (92, 110, 70), "Grass")
        tree_at(x, z, BASE)

    def dumpster(x, z, yaw=0):
        b.box("Cover", "Dumpster", (6, 3.4, 3.4), (x, BASE + 1.7, z), (50, 90, 60), "Metal", angles=(0, yaw, 0))

    LOTS = ((-28, -28), (28, -28), (-28, 28), (28, 28))

    def fill_downtown(bx, bz):
        slab(bx, bz)
        shop_lot = rng.randrange(4)
        for k, (ox, oz) in enumerate(LOTS):
            x, z = bx + ox, bz + oz
            face = face_to_street(ox, oz)
            if k == shop_lot:
                w, d = (44, 32) if face in "NS" else (32, 44)
                shop(x, z, w, d, face, upstairs=0.4)
            else:
                tower(x, z, rng.uniform(30, 44), rng.uniform(30, 44), rng.uniform(40, 105), rng.choice(tower_cols))
        dumpster(bx + rng.choice((-1, 1)) * 4, bz + rng.uniform(-30, 30), 90)

    def fill_midtown(bx, bz):
        slab(bx, bz)
        for ox, oz in LOTS:
            x, z = bx + ox, bz + oz
            face = face_to_street(ox, oz)
            w, d = (42, 32) if face in "NS" else (32, 42)
            r = rng.random()
            if r < 0.4:
                shop(x, z, w, d, face)
            elif r < 0.8:
                apartment(x, z, w, d, face)
            elif r < 0.9:
                tower(x, z, rng.uniform(30, 40), rng.uniform(30, 40), rng.uniform(28, 50), rng.choice(tower_cols))
            else:  # Hinterhof mit Autos und Müll
                car(x - 8, z, 0, rng.choice(car_cols), y=BASE)
                car(x + 8, z + 4, 10, rng.choice(car_cols), y=BASE)
                dumpster(x, z - 14)
                spot("Wood", x, z + 16)

    def fill_residential(bx, bz, big=False):
        slab(bx, bz)
        if big:  # zwei große Häuser mit Garten
            lots = ((-26, 0), (26, 0)) if rng.random() < 0.5 else ((0, -26), (0, 26))
            for ox, oz in lots:
                x, z = bx + ox, bz + oz
                face = face_to_street(ox, oz)
                w, d = (40, 28) if face in "NS" else (28, 40)
                # Haus zur Straße gerückt, Garten dahinter
                sx, sz = into(face, x, z, -4)
                house(sx, sz, w, d, face, h=rng.choice((9, 10, 12)))
                gx, gz = into(face, x, z, 24)
                if abs(gx - bx) < 52 and abs(gz - bz) < 52:
                    yard_tree(gx, gz)
            return
        for ox, oz in LOTS:
            x, z = bx + ox, bz + oz
            face = face_to_street(ox, oz)
            if rng.random() < 0.12:
                yard_tree(x - 6, z - 6)
                yard_tree(x + 8, z + 7)
                continue
            w, d = (36, 26) if face in "NS" else (26, 36)
            house(x, z, w, d, face, h=rng.choice((9, 9, 10, 12)))

    def fill_park(bx, bz):
        slab(bx, bz, (92, 112, 70), "Grass", "Park")
        b.box("Ground", "ParkPath", (SLAB, 0.1, 6), (bx, BASE + 0.05, bz), (170, 160, 140), "Pavement")
        b.box("Ground", "ParkPath", (6, 0.1, SLAB), (bx, BASE + 0.05, bz), (170, 160, 140), "Pavement")
        b.cylinder("Decor", "FountainBase", 14, 1.6, (bx, BASE + 0.8, bz), (130, 128, 122), material="Concrete")
        b.cylinder("Decor", "FountainWater", 11, 0.4, (bx, BASE + 1.5, bz), (60, 100, 120), material="Glass",
                   props={"Transparency": 0.3})
        b.cylinder("Decor", "FountainColumn", 1.6, 5, (bx, BASE + 3.4, bz), (150, 148, 142), material="Concrete")
        for _ in range(14):
            x, z = bx + rng.uniform(-50, 50), bz + rng.uniform(-50, 50)
            if abs(x - bx) > 8 and abs(z - bz) > 8:
                tree_at(x, z, BASE)
        for k in range(4):
            a = math.radians(45 + 90 * k)
            b.box("Cover", "Bench", (5, 1.2, 1.6), (bx + math.cos(a) * 14, BASE + 0.6, bz + math.sin(a) * 14), (110, 80, 56),
                  "WoodPlanks", angles=(0, -math.degrees(a) + 90, 0))
        spot("Wood", bx + 20, bz - 20)

    def fill_parking(bx, bz):
        slab(bx, bz, (70, 72, 76), "Asphalt", "Parking")
        for row in (-30, 0, 30):
            for k in range(-4, 5):
                b.box("Ground", "ParkingLine", (0.4, 0.05, 10), (bx + k * 11, BASE + 0.03, bz + row), (220, 220, 220), "SmoothPlastic")
                if rng.random() < 0.45 and k < 4:
                    car(bx + k * 11 + 5.5, bz + row, rng.uniform(-6, 6), rng.choice(car_cols), y=BASE)
        b.box("Cover", "ParkingBooth", (5, 7, 5), (bx - 50, BASE + 3.5, bz - 50), (190, 180, 160), "Concrete")
        spot("Toolbox", bx - 44, bz - 50)
        spot("Wood", bx + 40, bz + 44)

    # ---------- Besondere Gebäude ----------
    def fence_line(x0, z0, x1, z1, gaps=(), color=(150, 156, 160)):
        """Maschendrahtzaun mit Pfosten von (x0, z0) nach (x1, z1) (achsparallel); gaps = Mitten von 16 breiten Toren."""
        along_x = z0 == z1
        a, bnd = (x0, x1) if along_x else (z0, z1)
        cuts = sorted(gaps)
        pos = min(a, bnd)
        end = max(a, bnd)
        pieces = []
        for g in cuts:
            pieces.append((pos, g - 8))
            pos = g + 8
        pieces.append((pos, end))
        for p0, p1 in pieces:
            if p1 - p0 < 1:
                continue
            mid, length = (p0 + p1) / 2, p1 - p0
            if along_x:
                b.box("Walls", "ChainFence", (length, 9, 0.3), (mid, BASE + 4.5, z0), color, "DiamondPlate", props={"Transparency": 0.55})
            else:
                b.box("Walls", "ChainFence", (0.3, 9, length), (x0, BASE + 4.5, mid), color, "DiamondPlate", props={"Transparency": 0.55})
            t = p0
            while t <= p1 + 0.1:
                px, pz = (t, z0) if along_x else (x0, t)
                b.box("Walls", "FencePost", (0.8, 10, 0.8), (px, BASE + 5, pz), (80, 84, 88), "Metal")
                t += 20

    def watchtower(x, z, h=16):
        for dx in (-2.5, 2.5):
            for dz in (-2.5, 2.5):
                b.box("Decor", "TowerLeg", (0.9, h, 0.9), (x + dx, BASE + h / 2, z + dz), (80, 84, 88), "Metal")
        b.box("Buildings", "TowerDeck", (8, 0.6, 8), (x, BASE + h + 0.3, z), (90, 94, 98), "DiamondPlate")
        b.box("Cover", "TowerWall", (8, 3, 0.4), (x, BASE + h + 2, z - 4), (90, 94, 98), "Metal")
        b.box("Decor", "TowerRoof", (8.6, 0.4, 8.6), (x, BASE + h + 5.4, z), (70, 76, 62), "Metal")
        b.box("Decor", "TowerLamp", (1.2, 1.2, 1.2), (x, BASE + h + 4.6, z), (255, 236, 200), "Neon",
              children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                  "Face": "Bottom", "Range": 40, "Brightness": 1.4, "Angle": 70, "Color": rgb(255, 236, 210)}}])

    def tent(x, z, yaw, color):
        f = frame(x, z, yaw)
        b.box("Decor", "TentFloor", (8, 0.2, 10), f(0, BASE + 0.1, 0), (70, 70, 64), "Fabric", angles=(0, yaw, 0))
        b.add("Decor", "Tent", (8, 5, 5), f(0, BASE + 2.5, -2.5), color, "Fabric", angles=(0, yaw, 0), cls="WedgePart")
        b.add("Decor", "Tent", (8, 5, 5), f(0, BASE + 2.5, 2.5), color, "Fabric", angles=(0, yaw + 180, 0), cls="WedgePart")

    def build_police(bx, bz):
        slab(bx, bz)
        b.building2("PoliceHQ", bx, bz + 18, 72, 34, (150, 160, 176), (60, 70, 90), doors={"S": [-12, 12]},
                    windows1={"S": [-28, 0, 28], "N": [-24, 0, 24], "E": [0], "W": [0]},
                    windows2={"S": [-28, -12, 12, 28], "N": [-24, 0, 24], "E": [-8, 8], "W": [-8, 8]}, stairs_at=("W", "E"))
        wall_sign("PoliceSign", "POLIZEI", "PRÄSIDIUM ÖDSTADT", bx, bz + 18, "S", 72, 34, 9.6, (90, 140, 230), width=16)
        spot("Ammo", bx - 18, bz + 22)
        spot("Ammo", bx + 18, bz + 22)
        spot("Medical", bx, bz + 26)
        spot("Military", bx - 14, bz + 22, 10.5)
        spot("Toolbox", bx + 14, bz + 22, 10.5)
        b.flat_house("PoliceGarage", bx + 38, bz - 34, 28, 20, 8, (130, 134, 142), doors={"W": [0]}, windows={"S": [0]},
                     roof_color=(70, 76, 90))
        spot("Toolbox", bx + 36, bz - 34)
        for k, (cx_, cz_) in enumerate(((bx - 40, bz - 30), (bx - 24, bz - 34), (bx - 8, bz - 30))):
            car(cx_, cz_, rng.uniform(-8, 8), (60, 90, 150), y=BASE)
            b.box("Cover", "PoliceStripe", (5.7, 0.8, 11.2), (cx_, BASE + 2.2, cz_), (236, 236, 240), "SmoothPlastic")
        for k in range(4):
            b.barrier(bx - 45 + k * 12, bz - 52, along_x=True, length=8)

    def build_townhall(bx, bz):
        slab(bx, bz)
        b.building2("Rathaus", bx, bz + 10, 64, 36, (196, 186, 166), (96, 70, 60), doors={"S": [0]},
                    windows1={"S": [-22, -12, 12, 22], "N": [-16, 0, 16], "E": [0], "W": [0]},
                    windows2={"S": [-22, -8, 8, 22], "N": [-16, 0, 16], "E": [-8, 8], "W": [-8, 8]}, stairs_at=("W", "E"))
        for px in (-15, -5, 5, 15):
            b.cylinder("Decor", "Column", 2.2, 18, (bx + px, BASE + 9, bz - 10), (220, 214, 200), material="Concrete")
        b.box("Decor", "Portico", (36, 1.6, 6), (bx, BASE + 18.6, bz - 10), (210, 204, 190), "Concrete")
        wall_sign("RathausSign", "RATHAUS", "STADT ÖDSTADT", bx, bz + 10, "S", 64, 36, 21.5, (226, 178, 52), width=16)
        b.cylinder("Decor", "FlagPole", 0.5, 22, (bx - 26, BASE + 11, bz - 30), (200, 200, 205))
        b.box("Decor", "Flag", (7, 4, 0.2), (bx - 22.2, BASE + 19.5, bz - 30), (226, 178, 52), "Fabric")
        spot("Toolbox", bx - 18, bz + 16)
        spot("Wood", bx + 18, bz + 16)
        spot("Medical", bx, bz + 18, 10.5)

    def build_mall(bx, bz):
        slab(bx, bz)
        mx, mz, w, d = bx, bz + 8, 100, 72
        b.flat_house("Mall", mx, mz, w, d, 14, (206, 200, 188), doors={"N": [-30, 0, 30], "S": [0], "W": [0], "E": [0]},
                     windows={"N": [-42, -16, 16, 42], "S": [-30, 30]}, roof_color=(150, 60, 50), trim=(200, 60, 50))
        wall_sign("MallSign", "EINKAUFSZENTRUM", "ÖDLAND-GALERIE · 60 GESCHÄFTE", mx, mz, "N", w, d, 16.6, (200, 70, 60), width=26)
        for row in (-18, -4, 10, 24):
            for col in (-30, 0, 30):
                b.box("Cover", "Shelf", (18, 5, 2.4), (mx + col, BASE + 2.5, mz + row), (120, 110, 100), "WoodPlanks")
        spot("Wood", mx - 40, mz + 28)
        spot("Wood", mx + 40, mz - 26)
        spot("Medical", mx - 15, mz + 3)
        spot("Toolbox", mx + 15, mz + 17)
        spot("Ammo", mx + 42, mz + 28)
        for k in range(5):
            car(bx - 44 + k * 22, bz - 46, 90 + rng.uniform(-8, 8), rng.choice(car_cols), y=BASE)

    def build_school(bx, bz):
        slab(bx, bz)
        b.building2("School", bx - 20, bz, 34, 88, (196, 160, 120), (120, 70, 50), doors={"E": [-20, 20]},
                    windows1={"E": [-34, 0, 34], "W": [-30, -10, 10, 30]}, windows2={"E": [-34, -20, 0, 20, 34], "W": [-30, 0, 30]},
                    stairs_at=("S",), material="Brick")
        wall_sign("SchoolSign", "GESAMTSCHULE", "ÖDSTADT · SEIT 1962", bx - 20, bz, "E", 34, 88, 9.6, (230, 200, 90), width=16)
        spot("Wood", bx - 26, bz - 28)
        spot("Medical", bx - 26, bz + 30)
        spot("Toolbox", bx - 16, bz, 10.5)
        b.box("Ground", "Court", (30, 0.1, 50), (bx + 30, BASE + 0.05, bz), (160, 90, 60), "SmoothPlastic")
        b.box("Ground", "CourtLine", (30, 0.12, 0.5), (bx + 30, BASE + 0.06, bz), (240, 240, 240), "SmoothPlastic")
        for s in (-1, 1):
            b.box("Decor", "HoopPole", (0.5, 10, 0.5), (bx + 30, BASE + 5, bz + s * 25), (80, 80, 84), "Metal")
            b.box("Decor", "HoopBoard", (6, 3.6, 0.3), (bx + 30, BASE + 10.4, bz + s * 24.6), (230, 230, 230), "SmoothPlastic")

    def build_church(bx, bz):
        slab(bx, bz)
        kx, kz = bx + 20, bz
        b.house("Church", kx, kz, 20, 40, 15, (192, 186, 172), (96, 62, 52), doors=("E", "S"), material="Brick")
        b.box("Buildings", "ChurchTower", (9, 30, 9), (kx, 15, kz + 24.5), (186, 180, 166), "Brick")
        for w, yy in ((10, 31.5), (7, 34.5), (4.4, 37.5), (2, 41)):
            b.box("Buildings", "Spire", (w, 3.4, w), (kx, yy, kz + 24.5), (70, 52, 46), "Slate", angles=(0, 45, 0))
        b.box("Decor", "SpireCrossV", (0.5, 4, 0.5), (kx, 45, kz + 24.5), (220, 200, 120), "Metal")
        b.box("Decor", "SpireCrossH", (2, 0.5, 0.5), (kx, 45.6, kz + 24.5), (220, 200, 120), "Metal")
        for k in range(4):
            b.box("Cover", "Pew", (12, 1.4, 1.2), (kx, BASE + 0.7, kz - 10 + k * 5), (96, 70, 50), "WoodPlanks")
        spot("Wood", kx - 5, kz + 12)
        spot("Medical", kx + 5, kz - 15)
        b.box("Ground", "Graveyard", (52, 0.1, 100), (bx - 32, BASE + 0.05, bz), (88, 104, 68), "Grass")
        for row in range(6):
            for col in range(5):
                b.box("Cover", "Gravestone", (1.5, 2.4, 0.5), (bx - 52 + col * 9, BASE + 1.2, bz - 40 + row * 15),
                      (150, 150, 146), "Slate", angles=(0, rng.uniform(-8, 8), 0))
        for k in range(3):
            b.box("Nature", "DeadTrunk", (1.2, 9, 1.2), (bx - 50 + k * 18, BASE + 4.5, bz + 46), (60, 50, 44), "Wood",
                  angles=(rng.uniform(-6, 6), 0, rng.uniform(-6, 6)))
        spot("Wood", bx - 24, bz + 42)

    def build_gas(bx, bz):
        slab(bx, bz, (90, 90, 94), "Concrete", "FuelLot")
        b.box("Buildings", "FuelRoof", (40, 1, 24), (bx + 10, 10, bz), (200, 60, 50), "Metal")
        for dx in (-16, 16):
            for dz in (-9, 9):
                b.box("Buildings", "FuelPillar", (1.2, 9.5, 1.2), (bx + 10 + dx, BASE + 4.7, bz + dz), (220, 220, 220), "Metal")
        for dx in (-6, 6):
            b.box("Cover", "FuelPump", (2, 4.6, 3), (bx + 10 + dx, BASE + 2.3, bz), (220, 220, 220), "SmoothPlastic")
        b.flat_house("FuelShop", bx - 34, bz, 22, 30, 9, (210, 206, 196), doors={"E": [0]}, windows={"E": [-9, 9], "N": [0]},
                     roof_color=(200, 60, 50))
        b.sign("FuelSign", (12, 4, 0.4), (bx + 10, 14, bz - 12.2), "TANKSTELLE", (200, 60, 50), (250, 250, 250))
        spot("Toolbox", bx - 36, bz - 6)
        spot("Ammo", bx - 36, bz + 8)
        spot("Wood", bx + 30, bz + 30)
        car(bx + 4, bz - 6, 0, (90, 110, 70), y=BASE)

    def build_hospital():
        x0, x1, z0, z1 = 430, 690, 430, 550
        hx, hz = (x0 + x1) / 2, (z0 + z1) / 2
        b.box("Ground", "HospitalGround", (x1 - x0, BASE, z1 - z0), (hx, BASE / 2, hz), (150, 150, 146), "Concrete")
        white = (226, 228, 226)
        mx, mz = hx, hz + 20
        b.building2("Hospital", mx, mz, 110, 34, white, (150, 160, 170), doors={"S": [-30, 0, 30]},
                    windows1={"S": [-46, -15, 15, 46], "N": [-40, -20, 0, 20, 40], "E": [0], "W": [0]},
                    windows2={"S": [-46, -30, -15, 0, 15, 30, 46], "N": [-40, -20, 0, 20, 40], "E": [-8, 8], "W": [-8, 8]},
                    stairs_at=("W", "E"))
        b.box("Decor", "HospitalCrossV", (1.8, 7, 0.2), (mx, 15, mz - 17.6), (220, 40, 40), "Neon")
        b.box("Decor", "HospitalCrossH", (7, 1.8, 0.2), (mx, 15, mz - 17.6), (220, 40, 40), "Neon")
        wall_sign("HospitalSign", "ST. MARIEN", "KRANKENHAUS · NOTAUFNAHME 24 H", mx, mz, "S", 110, 34, 22.4, (220, 70, 70), width=24)
        b.floor_text("RoofHelipad", (14, 0.1, 14), (mx + 30, 20.2, mz), "H", (236, 236, 236), bg=(70, 72, 76))
        for k in range(5):
            b.box("Cover", "HospitalBed", (2.6, 1.4, 6), (mx - 40 + k * 20, BASE + 0.7, mz + 10), (210, 214, 222), "SmoothPlastic")
        for sx in (-34, -12, 12, 34):
            spot("Medical", mx + sx, mz)
        for sx in (-30, 0, 30):
            spot("Medical", mx + sx, mz + 4, 10.5)
        spot("Military", mx - 10, mz + 10, 10.5)
        spot("Toolbox", mx + 48, mz - 8)
        for k, (ax, az, yaw) in enumerate(((mx - 50, z0 + 16, 80), (mx - 26, z0 + 14, 100), (mx + 66, z0 + 18, 70))):
            car(ax, az, yaw, (232, 232, 232), y=BASE)
            b.box("Cover", "AmbulanceStripe", (5.7, 0.7, 11.2), (ax, BASE + 2.2, az), (200, 40, 40), "SmoothPlastic",
                  angles=(0, yaw, 0))
        spot("Medical", mx - 38, z0 + 22)
        for k in range(4):
            tent(mx + 4 + k * 12, z0 + 16, 0, (230, 230, 226))
        spot("Medical", mx + 22, z0 + 26)
        spot("Ammo", mx + 40, z0 + 32)
        for x in (x0 + 12, x1 - 12):
            b.barrier(x, z0 + 6, along_x=True, length=8)

    def build_military():
        x0, x1, z0, z1 = -690, -430, 430, 690
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        b.box("Ground", "MilitaryGround", (x1 - x0, BASE, z1 - z0), (cx, BASE / 2, cz), (110, 112, 100), "Concrete")
        fence_line(x0 + 4, z0 + 4, x1 - 4, z0 + 4, gaps=(cx,))
        fence_line(x0 + 4, z1 - 4, x1 - 4, z1 - 4)
        fence_line(x0 + 4, z0 + 4, x0 + 4, z1 - 4)
        fence_line(x1 - 4, z0 + 4, x1 - 4, z1 - 4, gaps=(cz,))
        for gx, gz in ((cx, z0 + 4), (x1 - 4, cz)):
            for s in (-1, 1):
                if gz == z0 + 4:
                    b.barrier(gx + s * 5, gz - 8, along_x=True, length=6)
                else:
                    b.barrier(gx + 8, gz + s * 5, along_x=False, length=6)
        for wx_, wz_ in ((x0 + 12, z0 + 12), (x1 - 12, z1 - 12), (x0 + 12, z1 - 12), (x1 - 12, z0 + 12)):
            watchtower(wx_, wz_)
        for k, (bx_, bz_) in enumerate(((cx - 70, cz + 60), (cx - 70, cz + 20), (cx - 70, cz - 20))):
            b.flat_house("Barracks%d" % k, bx_, bz_, 44, 16, 9, (98, 106, 86), doors={"E": [0]},
                         windows={"E": [-14, 14], "W": [-12, 0, 12]}, roof_color=(70, 76, 62))
            spot("Military", bx_ - 10, bz_)
            spot("Medical" if k == 1 else "Ammo", bx_ + 12, bz_)
        b.building2("MilitaryHQ", cx + 50, cz + 70, 56, 28, (110, 116, 98), (70, 76, 62), doors={"S": [0]},
                    windows1={"S": [-18, 18], "N": [-14, 14]}, windows2={"S": [-18, 0, 18], "N": [-14, 14], "E": [0], "W": [0]},
                    stairs_at=("W",))
        wall_sign("MilitarySign", "KOMMANDO", "SPERRGEBIET · SCHUSSWAFFENGEBRAUCH", cx + 50, cz + 70, "S", 56, 28, 9.6, (215, 85, 45), width=18)
        spot("Military", cx + 40, cz + 74)
        spot("Military", cx + 58, cz + 74, 10.5)
        spot("Toolbox", cx + 64, cz + 64)
        for k in range(6):
            b.container(cx + 20 + (k % 3) * 12, cz - 60 + (k // 3) * 26, along_x=False, color=rng.choice(((90, 110, 76), (70, 86, 64), (110, 96, 70))))
        b.container(cx + 20, cz - 60, along_x=False, level=1, color=(80, 100, 70))
        spot("Military", cx + 60, cz - 50)
        spot("Ammo", cx + 6, cz - 66)
        b.box("Cover", "TankHull", (10, 3.6, 16), (cx + 10, BASE + 1.8, cz + 10), (84, 92, 70), "CorrodedMetal", angles=(0, 20, 0))
        b.box("Cover", "TankTurret", (6.4, 2.4, 7), (cx + 10, BASE + 4.6, cz + 10), (78, 86, 66), "CorrodedMetal", angles=(0, 35, 0))
        look = (-math.sin(math.radians(35)), -math.cos(math.radians(35)))
        b.add("Decor", "TankBarrel", (11, 0.9, 0.9), (cx + 10 + look[0] * 8, BASE + 4.8, cz + 10 + look[1] * 8),
              (70, 76, 60), "Metal", angles=(0, 125, 0), props={"Shape": "Cylinder"})
        b.add("Ground", "Helipad", (0.3, 26, 26), (cx + 60, BASE + 0.1, cz + 10), (70, 72, 76), "Concrete", angles=(0, 0, 90),
              props={"Shape": "Cylinder"})
        b.floor_text("MilHelipadH", (10, 0.1, 10), (cx + 60, BASE + 0.3, cz + 10), "H", (236, 236, 236))
        for k in range(6):
            b.box("Cover", "Sandbags", (8, 3, 2.4), (cx - 40 + k * 14, BASE + 1.5, z0 + 30), (150, 134, 98), "Fabric",
                  angles=(0, rng.uniform(-8, 8), 0))
        for k in range(3):
            tent(cx - 10 + k * 14, cz + 40, 90, (96, 108, 78))
        spot("Ammo", cx + 4, cz + 46)

    def build_industry():
        x0, x1, z0, z1 = 430, 690, -690, -430
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        b.box("Ground", "IndustryGround", (x1 - x0, BASE, z1 - z0), (cx, BASE / 2, cz), (96, 96, 98), "Concrete")
        fence_line(x0 + 4, z1 - 4, x1 - 4, z1 - 4, gaps=(cx,))
        fence_line(x0 + 4, z0 + 4, x1 - 4, z0 + 4)
        fence_line(x0 + 4, z0 + 4, x0 + 4, z1 - 4, gaps=(cz,))
        fence_line(x1 - 4, z0 + 4, x1 - 4, z1 - 4)
        for k, (wx_, wz_) in enumerate(((cx - 60, cz + 60), (cx + 50, cz + 60), (cx - 60, cz - 30))):
            b.flat_house("Warehouse%d" % k, wx_, wz_, 64, 40, 14, (120, 122, 126), doors={"S": [-16, 16], "N": [0]},
                         windows={"E": [-10, 10], "W": [-10, 10]}, roof_color=(84, 86, 90))
            spot("Toolbox", wx_ - 18, wz_ + 6)
            spot(("Military", "Wood", "Ammo")[k], wx_ + 18, wz_ - 6)
        b.building2("IndustryOffice", cx + 60, cz - 40, 36, 24, (150, 146, 136), (90, 88, 84), doors={"W": [0]},
                    windows1={"W": [-10, 10], "E": [0]}, windows2={"W": [-10, 0, 10], "N": [0], "S": [0]}, stairs_at=("E",))
        spot("Military", cx + 56, cz - 36)
        spot("Ammo", cx + 60, cz - 44, 10.5)
        for k in range(10):
            b.container(cx - 90 + (k % 5) * 24, cz - 100 + (k // 5) * 12, along_x=True, level=0, length=20,
                        color=rng.choice(((150, 60, 50), (60, 100, 150), (170, 130, 60), (80, 120, 80))))
        b.container(cx - 90, cz - 100, along_x=True, level=1, color=(150, 60, 50))
        b.container(cx - 18, cz - 88, along_x=True, level=1, color=(60, 100, 150))
        spot("Toolbox", cx - 30, cz - 114)
        spot("Wood", cx + 10, cz - 76)
        for k in range(3):
            b.cylinder("Buildings", "FuelTank", 16, 18, (cx + 100, BASE + 9, cz - 100 + k * 22), (200, 200, 196))
        b.box("Buildings", "CraneTower", (3, 50, 3), (cx + 20, BASE + 25, cz + 10), (210, 170, 50), "Metal")
        b.box("Buildings", "CraneArm", (56, 2.4, 2.4), (cx + 4, BASE + 50, cz + 10), (210, 170, 50), "Metal")
        b.box("Decor", "Chimney", (7, 46, 7), (cx - 110, BASE + 23, cz + 110), (130, 110, 100), "Brick")

    # ---------- Stadt füllen ----------
    special_done = set()
    for bx in centers:
        for bz in centers:
            kind = block_kind(bx, bz)
            ring = max(abs(bx), abs(bz))
            if kind is None:
                if ring <= 210:
                    fill_downtown(bx, bz)
                elif ring <= 350:
                    fill_midtown(bx, bz)
                elif ring <= 490:
                    fill_residential(bx, bz)
                else:
                    fill_residential(bx, bz, big=True)
            elif kind in special_done or kind == "Plaza":
                continue
            elif kind == "Park":
                fill_park(bx, bz)
            elif kind == "Parkplatz":
                fill_parking(bx, bz)
            else:
                if kind in ("Krankenhaus", "Militaer", "Industrie"):
                    special_done.add(kind)
                {"Polizei": build_police, "Rathaus": build_townhall, "Einkaufszentrum": build_mall, "Schule": build_school,
                 "Kirche": build_church, "Tankstelle": build_gas}.get(kind, lambda *_: None)(bx, bz)
    build_hospital()
    build_military()
    build_industry()
    # Platz um die Safe Zone (vier Blöcke ohne Gehweg-Kante)
    b.box("Ground", "PlazaFloor", (2 * P - ST, 0.1, 2 * P - ST), (0, 0.05, 0), (150, 146, 138), "Pavement")
    for sx in (-1, 1):
        for sz in (-1, 1):
            for k in range(3):  # Pflanzkübel mit Bäumen in den Ecken des Platzes
                b.cylinder("Decor", "Planter", 7, 1.2, (sx * (110 - k * 3), 0.6, sz * (110 - 12 * k)), (120, 116, 110), material="Concrete")
                tree_at(sx * (110 - k * 3), sz * (110 - 12 * k), 1.2)
            b.box("Cover", "Bench", (6, 1.2, 1.6), (sx * 92, 0.6, sz * 118), (110, 80, 56), "WoodPlanks")

    def ground_y(x, z):
        """Oberkante des Bodens an einer Stelle (Gehweg, Anlage, Straße, Platz, Gelände)."""
        if abs(x) > C + ST or abs(z) > C + ST:
            return H(x, z)
        if abs(x) < P - ST / 2 and abs(z) < P - ST / 2:
            return 0.1
        for x0_, x1_, z0_, z1_ in ((430, 690, 430, 550), (-690, -430, 430, 690), (430, 690, -690, -430)):
            if x0_ <= x <= x1_ and z0_ <= z <= z1_:
                return BASE
        bx = min(centers, key=lambda c: abs(c - x))
        bz = min(centers, key=lambda c: abs(c - z))
        if abs(x - bx) <= SLAB / 2 and abs(z - bz) <= SLAB / 2:
            return BASE
        return 0.13

    # ---------- Wracks und Sperren auf den Straßen ----------
    placed = 0
    for _ in range(600):
        if placed >= 80:
            break
        line = rng.choice(lines)
        t = rng.uniform(-C + 14, C - 14)
        if abs(t - round(t / P) * P) < ST:  # nicht auf Kreuzungen
            continue
        vertical = rng.random() < 0.5
        x, z = (line + rng.choice((-5, 5)), t) if vertical else (t, line + rng.choice((-5, 5)))
        if in_safe(x, z, 50) or ground_y(x, z) != 0.13:
            continue
        yaw = (0 if vertical else 90) + rng.uniform(-30, 30)
        car(x, z, yaw, rng.choice(car_cols))
        placed += 1
    for x, z, along in ((0, 400, True), (-280, 300, False), (420, -150, True), (150, -420, False), (-560, -150, True),
                        (280, 560, False), (-420, 230, True)):
        for k in (-1, 1):
            b.barrier(x + (k * 5 if along else 0), z + (0 if along else k * 5), along_x=along, length=8)

    # ---------- Safe Zone: grüner Leuchtring am Boden ----------
    n = 72
    for k in range(n):
        a = 2 * math.pi * (k + 0.5) / n
        b.box("Zone", "SafeEdge", (2 * math.pi * (R - 1) / n + 0.2, 0.12, 1.4), (math.cos(a) * (R - 1), 0.24, math.sin(a) * (R - 1)),
              safe, "Neon", angles=(0, -math.degrees(a) + 90, 0),
              props={"Transparency": 0.25, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    # ---------- Rote Zonen: rot-weiße Linie am Boden und Kontrollpunkte an jeder Straße ----------
    def checkpoint(x, z, along_x, rx, rz, title):
        """Kontrollpunkt an der Grenze einer roten Zone auf einer Straße: Sperren, Torbogen mit Schildern, rotes Licht."""
        out_dir = (x - rx, z - rz)
        if along_x:   # Straße läuft entlang x: Torbogen quer (entlang z)
            yaw_out = -90 if out_dir[0] > 0 else 90
        else:
            yaw_out = 180 if out_dir[1] > 0 else 0
        f = frame(x, z, yaw_out)
        gy = 0.13
        for s in (-1, 1):
            b.box("Walls", "CheckpointPost", (1.2, 12, 1.2), f(s * (ST / 2 + 1), gy + 6, 0), (40, 40, 44), "Metal", angles=(0, yaw_out, 0))
            b.barrier(*f(s * 6.5, 0, -4)[0::2], along_x=not along_x, length=6)
        b.box("Walls", "CheckpointBeam", (ST + 4, 1.4, 1.2), f(0, gy + 12.4, 0), red, "Metal", angles=(0, yaw_out, 0))
        b.sign2("RedzoneSignOut", (16, 3.4, 0.3), f(0, gy + 15, -0.5), "ROTE ZONE", title + " · PVP SOFORT · BESSERE BEUTE",
                (40, 16, 14), red, (240, 230, 228), angles=(0, yaw_out, 0), glow=red)
        b.sign2("RedzoneSignIn", (16, 3.4, 0.3), f(0, gy + 15, 0.5), "AUSGANG", "ROTE ZONE ENDE", (24, 28, 26), safe,
                (230, 235, 230), angles=(0, yaw_out + 180, 0), glow=safe)
        b.box("Decor", "CheckpointLight", (2, 0.8, 0.8), f(0, gy + 11.4, 0), (255, 50, 40), "Neon", angles=(0, yaw_out, 0),
              children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 34, "Brightness": 1.6,
                                                                                      "Color": rgb(255, 60, 50)}}])

    road_segments = []  # (vertikal, Linie, von, bis) aller gebauten Stadtstraßen (für Kontrollpunkte)
    for line in lines:
        for t in lines[:-1]:
            if not (line == 0 and -P <= t < P):
                if segment_free(True, line, t):
                    road_segments.append((True, line, t, t + P))
                if segment_free(False, line, t):
                    road_segments.append((False, line, t, t + P))
    for s in (-1, 1):
        road_segments.append((True, 0, min(s * C, s * half), max(s * C, s * half)))
        road_segments.append((False, 0, min(s * C, s * half), max(s * C, s * half)))

    for key, radius in EXT_REDZONES.items():
        title, rx, rz, _ = EXT_PLACES[key]
        b.add("Redzones", "Redzone_" + key, (2 * radius, 120, 2 * radius), (rx, 60, rz), red, "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False,
                     "Attributes": {"Attributes": {"Title": {"String": title}}}})
        n = int(2 * math.pi * radius / 6)
        for k in range(n):
            a = 2 * math.pi * (k + 0.5) / n
            px, pz = rx + math.cos(a) * radius, rz + math.sin(a) * radius
            if abs(px) > half - 10 or abs(pz) > half - 10:
                continue
            b.box("Redzones", "RedLine", (2 * math.pi * radius / n + 0.1, 0.1, 1.6), (px, ground_y(px, pz) + 0.07, pz),
                  red if k % 2 == 0 else (236, 236, 236), "SmoothPlastic", angles=(0, -math.degrees(a) + 90, 0),
                  props={"CanCollide": False, "CanQuery": False, "CanTouch": False})
        for vertical, line, t0, t1 in road_segments:
            d = line - (rx if vertical else rz)
            if abs(d) >= radius:
                continue
            off = math.sqrt(radius * radius - d * d)
            for sgn in (-1, 1):
                t = (rz if vertical else rx) + sgn * off
                if t0 + ST < t < t1 - ST:
                    x, z = (line, t) if vertical else (t, line)
                    checkpoint(x, z, not vertical, rx, rz, title)

    # ---------- Orte (Banner beim Betreten, Weltkarte) ----------
    for key, (title, x, z, r) in EXT_PLACES.items():
        b.add("Places", "Place_" + key, (2 * r, 4, 2 * r), (x, 2, z), (255, 255, 255), "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False,
                     "Attributes": {"Attributes": {"Title": {"String": title}}}})

    # ---------- Außerhalb: Stadtgrenze, Bauernhof, See, Funkturm, Wald ----------
    def board(title, subtitle, x, z, yaw, color, width=14, bg=(26, 26, 28)):
        g = H(x, z)
        f = frame(x, z, yaw)
        for side in (-1, 1):
            b.box("Decor", "BoardPost", (0.5, 7.4, 0.5), f(side * (width / 2 - 0.6), g + 3.5, 0), (70, 62, 54), "Wood", angles=(0, yaw, 0))
        b.sign2("Board_" + title[:14], (width, 3.6, 0.3), f(0, g + 7.6, 0), title, subtitle, bg, color, (230, 230, 230),
                angles=(0, yaw, 0), glow=color)

    for s in (-1, 1):
        for vertical in (True, False):
            x, z = (14, s * (C + 40)) if vertical else (s * (C + 40), 14)
            board("ÖDSTADT", "STADTGRENZE · BETRETEN AUF EIGENE GEFAHR", x, z, facing(x, z, x * 3, z * 3),
                  (226, 178, 52))

    fx, fz = EXT_PLACES["Bauernhof"][1:3]
    b.house("Barn", fx, fz, 36, 26, 14, (150, 56, 46), (80, 72, 66), doors=("N", "E"), material="WoodPlanks")
    b.cylinder("Buildings", "Silo", 10, 26, (fx + 30, 13, fz + 4), (176, 176, 170))
    b.add("Buildings", "SiloTop", (10, 10, 10), (fx + 30, 26, fz + 4), (150, 150, 146), "Metal", props={"Shape": "Ball"})
    for k in range(2):
        px, pz = fx - 40 + k * 64, fz + 60
        b.box("Ground", "Field", (56, 0.1, 40), (px, 0.06, pz), (96, 74, 52), "Ground")
        for r_ in range(5):
            b.box("Nature", "Crops", (52, 1.2, 1.4), (px, 0.7, pz - 16 + r_ * 8), (120, 140, 60), "Grass", props={"CanCollide": False})
    for k in range(5):
        b.cylinder("Cover", "HayBale", 3.6, 4, (fx - 24 + k * 5, 1.8, fz - 26), (200, 176, 96), material="Fabric")
    b.flat_house("Farmhouse", fx + 50, fz - 40, 24, 18, 8, (176, 150, 120), doors={"N": [0]}, windows={"S": [-6, 6], "E": [0]},
                 roof_color=(130, 60, 50))
    spot("Wood", fx - 8, fz - 5, 0)
    spot("Toolbox", fx - 8, fz + 5, 0)
    spot("Medical", fx + 46, fz - 40, 0)

    lx, lz = EXT_PLACES["Schwarzsee"][1:3]
    b.box("Decor", "BoatHull", (4.6, 1.6, 13), (lx + 8, H(lx + 8, lz) + 3.8, lz + 4), (96, 70, 52), "WoodPlanks",
          angles=(rng.uniform(-6, 6), rng.uniform(0, 180), rng.uniform(-8, 8)))
    reeds = 0
    for _ in range(300):
        ang = rng.uniform(0, 2 * math.pi)
        for dist in range(30, 220, 4):
            rx_, rz_ = lx + math.cos(ang) * dist, lz + math.sin(ang) * dist
            if not terrain.is_water(rx_, rz_):
                if abs(rx_) < half - 40 and abs(rz_) < half - 40 and not on_road(rx_, rz_, 6):
                    for _k in range(4):
                        sx_, sz_ = rx_ + rng.uniform(-2, 2), rz_ + rng.uniform(-2, 2)
                        b.box("Nature", "Reed", (0.4, rng.uniform(3, 5), 0.4), (sx_, H(sx_, sz_) + 1.6, sz_), (100, 130, 70), "Grass",
                              props={"CanCollide": False})
                    reeds += 1
                break
        if reeds >= 30:
            break

    tx0, tz0 = EXT_PLACES["Funkturm"][1:3]
    g0 = H(tx0, tz0)
    b.box("Buildings", "TowerBase", (30, 6, 26), (tx0 - 8, g0 - 2.4, tz0 - 6), (110, 108, 102), "Concrete")
    base = g0 + 0.6
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.box("Buildings", "TowerLegLow", (0.9, 26, 0.9), (tx0 + sx * 4, base + 13, tz0 + sz * 4), (200, 200, 205), "Metal")
            b.box("Buildings", "TowerLegHigh", (0.7, 22, 0.7), (tx0 + sx * 2.2, base + 37, tz0 + sz * 2.2), (200, 60, 50), "Metal")
    for lv in range(1, 6):
        wd = 8.8 - lv * 0.95
        yy = base + lv * 8
        for dx_, dz_, sx_, sz_ in ((0, wd / 2, wd + 0.6, 0.5), (0, -wd / 2, wd + 0.6, 0.5), (wd / 2, 0, 0.5, wd + 0.6), (-wd / 2, 0, 0.5, wd + 0.6)):
            b.box("Buildings", "TowerRing", (sx_, 0.5, sz_), (tx0 + dx_, yy, tz0 + dz_), (200, 200, 205), "Metal")
    b.box("Buildings", "TowerMast", (0.5, 14, 0.5), (tx0, base + 55, tz0), (200, 200, 205), "Metal")
    b.box("Decor", "TowerBeacon", (1.2, 1.2, 1.2), (tx0, base + 62.6, tz0), (255, 40, 30), "Neon",
          children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 60, "Brightness": 1.5, "Color": rgb(255, 60, 40)}}])
    b.flat_house("RadioBunker", tx0 - 18, tz0 - 8, 16, 12, 6, (110, 112, 108), y0=g0 + 0.6, doors={"E": [0]}, windows={"N": [0]},
                 roof_color=(80, 82, 80))
    spot("Military", tx0 - 20, tz0 - 8, g0 + 0.6)
    spot("Ammo", tx0 - 15, tz0 - 6, g0 + 0.6)

    def free(x, z, pad=12):
        if on_road(x, z, pad):
            return False
        for key in ("Bauernhof", "Funkturm"):
            _, px, pz, pr = EXT_PLACES[key]
            if math.hypot(x - px, z - pz) < pr + 20:
                return False
        if H(x, z) < et.WATER + 2.5 or terrain.slope(x, z) > 0.62:
            return False
        return abs(x) < half - 24 and abs(z) < half - 24

    placed, tries = 0, 0
    while placed < 300 and tries < 30000:
        tries += 1
        x, z = rng.uniform(-half + 30, half - 30), rng.uniform(-half + 30, half - 30)
        density = terrain.noise.fbm(x / 120.0 + 40, z / 120.0 - 20, 3)
        if rng.random() > (0.95 if density > 0.5 else 0.12):
            continue
        if free(x, z):
            tree_at(x, z)
            placed += 1
    placed = 0
    for _ in range(3000):
        if placed >= 50:
            break
        x, z = rng.uniform(-half + 40, half - 40), rng.uniform(-half + 40, half - 40)
        if free(x, z, 14) and (terrain.slope(x, z) > 0.3 or rng.random() < 0.15):
            rock_at(x, z)
            placed += 1
    placed = 0
    for _ in range(400):
        if placed >= 12:
            break
        x, z = rng.uniform(-half + 60, half - 60), rng.uniform(-half + 60, half - 60)
        if free(x, z, 16) and all(math.hypot(x - ox_, z - oz_) > 12 for ox_, oz_ in obstacles):
            ground_spot(rng.choice(("Wood", "Wood", "Toolbox")), x, z)
            placed += 1
    for s in (-1, 1):  # Wracks auf den Landstraßen
        for k in range(3):
            d = C + 60 + k * 80
            car(rng.choice((-5, 5)), s * d, rng.uniform(-25, 25), rng.choice(car_cols))
            car(s * d, rng.choice((-5, 5)), 90 + rng.uniform(-25, 25), rng.choice(car_cols))
    print("Extinction: Kisten", spot_count, "gesamt", sum(spot_count.values()))

    b.save("Extinction.model.json", "Ödstadt", atmosphere="Wasteland")


if __name__ == "__main__":
    build_altstadt()  # Free-for-All (früher "Raffinerie": build_ffa)
    # Herrschaft spielt auf "Kraftwerk" (früher "Tal": build_drop). Team Deathmatch ist ausgebaut; zum
    # Wiedereinbauen eine Kopie ohne Flaggen erzeugen: build_kraftwerk(TDM_ORIGIN, "TDM.model.json", flags=False). Wingman-Rotation: Fabrik, Hochhaus, Gletscher,
    # Zellenblock, Kanäle, Windmühlen. Ausgebaute Modi (Strikeout, Demolition, Ranked, Extraction)
    # brauchen ihre Kopien nicht mehr: build_demolition(), build_strikeout() usw. bleiben zum Wiedereinbauen.
    build_kraftwerk(DROP_ORIGIN, "Domination.model.json")
    # Rotation mit Abstimmung: FFA Altstadt / Favela / Orbit, Herrschaft Kraftwerk / Lagune / Mondbasis
    build_favela()
    build_orbit()
    build_lagune()
    build_mondbasis()
    build_strikeout(WINGMAN_ORIGIN, "Wingman.model.json")
    build_training()
    build_arena()
    build_glacier()
    build_cellblock()
    build_canals((-3000, 0, 1500), "Kanaele.model.json")
    build_windmills((4500, 0, 0), "Windmuehlen.model.json")
    build_hightower((-4500, 0, 0), "Hochhaus.model.json")
    build_lobby()
    build_market()
    build_extinction()

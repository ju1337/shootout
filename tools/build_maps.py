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


class Builder:
    def __init__(self, origin=(0, 0, 0)):
        self.groups = {}
        self.origin = origin

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

    def spawn(self, x, z, yaw=0, real=False, group="Spawns"):
        """real=True: echte SpawnLocation (nur im Hub). Sonst unsichtbarer Spawnpunkt für die Modus-Logik."""
        if real:
            self.add(group, "Spawn", (6, 1, 6), (x, 0.5, z), (255, 140, 40), "Neon", angles=(0, yaw, 0),
                     cls="SpawnLocation", props={"Transparency": 0.6, "Neutral": True, "Duration": 0,
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
                "Font": "GothamBlack",
                "TextColor3": rgb(*fg),
            },
        }
        gui = {"Name": "SignGui", "ClassName": "SurfaceGui", "Properties": {"Face": "Front"}, "Children": [label]}
        self.box("Decor", name, size, pos, bg, "SmoothPlastic", angles=angles, children=[gui])

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
    """Raffinerie: Tanklager mit Brücken (zweite Ebene), Rohrbrücken, Kontrollhäuser."""
    b = Builder(FFA_ORIGIN)
    size = 180
    steel, pipe, tank, concrete = (90, 96, 104), (160, 120, 60), (205, 205, 200), (120, 122, 126)
    cyl = {"Shape": "Cylinder"}
    b.ground(size + 10, size + 10, concrete, "Concrete")
    b.border(size, size, 14, (110, 105, 100), "Brick", barrier=120)
    # Bodenmarkierungen
    for x in (-45, 45):
        b.box("Ground", "Lane", (0.6, 0.05, 160), (x, 0.03, 0), (230, 190, 40), "SmoothPlastic")

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
    for x, z, length, ax in ((0, -24, 30, True), (0, 24, 30, True)):
        # Geländer an der Innenseite, damit die Rampen außen frei ankommen
        b.box("Buildings", "Railing", (length, 1.2, 0.3), (x, top + 1.2, z - 2 if z > 0 else z + 2), (220, 180, 40), "Metal")
    # Rampen hoch aufs Tanklager (Norden und Süden)
    # Oberes Ende direkt an der Brücke (z = ±26), unteres Ende vor den Kontrollhäusern
    b.ramp("TankRampN", 0, 26, 6, 30, top + 0.6, "N")
    b.ramp("TankRampS", 0, -26, 6, 30, top + 0.6, "S")

    # Rohrbrücken an Ost- und Westseite (Deckung darunter)
    for x in (-62, 62):
        for z in range(-60, 61, 20):
            b.box("Buildings", "PipeSupport", (1.2, 7, 1.2), (x, 3.5, z), steel, "Metal")
        for dx in (-1.6, 0, 1.6):
            b.add("Buildings", "Pipe", (124, 1.4, 1.4), (x + dx, 7.6, 0), pipe, "Metal", angles=(0, 90, 0), props=cyl)

    # Kontrollhäuser
    b.house("ControlN", 0, 72, 30, 16, 11, (150, 155, 160), (60, 65, 70), doors=("S", "E", "W"), material="Concrete")
    b.house("ControlS", 0, -72, 30, 16, 11, (150, 155, 160), (60, 65, 70), doors=("N", "E", "W"), material="Concrete")

    # Container und Kisten
    for x, z, w, d, color in ((-35, 55, 16, 8, (70, 110, 150)), (35, -55, 16, 8, (150, 70, 60)),
                              (-80, -30, 8, 16, (90, 130, 80)), (80, 30, 8, 16, (160, 120, 50))):
        b.box("Cover", "Container", (w, 8, d), (x, 4, z), color, "Metal")
    for x, z in ((-45, 20), (45, -20), (-45, -45), (45, 45), (-12, 45), (12, -45), (-75, 65), (75, -65)):
        b.crate(x, z, color=(150, 120, 80))
    for x, z, length, ax in ((-30, 0, 12, False), (30, 0, 12, False), (-20, 50, 10, True), (20, -50, 10, True)):
        b.cover_wall(x, z, length, along_x=ax, height=5)

    # Spawns an den Rändern (Blick zur Mitte)
    for x, z in ((-82, 0), (82, 0), (0, -84), (0, 84), (-82, -40), (82, 40), (40, -84), (-40, 84)):
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

    # Stadt in der Mitte: begehbare Häuser
    houses = (
        (-55, -55, 24, 20, 12, ("N", "E")), (55, 55, 24, 20, 12, ("S", "W")),
        (-55, 55, 22, 22, 12, ("S", "E")), (55, -55, 22, 22, 12, ("N", "W")),
        (0, -95, 30, 18, 14, ("N",)), (0, 95, 30, 18, 14, ("S",)),
        (-100, -25, 18, 24, 11, ("E", "W")), (100, 25, 18, 24, 11, ("E", "W")),
    )
    colors = ((180, 160, 120), (160, 100, 80), (200, 190, 170), (140, 130, 120))
    for i, (x, z, w, d, h, doors) in enumerate(houses):
        b.house(f"House{i}", x, z, w, d, h, colors[i % len(colors)], (80, 60, 55), doors=doors)

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


# ---------- Strikeout: "Fabrik" (220 x 150), Team Gold bei -x, Team Lila bei +x ----------

def build_strikeout(origin=STRIKEOUT_ORIGIN, filename="Strikeout.model.json"):
    b = Builder(origin)
    sx, sz = 220, 150
    b.ground(sx + 10, sz + 10, (105, 100, 95), "Concrete")
    b.border(sx, sz, 14, (90, 85, 80), "Brick", barrier=120)

    # Team-Spawns gegenüber, Blick zur Mitte (Ordner SpawnsA = Gold, SpawnsB = Lila)
    for side, group, color in ((-1, "SpawnsA", (200, 120, 40)), (1, "SpawnsB", (130, 70, 180))):
        b.box("Ground", "SpawnPad", (24, 0.3, 50), (side * 96, 0.15, 0), color, "SmoothPlastic")
        for z in (-15, -5, 5, 15):
            b.spawn(side * 98, z, yaw=90 * side, group=group)  # Blick zur Mitte
        # Container als Deckung vor dem Spawn
        b.box("Cover", "Container", (8, 8, 20), (side * 78, 4, -28), color, "Metal")
        b.box("Cover", "Container", (8, 8, 20), (side * 78, 4, 28), color, "Metal")

    # Eroberungspunkt in der Mitte (Farbe setzt der Server je nach Team)
    b.add("Objective", "CapturePoint", (0.3, 24, 24), (0, 0.2, 0), (230, 230, 235), "Neon",
          angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.35, "CanCollide": False})
    for x, z in ((-12, -12), (12, -12), (-12, 12), (12, 12)):
        b.box("Objective", "PointPost", (1, 5, 1), (x, 2.5, z), (60, 60, 65), "Metal")

    # Deckung um den Punkt: L-förmige Mauern
    for x, z in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        b.cover_wall(x * 20, z * 16, 10, along_x=True, height=4.5)
        b.cover_wall(x * 25, z * 11, 10, along_x=False, height=4.5)
    b.crate(0, -24)
    b.crate(0, 24)

    # Gebäude an den Längsseiten (Flanken)
    b.house("NorthHall", 0, 56, 36, 20, 12, (150, 140, 125), (70, 60, 55), doors=("S", "E", "W"))
    b.house("SouthHall", 0, -56, 36, 20, 12, (150, 140, 125), (70, 60, 55), doors=("N", "E", "W"))
    # Rampen auf die Hallendächer (erhöhte Positionen wie in RC-Maps)
    b.ramp("RoofRampN", 19, 60, 6, 24, 12.5, "E")
    b.ramp("RoofRampS", -19, -60, 6, 24, 12.5, "W")

    # Seitengassen mit Kisten und Mauern
    for side in (-1, 1):
        b.cover_wall(side * 50, 0, 16, along_x=False, height=6)
        b.crate(side * 50, -24)
        b.crate(side * 50, 24)
        b.crate(side * 45, 45, s=6)
        b.crate(side * 45, -45, s=6)
        b.cover_wall(side * 62, 52, 14, height=6)
        b.cover_wall(side * 62, -52, 14, height=6)

    b.save(filename)


# ---------- Demolition: "Hafen" (260 x 180), Angreifer bei -x, Ziele A/B bei +x ----------

def build_demolition(origin=DEMOLITION_ORIGIN, filename="Demolition.model.json"):
    b = Builder(origin)
    sx, sz = 260, 180
    b.ground(sx + 10, sz + 10, (80, 82, 88), "Asphalt")
    b.border(sx, sz, 12, (110, 100, 90), "Brick", barrier=120)
    # Wasserkante an der Nordseite (nur Optik)
    b.box("Ground", "Water", (sx, 0.4, 14), (0, 0.05, sz / 2 - 7), (40, 90, 140), "Glass",
          props={"Transparency": 0.3})

    # Spawns: Angreifer ganz links, Verteidiger zwischen den Zielen (Blick zur Mitte)
    b.box("Ground", "AttackPad", (20, 0.3, 50), (-118, 0.15, 0), (200, 80, 80), "SmoothPlastic")
    for z in (-15, -5, 5, 15):
        b.spawn(-118, z, yaw=-90, group="SpawnsAtk")
    for x, z in ((100, -10), (100, 10), (108, -20), (108, 20)):
        b.spawn(x, z, yaw=90, group="SpawnsDef")

    # Zielbereiche A (Süden) und B (Norden) mit Schild
    for name, z in (("A", -50), ("B", 50)):
        b.add("Objective", "Site" + name, (0.3, 20, 20), (60, 0.2, z), (255, 80, 80), "Neon",
              angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.6, "CanCollide": False})
        b.box("Decor", "SitePost" + name, (1, 10, 1), (60, 5, z), (60, 60, 65), "Metal")
        b.sign("SiteSign" + name, (6, 6, 0.5), (60, 13, z), name, (25, 25, 30), (255, 90, 90))
        # Deckung direkt am Ziel
        b.box("Cover", "Container", (8, 8, 18), (72, 4, z + (12 if z < 0 else -12)), (60, 110, 160), "Metal")
        b.box("Cover", "Container", (18, 8, 8), (48, 4, z + (-14 if z < 0 else 14)), (180, 90, 50), "Metal")
        b.crate(66, z - 8)
        b.crate(54, z + 8)

    # Lagerhalle in der Mitte (begehbar, Durchgänge in alle Richtungen)
    b.house("Warehouse", -10, 0, 40, 30, 14, (150, 130, 110), (70, 65, 60), doors=("N", "S", "E", "W"))

    # Container-Gassen zwischen Angreifer-Spawn und Mitte
    for x, z, w, d in ((-70, -40, 20, 8), (-70, 40, 20, 8), (-50, -70, 8, 20), (-50, 70, 8, 20),
                       (-85, 0, 8, 16), (25, -20, 8, 14), (25, 20, 8, 14)):
        b.box("Cover", "Container", (w, 8, d), (x, 4, z), (90, 120, 80), "Metal")
    for x, z in ((-95, -30), (-95, 30), (-30, -55), (-30, 55), (10, -75), (10, 75), (90, 0)):
        b.crate(x, z)
    for x, z, length, ax in ((-40, 0, 14, False), (85, -35, 12, True), (85, 35, 12, True), (110, 0, 20, False)):
        b.cover_wall(x, z, length, along_x=ax)
    # Laufsteg über der Container-Gasse mit Rampen an beiden Enden
    b.box("Buildings", "Catwalk", (44, 1, 5), (-52, 9, -22), (80, 85, 90), "DiamondPlate")
    for x in (-74, -30):
        b.box("Buildings", "CatwalkRail", (0.4, 1.2, 5), (x, 10.1, -22), (200, 170, 40), "Metal")
    b.ramp("CatwalkRampW", -74, -22, 5, 20, 9.5, "W")
    b.ramp("CatwalkRampE", -30, -22, 5, 20, 9.5, "E")
    # Rampe auf das Lagerhallendach
    b.ramp("WarehouseRoofRamp", -31, 8, 6, 26, 14.5, "W")
    # Kräne als Orientierung
    for x, z in ((-20, 70), (40, -78)):
        b.box("Decor", "CraneLeg", (2, 30, 2), (x, 15, z), (220, 170, 40), "Metal")
        b.box("Decor", "CraneArm", (2, 2, 30), (x, 31, z), (220, 170, 40), "Metal")

    b.save(filename)


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
    b.ground(100, 80, (55, 50, 70), "SmoothPlastic")
    b.border(90, 70, 12, (90, 60, 140), "SmoothPlastic", barrier=60)
    b.add("Ground", "CenterRing", (0.2, 16, 16), (0, 0.1, 0), (170, 100, 255), "Neon",
          angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.5, "CanCollide": False})
    for side, group in ((-1, "SpawnsA"), (1, "SpawnsB")):
        b.spawn(side * 38, 0, yaw=90 * side, group=group)
        # Deckung gespiegelt
        b.cover_wall(side * 22, side * 12, 10, along_x=False, height=5, color=(120, 90, 170))
        b.cover_wall(side * 10, side * -18, 12, height=5, color=(120, 90, 170))
        b.crate(side * 30, side * -20)
        b.crate(side * 30, side * 20, s=4)
        b.box("Cover", "Pillar", (4, 10, 4), (side * 8, 5, side * 8), (150, 120, 200), "Marble")
    b.save("Arena.model.json")


# ---------- Gemeinsame Ziel-Ordner für Team-Maps ----------
# Jede Rotations-Map bekommt alles, was Demolition UND Strikeout brauchen:
# SpawnsAtk/SpawnsDef + SiteA/SiteB (Demolition), SpawnsA/SpawnsB + CapturePoint (Strikeout).

def team_objectives(b, atk_x, def_x, site_a, site_b, spawn_x=105, site_color=(255, 80, 80)):
    for z in (-15, -5, 5, 15):
        b.spawn(atk_x, z, yaw=-90, group="SpawnsAtk")
        b.spawn(-spawn_x, z, yaw=-90, group="SpawnsA")
        b.spawn(spawn_x, z, yaw=90, group="SpawnsB")
    for x, z in ((def_x, -10), (def_x, 10), (def_x + 8, -20), (def_x + 8, 20)):
        b.spawn(x, z, yaw=90, group="SpawnsDef")
    for name, (x, z) in (("A", site_a), ("B", site_b)):
        b.add("Objective", "Site" + name, (0.3, 20, 20), (x, 0.2, z), site_color, "Neon",
              angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.6, "CanCollide": False})
        b.box("Decor", "SitePost" + name, (1, 10, 1), (x, 5, z), (60, 60, 65), "Metal")
        b.sign("SiteSign" + name, (6, 6, 0.5), (x, 13, z), name, (25, 25, 30), site_color, angles=(0, 90, 0))
    b.add("Objective", "CapturePoint", (0.3, 24, 24), (0, 0.2, 0), (230, 230, 235), "Neon",
          angles=(0, 0, 90), props={"Shape": "Cylinder", "Transparency": 0.35, "CanCollide": False})


# ---------- "Gletscher": Forschungsstation im Eis (Stil: RC "Glacier") ----------

GLACIER_ORIGIN = (3000, 0, 0)


def build_glacier(origin=GLACIER_ORIGIN, filename="Gletscher.model.json"):
    b = Builder(origin)
    rng = random.Random(11)
    snow, ice, module, accent = (235, 240, 245), (170, 215, 240), (200, 205, 210), (230, 110, 40)
    b.ground(250, 190, snow, "Snow")
    b.border(240, 180, 10, (210, 225, 235), "Ice", barrier=120)
    # Eisschollen und Schneewehen als Deckung
    for _ in range(18):
        x, z = rng.uniform(-110, 110), rng.uniform(-80, 80)
        if abs(x) < 95 and not (abs(x) < 20 and abs(z) < 20):
            sx, sz, sy = rng.uniform(5, 10), rng.uniform(4, 9), rng.uniform(3, 6)
            b.box("Cover", "IceBlock", (sx, sy, sz), (x, sy / 2, z), ice, "Glass",
                  angles=(0, rng.uniform(0, 90), rng.uniform(-6, 6)), props={"Transparency": 0.25})
    # Forschungsmodule (begehbar) mit orangen Streifen
    for name, x, z, w, d, doors in (("LabA", 55, -55, 30, 20, ("N", "W")), ("LabB", 55, 55, 30, 20, ("S", "W")),
                                    ("Mess", -40, -50, 24, 18, ("N", "E")), ("Garage", -40, 50, 26, 18, ("S", "E"))):
        b.house(name, x, z, w, d, 10, module, (90, 95, 100), doors=doors, material="Metal")
        b.box("Buildings", name + "_Stripe", (w + 0.2, 1, d + 0.2), (x, 8.5, z), accent, "SmoothPlastic")
    # Rampen auf die Labordächer (erhöhte Positionen an den Zielen)
    b.ramp("LabRampA", 71, -60, 6, 20, 10.5, "E")
    b.ramp("LabRampB", 71, 60, 6, 20, 10.5, "E")
    # Radarkuppel und Antennenmast in der Mitte
    b.add("Buildings", "RadarBase", (4, 18, 18), (0, 2, 32), module, "Metal", angles=(0, 0, 90), props={"Shape": "Cylinder"})
    b.add("Buildings", "RadarDome", (14, 14, 14), (0, 7, 32), (240, 240, 245), "SmoothPlastic", props={"Shape": "Ball"})
    b.box("Buildings", "Mast", (1.5, 34, 1.5), (0, 17, -32), (90, 95, 100), "Metal")
    b.box("Buildings", "MastLight", (2, 2, 2), (0, 34.5, -32), (255, 60, 50), "Neon")
    # Treibstofftanks und Kisten an den Zielen
    for x, z in ((80, -30), (80, 30), (-80, 0)):
        b.add("Cover", "FuelTank", (12, 7, 7), (x, 3.5, z), (220, 200, 60), "Metal", angles=(0, 90, 0),
              props={"Shape": "Cylinder"})
    for x, z in ((40, -30), (40, 30), (20, -60), (20, 60), (-20, -20), (-20, 20), (70, 0)):
        b.crate(x, z, color=(150, 120, 80))
    for x, z, length, ax in ((-60, 0, 16, False), (15, 0, 12, False), (90, -55, 12, True), (90, 55, 12, True)):
        b.cover_wall(x, z, length, along_x=ax, height=5, color=(190, 200, 210))
    team_objectives(b, -110, 98, (55, -40), (55, 40))
    b.save(filename, "Gletscher")


# ---------- "Zellenblock": Gefängnis mit Wachtürmen (Stil: RC "Lockdown") ----------

CELLBLOCK_ORIGIN = (-3000, 0, 0)


def build_cellblock():
    b = Builder(CELLBLOCK_ORIGIN)
    concrete, wall, bars, yard = (150, 148, 140), (120, 118, 112), (60, 62, 66), (110, 112, 108)
    b.ground(240, 180, yard, "Concrete")
    b.border(230, 170, 18, wall, "Concrete", barrier=120)
    # Basketballfeld im Hof (nur Markierung)
    b.box("Ground", "Court", (40, 0.1, 24), (0, 0.06, 0), (170, 90, 50), "SmoothPlastic")
    b.box("Ground", "CourtLine", (0.4, 0.12, 24), (0, 0.08, 0), (240, 240, 240), "SmoothPlastic")
    # Wachtürme in den Ecken
    for x, z in ((-100, -70), (100, -70), (-100, 70), (100, 70)):
        b.box("Buildings", "TowerLeg", (6, 20, 6), (x, 10, z), wall, "Concrete")
        b.box("Buildings", "TowerHut", (10, 6, 10), (x, 23, z), concrete, "Concrete")
        b.box("Buildings", "TowerLight", (2, 1, 2), (x, 26.5, z), (255, 240, 200), "Neon")
    # Zellentrakte: lange Gebäude mit Zellen (Gitter = schmale Stäbe)
    for side in (-1, 1):
        z = side * 55
        b.house("CellBlock" + str(side), 40, z, 60, 18, 11, concrete, (80, 80, 85), doors=("W", "E"), material="Concrete")
        for k in range(-3, 4):
            x = 40 + k * 8
            b.box("Buildings", "CellWall", (0.6, 11, 7), (x, 5.5, z + side * -4), wall, "Concrete")
            for bar in range(5):
                b.box("Buildings", "Bar", (0.25, 8, 0.25), (x - 3 + bar * 1.4, 4, z - side * 0.5), bars, "Metal")
    # Rampen auf die Dächer der Zellentrakte
    b.ramp("CellRoofRampS", 9, -58, 6, 22, 11.5, "W")
    b.ramp("CellRoofRampN", 9, 58, 6, 22, 11.5, "W")
    # Verwaltung und Wäscherei (Ziele)
    b.house("Admin", 70, 0, 22, 26, 12, (165, 160, 150), (70, 70, 75), doors=("W", "N", "S"), material="Brick")
    b.house("Laundry", -45, -25, 22, 16, 10, (160, 165, 170), (70, 70, 75), doors=("E", "N"), material="Concrete")
    b.house("Kitchen", -45, 30, 22, 16, 10, (160, 165, 170), (70, 70, 75), doors=("E", "S"), material="Concrete")
    # Zäune und Deckung im Hof
    for x in (-20, 20):
        b.box("Cover", "Fence", (0.3, 6, 30), (x, 3, 0), (130, 135, 140), "Metal", props={"Transparency": 0.4})
    for x, z in ((-70, 0), (0, -30), (0, 30), (25, -15), (25, 15), (-25, 45), (-25, -45), (95, 0)):
        b.crate(x, z, color=(120, 100, 75))
    for x, z, length, ax in ((-80, -35, 12, True), (-80, 35, 12, True), (5, 0, 8, False)):
        b.cover_wall(x, z, length, along_x=ax, height=5, color=concrete)
    team_objectives(b, -108, 96, (70, -45), (70, 45))
    b.save("Zellenblock.model.json", "Zellenblock")


# ---------- Hub (Lobby): Hangar/Safehouse im Stil der Rogue-Company-Lobby ----------

# Einsatz-Tore an den Hallenwänden (Ids wie in src/shared/Modes.lua): links 4, rechts 4
HUB_GATES_WEST = (
    ("FreeForAll", "FREE-FOR-ALL"), ("TeamDeathmatch", "TEAM DEATHMATCH"), ("Drop", "DROP 5v5"),
    ("Strikeout", "STRIKEOUT 4v4"), ("Demolition", "DEMOLITION"),
)
HUB_GATES_EAST = (
    ("Extraction", "EXTRACTION"), ("Wingman", "WINGMAN 2v2"), ("Ranked", "RANKED"), ("Arena", "1v1 ARENA"),
    ("Training", "TRAINING"),
)
CYAN = (40, 210, 230)


def build_lobby():
    b = Builder(HUB_ORIGIN)
    rng = random.Random(3)
    cyl = {"Shape": "Cylinder"}
    concrete = (118, 122, 128)
    steel = (70, 76, 84)
    wall = (92, 98, 106)

    # Außen: Vorfeld und Rollfeld
    b.ground(260, 300, (62, 64, 68), "Asphalt")
    b.border(250, 290, 3, (90, 90, 95), "Metal", barrier=90)

    # ---------- Halle (innen x -60..60, z -40..50, 30 hoch) ----------
    W, D0, D1, H = 60, -40, 50, 30
    b.box("Ground", "HangarFloor", (2 * W, 0.2, D1 - D0), (0, 0.1, (D0 + D1) / 2), concrete, "Concrete")
    # Gelbe Sicherheitslinien
    for x in (-36, 36):
        b.box("Ground", "SafetyLine", (0.6, 0.05, D1 - D0 - 6), (x, 0.23, (D0 + D1) / 2), (240, 190, 30), "SmoothPlastic")
    b.box("Ground", "SafetyLine", (72, 0.05, 0.6), (0, 0.23, D0 + 6), (240, 190, 30), "SmoothPlastic")
    # Team-Raute in der Mitte
    b.box("Ground", "EmblemOuter", (16, 0.06, 16), (0, 0.24, -8), CYAN, "Neon", angles=(0, 45, 0),
          props={"Transparency": 0.35})
    b.box("Ground", "EmblemInner", (12, 0.08, 12), (0, 0.26, -8), (18, 30, 48), "SmoothPlastic", angles=(0, 45, 0))
    # Wände: Süd geschlossen, Nord mit großem Hallentor
    b.box("Walls", "WallSouth", (2 * W + 4, H, 2), (0, H / 2, D0 - 1), wall, "Metal")
    b.box("Walls", "WallWest", (2, H, D1 - D0), (-W - 1, H / 2, (D0 + D1) / 2), wall, "Metal")
    b.box("Walls", "WallEast", (2, H, D1 - D0), (W + 1, H / 2, (D0 + D1) / 2), wall, "Metal")
    door = 36
    for side in (-1, 1):
        seg = W - door
        b.box("Walls", "WallNorth", (seg + 2, H, 2), (side * (door + seg / 2 + 1), H / 2, D1 + 1), wall, "Metal")
        # Aufgeschobenes Hallentor
        b.box("Walls", "DoorPanel", (14, 24, 1.2), (side * (door + 8), 12, D1 + 3), (130, 135, 140), "CorrodedMetal")
    b.box("Walls", "DoorLintel", (2 * door, H - 24, 2), (0, 24 + (H - 24) / 2, D1 + 1), wall, "Metal")
    # Dach mit Stahlträgern und Deckenlampen
    b.box("Walls", "Roof", (2 * W + 4, 1, D1 - D0 + 4), (0, H + 0.5, (D0 + D1) / 2), (60, 64, 70), "Metal")
    for z in range(D0 + 8, D1, 14):
        b.box("Walls", "Truss", (2 * W, 1.6, 1.2), (0, H - 1.5, z), steel, "Metal")
        for x in (-30, 0, 30):
            b.box("Decor", "CeilingLamp", (8, 0.4, 2), (x, H - 2.6, z), (255, 245, 225), "Neon",
                  children=[{"Name": "Light", "ClassName": "PointLight",
                             "Properties": {"Range": 36, "Brightness": 1.4, "Color": rgb(255, 240, 220)}}])
    for x in (-45, -15, 15, 45):
        b.box("Walls", "Beam", (1.2, 1.6, D1 - D0), (x, H - 3.4, (D0 + D1) / 2), steel, "Metal")

    # Spawn in der Hallenmitte-Süd, Blick zum Hallentor
    b.spawn(0, -26, yaw=180, real=True)

    # ---------- Lineup-Bühne mit Spotlights und Bildschirm ----------
    b.box("Decor", "Stage", (40, 1.2, 10), (0, 0.6, 18), (30, 34, 42), "DiamondPlate")
    b.box("Decor", "StageEdge", (40, 0.2, 0.4), (0, 1.25, 13), CYAN, "Neon")
    for x in (-15, -5, 5, 15):
        b.add("Decor", "Spotlight", (H - 4, 4, 4), (x, (H - 4) / 2 + 1, 18), (255, 250, 235), "Neon", angles=(0, 0, 90),
              props={"Shape": "Cylinder", "Transparency": 0.9, "CanCollide": False, "CanQuery": False})
    b.sign("BriefingScreen", (34, 10, 0.6), (0, 18, 26), "SHOOTOUT", (12, 20, 32), CYAN)
    b.sign("BriefingSub", (34, 2.6, 0.6), (0, 11.6, 26), "TACTICAL OPERATIONS", (12, 20, 32), (235, 242, 248))
    # Einsatz-Tafel (Client zeigt darauf live die Spielerzahlen pro Modus)
    b.box("Decor", "MissionBoard", (26, 14, 0.6), (0, 14, D0 + 0.4), (12, 20, 32), "SmoothPlastic", angles=(0, 180, 0))

    # ---------- Einsatz-Tore an den Seitenwänden ----------
    def gate(x, z, yaw, inward, mode_id, title):
        # inward = Richtung in die Halle (+1 oder -1 auf der x-Achse)
        b.box("Decor", "GateFrameL", (1.2, 16, 1.6), (x, 8, z - 7.4), (30, 34, 42), "Metal", angles=(0, yaw, 0))
        b.box("Decor", "GateFrameR", (1.2, 16, 1.6), (x, 8, z + 7.4), (30, 34, 42), "Metal", angles=(0, yaw, 0))
        b.box("Decor", "GateTop", (1.2, 1.6, 16.4), (x, 16.6, z), (30, 34, 42), "Metal", angles=(0, 0, 0))
        b.box("Decor", "GateGlow", (0.3, 15, 13.4), (x, 7.6, z), CYAN, "ForceField", props={"Transparency": 0.25,
              "CanCollide": False})
        b.box("Decor", "GateStripL", (0.4, 16, 0.4), (x + inward * 0.8, 8, z - 6.8), CYAN, "Neon")
        b.box("Decor", "GateStripR", (0.4, 16, 0.4), (x + inward * 0.8, 8, z + 6.8), CYAN, "Neon")
        b.sign("Sign_" + mode_id, (14, 2.8, 0.4), (x + inward * 0.9, 19.4, z), title, (12, 20, 32), CYAN, angles=(0, yaw, 0))
        b.add("Portals", "Portal_" + mode_id, (7, 0.3, 13), (x + inward * 4.5, 0.4, z), CYAN, "Neon",
              props={"CanCollide": False, "Transparency": 0.55})
    for k, (mode_id, title) in enumerate(HUB_GATES_WEST):
        gate(-W + 0.6, -26 + k * 15.5, -90, 1, mode_id, title)
    for k, (mode_id, title) in enumerate(HUB_GATES_EAST):
        gate(W - 0.6, -26 + k * 15.5, 90, -1, mode_id, title)

    # ---------- Ausstattung: Spinde, Waffenregale, Werkbänke, Kisten ----------
    for x in range(-44, 45, 5):
        if abs(x) > 6:
            b.box("Decor", "Locker", (4.4, 9, 2.4), (x, 4.5, D0 + 1.4), (55, 70, 85), "Metal")
            b.box("Decor", "LockerVent", (3.6, 0.3, 0.1), (x, 7.5, D0 + 2.65), (25, 30, 36), "Metal")
    for x in (-24, 24):
        b.box("Decor", "WeaponRack", (14, 7, 1.2), (x, 3.5, D0 + 6), (40, 44, 52), "Metal")
        for k in range(4):
            b.box("Decor", "RackGun", (0.4, 4.4, 0.6), (x - 5 + k * 3.3, 3.8, D0 + 6.8), (25, 25, 28), "Metal",
                  angles=(0, 0, 8))
    for x, z in ((-40, 38), (40, 38)):
        b.box("Decor", "Workbench", (12, 3.2, 5), (x, 1.6, z), (80, 70, 60), "WoodPlanks")
        b.sign("Monitor", (5, 3, 0.3), (x, 5.2, z + 2.2), "◆ BRIEFING", (12, 20, 32), CYAN, angles=(0, 180, 0))
    for x, z, size in ((-48, 44, 5), (-48, 39, 5), (-43, 44, 4), (48, -34, 5), (43, -34, 4), (48, -29, 4)):
        b.crate(x, z, s=size, color=(110, 95, 70))

    # ---------- Draußen: Rollfeld mit Absetzflugzeug ----------
    b.box("Ground", "Runway", (250, 0.12, 40), (0, 0.06, 112), (45, 47, 52), "Asphalt")
    for x in range(-110, 111, 20):
        b.box("Ground", "RunwayMark", (10, 0.13, 1.2), (x, 0.07, 112), (235, 235, 235), "SmoothPlastic")
    b.box("Ground", "Apron", (80, 0.1, 40), (0, 0.05, 72), (55, 57, 62), "Concrete")
    plane = (150, 158, 150)
    b.add("Decor", "Fuselage", (64, 11, 11), (0, 8, 110), plane, "Metal", angles=(0, 90, 0), props=cyl)
    b.add("Decor", "Nose", (11, 11, 11), (0, 8, 78), plane, "Metal", props={"Shape": "Ball"})
    b.box("Decor", "Cockpit", (6, 2.5, 4), (0, 12, 80), (40, 70, 90), "Glass")
    b.box("Decor", "Wings", (78, 1.4, 13), (0, 10, 106), plane, "Metal")
    b.box("Decor", "TailFin", (1.4, 12, 9), (0, 18, 138), plane, "Metal")
    b.box("Decor", "TailWing", (26, 1.2, 7), (0, 12, 138), plane, "Metal")
    b.box("Decor", "Ramp", (9, 0.6, 12), (0, 3, 146), (90, 95, 92), "DiamondPlate", angles=(-25, 0, 0))
    for x in (-26, -14, 14, 26):
        b.add("Decor", "Engine", (8, 3.6, 3.6), (x, 8, 104), (60, 64, 70), "Metal", angles=(0, 90, 0), props=cyl)
    for x in range(-115, 116, 23):
        b.box("Decor", "RunwayLightPost", (0.6, 3, 0.6), (x, 1.5, 133), (50, 50, 55), "Metal")
        b.add("Decor", "RunwayLight", (1, 1, 1), (x, 3.3, 133), (255, 60, 50), "Neon", props={"Shape": "Ball"})
    # Zaun und Bäume am Rand
    for x in range(-120, 121, 8):
        b.box("Decor", "FencePost", (0.4, 5, 0.4), (x, 2.5, 140), (80, 80, 85), "Metal")
    b.box("Decor", "FenceMesh", (240, 4.4, 0.15), (0, 2.6, 140), (120, 125, 130), "Metal", props={"Transparency": 0.6})
    placed = 0
    while placed < 14:
        x, z = rng.uniform(-115, 115), rng.uniform(-130, -55)
        b.tree(x, z, rng)
        placed += 1

    b.save("Hub.model.json")


if __name__ == "__main__":
    build_ffa()
    build_drop()
    build_strikeout()
    build_strikeout(WINGMAN_ORIGIN, "Wingman.model.json")  # gleiche Map für Wingman (2v2)
    build_demolition()
    build_demolition(RANKED_ORIGIN, "Ranked.model.json")  # gleiche Map für Ranked
    build_training()
    build_arena()
    build_glacier()
    build_glacier((3000, 0, 1500), "Extraktion.model.json")   # Extraction spielt auf dem Gletscher
    build_strikeout((3000, 0, -1500), "TDM.model.json")         # Team Deathmatch auf der Fabrik
    build_cellblock()
    build_lobby()

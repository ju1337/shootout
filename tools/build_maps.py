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

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "maps")

# Mitte jeder Map in der Welt (wie Center in Modes.lua)
HUB_ORIGIN = (0, 0, 0)
FFA_ORIGIN = (0, 0, 1500)
DROP_ORIGIN = (1500, 0, 0)


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

    def spawn(self, x, z, yaw=0, real=False):
        """real=True: echte SpawnLocation (nur im Hub). Sonst unsichtbarer Spawnpunkt für die Modus-Logik."""
        if real:
            self.add("Spawns", "Spawn", (6, 1, 6), (x, 0.5, z), (255, 140, 40), "Neon", angles=(0, yaw, 0),
                     cls="SpawnLocation", props={"Transparency": 0.6, "Neutral": True, "Duration": 0,
                                                 "AllowTeamChangeOnTouch": False, "CanCollide": False})
        else:
            self.add("Spawns", "SpawnPoint", (4, 1, 4), (x, 0.5, z), (90, 160, 255), "SmoothPlastic",
                     angles=(0, yaw, 0), props={"Transparency": 1, "CanCollide": False, "CanQuery": False,
                                                "CanTouch": False})

    def sign(self, name, size, pos, text, bg, fg):
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
        self.box("Decor", name, size, pos, bg, "SmoothPlastic", children=[gui])

    def save(self, filename):
        model = {
            "ClassName": "Model",
            "Children": [{"Name": g, "ClassName": "Folder", "Children": c} for g, c in self.groups.items()],
        }
        os.makedirs(OUT_DIR, exist_ok=True)
        with open(os.path.join(OUT_DIR, filename), "w") as f:
            json.dump(model, f, indent=1)
        print(filename, sum(len(c) for c in self.groups.values()), "Parts")


# ---------- Free-for-All: "Lagerhof" (180 x 180) ----------

def build_ffa():
    b = Builder(FFA_ORIGIN)
    size = 180
    b.ground(size + 10, size + 10, (95, 95, 100), "Concrete")
    b.border(size, size, 18, (140, 120, 100), "Brick", barrier=120)

    # Mittelplattform auf Säulen mit zwei Rampen
    top = 12
    b.box("Buildings", "Platform", (28, 1.5, 28), (0, top - 0.75, 0), (120, 120, 125), "DiamondPlate")
    for sx in (-12, 12):
        for sz in (-12, 12):
            b.box("Buildings", "Pillar", (2.5, top - 1.5, 2.5), (sx, (top - 1.5) / 2, sz), (90, 90, 95), "Concrete")
    for sx in (-13.5, 13.5):
        b.box("Buildings", "Parapet", (1, 3, 28), (sx, top + 1.5, 0), (150, 150, 150), "Concrete")
    b.ramp("RampNorth", 0, 14, 8, 30, top, "N")
    b.ramp("RampSouth", 0, -14, 8, 30, top, "S")

    # Deckung unter der Plattform
    b.crate(-5, 0)
    b.crate(5, 3)
    b.cover_wall(0, -6, 10, height=4)

    # Häuser in den Ecken (Türen zur Mitte und zur Seite)
    for sx in (-1, 1):
        for sz in (-1, 1):
            doors = ("S" if sz > 0 else "N", "W" if sx > 0 else "E")
            b.house(f"House{sx}{sz}", sx * 62, sz * 62, 26, 20, 13, (170, 110, 80), (70, 60, 60), doors=doors)

    # Kisten-Stapel und Deckungsmauern verteilt (symmetrisch)
    for sx, sz in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        b.crate(sx * 30, sz * 40)
        b.crate(sx * 30, sz * 45)
        b.crate(sx * 30, sz * 42.5, y=5, s=4)
        b.crate(sx * 70, sz * 25, s=6)
        b.cover_wall(sx * 45, sz * 15, 16, along_x=False)
        b.cover_wall(sx * 15, sz * 70, 18)
    for sx in (-1, 1):
        b.cover_wall(sx * 60, 0, 12, along_x=False, height=7)
        b.crate(sx * 75, 6)
        b.crate(sx * 75, -6)
        b.crate(sx * 10, 45)
        b.crate(sx * 10, -45)

    # Spawns an den Rändern
    for x, z in ((-82, 0), (82, 0), (0, -82), (0, 82), (-82, -35), (82, 35), (35, -82), (-35, 82)):
        yaw = math.degrees(math.atan2(x, z))  # Blick zur Mitte
        b.spawn(x, z, yaw=yaw)

    b.save("FreeForAll.model.json")


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


# ---------- Hub (Lobby) ----------

# Gleiche Ids/Farben wie in src/shared/Modes.lua
HUB_MODES = (
    ("FreeForAll", "FREE-FOR-ALL", (255, 120, 60), True),
    ("Drop", "DROP 5v5", (80, 160, 255), True),
    ("Arena", "1v1 ARENA", (170, 100, 255), False),
    ("Ranked", "RANKED", (255, 200, 60), False),
)


def build_lobby():
    b = Builder(HUB_ORIGIN)
    rng = random.Random(3)
    accent = (255, 140, 40)
    b.ground(200, 200, (32, 35, 45), "SmoothPlastic")
    b.border(190, 190, 6, (55, 58, 72), "SmoothPlastic", barrier=80)

    # Runder Platz mit Leuchtrand und Brunnen in der Mitte
    cyl = {"Shape": "Cylinder"}
    b.add("Ground", "PlazaRing", (0.2, 74, 74), (0, 0.1, 0), accent, "Neon", angles=(0, 0, 90), props=cyl)
    b.add("Ground", "Plaza", (0.4, 72, 72), (0, 0.2, 0), (60, 63, 78), "Marble", angles=(0, 0, 90), props=cyl)
    b.add("Decor", "FountainBasin", (2, 18, 18), (0, 1.2, 8), (90, 92, 105), "Marble", angles=(0, 0, 90), props=cyl)
    b.add("Decor", "FountainWater", (0.4, 15.5, 15.5), (0, 2.1, 8), (80, 170, 255), "Glass", angles=(0, 0, 90),
          props={"Shape": "Cylinder", "Transparency": 0.3})
    b.box("Decor", "FountainPillar", (2, 7, 2), (0, 4.5, 8), (90, 92, 105), "Marble")
    b.add("Decor", "FountainTop", (3, 3, 3), (0, 8.5, 8), accent, "Neon", props={"Shape": "Ball"})

    # Spawn vorne auf dem Platz, Blick Richtung Portale (+Z)
    b.spawn(0, -22, yaw=180, real=True)

    # Weg vom Platz zu den Portalen
    b.box("Ground", "Path", (150, 0.3, 26), (0, 0.15, 62), (50, 53, 66), "Marble")

    # Portale nebeneinander am Nordende, Vorderseite zeigt zum Platz
    for i, (mode_id, title, color, available) in enumerate(HUB_MODES):
        x = -66 + i * 44
        z = 75
        c = color if available else (90, 92, 105)
        b.box("Decor", "PortalPillarL", (2.5, 18, 2.5), (x - 8, 9, z), c, "Neon" if available else "Metal")
        b.box("Decor", "PortalPillarR", (2.5, 18, 2.5), (x + 8, 9, z), c, "Neon" if available else "Metal")
        b.box("Decor", "PortalTop", (18.5, 2.5, 2.5), (x, 19, z), c, "Neon" if available else "Metal")
        b.box("Decor", "PortalField", (13.5, 16, 0.3), (x, 9, z), color, "ForceField",
              props={"Transparency": 0.2 if available else 0.75, "CanCollide": False})
        # Betretbare Fläche vor dem Portal (löst den Teleport aus)
        b.add("Portals", "Portal_" + mode_id, (14, 0.4, 8), (x, 0.5, z - 6), c, "Neon",
              props={"CanCollide": False, "Transparency": 0.35})
        b.sign("Sign_" + mode_id, (17, 4, 0.5), (x, 23.5, z), title if available else title + " · BALD",
               (20, 22, 30), c)

    # Großes Schild über allem
    b.sign("TitleSign", (70, 14, 1), (0, 40, 92), "SHOOTOUT", (20, 22, 30), accent)

    # Laternen rund um den Platz
    for k in range(10):
        a = math.radians(k * 36 + 18)
        x, z = math.cos(a) * 42, math.sin(a) * 42
        if z > 30:
            continue  # Platz vor den Portalen frei lassen
        b.box("Decor", "LampPost", (0.8, 11, 0.8), (x, 5.5, z), (40, 42, 50), "Metal")
        b.add("Decor", "LampLight", (2.2, 2.2, 2.2), (x, 11.5, z), (255, 225, 160), "Neon",
              props={"Shape": "Ball"},
              children=[{"Name": "Light", "ClassName": "PointLight",
                         "Properties": {"Range": 22, "Brightness": 1.5, "Color": rgb(255, 210, 150)}}])

    # Bänke am Platz
    for x, z, yaw in ((-26, -26, 45), (26, -26, -45), (-36, 0, 90), (36, 0, -90)):
        b.box("Decor", "Bench", (8, 1, 2.5), (x, 1.8, z), (110, 80, 55), "WoodPlanks", angles=(0, yaw, 0))
        b.box("Decor", "BenchLegs", (7, 1.3, 1.5), (x, 0.65, z), (40, 42, 50), "Metal", angles=(0, yaw, 0))

    # Bäume in den hinteren Ecken
    placed = 0
    while placed < 14:
        x, z = rng.uniform(-88, 88), rng.uniform(-88, 30)
        if abs(x) > 55 or z < -55:
            b.tree(x, z, rng)
            placed += 1

    b.save("Hub.model.json")


if __name__ == "__main__":
    build_ffa()
    build_drop()
    build_lobby()

"""Offene Welt EXTINCTION (3200 x 3200): verwüstete Stadt Ödstadt in der Mitte (Safe Zone "Camp Phoenix"), vier Dörfer,
Militärbasis, Industriehafen, Gefängnis, Flugplatz, Krankenhaus, Bauernhöfe, Tankstellen, Funkturm, drei Seen.

Aufruf über tools/build_maps.py (build_extinction). Straßen sind Linienzüge in beliebigen Winkeln; Gebäude werden als
"Prefabs" in einem eigenen Koordinatensystem gebaut (Tür vorne = -Z) und gedreht an die Straße gesetzt (stamp). Alles ist
zerstört: kaputte Mauerkronen, Löcher, eingestürzte Dächer, vernagelte Fenster, Schutt, Brandspuren, Graffiti,
ausgebrannte Autos, Sperren, Feuer und Rauch.

Gruppen der Karte (Server/Client lesen sie): Zone (SafeZone), Spawns, Stands, Portals, Redzones (Redzone_<Name>, Title),
Places (Place_<Name>, Title), Lakes (Lake_<Name>, nur für die Karte), Roads (Road), Ground, Buildings, Cover, Decor,
Nature, Walls, Loot (aus, siehe ContainerService).
"""
import copy
import math
import random

import extinction_terrain as et

ORIGIN = (0, 0, -6000)
SIZE = 3200
HALF = SIZE / 2
SAFE_R = 100
ROAD_W = 20          # Stadtstraßen
HIGHWAY_W = 22       # Landstraßen

# Orte: Schlüssel -> (Titel, x, z, Radius) – Banner beim Betreten (kleinster Ort gewinnt) und Namen auf der Weltkarte
PLACES = {
    "Camp": ("CAMP PHOENIX", 0, 0, 140),
    "Oedstadt": ("ÖDSTADT", 0, 0, 740),
    "Innenstadt": ("INNENSTADT", 0, 0, 320),
    "Krankenhaus": ("ST. MARIEN KRANKENHAUS", 330, 320, 120),
    "Polizei": ("POLIZEIWACHE", -300, 140, 60),
    "Nordheim": ("NORDHEIM", -250, 1150, 240),
    "Sandbach": ("SANDBACH", 1150, 520, 250),
    "Altenfeld": ("ALTENFELD", -1150, -250, 230),
    "Muehldorf": ("MÜHLDORF", 430, -1150, 220),
    "Militaer": ("MILITÄRBASIS FORT EISEN", -1150, 1150, 210),
    "Hafen": ("INDUSTRIEHAFEN", 1130, -1030, 230),
    "Gefaengnis": ("JVA SCHWARZWALD", -1080, -1130, 180),
    "Flugplatz": ("FLUGPLATZ", 1050, 1250, 220),
    "Funkturm": ("FUNKTURM", -560, -760, 70),
    "HofOst": ("BAUERNHOF KRÜGER", 960, -560, 110),
    "HofWest": ("BAUERNHOF LINDE", -880, 720, 110),
    "Schwarzsee": ("SCHWARZSEE", -760, 230, 150),
    "Stausee": ("STAUSEE", 1380, -1280, 170),
    "Teich": ("MÜHLTEICH", 320, 860, 90),
}
# Außenposten auf Hügeln: (Schlüssel, Titel, x, z) – Hügel mit ebener Kuppe, oben ein Lagerhaus, Turm, Zaun, Vorratslager
OUTPOSTS = [("Wolfshoehe", "WOLFSHÖHE", -1380, 820), ("Adlerhorst", "ADLERHORST", 1400, 100), ("Steinkuppe", "STEINKUPPE", -420, -1420),
            ("Kraehenberg", "KRÄHENBERG", 650, 1480), ("Baerenkopf", "BÄRENKOPF", -1420, -720), ("Fuchsbau", "FUCHSBAU", 760, -1460),
            ("HoherStein", "HOHER STEIN", 1460, -380), ("SchwarzerBuckel", "SCHWARZER BUCKEL", -820, 1460),
            ("Kahlenberg", "KAHLENBERG", 1000, 900), ("Rabenstein", "RABENSTEIN", -980, 330)]
for _key, _title, _x, _z in OUTPOSTS:
    PLACES[_key] = (_title, _x, _z, 70)

REDZONES = {"Krankenhaus": 150, "Militaer": 210, "Hafen": 230, "Gefaengnis": 180}
LAKES = [("Schwarzsee", -760, 230, 120, 10), ("Stausee", 1380, -1280, 150, 11), ("Teich", 320, 860, 60, 6)]
# Ebene Flächen (Orte mit Gebäuden): (x, z, Radius)
FLATS = [(0, 0, 760), (-250, 1150, 250), (1150, 520, 260), (-1150, -250, 240), (430, -1150, 230), (-1150, 1150, 230),
         (1130, -1030, 240), (-1080, -1130, 200), (960, -560, 120), (-880, 720, 120)]
# Gepflasterte Flächen (Terrain-Material Pflaster): Stadtkern und Dorfkerne
PAVED = [(0, 0, 720), (-250, 1150, 120), (1150, 520, 130), (-1150, -250, 110), (430, -1150, 100), (1130, -1030, 200),
         (-1150, 1150, 160), (-1080, -1130, 150)]

GRAFFITI = ("HILFE", "SIE SIND DRINNEN", "NICHT REINGEHEN", "EVAKUIERUNG -> CAMP PHOENIX", "TOT", "WIR LEBEN NOCH",
            "KEIN WASSER", "LAUF", "ZONE ROT", "MAMA WIR SIND BEI OMA", "INFIZIERT", "GOTT HAT UNS VERLASSEN", "X")


def dist_point_segment(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / l2))
    return math.hypot(px - (ax + dx * t), pz - (az + dz * t))


def polyline(points, rng, wobble=0.0, step=60.0):
    """Linienzug mit Zwischenpunkten (leicht geschwungen, wenn wobble > 0)."""
    out = [points[0]]
    for (ax, az), (bx, bz) in zip(points, points[1:]):
        length = math.hypot(bx - ax, bz - az)
        n = max(1, int(length // step))
        nx, nz = -(bz - az) / length, (bx - ax) / length
        phase = rng.uniform(0, math.pi * 2)
        for k in range(1, n + 1):
            t = k / n
            w = math.sin(t * math.pi) * math.sin(phase + t * 3) * wobble if k < n else 0
            out.append((ax + (bx - ax) * t + nx * w, az + (bz - az) * t + nz * w))
    return out


def terrain_layout():
    """Höhenfeld: Orte eben, Landstraßen eben eingeschnitten, Seen, Funkturm-Hügel, Bergrand."""
    t = et.Terrain(17)
    t.edge = HALF - 50
    for x, z, r in FLATS:
        t.flat(x, z, r, 90)
    t.flat_rect(780, 1210, 1340, 1290, 70)  # Startbahn
    for points in highway_points():
        for (ax, az), (bx, bz) in zip(points, points[1:]):
            t.road(ax, az, bx, bz, HIGHWAY_W, 70)
    for _, x, z, r, depth in LAKES:
        t.lake(x, z, r, depth)
    t.hill(-560, -760, 170, 30, 40)
    for _, _, x, z in OUTPOSTS:
        t.hill(x, z, 175, 36, 32)
    t.paved = PAVED
    t.build()
    return t


def highway_points():
    """Landstraßen als Linienzüge (ohne Schwung; der kommt in build dazu)."""
    return [
        [(0, 720), (-60, 860), (-250, 1000), (-250, 1150)],                       # Nord
        [(-250, 1150), (-500, 1190), (-900, 1160), (-1020, 1150)],                # Nordheim -> Militär
        [(720, 0), (860, 240), (1000, 460), (1150, 520)],                         # Ost
        [(1150, 520), (1160, 760), (1110, 1050), (1050, 1180)],                   # Sandbach -> Flugplatz
        [(-720, 0), (-860, -110), (-1150, -250)],                                 # West
        [(-1150, -250), (-1160, -560), (-1090, -960)],                            # Altenfeld -> Gefängnis
        [(0, -720), (180, -860), (430, -1150)],                                   # Süd
        [(430, -1150), (720, -1110), (960, -1050)],                               # Mühldorf -> Hafen
        [(1150, 520), (1060, 80), (860, -330), (960, -560)],                      # Sandbach -> Hof Ost
        [(960, -560), (640, -760), (430, -1150)],                                 # Hof Ost -> Mühldorf
        [(-1150, -250), (-1010, 200), (-880, 720), (-250, 1150)],                 # Altenfeld -> Hof West -> Nordheim
        [(-250, 1150), (60, 1060), (320, 900), (760, 1080), (1050, 1180)],        # Nordheim -> Teich -> Flugplatz
        [(-1090, -960), (-800, -1000), (-560, -820)],                             # Gefängnis -> Funkturm
        [(-560, -820), (-200, -780), (180, -800)],                                # Funkturm -> Süd
    ]


class World:
    def __init__(self, bm):
        self.bm = bm
        self.b = bm.Builder(ORIGIN)
        self.rng = random.Random(23)
        self.terrain = terrain_layout()
        self.H = self.terrain.sample
        self.roads = []        # (ax, az, bx, bz, Breite) aller Straßenstücke
        self.occupied = []     # (x, z, Radius) belegter Flächen (Gebäude, Anlagen)
        self.counter = 0

    # ---------- Grundlagen ----------
    def nm(self, prefix):
        self.counter += 1
        return "%s%d" % (prefix, self.counter)

    def prefab(self):
        return self.bm.Builder((0, 0, 0))

    def stamp(self, pb, x, z, yaw, y=0.0):
        """Prefab (Tür vorne = -Z) gedreht um yaw an (x, y, z) in die Karte setzen."""
        m = self.bm.rot(0, yaw, 0)
        ox, oy, oz = self.b.origin
        for group, items in pb.groups.items():
            target = self.b.groups.setdefault(group, [])
            for inst in items:
                inst = copy.deepcopy(inst)
                cf = inst["Properties"]["CFrame"]["CFrame"]
                px, py, pz = cf["position"]
                wx = m[0][0] * px + m[0][2] * pz
                wz = m[2][0] * px + m[2][2] * pz
                cf["position"] = [round(x + wx + ox, 3), round(y + py + oy, 3), round(z + wz + oz, 3)]
                o = cf["orientation"]
                cf["orientation"] = [[round(sum(m[i][k] * o[k][j] for k in range(3)), 6) for j in range(3)] for i in range(3)]
                target.append(inst)

    @staticmethod
    def yaw_to(fx, fz):
        """yaw, mit dem die Vorderseite (-Z) eines Prefabs in Richtung (fx, fz) zeigt."""
        return math.degrees(math.atan2(-fx, -fz))

    def free(self, x, z, r, road_pad=1.0):
        for ox, oz, orr in self.occupied:
            if math.hypot(x - ox, z - oz) < r + orr:
                return False
        for ax, az, bx, bz, w in self.roads:
            if dist_point_segment(x, z, ax, az, bx, bz) < r + w / 2 + road_pad:
                return False
        if abs(x) > HALF - 60 or abs(z) > HALF - 60:
            return False
        if self.terrain.is_water(x, z):
            return False
        return True

    def flat_here(self, x, z, r):
        for dx, dz in ((0, 0), (r, 0), (-r, 0), (0, r), (0, -r)):
            if abs(self.H(x + dx, z + dz) - et.FLAT) > 0.35:
                return False
        return True

    # ---------- Straßen ----------
    def road(self, ax, az, bx, bz, width=ROAD_W, lines=True, sidewalk=False, cracked=True):
        b, rng = self.b, self.rng
        length = math.hypot(bx - ax, bz - az)
        if length < 1:
            return
        dx, dz = (bx - ax) / length, (bz - az) / length
        yaw = math.degrees(math.atan2(-dz, dx))
        cx, cz = (ax + bx) / 2, (az + bz) / 2
        self.roads.append((ax, az, bx, bz, width))
        # Fahrbahn etwas über dem Gelände (das Terrain darf sie nicht verdecken), dunkler Asphalt mit gelber Mitte
        b.box("Roads", "Road", (length + width * 0.5, 0.9, width), (cx, -0.2, cz), (42, 43, 46), "Asphalt", angles=(0, yaw, 0))
        if lines and length > 12:
            b.box("Roads", "CenterLine", (length - 6, 0.02, 0.5), (cx, 0.26, cz), (190, 165, 80), "SmoothPlastic", angles=(0, yaw, 0))
        if sidewalk:
            nx, nz = -dz, dx
            for s in (-1, 1):
                b.box("Ground", "Sidewalk", (length, 0.9, 4), (cx + nx * s * (width / 2 + 2), -0.2, cz + nz * s * (width / 2 + 2)),
                      (128, 126, 120), "Concrete", angles=(0, yaw, 0))
        if cracked and length > 30 and rng.random() < 0.5:
            t = rng.uniform(0.2, 0.8)
            px, pz = ax + (bx - ax) * t, az + (bz - az) * t
            b.box("Roads", "Pothole", (rng.uniform(3, 7), 0.02, rng.uniform(2, 5)), (px + rng.uniform(-4, 4), 0.255, pz + rng.uniform(-4, 4)),
                  (30, 30, 32), "Slate", angles=(0, rng.uniform(0, 180), 0))

    def track(self, points, width=9):
        """Feldweg (Erde) über das Gelände: kurze Stücke folgen der Höhe, auch Hügel hinauf."""
        b = self.b
        pts = []
        for (ax, az), (bx, bz) in zip(points, points[1:]):
            length = math.hypot(bx - ax, bz - az)
            n = max(1, int(length // 14))
            for k in range(n):
                pts.append((ax + (bx - ax) * k / n, az + (bz - az) * k / n))
        pts.append(points[-1])
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            flat = math.hypot(bx - ax, bz - az)
            if flat < 0.5:
                continue
            h0, h1 = self.H(ax, az) + 0.25, self.H(bx, bz) + 0.25
            yaw = math.degrees(math.atan2(-(bz - az), bx - ax))
            roll = math.degrees(math.atan2(h1 - h0, flat))
            b.box("Roads", "Track", (math.hypot(flat, h1 - h0) + 1.5, 0.8, width), ((ax + bx) / 2, (h0 + h1) / 2 - 0.2, (az + bz) / 2),
                  (104, 86, 62), "Ground", angles=(0, yaw, roll))
            self.roads.append((ax, az, bx, bz, width))

    def nearest_highway(self, x, z):
        """Nächster Punkt auf einer Landstraße."""
        best, best_d = None, math.inf
        for ax, az, bx, bz, w in self.roads:
            if w != HIGHWAY_W:
                continue
            dx, dz = bx - ax, bz - az
            l2 = dx * dx + dz * dz or 1
            t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / l2))
            px, pz = ax + dx * t, az + dz * t
            d = math.hypot(px - x, pz - z)
            if d < best_d:
                best, best_d = (px, pz), d
        return best

    def road_line(self, points, width=ROAD_W, **kw):
        for (ax, az), (bx, bz) in zip(points, points[1:]):
            self.road(ax, az, bx, bz, width, **kw)

    # ---------- Kleinzeug und Zerstörung (alles in Weltkoordinaten) ----------
    def rubble(self, x, z, size=6.0, color=(120, 116, 108), n=None, group="Cover", y=None):
        rng = self.rng
        g = self.H(x, z) if y is None else y
        for _ in range(n or rng.randint(2, 4)):
            s = rng.uniform(0.6, 1.0) * size / 3
            self.b.box(group, "Rubble", (s * rng.uniform(0.8, 1.6), s * rng.uniform(0.4, 0.9), s), (x + rng.uniform(-size / 2, size / 2),
                       g + s * 0.25, z + rng.uniform(-size / 2, size / 2)), self.bm.lighten(color, rng.uniform(-0.3, 0.1)),
                       rng.choice(("Concrete", "Slate", "Brick")),
                       angles=(rng.uniform(-30, 30), rng.uniform(0, 360), rng.uniform(-30, 30)))

    def car(self, x, z, yaw, burned=None, group="Cover", y=None, color=None):
        """Autowrack: meist ausgebrannt (schwarz, ohne Glas), schief, Räder fehlen manchmal."""
        b, rng = self.b, self.rng
        burned = rng.random() < 0.55 if burned is None else burned
        g = (self.H(x, z) + 0.4 if y is None else y)
        color = color or rng.choice(((130, 60, 50), (70, 90, 120), (120, 120, 110), (90, 100, 70), (160, 150, 130), (60, 60, 64)))
        body = (40, 36, 34) if burned else self.bm.lighten(color, -0.3)
        tilt = rng.uniform(-5, 5)
        m = self.bm.rot(0, yaw, 0)

        def at(lx, ly, lz):
            return (x + m[0][0] * lx + m[0][2] * lz, g + ly, z + m[2][0] * lx + m[2][2] * lz)

        b.box(group, "CarBody", (5.6, 2.2, 11), at(0, 1.8, 0), body, "CorrodedMetal", angles=(tilt, yaw, rng.uniform(-4, 4)))
        b.box(group, "CarCabin", (5.0, 1.9, 5.4), at(0, 3.8, 0.6), self.bm.lighten(body, -0.25), "CorrodedMetal", angles=(tilt, yaw, 0))
        if not burned:
            b.box(group, "CarGlass", (5.1, 1.3, 4.0), at(0, 3.9, 0.4), (40, 52, 60), "Glass", angles=(tilt, yaw, 0),
                  props={"Transparency": 0.5})
        for sx in (-1, 1):
            for sz in (-1, 1):
                if burned and rng.random() < 0.4:
                    continue
                b.add(group, "CarWheel", (0.9, 2.4, 2.4), at(sx * 2.7, 1.0, sz * 3.6), (24, 24, 26), "Rubber",
                      angles=(0, yaw, 0), props={"Shape": "Cylinder"})

    def fire(self, x, z, y=None, size=5, smoke=False):
        """Brennende Tonne mit Feuer und Licht (nachts wichtig)."""
        g = self.H(x, z) if y is None else y
        children = [{"Name": "Fire", "ClassName": "Fire", "Properties": {"Size": size, "Heat": 9,
                                                                         "Color": self.bm.rgb(255, 140, 40),
                                                                         "SecondaryColor": self.bm.rgb(140, 40, 20)}},
                    {"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 28, "Brightness": 2.2,
                                                                                "Color": self.bm.rgb(255, 150, 60)}}]
        if smoke:
            children.append({"Name": "Smoke", "ClassName": "Smoke", "Properties": {
                "Color": self.bm.rgb(40, 38, 36), "Opacity": 0.35, "RiseVelocity": 9, "Size": 14}})
        self.b.cylinder("Decor", "FireBarrel", 2.4, 3.4, (x, g + 1.7, z), (70, 60, 52), material="CorrodedMetal",
                        props={"Shape": "Cylinder"})
        self.b.box("Decor", "Flames", (1.2, 0.4, 1.2), (x, g + 3.6, z), (255, 120, 40), "Neon",
                   props={"CanCollide": False, "Transparency": 0.4}, children=children)

    def smoke_column(self, x, y, z):
        self.b.box("Decor", "SmokeSource", (2, 1, 2), (x, y, z), (40, 38, 36), "SmoothPlastic",
                   props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False},
                   children=[{"Name": "Smoke", "ClassName": "Smoke", "Properties": {
                       "Color": self.bm.rgb(34, 32, 30), "Opacity": 0.45, "RiseVelocity": 14, "Size": 22}},
                       {"Name": "Fire", "ClassName": "Fire", "Properties": {"Size": 8, "Heat": 12,
                                                                            "Color": self.bm.rgb(255, 130, 40),
                                                                            "SecondaryColor": self.bm.rgb(120, 30, 10)}}])

    def stain(self, x, z, y=None):
        g = self.H(x, z) + 0.42 if y is None else y
        self.b.box("Decor", "BloodStain", (self.rng.uniform(2, 5), 0.03, self.rng.uniform(1.5, 4)), (x, g, z), (80, 16, 14),
                   "SmoothPlastic", angles=(0, self.rng.uniform(0, 180), 0), props={"CanCollide": False, "CanQuery": False})

    def body_bag(self, x, z, yaw):
        g = self.H(x, z) + 0.4
        self.b.box("Decor", "BodyBag", (2, 1, 6), (x, g + 0.5, z), (40, 44, 40), "Fabric", angles=(0, yaw, 0))

    def barricade(self, x, z, yaw, width=22):
        """Straßensperre quer zur Fahrbahn: Betonteile, Sandsäcke, Stacheldraht, Lücke in der Mitte."""
        b, rng = self.b, self.rng
        m = self.bm.rot(0, yaw, 0)
        g = self.H(x, z) + 0.4
        for lx in (-width / 2 + 3, -width / 2 + 9, width / 2 - 9, width / 2 - 3):
            if rng.random() < 0.85:
                px, pz = x + m[0][0] * lx, z + m[2][0] * lx
                kind = rng.random()
                if kind < 0.5:
                    b.box("Cover", "Barrier", (6, 3.2, 1.6), (px, g + 1.6, pz), (165, 162, 155), "Concrete",
                          angles=(0, yaw + rng.uniform(-12, 12), 0))
                else:
                    b.box("Cover", "Sandbags", (6, 2.8, 2.4), (px, g + 1.4, pz), (150, 134, 98), "Fabric",
                          angles=(0, yaw + rng.uniform(-10, 10), 0))
        b.box("Decor", "BarbedWire", (width, 0.3, 0.3), (x, g + 3.6, z), (90, 90, 94), "DiamondPlate", angles=(0, yaw, 0),
              props={"CanCollide": False})

    def graffiti(self, pb, text, pos, size, yaw=0, color=None):
        """Schrift (PermanentMarker) auf einer Fläche; pos/size im Prefab, Vorderseite -Z (yaw dreht)."""
        color = color or self.rng.choice(((200, 30, 30), (230, 230, 230), (20, 20, 20), (230, 200, 60)))
        label = {"Name": "Text", "ClassName": "TextLabel", "Properties": {
            "Size": {"UDim2": [[1, 0], [1, 0]]}, "BackgroundTransparency": 1, "Text": text, "TextScaled": True,
            "Font": "PermanentMarker", "TextColor3": self.bm.rgb(*color), "Rotation": self.rng.uniform(-8, 8)}}
        gui = {"Name": "Graffiti", "ClassName": "SurfaceGui", "Properties": {"Face": "Front", "LightInfluence": 1,
                                                                              "SizingMode": "PixelsPerStud", "PixelsPerStud": 20},
               "Children": [label]}
        pb.add("Decor", "GraffitiPanel", size, pos, (0, 0, 0), "SmoothPlastic", angles=(0, yaw, 0),
               props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False}, children=[gui])

    # ---------- Zerstörte Gebäude (Prefabs, Tür vorne = -Z, Mitte 0/0, Boden y = 0) ----------
    def wall(self, pb, side, w, d, h, color, mat, openings, tops, base=-1.0, t=1.0):
        """Eine Wand mit Öffnungen [(Mitte, Breite, unten, oben)] (unten 0 = ab Boden) und Mauerkrone tops = [(von, bis, Höhe)]
        entlang der Wand. side N/S laufen entlang x, E/W entlang z."""
        if side in ("N", "S"):
            a, bnd = -w / 2, w / 2
        else:
            a, bnd = -d / 2 + t, d / 2 - t
        cuts = {a, bnd}
        for c, width, _, _ in openings:
            cuts.add(max(a, min(bnd, c - width / 2)))
            cuts.add(max(a, min(bnd, c + width / 2)))
        for s0, s1, _ in tops:
            cuts.add(max(a, min(bnd, s0)))
            cuts.add(max(a, min(bnd, s1)))
        cuts = sorted(cuts)
        for p0, p1 in zip(cuts, cuts[1:]):
            if p1 - p0 < 0.05:
                continue
            mid = (p0 + p1) / 2
            top = h
            for s0, s1, th in tops:
                if s0 <= mid <= s1:
                    top = th
            solid = [(base, top)]
            for c, width, lo, hi in openings:
                if c - width / 2 <= mid <= c + width / 2:
                    lo_y = base if lo <= 0 else lo
                    new = []
                    for y0, y1 in solid:
                        if hi <= y0 or lo_y >= y1:
                            new.append((y0, y1))
                            continue
                        if lo_y > y0:
                            new.append((y0, lo_y))
                        if hi < y1:
                            new.append((hi, y1))
                    solid = new
            for y0, y1 in solid:
                if y1 - y0 < 0.1:
                    continue
                length = p1 - p0
                if side == "S":
                    size, pos = (length, y1 - y0, t), (mid, (y0 + y1) / 2, -d / 2 + t / 2)
                elif side == "N":
                    size, pos = (length, y1 - y0, t), (mid, (y0 + y1) / 2, d / 2 - t / 2)
                elif side == "E":
                    size, pos = (t, y1 - y0, length), (w / 2 - t / 2, (y0 + y1) / 2, mid)
                else:
                    size, pos = (t, y1 - y0, length), (-w / 2 + t / 2, (y0 + y1) / 2, mid)
                pb.box("Buildings", "Wall", size, pos, color, mat)

    def boards(self, pb, side, w, d, c, width, lo, hi):
        """Vernageltes Fenster: zwei schräge Bretter in der Öffnung."""
        rng = self.rng
        yaw = 0 if side in ("N", "S") else 90
        for k in range(self.rng.randint(1, 2)):
            y = lo + (hi - lo) * (0.3 + 0.4 * k)
            if side == "S":
                pos = (c, y, -d / 2 - 0.05)
            elif side == "N":
                pos = (c, y, d / 2 + 0.05)
            elif side == "E":
                pos = (w / 2 + 0.05, y, c)
            else:
                pos = (-w / 2 - 0.05, y, c)
            pb.box("Decor", "Board", (width + 0.8, 0.6, 0.2), pos, (120, 92, 64), "WoodPlanks",
                   angles=(0, yaw, rng.uniform(-18, 18)))

    def local_rubble(self, pb, x, z, size, color, n=5, y=0.0):
        rng = self.rng
        for _ in range(n):
            s = rng.uniform(0.5, 1.0) * size / 3
            pb.box("Cover", "Rubble", (s * rng.uniform(0.8, 1.6), s * rng.uniform(0.4, 0.9), s),
                   (x + rng.uniform(-size / 2, size / 2), y + s * 0.2, z + rng.uniform(-size / 2, size / 2)),
                   self.bm.lighten(color, rng.uniform(-0.3, 0.1)), rng.choice(("Concrete", "Slate", "Brick")),
                   angles=(rng.uniform(-30, 30), rng.uniform(0, 360), rng.uniform(-30, 30)))

    def ruin_house(self, w, d, h, color, mat="Concrete", damage=0.5, shop=None, floors_above=0):
        """Verfallenes Haus: Löcher, kaputte Mauerkrone, Dach ganz/teilweise/eingestürzt, vernagelte Fenster, Schutt,
        Graffiti, Brandspuren. shop = (Titel, Unterzeile, Farbe): großes Schaufenster und schiefes Schild.
        floors_above: geschlossene obere Stockwerke (Wohnblock), nur das Erdgeschoss ist begehbar."""
        pb, rng = self.prefab(), self.rng
        roof = "intact" if (damage < 0.35 or floors_above > 0) else rng.choice(("partial", "partial", "none"))
        cut = rng.uniform(-0.1, 0.25) * d  # bei "partial": Dach reicht von cut bis zur Rückwand
        windows = {}
        # vorne: Tür und Fenster (Laden: große Schaufenster)
        front = [(0, 5.5, 0, 7.5)]
        if shop:
            for s in (-1, 1):
                if w >= 18:
                    front.append((s * w / 4 + s * 1.5, max(5, w / 3 - 2), 1.2, 7.2))
        elif w >= 22:
            front += [(-w / 2 + 5, 3.4, 3.2, 6.4), (w / 2 - 5, 3.4, 3.2, 6.4)]
        elif w >= 16:
            front.append((rng.choice((-1, 1)) * (w / 2 - 4.5), 3.4, 3.2, 6.4))
        windows["S"] = front
        windows["N"] = [(0, 3.4, 3.2, 6.4)] if w >= 14 and rng.random() < 0.5 else []
        windows["E"] = [(0, 3.4, 3.2, 6.4)] if d >= 14 and rng.random() < 0.5 else []
        windows["W"] = [(0, 3.4, 3.2, 6.4)] if d >= 14 and rng.random() < 0.5 else []
        # Durchbrüche
        for side in ("S", "N", "E", "W"):
            if rng.random() < damage * 0.35:
                along = (w if side in ("N", "S") else d) / 2 - 4
                if along > 3:
                    windows[side].append((rng.uniform(-along, along), rng.uniform(3, 6), 0, rng.uniform(3.5, h + 1)))
        # Mauerkrone
        tops = {"S": [], "N": [], "E": [], "W": []}
        if roof != "intact":
            for side in ("S", "N", "E", "W"):
                length = w if side in ("N", "S") else d
                p = -length / 2
                while p < length / 2:
                    q = p + rng.uniform(7, 14)
                    low = rng.random() < damage * 0.6
                    if roof == "partial" and side == "N":
                        low = False
                    if roof == "partial" and side in ("E", "W") and p > cut:
                        low = False
                    if low:
                        tops[side].append((p, q, h * rng.uniform(0.35, 0.85)))
                    p = q
        for side in ("S", "N", "E", "W"):
            self.wall(pb, side, w, d, h, color, mat, windows[side], tops[side])
            for c, width, lo, hi in windows[side]:
                if lo > 0 and hi < h and rng.random() < 0.25 and not shop:
                    self.boards(pb, side, w, d, c, width, lo, hi)
        # Dach
        roof_col = self.bm.lighten(color, -0.35)
        if roof == "intact":
            pb.box("Buildings", "Roof", (w + 0.6, 0.8, d + 0.6), (0, h + 0.4, 0), roof_col, "Concrete")
        elif roof == "partial":
            depth = d / 2 - cut
            pb.box("Buildings", "Roof", (w + 0.6, 0.8, depth + 0.3), (0, h + 0.4, cut + depth / 2), roof_col, "Concrete")
            fall = d / 2 + cut
            ang = math.degrees(math.atan2(h - 0.5, fall))
            pb.box("Buildings", "FallenRoof", (w - 2.4, 0.8, math.hypot(h - 0.5, fall) * 0.95), (0, h / 2, cut - fall / 2), roof_col,
                   "Concrete", angles=(-ang, 0, rng.uniform(-6, 6)))
        else:
            self.local_rubble(pb, rng.uniform(-w / 4, w / 4), rng.uniform(-d / 4, d / 4), min(w, d) * 0.6, color, n=3)
        # obere Stockwerke (Wohnblock): geschlossen, dunkle Fensterbänder, eine Ecke weggesprengt
        if floors_above > 0:
            hu = floors_above * 9
            missing = rng.random() < 0.6
            if missing:
                pb.box("Buildings", "Upper", (w, hu, d * 0.55), (0, h + 0.8 + hu / 2, d * 0.225), color, mat)
                pb.box("Buildings", "Upper", (w * 0.5, hu * rng.uniform(0.4, 0.8), d * 0.45), (w * 0.25, h + 0.8 + hu * 0.3, -d * 0.275),
                       color, mat)
                self.local_rubble(pb, -w / 4, -d / 2 - 4, 8, color, n=3)
            else:
                pb.box("Buildings", "Upper", (w, hu, d), (0, h + 0.8 + hu / 2, 0), color, mat)
            for f in range(floors_above):
                y = h + 0.8 + f * 9 + 4.5
                pb.box("Decor", "WindowBand", (w + 0.25, 2.2, (d * 0.55 if missing else d) + 0.25),
                       (0, y, d * 0.225 if missing else 0), (26, 28, 32), "Slate")
        # Schaden außen und innen
        if rng.random() < 0.45:
            self.graffiti(pb, rng.choice(GRAFFITI), (rng.uniform(-w / 4, w / 4), 4.6, -d / 2 - 0.08), (min(10, w - 4), 2.4, 0.05))
        if rng.random() < 0.4:
            pb.box("Decor", "Scorch", (rng.uniform(3, 6), rng.uniform(3, 6), 0.08), (rng.uniform(-w / 3, w / 3), h * 0.6, -d / 2 - 0.1),
                   (20, 18, 16), "SmoothPlastic", props={"Transparency": 0.25, "CanCollide": False, "CanQuery": False})
        if rng.random() < 0.25:
            for _ in range(1):
                pb.box("Decor", "Vines", (0.3, h * rng.uniform(0.4, 0.9), rng.uniform(1.5, 3)),
                       (rng.choice((-1, 1)) * (w / 2 + 0.2), h * 0.35, rng.uniform(-d / 3, d / 3)), (60, 90, 44), "Grass",
                       props={"CanCollide": False, "CanQuery": False})
        if rng.random() < 0.3:
            self.local_rubble(pb, rng.uniform(-w / 2, w / 2), -d / 2 - 2.5, 5, color, n=2)
        if rng.random() < 0.5:
            pb.box("Cover", "Furniture", (rng.uniform(3, 6), rng.uniform(1.5, 3), rng.uniform(2, 4)),
                   (rng.uniform(-w / 3, w / 3), 0.8, rng.uniform(-d / 4, d / 3)), (110, 86, 60), "WoodPlanks",
                   angles=(rng.uniform(-40, 40), rng.uniform(0, 180), rng.uniform(-20, 20)))
        if shop:
            title, subtitle, sign_col = shop
            tilt = rng.choice((0, 0, rng.uniform(-14, 14)))
            pb.sign2(self.nm("ShopSign"), (min(16, w - 2), 2.8, 0.3), (0, h - 1.4, -d / 2 - 0.45), title, subtitle, (26, 26, 28),
                     sign_col, (220, 220, 220), angles=(0, 0, tilt))
            pb.box("Decor", "Awning", (min(14, w - 4), 0.3, 3.4), (0, 8.2, -d / 2 - 1.8), sign_col, "Fabric",
                   angles=(rng.uniform(8, 30), 0, rng.uniform(-10, 10)))
            for k in range(1):
                pb.box("Cover", "Shelf", (rng.uniform(6, 10), 4, 1.6), (rng.uniform(-w / 4, w / 4), 1.4, rng.uniform(-d / 6, d / 4)),
                       (110, 100, 90), "WoodPlanks", angles=(rng.choice((0, 0, 70)), rng.uniform(-20, 20), 0))
        return pb

    def ruin_tower(self, w, d, h, color):
        """Hochhaus-Ruine (nicht begehbar): ausgebrannte Fensterbänder, abgebrochene Spitze, Brandlöcher, Schutt."""
        pb, rng = self.prefab(), self.rng
        band = (26, 28, 32)
        if rng.random() < 0.12:  # eingestürzt: Stumpf und Schuttberg
            hs = h * rng.uniform(0.15, 0.3)
            pb.box("Buildings", "TowerStub", (w, hs, d), (0, hs / 2 - 1, 0), color, "Concrete")
            for _ in range(10):
                s = rng.uniform(4, 10)
                pb.box("Cover", "Rubble", (s * 1.4, s * 0.6, s), (rng.uniform(-w / 2 - 8, w / 2 + 8), s * 0.2, rng.uniform(-d / 2 - 8, d / 2 + 8)),
                       self.bm.lighten(color, rng.uniform(-0.3, 0.1)), "Concrete",
                       angles=(rng.uniform(-30, 30), rng.uniform(0, 360), rng.uniform(-30, 30)))
            return pb
        h0 = h * rng.uniform(0.55, 0.8)
        pb.box("Buildings", "Tower", (w, h0 + 1, d), (0, h0 / 2 - 0.5, 0), color, "Concrete")
        y = 9.0
        while y < h0 - 2:
            pb.box("Decor", "TowerWindows", (w + 0.3, 2.4, d + 0.3), (0, y, 0), band, "Slate")
            y += 5.5
        pb.box("Decor", "TowerLobby", (w + 0.4, 5.2, d + 0.4), (0, 2.2, 0), (20, 22, 24), "Slate")
        # oben zwei Hälften mit verschiedener Höhe (abgebrochen), manchmal fehlt eine
        for sx in (-1, 1):
            if rng.random() < 0.2:
                continue
            hu = (h - h0) * rng.uniform(0.3, 1.0)
            pb.box("Buildings", "TowerTop", (w / 2, hu, d), (sx * w / 4, h0 + hu / 2, 0), color, "Concrete")
            yy = h0 + 3
            while yy < h0 + hu - 2:
                pb.box("Decor", "TowerWindows", (w / 2 + 0.3, 2.4, d + 0.3), (sx * w / 4, yy, 0), band, "Slate")
                yy += 5.5
            for _ in range(2):  # Bewehrungseisen
                pb.box("Decor", "Rebar", (0.3, rng.uniform(2, 5), 0.3), (sx * w / 4 + rng.uniform(-w / 5, w / 5), h0 + hu + 1.5,
                       rng.uniform(-d / 3, d / 3)), (80, 60, 50), "CorrodedMetal", angles=(rng.uniform(-25, 25), 0, rng.uniform(-25, 25)))
        for _ in range(rng.randint(2, 4)):  # Brandlöcher mit Rußfahne
            hx, hy = rng.uniform(-w / 2 + 4, w / 2 - 4), rng.uniform(10, h0 - 6)
            pb.box("Decor", "BurnHole", (rng.uniform(4, 8), rng.uniform(3, 6), 0.6), (hx, hy, -d / 2 - 0.1), (12, 12, 12), "Slate")
            pb.box("Decor", "Soot", (rng.uniform(3, 6), rng.uniform(6, 12), 0.1), (hx, hy + 5, -d / 2 - 0.2), (24, 22, 20),
                   "SmoothPlastic", props={"Transparency": 0.3, "CanCollide": False, "CanQuery": False})
        if rng.random() < 0.5:
            self.graffiti(pb, rng.choice(GRAFFITI), (0, 4, -d / 2 - 0.3), (min(14, w - 4), 3, 0.05))
        self.local_rubble(pb, rng.uniform(-w / 3, w / 3), -d / 2 - 5, 9, color, n=3)
        return pb

    def ruin_barn(self, w=24, d=34, h=12, color=(140, 56, 46)):
        pb = self.ruin_house(w, d, h, color, "WoodPlanks", damage=0.7)
        return pb

    def lamp(self, x, z, yaw, working=False):
        """Straßenlaterne, meist kaputt (schief, ohne Licht)."""
        g = self.H(x, z) + 0.4
        tilt = 0 if working else self.rng.choice((0, self.rng.uniform(-25, 25)))
        self.b.box("Decor", "StreetLamp", (0.5, 12, 0.5), (x, g + 6, z), (40, 42, 46), "Metal", angles=(tilt, yaw, 0))
        if working:
            self.b.box("Decor", "StreetLampHead", (1.4, 0.4, 1.4), (x, g + 12.2, z), (255, 226, 180), "Neon",
                       children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {
                           "Range": 30, "Brightness": 1.0, "Color": self.bm.rgb(255, 220, 170)}}])

    # ---------- Besondere Orte ----------
    @staticmethod
    def merge(dst, src, ox, oz):
        """Prefab src um (ox, oz) verschoben in Prefab dst übernehmen."""
        for group, items in src.groups.items():
            for inst in items:
                inst = copy.deepcopy(inst)
                pos = inst["Properties"]["CFrame"]["CFrame"]["position"]
                inst["Properties"]["CFrame"]["CFrame"]["position"] = [pos[0] + ox, pos[1], pos[2] + oz]
                dst.groups.setdefault(group, []).append(inst)

    def place_ruin(self, pb, x, z, yaw, r):
        self.stamp(pb, x, z, yaw)
        self.occupied.append((x, z, r))

    def fence_rect(self, x0, z0, x1, z1, gaps=(), color=(140, 146, 150), height=9, broken=0.25):
        """Maschendrahtzaun um ein Rechteck, Tore gaps = [(Seite, Mitte)], Stücke fehlen (broken) oder hängen schief."""
        b, rng = self.b, self.rng
        for side, (ax, az, bx, bz) in (("S", (x0, z0, x1, z0)), ("N", (x0, z1, x1, z1)), ("W", (x0, z0, x0, z1)), ("E", (x1, z0, x1, z1))):
            along_x = az == bz
            a, e = (ax, bx) if along_x else (az, bz)
            p = a
            while p < e - 0.5:
                q = min(e, p + 20)
                mid = (p + q) / 2
                gate = any(gs == side and abs(gc - mid) < 14 for gs, gc in gaps)
                if not gate and rng.random() > broken * 0.5:
                    px, pz = (mid, az) if along_x else (ax, mid)
                    g = self.H(px, pz) + 0.4
                    tilt = rng.uniform(-14, 14) if rng.random() < broken else 0
                    size = (q - p, height, 0.3) if along_x else (0.3, height, q - p)
                    b.box("Walls", "ChainFence", size, (px, g + height / 2, pz), color, "DiamondPlate",
                          angles=((tilt, 0, 0) if along_x else (0, 0, tilt)), props={"Transparency": 0.55})
                    ex, ez = (p, az) if along_x else (ax, p)
                    b.box("Walls", "FencePost", (0.8, height + 1, 0.8), (ex, self.H(ex, ez) + 0.4 + height / 2, ez), (80, 84, 88), "Metal")
                p = q

    def watchtower(self, x, z, h=16):
        b = self.b
        g = self.H(x, z) + 0.4
        for dx in (-2.5, 2.5):
            for dz in (-2.5, 2.5):
                b.box("Decor", "TowerLeg", (0.9, h, 0.9), (x + dx, g + h / 2, z + dz), (80, 84, 88), "Metal")
        b.box("Buildings", "TowerDeck", (8, 0.6, 8), (x, g + h + 0.3, z), (90, 94, 98), "DiamondPlate")
        b.box("Cover", "TowerWall", (8, 3, 0.4), (x, g + h + 2, z - 4), (90, 94, 98), "Metal")
        b.box("Decor", "TowerRoof", (8.6, 0.4, 8.6), (x, g + h + 5.4, z), (70, 76, 62), "Metal",
              angles=(self.rng.uniform(-8, 8), 0, self.rng.uniform(-8, 8)))

    def tent(self, x, z, yaw, color, collapsed=False):
        b = self.b
        g = self.H(x, z) + 0.4
        m = self.bm.rot(0, yaw, 0)

        def at(lx, ly, lz):
            return (x + m[0][0] * lx + m[0][2] * lz, g + ly, z + m[2][0] * lx + m[2][2] * lz)
        b.box("Decor", "TentFloor", (8, 0.2, 10), at(0, 0.1, 0), (70, 70, 64), "Fabric", angles=(0, yaw, 0))
        if collapsed:
            b.box("Decor", "TentCloth", (8.4, 0.4, 10), at(0, 0.8, 0), color, "Fabric", angles=(self.rng.uniform(-8, 8), yaw, 6))
            return
        b.add("Decor", "Tent", (8, 5, 5), at(0, 2.5, -2.5), color, "Fabric", angles=(0, yaw, 0), cls="WedgePart")
        b.add("Decor", "Tent", (8, 5, 5), at(0, 2.5, 2.5), color, "Fabric", angles=(0, yaw + 180, 0), cls="WedgePart")

    def tank(self, x, z, yaw, burned=False):
        b = self.b
        g = self.H(x, z) + 0.4
        col = (40, 38, 36) if burned else (84, 92, 70)
        b.box("Cover", "TankHull", (10, 3.6, 16), (x, g + 1.8, z), col, "CorrodedMetal", angles=(0, yaw, 0))
        b.box("Cover", "TankTurret", (6.4, 2.4, 7), (x, g + 4.6, z), self.bm.lighten(col, -0.1), "CorrodedMetal", angles=(0, yaw + 25, 0))
        a = math.radians(yaw + 25)
        b.add("Decor", "TankBarrel", (11, 0.9, 0.9), (x - math.sin(a) * 8, g + 4.8, z - math.cos(a) * 8), (60, 64, 52), "Metal",
              angles=(0, yaw + 25 + 90, 0), props={"Shape": "Cylinder"})

    def helicopter_wreck(self, x, z, yaw):
        b = self.b
        g = self.H(x, z) + 0.4
        b.box("Cover", "HeliBody", (6, 5, 14), (x, g + 2.4, z), (60, 66, 54), "CorrodedMetal", angles=(8, yaw, 18))
        b.box("Cover", "HeliTail", (1.6, 1.6, 12), (x + 6, g + 1.2, z + 8), (60, 66, 54), "CorrodedMetal", angles=(0, yaw + 30, 8))
        b.box("Decor", "HeliRotor", (24, 0.3, 1.2), (x - 3, g + 0.4, z - 4), (40, 40, 40), "Metal", angles=(0, yaw + 60, 0))
        self.smoke_column(x, g + 4, z)

    def build_hospital(self):
        _, x, z, _ = PLACES["Krankenhaus"]
        rng = self.rng
        pb = self.ruin_house(90, 30, 11, (214, 216, 212), damage=0.5, floors_above=2)
        pb.box("Decor", "HospitalCrossV", (1.8, 7, 0.2), (0, 16, -15.2), (200, 40, 40), "Neon")
        pb.box("Decor", "HospitalCrossH", (7, 1.8, 0.2), (0, 16, -15.2), (200, 40, 40), "Neon")
        pb.sign2("HospitalSign", (24, 3.6, 0.3), (0, 31, -15.2), "ST. MARIEN", "KRANKENHAUS · NOTAUFNAHME", (26, 28, 30), (220, 70, 70),
                 (230, 230, 230), angles=(0, 0, 5))
        yaw = self.yaw_to(-x, -z)  # Vorderseite zur Stadtmitte
        self.place_ruin(pb, x, z, yaw, 52)
        m = self.bm.rot(0, yaw, 0)

        def at(lx, lz):
            return x + m[0][0] * lx + m[0][2] * lz, z + m[2][0] * lx + m[2][2] * lz
        for lx, lz in ((-30, -34), (-14, -38), (24, -32)):
            ax, az = at(lx, lz)
            self.car(ax, az, yaw + rng.uniform(60, 120), burned=rng.random() < 0.4, color=(232, 232, 232))
        for k in range(5):
            tx, tz = at(-40 + k * 14, -60)
            self.tent(tx, tz, yaw, (220, 220, 214), collapsed=rng.random() < 0.4)
            self.body_bag(tx + rng.uniform(-4, 4), tz - 8, yaw + 90)
        for k in range(4):
            sx, sz = at(rng.uniform(-40, 40), rng.uniform(-70, -36))
            self.stain(sx, sz)
        self.occupied.append((at(0, -55)[0], at(0, -55)[1], 40))

    def build_police(self):
        _, x, z, _ = PLACES["Polizei"]
        pb = self.ruin_house(40, 26, 10, (150, 160, 176), damage=0.45, shop=("POLIZEI", "WACHE ÖDSTADT", (90, 140, 230)))
        yaw = self.yaw_to(-x, -z)
        self.place_ruin(pb, x, z, yaw, 26)
        m = self.bm.rot(0, yaw, 0)
        for lx in (-14, 0, 14):
            px, pz = x + m[0][0] * lx + m[0][2] * -24, z + m[2][0] * lx + m[2][2] * -24
            self.car(px, pz, yaw + 90, burned=self.rng.random() < 0.5, color=(60, 90, 150))
        self.occupied.append((x + m[0][2] * -24, z + m[2][2] * -24, 22))

    def build_evac(self):
        """Verlassenes Evakuierungslager: Zaun, Zelte (teils eingestürzt), Militärlaster, Leichensäcke, Feuer."""
        x, z = 230, -260
        rng = self.rng
        self.fence_rect(x - 60, z - 50, x + 60, z + 50, gaps=(("N", x),), broken=0.5)
        for k in range(8):
            self.tent(x - 42 + (k % 4) * 26, z - 20 + (k // 4) * 34, 0, (96, 108, 78), collapsed=rng.random() < 0.35)
        for k in range(6):
            self.body_bag(x + rng.uniform(-50, 50), z + rng.uniform(-40, 40), rng.uniform(0, 180))
        self.car(x + 40, z + 36, 90, burned=True, color=(84, 92, 70))
        self.fire(x, z + 5, smoke=True)
        self.occupied.append((x, z, 80))
        PLACES["Evakuierung"] = ("EVAKUIERUNGSLAGER", x, z, 70)

    def build_military(self):
        _, x, z, _ = PLACES["Militaer"]
        rng = self.rng
        s = 130
        self.fence_rect(x - s, z - s, x + s, z + s, gaps=(("S", x), ("E", z)), broken=0.3)
        for k in range(4):
            pb = self.ruin_house(42, 16, 9, (98, 106, 86), damage=0.5)
            self.place_ruin(pb, x - 80, z + 80 - k * 34, -90, 22)
        pb = self.ruin_house(54, 42, 15, (92, 98, 84), "CorrodedMetal", damage=0.6)
        self.place_ruin(pb, x + 60, z + 70, 0, 35)
        self.tank(x - 10, z + 10, 30)
        self.tank(x + 30, z - 30, 200, burned=True)
        self.helicopter_wreck(x + 50, z - 80, 40)
        for wx, wz in ((x - s + 10, z - s + 10), (x + s - 10, z + s - 10), (x - s + 10, z + s - 10), (x + s - 10, z - s + 10)):
            self.watchtower(wx, wz)
        for k in range(8):
            self.b.container(x - 40 + (k % 4) * 12, z - 70 + (k // 4) * 26, along_x=False,
                             color=rng.choice(((90, 110, 76), (70, 86, 64), (110, 96, 70))))
        for k in range(8):
            self.b.box("Cover", "Sandbags", (8, 3, 2.4), (x - 50 + k * 14, self.H(x, z - 100) + 1.9, z - 100), (150, 134, 98), "Fabric",
                       angles=(0, rng.uniform(-10, 10), 0))
        for _ in range(4):
            self.rubble(x + rng.uniform(-100, 100), z + rng.uniform(-100, 100), 8)
        self.occupied.append((x, z, s + 10))

    def build_harbor(self):
        _, x, z, _ = PLACES["Hafen"]
        rng = self.rng
        for k, (wx, wz) in enumerate(((x - 80, z + 60), (x + 10, z + 80), (x - 90, z - 40))):
            pb = self.ruin_house(60, 36, 14, (120, 122, 126), "CorrodedMetal", damage=0.6)
            self.place_ruin(pb, wx, wz, rng.choice((0, 90, 180)), 36)
        for k in range(14):
            self.b.container(x - 20 + (k % 5) * 24, z - 90 + (k // 5) * 12, along_x=True, level=0,
                             color=rng.choice(((150, 60, 50), (60, 100, 150), (170, 130, 60), (80, 120, 80))))
        for k in range(4):
            self.b.container(x - 20 + k * 24, z - 90, along_x=True, level=1, color=rng.choice(((150, 60, 50), (60, 100, 150))))
        for cx, cz in ((x + 110, z - 60), (x + 60, z - 140)):
            g = self.H(cx, cz) + 0.4
            self.b.box("Buildings", "CraneTower", (3, 48, 3), (cx, g + 24, cz), (210, 170, 50), "Metal")
            self.b.box("Buildings", "CraneArm", (54, 2.4, 2.4), (cx + 18, g + 48, cz), (210, 170, 50), "Metal",
                       angles=(0, rng.uniform(0, 60), 0))
        for k in range(3):
            tx, tz = x - 120 + k * 22, z - 120
            self.b.cylinder("Buildings", "FuelTank", 16, 18, (tx, self.H(tx, tz) + 9.4, tz), (200, 200, 196))
        self.smoke_column(x - 98, self.H(x - 98, z - 120) + 19, z - 120)
        # Steg in den Stausee und ein halb versunkenes Schiff
        lx, lz = 1380, -1280
        dx, dz = (lx - x), (lz - z)
        dl = math.hypot(dx, dz)
        dx, dz = dx / dl, dz / dl
        shore = None
        for k in range(0, 400, 4):
            px, pz = x + dx * k, z + dz * k
            if self.terrain.is_water(px, pz):
                shore = (px, pz)
                break
        if shore:
            sx, sz = shore
            yaw = math.degrees(math.atan2(-dz, dx))
            self.b.box("Buildings", "Pier", (60, 0.8, 10), (sx + dx * 22, et.WATER + 1.4, sz + dz * 22), (110, 86, 60), "WoodPlanks",
                       angles=(0, yaw, 0))
            for k in range(6):
                px, pz = sx + dx * (k * 10), sz + dz * (k * 10)
                self.b.box("Buildings", "PierPost", (1, 10, 1), (px, et.WATER - 3, pz), (90, 70, 50), "Wood")
            self.b.box("Cover", "ShipHull", (14, 9, 46), (sx + dx * 75, et.WATER - 0.5, sz + dz * 75), (110, 60, 50), "CorrodedMetal",
                       angles=(10, yaw + 70, 14))
        self.occupied.append((x, z, 160))

    def build_prison(self):
        _, x, z, _ = PLACES["Gefaengnis"]
        rng = self.rng
        w, d, hgt = 200, 160, 14
        col = (150, 146, 136)
        for side, (ax, az, bx, bz) in (("N", (x - w / 2, z + d / 2, x + w / 2, z + d / 2)), ("S", (x - w / 2, z - d / 2, x + w / 2, z - d / 2)),
                                        ("W", (x - w / 2, z - d / 2, x - w / 2, z + d / 2)), ("E", (x + w / 2, z - d / 2, x + w / 2, z + d / 2))):
            along_x = az == bz
            a, e = (ax, bx) if along_x else (az, bz)
            p = a
            while p < e - 0.5:
                q = min(e, p + 20)
                mid = (p + q) / 2
                gate = side == "N" and abs(mid - x) < 12
                breach = rng.random() < 0.12
                if not gate:
                    hh = hgt * (rng.uniform(0.2, 0.5) if breach else 1)
                    px, pz = (mid, az) if along_x else (ax, mid)
                    size = (q - p, hh + 1, 2) if along_x else (2, hh + 1, q - p)
                    self.b.box("Walls", "PrisonWall", size, (px, hh / 2 - 0.5, pz), col, "Concrete")
                    if breach:
                        self.rubble(px, pz, 10, col)
                p = q
        for cx, cz in ((x - w / 2, z - d / 2), (x + w / 2, z - d / 2), (x - w / 2, z + d / 2), (x + w / 2, z + d / 2)):
            self.b.box("Buildings", "PrisonTower", (8, 22, 8), (cx, 10.5, cz), (130, 126, 118), "Concrete")
            self.b.box("Decor", "PrisonTowerTop", (10, 3, 10), (cx, 23, cz), (40, 44, 48), "Glass", props={"Transparency": 0.4})
        for k in range(2):
            pb = self.ruin_house(76, 18, 10, (176, 170, 156), damage=0.4, floors_above=1)
            self.place_ruin(pb, x - 30 + k * 0, z - 40 + k * 70, 0 if k == 0 else 180, 40)
        pb = self.ruin_house(24, 16, 9, (140, 136, 128), damage=0.5, shop=("JVA", "BESUCHER · ANMELDUNG", (230, 200, 90)))
        self.place_ruin(pb, x + 60, z + 50, 180, 16)
        self.car(x + 40, z + 100, 90, burned=True, color=(200, 170, 40))  # Gefangenenbus
        self.car(x + 52, z + 100, 90, burned=True, color=(200, 170, 40))
        self.occupied.append((x, z, 120))

    def build_airfield(self):
        _, x, z, _ = PLACES["Flugplatz"]
        rng = self.rng
        b = self.b
        b.box("Roads", "Road", (560, 0.9, 40), (x, -0.2, z), (58, 60, 64), "Asphalt")
        self.roads.append((x - 280, z, x + 280, z, 40))
        for k in range(-12, 13):
            b.box("Roads", "RunwayMark", (10, 0.02, 1), (x + k * 22, 0.26, z), (220, 220, 220), "SmoothPlastic")
        b.floor_text("RunwayNumber", (18, 0.1, 14), (x - 250, 0.14, z), "09", (230, 230, 230), bg=(58, 60, 64), yaw=90)
        for k in range(2):
            pb = self.ruin_house(52, 40, 15, (130, 134, 138), "CorrodedMetal", damage=0.55)
            self.place_ruin(pb, x - 140 + k * 80, z + 80, 0, 36)
        b.box("Buildings", "ControlTower", (10, 26, 10), (x + 140, 12.5, z + 80), (170, 166, 156), "Concrete")
        b.box("Decor", "ControlTop", (14, 5, 14), (x + 140, 28, z + 80), (30, 40, 48), "Glass", props={"Transparency": 0.3})
        b.box("Buildings", "ControlRoof", (15, 0.8, 15), (x + 140, 31, z + 80), (80, 80, 84), "Concrete", angles=(0, 0, 8))
        # Flugzeugwrack
        px, pz = x + 40, z - 60
        b.add("Cover", "Fuselage", (40, 7, 7), (px, 3.4, pz), (200, 200, 196), "Metal", angles=(0, 20, 6), props={"Shape": "Cylinder"})
        b.box("Cover", "Wing", (8, 0.8, 36), (px - 2, 2.6, pz - 4), (180, 180, 176), "Metal", angles=(4, 20, 0))
        b.box("Decor", "Tail", (5, 8, 0.8), (px + 18, 6, pz - 6), (160, 40, 40), "Metal", angles=(0, 20, 0))
        self.smoke_column(px, 6, pz)
        self.occupied.append((x, z + 60, 200))
        self.occupied.append((px, pz, 24))

    def build_farm(self, key):
        _, x, z, _ = PLACES[key]
        rng = self.rng
        pb = self.ruin_house(26, 36, 13, (150, 56, 46), "WoodPlanks", damage=0.6)
        self.place_ruin(pb, x, z, rng.choice((0, 90)), 24)
        g = self.H(x + 30, z + 4) + 0.4
        self.b.cylinder("Buildings", "Silo", 10, 26, (x + 30, g + 13, z + 4), (176, 176, 170))
        pb = self.ruin_house(22, 16, 8, (176, 150, 120), damage=0.5)
        self.place_ruin(pb, x - 40, z - 36, 0, 16)
        for k in range(2):
            fx, fz = x - 30 + k * 60, z + 60
            self.b.box("Ground", "Field", (52, 0.1, 40), (fx, self.H(fx, fz) + 0.46, fz), (96, 74, 52), "Ground")
            for r in range(5):
                self.b.box("Nature", "Crops", (48, 1.2, 1.2), (fx, self.H(fx, fz) + 1, fz - 16 + r * 8), (110, 120, 60), "Grass",
                           props={"CanCollide": False})
        self.car(x + 20, z - 30, rng.uniform(0, 360), burned=False, color=(60, 110, 60))
        self.occupied.append((x, z, 70))

    def build_gas(self, x, z, hx, hz):
        """Tankstelle bei (x, z), Zufahrt zur Landstraße bei (hx, hz)."""
        rng = self.rng
        yaw = self.yaw_to(hx - x, hz - z)
        pb = self.prefab()
        pb.box("Buildings", "FuelRoof", (34, 1, 20), (0, 9.5, -14), (180, 60, 50), "Metal", angles=(0, 0, rng.uniform(-6, 6)))
        for dx in (-14, 14):
            for dz in (-21, -7):
                if rng.random() < 0.85:
                    pb.box("Buildings", "FuelPillar", (1.2, 9.5, 1.2), (dx, 4.5, dz), (220, 220, 220), "Metal")
        for dx in (-6, 6):
            pb.box("Cover", "FuelPump", (2, 4.6, 3), (dx, 2.3, -14), (220, 220, 220), "SmoothPlastic",
                   angles=(rng.choice((0, 0, 80)), 0, 0))
        shop = self.ruin_house(24, 16, 9, (210, 206, 196), damage=0.5, shop=("TANKSTELLE", "24 H · GESCHLOSSEN", (200, 60, 50)))
        self.merge(pb, shop, 0, 10)
        self.place_ruin(pb, x, z, yaw, 26)
        self.road(x + (hx - x) * 0.35, z + (hz - z) * 0.35, hx, hz, 16, lines=False)
        PLACES["Tank%d" % len([k for k in PLACES if k.startswith("Tank")])] = ("TANKSTELLE", x, z, 45)

    def build_radio(self):
        _, x, z, _ = PLACES["Funkturm"]
        b = self.b
        g0 = self.H(x, z)
        base = g0 + 0.6
        b.box("Buildings", "TowerBase", (30, 6, 26), (x - 8, g0 - 2.4, z - 6), (110, 108, 102), "Concrete")
        for sx in (-1, 1):
            for sz in (-1, 1):
                b.box("Buildings", "TowerLegLow", (0.9, 26, 0.9), (x + sx * 4, base + 13, z + sz * 4), (200, 200, 205), "Metal")
                b.box("Buildings", "TowerLegHigh", (0.7, 22, 0.7), (x + sx * 2.2, base + 37, z + sz * 2.2), (200, 60, 50), "Metal",
                      angles=(0, 0, 4))
        for lv in range(1, 6):
            wd = 8.8 - lv * 0.95
            yy = base + lv * 8
            for dx_, dz_, sx_, sz_ in ((0, wd / 2, wd + 0.6, 0.5), (0, -wd / 2, wd + 0.6, 0.5), (wd / 2, 0, 0.5, wd + 0.6), (-wd / 2, 0, 0.5, wd + 0.6)):
                b.box("Buildings", "TowerRing", (sx_, 0.5, sz_), (x + dx_, yy, z + dz_), (200, 200, 205), "Metal")
        b.box("Decor", "TowerBeacon", (1.2, 1.2, 1.2), (x, base + 49, z), (255, 40, 30), "Neon",
              children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 60, "Brightness": 1.5,
                                                                                      "Color": self.bm.rgb(255, 60, 40)}}])
        pb = self.ruin_house(16, 12, 7, (110, 112, 108), damage=0.3)
        self.stamp(pb, x - 18, z - 8, 90, y=g0 + 0.4)
        self.occupied.append((x, z, 40))

    def build_outpost(self, key, title, x, z):
        """Außenposten auf der Hügelkuppe: Lagerhaus (begehbar), Wachturm, Zaun aus Pfählen, Sandsäcke, Feuer, Schild."""
        rng = self.rng
        g = self.H(x, z)
        color = rng.choice(((112, 96, 74), (96, 104, 92), (120, 116, 104)))
        pb = self.ruin_house(26, 18, 10, color, rng.choice(("CorrodedMetal", "WoodPlanks")), damage=0.25,
                             shop=("LAGER", title, (226, 178, 52)))
        yaw = rng.uniform(0, 360)
        self.stamp(pb, x, z, yaw, y=g + 0.4)
        m = self.bm.rot(0, yaw, 0)
        tx, tz = x + m[0][0] * 20 + m[0][2] * 10, z + m[2][0] * 20 + m[2][2] * 10
        self.watchtower(tx, tz, 14)
        for k in range(16):  # Palisade aus Pfählen mit Lücken
            a = k / 16 * math.pi * 2
            if k % 4 == 0:
                continue
            px, pz = x + math.cos(a) * 28, z + math.sin(a) * 28
            self.b.box("Walls", "Palisade", (11, 5, 1), (px, self.H(px, pz) + 2.2, pz), (96, 74, 52), "WoodPlanks",
                       angles=(rng.uniform(-6, 6), -math.degrees(a) + 90, rng.uniform(-4, 4)))
        for k in range(3):
            a = rng.uniform(0, 2 * math.pi)
            px, pz = x + math.cos(a) * 22, z + math.sin(a) * 22
            self.b.box("Cover", "Sandbags", (7, 2.8, 2.4), (px, self.H(px, pz) + 1.8, pz), (150, 134, 98), "Fabric",
                       angles=(0, -math.degrees(a) + 90, 0))
        fx, fz = x - m[0][2] * 16, z - m[2][2] * 16
        self.fire(fx, fz, smoke=rng.random() < 0.5)
        self.b.box("Decor", "FlagPole", (0.4, 14, 0.4), (x + 12, g + 7.4, z - 12), (60, 60, 64), "Metal")
        self.b.box("Decor", "Flag", (5, 3, 0.2), (x + 14.6, g + 12.8, z - 12), rng.choice(((180, 40, 40), (40, 40, 40), (200, 200, 190))),
                   "Fabric", angles=(0, 0, rng.uniform(-10, 10)))
        self.occupied.append((x, z, 32))

    def build_church(self, x, z):
        b = self.b
        pb = self.ruin_house(20, 40, 15, (192, 186, 172), "Brick", damage=0.5)
        self.place_ruin(pb, x, z, 0, 24)
        b.box("Buildings", "ChurchTower", (9, 30, 9), (x, 14, z + 24.5), (186, 180, 166), "Brick")
        for w, yy in ((10, 30.5), (7, 33.5), (4.4, 36.5)):
            b.box("Buildings", "Spire", (w, 3.4, w), (x, yy, z + 24.5), (70, 52, 46), "Slate", angles=(0, 45, 6))
        for row in range(4):
            for col in range(6):
                gx, gz = x - 50 + col * 7, z - 20 + row * 10
                b.box("Cover", "Gravestone", (1.5, 2.4, 0.5), (gx, self.H(gx, gz) + 1.4, gz), (150, 150, 146), "Slate",
                      angles=(self.rng.uniform(-15, 15), self.rng.uniform(-8, 8), self.rng.uniform(-10, 10)))
        self.occupied.append((x - 30, z, 30))
        PLACES["Kirche"] = ("KIRCHE NORDHEIM", x, z, 40)

    # ---------- Orte mit Straßen und Häusern ----------
    def city_streets(self):
        """Ödstadt: Ringe und Radialen mit Schwung, dazu schräge Querstraßen – kein Raster."""
        rng = self.rng
        streets = []

        def ring(radius, n, wobble, a0=0.0):
            pts = []
            for k in range(n + 1):
                a = a0 + 2 * math.pi * k / n
                r = radius + (rng.uniform(-wobble, wobble) if k < n else 0)
                pts.append((math.cos(a) * r, math.sin(a) * r))
            pts[-1] = pts[0]
            return pts
        rings = [ring(180, 14, 6), ring(340, 20, 22, 0.1), ring(500, 28, 28, 0.05), ring(660, 36, 30, 0.02)]
        streets += rings
        for k in range(12):  # Radialen: vier Achsen genau auf die Landstraßen, dazwischen leicht schräg
            if k % 3 == 0:
                c, sn = round(math.cos(math.radians(30 * k))), round(math.sin(math.radians(30 * k)))
                streets.append([(c * r, sn * r) for r in (180, 340, 500, 660, 720)])
                continue
            a = math.radians(30 * k) + rng.uniform(-0.1, 0.1)
            pts = []
            for r in (180, 340, 500, 660):
                b = a + rng.uniform(-0.05, 0.05)
                pts.append((math.cos(b) * r, math.sin(b) * r))
            streets.append(pts)
        for _ in range(26):  # schräge Querstraßen zwischen den Ringen
            a = rng.uniform(0, 2 * math.pi)
            r0, r1 = rng.choice(((185, 335), (345, 495), (345, 495), (505, 655), (505, 655), (505, 655)))
            a1 = a + rng.uniform(-0.3, 0.3)
            streets.append([(math.cos(a) * r0, math.sin(a) * r0), (math.cos(a1) * r1, math.sin(a1) * r1)])
        for _ in range(10):  # Sackgassen nach außen
            a = rng.uniform(0, 2 * math.pi)
            streets.append([(math.cos(a) * 665, math.sin(a) * 665), (math.cos(a + 0.08) * 730, math.sin(a + 0.08) * 730)])
        return streets

    def village_streets(self, cx, cz, radius):
        rng = self.rng
        streets = []
        base = rng.uniform(0, 2 * math.pi)
        for k in range(4):
            a = base + k * math.pi / 2 + rng.uniform(-0.4, 0.4)
            length = radius * rng.uniform(0.55, 0.85)
            mid = length * 0.5
            a2 = a + rng.uniform(-0.5, 0.5)
            streets.append([(cx + math.cos(a) * 20, cz + math.sin(a) * 20), (cx + math.cos(a) * mid, cz + math.sin(a) * mid),
                            (cx + math.cos(a) * mid + math.cos(a2) * (length - mid), cz + math.sin(a) * mid + math.sin(a2) * (length - mid))])
        return streets

    def pick_building(self, zone):
        rng = self.rng
        r = rng.random()
        if zone == "downtown":
            if r < 0.55:
                return "tower", rng.uniform(26, 40), rng.uniform(26, 38)
            if r < 0.75:
                return "apartment", rng.uniform(24, 34), rng.uniform(18, 26)
            return "shop", rng.uniform(20, 28), rng.uniform(16, 22)
        if zone == "city":
            if r < 0.4:
                return "apartment", rng.uniform(22, 32), rng.uniform(18, 24)
            if r < 0.72:
                return "shop", rng.uniform(18, 26), rng.uniform(14, 20)
            return "house", rng.uniform(16, 24), rng.uniform(14, 20)
        if zone == "suburb":
            if r < 0.25:
                return "apartment", rng.uniform(20, 28), rng.uniform(16, 22)
            if r < 0.45:
                return "shop", rng.uniform(16, 24), rng.uniform(14, 18)
            return "house", rng.uniform(14, 22), rng.uniform(12, 18)
        if zone == "rural":
            return ("barn", 22, 30) if r < 0.25 else ("house", rng.uniform(14, 20), rng.uniform(12, 16))
        if r < 0.72:
            return "house", rng.uniform(14, 22), rng.uniform(12, 18)
        if r < 0.86:
            return "shop", rng.uniform(16, 22), rng.uniform(14, 18)
        return "barn", 22, 30

    SHOPS = (("APOTHEKE", "MEDIKAMENTE", (90, 200, 120)), ("WAFFEN-HANDEL", "JAGD · SPORT", (215, 85, 45)),
             ("BAUMARKT", "WERKZEUG · HOLZ", (226, 160, 52)), ("SUPERMARKT", "24 H", (200, 70, 60)),
             ("KIOSK", "ZEITUNG · TABAK", (220, 200, 90)), ("ELEKTRO", "HANDY · TV", (90, 150, 230)),
             ("BAR", "GESCHLOSSEN", (200, 90, 200)), ("DINER", "BURGER · KAFFEE", (230, 120, 60)),
             ("ARZTPRAXIS", "DR. KRÄMER", (120, 200, 220)), ("PFANDHAUS", "ANKAUF", (210, 180, 90)),
             ("BANK", "SPARKASSE", (200, 60, 60)), ("BÄCKEREI", "SEIT 1958", (230, 190, 120)))
    COLORS = ((176, 160, 140), (150, 132, 116), (190, 184, 170), (140, 146, 150), (168, 140, 120), (186, 170, 150),
              (160, 170, 156), (150, 156, 164), (132, 126, 120), (196, 190, 178))

    def make_building(self, kind, w, d, zone):
        rng = self.rng
        color = rng.choice(self.COLORS)
        damage = rng.uniform(0.35, 0.9) if zone in ("downtown", "city", "suburb") else rng.uniform(0.2, 0.75)
        if kind == "tower":
            return self.ruin_tower(w, d, rng.uniform(40, 100), color)
        if kind == "apartment":
            return self.ruin_house(w, d, 9, color, rng.choice(("Concrete", "Brick")), damage=damage, floors_above=rng.randint(1, 3))
        if kind == "shop":
            return self.ruin_house(w, d, 10, color, damage=damage, shop=rng.choice(self.SHOPS))
        if kind == "barn":
            return self.ruin_barn()
        return self.ruin_house(w, d, rng.choice((8, 9, 10)), color, rng.choice(("Concrete", "Brick", "WoodPlanks")), damage=damage)

    def line_buildings(self, ax, az, bx, bz, width, zone_of, density=1.0, gap=(10, 22)):
        """Gebäude beidseits eines Straßenstücks, Vorderseite zur Straße."""
        rng = self.rng
        length = math.hypot(bx - ax, bz - az)
        if length < 20:
            return
        dx, dz = (bx - ax) / length, (bz - az) / length
        nx, nz = -dz, dx
        for side in (-1, 1):
            t = rng.uniform(4, 12)
            while t < length - 8:
                px, pz = ax + dx * t, az + dz * t
                zone = zone_of(px, pz)
                if zone is None:
                    t += 20
                    continue
                kind, w, d = self.pick_building(zone)
                off = width / 2 + 4 + d / 2 + rng.uniform(0.5, 3)
                cx, cz = px + dx * w / 2 + nx * side * off, pz + dz * w / 2 + nz * side * off
                r = 0.5 * math.hypot(w, d) * 0.92
                if rng.random() < density and t + w < length and self.free_rect(cx, cz, w, d, dx, dz) and self.flat_here(cx, cz, r):
                    pb = self.make_building(kind, w, d, zone)
                    self.place_ruin(pb, cx, cz, self.yaw_to(-nx * side, -nz * side), r)
                    t += w + rng.uniform(*gap)
                else:
                    t += 6

    def free_rect(self, cx, cz, w, d, dx, dz):
        """Rechteck (Breite w entlang der Straße dx/dz, Tiefe d) frei von Straßen und anderen Gebäuden?"""
        nx, nz = -dz, dx
        pts = [(cx, cz)]
        for sw in (-0.5, 0.5):
            for sd in (-0.5, 0.5):
                pts.append((cx + dx * w * sw + nx * d * sd, cz + dz * w * sw + nz * d * sd))
        for px, pz in pts:
            if abs(px) > HALF - 60 or abs(pz) > HALF - 60 or self.terrain.is_water(px, pz):
                return False
            for ax, az, bx, bz, rw in self.roads:
                if dist_point_segment(px, pz, ax, az, bx, bz) < rw / 2 + 2.5:
                    return False
        r = 0.5 * math.hypot(w, d) * 0.92
        for ox, oz, orr in self.occupied:
            if math.hypot(cx - ox, cz - oz) < r + orr - 1:
                return False
        return True

    def street_life(self, segments, cars=0.5, fires=0.06, lamps=True, stains=0.3):
        """Wracks, Blut, Sperren, Feuer und Laternen an Straßenstücken."""
        rng = self.rng
        for ax, az, bx, bz, w in segments:
            length = math.hypot(bx - ax, bz - az)
            if length < 20:
                continue
            dx, dz = (bx - ax) / length, (bz - az) / length
            nx, nz = -dz, dx
            road_yaw = math.degrees(math.atan2(-dz, dx))
            if rng.random() < cars:
                t = rng.uniform(0.15, 0.85) * length
                s = rng.choice((-1, 1)) * w / 4
                px, pz = ax + dx * t + nx * s, az + dz * t + nz * s
                if math.hypot(px, pz) > SAFE_R + 40:
                    self.car(px, pz, road_yaw + 90 + rng.uniform(-35, 35), y=0.26)
            if rng.random() < stains:
                t = rng.uniform(0.1, 0.9) * length
                self.stain(ax + dx * t, az + dz * t, y=0.27)
            if rng.random() < fires:
                t = rng.uniform(0.2, 0.8) * length
                s = rng.choice((-1, 1)) * (w / 2 + 2)
                fx, fz = ax + dx * t + nx * s, az + dz * t + nz * s
                if math.hypot(fx, fz) > SAFE_R + 40:
                    self.fire(fx, fz, smoke=rng.random() < 0.3)
            if lamps and length > 40:
                t = length / 2
                s = rng.choice((-1, 1)) * (w / 2 + 1.5)
                lx, lz = ax + dx * t + nx * s, az + dz * t + nz * s
                if math.hypot(lx, lz) > SAFE_R + 20:
                    self.lamp(lx, lz, road_yaw, working=rng.random() < 0.18)

    def overgrowth(self, cx, cz, radius, n):
        """Bäume und Schutt in Lücken zwischen den Häusern (die Stadt wächst zu)."""
        rng = self.rng
        placed = 0
        for _ in range(n * 8):
            if placed >= n:
                break
            a, r = rng.uniform(0, 2 * math.pi), radius * math.sqrt(rng.random())
            x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
            if math.hypot(x, z) < SAFE_R + 60 or not self.free(x, z, 4, road_pad=2):
                continue
            if rng.random() < 0.6:
                self.tree(x, z, dead=rng.random() < 0.4)
            else:
                self.rubble(x, z, rng.uniform(4, 8))
            self.occupied.append((x, z, 3))
            placed += 1

    def tree(self, x, z, dead=False):
        b, rng = self.b, self.rng
        g = self.H(x, z)
        if dead:
            h = rng.uniform(8, 13)
            b.box("Nature", "Trunk", (1.3, h, 1.3), (x, g + h / 2 - 0.6, z), (66, 54, 46), "Wood",
                  angles=(rng.uniform(-8, 8), 0, rng.uniform(-8, 8)))
            for _ in range(2):
                b.box("Nature", "Branch", (0.6, rng.uniform(3, 5), 0.6), (x, g + h * rng.uniform(0.6, 0.9), z), (66, 54, 46), "Wood",
                      angles=(rng.uniform(-50, 50), rng.uniform(0, 180), rng.uniform(-50, 50)), props={"CanCollide": False})
            return
        if rng.random() < 0.6:
            h = rng.uniform(13, 21)
            b.box("Nature", "Trunk", (1.5, h, 1.5), (x, g + h / 2 - 0.6, z), (92, 66, 44), "Wood")
            tone = rng.randint(-8, 8)
            for w, level in ((10.5, 0.4), (7.4, 0.62), (4.2, 0.84)):
                b.box("Nature", "Needles", (w, 4.2, w), (x, g + h * level + 1.2, z), (44 + tone, 82 + tone, 46), "Grass",
                      angles=(0, rng.uniform(0, 90), 0), props={"CanCollide": False})
        else:
            h = rng.uniform(9, 14)
            b.box("Nature", "Trunk", (1.8, h, 1.8), (x, g + h / 2 - 0.6, z), (100, 70, 45), "Wood")
            r = rng.uniform(9, 13)
            b.add("Nature", "Leaves", (r, r, r), (x, g + h + r / 3, z), (rng.randint(70, 100), rng.randint(100, 120), 48), "Grass",
                  props={"Shape": "Ball", "CanCollide": False})

    def rock(self, x, z):
        rng = self.rng
        s = rng.uniform(4, 11)
        g = self.H(x, z)
        self.b.box("Nature", "Rock", (s, s * 0.7, s * 1.2), (x, g + s * 0.15, z),
                   rng.choice(((115, 115, 110), (104, 102, 98), (126, 120, 108))), "Slate",
                   angles=(rng.uniform(-12, 12), rng.uniform(0, 360), rng.uniform(-12, 12)))


    # ---------- Apokalypse: Staus, Quarantäne, Leichen, Camps, Plakate ----------
    def corpse(self, x, z, yaw=None, y=None):
        """Leiche am Boden (liegende Figur aus Blöcken) mit Blutfleck."""
        b, rng = self.b, self.rng
        yaw = rng.uniform(0, 360) if yaw is None else yaw
        g = (self.H(x, z) + 0.4) if y is None else y
        m = self.bm.rot(0, yaw, 0)
        skin = rng.choice(((150, 160, 130), (120, 130, 104), (170, 150, 130)))
        cloth = rng.choice(((60, 64, 80), (90, 60, 50), (70, 80, 60), (110, 104, 90)))

        def at(lx, lz, ly=0.5):
            return (x + m[0][0] * lx + m[0][2] * lz, g + ly, z + m[2][0] * lx + m[2][2] * lz)
        self.stain(x, z, y=g + 0.02)
        b.box("Decor", "CorpseTorso", (2, 1, 2.2), at(0, 0), cloth, "Fabric", angles=(0, yaw, rng.uniform(-8, 8)),
              props={"CanCollide": False})
        b.box("Decor", "CorpseHead", (1.1, 1, 1.1), at(0, -1.8), skin, "SmoothPlastic", angles=(0, yaw + rng.uniform(-30, 30), 0),
              props={"CanCollide": False})
        for side in (-1, 1):
            b.box("Decor", "CorpseLimb", (0.9, 0.8, 2), at(side * 0.6, 2.1, 0.4), cloth, "Fabric",
                  angles=(0, yaw + side * rng.uniform(0, 25), 0), props={"CanCollide": False})
            b.box("Decor", "CorpseLimb", (0.8, 0.7, 1.9), at(side * 1.6, -0.2, 0.4), skin, "SmoothPlastic",
                  angles=(0, yaw + side * rng.uniform(30, 80), 0), props={"CanCollide": False})

    def traffic_jam(self, points, count):
        """Stau der Flucht: Autowracks Stoßstange an Stoßstange auf einer Landstraße, ein umgekippter Bus."""
        rng = self.rng
        total = sum(math.hypot(bx - ax, bz - az) for (ax, az), (bx, bz) in zip(points, points[1:]))
        placed = 0
        t = rng.uniform(0, 10)
        while placed < count and t < total:
            acc = 0
            for (ax, az), (bx, bz) in zip(points, points[1:]):
                length = math.hypot(bx - ax, bz - az)
                if acc + length >= t:
                    u = (t - acc) / length
                    dx, dz = (bx - ax) / length, (bz - az) / length
                    lane = rng.choice((-1, 1)) * 5
                    x, z = ax + (bx - ax) * u - dz * lane, az + (bz - az) * u + dx * lane
                    yaw = math.degrees(math.atan2(-dz, dx)) + 90 + rng.uniform(-12, 12)
                    if placed == count // 2:
                        self.bus(x, z, yaw + 90)
                    else:
                        self.car(x, z, yaw, y=0.26)
                    if rng.random() < 0.25:
                        self.corpse(x + rng.uniform(-6, 6), z + rng.uniform(-6, 6), y=0.27)
                    break
                acc += length
            placed += 1
            t += rng.uniform(13, 20)

    def bus(self, x, z, yaw):
        g = max(self.H(x, z) + 0.4, 0.26)
        self.b.box("Cover", "BusBody", (8, 8, 30), (x, g + 3.6, z), (190, 150, 40), "CorrodedMetal", angles=(0, yaw, 84))
        self.b.box("Decor", "BusWindows", (8.2, 2, 28), (x, g + 3.6, z), (30, 34, 38), "Slate", angles=(0, yaw, 84))
        self.smoke_column(x, g + 6, z)

    def warning_sign(self, x, z, yaw, title, subtitle, color=(226, 56, 48)):
        g = self.H(x, z) + 0.4
        m = self.bm.rot(0, yaw, 0)
        for side in (-1, 1):
            px, pz = x + m[0][0] * side * 4.5, z + m[2][0] * side * 4.5
            self.b.box("Decor", "SignPost", (0.4, 7, 0.4), (px, g + 3.5, pz), (60, 60, 64), "Metal")
        self.b.sign2("Warn_" + title[:10], (10, 3, 0.25), (x, g + 6.4, z), title, subtitle, (230, 226, 210), color, (40, 40, 40),
                     angles=(0, yaw, self.rng.uniform(-8, 8)))

    def quarantine(self, x, z, yaw, width=30):
        """Verlassene Quarantäne-Sperre quer über eine Straße: Zaun, Sandsäcke, Schilder, Militärfahrzeug, Leichen."""
        rng = self.rng
        self.barricade(x, z, yaw, width)
        m = self.bm.rot(0, yaw, 0)
        for side in (-1, 1):
            px, pz = x + m[0][0] * side * (width / 2 + 10), z + m[2][0] * side * (width / 2 + 10)
            self.warning_sign(px, pz, yaw + 180 * (side < 0), "QUARANTÄNE", "INFIZIERT · NICHT BETRETEN")
        hx, hz = x + m[0][2] * 14, z + m[2][2] * 14
        self.car(hx, hz, yaw + rng.uniform(-30, 30), burned=rng.random() < 0.5, color=(84, 92, 70))
        for _ in range(3):
            self.corpse(x + rng.uniform(-14, 14), z + rng.uniform(-14, 14))

    def mass_grave(self, x, z):
        b, rng = self.b, self.rng
        g = self.H(x, z) + 0.4
        b.box("Ground", "Grave", (40, 0.3, 14), (x, g - 0.05, z), (60, 48, 38), "Ground", angles=(0, 15, 0))
        for k in range(14):
            self.body_bag(x + rng.uniform(-17, 17), z + rng.uniform(-5, 5), 15 + rng.uniform(-20, 20))
        for k in range(6):
            cx, cz = x - 20 + k * 8, z + 12
            b.box("Decor", "Cross", (0.4, 3.4, 0.4), (cx, self.H(cx, cz) + 2, cz), (110, 86, 60), "Wood")
            b.box("Decor", "Cross", (1.8, 0.4, 0.4), (cx, self.H(cx, cz) + 2.8, cz), (110, 86, 60), "Wood")
        b.box("Cover", "DirtPile", (16, 4, 8), (x + 26, g + 1, z - 8), (80, 64, 48), "Ground", angles=(0, 15, 8))
        self.occupied.append((x, z, 30))

    def survivor_camp(self, x, z, title):
        """Verlassenes Lager von Überlebenden im Wald: Zelte, Feuer, Holzbarrikade, SOS auf dem Boden."""
        b, rng = self.b, self.rng
        for k in range(3):
            a = k * 2.1 + rng.uniform(-0.3, 0.3)
            self.tent(x + math.cos(a) * 12, z + math.sin(a) * 12, math.degrees(-a) + 90,
                      rng.choice(((96, 108, 78), (60, 90, 130), (150, 60, 50))), collapsed=rng.random() < 0.3)
        self.fire(x, z, smoke=False)
        for k in range(10):
            a = k / 10 * math.pi * 2
            px, pz = x + math.cos(a) * 22, z + math.sin(a) * 22
            if rng.random() < 0.7:
                b.box("Cover", "PlankWall", (7, 4, 0.6), (px, self.H(px, pz) + 2.2, pz), (110, 86, 60), "WoodPlanks",
                      angles=(rng.uniform(-8, 8), -math.degrees(a) + 90, rng.uniform(-6, 6)))
        b.floor_text("SOS" + title[:4], (16, 0.1, 7), (x + 8, self.H(x + 8, z - 15) + 0.5, z - 15), "SOS", (230, 230, 230),
                     bg=(60, 50, 40), yaw=rng.uniform(0, 360))
        self.corpse(x + 5, z + 4)
        self.occupied.append((x, z, 26))

    def billboard(self, x, z, yaw, title, subtitle):
        b = self.b
        g = self.H(x, z) + 0.4
        m = self.bm.rot(0, yaw, 0)
        for side in (-1, 1):
            px, pz = x + m[0][0] * side * 8, z + m[2][0] * side * 8
            b.box("Decor", "BillboardPost", (0.8, 12, 0.8), (px, g + 6, pz), (70, 70, 74), "Metal")
        b.sign2("Billboard_" + title[:8], (22, 8, 0.5), (x, g + 15, z), title, subtitle, (230, 230, 220), (180, 30, 30), (40, 40, 40),
                angles=(0, yaw, self.rng.uniform(-6, 6)))

    def litter(self, x, z, y=0.27):
        """Müll am Straßenrand: Säcke, Papier, Tonne."""
        b, rng = self.b, self.rng
        for _ in range(rng.randint(2, 4)):
            kind = rng.random()
            px, pz = x + rng.uniform(-3, 3), z + rng.uniform(-3, 3)
            if kind < 0.45:
                b.box("Decor", "TrashBag", (1.6, 1.3, 1.4), (px, y + 0.6, pz), (24, 24, 26), "Plastic",
                      angles=(rng.uniform(-15, 15), rng.uniform(0, 180), 0), props={"CanCollide": False})
            elif kind < 0.85:
                b.box("Decor", "Paper", (1.2, 0.03, 0.9), (px, y + 0.03, pz), (214, 210, 196), "SmoothPlastic",
                      angles=(0, rng.uniform(0, 180), 0), props={"CanCollide": False, "CanQuery": False})
            else:
                b.cylinder("Cover", "Barrel", 2.2, 3, (px, y + 1.5, pz), rng.choice(((60, 80, 110), (110, 40, 36), (70, 80, 50))),
                           material="CorrodedMetal")

    def crater(self, x, z):
        """Einschlagkrater (Bombardierung): dunkler Boden, Schuttring, Rauch."""
        rng = self.rng
        r = rng.uniform(7, 12)
        g = self.H(x, z)
        self.b.add("Decor", "Crater", (0.2, 2 * r, 2 * r), (x, g + 0.5, z), (36, 32, 30), "Slate", angles=(0, 0, 90),
                   props={"Shape": "Cylinder", "CanCollide": False})
        for k in range(8):
            a = k / 8 * math.pi * 2
            self.rubble(x + math.cos(a) * r, z + math.sin(a) * r, 4, (90, 86, 80), n=2)
        if rng.random() < 0.5:
            self.smoke_column(x, g + 1, z)

    def heli_crash(self, x, z):
        self.helicopter_wreck(x, z, self.rng.uniform(0, 360))
        for _ in range(3):
            self.rubble(x + self.rng.uniform(-12, 12), z + self.rng.uniform(-12, 12), 6, (70, 70, 64))
        for _ in range(2):
            self.corpse(x + self.rng.uniform(-10, 10), z + self.rng.uniform(-10, 10))
        self.occupied.append((x, z, 18))

    # ---------- Safe Zone "Camp Phoenix" (Mitte von Ödstadt) ----------
    def camp(self):
        b, rng = self.b, self.rng
        R, road_w = SAFE_R, ROAD_W
        safe, danger, dark = (96, 210, 120), (215, 85, 45), (34, 36, 40)
        concrete, sand = (128, 126, 120), (176, 158, 118)
        lighten, rgb = self.bm.lighten, self.bm.rgb

        def frame(cx, cz, yaw):
            c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
            return lambda lx, ly, lz: (cx + lx * c + lz * sn, ly, cz - lx * sn + lz * c)

        def facing(x, z, tx=0.0, tz=0.0):
            return math.degrees(math.atan2(x - tx, z - tz))

        # ---------- Safe Zone "Camp Phoenix": Überlebendenlager aus Containern, Wellblech und Holz ----------
        dirt, plank, rust, tarp = (92, 78, 60), (112, 88, 62), (104, 72, 54), (96, 104, 80)
        warm = rgb(255, 196, 120)
        # Boden: festgetretene Erde, Holzstege zu den Toren
        b.add("Ground", "CampFloor", (1.1, 2 * R + 30, 2 * R + 30), (0, -0.45, 0), dirt, "Ground",
              angles=(0, 0, 90), props={"Shape": "Cylinder"})
        b.add("Ground", "Plaza", (1.0, 330, 330), (0, -0.55, 0), (84, 74, 60), "Ground", angles=(0, 0, 90),
              props={"Shape": "Cylinder"})
        for gx, gz in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            yaw = facing(gx, gz)
            f = frame(gx * 60, gz * 60, yaw)
            b.box("Ground", "Walkway", (7, 0.3, 80), f(0, 0.2, 0), plank, "WoodPlanks", angles=(0, yaw, 0))
        b.add("Zone", "SafeZone", (2 * R, 80, 2 * R), (0, 40, 0), safe, "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

        # Mauer: Container und Wellblech-Platten im Kreis, vier Tore für die Straßen
        gate_half = math.degrees((road_w / 2 + 6) / (R + 6))
        phi = 0.0
        k = 0
        while phi < 360:
            nearest_gate = min(abs(((phi - g) + 180) % 360 - 180) for g in (0, 90, 180, 270))
            container = k % 3 != 2
            length = 20 if container else 10
            step = math.degrees(length / (R + 6))
            mid = phi + step / 2
            if nearest_gate > gate_half + step / 2:
                a = math.radians(mid)
                x, z = math.cos(a) * (R + 6), math.sin(a) * (R + 6)
                if container:
                    b.box("Walls", "WallContainer", (length, 8.5, 8), (x, 3.9, z),
                          rng.choice(((110, 60, 48), (60, 86, 110), (84, 98, 70), (150, 120, 60), (90, 90, 90))), "CorrodedMetal",
                          angles=(0, -mid + 90, 0))
                else:
                    b.box("Walls", "WallSheet", (length + 1, 9, 0.6), (x, 4.2, z), rust, "CorrodedMetal",
                          angles=(rng.uniform(-4, 4), -mid + 90, rng.uniform(-3, 3)))
                    for side in (-1, 1):
                        pa = math.radians(mid + side * step / 2)
                        b.box("Walls", "WallPost", (0.8, 10, 0.8), (math.cos(pa) * (R + 6), 4.6, math.sin(pa) * (R + 6)), plank, "Wood")
                k += 1
            phi += step
        for gx, gz in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            yaw = facing(gx, gz)  # Vorderseite zur Mitte
            f = frame(gx * (R + 6), gz * (R + 6), yaw)
            for side in (-1, 1):
                # Wachturm aus Holz mit Scheinwerfer
                tx, ty, tz = f(side * (road_w / 2 + 5), 0, 2)
                for dx in (-2.2, 2.2):
                    for dz in (-2.2, 2.2):
                        b.box("Walls", "GateTowerLeg", (0.8, 14, 0.8), (tx + dx, 6.6, tz + dz), plank, "Wood")
                b.box("Walls", "GateTowerDeck", (7, 0.6, 7), (tx, 13.7, tz), plank, "WoodPlanks")
                b.box("Cover", "GateTowerWall", (7, 3, 0.5), f(side * (road_w / 2 + 5), 15.4, -1.3), rust, "CorrodedMetal",
                      angles=(0, yaw, 0))
                b.box("Decor", "GateTowerRoof", (7.6, 0.4, 7.6), (tx, 18.6, tz), rust, "CorrodedMetal", angles=(rng.uniform(-6, 6), yaw, 4))
                b.box("Decor", "Searchlight", (1.4, 1.4, 1.8), f(side * (road_w / 2 + 5), 16.2, -2), (230, 226, 210), "Neon",
                      angles=(-25, yaw + 180, 0), children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                          "Face": "Front", "Range": 60, "Brightness": 2, "Angle": 40, "Color": rgb(255, 240, 210)}}])
                # offener Torflügel aus Wellblech
                b.box("Walls", "GateDoor", (road_w / 2, 8, 0.5), f(side * (road_w / 2 + 2), 4.2, -road_w / 4 - 1), rust, "CorrodedMetal",
                      angles=(0, yaw + side * 75, 0))
                b.box("Cover", "Sandbags", (6, 2.6, 2.4), f(side * (road_w / 2 + 5), 1.3, -9), (150, 134, 98), "Fabric",
                      angles=(0, yaw, 0))
            b.box("Decor", "GateBanner", (road_w + 10, 3.6, 0.3), f(0, 14.2, 0.2), (190, 180, 150), "Fabric",
                  angles=(0, yaw, rng.uniform(-2, 2)))
            b.sign2("GateSignOut", (16, 3, 0.25), f(0, 14.2, 0.5), "CAMP PHOENIX", "SICHERE ZONE · KEINE WAFFEN",
                    (190, 180, 150), (150, 40, 30), (60, 50, 40), angles=(0, yaw + 180, 0))
            b.sign2("GateSignIn", (16, 3, 0.25), f(0, 14.2, -0.1), "DRAUSSEN", "ZOMBIES · PVP NACH 5 SEKUNDEN",
                    (190, 180, 150), (150, 40, 30), (60, 50, 40), angles=(0, yaw, 0))

        # Mitte: Lagerfeuer (Spawn), Baumstämme zum Sitzen, Fahnenmast mit Fetzen
        for k in range(10):
            a = 2 * math.pi * k / 10
            x, z = math.cos(a) * 13, math.sin(a) * 13
            b.spawn(x, z, yaw=facing(x, z) + 180)
        for k in range(12):
            a = 2 * math.pi * k / 12
            b.box("Decor", "FireStone", (1.6, 1.0, 1.6), (math.cos(a) * 3.4, 0.5, math.sin(a) * 3.4), (110, 106, 100), "Slate",
                  angles=(0, rng.uniform(0, 90), 0))
        b.box("Decor", "Bonfire", (2.4, 1.2, 2.4), (0, 0.8, 0), (255, 130, 40), "Neon", props={"CanCollide": False},
              children=[{"Name": "Fire", "ClassName": "Fire", "Properties": {"Size": 9, "Heat": 12, "Color": rgb(255, 140, 40),
                                                                                "SecondaryColor": rgb(150, 40, 20)}},
                        {"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 40, "Brightness": 2.4, "Color": warm}},
                        {"Name": "Smoke", "ClassName": "Smoke", "Properties": {"Color": rgb(60, 56, 52), "Opacity": 0.25,
                                                                                 "RiseVelocity": 8, "Size": 10}}])
        for k in range(5):
            a = 2 * math.pi * (k + 0.3) / 5
            b.box("Cover", "LogBench", (6, 1.2, 1.2), (math.cos(a) * 8.5, 0.7, math.sin(a) * 8.5), (96, 70, 48), "Wood",
                  angles=(0, -math.degrees(a) + 90, 0))
        b.box("Decor", "FlagPole", (0.5, 20, 0.5), (0, 10, -22), (70, 66, 60), "Wood")
        b.box("Decor", "Flag", (7, 4, 0.2), (3.8, 17.5, -22), (150, 40, 32), "Fabric", angles=(0, 0, rng.uniform(-6, 6)))
        b.sign2("CampSign", (14, 3.6, 0.3), (0, 4.2, -18), "CAMP PHOENIX", "LETZTE SICHERE ZONE", (110, 88, 62), (230, 220, 190),
                (220, 210, 180), angles=(0, 0, 0))
        b.sign2("CampSignBack", (14, 3.6, 0.3), (0, 4.2, -18.4), "CAMP PHOENIX", "LETZTE SICHERE ZONE", (110, 88, 62),
                (230, 220, 190), (220, 210, 180), angles=(0, 180, 0))
        for side in (-1, 1):
            b.box("Decor", "CampSignPost", (0.5, 6, 0.5), (side * 6.6, 3, -18.2), plank, "Wood")

        def stand(key, title, subtitle, cx, cz, color, goods):
            """Behelfsmäßiger Stand: Bretter-Theke, Wellblech-Rückwand, schräge Plane, Laterne, handgemaltes Schild."""
            yaw = facing(cx, cz)
            f = frame(cx, cz, yaw)
            rot_y = (0, yaw, 0)
            b.box("Stands", "StandFloor", (16, 0.4, 11), f(0, 0.3, 0.5), plank, "WoodPlanks", angles=rot_y)
            b.box("Stands", "StandCounter", (13, 3.4, 1.6), f(0, 1.9, -3.4), (96, 72, 52), "WoodPlanks", angles=rot_y)
            b.box("Stands", "StandCounterTop", (13.6, 0.3, 2.2), f(0, 3.7, -3.4), (80, 62, 46), "WoodPlanks", angles=rot_y)
            b.box("Stands", "StandBack", (16, 9, 0.6), f(0, 4.8, 5.6), rust, "CorrodedMetal", angles=(0, yaw, rng.uniform(-2, 2)))
            for side in (-1, 1):
                b.box("Stands", "StandPost", (0.6, 10, 0.6), f(side * 7.6, 5, -5.6), plank, "Wood", angles=rot_y)
                b.box("Stands", "StandSide", (0.5, 7, 9), f(side * 7.6, 4, 1), rust, "CorrodedMetal", angles=(0, yaw, side * 3))
            b.box("Stands", "StandRoof", (17.5, 0.3, 13), f(0, 9.6, 0), color, "Fabric", angles=(yaw_tilt_deg(8), yaw, 0))
            b.sign2("StandSign_" + key, (11, 3, 0.25), f(0, 6.2, -4.3), title, subtitle, (110, 88, 62), (230, 220, 190), (220, 210, 180),
                    angles=(0, yaw, rng.uniform(-4, 4)))
            # Händler hinter der Theke (einfache Figur)
            b.box("Stands", "Vendor", (2, 2.2, 1.1), f(0, 4.9, -1.2), (60, 64, 58), "Fabric", angles=rot_y)
            b.box("Stands", "VendorHead", (1.2, 1.2, 1.2), f(0, 6.7, -1.2), (196, 156, 126), "SmoothPlastic", angles=rot_y)
            b.box("Stands", "VendorCap", (1.3, 0.4, 1.4), f(0, 7.4, -1.25), (70, 70, 64), "Fabric", angles=rot_y)
            for lx, ly, sx, sy, sz, col, mat in goods:
                b.box("Stands", "Goods", (sx, sy, sz), f(lx, ly, 5.0), col, mat, angles=rot_y)
            b.add("Stands", key, (2, 2, 2), f(0, 2.5, -5.4), color, "SmoothPlastic", angles=rot_y,
                  props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
            b.box("Stands", "Lantern", (0.8, 1.1, 0.8), f(-5, 8.2, -4.5), (255, 200, 120), "Neon", angles=rot_y,
                  children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 18, "Brightness": 1.2, "Color": warm}}])
            for k in range(3):
                b.box("Cover", "Crate", (2.6, 2.6, 2.6), f(rng.uniform(-9, 9), 1.3, rng.uniform(6, 9)), (120, 96, 64), "WoodPlanks",
                      angles=(0, yaw + rng.uniform(-20, 20), 0))

        def yaw_tilt_deg(t):
            return t

        gun = (40, 42, 46)
        stand("Stand_Weapons", "WAFFEN", "MUNITION · TAUSCH", -36, 40, (110, 60, 48),
              [(-4.5, 6.8, 4.6, 0.7, 0.4, gun, "Metal"), (0.5, 6.8, 4.0, 0.6, 0.4, gun, "Metal"),
               (4.6, 6.8, 2.6, 0.7, 0.4, gun, "Metal"), (-4.5, 4.8, 3.6, 0.6, 0.4, gun, "Metal"),
               (0.5, 4.8, 5.0, 0.7, 0.4, gun, "Metal"), (4.6, 4.8, 3.0, 0.6, 0.4, gun, "Metal")])
        med = (210, 208, 200)
        stand("Stand_Items", "SANI", "VERBAND · WESTEN", 36, 40, (150, 140, 120),
              [(-4.5, 4.6, 2.4, 1.6, 1.4, med, "SmoothPlastic"), (-1.5, 4.6, 2.4, 1.6, 1.4, med, "SmoothPlastic"),
               (1.5, 4.6, 2.4, 1.6, 1.4, med, "SmoothPlastic"), (4.5, 4.6, 2.4, 1.6, 1.4, med, "SmoothPlastic"),
               (-3, 6.6, 3.0, 1.6, 1.4, (70, 90, 70), "Fabric"), (3, 6.6, 3.0, 1.6, 1.4, (70, 90, 70), "Fabric")])
        stand("Stand_Vehicles", "WERKSTATT", "FAHRZEUGE", -34, -48, (84, 98, 70),
              [(-4, 6.2, 5, 2.4, 0.2, (60, 60, 64), "Metal"), (3.5, 6.2, 5, 2.4, 0.2, (60, 60, 64), "Metal")])

        # Fahrzeuge der Werkstatt (Schrott, aufgebockt)
        def car(x, z, yaw, color):
            f = frame(x, z, yaw)
            body = lighten(color, -0.35)
            b.box("Decor", "CarBody", (5.6, 2.2, 11), f(0, 2.4, 0), body, "CorrodedMetal", angles=(0, yaw, 0))
            b.box("Decor", "CarCabin", (5.0, 2.0, 5.4), f(0, 4.4, 0.6), lighten(body, -0.2), "CorrodedMetal", angles=(0, yaw, 0))
            for sx in (-1, 1):
                for sz in (-1, 1):
                    b.box("Decor", "CarJack", (1.2, 1.4, 1.2), f(sx * 2.2, 0.7, sz * 3.6), (60, 60, 64), "Metal", angles=(0, yaw, 0))
        car(-60, -40, 30, (150, 70, 50))
        car(-56, -64, 50, (70, 100, 130))

        # Lager: Container mit offener Tür zur Mitte
        lx, lz = 62, -32
        yaw = facing(lx, lz)
        f = frame(lx, lz, yaw)
        for side in (-1, 1):
            b.box("Stands", "StashWall", (0.6, 8.6, 20), f(side * 4.2, 4.3, 0), (60, 86, 64), "CorrodedMetal", angles=(0, yaw, 0))
        b.box("Stands", "StashRoof", (9, 0.6, 20), f(0, 8.9, 0), (52, 76, 56), "CorrodedMetal", angles=(0, yaw, 0))
        b.box("Stands", "StashBack", (9, 8.6, 0.6), f(0, 4.3, 9.7), (52, 76, 56), "CorrodedMetal", angles=(0, yaw, 0))
        b.box("Stands", "StashFloor", (8.4, 0.4, 20), f(0, 0.3, 0), (70, 70, 72), "DiamondPlate", angles=(0, yaw, 0))
        for side in (-1, 1):
            b.box("Stands", "StashDoor", (0.3, 8.4, 4.2), f(side * 6.2, 4.3, -11.6), (60, 86, 64), "CorrodedMetal",
                  angles=(0, yaw + side * 60, 0))
        for k in range(4):
            b.box("Stands", "StashCrate", (2.6, 2.6, 2.6), f(rng.uniform(-2, 2), 1.8 + (k % 2) * 2.6, 4 + (k // 2) * 3),
                  (120, 96, 64), "WoodPlanks", angles=(0, yaw + rng.uniform(-10, 10), 0))
        b.sign2("StandSign_Stash", (9, 2.6, 0.25), f(0, 10.6, -9.8), "LAGER", "DEINS BLEIBT DEINS", (110, 88, 62), (230, 220, 190),
                (220, 210, 180), angles=(0, yaw, 3))
        b.add("Stands", "Stash", (2, 2, 2), f(0, 2.5, -12), (226, 178, 52), "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

        # Rückweg zum Hub: Hubschrauber-Landeplatz (Evakuierung), Landefeld = Tor
        hx, hz = 22, -72
        b.add("Decor", "Helipad", (0.4, 22, 22), (hx, 0.2, hz), (70, 70, 66), "Concrete", angles=(0, 0, 90),
              props={"Shape": "Cylinder"})
        b.floor_text("HelipadH", (9, 0.1, 9), (hx, 0.45, hz), "H", (220, 214, 190), yaw=0)
        for k in range(10):
            a = 2 * math.pi * k / 10
            b.add("Decor", "PadTire", (1.2, 2.4, 2.4), (hx + math.cos(a) * 12, 0.6, hz + math.sin(a) * 12), (26, 26, 26), "Rubber",
                  angles=(0, -math.degrees(a), 90), props={"Shape": "Cylinder"})
        b.box("Decor", "HeliBody", (6, 5, 14), (hx + 20, 2.8, hz - 2), (70, 78, 62), "Metal", angles=(0, 30, 0))
        b.box("Decor", "HeliTail", (1.4, 1.4, 12), (hx + 25, 3.6, hz + 9), (70, 78, 62), "Metal", angles=(0, 30, 0))
        b.box("Decor", "HeliGlass", (5, 2.6, 4), (hx + 17, 3.6, hz - 7), (40, 50, 58), "Glass", angles=(0, 30, 0),
              props={"Transparency": 0.4})
        b.box("Decor", "HeliRotor", (26, 0.3, 1.2), (hx + 20, 5.6, hz - 2), (40, 40, 40), "Metal", angles=(0, 70, 0))
        b.sign2("HubGateSign", (12, 3, 0.25), (hx, 6.5, hz + 12.5), "EVAKUIERUNG", "LANDEFELD BETRETEN = ZURÜCK ZUM HUB",
                (110, 88, 62), (230, 220, 190), (220, 210, 180), angles=(0, 180, 0))
        for side in (-1, 1):
            b.box("Decor", "HubSignPost", (0.5, 6, 0.5), (hx + side * 5.4, 3, hz + 12.6), plank, "Wood")
        b.add("Portals", "Portal_Hub", (14, 0.4, 14), (hx, 0.5, hz), (120, 185, 235), "Neon",
              props={"CanCollide": False, "Transparency": 0.75})

        # Zelte, Pritschen, Generator, Lichtmasten, Wassertank, Kisten
        for tx, tz in ((-66, 42), (-58, 66), (66, 46), (58, 68), (-76, 14), (76, -12)):
            yaw = facing(tx, tz)
            f = frame(tx, tz, yaw)
            b.box("Decor", "TentFloor", (8, 0.2, 10), f(0, 0.2, 0), (70, 70, 64), "Fabric", angles=(0, yaw, 0))
            b.add("Decor", "Tent", (8, 5, 5), f(0, 2.6, -2.5), tarp, "Fabric", angles=(0, yaw, 0), cls="WedgePart")
            b.add("Decor", "Tent", (8, 5, 5), f(0, 2.6, 2.5), tarp, "Fabric", angles=(0, yaw + 180, 0), cls="WedgePart")
            b.box("Decor", "Cot", (2.4, 0.8, 6), f(-1.5, 0.7, 0), (90, 96, 76), "Fabric", angles=(0, yaw, 0))
        b.box("Cover", "Generator", (4, 3, 2.6), (46, 1.5, 20), (150, 130, 50), "Metal")
        b.box("Decor", "GeneratorPipe", (0.4, 3, 0.4), (47.4, 4, 20.6), (40, 40, 40), "Metal",
              children=[{"Name": "Smoke", "ClassName": "Smoke", "Properties": {"Color": rgb(50, 48, 46), "Opacity": 0.2,
                                                                                 "RiseVelocity": 5, "Size": 2}}])
        for k in range(4):
            a = math.radians(45 + 90 * k + 12)
            x, z = math.cos(a) * 58, math.sin(a) * 58
            b.box("Decor", "LightPole", (0.6, 13, 0.6), (x, 6.5, z), plank, "Wood")
            b.box("Decor", "Floodlight", (1.6, 1, 1.2), (x, 12.8, z), (255, 236, 200), "Neon",
                  children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                      "Face": "Bottom", "Range": 45, "Brightness": 1.6, "Angle": 80, "Color": rgb(255, 230, 190)}}])
        for k in range(16):
            a = math.radians(rng.uniform(0, 360))
            r = rng.uniform(66, 92)
            x, z = math.cos(a) * r, math.sin(a) * r
            if min(abs(x), abs(z)) < 10:
                continue
            if rng.random() < 0.5:
                b.box("Decor", "SupplyCrate", (3, 3, 3), (x, 1.5, z), (110, 90, 62), "WoodPlanks", angles=(0, rng.uniform(0, 90), 0))
            else:
                b.cylinder("Decor", "Barrel", 2.2, 3, (x, 1.5, z), rng.choice(((60, 80, 110), (110, 40, 36), (70, 80, 50))),
                           material="CorrodedMetal")

        # dezenter grüner Ring am Boden (Grenze der Safe Zone)
        n = 72
        for k in range(n):
            a = 2 * math.pi * (k + 0.5) / n
            b.box("Zone", "SafeEdge", (2 * math.pi * (R - 1) / n + 0.2, 0.12, 1.0), (math.cos(a) * (R - 1), 0.2, math.sin(a) * (R - 1)),
                  safe, "Neon", angles=(0, -math.degrees(a) + 90, 0),
                  props={"Transparency": 0.55, "CanCollide": False, "CanQuery": False, "CanTouch": False})
        # Vorfeld: Barrikaden aus Containern und Autowracks
        for k in range(10):
            a = 2 * math.pi * (k + 0.5) / 10
            if min(abs(math.cos(a)), abs(math.sin(a))) < 0.2:
                continue
            x, z = math.cos(a) * 135, math.sin(a) * 135
            self.b.container(x, z, along_x=abs(math.sin(a)) > 0.7, color=rng.choice(((90, 110, 76), (150, 60, 50), (60, 100, 150))))

    # ---------- Rote Zonen: Linie am Boden, Kontrollpunkte an jeder Straße ----------
    def redzones(self):
        b, rng = self.b, self.rng
        red = (226, 56, 48)
        for key, radius in REDZONES.items():
            title, rx, rz, _ = PLACES[key]
            b.add("Redzones", "Redzone_" + key, (2 * radius, 160, 2 * radius), (rx, 70, rz), red, "SmoothPlastic",
                  props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False,
                         "Attributes": {"Attributes": {"Title": {"String": title}}}})
            n = int(2 * math.pi * radius / 10)
            for k in range(n):
                a = 2 * math.pi * (k + 0.5) / n
                px, pz = rx + math.cos(a) * radius, rz + math.sin(a) * radius
                if abs(px) > HALF - 10 or abs(pz) > HALF - 10 or self.terrain.is_water(px, pz):
                    continue
                b.box("Redzones", "RedLine", (2 * math.pi * radius / n + 0.1, 0.1, 1.6), (px, self.H(px, pz) + 0.47, pz),
                      red if k % 2 == 0 else (236, 236, 236), "SmoothPlastic", angles=(0, -math.degrees(a) + 90, 0),
                      props={"CanCollide": False, "CanQuery": False, "CanTouch": False})
            # Kontrollpunkte: wo die Grenze eine Straße schneidet
            done = []
            for ax, az, bx, bz, w in list(self.roads):
                dx, dz = bx - ax, bz - az
                length = math.hypot(dx, dz)
                if length < 1:
                    continue
                ux, uz = dx / length, dz / length
                fx, fz = ax - rx, az - rz
                pb_ = fx * ux + fz * uz
                cc = fx * fx + fz * fz - radius * radius
                disc = pb_ * pb_ - cc
                if disc < 0:
                    continue
                for t in (-pb_ - math.sqrt(disc), -pb_ + math.sqrt(disc)):
                    if 2 < t < length - 2:
                        x, z = ax + ux * t, az + uz * t
                        if any(math.hypot(x - ox, z - oz) < 30 for ox, oz in done):
                            continue
                        done.append((x, z))
                        out = 1 if (x - rx) * ux + (z - rz) * uz > 0 else -1
                        self.checkpoint(x, z, ux * out, uz * out, w, title)

    def checkpoint(self, x, z, ox, oz, width, title):
        """Torbogen quer über die Straße: außen ROTE ZONE, innen AUSGANG, Sperren mit Lücke, rotes Licht."""
        b = self.b
        red, safe = (226, 56, 48), (96, 210, 120)
        yaw = self.yaw_to(ox, oz)  # Vorderseite nach außen
        m = self.bm.rot(0, yaw, 0)
        g = max(self.H(x, z) + 0.4, 0.26)

        def at(lx, ly, lz):
            return (x + m[0][0] * lx + m[0][2] * lz, g + ly, z + m[2][0] * lx + m[2][2] * lz)
        for s in (-1, 1):
            b.box("Walls", "CheckpointPost", (1.2, 12, 1.2), at(s * (width / 2 + 1), 6, 0), (40, 40, 44), "Metal", angles=(0, yaw, 0))
            b.box("Cover", "Barrier", (6, 3.2, 1.6), at(s * 6.5, 1.6, -4), (165, 162, 155), "Concrete", angles=(0, yaw, 0))
        b.box("Walls", "CheckpointBeam", (width + 4, 1.4, 1.2), at(0, 12.4, 0), red, "Metal", angles=(0, yaw, 0))
        b.sign2("RedzoneSignOut", (16, 3.4, 0.3), at(0, 15, -0.5), "ROTE ZONE", title + " · PVP SOFORT",
                (40, 16, 14), red, (240, 230, 228), angles=(0, yaw, 0), glow=red)
        b.sign2("RedzoneSignIn", (16, 3.4, 0.3), at(0, 15, 0.5), "AUSGANG", "ROTE ZONE ENDE", (24, 28, 26), safe,
                (230, 235, 230), angles=(0, yaw + 180, 0), glow=safe)
        b.box("Decor", "CheckpointLight", (2, 0.8, 0.8), at(0, 11.4, 0), (255, 50, 40), "Neon", angles=(0, yaw, 0),
              children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 34, "Brightness": 1.6,
                                                                                      "Color": self.bm.rgb(255, 60, 50)}}])


def find_spot(w, x, z, r, tries=80):
    """Freie, ebene Stelle nahe (x, z) suchen (Spirale nach außen)."""
    for k in range(tries):
        a = k * 2.4
        d = 3.0 * k
        px, pz = x + math.cos(a) * d, z + math.sin(a) * d
        if w.free(px, pz, r, road_pad=3) and w.terrain.slope(px, pz) < 0.25:
            return px, pz
    return None


def activities(w):
    """Spots mit Sachen zu tun (ActivityService): Zombienester, Vorratslager, Funkgerät, Horden-Sammelpunkte."""
    b = w.b

    def marker(kind, x, z, title, r):
        found = find_spot(w, x, z, r)
        if not found:
            return None
        px, pz = found
        g = w.H(px, pz) + 0.4
        b.add("Activities", "Act_" + kind, (4, 2, 4), (px, g + 1, pz), (255, 255, 255), "SmoothPlastic",
              angles=(0, w.rng.uniform(0, 360), 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False,
                     "Attributes": {"Attributes": {"Title": {"String": title}}}})
        if kind != "Horde":
            w.occupied.append((px, pz, r))
        return px, pz

    nests = [(-260, 360, "ÖDSTADT NORD"), (380, -120, "ÖDSTADT OST"), (-120, -400, "ÖDSTADT SÜD"), (-420, -160, "ÖDSTADT WEST"),
             (-180, 1270, "NORDHEIM"), (1240, 600, "SANDBACH"), (-1220, -170, "ALTENFELD"), (520, -1230, "MÜHLDORF"),
             (-1080, -1130, "JVA SCHWARZWALD"), (-1120, 1060, "FORT EISEN"), (1200, -960, "INDUSTRIEHAFEN"),
             (-420, 860, "NORDWALD"), (700, 900, "TEICHWALD"), (-900, -700, "SÜDWESTWALD"), (950, -150, "OSTHÜGEL")]
    for x, z, title in nests:
        if marker("Nest", x, z, title, 9):
            pass
    caches = [(-300, 100, "POLIZEIWACHE"), (330, 260, "ST. MARIEN"), (230, -300, "EVAKUIERUNGSLAGER"), (-1100, 1110, "FORT EISEN"),
              (-1180, 1200, "FORT EISEN"), (1100, -980, "INDUSTRIEHAFEN"), (-1040, -1100, "JVA SCHWARZWALD"),
              (1000, 1200, "FLUGPLATZ"), (1150, 1290, "FLUGPLATZ"), (-860, -20, "TANKSTELLE WEST"), (890, 140, "TANKSTELLE OST"),
              (165, -925, "TANKSTELLE SÜD"), (1000, -600, "HOF KRÜGER"), (-840, 760, "HOF LINDE"), (-230, 1110, "NORDHEIM"),
              (1110, 480, "SANDBACH"), (-1110, -280, "ALTENFELD"), (400, -1110, "MÜHLDORF"), (-520, -740, "FUNKTURM"),
              (60, 240, "INNENSTADT"), (-150, -200, "INNENSTADT")]
    for x, z, title in caches:
        marker("Cache", x, z, title, 4)
    marker("Radio", -540, -770, "FUNKTURM", 4)
    for k, (key, title, x, z) in enumerate(OUTPOSTS):
        marker("Cache", x + 8, z + 8, title, 4)
        if k % 3 == 0:
            marker("Nest", x - 30, z + 40, title, 9)
    survivors = [(-200, 1180, "NORDHEIM"), (1180, 560, "SANDBACH"), (-1180, -220, "ALTENFELD"), (460, -1180, "MÜHLDORF"),
                 (260, -230, "EVAKUIERUNGSLAGER"), (-420, 300, "ÖDSTADT"), (420, -300, "ÖDSTADT"), (-910, 700, "HOF LINDE"),
                 (980, -540, "HOF KRÜGER"), (1080, 1230, "FLUGPLATZ")]
    for x, z, title in survivors:
        marker("Survivor", x, z, title, 3)
    hordes = [(0, 400, "ÖDSTADT NORD"), (400, 0, "ÖDSTADT OST"), (0, -400, "ÖDSTADT SÜD"), (-400, 0, "ÖDSTADT WEST"),
              (-250, 1150, "NORDHEIM"), (1150, 520, "SANDBACH"), (-1150, -250, "ALTENFELD"), (430, -1150, "MÜHLDORF"),
              (230, -260, "EVAKUIERUNGSLAGER"), (1050, 1200, "FLUGPLATZ"), (960, -560, "HOF KRÜGER"), (-880, 720, "HOF LINDE")]
    for x, z, title in hordes:
        marker("Horde", x, z, title, 6)


def build(bm):
    """Baut die Karte Extinction.model.json und das Höhenfeld (ExtinctionTerrainData.lua)."""
    w = World(bm)
    b, rng = w.b, w.rng
    et.write_lua(w.terrain)
    b.box("Ground", "Ground", (SIZE + 120, 4, SIZE + 120), (0, -2, 0), (88, 100, 66), "Grass")
    b.border(SIZE, SIZE, 3, (96, 94, 88), "Slate", barrier=200)

    # Mitte: Safe Zone, dann die besonderen Orte (belegen ihre Fläche, bevor die Straßen Häuser bekommen)
    w.camp()
    w.occupied.append((0, 0, 168))
    w.build_hospital()
    w.build_police()
    w.build_evac()
    w.build_military()
    w.build_harbor()
    w.build_prison()
    w.build_airfield()
    w.build_farm("HofOst")
    w.build_farm("HofWest")
    w.build_radio()
    w.build_church(-170, 1250)
    for key, title, x, z in OUTPOSTS:
        w.build_outpost(key, title, x, z)

    # Landstraßen (leicht geschwungen) und Zufahrten zur Safe Zone
    for pts in highway_points():
        w.road_line(polyline(pts, rng, wobble=14, step=70), HIGHWAY_W)
    for sx, sz in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        w.road(sx * (SAFE_R - 2), sz * (SAFE_R - 2), sx * 180, sz * 180, ROAD_W, lines=False, cracked=False)
    w.build_gas(-860, -50, -860, -132)
    w.build_gas(880, 150, 930, 270)
    w.build_gas(165, -925, 255, -910)

    # Feldwege von der nächsten Landstraße hinauf zu den Außenposten, zum Funkturm und zu den Seeufern
    for _, _, x, z in OUTPOSTS:
        start = w.nearest_highway(x, z)
        if start:
            mid = ((start[0] + x) / 2 + rng.uniform(-40, 40), (start[1] + z) / 2 + rng.uniform(-40, 40))
            dx, dz = x - mid[0], z - mid[1]
            dl = math.hypot(dx, dz) or 1
            w.track([start, mid, (x - dx / dl * 30, z - dz / dl * 30)])

    # Einzelne Häuser und Scheunen an den Landstraßen (außerhalb der Orte)
    def rural_zone(x, z):
        if any(math.hypot(x - fx, z - fz) < fr + 40 for fx, fz, fr in FLATS):
            return None
        return "rural"
    for seg in [s_ for s_ in w.roads if s_[4] == HIGHWAY_W]:
        w.line_buildings(seg[0], seg[1], seg[2], seg[3], seg[4], rural_zone, 0.35, gap=(50, 120))

    # Ödstadt: Straßen mit Gehwegen, dann Häuser an jeder Straße
    first = len(w.roads)
    for pts in w.city_streets():
        w.road_line(pts, ROAD_W, sidewalk=True)
    city_segments = [s for s in w.roads[first:]]

    def city_zone(x, z):
        r = math.hypot(x, z)
        if r < 175 or r > 750:
            return None
        return "downtown" if r < 300 else ("city" if r < 540 else "suburb")
    for seg in city_segments + [s for s in w.roads[:first] if math.hypot((s[0] + s[2]) / 2, (s[1] + s[3]) / 2) < 740]:
        w.line_buildings(seg[0], seg[1], seg[2], seg[3], seg[4], city_zone, 0.95, gap=(4, 12))

    # Dörfer
    villages = [("Nordheim", 0.55), ("Sandbach", 0.6), ("Altenfeld", 0.55), ("Muehldorf", 0.55)]
    village_segments = []
    for key, density in villages:
        _, cx, cz, radius = PLACES[key]
        first = len(w.roads)
        for pts in w.village_streets(cx, cz, radius):
            w.road_line(pts, 18)
        segs = w.roads[first:] + [s for s in w.roads[:first]
                                  if math.hypot((s[0] + s[2]) / 2 - cx, (s[1] + s[3]) / 2 - cz) < radius * 0.9]
        village_segments += w.roads[first:]

        def zone(x, z, cx=cx, cz=cz, radius=radius):
            return "village" if math.hypot(x - cx, z - cz) < radius * 0.95 else None
        for seg in segs:
            w.line_buildings(seg[0], seg[1], seg[2], seg[3], seg[4], zone, density)
        w.overgrowth(cx, cz, radius, 30)

    # Leben auf den Straßen: Wracks, Blut, Feuer, Laternen; Sperren an den Stadtausgängen
    w.street_life(city_segments, cars=0.6, fires=0.08, stains=0.35)
    w.street_life(village_segments, cars=0.35, fires=0.05, stains=0.2)
    w.street_life([s for s in w.roads if s[4] == HIGHWAY_W], cars=0.12, fires=0.0, lamps=False, stains=0.05)
    for sx, sz in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        x, z = sx * 690, sz * 690
        w.barricade(x, z, math.degrees(math.atan2(-sx, -sz)) + 90, 24)
        w.fire(x + (8 if sz else 0) + 14 * abs(sz), z + 14 * abs(sx), smoke=True)
    for _ in range(14):
        ax, az, bx, bz, rw = rng.choice(city_segments)
        t = rng.uniform(0.3, 0.7)
        x, z = ax + (bx - ax) * t, az + (bz - az) * t
        if math.hypot(x, z) > 220:
            w.barricade(x, z, math.degrees(math.atan2(-(bz - az), bx - ax)) + 90, rw + 2)
    w.overgrowth(0, 0, 720, 200)
    for _ in range(10):  # brennende Ruinen
        x, z = rng.uniform(-680, 680), rng.uniform(-680, 680)
        if 200 < math.hypot(x, z) < 700:
            w.smoke_column(x, 12, z)

    # Apokalypse: Fluchtstaus auf den Ausfallstraßen, Quarantäne-Sperren an den Ortseingängen, Massengrab, Camps im Wald,
    # Leichen in den Straßen, Notstands-Plakate, abgestürzte Hubschrauber
    jam_roads = [[(0, 740), (-60, 860)], [(740, 0), (860, 240)], [(-740, 0), (-860, -110)], [(0, -740), (180, -860)]]
    for pts in jam_roads:
        w.traffic_jam(pts, 9)
    for key, (ax, az) in (("Nordheim", (-250, 1000)), ("Sandbach", (1000, 460)), ("Altenfeld", (-1010, -200)), ("Muehldorf", (330, -1000))):
        _, cx, cz, _ = PLACES[key]
        w.quarantine(ax, az, math.degrees(math.atan2(-(cz - az), cx - ax)) + 90)
    found = find_spot(w, 300, -200, 30)
    if found:
        w.mass_grave(*found)
    for x, z, title in ((-420, 860, "NORD"), (700, 920, "TEICH"), (-900, -700, "SUEDWEST"), (950, -150, "OST"), (-1300, 500, "WEST")):
        found = find_spot(w, x + 40, z + 40, 26)
        if found:
            w.survivor_camp(found[0], found[1], title)
    for seg in rng.sample(city_segments, min(40, len(city_segments))):
        t = rng.uniform(0.2, 0.8)
        x, z = seg[0] + (seg[2] - seg[0]) * t, seg[1] + (seg[3] - seg[1]) * t
        if math.hypot(x, z) > SAFE_R + 60:
            w.corpse(x + rng.uniform(-4, 4), z + rng.uniform(-4, 4), y=0.27)
    for seg in rng.sample(village_segments, min(16, len(village_segments))):
        x, z = (seg[0] + seg[2]) / 2, (seg[1] + seg[3]) / 2
        w.corpse(x + rng.uniform(-4, 4), z + rng.uniform(-4, 4), y=0.27)
    texts = (("NOTSTAND", "BLEIBEN SIE IN IHREN HÄUSERN"), ("EVAKUIERUNG", "ALLE BÜRGER ZUM CAMP PHOENIX"),
             ("ACHTUNG", "BISSE SOFORT MELDEN"), ("AUSGANGSSPERRE", "AB 20 UHR · SCHIESSBEFEHL"))
    for k, (x, z) in enumerate(((60, 790), (790, -60), (-790, 60), (-60, -790), (420, 700), (-700, -420))):
        found = find_spot(w, x, z, 10)
        if found:
            w.billboard(found[0], found[1], w.yaw_to(-found[0], -found[1]), *texts[k % len(texts)])
    for seg in rng.sample(city_segments, min(70, len(city_segments))):
        t = rng.uniform(0.1, 0.9)
        length = math.hypot(seg[2] - seg[0], seg[3] - seg[1]) or 1
        nx, nz = -(seg[3] - seg[1]) / length, (seg[2] - seg[0]) / length
        side = rng.choice((-1, 1)) * (seg[4] / 2 + 2)
        x, z = seg[0] + (seg[2] - seg[0]) * t + nx * side, seg[1] + (seg[3] - seg[1]) * t + nz * side
        if math.hypot(x, z) > SAFE_R + 60:
            w.litter(x, z)
    for _ in range(8):
        a, r = rng.uniform(0, 2 * math.pi), rng.uniform(220, 680)
        found = find_spot(w, math.cos(a) * r, math.sin(a) * r, 12)
        if found:
            w.crater(*found)
            w.occupied.append((found[0], found[1], 12))
    for x, z in ((-300, -420), (180, 640), (-700, 900)):
        found = find_spot(w, x, z, 18)
        if found:
            w.heli_crash(*found)

    # Rote Zonen, Aktivitäten, Orte, Seen
    w.redzones()
    activities(w)
    for key, (title, x, z, r) in PLACES.items():
        b.add("Places", "Place_" + key, (2 * r, 4, 2 * r), (x, 2, z), (255, 255, 255), "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False,
                     "Attributes": {"Attributes": {"Title": {"String": title}}}})
    for name, x, z, r, _ in LAKES:
        b.add("Lakes", "Lake_" + name, (2 * r, 1, 2 * r), (x, et.WATER, z), (54, 92, 110), "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    # Draußen: Wald, Felsen, Schilf am Ufer
    placed, tries = 0, 0
    while placed < 440 and tries < 60000:
        tries += 1
        x, z = rng.uniform(-HALF + 40, HALF - 40), rng.uniform(-HALF + 40, HALF - 40)
        density = w.terrain.noise.fbm(x / 140.0 + 40, z / 140.0 - 20, 3)
        if rng.random() > (0.95 if density > 0.5 else 0.08):
            continue
        if any(math.hypot(x - fx, z - fz) < fr + 10 for fx, fz, fr in FLATS) or w.terrain.slope(x, z) > 0.6:
            continue
        if w.H(x, z) < et.WATER + 2 or not w.free(x, z, 3, road_pad=4):
            continue
        w.tree(x, z, dead=rng.random() < 0.15)
        placed += 1
    placed = 0
    for _ in range(4000):
        if placed >= 90:
            break
        x, z = rng.uniform(-HALF + 40, HALF - 40), rng.uniform(-HALF + 40, HALF - 40)
        if any(math.hypot(x - fx, z - fz) < fr for fx, fz, fr in FLATS) or not w.free(x, z, 5, road_pad=4):
            continue
        if w.terrain.slope(x, z) > 0.25 or rng.random() < 0.2:
            w.rock(x, z)
            placed += 1
    for name, lx, lz, lr, _ in LAKES:
        reeds = 0
        for _ in range(200):
            ang = rng.uniform(0, 2 * math.pi)
            for dist in range(int(lr * 0.3), int(lr * 1.8), 4):
                px, pz = lx + math.cos(ang) * dist, lz + math.sin(ang) * dist
                if not w.terrain.is_water(px, pz):
                    if w.free(px, pz, 2, road_pad=3):
                        for _k in range(3):
                            sx_, sz_ = px + rng.uniform(-2, 2), pz + rng.uniform(-2, 2)
                            b.box("Nature", "Reed", (0.4, rng.uniform(3, 5), 0.4), (sx_, w.H(sx_, sz_) + 1.6, sz_), (100, 120, 70), "Grass",
                                  props={"CanCollide": False})
                        reeds += 1
                    break
            if reeds >= 22:
                break
    weather_signs(bm, b, rng)
    save(bm, b, "Extinction.model.json", "Ödstadt", "Wasteland")
    return w


def weather_signs(bm, b, rng):
    """Alle Schilder alt machen: Holz, Rost oder vergilbtes Blech statt glatter Tafeln, kein Leuchten, handgemalte Schrift
    (PermanentMarker / SpecialElite) in verblichenen Farben, leicht schief."""
    boards = ((96, 78, 58), (88, 70, 52), (110, 72, 52), (176, 168, 146), (70, 66, 60))

    def faded(color):
        r, g, b_ = (int(v * 255) if v <= 1 else int(v) for v in color)
        mix = 0.45
        return bm.rgb(int(r + (205 - r) * mix * 0.6), int(g + (196 - g) * mix * 0.6), int(b_ + (176 - b_) * mix * 0.6))

    def visit(inst):
        children = inst.get("Children", [])
        guis = [c for c in children if c.get("ClassName") == "SurfaceGui" and c.get("Name") in ("SignGui",)]
        if guis:
            props = inst["Properties"]
            props["Material"] = rng.choice(("WoodPlanks", "WoodPlanks", "CorrodedMetal", "Fabric"))
            props["Color"] = bm.rgb(*rng.choice(boards))
            inst["Children"] = [c for c in children if not (c.get("ClassName") == "SurfaceLight" and c.get("Name") == "Glow")]
            for gui in guis:
                gp = gui["Properties"]
                gp["LightInfluence"] = 1
                gp["Brightness"] = 1
                gui["Children"] = [c for c in gui.get("Children", []) if c.get("Name") != "Bar"]
                for label in gui["Children"]:
                    if label.get("ClassName") != "TextLabel":
                        continue
                    lp = label["Properties"]
                    title = label.get("Name") in ("Title", "Text")
                    lp["Font"] = "PermanentMarker" if title else "SpecialElite"
                    lp["TextColor3"] = faded(lp.get("TextColor3", [0.9, 0.9, 0.9]))
                    lp["TextStrokeTransparency"] = 1
                    lp["Rotation"] = round(rng.uniform(-3, 3), 2)
        for child in inst.get("Children", []):
            visit(child)

    for items in b.groups.values():
        for inst in items:
            visit(inst)


def save(bm, b, filename, display_name, atmosphere):
    """Wie Builder.save, aber kompakt (die Karte ist groß)."""
    import json
    import os
    attrs = {"DisplayName": {"String": display_name}, "Center": {"Vector3": [float(v) for v in b.origin]},
             "Atmosphere": {"String": atmosphere},
             # Minimap (Minimap.lua): weiter rausgezoomt, nur Straßen, Boden und Gebäude (kein Schutt, keine Bäume)
             "MinimapRange": {"Float64": 240.0}, "MinimapFolders": {"String": "Roads,Ground,Buildings,Walls,Stands"}}
    model = {"ClassName": "Model", "Properties": {"Attributes": {"Attributes": attrs}},
             "Children": [{"Name": g, "ClassName": "Folder", "Children": c} for g, c in b.groups.items()]}
    os.makedirs(bm.OUT_DIR, exist_ok=True)
    with open(os.path.join(bm.OUT_DIR, filename), "w") as f:
        json.dump(model, f, separators=(",", ":"))
    print(filename, sum(len(c) for c in b.groups.values()), "Parts")

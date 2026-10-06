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
SAFE_R = 120
CAMP_HALF = 82    # halbe Seitenlänge der Basis (HESCO-Wall im Quadrat, Ecken innerhalb SAFE_R)
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
            ("Kahlenberg", "KAHLENBERG", 780, 800), ("Rabenstein", "RABENSTEIN", -1330, 330)]
for _key, _title, _x, _z in OUTPOSTS:
    PLACES[_key] = (_title, _x, _z, 70)

# Kleine Safe Zones draußen (Safehouses): (Schlüssel, Titel, x, z) – kein PvP, Spawnpunkt (wer eine betritt, spawnt dort)
SAFEHOUSES = [("Nord", "SAFEHOUSE NORD", -640, 980), ("Ost", "SAFEHOUSE OST", 1240, 800),
              ("Sued", "SAFEHOUSE SÜD", 780, -420), ("West", "SAFEHOUSE WEST", -1000, -620)]
SAFEHOUSE_R = 44
SAFEHOUSE_WALL = 30   # halbe Seitenlänge der HESCO-Wall (Ecken innerhalb SAFEHOUSE_R)

# A7: Hochstraße quer über den Norden von Ödstadt (Rampen an beiden Enden), Oberkante, Breite, Rampenlänge
AUTOBAHN = [(-940, 560), (1000, 560)]
AUTOBAHN_H, AUTOBAHN_W, AUTOBAHN_RAMP = 24, 34, 180
# Bahnstrecke vom Westrand durch den Süden von Ödstadt in den Hafen; der Bahnhof liegt an Abschnitt STATION_SEG
RAIL = [(-1590, -470), (-900, -470), (-500, -560), (0, -600), (400, -620), (760, -760), (900, -880)]
STATION_SEG = 2
# Tankstellen: (x, z, Zufahrt-Ziel x, z)
GAS = [(-860, -50, -860, -132), (880, 150, 930, 270), (165, -925, 255, -910)]

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


def seg_intersect(a, b, c, d):
    """Schnittpunkt zweier Strecken a-b und c-d oder None."""
    (ax, az), (bx, bz), (cx, cz), (dx, dz) = a, b, c, d
    den = (bx - ax) * (dz - cz) - (bz - az) * (dx - cx)
    if abs(den) < 1e-9:
        return None
    t = ((cx - ax) * (dz - cz) - (cz - az) * (dx - cx)) / den
    u = ((cx - ax) * (bz - az) - (cz - az) * (bx - ax)) / den
    if 0 <= t <= 1 and 0 <= u <= 1:
        return ax + (bx - ax) * t, az + (bz - az) * t
    return None


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
    for points in highway_lines():
        for (ax, az), (bx, bz) in zip(points, points[1:]):
            t.road(ax, az, bx, bz, HIGHWAY_W + 4, 70)
    (ax, az), (bx, bz) = AUTOBAHN
    t.road(ax - 40, az, bx + 40, bz, AUTOBAHN_W + 20, 60)
    for (ax, az), (bx, bz) in zip(RAIL, RAIL[1:]):
        t.road(ax, az, bx, bz, 18, 60)
    for _, _, x, z in SAFEHOUSES:
        t.flat(x, z, SAFEHOUSE_R + 8, 60)
    for x, z, hx, hz in GAS:
        t.flat(x, z, 40, 50)
        t.road(x, z, hx, hz, 18, 50)
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
        [(-250, 1150), (60, 1060), (330, 990), (760, 1080), (1050, 1180)],        # Nordheim -> Teich -> Flugplatz
        [(-1090, -960), (-800, -1000), (-560, -980)],                             # Gefängnis -> am Funkturm vorbei
        [(-560, -980), (-250, -890), (180, -800)],                                # -> Süd
    ]


_HIGHWAY_LINES = None


def highway_lines():
    """Landstraßen mit Schwung – dieselben Linien für das Gelände (eben eingeschnitten) und die Fahrbahn."""
    global _HIGHWAY_LINES
    if _HIGHWAY_LINES is None:
        rng = random.Random(41)
        _HIGHWAY_LINES = [polyline(pts, rng, wobble=14, step=70) for pts in highway_points()]
    return _HIGHWAY_LINES


class World:
    def __init__(self, bm):
        self.bm = bm
        self.b = bm.Builder(ORIGIN)
        self.rng = random.Random(23)
        self.terrain = terrain_layout()
        self.H = self.terrain.sample
        self.roads = []        # (ax, az, bx, bz, Breite) aller Straßenstücke
        self.occupied = []     # (x, z, Radius) belegter Flächen (Gebäude, Anlagen)
        self.corridors = []    # (ax, az, bx, bz, Breite) freizuhaltender Streifen (Bahn, Autobahn) – keine Häuser
        self.pending_sidewalks = []  # Straßen, deren Gehwege sidewalks() setzt (an Kreuzungen unterbrochen)
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
        for ax, az, bx, bz, w in self.corridors:
            if dist_point_segment(x, z, ax, az, bx, bz) < r + w / 2:
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
        if any(self.terrain.is_water(ax + (bx - ax) * t, az + (bz - az) * t) for t in (0, 0.25, 0.5, 0.75, 1)):
            return  # keine Straße ins Wasser (Seeufer am Stadtrand)
        self.roads.append((ax, az, bx, bz, width))
        # Fahrbahn etwas über dem Gelände (das Terrain darf sie nicht verdecken), dunkler Asphalt; der Körper reicht tief in den
        # Boden, damit an Kanten und Senken nichts in der Luft hängt
        b.box("Roads", "Road", (length + width * 0.5, 3.0, width), (cx, -1.25, cz), (42, 43, 46), "Asphalt", angles=(0, yaw, 0))
        nx, nz = -dz, dx
        if sidewalk and length > 12:
            # Stadtstraße: weiße Randlinien, gestrichelte Mitte, ab und zu ein Zebrastreifen vor der Kreuzung
            # (Randlinien, Mittelstriche und Gehwege setzt sidewalks(), wenn alle Straßen da sind)
            paint = (196, 194, 184)
            if length > 50 and rng.random() < 0.4:
                end = rng.choice((0, 1))
                d0 = width / 2 + 7
                px, pz = (ax + dx * d0, az + dz * d0) if end == 0 else (bx - dx * d0, bz - dz * d0)
                stripes = int((width - 4) // 3)
                for k in range(stripes):
                    off = (k - (stripes - 1) / 2) * 3
                    b.box("Roads", "Crosswalk", (6, 0.02, 1.6), (px + nx * off, 0.265, pz + nz * off), paint, "SmoothPlastic",
                          angles=(0, yaw, 0))
                if rng.random() < 0.5:  # tote Ampel, oft umgeknickt
                    s = rng.choice((-1, 1))
                    lx_, lz_ = px + nx * s * (width / 2 + 2.5), pz + nz * s * (width / 2 + 2.5)
                    bent = rng.choice((0, 0, rng.uniform(-30, 30)))
                    b.box("Decor", "TrafficPole", (0.5, 11, 0.5), (lx_, 6, lz_), (52, 54, 56), "Metal", angles=(bent, yaw, 0))
                    b.box("Decor", "TrafficLight", (1.2, 3.4, 1.0), (lx_, 10.4, lz_), (36, 38, 30), "Metal", angles=(bent, yaw, 0))
        elif lines and length > 12:
            b.box("Roads", "CenterLine", (length - 6, 0.02, 0.5), (cx, 0.26, cz), (190, 165, 80), "SmoothPlastic", angles=(0, yaw, 0))
        if sidewalk:
            self.pending_sidewalks.append((ax, az, bx, bz, width))
        if sidewalk and length > 40 and rng.random() < 0.5:  # Gullydeckel
            t = rng.uniform(0.2, 0.8)
            b.add("Roads", "Manhole", (0.1, 2.6, 2.6), (ax + (bx - ax) * t + nx * width / 4, 0.27, az + (bz - az) * t + nz * width / 4),
                  (54, 54, 56), "DiamondPlate", angles=(0, 0, 90), props={"Shape": "Cylinder"})
        if cracked and length > 30 and rng.random() < 0.5:
            t = rng.uniform(0.2, 0.8)
            px, pz = ax + (bx - ax) * t, az + (bz - az) * t
            b.box("Roads", "Pothole", (rng.uniform(3, 7), 0.02, rng.uniform(2, 5)), (px + rng.uniform(-4, 4), 0.255, pz + rng.uniform(-4, 4)),
                  (30, 30, 32), "Slate", angles=(0, rng.uniform(0, 180), 0))

    def sidewalks(self):
        """Gehwege (Bordstein 0,35 über der Fahrbahn) beidseits der Stadtstraßen – dort unterbrochen, wo eine andere Straße
        kreuzt, damit kein Bordstein quer über die Kreuzung läuft."""
        b = self.b
        paint = (196, 194, 184)
        roads = [(r, min(r[0], r[2]) - r[4], max(r[0], r[2]) + r[4], min(r[1], r[3]) - r[4], max(r[1], r[3]) + r[4]) for r in self.roads]
        for ax, az, bx, bz, width in self.pending_sidewalks:
            length = math.hypot(bx - ax, bz - az)
            dx, dz = (bx - ax) / length, (bz - az) / length
            nx, nz = -dz, dx
            yaw = math.degrees(math.atan2(-dz, dx))
            near = [r for r, x0, x1, z0, z1 in roads
                    if r[:4] != (ax, az, bx, bz) and x0 - 20 < max(ax, bx) and x1 + 20 > min(ax, bx) and z0 - 20 < max(az, bz) and z1 + 20 > min(az, bz)]
            def free_at(t, off):
                px, pz = ax + dx * t + nx * off, az + dz * t + nz * off
                return all(dist_point_segment(px, pz, *r[:4]) > r[4] / 2 + 0.5 for r in near)

            def runs(off):
                """Abschnitte (t0, t1) entlang der Straße, die im Abstand off neben der Mitte frei von anderen Straßen sind."""
                n = max(2, int(length // 2))
                ok = [free_at(length * k / n, off) for k in range(n + 1)]
                out, k = [], 0
                while k <= n:
                    if not ok[k]:
                        k += 1
                        continue
                    j = k
                    while j + 1 <= n and ok[j + 1]:
                        j += 1
                    if (j - k) * length / n >= 2:
                        out.append((length * k / n, length * j / n))
                    k = j + 1
                return out
            for s in (-1, 1):
                for t0, t1 in runs(s * (width / 2 + 2)):
                    tm, off = (t0 + t1) / 2, s * (width / 2 + 2)
                    b.box("Ground", "Sidewalk", (t1 - t0, 3.0, 4), (ax + dx * tm + nx * off, -0.9, az + dz * tm + nz * off),
                          (128, 126, 120), "Concrete", angles=(0, yaw, 0))
                for t0, t1 in runs(s * (width / 2 - 1.4)):
                    if t1 - t0 < 4:
                        continue
                    tm, off = (t0 + t1) / 2, s * (width / 2 - 1.4)
                    b.box("Roads", "EdgeLine", (t1 - t0 - 2, 0.02, 0.4), (ax + dx * tm + nx * off, 0.26, az + dz * tm + nz * off), paint,
                          "SmoothPlastic", angles=(0, yaw, 0))
            n = int(length // 12)
            for k in range(n):
                t = length * (k + 0.5) / n
                if self.rng.random() < 0.12 or not (free_at(t - 3, 0) and free_at(t + 3, 0)):
                    continue  # abgefahren oder mitten auf der Kreuzung
                b.box("Roads", "LaneDash", (5, 0.02, 0.45), (ax + dx * t, 0.26, az + dz * t), paint, "SmoothPlastic", angles=(0, yaw, 0))
        self.pending_sidewalks = []

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
            lift = max(0.0, self.H((ax + bx) / 2, (az + bz) / 2) + 0.25 - (h0 + h1) / 2)  # Kuppe: nicht im Boden versinken
            h0, h1 = h0 + lift, h1 + lift
            yaw = math.degrees(math.atan2(-(bz - az), bx - ax))
            roll = math.degrees(math.atan2(h1 - h0, flat))
            b.box("Roads", "Track", (math.hypot(flat, h1 - h0) + 1.5, 3.6, width), ((ax + bx) / 2, (h0 + h1) / 2 - 1.6, (az + bz) / 2),
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
            for ax, az, bx, bz, rw in self.corridors:
                if dist_point_segment(px, pz, ax, az, bx, bz) < rw / 2:
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

    def litter(self, x, z, y=0.27, spread=3.0):
        """Müll am Straßenrand: Säcke, Papier, Tonne."""
        b, rng = self.b, self.rng
        for _ in range(rng.randint(2, 4)):
            kind = rng.random()
            px, pz = x + rng.uniform(-spread, spread), z + rng.uniform(-spread, spread)
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
    def frame(self, x, z, yaw):
        """Hilfen für ein gedrehtes Bauwerk: f(lx, ly, lz) -> Weltpunkt, box(...) mit Drehung yaw (+ extra)."""
        c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))

        def f(lx, ly, lz):
            return (x + lx * c + lz * sn, ly, z - lx * sn + lz * c)

        def box(group, name, size, lpos, color, mat, extra=(0, 0, 0), **kw):
            self.b.box(group, name, size, f(*lpos), color, mat, angles=(extra[0], yaw + extra[1], extra[2]), **kw)
        return f, box

    def warm_light(self, r=18, br=1.1):
        return [{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": r, "Brightness": br,
                                                                             "Color": self.bm.rgb(255, 196, 120)}}]

    def cabin(self, x, z, yaw, w=18, d=12, h=8, color=(168, 150, 120), porch=True, chimney=True, upper=False):
        """Intaktes Holzhaus (Vorderseite lokal -Z): Satteldach, beleuchtete Fenster mit Läden, Tür, Veranda, Schornstein."""
        rgb, lighten, rng = self.bm.rgb, self.bm.lighten, self.rng
        f, box = self.frame(x, z, yaw)
        dark, roof_c = (70, 54, 40), rng.choice(((74, 60, 52), (86, 58, 48), (64, 66, 70)))
        box("Buildings", "HouseBody", (w, h, d), (0, h / 2, 0), color, "WoodPlanks")
        box("Buildings", "HouseBase", (w + 0.6, 1, d + 0.6), (0, 0.5, 0), (110, 106, 100), "Slate")
        top = h
        if upper:
            box("Buildings", "HouseUpper", (w, 6, d), (0, h + 3, 0), lighten(color, -0.06), "WoodPlanks")
            box("Buildings", "HouseBelt", (w + 0.4, 0.5, d + 0.4), (0, h + 0.1, 0), dark, "Wood")
            top = h + 6
        rise = d * 0.36
        slope = math.degrees(math.atan2(rise, d / 2))
        for s in (-1, 1):
            box("Buildings", "Roof", (math.hypot(d / 2, rise) + 1.4, 0.6, w + 2), (0, top + rise / 2, s * d / 4), roof_c, "Slate",
                extra=(0, 90, s * slope))
        for s in (-1, 1):
            box("Buildings", "Gable", (0.5, rise, d * 0.8), (s * (w / 2 - 0.2), top + rise / 2 - 0.4, 0), lighten(color, -0.08),
                "WoodPlanks")
        if chimney:
            box("Buildings", "Chimney", (2, 6, 2), (w / 2 - 4, top + 3.5, 2), (120, 80, 64), "Brick",
                children=[{"Name": "Smoke", "ClassName": "Smoke", "Properties": {"Color": rgb(70, 66, 62), "Opacity": 0.18,
                                                                                 "RiseVelocity": 6, "Size": 4}}])
        box("Decor", "Door", (3, 6, 0.3), (0, 3.4, -d / 2 - 0.1), dark, "WoodPlanks")
        rows = [4.6] + ([h + 3] if upper else [])
        for wy in rows:
            for wx_ in (-w / 2 + 3.5, w / 2 - 3.5):
                box("Decor", "Window", (3, 2.4, 0.2), (wx_, wy, -d / 2 - 0.1), (255, 200, 130), "Neon",
                    children=self.warm_light(12, 0.7) if wy == 4.6 else None)
                box("Decor", "Shutter", (1.3, 2.6, 0.2), (wx_ - 2.2, wy, -d / 2 - 0.2), lighten(color, -0.3), "WoodPlanks")
        for wz_ in (-d / 4, d / 4):  # Seitenfenster
            for s in (-1, 1):
                box("Decor", "Window", (0.2, 2.2, 2.6), (s * (w / 2 + 0.1), 4.6, wz_), (255, 200, 130), "Neon")
        if porch:
            box("Buildings", "Porch", (w - 4, 0.6, 4), (0, 0.3, -d / 2 - 2), (104, 78, 54), "WoodPlanks")
            box("Buildings", "PorchRoof", (w - 3, 0.4, 4.6), (0, 6.6, -d / 2 - 2.2), roof_c, "Slate")
            for px_ in (-w / 2 + 2.5, w / 2 - 2.5):
                box("Buildings", "PorchPost", (0.5, 6.2, 0.5), (px_, 3.4, -d / 2 - 4), dark, "Wood")
            box("Decor", "PorchLamp", (0.7, 1, 0.7), (2.4, 5.6, -d / 2 - 0.5), (255, 206, 140), "Neon", children=self.warm_light(20, 1.2))
            if rng.random() < 0.6:
                box("Cover", "PorchBench", (4.6, 1.2, 1.4), (-w / 4, 1.2, -d / 2 - 1.2), (122, 92, 62), "WoodPlanks")

    def camp(self):
        """Safe Zone "Camp Phoenix": ummauerte Überlebenden-Siedlung. Palisade mit vier Torhäusern und Ecktürmen, Kieswege vom
        Tor zum Dorfplatz, dort ein großes Lagerfeuer unter Lichterketten (Spawn). An den Wegen Holzhäuser mit beleuchteten
        Fenstern und Veranden, Marktstände (Waffen, Sani, Werkstatt), Lagerhaus, Busstation (Reisen zu den Safehouses),
        Werkstatt-Scheune, Gärten, Wasserturm, Landeplatz mit Hubschrauber (Rückweg zum Hub)."""
        b, rng = self.b, self.rng
        R, H = SAFE_R, CAMP_HALF
        rgb, lighten = self.bm.rgb, self.bm.lighten
        wood, wood2, dark, rust = (122, 92, 62), (104, 78, 54), (70, 54, 40), (110, 76, 56)
        warm = rgb(255, 196, 120)
        lane_c = (112, 94, 70)

        b.add("Zone", "SafeZone", (2 * R, 80, 2 * R), (0, 40, 0), (96, 210, 120), "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
        # Boden: Kies, Erdwege vom Tor zum Platz, heller Dorfplatz
        b.box("Ground", "CampPad", (2 * H + 10, 3, 2 * H + 10), (0, -1.45, 0), (128, 120, 104), "Pebble")
        for gx, gz in ((0, 1), (1, 0)):
            b.box("Ground", "Lane", (12 if gx == 0 else 2 * H, 0.1, 2 * H if gx == 0 else 12), (0, 0.08, 0), lane_c, "Ground")
        b.add("Ground", "Plaza", (0.3, 52, 52), (0, 0.12, 0), (140, 128, 106), "Ground", angles=(0, 0, 90), props={"Shape": "Cylinder"})

        # ---------- Palisade, Ecktürme, Torhäuser ----------
        gate = 8
        for side in range(4):
            f, box = self.frame(0, 0, side * 90)
            t, k = -H + 3, 0
            while t < H - 2:
                if abs(t) > gate + 3:
                    sheet = k % 4 == 2
                    box("Walls", "WallSheet" if sheet else "Palisade", (6.2, 9.6 if not sheet else 9, 0.7), (t, 4.8, H),
                        rust if sheet else (wood if k % 2 else wood2), "CorrodedMetal" if sheet else "WoodPlanks",
                        extra=(0, 0, rng.uniform(-1, 1)))
                    box("Walls", "PalisadePost", (1, 11.4, 1), (t + 3, 5.7, H), dark, "Wood")
                    if k % 3 == 0:  # Fackel innen
                        box("Decor", "WallTorch", (0.6, 1, 0.6), (t, 8.6, H - 0.8), (255, 170, 80), "Neon",
                            children=self.warm_light(16, 0.9) if k % 6 == 0 else None)
                k += 1
                t += 6
            # Torhaus: zwei Holztürme, Brücke mit Schild, offene Flügel, Laternen
            for s in (-1, 1):
                tx = s * (gate + 3.5)
                for lx in (-2.6, 2.6):
                    for lz in (-2.6, 2.6):
                        box("Walls", "GateTowerLeg", (0.9, 16, 0.9), (tx + lx, 8, H + lz), dark, "Wood")
                box("Walls", "GateTowerWall", (6.4, 7, 6.4), (tx, 3.5, H), wood2, "WoodPlanks")
                box("Walls", "GateTowerDeck", (7, 0.5, 7), (tx, 16, H), wood, "WoodPlanks")
                for lx, lz, sx_, sz_ in ((0, -3.3, 7, 0.4), (0, 3.3, 7, 0.4), (3.3, 0, 0.4, 7), (-3.3, 0, 0.4, 7)):
                    box("Cover", "GateTowerRail", (sx_, 1.8, sz_), (tx + lx, 17.1, H + lz), wood2, "WoodPlanks")
                box("Decor", "GateTowerRoof", (8, 0.4, 8), (tx, 21, H), (74, 60, 52), "Slate", extra=(0, 0, s * 8))
                box("Decor", "GateLantern", (0.9, 1.3, 0.9), (s * (gate - 0.5), 8, H - 1.6), (255, 206, 140), "Neon",
                    children=self.warm_light(26, 1.4))
                box("Walls", "GateWing", (gate - 1, 9, 0.6), (s * (gate + 1.5), 4.6, H - gate / 2 - 1), wood2, "WoodPlanks",
                    extra=(0, s * 72, 0))
            box("Walls", "GateBridge", (2 * gate + 14, 1, 4), (0, 12.6, H), wood, "WoodPlanks")
            box("Walls", "GateBridgeRail", (2 * gate + 6, 1.4, 0.4), (0, 13.8, H + 1.8), wood2, "WoodPlanks")
            for yaw_off, dz_ in ((180, 2.1), (0, -2.1)):
                b.sign2("GateSign", (14, 3, 0.25), f(0, 10.4, H + dz_), "CAMP PHOENIX" if yaw_off == 180 else "DRAUSSEN",
                        "SICHERE ZONE · KEIN PVP" if yaw_off == 180 else "ZOMBIES · PVP NACH 5 SEKUNDEN",
                        (96, 74, 52), (236, 226, 196), (220, 210, 180), angles=(0, side * 90 + yaw_off, rng.uniform(-1.5, 1.5)))
        for sx in (-1, 1):
            for sz in (-1, 1):
                cx, cz = sx * (H - 5), sz * (H - 5)
                for lx in (-3, 3):
                    for lz in (-3, 3):
                        b.box("Walls", "TowerLeg", (1, 18, 1), (cx + lx, 9, cz + lz), dark, "Wood")
                b.box("Walls", "TowerDeck", (8, 0.5, 8), (cx, 18, cz), wood, "WoodPlanks")
                for lx, lz, sx_, sz_ in ((0, -3.8, 8, 0.4), (0, 3.8, 8, 0.4), (3.8, 0, 0.4, 8), (-3.8, 0, 0.4, 8)):
                    b.box("Cover", "TowerRail", (sx_, 1.8, sz_), (cx + lx, 19.1, cz + lz), wood2, "WoodPlanks")
                b.box("Decor", "TowerRoof", (9, 0.4, 9), (cx, 23, cz), (74, 60, 52), "Slate", angles=(0, 0, 7 * sx))
                b.add("Walls", "TowerLadder", (2, 18, 2), (cx - sx * 5, 9, cz), (90, 90, 92), "Metal", cls="TrussPart")
                b.box("Decor", "Searchlight", (1.4, 1.4, 1.8), (cx + sx * 2.5, 20, cz + sz * 2.5), (236, 236, 226), "Neon",
                      angles=(0, self.yaw_to(sx, sz), 0),
                      children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {"Face": "Front", "Range": 80,
                                                                                           "Brightness": 1.8, "Angle": 32,
                                                                                           "Color": rgb(255, 240, 210)}}])

        # ---------- Dorfplatz: Lagerfeuer, Bänke, Lichterketten, Spawns ----------
        for k in range(14):
            a = 2 * math.pi * k / 14
            b.box("Decor", "FireStone", (1.8, 1.1, 1.8), (math.cos(a) * 4, 0.55, math.sin(a) * 4), (110, 106, 100), "Slate",
                  angles=(0, rng.uniform(0, 90), 0))
        b.box("Decor", "Bonfire", (3, 1.4, 3), (0, 0.9, 0), (255, 130, 40), "Neon", props={"CanCollide": False},
              children=[{"Name": "Fire", "ClassName": "Fire", "Properties": {"Size": 12, "Heat": 14, "Color": rgb(255, 140, 40),
                                                                                "SecondaryColor": rgb(150, 40, 20)}},
                        {"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 50, "Brightness": 2.6, "Color": warm}},
                        {"Name": "Smoke", "ClassName": "Smoke", "Properties": {"Color": rgb(60, 56, 52), "Opacity": 0.2,
                                                                                 "RiseVelocity": 9, "Size": 10}}])
        for k in range(3):  # aufgeschichtete Scheite
            b.box("Decor", "FireLog", (4, 0.8, 0.8), (0, 1.2 + k * 0.5, 0), (90, 60, 40), "Wood", angles=(20, k * 60, 0))
        for k in range(6):
            a = 2 * math.pi * (k + 0.5) / 6
            b.box("Cover", "LogBench", (6, 1.2, 1.2), (math.cos(a) * 9, 0.7, math.sin(a) * 9), (96, 70, 48), "Wood",
                  angles=(0, -math.degrees(a) + 90, 0))
        for k in range(10):
            a = 2 * math.pi * (k + 0.25) / 10
            x, z = math.cos(a) * 14, math.sin(a) * 14
            b.spawn(x, z, yaw=math.degrees(math.atan2(x, z)) + 180)
        posts = []
        for k in range(8):
            a = math.radians(22.5 + 45 * k)
            posts.append((math.cos(a) * 24, math.sin(a) * 24))
            b.box("Decor", "StringPost", (0.6, 11, 0.6), (posts[-1][0], 5.5, posts[-1][1]), dark, "Wood")
            b.box("Decor", "PostLantern", (0.8, 1.1, 0.8), (posts[-1][0], 9.6, posts[-1][1]), (255, 206, 140), "Neon",
                  children=self.warm_light(18, 1) if k % 2 == 0 else None)
        spans = [(posts[k], posts[(k + 1) % 8]) for k in range(8)] + [(posts[k], posts[k + 4]) for k in range(4)]
        for (ax_, az_), (bx_, bz_) in spans:
            n = max(4, int(math.hypot(bx_ - ax_, bz_ - az_) / 3.4))
            sag = 1.4 if n < 8 else 3.2
            for j in range(1, n):
                t = j / n
                b.add("Decor", "Bulb", (0.55, 0.55, 0.55), (ax_ + (bx_ - ax_) * t, 10.4 - sag * math.sin(math.pi * t), az_ + (bz_ - az_) * t),
                      rng.choice(((255, 206, 140), (255, 186, 110), (255, 226, 170))), "Neon",
                      props={"Shape": "Ball", "CanCollide": False})
        b.box("Decor", "FlagPole", (0.6, 22, 0.6), (0, 11, -27), (190, 190, 186), "Metal")
        b.box("Decor", "Flag", (9, 5.4, 0.2), (4.8, 19.2, -27), (214, 96, 34), "Fabric", angles=(0, 0, -3))

        # ---------- Häuser an den Wegen ----------
        colors = ((168, 150, 120), (150, 120, 96), (126, 136, 120), (176, 160, 136), (140, 112, 92), (120, 128, 136))
        k = 0
        for gx, gz in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            for s in (-1, 1):
                nx, nz = -gz * s, gx * s  # Seite des Wegs
                x, z = gx * 58 + nx * 22, gz * 58 + nz * 22
                if (gx, gz, s) in ((1, 0, 1), (0, 1, -1)):  # Platz für Landeplatz und Gärten
                    pass
                self.cabin(x, z, self.yaw_to(-nx, -nz), w=16, d=12, h=8, color=colors[k % len(colors)], upper=k % 3 == 0)
                k += 1

        # ---------- Marktstände, Lager, Busstation ----------
        def stall(key, title, subtitle, x, z, fx, fz, awning, goods):
            yaw = self.yaw_to(fx, fz)
            f, box = self.frame(x, z, yaw)
            box("Stands", "StallFloor", (14, 0.5, 8), (0, 0.25, 0), wood2, "WoodPlanks")
            box("Stands", "StallBack", (14, 7, 0.5), (0, 3.5, 3.8), wood, "WoodPlanks")
            for s in (-1, 1):
                box("Stands", "StallSide", (0.5, 7, 8), (s * 6.8, 3.5, 0), wood, "WoodPlanks")
                box("Stands", "StallPost", (0.6, 9, 0.6), (s * 6.8, 4.5, -4.3), dark, "Wood")
            box("Stands", "StallCounter", (12, 3.2, 1.2), (0, 1.85, -3.4), (90, 70, 50), "WoodPlanks")
            box("Stands", "StallCounterTop", (12.6, 0.3, 1.8), (0, 3.6, -3.4), dark, "Wood")
            for j in range(5):  # gestreiftes Vordach
                box("Stands", "Awning", (14.6 / 5, 0.25, 7), (-5.84 + j * 2.92, 8.8, -1.6), awning if j % 2 == 0 else (236, 228, 210), "Fabric")
            box("Stands", "AwningFront", (14.6, 1.2, 0.2), (0, 8.2, -5.1), awning, "Fabric")
            b.sign2("StandSign_" + key, (9, 2.2, 0.25), f(0, 10.6, -1), title, subtitle, (96, 74, 52), (236, 226, 196), (220, 210, 180),
                    angles=(0, yaw, rng.uniform(-2, 2)))
            box("Stands", "SignPostL", (0.4, 2, 0.4), (-3.5, 9.6, -1), dark, "Wood")
            box("Stands", "SignPostR", (0.4, 2, 0.4), (3.5, 9.6, -1), dark, "Wood")
            for s in (-1, 1):
                box("Stands", "StallLantern", (0.8, 1.1, 0.8), (s * 5.5, 7.6, -4.6), (255, 206, 140), "Neon",
                    children=self.warm_light(18, 1.1))
            box("Stands", "Vendor", (2, 2.2, 1.1), (0, 4.9, -1.4), (66, 74, 56), "Fabric")
            box("Stands", "VendorHead", (1.2, 1.2, 1.2), (0, 6.7, -1.4), (196, 156, 126), "SmoothPlastic")
            box("Stands", "VendorCap", (1.3, 0.45, 1.4), (0, 7.45, -1.45), (60, 66, 50), "Fabric")
            for lx, ly, sx_, sy_, sz_, col, mat in goods:
                box("Stands", "Goods", (sx_, sy_, sz_), (lx, ly, 3.2), col, mat)
            b.add("Stands", key, (2, 2, 2), f(0, 2.5, -6.4), awning, "SmoothPlastic", angles=(0, yaw, 0),
                  props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
            for j in range(2):
                box("Cover", "Crate", (2.4, 2.4, 2.4), (rng.choice((-1, 1)) * 8.6, 1.2, rng.uniform(-2, 2)), (120, 98, 66), "WoodPlanks",
                    extra=(0, rng.uniform(-15, 15), 0))

        gun = (40, 42, 46)
        stall("Stand_Weapons", "WAFFEN", "MUNITION · TAUSCH", -15, 36, 1, 0, (160, 50, 40),
              [(-4, 6.4, 4.6, 0.7, 0.4, gun, "Metal"), (1, 6.4, 4.0, 0.6, 0.4, gun, "Metal"), (-4, 4.4, 3.6, 0.6, 0.4, gun, "Metal"),
               (1, 4.4, 5.0, 0.7, 0.4, gun, "Metal")])
        stall("Stand_Items", "SANI", "VERBAND · WESTEN", 36, 15, 0, -1, (220, 220, 214),
              [(-4, 4.4, 2.4, 1.6, 1.4, (226, 224, 216), "SmoothPlastic"), (-1, 4.4, 2.4, 1.6, 1.4, (200, 60, 50), "SmoothPlastic"),
               (2, 4.4, 2.4, 1.6, 1.4, (226, 224, 216), "SmoothPlastic"), (-2, 6.4, 3.0, 1.6, 1.4, (86, 96, 66), "Fabric")])
        stall("Stand_Vehicles", "WERKSTATT", "FAHRZEUGE", 15, -36, -1, 0, (70, 100, 140),
              [(-3, 6, 5, 2.4, 0.2, (60, 60, 64), "Metal"), (2.5, 6, 5, 2.4, 0.2, (60, 60, 64), "Metal"),
               (0, 4.2, 6, 1.2, 1.2, (150, 40, 34), "Metal")])
        # Lagerhaus (Scheune) mit offenem Tor
        yaw = self.yaw_to(0, 1)
        f, box = self.frame(-36, -15, yaw)
        box("Stands", "BarnBody", (16, 9, 12), (0, 4.5, 2), (130, 60, 48), "WoodPlanks")
        box("Stands", "BarnDoorGap", (7, 7, 0.4), (0, 3.5, -4.1), (40, 30, 24), "WoodPlanks")
        for s in (-1, 1):
            box("Stands", "BarnRoof", (math.hypot(6, 4) + 1, 0.5, 18), (0, 11, 2 + s * 3), (74, 60, 52), "Slate",
                extra=(0, 90, s * math.degrees(math.atan2(4, 6))))
            box("Stands", "BarnDoor", (3.6, 7, 0.3), (s * 5.4, 3.5, -5.2), (150, 70, 56), "WoodPlanks", extra=(0, s * 50, 0))
        box("Stands", "BarnLamp", (0.8, 0.8, 0.8), (0, 8, -4.4), (255, 206, 140), "Neon", children=self.warm_light(20, 1.2))
        b.sign2("StandSign_Stash", (9, 2.2, 0.25), f(0, 10.2, -4.4), "LAGER", "DEINS BLEIBT DEINS", (96, 74, 52), (236, 226, 196),
                (220, 210, 180), angles=(0, yaw, 0))
        b.add("Stands", "Stash", (2, 2, 2), f(0, 2.5, -7), (226, 178, 52), "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
        # Busstation: Reisen zu den Safehouses
        self.travel_stop("Travel", "REISEN", -36, 20, 0, -1)

        # ---------- Landeplatz (Rückweg zum Hub), Werkstatt-Scheune, Gärten, Wasserturm ----------
        hx, hz = 54, 54
        b.add("Decor", "Helipad", (0.4, 22, 22), (hx, 0.2, hz), (80, 78, 72), "Concrete", angles=(0, 0, 90), props={"Shape": "Cylinder"})
        b.floor_text("HelipadH", (8, 0.1, 8), (hx, 0.45, hz), "H", (236, 232, 220), yaw=0)
        for k in range(8):
            a = 2 * math.pi * k / 8
            b.box("Decor", "PadLight", (0.7, 0.5, 0.7), (hx + math.cos(a) * 11.6, 0.45, hz + math.sin(a) * 11.6), (255, 206, 140), "Neon",
                  children=self.warm_light(8, 0.8) if k % 2 == 0 else None)
        b.add("Portals", "Portal_Hub", (14, 0.4, 14), (hx, 0.5, hz), (120, 185, 235), "Neon",
              props={"CanCollide": False, "Transparency": 0.8})
        b.sign2("HubGateSign", (11, 2.6, 0.25), (hx - 14, 4.4, hz), "EVAKUIERUNG", "LANDEPLATZ BETRETEN = ZURÜCK ZUM HUB",
                (96, 74, 52), (236, 226, 196), (220, 210, 180), angles=(0, 90, 0))
        for s in (-1, 1):
            b.box("Decor", "HubSignPost", (0.5, 6, 0.5), (hx - 14.1, 3, hz + s * 5), dark, "Wood")
        hf, hbox = self.frame(hx + 4, hz + 22, 100)
        heli = (74, 82, 64)
        hbox("Decor", "HeliBody", (6, 5.6, 14), (0, 3.4, 0), heli, "Metal")
        hbox("Decor", "HeliNose", (5.4, 4, 3.4), (0, 3.2, -8.4), lighten(heli, -0.1), "Metal")
        hbox("Decor", "HeliGlass", (5.6, 2.4, 2.6), (0, 4.3, -8.6), (40, 52, 60), "Glass", props={"Transparency": 0.35})
        hbox("Decor", "HeliTail", (1.4, 1.4, 12), (0, 4.6, 13), heli, "Metal")
        hbox("Decor", "HeliFin", (0.4, 3.6, 2.2), (0, 6.3, 18.6), heli, "Metal")
        for a in (20, 110):
            hbox("Decor", "HeliRotor", (26, 0.3, 1.1), (0, 7.6, 0), (36, 36, 36), "Metal", extra=(0, a, 0))
        for s in (-1, 1):
            hbox("Decor", "HeliSkid", (0.5, 0.5, 12), (s * 2.8, 0.25, -1), (40, 40, 40), "Metal")
        # Werkstatt-Scheune mit Autos
        f, box = self.frame(50, -50, self.yaw_to(-1, 0))
        box("Buildings", "Workshop", (18, 0.4, 16), (0, 9, 0), rust, "CorrodedMetal")
        for lx in (-8.6, 8.6):
            for lz in (-7.6, 7.6):
                box("Buildings", "WorkshopPost", (0.7, 9, 0.7), (lx, 4.5, lz), dark, "Wood")
        box("Buildings", "WorkshopBack", (18, 9, 0.5), (0, 4.5, 7.8), wood2, "WoodPlanks")
        box("Decor", "WorkshopLamp", (3, 0.3, 0.6), (0, 8.6, 0), (240, 236, 220), "Neon", children=self.warm_light(22, 1.1))
        for j, lx in enumerate((-4.5, 4.5)):
            body = ((140, 60, 44), (70, 96, 120))[j]
            box("Cover", "CarBody", (5, 2.2, 10), (lx, 2.2, 1), body, "Metal")
            box("Cover", "CarCabin", (4.6, 1.8, 4.6), (lx, 4.1, 1.6), lighten(body, -0.15), "Metal")
            for sz_ in (-3, 3):
                for s in (-1, 1):
                    box("Cover", "CarWheel", (0.9, 2.2, 2.2), (lx + s * 2.5, 1.1, 1 + sz_), (24, 24, 26), "Rubber", props={"Shape": "Cylinder"})
        box("Cover", "Workbench", (6, 3, 2), (0, 1.5, 6.4), dark, "Wood")
        # Gärten und Wasserturm (Nordwesten), Zelte (Südwesten)
        for k in range(4):
            gx_, gz_ = -64 + k * 6, 46
            b.box("Decor", "GardenBed", (4.4, 1, 14), (gx_, 0.5, gz_), (96, 72, 50), "WoodPlanks")
            for j in range(5):
                b.add("Decor", "Plant", (1.8, 1.4, 1.8), (gx_, 1.6, gz_ - 5.6 + j * 2.8), rng.choice(((70, 110, 52), (90, 128, 60))), "Grass",
                      props={"Shape": "Ball", "CanCollide": False})
        wx, wz = -60, 66
        for lx in (-2.6, 2.6):
            for lz in (-2.6, 2.6):
                b.box("Decor", "WaterTowerLeg", (0.7, 13, 0.7), (wx + lx, 6.5, wz + lz), dark, "Wood")
        b.box("Decor", "WaterTowerDeck", (7, 0.4, 7), (wx, 13.2, wz), wood, "WoodPlanks")
        b.cylinder("Decor", "WaterTank", 6.4, 5.4, (wx, 16.1, wz), (78, 92, 96), material="CorrodedMetal")
        for k, (tx, tz) in enumerate(((-64, -40), (-50, -40), (-64, -60), (-50, -60))):
            f, box = self.frame(tx, tz, 0)
            box("Decor", "TentFloor", (8, 0.2, 9), (0, 0.2, 0), (70, 70, 64), "Fabric")
            for s in (-1, 1):
                box("Decor", "TentRoof", (5.4, 0.3, 9), (s * 2.1, 2.6, 0), (90, 100, 72) if k % 2 else (120, 110, 84), "Fabric",
                    extra=(0, 0, -s * 52))
        for k in range(5):
            b.box("Cover", "Firewood", (6, 0.9, 0.9), (-40, 0.45 + k * 0.9, -66 + (k % 2) * 0.4), (120, 86, 56), "Wood",
                  props={"Shape": "Cylinder"})

    def travel_stop(self, name, title, x, z, fx, fz):
        """Haltestelle für Reisen zwischen den Safe Zones: Wartehäuschen, Schild, Fahrer (Punkt name in Stands) und ein Bus."""
        b, rng = self.b, self.rng
        yaw = self.yaw_to(fx, fz)
        f, box = self.frame(x, z, yaw)
        dark = (70, 54, 40)
        box("Stands", "ShelterRoof", (10, 0.4, 5), (0, 7, 1.5), (74, 60, 52), "Slate", extra=(0, 0, 0))
        box("Stands", "ShelterBack", (10, 6.6, 0.4), (0, 3.5, 3.8), (122, 92, 62), "WoodPlanks")
        for s in (-1, 1):
            box("Stands", "ShelterPost", (0.5, 7, 0.5), (s * 4.8, 3.5, -0.8), dark, "Wood")
        box("Cover", "ShelterBench", (7, 1.2, 1.6), (0, 1.1, 2.6), (104, 78, 54), "WoodPlanks")
        box("Stands", "ShelterLamp", (0.8, 0.8, 0.8), (0, 6.5, 0), (255, 206, 140), "Neon", children=self.warm_light(18, 1.1))
        b.sign2("TravelSign", (8, 2.2, 0.25), f(0, 8.8, -0.6), title, "FAHRT ZU ANDEREN SAFE ZONES", (96, 74, 52), (236, 226, 196),
                (220, 210, 180), angles=(0, yaw, rng.uniform(-2, 2)))
        # Fahrer
        box("Stands", "DriverBody", (2, 2.4, 1.1), (3.2, 2.2, -2), (70, 80, 100), "Fabric")
        box("Stands", "DriverLegs", (1.8, 2, 1), (3.2, 0.5, -2), (50, 50, 56), "Fabric")
        box("Stands", "DriverHead", (1.2, 1.2, 1.2), (3.2, 4.1, -2), (196, 156, 126), "SmoothPlastic")
        box("Stands", "DriverCap", (1.4, 0.4, 1.5), (3.2, 4.85, -2.1), (40, 50, 80), "Fabric")
        b.add("Stands", name, (2, 2, 2), f(3.2, 2.5, -4), (90, 180, 100), "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    def safehouse(self, key, title, x, z):
        """Kleine Safe Zone draußen: befestigter Überlebenden-Hof. Kiesplatz hinter einer Palisade aus Holz und Wellblech, Tor
        mit Torbogen und Schild zur Zufahrt, ein intaktes Holzhaus mit Veranda, warm beleuchteten Fenstern und rauchendem
        Schornstein, Feuerstelle mit Bänken und Lichterkette (Spawn), Beete, Wasserturm, Brennholz, Pickup, Wachturm.
        Teil SafeZone_<Schlüssel> (Gruppe Zone), Spawns in Spawns_<Schlüssel>."""
        b, rng = self.b, self.rng
        R, W = SAFEHOUSE_R, SAFEHOUSE_WALL
        rgb, lighten = self.bm.rgb, self.bm.lighten
        warm = rgb(255, 196, 120)
        wood, wood2, dark = (122, 92, 62), (104, 78, 54), (70, 54, 40)
        rust, roof_c = (110, 76, 56), (74, 60, 52)
        house_c = rng.choice(((168, 150, 120), (150, 120, 96), (126, 136, 120)))

        def lamp_light(r=18, br=1.1):
            return [{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": r, "Brightness": br, "Color": warm}}]

        b.add("Zone", "SafeZone_" + key, (2 * R, 80, 2 * R), (x, 40, z), (96, 210, 120), "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False,
                     "Attributes": {"Attributes": {"Title": {"String": title}}}})
        # Ausrichtung: Tor zur Zufahrt (nächste Landstraße)
        start = self.nearest_highway(x, z)
        road_side = 2
        if start:
            ax_, az_ = start[0] - x, start[1] - z
            road_side = (0 if az_ > 0 else 2) if abs(az_) >= abs(ax_) else (1 if ax_ > 0 else 3)
        gx, gz = ((0, 1), (1, 0), (0, -1), (-1, 0))[road_side]
        yaw = self.yaw_to(gx, gz)  # Vorderseite (lokal -Z) zum Tor
        c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))

        def f(lx, ly, lz):
            return (x + lx * c + lz * sn, ly, z - lx * sn + lz * c)

        def box(group, name, size, lpos, color, mat, extra=(0, 0, 0), **kw):
            b.box(group, name, size, f(*lpos), color, mat, angles=(extra[0], yaw + extra[1], extra[2]), **kw)

        # Kiesplatz
        box("Ground", "CampPad", (2 * W + 4, 3, 2 * W + 4), (0, -1.45, 0), (128, 120, 104), "Pebble")
        # Palisade: Bretterwände und Wellblech im Wechsel, Pfosten mit Spitzen; Tor vorne (lokal -Z)
        for side in range(4):
            syaw = side * 90
            sc, ss = math.cos(math.radians(syaw)), math.sin(math.radians(syaw))
            t, k = -W + 3, 0
            while t < W - 2:
                lx, lz = t * sc + W * ss, -t * ss + W * sc  # Wand auf der Seite side (0 = hinten +Z)
                gate = side == 2 and abs(t) < 6
                if not gate:
                    sheet = k % 3 == 1
                    box("Walls", "Palisade" if not sheet else "WallSheet", (6.2, 7 if not sheet else 6.4, 0.6), (lx, 3.5, lz),
                        wood if k % 2 else wood2 if not sheet else rust, "WoodPlanks" if not sheet else "CorrodedMetal",
                        extra=(0, syaw, rng.uniform(-1.5, 1.5)))
                    px, pz = (t + 3) * sc + W * ss, -(t + 3) * ss + W * sc
                    box("Walls", "PalisadePost", (0.9, 8.4, 0.9), (px, 4.2, pz), dark, "Wood", extra=(0, syaw, 0))
                k += 1
                t += 6
        # Tor: Torbogen aus Balken, Schild beidseitig, Laternen, offene Torflügel
        for s in (-1, 1):
            box("Walls", "GatePost", (1.4, 11, 1.4), (s * 6, 5.5, -W), dark, "Wood")
            box("Walls", "GateWing", (5.6, 6.6, 0.5), (s * 8.6, 3.4, -W - 2.6), wood2, "WoodPlanks", extra=(0, -s * 70, 0))
            box("Decor", "GateLantern", (0.8, 1.2, 0.8), (s * 6, 8.6, -W - 1.1), (255, 206, 140), "Neon", children=lamp_light(22, 1.2))
        box("Walls", "GateBeam", (14, 1.2, 1.2), (0, 11.2, -W), dark, "Wood")
        for yaw_off, dz_ in ((0, -0.8), (180, 0.8)):
            b.sign2("SafehouseSign", (11, 2.6, 0.25), f(0, 9.4, -W + dz_), title, "KEIN PVP · SPAWNPUNKT", (96, 74, 52),
                    (236, 226, 196), (220, 210, 180), angles=(0, yaw + yaw_off, rng.uniform(-2, 2)))

        # Haus hinten in der Mitte: Holzwände, Satteldach, Fenster warm beleuchtet, Veranda, Schornstein
        hz, hw, hd, hh = 14, 20, 12, 8
        box("Buildings", "HouseBody", (hw, hh, hd), (0, hh / 2, hz), house_c, "WoodPlanks")
        box("Buildings", "HouseBase", (hw + 0.6, 1, hd + 0.6), (0, 0.5, hz), (110, 106, 100), "Slate")
        rise = 4.5
        slope = math.degrees(math.atan2(rise, hd / 2))
        for s in (-1, 1):  # Dachflächen: um 90° gedreht, damit die Neigung (lokale Drehung um z) quer zum First liegt
            box("Buildings", "Roof", (math.hypot(hd / 2, rise) + 1.4, 0.6, hw + 2), (0, hh + rise / 2, hz + s * hd / 4), roof_c,
                "Slate", extra=(0, 90, s * slope))
        box("Buildings", "Gable", (0.5, rise, hd * 0.8), (-hw / 2 + 0.2, hh + rise / 2 - 0.4, hz), lighten(house_c, -0.08), "WoodPlanks")
        box("Buildings", "Gable", (0.5, rise, hd * 0.8), (hw / 2 - 0.2, hh + rise / 2 - 0.4, hz), lighten(house_c, -0.08), "WoodPlanks")
        box("Buildings", "Chimney", (2, 6, 2), (hw / 2 - 4, hh + 3.5, hz + 2), (120, 80, 64), "Brick",
            children=[{"Name": "Smoke", "ClassName": "Smoke", "Properties": {"Color": rgb(70, 66, 62), "Opacity": 0.2,
                                                                             "RiseVelocity": 6, "Size": 4}}])
        box("Decor", "Door", (3, 6, 0.3), (0, 3.4, hz - hd / 2 - 0.1), dark, "WoodPlanks")
        for wx_ in (-6.5, 6.5):
            box("Decor", "Window", (3.4, 2.6, 0.2), (wx_, 4.6, hz - hd / 2 - 0.1), (255, 200, 130), "Neon", children=lamp_light(14, 0.8))
            box("Decor", "WindowFrame", (4, 0.4, 0.3), (wx_, 3.2, hz - hd / 2 - 0.2), dark, "Wood")
            box("Decor", "Shutter", (1.4, 2.8, 0.2), (wx_ - 2.5, 4.6, hz - hd / 2 - 0.2), lighten(house_c, -0.3), "WoodPlanks")
        # Veranda
        box("Buildings", "Porch", (hw - 4, 0.6, 4), (0, 0.3, hz - hd / 2 - 2), wood2, "WoodPlanks")
        box("Buildings", "PorchRoof", (hw - 3, 0.4, 4.6), (0, 6.6, hz - hd / 2 - 2.2), roof_c, "Slate", extra=(0, 0, 0))
        for px_ in (-hw / 2 + 2.5, -3, 3, hw / 2 - 2.5):
            box("Buildings", "PorchPost", (0.5, 6.2, 0.5), (px_, 3.4, hz - hd / 2 - 4), dark, "Wood")
        box("Cover", "PorchBench", (5, 1.2, 1.4), (-5, 1.2, hz - hd / 2 - 1.2), wood, "WoodPlanks")
        box("Decor", "PorchLamp", (0.7, 1, 0.7), (2.2, 5.6, hz - hd / 2 - 0.5), (255, 206, 140), "Neon", children=lamp_light(20, 1.2))

        # Feuerstelle in der Mitte, Bänke, Spawns, Lichterkette vom Haus zu zwei Masten
        fz = -6
        for k in range(10):
            a = 2 * math.pi * k / 10
            box("Decor", "FireStone", (1.3, 0.8, 1.3), (math.cos(a) * 2.6, 0.4, fz + math.sin(a) * 2.6), (110, 106, 100), "Slate",
                extra=(0, rng.uniform(0, 90), 0))
        box("Decor", "Bonfire", (1.8, 0.9, 1.8), (0, 0.55, fz), (255, 130, 40), "Neon", props={"CanCollide": False},
            children=[{"Name": "Fire", "ClassName": "Fire", "Properties": {"Size": 6, "Heat": 9, "Color": rgb(255, 140, 40),
                                                                              "SecondaryColor": rgb(150, 40, 20)}},
                      {"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 30, "Brightness": 2, "Color": warm}}])
        for k in range(3):
            a = math.radians(30 + 120 * k)
            box("Cover", "LogBench", (4.6, 1.1, 1.1), (math.cos(a) * 6, 0.6, fz + math.sin(a) * 6), (96, 70, 48), "Wood",
                extra=(0, -math.degrees(a) + 90, 0))
        for k in range(6):
            a = 2 * math.pi * (k + 0.5) / 6
            lx, lz = math.cos(a) * 10, fz + math.sin(a) * 10
            wx_, _, wz_ = f(lx, 0, lz)
            b.spawn(wx_, wz_, yaw=math.degrees(math.atan2(wx_ - x, wz_ - z)) + 180, group="Spawns_" + key)
        masts = [(-12, -14), (12, -14)]
        for mx_, mz_ in masts:
            box("Decor", "StringPost", (0.5, 8, 0.5), (mx_, 4, mz_), dark, "Wood")
        for (ax_, az_), (bx_, bz_) in (((-8, hz - hd / 2 - 4), masts[0]), ((8, hz - hd / 2 - 4), masts[1]), (masts[0], masts[1])):
            for j in range(1, 6):
                t = j / 6
                yy = 7.6 - 1.3 * math.sin(math.pi * t)
                box("Decor", "Bulb", (0.5, 0.5, 0.5), (ax_ + (bx_ - ax_) * t, yy, az_ + (bz_ - az_) * t),
                    rng.choice(((255, 206, 140), (255, 186, 110))), "Neon", props={"Shape": "Ball", "CanCollide": False},
                    children=lamp_light(10, 0.6) if j == 3 else None)

        # Hof: Beete links, Wasserturm und Brennholz rechts, Pickup, Kisten, Wachturm in der hinteren Ecke, Fahne
        for k in range(3):
            box("Decor", "GardenBed", (3.6, 1, 9), (-22 + k * 4.6, 0.5, -10), (96, 72, 50), "WoodPlanks")
            for j in range(4):
                box("Decor", "Plant", (1.6, 1.3, 1.6), (-22 + k * 4.6, 1.5, -13.5 + j * 2.4), rng.choice(((70, 110, 52), (90, 128, 60))),
                    "Grass", props={"Shape": "Ball", "CanCollide": False})
        wtx, wtz = 22, 18
        for lx in (-2.2, 2.2):
            for lz in (-2.2, 2.2):
                box("Decor", "WaterTowerLeg", (0.6, 10, 0.6), (wtx + lx, 5, wtz + lz), dark, "Wood")
        box("Decor", "WaterTowerDeck", (6, 0.4, 6), (wtx, 10.2, wtz), wood, "WoodPlanks")
        b.cylinder("Decor", "WaterTank", 5.4, 4.6, f(wtx, 12.7, wtz), (78, 92, 96), material="CorrodedMetal")
        for k in range(5):
            box("Cover", "Firewood", (6, 0.9, 0.9), (22, 0.45 + k * 0.9, 6 + (k % 2) * 0.4), (120, 86, 56), "Wood",
                props={"Shape": "Cylinder"})
        box("Decor", "FirewoodRoof", (7, 0.3, 3), (22, 5, 6), rust, "CorrodedMetal", extra=(0, 0, 8))
        # Haltestelle: Reisen zu den anderen Safe Zones
        sx_, _, sz_ = f(20, 0, -9)
        cx_, _, cz_ = f(0, 0, -9)
        self.travel_stop("Travel_" + key, "REISEN", sx_, sz_, cx_ - sx_, cz_ - sz_)
        # Pickup
        px_, pz_ = -18, 8
        body = rng.choice(((140, 60, 44), (60, 90, 120), (90, 100, 70)))
        box("Cover", "TruckBody", (5.4, 2.4, 11), (px_, 2.2, pz_), body, "Metal")
        box("Cover", "TruckCabin", (5, 2.2, 4.6), (px_, 4.5, pz_ - 1.6), lighten(body, -0.1), "Metal")
        box("Decor", "TruckGlass", (5.1, 1.4, 4), (px_, 4.6, pz_ - 1.6), (50, 64, 72), "Glass", props={"Transparency": 0.4})
        for sx_ in (-1, 1):
            for sz_ in (-3.4, 3.4):
                box("Cover", "TruckWheel", (0.9, 2.4, 2.4), (px_ + sx_ * 2.7, 1.2, pz_ + sz_), (24, 24, 26), "Rubber",
                    props={"Shape": "Cylinder"})
        for k in range(3):
            box("Cover", "SupplyCrate", (2.8, 2.4, 2.8), (px_ + rng.uniform(-1.4, 1.4), 4.6 if k == 0 else 1.2, pz_ + 4 + k * 3.2 if k else pz_ + 3),
                (110, 92, 62), "WoodPlanks", extra=(0, rng.uniform(-10, 10), 0))
        tx_, tz_ = -24, 24
        for lx in (-2.4, 2.4):
            for lz in (-2.4, 2.4):
                box("Walls", "TowerLeg", (0.8, 12, 0.8), (tx_ + lx, 6, tz_ + lz), dark, "Wood")
        box("Walls", "TowerDeck", (6.4, 0.5, 6.4), (tx_, 12.2, tz_), wood, "WoodPlanks")
        for lx, lz, sx_, sz_ in ((0, -3, 6.4, 0.4), (3, 0, 0.4, 6.4), (-3, 0, 0.4, 6.4), (0, 3, 6.4, 0.4)):
            box("Cover", "TowerRail", (sx_, 1.6, sz_), (tx_ + lx, 13.2, tz_ + lz), wood2, "WoodPlanks")
        box("Decor", "TowerRoof", (7.4, 0.3, 7.4), (tx_, 16.4, tz_), rust, "CorrodedMetal", extra=(0, 0, 6))
        b.add("Walls", "TowerLadder", (2, 12, 2), f(tx_ + 4.3, 6, tz_), (90, 90, 92), "Metal", angles=(0, yaw, 0), cls="TrussPart")
        box("Decor", "Searchlight", (1.2, 1.2, 1.6), (tx_ + 2, 14, tz_ - 2), (236, 236, 226), "Neon",
            children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {"Face": "Front", "Range": 60, "Brightness": 1.6,
                                                                                 "Angle": 35, "Color": rgb(255, 240, 210)}}])
        box("Decor", "FlagPole", (0.4, 14, 0.4), (10, 7, -20), (190, 190, 186), "Metal")
        box("Decor", "Flag", (5, 3, 0.2), (12.6, 12.4, -20), (90, 180, 100), "Fabric")
        n = 48
        for k in range(n):
            a = 2 * math.pi * (k + 0.5) / n
            b.box("Zone", "SafeEdge", (2 * math.pi * (R - 1) / n + 0.2, 0.12, 1.0), (x + math.cos(a) * (R - 1), 0.2, z + math.sin(a) * (R - 1)),
                  (96, 210, 120), "Neon", angles=(0, -math.degrees(a) + 90, 0),
                  props={"Transparency": 0.6, "CanCollide": False, "CanQuery": False, "CanTouch": False})
        self.occupied.append((x, z, R + 12))
        PLACES["Safe_" + key] = (title, x, z, R)
        # Zufahrt von der nächsten Landstraße gerade auf das Tor zu
        if start and math.hypot(start[0] - x, start[1] - z) > R:
            door = (x + gx * (W + 3), z + gz * (W + 3))
            bend = (door[0] + gx * 30, door[1] + gz * 30)
            self.road(start[0], start[1], bend[0], bend[1], 14, lines=False)
            self.road(bend[0], bend[1], door[0], door[1], 14, lines=False)

    # ---------- Autobahn auf Stelzen, Bahnstrecke mit Bahnhof ----------
    def slab(self, group, name, a, c, width, thick, color, mat, props=None):
        """Platte von a nach c (je (x, y_oben, z)), geneigt wie die Strecke."""
        (ax, ay, az), (bx, by, bz) = a, c
        flat = math.hypot(bx - ax, bz - az)
        yaw = math.degrees(math.atan2(-(bz - az), bx - ax))
        roll = math.degrees(math.atan2(by - ay, flat))
        self.b.box(group, name, (math.hypot(flat, by - ay), thick, width), ((ax + bx) / 2, (ay + by) / 2 - thick / 2, (az + bz) / 2),
                   color, mat, angles=(0, yaw, roll), props=props)

    def autobahn(self):
        """A7 quer über den Norden von Ödstadt: Hochstraße auf Pfeilern, Rampen an beiden Enden, ein eingestürztes Feld,
        Wracks und Mittelleitplanke. Die Fläche darunter bleibt frei (Korridor)."""
        b, rng = self.b, self.rng
        (x0, z), (x1, _) = AUTOBAHN[0], AUTOBAHN[1]
        top, width, ramp = AUTOBAHN_H, AUTOBAHN_W, AUTOBAHN_RAMP
        concrete, asphalt, paint = (150, 146, 138), (46, 47, 50), (196, 194, 184)
        gap = (240, 290)  # eingestürztes Feld (x von, bis)

        def height(x):
            if x < x0 + ramp:
                return 0.25 + (top - 0.25) * (x - x0) / ramp
            if x > x1 - ramp:
                return 0.25 + (top - 0.25) * (x1 - x) / ramp
            return top
        # Fahrbahn in Stücken (an den Rampen geneigt), Brüstung außen, Leitplanke in der Mitte
        xs = [x0, x0 + ramp / 2, x0 + ramp] + list(range(int(x0 + ramp) + 60, int(x1 - ramp), 60)) + [x1 - ramp, x1 - ramp / 2, x1]
        xs = sorted(set(round(v, 1) for v in xs) | set(gap))
        for xa, xb in zip(xs, xs[1:]):
            if gap[0] <= xa < gap[1]:
                continue
            ha, hb = height(xa), height(xb)
            self.slab("Roads", "Road", (xa, ha, z), (xb + 0.05, hb, z), width, 2.4, asphalt, "Asphalt")
            if xa < x0 + ramp - 1 or xb > x1 - ramp + 1:  # Rampe: massiver Damm bis in den Boden
                self.slab("Buildings", "Embankment", (xa, ha - 2.4, z), (xb, hb - 2.4, z), width - 1, max(ha, hb) + 1,
                          (120, 116, 108), "Concrete")
            for s in (-1, 1):
                self.slab("Walls", "Parapet", (xa, ha + 1.3, z + s * (width / 2 - 0.5)), (xb, hb + 1.3, z + s * (width / 2 - 0.5)),
                          1.0, 1.3, concrete, "Concrete")
                self.slab("Roads", "EdgeLine", (xa, ha + 0.02, z + s * (width / 2 - 2.5)), (xb, hb + 0.02, z + s * (width / 2 - 2.5)),
                          0.4, 0.04, paint, "SmoothPlastic")
            self.slab("Walls", "MedianBarrier", (xa, ha + 1.1, z), (xb, hb + 1.1, z), 1.2, 1.1, (170, 166, 158), "Concrete")
            if ha > 6 and hb > 6:  # Brückenkante als dickerer Träger unter der Fahrbahn
                self.slab("Buildings", "BridgeGirder", (xa, ha - 2.4, z), (xb, hb - 2.4, z), width - 6, 2.4, (120, 118, 112), "Concrete")
        # Spurmarkierung
        x = x0 + 12
        while x < x1 - 12:
            if not (gap[0] - 4 < x < gap[1] + 4):
                for s in (-1, 1):
                    h = height(x)
                    b.box("Roads", "LaneDash", (8, 0.04, 0.45), (x, h + 0.03, z + s * width / 4), paint, "SmoothPlastic",
                          angles=(0, 0, math.degrees(math.atan2(height(x + 1) - height(x - 1), 2))))
            x += 22
        # Pfeiler (Doppelstütze mit Querträger), nicht mitten auf eine Straße
        x = x0 + ramp + 10
        while x < x1 - ramp - 5:
            h = height(x)
            if h > 5 and not (gap[0] - 2 < x < gap[1] + 2):
                cols = [s for s in (-1, 1) if all(dist_point_segment(x, z + s * 9, *r[:4]) > r[4] / 2 + 3 for r in self.roads)]
                for s in cols:
                    b.box("Buildings", "Pillar", (3.4, h - 2.4, 3.4), (x, (h - 2.4) / 2 - 0.4, z + s * 9), concrete, "Concrete")
                if cols:
                    b.box("Buildings", "PillarCap", (4, 2, width - 4), (x, h - 3.6, z), concrete, "Concrete")
            x += 48
        # eingestürztes Feld: Platte schräg auf dem Boden, Bewehrungseisen, Schutt, ein abgestürztes Auto
        self.slab("Roads", "CollapsedDeck", (gap[0] + 2, top - 1.2, z + 3), (gap[1] - 14, 0.5, z - 2), width - 4, 2.4, asphalt, "Asphalt")
        for k in range(6):
            b.box("Decor", "Rebar", (0.25, 0.25, rng.uniform(4, 8)), (gap[0] + rng.uniform(-1, 1), top - 1.4, z + rng.uniform(-14, 14)),
                  (90, 60, 44), "CorrodedMetal", angles=(rng.uniform(-40, 40), 90 + rng.uniform(-20, 20), rng.uniform(-30, 30)))
            b.box("Decor", "Rebar", (0.25, 0.25, rng.uniform(4, 8)), (gap[1] + rng.uniform(-1, 1), top - 1.4, z + rng.uniform(-14, 14)),
                  (90, 60, 44), "CorrodedMetal", angles=(rng.uniform(-40, 40), 90 + rng.uniform(-20, 20), rng.uniform(-30, 30)))
        for k in range(8):
            self.rubble(rng.uniform(gap[0], gap[1]), z + rng.uniform(-18, 18), 7, (140, 136, 128), y=0.4)
        self.car(gap[1] - 8, z + 9, 110, burned=True, y=0.6)
        self.smoke_column(gap[0] + 20, 3, z)
        # Wracks und Stau auf der Hochstraße
        for k in range(18):
            x = rng.uniform(x0 + ramp, x1 - ramp)
            if gap[0] - 20 < x < gap[1] + 20:
                continue
            s = rng.choice((-1, 1)) * rng.uniform(3, width / 2 - 4)
            self.car(x, z + s, 90 + rng.uniform(-30, 30) + (180 if s < 0 else 0), y=top)
        for k in range(4):
            x = rng.uniform(x0 + ramp + 20, x1 - ramp - 20)
            if not (gap[0] - 20 < x < gap[1] + 20):
                self.fire(x, z + rng.choice((-1, 1)) * 12, y=top, smoke=rng.random() < 0.5)
        # Laternen und Schilderbrücken (Schilder werden später verwittert)
        x = x0 + ramp
        while x < x1 - ramp:
            if not (gap[0] - 6 < x < gap[1] + 6):
                for s in (-1, 1):
                    tilt = rng.choice((0, 0, rng.uniform(-20, 20)))
                    b.box("Decor", "StreetLamp", (0.6, 12, 0.6), (x, top + 6, z + s * (width / 2 - 0.5)), (40, 42, 46), "Metal",
                          angles=(tilt, 0, 0))
            x += 90
        for gx, title, sub in ((x0 + ramp + 30, "A7  ÖDSTADT-NORD", "SANDBACH 3 KM"), (x1 - ramp - 30, "A7  ÖDSTADT-NORD", "NORDHEIM 4 KM")):
            for s in (-1, 1):
                b.box("Decor", "GantryPost", (1, 9, 1), (gx, top + 4.5, z + s * (width / 2 - 0.5)), (110, 112, 116), "Metal")
            b.box("Decor", "GantryBeam", (1, 1, width), (gx, top + 9, z), (110, 112, 116), "Metal")
            for yaw in (90, -90):
                b.sign2("AutobahnSign", (16, 4, 0.3), (gx + (-0.7 if yaw == 90 else 0.7), top + 11.2, z + (-8 if yaw == 90 else 8)),
                        title, sub, (40, 86, 60), (230, 230, 220), (220, 220, 210), angles=(0, yaw, rng.uniform(-3, 3)))
        # Zufahrten unten an die Landstraßen
        self.road(x0 - 40, z, x0, z, HIGHWAY_W, cracked=False)
        self.road(x1, z, x1 + 60, z - 20, HIGHWAY_W, cracked=False)

    def railway(self):
        """Bahnstrecke West -> Hafen: Schotterbett, Schwellen-Bohlen, Schienen; Bahnübergänge mit Schranken."""
        b, rng = self.b, self.rng
        for (ax, az), (bx, bz) in zip(RAIL, RAIL[1:]):
            length = math.hypot(bx - ax, bz - az)
            n = max(1, int(length // 40))
            for k in range(n):
                pa = (ax + (bx - ax) * k / n, az + (bz - az) * k / n)
                pc = (ax + (bx - ax) * (k + 1) / n, az + (bz - az) * (k + 1) / n)
                ext = 0.6 / max(1.0, length / n)
                pc2 = (pa[0] + (pc[0] - pa[0]) * (1 + ext), pa[1] + (pc[1] - pa[1]) * (1 + ext))
                self.slab("Roads", "RailBed", (pa[0], 0.55, pa[1]), (pc2[0], 0.55, pc2[1]), 10, 3.0, (104, 98, 90), "Pebble")
                self.slab("Roads", "Sleepers", (pa[0], 0.75, pa[1]), (pc2[0], 0.75, pc2[1]), 6.6, 0.2, (78, 62, 48), "WoodPlanks")
                dx, dz = (bx - ax) / length, (bz - az) / length
                for s in (-1, 1):
                    ox_, oz_ = -dz * s * 2.4, dx * s * 2.4
                    self.slab("Roads", "Rail", (pa[0] + ox_, 1.15, pa[1] + oz_), (pc2[0] + ox_, 1.15, pc2[1] + oz_), 0.35, 0.4,
                              (96, 74, 60), "CorrodedMetal")
            # Bahnübergänge: wo eine Straße die Strecke kreuzt – Andreaskreuz und Schranke auf jeder Seite
            ux, uz = (bx - ax) / length, (bz - az) / length
            yaw = math.degrees(math.atan2(-uz, ux))
            for rx0, rz0, rx1, rz1, w in list(self.roads):
                hit = seg_intersect((ax, az), (bx, bz), (rx0, rz0), (rx1, rz1))
                if not hit:
                    continue
                rl = math.hypot(rx1 - rx0, rz1 - rz0) or 1
                vx, vz = (rx1 - rx0) / rl, (rz1 - rz0) / rl
                if vx * -uz + vz * ux < 0:
                    vx, vz = -vx, -vz
                for s in (-1, 1):
                    px, pz = hit[0] + vx * s * 9, hit[1] + vz * s * 9
                    sx_, sz_ = px + ux * s * (w / 2 + 2), pz + uz * s * (w / 2 + 2)
                    b.box("Decor", "CrossingPost", (0.4, 5, 0.4), (sx_, 2.5, sz_), (200, 200, 200), "Metal")
                    for ang in (45, -45):
                        b.box("Decor", "CrossingSign", (3.4, 0.5, 0.15), (sx_, 4.6, sz_), (220, 60, 50), "SmoothPlastic",
                              angles=(0, yaw + 90, ang))
                    up = rng.random() < 0.5
                    ax_, az_ = px + ux * s * (w / 4 + 1), pz + uz * s * (w / 4 + 1)
                    b.box("Decor", "CrossingArm", (w * 0.5, 0.4, 0.4), (ax_, 1.6 if not up else 3.5, az_), (210, 60, 50), "Metal",
                          angles=(0, yaw, rng.uniform(-6, 6) if not up else s * 35))
        # Prellbock am Ende im Hafen
        ex, ez = RAIL[-1]
        b.box("Walls", "BufferStop", (3, 3, 8), (ex, 1.5, ez), (160, 40, 36), "Metal",
              angles=(0, math.degrees(math.atan2(-(RAIL[-1][1] - RAIL[-2][1]), RAIL[-1][0] - RAIL[-2][0])), 0))

    def station(self):
        """Bahnhof Ödstadt Süd: zwei Bahnsteige mit Dach, Bahnhofsgebäude, entgleister Zug."""
        b, rng = self.b, self.rng
        # Stelle an der Strecke suchen, an der keine Straße über die Bahnsteige läuft
        (ax, az), (bx, bz) = RAIL[STATION_SEG], RAIL[STATION_SEG + 1]
        length = math.hypot(bx - ax, bz - az)
        dx, dz = (bx - ax) / length, (bz - az) / length
        nx, nz = -dz, dx
        if nz < 0:
            nx, nz = -nx, -nz  # Gebäude auf der Stadtseite (Norden)
        best = None
        for t in range(70, int(length) - 70, 10):
            cx, cz = ax + dx * t, az + dz * t
            ok = all(dist_point_segment(cx + dx * u + nx * v, cz + dz * u + nz * v, *r[:4]) > r[4] / 2 + 4
                     for r in self.roads for u in (-70, -35, 0, 35, 70) for v in (-12, 12, 34))
            if ok:
                best = (cx, cz)
                break
        if not best:
            best = (ax + dx * length / 2, az + dz * length / 2)
        cx, cz = best
        yaw = math.degrees(math.atan2(-dz, dx))

        def at(u, v):
            return cx + dx * u + nx * v, cz + dz * u + nz * v
        self.occupied.append((cx + nx * 30, cz + nz * 30, 40))
        for v in (-9.5, 9.5):
            px, pz = at(0, v)
            b.box("Buildings", "Platform", (130, 2.4, 7), (px, 0.8, pz), (150, 146, 136), "Concrete", angles=(0, yaw, 0))
            ex, ez = at(0, v - 3.2 if v > 0 else v + 3.2)
            b.box("Decor", "PlatformEdge", (130, 0.05, 0.6), (ex, 2.03, ez), (200, 180, 70), "SmoothPlastic", angles=(0, yaw, 0))
            for u in range(-50, 51, 20):
                qx, qz = at(u, v + (1.5 if v > 0 else -1.5))
                b.box("Buildings", "CanopyPost", (0.6, 8, 0.6), (qx, 6, qz), (60, 64, 68), "Metal")
            rx, rz = at(0, v)
            for u0, u1 in ((-56, -10), (-10, 30), (30, 56)):
                if rng.random() < 0.25:
                    continue  # Dach eingestürzt
                mx, mz = at((u0 + u1) / 2, v)
                b.box("Buildings", "Canopy", (u1 - u0, 0.4, 9), (mx, 10.2, mz), (88, 92, 96), "CorrodedMetal",
                      angles=(rng.uniform(-3, 3), yaw, rng.uniform(-2, 2)))
            sx, sz = at(-30, v)
            b.sign2("StationSign", (10, 2.4, 0.25), (sx, 8, sz), "ÖDSTADT SÜD", "GLEIS %d" % (1 if v > 0 else 2), (40, 60, 110),
                    (230, 230, 230), (220, 220, 220), angles=(0, yaw, rng.uniform(-4, 4)))
            for u in (-40, 0, 40):
                qx, qz = at(u, v)
                b.box("Cover", "Bench", (5, 1.4, 1.6), (qx, 2.6, qz), (90, 70, 50), "WoodPlanks", angles=(0, yaw, 0))
        # Bahnhofsgebäude hinter Gleis 1, Front zum Bahnsteig
        pb = self.ruin_house(52, 20, 14, (168, 120, 96), "Brick", damage=0.45, shop=("BAHNHOF", "ÖDSTADT SÜD", (230, 220, 200)))
        hx, hz = at(0, 26)
        self.stamp(pb, hx, hz, self.yaw_to(-nx, -nz))
        # Vorplatz zur Stadt: Straße bis zum nächsten Ring
        qx, qz = at(0, 40)
        tx, tz = qx + nx * 60, qz + nz * 60
        best_r = min(self.roads, key=lambda r: dist_point_segment(qx, qz, *r[:4]))
        # Fußweg/Straße vom Vorplatz zur nächsten Straße
        rx0, rz0, rx1, rz1, _ = best_r
        l2 = (rx1 - rx0) ** 2 + (rz1 - rz0) ** 2 or 1
        t = max(0.0, min(1.0, ((qx - rx0) * (rx1 - rx0) + (qz - rz0) * (rz1 - rz0)) / l2))
        jx, jz = rx0 + (rx1 - rx0) * t, rz0 + (rz1 - rz0) * t
        if math.hypot(jx - qx, jz - qz) < 120:
            self.road(qx, qz, jx, jz, 14, lines=False, cracked=True)
        # Zug: Lok und Wagen auf Gleis, die letzten zwei entgleist und umgekippt
        colors = ((150, 40, 36), (170, 168, 160), (170, 168, 160), (60, 90, 120), (170, 168, 160))
        u = -60.0
        for k, color in enumerate(colors):
            lng = 22 if k == 0 else 26
            mid = u + lng / 2
            px, pz = at(mid, 0)
            derail = k >= 3
            if derail:
                px, pz = px + nx * -(4 + 5 * (k - 3)), pz + nz * -(4 + 5 * (k - 3))
            roll = (rng.uniform(70, 88) if k == 4 else rng.uniform(10, 25)) if derail else 0
            ang = (0, yaw + 90 + (rng.uniform(-14, 14) if derail else 0), roll)
            body_y = 4.2 if not derail else (3.4 if k == 4 else 4.0)
            b.box("Buildings", "TrainCar", (6.6, 6.4, lng), (px, body_y, pz), color, "CorrodedMetal", angles=ang)
            b.box("Decor", "TrainWindows", (6.7, 1.6, lng - 4), (px, body_y + 1.2, pz), (30, 34, 38), "Glass", angles=ang,
                  props={"Transparency": 0.2})
            b.box("Decor", "TrainRoof", (5.8, 0.6, lng - 1), (px, body_y + 3.5, pz), (90, 90, 92), "Metal", angles=ang)
            if k == 0:
                b.box("Decor", "Pantograph", (0.3, 2.4, 3), (px, body_y + 4.8, pz), (50, 50, 50), "Metal", angles=(20, yaw + 90, 0))
            u += lng + 1.5
        sx_, sz_ = at(30, -12)
        self.smoke_column(sx_, 2, sz_)
        PLACES["Bahnhof"] = ("BAHNHOF ÖDSTADT SÜD", cx, cz, 80)

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
    (ax, az), (bx, bz) = AUTOBAHN
    w.corridors.append((ax - 40, az, bx + 60, bz, AUTOBAHN_W + 16))
    for (ax, az), (bx, bz) in zip(RAIL, RAIL[1:]):
        w.corridors.append((ax, az, bx, bz, 18))
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
    for pts in highway_lines():
        w.road_line(pts, HIGHWAY_W)
    for sx, sz in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        w.road(sx * (CAMP_HALF + 2), sz * (CAMP_HALF + 2), sx * 180, sz * 180, ROAD_W, lines=False, cracked=False)
    for gas in GAS:
        w.build_gas(*gas)

    # Kleine Safe Zones draußen (Safehouses) mit Zufahrt
    for key, title, x, z in SAFEHOUSES:
        w.safehouse(key, title, x, z)

    # Feldwege von der nächsten Landstraße hinauf zu den Außenposten und zum Funkturm
    for _, _, x, z in OUTPOSTS + [("Funkturm", "", PLACES["Funkturm"][1], PLACES["Funkturm"][2])]:
        start = w.nearest_highway(x, z)
        if start:
            mid = ((start[0] + x) / 2 + rng.uniform(-40, 40), (start[1] + z) / 2 + rng.uniform(-40, 40))
            dx, dz = x - mid[0], z - mid[1]
            dl = math.hypot(dx, dz) or 1
            w.track([start, mid, (x - dx / dl * 30, z - dz / dl * 30)])

    # Ödstadt: Straßen mit Gehwegen; darüber die Hochstraße, an der Bahn der Bahnhof
    first = len(w.roads)
    for pts in w.city_streets():
        w.road_line(pts, ROAD_W, sidewalk=True)
    city_segments = [s for s in w.roads[first:]]
    w.autobahn()
    w.station()
    w.sidewalks()

    # Einzelne Häuser und Scheunen an den Landstraßen (außerhalb der Orte)
    def rural_zone(x, z):
        if any(math.hypot(x - fx, z - fz) < fr + 40 for fx, fz, fr in FLATS):
            return None
        return "rural"
    for seg in [s_ for s_ in w.roads if s_[4] == HIGHWAY_W]:
        w.line_buildings(seg[0], seg[1], seg[2], seg[3], seg[4], rural_zone, 0.35, gap=(50, 120))

    # Ödstadt: Häuser an jeder Straße
    def city_zone(x, z):
        r = math.hypot(x, z)
        if r < 175 or r > 750:
            return None
        return "downtown" if r < 300 else ("city" if r < 540 else "suburb")
    for seg in city_segments + [s for s in w.roads[:first] if s[4] == HIGHWAY_W and math.hypot((s[0] + s[2]) / 2, (s[1] + s[3]) / 2) < 740]:
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
        side = rng.choice((-1, 1)) * (seg[4] / 2 + 2.5)
        x, z = seg[0] + (seg[2] - seg[0]) * t + nx * side, seg[1] + (seg[3] - seg[1]) * t + nz * side
        if math.hypot(x, z) > SAFE_R + 60:
            w.litter(x, z, y=0.6, spread=1.4)
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

    # Bahnstrecke zuletzt (Bahnübergänge an allen Straßen), dann rote Zonen, Aktivitäten, Orte, Seen
    w.railway()
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

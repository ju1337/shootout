"""Höhenfeld der offenen Welt EXTINCTION (Hügel, Seen, Bergrand).

Wird von tools/build_maps.py benutzt: Bäume, Felsen und Lagerkisten stehen auf dem Gelände, und
`write_lua()` schreibt das Raster nach src/server-shared/ExtinctionTerrainData.lua. Der Server (ExtinctionTerrain.lua)
baut daraus beim Start echtes Terrain. Die Abtastung (Catmull-Rom über ein 16-Stud-Raster) ist in Lua und hier
identisch, damit Objekte und Gelände zusammenpassen.

Koordinaten: x/z relativ zur Mitte der Welt (Camp Phoenix), Höhen in Studs. FLAT ist die Höhe der ebenen Flächen
(Straßen, Orte, Safe Zone); dort liegen die Bauteile der Karte bei y = 0, das Terrain 0,4 darunter.
"""
import math
import os
import random

CELL = 16            # Rasterweite in Studs
HALF = 1120          # Raster reicht von -HALF bis +HALF (die Welt ist 1800 groß, dahinter steigt der Bergrand)
N = 2 * HALF // CELL  # Zellen pro Achse
FLAT = -0.4          # Geländehöhe auf ebenen Flächen
WATER = -3.0         # Wasserspiegel (nur die Seen liegen tiefer, sonst nirgends)
MIN_H, MAX_H = -16.0, 60.0  # Wertebereich der gespeicherten Höhen

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "server-shared", "ExtinctionTerrainData.lua")


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


class Noise:
    """Value-Noise mit glatter Mischung, mehrere Oktaven."""

    def __init__(self, seed, size=64):
        rng = random.Random(seed)
        self.size = size
        self.grid = [[rng.random() for _ in range(size)] for _ in range(size)]

    def at(self, x, z):
        size = self.size
        x0, z0 = math.floor(x), math.floor(z)
        fx, fz = smooth(x - x0), smooth(z - z0)
        g = self.grid
        a = g[x0 % size][z0 % size]
        b = g[(x0 + 1) % size][z0 % size]
        c = g[x0 % size][(z0 + 1) % size]
        d = g[(x0 + 1) % size][(z0 + 1) % size]
        return (a + (b - a) * fx) * (1 - fz) + (c + (d - c) * fx) * fz

    def fbm(self, x, z, octaves=4):
        total, amp, norm, freq = 0.0, 1.0, 0.0, 1.0
        for _ in range(octaves):
            total += self.at(x * freq + 17.3 * freq, z * freq - 9.1 * freq) * amp
            norm += amp
            amp *= 0.5
            freq *= 2.0
        return total / norm


class Terrain:
    """flats: Liste (x, z, r_flach, r_Übergang) kreisförmiger Ebenen; roads: (x0, z0, x1, z1, Breite) Streifen;
    lakes: (x, z, Radius, Tiefe)."""

    def __init__(self, seed=7):
        self.noise = Noise(seed)
        self.flats = []
        self.roads = []
        self.lakes = []
        self.hills = []
        self.grid = None

    # ----- Beschreibung -----
    def flat(self, x, z, r, blend=70):
        self.flats.append((x, z, r, blend))

    def road(self, x0, z0, x1, z1, width=24, blend=64):
        self.roads.append((x0, z0, x1, z1, width, blend))

    def lake(self, x, z, r, depth=9):
        self.lakes.append((x, z, r, depth))

    def hill(self, x, z, r, height, top=24):
        """Markanter Hügel mit ebener Kuppe (Radius top) und Hang bis Radius r – z. B. für den Funkturm."""
        self.hills.append((x, z, r, height, top))

    # ----- Formel -----
    def _flat_weight(self, x, z):
        """0 = Gelände frei, 1 = ganz eben."""
        w = 0.0
        for fx, fz, r, blend in self.flats:
            d = math.hypot(x - fx, z - fz)
            w = max(w, 1 - smooth((d - r) / blend))
        for x0, z0, x1, z1, width, blend in self.roads:
            dx, dz = x1 - x0, z1 - z0
            length2 = dx * dx + dz * dz
            t = max(0.0, min(1.0, ((x - x0) * dx + (z - z0) * dz) / length2)) if length2 > 0 else 0.0
            d = math.hypot(x - (x0 + dx * t), z - (z0 + dz * t))
            w = max(w, 1 - smooth((d - width / 2) / blend))
        return w

    def _lake(self, x, z):
        """(Maske 0..1, Beckenhöhe) des tiefsten Sees an der Stelle; Maske 1 = ganz im See."""
        best, floor = 0.0, FLAT
        for lx, lz, r, depth in self.lakes:
            wobble = 1 + 0.25 * (self.noise.fbm(x / 70 + lx, z / 70 + lz, 2) - 0.5) * 2  # unregelmäßiger Rand
            d = math.hypot(x - lx, z - lz) / (r * wobble)
            mask = 1 - smooth((d - 0.75) / 0.55)
            if mask > best:
                best = mask
                floor = FLAT - depth * (1 - smooth(d / 0.95)) - 1.5
        return best, floor

    def height(self, x, z):
        """Geländehöhe an einer Stelle (ohne Raster)."""
        n = self.noise.fbm(x / 210.0, z / 210.0, 4)
        hills = max(0.0, n - 0.40) / 0.60          # 0..1
        hills = (hills ** 1.05) * 58.0               # Hügelland, Kuppen bis ca. 25 Studs
        # sanfte Dellen und kleine Buckel auch auf freier Fläche
        bumps = (self.noise.fbm(x / 55.0 + 5, z / 55.0 - 3, 3) - 0.5) * 4.0
        free = 1 - self._flat_weight(x, z)
        h = FLAT + max(-0.9, (hills + bumps) * free)
        for hx, hz, r, height, top in self.hills:
            d = math.hypot(x - hx, z - hz)
            h += height * (1 - smooth((d - top) / max(1.0, r - top)))
        mask, floor = self._lake(x, z)
        if mask > 0:
            h = h + (floor - h) * mask
        # Bergrand: hinter der Spielfläche steigt das Gelände steil an (statt Mauer)
        edge = max(abs(x), abs(z)) - 860
        if edge > 0:
            # Straßen schneiden als ebene Schneise durch den Bergrand bis zum Ende der Welt
            h += smooth(edge / 260.0) * 46.0 * (0.7 + 0.6 * self.noise.fbm(x / 90.0, z / 90.0, 2)) * free
        return max(MIN_H, min(MAX_H, h))

    # ----- Raster -----
    def build(self):
        pts = N + 1
        self.grid = [[self.height(-HALF + i * CELL, -HALF + j * CELL) for j in range(pts)] for i in range(pts)]
        return self.grid

    def sample(self, x, z):
        """Höhe aus dem Raster (Catmull-Rom), wie in ExtinctionTerrain.lua."""
        if self.grid is None:
            self.build()
        return sample(self.grid, x, z)

    def is_water(self, x, z):
        return self.sample(x, z) < WATER

    def slope(self, x, z, d=6.0):
        gx = (self.sample(x + d, z) - self.sample(x - d, z)) / (2 * d)
        gz = (self.sample(x, z + d) - self.sample(x, z - d)) / (2 * d)
        return math.hypot(gx, gz)


def _cr(p0, p1, p2, p3, t):
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def sample(grid, x, z):
    pts = len(grid)
    fx = (x + HALF) / CELL
    fz = (z + HALF) / CELL
    fx = max(0.0, min(pts - 1.001, fx))
    fz = max(0.0, min(pts - 1.001, fz))
    i, j = int(math.floor(fx)), int(math.floor(fz))
    tx, tz = fx - i, fz - j

    def at(a, b):
        return grid[max(0, min(pts - 1, a))][max(0, min(pts - 1, b))]

    rows = []
    for dj in (-1, 0, 1, 2):
        rows.append(_cr(at(i - 1, j + dj), at(i, j + dj), at(i + 1, j + dj), at(i + 2, j + dj), tx))
    return _cr(rows[0], rows[1], rows[2], rows[3], tz)


def encode(grid):
    """Raster -> Text: je Wert 2 Zeichen (Basis 64, Schrittweite (MAX_H-MIN_H)/4095), Zeilen nacheinander."""
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    out = []
    for column in grid:
        for h in column:
            v = int(round((max(MIN_H, min(MAX_H, h)) - MIN_H) / (MAX_H - MIN_H) * 4095))
            out.append(chars[v // 64] + chars[v % 64])
    return "".join(out)


def write_lua(terrain, path=OUT):
    grid = terrain.grid or terrain.build()
    text = encode(grid)
    lines = [text[i:i + 100] for i in range(0, len(text), 100)]
    body = ",\n".join('\t\t"%s"' % line for line in lines) + ","
    with open(path, "w", encoding="utf-8") as f:
        f.write(
            "-- ExtinctionTerrainData (ModuleScript)\n"
            "-- Höhenfeld der offenen Welt – ERZEUGT von tools/build_maps.py (tools/extinction_terrain.py), nicht von Hand ändern.\n"
            "-- Raster %d x %d, Zellen %d Studs, x/z von -%d bis %d relativ zur Mitte; Werte 2 Zeichen Basis 64 von %.0f bis %.0f.\n\n"
            "return {\n"
            "\tCell = %d,\n"
            "\tHalf = %d,\n"
            "\tPoints = %d,\n"
            "\tMinHeight = %.1f,\n"
            "\tMaxHeight = %.1f,\n"
            "\tFlat = %.1f,\n"
            "\tWater = %.1f,\n"
            "\tText = table.concat({\n%s\n\t}),\n"
            "}\n" % (N + 1, N + 1, CELL, HALF, HALF, MIN_H, MAX_H, CELL, HALF, N + 1, MIN_H, MAX_H, FLAT, WATER, body))

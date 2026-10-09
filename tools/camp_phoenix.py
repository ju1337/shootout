"""Camp Phoenix: die große Safe Zone in der Mitte der offenen Welt (Start des Spiels).

Eine runde Altstadt (Stil DayZ/Tarkov, aber gepflegt): von innen nach außen

  * PHÖNIXPLATZ (Radius PLAZA_R): Kopfsteinpflaster, in der Mitte ein runder Brunnen, Spawn-Ring um den Brunnen, Bänke, Bäume in Kübeln, Laternen,
    Lichterketten, Café-Terrasse, das Siegerpodest vor dem Rathaus.
  * INNERER HÄUSERRING (Fronten bei INNER_R): acht Altbauten mit Läden im Erdgeschoss, Schilder zum Platz, je Seite
    ein breites und ein schmales Haus:
      NO AUSRÜSTER (offene Arkade mit den Shop-Vitrinen) · WAFFEN & MUNITION
      SO CAFÉ ZENTRAL (Terrasse) · APOTHEKE
      SW RATHAUS (Uhrturm, Rathauslaube mit LAGEBERICHT und RUHMESWAND, davor das Siegerpodest) · TAUSCHMARKT
      NW GLÜCKSRAD (Spielhalle mit dem Rad) · LAGERHAUS
    Die Rückseiten der Häuser (Fenster, Hoftüren) stehen an der Ringstraße.
  * Vier HAUPTSTRASSEN (Asphalt, Gehsteige, Laternen, Wegweiser) vom Platz zu den Toren, eine RINGSTRASSE (RING_R).
  * ÄUSSERER HÄUSERRING (Fronten bei OUTER_R), je Viertel vier Häuser mit einer Gasse in der Mitte:
      NO MARKTVIERTEL (KIT-AUSGABE, Garküche, Stoffe, Funk; hinten die Marktgasse mit dem Schieber),
      SO FUHRPARK (KFZ-WERKSTATT, Ersatzteile, Hotel; hinten Tankstelle, Landeplatz, Parkplatz),
      SW DEPOT (BUSBAHNHOF, MARKTHALLE mit dem Tor zur Markt-Welt, Spedition; hinten Container und Kran),
      NW WOHNVIERTEL (VERSTECK, Wohnhäuser, Schule; hinten Garten, Lagerfeuer, Wasserturm, Gruftkapelle
        KATAKOMBEN = Dungeon-Eingang).
  * Betonmauer mit Stacheldraht (CAMP_WALL_R, wie im alten Camp), vier Tore, davor das Sperrgebiet.

Geometrie: Kompass th in Grad ab Norden (+Z) im Uhrzeigersinn, Osten = +X; P(r, th) gibt (x, z). Jedes Haus hat
seine Vorderseite bei lokal -Z und schaut zur Mitte. Die Teile, die Server und Client suchen (Shop, Rad, Bestenlisten,
Podest, Markt-Tor), landen in der Gruppe "Zentrale" (immer geladen, src/shared/Zentrale.lua).
Läuft mit eigenen Zufallszahlen (World.camp).
"""
import math

SAFE_R = 165                 # Safe Zone (Radius, Teil "SafeZone")
CAMP_WALL_R = 110            # Mitte der Mauer
PLAZA_R = 36                 # Phönixplatz (Apothem des 16-Ecks)
STREET_W, WALK_W = 14, 3     # Fahrbahn, Gehsteig je Seite
LINE = STREET_W / 2 + WALK_W  # Bauflucht neben den Straßen (Abstand zur Straßenachse)
HOUSE_D = 16                 # Haustiefe
INNER_R = 36.5               # Fronten am Platz (Rückseiten bei INNER_R + HOUSE_D)
RING_R, RING_W = 59.5, 10    # Ringstraße
OUTER_R = 66.5               # Fronten an der Ringstraße
YARD_R0, YARD_R1 = 83, 107   # Hinterhöfe hinter dem äußeren Ring
GATE_W = 18                  # Durchfahrt in den Toren
W_WIDE, W_NARROW = 22, 15    # Hausbreiten am Platz
W_OUTER = 18                 # Hausbreite an der Ringstraße

GRAVEL = (128, 120, 104)
PLANK, PLANK_DARK, DARK = (128, 100, 70), (92, 72, 52), (40, 42, 46)
GOLD = (212, 170, 80)
STONE, STONE_DARK = (150, 146, 138), (104, 100, 94)
ASPHALT, COBBLE = (58, 60, 62), (128, 122, 114)
PLASTER = ((196, 160, 96), (178, 112, 80), (204, 188, 156), (150, 168, 134), (124, 142, 160), (214, 206, 190),
           (200, 150, 120), (188, 142, 112), (206, 196, 176))
ROOFS = ((152, 78, 54), (112, 60, 48), (74, 74, 80), (140, 76, 58), (104, 80, 64))

# Stationen als Läden im Erdgeschoss: Schlüssel -> (Titel, Unterzeile, Farbe)
STATIONS = {
    "Stand_Weapons": ("WAFFEN & MUNITION", "ANKAUF · VERKAUF · TAUSCH", (226, 140, 60)),
    "Stand_Items": ("APOTHEKE", "VERBAND · MEDIZIN · WESTEN", (90, 200, 110)),
    "Stand_Market": ("TAUSCHMARKT", "SPIELER HANDELN", (230, 186, 70)),
    "Stash": ("LAGERHAUS", "DEINS BLEIBT DEINS", (176, 186, 200)),
    "Stand_Vehicles": ("KFZ-WERKSTATT", "FAHRZEUGE · REPARATUR", (110, 176, 230)),
    "Travel": ("BUSBAHNHOF", "FAHRT ZU ANDEREN SAFE ZONES", (110, 170, 220)),
    "Hideout": ("VERSTECK", "DEIN UNTERSCHLUPF · AUSBAUEN", (200, 160, 110)),
    "Kits": ("KIT-AUSGABE", "STARTPAKETE · KOSTENLOS", (70, 150, 90)),
}


def P(r, th):
    """Punkt im Abstand r von der Mitte in Kompassrichtung th (0 = Norden = +Z, 90 = Osten = +X)."""
    a = math.radians(th)
    return r * math.sin(a), r * math.cos(a)


def half_angle(r, w):
    """Halber Öffnungswinkel (Grad) einer Front der Breite w im Abstand r."""
    return math.degrees(math.atan2(w / 2, r))


class CampPhoenix:
    """Mixin für World (tools/extinction_world.py)."""

    # ---------- Grundlagen ----------
    def at_center(self, r, th):
        """(x, z, yaw) an Position (r, th), Vorderseite (lokal -Z) zur Mitte."""
        x, z = P(r, th)
        return x, z, self.yaw_to(-x, -z)

    def arc_pad(self, name, r0, r1, th0, th1, color, mat, top, group="Ground", step=6.0, thickness=0.2):
        """Ringstück (r0 bis r1, Winkel th0 bis th1) aus schmalen Platten, Oberkante top."""
        n = max(1, int(math.ceil((th1 - th0) / step)))
        d = (th1 - th0) / n
        for k in range(n):
            th = th0 + (k + 0.5) * d
            x, z, yaw = self.at_center((r0 + r1) / 2, th)
            width = 2 * r1 * math.tan(math.radians(d / 2)) + 0.3
            self.b.box(group, name, (width, thickness, r1 - r0), (x, top - thickness / 2, z), color, mat, angles=(0, yaw, 0))

    def polygon_pad(self, name, apothem, color, mat, top, thickness=0.2, group="Ground"):
        """Runde Fläche als 16-Eck (vier gedrehte Quadrate; die Karte zeichnet Rechtecke)."""
        for k in range(4):
            self.b.box(group, name, (2 * apothem, thickness, 2 * apothem), (0, top - thickness / 2, 0), color, mat,
                       angles=(0, k * 22.5, 0))

    def string_lights(self, a, b_, y, sag=1.2, n=7, color=(255, 214, 140)):
        """Lichterkette zwischen zwei Punkten (x, z) in Höhe y: Kabel und Glühbirnen (ohne Licht, nur Leuchten)."""
        (ax, az), (bx, bz) = a, b_
        length = math.hypot(bx - ax, bz - az)
        yaw = math.degrees(math.atan2(-(bz - az), bx - ax))
        self.b.box("Decor", "LightCable", (length, 0.08, 0.08), ((ax + bx) / 2, y - sag * 0.6, (az + bz) / 2), (30, 30, 30),
                   "SmoothPlastic", angles=(0, yaw, 0), props={"CanCollide": False, "CanQuery": False})
        for k in range(1, n):
            t = k / n
            dy = -sag * 4 * t * (1 - t)
            self.b.add("Decor", "Bulb", (0.35, 0.35, 0.35), (ax + (bx - ax) * t, y + dy - 0.3, az + (bz - az) * t), color, "SmoothPlastic",
                       props={"Shape": "Ball", "CanCollide": False, "CanQuery": False})

    def camp_lamp(self, x, z, fx, fz):
        """Altstadt-Laterne: Mast mit Ausleger zur Seite (fx, fz) und warmem Laternenkopf."""
        f, box = self.frame(x, z, self.yaw_to(fx, fz))
        box("Decor", "LampBase", (0.9, 1.2, 0.9), (0, 0.6, 0), DARK, "Metal")
        box("Decor", "LampPost", (0.45, 11, 0.45), (0, 6, 0), DARK, "Metal")
        box("Decor", "LampArm", (0.3, 0.3, 2.2), (0, 11.2, -1), DARK, "Metal")
        # kein Neon: mit dem Bloom der Map würde der Kopf zu einer riesigen weißen Kugel; Licht kommt vom PointLight
        box("Decor", "LampHead", (1, 1.3, 1), (0, 10.6, -2), (255, 232, 200), "SmoothPlastic",
            children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 30, "Brightness": 1.1,
                                                                                 "Color": self.bm.rgb(255, 220, 170)}}])
        box("Decor", "LampHat", (1.4, 0.3, 1.4), (0, 11.4, -2), DARK, "Metal")

    def signpost(self, x, z, boards):
        """Wegweiser: Pfahl mit Pfeil-Brettern über Kopfhöhe. boards = [(Richtung th, Text, Farbe)]."""
        b = self.b
        b.box("Decor", "SignpostPole", (0.6, 11, 0.6), (x, 5.5, z), PLANK_DARK, "Wood")
        for k, (th, text, color) in enumerate(boards):
            fx, fz = P(1, th)
            yaw = math.degrees(math.atan2(-fz, fx))  # Brett liegt entlang der Richtung (lokal +X zeigt dorthin)
            cx, cz = x + fx * 3.6, z + fz * 3.6
            y = 10.4 - k * 1.4
            board = {"Name": "SignGui", "ClassName": "SurfaceGui", "Properties": {
                "Face": "Front", "LightInfluence": 0.4, "SizingMode": "PixelsPerStud", "PixelsPerStud": 30},
                "Children": [{"Name": "Text", "ClassName": "TextLabel", "Properties": {
                    "Size": {"UDim2": [[1, 0], [1, 0]]}, "BackgroundTransparency": 1, "Text": text, "TextScaled": True,
                    "Font": "Oswald", "TextColor3": self.bm.rgb(*color)}}]}
            back = dict(board, Properties=dict(board["Properties"], Face="Back"))
            b.box("Decor", "SignpostBoard", (7.2, 1.3, 0.3), (cx, y, cz), (58, 46, 36), "WoodPlanks", angles=(0, yaw, 0),
                  children=[board, back], props={"CanCollide": False})
            b.add("Decor", "SignpostTip", (1.3, 1.3, 0.3), (x + fx * 7.4, y, z + fz * 7.4), (58, 46, 36), "WoodPlanks",
                  angles=(0, yaw, 45), props={"CanCollide": False})

    def crates(self, x, z, n=3, spread=3.0):
        rng = self.rng
        for _ in range(n):
            s = rng.uniform(2.2, 3.2)
            self.b.box("Cover", "Crate", (s, s * 0.9, s), (x + rng.uniform(-spread, spread), s * 0.45, z + rng.uniform(-spread, spread)),
                       rng.choice(((110, 92, 62), (96, 80, 56), (84, 98, 70))), "WoodPlanks", angles=(0, rng.uniform(0, 90), 0))

    def barrels(self, x, z, n=3, color=None):
        rng = self.rng
        for k in range(n):
            a = 2 * math.pi * k / n + rng.uniform(-0.3, 0.3)
            self.b.cylinder("Cover", "Barrel", 2.2, 3, (x + math.cos(a) * 1.4, 1.5, z + math.sin(a) * 1.4),
                            color or rng.choice(((60, 74, 50), (130, 56, 40), (52, 70, 104))), material="Metal")

    def container(self, x, z, yaw, color, y=0.0, length=16, group="Buildings", doors=False):
        """Seecontainer (8 x 8.5 x length), Längsseite entlang lokal X."""
        f, box = self.frame(x, z, yaw)
        box(group, "Container", (length, 8.5, 8), (0, y + 4.25, 0), color, "CorrodedMetal")
        for k in range(int(length // 2.6)):  # Sicken
            lx = -length / 2 + 1.6 + k * 2.6
            box("Decor", "ContainerRib", (0.4, 8.1, 8.15), (lx, y + 4.25, 0), self.bm.lighten(color, -0.12), "CorrodedMetal")
        if doors:
            box("Decor", "ContainerDoors", (0.2, 8, 7.6), (length / 2 + 0.1, y + 4.25, 0), self.bm.lighten(color, -0.2), "Metal")

    def plaza_tree(self, x, z, g=0.0, scale=1.0):
        """Lebender Baum (gepflegt, in der Safe Zone): Stamm und drei Kronenkugeln. Kein Teil heißt Trunk."""
        b, rng = self.b, self.rng
        h = 6 * scale
        b.box("Decor", "TreeStem", (0.9 * scale, h, 0.9 * scale), (x, g + h / 2, z), (84, 66, 50), "Wood")
        crown = rng.choice(((74, 110, 58), (86, 122, 62), (66, 104, 60)))
        for k, (dx, dy, dz, r) in enumerate(((0, 0, 0, 7), (1.8, 1.6, 0.8, 5), (-1.6, 1.2, -1.4, 5))):
            b.add("Decor", "TreeCrown", (r * scale, r * 0.85 * scale, r * scale), (x + dx * scale, g + h + 1.4 + dy * scale, z + dz * scale),
                  self.bm.lighten(crown, k * 0.08), "LeafyGrass", props={"Shape": "Ball", "CanCollide": False})

    def showcase(self, name, w, h, x, z, y, yaw, group="Zentrale"):
        """Schaukasten: Holzrahmen mit Messingecken um eine Holo-Tafel (Text schreibt der Client). (x, y, z) = Mitte
        der Tafel, die Front (lokal -Z) zeigt in Richtung yaw; der Rahmen liegt dahinter."""
        f, box = self.frame(x, z, yaw)
        box("Decor", "ShowcaseBack", (w + 1.0, h + 1.0, 0.25), (0, y, 0.3), (92, 70, 48), "WoodPlanks")
        box("Decor", "ShowcaseFrame", (w + 1.0, 0.4, 0.5), (0, y + h / 2 + 0.3, 0.1), (112, 86, 60), "Wood")
        box("Decor", "ShowcaseFrame", (w + 1.0, 0.4, 0.5), (0, y - h / 2 - 0.3, 0.1), (112, 86, 60), "Wood")
        box("Decor", "ShowcaseFrame", (0.4, h + 1.0, 0.5), (-w / 2 - 0.3, y, 0.1), (112, 86, 60), "Wood")
        box("Decor", "ShowcaseFrame", (0.4, h + 1.0, 0.5), (w / 2 + 0.3, y, 0.1), (112, 86, 60), "Wood")
        for sx in (-1, 1):
            for sy in (-1, 1):
                box("Decor", "ShowcaseCorner", (0.7, 0.7, 0.55), (sx * (w / 2 + 0.3), y + sy * (h / 2 + 0.3), 0.1), (176, 128, 64), "Metal")
        self.b.holo_panel(group, name, (w, h, 0.15), f(0, y, 0), angles=(0, yaw, 0))

    def _feature(self, build, x, z, yaw):
        """Prefab bauen (Vorderseite -Z zur Mitte) und aufstellen; Decor wird zur Gruppe Zentrale."""
        pb = self.prefab()
        build(pb)
        pb.groups["Zentrale"] = pb.groups.pop("Decor", []) + pb.groups.pop("Zentrale", [])
        self.stamp(pb, x, z, yaw)

    # ---------- Aufbau ----------
    def _camp(self):
        b = self.b
        R = SAFE_R
        b.add("Zone", "SafeZone", (2 * R, 80, 2 * R), (0, 40, 0), (96, 210, 120), "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
        self.polygon_pad("CampPad", CAMP_WALL_R + 6, (118, 110, 96), "Ground", 0.0, thickness=3)
        self.plaza()
        for th in (0, 90, 180, 270):
            self.street(th)
        self.ring_road()
        self.inner_ring()
        self.outer_ring()
        self.yard_market()
        self.yard_motor_pool()
        self.yard_depot()
        self.yard_living()
        self.camp_wall()
        self.glacis()

    # ---------- Phönixplatz ----------
    def plaza(self):
        """Pflasterplatz mit Brunnen (Spawn-Ring), Bänken unter Bäumen, Laternen, Lichterketten, Fahnen, der
        Café-Terrasse und dem Siegerpodest vor dem Rathaus; Wegweiser an der Nord- und Südstraße."""
        b = self.b
        self.polygon_pad("Square", PLAZA_R, COBBLE, "Cobblestone", 0.22)
        n = 32
        for k in range(n):
            th = 360 * (k + 0.5) / n
            x, z, yaw = self.at_center(PLAZA_R - 0.4, th)
            b.box("Ground", "SquareEdge", (2 * math.pi * PLAZA_R / n + 0.3, 0.35, 0.8), (x, 0.18, z), STONE_DARK, "Slate",
                  angles=(0, yaw, 0))
        for r in (16.5, 28):  # Pflasterringe im Muster
            self.arc_pad("SquareRing", r - 0.35, r + 0.35, 0, 360, (104, 96, 88), "Slate", 0.25, step=5)
        self.fountain()
        for k in range(10):
            th = 360 * (k + 0.5) / 10
            x, z = P(13, th)
            b.spawn(x, z, yaw=th)  # Blick nach außen
        # Bänke mit Blick zum Brunnen, dahinter Bäume in Pflanzkübeln, Lichterketten von Baum zu Baum
        trees = []
        for k in range(8):
            th = 22.5 + 45 * k
            x, z, yaw = self.at_center(19, th)
            f, box = self.frame(x, z, yaw)
            box("Cover", "Bench", (5, 0.4, 1.6), (0, 1.5, 0), (110, 84, 58), "WoodPlanks")
            box("Decor", "BenchBack", (5, 1.6, 0.3), (0, 2.5, 0.8), (110, 84, 58), "WoodPlanks")
            for s in (-1, 1):
                box("Decor", "BenchLeg", (0.3, 1.3, 1.4), (s * 2.2, 0.65, 0), (50, 50, 52), "Metal")
            tx, tz = P(24, th)
            b.box("Cover", "Planter", (4, 1.2, 4), (tx, 0.6, tz), STONE, "Concrete", angles=(0, -th, 0))
            b.box("Decor", "PlanterSoil", (3.4, 0.2, 3.4), (tx, 1.25, tz), (70, 56, 44), "Ground", angles=(0, -th, 0))
            self.plaza_tree(tx, tz, g=1.2, scale=0.9)
            trees.append((tx, tz))
        for k in range(8):
            self.string_lights(trees[k], trees[(k + 1) % 8], 9.2, sag=1.0, n=8)
        # Laternen an den Straßenmündungen (auf der Platzseite der Hausecken)
        for th in (0, 90, 180, 270):
            for d in (-1, 1):
                x, z = P(PLAZA_R - 2, th + d * 23)
                self.camp_lamp(x, z, -x, -z)
        # Fahnen beidseits der Nord- und Südmündung
        for th in (0, 180):
            for d in (-1, 1):
                x, z = P(PLAZA_R - 1, th + d * 18)
                b.box("Decor", "FlagPole", (0.5, 16, 0.5), (x, 8, z), (70, 72, 76), "Metal")
                b.box("Decor", "FlagBanner", (0.15, 6, 3.2), (x, 12.6, z), (176, 60, 40), "Fabric", angles=(0, -th + 90, 0),
                      props={"CanCollide": False})
                b.box("Decor", "FlagEmblem", (0.2, 1.8, 1.8), (x, 13.3, z), (236, 170, 70), "Fabric", angles=(0, -th + 90, 45),
                      props={"CanCollide": False})
        self.podium(*self.at_center(PLAZA_R - 6.5, 180 + self._inner_a() + half_angle(INNER_R, W_WIDE)))
        self.cafe_terrace()
        self.signposts()

    def _inner_a(self):
        """Halber Öffnungswinkel der Straßenmündungen am inneren Ring."""
        return math.degrees(math.asin(LINE / INNER_R))

    def fountain(self):
        """Brunnen in der Platzmitte: Stufe und rundes Becken mit Wasser (ohne Säule und Statue)."""
        b = self.b
        b.cylinder("Decor", "FountainStep", 19, 0.5, (0, 0.47, 0), STONE, material="Concrete")
        b.cylinder("Cover", "FountainBasin", 16, 2.2, (0, 1.8, 0), (138, 134, 126), material="Concrete")
        b.cylinder("Decor", "FountainRim", 16.6, 0.4, (0, 2.95, 0), STONE_DARK, material="Slate")
        b.cylinder("Decor", "FountainWater", 14.8, 0.3, (0, 2.6, 0), (70, 128, 168), material="Glass",
                   props={"Transparency": 0.35, "CanCollide": False, "Reflectance": 0.2})

    def podium(self, x, z, yaw):
        """SIEGERPODEST der Top 3 vor dem Rathaus (Statuen setzt der Server an Podium1-3): drei Steinsockel auf einer
        Stufe, Nummern, goldener Lichtkreis, Lorbeer, Titel im Pflaster davor. Bleibt niedrig, damit die Rathauslaube
        dahinter sichtbar bleibt."""
        def build(pb):
            gold = GOLD
            pb.box("Decor", "PodiumPlinth", (16, 0.6, 6.4), (0, 0.3, 0), STONE, "Concrete")
            for place, off, h, color in ((1, 0, 3.2, gold), (2, 5.3, 2.3, (190, 194, 200)), (3, -5.3, 1.5, (180, 120, 70))):
                pb.box("Decor", "PodiumBase", (4.6, h, 4.6), (off, 0.6 + h / 2, 0), (120, 116, 108), "Slate")
                pb.box("Decor", "PodiumTop", (4.8, 0.35, 4.8), (off, 0.78 + h, 0), color, "Metal")
                pb.add("Decor", "Podium" + str(place), (2, 0.2, 2), (off, 1.05 + h, 0), color, "SmoothPlastic",
                       props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
                pb.sign("PodiumNumber", (1.6, 1.3, 0.3), (off, 0.6 + h / 2, -2.45), str(place), (60, 58, 56), color)
                pb.add("Decor", "Laurel", (0.4, 4.2, 4.2), (off, 0.6 + h + 0.2, 0), (74, 110, 58), "LeafyGrass", angles=(0, 0, 90),
                       props={"Shape": "Cylinder", "CanCollide": False})
            pb.add("Decor", "PodiumGlow", (0.1, 5.6, 5.6), (0, 0.65, 0), gold, "Neon", angles=(0, 0, 90),
                   props={"Shape": "Cylinder", "Transparency": 0.7, "CanCollide": False})
            pb.floor_text("PodiumTitle", (14, 0.1, 2.2), (0, 0.3, -4.8), "SIEGERPODEST · TOP 3 NACH LEVEL", gold, yaw=180)
        self._feature(build, x, z, yaw)

    def cafe_terrace(self):
        """Terrasse vor dem CAFÉ ZENTRAL: drei Tische mit Schirmen und Stühlen auf dem Platz, Kreidetafel."""
        b = self.b
        th0 = 90 + self._inner_a() + half_angle(INNER_R, W_WIDE)   # Mitte des Cafés
        for th in (th0 - 9, th0, th0 + 9):
            x, z, yaw = self.at_center(PLAZA_R - 5.5, th)
            f, box = self.frame(x, z, yaw)
            b.cylinder("Cover", "CafeTable", 3.2, 0.25, f(0, 2.5, 0), (214, 206, 186), material="SmoothPlastic")
            box("Decor", "CafeTableLeg", (0.3, 2.4, 0.3), (0, 1.2, 0), DARK, "Metal")
            box("Decor", "UmbrellaPole", (0.25, 7.5, 0.25), (0, 3.75, 0), DARK, "Metal")
            b.cylinder("Decor", "Umbrella", 6, 0.3, f(0, 7.3, 0), (176, 60, 40), material="Fabric", props={"CanCollide": False})
            b.cylinder("Decor", "UmbrellaTop", 3, 0.3, f(0, 7.55, 0), (230, 220, 196), material="Fabric", props={"CanCollide": False})
            for lx, lz in ((-2.4, 0), (2.4, 0), (0, -2.4)):
                box("Cover", "CafeChair", (1.4, 0.3, 1.4), (lx, 1.4, lz), (110, 84, 58), "WoodPlanks")
                box("Decor", "CafeChairBack", (1.4, 1.6, 0.2), (lx * 1.3, 2.2, lz * 1.3), (110, 84, 58), "WoodPlanks")
                box("Decor", "CafeChairLeg", (0.2, 1.3, 0.2), (lx, 0.65, lz), DARK, "Metal")
        x, z, yaw = self.at_center(PLAZA_R - 2.2, th0 - 16)
        b.sign2("CafeBoard", (2.4, 3.0, 0.3), (x, 1.8, z), "HEUTE", "EINTOPF · KAFFEE · BROT", (40, 42, 40), (236, 230, 214),
                (200, 196, 180), angles=(0, yaw + 180, 0))

    def signposts(self):
        """Wegweiser am Platzrand neben der Nord- und Südmündung, Bretter zu Toren und Vierteln."""
        boards = [(0, "NORDTOR · KITS", (236, 226, 196)), (90, "OSTTOR · WERKSTATT", (240, 196, 120)),
                  (180, "SÜDTOR · BUSBAHNHOF", (240, 196, 120)), (270, "WESTTOR · VERSTECK", (200, 170, 120)),
                  (225, "MARKTHALLE", (120, 220, 180))]
        for th in (346, 166):
            self.signpost(*P(PLAZA_R - 4, th), boards)

    # ---------- Straßen ----------
    def street(self, th):
        """Hauptstraße vom Platz zum Tor (Richtung th): Asphalt mit Mittelstreifen, Gehsteige mit Bordstein, Laternen,
        ein Schachtdeckel; die Gehsteige setzen an der Ringstraße aus."""
        b, rng = self.b, self.rng
        f, box = self.frame(0, 0, th)  # lokal +Z = nach außen
        r0, r1 = PLAZA_R - 1, CAMP_WALL_R + 1
        box("Ground", "Sidewalk", (STREET_W, 0.2, r1 - r0), (0, 0.04, (r0 + r1) / 2), ASPHALT, "Asphalt")
        for k in range(int((r1 - r0 - 8) // 10)):
            box("Ground", "RoadDash", (0.4, 0.06, 4), (0, 0.15, r0 + 6 + k * 10), (214, 212, 200), "SmoothPlastic")
        for a, c in ((INNER_R - 2, RING_R - RING_W / 2 - 0.5), (RING_R + RING_W / 2 + 0.5, CAMP_WALL_R - 12)):
            for s in (-1, 1):
                box("Ground", "Sidewalk", (WALK_W, 0.5, c - a), (s * (STREET_W / 2 + WALK_W / 2), 0.25, (a + c) / 2), STONE, "Concrete")
                box("Ground", "Curb", (0.4, 0.55, c - a), (s * (STREET_W / 2 + 0.2), 0.27, (a + c) / 2), (120, 118, 112), "Slate")
        for k, lz in enumerate((46, 78, 94)):
            s = 1 if k % 2 == 0 else -1
            x, z = self._xz(f, s * (STREET_W / 2 + 1.6), lz)
            dx, dz = self._dir(f, -s, 0)
            self.camp_lamp(x, z, dx, dz)
        box("Ground", "Manhole", (2, 0.08, 2), (rng.uniform(-3, 3), 0.14, 48), (60, 60, 62), "DiamondPlate")

    def ring_road(self):
        """Ringstraße zwischen den Häuserringen: Asphalt, Mittelstreifen, Gehsteig außen, Laternen auf der Außenseite."""
        self.arc_pad("Sidewalk", RING_R - RING_W / 2, RING_R + RING_W / 2, 0, 360, ASPHALT, "Asphalt", 0.1, step=5)
        for k in range(48):
            th = 360 * k / 48
            if min(abs((th - g + 180) % 360 - 180) for g in (0, 90, 180, 270)) < 9:
                continue
            x, z, yaw = self.at_center(RING_R, th)
            self.b.box("Ground", "RoadDash", (0.4, 0.06, 3.5), (x, 0.17, z), (214, 212, 200), "SmoothPlastic", angles=(0, yaw + 90, 0))
        self.arc_pad("Sidewalk", RING_R + RING_W / 2, OUTER_R - 0.2, 0, 360, STONE, "Concrete", 0.3, step=5, thickness=0.5)
        self.arc_pad("Sidewalk", INNER_R + HOUSE_D, RING_R - RING_W / 2, 0, 360, STONE, "Concrete", 0.3, step=5, thickness=0.5)
        for k in range(16):
            th = 11.25 + 22.5 * k
            if min(abs((th - g + 180) % 360 - 180) for g in (0, 90, 180, 270)) < 14:
                continue
            x, z = P(OUTER_R - 1.2, th)
            self.camp_lamp(x, z, -x, -z)

    # ---------- Häuser ----------
    def house(self, r_front, th, w, floors, kind, sides=0):
        """Altbau mit der Front bei r_front in Richtung th, Blick zur Mitte. kind: house, shop:<Titel>|<Unterzeile>,
        station:<Schlüssel>, garage, bus, arcade (Ausrüster), rathaus, wheel (Glücksrad). sides: ±1 = diese
        Seitenwand (lokal ±X; -X ist links, wenn man zur Mitte schaut) steht an einer Hauptstraße und bekommt Fenster."""
        x, z, yaw = self.at_center(r_front + HOUSE_D / 2, th)
        key, shop, garage, bus, special = None, None, False, False, None
        if kind.startswith("shop:"):
            title, sub = kind[5:].split("|")
            shop = (title, sub, None)
        elif kind.startswith("station:"):
            key = kind[8:]
            shop = STATIONS[key]
        elif kind == "garage":
            key, shop, garage = "Stand_Vehicles", STATIONS["Stand_Vehicles"], True
        elif kind == "bus":
            key, shop, bus = "Travel", STATIONS["Travel"], True
        elif kind == "arcade":
            shop, special = ("AUSRÜSTER", "SKINS · ANGEBOTE DES TAGES · AN DER THEKE E DRÜCKEN", GOLD), "arcade"
        elif kind == "rathaus":
            shop, special = ("RATHAUS", "LAGEBERICHT · RUHMESWAND · SIEGERPODEST", (214, 206, 186)), "rathaus"
        elif kind == "wheel":
            shop, special = ("GLÜCKSRAD", "TÄGLICH GRATIS DREHEN · E AM PULT", GOLD), "wheel"
        self.townhouse(x, z, yaw, w, HOUSE_D, floors, shop=shop, key=key, garage=garage, bus=bus, special=special, sides=sides)

    def townhouse(self, x, z, yaw, w, d, floors, shop=None, key=None, garage=False, bus=False, special=None, sides=0):
        """Altbau (Front lokal -Z): Putz, Sockel, Gesimse, Fenster mit Rahmen, Sprossen, Bank, Läden und Blumenkästen,
        Satteldach mit Giebeln, Schornstein, Fallrohr; Rückfassade mit Fenstern und Hoftür, auf Wunsch Fenster in einer
        Seitenwand (sides). Erdgeschoss: Laden (Schild, Schaufenster, Ausgabe-Theke in der Tür, Markise), Werkstatt
        (offenes Rolltor), Wohnhaus (Haustür) oder special: offene Halle (arcade = Ausrüster-Vitrinen, rathaus = Laube
        mit Lagebericht und Ruhmeswand, wheel = Glücksrad). key: Punkt in Stands vor der Theke bzw. dem Tor."""
        b, rng = self.b, self.rng
        lighten = self.bm.lighten
        f, box = self.frame(x, z, yaw)
        color = rng.choice(PLASTER)
        roof_c = rng.choice(ROOFS)
        trim = lighten(color, 0.18)
        gf, fh = (15.0 if special == "wheel" else 11.0), 9.0
        top = gf + (floors - 1) * fh
        fz = -d / 2  # Fassade
        frame_c = rng.choice(((236, 232, 222), (236, 232, 222), (96, 74, 56)))
        shutter_c = rng.choice(((70, 92, 72), (96, 72, 54), (72, 84, 100), (120, 60, 50), (60, 96, 110)))
        accent = shop[2] if shop else None
        if special:
            box("Buildings", "HouseBody", (w, top - gf, d), (0, gf + (top - gf) / 2, 0), color, "Plaster")
            self.open_floor(f, box, yaw, w, d, gf, color, trim, special, accent)
        else:
            box("Buildings", "HouseBody", (w, top, d), (0, top / 2, 0), color, "Plaster")
            box("Decor", "Plinth", (w + 0.1, 1.6, 0.3), (0, 0.8, fz - 0.15), STONE_DARK, "Slate")
        for k in range(1, floors):
            box("Decor", "Cornice", (w + 0.2, 0.5, 0.5), (0, gf + (k - 1) * fh, fz - 0.25), trim, "Concrete")
        box("Decor", "Eave", (w + 0.6, 0.8, 1.0), (0, top - 0.2, fz - 0.4), trim, "Concrete")
        # obere Stockwerke: Fenster
        n = max(1, int((w - 1.5) // 5))
        step = w / n
        for k in range(1, floors):
            y0 = gf + (k - 1) * fh
            for i in range(n):
                c = -w / 2 + step * (i + 0.5)
                self.town_window(box, c, y0, fz, frame_c, shutter_c, trim)
        # Erdgeschoss
        if shop:
            title, sub, _ = shop
            b.sign2("StandSign_" + key if key else "ShopSign", (min(w - 2, 16), 1.8, 0.3), f(0, gf - 1.1, fz - 0.35), title, sub,
                    (30, 32, 30), accent or (214, 206, 186), (214, 212, 202), angles=(0, yaw, 0), glow=accent if key else None)
        if garage:
            box("Decor", "GarageOpening", (11, 8.2, 0.3), (0, 4.1, fz - 0.05), (26, 26, 28), "SmoothPlastic")
            box("Decor", "RollDoor", (11.6, 1.6, 1.2), (0, 8.9, fz - 0.6), (150, 152, 150), "CorrodedMetal")
            for s in (-1, 1):
                box("Decor", "GarageFrame", (0.6, 8.6, 0.6), (s * 5.8, 4.3, fz - 0.3), (90, 92, 94), "Metal")
            box("Cover", "TireStack", (3, 3, 3), (w / 2 - 2, 1.5, fz - 2), (26, 26, 26), "Rubber", props={"Shape": "Cylinder"},
                extra=(0, 0, 90))
            box("Cover", "OilDrum", (2, 3, 2), (-w / 2 + 1.8, 1.5, fz - 1.6), (60, 84, 120), "Metal", props={"Shape": "Cylinder"},
                extra=(0, 0, 90))
            for s in (-1, 1):  # Hebebühne mit Auto in der Halle
                box("Decor", "LiftPost", (0.7, 5, 0.7), (s * 3.6, 2.5, 3), (200, 160, 40), "Metal")
            box("Cover", "LiftCar", (4.8, 2.0, 9), (0, 4.6, 3), (130, 60, 50), "Metal")
            box("Decor", "LiftCarCabin", (4.4, 1.6, 4.4), (0, 6.4, 3.4), (110, 50, 42), "Metal")
            box("Decor", "WorkshopLamp", (6, 0.3, 0.5), (0, gf - 1.4, 2), (236, 240, 255), "Neon",
                children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 18, "Brightness": 1.0,
                                                                                     "Color": self.bm.rgb(230, 236, 255)}}])
        elif special:
            pass
        elif shop:
            for s in (-1, 1):  # Schaufenster (beleuchtet)
                sw = min(4.6, w / 2 - 3.6)
                cx = s * (w / 4 + 0.9)
                box("Decor", "ShopFrame", (sw + 0.6, 5.8, 0.25), (cx, 4.6, fz - 0.12), (60, 58, 56), "Metal")
                box("Decor", "ShopGlass", (sw, 5.2, 0.3), (cx, 4.6, fz - 0.16), (54, 66, 74), "Glass")
                box("Decor", "ShopLight", (sw - 0.6, 0.3, 0.2), (cx, 6.9, fz - 0.4), (255, 232, 190), "Neon",
                    props={"CanCollide": False}, children=self.warm_light(10, 0.6))
            box("Decor", "Doorway", (4.4, 7.2, 0.3), (0, 3.6, fz - 0.05), (28, 26, 24), "SmoothPlastic")
            box("Decor", "DoorFrame", (5.2, 0.5, 0.5), (0, 7.4, fz - 0.25), (60, 58, 56), "Metal")
            if key:  # Ausgabe-Theke in der Tür
                box("Stands", "Counter", (5.6, 3.2, 1.4), (0, 1.6, fz - 0.8), (110, 88, 62), "WoodPlanks")
                box("Stands", "CounterTop", (6, 0.3, 1.8), (0, 3.35, fz - 0.8), (80, 64, 46), "Wood")
                box("Stands", "CounterLamp", (1.2, 0.4, 0.8), (0, 7, fz - 0.6), (255, 220, 170), "Neon", children=self.warm_light(16, 0.9))
                self.npc_figure(box, 0, fz + 1.2, jacket=rng.choice(((60, 70, 100), (96, 72, 54), (60, 120, 76), (120, 60, 50))),
                                pants=(40, 42, 48), cap=rng.choice((None, (40, 50, 80), (46, 96, 60))))
            box("Decor", "Awning", (w - 3, 0.25, 3.4), (0, 8.5, fz - 1.7), lighten(accent or (170, 120, 90), -0.3), "Fabric",
                extra=(-14, 0, 0))
            for s in (-1, 1):
                box("Decor", "WallLantern", (0.8, 1.1, 0.8), (s * 3.4, 7.6, fz - 0.6), (255, 226, 180), "Neon",
                    children=self.warm_light(14, 0.8))
        else:
            self.house_door(box, w, fz, n, step, frame_c, trim, rng.choice((-1, 1)) * rng.uniform(0, w / 2 - 4))
        if bus:
            box("Decor", "BusCanopy", (w - 2, 0.3, 4), (0, 8.6, fz - 2), (70, 84, 104), "Metal")
            for s in (-1, 1):
                box("Decor", "CanopyPost", (0.4, 8.6, 0.4), (s * (w / 2 - 1.5), 4.3, fz - 3.8), (60, 62, 64), "Metal")
            box("Cover", "BusBench", (5, 1.2, 1.4), (-w / 4 - 1, 1.1, fz - 1.4), (104, 78, 54), "WoodPlanks")
            box("Decor", "BusStopPole", (0.3, 8, 0.3), (w / 2 - 2.2, 4, fz - 3.6), (150, 152, 150), "Metal")
            box("Decor", "BusStopSign", (2.2, 2.2, 0.15), (w / 2 - 2.2, 7.4, fz - 3.6), (232, 196, 40), "SmoothPlastic")
            box("Decor", "BusStopH", (0.35, 1.4, 0.05), (w / 2 - 2.55, 7.4, fz - 3.7), (40, 110, 60), "SmoothPlastic")
            box("Decor", "BusStopH", (0.35, 1.4, 0.05), (w / 2 - 1.85, 7.4, fz - 3.7), (40, 110, 60), "SmoothPlastic")
            box("Decor", "BusStopH", (0.7, 0.3, 0.05), (w / 2 - 2.2, 7.4, fz - 3.7), (40, 110, 60), "SmoothPlastic")
        if key:
            b.add("Stands", key, (2, 2, 2), f(0, 2.5, fz - 4), (200, 200, 200), "SmoothPlastic", angles=(0, yaw, 0),
                  props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
        # Rückfassade (zur Ringstraße bzw. zum Hof): Gesimse, Fenster, Hoftür
        fb, boxb = self.frame(x, z, yaw + 180)
        boxb("Decor", "Plinth", (w + 0.1, 1.6, 0.3), (0, 0.8, fz - 0.15), STONE_DARK, "Slate")
        for k in range(1, floors):
            boxb("Decor", "Cornice", (w + 0.2, 0.5, 0.5), (0, gf + (k - 1) * fh, fz - 0.25), trim, "Concrete")
            y0 = gf + (k - 1) * fh
            for i in range(n):
                self.town_window(boxb, -w / 2 + step * (i + 0.5), y0, fz, frame_c, shutter_c, trim)
        boxb("Decor", "Eave", (w + 0.6, 0.8, 1.0), (0, top - 0.2, fz - 0.4), trim, "Concrete")
        self.house_door(boxb, w, fz, n, step, frame_c, trim, 0 if n % 2 else -step / 2, back=True)
        # Seitenwand an einer Hauptstraße: Fenster
        if sides:
            self.side_windows(box, sides, w, d, floors, gf, fh, frame_c, shutter_c, trim)
        # Dach: zwei Flächen, Giebel an den Seiten, First, Schornstein
        rise = d * 0.34
        slope = math.degrees(math.atan2(rise, d / 2))
        for s in (-1, 1):
            box("Buildings", "Roof", (math.hypot(d / 2, rise) + 1.2, 0.5, w + 0.8), (0, top + rise / 2, s * d / 4), roof_c,
                "RoofShingles", extra=(0, 90, s * slope))
        for s in (-1, 1):
            for half in (-1, 1):  # Giebel aus zwei Keilen (hohe Seite zur Mitte)
                box("Buildings", "Gable", (0.6, rise, d / 2), (s * (w / 2 - 0.3), top + rise / 2, half * d / 4), color, "Plaster",
                    extra=(0, 0 if half < 0 else 180, 0), cls="WedgePart")
        box("Decor", "Ridge", (w + 0.8, 0.5, 0.9), (0, top + rise + 0.1, 0), lighten(roof_c, -0.2), "Slate")
        if special == "rathaus":
            self.clock_tower(box, top + rise, fz)
        elif rng.random() < 0.85:
            cx = rng.uniform(-w / 3, w / 3)
            cz = rng.uniform(0.5, 2.5)
            box("Decor", "Chimney", (1.8, 4.5, 1.8), (cx, top + rise * 0.75 + 1.6, cz), (124, 84, 66), "Brick")
            box("Decor", "ChimneyCap", (2.2, 0.4, 2.2), (cx, top + rise * 0.75 + 4, cz), (90, 88, 86), "Concrete")
        if rng.random() < 0.3 and floors > 1 and not special:  # Gaube
            gx = rng.uniform(-w / 3, w / 3)
            box("Buildings", "Dormer", (2.8, 2.6, 2.6), (gx, top + 1.3, -d / 4 + 0.4), color, "Plaster")
            box("Decor", "DormerWindow", (1.8, 1.6, 0.2), (gx, top + 1.3, -d / 4 - 0.95), (54, 66, 74), "Glass")
            box("Buildings", "DormerRoof", (3.4, 0.4, 3.0), (gx, top + 2.75, -d / 4 + 0.4), lighten(roof_c, -0.1), "RoofShingles")
        self.town_grime(f, yaw, box, w, top, fz, n, step, gf, fh, floors, shop is not None or garage)
        side = rng.choice((-1, 1))
        box("Decor", "Downpipe", (0.4, top, 0.4), (side * (w / 2 - 0.5), top / 2, fz - 0.35), (92, 96, 100), "Metal")
        boxb("Decor", "Downpipe", (0.4, top, 0.4), (side * (w / 2 - 0.5), top / 2, fz - 0.35), (92, 96, 100), "Metal")
        if rng.random() < 0.12:
            box("Decor", "Dish", (1.6, 1.6, 0.3), (-side * (w / 2 - 2), top - 3, fz - 0.4), (200, 200, 196), "Metal",
                extra=(15, 20, 0))

    def house_door(self, box, w, fz, n, step, frame_c, trim, dx, back=False):
        """Haustür (oder Hoftür hinten) mit Stufe und Fenstern daneben im Erdgeschoss."""
        rng = self.rng
        box("Decor", "HouseDoor", (3.4, 7, 0.3), (dx, 3.5, fz - 0.1), (84, 62, 46), "WoodPlanks")
        box("Decor", "DoorStep", (4.4, 0.5, 1.4), (dx, 0.25, fz - 0.7), STONE, "Concrete")
        box("Decor", "DoorLamp", (0.7, 0.9, 0.7), (dx + 2.4, 7.0, fz - 0.5), (255, 226, 180), "Neon", children=self.warm_light(12, 0.6))
        for i in range(n):
            c = -w / 2 + step * (i + 0.5)
            if abs(c - dx) < 4:
                continue
            box("Decor", "GroundWindow", (2.8, 3.8, 0.3), (c, 5, fz - 0.14), (54, 66, 74), "Glass")
            box("Decor", "WindowFrame", (3.3, 4.3, 0.2), (c, 5, fz - 0.1), frame_c, "WoodPlanks")
            box("Decor", "Sill", (3.4, 0.3, 0.7), (c, 2.9, fz - 0.35), trim, "Concrete")
            if not back and rng.random() < 0.15:
                for j in range(3):  # vernagelt
                    box("Decor", "Board", (3.4, 0.7, 0.2), (c, 3.7 + j * 1.3, fz - 0.32), (128, 102, 72), "WoodPlanks",
                        extra=(0, 0, rng.uniform(-10, 10)))

    def side_windows(self, box, side, w, d, floors, gf, fh, frame_c, shutter_c, trim):
        """Fenster in der Seitenwand side (±1 = lokal ±X), alle Stockwerke."""
        sx = side * (w / 2)
        m = max(1, int((d - 2) // 5))
        zstep = d / m
        rot = (0, -90 * side, 0)
        for k in range(floors):
            y0 = gf + (k - 1) * fh if k else 0
            for i in range(m):
                c = -d / 2 + zstep * (i + 0.5)
                if k == 0:
                    box("Decor", "GroundWindow", (2.8, 3.8, 0.3), (sx + side * 0.14, 5, c), (54, 66, 74), "Glass", extra=rot)
                    box("Decor", "WindowFrame", (3.3, 4.3, 0.2), (sx + side * 0.1, 5, c), frame_c, "WoodPlanks", extra=rot)
                    box("Decor", "Sill", (3.4, 0.3, 0.7), (sx + side * 0.35, 2.9, c), trim, "Concrete", extra=rot)
                else:
                    box("Decor", "WindowFrame", (2.9, 4.8, 0.25), (sx + side * 0.12, y0 + 4.8, c), frame_c, "WoodPlanks", extra=rot)
                    box("Decor", "WindowGlass", (2.3, 4.2, 0.3), (sx + side * 0.16, y0 + 4.8, c), (46, 54, 62), "Glass", extra=rot)
                    box("Decor", "Mullion", (0.18, 4.2, 0.34), (sx + side * 0.18, y0 + 4.8, c), frame_c, "WoodPlanks", extra=rot)
                    box("Decor", "Sill", (3.4, 0.3, 0.7), (sx + side * 0.35, y0 + 2.25, c), trim, "Concrete", extra=rot)
                    if self.rng.random() < 0.6:
                        for s in (-1, 1):
                            box("Decor", "Shutter", (1.3, 4.6, 0.2), (sx + side * 0.3, y0 + 4.8, c + s * 2.15), shutter_c, "WoodPlanks",
                                extra=rot)
            box("Decor", "Cornice", (0.5, 0.5, d + 0.2), (sx + side * 0.25, y0 + (fh if k else gf), 0), trim, "Concrete")

    def open_floor(self, f, box, yaw, w, d, gf, color, trim, special, accent):
        """Offenes Erdgeschoss (Steinboden, Rückwand, Seitenwände, Pfeiler mit Balken vorn, Deckenlicht) für
        arcade (AUSRÜSTER: drei Vitrinen mit ShopDisplay1-3 und ShopPlaque1-3, Theke = ShopCounter),
        rathaus (RATHAUSLAUBE: Lagebericht = MissionBoard an der Rückwand, die vier Bestenlisten Leaderboard_* an den
        Seitenwänden, Bank) und wheel (GLÜCKSRAD: Rad an der Rückwand = WheelSpot, Pult = WheelConsole, Tafel WheelBoard,
        Glühbirnen). Die gesuchten Teile liegen in der Gruppe Zentrale."""
        bm = self.bm
        fz = -d / 2
        accent = accent or (120, 185, 235)
        box("Buildings", "ArcadeFloor", (w, 0.4, d), (0, 0.2, 0), (112, 106, 98), "Marble")
        box("Buildings", "ArcadeBack", (w, gf, 0.6), (0, gf / 2, d / 2 - 0.3), self.bm.lighten(color, -0.1), "Plaster")
        for s in (-1, 1):
            box("Buildings", "ArcadeSide", (0.6, gf, d), (s * (w / 2 - 0.3), gf / 2, 0), self.bm.lighten(color, -0.1), "Plaster")
        pillars = (-w / 2 + 0.8, -w / 6, w / 6, w / 2 - 0.8)
        for px in pillars:
            box("Buildings", "ArcadePillar", (1.4, gf, 1.4), (px, gf / 2, fz + 0.7), trim, "Concrete")
            box("Decor", "ArcadePillarCap", (1.8, 0.5, 1.8), (px, gf - 1.0, fz + 0.7), trim, "Concrete")
        if special == "rathaus":  # Bögen angedeutet: Kämpfer-Keile zwischen den Pfeilern
            for px in pillars:
                for s in (-1, 1):
                    box("Decor", "ArchHaunch", (2.2, 1.6, 1.3), (px + s * 1.6, gf - 2.4, fz + 0.7), trim, "Concrete", extra=(0, 0, s * 35))
        box("Buildings", "ArcadeBeam", (w, 1.6, 1.6), (0, gf - 0.8, fz + 0.8), trim, "Concrete")
        box("Decor", "ArcadeCeilingLight", (w - 4, 0.2, 0.6), (0, gf - 1.7, 1), (255, 240, 220), "Neon",
            children=self.warm_light(20, 1.0))
        if special == "arcade":
            for k, vx in enumerate((-7, 0, 7), start=1):
                vz = 2.4
                box("Decor", "VitrineBase", (4, 2.4, 4), (vx, 1.6, vz), (54, 44, 36), "Wood")
                box("Decor", "VitrineBaseStrip", (4.1, 0.25, 4.1), (vx, 2.7, vz), accent, "Neon", props={"Transparency": 0.2})
                box("Decor", "VitrineGlass", (3.6, 4.2, 3.6), (vx, 4.9, vz), (200, 225, 240), "Glass", props={"Transparency": 0.8})
                box("Decor", "VitrineCap", (4, 0.4, 4), (vx, 7.2, vz), (54, 44, 36), "Wood")
                box("Decor", "VitrineLight", (2.4, 0.1, 2.4), (vx, 6.95, vz), (255, 248, 235), "Neon",
                    children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                        "Face": "Bottom", "Range": 10, "Brightness": 1.1, "Angle": 70, "Color": bm.rgb(255, 245, 230)}}])
                self.b.add("Zentrale", "ShopDisplay" + str(k), (1, 1, 1), f(vx, 4.8, vz), accent, "SmoothPlastic",
                           angles=(0, yaw, 0), props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
                self.b.holo_panel("Zentrale", "ShopPlaque" + str(k), (3.6, 1.4, 0.2), f(vx, 1.5, vz - 2.15), angles=(0, yaw, 0))
            self.b.box("Zentrale", "ShopCounter", (10, 3.4, 2.2), f(2, 2.1, fz + 2.6), (110, 88, 62), "WoodPlanks", angles=(0, yaw, 0))
            box("Decor", "ShopCounterTop", (10.4, 0.3, 2.6), (2, 3.9, fz + 2.6), (60, 48, 36), "Wood")
            box("Decor", "ShopCounterStrip", (10, 0.25, 0.15), (2, 3.2, fz + 1.45), accent, "Neon", props={"Transparency": 0.2})
            box("Decor", "ShopTerminal", (2.4, 1.6, 0.3), (5, 4.8, fz + 2.6), (22, 25, 30), "SmoothPlastic", extra=(-15, 180, 0))
            self.npc_figure(box, 0, fz + 4.4, jacket=(50, 60, 90), pants=(40, 42, 48), cap=(30, 40, 70))
            box("Decor", "Awning", (w - 2, 0.25, 3.6), (0, gf - 2.2, fz - 1.8), (176, 60, 40), "Fabric", extra=(-14, 0, 0))
            for k in range(6):
                box("Decor", "AwningStripe", (1.4, 0.27, 3.6), (-w / 2 + 2.4 + k * (w - 4.8) / 5, gf - 2.19, fz - 1.8), (230, 220, 196),
                    "Fabric", extra=(-14, 0, 0))
        elif special == "rathaus":
            self.showcase("MissionBoard", 10, 5.6, *self._xz(f, 0, d / 2 - 1.0), 5.6, yaw)
            self.b.sign2("NoticeTitle", (10, 1.3, 0.25), f(0, 9.3, d / 2 - 0.95), "LAGEBERICHT", "SPIELER · BLUTMOND · STURMNACHT",
                         (54, 48, 40), (226, 190, 120), (200, 190, 170), angles=(0, yaw, 0))
            boards = (("Zombies", "ZOMBIES", (200, 166, 92), -1, -2.5), ("Kills", "KILLS", (206, 70, 58), -1, 4.5),
                      ("Level", "LEVEL", (96, 164, 214), 1, -2.5), ("Missions", "AUFTRÄGE", (112, 178, 112), 1, 4.5))
            for board, title, bcolor, side, lz in boards:
                sx = side * (w / 2 - 1.1)
                self.showcase("Leaderboard_" + board, 6, 6, *self._xz(f, sx, lz), 5.4, yaw + 90 * side)
                self.b.sign2("BoardsTitle", (6, 1.1, 0.25), f(sx + side * 0.05, 9.3, lz), "RUHMESWAND · " + title, "GLOBALE TOP 10",
                             (30, 32, 36), bcolor, (236, 239, 243), angles=(0, yaw + 90 * side, 0))
            box("Cover", "LaubeBench", (6, 0.5, 1.4), (0, 1.5, d / 2 - 2.4), (110, 84, 58), "WoodPlanks")
            for s in (-1, 1):
                box("Decor", "LaubeBenchLeg", (0.4, 1.3, 1.2), (s * 2.6, 0.65, d / 2 - 2.4), DARK, "Metal")
                box("Decor", "BannerPole", (0.3, 0.3, 5), (s * 7.5, gf + 6.2, fz - 2.2), (60, 58, 56), "Metal", extra=(-35, 0, 0))
                box("Decor", "Banner", (3, 6, 0.15), (s * 7.5, gf + 3.4, fz - 3.6), (176, 60, 40), "Fabric", extra=(-35, 0, 0),
                    props={"CanCollide": False})
                box("Decor", "BannerEmblem", (1.6, 1.6, 0.2), (s * 7.5, gf + 4.0, fz - 3.75), (236, 170, 70), "Fabric", extra=(-35, 0, 45),
                    props={"CanCollide": False})
        elif special == "wheel":
            red, cream = (176, 60, 40), (230, 220, 196)
            for k in range(8):  # Rückwand aus Brettern in Rot und Creme hinter dem Rad
                box("Decor", "BoothBackRib", (w / 8, gf - 0.8, 0.25), (-w / 2 + w / 16 + k * w / 8, gf / 2, d / 2 - 0.72),
                    red if k % 2 == 0 else cream, "WoodPlanks")
            self.b.add("Zentrale", "WheelSpot", (1, 1, 1), f(0, 7.4, d / 2 - 1.3), GOLD, "SmoothPlastic", angles=(0, yaw, 0),
                       props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
            self.b.box("Zentrale", "WheelConsole", (5.6, 2.2, 1.6), f(0, 1.7, fz + 4.5), (36, 39, 46), "Metal", angles=(0, yaw, 0))
            box("Decor", "WheelConsoleStrip", (5.7, 0.2, 1.7), (0, 2.7, fz + 4.5), GOLD, "Neon", props={"Transparency": 0.2})
            self.b.holo_panel("Zentrale", "WheelBoard", (5.2, 1.9, 0.15), f(0, 3.35, fz + 4.3), angles=bm.yaw_tilt(yaw, 35))
            for k in range(int(w // 1.2)):
                box("Decor", "MarqueeBulb", (0.45, 0.45, 0.45), (-w / 2 + 0.9 + k * 1.2, gf - 1.9, fz + 0.1), (255, 226, 150), "SmoothPlastic",
                    props={"Shape": "Ball", "CanCollide": False})
            for s in (-1, 1):
                box("Decor", "BoothLamp", (1.0, 0.6, 1.0), (s * (w / 2 - 3), gf - 1.9, fz + 3), (255, 240, 210), "Neon",
                    children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 18, "Brightness": 1.2,
                                                                                         "Color": bm.rgb(255, 236, 200)}}])
            stripe = (w + 2) / 11
            for k in range(11):
                box("Decor", "Awning", (stripe + 0.05, 0.25, 3.6), (-(w + 2) / 2 + stripe * (k + 0.5), gf - 2.2, fz - 1.8),
                    red if k % 2 == 0 else cream, "Fabric", extra=(-14, 0, 0))
            self.b.floor_text("WheelFloorLabel", (8, 0.1, 2), f(0, 0.45, fz + 2.4), "E AM PULT", GOLD, yaw=yaw + 180)

    def clock_tower(self, box, roof_top, fz):
        """Uhrturm des Rathauses: Turm aus dem Dach, Uhr zum Platz, Spitzdach aus Keilen, Glocke, Wetterfahne."""
        T, H = 7, 10
        y0 = roof_top - 3
        box("Buildings", "Tower", (T, H, T), (0, y0 + H / 2, 0), (196, 186, 166), "Plaster")
        box("Decor", "TowerCornice", (T + 0.6, 0.5, T + 0.6), (0, y0 + H - 0.3, 0), (214, 206, 186), "Concrete")
        box("Decor", "ClockFace", (0.3, 4.2, 4.2), (0, y0 + H / 2 + 0.8, -T / 2 - 0.1), (236, 232, 222), "SmoothPlastic",
            extra=(0, 90, 0), props={"Shape": "Cylinder"})
        box("Decor", "ClockRing", (0.3, 4.6, 4.6), (0, y0 + H / 2 + 0.8, -T / 2 - 0.05), (60, 58, 56), "Metal",
            extra=(0, 90, 0), props={"Shape": "Cylinder"})
        box("Decor", "ClockHand", (0.25, 1.7, 0.1), (0, y0 + H / 2 + 1.5, -T / 2 - 0.3), (30, 30, 32), "Metal")
        box("Decor", "ClockHand", (1.3, 0.25, 0.1), (0.55, y0 + H / 2 + 0.8, -T / 2 - 0.3), (30, 30, 32), "Metal")
        for half in (-1, 1):
            box("Buildings", "TowerRoof", (T + 0.8, 4.5, T / 2 + 0.4), (0, y0 + H + 2.25, half * T / 4), (84, 84, 90), "Slate",
                extra=(0, 0 if half < 0 else 180, 0), cls="WedgePart")
        box("Decor", "TowerSpire", (0.4, 4, 0.4), (0, y0 + H + 6.4, 0), (60, 58, 56), "Metal")
        box("Decor", "WeatherVane", (2.2, 0.8, 0.15), (0, y0 + H + 8.2, 0), (176, 128, 64), "Metal", extra=(0, 30, 0))
        box("Decor", "TowerBell", (1.2, 1.2, 1.2), (0, y0 + H - 2.2, -T / 2 + 0.2), (176, 128, 64), "Metal")

    def town_grime(self, f, yaw, box, w, top, fz, n, step, gf, fh, floors, shop):
        """Etwas Patina, nicht kaputt: Schmutz über dem Sockel, eine Laufspur, selten abgeplatzter Putz."""
        rng = self.rng
        thin = {"CanCollide": False, "CanQuery": False}
        box("Decor", "Dirt", (w + 0.1, 1.4, 0.1), (0, 2.3, fz - 0.31), (64, 56, 46), "SmoothPlastic",
            props=dict(thin, Transparency=0.65))
        if rng.random() < 0.7:
            c = -w / 2 + step * (rng.randrange(n) + 0.5)
            k = rng.randint(1, max(1, floors - 1))
            length = rng.uniform(2.5, 5)
            box("Decor", "Streak", (rng.uniform(0.6, 1.2), length, 0.1), (c + rng.uniform(-0.8, 0.8), gf + (k - 1) * fh + 2.1 - length / 2,
                fz - 0.29), (58, 54, 48), "SmoothPlastic", props=dict(thin, Transparency=0.7))
        if rng.random() < 0.35:
            box("Decor", "PlasterGone", (rng.uniform(1.4, 2.8), rng.uniform(1.0, 2.0), 0.12),
                (rng.uniform(-w / 2 + 2, w / 2 - 2), rng.uniform(gf - 3, top - 2), fz - 0.3), (128, 84, 66), "Brick", props=thin)
        if not shop and rng.random() < 0.25:
            self.graffiti(self.b, rng.choice(("WIR LEBEN NOCH", "PHOENIX", "HILFE KOMMT")),
                          f(rng.uniform(-w / 4, w / 4), 3.2, fz - 0.4), (min(8, w - 4), 1.8, 0.05), yaw)

    def town_window(self, box, c, y0, fz, frame_c, shutter_c, trim):
        """Fenster im Obergeschoss: Rahmen, Glas, Sprossen, Bank; oft Läden, manchmal ein Blumenkasten, selten vernagelt."""
        rng = self.rng
        box("Decor", "WindowFrame", (2.9, 4.8, 0.25), (c, y0 + 4.8, fz - 0.12), frame_c, "WoodPlanks")
        lit = rng.random() < 0.35
        box("Decor", "WindowGlass", (2.3, 4.2, 0.3), (c, y0 + 4.8, fz - 0.16), (255, 226, 170) if lit else (46, 54, 62),
            "Neon" if lit else "Glass", children=self.warm_light(10, 0.5) if lit else None)
        r = rng.random()
        if r < 0.06:
            for j in range(3):
                box("Decor", "Board", (3.4, 0.7, 0.2), (c, y0 + 3.4 + j * 1.4, fz - 0.36), (128, 102, 72), "WoodPlanks",
                    extra=(0, 0, rng.uniform(-12, 12)))
        else:
            box("Decor", "Mullion", (0.18, 4.2, 0.34), (c, y0 + 4.8, fz - 0.18), frame_c, "WoodPlanks")
            box("Decor", "Transom", (2.3, 0.18, 0.34), (c, y0 + 5.6, fz - 0.18), frame_c, "WoodPlanks")
        box("Decor", "Sill", (3.4, 0.3, 0.7), (c, y0 + 2.25, fz - 0.35), trim, "Concrete")
        if r > 0.45:
            for s in (-1, 1):
                box("Decor", "Shutter", (1.3, 4.6, 0.2), (c + s * 2.15, y0 + 4.8, fz - 0.3), shutter_c, "WoodPlanks")
        if 0.15 < r < 0.45:
            box("Decor", "FlowerBox", (2.6, 0.7, 0.7), (c, y0 + 2.7, fz - 0.55), (110, 80, 56), "WoodPlanks")
            for k in range(3):
                box("Decor", "Flowers", (0.7, 0.6, 0.6), (c - 0.8 + k * 0.8, y0 + 3.25, fz - 0.55),
                    rng.choice(((200, 60, 70), (230, 170, 60), (220, 100, 140), (240, 240, 230))), "Grass",
                    props={"Shape": "Ball", "CanCollide": False})

    # ---------- Häuserringe ----------
    def inner_ring(self):
        """Acht Altbauten um den Platz (je Seite ein breites Haus nach der Straße und ein schmales vor der nächsten),
        Fronten bei INNER_R. Die vier Stationen liegen in den schmalen Häusern, 90° auseinander."""
        a = self._inner_a()
        h1, h2 = half_angle(INNER_R, W_WIDE), half_angle(INNER_R, W_NARROW)
        plan = {0: ("arcade", 3, "station:Stand_Weapons", 2), 90: ("shop:CAFÉ ZENTRAL|KAFFEE · EINTOPF", 3, "station:Stand_Items", 2),
                180: ("rathaus", 3, "station:Stand_Market", 2), 270: ("wheel", 2, "station:Stash", 3)}
        for base, (kind1, floors1, kind2, floors2) in plan.items():
            self.house(INNER_R, base + a + h1, W_WIDE, floors1, kind1, sides=-1)
            self.house(INNER_R, base + 90 - a - h2, W_NARROW, floors2, kind2, sides=1)
            # Hofmauer mit Tor schließt den Keil zwischen den Rückseiten der beiden Häuser
            x, z, yaw = self.at_center(INNER_R + HOUSE_D - 0.8, base + a + 2 * h1 + (90 - 2 * a - 2 * h1 - 2 * h2) / 2)
            f, box = self.frame(x, z, yaw)
            box("Buildings", "YardWall", (10, 6, 0.8), (0, 3, 0), (134, 88, 68), "Brick")
            box("Decor", "YardWallCap", (10.2, 0.4, 1.1), (0, 6.2, 0), STONE_DARK, "Slate")
            box("Decor", "YardGate", (3.4, 5, 0.3), (0, 2.5, 0.45), (84, 62, 46), "WoodPlanks")

    def outer_ring(self):
        """Altbauten an der Ringstraße (Fronten bei OUTER_R), je Viertel vier Häuser mit einer Gasse in der Mitte;
        im Südwesten die MARKTHALLE statt der mittleren Häuser. Stationen 90° auseinander, Kits im Nordosten."""
        a = math.degrees(math.asin(LINE / OUTER_R))
        h = half_angle(OUTER_R, W_OUTER)
        slots = (a + h, a + 3 * h, 90 - a - 3 * h, 90 - a - h)   # vier Häuser, Gasse in der Mitte (um base + 45)
        plan = {
            0: (("station:Kits", 2), ("shop:GARKÜCHE|HEUTE: EINTOPF", 2), ("shop:STOFFE|MÄNTEL · DECKEN", 3),
                ("shop:FUNK & BATTERIEN|FREQUENZ 104.5", 2)),
            90: (("garage", 2), ("shop:ERSATZTEILE|REIFEN · ÖL · BATTERIEN", 2), ("shop:HOTEL ZUR POST|ZIMMER FREI", 3), ("house", 2)),
            180: (("bus", 2), None, None, ("shop:SPEDITION|FRACHT · ZOLL", 2)),
            270: (("station:Hideout", 2), ("house", 3), ("shop:SCHULE|NOTUNTERKUNFT", 2), ("house", 2)),
        }
        for base, houses in plan.items():
            for k, (th_off, spec) in enumerate(zip(slots, houses)):
                if spec:
                    self.house(OUTER_R, base + th_off, W_OUTER, spec[1], spec[0], sides=-1 if k == 0 else (1 if k == 3 else 0))
        self.market_hall(*self.at_center(OUTER_R + 11, 225))
        self.parked_bus(-(STREET_W / 2 - 3.7), -(OUTER_R + 13))

    def market_hall(self, x, z, yaw):
        """MARKTHALLE: Backsteinhalle mit Torbogen zur Ringstraße; im Tor das Kraftfeld (GateGlow) und davor das
        Bodenfeld Portal_Market (Teleport in die Markt-Welt), darüber die Spielerzahl (GateCount_Market); Plakat,
        Laternen, Bodenschrift, Rundfenster, Satteldach mit Giebeln."""
        bm = self.bm

        def build(pb):
            W, D, H = 30, 22, 14
            brick, stone = (134, 88, 68), (190, 182, 166)
            rap = (86, 214, 170)
            fz = -D / 2
            gw, gh = 12, 11
            pb.box("Buildings", "HallBody", (W, H, D - 1), (0, H / 2, 0.5), brick, "Brick")
            for s in (-1, 1):  # Vorderwand links und rechts vom Tor
                pb.box("Buildings", "HallFront", ((W - gw) / 2, H, 1), (s * (gw / 2 + (W - gw) / 4), H / 2, fz + 0.5), brick, "Brick")
            pb.box("Buildings", "HallLintel", (gw + 0.2, H - gh, 1), (0, gh + (H - gh) / 2, fz + 0.5), brick, "Brick")
            pb.box("Decor", "HallPlinth", (W + 0.2, 1.6, 0.3), (0, 0.8, fz - 0.15), STONE_DARK, "Slate")
            for s in (-1, 1):
                pb.box("Decor", "GatePilaster", (2, gh + 2, 1.4), (s * (gw / 2 + 1), (gh + 2) / 2, fz - 0.2), stone, "Concrete")
                pb.box("Decor", "GatePilasterCap", (2.6, 0.6, 1.8), (s * (gw / 2 + 1), gh + 2.3, fz - 0.3), stone, "Concrete")
                pb.box("Decor", "GateLantern", (1, 1.4, 1), (s * (gw / 2 + 1), gh - 1, fz - 1.2), (255, 226, 180), "Neon",
                       children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 20, "Brightness": 1.1,
                                                                                            "Color": bm.rgb(255, 220, 170)}}])
                pb.box("Decor", "GateStrip", (0.4, gh - 0.5, 0.3), (s * (gw / 2 - 0.3), gh / 2, fz + 0.2), rap, "Neon")
            pb.box("Decor", "GateArch", (gw + 2.4, 1.6, 1.4), (0, gh + 0.8, fz - 0.2), stone, "Concrete")
            pb.box("Decor", "GateGlow", (gw - 0.8, gh - 0.4, 0.3), (0, gh / 2, fz + 1.0), rap, "ForceField",
                   props={"Transparency": 0.25, "CanCollide": False},
                   children=[{"Name": "Light", "ClassName": "PointLight",
                              "Properties": {"Range": 18, "Brightness": 0.9, "Color": bm.rgb(*rap)}}])
            pb.box("Decor", "GateBack", (gw, gh, 0.4), (0, gh / 2, fz + 3.2), (20, 22, 26), "SmoothPlastic")
            pb.add("Portals", "Portal_Market", (gw - 1, 0.3, 6), (0, 0.4, fz - 1.2), rap, "Neon",
                   props={"CanCollide": False, "Transparency": 0.45})
            pb.box("Decor", "GateRamp", (gw + 4, 0.3, 9), (0, 0.2, fz - 3.5), (96, 92, 86), "Cobblestone")
            pb.floor_text("FloorLabel_Market", (10, 0.1, 2.6), (0, 0.4, fz - 6.5), "MARKT", rap, yaw=180)
            pb.holo_panel("Decor", "GateCount_Market", (9, 1.6, 0.3), (0, gh + 3.4, fz - 0.6))
            pb.sign2("Sign_Market", (18, 4, 0.4), (0, H + 2.4, fz + 0.3), "MARKTHALLE", "STÄNDE · HANDEL · RAP", (30, 32, 36), rap,
                     (236, 239, 243), glow=rap)
            for s in (-1, 1):
                pb.box("Decor", "SignPost", (0.4, 2.4, 0.4), (s * 8, H + 1.2, fz + 0.6), DARK, "Metal")
                pb.box("Decor", "RoundWindow", (0.3, 3.2, 3.2), (s * 10, H - 3.6, fz - 0.15), (54, 66, 74), "Glass",
                       angles=(0, 90, 0), props={"Shape": "Cylinder"})
                pb.box("Decor", "RoundWindowRing", (0.3, 3.7, 3.7), (s * 10, H - 3.6, fz - 0.1), stone, "Concrete",
                       angles=(0, 90, 0), props={"Shape": "Cylinder"})
                for lz in (-5, 0, 5):  # Sprossenfenster in den Seitenwänden
                    pb.box("Decor", "WindowGlass", (0.3, 4, 2.4), (s * (W / 2 + 0.1), 7.5, lz), (54, 66, 74), "Glass")
                    pb.box("Decor", "WindowFrame", (0.2, 4.5, 2.9), (s * (W / 2 + 0.05), 7.5, lz), (236, 232, 222), "WoodPlanks")
            pb.box("Decor", "MarketPoster", (6, 4.5, 0.2), (-8.5, 5.2, fz - 0.3), (214, 206, 186), "SmoothPlastic")
            pb.sign2("MarketPosterText", (5.6, 2.6, 0.1), (-8.5, 5.6, fz - 0.45), "MARKT", "STÄNDE · HANDEL · RAP", (214, 206, 186),
                     (60, 58, 56), (90, 88, 86))
            pb.box("Decor", "MarketPoster", (6, 4.5, 0.2), (8.5, 5.2, fz - 0.3), (214, 206, 186), "SmoothPlastic")
            pb.sign2("MarketPosterText", (5.6, 2.6, 0.1), (8.5, 5.6, fz - 0.45), "TAUSCHEN", "JEDEN TAG · JEDE NACHT", (214, 206, 186),
                     (60, 58, 56), (90, 88, 86))
            # Dach: Satteldach, First entlang X (wie bei den Altbauten), Giebel an den Schmalseiten aus Keilpaaren
            rise = 7
            dd = D - 1
            slope = math.degrees(math.atan2(rise, dd / 2))
            for s in (-1, 1):
                pb.box("Buildings", "Roof", (math.hypot(dd / 2, rise) + 1.2, 0.6, W + 1.2), (0, H + rise / 2, 0.5 + s * dd / 4),
                       (84, 84, 90), "Slate", angles=(0, 90, s * slope))
            for s in (-1, 1):
                for half in (-1, 1):
                    pb.box("Buildings", "Gable", (0.8, rise, dd / 2), (s * (W / 2 - 0.4), H + rise / 2, 0.5 + half * dd / 4), brick, "Brick",
                           angles=(0, 0 if half < 0 else 180, 0), cls="WedgePart")
            pb.box("Decor", "Ridge", (W + 1.2, 0.5, 0.9), (0, H + rise + 0.1, 0.5), (60, 60, 64), "Slate")
            for sx in (-1, 1):
                pb.box("Decor", "RoofVent", (1.6, 2.4, 1.6), (sx * 9, H + rise * 0.6 + 1.2, 3), (90, 88, 86), "Metal")
        self._feature(build, x, z, yaw)

    def parked_bus(self, x, z):
        """Linienbus am Bordstein der Südstraße vor dem Busbahnhof (Nase nach Süden) mit Fenstern, Zielanzeige, Rädern."""
        f, box = self.frame(x, z, 180)
        col = (196, 176, 70)
        box("Cover", "BusBody", (7.4, 7.4, 24), (0, 4.6, 0), col, "Metal")
        box("Decor", "BusWindows", (7.5, 2.4, 21), (0, 6, 0.5), (40, 52, 60), "Glass")
        box("Decor", "BusStripe", (7.5, 0.6, 24.1), (0, 3.6, 0), (60, 62, 66), "SmoothPlastic")
        box("Decor", "BusDestination", (5, 1, 0.2), (0, 7.6, -12.05), (255, 170, 60), "Neon")
        for lz in (-8, 8):
            for s in (-1, 1):
                box("Decor", "BusWheel", (1, 2.4, 2.4), (s * 3.6, 1.2, lz), (26, 26, 26), "Rubber", props={"Shape": "Cylinder"})

    # ---------- Hinterhöfe ----------
    def yard_pad(self, base, color, mat, alleys=((45, 4.6),)):
        """Boden eines Hinterhofs: Ring zwischen äußerem Häuserring und Mauer, von Straße zu Straße; Gassen (Winkel ab
        base, halbe Breite in Grad) von der Ringstraße in den Hof."""
        a = math.degrees(math.asin((LINE + 1.5) / ((YARD_R0 + YARD_R1) / 2)))
        self.arc_pad("YardGround", YARD_R0, YARD_R1, base + a, base + 90 - a, color, mat, 0.08, step=6)
        for th, half in alleys:
            self.arc_pad("Sidewalk", OUTER_R - 0.5, YARD_R0 + 1, base + th - half, base + th + half, GRAVEL, "Pebble", 0.14, step=5)

    def lane_light(self, th, r0, r1, step=14):
        """Lichterketten über einer Gasse in Richtung th von r0 bis r1."""
        for r in range(int(r0), int(r1), step):
            x, z = P(r, th)
            ox, oz = P(5.5, th + 90)
            for d in (-1, 1):
                self.b.box("Decor", "LightPole", (0.4, 9, 0.4), (x + d * ox, 4.5, z + d * oz), PLANK_DARK, "Wood")
            self.string_lights((x - ox, z - oz), (x + ox, z + oz), 8.6)

    def shed(self, x, z, yaw):
        """Holzschuppen (Pultdach) mit Holzstapel daneben – Hinterhof-Inventar."""
        f, box = self.frame(x, z, yaw)
        box("Buildings", "Shed", (8, 5.5, 6), (0, 2.75, 0), (110, 92, 70), "WoodPlanks")
        box("Buildings", "ShedRoof", (8.8, 0.3, 7), (0, 5.8, 0), (74, 74, 80), "Slate", extra=(8, 0, 0))
        box("Decor", "ShedDoor", (2.4, 4.4, 0.2), (1.5, 2.2, -3.05), (70, 54, 40), "WoodPlanks")
        box("Decor", "ShedWindow", (1.8, 1.4, 0.2), (-2, 3.6, -3.05), (54, 66, 74), "Glass")
        for k in range(3):
            box("Cover", "Woodpile", (3, 1.0, 2.4), (6, 0.5 + k * 0.9, -1 + k * 0.1), (120, 92, 60), "Wood")

    def yard_market(self):
        """NO: Marktgasse hinter dem Marktviertel – Stände in zwei Reihen an der Gasse, Lichterketten, am Ende der
        Gasse der Schieber-Transporter (Stand_Red); in den Ecken Schuppen."""
        self.yard_pad(0, (118, 106, 86), "Ground")
        self.arc_pad("Sidewalk", YARD_R0, YARD_R1 - 6, 40.5, 49.5, GRAVEL, "Pebble", 0.14, step=5)
        for r, th, title, sub, tarp in ((89, 34, "WERKZEUG", "REPARIERT ALLES", (84, 98, 70)),
                                        (99, 35, "BÜCHER & KARTEN", "ALTE STADTPLÄNE", (70, 84, 104)),
                                        (89, 56, "ELEKTRONIK", "FUNKGERÄTE · AKKUS", (60, 62, 66)),
                                        (99, 55, "TALISMANE", "BRINGT GLÜCK", (130, 84, 60))):
            x, z = P(r, th)
            lx, lz = P(r, 45)
            self.junk_stall(x, z, self.yaw_to(lx - x, lz - z), title, sub, tarp)
        self.lane_light(45, 86, 104, step=9)
        self.schieber(*self.at_center(103, 45))
        self.shed(*self.at_center(97, 17))
        self.shed(*self.at_center(97, 73))
        self.fire_barrel(*P(103, 62))

    def yard_motor_pool(self):
        """SO: Fuhrpark – Tankstelle, Landeplatz am Ende der Gasse, Parkplatz mit Fahrzeugen, Flutlicht."""
        self.yard_pad(90, (70, 72, 74), "Asphalt")
        self.fuel_station(*self.at_center(91, 110))
        hx, hz = P(95, 135)
        self.b.add("Decor", "Helipad", (0.4, 22, 22), (hx, 0.25, hz), (96, 98, 96), "Concrete", angles=(0, 0, 90),
                   props={"Shape": "Cylinder"})
        self.b.floor_text("HelipadH", (8, 0.1, 8), (hx, 0.5, hz), "H", (230, 200, 90), yaw=self.yaw_to(-hx, -hz) + 180)
        for k in range(8):
            a = 2 * math.pi * k / 8
            self.b.box("Decor", "PadLight", (0.6, 0.4, 0.6), (hx + math.sin(a) * 10.4, 0.55, hz + math.cos(a) * 10.4), (120, 220, 120),
                       "Neon", props={"CanCollide": False})
        wx, wz = P(105, 122)
        self.b.box("Decor", "Windsock", (0.3, 8, 0.3), (wx, 4, wz), (150, 150, 150), "Metal")
        self.b.box("Decor", "WindsockCone", (1, 1, 3.2), (wx, 7.6, wz + 1.6), (230, 110, 40), "Fabric")
        for th in (155, 161, 167, 173):
            x, z, yaw = self.at_center(95, th)
            self.b.box("Ground", "ParkingLine", (0.4, 0.05, 11), (x, 0.12, z), (210, 206, 190), "SmoothPlastic", angles=(0, yaw, 0))
        for th in (158, 170):
            x, z, yaw = self.at_center(95, th)
            self.car(x, z, yaw + 180, burned=False, y=0.0)
        self.floodlight(*P(105, 150), *P(-1, 150), 13)
        self.barrels(*P(102, 100), n=3)

    def fuel_station(self, x, z, yaw):
        """Zapfinsel: Dach auf vier Stützen, zwei Zapfsäulen, Kanister, Schild."""
        b, rng = self.b, self.rng
        f, box = self.frame(x, z, yaw)
        box("Buildings", "Roof", (16, 0.6, 10), (0, 9, 0), (176, 60, 44), "Metal")
        box("Decor", "CanopyTrim", (16.2, 1.2, 10.2), (0, 8.2, 0), (220, 214, 200), "SmoothPlastic")
        for sx in (-1, 1):
            for sz in (-1, 1):
                box("Decor", "CanopyPost", (0.7, 8, 0.7), (sx * 6.5, 4, sz * 3.5), (200, 196, 186), "Metal")
        box("Cover", "PumpIsland", (11, 0.6, 2.4), (0, 0.3, 0), (130, 128, 120), "Concrete")
        for lx in (-3, 3):
            box("Cover", "FuelPump", (1.8, 4.2, 1.2), (lx, 2.7, 0), (200, 60, 44), "Metal")
            box("Decor", "PumpScreen", (1.2, 0.8, 0.1), (lx, 3.8, -0.65), (90, 200, 120), "Neon")
        for k in range(4):
            box("Cover", "Jerrycan", (0.8, 1.4, 1.2), (6.8 + k * 0.9, 0.7, 3.2), rng.choice(((150, 40, 34), (84, 98, 70))), "Metal")
        b.sign2("FuelStationSign", (8, 1.8, 0.3), f(0, 10.4, -5.2), "TANKSTELLE", "NUR GEGEN BARES", (30, 32, 36),
                (236, 200, 90), (214, 212, 202), angles=(0, yaw, 0))

    def yard_depot(self):
        """SW: Depot hinter der Markthalle – Container in einer Reihe, darüber der (niedrige) Portalkran, Paletten,
        Gabelstapler."""
        rng = self.rng
        self.yard_pad(180, (96, 96, 92), "Concrete", alleys=((28, 3.4), (62, 3.4)))
        cols = ((60, 86, 70), (110, 60, 48), (70, 84, 104), (150, 120, 60), (84, 98, 70))
        x, z, yaw = self.at_center(98, 209)
        self.container(x, z, yaw, rng.choice(cols), doors=True)
        self.container(x, z, yaw + rng.uniform(-2, 2), rng.choice(cols), y=8.5)
        for th in (225, 241):
            x, z, yaw = self.at_center(98, th)
            self.container(x, z, yaw, rng.choice(cols))
        gx, gz, gyaw = self.at_center(98, 225)
        f, box = self.frame(gx, gz, gyaw)
        for s in (-1, 1):
            for lz in (-5, 5):
                box("Buildings", "CraneLeg", (1.2, 17, 1.2), (s * 14, 8.5, lz), (200, 150, 40), "Metal")
        box("Buildings", "CraneBeam", (30, 1.8, 11.2), (0, 17.6, 0), (200, 150, 40), "Metal")
        box("Decor", "CraneHook", (0.2, 5, 0.2), (3, 14.5, 0), (40, 40, 40), "Metal")
        box("Decor", "CraneLight", (1, 1, 1), (0, 18.8, 0), (255, 60, 40), "Neon")
        self.forklift(*P(90, 243), 200)
        x, z, yaw = self.at_center(92, 206)
        f, box = self.frame(x, z, yaw)
        for lx in (-3, 0, 3):
            for j in range(rng.randint(1, 3)):
                box("Cover", "Pallet", (2.6, 0.5, 2.6), (lx, 0.25 + j * 1.6, 0), (150, 120, 84), "WoodPlanks")
                box("Cover", "PalletLoad", (2.4, 1.1, 2.4), (lx, 1.05 + j * 1.6, 0),
                    rng.choice(((180, 160, 120), (90, 100, 80), (120, 120, 114))), "Fabric")
        self.crates(*P(104, 253), n=3)
        self.floodlight(*P(105, 196), *P(-1, 196), 13)

    def forklift(self, x, z, yaw):
        """Gabelstapler (gelb) mit Mast und Gabel nach lokal -Z."""
        f, box = self.frame(x, z, yaw)
        yel = (214, 168, 40)
        box("Cover", "ForkliftBody", (3.4, 2.4, 4.6), (0, 1.6, 0.4), yel, "Metal")
        box("Decor", "ForkliftCage", (3.2, 2.6, 2.4), (0, 4.1, 0.8), (40, 40, 42), "Metal", props={"Transparency": 0.6})
        box("Decor", "ForkliftMast", (2.8, 5.4, 0.4), (0, 2.9, -2.1), (50, 50, 52), "Metal")
        for lx in (-0.8, 0.8):
            box("Decor", "ForkliftFork", (0.4, 0.2, 3), (lx, 0.4, -3.6), (50, 50, 52), "Metal")
        for lx in (-1.7, 1.7):
            for lz in (-1.2, 2):
                box("Decor", "ForkliftWheel", (0.6, 1.4, 1.4), (lx, 0.7, lz), (24, 24, 26), "Rubber", props={"Shape": "Cylinder"})

    def yard_living(self):
        """NW: Hof des Wohnviertels – Gemeinschaftsgarten, Lagerfeuer mit Bänken und Überlebenden, Wäscheleine,
        Wasserturm, Stromaggregat mit Flutlicht, ein Baum, ein Schuppen; an der Nordstraße die Gruftkapelle KATAKOMBEN."""
        b, rng = self.b, self.rng
        self.yard_pad(270, (106, 100, 80), "Ground")
        self.garden(*self.at_center(96, 299))
        fx, fz = P(95, 331)
        for k in range(10):
            a = 2 * math.pi * k / 10
            b.box("Decor", "FireStone", (1.3, 0.8, 1.3), (fx + math.cos(a) * 2.8, 0.4, fz + math.sin(a) * 2.8), (110, 106, 100), "Slate",
                  angles=(0, rng.uniform(0, 90), 0))
        b.box("Decor", "Bonfire", (2, 1, 2), (fx, 0.6, fz), (255, 130, 40), "Neon", props={"CanCollide": False},
              children=[{"Name": "Fire", "ClassName": "Fire", "Properties": {"Size": 7, "Heat": 10, "Color": self.bm.rgb(255, 140, 40),
                                                                                "SecondaryColor": self.bm.rgb(150, 40, 20)}},
                        {"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 34, "Brightness": 2.2,
                                                                                    "Color": self.bm.rgb(255, 180, 100)}}])
        for k in range(4):
            a = math.radians(20 + 90 * k)
            bx_, bz_ = fx + math.cos(a) * 6.5, fz + math.sin(a) * 6.5
            b.box("Cover", "LogBench", (5, 1.2, 1.3), (bx_, 0.6, bz_), (96, 72, 50), "Wood", angles=(0, -math.degrees(a) + 90, 0))
            if k != 2:
                self.survivor(bx_ - math.cos(a) * 0.8, bz_ - math.sin(a) * 0.8, self.yaw_to(fx - bx_, fz - bz_), pose="sit", y=0.3)
        x0, z0 = P(104, 308)
        x1, z1 = P(104, 322)
        for x_, z_ in ((x0, z0), (x1, z1)):
            b.box("Decor", "ClothesPole", (0.3, 7, 0.3), (x_, 3.5, z_), (90, 80, 70), "Wood")
        length = math.hypot(x1 - x0, z1 - z0)
        yaw = math.degrees(math.atan2(-(z1 - z0), x1 - x0))
        b.box("Decor", "ClothesLine", (length, 0.1, 0.1), ((x0 + x1) / 2, 6.6, (z0 + z1) / 2), (200, 200, 196), "SmoothPlastic",
              angles=(0, yaw, 0), props={"CanCollide": False})
        for k in range(6):
            t = 0.12 + k * 0.15
            b.box("Decor", "Laundry", (1.8, 2.4, 0.1), (x0 + (x1 - x0) * t, 5.3, z0 + (z1 - z0) * t),
                  rng.choice(((180, 60, 50), (200, 196, 186), (70, 90, 130), (120, 140, 90))), "Fabric",
                  angles=(0, yaw, 0), props={"CanCollide": False})
        wx, wz = P(94, 314)
        for dx in (-2.5, 2.5):
            for dz in (-2.5, 2.5):
                b.box("Decor", "TankLeg", (0.5, 10, 0.5), (wx + dx, 5, wz + dz), (70, 60, 50), "Wood")
        b.cylinder("Buildings", "WaterTank", 8, 6, (wx, 13, wz), (60, 84, 110), material="Plastic")
        gx, gz, gyaw = self.at_center(103, 284)
        f, box = self.frame(gx, gz, gyaw)
        box("Buildings", "Generator", (8, 4.5, 5), (0, 2.25, 0), (84, 98, 70), "Metal")
        box("Decor", "GeneratorExhaust", (0.8, 4, 0.8), (2.4, 5.8, 1.2), (50, 50, 52), "Metal",
            children=[{"Name": "Smoke", "ClassName": "Smoke", "Properties": {"Color": self.bm.rgb(60, 58, 56), "Opacity": 0.15,
                                                                             "RiseVelocity": 5, "Size": 3}}])
        self.floodlight(*self._xz(f, -6, -2), fx - gx, fz - gz, 13)
        self.plaza_tree(*P(92, 322), scale=1.1)
        self.shed(*self.at_center(89, 290))
        gx, gz = P(93, 344)
        self.crypt_gate(gx, gz + 2.5, self.yaw_to(1, 0))  # Front zur Nordstraße (nach Osten)

    def crypt_gate(self, x, z, yaw):
        """ABGANG ZU DEN KATAKOMBEN (Dungeon-Eingang): kleine Gruftkapelle aus Kalkstein mit Treppengiebel, Schieferdach,
        Strebepfeilern und violett flimmerndem Durchgang; davor Stufen, zwei Laternen, Kiesweg zur Straße. Der Punkt
        DungeonGate (Gruppe Zentrale, unsichtbar) vor der Tür trägt auf dem Server die E-Aufforderung (DungeonService).
        Ohne Zufallszahlen, damit der Rest des Camps gleich bleibt."""
        f, box = self.frame(x, z, yaw)
        W, D, H, rise = 12, 10, 7, 3.5
        fz = -D / 2
        stone, stone_dark, roof_c = (176, 170, 156), (120, 116, 108), (66, 68, 76)
        purple, door_w, door_h = (170, 90, 255), 4.4, 6
        box("Decor", "CryptPlinth", (W + 0.6, 0.8, D + 0.6), (0, 0.4, 0), stone_dark, "Slate")
        box("Buildings", "CryptWall", (W, H, 1), (0, H / 2, D / 2 - 0.5), stone, "Limestone")
        for s in (-1, 1):
            box("Buildings", "CryptWall", (1, H, D), (s * (W / 2 - 0.5), H / 2, 0), stone, "Limestone")
            pw = (W - door_w) / 2
            box("Buildings", "CryptWall", (pw, H, 1), (s * (door_w / 2 + pw / 2), H / 2, fz + 0.5), stone, "Limestone")
            for lz in (fz, D / 2):  # Strebepfeiler an den Ecken
                box("Decor", "CryptButtress", (1.4, H - 1, 1.4), (s * W / 2, (H - 1) / 2, lz), stone_dark, "Cobblestone")
            slope = math.degrees(math.atan2(rise, W / 2))
            box("Buildings", "CryptRoof", (math.hypot(W / 2, rise) + 0.8, 0.5, D + 1.2), (s * W / 4, H + rise / 2 + 0.2, 0), roof_c,
                "Slate", extra=(0, 0, -s * slope))
            box("Decor", "DoorPilaster", (0.8, door_h, 1.4), (s * (door_w / 2 + 0.4), door_h / 2, fz), stone_dark, "Cobblestone")
        box("Buildings", "CryptWall", (door_w, H - door_h, 1), (0, door_h + (H - door_h) / 2, fz + 0.5), stone, "Limestone")
        box("Decor", "DoorLintel", (door_w + 2.4, 1, 1.6), (0, door_h + 0.5, fz), stone_dark, "Cobblestone")
        # Treppengiebel vorn und hinten
        for gz, gname in ((fz + 0.5, "CryptGable"), (D / 2 - 0.5, "CryptGable")):
            for k, gw in enumerate((W - 1, W - 4.6, W - 8.2)):
                box("Buildings", gname, (gw, 1.2, 1), (0, H + 0.6 + k * 1.2, gz), stone, "Limestone")
        box("Decor", "GableCross", (0.4, 2.2, 0.4), (0, H + 4.7, fz + 0.5), stone_dark, "Cobblestone")
        box("Decor", "GableCross", (1.4, 0.4, 0.4), (0, H + 5.2, fz + 0.5), stone_dark, "Cobblestone")
        # dunkler Abgang mit violettem Flimmern
        box("Decor", "CryptFloor", (W - 2, 0.3, D - 2), (0, 0.95, 0.5), (24, 22, 28), "Slate")
        box("Decor", "Doorway", (door_w, door_h, 0.3), (0, door_h / 2, fz + 1.6), (8, 6, 12), "SmoothPlastic")
        box("Decor", "CryptRift", (door_w - 0.4, door_h - 0.4, 0.2), (0, door_h / 2, fz + 1.1), purple, "Neon",
            props={"CanCollide": False, "Transparency": 0.45, "CastShadow": False},
            children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 18, "Brightness": 1.8,
                                                                                 "Color": self.bm.rgb(*purple)}}])
        for k in range(2):  # Stufen vor der Tür
            box("Decor", "CryptStep", (door_w + 2.6 - k * 1.2, 0.4, 1.4), (0, 0.2 + k * 0.4, fz - 1.6 + k * 0.7), stone_dark, "Slate")
        for s in (-1, 1):  # Laternen und Urnen
            box("Decor", "LanternPost", (0.4, 4.4, 0.4), (s * 4.4, 2.2, fz - 2.4), (40, 40, 44), "Metal")
            box("Decor", "Lantern", (0.9, 1.2, 0.9), (s * 4.4, 4.8, fz - 2.4), (200, 150, 255), "Neon", props={"CanCollide": False},
                children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 14, "Brightness": 1.2,
                                                                                     "Color": self.bm.rgb(190, 130, 255)}}])
            self.b.cylinder("Decor", "Urn", 1.6, 1.8, f(s * 5.4, 0.9, fz - 1.2), stone_dark, material="Cobblestone")
        self.b.sign2("CryptSign", (7.2, 1.8, 0.3), f(0, H + 1.6, fz - 0.15), "KATAKOMBEN", "DUNGEON · E MIT DUNGEON-SCHLÜSSEL",
                     (24, 20, 30), (210, 160, 255), (214, 206, 224), angles=(0, yaw, 0), glow=purple)
        # Kiesweg zur Straße
        box("Ground", "Sidewalk", (4.6, 0.2, 9), (0, 0.04, fz - 2.3 - 4.5), GRAVEL, "Pebble")
        self.b.add("Zentrale", "DungeonGate", (2, 2, 2), f(0, 3, fz - 3.5), purple, "SmoothPlastic", angles=(0, yaw, 0),
                   props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    def garden(self, x, z, yaw):
        """Gemüsebeete mit Zaun und Vogelscheuche."""
        rng = self.rng
        f, box = self.frame(x, z, yaw)
        for k in range(4):
            box("Decor", "GardenBed", (3, 0.6, 12), (-7.5 + k * 5, 0.3, 0), (78, 60, 44), "Ground")
            for j in range(4):
                box("Decor", "GardenPlant", (1.3, 1.3, 1.3), (-7.5 + k * 5, 1.1, -4.2 + j * 2.8),
                    rng.choice(((84, 120, 60), (110, 130, 64), (140, 120, 50))), "Grass", props={"Shape": "Ball", "CanCollide": False})
        for s in (-1, 1):
            box("Decor", "GardenFence", (0.3, 2.2, 15), (s * 11, 1.1, 0), (110, 92, 70), "WoodPlanks")
        box("Decor", "GardenFence", (22, 2.2, 0.3), (0, 1.1, 7.5), (110, 92, 70), "WoodPlanks")
        box("Decor", "ScarecrowPole", (0.4, 7, 0.4), (0, 3.5, 6), (90, 70, 50), "Wood")
        box("Decor", "ScarecrowArms", (5, 0.4, 0.4), (0, 5.6, 6), (90, 70, 50), "Wood")
        box("Decor", "ScarecrowCoat", (2.2, 2.6, 1), (0, 5, 6), (110, 90, 60), "Fabric")
        box("Decor", "ScarecrowHead", (1.3, 1.3, 1.3), (0, 7, 6), (200, 180, 120), "Fabric")

    def junk_stall(self, x, z, yaw, title, sub, tarp):
        """Marktstand: Tisch aus Paletten mit Kram, Plane auf Stangen, Schild."""
        b, rng = self.b, self.rng
        f, box = self.frame(x, z, yaw)
        box("Cover", "StallTable", (9, 2.6, 2.4), (0, 1.3, -1.2), (124, 100, 70), "WoodPlanks")
        for k in range(6):
            box("Decor", "Junk", (rng.uniform(0.6, 1.6), rng.uniform(0.4, 1.2), rng.uniform(0.6, 1.4)),
                (-3.6 + k * 1.45, 3.0, -1.2 + rng.uniform(-0.5, 0.5)),
                rng.choice(((90, 92, 96), (150, 120, 60), (60, 70, 80), (130, 60, 50), (180, 176, 160))),
                rng.choice(("Metal", "Plastic", "Fabric")), extra=(0, rng.uniform(0, 60), 0))
        for s in (-1, 1):
            for lz in (-3, 3):
                box("Decor", "StallPole", (0.35, 7.5, 0.35), (s * 4.8, 3.75, lz), PLANK_DARK, "Wood")
        box("Decor", "StallTarp", (10.4, 0.2, 7.4), (0, 7.6, 0), tarp, "Fabric", extra=(rng.uniform(-6, 6), 0, rng.uniform(-3, 3)))
        b.sign2("StallSign", (7, 1.6, 0.2), f(0, 6.2, -3.1), title, sub, (150, 140, 120), (40, 30, 26), (60, 50, 44),
                angles=(0, yaw, rng.uniform(-4, 4)))
        self.crates(*self._xz(f, 0, 3.5), n=2, spread=2)

    def schieber(self, x, z, yaw):
        """Schwarzmarkt: schwarzer Transporter mit offener Seitentür (Kisten, rotes Licht), daneben der Schieber mit
        Kapuze (Punkt Stand_Red: Händler für Rote-Zone-Punkte), Planen als Sichtschutz."""
        b = self.b
        f, box = self.frame(x, z, yaw)  # lokal -Z = zur Mitte
        black = (26, 27, 30)
        box("Cover", "VanBody", (9, 5.2, 5.4), (1.5, 3.1, 1), black, "Metal")
        box("Cover", "VanCab", (3.4, 3.6, 5.2), (-4.6, 2.3, 1), black, "Metal")
        box("Decor", "VanWindshield", (0.2, 1.6, 4.6), (-6.35, 3.4, 1), (40, 52, 60), "Glass")
        for lx in (-4.4, 3.8):
            for lz in (-1.6, 3.6):
                box("Decor", "VanWheel", (2, 2, 0.8), (lx, 1, lz), (18, 18, 18), "Rubber")
        box("Decor", "VanOpening", (3.6, 4, 0.1), (0.9, 3, -1.72), (12, 10, 10), "SmoothPlastic")
        box("Decor", "VanDoor", (3.6, 4.2, 0.25), (4.4, 3, -1.95), black, "Metal")
        box("Stands", "SchieberLight", (3, 0.3, 0.2), (0.9, 5.2, -1.4), (255, 40, 40), "Neon",
            children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 16, "Brightness": 1.6,
                                                                                 "Color": self.bm.rgb(255, 40, 40)}}])
        for lx, h in ((0.2, 1.4), (1.6, 1.0)):
            box("Decor", "SchieberCrate", (1.3, h, 1.8), (lx, 1.0 + h / 2, -0.6), (70, 84, 56), "Metal")
        box("Decor", "SchieberCase", (1.6, 0.5, 1.1), (0.9, 0.9, -3.6), (30, 30, 34), "Metal")
        box("Decor", "SchieberCaseStand", (1.6, 0.6, 1.1), (0.9, 0.3, -3.6), (110, 88, 62), "WoodPlanks")
        self.npc_figure(box, -2.2, -4.2, jacket=(34, 34, 38), pants=(28, 28, 32), cap=None, skin=(170, 132, 104))
        box("Decor", "NpcHood", (1.5, 1.5, 1.5), (-2.2, 5.9, -4.05), (40, 40, 44), "Fabric")
        box("Decor", "NpcScarf", (1.3, 0.5, 1.25), (-2.2, 5.25, -4.25), (150, 30, 30), "Fabric")
        for lx in (-9, 10):
            box("Decor", "ScreenTarp", (0.2, 6, 7), (lx, 3.4, -1), (50, 54, 48), "Fabric", extra=(0, 0, 3))
            box("Decor", "ScreenPole", (0.3, 7, 0.3), (lx, 3.5, -4.5), PLANK_DARK, "Wood")
        b.add("Stands", "Stand_Red", (2, 2, 2), f(-2.2, 2.5, -7.2), (200, 60, 60), "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    # ---------- Mauer, Tore, Vorfeld ----------
    def camp_wall(self):
        """Ringmauer aus Betonfertigteilen mit Pfeilern und Stacheldraht (wie im alten Camp); vier Tore."""
        b, rng = self.b, self.rng
        R = CAMP_WALL_R
        gate_half = math.degrees(math.asin((GATE_W / 2 + 7.5) / R))
        for q in range(4):
            th0, th1 = q * 90 + gate_half, (q + 1) * 90 - gate_half
            n = int(round((th1 - th0) * math.pi / 180 * R / 8))
            d = (th1 - th0) / n
            for k in range(n):
                th = th0 + (k + 0.5) * d
                x, z, yaw = self.at_center(R, th)
                seg = 2 * R * math.sin(math.radians(d / 2)) + 0.4
                f, box = self.frame(x, z, yaw)
                box("Walls", "WallPanel", (seg, 10, 1.2), (0, 5, 0), rng.choice(((150, 148, 140), (144, 142, 134), (156, 152, 142))),
                    "Concrete")
                box("Decor", "WallPost", (1, 11, 1.6), (seg / 2, 5.5, 0), (130, 128, 122), "Concrete")
                b.add("Walls", "RazorWire", (seg, 1.4, 1.4), f(0, 11.4, 0), (128, 128, 126), "CorrodedMetal",
                      angles=(0, yaw + 90, 90), props={"Shape": "Cylinder"})
                if k % 4 == 2:
                    box("Decor", "WallLamp", (0.8, 0.6, 0.8), (0, 10.3, -0.9), (255, 236, 200), "Neon", children=self.warm_light(16, 0.7))
        for th in (0, 90, 180, 270):
            self.camp_gate(th)

    def camp_gate(self, th):
        """Tor: zwei Container-Türme mit Wachplattform, offene Stahlflügel, Balken mit Schild (außen CAMP PHOENIX,
        innen AUSGANG), Sandsack-Nester, Scheinwerfer, draußen Betonblöcke als Schikane."""
        b, rng = self.b, self.rng
        R = CAMP_WALL_R
        x, z, yaw = self.at_center(R, th)
        f, box = self.frame(x, z, yaw)  # lokal -Z = nach innen
        cont = rng.choice(((110, 60, 48), (60, 86, 110), (84, 98, 70)))
        for s in (-1, 1):
            lx = s * (GATE_W / 2 + 3.5)
            box("Walls", "GateContainer", (7, 8.5, 8), (lx, 4.25, 0), cont, "CorrodedMetal")
            box("Walls", "GateContainerTop", (7, 8.5, 8), (lx, 12.75, 0), self.bm.lighten(cont, -0.15), "CorrodedMetal")
            box("Decor", "GateRail", (7.4, 1.2, 0.3), (lx, 17.6, -4.1), (110, 92, 70), "WoodPlanks")
            box("Decor", "GateRail", (7.4, 1.2, 0.3), (lx, 17.6, 4.1), (110, 92, 70), "WoodPlanks")
            box("Decor", "GateLeaf", (7, 9, 0.3), (s * (GATE_W / 2 - 0.5), 4.5, -4.5), (120, 124, 126), "DiamondPlate",
                extra=(0, -s * 65, 0))
            box("Cover", "Sandbags", (5, 2.6, 2.2), (s * (GATE_W / 2 + 3.5), 1.3, -6.4), (150, 134, 98), "Fabric")
            box("Decor", "GateLamp", (1.4, 1.2, 1.6), (s * 7, 16.8, -2), (236, 236, 226), "Neon", extra=(25, 0, 0),
                children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {"Face": "Front", "Range": 50, "Brightness": 1.8,
                                                                                     "Angle": 70, "Color": self.bm.rgb(240, 240, 230)}}])
            wx, _, wz = f(lx, 0, 0)
            self.survivor(wx, wz, yaw + 180, y=17.0, gun=True)
        box("Walls", "GateBeam", (GATE_W + 2, 1.4, 1.4), (0, 17.3, 0), (90, 92, 94), "Metal")
        for yaw_off, dz_ in ((180, 1.2), (0, -1.2)):  # 180: liest man von draußen, 0: von drinnen
            outside = yaw_off == 180
            b.sign2("GateSign", (13, 2.8, 0.3), f(0, 15.2, dz_), "CAMP PHOENIX" if outside else "AUSGANG",
                    "SAFE ZONE · KEIN PVP" if outside else "DRAUSSEN: ZOMBIES · PVP NACH 5 SEK.",
                    (30, 32, 30), (226, 214, 180) if outside else (220, 70, 56), (214, 212, 202), angles=(0, yaw + yaw_off, 0))
        for lx, lz in ((-5, 9), (5, 16)):
            box("Cover", "JerseyBarrier", (8, 3, 2.2), (lx, 1.5, lz), (160, 158, 150), "Concrete", extra=(0, rng.uniform(-6, 6), 0))

    def glacis(self):
        """Vorfeld zwischen Mauer und Stadt: nahe der Mauer Panzersperren und Stacheldraht-Rollen, weiter draußen
        vereinzelt Wracks, tote Bäume und Gestrüpp; Warnschilder. Die Zufahrten bleiben frei."""
        b, rng = self.b, self.rng
        R = CAMP_WALL_R
        placed = []
        for k in range(90):
            th = rng.uniform(0, 360)
            if min(abs((th - g + 180) % 360 - 180) for g in (0, 90, 180, 270)) < 10:
                continue
            near = k < 45
            r = rng.uniform(R + 6, R + 22) if near else rng.uniform(R + 24, SAFE_R - 10)
            x, z = P(r, th)
            if any(math.hypot(x - px, z - pz) < 8 for px, pz in placed):
                continue
            placed.append((x, z))
            kind = rng.random()
            if near:
                if kind < 0.6:  # Panzersperre (drei gekreuzte Träger)
                    yaw = rng.uniform(0, 90)
                    for a in ((0, 0, 55), (0, 90, 55), (55, 45, 0)):
                        b.box("Cover", "Hedgehog", (0.8, 6, 0.8), (x, 1.9, z), (60, 58, 56), "Metal", angles=(a[0], yaw + a[1], a[2]))
                else:
                    x2, z2, yaw = self.at_center(r, th)
                    b.add("Decor", "BarbedCoil", (7, 1.6, 1.6), (x2, 0.8, z2), (120, 120, 116), "CorrodedMetal",
                          angles=(0, yaw + 90, 90), props={"Shape": "Cylinder", "Transparency": 0.2})
            elif kind < 0.3:
                self.car(x, z, rng.uniform(0, 360), burned=True, y=0.0)
            elif kind < 0.65:
                self.dead_tree(x, z, g=0.0)
            else:
                self.dry_scrub(x, z, g=0.0)
        for th in (45, 135, 225, 315):
            x, z, yaw = self.at_center(R + 9, th)
            self.warning_sign(x, z, yaw + 180, "SPERRZONE", "NICHT STEHEN BLEIBEN · SCHUSSFELD")

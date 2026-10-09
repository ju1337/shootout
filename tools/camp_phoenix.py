"""Camp Phoenix: die große Safe Zone in der Mitte der offenen Welt (Start des Spiels).

Rund angelegt statt Häuserblöcke: eine Festung aus Schrott und Containern (Mauer Radius CAMP_WALL_R, vier Tore in den
Himmelsrichtungen), innen alles über Wege erreichbar:

  * Mitte: der PHÖNIXPLATZ (Pflaster, Spawn-Ring) mit dem Denkmal „Agent der Woche“ (Statue setzt der Client).
  * Um den Platz der „Kern“ mit allem, was früher im Hub stand – jedes Stück schaut zum Platz:
      NO Glücksrad-Bühne, SO Ausrüster (Shop-Vitrinen, Theke, daneben der Kit-Händler),
      SW Ruhmeswand (vier Bestenlisten), NW Siegerpodest (Top 3) mit Lagebericht und Bildtafel.
  * Ringweg (Kies) um den Kern, vier Hauptwege vom Platz zu den Toren (an jeder Kreuzung ein Wegweiser).
  * Außen vier Viertel mit eigenem Gesicht:
      NO BASAR (Waffen, Sani, Garküche, Trödelstände, hinten in der Gasse der Schieber),
      SO FUHRPARK (Werkstatt, Busbahnhof, Landeplatz, Tanklager, Parkplatz),
      SW DEPOT (Lager, Tauschmarkt, Container-Stapel, das Tor zur Markthalle),
      NW WOHNLAGER (Lagerfeuer mit Überlebenden, Zelte, Sanitätszelt, Gemüsebeete, Wasserturm, Versteck).
  * Vor der Mauer ein freies Vorfeld mit Panzersperren und Stacheldraht.

Die Teile, die Server und Client suchen (Shop, Rad, Bestenlisten, Podest, Statue, Markt-Tor), landen in der Gruppe
"Zentrale" (immer geladen, src/shared/Zentrale.lua). Läuft mit eigenen Zufallszahlen (World.camp).
"""
import math

SAFE_R = 165          # Safe Zone (Radius, Teil "SafeZone")
CAMP_WALL_R = 140     # Mitte der Mauer
PLAZA_R = 24          # Phönixplatz
RING_R, RING_W = 60, 10      # Ringweg um den Kern
AVENUE_W = 14         # Hauptwege zu den Toren
GATE_W = 18           # Durchfahrt in den Toren

GRAVEL, GRAVEL_DARK = (128, 120, 104), (104, 98, 86)
PLANK, PLANK_DARK, RUST, STEEL, DARK = (128, 100, 70), (92, 72, 52), (112, 74, 52), (84, 88, 92), (40, 42, 46)
EMBER, GOLD = (255, 150, 60), (212, 170, 80)


def P(r, th):
    """Punkt im Abstand r von der Mitte in Kompassrichtung th (0 = Norden = +Z, 90 = Osten = +X)."""
    a = math.radians(th)
    return r * math.sin(a), r * math.cos(a)


class CampPhoenix:
    """Mixin für World (tools/extinction_world.py)."""

    # ---------- Grundlagen ----------
    def at_center(self, r, th):
        """(x, z, yaw) an Position (r, th), Vorderseite (lokal -Z) zur Mitte."""
        x, z = P(r, th)
        return x, z, self.yaw_to(-x, -z)

    def arc_pad(self, name, r0, r1, th0, th1, color, mat, top, group="Ground", step=6.0):
        """Ringstück (r0 bis r1, Winkel th0 bis th1) aus schmalen Platten, Oberkante top."""
        n = max(1, int(math.ceil((th1 - th0) / step)))
        d = (th1 - th0) / n
        for k in range(n):
            th = th0 + (k + 0.5) * d
            x, z, yaw = self.at_center((r0 + r1) / 2, th)
            width = 2 * r1 * math.tan(math.radians(d / 2)) + 0.3
            self.b.box(group, name, (width, 0.2, r1 - r0), (x, top - 0.1, z), color, mat, angles=(0, yaw, 0))

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
            self.b.add("Decor", "Bulb", (0.45, 0.45, 0.45), (ax + (bx - ax) * t, y + dy - 0.3, az + (bz - az) * t), color, "Neon",
                       props={"Shape": "Ball", "CanCollide": False, "CanQuery": False})

    def lamp_post(self, x, z, fx, fz, h=11):
        """Laternenmast aus Rohr mit Ausleger zur Seite (fx, fz) und warmer Lampe."""
        f, box = self.frame(x, z, self.yaw_to(fx, fz))
        box("Decor", "LampBase", (1, 1, 1), (0, 0.5, 0), DARK, "Metal")
        box("Decor", "LampPost", (0.45, h, 0.45), (0, h / 2, 0), DARK, "Metal")
        box("Decor", "LampArm", (0.3, 0.3, 2.4), (0, h - 0.2, -1.1), DARK, "Metal")
        box("Decor", "LampHead", (1.1, 0.7, 1.1), (0, h - 0.7, -2.2), (255, 222, 170), "Neon",
            children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 34, "Brightness": 1.2,
                                                                                 "Color": self.bm.rgb(255, 214, 160)}}])
        box("Decor", "LampHat", (1.6, 0.3, 1.6), (0, h - 0.2, -2.2), DARK, "Metal")

    def signpost(self, x, z, boards):
        """Wegweiser: Pfahl mit Pfeil-Brettern. boards = [(Richtung th, Text, Farbe)]."""
        b = self.b
        b.box("Decor", "SignpostPole", (0.6, 11, 0.6), (x, 5.5, z), PLANK_DARK, "Wood")
        for k, (th, text, color) in enumerate(boards):
            fx, fz = P(1, th)
            yaw = math.degrees(math.atan2(-fz, fx))  # Brett liegt entlang der Richtung (lokal +X zeigt dorthin)
            cx, cz = x + fx * 3.6, z + fz * 3.6
            y = 9.6 - k * 1.9
            board = {"Name": "SignGui", "ClassName": "SurfaceGui", "Properties": {
                "Face": "Front", "LightInfluence": 0.4, "SizingMode": "PixelsPerStud", "PixelsPerStud": 30},
                "Children": [{"Name": "Text", "ClassName": "TextLabel", "Properties": {
                    "Size": {"UDim2": [[1, 0], [1, 0]]}, "BackgroundTransparency": 1, "Text": text, "TextScaled": True,
                    "Font": "Oswald", "TextColor3": self.bm.rgb(*color)}}]}
            back = dict(board, Properties=dict(board["Properties"], Face="Back"))
            b.box("Decor", "SignpostBoard", (7.2, 1.5, 0.3), (cx, y, cz), (58, 46, 36), "WoodPlanks", angles=(0, yaw, 0),
                  children=[board, back])
            tip = math.degrees(math.atan2(-fz, fx))
            b.add("Decor", "SignpostTip", (1.5, 1.5, 0.3), (x + fx * 7.4, y, z + fz * 7.4), (58, 46, 36), "WoodPlanks",
                  angles=(0, tip, 45))

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

    # ---------- Aufbau ----------
    def _camp(self):
        b = self.b
        R = SAFE_R
        b.add("Zone", "SafeZone", (2 * R, 80, 2 * R), (0, 40, 0), (96, 210, 120), "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
        # Boden: festgetretene Erde bis vor die Mauer, Ringweg, Platz, Hauptwege
        self.polygon_pad("CampPad", CAMP_WALL_R + 8, (112, 104, 90), "Ground", 0.0, thickness=3)
        self.arc_pad("Sidewalk", RING_R - RING_W / 2, RING_R + RING_W / 2, 0, 360, GRAVEL, "Pebble", 0.1, step=7.5)
        for th in (0, 90, 180, 270):
            x, z = P((PLAZA_R + CAMP_WALL_R) / 2, th)
            yaw = self.yaw_to(-x, -z)
            length = CAMP_WALL_R - PLAZA_R + 4
            b.box("Ground", "Sidewalk", (AVENUE_W, 0.2, length), (x, 0.04, z), (96, 92, 86), "Asphalt", angles=(0, yaw, 0))
        self.plaza()
        for th in (0, 90, 180, 270):
            self.avenue(th)
        for th in range(0, 360, 30):  # Laternen am Ringweg (außen), nicht auf den Hauptwegen
            x, z = P(RING_R + RING_W / 2 + 1.5, th + 15)
            self.lamp_post(x, z, -x, -z)
        # der Kern um den Platz
        self.wheel_stage(*self.at_center(42, 45))
        self.outfitter(*self.at_center(43, 135))
        self.hall_of_fame(*self.at_center(46, 225))
        self.podium_wall(*self.at_center(38, 315))
        # die vier Viertel
        self.bazaar()
        self.motor_pool()
        self.depot()
        self.living_quarter()
        # Mauer, Tore, Türme, Vorfeld
        self.camp_wall()
        self.glacis()

    def plaza(self):
        """Phönixplatz: Pflaster, Randsteine, Denkmal mit dem Agenten der Woche, Feuerschalen, Spawn-Ring, Bänke, Fahnen."""
        b, rng = self.b, self.rng
        self.polygon_pad("Square", PLAZA_R, (128, 122, 114), "Cobblestone", 0.22)
        n = 32
        for k in range(n):
            th = 360 * (k + 0.5) / n
            x, z, yaw = self.at_center(PLAZA_R - 0.4, th)
            b.box("Ground", "SquareEdge", (2 * math.pi * PLAZA_R / n + 0.3, 0.35, 0.8), (x, 0.18, z), (100, 96, 90), "Slate",
                  angles=(0, yaw, 0))
        # Mosaik: Ring und Phönix-Strahlen im Pflaster
        for k in range(16):
            th = 360 * k / 16
            x, z, yaw = self.at_center(15.5, th)
            b.box("Ground", "MosaicRay", (0.6, 0.05, 5), (x, 0.24, z), (170, 92, 52), "Slate", angles=(0, yaw, 0))
        g = "Zentrale"
        # Denkmal: Stufen, Sockel, Bronzeband, Inschrift; Statue setzt der Client an AgentOfWeekSpot
        b.cylinder(g, "MonumentStep", 15, 0.8, (0, 0.4, 0), (120, 116, 108), material="Concrete")
        b.cylinder(g, "MonumentBase", 11, 1.4, (0, 1.5, 0), (96, 92, 86), material="Slate")
        b.cylinder(g, "MonumentPlinth", 8, 1.4, (0, 2.9, 0), (60, 58, 56), material="Slate")
        b.cylinder(g, "MonumentBand", 8.3, 0.3, (0, 3.3, 0), (176, 128, 64), material="Metal")
        b.add(g, "AgentOfWeekSpot", (1, 0.2, 1), (0, 3.6, 0), GOLD, "SmoothPlastic", angles=(0, 180, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
        b.add(g, "AgentOfWeekHolo", (1, 1, 1), (0, 17, 0), GOLD, "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
        for th, text in ((0, "AGENT DER WOCHE"), (180, "+50 % XP MIT IHM")):
            x, z, yaw = self.at_center(5.65, th)
            b.sign2("MonumentPlaque", (5, 1.2, 0.2), (x, 1.5, z), text, "", (54, 48, 40), (226, 190, 120), (200, 190, 170),
                    angles=(0, yaw + 180, 0))
        # Feuerschalen zwischen den Hauptwegen (warmes Licht für die Statue), Spawn-Ring nach außen
        for th in (45, 135, 225, 315):
            x, z = P(8.6, th)
            b.cylinder("Decor", "BrazierStand", 1.0, 2.6, (x, 1.3, z), DARK, material="Metal")
            b.cylinder("Decor", "Brazier", 2.4, 0.8, (x, 3.0, z), (60, 54, 48), material="CorrodedMetal")
            b.box("Decor", "BrazierFire", (1.4, 0.4, 1.4), (x, 3.5, z), (255, 120, 40), "Neon",
                  props={"CanCollide": False, "Transparency": 0.3},
                  children=[{"Name": "Fire", "ClassName": "Fire", "Properties": {"Size": 4, "Heat": 8,
                                                                                    "Color": self.bm.rgb(255, 140, 40),
                                                                                    "SecondaryColor": self.bm.rgb(140, 40, 20)}},
                            {"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 22, "Brightness": 1.6,
                                                                                        "Color": self.bm.rgb(255, 170, 90)}}])
        for k in range(10):
            th = 360 * (k + 0.5) / 10
            x, z = P(11.5, th)
            b.spawn(x, z, yaw=th)  # Blick nach außen
        # Bänke am Platzrand (zwischen den Wegen, Blick zur Statue), Pflanzkübel, Fahnenmasten mit Phönix-Bannern
        for th in (45, 135, 225, 315):
            for d in (-14, 14):
                x, z, yaw = self.at_center(20.5, th + d)
                f, box = self.frame(x, z, yaw)
                box("Cover", "Bench", (5, 0.4, 1.6), (0, 1.5, 0), (110, 84, 58), "WoodPlanks")
                box("Decor", "BenchBack", (5, 1.6, 0.3), (0, 2.5, 0.8), (110, 84, 58), "WoodPlanks")
                for s in (-1, 1):
                    box("Decor", "BenchLeg", (0.3, 1.3, 1.4), (s * 2.2, 0.65, 0), (50, 50, 52), "Metal")
            x, z = P(21, th)
            b.box("Cover", "Planter", (3.6, 1.2, 3.6), (x, 0.6, z), (120, 116, 108), "Concrete", angles=(0, th, 0))
            b.box("Decor", "PlanterSoil", (3.0, 0.2, 3.0), (x, 1.25, z), (70, 56, 44), "Ground", angles=(0, th, 0))
            b.add("Decor", "Shrub", (3.4, 2.6, 3.4), (x, 2.4, z), (74, 98, 54), "LeafyGrass",
                  props={"Shape": "Ball", "CanCollide": False})
        for th in (0, 90, 180, 270):  # Fahnen beidseits der Platz-Einfahrten
            for d in (-1, 1):
                x, z = P(PLAZA_R + 1.5, th)
                ox, oz = P(AVENUE_W / 2 + 2, th + 90)
                px, pz = x + d * ox, z + d * oz
                b.box("Decor", "FlagPole", (0.5, 18, 0.5), (px, 9, pz), (70, 72, 76), "Metal")
                b.box("Decor", "FlagBanner", (0.15, 7, 3.4), (px, 13.6, pz), (176, 60, 40), "Fabric", angles=(0, th + 90, 0),
                      props={"CanCollide": False})
                b.box("Decor", "FlagEmblem", (0.2, 2, 2), (px, 14.4, pz), (236, 170, 70), "Fabric", angles=(0, th + 90, 45),
                      props={"CanCollide": False})
        for _ in range(4):
            x, z = P(rng.uniform(17, 22), rng.uniform(0, 360))
            b.box("Decor", "Paper", (1, 0.05, 1.3), (x, 0.26, z), (200, 196, 180), "SmoothPlastic",
                  angles=(0, rng.uniform(0, 180), 0), props={"CanCollide": False})

    def avenue(self, th):
        """Hauptweg vom Platz zum Tor: Bretter-Gehwege an den Seiten, Laternen, Lichterketten, Wegweiser am Ringweg."""
        b = self.b
        for d in (-1, 1):
            for r0, r1 in ((PLAZA_R + 2, RING_R - RING_W / 2 - 1), (RING_R + RING_W / 2 + 1, CAMP_WALL_R - 8)):
                cx, cz = P((r0 + r1) / 2, th)
                ox, oz = P(AVENUE_W / 2 + 1.6, th + 90)
                b.box("Ground", "Boardwalk", (3, 0.4, r1 - r0), (cx + d * ox, 0.2, cz + d * oz), PLANK, "WoodPlanks", angles=(0, th, 0))
        for k, r in enumerate((76, 96, 116)):
            d = 1 if k % 2 == 0 else -1
            x, z = P(r, th)
            ox, oz = P(AVENUE_W / 2 + 3.4, th + 90)
            self.lamp_post(x + d * ox, z + d * oz, -d * ox, -d * oz, h=12)
        for r in (34, 86, 106):  # Lichterketten quer über den Weg
            x, z = P(r, th)
            ox, oz = P(AVENUE_W / 2 + 1.6, th + 90)
            for d in (-1, 1):
                b.box("Decor", "LightPole", (0.4, 9, 0.4), (x + d * ox, 4.5, z + d * oz), PLANK_DARK, "Wood")
            self.string_lights((x - ox, z - oz), (x + ox, z + oz), 8.6)
        # Wegweiser an der Kreuzung mit dem Ringweg (auf der Platzseite, rechts vom Weg nach außen)
        x, z = P(RING_R - RING_W / 2 - 3, th)
        ox, oz = P(AVENUE_W / 2 + 3, th + 90)
        quarters = {0: ("BASAR", "WOHNLAGER"), 90: ("FUHRPARK", "BASAR"), 180: ("DEPOT · MARKT", "FUHRPARK"),
                    270: ("WOHNLAGER", "DEPOT · MARKT")}
        right, left = quarters[th]
        gate = {0: "NORDTOR", 90: "OSTTOR", 180: "SÜDTOR", 270: "WESTTOR"}[th]
        self.signpost(x + ox, z + oz, [(th, gate, (236, 226, 196)), (th + 90, right, (240, 196, 120)),
                                       (th - 90, left, (240, 196, 120)), (th + 180, "PLATZ", (200, 200, 190))])

    # ---------- Kern: früher der Hub ----------
    def _feature(self, build, x, z, yaw):
        """Prefab bauen (Vorderseite -Z zum Platz) und aufstellen; Decor wird zur Gruppe Zentrale."""
        pb = self.prefab()
        build(pb)
        pb.groups["Zentrale"] = pb.groups.pop("Decor", []) + pb.groups.pop("Zentrale", [])
        self.stamp(pb, x, z, yaw)

    def wheel_stage(self, x, z, yaw):
        """Glücksrad-Bühne: runde Bühne, Rad zwischen zwei Pfeilern (das Rad baut der Client an WheelSpot), Glühbirnen-
        Rahmen wie auf dem Jahrmarkt, Pult vorne (E: drehen), Rückwand aus Wellblech, Strahler."""
        bm = self.bm

        def build(pb):
            gold, frame_c = GOLD, (36, 38, 42)
            wy, wr = 9.4, 6
            pb.add("Decor", "WheelPlatform", (0.6, 17, 17), (0, 0.3, 0), (60, 56, 52), "WoodPlanks", angles=(0, 0, 90),
                   props={"Shape": "Cylinder"})
            pb.add("Decor", "WheelPlatformEdge", (0.5, 17.6, 17.6), (0, 0.2, 0), gold, "Metal", angles=(0, 0, 90),
                   props={"Shape": "Cylinder"})
            pb.box("Decor", "WheelBackdrop", (20, 15, 0.6), (0, 7.8, 3.6), (92, 98, 92), "CorrodedMetal")
            for k in range(7):
                pb.box("Decor", "WheelBackdropRib", (0.4, 15, 0.8), (-9 + k * 3, 7.8, 3.8), (78, 84, 78), "CorrodedMetal")
            for s in (-(wr + 1.7), wr + 1.7):
                pb.box("Decor", "WheelPillar", (1.6, 17, 1.6), (s, 8.5, 1), frame_c, "Metal")
                pb.box("Decor", "WheelPillarStrip", (0.4, 15, 0.2), (s, 8.5, 0.1), gold, "Neon", props={"Transparency": 0.15})
            pb.box("Decor", "WheelAxle", (2 * wr + 3.4, 0.9, 0.9), (0, wy, 1.2), frame_c, "Metal")
            pb.box("Decor", "WheelHeader", (2 * wr + 6, 1.8, 1.8), (0, 17.8, 1), frame_c, "Metal")
            pb.sign2("WheelSign", (15, 3.6, 0.4), (0, 20.4, 0.6), "GLÜCKSRAD", "TÄGLICH GRATIS DREHEN", (30, 28, 26), gold,
                     (236, 230, 214), glow=gold)
            for k in range(13):  # Glühbirnen am Schild-Rahmen
                pb.add("Decor", "MarqueeBulb", (0.5, 0.5, 0.5), (-7.2 + k * 1.2, 22.4, 0.3), (255, 226, 150), "Neon",
                       props={"Shape": "Ball", "CanCollide": False})
                pb.add("Decor", "MarqueeBulb", (0.5, 0.5, 0.5), (-7.2 + k * 1.2, 18.4, 0.3), (255, 226, 150), "Neon",
                       props={"Shape": "Ball", "CanCollide": False})
            pb.add("Decor", "WheelSpot", (1, 1, 1), (0, wy, 0), gold, "SmoothPlastic",
                   props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
            pb.box("Decor", "WheelConsole", (5.6, 2.2, 1.6), (0, 1.1 + 0.6, -7.4), (36, 39, 46), "Metal")
            pb.box("Decor", "WheelConsoleStrip", (5.7, 0.2, 1.7), (0, 2.1 + 0.6, -7.4), gold, "Neon", props={"Transparency": 0.2})
            pb.holo_panel("Decor", "WheelBoard", (5.2, 1.9, 0.15), (0, 2.75 + 0.6, -7.55), angles=bm.yaw_tilt(0, 35))
            for s in (-1, 1):
                pb.box("Decor", "StageLightPole", (0.5, 12, 0.5), (s * 9.6, 6, -6), frame_c, "Metal")
                pb.box("Decor", "StageLight", (1.2, 1, 1.4), (s * 9.6, 12.2, -5.4), (255, 244, 220), "Neon", angles=(-25, -s * 30, 0),
                       children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                           "Face": "Back", "Range": 24, "Brightness": 1.4, "Angle": 50, "Color": bm.rgb(255, 240, 220)}}])
                pb.box("Cover", "Barrel", (2.2, 3, 2.2), (s * 10.5, 1.5, 2.6), (176, 60, 40), "Metal")
            pb.floor_text("WheelFloorLabel", (10, 0.1, 2.4), (0, 0.65, -4.6), "E AM PULT", gold, yaw=0)
        self._feature(build, x, z, yaw)

    def outfitter(self, x, z, yaw):
        """AUSRÜSTER: offener Container-Laden mit drei Vitrinen (Angebote des Tages setzt der Client), Theke vorn (E: Shop),
        Markise, Schild; links daneben der Kit-Händler (Punkt Kits)."""
        bm = self.bm

        def build(pb):
            shell, accent = (64, 86, 104), (120, 185, 235)
            L, D, H = 20, 9, 8.5
            pb.box("Decor", "ShopFloor", (L, 0.4, D), (0, 0.2, 0), (70, 70, 72), "DiamondPlate")
            pb.box("Decor", "ShopBack", (L, H, 0.4), (0, H / 2, D / 2), shell, "CorrodedMetal")
            for s in (-1, 1):
                pb.box("Decor", "ShopSide", (0.4, H, D), (s * L / 2, H / 2, 0), shell, "CorrodedMetal")
            pb.box("Decor", "ShopRoof", (L + 0.4, 0.4, D + 0.4), (0, H + 0.2, 0), bm.lighten(shell, -0.15), "CorrodedMetal")
            pb.box("Decor", "ShopAwning", (L + 2, 0.25, 5), (0, H - 0.6, -D / 2 - 2.2), (176, 60, 40), "Fabric", angles=(-12, 0, 0))
            for k in range(6):
                pb.box("Decor", "ShopAwningStripe", (1.6, 0.27, 5), (-8.5 + k * 3.4, H - 0.58, -D / 2 - 2.2), (226, 214, 190),
                       "Fabric", angles=(-12, 0, 0))
            for s in (-1, 1):
                pb.box("Decor", "ShopAwningPost", (0.4, H - 1.6, 0.4), (s * (L / 2 + 0.6), (H - 1.6) / 2, -D / 2 - 4.2), DARK, "Metal")
            for k, vx in enumerate((-6, 0, 6), start=1):
                vz = 1.6
                pb.box("Decor", "VitrineBase", (4.4, 2.5, 4.4), (vx, 1.45, vz), (32, 35, 41), "Metal")
                pb.box("Decor", "VitrineBaseStrip", (4.5, 0.25, 4.5), (vx, 2.6, vz), accent, "Neon", props={"Transparency": 0.2})
                pb.box("Decor", "VitrineGlass", (4, 4.4, 4), (vx, 4.9, vz), (200, 225, 240), "Glass",
                       props={"Transparency": 0.8})
                pb.box("Decor", "VitrineCap", (4.4, 0.4, 4.4), (vx, 7.3, vz), (32, 35, 41), "Metal")
                pb.box("Decor", "VitrineLight", (2.6, 0.1, 2.6), (vx, 7.05, vz), (255, 248, 235), "Neon",
                       children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                           "Face": "Bottom", "Range": 10, "Brightness": 1.1, "Angle": 70, "Color": bm.rgb(255, 245, 230)}}])
                pb.add("Decor", "ShopDisplay" + str(k), (1, 1, 1), (vx, 4.8, vz), accent, "SmoothPlastic",
                       props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
                pb.holo_panel("Decor", "ShopPlaque" + str(k), (3.8, 1.4, 0.2), (vx, 1.4, vz - 2.3))
            pb.box("Decor", "ShopCounter", (14, 3.4, 2.4), (0, 2.1, -3.2), (110, 88, 62), "WoodPlanks")
            pb.box("Decor", "ShopCounterTop", (14.4, 0.3, 2.8), (0, 3.9, -3.2), (60, 48, 36), "Wood")
            pb.box("Decor", "ShopCounterStrip", (14.2, 0.25, 0.15), (0, 3.2, -4.45), accent, "Neon", props={"Transparency": 0.2})
            pb.box("Decor", "ShopTerminal", (2.4, 1.6, 0.3), (3.5, 4.8, -3.2), (22, 25, 30), "SmoothPlastic", angles=(-15, 180, 0))
            pb.sign2("ShopSign", (16, 3, 0.4), (0, H + 2, -D / 2 + 0.2), "AUSRÜSTER",
                     "SHOP  ·  ANGEBOTE DES TAGES  ·  AN DER THEKE E DRÜCKEN", (30, 32, 36), GOLD, (236, 239, 243), glow=GOLD)
            for s in (-1, 1):
                pb.box("Decor", "ShopSignPost", (0.4, 3, 0.4), (s * 7, H + 1.5, -D / 2 + 0.6), DARK, "Metal")
        self._feature(build, x, z, yaw)
        # Kit-Händler links vom Laden (vom Platz aus gesehen), eigener Tisch unter grüner Plane
        f, _ = self.frame(x, z, yaw)
        kx, _, kz = f(17, 0, -1)
        self.kit_vendor(kx, kz, yaw)

    def kit_vendor(self, x, z, yaw):
        """Kit-Händler: Tisch mit Kisten, grünes Schild KITS, Händler mit Mütze (Punkt Kits: KitService)."""
        b = self.b
        f, box = self.frame(x, z, yaw)
        green, wood, dark = (70, 150, 90), (120, 92, 62), (44, 46, 48)
        box("Cover", "KitTable", (7, 0.4, 2.2), (0, 3, -1.4), wood, "WoodPlanks")
        for lx in (-3.1, 3.1):
            box("Decor", "KitTableLeg", (0.4, 2.8, 1.8), (lx, 1.4, -1.4), dark, "Metal")
        for lx, col in ((-2.2, green), (0, (200, 170, 70)), (2.2, (90, 130, 190))):
            box("Decor", "KitBox", (1.6, 1.1, 1.3), (lx, 3.75, -1.4), col, "SmoothPlastic")
            box("Decor", "KitBoxBand", (0.3, 1.15, 1.35), (lx, 3.75, -1.4), (240, 220, 120), "SmoothPlastic")
        for lx in (-3.6, 3.6):
            box("Decor", "KitPole", (0.35, 9, 0.35), (lx, 4.5, 1.6), dark, "Metal")
        box("Decor", "KitAwning", (8, 0.25, 4.4), (0, 9, -0.2), green, "Fabric", extra=(-8, 0, 0))
        b.sign("KitSign", (5.4, 1.6, 0.25), f(0, 7.6, 1.5), "KITS", green, (245, 245, 235), angles=(0, yaw, 0))
        self.npc_figure(box, 0, 0.6, jacket=(60, 120, 76), pants=(40, 42, 48), cap=(46, 96, 60))
        b.add("Stands", "Kits", (2, 2, 2), f(0, 2.5, -4), green, "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    def hall_of_fame(self, x, z, yaw):
        """RUHMESWAND: Gerüst mit vier Bestenlisten (Holo-Tafeln vor dunklen Platten; die Listen schreibt der Client),
        Titel oben, Strahler, Holzdeck davor."""
        bm = self.bm

        def build(pb):
            frame_c = (60, 62, 66)
            pb.box("Decor", "FameDeck", (48, 0.5, 7), (0, 0.25, -2.5), PLANK, "WoodPlanks")
            pb.box("Decor", "FameWall", (48, 15, 0.6), (0, 7.5, 1.2), (52, 50, 48), "CorrodedMetal")
            for k in range(9):
                lx = -24 + k * 6
                pb.box("Decor", "FameScaffold", (0.5, 19, 0.5), (lx, 9.5, 1.9), frame_c, "Metal")
            for y in (0.8, 9.2, 17.6):
                pb.box("Decor", "FameScaffoldBar", (48.5, 0.4, 0.4), (0, y, 1.9), frame_c, "Metal")
            for board, color, px in (("Elo", (200, 166, 92), -16.5), ("Kills", (206, 70, 58), -5.5),
                                     ("Level", (96, 164, 214), 5.5), ("Wins", (112, 178, 112), 16.5)):
                pb.box("Decor", "BoardBacking", (10.6, 9.2, 0.3), (px, 8.6, 0.75), (20, 22, 26), "SmoothPlastic")
                pb.holo_panel("Decor", "Leaderboard_" + board, (10, 8.5, 0.15), (px, 8.6, 0.4),
                              props={"Transparency": 0.82})
                pb.box("Decor", "HoloFrameTop", (10.6, 0.25, 0.2), (px, 13.25, 0.5), color, "Neon", props={"Transparency": 0.1})
                pb.box("Decor", "HoloFrameBottom", (10.6, 0.2, 0.2), (px, 3.95, 0.5), color, "Neon", props={"Transparency": 0.3})
            pb.sign2("BoardsTitle", (26, 3.6, 0.4), (0, 16.4, 0.7), "RUHMESWAND", "BESTENLISTEN  ·  GLOBALE TOP 10",
                     (30, 32, 36), GOLD, (236, 239, 243), glow=GOLD)
            for s in (-1, 1):
                pb.box("Decor", "FameLight", (1.2, 1, 1.4), (s * 11, 19.6, -2), (255, 244, 220), "Neon", angles=(-50, 0, 0),
                       children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                           "Face": "Back", "Range": 26, "Brightness": 1.2, "Angle": 70, "Color": bm.rgb(255, 240, 220)}}])
                pb.box("Decor", "FameLightArm", (0.3, 0.3, 4), (s * 11, 19.4, 0), frame_c, "Metal")
        self._feature(build, x, z, yaw)

    def podium_wall(self, x, z, yaw):
        """SIEGERPODEST der Top 3 (Statuen setzt der Server an Podium1-3) vor einer Ehrenwand mit LAGEBERICHT
        (MissionBoard, schreibt der Client) und Bildtafel (PhotoBoard)."""
        def build(pb):
            frame_c, gold = (60, 62, 66), GOLD
            pb.box("Decor", "PodiumPlinth", (23, 0.5, 8), (0, 0.25, 0), (32, 35, 41), "Metal")
            for place, off, h, color in ((1, 0, 3.2, gold), (2, 6.8, 2.3, (190, 194, 200)), (3, -6.8, 1.5, (180, 120, 70))):
                pb.box("Decor", "PodiumBase", (5.6, h, 5.6), (off, 0.5 + h / 2, 0), (32, 35, 41), "Metal")
                pb.box("Decor", "PodiumTop", (5.8, 0.35, 5.8), (off, 0.68 + h, 0), color, "Metal")
                pb.add("Decor", "Podium" + str(place), (2, 0.2, 2), (off, 0.95 + h, 0), color, "SmoothPlastic",
                       props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
                pb.sign("PodiumNumber", (1.6, 1.3, 0.3), (off, 0.5 + h / 2, -2.95), str(place), (32, 35, 41), color)
            pb.add("Decor", "PodiumGlow", (0.2, 7, 7), (0, 0.55, 0), gold, "Neon", angles=(0, 0, 90),
                   props={"Shape": "Cylinder", "Transparency": 0.6, "CanCollide": False})
            # Ehrenwand dahinter
            pb.box("Decor", "HonorWall", (36, 24, 0.6), (0, 12, 6.5), (58, 56, 52), "CorrodedMetal")
            for k in range(7):
                pb.box("Decor", "HonorScaffold", (0.5, 26, 0.5), (-18 + k * 6, 13, 7.2), frame_c, "Metal")
            pb.sign2("PodiumTitle", (20, 3.6, 0.4), (0, 9.4, 6.0), "SIEGERPODEST · TOP 3",
                     "DIE BESTEN SPIELER NACH ELO", (30, 32, 36), gold, (236, 239, 243), glow=gold)
            pb.box("Decor", "MissionBacking", (22.6, 9.1, 0.3), (-6, 17.6, 6.05), (20, 22, 26), "SmoothPlastic")
            pb.holo_panel("Decor", "MissionBoard", (22, 8.5, 0.5), (-6, 17.6, 5.7))
            pb.box("Decor", "PhotoBoardFrame", (11, 11, 0.4), (12, 17.2, 6.05), (40, 42, 46), "Metal")
            pb.box("Decor", "PhotoBoard", (10, 10, 0.4), (12, 17.2, 5.8), (22, 25, 30), "SmoothPlastic", angles=(0, 180, 0))
            for y in (11.4, 23.4):
                pb.box("Decor", "HonorTrim", (36.4, 0.3, 0.3), (0, y, 6.1), gold, "Neon", props={"Transparency": 0.25})
        self._feature(build, x, z, yaw)

    # ---------- Viertel ----------
    def bazaar(self):
        """NO: BASAR. Vorne am Ringweg Waffen und Sani, dazwischen die Garküche; dahinter Trödelstände unter Planen,
        Lichterketten über der Gasse; hinten an der Mauer der Schieber (Punkt Stand_Red)."""
        b, rng = self.b, self.rng
        self.arc_pad("BazaarGround", 66, 108, 8, 82, (118, 104, 84), "Ground", 0.06, step=6)
        gun = (40, 42, 46)
        x, z, yaw = self.at_center(80, 26)
        self.trader("Stand_Weapons", "WAFFEN & MUNITION", "ANKAUF · VERKAUF", *self._face(x, z),
                    [(-4, 6.0, 4.6, 0.7, 0.4, gun, "Metal"), (1, 6.0, 4.0, 0.6, 0.4, gun, "Metal"), (-4, 4.2, 3.6, 0.6, 0.4, gun, "Metal"),
                     (4, 4.4, 3.0, 1.6, 1.6, (84, 98, 70), "Metal")], accent=(150, 70, 44))
        x, z, yaw = self.at_center(80, 64)
        self.trader("Stand_Items", "SANI", "VERBAND · MEDIZIN · WESTEN", *self._face(x, z),
                    [(-4, 4.2, 2.4, 1.6, 1.4, (210, 206, 196), "SmoothPlastic"), (-1, 4.2, 2.4, 1.6, 1.4, (180, 50, 44), "SmoothPlastic"),
                     (2, 6.0, 3.0, 1.6, 1.4, (86, 96, 66), "Fabric")], accent=(70, 130, 90))
        self.soup_kitchen(*self.at_center(84, 45))
        # zweite Reihe: Trödelstände (ohne Punkt), Kisten und Fässer dazwischen
        for th, title, sub, tarp in ((22, "SCHROTT & TEILE", "ALLES MUSS RAUS", (90, 98, 110)),
                                     (45, "FUNK & BATTERIEN", "FREQUENZ 104.5", (150, 120, 60)),
                                     (68, "STOFFE", "MÄNTEL · DECKEN", (120, 60, 70))):
            self.junk_stall(*self.at_center(104, th), title, sub, tarp)
        for th in (12, 34, 56, 78):
            x, z = P(rng.uniform(92, 98), th)
            if rng.random() < 0.5:
                self.crates(x, z, n=rng.randint(2, 3))
            else:
                self.barrels(x, z, n=3)
        for th0, th1 in ((14, 38), (38, 52), (52, 76)):  # Lichterketten über der Gasse
            for r in (90,):
                self.string_lights(P(r, th0), P(r, th1), 8.5, n=9)
        for th in (14, 38, 52, 76):
            x, z = P(90, th)
            b.box("Decor", "LightPole", (0.4, 9, 0.4), (x, 4.5, z), PLANK_DARK, "Wood")
        for th, title, sub, tarp in ((19, "WERKZEUG", "REPARIERT ALLES", (84, 98, 70)),
                                     (31, "BÜCHER & KARTEN", "ALTE STADTPLÄNE", (70, 84, 104)),
                                     (59, "ELEKTRONIK", "FUNKGERÄTE · AKKUS", (60, 62, 66)),
                                     (71, "TALISMANE", "BRINGT GLÜCK", (130, 84, 60))):
            self.junk_stall(*self.at_center(121, th), title, sub, tarp)
        for th in (25, 65):
            self.fire_barrel(*P(112, th))
        self.schieber(*self.at_center(122, 45))

    def _face(self, x, z):
        """(x, z, fx, fz) mit Blick zur Mitte – für trader() und Co."""
        return x, z, -x, -z

    def soup_kitchen(self, x, z, yaw):
        """Garküche: großer Topf über dem Feuer, Theke, Bänke, Schild."""
        b, rng = self.b, self.rng
        f, box = self.frame(x, z, yaw)
        box("Buildings", "KitchenRoof", (14, 0.3, 9), (0, 8, 0), (90, 92, 94), "CorrodedMetal", extra=(4, 0, 0))
        for s in (-1, 1):
            for lz in (-4, 4):
                box("Decor", "KitchenPost", (0.5, 8, 0.5), (s * 6.6, 4, lz), PLANK_DARK, "Wood")
        box("Cover", "KitchenCounter", (11, 3, 1.6), (0, 1.5, -3.6), PLANK, "WoodPlanks")
        tx, _, tz = f(0, 0, 1.5)
        b.cylinder("Decor", "SoupPot", 4.2, 3, (tx, 2.6, tz), (60, 62, 64), material="Metal")
        b.cylinder("Decor", "Soup", 3.8, 0.2, (tx, 4.05, tz), (150, 100, 50), material="SmoothPlastic")
        self.fire(tx, tz, y=-1.6, size=3)
        for lz in (-8, -11):
            box("Cover", "KitchenBench", (9, 1.1, 1.4), (0, 0.6, lz), PLANK_DARK, "WoodPlanks")
        self.b.sign2("KitchenSign", (8, 2, 0.25), f(0, 9.5, -4.4), "GARKÜCHE", "HEUTE: EINTOPF", (150, 140, 120), (40, 30, 26),
                     (60, 50, 44), angles=(0, yaw, rng.uniform(-3, 3)))
        self.survivor(*self._xz(f, 2, 3), yaw)

    def junk_stall(self, x, z, yaw, title, sub, tarp):
        """Trödelstand: Tisch aus Paletten mit Kram, Plane auf Stangen, Schild."""
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
        """Schwarzmarkt hinten im Basar an der Mauer: schwarzer Transporter mit offener Seitentür (Kisten, rotes Licht),
        daneben der Schieber mit Kapuze (Punkt Stand_Red: Händler für Rote-Zone-Punkte), Planen als Sichtschutz."""
        b = self.b
        f, box = self.frame(x, z, yaw)  # lokal -Z = zur Mitte
        black, trim = (26, 27, 30), (60, 62, 66)
        # Transporter quer (Nase nach lokal +X), offene Seite zur Mitte
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
        for lx in (-9, 10):  # Planen links und rechts (Sichtschutz)
            box("Decor", "ScreenTarp", (0.2, 6, 7), (lx, 3.4, -1), (50, 54, 48), "Fabric", extra=(0, 0, 3))
            box("Decor", "ScreenPole", (0.3, 7, 0.3), (lx, 3.5, -4.5), PLANK_DARK, "Wood")
        b.add("Stands", "Stand_Red", (2, 2, 2), f(-2.2, 2.5, -7.2), (200, 60, 60), "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    def motor_pool(self):
        """SO: FUHRPARK. Werkstatt (Stand_Vehicles) mit Hebebühne, Busbahnhof (Travel) mit Bus, Landeplatz, Tanklager,
        Parkplatz mit Fahrzeugen; Boden aus altem Asphalt mit Markierungen."""
        b, rng = self.b, self.rng
        self.arc_pad("MotorPoolGround", 66, 128, 98, 172, (70, 72, 74), "Asphalt", 0.06, step=6)
        self.workshop(*self.at_center(86, 120))
        x, z = P(84, 158)
        self.travel_stop("Travel", "BUSBAHNHOF", x, z, -x, -z)
        bx, bz, byaw = self.at_center(98, 162)
        f, box = self.frame(bx, bz, byaw + 90)  # Bus quer zum Ringweg
        col = (196, 176, 70)
        box("Cover", "BusBody", (7.4, 7.4, 24), (0, 4.6, 0), col, "Metal")
        box("Decor", "BusWindows", (7.5, 2.4, 21), (0, 6, 0.5), (40, 52, 60), "Glass")
        box("Decor", "BusStripe", (7.5, 0.6, 24.1), (0, 3.6, 0), (60, 62, 66), "SmoothPlastic")
        box("Decor", "BusDestination", (5, 1, 0.2), (0, 7.6, -12.05), (255, 170, 60), "Neon")
        for lz in (-8, 8):
            for s in (-1, 1):
                box("Decor", "BusWheel", (1, 2.4, 2.4), (s * 3.6, 1.2, lz), (26, 26, 26), "Rubber", props={"Shape": "Cylinder"})
        # Landeplatz
        hx, hz = P(114, 138)
        b.add("Decor", "Helipad", (0.4, 24, 24), (hx, 0.25, hz), (96, 98, 96), "Concrete", angles=(0, 0, 90),
              props={"Shape": "Cylinder"})
        b.floor_text("HelipadH", (9, 0.1, 9), (hx, 0.5, hz), "H", (230, 200, 90), yaw=self.yaw_to(-hx, -hz) + 180)
        for k in range(8):
            a = 2 * math.pi * k / 8
            b.box("Decor", "PadLight", (0.6, 0.4, 0.6), (hx + math.sin(a) * 11.4, 0.55, hz + math.cos(a) * 11.4), (120, 220, 120),
                  "Neon", props={"CanCollide": False})
        wx, wz = P(126, 128)
        b.box("Decor", "Windsock", (0.3, 8, 0.3), (wx, 4, wz), (150, 150, 150), "Metal")
        b.box("Decor", "WindsockCone", (1, 1, 3.2), (wx, 7.6, wz + 1.6), (230, 110, 40), "Fabric")
        # Tanklager
        tx, tz, tyaw = self.at_center(116, 106)
        f, box = self.frame(tx, tz, tyaw)
        for k in range(2):
            b.cylinder("Buildings", "FuelTank", 6, 8, f(-4.5 + k * 9, 4.3, 0), (150, 146, 138), material="Metal")
            b.cylinder("Decor", "FuelTankBand", 6.2, 0.4, f(-4.5 + k * 9, 6.5, 0), (190, 60, 40), material="Metal")
        box("Decor", "FuelPipe", (12, 0.6, 0.6), (0, 1.2, -3.4), (70, 72, 74), "Metal")
        box("Cover", "FuelBund", (16, 1.2, 0.8), (0, 0.6, -4.4), (130, 128, 120), "Concrete")
        self.b.sign2("FuelSign", (6, 1.6, 0.2), f(0, 2.6, -4.85), "DIESEL", "RAUCHEN VERBOTEN", (150, 140, 120), (40, 30, 26),
                     (150, 40, 34), angles=(0, tyaw, 0))
        # Parkplatz: Markierungen und abgestellte Fahrzeuge
        for k, th in enumerate((102, 109, 116, 147, 154)):
            x, z, yaw = self.at_center(100, th)
            b.box("Ground", "ParkingLine", (0.4, 0.05, 11), (x, 0.08, z), (210, 206, 190), "SmoothPlastic", angles=(0, yaw + 90 + 90, 0))
        for th in (105.5, 112.5):
            x, z, yaw = self.at_center(100, th)
            self.car(x, z, yaw, burned=False, y=0.0)
        f, box = self.frame(*self.at_center(100, 150.5)[:2], self.at_center(100, 150.5)[2])
        box("Cover", "Pickup", (5.6, 3, 12), (0, 2.1, 0), (90, 100, 70), "Metal")
        box("Cover", "PickupCab", (5.2, 2.4, 4.6), (0, 4.6, -2.4), (80, 90, 62), "Metal")
        for lz in (-3.8, 3.8):
            for s in (-1, 1):
                box("Decor", "PickupWheel", (1, 2.6, 2.6), (s * 2.9, 1.3, lz), (24, 24, 26), "Rubber", props={"Shape": "Cylinder"})
        for th in (132, 144):
            x, z = P(rng.uniform(72, 76), th)
            self.barrels(x, z, n=3)
        self.floodlight(*P(124, 116), *P(-1, 116), 13)
        self.fuel_station(*self.at_center(80, 139))
        for th in (157, 166):  # Schrottecke an der Mauer
            x, z = P(rng.uniform(122, 126), th)
            self.car(x, z, rng.uniform(0, 360), burned=True, y=0.0)
        for k in range(3):
            x, z = P(126, 150 + k * 2.6)
            for j in range(rng.randint(2, 4)):
                b.add("Cover", "Tire", (1, 2.6, 2.6), (x, 0.5 + j, z), (24, 24, 26), "Rubber", angles=(0, 0, 90),
                      props={"Shape": "Cylinder"})

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

    def workshop(self, x, z, yaw):
        """KFZ-WERKSTATT: Halle aus zwei Containern mit Wellblechdach, offen zum Weg; Hebebühne mit Auto, Reifenstapel,
        Werkzeugwand, Ölfässer; Punkt Stand_Vehicles vorn."""
        b, rng = self.b, self.rng
        f, box = self.frame(x, z, yaw)
        col = (60, 86, 110)
        for s in (-1, 1):
            box("Buildings", "WorkshopContainer", (8, 8.5, 18), (s * 10, 4.25, 0), col, "CorrodedMetal")
        box("Buildings", "WorkshopBack", (12, 8.5, 0.5), (0, 4.25, 8.8), self.bm.lighten(col, -0.1), "CorrodedMetal")
        box("Buildings", "Roof", (30, 0.5, 20), (0, 9.6, 0), (90, 92, 94), "CorrodedMetal", extra=(0, 0, 0))
        box("Ground", "WorkshopFloor", (12, 0.2, 18), (0, 0.12, 0), (88, 88, 86), "Concrete")
        # Hebebühne mit Auto
        for s in (-1, 1):
            box("Decor", "LiftPost", (0.8, 6, 0.8), (s * 4.2, 3, 2), (200, 160, 40), "Metal")
            box("Decor", "LiftArm", (3, 0.4, 0.6), (s * 2.8, 3.4, 2), (200, 160, 40), "Metal")
        box("Cover", "LiftCar", (5, 2.2, 10.5), (0, 4.9, 2), (130, 60, 50), "Metal")
        box("Decor", "LiftCarCabin", (4.6, 1.8, 5), (0, 6.9, 2.6), (110, 50, 42), "Metal")
        box("Decor", "ToolWall", (11, 4, 0.2), (0, 5.2, 8.4), (70, 54, 40), "WoodPlanks")
        for k in range(7):
            box("Decor", "Tool", (0.3, rng.uniform(1, 2.2), 0.2), (-4.5 + k * 1.5, 5.4, 8.25), (140, 140, 146), "Metal")
        for lx, lz in ((-4.8, -6), (4.8, -5)):
            for j in range(3):
                b.add("Cover", "Tire", (1, 2.6, 2.6), f(lx, 0.5 + j * 1.0, lz), (24, 24, 26), "Rubber", angles=(0, 0, 90),
                      props={"Shape": "Cylinder"})
        self.barrels(*self._xz(f, -12, -12), n=2, color=(40, 40, 42))
        self.b.sign2("StandSign_Stand_Vehicles", (14, 2.4, 0.3), f(0, 11.4, -10), "KFZ-WERKSTATT", "FAHRZEUGE · REPARATUR",
                     (30, 32, 36), (110, 176, 230), (220, 220, 214), angles=(0, yaw, 0), glow=(110, 176, 230))
        box("Decor", "WorkshopLamp", (8, 0.3, 0.6), (0, 9.1, 0), (236, 240, 255), "Neon",
            children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 22, "Brightness": 1.2,
                                                                                 "Color": self.bm.rgb(230, 236, 255)}}])
        b.add("Stands", "Stand_Vehicles", (2, 2, 2), f(0, 2.5, -13), (110, 176, 230), "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
        self.npc_figure(box, -2.6, -9.4, jacket=(60, 70, 100), pants=(44, 48, 60), cap=(40, 50, 80))

    def depot(self):
        """SW: DEPOT. Lager-Container (Stash), Tauschmarkt (Stand_Market), dazwischen das Tor zur MARKTHALLE (Portal_Market),
        dahinter gestapelte Container und ein Portalkran."""
        b, rng = self.b, self.rng
        self.arc_pad("DepotGround", 66, 128, 188, 262, (96, 96, 92), "Concrete", 0.06, step=6)
        x, z = P(86, 198)
        self.stash_container(x, z, -x, -z, length=18)
        x, z = P(82, 252)
        self.trader("Stand_Market", "TAUSCHMARKT", "SPIELER HANDELN", x, z, -x, -z,
                    [(-4, 4.4, 2.4, 1.8, 1.4, (226, 196, 90), "Metal"), (0, 4.4, 2.4, 1.6, 1.4, (90, 130, 190), "Metal"),
                     (3.6, 5.8, 2.6, 1.6, 1.4, (200, 196, 186), "Fabric")], accent=(220, 170, 60))
        self.market_gate(*self.at_center(100, 225))
        # Container-Stapel hinten (zwei hoch), Portalkran darüber
        cols = ((60, 86, 70), (110, 60, 48), (70, 84, 104), (150, 120, 60), (84, 98, 70))
        for th in (196, 209, 241, 254):
            x, z, yaw = self.at_center(121, th)
            self.container(x, z, yaw, rng.choice(cols), doors=rng.random() < 0.5)
            if rng.random() < 0.7:
                self.container(x, z, yaw + rng.uniform(-4, 4), rng.choice(cols), y=8.5)
        for th in (188, 262):
            x, z, yaw = self.at_center(104, th)
            self.container(x, z, yaw + 90, rng.choice(cols))
        gx, gz, gyaw = self.at_center(121, 225)
        f, box = self.frame(gx, gz, gyaw)
        for s in (-1, 1):
            box("Buildings", "CraneLeg", (1.2, 24, 1.2), (s * 14, 12, -3), (200, 150, 40), "Metal")
            box("Buildings", "CraneLeg", (1.2, 24, 1.2), (s * 14, 12, 3), (200, 150, 40), "Metal")
        box("Buildings", "CraneBeam", (30, 1.8, 7.2), (0, 24.6, 0), (200, 150, 40), "Metal")
        box("Decor", "CraneHook", (0.2, 8, 0.2), (3, 20, 0), (40, 40, 40), "Metal")
        box("Decor", "CraneLight", (1, 1, 1), (0, 25.8, 0), (255, 60, 40), "Neon")
        for th in (205, 245):
            x, z = P(rng.uniform(96, 104), th)
            self.crates(x, z, n=3)
        for th in (210, 240):  # Paletten-Stapel und Gabelstapler am Ringweg
            x, z, yaw = self.at_center(76, th)
            f, box = self.frame(x, z, yaw)
            for lx in (-3, 0, 3):
                for j in range(rng.randint(1, 3)):
                    box("Cover", "Pallet", (2.6, 0.5, 2.6), (lx, 0.25 + j * 1.6, 0), (150, 120, 84), "WoodPlanks")
                    box("Cover", "PalletLoad", (2.4, 1.1, 2.4), (lx, 1.05 + j * 1.6, 0), rng.choice(((180, 160, 120), (90, 100, 80), (120, 120, 114))), "Fabric")
            self.forklift(*self._xz(f, 0, 6), yaw + rng.uniform(-30, 30))

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

    def market_gate(self, x, z, yaw):
        """Tor zur MARKTHALLE: zwei Container-Türme, Leuchtrahmen, Kraftfeld, Schild mit Spielerzahl (GateCount_Market),
        Bodenschrift; Portal_Market davor (Gruppe Portals)."""
        def build(pb):
            rap, frame_c = (86, 214, 170), (28, 31, 37)
            gw, gh = 12, 13
            for s in (-1, 1):
                pb.box("Decor", "GateTower", (6, gh + 4, 8), (s * (gw / 2 + 3.2), (gh + 4) / 2, 2), (70, 84, 104), "CorrodedMetal")
                pb.box("Decor", "GateStrip", (0.5, gh, 0.4), (s * (gw / 2 + 0.1), gh / 2 + 1, -2.1), rap, "Neon")
            pb.box("Decor", "GateHeader", (gw + 12.4, 3, 8), (0, gh + 2.5, 2), frame_c, "Metal")
            pb.box("Decor", "GateGlow", (gw, gh, 0.3), (0, gh / 2, 2), rap, "ForceField",
                   props={"Transparency": 0.25, "CanCollide": False},
                   children=[{"Name": "Light", "ClassName": "PointLight",
                              "Properties": {"Range": 18, "Brightness": 0.9, "Color": self.bm.rgb(*rap)}}])
            pb.box("Decor", "GateBack", (gw + 0.4, gh, 0.4), (0, gh / 2, 5.8), (20, 22, 26), "SmoothPlastic")
            pb.sign2("Sign_Market", (17, 4.6, 0.4), (0, gh + 6.4, 0), "MARKTHALLE", "STÄNDE · HANDEL · RAP", (30, 32, 36), rap,
                     (236, 239, 243), glow=rap)
            pb.holo_panel("Decor", "GateCount_Market", (9, 1.6, 0.3), (0, gh + 2.5, -2.2))
            pb.add("Portals", "Portal_Market", (gw - 1, 0.3, 6), (0, 0.4, -1), rap, "Neon",
                   props={"CanCollide": False, "Transparency": 0.45})
            pb.floor_text("FloorLabel_Market", (11, 0.1, 3), (0, 0.35, -7), "MARKT", rap, yaw=0)
            pb.box("Decor", "GateRamp", (gw + 4, 0.3, 10), (0, 0.2, -3), (40, 44, 48), "DiamondPlate")
        self._feature(build, x, z, yaw)
        # Weg vom Ringweg zum Tor
        self.arc_pad("Sidewalk", RING_R + RING_W / 2 - 1, 95, 221, 229, GRAVEL, "Pebble", 0.12, step=8)

    def living_quarter(self):
        """NW: WOHNLAGER. Lagerfeuer mit Überlebenden und Bänken, Zelte im Halbkreis, Sanitätszelt, Gemüsebeete,
        Wäscheleinen, Wasserturm, Stromaggregat mit Flutlicht, hinten das VERSTECK (Punkt Hideout)."""
        b, rng = self.b, self.rng
        self.arc_pad("CampGround", 66, 128, 278, 352, (106, 98, 80), "Ground", 0.06, step=6)
        fx, fz = P(92, 315)
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
        # Zelte: innere Reihe am Ringweg und äußere Reihe an der Mauer, zum Feuer hin offen
        tent_cols = ((84, 98, 70), (60, 86, 110), (150, 120, 60), (120, 60, 50), (100, 104, 96))
        for r, ths in ((76, (302, 328, 340)), (114, (284, 296, 334, 346)), (128, (308, 336))):
            for th in ths:
                x, z = P(r, th)
                self.tent(x, z, self.yaw_to(fx - x, fz - z), rng.choice(tent_cols))
        self.med_tent(*self.at_center(78, 288))
        self.mess_tent(*self.at_center(100, 291))
        self.garden(*self.at_center(106, 346))
        for th in (304, 326):  # Wäscheleinen zwischen den Zeltreihen
            x0, z0 = P(98, th - 4)
            x1, z1 = P(98, th + 4)
            for x_, z_ in ((x0, z0), (x1, z1)):
                b.box("Decor", "ClothesPole", (0.3, 7, 0.3), (x_, 3.5, z_), (90, 80, 70), "Wood")
            length = math.hypot(x1 - x0, z1 - z0)
            yaw = math.degrees(math.atan2(-(z1 - z0), x1 - x0))
            b.box("Decor", "ClothesLine", (length, 0.1, 0.1), ((x0 + x1) / 2, 6.6, (z0 + z1) / 2), (200, 200, 196), "SmoothPlastic",
                  angles=(0, yaw, 0), props={"CanCollide": False})
            for k in range(4):
                t = 0.2 + k * 0.2
                b.box("Decor", "Laundry", (1.8, 2.4, 0.1), (x0 + (x1 - x0) * t, 5.3, z0 + (z1 - z0) * t),
                      rng.choice(((180, 60, 50), (200, 196, 186), (70, 90, 130), (120, 140, 90))), "Fabric",
                      angles=(0, yaw, 0), props={"CanCollide": False})
        # Wasserturm und Stromaggregat an der Mauer
        wx, wz = P(124, 354)
        for dx in (-2.5, 2.5):
            for dz in (-2.5, 2.5):
                b.box("Decor", "TankLeg", (0.5, 10, 0.5), (wx + dx, 5, wz + dz), (70, 60, 50), "Wood")
        b.cylinder("Buildings", "WaterTank", 8, 6, (wx, 13, wz), (60, 84, 110), material="Plastic")
        gx, gz, gyaw = self.at_center(124, 300)
        f, box = self.frame(gx, gz, gyaw)
        box("Buildings", "Generator", (10, 5, 6), (0, 2.5, 0), (84, 98, 70), "Metal")
        box("Decor", "GeneratorExhaust", (0.8, 4, 0.8), (3, 6.5, 1.6), (50, 50, 52), "Metal",
            children=[{"Name": "Smoke", "ClassName": "Smoke", "Properties": {"Color": self.bm.rgb(60, 58, 56), "Opacity": 0.15,
                                                                             "RiseVelocity": 5, "Size": 3}}])
        self.floodlight(*self._xz(f, -7, -2), fx - gx, fz - gz, 13)
        self.hideout_bunker(*self.at_center(110, 322))

    def mess_tent(self, x, z, yaw):
        """Gemeinschaftszelt: Plane auf Stangen über zwei langen Tischen mit Bänken, Laterne."""
        b, rng = self.b, self.rng
        f, box = self.frame(x, z, yaw)
        box("Decor", "MessTarp", (14, 0.2, 9), (0, 7, 0), (84, 98, 70), "Fabric", extra=(0, 0, 4))
        for sx in (-1, 1):
            for sz in (-1, 1):
                box("Decor", "MessPole", (0.4, 7, 0.4), (sx * 6.6, 3.5, sz * 4.2), PLANK_DARK, "Wood")
        for lz in (-2, 2):
            box("Cover", "MessTable", (10, 0.4, 2), (0, 2.4, lz), PLANK, "WoodPlanks")
            for d in (-1.6, 1.6):
                box("Decor", "MessBench", (10, 0.3, 0.9), (0, 1.4, lz + d), PLANK_DARK, "WoodPlanks")
        box("Decor", "MessLantern", (0.8, 1, 0.8), (0, 6.2, 0), (255, 196, 120), "Neon", children=self.warm_light(18, 1))
        self.survivor(*self._xz(f, -2, -3.6), yaw + 180, pose="sit", y=0.3)

    def med_tent(self, x, z, yaw):
        """Sanitätszelt: großes weißes Zelt mit rotem Kreuz, Feldbetten, Kisten."""
        f, box = self.frame(x, z, yaw)
        white = (214, 212, 204)
        box("Decor", "MedTentFloor", (12, 0.2, 9), (0, 0.15, 0), (80, 80, 74), "Fabric")
        self.b.add("Decor", "MedTent", (12, 6, 4.5), f(0, 3, -2.25), white, "Fabric", angles=(0, yaw, 0), cls="WedgePart")
        self.b.add("Decor", "MedTent", (12, 6, 4.5), f(0, 3, 2.25), white, "Fabric", angles=(0, yaw + 180, 0), cls="WedgePart")
        box("Decor", "MedCrossV", (1.2, 3.4, 0.1), (0, 2.6, -4.6), (200, 40, 40), "SmoothPlastic", extra=(0, 0, 0))
        box("Decor", "MedCrossH", (3.4, 1.2, 0.1), (0, 2.6, -4.6), (200, 40, 40), "SmoothPlastic")
        for lx in (-7.5, 7.5):
            box("Cover", "Cot", (2.4, 1.2, 6), (lx, 0.6, 0), (90, 96, 80), "Fabric")
        box("Cover", "MedCrate", (2.4, 1.8, 2.4), (-5, 0.9, -6), (210, 206, 196), "SmoothPlastic")

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
            box("Decor", "GardenFence", (22, 2.2, 0.3), (0, 1.1, s * 7.5), (110, 92, 70), "WoodPlanks") if s > 0 else None
        box("Decor", "ScarecrowPole", (0.4, 7, 0.4), (0, 3.5, 6), (90, 70, 50), "Wood")
        box("Decor", "ScarecrowArms", (5, 0.4, 0.4), (0, 5.6, 6), (90, 70, 50), "Wood")
        box("Decor", "ScarecrowCoat", (2.2, 2.6, 1), (0, 5, 6), (110, 90, 60), "Fabric")
        box("Decor", "ScarecrowHead", (1.3, 1.3, 1.3), (0, 7, 6), (200, 180, 120), "Fabric")

    def hideout_bunker(self, x, z, yaw):
        """VERSTECK: Eingang in einen Erdbunker (Erdhügel, Betonrahmen, Stahltür, Sandsäcke, Schild); Punkt Hideout davor."""
        b = self.b
        f, box = self.frame(x, z, yaw)
        b.add("Buildings", "BunkerMound", (8, 20, 20), f(0, 1.2, 4), (96, 90, 70), "Ground", angles=(0, yaw, 90),
              props={"Shape": "Cylinder"})
        box("Buildings", "BunkerFrame", (8, 6.5, 2), (0, 3.25, -5.4), (130, 128, 120), "Concrete")
        box("Decor", "BunkerDoor", (4, 5, 0.3), (0, 2.5, -6.45), (70, 76, 70), "DiamondPlate")
        box("Decor", "BunkerLamp", (0.8, 0.6, 0.6), (0, 6, -6.6), (255, 196, 120), "Neon", children=self.warm_light(16, 1))
        for s in (-1, 1):
            for j in range(3):
                box("Cover", "Sandbags", (3, 1.1, 1.8), (s * 5.4, 0.55 + j * 1.1, -6.2), (150, 134, 98), "Fabric")
        b.sign2("StandSign_Hideout", (7, 1.8, 0.25), f(0, 7.6, -6.5), "VERSTECK", "DEIN UNTERSCHLUPF · AUSBAUEN", (60, 52, 42),
                (200, 160, 110), (214, 206, 190), angles=(0, yaw, 0))
        b.add("Stands", "Hideout", (2, 2, 2), f(0, 2.5, -10), (200, 160, 110), "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    # ---------- Mauer, Tore, Vorfeld ----------
    def camp_wall(self):
        """Ringmauer: abwechselnd Container (teils doppelt hoch) und Wellblech-Palisaden mit Stacheldraht; vier Tore,
        Wachtürme dazwischen."""
        b, rng = self.b, self.rng
        R = CAMP_WALL_R
        gate_half = math.degrees(math.asin((GATE_W / 2 + 7.5) / R))
        cols = ((60, 86, 70), (110, 60, 48), (70, 84, 104), (150, 120, 60), (84, 98, 70), (120, 120, 112))
        for q in range(4):
            th0, th1 = q * 90 + gate_half, (q + 1) * 90 - gate_half
            n = int(round((th1 - th0) * math.pi / 180 * R / 13))
            d = (th1 - th0) / n
            for k in range(n):
                th = th0 + (k + 0.5) * d
                x, z, yaw = self.at_center(R, th)
                seg = 2 * R * math.sin(math.radians(d / 2)) + 0.6
                if k % 3 == 1:
                    self.container(x, z, yaw, rng.choice(cols), length=seg, group="Walls")
                    if rng.random() < 0.5:
                        self.container(x, z, yaw + rng.uniform(-2, 2), rng.choice(cols), y=8.5, length=seg - 1, group="Walls")
                else:
                    f, box = self.frame(x, z, yaw)
                    box("Walls", "WallPanel", (seg, 11, 1.2), (0, 5.5, 0), rng.choice(((112, 108, 100), (96, 100, 96), RUST)),
                        "CorrodedMetal")
                    for lx in (-seg / 2, 0):
                        box("Decor", "WallPost", (1, 12, 1), (lx, 6, -0.8), PLANK_DARK, "Wood")
                    b.add("Walls", "RazorWire", (seg, 1.4, 1.4), f(0, 11.8, 0), (128, 128, 126), "CorrodedMetal",
                          angles=(0, yaw + 90, 90), props={"Shape": "Cylinder"})
                    box("Decor", "WallBrace", (0.5, 0.5, 6), (rng.uniform(-3, 3), 3, -3), PLANK_DARK, "Wood", extra=(40, 0, 0))
        for th in (0, 90, 180, 270):
            self.camp_gate(th)
        for th in (45, 135, 225, 315):
            self.watch_tower(*self.at_center(R - 8, th))

    def camp_gate(self, th):
        """Tor: zwei Container-Türme, offene Stahlflügel, Balken mit Schild (außen CAMP PHOENIX, innen AUSGANG),
        Sandsack-Nester, Scheinwerfer, draußen Betonblöcke als Schikane."""
        b, rng = self.b, self.rng
        R = CAMP_WALL_R
        x, z, yaw = self.at_center(R, th)
        f, box = self.frame(x, z, yaw)  # lokal -Z = nach innen
        cont = rng.choice(((110, 60, 48), (60, 86, 110), (84, 98, 70)))
        for s in (-1, 1):
            lx = s * (GATE_W / 2 + 3.5)
            box("Walls", "GateContainer", (7, 8.5, 8), (lx, 4.25, 0), cont, "CorrodedMetal")
            box("Walls", "GateContainerTop", (7, 8.5, 8), (lx, 12.75, 0), self.bm.lighten(cont, -0.15), "CorrodedMetal")
            box("Decor", "GateLeaf", (7, 9, 0.3), (s * (GATE_W / 2 - 0.5), 4.5, -4.5), (120, 124, 126), "DiamondPlate",
                extra=(0, -s * 65, 0))
            box("Cover", "Sandbags", (5, 2.6, 2.2), (s * (GATE_W / 2 + 3.5), 1.3, -6.4), (150, 134, 98), "Fabric")
            box("Decor", "GateLamp", (1.4, 1.2, 1.6), (s * 7, 16.8, -2), (236, 236, 226), "Neon", extra=(25, 0, 0),
                children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {"Face": "Front", "Range": 50, "Brightness": 1.8,
                                                                                     "Angle": 70, "Color": self.bm.rgb(240, 240, 230)}}])
        box("Walls", "GateBeam", (GATE_W + 2, 1.4, 1.4), (0, 17.3, 0), (90, 92, 94), "Metal")
        for yaw_off, dz_ in ((180, 1.2), (0, -1.2)):  # 180: liest man von draußen, 0: von drinnen
            outside = yaw_off == 180
            b.sign2("GateSign", (13, 2.8, 0.3), f(0, 15.2, dz_), "CAMP PHOENIX" if outside else "AUSGANG",
                    "SAFE ZONE · KEIN PVP" if outside else "DRAUSSEN: ZOMBIES · PVP NACH 5 SEK.",
                    (30, 32, 30), (226, 214, 180) if outside else (220, 70, 56), (214, 212, 202), angles=(0, yaw + yaw_off, 0))
        for lx, lz in ((-5, 9), (5, 16)):
            box("Cover", "JerseyBarrier", (8, 3, 2.2), (lx, 1.5, lz), (160, 158, 150), "Concrete", extra=(0, rng.uniform(-6, 6), 0))

    def watch_tower(self, x, z, yaw):
        """Wachturm aus Gerüst: vier Beine, Plattform mit Brüstung, Dach, Suchscheinwerfer, Wache mit Gewehr."""
        b = self.b
        f, box = self.frame(x, z, yaw)
        h = 15
        for sx in (-1, 1):
            for sz in (-1, 1):
                box("Buildings", "TowerLeg", (0.6, h, 0.6), (sx * 3, h / 2, sz * 3), (70, 72, 76), "Metal")
        for y in (4, 9):
            box("Decor", "TowerBrace", (6.4, 0.3, 0.3), (0, y, -3), (70, 72, 76), "Metal", extra=(0, 0, 35))
            box("Decor", "TowerBrace", (6.4, 0.3, 0.3), (0, y, 3), (70, 72, 76), "Metal", extra=(0, 0, -35))
        box("Buildings", "TowerFloor", (8, 0.5, 8), (0, h, 0), PLANK_DARK, "WoodPlanks")
        for lz in (-4, 4):
            box("Decor", "TowerRail", (8, 2.4, 0.3), (0, h + 1.4, lz), (110, 92, 70), "WoodPlanks")
        box("Decor", "TowerRail", (0.3, 2.4, 8), (4, h + 1.4, 0), (110, 92, 70), "WoodPlanks")
        box("Decor", "TowerRail", (0.3, 2.4, 8), (-4, h + 1.4, 0), (110, 92, 70), "WoodPlanks")
        for sx in (-1, 1):
            for sz in (-1, 1):
                box("Decor", "TowerRoofPost", (0.4, 4.5, 0.4), (sx * 3.6, h + 2.4, sz * 3.6), (70, 72, 76), "Metal")
        box("Buildings", "Roof", (9, 0.4, 9), (0, h + 4.8, 0), (80, 84, 80), "CorrodedMetal")
        box("Decor", "Searchlight", (1.6, 1.4, 2), (2, h + 1.4, 3.4), (236, 240, 255), "Neon", extra=(10, 180, 0),
            children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {"Face": "Front", "Range": 60, "Brightness": 2,
                                                                                 "Angle": 30, "Color": self.bm.rgb(230, 236, 255)}}])
        wx, _, wz = f(-1.5, 0, 1.5)
        self.survivor(wx, wz, yaw + 180, y=h + 0.25, gun=True)
        box("Decor", "TowerLadder", (2, h, 0.3), (0, h / 2, -3.3), (90, 80, 70), "Wood")

    def glacis(self):
        """Vorfeld zwischen Mauer und Stadt: Panzersperren, Stacheldraht-Rollen, ausgebrannte Autos, Leichen, Warnschilder.
        Die Zufahrten vor den Toren bleiben frei."""
        b, rng = self.b, self.rng
        R = CAMP_WALL_R
        placed = []
        for k in range(70):
            th = rng.uniform(0, 360)
            if min(abs((th - g + 180) % 360 - 180) for g in (0, 90, 180, 270)) < 9:
                continue
            r = rng.uniform(R + 6, SAFE_R - 9)
            x, z = P(r, th)
            if any(math.hypot(x - px, z - pz) < 7 for px, pz in placed):
                continue
            placed.append((x, z))
            kind = rng.random()
            if kind < 0.45:  # Panzersperre (drei gekreuzte Träger)
                yaw = rng.uniform(0, 90)
                for a in ((0, 0, 55), (0, 90, 55), (55, 45, 0)):
                    b.box("Cover", "Hedgehog", (0.8, 6, 0.8), (x, 1.9, z), (60, 58, 56), "Metal", angles=(a[0], yaw + a[1], a[2]))
            elif kind < 0.75:
                x2, z2, yaw = self.at_center(r, th)
                b.add("Decor", "BarbedCoil", (7, 1.6, 1.6), (x2, 0.8, z2), (120, 120, 116), "CorrodedMetal",
                      angles=(0, yaw + 90, 90), props={"Shape": "Cylinder", "Transparency": 0.2})
            elif kind < 0.88:
                self.car(x, z, rng.uniform(0, 360), burned=True, y=0.0)
            else:
                self.corpse(x, z, y=0.4)
        for th in (45, 135, 225, 315):
            x, z, yaw = self.at_center(R + 9, th)
            self.warning_sign(x, z, yaw + 180, "SPERRZONE", "NICHT STEHEN BLEIBEN · SCHUSSFELD")

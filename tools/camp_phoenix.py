"""Camp Phoenix: die große Safe Zone in der Mitte der offenen Welt (Start des Spiels).

Ein modernes, aufgeräumtes Camp (Glas, Sichtbeton, Stahl, Leuchtstreifen; keine Bäume, keine Bänke), von innen nach außen:

  * PHÖNIXPLATZ (offen bis an die Ringstraße, Radius PLAZA_R): heller Plattenbelag mit dunklen Fugenbändern, in der
    Mitte die Spawns (frei, ohne Brunnen), Poller am Rand; keine Laternen, Fahnen oder Banner. Auf den Diagonalen:
      NO AUSRÜSTER, SO GLÜCKSRAD, NW TAUSCHMARKT als offene PAVILLONS (Flachdach, Glasseiten, Leuchtkante, Schild auf
        dem Dach, Front zur Mitte; Vitrinen ShopDisplay1-3 und Theke ShopCounter, Rad WheelSpot mit Pult, Stand_Market)
      SW RUHMESWAND frei stehend: Lagebericht und vier Bestenlisten als Bildschirme auf Stelen im Bogen, davor das
        Siegerpodest
    Die Straßen-Achsen bleiben frei: von der Mitte sieht man alle Pavillons, die Läden und die vier Tore.
  * Vier HAUPTSTRASSEN (Asphalt, Gehsteige) von der RINGSTRASSE (RING_R) zu den Toren, Zebrastreifen über die
    Ringstraße neben jeder Mündung.
  * HÄUSERRING an der Ringstraße (Fronten bei OUTER_R): moderne Flachdachhäuser, je Viertel vier mit einer Gasse in der
    Mitte; die Stationen haben einen offenen Laden mit Theke und Händler:
      NO KIT-AUSGABE · Café · Stoffe · WAFFEN & MUNITION   (Hof: Food-Court mit zwei Kiosken, der Schieber)
      SO KFZ-WERKSTATT · Ersatzteile · Hotel · APOTHEKE    (Hof: Tankstelle, Landeplatz, Parkplatz)
      SW BUSBAHNHOF · MARKTHALLE (Tor zur Markt-Welt) · LAGERHAUS  (Hof: Container und Kran)
      NW VERSTECK · Wohnhäuser · Schule                    (Hof: Sportplatz, Solarfeld, Abgang KATAKOMBEN = Dungeon)
  * Betonmauer mit Stacheldraht (CAMP_WALL_R), vier Tore, davor das Sperrgebiet (ohne Bäume und Gestrüpp).

An jeder Station steht ein Händler (Figur aus Teilen im R15-Schnitt mit Gesicht, nicht anklickbar); die Symbole über den
Stationen setzt der Client (ExtinctionClient, BUBBLE_HEIGHT) hoch über die Dächer.

Geometrie: Kompass th in Grad ab Norden (+Z) im Uhrzeigersinn, Osten = +X; P(r, th) gibt (x, z). Jedes Haus hat
seine Vorderseite bei lokal -Z und schaut zur Mitte. Die Teile, die Server und Client suchen (Shop, Rad, Bestenlisten,
Podest, Markt-Tor, Dungeon-Eingang), landen in der Gruppe "Zentrale" (immer geladen, src/shared/Zentrale.lua).
Läuft mit eigenen Zufallszahlen (World.camp). Draufsicht zum Prüfen: python3 tools/camp_render.py camp.png
"""
import math

SAFE_R = 165                 # Safe Zone (Radius, Teil "SafeZone")
CAMP_WALL_R = 110            # Mitte der Mauer
STREET_W, WALK_W = 14, 3     # Fahrbahn, Gehsteig je Seite
LINE = STREET_W / 2 + WALK_W  # Bauflucht neben den Straßen (Abstand zur Straßenachse)
HOUSE_D = 16                 # Haustiefe
RING_R, RING_W = 59.5, 10    # Ringstraße
PLAZA_R = RING_R - RING_W / 2  # Phönixplatz bis an die Ringstraße
OUTER_R = 66.5               # Fronten an der Ringstraße
YARD_R0, YARD_R1 = 83, 107   # Hinterhöfe hinter dem Häuserring
GATE_W = 18                  # Durchfahrt in den Toren
W_OUTER = 18                 # Hausbreite an der Ringstraße
PAV_R, PAV_W, PAV_D = 44, 20, 16  # Pavillons auf dem Platz (Mitte, Breite, Tiefe)

WHITE, LIGHT = (232, 232, 228), (198, 200, 202)
ANTHRACITE, STEEL = (46, 50, 56), (92, 98, 106)
GLASS_DARK = (44, 58, 70)
PAVE, PAVE_DARK = (176, 174, 168), (78, 80, 86)
ASPHALT = (54, 56, 60)
GOLD = (212, 170, 80)
PHOENIX = (240, 124, 44)
GRAVEL = (128, 120, 104)
FACADES = (((232, 232, 228), "Plaster"), ((206, 208, 210), "Concrete"), ((64, 68, 76), "Metal"),
           ((150, 110, 80), "WoodPlanks"), ((176, 178, 182), "Concrete"), ((222, 214, 198), "Plaster"))
ACCENTS = ((240, 124, 44), (70, 170, 230), (90, 200, 140), (230, 200, 80), (210, 90, 120))
SKINS = ((236, 196, 160), (198, 150, 112), (150, 106, 78), (110, 76, 56), (226, 180, 140))
NO_HIT = {"CanCollide": False, "CanQuery": False}

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
# Pavillons auf dem Platz: Art -> (Titel, Unterzeile, Farbe)
PAVILIONS = {
    "outfitter": ("AUSRÜSTER", "SKINS · ANGEBOTE DES TAGES · AN DER THEKE E DRÜCKEN", GOLD),
    "wheel": ("GLÜCKSRAD", "TÄGLICH GRATIS DREHEN · E AM PULT", GOLD),
    "trade": STATIONS["Stand_Market"],
}
# Kleidung der Händler: Hemd, Hose, dazu wahlweise Weste, Kittel, Krawatte, Fliege, Mütze, Kapuze, Haare
OUTFITS = {
    "Stand_Weapons": dict(shirt=(84, 92, 64), pants=(52, 54, 46), vest=(52, 56, 44), cap=(50, 56, 44), skin=1),
    "Stand_Items": dict(shirt=(110, 160, 200), pants=(70, 90, 120), coat=(238, 240, 242), hair=(60, 44, 32), skin=0),
    "Stand_Market": dict(shirt=(40, 44, 56), pants=(36, 38, 44), tie=GOLD, hair=(30, 26, 24), skin=3),
    "trade": dict(shirt=(40, 44, 56), pants=(36, 38, 44), tie=GOLD, hair=(30, 26, 24), skin=3),
    "Stash": dict(shirt=(120, 126, 134), pants=(120, 126, 134), vest=(230, 190, 40), cap=(60, 64, 70), skin=2),
    "Stand_Vehicles": dict(shirt=(52, 86, 140), pants=(52, 86, 140), cap=(40, 40, 44), skin=4),
    "Travel": dict(shirt=(60, 80, 120), pants=(40, 44, 56), cap=(40, 50, 80), tie=(176, 60, 50), skin=1),
    "Hideout": dict(shirt=(70, 70, 76), pants=(50, 60, 80), hood=True, skin=2),
    "Kits": dict(shirt=(70, 150, 90), pants=(50, 52, 58), cap=(60, 130, 80), skin=0),
    "outfitter": dict(shirt=(28, 30, 34), pants=(28, 30, 34), tie=GOLD, hair=(196, 160, 90), skin=0),
    "wheel": dict(shirt=(176, 40, 40), pants=(28, 28, 32), bow=GOLD, hair=(40, 30, 26), skin=4),
    "kiosk": dict(shirt=(230, 230, 226), pants=(50, 52, 58), cap=(176, 60, 40), skin=2),
    "kiosk2": dict(shirt=(60, 64, 72), pants=(40, 42, 48), hair=(90, 60, 40), skin=3),
}


def P(r, th):
    """Punkt im Abstand r von der Mitte in Kompassrichtung th (0 = Norden = +Z, 90 = Osten = +X)."""
    a = math.radians(th)
    return r * math.sin(a), r * math.cos(a)


def half_angle(r, w):
    """Halber Öffnungswinkel (Grad) einer Front der Breite w im Abstand r."""
    return math.degrees(math.atan2(w / 2, r))


def near_axis(th, limit):
    """Liegt th näher als limit Grad an einer Hauptstraße?"""
    return min(abs((th - g + 180) % 360 - 180) for g in (0, 90, 180, 270)) < limit


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

    def container(self, x, z, yaw, color, y=0.0, length=16, group="Buildings", doors=False):
        """Seecontainer (8 x 8.5 x length), Längsseite entlang lokal X."""
        f, box = self.frame(x, z, yaw)
        box(group, "Container", (length, 8.5, 8), (0, y + 4.25, 0), color, "Metal")
        for k in range(int(length // 2.6)):  # Sicken
            lx = -length / 2 + 1.6 + k * 2.6
            box("Decor", "ContainerRib", (0.4, 8.1, 8.15), (lx, y + 4.25, 0), self.bm.lighten(color, -0.12), "Metal")
        if doors:
            box("Decor", "ContainerDoors", (0.2, 8, 7.6), (length / 2 + 0.1, y + 4.25, 0), self.bm.lighten(color, -0.2), "Metal")

    def _feature(self, build, x, z, yaw):
        """Prefab bauen (Vorderseite -Z zur Mitte) und aufstellen; Decor wird zur Gruppe Zentrale."""
        pb = self.prefab()
        build(pb)
        pb.groups["Zentrale"] = pb.groups.pop("Decor", []) + pb.groups.pop("Zentrale", [])
        self.stamp(pb, x, z, yaw)

    # ---------- Händler ----------
    def shopkeeper(self, box, lx, lz, look, y=0.0, pose="counter"):
        """Händler als Figur aus Teilen im R15-Schnitt (Füße, Unter-/Oberschenkel, Hüfte, Brust, Ober-/Unterarme,
        Hände, runder Kopf mit Gesicht), Blick nach lokal -Z. pose "counter": Hände liegen vor ihm auf der Theke
        (Thekenmitte bei lz - 1.6), "stand": Arme hängen. Nicht fest, nicht treffbar, ohne Zufall."""
        shirt, pants = look["shirt"], look["pants"]
        skin = SKINS[look.get("skin", 0)]
        shoes = (34, 34, 38)
        coat = look.get("coat")
        sleeve = coat or shirt

        def part(name, size, pos, color, mat="Fabric", extra=(0, 0, 0), **kw):
            box("Decor", name, size, (lx + pos[0], y + pos[1], lz + pos[2]), color, mat, extra=extra, props=dict(NO_HIT), **kw)
        for s in (-1, 1):
            part("NpcFoot", (0.85, 0.35, 1.15), (s * 0.5, 0.175, -0.12), shoes, "SmoothPlastic")
            part("NpcLowerLeg", (0.8, 1.3, 0.8), (s * 0.5, 1.0, 0), pants)
            part("NpcUpperLeg", (0.88, 1.3, 0.88), (s * 0.5, 2.3, 0), pants)
            part("NpcUpperArm", (0.82, 1.3, 0.82), (s * 1.45, 4.55, 0), sleeve)
            if pose == "counter":
                part("NpcLowerArm", (0.76, 0.76, 1.3), (s * 1.3, 3.75, -0.75), sleeve)
                part("NpcHand", (0.72, 0.5, 0.8), (s * 1.2, 3.65, -1.6), skin, "SmoothPlastic")
            else:
                part("NpcLowerArm", (0.76, 1.2, 0.76), (s * 1.45, 3.35, 0), sleeve)
                part("NpcHand", (0.72, 0.65, 0.72), (s * 1.45, 2.45, 0), skin, "SmoothPlastic")
        part("NpcLowerTorso", (1.9, 0.7, 1.0), (0, 3.25, 0), pants)
        part("NpcUpperTorso", (2.0, 1.65, 1.05), (0, 4.42, 0), shirt)
        if coat:  # Kittel bis über die Knie, vorne offen
            part("NpcCoat", (2.12, 3.2, 1.12), (0, 3.65, 0.03), coat)
            part("NpcCoatGap", (0.5, 1.6, 0.05), (0, 4.4, -0.58), shirt)
        if look.get("vest"):
            part("NpcVest", (2.1, 1.5, 1.12), (0, 4.45, 0), look["vest"])
        if look.get("tie"):
            part("NpcTie", (0.32, 1.3, 0.06), (0, 4.5, -0.56), look["tie"], "SmoothPlastic")
        if look.get("bow"):
            part("NpcBowTie", (0.7, 0.3, 0.08), (0, 5.12, -0.56), look["bow"], "SmoothPlastic")
        part("NpcBadge", (0.42, 0.28, 0.06), (0.55, 4.75, -0.56), (236, 236, 230), "SmoothPlastic")
        head = [{"Name": "Mesh", "ClassName": "SpecialMesh", "Properties": {"MeshType": "Head", "Scale": [1.25, 1.25, 1.25]}},
                {"Name": "face", "ClassName": "Decal", "Properties": {"Texture": "rbxasset://textures/face.png", "Face": "Front"}}]
        part("NpcHead", (2, 1, 1), (0, 5.85, 0), skin, "SmoothPlastic", children=head)
        if look.get("cap"):
            part("NpcCap", (1.35, 0.42, 1.35), (0, 6.55, 0.02), look["cap"])
            part("NpcVisor", (1.15, 0.12, 0.6), (0, 6.4, -0.85), look["cap"])
        elif look.get("hood"):
            part("NpcHood", (1.5, 1.5, 1.45), (0, 6.0, 0.12), shirt)
        elif look.get("hair"):
            part("NpcHair", (1.32, 0.38, 1.32), (0, 6.5, 0.05), look["hair"])
            part("NpcHairBack", (1.32, 0.8, 0.3), (0, 6.05, 0.55), look["hair"])

    # ---------- Aufbau ----------
    def _camp(self):
        b = self.b
        R = SAFE_R
        b.add("Zone", "SafeZone", (2 * R, 80, 2 * R), (0, 40, 0), (96, 210, 120), "SmoothPlastic",
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})
        self.polygon_pad("CampPad", CAMP_WALL_R + 6, (128, 128, 124), "Concrete", 0.0, thickness=3)
        self.plaza()
        for th in (0, 90, 180, 270):
            self.street(th)
        self.ring_road()
        self.outer_ring()
        self.yard_food()
        self.yard_motor_pool()
        self.yard_depot()
        self.yard_sports()
        self.camp_wall()
        self.glacis()

    # ---------- Phönixplatz ----------
    def plaza(self):
        """Offener Platz bis an die Ringstraße: Plattenbelag, Fugenbänder, Spawns in der Mitte, drei Pavillons und die frei
        stehende Ruhmeswand auf den Diagonalen, das Siegerpodest davor, Poller am Rand."""
        b = self.b
        self.polygon_pad("Square", PLAZA_R - 1, PAVE, "Pavement", 0.22)
        self.arc_pad("SquareEdge", PLAZA_R - 1.4, PLAZA_R, 0, 360, PAVE_DARK, "Slate", 0.32, step=5, thickness=0.4)
        self.arc_pad("SquareRing", 21.6, 22.4, 0, 360, PAVE_DARK, "Slate", 0.25, step=5)
        for th in (0, 90, 180, 270):  # Fugenbänder entlang der Achsen: führen den Blick zu den Toren
            x, z, yaw = self.at_center((22.4 + PLAZA_R - 1.4) / 2, th)
            b.box("Ground", "SquareLine", (0.8, 0.06, PLAZA_R - 23.8), (x, 0.25, z), PAVE_DARK, "Slate", angles=(0, yaw, 0))
        self.arc_pad("SquareRing", 35.6, 36.4, 0, 360, PAVE_DARK, "Slate", 0.25, step=5)
        for th, text in ((0, "NORDTOR · KITS"), (90, "OSTTOR · WERKSTATT"), (180, "SÜDTOR · BUSBAHNHOF"), (270, "WESTTOR · VERSTECK")):
            x, z = P(45, th)  # Wegweiser im Boden, lesbar auf dem Weg nach außen
            dx, dz = P(1, th)
            b.floor_text("PlazaGateLabel", (12, 0.1, 1.8), (x, 0.3, z), text, (236, 226, 206), yaw=self.yaw_to(dx, dz))
        b.spawn(0, 0, yaw=0)  # Spawn mitten auf dem Platz
        for k in range(9):
            th = 360 * (k + 0.5) / 9
            x, z = P(7, th)
            b.spawn(x, z, yaw=th)  # Blick nach außen
        self.pavilion(45, "outfitter")
        self.pavilion(135, "wheel")
        self.pavilion(315, "trade")
        self.fame_wall(225)
        self.podium(*self.at_center(PAV_R - 4, 225))
        for step in range(60):  # Poller mit Leuchtkopf am Platzrand, Lücken an den Zebrastreifen
            th = 3 + step * 6
            if any(abs((th - c + 180) % 360 - 180) < 3.5 for c in self._crossings()):
                continue
            x, z = P(PLAZA_R - 0.8, th)
            b.cylinder("Cover", "Bollard", 0.7, 1.2, (x, 0.9, z), ANTHRACITE, material="Metal")
            b.cylinder("Decor", "BollardLight", 0.72, 0.15, (x, 1.55, z), (236, 240, 246), material="Neon",
                       props={"CanCollide": False, "Transparency": 0.2})

    def _crossings(self):
        """Winkel der Zebrastreifen über die Ringstraße: in Verlängerung der Gehsteige jeder Hauptstraße."""
        a = math.degrees(math.asin((STREET_W / 2 + WALK_W / 2) / RING_R))
        return [g + s * a for g in (0, 90, 180, 270) for s in (-1, 1)]

    def podium(self, x, z, yaw):
        """SIEGERPODEST der Top 3 vor der Ruhmeswand (Statuen setzt der Server an Podium1-3): drei helle Sockel auf
        einer Stufe, oben je eine Platte in Medaillenfarbe mit Leuchtkante, kleine Platznummer vorn am Sockel, ein
        Licht vor jeder Statue (sonst sind die Figuren nachts nur dunkle Umrisse). Kein Text auf dem Boden."""
        def build(pb):
            pb.box("Decor", "PodiumPlinth", (16, 0.6, 6.4), (0, 0.3, 0), WHITE, "Concrete")
            for place, off, h, color in ((1, 0, 3.2, GOLD), (2, 5.3, 2.3, (200, 204, 210)), (3, -5.3, 1.5, (196, 130, 80))):
                pb.box("Decor", "PodiumBase", (4.6, h, 4.6), (off, 0.6 + h / 2, 0), LIGHT, "SmoothPlastic")
                pb.box("Decor", "PodiumTop", (4.8, 0.3, 4.8), (off, 0.75 + h, 0), color, "SmoothPlastic")
                pb.box("Decor", "PodiumEdge", (4.8, 0.1, 0.08), (off, 0.6 + h, -2.42), color, "Neon", props=dict(NO_HIT))
                pb.add("Decor", "Podium" + str(place), (2, 0.2, 2), (off, 1.0 + h, 0), color, "SmoothPlastic",
                       props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
                pb.sign("PodiumNumber", (1.1, 0.9, 0.2), (off, 0.6 + h / 2, -2.4), str(place), ANTHRACITE, color)
                pb.add("Decor", "PodiumLamp", (0.2, 0.2, 0.2), (off, 3.8 + h, -2.6), WHITE, "SmoothPlastic",
                       props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False},
                       children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {
                           "Range": 8, "Brightness": 1.6, "Color": self.bm.rgb(255, 240, 220)}}])
            pb.add("Decor", "PodiumGlow", (0.1, 5.6, 5.6), (0, 0.65, 0), GOLD, "Neon", angles=(0, 0, 90),
                   props={"Shape": "Cylinder", "Transparency": 0.7, "CanCollide": False})
        self._feature(build, x, z, yaw)

    # ---------- Pavillons ----------
    def pavilion(self, th, kind):
        """Offener Pavillon auf dem Platz (Mitte bei PAV_R, Front zur Mitte): heller Steinboden, dunkle Rückwand,
        Glasseiten (Ruhmeswand: feste Seiten für die Bestenlisten), zwei schlanke Stützen vorn, weißes Flachdach mit
        Leuchtkante, Schild auf dem Dach (vorn und hinten), Deckenlicht. Dazu je Art die Einrichtung."""
        x, z, yaw = self.at_center(PAV_R, th)
        f, box = self.frame(x, z, yaw)
        W, D = PAV_W, PAV_D
        H = 15.0 if kind == "wheel" else 12.0
        fz = -D / 2
        title, sub, accent = PAVILIONS[kind]
        box("Buildings", "PavilionFloor", (W, 0.5, D), (0, 0.25, 0), (214, 214, 210), "Marble")
        box("Decor", "PavilionEdge", (W, 0.08, 0.25), (0, 0.52, fz + 0.15), accent, "Neon", props=dict(NO_HIT, Transparency=0.2))
        box("Buildings", "PavilionBack", (W, H, 0.8), (0, H / 2, D / 2 - 0.4), ANTHRACITE, "Concrete")
        for s in (-1, 1):
            if kind == "fame":
                box("Buildings", "PavilionSide", (0.8, H, D - 0.8), (s * (W / 2 - 0.4), H / 2, -0.4), ANTHRACITE, "Concrete")
            else:
                box("Buildings", "PavilionGlass", (0.3, H - 0.5, D - 1.6), (s * (W / 2 - 0.4), H / 2 + 0.25, 0),
                    (170, 200, 220), "Glass", props={"Transparency": 0.6})
            box("Buildings", "PavilionColumn", (0.9, H, 0.9), (s * (W / 2 - 0.45), H / 2, fz + 0.45), ANTHRACITE, "Metal")
        box("Buildings", "Roof", (W + 3, 1.2, D + 3), (0, H + 0.6, 0), WHITE, "SmoothPlastic")
        box("Decor", "RoofStrip", (W + 3, 0.25, 0.25), (0, H + 0.05, fz - 1.4), accent, "Neon", props=dict(NO_HIT))
        box("Decor", "PavilionLight", (W - 4, 0.2, D - 5), (0, H - 0.1, 0.5), (250, 248, 240), "SmoothPlastic",
            children=[{"Name": "Light", "ClassName": "SurfaceLight", "Properties": {
                "Face": "Bottom", "Range": 16, "Brightness": 1.2, "Angle": 120, "Color": self.bm.rgb(255, 246, 230)}}])
        for s in (-1, 1):
            box("Decor", "SignPost", (0.3, 1.0, 0.3), (s * 5, H + 1.7, fz + 0.6), ANTHRACITE, "Metal")
        self.b.sign2("PavilionSign", (14, 2.8, 0.4), f(0, H + 3.4, fz + 0.4), title, sub, (24, 26, 30), accent, (226, 228, 232),
                     angles=(0, yaw, 0), glow=accent)
        self.b.sign2("PavilionSign", (14, 2.8, 0.4), f(0, H + 3.4, fz + 0.8), title, sub, (24, 26, 30), accent, (226, 228, 232),
                     angles=(0, yaw + 180, 0))
        getattr(self, "_pav_" + kind)(f, box, yaw, W, D, H, fz, accent)

    def _pav_outfitter(self, f, box, yaw, W, D, H, fz, accent):
        """AUSRÜSTER: drei Vitrinen mit ShopDisplay1-3 und ShopPlaque1-3, Theke = ShopCounter, Händler dahinter."""
        bm = self.bm
        for k, vx in enumerate((-7, 0, 7), start=1):
            vz = 2.4
            box("Decor", "VitrineBase", (4, 2.4, 4), (vx, 1.6, vz), ANTHRACITE, "SmoothPlastic")
            box("Decor", "VitrineBaseStrip", (4.1, 0.25, 4.1), (vx, 2.7, vz), accent, "Neon", props={"Transparency": 0.2})
            box("Decor", "VitrineGlass", (3.6, 4.2, 3.6), (vx, 4.9, vz), (200, 225, 240), "Glass", props={"Transparency": 0.8})
            box("Decor", "VitrineCap", (4, 0.4, 4), (vx, 7.2, vz), WHITE, "SmoothPlastic")
            box("Decor", "VitrineLight", (2.4, 0.1, 2.4), (vx, 6.95, vz), (255, 248, 235), "Neon",
                children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                    "Face": "Bottom", "Range": 10, "Brightness": 1.1, "Angle": 70, "Color": bm.rgb(255, 245, 230)}}])
            self.b.add("Zentrale", "ShopDisplay" + str(k), (1, 1, 1), f(vx, 4.8, vz), accent, "SmoothPlastic",
                       angles=(0, yaw, 0), props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
            self.b.holo_panel("Zentrale", "ShopPlaque" + str(k), (3.6, 1.4, 0.2), f(vx, 1.5, vz - 2.15), angles=(0, yaw, 0))
        self.b.box("Zentrale", "ShopCounter", (10, 3.4, 2.2), f(2, 2.1, fz + 2.6), WHITE, "SmoothPlastic", angles=(0, yaw, 0))
        box("Decor", "ShopCounterTop", (10.4, 0.3, 2.6), (2, 3.9, fz + 2.6), ANTHRACITE, "SmoothPlastic")
        box("Decor", "ShopCounterStrip", (10, 0.25, 0.15), (2, 3.2, fz + 1.45), accent, "Neon", props={"Transparency": 0.2})
        box("Decor", "ShopTerminal", (2.4, 1.6, 0.3), (5.5, 4.8, fz + 2.6), (22, 25, 30), "SmoothPlastic", extra=(-15, 180, 0))
        self.shopkeeper(box, 1.5, fz + 4.2, OUTFITS["outfitter"], y=0.5)

    def _pav_wheel(self, f, box, yaw, W, D, H, fz, accent):
        """GLÜCKSRAD: Rad an der Rückwand (WheelSpot, das Rad baut der Client), Pult WheelConsole mit Tafel WheelBoard,
        Lichtleiste, Gastgeber neben dem Pult."""
        bm = self.bm
        for k in range(8):  # Rückwand in zwei Grautönen hinter dem Rad
            box("Decor", "BoothBackRib", (W / 8, H - 0.8, 0.25), (-W / 2 + W / 16 + k * W / 8, H / 2, D / 2 - 0.92),
                (40, 44, 52) if k % 2 == 0 else (58, 62, 72), "SmoothPlastic")
        self.b.add("Zentrale", "WheelSpot", (1, 1, 1), f(0, 7.4, D / 2 - 1.5), GOLD, "SmoothPlastic", angles=(0, yaw, 0),
                   props={"Transparency": 1, "CanCollide": False, "CanQuery": False})
        self.b.box("Zentrale", "WheelConsole", (5.6, 2.2, 1.6), f(0, 1.6, fz + 4.5), (36, 39, 46), "Metal", angles=(0, yaw, 0))
        box("Decor", "WheelConsoleStrip", (5.7, 0.2, 1.7), (0, 2.6, fz + 4.5), GOLD, "Neon", props={"Transparency": 0.2})
        self.b.holo_panel("Zentrale", "WheelBoard", (5.2, 1.9, 0.15), f(0, 3.25, fz + 4.3), angles=bm.yaw_tilt(yaw, 35))
        box("Decor", "MarqueeStrip", (W - 2, 0.3, 0.3), (0, H - 0.7, fz + 0.4), GOLD, "Neon", props=dict(NO_HIT))
        for s in (-1, 1):
            box("Decor", "BoothLamp", (1.0, 0.6, 1.0), (s * (W / 2 - 3), H - 1.0, fz + 3), (255, 240, 210), "SmoothPlastic",
                children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 18, "Brightness": 1.2,
                                                                                     "Color": bm.rgb(255, 236, 200)}}])
        self.b.floor_text("WheelFloorLabel", (8, 0.1, 2), f(0, 0.55, fz + 2.4), "E AM PULT", GOLD, yaw=yaw + 180)
        self.shopkeeper(box, 5.0, fz + 4.6, OUTFITS["wheel"], y=0.5, pose="stand")

    def fame_wall(self, th0):
        """RUHMESWAND frei auf dem Platz, Front zur Mitte: vier hohe Bestenlisten-Monolithe Leaderboard_* (Bildschirm
        bis kurz über den Boden), je zwei links und rechts im Bogen; in der Mitte ein breiter, höherer Monolith, oben der
        Lagebericht (MissionBoard), unten die dunkle Kulisse für das Siegerpodest davor. Titel schreibt der Client
        auf die Bildschirme, darüber hängt nichts."""
        x, z, yaw = self.at_center(PAV_R + 3, th0)
        self.monolith("MissionBoard", 11, 5.6, 14.2, 17.6, x, z, yaw, (226, 190, 120), body_w=13)
        for name, off, color in (("Leaderboard_Zombies", -32, (212, 170, 80)), ("Leaderboard_Kills", -16, (206, 70, 58)),
                                 ("Leaderboard_Level", 16, (96, 164, 214)), ("Leaderboard_Missions", 32, (112, 178, 112))):
            x, z, yaw = self.at_center(PAV_R + 1, th0 + off)
            self.monolith(name, 6.5, 10.6, 6.7, 12.8, x, z, yaw, color)

    def monolith(self, name, w, h, y, top, x, z, yaw, accent, body_w=None, group="Zentrale"):
        """Freistehender Bildschirm-Monolith: Sockel, dunkler Korpus bis zur Höhe top, davor ein matter Bildschirm
        (w x h, Mitte in Höhe y; Text schreibt der Client), eine Akzentfarbe als Leuchtlinie oben und am Sockel.
        Front (lokal -Z) zeigt in Richtung yaw."""
        f, box = self.frame(x, z, yaw)
        bw = body_w or w + 0.8
        box("Decor", "MonolithPlinth", (bw + 0.8, 0.5, 2.4), (0, 0.25, 0.2), ANTHRACITE, "Concrete")
        box("Decor", "MonolithBody", (bw, top - 0.5, 1.0), (0, 0.5 + (top - 0.5) / 2, 0.3), (24, 27, 32), "SmoothPlastic")
        box("Decor", "MonolithCap", (bw, 0.12, 0.08), (0, top - 0.25, -0.24), accent, "Neon", props=dict(NO_HIT))
        box("Decor", "MonolithGlow", (bw + 0.8, 0.08, 0.08), (0, 0.42, -1.02), accent, "Neon",
            props=dict(NO_HIT, Transparency=0.2))
        self.b.add(group, name, (w, h, 0.1), f(0, y, -0.25), (14, 16, 20), "SmoothPlastic", angles=(0, yaw, 0),
                   props={"CanCollide": False, "CanQuery": False})

    def _pav_trade(self, f, box, yaw, W, D, H, fz, accent):
        """TAUSCHMARKT: lange Theke mit Händlerin, Regale mit Ware an den Seiten, Punkt Stand_Market davor."""
        box("Buildings", "Counter", (8, 3.4, 1.4), (0, 2.2, fz + 2.6), WHITE, "SmoothPlastic")
        box("Decor", "CounterTop", (8.4, 0.25, 1.8), (0, 4.0, fz + 2.6), ANTHRACITE, "SmoothPlastic")
        box("Decor", "CounterStrip", (8, 0.2, 0.1), (0, 3.2, fz + 1.85), accent, "Neon", props=dict(NO_HIT))
        self.shopkeeper(box, 0, fz + 4.2, OUTFITS["trade"], y=0.5)
        self.goods_shelf(box, -W / 2 + 2, 2, 6, 90, accent)
        self.goods_shelf(box, W / 2 - 2, 2, 6, -90, accent)
        self.b.add("Stands", "Stand_Market", (2, 2, 2), f(0, 2.5, fz - 3.5), (200, 200, 200), "SmoothPlastic", angles=(0, yaw, 0),
                   props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    def goods_shelf(self, box, lx, lz, length, turn, accent):
        """Regal mit Ware (bunte Kisten) an einer Wand; turn dreht es (90 = Rücken nach -X)."""
        rng = self.rng
        a = math.radians(turn)
        ax, az = math.cos(a), -math.sin(a)  # Richtung entlang des Regals
        box("Decor", "Shelf", (length, 6, 1.4), (lx, 3.5, lz), ANTHRACITE, "Metal", extra=(0, turn, 0))
        for row, y in enumerate((2.0, 4.0, 6.0)):
            box("Decor", "ShelfBoard", (length, 0.2, 1.6), (lx, y - 0.6, lz), WHITE, "SmoothPlastic", extra=(0, turn, 0))
            for k in range(4):
                t = -length / 2 + 0.9 + k * (length - 1.8) / 3
                s = rng.uniform(0.7, 1.1)
                color = rng.choice((accent, (70, 150, 220), (220, 220, 214), (90, 200, 110), (200, 80, 70)))
                box("Decor", "Goods", (s, s, s), (lx + ax * t, y - 0.5 + s / 2, lz + az * t), color,
                    "SmoothPlastic", extra=(0, turn + rng.uniform(-15, 15), 0), props=dict(NO_HIT))

    # ---------- Straßen ----------
    def street(self, th):
        """Hauptstraße von der Ringstraße zum Tor (Richtung th): Asphalt mit Mittelstreifen, Gehsteige mit Bordstein,
        ein Schachtdeckel."""
        b, rng = self.b, self.rng
        f, box = self.frame(0, 0, th)  # lokal +Z = nach außen
        r0, r1 = RING_R + RING_W / 2 - 0.2, CAMP_WALL_R + 1
        box("Ground", "Sidewalk", (STREET_W, 0.2, r1 - r0), (0, 0.04, (r0 + r1) / 2), ASPHALT, "Asphalt")
        for k in range(int((r1 - r0 - 8) // 10)):
            box("Ground", "RoadDash", (0.4, 0.06, 4), (0, 0.15, r0 + 6 + k * 10), (226, 226, 220), "SmoothPlastic")
        a, c = RING_R + RING_W / 2 + 0.5, CAMP_WALL_R - 12
        for s in (-1, 1):
            box("Ground", "Sidewalk", (WALK_W, 0.5, c - a), (s * (STREET_W / 2 + WALK_W / 2), 0.25, (a + c) / 2), LIGHT, "Concrete")
            box("Ground", "Curb", (0.4, 0.55, c - a), (s * (STREET_W / 2 + 0.2), 0.27, (a + c) / 2), STEEL, "Concrete")
        box("Ground", "Manhole", (2, 0.08, 2), (rng.uniform(-3, 3), 0.14, 72), (60, 60, 62), "DiamondPlate")

    def ring_road(self):
        """Ringstraße um den Platz: Asphalt, Mittelstreifen, Gehsteig außen, Zebrastreifen."""
        self.arc_pad("Sidewalk", RING_R - RING_W / 2, RING_R + RING_W / 2, 0, 360, ASPHALT, "Asphalt", 0.1, step=5)
        for k in range(48):
            th = 360 * k / 48
            if near_axis(th, 9):
                continue
            x, z, yaw = self.at_center(RING_R, th)
            self.b.box("Ground", "RoadDash", (0.4, 0.06, 3.5), (x, 0.17, z), (226, 226, 220), "SmoothPlastic", angles=(0, yaw + 90, 0))
        self.arc_pad("Sidewalk", RING_R + RING_W / 2, OUTER_R - 0.2, 0, 360, LIGHT, "Concrete", 0.3, step=5, thickness=0.5)
        for th in self._crossings():  # Zebrastreifen: Balken längs der Fahrtrichtung, quer über die Fahrbahn verteilt
            for k in range(6):
                r = RING_R - RING_W / 2 + 0.9 + k * 1.65
                x, z, yaw = self.at_center(r, th)
                self.b.box("Ground", "Crosswalk", (3.6, 0.06, 0.8), (x, 0.15, z), (236, 236, 230), "SmoothPlastic", angles=(0, yaw, 0))

    # ---------- Häuser ----------
    def house(self, r_front, th, w, floors, kind, sides=0):
        """Modernes Haus mit der Front bei r_front in Richtung th, Blick zur Mitte. kind: house, shop:<Titel>|<Unterzeile>,
        station:<Schlüssel>, garage, bus. sides: ±1 = diese Seitenwand (lokal ±X; -X ist links, wenn man zur Mitte schaut)
        steht an einer Hauptstraße und bekommt Fenster."""
        x, z, yaw = self.at_center(r_front + HOUSE_D / 2, th)
        key, shop = None, None
        if kind.startswith("shop:"):
            title, sub = kind[5:].split("|")
            shop = (title, sub, None)
        elif kind.startswith("station:"):
            key = kind[8:]
        elif kind == "garage":
            key = "Stand_Vehicles"
        elif kind == "bus":
            key = "Travel"
        if key:
            shop = STATIONS[key]
        self.block(x, z, yaw, w, HOUSE_D, floors, shop=shop, key=key, kind=kind, sides=sides)

    def block(self, x, z, yaw, w, d, floors, shop=None, key=None, kind="house", sides=0):
        """Flachdachhaus (Front lokal -Z): Fassade aus Putz, Beton, Metall oder Holz, Geschossbänder, Fensterbänder mit
        Pfosten (manche Fenster hell), Attika, Dach mit Technik, farbige Lisene an der Ecke, Rückfassade mit Fenstern
        und Hoftür. Erdgeschoss: Station = offener Laden (Glas links und rechts, Theke in der Öffnung, Händler dahinter,
        Regal an der Rückwand, Leuchtschild über einem Vordach), Werkstatt (offenes Tor, Hebebühne), Laden (Schaufenster,
        Schild) oder Wohnhaus (Eingang). key: Punkt in Stands vor der Theke bzw. dem Tor."""
        b, rng = self.b, self.rng
        f, box = self.frame(x, z, yaw)
        face_c, face_m = rng.choice(FACADES)
        dark = sum(face_c) < 360
        band = WHITE if dark else ANTHRACITE
        accent = shop[2] if shop and shop[2] else rng.choice(ACCENTS)
        gf, fh = 11.0, 9.0
        top = gf + (floors - 1) * fh
        fz = -d / 2
        open_gf = key is not None
        if open_gf:
            box("Buildings", "HouseBody", (w, top - gf, d), (0, gf + (top - gf) / 2, 0), face_c, face_m)
            self.open_shop(f, box, yaw, w, d, gf, face_c, face_m, accent, key, kind)
        else:
            box("Buildings", "HouseBody", (w, top, d), (0, top / 2, 0), face_c, face_m)
            if shop:
                self.storefront(box, w, gf, fz, accent)
            else:
                self.entrance(box, w, gf, fz, band)
        if shop:
            title, sub, _ = shop
            b.sign2("StandSign_" + key if key else "ShopSign", (min(w - 2, 14), 1.7, 0.3), f(0, gf - 1.0, fz - 0.35), title, sub,
                    (24, 26, 30), accent, (226, 228, 232), angles=(0, yaw, 0), glow=accent if key else None)
            box("Decor", "Canopy", (w - 1, 0.4, 2.6), (0, gf - 2.3, fz - 1.3), ANTHRACITE, "Metal")
            box("Decor", "CanopyStrip", (w - 1, 0.18, 0.18), (0, gf - 2.3, fz - 2.6), accent, "Neon", props=dict(NO_HIT))
        # Obergeschosse vorn und hinten: Geschossband, Fensterband mit Pfosten, manche Fenster hell
        for face_yaw in (0, 180):
            fb, boxb = self.frame(x, z, yaw + face_yaw)
            for k in range(1, floors):
                y0 = gf + (k - 1) * fh
                boxb("Decor", "FloorBand", (w + 0.3, 0.7, 0.4), (0, y0 + 0.1, fz - 0.2), band, "Concrete")
                self.window_band(boxb, w, y0, fz, band, balcony=(kind == "house" and face_yaw == 0))
            boxb("Decor", "Parapet", (w + 0.3, 1.2, 0.5), (0, top + 0.6, fz + 0.05), band, "Concrete")
        for s in (-1, 1):
            box("Decor", "Parapet", (0.5, 1.2, d), (s * (w / 2 - 0.05), top + 0.6, 0), band, "Concrete")
        box("Decor", "AccentFin", (0.8, top - gf + 1.2, 0.5), (-(w / 2 - 0.4), gf + (top - gf + 1.2) / 2, fz - 0.25), accent,
            "SmoothPlastic")
        # Rückseite: Hoftür mit kleinem Vordach
        fb, boxb = self.frame(x, z, yaw + 180)
        dx = rng.choice((-1, 1)) * (w / 2 - 4)
        boxb("Decor", "BackDoor", (3.4, 7, 0.3), (dx, 3.5, fz - 0.1), ANTHRACITE, "Metal")
        boxb("Decor", "BackCanopy", (5, 0.3, 2), (dx, 8, fz - 1), ANTHRACITE, "Metal")
        boxb("Decor", "GroundWindow", (w / 2 - 3, 4, 0.3), (-dx * 0.55, 5, fz - 0.14), GLASS_DARK, "Glass", props={"Reflectance": 0.15})
        if sides:
            self.side_windows(box, sides, w, d, floors, gf, fh, band)
        # Dach: Fläche (die Karte zeichnet "Roof"), Technik, manchmal Solarmodule
        box("Buildings", "Roof", (w - 0.4, 0.4, d - 0.4), (0, top + 0.2, 0), (96, 98, 102), "Concrete")
        ux = rng.uniform(-w / 4, w / 4)
        box("Decor", "RoofUnit", (2.6, 1.8, 2.2), (ux, top + 1.3, rng.uniform(0, d / 4)), LIGHT, "Metal")
        box("Decor", "RoofUnitFan", (1.6, 0.1, 1.6), (ux, top + 2.25, rng.uniform(0, 0.1)), ANTHRACITE, "Metal")
        if rng.random() < 0.5:
            for k in range(2):
                box("Decor", "SolarPanel", (w / 2 - 2, 0.2, 3), (-w / 4 + k * w / 2, top + 1.2, -d / 4), (30, 40, 62), "Glass",
                    extra=(-20, 0, 0), props={"Reflectance": 0.3})

    def window_band(self, box, w, y0, fz, frame_c, balcony=False):
        """Fensterband über die ganze Breite eines Stockwerks mit Pfosten; ein paar Felder hell erleuchtet."""
        rng = self.rng
        box("Decor", "WindowGlass", (w - 1.6, 5.0, 0.3), (0, y0 + 4.6, fz - 0.14), GLASS_DARK, "Glass", props={"Reflectance": 0.2})
        n = max(2, int((w - 1.6) // 3.2))
        step = (w - 1.6) / n
        for i in range(n + 1):
            box("Decor", "Mullion", (0.22, 5.0, 0.36), (-(w - 1.6) / 2 + i * step, y0 + 4.6, fz - 0.18), frame_c, "Metal")
        for i in range(n):
            if rng.random() < 0.25:
                box("Decor", "WindowLit", (step - 0.3, 4.7, 0.05), (-(w - 1.6) / 2 + (i + 0.5) * step, y0 + 4.6, fz - 0.31),
                    (255, 236, 200), "Neon", props=dict(NO_HIT, Transparency=0.35))
        if balcony and rng.random() < 0.5:
            bx = rng.choice((-1, 1)) * (w / 4)
            box("Decor", "Balcony", (6, 0.4, 2.2), (bx, y0 + 0.4, fz - 1.1), WHITE, "Concrete")
            box("Decor", "BalconyGlass", (6, 2.2, 0.15), (bx, y0 + 1.7, fz - 2.15), (170, 200, 220), "Glass", props={"Transparency": 0.5})

    def storefront(self, box, w, gf, fz, accent):
        """Geschlossener Laden: Schaufenster über die Breite, Glastür in der Mitte, Pfosten."""
        box("Decor", "ShopGlass", (w - 2, gf - 3.2, 0.3), (0, (gf - 3.2) / 2 + 0.4, fz - 0.14), GLASS_DARK, "Glass",
            props={"Reflectance": 0.2})
        box("Decor", "ShopDoor", (3.6, 7, 0.36), (0, 3.5, fz - 0.18), (30, 34, 40), "Glass")
        for lx in (-(w / 2 - 1), -1.9, 1.9, w / 2 - 1):
            box("Decor", "ShopFrame", (0.25, gf - 3.2, 0.4), (lx, (gf - 3.2) / 2 + 0.4, fz - 0.2), ANTHRACITE, "Metal")
        box("Decor", "ShopLight", (w - 3, 0.2, 0.2), (0, gf - 3.4, fz - 0.4), (255, 240, 214), "Neon", props=dict(NO_HIT))

    def entrance(self, box, w, gf, fz, band):
        """Wohnhaus: Glastür mit Rahmen, Fensterband im Erdgeschoss, Hausnummer-Leuchte."""
        dx = -w / 4
        box("Decor", "HouseDoor", (3.6, 7.4, 0.3), (dx, 3.7, fz - 0.1), (30, 34, 40), "Glass")
        box("Decor", "DoorFrame", (4.4, 0.4, 0.5), (dx, 7.6, fz - 0.2), band, "Metal")
        box("Decor", "DoorLight", (0.6, 0.6, 0.2), (dx + 2.6, 6.6, fz - 0.25), (255, 240, 214), "Neon", props=dict(NO_HIT))
        box("Decor", "GroundWindow", (w / 2 - 2, 4.4, 0.3), (w / 4, 5, fz - 0.14), GLASS_DARK, "Glass", props={"Reflectance": 0.2})

    def open_shop(self, f, box, yaw, w, d, gf, face_c, face_m, accent, key, kind):
        """Offener Laden im Erdgeschoss einer Station: Boden, Rück- und Seitenwände, Blende über der Öffnung, Glas links
        und rechts, Deckenlicht, Regal hinten. Theke mit Händler in der Öffnung (Werkstatt: offenes Tor mit Hebebühne,
        Tresen an der Seite; Busbahnhof: dazu ein Wartehäuschen aus Glas). Punkt key davor."""
        b = self.b
        fz = -d / 2
        box("Buildings", "ShopFloor", (w - 0.2, 0.4, d - 0.2), (0, 0.2, 0), (214, 214, 210), "Marble")
        box("Buildings", "ShopBack", (w, gf, 0.6), (0, gf / 2, d / 2 - 0.3), face_c, face_m)
        for s in (-1, 1):
            box("Buildings", "ShopSide", (0.6, gf, d), (s * (w / 2 - 0.3), gf / 2, 0), face_c, face_m)
        box("Buildings", "Fascia", (w, 2, 0.6), (0, gf - 1, fz + 0.3), ANTHRACITE, "Metal")
        box("Decor", "ShopCeilingLight", (w - 4, 0.2, d - 6), (0, gf - 2.1, 1), (250, 248, 240), "SmoothPlastic",
            children=[{"Name": "Light", "ClassName": "SurfaceLight", "Properties": {
                "Face": "Bottom", "Range": 14, "Brightness": 1.1, "Angle": 120, "Color": self.bm.rgb(255, 246, 230)}}])
        look = OUTFITS[key]
        if kind == "garage":
            ow = 12
            for s in (-1, 1):
                box("Decor", "GarageFrame", (0.6, gf - 2, 0.6), (s * (ow / 2 + 0.3), (gf - 2) / 2, fz + 0.3), ANTHRACITE, "Metal")
                box("Decor", "LiftPost", (0.7, 5, 0.7), (s * 3.6, 2.9, 3), (230, 190, 40), "Metal")
            box("Decor", "RollDoor", (ow + 0.6, 1.2, 1.0), (0, gf - 2.6, fz + 0.6), STEEL, "Metal")
            box("Cover", "LiftCar", (4.8, 2.0, 9), (0, 5.0, 3), (210, 214, 220), "Metal")
            box("Decor", "LiftCarCabin", (4.4, 1.6, 4.4), (0, 6.8, 3.4), (40, 52, 62), "Glass")
            box("Buildings", "Counter", (3, 3.6, 1.4), (w / 2 - 2.6, 2.2, fz + 2.2), WHITE, "SmoothPlastic")
            box("Decor", "CounterStrip", (3, 0.2, 0.1), (w / 2 - 2.6, 3.0, fz + 1.45), accent, "Neon", props=dict(NO_HIT))
            self.shopkeeper(box, w / 2 - 2.6, fz + 3.8, look, y=0.4)
        else:
            ow = 6.4
            pw = (w - ow) / 2 - 0.6
            for s in (-1, 1):
                box("Buildings", "ShopGlass", (pw, gf - 2.4, 0.3), (s * (ow / 2 + pw / 2), (gf - 2.4) / 2 + 0.4, fz + 0.3),
                    (170, 200, 220), "Glass", props={"Transparency": 0.55})
                box("Decor", "ShopFrame", (0.3, gf - 2, 0.5), (s * ow / 2, (gf - 2) / 2, fz + 0.3), ANTHRACITE, "Metal")
            box("Buildings", "Counter", (ow - 0.4, 3.4, 1.4), (0, 2.1, fz + 1.2), WHITE, "SmoothPlastic")
            box("Decor", "CounterTop", (ow, 0.25, 1.8), (0, 3.9, fz + 1.2), ANTHRACITE, "SmoothPlastic")
            box("Decor", "CounterStrip", (ow - 0.4, 0.2, 0.1), (0, 3.0, fz + 0.45), accent, "Neon", props=dict(NO_HIT))
            self.shopkeeper(box, 0, fz + 2.8, look, y=0.4)
            self.goods_shelf(box, 0, d / 2 - 1.4, w - 4, 0, accent)
        if kind == "bus":  # Wartehäuschen aus Glas mit Haltestellenschild (ohne Bank)
            sx = -(w / 2 - 3.2)
            box("Decor", "ShelterRoof", (5.2, 0.3, 3), (sx, 8, fz - 3), ANTHRACITE, "Metal")
            box("Decor", "ShelterGlass", (5, 7, 0.15), (sx, 4.1, fz - 1.6), (170, 200, 220), "Glass", props={"Transparency": 0.55})
            for s in (-1, 1):
                box("Decor", "ShelterPost", (0.25, 8, 0.25), (sx + s * 2.4, 4, fz - 4.3), ANTHRACITE, "Metal")
            box("Decor", "BusStopPole", (0.3, 8, 0.3), (w / 2 - 2.2, 4, fz - 3.8), STEEL, "Metal")
            box("Decor", "BusStopSign", (2.2, 2.2, 0.15), (w / 2 - 2.2, 7.4, fz - 3.8), (232, 196, 40), "SmoothPlastic")
            box("Decor", "BusStopH", (0.35, 1.4, 0.05), (w / 2 - 2.55, 7.4, fz - 3.9), (40, 110, 60), "SmoothPlastic")
            box("Decor", "BusStopH", (0.35, 1.4, 0.05), (w / 2 - 1.85, 7.4, fz - 3.9), (40, 110, 60), "SmoothPlastic")
            box("Decor", "BusStopH", (0.7, 0.3, 0.05), (w / 2 - 2.2, 7.4, fz - 3.9), (40, 110, 60), "SmoothPlastic")
        b.add("Stands", key, (2, 2, 2), f(0, 2.5, fz - 4), (200, 200, 200), "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    def side_windows(self, box, side, w, d, floors, gf, fh, band):
        """Fensterbänder in der Seitenwand side (±1 = lokal ±X) in den Obergeschossen."""
        sx = side * (w / 2)
        rot = (0, -90 * side, 0)
        for k in range(1, floors):
            y0 = gf + (k - 1) * fh
            box("Decor", "WindowGlass", (d - 2.4, 5.0, 0.3), (sx + side * 0.14, y0 + 4.6, 0), GLASS_DARK, "Glass", extra=rot,
                props={"Reflectance": 0.2})
            box("Decor", "FloorBand", (d + 0.3, 0.7, 0.4), (sx + side * 0.2, y0 + 0.1, 0), band, "Concrete", extra=rot)

    # ---------- Häuserring ----------
    def outer_ring(self):
        """Häuser an der Ringstraße (Fronten bei OUTER_R), je Viertel vier mit einer Gasse in der Mitte; im Südwesten die
        MARKTHALLE statt der mittleren Häuser. Die Stationen liegen in den Eckhäusern an den Hauptstraßen, so stehen ihre
        Punkte mindestens 30 Studs auseinander."""
        a = math.degrees(math.asin(LINE / OUTER_R))
        h = half_angle(OUTER_R, W_OUTER)
        slots = (a + h, a + 3 * h, 90 - a - 3 * h, 90 - a - h)   # vier Häuser, Gasse in der Mitte (um base + 45)
        plan = {
            0: (("station:Kits", 2), ("shop:CAFÉ ZENTRAL|KAFFEE · EINTOPF", 3), ("shop:STOFFE|MÄNTEL · DECKEN", 3),
                ("station:Stand_Weapons", 2)),
            90: (("garage", 2), ("shop:ERSATZTEILE|REIFEN · ÖL · BATTERIEN", 2), ("shop:HOTEL ZUR POST|ZIMMER FREI", 3),
                 ("station:Stand_Items", 2)),
            180: (("bus", 2), None, None, ("station:Stash", 2)),
            270: (("station:Hideout", 2), ("house", 3), ("house", 3), ("shop:SCHULE|NOTUNTERKUNFT", 2)),
        }
        for base, houses in plan.items():
            for k, (th_off, spec) in enumerate(zip(slots, houses)):
                if spec:
                    self.house(OUTER_R, base + th_off, W_OUTER, spec[1], spec[0], sides=-1 if k == 0 else (1 if k == 3 else 0))
        self.market_hall(*self.at_center(OUTER_R + 11, 225))
        self.parked_bus(-(STREET_W / 2 - 3.7), -(OUTER_R + 13))

    def market_hall(self, x, z, yaw):
        """MARKTHALLE: Halle aus Sichtbeton und dunklen Metallpaneelen mit großem Tor zur Ringstraße; im Tor das
        Kraftfeld (GateGlow) und davor das Bodenfeld Portal_Market (Teleport in die Markt-Welt), darüber die Spielerzahl
        (GateCount_Market); Leuchtschild auf dem Dach, Bildschirme neben dem Tor, Fensterschlitze, Flachdach mit Oberlicht."""
        bm = self.bm

        def build(pb):
            W, D, H = 30, 22, 14
            concrete, panel = (196, 198, 200), (58, 62, 70)
            rap = (86, 214, 170)
            fz = -D / 2
            gw, gh = 12, 11
            pb.box("Buildings", "HallBody", (W, H, D - 1), (0, H / 2, 0.5), concrete, "Concrete")
            for s in (-1, 1):  # Vorderwand links und rechts vom Tor
                pb.box("Buildings", "HallFront", ((W - gw) / 2, H, 1), (s * (gw / 2 + (W - gw) / 4), H / 2, fz + 0.5), panel, "Metal")
                pb.box("Decor", "GatePilaster", (1.4, gh + 1, 1.4), (s * (gw / 2 + 0.7), (gh + 1) / 2, fz - 0.2), concrete, "Concrete")
                pb.box("Decor", "GateStrip", (0.3, gh - 0.5, 0.3), (s * (gw / 2 - 0.2), gh / 2, fz + 0.2), rap, "Neon")
                pb.box("Decor", "GateLantern", (0.8, 0.4, 2.4), (s * (gw / 2 + 0.7), gh - 0.6, fz - 1.6), (236, 240, 246), "SmoothPlastic",
                       children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 20, "Brightness": 1.1,
                                                                                            "Color": bm.rgb(220, 240, 255)}}])
                for lz in (-5, 0, 5):  # Fensterschlitze in den Seitenwänden
                    pb.box("Decor", "WindowGlass", (0.3, 9, 1.4), (s * (W / 2 + 0.1), 6.5, lz), GLASS_DARK, "Glass")
            pb.box("Buildings", "HallLintel", (gw + 0.2, H - gh, 1), (0, gh + (H - gh) / 2, fz + 0.5), panel, "Metal")
            pb.box("Decor", "GateArch", (gw + 2.8, 1.2, 1.6), (0, gh + 0.6, fz - 0.2), concrete, "Concrete")
            pb.box("Decor", "GateArchStrip", (gw + 2.8, 0.2, 0.2), (0, gh, fz - 1.05), rap, "Neon")
            pb.box("Decor", "GateGlow", (gw - 0.8, gh - 0.4, 0.3), (0, gh / 2, fz + 1.0), rap, "ForceField",
                   props={"Transparency": 0.25, "CanCollide": False},
                   children=[{"Name": "Light", "ClassName": "PointLight",
                              "Properties": {"Range": 18, "Brightness": 0.9, "Color": bm.rgb(*rap)}}])
            pb.box("Decor", "GateBack", (gw, gh, 0.4), (0, gh / 2, fz + 3.2), (20, 22, 26), "SmoothPlastic")
            pb.add("Portals", "Portal_Market", (gw - 1, 0.3, 6), (0, 0.4, fz - 1.2), rap, "Neon",
                   props={"CanCollide": False, "Transparency": 0.45})
            pb.box("Decor", "GateRamp", (gw + 4, 0.3, 9), (0, 0.2, fz - 3.5), (150, 152, 154), "Concrete")
            pb.floor_text("FloorLabel_Market", (10, 0.1, 2.6), (0, 0.4, fz - 6.5), "MARKT", rap, yaw=180)
            pb.holo_panel("Decor", "GateCount_Market", (9, 1.6, 0.3), (0, gh + 2.6, fz - 0.6))
            pb.sign2("Sign_Market", (18, 3.6, 0.4), (0, H + 2.4, fz + 0.6), "MARKTHALLE", "STÄNDE · HANDEL · RAP", (24, 26, 30), rap,
                     (236, 239, 243), glow=rap)
            for s in (-1, 1):
                pb.box("Decor", "SignPost", (0.4, 1.2, 0.4), (s * 7, H + 0.9, fz + 0.8), ANTHRACITE, "Metal")
            for s, title, sub in ((-1, "MARKT", "STÄNDE · HANDEL · RAP"), (1, "TAUSCHEN", "JEDEN TAG · JEDE NACHT")):
                pb.box("Decor", "MarketScreen", (6, 4, 0.3), (s * 9.5, 5.2, fz - 0.2), (22, 25, 30), "SmoothPlastic")
                pb.sign2("MarketPosterText", (5.6, 3.4, 0.1), (s * 9.5, 5.2, fz - 0.4), title, sub, (22, 25, 30), rap,
                         (226, 228, 232))
            pb.box("Buildings", "Roof", (W + 1, 0.8, D), (0, H + 0.4, 0.5), (96, 98, 102), "Concrete")
            pb.box("Decor", "Skylight", (W - 8, 0.4, 4), (0, H + 1.0, 2.5), (150, 190, 220), "Glass", props={"Transparency": 0.4})
            for s in (-1, 1):
                pb.box("Decor", "Parapet", (0.6, 1.2, D), (s * (W / 2 + 0.2), H + 1.2, 0.5), concrete, "Concrete")
            pb.box("Decor", "Parapet", (W + 1, 1.2, 0.6), (0, H + 1.2, D / 2 + 0.2), concrete, "Concrete")
            for sx in (-1, 1):
                pb.box("Decor", "RoofVent", (2.4, 1.6, 2), (sx * 10, H + 1.6, 5), LIGHT, "Metal")
        self._feature(build, x, z, yaw)

    def parked_bus(self, x, z):
        """Moderner Stadtbus am Bordstein der Südstraße vor dem Busbahnhof (Nase nach Süden)."""
        f, box = self.frame(x, z, 180)
        box("Cover", "BusBody", (7.4, 7.4, 24), (0, 4.6, 0), (232, 234, 236), "SmoothPlastic")
        box("Decor", "BusWindows", (7.5, 3.0, 21), (0, 6.0, 0.5), (34, 44, 54), "Glass")
        box("Decor", "BusStripe", (7.5, 0.8, 24.1), (0, 3.4, 0), (40, 150, 170), "SmoothPlastic")
        box("Decor", "BusFront", (7.0, 5.4, 0.2), (0, 5.2, -12.05), (34, 44, 54), "Glass")
        box("Decor", "BusDestination", (5, 0.9, 0.2), (0, 8.0, -12.1), (255, 170, 60), "Neon")
        for lz in (-8, 8):
            for s in (-1, 1):
                box("Decor", "BusWheel", (1, 2.4, 2.4), (s * 3.6, 1.2, lz), (26, 26, 26), "Rubber", props={"Shape": "Cylinder"})

    # ---------- Höfe ----------
    def yard_pad(self, base, color, mat, alleys=((45, 4.6),)):
        """Boden eines Hofs: Ring zwischen Häuserring und Mauer, von Straße zu Straße; Gassen (Winkel ab base, halbe
        Breite in Grad) von der Ringstraße in den Hof."""
        a = math.degrees(math.asin((LINE + 1.5) / ((YARD_R0 + YARD_R1) / 2)))
        self.arc_pad("YardGround", YARD_R0, YARD_R1, base + a, base + 90 - a, color, mat, 0.08, step=6)
        for th, half in alleys:
            self.arc_pad("Sidewalk", OUTER_R - 0.5, YARD_R0 + 1, base + th - half, base + th + half, LIGHT, "Concrete", 0.14, step=5)

    def kiosk(self, x, z, yaw, title, sub, accent, look):
        """Food-Kiosk aus einem Container: offene Front mit Theke, Händler dahinter, flaches Vordach mit Leuchtkante,
        Schild auf dem Dach."""
        f, box = self.frame(x, z, yaw)
        L, D, H = 10, 6, 7.5
        box("Buildings", "KioskBack", (L, H, 0.4), (0, H / 2, D / 2 - 0.2), accent, "Metal")
        for s in (-1, 1):
            box("Buildings", "KioskSide", (0.4, H, D), (s * (L / 2 - 0.2), H / 2, 0), accent, "Metal")
        box("Buildings", "KioskFloor", (L, 0.4, D), (0, 0.2, 0), LIGHT, "Concrete")
        box("Buildings", "Roof", (L + 0.4, 0.5, D + 0.4), (0, H + 0.25, 0), ANTHRACITE, "Metal")
        box("Decor", "KioskCanopy", (L, 0.25, 2.4), (0, H - 0.8, -D / 2 - 1.2), ANTHRACITE, "Metal")
        box("Decor", "CanopyStrip", (L, 0.15, 0.15), (0, H - 0.8, -D / 2 - 2.4), WHITE, "Neon", props=dict(NO_HIT))
        box("Buildings", "Counter", (L - 1, 3.5, 1), (0, 2.15, -D / 2 + 0.6), WHITE, "SmoothPlastic")
        box("Decor", "CounterTop", (L - 0.6, 0.25, 1.4), (0, 4.0, -D / 2 + 0.6), ANTHRACITE, "SmoothPlastic")
        self.shopkeeper(box, 0, -D / 2 + 2.2, look, y=0.4)
        box("Decor", "KioskLight", (L - 2, 0.15, D - 2), (0, H - 0.1, 0), (250, 248, 240), "SmoothPlastic",
            children=[{"Name": "Light", "ClassName": "SurfaceLight", "Properties": {
                "Face": "Bottom", "Range": 12, "Brightness": 1.0, "Angle": 120, "Color": self.bm.rgb(255, 246, 230)}}])
        self.b.sign2("KioskSign", (8, 2, 0.3), f(0, H + 1.6, -D / 2 + 0.6), title, sub, (24, 26, 30), WHITE, (220, 222, 226),
                     angles=(0, yaw, 0), glow=accent)

    def yard_food(self):
        """NO: Food-Court hinter dem Marktviertel – zwei Kioske an der Gasse, am Ende der Gasse der Schieber-Transporter
        (Stand_Red)."""
        self.yard_pad(0, (150, 150, 146), "Concrete")
        self.arc_pad("Sidewalk", YARD_R0, YARD_R1 - 6, 40.5, 49.5, LIGHT, "Concrete", 0.14, step=5)
        for th, title, sub, accent, look in ((31, "GARKÜCHE", "HEUTE: EINTOPF", (176, 60, 40), "kiosk"),
                                             (59, "ELEKTRONIK", "FUNKGERÄTE · AKKUS", (60, 110, 160), "kiosk2")):
            x, z = P(93, th)
            lx, lz = P(93, 45)
            self.kiosk(x, z, self.yaw_to(lx - x, lz - z), title, sub, accent, OUTFITS[look])
        self.schieber(*self.at_center(103, 45))

    def yard_motor_pool(self):
        """SO: Fuhrpark – Tankstelle, Landeplatz am Ende der Gasse, Parkplatz mit Ladesäulen und zwei Autos."""
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
            self.b.box("Ground", "ParkingLine", (0.4, 0.05, 11), (x, 0.12, z), (226, 226, 220), "SmoothPlastic", angles=(0, yaw, 0))
            cx, cz, cyaw = self.at_center(102, th + 3)
            f, box = self.frame(cx, cz, cyaw)
            box("Decor", "Charger", (1.2, 3.6, 0.8), (0, 1.8, 0), WHITE, "SmoothPlastic")
            box("Decor", "ChargerLight", (0.8, 0.3, 0.1), (0, 3.0, -0.42), (90, 220, 140), "Neon", props=dict(NO_HIT))
        for th, color in ((158, (40, 44, 52)), (170, (196, 200, 206))):
            x, z, yaw = self.at_center(95, th)
            self.parked_car(x, z, yaw + 180, color)

    def parked_car(self, x, z, yaw, color):
        """Modernes Auto (heil, sauber): Karosserie, Glasdach, Räder, Lichter."""
        f, box = self.frame(x, z, yaw)
        box("Cover", "CarBody", (4.6, 2.0, 9.4), (0, 1.6, 0), color, "SmoothPlastic")
        box("Decor", "CarCabin", (4.2, 1.7, 5.0), (0, 3.4, 0.4), (34, 44, 54), "Glass", props={"Reflectance": 0.2})
        for lx in (-2.2, 2.2):
            for lz in (-3, 3):
                box("Decor", "CarWheel", (0.6, 1.6, 1.6), (lx, 0.8, lz), (24, 24, 26), "Rubber", props={"Shape": "Cylinder"})
        box("Decor", "CarLights", (4.0, 0.3, 0.1), (0, 2.1, -4.72), (236, 240, 255), "Neon", props=dict(NO_HIT))
        box("Decor", "CarTail", (4.0, 0.3, 0.1), (0, 2.1, 4.72), (220, 40, 40), "Neon", props=dict(NO_HIT))

    def fuel_station(self, x, z, yaw):
        """Zapfinsel: Flachdach auf vier Stützen mit Leuchtkante, zwei Zapfsäulen, Schild."""
        b = self.b
        f, box = self.frame(x, z, yaw)
        box("Buildings", "Roof", (16, 0.6, 10), (0, 9, 0), WHITE, "SmoothPlastic")
        box("Decor", "CanopyTrim", (16.2, 1.2, 10.2), (0, 8.2, 0), (176, 60, 44), "SmoothPlastic")
        for sx in (-1, 1):
            for sz in (-1, 1):
                box("Decor", "CanopyPost", (0.7, 8, 0.7), (sx * 6.5, 4, sz * 3.5), LIGHT, "Metal")
        box("Cover", "PumpIsland", (11, 0.6, 2.4), (0, 0.3, 0), LIGHT, "Concrete")
        for lx in (-3, 3):
            box("Cover", "FuelPump", (1.8, 4.2, 1.2), (lx, 2.7, 0), WHITE, "SmoothPlastic")
            box("Decor", "PumpScreen", (1.2, 0.8, 0.1), (lx, 3.8, -0.65), (90, 200, 120), "Neon")
            box("Decor", "PumpStripe", (1.85, 0.4, 1.25), (lx, 4.5, 0), (176, 60, 44), "SmoothPlastic")
        b.sign2("FuelStationSign", (8, 1.8, 0.3), f(0, 10.4, -5.2), "TANKSTELLE", "NUR GEGEN BARES", (24, 26, 30),
                (236, 200, 90), (214, 212, 202), angles=(0, yaw, 0))

    def yard_depot(self):
        """SW: Depot hinter der Markthalle – Container in einer Reihe, darüber der Portalkran, Paletten, Gabelstapler."""
        rng = self.rng
        self.yard_pad(180, (96, 96, 92), "Concrete", alleys=((28, 3.4), (62, 3.4)))
        cols = ((60, 86, 110), (176, 60, 44), (70, 84, 104), (210, 170, 60), (220, 220, 214))
        x, z, yaw = self.at_center(98, 209)
        self.container(x, z, yaw, rng.choice(cols), doors=True)
        self.container(x, z, yaw, rng.choice(cols), y=8.5)
        for th in (225, 241):
            x, z, yaw = self.at_center(98, th)
            self.container(x, z, yaw, rng.choice(cols))
        gx, gz, gyaw = self.at_center(98, 225)
        f, box = self.frame(gx, gz, gyaw)
        for s in (-1, 1):
            for lz in (-5, 5):
                box("Buildings", "CraneLeg", (1.2, 17, 1.2), (s * 14, 8.5, lz), (230, 180, 40), "Metal")
        box("Buildings", "CraneBeam", (30, 1.8, 11.2), (0, 17.6, 0), (230, 180, 40), "Metal")
        box("Decor", "CraneHook", (0.2, 5, 0.2), (3, 14.5, 0), (40, 40, 40), "Metal")
        box("Decor", "CraneLight", (1, 1, 1), (0, 18.8, 0), (255, 60, 40), "Neon")
        self.forklift(*P(90, 243), 200)
        x, z, yaw = self.at_center(92, 206)
        f, box = self.frame(x, z, yaw)
        for lx in (-3, 0, 3):
            for j in range(2):
                box("Cover", "Pallet", (2.6, 0.5, 2.6), (lx, 0.25 + j * 1.6, 0), (170, 140, 100), "WoodPlanks")
                box("Cover", "PalletLoad", (2.4, 1.1, 2.4), (lx, 1.05 + j * 1.6, 0), (214, 210, 200), "SmoothPlastic")

    def forklift(self, x, z, yaw):
        """Gabelstapler (gelb) mit Mast und Gabel nach lokal -Z."""
        f, box = self.frame(x, z, yaw)
        yel = (230, 180, 40)
        box("Cover", "ForkliftBody", (3.4, 2.4, 4.6), (0, 1.6, 0.4), yel, "Metal")
        box("Decor", "ForkliftCage", (3.2, 2.6, 2.4), (0, 4.1, 0.8), (40, 40, 42), "Metal", props={"Transparency": 0.6})
        box("Decor", "ForkliftMast", (2.8, 5.4, 0.4), (0, 2.9, -2.1), (50, 50, 52), "Metal")
        for lx in (-0.8, 0.8):
            box("Decor", "ForkliftFork", (0.4, 0.2, 3), (lx, 0.4, -3.6), (50, 50, 52), "Metal")
        for lx in (-1.7, 1.7):
            for lz in (-1.2, 2):
                box("Decor", "ForkliftWheel", (0.6, 1.4, 1.4), (lx, 0.7, lz), (24, 24, 26), "Rubber", props={"Shape": "Cylinder"})

    def yard_sports(self):
        """NW: Sportplatz (umzäunter Basketballplatz), Solarfeld mit Speicher und an der Nordstraße der
        Abgang zu den KATAKOMBEN (Dungeon-Eingang)."""
        self.yard_pad(270, (120, 122, 124), "Concrete")
        self.sports_court(*self.at_center(95, 297))
        x0, z0, yaw = self.at_center(96, 327)
        f, box = self.frame(x0, z0, yaw)
        for row in range(3):  # Solarmodule in drei Reihen, nach Süden geneigt
            for k in range(3):
                lx, lz = -7 + k * 7, -6 + row * 6
                box("Decor", "SolarPanel", (6.4, 0.25, 3.4), (lx, 2.2, lz), (30, 40, 62), "Glass", extra=(22, 0, 0),
                    props={"Reflectance": 0.3})
                for s in (-1, 1):
                    box("Decor", "SolarLeg", (0.25, 2, 0.25), (lx + s * 2.6, 1.0, lz), STEEL, "Metal")
        bx, bz, byaw = self.at_center(104, 283)
        f, box = self.frame(bx, bz, byaw)
        box("Buildings", "BatteryBox", (9, 4, 3.6), (0, 2, 0), WHITE, "SmoothPlastic")
        box("Decor", "BatteryStrip", (9.05, 0.25, 3.65), (0, 3.3, 0), (90, 220, 140), "Neon", props=dict(NO_HIT))
        gx, gz = P(93, 344)
        self.crypt_gate(gx, gz + 2.5, self.yaw_to(1, 0))  # Front zur Nordstraße (nach Osten)

    def sports_court(self, x, z, yaw):
        """Basketballplatz: blauer Belag mit Linien, Körbe an den Enden, Gitterzaun mit Öffnung zur Mitte."""
        f, box = self.frame(x, z, yaw)
        L, Wd = 26, 15
        white = (236, 236, 230)
        box("Ground", "CourtBorder", (L + 3, 0.2, Wd + 3), (0, 0.2, 0), (176, 76, 56), "SmoothPlastic")
        box("Ground", "CourtFloor", (L, 0.2, Wd), (0, 0.25, 0), (52, 96, 150), "SmoothPlastic")
        for lx, lz, sx, sz in ((0, 0, 0.25, Wd), (0, -Wd / 2 + 0.15, L, 0.25), (0, Wd / 2 - 0.15, L, 0.25),
                               (-L / 2 + 0.15, 0, 0.25, Wd), (L / 2 - 0.15, 0, 0.25, Wd)):
            box("Ground", "CourtLine", (sx, 0.05, sz), (lx, 0.37, lz), white, "SmoothPlastic")
        box("Ground", "CourtCircle", (0.05, 4, 4), (0, 0.37, 0), (176, 76, 56), "SmoothPlastic", extra=(0, 0, 90),
            props={"Shape": "Cylinder"})
        for s in (-1, 1):
            box("Ground", "CourtKey", (5, 0.05, 5), (s * (L / 2 - 2.5), 0.36, 0), (176, 76, 56), "SmoothPlastic")
            box("Decor", "HoopPole", (0.5, 9, 0.5), (s * (L / 2 + 0.6), 4.5, 0), ANTHRACITE, "Metal")
            box("Decor", "HoopArm", (1.6, 0.3, 0.3), (s * (L / 2 - 0.1), 8.6, 0), ANTHRACITE, "Metal")
            box("Decor", "Backboard", (0.2, 3, 4.5), (s * (L / 2 - 0.9), 8.6, 0), white, "SmoothPlastic")
            box("Decor", "HoopRim", (1.4, 0.12, 1.4), (s * (L / 2 - 1.7), 7.6, 0), (240, 110, 40), "Metal")
        fence = {"Transparency": 0.6}
        fl, fw = L + 3, Wd + 3
        box("Buildings", "CourtFence", (fl, 6, 0.2), (0, 3, fw / 2), (60, 64, 70), "Metal", props=fence)
        for s in (-1, 1):
            box("Buildings", "CourtFence", (0.2, 6, fw), (s * fl / 2, 3, 0), (60, 64, 70), "Metal", props=fence)
            box("Buildings", "CourtFence", ((fl - 6) / 2, 6, 0.2), (s * (fl + 6) / 4, 3, -fw / 2), (60, 64, 70), "Metal", props=fence)
        for lx in (-fl / 2, -3, 3, fl / 2):
            for lz in (-fw / 2, fw / 2):
                box("Decor", "FencePost", (0.4, 6.4, 0.4), (lx, 3.2, lz), ANTHRACITE, "Metal")

    def crypt_gate(self, x, z, yaw):
        """ABGANG ZU DEN KATAKOMBEN (Dungeon-Eingang): Portal aus dunklem Sichtbeton mit auskragendem Dach, im Tor eine
        Treppe ins Dunkle und violett flimmerndes Licht, Leuchtrahmen; davor zwei Lichtpoller und ein Weg zur Straße. Der
        Punkt DungeonGate (Gruppe Zentrale, unsichtbar) vor der Tür trägt auf dem Server die E-Aufforderung
        (DungeonService). Ohne Zufallszahlen."""
        f, box = self.frame(x, z, yaw)
        W, D, H = 12, 10, 7.5
        fz = -D / 2
        concrete, dark = (70, 72, 78), (36, 38, 44)
        purple, door_w, door_h = (170, 90, 255), 5, 6.2
        box("Decor", "CryptPlinth", (W + 0.6, 0.6, D + 0.6), (0, 0.3, 0), LIGHT, "Concrete")
        box("Buildings", "CryptWall", (W, H, 1), (0, H / 2, D / 2 - 0.5), concrete, "Concrete")
        for s in (-1, 1):
            box("Buildings", "CryptWall", (1, H, D), (s * (W / 2 - 0.5), H / 2, 0), concrete, "Concrete")
            pw = (W - door_w) / 2
            box("Buildings", "CryptWall", (pw, H, 1), (s * (door_w / 2 + pw / 2), H / 2, fz + 0.5), concrete, "Concrete")
            box("Decor", "CryptFrame", (0.25, door_h, 0.3), (s * (door_w / 2 + 0.15), door_h / 2, fz - 0.05), purple, "Neon",
                props=dict(NO_HIT))
            box("Decor", "CryptBollard", (0.8, 1.4, 0.8), (s * 4.4, 0.7, fz - 2.6), dark, "Metal")
            box("Decor", "Lantern", (0.82, 0.3, 0.82), (s * 4.4, 1.55, fz - 2.6), (200, 150, 255), "Neon", props={"CanCollide": False},
                children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 14, "Brightness": 1.2,
                                                                                     "Color": self.bm.rgb(190, 130, 255)}}])
        box("Buildings", "CryptWall", (door_w, H - door_h, 1), (0, door_h + (H - door_h) / 2, fz + 0.5), concrete, "Concrete")
        box("Decor", "CryptFrame", (door_w + 0.6, 0.25, 0.3), (0, door_h + 0.12, fz - 0.05), purple, "Neon", props=dict(NO_HIT))
        box("Buildings", "CryptRoof", (W + 2, 0.8, D + 3), (0, H + 0.4, -1), dark, "Concrete")
        box("Decor", "CryptRoofStrip", (W + 2, 0.15, 0.15), (0, H, fz - 2.45), purple, "Neon", props=dict(NO_HIT))
        # Treppe ins Dunkle mit violettem Flimmern
        box("Decor", "CryptFloor", (W - 2, 0.3, D - 2), (0, 0.65, 0.5), (16, 14, 20), "Slate")
        for k in range(4):
            box("Decor", "CryptStair", (door_w - 0.4, 0.06, 1.2), (0, 0.83, fz + 1.6 + k * 1.2),
                (60 - k * 12, 58 - k * 12, 66 - k * 12), "Concrete")
        box("Decor", "Doorway", (door_w, door_h, 0.3), (0, door_h / 2, fz + 6.4), (8, 6, 12), "SmoothPlastic")
        box("Decor", "CryptRift", (door_w - 0.4, door_h - 0.4, 0.2), (0, door_h / 2, fz + 5.8), purple, "Neon",
            props={"CanCollide": False, "Transparency": 0.55, "CastShadow": False},
            children=[{"Name": "Light", "ClassName": "PointLight", "Properties": {"Range": 18, "Brightness": 1.8,
                                                                                 "Color": self.bm.rgb(*purple)}}])
        self.b.sign2("CryptSign", (8, 1.8, 0.3), f(0, H + 1.8, fz - 0.6), "KATAKOMBEN", "DUNGEON · E MIT DUNGEON-SCHLÜSSEL",
                     (24, 20, 30), (210, 160, 255), (214, 206, 224), angles=(0, yaw, 0), glow=purple)
        for s in (-1, 1):
            box("Decor", "SignPost", (0.3, 1.1, 0.3), (s * 3, H + 0.75, fz - 0.6), dark, "Metal")
        # Weg zur Straße
        box("Ground", "Sidewalk", (4.6, 0.2, 9), (0, 0.04, fz - 2.3 - 4.5), LIGHT, "Concrete")
        self.b.add("Zentrale", "DungeonGate", (2, 2, 2), f(0, 3, fz - 3.5), purple, "SmoothPlastic", angles=(0, yaw, 0),
                   props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    def schieber(self, x, z, yaw):
        """Schwarzmarkt: schwarzer Transporter mit offener Seitentür (Kisten, rotes Licht), daneben der Schieber mit
        Kapuze (Punkt Stand_Red: Händler für Rote-Zone-Punkte), dunkle Sichtschutzwände."""
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
        box("Decor", "SchieberCaseStand", (1.6, 0.6, 1.1), (0.9, 0.3, -3.6), ANTHRACITE, "Metal")
        self.shopkeeper(box, -2.2, -4.2, dict(shirt=(34, 34, 38), pants=(28, 28, 32), hood=True, skin=1), pose="stand")
        box("Decor", "NpcScarf", (1.3, 0.5, 1.25), (-2.2, 5.3, -4.25), (150, 30, 30), "Fabric", props=dict(NO_HIT))
        for lx in (-9, 10):
            box("Decor", "ScreenWall", (0.3, 6, 7), (lx, 3, -1), ANTHRACITE, "Metal")
        b.add("Stands", "Stand_Red", (2, 2, 2), f(-2.2, 2.5, -7.2), (200, 60, 60), "SmoothPlastic", angles=(0, yaw, 0),
              props={"Transparency": 1, "CanCollide": False, "CanQuery": False, "CanTouch": False})

    # ---------- Mauer, Tore, Vorfeld ----------
    def camp_wall(self):
        """Ringmauer aus Betonfertigteilen mit Pfeilern und Stacheldraht; vier Tore."""
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
                box("Walls", "WallPanel", (seg, 10, 1.2), (0, 5, 0), rng.choice(((176, 176, 172), (170, 170, 166), (182, 180, 176))),
                    "Concrete")
                box("Decor", "WallPost", (1, 11, 1.6), (seg / 2, 5.5, 0), (130, 130, 128), "Concrete")
                b.add("Walls", "RazorWire", (seg, 1.4, 1.4), f(0, 11.4, 0), (128, 128, 126), "Metal",
                      angles=(0, yaw + 90, 90), props={"Shape": "Cylinder"})
                if k % 4 == 2:
                    box("Decor", "WallLamp", (0.8, 0.6, 0.8), (0, 10.3, -0.9), (236, 240, 246), "SmoothPlastic",
                        children=[{"Name": "Light", "ClassName": "SpotLight", "Properties": {
                            "Face": "Bottom", "Range": 18, "Brightness": 1.0, "Angle": 110, "Color": self.bm.rgb(236, 240, 255)}}])
                if k % 4 == 0:  # Leuchtband innen
                    box("Decor", "WallStrip", (seg, 0.2, 0.1), (0, 8.5, -0.65), PHOENIX, "Neon", props=dict(NO_HIT))
        for th in (0, 90, 180, 270):
            self.camp_gate(th)

    def camp_gate(self, th):
        """Tor: zwei Container-Türme mit Wachplattform, offene Stahlflügel, Balken mit Schild (außen CAMP PHOENIX,
        innen AUSGANG), Sandsack-Nester, Scheinwerfer, draußen Betonblöcke als Schikane."""
        b, rng = self.b, self.rng
        R = CAMP_WALL_R
        x, z, yaw = self.at_center(R, th)
        f, box = self.frame(x, z, yaw)  # lokal -Z = nach innen
        cont = rng.choice(((60, 64, 72), (46, 50, 56), (70, 84, 104)))
        for s in (-1, 1):
            lx = s * (GATE_W / 2 + 3.5)
            box("Walls", "GateContainer", (7, 8.5, 8), (lx, 4.25, 0), cont, "Metal")
            box("Walls", "GateContainerTop", (7, 8.5, 8), (lx, 12.75, 0), self.bm.lighten(cont, -0.15), "Metal")
            box("Decor", "GateStripe", (7.05, 0.4, 8.05), (lx, 8.5, 0), PHOENIX, "Neon", props=dict(NO_HIT))
            box("Decor", "GateRail", (7.4, 1.2, 0.3), (lx, 17.6, -4.1), STEEL, "Metal")
            box("Decor", "GateRail", (7.4, 1.2, 0.3), (lx, 17.6, 4.1), STEEL, "Metal")
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
                    (24, 26, 30), (240, 170, 90) if outside else (220, 70, 56), (214, 212, 202), angles=(0, yaw + yaw_off, 0))
        for lx, lz in ((-5, 9), (5, 16)):
            box("Cover", "JerseyBarrier", (8, 3, 2.2), (lx, 1.5, lz), (176, 176, 170), "Concrete", extra=(0, rng.uniform(-6, 6), 0))

    def glacis(self):
        """Vorfeld zwischen Mauer und Stadt: nahe der Mauer Panzersperren und Stacheldraht-Rollen, weiter draußen
        vereinzelt Wracks; keine Bäume, kein Gestrüpp; Warnschilder. Die Zufahrten bleiben frei."""
        b, rng = self.b, self.rng
        R = CAMP_WALL_R
        placed = []
        for k in range(90):
            th = rng.uniform(0, 360)
            if near_axis(th, 10):
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
        for th in (45, 135, 225, 315):
            x, z, yaw = self.at_center(R + 9, th)
            self.warning_sign(x, z, yaw + 180, "SPERRZONE", "NICHT STEHEN BLEIBEN · SCHUSSFELD")

#!/usr/bin/env python3
"""Baut aus dem MP7-Modell (art/sources/mp7a1.glb) die SMG: assets/Weapons/SMG.rbxmx.

Roblox kann in einer .rbxmx kein Mesh mitbringen (das braucht eine hochgeladene Mesh-ID). Deshalb ist die SMG hier
aus Quadern und Zylindern nachgebaut, die Maße stammen aus dem GLB (Silhouette, Magazin, Kimme, Korn, Schalldämpfer
bleibt weg: den baut das Spiel als Aufsatz an die Mündung). Teilnamen und Marker folgen docs/waffen-modelle.md.
Das echte Mesh kannst du in Studio über Import 3D aus art/sources/mp7a1.glb laden.

    python3 tools/mp7_model.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import weapon_templates as wt  # noqa: E402

SCALE = 0.571  # 4,16 GLB-Einheiten (Schulterstütze bis Mündung) -> 2,38 Studs wie die alte SMG
POLYMER, STEEL, BLACKMETAL, DOT = (38, 38, 40), (112, 112, 118), (28, 28, 30), (255, 190, 60)
Y_SIGHT = 0.90  # Visierlinie (GLB-Einheiten)
X_REAR, X_FRONT = -1.40, 0.95

# (Name, Form, (x0, x1), (y0, y1), (z0, z1), Farbe, Material) in GLB-Einheiten: x = nach vorn, y = oben, z = rechts
PARTS = [
	("Skin_ReceiverRear", "Block", (-1.88, -0.10), (0.02, 0.80), (-0.20, 0.20), POLYMER, "Plastic"),
	("Skin_ReceiverFront", "Block", (-0.10, 1.67), (0.12, 0.80), (-0.18, 0.18), POLYMER, "Plastic"),
	("Skin_Grip", "Block", (-1.00, -0.10), (-0.89, 0.02), (-0.19, 0.19), POLYMER, "Plastic"),
	("Magazine", "Block", (-0.76, -0.15), (-1.32, 0.20), (-0.12, 0.12), BLACKMETAL, "Metal"),
	("Skin_Stock", "Block", (-2.08, -1.64), (-0.54, 0.57), (-0.21, 0.21), POLYMER, "Plastic"),
	("StockRailL", "Block", (-1.64, -0.10), (0.37, 0.49), (-0.18, -0.12), STEEL, "Metal"),
	("StockRailR", "Block", (-1.64, -0.10), (0.37, 0.49), (0.12, 0.18), STEEL, "Metal"),
	("Barrel", "Cylinder", (1.67, 2.08), (0.25, 0.36), (-0.055, 0.055), STEEL, "Metal"),
	("FlashHider", "Cylinder", (1.46, 2.08), (0.23, 0.38), (-0.075, 0.075), BLACKMETAL, "Metal"),
	("Foregrip", "Block", (0.28, 1.33), (-0.17, 0.14), (-0.11, 0.11), POLYMER, "Plastic"),
	("Bolt", "Block", (-1.88, -0.58), (0.56, 0.75), (-0.19, 0.19), BLACKMETAL, "Metal"),
	# Kimme: Sockel mit zwei Pfosten (Lücke in der Mitte = Visierlinie)
	("RearBase", "Block", (-1.66, -1.15), (0.80, 0.86), (-0.17, 0.17), BLACKMETAL, "Metal"),
	("RearL", "Block", (-1.50, -1.30), (0.86, 0.97), (-0.17, -0.07), BLACKMETAL, "Metal"),
	("RearR", "Block", (-1.50, -1.30), (0.86, 0.97), (0.07, 0.17), BLACKMETAL, "Metal"),
	# Korn im Ring
	("FrontBase", "Block", (0.70, 1.18), (0.80, 0.84), (-0.16, 0.16), BLACKMETAL, "Metal"),
	("FrontPost", "Block", (0.90, 1.00), (0.84, 0.94), (-0.02, 0.02), BLACKMETAL, "Metal"),
	("Neon_FrontDot", "Block", (0.90, 1.00), (0.92, 0.95), (-0.025, 0.025), DOT, "Neon"),
	("FrontWingL", "Block", (0.90, 1.00), (0.84, 0.95), (-0.16, -0.12), BLACKMETAL, "Metal"),
	("FrontWingR", "Block", (0.90, 1.00), (0.84, 0.95), (0.12, 0.16), BLACKMETAL, "Metal"),
]

# Marker (GLB-Einheiten)
POINTS = [
	("Point_Grip", (-0.55, -0.52, 0)),
	("Point_SightRear", (X_REAR, Y_SIGHT, 0)),
	("Point_SightFront", (X_FRONT, Y_SIGHT, 0)),
	("Point_Muzzle", (2.08, 0.305, 0)),
	("Point_Eject", (0.20, 0.55, 0.20)),
	("Point_LeftHand", (0.80, -0.02, 0)),
	("Point_Stock", (-2.08, 0.30, 0)),
]


def to_roblox(p):
	"""GLB (x vorn, y oben, z rechts) -> Roblox (Lauf nach -Z), skaliert."""
	x, y, z = p
	return (z * SCALE, y * SCALE, -x * SCALE)


def build():
	parts = []
	for name, shape, xs, ys, zs, color, material in PARTS:
		center = to_roblox(((xs[0] + xs[1]) / 2, (ys[0] + ys[1]) / 2, (zs[0] + zs[1]) / 2))
		lx, ly, lz = (xs[1] - xs[0]) * SCALE, (ys[1] - ys[0]) * SCALE, (zs[1] - zs[0]) * SCALE
		if shape == "Cylinder":  # Roblox-Zylinder liegen entlang X: um Y drehen, damit sie entlang Z liegen
			cframe, size = [*center, 0, 0, -1, 0, 1, 0, 1, 0, 0], (lx, ly, lz)
		else:
			cframe, size = [*center, 1, 0, 0, 0, 1, 0, 0, 0, 1], (lz, ly, lx)
		parts.append({"name": name, "shape": shape, "cframe": cframe, "size": size, "color": color,
		              "material": material, "transparency": 0.0})
	parts += wt.marker_parts([(name, to_roblox(p)) for name, p in POINTS])
	return parts


def main():
	out = os.path.join(ROOT, "assets", "Weapons")
	os.makedirs(out, exist_ok=True)
	wt.OUT = out
	parts = build()
	wt.write_rbxmx("SMG", parts)
	print("SMG: %d Teile -> assets/Weapons/SMG.rbxmx" % len(parts))


if __name__ == "__main__":
	main()

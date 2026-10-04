#!/usr/bin/env python3
"""Erzeugt tests/fixtures/assets/Weapons/Rifle.rbxmx: ein Sturmgewehr so, wie Studio es nach einem
FBX-Import aus Blender per "Save to File..." speichert (gedreht und verschoben, MeshParts mit Mesh-Ids,
SurfaceAppearance, Untermodell, Marker als Teile und als Attachment, Textur-Skin-Ordner).
Benutzt von tests/rbxmx.test.luau. Neu erzeugen: python3 tests/fixtures/make_rifle_fixture.py
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "assets", "Weapons", "Rifle.rbxmx")

MATERIAL = {"Plastic": 256, "Metal": 1088, "Glass": 1568}
_ref = [0]


def referent():
    _ref[0] += 1
    return "RBX%08X" % (0x5EED0000 + _ref[0])


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rot_x(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def rot_y(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
# Import: Blender ist Z-oben – gekippt und irgendwo im Raum abgelegt
IMPORT_ROT = mat_mul(rot_x(-90), rot_y(35))
IMPORT_POS = (10.0, 2.0, -4.0)


def world(position, rotation=IDENTITY):
    """Waffenraum -> Welt (wie nach dem Import)."""
    p = [sum(IMPORT_ROT[i][k] * position[k] for k in range(3)) + IMPORT_POS[i] for i in range(3)]
    return p, mat_mul(IMPORT_ROT, rotation)


def cframe_xml(name, position, rotation):
    keys = ("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")
    values = [rotation[i][j] for i in range(3) for j in range(3)]
    parts = ["<X>%r</X><Y>%r</Y><Z>%r</Z>" % tuple(position)]
    parts += ["<%s>%r</%s>" % (k, v, k) for k, v in zip(keys, values)]
    return '<CoordinateFrame name="%s">%s</CoordinateFrame>' % (name, "".join(parts))


def vector_xml(name, v):
    return '<Vector3 name="%s"><X>%r</X><Y>%r</Y><Z>%r</Z></Vector3>' % (name, v[0], v[1], v[2])


def color_xml(rgb):
    return '<Color3uint8 name="Color3uint8">%d</Color3uint8>' % ((0xFF << 24) | (rgb[0] << 16) | (rgb[1] << 8) | rgb[2])


def item(cls, props, children=()):
    return '<Item class="%s" referent="%s"><Properties>%s</Properties>%s</Item>' % (
        cls, referent(), "".join(props), "".join(children))


def surface(name, color_map):
    return item("SurfaceAppearance", [
        '<token name="AlphaMode">1</token>',
        '<Content name="ColorMap"><url>%s</url></Content>' % color_map,
        '<string name="Name">%s</string>' % name,
    ])


def mesh_part(name, size, position, rgb=(60, 62, 68), material="Metal", transparency=0.0, rotation=IDENTITY,
              children=(), mesh_id=1000):
    pos, rot = world(position, rotation)
    return item("MeshPart", [
        '<bool name="Anchored">true</bool>',
        '<BinaryString name="AttributesSerialize"></BinaryString>',
        cframe_xml("CFrame", pos, rot),
        '<bool name="CanCollide">true</bool>',
        color_xml(rgb),
        vector_xml("InitialSize", size),
        '<token name="Material">%d</token>' % MATERIAL[material],
        '<Content name="MeshId"><url>rbxassetid://%d</url></Content>' % mesh_id,
        '<string name="Name">%s</string>' % name,
        '<float name="Transparency">%r</float>' % transparency,
        vector_xml("size", size),
    ], children)


def attachment(name, local_position):
    return item("Attachment", [
        cframe_xml("CFrame", local_position, IDENTITY),
        '<string name="Name">%s</string>' % name,
    ])


def marker(name, position):
    return mesh_part(name, (0.05, 0.05, 0.05), position, rgb=(255, 0, 255), material="Plastic", mesh_id=9999)


def main():
    tilt = rot_x(10)
    stock_center = (0, 0.35, 0.95)
    stock_attachment = (0, 0.35 - stock_center[1], 1.4 - stock_center[2])  # im Schaft: hinteres Ende
    rifle = item("Model", [
        '<string name="Name">Rifle</string>',
        '<Ref name="PrimaryPart">null</Ref>',
        '<BinaryString name="Tags"></BinaryString>',
    ], [
        mesh_part("Skin_Receiver", (0.35, 0.45, 1.8), (0, 0.4, -0.35), mesh_id=1001,
                  children=[surface("SurfaceAppearance", "rbxassetid://2001")]),
        item("Model", ['<string name="Name">Mesh</string>'], [
            mesh_part("Barrel", (0.14, 0.14, 0.6), (0, 0.48, -2.25), rgb=(25, 25, 28), mesh_id=1002),
            mesh_part("Handguard.001", (0.3, 0.32, 0.75), (0, 0.44, -1.6), mesh_id=1003),
        ]),
        mesh_part("Stock_Skin", (0.3, 0.5, 0.9), stock_center, rgb=(90, 70, 50), material="Plastic", mesh_id=1004,
                  children=[attachment("Point_Stock", stock_attachment)]),
        mesh_part("Magazine", (0.24, 0.62, 0.34), (0, -0.08, -0.65), rgb=(20, 20, 22), rotation=tilt, mesh_id=1005),
        mesh_part("Bolt", (0.22, 0.06, 0.1), (0, 0.6, 0.6), rgb=(20, 20, 22), mesh_id=1006),
        mesh_part("Glass_Optic", (0.26, 0.21, 0.008), (0, 0.9, -0.36), rgb=(120, 200, 215), material="Glass",
                  transparency=0.5, mesh_id=1007),
        marker("Point_Grip", (0, 0, 0)),
        marker("Point_SightRear", (0, 0.9, -0.36)),
        marker("Point_SightFront", (0, 0.9, -0.6)),
        marker("Point_Muzzle", (0, 0.48, -2.6)),
        marker("Point_Eject", (0.18, 0.47, -0.3)),
        marker("Point_LeftHand", (-0.03, 0.27, -1.55)),
        item("Folder", ['<string name="Name">Skins</string>'], [
            item("Folder", ['<string name="Name">W_Lava</string>'], [surface("Skin_Receiver", "rbxassetid://3001")]),
        ]),
    ])
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
           '\t<Meta name="ExplicitAutoJoints">true</Meta>\n\t<External>null</External>\n\t<External>nil</External>\n\t'
           + rifle + "\n</roblox>\n")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(xml)
    print("geschrieben:", os.path.relpath(OUT, os.path.dirname(HERE)))


if __name__ == "__main__":
    main()

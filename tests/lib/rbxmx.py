"""Roblox-Modelle im XML-Format (.rbxmx) für die Test-Engine.

assets_lua() liest assets/<Ordner>/*.rbxmx (z.B. assets/Weapons/Rifle.rbxmx, in Studio per Rechtsklick
"Save to File..." gespeichert) und liefert einen Luau-Ausdruck { [Ordner] = { Instanz, ... } }, aus dem
SIM.LoadAssets (tests/lib/engine.luau) die Instanzen unter ReplicatedStorage.Assets baut – so wie im Spiel.
Gelesen werden nur die Eigenschaften, die Tests brauchen: Klasse, Name, CFrame, Größe, Farbe, Transparenz,
Material und Form.
"""
import os
import xml.etree.ElementTree as ET

# Enum.Material: Zahl in der Datei -> Name
MATERIALS = {
    256: "Plastic", 272: "SmoothPlastic", 288: "Neon", 512: "Wood", 528: "WoodPlanks", 784: "Marble",
    788: "Basalt", 800: "Slate", 804: "CrackedLava", 816: "Concrete", 820: "Limestone", 832: "Granite",
    836: "Pavement", 848: "Brick", 864: "Pebble", 880: "Cobblestone", 896: "Rock", 912: "Sandstone",
    1040: "CorrodedMetal", 1056: "DiamondPlate", 1072: "Foil", 1088: "Metal", 1280: "Grass", 1284: "LeafyGrass",
    1296: "Sand", 1312: "Fabric", 1328: "Snow", 1344: "Mud", 1360: "Ground", 1376: "Asphalt", 1392: "Salt",
    1536: "Ice", 1552: "Glacier", 1568: "Glass", 1584: "ForceField",
}
SHAPES = {0: "Ball", 1: "Block", 2: "Cylinder", 3: "Wedge", 4: "CornerWedge"}
CFRAME_KEYS = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")

# Ordner, die es im Spiel immer gibt (default.project.json legt sie an)
DEFAULT_FOLDERS = ("Weapons",)


def _numbers(element, keys):
    return [float(element.find(key).text) for key in keys]


def _item(element):
    node = {"Class": element.get("class"), "Children": []}
    properties = element.find("Properties")
    for prop in properties if properties is not None else []:
        name, tag = prop.get("name"), prop.tag
        if tag in ("string", "ProtectedString") and name == "Name":
            node["Name"] = prop.text or ""
        elif tag == "CoordinateFrame" and name in ("CFrame", "CoordinateFrame"):
            node["CFrame"] = _numbers(prop, CFRAME_KEYS)
        elif tag == "Vector3" and name in ("size", "Size"):
            node["Size"] = _numbers(prop, ("X", "Y", "Z"))
        elif tag == "Color3uint8" and name == "Color3uint8":
            value = int(prop.text)
            node["Color"] = [(value >> 16) & 255, (value >> 8) & 255, value & 255]
        elif tag == "Color3" and name == "Color":
            node["Color"] = [round(v * 255) for v in _numbers(prop, ("R", "G", "B"))]
        elif tag == "float" and name == "Transparency":
            node["Transparency"] = float(prop.text)
        elif tag == "token" and name == "Material":
            node["Material"] = MATERIALS.get(int(prop.text), "Plastic")
        elif tag == "token" and name in ("shape", "Shape"):
            shape = SHAPES.get(int(prop.text))
            if shape:
                node["Shape"] = shape
    for child in element.findall("Item"):
        node["Children"].append(_item(child))
    return node


def load_file(path):
    """Wurzel-Instanzen einer .rbxmx-Datei als Liste von Tabellen."""
    return [_item(item) for item in ET.parse(path).getroot().findall("Item")]


def _lua(value):
    if isinstance(value, dict):
        return "{" + ", ".join("%s = %s" % (key, _lua(item)) for key, item in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        return "{" + ", ".join(_lua(item) for item in value) + "}"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(float(value)) if isinstance(value, float) else str(value)
    text = str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + text + '"'


def assets_lua(assets_dir):
    """Luau-Ausdruck { [Ordner] = { Instanz, ... } } aller assets/<Ordner>/*.rbxmx (plus die Standard-Ordner)."""
    folders = {name: [] for name in DEFAULT_FOLDERS}
    if os.path.isdir(assets_dir):
        for folder in sorted(os.listdir(assets_dir)):
            full = os.path.join(assets_dir, folder)
            if not os.path.isdir(full):
                continue
            items = folders.setdefault(folder, [])
            for name in sorted(os.listdir(full)):
                if name.endswith(".rbxmx"):
                    items.extend(load_file(os.path.join(full, name)))
    return "{" + ", ".join("[%s] = %s" % (_lua(name), _lua(items)) for name, items in folders.items()) + "}"

#!/usr/bin/env python3
"""Farb-Grundtextur (Skins/Farbe) für alle texturierten Waffen außer dem Sturmgewehr.

Die importierten Waffen haben eine deckende Textur (ColorMap) auf jeder Skin-Zone; die Farbe eines Skins käme
nicht durch, die Waffe sähe mit jedem Farb-Skin aus wie ohne. Für jede Waffe in models/Weapons/<Waffe>.rbxmx
schreibt das Skript models/Skins/<Waffe>.rbxmx: Ordner Skins › Farbe mit je einer SurfaceAppearance pro Skin-Zone
(Skin_Body, Skin_Slide, ... – passt auf Skin_Body_01, Skin_Body_02 usw.), OHNE ColorMap: die Farbe des Skins
deckt die Zone ganz, Normal-, Rauheits- und Metall-Map der Waffe bleiben (Kanten, Rillen, Glanz).
Das Sturmgewehr hat eine eigene Grundtextur mit Kratzern (tools/models/skins.luau).

Aufruf (nach einem neuen Waffen-Import):  python3 tools/models/color_skins.py
default.project.json bindet die Dateien unter ReplicatedStorage.Assets.Weapons.<Waffe>.Skins ein.
"""
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WEAPONS = os.path.join(ROOT, "models", "Weapons")
SKINS = os.path.join(ROOT, "models", "Skins")
OWN_TEXTURE = {"Rifle"}  # eigene Grundtextur in skins.luau
MAPS = ("MetalnessMap", "NormalMap", "RoughnessMap")


def url(sa, name):
    prop = sa.find("Properties/Content[@name='%s']/url" % name)
    return prop.text if prop is not None else None


def zones_of(path):
    """{ Zone: { Map: url } } aller Teile mit dem Wort Skin im Namen."""
    zones = {}
    for item in ET.parse(path).getroot().iter("Item"):
        if item.get("class") not in ("MeshPart", "Part"):
            continue
        name = re.sub(r"\.\d+$", "", item.find("Properties/string[@name='Name']").text or "")
        if "Skin" not in name.split("_"):
            continue
        zone = re.sub(r"_\d+$", "", name)
        for sa in item.findall("Item"):
            if sa.get("class") != "SurfaceAppearance":
                continue
            maps = {key: url(sa, key) for key in MAPS if url(sa, key)}
            known = zones.setdefault(zone, maps)
            if known != maps:
                sys.exit("%s: %s hat andere Texturen als der Rest der Zone %s" % (path, name, zone))
    return zones


def write(weapon, zones):
    lines = ['<roblox version="4">', '  <Item class="Folder" referent="0">', "    <Properties>",
             '      <string name="Name">Skins</string>', "    </Properties>",
             '    <Item class="Folder" referent="1">', "      <Properties>",
             '        <string name="Name">Farbe</string>', "      </Properties>"]
    for index, zone in enumerate(sorted(zones)):
        lines += ['      <Item class="SurfaceAppearance" referent="%d">' % (index + 2), "        <Properties>",
                  '          <string name="Name">%s</string>' % zone, '          <token name="AlphaMode">0</token>']
        for key, value in sorted(zones[zone].items()):
            lines.append('          <Content name="%s"><url>%s</url></Content>' % (key, value))
        lines += ["        </Properties>", "      </Item>"]
    lines += ["    </Item>", "  </Item>", "</roblox>", ""]
    with open(os.path.join(SKINS, weapon + ".rbxmx"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    for path in sorted(glob.glob(os.path.join(WEAPONS, "*.rbxmx"))):
        weapon = os.path.splitext(os.path.basename(path))[0]
        if weapon in OWN_TEXTURE:
            continue
        zones = {zone: maps for zone, maps in zones_of(path).items() if maps}
        if not zones:
            print("%s: keine texturierten Skin-Zonen, übersprungen" % weapon)
            continue
        write(weapon, zones)
        print("%s: Skins/Farbe mit %s" % (weapon, ", ".join(sorted(zones))))


if __name__ == "__main__":
    main()

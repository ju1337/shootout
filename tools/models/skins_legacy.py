# Texturen der Skins in die alte Form (ColorMap ...) umschreiben, Glühen (EmissiveMaskContent) bleibt neu.
# Aufruf: python3 tools/models/skins_legacy.py models/Skins/Rifle.rbxmx
import re
import sys

MAP = {"ColorMapContent": "ColorMap", "MetalnessMapContent": "MetalnessMap", "NormalMapContent": "NormalMap",
       "RoughnessMapContent": "RoughnessMap"}
path = sys.argv[1]
s = open(path, encoding="utf-8").read()


def legacy(m):
    name, body = m.group(1), m.group(2)
    if name not in MAP:
        return m.group(0)
    uri = re.search(r"<uri>(.*?)</uri>", body, re.S)
    return '<Content name="%s">%s</Content>' % (MAP[name], "<url>%s</url>" % uri.group(1) if uri else "<null></null>")


s = re.sub(r'<Content name="(\w+)">(.*?)</Content>', legacy, s, flags=re.S)
open(path, "w", encoding="utf-8").write(s)

# Neue Content-Felder (MeshContent, ColorMapContent ...) in die alte Form (MeshId, ColorMap ...) umschreiben,
# damit jede Rojo-Version die Datei lesen kann. Aufruf: python3 rbxmx_legacy.py <datei.rbxmx> ContentId:TexturePack
import re, sys
MAP = {"MeshContent": "MeshId", "TextureContent": "TextureID", "ColorMapContent": "ColorMap",
       "MetalnessMapContent": "MetalnessMap", "NormalMapContent": "NormalMap", "RoughnessMapContent": "RoughnessMap"}
DROP = set(sys.argv[2].split(",")) if len(sys.argv) > 2 and sys.argv[2] else set()
s = open(sys.argv[1], encoding="utf-8").read()
def content(m):
    name, body = m.group(1), m.group(2)
    if name not in MAP:
        return ""  # z.B. EmissiveMaskContent: ältere Rojo kennen den Typ nicht
    uri = re.search(r"<uri>(.*?)</uri>", body, re.S)
    inner = "<url>%s</url>" % uri.group(1) if uri else "<null></null>"
    return '<Content name="%s">%s</Content>' % (MAP[name], inner)
s = re.sub(r'<Content name="(\w+)">(.*?)</Content>', content, s, flags=re.S)
for tag_name in DROP:
    t, n = tag_name.split(":")
    s = re.sub(r'\s*<%s name="%s"(?:/>|>.*?</%s>)' % (t, n, t), "", s, flags=re.S)
open(sys.argv[1], "w", encoding="utf-8").write(s)

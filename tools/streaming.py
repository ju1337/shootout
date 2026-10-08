"""Instance Streaming (Workspace.StreamingEnabled) für die Maps vorbereiten.

Mit Streaming bekommt jeder Client nur die Teile in seiner Nähe (Radius in default.project.json). Was der Client
immer vollständig braucht, wird als Model mit ModelStreamingMode "Persistent" gespeichert:
  * ganze Maps, auf denen Client-Skripte viele einzelne Teile suchen (Hub, Markt)
  * einzelne Gruppen der übrigen Maps (z. B. Zone, Orte und Stände der offenen Welt, Ziele der Arcade-Maps).
    Eine Gruppe ist sonst ein Folder; als Model verhält sie sich für Skripte gleich (FindFirstChild, GetChildren …).

Aufruf:  python3 tools/streaming.py      (bestehende src/maps/*.model.json anpassen, Format bleibt gleich)
Die Map-Skripte (build_maps.py, extinction_world.py) rufen apply() beim Speichern selbst auf.
"""

import glob
import json
import os

# Ganze Map immer laden
PERSISTENT_MAPS = {"Hub", "Market"}
# Nur diese Gruppen immer laden (gilt für jede Map, die sie hat)
PERSISTENT_GROUPS = {"Zone", "Places", "Stands", "Lakes", "Objective"}


def apply(model, name):
    """Setzt ModelStreamingMode im Modell (dict wie in *.model.json); name = Dateiname ohne .model.json."""
    if name in PERSISTENT_MAPS:
        model.setdefault("Properties", {})["ModelStreamingMode"] = "Persistent"
        return model
    for group in model.get("Children", []):
        if group.get("Name") in PERSISTENT_GROUPS and group.get("ClassName") in ("Folder", "Model"):
            group["ClassName"] = "Model"
            group.setdefault("Properties", {})["ModelStreamingMode"] = "Persistent"
    return model


def _format_of(text, data):
    """Findet die json.dump-Optionen, mit denen die Datei geschrieben wurde (damit der Diff klein bleibt)."""
    for options in ({"indent": 1}, {"separators": (",", ":")}, {"indent": 1, "ensure_ascii": False}):
        if json.dumps(data, **options) == text:
            return options
    return {"indent": 1}


def main():
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "maps")
    for path in sorted(glob.glob(os.path.join(out_dir, "*.model.json"))):
        with open(path) as f:
            text = f.read()
        data = json.loads(text)
        options = _format_of(text, data)
        apply(data, os.path.basename(path).replace(".model.json", ""))
        new = json.dumps(data, **options)
        if new != text:
            with open(path, "w") as f:
                f.write(new)
            print("angepasst:", os.path.basename(path))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Erzeugt eine Rojo-kompatible sourcemap.json für luau-lsp (ohne Rojo installiert zu haben).
Aufruf: python3 tools/sourcemap.py [Projektordner] [Ausgabedatei]"""
import json
import os
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "sourcemap.json")


def model_json(path, name):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    def conv(node, node_name):
        out = {"name": node_name, "className": node.get("ClassName", "Folder")}
        children = [conv(c, c.get("Name", "?")) for c in node.get("Children", [])]
        if children:
            out["children"] = children
        return out

    out = conv(data, name)
    out["filePaths"] = [os.path.relpath(path, ROOT)]
    return out


def from_path(path, name):
    """Instanz aus Datei oder Ordner (Rojo-Regeln für .lua/.server.lua/.client.lua/.model.json)."""
    rel = os.path.relpath(path, ROOT)
    if os.path.isdir(path):
        init = None
        for candidate, cls in (("init.server.lua", "Script"), ("init.client.lua", "LocalScript"), ("init.lua", "ModuleScript")):
            if os.path.exists(os.path.join(path, candidate)):
                init = (candidate, cls)
        node = {"name": name, "className": init[1] if init else "Folder", "children": []}
        node["filePaths"] = [os.path.join(rel, init[0])] if init else []
        for entry in sorted(os.listdir(path)):
            full = os.path.join(path, entry)
            if init and entry == init[0]:
                continue
            child = child_from_entry(full, entry)
            if child:
                node["children"].append(child)
        return node
    return child_from_entry(path, name)


def child_from_entry(full, entry):
    if os.path.isdir(full):
        return from_path(full, entry)
    rel = os.path.relpath(full, ROOT)
    if entry.endswith(".server.lua"):
        return {"name": entry[: -len(".server.lua")], "className": "Script", "filePaths": [rel]}
    if entry.endswith(".client.lua"):
        return {"name": entry[: -len(".client.lua")], "className": "LocalScript", "filePaths": [rel]}
    if entry.endswith(".lua") or entry.endswith(".luau"):
        base = entry.rsplit(".", 1)[0]
        return {"name": base, "className": "ModuleScript", "filePaths": [rel]}
    if entry.endswith(".model.json"):
        return model_json(full, entry[: -len(".model.json")])
    if full.endswith(".rbxm") or full.endswith(".rbxmx"):
        # Binär-/XML-Modell (z.B. models/Weapons/Rifle.rbxm): kein Code, nur als Modell im Baum
        base = entry.rsplit(".", 1)[0] if entry.endswith((".rbxm", ".rbxmx")) else entry
        return {"name": base, "className": "Model", "filePaths": [rel]}
    return None


def tree_node(name, spec):
    class_name = spec.get("$className", "Folder")
    node = {"name": name, "className": class_name, "children": []}
    if "$path" in spec:
        sub = from_path(os.path.join(ROOT, spec["$path"]), name)
        if sub:
            sub["className"] = spec.get("$className", sub["className"])
            node = sub
    for key, value in spec.items():
        if key.startswith("$") or not isinstance(value, dict):
            continue
        node.setdefault("children", []).append(tree_node(key, value))
    return node


with open(os.path.join(ROOT, "default.project.json"), encoding="utf-8") as f:
    project = json.load(f)

root = tree_node(project["name"], project["tree"])
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(root, f, indent=1)
print("sourcemap ->", OUT)

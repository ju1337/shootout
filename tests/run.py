#!/usr/bin/env python3
"""Startet die Tests (tests/*.test.luau) mit dem Luau-Interpreter – ohne Roblox.

Jeder Test wird mit der Roblox-Nachbildung (tests/lib/shim.luau = Datentypen, tests/lib/engine.luau = Zeit,
Instanzen, Dienste) und allen Modulen des Projekts zu einer Datei gebündelt. Die Module liegen unter denselben
Pfaden wie in Roblox (aus default.project.json, wie Rojo sie anlegt), require(script.Parent.X) und
require(Shared.X) funktionieren also wie im Spiel. Im Test lädt require("Name") ein Modul über seinen Namen.

Ein Test ist bestanden, wenn der Interpreter ohne Fehler endet und keine Ausgabezeile mit "FEHLER" beginnt.

Kopfzeilen im Test:
  --!expose Modul name1 name2   lokale Funktionen eines Moduls für den Test freigeben (Modul.__name1, ...)
  --!signals immediate deferred Test für jedes Signal-Verhalten von Roblox einmal ausführen (Standard: immediate)

Aufruf:
  python3 tests/run.py                  alle Tests
  python3 tests/run.py session kill     nur Tests, deren Dateiname das Wort enthält
  --luau PFAD                           Luau-Interpreter (Standard: $LUAU oder "luau")
  --keep ORDNER                         gebündelte Dateien dort ablegen (zum Nachsehen bei Fehlern)
  -v                                    Ausgabe auch bei bestandenen Tests zeigen
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

PRELUDE_TYPES = """local Vector3, Vector2, CFrame, Color3, Enum = __shim.Vector3, __shim.Vector2, __shim.CFrame, __shim.Color3, __shim.Enum
local UDim, UDim2, NumberRange, NumberSequence = __shim.UDim, __shim.UDim2, __shim.NumberRange, __shim.NumberSequence
local NumberSequenceKeypoint, ColorSequence, ColorSequenceKeypoint = __shim.NumberSequenceKeypoint, __shim.ColorSequence, __shim.ColorSequenceKeypoint
local TweenInfo, Font, Rect, PhysicalProperties, Ray = __shim.TweenInfo, __shim.Font, __shim.Rect, __shim.PhysicalProperties, __shim.Ray
local BrickColor, RaycastParams, OverlapParams, Random, typeof = __shim.BrickColor, __shim.RaycastParams, __shim.OverlapParams, __shim.Random, __shim.typeof"""

PRELUDE_GLOBALS = """local task, game, workspace, Instance = SIM.task, SIM.Game, SIM.Workspace, SIM.Instance
local os, tick, time, warn, settings = SIM.Os, SIM.Tick, SIM.Time, SIM.Warn, SIM.Settings
local wait, spawn, delay = SIM.task.wait, SIM.task.defer, SIM.task.delay
local require = SIM.Require
math.randomseed(1)"""

EPILOGUE = """if SIM.Errors > 0 then
	error(SIM.Errors .. " Fehler in Threads (siehe oben)")
end"""


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def project_modules():
    """[(Roblox-Pfad, Datei)] aller ModuleScripts laut default.project.json (Skripte .server/.client nicht)."""
    project = json.loads(read(os.path.join(ROOT, "default.project.json")))
    found = []

    def add_dir(directory, path):
        for entry in sorted(os.listdir(directory)):
            full = os.path.join(directory, entry)
            if os.path.isdir(full):
                add_dir(full, path + [entry])
                continue
            match = re.fullmatch(r"(.+?)\.(lua|luau)", entry)
            if not match or match.group(1).endswith((".server", ".client")):
                continue
            name = match.group(1)
            found.append(("/".join(path if name == "init" else path + [name]), full))

    def walk(node, path):
        source = node.get("$path")
        if source and os.path.isdir(os.path.join(ROOT, source)):
            add_dir(os.path.join(ROOT, source), path)
        for key, child in node.items():
            if not key.startswith("$") and isinstance(child, dict):
                walk(child, path + [key])

    walk(project["tree"], [])
    return found


def expose(source, names):
    """Vor dem letzten 'return Modul' die lokalen Funktionen als Modul.__name eintragen."""
    lines = source.rstrip().split("\n")
    for i in range(len(lines) - 1, -1, -1):
        match = re.fullmatch(r"return\s+([A-Za-z_][A-Za-z0-9_]*)\s*", lines[i])
        if match:
            table = match.group(1)
            lines[i:i] = ["%s.__%s = %s" % (table, name, name) for name in names]
            return "\n".join(lines) + "\n"
    raise SystemExit("--!expose: kein 'return Modul' am Ende gefunden")


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def directives(test_source):
    """Kopfzeilen: {"expose": {Modul: [Namen]}, "signals": [Verhalten]}"""
    exposes, signals = {}, []
    for line in test_source.split("\n"):
        match = re.match(r"--!expose\s+(\S+)\s+(.+)", line)
        if match:
            exposes.setdefault(match.group(1), []).extend(match.group(2).split())
        match = re.match(r"--!signals\s+(.+)", line)
        if match:
            signals.extend(match.group(1).split())
    for mode in signals:
        if mode not in ("immediate", "deferred"):
            raise SystemExit("--!signals: unbekanntes Verhalten " + mode)
    return {"expose": exposes, "signals": signals or ["immediate"]}


def build(test_path, modules, signals="immediate"):
    """Bündel als Text und Zeilenzuordnung [(erste Zeile, letzte Zeile, Datei, Versatz)]."""
    test_source = read(test_path)
    exposes = {name: list(names) for name, names in directives(test_source)["expose"].items()}
    chunks = []  # (Text, Datei oder None, Zeilen vor dem Quelltext im Text)
    chunks.append(("local __shim = (function()\n" + read(os.path.join(HERE, "lib", "shim.luau")) + "\nend)()",
                   "tests/lib/shim.luau", 1))
    chunks.append((PRELUDE_TYPES, None, 0))
    chunks.append(("local SIM = (function()\n" + read(os.path.join(HERE, "lib", "engine.luau")) + "\nend)()",
                   "tests/lib/engine.luau", 1))
    chunks.append((PRELUDE_GLOBALS + "\nSIM.Deferred = %s" % ("true" if signals == "deferred" else "false"), None, 0))
    for path, file in modules:
        source = read(file)
        name = path.rsplit("/", 1)[-1]
        if name in exposes:
            source = expose(source, exposes.pop(name))
        chunks.append(("SIM.Module(%s, function(script)\n%s\nend)" % (lua_string(path), source),
                       os.path.relpath(file, ROOT), 1))
    if exposes:
        raise SystemExit("--!expose: Modul nicht gefunden: " + ", ".join(exposes))
    chunks.append((test_source, os.path.relpath(test_path, ROOT), 0))
    chunks.append((EPILOGUE, None, 0))
    text, line_map, line = [], [], 1
    for chunk, file, offset in chunks:
        count = chunk.count("\n") + 1
        if file:
            line_map.append((line, line + count - 1, file, line + offset))
        text.append(chunk)
        line += count
    return "\n".join(text) + "\n", line_map


def translate(output, bundle_name, line_map):
    """Zeilenangaben im Bündel (name.luau:123) in Datei:Zeile des Projekts übersetzen."""
    def repl(match):
        number = int(match.group(1))
        for first, last, file, start in line_map:
            if first <= number <= last:
                return "%s:%d" % (file, number - start + 1)
        return match.group(0)
    return re.sub(r"[^\s\"']*" + re.escape(bundle_name) + r":(\d+)", repl, output)


def main():
    parser = argparse.ArgumentParser(description="Tests ohne Roblox ausführen")
    parser.add_argument("names", nargs="*", help="nur Tests, deren Dateiname das Wort enthält")
    parser.add_argument("--luau", default=os.environ.get("LUAU", "luau"), help="Luau-Interpreter")
    parser.add_argument("--keep", help="gebündelte Dateien in diesem Ordner ablegen")
    parser.add_argument("-v", "--verbose", action="store_true", help="Ausgabe auch bei bestandenen Tests zeigen")
    args = parser.parse_args()

    tests = sorted(f for f in os.listdir(HERE) if f.endswith(".test.luau"))
    if args.names:
        tests = [t for t in tests if any(n in t for n in args.names)]
    if not tests:
        print("Keine Tests gefunden.")
        return 1
    modules = project_modules()
    out_dir = args.keep or tempfile.mkdtemp(prefix="shootout-tests-")
    os.makedirs(out_dir, exist_ok=True)
    runs = []
    for test in tests:
        modes = directives(read(os.path.join(HERE, test)))["signals"]
        for mode in modes:
            runs.append((test, mode, test[: -len(".test.luau")] + (" [%s]" % mode if len(modes) > 1 else "")))
    failed = []
    for test, mode, name in runs:
        bundle, line_map = build(os.path.join(HERE, test), modules, mode)
        bundle_name = re.sub(r"[^A-Za-z0-9_]+", "_", name).strip("_") + ".bundle.luau"
        bundle_path = os.path.join(out_dir, bundle_name)
        with open(bundle_path, "w", encoding="utf-8") as f:
            f.write(bundle)
        started = time.time()
        try:
            result = subprocess.run([args.luau, bundle_name], cwd=out_dir, capture_output=True, text=True, timeout=600)
            output, code = result.stdout + result.stderr, result.returncode
        except subprocess.TimeoutExpired:
            output, code = "FEHLER: Zeitlimit (600 s) überschritten\n", -1
        except FileNotFoundError:
            print("Luau-Interpreter nicht gefunden: %s (mit --luau oder $LUAU angeben)" % args.luau)
            return 2
        output = translate(output, bundle_name, line_map)
        ok = code == 0 and not any(line.startswith("FEHLER") for line in output.split("\n"))
        print("%s %s (%.1f s)" % ("ok    " if ok else "FEHLER", name, time.time() - started))
        if not ok or args.verbose:
            for line in output.rstrip().split("\n"):
                print("       " + line)
        if not ok:
            failed.append(name)
    print()
    if failed:
        print("%d von %d Tests fehlgeschlagen: %s" % (len(failed), len(runs), ", ".join(failed)))
        return 1
    print("Alle %d Tests bestanden." % len(runs))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Setzt src/shared/LocaleStrings.lua aus Teil-Wörterbüchern zusammen (Deutsch -> Englisch).

Eingabe: Lua-Dateien der Form  return { ["Deutsch"] = "English", ... }  (eine Zeile je Eintrag).
Gleiche Schlüssel mit verschiedener Übersetzung werden gemeldet; es gewinnt die erste Datei.

Aufruf: python3 tools/locale_merge.py teil1.lua teil2.lua ... [-o src/shared/LocaleStrings.lua]
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENTRY = re.compile(r'^\s*\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*,?\s*(?:--.*)?$')


def unescape(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def read(path):
    entries = {}
    skipped = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.strip() in ("return {", "}", "{") or line.strip().startswith("--"):
                continue
            m = ENTRY.match(line)
            if not m:
                skipped += 1
                print(f"{path}: Zeile nicht erkannt: {line.strip()[:100]}")
                continue
            entries[unescape(m.group(1))] = unescape(m.group(2))
    return entries, skipped


def main():
    args = sys.argv[1:]
    out = os.path.join(ROOT, "src", "shared", "LocaleStrings.lua")
    if "-o" in args:
        i = args.index("-o")
        out = args[i + 1]
        del args[i:i + 2]
    merged = {}
    conflicts = 0
    for path in args:
        entries, _ = read(path)
        for key, value in entries.items():
            if key in merged and merged[key] != value:
                conflicts += 1
                print(f"Konflikt: {key!r}: {merged[key]!r} (behalten) vs {value!r} ({os.path.basename(path)})")
            merged.setdefault(key, value)
    # Einträge, die nichts ändern, sind überflüssig
    merged = {k: v for k, v in merged.items() if k != v and k.strip() and v.strip()}
    lines = [
        "-- LocaleStrings (ModuleScript): Deutsch -> Englisch (US), siehe Locale.lua. Platzhalter {1}, {2} … für veränderliche",
        "-- Teile. Zusammengesetzt mit tools/locale_merge.py; fehlende Texte zeigt tools/locale_scan.py.",
        "-- Einträge bitte alphabetisch halten (Schlüssel = genauer deutscher Text auf dem Bildschirm).",
        "return {",
    ]
    for key in sorted(merged, key=lambda k: k.lower()):
        lines.append(f'\t["{escape(key)}"] = "{escape(merged[key])}",')
    lines.append("}")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{len(merged)} Einträge -> {os.path.relpath(out, ROOT)}, {conflicts} Konflikte")


if __name__ == "__main__":
    main()

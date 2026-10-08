#!/usr/bin/env python3
"""Findet deutsche Texte in den Skripten, die (noch) nicht in LocaleStrings stehen.

Hilfe beim Übersetzen (src/shared/LocaleStrings.lua, siehe src/shared/Locale.lua): sucht in allen Skripten
String-Literale, die wie Anzeigetext aussehen (Umlaute, ß, Leerzeichen oder GROSSSCHRIFT), und gibt die aus, zu denen
es keinen Eintrag gibt. Zusammengesetzte Texte (.. und string.format) erkennt die Suche nicht als Ganzes; dafür gibt es
Muster-Einträge mit {1}, {2} … in LocaleStrings.

Aufruf:
  python3 tools/locale_scan.py            Zusammenfassung je Datei
  python3 tools/locale_scan.py -v         alle fehlenden Texte
  python3 tools/locale_scan.py --json     alle Kandidaten je Datei als JSON (auch die übersetzten)
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
GERMAN = re.compile(r"[äöüÄÖÜß]")
WORDS = re.compile(r"[A-Za-zÄÖÜäöüß]{2,}")
SKIP_FILES = {"LocaleStrings.lua", "Locale.lua", "ExtinctionTerrainData.lua"}
# Literale, die nie Anzeigetext sind
SKIP = re.compile(r"^(rbxasset|rbxassetid|http|%[-+ #0]*[0-9.]*[dsfgxq%]|[A-Za-z]+_[A-Za-z0-9_]+|[a-z][A-Za-z0-9]*)$")


def normalize(s):
    """string.format-Platzhalter (%d, %s, %.1f, %5.2f …) -> {1}, {2} …, %% -> %"""
    n = 0

    def repl(m):
        nonlocal n
        n += 1
        return "{%d}" % n

    s = s.replace("%%", "\0")
    return re.sub(r"%[-+ #0]*\d*(?:\.\d+)?[dsfgiqxXc]", repl, s).replace("\0", "%")


def looks_like_text(s):
    if len(s) < 2 or SKIP.match(s):
        return False
    if s != s.strip() and len(s.strip()) < 40:
        return False  # Bruchstück einer Verkettung (Anfang/Ende mit Leerzeichen) – dafür gibt es Muster-Einträge
    if GERMAN.search(s):
        return True
    if " " in s.strip() and WORDS.search(s):
        return True
    letters = re.sub(r"[^A-Za-z]", "", s)
    return len(letters) >= 3 and letters.isupper() and " " not in s and len(s) <= 24


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in s else s


def candidates():
    found = {}
    for base, _, files in os.walk(SRC):
        for name in sorted(files):
            if not name.endswith(".lua") and not name.endswith(".luau") or name in SKIP_FILES:
                continue
            path = os.path.join(base, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            # Kommentare grob entfernen
            text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
            text = re.sub(r"--[^\n]*", "", text)
            # Entwickler-Ausgaben (print/warn/error/assert) zählen nicht
            text = re.sub(r"\b(?:print|warn|error|assert)\s*\((?:[^()]|\([^()]*\))*\)", "", text)
            items = []
            for m in LITERAL.finditer(text):
                s = m.group(1)
                try:
                    s = unescape(s)
                except Exception:
                    pass
                s = normalize(s)
                if looks_like_text(s) and s not in items:
                    items.append(s)
            if items:
                found[os.path.relpath(path, ROOT)] = items
    return found


def translated():
    path = os.path.join(SRC, "shared", "LocaleStrings.lua")
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8") as f:
        text = f.read()
    keys = set()
    for m in re.finditer(r'^\s*\["((?:[^"\\]|\\.)*)"\]\s*=', text, flags=re.M):
        keys.add(unescape(m.group(1)))
    return keys


def main():
    found = candidates()
    if "--json" in sys.argv:
        print(json.dumps(found, ensure_ascii=False, indent=1))
        return
    known = translated()
    verbose = "-v" in sys.argv
    total = missing = 0
    for path, items in found.items():
        gaps = [s for s in items if s not in known]
        total += len(items)
        missing += len(gaps)
        if gaps:
            print(f"{path}: {len(gaps)} von {len(items)} ohne Eintrag")
            if verbose:
                for s in gaps:
                    print("   " + json.dumps(s, ensure_ascii=False))
    print(f"\n{total} Texte, {missing} ohne Eintrag")


if __name__ == "__main__":
    main()

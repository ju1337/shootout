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

Läuft auch in tests/run.py (Test "locale"): jeder neue Anzeigetext braucht sofort einen englischen Eintrag.
Gilt ein Text auf Englisch genauso (Namen, Abkürzungen), gehört er in SAME; ist er gar kein Anzeigetext, in IGNORE.
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
SKIP_FILES = {"LocaleStrings.lua", "Locale.lua", "ExtinctionTerrainData.lua",
              # nur Entwickler-Ausgaben (Studio-Ausgabe, Discord-Log, Modellprüfung), nie auf dem Bildschirm
              "GunModels.lua", "DiscordLog.lua", "SpawnUtil.lua",
              "MovementGuard.lua", "CharacterPose.lua",
              "Credits.lua"}  # Titel und Lizenzen der Modelle bleiben unübersetzt
# Texte, die auf Englisch genauso heißen (Namen, Abkürzungen, Tasten, Roblox-Farben) – brauchen keinen Eintrag
SAME = {
    "SMG", "DMR", "LMG", "VIP", "HUD", "GADGET", "ULTIMATE", "ULT", "PING", "SPRINT", "TOUCH", "LMB", "RMB", "SHIFT",
    "TAB", "BRONZE", "GOLD", "CYAN", "PINK", "ENGLISH", "III", "JACKPOT", "OWNER", "DEV", "LEAD MOD", "HELPER",
    "BOOSTER", "VIP KIT", "STARTER KIT", "DAILY KIT", "WEEKLY KIT", "BATTLE PASS", "BATTLE PASS · S1", "SHOOTOUT",
    "TACTICAL OPERATIONS", "CODES", "CODE", "ARCADE", "EXTINCTION", "SAFE ZONE", "SAFEHOUSE", "CAMP", "SQUAD", "GUIDE",
    "CONTAINER", "OFFLINE", "ZOOM", "CLAN", "PRESTIGE", "PASS", "LOGIN", "STATS", "AGENT", "BOT", "SPAWN", "ROBUX",
    "IAP", "Battle Pass", "MAYDAY", "COMEBACK", "CLUTCH", "ACE", "Clutch / ACE", "OVERTIME", "RANKED", "TDM",
    "ASSISTS", "MATCHES", "CLUTCHES", "TOP 10 · ELO", "LEVEL UP!", "LEVEL 1", "+0 XP", "+25 XP", "30 XP", "50 XP",
    "150 XP", "2× XP", "Prestige 1", "Prestige 10", "Prestige Bronze", "Prestige Gold",
    "1v1 Arena", "FREE-FOR-ALL", "WINGMAN", "DUELS", "1v1 ARENA", "TRAINING",
    "TEAM DEATHMATCH", "DROP", "STRIKEOUT", "DEMOLITION", "EXTRACTION", "Duels · 2v2", "Duels · 1v1", "5v5 Respawn",
    "5v5 Team", "4v4 Team", "VIP & BOOSTER", "HORDE {1} %", "VIPER", "BASTION", "MENDER", "HAWK", "GHOST", "BLAZE",
    "AEGIS", "TRAPPER", "VOLT", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Left Shoulder", "Right Shoulder",
    "Left Hip", "Right Hip", "Sand blue", "Storm blue", "Bright red", "Bright blue", "Steel blue", "Dusty Rose",
    "Royal blue", "Deep orange", "Bright violet", "Earth green", "Fawn brown", "D7E1EE", "RESPAWN IN",
    "SAFE ZONE (CAMP, SAFEHOUSES)", "LEVEL UP! ×", "XP ×", "Ödstadt", "ÖDSTADT WEST", "CREDITS",
}
# kein Anzeigetext: Discord-Log-Titel und -Felder, Telemetrie-Gründe, interne Namen, Kartenschlüssel (Arcade)
IGNORE = {
    "Wert 1", "Wert 2", "Boss besiegt", "Legendärer Skin aus der Kiste", "Glücksrad-Jackpot", "Glücksrad-Skin", "Drehs umgewandelt",
    "Aufsatz passt nicht", "Module laden", "Bot-KI von {1} neu gestartet: {2}", "Kanäle", "Windmühlen",
    "{1} % · WELLE {2}/{3}{4}",  # {4} = "" oder " · NIEMAND DA", beide Formen haben einen Eintrag
    # ActivityService.SurvivorLost(spot, why) zeigt "Der Überlebende " .. why, dafür gibt es ganze Einträge
    "ist gestorben", "ist verschwunden", "wurde allein gelassen", "hat dich verloren", "hat aufgegeben",
    "SQUAD ZUM ANNEHMEN",  # Ende von "{1} LÄDT DICH IN DEN SQUAD EIN  ·  SQUAD ZUM ANNEHMEN"
}
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
    return re.sub(r"%[-+#0]*\d*(?:\.\d+)?[dsfgiqxXc]", repl, s).replace("\0", "%")


def looks_like_text(s):
    if len(s) < 2 or SKIP.match(s):
        return False
    if re.match(r"^#[0-9A-Fa-f]{6}$", s) or "' .." in s or ".. '" in s:
        return False  # Farbcodes und Rich-Text-Bausteine (<font color="#' .. c:ToHex() .. '">)
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


CONCAT = set()  # Literale, die mit .. an etwas anderes gehängt werden (nur Teil eines Textes)


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
                before = text[max(0, m.start() - 200):m.start()]
                after = text[m.end():m.end() + 60]
                if (re.search(r"\.\.\s*$", before) or re.match(r"^\s*\.\.", after)
                        or re.search(r"\.\.\s*\([^()]*$", before)):  # x .. (a and "…" or "…")
                    CONCAT.add(s)
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


def fragments(keys):
    """feste Teile aller Einträge ("Nicht genug Münzen ({1} nötig)." -> "Nicht genug Münzen (", " nötig).");
    Zeilen eines über mehrere Literale verketteten Textes stecken so im Eintrag für den ganzen Text"""
    parts = []
    for key in keys:
        parts.extend(p for p in re.split(r"\{\d+\}", key) if p.strip())
    return parts


def matchers(keys):
    """Muster-Einträge als Regex ("SPIELER ({1})" passt auf "SPIELER (0)")"""
    out = []
    for key in keys:
        pieces = re.split(r"\{\d+\}", key)
        # nur Muster mit echtem Text ("{1}: {2}" passt auf alles, übersetzt aber nur die Teile)
        if len(pieces) > 1 and len(re.findall(r"[A-Za-zÄÖÜäöüß]", "".join(pieces))) >= 4:
            out.append(re.compile("^" + "(.+)".join(re.escape(p) for p in pieces) + "$", re.S))
    return out


def covered(s, known, parts, regexes):
    """hat einen Eintrag (auch über ein Muster), heißt auf Englisch genauso, ist kein Anzeigetext oder ist
    Bruchstück eines Eintrags (Verkettung mit ..)"""
    if s in known or s in SAME or s in IGNORE:
        return True
    if s in CONCAT and any(s in p for p in parts):
        return True
    if "{" in s:
        return False
    for r in regexes:
        m = r.match(s)
        # die Teile werden selbst nachgeschlagen: Zahlen/Namen ohne Buchstaben oder bekannte Texte
        if m and all(not re.search(r"[A-Za-zÄÖÜäöüß]", g) or g in known or g in SAME for g in m.groups()):
            return True
    return False


def gaps():
    """[(Datei, Text)] aller Texte ohne Eintrag – für tests/run.py (Test "locale")"""
    known = translated()
    parts = fragments(known)
    regexes = matchers(known)
    return [(path, s) for path, items in candidates().items() for s in items
            if not covered(s, known, parts, regexes)]


def main():
    found = candidates()
    if "--json" in sys.argv:
        print(json.dumps(found, ensure_ascii=False, indent=1))
        return
    known = translated()
    parts = fragments(known)
    regexes = matchers(known)
    verbose = "-v" in sys.argv
    total = missing = 0
    for path, items in found.items():
        gaps = [s for s in items if not covered(s, known, parts, regexes)]
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

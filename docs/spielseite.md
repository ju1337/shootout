# Spielseite im Creator Hub (Englisch)

Was ein neuer Spieler zuerst sieht, ist die Spielseite – nicht das Spiel. Alles hier ist zum Kopieren in den Creator Hub
(dein Spiel › **Basic Settings** bzw. **Places** › Startplace) gedacht. Die Texte sind auf Englisch (US), wie das Spiel
selbst (siehe README › Sprache). Die Zahlen stammen aus dem Code (Modes.lua, ExtinctionConfig.lua); wenn sich dort etwas
ändert, hier nachziehen.

## Name (höchstens 50 Zeichen)

```
Shootout: Extinction
```

Alternativen, falls der Name schon vergeben ist: `Shootout – Extinction Survival`, `Extinction Shootout`.

## Beschreibung (höchstens 1000 Zeichen)

Roblox zeigt nur die ersten Zeilen ohne „Read more“, darum steht das Wichtigste oben. 1026 Zeichen:

```
Survive the open world of EXTINCTION – or fight it out in the arcade modes.

🧟 EXTINCTION (main mode): Leave the safe zone of Camp Phoenix and loot the ruined city of Ödstadt, villages, outposts and a hilltop radio tower. Zombies, runners, screamers and brutes hunt you. Buy weapons, ammo, vests and vehicles with coins, keep your best gear in the stash – everything in your bag drops when you die outside.
🔴 RED ZONE: one zone moves every 20 minutes. PvP is instant, zombies are tougher, loot is better, and the top 3 get rewards.
🚁 Quads, pickups, sports cars and a helicopter for 4. Supply drops, convoys, heli crashes, bosses, blood moon and storm nights.
🤝 Squads of 4, player market, trading, clans, missions, battle pass, lucky wheel.
🎯 ARCADE: Free-for-All, Domination 5v5, Wingman 2v2, 1v1 Arena and a shooting range – with ELO ranks in every mode.

New here? A short tutorial starts the first time you enter the open world. Press M for the menu, N for the map.

Updates every week. Join the group for news and codes!
```

Ohne Emojis (falls die Seite nüchterner wirken soll): die Zeilen mit „EXTINCTION:“, „RED ZONE:“ usw. beginnen lassen.

## Genre, Untergenre und Tags

- **Genre:** Shooter · **Subgenre:** Battle Arena / Survival (Creator Hub bietet je nach Stand nur eine Auswahl;
  Shooter zuerst, Survival als Zweites)
- **Tags / Suchbegriffe** (in die Beschreibung passen sie schon): zombie, survival, open world, pvp, loot, shooter, fps

## Icon (512 × 512)

Ein Motiv, das auch winzig lesbar ist: Agent mit Sturmgewehr von vorn, dahinter das rote Phoenix-Banner des Camps, oben
links klein das Wort **EXTINCTION** in Oswald (die Schrift der UI). Keine Kleinteile, kein Text unter 1/6 der Höhe.
Hintergrund dunkel (Graphit wie `UITheme`), eine Signalfarbe (Bernstein) – so wirkt das Icon wie das Spiel.

## Thumbnails (1920 × 1080, bis zu 10, die ersten drei zählen)

Screenshots aus Studio mit F12 oder dem Screenshot-Werkzeug, Grafik auf HOCH, Uhrzeit per Admin-Panel setzen:

1. **Camp Phoenix bei Tag** von leicht erhöht, Tor im Bild, Händler unter Planen, Spieler mit Waffe – Titel darüber
   „EXTINCTION – OPEN WORLD SURVIVAL“.
2. **Rote Zone bei Nacht**: rote Wand, Lichtsäule, Brocken im Vordergrund – „RED ZONE · PVP · BEST LOOT“.
3. **Helikopter über Ödstadt** (Admin: Fahrzeug spawnen, Kamera frei) – „VEHICLES · HELICOPTER FOR 4“.
4. Lootdrop am Fallschirm mit Zombies darunter – „SUPPLY DROPS · CONVOYS · BOSSES“.
5. Lobby mit Agenten und Loadout – „ARCADE: FFA · DOMINATION · WINGMAN · 1V1“.
6. Squad von 4 am Lagerfeuer eines Safehouses – „SQUAD UP · TRADE · CLANS“.

Text auf den Bildern groß (mindestens 1/8 der Höhe), weiß mit dunklem Rand, oben oder unten im Drittel; Roblox zeigt
Thumbnails auf dem Handy sehr klein. Kein Thumbnail ohne Spielerfigur – Bilder mit Charakter werden öfter angeklickt.

Dazu ein **Video-Thumbnail** (YouTube-Link, 30–60 s): 10 s Camp, 15 s Kampf draußen, 10 s rote Zone bei Nacht, 10 s Heli.

## Fragebogen zur Altersfreigabe (Experience Questionnaire)

Pflicht, sonst bleibt das Spiel für viele unsichtbar. Antworten, die zum Spiel passen (bitte beim Ausfüllen gegenprüfen,
Roblox ändert die Fragen gelegentlich):

| Thema | Antwort | Warum |
|---|---|---|
| Violence | Moderate: repeated, non-realistic violence against humans and creatures | Schusswaffen, Zombies, PvP; keine Zerstückelung, kein realistisches Blut |
| Blood | Mild / unrealistic blood | Blutflecken an Zombies und Wracks, Trefferzahlen statt Blutfontänen |
| Fear | Mild: creepy or scary atmosphere | Nacht, Nebel, Schreier, verlassene Stadt |
| Crude humor | None | – |
| Romance / sexual content | None | – |
| Alcohol / drugs | None (Adrenaline/Medkit sind Medizin) | – |
| Gambling / paid random items | Yes: paid random items | Glücksrad-Drehs und Kisten sind mit Robux kaufbar; Gewinnchancen werden im Spiel angezeigt (`PaidRandom`, `OddsPanel`), in gesperrten Ländern blockiert `PolicyGate` |
| Free-form user creation | No | Nur Chat und Clan-Namen (gefiltert) |
| Strong language | None | Chat ist der Roblox-Chat mit Filter |

Ergebnis in der Regel **Moderate (9+)**; mit „Mild“ bei Blut und Angst bleibt es unter 13+.

## Weitere Einstellungen

- **Zugriff:** Public · **Geräte:** Computer, Phone, Tablet (Konsole erst nach einem Test mit Controller)
- **Max. Spieler je Server:** 30 (`Modes.lua`: Extinction „bis 30 Spieler“); **Server fill:** Roblox optimizes
- **Private Servers:** erlauben, Preis 0 oder 100 Robux – Squads testen gern unter sich
- **Monetization:** Gamepässe VIP (399), Double XP (299), Loot All (149) und die Münzpakete anlegen, IDs in
  `src/shared/RobuxConfig.lua` eintragen (bis dahin steht im Shop „BALD“); Badges anlegen, IDs in `src/shared/BadgeConfig.lua`
- **Social links:** Roblox-Gruppe und Discord (Discord erst mit 13+-Freigabe erlaubt)
- **Sprache der Seite:** English (US) als Quellsprache; die deutsche Beschreibung als Übersetzung ergänzen
  (Creator Hub › Localization › Source Language = English)

## Checkliste vor dem Veröffentlichen

- [ ] Name, Beschreibung, Genre eingetragen
- [ ] Icon und mindestens 3 Thumbnails hochgeladen (jedes muss durch die Moderation)
- [ ] Fragebogen beantwortet, Freigabe sichtbar
- [ ] Gamepass- und Produkt-IDs in `RobuxConfig.lua`, Badge-IDs in `BadgeConfig.lua`
- [ ] „Enable Studio Access to API Services“ an (Speichern, Analytics, Sperrliste)
- [ ] Einmal mit zwei Freunden live gespielt, Fehlerkonsole im Creator Hub leer

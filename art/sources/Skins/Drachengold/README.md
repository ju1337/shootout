# Drachengold (Test-Skin, Sturmgewehr)

Alles, was der Skin im Spiel braucht. Code: `src/shared/SkinEffects.lua`, Eintrag `W_Drachengold` in `src/shared/Cosmetics.lua`.

- `Texturen/` – Farbe, Normal, Rauheit, Metall, Emissive (Lava-Glühen), 1024 x 1024, unverändert aus dem Paket
- `Effekte/` – FX_Glitzer, FX_Glut, FX_Flamme (Partikelbilder)
- `Drachengold_Studio.lua` – legt die Texturen im Place an

## Einbauen (einmal pro Place)
1. Studio → Asset Manager → Bulk Import: die 5 Bilder aus `Texturen/` und die 3 aus `Effekte/` hochladen.
2. In `Drachengold_Studio.lua` oben bei `IDS` die 8 Nummern eintragen (Rechtsklick auf das Bild → Copy ID).
3. Skript komplett in die Command Bar (View → Command Bar) einfügen, Enter – nicht während Play.
   Ergebnis: `ReplicatedStorage › Assets › Weapons › Rifle › Skins › W_Drachengold`.
4. Play → Skin-Shop → Drachengold (1 Münze) kaufen und auf das Sturmgewehr ausrüsten.

Ohne Schritt 1–3 gibt es die Effekte (Glitzer, Glut, Licht, Feuerstoß), aber keine Gold-Textur.
Das `Drachengold_Setup.lua` aus dem Original-Paket NICHT benutzen: es macht jedes Sturmgewehr für alle golden.

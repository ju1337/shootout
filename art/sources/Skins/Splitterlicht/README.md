# Splitterlicht (Test-Skin, Sturmgewehr)

Kristall mit glühenden Energieadern, prismatische Leuchtspur, Kill-Finisher „Kristallbruch“. Effekt-Werte: `Werte.md`
(im Code: `src/shared/SkinStyles.lua`, gebaut von `src/shared/SkinEffects.lua`). Shop: `W_Splitterlicht` in
`src/shared/Cosmetics.lua` (1 Münze, nicht in Kisten).

## Bilder ins Spiel
1. Studio → Asset Manager → Bulk Import: die 5 Bilder aus `Texturen/` und die 8 aus `Effekte/` hochladen.
2. Die 13 IDs (Rechtsklick → Copy ID) in `tools/models/skins.luau` bei `W_Splitterlicht` eintragen, dann
   `lune run tools/models/skins.luau models/Skins/Rifle.rbxmx` und `python3 tools/models/skins_legacy.py models/Skins/Rifle.rbxmx`.
3. Rojo legt sie unter `Assets › Weapons › Rifle › Skins › W_Splitterlicht` ab.

Ohne die Bilder funktioniert der Skin schon (Partikel, Leuchtspur, Finisher mit Roblox-Standardbildern, Waffe nur
violett eingefärbt).

-- Credits (ModuleScript)
-- Fremde Inhalte mit Pflicht zur Namensnennung (CC BY 4.0). Dieselbe Liste steht in CREDITS.md im Repo und auf der
-- Spielseite; im Spiel zeigt sie die Karte CREDITS unten auf der Seite OPTIONEN (SideMenu). Titel, Autoren und Links
-- stammen aus den Quelldateien (art/sources/*.glb, asset.extras) und bleiben unübersetzt.

local Credits = {}

Credits.License = "CC BY 4.0"
Credits.LicenseUrl = "creativecommons.org/licenses/by/4.0"

-- Weapon = Schlüssel in WeaponConfig; Title/Author/Profile wie auf Sketchfab, Source = Seite des Modells
Credits.Models = {
	{ Weapon = "SMG", Title = "low-poly HK MP7 A1", Author = "D_U", Profile = "sketchfab.com/DU1701",
		Source = "https://sketchfab.com/3d-models/low-poly-hk-mp7-a1-4715a09c0d054bdba7c0fbf0929a9878" },
	{ Weapon = "Pistol", Title = "low-poly HK Mark 23 SOCOM", Author = "D_U", Profile = "sketchfab.com/DU1701",
		Source = "https://sketchfab.com/3d-models/low-poly-hk-mark-23-socom-b6426adeae9d45999610453df5a68c43" },
	{ Weapon = "LMG", Title = "low-poly M60 Machine Gun", Author = "D_U", Profile = "sketchfab.com/DU1701",
		Source = "https://sketchfab.com/3d-models/low-poly-m60-machine-gun-9defc3535972489c817c5f47551cbebf" },
	{ Weapon = "Shotgun", Title = "low-poly GEN-12", Author = "D.U.", Profile = "sketchfab.com/D.U.",
		Source = "https://sketchfab.com/3d-models/low-poly-gen-12-5a8e85a2375948498d76d379e915f3bf" },
	{ Weapon = "Revolver", Title = "low-poly Chiappa Rhino", Author = "D.U.", Profile = "sketchfab.com/D.U.",
		Source = "https://sketchfab.com/3d-models/low-poly-chiappa-rhino-dd187489aaca42b2abda9831e76bc94b" },
}

return Credits

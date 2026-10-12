-- DevConfig (ModuleScript)
-- Hilfen fürs Entwickeln, nur in Roblox Studio (RunService:IsStudio()), nie im echten Spiel:
--   StudioBoost: beim Laden des Spielstands Münzen, RAP und Rote-Zone-Punkte mindestens auf diese Werte auffüllen, damit man alles
--   kaufen und testen kann. AllSkins: dazu jeden Skin aus Cosmetics (Waffen, Agenten, Creator, Pass …) einmal besitzen. Nur ohne DataStore-Zugriff (Stand gilt nur für die Sitzung): einen echten, gespeicherten Spielstand füllt es nie auf.

local DevConfig = {}

DevConfig.StudioBoost = true
DevConfig.Coins = 100000
DevConfig.Rap = 100000
DevConfig.RedPoints = 10000
DevConfig.AllSkins = true

return DevConfig

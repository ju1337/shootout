-- DevConfig (ModuleScript)
-- Hilfen fürs Entwickeln, nur in Roblox Studio (RunService:IsStudio()), nie im echten Spiel:
--   StudioBoost: beim Laden des Spielstands Münzen, RAP und Rote-Zone-Punkte mindestens auf diese Werte auffüllen, damit man alles
--   kaufen und testen kann. Achtung: hat Studio Zugriff auf die DataStores, wird das im eigenen Spielstand gespeichert.

local DevConfig = {}

DevConfig.StudioBoost = true
DevConfig.Coins = 100000
DevConfig.Rap = 100000
DevConfig.RedPoints = 10000

return DevConfig

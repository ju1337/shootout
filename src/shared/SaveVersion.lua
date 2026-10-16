-- SaveVersion (ModuleScript)
-- Gemeinsame Versionsnummer der Spielstand-Speicher. Ein Wipe (alle Spieler fangen von vorn an) = Wipe um 1 erhöhen
-- und veröffentlichen: Die Speicher bekommen dann neue Namen ("PlayerData_v2" usw.), die alten bleiben unangetastet
-- in Roblox liegen (zurück = Zahl wieder senken). Betroffen: Spielstände (Fortschritt, Inventar, Lager, Versteck),
-- Bestenlisten, Clans und Markt-Preisverlauf/RAP. NICHT betroffen: Sperren (Bans_v1), Teamränge (StaffRanks_v1),
-- Shop-Angebote (ShopOffers_v1) und Gamepässe (die prüft Roblox selbst).
local SaveVersion = {}

SaveVersion.Wipe = 2

-- Name des Speichers für base, z.B. Name("PlayerData") = "PlayerData_v2"
function SaveVersion.Name(base)
	return base .. "_v" .. SaveVersion.Wipe
end

return SaveVersion

-- TutorialConfig (ModuleScript, Client und Server)
-- Reihenfolge der Schritte des Pflicht-Tutorials (ExtTutorial auf dem Client, Modes/Extinction auf dem Server).
-- Phase "Camp": der Spieler kommt nicht aus der Safe Zone (Server setzt ihn an den Rand zurück, Attribut TutorialLock),
-- bis er beim Schritt "Leave" ist. Texte, Ziele und Prüfungen stehen in ExtTutorial; hier nur, was beide Seiten brauchen.
-- Flags: Aktionen, die der Server selbst sieht (InventoryService.Notify) und dem Client im Attribut TutorialFlags
-- meldet – damit zählt ein Schritt erst, wenn der Spieler es wirklich getan hat.

local TutorialConfig = {}

TutorialConfig.Steps = {
	{ Id = "Kit", Phase = "Camp" },       -- Starter-Kit am Kit-Händler abholen
	{ Id = "Inventory", Phase = "Camp" }, -- Inventar öffnen
	{ Id = "Safe", Phase = "Camp" },      -- Tasche, Schnellleiste, Container erklärt; ein Item in den Container legen
	{ Id = "Equip", Phase = "Camp" },     -- Waffe in die Hand
	{ Id = "Trader", Phase = "Camp" },    -- HÄNDLER: Munition kaufen, Verkaufen erklärt
	{ Id = "Stash", Phase = "Camp" },     -- LAGER öffnen und erklärt
	{ Id = "Market", Phase = "Camp" },    -- SPIELERMARKT (Tauschmarkt): Angebote, Suche, Verkaufen, eigene Angebote
	{ Id = "Leave", Phase = "World" },    -- durch ein Tor hinaus
	{ Id = "Zombie", Phase = "World" },   -- ersten Zombie töten
	{ Id = "Loot", Phase = "World" },     -- Leiche durchsuchen
	{ Id = "Map", Phase = "World" },      -- Karte öffnen
	{ Id = "Redzone", Phase = "World" },  -- rote Zone erklärt
	{ Id = "Return", Phase = "World" },   -- zurück in eine Safe Zone
	{ Id = "Sell", Phase = "World" },     -- Beute am Händler verkaufen oder im Spielermarkt anbieten
	{ Id = "Ready", Phase = "World" },    -- Schluss: Versteck, Regeln
}

-- Server-Ereignisse, die als Flag zählen (InventoryService.Notify)
TutorialConfig.Flags = { Kit = true, Safe = true, Stash = true, Buy = true, Sell = true, MarketList = true, MarketBuy = true }

function TutorialConfig.Index(id)
	for index, step in TutorialConfig.Steps do
		if step.Id == id then
			return index
		end
	end
	return nil
end

-- Muss der Spieler bei diesem Schritt noch im Camp bleiben?
function TutorialConfig.Locked(id)
	local index = TutorialConfig.Index(id)
	return index ~= nil and TutorialConfig.Steps[index].Phase == "Camp"
end

-- Onboarding-Trichter (Telemetry): 1 Beitritt, 2 offene Welt, 3 ... Schritte, danach "fertig"
function TutorialConfig.FunnelStep(index)
	return 2 + index
end
TutorialConfig.FunnelDone = 3 + #TutorialConfig.Steps

return TutorialConfig

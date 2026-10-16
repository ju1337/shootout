-- ZombieOwner (ModuleScript, Server und Client)
-- Zombies pro Spieler (Joel/Julio 2026-10-16): Zombies der offenen Welt, die für einen Spieler spawnen (Umgebung, rote
-- Zone, Schreier-Rufe, Sturm-Wellen, Lager-Alarm), tragen das Attribut ZombieOwnerId = UserId dieses Spielers. Nur er sieht sie (der Client
-- versteckt fremde, siehe ZombieVisibility), nur ihn jagen und schlagen sie, nur er kann sie treffen und ihre Leiche
-- durchsuchen. Stehen mehrere Spieler zusammen, hat jeder so viele wie allein (nicht doppelt und dreifach).
-- Ohne ZombieOwnerId (Bosse, Event-Zombies an Lootdrop/Wrack/Horden-Kiste/Lager, Dungeon-Wellen) sehen und bekämpfen alle sie.

local ZombieOwner = {}

ZombieOwner.Attribute = "ZombieOwnerId"

-- UserId des Besitzers oder nil (gemeinsamer Zombie)
function ZombieOwner.Of(model)
	return model:GetAttribute(ZombieOwner.Attribute)
end

-- Darf player (Player oder nil) diesen Zombie sehen, treffen und von ihm getroffen werden?
-- Gemeinsame Zombies: ja; eigene: nur der Besitzer
function ZombieOwner.CanSee(model, player)
	local owner = model:GetAttribute(ZombieOwner.Attribute)
	return owner == nil or (player ~= nil and player.UserId == owner)
end

-- Zombies (auch Leichen), die player nicht sieht – für Raycast-Filter des Servers (fremde Zombies sind keine Deckung
-- und kein Ziel)
function ZombieOwner.HiddenFrom(player)
	local list = {}
	local folder = workspace:FindFirstChild("Zombies")
	if folder then
		for _, model in folder:GetChildren() do
			if model:IsA("Model") and not ZombieOwner.CanSee(model, player) then
				table.insert(list, model)
			end
		end
	end
	return list
end

return ZombieOwner
